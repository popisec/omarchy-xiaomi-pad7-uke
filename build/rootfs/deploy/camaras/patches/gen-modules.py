#!/usr/bin/env python3
"""Genera, a partir del arbol FUENTE del kernel senemos (solo LECTURA), las copias parcheadas de los drivers de camara de la uke.
Uso: gen-modules.py <KT> <stage-dir>
Cada edicion se exige EXACTAMENTE una vez (si el fuente cambia, falla en vez de generar un modulo distinto del previsto).
Fecha: 19-oct-2026 (C0). Plan: build/gates/revision/CAMARAS-PLAN-20261019.md."""
import os, shutil, sys

KT, ST = sys.argv[1], sys.argv[2]
os.makedirs(ST, exist_ok=True)


def edit(text, old, new, name, count=1):
    n = text.count(old)
    if n != count:
        sys.exit("FALLO %s: %r aparece %d veces (esperado %d)" % (name, old[:60], n, count))
    return text.replace(old, new)


def rd(p):
    return open(os.path.join(KT, p)).read()


def wr(name, text):
    open(os.path.join(ST, name), "w").write(text)


# ---- 1. camcc: camcc-sm8650.c -> camcc-cliffs-uke.c ----------------------------------------------------------------
t = rd("drivers/clk/qcom/camcc-sm8650.c")
t = edit(t, '{ .compatible = "qcom,sm8650-camcc" },', '{ .compatible = "qcom,cliffs-camcc" },', "camcc.compat")
t = edit(t, '.name = "camcc-sm8650",', '.name = "camcc-cliffs-uke",', "camcc.name")
t = edit(t, "\t&cam_cc_pll10,\n", "", "camcc.pll10")  # la uke solo tiene PLL0..9 (clk_summary de Android)
t = edit(t, 'MODULE_DESCRIPTION("QTI CAMCC SM8650 Driver");',
         'MODULE_DESCRIPTION("uke: camcc de Cliffs sobre camcc-sm8650 (offsets identicos, sin PLL10, votos de rieles vdd_*)");', "camcc.desc")
t = edit(t, "#include <linux/platform_device.h>\n",
         "#include <linux/platform_device.h>\n#include <linux/regulator/consumer.h>\n#include <linux/limits.h>\n#include <linux/of_address.h>\n#include <linux/io.h>\n#include <linux/regmap.h>\n", "camcc.inc")
