#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""mkcpio-k52b2-diag.py — cpio uke-k52b2-diag: el cpio VIVO (k52b2, ebc2de46…,
embebido en los kernels L19/L25 vía CONFIG_INITRAMFS_SOURCE) + vigilante de
diagnóstico UKE-DIAG:
  /uke/diag-snapshot.sh            <- build/init/diag-snapshot.sh (nuevo, 755)
  /ukeinit: bloque UKE-DIAG tras el remount rw del S123 (lanza el vigilante
    con setsid + stdin-fd para sobrevivir al switch_root, + self-test ls -la
    en background a +2 s).

Clon estructural de build/gates/mkcpio-k51.py (mismos gates G0/G1/G3 + G4 de
tamaño; G2 = smoke funcional del vigilante bajo qemu-aarch64 con /proc y
/sys falsos, casos happy + ro + dmesg-vacío). NO toca el kernel ni ningún
boot.img: solo publica el cpio. El horneado al kernel lo hace el rebuild
incremental con INITRAMFS_SOURCE (precedente #602, L19fsck) y el repack
build/gates/repack-k52L25diag.py.
"""
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
K52B2 = R + "/build/init/uke-k34-fw-k52b2-initramfs.cpio.gz"
K52B2_SHA = "ebc2de46ea89a4512be06b87e92d5dbb2f8aca8fe9a07304b697566551bf48bc"
DIAG = R + "/build/init/diag-snapshot.sh"
WORK = "/var/tmp/uke-cpio-k52b2-diag"
OUT = R + "/build/init/uke-k52b2-diag-initramfs.cpio.gz"
LOG = R + "/build/init/repack-uke-k52b2-diag-initramfs-report.txt"
QEMU = "/usr/bin/qemu-aarch64"
LOGF = []


def log(m):
    print(m)
    LOGF.append(m)


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


ANCLA = 'mount -o remount,rw /mnt/ubuntu 2>/dev/null || kmsg "S123 AVISO: remount rw fallo (raiz en ro)"'
BLOQUE = '''
# --- UKE-DIAG (#diag): vigilante de diagnóstico en el rootfs persistente ---
# El kernel muere en boot loop SIN unclean shutdown y el ACM pierde la ventana
# mortal; pstore guarda 0 ficheros. El rootfs es ext4 persistente: un snapshot
# periódico de dmesg+estado en /root/diag SOBREVIVE al reset (el último escrito
# con éxito ES la evidencia). Lanzado con setsid + stdin-fd (< script) para que
# sobreviva al switch_root aunque se borre la raíz vieja; background para no
# bloquear el arranque; todo best-effort (|| true) para no tumbarlo.
if [ -x /uke/diag-snapshot.sh ]; then
  mkdir -p /mnt/ubuntu/root/diag 2>/dev/null || true
  busybox cp -f /uke/diag-snapshot.sh /mnt/ubuntu/root/diag/diag-snapshot.sh 2>/dev/null || true
  setsid sh /uke/diag-snapshot.sh < /uke/diag-snapshot.sh >/dev/null 2>&1 &
  kmsg "UKE-DIAG: vigilante lanzado (pid $!)"
  ( sleep 2
    if [ -d /mnt/ubuntu/root/diag ] && [ -n "$(ls /mnt/ubuntu/root/diag 2>/dev/null)" ]; then
      ls -la /mnt/ubuntu/root/diag 2>/dev/null | while IFS= read -r _l; do kmsg "UKE-DIAG-TEST: $_l"; done
    else
      kmsg "UKE-DIAG-TEST: FALLO (sin ficheros a +2s)"
    fi ) &
else
  kmsg "UKE-DIAG: sin /uke/diag-snapshot.sh (se sigue sin vigilante)"
fi
'''


def main():
    with open(LOG, "w", encoding="utf-8") as f:
        f.write("==== mkcpio-k52b2-diag.py ====\n")
    log("=== G0: pins y sintaxis ===")
    if not os.path.isfile(K52B2) or sha_de(K52B2) != K52B2_SHA:
        die("G0: pin del cpio k52b2 (¿cambió el cpio vivo?)")
    ok("cpio k52b2 pineado (ebc2de46…)")
    if not os.path.isfile(DIAG):
        die("G0: falta build/init/diag-snapshot.sh")
    if not os.access(DIAG, os.X_OK):
        die("G0: diag-snapshot.sh no ejecutable")
    if run("bash -n %s" % DIAG).returncode != 0:
        die("G0: bash -n del vigilante")
    ok("bash -n del vigilante")
    # ash -n con el busybox REAL del cpio (es lo que lo ejecutará pre-switch)
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)
    if run("cd %s && gzip -dc %s | cpio -idm --quiet" % (WORK, K52B2)).returncode != 0:
        die("G0: extracción previa del cpio")
    bb = WORK + "/bin/busybox"
    r = run("%s %s sh -n %s" % (QEMU, bb, DIAG))
    if r.returncode != 0:
        die("G0: ash -n del vigilante bajo qemu: %r %r" % (r.stdout[-200:], r.stderr[-200:]))
    ok("ash -n del vigilante (busybox del cpio bajo qemu)")

    log("=== G1: extraccion, ancla e instalacion ===")
    ini_path = WORK + "/ukeinit"
    ini = open(ini_path, encoding="utf-8").read()
    if ini.count(ANCLA) != 1:
        die("G1: ancla remount-rw no única (%d)" % ini.count(ANCLA))
    if "UKE-DIAG" in ini:
        die("G1: el ukeinit ya lleva UKE-DIAG (¿doble aplicación?)")
    ini = ini.replace(ANCLA, ANCLA + "\n" + BLOQUE)
    open(ini_path, "w", encoding="utf-8").write(ini)
    ok("bloque UKE-DIAG insertado tras el remount rw del S123")
    os.makedirs(WORK + "/uke", exist_ok=True)
    shutil.copy2(DIAG, WORK + "/uke/diag-snapshot.sh")
    os.chmod(WORK + "/uke/diag-snapshot.sh", 0o755)
    if run("bash -n %s" % ini_path).returncode != 0:
        die("G1: bash -n del ukeinit parcheado")
    r = run("%s %s sh -n %s" % (QEMU, bb, ini_path))
    if r.returncode != 0:
        die("G1: ash -n del ukeinit parcheado: %r" % (r.stderr[-200:],))
    ok("ukeinit parcheado pasa bash -n y ash -n")

    log("=== G2: smoke funcional del vigilante (qemu, /proc y /sys falsos) ===")
    t = "/var/tmp/uke-diag-smoke"
    shutil.rmtree(t, ignore_errors=True)
    for d in ("fakeproc", "fakesys/class/drm/card1-DSI-1", "out", "out-ro",
              "out-empty", "kmsg", "tbin"):
        os.makedirs(t + "/" + d)
    open(t + "/fakeproc/uptime", "w").write("123.45 67.89\n")
    open(t + "/fakeproc/cmdline", "w").write(
        "console=ttyGS0 bootinfo.pureason=0x800011 video=DSI-1:d\n")
    open(t + "/fakeproc/interrupts", "w").write(
        " 86:          1          0     GICv3 123 Edge      ae94000.dsi\n"
        " 87:          0          0     GICv3 124 Edge      mdss_dsi_esd\n"
        " 99:          5          0     GICv3 200 Level     uart\n")
    open(t + "/fakesys/class/drm/card1-DSI-1/status", "w").write("connected\n")
    with open(t + "/fakedmesg.txt", "w") as f:
        for i in range(1, 601):
            f.write("[    0.123456] fake-kernel line %d\n" % i)
    open(t + "/tbin/dmesg", "w").write("#!/bin/sh\ncat %s/fakedmesg.txt\n" % t)
    os.chmod(t + "/tbin/dmesg", 0o755)
    env = ("PATH=%s/tbin:$PATH PROC=%s/fakeproc SYS=%s/fakesys "
           "DIAG_INTERVAL=0 DIAG_KMSG_EVERY=10 " % (t, t, t))
    scr = WORK + "/uke/diag-snapshot.sh"
    # happy: 12 ciclos -> 5 rotativos de 400 líneas (201..600), estado, ultimo
    r = run("%sDIAG_DIR=%s/out DEVKMSG=%s/kmsg/msg DIAG_MAXCYC=12 "
            "%s %s sh %s < %s" % (env, t, t, QEMU, bb, scr, scr))
    if r.returncode != 0:
        die("G2: happy rc=%d %r %r" % (r.returncode, r.stdout[-300:], r.stderr[-300:]))
    outs = sorted(os.listdir(t + "/out"))
    want = sorted(["dmesg.%d.txt" % i for i in range(5)] + ["estado.txt", "ultimo.txt"])
    if outs != want:
        die("G2: happy ficheros %r != %r" % (outs, want))
    got = open(t + "/out/dmesg.3.txt", encoding="utf-8").read().splitlines()
    if len(got) != 400 or not got[0].endswith("line 201") or not got[-1].endswith("line 600"):
        die("G2: happy truncado != 400 últimas (201..600)")
    est = open(t + "/out/estado.txt", encoding="utf-8").read()
    for tok in ("bootinfo.pureason=0x800011", "ae94000.dsi", "mdss_dsi_esd",
                "card1-DSI-1 status=connected"):
        if tok not in est:
            die("G2: happy estado sin %r" % tok)
    if "uart" in [l for l in est.splitlines() if "interrupts" not in l and "Edge" in l and "uart" in l]:
        die("G2: happy el filtro de IRQ deja pasar uart")
    ult = open(t + "/out/ultimo.txt", encoding="utf-8").read()
    if "ciclo=11" not in ult or "lineas=400" not in ult:
        die("G2: happy ultimo sin ciclo=11/lineas=400: %r" % ult)
    km = open(t + "/kmsg/msg", encoding="utf-8").read()
    if km.count("UKE-DIAG-SNAP") != 1 or "UKE-DIAG-SNAP 10" not in km:
        die("G2: happy kmsg != 1 latido (n=10): %r" % km)
    if [f for f in outs if ".tmp" in f]:
        die("G2: happy deja .tmp")
    ok("happy: 5 rotativos x400 + estado + ultimo + 1 latido kmsg")
    # ro: dir no escribible -> rc 0, sin ficheros, con latido
    os.makedirs(t + "/out-ro", exist_ok=True)
    os.chmod(t + "/out-ro", 0o555)
    r = run("%sDIAG_DIR=%s/out-ro DEVKMSG=%s/kmsg/msg-ro DIAG_MAXCYC=3 "
            "%s %s sh %s < %s" % (env, t, t, QEMU, bb, scr, scr))
    os.chmod(t + "/out-ro", 0o755)
    if r.returncode != 0 or os.listdir(t + "/out-ro"):
        die("G2: ro rc=%d o escribió" % r.returncode)
    if "UKE-DIAG-SNAP 0" not in open(t + "/kmsg/msg-ro", encoding="utf-8").read():
        die("G2: ro sin latido kmsg")
    ok("ro: rc 0, no escribe, mantiene latido")
    # dmesg vacío: rc 0, sin ficheros
    open(t + "/tbin/dmesg", "w").write("#!/bin/sh\nexit 1\n")
    r = run("%sDIAG_DIR=%s/out-empty DEVKMSG=%s/kmsg/msg-e DIAG_MAXCYC=3 "
            "%s %s sh %s < %s" % (env, t, t, QEMU, bb, scr, scr))
    if r.returncode != 0 or os.listdir(t + "/out-empty"):
        die("G2: empty rc=%d o escribió" % r.returncode)
    ok("dmesg vacío: rc 0, no escribe")

    log("=== G3: empaquetar y roundtrip ===")
    if run("cd %s && find . | LC_ALL=C sort | cpio -o -H newc --quiet | gzip -9n > %s"
           % (WORK, OUT)).returncode != 0:
        die("G3: empaquetado")
    chk = "/var/tmp/uke-cpio-k52b2-diag-check"
    shutil.rmtree(chk, ignore_errors=True)
    os.makedirs(chk)
    run("cd %s && gzip -dc %s | cpio -idm --quiet" % (chk, OUT))
    c2 = open(chk + "/ukeinit", encoding="utf-8").read()
    for tok in ("UKE-DIAG: vigilante lanzado", "UKE-DIAG-TEST:",
                "setsid sh /uke/diag-snapshot.sh < /uke/diag-snapshot.sh",
                "X9S123-SWITCH", "exec busybox switch_root /mnt/ubuntu /sbin/init"):
        if tok not in c2:
            die("G3: roundtrip sin %r" % tok)
    if c2.count(ANCLA) != 1:
        die("G3: ancla duplicada en roundtrip")
    st = os.stat(chk + "/uke/diag-snapshot.sh")
    if not (st.st_mode & 0o111):
        die("G3: diag-snapshot.sh sin +x en roundtrip")
    if sha_de(chk + "/uke/diag-snapshot.sh") != sha_de(DIAG):
        die("G3: diag-snapshot.sh corrupto en roundtrip")
    if not os.path.isfile(chk + "/lib/firmware/qcom/gen71100_gmu.bin"):
        die("G3: fw GPU desaparecido")
    ok("roundtrip OK (hook + script + fw GPU intacto)")

    log("=== G4: publicacion ===")
    sz, ref = os.path.getsize(OUT), os.path.getsize(K52B2)
    if not (8 << 20) > sz > 1_000_000:
        die("G4: tamano raro %d" % sz)
    if abs(sz - ref) > 65536:
        die("G4: delta vs k52b2 %d B (>64 KiB, ¿qué más cambió?)" % (sz - ref))
    log("PUBLICADO %s (%d B, delta %+d B vs k52b2)\nsha256 = %s"
        % (OUT, sz, sz - ref, sha_de(OUT)))
    with open(LOG, "a", encoding="utf-8") as f:
        f.write("\n".join(LOGF) + "\n")


if __name__ == "__main__":
    main()
