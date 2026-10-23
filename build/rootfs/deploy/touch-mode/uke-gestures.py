#!/usr/bin/env python3
"""uke-gestures.py v2 (touch-mode, 18-oct-2026) — gestos de borde, 2 y 3 dedos para la tablet uke. Base: T4.

Lee en modo PASIVO (sin EVIOCGRAB) el evdev del tactil «uke NT36532 THP touchscreen»: Hyprland sigue recibiendo
todos los toques; este demonio solo observa y lanza comandos.  Python puro, sin dependencias.

Gestos (bordes segun la orientacion VISUAL del monitor, leida de `hyprctl monitors -j` -> transform):
  edge_top / edge_bottom / edge_left / edge_right   un dedo que EMPIEZA en el margen y recorre > edge_dist hacia dentro
  three_up / three_down / three_left / three_right  tres dedos que se desplazan > three_dist (centroide)
  three_pinch_in / three_pinch_out                  tres dedos que se juntan / separan (radio medio < pinch_in / > pinch_out)
  two_edge_top/bottom/left/right                    DOS dedos que empiezan juntos en ese borde y entran > two_edge_dist
  tap2                                              toque corto con 2 dedos casi quietos (= clic derecho: accion "@rightclick")
Scroll y pellizco de 2 dedos EN MEDIO de la pantalla no se tocan: los hacen las apps.
Acciones especiales (en vez de un comando de shell): "@rightclick" (clic derecho en el punto del toque, por uinput) y
"@key alt+left" (pulsa esa combinacion por un teclado virtual uinput).
Cada gesto lanza el comando de [actions] del conf (vacio = solo registrar).

Uso: uke-gestures.py [--inject rightclick FX FY | --inject key COMBO] [--conf F] [--log] [--act] [--record F] [--replay F [--transform N]] [--device /dev/input/eventN]
  --log      imprime cada toque (inicio/fin, coordenadas visuales) y cada gesto; con --log NO se ejecutan acciones (--act las activa)
  --record   guarda los eventos crudos (24 B c/u) para reproducirlos luego
  --replay   lee un fichero grabado, con sus marcas de tiempo, sin ejecutar acciones (siempre en seco)
  SIGHUP recarga el conf.
"""
import argparse, configparser, fcntl, glob, json, os, re, select, signal, struct, subprocess, sys, time
import math

NAME = "uke NT36532 THP touchscreen"
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
ABS_MT_SLOT, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID = 0x2f, 0x35, 0x36, 0x39
EVFMT = "llHHi"
EVSZ = struct.calcsize(EVFMT)

DEFAULTS = {
    "gestures": {
        "edge_margin": "40",       # px fisicos del panel (13 px/mm): el toque debe EMPEZAR a menos de esto del borde
        "edge_dist": "220",        # px que debe recorrer hacia dentro (~17 mm)
        "edge_max_lateral": "0.8", # |deriva lateral| / recorrido hacia dentro maximo (0.8 ~ 39 grados)
        "edge_time_ms": "900",     # tiempo maximo desde que toca hasta superar edge_dist
        "three_dist": "300",       # px de desplazamiento del centroide
        "three_dominance": "1.5",  # el eje dominante debe superar al otro por este factor
        "three_time_ms": "1200",
        "cooldown_ms": "500",      # tras un gesto no se acepta otro durante este tiempo
        "monitor": "",             # nombre del monitor para la rotacion (vacio = el primero)
        "rotation_poll_s": "2",    # reconsulta hyprctl si la ultima lectura es mas vieja que esto (al tocar)
        "pinch_in": "0.65",        # 3 dedos: radio medio final / inicial por debajo de esto = pinch_in
        "pinch_out": "1.5",        # ... por encima de esto = pinch_out
        "pinch_move_max": "150",   # px: el centroide no debe haberse movido mas que esto (si no, es un deslizamiento)
        "two_edge_dist": "200",    # 2 dedos desde el borde: recorrido hacia dentro del centroide
        "two_edge_window_ms": "250",  # el 2.o dedo debe tocar como mucho este tiempo despues del 1.o
        "two_edge_time_ms": "900",
        "tap2_time_ms": "350",     # toque con 2 dedos: duracion maxima desde que toca el 1.o hasta que se suelta el ultimo
        "tap2_window_ms": "150",   # ... los dos dedos deben tocar dentro de esta ventana
        "tap2_move": "50",         # ... ningun dedo se mueve mas de esto (px) -> si no es scroll/pellizco
    },
    "actions": {
        "edge_top": "omarchy-shell omarchy.power toggle",
        "edge_bottom": "/usr/local/bin/uke-osk-toggle",
        "edge_left": "hyprctl eval 'hl.dispatch(hl.dsp.focus({ workspace = \"e-1\" }))'",
        "edge_right": "hyprctl eval 'hl.dispatch(hl.dsp.focus({ workspace = \"e+1\" }))'",
        "three_down": "hyprctl eval 'hl.dispatch(hl.dsp.window.close())'",
        "three_up": "hyprctl eval 'hl.dispatch(hl.dsp.window.fullscreen({ mode = \"fullscreen\" }))'",
        "three_left": "",
        "three_right": "",
        "three_pinch_in": "",
        "three_pinch_out": "",
        "two_edge_top": "",
        "two_edge_bottom": "",
        "two_edge_left": "",
        "two_edge_right": "",
        "tap2": "",
    },
}


