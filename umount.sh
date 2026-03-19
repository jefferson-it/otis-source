#!/bin/bash

ROOTFS=/home/jefferson/Documentos/projects/otis/rootfs


umount_if_needed() {
  local dst="$1"

  if mountpoint -q "$dst"; then
    echo ">> desmontando $dst"
    sudo umount "$dst"
  else
    echo ">> $dst não está montado"
  fi
}

umount_if_needed "$ROOTFS/dev"
umount_if_needed "$ROOTFS/proc"
umount_if_needed "$ROOTFS/sys"
