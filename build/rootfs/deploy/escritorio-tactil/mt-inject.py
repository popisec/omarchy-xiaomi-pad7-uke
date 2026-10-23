#!/usr/bin/env python3
"""mt-inject.py — pantalla tactil MULTITOQUE virtual (uinput, protocolo MT tipo B) para probar gestos de 2/3 dedos
en la tablet de extremo a extremo (ESCRITORIO-TACTIL 22-oct-2026).

Crea «uke-mt-prueba» (INPUT_PROP_DIRECT, 3200x2136 como el panel NT36532), escribe su /dev/input/eventN en el fichero
indicado, espera `--wait` s (para enganchar una instancia de prueba de uke-gestures.py con --device) y ejecuta los gestos.
Hyprland lo ve como un tactil mas: los toques llegan tambien a las apps, como con el dedo.
Uso: mt-inject.py --path-file F [--wait 3] GESTO [GESTO ...]   (orden: los gestos se separan 1,5 s)
     mt-inject.py --path-file F --stdin      (un gesto por linea en stdin; responde "hecho <gesto>"; EOF = fin)
Gestos: pinch_in pinch_out swipe3_left swipe3_right swipe3_up swipe3_down tap1:FX,FY
        path:X,Y;X,Y;...   (un dedo que recorre esos puntos en pixeles fisicos; para probar el swipe del teclado)
Necesita /dev/uinput (usuario omarchy, grupo input)."""
import argparse, fcntl, glob, math, os, struct, time

UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT, UI_SET_PROPBIT = 0x40045564, 0x40045565, 0x40045567, 0x4004556E
UI_DEV_SETUP, UI_ABS_SETUP, UI_DEV_CREATE, UI_DEV_DESTROY = 0x405C5503, 0x401C5504, 0x5501, 0x5502
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
BTN_TOUCH, BTN_TOOL_FINGER, BTN_TOOL_DOUBLETAP, BTN_TOOL_TRIPLETAP = 0x14A, 0x145, 0x14D, 0x14E
ABS_X, ABS_Y, ABS_MT_SLOT, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID = 0, 1, 0x2F, 0x35, 0x36, 0x39
INPUT_PROP_DIRECT = 1
W, H = 3200, 2136
NAME = "uke-mt-prueba"


class Touch:
    def __init__(self):
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_KEY)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_ABS)
        for k in (BTN_TOUCH, BTN_TOOL_FINGER, BTN_TOOL_DOUBLETAP, BTN_TOOL_TRIPLETAP):
            fcntl.ioctl(self.fd, UI_SET_KEYBIT, k)
        fcntl.ioctl(self.fd, UI_SET_PROPBIT, INPUT_PROP_DIRECT)
        for code, mx in ((ABS_X, W - 1), (ABS_Y, H - 1), (ABS_MT_SLOT, 9), (ABS_MT_POSITION_X, W - 1),
                         (ABS_MT_POSITION_Y, H - 1), (ABS_MT_TRACKING_ID, 65535)):
            fcntl.ioctl(self.fd, UI_SET_ABSBIT, code)
            # struct uinput_abs_setup { u16 code; (pad) ; input_absinfo {value,min,max,fuzz,flat,resolution} }
            fcntl.ioctl(self.fd, UI_ABS_SETUP, struct.pack("HxxiiiiiI", code, 0, 0, mx, 0, 0, 13 if code not in (ABS_MT_SLOT, ABS_MT_TRACKING_ID) else 0))
        fcntl.ioctl(self.fd, UI_DEV_SETUP, struct.pack("4H80sI", 0x18, 0x1209, 0x0cbf, 1, NAME.encode(), 0))
        fcntl.ioctl(self.fd, UI_DEV_CREATE)
        self.tid = 100
        self.down = {}

    def path(self):
        for d in glob.glob("/sys/class/input/event*"):
            try:
                if open(d + "/device/name").read().strip() == NAME:
                    return "/dev/input/" + os.path.basename(d)
            except OSError:
                pass
        return ""

    def ev(self, t, c, v):
        os.write(self.fd, struct.pack("llHHi", 0, 0, t, c, v))

    def frame(self, pts):
        """pts: lista de (x, y) o None por ranura; None = dedo levantado."""
        for slot, p in enumerate(pts):
            self.ev(EV_ABS, ABS_MT_SLOT, slot)
            if p is None:
                if slot in self.down:
                    self.ev(EV_ABS, ABS_MT_TRACKING_ID, -1)
                    del self.down[slot]
                continue
            if slot not in self.down:
                self.tid += 1
                self.down[slot] = self.tid
                self.ev(EV_ABS, ABS_MT_TRACKING_ID, self.tid)
            self.ev(EV_ABS, ABS_MT_POSITION_X, int(p[0]))
            self.ev(EV_ABS, ABS_MT_POSITION_Y, int(p[1]))
        n = len(self.down)
        self.ev(EV_KEY, BTN_TOUCH, 1 if n else 0)
        self.ev(EV_KEY, BTN_TOOL_FINGER, 1 if n == 1 else 0)
        self.ev(EV_KEY, BTN_TOOL_DOUBLETAP, 1 if n == 2 else 0)
        self.ev(EV_KEY, BTN_TOOL_TRIPLETAP, 1 if n == 3 else 0)
        if n:
            first = self.down and min(self.down)
            p0 = pts[first]
            self.ev(EV_ABS, ABS_X, int(p0[0])); self.ev(EV_ABS, ABS_Y, int(p0[1]))
        self.ev(EV_SYN, 0, 0)

    def stroke(self, start, end, dur=0.4, steps=24):
        """start/end: listas de puntos (mismo numero de dedos); interpola linealmente."""
        self.frame(start); time.sleep(0.03)
        for i in range(1, steps + 1):
            a = i / steps
            self.frame([(s[0] + (e[0] - s[0]) * a, s[1] + (e[1] - s[1]) * a) for s, e in zip(start, end)])
            time.sleep(dur / steps)
        time.sleep(0.03)
        self.frame([None] * len(start))

    def close(self):
        fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        os.close(self.fd)


