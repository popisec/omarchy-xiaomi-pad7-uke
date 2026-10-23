#!/usr/bin/env bash
# c5-ciclo5.sh — C5b ciclo 5 (preparado 21-oct-2026, NO EJECUTADO): IRQ del RX/RDI del CSID + patron de test del sensor, en UN ciclo.
# Uso:  ./c5-ciclo5.sh --check   (solo PC: verifica modulos y sha)   |   ./c5-ciclo5.sh --go   (EJECUTA en la tablet: carga modulos; SIN flash ni reinicio)
# PRECONDICIONES (todas): orden del dueno para ESTE ciclo; la sesion de audio dijo «libre»; bateria >= 30 %; ningun modulo de camara cargado;
# lector ACM unico vivo; USB 192.168.42.129 alcanzable (via de riesgo; no Tailscale). Resultado en out/c5-ciclo5-AAAAMMDD-HHMM.txt (+ dmesg a fichero).
set -u
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../.." && pwd); D=$HERE/out-rxirq
SSH=(ssh -o ConnectTimeout=8 -i "$R/build/rootfs/uke-arch-root" -o BatchMode=yes root@192.168.42.129)
F="uke_cam_camcc.ko camcc-cliffs-uke.ko uke_cam_rear.ko uke_ov13b10.ko uke_cam_camss.ko uke-camss.ko"
cd "$D" || exit 2
for f in $F; do [ -s "$f" ] || { echo "falta $f (build con UKE_RXIRQ=1 UKE_CSID_LOG=1 UKE_PHY_LOG=1 UKE_CPHY_RX_HZ=19200000 CPPX=-DWITH_IOMMU OUT=out-rxirq)"; exit 2; }; done
[ "$(modinfo -F vermagic uke-camss.ko | cut -d' ' -f1)" = "7.2.9-senemos.1.4054.3-ouke5" ] || { echo "vermagic != ouke5"; exit 2; }
modinfo -F parm uke-camss.ko | grep -q uke_rx_mask || { echo "uke-camss.ko sin el IRQ del RX (UKE_RXIRQ)"; exit 2; }
if [ "${1:-}" != "--go" ]; then echo "check OK (módulos con vermagic ouke5 y parámetros uke_rx_mask/uke_rdin_mask/uke_settle)"; sha256sum $F | cut -c1-16,65-; exit 0; fi
OUT=$HERE/out/c5-ciclo5-$(date +%Y%m%d-%H%M).txt; exec > >(tee "$OUT") 2>&1
echo "# C5b ciclo 5 $(date -Is)"
BAT=$("${SSH[@]}" 'cat /sys/class/power_supply/qcom-battmgr-bat/capacity'); echo "bateria=$BAT %"; [ "$BAT" -ge 30 ] || { echo "ABORTO: bateria < 30 %"; exit 3; }
[ "$("${SSH[@]}" 'lsmod | grep -cE "uke_cam|camcc|uke_camss|ov13|i2c_qcom_cci"')" = 0 ] || { echo "ABORTO: ya hay modulos de camara cargados"; exit 3; }
tar cf - $F | "${SSH[@]}" 'rm -rf /root/uke-cam; mkdir -p /root/uke-cam; tar xf - -C /root/uke-cam 2>/dev/null; cd /root/uke-cam && sha256sum *.ko' | sort -k2 > /tmp/c5c5.remote
sha256sum $F | sort -k2 | diff - /tmp/c5c5.remote && echo "sha iguales" || { echo "ABORTO: sha distintos"; exit 3; }
DL=$HERE/out/c5c5-dmesg-$(date +%H%M).log; "${SSH[@]}" 'dmesg -w' > "$DL" 2>&1 &
DP=$!; sleep 2
"${SSH[@]}" 'bash -s' <<'REMOTE'
U=/root/uke-cam; (setsid nohup systemd-inhibit --what=sleep:idle --who=camara --why=C5c5 sleep 1500 >/dev/null 2>&1 &)
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
echo "=== A: stream normal con el IRQ del RX/RDI habilitado"
dmesg -C 2>/dev/null; rm -f /root/a.raw; timeout 8 v4l2-ctl -d /dev/video0 --stream-mmap=3 --stream-count=1 --stream-to=/root/a.raw 2>&1 | tail -1
echo "A: $(stat -c %s /root/a.raw) bytes"; dmesg | grep -a "uke-csid" | cut -c20-260 | head -30
echo "=== B: patron de test del sensor (barras)"
v4l2-ctl -d $SUB -L 2>&1 | grep -i -A8 "test_pattern" | head -10
v4l2-ctl -d $SUB -c test_pattern=1 2>&1 | head -2
dmesg -C 2>/dev/null; rm -f /root/b.raw; timeout 8 v4l2-ctl -d /dev/video0 --stream-mmap=3 --stream-count=1 --stream-to=/root/b.raw 2>&1 | tail -1
echo "B: $(stat -c %s /root/b.raw) bytes"; dmesg | grep -a "uke-csid" | cut -c20-260 | head -30
v4l2-ctl -d $SUB -c test_pattern=0 2>&1 | head -1
echo "fallos SMMU/oops: $(dmesg | grep -acE 'Unhandled (context|stream) fault|Oops')"
echo "=== descarga"
for m in uke_camss uke_cam_camss uke_ov13b10 i2c_qcom_cci uke_cam_rear camcc_cliffs_uke uke_cam_camcc; do rmmod $m 2>&1 | head -1; done
echo "restan $(lsmod | grep -cE 'uke_cam|camcc|uke_camss|ov13|i2c_qcom_cci')"
REMOTE
kill "$DP" 2>/dev/null
echo "# fin; dmesg completo en $DL"
