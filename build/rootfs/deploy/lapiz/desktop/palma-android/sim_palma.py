#!/usr/bin/env python3
"""Simulacion con el arnes REAL (lapiz/analisis-pellizco/harness.py): ejecuta main() del demonio parcheado (uke-touchd.py + pen.patch +
uke-touchd-palm-android.patch) con SPI/uinput/reloj falsos y valida los eventos kernel-like. Un frame = 1/226 s (4,42 ms).
Uso: python3 sim_palma.py   (imprime una tabla por escenario; los asserts estan en test_sim_palma.py)."""
import importlib.util, os, select, shutil, struct, subprocess, sys, tempfile, types

HERE = os.path.dirname(os.path.abspath(__file__))
DEP = os.path.join(HERE, "..", "..", "..")
sys.path.insert(0, os.path.join(DEP, "lapiz", "analisis-pellizco"))
import harness as H  # noqa: E402

DT = 1 / 226.0
PATCH = os.path.join(HERE, "uke-touchd-palm-android.patch")


def build(extra_patches=(), base_patch=None):
    """Como H.build pero con el parche Android en vez del PalmGuard antiguo."""
    d = tempfile.mkdtemp()
    dst = os.path.join(d, "uke-touchd.py")
    for f, src in (("uke-touchd.py", os.path.join(DEP, "tactil", "uke-touchd.py")), ("thp_algo.py", os.path.join(DEP, "tactil", "thp_algo.py")),
                   ("palm_android.py", os.path.join(HERE, "palm_android.py"))):
        shutil.copy(src, os.path.join(d, f))
    subprocess.run(["patch", "-p0", "-s", dst, base_patch or os.path.join(DEP, "lapiz", "uke-touchd-pen.patch")], check=True)
    subprocess.run(["patch", "-p0", "-s", dst, PATCH], check=True)
    return dst


def build_plain():
    """uke-touchd.py + pen.patch SIN el parche Android (referencia de comportamiento previo)."""
    d = tempfile.mkdtemp()
    dst = os.path.join(d, "uke-touchd.py")
    for f in ("uke-touchd.py", "thp_algo.py"):
        open(os.path.join(d, f), "w").write(open(os.path.join(DEP, "tactil", f)).read())
    subprocess.run(["patch", "-p0", "-s", dst, os.path.join(DEP, "lapiz", "uke-touchd-pen.patch")], check=True)
    return dst


H.build = build


def run(frames, palm=True, args=(), plain=False):
    """Devuelve ([(indice_de_frame_de_entrada, [(t,c,v)..]) por SYN], modulo). Copia reducida de H.run con el indice anotado."""
    a = ("--pen",) + (("--palm-android",) if (palm and not plain) else ()) + tuple(args)
    path = build_plain() if plain else H.build()
    spec = importlib.util.spec_from_file_location("touchd_palma_t", path)
    sys.path.insert(0, os.path.dirname(path))
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    sys.path.pop(0)
    out, cur, idx = [], [], [-1]
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
            clock[0] += DT; idx[0] += 1
            return queue.pop(0).ljust(n - off, b"\0")
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
            if (t, c) == (H.EV_SYN, 0):
                out.append((idx[0], list(cur))); cur.clear()
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
    U = H.U

    class FPenUI:
        def __init__(s, *a): s.events = []
        def apply(s, evs, ts): s.events += list(evs)
        def close(s): pass
        def release(s, *a): pass

    class FSock:
        def fileno(s): return rfd + 1000
        def close(s): pass
    U.PenUInput = FPenUI; U.open_ble_socket = lambda *a: FSock(); U.PenKeys = lambda *a: types.SimpleNamespace(close=lambda: None, key=lambda *a: None)
    orig_argv = sys.argv; sys.argv = ["touchd"] + list(a) + ["--no-fwload"]
    try:
        mod.main()
    except Done:
        pass
    finally:
        sys.argv = orig_argv; os.write = real_write; os.close(rfd); os.close(wfd)
    return out, mod



def downs(out, lo=0, hi=10 ** 9):
    """indices de frame de entrada de cada inicio de contacto (TRACKING_ID >= 0) en [lo, hi)"""
    return [i for i, fr in out if lo <= i < hi for t, c, v in fr if t == H.EV_ABS and c == H.TID and v >= 0]


def kernel(out):
    k = H.Kernel(); mx = 0
    for _, fr in out:
        k.apply(fr); mx = max(mx, len(k.slots))
    return mx, k.finish()


def max_simult(out, lo, hi):
    k = H.Kernel(); mx = 0
    for i, fr in out:
        k.apply(fr)
        if lo <= i < hi: mx = max(mx, len(k.slots))
    return mx


# --- constructores de secuencias ---------------------------------------------------------------------------------------------
IDLE = lambda n: [H.finger_frame([]) for _ in range(n)]            # noqa: E731
PEN = lambda n, contact=16: [H.pen_frame(contact) for _ in range(n)]  # noqa: E731
FING = lambda n, pts: [H.finger_frame(pts) for _ in range(n)]      # noqa: E731
PALM = [(10, 10), (10, 11)]        # palma = 2 picos vecinos (area grande)


def ms(x):
    return int(round(x / (DT * 1e3)))


def pinch_frames(off=0):
    return [H.finger_frame(p, off=off) for p in H.pinch()]          # 25 frames (110 ms), 2 dedos


