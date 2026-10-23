"""
mkdtbo-s288.py — s287 + ADSP icc (fragment@2404). Ciclo L66 (15-oct).

POR QUE: ADSP-AUTH-22.md (MEDIDO 14-oct): el TZ rechaza AUTH_AND_RESET(1) con -22
porque el kernel no vota los buses DDR — L19 anulaba el icc_get a NULL y el DT vendor
apunta a 0x187/0x189 sin driver. Fix 2 piezas: revert L19 (kernel k52L66, otro
subagente) + este dtbo que repunta interconnects del ADSP a mc_virt, como el @1301
del hermano (ledger #398, s196, ADSP OK en Ubuntu 25-sep).

CAMBIO ÚNICO vs s287: 1 fragmento (2404; s287 acaba en 2403) al nodo
/soc/remoteproc-adsp@03000000: interconnects = <0x188 3 0x188 512> (mc_virt,
MASTER_LLCC=3 -> SLAVE_EBI1=512, verificado en palawan.c:1851-1852) + cx-supply
vacía (fiel al @1301; con L18 es redundante pero inofensiva).
Fuente del literal: ~/proyectos/ubuntu-permanente/criticas/ronda-29/ADSP-Y-CARGA.md §2.1.

Gates: fdtoverlay + ADSP cambia (interconnects exactos + cx-supply vacía) + paridad
s287 (gpr disabled, backlight, OPP, panel, GENI, GPI) + diff exhaustivo libfdt (SOLO
el nodo ADSP puede diferir, y solo en interconnects/cx-supply) + uke-dtbo-check.py.

Uso: python3 charge/mkdtbo-s288.py   (SOLO PC, NO flashea)
Salida: build/bootimg/s288-boot-dtbo-gpu-display-gpi-i2c-ktz-vci-adsp.img
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
S287 = os.path.join(BOOTIMG, "s287-boot-dtbo-gpu-display-gpi-i2c-ktz-vci.img")
S287_SHA = "9f3d2b0043921d9a2090f53cdccf8e97df9038f1cd82a4deb1b6f3da0a4c09e9"
BASE = os.path.expanduser("~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img")
BASE_SHA = "3f973c78f7dc6a66f1acea363be27774c51ff174fbf71117ebe74c385547562e"
OUT = os.path.join(BOOTIMG, "s288-boot-dtbo-gpu-display-gpi-i2c-ktz-vci-adsp.img")
WORK = "/tmp/dtbo-build-288"
PART_DTBO = 0x1800000
CHECK = os.path.join(R, "build/gates/uke-dtbo-check.py")

ADSP_PATH  = "/soc/remoteproc-adsp@03000000"
MCVIRT_PATH = "/soc/interconnect@1"   # phandle 0x188, qcom,cliffs-mc_virt, bound en L64
GPR_PATH   = "/soc/remoteproc-adsp@03000000/glink-edge/qcom,gpr"
KTZ_BUS    = "/soc/qcom,qupv3_0_geni_se@ac0000/i2c@a80000"
KTZ_PATH   = KTZ_BUS + "/ktz8866@11"
PANEL_PATH = "/soc/display-subsystem@ae00000/dsi@ae94000/panel@0"
OPP_BASE   = "/soc/display-subsystem@ae00000/dsi@ae94000/opp-table"
GPI_NODES  = ["/soc/qcom,gpi-dma@a00000", "/soc/qcom,gpi-dma@800000"]
GENI_INTACTOS = [
    "/soc/qcom,qupv3_0_geni_se@ac0000/i2c@a8c000",
    "/soc/qcom,qupv3_0_geni_se@ac0000/spi@a84000",
    "/soc/qcom,qupv3_0_geni_se@ac0000/spi@a90000",
    "/soc/qcom,qupv3_1_geni_se@8c0000/i2c@880000",
    "/soc/qcom,qupv3_1_geni_se@8c0000/i2c@88c000",
    "/soc/qcom,qupv3_1_geni_se@8c0000/i2c@890000",
]
GPI_BUS_WRAPPER0 = "/soc/qcom,gpi-dma@a00000"   # literal 0x1df
L19_PATH = "/soc/rsc@17a00000/drv@2/rpmh-regulator-ldob19/regulator-pmxr2230-l19"

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
    for p, w, e in ((S287, S287_SHA, "s287"), (BASE, BASE_SHA, "base")):
        if not os.path.isfile(p) or sha(p) != w: die("G0: pin %s" % e)
    if not os.path.isfile(CHECK): die("G0: falta %s" % CHECK)
    if not os.path.isfile(os.path.join(BOOTIMG, "dtbo-extract.py")):
        die("G0: falta dtbo-extract.py")
    for t in ("dtc", "fdtoverlay", "fdtget"):
        if run("command -v %s" % t).returncode != 0: die("G0: falta %s" % t)
    ok("pins (s287 9f3d2b00 + base 3f973c78) y herramientas")

    log("=== G1: extraer payload s287 ===")
    pay = os.path.join(WORK, "s287.dtbo")
    r = subprocess.run([shutil.which("python3"), os.path.join(BOOTIMG, "dtbo-extract.py"),
                        S287, pay], capture_output=True, text=True)
    if r.returncode != 0: die("G1: extract s287: %s" % r.stderr[-200:])
    if run("dtc -I dtb -O dts -o %s/s287.dts %s 2>/dev/null" % (WORK, pay)).returncode != 0:
        die("G1: dtc s287")
    src = open(os.path.join(WORK, "s287.dts"), encoding="utf-8", errors="replace").read()
    frags = [int(x) for x in re.findall(r"^[ \t]*fragment@(\d+) \{", src, re.M)]
    mx = max(frags)
    if mx != 2403: die("G1: el s287 deberia acabar en 2403 (s286=2402 + vci 2403), veo %d" % mx)
    if "qcom,geni-i2c" not in src: die("G1: el s287 no trae el bus GENI del KTZ (revisar)")
    if "vci-supply" not in src: die("G1: el s287 no trae el vci-supply del panel (revisar)")
    ok("payload s287 (%d frags, max=%d), bus KTZ + vci presentes" % (len(set(frags)), mx))

    log("=== G2: injertar fragment@2404 (ADSP icc -> mc_virt) ===")
    inj = ('\tfragment@2404 {\n'
           '\t\ttarget-path = "%s";\n\n'
           '\t\t__overlay__ {\n'
           '\t\t\tinterconnects = <0x188 3 0x188 512>;\n'
           '\t\t\tcx-supply;\n'
           '\t\t};\n'
           '\t};\n' % ADSP_PATH)
    open(os.path.join(WORK, "s288.dts"), "w").write(
        src.rstrip()[:src.rstrip().rfind("\n};")] + "\n" + inj + "};\n")
    pay2 = os.path.join(WORK, "s288.dtbo")
    rc = run("dtc -@ -I dts -O dtb -o %s %s" % (pay2, os.path.join(WORK, "s288.dts")))
    if rc.returncode != 0: die("G2: dtc s288: %s" % rc.stderr[-500:])
    ok("compila con 1 fragmento anadido (2404, ADSP icc en %s)" % ADSP_PATH)

    log("=== G3: fdtoverlay (gate 1: el ABL haria lo mismo) ===")
    m_new = os.path.join(WORK, "m288.dtb")
    rr = run("fdtoverlay -i %s -o %s %s" % (BASE, m_new, pay2))
    if rr.returncode != 0: die("G3: fdtoverlay s288: %s" % (rr.stdout + rr.stderr)[-400:])
    m_ref = os.path.join(WORK, "m287.dtb")
    if run("fdtoverlay -i %s -o %s %s" % (BASE, m_ref, pay)).returncode != 0:
        die("G3: fdtoverlay s287 (referencia)")
    ok("fdtoverlay verde (s288 y s287)")

    log("=== G4: el ADSP cambia a mc_virt, y SOLO el ===")
    # mc_virt existe con el phandle que usa el fragmento
    if gt(m_new, MCVIRT_PATH, "compatible", "-t s") != "qcom,cliffs-mc_virt":
        die("G4: %s no es cliffs-mc_virt" % MCVIRT_PATH)
    if gt(m_new, MCVIRT_PATH, "phandle", "-t x") != "188":
        die("G4: phandle de mc_virt != 0x188 (el fragmento apunta a 0x188)")
    ok("mc_virt = %s, phandle 0x188, cliffs-mc_virt" % MCVIRT_PATH)
    # interconnects exactos del @1301 del hermano
    icc = gt(m_new, ADSP_PATH, "interconnects", "-t x").split()
    if icc != ["188", "3", "188", "200"]:
        die("G4: %s interconnects=%s (esperado 188 3 188 200 = 0x188 3 0x188 512)"
            % (ADSP_PATH, icc))
    ok("interconnects = <0x188 3 0x188 512> (MASTER_LLCC=3 -> SLAVE_EBI1=512)")
    # cx-supply presente y vacía (fdtget RC=0 + salida vacía)
    cxr = run("fdtget '%s' '%s' cx-supply" % (m_new, ADSP_PATH))
    if cxr.returncode != 0: die("G4: cx-supply ausente en el merged s288")
    if cxr.stdout.strip() != "": die("G4: cx-supply no vacia: %r" % cxr.stdout.strip())
    ok("cx-supply presente y vacia (of_parse_phandle NULL -> -ENODEV -> ausente)")
    # la referencia s287 sigue con el vendor (los 0x187/0x189 sin driver)
    icc_ref = gt(m_ref, ADSP_PATH, "interconnects", "-t x").split()
    if len(icc_ref) != 8 or icc_ref[0] != "187":
        die("G4: el s287 no trae el vendor esperado (%s)" % icc_ref)
    ok("referencia s287 con vendor (0x187../0x189.., 8 celdas): el cambio es solo del s288")
    # names intactos (el @1301 no los toca, igual que en el hermano)
    if gt(m_new, ADSP_PATH, "interconnect-names", "-t s") != gt(m_ref, ADSP_PATH, "interconnect-names", "-t s"):
        die("G4: interconnect-names cambio (el fragmento no debe tocarlo)")
    ok("interconnect-names intactos")

    log("=== G5: paridad s287 ===")
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
    for k in ("compatible", "reg", "reset-gpios", "vddil8b-supply", "vci-supply"):
        if gt(m_new, PANEL_PATH, k) != gt(m_ref, PANEL_PATH, k):
            die("G5: el panel cambio en %s" % k)
    ok("gpr disabled + backlight resuelto + OPP 148648750 + panel identico: paridad s287")
    # KTZ bus + GPI + GENI intactos
    if gt(m_new, KTZ_BUS, "compatible", "-t s") != "qcom,geni-i2c":
        die("G5: el bus KTZ perdio el compatible")
    for n in GPI_NODES:
        if gt(m_new, n, "compatible", "-t s") != gt(m_ref, n, "compatible", "-t s"):
            die("G5: %s cambio respecto a s287" % n)
    for n in GENI_INTACTOS:
        for k in ("compatible", "clock-names", "dmas", "dma-names"):
            if gt(m_new, n, k) != gt(m_ref, n, k):
                die("G5: %s cambio en %s" % (n, k))
    ok("KTZ + 2 gpi-dma + 6 GENI identicos a s287")

    log("=== G5b: diff exhaustivo m287 vs m288 (SOLO el ADSP puede diferir) ===")
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
        if p == ADSP_PATH:
            continue
        if t_ref[p] != t_new[p]:
            dif = [k for k in set(t_ref[p]) | set(t_new[p])
                   if t_ref[p].get(k) != t_new[p].get(k)]
            extras.append((p, dif))
    if extras:
        die("G5b: %d nodos fuera del ADSP cambiaron: %s" % (len(extras), extras[:5]))
    if t_ref.get(ADSP_PATH) == t_new.get(ADSP_PATH):
        die("G5b: el ADSP no cambio (el fragmento no aplico)")
    difa = [k for k in set(t_ref[ADSP_PATH]) | set(t_new[ADSP_PATH])
            if t_ref[ADSP_PATH].get(k) != t_new[ADSP_PATH].get(k)]
    if sorted(difa) != ["cx-supply", "interconnects"]:
        die("G5b: el ADSP cambio en %s (esperado solo interconnects+cx-supply)" % difa)
    ok("cero cambios fuera del ADSP; en el ADSP SOLO interconnects + cx-supply")

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
    open(os.path.join(WORK, "repack-s288-report.txt"), "w").write("\n".join(LOG) + "\n")
    shutil.copy(os.path.join(WORK, "repack-s288-report.txt"),
                os.path.join(R, "charge/repack-s288-report.txt"))

if __name__ == "__main__":
    main()
