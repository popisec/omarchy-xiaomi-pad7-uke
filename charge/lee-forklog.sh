#!/bin/bash
# lee-forklog.sh — AUDITOR paso 0, evidencia gratis, 0 escrituras.
#
# POR QUE: el auditor dijo (build/gates/revision/AUDITORIA-METODO-20261013.md §3,
# peldaño 0) que antes de volver a flashear hay que leer el forklog de rescate:
# los boots que mueren antes de USB pueden haber escrito su dmesg alli.
#
# CORRECCION 13-oct-2026 (medida en vivo la noche del 13-oct): la particion de
# rescate es la de PARTLABEL "rescue" y en este kernel es **/dev/sdb30** (128M
# ext4), NO /dev/sda30 (sda es un LUN de 12M con xbl_a..apdp). El nombre sdX
# depende de la enumeracion, asi que ahora se resuelve por PARTLABEL con
# fallback sdb30 -> sda30. (El script viejo buscaba sda30 y fallaba.)
#
# Solo lee. No toca nada. Uso:  bash charge/lee-forklog.sh
set -u
S="ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=8 -o LogLevel=ERROR root@192.168.42.129"

echo "=== $(date +%T) 1. donde esta la particion de rescate ==="
$S 'bash -s' <<'EOS'
RESCUE=$(blkid -t PARTLABEL=rescue -o device 2>/dev/null | head -1)
[ -n "${RESCUE:-}" ] || RESCUE=$(lsblk -rno NAME,PARTLABEL 2>/dev/null | awk '$2=="rescue"{print "/dev/"$1; exit}')
[ -n "${RESCUE:-}" ] || { [ -e /dev/sdb30 ] && RESCUE=/dev/sdb30; }
[ -n "${RESCUE:-}" ] || RESCUE=/dev/sda30
echo "  rescue => ${RESCUE} ($(blkid -s TYPE -o value "${RESCUE}" 2>/dev/null))"
echo
echo "  particiones sd?3x:"
grep -E ' sd[ab]3[0-9] ' /proc/partitions | head -20
echo
echo "  nodo:"
ls -la "${RESCUE}" 2>/dev/null || echo "    ${RESCUE} NO existe como nodo"
echo
echo "  montajes actuales:"
mount 2>/dev/null | grep -iE 'rescue|sd[ab]3[0-9]' || echo "    ninguna de rescate montada"
EOS

echo
echo "=== 2. montar (solo lectura) y listar ==="
$S 'bash -s' <<'EOS'
set -u
RESCUE=$(blkid -t PARTLABEL=rescue -o device 2>/dev/null | head -1)
[ -n "${RESCUE:-}" ] || RESCUE=$(lsblk -rno NAME,PARTLABEL 2>/dev/null | awk '$2=="rescue"{print "/dev/"$1; exit}')
[ -n "${RESCUE:-}" ] || { [ -e /dev/sdb30 ] && RESCUE=/dev/sdb30; }
[ -n "${RESCUE:-}" ] || RESCUE=/dev/sda30
M=/mnt/rescue
mkdir -p "$M"
if mount -o ro,noatime "$RESCUE" "$M" 2>/dev/null; then
  echo "  montada $M (ro)"
else
  echo "  *** no se pudo montar $RESCUE ***"
  lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL 2>/dev/null | head -40
  exit 0
fi
echo
echo "  contenido:"
ls -la --time-style=long-iso "$M" | head -40
echo
echo "  --- busca forklogs / dmesgs por todo el arbol ---"
find "$M" -maxdepth 4 -type f \( -name '*forklog*' -o -name '*dmesg*' -o -name '*.log' \) \
     -printf '%10s  %TY-%Tm-%Td %TH:%TM  %p\n' 2>/dev/null | sort -k3 | head -40
EOS

echo
echo "=== 3. volcar los forklogs ==="
$S 'bash -s' <<'EOS'
set -u
RESCUE=$(blkid -t PARTLABEL=rescue -o device 2>/dev/null | head -1)
[ -n "${RESCUE:-}" ] || RESCUE=$(lsblk -rno NAME,PARTLABEL 2>/dev/null | awk '$2=="rescue"{print "/dev/"$1; exit}')
[ -n "${RESCUE:-}" ] || { [ -e /dev/sdb30 ] && RESCUE=/dev/sdb30; }
[ -n "${RESCUE:-}" ] || RESCUE=/dev/sda30
M=/mnt/rescue
mkdir -p "$M" 2>/dev/null
mount -o ro,noatime "$RESCUE" "$M" 2>/dev/null || { echo "  (no montada, ya se reporto antes)"; exit 0; }
n=0
for f in $(find "$M" -maxdepth 4 -type f \( -name '*forklog*' -o -name '*dmesg*' \) 2>/dev/null | sort); do
  n=$((n+1))
  echo
  echo "───────── $f  ($(stat -c%s "$f") B) ─────────"
  tail -4000 "$f" 2>/dev/null
done
[ "$n" -eq 0 ] && echo "  (ningun forklog encontrado)"
EOS
