#!/bin/bash
# flash-l60-gated.sh — flash L60 (carga+PPS+luz+zram) SOLO si la tablet está visible; aborta antes que colgarse.
set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")" || exit 1
IMG=build/bootimg/boot-uke-k52L60.img
EXPECT=09195fb57eba253dddc4a9ec5beb8a4341e25a6d6feb9043f365c410ee4ae608
ACT=$(sha256sum "$IMG" | cut -d' ' -f1)
[ "$ACT" = "$EXPECT" ] || { echo "SHA MISMATCH: $ACT"; exit 2; }
DEV=$(timeout 15 fastboot devices 2>/dev/null | head -1)
[ -n "$DEV" ] || { echo "ABORTADO: fastboot devices vacio (USB caido o fuera de fastboot)"; exit 3; }
echo "device: $DEV"
for v in battery-voltage current-slot slot-retry-count:a slot-retry-count:b; do
  timeout 15 fastboot getvar "$v" 2>&1 | grep -E "^$v" | head -1
done
BV=$(timeout 15 fastboot getvar battery-voltage 2>/dev/null | grep -oE '[0-9]+' | head -1)
[ -n "${BV:-}" ] && [ "$BV" -lt 3300 ] 2>/dev/null && echo "AVISO: bateria muy baja ($BV mV): valora cargar antes de flashear"
timeout 150 fastboot flash boot_a "$IMG" 2>&1 | tail -3
timeout 20 fastboot set_active a 2>&1 | tail -1
timeout 20 fastboot reboot 2>&1 | tail -1
echo '== esperar arranque (~55 s) + checks =='
sleep 55
timeout 60 ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=10 root@192.168.42.129 'uptime; echo; echo "== display DRM =="; ls /dev/dri/ 2>&1; dmesg | grep -E "no IOMMU|kms hw init" | tail -2; echo; echo "== carga: power_supply =="; ls /sys/class/power_supply/ 2>/dev/null; for f in /sys/class/power_supply/*/uevent; do [ -f "$f" ] && echo "-- $f" && grep -E "^(POWER_SUPPLY_STATUS|POWER_SUPPLY_CAPACITY|POWER_SUPPLY_VOLTAGE_NOW|POWER_SUPPLY_CURRENT_NOW|POWER_SUPPLY_ONLINE|POWER_SUPPLY_USB_TYPE|POWER_SUPPLY_CHARGE_TYPE)=" "$f"; done 2>/dev/null | head -30; echo; echo "== dmesg carga =="; dmesg | grep -iE "battmgr|pmic_glink|ucsi" | tail -6; echo; echo "== marcadores =="; echo "UKE-L37: $(dmesg | grep -c UKE-L37) UKE-L56: $(dmesg | grep -c UKE-L56)"' 2>&1
