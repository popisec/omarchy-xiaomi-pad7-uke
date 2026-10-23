#!/bin/bash
# flash-l67-gated.sh — L67: BTA readback del DDIC (boot nuevo) sobre base L66 (icc) + dtbo s288 ya en slot a.
# Carga: mismo config k52L66.config (modulos rootfs intactos) + L66 icc revert + dtbo s288 (ya flasheado).
set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")" || exit 1
BOOT=build/bootimg/boot-uke-k52L67.img
DTBO=build/bootimg/s288-boot-dtbo-gpu-display-gpi-i2c-ktz-vci-adsp.img
EB=56e7b1e5a6b328802ae9421a67d82c0df149dc1bc46e40418afbb415580f4d79
ED=02d403c518346bf5a3757c5519eb8ca205f8f75af078cfde2e03d9d49e702dfb
[ "$EB" != "SHA_PENDIENTE" ] || { echo "ABORTADO: sha del boot L67 sin rellenar"; exit 2; }
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
echo "== BTA (L65) — LECTURAS DEL DDIC =="
if [ "$(dmesg | grep -c UKE-L63)" = "0" ]; then
  echo "(sin UKE-L63: el enable no ha corrido; forzando commit con modetest)"
  timeout 25 modetest -M msm-kms -s 36@85:#0 >/dev/null 2>&1; sleep 3
fi
echo "count: $(dmesg | grep -c "UKE-L65:")"
dmesg | grep "UKE-L65:" | head -14
echo
echo "== contexto ==="
echo "UKE-L63: $(dmesg | grep -c UKE-L63) | UKE-L66: $(dmesg | grep -c UKE-L66) | UKE-L37: $(dmesg | grep -c UKE-L37) | L37-pps: $(dmesg | grep -c "L37-pps")"
dmesg | grep -E "UKE-L63|UKE-L62" | head -3
echo
echo "== ADSP / CARGA =="
for r in /sys/class/remoteproc/remoteproc*; do n=$(cat $r/name 2>/dev/null); echo "$n: $(cat $r/state 2>/dev/null)"; done
echo "PDR: $(dmesg | grep -c charger_pd) mencion(es); up: $(dmesg | grep -c "adsp is now up")"
echo "icc-fail (debe ser 0): $(dmesg | grep -c 'failed to acquire interconnect path')"
for f in status voltage_now current_now capacity; do echo "-- bat/$f: $(cat /sys/class/power_supply/qcom-battmgr-bat/$f 2>&1 | head -1)"; done
echo "-- usb/online: $(cat /sys/class/power_supply/qcom-battmgr-usb/online 2>&1 | head -1)"
' 2>&1 | tail -42
echo '== CRITERIO PREFIJADO L65 (ANGULO-DDIC §2 + CRITICA-L67 I1-I3) =='
echo '  0x0A es oraculo de 3 bits: D7=booster, D4=sleep-out latchado, D2/D3=display-on+normal.'
echo '  0x9C (D7+D4+D3+D2) => DDIC DESPIERTO -> queda video (FLUSH/HS_TIMER/DB_MODE | widebus/ACTIVE_H)'
echo '  JUICIO POR LINEA (ret+val) y POR LINK: ret==len => responde; 0<ret<len => parcial (reply valido);'
echo '  ret<=0 => NAK/sordo SOLO si tambien en link0; val sin mirar ret NO decide (val=0 inicial del diff).'
echo '  0x0B=0x00 puede ser NORMAL (MADCTL default); el "0x00/0xFF anomalo" aplica a 0x0A/0x04.'
echo '  Si el DDIC vive solo en link0 (dual-DSI tipico), link1 NAK por diseno: link0 manda.'
echo '  VOID si no hay linea UKE-L63 en el mismo dmesg (uke_panel_inherit) -> re-commit y releer'