def load_conf(path):
    cp = configparser.ConfigParser(interpolation=None)
    cp.read_dict(DEFAULTS)
    try:
        cp.read(path)
    except configparser.Error as e:
        print(f"conf ilegible ({e}); uso valores por defecto", file=sys.stderr)
    g = cp["gestures"]
    cfg = {k: g[k] for k in DEFAULTS["gestures"]}
    for k in ("edge_margin", "edge_dist", "three_dist"):
        cfg[k] = int(cfg[k])
    for k in ("pinch_move_max", "two_edge_dist", "tap2_move"):
        cfg[k] = int(cfg[k])
    for k in ("edge_max_lateral", "three_dominance", "rotation_poll_s", "pinch_in", "pinch_out"):
        cfg[k] = float(cfg[k])
    for k in ("edge_time_ms", "three_time_ms", "cooldown_ms", "two_edge_window_ms", "two_edge_time_ms", "tap2_time_ms", "tap2_window_ms"):
        cfg[k] = int(cfg[k]) / 1000.0
    cfg["actions"] = dict(cp["actions"])
    return cfg


def find_device():
    try:
        txt = open("/proc/bus/input/devices").read()
    except OSError:
        return None
    for blk in txt.split("\n\n"):
        if f'Name="{NAME}"' in blk:
            m = re.search(r"event(\d+)", blk)
            if m:
                return f"/dev/input/event{m.group(1)}"
    return None


def absmax(fd, code, default):
    # EVIOCGABS(code) = _IOR('E', 0x40+code, struct input_absinfo[24 B])
    req = (2 << 30) | (24 << 16) | (ord("E") << 8) | (0x40 + code)
    try:
        buf = fcntl.ioctl(fd, req, b"\0" * 24)
        return struct.unpack("6i", buf)[2]
    except OSError:
        return default


def hypr_env():
    env = dict(os.environ)
    rt = env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    if not env.get("HYPRLAND_INSTANCE_SIGNATURE"):
        dirs = sorted(glob.glob(os.path.join(rt, "hypr", "*_*")), key=os.path.getmtime)
        if dirs:
            env["HYPRLAND_INSTANCE_SIGNATURE"] = os.path.basename(dirs[-1])
    env.setdefault("OMARCHY_PATH", "/usr/share/omarchy")
    env["PATH"] = f"{env['OMARCHY_PATH']}/bin:/usr/local/bin:" + env.get("PATH", "/usr/bin:/bin")
    if not env.get("WAYLAND_DISPLAY"):
        socks = sorted((f for f in glob.glob(os.path.join(rt, "wayland-[0-9]*")) if not f.endswith(".lock")), key=os.path.getmtime)
        if socks:
            env["WAYLAND_DISPLAY"] = os.path.basename(socks[-1])
    return env


