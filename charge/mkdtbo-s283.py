"""
mkdtbo-s283.py — s282 + el phandle del KTZ8866 + la prop `backlight` del panel.

POR QUE: el build L39b hace que el driver del panel EXIJA el backlight externo
(`panel-xiaomi-o82-dualdsi.c:767-773`):

    ret = drm_panel_of_backlight(&ctx->panel);
    if (!ctx->panel.backlight)
        return dev_err_probe(dev, -ENODEV, "no 'backlight' phandle (KTZ8866 required)");

Pero el s282 tiene el nodo `ktz8866@11` (compatible correcto) y **NO** tiene
la propiedad `backlight = <...>` en el panel. Sin ella el panel NO PROBEA:
sin prepare() no hay reset, no hay DCS, no hay TDDI => pantalla negra
garantizada. Este dtbo lo arregla sin tocar el kernel.

MÉTODO: partir del payload del s282 (no del s281: así el `status="disabled"`
del nodo gpr, la trampa del ADSP, se conserva) e injertar DOS fragments con
`target-path` — la forma probada en este repo (frags 912/913 de
mkdtbo-s281.py): sin labels, sin resolucion de phandles.

  fragment@2300 -> /soc/qupv3_0_geni_se@ac0000/i2c@a80000/ktz8866@11
                   phandle = <0x2001>          (el nodo no tenia ninguno)
  fragment@2301 -> /soc/display-subsystem@ae00000/dsi@ae94000/panel@0
                   backlight = <0x2001>

0x2001 esta muy por encima del maximo del arbol (0xca8, 1791 phandles), asi
que no puede colisionar; aun asi G4 lo verifica explicitamente.

Gates (REGLAS del proyecto): fdtoverlay + uke-dtbo-check.py + paridad s282
(OPP, gpr disabled, iommus-DC, bootargs, touch) + G-BACKLIGHT nuevo.

Uso: python3 charge/mkdtbo-s283.py   (SOLO PC, NO flashea)
Salida: build/bootimg/s283-boot-dtbo-gpu-display-opp148-nogpr-bl.img
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
S282 = os.path.join(BOOTIMG, "s282-boot-dtbo-gpu-display-opp148-nogpr.img")
S282_SHA = "00c3410677eaa15d801024a2e9b0e0213cefd028a4372fee913b4d21eee168d0"
BASE = os.path.expanduser("~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img")
BASE_SHA = "3f973c78f7dc6a66f1acea363be27774c51ff174fbf71117ebe74c385547562e"
OUT = os.path.join(BOOTIMG, "s283-boot-dtbo-gpu-display-opp148-nogpr-bl.img")
WORK = "/tmp/dtbo-build-283"
PART_DTBO = 0x1800000
CHECK = os.path.join(R, "build/gates/uke-dtbo-check.py")

# --- rutas medidas sobre el arbol fusionado s282 (decompile.dts) ---
GPR_PATH   = "/soc/remoteproc-adsp@03000000/glink-edge/qcom,gpr"
KTZ_BUS_PATH = "/soc/qcom,qupv3_0_geni_se@ac0000/i2c@a80000"
KTZ_PATH   = "/soc/qcom,qupv3_0_geni_se@ac0000/i2c@a80000/ktz8866@11"
PANEL_PATH = "/soc/display-subsystem@ae00000/dsi@ae94000/panel@0"
KTZ_PHANDLE = 0x2001

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

FRAGS = (
    # El nodo ktz8866@11 esta en el ARBOL BASE y no tiene phandle. No se le puede
    # poner uno por target-path: fdtoverlay/libfdt reasigna el valor declarado y NO
    # repara las referencias que apuntan a el (medido: quedo 0x2001 -> 9522 y el
    # panel seguia en 0x2001 => referencia colgando, que wedgea el arranque).
    # La forma que SI funciona es redefinir el nodo dentro del overlay con una LABEL:
    # dtc -@ genera el phandle, lo mete en __symbols__ y resuelve <&ktz_bl_0>.
    '\tfragment@2300 {\n'
    '\t\ttarget-path = "%s";\n\n'
    '\t\t__overlay__ {\n'
    '\t\t\tktz_bl_0: ktz8866@11 {\n'
    '\t\t\t\tcompatible = "ktz,ktz8866";\n'
    '\t\t\t\treg = <0x11>;\n'
    '\t\t\t\tstatus = "ok";\n'
    '\t\t\t};\n'
    '\t\t};\n'
    '\t};\n'
    '\n'
    '\tfragment@2301 {\n'
    '\t\ttarget-path = "%s";\n\n'
    '\t\t__overlay__ {\n'
    '\t\t\tbacklight = <&ktz_bl_0>;\n'
    '\t\t};\n'
    '\t};\n' % (KTZ_BUS_PATH, PANEL_PATH)
)

def main():
    os.makedirs(WORK, exist_ok=True)
    log("=== G0 pins ===")
    for p, w, e in ((S282, S282_SHA, "s282"), (BASE, BASE_SHA, "base")):
        if not os.path.isfile(p) or sha(p) != w: die("G0: pin %s" % e)
    for t in ("dtc", "fdtoverlay", "fdtget"):
        if run("command -v %s" % t).returncode != 0: die("G0: falta %s" % t)
    if not os.path.isfile(CHECK): die("G0: falta %s" % CHECK)
    ok("pins y herramientas")

    log("=== G1: extraer payload s282 ===")
    pay = os.path.join(WORK, "s282.dtbo")
    r = subprocess.run([shutil.which("python3"), os.path.join(BOOTIMG, "dtbo-extract.py"),
                        S282, pay], capture_output=True, text=True)
    if r.returncode != 0: die("G1: extract s282")
    if run("dtc -I dtb -O dts -o %s/s282.dts %s 2>/dev/null" % (WORK, pay)).returncode != 0:
        die("G1: dtc s282")
    src = open(os.path.join(WORK, "s282.dts"), encoding="utf-8", errors="replace").read()
    # El s282 YA tiene un fragmento que apunta al panel (pinctrl-names="sleep"),
    # pero NO debe traer la prop `backlight = <...>`: eso es justo lo que anade este
    # script. Comprobar la PROPIEDAD, no la existencia del target-path.
    m = re.search(r'fragment@\d+ \{\s*target-path = "%s";.*?\n\t\};' % re.escape(PANEL_PATH),
                  src, re.S)
    if m and "backlight = <" in m.group(0):
        die("G1: el s282 ya trae la prop backlight del panel (revisar)")
    # ni una ktz_bl_0 label (el s282 no debe tocar el bus i2c del KTZ)
    if 'ktz_bl_0' in src:
        die("G1: el s282 ya declara ktz_bl_0 (revisar)")
    frags = re.findall(r"fragment@(\d+)", src)
    if max(int(x) for x in frags) >= 2300:
        die("G1: fragment@2300 colisiona (max=%d)" % max(int(x) for x in frags))
    ok("payload s282 (%d frags, max=%d)" % (len(set(frags)), max(int(x) for x in frags)))

    log("=== G2: injertar fragment@2300 (phandle) + @2301 (backlight) ===")
    i0 = src.rstrip().rfind("\n};")
    if i0 <= 0: die("G2: cierre del dts")
    open(os.path.join(WORK, "s283.dts"), "w").write(
        src.rstrip()[:i0] + "\n" + FRAGS + "};\n")
    pay2 = os.path.join(WORK, "s283.dtbo")
    rc = run("dtc -@ -I dts -O dtb -o %s %s" % (pay2, os.path.join(WORK, "s283.dts")))
    if rc.returncode != 0: die("G2: dtc s283: %s" % rc.stderr[-400:])
    ok("compila con 2 fragments añadidos")

    log("=== G3: fdtoverlay (gate 1) ===")
    m_new = os.path.join(WORK, "m283.dtb")
    if run("fdtoverlay -i %s -o %s %s" % (BASE, m_new, pay2)).returncode != 0:
        die("G3: fdtoverlay s283: %s" % run("fdtoverlay -i %s -o %s %s" % (BASE, m_new, pay2)).stderr[-300:])
    m_ref = os.path.join(WORK, "m282.dtb")
    if run("fdtoverlay -i %s -o %s %s" % (BASE, m_ref, pay)).returncode != 0:
        die("G3: fdtoverlay s282 (referencia)")
    ok("fdtoverlay verde (s283 y s282)")

    log("=== G4: G-BACKLIGHT (el gate que importa) ===")
    # OJO: fdtoverlay/libfdt REASIGNA los phandles que colisionan con la base, asi
    # que el 0x2001 pedido puede no ser el final. Lo que debe cumplirse es que el
    # panel apunte al phandle REAL del nodo ktz tras aplicar el overlay: es lo que
    # resuelve el core, y lo unico que importa (un phandle colgando wedgea el arranque).
    ph = gt(m_new, KTZ_PATH, "phandle", "-t u")
    bl = gt(m_new, PANEL_PATH, "backlight", "-t u")
    if not ph: die("G4: el nodo ktz no tiene phandle en el merged")
    if not bl: die("G4: el panel no tiene prop backlight en el merged")
    if ph != bl:
        die("G4: backlight=%s no apunta al phandle del ktz=%s (referencia colgando)"
            % (bl, ph))
    ok("panel.backlight = %s = phandle real del ktz (libfdt reasigno el 0x%x pedido)"
       % (ph, KTZ_PHANDLE))
    comp = gt(m_new, KTZ_PATH, "compatible", "-t s")
    if comp != "ktz,ktz8866": die("G4: compatible del ktz = %r" % comp)
    ok("compatible del ktz correcto: %s" % comp)
    if run("fdtget -l %s %s" % (m_new, PANEL_PATH)).returncode != 0:
        die("G4: el nodo panel no es legible en el merged")
    ok("nodo panel legible en el merged")

    log("=== G5: paridad s282 (nada mas puede haber cambiado) ===")
    if gt(m_new, GPR_PATH, "status", "-t s") != "disabled":
        die("G5: el gpr dejo de estar disabled")
    rates = {}
    for opp in ("opp-148648750", "opp-187500000", "opp-300000000", "opp-358000000"):
        v = gt(m_new, "/soc/display-subsystem@ae00000/dsi@ae94000/opp-table/" + opp, "opp-hz", "-t x")
        try: rates[opp] = int(v.split()[1], 16)
        except Exception: die("G5: %s ilegible (%s)" % (opp, v))
    if sorted(rates.values()) != [148648750, 187500000, 300000000, 358000000]:
        die("G5: tabla DSI = %s" % rates)
    if gt(m_new, "/soc/display-subsystem@ae00000/dsi@ae94000/panel@0", "compatible", "-t s") \
            != gt(m_ref, PANEL_PATH, "compatible", "-t s"):
        die("G5: el compatible del panel cambio")
    ok("gpr disabled + OPP 148648750 + panel identico: paridad s282")

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

    log("=== G7: gate 2 (uke-dtbo-check.py) ===")
    r = subprocess.run([shutil.which("python3"), CHECK, OUT, BASE],
                       capture_output=True, text=True)
    print(r.stdout[-1500:])
    if r.returncode != 0: die("G7: uke-dtbo-check.py RC=%d" % r.returncode)
    ok("uke-dtbo-check.py limpio")

    h = sha(OUT)
    log("\nPUBLICADO: %s\nsha256 = %s" % (OUT, h))
    open(os.path.join(WORK, "repack-s283-report.txt"), "w").write("\n".join(LOG) + "\n")
    shutil.copy(os.path.join(WORK, "repack-s283-report.txt"),
                os.path.join(R, "charge/repack-s283-report.txt"))

if __name__ == "__main__":
    main()
