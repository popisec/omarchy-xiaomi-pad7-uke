#!/bin/bash
# flash-l66-gated.sh — L66: dtbo s288 (ADSP->mc_virt) + boot L66 (revert L19) → ADSP→PDR→CARGA.
set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")" || exit 1
BOOT=build/bootimg/boot-uke-k52L66.img
DTBO=build/bootimg/s288-boot-dtbo-gpu-display-gpi-i2c-ktz-vci-adsp.img
EB=1aa5a1f1c728146f41d0139d05798a91d04c2a8707caa4c924e1cf2472f5b432
ED=02d403c518346bf5a3757c5519eb8ca205f8f75af078cfde2e03d9d49e702dfb
[ "$(sha256sum "$BOOT" | cut -d' ' -f1)" = "$EB" ] || { echo "BOOT SHA MISMATCH"; exit 2; }
[ "$(sha256sum "$DTBO" | cut -d' ' -f1)" = "$ED" ] || { echo "DTBO SHA MISMATCH"; exit 2; }
DEV=$(timeout 15 fastboot devices 2>/dev/null | head -1)
[ -n "$DEV" ] || { echo "ABORTADO: fastboot devices vacio"; exit 3; }
echo "device: $DEV"
for v in battery-voltage current-slot slot-retry-count:a slot-retry-count:b; do timeout 15 fastboot getvar "$v" 2>&1 | grep -E "^$v" | head -1; done
echo '== flash dtbo_a (s288) =='
timeout 60 fastboot flash dtbo_a "$DTBO" 2>&1 | tail -2
echo '== flash boot_a (L66) =='
timeout 150 fastboot flash boot_a "$BOOT" 2>&1 | tail -2
timeout 20 fastboot set_active a 2>&1 | tail -1
timeout 20 fastboot reboot 2>&1 | tail -1
echo '== esperar arranque (~70 s) + checks de CARGA =='
sleep 70
for i in 1 2 3; do
  UP=$(timeout 12 ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=6 root@192.168.42.129 'uptime' 2>&1 | tail -1)
  case "$UP" in *up*) echo "arrancada: $UP"; break;; esac
  echo "reintento SSH $i: $UP"; sleep 12
done
timeout 90 ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=8 root@192.168.42.129 'echo "== UKE-L66 =="; echo "count: $(dmesg | grep -c UKE-L66)"; echo; echo "== ADSP =="; for r in /sys/class/remoteproc/remoteproc*; do n=$(cat $r/name 2>/dev/null); echo "$n: $(cat $r/state 2>/dev/null)"; done; echo; echo "== dmesg adsp/PDM/carga =="; dmesg | grep -iE "adsp|PDM|charger_pd|servreg|battmgr|is now up" | tail -14; echo; echo "== power_supply =="; for f in status voltage_now current_now; do echo "-- bat/$f: $(cat /sys/class/power_supply/qcom-battmgr-bat/$f 2>&1 | head -1)"; done; echo "-- usb/online: $(cat /sys/class/power_supply/qcom-battmgr-usb/online 2>&1 | head -1)"' 2>&1 | tail -40
