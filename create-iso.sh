#!/usr/bin/env bash
set -euo pipefail

# ==============================
# create-iso.sh (build stage)
# From mksquashfs -> ISO (GRUB)
# ==============================

# Config (pode exportar antes de rodar)
ROOTFS="${ROOTFS:-$PWD/rootfs}"
WORKDIR="${WORKDIR:-$PWD/build}"
ISODIR="$WORKDIR/iso"
OUTDIR="${OUTDIR:-$WORKDIR/out}"
ISONAME="${ISONAME:-otis-live.iso}"

# Parâmetros do boot "live"
LIVE_KERNEL_PARAMS="${LIVE_KERNEL_PARAMS:-boot=live components quiet splash}"

# ---------- helpers ----------
need() { command -v "$1" >/dev/null 2>&1 || { echo "Falta: $1"; exit 1; }; }

as_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    sudo "$@"
  else
    "$@"
  fi
}

die() { echo "Erro: $*" >&2; exit 1; }

# ---------- checks ----------
[ -d "$ROOTFS" ] || die "ROOTFS não existe: $ROOTFS"
[ -d "$ROOTFS/boot" ] || die "ROOTFS não tem /boot: $ROOTFS/boot"


sudo chroot "$ROOTFS" /bin/bash -c "
rm -rf /root/.cache
rm -rf /var/cache/apt/archives/*.deb
rm -rf /root/.zsh_history
rm -rf /root/..zcompdump*
rm -rf /root/.bash_history
rm -rf /var/log/*
rm -rf /tmp/*

apt autoremove -y
apt clean
"

echo ">> Forçando tema Plymouth..."

sudo chroot "$ROOTFS" /bin/bash <<'EOF'

ln -sf /usr/share/plymouth/themes/otis-main/otis-main.plymouth \
/usr/share/plymouth/themes/default.plymouth

cat > /etc/plymouth/plymouthd.conf <<PLY
[Daemon]
Theme=otis-main
ShowDelay=0
DeviceTimeout=8
PLY

update-initramfs -u

EOF

need mksquashfs
need grub-mkrescue
need xorriso

# ---------- prepare dirs ----------
echo ">> Limpando diretórios anteriores..."
rm -rf "$ISODIR" "$WORKDIR"
mkdir -p "$ISODIR/boot/grub" "$ISODIR/live" "$OUTDIR"

# ---------- pick kernel/initrd ----------
echo ">> Procurando kernel e initrd..."
VMLINUX="$(ls -1 "$ROOTFS/boot"/vmlinuz-* 2>/dev/null | head -n1 || true)"
INITRD="$(ls -1 "$ROOTFS/boot"/initrd.img-* 2>/dev/null | head -n1 || true)"

[ -n "$VMLINUX" ] || die "Não achei vmlinuz-* em $ROOTFS/boot"
[ -n "$INITRD" ]  || die "Não achei initrd.img-* em $ROOTFS/boot"

echo ">> kernel: $VMLINUX"
echo ">> initrd: $INITRD"

cp -v "$VMLINUX" "$ISODIR/live/vmlinuz"
cp -v "$INITRD"  "$ISODIR/live/initrd"

# ---------- squashfs ----------
# Exclui /boot porque kernel+initrd já vão fora do squashfs
echo ">> Gerando filesystem.squashfs..."
as_root mksquashfs "$ROOTFS" "$ISODIR/live/filesystem.squashfs" \
  -comp xz \
  -noappend

# ---------- validate files ----------
echo ">> Validando estrutura da ISO..."
ls -lh "$ISODIR/live/vmlinuz" || die "vmlinuz não copiado!"
ls -lh "$ISODIR/live/initrd" || die "initrd não copiado!"
ls -lh "$ISODIR/live/filesystem.squashfs" || die "squashfs não criado!"
file "$ISODIR/live/vmlinuz" | grep -qi "kernel\|boot" || die "vmlinuz não parece ser um kernel!"

# ---------- grub config ----------
echo ">> Criando grub.cfg..."
cat > "$ISODIR/boot/grub/grub.cfg" <<'EOF'
set default=0
set timeout=5
set gfxmode=auto

# Carregar módulos ANTES de tentar usar
insmod part_gpt
insmod part_msdos
insmod iso9660
insmod fat
insmod ext2
insmod ntfs
insmod all_video
insmod gfxterm
insmod font
insmod gzio

# Tentar carregar terminal gráfico
if loadfont unicode ; then
  set gfxmode=auto
  insmod gfxterm
  set locale_dir=$prefix/locale
  set lang=pt_BR
  terminal_output gfxterm
fi

# Procurar pelo dispositivo correto
search --no-floppy --set=root --file /live/vmlinuz

menuentry "Live Otis" {
    set gfxpayload=keep
    linux /live/vmlinuz boot=live components quiet splash plymouth.ignore-serial-consoles plymouth.use-simpledrm
    initrd /live/initrd
}

menuentry "Live Otis - Modo Debug" {
    set gfxpayload=keep
    linux /live/vmlinuz boot=live components debug verbose
    initrd /live/initrd
}

menuentry "Live Otis - Safe Mode" {
    set gfxpayload=text
    linux /live/vmlinuz boot=live components nomodeset
    initrd /live/initrd
}
EOF

# ---------- create ISO ----------
ISO_PATH="$OUTDIR/$ISONAME"
echo ">> Criando ISO: $ISO_PATH"

# Criar ISO com grub-mkrescue (modo simples e compatível)
grub-mkrescue \
  -o "$ISO_PATH" \
  "$ISODIR" \
  -volid "OTIS_LIVE" \
  2>&1 | grep -v "^xorriso" || true

# Se a ISO foi criada com sucesso
if [ -f "$ISO_PATH" ]; then
  echo ""
  echo "✅ ISO criada com sucesso!"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "ISO: $ISO_PATH"
  echo "Tamanho: $(du -h "$ISO_PATH" | cut -f1)"
  echo ""
  echo "Estrutura da ISO:"
  echo "  /boot/grub/grub.cfg"
  echo "  /live/vmlinuz ($(du -h "$ISODIR/live/vmlinuz" | cut -f1))"
  echo "  /live/initrd ($(du -h "$ISODIR/live/initrd" | cut -f1))"
  echo "  /live/filesystem.squashfs ($(du -h "$ISODIR/live/filesystem.squashfs" | cut -f1))"
  echo ""
  echo "Para testar com QEMU:"
  echo "  qemu-system-x86_64 -cdrom \"$ISO_PATH\" -m 2G -boot d -enable-kvm"
  echo ""
  echo "Para gravar em USB:"
  echo "  sudo dd if=\"$ISO_PATH\" of=/dev/sdX bs=4M status=progress && sync"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
  die "Falha ao criar ISO"
fi