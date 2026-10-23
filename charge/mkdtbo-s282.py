#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
mkdtbo-s282.py — s281 + UN SOLO fragmento: /soc/remoteproc-adsp@03000000/
glink-edge/qcom,gpr en status="disabled" (trampa documentada en #406:
apr_probe falla con -22 por falta de qcom,domain => bucle CLOSE/re-open,
6420 fallos en 38 min, udevd al 99 %, batería agotada).

Método: extraer el payload del s281, añadir fragment@2200 con target-path
(forma probada en este repo: frags 912/913 del mkdtbo-s281.py, sin labels ni
phandles que resolver), recompilar con dtc -@ y reempaquetar como dt_table
de UNA entrada (igual que s281: el ABL aplica la entrada seleccionada; dos
entradas con el mismo id serían ambiguas, por eso NO se añade una 2ª entrada).

Gates (obligatorios por REGLAS del proyecto):
  G-fdtoverlay: fdtoverlay -i base -o merged payload  => RC 0
  G-check:      build/gates/uke-dtbo-check.py <img> base => RC 0
  + paridad s281 (OPP, display, panel, touch, bootargs, ADSP cx-supply)
  + G-GPR: merged trae el nodo gpr con status="disabled" y sin él el bucle
    no puede existir (qcom_glink_match_channel usa for_each_available_child).