def ring(cx, cy, r, n=3):
    return [(cx + r * math.cos(2 * math.pi * k / n + 0.3), cy + r * math.sin(2 * math.pi * k / n + 0.3)) for k in range(n)]


def do(t, g):
    cx, cy = W / 2, H / 2
    row = [(cx - 220, cy), (cx, cy - 40), (cx + 220, cy)]
    if g == "pinch_in":
        t.stroke(ring(cx, cy, 520), ring(cx, cy, 170))
    elif g == "pinch_out":
        t.stroke(ring(cx, cy, 170), ring(cx, cy, 520))
    elif g.startswith("swipe3_"):
        dx, dy = {"left": (-750, 0), "right": (750, 0), "up": (0, -650), "down": (0, 650)}[g[7:]]
        t.stroke(row, [(x + dx, y + dy) for x, y in row])
    elif g.startswith("path:"):
        pts = [tuple(map(float, q.split(","))) for q in g[5:].split(";") if q]
        t.frame([pts[0]]); time.sleep(0.04)
        for a, b in zip(pts, pts[1:]):
            n = max(3, int(math.dist(a, b) / 40))
            for i in range(1, n + 1):
                t.frame([(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n)])
                time.sleep(0.012)
        time.sleep(0.04)
        t.frame([None])
    elif g.startswith("tap1:"):
        fx, fy = map(float, g[5:].split(","))
        t.stroke([(fx * W, fy * H)], [(fx * W, fy * H)], dur=0.06, steps=2)
    else:
        raise SystemExit(f"gesto desconocido: {g}")


def input_line():
    try:
        line = input().strip()
    except EOFError:
        return None
    return line or input_line()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--path-file", required=True)
    ap.add_argument("--wait", type=float, default=3)
    ap.add_argument("--stdin", action="store_true")
    ap.add_argument("gestures", nargs="*")
    a = ap.parse_args()
    t = Touch()
    time.sleep(0.8)
    open(a.path_file, "w").write(t.path() + "\n")
    time.sleep(a.wait)
    try:
        if a.stdin:
            for line in iter(input_line, None):
                do(t, line)
                print(f"hecho {line}", flush=True)
        for g in a.gestures:
            print(f"gesto {g}", flush=True)
            do(t, g)
            time.sleep(1.5)
    finally:
        t.close()


if __name__ == "__main__":
    main()
