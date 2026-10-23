#!/bin/bash
# flash-senemos-v4-gated.sh — CUARTA prueba del kernel senemos (ouke4) = ouke3 (boot_a 5c9fb2c6: todo arranca solo, Omarchy, WiFi, tactil)
# con UN cambio de CODIGO y la misma config: parches 0002+0004 en arm-smmu-qcom.c (lista blanca de SIDs del SMMU: LPASS audio
# 0x801001/0x1061 y compute-cb de FastRPC del ADSP). Es el requisito de la etapa E2b de audio (build/gates/revision/AUDIO-E2b-*.md):
# crear el PD "audiopd" del ADSP por FastRPC para que el APM responda. Sin el flash nada de eso puede probarse.
# Cambia el release del kernel (…-ouke3 -> …-ouke4): los modulos propios (uke_bt_*.ko, uke_audio_*.ko) hay que recompilarlos.
#
# NO EJECUTAR sin: (1) orden EXPRESA del dueno (el reinicio corta BT/WiFi y la sesion), (2) fila pre-registrada en el ledger hermano con
# el sha del boot v4, (3) semaforo inter-proyecto libre, (4) presupuesto de escrituras (UNA: boot_a), (5) haber corrido --pre en v3.
#
# ORDEN:
#   0) con la tablet AUN EN v3 y SSH vivo:  bash build/gates/flash-senemos-v4-gated.sh --pre
#      (instala los modulos ouke4 en /lib/modules/7.2.9-senemos.1.4054.3-ouke4 + depmod, junto a los ouke3 (que NO se tocan: rollback);
#       sin esto, tras el arranque v4 uke-carga y el WiFi no encuentran modulos con su vermagic. Orden de instalacion de lo propio:
#       (a) tarball de modulos ouke4, (b) uke_audio_e2/e2b.ko recompilados contra ouke4 en .../extra, (c) depmod. Los uke_bt_*.ko los
#       instala la sesion BT con su deploy.sh (por KREL) DESPUES de recompilarlos contra el arbol ouke4 (build/rootfs/deploy/bt/build.sh))
#   1) el dueno pone la tablet en fastboot a mano (Power + Vol-)
#   2) bash build/gates/flash-senemos-v4-gated.sh      -> boot_a <- v4 (UNICA escritura); dtbo_a stock NO se toca
#   3) --post automatico: relectura, gates de display/USB/carga y GPU AL ARRANQUE (como v3) + gates nuevos de v4 (release, sin faults de SMMU)
# Rollback: --rollback v3 (1 escritura, boot_a <- 5c9fb2c6, el vigente) | v2 | v1 | l77ba|l76r (2 escrituras, dtbo_a <- s288).
#
# Uso: bash build/gates/flash-senemos-v4-gated.sh [--check|--pre|--post|--rollback v3|v2|v1|l77ba|l76r]
set -u
set -o pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")" || exit 1
BK=build/backup-par-bueno/android-20261017
BOOT=build/bootimg/boot-uke-senemos-7.2.9-v4.img
EB=fc9309a3953e8c423b30647b27a151aa740e6473757642ae922ec9cc0aaab88f
RB_V3=build/bootimg/boot-uke-senemos-7.2.9-v3.img
EB_V3=5c9fb2c638c0a365da6988ea92db54dff03be49812a61ac34d1a586f3a3d6990
KREL_V3=7.2.9-senemos.1.4054.3-ouke3
RB_V2=build/bootimg/boot-uke-senemos-7.2.9-v2.img
EB_V2=7848d68dbdc6dde2d60e4b3afedc266a3ee62eb8ecf3fcd1b8ad1ddedce746d4
RB_V1=build/bootimg/boot-uke-senemos-7.2.9.img
EB_V1=4894a841de1d1dd23f00a865e6b13169b11d498502948aeddf8295984d911eca
DTBO_STOCK=$BK/dtbo_b.img
ED_STOCK=27e61d21fd6a0858135e322eef9e8a223f6612ad24b1913fd7d9d680d602b3d8
DTBO_S288=$BK/dtbo_a.img
ED_S288=69c82e7beb80d7a89d065882615f358c1371b8fc110ca404d7fd81bd4989b214
RB_L77BA=build/bootimg/boot-uke-k52L77b-a.img
EB_L77BA=b302714a2bcd23e6a0118f52163d8fd63b27ecadefaf31e671a9ce0ddda2e6da
RB_L76R=build/bootimg/boot-uke-k52L76r.img
EB_L76R=f75a27fdcae7e46ec76f0c4f5a8c5af652b8f24af65472ada4129dc2efe51073
KREL=7.2.9-senemos.1.4054.3-ouke4
MODTB=build/kernel-pokes/senemos-build/modules-$KREL.tar.zst
EM=57ef06f6ea92deec5972444d433b1cf0c6211067a76c2b9214f86d20afbdb240
AUDIO_KO="build/rootfs/deploy/audio/out/uke_audio_e2.ko build/rootfs/deploy/audio/out/uke_audio_e2b.ko"
DT=build/kernel-pokes/senemos-7.2.9/dt
GEN=build/kernel-pokes/senemos-7.2.9/linux-7.2.9/native-generated-v2
KEY=build/rootfs/uke-arch-root
IP=192.168.42.129
SSHO="-i $KEY -o BatchMode=yes -o ConnectTimeout=8"
MODE=${1:-flash}
TS=$(date +%Y%m%d-%H%M%S)

