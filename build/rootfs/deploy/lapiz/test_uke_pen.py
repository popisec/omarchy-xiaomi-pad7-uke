#!/usr/bin/env python3
"""Pruebas offline de uke_pen.py (cd build/rootfs/deploy/lapiz && PYTHONPATH=. python3 -m unittest test_uke_pen -v)."""
import json, os, socket, tempfile, unittest

import test_lapiz as TL
import thp_pen as P
import uke_pen as U


class FakeSpi:
    """Registro de comando host simulado: reposo (0) hasta la 1.a escritura; despues devuelve `busy_reads` lecturas ocupadas por
    comando (el chip tarda esas lecturas en poner a 0 el registro, p. ej. pen_switch hizo ACK al 2.o intento en run 1)."""

    def __init__(self, busy_reads=0, always_busy=False):
        self.writes, self.busy_reads, self.always_busy, self._left, self._written = [], busy_reads, always_busy, 0, False

    def write_regs(self, addr, payload):
        self.writes.append((addr, bytes(payload)))
        if not self._written:            # primer intento de un comando: el chip tarda busy_reads lecturas
            self._left = self.busy_reads
        self._written = True

    def read(self, addr, n):
        if self.always_busy:
            return bytes([1, 0])[:n]
        if self._written and self._left > 0:
            self._left -= 1
            return bytes([1, 0])[:n]
        self._written = False
        return bytes([0, 0])[:n]


class ChipTests(unittest.TestCase):
    def test_enable_sequence(self):
        spi = FakeSpi(busy_reads=1)
        c = U.PenChip(spi, 0x11c400, sleep=lambda s: None)
        self.assertTrue(c.enable())
        self.assertGreaterEqual(len(spi.writes), 3)        # reintentos hasta el ACK
        cmds = [w[1] for w in spi.writes]
        self.assertEqual(cmds[0], bytes([0xBF, 0x04, 0x00, 0x01, 0x00]))
        self.assertIn(bytes([0x7B, 0x01]), cmds)
        self.assertTrue(all(w[0] == 0x11c450 for w in spi.writes))
        self.assertNotIn(bytes([0x7C]), cmds)          # Android no manda 7C
        self.assertFalse(any(w == bytes([0x7B, 0x00]) for w in cmds))

    def test_busy_chip_aborts(self):
        spi = FakeSpi(always_busy=True)
        c = U.PenChip(spi, 0x11c400, sleep=lambda s: None)
        self.assertFalse(c.enable())
        self.assertEqual(spi.writes, [])               # no se escribe si el chip esta ocupado

    def test_disable_only_stylus_enable(self):
        spi = FakeSpi()
        c = U.PenChip(spi, 0x11c400, sleep=lambda s: None)
        c.enabled = True
        self.assertTrue(c.disable())
        self.assertEqual([w[1] for w in spi.writes], [bytes([0xBF, 0x04, 0x00, 0x00, 0x00])])


