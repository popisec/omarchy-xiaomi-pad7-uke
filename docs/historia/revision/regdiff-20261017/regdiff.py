#!/usr/bin/env python3
"""regdiff-20261017: vendor (Android, 120 Hz, pantalla OK) vs nuestro (codigo k52-L16-tree / medido L70-L74).

Solo lectura. Uso:  python3 -I docs/historia/revision/regdiff-20261017/regdiff.py <dir vendor-harvest-20261017b>  > docs/historia/revision/regdiff-20261017/regdiff-out.txt
Emula drm_dsc_* (drm_dsc_helper.c), dsi_populate_dsc_params (+ quirk L73), dsi_timing_setup,
dsi_ctrl_enable, drm_mode_to_intf_timing_params + dpu_hw_intf_setup_timing_engine y
dpu_hw_dsc_config_1_2/_thresh_1_2, todo copiado del arbol k52-L16-tree.
"""
import math
import os
import re
import sys

V = sys.argv[1] if len(sys.argv) > 1 else "build/android/vendor-harvest-20261017b"


def cdiv(a, b):
    return -(-a // b)


def load_hex(path, start_marker=None):
    regs = {}
    on = start_marker is None
    with open(path) as f:
        for ln in f:
            if start_marker is not None:
                if ln.startswith("== "):
                    on = ln.startswith(start_marker)
                    continue
            if not on:
                continue
            m = re.match(r"0x([0-9a-fA-F]+):\s+((?:[0-9a-fA-F]{8}\s*)+)$", ln.strip())
            if not m:
                continue
            base = int(m.group(1), 16)
            for i, w in enumerate(m.group(2).split()):
                regs[base + 4 * i] = int(w, 16)
    return regs


def bits(v, hi, lo):
    return (v >> lo) & ((1 << (hi - lo + 1)) - 1)


# ----------------------------------------------------------------------------- DSC (drm_dsc_helper.c)
PRE_SCR_8BPP_10BPC = dict(
    initial_xmit_delay=512, first_line_bpg_offset=12, initial_offset=6144,
    flatness_min_qp=7, flatness_max_qp=16, rc_quant_incr_limit0=15, rc_quant_incr_limit1=15,
    rc=[(0, 4, 2), (4, 8, 0), (5, 9, 0), (5, 10, -2), (7, 11, -4), (7, 11, -6), (7, 11, -8),
        (7, 12, -8), (7, 13, -8), (7, 14, -10), (9, 15, -10), (9, 16, -12), (9, 17, -12),
        (11, 17, -12), (17, 19, -12)])
RC_BUF_THRESH = [896, 1792, 2688, 3584, 4480, 5376, 6272, 6720, 7168, 7616, 7744, 7872, 8000, 8064]


def compute_rc(d):
    gpl = cdiv(d["slice_width"], 3)
    d["slice_chunk_size"] = cdiv(d["slice_width"] * d["bits_per_pixel"], 8 * 16)
    nemb = 3 * (d["mux_word_size"] + (4 * d["bits_per_component"] + 4) - 2)  # convert_rgb
    slice_bits = 8 * d["slice_chunk_size"] * d["slice_height"]
    while nemb > 0 and (slice_bits - nemb) % d["mux_word_size"]:
        nemb -= 1
    if gpl < d["initial_scale_value"] - 8:
        d["initial_scale_value"] = gpl + 8
    d["scale_decrement_interval"] = gpl // (d["initial_scale_value"] - 8) if d["initial_scale_value"] > 8 else 4095
    d["final_offset"] = d["rc_model_size"] - (d["initial_xmit_delay"] * d["bits_per_pixel"] + 8) // 16 + nemb
    final_scale = (d["rc_model_size"] * 8) // (d["rc_model_size"] - d["final_offset"])
    d["nfl_bpg_offset"] = cdiv(d["first_line_bpg_offset"] << 11, d["slice_height"] - 1)
    groups_total = gpl * d["slice_height"]
    d["slice_bpg_offset"] = cdiv((d["rc_model_size"] - d["initial_offset"] + nemb) << 11, groups_total)
    if final_scale > 9:
        d["scale_increment_interval"] = (d["final_offset"] * (1 << 11)) // (
            (d["nfl_bpg_offset"] + d["slice_bpg_offset"]) * (final_scale - 9))
    else:
        d["scale_increment_interval"] = 0
    rbs_min = (d["rc_model_size"] - d["initial_offset"] + cdiv(d["initial_xmit_delay"] * d["bits_per_pixel"], 16)
               + gpl * d["first_line_bpg_offset"])
    hrd = cdiv(rbs_min * 16, d["bits_per_pixel"])
    d["rc_bits"] = (hrd * d["bits_per_pixel"]) // 16
    d["initial_dec_delay"] = hrd - d["initial_xmit_delay"]
    d["_groups_per_line"] = gpl
    d["_num_extra_mux_bits"] = nemb
    d["_final_scale"] = final_scale


def our_dsc_config(l73=True, pic_width=3200):
    # panel-xiaomi-o82-dualdsi.c o82_dsc_config + dsi_timing_setup (pic_width = mode->hdisplay)
    d = dict(dsc_version_major=1, dsc_version_minor=1, slice_width=800, slice_height=24, slice_count=2,
             bits_per_component=10, bits_per_pixel=8 << 4, block_pred_enable=1, convert_rgb=1,
             pic_width=pic_width, pic_height=2136, simple_422=0, vbr_enable=0, native_422=0, native_420=0,
             second_line_bpg_offset=0, nsl_bpg_offset=0, second_line_offset_adj=0)
    # dsi_populate_dsc_params
    d["rc_model_size"] = 8192
    d["rc_edge_factor"] = 6
    d["rc_tgt_offset_high"] = 3
    d["rc_tgt_offset_low"] = 3
    d["mux_word_size"] = 48
    d["rc_buf_thresh"] = [x >> 6 for x in RC_BUF_THRESH]
    p = PRE_SCR_8BPP_10BPC
    for k in ("initial_xmit_delay", "first_line_bpg_offset", "initial_offset", "flatness_min_qp",
              "flatness_max_qp", "rc_quant_incr_limit0", "rc_quant_incr_limit1"):
        d[k] = p[k]
    d["rc"] = [list(x) for x in p["rc"]]
    d["initial_scale_value"] = 8 * d["rc_model_size"] // (d["rc_model_size"] - d["initial_offset"])
    d["line_buf_depth"] = d["bits_per_component"] + 1
    compute_rc(d)
    if l73:  # L73-FIX1 dsi_host.c:2095-2100
        d["first_line_bpg_offset"] = 13
        d["rc"][0][1] = 8
        compute_rc(d)
    return d


