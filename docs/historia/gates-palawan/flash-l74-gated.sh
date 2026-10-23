#!/bin/bash
# flash-l74-gated.sh — L74: paridad vendor de la ventana de timing (HS_TIMER+MISR+FLUSH, INV-HSTIMER)
# sobre el composite L73 INTACTO (L72 + FIX-1 PPS OEM + B2-A freno + B2-C ceil).
# ÚNICO flash autorizado por el dueño (16-oct, pendiente de su orden). Carga: mismo config
# k52L74.config (=k52L73, módulos rootfs intactos) + L66 icc + dtbo s288 (ya en slot a, SIN escritura).
# Base de la decisión: PANEL-REVISION-INV-HSTIMER-20261016 (M1/M2/M3: únicos writes de vídeo que
# mainline no hace; watchdog HS = único detector HW de burst colgado; MISR = firma de líneas).
# Rollback = L73 a671d293f738... / L71 5e13addf.
set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")" || exit 1
BOOT=build/bootimg/boot-uke-k52L74.img
DTBO=build/bootimg/s288-boot-dtbo-gpu-display-gpi-i2c-ktz-vci-adsp.img
EB=06a1d9fe73b52aae4eceec1ccdc742bd1da338eb48ef72ba168f66be03d0a543
ED=02d403c518346bf5a3757c5519eb8ca205f8f75af078cfde2e03d9d49e702dfb
[ "$EB" != "SHA_PENDIENTE" ] || { echo "ABORTADO: sha del boot L74 sin rellenar (tras el repack)"; exit 2; }
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
timeout 20 fastboot set_active a 2>&1 | tail -1
timeout 20 fastboot reboot 2>&1 | tail -1
echo '== esperar arranque (~75 s) + captura kmsg + gates L74 + guarda-flood + CARGA =='
sleep 75
for i in 1 2 3 4; do
  UP=$(timeout 12 ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=6 root@192.168.42.129 'uptime' 2>&1 | tail -1)
  case "$UP" in *up*) echo "arrancada: $UP"; break;; esac
  echo "reintento SSH $i: $UP"; sleep 12
done
timeout 120 ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=8 root@192.168.42.129 'exec 2>&1
echo "== captura VIVA /dev/kmsg (sin eviccion) =="
( timeout 22 cat /dev/kmsg > /root/kmsg-l74.txt 2>/dev/null & echo $! > /root/kmsg.pid )
sleep 1
if [ "$(dmesg | grep -c UKE-L63)" = "0" ]; then echo "(enable no corrido: commit con modetest)"; timeout 25 modetest -M msm-kms -s 36@85:#0 >/dev/null 2>&1; fi
sleep 3
kill $(cat /root/kmsg.pid) 2>/dev/null
echo "== GATE-0 continuidad L73 (composite intacto): PPS OEM + mundo 24 + ceil + freno =="
grep -a "UKE-L73" /root/kmsg-l74.txt | head -2
grep -aE "UKE-L68: ACTIVE_H" /root/kmsg-l74.txt | head -2
grep -ac "L72-intf24ceil" /root/kmsg-l74.txt
echo "== GATE-1 L74-A: marcador UKE-L74 con readback (DEBE ecoar 0x4bb80/0x10100/0x1) =="
grep -a "UKE-L74" /root/kmsg-l74.txt | head -4
echo "  (x2 esperado: id=0 e id=1, un marcador por link)"
grep -ac "UKE-L74" /root/kmsg-l74.txt
echo "== GATE-2 S4-DIAG: ahora con MISR= y TO=; TIMEOUT_STATUS != 0 => burst colgado =="
grep -a "S4-DIAG: wait for video done" /root/kmsg-l74.txt | head -5
echo "== GATE-3 flood (B2-A): S4-DIAG acotado; si hay, ver flood frenado y FIFO crudo =="
grep -ac S4-DIAG /root/kmsg-l74.txt; grep -a "flood frenado" /root/kmsg-l74.txt | head -2
grep -oE "underrun: *[0-9]+" /sys/kernel/debug/dri/1/encoder-0/status 2>/dev/null | head -2
echo "== CARGA =="
for r in /sys/class/remoteproc/remoteproc*; do echo "$(cat $r/name): $(cat $r/state)"; done
echo "PDR: $(dmesg | grep -c charger_pd)"
for f in status current_now; do echo "$f: $(cat /sys/class/power_supply/qcom-battmgr-bat/$f 2>&1 | head -1)"; done
F=$(dmesg | grep -c S4-DIAG)
if [ "$F" -gt 1500 ]; then echo "GUARDA-FLOOD: $F lineas -> DPMS off (protejo disco/sistema)"; timeout 20 modetest -M msm-kms -w 36:DPMS:3 >/dev/null 2>&1; fi
echo "flood final: $(dmesg | grep -c S4-DIAG)"
' 2>&1 | tail -50
echo '== CRITERIO PREFIJADO L74 (INV-HSTIMER 2026-10-16 + CRITICA-L74 H-2) =='
echo '  GATE-1: UKE-L74 id=0/1 con readback HS_TIMER=0x4bb80 MISR=0x10100 (rd iguales = OBLIGATORIO:'
echo '     eco distinto => mapa de offsets mal => ABORTAR interpretacion). FLUSH (rd ...) es'
echo '     INFORMATIVO: el vendor jamas lo lee y un no-eco es esperable, no invalida el mapa.'
echo '     Si el S4-DIAG trae MCTRL=0 con el marcador armado => el sw_reset desarmo la unidad'
echo '     MISR (H-1) => el dato MISR de esa linea no cuenta.'
echo '  GATE-2 (por linea S4-DIAG):'
echo '    - TO=... != 0 en ALGUNA linea => burst HS colgado >=1,29 ms CONFIRMADO => L75 = PHY.'
echo '    - MISR=... != 0 => el host empuja VIDEO REAL hacia el DDIC => L75 = 14 TIMING_CTRL RX'
echo '      de la PHY del DT (candidata nº1 historica).'
echo '    - MISR=... == 0 con BUSY=1 => el motor DSI no recibe nada del INTF => L75 = feed/ICC'
echo '      (DPU/INTF-side; ahi si, F2/F4 ICC como siguiente flash).'
echo '    - TO=0 siempre + MISR!=0 en el primer volcado => residuo = transitorio/PHY-RX (discriminante A).'
echo '  GATE-3: flood ~0 (o acotado con "flood frenado" si la condicion vive); underruns lentos'
echo '     (~10/30 min) y dddd1019 residual NO cambian por este parche: que sigan NO es fallo de L74.'
echo '  PASA = CONTENIDO en pantalla (patron/hyprland).'
echo '  GUARDA: >1500 lineas S4-DIAG => DPMS off automatico (el freno B2-A ya acota el log).'
