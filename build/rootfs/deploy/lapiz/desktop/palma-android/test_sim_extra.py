#!/usr/bin/env python3
"""Escenarios extra con el demonio REAL + validador kernel-like + fuzzing (semilla fija). cd .../palma-android && python3 -m unittest test_sim_extra -v"""
import os, signal, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sim_extra as X
import sim_palma as S

SC = X.scenarios()
OPTS = {"base": (), "release": ("--palm-release-ms", "300"), "keep": ("--palm-noise-keep",), "todo": ("--palm-release-ms", "300", "--palm-noise-keep")}


def go(name, opts="base"):
    f, m, key = SC[name]
    out, _ = S.run(f, args=OPTS[opts])
    return out, m, key


def after_pen(out, m):
    return [d for d in S.downs(out) if d > m["pen"][0]] if "pen" in m else S.downs(out)


class Timeout(Exception):
    pass


def alarm(s):
    def h(*a):
        raise Timeout()
    signal.signal(signal.SIGALRM, h); signal.alarm(s)


class Todos(unittest.TestCase):
    def test_todos_los_escenarios_0_violaciones_con_cada_combinacion_de_opciones(self):
        for n, name in enumerate(SC):
            if name.startswith("rafaga_larga"):
                continue                                                # tiene su propia prueba (12 s)
            for o in (("base", "todo") if n % 3 == 0 else ("base",)):   # las opciones M1/noise-keep ya las ejercitan el fuzz y sus pruebas propias
                out, m, key = go(name, o)
                mx, v = S.kernel(out)
                self.assertEqual(v, [], (name, o, v[:3]))


class Palma(unittest.TestCase):
    def test_arrastre_tras_rafaga_sin_toques(self):
        for d in (0, 1, 2, 4, 8):
            out, m, _ = go("arrastre_post_rafaga_d%d" % d)
            self.assertEqual(S.downs(out, m["pen"][0]), [], d)          # solo el down previo al lapiz (limite conocido), nada despues

    def test_arrastre_intercalado_lento_rechazado_rapido_pasa_como_en_android(self):
        out, m, _ = go("arrastre_intercalado_k2_s6")
        self.assertEqual(S.downs(out), [])                              # 1 nodo (53 px) cada 66 ms: contacto quieto en la ventana de 64 ms
        for name in ("arrastre_intercalado_k4_s3", "arrastre_intercalado_k8_s2"):
            out, m, _ = go(name)
            self.assertGreater(len(S.downs(out)), 0, name)              # LIMITE (= regla de Android): > 8 px en la ventana = dedo (tras el
            self.assertEqual(S.kernel(out)[1], [])                      # reset los ids cambian cada frame: un down por frame de dedos)

    def test_palma_que_va_y_viene_gap_dentro_del_margen_0_toques(self):
        for gap in (30, 60, 90):
            out, m, _ = go("palma_va_y_viene_gap%d" % gap)
            self.assertEqual(S.downs(out, m["pen0"][0]), [], gap)

    def test_palma_que_vuelve_con_lapiz_fuera_de_rango_mas_de_100ms_toca(self):
        out, m, _ = go("palma_va_y_viene_gap200")
        self.assertGreaterEqual(len(S.downs(out, m["pen0"][0])), 6)    # sin lapiz activo no hay rechazo (por diseno, regla A)

    def test_lapiz_parpadea_con_palma_0_toques_tras_el_primero(self):
        for gap in (2, 10, 40, 90):
            out, m, _ = go("lapiz_parpadea_gap%d_con_palma" % gap)
            self.assertEqual(S.downs(out, m["p0"][0]), [], gap)
            self.assertEqual(len(S.downs(out)), 1)

    def test_ruido_bajo_hover_o_tras_lapiz_no_suelta_palma(self):
        for name in ("ruido_bajo_hover_palma", "palma_baneada_con_ruido_tras_lapiz"):
            for o in ("base", "keep"):
                out, m, _ = go(name, o)
                self.assertEqual(S.downs(out), [], (name, o))

    def test_rafaga_larga_2_minutos(self):
        alarm(120)
        try:
            out, m, _ = go("rafaga_larga_2min")
        finally:
            signal.alarm(0)
        self.assertEqual(S.downs(out, m["pen"][0], m["dedo"][0]), [])   # 120 s de lapiz + palma tras la rafaga: ninguno
        self.assertEqual(len(S.downs(out, *m["dedo"])), 1)              # y el dedo posterior (> 100 ms) pasa sin retardo
        self.assertEqual(X.lat(out, m, "dedo"), 0.0)
        self.assertEqual(S.kernel(out)[1], [])


