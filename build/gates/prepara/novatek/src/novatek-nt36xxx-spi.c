// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * SPI driver for Novatek NT36xxx-family touch controllers
 * (Xiaomi Pad 7 "uke": NT36532, TDDI panel, touch on QUP0 SE4 SPI).
 *
 * PROTOCOL: verified against the actual vendor kernel module
 * nt36532_touch.ko (ELF aarch64, not stripped) instead of guessed:
 *   - CTP_SPI_READ   @ .text 0x4e8 (calls spi_sync)
 *   - CTP_SPI_WRITE  @ .text 0x754
 *   - nvt_set_page   @ .text 0x9a0 (register 0xFF, [A22:15][A14:7])
 *   - nvt_ts_work_func @ .text 0x8914 (event read 0x101 = 257 bytes,
 *     sync pattern 0xFD/0xFE, additive checksum 64+1 == 0, fingers
 *     = head >> 3)
 *   - NT36532_single_memory_map @ .rodata 0x9e00 (EVENT_BUF = 0x125800)
 *   - nvt_ts_check_chip_ver_trim_loop @ .text 0x8370 (chip-id region
 *     0x1fb535)
 *
 * Wire format (verified, byte-exact):
 *   write: one spi_message, tx = [cmd | 0x80][payload...][0x00], with
 *          cmd = addr & 0x7f; page select written first as a 3-byte
 *          write [0xff][addr >> 15][addr >> 7].  5 retries (the .ko
 *          loops 5 times around spi_sync).
 *   read:  one spi_message, FULL-DUPLEX, tx = [cmd & 0x7f][0x00 * len]
 *          and rx into a separate buffer, both len+1 bytes; the chip
 *          answers [junk][dummy][data * len] so the data lands at
 *          rbuf[2] (the .ko does memcpy(buf + 1, xbuf2 + 2, len - 1)
 *          at 0x6e8-0x6fc).  5 retries.
 *
 * The finger-record layout inside the event packet is the ONLY piece
 * that could not be verified: the vendor module hands the raw packet
 * to xiaomi_touch.ko (notify_raw_data_update, 5176 bytes) and the MT
 * reporting happens there, not in this module.  See the big comment
 * above nvt_spi_parse_point() for the candidates and how to tell them
 * apart on hardware.
 *
 * Copyright (c) 2026 bring-up: Xiaomi Pad 7 mainline project.
 */

#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/interrupt.h>
#include <linux/input.h>
#include <linux/input/mt.h>
#include <linux/input/touchscreen.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/regulator/consumer.h>
#include <linux/spi/spi.h>

#include <linux/unaligned.h>

/* --- Bus access (verified against nt36532_touch.ko) -------------------- */
#define NVT_SPI_CMD_ADDR_MASK		0x7f	/* A[6:0] rides on the cmd byte */
#define NVT_SPI_CMD_WRITE_BIT		0x80	/* write command flag */
#define NVT_SPI_PAGE_SEL_REG		0xff	/* page select register */
#define NVT_SPI_XFER_RETRIES		5	/* .ko loops 5x on spi_sync */

/* --- Event report (verified addresses/frame from the .ko) -------------- */
/* NT36532_single_memory_map[0]; .ko page-selects it in nvt_get_fw_info */
#define NVT_SPI_EVENT_BUF_ADDR		0x125800
/* work_func reads 0x101 = 1 cmd byte + 256 data bytes */
#define NVT_SPI_EVENT_DATA_LEN		256
/* data[0..5]: each byte is 0xfd or 0xfe in an idle/gesture frame */
#define NVT_SPI_SYNC_LEN		6
#define NVT_SPI_SYNC_BYTE_LO		0xfd
#define NVT_SPI_SYNC_BYTE_HI		0xfe
/* additive checksum packet: data[0..0x3f] summed, data[0x40] = -sum */
#define NVT_SPI_CKSUM_DATA_LEN		64
#define NVT_SPI_CKSUM_OFF		0x40

/* chip-id/trim region probed by nvt_ts_check_chip_ver_trim_loop (0x8370) */
#define NVT_SPI_CHIP_ID_ADDR		0x1fb535
#define NVT_SPI_CHIP_ID_LEN		4

