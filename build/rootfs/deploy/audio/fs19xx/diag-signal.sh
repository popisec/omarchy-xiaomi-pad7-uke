#!/bin/bash
# diag-signal.sh — SE EJECUTA EN LA TABLET. A/B de registros de los amps con PCM de SILENCIO frente a PCM con TONO (-18 dBFS, 1 kHz), amps habilitados (vol 0xF3):
# si algun registro cambia con el tono, el amp esta decodificando datos; si no cambia ninguno, no los ve (formato/slot/linea). Solo lectura de registros.
# Uso: bash -s [WAV_tono] < diag-signal.sh   (defecto /root/uke-1k-m18.wav; con /root/uke-1k-m18-s32.wav prueba el dato de 32 bit)
P=/sys/module/uke_fs19xx/parameters; R=/sys/kernel/debug/uke_fs19xx/regs; W=${1:-/root/uke-1k-m18.wav}
echo 243 > $P/uke_fs_volmax; echo 243 > $P/uke_fs_vol; echo Y > $P/uke_fs_play
amixer -c UKE cset name='PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1' on >/dev/null
(timeout 5 aplay -q -D hw:UKE,0 -f S16_LE -r 48000 -c 2 -t raw /dev/zero >/dev/null 2>&1) & sleep 2; cat $R > /root/diag-sil.txt; wait; sleep 1
(timeout 5 aplay -q -D hw:UKE,0 $W >/dev/null 2>&1) & sleep 1; cat $R > /root/diag-ton.txt; wait
amixer -c UKE cset name='PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1' off >/dev/null; echo N > $P/uke_fs_play
echo "=== diferencias silencio -> tono ($W)"; diff /root/diag-sil.txt /root/diag-ton.txt && echo "(ninguna)"