die() { echo "ABORTADO: $*"; exit "${2:-2}"; }

pc_gates() {
  echo '== GATES DE PC (shas + admision del DT por el transform de uke-abl.c, port propio) =='
  # gate estatico: el camino de prueba NO escribe dtbo_a (solo boot_a)
  local nw nb
  nw=$(sed -n '/^# ===FLASH-PATH-BEGIN===/,/^# ===FLASH-PATH-END===/p' "$0" | grep -c 'flash_one dtbo_a')
  nb=$(sed -n '/^# ===FLASH-PATH-BEGIN===/,/^# ===FLASH-PATH-END===/p' "$0" | grep -c 'flash_one boot_a')
  [ "$nw" = 0 ] && [ "$nb" = 1 ] || die "el camino de prueba escribe dtbo_a ($nw) o no escribe boot_a una vez ($nb)"
  echo '  OK  gate estatico: el camino de prueba tiene 1 escritura (boot_a) y 0 a dtbo_a'
  # el overlay USB v2 no lleva usb-psy-name y conserva dr_mode peripheral
  ! fdtdump "$GEN/usb.dtbo" 2>/dev/null | grep -q 'usb-psy-name' || die "usb.dtbo v2 aun lleva usb-psy-name"
  fdtdump "$GEN/usb.dtbo" 2>/dev/null | grep -q 'dr_mode = "peripheral"' || die "usb.dtbo v2 sin dr_mode peripheral"
  echo '  OK  overlay USB v2: sin usb-psy-name, dr_mode peripheral'
  [ "$EB" != "SHA_PENDIENTE" ] && [ "$EM" != "SHA_PENDIENTE" ] || die "sha del boot v4 o del tarball de modulos sin rellenar"
  [ "$(sha256sum "$MODTB" | cut -d' ' -f1)" = "$EM" ] || die "TARBALL MODULOS ouke4 SHA MISMATCH"
  [ "$(sha256sum "$RB_V3" | cut -d' ' -f1)" = "$EB_V3" ] || die "rollback v3 (boot-uke-senemos-7.2.9-v3.img) SHA MISMATCH"
  [ "$(sha256sum "$RB_V2" | cut -d' ' -f1)" = "$EB_V2" ] || die "rollback v2 (boot-uke-senemos-7.2.9-v2.img) SHA MISMATCH"
  [ "$(sha256sum "$BOOT" | cut -d' ' -f1)" = "$EB" ] || die "BOOT SHA MISMATCH"
  [ "$(sha256sum "$DTBO_STOCK" | cut -d' ' -f1)" = "$ED_STOCK" ] || die "DTBO STOCK SHA MISMATCH"
  [ "$(sha256sum "$DTBO_S288" | cut -d' ' -f1)" = "$ED_S288" ] || die "DTBO s288 (rollback) SHA MISMATCH"
  [ "$(sha256sum "$RB_V1" | cut -d' ' -f1)" = "$EB_V1" ] || die "rollback v1 (boot-uke-senemos-7.2.9.img) SHA MISMATCH"
  [ "$(sha256sum "$RB_L77BA" | cut -d' ' -f1)" = "$EB_L77BA" ] || die "rollback L77b-a SHA MISMATCH"
  [ "$(sha256sum "$RB_L76R" | cut -d' ' -f1)" = "$EB_L76R" ] || die "rollback L76R SHA MISMATCH"
  [ "$(stat -c%s "$DTBO_STOCK")" = 25165824 ] || die "dtbo stock no mide 24 MiB (particion completa)"
  # la entrada DT de la tabla del dtbo stock = la que se verifico en el PC
  python3 -I - "$DTBO_STOCK" <<'EOF' || exit 2
import struct, sys, hashlib
b = open(sys.argv[1], 'rb').read()
m, tot, hs, es, n, off = struct.unpack('>6I', b[:24])
assert m == 0xd7b7ab1e and n == 1, 'tabla DT inesperada'
sz, o = struct.unpack('>2I', b[off:off+8])
h = hashlib.sha256(b[o:o+sz]).hexdigest()
assert h == 'e8f991e3324048ee3915fe8342c0b599c630ee2baf8929d4670820b388ecbcfc', 'entrada dtbo stock != verificada: ' + h
assert b'Uke based on SM8635' in b[o:o+sz]
print('  OK  dtbo stock: 1 entrada, sha e8f991e3 (la verificada), modelo Uke')
EOF
  local ok=0 x
  for x in "live-android-os3.dtb bootargs-live-android.txt" "abl-2-dtbo_b-0.dtb bootargs-captura-L52.txt" \
           "abl-3-dtbo_b-0.dtb bootargs-captura-L52.txt" "abl-1-dtbo_b-0.dtb bootargs-captura-L52.txt"; do
    set -- $x
    if python3 -I $DT/check-uke-abl.py $DT/$1 $DT/$2 $GEN/ufs.dtbo $GEN/usb.dtbo $GEN/display.dtbo /var/tmp/uke-senemos-chk-v2 2>&1 \
         | grep -q 'RESULTADO uke_abl_native = OK'; then echo "  OK  admitido + overlay nativo: $1"; ok=$((ok+1))
    else echo "  FALLA admision: $1"; fi
  done
  [ "$ok" = 4 ] || die "el port del transform no admite el DT stock en los 4 casos"
  # (pipefail: el checker sale 1 al rechazar; se captura primero y se busca despues)
  local neg
  neg=$(python3 -I $DT/check-uke-abl.py $DT/abl-2-dtbo_a-0.dtb $DT/bootargs-captura-L52.txt $GEN/ufs.dtbo $GEN/usb.dtbo $GEN/display.dtbo /var/tmp/uke-senemos-chk-v2 2>&1)
  if printf '%s\n' "$neg" | grep -q 'RESULTADO RECHAZO'; then
    echo "  OK  control negativo: con s288 el transform RECHAZA (por eso dtbo_a <- stock)"
  else die "control negativo fallido: s288 no sale rechazado (el checker no discrimina)"; fi
}

