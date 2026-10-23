"""thp_tilt.py — estimacion de la inclinacion del lapiz (TILT_X/Y en grados, como ABS_TILT_X/Y de Android) desde un frame 0x509.

21-oct-2026: v3 = mismos coeficientes que v2 (los modelos alternativos no ganaron en validacion honesta) + estimate_conf() y TiltFilter (EMA).
20-oct-2026, v2 (ajustada con cap4+cap8). EXPERIMENTAL, medido solo en Android con el Focus Pen M80P (2 sesiones, 1 lapiz, 1 agarre).
Detalle y cifras: build/android/lapiz-20261019/analisis/TILT-DECODIFICACION.md (seccion «cap8»).
Hallazgo de cap8: a2 (amplitud del grupo 2) crece de forma monotona con la inclinacion TOTAL (|TX,TY|), en las dos sesiones; la direccion la dan
dr (X) y dp = p2 - p1 (Y, con signo). El modelo v1 (lineal en a2) no generalizaba: en cap8 daba TY r=-0.21, MAE 48 (baseline 32).
  la = ln(1 + a2)
  TILT_X = A0 + A1*dr + A2*r1 + A3*dr*la
  TILT_Y = B0 + B1*dp + B2*dp^2 + B3*la + B4*dp*la
Validacion dejando un bloque fuera (bloques de <=1.5 s), cap4+cap8: TX r=0.97 MAE 3.4 (baseline 12.2); TY r=0.99 MAE 4.8 (baseline 27.9).
Solo con la punta apoyada (F+0x44 == 16): en hover la relacion se rompe, por eso estimate() devuelve None. Los extremos (>45 grados) se subestiman ~8 grados.
Caracteristicas (F = frame completo, mismo convenio que thp_pen.py):
  r1 = centroide de filas de la rejilla 1 (40x12 i16 @F+0x64); r2 igual en la rejilla 2 (@F+0x7E4); dr = r2 - r1
  p1 / p2 = posicion media (parabola) del maximo de los 8 planos del grupo 1 (@F+0x424, paso 0x78, 60 palabras) / del grupo 2 (@F+0xBA6); dp = p2 - p1
  a2 = amplitud media del maximo de los 8 planos del grupo 2
"""
import math
import struct

GRID1, GRID2, ROWS, COLS = 0x64, 0x7E4, 40, 12
PL1, PL2, PSTEP, PLEN = 0x424, 0xBA6, 0x78, 60
NEED = PL2 + 7 * PSTEP + PLEN * 2
CONTACT_OFF = 0x44
MAGIC_PEN = 0x509
# coeficientes (ajuste sobre todos los pares con punta apoyada)
TX_COEF = (-13.016538611891695, -23.40444356443419, 0.6997817740798418, 7.384350847824661)   # A0, dr, r1, dr*la
TY_COEF = (-41.46375952433179, -23.875734916394073, -1.7913672591909116, 10.898197080076436, 6.778625308400509)   # B0, dp, dp^2, la, dp*la
CONF_DR0, CONF_DR_W, CONF_LA0, CONF_LA_W = 1.8, 0.4, 6.9, 0.25   # umbrales de confidence()
TILT_MAX = 60.0   # rango declarado por Android (min -60, max 60); el sensor llega a +-69 en los extremos


