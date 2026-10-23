#!/usr/bin/env bash
# c5-ciclo23.sh — C5b ciclo 23 (22-oct-2026): PRIMERA prueba de la FRONTAL OV08D10 (bus GENI i2c@880000, MCLK4, csiphy4, 2 lanes) en caliente.
# Modulos out-ciclo23 (camss como qcom-camss; uke_ov08d10 con reset por pinctrl; overlay frontal con titan_top y sin hijos vendor).
# Orden de overlays: camcc -> rear -> camss -> front (front apunta a &camss y su port@4 debe existir antes de que camss sondee).
# Ruta: csiphy4 -> csid0 -> vfe0_rdi0 -> msm_vfe0_video0 (la misma que usara Megapixels; 1.a ejecucion con vfe1: nodo de video mal elegido). Patron de test + imagen real en 1632x1224 y 3264x2448. Turno «camaras-2» (uke-turno).
# Uso: ./c5-ciclo23.sh --check | --go   (solo insmod/rmmod; SIN flash ni reinicio)
set -u
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../.." && pwd); D=$HERE/out-ciclo23
HOST=${UKE_HOST:-root@192.168.42.129}; export UKE_HOST=$HOST
SSH=(ssh -o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=4 -i "$R/build/rootfs/uke-arch-root" -o BatchMode=yes "$HOST")
TURNO="$R/build/rootfs/deploy/turno/uke-turno"
F="uke_cam_camcc.ko camcc-cliffs-uke.ko uke_cam_rear.ko uke_ov13b10.ko uke_cam_camss.ko uke_cam_front.ko uke_ov08d10.ko uke-camss.ko"
cd "$D" || exit 2
for f in $F; do [ -s "$f" ] || { echo "falta $f"; exit 2; }; done
[ "$(modinfo -F vermagic uke-camss.ko | cut -d' ' -f1)" = "7.2.9-senemos.1.4054.3-ouke5" ] || { echo "vermagic != ouke5"; exit 2; }
strings uke-camss.ko | grep -qx qcom-camss || { echo "camss no se llama qcom-camss"; exit 2; }
grep -q uke_rst uke_ov08d10.c 2>/dev/null || modinfo -F parm uke_ov08d10.ko | grep -q uke_chip_id || { echo "uke_ov08d10 sin parche"; exit 2; }
if [ "${1:-}" != "--go" ]; then echo "check OK"; sha256sum $F | cut -c1-16,65-; exit 0; fi
OUT=$HERE/out/c5-ciclo23-$(date +%Y%m%d-%H%M).txt; exec > >(tee "$OUT") 2>&1
echo "# C5b ciclo 23 $(date -Is) host=$HOST"
"$TURNO" pedir camaras-2 "ciclo 23: insmod de la camara frontal (sin reinicio)" 1200 || { echo "ABORTO: sin turno"; exit 3; }
BAT=$("${SSH[@]}" 'cat /sys/class/power_supply/qcom-battmgr-bat/capacity') || { "$TURNO" soltar camaras-2; exit 3; }; echo "bateria=$BAT %"
[ "$("${SSH[@]}" 'lsmod | grep -cE "uke_cam|camcc|camss|ov13|ov08|i2c_qcom_cci|uke_vcm|ldob14|dw9714"')" = 0 ] || { echo "ABORTO: ya hay modulos de camara"; "$TURNO" soltar camaras-2; exit 3; }
TMPR=$(mktemp); tar cf - $F | "${SSH[@]}" 'rm -rf /root/uke-cam23; mkdir -p /root/uke-cam23; tar xf - -C /root/uke-cam23; sync -f /root/uke-cam23/*.ko; cd /root/uke-cam23 && sha256sum *.ko' | sort -k2 > "$TMPR"
sha256sum $F | sort -k2 | diff - "$TMPR" && echo "sha iguales" || { echo "ABORTO: sha distintos"; "$TURNO" soltar camaras-2; exit 3; }
DL=$HERE/out/c5c23-dmesg-$(date +%H%M).log; "${SSH[@]}" 'dmesg -w' > "$DL" 2>&1 &
DP=$!
MODS="uke_camss uke_ov08d10 uke_cam_front uke_cam_camss uke_ov13b10 i2c_qcom_cci uke_cam_rear camcc_cliffs_uke uke_cam_camcc"
pc_cleanup() { kill "$DP" 2>/dev/null; "${SSH[@]}" "pkill -f 'v4l2-ctl -d /dev/video' 2>/dev/null; sleep 0.5; for m in $MODS; do rmmod \$m 2>/dev/null; done; pkill -f 'why=C5c23' 2>/dev/null; echo \"limpieza PC: restan \$(lsmod | grep -cE 'uke_cam|camcc|camss|ov13|ov08|i2c_qcom_cci')\"" 2>/dev/null; rm -f "$TMPR"; "$TURNO" soltar camaras-2; }
trap pc_cleanup EXIT INT TERM; sleep 2
"${SSH[@]}" "bash -s" <<'REMOTE'
U=/root/uke-cam23; MODS="uke_camss uke_ov08d10 uke_cam_front uke_cam_camss uke_ov13b10 i2c_qcom_cci uke_cam_rear camcc_cliffs_uke uke_cam_camcc"
pkill -f "why=C5c" 2>/dev/null; (setsid nohup systemd-inhibit --what=sleep:idle --who=camara --why=C5c23 sleep 1500 >/dev/null 2>&1 &)
unl() { pkill -f "v4l2-ctl -d /dev/video" 2>/dev/null; sleep 0.5; for m in $MODS; do rmmod $m 2>/dev/null; done; pkill -f "why=C5c23" 2>/dev/null; }
trap unl EXIT HUP TERM INT
rm -f /root/b23-*.raw /root/c23.raw
dmesg -n 7
for m in mc videodev v4l2-async v4l2-fwnode videobuf2-common videobuf2-v4l2 videobuf2-dma-sg; do modprobe $m; done
insmod $U/uke_cam_camcc.ko; insmod $U/camcc-cliffs-uke.ko ungate=1; insmod $U/uke_cam_rear.ko
echo ac15000.qcom,cci0 > /sys/bus/platform/drivers/simple-pm-bus/unbind 2>/dev/null; echo i2c-qcom-cci > /sys/bus/platform/devices/ac15000.qcom,cci0/driver_override
modprobe i2c-qcom-cci; insmod $U/uke_ov13b10.ko; sleep 2   # la trasera tambien: el notificador de camss espera a TODOS sus sensores
insmod $U/uke_cam_camss.ko
insmod $U/uke_ov08d10.ko uke_chip_id=0x5647; sleep 0.5
insmod $U/uke_cam_front.ko; sleep 4
echo "bus i2c@880000: $(ls -d /sys/bus/platform/devices/880000.i2c 2>/dev/null) driver=$(basename "$(readlink /sys/bus/platform/devices/880000.i2c/driver 2>/dev/null)")"
echo "clientes: $(ls /sys/bus/i2c/devices/ | tr '\n' ' ')"
echo "frontal: $(dmesg | grep -aiE 'ov08d10|880000.i2c|geni' | tail -8 | cut -c15-220 | tr '\n' '|')"
insmod $U/uke-camss.ko; sleep 4
[ -e /dev/media0 ] || { echo "ABORTO: sin /dev/media0"; exit 4; }
M="media-ctl -d /dev/media0"
SE=$($M -p 2>/dev/null | awk '/entity.*ov08d10/{sub(/.*: /,""); sub(/ \(.*/,""); print; exit}'); echo "entidad frontal: '${SE:-NO}'"
[ -n "$SE" ] || { echo "ABORTO: el OV08D10 no esta en el grafo"; exit 5; }
SUB=$($M -e "$SE"); VID=$($M -e msm_vfe0_video0); echo "subdev=$SUB video=$VID"
v4l2-ctl -d $SUB -l 2>&1 | grep -E 'test_pattern|exposure|gain|blank|link' | head -8
CODE=$($M --get-v4l2 "\"$SE\":0" | sed -n 's/.*fmt:\([A-Z0-9_]*\)\/.*/\1/p'); echo "formato del sensor: $CODE"
case $CODE in SBGGR10_1X10) PF=pBAA;; SGBRG10_1X10) PF=pGAA;; SGRBG10_1X10) PF=pgAA;; SRGGB10_1X10) PF=pRAA;; *) echo "ABORTO: formato $CODE"; exit 5;; esac
$M -l "\"msm_csiphy4\":1->\"msm_csid0\":0[1]"; $M -l "\"msm_csid0\":1->\"msm_vfe0_rdi0\":0[1]"
P=/sys/module/qcom_camss/parameters; [ -d $P ] || P=/sys/module/uke_camss/parameters
echo 1 > $P/uke_stat 2>/dev/null; echo 0 > $P/uke_rx_budget 2>/dev/null; echo 0 > $P/uke_rdi_budget 2>/dev/null; echo $((0xfffffff0)) > $P/uke_rx_mask 2>/dev/null
saved=0
shot() {  # $1 etiqueta $2 ancho $3 alto $4 test_pattern
  local f="fmt:$CODE/$2x$3"
  $M -V "\"$SE\":0[$f],\"msm_csiphy4\":0[$f],\"msm_csiphy4\":1[$f],\"msm_csid0\":0[$f],\"msm_csid0\":1[$f],\"msm_vfe0_rdi0\":0[$f],\"msm_vfe0_rdi0\":1[$f]" 2>&1 | tail -1
  v4l2-ctl -d $VID --set-fmt-video=width=$2,height=$3,pixelformat=$PF >/dev/null
  local SZ=$(v4l2-ctl -d $VID --get-fmt-video | awk -F: '/Size Image/{gsub(/ /,"",$2); print $2}')
  v4l2-ctl -d $SUB -c test_pattern=$4 >/dev/null 2>&1
  rm -f /root/c23.raw
  timeout 12 v4l2-ctl -d $VID --stream-mmap=3 --stream-skip=3 --stream-count=1 --stream-to=/root/c23.raw > /root/c23.v4l 2>&1
  local BY=$(stat -c %s /root/c23.raw 2>/dev/null || echo 0)
  echo "######## $1 ${2}x${3} tp=$4 sizeimage=$SZ bytes=$BY $(tail -c 120 /root/c23.v4l | tr '\n' ' ')"
  head -c 600 $P/uke_statline 2>/dev/null | head -4
  if [ "$BY" -gt 0 ]; then
    echo "  nonzero=$(tr -d '\000' < /root/c23.raw | wc -c) sha=$(sha256sum /root/c23.raw | cut -c1-16)"
    saved=$((saved+1)); sync -f /root/c23.raw; cp /root/c23.raw "/root/b23-$saved-$2x$3-tp$4.raw"
  fi
}
cap() { echo $1 > $P/uke_cap_ctrl; echo 6 > $P/uke_cap_n; echo 6 > $P/uke_rx_budget; dmesg -C; }
cap $((0x2b3)); shot "C1 cap DT2b" 3280 2460 1; dmesg | grep -a 'uke-cap\|RX_IRQ' | cut -c15-260 | head -14
cap $((0x003)); shot "C2 cap DT0" 3280 2460 1; dmesg | grep -a 'uke-cap\|RX_IRQ' | cut -c15-260 | head -14
echo 0 > $P/uke_rx_budget; echo -1 > $P/uke_cap_ctrl
echo "buffers guardados: $saved"
echo "fallos SMMU/oops: $(dmesg | grep -acE 'Unhandled (context|stream) fault|Oops')"
echo "=== descarga"
trap - EXIT; unl
echo "restan $(lsmod | grep -cE 'uke_cam|camcc|camss|ov13|ov08|i2c_qcom_cci')"
REMOTE
"${SSH[@]}" 'cd /root && ls b23-*.raw 2>/dev/null | xargs -r tar cf -' | { rm -f "$HERE"/out/b23-*.raw; tar xf - -C "$HERE/out/" 2>/dev/null; }; ls -l "$HERE"/out/b23-*.raw 2>/dev/null
echo "# fin; dmesg completo en $DL"