fb_gates() {  # $1 = umbral mV
  DEV=$(timeout 15 fastboot devices 2>/dev/null | head -1)
  [ -n "$DEV" ] || die "fastboot devices vacio" 3
  echo "device: $DEV"
  for v in battery-voltage current-slot slot-retry-count:a slot-retry-count:b slot-unbootable:a; do
    timeout 15 fastboot getvar "$v" 2>&1 | grep -E "^$v" | head -1; done
  MV=$(timeout 15 fastboot getvar battery-voltage 2>&1 | grep -oE '[0-9]+' | head -1)
  [ -n "${MV:-}" ] || die "sin battery-voltage" 4
  if [ "$MV" -lt 3300 ]; then die "bateria $MV mV < 3300 (riesgo de brick)" 4; fi
  if [ "$MV" -lt "$1" ]; then
    [ "${FORCE_LOWBAT:-0}" = 1 ] || die "bateria $MV mV < $1 (FORCE_LOWBAT=1 solo con orden del dueno)" 4
    echo "AVISO: bateria $MV mV < $1 con FORCE_LOWBAT=1"
  fi
  RB=$(timeout 15 fastboot getvar slot-retry-count:b 2>&1 | grep -E '^slot-retry-count:b' | head -1 | grep -oE '[0-9]+$')
  if [ -z "${RB:-}" ] || [ "$RB" -lt 3 ]; then
    [ "${FORCE_RETRY:-0}" = 1 ] || die "slot-retry-count:b='${RB:-?}' < 3 (FORCE_RETRY=1 para forzar)" 5
  fi
  LPID=/var/tmp/uke-consola-lector.pid
  { [ -f "$LPID" ] && kill -0 "$(cat "$LPID")" 2>/dev/null; } || die "lector ACM no armado (build/gates/uke-consola-lector.sh)" 6
  NR=$(pgrep -fc 'cat /dev/ttyACM' || true)
  [ "${NR:-0}" -le 1 ] || die "$NR lectores ACM vivos (debe ser UNICO)" 6
  echo "lector ACM vivo (pid $(cat "$LPID")), cat activos: ${NR:-0}"
}

flash_one() {  # $1 particion $2 imagen
  echo "== ESCRITURA: $1 <- $2 =="
  timeout 600 fastboot flash "$1" "$2" 2>&1 | tail -2
  [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "ABORTADO: fastboot flash $1 rc!=0; NO set_active ni reboot."
    echo "  estado posible: dtbo_a ya stock y boot_a viejo -> reintentar o --rollback antes de arrancar"; exit 7; }
}

