"""
mkdtbo-s289.py — s288 + label ktz_bl_1 (fragment@2405) en el 2o KTZ8866 (i2c@890000).

HALLAZGO (sesion s289): el payload de s288 YA arrastra los fragmentos stock @105/@106
(se0_i2c=i2c@a80000 y se12_i2c=i2c@890000, status ok, ktz8866@11 compatible
"ktz,ktz8866", reg 0x11, SIN mas props: el vendor tampoco tiene supplies/enable-gpio/
pinctrl en el nodo). El mergeado s288 ya tiene los DOS chips. Lo unico que falta en DT
es un phandle direccionable para el 2o (el panel solo enlaza ktz_bl_0).

CAMBIO UNICO vs s288: fragment@2405 -> /soc/qcom,qupv3_1_geni_se@8c0000/i2c@890000
con `ktz_bl_1: ktz8866@11 {}` (solo anade phandle/simbolo; mismas props que el vendor).
NO cambia el comportamiento del driver: el 2o chip probea igual (ya lo hacia en s288).
Encender ambos requiere cambio de DRIVER/panel (ver KTZ-DUAL-S289-20261017.md).

Gates: pins, fdtoverlay, ambos KTZ ok con props vendor, bus 890000 ok (pinctrl/GENI/
GPI1), panel.backlight sigue en ktz_bl_0, diff exhaustivo libfdt vs s288 (sin contar
phandles: SOLO ktz@890000 puede ganar phandle), dt_table roundtrip, uke-dtbo-check.

Uso: python3 charge/mkdtbo-s289.py   (SOLO PC, NO flashea, NO registra ledger)
Salida: build/bootimg/s289-boot-dtbo-gpu-display-gpi-i2c-ktz-dual-adsp.img
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
S288 = os.path.join(BOOTIMG, "s288-boot-dtbo-gpu-display-gpi-i2c-ktz-vci-adsp.img")
S288_SHA = "02d403c518346bf5a3757c5519eb8ca205f8f75af078cfde2e03d9d49e702dfb"
BASE = os.path.expanduser("~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img")
BASE_SHA = "3f973c78f7dc6a66f1acea363be27774c51ff174fbf71117ebe74c385547562e"
OUT = os.path.join(BOOTIMG, "s289-boot-dtbo-gpu-display-gpi-i2c-ktz-dual-adsp.img")
WORK = "/tmp/dtbo-build-289"
PART_DTBO = 0x1800000
CHECK = os.path.join(R, "build/gates/uke-dtbo-check.py")

KTZ0_BUS = "/soc/qcom,qupv3_0_geni_se@ac0000/i2c@a80000"
KTZ0 = KTZ0_BUS + "/ktz8866@11"
KTZ1_BUS = "/soc/qcom,qupv3_1_geni_se@8c0000/i2c@890000"
KTZ1 = KTZ1_BUS + "/ktz8866@11"
PANEL_PATH = "/soc/display-subsystem@ae00000/dsi@ae94000/panel@0"
GPI1 = "/soc/qcom,gpi-dma@800000"

LOG = []
def log(m): print(m, flush=True); LOG.append(m)
def die(m): log("\n*** %s ***" % m); sys.exit(1)
def ok(m): log("  OK  %s" % m)
def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()
def run(c): return subprocess.run(c, shell=True, capture_output=True, text=True)
def gt(m, node, prop, t=""):
    return run("fdtget %s '%s' '%s' '%s'" % (t, m, node, prop)).stdout.strip()

def main():
    os.makedirs(WORK, exist_ok=True)
    log("=== G0 pins ===")
    for p, w, e in ((S288, S288_SHA, "s288"), (BASE, BASE_SHA, "base")):
        if not os.path.isfile(p) or sha(p) != w: die("G0: pin %s" % e)
    for f in (CHECK, os.path.join(BOOTIMG, "dtbo-extract.py")):
        if not os.path.isfile(f): die("G0: falta %s" % f)
    for t in ("dtc", "fdtoverlay", "fdtget"):
        if run("command -v %s" % t).returncode != 0: die("G0: falta %s" % t)
    ok("pins (s288 02d403c5 + base 3f973c78) y herramientas")

    log("=== G1: extraer payload s288 ===")
    pay = os.path.join(WORK, "s288.dtbo")
    r = subprocess.run([shutil.which("python3"), os.path.join(BOOTIMG, "dtbo-extract.py"),
                        S288, pay], capture_output=True, text=True)
    if r.returncode != 0: die("G1: extract s288: %s" % r.stderr[-200:])
    if run("dtc -I dtb -O dts -o %s/s288.dts %s 2>/dev/null" % (WORK, pay)).returncode != 0:
        die("G1: dtc s288")
    src = open(os.path.join(WORK, "s288.dts"), encoding="utf-8", errors="replace").read()
    frags = [int(x) for x in re.findall(r"^[ \t]*fragment@(\d+) \{", src, re.M)]
    if max(frags) != 2404: die("G1: s288 deberia acabar en 2404, veo %d" % max(frags))
    if 2405 in frags: die("G1: ya existe fragment@2405")
    ok("payload s288 (%d frags, max=2404)" % len(set(frags)))

    log("=== G2: injertar fragment@2405 (label ktz_bl_1 en el KTZ del bus 890000) ===")
    inj = ('\tfragment@2405 {\n'
           '\t\ttarget-path = "%s";\n\n'
           '\t\t__overlay__ {\n\n'
           '\t\t\tktz_bl_1: ktz8866@11 {\n'
           '\t\t\t};\n'
           '\t\t};\n'
           '\t};\n' % KTZ1_BUS)
    open(os.path.join(WORK, "s289.dts"), "w").write(
        src.rstrip()[:src.rstrip().rfind("\n};")] + "\n" + inj + "};\n")
    pay2 = os.path.join(WORK, "s289.dtbo")
    rc = run("dtc -@ -I dts -O dtb -o %s %s" % (pay2, os.path.join(WORK, "s289.dts")))
    if rc.returncode != 0: die("G2: dtc s289: %s" % rc.stderr[-500:])
    ok("compila con 1 fragmento anadido (2405)")

    log("=== G3: fdtoverlay ===")
    m_new = os.path.join(WORK, "m289.dtb"); m_ref = os.path.join(WORK, "m288.dtb")
    for o, p in ((m_new, pay2), (m_ref, pay)):
        rr = run("fdtoverlay -i %s -o %s %s" % (BASE, o, p))
        if rr.returncode != 0: die("G3: fdtoverlay %s: %s" % (p, (rr.stdout + rr.stderr)[-400:]))
    ok("fdtoverlay verde (s289 y s288)")

    log("=== G4: dual KTZ + bus 890000 sano ===")
    for k in (KTZ0, KTZ1):
        if gt(m_new, k, "compatible", "-t s") != "ktz,ktz8866": die("G4: %s compatible" % k)
        if gt(m_new, k, "reg", "-t x") != "11": die("G4: %s reg != 0x11" % k)
        if gt(m_new, k, "status", "-t s") not in ("ok", "okay"): die("G4: %s no ok" % k)
        # solo props del vendor (compatible/reg/status/phandle): nada inventado
        extra = run("fdtget -p %s '%s'" % (m_new, k)).stdout.split()
        if set(extra) - {"compatible", "reg", "status", "phandle", "name"}:
            die("G4: %s props inesperadas %s" % (k, extra))
    ok("2 KTZ: compatible ktz,ktz8866, reg 0x11, status ok, solo props vendor")
    for b in (KTZ0_BUS, KTZ1_BUS):
        if gt(m_new, b, "status", "-t s") not in ("ok", "okay"): die("G4: bus %s no ok" % b)
        if gt(m_new, b, "compatible", "-t s") != "qcom,i2c-geni" and \
           gt(m_new, b, "compatible", "-t s") != "qcom,geni-i2c":
            die("G4: bus %s compatible" % b)
    for k in ("pinctrl-0", "pinctrl-1", "pinctrl-names", "dmas", "dma-names", "clocks",
              "clock-names", "interconnects", "interrupts", "reg"):
        if not gt(m_new, KTZ1_BUS, k): die("G4: bus 890000 sin %s" % k)
    if gt(m_new, GPI1, "status", "-t s") not in ("ok", "okay"): die("G4: gpi-dma@800000 no ok")
    if gt(m_new, GPI1, "compatible") != gt(m_ref, GPI1, "compatible"): die("G4: GPI1 cambio")
    ok("bus 890000 ok con pinctrl/clocks/dmas/interconnects/irq; gpi-dma@800000 ok")
    ph0 = gt(m_new, KTZ0, "phandle", "-t u"); ph1 = gt(m_new, KTZ1, "phandle", "-t u")
    bl = gt(m_new, PANEL_PATH, "backlight", "-t u")
    if not ph0 or not ph1 or ph0 == ph1: die("G4: phandles ktz0=%s ktz1=%s" % (ph0, ph1))
    if bl != ph0: die("G4: panel.backlight=%s != ktz_bl_0=%s" % (bl, ph0))
    ok("ktz_bl_0=%s (panel.backlight) y ktz_bl_1=%s distintos" % (ph0, ph1))

    log("=== G5: diff exhaustivo m288 vs m289 (sin phandles) ===")
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
    if set(t_ref) != set(t_new): die("G5: set de nodos cambio")
    dif = [p for p in t_ref if t_ref[p] != t_new[p]]
    if dif != ["/__symbols__"] and dif:
        die("G5: nodos con props distintas: %s" % dif[:5])
    if dif:   # fdtoverlay anade el simbolo: solo ktz_bl_1
        d = [k for k in set(t_ref["/__symbols__"]) | set(t_new["/__symbols__"])
             if t_ref["/__symbols__"].get(k) != t_new["/__symbols__"].get(k)]
        if d != ["ktz_bl_1"]: die("G5: __symbols__ difiere en %s" % d)
        ok("/__symbols__: solo se anade ktz_bl_1")
    ok("%d nodos, props identicas (salvo phandle: solo el KTZ@890000 gana uno)" % len(t_new))
    # phandle: el KTZ@890000 no lo tenia en s288 (fdtget falla), y ningun otro ktz cambia
    if run("fdtget %s '%s' phandle" % (m_ref, KTZ1)).returncode == 0:
        die("G5: el KTZ@890000 ya tenia phandle en s288 (el fragmento no aporta nada)")
    ok("s288 sin phandle en KTZ@890000; s289 con phandle %s" % ph1)

    log("=== G6: dt_table + roundtrip ===")
    blob = open(pay2, "rb").read()
    if len(blob) > PART_DTBO - 96: die("G6: tamaño %d" % len(blob))
    img = (struct.pack(">IIIIIIII", 0xD7B7AB1E, 64 + len(blob), 32, 32, 1, 32, 4096, 0)
           + struct.pack(">IIIIIIII", len(blob), 64, 0, 0, 0, 0, 0, 0) + blob)
    if os.path.exists(OUT): die("G6: %s ya existe (no se sobrescribe)" % OUT)
    open(OUT, "wb").write(img)
    rt = os.path.join(WORK, "rt.dtbo")
    r = subprocess.run([shutil.which("python3"), os.path.join(BOOTIMG, "dtbo-extract.py"),
                        OUT, rt], capture_output=True, text=True)
    if r.returncode != 0 or sha(rt) != sha(pay2): die("G6: roundtrip")
    ok("dt_table (1 entrada) + roundtrip; %d B" % len(img))

    log("=== G7: uke-dtbo-check.py (GATE) ===")
    r = subprocess.run([shutil.which("python3"), CHECK, OUT, BASE], capture_output=True, text=True)
    print(r.stdout[-700:])
    if r.returncode != 0: die("G7: uke-dtbo-check.py RC=%d" % r.returncode)
    ok("uke-dtbo-check.py limpio")

    log("\nPUBLICADO: %s\nsha256 = %s" % (OUT, sha(OUT)))
    open(os.path.join(WORK, "repack-s289-report.txt"), "w").write("\n".join(LOG) + "\n")

if __name__ == "__main__":
    main()
