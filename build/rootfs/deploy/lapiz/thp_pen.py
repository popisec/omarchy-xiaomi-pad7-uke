"""thp_pen.py — decodificacion del frame de lapiz (magic 0x509) del NT36532 de la Xiaomi Pad 7 «uke».

19-oct-2026. MEDIDO solo en Android con el Focus Pen M80P (LAPIZ-20261018.md §17–§18); NO validado en Linux. Sin dependencias.

Formato del frame (F = dato+0x100, como en uke-touchd.py; cabecera como la del frame tactil: id u16 @+4, magic @+8,
~id @+0xC, ~magic @+0x10; magic 0x4bf = tactil, 0x509 = lapiz):
  F+0x44  u16    contacto: 16 con la punta apoyada, 0 en hover (concuerda con BTN_TOUCH en el 98,8 % de los frames)
  F+0x64..0x423  rejilla 40 filas x 12 columnas de i16 LE (480 palabras): el centroide de la suma por filas da X
  F+0x424 + i*0x78, i=0..7   8 planos de 60 i16 LE (grupo 1) y otros 8 desde F+0xBA6 (grupo 2): la posicion del maximo
                             con interpolacion parabolica, promediada en el grupo 1, da Y
Calibracion (19-oct, CORREGIDA tras la revision independiente: frames armados con las 8 sondas en orden 7..0; emparejado frame-evento
con desfase +8 ms y ventana +-3 ms; 1443 pares con punta apoyada; validacion cruzada por mitades temporales):
  X = 535.7*fila_centroide + 235.7   (error mediano ~30, p90 ~80 de 21360)
  Y = 531.371*pos + 301.54 + 85.28*sin(2*pi*f) - 3.30*cos(2*pi*f) + 27.74*sin(4*pi*f) + 0.47*cos(4*pi*f), f = parte fraccionaria de pos
      (la correccion armonica quita el sesgo periodico de la interpolacion parabolica: error mediano 61 -> ~26, p90 ~118 -> ~61, validado por
      mitades temporales y dejando un trazo fuera)
Presencia: pico de la rejilla > 80 (96 % de acierto; con lapiz p5=82, sin lapiz p95=83: margen escaso).
La presion NO esta aqui: llega por BLE (informe 5, lapiz_ble.py). La inclinacion NO esta decodificada (el grupo 2 de planos tiene
correlacion debil con TILT, ver LAPIZ-20261018.md §21). Medido solo en Android con el M80P; NO validado en Linux.
"""
import math
import struct

MAGIC_PEN = 0x509
MAGIC_TOUCH = 0x4BF
GRID_OFF, GRID_ROWS, GRID_COLS = 0x64, 40, 12
PLANE_OFF0, PLANE_STEP, PLANE_LEN, PLANES = 0x424, 0x78, 60, 8
PLANE2_OFF0 = 0xBA6   # segundo grupo de 8 planos (sin usar todavia)
CONTACT_OFF = 0x44
X_MAX, Y_MAX = 21359, 31999
X_A, X_B = 535.7, 235.7
Y_A, Y_B = 531.371, 301.54
Y_HARM = (85.28, -3.30, 27.74, 0.47)   # sesgo periodico de la interpolacion parabolica (critica de datos 20-oct): sin/cos de 1.a y 2.a armonica de la fraccion
PRESENCE_MIN = 80
NEED = PLANE_OFF0 + (PLANES - 1) * PLANE_STEP + PLANE_LEN * 2   # 0x7E4 bytes


_HDR = struct.Struct("<H2xH2xH2xH")                       # id, magic, ~id, ~magic (offsets +4/+8/+0xC/+0x10)
_GRID = struct.Struct("<%dh" % (GRID_ROWS * GRID_COLS))
_PLANES = struct.Struct("<%dh" % ((PLANES - 1) * (PLANE_STEP // 2) + PLANE_LEN))
_U16 = struct.Struct("<H")
_HALF = PLANE_STEP // 2
_ROW_STARTS = tuple(range(0, GRID_ROWS * GRID_COLS, GRID_COLS))
_PLANE_SLICES = tuple((i * _HALF, i * _HALF + PLANE_LEN) for i in range(PLANES))
_TWO_PI = 2 * math.pi
_floor, _sin, _cos = math.floor, math.sin, math.cos


def _i16(F, off, n):
    return struct.unpack_from("<%dh" % n, F, off)


def _centroid(profile, k=2):
    a = profile.index(max(profile))
    lo, hi = max(0, a - k), min(len(profile), a + k + 1)
    seg = profile[lo:hi]
    base = min(seg)
    s = 0
    m = 0
    for i, v in enumerate(seg):
        w = v - base
        if w > 0:
            s += w
            m += (lo + i) * w
    return (m / s) if s else float(a)


def _parabolic(seg):
    k = seg.index(max(seg))
    if 0 < k < len(seg) - 1:
        y0, y1, y2 = seg[k - 1], seg[k], seg[k + 1]
        d = y0 - 2 * y1 + y2
        if d:
            return k + 0.5 * (y0 - y2) / d
    return float(k)


def y_from_pos(pos):
    """Posicion media de los planos (en lineas, con fraccion) -> Y en unidades del eje, con la correccion armonica del sesgo de la parabola."""
    f = pos - _floor(pos)
    w = _TWO_PI * f
    return (Y_A * pos + Y_B + Y_HARM[0] * _sin(w) + Y_HARM[1] * _cos(w)
            + Y_HARM[2] * _sin(2 * w) + Y_HARM[3] * _cos(2 * w))


def parse(F):
    """Devuelve None si F no es un frame de lapiz valido; si no, dict(present, contact, x, y, peak, frame_id)."""
    if len(F) < NEED:
        return None
    fid, magic, nid, nmag = _HDR.unpack_from(F, 4)
    if magic != MAGIC_PEN or nmag != (~magic & 0xFFFF) or nid != (~fid & 0xFFFF):
        return None   # no es un frame de lapiz, o esta leido a medias (complementos de id/magic como en uke-touchd.py)
    g = _GRID.unpack_from(F, GRID_OFF)
    peak = max(g)
    present = peak > PRESENCE_MIN
    contact = _U16.unpack_from(F, CONTACT_OFF)[0] == 16
    out = {"present": present, "contact": contact and present, "peak": peak, "frame_id": fid, "x": None, "y": None}
    if present:
        pos_g = [x if x > 0 else 0 for x in g]                     # parte positiva de la rejilla (una sola pasada)
        rows = [sum(pos_g[r:r + GRID_COLS]) for r in _ROW_STARTS]
        row = _centroid(rows)
        planes = _PLANES.unpack_from(F, PLANE_OFF0)                # los 8 planos de una vez
        tot = 0.0
        for a, b in _PLANE_SLICES:                                  # _parabolic inline (sin llamada ni lista temporal por plano)
            seg = planes[a:b]
            k = seg.index(max(seg))
            if 0 < k < PLANE_LEN - 1:
                y0, y1, y2 = seg[k - 1], seg[k], seg[k + 1]
                d = y0 - 2 * y1 + y2
                tot += (k + 0.5 * (y0 - y2) / d) if d else float(k)
            else:
                tot += float(k)
        pos = tot / PLANES
        out["x"] = int(min(X_MAX, max(0, round(X_A * row + X_B))))
        out["y"] = int(min(Y_MAX, max(0, round(y_from_pos(pos)))))
    return out
