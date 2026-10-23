"""
mkdtbo-s284.py — s283 + el arreglo de GENI/I2C/DMA (9 fragmentos).

POR QUE: medido en vivo el 13-oct, `/sys/class/i2c-adapter/` esta VACIO. Sin I2C:

  1. el KTZ8866 (backlight, i2c 0x11) nunca se une al bus -> no hay
     backlight_device -> `panel-xiaomi-o82-dualdsi: failed to find external
     backlight` -> el panel no probea -> no hay card1 -> el enlace DSI no se
     puede medir. Y el SPI del tactil tampoco (`Failed to get tx DMA ch`).

TRIPLE VALLA, cada una verificada contra el arbol del kernel:

  1) i2c-qcom-geni.c:1283-1286 — la tabla OF solo acepta `qcom,geni-i2c`
     y `qcom,geni-i2c-master-hub`. El DT trae **`qcom,i2c-geni`** (nombre
     downstream). of_match() NO CASA -> el driver nunca se une -> el probe
     ni se invoca. Esta es la valla mortal.
  2) Mismo nodo: el DT declara `clock-names="se-clk"` y el driver pide `"se"`
     (i2c-qcom-geni.c:1019), y los `dmas` del DT son de 5 celdas cuando la
     propiedad del driver es de 3.
  3) El PROVEEDOR: los dos nodos `qcom,gpi-dma` traen el compatible generico
     `qcom,gpi-dma`, que no esta en la tabla de `drivers/dma/qcom/gpi.c`
     (:2299-2311, que acepta `qcom,sm6350-gpi-dma`), y les faltan
     `dma-channels` y `dma-channel-mask`, que son **obligatorias**
     (gpi.c:2178 y :2185). Sin driver GPI no hay canales DMA para nadie.

Refutado por el camino (documentado para que no se repita): el nodo
`qcom,geni-se-qup` tiene `dmas` vacio pero **no es la causa** —
`qcom-geni-se.c:1571` no pide canales DMA, el motor GSI va por dentro.

ALCANCE: este fragmento arregla el I2C **y** el SPI (misma GPI-DMA), asi que
tambien desbloquea el tactil NT36532.

RENUMERACION: los fragmentos llegan como fragment@2200..2208 y el s283 ya
tiene un fragment@2200 (el del gpr disabled). Se renumeran a 2400..2408 antes
de inyectar. Un fragment duplicado con el mismo target-path haria que
fdtoverlay aplicase el ultimo y el otro se perdiera en silencio.

Gates (REGLAS del proyecto): fdtoverlay + uke-dtbo-check.py + paridad s283
(OPP, gpr disabled, panel backlight) + verificacion de los 3 fences.

Uso: python3 charge/mkdtbo-s284.py   (SOLO PC, NO flashea)
Salida: build/bootimg/s284-boot-dtbo-gpu-display-opp148-nogpr-bl-geni.img
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
OUT = os.path.join(BOOTIMG, "s284-boot-dtbo-gpu-display-opp148-nogpr-bl-geni.img")
WORK = "/tmp/dtbo-build-284"
PART_DTBO = 0x1800000
CHECK = os.path.join(R, "build/gates/uke-dtbo-check.py")

GPR_PATH   = "/soc/remoteproc-adsp@03000000/glink-edge/qcom,gpr"
KTZ_PATH   = "/soc/qcom,qupv3_0_geni_se@ac0000/i2c@a80000/ktz8866@11"
PANEL_PATH = "/soc/display-subsystem@ae00000/dsi@ae94000/panel@0"
OPP_BASE   = "/soc/display-subsystem@ae00000/dsi@ae94000/opp-table"

# Las rutas NO se hardcodean: se derivan de los `target-path` del propio
# fragmento (lección s284: la lista hardcodeada traía i2c@a80000/i2c@a8c000
# bajo qupv3_1 y spi@a84000 bajo qupv3_1, nodos que NO existen en la base —
# el wrapper1 usa direcciones 88xxxx, no a8xxxx — y G4 moría con
# "compatible=''" culpando al fragmento, que estaba bien).
# Lo único hardcodeado son los dos proveedores GPI (verificados en base:
# 0x1df=/soc/qcom,gpi-dma@a00000, 0x228=/soc/qcom,gpi-dma@800000).
GPI_OF_LITERAL = {0x1df: "/soc/qcom,gpi-dma@a00000",
                  0x228: "/soc/qcom,gpi-dma@800000"}

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
    # OJO: node y prop van entrecomillados porque el shell recorta todo lo
    # que sigue a un `#` (las props `#dma-cells`/`#clock-cells` volvían VACÍAS).
    return run("fdtget %s \"%s\" \"%s\" \"%s\"" % (t, m, node, prop)).stdout.strip()

def main():
    os.makedirs(WORK, exist_ok=True)
    log("=== G0 pins ===")
    for p, w, e in ((S283, S283_SHA, "s283"), (BASE, BASE_SHA, "base")):
        if not os.path.isfile(p) or sha(p) != w: die("G0: pin %s" % e)
    if not os.path.isfile(FRAG_SRC): die("G0: falta %s" % FRAG_SRC)
    for t in ("dtc", "fdtoverlay", "fdtget"):
        if run("command -v %s" % t).returncode != 0: die("G0: falta %s" % t)
    ok("pins, fragmento y herramientas")

    log("=== G1: extraer payload s283 ===")
    pay = os.path.join(WORK, "s283.dtbo")
    r = subprocess.run([shutil.which("python3"), os.path.join(BOOTIMG, "dtbo-extract.py"),
                        S283, pay], capture_output=True, text=True)
    if r.returncode != 0: die("G1: extract s283: %s" % r.stderr[-200:])
    if run("dtc -I dtb -O dts -o %s/s283.dts %s 2>/dev/null" % (WORK, pay)).returncode != 0:
        die("G1: dtc s283")
    src = open(os.path.join(WORK, "s283.dts"), encoding="utf-8", errors="replace").read()
    frags = [int(x) for x in re.findall(r"fragment@(\d+)", src)]
    mx = max(frags)
    if mx >= 2400: die("G1: renumeracion 2400+ colisiona con el s283 (max=%d)" % mx)
    if mx != 2301: die("G1: el s283 deberia acabar en 2301, veo %d" % mx)
    ok("payload s283 (%d frags, max=%d)" % (len(set(frags)), mx))

    log("=== G2: renumerar e inyectar los 9 fragmentos del GENI ===")
    raw = open(FRAG_SRC, encoding="utf-8", errors="replace").read()
    # Aislar SOLO el bloque de fragmentos: desde el primer `fragment@2200`
    # hasta la linea que cierra el /plugin/ (un "};" sin tabulador delante).
    start = raw.find("fragment@2200 {")
    if start < 0: die("G2: el fragmento no empieza por fragment@2200")
    tail = raw[start:]
    cierre = tail.rfind("\n};")          # el cierre del root, sin tabulador
    if cierre < 0: die("G2: no se encuentra el cierre del root")
    block = tail[:cierre]
    # contar SOLO definiciones (las menciones en comentarios `/* fragment@N: ... */`
    # no cuentan; contarlas daran 17 en vez de 9)
    defs = re.findall(r"^fragment@(\d+) \{", block, re.M)
    nf = len(defs)
    if nf != 9: die("G2: se esperaban 9 fragmentos, hay %d" % nf)
    # renumerar 2200..2208 -> 2400..2408. Se renumera TODO el bloque (incluidas
    # las menciones de los comentarios `/* fragment@22NN: ... */`) para que no
    # queden numeros viejos desincronizados; dtc descarta los comentarios.
    block = re.sub(r"fragment@22(\d\d)", lambda mm: "fragment@24%s" % mm.group(1), block)
    nums = sorted(int(x) for x in re.findall(r"^fragment@(24\d\d) \{", block, re.M))
    if nums != list(range(2400, 2409)):
        die("G2: renumeracion fallo -> %s" % nums)
    if max(frags) >= nums[0]:
        die("G2: colision %d vs %d" % (max(frags), nums[0]))
    ok("9 fragmentos renumerados a 2400..2408, sin colision con %d" % mx)

    i0 = src.rstrip().rfind("\n};")
    if i0 <= 0: die("G2: cierre del dts del s283")
    open(os.path.join(WORK, "s284.dts"), "w").write(
        src.rstrip()[:i0] + "\n" + block + "\n};\n")
    pay2 = os.path.join(WORK, "s284.dtbo")
    rc = run("dtc -@ -I dts -O dtb -o %s %s" % (pay2, os.path.join(WORK, "s284.dts")))
    if rc.returncode != 0: die("G2: dtc s284: %s" % rc.stderr[-500:])
    ok("compila con los 9 fragmentos anadidos")

    log("=== G3: fdtoverlay (gate 1: el ABL haria lo mismo) ===")
    m_new = os.path.join(WORK, "m284.dtb")
    rr = run("fdtoverlay -i %s -o %s %s" % (BASE, m_new, pay2))
    if rr.returncode != 0: die("G3: fdtoverlay s284: %s" % (rr.stdout + rr.stderr)[-400:])
    m_ref = os.path.join(WORK, "m283.dtb")
    if run("fdtoverlay -i %s -o %s %s" % (BASE, m_ref, pay)).returncode != 0:
        die("G3: fdtoverlay s283 (referencia)")
    ok("fdtoverlay verde (s284 y s283)")

    log("=== G4: las TRES vallas, una por una (rutas derivadas del fragmento) ===")
    # Derivar los 9 targets del propio bloque ya renumerado: por cada
    # `target-path` extraer el compatible esperado del texto del fragmento.
    # Así el validador no puede desincronizarse del fragmento nunca más.
    targets = []  # (path, compatible_esperado, es_gpi)
    for m in re.finditer(r"^\s*fragment@24\d\d \{\s*\n\s*target-path = \"([^\"]+)\";(.*?)^\s*\};",
                         block, re.M | re.S):
        path, body = m.group(1), m.group(2)
        mc = re.search(r"compatible = ([^;]+);", body)
        if not mc:
            die("G4: el fragmento para %s no declara compatible (revisar)" % path)
        targets.append((path, mc.group(1).strip()))
    if len(targets) != 9:
        die("G4: se esperaban 9 targets derivados, hay %d" % len(targets))
    geni_targets = [t for t in targets if "gpi-dma" not in t[0]]
    gpi_targets = [t for t in targets if "gpi-dma" in t[0]]
    if len(geni_targets) != 7 or len(gpi_targets) != 2:
        die("G4: derivados %d GENI + %d GPI (esperado 7+2)" % (len(geni_targets), len(gpi_targets)))
    ok("9 target-path derivados del fragmento: 7 GENI + 2 GPI")

    # valla 1+2: compatible y clock-names de cada GENI tocado por el fragmento
    for n, comp_esp in geni_targets:
        c = gt(m_new, n, "compatible", "-t s")
        if c not in comp_esp.replace('"', '').split(", "):
            die("G4: %s compatible=%r (fragmento pide %s; el driver NO acepta otro)"
                % (n, c, comp_esp))
        cn = gt(m_new, n, "clock-names", "-t s")
        if cn != "se":
            die("G4: %s clock-names=%r (el driver pide 'se')" % (n, cn))
        dn = gt(m_new, n, "dma-names", "-t s")
        # fdtget -t s imprime la stringlist separada por espacios: "tx rx"
        if dn.split() != ["tx", "rx"]:
            die("G4: %s dma-names=%r (esperado 'tx rx')" % (n, dn))
    ok("valla 1+2: %d/7 GENI con compatible mainline + clock-names=se + dma-names=tx,rx"
       % len(geni_targets))

    # valla 2b: los dmas de cada GENI usan 3 celdas y sus phandles resuelven
    # al proveedor GPI de su wrapper (el literal del fragmento debe coincidir
    # con el phandle REAL del proveedor en el merged; un literal colgando
    # wedgea el arranque igual que un __local_fixups__ colgando).
    for n, comp_esp in geni_targets:
        raw = gt(m_new, n, "dmas", "-t x")
        try:
            cells = [int(x, 16) for x in raw.split()]
        except ValueError:
            die("G4: %s dmas ilegible (%r)" % (n, raw))
        if len(cells) != 8 or len(cells) % 4 != 0:
            die("G4: %s dmas tiene %d celdas (esperado 8 = 2 entradas de ph+3)"
                % (n, len(cells)))
        provs = [c for i, c in enumerate(cells) if i % 4 == 0]
        # proveedor esperado: el literal que el fragmento escribió para este nodo
        mbody = re.search(r'target-path = "%s";(.*?)^\s*\};' % re.escape(n),
                          block, re.M | re.S)
        lit = int(re.search(r"dmas = <(0x[0-9a-fA-F]+)", mbody.group(1)).group(1), 16)
        prov_esp = GPI_OF_LITERAL.get(lit)
        if prov_esp is None:
            die("G4: %s usa literal 0x%x desconocido (solo 0x1df/0x228 verificados)"
                % (n, lit))
        ph_real = gt(m_new, prov_esp, "phandle", "-t x")
        if not all(p == int(ph_real, 16) for p in provs):
            die("G4: %s dmas apunta a %s pero el phandle real de %s es %s (colgando)"
                % (n, ["0x%x" % p for p in provs], prov_esp, ph_real))
        # proto esperado: 3=I2C, 1=SPI (include/dt-bindings/dma/qcom-gpi.h)
        protos = [cells[i + 3] for i in range(0, len(cells), 4)]
        proto_ok = 3 if "i2c" in comp_esp else 1
        if any(p != proto_ok for p in protos):
            die("G4: %s proto=%s (esperado %d para %s)" % (n, protos, proto_ok, comp_esp))
    ok("valla 2b: 7/7 dmas con phandles al GPI de su wrapper + proto correcto")

    # valla 3: el proveedor GPI-DMA
    for n, comp_esp in gpi_targets:
        c = gt(m_new, n, "compatible", "-t s")
        if "qcom,sm6350-gpi-dma" not in c:
            die("G4: %s compatible=%r (gpi.c:2300 pide sm6350)" % (n, c))
        dc = gt(m_new, n, "#dma-cells", "-t u")
        if dc.strip() != "3":
            die("G4: %s #dma-cells=%r (gpi_of_dma_xlate exige >=3)" % (n, dc))
        ch = gt(m_new, n, "dma-channels", "-t u")
        mk = gt(m_new, n, "dma-channel-mask", "-t x")
        if not ch or not mk:
            die("G4: %s sin dma-channels/dma-channel-mask (gpi.c:2178/2185 las exige)" % n)
    ok("valla 3: 2/2 gpi-dma con compatible sm6350 + #dma-cells=3 + channels + mask")

    log("=== G5: paridad s283 (nada mas puede haber cambiado) ===")
    if gt(m_new, GPR_PATH, "status", "-t s") != "disabled":
        die("G5: el gpr dejo de estar disabled (era la trampa del ADSP)")
    ph = gt(m_new, KTZ_PATH, "phandle", "-t u")
    bl = gt(m_new, PANEL_PATH, "backlight", "-t u")
    if not ph or ph != bl:
        die("G5: backlight=%s dejo de apuntar al ktz=%s (referencia colgando)" % (bl, ph))
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
    ok("gpr disabled + backlight resuelto + OPP 148648750 + panel identico: paridad s283")

    log("=== G5b: diff exhaustivo m283 vs m284 (el overlay no puede tocar nada mas) ===")
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
    # targets derivados en G4 (GENI+GPI): son los únicos que pueden diferir
    permitidos = set(p for p, _ in targets)
    extras = []
    for p in t_ref:
        if p in permitidos:
            continue
        if t_ref[p] != t_new[p]:
            dif = [k for k in set(t_ref[p]) | set(t_new[p])
                   if t_ref[p].get(k) != t_new[p].get(k)]
            extras.append((p, dif))
    if extras:
        die("G5b: %d nodos fuera de los 9 fragmentos cambiaron: %s" % (len(extras), extras[:5]))
    ok("cero cambios fuera de los 9 target-path del fragmento")

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
    open(os.path.join(WORK, "repack-s284-report.txt"), "w").write("\n".join(LOG) + "\n")
    shutil.copy(os.path.join(WORK, "repack-s284-report.txt"),
                os.path.join(R, "charge/repack-s284-report.txt"))

if __name__ == "__main__":
    main()
