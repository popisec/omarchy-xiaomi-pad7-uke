"""
mkdtbo-s286.py — s285 + SOLO el bus I2C del KTZ8866 (peldaño 6 del auditor).

POR QUE: s284 (s283 + GPI + 7 GENI) wedgea a 70 s con 0 B; s285 (solo los 2
del GPI-DMA) ARRANCA (VEREDICTO-WEDGE-AISLADO.md 13-oct). Veredicto: el
GPI-DMA es inocuo; el culpable es hacer que los buses GENI probeen por
primera vez. El auditor (AUDITORIA-METODO-20261013.md §3 peldaño 6) ordena:
"s286 = s283 + GPI + solo 1 bus I2C (el del KTZ8866); techo 1 bus por flash".

CUAL BUS (verificado en esta máquina, 13-oct-2026, sin tablet):
  /soc/qcom,qupv3_0_geni_se@ac0000/i2c@a80000  (wrapper0 SE0, reg 0xa80000)
  = fragment@2202 de FRAGMENTO-GENI-I2C-DMA.dts. Por qué este y no otro:
  1) El panel.backlight de s283 (flasheado, arranca) resuelve al nodo
     ktz8866@11 que vive BAJO ESTE BUS (KTZ_BUS_PATH de mkdtbo-s283.py).
     s286 existe para que ESE bus probee y el KTZ del panel bindee.
  2) Alias stock verificado: stock2-Cliffs7P-uke.dts:21204
     `qupv3_se0_i2c = "/soc/qcom,qupv3_0_geni_se@ac0000/i2c@a80000"`.
  3) DT vivo Android (dt-r15, snapshot del aparato): ktz8866@11 existe bajo
     i2c@a80000 (con wcd939x_i2c@e: bus probado electricamente).
  4) En la base este bus ya esta status="ok" (estable 39 rondas); su dmas
     usa el GPI 0x1df de SU wrapper (gpi-dma@a00000, ya en s285).
  EL OTRO NODO (declaración dual, NO dos chips confirmados):
  dt-r15 también trae ktz8866@11 bajo i2c@890000 (qupv3_se12_i2c, alias
  stock2:21232), pero el panel NO apunta ahí, en base está
  status="disabled", y 1-vs-2 chips físicos solo lo dirime `i2cdetect
  se0/se12` en la tablet (ESTADO-VIVO:147-155, pendiente). El probe vendor
  no hace I/O (REV-KTZ8866 §1), así que un nodo fantasma es inofensivo, y
  el techo de 1 bus por flash deja se12 para un peldaño posterior.
  Este script NO asume número de chips: solo probea se0.

CAMBIO ÚNICO vs s285: 1 fragmento (2202->2402) con compatible
`qcom,geni-i2c` + clock-names="se" + dmas 3-celdas al GPI 0x1df +
dma-names="tx,rx". Efecto colateral documentado: el vecino wcd939x_i2c@e
del mismo bus también verá su driver si existe en mainline (inevitable,
mismo bus).

Gates: fdtoverlay + el bus cambia (fences 1+2+2b como s284 G4) + GPI
intacto de s285 + los otros 6 GENI intactos + paridad s285 (gpr disabled,
backlight resuelto, OPP, panel) + diff exhaustivo libfdt (solo el bus
puede diferir) + uke-dtbo-check.py.

Uso: python3 charge/mkdtbo-s286.py   (SOLO PC, NO flashea)
Salida: build/bootimg/s286-boot-dtbo-gpu-display-gpi-i2c-ktz.img
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
S285 = os.path.join(BOOTIMG, "s285-boot-dtbo-gpu-display-gpi-only.img")
S285_SHA = "0b0b16b569e7212bd5f6dfa8a17d43c512a812f9950ca7bcd2084914d181bf06"
FRAG_SRC = os.path.join(R, "build/gates/FRAGMENTO-GENI-I2C-DMA.dts")
BASE = os.path.expanduser("~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img")
BASE_SHA = "3f973c78f7dc6a66f1acea363be27774c51ff174fbf71117ebe74c385547562e"
OUT = os.path.join(BOOTIMG, "s286-boot-dtbo-gpu-display-gpi-i2c-ktz.img")
WORK = "/tmp/dtbo-build-286"
PART_DTBO = 0x1800000
CHECK = os.path.join(R, "build/gates/uke-dtbo-check.py")

GPR_PATH   = "/soc/remoteproc-adsp@03000000/glink-edge/qcom,gpr"
KTZ_BUS    = "/soc/qcom,qupv3_0_geni_se@ac0000/i2c@a80000"
KTZ_PATH   = KTZ_BUS + "/ktz8866@11"
PANEL_PATH = "/soc/display-subsystem@ae00000/dsi@ae94000/panel@0"
OPP_BASE   = "/soc/display-subsystem@ae00000/dsi@ae94000/opp-table"
GPI_NODES  = ["/soc/qcom,gpi-dma@a00000", "/soc/qcom,gpi-dma@800000"]
# los 6 GENI que s286 NO toca: deben salir del merged IDENTICOS a s285
GENI_INTACTOS = [
    "/soc/qcom,qupv3_0_geni_se@ac0000/i2c@a8c000",
    "/soc/qcom,qupv3_0_geni_se@ac0000/spi@a84000",
    "/soc/qcom,qupv3_0_geni_se@ac0000/spi@a90000",
    "/soc/qcom,qupv3_1_geni_se@8c0000/i2c@880000",
    "/soc/qcom,qupv3_1_geni_se@8c0000/i2c@88c000",
    "/soc/qcom,qupv3_1_geni_se@8c0000/i2c@890000",
]
GPI_BUS_WRAPPER0 = "/soc/qcom,gpi-dma@a00000"   # literal 0x1df

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
    return run("fdtget %s '%s' '%s' '%s'" % (t, m, node, prop)).stdout.strip()

def main():
    os.makedirs(WORK, exist_ok=True)
    log("=== G0 pins ===")
    for p, w, e in ((S285, S285_SHA, "s285"), (BASE, BASE_SHA, "base")):
        if not os.path.isfile(p) or sha(p) != w: die("G0: pin %s" % e)
    if not os.path.isfile(FRAG_SRC): die("G0: falta %s" % FRAG_SRC)
    if not os.path.isfile(CHECK): die("G0: falta %s" % CHECK)
    for t in ("dtc", "fdtoverlay", "fdtget"):
        if run("command -v %s" % t).returncode != 0: die("G0: falta %s" % t)
    ok("pins (s285 0b0b16b5 + base 3f973c78), fragmento y herramientas")

    log("=== G1: extraer payload s285 ===")
    pay = os.path.join(WORK, "s285.dtbo")
    r = subprocess.run([shutil.which("python3"), os.path.join(BOOTIMG, "dtbo-extract.py"),
                        S285, pay], capture_output=True, text=True)
    if r.returncode != 0: die("G1: extract s285: %s" % r.stderr[-200:])
    if run("dtc -I dtb -O dts -o %s/s285.dts %s 2>/dev/null" % (WORK, pay)).returncode != 0:
        die("G1: dtc s285")
    src = open(os.path.join(WORK, "s285.dts"), encoding="utf-8", errors="replace").read()
    frags = [int(x) for x in re.findall(r"^[ \t]*fragment@(\d+) \{", src, re.M)]
    mx = max(frags)
    if mx != 2401: die("G1: el s285 deberia acabar en 2401 (2400/2401 GPI), veo %d" % mx)
    if "qcom,geni-i2c" in src: die("G1: el s285 ya toca un bus GENI (revisar)")
    ok("payload s285 (%d frags, max=%d), sin GENI tocado" % (len(set(frags)), mx))

    log("=== G2: aislar SOLO fragment@2202 (bus i2c@a80000 del KTZ) ===")
    raw = open(FRAG_SRC, encoding="utf-8", errors="replace").read()
    m = re.search(r"fragment@2202 \{(.*?)\n\};", raw, re.S)
    if not m: die("G2: fragment@2202 no encontrado en %s" % FRAG_SRC)
    body = m.group(1)
    if ('target-path = "%s";' % KTZ_BUS) not in body:
        die("G2: fragment@2202 no apunta a %s (revisar)" % KTZ_BUS)
    if "compatible = \"qcom,geni-i2c\"" not in body:
        die("G2: fragment@2202 sin compatible mainline (revisar)")
    if "dmas = <0x1df" not in body:
        die("G2: fragment@2202 sin dmas al GPI 0x1df de su wrapper (revisar)")
    inj = "fragment@2402 {%s\n};\n" % body
    open(os.path.join(WORK, "s286.dts"), "w").write(
        src.rstrip()[:src.rstrip().rfind("\n};")] + "\n" + inj + "};\n")
    pay2 = os.path.join(WORK, "s286.dtbo")
    rc = run("dtc -@ -I dts -O dtb -o %s %s" % (pay2, os.path.join(WORK, "s286.dts")))
    if rc.returncode != 0: die("G2: dtc s286: %s" % rc.stderr[-500:])
    ok("compila con 1 fragmento anadido (2202->2402, %s)" % KTZ_BUS)

    log("=== G3: fdtoverlay (gate 1: el ABL haria lo mismo) ===")
    m_new = os.path.join(WORK, "m286.dtb")
    rr = run("fdtoverlay -i %s -o %s %s" % (BASE, m_new, pay2))
    if rr.returncode != 0: die("G3: fdtoverlay s286: %s" % (rr.stdout + rr.stderr)[-400:])
    m_ref = os.path.join(WORK, "m285.dtb")
    if run("fdtoverlay -i %s -o %s %s" % (BASE, m_ref, pay)).returncode != 0:
        die("G3: fdtoverlay s285 (referencia)")
    ok("fdtoverlay verde (s286 y s285)")

    log("=== G4: el bus del KTZ cambia, y SOLO el ===")
    c = gt(m_new, KTZ_BUS, "compatible", "-t s")
    if c != "qcom,geni-i2c":
        die("G4: %s compatible=%r (el driver i2c-qcom-geni NO acepta otro)" % (KTZ_BUS, c))
    cn = gt(m_new, KTZ_BUS, "clock-names", "-t s")
    if cn != "se": die("G4: %s clock-names=%r (el driver pide 'se')" % (KTZ_BUS, cn))
    if gt(m_new, KTZ_BUS, "dma-names", "-t s").split() != ["tx", "rx"]:
        die("G4: %s dma-names != 'tx rx'" % KTZ_BUS)
    cells = [int(x, 16) for x in gt(m_new, KTZ_BUS, "dmas", "-t x").split()]
    if len(cells) != 8:
        die("G4: %s dmas tiene %d celdas (esperado 8 = 2 entradas de ph+3)" % (KTZ_BUS, len(cells)))
    provs = [cells[0], cells[4]]
    ph_real = gt(m_new, GPI_BUS_WRAPPER0, "phandle", "-t x")
    if not all(p == int(ph_real, 16) for p in provs):
        die("G4: dmas apunta a %s pero el phandle real de %s es %s (colgando)"
            % (["0x%x" % p for p in provs], GPI_BUS_WRAPPER0, ph_real))
    if [cells[3], cells[7]] != [3, 3]:
        die("G4: proto=%s (esperado 3=I2C en ambas entradas)" % ([cells[3], cells[7]]))
    ok("vallas 1+2+2b: compatible mainline + clock-names=se + dmas al GPI de su wrapper + proto I2C")
    # el GPI sigue como lo dejo s285
    for n in GPI_NODES:
        if "qcom,sm6350-gpi-dma" not in gt(m_new, n, "compatible", "-t s"):
            die("G4: %s perdio el compatible sm6350 de s285" % n)
        if gt(m_new, n, "compatible", "-t s") != gt(m_ref, n, "compatible", "-t s"):
            die("G4: %s cambio respecto a s285" % n)
    ok("los 2 gpi-dma intactos de s285 (sm6350 + channels + mask)")
    # los otros 6 GENI, intactos prop por prop
    for n in GENI_INTACTOS:
        for k in ("compatible", "clock-names", "dmas", "dma-names"):
            if gt(m_new, n, k) != gt(m_ref, n, k):
                die("G4: %s cambio en %s (techo: 1 bus por flash)" % (n, k))
    ok("los 6 GENI no tocados siguen identicos a s285")

    log("=== G5: paridad s285 ===")
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
    for k in ("compatible", "reg", "reset-gpios", "vddil8b-supply"):
        if gt(m_new, PANEL_PATH, k) != gt(m_ref, PANEL_PATH, k):
            die("G5: el panel cambio en %s" % k)
    ok("gpr disabled + backlight resuelto + OPP 148648750 + panel identico: paridad s285")

    log("=== G5b: diff exhaustivo m285 vs m286 (solo el bus puede diferir) ===")
    import libfdt
    def tree_props(path):
        fdt = libfdt.Fdt(open(path, "rb").read())
        nodes = {}
        def walk(off, p):
            try: name = fdt.get_name(off)
            except Exception: name = ""
            q = (p.rstrip("/") + "/" + name) if name else p
            props = {}
            try: poff = fdt.first_property_offset(off)
            except Exception: poff = -1
            while poff >= 0:
                pr = fdt.get_property_by_offset(poff)
                if pr.name not in ("phandle", "name"):
                    props[pr.name] = bytes(pr)
                try: poff = fdt.next_property_offset(poff)
                except Exception: break
            nodes[q] = props
            try: c = fdt.first_subnode(off)
            except Exception: return
            while c >= 0:
                walk(c, q)
                try: c = fdt.next_subnode(c)
                except Exception: break
        walk(0, "")
        return nodes
    t_ref, t_new = tree_props(m_ref), tree_props(m_new)
    if set(t_ref) != set(t_new):
        die("G5b: el set de nodos cambio: +[%s] -[%s]"
            % (sorted(set(t_new) - set(t_ref))[:5], sorted(set(t_ref) - set(t_new))[:5]))
    ok("set de nodos identico (%d nodos, ninguno creado ni borrado)" % len(t_new))
    extras = []
    for p in t_ref:
        if p == KTZ_BUS:
            continue
        if t_ref[p] != t_new[p]:
            dif = [k for k in set(t_ref[p]) | set(t_new[p])
                   if t_ref[p].get(k) != t_new[p].get(k)]
            extras.append((p, dif))
    if extras:
        die("G5b: %d nodos fuera del bus cambiaron: %s" % (len(extras), extras[:5]))
    ok("cero cambios fuera de %s" % KTZ_BUS)

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
    open(os.path.join(WORK, "repack-s286-report.txt"), "w").write("\n".join(LOG) + "\n")
    shutil.copy(os.path.join(WORK, "repack-s286-report.txt"),
                os.path.join(R, "charge/repack-s286-report.txt"))

if __name__ == "__main__":
    main()