class Rotation:
    """transform del monitor (0..7) con cache; hyprctl solo se consulta al tocar y si la lectura es vieja."""
    def __init__(self, cfg, fixed=None):
        self.cfg, self.fixed, self.val, self.at = cfg, fixed, 0, 0.0

    def get(self, now):
        if self.fixed is not None:
            return self.fixed
        if now - self.at < self.cfg["rotation_poll_s"]:
            return self.val
        self.at = now
        try:
            out = subprocess.run(["hyprctl", "monitors", "-j"], env=hypr_env(), capture_output=True, timeout=3, text=True).stdout
            mons = json.loads(out)
            name = self.cfg["monitor"]
            m = next((m for m in mons if m.get("name") == name), mons[0]) if mons else None
            if m is not None:
                self.val = int(m.get("transform", 0))
        except (OSError, ValueError, subprocess.SubprocessError):
            pass  # conserva el ultimo valor
        return self.val


def to_visual(x, y, W, H, t):
    """Coordenadas crudas (panel W x H, orientacion nativa) -> coordenadas del contenido tal como se ve con transform t.
    Hyprland: 1 = 90 grados antihorario, 2 = 180, 3 = 270; 4-7 = lo mismo con espejo (aqui: espejo en X crudo)."""
    if t >= 4:
        x = W - 1 - x
    r = t & 3
    if r == 0:
        return x, y, W, H
    if r == 1:
        return H - 1 - y, x, H, W
    if r == 2:
        return W - 1 - x, H - 1 - y, W, H
    return y, W - 1 - x, H, W


UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT = 0x40045564, 0x40045565, 0x40045567
UI_DEV_SETUP, UI_ABS_SETUP, UI_DEV_CREATE, UI_DEV_DESTROY = 0x405C5503, 0x401C5504, 0x5501, 0x5502
BTN_LEFT, BTN_RIGHT, ABS_X, ABS_Y, ABS_RES = 0x110, 0x111, 0, 1, 32767
KEYS = {"ctrl": 29, "shift": 42, "alt": 56, "super": 125, "esc": 1, "tab": 15, "enter": 28, "space": 57,
        "left": 105, "right": 106, "up": 103, "down": 108, "home": 102, "end": 107, "pageup": 104, "pagedown": 109,
        "f5": 63, "w": 17, "t": 20, "r": 19, "l": 38, "plus": 13, "minus": 12}


class Injector:
    """Dispositivos virtuales uinput: un puntero ABSOLUTO (clic en el punto del toque) y un teclado (combinaciones)."""
    def __init__(self, log):
        self.log, self.ptr, self.kbd, self.ok = log, None, None, False

    def _dev(self, name, keys, absaxes):
        fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
        for k in keys:
            fcntl.ioctl(fd, UI_SET_KEYBIT, k)
        if absaxes:
            fcntl.ioctl(fd, UI_SET_EVBIT, EV_ABS)
            for a in absaxes:
                fcntl.ioctl(fd, UI_SET_ABSBIT, a)
                fcntl.ioctl(fd, UI_ABS_SETUP, struct.pack("H2x6i", a, 0, 0, ABS_RES, 0, 0, 0))
        fcntl.ioctl(fd, UI_DEV_SETUP, struct.pack("4H80sI", 0x03, 0x1209, 0x0cb2 + len(keys), 1, name.encode(), 0))
        fcntl.ioctl(fd, UI_DEV_CREATE)
        return fd

    def open(self):
        try:
            self.ptr = self._dev("uke-gestures virtual pointer", [BTN_LEFT, BTN_RIGHT], [ABS_X, ABS_Y])
            self.kbd = self._dev("uke-gestures virtual keyboard", sorted(set(KEYS.values())), [])
            time.sleep(0.4)      # que el compositor los descubra antes del primer uso
            self.ok = True
            self.log("uinput: puntero y teclado virtuales creados")
        except OSError as e:
            self.log(f"uinput no disponible ({e}): '@rightclick' y '@key' no funcionaran (¿regla udev 71-uke-uinput.rules?)")

    def _w(self, fd, typ, code, val):
        os.write(fd, struct.pack(EVFMT, 0, 0, typ, code, val))

    def _syn(self, fd):
        self._w(fd, EV_SYN, 0, 0)

    def rightclick(self, fx, fy):
        if not self.ok:
            return
        fx, fy = min(max(fx, 0.0), 1.0), min(max(fy, 0.0), 1.0)
        self._w(self.ptr, EV_ABS, ABS_X, int(fx * ABS_RES)); self._w(self.ptr, EV_ABS, ABS_Y, int(fy * ABS_RES)); self._syn(self.ptr)
        time.sleep(0.04)
        self._w(self.ptr, EV_KEY, BTN_RIGHT, 1); self._syn(self.ptr)
        time.sleep(0.05)
        self._w(self.ptr, EV_KEY, BTN_RIGHT, 0); self._syn(self.ptr)

    def key(self, combo):
        if not self.ok:
            return
        codes = [KEYS[p] for p in combo.lower().split("+") if p in KEYS]
        for c in codes:
            self._w(self.kbd, EV_KEY, c, 1)
        self._syn(self.kbd)
        time.sleep(0.03)
        for c in reversed(codes):
            self._w(self.kbd, EV_KEY, c, 0)
        self._syn(self.kbd)


