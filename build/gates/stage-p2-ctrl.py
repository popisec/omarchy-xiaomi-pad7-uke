#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
stage-p2-ctrl.py — calcula y descarga el conjunto MÍNIMO de paquetes aarch64
necesarios para que P2-ctrl (la sonda de pantalla a 0 escrituras) sea ejecutable,
y deja escrito el procedimiento de instalación.

POR QUÉ ESTE SCRIPT (1-oct-2026). El plan v4 manda hacer P2-ctrl como primer test
de pantalla (0 flashes) y lo da por hecho, pero:
  - `modetest` NO está en el rootfs que hay en la tablet (debugfs sobre
    build/rootfs/arch-rootfs.img: 6540 entradas en /usr/bin, 0 coincidencias);
  - build/pkg/ no tiene mesa/libdrm/mesa-utils (lo verificó C8 en su día);
  - y el canal que citaba el plan ("A1-auditoria-instalador §4 / v2 P3.5")
    NO EXISTE: no hay ningún fichero A1 en este proyecto ni en el hermano.
O sea: el paso 1 del plan no se podía ejecutar y el procedimiento no estaba escrito.
Este script lo baja del repo real de Arch Linux ARM, resuelve el grafo de
dependencias de verdad (leyendo las bases de datos de paquetes, no de memoria) y
deja los .pkg en build/pkg/staging-p2-ctrl/ con un MANIFIEST y el comando exacto
de instalación.

Uso:
  stage-p2-ctrl.py --list                 # solo el grafo, no descarga
  stage-p2-ctrl.py --download             # calcula y descarga
  stage-p2-ctrl.py --verify               # sha256 de lo descargado vs manifiesto