#define NVT_SPI_MAX_FINGERS		10	/* .ko: strb #0xa, [ts+0xc2] */
#define NVT_SPI_MAX_SIZE		4096
#define NVT_SPI_XFER_MAX		512	/* kmalloc'd bus buffers */

/* Panel del Xiaomi Pad 7 (uke): 1600x2136. Overridable por DT. */
#define NVT_SPI_DEF_X_SIZE		1600
#define NVT_SPI_DEF_Y_SIZE		2136

/*
 * LAYOUT del registro de dedo: NO verificado (ver nvt_spi_parse_point).
 * 0 = candidato A (por defecto), 1 = candidato B, 2 = candidato C.
 * Cambiable en runtime: /sys/module/novatek-nt36xxx-spi/parameters/point_layout
 */
static unsigned int point_layout;
module_param_named(point_layout, point_layout, uint, 0644);
MODULE_PARM_DESC(point_layout,
		 "Finger record layout guess: 0=A(head+6B), 1=B(7B classic), 2=C(5B LE)");

struct nvt_spi_data {
	struct spi_device *spi;
	struct input_dev *input;
	struct gpio_desc *reset_gpio;
	struct mutex bus_mutex;		/* the .ko guards its bus with one */
	u8 *xbuf;			/* DMA-safe tx buffer (ko: ts->[0x348]) */
	u8 *rbuf;			/* DMA-safe rx buffer (ko: ts->[0x340]) */
	bool pen_support;		/* DT: novatek,pen-support (sin soporte) */
	struct touchscreen_properties prop;
	u8 event[NVT_SPI_EVENT_DATA_LEN];
	bool sync_warned;
	bool cksum_warned;
};

/* --- Low-level bus helpers, mirroring the .ko -------------------------- */

/*
 * CTP_SPI_WRITE (ko 0x754): frame = [cmd|0x80][payload][0x00], tx-only,
 * spi_sync with 5 retries.  cmd_frame[0] must be (addr & 0x7f); the
 * payload bytes follow it in cmd_frame (len counts cmd + payload).
 * Caller must hold bus_mutex.
 */
static int nvt_spi_write_frame(struct nvt_spi_data *ts, const u8 *cmd_frame,
			       size_t len)
{
	struct spi_transfer xfer = { };
	struct spi_message m;
	unsigned int retry;
	int ret = 0;

	if (len + 1 > NVT_SPI_XFER_MAX)
		return -EINVAL;

	memset(ts->xbuf, 0, len + 1);
	ts->xbuf[0] = cmd_frame[0] | NVT_SPI_CMD_WRITE_BIT;
	memcpy(&ts->xbuf[1], &cmd_frame[1], len - 1);

	xfer.tx_buf = ts->xbuf;
	xfer.len = len + 1;
	spi_message_init_with_transfers(&m, &xfer, 1);

	for (retry = 0; retry < NVT_SPI_XFER_RETRIES; retry++) {
		ret = spi_sync(ts->spi, &m);
		if (!ret)
			break;
	}
	if (ret)
		dev_err(&ts->spi->dev, "SPI write @0x%02x failed: %d\n",
			cmd_frame[0], ret);

	return ret;
}

/* nvt_set_page (ko 0x9a0): write [0xff][A22:15][A14:7] to reg 0xff. */
static int nvt_spi_set_page(struct nvt_spi_data *ts, u32 addr)
{
	const u8 cmd[3] = {
		NVT_SPI_PAGE_SEL_REG,
		addr >> 15,
		addr >> 7,
	};

	return nvt_spi_write_frame(ts, cmd, sizeof(cmd));
}

/*
 * CTP_SPI_READ (ko 0x4e8): full-duplex message, tx = [cmd][0x00 * len]
 * (len+1 bytes) and rx into a SEPARATE buffer (ko: tx_buf = ts->xbuf,
 * rx_buf = ts->rbuf).  The chip answers [junk][dummy][data * len], so
 * the caller's data starts at rbuf[2] (ko memcpy at 0x6e8).  On return
 * buf[] holds exactly @len clean data bytes.
 */
