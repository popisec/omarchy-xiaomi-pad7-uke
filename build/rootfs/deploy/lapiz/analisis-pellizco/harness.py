#!/usr/bin/env python3
"""Arnes: ejecuta main() REAL del demonio (tactil/uke-touchd.py + pen.patch [+ palm.patch]) con Spi/UInput/poll/reloj falsos,
alimenta frames sinteticos (dedos 0x4BF y lapiz 0x509) y valida los eventos evdev emitidos como lo haria el kernel/libinput."""
import importlib.util, os, struct, subprocess, sys, tempfile, types, select

HERE = os.path.dirname(os.path.abspath(__file__))
DEP = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(DEP, "lapiz")); sys.path.insert(0, os.path.join(DEP, "tactil"))
import thp_pen as P, uke_pen as U, thp_algo as A  # noqa: E402
import test_lapiz as TL  # noqa: E402

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
SLOT, TID, BTN_TOUCH, TOOL_F, TOOL_D, TOOL_T = 0x2f, 0x39, 0x14a, 0x145, 0x14d, 0x14e


def build(extra_patches=(), base_patch=None):
    d = tempfile.mkdtemp()
    dst = os.path.join(d, "uke-touchd.py")
    open(dst, "w").write(open(os.path.join(DEP, "tactil", "uke-touchd.py")).read())
    open(os.path.join(d, "thp_algo.py"), "w").write(open(os.path.join(DEP, "tactil", "thp_algo.py")).read())
    subprocess.run(["patch", "-p0", "-s", dst, base_patch or os.path.join(DEP, "lapiz", "uke-touchd-pen.patch")], check=True)
    subprocess.run(["patch", "-p0", "-s", dst, os.path.join(DEP, "lapiz", "desktop", "uke-touchd-palm.patch")], check=True)
    for p in extra_patches:
        subprocess.run(["patch", "-p0", "-s", dst, p], check=True)
    return dst


def finger_frame(fingers, fid=[0], off=0):
    """fingers = [(row, col)] en nodos. Rejilla 40x60, base 10000."""
    g = [10000 + off] * (A.ROWS * A.COLS)
    for r, c in fingers:
        for dr in (-1, 0, 1):
            for dc in (-1, 0, 1):
                rr, cc = r + dr, c + dc
                if 0 <= rr < A.ROWS and 0 <= cc < A.COLS:
                    g[rr * A.COLS + cc] += 1300 if (dr, dc) == (0, 0) else 450
    fid[0] = (fid[0] + 1) & 0xFFFF
    F = bytearray(0x40 + 2 * A.ROWS * A.COLS)
    struct.pack_into("<H2xH2xH2xH", F, 4, fid[0], A.MAGIC, ~fid[0] & 0xFFFF, ~A.MAGIC & 0xFFFF)
    struct.pack_into("<%dH" % len(g), F, 0x40, *g)
    return bytes(F)


def pen_frame(contact=16):
    F = bytearray(TL.synth(contact=contact))
    return bytes(F) + bytes(max(0, 0x40 + 2 * A.ROWS * A.COLS - len(F)))