class SessionTests(unittest.TestCase):
    def test_enable_follows_ble_and_hall(self):
        s = U.PenSession()
        self.assertEqual(s.feed_ble({"connected": True}, 0), [])       # pegado por defecto
        self.assertEqual(s.feed_ble({"attached": False}, 1), [("enable", True)])
        self.assertEqual(s.feed_ble({"attached": True}, 2), [("enable", False)])
        self.assertEqual(s.feed_ble({"attached": False}, 3), [("enable", True)])
        self.assertEqual(s.feed_ble({"connected": False}, 4), [("enable", False)])

    def _enter(self, s, t=0.0, contact=16):
        s.feed_frame(TL.synth(contact=contact), t)
        return s.feed_frame(TL.synth(contact=contact), t + 0.004)

    def test_pen_lifecycle_needs_two_frames(self):
        s = U.PenSession()
        self.assertEqual(s.feed_frame(TL.synth(contact=16), 0.0), [])        # 1.er frame presente: aun no
        ev = s.feed_frame(TL.synth(contact=16), 0.004)
        self.assertEqual(ev[0], ("tool", True))
        self.assertEqual(ev[1][0], "pos")
        self.assertIn(("touch", True), ev)
        ev = s.feed_frame(TL.synth(contact=0), 0.01)
        self.assertIn(("touch", False), ev)
        self.assertEqual(s.tick(0.2), [])                 # dentro del hold
        self.assertEqual(s.tick(0.5), [("tool", False)])  # fuera de rango tras HOLD_S
        self.assertEqual(s.tick(0.9), [])

    def test_single_noise_frame_ignored(self):
        s = U.PenSession()
        s.feed_frame(TL.synth(), 0.0)
        s.feed_frame(TL.synth(amp=20), 0.004)             # ruido rompe la racha
        self.assertEqual(s.feed_frame(TL.synth(), 0.008), [])
        self.assertFalse(s.in_range)

    def test_release_while_touching_resets_pressure(self):
        s = U.PenSession()
        s.feed_ble({"pressure": 500}, 0)
        self._enter(s)
        self.assertEqual(s.out_pressure, 500)
        self.assertEqual(s.tick(1.0), [("pressure", 0), ("touch", False), ("tool", False)])     # presion a 0 ANTES de soltar la punta

    def test_noise_ignored(self):
        s = U.PenSession()
        self.assertEqual(s.feed_frame(TL.synth(amp=20), 0.0), [])
        self.assertEqual(s.feed_frame(TL.synth(magic=P.MAGIC_TOUCH), 0.0), [])
        self.assertFalse(s.in_range)
        self.assertEqual(s.stats["bad"], 1)

    def test_tip_decided_by_chip_contact_pressure_follows(self):
        s = U.PenSession()
        self.assertEqual(s.feed_ble({"pressure": 9999}, 0), [])                  # sin contacto: se guarda, no se emite
        self.assertEqual(s.pressure, 8191)
        ev = self._enter(s, contact=0)                                           # en rango SIN contacto: sin presion
        self.assertNotIn("pressure", [e[0] for e in ev])
        ev = s.feed_frame(TL.synth(contact=16), 0.01)                            # contacto del chip: presion ANTES de la punta
        kinds = [e[0] for e in ev]
        self.assertLess(kinds.index("pressure"), kinds.index("touch"))
        self.assertIn(("pressure", 8191), ev)
        self.assertEqual(s.feed_ble({"pressure": -5}, 0), [("pressure", U.PRESSURE_FLOOR)])   # con contacto nunca baja del suelo
        ev = s.feed_frame(TL.synth(contact=0), 0.02)                             # al levantar: presion 0 y luego punta fuera
        self.assertEqual([e for e in ev if e[0] in ("pressure", "touch")], [("pressure", 0), ("touch", False)])

    def test_pressure_floor_when_ble_late(self):
        s = U.PenSession()
        self._enter(s, contact=0)
        ev = s.feed_frame(TL.synth(contact=16), 0.01)
        self.assertIn(("pressure", U.PRESSURE_FLOOR), ev)                        # el BLE aun no ha llegado: la punta ya cuenta

    def test_position_jump_filtered_until_confirmed(self):
        s = U.PenSession()
        self._enter(s, contact=0)
        x0 = [e for e in s.feed_frame(TL.synth(peak_row=18, plane_pos=30), 0.01) if e[0] == "pos"][0]
        far = [e for e in s.feed_frame(TL.synth(peak_row=2, plane_pos=5), 0.014) if e[0] == "pos"][0]
        self.assertEqual(far[1:], x0[1:])                                        # salto sospechoso: se retiene
        far2 = [e for e in s.feed_frame(TL.synth(peak_row=2, plane_pos=5), 0.018) if e[0] == "pos"][0]
        self.assertNotEqual(far2[1:], x0[1:])                                    # un 2.o frame lo confirma
        self.assertEqual(s.stats["jumps"], 1)

    def test_ble_drop_releases(self):
        s = U.PenSession()
        s.feed_ble({"connected": True, "attached": False}, 0)
        s.feed_ble({"pressure": 700}, 0)
        self._enter(s)
        ev = s.feed_ble({"connected": False}, 1)
        self.assertIn(("tool", False), ev)
        self.assertIn(("pressure", 0), ev)
        self.assertIn(("enable", False), ev)
        self.assertEqual(s.pressure, 0)

    def test_spurious_attached_ignored_while_pen_in_use(self):
        s = U.PenSession()
        s.feed_ble({"connected": True, "attached": False}, 0)
        s.feed_ble({"pressure": 600}, 1.0)                                       # el lapiz presiona: en uso
        self.assertEqual(s.feed_ble({"attached": True}, 1.3), [])                # aviso «pegado» espurio (boton pequeño): se ignora
        self.assertFalse(s.attached)
        self.assertEqual(s.stats["hall_ignored"], 1)
        self.assertTrue(s.want_enable)

    def test_attached_accepted_when_idle_and_healed_by_activity(self):
        s = U.PenSession()
        s.feed_ble({"connected": True, "attached": False}, 0)
        self.assertEqual(s.feed_ble({"attached": True}, 10.0), [("enable", False)])   # sin actividad: lapiz de verdad pegado
        self.assertTrue(s.attached)
        ev = s.feed_ble({"pressure": 300}, 20.0)                                 # aparece presion: no estaba pegado
        self.assertIn(("enable", True), ev)
        self.assertFalse(s.attached)
        self.assertEqual(s.stats["hall_healed"], 1)

    def test_attached_healed_by_pen_frames(self):
        s = U.PenSession()
        s.feed_ble({"connected": True, "attached": True}, 0)
        self.assertFalse(s.want_enable)
        ev = s.feed_frame(TL.synth(contact=0), 5.0)
        self.assertIn(("enable", True), ev)                                      # frames de lapiz con «pegado»: se corrige
        self.assertFalse(s.attached)

    def test_buttons(self):
        s = U.PenSession()
        self.assertEqual(s.feed_ble({"btn": "small", "down": True}, 0), [("btn", "small", True)])
        self.assertEqual(s.feed_ble({"btn": "bogus"}, 0), [])

    def test_malformed_messages_do_not_raise(self):
        s = U.PenSession()
        for m in ({"pressure": None}, {"pressure": "x"}, {"btn": ["a"]}, {"connected": "yes"}, {"attached": 1}, [1], "x", None, {"pressure": True}):
            self.assertIsInstance(s.feed_ble(m, 0), list)
        self.assertFalse(s.connected)


