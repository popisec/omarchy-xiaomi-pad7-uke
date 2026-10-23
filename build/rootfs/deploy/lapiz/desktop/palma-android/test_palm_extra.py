#!/usr/bin/env python3
"""Pruebas extra de la logica pura: mitigaciones (replay de inicio, liberacion de ban M1, tracker_reset, tope de fantasmas), coste por frame,
fuzzing con semilla fija y memoria acotada. cd .../palma-android && python3 -m unittest test_palm_extra -v"""
import gc, os, sys, tracemalloc, unittest
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from palm_android import AndroidPalm, PASS, PEND, BAN
import bench_palm, sim_extra as X

DT = 1 / 226.0


class Clock:
    def __init__(s, t=100.0): s.t = t
    def tick(s, n=1): s.t += n * DT; return s.t


def pen_for(p, c, n):
    for _ in range(n):
        p.pen_frame(c.tick())


class Mitigaciones(unittest.TestCase):
    def test_replay_start_primer_frame_en_la_posicion_de_inicio(self):
        p, c = AndroidPalm(), Clock()
        pen_for(p, c, 5)
        first = None
        for i in range(40):
            p.pen_frame(c.tick())
            o = p.filter([(5, 100 + 20 * i, 500, 9)], c.t, True)
            if o:
                first = (i, o[0]); break
        self.assertIsNotNone(first)
        self.assertEqual(first[1][1:3], (100, 500))                     # donde empezo, no donde esta (bordes de uke-gestures)
        p.pen_frame(c.tick())
        self.assertEqual(p.filter([(5, 100 + 20 * (first[0] + 1), 500, 9)], c.t, True)[0][1], 100 + 20 * (first[0] + 1))   # el siguiente, actual

    def test_replay_start_apagado(self):
        p, c = AndroidPalm(replay_start=False), Clock()
        pen_for(p, c, 5)
        for i in range(40):
            p.pen_frame(c.tick())
            o = p.filter([(5, 100 + 20 * i, 500, 9)], c.t, True)
            if o:
                self.assertEqual(o[0][1], 100 + 20 * i); break
        else:
            self.fail("no paso")

    def _quieto_tras_lapiz(self, p, c, area, hold_frames):
        pen_for(p, c, 30)
        c.tick(ms_to_frames(20))
        outs = []
        for _ in range(hold_frames):
            outs.append(p.filter([(1, 800, 800, area)], c.tick(), False))
        return outs

    def test_ban_sin_release_dura_hasta_levantar(self):
        p, c = AndroidPalm(), Clock()
        outs = self._quieto_tras_lapiz(p, c, 5, 600)
        self.assertTrue(all(o == [] for o in outs))
        self.assertEqual(p.rec[1].state, BAN)

    def test_release_dedo_pequeno_quieto_pasa_tras_release_ms(self):
        p, c = AndroidPalm(release_ms=300), Clock()
        outs = self._quieto_tras_lapiz(p, c, 5, 600)
        first = next(i for i, o in enumerate(outs) if o)
        t_first = (first + 1) * DT
        t_pen_end = ms_to_frames(20) * DT                               # hueco lapiz -> dedo (first cuenta desde el dedo)
        self.assertGreaterEqual(t_first + t_pen_end, 0.300)             # desde el fin del lapiz
        self.assertLessEqual(t_first + t_pen_end, 0.300 + 0.100 + 3 * DT)   # margen 100 ms de inactividad + release
        self.assertEqual(p.stats["released"], 1)
        self.assertEqual(outs[first][0][1:3], (800, 800))

    def test_release_nunca_si_el_contacto_tuvo_area_de_palma(self):
        p, c = AndroidPalm(release_ms=300), Clock()
        pen_for(p, c, 30); c.tick(ms_to_frames(20))
        outs = []
        for i in range(600):
            outs.append(p.filter([(1, 800, 800, 9 if i == 10 else 5)], c.tick(), False))   # un pico de area 9 y vuelve a 5
        self.assertTrue(all(o == [] for o in outs))
        self.assertEqual(p.stats["released"], 0)

    def test_release_no_actua_con_el_lapiz_activo(self):
        p, c = AndroidPalm(release_ms=100), Clock()
        pen_for(p, c, 5)
        for i in range(400):
            p.pen_frame(c.tick())                                       # lapiz continuo
            self.assertEqual(p.filter([(1, 800, 800, 3)], c.t, False), [])
        self.assertEqual(p.stats["released"], 0)

    def test_tracker_reset_conserva_estado_sin_activar_lapiz(self):
        p, c = AndroidPalm(), Clock()
        p.filter([(1, 800, 800, 9)], c.tick(), False)                   # dedo nuevo sin lapiz: pasa
        p.tracker_reset(c.tick())
        self.assertIsNone(p.last_pen)                                   # el ruido NO activa el rechazo
        o = p.filter([(7, 802, 800, 9)], c.tick(), False)               # tid nuevo en el mismo sitio
        self.assertEqual(o[0][0], 7)
        self.assertEqual(p.stats["inherit"], 1)
        self.assertFalse(p.pen_active(c.t))

    def test_ruido_no_retrasa_un_dedo_sin_lapiz(self):
        p, c = AndroidPalm(), Clock()
        for i in range(50):
            if i % 5 == 4:
                p.tracker_reset(c.tick())
            o = p.filter([(i, 800, 800, 9)], c.tick(), False)
            self.assertEqual(len(o), 1, i)

    def test_tope_de_fantasmas(self):
        p, c = AndroidPalm(max_ghosts=16), Clock()
        pen_for(p, c, 5)
        for i in range(200):                                            # palmas baneadas que van y vienen lejos, con lapiz continuo
            p.pen_frame(c.tick())
            p.filter([(i, (i * 300) % 2000, (i * 170) % 3000, 9)], c.t, True)
            for _ in range(40):
                p.pen_frame(c.tick()); p.filter([(i, (i * 300) % 2000, (i * 170) % 3000, 9)], c.t, True)
            p.filter([], c.tick(), True)
            self.assertLessEqual(len(p.ghosts), 16)

    def test_diez_dedos_sin_lapiz_sin_retardo(self):
        p, c = AndroidPalm(), Clock()
        pts = [(i, 100 + 150 * i, 500, 9) for i in range(10)]
        self.assertEqual(p.filter(pts, c.tick(), False), pts)