votes = r'''
/*
 * uke: la uke no tiene rpmhpd; MMCX/MXC/MX se votan con los reguladores de nivel del DT vendor (vdd_mx/vdd_mxc/vdd_mm),
 * igual que el dispcc (uke-dispcc-votes.c). Ademas vdd_mmcx_voter = pm_v6c_s6_mmcx_voter_level, el parent-supply del GDSC titan_top en el DT vendor (C4: sin el, el GDSC se queda en 'off'). Voto fijo mientras el modulo este cargado (bring-up; el ajuste fino por
 * frecuencia es posterior). Niveles RPMh: 64 LOW_SVS, 128 SVS, 192 SVS_L1, 256 NOM. Parametro vote_level.
 */
static unsigned int uke_vote_level = 128;
module_param_named(vote_level, uke_vote_level, uint, 0444);
MODULE_PARM_DESC(vote_level, "nivel RPMh votado en vdd_mx/vdd_mxc/vdd_mm (128 = SVS)");

static void uke_vote_off(void *data)
{
	regulator_disable(data);
}

static int uke_cam_votes(struct device *dev)
{
	static const char * const names[] = { "vdd_mx", "vdd_mxc", "vdd_mm", "vdd_mmcx_voter" };
	int i, ret;

	for (i = 0; i < ARRAY_SIZE(names); i++) {
		struct regulator *r = devm_regulator_get(dev, names[i]);

		if (IS_ERR(r))
			return dev_err_probe(dev, PTR_ERR(r), "falta %s\n", names[i]);
		ret = regulator_set_voltage(r, uke_vote_level, INT_MAX);
		if (ret)
			dev_warn(dev, "%s: set_voltage(%u) = %d\n", names[i], uke_vote_level, ret);
		ret = regulator_enable(r);
		if (ret)
			return dev_err_probe(dev, ret, "%s: enable\n", names[i]);
		ret = devm_add_action_or_reset(dev, uke_vote_off, r);
		if (ret)
			return ret;
	}
	return 0;
}

/*
 * C4-bis (19-oct-2026, SOLO LECTURA): registros que explican el «GDSC stuck at off». Se leen antes y despues de qcom_cc_probe:
 * gcc 0x26004 (gcc_camera_ahb_clk), 0x26028 (camera_hf_xo), 0x2602c (camera_sf_xo): el probe OEM de gcc-cliffs los fuerza a BIT(0) y el de
 * senemos NO; camcc PLL0 L_VAL (0x10), cam_cc_gdsc_clk cbcr (0x132ec) y GDSCR titan_top (0x132bc). Ninguna escritura.
 */
static unsigned int uke_dbg = 1;
module_param_named(dbg, uke_dbg, uint, 0444);
MODULE_PARM_DESC(dbg, "imprime registros de gcc/camcc antes y despues del probe (solo lectura)");

static void uke_dbg_regs(struct platform_device *pdev, const char *when, struct regmap *rm)
{
	struct device_node *gn;
	void __iomem *cc = NULL, *gcc = NULL;
	unsigned int a = 0, b = 0, c = 0;

	if (!uke_dbg)
		return;
	gn = of_find_compatible_node(NULL, NULL, "qcom,cliffs-gcc");
	if (gn) {
		gcc = of_iomap(gn, 0);
		of_node_put(gn);
	}
	if (gcc)
		dev_info(&pdev->dev, "uke-dbg %s: gcc camera_ahb[0x26004]=%08x camera_hf_xo[0x26028]=%08x camera_sf_xo[0x2602c]=%08x\n",
			 when, readl(gcc + 0x26004), readl(gcc + 0x26028), readl(gcc + 0x2602c));
	else
		dev_info(&pdev->dev, "uke-dbg %s: sin gcc (qcom,cliffs-gcc)\n", when);
	if (rm) {
		regmap_read(rm, 0x10, &a);
		regmap_read(rm, 0x132ec, &b);
		regmap_read(rm, 0x132bc, &c);
	} else {
		cc = of_iomap(pdev->dev.of_node, 0);
		if (cc) {
			a = readl(cc + 0x10);
			b = readl(cc + 0x132ec);
			c = readl(cc + 0x132bc);
			iounmap(cc);
		}
	}
	dev_info(&pdev->dev, "uke-dbg %s: camcc(%s) pll0_L_VAL=%08x gdsc_clk=%08x gdscr_titan=%08x\n", when, rm ? "regmap" : "iomap", a, b, c);
	if (gcc)
		iounmap(gcc);
}

/*
 * C4-ter (autorizado por el dueno 19-oct-2026; ungate=1 lo activa): el probe OEM de gcc-cliffs fuerza a BIT(0) gcc_camera_ahb_clk (0x26004),
 * gcc_camera_hf_xo_clk (0x26028) y gcc_camera_sf_xo_clk (0x2602c); el gcc de senemos no lo hace y en C4-bis se midio 0x80000000 (CLK_OFF) en los
 * tres: camcc no responde. Con ungate=1 se hace el mismo RMW y se restauran los valores originales al descargar.
 */
static unsigned int uke_ungate;
module_param_named(ungate, uke_ungate, uint, 0444);
MODULE_PARM_DESC(ungate, "1 = poner BIT(0) en gcc camera_ahb/hf_xo/sf_xo como hace el probe OEM (restaura al descargar)");

struct uke_gcc_saved {
	void __iomem *gcc;
	u32 v[3];
};
static const u32 uke_gcc_offs[3] = { 0x26004, 0x26028, 0x2602c };

static void uke_gcc_restore(void *data)
{
	struct uke_gcc_saved *sv = data;
	int i;

	for (i = 0; i < 3; i++)
		writel(sv->v[i], sv->gcc + uke_gcc_offs[i]);
	pr_info("uke-dbg: gcc camera_ahb/hf_xo/sf_xo restaurados a %08x %08x %08x\n", sv->v[0], sv->v[1], sv->v[2]);
	iounmap(sv->gcc);
}

static int uke_gcc_ungate(struct device *dev)
{
	struct device_node *gn;
	struct uke_gcc_saved *sv;
	int i;

	if (!uke_ungate)
		return 0;
	gn = of_find_compatible_node(NULL, NULL, "qcom,cliffs-gcc");
	if (!gn)
		return dev_err_probe(dev, -ENODEV, "sin qcom,cliffs-gcc\n");
	sv = devm_kzalloc(dev, sizeof(*sv), GFP_KERNEL);
	if (!sv) {
		of_node_put(gn);
		return -ENOMEM;
	}
	sv->gcc = of_iomap(gn, 0);
	of_node_put(gn);
	if (!sv->gcc)
		return -ENOMEM;
	for (i = 0; i < 3; i++) {
		sv->v[i] = readl(sv->gcc + uke_gcc_offs[i]);
		writel(sv->v[i] | BIT(0), sv->gcc + uke_gcc_offs[i]);
	}
	dev_info(dev, "uke-dbg ungate: gcc camera_ahb/hf_xo/sf_xo %08x %08x %08x -> %08x %08x %08x\n", sv->v[0], sv->v[1], sv->v[2],
		 readl(sv->gcc + uke_gcc_offs[0]), readl(sv->gcc + uke_gcc_offs[1]), readl(sv->gcc + uke_gcc_offs[2]));
	return devm_add_action_or_reset(dev, uke_gcc_restore, sv);
}

static int cam_cc_sm8650_probe(struct platform_device *pdev)
{
	int ret = uke_cam_votes(&pdev->dev);

	if (ret)
		return ret;
	ret = uke_gcc_ungate(&pdev->dev);
	if (ret)
		return ret;
	uke_dbg_regs(pdev, "pre", NULL);
	ret = qcom_cc_probe(pdev, &cam_cc_sm8650_desc);
	if (!ret)
		uke_dbg_regs(pdev, "post", dev_get_regmap(&pdev->dev, NULL));
	return ret;
}
'''
t = edit(t, "static int cam_cc_sm8650_probe(struct platform_device *pdev)\n{\n\treturn qcom_cc_probe(pdev, &cam_cc_sm8650_desc);\n}\n",
         votes.lstrip("\n"), "camcc.probe")
wr("camcc-cliffs-uke.c", t)
for h in ("common.h", "clk-alpha-pll.h", "clk-branch.h", "clk-rcg.h", "clk-regmap.h", "clk-regmap-divider.h",
          "clk-regmap-mux.h", "gdsc.h", "reset.h", "vdd-class.h", "vdd-level.h"):
    p = os.path.join(KT, "drivers/clk/qcom", h)
    if os.path.exists(p):
        shutil.copy(p, os.path.join(ST, h))

# ---- 2. ov13b10: of_match + chip-id en el log ----------------------------------------------------------------------
t = rd("drivers/media/i2c/ov13b10.c")
t = edit(t, "static struct i2c_driver ov13b10_i2c_driver = {\n\t.driver = {\n\t\t.name = \"ov13b10\",\n",
         "static const struct of_device_id ov13b10_of_ids[] = {\n\t{ .compatible = \"ovti,ov13b10\" },\n\t{ }\n};\nMODULE_DEVICE_TABLE(of, ov13b10_of_ids);\n\n"
         "static struct i2c_driver ov13b10_i2c_driver = {\n\t.driver = {\n\t\t.name = \"ov13b10\",\n\t\t.of_match_table = ov13b10_of_ids,\n", "ov13.of")
t = edit(t, "\t\t\t\t     \"failed to get regulators\\n\");\n\treturn 0;\n}\n",
         "\t\t\t\t     \"failed to get regulators\\n\");\n"
         "\t/* uke: el rieles l20 arranca a su init-voltage (1,62 V) y el driver no fija tension: DOVDD 1,8 V, DVDD 1,2 V (rails vendor) */\n"
         "\tif (regulator_set_voltage(ov13b->supplies[0].consumer, 1800000, 1800000))\n\t\tdev_warn(ov13b->dev, \"uke: dovdd 1,8 V no fijado\\n\");\n"
         "\tif (regulator_set_voltage(ov13b->supplies[2].consumer, 1200000, 1200000))\n\t\tdev_warn(ov13b->dev, \"uke: dvdd 1,2 V no fijado\\n\");\n"
         "\treturn 0;\n}\n", "ov13.volt")
