#!/usr/bin/env python3
"""uke-touchd.py — demonio tactil de la uke: rejillas THP del NT36532 (spidev) -> toques -> /dev/uinput. 18-oct-2026.

Python puro (ioctl de spidev, gpio v2 y uinput). Algoritmo en thp_algo.py (validado contra la captura de Android:
1224 dedos, 4 FP, 1 FN, error mediana 10 px / p90 31 px frente al HAL de Xiaomi; thp_validate.py).

REQUIERE: /dev/spidev0.0 (spidev ligado a spi0.0) y el FIRMWARE del chip cargado (uke-touch-fwload.py); sin firmware
los frames no pasan la validacion de cabecera y el demonio no emite nada (lo dice en el log).

Uso: uke-touchd.py [--hz 120] [--no-irq] [--swap-xy] [--invert-x] [--invert-y] [--verbose]
  Coordenadas publicadas en pixeles del panel tal como lo muestra Linux (3200x2136, DSI-1). La orientacion se fija
  con --swap-xy/--invert-* (por defecto, medido: X de pantalla = Y de Android, Y de pantalla = X de Android invertido).
"""
import argparse, array, ctypes, fcntl, glob, os, select, struct, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import thp_algo  # noqa: E402

SPIDEV = "/dev/spidev0.0"
SPEED = 19_200_000
EVENT_BUF = 0x11c400                 # mapa CASCADE (NT36532 "Cascade Chip"; TACTIL-FWLOAD-20261018.md). 0x125800 = mapa single
THP_OFF, THP_LEN = 0x100, 0x1438    # buf+0x101 del vendor (buf[0] = comando) = dato+0x100
IRQ_LINE = 54                        # tlmm 54, flanco de subida (DT: novatek,irq-gpio <&tlmm 54 0x2001>)
SCR_W, SCR_H = 3200, 2136


def _ioc(d, t, nr, size):
    return (d << 30) | (size << 16) | (t << 8) | nr


# ---------------------------------------------------------------- spidev
class Spi:
    def __init__(self, path=SPIDEV, speed=SPEED):
        self.fd = os.open(path, os.O_RDWR)
        self.speed = speed
        fcntl.ioctl(self.fd, _ioc(1, ord('k'), 1, 1), struct.pack("B", 0))
        fcntl.ioctl(self.fd, _ioc(1, ord('k'), 3, 1), struct.pack("B", 8))
        fcntl.ioctl(self.fd, _ioc(1, ord('k'), 4, 4), struct.pack("I", speed))
        n = 2 + THP_OFF + THP_LEN
        self.tx = ctypes.create_string_buffer(n)   # todo ceros salvo tx[0..2], que read() restaura
        self.rx = ctypes.create_string_buffer(n)
        self._req = {}                             # n -> struct spi_ioc_transfer ya empaquetado (sin repack por frame)
        self._msg = _ioc(1, ord('k'), 0, 32)

    def _xfer(self, n):
        tr = self._req.get(n)
        if tr is None:
            tr = self._req[n] = bytearray(struct.pack("QQIIHBBBBBB", ctypes.addressof(self.tx), ctypes.addressof(self.rx),
                                                      n, self.speed, 0, 8, 0, 0, 0, 0, 0))
        fcntl.ioctl(self.fd, self._msg, tr)

    def read(self, addr, n, off=0):
        """Lee n bytes en addr; devuelve bytes desde el desplazamiento off (evita copiar lo que no se usa)."""
        tx = self.tx
        tx[0], tx[1], tx[2] = 0xFF, (addr >> 15) & 0xFF, (addr >> 7) & 0xFF
        self._xfer(4)
        tx[0], tx[1], tx[2] = addr & 0x7F, 0, 0
        self._xfer(n + 2)
        return ctypes.string_at(ctypes.addressof(self.rx) + 2 + off, n - off)


# ---------------------------------------------------------------- gpio v2 (flanco de subida en la linea IRQ)
def tlmm_chip():
    """gpiochip del TLMM: el de mas lineas (GPIO_GET_CHIPINFO_IOCTL: name[32], label[32], lines u32)."""
    best = None
    for name in sorted(os.listdir("/dev")):
        if not name.startswith("gpiochip"):
            continue
        try:
            fd = os.open("/dev/" + name, os.O_RDONLY)
            info = bytearray(68)
            fcntl.ioctl(fd, _ioc(2, 0xB4, 0x01, 68), info)
            os.close(fd)
        except OSError:
            continue
        label = info[32:64].split(b"\0")[0].decode(errors="replace")
        lines = struct.unpack_from("I", info, 64)[0]
        if best is None or lines > best[1]:
            best = ("/dev/" + name, lines, label)
    return best[0] if best else None


