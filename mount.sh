#!/bin/bash

# Configurações
ROOTFS="/home/jefferson/Documentos/projects/otis/rootfs"

# Função para montar com segurança
mount_safe() {
  local src="$1"
  local dst="$2"
  local type="$3"

  # Cria o diretório de destino se não existir
  [ ! -d "$dst" ] && mkdir -p "$dst"

  if ! mountpoint -q "$dst"; then
    echo ">> Montando $dst"
    if [ "$type" == "bind" ]; then
      # --make-private garante que mudanças no chroot NÃO afetem o host
      sudo mount --bind "$src" "$dst"
      sudo mount --make-private "$dst"
    else
      sudo mount -t "$type" "$src" "$dst"
    fi
  else
    echo ">> $dst já está montado"
  fi
}

# 1. Montagens essenciais
# Nota: /dev/pts é crucial para programas que usam terminais (como o apt ou pacman)
mount_safe /dev     "$ROOTFS/dev"     "bind"
mount_safe devpts   "$ROOTFS/dev/pts" "devpts"
mount_safe proc     "$ROOTFS/proc"    "proc"
mount_safe sysfs    "$ROOTFS/sys"     "sysfs"
mount_safe tmpfs    "$ROOTFS/run"     "tmpfs"

# 2. Sincronizar DNS (Resolv.conf)
# Usar -L garante que se o seu resolv.conf for um link simbólico, ele copie o conteúdo real
if [ -f /etc/resolv.conf ]; then
  sudo cp -L /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
  echo ">> resolv.conf atualizado"
fi

echo ">> Ambiente chroot pronto para o Otis Linux."