def pinch(n=25, r=20, c0=30, d0=14, d1=3):
    return [[(r, c0 - round(d0 + (d1 - d0) * i / (n - 1)) // 1), (r, c0 + round(d0 + (d1 - d0) * i / (n - 1)))] for i in range(n)]


def run(frames, extra_patches=(), base_patch=None, args=("--pen",), log=None):
    """frames: lista de bytes (cada uno = un IRQ). Devuelve lista de frames evdev: [[(t,c,v),..] por SYN]."""
    path = build(extra_patches, base_patch)
    spec = importlib.util.spec_from_file_location("touchd_under_test", path)
    sys.path.insert(0, os.path.dirname(path))
    sys.modules.pop("thp_algo_dummy", None)
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    sys.path.pop(0)
    out, cur = [], []
    rfd, wfd = os.pipe()
    clock = [1000.0]
    queue = list(frames)

    class Done(Exception):
        pass

    class FSpi:
        def __init__(s, *a, **k): pass
        def read(s, addr, n, off=0):
            if not queue:
                raise Done()
            clock[0] += 1 / 226.0
            F = queue.pop(0)
            return F.ljust(n - off, b"\0")
        write_regs = lambda s, *a: None  # noqa: E731

    class FUI(mod.UInput):
        def __init__(s, w, h):
            s.fd = -77; s.slot_of = {}; s.buf = []
    real_write = os.write
    def fwrite(fd, b):
        if fd != -77:
            return real_write(fd, b)
        for i in range(0, len(b), 24):
            t, c, v = struct.unpack_from("HHi", b, i + 16)
            cur.append((t, c, v))
            if (t, c) == (EV_SYN, 0):
                out.append(list(cur)); cur.clear()
        return len(b)
    os.write = fwrite

    class FPoll:
        def register(s, *a): pass
        def unregister(s, *a): pass
        def poll(s, to):
            real_write(wfd, b"x")
            return [(rfd, select.POLLIN)]
    class FTime:
        monotonic = staticmethod(lambda: clock[0])
        @staticmethod
        def sleep(x): clock[0] += x
        time = monotonic
    shim = types.SimpleNamespace(**{k: getattr(select, k) for k in dir(select) if not k.startswith("_")}); shim.poll = FPoll
    mod.Spi, mod.UInput, mod.select, mod.time = FSpi, FUI, shim, FTime
    mod.tlmm_chip = lambda: "x"; mod.gpio_edge_fd = lambda c, l: rfd
    mod.panel_state_path = lambda: None; mod.fw_alive = lambda spi: True
    class FPenUI:
        def __init__(s, *a): s.events = []
        def apply(s, evs, ts): s.events += list(evs)
        def close(s): pass
        def release(s, *a): pass
    class FSock:
        def fileno(s): return rfd + 1000
        def close(s): pass
    U.PenUInput = FPenUI; U.open_ble_socket = lambda *a: FSock(); U.PenKeys = lambda *a: types.SimpleNamespace(close=lambda: None, key=lambda *a: None)
    orig_argv = sys.argv; sys.argv = ["touchd"] + list(args) + ["--no-fwload"]
    try:
        mod.main()
    except Done:
        pass
    finally:
        sys.argv = orig_argv; os.write = real_write; os.close(rfd); os.close(wfd)
    return out, mod


class Kernel:
    """Maquina de estados MT tipo B + comprobaciones de coherencia (libevdev/libinput)."""
    def __init__(s):
        s.slots = {}; s.cur = 0; s.btn = {BTN_TOUCH: 0, TOOL_F: 0, TOOL_D: 0, TOOL_T: 0}; s.viol = []; s.n = 0

    def apply(s, frame):
        s.n += 1
        slot_set = False; touched_slot = {}
        for t, c, v in frame:
            if t == EV_ABS and c == SLOT:
                s.cur = v; slot_set = True
            elif t == EV_ABS and c == TID:
                if not slot_set: s.viol.append((s.n, "TID sin SLOT previo"))
                if v == -1:
                    if s.cur not in s.slots: s.viol.append((s.n, "fin de slot %d ya inactivo" % s.cur))
                    s.slots.pop(s.cur, None)
                else:
                    if s.cur in s.slots: s.viol.append((s.n, "TID nuevo en slot %d activo" % s.cur))
                    if v in s.slots.values(): s.viol.append((s.n, "tracking id %d repetido en otro slot" % v))
                    s.slots[s.cur] = v
            elif t == EV_ABS and c in (0x35, 0x36, 0x30):
                if not slot_set: s.viol.append((s.n, "posicion sin SLOT"))
                if s.cur not in s.slots: s.viol.append((s.n, "posicion en slot %d inactivo" % s.cur))
            elif t == EV_KEY and c in s.btn:
                s.btn[c] = v
        k = len(s.slots)
        if s.btn[BTN_TOUCH] != (1 if k else 0): s.viol.append((s.n, "BTN_TOUCH=%d con %d slots" % (s.btn[BTN_TOUCH], k)))
        if k and not s.btn[TOOL_F]: s.viol.append((s.n, "BTN_TOOL_FINGER=0 con %d slots" % k))
        if k == 0 and s.btn[TOOL_F]: s.viol.append((s.n, "BTN_TOOL_FINGER=1 sin slots"))
        # libinput: 2 dedos -> DOUBLETAP. El demonio no declara BTN_TOOL_DOUBLETAP; libinput cuenta slots, asi que solo se informa.

    def finish(s):
        if s.slots: s.viol.append((s.n, "slots atascados al final: %r" % s.slots))
        return s.viol
