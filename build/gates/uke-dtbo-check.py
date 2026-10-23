#!/usr/bin/env python3
"""uke-dtbo-check.py — reproduce la aplicacion del dtbo (libfdt, igual que el ABL) y
verifica que TODAS las referencias del stack display resuelven a nodos existentes.

Uso: uke-dtbo-check.py <dtbo.img> [base.dtb]
  1) extrae el payload del dt_table del .img
  2) fdtoverlay -i base.dtb -o merged.dtb payload.dtb  (misma libfdt que usa el ABL)
  3) recorre el arbol merged con pylibfdt y comprueba los phandles de las props criticas
Salida: OK / lista de problemas. Caza el error clasico: referencia colgante por phandle
literal no reubicado (leccion del OPP del GMU, ledger #391) y nodos que no existen
porque el fragmento no se aplico.
"""
import sys, struct, subprocess

PROPS_ONE_REF = ("power-domains", "resets", "operating-points-v2", "remote-endpoint",
                 "pinctrl-0", "pinctrl-1", "pinctrl-2", "phys", "assigned-clocks",
                 "assigned-clock-parents", "interconnects", "iommus")
PROPS_GPIO = ("reset-gpios", "gpio", "enable-gpios", "cs-gpios")
PROPS_CLOCKS = ("clocks",)
SUPPLY_SUFFIX = "-supply"

NODES_REPORT = [
    "/soc/clock-controller@af00000",
    "/soc/display-subsystem@ae00000",
    "/soc/display-subsystem@ae00000/display-controller@ae01000",
    "/soc/display-subsystem@ae00000/dsi@ae94000",
    "/soc/display-subsystem@ae00000/dsi@ae94000/panel@0",
    "/soc/display-subsystem@ae00000/dsi@ae96000",
    "/soc/display-subsystem@ae00000/phy@ae95000",
    "/soc/display-subsystem@ae00000/phy@ae97000",
]
NODES_DISPLAY_EXTRA = ["/soc/uke-regulator-display-vsp",
                       "/soc/uke-regulator-display-vsn",
                       "/soc/pinctrl@f000000/uke-pmx-sde"]
NODES_CHARGE = ["/soc/qcom,pmic_glink_log", "/soc/remoteproc-adsp@03000000"]
NODES_TOUCH = ["/soc/qcom,qupv3_0_geni_se@ac0000/spi@a90000",
               "/soc/qcom,qupv3_0_geni_se@ac0000/spi@a90000/touchscreen@0"]


import libfdt as _lf

def _try(fn, *a):
    try:
        return fn(*a)
    except _lf.FdtException:
        return -1

def walk(fdt, off, path, out):
    name = fdt.get_name(off)
    p = (path.rstrip("/") + "/" + name) if name else path
    ph = None
    if fdt.hasprop(off, "phandle"):
        ph = fdt.getprop(off, "phandle").as_uint32()
    out[p] = (off, ph)
    child = _try(fdt.first_subnode, off)
    while child >= 0:
        walk(fdt, child, p, out)
        child = _try(fdt.next_subnode, child)