helper = r'''
/*
 * uke: gpiolib-shared (7.2) marca gpio14 como COMPARTIDO (el DT vendor lo cita en cam-sensor0 y eeprom0 con la propiedad "gpios"), lo pide
 * como "shared" al registrar el chip y rechaza a un consumidor posterior (overlay): devm_gpiod_get_optional() daba WARN + NULL y el reset
 * nunca se movia (C4: «failed to find sensor: -5»); gpiochip_request_own_desc da -EBUSY. Se maneja el XSHUTDN por PINCTRL (el pin esta
 * UNCLAIMED en pinmux): estado "default" = reset asertado (output-low), estado "rst_release" = liberado (output-high).
 */
static void uke_rst(struct device *dev, bool release)
{
	struct pinctrl_state *st;

	if (!dev->pins || IS_ERR_OR_NULL(dev->pins->p))
		return;
	st = pinctrl_lookup_state(dev->pins->p, release ? "rst_release" : "default");
	if (IS_ERR(st) || pinctrl_select_state(dev->pins->p, st))
		dev_warn(dev, "uke: no se pudo pasar el reset a %s\n", release ? "liberado" : "asertado");
}

static int ov13b10_power_off(struct device *dev)
'''
t = edit(t, "static int ov13b10_power_off(struct device *dev)\n", helper.lstrip("\n"), "ov13.helper")
t = edit(t, "\tgpiod_set_value_cansleep(ov13b10->reset, 1);\n", "\tuke_rst(dev, false);\n", "ov13.rst1")
t = edit(t, "\tgpiod_set_value_cansleep(ov13b10->reset, 0);\n", "\tusleep_range(1000, 1500);\n\tuke_rst(dev, true);\n", "ov13.rst0")
t = edit(t, "\tov13b->reset = devm_gpiod_get_optional(ov13b->dev, \"reset\",\n\t\t\t\t\t       GPIOD_OUT_LOW);\n", "\tov13b->reset = NULL;\n", "ov13.reset")
t = edit(t, "#include <linux/clk.h>\n", "#include <linux/clk.h>\n#include <linux/pinctrl/consumer.h>\n#include <linux/pinctrl/devinfo.h>\n", "ov13.inc3")
t = edit(t, "\tov13b->identified = true;\n", "\tov13b->identified = true;\n\tdev_info(ov13b->dev, \"uke: chip id 0x%06x leido por I2C (esperado 0x%06x)\\n\", val, OV13B10_CHIP_ID);\n", "ov13.info")
t = edit(t, "#include <linux/clk.h>\n", "#include <linux/clk.h>\n#include <linux/of.h>\n", "ov13.inc")
# C5b ciclo 8 (preparado 21-oct): sonda del lado sensor. uke_dump=1 lee ~18 registros CONCRETOS del OV13B10 tras arrancar el stream (a 50 y 400 ms);
# uke_xreg/uke_xval (xreg>=0) escribe UN registro extra tras la tabla del modo y antes de MODE_SELECT. Por defecto no cambian nada.
if os.environ.get("UKE_SENSDBG"):
    t = edit(t, "static int ov13b10_start_streaming(struct ov13b10 *ov13b)\n{",
             """static int uke_dump;
module_param(uke_dump, int, 0644);
MODULE_PARM_DESC(uke_dump, "1 = lee registros concretos del sensor tras arrancar el stream");
static int uke_xreg = -1;
module_param(uke_xreg, int, 0644);
MODULE_PARM_DESC(uke_xreg, "registro extra a escribir antes de MODE_SELECT (-1 = ninguno)");
static int uke_xval;
module_param(uke_xval, int, 0644);
MODULE_PARM_DESC(uke_xval, "valor del registro extra");

static void uke_sens_dump(struct ov13b10 *ov13b, const char *tag)
{
	static const u16 regs[] = { 0x0100, 0x0103, 0x0303, 0x0305, 0x0323, 0x0324, 0x0325, 0x0326, 0x0327, 0x3012, 0x3013,
				    0x4008, 0x4800, 0x4837, 0x5000, 0x5080, 0x3501, 0x0202 };
	char buf[256];
	int i, n = 0;
	u32 v;

	for (i = 0; i < ARRAY_SIZE(regs); i++) {
		if (ov13b10_read_reg(ov13b, regs[i], OV13B10_REG_VALUE_08BIT, &v))
			v = 0xffff;
		n += scnprintf(buf + n, sizeof(buf) - n, "%04x=%02x ", regs[i], v & 0xffff);
	}
	dev_info(ov13b->dev, "uke-sens %s: mode=%ux%u %s\\n", tag, ov13b->cur_mode->width, ov13b->cur_mode->height, buf);
}

static int ov13b10_start_streaming(struct ov13b10 *ov13b)
{""", "sens.fn")
    t = edit(t, "\t/* Apply customized values from user */\n\tret =  __v4l2_ctrl_handler_setup(ov13b->sd.ctrl_handler);\n\tif (ret)\n\t\treturn ret;\n\n\treturn ov13b10_write_reg(ov13b, OV13B10_REG_MODE_SELECT,\n\t\t\t\t OV13B10_REG_VALUE_08BIT,\n\t\t\t\t OV13B10_MODE_STREAMING);\n",
             "\t/* Apply customized values from user */\n\tret =  __v4l2_ctrl_handler_setup(ov13b->sd.ctrl_handler);\n\tif (ret)\n\t\treturn ret;\n\n"
             "\tif (uke_xreg >= 0) {\n\t\tdev_info(ov13b->dev, \"uke-sens: registro extra %04x=%02x\\n\", uke_xreg, uke_xval);\n\t\tov13b10_write_reg(ov13b, uke_xreg, OV13B10_REG_VALUE_08BIT, uke_xval);\n\t}\n"
             "\tret = ov13b10_write_reg(ov13b, OV13B10_REG_MODE_SELECT, OV13B10_REG_VALUE_08BIT, OV13B10_MODE_STREAMING);\n"
             "\tif (!ret && uke_dump) {\n\t\tmsleep(50);\n\t\tuke_sens_dump(ov13b, \"+50ms\");\n\t\tmsleep(350);\n\t\tuke_sens_dump(ov13b, \"+400ms\");\n\t}\n\treturn ret;\n", "sens.start")
    print("ov13b10: sonda del sensor (UKE_SENSDBG)")
wr("uke_ov13b10.c", t)