static int nvt_spi_read(struct nvt_spi_data *ts, u32 addr, u8 *buf, size_t len)
{
	struct spi_transfer xfer = { };
	struct spi_message m;
	unsigned int retry;
	int ret = 0;

	if (len + 1 > NVT_SPI_XFER_MAX)
		return -EINVAL;

	guard(mutex)(&ts->bus_mutex);

	ret = nvt_spi_set_page(ts, addr);
	if (ret)
		return ret;

	memset(ts->xbuf, 0, len + 1);
	ts->xbuf[0] = addr & NVT_SPI_CMD_ADDR_MASK;

	xfer.tx_buf = ts->xbuf;
	xfer.rx_buf = ts->rbuf;
	xfer.len = len + 1;
	spi_message_init_with_transfers(&m, &xfer, 1);

	for (retry = 0; retry < NVT_SPI_XFER_RETRIES; retry++) {
		ret = spi_sync(ts->spi, &m);
		if (!ret)
			break;
	}
	if (ret) {
		dev_err(&ts->spi->dev, "SPI read @0x%06x failed: %d\n",
			addr, ret);
		return ret;
	}

	memcpy(buf, &ts->rbuf[2], len);	/* skip junk + 1 dummy byte */

	return 0;
}

/*
 * Write @len payload bytes to register @addr (page select included).
 * Still unused by the probe/rescue paths; kept as the verified transport
 * entry point for hardware triage (e.g. issuing the .ko's SW-reset write
 * once its register address is mapped).
 */
static __maybe_unused int nvt_spi_write(struct nvt_spi_data *ts, u32 addr,
					const u8 *buf, size_t len)
{
	u8 cmd[1 + 16];
	int ret;

	if (len > sizeof(cmd) - 1)
		return -EINVAL;

	guard(mutex)(&ts->bus_mutex);

	cmd[0] = addr & NVT_SPI_CMD_ADDR_MASK;
	memcpy(&cmd[1], buf, len);

	ret = nvt_spi_set_page(ts, addr);
	if (ret)
		return ret;

	return nvt_spi_write_frame(ts, cmd, len + 1);
}

/* --- Event frame validation (verified against the .ko) ----------------- */

/*
 * data[0..5] == 0xfd/0xfe each => idle/gesture frame (ko work_func
 * 0x8ac4-0x8b44: (b + 3) & 0xff <= 1 for all six).  Returns true when
 * the frame carries NO touch data.
 */
static bool nvt_spi_frame_is_idle(const u8 *data)
{
	unsigned int i;

	for (i = 0; i < NVT_SPI_SYNC_LEN; i++) {
		u8 b = data[i];

		if (b != NVT_SPI_SYNC_BYTE_LO && b != NVT_SPI_SYNC_BYTE_HI)
			return false;
	}
	return true;
}

/*
 * Checksum aditivo del packet de 64+1 bytes (ko 0x8c34-0x8c5c):
 * sum(data[0..0x3f]) + data[0x40] == 0 (mod 256).  Siempre se comprueba;
 * no es fatal: se loguea UNA vez con detalle y luego ratelimited.
 */
static bool nvt_spi_frame_cksum_ok(struct nvt_spi_data *ts, const u8 *data)
{
	u8 sum = 0;
	unsigned int i;

	for (i = 0; i < NVT_SPI_CKSUM_DATA_LEN; i++)
		sum += data[i];

	if ((u8)(sum + data[NVT_SPI_CKSUM_OFF]) == 0) {
		ts->cksum_warned = false;
		return true;
	}

	if (!ts->cksum_warned) {
		ts->cksum_warned = true;
		dev_warn(&ts->spi->dev,
			 "checksum mismatch: sum(data[0..0x3f])=0x%02x vs data[0x40]=0x%02x, frame head: %16ph\n",
			 sum, data[NVT_SPI_CKSUM_OFF], data);
	} else {
		dev_warn_ratelimited(&ts->spi->dev,
				     "checksum mismatch (sum=0x%02x cksum=0x%02x)\n",
				     sum, data[NVT_SPI_CKSUM_OFF]);
	}

	return false;
}

