#!/usr/bin/env bash
# c5-ciclo15.sh — C5b ciclo 15 (preparado 22-oct-2026, NO EJECUTADO): instrumentacion arreglada (solo memoria, sin volcar registros): contadores por bit de RX/RDI0 de todo el stream + los ultimos 96 eventos de RDI0 que no son SOL/EOL y los BUF_DONE con marca de tiempo, leidos por /sys/module/uke_camss/parameters/uke_statline despues de cada stream. 0x7e/0x76 x captura 0x208 activa/inactiva x 10 rondas; buffers guardados con 'nonzero'. Criterios: CAMARAS-C5-CICLO15-PLAN-20261022.md
# Uso:  ./c5-ciclo15.sh --check   (solo PC: verifica modulos y sha)   |   ./c5-ciclo15.sh --go   (EJECUTA en la tablet: carga modulos; SIN flash ni reinicio)
# PRECONDICIONES (todas): orden del dueno para ESTE ciclo; la sesion de audio dijo «libre»; bateria >= 30 %; ningun modulo de camara cargado;
# lector ACM unico vivo; USB 192.168.42.129 alcanzable (via de riesgo; no Tailscale). Resultado en out/c5-ciclo15-AAAAMMDD-HHMM.txt (+ dmesg a fichero).
set -u
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../.." && pwd); D=$HERE/out-ciclo15
SSH=(ssh -o ConnectTimeout=8 -i "$R/build/rootfs/uke-arch-root" -o BatchMode=yes root@192.168.42.129)
F="uke_cam_camcc.ko camcc-cliffs-uke.ko uke_cam_rear.ko uke_ov13b10.ko uke_cam_camss.ko uke-camss.ko"
cd "$D" || exit 2
for f in $F; do [ -s "$f" ] || { echo "falta $f (build con UKE_SENSDBG=1 UKE_RXIRQ=1 UKE_CSID_LOG=1 UKE_PHY_LOG=1 UKE_CPHY_RX_HZ=19200000 CPPX=-DWITH_IOMMU OUT=out-ciclo15)"; exit 2; }; done
[ "$(modinfo -F vermagic uke-camss.ko | cut -d' ' -f1)" = "7.2.9-senemos.1.4054.3-ouke5" ] || { echo "vermagic != ouke5"; exit 2; }
for p in uke_rx_mask uke_skew uke_lane_assign uke_settle uke_cap_ctrl uke_cap_n uke_rdi_budget; do modinfo -F parm uke-camss.ko | grep -q "^$p:" || { echo "falta parametro $p"; exit 2; }; done; modinfo -F parm uke_ov13b10.ko | grep -q "^uke_dump:" || { echo "uke_ov13b10.ko sin la sonda (UKE_SENSDBG)"; exit 2; }; modinfo -F parm uke-camss.ko | grep -q "^uke_cap_ctrl:" || { echo "uke-camss.ko sin uke_cap_ctrl"; exit 2; }; modinfo -F parm uke-camss.ko | grep -q "^uke_statline:" || { echo "uke-camss.ko sin uke_statline"; exit 2; }; modinfo -F parm uke-camss.ko | grep -q uke_rx_mask || { echo "uke-camss.ko sin el IRQ del RX (UKE_RXIRQ)"; exit 2; }
if [ "${1:-}" != "--go" ]; then echo "check OK (vermagic ouke5; parametros uke_skew/uke_lane_assign/uke_settle/uke_ctl7/uke_ctl0_post)"; sha256sum $F | cut -c1-16,65-; exit 0; fi
OUT=$HERE/out/c5-ciclo15-$(date +%Y%m%d-%H%M).txt; exec > >(tee "$OUT") 2>&1
echo "# C5b ciclo 15 $(date -Is)"
BAT=$("${SSH[@]}" 'cat /sys/class/power_supply/qcom-battmgr-bat/capacity'); echo "bateria=$BAT %"; [ "$BAT" -ge 30 ] || { echo "ABORTO: bateria < 30 %"; exit 3; }
[ "$("${SSH[@]}" 'lsmod | grep -cE "uke_cam|camcc|uke_camss|ov13|i2c_qcom_cci"')" = 0 ] || { echo "ABORTO: ya hay modulos de camara cargados"; exit 3; }
tar cf - $F | "${SSH[@]}" 'rm -rf /root/uke-cam; mkdir -p /root/uke-cam; tar xf - -C /root/uke-cam 2>/dev/null; cd /root/uke-cam && sha256sum *.ko' | sort -k2 > /tmp/c5c15.remote
sha256sum $F | sort -k2 | diff - /tmp/c5c15.remote && echo "sha iguales" || { echo "ABORTO: sha distintos"; exit 3; }
DL=$HERE/out/c5c15-dmesg-$(date +%H%M).log; "${SSH[@]}" 'dmesg -w' > "$DL" 2>&1 &
DP=$!; trap 'kill $DP 2>/dev/null' EXIT; sleep 2
"${SSH[@]}" "bash -s -- ${2:-all}" <<'REMOTE'
U=/root/uke-cam; pkill -f "why=C5c" 2>/dev/null; (setsid nohup systemd-inhibit --what=sleep:idle --who=camara --why=C5c15 sleep 1500 >/dev/null 2>&1 &)
unl() { for m in uke_camss uke_cam_camss uke_ov13b10 i2c_qcom_cci uke_cam_rear camcc_cliffs_uke uke_cam_camcc; do rmmod $m 2>/dev/null; done; pkill -f "why=C5c15" 2>/dev/null; }
trap unl HUP TERM
rm -f /root/b15-*.raw
dmesg -n 7
echo ac15000.qcom,cci0 > /sys/bus/platform/drivers/simple-pm-bus/unbind 2>/dev/null; echo i2c-qcom-cci > /sys/bus/platform/devices/ac15000.qcom,cci0/driver_override
for m in mc videodev v4l2-async v4l2-fwnode videobuf2-common videobuf2-v4l2 videobuf2-dma-sg; do modprobe $m; done
insmod $U/uke_cam_camcc.ko; insmod $U/camcc-cliffs-uke.ko ungate=1; insmod $U/uke_cam_rear.ko; modprobe i2c-qcom-cci; insmod $U/uke_ov13b10.ko; sleep 3
echo "chip: $(dmesg | grep -a 'chip id' | tail -1 | cut -c20-120)"
insmod $U/uke_cam_camss.ko; insmod $U/uke-camss.ko; sleep 4
M="media-ctl -d /dev/media0"; F="fmt:SGRBG10_1X10/2104x1560"
$M -l "\"msm_csiphy1\":1->\"msm_csid0\":0[1]"; $M -l "\"msm_csid0\":1->\"msm_vfe0_rdi0\":0[1]"
$M -V "\"ov13b10 7-0010\":0[$F],\"msm_csiphy1\":0[$F],\"msm_csiphy1\":1[$F],\"msm_csid0\":0[$F],\"msm_csid0\":1[$F],\"msm_vfe0_rdi0\":0[$F],\"msm_vfe0_rdi0\":1[$F]"
v4l2-ctl -d /dev/video0 --set-fmt-video=width=2104,height=1560,pixelformat=pgAA | head -1
SUB=$($M -p -e "ov13b10 7-0010" | awk '/device node name/{print $NF; exit}'); echo "subdev del sensor: $SUB"
P=/sys/module/uke_camss/parameters; S=/sys/module/uke_ov13b10/parameters
echo -1 > $P/uke_settle; echo 1 > $S/uke_dump
setmode() {  # $1 ancho $2 alto
  F="fmt:SGRBG10_1X10/$1x$2"
  $M -V "\"ov13b10 7-0010\":0[$F],\"msm_csiphy1\":0[$F],\"msm_csiphy1\":1[$F],\"msm_csid0\":0[$F],\"msm_csid0\":1[$F],\"msm_vfe0_rdi0\":0[$F],\"msm_vfe0_rdi0\":1[$F]" 2>&1 | tail -1
  v4l2-ctl -d /dev/video0 --set-fmt-video=width=$1,height=$2,pixelformat=pgAA | head -1
}
P=/sys/module/uke_camss/parameters; S=/sys/module/uke_ov13b10/parameters
echo -1 > $P/uke_settle; echo 0 > $P/uke_skew; echo -1 > $P/uke_lane_assign; echo 0 > $S/uke_dump
echo 1 > $P/uke_stat; echo 0 > $P/uke_cap_n; echo 0 > $P/uke_rx_budget; echo 0 > $P/uke_rdi_budget
echo $((0xfffffff0)) > $P/uke_rx_mask
v4l2-ctl -d $SUB -c test_pattern=0 2>&1 | head -1
saved=0; n=0
try() {  # $1 etiqueta  $2 valor de 0x4800  $3 captura 0x208 (-1 = apagada)
  n=$((n+1)); echo "######## $n $1"
  echo $((0x4800)) > $S/uke_xreg; echo $(($2)) > $S/uke_xval; echo $3 > $P/uke_cap_ctrl
  dmesg -C 2>/dev/null; rm -f /root/c15.raw
  timeout 10 v4l2-ctl -d /dev/video0 --stream-mmap=3 --stream-count=1 --stream-to=/root/c15.raw 2>&1 | tail -1
  BY=$(stat -c %s /root/c15.raw 2>/dev/null || echo 0)
  cat $P/uke_statline | head -60
  if [ "$BY" -gt 0 ]; then
    NZ=$(tr -d '\000' < /root/c15.raw | wc -c); SH=$(sha256sum /root/c15.raw | cut -c1-16)
    echo "BUF $1 bytes=$BY nonzero=$NZ sha=$SH"
    if [ $saved -lt 6 ]; then saved=$((saved+1)); cp /root/c15.raw /root/b15-$saved.raw; echo "GUARDADO b15-$saved.raw"; fi
  else echo "BUF $1 bytes=0"; fi
}
for r in 1 2 3 4 5 6 7 8 9 10; do
  try "A 7e cap-on r$r" 0x7e $((0x2b3)); try "A 7e cap-off r$r" 0x7e -1
  try "A 76 cap-on r$r" 0x76 $((0x2b3)); try "A 76 cap-off r$r" 0x76 -1
done
echo "buffers guardados: $saved"
echo "fallos SMMU/oops: $(dmesg | grep -acE 'Unhandled (context|stream) fault|Oops')"
echo "=== descarga"
for m in uke_camss uke_cam_camss uke_ov13b10 i2c_qcom_cci uke_cam_rear camcc_cliffs_uke uke_cam_camcc; do rmmod $m 2>&1 | head -1; done; pkill -f "why=C5c15" 2>/dev/null
echo "restan $(lsmod | grep -cE 'uke_cam|camcc|uke_camss|ov13|i2c_qcom_cci')"
REMOTE
"${SSH[@]}" 'tar cf - -C /root b15-1.raw b15-2.raw b15-3.raw b15-4.raw b15-5.raw b15-6.raw 2>/dev/null' | { rm -f "$HERE"/out/b15-*.raw; tar xf - -C "$HERE/out/" 2>/dev/null; }; ls -l "$HERE"/out/b15-*.raw 2>/dev/null
kill "$DP" 2>/dev/null
echo "# fin; dmesg completo en $DL"