# ---- 3. ov08d10: chip_id esperado como parametro (el vendor lee 0x5647, el driver espera 0x5608) ------------------------
t = rd("drivers/media/i2c/ov08d10.c")
t = edit(t, "if ((chip_id & OV08D10_ID_MASK) != OV08D10_CHIP_ID) {",
         "dev_info(ov08d10->dev, \"uke: chip id 0x%04x leido por I2C (driver espera 0x%04x, vendor leyo 0x5647)\\n\", chip_id, OV08D10_CHIP_ID);\n"
         "\tif ((chip_id & OV08D10_ID_MASK) != OV08D10_CHIP_ID && chip_id != uke_chip_id) {", "ov08.id")
t = edit(t, "#define OV08D10_CHIP_ID\t\t\t0x5608\n",
         "#define OV08D10_CHIP_ID\t\t\t0x5608\n\nstatic unsigned int uke_chip_id = 0x5608;\nmodule_param(uke_chip_id, uint, 0444);\nMODULE_PARM_DESC(uke_chip_id, \"chip id alternativo aceptado (el vendor de la uke leyo 0x5647)\");\n", "ov08.param")
t = edit(t, "\t\t\t\t     \"failed to get regulators\\n\");\n\n\tv4l2_i2c_subdev_init(",
         "\t\t\t\t     \"failed to get regulators\\n\");\n\n"
         "\t/* uke: l20 arranca a 1,62 V: DOVDD 1,8 V, DVDD 1,2 V (supplies: dovdd, avdd, dvdd) */\n"
         "\tif (regulator_set_voltage(ov08d10->supplies[0].consumer, 1800000, 1800000))\n\t\tdev_warn(ov08d10->dev, \"uke: dovdd 1,8 V no fijado\\n\");\n"
         "\tif (regulator_set_voltage(ov08d10->supplies[2].consumer, 1200000, 1200000))\n\t\tdev_warn(ov08d10->dev, \"uke: dvdd 1,2 V no fijado\\n\");\n\n"
         "\tv4l2_i2c_subdev_init(", "ov08.volt")
# ciclo 23 (22-oct-2026): reset por PINCTRL como la trasera (gpio3 es egpio y sale en `gpios` del cam-sensor1 vendor -> gpiolib-shared):
# sin reset_control; "default" = asertado, "rst_release" = liberado; los retardos 5 ms / 8 ms del driver se conservan.
t = edit(t, "#include <linux/reset.h>\n", "#include <linux/reset.h>\n#include <linux/pinctrl/consumer.h>\n#include <linux/pinctrl/devinfo.h>\n", "ov08.inc")
t = edit(t, "static int ov08d10_power_off(struct device *dev)\n{", """static void uke_rst(struct device *dev, bool release)
{
	struct pinctrl_state *st;

	if (!dev->pins || IS_ERR_OR_NULL(dev->pins->p))
		return;
	st = pinctrl_lookup_state(dev->pins->p, release ? "rst_release" : "default");
	if (IS_ERR(st) || pinctrl_select_state(dev->pins->p, st))
		dev_warn(dev, "uke: no se pudo pasar el reset a %s\\n", release ? "liberado" : "asertado");
}

static int ov08d10_power_off(struct device *dev)
{""", "ov08.helper")
t = edit(t, "\treset_control_assert(ov08d10->reset);\n\n\tregulator_bulk_disable", "\tuke_rst(dev, false);\n\n\tregulator_bulk_disable", "ov08.rstoff")
t = edit(t, "\tif (ov08d10->reset) {\n\t\t/* Delay from DVDD stable to sensor XSHUTDN pull up: 5ms */\n\t\tfsleep(5 * USEC_PER_MSEC);\n\n\t\treset_control_deassert(ov08d10->reset);\n",
         "\t{\n\t\t/* Delay from DVDD stable to sensor XSHUTDN pull up: 5ms */\n\t\tfsleep(5 * USEC_PER_MSEC);\n\n\t\tuke_rst(dev, true);\n", "ov08.rston")
t = edit(t, "\tov08d10->reset = devm_reset_control_get_optional_exclusive(ov08d10->dev, NULL);\n", "\tov08d10->reset = NULL;\t/* uke: reset por pinctrl (uke_rst) */\n", "ov08.rstget")
wr("uke_ov08d10.c", t)

# ---- 4. camss: recurso cliffs = sm8650 con 5 CSIPHY y SIN rutas ICC ------------------------------------------------------
src = os.path.join(KT, "drivers/media/platform/qcom/camss")
for f in sorted(os.listdir(src)):
    if f.endswith((".c", ".h")):
        shutil.copy(os.path.join(src, f), os.path.join(ST, f))
t = open(os.path.join(ST, "camss.c")).read()
res = '''static const struct camss_resources cliffs_resources = {
	.version = CAMSS_8650,
	.pd_name = "top",
	.csiphy_res = csiphy_res_sm8650,
	.csid_res = csid_res_sm8650,
	.csid_wrapper_res = &csid_wrapper_res_sm8550,
	.vfe_res = vfe_res_sm8650,
	/* uke: sin ICC (la capa interconnect cliffs de senemos no tiene CAMNOC_HF); 5 CSIPHY (no hay csiphy5) */
	.csiphy_num = 5,
	.csid_num = ARRAY_SIZE(csid_res_sm8650),
	.vfe_num = ARRAY_SIZE(vfe_res_sm8650),
};

'''
t = edit(t, "static const struct camss_resources sm8650_resources = {", res + "static const struct camss_resources sm8650_resources = {", "camss.res")
t = edit(t, '\t{ .compatible = "qcom,sm8650-camss", .data = &sm8650_resources },\n',
         '\t{ .compatible = "qcom,sm8650-camss", .data = &sm8650_resources },\n\t{ .compatible = "qcom,cliffs-camss", .data = &cliffs_resources },\n', "camss.match")
n = t.count('.name = "qcom-camss"')
if n != 1:
    sys.exit("FALLO camss.name: %d" % n)
