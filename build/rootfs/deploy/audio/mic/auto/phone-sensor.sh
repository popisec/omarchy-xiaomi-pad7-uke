#!/bin/bash
# phone-sensor.sh SERIAL_ADB SEGUNDOS SALIDA.wav — (b) el movil como SENSOR de referencia, sin app ni root: scrcpy >=2.0 abre su servidor con el UID shell y captura el micro.
# NO PROBADO (no se toco el movil). Necesita autorizacion del dueño: ADB al Nothing Phone (2a) (adb connect IP:PUERTO tras avahi-browse, ver docs/historia/AGENTS.md raiz; NO el Pixel 10 Pro XL).
# Android 11+ para --audio-source=mic*. mic-unprocessed = sin AGC/NS/EQ (lo mas cercano a un micro de medida; no calibrado en dB SPL: solo ratios/retardos, no nivel absoluto).
# Formato: --audio-codec=raw => WAV sin perdidas (opus seria con perdidas, mal para correlar). Latencia de arranque desconocida => sincroniza por el chirp, no por reloj.
set -eu
S=${1:?serial ip:puerto}; T=${2:-12}; O=${3:-/var/tmp/uke-re/mic-auto/phone.wav}
timeout $((T + 8)) scrcpy -s "$S" --no-video --no-playback --no-control --audio-source=mic-unprocessed --audio-codec=raw --record="$O" --record-format=wav --time-limit="$T" || true
ls -l "$O"; echo "analizar: python3 uke_chirp.py analyze $O --meta meta.json  (el wav del movil es 1-2 canales a 48 kHz segun el dispositivo)"
# Fuente de tono desde el movil (sin app): adb push seq.wav /sdcard/Download/ ; adb shell am start -a android.intent.action.VIEW -d file:///sdcard/Download/seq.wav -t audio/wav
#   -> abre el reproductor por defecto (si lo hay; en Android moderno file:// exige FileProvider: suele fallar). Alternativa fiable: servir seq.wav con `python3 -m http.server` y abrir la URL en Chrome del movil
#   (am start -a android.intent.action.VIEW -d http://IP_PC:8000/seq.wav). `cmd media_session dispatch play` solo controla una sesion ya existente. No hay `tinyplay` en builds de usuario.