/* --- Finger record layout: NO VERIFICADO ------------------------------- */

/*
 * ===========================================================================
 * LAYOUT DEL REGISTRO DE DEDO — NO VERIFICADO contra el .ko
 * ===========================================================================
 * El modulo del fabricante NO decodifica los records en este .ko: entrega
 * el packet crudo a xiaomi_touch.ko (notify_raw_data_update, ko 0x8ccc,
 * 5176 bytes) y es xiaomi_touch quien hace el reporte MT (sus registros
 * decodificados son de 28 B {slot u32, pressed u32, x u32, y u32, ...}).
 * Lo unico verificado del head: el numero de dedos es (u16_le >> 3) del
 * head (ko 0x8c60 sobre data[0] no-DMA; en el camino DMA el mismo valor
 * es el campo id u16 del header {id, magic 0x509/0x4BF, ~id, ~magic} en
 * +0x105, validado contra su complemento, ko 0x8bb4-0x8be8).
 *
 * Restricciones que sí se pueden afirmar: el packet util es data[0..0x3f]
 * (64 B, el checksum cubre todo), y en frame idle los 6 primeros bytes son
 * el patron 0xfd/0xfe. Para 10 dedos caben records de hasta 6 bytes
 * (10*6 = 60 <= 62 desde data[2]); records de 7 u 8 bytes no caben con los
 * 6 sync delante (58 B) ni detras del head solo (62 B para 8 B x7 max).
 *
 * Candidatos (seleccionables con el module param point_layout):
 *   A (por defecto): head u16 LE en data[0..1] (count = >>3), records de
 *       6 B desde data[2 + 6*i]: {x_hi4|x_lo, y_hi4|y_lo, pressure, tid}.
 *       x/y de 12 bits estilo Novatek clasico. 10*6 = 60 <= 62: el unico
 *       que cabe para 10 dedos sin romper el patron idle.
 *   B: 7 B/dedo estilo NT36xxx clasico {x_hi, x_lo, y_hi, y_lo, pressure,
 *       area, gid} desde data[2]; implica que el head no gasta 2 bytes
 *       (count = data[0] >> 3 y data[1] seria byte bajo del head/flags).
 *   C: 5 B/dedo LE {x u12 | y u12 en 3 B, pressure, tid} desde data[2]
 *       (50 <= 62). Probable si el FW empaqueta 12-bit contiguos LE, como
 *       los u16/u32 LE que el .ko lee en sus cabeceras.
 *
 * Como distinguirlos con evtest en hardware (ver TOUCH-REWRITE.md):
 *   - tocar con UN dedo y mirar cuantos slots se mueven (A: 1; si el
 *     stride es otro, los slots bailan o el id salta) y con que rango;
 *   - esquinas opuestas: (0,0) y (max,max) esperados; X/Y intercambiados
 *     => el marco nativo del IC es el lado largo (X_Channel=60 en el eje
 *     de 1600 px segun MP criteria) => intercambiar size-x/size-y;
 *   - coordenadas que solo toman valores multiplos grandes => stride o
 *     endian mal (probar point_layout=2, luego 1).
 * En cuanto se confirme el layout en hardware, fijar UNO y borrar el resto.
 * ===========================================================================
 */
static bool nvt_spi_parse_point(struct nvt_spi_data *ts, unsigned int i,
				u16 *x, u16 *y, u8 *tid)
{
	const u8 *data = ts->event;
	const u8 *rec;

	switch (point_layout) {
	case 2:
		/* Candidato C: head u16 + 5 B/dedo LE desde data[2] */
		rec = &data[2 + i * 5];
		*x = (rec[0] | (rec[1] << 8)) & 0x0fff;
		*y = ((rec[1] >> 4) | (rec[2] << 4)) & 0x0fff;
		*tid = rec[4];
		return rec[3] != 0;
	case 1:
		/* Candidato B: 7 B/dedo clasico desde data[2] */
		rec = &data[2 + i * 7];
		*x = ((rec[0] & 0xf0) << 4) | rec[1];
		*y = ((rec[2] & 0xf0) << 4) | rec[3];
		*tid = rec[6];
		return rec[4] != 0;
	default:
		/* Candidato A (por defecto): head u16 + 6 B/dedo */
		rec = &data[2 + i * 6];
		*x = ((rec[0] & 0xf0) << 4) | rec[1];
		*y = ((rec[2] & 0xf0) << 4) | rec[3];
		*tid = rec[5] & 0x0f;
		return rec[4] != 0;
	}
}