# ciclo 22 (22-oct-2026): libcamera (pipeline simple + softISP) reconoce camss por el nombre del driver del media device ("qcom-camss").
# UKE_CAMSS_NAME=qcom-camss conserva el nombre de mainline (el qcom-camss.ko del arbol no casa con qcom,cliffs-camss y no se carga).
t = t.replace('.name = "qcom-camss"', '.name = "%s"' % os.environ.get("UKE_CAMSS_NAME", "uke-camss"))
# H-PHY2 (C5b, 20-oct): en Android cphy_rx_clk_src corre a 19,2 MHz (solo el timer del PHY a 400 MHz); camss pide 400 MHz al "csiphy_rx" del CSID
# (primer valor de la lista). UKE_CPHY_RX_HZ=19200000 genera la variante de prueba (por defecto: sin cambio).
hz = os.environ.get("UKE_CPHY_RX_HZ")
if hz:
    a = t.index("static const struct camss_subdev_resources csid_res_sm8650[]")
    b = t.index("\n};\n", a)
    blk = t[a:b]
    old_v = "{ 400000000, 480000000 } },"
    n = blk.count(old_v)
    if n < 1:
        sys.exit("FALLO camss.cphyrx: no hay %r en csid_res_sm8650" % old_v)
    t = t[:a] + blk.replace(old_v, "{ %s, 480000000 } }," % hz) + t[b:]
    print("camss: csiphy_rx del CSID a %s Hz en %d entradas de csid_res_sm8650" % (hz, n))
open(os.path.join(ST, "camss.c"), "w").write(t)
# H-PHY1/3 (C5b ciclo 3, 20-oct): UKE_PHY_LOG=1 registra lo que camss programa en el CSIPHY (lanes, settle y ~10 registros CONCRETOS leidos tras escribirlos;
# sin volcados de rango). Por defecto no cambia nada.
if os.environ.get("UKE_PHY_LOG"):
    pp = os.path.join(ST, "camss-csiphy-3ph-1-0.c")
    t3 = open(pp).read()
    old3 = """	/* IRQ_MASK registers - disable all interrupts */
	for (i = 11; i < 22; i++) {
		writel_relaxed(0, csiphy->base +
			       CSIPHY_3PH_CMN_CSI_COMMON_CTRLn(regs->offset, i));
	}
}
"""
    assert t3.count(old3) == 1, "phylog.anchor"
    new3 = old3[:-2] + r"""
	if (uke_skew) {
		/* vendor 2.2.1 bloque skew-cal (lanes en 0x000/0x400/0x800/0xC00): +0x94=D7 +0x5C=04 +0x60=BD +0x64=7F; mainline sm8650 lo omite */
		int ln;
		for (ln = 0; ln < 4; ln++) {
			writel_relaxed(0xd7, csiphy->base + ln * 0x400 + 0x94);
			writel_relaxed(0x04, csiphy->base + ln * 0x400 + 0x5c);
			writel_relaxed(0xbd, csiphy->base + ln * 0x400 + 0x60);
			writel_relaxed(0x7f, csiphy->base + ln * 0x400 + 0x64);
		}
		dev_info(csiphy->camss->dev, "uke-phy: skew-cal vendor aplicado\n");
	}
	if (uke_ctl0_post >= 0) {
		/* vendor (camera-kernel uke-v-oss, cam_csiphy_release_from_reset_state, D-PHY): 0x1000=0x02 tras tablas y mascaras */
		writel_relaxed(uke_ctl0_post, csiphy->base + CSIPHY_3PH_CMN_CSI_COMMON_CTRLn(regs->offset, 0));
		dev_info(csiphy->camss->dev, "uke-phy: CTRL0 post-lanes = 0x%02x\n", uke_ctl0_post);
	}
	{
		/* uke-phy (C5b, solo lectura de ~10 registros concretos) */
		const struct csiphy_lane_regs *lr = regs->lane_regs;
		struct device *d = csiphy->camss->dev;
		int k, shown = 0;
		u32 st0 = readl_relaxed(csiphy->base + regs->offset + regs->common_status_offset);
		u32 st1 = readl_relaxed(csiphy->base + regs->offset + regs->common_status_offset + 4);

		dev_info(d, "uke-phy: id=%u lanes=%u clk_pos=%u data_pos=%u,%u,%u,%u link_freq=%lld timer_clk=%lu settle=%u mask=0x%02x offset=0x%x status_off=0x%x\n",
			 csiphy->id, c->num_data, c->clk.pos, c->data[0].pos, c->num_data > 1 ? c->data[1].pos : 99,
			 c->num_data > 2 ? c->data[2].pos : 99, c->num_data > 3 ? c->data[3].pos : 99,
			 link_freq, (unsigned long)csiphy->timer_clk_rate, settle_cnt, lane_mask, regs->offset, regs->common_status_offset);
		dev_info(d, "uke-phy: ctrl0=%08x ctrl5=%08x ctrl6=%08x ctrl7=%08x stat0=%08x stat1=%08x (version/stat regs)\n",
			 readl_relaxed(csiphy->base + CSIPHY_3PH_CMN_CSI_COMMON_CTRLn(regs->offset, 0)),
			 readl_relaxed(csiphy->base + CSIPHY_3PH_CMN_CSI_COMMON_CTRLn(regs->offset, 5)),
			 readl_relaxed(csiphy->base + CSIPHY_3PH_CMN_CSI_COMMON_CTRLn(regs->offset, 6)),
			 readl_relaxed(csiphy->base + CSIPHY_3PH_CMN_CSI_COMMON_CTRLn(regs->offset, 7)), st0, st1);
		for (k = 0; k < regs->lane_array_size && shown < 4; k++, lr++) {
			if (lr->csiphy_param_type == CSIPHY_SKEW_CAL || lr->csiphy_param_type == CSIPHY_DNP_PARAMS)
				continue;
			dev_info(d, "uke-phy: lane_reg[%d] addr=0x%x type=%d escrito=0x%02x leido=0x%08x\n", k, lr->reg_addr,
				 lr->csiphy_param_type, lr->csiphy_param_type == CSIPHY_SETTLE_CNT_LOWER_BYTE ? (settle_cnt & 0xff) : lr->reg_data,
				 readl_relaxed(csiphy->base + lr->reg_addr));
			shown++;
		}
	}
}
"""
    t3 = t3.replace(old3, new3)
    open(pp, "w").write(t3)
    print("camss: log uke-phy en csiphy_lanes_enable")

