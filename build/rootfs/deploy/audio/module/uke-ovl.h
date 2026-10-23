/* SPDX-License-Identifier: GPL-2.0 */
/*
 * uke-ovl.h -- cargador GENERICO de UN overlay de DT embebido (Xiaomi Pad 7 "uke", senemos ouke3).
 *
 * El kernel ouke3 tiene OF_OVERLAY=y pero no OF_CONFIGFS, asi que no hay otra forma de aplicar un overlay en
 * caliente que llamar a of_overlay_fdt_apply() desde un modulo. insmod/modprobe = aplicar; rmmod = retirar.
 *
 * Cada modulo (uke_bt_*.c, 5 lineas) define antes de incluir este fichero:
 *   UKE_OVL_NAME    "uke_bt_b"      nombre para los logs
 *   UKE_OVL_DESC    "..."           MODULE_DESCRIPTION
 *   UKE_OVL_BDADDR  (opcional)      el .dtbo lleva el marcador local-bd-address y el modulo admite `bdaddr=`
 * y Kbuild pasa -DUKE_OVL_BLOB=\"/ruta/absoluta/al.dtbo\" (el .dtbo se embebe con .incbin en la seccion .uke_ovl).
 *
 * of_overlay_fdt_apply() COPIA el FDT, asi que nada del arbol vivo apunta a la memoria del modulo: si el
 * of_overlay_remove() de rmmod fallase, el overlay queda aplicado (fuga de unos KB) pero no hay puntero colgante.
 */
#ifndef UKE_OVL_NAME
#error "define UKE_OVL_NAME antes de incluir uke-ovl.h"
#endif
#ifndef UKE_OVL_BLOB
#error "Kbuild debe pasar -DUKE_OVL_BLOB=\"/ruta/al.dtbo\""
#endif

#define pr_fmt(fmt) UKE_OVL_NAME ": " fmt

#include <linux/module.h>
#include <linux/of.h>
#include <linux/slab.h>
#include <linux/string.h>
#include "uke-ovl-patch.h"

asm(".pushsection .uke_ovl, \"a\"\n"
	".balign 8\n"
	"uke_ovl_blob:\n"
	".incbin \"" UKE_OVL_BLOB "\"\n"
	"uke_ovl_blob_end:\n"
	".popsection\n");
extern const u8 uke_ovl_blob[], uke_ovl_blob_end[];

static int uke_ovl_id;

#ifdef UKE_OVL_BDADDR
static char *bdaddr;
module_param(bdaddr, charp, 0400);
MODULE_PARM_DESC(bdaddr, "direccion BD 'AA:BB:CC:DD:EE:FF' (unicast, no nula); sin ella local-bd-address queda a ceros y el controlador sin configurar");
#endif

static int __init uke_ovl_init(void)
{
	const size_t len = uke_ovl_blob_end - uke_ovl_blob;
	u8 *buf;
	int ret = 0;

#ifdef UKE_OVL_REFUSE_IF_PATH
	/* Overlays de TARJETA (nodo /sound, modelo UKE): fdtoverlay/of_overlay FUSIONAN nodos del mismo nombre; si ya existe /sound (otra tarjeta cargada) el
	 * overlay se aplicaria sobre el nodo vivo, la tarjeta no se volveria a sondear y quedaria «aplicado pero inerte» sin error. Se rechaza: reiniciar para cambiar de tarjeta. */
	{
		struct device_node *exist = of_find_node_by_path(UKE_OVL_REFUSE_IF_PATH);

		if (exist) {
			of_node_put(exist);
			pr_err("ya existe %s en el DT vivo (otra tarjeta UKE cargada): no aplico este overlay; reinicia para cambiar de tarjeta\n", UKE_OVL_REFUSE_IF_PATH);
			return -EEXIST;
		}
	}
#endif

	buf = kmemdup(uke_ovl_blob, len, GFP_KERNEL);
	if (!buf)
		return -ENOMEM;

#ifdef UKE_OVL_BDADDR
	{
		u8 bd[UKE_OVL_BD_LEN] = { };
		bool have = bdaddr && *bdaddr;

		if (have && uke_ovl_parse_bdaddr(bdaddr, bd)) {
			pr_err("bdaddr invalida (AA:BB:CC:DD:EE:FF, unicast, no nula)\n");
			ret = -EINVAL;
			goto out;
		}
		if (uke_ovl_patch_bdaddr(buf, len, bd)) {
			pr_err("el overlay no lleva exactamente un marcador local-bd-address\n");
			ret = -EINVAL;
			goto out;
		}
		pr_info("local-bd-address %s\n", have ? "fijada por el parametro bdaddr" : "a ceros (el nucleo la ignora)");
	}
#else
	if (uke_ovl_count_mark(buf, len)) {	/* un marcador sin sustituir NO debe llegar al nucleo */
		pr_err("el overlay lleva un marcador local-bd-address y este modulo no lo sustituye\n");
		ret = -EINVAL;
		goto out;
	}
#endif

	ret = of_overlay_fdt_apply(buf, len, &uke_ovl_id, NULL);
	if (ret) {
		pr_err("of_overlay_fdt_apply: %d (id %d)\n", ret, uke_ovl_id);
		/* Con error el changeset puede haber quedado a medias: la doc de of_overlay_fdt_apply() pide retirarlo. */
		if (uke_ovl_id && of_overlay_remove(&uke_ovl_id))
			pr_err("no pude retirar el overlay a medias: arbol en estado dudoso\n");
		goto out;
	}
	pr_info("overlay aplicado (id %d, %zu B)\n", uke_ovl_id, len);
out:
	kfree(buf);
	return ret;
}

static void __exit uke_ovl_exit(void)
{
	int ret = of_overlay_remove(&uke_ovl_id);

	if (ret)
		pr_err("of_overlay_remove: %d; el overlay SIGUE aplicado (el modulo se descarga igual)\n", ret);
	else
		pr_info("overlay retirado\n");
}

module_init(uke_ovl_init);
module_exit(uke_ovl_exit);
MODULE_DESCRIPTION(UKE_OVL_DESC);
MODULE_AUTHOR("omarchy-uke");
MODULE_LICENSE("GPL");
