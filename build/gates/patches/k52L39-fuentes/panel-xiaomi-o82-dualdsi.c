// SPDX-License-Identifier: GPL-2.0-only
/*
 * Xiaomi O82 (42_02_0b) dual-DSI DSC video-mode LCD panel driver
 *
 * Panel driven by two MIPI-DSI links (bonded/broadcast, 4 lanes each):
 * 1600x2136 px per link, 3200x2136 total, DSC 1.1 (10 bpc -> 8 bpp,
 * slices 800x24, block prediction on), 120/144/90 Hz.
 *
 * All panel data (init sequence, off sequence, timings, DSC block,
 * regulators, reset sequence) comes verbatim from the vendor device
 * tree overlay node "qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid",
 * as transcribed in:
 *   criticas/ronda-29/PANEL-O82.md (Xiaomi Pad 7 / "uke", SM7675).
 * Nothing in the sequences below is invented or reverse-engineered.
 *
 * Dual-DSI handling follows the same scheme as panel-novatek-nt36523.c:
 * the panel node hangs off the primary DSI controller and the driver
 * registers a second DSI device on the host behind port@1, then sends
 * every command to both links (the vendor uses broadcast mode).
 */

#include <linux/uke-poke.h>
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/interrupt.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_graph.h>
#include <linux/regulator/consumer.h>

#include <drm/display/drm_dsc.h>
#include <drm/display/drm_dsc_helper.h>
#include <drm/drm_mipi_dsi.h>
#include <drm/drm_modes.h>
#include <drm/drm_panel.h>

#include <video/mipi_display.h>

/* Brillo: EXTERNO (Kinetic KTZ8866 por I2C, "bl_ctrl_external" del vendor).
 * El vendor NUNCA escribe DCS 0x51 en este panel (ID 0x14):
 * dsi_panel_set_backlight() case 3 llama a ktz8866_backlight_update_status().
 * El phandle 'backlight' del DT resuelve al KTZ y el core DRM lo enciende en
 * drm_panel_enable() (tras el modeset ~= delay_until_first_frame del vendor).
 * Los niveles min/max/init viven en el driver KTZ + DT stock, no aqui.
 */
/* Vendor: qcom,supply-enable-load of the three panel supply entries. */
#define O82_SUPPLY_ENABLE_LOAD_UA	300000

struct o82_panel {
	struct drm_panel panel;
	struct mipi_dsi_device *dsi[2];
	const struct o82_panel_desc *desc;
	struct drm_dsc_config dsc;
	struct regulator_bulk_data *supplies;
	struct gpio_desc *reset_gpio;
	/* K49 (#509): vendor declara mi,esd-err-irq-gpio TLMM 168 y
	 * mi,esd-err-irq-gpio-second TLMM 169 (flags 0x2004); el port no los
	 * tocaba y quedaban en el estado del bootloader mientras el panel TDDI
	 * asevera sus lineas al arrancar su parte tactil. Aqui se registran
	 * como esd-err-gpios (s266) y se arma una irq por linea. */
	struct gpio_descs *esd_gpios;
};

struct o82_panel_desc {
	const struct drm_display_mode *modes;
	unsigned int num_modes;

	unsigned int width_mm;
	unsigned int height_mm;
	unsigned int bpc;
	unsigned int lanes;

	unsigned long mode_flags;
	enum mipi_dsi_pixel_format format;

	bool is_dual_dsi;

	/* Timing-select registers written at the end of the init sequence
	 * (vendor commands 105/106). The array below is the 120 Hz one.
	 */
	u8 freq_reg_b3;
	u8 freq_reg_b2;
};

static const struct regulator_bulk_data o82_supplies[] = {
	{ .supply = "vddil8b" },	/* 1.9 V IO, pmxr2230 L8B */
	{ .supply = "vsp" },		/* +5.8 V, GPIO regulator (TLMM 74) */
	{ .supply = "vsn" },		/* -5.8 V, GPIO regulator (TLMM 75) */
};

/*
 * Vendor init sequence, "qcom,mdss-dsi-on-command" of the default timing
 * (120 Hz), verbatim (998 bytes, 108 commands). The last 4 commands
 * (timing-select 0xb3/0xb2, sleep out 0x11 + 120 ms, display on 0x29)
 * are emitted separately in o82_prepare() so the timing registers can be
 * parameterized; this array carries the common commands 1..104 (964 bytes).
 */
