#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

ROOTFS="./rootfs"
DISTRO="trixie"
MIRROR="http://deb.debian.org/debian"

echo "Pegando a base do Debian..."

if [ -d "$ROOTFS" ]; then
    read -p "A pasta $ROOTFS já existe. Deseja remover e baixar novamente? [s/N]: " resposta
    resposta=${resposta,,} # minúscula
    if [[ "$resposta" == "s" || "$resposta" == "sim" ]]; then
        ./umount.sh || { echo "Erro ao desmontar pseudo-filesystems antes de remover $ROOTFS"; exit 1; }
        echo "Removendo $ROOTFS..."
        sudo rm -rf "$ROOTFS"
        sudo debootstrap --variant=minbase "$DISTRO" "$ROOTFS" "$MIRROR"
    fi
else
    sudo debootstrap --variant=minbase "$DISTRO" "$ROOTFS" "$MIRROR"
fi

# Montagem de pseudo-filesystems
./mount.sh || { echo "Erro ao montar pseudo-filesystems"; exit 1; }

# Criar diretórios necessários antes de copiar
if [ ! -d "./rootfs/etc/calamares/branding/otis" ]; then
    sudo mkdir -p ./rootfs/etc/calamares/branding/otis
    sudo cp -r ./branding-calamares/* ./rootfs/etc/calamares/branding/otis/
    echo "Branding Otis copiado."
else
    echo "Branding Otis já existe, pulando cópia."
fi

# Criar script temporário para execução dentro do chroot
CHROOT_SCRIPT="$ROOTFS/tmp/setup-otis.sh"
cat > "$CHROOT_SCRIPT" << 'EOF'
#!/bin/bash
set -e

echo 'Atualizando repositórios e instalando ferramentas essenciais...'
apt update

DEBIAN_FRONTEND=noninteractive apt install -y equivs curl sudo build-essential dkms zsh git

echo 'Criando pacote dummy para desktop-base...'
cd /tmp
cat > desktop-base-dummy << 'EOP'
Section: misc
Priority: optional
Standards-Version: 3.9.2
Package: desktop-base
Version: 999.0
Maintainer: Jefferson <jeff.silvadsouza@gmail.com>
Provides: desktop-theme, gdm3-theme, debian-desktop-base
Architecture: all
Description: Pacote fantasma do Otis OS
EOP

equivs-build desktop-base-dummy
# Instalamos com dpkg e depois usamos o apt-mark hold APÓS ele estar instalado
echo '$(ls /tmp/desktop-base*.deb) instalado como desktop-base...'
dpkg -i /tmp/desktop-base*.deb

apt-mark hold desktop-base
apt-mark hold systemsettings

echo 'Configurando repositórios Otis e Debian Trixie...'
cat > /etc/apt/sources.list.d/otis.list << 'EOO'
deb [trusted=yes] https://jefferson-it.github.io/otis-repo/ stable main
EOO

cat > /etc/apt/sources.list << 'EOO'
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
EOO

apt update

echo 'Instalando pacotes principais do Otis OS...'
DEBIAN_FRONTEND=noninteractive apt install -y \
    linux-image-amd64 \
    linux-headers-amd64 \
    grub-efi-amd64 \
    grub-efi-amd64-bin \
    grub-common \
    efibootmgr \
    os-prober \
    live-boot \
    nano \
    iputils-ping \
    squashfs-tools \
    plymouth \
    plymouth-themes \
    desktop-base-otis \
    firmware-linux \
    firmware-linux-nonfree \
    firmware-realtek \
    firmware-iwlwifi \
    firmware-misc-nonfree \
    network-manager \
    network-manager-gnome \
    gtk2-engines-murrine \ 
    gtk2-engines-pixbuf \
    sassc \
    libgtk-3-0 \
    libgtk-4-1 \
    tree \
    adwaita-qt

apt install -y --no-install-recommends calamares calamares-settings-debian

echo 'Removendo pacotes desnecessários...'
apt remove -y firefox yelp malcontent malcontent-gui || true
apt autoremove -y || true

# Scripts Calamares
mkdir -p /usr/share/calamares/scripts
cat > /usr/share/calamares/scripts/remove-live-user.sh << 'EOL'
#!/bin/bash
set -e
echo ">> Ajustando usuários..."
if id live &>/dev/null; then
    deluser --remove-home live || true
    rm -rf /home/live || true
fi
awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd | while read user; do
    usermod -s /usr/bin/zsh "$user"
done
echo ">> Concluido."
EOL

cat > /etc/calamares/modules/packages.conf << 'EOPKG'
backend: apt

operations:
  - remove:
      - 'live-boot'
      - 'live-boot-doc'
      - 'live-boot-initramfs-tools'
      - 'live-tools'
      - 'calamares-settings-debian'
EOPKG

cat > /usr/share/calamares/scripts/remove-calamares.sh << 'EOC'
#!/bin/bash
set -e
apt remove --purge "calamares*" -y || true
apt autoremove -y || true

rm -rf /usr/share/applications/otis-install.desktop
EOC

chmod +x /usr/share/calamares/scripts/remove-live-user.sh
chmod +x /usr/share/calamares/scripts/remove-calamares.sh

# Config Calamares
sed -i '/^passwordRequirements:/,/^[^ ]/c\
passwordRequirements:\
    nonempty: true\
    minLength: 4\
    maxLength: -1
' /etc/calamares/modules/users.conf

sed -i 's/- sources-final/- sources-final\n  - shellprocess/' /etc/calamares/settings.conf

cat > /etc/calamares/modules/welcome.conf << 'EOW'
---
showSupportUrl:         true
showKnownIssuesUrl:     true
showReleaseNotesUrl:    true

requirements:
    requiredStorage:    15
    requiredRam:        1.0
    # Adicionado para mostrar o status da conexão na tela de boas-vindas
    internet:           true 
    check:
        - storage
        - ram
        - power
        - root
        - internet
    # Adicionado para travar o botão "Próximo" se não houver rede
    required:
        - storage
        - ram
        - root
        - internet
EOW

cat > /etc/calamares/modules/shellprocess.conf << 'EOP'
type: shellprocess
name: "Shell process"
chroot: true
script:
  - "/usr/share/calamares/scripts/remove-live-user.sh"
  - "/usr/share/calamares/scripts/remove-calamares.sh"
EOP

# Sistema
cat > /etc/hostname << 'EOH'
otis
EOH

sed -i 's/branding: .*/branding: otis/' /etc/calamares/settings.conf

curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly sh
echo "Instalando LinuxToys..."
curl -fsSL https://linux.toys/install.sh -o /tmp/linuxtoys.sh
sed -i 's/sudo //g' /tmp/linuxtoys.sh
bash /tmp/linuxtoys.sh

dpkg --configure -a

cat > /etc/os-release << 'EOR'
NAME="Otis OS"
VERSION="1.0"
ID=debian
PRETTY_NAME="Otis OS 1.0"
VERSION_ID="1.0"
EOR

cat > /etc/issue << 'EOI'
Welcome to Otis OS 1.0
EOI

cat > /etc/issue.net << 'EOIN'
Welcome to Otis OS 1.0
EOIN

cat > /etc/lsb-release << 'ELR'
DISTRIB_ID=Otis
DISTRIB_RELEASE=1.0
DISTRIB_CODENAME=otis
DISTRIB_DESCRIPTION="Otis OS 1.0"
ELR

# Shell padrão
chsh -s /bin/zsh root || true
sed -i 's|#DSHELL=/bin/bash|DSHELL=/usr/bin/zsh|' /etc/adduser.conf
sed -i 's|SHELL=/bin/sh|SHELL=/usr/bin/zsh|' /etc/default/useradd

# Oh My Zsh
export RUNZSH=no
cd /root

# Verificar se Oh My Zsh já está instalado
if [ ! -d "/root/.oh-my-zsh" ]; then
    echo "Instalando Oh My Zsh..."

    # Instalar Oh My Zsh
    curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | bash

    # Adicionar alias
    echo 'alias c="clear"' >> /root/.zshrc

    # Clonar plugins
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
    git clone https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

    # Adicionar plugins no .zshrc
    sed -i 's/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions)/' /root/.zshrc

    # Copiar para /etc/skel para novos usuários
    cp -r /root/.oh-my-zsh /etc/skel/.oh-my-zsh
    cp /root/.zshrc /etc/skel/.zshrc

    echo "Oh My Zsh instalado com sucesso!"
else
    echo "Oh My Zsh já está instalado. Pulando instalação."
fi

# Usuário para configurar
install_ohmyzsh() {
    local USER_NAME=$1
    local USER_HOME=$(eval echo "~$USER_NAME")

    # Checar se já está instalado
    if [ ! -d "$USER_HOME/.oh-my-zsh" ]; then
        echo "Instalando Oh My Zsh para $USER_NAME..."

        # Rodar instalação como o próprio usuário
        sudo -u "$USER_NAME" bash -c "export RUNZSH=no && curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | bash"

        # Adicionar alias
        echo 'alias c="clear"' >> "$USER_HOME/.zshrc"

        # Clonar plugins
        sudo -u "$USER_NAME" git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-$USER_HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
        sudo -u "$USER_NAME" git clone https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH_CUSTOM:-$USER_HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

        # Adicionar plugins no .zshrc
        sed -i 's/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions)/' "$USER_HOME/.zshrc"

        # Copiar para /etc/skel para novos usuários futuros
        cp -r "$USER_HOME/.oh-my-zsh" /etc/skel/.oh-my-zsh
        cp "$USER_HOME/.zshrc" /etc/skel/.zshrc

        echo "Oh My Zsh configurado para $USER_NAME!"
    else
        echo "Oh My Zsh já instalado para $USER_NAME. Pulando."
    fi
}

