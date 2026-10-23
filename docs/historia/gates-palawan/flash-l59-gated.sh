#!/bin/bash
# flash-l59-gated.sh — flash L59 SOLO si la tablet está visible; aborta en vez de colgarse.
set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")" || exit 1
IMG=build/bootimg/boot-uke-k52L59.img
EXPECT=e3511595de6cb2ae142735402e5b5db0c0dfcdbbe5412f78307aa8686829534e
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
echo '== esperar arranque + checks =='
sleep 55
timeout 60 ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=10 root@192.168.42.129 'uptime; echo "UKE-L37: $(dmesg | grep -c UKE-L37)"; dmesg | grep UKE-L37 | head -2; echo "UKE-L56: $(dmesg | grep -c UKE-L56)"; free -h | head -2' 2>&1
