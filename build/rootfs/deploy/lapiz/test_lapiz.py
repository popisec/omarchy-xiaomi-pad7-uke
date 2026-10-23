#!/usr/bin/env python3
"""Pruebas offline de thp_pen.py y lapiz_ble.py (python3 -I -m unittest test_lapiz -v). Sin tablet."""
import bisect, gzip, os, re, statistics, struct, unittest

import lapiz_ble as B
import thp_pen as P

HERE = os.path.dirname(os.path.abspath(__file__))
CAP4 = os.path.join(HERE, "..", "..", "..", "android", "lapiz-20261019", "cap4")

# Handshake REAL capturado en Android (btsnoop 19-oct 11:22; handle 0x36), MAC del host de Android 02:00:5e:00:00:17, hora 0x6ad5e16f, hall 0
ANDROID = ["5200", "0000", "0100", "0200", "0300", "0400",
           "301e3c3824a2e5370300a01e3e171a041a0300000d680000052800000d68f401", "310800039b6fef432800", "3203002800", "0400",
           "301e3c3824a2e5370301a01e3e171a041a0100000d680000052800000d68f401", "310801039b6fef432800", "3203012800",
           "33046ad5e16f", "510100"]
# Handshake enviado desde Linux (btsnoop 19-oct 10:28), MAC 02:00:5e:00:00:08, hora 0x6ad5d4a6 (secs), hall 0
LINUX_FIRST = "301e52c60408be120300a01e3e171a041a0300000d680000052800000d68f401"


class BleTests(unittest.TestCase):
    def test_handshake_matches_android(self):
        seq = B.handshake(bytes.fromhex("3c3824a2e537"), 0, now=int.from_bytes(bytes.fromhex("6ad5e16f"), "big"))
        self.assertEqual([c.hex() for c in seq], ANDROID)

    def test_handshake_linux_mac(self):
        seq = B.handshake(bytes.fromhex("52c60408be12"), 0, now=0)
        self.assertEqual(seq[6].hex(), LINUX_FIRST)
        self.assertEqual(len(seq), 15)

    def test_hall_byte(self):
        self.assertEqual(B.handshake(bytes(6), 1, now=0)[-1].hex(), "510101")

    def test_pressure_report(self):
        r = B.parse_pressure_report(bytes.fromhex("5c1b0000" "9b6fef43" "cb2d" "ff5454" "a1"))
        self.assertEqual(r["pressure"], 0x1b5c)
        self.assertEqual(r["freq"], "9b6fef43")
        self.assertIsNone(B.parse_pressure_report(b"\0" * 13))

    def test_keyboard(self):
        self.assertEqual(B.parse_keyboard_report(b"\x6e"), ("down", "small"))
        self.assertEqual(B.parse_keyboard_report(b"\x4b"), ("down", "big_up"))
        self.assertEqual(B.parse_keyboard_report(b"\x4e"), ("down", "big_down"))
        self.assertEqual(B.parse_keyboard_report(b"\x00"), ("up", None))


def synth(peak_row=18, peak_col=5, plane_pos=30, contact=16, amp=900, magic=P.MAGIC_PEN):
    F = bytearray(P.NEED + 64)
    struct.pack_into("<H2xH2xH2xH", F, 4, 7, magic, ~7 & 0xFFFF, ~magic & 0xFFFF)
    struct.pack_into("<H", F, P.CONTACT_OFF, contact)
    struct.pack_into("<h", F, P.GRID_OFF + 2 * (peak_row * P.GRID_COLS + peak_col), amp)
    for i in range(P.PLANES):
        struct.pack_into("<h", F, P.PLANE_OFF0 + i * P.PLANE_STEP + 2 * plane_pos, amp)
    return bytes(F)


