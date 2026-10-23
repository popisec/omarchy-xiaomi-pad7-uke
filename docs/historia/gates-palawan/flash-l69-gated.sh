#!/bin/bash
# flash-l69-gated.sh — L69: FIX divisor INTF DSC /24 (pantalla) sobre base L68 (carga intacta).
# Carga: mismo config k52L68.config (modulos rootfs intactos) + L66 icc + dtbo s288 (ya en slot a).
set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")" || exit 1
BOOT=build/bootimg/boot-uke-k52L69.img
DTBO=build/bootimg/s288-boot-dtbo-gpu-display-gpi-i2c-ktz-vci-adsp.img
EB=a986950fb08c0fa0c6ac5e0ddc5c9c37802a5c198e6477dc8bfab31ad398c6ab
ED=02d403c518346bf5a3757c5519eb8ca205f8f75af078cfde2e03d9d49e702dfb
[ "$EB" != "SHA_PENDIENTE" ] || { echo "ABORTADO: sha del boot L69 sin rellenar"; exit 2; }
[ "$(sha256sum "$BOOT" | cut -d' ' -f1)" = "$EB" ] || { echo "BOOT SHA MISMATCH"; exit 2; }
[ "$(sha256sum "$DTBO" | cut -d' ' -f1)" = "$ED" ] || { echo "DTBO SHA MISMATCH"; exit 2; }
DEV=$(timeout 15 fastboot devices 2>/dev/null | head -1)
[ -n "$DEV" ] || { echo "ABORTADO: fastboot devices vacio"; exit 3; }
echo "device: $DEV"
for v in battery-voltage current-slot slot-retry-count:a slot-retry-count:b; do timeout 15 fastboot getvar "$v" 2>&1 | grep -E "^$v" | head -1; done
MV=$(timeout 15 fastboot getvar battery-voltage 2>&1 | grep -oE '[0-9]+' | head -1)
if [ -n "${MV:-}" ] && [ "$MV" -lt 3300 ]; then echo "ABORTADO: bateria $MV mV < 3300 (riesgo de brick)"; exit 4; fi
[ -n "${MV:-}" ] && [ "$MV" -lt 3700 ] && echo "AVISO: bateria $MV mV < gate 3700 (orden explicita del dueno: flashear igual)"
echo '== SOLO boot_a (1 escritura; dtbo s288 ya esta en slot a) =='
timeout 150 fastboot flash boot_a "$BOOT" 2>&1 | tail -2
timeout 20 fastboot set_active a 2>&1 | tail -1
timeout 20 fastboot reboot 2>&1 | tail -1
echo '== esperar arranque (~75 s) + checks BTA + CARGA =='
sleep 75
for i in 1 2 3 4; do
  UP=$(timeout 12 ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=6 root@192.168.42.129 'uptime' 2>&1 | tail -1)
  case "$UP" in *up*) echo "arrancada: $UP"; break;; esac
  echo "reintento SSH $i: $UP"; sleep 12
done
timeout 90 ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=8 root@192.168.42.129 '
echo "== FIX /24 — underruns INTF (criterio: no deben crecer; ideal 0) =="
grep -o "underrun: *[0-9]*" /sys/kernel/debug/dri/1/encoder-0/status 2>/dev/null | head -4
echo "vsync/frames: $(grep -o "vsync: *[0-9]*" /sys/kernel/debug/dri/1/encoder-0/status 2>/dev/null | head -2 | tr '\n' ' ')"
echo
echo "== BTA: control ON (L65) vs OFF (L68) =="
if [ "$(dmesg | grep -c UKE-L63)" = "0" ]; then
  echo "(sin UKE-L63: el enable no ha corrido; forzando commit con modetest)"
  timeout 25 modetest -M msm-kms -s 36@85:#0 >/dev/null 2>&1; sleep 3
fi
echo "L65 (video ON)  count: $(dmesg | grep -c "UKE-L65:")"
dmesg | grep "UKE-L65:" | head -12
echo "L68 (video OFF) count: $(dmesg | grep -c "UKE-L68: DCS")"
dmesg | grep "UKE-L68:" | head -16
echo "ACTIVE_H/widebus: $(dmesg | grep "UKE-L68: ACTIVE_H" | tail -1)"
echo
echo "== contexto ==="
echo "UKE-L63: $(dmesg | grep -c UKE-L63) | UKE-L66: $(dmesg | grep -c UKE-L66) | UKE-L37: $(dmesg | grep -c UKE-L37) | L37-pps: $(dmesg | grep -c "L37-pps")"
dmesg | grep -E "UKE-L63|UKE-L62" | head -3
echo
echo "== ADSP / CARGA =="
for r in /sys/class/remoteproc/remoteproc*; do n=$(cat $r/name 2>/dev/null); echo "$n: $(cat $r/state 2>/dev/null)"; done
echo "PDR: $(dmesg | grep -c charger_pd) mencion(es); up: $(dmesg | grep -c "adsp is now up")"
echo "icc-fail (debe ser 0): $(dmesg | grep -c "failed to acquire interconnect path")"
for f in status voltage_now current_now capacity; do echo "-- bat/$f: $(cat /sys/class/power_supply/qcom-battmgr-bat/$f 2>&1 | head -1)"; done
echo "-- usb/online: $(cat /sys/class/power_supply/qcom-battmgr-usb/online 2>&1 | head -1)"
' 2>&1 | tail -42
echo '== CRITERIO PREFIJADO L69 (EXTERNO-DSC-NEGRO §1) =='
echo '  FIX: divisor INTF DSC /24 (antes /30 con bpc=10 => FIFO errors; medido underrun 19 en intf1/2).'
echo '  PASA = CONTENIDO visible en pantalla (test pattern/hyprland) + underrun ~0 sin crecer.'
echo '  FALLA = sigue negro con luz => siguiente candidato: byte-clock DSC x30 (hunk senemos/linuxgamer'
echo '     => 148,6 MHz; diff propio pendiente, l70-byteclock) — un cambio por ciclo.'
echo '  Extra: UKE-L65/L68 (BTA ON/OFF) y ACTIVE_H quedan en dmesg para el análisis.'
echo '  Carga: ADSP/PDR/Charging deben seguir OK (misma config/modulos).'
