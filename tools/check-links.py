#!/usr/bin/env python3
# check-links.py — comprueba que las referencias a ficheros del repo existen.
#
# Por que: el corpus son miles de lineas que citan "fichero:linea" de otros
# ficheros. Al mover o renombrar algo, esas citas se quedan obsoletas en
# silencio. Este script las revisa y falla si apunta a algo que no existe.
#
# Uso:  python3 tools/check-links.py [--repo RAIZ] [--max N]
# Salida: 0 si todo cuadra, 1 si hay referencias rotas.
#
# Lo que NO se comprueba (y por que):
#   - Rutas del entorno del autor: ~/proyectos/..., /home/..., bin/... de
#     proyectos hermanos. No viven en este repo.
#   - Rutas de sistema (/etc, /usr, /proc, /sys, /dev, /boot...).
#   - Ficheros que el proyecto genera en la tablet (artefactos, .ko, imagenes).
#   - URLs.

import argparse
import os
import re
import subprocess
import sys

# Directorios del repo que se consideran "propios" (todo lo demas se ignora).
RAIZES_PROPIAS = {
    "build", "charge", "docs", "tools", ".github",
}

# Prefijos que son externos al repo: no se comprueban.
EXTERNOS = (
    "~/", "/home/", "/etc/", "/usr/", "/proc/", "/sys/", "/dev/", "/boot/",
    "/tmp/", "/var/", "/root/", "http://", "https://", "git@", "ssh ",
)

# Ficheros que se generan y no se versionan.
GENERADOS = (
    ".ko", ".img", ".bin", ".elf", ".mbn", ".mdt", ".acdb", ".fsm",
    ".dtb", ".dtbo", ".raw", ".dng", ".log", ".img.gz", ".tar.gz",
)

# Referencia: un camino con al menos una extension, en backticks o suelto.
# Extensiones que se consideran "un fichero citado". Sin esta lista, cualquier
# cadena con punto parece un fichero: las versiones ("0.3.2.r7"), los rangos
# ("0..N") y las fechas ("-20261005") se leian como referencias.
EXT_CITABLES = (
    "md", "txt", "sh", "py", "c", "h", "m4", "diff", "patch", "conf", "cfg",
    "config", "dts", "dtsi", "dtso", "qml", "lua", "json", "yaml", "yml",
    "toml", "xml", "rules", "service", "timer", "socket", "target", "desktop",
    "svg", "png", "jpg", "jpeg", "gif", "webp", "pdf", "tsv", "csv", "log",
    "out", "list", "in", "srs", "cmake", "mk", "spec", "ini",
)

_PATRON_REF = (
    r"(?<![\w/.-])"                                     # no dentro de otra palabra
    r"(?P<path>(?![-.])(?:[A-Za-z0-9_][A-Za-z0-9._-]*/)*"   # subdirectorios
    r"(?![-.])(?:[A-Za-z0-9_][A-Za-z0-9._-]*\.(?:" + "|".join(EXT_CITABLES) + r")))"
    r"(?::[\d,\-]+)?"                                    # :linea opcional
    r"(?![\w/])"
)
RE_REF = re.compile(_PATRON_REF)

# Ignorar lo que parece codigo, no una referencia.
RE_CODIGO = re.compile(r"^\s{4,}")


def ficheros_texto(repo):
    """(ruta relativa, ruta absoluta) de todos los ficheros de texto del repo."""
    for dirpath, dirnames, filenames in os.walk(repo):
        dirnames[:] = [d for d in dirnames if d not in (".git", "node_modules", "__pycache__")]
        for f in filenames:
            p = os.path.join(dirpath, f)
            if not os.path.islink(p) and os.path.isfile(p):
                yield os.path.relpath(p, repo), p


def referencias(texto):
    """Devuelve las rutas citadas en el texto."""
    for linea in texto.splitlines():
        if RE_CODIGO.match(linea):
            continue
        for m in RE_REF.finditer(linea):
            yield m.group("path")


