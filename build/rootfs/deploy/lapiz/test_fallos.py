#!/usr/bin/env python3
"""Pruebas de REVISION-FALLOS.md (21-oct-2026). Fallan contra uke_pen.py / uke_lapiz_ble.py originales y pasan con fallos-lapiz.patch +
fallos-cliente.patch. Uso, con los parches ya aplicados en una copia:  cd <copia de deploy/lapiz> && cp analisis-fallos/test_fallos.py . &&
PYTHONPATH=. python3 -W error -m unittest test_fallos"""
import json, os, signal, socket, subprocess, sys, tempfile, textwrap, time, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
for d in (HERE, os.path.dirname(HERE)):
    if d not in sys.path:
        sys.path.insert(0, d)

import test_uke_pen as TP          # noqa: E402  (reutiliza FakeSpi, FakeKeys y RuntimeTests.make/send)
import uke_lapiz_ble as L          # noqa: E402
import uke_pen as U                # noqa: E402


def _base():
    class Base(TP.RuntimeTests):            # dentro de una funcion: no se descubre (heredaria todas las pruebas de RuntimeTests)
        def runTest(self):
            pass
    return Base()


class PenFailures(unittest.TestCase):
    def setUp(self):
        self.b = _base()
        self.b.setUp() if hasattr(self.b, "setUp") else None
        self.b.addCleanup = self.addCleanup
        self.rt, self.spi, self.ui = self.b.make()
        self.keys = self.b.keys
        self.send = lambda m: self.b.send(self.rt, m)

    def test_F1_key_released_when_ble_drops_while_pressed(self):
        self.send({"connected": True, "attached": False}); self.rt.on_socket(1.0)
        self.send({"btn": "big_down", "down": True}); self.rt.on_socket(1.1)
        self.send({"connected": False}); self.rt.on_socket(2.0)
        self.assertEqual(self.keys.log, [("big_down", True), ("big_down", False)])

    def test_F2_key_without_release_times_out(self):
        self.send({"connected": True, "attached": False}); self.rt.on_socket(1.0)
        self.send({"btn": "big_up", "down": True}); self.rt.on_socket(1.1)
        self.rt.tick(10.0); self.assertEqual(self.keys.log, [("big_up", True)])          # una pulsacion larga normal no se toca
        for t in range(11, 20):
            self.send({"connected": True}); self.rt.on_socket(float(t)); self.rt.tick(float(t))
        self.assertEqual(self.keys.log, [("big_up", True), ("big_up", False)])           # ya pasaron BTN_MAX_HOLD_S
        self.send({"btn": "big_up", "down": False}); self.rt.on_socket(20.0)             # el «soltar» tardio no rompe nada
        self.assertFalse(self.rt.dead)

    def test_F3_dead_ble_client_is_treated_as_disconnected(self):
        self.send({"connected": True, "attached": False}); self.rt.on_socket(1.0)
        self.send({"btn": "big_down", "down": True}); self.rt.on_socket(1.1)
        self.assertTrue(self.rt.chip.enabled)
        t = 1.1
        while t < 30:
            t += 0.1; self.rt.tick(t)
        self.assertFalse(self.rt.sess.connected)
        self.assertFalse(self.rt.chip.enabled)                                           # BF 04 00 00 00 enviado
        self.assertEqual(self.keys.log[-1], ("big_down", False))

    def test_F3b_live_client_keeps_pen_mode(self):
        self.send({"connected": True, "attached": False}); self.rt.on_socket(1.0)
        t = 1.0
        while t < 60:
            t += 0.5; self.rt.tick(t)
            if int(t * 2) % 4 == 0:                                                      # el cliente reenvia cada 2 s
                self.send({"connected": True}); self.rt.on_socket(t)
        self.assertTrue(self.rt.sess.connected and self.rt.chip.enabled)

    def test_F4_non_finite_pressure_does_not_kill_pen_mode(self):
        for raw in (b'{"pressure": NaN}', b'{"pressure": Infinity}', b'{"pressure": -Infinity}', b'{"pressure": 1e999}'):
            self.send(raw); self.rt.on_socket(1.0)
            self.assertFalse(self.rt.dead, raw)

    def test_F4b_lost_pressure_zero_does_not_cause_200_rearms(self):
        self.send({"connected": True, "attached": False}); self.rt.on_socket(1.0)
        self.send({"pressure": 500}); self.rt.on_socket(2.0)
        t = 2.0
        while t < 400:
            t += 0.05; self.rt.tick(t)
            if int(t * 20) % 40 == 0:
                self.send({"connected": True}); self.rt.on_socket(t)
        self.assertLessEqual(self.rt.rearms, 6)

    def test_F4c_real_sustained_press_still_rearms(self):
        self.send({"connected": True, "attached": False}); self.rt.on_socket(1.0)
        t = 1.0
        for i in range(30):                                                              # presion que va cambiando (informes nuevos) sin frames
            t += 0.2; self.send({"pressure": 500 + i}); self.rt.on_socket(t); self.rt.tick(t)
        self.assertGreaterEqual(self.rt.rearms, 3)


