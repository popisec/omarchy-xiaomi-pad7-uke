#!/usr/bin/env python3
"""Pruebas de thp_tilt.py (cd build/rootfs/deploy/lapiz && PYTHONPATH=. python3 -m unittest test_thp_tilt -v)."""
import json, os, struct, unittest

import thp_tilt as T

HERE = os.path.dirname(os.path.abspath(__file__))
FRAME_BYTES = 0x1440


def blank(contact=16, magic=0x509, fid=7):
    F = bytearray(FRAME_BYTES)
    struct.pack_into("<H2xH2xH2xH", F, 4, fid, magic, ~fid & 0xFFFF, ~magic & 0xFFFF)
    struct.pack_into("<H", F, T.CONTACT_OFF, contact)
    return bytearray(F)


class Tilt(unittest.TestCase):
    def test_rechaza_basura(self):
        self.assertIsNone(T.estimate(b""))
        self.assertIsNone(T.estimate(bytes(100)))
        self.assertIsNone(T.estimate(bytes(blank(magic=0x4BF))))
        F = blank(); F[4] ^= 1
        self.assertIsNone(T.estimate(bytes(F)))        # id sin su complemento: lectura a medias

    def test_hover_none(self):
        self.assertIsNone(T.estimate(bytes(blank(contact=0))))

    def test_frame_sintetico_y_limites(self):
        F = blank()
        struct.pack_into("<h", F, T.GRID1 + (20 * T.COLS + 5) * 2, 300)
        struct.pack_into("<h", F, T.GRID2 + (21 * T.COLS + 5) * 2, 300)
        for i in range(8):
            struct.pack_into("<3h", F, T.PL1 + i * T.PSTEP + 29 * 2, 100, 300, 100)
            struct.pack_into("<3h", F, T.PL2 + i * T.PSTEP + 29 * 2, 100, 5000, 100)
        r1, p1, dr, a2, p2 = T.features(bytes(F))
        self.assertAlmostEqual(r1, 20.0, 3); self.assertAlmostEqual(dr, 1.0, 3)
        self.assertAlmostEqual(p1, 30.0, 3); self.assertAlmostEqual(a2, 5000, 3)
        tx, ty = T.estimate(bytes(F))
        self.assertLessEqual(abs(ty), 60.0)           # recorte a +-60 incluso con amplitud absurda
        self.assertLessEqual(abs(tx), 60.0)
        for i in range(8):
            struct.pack_into("<3h", F, T.PL2 + i * T.PSTEP + 29 * 2, 100, 30000, 100)
        self.assertEqual(T.estimate(bytes(F))[1], 60.0)

    def test_frames_reales(self):
        """4 frames reales de Android (trazos distintos) con la inclinacion de referencia: error < 12 grados y orden TX entre trazos."""
        with open(os.path.join(HERE, "fixtures", "thp-tilt-frames.bin"), "rb") as fh:
            raw = fh.read()
        with open(os.path.join(HERE, "fixtures", "thp-tilt-frames.json")) as fh:
            meta = json.load(fh)
        est = []
        for k, (tx, ty, _, _) in enumerate(meta):
            e = T.estimate(raw[k * FRAME_BYTES:(k + 1) * FRAME_BYTES])
            self.assertIsNotNone(e)
            est.append(e)
            self.assertLess(abs(e[0] - tx), 12); self.assertLess(abs(e[1] - ty), 12)
        # el trazo 3 (tilt_x -11) debe dar menos TX que el trazo 6 (+4)
        self.assertLess(est[0][0], est[2][0])

    def test_frames_cap8_extremos(self):
        """5 frames reales de cap8 (sesion distinta de cap4; inclinaciones hasta +-65, estan en el ajuste: es prueba de regresion, no validacion): error < 18 grados por eje (los extremos se subestiman: aqui TY 60 sale 44)."""
        with open(os.path.join(HERE, "fixtures", "thp-tilt-cap8-frames.bin"), "rb") as fh:
            raw = fh.read()
        with open(os.path.join(HERE, "fixtures", "thp-tilt-cap8-frames.json")) as fh:
            meta = json.load(fh)
        for k, (tx, ty) in enumerate(meta):
            e = T.estimate(raw[k * FRAME_BYTES:(k + 1) * FRAME_BYTES])
            self.assertIsNotNone(e)
            self.assertLess(abs(e[0] - tx), 18); self.assertLess(abs(e[1] - ty), 18)
        self.assertLess(T.estimate(raw[0:FRAME_BYTES])[1], -45)   # TY -65: debe salir claramente negativo
        self.assertGreater(T.estimate(raw[2 * FRAME_BYTES:3 * FRAME_BYTES])[1], 40)


