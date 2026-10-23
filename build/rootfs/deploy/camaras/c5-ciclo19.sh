#!/usr/bin/env bash
# c5-ciclo19.sh — C5b ciclo 19 (22-oct-2026): foto enfocada de la trasera. Mismos modulos que el ciclo 18 (VCM CN3927V en 0x0c, ACK confirmado).
# Auto-exposicion simple en la tablet (ukeaf.py mean: verdes del centro) y autofoco por contraste (ukeaf.py sharp): barrido grueso 0..1023
# paso 64 + fino +-48 paso 16. Guarda el mejor frame (b19-best.raw) y los extremos. Uso: ./c5-ciclo19.sh --check | --go (solo insmod/rmmod)
set -u
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../.." && pwd); D=$HERE/out-ciclo16
HOST=${UKE_HOST:-root@uke}
SSH=(ssh -o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=4 -i "$R/build/rootfs/uke-arch-root" -o BatchMode=yes "$HOST")
F="uke_cam_camcc.ko camcc-cliffs-uke.ko uke_cam_rear.ko uke_ov13b10.ko uke_cam_camss.ko uke-camss.ko uke_rpmh_ldob14.ko uke_cam_vcm.ko uke_vcm.ko ukeaf.py"
MODS="uke_vcm uke_cam_vcm uke_rpmh_ldob14 uke_camss uke_cam_camss uke_ov13b10 i2c_qcom_cci uke_cam_rear camcc_cliffs_uke uke_cam_camcc"
cd "$D" || exit 2
for f in uke_rpmh_ldob14.ko uke_cam_vcm.ko uke_vcm.ko; do cp -f "$HERE/out-ciclo18/$f" . || exit 2; done
cp -f "$HERE/ukeaf.py" . || exit 2
for f in $F; do [ -s "$f" ] || { echo "falta $f"; exit 2; }; done
[ "$(modinfo -F vermagic uke-camss.ko | cut -d' ' -f1)" = "7.2.9-senemos.1.4054.3-ouke5" ] || { echo "vermagic != ouke5"; exit 2; }
for p in uke_statline uke_stat uke_cap_ctrl uke_rx_mask; do modinfo -F parm uke-camss.ko | grep -q "^$p:" || { echo "falta parametro $p"; exit 2; }; done
modinfo -F parm uke_ov13b10.ko | grep -q "^uke_xreg:" || { echo "uke_ov13b10.ko sin la sonda (UKE_SENSDBG)"; exit 2; }
if [ "${1:-}" != "--go" ]; then echo "check OK (vermagic ouke5)"; sha256sum $F | cut -c1-16,65-; exit 0; fi
OUT=$HERE/out/c5-ciclo19-$(date +%Y%m%d-%H%M).txt; exec > >(tee "$OUT") 2>&1
echo "# C5b ciclo 19 $(date -Is) host=$HOST"
BAT=$("${SSH[@]}" 'cat /sys/class/power_supply/qcom-battmgr-bat/capacity') || { echo "ABORTO: sin ssh"; exit 3; }; echo "bateria=$BAT %"; [ "$BAT" -ge 30 ] || { echo "ABORTO: bateria < 30 %"; exit 3; }
[ "$("${SSH[@]}" 'lsmod | grep -cE "uke_cam|camcc|uke_camss|ov13|i2c_qcom_cci|uke_vcm|ldob14"')" = 0 ] || { echo "ABORTO: ya hay modulos de camara cargados"; exit 3; }
TMPR=$(mktemp); tar cf - $F | "${SSH[@]}" 'rm -rf /root/uke-cam; mkdir -p /root/uke-cam; tar xf - -C /root/uke-cam 2>/dev/null; cd /root/uke-cam && sha256sum *.ko ukeaf.py' | sort -k2 > "$TMPR"
sha256sum $F | sort -k2 | diff - "$TMPR" && echo "sha iguales" || { echo "ABORTO: sha distintos"; exit 3; }
DL=$HERE/out/c5c19-dmesg-$(date +%H%M).log; "${SSH[@]}" 'dmesg -w' > "$DL" 2>&1 &
DP=$!
pc_cleanup() { kill "$DP" 2>/dev/null; "${SSH[@]}" "for m in $MODS; do rmmod \$m 2>/dev/null; done; pkill -f 'why=C5c19' 2>/dev/null; echo \"limpieza PC: restan \$(lsmod | grep -cE 'uke_cam|camcc|uke_camss|ov13|i2c_qcom_cci|uke_vcm|ldob14')\"" 2>/dev/null; rm -f "$TMPR"; }
trap pc_cleanup EXIT INT TERM; sleep 2
"${SSH[@]}" "bash -s" <<'REMOTE'
U=/root/uke-cam; MODS="uke_vcm uke_cam_vcm uke_rpmh_ldob14 uke_camss uke_cam_camss uke_ov13b10 i2c_qcom_cci uke_cam_rear camcc_cliffs_uke uke_cam_camcc"
pkill -f "why=C5c" 2>/dev/null; (setsid nohup systemd-inhibit --what=sleep:idle --who=camara --why=C5c19 sleep 1500 >/dev/null 2>&1 &)
unl() { pkill -f "v4l2-ctl -d /dev/video0" 2>/dev/null; sleep 0.5; for m in $MODS; do rmmod $m 2>/dev/null; done; pkill -f "why=C5c19" 2>/dev/null; }
trap unl EXIT HUP TERM INT
rm -f /root/b19-*.raw /root/c19.raw
dmesg -n 7
echo ac15000.qcom,cci0 > /sys/bus/platform/drivers/simple-pm-bus/unbind 2>/dev/null; echo i2c-qcom-cci > /sys/bus/platform/devices/ac15000.qcom,cci0/driver_override
for m in mc videodev v4l2-async v4l2-fwnode videobuf2-common videobuf2-v4l2 videobuf2-dma-sg; do modprobe $m; done
insmod $U/uke_cam_camcc.ko; insmod $U/camcc-cliffs-uke.ko ungate=1; insmod $U/uke_cam_rear.ko; modprobe i2c-qcom-cci; insmod $U/uke_ov13b10.ko; sleep 3
echo "chip: $(dmesg | grep -a 'chip id' | tail -1 | cut -c20-120)"
insmod $U/uke_cam_camss.ko; insmod $U/uke-camss.ko; sleep 4
[ -e /dev/media0 ] || { echo "ABORTO: sin /dev/media0"; exit 4; }
M="media-ctl -d /dev/media0"
$M -l "\"msm_csiphy1\":1->\"msm_csid0\":0[1]"; $M -l "\"msm_csid0\":1->\"msm_vfe0_rdi0\":0[1]"
F="fmt:SGRBG10_1X10/2104x1560"
$M -V "\"ov13b10 7-0010\":0[$F],\"msm_csiphy1\":0[$F],\"msm_csiphy1\":1[$F],\"msm_csid0\":0[$F],\"msm_csid0\":1[$F],\"msm_vfe0_rdi0\":0[$F],\"msm_vfe0_rdi0\":1[$F]"
v4l2-ctl -d /dev/video0 --set-fmt-video=width=2104,height=1560,pixelformat=pgAA | head -1
SUB=$($M -p -e "ov13b10 7-0010" | awk '/device node name/{print $NF; exit}'); echo "subdev del sensor: $SUB"
P=/sys/module/uke_camss/parameters; S=/sys/module/uke_ov13b10/parameters
echo -1 > $P/uke_settle; echo 0 > $P/uke_skew; echo -1 > $P/uke_lane_assign; echo 0 > $S/uke_dump
echo 1 > $P/uke_stat; echo 0 > $P/uke_cap_n; echo 0 > $P/uke_rx_budget; echo 0 > $P/uke_rdi_budget; echo -1 > $P/uke_cap_ctrl
echo $((0xfffffff0)) > $P/uke_rx_mask
CK=/sys/kernel/debug/clk
saved=0; n=0; full=0
try() {  # $1 etiqueta  $2 vblank  $3 exposicion (lineas; max = alto+vblank-8)  $4 ganancia analogica (0x80=1x .. 0x7c0)  $5 ganancia digital (1024=1x)
  n=$((n+1)); echo "######## $n $1"
  echo -1 > $S/uke_xreg
  v4l2-ctl -d $SUB -c test_pattern=0 -c vertical_blanking=$2 2>&1 | head -1
  v4l2-ctl -d $SUB -c exposure=$3 -c analogue_gain=$(($4)) -c digital_gain=$5 2>&1 | head -1
  echo "ctrl: $(v4l2-ctl -d $SUB -C vertical_blanking,exposure,analogue_gain,digital_gain 2>&1 | tr '\n' ' ')"
  rm -f /root/c18.raw
  timeout 12 v4l2-ctl -d /dev/video0 --stream-mmap=3 --stream-skip=2 --stream-count=1 --stream-to=/root/c18.raw > /root/c18.v4l 2>&1
  tail -1 /root/c18.v4l
  BY=$(stat -c %s /root/c18.raw 2>/dev/null || echo 0)
  head -c 600 $P/uke_statline | head -3
  if [ "$BY" -gt 0 ]; then
    NZ=$(tr -d '\000' < /root/c18.raw | wc -c); SH=$(sha256sum /root/c18.raw | cut -c1-16)
    echo "BUF $1 bytes=$BY nonzero=$NZ sha=$SH"
    [ "$NZ" -gt 2000000 ] && full=$((full+1))
    if [ $saved -lt 20 ]; then saved=$((saved+1)); cp /root/c18.raw /root/b18-$saved.raw; echo "GUARDADO b18-$saved.raw ($1)"; fi
  else echo "BUF $1 bytes=0"; fi
}
V=/sys/module/uke_vcm/parameters
insmod $U/uke_rpmh_ldob14.ko; sleep 1; echo "l14: $(for r in /sys/class/regulator/*; do [ "$(cat $r/name)" = pmxr2230_l14 ] && echo "$(cat $r/state) $(cat $r/microvolts 2>/dev/null)uV"; done)"
insmod $U/uke_cam_vcm.ko; sleep 2; insmod $U/uke_vcm.ko; sleep 2
[ -d $V ] || { echo "ABORTO: uke_vcm no cargo"; exit 5; }
echo "vcm: $(dmesg | grep -a 'uke-vcm' | cut -c15-200 | tr '\n' '|')"
echo "found: $(cat $V/found)"
T=""; for x in $(cat $V/found); do a=${x%%=*}; case $a in 0x10|0x5[0-7]) ;; *) [ -z "$T" ] && T=$a;; esac; done
echo "objetivo VCM: ${T:-ninguno}"
[ -n "$T" ] || { echo "ABORTO: ninguna direccion candidata respondio (no se escribe nada)"; exit 5; }
echo $((T)) > $V/tgt
echo 0 > $V/dac; echo "dac=0 lastret=$(cat $V/lastret)"
[ "$(cat $V/lastret)" = 1 ] || { echo "ABORTO: el VCM no da ACK a la escritura"; exit 5; }
AF="python3 -I $U/ukeaf.py"
cap() {  # $1 vblank $2 exp $3 ag $4 dg -> /root/c19.raw completo
  v4l2-ctl -d $SUB -c test_pattern=0 -c vertical_blanking=$1 >/dev/null 2>&1
  v4l2-ctl -d $SUB -c exposure=$2 -c analogue_gain=$3 -c digital_gain=$4 >/dev/null 2>&1
  rm -f /root/c19.raw; timeout 12 v4l2-ctl -d /dev/video0 --stream-mmap=3 --stream-skip=2 --stream-count=1 --stream-to=/root/c19.raw >/dev/null 2>&1
  [ "$(stat -c %s /root/c19.raw 2>/dev/null || echo 0)" = 4118400 ]
}
echo 256 > $V/dac; VB=1636; EX=3188; AG=128; DG=1024
for k in 1 2 3 4 5 6 7 8; do
  cap $VB $EX $AG $DG || { echo "AE: captura fallida"; continue; }
  M=$($AF mean /root/c19.raw); echo "AE $k: exp=$EX ag=$AG dg=$DG -> media8=$M"
  read EX AG <<<"$(awk -v m="$M" -v e=$EX -v a=$AG 'BEGIN{ if (m>=70 && m<=140) {print "OK", a; exit}
     if (m>=250) f=0.125; else { d=m-15; if (d<1) d=1; f=100/d }
     ne=int(e*f); na=a; if (ne>3188) { na=int(a*ne/3188); ne=3188; if (na>1984) na=1984 } if (ne<4) ne=4
     if (na>128 && f<1) { na=int(a*f); if (na<128) na=128; ne=e } print ne, na }')"
  if [ "$EX" = OK ]; then EX=$(v4l2-ctl -d $SUB -C exposure | awk '{print $2}'); echo "AE: fijada exp=$EX ag=$AG"; break; fi
