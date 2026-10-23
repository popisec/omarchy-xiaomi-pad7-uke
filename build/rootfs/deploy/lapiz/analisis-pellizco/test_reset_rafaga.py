#!/usr/bin/env python3
"""Con el reset de ráfaga ya integrado en uke-touchd-pen.patch (antes: toque fantasma que sobrevivía a la ráfaga de lápiz y mataba el pellizco)."""
import os, sys, unittest
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import harness as H
from scenario2 import seq



def simult(out):
    """maximo de dedos simultaneos y estado final de slots"""
    k = H.Kernel(); mx = 0
    for fr in out:
        k.apply(fr); mx = max(mx, len(k.slots))
    return mx, k.finish()


class T(unittest.TestCase):
    def test_pellizco_tras_rafaga_con_linea_base_distinta(self):
        out, _ = H.run(seq(700))
        mx, viol = simult(out)
        self.assertEqual(viol, []); self.assertEqual(mx, 2)

    def test_secuencia_valida_sin_desfase(self):
        for pf in (False, True):
            out, _ = H.run(seq(0, pf))
            self.assertEqual(simult(out), (2, []))


if __name__ == "__main__":
    unittest.main()