wait_ssh() {
  local i UP
  for i in $(seq 1 12); do
    UP=$(timeout 12 ssh $SSHO -o ConnectTimeout=6 root@$IP 'uptime' 2>&1 | tail -1)
    case "$UP" in *up*) echo "arrancada: $UP"; return 0;; esac
    echo "reintento SSH $i: $UP"; sleep 12
  done
  return 1
}

post() {
  echo "== RELECTURA boot_a y dtbo_a (ledger #241: hash al tamano EXACTO de la imagen) =="
  local SZ R1 R2
  SZ=$(stat -c%s "$BOOT")
  R1=$(timeout 60 ssh $SSHO root@$IP "head -c $SZ /dev/disk/by-partlabel/boot_a | sha256sum" 2>/dev/null | cut -d' ' -f1)
  [ "$R1" = "$EB" ] && echo "  OK  boot_a == senemos ($R1)" || echo "  *** boot_a releido '${R1:-vacio}' != $EB ***"
  R2=$(timeout 60 ssh $SSHO root@$IP "head -c 25165824 /dev/disk/by-partlabel/dtbo_a | sha256sum" 2>/dev/null | cut -d' ' -f1)
  [ "$R2" = "$ED_STOCK" ] && echo "  OK  dtbo_a == stock ($R2)" || echo "  *** dtbo_a releido '${R2:-vacio}' != $ED_STOCK ***"
  timeout 240 ssh $SSHO root@$IP "KREL=$KREL TS=$TS bash -s" <<'EOS' 2>&1 | tee build/logs/senemos-post-$TS.txt | tail -150
exec 2>&1
dmesg -n 7 2>/dev/null
OK=0; NG=0
g() { if [ "$2" = 1 ]; then echo "  PASA  $1"; OK=$((OK+1)); else echo "  FALLA $1"; NG=$((NG+1)); fi; }
dmesg > /root/dmesg-senemos-$TS.txt
D=/root/dmesg-senemos-$TS.txt
echo "== G1 identidad del kernel y del DT =="
echo "uname: $(uname -r)"; [ "$(uname -r)" = "$KREL" ] && g "uname -r = $KREL" 1 || g "uname -r = $KREL" 0
echo "cmdline: $(cat /proc/cmdline)"
grep -q 'rdinit=/ukeinit' /proc/cmdline && grep -q 'msm.separate_gpu_kms=1' /proc/cmdline && g "cmdline del boot.img en /proc/cmdline (sin CMDLINE_FORCE)" 1 || g "cmdline del boot.img en /proc/cmdline" 0
echo "model: $(tr -d '\0' < /proc/device-tree/model)"; echo "compatible: $(tr '\0' ' ' < /proc/device-tree/compatible)"
tr -d '\0' < /proc/device-tree/chosen/bootargs | grep -q 'mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid' && g "selector O82-42 en /chosen/bootargs del ABL" 1 || g "selector O82-42 en /chosen/bootargs" 0
grep -a 'Uke ABL DT' $D | head -3
grep -aq 'isolated native display graph prepared' $D && g "uke-abl: grafo nativo preparado" 1 || g "uke-abl: grafo nativo preparado" 0
grep -aq 'UKE-SENEMOS' $D && g "sin panic/aviso UKE-SENEMOS" 0 || g "sin panic/aviso UKE-SENEMOS" 1
echo "== G2 display (msm/dpu/dsi/o82/ktz) =="
grep -aiE 'msm|dpu|dsi|o82|ktz8866|mdss|dispcc|panel|drm' $D | grep -viE 'adreno|a7xx|gmu|zap' | head -60
echo "-- errores display:"; grep -aiE '(msm|dpu|dsi|o82|ktz|mdss|dispcc).*(error|fail|timeout|-[0-9]+)|underrun|fifo|quarantin' $D | head -25
echo "-- /sys/class/drm:"; ls /sys/class/drm/
for c in /sys/class/drm/card*-DSI-*; do [ -d "$c" ] && echo "$c status=$(cat $c/status) enabled=$(cat $c/enabled) modes=$(tr '\n' ' ' < $c/modes)"; done
ls -d /sys/class/drm/card*-DSI-* >/dev/null 2>&1 && g "conector DSI registrado" 1 || g "conector DSI registrado" 0
FBN=$(cat /sys/class/graphics/fb0/name 2>/dev/null); echo "fb0: ${FBN:-ninguno}"
[ "$FBN" = "msm-kmsdrmfb" ] || echo "$FBN" | grep -q msm && g "fb0 = msm (fbdev emulacion sobre DPU)" 1 || g "fb0 = msm (no simpledrm)" 0
for b in /sys/class/backlight/*; do [ -d "$b" ] && echo "$b brightness=$(cat $b/brightness) actual=$(cat $b/actual_brightness) max=$(cat $b/max_brightness) power=$(cat $b/bl_power)"; done
find /sys/devices -name touch_reset_state 2>/dev/null | head -2 | while read -r f; do echo "$f = $(cat $f)"; done
mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug
echo "-- encoders (debugfs):"; for s in /sys/kernel/debug/dri/*/encoder-*/status; do [ -f "$s" ] && echo "$s: $(head -1 $s)"; done
echo "== G3 patron con modetest (ids descubiertos, no supuestos) =="
systemctl is-active sddm display-manager 2>/dev/null | head -2
systemctl stop sddm 2>/dev/null; systemctl stop display-manager 2>/dev/null
modetest -M msm-kms -c 2>&1 | head -30
modetest -M msm-kms -e 2>&1 | head -12
CON=$(modetest -M msm-kms -c 2>/dev/null | awk '$3=="connected" && $4 ~ /^DSI/ {print $1; exit}')
CRTC=$(modetest -M msm-kms -p 2>/dev/null | awk '/^CRTCs:/{f=1;next} f && $1 ~ /^[0-9]+$/ {print $1; exit}')
echo "conector DSI=${CON:-?} crtc=${CRTC:-?} (modo #0 = preferido, 120 Hz)"
if [ -n "$CON" ] && [ -n "$CRTC" ]; then
  S=$(ls /sys/kernel/debug/dri/*/encoder-0/status 2>/dev/null | head -1)
  ( sleep 30 | timeout 40 modetest -M msm-kms -s ${CON}@${CRTC}:#0 -v > /root/modetest-senemos-$TS.txt 2>&1 ) &
  sleep 5
  # el status tiene una linea por INTF (intf:1 e intf:2): se suman
  sumk() { grep -oE "$1: *[0-9]+" "$S" 2>/dev/null | grep -oE "[0-9]+$" | awk '{s+=$1} END{if (NR) print s}'; }
  U1=$(sumk underrun); V1=$(sumk vsync)
  sleep 12
  U2=$(sumk underrun); V2=$(sumk vsync)
  echo "  >>> DUENO: MIRA EL PANEL AHORA (patron SMPTE de modetest ~30 s) <<<"
  wait
  DU=$(( ${U2:-0} - ${U1:-0} )); DV=$(( ${V2:-0} - ${V1:-0} ))
  echo "  12 s con plano: vsync ${V1:-?}->${V2:-?} (delta $DV, ~1440 a 120 Hz) underrun ${U1:-?}->${U2:-?} (delta $DU)"
  grep -aE "setting mode|freq|failed|error" /root/modetest-senemos-$TS.txt | head -4
  [ -n "${U1:-}" ] && [ "$DV" -gt 100 ] && [ "$DU" -eq 0 ] && g "underrun delta 0 con vsync vivo" 1 || g "underrun delta 0 con vsync vivo (DU=$DU DV=$DV)" 0
else g "ids de conector/CRTC descubiertos" 0; fi
echo "== G4 carga/ADSP (uke-carga.service habilitado; modulos ouke3 instalados por --pre) =="
ls /sys/class/remoteproc 2>/dev/null; ls /sys/class/power_supply 2>/dev/null
journalctl -b -u uke-carga.service --no-pager 2>/dev/null | grep -E "RESULTADO|FALLO|modprobe" | tail -8
systemctl is-active -q uke-carga.service && g "uke-carga.service activo" 1 || g "uke-carga.service activo" 0
BS=$(cat /sys/class/power_supply/qcom-battmgr-bat/status 2>/dev/null); echo "bat status: ${BS:-?} cap=$(cat /sys/class/power_supply/qcom-battmgr-bat/capacity 2>/dev/null)"
[ -n "$BS" ] && g "qcom-battmgr-bat presente (status=$BS)" 1 || g "qcom-battmgr-bat presente" 0
echo "== G6 GPU AL ARRANQUE (v3: gpucc built-in => kgsl-smmu sin -110 => adreno con IOMMU). NO se abre renderD128 =="
grep -aE "kgsl-smmu|adreno|gpu_cc|Initialized msm" $D | head -12
grep -aq "3da0000.kgsl-smmu: probe with driver arm-smmu failed with error -110" $D && g "kgsl-smmu SIN el -110 de ouke2" 0 || g "kgsl-smmu SIN el -110 de ouke2" 1
[ -e /sys/bus/platform/devices/3da0000.kgsl-smmu/driver ] && g "3da0000.kgsl-smmu enlazado a arm-smmu" 1 || g "3da0000.kgsl-smmu enlazado" 0
[ "$(basename "$(readlink /sys/bus/platform/devices/3d00000.qcom,kgsl-3d0/driver 2>/dev/null)")" = adreno ] && g "GPU enlazada a adreno" 1 || g "GPU enlazada a adreno" 0
[ -c /dev/dri/renderD128 ] && g "/dev/dri/renderD128 existe" 1 || g "/dev/dri/renderD128 existe" 0
echo "fds abiertos sobre renderD128 (debe ser 0: GMU sin arrancar): $(ls -l /proc/[0-9]*/fd 2>/dev/null | grep -c renderD128)"
grep -aiE "gmu|zap" $D | grep -viE "iommu group|sync_state" | head -3
echo "== G5 USB (como v2) =="
UDCS=$(ls /sys/class/udc 2>/dev/null | head -1); echo "udc: ${UDCS:-NINGUNO}"
[ -n "$UDCS" ] && g "existe /sys/class/udc/* (dwc3 probo, sin usb-psy-name)" 1 || g "existe /sys/class/udc/*" 0
UST=$(cat /sys/class/udc/$UDCS/state 2>/dev/null); echo "udc state: ${UST:-?}"
[ "$UST" = configured ] && g "UDC en estado configured (el host enumero)" 1 || g "UDC en estado configured (state=${UST:-?})" 0
echo "gadget g1/UDC: $(cat /sys/kernel/config/usb_gadget/g1/UDC 2>/dev/null)"
echo "red: $(ls /sys/class/net | tr '\n' ' ')"
tr -d '\0' < /proc/device-tree/soc/ssusb@a600000/dr_mode 2>/dev/null | sed 's/^/dr_mode: /'; echo
[ -e /proc/device-tree/soc/ssusb@a600000/usb-psy-name ] && g "DT vivo SIN usb-psy-name" 0 || g "DT vivo SIN usb-psy-name" 1
grep -aiE 'dwc3|eusb2|repeater|a600000|udc|gadget|usb budget|(usb|phy).*(error|fail|defer)' $D | head -30
echo "-- devices_deferred:"; cat /sys/kernel/debug/devices_deferred 2>/dev/null | head -20
for n in /sys/module/phy_msm_snps_eusb2_uke/parameters/diag_probe /sys/module/dwc3/parameters/diag_events; do [ -r $n ] && echo "$n = $(cat $n)"; done
echo "-- UFS: $(grep -c '' /proc/partitions) lineas en /proc/partitions"
echo "== G7 (v4) release, SMMU y servicios que ya arrancaban solos en v3 =="
[ "$(uname -r)" = "$KREL" ] && g "release $KREL" 1 || g "release $KREL" 0
grep -aE "Unhandled (context|stream) fault|outside Uke boot SMMU scope" $D | head -5
grep -aqE "Unhandled (context|stream) fault|outside Uke boot SMMU scope" $D && g "sin faults ni rechazos del SMMU en el arranque" 0 || g "sin faults ni rechazos del SMMU en el arranque" 1
sleep 25   # WiFi/escritorio llegan ~26 s tras el arranque (uke-bootguard)
[ "$(cat /sys/class/net/wlan0/operstate 2>/dev/null)" = up ] && g "wlan0 up (WiFi al arranque)" 1 || g "wlan0 up (WiFi al arranque)" 0
systemctl is-active -q uke-wifi.service && g "uke-wifi.service activo" 1 || g "uke-wifi.service activo" 0
systemctl is-active -q uke-desktop.service && g "uke-desktop.service activo" 1 || g "uke-desktop.service activo" 0
systemctl is-active -q uke-touch.service && g "uke-touch.service activo" 1 || g "uke-touch.service activo" 0
[ "$(cat /sys/class/remoteproc/remoteproc1/state 2>/dev/null)" = running ] && g "ADSP running (recovery $(cat /sys/class/remoteproc/remoteproc1/recovery))" 1 || g "ADSP running" 0
echo "SENEMOS-GATES: $OK PASA / $NG FALLA"
sync
EOS
  timeout 60 scp $SSHO root@$IP:/root/dmesg-senemos-$TS.txt build/logs/ 2>/dev/null && echo "dmesg copiado a build/logs/dmesg-senemos-$TS.txt"
  echo '== CRITERIO PREFIJADO v4 (AUDIO-E2b-PREPA-20261018) =='
  echo '  PASA  = SSH + terminal en el panel (como v2) + G6: kgsl-smmu enlazado, adreno enlazado y renderD128 al arranque.'
  echo '  G6 FALLA con lo demas bien => otra dependencia tardia de la GPU: devices_deferred / dmesg kgsl-smmu (no reflashear a ciegas).'
  echo '  Abrir la GPU (sesion Omarchy) es OTRO paso, con orden del dueno: build/rootfs/deploy/omarchy/deploy.sh start --go'
  echo '  Volver: fastboot a mano (Power+Vol-)  y  bash build/gates/flash-senemos-v4-gated.sh --rollback v3'
}

