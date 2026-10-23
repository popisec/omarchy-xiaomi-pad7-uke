#!/usr/bin/env bash
# c5-ciclo16.sh — C5b ciclo 16 (22-oct-2026): H7 «cphy_rx a 19,2 MHz». Desde el ciclo 2 (H-PHY2) todos los modulos se compilaban con
# UKE_CPHY_RX_HZ=19200000: el RCG compartido cam_cc_cphy_rx_clk_src (csiphy1_clk + csid_csiphy_rx_clk) corria a 19,2 MHz, cuando 4 lanes a
# 1,12 Gbps necesitan >= 140 MHz de reloj de byte. El 19,2 MHz de Android era una lectura en reposo (csid_clk e ife_2 tambien a 19,2 MHz).
# Modulos de out-ciclo16 = los del ciclo 15 SIN UKE_CPHY_RX_HZ (400 MHz de mainline). Misma instrumentacion de solo memoria (uke_statline).
# Uso:  ./c5-ciclo16.sh --check   (solo PC)   |   ./c5-ciclo16.sh --go   (tablet: insmod/rmmod en caliente; SIN flash ni reinicio)
# Robustez (pendiente §4c): trap EXIT en PC (mata el dmesg -w y descarga modulos por ssh) y en la tablet (descarga + inhibidor); ningun printk
# en el ISR (presupuestos 0); host por Tailscale (UKE_HOST=root@192.168.42.129 para el USB).
set -u
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../.." && pwd); D=$HERE/out-ciclo16
HOST=${UKE_HOST:-root@uke}
SSH=(ssh -o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=4 -i "$R/build/rootfs/uke-arch-root" -o BatchMode=yes "$HOST")
F="uke_cam_camcc.ko camcc-cliffs-uke.ko uke_cam_rear.ko uke_ov13b10.ko uke_cam_camss.ko uke-camss.ko"
MODS="uke_camss uke_cam_camss uke_ov13b10 i2c_qcom_cci uke_cam_rear camcc_cliffs_uke uke_cam_camcc"
cd "$D" || exit 2
for f in $F; do [ -s "$f" ] || { echo "falta $f"; exit 2; }; done
[ "$(modinfo -F vermagic uke-camss.ko | cut -d' ' -f1)" = "7.2.9-senemos.1.4054.3-ouke5" ] || { echo "vermagic != ouke5"; exit 2; }
for p in uke_statline uke_stat uke_cap_ctrl uke_rx_mask; do modinfo -F parm uke-camss.ko | grep -q "^$p:" || { echo "falta parametro $p"; exit 2; }; done
modinfo -F parm uke_ov13b10.ko | grep -q "^uke_xreg:" || { echo "uke_ov13b10.ko sin la sonda (UKE_SENSDBG)"; exit 2; }
cmp -s uke-camss.ko ../out-ciclo15/uke-camss.ko && { echo "uke-camss.ko identico al del ciclo 15 (sigue con 19,2 MHz?)"; exit 2; }
if [ "${1:-}" != "--go" ]; then echo "check OK (vermagic ouke5)"; sha256sum $F | cut -c1-16,65-; exit 0; fi
OUT=$HERE/out/c5-ciclo16-$(date +%Y%m%d-%H%M).txt; exec > >(tee "$OUT") 2>&1
echo "# C5b ciclo 16 $(date -Is) host=$HOST"
BAT=$("${SSH[@]}" 'cat /sys/class/power_supply/qcom-battmgr-bat/capacity') || { echo "ABORTO: sin ssh"; exit 3; }; echo "bateria=$BAT %"; [ "$BAT" -ge 30 ] || { echo "ABORTO: bateria < 30 %"; exit 3; }
[ "$("${SSH[@]}" 'lsmod | grep -cE "uke_cam|camcc|uke_camss|ov13|i2c_qcom_cci"')" = 0 ] || { echo "ABORTO: ya hay modulos de camara cargados"; exit 3; }
TMPR=$(mktemp); tar cf - $F | "${SSH[@]}" 'rm -rf /root/uke-cam; mkdir -p /root/uke-cam; tar xf - -C /root/uke-cam 2>/dev/null; cd /root/uke-cam && sha256sum *.ko' | sort -k2 > "$TMPR"
sha256sum $F | sort -k2 | diff - "$TMPR" && echo "sha iguales" || { echo "ABORTO: sha distintos"; exit 3; }
DL=$HERE/out/c5c16-dmesg-$(date +%H%M).log; "${SSH[@]}" 'dmesg -w' > "$DL" 2>&1 &
DP=$!
pc_cleanup() { kill "$DP" 2>/dev/null; "${SSH[@]}" "for m in $MODS; do rmmod \$m 2>/dev/null; done; pkill -f 'why=C5c16' 2>/dev/null; echo \"limpieza PC: restan \$(lsmod | grep -cE 'uke_cam|camcc|uke_camss|ov13|i2c_qcom_cci')\"" 2>/dev/null; rm -f "$TMPR"; }
trap pc_cleanup EXIT INT TERM; sleep 2
"${SSH[@]}" "bash -s" <<'REMOTE'
U=/root/uke-cam; MODS="uke_camss uke_cam_camss uke_ov13b10 i2c_qcom_cci uke_cam_rear camcc_cliffs_uke uke_cam_camcc"
pkill -f "why=C5c" 2>/dev/null; (setsid nohup systemd-inhibit --what=sleep:idle --who=camara --why=C5c16 sleep 1500 >/dev/null 2>&1 &)
unl() { pkill -f "v4l2-ctl -d /dev/video0" 2>/dev/null; sleep 0.5; for m in $MODS; do rmmod $m 2>/dev/null; done; pkill -f "why=C5c16" 2>/dev/null; }
trap unl EXIT HUP TERM INT
rm -f /root/b16-*.raw /root/c16.raw
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
try() {  # $1 etiqueta  $2 registro 0x4800 (-1 = no se escribe: 0x64 de la tabla)  $3 test_pattern
  n=$((n+1)); echo "######## $n $1"
  if [ "$2" = -1 ]; then echo -1 > $S/uke_xreg; else echo $((0x4800)) > $S/uke_xreg; echo $(($2)) > $S/uke_xval; fi
  v4l2-ctl -d $SUB -c test_pattern=$3 2>&1 | head -1
  rm -f /root/c16.raw
  timeout 10 v4l2-ctl -d /dev/video0 --stream-mmap=3 --stream-count=1 --stream-to=/root/c16.raw > /root/c16.v4l 2>&1 &
  VP=$!; sleep 1
  echo "clk(1s): cphy_rx=$(cat $CK/cam_cc_cphy_rx_clk_src/clk_rate 2>/dev/null) csiphy1=$(cat $CK/cam_cc_csiphy1_clk/clk_rate 2>/dev/null) csid_csiphy_rx=$(cat $CK/cam_cc_csid_csiphy_rx_clk/clk_rate 2>/dev/null) csid=$(cat $CK/cam_cc_csid_clk_src/clk_rate 2>/dev/null)"
  wait $VP; tail -1 /root/c16.v4l
  BY=$(stat -c %s /root/c16.raw 2>/dev/null || echo 0)
  head -c 3000 $P/uke_statline | head -40
  if [ "$BY" -gt 0 ]; then
    NZ=$(tr -d '\000' < /root/c16.raw | wc -c); SH=$(sha256sum /root/c16.raw | cut -c1-16)
    echo "BUF $1 bytes=$BY nonzero=$NZ sha=$SH"
    [ "$NZ" -gt 2000000 ] && full=$((full+1))
    if [ $saved -lt 6 ]; then saved=$((saved+1)); cp /root/c16.raw /root/b16-$saved.raw; echo "GUARDADO b16-$saved.raw ($1)"; fi
  else echo "BUF $1 bytes=0"; fi
}
try "TP barras" -1 1
try "TP barras r2" -1 1
for r in 1 2 3 4; do
  try "base64 r$r" -1 0; try "7e r$r" 0x7e 0; try "76 r$r" 0x76 0
done
echo "buffers guardados: $saved  casi-completos(>2MB no nulos): $full"
echo "fallos SMMU/oops: $(dmesg | grep -acE 'Unhandled (context|stream) fault|Oops')"
echo "=== descarga"
trap - EXIT; unl
echo "restan $(lsmod | grep -cE 'uke_cam|camcc|uke_camss|ov13|i2c_qcom_cci')"
REMOTE
"${SSH[@]}" 'cd /root && ls b16-*.raw 2>/dev/null | xargs -r tar cf -' | { rm -f "$HERE"/out/b16-*.raw; tar xf - -C "$HERE/out/" 2>/dev/null; }; ls -l "$HERE"/out/b16-*.raw 2>/dev/null
echo "# fin; dmesg completo en $DL"
