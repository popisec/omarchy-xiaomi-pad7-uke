#!/usr/bin/env python3
"""ukeaf.py -- ayuda de la tablet (sin numpy) para el ciclo 19: `mean F` = media de los 8 bits altos de los verdes del centro;
`sharp F` = suma de |diferencias| entre verdes vecinos (paso 4 px) en el centro. RAW10 MIPI 2104x1560, stride 2640. 22-oct-2026."""
import sys
W, H, ST = 2104, 1560, 2640
def grid(f):
    # ciclo 20: medias de bloques de 4x4 muestras verdes (cada muestra 4 px) -> 16 px de lado; quita el ruido de ganancia alta
    d = open(f, 'rb').read()
    rows = []
    for y in range(96, H - 96, 4):          # filas pares (G en GRBG)
        o = y * ST
        rows.append([d[o + (x // 4) * 5] for x in range(128, W - 128, 4)])   # x multiplo de 4 -> pixel par -> G
    out = []
    for by in range(0, len(rows) - 3, 4):
        r4 = rows[by:by + 4]
        out.append([sum(sum(r[bx:bx + 4]) for r in r4) for bx in range(0, len(r4[0]) - 3, 4)])
    return out
cmd, f = sys.argv[1], sys.argv[2]
g = grid(f)
if cmd == 'mean':
    n = sum(len(r) for r in g) * 16; print(round(sum(sum(r) for r in g) / n, 1))
else:
    s = 0
    for y in range(len(g) - 1):
        r, q = g[y], g[y + 1]
        for x in range(len(r) - 1):
            s += abs(r[x] - r[x + 1]) + abs(r[x] - q[x])
    print(s)