class DedoLegitimo(unittest.TestCase):
    def test_latencia_dedo_que_se_mueve_tras_lapiz(self):
        # (tag, gap_ms) -> latencia esperada (ms simulados) desde el primer frame del dedo hasta el primer down
        for tag, want in (("hover", 44.2), ("escritura", 66.4)):
            for gap in (20, 50):
                out, m, _ = go("dedo_mueve_%s_gap%d" % (tag, gap))
                self.assertAlmostEqual(X.lat(out, m, "dedo"), want, delta=5, msg=(tag, gap))
            out, m, _ = go("dedo_mueve_%s_gap0" % tag)
            self.assertEqual(S.downs(out), [], "gap 0: el dedo que ya estaba cuando el lapiz sigue activo y se mueve poco antes de decidir")  # LIMITE
            for gap in (120, 200, 500):
                out, m, _ = go("dedo_mueve_%s_gap%d" % (tag, gap))
                self.assertEqual(X.lat(out, m, "dedo"), 0.0, (tag, gap))

    def test_dedo_quieto_justo_tras_el_lapiz_zona_muerta(self):
        # hover: rechazado hasta levantarlo si empieza < 100-40 = 60 ms tras el ultimo frame; escritura < 100-64 = 36 ms; despues pasa a 44/66 ms
        for gap in (0, 20, 50):
            self.assertEqual(S.downs(go("dedo_quieto_hover_gap%d" % gap)[0]), [], gap)
        for gap in (0, 20):
            self.assertEqual(S.downs(go("dedo_quieto_escritura_gap%d" % gap)[0]), [], gap)
        for gap, want in ((90, 44.2),):
            out, m, _ = go("dedo_quieto_hover_gap%d" % gap); self.assertAlmostEqual(X.lat(out, m, "dedo"), want, delta=5)
        for gap in (50, 90):
            out, m, _ = go("dedo_quieto_escritura_gap%d" % gap); self.assertAlmostEqual(X.lat(out, m, "dedo"), 66.4, delta=5)
        for gap in (120, 200, 500):
            for tag in ("hover", "escritura"):
                out, m, _ = go("dedo_quieto_%s_gap%d" % (tag, gap)); self.assertEqual(X.lat(out, m, "dedo"), 0.0)

    def test_gestos_multidedo_tras_lapiz(self):
        for gap in (20, 60):
            for name, n in (("scroll2", 2), ("pellizco", 2), ("gesto3", 3)):
                out, m, _ = go("%s_tras_lapiz_gap%d" % (name, gap))
                self.assertEqual(S.max_simult(out, *m["dedo"]), n, name)
                self.assertEqual(len(S.downs(out, *m["dedo"])), n, name)
                self.assertLessEqual(X.lat(out, m, "dedo"), 70.0)               # 64 ms + 1 frame
                self.assertLessEqual(X.lat(out, m, "dedo", n - 1), 75.0)        # todos los dedos entran juntos

    def test_borde_replay_de_inicio_posicion_identica_a_sin_lapiz(self):
        ref, m0, _ = go("borde_entra_sin_lapiz")
        p0 = X.first_down_pos(ref, m0, "dedo")
        for gap in (20, 60):
            out, m, _ = go("borde_entra_tras_lapiz_gap%d" % gap)
            self.assertEqual(X.first_down_pos(out, m, "dedo"), p0, gap)        # uke-gestures ve el inicio en el borde
        f, m, _ = SC["borde_entra_tras_lapiz_gap20"]
        out, _ = S.run(f, args=("--palm-no-replay-start",))
        self.assertNotEqual(X.first_down_pos(out, m, "dedo"), p0)               # sin la mitigacion el inicio ya estaba 66 ms dentro

    def test_diez_dedos(self):
        out, m, _ = go("diez_dedos_sin_lapiz")
        self.assertEqual((S.max_simult(out, *m["dedo"]), X.lat(out, m, "dedo")), (10, 0.0))
        out, m, _ = go("diez_dedos_con_hover")
        self.assertEqual(S.downs(out), [])                                      # 10 quietos con lapiz activo: 10 palmas
        out, m, _ = go("diez_dedos_moviendose_con_hover")
        self.assertEqual(S.max_simult(out, *m["dedo"]), 10)
        self.assertLessEqual(X.lat(out, m, "dedo"), 50.0)

    def test_tids_reutilizados_sin_violaciones_ni_atascos(self):
        out, m, _ = go("tids_reutilizados")
        self.assertEqual(S.kernel(out)[1], [])
        self.assertLessEqual(S.max_simult(out, 0, 10 ** 9), 2)


