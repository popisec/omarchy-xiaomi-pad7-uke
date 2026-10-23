#!/bin/bash
# mk-rootfs-l76.sh — rootfs Arch de 8 GiB para userdata (17-oct-2026), SIN root y SIN tocar la tablet.
#
# Base: rootfs v8 (/var/tmp/rootfs-v8-backup-20261007.img, sha bd2b3029…), el ultimo rootfs con SSH
# verificado (sshd + networkd 10-uke-usb.network + authorized_keys = build/rootfs/uke-arch-root.pub;
# el gadget USB y la IP 192.168.42.129 los pone el initramfs del boot.img).
# Se amplia a 8 GiB (la raiz de 4 GiB se lleno con el flood DSI del 15-oct) y se hornea el stack de
# carga actual (CARGA-REVISION-L76-20261017.md §3, las 6 piezas):
#   1. charge/mods-7.2.0-rc2-palawan/*.ko  -> /usr/local/share/uke/mods/   (insmod, sin depmod)
#   2. charge/firmware/adsp*               -> /lib/firmware/               (SIN qcom/)
#   3. charge/adsp-fw.sha256               -> /lib/firmware/adsp-fw.sha256
#   4. charge/uke-adsp-load.sh             -> /usr/local/sbin/ (0755)
#   5. charge/uke-adsp.service             -> /etc/systemd/system/ (sustituye la unidad v8 vieja)
#   6. enable: el symlink multi-user.target.wants/uke-adsp.service ya existe en v8 (se verifica)
# Todo con debugfs -w (dueño root:root y modo fijados con sif). Salida: build/rootfs/rootfs-uke-l76-8g.img
set -euo pipefail
R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
# La imagen base del rootfs NO se publica (lleva dentro el firmware del
# fabricante, el hash de la contrasena de root y las claves SSH de host). Se
# construye en local; antes vivia en /var/tmp/ del autor, por eso el override.
# UKE_ROOTFS_BASE=/ruta/a/rootfs-v8-base.img
BASE=${UKE_ROOTFS_BASE:-$R/build/rootfs/rootfs-v8-base.img}
BASE_SHA=bd2b30294aee99897ca7e86cb4843317cdf545ee08f1694aac1bc3ccf101899c
OUT=$R/build/rootfs/rootfs-uke-l76-8g.img
C=$R/charge
CMDS=$(mktemp)
trap 'rm -f "$CMDS"' EXIT

