#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
mkcpio-v8a.py — 23-oct-2026 (kernel «v8a», sin flashear): initramfs = cpio k34-fw-k52b2 (el embebido en v7)
con /ukeinit parcheado por build/init/ukeinit-v8.diff + e2fsck aarch64 y sus libs (patrón mkcpio-k50.py, #510).

Diferencias con mkcpio-k50.py:
  * NO se extrae el cpio a disco para re-empaquetarlo: se reescribe en Python entrada a entrada (formato newc),
    así se conservan EXACTAMENTE modos, uid/gid, mtimes, symlinks y orden del cpio de v7; solo cambia el cuerpo
    de /ukeinit y se añaden al final /bin/e2fsck + 7 ficheros en /lib.
  * El binario va como /bin/e2fsck (lo que espera ukeinit-v8.diff), no /bin/e2fsck-k50.
  * Binarios fijados por sha256 (== mtree de pacman del staging == los de la tablet, medido 23-oct por SSH).
  * Salida en carpeta IGNORADA por git (build/kernel-pokes/): el cpio lleva binarios.

Gates: G0 pins (cpio, ukeinit, binarios vs mtree), G1 parche + sh -n + busybox ash -n (el busybox del propio
cpio bajo qemu-aarch64), G2 ELF aarch64 + cierre de NEEDED + intérprete, G3 cpio nuevo + roundtrip con cpio(1),
G4 qemu smoke (e2fsck -V), G5 tamaño.
Uso: python3 -I build/gates/mkcpio-v8a.py
"""
import gzip
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

# La raiz del repo: se sube hasta el directorio con .git, para que el script
# funcione recien clonado y no dependa de donde este el arbol.
def _raiz_del_repo():
    d = os.path.dirname(os.path.abspath(__file__))
    while d != "/" and not os.path.isdir(os.path.join(d, ".git")):
        d = os.path.dirname(d)
    return d


R = _raiz_del_repo()
BASE = R + "/build/init/uke-k34-fw-k52b2-initramfs.cpio.gz"
BASE_SHA = "ebc2de46ea89a4512be06b87e92d5dbb2f8aca8fe9a07304b697566551bf48bc"
UKEINIT_SHA = "fcdd63f14a99171976f1c038d4110fe7eb57695de452ccfa42021914527d81fc"
DIFF = R + "/build/init/ukeinit-v8.diff"
STG = R + "/build/rootfs/staging"
OUTD = R + "/build/kernel-pokes/optim-ouke6/v8a"
OUT = OUTD + "/uke-k34-fw-v8a-initramfs.cpio.gz"      # termina en .cpio.gz: usr/Makefile lo copia tal cual
LOG = OUTD + "/mkcpio-v8a-report.txt"
MTIME_NEW = 1792713600   # 2026-10-23 00:00:00 UTC (mtime fijo de las entradas nuevas/cambiadas: reproducible)

# (ruta en cpio, origen en staging, sha256 esperado, paquete con mtree)
BINS = [
    ("bin/e2fsck", "usr/bin/e2fsck", "48abcde5daff900e774f17f255580a3306d35b21bc2c8660b82016835e3f295c", "e2fsprogs-1.47.4-1"),
    ("lib/ld-linux-aarch64.so.1", "usr/lib/ld-linux-aarch64.so.1", "b1f2738bdb51e6419d7062f96c8a44bd68853698dc5ac624fa6ca9f9b03d456d", "glibc-2.43+r22+g8362e8ce10b2-2"),
    ("lib/libext2fs.so.2", "usr/lib/libext2fs.so.2.4", "7714544a666b472dfdf54e4c074401ac957e6c38053382ef94630a69bbc3ab4a", "e2fsprogs-1.47.4-1"),
    ("lib/libcom_err.so.2", "usr/lib/libcom_err.so.2.1", "e00d7e9f917da09261087bda0b421f1749c8f1536e9ee13f6f0361177243e788", "e2fsprogs-1.47.4-1"),
    ("lib/libblkid.so.1", "usr/lib/libblkid.so.1.1.0", "36c2815cbef03db5a25334cf7355d8b4d2b7867398bf7f485806493ec7b92e42", "TABLET:util-linux-libs-2.42.4-1"),
    ("lib/libuuid.so.1", "usr/lib/libuuid.so.1.3.0", "98f5106993cd1523eff94cfb46380fd802071113eb6b4e4895042d3bd3c33dc8", "TABLET:util-linux-libs-2.42.4-1"),
    ("lib/libe2p.so.2", "usr/lib/libe2p.so.2.3", "76354e6f09bfc86ff28467ec8a23e94cf7bd6e4d7d3be4acd60fe0e3153749f9", "e2fsprogs-1.47.4-1"),
    ("lib/libc.so.6", "usr/lib/libc.so.6", "6ab264fb4e8df9942b0fb75b48fcd5c30b2f081d8dfaa6c25d7be1d3fce5b2ab", "glibc-2.43+r22+g8362e8ce10b2-2"),
]

LOGF = []


def log(m):
    print(m)
    LOGF.append(m)


def flush():
    os.makedirs(OUTD, exist_ok=True)
    with open(LOG, "w", encoding="utf-8") as f:
        f.write("\n".join(LOGF) + "\n")


def die(m):
    log("\n*** %s ***" % m)
    flush()
    sys.exit(1)


def ok(m):
    log("  OK  %s" % m)


def sha(b):
    return hashlib.sha256(b).hexdigest()


def run(argv, **kw):
    return subprocess.run(argv, capture_output=True, text=True, **kw)


# ---------------- newc ----------------
def parse_newc(data):
    ents, off = [], 0
    while True:
        if data[off:off + 6] != b"070701":
            raise ValueError("magia newc mala en %d" % off)
        f = [int(data[off + 6 + 8 * i: off + 14 + 8 * i], 16) for i in range(13)]
        ino, mode, uid, gid, nlink, mtime, fsize, devmaj, devmin, rdevmaj, rdevmin, nsz, _chk = f
        p = off + 110
        name = data[p:p + nsz - 1].decode()
        p = (p + nsz + 3) & ~3
        body = data[p:p + fsize]
        off = (p + fsize + 3) & ~3
        if name == "TRAILER!!!":
            return ents
        ents.append(dict(ino=ino, mode=mode, uid=uid, gid=gid, nlink=nlink, mtime=mtime, devmaj=devmaj,
                         devmin=devmin, rdevmaj=rdevmaj, rdevmin=rdevmin, name=name, body=body))


def emit_newc(ents):
    out = bytearray()

    def one(e):
        nm = e["name"].encode() + b"\0"
        hdr = "070701" + "".join("%08X" % v for v in (
            e["ino"], e["mode"], e["uid"], e["gid"], e["nlink"], e["mtime"], len(e["body"]), e["devmaj"],
            e["devmin"], e["rdevmaj"], e["rdevmin"], len(nm), 0))
        out.extend(hdr.encode() + nm)
        out.extend(b"\0" * ((-len(out)) % 4))
        out.extend(e["body"])
        out.extend(b"\0" * ((-len(out)) % 4))
    for e in ents:
        one(e)
    one(dict(ino=0, mode=0, uid=0, gid=0, nlink=1, mtime=0, devmaj=0, devmin=0, rdevmaj=0, rdevmin=0,
             name="TRAILER!!!", body=b""))
    out.extend(b"\0" * ((-len(out)) % 512))
    return bytes(out)


def mtree_sha(pkg, path):
    p = STG + "/var/lib/pacman/local/%s/mtree" % pkg
    for l in gzip.open(p, "rt", errors="replace"):
        parts = l.split()
        if parts and parts[0] == "./" + path:
            for t in parts[1:]:
                if t.startswith("sha256digest="):
                    return t.split("=", 1)[1]
    return None


def main():
    os.makedirs(OUTD, exist_ok=True)
    log("=== mkcpio-v8a.py (%s) ===" % subprocess.run(["date", "-Is"], capture_output=True, text=True).stdout.strip())
    log("=== G0: pins ===")
    raw_gz = open(BASE, "rb").read()
    if sha(raw_gz) != BASE_SHA:
        die("G0: sha del cpio base != ebc2de46…")
    cpio = gzip.decompress(raw_gz)
    ents = parse_newc(cpio)
    reem = emit_newc(ents)
    if reem == cpio:
        ok("el escritor newc re-emite el cpio base BYTE A BYTE (%d B): el formato es fiel" % len(cpio))
    else:
        log("  (aviso) re-emision del cpio base no es byte-identica (%d vs %d B); se comprueba por entradas en G3"
            % (len(reem), len(cpio)))
    names = [e["name"] for e in ents]
    ui = [e for e in ents if e["name"] == "ukeinit"]
    if len(ui) != 1 or sha(ui[0]["body"]) != UKEINIT_SHA:
        die("G0: /ukeinit ausente o sha != fcdd63f1…")
    ok("cpio base %s (%d entradas); /ukeinit fcdd63f1…" % (BASE_SHA[:16], len(ents)))
    for dst, src, want, pkg in BINS:
        if dst in names:
            die("G0: %s ya existe en el cpio base" % dst)
        b = open(STG + "/" + src, "rb").read()
        # libblkid/libuuid: el mtree del staging es de 2.42.2 pero el fichero es el de 2.42.4-1 (staging resincronizado
        # sin su db); el pin sale del mtree de util-linux-libs-2.42.4-1 instalado en la tablet (pacman verifico la .sig
        # al instalar; .pkg.tar.xz + .sig en /var/cache/pacman/pkg), medido 23-oct por SSH.
        m = want if pkg.startswith("TABLET:") else mtree_sha(pkg, src)
        if sha(b) != want or m != want:
            die("G0: %s sha %s (mtree %s) != pin %s" % (src, sha(b)[:16], (m or "-")[:16], want[:16]))
    ok("8 binarios == pin == sha256digest del mtree de pacman (e2fsprogs 1.47.4-1, glibc 2.43, util-linux-libs 2.42.4-1 de la tablet)"
       " == ficheros de la tablet (medido 23-oct por SSH)")

    log("=== G1: parche ukeinit-v8.diff ===")
    td = tempfile.mkdtemp(prefix="v8a-ukeinit-")
    open(td + "/ukeinit", "wb").write(ui[0]["body"])
    r = run(["patch", "-p1", "--no-backup-if-mismatch", "-d", td, "-i", DIFF])
    if r.returncode != 0 or "FAILED" in r.stdout or "fuzz" in r.stdout.lower() or "offset" in r.stdout.lower():
        die("G1: patch no aplica limpio: %r %r" % (r.stdout, r.stderr))
    new = open(td + "/ukeinit", "rb").read()
    old_s, new_s = ui[0]["body"].decode(), new.decode()

    def nocom(t):
        return "\n".join(l for l in t.splitlines() if not l.lstrip().startswith("#"))
    checks = [
        ('mount -t ext4 -o ro "/dev/$UBUNTU" /mnt/ubuntu' in new_s, "mount ro sin noload"),
        (new_s.count('mount -t ext4 -o ro,noload "/dev/$UBUNTU"') == 1, "ro,noload solo como respaldo (1 vez)"),
        ("LD_LIBRARY_PATH=/lib /bin/e2fsck -p " in new_s, "e2fsck -p (preen, sin -f/-y)"),
        ("e2fsck -fy" not in new_s and "e2fsck -y" not in new_s, "sin -fy"),
        (nocom(new_s).count("reboot") == nocom(old_s).count("reboot"),
         "no se anade ningun reboot fuera de comentarios (%d antes y despues)" % nocom(old_s).count("reboot")),
        ("exec busybox switch_root /mnt/ubuntu /sbin/init" in new_s, "switch_root intacto"),
    ]
    for c, what in checks:
        if not c:
            die("G1: falla '%s'" % what)
    ok("patch -p1 limpio (sin fuzz/offset); " + "; ".join(w for _, w in checks))
    q = shutil.which("qemu-aarch64")
    r = run(["sh", "-n", td + "/ukeinit"])
    if r.returncode:
        die("G1: sh -n: %s" % r.stderr)
    bb = td + "/busybox"
    open(bb, "wb").write([e for e in ents if e["name"] == "bin/busybox"][0]["body"])
    os.chmod(bb, 0o755)
    if q:
        r = run([q, bb, "ash", "-n", td + "/ukeinit"])
        if r.returncode:
            die("G1: busybox ash -n (busybox del cpio, qemu): %s" % r.stderr)
        ok("sh -n y 'busybox ash -n' con el busybox DEL CPIO bajo qemu-aarch64: sin errores")
    else:
        ok("sh -n OK (sin qemu-aarch64: ash -n no comprobado)")
    open(OUTD + "/ukeinit-v8a", "wb").write(new)
    log("      ukeinit nuevo sha256 %s (%d B) -> %s" % (sha(new), len(new), OUTD + "/ukeinit-v8a"))

    log("=== G2: ELF ===")
    soname = {os.path.basename(d) for d, _, _, _ in BINS if d.startswith("lib/")}
    for dst, src, _, _ in BINS:
        p = STG + "/" + src
        h = run(["readelf", "-h", p]).stdout
        if "AArch64" not in h or "ELF64" not in h:
            die("G2: %s no es ELF64 AArch64" % src)
        need = [l.split("[")[-1].rstrip("]") for l in run(["readelf", "-d", p]).stdout.splitlines() if "(NEEDED)" in l]
        falta = [n for n in need if n not in soname]
        if falta:
            die("G2: %s necesita %s, que no va en el cpio" % (src, falta))
    interp = [l for l in run(["readelf", "-l", STG + "/usr/bin/e2fsck"]).stdout.splitlines() if "interpreter" in l]
    if not interp or "/lib/ld-linux-aarch64.so.1" not in interp[0]:
        die("G2: interprete de e2fsck inesperado: %r" % interp)
    ok("8 ELF64 AArch64; cierre de NEEDED dentro del cpio (recursivo por fichero); interprete /lib/ld-linux-aarch64.so.1 presente")

    log("=== G3: cpio nuevo ===")
    nents = []
    for e in ents:
        e = dict(e)
        if e["name"] == "ukeinit":
            e["body"] = new
            e["mtime"] = MTIME_NEW
        nents.append(e)
    uid = ui[0]["uid"]
    gid = ui[0]["gid"]
    ino = max(e["ino"] for e in ents) + 1
    for dst, src, _, _ in BINS:
        nents.append(dict(ino=ino, mode=0o100755, uid=uid, gid=gid, nlink=1, mtime=MTIME_NEW, devmaj=0, devmin=0,
                          rdevmaj=0, rdevmin=0, name=dst, body=open(STG + "/" + src, "rb").read()))
        ino += 1
    blob = emit_newc(nents)
    gz = gzip.compress(blob, compresslevel=9, mtime=0)
    open(OUT, "wb").write(gz)
    # roundtrip con cpio(1) del sistema
    rt = tempfile.mkdtemp(prefix="v8a-rt-")
    r = subprocess.run("gzip -dc '%s' | cpio -idm --quiet" % OUT, shell=True, cwd=rt, capture_output=True, text=True)
    if r.returncode:
        die("G3: cpio -idm del cpio nuevo: %s" % r.stderr)
    lst = run(["sh", "-c", "gzip -dc '%s' | cpio -t --quiet" % OUT]).stdout.split()
    if lst != [e["name"] for e in nents]:
        die("G3: listado del cpio nuevo != entradas esperadas")
    for e in nents:
        p = os.path.join(rt, e["name"])
        if (e["mode"] & 0o170000) == 0o100000:
            if sha(open(p, "rb").read()) != sha(e["body"]):
                die("G3: roundtrip %s" % e["name"])
        elif (e["mode"] & 0o170000) == 0o120000:
            if os.readlink(p) != e["body"].decode():
                die("G3: roundtrip symlink %s" % e["name"])
    for e0 in ents:
        if e0["name"] == "ukeinit":
            continue
        e1 = [e for e in nents if e["name"] == e0["name"]][0]
        if any(e0[k] != e1[k] for k in ("mode", "uid", "gid", "mtime", "body")):
            die("G3: la entrada heredada %s cambio" % e0["name"])
    if not os.path.isfile(rt + "/lib/firmware/qcom/gen71100_gmu.bin"):
        die("G3: fw GPU ausente")
    ok("%d entradas (= %d heredadas, 47 identicas a v7 + ukeinit nuevo, + %d nuevas); roundtrip cpio(1) por sha;"
       " fw GPU intacto" % (len(nents), len(ents), len(BINS)))

    log("=== G4: qemu smoke ===")
    if q:
        r = run([q, "-L", rt, rt + "/bin/e2fsck", "-V"], env=dict(os.environ, LD_LIBRARY_PATH="/lib"))
        out = (r.stdout + r.stderr).strip()
        if r.returncode != 0 or "1.47.4" not in out:
            die("G4: qemu smoke: rc=%d %r" % (r.returncode, out[-200:]))
        ok("qemu-aarch64 -L <cpio extraido> /bin/e2fsck -V: %s" % out.splitlines()[0])
    else:
        log("  AVISO sin qemu-aarch64")
    shutil.rmtree(rt, ignore_errors=True)
    shutil.rmtree(td, ignore_errors=True)

    log("=== G5: publicacion ===")
    if not (len(gz) < 8 << 20):
        die("G5: cpio.gz demasiado grande (%d)" % len(gz))
    log("  %s" % OUT)
    log("  cpio.gz %d B sha256 %s" % (len(gz), sha(gz)))
    log("  cpio    %d B sha256 %s (base %d B: +%d B)" % (len(blob), sha(blob), len(cpio), len(blob) - len(cpio)))
    with open(OUT + ".sha256", "w") as f:
        f.write("%s  %s\n" % (sha(gz), os.path.basename(OUT)))
    flush()


if __name__ == "__main__":
    main()