static const u8 o82_init_cmds[] = {
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xff, 0x27, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0xfb, 0x01, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0xd0, 0x31, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xd1, 0x20,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xd2, 0x38, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0xde, 0x43, 0x39, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x02, 0xdf, 0x02, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x03, 0x08, 0x24,
	0x0a, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x03, 0x0c, 0x1e, 0x00, 0x39,
	0x00, 0x00, 0x40, 0x00, 0x00, 0x03, 0x10, 0x1e, 0x00, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x03, 0x80, 0x57, 0x09, 0x39, 0x00, 0x00, 0x40, 0x00,
	0x00, 0x03, 0x84, 0x2d, 0x00, 0x39, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03,
	0x88, 0x2d, 0x00, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xff, 0x23,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xfb, 0x01, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0x00, 0x80, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0x01, 0x84, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x05, 0xf6,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x06, 0x02, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0x11, 0x03, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0x12, 0x2a, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x15, 0xd0,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x16, 0x16, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0x29, 0x0a, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0x30, 0xff, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x31, 0xfe,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x32, 0xfd, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0x33, 0xfb, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0x34, 0xf8, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x35, 0xf5,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x36, 0xf3, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0x37, 0xf2, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0x38, 0xf2, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x39, 0xf2,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x3a, 0xef, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0x3b, 0xec, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0x3d, 0xe9, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x3f, 0xe5,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x40, 0xe5, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0x41, 0xe5, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0x2a, 0x13, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x45, 0xff,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x46, 0xf4, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0x47, 0xe7, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0x48, 0xda, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x49, 0xcd,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x4a, 0xc0, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0x4b, 0xb3, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0x4c, 0xb1, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x4d, 0xb1,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x4e, 0xb1, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0x4f, 0x95, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0x50, 0x79, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x51, 0x5c,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x52, 0x58, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0x53, 0x58, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0x54, 0x58, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xff, 0x23,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xfb, 0x01, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0x58, 0xff, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0x59, 0xfb, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x5a, 0xf7,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x5b, 0xf3, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0x5c, 0xef, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0x5d, 0xe3, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x5e, 0xd9,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x5f, 0xd7, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0x60, 0xd7, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0x61, 0xd7, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x62, 0xc9,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x63, 0xb9, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0x64, 0xac, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0x65, 0xaa, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x66, 0xaa,
	0x39, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x67, 0xaa, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0xff, 0x25, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0xfb, 0x01, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x0f, 0x20,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xff, 0x2a, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0xfb, 0x01, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0xc4, 0x82, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xff, 0x26,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xfb, 0x01, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0x3b, 0x06, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0x4b, 0x06, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xff, 0x22,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xfb, 0x01, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0xc4, 0x06, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0xff, 0xf0, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xfb, 0x01,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xfa, 0x05, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0x76, 0x16, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0xff, 0x20, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xfb, 0x01,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x30, 0x00, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x02, 0xff, 0x10, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
	0x02, 0xfb, 0x01, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x03, 0x51, 0x0f,
	0xff, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x53, 0x24, 0x39, 0x00,
	0x00, 0x40, 0x00, 0x00, 0x07, 0x3b, 0x03, 0x94, 0x1a, 0x04, 0x04, 0x00,
	0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x90, 0x03, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x11, 0x91, 0xab, 0x28, 0x00, 0x18, 0xd2, 0x00, 0x02,
	0xb2, 0x02, 0x9f, 0x00, 0x0b, 0x04, 0x86, 0x02, 0xdc, 0x39, 0x00, 0x00,
	0x40, 0x00, 0x00, 0x03, 0x92, 0x10, 0xf0, 0x39, 0x00, 0x00, 0x40, 0x00,
	0x00, 0x02, 0x9d, 0x01,
};

static inline struct o82_panel *to_o82_panel(struct drm_panel *panel)
{
	return container_of(panel, struct o82_panel, panel);
}

/*
 * o82_send_panel_cmds() - walk a vendor-format command blob and emit each
 * command to both DSI links (vendor broadcast mode).
 *
 * The vendor DT encodes command arrays as a concatenation of records with
 * a 7-byte header:
 *
 *   [0]     data type: 0x39 = DCS long write, 0x15 = DCS short write with
 *           1 parameter, 0x05 = DCS short write, 0x06 = DCS read
 *   [1..3]  per-command vendor flags (LP/HS hint for the vendor parser,
 *           not representable in the mainline API; the whole init runs in
 *           low-power mode on the vendor panel, which we get through
 *           MIPI_DSI_MODE_LPM, so they are ignored here)
 *   [4]     delay in ms to wait after the command
 *   [5..6]  payload length, big endian
 *   [7..]   payload (payload[0] is the DCS register)
 *
 * All commands of this panel use data types 0x39/0x15/0x05, which map to
 * plain DCS writes; mipi_dsi_dcs_write_buffer() picks short/long writes
 * from the length. Data type 0x06 (reads) is not used by the init/off
 * sequences and is rejected explicitly.
 */
