#!/usr/bin/env python3
"""Genera fork/click.wav: clic de tecla de 12 ms (48 kHz, mono, 16 bit), ruido filtrado con caida exponencial."""
import math, random, struct, sys, wave
random.seed(7)
sr, n = 48000, int(48000 * 0.012)
out, prev = [], 0.0
for i in range(n):
    x = random.uniform(-1, 1)
    prev = 0.55 * prev + 0.45 * x                      # paso bajo suave: menos estridente
    out.append(int(32767 * 0.6 * prev * math.exp(-i / (sr * 0.0025))))
with wave.open(sys.argv[1] if len(sys.argv) > 1 else "fork/click.wav", "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes(struct.pack("<%dh" % n, *out))