def pps_pack(d):
    b = bytearray(128)
    b[0] = d["dsc_version_minor"] | d["dsc_version_major"] << 4
    b[3] = d["line_buf_depth"] | d["bits_per_component"] << 4
    b[4] = (((d["bits_per_pixel"] & 0x300) >> 8) | d["vbr_enable"] << 2 | d["simple_422"] << 3
            | d["convert_rgb"] << 4 | d["block_pred_enable"] << 5)
    b[5] = d["bits_per_pixel"] & 0xff

    def be16(o, v):
        b[o] = (v >> 8) & 0xff
        b[o + 1] = v & 0xff
    be16(6, d["pic_height"]); be16(8, d["pic_width"]); be16(10, d["slice_height"])
    be16(12, d["slice_width"]); be16(14, d["slice_chunk_size"])
    b[16] = (d["initial_xmit_delay"] & 0x300) >> 8
    b[17] = d["initial_xmit_delay"] & 0xff
    be16(18, d["initial_dec_delay"])
    b[21] = d["initial_scale_value"]
    be16(22, d["scale_increment_interval"])
    b[24] = (d["scale_decrement_interval"] & 0xf00) >> 8
    b[25] = d["scale_decrement_interval"] & 0xff
    b[27] = d["first_line_bpg_offset"]
    be16(28, d["nfl_bpg_offset"]); be16(30, d["slice_bpg_offset"])
    be16(32, d["initial_offset"]); be16(34, d["final_offset"])
    b[36] = d["flatness_min_qp"]; b[37] = d["flatness_max_qp"]
    be16(38, d["rc_model_size"])
    b[40] = 6
    b[41] = d["rc_quant_incr_limit0"]; b[42] = d["rc_quant_incr_limit1"]
    b[43] = 3 | 3 << 4
    for i in range(14):
        b[44 + i] = d["rc_buf_thresh"][i]
    for i, (mn, mx, off) in enumerate(d["rc"]):
        be16(58 + 2 * i, (mn << 11) | (mx << 6) | (off & 0x3f))
    b[88] = d["native_422"] | d["native_420"] << 1
    b[89] = d["second_line_bpg_offset"]
    be16(90, d["nsl_bpg_offset"]); be16(92, d["second_line_offset_adj"])
    return bytes(b)


PPS_FIELDS = [
    (0, 1, "dsc_version (maj<<4|min)"), (1, 1, "pps_identifier"), (2, 1, "reservado"),
    (3, 1, "bpc<<4 | line_buf_depth"), (4, 1, "flags: block_pred(5) convert_rgb(4) 422(3) vbr(2) bpp_hi"),
    (5, 1, "bits_per_pixel_low (bpp*16)"), (6, 2, "pic_height"), (8, 2, "pic_width"),
    (10, 2, "slice_height"), (12, 2, "slice_width"), (14, 2, "chunk_size"),
    (16, 2, "initial_xmit_delay"), (18, 2, "initial_dec_delay"), (20, 1, "reservado"),
    (21, 1, "initial_scale_value"), (22, 2, "scale_increment_interval"),
    (24, 2, "scale_decrement_interval"), (26, 1, "reservado"), (27, 1, "first_line_bpg_offset"),
    (28, 2, "nfl_bpg_offset"), (30, 2, "slice_bpg_offset"), (32, 2, "initial_offset"),
    (34, 2, "final_offset"), (36, 1, "flatness_min_qp"), (37, 1, "flatness_max_qp"),
    (38, 2, "rc_model_size"), (40, 1, "rc_edge_factor"), (41, 1, "rc_quant_incr_limit0"),
    (42, 1, "rc_quant_incr_limit1"), (43, 1, "rc_tgt_offset hi<<4|lo"),
] + [(44 + i, 1, "rc_buf_thresh[%d]" % i) for i in range(14)] + \
    [(58 + 2 * i, 2, "rc_range[%d] (minqp<<11|maxqp<<6|ofs)" % i) for i in range(15)] + \
    [(88, 1, "native_422|420"), (89, 1, "second_line_bpg_offset"), (90, 2, "nsl_bpg_offset"),
     (92, 2, "second_line_offset_adj"), (94, 34, "reservado (0)")]


def fmt_field(b, off, n):
    if n == 1:
        return "0x%02x (%d)" % (b[off], b[off])
    if n == 2:
        v = b[off] << 8 | b[off + 1]
        return "0x%04x (%d)" % (v, v)
    return "todo-cero" if not any(b[off:off + n]) else b[off:off + n].hex()


def rc_range_decode(v):
    off = v & 0x3f
    if off & 0x20:
        off -= 64
    return "min %d max %d ofs %d" % (v >> 11, (v >> 6) & 0x1f, off)


