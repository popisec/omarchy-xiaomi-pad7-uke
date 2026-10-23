// SPDX-License-Identifier: GPL-2.0
/*
 * uke_lpi_io.c — E3d: VALIDA EL METODO DE MEDIDA de uke_lpi_rd (leer VALUE.IN de un pad LPI). BORRADOR DEL PC (18-oct-2026): compila contra ouke4; NO probado en la tablet.
 *
 * Con los votos PRM activos (pm_runtime_resume_and_get, como el driver LPI) y SOLO sobre un pin de la lista blanca {15,16,17,18} (sin ninguna funcion en los
 * pinctrl del DT de Android: no estan cableados a nada conocido): guarda CFG y VALUE, lo pone en funcion GPIO como SALIDA (VALUE.OUT antes de OE, como pide el
 * manual), alterna OUT 0/1 `uke_lpi_cycles` veces leyendo IN tras cada escritura y cuenta cuantas veces IN sigue a OUT; despues RESTAURA CFG y VALUE originales.
 * Resultado esperado si leer IN funciona: coincidencias = ciclos, transiciones ~ 2*ciclos-1. Con uke_lpi_go=0 (defecto) solo hace las comprobaciones y
 * las LECTURAS de CFG/VALUE (ninguna escritura).
 * NO toca gpio6-9 (TDM), 0-5 (SWR/quat), 12 (reset del WCD) ni 13.
 */
#include <linux/module.h>
#include <linux/io.h>
#include <linux/delay.h>
#include <linux/ioport.h>
#include <linux/platform_device.h>
#include <linux/pm_runtime.h>

#define UKE_LPI_NAME	"6e80000.pinctrl"
#define UKE_LPI_STRIDE	0x1000
#define CFG_REG		0x00
#define VAL_REG		0x04
#define CFG_FUNC	GENMASK(5, 2)
#define CFG_OE		BIT(9)
#define VAL_IN		BIT(0)
#define VAL_OUT		BIT(1)

static uint uke_lpi_pin = 16;
module_param(uke_lpi_pin, uint, 0444);
MODULE_PARM_DESC(uke_lpi_pin, "pin de la lista blanca 15..18 (defecto 16)");
static uint uke_lpi_cycles = 2000;
module_param(uke_lpi_cycles, uint, 0444);
MODULE_PARM_DESC(uke_lpi_cycles, "ciclos OUT 1/0 (1..20000, defecto 2000)");
static bool uke_lpi_go;
module_param(uke_lpi_go, bool, 0444);
MODULE_PARM_DESC(uke_lpi_go, "1 = hacer la prueba con escrituras al pin (defecto 0: solo lecturas)");