done
best=-1; bs=-1
af() {  # $1 dac
  echo $1 > $V/dac 2>/dev/null; sleep 0.05
  cap $VB $EX $AG $DG || { echo "AF dac=$1 captura fallida"; return; }
  s=$($AF sharp /root/c19.raw); m=$($AF mean /root/c19.raw); echo "AF dac=$1 nitidez=$s media8=$m"
  [ "$s" -gt "$bs" ] && { bs=$s; best=$1; cp /root/c19.raw /root/b19-best.raw; }
  case $1 in 0) cp /root/c19.raw /root/b19-dac0.raw;; 1023) cp /root/c19.raw /root/b19-dac1023.raw;; esac
}
for d in 0 64 128 192 256 320 384 448 512 576 640 704 768 832 896 960 1023; do af $d; done
c=$best; echo "AF grueso: mejor dac=$c nitidez=$bs"
for d in $((c-48)) $((c-32)) $((c-16)) $((c+16)) $((c+32)) $((c+48)); do [ $d -ge 0 ] && [ $d -le 1023 ] && af $d; done
echo "AF final: mejor dac=$best nitidez=$bs exp=$EX ag=$AG dg=$DG"
saved=3; full=1
echo 0 > $V/dac 2>/dev/null
echo "buffers guardados: $saved  casi-completos(>2MB no nulos): $full"
echo "fallos SMMU/oops: $(dmesg | grep -acE 'Unhandled (context|stream) fault|Oops')"
echo "=== descarga"
trap - EXIT; unl
echo "restan $(lsmod | grep -cE 'uke_cam|camcc|uke_camss|ov13|i2c_qcom_cci|uke_vcm|ldob14')"
REMOTE
"${SSH[@]}" 'cd /root && ls b19-*.raw 2>/dev/null | xargs -r tar cf -' | { rm -f "$HERE"/out/b19-*.raw; tar xf - -C "$HERE/out/" 2>/dev/null; }; ls -l "$HERE"/out/b19-*.raw 2>/dev/null
echo "# fin; dmesg completo en $DL"
