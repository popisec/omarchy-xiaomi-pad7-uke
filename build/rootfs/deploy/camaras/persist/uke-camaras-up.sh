#!/usr/bin/env bash
# uke-camaras-up.sh — carga UNA VEZ por arranque los módulos de cámara de la uke (trasera OV13B10 + VCM, frontal OV08D10) en el orden
# medido en los ciclos 16–23. PREPARADO 22-oct-2026, NO INSTALADO. Motivo: reaplicar overlays de DT en caliente provocó un oops (ciclo 23).
# Sin descarga: para quitar la cámara, reiniciar. Interruptor: /etc/uke/no-camaras.
set -u
U=${UKE_CAM_DIR:-/usr/lib/uke-camaras}
[ -e /etc/uke/no-camaras ] && { echo "uke-camaras: desactivado por /etc/uke/no-camaras"; exit 0; }
YA=; [ -e /run/uke-camaras.done ] && { YA=1; echo "uke-camaras: modulos ya cargados en este arranque: solo configuracion (sin insmod: nunca se reaplican overlays)"; }
[ "$(uname -r)" = "7.2.9-senemos.1.4054.3-ouke5" ] || { echo "uke-camaras: kernel distinto, no se carga"; exit 0; }
NOF=; [ -e /etc/uke/no-camara-frontal ] && NOF=1
if [ -z "$YA" ]; then
touch /run/uke-camaras.done
for m in mc videodev v4l2-async v4l2-fwnode videobuf2-common videobuf2-v4l2 videobuf2-dma-sg; do modprobe $m || exit 1; done
insmod $U/uke_cam_camcc.ko && insmod $U/camcc-cliffs-uke.ko ungate=1 && insmod $U/uke_cam_rear.ko || exit 1
insmod $U/uke_rpmh_ldob14.ko; insmod $U/uke_cam_lens.ko
echo ac15000.qcom,cci0 > /sys/bus/platform/drivers/simple-pm-bus/unbind 2>/dev/null; echo i2c-qcom-cci > /sys/bus/platform/devices/ac15000.qcom,cci0/driver_override
modprobe i2c-qcom-cci && insmod $U/uke_ov13b10.ko && insmod $U/uke_dw9714.ko || exit 1
insmod $U/uke_cam_camss.ko || exit 1
if [ -z "$NOF" ]; then insmod $U/uke_ov08d10.ko && insmod $U/uke_cam_front.ko; fi
insmod $U/uke-camss.ko || exit 1
fi
# 22-oct (arranque 19:05): tras el arranque el grafo de camss tarda mas de 10 s (fallo «sin /dev/media0»): hasta 60 s, y tambien las entidades
for i in $(seq 1 120); do [ -e /dev/media0 ] && media-ctl -d /dev/media0 -p 2>/dev/null | grep -q "entity.*ov13b10" && break; sleep 0.5; done
[ -e /dev/media0 ] && echo "uke-camaras: /dev/media0 listo" || { echo "uke-camaras: sin /dev/media0"; exit 1; }
# Valores iniciales de los sensores: no tienen auto-exposicion y Megapixels 1.8.3 arranca con lo que encuentre (OV13B10: 64 lineas =
# casi negro). Exposicion maxima a 30 fps y ganancia analogica 4x (ciclos 17-20). Ajustables en /etc/uke/camaras.conf.
EXP_R=3188; AG_R=512; EXP_F=2498; AG_F=512; FOCO=200
[ -r /etc/uke/camaras.conf ] && . /etc/uke/camaras.conf
M="media-ctl -d /dev/media0"
sub() { $M -e "$($M -p 2>/dev/null | awk -v s="$1" '$0 ~ "entity.*"s {sub(/.*: /,""); sub(/ \(.*/,""); print; exit}')" 2>/dev/null; }
for i in $(seq 1 20); do R=$(sub ov13b10); F=$(sub ov08d10); L=$(sub dw9714); [ -n "$R" ] && [ -n "$F$NOF" ] && [ -n "$L" ] && break; sleep 0.5; done
[ -n "$R" ] && { v4l2-ctl -d "$R" -c exposure=$EXP_R -c analogue_gain=$AG_R && echo "uke-camaras: trasera $R exp=$EXP_R ag=$AG_R" || echo "uke-camaras: AVISO controles de la trasera"; } || echo "uke-camaras: AVISO sin subdev de la trasera"
[ -n "$F" ] && { v4l2-ctl -d "$F" -c exposure=$EXP_F -c analogue_gain=$AG_F && echo "uke-camaras: frontal $F exp=$EXP_F ag=$AG_F" || echo "uke-camaras: AVISO controles de la frontal"; } || echo "uke-camaras: sin subdev de la frontal"
[ -n "$L" ] && echo "$L $FOCO" > /run/uke-camaras.lente && echo "uke-camaras: lente $L (foco $FOCO; la mantiene uke-camaras-lente.service)"
# ISP siempre activo (22-oct, ciclo 25): tras un stream, el runtime suspend de camss deja la ruta de la FRONTAL sin buffers (bufdone=0)
# hasta recargar el driver; con power/control=on funciona siempre (B1/B2). Coste de energia SIN MEDIR. Interruptor: /etc/uke/camaras-isp-auto.
if [ ! -e /etc/uke/camaras-isp-auto ]; then echo on > /sys/bus/platform/devices/acb6000.isp/power/control && echo "uke-camaras: ISP en power/control=on"; fi
exit 0
