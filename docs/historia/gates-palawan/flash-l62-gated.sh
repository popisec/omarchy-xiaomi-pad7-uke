#!/bin/bash
# flash-l62-gated.sh — flash L62 (PPS dims) + test automatico (brightness+modetest+PPS).
set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")" || exit 1
IMG=build/bootimg/boot-uke-k52L62.img
EXPECT=d52f59677af04a9d5ab9efcffd0b5d7224b2dcc3fedea1cca621cd519f90f260
ACT=$(sha256sum "$IMG" | cut -d' ' -f1)
[ "$ACT" = "$EXPECT" ] || { echo "SHA MISMATCH: $ACT"; exit 2; }
DEV=$(timeout 15 fastboot devices 2>/dev/null | head -1)
[ -n "$DEV" ] || { echo "ABORTADO: fastboot devices vacio (USB caido o fuera de fastboot)"; exit 3; }
echo "device: $DEV"
for v in battery-voltage current-slot slot-retry-count:a slot-retry-count:b; do
  timeout 15 fastboot getvar "$v" 2>&1 | grep -E "^$v" | head -1
done
timeout 150 fastboot flash boot_a "$IMG" 2>&1 | tail -3
timeout 20 fastboot set_active a 2>&1 | tail -1
timeout 20 fastboot reboot 2>&1 | tail -1
echo '== esperar arranque (~55 s) + test =='
sleep 55
timeout 90 ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=10 root@192.168.42.129 'uptime; echo; echo "== PPS antes del commit =="; dmesg | grep -cE "UKE-L62"; echo; B=/sys/class/backlight/2-0011; echo 4095 > $B/brightness; sleep 1; echo "brightness: $(cat $B/brightness)/4095"; echo "== commit modetest =="; timeout 40 modetest -M msm-kms -s 36@85:#0 2>&1 | tail -2; sleep 2; echo "commits K47: $(dmesg | grep -cE K47-atom-tail)"; echo; echo "== PPS con dims =="; dmesg | grep -E "UKE-L62|UKE-L37" | tail -3' 2>&1
