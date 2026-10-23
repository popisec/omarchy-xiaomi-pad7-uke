#!/bin/bash
# flash-l63-gated.sh — flash L63 (PPS post-0x29 + carga glink/ucsi) + test doble.
set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")" || exit 1
IMG=build/bootimg/boot-uke-k52L63.img
EXPECT=1d7b440f901d98a6f659c2cdde81b7370364f357804b88f34181068a244ee109
ACT=$(sha256sum "$IMG" | cut -d' ' -f1)
[ "$ACT" = "$EXPECT" ] || { echo "SHA MISMATCH: $ACT"; exit 2; }
DEV=$(timeout 15 fastboot devices 2>/dev/null | head -1)
[ -n "$DEV" ] || { echo "ABORTADO: fastboot devices vacio"; exit 3; }
echo "device: $DEV"
for v in battery-voltage current-slot slot-retry-count:a slot-retry-count:b; do
  timeout 15 fastboot getvar "$v" 2>&1 | grep -E "^$v" | head -1
done
timeout 150 fastboot flash boot_a "$IMG" 2>&1 | tail -3
timeout 20 fastboot set_active a 2>&1 | tail -1
timeout 20 fastboot reboot 2>&1 | tail -1
echo '== esperar arranque (~55 s) + test doble =='
sleep 55
timeout 90 ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=10 root@192.168.42.129 'uptime; echo; echo "== CARGA =="; ls /sys/class/power_supply/ 2>/dev/null; grep -E "^(POWER_SUPPLY_STATUS|POWER_SUPPLY_CAPACITY|POWER_SUPPLY_VOLTAGE_NOW|POWER_SUPPLY_CURRENT_NOW|POWER_SUPPLY_ONLINE)=" /sys/class/power_supply/*/uevent 2>/dev/null | head -12; dmesg | grep -iE "battmgr|pmic_glink|ucsi" | tail -4; echo; echo "== PPS antes =="; echo "L63: $(dmesg | grep -c UKE-L63)"; B=/sys/class/backlight/2-0011; echo 4095 > $B/brightness; sleep 1; echo "brightness: $(cat $B/brightness)"; echo "== commit modetest =="; timeout 40 modetest -M msm-kms -s 36@85:#0 2>&1 | tail -2; sleep 2; echo "commits: $(dmesg | grep -cE K47-atom-tail)"; echo; echo "== PPS =="; dmesg | grep -E "UKE-L63|UKE-L62|UKE-L37" | tail -4' 2>&1