static int o82_send_panel_cmds(struct o82_panel *ctx, const u8 *cmds, size_t size)
{
	struct mipi_dsi_multi_context dsi_ctx = { .dsi = ctx->dsi[0] };
	size_t off = 0;
	size_t n = 0;

	while (off < size) {
		u8 dt = cmds[off];
		u16 len;

		pr_err("UKE-K47c: cmd#%zu off=%zu dt=%02x\n", n, off, dt);

		if (size - off < 7) {
			dev_err(&ctx->dsi[0]->dev, "truncated command header at %zu\n", off);
			return -EINVAL;
		}

		len = (cmds[off + 5] << 8) | cmds[off + 6];
		pr_info("UKE-P82: cmd[%zu] off=%zu dt=0x%02x len=%u\n", n++, off, dt, len);
		if (size - off - 7 < len) {
			dev_err(&ctx->dsi[0]->dev, "truncated command payload at %zu\n", off);
			return -EINVAL;
		}

		switch (dt) {
		case 0x39:		/* DCS long write */
		case 0x15:		/* DCS short write, 1 param */
		case 0x05:		/* DCS short write, 0 params */
			mipi_dsi_dual_dcs_write_buffer_multi(&dsi_ctx,
							     ctx->dsi[0], ctx->dsi[1],
							     &cmds[off + 7], len);
			break;
		default:
			dev_err(&ctx->dsi[0]->dev, "unsupported data type 0x%02x at %zu\n",
				dt, off);
			return -EINVAL;
		}

		if (dsi_ctx.accum_err)
			return dsi_ctx.accum_err;

		if (cmds[off + 4])
			msleep(cmds[off + 4]);

		off += 7 + len;
	}

	return dsi_ctx.accum_err;
}

/* Vendor reset sequence: level 0 10 ms -> level 1 3 ms -> level 0 3 ms ->
 * level 1 15 ms. The gpio is described active-low, so "asserted" (physical
 * level 0) is gpiod value 1.
 */
static void o82_reset(struct o82_panel *ctx)
{
	uke_poke("K48-rst-A");	/* fisico: ASSERT (gpiod1=LOW) */
	gpiod_set_value_cansleep(ctx->reset_gpio, 1);
	uke_poke("K48-w1-done");
	usleep_range(10000, 10500);
	uke_poke("K48-rst-A-ok");	/* 10ms */
	pr_info("UKE-P82: rst: assert(10ms) OK\n");
	gpiod_set_value_cansleep(ctx->reset_gpio, 0);
	uke_poke("K48-w2-done");
	usleep_range(3000, 3500);
	uke_poke("K48-rst-R-ok");	/* fisico: RELEASE 3ms */
	pr_info("UKE-P82: rst: release(3ms) OK\n");
	gpiod_set_value_cansleep(ctx->reset_gpio, 1);
	uke_poke("K48-w3-done");
	usleep_range(3000, 3500);
	uke_poke("K48-rst-A2-ok");	/* re-ASSERT 3ms */
	pr_info("UKE-P82: rst: assert2(3ms) OK\n");
	gpiod_set_value_cansleep(ctx->reset_gpio, 0);
	uke_poke("K48-w4-done");
	/* L38 (13-oct): vuelve a los 15 ms del VENDOR. El 100 ms era el
	 * "discriminador temporal" de la ronda r7, un valor inventado para
	 * medir que nunca debió quedarse en el camino del fallo. La secuencia
	 * del DT de Android es (0,10),(1,3),(0,3),(1,15) y el vendor la ejecuta
	 * con usleep_range_state(15*1000, .., TASK_UNINTERRUPTIBLE); nuestro
	 * ultimo release se habia ido a 100 ms, y el SoC muere justo ANTES de
	 * este sleep. Ademas el log de abajo moria: decia "15ms" durmiendo
	 * 100. Ver NOTAS-OMARCHY 13-oct 20:10.
	 */
	usleep_range(15000, 15100);
	uke_poke("K48-rst-R2-ok");	/* RELEASE final 15ms (vendor) */
	pr_info("UKE-P82: rst: release2(15ms) OK — reset COMPLETO (L38: 100->15ms)\n");
}

/* Vendor power-on order: the three supply entries in order (vddil8b, vsp,
 * vsn), each with its qcom,supply-enable-load of 300 mA (rpmh rails need
 * it to leave LPM) and post-on-sleep of 2 ms.
 */
static int o82_power_on(struct o82_panel *ctx)
{
	uke_poke("K47-pan-pwron");
	uke_poke("K47-pan-pwr");
	unsigned int i;
	int ret;

	pr_info("UKE-P82: power_on: inicio (%zu supplies)\n", ARRAY_SIZE(o82_supplies));
	for (i = 0; i < ARRAY_SIZE(o82_supplies); i++) {
		pr_info("UKE-P82: power_on[%u]: %s enable-load\n", i, o82_supplies[i].supply);
		ret = regulator_set_load(ctx->supplies[i].consumer,
					 O82_SUPPLY_ENABLE_LOAD_UA);
		if (ret < 0)
			goto err;
		ret = regulator_enable(ctx->supplies[i].consumer);
		if (ret < 0) {
			regulator_set_load(ctx->supplies[i].consumer, 0);
			goto err;
		}
		usleep_range(2000, 2500);
		pr_info("UKE-P82: power_on[%u]: %s ENABLED\n", i, o82_supplies[i].supply);
	}

	pr_info("UKE-P82: power_on: TODAS OK\n");
	uke_poke("K47-pwr-OK");
	uke_poke("K47-pan-pwron-ok");
	return 0;

err:
	while (i--) {
		regulator_disable(ctx->supplies[i].consumer);
		regulator_set_load(ctx->supplies[i].consumer, 0);
	}
	return ret;
}

