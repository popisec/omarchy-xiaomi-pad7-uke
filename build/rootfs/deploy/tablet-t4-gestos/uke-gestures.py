#!/usr/bin/env python3
"""uke-gestures.py — gestos de borde y de 3 dedos para la tablet uke (T4, 18-oct-2026).

Lee en modo PASIVO (sin EVIOCGRAB) el evdev del tactil «uke NT36532 THP touchscreen»: Hyprland sigue recibiendo
todos los toques; este demonio solo observa y lanza comandos.  Python puro, sin dependencias.

Gestos (bordes segun la orientacion VISUAL del monitor, leida de `hyprctl monitors -j` -> transform):
  edge_top / edge_bottom / edge_left / edge_right   un dedo que EMPIEZA en el margen y recorre > edge_dist hacia dentro
  three_up / three_down / three_left / three_right  tres dedos que se desplazan > three_dist (centroide)
Cada gesto lanza el comando de [actions] del conf (vacio = solo registrar).

Uso: uke-gestures.py [--conf F] [--log] [--act] [--record F] [--replay F [--transform N]] [--device /dev/input/eventN]
  --log      imprime cada toque (inicio/fin, coordenadas visuales) y cada gesto; con --log NO se ejecutan acciones (--act las activa)
  --record   guarda los eventos crudos (24 B c/u) para reproducirlos luego
  --replay   lee un fichero grabado, con sus marcas de tiempo, sin ejecutar acciones (siempre en seco)
  SIGHUP recarga el conf.
"""
import argparse, configparser, fcntl, glob, json, os, re, select, signal, struct, subprocess, sys, time

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
    for k in ("edge_max_lateral", "three_dominance", "rotation_poll_s"):
        cfg[k] = float(cfg[k])
    for k in ("edge_time_ms", "three_time_ms", "cooldown_ms"):
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
                out.append((vx, vy, vw, vh))
        return out

    def step(self, t):
        n = len([s for s in self.slots.values() if s["x"] is not None and s["y"] is not None])
        seq = self.seq
        if n == 0:
            if seq is not None:
                self.say(f"fin   t={t:.3f} dur={t - seq['t0']:.2f}s maxdedos={seq['maxn']} fired={seq['done']}")
            self.reset_seq()
            return
        if seq is None:
            tr = self.rot.get(t)
            pts = self.points(tr)
            vx, vy, vw, vh = pts[0]
            m = self.cfg["edge_margin"]
            edges = [e for e, ok in (("top", vy < m), ("bottom", vy >= vh - m), ("left", vx < m), ("right", vx >= vw - m)) if ok] if n == 1 else []
            seq = self.seq = {"t0": t, "tr": tr, "vw": vw, "vh": vh, "start": (vx, vy), "edges": edges, "maxn": n,
                              "done": False, "c0": None, "t3": None}
            self.say(f"toque t={t:.3f} transform={tr} visual=({vx},{vy}) de {vw}x{vh} bordes={edges or '-'}")
        pts = self.points(seq["tr"])
        if len(pts) > seq["maxn"]:
            seq["maxn"] = len(pts)
        if seq["done"]:
            return
        if seq["maxn"] >= 2:
            seq["edges"] = []          # un segundo dedo anula el candidato a borde
        if len(pts) >= 3:
            self.three(t, seq, pts)
        elif len(pts) == 1 and seq["edges"]:
            self.edge(t, seq, pts[0])

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
        if seq["c0"] is None:      # referencia = centroide en el instante en que hay 3 dedos
            seq["c0"], seq["t3"] = (cx, cy), t
            return
        if t - seq["t3"] > c["three_time_ms"]:
            return
        dx, dy = cx - seq["c0"][0], cy - seq["c0"][1]
        ax, ay = abs(dx), abs(dy)
        if max(ax, ay) < c["three_dist"]:
            return
        if ay >= c["three_dominance"] * ax:
            name = "three_down" if dy > 0 else "three_up"
        elif ax >= c["three_dominance"] * ay:
            name = "three_right" if dx > 0 else "three_left"
        else:
            return
        self.trigger(t, seq, name, f"dx={dx:.0f} dy={dy:.0f}")

    def trigger(self, t, seq, name, detail):
        seq["done"] = True
        if t - self.last_fire < self.cfg["cooldown_ms"]:
            self.say(f"GESTO {name} ({detail}) ignorado por cooldown")
            return
        self.last_fire = t
        cmd = self.cfg["actions"].get(name, "").strip()
        self.say(f"GESTO {name} ({detail}) t={t:.3f} -> {cmd or '(sin accion)'}")
        if cmd:
            self.fire(name, cmd)


def run_cmd(name, cmd):
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
    ap.add_argument("--transform", type=int, help="fija la rotacion (replay, o forzar sin hyprctl)")
    a = ap.parse_args()
    cfg = load_conf(a.conf)
    W, H = 3200, 2136
    out = lambda m: print(m, flush=True)
    dry = a.replay is not None or (a.log and not a.act)
    fire = (lambda n, c: None) if dry else run_cmd
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
