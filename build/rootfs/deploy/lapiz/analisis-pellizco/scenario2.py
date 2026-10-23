"""Hipotesis: tras una rafaga de lapiz la rejilla 4bf tiene otra linea base (off). Sin tr.reset() (was_down=False al empezar) la base
del Tracker queda obsoleta y NUNCA se readapta (adapta solo e<thr_on/2) -> toque fantasma permanente -> el pellizco son 3 dedos."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import harness as H
from scenario import check

def seq(off, pen_with_finger=False):
    f = [H.finger_frame([]) for _ in range(12)] + [H.finger_frame(p) for p in H.pinch()] + [H.finger_frame([]) for _ in range(12)]
    if pen_with_finger: f += [H.finger_frame([(10, 10)]) for _ in range(5)]
    f += [H.pen_frame() for _ in range(40)]
    f += [H.finger_frame([], off=off) for _ in range(12)]
    f += [H.finger_frame(p, off=off) for p in H.pinch()] + [H.finger_frame([], off=off) for _ in range(12)]
    return f

def maxslots(out):
    n = 0; cur = 0; act = set(); s = 0
    for fr in out:
        for t, c, v in fr:
            if t == 3 and c == 0x2f: s = v
            if t == 3 and c == 0x39: (act.discard(s) if v == -1 else act.add(s))
        n = max(n, len(act))
    return n

if __name__ == "__main__":
    extra = sys.argv[1:]
    for off in (0, 700):
        for pf in (False, True):
            out, v = check("off=%d pen_with_finger=%s" % (off, pf), seq(off, pf), extra_patches=extra)
            second = out[-27:]
            print("    max dedos simultaneos en el 2o pellizco:", maxslots(out[-27:]), "(esperado 2); eventos tras la rafaga:", len(second))
