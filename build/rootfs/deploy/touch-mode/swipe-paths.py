#!/usr/bin/env python3
"""swipe-paths.py — genera trazos de swipe realistas sobre la geometria del teclado ES de Keyboard.qml (filas q-p, a-ñ, z-m con sus
desplazamientos por Tab 1.4 / Caps 1.5 / Shift 1.6 + '<'), igual que los mandaria el QML: teclas cruzadas en orden y '*' en las
esquinas (giro > 50 grados), primera y ultima. Uso: swipe-paths.py palabra [palabra...]  -> "palabra<TAB>trazo" por linea."""
import math, sys
ROWS = [("qwertyuiop", 1.4), ("asdfghjklñ", 1.5), ("zxcvbnm", 2.6)]
POS = {}
for y, (keys, off) in enumerate(ROWS):
    for i, k in enumerate(keys):
        POS[k] = (off + i + 0.5, y + 0.5)
FOLD = str.maketrans("áéíóúü", "aeiouu")


def key_at(x, y):
    row = min(2, max(0, int(y)))
    keys, off = ROWS[row]
    i = min(len(keys) - 1, max(0, int(x - off)))
    return keys[i]


def path(word):
    w = [c for c in word.lower().translate(FOLD)]
    pts = [POS[c] for c in w]
    seq, corners = [], {0, len(pts) - 1}
    for i in range(1, len(pts) - 1):
        a = math.atan2(pts[i][1] - pts[i - 1][1], pts[i][0] - pts[i - 1][0])
        b = math.atan2(pts[i + 1][1] - pts[i][1], pts[i + 1][0] - pts[i][0])
        d = abs((b - a + math.pi) % (2 * math.pi) - math.pi)
        if pts[i] != pts[i - 1] and pts[i] != pts[i + 1] and d > math.radians(50):
            corners.add(i)
    for i, p in enumerate(pts):
        if i:
            q = pts[i - 1]
            n = max(1, int(math.dist(p, q) / 0.1))
            for s in range(1, n):
                k = key_at(q[0] + (p[0] - q[0]) * s / n, q[1] + (p[1] - q[1]) * s / n)
                if not seq or seq[-1][0] != k:
                    seq.append([k, False])
        k = w[i]
        if not seq or seq[-1][0] != k:
            seq.append([k, i in corners])
        elif i in corners:
            seq[-1][1] = True
    return " ".join(("*" if c else "") + k for k, c in seq)


for word in sys.argv[1:]:
    print(f"{word}\t{path(word)}")
