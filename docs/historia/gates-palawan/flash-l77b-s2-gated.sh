#!/bin/bash
# flash-l77b-s2-gated.sh — L77b = L76R + paridad vendor COHERENTE con C4/C7
# (build/gates/revision/L77B-PREP-20261017.md; parche patches/l77b-paridad-progfetch.diff):
#   L77b-1 INTF prog-fetch: INTF_CONFIG 0x80800000 (bit31+bit23), PROG_FETCH_START 0x0014272d
#   L77b-2 DSC_CLK_CTRL 0xc0000000 en DSC_0/DSC_1
#   L77b-3 split TOP en video UPPER/LOWER 0/0 (mainline BIT(4)/BIT(8))
#   C4 (ENC_DF_CTRL 0x095c1203) y C7 (TE solo INTF_1) SE MANTIENEN.
# Gate nuevo 'underrun': con un plano mantenido y page-flip continuo
# (sleep 20 | modetest -v: modetest necesita stdin abierto, si no sale al instante),
# delta de underrun de encoder-0 entre t+5 s y t+17 s == 0 (L76R: ~1 por frame).
# Clon de flash-l76r-gated.sh: mismas guardas (bateria, retry:b, lector ACM unico,
# relectura boot_a al tamano exacto, guarda-flood, CARGA). NADA se flashea sin la
# orden del dueno + fila pre-registrada en el ledger hermano.
# Config k52L77b.config = copia de k52L76r.config; dtbo s288 SOLO LECTURA.
# Unica escritura: boot_a. Rollback = L76R (f75a27fd) / L74 06a1d9fe.
#
# ---- cabecera heredada de flash-l76r-gated.sh ----
# flash-l76r-gated.sh — L76 "paridad vendor" del encendido DSI/DPU sobre
# L73+L74+L75 INTACTOS (PLAN-KERNEL-PANTALLA-20261017 + REGDIFF/ENABLE-ORDER/
# CMD-FLAGS-SYNC/DCS-COTEJO/DPU-VENDOR del 17-oct; resumen en
# build/gates/revision/L76-PREP-20261017.md):
#   C1 widebus ON + RGB101010 (VID_CFG0 0x02009140)   C2 INTF 427 (HSYNC 572, CFG2 0x1011)
#   C3 PPS unica post-0x29, pic_width 3200, sin BTA   C4 DSC ENC_DF_CTRL 0x095c1203
#   C5 VID diferido (0x1f1) -> VID ON tras PPS (0x1f3), reset 15 ms, DCS 0x39,
#      sin K50-commit entre TRIG_DMA, CLKOUT_TIMING_CTRL=0
#   C7 TIMING_ENGINE_EN solo INTF_1 (maestro)
# Clon de flash-l75-gated.sh (endurecido): mismas guardas de bateria, retry:b,
# lector ACM unico, relectura boot_a al tamano exacto, guarda-flood. NADA se
# flashea sin la orden del dueno + fila pre-registrada en el ledger hermano.
# Carga: mismo config k52L76.config (=k52L74=k52L73, modulos rootfs intactos) +
# dtbo s288 (ya en slot a, SOLO LECTURA). Unica escritura: boot_a.
# PRERREQUISITO: rootfs Arch restaurado en userdata (se perdio con #653);
# sin el no hay SSH ni gates.
# Rollback = L74 06a1d9fe / L73 a671d293 / L71 5e13addf.
set -u
set -o pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")" || exit 1
BOOT=build/bootimg/boot-uke-k52L77b-s2.img
DTBO=build/bootimg/s288-boot-dtbo-gpu-display-gpi-i2c-ktz-vci-adsp.img
EB=4bc5388ad10e22cc562e042deb2879f30626f560bc5faab935525e22635ebf9f
ED=02d403c518346bf5a3757c5519eb8ca205f8f75af078cfde2e03d9d49e702dfb
[ "$EB" != "SHA_PENDIENTE" ] || { echo "ABORTADO: sha del boot L77b sin rellenar (tras el repack)"; exit 2; }
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
timeout 600 fastboot flash boot_a "$BOOT" 2>&1 | tail -2
FRC=${PIPESTATUS[0]}
if [ "$FRC" -ne 0 ]; then echo "ABORTADO: fastboot flash boot_a rc=$FRC; NO set_active ni reboot"; exit 7; fi
# fastboot NO lee particiones: la relectura boot_a vs imagen va post-arranque (bloque ssh, ledger #241).
timeout 20 fastboot set_active a 2>&1 | tail -1
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "ABORTADO: set_active a fallo; NO reboot"; exit 7; }
timeout 20 fastboot reboot 2>&1 | tail -1
echo '== esperar arranque (~75 s) + captura kmsg + gates L76+L77b + underrun + guarda-flood + CARGA =='
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
timeout 150 ssh -i build/rootfs/uke-arch-root -o BatchMode=yes -o ConnectTimeout=8 root@192.168.42.129 'exec 2>&1
echo "== captura VIVA /dev/kmsg (desde el registro mas antiguo, sin eviccion) =="
( timeout 22 cat /dev/kmsg > /root/kmsg-l77b.txt 2>/dev/null & echo $! > /root/kmsg.pid )
sleep 1
if [ "$(dmesg | grep -c "UKE-L76: VID ON tras")" = "0" ]; then echo "(enable no corrido: commit con modetest)"; sleep 5 | timeout 25 modetest -M msm-kms -s 36@85:#0 >/dev/null 2>&1; fi
sleep 3
kill $(cat /root/kmsg.pid) 2>/dev/null
K=/root/kmsg-l77b.txt
OK=0; NG=0
g() { # g "<descripcion>" <n_minimo> <patron-ERE>
  local n; n=$(grep -acE "$3" $K)
  if [ "$n" -ge "$2" ]; then echo "  PASA  [$n>=$2] $1"; OK=$((OK+1)); else echo "  FALLA [$n<$2] $1"; NG=$((NG+1)); fi
}
echo "== CMDLINE variante s2: $(grep -o 'msm.uke_l77_split=2' /proc/cmdline || echo AUSENTE)"
echo "== GATE-0 continuidad L73/L74/L75 (todo lo anterior INTACTO) =="
grep -a "UKE-L74" $K | head -2
grep -a "UKE-L75" $K | head -2
grep -a "UKE-L73" $K | head -1
g "L75 tabla PHY vendor en NOW (x2 PHY)" 2 "now 00 27 0a 0a 1b 19 0a 0b 0a 02 04 00 20 0f"
g "L74 HS_TIMER=0x0004bb80 eco" 2 "UKE-L74: id=[01] HS_TIMER=0x0004bb80 \(rd 0x0004bb80\)"
echo "== GATE-1 C1/C5 host DSI (readback power_on; fisico vendor = offset+4) =="
grep -a "UKE-L76-DSI" $K | head -6
g "widebus ON" 1 "UKE-L76: widebus ON"
g "VIDCFG0=0x02009140 (RGB101010+WIDEN) x2" 2 "VIDCFG0=0x02009140 "
g "COMP=0x03200b51 x2" 2 "COMP=0x03200b51 "
g "AH=0x01cb0020 AV=0x08ec0094 TOT=0x0905023b x2" 2 "AH=0x01cb0020 \(v 0x01cb0020\) AV=0x08ec0094 \(v 0x08ec0094\) TOT=0x0905023b "
g "CLKOUT=0x00000000 x2" 2 "CLKOUT=0x00000000 "
g "VID diferido CTRL=0x000001f1 x2 (dsi0,dsi1)" 2 "UKE-L76: VID diferido id=[01] CTRL=0x000001f1"
echo "  (solo informativo, sin gate: TRIG v 0x80000004 [nuestro 0x80001004, BLOCK_DMA se queda], LANE_CTRL, DBMODE, LMAP30c)"
echo "== GATE-2 C5/C3 panel: DCS 0x39, PPS unica 3200, VID ON tras PPS =="
grep -aE "UKE-L76: (DCS|PPS|VID)" $K | head -8
grep -a "UKE-L76-RAIL" $K | head -2
g "L76-R ciclo de rieles: vsn/vsp 1->0 con reset=0" 1 "UKE-L76-RAIL: reset=0, vsn 1->0, vsp 1->0"
g "DCS dt=0x39 n=108 err=0" 1 "UKE-L76: DCS dt=0x39 n=108 err=0"
g "PPS w=3200 [8..9]=0C 80 + [19..58]=B2 9F 0D 86 02" 1 "UKE-L76: PPS w=3200 PPS\[8\.\.9\]=0C 80 .* \[19\]=B2 \[23\]=9F \[27\]=0D \[29\]=86 \[58\]=02 "
g "PPS enviada err=0 (dims 3200x2136)" 1 "UKE-L63: PPS post-0x29 enviada \(dims=3200x2136 por link, err=0\)"
g "VID ON CTRL=0x000001f3 x2 (dsi0,dsi1)" 2 "UKE-L76: VID ON id=[01] CTRL=0x000001f3"
g "VID ON tras PPS" 1 "UKE-L76: VID ON tras PPS"
echo "  ausencias (deben ser 0): PPS#1 L37=$(grep -ac UKE-L37 $K) L62=$(grep -ac UKE-L62 $K) BTA L65=$(grep -ac UKE-L65 $K) K50-commit=$(grep -ac K50-commit $K)"
echo "== GATE-3 C2/C7 INTF + C4 DSC =="
grep -aE "UKE-L76-INTF|UKE-L76-DSC|UKE-L76: INTF" $K | head -8
g "INTF HSYNC/VPER/DHCTL/CFG2/DATA = vendor (INTF1+INTF2)" 2 "UKE-L76-INTF: INTF[12] HSYNC=0x023c0010 \(v 0x023c0010\) VPER=0x00142968 \(v 0x00142968\) DHCTL=0x01ca0020 \(v 0x01ca0020\) CFG2=0x00001011 \(v 0x00001011\) DHCTL_DATA=0x012a0020 "
g "DSC ENC_DF_CTRL=0x095c1203 (DSC0+DSC1)" 2 "UKE-L76-DSC: DSC[01] ENC_DF_CTRL=0x095c1203 "
g "INTF1 TE ON (maestro)" 1 "UKE-L76: INTF1 TE ON "
g "INTF2 TE OFF (esclavo, vendor 0)" 1 "UKE-L76: INTF2 TE OFF"
echo "== GATE-4 ORDEN: VID ON (dsi0,dsi1) ANTES que INTF1 TE ON (vendor: +1.68 ms) =="
LV=$(grep -an "UKE-L76: VID ON id=1" $K | head -1 | cut -d: -f1)
LT=$(grep -an "UKE-L76: INTF1 TE ON" $K | head -1 | cut -d: -f1)
TV=$(grep -a "UKE-L76: VID ON id=1" $K | head -1 | grep -oE "t=[0-9]+" | cut -d= -f2)
TT=$(grep -a "UKE-L76: INTF1 TE ON" $K | head -1 | grep -oE "t=[0-9]+" | cut -d= -f2)
if [ -n "$LV" ] && [ -n "$LT" ] && [ "$LV" -lt "$LT" ]; then echo "  PASA  orden VID ON (linea $LV) < INTF1 TE ON (linea $LT); dt=$(( ${TT:-0} - ${TV:-0} )) us (vendor ~1680 us)"; OK=$((OK+1))
else echo "  FALLA orden VID/TE (VID linea ${LV:-?}, TE linea ${LT:-?})"; NG=$((NG+1)); fi
echo "== GATE-5 S4-DIAG / flood / underruns =="
grep -a "S4-DIAG: wait for video done" $K | head -5
echo "S4-DIAG total (dmesg completo): $(dmesg | grep -c S4-DIAG)"
echo "S4-DIAG en la captura: $(grep -ac S4-DIAG $K)"
grep -a "flood frenado" $K | head -2
grep -oE "underrun: *[0-9]+" /sys/kernel/debug/dri/1/encoder-0/status 2>/dev/null | head -2
grep -oE "underrun: *[0-9]+" /sys/kernel/debug/dri/1/encoder-1/status 2>/dev/null | head -2
echo "== GATE-6 L77b paridad INTF prog-fetch / DSC_CLK_CTRL / split (readback, vendor al lado) =="
grep -aE "UKE-L77" $K | head -8
g "INTF CONFIG=0x80800000 PROG_FETCH_START=0x0014272d (INTF1+INTF2)" 2 "UKE-L77-INTF: INTF[12] CONFIG=0x80800000 \(v 0x80800000\) PROG_FETCH_START=0x0014272d \(v 0x0014272d\) en=1"
g "DSC_CLK_CTRL=0xc0000000 (DSC0+DSC1)" 2 "UKE-L77-DSC: DSC[01] CLK_CTRL=0xc0000000 "
g "SPLIT EN=1 UPPER=0x0 LOWER=0x0" 1 "UKE-L77-SPLIT: EN=1 \(v 1\) UPPER=0x0 \(v 0x0\) LOWER=0x0 \(v 0x0\)"
echo "  (informativo: SPARE con param 1 = 0 mainline; vendor 1 -> msm.uke_l77_split=2)"
echo "== GATE-7 UNDERRUN con plano mantenido + page-flip (criterio: delta 0) =="
S=/sys/kernel/debug/dri/1/encoder-0/status
cat $S 2>&1 | head -2
( sleep 20 | timeout 30 modetest -M msm-kms -s 36@85:#0 -v >/root/modetest-l77b.txt 2>&1 ) &
sleep 5
U1=$(grep -oE "underrun: *[0-9]+" $S | head -1 | grep -oE "[0-9]+$"); V1=$(grep -oE "vsync: *[0-9]+" $S | head -1 | grep -oE "[0-9]+$")
sleep 12
U2=$(grep -oE "underrun: *[0-9]+" $S | head -1 | grep -oE "[0-9]+$"); V2=$(grep -oE "vsync: *[0-9]+" $S | head -1 | grep -oE "[0-9]+$")
cat $S 2>&1 | head -2
wait
DU=$(( ${U2:-0} - ${U1:-0} )); DV=$(( ${V2:-0} - ${V1:-0} ))
echo "  12 s con plano: vsync ${V1:-?}->${V2:-?} (delta $DV, esperado ~1440) underrun ${U1:-?}->${U2:-?} (delta $DU)"
grep -aE "freq|failed|error" /root/modetest-l77b.txt | head -3
if [ -n "${U1:-}" ] && [ -n "${U2:-}" ] && [ "$DV" -gt 100 ] && [ "$DU" -eq 0 ]; then echo "  PASA  underrun delta 0 con vsync vivo"; OK=$((OK+1))
else echo "  FALLA underrun delta $DU (vsync delta $DV; sin vsync vivo el gate no es valido)"; NG=$((NG+1)); fi
echo "== CARGA =="
for r in /sys/class/remoteproc/remoteproc*; do echo "$(cat $r/name): $(cat $r/state)"; done
echo "PDR: $(dmesg | grep -c charger_pd)"
for f in status current_now; do echo "$f: $(cat /sys/class/power_supply/qcom-battmgr-bat/$f 2>&1 | head -1)"; done
# Carga como gates (CARGA-REVISION-L76-20261017 §2): cuentan aparte, no son de paridad.
CO=0; CN=0
cg() { if [ "$2" = 1 ]; then echo "  PASA  CARGA: $1"; CO=$((CO+1)); else echo "  FALLA CARGA: $1"; CN=$((CN+1)); fi; }
AS=$(for r in /sys/class/remoteproc/remoteproc*; do case "$(cat $r/name)" in *adsp*) cat $r/state;; esac; done | head -1)
[ "$AS" = running ] && cg "adsp running" 1 || cg "adsp running (estado: ${AS:-ausente})" 0
[ "$(dmesg | grep -c charger_pd)" -ge 1 ] && cg "PDR charger_pd >=1" 1 || cg "PDR charger_pd >=1" 0
BS=$(cat /sys/class/power_supply/qcom-battmgr-bat/status 2>/dev/null)
[ "$BS" = Charging ] || [ "$BS" = Full ] && cg "battmgr status=$BS" 1 || cg "battmgr status=${BS:-ausente} (con cargador debe ser Charging)" 0
[ "$(sha256sum /lib/firmware/adsp.b40 2>/dev/null | cut -c1-8)" = 42c86837 ] && cg "adsp.b40 sha 42c86837" 1 || cg "adsp.b40 sha 42c86837 (corrupto o ausente: re-scp charge/firmware/adsp.b40 a /lib/firmware/)" 0
echo "CARGA-GATES: $CO PASA / $CN FALLA (de 4)"
F=$(dmesg | grep -c S4-DIAG)
if [ "$F" -gt 1500 ]; then echo "GUARDA-FLOOD: $F lineas -> DPMS off (protejo disco/sistema)"; timeout 20 modetest -M msm-kms -w 36:DPMS:3 >/dev/null 2>&1; fi
echo "flood final: $(dmesg | grep -c S4-DIAG)"
echo "L77b-GATES: $OK PASA / $NG FALLA (de 23 = 19 L76 + 3 L77 + underrun)"
' 2>&1 | tail -110
echo '== CRITERIO PREFIJADO L77b (L77B-PREP-20261017 §5) =='
echo '  23/23 + underrun delta 0 + IMAGEN => cerrado (paridad coherente era la causa).'
echo '  23/23 + underrun 0 + NEGRO       => underrun no era el bloqueo (como L67): L77c ICC/MMCX.'
echo '  gates L77 PASA + underrun >0      => C4/C7 no son la causa unica: L77a (dsc_df=0 te_master_only=0)'
echo '                                       o fetch (L77c / L77-SSPP); probar msm.uke_l77_split=2.'
echo '  algun gate L77 FALLA              => la paridad no se consiguio: lectura NO concluyente.'
echo '  (Bisect por cmdline sin rebuild: msm.uke_l77_progfetch=0 / uke_l77_dsc_clk=0 / uke_l77_split=0.)'
echo '== CRITERIO HEREDADO L76 (L76-PREP-20261017 §6) =='