class FakeKeys:
    def __init__(self):
        self.log, self.closed = [], False

    def key(self, name, down):
        self.log.append((name, down))

    def close(self):
        self.closed = True


class RuntimeTests(unittest.TestCase):
    class FakeUI:
        def __init__(self):
            self.events, self.closed = [], False

        def apply(self, evs, to_screen):
            self.events += list(evs)

        def close(self):
            self.closed = True

    def make(self, spi=None, ui=None, sock_ok=True, log=None):
        spi = spi or FakeSpi()
        ui = ui or self.FakeUI()
        d = tempfile.mkdtemp()
        path = os.path.join(d, "s.sock")
        self.keys = FakeKeys()
        rt = U.PenRuntime(spi, 0x11c400, 3200, 2136, None, lambda x, y: (x // 10, y // 15), log=log or (lambda *a: None),
                          ui_factory=lambda: ui, sock_factory=(lambda: U.open_ble_socket(path)) if sock_ok else (lambda: 1 / 0),
                          sleep=lambda s: None, keys_factory=lambda: self.keys)
        rt._path = path
        self.addCleanup(lambda: rt.sock is not None and not isinstance(rt.sock, int) and rt.sock.close())
        return rt, spi, ui

    def send(self, rt, msg):
        c = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        c.sendto(json.dumps(msg).encode() if not isinstance(msg, bytes) else msg, rt._path)
        c.close()

    def test_init_failure_disables_not_raises(self):
        rt, _, _ = self.make(sock_ok=False)
        self.assertTrue(rt.dead)
        self.assertEqual(rt.fileno(), -1)
        self.assertFalse(rt.handles(TL.synth()))
        rt.on_socket(0); rt.tick(0); rt.shutdown(); rt.set_ready(False); rt.resync()      # no lanzan

    def test_opmode_commands_after_enable(self):
        rt, spi, ui = self.make()
        rt.OPMODE = True
        self.send(rt, {"connected": True}); self.send(rt, {"attached": False})
        rt.on_socket(1.0)
        cmds = [w[1] for w in spi.writes]
        self.assertEqual(cmds[0], bytes([0xBF, 0x04, 0x00, 0x01, 0x00]))
        self.assertIn(bytes([0x7B, 0x01]), cmds)
        self.assertEqual(cmds[-2:], [bytes([0xBF, 0x01, 0x00, 0x02, 0x00]), bytes([0xBF, 0x19, 0x00, 0x01, 0x00])])

    def test_opmode_can_be_disabled(self):
        rt, spi, ui = self.make()
        rt.OPMODE = False
        self.send(rt, {"connected": True}); self.send(rt, {"attached": False})
        rt.on_socket(1.0)
        self.assertNotIn(bytes([0xBF, 0x01, 0x00, 0x02, 0x00]), [w[1] for w in spi.writes])

    def test_enable_after_ble_messages(self):
        rt, spi, ui = self.make()
        self.send(rt, {"connected": True}); self.send(rt, {"attached": False})
        rt.on_socket(1.0)
        self.assertTrue(rt.chip.enabled)
        self.assertEqual(spi.writes[0][1], bytes([0xBF, 0x04, 0x00, 0x01, 0x00]))

    def test_pen_frames_to_uinput(self):
        rt, spi, ui = self.make()
        F = TL.synth(contact=16)
        self.assertTrue(rt.handles(F))
        rt.on_frame(F, 0.0); rt.on_frame(F, 0.004)
        kinds = [e[0] for e in ui.events]
        self.assertIn("tool", kinds); self.assertIn("pos", kinds); self.assertIn("touch", kinds)

    def test_exception_in_ui_kills_pen_but_not_caller(self):
        ui = self.FakeUI()
        ui.apply = lambda evs, ts: (_ for _ in ()).throw(OSError("uinput"))
        logs = []
        rt, spi, _ = self.make(ui=ui, log=lambda *a: logs.append(a))
        F = TL.synth(contact=16)
        rt.on_frame(F, 0.0); rt.on_frame(F, 0.004)          # no lanza
        self.assertTrue(rt.dead)
        self.assertTrue(any("DESACTIVADO" in str(a) for a in logs))
        self.assertTrue(all(str(a[0]).startswith("[") for a in logs))               # cada linea lleva marca monotonica
        self.assertTrue(ui.closed)

    def test_buttons_out_of_range_go_to_keyboard(self):
        rt, spi, ui = self.make()
        self.send(rt, {"btn": "big_up", "down": True}); self.send(rt, {"btn": "big_up", "down": False})
        self.send(rt, {"btn": "small", "down": True}); self.send(rt, {"btn": "small", "down": False})
        rt.on_socket(1.0)
        self.assertEqual(self.keys.log, [("big_up", True), ("big_up", False), ("small", True), ("small", False)])
        self.assertFalse([e for e in ui.events if e[0] == "btn"])

    def test_small_button_in_range_goes_to_stylus_and_release_precedes_tool_out(self):
        rt, spi, ui = self.make()
        F = TL.synth(contact=0)
        rt.on_frame(F, 0.0); rt.on_frame(F, 0.004)                 # lapiz en rango
        self.send(rt, {"btn": "small", "down": True})
        rt.on_socket(0.01)
        rt.tick(1.0)                                               # el lapiz sale de rango con el boton aun pulsado
        kinds = [(e[0], e[-1]) for e in ui.events if e[0] in ("btn", "tool")]
        self.assertIn(("btn", False), kinds)
        self.assertLess(kinds.index(("btn", False)), kinds.index(("tool", False)))     # el soltar sale ANTES de la salida de rango
        self.send(rt, {"btn": "small", "down": False})
        rt.on_socket(1.01)
        self.assertEqual([e for e in ui.events if e[0] == "btn" and e[2] is False].__len__(), 1)   # y no se duplica
        self.assertEqual(self.keys.log, [])

    def test_big_buttons_never_reach_the_tablet_node(self):
        rt, spi, ui = self.make()
        F = TL.synth(contact=16)
        rt.on_frame(F, 0.0); rt.on_frame(F, 0.004)                 # lapiz en rango y tocando
        for b in ("big_up", "big_down"):
            self.send(rt, {"btn": b, "down": True}); self.send(rt, {"btn": b, "down": False})
        rt.on_socket(0.01)
        self.assertFalse([e for e in ui.events if e[0] == "btn"])   # nunca BTN_STYLUS2/3 en la tableta (bug de Qt/quickshell)
        self.assertEqual(self.keys.log, [("big_up", True), ("big_up", False), ("big_down", True), ("big_down", False)])

    def test_keys_failure_kills_pen_not_caller(self):
        rt, spi, ui = self.make()
        self.keys.key = lambda n, d: (_ for _ in ()).throw(OSError("uinput"))
        self.send(rt, {"btn": "small", "down": True})
        rt.on_socket(1.0)
        self.assertTrue(rt.dead)

    def test_rearm_when_pressure_without_frames(self):
        rt, spi, ui = self.make()
        self.send(rt, {"connected": True, "attached": False}); rt.on_socket(1.0)        # chip activado
        self.send(rt, {"pressure": 700}); rt.on_socket(1.1)                              # la punta presiona (BLE) pero no hay frames
        spi.writes.clear()
        rt.tick(3.0)
        self.assertEqual(spi.writes[0][1], bytes([0xBF, 0x04, 0x00, 0x01, 0x00]))        # re-arme
        n = len(spi.writes)
        rt.tick(3.4)
        self.assertEqual(len(spi.writes), n)                                             # limitado a 1 por segundo
        rt.tick(4.5)
        self.assertGreater(len(spi.writes), n)
        self.assertEqual(rt.rearms, 2)

    def test_no_rearm_when_frames_flow_or_no_pressure(self):
        rt, spi, ui = self.make()
        self.send(rt, {"connected": True, "attached": False}); rt.on_socket(1.0)
        spi.writes.clear()
        rt.tick(3.0)                                                                     # sin presion BLE: no se re-arma
        self.assertEqual(spi.writes, [])
        self.send(rt, {"pressure": 700}); rt.on_socket(3.1)
        F = TL.synth(contact=16)
        rt.on_frame(F, 3.2); rt.on_frame(F, 3.204)                                       # hay frames de lapiz
        spi.writes.clear()
        rt.tick(3.3)
        self.assertEqual(spi.writes, [])

    def test_malformed_socket_message_does_not_kill(self):
        rt, _, _ = self.make()
        self.send(rt, {"pressure": None}); self.send(rt, b"\xff\xfe")
        rt.on_socket(0.0)
        self.assertFalse(rt.dead)

    def test_retry_enable_when_no_ack(self):
        rt, spi, _ = self.make(spi=FakeSpi(always_busy=True))
        self.send(rt, {"connected": True, "attached": False})
        rt.on_socket(1.0)
        self.assertFalse(rt.chip.enabled)                     # chip ocupado: no escribe, sin ACK
        spi.always_busy = False
        rt.tick(1.5)
        self.assertFalse(rt.chip.enabled)                     # aun dentro de RETRY_S
        rt.tick(3.0)
        self.assertTrue(rt.chip.enabled)                      # reintento real

    def test_silent_chip_loses_pen_mode_then_retries(self):
        rt, spi, ui = self.make()
        rt.set_ready(True, 0.0)
        self.send(rt, {"connected": True, "attached": False})
        rt.on_socket(1.0)
        self.assertTrue(rt.chip.enabled)
        rt.silence(2.5, 1.0)                                  # 1.5 s de silencio: aun no
        self.assertTrue(rt.chip.enabled)
        rt.silence(3.5, 1.0)                                  # 2.5 s: se vuelve al modo normal (BF 04 00 00 00)
        self.assertFalse(rt.chip.enabled)
        self.assertEqual(spi.writes[-1][1], bytes([0xBF, 0x04, 0x00, 0x00, 0x00]))
        rt.tick(8.0)
        self.assertFalse(rt.chip.enabled)                     # dentro del hold-off de 10 s
        rt.tick(14.0)
        self.assertTrue(rt.chip.enabled)                      # reintento tras el hold-off
        self.assertFalse(rt.dead)

    def test_not_ready_blocks_enable_and_releases(self):
        rt, spi, ui = self.make()
        F = TL.synth(contact=16)
        rt.on_frame(F, 0.0); rt.on_frame(F, 0.004)
        rt.set_ready(False)
        self.assertIn(("tool", False), ui.events)
        self.send(rt, {"connected": True, "attached": False})
        rt.on_socket(1.0)
        self.assertEqual(spi.writes, [])                      # no se escribe al chip sin firmware
        rt.set_ready(True)
        rt.tick(2.5)
        self.assertTrue(rt.chip.enabled)                      # y se activa al volver

    def test_shutdown_disables_with_bf04_only(self):
        rt, spi, ui = self.make()
        self.send(rt, {"connected": True, "attached": False}); rt.on_socket(1.0)
        spi.writes.clear()
        rt.shutdown()
        cmds = [w[1] for w in spi.writes]
        self.assertEqual(cmds, [bytes([0xBF, 0x04, 0x00, 0x00, 0x00])])

    def test_resync_after_firmware_reload(self):
        rt, spi, ui = self.make()
        self.send(rt, {"connected": True, "attached": False}); rt.on_socket(1.0)
        rt.resync()
        self.assertFalse(rt.chip.enabled)
        rt.tick(5.0)
        self.assertTrue(rt.chip.enabled)


class SocketTests(unittest.TestCase):
    def test_read_ble_ignores_garbage(self):
        d = tempfile.mkdtemp()
        path = os.path.join(d, "s.sock")
        srv = U.open_ble_socket(path)
        cl = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        for m in (b'{"pressure": 10}', b"no es json", b"[1,2]", b'{"btn":"small","down":false}', b"\xff\xfe"):
            cl.sendto(m, path)
        self.assertEqual(U.read_ble(srv), [{"pressure": 10}, {"btn": "small", "down": False}])
        self.assertEqual(U.read_ble(srv), [])
        srv.close(); cl.close()



# ---- equivalencia de la optimizacion de rendimiento (20-oct): copia literal de parse() ANTES de precompilar Structs / inlinar la parabola ----
def _old_i16(F, off, n):
    return U.struct.unpack_from("<%dh" % n, F, off)


def _old_parse(F):
    if len(F) < P.NEED:
        return None
    fid, magic, nid, nmag = U.struct.unpack_from("<H2xH2xH2xH", F, 4)
    if magic != P.MAGIC_PEN or nmag != (~magic & 0xFFFF) or nid != (~fid & 0xFFFF):
        return None
    g = _old_i16(F, P.GRID_OFF, P.GRID_ROWS * P.GRID_COLS)
    peak = max(g)
    present = peak > P.PRESENCE_MIN
    contact = U.struct.unpack_from("<H", F, P.CONTACT_OFF)[0] == 16
    out = {"present": present, "contact": contact and present, "peak": peak, "frame_id": fid, "x": None, "y": None}
    if present:
        pos_g = [x if x > 0 else 0 for x in g]
        rows = [sum(pos_g[r:r + P.GRID_COLS]) for r in range(0, P.GRID_ROWS * P.GRID_COLS, P.GRID_COLS)]
        row = P._centroid(rows)
        planes = _old_i16(F, P.PLANE_OFF0, (P.PLANES - 1) * (P.PLANE_STEP // 2) + P.PLANE_LEN)
        half = P.PLANE_STEP // 2
        pos = sum(P._parabolic(list(planes[i * half:i * half + P.PLANE_LEN])) for i in range(P.PLANES)) / P.PLANES
        out["x"] = int(min(P.X_MAX, max(0, round(P.X_A * row + P.X_B))))
        out["y"] = int(min(P.Y_MAX, max(0, round(P.y_from_pos(pos)))))
    return out


def _random_frames(n, seed=20261020):
    import random
    rnd = random.Random(seed)
    out = []
    for i in range(n):
        F = bytearray(P.NEED + rnd.choice((0, 64)))
        fid = rnd.randrange(65536)
        magic = P.MAGIC_PEN if rnd.random() < 0.9 else P.MAGIC_TOUCH
        U.struct.pack_into("<H2xH2xH2xH", F, 4, fid, magic, ~fid & 0xFFFF if rnd.random() < 0.97 else 0x1234, ~magic & 0xFFFF)
        U.struct.pack_into("<H", F, P.CONTACT_OFF, rnd.choice((0, 16, 16, 3)))
        for k in range(P.GRID_ROWS * P.GRID_COLS):
            U.struct.pack_into("<h", F, P.GRID_OFF + 2 * k, rnd.randint(-40, 60))
        for k in range((P.PLANES - 1) * (P.PLANE_STEP // 2) + P.PLANE_LEN):
            U.struct.pack_into("<h", F, P.PLANE_OFF0 + 2 * k, rnd.randint(-400, 400))
        if rnd.random() < 0.75:                                     # lapiz presente: mancha alrededor de un pico (a veces en el borde o con empates)
            r, c, amp = rnd.randrange(P.GRID_ROWS), rnd.randrange(P.GRID_COLS), rnd.randint(81, 32000)
            for dr in (-1, 0, 1):
                for dc in (-1, 0, 1):
                    if 0 <= r + dr < P.GRID_ROWS and 0 <= c + dc < P.GRID_COLS:
                        U.struct.pack_into("<h", F, P.GRID_OFF + 2 * ((r + dr) * P.GRID_COLS + c + dc), amp if not (dr or dc) else rnd.randint(0, amp))
        if rnd.random() < 0.1:
            for pl in range(P.PLANES):                                # planos planos / con el maximo en los bordes
                U.struct.pack_into("<h", F, P.PLANE_OFF0 + pl * P.PLANE_STEP + 2 * rnd.choice((0, 59, 30)), rnd.choice((0, 500)))
        out.append(bytes(F))
    out += [b"", b"\0" * 100, bytes(P.NEED - 1)]
    return out


class PerfEquivalenceTests(unittest.TestCase):
    def test_parse_identical_to_reference(self):
        frames = _random_frames(2400)
        self.assertGreaterEqual(len(frames), 2000)
        npres = 0
        for F in frames:
            a, b = P.parse(F), _old_parse(F)
            self.assertEqual(a, b)
            npres += bool(a and a["present"])
        self.assertGreater(npres, 1000)

    def test_parse_identical_on_real_capture(self):
        if not os.path.exists(os.path.join(TL.CAP4, "thp.gz")):
            self.skipTest("sin cap4")
        TL.ReplayTests.setUpClass()
        for _, F in TL.ReplayTests.frames:
            self.assertEqual(P.parse(F), _old_parse(F))

    def test_session_events_identical(self):
        from unittest import mock
        frames = _random_frames(2400, seed=7)
        runs = []
        for parse in (P.parse, _old_parse):
            with mock.patch.object(P, "parse", parse):
                s, evs = U.PenSession(), []
                for i, F in enumerate(frames):
                    evs.append(s.feed_frame(F, i * 0.004))
                runs.append((evs, dict(s.stats)))
        self.assertEqual(runs[0], runs[1])


if __name__ == "__main__":
    unittest.main(verbosity=2)
