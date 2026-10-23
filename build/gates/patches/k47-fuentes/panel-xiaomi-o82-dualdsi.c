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

#include <linux/backlight.h>
#include <linux/uke-poke.h>
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_graph.h>
#include <linux/regulator/consumer.h>

#include <drm/display/drm_dsc.h>
#include <drm/drm_mipi_dsi.h>
#include <drm/drm_modes.h>
#include <drm/drm_panel.h>

#include <video/mipi_display.h>

/* Vendor: qcom,mdss-dsi-bl-min-level = <4>, bl-max-level = <0xfff> (12 bit,
 * written through DCS 0x51, "bl_ctrl_external" = no PWM).
 */
#define O82_BL_MIN_LEVEL	4
#define O82_BL_MAX_LEVEL	0xfff
/* Vendor: qcom,mdss-brightness-init-level = <0x133>. */
#define O82_BL_INIT_LEVEL	0x133
/* Vendor: qcom,supply-enable-load of the three panel supply entries. */
#define O82_SUPPLY_ENABLE_LOAD_UA	300000

struct o82_panel {
	struct drm_panel panel;
	struct mipi_dsi_device *dsi[2];
	const struct o82_panel_desc *desc;
	struct drm_dsc_config dsc;
	struct regulator_bulk_data *supplies;
	struct gpio_desc *reset_gpio;
	struct backlight_device *backlight;
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
	gpiod_set_value_cansleep(ctx->reset_gpio, 1);
	usleep_range(10000, 10500);
	pr_info("UKE-P82: rst: hi(10ms) OK\n");
	gpiod_set_value_cansleep(ctx->reset_gpio, 0);
	usleep_range(3000, 3500);
	pr_info("UKE-P82: rst: lo(3ms) OK\n");
	gpiod_set_value_cansleep(ctx->reset_gpio, 1);
	usleep_range(3000, 3500);
	pr_info("UKE-P82: rst: hi2(3ms) OK\n");
	gpiod_set_value_cansleep(ctx->reset_gpio, 0);
	usleep_range(15000, 16000);
	pr_info("UKE-P82: rst: lo2(15ms) OK — reset COMPLETO\n");
}

/* Vendor power-on order: the three supply entries in order (vddil8b, vsp,
 * vsn), each with its qcom,supply-enable-load of 300 mA (rpmh rails need
 * it to leave LPM) and post-on-sleep of 2 ms.
 */
static int o82_power_on(struct o82_panel *ctx)
{
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

	o82_reset(ctx);
	pr_info("UKE-P82: prepare: reset OK\n");

	pr_info("UKE-P82: prepare: init cmds INICIO\n");
	ret = o82_send_panel_cmds(ctx, o82_init_cmds, ARRAY_SIZE(o82_init_cmds));
	pr_info("UKE-P82: prepare: init cmds rc=%d\n", ret);
	if (ret < 0)
		goto err;

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

	pr_info("UKE-P82: prepare: backlight_enable...\n");
	backlight_enable(ctx->backlight);
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

	backlight_disable(ctx->backlight);

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

/* Brightness goes through DCS 0x51 (12 bits, MSB first) on both links;
 * there is no PWM ("bl_ctrl_external"). The vendor sets control register
 * 0x53 = 0x24 in the init sequence, so no extra control write is needed.
 */
static int o82_bl_update_status(struct backlight_device *bl)
{
	uke_poke("K47-pan-bl");
	struct o82_panel *ctx = bl_get_data(bl);
	int level;
	u16 brightness;
	int ret = 0, i;

	level = clamp(backlight_get_brightness(bl),
		      (int)O82_BL_MIN_LEVEL, (int)O82_BL_MAX_LEVEL);
	brightness = level;

	for (i = 0; i < 2 && !ret; i++) {
		if (!ctx->dsi[i])
			break;
		ret = mipi_dsi_dcs_set_display_brightness_large(ctx->dsi[i],
								brightness);
	}

	return ret;
}

static const struct backlight_ops o82_bl_ops = {
	.options = BL_CORE_SUSPENDRESUME,
	.update_status = o82_bl_update_status,
};

static struct backlight_device *
o82_create_backlight(struct o82_panel *ctx)
{
	struct device *dev = &ctx->dsi[0]->dev;
	const struct backlight_properties props = {
		.type = BACKLIGHT_RAW,
		.brightness = O82_BL_INIT_LEVEL,
		.max_brightness = O82_BL_MAX_LEVEL,
		.scale = BACKLIGHT_SCALE_NON_LINEAR,
	};

	return devm_backlight_device_register(dev, dev_name(dev), dev, ctx,
					      &o82_bl_ops, &props);
}

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
	.mode_flags = MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_LPM,
	.format = MIPI_DSI_FMT_RGB888,
	.is_dual_dsi = true,
	.freq_reg_b3 = 0x40,
	.freq_reg_b2 = 0x91,
};

static int o82_probe(struct mipi_dsi_device *dsi)
{
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

	ctx->backlight = o82_create_backlight(ctx);
	if (IS_ERR(ctx->backlight))
		return dev_err_probe(dev, PTR_ERR(ctx->backlight),
				     "failed to create backlight\n");

	drm_panel_add(&ctx->panel);

	for (i = 0; i < num_dsi; i++) {
		ctx->dsi[i]->lanes = desc->lanes;
		ctx->dsi[i]->format = desc->format;
		ctx->dsi[i]->mode_flags = desc->mode_flags;
		ctx->dsi[i]->dsc = &ctx->dsc;

		ret = devm_mipi_dsi_attach(dev, ctx->dsi[i]);
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
