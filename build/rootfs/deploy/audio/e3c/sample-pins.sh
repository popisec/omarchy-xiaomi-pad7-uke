#!/bin/bash
# sample-pins.sh — SE EJECUTA EN LA TABLET (ssh … 'bash -s' < sample-pins.sh). SOLO LECTURA de los pads: con un PCM de 48 kHz sonando (uke_fs_play se deja en N: los amps NO se tocan),
# lee 5000 veces VALUE de gpio6..9 y muestra unos/transiciones (BCLK gpio6 y WS gpio7 deben conmutar; DATA gpio8/9 conmuta con el tono). Requiere e3 + driver LPI, e8b y uke_lpi_rd.ko en extra/.
K=$(uname -r); WAV=${1:-/root/uke-1k-40dbfs.wav}
[ "$(cat /sys/module/uke_fs19xx/parameters/uke_fs_play)" = N ] || { echo "uke_fs_play no es N: abortado"; exit 2; }
amixer -c UKE cset name='PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1' on >/dev/null
(timeout 12 sh -c "while :; do aplay -q -D hw:UKE,0 $WAV; done" >/dev/null 2>&1) &
sleep 2; echo "--- estado: $(grep -E '^state' /proc/asound/card0/pcm0p/sub0/status)"
for p in 6 7 8 9; do
	insmod /lib/modules/$K/extra/uke_lpi_rd.ko uke_lpi_go=1 uke_lpi_pin=$p uke_lpi_samples=5000 || { echo "insmod fallo (pin $p)"; break; }
	dmesg | grep "uke_lpi_rd: VALUE(gpio$p)" | tail -1 | sed 's/.*uke_lpi_rd: //'; rmmod uke_lpi_rd
done
wait
amixer -c UKE cset name='PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1' off >/dev/null