pre() {
  echo '== --pre (tablet AUN en v3, por SSH): modulos ouke4 (+ uke_audio_*.ko ouke4) junto a los ouke3 =='
  [ "$(sha256sum "$MODTB" | cut -d' ' -f1)" = "$EM" ] || die "TARBALL MODULOS ouke4 SHA MISMATCH"
  timeout 20 ssh $SSHO root@$IP 'uname -r' | grep -q 'ouke3$' || die "la tablet no esta en ouke3 (o sin SSH)"
  local k
  for k in $AUDIO_KO; do
    [ "$(modinfo -F vermagic "$k" | cut -d' ' -f1)" = "$KREL" ] || die "$k no esta compilado para $KREL (build/rootfs/deploy/audio/build-module.sh contra el arbol ouke4)"
  done
  zstd -dc "$MODTB" | timeout 300 ssh $SSHO root@$IP "tar -x --no-same-owner -C / 2>/dev/null && chown -R 0:0 /lib/modules/$KREL && rm -f /lib/modules/$KREL/build /lib/modules/$KREL/source && mkdir -p /lib/modules/$KREL/extra" \
    || die "fallo al instalar los modulos ouke4"
  tar -C "$(dirname $(echo $AUDIO_KO | cut -d' ' -f1))" --owner=0 --group=0 --numeric-owner -cf - $(for k in $AUDIO_KO; do basename $k; done) | \
    timeout 60 ssh $SSHO root@$IP "tar -x --no-same-owner -C /lib/modules/$KREL/extra && depmod -a $KREL && sync" || die "fallo al instalar los uke_audio_*.ko"
  timeout 60 ssh $SSHO root@$IP "KREL=$KREL KREL_V3=$KREL_V3 bash -s" <<'EOP'
K=/lib/modules/$KREL
echo "ko instalados ouke4: $(find $K -name '*.ko*' | wc -l)  (ouke3 intactos: $(find /lib/modules/$KREL_V3 -name '*.ko*' | wc -l))"
for m in qcom_battmgr qcom_q6v5_pas ath11k_ahb; do echo "$m: $(modinfo -k $KREL -F vermagic $m)"; done
ls $K/extra; ls /lib/modules
EOP
  echo '--pre hecho. Antes del flash: la sesion BT recompila/instala uke_bt_*.ko para ouke4 (deploy.sh). Luego el dueno pone fastboot (Power + Vol-).'
}

