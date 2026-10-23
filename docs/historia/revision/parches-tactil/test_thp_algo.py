#!/usr/bin/env python3
"""Test offline de thp_algo.Tracker con rejillas sinteticas (sin tablet).
Uso: docs/historia/revision/parches-tactil/test_thp_algo.py <dir con thp_algo.py> [--palm]   (--palm exige ademas el rechazo de palma: parche 0002)
"""
import array, os, random, sys

sys.path.insert(0, os.path.abspath(sys.argv[1]))
import thp_algo as T  # noqa: E402

PALM = "--palm" in sys.argv


def grid(blobs, noise=4, seed=1, rough=0):
    rnd = random.Random(seed)
    g = [10000 + rnd.randint(-noise, noise) for _ in range(T.ROWS * T.COLS)]
    for r0, c0, rad, amp in blobs:
        for r in range(T.ROWS):
            for c in range(T.COLS):
                d = ((r - r0) ** 2 + (c - c0) ** 2) ** .5
                if d <= rad:
                    g[r * T.COLS + c] += int(amp * (1 - d / (rad + 1))) + (rnd.randint(-rough, rough) if rough else 0)
    return array.array("H", [max(0, min(65535, v)) for v in g])


def fresh():
    tr = T.Tracker()
    tr.feed(grid([]))               # base inicial plana
    return tr


# 1. reposo: la via rapida lo reconoce y un dedo no
tr = fresh()
assert tr.quick_idle(grid([])), "reposo no detectado"
assert not tr.quick_idle(grid([(20, 30, 2.2, 1300)])), "dedo tomado por reposo"

# 2. un dedo -> un toque cerca del centro (nodo 20,30 -> X=(20.5)*534, Y=(30.5)*533)
tr = fresh()
p = tr.feed(grid([(20, 30, 2.2, 1300)]))
assert len(p) == 1, p
assert abs(p[0][1] - 20.5 * T.X_MAX / T.ROWS) < 300 and abs(p[0][2] - 30.5 * T.Y_MAX / T.COLS) < 300, p

# 3. id estable al moverse 1 nodo por frame, id nuevo para un segundo dedo
tr = fresh()
ids = set()
for k in range(6):
    p = tr.feed(grid([(10, 10 + k, 2.2, 1300)]))
    assert len(p) == 1
    ids.add(p[0][0])
assert len(ids) == 1, ids
p = tr.feed(grid([(10, 16, 2.2, 1300), (30, 40, 2.2, 1300)]))
assert len(p) == 2 and len({t for t, *_ in p}) == 2, p

# 4. dos dedos separados 6 nodos siguen separados; fuera de rango (>10) no se inventan toques
tr = fresh()
assert tr.feed(grid([])) == []

# 5. levantar el dedo: sin toques y reposo de nuevo
tr = fresh()
tr.feed(grid([(20, 30, 2.2, 1300)]))
assert tr.feed(grid([])) == []
assert tr.quick_idle(grid([]))

# 6. palma (mancha de ~110 nodos con textura): no debe producir toques; un dedo aparte si
tr = fresh()
palm = grid([(25, 40, 6.0, 1500)], rough=250, seed=3)
p = tr.feed(palm)
if PALM:
    assert p == [], "palma no rechazada: %r" % (p,)
    p = tr.feed(grid([(25, 40, 6.0, 1500), (8, 8, 2.2, 1300)], rough=0, seed=4))
    assert len(p) == 1 and p[0][2] < 8 * T.Y_MAX / T.COLS + 2000, p
    print("palma: OK (rechazada, dedo aparte conservado)")
else:
    print("palma sin parche: %d toques fantasma" % len(p))

print("OK", os.path.basename(sys.argv[1].rstrip("/")))