class Ruido(unittest.TestCase):
    def test_ruido_aislado_no_activa_rechazo(self):
        out, m, _ = go("ruido_aislado_toque_nuevo")
        self.assertEqual(X.lat(out, m, "dedo"), 0.0)                            # sin retardo 40/64
        self.assertEqual(len(S.downs(out)), 1)
        out, m, _ = go("ruido_aislado_dedo_continuo")
        self.assertEqual(S.kernel(out)[1], [])

    def test_ruido_el_demonio_ya_cortaba_el_dedo_y_noise_keep_lo_arregla(self):
        f, m, _ = SC["ruido_aislado_dedo_continuo"]
        plain, _ = S.run(f, plain=True)
        base, _ = S.run(f)
        keep, _ = S.run(f, args=("--palm-noise-keep",))
        self.assertEqual(len(S.downs(plain)), 40)                               # pen.patch: cada 0x509 suelta el dedo (hallazgo, no es de este modulo)
        self.assertEqual(len(S.downs(base)), 40)                                # el modulo no lo empeora
        self.assertEqual(len(S.downs(keep)), 1)                                 # con la bandera: un solo toque continuo
        self.assertEqual(S.kernel(keep)[1], [])


class Mitigaciones(unittest.TestCase):
    def test_release_dedo_pequeno_quieto_justo_tras_lapiz(self):
        out, m, _ = go("dedo_quieto_area_m_gap20_largo")
        self.assertEqual(S.downs(out), [])                                      # por defecto apagado: ban hasta levantar (README)
        out, m, _ = go("dedo_quieto_area_m_gap20_largo", "release")
        self.assertEqual(len(S.downs(out)), 1)
        self.assertLessEqual(X.lat(out, m, "dedo"), 400.0)                      # 300 ms de inactividad del lapiz + margen 100 ms - 20 ms de hueco
        self.assertEqual(S.kernel(out)[1], [])

    def test_release_nunca_con_area_de_palma(self):
        out, m, _ = go("dedo_quieto_area_f_gap20_largo", "release")
        self.assertEqual(S.downs(out), [])

    def test_release_no_cambia_el_resto(self):
        for name in ("palma_baneada_con_ruido_tras_lapiz", "ruido_bajo_hover_palma", "diez_dedos_con_hover"):
            a, _, _ = go(name); b, _, _ = go(name, "release")
            self.assertEqual([e for _, e in a], [e for _, e in b], name)


class Fuzz(unittest.TestCase):
    def test_fuzz_demonio_semillas_fijas(self):
        alarm(240)
        try:
            for seed in range(8):
                for o in ("base", "todo"):
                    f = X.random_timeline(seed)
                    out, _ = S.run(f, args=OPTS[o])
                    mx, v = S.kernel(out)                                       # kernel.finish(): 0 violaciones y 0 slots atascados
                    self.assertEqual(v, [], (seed, o, v[:3]))
                    self.assertLessEqual(mx, 10)
        finally:
            signal.alarm(0)

    def test_fuzz_sin_bandera_identico_al_demonio_sin_parche(self):
        for seed in (0, 1, 2):
            f = X.random_timeline(seed)
            a, _ = S.run(f, palm=False); b, _ = S.run(f, plain=True)
            self.assertEqual([e for _, e in a], [e for _, e in b], seed)

    def test_fuzz_es_reproducible(self):
        a, b = X.random_timeline(5), X.random_timeline(5)
        self.assertEqual(len(a), len(b))                                        # (los bytes difieren: el id de frame del arnes es global)
        a, _ = S.run(X.random_timeline(3)); b, _ = S.run(X.random_timeline(3))
        self.assertEqual([e for _, e in a], [e for _, e in b])


if __name__ == "__main__":
    unittest.main()