static int o82_prepare(struct drm_panel *panel)
{
	uke_poke("K47-pan-prep");
	struct o82_panel *ctx = to_o82_panel(panel);
	const struct o82_panel_desc *desc = ctx->desc;
	struct mipi_dsi_multi_context dsi_ctx = { .dsi = ctx->dsi[0] };
	int ret;

	pr_info("UKE-P82: prepare: INICIO\n");
	ret = o82_power_on(ctx);
	if (ret < 0) {
		pr_info("UKE-P82: prepare: power_on FALLO %d\n", ret);
		return ret;
	}
	pr_info("UKE-P82: prepare: power OK\n");

	uke_poke("K47-pre-rst");
	o82_reset(ctx);
	uke_poke("K47-pre-rstOK");
	pr_info("UKE-P82: prepare: reset OK\n");

	uke_poke("K47-pre-init");
	pr_info("UKE-P82: prepare: init cmds INICIO\n");
	ret = o82_send_panel_cmds(ctx, o82_init_cmds, ARRAY_SIZE(o82_init_cmds));
	pr_info("UKE-P82: prepare: init cmds rc=%d\n", ret);
	if (ret < 0)
		goto err;

	/*
	 * L37 (13-oct): enviar las Picture Parameter Set (PPS) de DSC.
	 *
	 * El panel o82 declara drm_dsc_config (DSC 1.1, 10bpc->8bpp, slice
	 * 800x24, 2 slices) pero hasta ahora NUNCA recibia sus PPS: los 104
	 * comandos de o82_init_cmds[] no contienen ninguna cabecera 0x0A 0x00
	 * (Set-PPS), y en drivers/gpu/drm/msm/dsi/ no hay ninguna ruta que las
	 * envie (grep 'pps' = 0). Un panel DSC al que no le mandas las PPS no
	 * puede decodificar la trama.
	 *
	 * El vendor CAF las genera en runtime (sde_dsc_create_pps_buf_cmd) y las
	 * envia como DCS Set-PPS desde dsi_display_enable -> dsi_panel_update_pps.
	 * En mainline el camino equivalente es exactamente el que usa el panel
	 * nt36532e que SI funciona en sm8550-mainline (sheng):
	 *   drm_dsc_pps_payload_pack() + mipi_dsi_picture_parameter_set_multi()
	 * (panel-novatek-nt36532e.c:201-202). Mismo packer, misma via DCS.
	 *
	 * La config DSC de mainline coincide campo a campo con la del vendor o82
	 * (verificado sobre el .ko), asi que la UNICA diferencia era el envio.
	 */
	{
		struct drm_dsc_picture_parameter_set pps;

		uke_poke("L37-pps-pack");
		drm_dsc_pps_payload_pack(&pps, &ctx->dsc);
		uke_poke("L37-pps-send");
		/* L40 (14-oct, rev DSI): la PPS debe llegar a LOS DOS links. El
		 * vendor la emite en broadcast (dsi_panel_tx_cmd_set() con
		 * qcom,mdss-dsi-panel-broadcast-mode); mipi_dsi_picture_parameter_set_multi()
		 * solo transmite por ctx->dsi (drm_mipi_dsi.c:1556), asi que hay que
		 * llamarla una vez por link. NOTA: pic_width/pic_height del PPS salen
		 * del template (0 a prepare-time; el host los rellena en modeset) —
		 * el vendor los lleva del modo; pendiente verificar byte a byte.
		 */
		dsi_ctx.dsi = ctx->dsi[0];
		mipi_dsi_picture_parameter_set_multi(&dsi_ctx, &pps);
		dsi_ctx.dsi = ctx->dsi[1];
		mipi_dsi_picture_parameter_set_multi(&dsi_ctx, &pps);
		dsi_ctx.dsi = ctx->dsi[0];
		pr_info("UKE-L37: PPS enviada: ver=%u%u bpc=%u bpp=%u slices=%u slice=%ux%u pred=%u rgb=%u\n",
			(ctx->dsc.dsc_version_major), (ctx->dsc.dsc_version_minor),
			ctx->dsc.bits_per_component, ctx->dsc.bits_per_pixel >> 4,
			ctx->dsc.slice_count, ctx->dsc.slice_width, ctx->dsc.slice_height,
			ctx->dsc.block_pred_enable, ctx->dsc.convert_rgb);
		uke_poke("L37-pps-done");
		if (dsi_ctx.accum_err) {
			pr_info("UKE-L37: PPS envio fallo rc=%d\n", dsi_ctx.accum_err);
			goto err;
		}
	}

	u8 freq_sel[2];

	/* Timing-select tail (vendor commands 105/106 of the init sequence).
	 * The frequency registers differ per timing:
	 *   120 Hz: b3 = 0x40, b2 = 0x91
	 *   144 Hz: b3 = 0x00, b2 = 0x00
	 *    90 Hz: b3 = 0x80, b2 = 0x00
	 * TODO: implement runtime timing switch (vendor does it through
	 * mi,mdss-dsi-timing-switch-video-command in HS mode, plus a change
	 * of h-front-porch). For now the panel is always programmed for its
	 * default timing (120 Hz).
	 */
	freq_sel[0] = 0xb3;
	freq_sel[1] = desc->freq_reg_b3;
	mipi_dsi_dual_dcs_write_buffer_multi(&dsi_ctx, ctx->dsi[0], ctx->dsi[1],
					     freq_sel, ARRAY_SIZE(freq_sel));
	freq_sel[0] = 0xb2;
	freq_sel[1] = desc->freq_reg_b2;
	mipi_dsi_dual_dcs_write_buffer_multi(&dsi_ctx, ctx->dsi[0], ctx->dsi[1],
					     freq_sel, ARRAY_SIZE(freq_sel));
	pr_info("UKE-P82: prepare: freq_sel OK (err=%d)\n", dsi_ctx.accum_err);

	mipi_dsi_dual_dcs_write_buffer_multi(&dsi_ctx, ctx->dsi[0], ctx->dsi[1],
					     (u8[]){ 0x11 }, 1);	/* sleep out */
	mipi_dsi_msleep(&dsi_ctx, 120);	/* vendor delay 0x78 after sleep out */
	pr_info("UKE-P82: prepare: sleep-out OK (err=%d)\n", dsi_ctx.accum_err);
	mipi_dsi_dual_dcs_write_buffer_multi(&dsi_ctx, ctx->dsi[0], ctx->dsi[1],
					     (u8[]){ 0x29 }, 1);	/* display on */
	pr_info("UKE-P82: prepare: display-on ENVIADO (err=%d)\n", dsi_ctx.accum_err);

	if (dsi_ctx.accum_err) {
		ret = dsi_ctx.accum_err;
		goto err;
	}

	/* Sin backlight_enable aqui: el core DRM enciende el KTZ externo en
	 * drm_panel_enable(), tras el modeset (equivale al
	 * "delay_until_first_frame" del vendor). */
	pr_info("UKE-P82: prepare: COMPLETO\n");

	return 0;

err:
	gpiod_set_value_cansleep(ctx->reset_gpio, 1);
	regulator_bulk_disable(ARRAY_SIZE(o82_supplies), ctx->supplies);
	return ret;
}

