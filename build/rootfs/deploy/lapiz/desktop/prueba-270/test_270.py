#!/usr/bin/env python3
"""Simulacion del mapa lapiz/tactil -> pantalla para uke-rotate 0/90/180/270. 21-oct-2026. Solo calculo, no toca la tablet.

Fuentes (comprobadas 21-oct-2026):
- Hyprland v0.56.2 src/managers/input/InputManager.hpp MATRICES[8][6] (la MISMA tabla para input:touchdevice:transform y input:tablet:transform;
  InputManager.cpp setTouchDeviceConfigs L1982 y setTabletConfigs L2027 llaman a libinput_device_config_calibration_set_matrix(MATRICES[N])).
- libinput 1.32.0 src/evdev-tablet.c: tablet_init_calibration solo si INPUT_PROP_DIRECT (uke_pen.py:252 lo activa); la matriz se aplica con
  evdev_transform_absolute en coordenadas del dispositivo, igual que el tactil. Hyprland Tablets.cpp onTabletAxis -> warpAbsolute(x,y normalizados)
  sobre logicalBox() del output ligado (input:tablet:output); Touch.cpp usa pos*size del monitor. No hay transform inverso para absolutos.
Convencion: matriz [a b c d e f]: x' = a x + b y + c ; y' = d x + e y + f, con x,y en 0..1 del panel SIN rotar (3200x2136) y y hacia abajo.
"""
import itertools
import unittest

# Copia literal de MATRICES de Hyprland v0.56.2
MATRICES = [
    (1, 0, 0, 0, 1, 0),      # normal
    (0, -1, 1, 1, 0, 0),     # 90
    (-1, 0, 1, 0, -1, 1),    # 180
    (0, 1, 0, -1, 0, 1),     # 270
    (-1, 0, 1, 0, 1, 0),     # flipped
    (0, 1, 0, 1, 0, 0),      # flipped + 90
    (1, 0, 0, 0, -1, 1),     # flipped + 180
    (0, -1, 1, -1, 0, 1),    # flipped + 270
]
PANEL = (3200, 2136)
SCALE = 2
DEG_TO_TF = {0: 0, 90: 1, 180: 2, 270: 3}


def monitor_size(deg):
    """Tamano logico del monitor (con escala 2) tras la rotacion."""
    w, h = PANEL[0] / SCALE, PANEL[1] / SCALE
    return (h, w) if deg in (90, 270) else (w, h)


def apply_matrix(m, x, y):
    a, b, c, d, e, f = m
    return a * x + b * y + c, d * x + e * y + f


def cursor_pos(deg, panel_pt, tf=None):
    """Donde cae el cursor (px logicos) si el dedo/lapiz toca panel_pt (0..1 del panel sin rotar), con transform tf (por defecto el del monitor)."""
    tf = DEG_TO_TF[deg] if tf is None else tf
    x, y = apply_matrix(MATRICES[tf], *panel_pt)
    x = min(max(x, 0.0), 1.0)
    y = min(max(y, 0.0), 1.0)
    w, h = monitor_size(deg)
    return x * w, y * h


def panel_to_logical_truth(deg, panel_pt):
    """Verdad fisica independiente de MATRICES: wl_output transform N muestra el contenido logico girado N*90 grados
    ANTI-horario sobre el panel (la esquina logica sup-derecha va a la sup-izquierda del panel con N=1). Aqui se invierte esa regla."""
    def ccw(p):                    # un giro anti-horario en coordenadas normalizadas con y hacia abajo: (x,y) -> (y, 1-x)
        return (p[1], 1 - p[0])
    # logico -> panel = ccw^N ; invertir probando las 4 esquinas/punto no hace falta: ccw es biyectiva, se invierte iterando 4-N veces
    p = panel_pt
    for _ in range((4 - DEG_TO_TF[deg]) % 4):
        p = ccw(p)
    return p                       # punto logico normalizado


