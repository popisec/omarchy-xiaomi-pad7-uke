import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import harness as H

def seq(pen_with_finger=False, pen_n=40, idle_n=12):
    f = [H.finger_frame([]) for _ in range(idle_n)]
    pinch1 = [H.finger_frame(p) for p in H.pinch()]
    f += pinch1 + [H.finger_frame([]) for _ in range(idle_n)]
    if pen_with_finger:
        f += [H.finger_frame([(10, 10)]) for _ in range(5)]          # palma/dedo apoyado al empezar
    f += [H.pen_frame(16) for _ in range(pen_n)]
    f += [H.finger_frame([]) for _ in range(idle_n)]
    mark = len(f)
    f += [H.finger_frame(p) for p in H.pinch()] + [H.finger_frame([]) for _ in range(idle_n)]
    return f

def check(name, frames, **kw):
    out, mod = H.run(frames, **kw)
    k = H.Kernel()
    for fr in out: k.apply(fr)
    v = k.finish()
    print("==", name, "frames evdev:", len(out), "violaciones:", len(v))
    for x in v[:6]: print("   ", x)
    return out, v

if __name__ == "__main__":
    for pf in (False, True):
        check("pen_with_finger=%s" % pf, seq(pf))
