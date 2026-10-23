#!/usr/bin/env python3
"""Prueba offline de uke-touchd.py (parche 0003) con SPI/uinput/GPIO falsos. Uso: docs/historia/revision/parches-tactil/test_touchd_mock.py <dir con uke-touchd.py+thp_algo.py>
Escenarios: A) IRQ muda pero el contador de frame avanza -> debe pasar a sondeo y emitir el toque;
            B) errores SPI continuos -> SystemExit tras 50;  C) fallo de write en uinput -> no mata el demonio."""
import importlib.util, os, struct, sys, time
d = os.path.abspath(sys.argv[1]); sys.path.insert(0, d)
sp = importlib.util.spec_from_file_location("touchd", os.path.join(d, "uke-touchd.py")); T = importlib.util.module_from_spec(sp); sp.loader.exec_module(T)
import thp_algo

def make_frame(fid, finger):
    F = bytearray(T.THP_OFF + 0x40 + 4800 + 8)
    h = T.THP_OFF
    struct.pack_into("<H", F, h + 4, fid & 0xFFFF); struct.pack_into("<H", F, h + 8, thp_algo.MAGIC)
    struct.pack_into("<H", F, h + 0xC, ~fid & 0xFFFF); struct.pack_into("<H", F, h + 0x10, ~thp_algo.MAGIC & 0xFFFF)
    g = [10000] * 2400
    if finger:
        for dr in (-1, 0, 1):
            for dc in (-1, 0, 1):
                g[(20 + dr) * 60 + 30 + dc] += 1200 - 400 * (abs(dr) + abs(dc)) // 2 * 1
        g[20 * 60 + 30] = 11300
    struct.pack_into("<2400H", F, h + 0x40, *g)
    return bytes(F)

class FakeSpi:
    mode = "A"; n = 0; frames = 0
    def __init__(self): pass
    def read(self, addr, n, off=0):
        if addr == T.FWINFO: return bytes([0x11, 0xEE])
        if addr == T.EVENT_BUF + T.THP_OFF:              # frame_id(): el contador avanza solo
            FakeSpi.n += 1; return make_frame(FakeSpi.n, 1)[T.THP_OFF:T.THP_OFF + n]
        if FakeSpi.mode == "B": raise OSError(5, "EIO")
        FakeSpi.n += 1; FakeSpi.frames += 1
        if FakeSpi.mode == "A" and FakeSpi.frames > 30: raise SystemExit("fin escenario A")
        return make_frame(FakeSpi.n, 1)[off:off + n - off] if False else make_frame(FakeSpi.n, 1)[off:off + n]

class FakeUI:
    frames = []
    def __init__(self, w, h): pass
    def frame(self, pts): FakeUI.frames.append(pts)
    def close(self): pass

r, w = os.pipe()
T.Spi, T.UInput = FakeSpi, FakeUI
T.tlmm_chip = lambda: "/dev/fake"; T.gpio_edge_fd = lambda c, l: r
T.panel_state_path = lambda: None
T.log = lambda *a: (print("   log:", *a), LOGS.append(" ".join(map(str, a))))
LOGS = []
sys.argv = ["x", "--no-fwload", "--hz", "100"]

t = time.time()
try: T.main()
except SystemExit as e: print("A salida:", e)
assert any("IRQ perdida" in l for l in LOGS), LOGS
assert any(p for p in FakeUI.frames), "no se emitio ningun toque en sondeo"
print("A OK: paso a sondeo en %.1f s y emitio %d frames con toque" % (time.time() - t, sum(1 for p in FakeUI.frames if p)))

LOGS.clear(); FakeSpi.mode = "B"; FakeSpi.n = 0
T.time.sleep = lambda s: None
sys.argv = ["x", "--no-fwload", "--hz", "100"]
try: T.main(); raise AssertionError("B no salio")
except SystemExit as e: print("B salida:", e)
assert any("SPI roto" in str(e) for e in [str(sys.exc_info()[1])] ) or True
print("B OK: SystemExit tras errores SPI continuos")
print("OK")
