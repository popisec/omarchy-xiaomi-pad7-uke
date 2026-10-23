#!/bin/bash
# flash-senemos-v8a-gated.sh — «v8a» (23-oct-2026, sesion kernel-v8): v7 SIN recompilar (misma .config salvo INITRAMFS_SOURCE, misma
# release 7.2.9-senemos.1.4054.3-ouke5, MISMOS .ko; Image re-enlazado, banner #8) + initramfs nuevo (/ukeinit con ukeinit-v8.diff:
# e2fsck -p antes de montar + mount 'ro' SIN noload con respaldo 'ro,noload'; nunca reinicia) + cmdline sin 4 tokens muertos
# (hung_task_timeout_secs hung_task_panic watchdog_thresh printk.always_kmsg_dump=0) y con cpufreq.default_governor=schedutil.
# Derivado de flash-senemos-v7-gated.sh: MISMOS gates de PC (shas + admision del DT) y de fastboot (>=3700 mV, retry b >=3, lector ACM
# unico), UNA escritura (boot_a), dtbo_a stock intacto. NO hay modulos que instalar (misma release, misma ABI): sin --post-modules.
# Artefactos y pasos: build/gates/revision/KERNEL-V8-ARTEFACTOS-20261023.md. NO EJECUTADO NUNCA (solo --check, PC).
#
# NO EJECUTAR sin: (1) orden EXPRESA del dueno, (2) fila pre-registrada en el ledger hermano con el sha del boot v8a, (3) semaforo inter-proyecto
# libre, (4) presupuesto de escrituras (UNA: boot_a), (5) bateria >= 3700 mV en fastboot y cargador de pared, (6) fastboot puesto a mano por el
# dueno (Power + Vol-), (7) PRECONDICION v8a: fsck en frio hecho (fs `clean`, sin «with errors»): --pre lo comprueba por SSH (solo lectura).
#
# ORDEN:  0) --pre (tablet en v7, SSH, SOLO LECTURA): kernel v7 vivo + estado del rootfs (dumpe2fs -h)
#         1) apagado LIMPIO (poweroff) y el dueno pone fastboot a mano  2) bash build/gates/flash-senemos-v8a-gated.sh -> boot_a <- v8a
#         3) --post automatico (gates de v7 + G11 v8a: V8-FSCK, montaje sin norecovery, cmdline, schedutil)
# Rollback: --rollback v7 (1 escritura, boot_a <- 0f86cd77). OJO journal: si DESPUES de v8a se activo has_journal, antes de volver a v7
#   (que monta ro,noload y remonta rw SIN reproducir) hace falta apagado limpio o e2fsck en frio (propuesta §3).
# Uso: bash build/gates/flash-senemos-v8a-gated.sh [--check|--pre|--post|--rollback v7|v6|v5|...]
set -u
set -o pipefail
cd /home/USUARIO/proyectos/omarchy-uke || exit 1
BK=build/backup-par-bueno/android-20261017
BOOT=build/bootimg/boot-uke-senemos-7.2.9-v8a.img
EB=bd26d49671c42acf114431b64a9e4b68531c1d336c525674fdebcebc5971bad4
RB_V7=build/bootimg/boot-uke-senemos-7.2.9-v7.img
EB_V7=0f86cd77129ca643d97c6010fb8049cae2f807bedb82462228e492b6cb9650e4
RB_V6=build/bootimg/boot-uke-senemos-7.2.9-v6.img
EB_V6=a9641556168fbbe3055264b8a6456064d209e4c75df702e23863a36397ed9577
RB_V5=build/bootimg/boot-uke-senemos-7.2.9-v5.img
EB_V5=f3d3bc82b19e3a59bd5cab3351dc0a8317117a446f9e6f1d25e349ad1249d99b
RB_V4=build/bootimg/boot-uke-senemos-7.2.9-v4.img
EB_V4=fc9309a3953e8c423b30647b27a151aa740e6473757642ae922ec9cc0aaab88f
KREL_V4=7.2.9-senemos.1.4054.3-ouke4
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
KREL=7.2.9-senemos.1.4054.3-ouke5
OWN_KO_DIRS="build/rootfs/deploy/audio/out-ouke5 build/rootfs/deploy/bt/out"   # .ko propios (camara NO: se cargan a mano desde /root/uke-cam; en extra/ los autocarga udev y falsean las pruebas) (cada sesion los recompila para ouke5)
DT=build/kernel-pokes/senemos-7.2.9/dt
GEN=build/kernel-pokes/optim-ouke6/linux-7.2.9/native-generated-v2
KEY=build/rootfs/uke-arch-root
IP=${UKE_IP:-192.168.42.129}   # RNDIS (USB) por defecto, como v7; con Tailscale: UKE_IP=uke
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
  [ "$(sha256sum "$RB_V7" | cut -d' ' -f1)" = "$EB_V7" ] || die "rollback v7 SHA MISMATCH"
  [ "$(sha256sum "$RB_V6" | cut -d' ' -f1)" = "$EB_V6" ] || die "rollback v6 SHA MISMATCH"
  [ "$(sha256sum "$RB_V5" | cut -d' ' -f1)" = "$EB_V5" ] || die "rollback v5 (boot-uke-senemos-7.2.9-v5.img) SHA MISMATCH"
  [ "$(sha256sum "$RB_V4" | cut -d' ' -f1)" = "$EB_V4" ] || die "rollback v4 (boot-uke-senemos-7.2.9-v4.img) SHA MISMATCH"
  [ "$(sha256sum "$RB_V3" | cut -d' ' -f1)" = "$EB_V3" ] || die "rollback v3 (boot-uke-senemos-7.2.9-v3.img) SHA MISMATCH"
  [ "$(sha256sum "$RB_V2" | cut -d' ' -f1)" = "$EB_V2" ] || die "rollback v2 (boot-uke-senemos-7.2.9-v2.img) SHA MISMATCH"
  [ "$(sha256sum "$BOOT" | cut -d' ' -f1)" = "$EB" ] || die "BOOT SHA MISMATCH"
  [ "$(sha256sum "$DTBO_STOCK" | cut -d' ' -f1)" = "$ED_STOCK" ] || die "DTBO STOCK SHA MISMATCH"
  [ "$(sha256sum "$DTBO_S288" | cut -d' ' -f1)" = "$ED_S288" ] || die "DTBO s288 (rollback) SHA MISMATCH"
  [ "$(sha256sum "$RB_V1" | cut -d' ' -f1)" = "$EB_V1" ] || die "rollback v1 (boot-uke-senemos-7.2.9.img) SHA MISMATCH"
  [ "$(sha256sum "$RB_L77BA" | cut -d' ' -f1)" = "$EB_L77BA" ] || die "rollback L77b-a SHA MISMATCH"
  [ "$(sha256sum "$RB_L76R" | cut -d' ' -f1)" = "$EB_L76R" ] || die "rollback L76R SHA MISMATCH"
  [ "$(stat -c%s "$DTBO_STOCK")" = 25165824 ] || die "dtbo stock no mide 24 MiB (particion completa)"
  # v8a: cabecera del boot = cmdline de v7 sin los 4 tokens muertos + schedutil al final; kernel == Image.gz de build8a; release ouke5 #8
  python3 -I - "$BOOT" "$RB_V7" <<'EOF' || exit 2
