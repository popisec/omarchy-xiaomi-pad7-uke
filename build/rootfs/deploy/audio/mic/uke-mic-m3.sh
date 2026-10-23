#!/bin/bash
# uke-mic-m3.sh OPCION [SEGUNDOS=4] — M3 del micro: aplica la ruta (uke-mic-route.sh), graba SEGUNDOS con arecord en hw:UKE,2 (MultiMedia3 Capture) y mide RMS/pico por ventanas (uke-mic-rms.py).
# OPCION tambien dual-A-B (dos micros a la vez). Se ejecuta EN la tablet (root) con la tarjeta e9a cargada. OPCION = amic1 | amic4 | amic3-vendor | estereo-vendor | silencio (ruta amic1 con el micro tapado/sin hablar es lo mismo: usa «amic1»).
# Deja WAV en /root/mic-m3/ (no al repo salvo que se pida). Tras grabar apaga la ruta (`uke-mic-route.sh --off`). Timeout duro de arecord: SEGUNDOS+6.
# El dueño habla o golpea el micro indicado DURANTE la grabacion (empieza ~1 s despues del aviso «GRABANDO»).
set -u
OPT=${1:?uso: $0 amic1|amic4|amic3-vendor|estereo-vendor [SEGUNDOS]}; S=${2:-4}; D=/root/mic-m3; mkdir -p "$D"
HERE=$(cd "$(dirname "$0")" && pwd); R=${UKE_MIC_ROUTE:-/usr/local/sbin/uke-mic-route.sh}; RMS=${UKE_MIC_RMS:-/usr/local/sbin/uke-mic-rms.py}; [ -f "$RMS" ] || RMS=$HERE/uke-mic-rms.py
CH=2   # el PCM de captura (MultiMedia3 Capture) solo ofrece S16_LE, 48 kHz, 2 CANALES (medido con --dump-hw-params en M3); un micro mono llega a uno o a los dos canales
F=$D/$OPT-$(date +%H%M%S).wav
echo "== ruta $OPT"; "$R" --apply "$OPT" | grep -v "^  ok" | head -20
echo "$(date +%T) GRABANDO $S s (hw:UKE,2, $CH canal(es), S16_LE 48 kHz): HABLA/GOLPEA el micro «$OPT» AHORA"
timeout $((S + 6)) arecord -D hw:UKE,2 -f S16_LE -r 48000 -c $CH -d "$S" "$F" 2>&1 | tail -2
rc=${PIPESTATUS[0]}; echo "arecord rc=$rc"
if [ -s "$F" ]; then echo "== medida de $F ($(stat -c %s "$F") B)"; python3 -I "$RMS" "$F"; else echo "(sin fichero de salida)"; fi
"$R" --off | grep -c "ok" | sed 's/^/rutas desactivadas: /'
dmesg | tail -n 6 | grep -iE "wcd|swr|sdw|q6apm|audioreach|timeout|fault|oops" | cut -c1-150 | head -4
