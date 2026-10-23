#!/usr/bin/env python3
"""thp_validate.py — valida thp_algo.Tracker contra la captura de Android (PC, sin tablet). 18-oct-2026.

Uso: thp_validate.py <dir frames/> <trace.txt> <getevent.txt> [--thr-on N --thr-peak N]
- frames/fNNNN.bin = F (6144 B) en orden; su instante = el N-esimo kprobe uke_thp0 de trace.txt.
- getevent.txt = salida de `getevent -lt` del NVTCapacitiveTouchScreen (la verdad: el HAL de Xiaomi).
Los relojes difieren (trace en BOOTTIME, getevent en MONOTONIC): se alinean por el primer toque.
Imprime: aciertos/falsos positivos/negativos por frame y el error de posicion (escala Android y en nodos).
"""
import argparse, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import thp_algo  # noqa: E402


def frame_times(trace):
    ts = []
    for line in open(trace, errors="replace"):
        if "uke_thp0:" in line:
            m = re.search(r" (\d+\.\d+): uke_thp0:", line)
            if m:
                ts.append(float(m.group(1)))
    return ts


def getevent_states(path):
    """Lista [(t, {slot: (x, y)})] en cada SYN_REPORT."""
    slots, cur, out = {}, 0, []
    for line in open(path, errors="replace"):
        m = re.match(r"\[\s*(\d+\.\d+)\]\s+(\S+)\s+(\S+)\s+(\S+)", line)
        if not m:
            continue
        t, typ, code, val = float(m.group(1)), m.group(2), m.group(3), m.group(4)
        if code == "ABS_MT_SLOT":
            cur = int(val, 16)
        elif code == "ABS_MT_TRACKING_ID":
            if val.lower() == "ffffffff":
                slots.pop(cur, None)
            else:
                slots.setdefault(cur, [None, None])
        elif code == "ABS_MT_POSITION_X":
            slots.setdefault(cur, [None, None])[0] = int(val, 16)
        elif code == "ABS_MT_POSITION_Y":
            slots.setdefault(cur, [None, None])[1] = int(val, 16)
        elif code == "SYN_REPORT":
            out.append((t, {k: tuple(v) for k, v in slots.items() if None not in v}))
    return out


def state_at(states, t):
    lo, hi = 0, len(states) - 1
    if not states or t < states[0][0]:
        return {}
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if states[mid][0] <= t:
            lo = mid
        else:
            hi = mid - 1
    return states[lo][1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("frames"); ap.add_argument("trace"); ap.add_argument("getevent")
    ap.add_argument("--thr-on", type=int, default=420); ap.add_argument("--thr-peak", type=int, default=600)
    ap.add_argument("--latency", type=float, default=0.0, help="segundos que el HAL va por detras del frame")
    ap.add_argument("--fast", action="store_true", help="usar la via rapida de reposo del demonio (quick_idle)")
    a = ap.parse_args()
    files = sorted(f for f in os.listdir(a.frames) if f.endswith(".bin"))
    ts = frame_times(a.trace)
    if len(ts) != len(files):
        print("AVISO: %d tiempos de trace para %d frames" % (len(ts), len(files)))
    states = getevent_states(a.getevent)
    tr = thp_algo.Tracker(thr_on=a.thr_on, thr_peak=a.thr_peak)
    res = []
    for i, f in enumerate(files):
        p = thp_algo.parse_frame(open(os.path.join(a.frames, f), "rb").read())
        if p is None:
            res.append((ts[i] if i < len(ts) else None, None))
            continue
        if a.fast and tr.quick_idle(p[1]):
            res.append((ts[i] if i < len(ts) else None, []))
            continue
        res.append((ts[i] if i < len(ts) else None, tr.feed(p[1])))
    t_first_frame = next((t for t, pts in res if pts), None)
    t_first_ge = next((t for t, s in states if s), None)
    if t_first_frame is None or t_first_ge is None:
        sys.exit("no hay toques en frames (%s) o en getevent (%s)" % (t_first_frame, t_first_ge))
    # desfase de relojes: barrido +-30 s en pasos de 5 ms maximizando la coincidencia del numero de dedos
    base_off = t_first_ge - t_first_frame
    best = (-1, base_off)
    for k in range(-6000, 6001):
        o = base_off + k * 0.005
        sc = sum(1 for t, pts in res[::3] if pts is not None and t is not None and len(state_at(states, t + o)) == len(pts))
        if sc > best[0]:
            best = (sc, o)
    off = best[1] + a.latency
    print("frames %d (cabecera mala: %d); estados getevent %d; desfase de relojes %.3f s"
          % (len(res), sum(1 for _, p in res if p is None), len(states), off))
    tp = fp = fn = tn = 0
    errs = []
    for t, pts in res:
        if pts is None or t is None:
            continue
        gt = list(state_at(states, t + off).values())
        mine = [(x, y) for _, x, y, _ in pts]
        if not gt and not mine:
            tn += 1
            continue
        used = set()
        for gx, gy in gt:
            best, bd = None, None
            for j, (x, y) in enumerate(mine):
                if j in used:
                    continue
                d = ((x - gx) ** 2 + (y - gy) ** 2) ** 0.5
                if bd is None or d < bd:
                    best, bd = j, d
            if best is None:
                fn += 1
            else:
                used.add(best)
                tp += 1
                errs.append(bd)
        fp += len(mine) - len(used)
    errs.sort()
    node = (thp_algo.X_MAX / thp_algo.ROWS + thp_algo.Y_MAX / thp_algo.COLS) / 2
    if errs:
        med, p90, mx = errs[len(errs) // 2], errs[int(len(errs) * 0.9)], errs[-1]
        print("dedos emparejados %d | falsos positivos %d | falsos negativos %d | frames vacios bien %d" % (tp, fp, fn, tn))
        print("error de posicion (escala Android 21360x32000): mediana %.0f  p90 %.0f  max %.0f  (= %.2f / %.2f / %.2f nodos;"
              " en pixeles del panel /10: %.0f / %.0f / %.0f px)" % (med, p90, mx, med / node, p90 / node, mx / node, med / 10, p90 / 10, mx / 10))
    else:
        print("sin emparejamientos (tp=%d fp=%d fn=%d)" % (tp, fp, fn))


if __name__ == "__main__":
    main()
