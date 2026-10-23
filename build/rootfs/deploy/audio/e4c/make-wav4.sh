#!/bin/bash
# make-wav4.sh — WAV de 4 canales, 48 kHz, S16_LE, de DIAGNOSTICO del mapa canal->slot->altavoz: cada canal suena SOLO 1,5 s con un tono de 1 kHz a -40 dBFS,
# en orden canal 0, 1, 2, 3 (huecos de 0,5 s). Total 8 s. Salida: el fichero dado (por defecto uke-4ch-seq-40dbfs.wav). Genera solo en el PC.
set -Eeuo pipefail
OUT=${1:-uke-4ch-seq-40dbfs.wav}
python3 -I - "$OUT" <<'PY'
import sys, struct, math, wave
out = sys.argv[1]; fs = 48000; amp = int(32767 * 10 ** (-40 / 20))
frames = bytearray()
for ch in range(4):
    for _ in range(0):  # (sin relleno previo: el orden lo marca el tiempo)
        pass
total = 8 * fs
for n in range(total):
    t = n / fs; slot = int(t // 2); within = t - slot * 2
    row = [0, 0, 0, 0]
    if slot < 4 and within < 1.5:
        row[slot] = int(amp * math.sin(2 * math.pi * 1000 * t))
    frames += struct.pack('<4h', *row)
w = wave.open(out, 'wb'); w.setnchannels(4); w.setsampwidth(2); w.setframerate(fs); w.writeframes(bytes(frames)); w.close()
print(out, total, "tramas,", 4, "canales, -40 dBFS, canal k suena en [2k, 2k+1.5) s")
PY
