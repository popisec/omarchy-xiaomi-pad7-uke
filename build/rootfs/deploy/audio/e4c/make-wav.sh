#!/bin/bash
# Genera el WAV de prueba de E4c: 2 s, 48 kHz, estereo, S16_LE, seno de 1 kHz a -40 dBFS (amplitud 328/32768). Uso: make-wav.sh SALIDA.wav
set -eu
python3 -I - "${1:?uso: $0 SALIDA.wav}" <<'PY'
import math, struct, sys, wave
rate, secs, amp, f = 48000, 2, int(32768 * 10 ** (-40 / 20)), 1000.0
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate)
    fr = b"".join(struct.pack("<hh", s, s) for s in (int(amp * math.sin(2 * math.pi * f * i / rate)) for i in range(rate * secs)))
    w.writeframes(fr)
print("WAV:", sys.argv[1], "amplitud", amp, "(-40 dBFS)")
PY