case "$MODE" in
  --check) pc_gates; echo "GATES DE PC OK"; exit 0;;
  --pre) pre; exit 0;;
  --post) post; exit 0;;
  --rollback)
    if [ "${2:-}" = v3 ]; then
      # 1 escritura: boot_a <- v3 (vigente antes de v4: todo arranca solo). Los modulos ouke3 siguen instalados. dtbo_a stock intacto.
      [ "$(sha256sum "$RB_V3" | cut -d' ' -f1)" = "$EB_V3" ] || die "rollback v3 SHA MISMATCH"
      fb_gates 3300
      flash_one boot_a "$RB_V3"
      timeout 20 fastboot set_active a 2>&1 | tail -1
      timeout 20 fastboot reboot 2>&1 | tail -1
      echo "v3 restaurada (boot_a = $EB_V3). Tras arrancar: SSH 192.168.42.129 (los modulos ouke3 siguen instalados)."
      exit 0
    fi
    if [ "${2:-}" = v2 ]; then
      # 1 escritura: boot_a <- v2 (display + USB; GPU solo en caliente). dtbo_a se queda stock.
      [ "$(sha256sum "$RB_V2" | cut -d' ' -f1)" = "$EB_V2" ] || die "rollback v2 SHA MISMATCH"
      fb_gates 3300
      flash_one boot_a "$RB_V2"
      timeout 20 fastboot set_active a 2>&1 | tail -1
      timeout 20 fastboot reboot 2>&1 | tail -1
      echo "v2 restaurada (boot_a = $EB_V2). Tras arrancar: SSH 192.168.42.129 (los modulos ouke2 siguen instalados)."
      exit 0
    fi
    if [ "${2:-}" = v1 ]; then
      # 1 escritura: boot_a <- la v1 (display OK, sin USB). dtbo_a se queda stock.
      [ "$(sha256sum "$RB_V1" | cut -d' ' -f1)" = "$EB_V1" ] || die "rollback v1 SHA MISMATCH"
      fb_gates 3300
      flash_one boot_a "$RB_V1"
      timeout 20 fastboot set_active a 2>&1 | tail -1
      timeout 20 fastboot reboot 2>&1 | tail -1
      echo "v1 restaurada (boot_a = $EB_V1). Sin USB/SSH por diseno: comprobar en el PANEL (terminal + 'uke-arch login')."
      exit 0
    fi
    case "${2:-}" in
      l77ba) RBI=$RB_L77BA; RBS=$EB_L77BA;; l76r) RBI=$RB_L76R; RBS=$EB_L76R;;
      *) die "uso: --rollback v3|v2|v1|l77ba|l76r";;
    esac
    [ "$(sha256sum "$RBI" | cut -d' ' -f1)" = "$RBS" ] || die "rollback boot SHA MISMATCH"
    [ "$(sha256sum "$DTBO_S288" | cut -d' ' -f1)" = "$ED_S288" ] || die "s288 backup SHA MISMATCH"
    fb_gates 3300
    flash_one dtbo_a "$DTBO_S288"
    flash_one boot_a "$RBI"
    timeout 20 fastboot set_active a 2>&1 | tail -1
    timeout 20 fastboot reboot 2>&1 | tail -1
    sleep 75; wait_ssh || { echo "sin SSH tras el rollback: mirar ACM"; exit 8; }
    timeout 60 ssh $SSHO root@$IP "uname -r; head -c $(stat -c%s "$RBI") /dev/disk/by-partlabel/boot_a | sha256sum; head -c 25165824 /dev/disk/by-partlabel/dtbo_a | sha256sum"
    echo "esperado: boot $RBS / dtbo $ED_S288"; exit 0;;
  flash) ;;
  *) die "modo desconocido: $MODE";;