def gpio_edge_fd(chip, line):
    """Pide la linea como entrada con deteccion de flanco de subida (GPIO_V2_GET_LINE_IOCTL); devuelve el fd."""
    req = bytearray(592)
    struct.pack_into("I", req, 0, line)                        # offsets[0]
    req[256:256 + 9] = b"uke-touch"                            # consumer[32]
    struct.pack_into("Q", req, 288, (1 << 2) | (1 << 4))       # config.flags = INPUT | EDGE_RISING
    struct.pack_into("I", req, 560, 1)                         # num_lines
    struct.pack_into("I", req, 564, 64)                        # event_buffer_size
    fd = os.open(chip, os.O_RDWR)
    try:
        fcntl.ioctl(fd, _ioc(3, 0xB4, 0x07, 592), req)
    finally:
        os.close(fd)
    return struct.unpack_from("i", req, 588)[0]


# ---------------------------------------------------------------- uinput
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
BTN_TOUCH, BTN_TOOL_FINGER = 0x14a, 0x145
ABS_X, ABS_Y = 0, 1
ABS_MT_SLOT, ABS_MT_TOUCH_MAJOR, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID = 0x2f, 0x30, 0x35, 0x36, 0x39
INPUT_PROP_DIRECT = 1
NSLOTS = 10


class UInput:
    def __init__(self, w, h):
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        U = ord('U')
        io = lambda nr, v: fcntl.ioctl(self.fd, _ioc(1, U, nr, 4), v)  # noqa: E731
        io(100, EV_KEY); io(100, EV_ABS)
        io(101, BTN_TOUCH); io(101, BTN_TOOL_FINGER)
        io(110, INPUT_PROP_DIRECT)
        for code, mx in ((ABS_X, w - 1), (ABS_Y, h - 1), (ABS_MT_SLOT, NSLOTS - 1), (ABS_MT_TOUCH_MAJOR, 64),
                         (ABS_MT_POSITION_X, w - 1), (ABS_MT_POSITION_Y, h - 1), (ABS_MT_TRACKING_ID, 65535)):
            io(103, code)
            res = 13 if code in (ABS_X, ABS_Y, ABS_MT_POSITION_X, ABS_MT_POSITION_Y) else 0  # ~13 px/mm (237x158 mm)
            fcntl.ioctl(self.fd, _ioc(1, U, 4, 28), struct.pack("Hxxiiiiii", code, 0, 0, mx, 0, 0, res))
        setup = struct.pack("HHHH80sI", 0x18, 0x0603, 0x6532, 1, b"uke NT36532 THP touchscreen", 0)  # BUS_I2C-like 0x18
        fcntl.ioctl(self.fd, _ioc(1, U, 3, len(setup)), setup)
        fcntl.ioctl(self.fd, _ioc(0, U, 1, 0))                  # UI_DEV_CREATE
        self.slot_of = {}                                       # tracking id -> slot
        self.buf = []

    def ev(self, t, c, v):
        self.buf.append(struct.pack("qqHHi", 0, 0, t, c, v))

    def frame(self, pts):
        alive = {tid for tid, *_ in pts}
        for tid in [t for t in self.slot_of if t not in alive]:
            self.ev(EV_ABS, ABS_MT_SLOT, self.slot_of.pop(tid))
            self.ev(EV_ABS, ABS_MT_TRACKING_ID, -1)
        free = [s for s in range(NSLOTS) if s not in self.slot_of.values()]
        first = None
        for tid, x, y, area in pts:
            if tid not in self.slot_of:
                if not free:
                    continue
                self.slot_of[tid] = free.pop(0)
                self.ev(EV_ABS, ABS_MT_SLOT, self.slot_of[tid])
                self.ev(EV_ABS, ABS_MT_TRACKING_ID, tid & 0xFFFF)
            else:
                self.ev(EV_ABS, ABS_MT_SLOT, self.slot_of[tid])
            self.ev(EV_ABS, ABS_MT_POSITION_X, x)
            self.ev(EV_ABS, ABS_MT_POSITION_Y, y)
            self.ev(EV_ABS, ABS_MT_TOUCH_MAJOR, min(64, area))
            if first is None:
                first = (x, y)
        down = 1 if self.slot_of else 0
        self.ev(EV_KEY, BTN_TOUCH, down)
        self.ev(EV_KEY, BTN_TOOL_FINGER, down)
        if first:
            self.ev(EV_ABS, ABS_X, first[0])
            self.ev(EV_ABS, ABS_Y, first[1])
        self.ev(EV_SYN, 0, 0)
        os.write(self.fd, b"".join(self.buf))
        self.buf = []


