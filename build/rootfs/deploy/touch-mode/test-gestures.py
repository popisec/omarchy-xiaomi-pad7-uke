#!/usr/bin/env python3
"""Prueba sintetica de uke-gestures.py v2 (sin tablet): genera toques y comprueba que gesto sale. Uso: python3 -I test-gestures.py"""
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("ug", os.path.join(os.path.dirname(os.path.abspath(__file__)), "uke-gestures.py"))
ug = importlib.util.module_from_spec(spec); spec.loader.exec_module(ug)

def run(fingers, transform=0):
    """fingers: lista de (t_down, t_up, [(t, x, y), ...]) con x,y RAW; devuelve gestos disparados."""
    cfg = ug.load_conf("/nonexistent")
    fired = []
    g = ug.Gestures(cfg, 3200, 2136, ug.Rotation(cfg, fixed=transform), lambda n, c, p=None: fired.append(n), None)
    for n in cfg["actions"]:
        cfg["actions"][n] = "x"
    ev = []
    for slot, (td, tu, path) in enumerate(fingers):
        ev.append((td, slot, "down", path[0][1], path[0][2]))
        for t, x, y in path:
            ev.append((t, slot, "move", x, y))
        ev.append((tu, slot, "up", 0, 0))
    ev.sort(key=lambda e: (e[0], {"down": 0, "move": 1, "up": 2}[e[2]]))
    for i, (t, slot, kind, x, y) in enumerate(ev):
        g.feed(t, ug.EV_ABS, ug.ABS_MT_SLOT, slot)
        if kind == "down":
            g.feed(t, ug.EV_ABS, ug.ABS_MT_TRACKING_ID, slot + 10)
        if kind == "up":
            g.feed(t, ug.EV_ABS, ug.ABS_MT_TRACKING_ID, -1)
        else:
            g.feed(t, ug.EV_ABS, ug.ABS_MT_POSITION_X, x); g.feed(t, ug.EV_ABS, ug.ABS_MT_POSITION_Y, y)
        g.feed(t, ug.EV_SYN, 0, 0)
    return fired

def line(t0, t1, p0, p1, n=12):
    return [(t0 + (t1 - t0) * i / n, p0[0] + (p1[0] - p0[0]) * i / n, p0[1] + (p1[1] - p0[1]) * i / n) for i in range(n + 1)]

fails = 0
def check(name, got, want):
    global fails
    ok = got == want
    fails += not ok
    print(("OK  " if ok else "FALLA"), name, got, "esperado", want)

# 2 dedos quietos 120 ms, casi simultaneos = tap2
check("tap2", run([(0, .12, [(0, 1000, 1000)]), (.02, .13, [(.02, 1200, 1000)])]), ["tap2"])
# 2 dedos que arrastran (scroll) NO dispara
check("scroll 2 dedos", run([(0, .5, line(0, .5, (1000, 1000), (1000, 1500))), (0, .5, line(0, .5, (1200, 1000), (1200, 1500)))]), [])
# pellizco 2 dedos NO dispara
check("pellizco 2 dedos", run([(0, .5, line(0, .5, (1000, 1000), (800, 1000))), (0, .5, line(0, .5, (1200, 1000), (1400, 1000)))]), [])
# toque largo 2 dedos (1 s) NO dispara
check("2 dedos largo", run([(0, 1.0, [(0, 1000, 1000)]), (.02, 1.0, [(.02, 1200, 1000)])]), [])
# 2 dedos desde borde inferior hacia arriba
check("two_edge_bottom", run([(0, .5, line(0, .5, (1000, 2120), (1000, 1700))), (.03, .5, line(.03, .5, (1200, 2120), (1200, 1700)))]), ["two_edge_bottom"])
# 2 dedos desde borde izquierdo hacia dentro
check("two_edge_left", run([(0, .5, line(0, .5, (10, 900), (400, 900))), (.03, .5, line(.03, .5, (10, 1100), (400, 1100)))]), ["two_edge_left"])
# 2 dedos desde el borde pero el segundo llega tarde (400 ms) -> nada
check("two_edge tardio", run([(0, 1.2, line(0, 1.2, (1000, 2120), (1000, 1700))), (.4, 1.2, line(.4, 1.2, (1200, 2120), (1200, 1700)))]), [])
# 1 dedo borde inferior: edge_bottom
check("edge_bottom", run([(0, .5, line(0, .5, (1000, 2120), (1000, 1800)))]), ["edge_bottom"])
# 3 dedos abajo / arriba / izquierda
def three(p0, d, t=.5): return [(0, t, line(0, t, (p0[0] + i * 200, p0[1]), (p0[0] + i * 200 + d[0], p0[1] + d[1]))) for i in range(3)]
check("three_down", run(three((1000, 600), (0, 450))), ["three_down"])
check("three_up", run(three((1000, 1400), (0, -450))), ["three_up"])
check("three_left", run(three((1500, 1000), (-450, 0))), ["three_left"])
# pellizco 3 dedos (juntarse) y separarse
def pinch(r0, r1):
    cx, cy = 1600, 1000
    pts = [(1, 0), (-0.5, 0.866), (-0.5, -0.866)]
    return [(0, .5, line(0, .5, (cx + r0 * dx, cy + r0 * dy), (cx + r1 * dx, cy + r1 * dy))) for dx, dy in pts]
check("three_pinch_in", run(pinch(400, 150)), ["three_pinch_in"])
check("three_pinch_out", run(pinch(150, 400)), ["three_pinch_out"])
# rotado 90 (transform 1): arrastre visual hacia abajo en pantalla = three_down con eje RAW distinto
# transform 1 (90 grados): un arrastre RAW hacia +x se ve hacia abajo
check("three_down t=1", run(three((1000, 600), (450, 0)), transform=1), ["three_down"])
check("three_right t=1", run(three((1000, 600), (0, -450)), transform=1), ["three_right"])
sys.exit(1 if fails else 0)
