// SPDX-License-Identifier: GPL-2.0
/*
 * uke_fs19xx.c — driver minimo de los 4 amplificadores FourSemi FS19xx ("foursemi,fs16xx") de la Xiaomi Pad 7 «uke».
 * BORRADOR DEL PC (18-oct-2026): compila contra el arbol ouke4; NO probado en la tablet.
 *
 * Escrito DESDE EL COMPORTAMIENTO medido en el driver vendor fs19xx_dlkm.ko v4.0.7 (decompilado Ghidra, informe
 * RE-AUDIO-WCD939X-FS19XX-ADD2-FSM-DRIVER.md y artifacts/audio/decomp-fs19xx/); no se copia codigo del vendor.
 * El preset `fs19xx.fsm` (4828 B, escenas/registros de cada esquina) se CARGA EN EJECUCION con request_firmware y se valida
 * (tamanio + CRC-16/MODBUS + limites); NO se hornea en el modulo ni en el repo (no se redistribuye).
 *
 * Diseno "falla cerrado" por etapas (parametros del modulo, por defecto lo mas inofensivo):
 *   etapa 0  probe I2C: pulso de reset (uke_fs_reset=1) + lectura de DEVID (reg 0x03) + validacion del preset. NINGUNA otra escritura.
 *   etapa 1  uke_fs_play=1: al desenmudecer el PCM (mute_stream) se inicializa cada amp (reg_init + tablas comunes y de escena),
 *            se programa I2S/PLL y se habilita; al enmudecer/cerrar, shut_down. Volumen limitado por uke_fs_volmax.
 *   El DAI lo registra un dispositivo de plataforma "uke,fs19xx-codec" (lo crea el overlay e8) que actua sobre los 4 amps.
 *
 * Direcciones I2C: 0x34..0x37 (bus i2c@88c000 = i2c4). Registros de 8 bit con valores de 16 bit BIG-ENDIAN.
 */
#include <linux/module.h>
#include <linux/i2c.h>
#include <linux/regmap.h>
#include <linux/gpio/consumer.h>
#include <linux/delay.h>
#include <linux/firmware.h>
#include <linux/mutex.h>
#include <linux/platform_device.h>
#include <sound/soc.h>
#include <sound/pcm_params.h>
#include <linux/debugfs.h>
#include <linux/uaccess.h>
#include <linux/seq_file.h>

#define FS_FW_NAME		"fs19xx.fsm"
#define FS_NAMPS		4
#define FS_ADDR0		0x34

#define FS_REG_DEVID		0x03
#define FS_REG_VOL_OLD		0x06	/* variante antigua: vol<<8 (no la usan 0x17xx/0x29xx) */
#define FS_REG_KEY		0x0b	/* "access key": 0xCA91 abre los registros del PLL, 0 cierra */
#define FS_REG_STATUS		0x0e
#define FS_REG_PWR		0x10	/* 2/1: danza de reset; 0: marcha; 1: parado */
#define FS_REG_EN		0x11	/* 0xEF habilita, 0 deshabilita */
#define FS_REG_VOL		0x16	/* (vol<<8)|0xC0 (|0x80 si devid>>8 == 0x17) */
#define FS_REG_I2S		0x17	/* bits 15:12 = codigo de frecuencia, bit 11 = actualizar */
#define FS_REG_RE25		0x14
#define FS_REG_STATE		0x30	/* 0x210 arranque, 0x310 parada */
#define FS_REG_CH		0x4c	/* bit 3 segun escena (ver fs_start_up) */
#define FS_REG_PLL1		0xa1

/* TOPE DURO DE COMPILACION del registro de volumen (0xF3 = 243, el valor fijo de Android): ningun parametro, mando ni escritura en sysfs puede superarlo */
#define FS_VOL_HARD 243U
static bool uke_fs_play;
module_param(uke_fs_play, bool, 0644);
MODULE_PARM_DESC(uke_fs_play, "1 = al reproducir se inicializan y habilitan los amps (defecto 0: solo probe/ID, sin escrituras)");
static bool uke_fs_reset = true;
module_param(uke_fs_reset, bool, 0444);
MODULE_PARM_DESC(uke_fs_reset, "pulso de reset (bajo 10 ms, alto 1 ms) antes de leer el DEVID (defecto 1; con 0 solo funciona si el bootloader dejo los amps fuera de reset)");
static uint uke_fs_volmax = 0x80;
/* module_param_cb mas abajo (recorta al tope duro y reaplica en caliente) */
MODULE_PARM_DESC(uke_fs_volmax, "tope del registro de volumen 0..255 (INFERIDO: mayor = mas fuerte; 255 sin atenuacion; Android usa 235..243). Defecto 0x80");
static uint uke_fs_vol = 0x40;
MODULE_PARM_DESC(uke_fs_vol, "volumen inicial 0..255, recortado a uke_fs_volmax (defecto 0x40)");
static uint uke_fs_scene;
module_param(uke_fs_scene, uint, 0644);
MODULE_PARM_DESC(uke_fs_scene, "escena inicial 0..14 (0 = altavoces estereo; 7/9/11/13 = una esquina TL/TR/BL/BR; INFERIDO)");
static uint uke_fs_bclk_ratio = 128;
module_param(uke_fs_bclk_ratio, uint, 0444);
MODULE_PARM_DESC(uke_fs_bclk_ratio, "BCLK/FS: 4 slots x 32 bit = 128 (TDM_INTF_CFG del ACDB)");
static uint uke_fs_min_amps = 1;
module_param(uke_fs_min_amps, uint, 0444);
MODULE_PARM_DESC(uke_fs_min_amps, "amps con probe correcto necesarios para registrar el DAI (defecto 1; 4 = todos)");

