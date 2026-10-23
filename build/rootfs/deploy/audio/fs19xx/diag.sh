#!/bin/bash
# diag.sh — SE EJECUTA EN LA TABLET (ssh … 'bash -s' < diag.sh). Volcado de SOLO LECTURA de registros de los 4 FS19xx (debugfs de uke_fs19xx):
#   1) en reposo (amps parados), 2) a mitad de un PCM de silencio con uke_fs_play=1 (amps habilitados), 3) tras parar.
# Cambia SOLO parametros del modulo (uke_fs_vol=0x20, uke_fs_play) y el mezclador/aplay; restaura uke_fs_play=N. No escribe registros de los amps salvo lo que ya hace el driver al reproducir.
P=/sys/module/uke_fs19xx/parameters; D=/sys/kernel/debug/uke_fs19xx/regs
echo "=== 1) reposo"; cat $D
echo 32 > $P/uke_fs_vol; echo Y > $P/uke_fs_play
amixer -c UKE cset name='PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1' on >/dev/null
(timeout 5 aplay -D hw:UKE,0 -f S16_LE -r 48000 -c 2 -t raw /dev/zero >/dev/null 2>&1) &
sleep 2.5; echo "=== 2) reproduciendo (amps habilitados)"; cat $D
wait
amixer -c UKE cset name='PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1' off >/dev/null; echo N > $P/uke_fs_play
echo "=== 3) tras parar"; cat $D
