// SPDX-License-Identifier: GPL-2.0
/*
 * uke_lpi_rd.c — E3c: UNA lectura de 32 bit del registro CFG de UN pin del TLMM del LPASS (pinctrl@6e80000), con los votos PRM activos.
 * BORRADOR DEL PC (18-oct-2026): compila contra ouke4; NO probado en la tablet. Solo lectura: no escribe ningun registro.
 *
 * Camino: busca el dispositivo `6e80000.pinctrl` (ya ligado a pinctrl-sm8650-lpass-lpi, E3a), pide `pm_runtime_resume_and_get()`, que es EXACTAMENTE
 * lo que hace el driver antes de cualquier acceso (E3b: vota LPASS_HW_MACRO y LPASS_HW_DCODEC por PRM y los confirma), comprueba que sigue activo y,
 * solo si uke_lpi_go=1, hace UN readl() en  base + 0x1000 * pin + 0x00  (LPI_TLMM_REG_OFFSET * pin + LPI_GPIO_CFG_REG; sm8650 no usa offsets predefinidos).
 *
 * Parametros (todos validados; nada que dependa de entrada libre):
 *   uke_lpi_pin  0..22, defecto 13 (dmic3_data/i2s3_ws: sin consumidor en la tablet; no es gpio12=reset del WCD, ni gpio6-9=TDM de los amps, ni gpio0-5)
 *   uke_lpi_go   0 (defecto) = solo resume/votos y comprobaciones, SIN MMIO; 1 = ademas la lectura unica.
 * NOTA: sin module_exit el modulo no se puede descargar (la 1.a version, uke_lpi_read, quedo cargada en E3c-2 hasta el proximo arranque);
 * por eso esta version se llama uke_lpi_rd y lleva un exit vacio.
 * Siempre libera la referencia PM (put_autosuspend). Devuelve 0 si todo fue bien; si falla algo antes de la lectura devuelve error y NO lee.
 */
#include <linux/module.h>
#include <linux/io.h>
#include <linux/ioport.h>
#include <linux/platform_device.h>
#include <linux/pm_runtime.h>

#define UKE_LPI_NAME	"6e80000.pinctrl"
#define UKE_LPI_STRIDE	0x1000
#define UKE_LPI_NPINS	23

static uint uke_lpi_pin = 13;
module_param(uke_lpi_pin, uint, 0444);
MODULE_PARM_DESC(uke_lpi_pin, "pin LPI 0..22 (defecto 13)");
static uint uke_lpi_samples;
module_param(uke_lpi_samples, uint, 0444);
MODULE_PARM_DESC(uke_lpi_samples, "0 (defecto) = leer CFG; N>0 (max 20000) = con go=1, leer N veces el registro VALUE del pin y contar unos y transiciones del bit IN (detecta si el pad conmuta: BCLK/WS/DATA)");
static bool uke_lpi_go;
module_param(uke_lpi_go, bool, 0444);
MODULE_PARM_DESC(uke_lpi_go, "1 = hacer la lectura MMIO unica (defecto 0: solo resume/votos)");

static int __init uke_lpi_rd_init(void)
{
	struct platform_device *pdev;
	struct device *dev;
	struct resource *res;
	void __iomem *p;
	phys_addr_t pa;
	int ret;
	u32 val;

	if (uke_lpi_pin >= UKE_LPI_NPINS)
		return -EINVAL;
	dev = bus_find_device_by_name(&platform_bus_type, NULL, UKE_LPI_NAME);
	if (!dev) {
		pr_err("uke_lpi_rd: no existe %s (E3a: insmod uke_audio_e3 + modprobe pinctrl-sm8650-lpass-lpi)\n", UKE_LPI_NAME);
		return -ENODEV;
	}
	if (!dev->driver) {
		pr_err("uke_lpi_rd: %s sin driver ligado; no se lee\n", UKE_LPI_NAME);
		put_device(dev);
		return -ENODEV;
	}
	pdev = to_platform_device(dev);
	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (!res || resource_size(res) < (resource_size_t)UKE_LPI_STRIDE * UKE_LPI_NPINS) {
		pr_err("uke_lpi_rd: recurso MMIO inesperado; no se lee\n");
		put_device(dev);
		return -EINVAL;
	}
	pa = res->start + (phys_addr_t)UKE_LPI_STRIDE * uke_lpi_pin;

	ret = pm_runtime_resume_and_get(dev);
	if (ret < 0) {
		pr_err("uke_lpi_rd: resume/votos PRM fallaron: %d; no se lee\n", ret);
		put_device(dev);
		return ret;
	}
	if (!pm_runtime_active(dev)) {
		pr_err("uke_lpi_rd: el dispositivo no esta activo tras el resume; no se lee\n");
		ret = -EIO;
		goto out;
	}
	pr_info("uke_lpi_rd: votos PRM activos (runtime active); pin %u, CFG en 0x%llx; go=%d\n", uke_lpi_pin, (unsigned long long)pa, uke_lpi_go);
	if (!uke_lpi_go) {
		ret = 0;
		goto out;
	}
	if (uke_lpi_samples) {
		/* SOLO LECTURA de VALUE (offset 0x04): cuenta unos y transiciones del bit IN en N lecturas seguidas; un pad que conmuta a MHz da ~50 % de unos y muchas transiciones */
		u32 n = min(uke_lpi_samples, 20000U), i, ones = 0, trans = 0, prev = 2, b;

		p = ioremap(pa + 4, 4);
		if (!p) {
			ret = -ENOMEM;
			goto out;
		}
		for (i = 0; i < n; i++) {
			b = ioread32(p) & 1;
			ones += b;
			if (prev != 2 && b != prev)
				trans++;
			prev = b;
		}
		iounmap(p);
		pr_info("uke_lpi_rd: VALUE(gpio%u): n=%u unos=%u transiciones=%u\n", uke_lpi_pin, n, ones, trans);
		ret = 0;
		goto out;
	}
	p = ioremap(pa, 4);
	if (!p) {
		ret = -ENOMEM;
		goto out;
	}
	val = ioread32(p);
	iounmap(p);
	pr_info("uke_lpi_rd: CFG(gpio%u) = 0x%08x\n", uke_lpi_pin, val);
	ret = 0;
out:
	pm_runtime_put_autosuspend(dev);
	put_device(dev);
	return ret;
}

static void __exit uke_lpi_rd_exit(void)
{
}

module_init(uke_lpi_rd_init);
module_exit(uke_lpi_rd_exit);
MODULE_DESCRIPTION("uke E3c: una lectura de un registro CFG del TLMM LPI con los votos PRM activos");
MODULE_LICENSE("GPL");
