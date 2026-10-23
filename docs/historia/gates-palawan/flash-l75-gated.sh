#!/bin/bash
# flash-l75-gated.sh — L75: paridad vendor de los 14 TIMING_CTRL de la PHY
# (override en dsi_7nm_phy_enable con la tabla del DTBO
# qcom,mdss-dsi-panel-phy-timings: 00 27 0a 0a 1b 19 0a 0b 0a 02 04 00 20 0f,
# gate fail-closed bitclk 1189188000 + !cphy_mode) sobre el L74 INTACTO
# (L73 composite + L74-A/B hstimer/MISR/FLUSH). Base de la decisión:
# PANEL-REVISION-INV75-PHY-20261017. ÚNICO flash autorizado por el dueño
# (17-oct, pendiente de su orden). Carga: mismo config k52L75.config
# (=k52L74=k52L73, módulos rootfs intactos) + L66 icc + dtbo s288 (ya en slot
# a, SOLO LECTURA: se verifica su sha, nunca se escribe). Única escritura: boot_a.
# Rollback = L74 06a1d9fe / L73 a671d293 / L71 5e13addf.
set -u
set -o pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")" || exit 1
BOOT=build/bootimg/boot-uke-k52L75.img
DTBO=build/bootimg/s288-boot-dtbo-gpu-display-gpi-i2c-ktz-vci-adsp.img
EB=SHA_PENDIENTE
ED=02d403c518346bf5a3757c5519eb8ca205f8f75af078cfde2e03d9d49e702dfb
[ "$EB" != "SHA_PENDIENTE" ] || { echo "ABORTADO: sha del boot L75 sin rellenar (tras el repack)"; exit 2; }
[ "$(sha256sum "$BOOT" | cut -d' ' -f1)" = "$EB" ] || { echo "BOOT SHA MISMATCH"; exit 2; }
[ "$(sha256sum "$DTBO" | cut -d' ' -f1)" = "$ED" ] || { echo "DTBO SHA MISMATCH (s288 debe seguir intacto)"; exit 2; }
DEV=$(timeout 15 fastboot devices 2>/dev/null | head -1)
[ -n "$DEV" ] || { echo "ABORTADO: fastboot devices vacio"; exit 3; }
echo "device: $DEV"
for v in battery-voltage current-slot slot-retry-count:a slot-retry-count:b; do timeout 15 fastboot getvar "$v" 2>&1 | grep -E "^$v" | head -1; done
MV=$(timeout 15 fastboot getvar battery-voltage 2>&1 | grep -oE '[0-9]+' | head -1)
if [ -n "${MV:-}" ] && [ "$MV" -lt 3300 ]; then echo "ABORTADO: bateria $MV mV < 3300 (riesgo de brick)"; exit 4; fi
[ -n "${MV:-}" ] && [ "$MV" -lt 3700 ] && echo "AVISO: bateria $MV mV < gate 3700 (orden explicita del dueno: UN flash)"
# --- Gate slot-retry-count:b (B es el rollback; si <3 no hay red de seguridad) ---
RB=$(timeout 15 fastboot getvar slot-retry-count:b 2>&1 | grep -E '^slot-retry-count:b' | head -1 | grep -oE '[0-9]+$')
echo "slot-retry-count:b = ${RB:-?}"
if [ -z "${RB:-}" ] || [ "$RB" -lt 3 ]; then
  if [ "${FORCE_RETRY:-0}" = "1" ]; then echo "AVISO: retry-count:b '${RB:-?}' <3 pero FORCE_RETRY=1 (decision explicita)"
  else echo "ABORTADO: slot-retry-count:b='${RB:-?}' < 3 (FORCE_RETRY=1 para forzar)"; exit 5; fi
fi
# --- Gate lector ACM unico armado (regla: nunca arrancar sin lector) ---
LPID=/var/tmp/uke-consola-lector.pid
if ! { [ -f "$LPID" ] && kill -0 "$(cat "$LPID")" 2>/dev/null; }; then
  echo "ABORTADO: lector ACM no armado (build/gates/uke-consola-lector.sh; log /var/tmp/uke-sesion-console.log)"; exit 6
fi
NR=$(pgrep -fc 'cat /dev/ttyACM' || true)
if [ "${NR:-0}" -gt 1 ]; then echo "ABORTADO: $NR 'cat /dev/ttyACM*' vivos (el lector debe ser UNICO)"; exit 6; fi
echo "lector ACM vivo (pid $(cat "$LPID")), cat activos: ${NR:-0}"
echo '== UNICA ESCRITURA: boot_a (dtbo s288 ya esta en slot a, no se toca) =='
timeout 150 fastboot flash boot_a "$BOOT" 2>&1 | tail -2
FRC=${PIPESTATUS[0]}
if [ "$FRC" -ne 0 ]; then echo "ABORTADO: fastboot flash boot_a rc=$FRC; NO set_active ni reboot"; exit 7; fi
# fastboot NO lee particiones: la relectura boot_a vs imagen va post-arranque (bloque ssh, ledger #241).
timeout 20 fastboot set_active a 2>&1 | tail -1
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "ABORTADO: set_active a fallo; NO reboot"; exit 7; }
timeout 20 fastboot reboot 2>&1 | tail -1
echo '== esperar arranque (~75 s) + captura kmsg + gates L75 + guarda-flood + CARGA =='
sleep 75
for i in 1 2 3 4; do
  UP=$(timeout 12 ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=6 root@192.168.42.129 'uptime' 2>&1 | tail -1)
  case "$UP" in *up*) echo "arrancada: $UP"; break;; esac
  echo "reintento SSH $i: $UP"; sleep 12