class ParseTests(unittest.TestCase):
    def test_not_pen(self):
        self.assertIsNone(P.parse(synth(magic=P.MAGIC_TOUCH)))
        self.assertIsNone(P.parse(b"\0" * 100))

    def test_bad_complements(self):
        F = bytearray(synth())
        struct.pack_into("<H", F, 0xC, 0x1234)      # ~id incorrecto: frame leido a medias
        self.assertIsNone(P.parse(bytes(F)))

    def test_position(self):
        r = P.parse(synth(peak_row=18, plane_pos=30))
        self.assertTrue(r["present"] and r["contact"])
        self.assertAlmostEqual(r["x"], P.X_A * 18 + P.X_B, delta=1)
        self.assertAlmostEqual(r["y"], P.y_from_pos(30.0), delta=1)

    def test_hover_and_absent(self):
        self.assertFalse(P.parse(synth(contact=0))["contact"])
        r = P.parse(synth(amp=20))
        self.assertFalse(r["present"])
        self.assertIsNone(r["x"])

    def test_clamp(self):
        r = P.parse(synth(peak_row=39, plane_pos=59))
        self.assertLessEqual(r["x"], P.X_MAX)
        self.assertLessEqual(r["y"], P.Y_MAX)
        self.assertGreaterEqual(P.parse(synth(peak_row=0, plane_pos=0))["y"], 0)


@unittest.skipUnless(os.path.exists(os.path.join(CAP4, "thp.gz")) and os.path.exists(os.path.join(CAP4, "getevent-event12.txt")), "sin cap4")
class ReplayTests(unittest.TestCase):
    """Reproduce la captura de Android. Las 8 sondas de un frame se disparan en orden 7..0 (mismo instante): el frame abre en
    uke_thp7 y cierra en uke_thp0. Emparejado con event12 a +8 ms, ventana +-3 ms (frames cada ~4,2 ms)."""

    @classmethod
    def setUpClass(cls):
        rx = re.compile(r"\]\s+[d.]+\s+([\d.]+): uke_thp(\d): \(.*?\) a=\{(.*?)\} b=\{(.*?)\}")
        arr = lambda s: b"".join(struct.pack("<Q", int(x, 16)) for x in s.split(","))  # noqa: E731
        cls.frames, cur = [], None
        with gzip.open(os.path.join(CAP4, "thp.gz"), "rt", errors="replace") as f:
            for l in f:
                m = rx.search(l)
                if not m:
                    continue
                t, k = float(m.group(1)), int(m.group(2))
                if k == 7:
                    cur = [t, {}]
                if cur is None or abs(t - cur[0]) > 0.005:
                    cur = None
                    continue
                cur[1][k] = arr(m.group(3)) + arr(m.group(4))
                if k == 0:
                    if len(cur[1]) == 8:
                        cls.frames.append((cur[0], b"".join(cur[1][i] for i in range(8))))
                    cur = None
        cls.ev, st = [], {}
        with open(os.path.join(CAP4, "getevent-event12.txt")) as g:
            for l in g:
                m = re.match(r"\[\s*([\d.]+)\]\s+(\w+)\s+(\w+)\s+(\w+)", l)
                if not m:
                    continue
                typ, code, val = m.group(2), m.group(3), m.group(4)
                if typ == "EV_SYN":
                    if st.get("ABS_X", 0) > 0 and st.get("ABS_Y", 0) > 0 and st.get("ABS_PRESSURE", 0) > 0:
                        d = dict(st); d["t"] = float(m.group(1)); cls.ev.append(d)
                elif typ == "EV_ABS":
                    v = int(val, 16); st[code] = v - (1 << 32) if v >= 1 << 31 else v

    def _errors(self, events):
        ts = [t for t, _ in self.frames]
        ex, ey = [], []
        for e in events:
            i = bisect.bisect_left(ts, e["t"] + 0.008 - 0.003)
            if i >= len(ts) or abs(ts[i] - (e["t"] + 0.008)) > 0.003:
                continue
            r = P.parse(self.frames[i][1])
            if r and r["present"]:
                ex.append(abs(r["x"] - e["ABS_X"])); ey.append(abs(r["y"] - e["ABS_Y"]))
        return ex, ey

    def test_frame_assembly(self):
        self.assertGreater(len(self.frames), 4000)
        ts = [t for t, _ in self.frames]
        self.assertEqual(ts, sorted(ts))

    def test_error_bounds_by_halves(self):
        # la calibracion de thp_pen.py se ajusto con TODA la captura; ambas mitades deben quedar por debajo de las cotas
        h = len(self.ev) // 2
        for part in (self.ev[:h], self.ev[h:]):
            ex, ey = self._errors(part)
            self.assertGreater(len(ex), 500)
            self.assertLess(statistics.median(ex), 60)     # medido ~30
            self.assertLess(statistics.median(ey), 45)     # medido ~26 con la correccion armonica (antes ~60)


if __name__ == "__main__":
    unittest.main(verbosity=2)