def ignorados_por_git(repo, paths):
    """Devuelve el conjunto de rutas que cae bajo una regla del .gitignore.

    Se hace UNA llamada con --stdin y no una por ruta: con ~28.000 referencias,
    lanzar un git check-ignore por cada una costaba 165 s (28.000 forks).

    CUIDADO: `git check-ignore` aborta con error 128 si ALGUNA ruta se sale del
    repositorio (p.ej. "../README.md"), y entonces no imprime ninguna: el lote
    entero se pierde. Por eso se filtran las rutas que no pueden estar dentro, y
    si aun asi falla, se repliega a consultarlas de una en una."""
    dentro = [p for p in paths if p and not p.startswith("..") and not os.path.isabs(p)]
    fuera = set(paths) - set(dentro)
    if not dentro:
        return set()
    try:
        r = subprocess.run(["git", "check-ignore", "--no-index", "--stdin", "-z"],
                           cwd=repo, input=("\0".join(sorted(dentro)) + "\0").encode(),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError:
        return set()
    if r.returncode == 0 or r.stdout:
        return {x.decode("utf-8", "replace") for x in r.stdout.split(b"\0") if x} | fuera
    # El lote fallo: se consulta de una en una (lento, pero no pierde nada).
    out = set(fuera)
    for p in dentro:
        try:
            rr = subprocess.run(["git", "check-ignore", "-q", "--no-index", p],
                                cwd=repo, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if rr.returncode == 0:
                out.add(p)
        except OSError:
            pass
    return out


def es_externa_sin_git(path):
    """Lo que se puede decidir sin preguntar al .gitignore."""
    if path.startswith(EXTERNOS):
        return True
    if os.path.isabs(path):
        return True
    if path.endswith(GENERADOS):
        return True
    # Solo se comprueban las rutas que viven dentro del repo. Un fichero SIN
    # "/" es de la raiz del repo (o del directorio del documento) y tiene que
    # existir: antes, los .md de la raiz nunca se comprobaban y sus
    # referencias rotas pasaban desapercibidas.
    if "/" not in path:
        return False
    raiz = path.split("/")[0]
    return raiz not in RAIZES_PROPIAS and not os.path.exists(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--max", type=int, default=40, help="maximo de referencias a listar")
    ap.add_argument("--baseline", default=None,
                    help="fichero con las referencias rotas ya conocidas; solo se fallan las nuevas")
    ap.add_argument("--update-baseline", action="store_true",
                    help="reescribe el baseline con las referencias rotas actuales")
    args = ap.parse_args()
    repo = os.path.abspath(args.repo)
    baseline_path = args.baseline or os.path.join(repo, "tools", "link-baseline.txt")

    # Solo los ficheros VERSIONADOS: en local hay arboles sin versionar (el
    # del kernel, que pesa GB) que resolverian referencias que en un clon
    # limpio NO existen, y el check daria verde donde la CI falla.
    mds = []
    try:
        out = subprocess.run(["git", "ls-files", "-z", "*.md"], cwd=repo,
                              capture_output=True, timeout=120)
        if out.returncode == 0 and out.stdout:
            mds = [os.path.join(repo, p) for p in
                    out.stdout.decode("utf-8", "replace").split("\0") if p]
    except Exception:
        mds = []
    if not mds:
        for dirpath, dirnames, filenames in os.walk(repo):
            dirnames[:] = [d for d in dirnames if d not in (".git", "node_modules", "__pycache__")]
            for f in filenames:
                if f.endswith(".md"):
                    mds.append(os.path.join(dirpath, f))
    mds.sort()

    # Primera pasada: reunir todas las referencias y cuales serian candidatas a
    # comprobar (las que el .gitignore no excluye, que no se publican).
    refs_por_fichero = {}
    candidatas = set()
    total = 0
    for md in mds:
        rel = os.path.relpath(md, repo)
        try:
            texto = open(md, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for path in referencias(texto):
            total += 1
            refs_por_fichero.setdefault(md, []).append(path)
            if not es_externa_sin_git(path):
                candidatas.add(path)

    ignorados = ignorados_por_git(repo, sorted(candidatas))
    # Todos los nombres de fichero del repo, para resolver las referencias
    # ambiguas por nombre simple.
    nombres_en_el_repo = set()
    for _, p in ficheros_texto(repo):
        nombres_en_el_repo.add(os.path.basename(p))

    # Segunda pasada: decidir cuales quedan rotas.
    rotas = {}
    for md, paths in refs_por_fichero.items():
        rel = os.path.relpath(md, repo)
        for path in paths:
            if es_externa_sin_git(path):
                continue
            if path in ignorados:
                continue
            # Probar la ruta tal cual y relativa al directorio del documento.
            candidatos = [os.path.join(repo, path),
                          os.path.join(os.path.dirname(md), path)]
            if any(os.path.exists(c) for c in candidatos):
                continue
            # Una referencia por NOMBRE SIMPLE a un fichero que vive en un
            # subdirectorio es ambigua pero localizable: no esta rota.
            if "/" not in path and path in nombres_en_el_repo:
                continue
            rotas.setdefault(path, []).append(rel)

    print(f"referencias comprobadas: {total} en {len(mds)} ficheros .md")

    # Baseline: referencias rotas que ya se sabian (ficheros que solo viven en
    # el repo privado). Solo se falla por referencias NUEVAS, que si son un
    # error de quien acaba de mover o renombrar algo.
    conocidos = set()
    if os.path.exists(baseline_path) and not args.update_baseline:
        with open(baseline_path, encoding="utf-8") as f:
            conocidos = {l.strip() for l in f if l.strip() and not l.startswith("#")}

    nuevas = {p: w for p, w in rotas.items() if p not in conocidos}

    if args.update_baseline:
        with open(baseline_path, "w", encoding="utf-8") as f:
            f.write("# Referencias rotas conocidas: ficheros que se citan pero no se\n"
                    "# publican (viven solo en el repo privado del autor).\n"
                    "# Regenerar: python3 tools/check-links.py --update-baseline\n")
            for p in sorted(rotas):
                f.write(p + "\n")
        print(f"baseline escrito: {baseline_path} ({len(rotas)} rutas)")
        return 0

    if not nuevas:
        extra = f" ({len(rotas)} conocidas, en el baseline)" if rotas else ""
        print(f"OK: ninguna referencia rota nueva{extra}.")
        return 0

    print(f"referencias rotas nuevas: {len(nuevas)}\n")
    for path, donde in sorted(nuevas.items())[:args.max]:
        print(f"  {path}")
        for d in donde[:3]:
            print(f"      citado en {d}")
    if len(nuevas) > args.max:
        print(f"  ... y {len(nuevas) - args.max} mas")
    if rotas:
        print(f"\n({len(rotas) - len(nuevas)} referencias rotas conocidas ya listadas en el baseline.)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
