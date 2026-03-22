#!/bin/bash

ROOTFS="/home/jefferson/Documentos/projects/otis/rootfs"

umount_if_needed() {
  local dst="$1"
  # Verifica se está montado de forma mais rigorosa
  if findmnt -n "$dst" > /dev/null; then
    echo ">> Desmontando $dst..."
    # -l (lazy) evita travar o terminal se o recurso estiver ocupado
    # -f (force) pode ser usado em sistemas de rede, mas aqui o -l é melhor
    sudo umount -l "$dst"
  else
    echo ">> $dst não está montado."
  fi
}

# Desmonte sempre do caminho mais profundo para o mais raso
# Se você montou dev/pts, desmonte-o antes do dev/
umount_if_needed "$ROOTFS/dev/pts"
umount_if_needed "$ROOTFS/dev"
umount_if_needed "$ROOTFS/proc"
umount_if_needed "$ROOTFS/sys"

echo ">> Limpeza concluída."