INSTALACIÓN en la tablet (sin WiFi, por el enlace NCM-USB; ver
build/gates/prepara/A1-auditoria-instalador.md §4 para las IP:
PC 192.168.42.1, tablet 192.168.42.129):

  # en el PC
  scp -i build/rootfs/uke-arch-root -r build/pkg/staging-p2-ctrl/*.pkg.tar.* \\
      root@192.168.42.129:/root/p2/
  # en la tablet
  pacman -U --noconfirm /root/p2/*.pkg.tar.*      # todos a la vez: resuelve el grafo
  modetest -M msm -c ; eglinfo -B                 # los dos deben aparecer

Notas de por qué NO se usa `pacman -S`: sin WiFi no hay mirror, y el repo
`omarchy`/ALARM exige red. `pacman -U` con el conjunto completo en local es
equivalente y no toca la base.
"""
import argparse
import gzip
import hashlib
import io
import os
import re
import subprocess
import sys
import tarfile
import time
import urllib.request

def _repo_root():
    """Raiz del repo: se sube hasta el directorio con .git, para que el script
    funcione recien clonado y no dependa de donde este el arbol."""
    d = os.path.dirname(os.path.abspath(__file__))
    while d != "/" and not os.path.isdir(os.path.join(d, ".git")):
        d = os.path.dirname(d)
    return d


R = _repo_root()


MIRROR = os.environ.get("UKE_ALARM_MIRROR", "http://mirror.archlinuxarm.org/aarch64")
REPOS = ("core", "extra")
DEST = os.path.join(R, "build/pkg/staging-p2-ctrl")
# Semilla: lo que necesitan los peldaños de P2-ctrl y P1.
#   modetest  -> libdrm (y solo el paquete libpciaccess como dependencia)
#   eglinfo   -> mesa-utils -> mesa
WANT = ("modetest", "eglinfo")
SEEDS = ("libdrm", "mesa-utils")

UA = {"User-Agent": "Mozilla/5.0 (staging omarchy-uke)"}


def get(url, timeout=120, retries=4):
    """El mirror de ALARM corta la conexion sin aviso (se ha visto 3 veces): reintenta."""
    last = None
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                data = r.read()
            if data:
                return data
            last = "respuesta vacia"
        except Exception as e:                      # noqa: BLE001
            last = str(e)
        print("  (reintento %d/%d) %s: %s" % (i + 1, retries, url, last),
              file=sys.stderr)
        time.sleep(3 * (i + 1))
    raise RuntimeError("no se pudo bajar %s (%s)" % (url, last))


def load_repos():
    """Devuelve {pkgname: {...}} leyendo las .db de pacman.

    Layout real de un .db: tar.gz con entradas "<nombre>-<version>/desc" y
    "<nombre>-<version>/depends" (una dependencia por linea). NO usar memoria:
    esto se lee de la base de datos del repo.
    """
    pkgs = {}
    provides = {}
    for repo in REPOS:
        cache = os.path.join(DEST, "%s.db" % repo)
        if os.path.isfile(cache) and os.path.getsize(cache) > 100000:
            with open(cache, "rb") as f:
                raw = f.read()
        else:
            url = "%s/%s/%s.db" % (MIRROR, repo, repo)
            try:
                raw = get(url, timeout=600)
            except Exception as e:                  # noqa: BLE001
                print("AVISO: no se pudo bajar %s (%s)" % (url, e), file=sys.stderr)
                continue
        data = gzip.decompress(raw) if raw[:2] == b"\x1f\x8b" else raw
        n = 0
        with tarfile.open(fileobj=io.BytesIO(data)) as tf:
            members = {m.name: m for m in tf.getmembers()}
            for name, m in members.items():
                if not name.endswith("/desc"):
                    continue
                txt = tf.extractfile(m).read().decode("utf-8", "replace")
                d, key = {}, None
                for line in txt.split("\n"):
                    if line.startswith("%"):
                        # OJO: el cierre tambien lleva '%' ("%NAME%"); con line[1:]
                        # la clave quedaba "NAME%" y no se encontraba nada.
                        key = line[1:].rstrip("%")
                        d[key] = []
                    elif line and key:
                        d[key].append(line)
                pkg = d.get("NAME", [None])[0]
                if not pkg:
                    continue
                deps = []
                dep_name = name[:-len("/desc")] + "/depends"
                if dep_name in members:
                    dtxt = tf.extractfile(members[dep_name]).read().decode(
                        "utf-8", "replace")
                    # OJO: el fichero depends trae varias secciones (%DEPENDS%,
                    # %OPTDEPENDS%, %MAKEDEPENDS%, %PROVIDES%...). Solo cuentan
                    # las runtime: %DEPENDS%. Leerlo entero mete optdepends
                    # (p. ej. cairo "needed for modetest") y el cierre explota
                    # a miles de paquetes. Medido 1-oct-2026: 2048 pkgs/4,5 GiB.
                    in_deps = False
                    for line in dtxt.split("\n"):
                        if line.startswith("%"):
                            in_deps = (line.strip("%") == "DEPENDS")
                            continue
                        if not in_deps or not line.strip():
                            continue
                        m2 = re.match(r"([A-Za-z0-9@._+-]+)", line.strip())
                        if m2:
                            deps.append(m2.group(1))
                pkgs[pkg] = {
                    "version": d.get("VERSION", ["?"])[0],
                    "filename": d.get("FILENAME", [pkg])[0],
                    "csize": int(d.get("CSIZE", ["0"])[0]),
                    "deps": deps,
                    "repo": repo,
                }
                # Los provides (%PROVIDES% del fichero depends: "libgl",
                # "libz.so=1-64", "sh"...) resuelven deps virtuales/sonames.
                # Sin esto "libgl" (mesa) o "libz.so" (zlib) quedan como
                # missing y el conjunto sale incompleto.
                if dep_name in members:
                    dtxt2 = tf.extractfile(members[dep_name]).read().decode(
                        "utf-8", "replace")
                    in_prov = False
                    for line in dtxt2.split("\n"):
                        if line.startswith("%"):
                            in_prov = (line.strip("%") == "PROVIDES")
                            continue
                        if not in_prov or not line.strip():
                            continue
                        m3 = re.match(r"([A-Za-z0-9@._+-]+)", line.strip())
                        if m3:
                            provides.setdefault(m3.group(1), pkg)
                n += 1
        print("  %-6s %d paquetes" % (repo, n), file=sys.stderr)
    return pkgs, provides


def closure(pkgs, provides, seeds):
    seen, order, missing, alias = set(), [], [], {}
    stack = list(seeds)
    while stack:
        n = stack.pop(0)
        if n in seen:
            continue
        if n not in pkgs and n in provides:
            alias[n] = provides[n]
            n = provides[n]
            if n in seen:
                continue
        seen.add(n)
        p = pkgs.get(n)
        if not p:
            missing.append(n)
            continue
        order.append(n)
        stack.extend(p["deps"])
    return order, missing, alias


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--download", action="store_true")
    ap.add_argument("--verify", action="store_true")
    args = ap.parse_args()

    if args.verify:
        man = os.path.join(DEST, "MANIFEST.sha256")
        if not os.path.isfile(man):
            sys.exit("ABORT: no hay manifiesto; ejecuta antes --download")
        os.chdir(DEST)
        return subprocess.call(["sha256sum", "-c", "MANIFEST.sha256"])

    print("leyendo bases de datos de %s ..." % MIRROR, file=sys.stderr)
    # Cache local: el mirror de ALARM corta la conexion a menudo y las .db son
    # grandes (extra ~10 MB). Si ya hay una cache, se usa.
    os.makedirs(DEST, exist_ok=True)
    for repo in REPOS:
        cache = os.path.join(DEST, "%s.db" % repo)
        src = "%s/%s/%s.db" % (MIRROR, repo, repo)
        if os.path.isfile(cache) and os.path.getsize(cache) > 100000:
            continue
        try:
            with open(cache, "wb") as f:
                f.write(get(src, timeout=600))
            print("  cacheada %s" % cache, file=sys.stderr)
        except Exception as e:                      # noqa: BLE001
            print("AVISO: sin cache para %s (%s)" % (repo, e), file=sys.stderr)
    pkgs, provides = load_repos()
    if not pkgs:
        sys.exit("ABORT: no se pudo leer ninguna repo; sin eso no hay cierre de deps")
    order, missing, alias = closure(pkgs, provides, SEEDS)
    # lo que ya esta en la tablet segun PACKAGES-OVERLAY.txt no se descarga
    ov = os.path.expanduser(
        R + "/build/rootfs/PACKAGES-OVERLAY.txt")
    ya = set()
    if os.path.isfile(ov):
        for line in open(ov, encoding="utf-8", errors="replace"):
            line = line.strip()
            # Formato: "<nombre>-<pkgver>-<pkgrel>-<arch>.pkg.tar.<comp>".
            # pkgver/pkgrel/arch no llevan guiones; el nombre sí puede.
            # La regex ingenua "(.+)-[0-9]" es greedy y captura "nombre-pkgver"
            # (medido 1-oct-2026: "curl-8.22.0"); hay que anclar por la cola.
            m = re.match(r"(.+)-[^-]+-[^-]+-(?:aarch64|any)\.pkg\.tar\.",
                         line)
            if m:
                ya.add(m.group(1))
    faltan = [n for n in order if n not in ya]
    # glibc y friends: vienen de la base ALARM, no del overlay
    base = {"glibc", "gcc-libs", "bash", "coreutils", "filesystem", "shadow",
            "util-linux", "coreutils", "archlinux-keyring", "pacman", "gpgme",
            "libgpg-error", "p11-kit", "libtasn1", "nss", "nspr", "sqlite",
            "python", "python-libs", "zlib", "bzip2", "xz", "lz4", "gzip",
            "iana-etc", "ca-certificates", "libcap", "openssl", "libffi",
            "gettext", "ncurses", "readline", "sqlite", "db", "gettext-locale"}
    faltan = [n for n in faltan if n not in base]
    total = sum(pkgs[n]["csize"] for n in faltan if n in pkgs)

    print("\n== grafo de %s ==" % ", ".join(SEEDS), file=sys.stderr)
    for n in sorted(order):
        tag = "ya en la tablet" if n in ya else ("base ALARM" if n in base else "DESCARGAR")
        v = pkgs.get(n, {}).get("version", "?")
        print("  %-22s %-14s %s" % (n, v, tag))
    if missing:
        print("\nAVISO: no estan en las repos (deps opcionales/propietarias): %s"
              % ", ".join(sorted(set(missing))), file=sys.stderr)
    if alias:
        print("\nresueltos por PROVIDES:", file=sys.stderr)
        for n in sorted(alias):
            print("  %-22s -> %s" % (n, alias[n]), file=sys.stderr)
    print("\n%d paquetes a descargar, %.1f MiB" % (len(faltan), total / 2**20),
          file=sys.stderr)

    if args.list:
        return 0
    if not args.download:
        return 0

    os.makedirs(DEST, exist_ok=True)
    lines = []
    for n in faltan:
        p = pkgs[n]
        url = "%s/%s/%s" % (MIRROR, p["repo"], p["filename"])
        out = os.path.join(DEST, os.path.basename(p["filename"]))
        try:
            data = get(url, timeout=600)
        except Exception as e:                      # noqa: BLE001
            print("FALLO %s: %s" % (url, e), file=sys.stderr)
            continue
        with open(out, "wb") as f:
            f.write(data)
        sh = hashlib.sha256(data).hexdigest()
        lines.append("%s  %s" % (sh, os.path.basename(out)))
        print("  OK %8.1f KiB  %s" % (len(data) / 1024, os.path.basename(out)),
              file=sys.stderr)
        # gate de tamaño: el .db declara CSIZE y lo que llega debe coincidir
        if p["csize"] and abs(len(data) - p["csize"]) > 4096:
            print("AVISO: %s mide %d y la repo declara %d" %
                  (out, len(data), p["csize"]), file=sys.stderr)

    with open(os.path.join(DEST, "MANIFEST.sha256"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    with open(os.path.join(DEST, "INSTALAR.txt"), "w", encoding="utf-8") as f:
        f.write(
            "STAGING de P2-ctrl (modetest + eglinfo) — generado %s\n"
            "Fuente: %s  (repos %s, aarch64)\n\n"
            "EN EL PC:\n"
            "  scp -i ~/proyectos/omarchy-uke/build/rootfs/uke-arch-root \\\n"
            "      %s/*.pkg.tar.* root@192.168.42.129:/root/p2/\n\n"
            "EN LA TABLET (por ssh, enlace NCM-USB):\n"
            "  pacman -U --noconfirm /root/p2/*.pkg.tar.*\n"
            "  modetest -M msm -c     # primer peldano de P2-ctrl (d)\n"
            "  eglinfo -B             # criterio de OBJ 5 (P1)\n\n"
            "NOTA: sin WiFi no hay mirror; pacman -U con el conjunto completo en\n"
            "local resuelve el grafo y no toca la base.\n"
            % (subprocess.run(["date", "-Iseconds"], capture_output=True,
                              text=True).stdout.strip(), MIRROR,
               ", ".join(REPOS), DEST))
    print("\nescrito %s/MANIFEST.sha256 y INSTALAR.txt" % DEST, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
