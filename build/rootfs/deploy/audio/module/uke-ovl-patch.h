/* SPDX-License-Identifier: GPL-2.0 */
/*
 * uke-ovl-patch.h -- parte PURA del cargador de overlays (sin dependencias del nucleo salvo u8/size_t/memcmp).
 * La incluye module/uke-ovl.h y tambien harness/test-patch.c, que la prueba en el PC con ASan/UBSan.
 *
 * Direccion BD: el .dtbo lleva `local-bd-address = [55 4b 45 42 54 21]` ("UKEBT!"), un MARCADOR. El cargador lo
 * sustituye, en una copia en memoria, por la direccion pedida (o por ceros, que el nucleo ignora). Nada de esto
 * hace que una direccion real viaje en el repo ni en el .ko.
 */
#ifndef UKE_OVL_PATCH_H
#define UKE_OVL_PATCH_H

#define UKE_OVL_BD_LEN 6

static const u8 uke_ovl_bd_mark[UKE_OVL_BD_LEN] = { 0x55, 0x4b, 0x45, 0x42, 0x54, 0x21 };	/* "UKEBT!" */

static inline int uke_ovl_hex(char c)
{
	if (c >= '0' && c <= '9')
		return c - '0';
	if (c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	if (c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	return -1;
}

/*
 * "AA:BB:CC:DD:EE:FF" -> out[] en el orden de la propiedad (LSB primero: out[0]=FF ... out[5]=AA).
 * 0 si vale; -1 si: NULL, longitud != 17, separador != ':', digito no hexadecimal, direccion nula, o multicast
 * (bit 0 del primer byte impreso: un controlador no puede tener una direccion de grupo).
 */
static inline int uke_ovl_parse_bdaddr(const char *s, u8 out[UKE_OVL_BD_LEN])
{
	u8 b[UKE_OVL_BD_LEN];
	int i, hi, lo, any = 0;

	if (!s)
		return -1;
	for (i = 0; i < 17; i++)
		if (!s[i])
			return -1;
	if (s[17])
		return -1;
	for (i = 0; i < UKE_OVL_BD_LEN; i++) {
		hi = uke_ovl_hex(s[3 * i]);
		lo = uke_ovl_hex(s[3 * i + 1]);
		if (hi < 0 || lo < 0 || (i < 5 && s[3 * i + 2] != ':'))
			return -1;
		b[i] = (u8)(hi << 4 | lo);
		any |= b[i];
	}
	if (!any || (b[0] & 1))
		return -1;
	for (i = 0; i < UKE_OVL_BD_LEN; i++)
		out[i] = b[UKE_OVL_BD_LEN - 1 - i];
	return 0;
}

static inline size_t uke_ovl_count_mark(const u8 *blob, size_t len)
{
	size_t i, n = 0;

	for (i = 0; i + UKE_OVL_BD_LEN <= len; i++)
		if (!memcmp(blob + i, uke_ovl_bd_mark, UKE_OVL_BD_LEN))
			n++;
	return n;
}

/* Sustituye el UNICO marcador por bd[]. 0 si habia exactamente uno; -1 si habia 0 o varios (no toca nada). */
static inline int uke_ovl_patch_bdaddr(u8 *blob, size_t len, const u8 bd[UKE_OVL_BD_LEN])
{
	size_t i;

	if (uke_ovl_count_mark(blob, len) != 1)
		return -1;
	for (i = 0; i + UKE_OVL_BD_LEN <= len; i++) {
		if (!memcmp(blob + i, uke_ovl_bd_mark, UKE_OVL_BD_LEN)) {
			memcpy(blob + i, bd, UKE_OVL_BD_LEN);
			return 0;
		}
	}
	return -1;
}

#endif /* UKE_OVL_PATCH_H */
