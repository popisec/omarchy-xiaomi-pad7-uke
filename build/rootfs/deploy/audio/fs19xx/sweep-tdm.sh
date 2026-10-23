#!/bin/bash
# sweep-tdm.sh — SE EJECUTA EN LA TABLET (ssh … 'bash -s' < sweep-tdm.sh). Barrido de los parametros del TDM (snd_q6apm, 0644 con el .ko nuevo):
# retraso de datos {0,1,2} x modo de sincronizacion {0 short-bit, 1 long, 2 short-slot} x inversion {0,1} = 18 combinaciones (la del ACDB es delay=1 sync=0 inv=0).
# Cada una: abre un PCM con el WAV de 1 kHz a -18 dBFS (2 s) con los amps habilitados (uke_fs_play=Y, vol 0xF3) y, a 1 s, lee registros 00/0A/0C/19 del amp 0x34.
# Imprime "[n] delay=d sync=s inv=i" ANTES de cada tono, para que el dueno cuente cuantos tonos oye y diga en cual. Pausa de 2,5 s entre combinaciones.
# Restaura los parametros del ACDB y uke_fs_play=N al terminar (o al abortar con Ctrl-C/senal).
Q=/sys/module/snd_q6apm/parameters; F=/sys/module/uke_fs19xx/parameters; R=/sys/kernel/debug/uke_fs19xx/regs
WAV=${1:-/root/uke-1k-m18.wav}
for p in uke_tdm_delay uke_tdm_sync_mode uke_tdm_invert; do [ -w $Q/$p ] || { echo "$Q/$p no es escribible (hace falta el snd-q6apm con parametros 0644)"; exit 2; }; done
restore() { echo 1 > $Q/uke_tdm_delay; echo 0 > $Q/uke_tdm_sync_mode; echo 0 > $Q/uke_tdm_invert; echo N > $F/uke_fs_play; amixer -c UKE cset name='PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1' off >/dev/null 2>&1; echo "(parametros restaurados: delay=1 sync=0 inv=0, uke_fs_play=N)"; }
trap restore EXIT
echo 243 > $F/uke_fs_volmax; echo 243 > $F/uke_fs_vol; echo Y > $F/uke_fs_play
amixer -c UKE cset name='PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1' on >/dev/null
n=0
for d in 1 0 2; do for s in 0 1 2; do for i in 0 1; do
  n=$((n+1)); echo $d > $Q/uke_tdm_delay; echo $s > $Q/uke_tdm_sync_mode; echo $i > $Q/uke_tdm_invert
  echo "[$n] delay=$d sync=$s inv=$i  $( [ $d = 1 ] && [ $s = 0 ] && [ $i = 0 ] && echo '(= ACDB)')"
  (timeout 5 aplay -q -D hw:UKE,0 $WAV >/dev/null 2>&1) &
  sleep 1; regs=$(sed -n '2,4p' $R | tr ' ' '\n' | grep -E '^(00|0a|0c|19):' | tr '\n' ' '); echo "    amp0x34: $regs"
  wait; sleep 2.5
done; done; done
