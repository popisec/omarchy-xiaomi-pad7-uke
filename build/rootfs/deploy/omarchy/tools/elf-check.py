#!/usr/bin/env python3
"""elf-check.py -- segunda opinion del cierre: mira los ELF de verdad, no solo las deps declaradas.

Extrae (a un directorio temporal) los paquetes de manifest/instalar.tsv, lee los DT_NEEDED de cada ELF
con readelf y comprueba que cada soname lo da (a) otro paquete de la lista o (b) /usr/lib de la imagen
del rootfs (debugfs, solo lectura). Imprime lo que no resuelve. Un soname sin proveedor que NO este en
OPCIONALES es una dependencia sin declarar -> mirar antes de desplegar.

Uso:  python3 -I elf-check.py [--stage DIR] [--image IMG]     (solo PC; ~10-20 s con 12 hilos)
"""
import argparse, collections, concurrent.futures as cf, os, re, shutil, subprocess, sys, tempfile

# Raiz del repo: se sube hasta el directorio que tiene .git, para que el
# script funcione recien clonado y no dependa de donde este el arbol.
def _repo_root():
    d = os.path.dirname(os.path.abspath(__file__))
    while d != "/" and not os.path.isdir(os.path.join(d, ".git")):
        d = os.path.dirname(d)
    return d

R = _repo_root()
HERE = os.path.dirname(os.path.abspath(__file__))
# Plugins/herramientas opcionales de los paquetes que enlazan librerias que el escritorio NO usa
# (medido el 17-oct: ninguna esta en la ruta de Hyprland/quickshell/sddm-greeter-qt6).
OPCIONALES = {"libQt5Core.so.5", "libQt5Gui.so.5", "libQt5Network.so.5", "libQt5Qml.so.5", "libQt5Quick.so.5",
              "libQt5Widgets.so.5", "libSDL2-2.0.so.0", "libffado.so.2", "libglut.so.3", "libheif.so.1",
              "libmariadb.so.3", "libnotify.so.4", "libodbc.so.2", "libpq.so.5", "librrd.so.8", "libtcl8.6.so",
              "libtk8.6.so"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", default=f"{R}/build/stage-escritorio")
    ap.add_argument("--image", default=f"{R}/build/rootfs/rootfs-uke-l76-8g.img")
    a = ap.parse_args()
    rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(HERE, "..", "manifest", "instalar.tsv")) if not l.startswith("#")]
    work = tempfile.mkdtemp(prefix="elf-check-")

    def scan(r):
        fname, name = r[2], r[3]
        tmp = tempfile.mkdtemp(dir=work)
        out = {"needed": collections.defaultdict(set), "provides": set()}
        subprocess.run(["bsdtar", "-xf", os.path.join(a.stage, fname), "-C", tmp, "--no-same-owner", "--no-same-permissions",
                        "--exclude", ".*"], capture_output=True)
        for root, _d, files in os.walk(tmp):
            for f in files:
                p = os.path.join(root, f)
                if ".so" in f:
                    out["provides"].add(f)
                if os.path.islink(p) or not os.path.isfile(p):
                    continue
                with open(p, "rb") as fh:
                    if fh.read(4) != b"\x7fELF":
                        continue
                dyn = subprocess.run(["readelf", "-d", p], capture_output=True, text=True, env={"LC_ALL": "C"}).stdout
                for s in re.findall(r"\(NEEDED\)\s+Shared library: \[(.*?)\]", dyn):
                    out["needed"][s].add(os.path.relpath(p, tmp))
                for s in re.findall(r"\(SONAME\)\s+Library soname: \[(.*?)\]", dyn):
                    out["provides"].add(s)
        shutil.rmtree(tmp, ignore_errors=True)
        return name, out

    try:
        with cf.ThreadPoolExecutor(10) as ex:
            res = dict(ex.map(scan, rows))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    img = set()
    for line in subprocess.run(["debugfs", "-R", "ls -p /usr/lib", a.image], capture_output=True, text=True).stdout.splitlines():
        f = line.split("/")
        if len(f) > 5:
            img.add(f[5])
    prov = collections.defaultdict(set)
    for n, o in res.items():
        for s in o["provides"]:
            prov[s].add(n)
    miss = collections.defaultdict(set)
    n_elf = 0
    for n, o in res.items():
        for s, files in o["needed"].items():
            n_elf += len(files)
            if s not in prov and s not in img:
                miss[s].add(n)
    print(f"paquetes: {len(res)} | enlaces NEEDED revisados: {n_elf}")
    bad = {s: v for s, v in miss.items() if s not in OPCIONALES}
    for s, v in sorted(miss.items()):
        tag = "opcional" if s in OPCIONALES else "SIN DECLARAR"
        print(f"  {tag:13s} {s}  <- {sorted(v)[:5]}")
    print("RESULTADO:", "OK (solo opcionales)" if not bad else f"REVISAR {len(bad)} sonames")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