def scenarios():
    """nombre -> (frames, marcas) ; marcas = indices de entrada [inicio, fin) de cada fase"""
    S = {}

    def seq(name, parts):
        f, m = [], {}
        for key, fr in parts:
            m[key] = (len(f), len(f) + len(fr)); f += fr
        S[name] = (f, m)

    seq("pellizco_sin_lapiz", [("idle", IDLE(12)), ("pinch", pinch_frames()), ("fin", IDLE(12))])
    for off in (0, 700):
        for pf in (False, True):
            seq("pellizco_tras_rafaga_off%d_pf%d" % (off, pf), [
                ("idle", IDLE(12)), ("p1", pinch_frames()), ("i2", IDLE(12)), ("apoyado", FING(5, [(10, 10)]) if pf else []),
                ("pen", PEN(40)), ("i3", IDLE(12, ) if False else [H.finger_frame([], off=off) for _ in range(12)]),
                ("pinch", pinch_frames(off)), ("fin", [H.finger_frame([], off=off) for _ in range(12)])])
    # palma que llega ANTES del lapiz (35 ms antes, quieta), el lapiz escribe 0,44 s, la palma sigue apoyada 0,27 s y se levanta; luego pellizco
    seq("palma_antes_del_lapiz", [("idle", IDLE(12)), ("palma_pre", FING(ms(35), PALM)), ("pen", PEN(100)), ("palma_post", FING(60, PALM)),
                                  ("fin_palma", IDLE(30)), ("pinch", pinch_frames()), ("fin", IDLE(12))])
    # palma que llega cuando el chip ya escanea solo lapiz: el primer frame de dedos tras la rafaga la trae (acarreo)
    seq("palma_durante_escritura", [("idle", IDLE(12)), ("pen", PEN(100)), ("palma_post", FING(80, PALM)), ("fin_palma", IDLE(30)),
                                    ("pinch", pinch_frames()), ("fin", IDLE(12))])
    # la palma llega 20 ms DESPUES del ultimo frame de lapiz (dentro del margen), quieta
    seq("palma_20ms_tras_lapiz", [("idle", IDLE(12)), ("pen", PEN(100)), ("hueco", IDLE(ms(20))), ("palma_post", FING(80, PALM)),
                                  ("fin_palma", IDLE(30)), ("pinch", pinch_frames()), ("fin", IDLE(12))])
    # palma apoyada que NO se levanta mientras dos dedos pellizcan despues (la palma baneada no cuenta como dedo)
    seq("pellizco_con_palma_baneada", [("idle", IDLE(12)), ("pen", PEN(100)), ("palma_post", FING(30, PALM)),
                                       ("pinch", [H.finger_frame(p + PALM) for p in H.pinch()]), ("palma_sola", FING(20, PALM)), ("fin", IDLE(12))])
    # dedo suelto 500 ms tras el lapiz: debe entrar SIN retardo
    seq("dedo_500ms_tras_lapiz", [("idle", IDLE(12)), ("pen", PEN(60)), ("espera", IDLE(ms(500))), ("dedo", FING(30, [(20, 30)])), ("fin", IDLE(12))])
    # dedo suelto SIN lapiz alguno: sin retardo
    seq("dedo_sin_lapiz", [("idle", IDLE(20)), ("dedo", FING(30, [(20, 30)])), ("fin", IDLE(12))])
    # dedo que se mueve (1 nodo = 53 px cada 2 frames) 40 ms tras el lapiz: pasa a los 40 ms (hover) o 64 ms (acaba de escribir) de aparecer
    mov = [H.finger_frame([(20, 20 + i // 2)]) for i in range(40)]
    for tag, contact in (("hover", 0), ("escritura", 16)):
        seq("dedo_moviendose_tras_%s" % tag, [("idle", IDLE(12)), ("pen", PEN(60, contact)), ("hueco", IDLE(ms(40))), ("dedo", mov), ("fin", IDLE(12))])
        # toque breve (3 frames = 13 ms) a 20 ms del lapiz: tras hover se re-emite como toque de 1 frame; tras escribir se descarta (rebote de palma)
        seq("toque_breve_tras_%s" % tag, [("idle", IDLE(12)), ("pen", PEN(60, contact)), ("hueco", IDLE(ms(20))), ("toque", FING(3, [(20, 30)])), ("fin", IDLE(12))])
    # estres (el chip real NO intercala, Android 2718 frames sin 4bf dentro de una rafaga): palma intercalada con lapiz
    f = IDLE(12); a = len(f)
    for _ in range(25): f += PEN(2) + FING(1, PALM)
    f += PEN(10) + FING(40, PALM) + IDLE(20)
    S["estres_intercalado"] = (f, dict(todo=(a, len(f))))
    # dos rafagas seguidas con un pellizco entre medias (0,5 s entre ellas)
    seq("pellizco_entre_rafagas", [("idle", IDLE(12)), ("pen", PEN(60)), ("espera", IDLE(ms(400))), ("pinch", pinch_frames()),
                                   ("i", IDLE(20)), ("pen2", PEN(60)), ("espera2", IDLE(ms(400))), ("pinch2", pinch_frames()), ("fin", IDLE(12))])
    return S


def report():
    for name, (f, m) in scenarios().items():
        out, _ = run(f)
        base, _ = run(f, palm=False)
        mx, v = kernel(out)
        print("%-34s eventos %3d (sin modulo %3d) violaciones %d  max dedos %d  downs en %s" % (
            name, len(out), len(base), len(v), mx, downs(out)[:6]))


if __name__ == "__main__":
    report()