def _real_frames():
    with open(os.path.join(HERE, "fixtures", "thp-tilt-cap8-frames.bin"), "rb") as fh:
        raw = fh.read()
    return [raw[k * FRAME_BYTES:(k + 1) * FRAME_BYTES] for k in range(len(raw) // FRAME_BYTES)]


class TiltV3(unittest.TestCase):
    def test_estimate_conf_coherente(self):
        for F in _real_frames():
            e, c = T.estimate(F), T.estimate_conf(F)
            self.assertEqual(c[:2], e)
            self.assertTrue(0.0 <= c[2] <= 1.0 and 0.0 <= c[3] <= 1.0)
        self.assertIsNone(T.estimate_conf(bytes(blank(contact=0))))
        self.assertIsNone(T.estimate_conf(b""))

    def test_confianza_monotona(self):
        self.assertGreater(T.confidence(0.3, 5.5)[0], 0.95)
        self.assertGreater(T.confidence(0.3, 5.5)[1], 0.95)
        self.assertLess(T.confidence(3.0, 5.5)[0], 0.1)       # |dr| extremo
        self.assertLess(T.confidence(0.3, 7.5)[1], 0.1)       # amplitud extrema
        self.assertGreater(T.confidence(1.0, 5.5)[0], T.confidence(2.0, 5.5)[0])
        self.assertAlmostEqual(T.confidence(-1.0, 5.5)[0], T.confidence(1.0, 5.5)[0])

    def test_filtro_ema(self):
        F = _real_frames()[1]
        e = T.estimate_conf(F)
        flt = T.TiltFilter(alpha=0.5, gap=0.05, min_conf=0.0)
        r = flt.update(0.0, F)
        self.assertEqual(r[:2], e[:2])                          # primer frame: sin suavizar
        flt.v = [e[0] + 10.0, e[1] - 10.0]                      # estado desplazado: el EMA converge hacia la medida
        r = flt.update(0.004, F)
        self.assertAlmostEqual(r[0], e[0] + 5.0, 6); self.assertAlmostEqual(r[1], e[1] - 5.0, 6)
        flt.v = [e[0] + 10.0, e[1] - 10.0]
        r = flt.update(0.5, F)                                   # hueco > gap: reinicia, sin arrastre
        self.assertEqual(r[:2], e[:2])
        self.assertIsNone(flt.update(0.504, bytes(blank(contact=0))))   # hover: None y estado reiniciado
        self.assertIsNone(flt.t)

    def test_filtro_descarta_dudosos(self):
        F = _real_frames()[0]
        flt = T.TiltFilter(alpha=1.0, min_conf=2.0)             # umbral imposible: nada se acepta
        self.assertIsNone(flt.update(0.0, F))

    def test_coste_por_frame(self):
        import time
        F = _real_frames()[0]
        t0 = time.perf_counter()
        for _ in range(300):
            T.estimate_conf(F)
        ms = (time.perf_counter() - t0) / 300 * 1000
        self.assertLess(ms, 0.5)    # medido 0,13 ms en esta maquina (margen 4x)


if __name__ == "__main__":
    unittest.main()