done
echo "== RELECTURA boot_a post-arranque (ledger #241: hash al tamano EXACTO de la imagen) =="
IMGSZ=$(stat -c%s "$BOOT")
RBSHA=$(timeout 60 ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=8 root@192.168.42.129 "head -c $IMGSZ /dev/disk/by-partlabel/boot_a | sha256sum" 2>/dev/null | cut -d' ' -f1)
if [ "$RBSHA" = "$EB" ]; then echo "  OK  boot_a releido == imagen ($IMGSZ B, $RBSHA)"
else echo "  *** RELECTURA NO COINCIDE o no disponible: '${RBSHA:-vacio}' != $EB (REVISAR antes de seguir) ***"; fi
timeout 120 ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=8 root@192.168.42.129 'exec 2>&1
echo "== captura VIVA /dev/kmsg (sin eviccion) =="
( timeout 22 cat /dev/kmsg > /root/kmsg-l75.txt 2>/dev/null & echo $! > /root/kmsg.pid )
sleep 1
if [ "$(dmesg | grep -c UKE-L63)" = "0" ]; then echo "(enable no corrido: commit con modetest)"; timeout 25 modetest -M msm-kms -s 36@85:#0 >/dev/null 2>&1; fi
sleep 3
kill $(cat /root/kmsg.pid) 2>/dev/null
echo "== GATE-0 continuidad L74 (todo lo anterior INTACTO): hstimer/MISR/FLUSH + PPS OEM + mundo 24 + ceil + freno =="
grep -a "UKE-L74" /root/kmsg-l75.txt | head -3
grep -aE "UKE-L68: ACTIVE_H" /root/kmsg-l75.txt | head -2
grep -ac "L72-intf24ceil" /root/kmsg-l75.txt
grep -a "UKE-L73" /root/kmsg-l75.txt | head -2
echo "== GATE-1 L75: marcador UKE-L75 con was/now; NOW = tabla vendor 00 27 0a 0a 1b 19 0a 0b 0a 02 04 00 20 0f =="
grep -a "UKE-L75" /root/kmsg-l75.txt | head -4
echo "  (x2 esperado: PHY0 ae95000 + PHY1 ae97000, un marcador por link; el print va ANTES de los writels)"
grep -ac "UKE-L75" /root/kmsg-l75.txt
echo "  lineas con la tabla vendor en NOW:"
grep -ac "now 00 27 0a 0a 1b 19 0a 0b 0a 02 04 00 20 0f" /root/kmsg-l75.txt
echo "== GATE-2 S4-DIAG (L74-B, con MISR= y TO=): sanity del host tras el override =="
grep -a "S4-DIAG: wait for video done" /root/kmsg-l75.txt | head -5
echo "== GATE-3 flood + underruns: el criterio nº1 es que el burst DESAPAREZCA =="
echo "S4-DIAG total (dmesg completo): $(dmesg | grep -c S4-DIAG)"
echo "S4-DIAG en la ventana de captura: $(grep -ac S4-DIAG /root/kmsg-l75.txt)"
grep -a "flood frenado" /root/kmsg-l75.txt | head -2
grep -oE "underrun: *[0-9]+" /sys/kernel/debug/dri/1/encoder-0/status 2>/dev/null | head -2
grep -oE "underrun: *[0-9]+" /sys/kernel/debug/dri/1/encoder-1/status 2>/dev/null | head -2
echo "== CARGA =="
for r in /sys/class/remoteproc/remoteproc*; do echo "$(cat $r/name): $(cat $r/state)"; done
echo "PDR: $(dmesg | grep -c charger_pd)"
for f in status current_now; do echo "$f: $(cat /sys/class/power_supply/qcom-battmgr-bat/$f 2>&1 | head -1)"; done
F=$(dmesg | grep -c S4-DIAG)
if [ "$F" -gt 1500 ]; then echo "GUARDA-FLOOD: $F lineas -> DPMS off (protejo disco/sistema)"; timeout 20 modetest -M msm-kms -w 36:DPMS:3 >/dev/null 2>&1; fi
echo "flood final: $(dmesg | grep -c S4-DIAG)"
' 2>&1 | tail -60
echo '== CRITERIO PREFIJADO L75 (PANEL-REVISION-INV75-PHY-20261017 §4d) =='
echo '  GATE-1: UKE-L75 x2 (PHY0+PHY1) y en NOW la tabla vendor COMPLETA'
echo '     00 27 0a 0a 1b 19 0a 0b 0a 02 04 00 20 0f (was = calc ui=840:'
echo '     00 27 0a 0c 27 25 0a 0b 07 02 04 00 23 1a; delta 6 campos).'
echo '     Marcador ausente o tasa != 1189188000 Hz => gate fallido (clk_req).'
echo '  CRITERIO Nº1 (a): el burst FIFO del arranque (17 eventos/250 ms, ambos links,'
echo '     latch dddd1019, "flood frenado" desde L73) DEBE DESAPARECER: S4-DIAG total ~0.'
echo '  (b): underruns ~0 en encoder-0/1.'
echo '  (c): PASA = CONTENIDO en pantalla (patron/hyprland).'
echo '  Matriz de salida:'
echo '    flood 0 + contenido  => cerrado (la PHY era el eslabon).'
echo '    flood 0 + NEGRO      => paridad PHY 14/14 conseguida pero no era el eslabon:'
echo '                            rama restante = TDDI tactil (L76 = port tactil SPI; NVT-ts).'
echo '    flood persistente    => el flood no nacia de la PHY: descartado definitivo (dato duro).'
echo '  No cambia por este parche: init err, TIMEOUT_STATUS/MISR del L74-B (no deben EMPEORAR).'
echo '  GUARDA: >1500 lineas S4-DIAG => DPMS off automatico (el freno B2-A ya acota el log).'