class ClientFailures(unittest.TestCase):
    def test_F5_second_button_down_closes_first(self):
        st = {}
        A, B = bytes([0x4B]), bytes([0x4E])
        self.assertEqual(L.to_messages("service001c/char0029", A, st), [{"btn": "big_up", "down": True}])
        out = L.to_messages("service001c/char0029", B, st)
        self.assertEqual(out, [{"btn": "big_up", "down": False}, {"btn": "big_down", "down": True}])
        self.assertEqual(L.to_messages("service001c/char0029", bytes([0]), st), [{"btn": "big_down", "down": False}])
        self.assertEqual(L.release_held(st), [])

    def test_F5b_release_held(self):
        st = {}
        L.to_messages("service001c/char0029", bytes([0x6E]), st)
        self.assertEqual(L.release_held(st), [{"btn": "small", "down": False}])
        self.assertEqual(L.release_held(st), [])

    def test_F6_hostile_nested_json_does_not_raise(self):
        n = 100000
        a = b'{"path":"dev_70_61_EE_XX_XX_XX/service","member":"PropertiesChanged","Value":' + b"[" * n + b"]" * n + b"}"
        b = b'{"path":"dev_70_61_EE_XX_XX_XX","member":"PropertiesChanged","Connected":' + b"[" * n + b"]" * n + b"}"
        self.assertIsNone(L.parse_busctl_bytes(a))
        self.assertIsNone(L.parse_busctl_connected(b))

    def test_F6b_handle_line_swallows_any_exception(self):
        class Pub:
            def send(self, m):
                raise RuntimeError("boom")
        s = L.Session.__new__(L.Session)
        s.pub, s.state, s.connected = Pub(), {}, type("C", (), {"set": lambda *a: None, "v": True})()
        ln = (b'{"type":"signal","path":"/org/bluez/hci0/dev_70_61_EE_XX_XX_XX/service001c/char002d","member":"PropertiesChanged",'
              b'"payload":{"type":"sa{sv}as","data":["x",{"Value":{"type":"ay","data":[1,2,0,0,0,0,0,0,0,0,0,0,0,0]}},[]]}}')
        s.handle_line(ln, 0.0)                                                          # no lanza

    def test_F1b_sigterm_sends_button_up_and_disconnected(self):
        d = tempfile.mkdtemp()

        def script(n, body):
            p = os.path.join(d, n)
            with open(p, "w") as f:
                f.write("#!/bin/sh\n" + textwrap.dedent(body))
            os.chmod(p, 0o755)
            return p
        bt = script("bt.sh", """
            case "$1" in
              info) echo 'Connected: yes'; echo 'ServicesResolved: yes';;
              show) echo 'Controller AA:BB:CC:DD:EE:FF (public)';;
              *) exec cat >/dev/null;;
            esac
            """)
        line = ('{"type":"signal","path":"/org/bluez/hci0/dev_70_61_EE_XX_XX_XX/service001c/char0029","member":"PropertiesChanged",'
                '"payload":{"type":"sa{sv}as","data":["org.bluez.GattCharacteristic1",{"Value":{"type":"ay","data":[78]}},[]]}}')
        bus = script("bus.sh", "echo '%s'\nexec sleep 60\n" % line)
        sp = os.path.join(d, "s.sock")
        s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        s.bind(sp)
        s.settimeout(0.2)
        self.addCleanup(s.close)
        env = dict(os.environ, LAPIZ_BTCTL=bt, LAPIZ_BUSCTL=bus, PYTHONPATH=os.getcwd() + os.pathsep + HERE + os.pathsep + os.path.dirname(HERE),
                   LAPIZ_ASSUME_DETACHED="1")
        code = "import sys, uke_lapiz_ble as L; L.Publisher.__init__.__defaults__=(%r,); sys.exit(L.run())" % sp
        p = subprocess.Popen([sys.executable, "-c", code], env=env)
        self.addCleanup(lambda: p.poll() is None and p.kill())
        msgs, t0, termed = [], time.time(), None
        while time.time() - t0 < 25:
            try:
                msgs.append(json.loads(s.recv(1024)))
            except socket.timeout:
                pass
            if termed is None and any(m.get("attached") is False for m in msgs):      # handshake completo (~7 s)
                p.send_signal(signal.SIGTERM)
                termed = time.time()
            if termed and time.time() - termed > 1.5:
                break
        p.wait(5)
        self.assertIsNotNone(termed, msgs)
        tail = [m for m in msgs if "btn" in m or m.get("connected") is False]
        self.assertEqual(tail[-2:], [{"btn": "big_down", "down": False}, {"connected": False}], msgs)


if __name__ == "__main__":
    unittest.main()