struct fs19xx_amp {
	struct i2c_client *client;
	struct regmap *map;
	struct gpio_desc *rst;
	u8 *blob;			/* copia validada del preset */
	size_t blob_len;
	const u8 *common;		/* entradas comunes (4 B: desc,val) */
	u16 ncommon;
	const u8 *scene;		/* entradas de escena (6 B: mask,desc,val) */
	u16 nscene;
	u16 info[17];
	u16 devid;
	u16 cur_mask;			/* mascara de escena escrita (1<<escena) */
	bool inited;
	bool on;
};

static DEFINE_MUTEX(fs_lock);
static struct fs19xx_amp *fs_amps[FS_NAMPS];
static uint fs_vol;			/* volumen vigente (recortado) */
static uint fs_scene;
static uint fs_rate, fs_bclk;
static bool fs_streaming;

/* Tabla PLL del vendor (g_fs19xx_pll_tbl, 12 B por entrada). CORREGIDA el 19-oct-2026 con la traza I2C de Android (tracefs, bus 4, reproduciendo): a 6,144 MHz el driver
 * vendor escribe A1=0x0260, A2=0x0540, A3=0x0018, es decir las palabras [2],[3],[4] de la entrada (no [0],[1],[2] como se leyo del decompilado: 0xC000/0x005D/0x0260, que
 * dejaban el PLL del amp mal configurado). Las demas filas se derivan con el mismo desplazamiento (SOLO la fila 6,144 MHz esta verificada contra Android). */
static const struct { u32 bclk; u16 a1, a2, a3; } fs_pll[] = {
	{ 256000,   0x0260, 0x0540, 0x0001 },
	{ 512000,   0x0260, 0x0540, 0x0002 },
	{ 1024000,  0x0260, 0x0540, 0x0004 },
	{ 1024032,  0x0160, 0x0380, 0x0004 },
	{ 1411200,  0x0260, 0x0460, 0x0005 },
	{ 1536000,  0x0260, 0x0540, 0x0006 },
	{ 2048000,  0x0160, 0x0380, 0x0008 },
	{ 2822400,  0x0260, 0x0460, 0x000A },
	{ 3072000,  0x0260, 0x0540, 0x000C },
	{ 6144000,  0x0260, 0x0540, 0x0018 },
	{ 12288000, 0x0260, 0x02A0, 0x0018 },
};

static const struct { u32 rate; u8 code; } fs_rates[] = {
	{ 8000, 1 }, { 16000, 3 }, { 32000, 7 }, { 44100, 8 }, { 48000, 9 },
	{ 88200, 10 }, { 96000, 11 }, { 176400, 12 }, { 192000, 13 },
};

static inline u16 le16(const u8 *p) { return p[0] | (p[1] << 8); }

/* ---- acceso a registros (8 bit / 16 bit BE) con los 5 intentos de 5 ms del vendor ---- */
static int fs_rd(struct fs19xx_amp *a, unsigned int reg, unsigned int *v)
{
	int i, ret = -EIO;

	for (i = 0; i < 5; i++) {
		ret = regmap_read(a->map, reg, v);
		if (!ret)
			return 0;
		msleep(5);
	}
	dev_err(&a->client->dev, "lectura reg 0x%02x fallo: %d\n", reg, ret);
	return ret;
}

static int fs_wr(struct fs19xx_amp *a, unsigned int reg, unsigned int v)
{
	int i, ret = -EIO;

	for (i = 0; i < 5; i++) {
		ret = regmap_write(a->map, reg, v & 0xffff);
		if (!ret)
			return 0;
		msleep(5);
	}
	dev_err(&a->client->dev, "escritura reg 0x%02x=0x%04x fallo: %d\n", reg, v & 0xffff, ret);
	return ret;
}

/* Descriptor de registro del preset: bits15:12 = ancho-1, bits11:8 = desplazamiento, bits7:0 = direccion.
 * Solo se admiten las dos formas que usa el blob real: escritura completa 0xF0xx y lectura-modificacion-escritura. */