class Gestures:
    def __init__(self, cfg, W, H, rot, fire, log=None):
        self.cfg, self.W, self.H, self.rot, self.fire, self.log = cfg, W, H, rot, fire, log
        self.slots = {}      # slot -> dict(id,x,y)
        self.cur = 0
        self.dirty = False
        self.reset_seq()
        self.last_fire = -1e9

    def reset_seq(self):
        self.seq = None      # secuencia activa (desde el primer dedo hasta que no quedan dedos)

    def say(self, msg):
        if self.log:
            self.log(msg)

    def feed(self, t, typ, code, val):
        if typ == EV_ABS:
            if code == ABS_MT_SLOT:
                self.cur = val
            elif code == ABS_MT_TRACKING_ID:
                if val < 0:
                    self.slots.pop(self.cur, None)
                else:
                    self.slots[self.cur] = {"id": val, "x": None, "y": None}
                self.dirty = True
            elif code in (ABS_MT_POSITION_X, ABS_MT_POSITION_Y) and self.cur in self.slots:
                self.slots[self.cur]["x" if code == ABS_MT_POSITION_X else "y"] = val
                self.dirty = True
        elif typ == EV_SYN and code == 0 and self.dirty:
            self.dirty = False
            self.step(t)

    def points(self, tr):
        out = []
        for s in self.slots.values():
            if s["x"] is not None and s["y"] is not None:
                vx, vy, vw, vh = to_visual(s["x"], s["y"], self.W, self.H, tr)
                out.append((vx, vy, vw, vh, s["id"]))
        return out

    def step(self, t):
        n = len([s for s in self.slots.values() if s["x"] is not None and s["y"] is not None])
        seq = self.seq
        if n == 0:
            if seq is not None:
                self.tap2(t, seq)
                self.say(f"fin   t={t:.3f} dur={t - seq['t0']:.2f}s maxdedos={seq['maxn']} fired={seq['done']}")
            self.reset_seq()
            return
        if seq is None:
            tr = self.rot.get(t)
            pts = self.points(tr)
            vx, vy, vw, vh = pts[0][:4]
            m = self.cfg["edge_margin"]
            edges = [e for e, ok in (("top", vy < m), ("bottom", vy >= vh - m), ("left", vx < m), ("right", vx >= vw - m)) if ok] if n == 1 else []
            seq = self.seq = {"t0": t, "tr": tr, "vw": vw, "vh": vh, "start": (vx, vy), "edges": edges, "maxn": n,
                              "done": False, "c0": None, "t3": None, "r0": None,
                              "fingers": {}, "two_checked": False, "two": None}
            self.say(f"toque t={t:.3f} transform={tr} visual=({vx},{vy}) de {vw}x{vh} bordes={edges or '-'}")
        pts = self.points(seq["tr"])
        if len(pts) > seq["maxn"]:
            seq["maxn"] = len(pts)
        for vx, vy, vw, vh, fid in pts:
            f = seq["fingers"].setdefault(fid, {"t0": t, "s": (vx, vy), "move": 0.0})
            f["p"] = (vx, vy)
            f["move"] = max(f["move"], math.hypot(vx - f["s"][0], vy - f["s"][1]))
        if seq["done"]:
            return
        if seq["maxn"] >= 2:
            seq["edges"] = []          # un segundo dedo anula el candidato a borde
        if seq["maxn"] == 2 and not seq["two_checked"] and len(seq["fingers"]) == 2:
            self.two_edge_init(seq)
        if len(pts) >= 3:
            seq["two"] = None
            self.three(t, seq, pts)
        elif len(pts) == 2 and seq["two"]:
            self.two_edge(t, seq, pts)
        elif len(pts) == 1 and seq["edges"]:
            self.edge(t, seq, pts[0])

    def tap2(self, t, seq):
        c, fs = self.cfg, list(seq["fingers"].values())
        if seq["done"] or seq["maxn"] != 2 or len(fs) != 2 or t - seq["t0"] > c["tap2_time_ms"]:
            return
        if abs(fs[0]["t0"] - fs[1]["t0"]) > c["tap2_window_ms"] or max(f["move"] for f in fs) > c["tap2_move"]:
            return
        mx = (fs[0]["s"][0] + fs[1]["s"][0]) / 2 / seq["vw"]
        my = (fs[0]["s"][1] + fs[1]["s"][1]) / 2 / seq["vh"]
        self.trigger(t, seq, "tap2", f"dur={t - seq['t0']:.2f}s mov={max(f['move'] for f in fs):.0f}px", pos=(mx, my))

    def two_edge_init(self, seq):
        """Cuando aparece el 2.o dedo: ¿empezaron los dos en el mismo margen y casi a la vez?"""
        c, vw, vh = self.cfg, seq["vw"], seq["vh"]
        seq["two_checked"] = True
        fs = list(seq["fingers"].values())
        if abs(fs[0]["t0"] - fs[1]["t0"]) > c["two_edge_window_ms"]:
            return
        m = c["edge_margin"]
        tests = {"top": lambda p: p[1] < m, "bottom": lambda p: p[1] >= vh - m,
                 "left": lambda p: p[0] < m, "right": lambda p: p[0] >= vw - m}
        edges = [e for e, ok in tests.items() if all(ok(f["s"]) for f in fs)]
        if edges:
            cs = (sum(f["s"][0] for f in fs) / 2, sum(f["s"][1] for f in fs) / 2)
            seq["two"] = {"edges": edges, "c0": cs, "t0": min(f["t0"] for f in fs)}
            self.say(f"  2 dedos en borde {edges}")

    def two_edge(self, t, seq, pts):
        c, tw = self.cfg, seq["two"]
        if t - tw["t0"] > c["two_edge_time_ms"]:
            seq["two"] = None
            return
        cx = sum(p[0] for p in pts) / 2
        cy = sum(p[1] for p in pts) / 2
        dx, dy = cx - tw["c0"][0], cy - tw["c0"][1]
        for e in tw["edges"]:
            inward, lateral = {"top": (dy, dx), "bottom": (-dy, dx), "left": (dx, dy), "right": (-dx, dy)}[e]
            if inward >= c["two_edge_dist"] and abs(lateral) <= c["edge_max_lateral"] * inward:
                self.trigger(t, seq, f"two_edge_{e}", f"inward={inward:.0f} lateral={lateral:.0f}")
                return

    def edge(self, t, seq, p):
        c = self.cfg
        if t - seq["t0"] > c["edge_time_ms"]:
            seq["edges"] = []
            return
        dx, dy = p[0] - seq["start"][0], p[1] - seq["start"][1]
        for e in seq["edges"]:
            inward, lateral = {"top": (dy, dx), "bottom": (-dy, dx), "left": (dx, dy), "right": (-dx, dy)}[e]
            if inward >= c["edge_dist"] and abs(lateral) <= c["edge_max_lateral"] * inward:
                self.trigger(t, seq, f"edge_{e}", f"inward={inward} lateral={lateral}")
                return

    def three(self, t, seq, pts):
        c = self.cfg
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        rad = sum(math.hypot(p[0] - cx, p[1] - cy) for p in pts) / len(pts)
        if seq["c0"] is None:      # referencia = centroide y radio en el instante en que hay 3 dedos
            seq["c0"], seq["t3"], seq["r0"] = (cx, cy), t, max(rad, 1.0)
            return
        if t - seq["t3"] > c["three_time_ms"]:
            return
        dx, dy = cx - seq["c0"][0], cy - seq["c0"][1]
        ax, ay = abs(dx), abs(dy)
        ratio = rad / seq["r0"]
        if math.hypot(dx, dy) <= c["pinch_move_max"]:
            if ratio <= c["pinch_in"]:
                self.trigger(t, seq, "three_pinch_in", f"radio x{ratio:.2f}")
                return
            if ratio >= c["pinch_out"]:
                self.trigger(t, seq, "three_pinch_out", f"radio x{ratio:.2f}")
                return
        if max(ax, ay) < c["three_dist"]:
            return
        if ay >= c["three_dominance"] * ax:
            name = "three_down" if dy > 0 else "three_up"
        elif ax >= c["three_dominance"] * ay:
            name = "three_right" if dx > 0 else "three_left"
        else:
            return
        self.trigger(t, seq, name, f"dx={dx:.0f} dy={dy:.0f}")

    def trigger(self, t, seq, name, detail, pos=None):
        seq["done"] = True
        if t - self.last_fire < self.cfg["cooldown_ms"]:
            self.say(f"GESTO {name} ({detail}) ignorado por cooldown")
            return
        self.last_fire = t
        cmd = self.cfg["actions"].get(name, "").strip()
        self.say(f"GESTO {name} ({detail}) t={t:.3f} -> {cmd or '(sin accion)'}")
        if cmd:
            self.fire(name, cmd, pos)