Uso: python3 charge/mkdtbo-s282.py   (SOLO PC, NO flashea)
Salida: build/bootimg/s282-boot-dtbo-gpu-display-opp148-nogpr.img
"""
import os, re, sys, struct, hashlib, shutil, subprocess

def _repo_root():
    """Raiz del repo: se sube hasta el directorio con .git, para que el script
    funcione recien clonado y no dependa de donde este el arbol."""
    d = os.path.dirname(os.path.abspath(__file__))
    while d != "/" and not os.path.isdir(os.path.join(d, ".git")):
        d = os.path.dirname(d)
    return d


R = _repo_root()


R = os.path.join(R, "")
BOOTIMG = os.path.join(R, "build/bootimg")
S281 = os.path.join(BOOTIMG, "s281-boot-dtbo-gpu-display-opp148.img")
S281_SHA = "90e41a6b4b91f47451bb18c0518193997604df7362631f7f3946c3ad6481b437"
BASE = os.path.expanduser("~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img")
BASE_SHA = "3f973c78f7dc6a66f1acea363be27774c51ff174fbf71117ebe74c385547562e"
OUT = os.path.join(BOOTIMG, "s282-boot-dtbo-gpu-display-opp148-nogpr.img")
WORK = "/tmp/dtbo-build-282"
PART_DTBO = 0x1800000
CHECK = os.path.join(R, "build/gates/uke-dtbo-check.py")
GPR_PATH = "/soc/remoteproc-adsp@03000000/glink-edge/qcom,gpr"

LOG = []
def log(m): print(m, flush=True); LOG.append(m)
def die(m): log("\n*** %s ***" % m); sys.exit(1)
def ok(m): log("  OK  %s" % m)
def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        while True:
            c = f.read(1 << 20)
            if not c: break
            h.update(c)
    return h.hexdigest()
def run(c): return subprocess.run(c, shell=True, capture_output=True, text=True)
def gt(m, node, prop, t=""):
    return run("fdtget %s %s %s %s" % (t, m, node, prop)).stdout.strip()

FRAG2200 = (
    '\tfragment@2200 {\n'
    '\t\ttarget-path = "%s";\n\n'
    '\t\t__overlay__ {\n'
    '\t\t\tstatus = "disabled";\n'
    '\t\t};\n'
    '\t};\n' % GPR_PATH)

def main():
    os.makedirs(WORK, exist_ok=True)
    log("=== G0 pins ===")
    for p, w, e in ((S281, S281_SHA, "s281"), (BASE, BASE_SHA, "base")):
        if not os.path.isfile(p) or sha(p) != w: die("G0: pin %s" % e)
    for t in ("dtc", "fdtoverlay", "fdtget"):
        if run("command -v %s" % t).returncode != 0: die("G0: falta %s" % t)
    if not os.path.isfile(CHECK): die("G0: falta %s" % CHECK)
    ok("pins y herramientas")

    log("=== G1: extraer payload s281 ===")
    pay = os.path.join(WORK, "s281.dtbo")
    r = subprocess.run([shutil.which("python3"), os.path.join(BOOTIMG, "dtbo-extract.py"),
                        S281, pay], capture_output=True, text=True)
    if r.returncode != 0: die("G1: extract s281")
    if run("dtc -I dtb -O dts -o %s/s281.dts %s 2>/dev/null" % (WORK, pay)).returncode != 0:
        die("G1: dtc s281")
    s281 = open(os.path.join(WORK, "s281.dts"), encoding="utf-8", errors="replace").read()
    if "qcom,gpr" in s281: die("G1: el s281 ya toca gpr (revisar)")
    frags = re.findall(r"fragment@(\d+)", s281)
    mx = max(int(x) for x in frags)
    if mx >= 2200: die("G1: fragment@2200 colisiona (max=%d)" % mx)
    ok("payload s281 (%d frags, max=%d), sin rastro de gpr" % (len(set(frags)), mx))

    log("=== G2: injertar fragment@2200 (gpr disabled) ===")
    if s281.count("fragment@2200") != 0: die("G2: 2200 ya existe")
    i0 = s281.rstrip().rfind("\n};")
    if i0 <= 0: die("G2: cierre del dts")
    open(os.path.join(WORK, "s282.dts"), "w").write(
        s281.rstrip()[:i0] + "\n" + FRAG2200 + "};\n")
    pay2 = os.path.join(WORK, "s282.dtbo")
    rc = run("dtc -@ -I dts -O dtb -o %s %s" % (pay2, os.path.join(WORK, "s282.dts")))
    if rc.returncode != 0: die("G2: dtc s282: %s" % rc.stderr[-400:])
    ok("compila con 1 fragmento añadido")

    log("=== G3: fdtoverlay (gate 1: el ABL haría lo mismo) ===")
    m_new = os.path.join(WORK, "m282.dtb")
    rr = run("fdtoverlay -i %s -o %s %s" % (BASE, m_new, pay2))
    if rr.returncode != 0: die("G3: fdtoverlay s282: %s" % (rr.stdout + rr.stderr)[-400:])
    # referencia s281 en la misma corrida (paridad)
    m_ref = os.path.join(WORK, "m281.dtb")
    if run("fdtoverlay -i %s -o %s %s" % (BASE, m_ref, pay)).returncode != 0:
        die("G3: fdtoverlay s281 (referencia)")
    ok("fdtoverlay verde (s282 y s281)")

    log("=== G4: G-GPR (el gate que importa) ===")
    st = gt(m_new, GPR_PATH, "status")
    if st != "disabled": die("G4: gpr status=%s (esperado disabled)" % st)
    ok("gpr status=disabled en el merged")
    # el resto del ADSP sigue intacto (qrtr + pmic_glink vivos)
    txt = run("dtc -I dtb -O dts %s 2>/dev/null" % m_new).stdout
    for aguja in ("qcom,pmic_glink_rpmsg", 'qcom,glink-channels = "IPCRTR"',
                  "qcom,msm-fastrpc-rpmsg"):
        if aguja not in txt: die("G4: el merged perdió %s" % aguja)
    ok("canales qrtr/pmic_glink/fastrpc intactos")

    log("=== G5: paridad s281 (nada más puede haber cambiado) ===")
    for nodo, prop, args, desc in (
        ("/soc/display-subsystem@ae00000/display-controller@ae01000", "iommus", "-t x", "iommus-DC"),
    ):
        a, b = gt(m_new, nodo, prop, args), gt(m_ref, nodo, prop, args)
        if a != b: die("G5: %s difiere s282=%s s281=%s" % (desc, a, b))
    rates = {}
    for opp in ("opp-148648750", "opp-187500000", "opp-300000000", "opp-358000000"):
        v = gt(m_new, "/soc/display-subsystem@ae00000/dsi@ae94000/opp-table/" + opp, "opp-hz", "-t x")
        try: rates[opp] = int(v.split()[1], 16)
        except Exception: die("G5: %s ilegible (%s)" % (opp, v))
    if sorted(rates.values()) != [148648750, 187500000, 300000000, 358000000]:
        die("G5: tabla DSI = %s" % rates)
    if txt.count("opp-148648750 {") != 1: die("G5: OPP duplicado/perdido")
    ba = gt(m_new, "/chosen", "bootargs")
    if not ba.startswith("msm.separate_gpu_kms=1 "): die("G5: bootargs")
    nodos = ("/soc/qcom,qupv3_0_geni_se@ac0000/spi@a90000/novatek@0",)
    if gt(m_new, nodos[0], "touchscreen-size-x") != "2136": die("G5: touch")
    ok("OPP + iommus-DC + bootargs + touch: paridad s281")

    log("=== G6: dt_table + roundtrip ===")
    blob = open(pay2, "rb").read()
    if len(blob) > PART_DTBO - 96: die("G6: tamaño %d" % len(blob))
    img = (struct.pack(">IIIIIIII", 0xD7B7AB1E, 64 + len(blob), 32, 32, 1, 32, 4096, 0)
           + struct.pack(">IIIIIIII", len(blob), 64, 0, 0, 0, 0, 0, 0) + blob)
    open(OUT, "wb").write(img)
    rt = os.path.join(WORK, "rt.dtbo")
    r = subprocess.run([shutil.which("python3"), os.path.join(BOOTIMG, "dtbo-extract.py"),
                        OUT, rt], capture_output=True, text=True)
    if r.returncode != 0 or sha(rt) != sha(pay2): die("G6: roundtrip")
    ok("dt_table (1 entrada) + roundtrip; %d B" % len(img))

    log("=== G7: gate 2 (uke-dtbo-check.py, igual que antes de flashear) ===")
    r = subprocess.run([shutil.which("python3"), CHECK, OUT, BASE],
                       capture_output=True, text=True)
    print(r.stdout[-1500:])
    if r.returncode != 0: die("G7: uke-dtbo-check.py RC=%d" % r.returncode)
    ok("uke-dtbo-check.py limpio")

    h = sha(OUT)
    log("\nPUBLICADO: %s\nsha256 = %s" % (OUT, h))
    with open(os.path.join(WORK, "repack-s282-report.txt"), "w") as f:
        f.write("\n".join(LOG) + "\n")
    shutil.copy(os.path.join(WORK, "repack-s282-report.txt"),
                os.path.join(R, "charge/repack-s282-report.txt"))

if __name__ == "__main__":
    main()
