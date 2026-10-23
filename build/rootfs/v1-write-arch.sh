#!/bin/sh
# v1-write-arch.sh — se ejecuta DENTRO de la tablet, en el shell de rescate (BusyBox).
#
# POR QUÉ AQUÍ Y NO ANTES. El intento B2 falló porque escribió el rootfs con `dd` desde el
# sistema que estaba CORRIENDO sobre esa misma partición: el kernel en rw seguía escribiendo
# journal y bitmap encima, y el `sync` final consolidó el superbloque viejo. Aquí, en
# cambio, **`/dev/sda32` no está montado** (`grep sda32 /proc/mounts` → nada): nada lo
# sobreescribe, que es exactamente la condición que faltaba.
#
# Además el flash por fastboot mezcló dos imágenes: `fastboot flash` con una imagen sparse
# NO borra la partición, así que tras Arch(1,2 GB)+Ubuntu(87 MB) quedó un frankenstein con
# metadatos de Ubuntu y sin init. Este dd escribe los 8 GiB completos y deja restos.
#
# GATES: sha256 del .gz antes de descomprimir, y verificación montando en ro al final.
GZ=http://192.168.42.1:8000/arch-rootfs.img.gz
SHA=bca709a275c1c23c0b7bed3789e63be1ab04f19b0401b5ec3cc5f53edca5e112
DEV=/dev/sda32
LOG=/mnt/rescue/v1-write.log
exec >>"$LOG" 2>&1
echo "=== $(date) inicio ==="
echo "--- GATE 1: sda32 NO debe estar montado ---"
grep -q "$DEV" /proc/mounts && { echo "ABORT: $DEV esta montado"; exit 1; }
echo "  OK: no montado"
echo "--- GATE 2: tamano de la particion ---"
SZ=$(blockdev --getsize64 $DEV); echo "  $SZ B"
[ "$SZ" -gt 5000000000 ] || { echo "ABORT: particion demasiado pequena"; exit 1; }
echo "--- GATE 3: descarga ---"
wget -O /tmp/arch.gz "$GZ" || { echo "ABORT: descarga fallida"; exit 1; }
echo "  descargado: $(stat -c%s /tmp/arch.gz) B"
echo "--- GATE 4: sha256 ANTES de descomprimir ---"
S=$(sha256sum /tmp/arch.gz | cut -d' ' -f1); echo "  $S"
[ "$S" = "$SHA" ] || { echo "ABORT: sha distinto, no escribo"; exit 1; }
echo "  OK"
echo "--- GATE 5: dd de los 8 GiB (sin nada montado) ---"
zcat /tmp/arch.gz | dd of=$DEV bs=4M conv=fsync
echo "  dd rc=$?"
sync
rm -f /tmp/arch.gz
echo "--- GATE 6: verificacion montando en SOLO LECTURA ---"
mkdir -p /mnt/chk
if mount -t ext4 -o ro,noload $DEV /mnt/chk; then
    echo "  monta: OK"
    echo "  os-release: $(grep PRETTY /mnt/chk/etc/os-release 2>/dev/null)"
    echo "  /sbin/init: $(ls -l /mnt/chk/sbin/init 2>&1)"
    echo "  systemd   : $(ls /mnt/chk/usr/lib/systemd/systemd 2>&1)"
    echo "  sshd      : $(ls /mnt/chk/usr/bin/sshd 2>&1)"
    umount /mnt/chk
else
    echo "  NO MONTA"
fi
sync
echo "=== $(date) fin. Reiniciando para que el init lo vea ==="
echo b > /proc/sysrq-trigger