echo "== base: verificar sha =="
[ "$(sha256sum "$BASE" | cut -d' ' -f1)" = "$BASE_SHA" ] || { echo "ABORTA: la base no es v8"; exit 2; }
echo "== fuentes de carga: verificar manifiesto del firmware =="
(cd "$C/firmware" && sha256sum -c --quiet "$C/adsp-fw.sha256") || { echo "ABORTA: firmware del PC no casa con el manifiesto"; exit 3; }
[ "$(sha256sum "$C/firmware/adsp.b40" | cut -c1-8)" = 42c86837 ] || { echo "ABORTA: adsp.b40 != 42c86837"; exit 3; }
NKO=$(ls "$C"/mods-7.2.0-rc2-palawan/*.ko | wc -l); [ "$NKO" = 10 ] || { echo "ABORTA: $NKO .ko (esperados 10)"; exit 3; }
for k in "$C"/mods-7.2.0-rc2-palawan/*.ko; do
  grep -qa "vermagic=7.2.0-rc2-palawan SMP preempt mod_unload aarch64" "$k" || { echo "ABORTA: vermagic $k"; exit 3; }
done

echo "== copia + ampliacion a 8 GiB =="
cp --sparse=always "$BASE" "$OUT"
e2fsck -fy "$OUT" >/dev/null || true
e2fsck -fn "$OUT" >/dev/null || { echo "ABORTA: la base tiene errores"; exit 4; }
truncate -s 8G "$OUT"
resize2fs "$OUT" >/dev/null

echo "== guion debugfs =="
{
  # firmware: borrar los adsp* viejos de v8 y escribir los 56 actuales + manifiesto
  debugfs -R "ls /lib/firmware" "$OUT" 2>/dev/null | tr -s ' ' '\n' | grep -E '^adsp' | sort -u | while read -r f; do echo "rm /lib/firmware/$f"; done
  echo "rm /lib/firmware/adsp-fw.sha256"
  for f in $(cd "$C/firmware" && ls adsp*); do
    echo "write $C/firmware/$f /lib/firmware/$f"
    echo "sif /lib/firmware/$f uid 0"; echo "sif /lib/firmware/$f gid 0"; echo "sif /lib/firmware/$f mode 0100644"
  done
  echo "write $C/adsp-fw.sha256 /lib/firmware/adsp-fw.sha256"
  echo "sif /lib/firmware/adsp-fw.sha256 uid 0"; echo "sif /lib/firmware/adsp-fw.sha256 gid 0"; echo "sif /lib/firmware/adsp-fw.sha256 mode 0100644"
  # mods
  for d in /usr/local/share /usr/local/share/uke /usr/local/share/uke/mods /usr/local/sbin; do
    echo "mkdir $d"; echo "sif $d uid 0"; echo "sif $d gid 0"; echo "sif $d mode 040755"
  done
  for k in "$C"/mods-7.2.0-rc2-palawan/*.ko; do
    b=$(basename "$k")
    echo "rm /usr/local/share/uke/mods/$b"
    echo "write $k /usr/local/share/uke/mods/$b"
    echo "sif /usr/local/share/uke/mods/$b uid 0"; echo "sif /usr/local/share/uke/mods/$b gid 0"; echo "sif /usr/local/share/uke/mods/$b mode 0100644"
  done
  # qbootctl (build/slot, sha 629434ac…): solo modos de lectura; `-m` reescribe GPT y exige decision + ledger
  echo "mkdir /usr/local/bin"
  echo "rm /usr/local/bin/qbootctl"
  echo "write $R/build/slot/qbootctl-aarch64 /usr/local/bin/qbootctl"
  echo "sif /usr/local/bin/qbootctl uid 0"; echo "sif /usr/local/bin/qbootctl gid 0"; echo "sif /usr/local/bin/qbootctl mode 0100755"
  # loader + unidad
  echo "rm /usr/local/sbin/uke-adsp-load.sh"
  echo "write $C/uke-adsp-load.sh /usr/local/sbin/uke-adsp-load.sh"
  echo "sif /usr/local/sbin/uke-adsp-load.sh uid 0"; echo "sif /usr/local/sbin/uke-adsp-load.sh gid 0"; echo "sif /usr/local/sbin/uke-adsp-load.sh mode 0100755"
  echo "rm /etc/systemd/system/uke-adsp.service"
  echo "write $C/uke-adsp.service /etc/systemd/system/uke-adsp.service"
  echo "sif /etc/systemd/system/uke-adsp.service uid 0"; echo "sif /etc/systemd/system/uke-adsp.service gid 0"; echo "sif /etc/systemd/system/uke-adsp.service mode 0100644"
} > "$CMDS"
debugfs -w -f "$CMDS" "$OUT" >/dev/null 2>"$CMDS.err" || true
grep -vE "^debugfs|File not found by ext2_lookup|already exists|^$" "$CMDS.err" | head -5 || true
rm -f "$CMDS.err"
e2fsck -fn "$OUT" >/dev/null || { echo "ABORTA: e2fsck tras inyectar"; exit 5; }

echo "== verificacion dentro de la imagen =="
D() { debugfs -R "$1" "$OUT" 2>/dev/null; }
X=$(mktemp -d)
D "dump /lib/firmware/adsp.b40 $X/adsp.b40"; [ "$(sha256sum "$X/adsp.b40" | cut -c1-8)" = 42c86837 ] && echo "  OK adsp.b40 42c86837"
D "dump /lib/firmware/adsp-fw.sha256 $X/m"; cmp -s "$X/m" "$C/adsp-fw.sha256" && echo "  OK manifiesto"
NFW=$(D "ls /lib/firmware" | tr -s ' ' '\n' | grep -cE '^adsp\.|^adsp_'); echo "  firmware adsp en imagen: $NFW"
NM=$(D "ls /usr/local/share/uke/mods" | tr -s ' ' '\n' | grep -c '\.ko$'); echo "  .ko en imagen: $NM"
D "dump /usr/local/sbin/uke-adsp-load.sh $X/l"; cmp -s "$X/l" "$C/uke-adsp-load.sh" && echo "  OK loader"
D "dump /etc/systemd/system/uke-adsp.service $X/u"; cmp -s "$X/u" "$C/uke-adsp.service" && echo "  OK unidad"
D "stat /etc/systemd/system/multi-user.target.wants/uke-adsp.service" | grep -c 'Fast link dest: "../uke-adsp.service"' && echo "  OK enable (symlink)"
D "stat /usr/local/sbin/uke-adsp-load.sh" | grep -oE "Mode: +[0-7]+|User: +[0-9]+" | tr '\n' ' '; echo
rm -rf "$X"
sha256sum "$OUT" | tee "$OUT.sha256"
