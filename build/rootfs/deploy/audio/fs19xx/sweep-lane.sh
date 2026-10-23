#!/bin/bash
# sweep-lane.sh — SE EJECUTA EN LA TABLET. Prueba la linea de datos del TDM (parametro snd_q6apm uke_tdm_lane, parche 0007): lane_mask 1 (SD0/gpio8), 2 (SD1/gpio9), 3 (ambas),
# con el formato del ACDB, un tono de 1 kHz a -18 dBFS de 2 s por caso con los amps habilitados (uke_fs_play=Y, vol 0xF3). Imprime "[n] lane=L" antes de cada tono.
# Restaura uke_tdm_lane=0 y uke_fs_play=N al terminar o al abortar.
Q=/sys/module/snd_q6apm/parameters; F=/sys/module/uke_fs19xx/parameters; WAV=${1:-/root/uke-1k-m18.wav}
[ -w $Q/uke_tdm_lane ] || { echo "falta uke_tdm_lane (snd-q6apm con el parche 0007)"; exit 2; }
restore() { echo 0 > $Q/uke_tdm_lane; echo N > $F/uke_fs_play; amixer -c UKE cset name='PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1' off >/dev/null 2>&1; echo "(restaurado: uke_tdm_lane=0, uke_fs_play=N)"; }
trap restore EXIT
echo 243 > $F/uke_fs_volmax; echo 243 > $F/uke_fs_vol; echo Y > $F/uke_fs_play
amixer -c UKE cset name='PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1' on >/dev/null
n=0
for l in 1 2 3; do
  n=$((n+1)); echo $l > $Q/uke_tdm_lane; echo "[$n] lane=$l"
  timeout 6 aplay -q -D hw:UKE,0 $WAV >/dev/null 2>&1 || echo "    (aplay fallo: rc $?)"
  sleep 2.5
done
