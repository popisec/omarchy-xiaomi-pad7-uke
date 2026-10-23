"""
mkdtbo-s285.py — s283 + SOLO los 2 fragmentos del GPI-DMA (aislar el wedge de s284).

POR QUE: s284 (s283 + 9 fragmentos GENI) hace WEDGEAR el arranque a los 70 s con
0 bytes de consola. s284 hacia DOS cambios a la vez:

  (a) los 2 nodos `qcom,gpi-dma`: compatible `qcom,gpi-dma` (generico, sin match)
      -> `qcom,palawan-gpi-dma` + `qcom,sm6350-gpi-dma`, `#dma-cells` 5->3, y anade
      `dma-channels=12` + `dma-channel-mask=0x1e`, que gpi.c:2178/2185 EXIGE.
      Efecto: **el driver GPI pasa a bindear**, y no se habia probado nunca en esta
      maquina (antes fallaba el probe y no tocaba nada).
  (b) los 7 nodos GENI (5 i2c + 2 spi): compatible vendor sin match -> el de mainline,
      `clock-names`, y `dmas` a 3 celdas. Efecto: **los 5 buses I2C pasan a probe-ar**
      por primera vez.

Cual de los dos wedgea NO SE SABE. Aqui solo se anade (a): los 2 fragmentos del GPI,
dejando los compatibles del I2C/SPI como estaban (y por tanto sin probe, que es el
estado conocido y estable de las 39 rondas).

| Resultado | Lectura |
|---|---|
| arranca | el wedge es (b), los buses I2C/SPI. (a) es inocuo y se puede usar ya |
| wedgea  | **(a) es el culpable**: bindear el GPI-DMA tumba el SoC. Habria que buscar otro proveedor de DMA |

Comparar contra: s283 (arranca, log de 376 KB) y s284 (muerto, 0 B).

Gates: fdtoverlay + verificacion de los 2 nodos + paridad s283 (OPP, gpr disabled,
backlight del panel, panel intacto) + uke-dtbo-check.py.

Uso: python3 charge/mkdtbo-s285.py   (SOLO PC, NO flashea)
Salida: build/bootimg/s285-boot-dtbo-gpu-display-gpi-only.img
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
S283 = os.path.join(BOOTIMG, "s283-boot-dtbo-gpu-display-opp148-nogpr-bl.img")
S283_SHA = "a8e7d4c06af2733445ccf40d15f2efcd1d076cc3702698665c3e5ff076c610d7"
FRAG_SRC = os.path.join(R, "build/gates/FRAGMENTO-GENI-I2C-DMA.dts")
BASE = os.path.expanduser("~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img")
BASE_SHA = "3f973c78f7dc6a66f1acea363be27774c51ff174fbf71117ebe74c385547562e"
OUT = os.path.join(BOOTIMG, "s285-boot-dtbo-gpu-display-gpi-only.img")
WORK = "/tmp/dtbo-build-285"
PART_DTBO = 0x1800000
CHECK = os.path.join(R, "build/gates/uke-dtbo-check.py")

GPR_PATH   = "/soc/remoteproc-adsp@03000000/glink-edge/qcom,gpr"
KTZ_PATH   = "/soc/qcom,qupv3_0_geni_se@ac0000/i2c@a80000/ktz8866@11"
PANEL_PATH = "/soc/display-subsystem@ae00000/dsi@ae94000/panel@0"
OPP_BASE   = "/soc/display-subsystem@ae00000/dsi@ae94000/opp-table"
GPI_NODES  = ["/soc/qcom,gpi-dma@a00000", "/soc/qcom,gpi-dma@800000"]
# los nodos GENI que s284 tocaba: deben seguir SIN tocar en s285
GENI_NODES = [
    "/soc/qcom,qupv3_0_geni_se@ac0000/i2c@a80000",
    "/soc/qcom,qupv3_0_geni_se@ac0000/i2c@a8c000",
    "/soc/qcom,qupv3_1_geni_se@8c0000/i2c@890000",
    "/soc/qcom,qupv3_0_geni_se@ac0000/spi@a84000",
    "/soc/qcom,qupv3_0_geni_se@ac0000/spi@a90000",
]

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
    # TODO entrecomillado, incluido el prop: sin comillas, '#dma-cells' lo
    # lee el shell como inicio de comentario y devuelve vacio (bug H2 del s284,
    # repetido aqui porque se copio la idea sin el entrecomillado del prop).
    return run("fdtget %s '%s' '%s' '%s'" % (t, m, node, prop)).stdout.strip()

def main():
    os.makedirs(WORK, exist_ok=True)
    log("=== G0 pins ===")
    for p, w, e in ((S283, S283_SHA, "s283"), (BASE, BASE_SHA, "base")):
        if not os.path.isfile(p) or sha(p) != w: die("G0: pin %s" % e)
    for t in ("dtc", "fdtoverlay", "fdtget"):
        if run("command -v %s" % t).returncode != 0: die("G0: falta %s" % t)
    ok("pins y herramientas")

    log("=== G1: extraer payload s283 ===")
    pay = os.path.join(WORK, "s283.dtbo")
    r = subprocess.run([shutil.which("python3"), os.path.join(BOOTIMG, "dtbo-extract.py"),
                        S283, pay], capture_output=True, text=True)
    if r.returncode != 0: die("G1: extract s283: %s" % r.stderr[-200:])
    if run("dtc -I dtb -O dts -o %s/s283.dts %s 2>/dev/null" % (WORK, pay)).returncode != 0:
        die("G1: dtc s283")
    src = open(os.path.join(WORK, "s283.dts"), encoding="utf-8", errors="replace").read()
    frags = [int(x) for x in re.findall(r"^[ \t]*fragment@(\d+) \{", src, re.M)]
    mx = max(frags)
    if mx >= 2400: die("G1: 2400+ colisiona (max=%d)" % mx)
    if "qcom,palawan-gpi-dma" in src: die("G1: el s283 ya toca el gpi-dma")
    ok("payload s283 (%d frags, max=%d), sin gpi-dma tocado" % (len(set(frags)), mx))

    log("=== G2: aislar SOLO los 2 fragmentos del GPI-DMA ===")
    raw = open(FRAG_SRC, encoding="utf-8", errors="replace").read()
    # extraer SOLO los fragmentos cuyo target-path es un gpi-dma
    blocks = re.findall(r"fragment@22(\d\d) \{(.*?)\n\};", raw, re.S)
    gpi = [(n, b) for n, b in blocks if "gpi-dma" in b]
    if len(gpi) != 2:
        die("G2: esperaba 2 fragmentos gpi-dma, hay %d" % len(gpi))
    inj = ""
    for i, (n, b) in enumerate(sorted(gpi)):
        inj += "fragment@24%02d {%s\n};\n\n" % (i, b)
    inj = re.sub(r"fragment@22(\d\d)", lambda mm: "fragment@24%s" % mm.group(1), inj)
    nums = sorted(int(x) for x in re.findall(r"^fragment@(24\d\d) \{", inj, re.M))
    if nums != [2400, 2401]:
        die("G2: renumeracion fallo -> %s" % nums)
    if mx >= nums[0]: die("G2: colision %d vs %d" % (mx, nums[0]))
    ok("2 fragmentos gpi-dma aislados y renumerados a 2400/2401")

    i0 = src.rstrip().rfind("\n};")
    if i0 <= 0: die("G2: cierre del dts")
    open(os.path.join(WORK, "s285.dts"), "w").write(
        src.rstrip()[:i0] + "\n" + inj.rstrip() + "\n};\n")
    pay2 = os.path.join(WORK, "s285.dtbo")
    rc = run("dtc -@ -I dts -O dtb -o %s %s" % (pay2, os.path.join(WORK, "s285.dts")))
    if rc.returncode != 0: die("G2: dtc s285: %s" % rc.stderr[-500:])
    ok("compila con 2 fragmentos anadidos")

    log("=== G3: fdtoverlay (gate 1) ===")
    m_new = os.path.join(WORK, "m285.dtb")
    rr = run("fdtoverlay -i %s -o %s %s" % (BASE, m_new, pay2))
    if rr.returncode != 0: die("G3: fdtoverlay s285: %s" % (rr.stdout + rr.stderr)[-400:])
    m_ref = os.path.join(WORK, "m283.dtb")
    if run("fdtoverlay -i %s -o %s %s" % (BASE, m_ref, pay)).returncode != 0:
        die("G3: fdtoverlay s283 (referencia)")
    ok("fdtoverlay verde (s285 y s283)")

    log("=== G4: el GPI cambia, y SOLO el GPI ===")
    for n in GPI_NODES:
        c = gt(m_new, n, "compatible", "-t s")
        dc = gt(m_new, n, "#dma-cells", "-t u")
        ch = gt(m_new, n, "dma-channels", "-t u")
        mk = gt(m_new, n, "dma-channel-mask", "-t x")
        c_ref = gt(m_ref, n, "compatible", "-t s")
        if "qcom,sm6350-gpi-dma" not in c:
            die("G4: %s compatible=%r" % (n, c))
        if c_ref == c:
            die("G4: %s no cambio de compatible (%r) — el aislamiento no aisla nada" % (n, c))
        if not dc or not ch or not mk:
            die("G4: %s incompleto: #dma-cells=%r channels=%r mask=%r" % (n, dc, ch, mk))
        ok("  %s -> %s | #dma-cells=%s channels=%s mask=%s" % (n, c, dc, ch, mk))
    # los GENI deben seguir EXACTAMENTE como en s283
    for n in GENI_NODES:
        c = gt(m_new, n, "compatible", "-t s")
        c_ref = gt(m_ref, n, "compatible", "-t s")
        if c != c_ref:
            die("G4: %s cambio a %r (el aislamiento exige %r intacto)" % (n, c, c_ref))
    ok("  los %d nodos GENI siguen intactos (compatible=%r)" % (len(GENI_NODES), c))

    log("=== G5: paridad s283 ===")
    if gt(m_new, GPR_PATH, "status", "-t s") != "disabled":
        die("G5: el gpr dejo de estar disabled (la trampa del ADSP vuelve)")
    ph = gt(m_new, KTZ_PATH, "phandle", "-t u")
    bl = gt(m_new, PANEL_PATH, "backlight", "-t u")
    if not ph or ph != bl:
        die("G5: backlight=%s dejo de apuntar al ktz=%s" % (bl, ph))
    rates = {}
    for opp in ("opp-148648750", "opp-187500000", "opp-300000000", "opp-358000000"):
        v = gt(m_new, OPP_BASE + "/" + opp, "opp-hz", "-t x")
        try: rates[opp] = int(v.split()[1], 16)
        except Exception: die("G5: %s ilegible (%s)" % (opp, v))
    if sorted(rates.values()) != [148648750, 187500000, 300000000, 358000000]:
        die("G5: tabla DSI = %s" % rates)
    ok("gpr disabled + backlight resuelto + OPP 148648750: paridad s283")

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

    log("=== G7: uke-dtbo-check.py (GATE, no aviso) ===")
    r = subprocess.run([shutil.which("python3"), CHECK, OUT, BASE],
                       capture_output=True, text=True)
    print(r.stdout[-700:])
    if r.returncode != 0: die("G7: uke-dtbo-check.py RC=%d" % r.returncode)
    ok("uke-dtbo-check.py limpio")

    h = sha(OUT)
    log("\nPUBLICADO: %s\nsha256 = %s" % (OUT, h))
    open(os.path.join(WORK, "repack-s285-report.txt"), "w").write("\n".join(LOG) + "\n")
    shutil.copy(os.path.join(WORK, "repack-s285-report.txt"),
                os.path.join(R, "charge/repack-s285-report.txt"))

if __name__ == "__main__":
    main()