static int o82_unprepare(struct drm_panel *panel)
{
	uke_poke("K47-pan-unprep");
	struct o82_panel *ctx = to_o82_panel(panel);
	int ret, i;

	/* Sin backlight_disable aqui: el core DRM ya apago el KTZ en
	 * drm_panel_disable(), antes de llamar a este unprepare. */

	/* Vendor off command, en BROADCAST a los dos links (como el init):
	 * 0x28 + 20 ms, 0x10 + 100 ms, 0x4f + 0 ms. Si solo se apaga el link
	 * maestro, la otra mitad se queda encendida y en estado indeterminado
	 * para el siguiente prepare (que empieza con un reset).
	 */
	ret = 0;
	for (i = 0; i < ARRAY_SIZE(ctx->dsi) && !ret; i++)
		ret = mipi_dsi_dcs_set_display_off(ctx->dsi[i]);
	if (!ret)
		msleep(20);
	for (i = 0; i < ARRAY_SIZE(ctx->dsi) && !ret; i++)
		ret = mipi_dsi_dcs_enter_sleep_mode(ctx->dsi[i]);
	if (!ret)
		msleep(100);
	for (i = 0; i < ARRAY_SIZE(ctx->dsi) && !ret; i++) {
		uke_poke("K47-pan-dcs");
		ret = mipi_dsi_dcs_write_buffer(ctx->dsi[i],
						(u8[]){ 0x4f }, 1);
	}
	if (ret < 0)
		dev_err(&ctx->dsi[0]->dev, "panel off sequence failed: %d\n", ret);

	gpiod_set_value_cansleep(ctx->reset_gpio, 1);

	regulator_bulk_disable(ARRAY_SIZE(o82_supplies), ctx->supplies);

	return 0;
}

static int o82_get_modes(struct drm_panel *panel,
			 struct drm_connector *connector)
{
	uke_poke("K47-pan-modes");
	pr_info("UKE-P82: get_modes: entrada\n");
	struct o82_panel *ctx = to_o82_panel(panel);
	const struct o82_panel_desc *desc = ctx->desc;
	unsigned int i;

