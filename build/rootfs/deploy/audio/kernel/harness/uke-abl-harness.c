// SPDX-License-Identifier: GPL-2.0-only
/*
 * uke-abl-harness.c — arnes de PC para ejecutar `uke_abl_transform()` (el de arch/arm64/kernel/uke-abl.c, en su
 * modo de espacio de usuario: sin __KERNEL__ el fichero es compilable con libfdt) sobre un DTB capturado.
 * NO forma parte del kernel ni se aplica a la tablet. E0, 18-oct-2026.
 *
 *   gcc -O1 -Wall -DUKE_ABL_C='"/ruta/uke-abl.c"' -I<dir con uke-abl-overlays.h> uke-abl-harness.c -lfdt -o harness
 *   ./harness ENTRADA.dtb SALIDA.dtb        # imprime el codigo de retorno de uke_abl_transform (1 = aceptado, <0 = rechazo)
 *
 * Solo ejecuta uke_abl_transform (comprobaciones + overlays UFS/USB + recortes). El paso posterior del kernel
 * (uke_abl_native: display nativo) no esta aqui; para el resultado completo existe res-live-final.dtb.
 */
#include <stdio.h>
#include <stdlib.h>
#define __initdata
#define __aligned(x) __attribute__((aligned(x)))
#include UKE_ABL_C
#include "uke-abl-overlays.h"

int main(int argc, char **argv)
{
	static unsigned char out[UKE_FDT_CAPACITY] __attribute__((aligned(8)));
	static unsigned char in[UKE_FDT_CAPACITY] __attribute__((aligned(8)));
	size_t n;
	int ret;
	FILE *f;

	if (argc != 3) {
		fprintf(stderr, "uso: %s ENTRADA.dtb SALIDA.dtb\n", argv[0]);
		return 2;
	}
	f = fopen(argv[1], "rb");
	if (!f) {
		perror(argv[1]);
		return 2;
	}
	n = fread(in, 1, sizeof(in), f);
	fclose(f);
	ret = uke_abl_transform(out, sizeof(out), in, n, uke_ufs_overlay, sizeof(uke_ufs_overlay),
				uke_usb_overlay, sizeof(uke_usb_overlay));
	printf("uke_abl_transform = %d%s\n", ret,
	       ret == 1 ? " (aceptado)" : ret == 0 ? " (foreign: DT intacto)" : " (RECHAZADO)");
	if (ret > 0) {
		f = fopen(argv[2], "wb");
		if (!f) {
			perror(argv[2]);
			return 2;
		}
		fwrite(out, 1, fdt_totalsize(out), f);
		fclose(f);
	}
	return ret > 0 ? 0 : 1;
}
