#!/usr/bin/env python3
"""raw-develop.py -- revelado de calidad de los RAW10 MIPI (SGRBG10) de la trasera de la uke (OV13B10). 22-oct-2026, ciclo 20. Solo numpy + PIL.
Uso: raw-develop.py salida.png entrada.raw [entrada2.raw ...] [--w 2104 --h 1560] [--stride N] [--lsc 0.55] [--ccm generic|none] [--nr 1.0] [--rot 0]
- Varias entradas (o un fichero con N frames seguidos) se PROMEDIAN (rafaga: el ruido baja con sqrt(N)).
- Cadena: desempaquetado -> nivel de negro 64 -> sombreado de lente radial (APROXIMADO, sin la tabla LSC del tuning de Android)
  -> balance de blancos gris en tonos medios (sin saturados ni negros) -> demosaico Malvar-He-Cutler (gradiente corregido)
  -> CCM generica de sensor OmniVision (APROXIMADA, sin la CCM del tuning) -> ruido: crominancia fuerte + luminancia suave
  -> curva sRGB + contraste suave -> mascara de enfoque en luminancia.
Las partes marcadas APROXIMADO son estimaciones razonables, no calibracion del modulo OFILM."""
import argparse
import numpy as np
from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument("out"); ap.add_argument("inp", nargs="+")
ap.add_argument("--w", type=int, default=2104); ap.add_argument("--h", type=int, default=1560); ap.add_argument("--stride", type=int, default=0)
ap.add_argument("--lsc", type=float, default=0.55, help="ganancia extra en la esquina (r=1): 1+lsc*r^2 (APROXIMADO)")
ap.add_argument("--ccm", default="generic"); ap.add_argument("--nr", type=float, default=1.0); ap.add_argument("--rot", type=int, default=0)
ap.add_argument("--wb", default="", help="ganancias R,G,B fijas (por defecto: gris en tonos medios)")
a = ap.parse_args()
W, H = a.w, a.h
ST = a.stride or {2104: 2640, 4208: 5264}.get(W, W * 10 // 8)
FR = ST * H


def unpack(buf):
    x = np.frombuffer(buf, np.uint8)[:FR].reshape(H, ST)[:, :W // 4 * 5].reshape(H, W // 4, 5).astype(np.uint16)
    p = np.empty((H, W // 4, 4), np.uint16)
    for k in range(4):
        p[:, :, k] = (x[:, :, k] << 2) | ((x[:, :, 4] >> (2 * k)) & 3)
    return p.reshape(H, W).astype(np.float32)


acc, n = np.zeros((H, W), np.float32), 0
for f in a.inp:
    d = open(f, "rb").read()
    for i in range(len(d) // FR):
        acc += unpack(d[i * FR:(i + 1) * FR]); n += 1
assert n, "ningun frame completo"
raw = np.clip((acc / n - 64.0) / (1023.0 - 64.0), 0, None)
print("frames promediados:", n, " media lineal:", round(float(raw.mean()), 4))
sat = (acc / n) >= 1000

# sombreado de lente radial (APROXIMADO)
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
r2 = ((xx - W / 2) ** 2 + (yy - H / 2) ** 2) / ((W / 2) ** 2 + (H / 2) ** 2)
raw *= 1 + a.lsc * r2

# mascaras de Bayer GRBG: fila par G R, fila impar B G
R = np.zeros((H, W), bool); R[0::2, 1::2] = True
B = np.zeros((H, W), bool); B[1::2, 0::2] = True
G = ~(R | B)

# balance de blancos: gris en tonos medios
if a.wb:
    g = [float(v) for v in a.wb.split(",")]
else:
    # superpixeles 2x2 (Gr R / B Gb): la mascara de tonos medios se decide por bloque, no por pixel (si no, los umbrales sesgan R/B)
    sr, sgr, sb, sgb = raw[0::2, 1::2], raw[0::2, 0::2], raw[1::2, 0::2], raw[1::2, 1::2]
    sg = (sgr + sgb) / 2
    lum = (sr + 2 * sg + sb) / 4
    ss = sat[0::2, 0::2] | sat[0::2, 1::2] | sat[1::2, 0::2] | sat[1::2, 1::2]
    ok = (lum > np.percentile(lum, 20)) & (lum < np.percentile(lum, 97)) & ~ss
    rm, gm, bm = sr[ok].mean(), sg[ok].mean(), sb[ok].mean()
    g = [gm / rm, 1.0, gm / bm]
print("ganancias WB R,G,B:", [round(v, 3) for v in g])
raw = raw * np.where(R, g[0], np.where(B, g[2], g[1]))
# altas luces: tras el WB se recorta todo a 1,0 (el blanco del sensor) y lo saturado se fuerza a gris neutro (si no, R/B escalados -> magenta)
raw = np.minimum(raw, 1.0)


def conv(img, taps):  # taps: {(dy,dx): w}
    p = np.pad(img, 2, mode="reflect")
    out = np.zeros_like(img)
    for (dy, dx), w in taps.items():
        out += w * p[2 + dy:2 + dy + H, 2 + dx:2 + dx + W]
    return out


def k(rows):  # 5x5 en octavos -> taps
    t = {}
    for y, row in enumerate(rows):
        for x, v in enumerate(row):
            if v:
                t[(y - 2, x - 2)] = v / 8.0
    return t


# Malvar-He-Cutler (2004)
G_at_RB = k([[0, 0, -1, 0, 0], [0, 0, 2, 0, 0], [-1, 2, 4, 2, -1], [0, 0, 2, 0, 0], [0, 0, -1, 0, 0]])
RB_at_G_rowR = k([[0, 0, .5, 0, 0], [0, -1, 0, -1, 0], [-1, 4, 5, 4, -1], [0, -1, 0, -1, 0], [0, 0, .5, 0, 0]])  # vecinos en la fila
RB_at_G_colR = k([[0, 0, -1, 0, 0], [0, -1, 4, -1, 0], [.5, 0, 5, 0, .5], [0, -1, 4, -1, 0], [0, 0, -1, 0, 0]])  # vecinos en la columna
RB_at_BR = k([[0, 0, -1.5, 0, 0], [0, 2, 0, 2, 0], [-1.5, 0, 6, 0, -1.5], [0, 2, 0, 2, 0], [0, 0, -1.5, 0, 0]])
cG, cRow, cCol, cDiag = conv(raw, G_at_RB), conv(raw, RB_at_G_rowR), conv(raw, RB_at_G_colR), conv(raw, RB_at_BR)
Gr = np.zeros((H, W), bool); Gr[0::2, 0::2] = True   # G en fila de R
Gb = np.zeros((H, W), bool); Gb[1::2, 1::2] = True   # G en fila de B
r = np.where(R, raw, np.where(Gr, cRow, np.where(Gb, cCol, cDiag)))
gch = np.where(G, raw, cG)
b = np.where(B, raw, np.where(Gb, cRow, np.where(Gr, cCol, cDiag)))
rgb = np.clip(np.stack([r, gch, b], -1), 0, None)
hl = np.clip((rgb.min(-1) - 0.85) / 0.15, 0, 1)[..., None]   # cerca del blanco: mezclar con el maximo (sin dominante)
rgb = rgb * (1 - hl) + rgb.max(-1, keepdims=True) * hl

# CCM generica (APROXIMADA; filas suman 1 para no mover el blanco)
if a.ccm == "generic":
    M = np.array([[1.62, -0.45, -0.17], [-0.28, 1.52, -0.24], [-0.05, -0.62, 1.67]], np.float32)
    rgb = np.clip(rgb @ M.T, 0, None)

# exposicion: el percentil 99 de la luminancia a 0,92 (sin pasarse del maximo lineal)
Y = rgb @ np.array([.2126, .7152, .0722], np.float32)
rgb *= min(0.92 / max(np.percentile(Y, 99), 1e-4), 64.0)


def blur(img, s):  # gaussiana aproximada: 3 cajas separables
    if s <= 0:
        return img
    rad = max(1, int(round(s)))
    out = img
    for _ in range(3):
        for ax in (0, 1):
            c = np.cumsum(np.pad(out, [(rad + 1, rad) if i == ax else (0, 0) for i in range(out.ndim)], mode="edge"), axis=ax)
            sl_hi = [slice(None)] * out.ndim; sl_lo = [slice(None)] * out.ndim
            sl_hi[ax] = slice(2 * rad + 1, None); sl_lo[ax] = slice(0, -(2 * rad + 1))
            out = (c[tuple(sl_hi)] - c[tuple(sl_lo)]) / (2 * rad + 1)
    return out


# ruido: YCbCr, crominancia fuerte, luminancia suave
Y = rgb @ np.array([.299, .587, .114], np.float32)
Cb, Cr = rgb[..., 2] - Y, rgb[..., 0] - Y
Cb, Cr = blur(Cb, 3 * a.nr), blur(Cr, 3 * a.nr)
Ys = blur(Y, 0.8 * a.nr)
edge = np.abs(Y - blur(Y, 2))
wgt = np.clip(edge / (np.percentile(edge, 90) + 1e-6), 0, 1)   # en bordes conserva el detalle
Y = wgt * Y + (1 - wgt) * Ys
# enfoque (mascara) en luminancia
Y = Y + 0.6 * (Y - blur(Y, 1.5))
rgb = np.stack([Y + Cr, Y - 0.299 / 0.587 * Cr - 0.114 / 0.587 * Cb, Y + Cb], -1)
rgb = np.clip(rgb, 0, 1)
srgb = np.where(rgb <= 0.0031308, 12.92 * rgb, 1.055 * np.power(rgb, 1 / 2.4) - 0.055)
srgb = srgb + 0.08 * (srgb - 0.5) * (1 - np.abs(2 * srgb - 1))          # contraste suave
im = Image.fromarray((np.clip(srgb, 0, 1) * 255 + 0.5).astype(np.uint8))
if a.rot:
    im = im.rotate(-a.rot, expand=True)
im.save(a.out)
print("escrito", a.out, im.size)
