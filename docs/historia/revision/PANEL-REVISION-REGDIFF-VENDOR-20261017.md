# PANEL-REVISION-REGDIFF-VENDOR — registro a registro: vendor (Android, 120 Hz, imagen OK) vs nuestro (código / medido)

> 17-oct-2026. Solo lectura. Sin adb/fastboot/ssh, sin flasheos, sin commits, sin compilar.
> **Vendor** = `build/android/vendor-harvest-20261017b/` (V:): `full-dsi{0,1}-ctrl-reg.txt`, `full-dsi{0,1}-phy-reg.txt`,
> `dpu/sde-blocks-raw-awake.txt`, `kprobe/dsi-cmds-decoded.txt` (PPS = línea 217/218), `kprobe/sde-regwrites-decoded.txt`
> (escrituras SDE reales del enable, con nombre de registro).
> **Nuestro (código)** = `build/kernel-pokes/k52-L16-tree` (= L73+L74+L75 aplicados; el build más reciente es `k52L74-build`).
> Abreviaturas: HOST = `drivers/gpu/drm/msm/dsi/dsi_host.c`, PANEL = `drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c`,
> PVID = `.../dpu1/dpu_encoder_phys_vid.c`, HINTF = `.../dpu1/dpu_hw_intf.c`, HDSC = `.../dpu1/dpu_hw_dsc_1_2.c`,
> ENC = `.../dpu1/dpu_encoder.c`.
> **Nuestro (medido)** = únicas lecturas de registros de nuestro Linux que existen en el repo/ledger (`~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`
> #649–#652): readback `UKE-L68` (ACTIVE_H/V/TOTAL) en L70/L71/L73, `UKE-L74` (HS_TIMER/MISR/FLUSH), `S4-DIAG` (STATUS0/FIFO_STATUS).
> **No hay** volcado de INTF/DSC/CTL ni de VID_CFG0/LANE_CTRL/CLKOUT de nuestro lado: esas columnas son lectura de código.
> Herramienta: `docs/historia/revision/regdiff-20261017/regdiff.py` (python3 -I, emula `drm_dsc_*`, `dsi_populate_dsc_params`+quirk L73,
> `dsi_timing_setup`, `dsi_ctrl_enable`, `drm_mode_to_intf_timing_params`+`dpu_hw_intf_setup_timing_engine`, `dpu_hw_dsc_config_1_2`);
> salida íntegra en `regdiff-20261017/regdiff-out.txt`. Relacionado (no repetido): `docs/historia/revision/PLAN-KERNEL-PANTALLA-20261017.md` (ya identificó
> DST_FORMAT/ceil 427), `docs/historia/revision/PANEL-REVISION-DPU-VENDOR-20261017.md`, `docs/historia/revision/PANEL-REVISION-DCS-COTEJO-20261017.md`.

## 0. Convenciones y comprobaciones previas

- **Offset DSI**: el volcado vendor es físico; mainline usa base 6G = físico + 4 (`DSI_6G_REG_SHIFT`, `dsi_cfg.c:40`).
  Verificado: HW_VERSION físico 0x000 = `0x20080000` (DSI 2.8.0) y ACTIVE_H en físico 0x024 = mainline `REG_DSI_ACTIVE_H` 0x020.
- **Offset DPU**: vendor `sde_off` cuenta desde MDSS (0xae00000); mainline desde MDP (+0x1000). INTF_1 vendor 0x36000 = catálogo
  palawan 0x35000; DSC_0 vendor 0x81000 = catálogo 0x80000 (`catalog/dpu_10_1_palawan.h:222-230`, enc +0x100/+0x200, ctl +0xf00/+0xf80).
- **dsi0 vs dsi1 vendor**: idénticos salvo FIFO_STATUS (bits EMPTY de HS por carril, sin errores en ninguno), CMD_DMA_CTRL bit30 (maestro
  de broadcast solo en dsi0), LANE_STATUS (instantánea), CLK_STATUS y un contador en 0x39c. Timing/VID_CFG0/compresión: iguales.
- **PHY 0x800-0x9ff**: **SÍ es espejo exacto de 0x000-0x1ff** en ambas PHY (128/128 palabras iguales; §E). TIMING_CTRL_0..13 =
  `00 27 0a 0a 1b 19 0a 0b 0a 02 04 00 20 0f` en dsi0 y dsi1 (= tabla L75).
- **Las escrituras SDE del vendor confirman los valores leídos**: INTF_1/INTF_2 se programan con exactamente los valores del volcado
  (V:kprobe/sde-regwrites-decoded.txt:187-236), salvo dos registros que **se escriben** igual que mainline y **se leen** distinto:
  `INTF_PANEL_FORMAT` (escrito `0x213f` = el nuestro, leído `0x2100`) e `INTF_FRAME_LINE_COUNT_EN` (escrito `3` = el nuestro, leído 0).
  No son diferencias.

## A. Controlador DSI (ambos links) — tabla completa

Columna "¿igual?": compara con dsi0 vendor; cuando nuestro valor depende de la versión se dan dos (L70 / L71-L74, o L74 / L75).
Filas "CAF:" = huecos del XML mainline con nombre de `dsi_ctrl_reg.h` downstream (de memoria, orientativo); "?" = sin nombre.

| fis | mainline | nombre | dsi0 | dsi1 | decodificado (dsi0) | nuestro (codigo) | nuestro (medido) | igual? |
|---|---|---|---|---|---|---|---|---|
| 0x000 | - | CAF:DSI_HW_VERSION | 0x20080000 | 0x20080000 | major=2 minor=8 step=0 | - | - | - |
| 0x004 | 0x000 | CTRL | 0x000001f3 | 0x000001f3 | ENABLE=1 VID_MODE_EN=1 CMD_MODE_EN=0 LANES=0xf CLK_EN=1 ECC=0 CRC=0 | 0x000001f3 [dsi_host.c:945-969 + :1256 (dsi_op_mode_config)] | - | SI |
| 0x008 | 0x004 | STATUS0 | 0x00002008 | 0x00002008 | CMD_ENG_BUSY=0 DMA_BUSY=0 MDP_BUSY=0 VIDEO_BUSY=1 DSI_BUSY=0 bit13=1 bit14=0 | - | L74 timeout 0x00004000 (#652) | - |
| 0x00c | 0x008 | FIFO_STATUS | 0x00001010 | 0x11111010 | VID_MDP_OVF=0 VID_MDP_UNF=0 CMD_MDP_UNF=0 DMA_UNF=0 bit4=1 LP_FIFO_EMPTY=1 HS[L0:---- L1:---- L2:---- L3:----] | - | L70/L73/L74 0xdddd1011; L74 timeout 0xdddd1019 (#649/#652) | - |
| 0x010 | 0x00c | VID_CFG0 | 0x02009140 | 0x02009140 | VC=0 DST_FORMAT=4(RGB101010) TRAFFIC=NON_BURST_SYNC_EVENT BLLP_STOP=1 EOF_BLLP_STOP=1 HSA/HBP/HFP_STOP=0/0/0 DATABUS_WIDEN=1 PULSE_HSA_HE=0 | L70 0x02009130 / L71-L74 0x00009130 [dsi_host.c:863-881; formato RGB888 de panel-xiaomi-o82-dualdsi.c:814; widebus :841-852] | - | NO / NO |
| 0x014 | 0x010 | CAF:VIDEO_MODE_SYNC_DATATYPE | 0x31211101 | 0x31211101 |  | - | - | - |
| 0x018 | 0x014 | CAF:VIDEO_MODE_PIXEL_DATATYPE | 0x3e2e1e0e | 0x3e2e1e0e |  | - | - | - |
| 0x01c | 0x018 | CAF:VIDEO_MODE_BLANKING_DATATYPE | 0x00001900 | 0x00001900 |  | - | - | - |
| 0x020 | 0x01c | VID_CFG1 | 0x00000000 | 0x00000000 |  | 0x00000000 [dsi_host.c:885] | - | SI |
| 0x024 | 0x020 | ACTIVE_H | 0x01cb0020 | 0x01cb0020 | start=32 end=459 (len 427) | L70 0x01cb0020 / L71-L74 0x02360020 [dsi_host.c:1092-1131] | L70 0x01cb0020; L71/L73 0x02360020 (ledger #649/#650/#651) | SI / NO |
| 0x028 | 0x024 | ACTIVE_V | 0x08ec0094 | 0x08ec0094 | start=148 end=2284 (len 2136) | 0x08ec0094 [dsi_host.c:1132] | L71/L73 0x08ec0094 (#650) | SI |
| 0x02c | 0x028 | TOTAL | 0x0905023b | 0x0905023b | H_TOTAL=571(+1=572) V_TOTAL=2309(+1=2310) | L70 0x0905023b / L71-L74 0x090502a6 [dsi_host.c:1135] | L70 0x0905023b; L71/L73 0x090502a6 (#650/#651) | SI / NO |
| 0x030 | 0x02c | ACTIVE_HSYNC | 0x00100000 | 0x00100000 | start=0 end=16 (len 16) | 0x00100000 [dsi_host.c:1139] | - | SI |
| 0x034 | 0x030 | ACTIVE_VSYNC_HPOS | 0x00000000 | 0x00000000 | start=0 end=0 (len 0) | 0x00000000 [dsi_host.c:1142] | - | SI |
| 0x038 | 0x034 | ACTIVE_VSYNC_VPOS | 0x00020000 | 0x00020000 | start=0 end=2 (len 2) | 0x00020000 [dsi_host.c:1143] | - | SI |
| 0x03c | 0x038 | CMD_DMA_CTRL | 0xd0000000 | 0x90000000 | BROADCAST_EN=1 BROADCAST_MASTER(b30)=1 FROM_FB=1 LOW_POWER=0 | 0x14000000 (LP) / 0x10000000 (HS); nunca BROADCAST [dsi_host.c:912, :1296] | - | NO |
| 0x040 | 0x03c | CMD_CFG0 | 0x06100006 | 0x06100006 |  | - | - | - |
| 0x044 | 0x040 | CMD_CFG1 | 0x00003c2c | 0x00003c2c |  | - | - | - |
| 0x048 | 0x044 | DMA_BASE | 0xfff2c000 | 0xfff2c000 |  | - | - | - |
| 0x04c | 0x048 | DMA_LEN | 0x00000020 | 0x00000020 |  | - | - | - |
| 0x050 | 0x04c | CAF:DMA_FIFO_CTRL | 0x00110000 | 0x00110000 |  | - | - | - |
| 0x054 | 0x050 | CAF:DMA_NULL_PACKET_DATA | 0x00000900 | 0x00000900 |  | - | - | - |
| 0x07c | 0x078 | CAF:RDBK_DATATYPE0 | 0x22211211 | 0x22211211 |  | - | - | - |
| 0x080 | 0x07c | CAF:RDBK_DATATYPE1 | 0x001c1a02 | 0x001c1a02 |  | - | - | - |
| 0x084 | 0x080 | TRIG_CTRL | 0x80000004 | 0x80000004 | DMA_TRIG=4 MDP_TRIG=0 STREAM=0 BLOCK_DMA_WITHIN_FRAME=0 TE=1 | 0x80001004 [dsi_host.c:916-925 (BLOCK_DMA_WITHIN_FRAME por 6G>=v1.2)] | - | NO |
| 0x090 | 0x08c | TRIG_DMA | 0x00000001 | 0x00000001 |  | - | - | - |
| 0x0a4 | 0x0a0 | (UKE) MISR_VIDEO_CTRL | 0x00010100 | 0x00010100 |  | L74: 0x00010100 / <=L73: no escrito [dsi_host.c:1165] | L74 rd 0x00010100 (#652) | SI |
| 0x0a8 | 0x0a4 | LANE_STATUS | 0x00001f00 | 0x00001f1f | STOP[D0-3,CLK]=0b0 ULPS_NOT=0b11111 DLN0_DIR=0 | - | - | - |
| 0x0ac | 0x0a8 | LANE_CTRL | 0x01000000 | 0x01000000 | HS_REQ_SEL_PHY=1 CLKLN_HS_FORCE_REQUEST=0 | no escrito (CLOCK_NON_CONTINUOUS en panel :812-813) [dsi_host.c:959-965] | - | - |
| 0x0b0 | 0x0ac | LANE_SWAP_CTRL | 0x00000000 | 0x00000000 | DLN_SWAP_SEL=0 | 0 (dlane_swap por DT) [dsi_host.c:954] | - | SI |
| 0x0b8 | 0x0b4 | LP_TIMER_CTRL | 0xffffffff | 0xffffffff | LP_RX_TO=0xffff BTA_TO=0xffff | no escrito [dsi_host.c:1158 comentario] | - | - |
| 0x0bc | 0x0b8 | HS_TIMER_CTRL | 0x0004bb80 | 0x0004bb80 | HS_TX_TO=48000 RES=4 STOP_EN=0 | L74: 0x0004bb80 / <=L73: no escrito [dsi_host.c:1164] | L74 rd 0x0004bb80 (#652) | SI |
| 0x0c4 | 0x0c0 | CLKOUT_TIMING_CTRL | 0x00000000 | 0x00000000 | T_CLK_PRE=0x0 T_CLK_POST=0x0 | L74 calc 0x00001a23 / L75 0x00000f20 [dsi_host.c:927-929 (+ dsi_phy_7nm.c:1034-1035 L75)] | - | NO / NO |
| 0x0c8 | 0x0c4 | CAF:EOT_PACKET (bytes EoTp 08 0f 0f 01) | 0x010f0f08 | 0x010f0f08 |  | - | - | - |
| 0x0cc | 0x0c8 | EOT_PACKET_CTRL | 0x00000011 | 0x00000011 | TX_EOT_APPEND=1 RX_EOT_IGNORE=1 | 0x00000001 [dsi_host.c:937-940] | - | NO |
| 0x10c | 0x108 | ERR_INT_MASK0 | 0x13e0391f | 0x13e0391f |  | 0x13ff3fe0 [dsi_host.c:943] | - | NO |
| 0x110 | 0x10c | INTR_CTRL | 0x02010000 | 0x02010000 | masks: DMA=0 MDP=0 VIDEO=0 BTA=0 ERROR=1 | status: DMA=0 MDP=0 VIDEO=1 BTA=0 ERR=0 | - | - | - |
| 0x11c | 0x118 | CLK_CTRL | 0x0000023f | 0x0000023f | AHBS=1 AHBM=1 PCLK=1 DSICLK=1 BYTE=1 ESC=1 FORCE_DYN_AHBM=1 | 0x0000023f [dsi_host.c:947 (DSI_CLK_CTRL_ENABLE_CLKS :120-124)] | - | SI |
| 0x120 | 0x11c | CLK_STATUS | 0x008047c3 | 0x00004343 |  | - | - | - |
| 0x134 | 0x130 | CAF:MISR_CMD_MDP0_32BIT | 0xffffffff | 0xffffffff |  | - | - | - |
| 0x138 | 0x134 | CAF:MISR_CMD_MDP1_32BIT | 0xffffffff | 0xffffffff |  | - | - | - |
| 0x13c | 0x138 | ? | 0xffffffff | 0xffffffff |  | - | - | - |
| 0x140 | 0x13c | (UKE) MISR_VIDEO_DATA | 0xffffffff | 0xffffffff |  | - | - | - |
| 0x148 | 0x144 | CAF:LANE0_MISR | 0x0000ffff | 0x0000ffff |  | - | - | - |
| 0x14c | 0x148 | CAF:LANE1_MISR | 0x0000ffff | 0x0000ffff |  | - | - | - |
| 0x150 | 0x14c | CAF:LANE2_MISR | 0x0000ffff | 0x0000ffff |  | - | - | - |
| 0x154 | 0x150 | CAF:LANE3_MISR | 0x0000ffff | 0x0000ffff |  | - | - | - |
| 0x15c | 0x158 | TEST_PATTERN_GEN_CTRL | 0x00000004 | 0x00000004 | EN=0 CMD_DMA_TPG_EN=0 TPG_DMA_FIFO_MODE=1 | - | - | - |
| 0x180 | 0x17c | T_CLK_PRE_EXTEND | 0x00000000 | 0x00000000 |  | 0 salvo clk_pre_inc_by_2 [dsi_host.c:931-935] | - | SI |
| 0x1a4 | 0x1a0 | TPG_VIDEO_CONFIG | 0x00000001 | 0x00000001 |  | - | - | - |
| 0x1a8 | 0x1a4 | ? | 0x00ff0000 | 0x00ff0000 |  | - | - | - |
| 0x1ac | 0x1a8 | ? | 0x00400040 | 0x00400040 |  | - | - | - |
| 0x1b0 | 0x1ac | ? | 0x000000ff | 0x000000ff |  | - | - | - |
| 0x1b4 | 0x1b0 | ? | 0x00000024 | 0x00000024 |  | - | - | - |
| 0x1b8 | 0x1b4 | CMD_MODE_MDP_CTRL2 | 0x00000006 | 0x00000006 |  | - | - | - |
| 0x1c8 | 0x1c4 | CAF:MISR_CMD_MDP2_32BIT | 0xffffffff | 0xffffffff |  | - | - | - |
| 0x1cc | 0x1c8 | CAF:VBIF_CTRL | 0x00000007 | 0x00000007 |  | - | - | - |
| 0x1d0 | 0x1cc | ? | 0x00290000 | 0x00290000 |  | - | - | - |
| 0x1e4 | 0x1e0 | (UKE) FLUSH | 0x00000000 | 0x00000000 |  | L74: 1 (eco 0) [dsi_host.c:1166] | L74 rd 0x0 (#652) | NO |
| 0x1f4 | 0x1f0 | VERSION | 0x03000104 | 0x03000104 |  | - | - | - |
| 0x200 | 0x1fc | CAF:DYNAMIC_REFRESH_CTRL | 0x80000000 | 0x80000000 |  | - | - | - |
| 0x2a0 | 0x29c | VIDEO_COMPRESSION_MODE_CTRL | 0x03200b51 | 0x03200b51 | EN=1 EOL_BYTE_NUM=1 PKT_PER_LINE(log2)=1 DATATYPE=0xb WC=800 | 0x03200b51 (calculado, no medido) [dsi_host.c:976-1034] | - | SI |
| 0x2a8 | 0x2a4 | COMMAND_COMPRESSION_MODE_CTRL | 0x39003900 | 0x39003900 | S0_DT=0x39 S1_DT=0x39 (reset; no se usa en video) | - | - | - |
| 0x2b8 | 0x2b4 | CAF:READ_BACK_DISABLE_STATUS(?) | 0x3e2e0600 | 0x3e2e0600 |  | - | - | - |
| 0x2bc | 0x2b8 | CAF:DESKEW_CTRL(?) | 0x0000f000 | 0x0000f000 |  | - | - | - |
| 0x2c8 | 0x2c4 | ? | 0x20000004 | 0x20000004 |  | - | - | - |
| 0x2d8 | 0x2d4 | CPHY_MODE_CTRL | 0x00000000 | 0x00000000 |  | no escrito (cphy_mode=0) [dsi_host.c:971-972] | - | SI |
| 0x300 | 0x2fc | ? | 0x0000ffff | 0x0000ffff |  | - | - | - |
| 0x310 | 0x30c | CAF:LOGICAL_LANE_SWAP_CTRL(?) | 0x00008421 | 0x00008421 |  | - | - | - |
| 0x314 | 0x310 | ? | 0x00f3ffff | 0x00f3ffff |  | - | - | - |
| 0x318 | 0x314 | ? | 0x0002a300 | 0x0002a300 |  | - | - | - |
| 0x31c | 0x318 | ? | 0x00000143 | 0x00000143 |  | - | - | - |
| 0x320 | 0x31c | ? | 0x10ffffff | 0x10ffffff |  | - | - | - |
| 0x324 | 0x320 | ? | 0x0000b81f | 0x0000b81f |  | - | - | - |
| 0x32c | 0x328 | ? | 0x3c0c2c0d | 0x3c0c2c0d |  | - | - | - |
| 0x330 | 0x32c | CAF:SPLIT_LINK(?) | 0x33533000 | 0x33533000 |  | - | - | - |
| 0x334 | 0x330 | ? | 0xffffffff | 0xffffffff |  | - | - | - |
| 0x338 | 0x334 | ? | 0xffffffff | 0xffffffff |  | - | - | - |
| 0x33c | 0x338 | ? | 0xffffffff | 0xffffffff |  | - | - | - |
| 0x364 | 0x360 | ? | 0x01000000 | 0x01000000 |  | - | - | - |
| 0x368 | 0x364 | ? | 0xffffffff | 0xffffffff |  | - | - | - |
| 0x370 | 0x36c | ? | 0xffffffff | 0xffffffff |  | - | - | - |
| 0x374 | 0x370 | ? | 0xffffffff | 0xffffffff |  | - | - | - |
| 0x378 | 0x374 | ? | 0xffffffff | 0xffffffff |  | - | - | - |
| 0x398 | 0x394 | ? | 0x00130013 | 0x00130013 |  | - | - | - |
| 0x39c | 0x398 | ? | 0x0000038d | 0x000003a4 |  | - | - | - |
| 0x4d8 | 0x4d4 | ? | 0x00000001 | 0x00000001 |  | - | - | - |


### A.1 Lectura de la tabla DSI (lo que importa)

- **VID_CFG0 es la diferencia de fondo**: vendor `0x02009140` = DST_FORMAT **4 (RGB101010)** + DATABUS_WIDEN + NON_BURST_SYNC_EVENT +
  BLLP/EOF_BLLP stop. Nuestro: L70 `0x02009130` (widen sí, **RGB888**), L71-L74 `0x00009130` (ni widen ni RGB101010). El campo sale de
  `dsi_get_vid_fmt(msm_host->format)` (HOST:801-811, 877) y el panel declara `.format = MIPI_DSI_FMT_RGB888` (PANEL:814); el DT vendor
  tiene `qcom,mdss-dsi-bpp = 0x1e` (30). Con widebus el DSI consume "la profundidad sin comprimir por pclk" (comentario HOST:1094-1100; `bits_per_pclk = bpc*3` HOST:1112, H activo HOST:1119):
  vendor 30 bit × 427 pclk = 12 810 ≥ 12 800 bit/línea (1600 B); L70 24 bit × 427 = 10 248 → el DSI se traga 1281 B de 1600 por línea
  y el MDP **desborda** (encaja con `FIFO_STATUS=dddd1011`: VID_MDP_OVF=1 + HS FIFOs O/U en los 4 carriles, medido en L70 y aún en L73/L74).
  El vendor tiene FIFO_STATUS limpio (`0x00001010`/`0x11111010`: solo bits EMPTY).
- **ACTIVE_H/TOTAL**: vendor 427/572 (`0x01cb0020`/`0x0905023b`) = **L70 medido**; L71-L74 medido 534/679 (`0x02360020`/`0x090502a6`),
  que nunca fue vendor (DPU-VENDOR §3). Con pclk 158,56 MHz (igual en ambos) el mundo 24 da 158,56e6/(679·2310) = **101,1 Hz** de cuadro
  y 4,28 µs/línea frente a 120 Hz / 3,61 µs del vendor y del timing que el DDIC tiene seleccionado (b2 91 / b3 40).
- **VIDEO_COMPRESSION_MODE_CTRL** `0x03200b51` (WC 800, DT 0x0b, 2 pkt/línea, EOL 1): nuestro código produce exactamente eso
  (HOST:976-1034, slice_count 2 × chunk 800). No medido, pero sin diferencia de código.
- **CLKOUT_TIMING_CTRL**: vendor **0**; nosotros escribimos T_CLK_PRE/POST del cálculo de la PHY (L74: `0x1a23`; con L75: `0x0f20`,
  HOST:927-929 + `dsi_phy_7nm.c:1034-1035`). El vendor programa clk_pre/clk_post solo en la PHY (TIMING_CTRL_12/13 = 0x20/0x0f, que
  L75 ya copia) y deja el registro del controlador a 0. Corrige la afirmación de `CRITICA-L75` §verif.1 ("el vendor alimenta su host con
  los mismos bytes"): el registro leído vale 0 en ambos links.
- **CMD_DMA_CTRL**: vendor deja BROADCAST_EN (+bit30 maestro en dsi0) = los DCS salen por broadcast HW con un solo disparo. Mainline no
  usa BROADCAST_EN nunca (grep sin usos en HOST); el "sync" de `dsi_manager.c:35,61-63` (`qcom,sync-dual-dsi`) son dos commits SW
  seguidos.
- **TRIG_CTRL**: nuestro BLOCK_DMA_WITHIN_FRAME=1 (HOST:921-923), vendor 0. **EOT_PACKET_CTRL**: vendor RX_EOT_IGNORE=1
  (`qcom,mdss-dsi-rx-eot-ignore` en el DT), nuestro 0 (HOST:937-940; solo afecta a lecturas BTA). **ERR_INT_MASK0**: vendor `0x13e0391f`
  (desenmascara timeouts/FIFO), nuestro `0x13ff3fe0` (HOST:943; solo reporte de IRQ).
- **LANE_CTRL** vendor `0x01000000` (HS_REQ_SEL_PHY=1, sin CLKLN_HS_FORCE_REQUEST): reloj NO continuo, coherente con nuestro
  `MIPI_DSI_CLOCK_NON_CONTINUOUS` (PANEL:812-813; LANE_STATUS de dsi1 muestra el carril de reloj en STOP). Nosotros no escribimos
  LANE_CTRL en ese caso (HOST:959-965): queda el valor de reset, **no medido**.
- **TEST_PATTERN_GEN_CTRL** vendor `0x4` (TPG_DMA_FIFO_MODE) y DMA_BASE/LEN poblados: modo de DMA de comandos del downstream;
  no afecta al vídeo.
- **FLUSH** (físico 0x1e4): es un strobe; el vendor lee 0 en el volcado completo y 1 en `dpu/dsi-ctrl-awake-rereads.txt`. Nuestro L74
  escribe 1 (eco 0). Sin diferencia real. HS_TIMER y MISR: paridad desde L74 (medida).
- STATUS0 vendor `0x2008` (VIDEO_ENGINE_BUSY + bit13 sin nombre); el nuestro (L74, durante un timeout) `0x4000`: no comparable.

## B. INTF_1 / INTF_2

| off | reg | INTF_1 | INTF_2 | L70 (wb ON, trunc 426) | L73/L74 (wb OFF, ceil 534) | propuesta (wb ON, ceil 427) |
|---|---|---|---|---|---|---|
| 0x000 | TIMING_ENGINE_EN | 0x00000001 | 0x00000000 | - | - | - |
| 0x004 | INTF_CONFIG | 0x80800000 | 0x80800000 | - | - | - |
| 0x008 | HSYNC_CTL | 0x023c0010 | 0x023c0010 | 0x023b0010 != | 0x02a70010 != | 0x023c0010 == |
| 0x00c | VSYNC_PERIOD_F0 | 0x00142968 | 0x00142968 | 0x00142062 != | 0x0017eeea != | 0x00142968 == |
| 0x014 | VSYNC_PULSE_WIDTH_F0 | 0x00000478 | 0x00000478 | 0x00000476 != | 0x0000054e != | 0x00000478 == |
| 0x01c | DISPLAY_V_START_F0 | 0x00014ab0 | 0x00014ab0 | 0x00014a1c != | 0x0001888c != | 0x00014ab0 == |
| 0x024 | DISPLAY_V_END_F0 | 0x0013ef4f | 0x0013ef4f | 0x0013e663 != | 0x0017a9f3 != | 0x0013ef4f == |
| 0x02c | ACTIVE_V_START_F0 | 0x00014ab0 | 0x00014ab0 | 0x00000000 != | 0x00000000 != | 0x00000000 != |
| 0x034 | ACTIVE_V_END_F0 | 0x0013ef4f | 0x0013ef4f | 0x00000000 != | 0x00000000 != | 0x00000000 != |
| 0x03c | DISPLAY_HCTL | 0x01ca0020 | 0x01ca0020 | 0x01c90020 != | 0x02350020 != | 0x01ca0020 == |
| 0x040 | ACTIVE_HCTL | 0x01ca0020 | 0x01ca0020 | 0x00000000 != | 0x00000000 != | 0x00000000 != |
| 0x050 | POLARITY_CTL | 0x00000000 | 0x00000000 | 0x00000000 == | 0x00000000 == | 0x00000000 == |
| 0x060 | INTF_CONFIG2 | 0x00001011 | 0x00001011 | 0x00001011 == | 0x00001000 != | 0x00001011 == |
| 0x064 | DISPLAY_DATA_HCTL | 0x012a0020 | 0x012a0020 | 0x012a0020 == | 0x02350020 != | 0x012a0020 == |
| 0x08c | ? | 0x00000011 | 0x00000011 | - | - | - |
| 0x090 | PANEL_FORMAT | 0x00002100 | 0x00002100 | 0x0000213f != | 0x0000213f != | 0x0000213f != |
| 0x094 | ? | 0x01234567 | 0x01234567 | - | - | - |
| 0x0a4 | ? | 0x000000bf | 0x000000d2 | - | - | - |
| 0x0a8 | FRAME_LINE_COUNT_EN | 0x00000000 | 0x00000000 | 0x00000003 != | 0x00000003 != | 0x00000003 != |
| 0x0ac | FRAME_COUNT | 0x000000bf | 0x000000d2 | - | - | - |
| 0x0b0 | LINE_COUNT | 0x000005a0 | 0x0000059e | - | - | - |
| 0x0b8 | ? | 0x00000010 | 0x00000010 | - | - | - |
| 0x0d4 | ? | 0xffffffff | 0xffffffff | - | - | - |
| 0x0d8 | ? | 0xffffffff | 0xffffffff | - | - | - |
| 0x170 | PROG_FETCH_START | 0x0014272d | 0x0014272d | - | - | - |
| 0x178 | ? | 0xffffffff | 0xffffffff | - | - | - |
| 0x180 | MISR_CTRL | 0x01000000 | 0x01000000 | - | - | - |
| 0x1c4 | ? | 0x00000a00 | 0x00000a00 | - | - | - |
| 0x1d8 | ? | 0x00000002 | 0x00000002 | - | - | - |
| 0x1dc | ? | 0x00020001 | 0x00020001 | - | - | - |
| 0x1f0 | ? | 0xffffffff | 0xffffffff | - | - | - |
| 0x210 | ? | 0x00000011 | 0x00000030 | - | - | - |
| 0x214 | ? | 0xe1af83a0 | 0x00000000 | - | - | - |
| 0x218 | ? | 0x00000093 | 0x00000000 | - | - | - |
| 0x21c | ? | 0xe1af835a | 0x00000000 | - | - | - |
| 0x220 | ? | 0x00000093 | 0x00000000 | - | - | - |
| 0x224 | ? | 0x00000001 | 0x00000001 | - | - | - |
| 0x234 | WD_TIMER_0_CTL2 | 0x00000022 | 0x00000022 | - | - | - |
| 0x250 | ? | 0xffffffff | 0xffffffff | - | - | - |
| 0x25c | INTF_MUX | 0x000f0000 | 0x000f0001 | - | - | - |
| 0x268 | ? | 0xffffffff | 0xffffffff | - | - | - |
| 0x26c | INTF_STATUS | 0x00000001 | 0x00000001 | - | - | - |


### B.1 Lectura de la tabla INTF

- Modo por link usado en la emulación: hactive 1600, hfp 113, hsync 16, hbp 16; vactive 2136, vfp 26, vsync 2, vbp 146 (DT vendor
  timing@120 = PANEL:730-741 tras el split de PVID:290-295). `dce_bytes_per_line` = 2 × 800 = 1600.
- **La "propuesta" (widebus ON + ceil(1600·8/30) = 427) reproduce el vendor bit a bit** en HSYNC_CTL, VSYNC_PERIOD, VSYNC_PULSE,
  DISPLAY_V_START/END, DISPLAY_HCTL, INTF_CONFIG2 `0x1011` y DATA_HCTL `0x012a0020` (267 = ceil(1600/6)).
- **L70** (widebus ON pero `width·8/30` truncado a 426, código vanilla): periodo 571 frente a DSI 572 → 1 px/línea de desfase INTF→DSI
  (2310 px por cuadro de sobre-alimentación). **L73/L74** (ceil /24 = 534, PVID:139-147; widebus OFF): periodo 679, CONFIG2 `0x1000`
  (DATA_HCTL_EN=0 por compresión sin widebus, HINTF:262-267). Coherente con su DSI, pero no es el vendor.
- **INTF_CONFIG**: el vendor escribe `0x60800000` y luego `0x80800000` (V:sde-regwrites:201/209, 228/236): bit31 = prog-fetch ON con
  `PROG_FETCH_START=0x0014272d` (1 línea antes del fin de cuadro) y **bit23** (sin nombre en mainline). Mainline hace read-modify-write
  (HINTF:123, 258) y solo toca bits 29/30/31; con vbp 146 > `prog_fetch_lines_worst_case` 24 no activa prog-fetch → bit31=0 y bit23 queda
  al valor heredado (no medido).
- **TIMING_ENGINE_EN**: vendor solo en INTF_1 (una única escritura, V:sde-regwrites:331, a +2 ms del PPS); INTF_2 queda a 0 pero su
  contador de líneas corre (0x59e vs 0x5a0: esclavo del maestro). Mainline lo activa en **cada** phys encoder
  (`dpu_encoder_phys_vid_handle_post_kickoff`, PVID:659-673, sin `is_master`).
- ACTIVE_HCTL / ACTIVE_V_* los escribe el vendor pero sin ACTIVE_H/V_EN en el valor final: sin efecto. INTF_MUX: INTF_1←PP_0,
  INTF_2←PP_1, igual que nuestro `bind_pingpong_blk`.

## C. DPU: DSC_0/DSC_1, DSC ctl, CTL, LM, MERGE_3D, PP

| off | reg | DSC0 vendor | DSC1 vendor | decod. vendor | nuestro L73+ | decod. nuestro | igual? | mainline puro (<=L72) |
|---|---|---|---|---|---|---|---|---|
| 0x00 | ENC_DF_CTRL | 0x095c1203 | 0x095c1203 | initial_lines=3 video=1 bit12=1 bits10-17=0x4 ob_max_addr=599 | 0x095c0202 | initial_lines=2 video=1 bit12=0 bits10-17=0x0 ob_max_addr=599 | **NO** | 0x095c0202 (!=) |
| 0x04 | ENC_GENERAL_STATUS | 0x00000003 | 0x00000003 |  | (estado) |  | - | - |
| 0x08 | ENC_HSLICE_STATUS | 0x000e0004 | 0x00230006 |  | (estado) |  | - | - |
| 0x0c | ENC_OUT_STATUS | 0x000d0011 | 0x00220012 |  | (estado) |  | - | - |
| 0x10 | ENC_INT_STAT | 0x000007b0 | 0x000007b0 |  | (estado) |  | - | - |
| 0x14 | ENC_INT_CLR | 0x00000000 | 0x00000000 |  | (estado) |  | - | - |
| 0x18 | ENC_INT_MASK | 0x00000000 | 0x00000000 |  | (estado) |  | - | - |
| 0x1c | ? | 0x00000000 | 0x00000000 |  | (estado) |  | - | - |
| 0x20 | ? | 0x00000000 | 0x00000000 |  | (estado) |  | - | - |
| 0x24 | ? | 0x00000000 | 0x00000000 |  | (estado) |  | - | - |
| 0x28 | ? | 0x00000000 | 0x00000000 |  | (estado) |  | - | - |
| 0x2c | ? | 0x00000000 | 0x00000000 |  | (estado) |  | - | - |
| 0x30 | DSC_MAIN_CONF | 0x101202da | 0x101202da | minor=1 bpp16=128 blk_pred=1 lbd=11 rgb=1 bpc=10 | 0x101202da | minor=1 bpp16=128 blk_pred=1 lbd=11 rgb=1 bpc=10 | SI | 0x101202da |
| 0x34 | DSC_PICTURE_SIZE | 0x08580c80 | 0x08580c80 | w=3200 h=2136 | 0x08580c80 | w=3200 h=2136 | SI | 0x08580c80 |
| 0x38 | DSC_SLICE_SIZE | 0x00180320 | 0x00180320 | w=800 h=24 | 0x00180320 | w=800 h=24 | SI | 0x00180320 |
| 0x3c | DSC_MISC_SIZE | 0x00000320 | 0x00000320 |  | 0x00000320 |  | SI | 0x00000320 |
| 0x40 | DSC_HRD_DELAYS | 0x02b20200 | 0x02b20200 | xmit=512 dec=690 | 0x02b20200 | xmit=512 dec=690 | SI | 0x02910200 (!=) |
| 0x44 | DSC_RC_SCALE | 0x00000020 | 0x00000020 |  | 0x00000020 |  | SI | 0x00000020 |
| 0x48 | DSC_RC_SCALE_INC_DEC | 0x000b029f | 0x000b029f | inc=671 dec=11 | 0x000b029f | inc=671 dec=11 | SI | 0x000b02c0 (!=) |
| 0x4c | DSC_RC_OFFSETS_1 | 0x0000000d | 0x0000000d | flb=13 slb=0 | 0x0000000d | flb=13 slb=0 | SI | 0x0000000c (!=) |
| 0x50 | DSC_RC_OFFSETS_2 | 0x02dc0486 | 0x02dc0486 | nfl=1158 slice_bpg=732 | 0x02dc0486 | nfl=1158 slice_bpg=732 | SI | 0x02dc042d (!=) |
| 0x54 | DSC_RC_OFFSETS_3 | 0x10f01800 | 0x10f01800 | init_ofs=6144 final_ofs=4336 | 0x10f01800 | init_ofs=6144 final_ofs=4336 | SI | 0x10f01800 |
| 0x58 | DSC_RC_OFFSETS_4 | 0x00000000 | 0x00000000 |  | 0x00000000 |  | SI | 0x00000000 |
| 0x5c | DSC_FLATNESS_QP | 0x00002207 | 0x00002207 | flat min 7 max 16 det 8 | 0x00002207 | flat min 7 max 16 det 8 | SI | 0x00002207 |
| 0x60 | DSC_RC_MODEL_SIZE | 0x00002000 | 0x00002000 |  | 0x00002000 |  | SI | 0x00002000 |
| 0x64 | DSC_RC_CONFIG | 0x0331ef06 | 0x0331ef06 |  | 0x0331ef06 |  | SI | 0x0331ef06 |
| 0x68 | DSC_RC_BUF_THRESH_0 | 0x382a1c0e | 0x382a1c0e |  | 0x382a1c0e |  | SI | 0x382a1c0e |
| 0x6c | DSC_RC_BUF_THRESH_1 | 0x69625446 | 0x69625446 |  | 0x69625446 |  | SI | 0x69625446 |
| 0x70 | DSC_RC_BUF_THRESH_2 | 0x7b797770 | 0x7b797770 |  | 0x7b797770 |  | SI | 0x7b797770 |
| 0x74 | DSC_RC_BUF_THRESH_3 | 0x00007e7d | 0x00007e7d |  | 0x00007e7d |  | SI | 0x00007e7d |
| 0x78 | DSC_RC_MIN_QP_0 | 0x00729480 | 0x00729480 | 0/4/5/5/7 | 0x00729480 | 0/4/5/5/7 | SI | 0x00729480 |
| 0x7c | DSC_RC_MIN_QP_1 | 0x00739ce7 | 0x00739ce7 | 7/7/7/7/7 | 0x00739ce7 | 7/7/7/7/7 | SI | 0x00739ce7 |
| 0x80 | DSC_RC_MIN_QP_2 | 0x0115a529 | 0x0115a529 | 9/9/9/11/17 | 0x0115a529 | 9/9/9/11/17 | SI | 0x0115a529 |
| 0x84 | DSC_RC_MAX_QP_0 | 0x00b52508 | 0x00b52508 | 8/8/9/10/11 | 0x00b52508 | 8/8/9/10/11 | SI | 0x00b52504 (!=) |
| 0x88 | DSC_RC_MAX_QP_1 | 0x00e6b16b | 0x00e6b16b | 11/11/12/13/14 | 0x00e6b16b | 11/11/12/13/14 | SI | 0x00e6b16b |
| 0x8c | DSC_RC_MAX_QP_2 | 0x0138c60f | 0x0138c60f | 15/16/17/17/19 | 0x0138c60f | 15/16/17/17/19 | SI | 0x0138c60f |
| 0x90 | DSC_RC_RANGE_BPG_OFFSETS_0 | 0x3cf80002 | 0x3cf80002 | 2/0/0/-2/-4 | 0x3cf80002 | 2/0/0/-2/-4 | SI | 0x3cf80002 |
| 0x94 | DSC_RC_RANGE_BPG_OFFSETS_1 | 0x36e38e3a | 0x36e38e3a | -6/-8/-8/-8/-10 | 0x36e38e3a | -6/-8/-8/-8/-10 | SI | 0x36e38e3a |
| 0x98 | DSC_RC_RANGE_BPG_OFFSETS_2 | 0x34d34d36 | 0x34d34d36 | -10/-12/-12/-12/-12 | 0x34d34d36 | -10/-12/-12/-12/-12 | SI | 0x34d34d36 |

DSC_CMN_MAIN_CNF (top 0x81000): vendor 0x00000101 | nuestro 0x00000101 | SI
DSC0_ctl: DSC_CTL vendor 0x0 / nuestro 0x0 (PP_0); DSC_CFG vendor 0x00001001 / nuestro 0x00001001; DATA_IN_SWAP vendor 0x0002c688 / nuestro no escrito; DSC_CLK_CTRL vendor 0xc0000000 / nuestro no escrito
DSC1_ctl: DSC_CTL vendor 0x1 / nuestro 0x1 (PP_1); DSC_CFG vendor 0x00001001 / nuestro 0x00001001; DATA_IN_SWAP vendor 0x0002c688 / nuestro no escrito; DSC_CLK_CTRL vendor 0xc0000000 / nuestro no escrito
initial_lines nuestro = 2 (dpu_encoder.c:1970-1990, enc_ip_w=1600, soft_slice=2)


### C.1 Lectura DSC + resto del DPU

- **Encoder DSC: paridad total en los 27 registros de configuración (0x30-0x98); solo difiere ENC_DF_CTRL** (con el quirk L73; sin él difieren HRD_DELAYS,
  SCALE_INC_DEC, OFFSETS_1/2 y MAX_QP_0, que L73 ya cerró). DSC_PICTURE_SIZE = 3200×2136 en **ambos** encoders, como el nuestro
  (`dsc->pic_width = mode->hdisplay`, HOST:1082). Tablas RC (BUF_THRESH, MIN/MAX_QP, BPG_OFFSETS) idénticas.
- **ENC_DF_CTRL**: vendor `0x095c1203` vs nuestro `0x095c0202`:
  - `initial_lines` **3 vs 2**. Nuestro: `dpu_encoder_dsc_initial_line_calc` (ENC:1970-1993) = ceil((92·3 + 512 + 47 + 92·3)/800) = 2
    (enc_ip_w 1600 → 2 soft-slices). El vendor programa 3 (su `sde_encoder` usa otra fórmula de latencia; no reproducida aquí, el valor es lo medido).
  - **bit12 = 1** en vendor; mainline no lo define ni lo escribe (HDSC:120-127).
  - ob_max_addr 599 igual (palawan declara `DPU_DSC_NATIVE_42x_EN`), video=1 igual.
- DSC_CMN_MAIN_CNF `0x101` (split-panel, 2 slices/enc), DSC_CTL (PP_0/PP_1) y DSC_CFG `0x1001`: iguales.
  `DSC_DATA_IN_SWAP 0x2c688` = valor de reset (DSC_2 sin uso también lo tiene). **DSC_CLK_CTRL `0xc0000000`** en DSC_0/1 (DSC_2: 0);
  no aparece en las escrituras `sde_reg_write` (¿REG_DMA?); mainline nunca lo escribe.
- `DSC_4HS_MERGE_EN/CFG` (ctl+0x10/0x14): el vendor escribe 0; mainline no los toca (reset 0 presumible).
- **CTL_0**: DSC_ACTIVE 3, INTF_ACTIVE 6, INTF_MASTER 2 (INTF_1), MERGE_3D_ACTIVE 0, CTL_TOP `0xf0000000`: es lo que genera
  `dpu_hw_ctl_intf_cfg_v1` para 2 LM + 2 DSC + 2 INTF (dpu_hw_ctl.c:580-620; group_id 0xf). MERGE_3D_0..3 = 0. LM_0/LM_1
  OUT_SIZE `0x08580640` (1600×2136/LM). Sin diferencia de código (no medido en nuestro lado).
- PP: los bloques "PP_x_b/_c" del volcado (0x6a300…) no corresponden a ningún registro de `dpu_hw_pingpong.c`; en DPU ≥ 7 el DSC no
  pasa por PP_DSC_MODE. Nada que comparar.

## D. PPS (128 B, dt=0x0A)

Vendor (V:kprobe/dsi-cmds-decoded.txt:217-218, idéntica en ctrl 0 y 1, mflags 0x2 = LP, +1,4 ms tras 0x29).
Nuestra PPS emulada con `drm_dsc_pps_payload_pack` sobre la `drm_dsc_config` del panel (PANEL:779-789) → `dsi_populate_dsc_params`
(HOST:2036-2103, pre-SCR 8bpp/10bpc) → recompute L73 (flb 13, range_max_qp[0] 8) → `pic_width = hdisplay/2` (PANEL:432 y :623).

```
vendor : 11 00 00 ab 30 80 08 58 0c 80 00 18 03 20 03 20 02 00 02 b2 00 20 02 9f 00 0b 00 0d 04 86 02 dc 18 00 10 f0 07 10 20 00 06 0f 0f 33 0e 1c 2a 38 46 54 62 69 70 77 79 7b 7d 7e 02 02 22 00 2a 40 2a be 3a fc 3a fa 3a f8 3b 38 3b 78 3b b6 4b f6 4c 34 4c 74 5c 74 8c f4 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```
```
L73+   : 11 00 00 ab 30 80 08 58 06 40 00 18 03 20 03 20 02 00 02 b2 00 20 02 9f 00 0b 00 0d 04 86 02 dc 18 00 10 f0 07 10 20 00 06 0f 0f 33 0e 1c 2a 38 46 54 62 69 70 77 79 7b 7d 7e 02 02 22 00 2a 40 2a be 3a fc 3a fa 3a f8 3b 38 3b 78 3b b6 4b f6 4c 34 4c 74 5c 74 8c f4 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00   (pic_width=1600 por link, panel :432/:623)
```
```
<=L72  : 11 00 00 ab 30 80 08 58 06 40 00 18 03 20 03 20 02 00 02 91 00 20 02 c0 00 0b 00 0c 04 2d 02 dc 18 00 10 f0 07 10 20 00 06 0f 0f 33 0e 1c 2a 38 46 54 62 69 70 77 79 7b 7d 7e 01 02 22 00 2a 40 2a be 3a fc 3a fa 3a f8 3b 38 3b 78 3b b6 4b f6 4c 34 4c 74 5c 74 8c f4 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```
| byte | campo | vendor | nuestro L73+ (1600) | igual? | nuestro <=L72 |
|---|---|---|---|---|---|
| 0 | dsc_version (maj<<4|min) | 0x11 (17) | 0x11 (17) | SI | 0x11 (17) |
| 1 | pps_identifier | 0x00 (0) | 0x00 (0) | SI | 0x00 (0) |
| 2 | reservado | 0x00 (0) | 0x00 (0) | SI | 0x00 (0) |
| 3 | bpc<<4 | line_buf_depth | 0xab (171) | 0xab (171) | SI | 0xab (171) |
| 4 | flags: block_pred(5) convert_rgb(4) 422(3) vbr(2) bpp_hi | 0x30 (48) | 0x30 (48) | SI | 0x30 (48) |
| 5 | bits_per_pixel_low (bpp*16) | 0x80 (128) | 0x80 (128) | SI | 0x80 (128) |
| 6-7 | pic_height | 0x0858 (2136) | 0x0858 (2136) | SI | 0x0858 (2136) |
| 8-9 | pic_width | 0x0c80 (3200) | 0x0640 (1600) | **NO** | 0x0640 (1600) |
| 10-11 | slice_height | 0x0018 (24) | 0x0018 (24) | SI | 0x0018 (24) |
| 12-13 | slice_width | 0x0320 (800) | 0x0320 (800) | SI | 0x0320 (800) |
| 14-15 | chunk_size | 0x0320 (800) | 0x0320 (800) | SI | 0x0320 (800) |
| 16-17 | initial_xmit_delay | 0x0200 (512) | 0x0200 (512) | SI | 0x0200 (512) |
| 18-19 | initial_dec_delay | 0x02b2 (690) | 0x02b2 (690) | SI | 0x0291 (657) |
| 20 | reservado | 0x00 (0) | 0x00 (0) | SI | 0x00 (0) |
| 21 | initial_scale_value | 0x20 (32) | 0x20 (32) | SI | 0x20 (32) |
| 22-23 | scale_increment_interval | 0x029f (671) | 0x029f (671) | SI | 0x02c0 (704) |
| 24-25 | scale_decrement_interval | 0x000b (11) | 0x000b (11) | SI | 0x000b (11) |
| 26 | reservado | 0x00 (0) | 0x00 (0) | SI | 0x00 (0) |
| 27 | first_line_bpg_offset | 0x0d (13) | 0x0d (13) | SI | 0x0c (12) |
| 28-29 | nfl_bpg_offset | 0x0486 (1158) | 0x0486 (1158) | SI | 0x042d (1069) |
| 30-31 | slice_bpg_offset | 0x02dc (732) | 0x02dc (732) | SI | 0x02dc (732) |
| 32-33 | initial_offset | 0x1800 (6144) | 0x1800 (6144) | SI | 0x1800 (6144) |
| 34-35 | final_offset | 0x10f0 (4336) | 0x10f0 (4336) | SI | 0x10f0 (4336) |
| 36 | flatness_min_qp | 0x07 (7) | 0x07 (7) | SI | 0x07 (7) |
| 37 | flatness_max_qp | 0x10 (16) | 0x10 (16) | SI | 0x10 (16) |
| 38-39 | rc_model_size | 0x2000 (8192) | 0x2000 (8192) | SI | 0x2000 (8192) |
| 40 | rc_edge_factor | 0x06 (6) | 0x06 (6) | SI | 0x06 (6) |
| 41 | rc_quant_incr_limit0 | 0x0f (15) | 0x0f (15) | SI | 0x0f (15) |
| 42 | rc_quant_incr_limit1 | 0x0f (15) | 0x0f (15) | SI | 0x0f (15) |
| 43 | rc_tgt_offset hi<<4|lo | 0x33 (51) | 0x33 (51) | SI | 0x33 (51) |
| 44 | rc_buf_thresh[0] | 0x0e (14) | 0x0e (14) | SI | 0x0e (14) |
| 45 | rc_buf_thresh[1] | 0x1c (28) | 0x1c (28) | SI | 0x1c (28) |
| 46 | rc_buf_thresh[2] | 0x2a (42) | 0x2a (42) | SI | 0x2a (42) |
| 47 | rc_buf_thresh[3] | 0x38 (56) | 0x38 (56) | SI | 0x38 (56) |
| 48 | rc_buf_thresh[4] | 0x46 (70) | 0x46 (70) | SI | 0x46 (70) |
| 49 | rc_buf_thresh[5] | 0x54 (84) | 0x54 (84) | SI | 0x54 (84) |
| 50 | rc_buf_thresh[6] | 0x62 (98) | 0x62 (98) | SI | 0x62 (98) |
| 51 | rc_buf_thresh[7] | 0x69 (105) | 0x69 (105) | SI | 0x69 (105) |
| 52 | rc_buf_thresh[8] | 0x70 (112) | 0x70 (112) | SI | 0x70 (112) |
| 53 | rc_buf_thresh[9] | 0x77 (119) | 0x77 (119) | SI | 0x77 (119) |
| 54 | rc_buf_thresh[10] | 0x79 (121) | 0x79 (121) | SI | 0x79 (121) |
| 55 | rc_buf_thresh[11] | 0x7b (123) | 0x7b (123) | SI | 0x7b (123) |
| 56 | rc_buf_thresh[12] | 0x7d (125) | 0x7d (125) | SI | 0x7d (125) |
| 57 | rc_buf_thresh[13] | 0x7e (126) | 0x7e (126) | SI | 0x7e (126) |
| 58-59 | rc_range[0] (minqp<<11|maxqp<<6|ofs) | 0x0202 (514) min 0 max 8 ofs 2 | 0x0202 (514) min 0 max 8 ofs 2 | SI | 0x0102 (258) |
| 60-61 | rc_range[1] (minqp<<11|maxqp<<6|ofs) | 0x2200 (8704) min 4 max 8 ofs 0 | 0x2200 (8704) min 4 max 8 ofs 0 | SI | 0x2200 (8704) |
| 62-63 | rc_range[2] (minqp<<11|maxqp<<6|ofs) | 0x2a40 (10816) min 5 max 9 ofs 0 | 0x2a40 (10816) min 5 max 9 ofs 0 | SI | 0x2a40 (10816) |
| 64-65 | rc_range[3] (minqp<<11|maxqp<<6|ofs) | 0x2abe (10942) min 5 max 10 ofs -2 | 0x2abe (10942) min 5 max 10 ofs -2 | SI | 0x2abe (10942) |
| 66-67 | rc_range[4] (minqp<<11|maxqp<<6|ofs) | 0x3afc (15100) min 7 max 11 ofs -4 | 0x3afc (15100) min 7 max 11 ofs -4 | SI | 0x3afc (15100) |
| 68-69 | rc_range[5] (minqp<<11|maxqp<<6|ofs) | 0x3afa (15098) min 7 max 11 ofs -6 | 0x3afa (15098) min 7 max 11 ofs -6 | SI | 0x3afa (15098) |
| 70-71 | rc_range[6] (minqp<<11|maxqp<<6|ofs) | 0x3af8 (15096) min 7 max 11 ofs -8 | 0x3af8 (15096) min 7 max 11 ofs -8 | SI | 0x3af8 (15096) |
| 72-73 | rc_range[7] (minqp<<11|maxqp<<6|ofs) | 0x3b38 (15160) min 7 max 12 ofs -8 | 0x3b38 (15160) min 7 max 12 ofs -8 | SI | 0x3b38 (15160) |
| 74-75 | rc_range[8] (minqp<<11|maxqp<<6|ofs) | 0x3b78 (15224) min 7 max 13 ofs -8 | 0x3b78 (15224) min 7 max 13 ofs -8 | SI | 0x3b78 (15224) |
| 76-77 | rc_range[9] (minqp<<11|maxqp<<6|ofs) | 0x3bb6 (15286) min 7 max 14 ofs -10 | 0x3bb6 (15286) min 7 max 14 ofs -10 | SI | 0x3bb6 (15286) |
| 78-79 | rc_range[10] (minqp<<11|maxqp<<6|ofs) | 0x4bf6 (19446) min 9 max 15 ofs -10 | 0x4bf6 (19446) min 9 max 15 ofs -10 | SI | 0x4bf6 (19446) |
| 80-81 | rc_range[11] (minqp<<11|maxqp<<6|ofs) | 0x4c34 (19508) min 9 max 16 ofs -12 | 0x4c34 (19508) min 9 max 16 ofs -12 | SI | 0x4c34 (19508) |
| 82-83 | rc_range[12] (minqp<<11|maxqp<<6|ofs) | 0x4c74 (19572) min 9 max 17 ofs -12 | 0x4c74 (19572) min 9 max 17 ofs -12 | SI | 0x4c74 (19572) |
| 84-85 | rc_range[13] (minqp<<11|maxqp<<6|ofs) | 0x5c74 (23668) min 11 max 17 ofs -12 | 0x5c74 (23668) min 11 max 17 ofs -12 | SI | 0x5c74 (23668) |
| 86-87 | rc_range[14] (minqp<<11|maxqp<<6|ofs) | 0x8cf4 (36084) min 17 max 19 ofs -12 | 0x8cf4 (36084) min 17 max 19 ofs -12 | SI | 0x8cf4 (36084) |
| 88 | native_422|420 | 0x00 (0) | 0x00 (0) | SI | 0x00 (0) |
| 89 | second_line_bpg_offset | 0x00 (0) | 0x00 (0) | SI | 0x00 (0) |
| 90-91 | nsl_bpg_offset | 0x0000 (0) | 0x0000 (0) | SI | 0x0000 (0) |
| 92-93 | second_line_offset_adj | 0x0000 (0) | 0x0000 (0) | SI | 0x0000 (0) |
| 94-127 | reservado (0) | todo-cero | todo-cero | SI | todo-cero |

Bytes distintos vendor vs L73+(1600): [8] 0c/06, [9] 80/40
Bytes distintos vendor vs L73+ con pic_width=3200: NINGUNO (identica)
Bytes distintos vendor vs <=L72(1600): [8] 0c/06, [9] 80/40, [19] b2/91, [23] 9f/c0, [27] 0d/0c, [29] 86/2d, [58] 02/01

DSC config nuestro L73+: slice_chunk_size=800, initial_xmit_delay=512, initial_dec_delay=690, initial_scale_value=32, scale_increment_interval=671, scale_decrement_interval=11, first_line_bpg_offset=13, nfl_bpg_offset=1158, slice_bpg_offset=732, initial_offset=6144, final_offset=4336, rc_bits=9616, _groups_per_line=267, _num_extra_mux_bits=240, _final_scale=16


### D.1 Lectura PPS

- **Con L73 la PPS es idéntica a la del vendor en 126 de 128 bytes**; las únicas diferencias son **bytes 8-9 = pic_width**:
  vendor `0x0c80` (**3200, ancho COMPLETO en cada link**) vs nuestro `0x0640` (1600). Si se empaqueta con pic_width = 3200
  (es decir, el `ctx->dsc` tal cual lo deja el host, HOST:1082) la PPS sale **byte a byte idéntica** (0 diferencias, §salida).
- Los 5 bytes OEM que L73 cerró (dec_delay 690 [19], scale_inc 671 [23], flb 13 [27], nfl 1158 [29], max_qp0 8 [58]) aparecen tal cual
  en la PPS vendor medida: el quirk L73 queda **confirmado por el cable**, no solo por el init 0x91 del DDIC.
- El argumento de L62 ("pic_width = slices × slice_width de LA INTERFAZ = 1600", PANEL:416-428) queda refutado por la medida: el
  vendor declara el cuadro completo (3200 = 4 slices de 800) al DDIC por ambos links, coherente con el `DSC_PICTURE_SIZE` de sus dos
  encoders (3200×2136) y con el nuestro.
- Nota de proceso: el vendor manda la PPS una vez, en LP, tras 0x29 y antes del motor de vídeo (DCS-COTEJO Dif. 1-2); nosotros dos veces
  (PANEL:445-448 pre-0x11 y :636-638 post-0x29).

## E. PHY: espejo 0x800-0x9ff

- dsi0_phy: 128/128 palabras iguales; difieren: ninguna
- dsi0_phy TIMING_CTRL_0..13 (0x0b4..0x0e8): 00 27 0a 0a 1b 19 0a 0b 0a 02 04 00 20 0f
- dsi1_phy: 128/128 palabras iguales; difieren: ninguna
- dsi1_phy TIMING_CTRL_0..13 (0x0b4..0x0e8): 00 27 0a 0a 1b 19 0a 0b 0a 02 04 00 20 0f

## F. Lo que YA coincide (no tocar)

DSI: CTRL `0x1f3`, VID_CFG1, ACTIVE_V `0x08ec0094` (medido), ACTIVE_HSYNC/VSYNC_VPOS, VIDEO_COMPRESSION_MODE_CTRL `0x03200b51`
(código), CLK_CTRL `0x23f`, LANE_SWAP 0, HS_TIMER `0x4bb80` y MISR `0x10100` (L74, medidos), reloj no continuo, CPHY off.
DPU: los 27 registros de configuración del encoder DSC (0x30-0x98) (con L73), DSC_CMN_MAIN_CNF, DSC_CFG, DSC_CTL, topología
CTL (DSC_ACTIVE 3 / INTF_ACTIVE 6 / MASTER INTF_1 / sin MERGE_3D), LM 1600×2136, INTF_MUX, PANEL_FORMAT y FRAME_LINE_COUNT_EN (mismo
valor escrito). PHY: TIMING_CTRL 14/14 con L75. PPS: 126/128 con L73.

## G. DIFERENCIAS, ordenadas por probabilidad de causar pantalla negra

| # | Diferencia | Vendor | Nuestro (árbol actual = L74/L75) | Cambio concreto que la cierra | Prob. |
|---|---|---|---|---|---|
| 1 | **Formato de píxel del DSI + widebus** (VID_CFG0, ACTIVE_H, TOTAL) | `0x02009140` (RGB101010 + WIDEN), H 427, TOTAL `0x0905023b` (120 Hz) | `0x00009130` (RGB888, sin WIDEN), H 534, TOTAL `0x090502a6` → 101 Hz; L70 tenía WIDEN con RGB888 (DSI consume 24 de 30 bit/pclk → VID_MDP overflow `dddd1011`) | PANEL:814 `.format = MIPI_DSI_FMT_RGB101010`; HOST:841-852 `msm_dsi_host_is_wide_bus_enabled()` → volver a `msm_host->dsc && msm_dsi_host_version_geq(msm_host, MSM_DSI_VER_MAJOR_6G, MSM_DSI_6G_VER_MINOR_V2_5_0)`. Esperado: VID_CFG0 `0x02009140`, ACTIVE_H `0x01cb0020`, TOTAL `0x0905023b` sin tocar `dsi_timing_setup` (HOST:1112/1119 ya usa bpc·3). El hunk L70 (HOST:684-688) queda redundante (bpp 30 por formato). El aviso de HOST:1903-1906 no salta (widebus ON). | **Muy alta** |
| 2 | **Ancho del INTF** (va obligatoriamente con #1) | 427, HSYNC_CTL `0x023c0010`, CONFIG2 `0x1011`, DATA_HCTL `0x012a0020` | ceil /24 = 534 (PVID:144); con widebus ON y este /24 el INTF quedaría en 679 frente a DSI 572 (peor que L70) | PVID:144 → `timing->width = DIV_ROUND_UP(timing->width * drm_dsc_get_bpp_int(dsc), timing->wide_bus_en ? dsc->bits_per_component * 3 : 24);` (ceil, no el truncado vanilla que daba 426/571 en L70). Gate: readback HINTF de HSYNC_CTL/DISPLAY_HCTL/CONFIG2/DATA_HCTL == vendor. | **Muy alta** (junto con #1) |
| 3 | **PPS pic_width** (bytes 8-9) | 3200 en cada link | 1600 (PANEL:432 y :623, `hdisplay / 2`) | PANEL:432 y :623 → `dsc_link.pic_width = desc->modes[0].hdisplay;` (o empaquetar `ctx->dsc` sin copia). Resultado emulado: PPS 128/128 = vendor. | **Alta** (único byte de la PPS que el DDIC recibe distinto; barato) |
| 4 | **DSC ENC_DF_CTRL**: initial_lines y bit12 | `0x095c1203` (3 líneas, bit12=1) | `0x095c0202` (2 líneas, bit12=0) — ENC:1970-1993, HDSC:120-127 | HDSC `dpu_hw_dsc_config_1_2()` tras :125: quirk o82 (`bpc==10 && slice_width==800 && slice_height==24`) → `initial_lines = 3` y `data \|= BIT(12)`; o en ENC:2060 forzar 3 y añadir el BIT(12) en HDSC. Gate: readback `ENC_DF_CTRL == 0x095c1203`. | **Media** (menos líneas de precarga = posible subdesbordamiento del rate buffer al inicio de cuadro) |
| 5 | **INTF_2 timing engine** | 0 (solo INTF_1, una escritura) | 1 en INTF_1 e INTF_2 (PVID:659-673 sin `is_master`) | PVID:668-672 → envolver `enable_timing(...,1)` en `if (dpu_encoder_phys_vid_is_master(phys_enc))` (dejar `enable_state = DPU_ENC_ENABLED` para ambos). | Media-baja |
| 6 | **CLKOUT_TIMING_CTRL** del host | 0 | `0x1a23` (L74) / `0x0f20` (L75) — HOST:927-929 | HOST:927-929 → para DSI ≥ 2.8 (o este panel) escribir 0; clk_pre/post quedan solo en la PHY (TIMING_CTRL_12/13, ya vendor con L75). | Media-baja |
| 7 | **INTF_CONFIG bit23** (+ prog-fetch) | `0x80800000` (bit31 prog-fetch con START `0x0014272d`, bit23) | read-modify-write sin bit23; prog-fetch OFF (vbp 146 > 24) — HINTF:123/258 | HINTF:258 → `intf_cfg \|= BIT(23)` para INTF_DSI con compresión (semántica no documentada en mainline; cambio de paridad pura). Prog-fetch: opcional. | Baja-media (desconocida) |
| 8 | **Broadcast HW de comandos** (CMD_DMA_CTRL) | BROADCAST_EN en ambos + bit30 maestro en dsi0 | nunca (HOST:912/1296; `dsi_manager.c` hace 2 commits SW) | HOST `msm_dsi_host_xfer_prepare()`/`dsi_cmd_dma_tx()`: con bonded+sync, OR `BIT(31)` en ambos y `BIT(30)` en DSI_0, disparar solo DSI_0. Más invasivo; diferir. | Baja-media (afecta solo a la entrega de DCS/PPS) |
| 9 | DSC_CLK_CTRL | `0xc0000000` en DSC_0/1 | no escrito | HDSC: `DPU_REG_WRITE(hw, sblk->ctl.base + DSC_CLK_CTRL, 0xc0000000)` al configurar (semántica no documentada). | Baja |
| 10 | TRIG_CTRL BLOCK_DMA_WITHIN_FRAME | 0 (`0x80000004`) | 1 (`0x80001004`, HOST:921-923) | HOST:921-923 → no poner el bit para este host. Solo cambia cuándo sale un DCS con vídeo activo (la PPS #2). | Baja |
| 11 | EOT RX_EOT_IGNORE | 1 (`0x11`) | 0 (HOST:937-940) | HOST:939 → `data \|= DSI_EOT_PACKET_CTRL_RX_EOT_IGNORE` (DT vendor `qcom,mdss-dsi-rx-eot-ignore`). Solo lecturas BTA (posible pista del "DDIC mudo"); no causa negro. | Muy baja (negro) |
| 12 | ERR_INT_MASK0 / LANE_CTRL | `0x13e0391f` / `0x01000000` | `0x13ff3fe0` (HOST:943) / reset no medido | Paridad opcional; solo reporte de errores y selección de petición HS. | Muy baja |

**Empaquetado recomendado**: #1+#2+#3 juntos (las tres piezas del "mundo 30" vendor + PPS byte-exacta; cada una con readback:
`VID_CFG0/ACTIVE_H/TOTAL/VIDEO_COMPRESSION_MODE_CTRL` en el `UKE-L68` de HOST:1176-1181, INTF en HINTF, y el volcado de la PPS completa
en vez de 5 bytes). #4 en el mismo ciclo si se acepta un quirk de 2 líneas (tiene readback trivial). #5-#7 como segundo ciclo o
combinados con el C2 de `PLAN-KERNEL-PANTALLA` (PPS única post-0x29 y vídeo después). Lo de secuencia (VID_MODE_EN desde pre_enable,
PPS ×2, DCS 0x05/0x15) no es de registros y está en DCS-COTEJO.

**Medidas que faltan en nuestro lado** (para la próxima sesión viva, sin flash): VID_CFG0, CMD_DMA_CTRL, TRIG_CTRL, LANE_CTRL,
CLKOUT_TIMING_CTRL, VIDEO_COMPRESSION_MODE_CTRL, INTF_1/2 (0x000-0x070, 0x170, 0x25c) y DSC enc (0x00, 0x30-0x60). `/dev/mem` dio
EACCES en L74; la vía es un `pr_info` de readback en el propio kernel.

## H. Resumen (≤300 palabras)

Decodificados registro a registro el controlador DSI de los dos links (offset físico = mainline + 4), INTF_1/2, DSC_0/1 (encoder, ctl y
top), CTL/LM/MERGE_3D y la PPS vendor, y comparados con lo que programa nuestro árbol (L74/L75) y con lo poco medido en L70-L74.

1. **Formato de píxel del DSI.** Vendor VID_CFG0 `0x02009140` = RGB101010 + widebus, H 427 / TOTAL 572 (120 Hz). Nosotros: RGB888
   (PANEL:814) y, desde L71, widebus forzado OFF (HOST:841-852), lo que da H 534 / TOTAL 679 = 101 Hz. L70 tenía widebus con RGB888: el DSI
   consumía 24 de los 30 bit/pclk que manda el DPU, lo que encaja con el overflow `dddd1011`.
2. **INTF.** Con widebus ON y ceil(1600·8/30) = 427, la emulación de mainline reproduce el INTF vendor bit a bit (HSYNC 572, CONFIG2
   `0x1011`, DATA_HCTL 267). Hay que cambiar el /24 de PVID:144 por bpc·3 con ceil.
3. **PPS.** Con L73 coincide con la del vendor en 126 de 128 bytes. Solo difiere pic_width: el vendor manda **3200 en cada link** y
   nosotros 1600 (PANEL:432/623). Con 3200 la PPS sale idéntica. La PPS medida confirma además el quirk flb 13 / max_qp0 8.
4. **Encoder DSC.** Idéntico salvo ENC_DF_CTRL: vendor `0x095c1203` (initial_lines 3 y bit12) contra nuestro `0x095c0202`.
5. **Menores:** INTF_2 con timing engine ON (en el vendor solo va INTF_1), CLKOUT_TIMING_CTRL 0 en el vendor, bit23 de INTF_CONFIG,
   broadcast HW de comandos, DSC_CLK_CTRL, BLOCK_DMA, RX_EOT_IGNORE.

La PHY de 0x800 a 0x9ff es espejo exacto de 0x000-0x1ff, y su TIMING_CTRL ya coincide con L75.

Recomendación: aplicar juntos #1, #2 y #3, cada uno con su readback; #4 si se acepta el quirk.
