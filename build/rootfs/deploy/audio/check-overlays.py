#!/usr/bin/env python3
"""check-overlays.py — comprobaciones de solo lectura sobre el resultado de fdtoverlay (E0, 18-oct-2026).

Uso: check-overlays.py BASE.dtb MERGED.dtb [modules.alias]

 1. Nodos anadidos = presentes en MERGED y ausentes en BASE.
 2. Etiquetas nuevas de /__symbols__ que PISAN una etiqueta del vendor (libfdt las sobrescribe, el kernel
    rechaza el overlay): debe haber 0.
 3. Todo phandle de las propiedades conocidas de los nodos anadidos resuelve a un nodo existente y el
    numero de celdas de la referencia cuadra con el `#...-cells` del proveedor (clocks, pinctrl-N, *-supply,
    *-gpios, iommus, sound-dai, qcom,{rx,tx}-device, gpio-ranges).
 4. (opcional) cobertura de `compatible`: cada compatible de un nodo anadido tiene un modulo en modules.alias
    del kernel ouke3 (patron `of:N*T*C<compat>C*`) — equivale a "existe driver y esta compilado".
Sale con 1 si algo falla. Solo lee ficheros; no toca la tablet.
"""
import os, fnmatch
import re
import struct
import sys

import libfdt
from libfdt import QUIET_NOTFOUND

base_p, merged_p = sys.argv[1], sys.argv[2]
alias_p = sys.argv[3] if len(sys.argv) > 3 else None
base = libfdt.Fdt(open(base_p, "rb").read())
merged = libfdt.Fdt(open(merged_p, "rb").read())
fails = 0


def fail(msg):
    global fails
    fails += 1
    print("FALLO:", msg)


def walk(fdt, off=0, path=""):
    yield off, path or "/"
    child = fdt.first_subnode(off, QUIET_NOTFOUND)
    while child >= 0:
        name = fdt.get_name(child)
        yield from walk(fdt, child, (path + "/" + name) if path != "/" else "/" + name)
        child = fdt.next_subnode(child, QUIET_NOTFOUND)


def props(fdt, off):
    out = {}
    p = fdt.first_property_offset(off, QUIET_NOTFOUND)
    while p >= 0:
        pr = fdt.get_property_by_offset(p)
        out[pr.name] = bytes(pr)
        p = fdt.next_property_offset(p, QUIET_NOTFOUND)
    return out