# C5b ciclo 4 (20-oct): parametro de settle del PHY (por defecto -1 = el calculado, sin cambio) y log del CSID (solo lecturas de registros concretos).
if os.environ.get("UKE_PHY_LOG"):
    pp = os.path.join(ST, "camss-csiphy-3ph-1-0.c")
    t3 = open(pp).read()
    old_s = "	settle_cnt = csiphy_settle_cnt_calc(link_freq, csiphy->timer_clk_rate);\n"
    assert t3.count(old_s) == 1, "settle.anchor"
    t3 = t3.replace(old_s, old_s + """	if (uke_settle >= 0) {
		dev_info(csiphy->camss->dev, "uke-phy: settle calculado %u -> parametro %d\\n", settle_cnt, uke_settle);
		settle_cnt = uke_settle;
	}
""")
    old_c7 = """	val = 0x02;
	writel_relaxed(val, csiphy->base +
		       CSIPHY_3PH_CMN_CSI_COMMON_CTRLn(regs->offset, 7));
"""
    assert t3.count(old_c7) == 1, "ctl7.anchor"
    t3 = t3.replace(old_c7, """	val = uke_ctl7 >= 0 ? uke_ctl7 : 0x02;
	writel_relaxed(val, csiphy->base +
		       CSIPHY_3PH_CMN_CSI_COMMON_CTRLn(regs->offset, 7));
""")
    old_c5 = """	val = CSIPHY_3PH_CMN_CSI_COMMON_CTRL5_CLK_ENABLE;
	for (i = 0; i < c->num_data; i++)
		val |= BIT(c->data[i].pos * 2);
"""
    assert t3.count(old_c5) == 1, "cmn84.anchor"
    t3 = t3.replace(old_c5, """	if (uke_cmn84) {
		writel_relaxed(0, csiphy->base + 0x1084);
		writel_relaxed(0, csiphy->base + 0x108c);
		udelay(1);
	}
""" + old_c5)
    old_i = "static void csiphy_lanes_enable("
    assert t3.count(old_i) == 1, "settle.param"
    t3 = t3.replace(old_i, """static int uke_settle = -1;
module_param(uke_settle, int, 0644);
MODULE_PARM_DESC(uke_settle, "settle count del PHY (-1 = el calculado)");
static int uke_skew = 0;
module_param(uke_skew, int, 0644);
MODULE_PARM_DESC(uke_skew, "1 = aplica el bloque skew-cal del vendor tras las tablas");
static int uke_ctl7 = -1;
module_param(uke_ctl7, int, 0644);
MODULE_PARM_DESC(uke_ctl7, "valor de CTRL7 (0x101c); -1 = 0x02 de mainline; vendor = 0x7a");
static int uke_ctl0_post = -1;
module_param(uke_ctl0_post, int, 0644);
MODULE_PARM_DESC(uke_ctl0_post, "si >=0 escribe CTRL0 (0x1000) tras las tablas (vendor: 0x02)");
static int uke_cmn84 = 0;
module_param(uke_cmn84, int, 0644);
MODULE_PARM_DESC(uke_cmn84, "1 = escribe 0x1084=0 y 0x108c=0 antes de CTRL5 (como el vendor)");

""" + old_i)
    open(pp, "w").write(t3)
if os.environ.get("UKE_CSID_LOG"):
    cp = os.path.join(ST, "camss-csid-gen3.c")
    t4 = open(cp).read()
    old_c = """			__csid_configure_rx(csid, &csid->phy, 0);
			__csid_ctrl_rdi(csid, enable, i);
		}
}
"""
    assert t4.count(old_c) == 1, "csidlog.anchor"
    new_c = """			__csid_configure_rx(csid, &csid->phy, 0);
			__csid_ctrl_rdi(csid, enable, i);
			if (i == 0)
				dev_info(csid->camss->dev,
					 "uke-csid%u %s: lanes=%u assign=0x%x csiphy_id=%u rx_cfg0=%08x rx_cfg1=%08x rdi_cfg0=%08x rdi_cfg1=%08x rdi_ctrl=%08x rx_irq_st=%08x top_irq_st=%08x bufdone_st=%08x rdin_st=%08x\\n",
					 csid->id, enable ? "start" : "stop", csid->phy.lane_cnt, csid->phy.lane_assign, csid->phy.csiphy_id,
					 readl(csid->base + CSID_CSI2_RX_CFG0), readl(csid->base + CSID_CSI2_RX_CFG1),
					 readl(csid->base + CSID_RDI_CFG0(0)), readl(csid->base + CSID_RDI_CFG1(0)), readl(csid->base + CSID_RDI_CTRL(0)),
					 readl(csid->base + CSID_CSI2_RX_IRQ_STATUS), readl(csid->base + CSID_TOP_IRQ_STATUS),
					 readl(csid->base + CSID_BUF_DONE_IRQ_STATUS), readl(csid->base + CSID_CSI2_RDIN_IRQ_STATUS(0)));
		}
}
"""
    t4 = t4.replace(old_c, new_c)
    open(cp, "w").write(t4)
    print("camss: log uke-csid en csid_configure_stream")