static int __init uke_lpi_io_init(void)
{
	struct platform_device *pdev;
	struct device *dev;
	struct resource *res;
	void __iomem *p;
	phys_addr_t pa;
	u32 cfg0, val0, cfg, i, n, good = 0, trans = 0, prev = 2, b;
	int ret;

	if (uke_lpi_pin < 15 || uke_lpi_pin > 18 || !uke_lpi_cycles || uke_lpi_cycles > 20000)
		return -EINVAL;
	dev = bus_find_device_by_name(&platform_bus_type, NULL, UKE_LPI_NAME);
	if (!dev || !dev->driver) {
		pr_err("uke_lpi_io: %s no existe o sin driver\n", UKE_LPI_NAME);
		if (dev)
			put_device(dev);
		return -ENODEV;
	}
	pdev = to_platform_device(dev);
	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (!res || resource_size(res) < (resource_size_t)UKE_LPI_STRIDE * 23) {
		put_device(dev);
		return -EINVAL;
	}
	pa = res->start + (phys_addr_t)UKE_LPI_STRIDE * uke_lpi_pin;
	ret = pm_runtime_resume_and_get(dev);
	if (ret < 0) {
		put_device(dev);
		return ret;
	}
	if (!pm_runtime_active(dev)) {
		ret = -EIO;
		goto out_put;
	}
	p = ioremap(pa, 8);
	if (!p) {
		ret = -ENOMEM;
		goto out_put;
	}
	cfg0 = ioread32(p + CFG_REG);
	val0 = ioread32(p + VAL_REG);
	pr_info("uke_lpi_io: gpio%u antes: CFG=0x%08x VALUE=0x%08x go=%d\n", uke_lpi_pin, cfg0, val0, uke_lpi_go);
	if (!uke_lpi_go) {
		ret = 0;
		goto out_unmap;
	}
	n = uke_lpi_cycles;
	/* GPIO como salida: primero el valor, despues OE (manual de programacion) */
	iowrite32(val0 & ~VAL_OUT, p + VAL_REG);
	cfg = (cfg0 & ~CFG_FUNC) | CFG_OE;
	iowrite32(cfg, p + CFG_REG);
	for (i = 0; i < n; i++) {
		iowrite32(VAL_OUT, p + VAL_REG);
		b = ioread32(p + VAL_REG) & VAL_IN;
		if (b)
			good++;
		if (prev != 2 && b != prev)
			trans++;
		prev = b;
		iowrite32(0, p + VAL_REG);
		b = ioread32(p + VAL_REG) & VAL_IN;
		if (!b)
			good++;
		if (b != prev)
			trans++;
		prev = b;
	}
	{
		/* 2.a prueba: raw de VALUE tras OUT=1/0 y lectura con el pin como ENTRADA y pull-up / pull-down (independiente de OE): IN debe ser 1 con pull-up y 0 con pull-down */
		u32 raw1, raw0, up, dn, nopull;

		iowrite32(VAL_OUT, p + VAL_REG);
		raw1 = ioread32(p + VAL_REG);
		iowrite32(0, p + VAL_REG);
		raw0 = ioread32(p + VAL_REG);
		iowrite32((cfg0 & ~(CFG_FUNC | CFG_OE | GENMASK(1, 0))) | 3, p + CFG_REG);	/* entrada, pull-up */
		udelay(100);
		up = ioread32(p + VAL_REG);
		iowrite32((cfg0 & ~(CFG_FUNC | CFG_OE | GENMASK(1, 0))) | 1, p + CFG_REG);	/* entrada, pull-down */
		udelay(100);
		dn = ioread32(p + VAL_REG);
		iowrite32((cfg0 & ~(CFG_FUNC | CFG_OE | GENMASK(1, 0))), p + CFG_REG);		/* entrada, sin pull */
		udelay(100);
		nopull = ioread32(p + VAL_REG);
		pr_info("uke_lpi_io: gpio%u VALUE crudo tras OUT=1: 0x%08x, tras OUT=0: 0x%08x; como entrada: pull-up 0x%08x, pull-down 0x%08x, sin pull 0x%08x\n",
			uke_lpi_pin, raw1, raw0, up, dn, nopull);
	}
	/* restaurar exactamente lo guardado (primero CFG, luego VALUE) */
	iowrite32(cfg0, p + CFG_REG);
	iowrite32(val0, p + VAL_REG);
	pr_info("uke_lpi_io: gpio%u: %u escrituras OUT, IN siguio a OUT en %u de %u lecturas, transiciones=%u; restaurado CFG=0x%08x VALUE=0x%08x\n",
		uke_lpi_pin, 2 * n, good, 2 * n, trans, ioread32(p + CFG_REG), ioread32(p + VAL_REG));
	ret = 0;
out_unmap:
	iounmap(p);
out_put:
	pm_runtime_put_autosuspend(dev);
	put_device(dev);
	return ret;
}

static void __exit uke_lpi_io_exit(void)
{
}

module_init(uke_lpi_io_init);
module_exit(uke_lpi_io_exit);
MODULE_DESCRIPTION("uke E3d: validacion de la lectura de VALUE.IN con un pin LPI libre");
MODULE_LICENSE("GPL");
