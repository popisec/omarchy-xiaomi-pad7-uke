#!/usr/bin/env python3
# uke-mic-rms.py FICHERO.wav — RMS y pico en dBFS del WAV (S16_LE), global y por ventanas de 0,5 s, por canal. Sin dependencias. Salida de una linea por canal + ventanas.
import struct, sys, wave, math
CLICK = '--click' in sys.argv
if CLICK: sys.argv.remove('--click')
w = wave.open(sys.argv[1]); n, ch, sw, rate = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
if sw != 2: sys.exit("solo S16_LE")
raw = w.readframes(n); s = struct.unpack("<%dh" % (len(raw) // 2), raw)
def db(x): return -200.0 if x <= 0 else 20 * math.log10(x / 32768.0)
win = rate // 2
for c in range(ch):
    x = s[c::ch]
    rms = math.sqrt(sum(v * v for v in x) / max(1, len(x)))
    pk = max((abs(v) for v in x), default=0)
    dc = sum(x) / max(1, len(x))
    ws = [db(math.sqrt(sum(v * v for v in x[i:i + win]) / max(1, len(x[i:i + win])))) for i in range(0, len(x), win) if len(x[i:i + win]) == win]
    xs = x[win:] if len(x) > 2 * win else x
    rms2 = math.sqrt(sum(v * v for v in xs) / max(1, len(xs)))
    print("canal %d: %d muestras %d Hz  RMS %.1f dBFS  pico %.1f dBFS  DC %.0f  ventanas0,5s: %s  (max-min %.1f dB)  RMS_sin_0,5s_inicial %.1f dBFS" % (c, len(x), rate, db(rms), db(pk), dc, " ".join("%.0f" % v for v in ws), (max(ws) - min(ws)) if ws else 0.0, db(rms2)))
if ch == 2:
    def wins(x):
        return [math.sqrt(sum(v * v for v in x[i:i + win]) / win) for i in range(0, len(x) - win + 1, win)]
    a, b = wins(s[0::2]), wins(s[1::2])
    print("dif ch0-ch1 por ventana (dB; >0 = canal 0 mas fuerte): " + " ".join("%+.0f" % (20 * math.log10(max(x, 1e-3) / max(y, 1e-3))) for x, y in zip(a, b)))
if CLICK:
    # chasquido de arranque: ventanas de 50 ms; delta = RMS maximo de las ventanas de los primeros 0,5 s - mediana de las ventanas de 1,0-2,0 s; settle = ms hasta la primera ventana a <= 3 dB del suelo
    w50 = rate // 20
    for c in range(ch):
        x = s[c::ch]
        r = [math.sqrt(sum(v * v for v in x[i:i + w50]) / w50) for i in range(0, len(x) - w50 + 1, w50)]
        first = max(r[:10]) if len(r) >= 10 else max(r)
        tail = sorted(r[20:40]) if len(r) >= 40 else sorted(r[len(r) // 2:])
        floor = tail[len(tail) // 2] if tail else 1e-3
        settle = next((i * 50 for i, v in enumerate(r) if v <= floor * 1.41), -1)
        print("click canal %d: primeros 0,5 s max %.1f dBFS, suelo %.1f dBFS, delta %.1f dB, estable a los %d ms" % (c, db(first), db(floor), db(first) - db(floor), settle))