INJ = None


def over_shell_layer(fx, fy):
    """True si (fx, fy) (fracciones de la pantalla visual) cae sobre una capa top/overlay (barra, teclado, paneles).
    20-oct: un clic derecho entregado a una ventana de Quickshell la tumba (SIGSEGV en deliverContextMenuEvent con
    activeFocusItem nulo; CAUSA-QUICKSHELL-LAPIZ.md / OSK-REWORK-20261020.md), asi que ahi no se inyecta."""
    try:
        env = hypr_env()
        mons = json.loads(subprocess.run(["hyprctl", "monitors", "-j"], env=env, capture_output=True, text=True, timeout=2).stdout)
        lays = json.loads(subprocess.run(["hyprctl", "layers", "-j"], env=env, capture_output=True, text=True, timeout=2).stdout)
    except (OSError, ValueError, subprocess.SubprocessError):
        return True                                     # sin datos: no arriesgar el shell
    for m in mons:
        w, h = m["width"] / m["scale"], m["height"] / m["scale"]
        if m.get("transform", 0) % 2:
            w, h = h, w
        x, y = m["x"] + fx * w, m["y"] + fy * h
        for lvl, ls in lays.get(m["name"], {}).get("levels", {}).items():
            if int(lvl) < 2:
                continue
            for l in ls:
                if l["x"] <= x < l["x"] + l["w"] and l["y"] <= y < l["y"] + l["h"]:
                    return True
    return False


