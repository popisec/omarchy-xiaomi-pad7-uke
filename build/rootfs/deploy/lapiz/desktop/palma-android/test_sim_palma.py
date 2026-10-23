#!/usr/bin/env python3
"""Simulacion con el demonio REAL parcheado + validador kernel-like: cd .../palma-android && python3 -m unittest test_sim_palma -v"""
import os, subprocess, sys, tempfile, unittest
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sim_palma as S

SC = S.scenarios()


def go(name, **kw):
    f, m = SC[name]
    out, mod = S.run(f, **kw)
    return out, m


class Sim(unittest.TestCase):
    def assertClean(self, out):
        mx, v = S.kernel(out)
        self.assertEqual(v, [], v[:5])
        return mx

    def test_todos_los_escenarios_0_violaciones(self):
        for name in SC:
            out, _ = go(name)
            self.assertClean(out)

    def test_bandera_apagada_identica_al_demonio_sin_parche(self):
        for name in ("pellizco_sin_lapiz", "palma_antes_del_lapiz", "pellizco_tras_rafaga_off700_pf1", "estres_intercalado"):
            f, _ = SC[name]
            a, _ = S.run(f, palm=False)
            b, _ = S.run(f, plain=True)
            self.assertEqual([e for _, e in a], [e for _, e in b], name)

    def test_pellizco_sin_lapiz_igual_que_sin_modulo(self):
        f, m = SC["pellizco_sin_lapiz"]
        a, _ = S.run(f); b, _ = S.run(f, plain=True)
        self.assertEqual([e for _, e in a], [e for _, e in b])
        self.assertEqual(S.max_simult(a, *m["pinch"]), 2)
        self.assertEqual(S.downs(a, *m["pinch"])[0], m["pinch"][0])     # sin retardo

    def test_pellizco_tras_rafaga_valido(self):
        for off in (0, 700):
            for pf in (0, 1):
                out, m = go("pellizco_tras_rafaga_off%d_pf%d" % (off, pf))
                self.assertClean(out)
                self.assertEqual(S.max_simult(out, *m["pinch"]), 2)
                d = S.downs(out, *m["pinch"])
                self.assertEqual(len(d), 2)
                self.assertLessEqual((d[0] - m["pinch"][0]) * S.DT, 0.070)    # <= retardo fuerte + 1 frame (margen aun vivo)

    def test_palma_rechazada(self):
        for name in ("palma_antes_del_lapiz", "palma_durante_escritura", "palma_20ms_tras_lapiz", "pellizco_con_palma_baneada", "estres_intercalado"):
            out, m = go(name)
            self.assertClean(out)
            first_pen = m["pen"][0] if "pen" in m else m["todo"][0]
            self.assertEqual(S.downs(out, first_pen, m["pinch"][0] if "pinch" in m else 10 ** 9) if name != "pellizco_con_palma_baneada" else [], [], name)
            base, _ = S.run(SC[name][0], plain=True)
            self.assertGreater(len(S.downs(base, first_pen)), 0, "sin modulo la palma SI genera toques (%s)" % name)

    def test_palma_antes_del_lapiz_solo_un_toque_espureo_previo(self):
        out, m = go("palma_antes_del_lapiz")
        d = S.downs(out)
        self.assertEqual(d[0], m["palma_pre"][0])                         # inevitable: sin retardo para dedos sin lapiz
        self.assertEqual(len([i for i in d if i < m["pinch"][0]]), 1)
        self.assertEqual(S.max_simult(out, *m["pinch"]), 2)

    def test_pellizco_con_palma_baneada_dos_dedos(self):
        out, m = go("pellizco_con_palma_baneada")
        self.assertEqual(S.max_simult(out, *m["pinch"]), 2)
        self.assertEqual(len(S.downs(out)), 2)

    def test_dedo_sin_retardo_con_o_sin_lapiz_previo(self):
        for name in ("dedo_sin_lapiz", "dedo_500ms_tras_lapiz"):
            out, m = go(name)
            self.assertEqual(S.downs(out), [m["dedo"][0]], name)

    def test_dedo_moviendose_retardo(self):
        for name, want in (("dedo_moviendose_tras_hover", 0.040), ("dedo_moviendose_tras_escritura", 0.064)):
            out, m = go(name)
            d = S.downs(out)
            self.assertEqual(len(d), 1)
            self.assertAlmostEqual((d[0] - m["dedo"][0]) * S.DT, want, delta=0.008, msg=name)

    def test_toque_breve(self):
        out, m = go("toque_breve_tras_hover")
        self.assertEqual(len(S.downs(out)), 1); self.assertClean(out)
        out, m = go("toque_breve_tras_escritura")
        self.assertEqual(S.downs(out), [])

    def test_pellizco_entre_rafagas(self):
        out, m = go("pellizco_entre_rafagas")
        for k in ("pinch", "pinch2"):
            self.assertEqual(S.max_simult(out, *m[k]), 2)
            self.assertEqual(S.downs(out, *m[k])[0], m[k][0])            # 400 ms tras el lapiz: sin retardo


class Patch(unittest.TestCase):
    def test_dry_run_sobre_pen_patch_y_conflicto_con_palma_antigua(self):
        D = os.path.join(S.DEP, "lapiz")
        d = tempfile.mkdtemp(); dst = os.path.join(d, "uke-touchd-pen.py")
        open(dst, "w").write(open(os.path.join(S.DEP, "tactil", "uke-touchd.py")).read())
        subprocess.run(["patch", "-p0", "-s", dst, os.path.join(D, "uke-touchd-pen.patch")], check=True)
        r = subprocess.run(["patch", "-p0", "--dry-run", dst, S.PATCH], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        subprocess.run(["patch", "-p0", "-s", dst, S.PATCH], check=True)
        subprocess.run([sys.executable, "-m", "py_compile", dst], check=True)
        src = open(dst).read()
        self.assertNotIn("ABS_MT_TOOL_TYPE", src); self.assertNotIn("MT_TOOL_PALM", src)
        # excluyente con el PalmGuard
        dst2 = os.path.join(d, "b.py")
        open(dst2, "w").write(open(os.path.join(S.DEP, "tactil", "uke-touchd.py")).read())
        subprocess.run(["patch", "-p0", "-s", dst2, os.path.join(D, "uke-touchd-pen.patch")], check=True)
        subprocess.run(["patch", "-p0", "-s", dst2, os.path.join(D, "desktop", "uke-touchd-palm.patch")], check=True)
        self.assertNotEqual(subprocess.run(["patch", "-p0", "--dry-run", dst2, S.PATCH], capture_output=True).returncode, 0)

    def test_originales_intactos(self):
        self.assertNotIn("palm_android", open(os.path.join(S.DEP, "tactil", "uke-touchd.py")).read())
        self.assertNotIn("palm_android", open(os.path.join(S.DEP, "lapiz", "uke-touchd-pen.patch")).read())


if __name__ == "__main__":
    unittest.main()