/* --- IRQ / reporting ---------------------------------------------------- */

static void nvt_spi_report_release(struct nvt_spi_data *data)
{
	input_mt_sync_frame(data->input);
	input_sync(data->input);
}

static irqreturn_t nvt_spi_irq(int irq, void *dev_id)
{
	struct nvt_spi_data *data = dev_id;
	struct device *dev = &data->spi->dev;
	u8 *ev = data->event;
	unsigned int n_contacts, i;

	if (nvt_spi_read(data, NVT_SPI_EVENT_BUF_ADDR, ev,
			 NVT_SPI_EVENT_DATA_LEN))
		return IRQ_HANDLED;

	/* Frame idle/gesto: patron 0xfd/0xfe verificado => no hay toques */
	if (nvt_spi_frame_is_idle(ev)) {
		nvt_spi_report_release(data);
		return IRQ_HANDLED;
	}

	if (!nvt_spi_frame_cksum_ok(data, ev))
		return IRQ_HANDLED;

	/* Nº de dedos: head u16 LE >> 3 (ko 0x8c60 / header DMA 0x8bb8) */
	n_contacts = min_t(unsigned int,
			   get_unaligned_le16(ev) >> 3, NVT_SPI_MAX_FINGERS);

	for (i = 0; i < n_contacts; i++) {
		u16 x, y;
		u8 tid;
		bool active;

		active = nvt_spi_parse_point(data, i, &x, &y, &tid);
		if (!active)
			continue;

		if (x >= data->prop.max_x + 1 || y >= data->prop.max_y + 1) {
			dev_dbg(dev, "contact %u out of range (%ux%u)\n",
				i, x, y);
			continue;
		}

		input_mt_slot(data->input, i);
		input_mt_report_slot_state(data->input, MT_TOOL_FINGER, true);
		touchscreen_report_pos(data->input, &data->prop, x, y, true);
	}

	input_mt_sync_frame(data->input);
	input_sync(data->input);

	return IRQ_HANDLED;
}

/* --- Power / open / close ------------------------------------------------ */

static int nvt_spi_start(struct input_dev *dev)
{
	struct nvt_spi_data *data = input_get_drvdata(dev);

	enable_irq(data->spi->irq);

	return 0;
}

static void nvt_spi_stop(struct input_dev *dev)
{
	struct nvt_spi_data *data = input_get_drvdata(dev);

	disable_irq(data->spi->irq);
}

static int nvt_spi_suspend(struct device *dev)
{
	struct nvt_spi_data *data = dev_get_drvdata(dev);

	guard(mutex)(&data->input->mutex);

	if (input_device_enabled(data->input))
		nvt_spi_stop(data->input);

	return 0;
}

static int nvt_spi_resume(struct device *dev)
{
	struct nvt_spi_data *data = dev_get_drvdata(dev);

	guard(mutex)(&data->input->mutex);

	if (input_device_enabled(data->input))
		return nvt_spi_start(data->input);

	return 0;
}

static DEFINE_SIMPLE_DEV_PM_OPS(nvt_spi_pm_ops, nvt_spi_suspend,
				nvt_spi_resume);

/* --- Probe --------------------------------------------------------------- */

static const char * const nvt_spi_regulator_names[] = { "vdd", "vddio" };

/*
 * El chip deberia estar vivo (TDDI: el FW del touch arranca con el panel).
 * Si el EVENT_BUF no responde, se intenta UN ciclo corto de reset/handshake
 * para dejar constancia exacta en dmesg de hasta donde llega, sin bucles
 * infinitos ni sleeps largos.
 */
