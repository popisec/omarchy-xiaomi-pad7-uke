#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
mk-dtbo-touchfix.py — construye un CANDIDATO de dtbo con el fix del táctil
(fragmentos de touch-fix.dts) a partir del dtbo que está en la tablet.

QUÉ HACE (mismo método que el constructor del proyecto, ver
INFORME-GPIO-EINVAL.md §5: descompilar payload -> insertar fragmento antes del
último `};` -> recompilar -> gate fdtoverlay -> empaquetar dt_table):

  1. Extrae el payload del .img de entrada (default: s258-panel-gpio2.img).
  2. dtc -I dtb -O dts -> payload.dts; inserta touch-fix.dts antes del último `};`.
  3. dtc -I dts -O dtb -> payload-fix.dtb.
  4. Gate 1: fdtoverlay -i base-dtb.img -o fused.dtb payload-fix.dtb (rc=0).
  5. Gate 2 (fdtget sobre el fusionado): novatek@0 con interrupts=<0x36 0x01>,
     interrupt-parent=<0x16b>, touchscreen-size 0x858/0xc80; touchscreen@0
     disabled; el controlador SPI sigue con compatible qcom,geni-spi.
  6. Empaqueta la imagen dt_table (magic 0xd7b7ab1e, 1 entrada) y verifica el
     roundtrip con dtbo-extract.py + el límite de dtbo_b (610304 B).