static bool fs_desc_ok(u16 d)
{
	if (d >= 0x1000 && (d & 0xf00) == 0xf00)
		return false;			/* "fsm_reg_case" del vendor (retardos/sondeos): no soportado */
	if (d >= 0xf000 && (d & 0xf00) == 0)
		return true;			/* escritura completa de 16 bit */
	return ((d >> 12) + 1) + ((d >> 8) & 0xf) <= 16;
}

static int fs_apply(struct fs19xx_amp *a, u16 d, u16 val)
{
	unsigned int old, m, sh, v;
	int ret;

	if (d >= 0xf000 && (d & 0xf00) == 0)
		return fs_wr(a, d & 0xff, val);
	sh = (d >> 8) & 0xf;
	m = (~(~0U << ((d >> 12) + 1)) << sh) & 0xffff;
	ret = fs_rd(a, d & 0xff, &old);
	if (ret)
		return ret;
	v = (old & ~m) | ((val << sh) & m);
	return fs_wr(a, d & 0xff, v);
}

static int fs_write_common(struct fs19xx_amp *a)
{
	int i, ret, err = 0;

	for (i = 0; i < a->ncommon; i++) {
		ret = fs_apply(a, le16(a->common + 4 * i), le16(a->common + 4 * i + 2));
		err |= ret;
	}
	return err;
}

static int fs_write_scene(struct fs19xx_amp *a, u16 mask)
{
	int i, ret, err = 0;

	for (i = 0; i < a->nscene; i++) {
		const u8 *e = a->scene + 6 * i;

		if (!(le16(e) & mask))
			continue;
		ret = fs_apply(a, le16(e + 2), le16(e + 4));
		err |= ret;
	}
	if (!err)
		a->cur_mask = mask;
	else
		a->inited = false;
	return err;
}

/* ---- preset .fsm: cabecera + CRC-16/MODBUS + trozo del amp ---- */
static u16 fs_crc16(const u8 *p, size_t n)
{
	u16 crc = 0;
	int b;

	while (n--) {
		crc ^= *p++;
		for (b = 0; b < 8; b++)
			crc = (crc & 1) ? (crc >> 1) ^ 0xA001 : crc >> 1;
	}
	return crc;
}

static int fs_parse(struct fs19xx_amp *a, const struct firmware *fw)
{
	struct device *dev = &a->client->dev;
	const u8 *d = fw->data;
	size_t len = fw->size;
	u16 ndev, nsec, k, i;
	size_t s = 0;
	bool found = false;

	if (len < 0x40 || le16(d + 0x16) != len) {
		dev_err(dev, "preset: tamanio incoherente (%zu vs %u)\n", len, len >= 0x18 ? le16(d + 0x16) : 0);
		return -EINVAL;
	}
	if (fs_crc16(d + 0x1a, len - 0x1a) != le16(d + 0x18)) {
		dev_err(dev, "preset: CRC no coincide (0x%04x != 0x%04x)\n", fs_crc16(d + 0x1a, len - 0x1a), le16(d + 0x18));
		return -EINVAL;
	}
	ndev = le16(d + 0x1a);
	if (!ndev || ndev > 8 || 0x1c + 4 * (size_t)ndev > len)
		return -EINVAL;
	for (k = 0; k < ndev; k++) {
		size_t off = le16(d + 0x1c + 4 * k);

		if (off + 0x30 > len)
			return -EINVAL;
		if (le16(d + off + 0x1e) == a->client->addr) {
			s = off;
			found = true;
			break;
		}
	}
	if (!found) {
		dev_err(dev, "preset: sin trozo para la direccion 0x%02x\n", a->client->addr);
		return -ENODEV;
	}
	nsec = le16(d + s + 0x1a);
	if (!nsec || nsec > 8 || s + 0x28 + 4 * (size_t)nsec > len)
		return -EINVAL;
	for (k = 0; k < nsec; k++) {
		u16 typ = le16(d + s + 0x2a + 4 * k);
		size_t t = s + 0x28 + le16(d + s + 0x28 + 4 * k);
		u16 n;

		if (t + 2 > len)
			return -EINVAL;
		n = le16(d + t);
		switch (typ) {
		case 1:
			if (n != 17 || t + 2 + 2 * (size_t)n > len)
				return -EINVAL;
			for (i = 0; i < n; i++)
				a->info[i] = le16(d + t + 2 + 2 * i);
			break;
		case 2:
			if (t + 2 + 4 * (size_t)n > len)
				return -EINVAL;
			for (i = 0; i < n; i++)
				if (!fs_desc_ok(le16(d + t + 2 + 4 * i)))
					return -EINVAL;
			a->common = a->blob + t + 2;
			a->ncommon = n;
			break;
		case 3:
			if (t + 2 + 6 * (size_t)n > len)
				return -EINVAL;
			for (i = 0; i < n; i++)
				if (!fs_desc_ok(le16(d + t + 4 + 6 * i)))
					return -EINVAL;
			a->scene = a->blob + t + 2;
			a->nscene = n;
			break;
		default:
			break;
		}
	}
	if (!a->common || !a->scene)
		return -EINVAL;
	return 0;
}