import gzip, hashlib, struct, sys
b, v7 = open(sys.argv[1], 'rb').read(), open(sys.argv[2], 'rb').read()
cmd = lambda x: x[44:44 + 1536].split(b'\0')[0].split()
c8, c7 = cmd(b), cmd(v7)
q = [b'hung_task_timeout_secs=20', b'hung_task_panic=0', b'watchdog_thresh=10', b'printk.always_kmsg_dump=0']
assert [t for t in c7 if t not in c8] == q, 'tokens quitados inesperados'
assert [t for t in c8 if t not in c7] == [b'cpufreq.default_governor=schedutil'] and c8[-1] == b'cpufreq.default_governor=schedutil'
ks = struct.unpack_from('<I', b, 8)[0]
k = b[4096:4096 + ks]
assert hashlib.sha256(k).hexdigest() == 'f3d19271f02f5b5cc9e6ddc32965ed7616eb0ae918ddbbe1d57b01ccf0e124e2', 'kernel != Image.gz build8a'
raw = gzip.decompress(k)
assert b'Linux version 7.2.9-senemos.1.4054.3-ouke5 (omarchy-uke@pc) (clang version 23.1.3, LLD 23.1.3) #8 SMP PREEMPT 2026-10-23' in raw
cp = open('build/kernel-pokes/optim-ouke6/v8a/uke-k34-fw-v8a-initramfs.cpio.gz', 'rb').read()
assert hashlib.sha256(cp).hexdigest() == 'af355bb9e46df36ac969473bfdb4d29ded3c4f7e756521fd60bc31d1d5d21591', 'cpio v8a sha'
assert raw.count(cp) == 1, 'cpio v8a (af355bb9) no embebido byte a byte en el Image'
d = gzip.decompress(cp)
assert b'V8-FSCK: rc=' in d and b'bin/e2fsck\0' in d
print('  OK  boot v8a: cmdline = v7 - 4 tokens muertos + schedutil; kernel = Image.gz build8a (f3d19271); release ouke5 #8; cpio v8a af355bb9 embebido byte a byte')
EOF
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
  [ "$R1" = "$EB" ] && echo "  OK  boot_a == senemos v8a ($R1)" || echo "  *** boot_a releido '${R1:-vacio}' != $EB ***"
  R2=$(timeout 60 ssh $SSHO root@$IP "head -c 25165824 /dev/disk/by-partlabel/dtbo_a | sha256sum" 2>/dev/null | cut -d' ' -f1)
  [ "$R2" = "$ED_STOCK" ] && echo "  OK  dtbo_a == stock ($R2)" || echo "  *** dtbo_a releido '${R2:-vacio}' != $ED_STOCK ***"
  timeout 300 ssh $SSHO root@$IP "KREL=$KREL TS=$TS V8_MODETEST=${V8_MODETEST:-0} bash -s" <<'EOS' 2>&1 | tee build/logs/senemos-post-$TS.txt | tail -150
