#!/bin/bash
# flash-l73-gated.sh — L73: composite panel (L72 + FIX-1 quirk PPS OEM + B2-A freno + B2-C ceil) sobre base L71.
# ÚNICO flash autorizado por el dueño (15-oct). Carga: mismo config k52L73.config (=k52L72, módulos
# rootfs intactos) + L66 icc + dtbo s288 (ya en slot a, SIN escritura).
# Base de la decisión: PANEL-REVISION-B1 (PPS difiere del OEM en 5 bytes; el init 0x91 del panel
# certifica flb=13) + B2 (flood = re-arm sin freno; ceil INTF) + B3/B4 (PHY y pclk descartados).
set -u
set -o pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")" || exit 1
BOOT=build/bootimg/boot-uke-k52L73.img
DTBO=build/bootimg/s288-boot-dtbo-gpu-display-gpi-i2c-ktz-vci-adsp.img
EB=a671d293f738a6325bd18cb4a63a17a52c449b0af2e53adeb9700256960bd37d
ED=02d403c518346bf5a3757c5519eb8ca205f8f75af078cfde2e03d9d49e702dfb
[ "$EB" != "SHA_PENDIENTE" ] || { echo "ABORTADO: sha del boot L73 sin rellenar"; exit 2; }
[ "$(sha256sum "$BOOT" | cut -d' ' -f1)" = "$EB" ] || { echo "BOOT SHA MISMATCH"; exit 2; }
[ "$(sha256sum "$DTBO" | cut -d' ' -f1)" = "$ED" ] || { echo "DTBO SHA MISMATCH (s288 debe seguir intacto)"; exit 2; }
DEV=$(timeout 15 fastboot devices 2>/dev/null | head -1)
[ -n "$DEV" ] || { echo "ABORTADO: fastboot devices vacio"; exit 3; }
echo "device: $DEV"
for v in battery-voltage current-slot slot-retry-count:a slot-retry-count:b; do timeout 15 fastboot getvar "$v" 2>&1 | grep -E "^$v" | head -1; done
MV=$(timeout 15 fastboot getvar battery-voltage 2>&1 | grep -oE '[0-9]+' | head -1)
if [ -n "${MV:-}" ] && [ "$MV" -lt 3300 ]; then echo "ABORTADO: bateria $MV mV < 3300 (riesgo de brick)"; exit 4; fi
[ -n "${MV:-}" ] && [ "$MV" -lt 3700 ] && echo "AVISO: bateria $MV mV < gate 3700 (orden explicita del dueno: UN flash)"
echo '== UNICA ESCRITURA: boot_a (dtbo s288 ya esta en slot a, no se toca) =='
timeout 150 fastboot flash boot_a "$BOOT" 2>&1 | tail -2
FRC=${PIPESTATUS[0]}
if [ "$FRC" -ne 0 ]; then echo "ABORTADO: fastboot flash boot_a rc=$FRC; NO set_active ni reboot"; exit 7; fi
timeout 20 fastboot set_active a 2>&1 | tail -1
timeout 20 fastboot reboot 2>&1 | tail -1
echo '== esperar arranque (~75 s) + captura kmsg + gates L73 + guarda-flood + CARGA =='
sleep 75
for i in 1 2 3 4; do
  UP=$(timeout 12 ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=6 root@192.168.42.129 'uptime' 2>&1 | tail -1)
  case "$UP" in *up*) echo "arrancada: $UP"; break;; esac
  echo "reintento SSH $i: $UP"; sleep 12
done
timeout 120 ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=8 root@192.168.42.129 'exec 2>&1
echo "== captura VIVA /dev/kmsg (sin eviccion) =="
( timeout 22 cat /dev/kmsg > /root/kmsg-l73.txt 2>/dev/null & echo $! > /root/kmsg.pid )
sleep 1
if [ "$(dmesg | grep -c UKE-L63)" = "0" ]; then echo "(enable no corrido: commit con modetest)"; timeout 25 modetest -M msm-kms -s 36@85:#0 >/dev/null 2>&1; fi
sleep 3
kill $(cat /root/kmsg.pid) 2>/dev/null
echo "== GATE-1 PPS OEM (B1): esperado UKE-L73: PPS[19]=B2 [23]=9F [27]=0D [29]=86 [58]=02 =="
grep -a "UKE-L73" /root/kmsg-l73.txt | head -3
echo "== GATE-2 mundo 24 intacto: UKE-L71 / ACTIVE_H (0x02360020) / byte 148,6 =="
grep -aE "UKE-L71|UKE-L68: ACTIVE_H|UKE-L63|UKE-L70" /root/kmsg-l73.txt | head -8
grep -E "pll_byte_clk0|dsi0_phy_pll_out_byteclk" /sys/kernel/debug/clk/clk_summary | head -2
echo "== GATE-3 ceil INTF (B2-C): L72-intf24ceil x1, L71-intf24 x0 =="
grep -ac "L72-intf24ceil" /root/kmsg-l73.txt; grep -ac "L71-intf24" /root/kmsg-l73.txt
echo "== GATE-4 flood (B2-A): S4-DIAG acotado; si hay, ver 'flood frenado' y FIFO crudo =="
grep -ac S4-DIAG /root/kmsg-l73.txt; grep -a "flood frenado" /root/kmsg-l73.txt | head -2
grep -oE "underrun: *[0-9]+" /sys/kernel/debug/dri/1/encoder-0/status 2>/dev/null | head -2
echo "== CARGA =="
for r in /sys/class/remoteproc/remoteproc*; do echo "$(cat $r/name): $(cat $r/state)"; done
echo "PDR: $(dmesg | grep -c charger_pd)"
for f in status current_now; do echo "$f: $(cat /sys/class/power_supply/qcom-battmgr-bat/$f 2>&1 | head -1)"; done
F=$(dmesg | grep -c S4-DIAG)
if [ "$F" -gt 1500 ]; then echo "GUARDA-FLOOD: $F lineas -> DPMS off (protejo disco/sistema)"; timeout 20 modetest -M msm-kms -w 36:DPMS:3 >/dev/null 2>&1; fi
echo "flood final: $(dmesg | grep -c S4-DIAG)"
' 2>&1 | tail -50
echo '== CRITERIO PREFIJADO L73 (composite B1+B2, un solo flash) =='
echo '  GATE-1: UKE-L73 PPS[19]=B2 [23]=9F [27]=0D [29]=86 [58]=02 (el quirk live).'
echo '  GATE-4: flood ~0 (o acotado con "flood frenado" si la condicion vive).'
echo '  PASA = CONTENIDO en pantalla (patron/hyprland).'
echo '  NEGRO con flood 0 y GATE-1 verde => rama PPS CERRADA de verdad; residuo = PHY-RX/handoff'
echo '     (siguiente ciclo: RX-timings/LP_TIMER, ICC mmss_noc F2, sin gasto de este flash).'
echo '  GARBAGE/parcial => RC desemparejado en otro campo (second_line/native-422 ya a 0).'
echo '  GUARDA: >1500 lineas S4-DIAG => DPMS off automatico (el freno B2-A ya acota el log).'