/* ---- secuencias (HECHO por decompilado; ADD2 §2) ---- */
static bool fs_newvar(struct fs19xx_amp *a) { return (a->devid >> 8) == 0x17 || (a->devid >> 8) == 0x29; }

static int fs_reg_init(struct fs19xx_amp *a)
{
	unsigned int v = 0;
	int i, ret;

	for (i = 0; i < 5; i++) {
		fs_wr(a, FS_REG_PWR, 2);
		fs_rd(a, FS_REG_PWR, &v);
		msleep(15);
		fs_wr(a, FS_REG_PWR, 1);
		ret = fs_rd(a, FS_REG_STATUS, &v);
		if (!ret && (v == 3 || v == 0x300))
			break;
	}
	if (i == 5) {
		dev_err(&a->client->dev, "reg_init: el estado 0x0e nunca llego a 3/0x300 (ultimo 0x%04x)\n", v);
		return -ETIMEDOUT;
	}
	ret = fs_wr(a, FS_REG_RE25, (unsigned int)a->info[1] << 1);
	ret |= fs_write_common(a);
	ret |= fs_write_scene(a, 1U << fs_scene);
	a->inited = !ret;
	return ret;
}

static int fs_set_vol(struct fs19xx_amp *a)
{
	unsigned int v = min(fs_vol, min(uke_fs_volmax, FS_VOL_HARD));

	if (!fs_newvar(a))
		return fs_wr(a, FS_REG_VOL_OLD, v << 8);
	return fs_wr(a, FS_REG_VOL, (v << 8) | ((a->devid >> 8) == 0x17 ? 0x80 : 0xc0));
}

/* uke_fs_vol / uke_fs_volmax: cualquier valor se recorta a FS_VOL_HARD y, si hay amps sonando, se reaplica el volumen (bajar el tope BAJA el volumen en curso) */
static int fs_vol_param_set(const char *val, const struct kernel_param *kp)
{
	unsigned int *p = kp->arg, v;
	int ret = kstrtouint(val, 0, &v), i;

	if (ret)
		return ret;
	if (v > FS_VOL_HARD)
		pr_warn("uke_fs19xx: %s=%u recortado al tope duro %u\n", kp->name, v, FS_VOL_HARD);
	*p = min(v, FS_VOL_HARD);
	mutex_lock(&fs_lock);
	if (fs_streaming) {
		fs_vol = min(fs_vol, min(uke_fs_volmax, FS_VOL_HARD));
		for (i = 0; i < FS_NAMPS; i++)
			if (fs_amps[i] && fs_amps[i]->on)
				fs_set_vol(fs_amps[i]);
	}
	mutex_unlock(&fs_lock);
	return 0;
}
static const struct kernel_param_ops fs_vol_param_ops = { .set = fs_vol_param_set, .get = param_get_uint };
module_param_cb(uke_fs_volmax, &fs_vol_param_ops, &uke_fs_volmax, 0644);
module_param_cb(uke_fs_vol, &fs_vol_param_ops, &uke_fs_vol, 0644);

static int fs_start_up(struct fs19xx_amp *a)
{
	unsigned int r17, r04, bits = 0, ch, newch, mask = a->cur_mask;
	int i, idx = -1, ret = 0;

	for (i = 0; i < ARRAY_SIZE(fs_rates); i++)
		if (fs_rates[i].rate == fs_rate)
			bits = fs_rates[i].code;
	for (i = 0; i < ARRAY_SIZE(fs_pll); i++)
		if (fs_pll[i].bclk == fs_bclk)
			idx = i;
	if (!bits || idx < 0) {
		dev_err(&a->client->dev, "start_up: rate %u / bclk %u sin entrada\n", fs_rate, fs_bclk);
		return -EINVAL;
	}
	ret |= fs_rd(a, FS_REG_I2S, &r17);
	ret |= fs_rd(a, 4, &r04);
	if ((r04 & 0xff) == 0xa1 && (a->devid >> 8) == 0x17)
		bits = 7;
	r17 = (r17 & ~0xf000U) | (bits << 12) | BIT(11);
	ret |= fs_wr(a, FS_REG_I2S, r17);
	/* PLL: A1/A2/A3 bajo la clave de acceso */
	ret |= fs_wr(a, FS_REG_KEY, 0xca91);
	ret |= fs_wr(a, FS_REG_PLL1, fs_pll[idx].a1);
	ret |= fs_wr(a, FS_REG_PLL1 + 1, fs_pll[idx].a2);
	ret |= fs_wr(a, FS_REG_PLL1 + 2, fs_pll[idx].a3);
	ret |= fs_wr(a, FS_REG_KEY, 0);
	ret |= fs_wr(a, FS_REG_EN, 0xef);
	/* DESVIACION DELIBERADA del vendor (que escribe el volumen DESPUES de sacar al amp de standby): la tabla de escena deja
	 * reg 0x16 al maximo (RMW mask 0xffc0 <- 0xffc0, medido con dryrun.py), asi que el volumen limitado se escribe ANTES de 0x10<-0. */
	ret |= fs_set_vol(a);
	if (ret) {
		fs_wr(a, FS_REG_EN, 0);		/* best effort: EN se habia puesto a 0xEF antes de fallar el volumen */
		return ret;
	}
	ret |= fs_wr(a, FS_REG_PWR, 0);
	a->on = true;			/* a partir de aqui cualquier fallo debe terminar en shut_down */
	ret |= fs_wr(a, FS_REG_STATE, 0x210);
	msleep(10);
	ret |= fs_rd(a, FS_REG_CH, &ch);
	/* bit 3 de 0x4C: a 0 para las escenas {4 (solo posicion 8), 6, 8, 10, 12, 14, 15}; a 1 en el resto */
	if (mask == 0x40 || mask == 0x100 || mask == 0x400 || mask == 0x1000 || mask == 0x4000 || mask == 0x8000 ||
	    (mask == 0x10 && a->info[16] == 8)) {
		ret |= fs_wr(a, FS_REG_CH, ch & ~BIT(3));
		msleep(35);
	} else {
		newch = ch | BIT(3);
		if (newch != ch)
			ret |= fs_wr(a, FS_REG_CH, newch);
	}
	return ret;
}

