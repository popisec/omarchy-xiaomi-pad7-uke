#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""mkcpio-k51.py — #511: cpio k50 + SLEEP discriminador de 30 s ANTES de tocar el
rootfs (partición/mount/fsck). Si la máquina muere a los ~8,2 s durante el sueño
puro de initramfs (sin I/O al rootfs), el asesino 8,2 s NO es el disco; si
sobrevive y el fsck llega a correr/completar, el frente es storage/corrupción.
Latido cada 5 s por kmsg Y /dev/ttyGS0 (líneas repetidas vencen la carrera de
reattach del lector)."""
import os
import gzip, hashlib, os, shutil, subprocess, sys

# La raiz del repo: se sube hasta el directorio con .git, para que el script
# funcione recien clonado y no dependa de donde este el arbol.
def _raiz_del_repo():
    d = os.path.dirname(os.path.abspath(__file__))
    while d != "/" and not os.path.isdir(os.path.join(d, ".git")):
        d = os.path.dirname(d)
    return d


R = _raiz_del_repo()
K50 = R + "/build/init/uke-k50-fw-fsck-initramfs.cpio.gz"
K50_SHA = "9aee1d4dab5fbc82db6ecc3e902185497a59ecf2cf318a062e02d2e7455ee494"
WORK = "/var/tmp/uke-cpio-k51"
OUT = R + "/build/init/uke-k51-sleep-fsck-initramfs.cpio.gz"
LOG = R + "/build/init/repack-uke-k51-initramfs-report.txt"
LOGF = []

def log(m): print(m); LOGF.append(m)
def die(m):
    log("\n*** %s ***" % m)
    with open(LOG, "a", encoding="utf-8") as f: f.write("\n".join(LOGF) + "\n")
    sys.exit(1)
def ok(m): log("  OK  %s" % m)
def sha_de(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        while True:
            c = f.read(1 << 20)
            if not c: break
            h.update(c)
    return h.hexdigest()
def run(c): return subprocess.run(c, shell=True, capture_output=True, text=True)

ANCLA = '# ============ S123: switch_root a Ubuntu (fase 2) ============'
BLOQUE = '''# --- UKE-K51 (#511): SUENO DISCRIMINADOR. 30 s de initramfs puro ANTES de
# --- esperar/montar/fsck-ear el rootfs. Latido cada 5 s por kmsg y ttyGS0.
kmsg "K51: sueno discriminador 30s empieza t=$(cut -d. -f1 /proc/uptime)s"
_k51i=0
while [ $_k51i -lt 6 ]; do
  sleep 5
  _k51t=$(cut -d. -f1 /proc/uptime)
  kmsg "K51-vivo t=${_k51t}s ($(($_k51i+1))/6)"
  echo "uke: K51-vivo t=${_k51t}s ($(($_k51i+1))/6)" > /dev/ttyGS0 2>/dev/null
  _k51i=$((_k51i+1))
done
kmsg "K51: sueno COMPLETO t=$(cut -d. -f1 /proc/uptime)s — sigue el flujo S123"
echo "uke: K51 sueno completo" > /dev/ttyGS0 2>/dev/null

'''

def main():
    with open(LOG, "a", encoding="utf-8") as f: f.write("\n\n==== mkcpio-k51.py ====\n")
    log("=== G0: pin ===")
    if not os.path.isfile(K50) or sha_de(K50) != K50_SHA:
        die("G0: pin del cpio k50")
    ok("cpio k50 pineado")
    log("=== G1: extraccion y ancla ===")
    shutil.rmtree(WORK, ignore_errors=True); os.makedirs(WORK)
    if run("cd %s && gzip -dc %s | cpio -idm --quiet" % (WORK, K50)).returncode != 0:
        die("G1: extraccion")
    ini = open(WORK + "/ukeinit", encoding="utf-8").read()
    if ini.count(ANCLA) != 1:
        die("G1: ancla no unica (%d)" % ini.count(ANCLA))
    ini = ini.replace(ANCLA, BLOQUE + ANCLA)
    open(WORK + "/ukeinit", "w", encoding="utf-8").write(ini)
    ok("bloque K51 insertado antes de S123")
    log("=== G3: empaquetar y roundtrip ===")
    if run("cd %s && find . | LC_ALL=C sort | cpio -o -H newc --quiet | gzip -9n > %s" % (WORK, OUT)).returncode != 0:
        die("G3: empaquetado")
    chk = "/var/tmp/uke-cpio-k51-check"
    shutil.rmtree(chk, ignore_errors=True); os.makedirs(chk)
    run("cd %s && gzip -dc %s | cpio -idm --quiet" % (chk, OUT))
    c2 = open(chk + "/ukeinit", encoding="utf-8").read()
    for tok in ("K51-vivo", "K51: sueno COMPLETO", "K50: e2fsck rc="):
        if tok not in c2:
            die("G3: roundtrip sin %s" % tok)
    if not os.path.isfile(chk + "/bin/e2fsck-k50"):
        die("G3: roundtrip sin e2fsck")
    if not os.path.isfile(chk + "/lib/firmware/qcom/gen71100_gmu.bin"):
        die("G3: fw GPU desaparecido")
    ok("roundtrip OK (K51+K50+fw)")
    log("PUBLICADO %s (%d B)\nsha256 = %s" % (OUT, os.path.getsize(OUT), sha_de(OUT)))
    with open(LOG, "a", encoding="utf-8") as f: f.write("\n".join(LOGF) + "\n")

if __name__ == "__main__":
    main()
