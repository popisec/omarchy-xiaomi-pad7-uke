#!/bin/bash
# test-chain.sh ETAPA — SE EJECUTA EN LA TABLET (ssh … 'bash -s ETAPA' < test-chain.sh). Requiere UKE-tplg.bin = UKE-tplg-chain.bin (MFC->SAL->LOG->TDM_SINK) y snd-q6apm con el parche 0008.
# ETAPA a: cadena con los parametros a 0 (MFC/SAL a 16 bit, 2 canales) y amps SIN tocar (uke_fs_play=N): solo comprueba que el ADSP acepta el grafo.
#        b: + uke_tdm_chain_bits=32 (MFC/SAL/TDM_SINK a 32 bit), amps sin tocar.
#        c: + uke_tdm_chain_chan=4 (4 canales mapa {1,2,8,9}), amps sin tocar.
#        d: igual que c pero con los amps habilitados (uke_fs_play=Y, vol 0xF3) y tono -18 dBFS de 2 s para escuchar.
# Cada etapa abre un PCM de 2 s (WAV S16 estereo de 1 kHz a -18 dBFS), restaura los parametros a 0 y uke_fs_play=N, y avisa si el ADSP cae.
E=${1:?etapa a|b|c|d}; Q=/sys/module/snd_q6apm/parameters; F=/sys/module/uke_fs19xx/parameters; WAV=/root/uke-1k-m18.wav; R=/sys/class/remoteproc/remoteproc1/state
for p in uke_tdm_chain_bits uke_tdm_chain_chan; do [ -w $Q/$p ] || { echo "falta $p (snd-q6apm con el parche 0008)"; exit 2; }; done
restore() { echo 0 > $Q/uke_tdm_chain_bits; echo 0 > $Q/uke_tdm_chain_chan; echo N > $F/uke_fs_play; amixer -c UKE cset name='PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1' off >/dev/null 2>&1; echo "(restaurado: chain_bits=0 chain_chan=0 uke_fs_play=N) adsp=$(cat $R)"; }
trap restore EXIT
case $E in a) ;; b) echo 32 > $Q/uke_tdm_chain_bits;; c|d) echo 32 > $Q/uke_tdm_chain_bits; echo 4 > $Q/uke_tdm_chain_chan;; *) echo "etapa invalida"; exit 2;; esac
[ $E = d ] && { echo 243 > $F/uke_fs_volmax; echo 243 > $F/uke_fs_vol; echo Y > $F/uke_fs_play; }
echo "=== etapa $E: bits=$(cat $Q/uke_tdm_chain_bits) chan=$(cat $Q/uke_tdm_chain_chan) play=$(cat $F/uke_fs_play)"
amixer -c UKE cset name='PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1' on >/dev/null
timeout 6 aplay -D hw:UKE,0 $WAV 2>&1 | tail -1; echo "aplay rc=${PIPESTATUS[0]} adsp=$(cat $R)"
dmesg | grep -E "audio_process|fatal error|Failed to start APM|DSP returned error|amps habil" | tail -3 | cut -c1-150