echo '  GATES DE REGISTRO (deben ser TODOS PASA = 19/19; uno en FALLA => la paridad no'
echo '  se consiguio y la lectura visual NO es concluyente para C1-C7):'
echo '     DSI: widebus ON, VIDCFG0 0x02009140, COMP 0x03200b51, AH/AV/TOT 0x01cb0020/'
echo '          0x08ec0094/0x0905023b, CLKOUT 0, CTRL 0x1f1 (diferido) -> 0x1f3 (VID ON) x2.'
echo '     PANEL: DCS 0x39 n=108 err=0; PPS w=3200 [8..9]=0C 80 [19,23,27,29,58]=B2 9F 0D 86 02;'
echo '          PPS err=0; sin L37/L62/L65/K50-commit.'
echo '     INTF1/2: HSYNC 0x023c0010 VPER 0x00142968 DHCTL 0x01ca0020 CFG2 0x1011 DATA 0x012a0020.'
echo '     DSC0/1: ENC_DF_CTRL 0x095c1203.  TE: INTF1 ON, INTF2 OFF.  ORDEN: VID ON < INTF1 TE ON.'
echo '  LECTURA (matriz PLAN §3.3):'
echo '    gates 18/18 + CONTENIDO           => cerrado.'
echo '    gates 18/18 + negro + flood 0     => residuo DDIC/PHY-RX o potencia (L77 broadcast HW C6-SYNC;'
echo '                                         L78 votos MMCX/MXA e ICC).'
echo '    gates 18/18 + FIFO burst/flood    => mirar INTF2 TE (param uke_l76_te_master_only),'
echo '                                         ERR_INT_MASK0, broadcast, BLOCK_DMA antes de tocar timing.'
echo '    INTF2 sin imagen (mitad derecha)  => C7 refutado: L77 con msm.uke_l76_te_master_only=0.'
echo '  GUARDA: >1500 lineas S4-DIAG => DPMS off automatico (el freno B2-A ya acota el log).'