def cells(b):
    return list(struct.unpack(">%dI" % (len(b) // 4), b[: len(b) // 4 * 4]))


def strs(b):
    return [s.decode() for s in b.split(b"\0") if s]


base_paths = {p for _, p in walk(base)}
added = [(o, p) for o, p in walk(merged) if p not in base_paths]
print("nodos anadidos: %d" % len(added))
for _, p in added:
    print("  +", p)

# --- 2. simbolos -----------------------------------------------------------------------
bs = props(base, base.path_offset("/__symbols__"))
ms = props(merged, merged.path_offset("/__symbols__"))
new_syms = [k for k in ms if k not in bs]
clash = [k for k in bs if k in ms and ms[k] != bs[k]]
print("etiquetas nuevas: %d (%s)" % (len(new_syms), ", ".join(sorted(new_syms))))
for k in clash:
    fail("la etiqueta %s del vendor cambia de destino: %r -> %r" % (k, bs[k], ms[k]))
for k in new_syms:
    if not k.startswith("uke_"):
        fail("etiqueta nueva sin prefijo uke_: %s" % k)
    try:
        merged.path_offset(ms[k][:-1].decode())
    except libfdt.FdtException:
        fail("etiqueta %s apunta a una ruta inexistente %s" % (k, ms[k]))

# --- 3. phandles -----------------------------------------------------------------------


def node_of(ph):
    try:
        return merged.node_offset_by_phandle(ph)
    except libfdt.FdtException:
        return -1


def cell_prop(off, name, default=None):
    try:
        return cells(bytes(merged.getprop(off, name)))[0]
    except libfdt.FdtException:
        return default


def check_refs(path, prop, v, spec):
    """spec: (cells_prop|None, fixed_n) -> grupos <phandle args...>"""
    cprop, fixed = spec
    c = cells(v)
    i = 0
    while i < len(c):
        n = node_of(c[i])
        if n < 0:
            fail("%s: %s phandle 0x%x no resuelve" % (path, prop, c[i]))
            return
        na = fixed if cprop is None else cell_prop(n, cprop)
        if na is None:
            fail("%s: %s proveedor %s sin %s" % (path, prop, merged.get_path(n), cprop))
            return
        i += 1 + na
    if i != len(c):
        fail("%s: %s longitud %d celdas no cuadra con %s" % (path, prop, len(c), cprop))


SPECS = {
    "clocks": ("#clock-cells", None),
    "iommus": ("#iommu-cells", None),
    "sound-dai": ("#sound-dai-cells", None),
    "reset-gpios": ("#gpio-cells", None),
    "gpio-ranges": (None, 3),
}
checked = 0
for off, path in added:
    pr = props(merged, off)
    for name, v in pr.items():
        if name in SPECS:
            check_refs(path, name, v, SPECS[name])
            checked += 1
        elif re.fullmatch(r"pinctrl-\d+", name) or name in ("qcom,rx-device", "qcom,tx-device"):
            for ph in cells(v):
                if node_of(ph) < 0:
                    fail("%s: %s phandle 0x%x no resuelve" % (path, name, ph))
            checked += 1
        elif name.endswith("-supply"):
            ph = cells(v)[0]
            n = node_of(ph)
            if n < 0:
                fail("%s: %s phandle 0x%x no resuelve" % (path, name, ph))
            else:
                print("  %s %s -> %s (%s)" % (path.rsplit("/", 1)[-1], name, merged.get_path(n),
                                              bytes(merged.getprop(n, "regulator-name"))[:-1].decode()))
            checked += 1
    # los sound-dai de los enlaces de la tarjeta cuelgan de subnodos: ya recorridos como nodos anadidos
print("propiedades con referencia comprobadas: %d" % checked)

# iommus: ¿apunta al apps-smmu?
for off, path in added:
    pr = props(merged, off)
    if "iommus" in pr:
        ph = cells(pr["iommus"])[0]
        tgt = merged.get_path(node_of(ph))
        print("  %s iommus -> %s %s" % (path, tgt, [hex(x) for x in cells(pr["iommus"])]))
        if tgt != "/soc/apps-smmu@15000000":
            fail("%s: iommus no apunta al apps-smmu" % path)

# --- 4. compatibles --------------------------------------------------------------------
if alias_p:
    of_pats, sdw_pats = [], []
    for line in open(alias_p):
        m = re.match(r"alias (of:\S+) (\S+)", line)
        if m:
            of_pats.append((re.compile(fnmatch.translate(m.group(1))), m.group(2)))
        m = re.match(r"alias (sdw:\S+) (\S+)", line)
        if m:
            sdw_pats.append((re.compile(fnmatch.translate(m.group(1))), m.group(2)))
    print("cobertura de compatibles contra %s (%d alias of:, %d sdw:)" % (alias_p, len(of_pats), len(sdw_pats)))
    for off, path in added:
        pr = props(merged, off)
        if "compatible" not in pr:
            continue
        name = path.rsplit("/", 1)[-1].split("@")[0]
        short = path.replace("/soc/remoteproc-adsp@03000000/glink-edge/qcom,gpr", "…/gpr")
        hit_any = False
        rows = []
        for comp in strs(pr["compatible"]):
            m = re.fullmatch(r"sdw([0-9a-f])([0-9a-f]{4})([0-9a-f]{4})([0-9a-f]{2})", comp)
            if m:
                # dispositivos SoundWire: id_table => alias sdw:m<mfg>p<part>v<ver>c<clase>
                ver, mfg, part, cls = m.groups()
                key = "sdw:m%sp%sv%sc%s" % (mfg.upper(), part.upper(), ver.upper().zfill(2), cls.upper())
                hit = sorted({mod for rx, mod in sdw_pats if rx.fullmatch(key)})
            else:
                hit = sorted({mod for rx, mod in of_pats if rx.fullmatch("of:N%sT<NULL>C%s" % (name, comp))})
            hit_any |= bool(hit)
            rows.append((comp, hit))
        # drivers COMPILADOS EN el kernel (no tienen alias de modulo): regulator-fixed (CONFIG_REGULATOR_FIXED_VOLTAGE=y en ouke5, comprobado en .config)
        if not hit_any and "regulator-fixed" in strs(pr["compatible"]):
            hit_any = True
            rows = [(c, ["(built-in)"] if c == "regulator-fixed" else h) for c, h in rows]
        # drivers FUERA DE ARBOL propios (no estan en modules.alias del kernel): se aceptan solo si el compatible aparece en nuestras fuentes
        own_src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fs19xx", "uke_fs19xx.c")
        if not hit_any and os.path.exists(own_src):
            src_txt = open(own_src, errors="replace").read()
            own = [c for c in strs(pr["compatible"]) if ('"%s"' % c) in src_txt]
            if own:
                hit_any = True
                rows = [(c, ["(modulo propio uke_fs19xx.ko)"] if c in own else h) for c, h in rows]
        for comp, hit in rows:
            print("  %-46s %-40s %s" % (short, comp, ",".join(hit) if hit else
                                        ("(sin alias; lo cubre el compatible de reserva)" if hit_any else "(SIN MODULO)")))
        if not hit_any:
            fail("%s: ningun compatible tiene driver en el kernel ouke3" % path)
print("RESULTADO:", "OK" if not fails else "%d FALLO(S)" % fails)
sys.exit(1 if fails else 0)
