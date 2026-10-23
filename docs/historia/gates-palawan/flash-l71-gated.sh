#!/bin/bash
# flash-l71-gated.sh — L71: MUNDO 24 COMPLETO (INTF /24 + widebus OFF + byte x30) sobre base L70.
# Carga: mismo config k52L70.config (modulos rootfs intactos) + L66 icc + dtbo s288 (ya en slot a).
set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")" || exit 1
BOOT=build/bootimg/boot-uke-k52L71.img
DTBO=build/bootimg/s288-boot-dtbo-gpu-display-gpi-i2c-ktz-vci-adsp.img
EB=5e13addfe6c11fcd5b580a18f89b1739dc98be23ffcd347b4f90845109ff0d89
ED=02d403c518346bf5a3757c5519eb8ca205f8f75af078cfde2e03d9d49e702dfb
[ "$EB" != "SHA_PENDIENTE" ] || { echo "ABORTADO: sha del boot L71 sin rellenar"; exit 2; }
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
echo '== esperar arranque (~75 s) + checks mundo24 + guarda-flood + CARGA =='
sleep 75
for i in 1 2 3 4; do
  UP=$(timeout 12 ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=6 root@192.168.42.129 'uptime' 2>&1 | tail -1)
  case "$UP" in *up*) echo "arrancada: $UP"; break;; esac
  echo "reintento SSH $i: $UP"; sleep 12
done
timeout 120 ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=8 root@192.168.42.129 'exec 2>&1
echo "== captura VIVA /dev/kmsg (sin eviccion) =="
( timeout 22 cat /dev/kmsg > /root/kmsg-l71.txt 2>/dev/null & echo $! > /root/kmsg.pid )
sleep 1
if [ "$(dmesg | grep -c UKE-L63)" = "0" ]; then echo "(enable no corrido: commit con modetest)"; timeout 25 modetest -M msm-kms -s 36@85:#0 >/dev/null 2>&1; fi
sleep 3
kill $(cat /root/kmsg.pid) 2>/dev/null
echo "== mundo 24: UKE-L71 / ACTIVE_H (esperado 0x02360020) / byte =="
grep -aE "UKE-L71|L71-intf24|UKE-L68: ACTIVE_H|UKE-L63|UKE-L70" /root/kmsg-l71.txt | head -10
echo "== BTA (L65 ON / L68 OFF) =="
grep -a "UKE-L65:\|UKE-L68: DCS\|L68-ve" /root/kmsg-l71.txt | head -10
echo "== flood S4-DIAG (esperado ~0) =="
grep -ac S4-DIAG /root/kmsg-l71.txt
echo "== byte clock / underruns =="
grep -E "pll_byte_clk0|dsi0_phy_pll_out_byteclk" /sys/kernel/debug/clk/clk_summary | head -2
grep -oE "underrun: *[0-9]+" /sys/kernel/debug/dri/1/encoder-0/status 2>/dev/null | head -2
echo "== CARGA =="
for r in /sys/class/remoteproc/remoteproc*; do echo "$(cat $r/name): $(cat $r/state)"; done
echo "PDR: $(dmesg | grep -c charger_pd)"
for f in status current_now; do echo "$f: $(cat /sys/class/power_supply/qcom-battmgr-bat/$f 2>&1 | head -1)"; done
F=$(dmesg | grep -c S4-DIAG)
if [ "$F" -gt 1500 ]; then echo "GUARDA-FLOOD: $F lineas -> DPMS off (protejo disco/sistema)"; timeout 20 modetest -M msm-kms -w 36:DPMS:3 >/dev/null 2>&1; fi
echo "flood final: $(dmesg | grep -c S4-DIAG)"
' 2>&1 | tail -46
echo '== CRITERIO PREFIJADO L71 (mundo 24 del vendor) =='
echo '  ACTIVE_H debe leer 0x02360020 (534) | byte clock ~148,6 MHz | flood S4-DIAG ~0 | underruns bajos.'
echo '  PASA = CONTENIDO en pantalla (patron/hyprland).'
echo '  FALLA = sigue negro => siguiente: handler DSI (ratelimit + clear-before-unmask) para que no haya'
echo '     flujo de errores; luego RX-timings PHY / DCS-direct. Un cambio por ciclo.'
echo '  GUARDA: si el flood pasa de 1500 lineas, el script apaga DPMS para no llenar el disco.'