FW = "/lib/firmware/novatek_nt36532_o82_fw_csot.bin"
FWLOAD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "uke-touch-fwload.py")
FWINFO = EVENT_BUF + 0x78


def log(*a):
    print("uke-touchd:", *a, flush=True)


def panel_state_path():
    """touch_reset_state del driver del panel O82 (senemos): '<generacion> <listo>' con sysfs_notify en cada cambio.
    La generacion sube en cada prepare (reset del panel => el chip tactil pierde el firmware de RAM); listo=1 tras el
    primer frame con el panel encendido, 0 al apagarlo."""
    g = glob.glob("/sys/devices/platform/soc/*display-subsystem/*.dsi/*.dsi.0/touch_reset_state")
    return g[0] if g else None


def read_state(fd):
    os.lseek(fd, 0, os.SEEK_SET)
    try:
        gen, ready = os.read(fd, 64).split()[:2]
        return int(gen), int(ready)
    except (OSError, ValueError):
        return None, 0


def fw_alive(spi):
    fi = spi.read(FWINFO, 2)
    return fi[0] == (~fi[1] & 0xFF) and fi[0] not in (0, 0xFF)


def load_fw():
    t = time.monotonic()
    r = subprocess.run([sys.executable, "-u", FWLOAD, "--execute", "--force", "--fw", FW],
                       capture_output=True, text=True, timeout=60)
    tail = [l for l in r.stdout.splitlines() if "FWINFO:" in l or "estado de reset" in l or "ERROR" in l.upper()]
    log("carga de firmware rc=%d en %.2f s: %s" % (r.returncode, time.monotonic() - t, " | ".join(tail[-2:])))
    return r.returncode == 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hz", type=float, default=120.0, help="ritmo de sondeo si no hay IRQ")
    ap.add_argument("--no-irq", action="store_true")
    ap.add_argument("--no-fwload", action="store_true", help="no cargar ni recargar el firmware del chip")
    ap.add_argument("--swap-xy", action="store_true")
    ap.add_argument("--invert-x", action="store_true")
    # orientacion MEDIDA (18-oct, dueno tocando esquinas): X correcto, Y invertido -> --invert-y por defecto
    ap.add_argument("--invert-y", action=argparse.BooleanOptionalAction, default=True)
    ap.add_argument("--verbose", action="store_true")
    # 19-oct: en reposo el chip lanza ~177 IRQ/s y procesar cada frame en Python costaba 36 % de un nucleo. En reposo se
    # procesa 1 de cada N IRQ (~60 Hz con N=3: el primer toque llega como mucho ~11 ms mas tarde); con dedo o durante
    # --hold-ms tras levantarlo, todas. En reposo duerme entre frames y vacia los flancos acumulados de una vez.
    ap.add_argument("--idle-div", type=int, default=3, help="en reposo, en reposo, frames procesados = 180/N por segundo (N=3: 60 Hz)")
    ap.add_argument("--hold-ms", type=int, default=500, help="ritmo completo durante este tiempo tras el ultimo toque")
    a = ap.parse_args()

    def to_screen(x, y):
        # Android: x 0..21360 (lado corto, filas), y 0..32000 (lado largo, columnas). Pantalla Linux 3200x2136.
        sx, sy = y / thp_algo.Y_MAX * SCR_W, x / thp_algo.X_MAX * SCR_H
        if a.swap_xy:
            sx, sy = x / thp_algo.X_MAX * SCR_W, y / thp_algo.Y_MAX * SCR_H
        if a.invert_x:
            sx = SCR_W - 1 - sx
        if a.invert_y:
            sy = SCR_H - 1 - sy
        return int(max(0, min(SCR_W - 1, sx))), int(max(0, min(SCR_H - 1, sy)))

    spi = Spi()
    ui = UInput(SCR_W, SCR_H)
    tr = thp_algo.Tracker()
    gfd = None
    if not a.no_irq:
        try:
            chip = tlmm_chip()
            gfd = gpio_edge_fd(chip, IRQ_LINE)
            log("IRQ por %s linea %d (flanco de subida)" % (chip, IRQ_LINE))
        except OSError as e:
            log("sin IRQ (%s); sondeo a %.0f Hz" % (e, a.hz))
    sp = panel_state_path()
    sfd = os.open(sp, os.O_RDONLY) if sp else None
    gen, ready = read_state(sfd) if sfd is not None else (None, 1)
    log("estado del panel: %s gen=%s listo=%s" % (sp or "(sin touch_reset_state: se asume listo)", gen, ready))
    loaded_gen = None
    if ready and not a.no_fwload:
        if fw_alive(spi):
            loaded_gen = gen
            log("firmware ya vivo en el chip")
        elif load_fw():
            loaded_gen = gen
    elif a.no_fwload:
        loaded_gen = gen
    poller = select.poll()
    if gfd is not None:
        poller.register(gfd, select.POLLIN)
    if sfd is not None:
        poller.register(sfd, select.POLLPRI | select.POLLERR)
    period_ms = int(1000 / a.hz)
    mut = array.array("H")
    good = bad = idle = 0
    last_log = last_frame = last_touch = time.monotonic()
    was_down = False
    hold = a.hold_ms / 1000.0
    idle_period = a.idle_div / 180.0                    # el chip da ~180 frames/s (medido 19-oct)
    next_idle = 0.0
    while True:
        if gfd is not None and a.idle_div > 1 and ready and not was_down:
            # reposo: dormir hasta el siguiente frame util; los flancos se acumulan en el fd y se vacian de una vez
            # (60 despertares/s en vez de 180)
            # 20-oct (bug visto por la sesion del lapiz): next_idle solo avanza EN reposo; durante --hold-ms va pegado al
            # reloj. Antes avanzaba un periodo por frame tambien a ritmo completo (3x mas rapido que el reloj) y al volver
            # al reposo dormia hasta ~1 s con el dedo y decenas de s con el lapiz (tactil muerto). Sueno acotado a 1 periodo.
            t = time.monotonic()
            if t - last_touch > hold:
                if next_idle > t:
                    time.sleep(min(next_idle - t, idle_period))
                next_idle = max(next_idle + idle_period, time.monotonic())
            else:
                next_idle = t
        evs = poller.poll(500 if gfd is not None else period_ms)
        now = time.monotonic()
        irq = gfd is None
        for fd, ev in evs:
            if fd == sfd:
                ng, nr = read_state(sfd)
                if (ng, nr) != (gen, ready):
                    log("panel: gen %s->%s listo %s->%s" % (gen, ng, ready, nr))
                    gen, ready = ng, nr
                    if was_down:
                        ui.frame([]); was_down = False
                    tr.reset()
            elif fd == gfd:
                os.read(gfd, 48 * 16)                           # vaciar eventos de flanco
                irq = True
        if not ready:
            continue
        if loaded_gen != gen and not a.no_fwload:
            time.sleep(0.05)
            if load_fw():
                loaded_gen = gen
                tr.reset()
                last_frame = time.monotonic()
            else:
                time.sleep(2)
            continue
        if not irq:
            # sin IRQ en 3 s con el panel listo: comprobar si el chip perdio el firmware (reset no notificado)
            if now - last_frame > 3 and not a.no_fwload:
                if not fw_alive(spi):
                    log("sin frames y FWINFO invalido: recarga")
                    loaded_gen = None
                last_frame = now
            continue
        last_frame = now
        F = spi.read(EVENT_BUF, THP_OFF + 0x40 + 2 * thp_algo.ROWS * thp_algo.COLS, THP_OFF)
        fid, mag, nid, nmag = struct.unpack_from("<H2xH2xH2xH", F, 4)
        if mag != thp_algo.MAGIC or nmag != (~thp_algo.MAGIC & 0xFFFF) or nid != (~fid & 0xFFFF):
            bad += 1
        else:
            good += 1
            del mut[:]
            mut.frombytes(F[0x40:0x40 + 2 * thp_algo.ROWS * thp_algo.COLS])
            if tr.quick_idle(mut):
                idle += 1
                if was_down:
                    ui.frame([]); was_down = False
            else:
                pts = [(tid, *to_screen(x, y), n) for tid, x, y, n in tr.feed(mut)]
                if pts or was_down:
                    ui.frame(pts)
                    if a.verbose and pts:
                        print("toques:", pts, flush=True)
                was_down = bool(pts)
                if was_down:
                    last_touch = now
        if now - last_log > 30:
            log("30 s: frames validos %d (reposo rapido %d), cabecera mala %d%s" % (
                good, idle, bad, "  <- sin firmware?" if good == 0 else ""))
            good = bad = idle = 0
            last_log = now


if __name__ == "__main__":
    main()
