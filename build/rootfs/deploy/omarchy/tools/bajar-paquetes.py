#!/usr/bin/env python3
# bajar-paquetes.py — baja los 342 paquetes de la capa de Omarchy y verifica
# su sha256 contra el manifiesto.
#
# POR QUE. build/rootfs/deploy/omarchy/ instala la capa de escritorio de
# Omarchy (Hyprland, Quickshell, la shell, sus dotfiles). Los 342 .pkg.tar.xz
# NO se versionan: pesan y son de Arch. Lo que si se versiona es el manifiesto
# (instalar.tsv) con el nombre, la version, el tamano y el sha256 de cada uno.
# Este script convierte ese manifiesto en los ficheros.
#
# DE DONDE, Y QUE SE ESPERA. De dos repos: el de Omarchy para aarch64
# (pkgs.omarchy.org) y el edge de Arch Linux ARM. Cada paquete se pide por su
# nombre EXACTO y se comprueba su sha256 contra el manifiesto.
#
# OJO, UN MATIZ IMPORTANTE. La capa esta fijada a las versiones que habia en
# el edge de ALARM cuando se monto (adwaita-cursors 50.0-1, sddm 0.21.0-7,
# libxxf86vm 1.1.7-1...). Esos repositorios SOLO guardan la ultima version de
# cada paquete, asi que la mayoria de los 342 ya NO estan ahi: al pedir el
# nombre exacto dan 404. En una muestra de 25, ninguno estaba.
#
# Por eso este script es una AYUDA, no la via principal: con el stage del autor
# (build/rootfs/deploy/omarchy/stage, que no se publica) o con un snapshot
# del repo, funciona. Si lo que quieres es la lista, `--listar` la da sin
# tocar la red.
#
# USO:
#   python3 build/rootfs/deploy/omarchy/tools/bajar-paquetes.py [--dest DIR]
#                                                    [--solo PAQUETE]
#                                                    [--verificar] [--listar]
#
#   --dest DIR    donde se dejan los .pkg (por defecto build/rootfs/deploy/omarchy/stage)
#   --solo NOM    solo ese paquete (para probar uno)
#   --verificar   solo comprueba los que ya estan (no descarga)
#   --listar      lista lo que falta y su tamano, y sale
#
# QUE COMPRUEBA: el sha256 de cada .pkg descargado contra el del manifiesto. Si
# no coincide, lo borra y falla: un paquete con otro hash no se instala.
import argparse
import hashlib
import os
import sys
import urllib.error
import urllib.request

# Los 342 paquetes vienen de DOS repos:
#   - los de Omarchy (tier2, 120), en su propio repo para aarch64
#   - los de la base (tier1, 222), del repo edge de Arch Linux ARM
# Los dos se prueban para cada paquete; el que acierte es el que lo tiene.
BASES = (
    "https://pkgs.omarchy.org/edge/aarch64",
    "http://mirror.archlinuxarm.org/edge/os/aarch64",
)

def _raiz_del_repo():
    """La raiz del repo: se sube hasta el directorio con .git."""
    d = os.path.dirname(os.path.abspath(__file__))
    while d != "/" and not os.path.isdir(os.path.join(d, ".git")):
        d = os.path.dirname(d)
    return d


R = _raiz_del_repo()
MANIFEST = os.path.join(R, "build", "rootfs", "deploy", "omarchy", "manifest", "instalar.tsv")


def leer_manifiesto():
    """(nombre_fichero, sha256) de cada paquete del manifiesto."""
    out = []
    with open(MANIFEST, encoding="utf-8") as f:
        for i, linea in enumerate(f):
            if i == 0 or not linea.strip():
                continue
            campos = linea.rstrip("\n").split("\t")
            if len(campos) < 9:
                continue
            out.append((campos[2], campos[8]))  # fichero, sha256
    return out


def sha256_de(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for bloque in iter(lambda: f.read(1 << 20), b""):
            h.update(bloque)
    return h.hexdigest()


def bajar(url, destino):
    tmp = destino + ".parcial"
    with urllib.request.urlopen(url, timeout=120) as r, open(tmp, "wb") as f:
        while True:
            bloque = r.read(1 << 20)
            if not bloque:
                break
            f.write(bloque)
    os.replace(tmp, destino)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dest", default=os.path.join(R, "build", "rootfs", "deploy", "omarchy", "stage"))
    ap.add_argument("--solo", default=None)
    ap.add_argument("--verificar", action="store_true")
    ap.add_argument("--listar", action="store_true")
    args = ap.parse_args()

    if not os.path.exists(MANIFEST):
        print(f"falta el manifiesto {MANIFEST}", file=sys.stderr)
        return 2
    paquetes = leer_manifiesto()
    if args.solo:
        paquetes = [p for p in paquetes if args.solo in p[0]]
    os.makedirs(args.dest, exist_ok=True)

    faltan = []
    ya = 0
    for nombre, esperado in paquetes:
        dest = os.path.join(args.dest, nombre)
        if os.path.exists(dest):
            if sha256_de(dest) == esperado:
                ya += 1
                continue
            print(f"  {nombre}: el sha NO casa; se borra y se vuelve a bajar")
            os.remove(dest)
        faltan.append((nombre, esperado, dest))

    if args.listar:
        print(f"paquetes en el manifiesto: {len(paquetes)} | ya descargados y verificados: {ya} | faltan: {len(faltan)}")
        for nombre, _, _ in faltan:
            print(f"  {nombre}")
        return 0

    if args.verificar:
        print(f"verificados: {ya} | faltan: {len(faltan)}")
        return 0 if not faltan else 1

    fallos = 0
    for i, (nombre, esperado, dest) in enumerate(faltan, 1):
        ok = False
        for base in BASES:
            try:
                bajar(f"{base}/{nombre}", dest)
            except (urllib.error.URLError, urllib.error.HTTPError, OSError) as e:
                print(f"  [{i}/{len(faltan)}] {nombre}: no se pudo bajar de {base} ({e})")
                continue
            got = sha256_de(dest)
            if got == esperado:
                print(f"  [{i}/{len(faltan)}] {nombre}: OK")
                ok = True
                break
            print(f"  [{i}/{len(faltan)}] {nombre}: sha distinto ({got[:12]} != {esperado[:12]}); se borra")
            os.remove(dest)
        if not ok:
            fallos += 1

    print(f"\ndescargados: {len(faltan) - fallos} | fallidos: {fallos} | ya verificados: {ya}")
    print(f"destino: {args.dest}")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