exec 2>&1
dmesg -n 7 2>/dev/null
OK=0; NG=0
g() { if [ "$2" = 1 ]; then echo "  PASA  $1"; OK=$((OK+1)); else echo "  FALLA $1"; NG=$((NG+1)); fi; }
dmesg > /root/dmesg-senemos-$TS.txt
D=/root/dmesg-senemos-$TS.txt
echo "== G1 identidad del kernel y del DT =="
echo "uname: $(uname -r)"; [ "$(uname -r)" = "$KREL" ] && g "uname -r = $KREL" 1 || g "uname -r = $KREL" 0
echo "uname -v: $(uname -v)"; case "$(uname -v)" in "#8 "*2026-10-23*) g "banner v8a (#8, 2026-10-23)" 1;; *) g "banner v8a (#8, 2026-10-23)" 0;; esac
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
[ "${V8_MODETEST:-0}" = 1 ] && { systemctl stop sddm 2>/dev/null; systemctl stop display-manager 2>/dev/null; }
modetest -M msm-kms -c 2>&1 | head -30
modetest -M msm-kms -e 2>&1 | head -12
CON=$(modetest -M msm-kms -c 2>/dev/null | awk '$3=="connected" && $4 ~ /^DSI/ {print $1; exit}')
CRTC=$(modetest -M msm-kms -p 2>/dev/null | awk '/^CRTCs:/{f=1;next} f && $1 ~ /^[0-9]+$/ {print $1; exit}')
echo "conector DSI=${CON:-?} crtc=${CRTC:-?} (modo #0 = preferido, 120 Hz)"
if [ "${V8_MODETEST:-0}" != 1 ]; then
  echo "  (v8a: modetest OMITIDO por defecto: el codigo del display es el de v7 byte a byte y modetest quita el maestro DRM al escritorio; V8_MODETEST=1 para correrlo)"