def main():
    import libfdt
    img = sys.argv[1]
    base = sys.argv[2] if len(sys.argv) > 2 else "/tmp/base.dtb"
    d = open(img, "rb").read()
    magic, total, hsize, esize, count, eoff, page, ver = struct.unpack(">IIIIIIII", d[:32])
    assert magic == 0xd7b7ab1e, "no es un dt_table"
    dsize, doff, did, drev = struct.unpack(">IIII", d[32:48])
    pay = "/tmp/uke-check-payload.dtb"
    open(pay, "wb").write(d[doff:doff + dsize])
    print("dtbo %s: %d B, dt_size %d" % (img, len(d), dsize))
    merged = "/tmp/uke-check-merged.dtb"
    r = subprocess.run(["fdtoverlay", "-i", base, "-o", merged, pay],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("fdtoverlay FALLO (el ABL fallaria igual):\n" + r.stdout + r.stderr)
    print("fdtoverlay OK: %s" % merged)

    fdt = libfdt.Fdt(open(merged, "rb").read())
    nodes = {}
    walk(fdt, 0, "", nodes)
    ph2path = {ph: p for p, (off, ph) in nodes.items() if ph}
    print("nodos: %d, phandles: %d" % (len(nodes), len(ph2path)))

    # perfil automatico segun lo que traiga el PAYLOAD (no el arbol base)
    pay_b = open(pay, "rb").read()
    required = []
    report = []
    if b"display-subsystem@ae00000" in pay_b:
        report += NODES_REPORT
        required += NODES_REPORT + NODES_DISPLAY_EXTRA
    if b"qcom,pmic-glink-log" in pay_b:
        report += NODES_CHARGE
        required += NODES_CHARGE
    if b"/soc/qcom,qupv3_0_geni_se@ac0000/spi@a90000" in pay_b:
        report += NODES_TOUCH
        required += NODES_TOUCH
    print("perfil detectado: %d nodos a exigir (%s)" %
          (len(required), ", ".join(filter(None, [
              "display" if b"display-subsystem@ae00000" in pay_b else "",
              "carga" if b"qcom,pmic-glink-log" in pay_b else "",
              "tactil" if b"/soc/qcom,qupv3_0_geni_se@ac0000/spi@a90000" in pay_b else ""]))))
    # UKE (13-oct-2026): el táctil vive en novatek@0, no en touchscreen@0
    # (medido en el merged base+s281; el s281 YA flasheado falla el perfil
    # sin este ajuste). Se acepta cualquiera de los dos nombres.
    _touch_old = "/soc/qcom,qupv3_0_geni_se@ac0000/spi@a90000/touchscreen@0"
    _touch_uke = "/soc/qcom,qupv3_0_geni_se@ac0000/spi@a90000/novatek@0"
    if _touch_uke in nodes and _touch_old not in nodes:
        print("perfil táctil: novatek@0 (uke) en vez de touchscreen@0")
        required = [n.replace("touchscreen@0", "novatek@0") for n in required]
        report = [n.replace("touchscreen@0", "novatek@0") for n in report]
    missing = [n for n in required if n not in nodes]
    probs = []
    for path in report:
        if path not in nodes:
            continue
        off = nodes[path][0]
        print("\n== %s" % path)
        poff = _try(fdt.first_property_offset, off)
        while poff >= 0:
            p = fdt.get_property_by_offset(poff)
            prop, val = p.name, bytes(p)
            if prop in ("phandle", "name"):
                poff = _try(fdt.next_property_offset, poff)
                continue
            cells = None
            if len(val) > 0 and len(val) % 4 == 0:
                cells = struct.unpack(">%dI" % (len(val) // 4), val)
            if prop == "compatible":
                show = val.rstrip(b"\x00").replace(b"\x00", b"|").decode()
            elif cells is not None:
                show = " ".join("0x%x" % c for c in cells[:12]) + (" ..." if len(cells) > 12 else "")
            else:
                show = repr(val[:32])
            # 'clocks' no es una lista plana de pares: cada entrada tiene phandle + tantas
            # celdas como #clock-cells del proveedor (sleep_clk tiene 0 => 1 celda). Por eso
            # aqui se comprueba celda a celda: una celda que no resuelve a NINGUN nodo es una
            # referencia colgante (el fallo clasico del literal <0x777>); una que resuelve a un
            # nodo SIN #clock-cells es un indice de reloj (nota, no error).
            refs = []
            if cells:
                if prop in PROPS_CLOCKS:
                    refs = [("clocks", c) for c in cells if c != 0]
                elif prop in PROPS_ONE_REF or prop in PROPS_GPIO or prop.endswith(SUPPLY_SUFFIX):
                    refs = [(prop, cells[0])]
            for label, ph in refs:
                if ph == 0:
                    probs.append("%s: %s -> phandle 0 (nulo)" % (path, label))
                    continue
                tgt = ph2path.get(ph)
                if tgt is None:
                    probs.append("%s: %s -> 0x%x COLGANTE (no es ningun nodo)" % (path, label, ph))
                    show += "   [0x%x COLGANTE!]" % ph
                elif label == "clocks":
                    toff = nodes.get(tgt, (None, None))[0]
                    if toff is not None and fdt.hasprop(toff, "#clock-cells"):
                        show += "   [clk 0x%x = %s]" % (ph, tgt)
                    else:
                        show += "   [idx 0x%x]" % ph
                else:
                    show += "   [%s = %s]" % (label, tgt)
            print("   %-24s = %s" % (prop, show))
            poff = _try(fdt.next_property_offset, poff)

    print("\n================ RESULTADO ================")
    if missing:
        print("FALTAN nodos requeridos (%d):" % len(missing))
        for m in missing:
            print("   " + m)
    if probs:
        print("REFERENCIAS ROTAS (%d):" % len(probs))
        for x in probs:
            print("   " + x)
    if not missing and not probs:
        print("OK: el stack display existe en el arbol merged y todas sus referencias resuelven")
    return 1 if (missing or probs) else 0


if __name__ == "__main__":
    sys.exit(main())
