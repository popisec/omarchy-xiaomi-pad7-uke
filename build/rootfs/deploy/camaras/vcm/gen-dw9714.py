#!/usr/bin/env python3
"""gen-dw9714.py <KT> <stage>: copia drivers/media/i2c/dw9714.c (arbol senemos, solo lectura) como uke_dw9714.c para el CN3927V de la uke:
compatible "uke,cn3927v" (protocolo DW9714 verificado en los ciclos 18-20: ACK y foco monotono) y riel opcional "vio" (l20, pull-ups del
bus CCI) encendido junto a vcc. Asi el VCM es un subdev V4L2 (MEDIA_ENT_F_LENS, V4L2_CID_FOCUS_ABSOLUTE) que libcamera reconoce. 22-oct-2026."""
import os, sys
KT, ST = sys.argv[1], sys.argv[2]
t = open(os.path.join(KT, "drivers/media/i2c/dw9714.c")).read()
def one(t, old, new):
    assert t.count(old) == 1, old
    return t.replace(old, new)
t = one(t, "\tstruct regulator *vcc;\n", "\tstruct regulator *vcc;\n\tstruct regulator *vio;\t/* uke: l20 1,8 V, pull-ups del bus */\n")
t = one(t, "\tret = regulator_enable(dw9714_dev->vcc);\n\tif (ret)\n\t\treturn ret;\n",
        "\tret = regulator_enable(dw9714_dev->vio);\n\tif (ret)\n\t\treturn ret;\n\tret = regulator_enable(dw9714_dev->vcc);\n\tif (ret) {\n\t\tregulator_disable(dw9714_dev->vio);\n\t\treturn ret;\n\t}\n")
t = one(t, "\treturn regulator_disable(dw9714_dev->vcc);\n}\n",
        "\tregulator_disable(dw9714_dev->vcc);\n\treturn regulator_disable(dw9714_dev->vio);\n}\n")
t = one(t, "\tdw9714_dev->vcc = devm_regulator_get(&client->dev, \"vcc\");\n\tif (IS_ERR(dw9714_dev->vcc))\n\t\treturn PTR_ERR(dw9714_dev->vcc);\n",
        "\tdw9714_dev->vcc = devm_regulator_get(&client->dev, \"vcc\");\n\tif (IS_ERR(dw9714_dev->vcc))\n\t\treturn PTR_ERR(dw9714_dev->vcc);\n"
        "\tdw9714_dev->vio = devm_regulator_get(&client->dev, \"vio\");\t/* sin vio-supply: regulador ficticio */\n\tif (IS_ERR(dw9714_dev->vio))\n\t\treturn PTR_ERR(dw9714_dev->vio);\n")
t = one(t, '\t{ .compatible = "dongwoon,dw9714" },\n', '\t{ .compatible = "dongwoon,dw9714" },\n\t{ .compatible = "uke,cn3927v" },\n')
open(os.path.join(ST, "uke_dw9714.c"), "w").write(t)
print("gen-dw9714: OK")