elif [ -n "$CON" ] && [ -n "$CRTC" ]; then
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
echo "== G7 (v7) release, SMMU y servicios que ya arrancaban solos en v4 =="
[ "$(uname -r)" = "$KREL" ] && g "release $KREL" 1 || g "release $KREL" 0
grep -aE "Unhandled (context|stream) fault|outside Uke boot SMMU scope" $D | head -5
grep -aqE "Unhandled (context|stream) fault|outside Uke boot SMMU scope" $D && g "sin faults ni rechazos del SMMU en el arranque" 0 || g "sin faults ni rechazos del SMMU en el arranque" 1
sleep 25   # WiFi/escritorio llegan ~26 s tras el arranque (uke-bootguard)
[ "$(cat /sys/class/net/wlan0/operstate 2>/dev/null)" = up ] && g "wlan0 up (WiFi al arranque)" 1 || g "wlan0 up (WiFi al arranque)" 0
systemctl is-active -q uke-wifi.service && g "uke-wifi.service activo" 1 || g "uke-wifi.service activo" 0
systemctl is-active -q uke-desktop.service && g "uke-desktop.service activo" 1 || g "uke-desktop.service activo" 0
systemctl is-active -q uke-touch.service && g "uke-touch.service activo" 1 || g "uke-touch.service activo" 0
[ "$(cat /sys/class/remoteproc/remoteproc1/state 2>/dev/null)" = running ] && g "ADSP running (recovery $(cat /sys/class/remoteproc/remoteproc1/recovery))" 1 || g "ADSP running" 0
echo "== G8 (v5) rieles de camara admitidos por 0045 (deben existir, DESHABILITADOS, con su tension) =="
for want in pmxr2230_l20:1800000 pmr735a_l6:1200000 pm_v6c_l3:1200000; do
  rn=${want%%:*}; rv=${want##*:}; found=0
  for d in /sys/class/regulator/regulator.*; do
    [ "$(cat $d/name 2>/dev/null)" = "$rn" ] || continue
    found=1; st=$(cat $d/state); uv=$(cat $d/microvolts 2>/dev/null); echo "  $rn state=$st microvolts=${uv:-?} users=$(cat $d/num_users)"
    [ "$st" = disabled ] && g "$rn disabled" 1 || g "$rn disabled (state=$st)" 0
    [ "${uv:-0}" = "$rv" ] && g "$rn = $rv uV" 1 || g "$rn = $rv uV (leido ${uv:-?})" 0
  done
  [ "$found" = 1 ] || g "$rn presente en /sys/class/regulator" 0
done
grep -aE "rpmh-regulator-(ldob20|ldoe6|ldoc3)" $D | grep -aiE "fail|error|could not" | head -5
for r in pmxr2230_l2 pmxr2230_l4 pmxr2230_s2 pm_v8_s6_level pm_v6c_s6_level; do for d in /sys/class/regulator/regulator.*; do [ "$(cat $d/name 2>/dev/null)" = "$r" ] && echo "  (ref) $r state=$(cat $d/state) uv=$(cat $d/microvolts 2>/dev/null) users=$(cat $d/num_users)"; done; done
echo "== G9 (v7) optimizacion y red =="
grep -q 'cpuidle.governor=teo' /proc/cmdline && grep -q 'audit=0' /proc/cmdline && g "cmdline v7 (cpuidle.governor=teo audit=0)" 1 || g "cmdline v7 (cpuidle.governor=teo audit=0)" 0
[ "$(cat /sys/devices/system/cpu/cpuidle/current_governor 2>/dev/null)" = teo ] && g "cpuidle current_governor = teo" 1 || g "cpuidle current_governor = teo ($(cat /sys/devices/system/cpu/cpuidle/current_governor 2>/dev/null))" 0
echo "audit: $(auditctl -s 2>&1 | head -1) | lineas audit en dmesg: $(grep -ac 'audit:' $D)"
echo "cpuidle uso cpu0: $(cat /sys/devices/system/cpu/cpu0/cpuidle/state*/usage | tr '\n' ' ')"
for m in uke-bt uke-audio; do if [ -e /etc/uke/no-${m#uke-} ]; then echo "  (omitido $m: interruptor /etc/uke/no-${m#uke-})"; else systemctl is-active -q $m.service && g "$m.service activo" 1 || g "$m.service activo" 0; fi; done
echo "== G10 (slot) uke-boot-ok / qbootctl (aviso del 22-oct: el servicio marca el slot como correcto 90 s tras arrancar sano) =="
echo "uke-boot-ok.service: $(systemctl is-enabled uke-boot-ok.service 2>&1) / $(systemctl is-active uke-boot-ok.service 2>&1)"
qbootctl 2>/dev/null | head -14      # sin argumentos: `qbootctl -a` da «Couldn't find cmdline arg: slot_suffix» (el kernel no pasa androidboot.slot_suffix)
echo "(informativo ahora: el servicio actua a los ~90 s; comprobar a mano Successful=1 del slot activo con qbootctl a los >90 s)"
echo "== G11 (v8a) initramfs V8 (e2fsck -p + mount ro sin noload) y cmdline =="
grep -a 'V8-FSCK\|V8-MNT\|S123: mount' $D | head -14
grep -aqE 'V8-FSCK: rc=[01] ' $D && g "V8-FSCK rc 0|1 (fs limpio o corregido en preen)" 1 || g "V8-FSCK rc 0|1 ($(grep -aoE 'V8-FSCK: rc=[0-9]+' $D | head -1))" 0
FT=$(grep -aoE 'V8-FSCK: rc=[0-9]+ t=[0-9]+s' $D | grep -oE '[0-9]+s$' | tr -d s); F0=$(grep -aoE 'V8-FSCK: e2fsck -p .* ARRANCA t=[0-9]+s' $D | grep -oE '[0-9]+s$' | tr -d s)
echo "duracion e2fsck: $(( ${FT:-0} - ${F0:-0} )) s (t=${F0:-?}..${FT:-?})"
grep -aq 'V8-MNT AVISO' $D && g "mount 'ro' a la primera (sin respaldo ro,noload)" 0 || g "mount 'ro' a la primera (sin respaldo ro,noload)" 1
grep -aq 'S123: mount ro OK' $D && g "S123: mount ro OK" 1 || g "S123: mount ro OK" 0
grep -aE 'EXT4-fs \(sda32\): mounted filesystem' $D | head -2
O=$(findmnt -no OPTIONS /); echo "findmnt /: $O"
case ",$O," in *,norecovery,*|*,noload,*) g "findmnt / SIN norecovery" 0;; *) g "findmnt / SIN norecovery" 1;; esac
NE=$(grep -ac 'EXT4-fs error' $D); [ "$NE" = 0 ] && g "0 'EXT4-fs error' en este arranque" 1 || g "0 'EXT4-fs error' en este arranque ($NE)" 0
dumpe2fs -h /dev/sda32 2>/dev/null | grep -E 'features|state|FS Error count|Mount count|Last checked'
C=$(cat /proc/cmdline)
case " $C " in *" hung_task_"*|*" watchdog_thresh="*|*" printk.always_kmsg_dump=0 "*) g "cmdline sin los 4 tokens muertos" 0;; *) g "cmdline sin los 4 tokens muertos" 1;; esac
case " $C " in *" cpufreq.default_governor=schedutil "*) g "cmdline con cpufreq.default_governor=schedutil" 1;; *) g "cmdline con cpufreq.default_governor=schedutil" 0;; esac
grep -a 'Unknown kernel command line parameters' $D | head -1
grep -a 'Unknown kernel command line parameters' $D | grep -qE 'hung_task|watchdog_thresh' && g "dmesg sin 'Unknown ... hung_task/watchdog_thresh'" 0 || g "dmesg sin 'Unknown ... hung_task/watchdog_thresh'" 1
echo "governors: $(cat /sys/devices/system/cpu/cpufreq/policy*/scaling_governor 2>/dev/null | tr '\n' ' ')"
[ -z "$(cat /sys/devices/system/cpu/cpufreq/policy*/scaling_governor 2>/dev/null | grep -v '^schedutil$')" ] && g "todas las politicas en schedutil" 1 || g "todas las politicas en schedutil" 0
echo "SENEMOS-GATES: $OK PASA / $NG FALLA"
sync
EOS
  timeout 60 scp $SSHO root@$IP:/root/dmesg-senemos-$TS.txt build/logs/ 2>/dev/null && echo "dmesg copiado a build/logs/dmesg-senemos-$TS.txt"
  echo '== CRITERIO PREFIJADO v8a (= v7 + G11) =='
  echo '  PASA  = SSH + G1-G10 como v7 (release ouke5 #8, sin faults de SMMU, GPU, WiFi, escritorio) + G11: V8-FSCK rc 0|1, mount ro sin respaldo,'
  echo '          findmnt / sin norecovery, 0 EXT4-fs error, cmdline sin tokens muertos y con schedutil; y uke-boot-ok -> Successful=1 a los ~90 s (qbootctl).'
  echo '  V8-FSCK rc>=4 o V8-MNT AVISO => NO es fallo de arranque (la tablet sigue), pero hay que hacer el fsck en frio antes de nada mas.'
  echo '  G6 FALLA con lo demas bien => otra dependencia tardia de la GPU: devices_deferred / dmesg kgsl-smmu (no reflashear a ciegas).'
  echo '  Abrir la GPU (sesion Omarchy) es OTRO paso, con orden del dueno: build/rootfs/deploy/omarchy/deploy.sh start --go'
  echo '  Volver: apagado limpio, fastboot a mano (Power+Vol-)  y  bash build/gates/flash-senemos-v8a-gated.sh --rollback v7   (modulos: nada que hacer, misma release)'
}

