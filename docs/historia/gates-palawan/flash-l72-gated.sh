#!/bin/bash
# flash-l72-gated.sh — L72: MUNDO 24 LIMPIO (sin el toggle L68) sobre base L71.
# Carga: mismo config k52L71.config (modulos rootfs intactos) + L66 icc + dtbo s288 (ya en slot a).
set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")" || exit 1
BOOT=build/bootimg/boot-uke-k52L72.img
DTBO=build/bootimg/s288-boot-dtbo-gpu-display-gpi-i2c-ktz-vci-adsp.img
EB=SHA_PENDIENTE
ED=02d403c518346bf5a3757c5519eb8ca205f8f75af078cfde2e03d9d49e702dfb
[ "$EB" != "SHA_PENDIENTE" ] || { echo "ABORTADO: sha del boot L72 sin rellenar"; exit 2; }
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
( timeout 22 cat /dev/kmsg > /root/kmsg-l72.txt 2>/dev/null & echo $! > /root/kmsg.pid )
sleep 1
if [ "$(dmesg | grep -c UKE-L63)" = "0" ]; then echo "(enable no corrido: commit con modetest)"; timeout 25 modetest -M msm-kms -s 36@85:#0 >/dev/null 2>&1; fi
sleep 3
kill $(cat /root/kmsg.pid) 2>/dev/null
echo "== mundo 24 (sin toggle L68): UKE-L71 / ACTIVE_H (0x02360020) / byte =="
grep -aE "UKE-L71|L71-intf24|UKE-L68: ACTIVE_H|UKE-L63|UKE-L70" /root/kmsg-l72.txt | head -10
echo "== BTA (solo L65 video-ON; L68-ve NO debe existir) =="
grep -a "UKE-L65:\|L68-ve" /root/kmsg-l72.txt | head -8
echo "== flood S4-DIAG (esperado ~0: toggle retirado) =="
grep -ac S4-DIAG /root/kmsg-l72.txt
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
echo '== CRITERIO PREFIJADO L72 (mundo 24 limpio, sin toggle) =='
echo '  ACTIVE_H 0x02360020 + byte 148,6 + flood ~0 (sin el toggle del L68) + underruns bajos.'
echo '  PASA = CONTENIDO en pantalla (patron/hyprland).'
echo '  FALLA = negro sin flood => el muro no es el flood: siguientes (1 variable): RX-timings PHY,'
echo '     DCS-direct (senemos), o re-medir BTA por link con el sistema vivo.'
echo '  GUARDA: si el flood pasa de 1500 lineas, el script apaga DPMS para no llenar el disco.'