def ms_to_frames(x):
    return int(round(x / (DT * 1e3)))


class Bench(unittest.TestCase):
    LIMIT_US = 50.0

    def test_camino_sin_lapiz_menos_de_50us(self):
        for n_pts in (0, 1, 2, 3, 10):
            us = bench_palm.bench(n_pts, pen=False, n=10000, repeat=3)
            self.assertLess(us, self.LIMIT_US, "%d dedos: %.2f us" % (n_pts, us))

    def test_con_lapiz_menos_de_50us_hasta_2_dedos(self):
        for n_pts in (1, 2):
            self.assertLess(bench_palm.bench(n_pts, pen=True, n=10000, repeat=3), self.LIMIT_US)


class Fuzz(unittest.TestCase):
    def test_fuzz_puro_120_semillas(self):
        for seed in range(120):
            for kw in ({}, {"release_ms": 200}, {"replay_start": False, "tap_replay": False}):
                X.fuzz_pure(seed, n=1500, **kw)

    def test_fuzz_puro_reproducible(self):
        self.assertEqual(X.fuzz_pure(7), X.fuzz_pure(7))

    def test_memoria_acotada_200k_frames(self):
        gc.collect(); tracemalloc.start()
        X.fuzz_pure(11, n=40000)
        a = tracemalloc.take_snapshot()
        X.fuzz_pure(11, n=40000)
        cur, peak = tracemalloc.get_traced_memory(); tracemalloc.stop()
        self.assertLess(peak, 2_000_000)                                # un AndroidPalm cuesta KB, no crece con el tiempo
        import palm_android
        p = palm_android.AndroidPalm(); t = 100.0
        for i in range(50000):
            t += DT
            p.pen_frame(t); p.filter([(i % 7, 100 * (i % 20), 700, 9)], t, True)
        self.assertLessEqual(len(p.ghosts), p.max_ghosts); self.assertLessEqual(len(p.rec), 10)


if __name__ == "__main__":
    unittest.main()
