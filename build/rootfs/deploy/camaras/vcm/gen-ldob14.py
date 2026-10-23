#!/usr/bin/env python3
"""gen-ldob14.py <KT> <stage>: copia qcom-rpmh-regulator-uke.c (arbol senemos, solo lectura) como modulo uke_rpmh_ldob14.c que SOLO acepta
el recurso ldob14 (pmxr2230_l14, 2,8 V fijo: riel cam_vaf del VCM). El driver integrado lo rechaza a proposito (allowlist C3). 22-oct-2026."""
import os, re, sys
KT, ST = sys.argv[1], sys.argv[2]
t = open(os.path.join(KT, "drivers/regulator/qcom-rpmh-regulator-uke.c")).read()
a = t.index('\tif (strcmp(aggr_vreg->resource_name, "cx.lvl") &&')
b = t.index('\t\treturn -ENODEV;\n', a) + len('\t\treturn -ENODEV;\n')
assert t[a:b].count('"ldoc3"') == 1, "allowlist cambiada"
t = t[:a] + '\t/* uke_rpmh_ldob14: SOLO el riel del VCM; cualquier otro nodo se rechaza antes de tocar el hardware */\n\tif (strcmp(aggr_vreg->resource_name, "ldob14"))\n\t\treturn -ENODEV;\n' + t[b:]
def one(t, old, new):
    assert t.count(old) == 1, old
    return t.replace(old, new)
t = one(t, '.name\t\t= "qcom,rpmh-regulator",', '.name\t\t= "uke-rpmh-ldob14",')
t = one(t, 'arch_initcall(rpmh_regulator_init);', 'module_init(rpmh_regulator_init);')
t = one(t, 'MODULE_DESCRIPTION("RPMh regulator driver");', 'MODULE_DESCRIPTION("uke: RPMh ldob14 (pmxr2230_l14, cam_vaf 2,8 V) como modulo; copia de qcom-rpmh-regulator-uke con allowlist de 1");')
open(os.path.join(ST, "uke_rpmh_ldob14.c"), "w").write(t)
print("gen-ldob14: OK")
