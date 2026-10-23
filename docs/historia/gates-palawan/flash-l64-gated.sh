#!/bin/bash
# flash-l64-gated.sh — L64 display-only (PPS post-0x29) + test de pantalla.
set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")" || exit 1
IMG=build/bootimg/boot-uke-k52L64.img
EXPECT=84bc0e440b6821a999081c7c8295bdf8f7e0d329e4ab244934f39e4db8cfa231
ACT=$(sha256sum "$IMG" | cut -d' ' -f1)
[ "$ACT" = "$EXPECT" ] || { echo "SHA MISMATCH: $ACT"; exit 2; }
DEV=$(timeout 15 fastboot devices 2>/dev/null | head -1)
[ -n "$DEV" ] || { echo "ABORTADO: fastboot devices vacio"; exit 3; }
echo "device: $DEV"
for v in battery-voltage current-slot slot-retry-count:a slot-retry-count:b; do timeout 15 fastboot getvar "$v" 2>&1 | grep -E "^$v" | head -1; done
timeout 150 fastboot flash boot_a "$IMG" 2>&1 | tail -3
timeout 20 fastboot set_active a 2>&1 | tail -1
timeout 20 fastboot reboot 2>&1 | tail -1
echo '== esperar arranque (~60 s) + test de pantalla =='
sleep 60
for i in 1 2 3; do
  UP=$(timeout 12 ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=6 root@192.168.42.129 'uptime' 2>&1 | tail -1)
  case "$UP" in *up*) echo "arrancada: $UP"; break;; esac
  echo "reintento SSH $i ($UP)"; sleep 12
done
timeout 90 ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=8 root@192.168.42.129 'uptime; echo; echo "== L63 antes del commit =="; echo "UKE-L63: $(dmesg | grep -c UKE-L63)"; B=/sys/class/backlight/2-0011; echo 4095 > $B/brightness; sleep 1; echo "brightness=$(cat $B/brightness)/4095"; echo; echo "== commit modetest =="; timeout 40 modetest -M msm-kms -s 36@85:#0 2>&1 | tail -2; sleep 2; echo "commits K47: $(dmesg | grep -cE K47-atom-tail)"; echo; echo "== PPS/final =="; dmesg | grep -E "UKE-L63|UKE-L62|UKE-L37" | tail -4' 2>&1 | tail -25