def run_cmd(name, cmd, pos=None):
    if cmd.startswith("@"):
        verb, _, arg = cmd[1:].partition(" ")
        if INJ is None:
            return
        try:
            if verb == "rightclick":
                p = pos or (0.5, 0.5)
                if over_shell_layer(*p):
                    print(f"clic derecho omitido: cae sobre una capa del shell en {p}", flush=True)
                    return
                INJ.rightclick(*p)
            elif verb == "key":
                INJ.key(arg.strip())
            else:
                print(f"accion especial desconocida: {cmd}", file=sys.stderr, flush=True)
        except OSError as e:
            print(f"accion {name} fallo: {e}", file=sys.stderr, flush=True)
        return
    try:
        subprocess.Popen(["/bin/sh", "-c", cmd], env=hypr_env(), stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError as e:
        print(f"accion {name} fallo: {e}", file=sys.stderr, flush=True)


def reap(*_):
    try:
        while os.waitpid(-1, os.WNOHANG)[0]:
            pass
    except ChildProcessError:
        pass


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--conf", default=os.path.expanduser("~/.config/uke-gestures.conf"))
    ap.add_argument("--device")
    ap.add_argument("--log", action="store_true")
    ap.add_argument("--act", action="store_true", help="con --log, ejecutar tambien las acciones")
    ap.add_argument("--record")
    ap.add_argument("--replay")
    ap.add_argument("--inject", nargs="+", metavar="ARG", help="prueba: --inject rightclick FX FY (fracciones 0..1) | --inject key alt+left")
    ap.add_argument("--transform", type=int, help="fija la rotacion (replay, o forzar sin hyprctl)")
    a = ap.parse_args()
    cfg = load_conf(a.conf)
    W, H = 3200, 2136
    out = lambda m: print(m, flush=True)
    global INJ
    if a.inject:
        INJ = Injector(out)
        INJ.open()
        if a.inject[0] == "rightclick":
            INJ.rightclick(float(a.inject[1]), float(a.inject[2]))
        elif a.inject[0] == "key":
            INJ.key(a.inject[1])
        time.sleep(0.2)
        return
    dry = a.replay is not None or (a.log and not a.act)
    fire = (lambda n, c, p=None: None) if dry else run_cmd
    if not dry:
        INJ = Injector(out)
        INJ.open()
    tr = a.transform if a.transform is not None else (0 if a.replay else None)

    if a.replay:
        g = Gestures(cfg, W, H, Rotation(cfg, fixed=tr), fire, out)
        data = open(a.replay, "rb").read()
        for i in range(0, len(data) - EVSZ + 1, EVSZ):
            s, us, typ, code, val = struct.unpack_from(EVFMT, data, i)
            g.feed(s + us / 1e6, typ, code, val)
        return

    signal.signal(signal.SIGCHLD, reap)
    rot = Rotation(cfg, fixed=tr)
    g = Gestures(cfg, W, H, rot, fire, out if a.log else (lambda m: out(m) if m.startswith("GESTO") else None))  # sin --log, al journal solo los gestos
    signal.signal(signal.SIGHUP, lambda *_: (g.cfg.update(load_conf(a.conf)), out("conf recargado")))
    rec = open(a.record, "ab") if a.record else None
    while True:                                  # reconecta si el demonio del tactil se reinicia
        path = a.device or find_device()
        if not path:
            time.sleep(2)
            continue
        try:
            fd = os.open(path, os.O_RDONLY)
        except OSError as e:
            out(f"no puedo abrir {path}: {e}")
            time.sleep(2)
            continue
        g.W, g.H = absmax(fd, ABS_MT_POSITION_X, W - 1) + 1, absmax(fd, ABS_MT_POSITION_Y, H - 1) + 1
        g.slots.clear(); g.reset_seq()
        out(f"leyendo {path} ({g.W}x{g.H}) pasivo, sin grab; acciones {'DESACTIVADAS' if dry else 'activas'}")
        try:
            while True:
                select.select([fd], [], [])
                buf = os.read(fd, EVSZ * 64)
                if not buf:
                    break
                if rec:
                    rec.write(buf); rec.flush()
                for i in range(0, len(buf) - EVSZ + 1, EVSZ):
                    s, us, typ, code, val = struct.unpack_from(EVFMT, buf, i)
                    g.feed(s + us / 1e6, typ, code, val)
        except OSError as e:
            out(f"dispositivo perdido: {e}")
        finally:
            os.close(fd)
        time.sleep(1)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