static void nvt_spi_chip_alive_check(struct nvt_spi_data *data)
{
	struct device *dev = &data->spi->dev;
	u8 id[NVT_SPI_CHIP_ID_LEN] = { };
	int ret, attempt;

	/* chip-id (region trim 0x1fb535, ko nvt_ts_check_chip_ver_trim_loop):
	 * solo diagnostico, no decide nada. */
	ret = nvt_spi_read(data, NVT_SPI_CHIP_ID_ADDR, id, sizeof(id));
	if (ret)
		dev_warn(dev, "chip-id read @0x%06x failed: %d\n",
			 NVT_SPI_CHIP_ID_ADDR, ret);
	else
		dev_info(dev, "chip-id @0x%06x: %*ph\n",
			 NVT_SPI_CHIP_ID_ADDR, (int)sizeof(id), id);

	ret = nvt_spi_read(data, NVT_SPI_EVENT_BUF_ADDR, data->event,
			   NVT_SPI_EVENT_DATA_LEN);
	if (!ret && (nvt_spi_frame_is_idle(data->event) ||
		     nvt_spi_frame_cksum_ok(data, data->event))) {
		dev_info(dev,
			 "chip alive: EVENT_BUF frame ok (idle=%d), head %*ph\n",
			 nvt_spi_frame_is_idle(data->event), 12, data->event);
		return;
	}

	/* Chip mudo: handshake opcional. Timeout corto y log claro. */
	dev_warn(dev,
		 "EVENT_BUF no responde (ret=%d, head %12ph): intentando reset/bootloader handshake\n",
		 ret, data->event);

	if (data->reset_gpio) {
		gpiod_set_value_cansleep(data->reset_gpio, 1);
		usleep_range(10000, 11000);
		gpiod_set_value_cansleep(data->reset_gpio, 0);
		msleep(240);	/* boot de FW TDDI */
	}

	for (attempt = 0; attempt < 5; attempt++) {
		ret = nvt_spi_read(data, NVT_SPI_EVENT_BUF_ADDR,
				   data->event, NVT_SPI_EVENT_DATA_LEN);
		if (!ret && (nvt_spi_frame_is_idle(data->event) ||
			     nvt_spi_frame_cksum_ok(data, data->event))) {
			dev_info(dev,
				 "chip vivo tras handshake (intento %d), head %12ph\n",
				 attempt + 1, data->event);
			return;
		}
		msleep(20);
	}

	dev_warn(dev,
		 "chip SIGUE mudo tras handshake (%d): revisar alimentacion TDDI (panel), bus SPI o IRQ; continuando sin chip\n",
		 ret);
}