# ----------------------------------------------------------------------------- DSC encoder regs (dpu_hw_dsc_1_2.c)
def dsc_enc_regs(d, mode_split=True, mode_video=True, num_dsc=2):
    r = {}
    nslice = d["slice_count"]  # sin MULTIPLEX
    cmn = (1 if mode_split else 0) | ((nslice & 3) << 7)
    # dpu_encoder_dsc_initial_line_calc
    this_frame_slices = d["pic_width"] // d["slice_width"]
    enc_ip_w = this_frame_slices * d["slice_width"] // num_dsc
    soft = enc_ip_w // d["slice_width"]
    ssm = 84 if d["bits_per_component"] < 10 else 92
    tot = ssm * 3 + d["initial_xmit_delay"] + 47 + (ssm * 3 if soft > 1 else 0)
    initial_lines = cdiv(tot, d["slice_width"])
    max_addr = (2400 // nslice) // 2 - 1  # DPU_DSC_NATIVE_42x_EN en palawan_dsc
    r[0x00] = (initial_lines & 0xff) | ((1 << 9) if mode_video else 0) | (max_addr << 18)
    r[0x30] = ((d["dsc_version_minor"] & 0xf) << 28 | d["bits_per_pixel"] << 10 | d["block_pred_enable"] << 20
               | d["convert_rgb"] << 4 | (d["line_buf_depth"] & 0xf) << 6 | (d["bits_per_component"] & 0xf))
    r[0x34] = (d["pic_width"] & 0xffff) | (d["pic_height"] & 0xffff) << 16
    r[0x38] = (d["slice_width"] & 0xffff) | (d["slice_height"] & 0xffff) << 16
    r[0x3c] = d["slice_chunk_size"] & 0xffff
    r[0x40] = (d["initial_xmit_delay"] & 0xffff) | (d["initial_dec_delay"] & 0xffff) << 16
    r[0x44] = d["initial_scale_value"] & 0x3f
    r[0x48] = (d["scale_increment_interval"] & 0xffff) | (d["scale_decrement_interval"] & 0x7ff) << 16
    r[0x4c] = (d["first_line_bpg_offset"] & 0x1f) | (d["second_line_bpg_offset"] & 0x1f) << 5
    r[0x50] = (d["nfl_bpg_offset"] & 0xffff) | (d["slice_bpg_offset"] & 0xffff) << 16
    r[0x54] = (d["initial_offset"] & 0xffff) | (d["final_offset"] & 0xffff) << 16
    r[0x58] = (d["nsl_bpg_offset"] & 0xffff) | (d["second_line_offset_adj"] & 0xffff) << 16
    det = 2 << (d["bits_per_component"] - 8)
    r[0x5c] = (d["flatness_min_qp"] & 0x1f) | (d["flatness_max_qp"] & 0x1f) << 5 | (det & 0xff) << 10
    r[0x60] = d["rc_model_size"] & 0xffff
    r[0x64] = (6 & 0xf) | (d["rc_quant_incr_limit0"] & 0x1f) << 8 | (d["rc_quant_incr_limit1"] & 0x1f) << 13 \
        | 3 << 20 | 3 << 24
    t = d["rc_buf_thresh"]
    r[0x68] = t[0] | t[1] << 8 | t[2] << 16 | t[3] << 24
    r[0x6c] = t[4] | t[5] << 8 | t[6] << 16 | t[7] << 24
    r[0x70] = t[8] | t[9] << 8 | t[10] << 16 | t[11] << 24
    r[0x74] = t[12] | t[13] << 8
    rc = d["rc"]
    for grp in range(3):
        mn = mx = bo = 0
        for j in range(5):
            a, b_, c = rc[grp * 5 + j]
            mn |= a << (5 * j)
            mx |= b_ << (5 * j)
            bo |= (c & 0x3f) << (6 * j)
        r[0x78 + 4 * grp] = mn
        r[0x84 + 4 * grp] = mx
        r[0x90 + 4 * grp] = bo
    ctl_cfg = 1 | ((1 << 12) if mode_split else 0) | (0 if mode_video else (1 << 17))
    return r, cmn, ctl_cfg, initial_lines


DSC_ENC_NAMES = {0x00: "ENC_DF_CTRL", 0x04: "ENC_GENERAL_STATUS", 0x08: "ENC_HSLICE_STATUS",
                 0x0c: "ENC_OUT_STATUS", 0x10: "ENC_INT_STAT", 0x14: "ENC_INT_CLR", 0x18: "ENC_INT_MASK",
                 0x30: "DSC_MAIN_CONF", 0x34: "DSC_PICTURE_SIZE", 0x38: "DSC_SLICE_SIZE",
                 0x3c: "DSC_MISC_SIZE", 0x40: "DSC_HRD_DELAYS", 0x44: "DSC_RC_SCALE",
                 0x48: "DSC_RC_SCALE_INC_DEC", 0x4c: "DSC_RC_OFFSETS_1", 0x50: "DSC_RC_OFFSETS_2",
                 0x54: "DSC_RC_OFFSETS_3", 0x58: "DSC_RC_OFFSETS_4", 0x5c: "DSC_FLATNESS_QP",
                 0x60: "DSC_RC_MODEL_SIZE", 0x64: "DSC_RC_CONFIG", 0x68: "DSC_RC_BUF_THRESH_0",
                 0x6c: "DSC_RC_BUF_THRESH_1", 0x70: "DSC_RC_BUF_THRESH_2", 0x74: "DSC_RC_BUF_THRESH_3",
                 0x78: "DSC_RC_MIN_QP_0", 0x7c: "DSC_RC_MIN_QP_1", 0x80: "DSC_RC_MIN_QP_2",
                 0x84: "DSC_RC_MAX_QP_0", 0x88: "DSC_RC_MAX_QP_1", 0x8c: "DSC_RC_MAX_QP_2",
                 0x90: "DSC_RC_RANGE_BPG_OFFSETS_0", 0x94: "DSC_RC_RANGE_BPG_OFFSETS_1",
                 0x98: "DSC_RC_RANGE_BPG_OFFSETS_2"}


def decode_dsc_enc(o, v):
    if o == 0x00:
        return "initial_lines=%d video=%d bit12=%d bits10-17=0x%x ob_max_addr=%d" % (
            v & 0xff, bits(v, 9, 9), bits(v, 12, 12), bits(v, 17, 10), v >> 18)
    if o == 0x30:
        return "minor=%d bpp16=%d blk_pred=%d lbd=%d rgb=%d bpc=%d" % (
            v >> 28, bits(v, 19, 10), bits(v, 20, 20), bits(v, 9, 6), bits(v, 4, 4), v & 0xf)
    if o in (0x34, 0x38):
        return "w=%d h=%d" % (v & 0xffff, v >> 16)
    if o == 0x40:
        return "xmit=%d dec=%d" % (v & 0xffff, v >> 16)
    if o == 0x48:
        return "inc=%d dec=%d" % (v & 0xffff, v >> 16)
    if o == 0x4c:
        return "flb=%d slb=%d" % (v & 0x1f, bits(v, 9, 5))
    if o == 0x50:
        return "nfl=%d slice_bpg=%d" % (v & 0xffff, v >> 16)
    if o == 0x54:
        return "init_ofs=%d final_ofs=%d" % (v & 0xffff, v >> 16)
    if o == 0x5c:
        return "flat min %d max %d det %d" % (v & 0x1f, bits(v, 9, 5), bits(v, 17, 10))
    if o in (0x78, 0x7c, 0x80, 0x84, 0x88, 0x8c):
        return "/".join(str(bits(v, 5 * j + 4, 5 * j)) for j in range(5))
    if o in (0x90, 0x94, 0x98):
        out = []
        for j in range(5):
            x = bits(v, 6 * j + 5, 6 * j)
            out.append(str(x - 64 if x & 0x20 else x))
        return "/".join(out)
    return ""


# ----------------------------------------------------------------------------- INTF (dpu_hw_intf.c)
MODE_LINK = dict(hdisplay=1600, hfp=113, hsync=16, hbp=16, vdisplay=2136, vfp=26, vsync=2, vbp=146)


def intf_regs(width, widebus, dce_bytes=1600, compression=True):
    p = MODE_LINK
    hp = p["hsync"] + p["hbp"] + width + p["hfp"]
    vp = p["vsync"] + p["vbp"] + p["vdisplay"] + p["vfp"]
    dvs = (p["vsync"] + p["vbp"]) * hp
    dve = (vp - p["vfp"]) * hp - 1
    hsx = p["hbp"] + p["hsync"]
    hex_ = hp - p["hfp"] - 1
    cfg2 = 0
    if widebus:
        cfg2 |= 1
    if compression:
        dw = cdiv(dce_bytes, 6) if widebus else cdiv(dce_bytes, 3)
        cfg2 |= 1 << 12
    else:
        dw = width
    if not (compression and not widebus):
        cfg2 |= 1 << 4
    r = {0x08: (hp << 16) | p["hsync"], 0x0c: vp * hp, 0x14: p["vsync"] * hp, 0x1c: dvs, 0x24: dve,
         0x3c: (hex_ << 16) | hsx, 0x40: 0, 0x2c: 0, 0x34: 0, 0x50: 0, 0x60: cfg2,
         0x64: ((hsx + dw - 1) << 16) | hsx, 0x90: 0x213f, 0xa8: 3}
    return r


INTF_NAMES = {0x000: "TIMING_ENGINE_EN", 0x004: "INTF_CONFIG", 0x008: "HSYNC_CTL", 0x00c: "VSYNC_PERIOD_F0",
              0x014: "VSYNC_PULSE_WIDTH_F0", 0x01c: "DISPLAY_V_START_F0", 0x024: "DISPLAY_V_END_F0",
              0x02c: "ACTIVE_V_START_F0", 0x034: "ACTIVE_V_END_F0", 0x03c: "DISPLAY_HCTL", 0x040: "ACTIVE_HCTL",
              0x044: "BORDER_COLOR", 0x048: "UNDERFLOW_COLOR", 0x050: "POLARITY_CTL", 0x060: "INTF_CONFIG2",
              0x064: "DISPLAY_DATA_HCTL", 0x068: "ACTIVE_DATA_HCTL", 0x084: "DSI_CMD_MODE_TRIGGER_EN",
              0x090: "PANEL_FORMAT", 0x0a8: "FRAME_LINE_COUNT_EN", 0x0ac: "FRAME_COUNT", 0x0b0: "LINE_COUNT",
              0x170: "PROG_FETCH_START", 0x180: "MISR_CTRL", 0x184: "MISR_SIGNATURE",
              0x230: "WD_TIMER_0_CTL", 0x234: "WD_TIMER_0_CTL2", 0x238: "WD_TIMER_0_LOAD_VALUE",
              0x25c: "INTF_MUX", 0x26c: "INTF_STATUS"}


# ----------------------------------------------------------------------------- DSI ctrl
# offset FISICO del volcado = offset mainline (dsi.xml.h, base 6G) + 4 (DSI_6G_REG_SHIFT, dsi_cfg.c)
ML = {0x00: "CTRL", 0x04: "STATUS0", 0x08: "FIFO_STATUS", 0x0c: "VID_CFG0", 0x1c: "VID_CFG1",
      0x20: "ACTIVE_H", 0x24: "ACTIVE_V", 0x28: "TOTAL", 0x2c: "ACTIVE_HSYNC", 0x30: "ACTIVE_VSYNC_HPOS",
      0x34: "ACTIVE_VSYNC_VPOS", 0x38: "CMD_DMA_CTRL", 0x3c: "CMD_CFG0", 0x40: "CMD_CFG1", 0x44: "DMA_BASE",
      0x48: "DMA_LEN", 0x54: "CMD_MDP_STREAM0_CTRL", 0x58: "CMD_MDP_STREAM0_TOTAL", 0x64: "ACK_ERR_STATUS",
      0x68: "RDBK(0)", 0x6c: "RDBK(1)", 0x70: "RDBK(2)", 0x74: "RDBK(3)", 0x80: "TRIG_CTRL", 0x8c: "TRIG_DMA",
      0xa0: "(UKE) MISR_VIDEO_CTRL", 0xa4: "LANE_STATUS", 0xa8: "LANE_CTRL", 0xac: "LANE_SWAP_CTRL",
      0xb0: "DLN0_PHY_ERR", 0xb4: "LP_TIMER_CTRL", 0xb8: "HS_TIMER_CTRL", 0xbc: "TIMEOUT_STATUS",
      0xc0: "CLKOUT_TIMING_CTRL", 0xc8: "EOT_PACKET_CTRL", 0x108: "ERR_INT_MASK0", 0x10c: "INTR_CTRL",
      0x114: "RESET", 0x118: "CLK_CTRL", 0x11c: "CLK_STATUS", 0x128: "PHY_RESET",
      0x13c: "(UKE) MISR_VIDEO_DATA", 0x158: "TEST_PATTERN_GEN_CTRL", 0x160: "TPG_VIDEO_INIT_VAL",
      0x17c: "T_CLK_PRE_EXTEND", 0x198: "TPG_MAIN_CONTROL", 0x19c: "TPG_MAIN_CONTROL2", 0x1a0: "TPG_VIDEO_CONFIG",
      0x1b4: "CMD_MODE_MDP_CTRL2", 0x1b8: "CMD_MODE_MDP_STREAM2_CTRL", 0x1d0: "RDBK_DATA_CTRL",
      0x1e0: "(UKE) FLUSH", 0x1f0: "VERSION", 0x29c: "VIDEO_COMPRESSION_MODE_CTRL",
      0x2a4: "COMMAND_COMPRESSION_MODE_CTRL", 0x2a8: "COMMAND_COMPRESSION_MODE_CTRL2", 0x2d4: "CPHY_MODE_CTRL"}
# nombres CAF (dsi_ctrl_reg.h, de memoria) para huecos del XML mainline; solo orientativos
CAF = {0x000: "DSI_HW_VERSION", 0x014: "VIDEO_MODE_SYNC_DATATYPE", 0x018: "VIDEO_MODE_PIXEL_DATATYPE",
       0x01c: "VIDEO_MODE_BLANKING_DATATYPE", 0x04c: "DMA_CMD_LENGTH", 0x050: "DMA_FIFO_CTRL",
       0x054: "DMA_NULL_PACKET_DATA", 0x07c: "RDBK_DATATYPE0", 0x080: "RDBK_DATATYPE1", 0x090: "CMD_MODE_DMA_SW_TRIGGER",
       0x0c8: "EOT_PACKET (bytes EoTp 08 0f 0f 01)", 0x134: "MISR_CMD_MDP0_32BIT", 0x138: "MISR_CMD_MDP1_32BIT",
       0x140: "MISR_VIDEO_32BIT", 0x144: "LANE_MISR_CTRL", 0x148: "LANE0_MISR", 0x14c: "LANE1_MISR",
       0x150: "LANE2_MISR", 0x154: "LANE3_MISR", 0x1c8: "MISR_CMD_MDP2_32BIT", 0x1cc: "VBIF_CTRL",
       0x1e4: "DSI_TIMING_FLUSH", 0x1e8: "DSI_TIMING_DB_MODE", 0x200: "DYNAMIC_REFRESH_CTRL",
       0x2a4: "VIDEO_COMPRESSION_MODE_CTRL2", 0x2b8: "READ_BACK_DISABLE_STATUS(?)", 0x2bc: "DESKEW_CTRL(?)",
       0x310: "LOGICAL_LANE_SWAP_CTRL(?)", 0x330: "SPLIT_LINK(?)"}


def dsi_decode(phys, v):
    m = phys - 4
    n = ML.get(m)
    if n == "CTRL":
        return ("ENABLE=%d VID_MODE_EN=%d CMD_MODE_EN=%d LANES=0x%x CLK_EN=%d ECC=%d CRC=%d" %
                (v & 1, bits(v, 1, 1), bits(v, 2, 2), bits(v, 7, 4), bits(v, 8, 8), bits(v, 20, 20), bits(v, 24, 24)))
    if n == "STATUS0":
        return "CMD_ENG_BUSY=%d DMA_BUSY=%d MDP_BUSY=%d VIDEO_BUSY=%d DSI_BUSY=%d bit13=%d bit14=%d" % (
            v & 1, bits(v, 1, 1), bits(v, 2, 2), bits(v, 3, 3), bits(v, 4, 4), bits(v, 13, 13), bits(v, 14, 14))
    if n == "FIFO_STATUS":
        s = "VID_MDP_OVF=%d VID_MDP_UNF=%d CMD_MDP_UNF=%d DMA_UNF=%d bit4=%d LP_FIFO_EMPTY=%d" % (
            v & 1, bits(v, 3, 3), bits(v, 7, 7), bits(v, 10, 10), bits(v, 4, 4), bits(v, 12, 12))
        ln = []
        for L in range(4):
            nib = bits(v, 19 + 4 * L, 16 + 4 * L)
            ln.append("L%d:%s%s%s%s" % (L, "E" if nib & 1 else "-", "F" if nib & 2 else "-",
                                        "O" if nib & 4 else "-", "U" if nib & 8 else "-"))
        return s + " HS[" + " ".join(ln) + "]"
    if n == "VID_CFG0":
        fmts = {0: "RGB565", 1: "RGB666", 2: "RGB666_LOOSE", 3: "RGB888", 4: "RGB101010"}
        tm = {0: "NON_BURST_SYNC_PULSE", 1: "NON_BURST_SYNC_EVENT", 2: "BURST"}
        return ("VC=%d DST_FORMAT=%d(%s) TRAFFIC=%s BLLP_STOP=%d EOF_BLLP_STOP=%d HSA/HBP/HFP_STOP=%d/%d/%d "
                "DATABUS_WIDEN=%d PULSE_HSA_HE=%d" % (
                    v & 3, bits(v, 6, 4), fmts.get(bits(v, 6, 4), "?"), tm.get(bits(v, 9, 8), "?"),
                    bits(v, 12, 12), bits(v, 15, 15), bits(v, 16, 16), bits(v, 20, 20), bits(v, 24, 24),
                    bits(v, 25, 25), bits(v, 28, 28)))
    if n in ("ACTIVE_H", "ACTIVE_V", "ACTIVE_HSYNC", "ACTIVE_VSYNC_HPOS", "ACTIVE_VSYNC_VPOS"):
        return "start=%d end=%d (len %d)" % (v & 0xffff, v >> 16, (v >> 16) - (v & 0xffff))
    if n == "TOTAL":
        return "H_TOTAL=%d(+1=%d) V_TOTAL=%d(+1=%d)" % (v & 0xffff, (v & 0xffff) + 1, v >> 16, (v >> 16) + 1)
    if n == "CMD_DMA_CTRL":
        return "BROADCAST_EN=%d BROADCAST_MASTER(b30)=%d FROM_FB=%d LOW_POWER=%d" % (
            bits(v, 31, 31), bits(v, 30, 30), bits(v, 28, 28), bits(v, 26, 26))
    if n == "TRIG_CTRL":
        return "DMA_TRIG=%d MDP_TRIG=%d STREAM=%d BLOCK_DMA_WITHIN_FRAME=%d TE=%d" % (
            v & 7, bits(v, 6, 4), bits(v, 9, 8), bits(v, 12, 12), bits(v, 31, 31))
    if n == "LANE_STATUS":
        return "STOP[D0-3,CLK]=%s ULPS_NOT=%s DLN0_DIR=%d" % (bin(v & 0x1f), bin(bits(v, 12, 8)), bits(v, 16, 16))
    if n == "LANE_CTRL":
        return "HS_REQ_SEL_PHY=%d CLKLN_HS_FORCE_REQUEST=%d" % (bits(v, 24, 24), bits(v, 28, 28))
    if n == "LANE_SWAP_CTRL":
        return "DLN_SWAP_SEL=%d" % (v & 7)
    if n == "LP_TIMER_CTRL":
        return "LP_RX_TO=0x%x BTA_TO=0x%x" % (v & 0xffff, v >> 16)
    if n == "HS_TIMER_CTRL":
        return "HS_TX_TO=%d RES=%d STOP_EN=%d" % (v & 0xffff, bits(v, 19, 16), bits(v, 28, 28))
    if n == "CLKOUT_TIMING_CTRL":
        return "T_CLK_PRE=0x%x T_CLK_POST=0x%x" % (v & 0x3f, bits(v, 13, 8))
    if n == "EOT_PACKET_CTRL":
        return "TX_EOT_APPEND=%d RX_EOT_IGNORE=%d" % (v & 1, bits(v, 4, 4))
    if n == "INTR_CTRL":
        return "masks: DMA=%d MDP=%d VIDEO=%d BTA=%d ERROR=%d | status: DMA=%d MDP=%d VIDEO=%d BTA=%d ERR=%d" % (
            bits(v, 1, 1), bits(v, 9, 9), bits(v, 17, 17), bits(v, 21, 21), bits(v, 25, 25),
            v & 1, bits(v, 8, 8), bits(v, 16, 16), bits(v, 20, 20), bits(v, 24, 24))
    if n == "CLK_CTRL":
        return "AHBS=%d AHBM=%d PCLK=%d DSICLK=%d BYTE=%d ESC=%d FORCE_DYN_AHBM=%d" % (
            v & 1, bits(v, 1, 1), bits(v, 2, 2), bits(v, 3, 3), bits(v, 4, 4), bits(v, 5, 5), bits(v, 9, 9))
    if n == "VIDEO_COMPRESSION_MODE_CTRL":
        return "EN=%d EOL_BYTE_NUM=%d PKT_PER_LINE(log2)=%d DATATYPE=0x%x WC=%d" % (
            v & 1, bits(v, 5, 4), bits(v, 7, 6), bits(v, 13, 8), v >> 16)
    if n == "COMMAND_COMPRESSION_MODE_CTRL":
        return "S0_DT=0x%x S1_DT=0x%x (reset; no se usa en video)" % (bits(v, 13, 8), bits(v, 29, 24))
    if n == "TEST_PATTERN_GEN_CTRL":
        return "EN=%d CMD_DMA_TPG_EN=%d TPG_DMA_FIFO_MODE=%d" % (v & 1, bits(v, 1, 1), bits(v, 2, 2))
    if phys == 0:
        return "major=%d minor=%d step=%d" % (v >> 28, bits(v, 27, 16), v & 0xffff)
    return ""


# Nuestro lado, por variante. Clave = offset mainline. (valor, cita). None = no lo escribe.
H = "dsi_host.c"
OURS_CODE = {
    0x00: ("0x000001f3", 0x1f3, H + ":945-969 + :1256 (dsi_op_mode_config)"),
    0x0c: ("L70 0x02009130 / L71-L74 0x00009130", (0x02009130, 0x00009130),
           H + ":863-881; formato RGB888 de panel-xiaomi-o82-dualdsi.c:814; widebus :841-852"),
    0x1c: ("0x00000000", 0, H + ":885"),
    0x20: ("L70 0x01cb0020 / L71-L74 0x02360020", (0x01cb0020, 0x02360020), H + ":1092-1131"),
    0x24: ("0x08ec0094", 0x08ec0094, H + ":1132"),
    0x28: ("L70 0x0905023b / L71-L74 0x090502a6", (0x0905023b, 0x090502a6), H + ":1135"),
    0x2c: ("0x00100000", 0x00100000, H + ":1139"),
    0x30: ("0x00000000", 0, H + ":1142"),
    0x34: ("0x00020000", 0x00020000, H + ":1143"),
    0x38: ("0x14000000 (LP) / 0x10000000 (HS); nunca BROADCAST", 0x10000000, H + ":912, :1296"),
    0x80: ("0x80001004", 0x80001004, H + ":916-925 (BLOCK_DMA_WITHIN_FRAME por 6G>=v1.2)"),
    0xa0: ("L74: 0x00010100 / <=L73: no escrito", 0x10100, H + ":1165"),
    0xa8: ("no escrito (CLOCK_NON_CONTINUOUS en panel :812-813)", None, H + ":959-965"),
    0xac: ("0 (dlane_swap por DT)", 0, H + ":954"),
    0xb4: ("no escrito", None, H + ":1158 comentario"),
    0xb8: ("L74: 0x0004bb80 / <=L73: no escrito", 0x4bb80, H + ":1164"),
    0xc0: ("L74 calc 0x00001a23 / L75 0x00000f20", (0x1a23, 0x0f20), H + ":927-929 (+ dsi_phy_7nm.c:1034-1035 L75)"),
    0xc8: ("0x00000001", 1, H + ":937-940"),
    0x108: ("0x13ff3fe0", 0x13ff3fe0, H + ":943"),
    0x118: ("0x0000023f", 0x23f, H + ":947 (DSI_CLK_CTRL_ENABLE_CLKS :120-124)"),
    0x17c: ("0 salvo clk_pre_inc_by_2", 0, H + ":931-935"),
    0x1e0: ("L74: 1 (eco 0)", 1, H + ":1166"),
    0x29c: ("0x03200b51 (calculado, no medido)", 0x03200b51, H + ":976-1034"),
    0x2d4: ("no escrito (cphy_mode=0)", 0, H + ":971-972"),
}
MEASURED = {
    0x20: "L70 0x01cb0020; L71/L73 0x02360020 (ledger #649/#650/#651)",
    0x24: "L71/L73 0x08ec0094 (#650)",
    0x28: "L70 0x0905023b; L71/L73 0x090502a6 (#650/#651)",
    0x08: "L70/L73/L74 0xdddd1011; L74 timeout 0xdddd1019 (#649/#652)",
    0x04: "L74 timeout 0x00004000 (#652)",
    0xa0: "L74 rd 0x00010100 (#652)",
    0xb8: "L74 rd 0x0004bb80 (#652)",
    0x1e0: "L74 rd 0x0 (#652)",
}


def main():
    out = []
    P = out.append
    d0 = load_hex(os.path.join(V, "full-dsi0-ctrl-reg.txt"))
    d1 = load_hex(os.path.join(V, "full-dsi1-ctrl-reg.txt"))
    P("## A. DSI ctrl vendor (full-dsi{0,1}-ctrl-reg.txt), offset fisico = mainline+4")
    P("| fis | mainline | nombre | dsi0 | dsi1 | decodificado (dsi0) | nuestro (codigo) | nuestro (medido) | igual? |")
    P("|---|---|---|---|---|---|---|---|---|")
    offs = sorted(set(k for k, v in d0.items() if v) | set(k for k, v in d1.items() if v)
                  | set(m + 4 for m in OURS_CODE) | set(m + 4 for m in MEASURED))
    for phys in offs:
        if phys >= 0x1000:
            continue
        m = phys - 4
        name = ML.get(m) or ("CAF:" + CAF[phys] if phys in CAF else "?")
        v0 = d0.get(phys, 0)
        v1 = d1.get(phys, 0)
        dec = dsi_decode(phys, v0)
        oc = OURS_CODE.get(m)
        ocs = "%s [%s]" % (oc[0], oc[2]) if oc else "-"
        meas = MEASURED.get(m, "-")
        eq = "-"
        if oc and oc[1] is not None:
            vals = oc[1] if isinstance(oc[1], tuple) else (oc[1],)
            eq = " / ".join("SI" if x == v0 else "NO" for x in vals)
        P("| 0x%03x | %s | %s | 0x%08x | 0x%08x | %s | %s | %s | %s |" % (
            phys, ("0x%03x" % m) if m >= 0 else "-", name, v0, v1, dec, ocs, meas, eq))

    # ---- INTF
    sde = os.path.join(V, "dpu", "sde-blocks-raw-awake.txt")
    i1 = load_hex(sde, "== INTF_1 ")
    i2 = load_hex(sde, "== INTF_2 ")
    i1 = {k - 0x36000: v for k, v in i1.items()}
    i2 = {k - 0x37000: v for k, v in i2.items()}
    variants = [("L70 (wb ON, trunc 426)", intf_regs(426, True)), ("L73/L74 (wb OFF, ceil 534)", intf_regs(534, False)),
                ("propuesta (wb ON, ceil 427)", intf_regs(427, True))]
    P("\n## B. INTF_1 / INTF_2 (vendor) vs dpu_hw_intf_setup_timing_engine emulado")
    P("| off | reg | INTF_1 | INTF_2 | " + " | ".join(n for n, _ in variants) + " |")
    P("|---|---|---|---|" + "---|" * len(variants))
    for o in sorted(set(k for k, v in i1.items() if v) | set(k for k, v in i2.items() if v) | set(variants[0][1])):
        cells = []
        for n, r in variants:
            if o in r:
                cells.append("0x%08x %s" % (r[o], "==" if r[o] == i1.get(o, 0) else "!="))
            else:
                cells.append("-")
        P("| 0x%03x | %s | 0x%08x | 0x%08x | %s |" % (o, INTF_NAMES.get(o, "?"), i1.get(o, 0), i2.get(o, 0),
                                                    " | ".join(cells)))

    # ---- DSC
    ours = our_dsc_config(l73=True, pic_width=3200)
    ours_ml = our_dsc_config(l73=False, pic_width=3200)
    e0 = {k - 0x81100: v for k, v in load_hex(sde, "== DSC0_enc ").items()}
    e1 = {k - 0x81200: v for k, v in load_hex(sde, "== DSC1_enc ").items()}
    r73, cmn, ctlcfg, il = dsc_enc_regs(ours)
    r_ml, _, _, _ = dsc_enc_regs(ours_ml)
    top0 = load_hex(sde, "== DSC0_top ").get(0x81000, 0)
    c0 = {k - 0x81f00: v for k, v in load_hex(sde, "== DSC0_ctl ").items()}
    c1 = {k - 0x81f80: v for k, v in load_hex(sde, "== DSC1_ctl ").items()}
    P("\n## C. DSC_0/DSC_1 encoder (vendor) vs dpu_hw_dsc_config_1_2 emulado (L73: flb13+maxqp0=8; mainline puro)")
    P("| off | reg | DSC0 vendor | DSC1 vendor | decod. vendor | nuestro L73+ | decod. nuestro | igual? | mainline puro (<=L72) |")
    P("|---|---|---|---|---|---|---|---|---|")
    for o in sorted(set(e0) | set(r73)):
        v0 = e0.get(o, 0)
        ourv = r73.get(o)
        P("| 0x%02x | %s | 0x%08x | 0x%08x | %s | %s | %s | %s | %s |" % (
            o, DSC_ENC_NAMES.get(o, "?"), v0, e1.get(o, 0), decode_dsc_enc(o, v0),
            ("0x%08x" % ourv) if ourv is not None else "(estado)", decode_dsc_enc(o, ourv) if ourv is not None else "",
            ("SI" if ourv == v0 else "**NO**") if ourv is not None else "-",
            ("0x%08x%s" % (r_ml[o], "" if r_ml[o] == v0 else " (!=)")) if o in r_ml else "-"))
    P("\nDSC_CMN_MAIN_CNF (top 0x81000): vendor 0x%08x | nuestro 0x%08x | %s" % (top0, cmn, "SI" if top0 == cmn else "NO"))
    for nm, c, mux in (("DSC0", c0, 0), ("DSC1", c1, 1)):
        P("%s_ctl: DSC_CTL vendor 0x%x / nuestro 0x%x (PP_%d); DSC_CFG vendor 0x%08x / nuestro 0x%08x; "
          "DATA_IN_SWAP vendor 0x%08x / nuestro no escrito; DSC_CLK_CTRL vendor 0x%08x / nuestro no escrito" % (
              nm, c.get(0, 0), mux, mux, c.get(4, 0), ctlcfg, c.get(8, 0), c.get(0xc, 0)))
    P("initial_lines nuestro = %d (dpu_encoder.c:1970-1990, enc_ip_w=1600, soft_slice=2)" % il)

    # ---- PPS
    vend = None
    with open(os.path.join(V, "kprobe", "dsi-cmds-decoded.txt")) as f:
        for ln in f:
            if "dt=0xa " in ln and "len=128" in ln:
                vend = bytes(int(x, 16) for x in ln.split("len=128")[1].split())
                break
    our_link = pps_pack(our_dsc_config(True, 1600))
    our_full = pps_pack(our_dsc_config(True, 3200))
    our_ml = pps_pack(our_dsc_config(False, 1600))
    P("\n## D. PPS 128 B: vendor (dt=0x0a, ambos links identicos) vs nuestro")
    P("vendor : " + vend.hex(" "))
    P("L73+   : " + our_link.hex(" ") + "   (pic_width=1600 por link, panel :432/:623)")
    P("<=L72  : " + our_ml.hex(" "))
    P("| byte | campo | vendor | nuestro L73+ (1600) | igual? | nuestro <=L72 |")
    P("|---|---|---|---|---|---|")
    for off, n, name in PPS_FIELDS:
        vv = fmt_field(vend, off, n)
        oo = fmt_field(our_link, off, n)
        mm = fmt_field(our_ml, off, n)
        if n == 2 and name.startswith("rc_range"):
            vv += " " + rc_range_decode(vend[off] << 8 | vend[off + 1])
            oo += " " + rc_range_decode(our_link[off] << 8 | our_link[off + 1])
        same = vend[off:off + n] == our_link[off:off + n]
        P("| %d%s | %s | %s | %s | %s | %s |" % (off, ("-%d" % (off + n - 1)) if n > 1 else "", name, vv, oo,
                                               "SI" if same else "**NO**", mm))
    diffs = [i for i in range(128) if vend[i] != our_link[i]]
    P("\nBytes distintos vendor vs L73+(1600): %s" % (", ".join("[%d] %02x/%02x" % (i, vend[i], our_link[i]) for i in diffs) or "ninguno"))
    diffs_f = [i for i in range(128) if vend[i] != our_full[i]]
    P("Bytes distintos vendor vs L73+ con pic_width=3200: %s" % (", ".join("[%d]" % i for i in diffs_f) or "NINGUNO (identica)"))
    diffs_m = [i for i in range(128) if vend[i] != our_ml[i]]
    P("Bytes distintos vendor vs <=L72(1600): %s" % ", ".join("[%d] %02x/%02x" % (i, vend[i], our_ml[i]) for i in diffs_m))
    P("\nDSC config nuestro L73+: " + ", ".join("%s=%s" % (k, ours[k]) for k in (
        "slice_chunk_size", "initial_xmit_delay", "initial_dec_delay", "initial_scale_value",
        "scale_increment_interval", "scale_decrement_interval", "first_line_bpg_offset", "nfl_bpg_offset",
        "slice_bpg_offset", "initial_offset", "final_offset", "rc_bits", "_groups_per_line", "_num_extra_mux_bits",
        "_final_scale")))

    # ---- PHY espejo
    P("\n## E. PHY: 0x800-0x9ff vs 0x000-0x1ff")
    for L in (0, 1):
        ph = load_hex(os.path.join(V, "full-dsi%d-phy-reg.txt" % L))
        same = sum(1 for o in range(0, 0x200, 4) if ph.get(o) == ph.get(0x800 + o))
        diff = [o for o in range(0, 0x200, 4) if ph.get(o) != ph.get(0x800 + o)]
        P("dsi%d_phy: %d/128 palabras iguales; difieren: %s" % (L, same, ", ".join(
            "0x%03x(%08x vs %08x)" % (o, ph.get(o, 0), ph.get(0x800 + o, 0)) for o in diff[:12]) or "ninguna"))
        tc = [ph.get(o, 0) for o in range(0xb4, 0xec, 4)]
        P("dsi%d_phy TIMING_CTRL_0..13 (0x0b4..0x0e8): %s" % (L, " ".join("%02x" % x for x in tc)))
    print("\n".join(out))


if __name__ == "__main__":
    main()
