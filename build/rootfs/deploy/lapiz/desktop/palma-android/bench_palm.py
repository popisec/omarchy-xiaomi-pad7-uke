#!/usr/bin/env python3
"""Coste por frame de palm_android (microsegundos, PC) - uso: python3 bench_palm.py. Mide filter() en el camino SIN lapiz (la parte que corre
SIEMPRE con --palm-android) y con lapiz activo. El maximo exigido en el camino sin lapiz es 50 us (test_palm_extra.Bench)."""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from palm_android import AndroidPalm

DT = 1 / 226.0


def bench(n_pts, pen=False, n=20000, repeat=5):
    """mediana (us) de filter() por llamada; pts estaticos o moviendose; con pen=True se alterna pen_frame y filter."""
    best = []
    for _ in range(repeat):
        p, t = AndroidPalm(), 100.0
        pts = [(i, 500 + 100 * i, 800, 9) for i in range(n_pts)]
        t0 = time.perf_counter()
        for k in range(n):
            t += DT
            if pen:
                p.pen_frame(t)
            if n_pts:
                pts = [(i, 500 + 100 * i + (k & 1), 800, 9) for i in range(n_pts)]
            p.filter(pts, t, pen)
        best.append((time.perf_counter() - t0) / n * 1e6)
    return sorted(best)[len(best) // 2]


def table():
    rows = []
    for name, npts, pen in (("sin lapiz, 0 dedos (reposo)", 0, False), ("sin lapiz, 1 dedo", 1, False), ("sin lapiz, 2 dedos", 2, False),
                            ("sin lapiz, 10 dedos", 10, False), ("lapiz activo, 1 dedo (pen_frame+filter)", 1, True),
                            ("lapiz activo, 10 dedos", 10, True)):
        rows.append((name, bench(npts, pen)))
    return rows


if __name__ == "__main__":
    for name, us in table():
        print("%-42s %7.2f us/frame" % (name, us))
