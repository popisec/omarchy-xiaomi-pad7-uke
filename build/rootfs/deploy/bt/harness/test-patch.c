// SPDX-License-Identifier: GPL-2.0
/*
 * test-patch.c -- prueba EN EL PC (userspace) de module/uke-ovl-patch.h: parseo de la direccion BD y sustitucion
 * del marcador. Con --blob IN OUT parchea ademas un .dtbo real y escribe el resultado para que build.sh lo pase
 * por fdtoverlay/fdtget.
 *   test-patch                          pruebas unitarias
 *   test-patch --blob IN.dtbo OUT.dtbo ADDR   parchea IN con ADDR (AA:BB:..) y escribe OUT; sale 0 si hubo 1 marcador
 *   test-patch --count IN.dtbo          imprime cuantos marcadores lleva
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef uint8_t u8;
#include "../module/uke-ovl-patch.h"

static int fails, tests;
#define CHECK(c) do { tests++; if (!(c)) { fails++; printf("  FALLO l.%d: %s\n", __LINE__, #c); } } while (0)

static void t_parse(void)
{
	u8 o[6];
	static const u8 want[6] = { 0x55, 0x44, 0x33, 0x22, 0x11, 0x02 };
	const char *bad[] = { "", "02:11:22:33:44", "02:11:22:33:44:5", "02:11:22:33:44:55:", "02:11:22:33:44:555",
		"02-11-22-33-44-55", "02:11:22:33:44:5g", "0g:11:22:33:44:55", " 2:11:22:33:44:55", "2:11:22:33:44:55:66",
		"00:00:00:00:00:00", "02:00:5e:00:00:11", "02:00:5e:00:00:12", "02:00:5e:00:00:xx", "02:11:22:33:44:55\n" };
	size_t i;

	CHECK(uke_ovl_parse_bdaddr("02:11:22:33:44:55", o) == 0 && !memcmp(o, want, 6));
	CHECK(uke_ovl_parse_bdaddr("02:00:5e:00:00:13", o) == 0 && o[0] == 0xb5 && o[1] == 0x0a && o[2] == 0xef &&
	      o[3] == 0xcd && o[4] == 0xab && o[5] == 0x02);
	CHECK(uke_ovl_parse_bdaddr("02:00:5e:00:00:14", o) == 0 && o[0] == 1 && !o[5]);	/* nula solo si TODO es 0 */
	CHECK(uke_ovl_parse_bdaddr("02:00:5E:00:00:15", o) == 0);	/* unicast aunque sea de administracion local */
	CHECK(uke_ovl_parse_bdaddr(NULL, o) == -1);
	for (i = 0; i < sizeof(bad) / sizeof(bad[0]); i++) {
		u8 keep[6] = { 9, 9, 9, 9, 9, 9 };
		memcpy(o, keep, 6);
		CHECK(uke_ovl_parse_bdaddr(bad[i], o) == -1);
		CHECK(!memcmp(o, keep, 6));	/* en error no toca la salida */
	}
}

static void t_patch(void)
{
	u8 b[64], ref[64];
	const u8 bd[6] = { 0xb5, 0x0a, 0xef, 0xcd, 0xab, 0x02 };
	size_t off, i;

	/* un marcador en cada posicion posible, incl. los dos extremos */
	for (off = 0; off + 6 <= sizeof(b); off++) {
		for (i = 0; i < sizeof(b); i++)
			b[i] = (u8)(i * 7 + 3);
		memcpy(b + off, uke_ovl_bd_mark, 6);
		memcpy(ref, b, sizeof(b));
		CHECK(uke_ovl_count_mark(b, sizeof(b)) == 1);
		CHECK(uke_ovl_patch_bdaddr(b, sizeof(b), bd) == 0);
		memcpy(ref + off, bd, 6);
		CHECK(!memcmp(b, ref, sizeof(b)));
		CHECK(uke_ovl_count_mark(b, sizeof(b)) == 0);
	}
	/* sin marcador / con dos: -1 y el buffer no cambia */
	memset(b, 0x11, sizeof(b));
	memcpy(ref, b, sizeof(b));
	CHECK(uke_ovl_patch_bdaddr(b, sizeof(b), bd) == -1 && !memcmp(b, ref, sizeof(b)));
	memcpy(b + 3, uke_ovl_bd_mark, 6);
	memcpy(b + 40, uke_ovl_bd_mark, 6);
	memcpy(ref, b, sizeof(b));
	CHECK(uke_ovl_count_mark(b, sizeof(b)) == 2);
	CHECK(uke_ovl_patch_bdaddr(b, sizeof(b), bd) == -1 && !memcmp(b, ref, sizeof(b)));
	/* tamanios degenerados */
	CHECK(uke_ovl_patch_bdaddr(b, 0, bd) == -1);
	CHECK(uke_ovl_patch_bdaddr(b, 5, bd) == -1);
	CHECK(uke_ovl_count_mark(b, 5) == 0);
	/* el marcador no se parece a ninguna direccion valida: primer byte impreso = ultimo byte de la propiedad (0x21, impar) */
	{ u8 o[6]; CHECK(uke_ovl_parse_bdaddr("02:00:5E:00:00:16", o) == -1); }
}

static u8 *slurp(const char *p, size_t *n)
{
	FILE *f = fopen(p, "rb");
	u8 *b;
	long sz;

	if (!f) { perror(p); exit(2); }
	fseek(f, 0, SEEK_END); sz = ftell(f); fseek(f, 0, SEEK_SET);
	b = malloc(sz ? sz : 1);
	if (!b || fread(b, 1, sz, f) != (size_t)sz) { perror("read"); exit(2); }
	fclose(f);
	*n = sz;
	return b;
}

int main(int argc, char **argv)
{
	if (argc == 3 && !strcmp(argv[1], "--count")) {
		size_t n; u8 *b = slurp(argv[2], &n);
		printf("%zu\n", uke_ovl_count_mark(b, n));
		free(b);
		return 0;
	}
	if (argc == 5 && !strcmp(argv[1], "--blob")) {
		size_t n; u8 *b = slurp(argv[2], &n); u8 bd[6]; FILE *f;
		if (uke_ovl_parse_bdaddr(argv[4], bd)) { fprintf(stderr, "direccion invalida\n"); free(b); return 1; }
		if (uke_ovl_patch_bdaddr(b, n, bd)) { fprintf(stderr, "no hay exactamente un marcador\n"); free(b); return 1; }
		f = fopen(argv[3], "wb");
		if (!f || fwrite(b, 1, n, f) != n) { perror(argv[3]); free(b); return 2; }
		fclose(f);
		free(b);
		return 0;
	}
	t_parse();
	t_patch();
	printf("test-patch: %d comprobaciones, %d fallos\n", tests, fails);
	return fails ? 1 : 0;
}
