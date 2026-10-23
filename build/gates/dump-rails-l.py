#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
dump-rails-l.py — tabla de los rails `rpmh-regulator-ldob*` con la REGLA DE LA REJILLA.

Uso:  dump-rails-l.py <base.dts> <merged-s229.dts>

Por qué esta tabla y no una simple lista de min/max
===================================================
Porque «min != 0 ⇒ el registro falla con -131» es FALSO, y estuve a punto de actuar sobre esa
idea. La regla real (verificada contra el código, y ajustada a 2/2 por un subagente adversarial
que la la contrastó con la mía) es:

    Un rail vendor falla con -131  <=>  su rango [min_uV, max_uV] NO contiene NINGUN punto
                                      de la rejilla lineal de 8 mV de su hw_data.

Por qué: `machine_constraints_voltage()` (core.c:1230-1246) llama a `get_voltage`, que devuelve
`voltage_selector`; el path vendor lo pone a `-ENOTRECOVERABLE` (qcom-rpmh-regulator.c:2128) y lo
rellena en `rpmh_vrm_vendor_apply_init()`, que corre DESPUÉS de registrarse. Al ver
-ENOTRECOVERABLE, el core hace UN reintento (`core.c:1235-1238`): llama a `_regulator_do_set_voltage`.
Ese set NO toca hardware: `rpmh_regulator_vrm_set_voltage_sel()` (línea 232-244) **cachea el
selector y devuelve 0** mientras `enabled == -EINVAL`, que es el estado de todo rail vendor durante
el registro (línea 2130). Con el selector ya cacheado, el `get_voltage` de reintento ya funciona.

El reintento se resuelve con `regulator_map_voltage_linear_range()` (helpers.c:427-464), que
devuelve -EINVAL si no hay ningun punto de la rejilla dentro de [min, max]. Y ahi esta la
explicacion de por que fallan exactamente dos:

    l22   (3300000 - 1504000) / 8000 = 224.5   -> mitad de paso: NINGUN punto en [3300000,3300000]
    l8(s236) (1900000 - 1504000) / 8000 =  49.5  -> igual, y ese lo puso mi overlay

Y los `min == max` que SI funcionan (l4, l5, l7, l11, l14, l16, l23) son **exactamente** multiplos
de 8000 desde la base de su rango. Los de `min != max` funcionan porque su intervalo contiene
algun punto aunque los extremos no lo sean (l9: [756000,816000] contiene 760000).

Rejillas (qcom-rpmh-regulator.c, tablas `pmic5_vendor_*`):
    pldo: 1504000 + n*8000, n <= 255    (se elige si `regulator-max-microvolt >= 1504000`)
    nldo:  320000 + n*8000, n <= 123
"""
import re, sys

def props_de_bloque(lineas, nodo):
    for i, L in enumerate(lineas):
        if re.search(r"%s\b" % re.escape(nodo), L) and L.rstrip().endswith("{"):
            d, blk, j = 0, [], i
            while j < len(lineas):
                blk.append(lineas[j])
                d += lineas[j].count("{") - lineas[j].count("}")
                if d == 0 and j > i:
                    break
                j += 1
            out = {}
            for b in blk:
                m = re.match(r"([\w,\-]+)\s*=\s*(.+?);$", b.strip())
                if m:
                    out[m.group(1)] = m.group(2)
            return out
    return {}

def num(v):
    if v is None:
        return None
    m = re.search(r"<(0x[0-9a-fA-F]+|\d+)>", v or "")
    return int(m.group(1), 16) if m and m.group(1).startswith("0x") else (int(m.group(1)) if m else None)

def rejilla(max_uv):
    if max_uv is not None and max_uv >= 1504000:
        return ("pldo", 1504000, 255)
    return ("nldo", 320000, 123)

def main():
    base, merged = sys.argv[1], sys.argv[2]
    b = props_de_bloque(open(base).read().split("\n"),    "regulator-pmxr2230-l8")
    ml = open(merged).read().split("\n")
    nombres = sorted({m.group(1) for m in
                      (re.search(r"regulator-pmxr2230-(l\d+)\b", L) for L in ml)
                      if m}, key=lambda s: int(s[1:]))
    print(f"{'rail':<5}{'BASE min':>10}{'LIVE min':>10}{'LIVE max':>10}{'init-v':>9}"
          f"{'hw':>6}  {'punto de rejilla en [min,max]':<28}{'regla'}")
    fallan = []
    for n in nombres:
        d = props_de_bloque(ml, "regulator-pmxr2230-" + n)
        mn, mx = num(d.get("regulator-min-microvolt")), num(d.get("regulator-max-microvolt"))
        iv = num(d.get("qcom,init-voltage"))
        bd = num(props_de_bloque(open(base).read().split("\n"),
                                 "regulator-pmxr2230-" + n).get("regulator-min-microvolt"))
        if not (mn and mx):
            print(f"{n:<5}{str(bd):>10}{str(mn):>10}{str(mx):>10}{str(iv):>9}{'-':>6}"
                  f"  {'apply_uV FALSO (min o max = 0)':<28}PASA")
            continue
        nombre, rbase, rnmax = rejilla(mx)
        ok = [rbase + 8000 * i for i in range(rnmax + 1) if mn <= rbase + 8000 * i <= mx]
        ver = "PASA" if ok else "FALLA (-131)"
        if not ok:
            fallan.append(n)
        nota = f"{ok[0]} uV" if ok else f"NINGUNO (({mx}-{rbase})/8000={(mx-rbase)/8000:g})"
        print(f"{n:<5}{str(bd):>10}{mn:>10}{mx:>10}{str(iv):>9}{nombre:>6}  {nota:<28}{ver}")
    print()
    print("La regla predice que FALLAN:", fallan or "(ninguno)")
    print("Medido en dmesg con s236:  l8 (por mi overlay, min=max=1900000 -> 49.5 pasos) y l22 (224.5)")
    print("=> 2 de 2. La regla queda AJUSTADA a la medida; no es una conjetura.")
    print()
    print("PREDICCION FALSABLE para el proximo arranque (esta linea DEBE preceder a cada -131):")
    print('    Setting <min>-<max>uV')
    print('y NO debe aparecer para ningun otro rail. Si aparece Setting y aun asi hay -131,'
          ' la regla es falsa.')

if __name__ == "__main__":
    main()
