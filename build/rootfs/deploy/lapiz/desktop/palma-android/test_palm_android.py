#!/usr/bin/env python3
"""Pruebas de la logica pura (sin hardware): cd .../palma-android && python3 -m unittest test_palm_android -v"""
import os, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from palm_android import AndroidPalm, PASS, PEND, BAN

DT = 1 / 226.0


def pt(tid, x=1000, y=1000, a=9):
    return (tid, x, y, a)


class Clock:
    def __init__(s, t=100.0): s.t = t
    def tick(s, n=1): s.t += n * DT; return s.t


class T(unittest.TestCase):
    def setUp(self):
        self.p, self.c = AndroidPalm(), Clock()

    def run_frames(self, n, pts_fn, touching=False):
        out = []
        for i in range(n):
            out.append(self.p.filter(pts_fn(i), self.c.tick(), touching))
        return out

    def test_no_pen_no_delay(self):
        out = self.p.filter([pt(1)], self.c.tick())
        self.assertEqual(out, [pt(1)])                                # primer frame, sin retardo

    def test_pinch_without_pen_untouched(self):
        for i in range(30):
            pts = [pt(1, 800 - i, 1000), pt(2, 1200 + i, 1000)]
            self.assertEqual(self.p.filter(pts, self.c.tick()), pts)
        self.assertEqual(self.p.stats["palm"], 0)

    def test_new_finger_during_pen_is_delayed_then_banned_if_static(self):
        self.p.pen_frame(self.c.t)
        outs = []
        for i in range(30):
            self.p.pen_frame(self.c.tick())
            outs.append(self.p.filter([pt(5)], self.c.t))
        self.assertTrue(all(o == [] for o in outs))
        self.assertEqual(self.p.rec[5].state, BAN)

    def test_weak_delay_40ms_moving_finger_passes_after_delay_not_before(self):
        self.p.pen_frame(self.c.t)
        first = None
        for i in range(40):
            self.p.pen_frame(self.c.tick())
            o = self.p.filter([pt(5, 1000 + 4 * i, 1000)], self.c.t)
            if o and first is None:
                first = i * DT
        self.assertIsNotNone(first)
        self.assertAlmostEqual(first, 0.040, delta=2 * DT)

    def test_strong_delay_64ms(self):
        self.p.pen_frame(self.c.t)
        first = None
        for i in range(40):
            self.p.pen_frame(self.c.tick())
            o = self.p.filter([pt(5, 1000 + 4 * i, 1000)], self.c.t, touching=True)
            if o and first is None:
                first = i * DT
        self.assertAlmostEqual(first, 0.064, delta=2 * DT)

    def test_move_threshold_8px(self):
        for dx, expect in ((7, BAN), (9, PASS)):
            p, c = AndroidPalm(), Clock()
            p.pen_frame(c.t)
            for i in range(30):
                p.pen_frame(c.tick())
                p.filter([pt(5, 1000 + (dx if i > 3 else 0), 1000)], c.t)
            self.assertEqual(p.rec[5].state, expect, dx)

    def test_pen_leaves_before_decision_finger_passes(self):
        self.p.pen_frame(self.c.t)
        self.c.tick(int(0.095 / DT))                                   # margen casi vencido
        out = []
        for i in range(30):
            out.append(self.p.filter([pt(5)], self.c.tick()))
        self.assertEqual(out[-1], [pt(5)])                              # nada de bloqueo largo

    def test_tap_replay_hover_and_drop_when_touching(self):
        for touching, n in ((False, 1), (True, 0)):
            p, c = AndroidPalm(), Clock()
            p.pen_frame(c.t); c.tick()
            for i in range(3):
                self.assertEqual(p.filter([pt(9)], c.tick(), touching), [])
            out = p.filter([], c.tick(), touching)
            self.assertEqual(len(out), n)
            self.assertEqual(p.filter([], c.tick(), touching), [])      # un solo frame

    def test_pre_pen_palm_banned_and_inherited_after_burst(self):
        self.p.filter([pt(1, 500, 500, 30)], self.c.tick())            # palma llega sin lapiz: pasa
        self.p.filter([pt(1, 501, 500, 30)], self.c.tick())
        for i in range(60):                                            # rafaga de lapiz >= 100 ms
            self.p.pen_frame(self.c.tick())
        self.assertEqual(self.p.stats["pre"], 1)
        # tr.reset(): la palma vuelve con tid NUEVO en el primer frame de dedos
        for i in range(40):
            self.assertEqual(self.p.filter([pt(77, 502, 502, 30)], self.c.tick()), [])
        self.assertEqual(self.p.stats["inherit"], 1)

    def test_old_finger_resumes_after_burst(self):
        for i in range(40):                                            # dedo apoyado 170 ms (deliberado)
            self.p.filter([pt(1, 500, 500)], self.c.tick())
        for i in range(60):
            self.p.pen_frame(self.c.tick())
        out = self.p.filter([pt(78, 500, 500)], self.c.tick())
        self.assertEqual(out, [pt(78, 500, 500)])

    def test_carry_over_palm_unseen(self):
        for i in range(60):
            self.p.pen_frame(self.c.tick())
        for i in range(10):
            self.assertEqual(self.p.filter([pt(3, 2000, 900)], self.c.tick()), [])
        self.assertEqual(self.p.stats["carry"], 1)

    def test_palm_ban_lasts_while_contact_lives_and_new_finger_passes(self):
        for i in range(60):
            self.p.pen_frame(self.c.tick())
        for i in range(2000):                                          # 9 s de palma apoyada tras el lapiz
            self.assertEqual(self.p.filter([pt(3, 2000, 900)], self.c.tick()), [])
        # un dedo nuevo, lejos de la palma y sin lapiz, pasa de inmediato
        out = self.p.filter([pt(3, 2000, 900), pt(4, 300, 300)], self.c.tick())
        self.assertEqual(out, [pt(4, 300, 300)])

    def test_tracker_glitch_of_banned_palm(self):
        for i in range(60):
            self.p.pen_frame(self.c.tick())
        for i in range(5):
            self.p.filter([pt(3, 2000, 900)], self.c.tick())
        self.p.filter([], self.c.tick())                               # un frame sin pico
        self.assertEqual(self.p.filter([pt(4, 2003, 901)], self.c.tick()), [])   # vuelve con otro tid: sigue baneada

    def test_pen_frame_without_fingers_is_cheap_and_ghost_expires(self):
        self.p.filter([pt(1)], self.c.tick())
        self.p.pen_frame(self.c.tick())
        self.c.tick(100)                                               # 440 ms despues
        self.assertEqual(self.p.filter([pt(9)], self.c.tick()), [pt(9)])
        self.assertEqual(self.p.ghosts, [])


if __name__ == "__main__":
    unittest.main()