# C5b ciclo 5 (preparado 21-oct): UKE_RXIRQ=1 HABILITA el IRQ del RX del CSI-2 y de los RDI en el CSID (el driver gen3 solo enmascara TOP y BUF_DONE) y registra
# lo que el hardware diga (con presupuesto de mensajes: al agotarse se vuelve a enmascarar). Es una escritura de configuracion reversible (mascaras de IRQ), no un volcado.
if os.environ.get("UKE_RXIRQ"):
    cp = os.path.join(ST, "camss-csid-gen3.c")
    t4 = open(cp).read()
    old_h = "#define CSI2_RX_CFG0_PHY_SEL_BASE_IDX	1\n"
    assert t4.count(old_h) == 1, "rxirq.isr"
    t4 = t4.replace(old_h, old_h + """static unsigned int uke_rx_mask = 0xffffffff;
module_param(uke_rx_mask, uint, 0644);
MODULE_PARM_DESC(uke_rx_mask, "mascara del IRQ del RX del CSI-2 del CSID (0 = como el driver original)");
static unsigned int uke_rdin_mask = 0xffffffff;
module_param(uke_rdin_mask, uint, 0644);
MODULE_PARM_DESC(uke_rdin_mask, "mascara del IRQ de RDI del CSID (0 = como el driver original)");
static int uke_rdi_budget = 100;
module_param(uke_rdi_budget, int, 0644);
MODULE_PARM_DESC(uke_rdi_budget, "mensajes de IRQ de RDI a registrar");
static int uke_cap_ctrl = -1;
module_param(uke_cap_ctrl, int, 0644);
MODULE_PARM_DESC(uke_cap_ctrl, "si >=0 escribe CSID_CSI2_RX_CAPTURE_CTRL (0x208) al arrancar (vendor: bit0 long, bit1 short, dt<<4, vc<<10, vc corto<<15)");
static int uke_cap_n = 0;
module_param(uke_cap_n, int, 0644);
MODULE_PARM_DESC(uke_cap_n, "n de IRQ de RX en los que se leen los registros de captura de paquetes");
static void uke_cap_dump(struct csid_device *csid, const char *tag)
{
	dev_info(csid->camss->dev,
		 "uke-cap%u %s: capctrl=%08x unmap_hdr0=%08x short0=%08x long0=%08x long1=%08x total_pkts=%08x ecc=%08x crc=%08x\\n",
		 csid->id, tag, readl(csid->base + 0x208), readl(csid->base + 0x210), readl(csid->base + 0x218),
		 readl(csid->base + 0x220), readl(csid->base + 0x224), readl(csid->base + 0x240),
		 readl(csid->base + 0x244), readl(csid->base + 0x248));
}
static int uke_lane_assign = -1;
module_param(uke_lane_assign, int, 0644);
MODULE_PARM_DESC(uke_lane_assign, "si >=0 sustituye phy->lane_assign (4 bits por lane; 0x3210 = identidad)");
static int uke_stat;
module_param(uke_stat, int, 0644);
MODULE_PARM_DESC(uke_stat, "1 = cuenta por bit TODAS las IRQ de RX y RDI0 del stream, anota los eventos de RDI0 que no son SOL/EOL y los BUF_DONE (solo memoria); se lee en uke_statline");
static u32 uke_rxc[32], uke_rdic[32], uke_irqn, uke_rdin, uke_c00, uke_bufdone;
static ktime_t uke_t0k;
struct uke_ev { u32 us; u32 kind; u32 val; u32 rxirq; u32 ecc; u32 sot; };
static struct uke_ev uke_evs[96];
static u32 uke_evn;
static void uke_stat_count(u32 *c, u32 v)
{
	while (v) {
		int b = __builtin_ctz(v);

		c[b]++;
		v &= v - 1;
	}
}
static void uke_ev_add(u32 kind, u32 val)
{
	struct uke_ev *e = &uke_evs[uke_evn++ % ARRAY_SIZE(uke_evs)];

	e->us = (u32)ktime_to_us(ktime_sub(ktime_get(), uke_t0k));
	e->kind = kind;
	e->val = val;
	e->rxirq = uke_irqn;
	e->ecc = uke_rxc[20];
	e->sot = uke_rxc[4] + uke_rxc[5] + uke_rxc[6] + uke_rxc[7];
}
static void uke_stat_reset(void)
{
	memset(uke_rxc, 0, sizeof(uke_rxc));
	memset(uke_rdic, 0, sizeof(uke_rdic));
	memset(uke_evs, 0, sizeof(uke_evs));
	uke_irqn = 0;
	uke_rdin = 0;
	uke_c00 = 0;
	uke_bufdone = 0;
	uke_evn = 0;
	uke_t0k = ktime_get();
}
/* lectura (solo memoria, sin tocar registros): resumen + los ultimos 96 eventos de RDI0 que no son SOL/EOL (kind 1) y los BUF_DONE (kind 2) */
static int uke_statline_get(char *buf, const struct kernel_param *kp)
{
	int i, n = 0, first = uke_evn > ARRAY_SIZE(uke_evs) ? uke_evn - ARRAY_SIZE(uke_evs) : 0;

	n += scnprintf(buf + n, PAGE_SIZE - n, "t=%uus rx_irq=%u rdi_irq=%u c00=%u bufdone=%u eventos=%u\\nRX[", (u32)ktime_to_us(ktime_sub(ktime_get(), uke_t0k)), uke_irqn, uke_rdin, uke_c00, uke_bufdone, uke_evn);
	for (i = 0; i < 32; i++)
		if (uke_rxc[i])
			n += scnprintf(buf + n, PAGE_SIZE - n, " b%d:%u", i, uke_rxc[i]);
	n += scnprintf(buf + n, PAGE_SIZE - n, " ]\\nRDI0[");
	for (i = 0; i < 32; i++)
		if (uke_rdic[i])
			n += scnprintf(buf + n, PAGE_SIZE - n, " b%d:%u", i, uke_rdic[i]);
	n += scnprintf(buf + n, PAGE_SIZE - n, " ]\\n");
	for (i = first; i < uke_evn && n < PAGE_SIZE - 80; i++) {
		struct uke_ev *e = &uke_evs[i % ARRAY_SIZE(uke_evs)];

		n += scnprintf(buf + n, PAGE_SIZE - n, "EV %u %uus k%u %08x rx=%u ecc=%u sot=%u\\n", i, e->us, e->kind, e->val, e->rxirq, e->ecc, e->sot);
	}
	return n;
}
module_param_call(uke_statline, NULL, uke_statline_get, NULL, 0444);
MODULE_PARM_DESC(uke_statline, "solo lectura: contadores de RX/RDI0 del ultimo stream y ultimos 96 eventos (memoria)");
static int uke_rx_budget = 200;
module_param(uke_rx_budget, int, 0644);
MODULE_PARM_DESC(uke_rx_budget, "mensajes de IRQ a registrar antes de volver a enmascarar");

""")
    old_r = """	val = readl(csid->base + CSID_CSI2_RX_IRQ_STATUS);
	writel(val, csid->base + CSID_CSI2_RX_IRQ_CLEAR);
"""
    assert t4.count(old_r) == 1, "rxirq.rx"
    t4 = t4.replace(old_r, old_r + """	if (val && uke_stat) {
		uke_irqn++;
		uke_stat_count(uke_rxc, val);
	}
	if (val && uke_rx_budget > 0) {
		uke_rx_budget--;
		dev_info(csid->camss->dev, "uke-csid%u: RX_IRQ=%08x TOP=%08x\\n", csid->id, val, reset_done);
		if (uke_cap_n > 0) {
			uke_cap_n--;
			uke_cap_dump(csid, "irq");
		}
		if (!uke_rx_budget) {
			writel(0, csid->base + CSID_CSI2_RX_IRQ_MASK);
			dev_info(csid->camss->dev, "uke-csid%u: presupuesto agotado, RX IRQ enmascarado\\n", csid->id);
		}
	}
""")
    old_d = """			val = readl(csid->base + CSID_CSI2_RDIN_IRQ_STATUS(i));
			writel(val, csid->base + CSID_CSI2_RDIN_IRQ_CLEAR(i));
"""
    assert t4.count(old_d) == 1, "rxirq.rdin"
    t4 = t4.replace(old_d, old_d + """			if (uke_stat && i == 0) {
				if (val) {
					uke_rdin++;
					uke_stat_count(uke_rdic, val);
					if (val & ~0xc00u)
						uke_ev_add(1, val);
					else
						uke_c00++;
				}
				if (buf_done_val & BIT(BUF_DONE_IRQ_STATUS_RDI_OFFSET + i)) {
					uke_bufdone++;
					uke_ev_add(2, buf_done_val);
				}
			}
			if (val && uke_rdi_budget > 0) {
				uke_rdi_budget--;
				dev_info(csid->camss->dev, "uke-csid%u: RDI%d_IRQ=%08x\\n", csid->id, i, val);
			}
""")
    old_la = "	val |= phy->lane_assign << CSI2_RX_CFG0_DL0_INPUT_SEL;\n"
    assert t4.count(old_la) == 1, "lane_assign.anchor"
    t4 = t4.replace(old_la, "	val |= (uke_lane_assign >= 0 ? (u32)uke_lane_assign : phy->lane_assign) << CSI2_RX_CFG0_DL0_INPUT_SEL;\n")
    old_s = """			__csid_ctrl_rdi(csid, enable, i);
"""
    assert t4.count(old_s) == 1, "rxirq.cfg"
    t4 = t4.replace(old_s, old_s + """			if (enable && i == 0)
				uke_stat_reset();
			if (enable && uke_cap_ctrl >= 0)
				writel(uke_cap_ctrl, csid->base + 0x208);
			if (!enable && uke_cap_ctrl >= 0)
				uke_cap_dump(csid, "stop");
			if (!enable) {
				writel(0, csid->base + CSID_CSI2_RX_IRQ_MASK);
				writel(0, csid->base + 0xF0 + 0x10 * i);
			}
			if (enable) {
				writel(uke_rx_mask, csid->base + CSID_CSI2_RX_IRQ_MASK);
				writel(uke_rdin_mask, csid->base + 0xF0 + 0x10 * i);	/* CSID_CSI2_RDIN_IRQ_MASK(rdi) */
			}
""")
    # ciclo 24 (22-oct-2026): la frontal llega al RDI (INFO_INPUT_SOL/EOL) pero solo dispara VCDT_GRP1_SEL y ninguna linea sale (sin EPOCH, sin
    # BUF_DONE); la trasera dispara GRP0 y GRP1. Parametros para forzar el VC/DT del RDI y su cfg1 (mainline activa crop/drop sin programar
    # ventanas) y lectura de 5 registros CONCRETOS del RDI0 al arrancar (multi_vcdt 0x50c, frm_drop 0x540/0x544, hcrop/vcrop 0x550/0x554;
    # offsets de cam_ife_csid880.h del vendor). Por defecto no cambia nada.
    old_v = "\t\t\t__csid_configure_rdi_stream(csid, enable, i, 0);\n"
    assert t4.count(old_v) == 1, "rdi.vc"
    t4 = t4.replace(old_v, "\t\t\t__csid_configure_rdi_stream(csid, enable, i, uke_rdi_vc >= 0 ? uke_rdi_vc : 0);\n")
    old_dt = "\tval |= format->data_type << RDI_CFG0_DT;\n"
    assert t4.count(old_dt) == 1, "rdi.dt"
    t4 = t4.replace(old_dt, "\tval |= (uke_rdi_dt >= 0 ? (u32)uke_rdi_dt : format->data_type) << RDI_CFG0_DT;\n")
    old_c1 = "\twritel(val, csid->base + CSID_RDI_CFG1(port));\n"
    assert t4.count(old_c1) == 1, "rdi.cfg1"
    t4 = t4.replace(old_c1, "\tif (uke_rdi_cfg1 >= 0)\n\t\tval = uke_rdi_cfg1;\n\twritel(val, csid->base + CSID_RDI_CFG1(port));\n")
    old_p = "static int uke_rx_budget = 200;\n"
    assert t4.count(old_p) == 1, "rdi.params"
    t4 = t4.replace(old_p, """static int uke_rdi_vc = -1;
module_param(uke_rdi_vc, int, 0644);
MODULE_PARM_DESC(uke_rdi_vc, "si >=0 fuerza el VC del RDI (mainline: 0)");
static int uke_rdi_dt = -1;
module_param(uke_rdi_dt, int, 0644);
MODULE_PARM_DESC(uke_rdi_dt, "si >=0 fuerza el DT del RDI (mainline: el del formato, 0x2b para RAW10)");
static int uke_rdi_cfg1 = -1;
module_param(uke_rdi_cfg1, int, 0644);
MODULE_PARM_DESC(uke_rdi_cfg1, "si >=0 sustituye RDI_CFG1 (mainline 0x85e0 = packing MIPI + pix store + crop/drop H/V; sin crop/drop: 0x8400)");
""" + old_p)
    old_s = "\t\t\tif (enable && i == 0)\n\t\t\t\tuke_stat_reset();\n"
    assert t4.count(old_s) == 1, "rdi.regs"
    t4 = t4.replace(old_s, old_s + """\t\t\tif (enable && i == 0)
\t\t\t\tdev_info(csid->camss->dev, "uke-rdi0: vc=%d dt=0x%x cfg0=%08x cfg1=%08x multi_vcdt=%08x frm_drop_pat=%08x frm_drop_per=%08x hcrop=%08x vcrop=%08x\\n",
\t\t\t\t\t uke_rdi_vc, uke_rdi_dt, readl(csid->base + CSID_RDI_CFG0(0)), readl(csid->base + CSID_RDI_CFG1(0)),
\t\t\t\t\t readl(csid->base + 0x50c), readl(csid->base + 0x540), readl(csid->base + 0x544),
\t\t\t\t\t readl(csid->base + 0x550), readl(csid->base + 0x554));
""")
    open(cp, "w").write(t4)
    print("camss: IRQ del RX/RDI del CSID habilitado + log (UKE_RXIRQ)")

print("gen-modules: OK ->", ST)
