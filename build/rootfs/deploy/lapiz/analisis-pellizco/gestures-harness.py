#!/usr/bin/env python3
"""Arnes: alimenta Gestures de uke-gestures.py con pellizco -> toque 1-3 dedos -> cancelacion masiva (palma) -> pellizco
y comprueba que no se atasca (tap2 de 2 dedos sigue reconociendose y la secuencia se cierra).
Uso: gestures-harness.py [ruta/uke-gestures.py]   (por defecto touch-mode/uke-gestures.py). Sale 1 si algo falla."""
import importlib.util, os, sys
here = os.path.dirname(os.path.abspath(__file__))
path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "../../touch-mode/uke-gestures.py")
spec = importlib.util.spec_from_file_location("ug", path); ug = importlib.util.module_from_spec(spec); spec.loader.exec_module(ug)
SLOT, X, Y, TID = ug.ABS_MT_SLOT, ug.ABS_MT_POSITION_X, ug.ABS_MT_POSITION_Y, ug.ABS_MT_TRACKING_ID
BTN_TOUCH = 0x14a

class Sim:
    def __init__(self):
        self.t, self.fired, self.tid = 1000.0, [], 0
        cfg = ug.load_conf("/nonexistent"); cfg["actions"] = {"tap2": "x"}
        self.g = ug.Gestures(cfg, 3200, 2136, ug.Rotation(cfg, fixed=0), lambda n, c, p=None: self.fired.append(n))
    def ev(self, typ, code, val): self.g.feed(self.t, typ, code, val)
    def syn(self, dt=0.01): self.ev(ug.EV_SYN, 0, 0); self.t += dt
    def down(self, slots):
        for s in slots:
            self.tid += 1; self.ev(ug.EV_ABS, SLOT, s); self.ev(ug.EV_ABS, TID, self.tid)
            self.ev(ug.EV_ABS, X, 1000 + 300 * s); self.ev(ug.EV_ABS, Y, 1000)
        self.ev(ug.EV_KEY, BTN_TOUCH, 1); self.syn()
    def move(self, slots, d):
        for s in slots: self.ev(ug.EV_ABS, SLOT, s); self.ev(ug.EV_ABS, X, 1000 + 300 * s + d)
        self.syn()
    def up(self, slots):
        for s in slots: self.ev(ug.EV_ABS, SLOT, s); self.ev(ug.EV_ABS, TID, -1)
        self.ev(ug.EV_KEY, BTN_TOUCH, 0); self.syn()
    def cancel_ghost(self):      # variante: solo BTN_TOUCH 0 + SYN, los slots no reciben TRACKING_ID -1
        self.ev(ug.EV_KEY, BTN_TOUCH, 0); self.syn()
    def pinch(self): self.down([0, 1]); self.move([0, 1], 60); self.up([0, 1])
    def tap2(self):
        self.fired.clear(); self.down([0, 1]); self.t += 0.1; self.up([0, 1]); return "tap2" in self.fired

def scenario(name, cancel):
    s = Sim(); ok = True
    s.pinch(); ok &= s.tap2()
    for n in (1, 2, 3):
        s.down(list(range(n))); s.t += 0.05
    cancel(s); s.t += 1.0                 # (cooldown pasado)
    seq_open = s.g.seq is not None; ghosts = len(s.g.slots)
    good = s.tap2()
    print(f"{name:28s} seq abierta tras cancelar={seq_open} slots fantasma={ghosts} tap2 reconocido despues={good}")
    return ok and good and not seq_open and ghosts == 0

def cancel_real(s):                        # TRACKING_ID -1 en todos + BTN_TOUCH 0 + SYN en un frame
    for sl in range(3): s.ev(ug.EV_ABS, SLOT, sl); s.ev(ug.EV_ABS, TID, -1)
    s.ev(ug.EV_KEY, BTN_TOUCH, 0); s.syn()
def cancel_partial(s):                     # solo se liberan 2 de 3 slots, BTN_TOUCH 0
    for sl in (0, 1): s.ev(ug.EV_ABS, SLOT, sl); s.ev(ug.EV_ABS, TID, -1)
    s.ev(ug.EV_KEY, BTN_TOUCH, 0); s.syn()

res = [scenario("cancelacion real (-1 todos)", cancel_real),
       scenario("cancelacion sin -1 (BTN 0)", lambda s: s.cancel_ghost()),
       scenario("cancelacion parcial", cancel_partial)]
print("OK" if all(res) else "ATASCO detectado"); sys.exit(0 if all(res) else 1)