static int fs_shut_down(struct fs19xx_amp *a)
{
	int ret = fs_wr(a, FS_REG_STATE, 0x310);

	ret |= fs_wr(a, FS_REG_PWR, 1);
	msleep(35);
	ret |= fs_wr(a, FS_REG_EN, 0);
	if (ret)
		dev_err(&a->client->dev, "shut_down con errores I2C (%d): el amp puede seguir habilitado; se reintenta\n", ret);
	else
		a->on = false;		/* con error se deja `on` para que el siguiente mute/ctl off/remove lo reintente */
	return ret;
}

static void fs_stop_all_locked(void)
{
	int i, left = 0;

	for (i = 0; i < FS_NAMPS; i++) {
		struct fs19xx_amp *a = fs_amps[i];

		if (!a || !a->on)
			continue;
		if (fs_shut_down(a)) {
			msleep(10);
			fs_shut_down(a);
		}
		left += a->on;
	}
	fs_streaming = !!left;		/* si alguno sigue habilitado se sigue considerando activo para reintentar */
	if (left)
		pr_err("uke_fs19xx: %d amp(s) siguen habilitados tras la parada\n", left);
}

static int fs_start_all_locked(void)
{
	int i, ret = 0;
	u16 mask = 1U << fs_scene;

	for (i = 0; i < FS_NAMPS; i++) {
		struct fs19xx_amp *a = fs_amps[i];

		if (!a)
			continue;
		/* try_init del vendor (MEDIDO en la traza I2C de Android: lee reg 0x14 de cada amp y solo reinicializa si no vale re25<<1): con el amp ya
		 * configurado (0x14 == info[1]<<1) NO se repite reg_init ni la tabla comun */
		{
			unsigned int r14 = 0;

			if (!fs_rd(a, FS_REG_RE25, &r14) && r14 == ((unsigned int)a->info[1] << 1) && a->inited)
				ret = 0;
			else
				ret = fs_reg_init(a);
		}
		if (!ret && a->cur_mask != mask)
			ret = fs_write_scene(a, mask);
		if (ret) {
			dev_err(&a->client->dev, "init fallo (%d): no se habilita ningun amp\n", ret);
			goto fail;
		}
	}
	for (i = 0; i < FS_NAMPS; i++) {
		if (!fs_amps[i])
			continue;
		ret = fs_start_up(fs_amps[i]);
		if (ret)
			goto fail;
	}
	fs_streaming = true;
	return 0;
fail:
	fs_stop_all_locked();
	return ret;
}


/* ---- diagnostico de SOLO LECTURA: /sys/kernel/debug/uke_fs19xx/regs (E8 diag) ----
 * Lee con I2C (lectura) los registros de estado/configuracion que el vendor vuelca en fsm_reg_dump (sin la clave 0xCA91 ni escrituras):
 * 0x00-0x1f completos y un puñado de los usados por reg_init/start_up. No escribe NADA (fs_rd). Puede leerse con los amps en marcha. */
static const u8 fs_dump_regs[] = {
	0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
	0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f,
	0x20, 0x21, 0x22, 0x24, 0x29, 0x30, 0x39, 0x3a, 0x3c, 0x41, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x5f,
};

