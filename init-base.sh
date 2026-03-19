#!/bin/bash

echo "Pegando a base do Debian"
sudo debootstrap --variant=minbase stable ./rootfs http://deb.debian.org/debian      

echo "Instalando pacotes essenciais na base..."
sudo chroot /rootfs /bin/bash -c "
apt update

apt-mark hold desktop-base
apt install equivs -y

cd  /tmp
equivs-control desktop-base-dummy
cat << 'EOF' > desktop-base-dummy
Section: misc
Priority: optional
Standards-Version: 3.9.2

Package: desktop-base
Version: 999.0
Maintainer: Jefferson <jeff.silvadsouza@gmail.com>
Provides: desktop-theme, gdm3-theme, debian-desktop-base
Architecture: all
Description: Pacote fantasma do Otis OS para remover o desktop-base
 Este pacote substitui o desktop-base original do Debian para
 evitar que ele sobrescreva o Plymouth e os temas do Otis OS.
EOF
equivs-build desktop-base-dummy
dpkg -i desktop-base-dummy_999.0_all.deb

rm desktop-base-dummy_999.0_all.deb 

apt install -y --no-install-recommends \
    linux-image-amd64 \
    linux-headers-amd64 \
    grub-pc-bin \
    grub-efi-amd64-bin \
    live-boot \
    plymouth \
    plymouth-themes \
    zsh \
    curl \
    sudo \
    dkms \
    build-essential \
    git  -y

apt install -y desktop-base-otis
"

sudo chroot /rootfs /bin/bash -c "
useradd -m -s /bin/zsh live
echo "live:live" | chpasswd
echo "live ALL=(ALL) NOPASSWD:ALL" >> /etc/sudo

passwd -d live
passwd root
"