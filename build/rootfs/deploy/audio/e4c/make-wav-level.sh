#!/bin/bash
# make-wav-level.sh NIVEL_dBFS SALIDA.wav [BITS=16|32] — WAV de 2 s, 48 kHz, estéreo, S16_LE (o S32_LE con BITS=32), seno de 1 kHz al nivel pedido (negativo, entre -60 y -12 dBFS). Solo en el PC.
set -eu
L=${1:?uso: $0 NIVEL_dBFS SALIDA.wav}; OUT=${2:?uso: $0 NIVEL_dBFS SALIDA.wav}
python3 -I - "$L" "$OUT" "${3:-16}" <<'PY'
import math, struct, sys, wave
lvl = float(sys.argv[1])
if not (-60 <= lvl <= -12): sys.exit("nivel fuera de rango (-60..-12 dBFS)")
bits = int(sys.argv[3])
if bits not in (16, 32): sys.exit("BITS debe ser 16 o 32")
rate, secs = 48000, 2
full = (1 << (bits - 1)) - 1
amp = int(full * 10 ** (lvl / 20))
with wave.open(sys.argv[2], "wb") as w:
    w.setnchannels(2); w.setsampwidth(bits // 8); w.setframerate(rate)
    w.writeframes(b"".join(struct.pack("<ii" if bits == 32 else "<hh", s, s) for s in (int(amp * math.sin(2 * math.pi * 1000 * i / rate)) for i in range(rate * secs))))
print("WAV:", sys.argv[2], "%.0f dBFS, S%d_LE, amplitud %d" % (lvl, bits, amp))
PY
