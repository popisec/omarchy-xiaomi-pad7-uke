#!/usr/bin/env python3
"""Cuanta evidencia hay en los getevent de Android (cap6/7/8) sobre dedos (event11) justo antes/despues de lapiz (event12).
Uso: python3 analiza_android.py   (solo lectura; imprime tabla)."""
import os, re
A = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "..", "android", "lapiz-20261019")
R = re.compile(r"\[\s*([\d.]+)\]\s+(\w+)\s+(\w+)\s+(\w+)")


def parse(path):
    try:
        return [(float(m.group(1)), m.group(3), m.group(4)) for m in map(R.match, open(path)) if m]
    except OSError:
        return []


def fingers(ev):
    """[(t0,t1,x0,y0,maxdisp)] por contacto (tracking id)."""
    out, cur, slot = [], {}, 0
    for t, c, v in ev:
        if c == "ABS_MT_SLOT": slot = int(v, 16)
        elif c == "ABS_MT_TRACKING_ID":
            if v.lower() == "ffffffff":
                f = cur.pop(slot, None)
                if f: f[1] = t; out.append(tuple(f[:2]) + (f[2], f[3], f[6]))
            else: cur[slot] = [t, None, None, None, None, None, 0.0]
        elif c in ("ABS_MT_POSITION_X", "ABS_MT_POSITION_Y") and slot in cur:
            f = cur[slot]; val = int(v, 16)
            if c.endswith("X"): f[4] = val
            else: f[5] = val
            if f[4] is not None and f[5] is not None:
                if f[2] is None: f[2], f[3] = f[4], f[5]
                f[6] = max(f[6], ((f[4] - f[2]) ** 2 + (f[5] - f[3]) ** 2) ** .5)
    return out


def pen_ranges(ev, gap=0.3):
    """intervalos de lapiz en rango: BTN_DIGI DOWN..UP"""
    out, t0 = [], None
    for t, c, v in ev:
        if c == "BTN_DIGI":
            if v == "DOWN": t0 = t
            elif t0 is not None: out.append((t0, t)); t0 = None
    return out


def main():
    tot = []
    for cap, f11, f12 in [("cap6", "getevent-event11.txt", "getevent-event12.txt"),
                          ("cap7", "getevent-t1-event11.txt", "getevent-t2-event12.txt"),
                          ("cap8", "getevent-t1-event11.txt", "getevent-t1-event12.txt")]:
        e11, e12 = parse(os.path.join(A, cap, f11)), parse(os.path.join(A, cap, f12))
        fg, pr = fingers(e11), pen_ranges(e12)
        print("== %s: %d dedos (event11), %d rangos de lapiz (event12), t11=[%s] t12=[%s]" % (
            cap, len(fg), len(pr), (e11[0][0], e11[-1][0]) if e11 else "-", (e12[0][0], e12[-1][0]) if e12 else "-"))
        for t0, t1, x, y, d in fg:
            near = [(a, b) for a, b in pr if a - 2 <= t0 <= b + 2 or a - 2 <= t1 <= b + 2]
            if near:
                a, b = near[0]
                print("  dedo %.3f-%.3f (%.0f ms) desp.max %.0f u | lapiz %.3f-%.3f: inicio dedo %+.0f ms vs entrada lapiz, %+.0f ms vs salida" % (
                    t0, t1, (t1 - t0) * 1e3, d, a, b, (t0 - a) * 1e3, (t0 - b) * 1e3))
                tot.append((cap, t0 - a, t0 - b))
        if fg and not [1 for t0, *_ in fg if any(a - 2 <= t0 <= b + 2 for a, b in pr)]:
            print("  (ningun dedo a <2 s de un rango de lapiz)")
    print("dedos con lapiz a <2 s en total:", len(tot))


if __name__ == "__main__":
    main()