static int fs_regs_show(struct seq_file *m, void *unused)
{
	int i, k, n;

	mutex_lock(&fs_lock);
	for (i = 0; i < FS_NAMPS; i++) {
		struct fs19xx_amp *a = fs_amps[i];

		if (!a)
			continue;
		seq_printf(m, "amp 0x%02x devid=0x%04x on=%d inited=%d mask=0x%04x pos=%u\n", a->client->addr, a->devid, a->on, a->inited, a->cur_mask, a->info[16]);
		for (k = n = 0; k < ARRAY_SIZE(fs_dump_regs); k++) {
			unsigned int v;

			if (fs_rd(a, fs_dump_regs[k], &v))
				seq_printf(m, "%02x:---- ", fs_dump_regs[k]);
			else
				seq_printf(m, "%02x:%04x ", fs_dump_regs[k], v);
			if (++n % 8 == 0)
				seq_putc(m, '\n');
		}
		seq_putc(m, '\n');
	}
	mutex_unlock(&fs_lock);
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(fs_regs);
static struct dentry *fs_dbg;

/* ---- /sys/kernel/debug/uke_fs19xx/ctl (E8 diag 3): "on"/"off" arrancan/paran los amps SIN PCM (para comparar sus registros con y sin BCLK).
 * Doble candado: exige uke_fs_play=Y. "on" usa 48 kHz / BCLK 6,144 MHz y el volumen/escena de los parametros (recortados). */
static ssize_t fs_ctl_write(struct file *f, const char __user *ubuf, size_t len, loff_t *off)
{
	char buf[8] = {};
	int ret = 0;

	if (len == 0 || len >= sizeof(buf) || copy_from_user(buf, ubuf, len))
		return -EINVAL;
	if (!uke_fs_play && strncmp(buf, "off", 3))	/* PARAR siempre se permite: solo el arranque exige uke_fs_play=Y */
		return -EPERM;
	mutex_lock(&fs_lock);
	if (!strncmp(buf, "on", 2)) {
		if (fs_streaming) {
			ret = -EBUSY;
		} else {
			fs_rate = 48000;
			fs_bclk = 48000 * uke_fs_bclk_ratio;
			fs_vol = min(uke_fs_vol, min(uke_fs_volmax, FS_VOL_HARD));
			fs_scene = min(uke_fs_scene, 14U);
			ret = fs_start_all_locked();
			pr_info("uke_fs19xx: ctl on (sin PCM): rc %d vol 0x%02x\n", ret, fs_vol);
		}
	} else if (!strncmp(buf, "off", 3)) {
		fs_stop_all_locked();
		pr_info("uke_fs19xx: ctl off\n");
	} else {
		ret = -EINVAL;
	}
	mutex_unlock(&fs_lock);
	return ret ? ret : len;
}

static const struct file_operations fs_ctl_fops = {
	.owner = THIS_MODULE,
	.write = fs_ctl_write,
	.llseek = noop_llseek,
};

/* ---- cliente I2C: solo hardware (etapa 0) ---- */
static const struct regmap_config fs_regmap = {
	.reg_bits = 8,
	.val_bits = 16,
	.max_register = 0xff,
	.cache_type = REGCACHE_NONE,
	.volatile_reg = NULL,
};

static int fs19xx_i2c_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	const struct firmware *fw;
	struct fs19xx_amp *a;
	unsigned int id;
	int idx = client->addr - FS_ADDR0, ret;

	if (idx < 0 || idx >= FS_NAMPS)
		return -ENODEV;
	a = devm_kzalloc(dev, sizeof(*a), GFP_KERNEL);
	if (!a)
		return -ENOMEM;
	a->client = client;
	a->map = devm_regmap_init_i2c(client, &fs_regmap);
	if (IS_ERR(a->map))
		return dev_err_probe(dev, PTR_ERR(a->map), "regmap\n");

	/* "reset-gpio" del DT de Android (nivel crudo: bajo = reset); el nucleo acepta el sufijo -gpio */
	/* El vendor pide el GPIO como SALIDA a nivel bajo (devm_gpio_request_one(..., 0)): con GPIOD_ASIS la linea queda como ENTRADA y el
	 * pulso no se manejaria (E8-2, 18-oct: los 4 amps daban -ENXIO). Con uke_fs_reset=0 no se toca la linea. */
	a->rst = devm_gpiod_get_optional(dev, "reset", uke_fs_reset ? GPIOD_OUT_LOW : GPIOD_ASIS);
	if (IS_ERR(a->rst))
		return dev_err_probe(dev, PTR_ERR(a->rst), "reset-gpio\n");

	ret = request_firmware(&fw, FS_FW_NAME, dev);
	if (ret)
		return dev_err_probe(dev, ret, "falta /lib/firmware/%s\n", FS_FW_NAME);
	a->blob = devm_kmemdup(dev, fw->data, fw->size, GFP_KERNEL);
	a->blob_len = fw->size;
	if (!a->blob) {
		release_firmware(fw);
		return -ENOMEM;
	}
	{
		struct firmware tmp = { .size = fw->size, .data = a->blob };

		ret = fs_parse(a, &tmp);
	}
	release_firmware(fw);
	if (ret)
		return dev_err_probe(dev, ret, "preset invalido\n");

	if (a->rst && uke_fs_reset) {
		gpiod_set_raw_value_cansleep(a->rst, 0);
		msleep(10);
		gpiod_set_raw_value_cansleep(a->rst, 1);
		msleep(1);
	}
	ret = fs_rd(a, FS_REG_DEVID, &id);
	if (ret)
		return dev_err_probe(dev, ret, "no contesta (reset liberado: %d)\n", uke_fs_reset);
	a->devid = id;
	dev_info(dev, "DEVID 0x%04x (&0xfff0 %s 0x5b0), preset OK: %u comunes, %u de escena, info[1]=0x%03x pos=%u\n",
		 id, (id & 0xfff0) == 0x5b0 ? "==" : "!=", a->ncommon, a->nscene, a->info[1], a->info[16]);
	if (!fs_newvar(a))
		return dev_err_probe(dev, -ENODEV, "DEVID 0x%04x no soportado (solo familias 0x17xx/0x29xx: sin secuencia de arranque validada)\n", id);

	mutex_lock(&fs_lock);
	fs_amps[idx] = a;
	mutex_unlock(&fs_lock);
	i2c_set_clientdata(client, a);
	return 0;
}

