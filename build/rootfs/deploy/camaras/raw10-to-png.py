#!/usr/bin/env python3
"""raw10-to-png.py -- vista previa de un frame RAW10 MIPI empaquetado (SGRBG10, 5 bytes = 4 pixeles) de la camara trasera de la uke.
Uso: raw10-to-png.py frame.raw salida.png [ancho=2104] [alto=1560] [stride_bytes=2640]
Binning 2x2 (mitad de resolucion, sin demosaico fino), sin balance de blancos: solo para comprobar que la imagen es una imagen."""
import sys
import numpy as np
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
w = int(sys.argv[3]) if len(sys.argv) > 3 else 2104
h = int(sys.argv[4]) if len(sys.argv) > 4 else 1560
stride = int(sys.argv[5]) if len(sys.argv) > 5 else 2640
a = np.fromfile(src, dtype=np.uint8)
assert a.size >= stride * h, "fichero corto: %d < %d" % (a.size, stride * h)
a = a[:stride * h].reshape(h, stride)
g = a[:, :(w // 4) * 5].reshape(h, w // 4, 5).astype(np.uint16)
px = np.empty((h, w // 4, 4), np.uint16)
for k in range(4):
    px[:, :, k] = (g[:, :, k] << 2) | ((g[:, :, 4] >> (2 * k)) & 3)
raw = px.reshape(h, w)                      # 10 bits
print("min/max/media:", raw.min(), raw.max(), round(float(raw.mean()), 1))
r = raw[0::2, 1::2]; b = raw[1::2, 0::2]
gg = (raw[0::2, 0::2].astype(np.uint32) + raw[1::2, 1::2]) // 2
rgb = np.stack([r, gg.astype(np.uint16), b], axis=-1).astype(np.float32)
lo, hi = np.percentile(rgb, 1), np.percentile(rgb, 99)
rgb = np.clip((rgb - lo) / max(hi - lo, 1) * 255, 0, 255).astype(np.uint8)
Image.fromarray(rgb).save(dst)
print("escrito", dst, rgb.shape)