# --- Setup Root ---
install_ohmyzsh root

# --- Criar usuário live e adicionar aos grupos ---
USER_NAME="live"
if ! id "$USER_NAME" &>/dev/null; then
    useradd -m -s /bin/zsh "$USER_NAME"
    passwd -d "$USER_NAME"
    usermod -aG sudo,adm,dip,cdrom,plugdev,lpadmin,shadow "$USER_NAME"
    echo "Usuário $USER_NAME criado e adicionado aos grupos."
fi

# --- Setup live ---
install_ohmyzsh "$USER_NAME"

mkdir -p /home/live/.config/autostart
mkdir -p /home/live/Desktop

cat > /home/live/.config/autostart/fix.desktop << 'EOFIX'
[Desktop Entry]
Type=Application
Exec=/usr/local/bin/fix-desktop-launcher.sh
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
Name=Fix Desktop Launcher
Comment=Fix desktop launcher on live session
EOFIX

cat > /usr/local/bin/fix-desktop-launcher.sh << 'EOF_FIX'
#!/bin/bash
FILE="/home/live/Desktop/otis-install.desktop"
if [ -f "$FILE" ]; then
    chmod +x "$FILE"
    gio set "$FILE" metadata::trusted true || true
    echo "Launcher corrigido."
else
    echo "Arquivo não encontrado, pulando..."
fi
EOF_FIX

chmod +x /usr/local/bin/fix-desktop-launcher.sh

# Detectar arquivo .desktop do Calamares
DESKTOP_FILE=""

if [ -f /usr/share/applications/calamares-install-debian.desktop ]; then
    DESKTOP_FILE="/usr/share/applications/calamares-install-debian.desktop"
else
    # fallback: procurar qualquer launcher do calamares
    DESKTOP_FILE=$(find /usr/share/applications -iname "*calamares*.desktop" | head -n 1)
fi

if [ -n "$DESKTOP_FILE" ] && [ -f "$DESKTOP_FILE" ]; then
    echo "Arquivo encontrado: $DESKTOP_FILE"

    sed -i 's|Icon=.*|Icon=otis-install|' "$DESKTOP_FILE"
    sed -i 's|Name=.*|Name=Install Otis OS|' "$DESKTOP_FILE"
    sed -i 's|Exec=.*|Exec=sudo calamares|' "$DESKTOP_FILE"

    mv "$DESKTOP_FILE" /usr/share/applications/otis-install.desktop

    echo "Launcher do Otis criado com sucesso!"
else
    echo "[WARN] Nenhum launcher do Calamares encontrado, pulando..."
fi

cp /usr/share/applications/otis-install.desktop /home/live/Desktop/otis-install.desktop

chown live:live /home/live/Desktop/otis-install.desktop
chmod +x /home/live/Desktop/otis-install.desktop

grep -q '^Defaults\s\+pwfeedback' /etc/sudoers || sed -i '/^Defaults/ a Defaults        pwfeedback' /etc/sudoers

# --- Configuração de Auto-login no GDM3 ---
echo "Configurando GDM3 para login automático do usuário live..."
mkdir -p /etc/gdm3/
cat > /etc/gdm3/daemon.conf << 'EOGDM'
[daemon]
# Habilitando o login automático
AutomaticLoginEnable=true
AutomaticLogin=live

# Caso o login automático falhe, permite o login agendado
TimedLoginEnable=true
TimedLogin=live
TimedLoginDelay=0
EOGDM

# Limpeza
rm -rf /root/.cache /var/cache/apt/archives/*.deb /root/.zsh_history /root/..zcompdump* /root/.bash_history /var/log/* /tmp/*

# Definir senha root automática
echo "root:root" | chpasswd

echo "root:otis123" | chpasswd  # Use uma senha clara para testes

apt autoremove -y || true
apt clean

EOF

# Executar script dentro do chroot
sudo chmod +x "$CHROOT_SCRIPT"
sudo chroot "$ROOTFS" /bin/bash /tmp/setup-otis.sh

# Desmontagem de pseudo-filesystems
./umount.sh || { echo 'Erro ao desmontar pseudo-filesystems'; exit 1; }

echo "Base Otis OS pronta!"