def _row_centroid(g, off):
    """Centroide de filas (ventana +-3 alrededor del maximo, base = minimo de la ventana) de la parte positiva de la rejilla en F[off:]."""
    rows = []
    for r in range(ROWS):
        s = 0
        for v in g[off // 2 + r * COLS: off // 2 + (r + 1) * COLS]:
            if v > 0:
                s += v
        rows.append(s)
    a = rows.index(max(rows))
    lo, hi = max(0, a - 3), min(ROWS, a + 4)
    seg = rows[lo:hi]
    base = min(seg)
    sw = sm = 0
    for i, v in enumerate(seg):
        w = v - base
        if w > 0:
            sw += w
            sm += (lo + i) * w
    return (sm / sw) if sw else float(a)


def _plane_peak(w, off):
    seg = w[off // 2: off // 2 + PLEN]
    m = max(seg)
    k = seg.index(m)
    if 0 < k < PLEN - 1:
        y0, y1, y2 = seg[k - 1], m, seg[k + 1]
        d = y0 - 2 * y1 + y2
        if d:
            return k + 0.5 * (y0 - y2) / d, m
    return float(k), m


def features(F):
    """(r1, p1, dr, a2, p2) o None si F no es un frame de lapiz completo."""
    if len(F) < NEED:
        return None
    fid, magic, nid, nmag = struct.unpack_from("<H2xH2xH2xH", F, 4)
    if magic != MAGIC_PEN or nmag != (~magic & 0xFFFF) or nid != (~fid & 0xFFFF):
        return None
    w = struct.unpack_from("<%dh" % (NEED // 2), F, 0)
    r1 = _row_centroid(w, GRID1)
    r2 = _row_centroid(w, GRID2)
    p1 = p2 = a2 = 0.0
    for i in range(8):
        p1 += _plane_peak(w, PL1 + i * PSTEP)[0]
        q, m = _plane_peak(w, PL2 + i * PSTEP)
        p2 += q
        a2 += m
    return r1, p1 / 8, r2 - r1, a2 / 8, p2 / 8


def _estimate_full(F):
    """(tx, ty, dr, la) sin recortar a nada mas que +-60, o None."""
    if len(F) < NEED or struct.unpack_from("<H", F, CONTACT_OFF)[0] != 16:
        return None
    f = features(F)
    if f is None:
        return None
    r1, p1, dr, a2, p2 = f
    la = math.log(1.0 + max(a2, 0.0))
    dp = p2 - p1
    tx = TX_COEF[0] + TX_COEF[1] * dr + TX_COEF[2] * r1 + TX_COEF[3] * dr * la
    ty = TY_COEF[0] + TY_COEF[1] * dp + TY_COEF[2] * dp * dp + TY_COEF[3] * la + TY_COEF[4] * dp * la
    c = lambda v: max(-TILT_MAX, min(TILT_MAX, v))
    return c(tx), c(ty), dr, la


def estimate(F):
    """(tilt_x, tilt_y) en grados (flotantes, recortados a +-60), o None si no es un frame de lapiz o no hay punta apoyada."""
    r = _estimate_full(F)
    return None if r is None else (r[0], r[1])


def _sig(z):
    """1/(1+e^z): decreciente en z."""
    return 1.0 / (1.0 + math.exp(max(-30.0, min(30.0, z))))


def confidence(dr, la):
    """(cx, cy) en [0,1]: confianza heuristica del TX y del TY de un frame, SOLO a partir de sus caracteristicas.
    cx cae con |dr| grande (|dr|>~1,8 filas = percentil ~90: inclinacion X extrema, donde v2 subestima);
    cy cae con ln(1+a2) alto (>~6,9, a2>~1000 = inclinacion total extrema/saturacion). Umbrales fijados a ojo sobre
    cap4+cap8 (descriptivos, NO validados en datos no vistos). Es una bandera de «extremo/dudoso», no una probabilidad calibrada:
    el error de v2 es sobre todo sesgo sistematico y la confianza solo recoge una parte (ver TILT-DECODIFICACION.md, v3)."""
    return _sig((abs(dr) - CONF_DR0) / CONF_DR_W), _sig((la - CONF_LA0) / CONF_LA_W)


def estimate_conf(F):
    """(tilt_x, tilt_y, conf_x, conf_y) o None. Mismos tilt que estimate(F); las confianzas permiten descartar frames dudosos (sugerido: <0,5)."""
    r = _estimate_full(F)
    if r is None:
        return None
    cx, cy = confidence(r[2], r[3])
    return r[0], r[1], cx, cy


class TiltFilter:
    """Suavizado EMA de estimate_conf() con descarte de frames dudosos. Sugerido: alpha=0,2 a ~240 Hz (frames cada ~4,2 ms) = retardo ~17 ms.
    update(t, F) -> (tx, ty, cx, cy) suavizados o None (sin punta/lapiz invalido: se reinicia el estado). El estado tambien se reinicia si pasan
    > gap s entre frames. Un eje con confianza < min_conf no actualiza su EMA (mantiene el ultimo valor; si no hay ninguno, devuelve None)."""

    def __init__(self, alpha=0.2, gap=0.05, min_conf=0.5):
        self.alpha, self.gap, self.min_conf = alpha, gap, min_conf
        self.reset()

    def reset(self):
        self.t = None
        self.v = [None, None]

    def update(self, t, F):
        r = estimate_conf(F)
        if r is None or (self.t is not None and t - self.t > self.gap):
            self.reset()
            if r is None:
                return None
        self.t = t
        for i in (0, 1):
            if r[2 + i] < self.min_conf:
                continue
            self.v[i] = r[i] if self.v[i] is None else self.v[i] + self.alpha * (r[i] - self.v[i])
        if self.v[0] is None or self.v[1] is None:
            return None
        return self.v[0], self.v[1], r[2], r[3]
