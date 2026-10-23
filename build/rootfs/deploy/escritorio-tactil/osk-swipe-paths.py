#!/usr/bin/env python3
"""osk-swipe-paths.py — trazos de swipe en PIXELES FISICOS sobre el teclado acoplado (horizontal, 1600x1068 logicos, escala 2),
con la geometria exacta de Keyboard.qml (distribucion ES, separacion 6, columna x=8 y=52, 5 filas, 40 % de alto).
Uso: osk-swipe-paths.py palabra [palabra...] -> argumentos "path:..." para mt-inject.py"""
import sys
SW, SH, SCALE = 1600, 1068, 2
KH = round(SH * 0.40); KY = SH - KH; GAP = 6
COLW = SW - 16; COLH = KH - 52 - 8; ROWH = (COLH - 4 * GAP) / 5
ROWS = {1: [("Tab", 1.4)] + [(c, 1) for c in "qwertyuiop"] + [("`", 1), ("+", 1), ("Del", 1.4)],
        2: [("Caps", 1.5)] + [(c, 1) for c in "asdfghjklñ"] + [("´", 1), ("ç", 1), ("Enter", 1.8)],
        3: [("Shift", 1.6), ("<", 1)] + [(c, 1) for c in "zxcvbnm"] + [(",", 1), (".", 1), ("-", 1), ("Shift", 2.0)]}
POS = {}
for r, keys in ROWS.items():
    unit = (COLW - GAP * (len(keys) - 1)) / sum(w for _, w in keys)
    x = 8
    for name, w in keys:
        POS.setdefault(name, (x + unit * w / 2, KY + 52 + r * (ROWH + GAP) + ROWH / 2))
        x += unit * w + GAP
FOLD = str.maketrans("áéíóúü", "aeiouu")
out = []
for word in sys.argv[1:]:
    pts = [POS[c] for c in word.lower().translate(FOLD)]
    out.append("path:" + ";".join(f"{x * SCALE:.0f},{y * SCALE:.0f}" for x, y in pts))
print(" ".join(out))