static void fs19xx_shutdown(struct device *dev)
{
	/* reboot/poweroff con audio sonando: parar los amps antes (no hay otro punto de parada en el apagado) */
	mutex_lock(&fs_lock);
	fs_stop_all_locked();
	mutex_unlock(&fs_lock);
}

static void fs19xx_i2c_remove(struct i2c_client *client)
{
	struct fs19xx_amp *a = i2c_get_clientdata(client);
	int i;

	mutex_lock(&fs_lock);
	if (a && a->on)
		fs_shut_down(a);
	for (i = 0; i < FS_NAMPS; i++)
		if (fs_amps[i] == a)
			fs_amps[i] = NULL;
	mutex_unlock(&fs_lock);
}

static const struct of_device_id fs19xx_of_match[] = {
	{ .compatible = "foursemi,fs16xx" },
	{ }
};
MODULE_DEVICE_TABLE(of, fs19xx_of_match);

static struct i2c_driver fs19xx_i2c_driver = {
	.driver = { .name = "uke-fs19xx", .of_match_table = fs19xx_of_match, .shutdown = fs19xx_shutdown },
	.probe = fs19xx_i2c_probe,
	.remove = fs19xx_i2c_remove,
};

/* ---- DAI/componente (etapa 1): un unico codec "fs16xx-aif" que gobierna los amps presentes ---- */
static int fs_dai_hw_params(struct snd_pcm_substream *ss, struct snd_pcm_hw_params *p, struct snd_soc_dai *dai)
{
	u32 rate = params_rate(p);

	if (rate != 48000)			/* PLL de 6,144 MHz = unico caso medido (ACDB + tabla del vendor) */
		return -EINVAL;
	mutex_lock(&fs_lock);
	fs_rate = rate;
	fs_bclk = rate * uke_fs_bclk_ratio;
	mutex_unlock(&fs_lock);
	return 0;
}

static int fs_dai_mute(struct snd_soc_dai *dai, int mute, int stream)
{
	int ret = 0;

	if (stream != SNDRV_PCM_STREAM_PLAYBACK)
		return 0;
	if (!uke_fs_play && !mute) {		/* arrancar exige uke_fs_play=Y; PARAR (mute) siempre se atiende */
		dev_info(dai->dev, "mute=%d ignorado (uke_fs_play=0): los amps no se tocan\n", mute);
		return 0;
	}
	mutex_lock(&fs_lock);
	if (!mute && !fs_streaming) {
		fs_vol = min(uke_fs_vol, min(uke_fs_volmax, FS_VOL_HARD));
		fs_scene = min(uke_fs_scene, 14U);
		ret = fs_start_all_locked();
		dev_info(dai->dev, "amps habilitados: rc %d (vol 0x%02x, escena %u)\n", ret, fs_vol, fs_scene);
	} else if (mute && fs_streaming) {
		fs_stop_all_locked();
		dev_info(dai->dev, "amps parados\n");
	}
	mutex_unlock(&fs_lock);
	return ret;
}

static const struct snd_soc_dai_ops fs_dai_ops = {
	.hw_params = fs_dai_hw_params,
	.mute_stream = fs_dai_mute,
	.no_capture_mute = 1,
};

static struct snd_soc_dai_driver fs_dai = {
	.name = "fs16xx-aif",
	.playback = {
		.stream_name = "AIF Playback",
		.channels_min = 1, .channels_max = 4,
		.rates = SNDRV_PCM_RATE_48000,
		.formats = SNDRV_PCM_FMTBIT_S16_LE | SNDRV_PCM_FMTBIT_S24_LE | SNDRV_PCM_FMTBIT_S32_LE,
	},
	.ops = &fs_dai_ops,
};

static int fs_vol_get(struct snd_kcontrol *k, struct snd_ctl_elem_value *u)
{
	u->value.integer.value[0] = fs_vol;
	return 0;
}