	for (i = 0; i < desc->num_modes; i++) {
		const struct drm_display_mode *m = &desc->modes[i];
		struct drm_display_mode *mode;

		mode = drm_mode_duplicate(connector->dev, m);
		if (!mode) {
			dev_err(panel->dev, "failed to add mode %ux%u@%u\n",
				m->hdisplay, m->vdisplay, drm_mode_vrefresh(m));
			return -ENOMEM;
		}

		mode->type = DRM_MODE_TYPE_DRIVER;
		if (i == 0)
			mode->type |= DRM_MODE_TYPE_PREFERRED;

		drm_mode_set_name(mode);
		drm_mode_probed_add(connector, mode);
	}

	connector->display_info.width_mm = desc->width_mm;
	connector->display_info.height_mm = desc->height_mm;
	connector->display_info.bpc = desc->bpc;

	return desc->num_modes;
}

static const struct drm_panel_funcs o82_panel_funcs = {
	.prepare = o82_prepare,
	.unprepare = o82_unprepare,
	.get_modes = o82_get_modes,
};

/* Backlight externo: ver cabecera (KTZ8866 por I2C). El core DRM lo maneja
 * via ctx->panel.backlight (drm_panel_of_backlight en el probe). */

/*
 * Full-panel modes (both links, 3200x2136). Per-link timings from the
 * vendor DT: hactive 1600, hfp 113 (120 Hz) / 18 (144) / 304 (90),
 * hbp 16, hsync 16; vactive 2136, vfp 26, vbp 146, vsync 2. The two
 * links are bonded and msm SPLITS the mode per link, so the horizontal
 * values here must be the vendor's FULL-BOTH-LINKS ones: hfp/hsync/hbp
 * are doubled (2x113, 2x16, 2x16) to survive that split, and htotal is
 * therefore 2x1745 = 3490 at 120 Hz.
 *
 * TODO: 144/90 Hz need the runtime timing switch (see o82_prepare());
 * only the 120 Hz mode is exposed until that exists.
 */
static const struct drm_display_mode o82_modes[] = {
	{
		/* clock = 3490 * 2310 * 120 / 1000 = 967428 kHz */
		.clock = (3200 + 226 + 32 + 32) * (2136 + 26 + 146 + 2) * 120 / 1000,
		.hdisplay = 3200,
		.hsync_start = 3200 + 226,
		.hsync_end = 3200 + 226 + 32,
		.htotal = 3200 + 226 + 32 + 32,
		.vdisplay = 2136,
		.vsync_start = 2136 + 26,
		.vsync_end = 2136 + 26 + 2,
		.vtotal = 2136 + 26 + 146 + 2,
	},
	{
		/* hfp 18 x2; clock = 3300 * 2310 * 144 / 1000 = 1097712 kHz */
		.clock = (3200 + 36 + 32 + 32) * (2136 + 26 + 146 + 2) * 144 / 1000,
		.hdisplay = 3200,
		.hsync_start = 3200 + 36,
		.hsync_end = 3200 + 36 + 32,
		.htotal = 3200 + 36 + 32 + 32,
		.vdisplay = 2136,
		.vsync_start = 2136 + 26,
		.vsync_end = 2136 + 26 + 2,
		.vtotal = 2136 + 26 + 146 + 2,
	},
	{
		/* hfp 304 x2; clock = 3872 * 2310 * 90 / 1000 = 804989 kHz */
		.clock = (3200 + 608 + 32 + 32) * (2136 + 26 + 146 + 2) * 90 / 1000,
		.hdisplay = 3200,
		.hsync_start = 3200 + 608,
		.hsync_end = 3200 + 608 + 32,
		.htotal = 3200 + 608 + 32 + 32,
		.vdisplay = 2136,
		.vsync_start = 2136 + 26,
		.vsync_end = 2136 + 26 + 2,
		.vtotal = 2136 + 26 + 146 + 2,
	},
};

/*
 * DSC 1.1, SCR rev 0 (pre-SCR), 10 bpc -> 8 bpp, slices 800x24, block
 * prediction enabled, 1 slice per packet (the only value the msm DSI
 * driver supports). slice_count is per interface: 1600 px per link /
 * 800 px per slice = 2. The msm DSI host overwrites pic_width/pic_height
 * and the RC parameters from this template at modeset time.
 *
 * No picture parameter set is sent to the panel: the vendor init sequence
 * contains none (the panel IC is preconfigured; DSC encoding lives in the
 * DPU/DSI encoders).
 */
static const struct drm_dsc_config o82_dsc_config = {
	.dsc_version_major = 1,
	.dsc_version_minor = 1,
	.slice_width = 800,
	.slice_height = 24,
	.slice_count = 2,
	.bits_per_component = 10,
	.bits_per_pixel = 8 << 4,
	.block_pred_enable = true,
	.convert_rgb = true,
};

