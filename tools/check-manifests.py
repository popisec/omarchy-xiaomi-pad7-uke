#!/usr/bin/env python3
# check-manifests.py — comprueba los MANIFEST.sha256 de los despliegues.
#
# POR QUE. Cada despliegue lleva un manifiesto con el sha256 de lo que instala.
# Es un GATE: si el manifiesto no cuadra, el despliegue no se aplica. Y se
# rompia en silencio: tres .dtso de camaras y cuatro ficheros del harness de
# bt se editaron sin regenerar el manifiesto, y el "check" de esos despliegues
# fallaba sin decir por que.
#
# QUE COMPRUEBA. De cada manifiesto:
#   - las entradas cuyo fichero esta VERSIONADO (las fuentes) tienen que
#     cuadrar: si no, FALLA.
#   - las entradas de ficheros GENERADOS (out/, *.ko, *.dtbo, firmware) no se
#     pueden comprobar en un clon nuevo (se construyen): se cuentan y se
#     informationan, no fallan.
#
# USO:   python3 tools/check-manifests.py [--verbose]
# SALIDA: 0 si todos los manifiestos cuadran, 1 si alguno no.
#
# Para regenerar el manifiesto de un despliegue, mira su deploy.sh (almostos
# todos tienen un 'regen-manifest' o su build.sh lo genera).

import hashlib
import os
import subprocess
import sys

# Ficheros que se construyen y no se versionan: sus entradas no se comprueban.
GENERADOS_SUFIJOS = (
    ".ko", ".o", ".dtbo", ".dtb", ".bin", ".mbn", ".mdt", ".b00", ".b01", ".b02",
    ".b03", ".b04", ".b05", ".b06", ".b07", ".b08", ".b09", ".b10", ".b12",
    ".acdb", ".fsm", ".img", ".cpio.gz",
)
# Un "out/" en cualquier posicion es salida de compilacion (p.ej. topology/out/).
GENERADOS_DIRS = ("out/", "out-hciqca/", "out-ouke5/", "modroot/")


def versionados(repo):
    out = subprocess.run(["git", "ls-files", "-z"], cwd=repo, capture_output=True)
    return {p for p in out.stdout.decode("utf-8", "replace").split("\0") if p}


def es_generado(nombre):
    n = nombre[2:] if nombre.startswith("./") else nombre
    if any(d in n for d in GENERADOS_DIRS):
        return True
    return n.endswith(GENERADOS_SUFIJOS)


def main():
    args = sys.argv[1:]
    verbose = "--verbose" in args
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if "--repo" in args:
        i = args.index("--repo")
        if i + 1 < len(args):
            repo = os.path.abspath(args[i + 1])
    tracked = versionados(repo)

    manifiestos = []
    for dirpath, dirnames, filenames in os.walk(repo):
        dirnames[:] = [d for d in dirnames if d not in (".git", "node_modules", "__pycache__")]
        if "MANIFEST.sha256" in filenames:
            manifiestos.append(os.path.join(dirpath, "MANIFEST.sha256"))

    manifiestos.sort()
    if not manifiestos:
        print("OK: no hay manifiestos que comprobar.")
        return 0

    fallos = 0
    total_fuentes = total_gen = 0
    for man in manifiestos:
        d = os.path.dirname(man)
        rel = os.path.relpath(d, repo)
        mal = []
        gen = 0
        fuentes = 0
        for linea in open(man, encoding="utf-8", errors="replace"):
            linea = linea.rstrip("\n")
            if not linea.strip() or "  " not in linea:
                continue
            esperado, nombre = linea.split("  ", 1)
            # Prefijo "./" se quita como prefijo, NO como conjunto de
            # caracteres: lstrip("./) rompia los dotfiles (.config/x -> config/x).
            if nombre.startswith("./"):
                nombre = nombre[2:]
            if es_generado(nombre):
                gen += 1
                continue
            # Los manifiestos usan rutas relativas al despliegue o a su
            # subcarpeta root/ (segun el despliegue). Se prueba la del
            # despliegue primero y, si no existe, la de root/.
            ruta = os.path.join(rel, nombre)
            if not os.path.exists(os.path.join(repo, ruta)):
                ruta = os.path.join(rel, "root", nombre)
            ruta_abs = os.path.join(repo, ruta)
            if not os.path.exists(ruta_abs):
                # No existe en absoluto. Si su nombre NO parece de artefacto
                # generado (out/, *.ko, firmware), es una FUENTE que se ha
                # borrado: el manifiesto la cita y el repo no la tiene.
                if es_generado(nombre):
                    gen += 1
                else:
                    mal.append((nombre, "NO EXISTE (fuente borrada del repo)"))
                continue
            if ruta not in tracked:
                # EXISTE pero no esta versionado: el manifiesto cita un
                # fichero que el repo no tiene. Eso es un fallo, no un
                # artefacto generado (si lo fuera, no existiria).
                mal.append((nombre, "existe pero NO esta versionado"))
                continue
            got = hashlib.sha256(open(ruta_abs, "rb").read()).hexdigest()
            if got != esperado:
                mal.append((nombre, "sha distinto"))
            else:
                fuentes += 1
        total_fuentes += fuentes
        total_gen += gen
        if mal:
            fallos += 1
            print(f"::error::{rel}/MANIFEST.sha256: {len(mal)} ficheros de FUENTE no cuadran")
            for nombre, motivo in mal:
                print(f"    {motivo}: {nombre}")
        elif verbose:
            print(f"  OK {rel}: {fuentes} fuentes, {gen} generadas")

    print(f"manifiestos: {len(manifiestos)} | ficheros de fuente comprobados: {total_fuentes} | generados (no se comprueban): {total_gen}")
    if fallos:
        print(f"FALLOS: {fallos} manifiestos con fuentes que no cuadran.")
        print("Para regenerarlos: mira el deploy.sh del tema (regen-manifest) o su build.sh.")
        return 1
    print("OK: todos los manifiestos cuadran en sus ficheros de fuente.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
