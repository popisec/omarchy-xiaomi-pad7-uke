#!/usr/bin/env bash
# c1-baseline.sh -- C1: linea base de SOLO LECTURA de la tablet antes de tocar nada de camaras (ssh, sin escribir, sin cargar).
# Uso: ./c1-baseline.sh [fichero-salida]   (por defecto out/c1-baseline-AAAAMMDD-HHMM.txt). No usa dmesg -c ni escribe en sysfs/debugfs.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../.." && pwd)
OUT=${1:-$HERE/out/c1-baseline-$(date +%Y%m%d-%H%M).txt}
SSH=(ssh -o ConnectTimeout=6 -i "$R/build/rootfs/uke-arch-root" -o BatchMode=yes root@192.168.42.129)
{
echo "# C1 linea base $(date -Is)"; "${SSH[@]}" 'uname -r; uptime; cat /sys/class/power_supply/*/capacity 2>/dev/null | head -1'
echo "## 1. el DT vivo: nodos de camara y su estado"
"${SSH[@]}" 'for p in clock-controller@ade0000 qcom,cci0@ac15000 qcom,cci1@ac16000 qcom,csiphy1@ace6000 qcom,csiphy4@acec000 qcom,qupv3_1_geni_se@8c0000/i2c@880000; do echo "$p status=$(tr -d "\0" < /proc/device-tree/soc/$p/status 2>/dev/null) compat=$(tr "\0" " " < /proc/device-tree/soc/$p/compatible)"; done'
echo "## 2. iomem de camara (vacio = los dispositivos vendor no reservan MMIO)"
"${SSH[@]}" 'grep -E "ac1[0-9a-f]000|ade0000|acb[0-9a-f]000|ace[0-9a-f]000|ac[6-8][0-9a-f]000" /proc/iomem; echo "(fin)"'
echo "## 3. kernel: opciones relevantes"
"${SSH[@]}" 'zcat /proc/config.gz | grep -E "OF_OVERLAY|RESET_GPIO=|I2C_QCOM_CCI|VIDEO_QCOM_CAMSS|SM_CAMCC_8650|CONFIG_V4L2_ASYNC|VIDEOBUF2_DMA_SG|QCOM_GDSC|REGULATOR_QCOM_RPMH_UKE|LEDS_QCOM_FLASH|INPUT_PM8XXX|VIDEO_OV13B10|VIDEO_OV08D10|DW9"'
echo "## 4. pines (debugfs, solo lectura): 3 14 64 68 72 73 79 160"
"${SSH[@]}" 'for g in 3 14 64 68 72 73 79 160; do grep -E "^ gpio$g " /sys/kernel/debug/gpio | head -1; done'
echo "## 5. rieles de camara y los que ya votan otros"
"${SSH[@]}" 'for r in /sys/class/regulator/regulator.*; do n=$(cat $r/name); case $n in camera*|pmxr2230_s2|pmxr2230_l2|pmxr2230_l4|pm_v6c_s6_level|pm_v8_s6_level|pm_v8_s8_level) echo "$n $(cat $r/state) $(cat $r/microvolts 2>/dev/null) users=$(cat $r/num_users)";; esac; done'
echo "## 6. dispositivos rpmh-regulator de los rieles de camara: enlazados? (sin driver = fuera de la allowlist de qcom-rpmh-regulator-uke.c)"
"${SSH[@]}" 'D=/sys/bus/platform/devices; for n in ldob20 ldoe6 ldoc3 ldob14 bobb1 ldob2 ldob4; do echo "$n driver=$(readlink $D/17a00000.rsc:drv@2:rpmh-regulator-$n/driver | xargs -r basename)"; done'
echo "## 7. modulos de camara disponibles en /lib/modules"
"${SSH[@]}" 'K=$(uname -r); ls /lib/modules/$K/kernel/drivers/media/platform/qcom/camss /lib/modules/$K/kernel/drivers/i2c/busses 2>/dev/null | grep -E "camss|cci"; ls /lib/modules/$K/extra 2>/dev/null | head -20; lsmod | grep -E "camss|cci|camcc|ov13|ov08|videodev" || echo "(ninguno cargado)"'
echo "## 8. dispositivos V4L/I2C actuales"
"${SSH[@]}" 'ls /dev/video* /dev/media* /dev/v4l-subdev* 2>&1 | head; ls /dev/i2c-*; for a in /sys/class/i2c-adapter/i2c-*; do echo "$(basename $a): $(cat $a/name)"; done'
echo "## 9. fw_devlink/sync_state pendientes por camara (dmesg, solo lectura)"
"${SSH[@]}" 'dmesg | grep -E "cam-cpas|camcc|ade0000" | head -8'
} > "$OUT" 2>&1
echo "escrito $OUT ($(wc -l < "$OUT") lineas)"
