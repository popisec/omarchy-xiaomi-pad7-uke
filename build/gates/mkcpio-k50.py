#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
mkcpio-k50.py — #510: cpio K34-fw + e2fsck aarch64 embebido + bloque de fsck
en ukeinit ANTES del montaje del rootfs.

POR QUÉ: las muertes en reposo (#509) dejaron el rootfs ext4 inconsistente
(EXT4-fs error group 37, visible desde las 15:12) y desde entonces TODOS los
arranques mueren a ~8.2 s (determinista, silencioso) al tocar la metadata mala
durante el burst de I/O del arranque. El rootfs monta `norecovery`: el journal
NO se re-aplica, así que la corrupción no se auto-cura nunca. La máquina no
vive lo suficiente para fsck-earse desde dentro ⇒ el fsck va en el INITRAMFS
(corre con /dev/sda32 SIN montar, que es como e2fsck debe correr).

QUÉ AÑADE al cpio K34 (que ya lleva el fw de la GPU):
  /bin/e2fsck-k50            <- staging/usr/bin/e2fsck (aarch64, dinámico)
  /lib/ld-linux-aarch64.so.1 + libext2fs.so.2 libcom_err.so.2 libblkid.so.1
     libuuid.so.1 libe2p.so.2 libc.so.6      <- staging/usr/lib
  ukeinit: bloque K50 justo antes de `mkdir -p /mnt/ubuntu`: e2fsck -fy sobre
     /dev/$UBUNTU (elegida por la lógica s123), salida a /tmp/fsck.log, rc y
     tail de 5 líneas a /dev/kmsg (la consola lo ve: uke-arch arranque).

GATES: G0 pins+ELF aarch64+NEEDED completas; G1 ancla única; G2 qemu smoke si
hay qemu-aarch64; G3 roundtrip del cpio publicado; G4 tamaño razonable.
"""
import gzip
import hashlib
import os
import shutil
import subprocess
import sys

# La raiz del repo: se sube hasta el directorio con .git, para que el script
# funcione recien clonado y no dependa de donde este el arbol.
def _raiz_del_repo():
    d = os.path.dirname(os.path.abspath(__file__))
    while d != "/" and not os.path.isdir(os.path.join(d, ".git")):
        d = os.path.dirname(d)
    return d


R = _raiz_del_repo()
K34 = R + "/build/init/uke-k34-fw-initramfs.cpio.gz"
K34_SHA = "ebc2de46ea89a4512be06b87e92d5dbb2f8aca8fe9a07304b697566551bf48bc"
STG = R + "/build/rootfs/staging"
WORK = "/var/tmp/uke-cpio-k50"
OUT = R + "/build/init/uke-k50-fw-fsck-initramfs.cpio.gz"
LOG = R + "/build/init/repack-uke-k50-initramfs-report.txt"

LIBS = ["ld-linux-aarch64.so.1", "libext2fs.so.2", "libcom_err.so.2",
        "libblkid.so.1", "libuuid.so.1", "libe2p.so.2", "libc.so.6"]

LOGF = []


def log(m):
    print(m); LOGF.append(m)


def die(m):
    log("\n*** %s ***" % m)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write("\n".join(LOGF) + "\n")
    sys.exit(1)


def ok(m):
    log("  OK  %s" % m)


def sha_de(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        while True:
            c = f.read(1 << 20)
            if not c:
                break
            h.update(c)
    return h.hexdigest()


def run(c):
    return subprocess.run(c, shell=True, capture_output=True, text=True)


ANCLA = 'kmsg "S123: raiz candidata /dev/$UBUNTU ($max KB)"'
BLOQUE = '''
# --- UKE-K50 (#510): fsck del rootfs ANTES de montarlo. La corrupcion acumulada
# --- por las muertes sucias (norecovery) mataba el arranque a los ~8.2 s.
if [ -x /bin/e2fsck-k50 ]; then
  kmsg "K50: e2fsck -fy /dev/$UBUNTU ARRANCA"
  LD_LIBRARY_PATH=/lib /bin/e2fsck-k50 -fy "/dev/$UBUNTU" >/tmp/fsck-k50.log 2>&1
  rc=$?
  kmsg "K50: e2fsck rc=$rc (0=limpio 1=corregido 2+3=reparado|reiniciar 4=cancelado)"
  busybox tail -n 6 /tmp/fsck-k50.log 2>/dev/null | while IFS= read -r _l; do
    kmsg "K50-fsck: $_l"
  done
  sync
else
  kmsg "K50: SIN e2fsck embebido (esto no deberia verse)"
fi
'''


def main():
    with open(LOG, "a", encoding="utf-8") as f:
        f.write("\n\n==== mkcpio-k50.py ====\n")

    log("=== G0: pins y binarios ===")
    if not os.path.isfile(K34) or sha_de(K34) != K34_SHA:
        die("G0: pin del cpio K34")
    e2 = STG + "/usr/bin/e2fsck"
    if not os.path.isfile(e2):
        die("G0: falta e2fsck en staging")
    mach = run("readelf -h %s | grep -m1 AArch64" % e2).stdout
    if "AArch64" not in mach:
        die("G0: e2fsck no es aarch64: %r" % mach.strip())
    ok("e2fsck aarch64")
    needed = [l.split("[")[-1].rstrip("]") for l in
              run("readelf -d %s | grep NEEDED" % e2).stdout.splitlines()]
    faltan = [n for n in needed if n not in LIBS]
    if faltan:
        die("G0: NEEDED fuera de la lista: %r" % faltan)
    for l in LIBS:
        if not os.path.isfile(STG + "/usr/lib/" + l):
            die("G0: falta la lib %s en staging/usr/lib" % l)
    ok("NEEDED completas: %s" % ", ".join(needed))

    log("=== G1: extraccion y ancla ===")
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)
    r = run("cd %s && gzip -dc %s | cpio -idm --quiet" % (WORK, K34))
    if r.returncode != 0 or not os.path.isfile(WORK + "/ukeinit"):
        die("G1: no extraje el cpio")
    ini = open(WORK + "/ukeinit", encoding="utf-8").read()
    if ini.count(ANCLA) != 1:
        die("G1: ancla no unica (%d)" % ini.count(ANCLA))
    ini = ini.replace(ANCLA, ANCLA + "\n" + BLOQUE)
    open(WORK + "/ukeinit", "w", encoding="utf-8").write(ini)
    ok("bloque K50 insertado tras la seleccion de la raiz")

    log("=== G2: copiar binarios ===")
    os.makedirs(WORK + "/lib", exist_ok=True)
    shutil.copy2(e2, WORK + "/bin/e2fsck-k50")
    os.chmod(WORK + "/bin/e2fsck-k50", 0o755)
    for l in LIBS:
        shutil.copy2(STG + "/usr/lib/" + l, WORK + "/lib/" + l)
    ok("e2fsck-k50 + %d libs en /lib" % len(LIBS))

    q = shutil.which("qemu-aarch64-static") or shutil.which("qemu-aarch64")
    if q:
        r = run("LD_LIBRARY_PATH=%s/lib %s -L %s %s/bin/e2fsck-k50 -V" % (WORK, q, WORK, WORK))
        if r.returncode != 0 or "e2fsck" not in (r.stdout + r.stderr):
            die("G2: qemu smoke fallo: %r %r" % (r.stdout[-100:], r.stderr[-100:]))
        ok("qemu smoke: %s" % (r.stdout + r.stderr).splitlines()[0])
    else:
        log("  AVISO  sin qemu-aarch64: smoke test saltado (documentado)")

    log("=== G3: empaquetar y roundtrip ===")
    r = run("cd %s && find . | LC_ALL=C sort | cpio -o -H newc --quiet | gzip -9n > %s"
            % (WORK, OUT))
    if r.returncode != 0 or not os.path.isfile(OUT):
        die("G3: empaquetado")
    chk = "/var/tmp/uke-cpio-k50-check"
    shutil.rmtree(chk, ignore_errors=True)
    os.makedirs(chk)
    run("cd %s && gzip -dc %s | cpio -idm --quiet" % (chk, OUT))
    if sha_de(chk + "/bin/e2fsck-k50") != sha_de(e2):
        die("G3: roundtrip sha e2fsck")
    if "K50: e2fsck rc=" not in open(chk + "/ukeinit", encoding="utf-8").read():
        die("G3: roundtrip sin bloque K50")
    for l in LIBS:
        if not os.path.isfile(chk + "/lib/" + l):
            die("G3: roundtrip sin %s" % l)
    # el fw de la GPU sigue dentro (herencia K34)
    if not os.path.isfile(chk + "/lib/firmware/qcom/gen71100_gmu.bin"):
        die("G3: el fw de la GPU desaparecio")
    ok("roundtrip OK; fw GPU intacto")

    log("=== G4: publicacion ===")
    sz = os.path.getsize(OUT)
    if not (30 << 20) > sz > 2_000_000:
        die("G4: tamano raro %d" % sz)
    log("PUBLICADO %s (%d B)\nsha256 = %s" % (OUT, sz, sha_de(OUT)))
    with open(LOG, "a", encoding="utf-8") as f:
        f.write("\n".join(LOGF) + "\n")


if __name__ == "__main__":
    main()
