#!/bin/sh
# dump-log.sh — vuelca el log del arranque a la particion `rescue` (sda30).
#
# POR QUE: el painter solo muestra una VENTANA de ~0.5 s del log, y el USB del fork
# aparece a t~3.5 s (el init bindea el UDC) y en Android hasta t~9.6 s. Es decir: la
# pantalla se corta ANTES del momento interesante. Esta particion la monta el recovery
# de Android como /cache y sus ficheros se leen SIN root desde el PC:
#     adb exec-out cat /cache/forklog.txt
# (hallazgo del carril B2, ronda 20)
#
# Se llama varias veces durante el arranque; cada llamada sobrescribe el fichero con
# el estado ACTUAL, y ademas deja copias numeradas para no perder las fases previas.

R=/mnt/rescue
# FIX 14-oct-2026 (post-#620): el nombre sdX cambia entre enumeraciones (13-oct fue sdb30).
# Resolver por PARTLABEL con fallback a los dos candidatos conocidos. (Medido: en el
# sistema vivo el rescue es sda30; en el initramfs de la noche del 13-oct era sdb30.)
P=$(blkid -t PARTLABEL=rescue -o device 2>/dev/null | head -1)
[ -n "$P" ] || P=$(findfs PARTLABEL=rescue 2>/dev/null | head -1)
[ -n "$P" ] || { [ -e /dev/sda30 ] && P=/dev/sda30; }
[ -n "$P" ] || { [ -e /dev/sdb30 ] && P=/dev/sdb30; }
[ -n "$P" ] || P=/dev/sda30
K=25                  # cuantas copias numeradas conservar

[ -d "$R" ] || mkdir -p "$R" 2>/dev/null

# montar si no esta montada (con reintentos cortos: la UFS tarda en enumerar)
i=0
while [ $i -lt 10 ]; do
  grep -q " $R " /proc/mounts 2>/dev/null && break
  [ -e "$P" ] && mount -t ext4 -o rw "$P" "$R" 2>/dev/null
  grep -q " $R " /proc/mounts 2>/dev/null && break
  sleep 1
  i=$((i+1))
done
grep -q " $R " /proc/mounts 2>/dev/null || exit 0

N=$(cut -d. -f1 /proc/uptime 2>/dev/null)
: > "$R/forklog.txt" 2>/dev/null
{
  echo "=== forklog t=${N}s (se actualiza varias veces durante el arranque) ==="
  echo "--- uptime : $(cat /proc/uptime 2>/dev/null)"
  echo "--- cmdline: $(cat /proc/cmdline 2>/dev/null)"
  echo "--- sello  : $(grep -ao 's1[0-9][0-9]-[a-z]*' /proc/device-tree 2>/dev/null | head -1)"
  echo
  echo "########## dmesg ##########"
  dmesg 2>/dev/null
  echo
  echo "########## USB / UDC ##########"
  echo "-- /sys/class/udc:";        ls /sys/class/udc 2>/dev/null
  echo "-- gadget dir:";            ls /sys/kernel/config/usb_gadget/ 2>/dev/null
  echo "-- gadget UDC:";            cat /sys/kernel/config/usb_gadget/*/UDC 2>/dev/null
  echo "-- /dev/ttyGS0:";           ls -la /dev/ttyGS0 2>/dev/null
  echo "-- interfaces de red:";     ls /sys/class/net/ 2>/dev/null
  echo
  echo "########## USB drivers ##########"
  echo "-- dwc3 en /sys/bus/platform/drivers:"
  ls /sys/bus/platform/drivers/ 2>/dev/null | grep -iE "dwc3|phy|repeater" | head -20
  echo "-- dwc3 bindeados:"
  for d in /sys/bus/platform/drivers/*dwc3*/; do ls -l "$d" 2>/dev/null | grep '^l' | head -5; done
  echo
  echo "########## particiones / UFS ##########"
  echo "-- /proc/partitions:";  cat /proc/partitions 2>/dev/null
  echo "-- puntos de montaje:"; cat /proc/mounts 2>/dev/null
  echo
  echo "########## REGULADORES ##########"
  echo "-- con estado (los railes de la PHY son ldob2/ldob4):"
  for r in /sys/class/regulator/*/; do
    n=$(cat "$r/name" 2>/dev/null)
    case "$n" in
      *ldob2*|*ldob4*|*pmxr2230*) printf "   %-34s %s\n" "$n" "$(cat "$r/state" 2>/dev/null)";;
    esac
  done
  echo "-- total reguladores registrados: $(ls /sys/class/regulator/ 2>/dev/null | wc -l)"
} > "$R/forklog.txt" 2>&1

# copia numerada para no perder fases previas
if [ -n "$N" ]; then
  cp "$R/forklog.txt" "$R/forklog-$N.txt" 2>/dev/null
  # podar: dejar solo las K mas recientes
  ls -1t "$R"/forklog-*.txt 2>/dev/null | tail -n +$((K+1)) | while read -r f; do rm -f "$f" 2>/dev/null; done
fi
sync
exit 0
