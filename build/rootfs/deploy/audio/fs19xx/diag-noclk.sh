#!/bin/bash
# diag-noclk.sh — SE EJECUTA EN LA TABLET. A/B de registros de los amps CON y SIN BCLK (instrumento alternativo a VALUE.IN, que no funciona):
#   A) amps habilitados SIN PCM (sin BCLK), volcado de registros;  B) con un PCM de silencio en marcha (BCLK del ADSP), volcado;  C) parados.
# Solo lecturas I2C de registros y el arranque/parada normales del driver (vol 0x20, silencio). Requiere el uke_fs19xx.ko con debugfs ctl (E8 diag 3).
P=/sys/module/uke_fs19xx/parameters; D=/sys/kernel/debug/uke_fs19xx
echo 32 > $P/uke_fs_vol; echo Y > $P/uke_fs_play
echo on > $D/ctl || { echo "ctl on fallo"; echo N > $P/uke_fs_play; exit 1; }
sleep 1; echo "=== A) amps ON, SIN PCM (sin BCLK)"; cat $D/regs
amixer -c UKE cset name='PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1' on >/dev/null
(timeout 5 aplay -q -D hw:UKE,0 -f S16_LE -r 48000 -c 2 -t raw /dev/zero >/dev/null 2>&1) &
sleep 2.5; echo "=== B) amps ON, CON PCM (BCLK del ADSP)"; cat $D/regs
wait; amixer -c UKE cset name='PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1' off >/dev/null
echo off > $D/ctl; echo N > $P/uke_fs_play
echo "=== C) parados"; cat $D/regs | head -12
