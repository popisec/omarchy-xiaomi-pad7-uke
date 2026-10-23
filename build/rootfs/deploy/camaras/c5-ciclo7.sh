#!/usr/bin/env bash
# c5-ciclo7.sh — C5b ciclo 7 (preparado 21-oct-2026, NO EJECUTADO): H-SETTLE/H-SKEW/H-LANE. Barrido de settle, skew-cal del vendor y lane_assign, patron de test, con resumen por stream (SOT/ECC/LONG/SHORT). Criterios: CAMARAS-C5-CICLO7-PLAN-20261021.md
# Uso:  ./c5-ciclo7.sh --check   (solo PC: verifica modulos y sha)   |   ./c5-ciclo7.sh --go   (EJECUTA en la tablet: carga modulos; SIN flash ni reinicio)
# PRECONDICIONES (todas): orden del dueno para ESTE ciclo; la sesion de audio dijo «libre»; bateria >= 30 %; ningun modulo de camara cargado;
# lector ACM unico vivo; USB 192.168.42.129 alcanzable (via de riesgo; no Tailscale). Resultado en out/c5-ciclo7-AAAAMMDD-HHMM.txt (+ dmesg a fichero).
set -u
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../.." && pwd); D=$HERE/out-ciclo7
SSH=(ssh -o ConnectTimeout=8 -i "$R/build/rootfs/uke-arch-root" -o BatchMode=yes root@192.168.42.129)
F="uke_cam_camcc.ko camcc-cliffs-uke.ko uke_cam_rear.ko uke_ov13b10.ko uke_cam_camss.ko uke-camss.ko"
cd "$D" || exit 2
for f in $F; do [ -s "$f" ] || { echo "falta $f (build con UKE_RXIRQ=1 UKE_CSID_LOG=1 UKE_PHY_LOG=1 UKE_CPHY_RX_HZ=19200000 CPPX=-DWITH_IOMMU OUT=out-ciclo7)"; exit 2; }; done
[ "$(modinfo -F vermagic uke-camss.ko | cut -d' ' -f1)" = "7.2.9-senemos.1.4054.3-ouke5" ] || { echo "vermagic != ouke5"; exit 2; }
for p in uke_rx_mask uke_skew uke_lane_assign uke_settle; do modinfo -F parm uke-camss.ko | grep -q "^$p:" || { echo "falta parametro $p"; exit 2; }; done; modinfo -F parm uke-camss.ko | grep -q uke_rx_mask || { echo "uke-camss.ko sin el IRQ del RX (UKE_RXIRQ)"; exit 2; }
if [ "${1:-}" != "--go" ]; then echo "check OK (vermagic ouke5; parametros uke_skew/uke_lane_assign/uke_settle/uke_ctl7/uke_ctl0_post)"; sha256sum $F | cut -c1-16,65-; exit 0; fi
OUT=$HERE/out/c5-ciclo7-$(date +%Y%m%d-%H%M).txt; exec > >(tee "$OUT") 2>&1
echo "# C5b ciclo 7 $(date -Is)"
BAT=$("${SSH[@]}" 'cat /sys/class/power_supply/qcom-battmgr-bat/capacity'); echo "bateria=$BAT %"; [ "$BAT" -ge 30 ] || { echo "ABORTO: bateria < 30 %"; exit 3; }
[ "$("${SSH[@]}" 'lsmod | grep -cE "uke_cam|camcc|uke_camss|ov13|i2c_qcom_cci"')" = 0 ] || { echo "ABORTO: ya hay modulos de camara cargados"; exit 3; }
tar cf - $F | "${SSH[@]}" 'rm -rf /root/uke-cam; mkdir -p /root/uke-cam; tar xf - -C /root/uke-cam 2>/dev/null; cd /root/uke-cam && sha256sum *.ko' | sort -k2 > /tmp/c5c7.remote
sha256sum $F | sort -k2 | diff - /tmp/c5c7.remote && echo "sha iguales" || { echo "ABORTO: sha distintos"; exit 3; }
DL=$HERE/out/c5c7-dmesg-$(date +%H%M).log; "${SSH[@]}" 'dmesg -w' > "$DL" 2>&1 &
DP=$!; sleep 2
"${SSH[@]}" 'bash -s' <<'REMOTE'
U=/root/uke-cam; (setsid nohup systemd-inhibit --what=sleep:idle --who=camara --why=C5c7 sleep 1500 >/dev/null 2>&1 &)
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
P=/sys/module/uke_camss/parameters
ls $P | tr '\n' ' '; echo
v4l2-ctl -d $SUB -c test_pattern=1 2>&1 | head -1
run() {  # $1 etiqueta  $2 settle  $3 skew  $4 lane_assign  $5 ctl7  $6 ctl0_post  $7 test_pattern(1=B,0=A)
  echo $2 > $P/uke_settle; echo $3 > $P/uke_skew; echo $4 > $P/uke_lane_assign; echo $5 > $P/uke_ctl7; echo $6 > $P/uke_ctl0_post
  v4l2-ctl -d $SUB -c test_pattern=$7 2>&1 | head -1
  echo 400 > $P/uke_rx_budget; echo $((0xfffffff0)) > $P/uke_rx_mask
  dmesg -C 2>/dev/null; rm -f /root/c7.raw
  timeout 8 v4l2-ctl -d /dev/video0 --stream-mmap=3 --stream-count=1 --stream-to=/root/c7.raw 2>&1 | tail -1
  BY=$(stat -c %s /root/c7.raw 2>/dev/null || echo 0)
  dmesg | grep -ao "RX_IRQ=[0-9a-f]*" | cut -d= -f2 | awk -v L="$1" -v B=$BY 'function bit(v,n){return int(v/(2^n))%2}
    {v=strtonum("0x"$1); n++; sot+=(bit(v,4)||bit(v,5)||bit(v,6)||bit(v,7)); sot4+=(bit(v,4)&&bit(v,5)&&bit(v,6)&&bit(v,7)); ecc+=bit(v,20); lng+=bit(v,8); sht+=bit(v,9); crc+=bit(v,19); ovf+=(bit(v,15)||bit(v,16)||bit(v,17)||bit(v,18)); wecc+=bit(v,14)}
    END{printf "RESUMEN %-22s bytes=%-8d irq=%d SOT=%d SOT4=%d ECC=%d LONG=%d SHORT=%d CRC=%d OVF=%d WECC=%d\n",L,B,n,sot,sot4,ecc,lng,sht,crc,ovf,wecc}'
}
# S: barrido de settle (patron de test, secuencia mainline, skew off, lane_assign del DT)
for st in 10 19 25 30 40 60 80; do run "S settle=$st" $st 0 -1 -1 -1 1; done
# K: skew-cal del vendor (B), con y sin la secuencia vendor
for st in 19 30; do run "K skew settle=$st" $st 1 -1 -1 -1 1; done
for st in 19 30; do run "KV skew+vendor st=$st" $st 1 -1 122 2 1; done
# L: permutaciones de lane_assign (settle calculado)
for la in $((0x0123)) $((0x1032)) $((0x2301)); do run "L lane_assign=$(printf 0x%04x $la)" -1 0 $la -1 -1 1; done
# A: stream normal con las dos combinaciones de skew
run "A skew st=19" 19 1 -1 -1 -1 0
run "A skew+vendor st=30" 30 1 -1 122 2 0
echo "fallos SMMU/oops: $(dmesg | grep -acE 'Unhandled (context|stream) fault|Oops')"
echo "=== descarga"
for m in uke_camss uke_cam_camss uke_ov13b10 i2c_qcom_cci uke_cam_rear camcc_cliffs_uke uke_cam_camcc; do rmmod $m 2>&1 | head -1; done
echo "restan $(lsmod | grep -cE 'uke_cam|camcc|uke_camss|ov13|i2c_qcom_cci')"
REMOTE
kill "$DP" 2>/dev/null
echo "# fin; dmesg completo en $DL"