static const struct o82_panel_desc o82_4202_0b_desc = {
	.modes = o82_modes,
	/* Solo 120 Hz: o82_prepare() escribe SIEMPRE los registros de frecuencia
	 * de 120 Hz (b3 = 0x40, b2 = 0x91), asi que exponer 144/90 daria un modo
	 * con el panel en otro timing (imagen corrupta). El vendor cambia de
	 * timing con mi,mdss-dsi-timing-switch-video-command en HS + cambio de
	 * h-front-porch: trabajo pendiente.
	 */
	.num_modes = 1,
	.width_mm = 238,
	.height_mm = 163,
	.bpc = 10,
	.lanes = 4,
	/* Vendor: video mode, non_burst_sync_event, LP tx for commands,
	 * EOT append (default in msm).
	 */
	/* K48-A (#507): lp11-init del vendor — sin CLOCK_NON_CONTINUOUS,
	 * dsi_ctrl_enable (dsi_host.c:909-916) fuerza bitclk HS CONTINUO en el
	 * carril de clock desde power_on, ANTES de rieles y reset; el vendor
	 * tiene LP11 durante toda la secuencia de reset. */
	.mode_flags = MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_LPM |
		      MIPI_DSI_CLOCK_NON_CONTINUOUS,
	.format = MIPI_DSI_FMT_RGB888,
	.is_dual_dsi = true,
	.freq_reg_b3 = 0x40,
	.freq_reg_b2 = 0x91,
};

static irqreturn_t o82_esd_irq_thread(int irq, void *data)
{
	struct o82_panel *ctx = data;
	int j, v = -1;

	if (ctx->esd_gpios)
		for (j = 0; j < ctx->esd_gpios->ndescs; j++)
			if (gpiod_to_irq(ctx->esd_gpios->desc[j]) == irq) {
				v = gpiod_get_value_cansleep(ctx->esd_gpios->desc[j]);
				break;
			}
	uke_poke("K49-esd-irq");
	pr_err("UKE-K49: ESD irq %d! gpio idx %d val=%d\n", irq, j, v);
	return IRQ_HANDLED;
}