NO FLASHEA NADA. El candidato queda en candidato/ para que el orquestador lo
meta por el protocolo de siempre (sha + slot bueno + rollback). Vía sin flash:
el .ko ext de ../ext/ (no necesita este dtbo).
"""
import hashlib
import os
import re
import struct
import subprocess
import sys

def _repo_root():
    """Raiz del repo: se sube hasta el directorio con .git, para que el script
    funcione recien clonado y no dependa de donde este el arbol."""
    d = os.path.dirname(os.path.abspath(__file__))
    while d != "/" and not os.path.isdir(os.path.join(d, ".git")):
        d = os.path.dirname(d)
    return d


R = _repo_root()


HERE = os.path.dirname(os.path.abspath(__file__))
PREP = os.path.dirname(HERE)
ROOT = R
BOOTIMG = os.path.join(ROOT, "build", "bootimg")
DTBO_EXTRACT = os.path.join(BOOTIMG, "dtbo-extract.py")
BASE_DTB = "~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img"
IN_IMG = os.path.join(BOOTIMG, "s258-panel-gpio2.img")
FRAGMENT = os.path.join(HERE, "touch-fix.dts")
OUT_DIR = os.path.join(PREP, "candidato")
MAX_DTBO = 610304
PY = "/usr/bin/python3"  # NO sys.executable: dentro de ZCode es el AppImage (leccion 28-sep)
SPI = "/soc/qcom,qupv3_0_geni_se@ac0000/spi@a90000"


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def die(msg):
    print("FALLO:", msg)
    sys.exit(1)


def ok(msg):
    print("  OK  ", msg)


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def fdtget(dtb, node, prop, tipo="x"):
    r = run(["fdtget", "-t", tipo, dtb, node, prop])
    if r.returncode:
        return None
    return r.stdout.strip()


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    # --- 1. payload ---------------------------------------------------------
    payload = os.path.join(OUT_DIR, "s258-payload.dtb")
    r = run([PY, DTBO_EXTRACT, IN_IMG, payload])
    if r.returncode:
        die("dtbo-extract: %s%s" % (r.stdout, r.stderr))
    ok("payload extraído (%d B), sha %s" % (os.path.getsize(payload), sha(payload)[:16]))

    # --- 2. insertar el fragmento ------------------------------------------
    dts = os.path.join(OUT_DIR, "s258-payload.dts")
    r = run(["dtc", "-I", "dtb", "-O", "dts", "-o", dts, payload])
    if r.returncode:
        die("dtc -I dtb: %s" % r.stderr)
    text = open(dts).read()
    m = re.search(r"\n\};\s*$", text)
    if not m:
        die("no encuentro el `};` final del payload")
    frag = open(FRAGMENT).read()
    new = text[:m.start()] + "\n" + frag + text[m.start():]
    dts2 = os.path.join(OUT_DIR, "s258-payload-touchfix.dts")
    open(dts2, "w").write(new)
    ok("fragmento insertado antes del `};` final")

    # --- 3. recompilar ------------------------------------------------------
    dtb2 = os.path.join(OUT_DIR, "s258-payload-touchfix.dtb")
    r = run(["dtc", "-I", "dts", "-O", "dtb", "-o", dtb2, dts2])
    if r.returncode:
        die("dtc -I dts: %s" % r.stderr)
    ok("payload recompilado (%d B)" % os.path.getsize(dtb2))

    # --- 4. gate fdtoverlay -------------------------------------------------
    fused = os.path.join(OUT_DIR, "s258-fused-touchfix.dtb")
    r = run(["fdtoverlay", "-i", BASE_DTB, "-o", fused, dtb2])
    if r.returncode:
        die("fdtoverlay: %s%s" % (r.stdout, r.stderr))
    ok("fdtoverlay rc=0 (fusionado %d B)" % os.path.getsize(fused))

    # --- 5. gates de contenido ---------------------------------------------
    checks = [
        ("novatek@0 interrupts", fdtget(fused, SPI + "/novatek@0", "interrupts"), "36 1"),
        ("novatek@0 interrupt-parent", fdtget(fused, SPI + "/novatek@0", "interrupt-parent"), "16b"),
        ("novatek@0 touchscreen-size-x", fdtget(fused, SPI + "/novatek@0", "touchscreen-size-x"), "858"),
        ("novatek@0 touchscreen-size-y", fdtget(fused, SPI + "/novatek@0", "touchscreen-size-y"), "c80"),
        ("novatek@0 status", fdtget(fused, SPI + "/novatek@0", "status", "s"), "ok"),
        ("touchscreen@0 status", fdtget(fused, SPI + "/touchscreen@0", "status", "s"), "disabled"),
        ("spi compatible", fdtget(fused, SPI, "compatible", "s"), "qcom,geni-spi"),
        ("spi status", fdtget(fused, SPI, "status", "s"), "okay"),
    ]
    malos = 0
    for nombre, val, esperado in checks:
        if val != esperado:
            print("  GATE ROJO: %s = %r (esperado %r)" % (nombre, val, esperado))
            malos += 1
        else:
            ok("%s = %r" % (nombre, val))
    if malos:
        die("%d gates rojos; NO se empaqueta" % malos)

    # --- 6. empaquetar dt_table --------------------------------------------
    pay = open(dtb2, "rb").read()
    img = (struct.pack(">IIIIIIII", 0xD7B7AB1E, 64 + len(pay), 32, 32, 1, 32, 4096, 0)
           + struct.pack(">IIIIIIII", len(pay), 64, 0, 0, 0, 0, 0, 0) + pay)
    if len(img) > MAX_DTBO:
        die("no cabe en dtbo_b: %d > %d" % (len(img), MAX_DTBO))
    out_img = os.path.join(OUT_DIR, "touchfix-s259-candidato.img")
    open(out_img, "wb").write(img)
    ok("imagen %s (%d B, margen %d B sobre dtbo_b)"
       % (os.path.basename(out_img), len(img), MAX_DTBO - len(img)))

    # roundtrip
    rt = os.path.join(OUT_DIR, "roundtrip.dtb")
    r = run([PY, DTBO_EXTRACT, out_img, rt])
    if r.returncode:
        die("roundtrip: %s" % (r.stdout + r.stderr))
    if open(rt, "rb").read() != pay:
        die("roundtrip byte a byte FALLA")
    ok("roundtrip byte a byte del payload")

    print()
    print("sha256 %s  %s" % (sha(out_img), out_img))
    print("sha256 %s  (payload)" % sha(dtb2))
    print()
    print("NO FLASHEADO. Protocolo: leer PRE-REGISTRO/rollback ANTES de tocar dtbo_b.")


if __name__ == "__main__":
    main()
