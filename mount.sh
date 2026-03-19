#!/bin/bash

ROOTFS=/home/jefferson/Documentos/projects/otis/rootfs

mount_if_needed() {
  local src="$1"
  local dst="$2"

  if ! mountpoint -q "$dst"; then
    echo ">> montando $dst"
    sudo mount --bind "$src" "$dst"
  else
    echo ">> $dst já está montado"
  fi
}

mount_if_needed /dev  "$ROOTFS/dev"
mount_if_needed /proc "$ROOTFS/proc"
mount_if_needed /sys  "$ROOTFS/sys"

sudo cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