static int nvt_spi_probe(struct spi_device *spi)
{
	struct device *dev = &spi->dev;
	struct nvt_spi_data *data;
	struct input_dev *input;
	int error;

	if (!spi->irq) {
		dev_err(dev, "no IRQ specified\n");
		return -EINVAL;
	}

	data = devm_kzalloc(dev, sizeof(*data), GFP_KERNEL);
	if (!data)
		return -ENOMEM;

	data->spi = spi;
	spi_set_drvdata(spi, data);
	mutex_init(&data->bus_mutex);

	data->xbuf = devm_kmalloc(dev, NVT_SPI_XFER_MAX, GFP_KERNEL);
	data->rbuf = devm_kmalloc(dev, NVT_SPI_XFER_MAX, GFP_KERNEL);
	if (!data->xbuf || !data->rbuf)
		return -ENOMEM;

	data->pen_support = device_property_read_bool(dev, "novatek,pen-support");
	if (data->pen_support)
		dev_warn(dev,
			 "novatek,pen-support presente: el stylus no esta implementado\n");

	/*
	 * Supplies OPCIONALES: el DT vendor del uke no declara supplies
	 * (TDDI: los rieles van con el panel). Sin vdd/vddio el core usa
	 * dummies; si un overlay las declara, se controlan de verdad.
	 */
	error = devm_regulator_bulk_get_enable(dev,
					       ARRAY_SIZE(nvt_spi_regulator_names),
					       nvt_spi_regulator_names);
	if (error)
		return dev_err_probe(dev, error,
				     "failed to get/enable regulators\n");

	/*
	 * Reset OPCIONAL: el nodo vendor no trae reset-gpio (TDDI). Si un
	 * overlay lo declara, se usa solo en el camino de rescate del
	 * handshake (nvt_spi_chip_alive_check), como hace el .ko en
	 * nvt_bootloader_reset.
	 */
	data->reset_gpio = devm_gpiod_get_optional(dev, "reset", GPIOD_OUT_LOW);
	if (IS_ERR(data->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(data->reset_gpio),
				     "failed to request reset GPIO\n");

	nvt_spi_chip_alive_check(data);

	input = devm_input_allocate_device(dev);
	if (!input)
		return -ENOMEM;

	input->name = "Novatek NT36xxx Touchscreen";
	input->id.bustype = BUS_SPI;
	input->open = nvt_spi_start;
	input->close = nvt_spi_stop;

	input_set_abs_params(input, ABS_MT_POSITION_X,
			     0, NVT_SPI_DEF_X_SIZE - 1, 0, 0);
	input_set_abs_params(input, ABS_MT_POSITION_Y,
			     0, NVT_SPI_DEF_Y_SIZE - 1, 0, 0);
	touchscreen_parse_properties(input, true, &data->prop);
	if (data->prop.max_x + 1 > NVT_SPI_MAX_SIZE ||
	    data->prop.max_y + 1 > NVT_SPI_MAX_SIZE) {
		dev_err(dev, "touchscreen-size too large (%ux%u)\n",
			data->prop.max_x + 1, data->prop.max_y + 1);
		return -EINVAL;
	}

	error = input_mt_init_slots(input, NVT_SPI_MAX_FINGERS,
				    INPUT_MT_DIRECT | INPUT_MT_DROP_UNUSED);
	if (error)
		return dev_err_probe(dev, error, "failed to init MT slots\n");

	data->input = input;
	input_set_drvdata(input, data);

	error = devm_request_threaded_irq(dev, spi->irq, NULL, nvt_spi_irq,
					  IRQF_ONESHOT | IRQF_NO_AUTOEN |
						irq_get_trigger_type(spi->irq),
					  input->name, data);
	if (error)
		return dev_err_probe(dev, error, "failed to request irq\n");

	error = input_register_device(input);
	if (error)
		return dev_err_probe(dev, error,
				     "failed to register input device\n");

	dev_info(dev,
		 "NT36xxx SPI probe ok: irq %d (trigger 0x%lx), %ux%u, transporte verificado vs nt36532_touch.ko; layout de dedo SIN verificar (point_layout=%u)\n",
		 spi->irq, (unsigned long)irq_get_trigger_type(spi->irq),
		 data->prop.max_x + 1, data->prop.max_y + 1, point_layout);

	return 0;
}

/*
 * El compatible es EXACTAMENTE el del nodo vendor del dtbo stock del uke
 * ("novatek,NVT-ts-spi", mayusculas incluidas; fragment@35 -> qupv3_se4_spi).
 * "novatek,nt36xxx-spi" queda como alias en minusculas para DTs nuevos.
 */
static const struct of_device_id nvt_spi_of_match[] = {
	{ .compatible = "novatek,NVT-ts-spi" },
	{ .compatible = "novatek,nt36xxx-spi" },
	{ }
};
MODULE_DEVICE_TABLE(of, nvt_spi_of_match);

static struct spi_driver nvt_spi_driver = {
	.driver = {
		.name		= "novatek-nt36xxx-spi",
		.pm		= pm_sleep_ptr(&nvt_spi_pm_ops),
		.of_match_table	= nvt_spi_of_match,
	},
	.probe	= nvt_spi_probe,
};

module_spi_driver(nvt_spi_driver);

MODULE_DESCRIPTION("Novatek NT36xxx SPI touchscreen driver (protocol verified vs vendor module)");
MODULE_AUTHOR("Xiaomi Pad 7 mainline bring-up");
MODULE_LICENSE("GPL");