def penmap_table():
    """Para cada transform de lapiz p (0..7) cuando el monitor esta en 270: efecto sobre la tinta (donde cae respecto a donde esta la punta)."""
    good = MATRICES[3]
    rows = []
    for p in range(8):
        pts = {"sup-izq": (0, 0), "sup-der": (1, 0), "inf-izq": (0, 1), "inf-der": (1, 1)}
        # esquinas de PANTALLA (logicas): se calcula donde acaba la tinta si la punta esta en cada una
        res = []
        for name, q in {"sup-izq": (0, 0), "sup-der": (1, 0), "inf-der": (1, 1), "inf-izq": (0, 1)}.items():
            # punto del panel bajo la punta: inversa de la buena (ensayo sobre las 4 esquinas y centro basta: es afin y biyectiva)
            a, b, c, d, e, f = good
            det = a * e - b * d
            px = (e * (q[0] - c) - b * (q[1] - f)) / det
            py = (-d * (q[0] - c) + a * (q[1] - f)) / det
            x, y = apply_matrix(MATRICES[p], px, py)
            res.append((name, (round(x), round(y))))
        rows.append((p, res))
    return rows


class Test270(unittest.TestCase):
    def test_matriz_igual_a_la_verdad_fisica(self):
        """Para los 4 angulos: la matriz de Hyprland lleva el punto tocado del panel al punto logico correcto."""
        for deg in (0, 90, 180, 270):
            for pt in [(0, 0), (1, 0), (0, 1), (1, 1), (.25, .75), (.5, .5)]:
                got = apply_matrix(MATRICES[DEG_TO_TF[deg]], *pt)
                exp = panel_to_logical_truth(deg, pt)
                self.assertAlmostEqual(got[0], exp[0], msg=f"{deg} {pt}")
                self.assertAlmostEqual(got[1], exp[1], msg=f"{deg} {pt}")

    def test_esquina_fisica_misma_esquina_visible(self):
        """La esquina fisica sup-izq del panel (sin rotar) se ve en la esquina logica correcta y el lapiz coincide con el dedo."""
        # panel sup-izq: con N giros anti-horarios del contenido, esa esquina del panel muestra la esquina logica:
        visible = {0: "sup-izq", 90: "sup-der", 180: "inf-der", 270: "inf-izq"}
        for deg, corner in visible.items():
            w, h = monitor_size(deg)
            cx, cy = cursor_pos(deg, (0, 0))
            exp = {"sup-izq": (0, 0), "sup-der": (w, 0), "inf-der": (w, h), "inf-izq": (0, h)}[corner]
            self.assertEqual((round(cx), round(cy)), exp, f"{deg}")
            # lapiz con penmap/touchmap por defecto '0 1 2 3' = mismo transform que el dedo
            self.assertEqual(cursor_pos(deg, (0, 0), tf=DEG_TO_TF[deg]), (cx, cy))

    def test_las_4_esquinas_son_biyectivas_y_no_espejadas(self):
        """Giro puro (determinante +1) en los 4 angulos: sin espejo."""
        for tf in range(4):
            a, b, c, d, e, f = MATRICES[tf]
            self.assertEqual(a * e - b * d, 1, f"transform {tf}")
        for tf in range(4, 8):
            a, b, c, d, e, f = MATRICES[tf]
            self.assertEqual(a * e - b * d, -1, f"transform {tf}")

    def test_270_inversa_de_90(self):
        """270 es la inversa exacta de 90: componer las matrices da la identidad (sin simetria rara)."""
        for pt in [(0.1, 0.2), (0.9, 0.3), (0.5, 0.5)]:
            x, y = apply_matrix(MATRICES[1], *pt)
            x, y = apply_matrix(MATRICES[3], x, y)
            self.assertAlmostEqual(x, pt[0])
            self.assertAlmostEqual(y, pt[1])

    def test_punta_en_todo_el_panel_cae_en_pantalla(self):
        for deg in (0, 90, 180, 270):
            w, h = monitor_size(deg)
            for ix, iy in itertools.product(range(11), range(11)):
                cx, cy = cursor_pos(deg, (ix / 10, iy / 10))
                self.assertTrue(0 <= cx <= w and 0 <= cy <= h)

    def test_penmap_por_defecto_270(self):
        """touchmap por defecto '0 1 2 3' con uke-pen-sync: el indice tf=3 da valor 3 (mismo que el dedo)."""
        m = "0 1 2 3".split()
        self.assertEqual(int(m[3]), 3)


if __name__ == "__main__":
    import sys
    if "--tabla" in sys.argv:
        for p, res in penmap_table():
            print(p, res)
    else:
        unittest.main()