static int o82_probe(struct mipi_dsi_device *dsi)
{
	uke_poke("K47-pan-probe");
	struct mipi_dsi_device_info dsi_info = { "dsi-secondary", 0, NULL };
	struct device *dev = &dsi->dev;
	const struct o82_panel_desc *desc;
	struct o82_panel *ctx;
	struct device_node *dsi1;
	struct mipi_dsi_host *dsi1_host;
	int num_dsi = 1;
	int ret, i;

	ctx = devm_drm_panel_alloc(dev, struct o82_panel, panel,
				   &o82_panel_funcs, DRM_MODE_CONNECTOR_DSI);
	if (IS_ERR(ctx))
		return PTR_ERR(ctx);

	ret = devm_regulator_bulk_get_const(dev, ARRAY_SIZE(o82_supplies),
					    o82_supplies, &ctx->supplies);
	if (ret < 0)
		return dev_err_probe(dev, ret, "failed to get regulators\n");

	ctx->reset_gpio = devm_gpiod_get(dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(ctx->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(ctx->reset_gpio),
				     "failed to get reset gpio\n");

	/* K49 (#509): registrar las lineas ESD del TDDI como el vendor y
	 * absorber sus aseveraciones con una irq con dueno. El mux/pull lo
	 * pone el estado pinctrl uke-esd-active (s266) al probe. */
	ctx->esd_gpios = devm_gpiod_get_array_optional(dev, "esd-err", GPIOD_IN);
	if (IS_ERR(ctx->esd_gpios)) {
		dev_err_probe(dev, PTR_ERR(ctx->esd_gpios),
			      "UKE-K49: esd-err-gpios presente pero fallo\n");
		ctx->esd_gpios = NULL;
	} else if (ctx->esd_gpios && ctx->esd_gpios->ndescs > 0) {
		for (i = 0; i < ctx->esd_gpios->ndescs && i < 4; i++) {
			int esd_irq = gpiod_to_irq(ctx->esd_gpios->desc[i]);

			if (esd_irq < 0) {
				dev_err(dev, "UKE-K49: esd gpio %d sin irq (%d)\n",
					i, esd_irq);
				continue;
			}
			ret = devm_request_threaded_irq(dev, esd_irq, NULL,
							o82_esd_irq_thread,
							IRQF_ONESHOT |
							IRQF_TRIGGER_FALLING |
							IRQF_TRIGGER_RISING,
							"uke-o82-esd", ctx);
			if (ret)
				dev_err(dev, "UKE-K49: esd irq %d NO armada (%d)\n",
					esd_irq, ret);
			else
				dev_err(dev, "UKE-K49: esd gpio %d -> irq %d ARMADA val=%d\n",
					i, esd_irq,
					gpiod_get_value_cansleep(ctx->esd_gpios->desc[i]));
		}
		uke_poke("K49-esd-armado");
	} else {
		dev_err(dev, "UKE-K49: sin esd-err-gpios en DT (port viejo)\n");
	}

	desc = of_device_get_match_data(dev);
	if (!desc)
		return -ENODEV;
	ctx->desc = desc;
	ctx->dsc = o82_dsc_config;

	if (desc->is_dual_dsi) {
		num_dsi = 2;

		dsi1 = of_graph_get_remote_node(dev->of_node, 1, -1);
		if (!dsi1) {
			dev_err(dev, "cannot find secondary DSI host node\n");
			return -ENODEV;
		}

		dsi1_host = of_find_mipi_dsi_host_by_node(dsi1);
		of_node_put(dsi1);
		if (!dsi1_host)
			return dev_err_probe(dev, -EPROBE_DEFER,
					     "cannot get secondary DSI host\n");

		ctx->dsi[1] = devm_mipi_dsi_device_register_full(dev, dsi1_host,
								 &dsi_info);
		if (IS_ERR(ctx->dsi[1])) {
			dev_err(dev, "cannot create secondary DSI device\n");
			return PTR_ERR(ctx->dsi[1]);
		}

		mipi_dsi_set_drvdata(ctx->dsi[1], ctx);
	}

	ctx->dsi[0] = dsi;
	mipi_dsi_set_drvdata(dsi, ctx);

	ctx->panel.prepare_prev_first = true;

	/* Backlight externo (KTZ8866): el DT trae 'backlight = <&ktz_bl_0>'.
	 * El core DRM lo enciende/apaga en enable/disable (tras el modeset).
	 *
	 * L39b (13-oct) — DEGRADADO A AVISO, no a fallo. Motivo medido el mismo dia:
	 *
	 *   mipi-dsi ae94000.dsi.0: deferred probe pending:
	 *       panel-xiaomi-o82-dualdsi: failed to find external backlight
	 *
	 * y la causa real NO es el phandle: /proc/device-tree lo resuelve bien
	 * (backlight = <0x703> -> .../i2c@a80000/ktz8866@11). Es que ESTE PORT NO
	 * TIENE I2C: /sys/class/i2c-adapter/ esta VACIO, asi que el driver del KTZ
	 * nunca se une al bus, nunca hay backlight_device, y el panel entero se
	 * queda sin probar -> no aparece card1 -> el enlace DSI no se puede medir.
	 *
	 * Con el fallo duro, el port no puede ni INTENTAR el enlace hasta que haya
	 * I2C, y el I2C es un proyecto aparte (agente creado 13-oct). Failar aqui
	 * convertia " todavia no sabemos si la PHY funciona" en "no hay panel", que
	 * es peor: perdia la medicion.
	 *
	 * El flash que dejaria la pantalla a oscuras si no hay I2C sigue siendo
	 * cierto, pero AHORA es el kernel quien avisa, no un probe silencioso. Cuando
	 * I2C funcione, esto se puede volver a endurecer.
	 */
	ret = drm_panel_of_backlight(&ctx->panel);
	if (ret < 0 || !ctx->panel.backlight)
		dev_warn(dev, "sin backlight externo (KTZ8866): ret=%d bl=%p. "
			     "Este port no tiene I2C (i2c-adapter vacio), asi que el "
			     "chip no puede probe-ar. El panel sigue; la luz la "
			     "deja el splash del ABL.\n",
			ret, ctx->panel.backlight);

	drm_panel_add(&ctx->panel);

	for (i = 0; i < num_dsi; i++) {
		ctx->dsi[i]->lanes = desc->lanes;
		ctx->dsi[i]->format = desc->format;
		ctx->dsi[i]->mode_flags = desc->mode_flags;
		ctx->dsi[i]->dsc = &ctx->dsc;

		uke_poke("K47-pan-probe-ok");
		ret = devm_mipi_dsi_attach(dev, ctx->dsi[i]);
		uke_poke("K47-pan-probe-attach-ok");
		if (ret < 0) {
			drm_panel_remove(&ctx->panel);
			return dev_err_probe(dev, ret,
					     "cannot attach to DSI host %d\n", i);
		}
	}

	return 0;
}

static void o82_remove(struct mipi_dsi_device *dsi)
{
	struct o82_panel *ctx = mipi_dsi_get_drvdata(dsi);

	drm_panel_remove(&ctx->panel);
}

static const struct of_device_id o82_of_match[] = {
	{ .compatible = "xiaomi,uke-o82-4202-0b", .data = &o82_4202_0b_desc },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, o82_of_match);

static struct mipi_dsi_driver o82_driver = {
	.probe = o82_probe,
	.remove = o82_remove,
	.driver = {
		.name = "panel-xiaomi-o82-dualdsi",
		.of_match_table = o82_of_match,
	},
};
module_mipi_dsi_driver(o82_driver);

MODULE_AUTHOR("Ubuntu-Uke project");
MODULE_DESCRIPTION("DRM panel driver for the Xiaomi O82 42_02_0b dual-DSI DSC LCD panel (Xiaomi Pad 7)");
MODULE_LICENSE("GPL");