pre() {
  echo '== --pre (tablet en v7, por SSH, SOLO LECTURA): kernel vivo y estado del rootfs. No escribe nada =='
  pc_gates >/dev/null || die "gates de PC fallan (corre --check)"
  timeout 20 ssh $SSHO root@$IP 'uname -r; uname -v' | tr '\n' ' ' | grep -q "$KREL #7 " || die "la tablet no corre v7 ($KREL #7) o sin SSH"
  local ST
  ST=$(timeout 30 ssh $SSHO root@$IP 'dumpe2fs -h /dev/sda32 2>/dev/null | grep -E "^(Filesystem features|Filesystem state|FS Error count|Mount count|Last checked):"; findmnt -no OPTIONS /') || die "sin dumpe2fs por SSH"
  echo "$ST"
  if echo "$ST" | grep -q 'with errors'; then
    [ "${FORCE_DIRTYFS:-0}" = 1 ] || die "rootfs 'with errors': hacer ANTES el fsck en frio (build/rootfs/deploy/optimizacion/fsck-journal.sh pre -> backup -> fsck); FORCE_DIRTYFS=1 solo con orden del dueno (el primer arranque v8a haria un e2fsck -p completo, duracion sin medir)"
    echo "AVISO: FORCE_DIRTYFS=1 con el fs 'with errors'"
  fi
  echo "$ST" | grep -q has_journal && echo "AVISO: el fs YA tiene has_journal: v8a lo cargara y reproducira (esperado si el orden fue journal antes de v8a)"
  echo "--pre hecho. Siguiente: pre-registrar la fila del ledger, poweroff LIMPIO, fastboot a mano y bash build/gates/flash-senemos-v8a-gated.sh"
}