esac

pc_gates
fb_gates 3700
# dtbo_a ya es el stock (v1). Verificacion previa por fetch si el bootloader lo soporta:
MF=$(timeout 15 fastboot getvar max-fetch-size 2>&1 | grep -oE '(0x[0-9a-fA-F]+|[0-9]+)$' | head -1)
if [ -n "${MF:-}" ] && [ "$((MF))" -gt 0 ] 2>/dev/null; then
  FT=/var/tmp/uke-dtbo_a-fetch-$TS.img
  if timeout 300 fastboot fetch dtbo_a "$FT" >/dev/null 2>&1 && [ -s "$FT" ]; then
    FH=$(head -c 25165824 "$FT" | sha256sum | cut -d' ' -f1); rm -f "$FT"
    [ "$FH" = "$ED_STOCK" ] || die "dtbo_a del aparato ($FH) != stock ($ED_STOCK): NO se flashea (con s288 el transform rechaza)" 9
    echo "  OK  dtbo_a del aparato == stock ($FH) por fastboot fetch"
  else
    echo "  AVISO: fastboot fetch dtbo_a fallo; se confia en la inferencia (v1 arranco con display => dtbo_a stock) y se relee por SSH en --post"
  fi
else
  echo "  AVISO: el bootloader no ofrece fastboot fetch (max-fetch-size='${MF:-ausente}'): dtbo_a no verificable ahora."
  echo "         Inferencia: la v1 arranco con display => su uke-abl.c admitio el DT => dtbo_a es el stock (con s288 rechazaria)."
  echo "         Relectura de dtbo_a por SSH en --post."
fi
echo '== 1 ESCRITURA: boot_a <- senemos v4 (dtbo_a NO se toca; slot b intacto) =='
# ===FLASH-PATH-BEGIN===
flash_one boot_a "$BOOT"
# ===FLASH-PATH-END===
timeout 20 fastboot set_active a 2>&1 | tail -1
[ "${PIPESTATUS[0]}" -eq 0 ] || die "set_active a fallo; NO reboot" 7
timeout 20 fastboot reboot 2>&1 | tail -1
echo '== esperar arranque (hasta ~4 min: fw_devlink por defecto y probes diferidos) =='
sleep 90
if ! wait_ssh; then
  echo "SIN SSH. Revisar ACM: tail -60 /var/tmp/uke-sesion-console.log (UKE-SENEMOS => DT rechazado; reinicia solo en 10 s)."
  echo "Si el panel muestra la terminal como en la v1 pero sigue sin USB: dwc3 no probo por OTRA causa (ver el informe,"
  echo "  seccion 'si sigue sin UDC': devices_deferred / diag_probe del PHY). Para volver: fastboot (Vol- + Power) y"
  echo "  --rollback v3 (1 escritura) o --rollback l77ba (2 escrituras)."
  exit 8
fi
post
