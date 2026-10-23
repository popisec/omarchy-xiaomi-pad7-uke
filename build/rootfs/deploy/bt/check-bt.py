#!/usr/bin/env python3
"""check-bt.py -- comprueba el DT RESULTANTE de aplicar una variante del overlay del BT sobre el DT base.

Uso: python3 -I check-bt.py BASE.dtb MERGED.dtb {uart-only|B|A} [modules.alias [hci_qca.c]]

Todo lo que se afirma aqui sale de comparar los dos DTB con libfdt (nada de memoria):
  1. el overlay SOLO toca el nodo de la UART (y su hijo `bluetooth`): el resto del arbol es identico al base;
  2. en el nodo de la UART cambian exactamente {compatible, clock-names, status, pinctrl-names, pinctrl-0, pinctrl-1,
     interrupts-extended}; reg/clocks/interconnects/pinctrl-2/3... quedan como en el vendor;
  3. cada phandle del overlay apunta al nodo que dice su etiqueta en /__symbols__ del base (pinctrl, tlmm, intc, rails);
  4. el intercambio default<->sleep del pinctrl es exactamente el del vendor (default=UART=antiguo 'active');
  5. variante A lleva vddrfa2p2, B no, U no tiene hijo `bluetooth`;
  6. los phandles de los rails/tlmm son los medidos en el DT vivo (informe BT-SENEMOS-20261018 §2.1);
  7. (con hci_qca.c) los nombres de supply son EXACTAMENTE los 9 de qca_soc_data_wcn6750 y las propiedades
     `enable-gpios`/`swctrl-gpios` las lee el driver.
Sale con 1 si algo falla.
"""
import re
import struct
import sys

import libfdt

UART = "/soc/qcom,qupv3_1_geni_se@8c0000/qcom,qup_uart@888000"
# phandles medidos en la tablet (informe §2.1/App. A); en el DT base son los mismos
LIVE_PH = {"pmxr2230_l7": 0x1E0, "pmxr2230_s3": 0x348, "pmxr2230_s1": 0x346, "pmxr2230_s2": 0x347,
           "pmr735a_s3": 0x345, "tlmm": 0x16B}
CHANGED = {"compatible", "clock-names", "status", "pinctrl-names", "pinctrl-0", "pinctrl-1", "interrupts-extended"}
SUPPLIES_B = {"vddio": "pmxr2230_l7", "vddaon": "pmxr2230_s3", "vddbtcxmx": "pmxr2230_s3", "vddrfacmn": "pmxr2230_s3",
              "vddrfa0p8": "pmxr2230_s3", "vddrfa1p7": "pmxr2230_s1", "vddrfa1p2": "pmxr2230_s2"}
MARK = bytes([0x55, 0x4B, 0x45, 0x42, 0x54, 0x21])

fails = 0


def ok(cond, msg):
    global fails
    print(("  ok    " if cond else "  FALLO ") + msg)
    if not cond:
        fails += 1