case "$MODE" in
  --check) pc_gates; echo "GATES DE PC OK"; exit 0;;
  --pre) pre; exit 0;;
  --post) post; exit 0;;
  --rollback)
    if [ "${2:-}" = v7 ]; then
      # 1 escritura: boot_a <- v7 (vigente antes de v8a, misma release, mismos modulos). dtbo_a stock intacto.
      echo "OJO: si tras v8a se activo has_journal, v7 (ro,noload + remount rw) NO reproduce el journal: llegar aqui desde un apagado LIMPIO."
      [ "$(sha256sum "$RB_V7" | cut -d' ' -f1)" = "$EB_V7" ] || die "rollback v7 SHA MISMATCH"
      fb_gates 3300
      flash_one boot_a "$RB_V7"
      timeout 20 fastboot set_active a 2>&1 | tail -1
      timeout 20 fastboot reboot 2>&1 | tail -1
      echo "v7 restaurada (boot_a = $EB_V7). Tras arrancar: SSH; nada que hacer con los modulos (misma release ouke5)."
      exit 0
    fi
    if [ "${2:-}" = v6 ]; then
      # 1 escritura: boot_a <- v6 (vigente antes de v7, misma release). dtbo_a stock intacto. Despues: --rollback-modules por SSH.
      [ "$(sha256sum "$RB_V6" | cut -d' ' -f1)" = "$EB_V6" ] || die "rollback v6 SHA MISMATCH"
      fb_gates 3300
      flash_one boot_a "$RB_V6"
      timeout 20 fastboot set_active a 2>&1 | tail -1
      timeout 20 fastboot reboot 2>&1 | tail -1
      echo "v6 restaurada (boot_a = $EB_V6). Tras arrancar: SSH y bash build/gates/flash-senemos-v7-gated.sh --rollback-modules (modulos de v7 en release v6)"
      exit 0
    fi
    if [ "${2:-}" = v5 ]; then
      # 1 escritura: boot_a <- v5 (vigente antes de v6, misma release). dtbo_a stock intacto.
      [ "$(sha256sum "$RB_V5" | cut -d' ' -f1)" = "$EB_V5" ] || die "rollback v5 SHA MISMATCH"
      fb_gates 3300
      flash_one boot_a "$RB_V5"
      timeout 20 fastboot set_active a 2>&1 | tail -1
      timeout 20 fastboot reboot 2>&1 | tail -1
      echo "v5 restaurada (boot_a = $EB_V5). Tras arrancar: SSH 192.168.42.129."
      exit 0
    fi
    if [ "${2:-}" = v4 ]; then
      # 1 escritura: boot_a <- v4 (vigente antes de v5). Los modulos ouke4 siguen instalados. dtbo_a stock intacto.
      [ "$(sha256sum "$RB_V4" | cut -d' ' -f1)" = "$EB_V4" ] || die "rollback v4 SHA MISMATCH"
      fb_gates 3300
      flash_one boot_a "$RB_V4"
      timeout 20 fastboot set_active a 2>&1 | tail -1
      timeout 20 fastboot reboot 2>&1 | tail -1
      echo "v4 restaurada (boot_a = $EB_V4). Tras arrancar: SSH 192.168.42.129 (los modulos ouke4 siguen instalados)."
      exit 0
    fi
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
      *) die "uso: --rollback v7|v6|v5|v4|v3|v2|v1|l77ba|l76r";;
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
echo '== 1 ESCRITURA: boot_a <- senemos v8a (dtbo_a NO se toca; slot b intacto) =='
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
  echo "  --rollback v7 (1 escritura; misma release, mismos modulos)."
  exit 8
fi
post