static int fs_vol_put(struct snd_kcontrol *k, struct snd_ctl_elem_value *u)
{
	long v = u->value.integer.value[0];

	if (v < 0 || v > min(uke_fs_volmax, FS_VOL_HARD))
		return -EINVAL;
	mutex_lock(&fs_lock);
	fs_vol = v;
	if (fs_streaming) {		/* cambio en caliente solo de volumen */
		int i;

		for (i = 0; i < FS_NAMPS; i++)
			if (fs_amps[i] && fs_amps[i]->on)
				fs_set_vol(fs_amps[i]);
	}
	mutex_unlock(&fs_lock);
	return 1;
}

static int fs_scene_get(struct snd_kcontrol *k, struct snd_ctl_elem_value *u)
{
	u->value.integer.value[0] = fs_scene;
	return 0;
}

static int fs_scene_put(struct snd_kcontrol *k, struct snd_ctl_elem_value *u)
{
	long v = u->value.integer.value[0];

	if (v < 0 || v > 14)
		return -EINVAL;
	mutex_lock(&fs_lock);
	if (fs_streaming) {
		mutex_unlock(&fs_lock);
		return -EBUSY;		/* la escena solo se cambia con el PCM parado: se aplica en el siguiente arranque */
	}
	uke_fs_scene = v;
	mutex_unlock(&fs_lock);
	return 1;
}

static const struct snd_kcontrol_new fs_controls[] = {
	SOC_SINGLE_EXT("FS19XX Volume", SND_SOC_NOPM, 0, 255, 0, fs_vol_get, fs_vol_put),
	SOC_SINGLE_EXT("FS19XX Scene", SND_SOC_NOPM, 0, 14, 0, fs_scene_get, fs_scene_put),
};

static const struct snd_soc_component_driver fs_component = {
	.name = "uke-fs19xx",
	.controls = fs_controls,
	.num_controls = ARRAY_SIZE(fs_controls),
	.idle_bias_on = 1,
	.endianness = 1,
};

static int fs19xx_codec_probe(struct platform_device *pdev)
{
	int i, n = 0;

	mutex_lock(&fs_lock);
	for (i = 0; i < FS_NAMPS; i++)
		n += !!fs_amps[i];
	mutex_unlock(&fs_lock);
	if (n < uke_fs_min_amps)
		return dev_err_probe(&pdev->dev, -EPROBE_DEFER, "solo %d/%u amps listos\n", n, uke_fs_min_amps);
	fs_vol = min(uke_fs_vol, min(uke_fs_volmax, FS_VOL_HARD));
	fs_scene = min(uke_fs_scene, 14U);
	dev_info(&pdev->dev, "DAI fs16xx-aif con %d amp(s); uke_fs_play=%d vol=0x%02x tope=0x%02x\n", n, uke_fs_play, fs_vol, min(uke_fs_volmax, FS_VOL_HARD));
	return devm_snd_soc_register_component(&pdev->dev, &fs_component, &fs_dai, 1);
}

static void fs19xx_codec_remove(struct platform_device *pdev)
{
	mutex_lock(&fs_lock);
	fs_stop_all_locked();
	mutex_unlock(&fs_lock);
}

static const struct of_device_id fs19xx_codec_of[] = {
	{ .compatible = "uke,fs19xx-codec" },
	{ }
};
MODULE_DEVICE_TABLE(of, fs19xx_codec_of);

static struct platform_driver fs19xx_codec_driver = {
	.driver = { .name = "uke-fs19xx-codec", .of_match_table = fs19xx_codec_of, .shutdown = fs19xx_shutdown },
	.probe = fs19xx_codec_probe,
	.remove = fs19xx_codec_remove,
};

static int __init uke_fs19xx_init(void)
{
	int ret;

	fs_dbg = debugfs_create_dir("uke_fs19xx", NULL);
	debugfs_create_file("regs", 0444, fs_dbg, NULL, &fs_regs_fops);
	debugfs_create_file("ctl", 0200, fs_dbg, NULL, &fs_ctl_fops);
	ret = i2c_add_driver(&fs19xx_i2c_driver);
	if (ret) {
		debugfs_remove_recursive(fs_dbg);
		return ret;
	}
	ret = platform_driver_register(&fs19xx_codec_driver);
	if (ret)
		i2c_del_driver(&fs19xx_i2c_driver);
	return ret;
}

static void __exit uke_fs19xx_exit(void)
{
	debugfs_remove_recursive(fs_dbg);
	platform_driver_unregister(&fs19xx_codec_driver);
	i2c_del_driver(&fs19xx_i2c_driver);
}

module_init(uke_fs19xx_init);
module_exit(uke_fs19xx_exit);
MODULE_DESCRIPTION("FourSemi FS19xx (fs16xx) smart amplifiers of the Xiaomi Pad 7 (uke) - minimal fail-closed driver");
MODULE_LICENSE("GPL");
MODULE_FIRMWARE(FS_FW_NAME);