def u32s(b):
    b = bytes(b)
    return list(struct.unpack(">%dI" % (len(b) // 4), b))


def strs(b):
    return [s.decode() for s in bytes(b).split(b"\0") if s]


def walk(f):
    """{ruta: {prop: bytes}} de todo el arbol."""
    out = {}

    def rec(off, path):
        props = {}
        p = f.first_property_offset(off, libfdt.QUIET_NOTFOUND)
        while p >= 0:
            pr = f.get_property_by_offset(p)
            props[pr.name] = bytes(pr)
            p = f.next_property_offset(p, libfdt.QUIET_NOTFOUND)
        out[path] = props
        c = f.first_subnode(off, libfdt.QUIET_NOTFOUND)
        while c >= 0:
            n = f.get_name(c)
            rec(c, (path.rstrip("/") + "/" + n))
            c = f.next_subnode(c, libfdt.QUIET_NOTFOUND)

    rec(f.path_offset("/"), "/")
    return out


def main():
    base_p, merged_p, variant = sys.argv[1:4]
    alias_p = sys.argv[4] if len(sys.argv) > 4 else None
    qca_p = sys.argv[5] if len(sys.argv) > 5 else None
    assert variant in ("uart-only", "B", "A"), variant
    fb = libfdt.Fdt(open(base_p, "rb").read())
    fm = libfdt.Fdt(open(merged_p, "rb").read())
    tb, tm = walk(fb), walk(fm)

    def sym(f, label):
        return bytes(f.getprop(f.path_offset("/__symbols__"), label)).rstrip(b"\0").decode()

    def ph_of(f, path):
        return f.get_phandle(f.path_offset(path))

    def path_of_ph(f, ph):
        off = f.node_offset_by_phandle(ph)
        return f.get_path(off)

    print("[%s] base vs fusionado" % variant)
    # 1. solo cambia el nodo de la UART y su subarbol
    diff_paths = sorted(p for p in set(tb) | set(tm) if tb.get(p) != tm.get(p))
    outside = [p for p in diff_paths if not (p == UART or p.startswith(UART + "/"))]
    ok(not outside, "el overlay no toca nada fuera de la UART (%d nodos distintos, todos bajo %s)%s"
       % (len(diff_paths), UART.split("/")[-1], "" if not outside else ": " + ", ".join(outside[:5])))
    expect_new = {UART + "/bluetooth"} if variant != "uart-only" else set()
    new_nodes = set(tm) - set(tb)
    ok(new_nodes == expect_new, "nodos nuevos = %s" % (sorted(new_nodes) or "ninguno"))
    ok(not (set(tb) - set(tm)), "no desaparece ningun nodo")

    # 2. propiedades del nodo UART
    b, m = tb[UART], tm[UART]
    ok(b["status"] == b"disabled\0" and b["compatible"] == b"qcom,msm-geni-serial-hs\0",
       "base: status=disabled, compatible=qcom,msm-geni-serial-hs (lo que deja uke_scope_qup_buses)")
    changed = {k for k in set(b) | set(m) if b.get(k) != m.get(k)}
    ok(changed == CHANGED, "propiedades cambiadas = %s" % sorted(changed))
    ok(m["status"] == b"okay\0", "status = okay")
    ok(strs(m["compatible"]) == ["qcom,geni-uart"], "compatible = qcom,geni-uart")
    ok(strs(m["clock-names"]) == ["se"], "clock-names = se")
    for k in ("reg", "clocks", "interconnects", "interconnect-names", "reg-names", "qcom,wakeup-byte", "pinctrl-2",
              "pinctrl-3", "phandle"):
        ok(b[k] == m[k], "sin cambios: %s" % k)

    # 3/4. pinctrl: default=UART (antiguo 'active'), sleep=GPIO (antiguo 'default')
    ok(strs(b["pinctrl-names"]) == ["default", "active", "sleep", "shutdown"], "base: pinctrl-names vendor default/active/sleep/shutdown")
    ok(strs(m["pinctrl-names"]) == ["default", "sleep"], "pinctrl-names = default, sleep")
    ok(m["pinctrl-0"] == b["pinctrl-1"], "pinctrl-0 (default) == 'active' del vendor (funciones UART)")
    ok(m["pinctrl-1"] == b["pinctrl-0"], "pinctrl-1 (sleep) == 'default' del vendor (GPIO en reposo)")
    for st, labels, want_fn in (("pinctrl-0", ["qupv3_se10_cts", "qupv3_se10_rts", "qupv3_se10_tx", "qupv3_se10_rx"], "qup1_se2"),
                                ("pinctrl-1", ["qupv3_se10_default_cts", "qupv3_se10_default_rts", "qupv3_se10_default_tx",
                                               "qupv3_se10_default_rx"], "gpio")):
        got = [path_of_ph(fm, p) for p in u32s(m[st])]
        want = [sym(fb, lb) for lb in labels]
        ok(got == want, "%s apunta a %s..." % (st, labels[0] + "+3"))
        fns = [bytes(tm[g + "/mux"]["function"]).rstrip(b"\0").decode() for g in got]
        pins = sorted(bytes(tm[g + "/mux"]["pins"]).rstrip(b"\0").decode() for g in got)
        ok(all(fn.startswith(want_fn) for fn in fns) and pins == ["gpio40", "gpio41", "gpio42", "gpio43"],
           "%s: pines %s con funcion %s" % (st, "/".join(p[4:] for p in pins), "/".join(sorted(set(fns)))))

    # interrupciones: GIC SPI 584 nivel alto + wake tlmm 43 flanco de bajada
    intc, tlmm = ph_of(fb, sym(fb, "intc")), ph_of(fb, sym(fb, "tlmm"))
    ie = u32s(m["interrupts-extended"])
    ok(ie == [intc, 0, 584, 4, tlmm, 43, 2], "interrupts-extended = <intc SPI 584 nivel-alto>, <tlmm 43 flanco-bajada> %s" % ie)
    ok(u32s(b["interrupts-extended"])[:4] == ie[:4], "la IRQ principal es la del DT vendor (SPI 584)")

    # 6. phandles medidos en el vivo
    for lb, ph in LIVE_PH.items():
        ok(ph_of(fb, sym(fb, lb)) == ph, "phandle de %s = 0x%x (medido en la tablet)" % (lb, ph))

    bt = UART + "/bluetooth"
    if variant == "uart-only":
        ok(bt not in tm, "variante U: sin nodo bluetooth, sin GPIO ni rails")
    else:
        t = tm[bt]
        ok(strs(t["compatible"]) == ["qcom,wcn6750-bt"], "bluetooth: compatible = qcom,wcn6750-bt")
        ok(strs(t["pinctrl-names"]) == ["default"] and path_of_ph(fm, u32s(t["pinctrl-0"])[0]) == sym(fb, "bt_en_sleep")
           and len(u32s(t["pinctrl-0"])) == 1, "bluetooth: pinctrl-0 = bt_en_sleep (gpio156 salida a 0)")
        ok(u32s(t["enable-gpios"]) == [tlmm, 156, 0], "enable-gpios = <tlmm 156 ACTIVE_HIGH>")
        ok(u32s(t["swctrl-gpios"]) == [tlmm, 80, 0], "swctrl-gpios = <tlmm 80 ACTIVE_HIGH>")
        sup = dict(SUPPLIES_B)
        if variant == "A":
            sup["vddrfa2p2"] = "pmr735a_s3"
        got = {k[:-7]: v for k, v in t.items() if k.endswith("-supply")}
        ok(set(got) == set(sup), "supplies = %s" % sorted(got))
        for k, lb in sorted(sup.items()):
            ok(k in got and u32s(got[k]) == [ph_of(fb, sym(fb, lb))] and path_of_ph(fm, u32s(got[k])[0]) == sym(fb, lb),
               "%s-supply -> %s (0x%x)" % (k, lb, LIVE_PH[lb]))
        ok(("vddrfa2p2-supply" in t) == (variant == "A"), "vddrfa2p2: %s" % ("presente (variante A, exige kernel v4)" if variant == "A"
           else "ausente (variante B; el core pondra un regulador dummy)"))
        ok("vddasd-supply" not in t, "vddasd ausente (dummy, no bloquea; informe §2.2)")
        ok(bytes(t["local-bd-address"]) == MARK, "local-bd-address = marcador UKEBT! (sin direccion real en el repo)")
        extra = set(t) - {"compatible", "pinctrl-names", "pinctrl-0", "enable-gpios", "swctrl-gpios", "local-bd-address", "phandle"} \
            - {k + "-supply" for k in sup}
        ok(not extra, "el nodo bluetooth no lleva propiedades inesperadas %s" % (sorted(extra) or ""))

    # compatibles con driver en el kernel ouke3
    if alias_p:
        al = open(alias_p, errors="replace").read()
        if variant != "uart-only":
            ok("alias of:N*T*Cqcom,wcn6750-bt hci_uart" in al, "modules.alias: qcom,wcn6750-bt -> hci_uart (por nombre; la blacklist frena solo el autoload)")
    if qca_p and variant != "uart-only":
        src = open(qca_p, errors="replace").read()
        blk = src[src.index("qca_soc_data_wcn6750"):]
        blk = blk[:blk.index(".num_vregs")]
        names = set(re.findall(r'\{\s*"(vdd\w+)"', blk))
        got = {k[:-7] for k in tm[bt] if k.endswith("-supply")}
        ok(got <= names, "todos los supplies del overlay existen en qca_soc_data_wcn6750 (%d de %d del driver)" % (len(got), len(names)))
        ok(names - got == ({"vddasd"} if variant == "A" else {"vddasd", "vddrfa2p2"}),
           "supplies del driver que el overlay NO da (el core pone regulador dummy): %s" % sorted(names - got))
        ok('devm_gpiod_get_optional(&serdev->dev, "enable"' in src and 'devm_gpiod_get_optional(&serdev->dev, "swctrl"' in src,
           "hci_qca.c lee enable-gpios y swctrl-gpios")
        ok('{ .compatible = "qcom,wcn6750-bt", .data = &qca_soc_data_wcn6750}' in src, "hci_qca.c: of_match qcom,wcn6750-bt -> qca_soc_data_wcn6750")
    print("[%s] %s" % (variant, "OK" if not fails else "%d FALLO(S)" % fails))
    return 1 if fails else 0


sys.exit(main())
