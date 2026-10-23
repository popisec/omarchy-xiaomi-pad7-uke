# RE-DSI-ENABLE-ORDER — orden de encendido DSI+DPU: vendor (msm_drm.ko 6.1) vs mainline (árbol L73-L75)

Fecha 17-oct-2026. Solo lectura (decompilado + volcados + trazas ya cosechadas). Sin adb/fastboot/flash/compile.

Fuentes:
- **V-dec**: `build/vendor-re/decomp/*.c` (Ghidra sobre `msm_drm.ko`; binario `build/android/vendor-static-display-20261017/modules/msm_drm.ko`).
- **V-reg**: `build/android/vendor-harvest-20261017b/full-dsi{0,1}-ctrl-reg.txt` (offsets FÍSICOS vendor) y `dpu/sde-blocks-raw-awake.txt`.
- **V-ft**: `panel-on-timeline.txt` (ftrace, ms desde vsp ON). **V-kp**: `kprobe/trace-kprobe-offon.txt` +
  `kprobe/dsi-cmds-decoded.txt` + `kprobe/sde-enable-writes.txt` (ms desde MARK_WAKE = 33575.009569; mismo reloj en los tres:
  lo comprobé alineando `uke_dsitx` con `sde_evtlog` del propio trace).
- **HOST** = `build/kernel-pokes/k52-L16-tree/drivers/gpu/drm/msm/dsi/dsi_host.c`, **MGR** = `.../dsi/dsi_manager.c`,
  **PANEL** = `.../gpu/drm/panel/panel-xiaomi-o82-dualdsi.c`, **PVID** = `.../msm/disp/dpu1/dpu_encoder_phys_vid.c`,
  **ENC** = `.../dpu1/dpu_encoder.c`, **HINTF** = `.../dpu1/dpu_hw_intf.c`, **ATOM** = `.../msm/msm_atomic.c`,
  **HLP** = `.../gpu/drm/drm_atomic_helper.c`.

Regla de offsets: mainline 6G suma `io_offset = DSI_6G_REG_SHIFT` (4) → **físico vendor = mainline + 4**
(p. ej. vendor 0x010 VIDEO_MODE_CTRL = mainline `REG_DSI_VID_CFG0` 0x00c; vendor 0x2a0 = mainline
`REG_DSI_VIDEO_COMPRESSION_MODE_CTRL` 0x29c). En DPU, los `blk=` del kprobe son relativos a MDSS (= catálogo mainline + 0x1000):
0x16000 = CTL_0, 0x36000 = **INTF_1** (maestro), 0x37000 = **INTF_2**, 0x81000 = DSC (enc 0 en +0x100, enc 1 en +0x200).

---

## 1. Camino vendor reconstruido (orden exacto)

La tabla de ops `dsi_ctrl_hw` sale de `dsi_catalog_cmn_init.c` (hw = ctrl+0x60, así que `ctrl+X` → `hw+(X-0x60)`):
+0xa8 host_setup, +0xb0 video_engine_en, +0xc0 video_engine_setup, +0xc8 set_video_timing, +0xe8 ctrl_en,
+0x108 soft_reset, +0x110 setup_lane_map (hw_22), +0x198 enable_status_interrupts, +0x1b0 enable_error_interrupts,
+0x250 vid_engine_busy. `dsi_catalog_ctrl_setup.c` pone `widebus_support` (hw+0x23a) = 1 para la versión de ctrl de índice 4-7
(la nuestra).

Cadena DRM: `dsi_bridge_pre_enable` (V-dec `dsi_bridge_pre_enable.c`) hace **set_mode → dsi_display_prepare →
dsi_display_enable** (este último incluye el VIDEO ENGINE ON), y solo después corre `sde_encoder_virt_enable`. El
`dsi_bridge_enable` hace `dsi_display_post_enable` (cmd set 4/0xf4, backlight).

Tiempos: **ft** = V-ft (ms desde vsp ON); **kp** = V-kp (ms desde MARK_WAKE; vsp ON = kp 103.019, así que kp−103.0 ≈ ft con
~±3 ms de varianza entre las dos capturas).

| # | Función (V-dec) | Registro(s) físico vendor ← valor | ft | kp | vs DCS/PPS |
|---|---|---|---|---|---|
| P0 | `dsi_display_prepare` evtlog 0x1111 (`dsi_display_prepare.c` :8748 del evtlog) | — | — | 99.851 | antes de todo |
| P1 | `dsi_panel_pre_prepare` (`dsi_display_prepare.c:160`) | vsp, vsn (+GPIO 407/431/408) | +0 / +2.5 | 103.0 / 105.6 | antes |
| P2 | `dsi_display_clk_ctrl(CORE,ON)` (:167) → `dsi_display_phy_sw_reset` (:171) → `dsi_display_phy_enable` (:173) | PHY (tabla L75) | (2.9-8.6) | — | antes |
| P3 | `dsi_ctrl_host_init(ctrl0)` y `(ctrl1)` (:195/:198) → (no splash) en este orden: | | | | antes |
| P3a | `dsi_ctrl_hw_22_setup_lane_map` | 0x310 ← one-hot por carril (volcado **0x00008421**) | | | |
| P3b | `dsi_ctrl_hw_cmn_host_setup` (`:11-42`) | 0x084 TRIG_CTRL ← RMW (TE bit31 + DMA/MDP trig) → **0x80000004**; 0x0c4 CLKOUT_TIMING ← clk_post/pre del host cfg → **0x00000000**; 0x0cc EOT ← **0x11**; 0x11c CLK_CTRL ← **0x23f**; 0x004 CTRL ← RMW lanes(0xf0)\|CLK_EN(0x100) (ENABLE=0) | | | |
| P3c | `dsi_ctrl_hw_cmn_video_engine_setup` (`:15-19`) | 0x010 VIDEO_MODE_CTRL ← **0x00009140** (DST_FORMAT=4 RGB101010 de `video_mode_format_map`, traffic 1, BLLP/EOF_BLLP stop); 0x020 VIDEO_MODE_DATA_CTRL ← 0; 0x1e8 TIMING_DB_MODE ← 0 | | | |
| P3d | `dsi_ctrl_hw_cmn_set_video_timing` (`:46-74`) | **0x2a0 VIDEO_COMPRESSION_MODE_CTRL ← 0x03200b51** (`(ppl&~1)<<5 \| eol<<4 \| bytes_per_pkt<<16 \| 0xb01`); **0x010 \|= 0x02000000 (WIDEBUS, si `widebus_support`) → 0x02009140**; H activo recalculado `ceil(num·h/den)` = 427; 0x024 ACTIVE_H ← 0x01cb0020; 0x028 ACTIVE_V ← 0x08ec0094; 0x02c TOTAL ← 0x0905023b; 0x030 HSYNC ← 0x00100000; 0x034 ← 0; 0x038 VSYNC_VPOS ← 0x00020000; 0x0bc HS_TIMER ← 0x4bb80; 0x0a4 MISR_VIDEO ← 0x10100; 0x1e4 TIMING_FLUSH ← 1; evtlog `0x905\|0x23b` | **+8.6** | **111.50 / 111.53** (ctrl0, ctrl1) | antes |
| P3e | `enable_status_interrupts(0)`, `enable_error_interrupts(0xff00a0/e0)` | limpia 0x0b4/0x00c/0x0c0/0x068/0x120/0x008; 0x110 INT_CTRL; **0x10c ERR_INT_MASK0 ← 0x13e0391f** | | | antes |
| P4 | `dsi_ctrl_set_host_engine_state(ON)` maestro y luego esclavo (:267/:277) → `dsi_ctrl_hw_cmn_ctrl_en` | 0x11c ← 0x23f\|0x200b3f (forzado) ; **0x004 CTRL \|= ENABLE → 0x1f1**; 0x11c ← restaurado | — | 115.807 / 115.813 | antes |
| P5 | `dsi_display_clk_ctrl(LINK,ON)` (:293) | byte/pixel/esc DSI ON | **+10.7** | — | antes |
| P6 | `dsi_display_soft_reset` (:300) → `dsi_ctrl_hw_cmn_soft_reset` | 0x004 &= ~0x7; 0x11c forzado; **0x118 RESET 1→0 (sin sleep)**; restaura 0x11c y 0x004 (0x1f1) | — | 116.183 / 116.192 | antes |
| P7 | `dsi_panel_prepare` (:303) → reset GPIO335 0/1/0/1 + cmd set PRE_ON (vacío) | GPIO 10/3/3 ms; **15.2 ms** desde el último release hasta el primer DCS | +10.8…+27.3 | 116.2…132.7 | antes |
| P8 | `dsi_display_prepare` evtlog 0x2222 | — | — | 147.849 | — |
| E0 | `dsi_display_enable` evtlog 0x1111 (`dsi_display_enable.c:68`) | — | **+42.4** | 147.851 | — |
| E1 | `dsi_panel_enable` (`:75`) → `dsi_panel_tx_cmd_set(ON=1)` | 104 DCS dt=0x39 LP por **broadcast HW** (0x03c CMD_DMA_CTRL bit31 + bit30 maestro en ctrl0); por cada paquete `dsi_ctrl_set_cmd_engine_state` 1/0 (0x004 bit2); `9d 01`, `b3 40`, `b2 91`, **0x11**, 120 ms, **0x29** | +42.4…+166.6 | 149.4 … 0x11 152.318 … **0x29 272.840** | DCS |
| E2 | `dsi_panel_tx_cmd_set(2)` (POST_ON, vacío) (`dsi_panel_enable.c:34`) | — | +167.0 | 273.031 | tras 0x29 |
| E3 | `dsi_panel_update_pps` (`dsi_display_enable.c:106`) → `tx_cmd_set(0x13)` | **PPS dt=0x0A, 128 B, LP, UNA vez, ambos links, pic_width 0x0c80 (3200)** | **+168.3** | 274.170 (paquetes 274.200 / 274.226 = **+1.36 ms tras 0x29**) | PPS |
| E4 | `dsi_display_vid_engine_enable` (`:154`) → `dsi_ctrl_set_vid_engine_state(1)` ctrl0 y luego ctrl1 → `dsi_ctrl_hw_cmn_video_engine_en` | **0x004 CTRL \|= VID_MODE_EN (bit1) → 0x1f3** (solo ese bit; `vid_engine_busy` solo se mira al apagar) | **+168.8** | **274.449 / 274.453** (+0.25 ms tras el último byte de PPS) | después de PPS |
| E5 | `dsi_display_enable` evtlog 0x2222 (`:254`) | — | +168.8 | 274.454 | — |
| D0 | `sde_encoder_virt_enable` | — | **+168.9** | 274.458 | después de VID ON |
| D1 | `sde_encoder_phys_vid_enable` del **esclavo** → `sde_hw_intf_setup_timing_engine` (INTF_2) | 0x37000: HSYNC_CTL 0x023c0010, VSYNC_PERIOD 0x142968, … DISPLAY/ACTIVE_HCTL 0x01ca0020, INTF_CONFIG 0x60800000, PANEL_FORMAT 0x213f, **CONFIG2 0x1011** (WIDEN\|DATA_HCTL_EN\|DCE_COMPRESS), DATA_HCTL 0x012a0020, MUX 0xf0001, PROG_FETCH 0x14272d, INTF_CONFIG 0x80800000 | | 274.582-274.648 | después |
| D2 | split config | MDP_TOP 0x2f4 SPLIT_DISPLAY_EN ← 1 | | 274.663 | |
| D3 | `phys_vid_enable` del **maestro** (INTF_1) | 0x36000: mismos valores, MUX 0xf0000 | | 274.668-274.730 | |
| D4 | CTL intf cfg | CTL_TOP 0xf0000000, INTF_ACTIVE 0x6, INTF_MASTER 0x2 | | 274.744-274.761 | |
| D5 | DSC (kickoff prep) | DSC enc0/enc1 (PICTURE_SIZE 0x08580c80, …), DSC_CTL, CTL_DSC_ACTIVE 1→3 | | 275.491-275.726 | |
| D6 | CTL flush | 0x104/0x100/0x110 flush regs; **CTL_FLUSH 0xa0c200c0** | | 276.003-276.008 | |
| D7 | `sde_encoder_phys_vid_handle_post_kickoff` → `sde_hw_intf_enable_timing_engine` | **INTF_1 TIMING_ENGINE_EN ← 1** (+ VSYNC_TIMESTAMP_CTRL 0x11). **INTF_2 NO**: el decomp salta el esclavo (`sde_encoder_phys_vid_handle_post_kickoff.c:39-40`: `enable_state==ENABLING && split_role != ENC_ROLE_SLAVE(2)`); volcado INTF_2 0x000 = 0 | | **276.128** (+1.68 ms tras VID ON) | después |
| D8 | `dsi_display_post_enable` → cmd set 4 y 0xf4 (`dsi_panel_post_enable.c:15,46`) | DCS HS `ff 10 / fb 01 / b2 91 / b3 40`; luego `55 00` (dt 0x15), `13 00`, `d1 28`…; KTZ8866 ×2 por I2C | +173…+182 | 277.056 … | con vídeo ya corriendo |

**Respuesta directa a "¿quién arranca primero?"**: el **VID_MODE_EN del DSI** (E4, kp 274.449) va **1.68 ms antes** que el
TIMING_ENGINE_EN del INTF_1 (D7, kp 276.128). Entre medias: toda la programación INTF/CTL/DSC y el flush. El DSI espera con
el motor de vídeo armado hasta que el INTF empieza a emitir.

Notas de detalle:
- **Widebus** del DSI va en **VIDEO_MODE_CTRL (0x010) bit 25** (`set_video_timing.c:49`), **no** en el registro de compresión.
  Lo escribe `set_video_timing` justo después de 0x2a0. En el INTF va en CONFIG2 bit0 (`sde_hw_intf_setup_timing_engine`/
  `sde_hw_intf_enable_wide_bus`).
- **VIDEO_COMPRESSION_MODE_CTRL2** (físico 0x2a4) no lo escribe nadie en vídeo (volcado 0). 0x2a8 `0x39003900` = COMMAND
  compression (valor de reset, sin EN); 0x2ac = 0.
- El motor de comandos se arma y desarma **por paquete** (`dsi_ctrl_set_cmd_engine_state` 1/0; CTRL bit2). Mainline hace lo
  mismo en `msm_dsi_host_xfer_prepare/restore` (HOST:2374-2378 / :2393): paridad.
- El vendor no tiene "phy ulps exit" en este camino (no hay ULPS en suspend ligero; la traza no muestra `ulps`).

## 2. Registros de compresión/widebus decodificados (V-reg, idénticos en dsi0/dsi1)

| físico | mainline | nombre | valor | decodificado |
|---|---|---|---|---|
| 0x004 | 0x000 | CTRL | 0x000001f3 | ENABLE, VID_MODE_EN, CMD_MODE_EN=0, LANE0-3, CLK_EN; ECC/CRC=0 |
| 0x010 | 0x00c | VID_CFG0 | **0x02009140** | VC 0, DST_FORMAT **4 = RGB101010**, TRAFFIC 1 (non-burst sync event), BLLP_STOP, EOF_BLLP_STOP, HSA/HBP/HFP_STOP 0, **bit25 DATABUS_WIDEN = 1**, PULSE_HSA_HE 0 |
| 0x024 | 0x020 | ACTIVE_H | 0x01cb0020 | start 32, end 459 → **427** (= ceil(1600·8/30)) |
| 0x02c | 0x028 | TOTAL | 0x0905023b | H_TOTAL−1 = 571 (periodo 572), V_TOTAL−1 = 2309 |
| 0x2a0 | 0x29c | VIDEO_COMPRESSION_MODE_CTRL | **0x03200b51** | EN 1, EOL_BYTE_NUM 1 (ver nota), PKT_PER_LINE 1 (log2: 2 pkt/línea), DATATYPE 0x0b, WC 0x320 = 800 |
| 0x2a4 | 0x2a0 | VIDEO_COMPRESSION_MODE_CTRL2 | 0x00000000 | no se usa en vídeo |
| 0x2a8 | 0x2a4 | COMMAND_COMPRESSION_MODE_CTRL | 0x39003900 | reset, EN=0 |
| 0x2ac | 0x2a8 | COMMAND_COMPRESSION_MODE_CTRL2 | 0x00000000 | — |
| 0x1e8 | 0x1e4 | TIMING_DB_MODE | 0x00000000 | doble buffer OFF (escrito por `video_engine_setup`) |

Nota EOL: el vendor calcula `eol_byte_num = bytes_per_line_por_intf % 3` = (2 slices × 800) % 3 = 1600 % 3 = **1**; mainline
(HOST:989-992) usa `slice_chunk_size × slice_count` = 800 × 2 = 1600 → 1: misma cifra; el valor completo `0x03200b51` es el que
`dsi_update_dsc_timing()` produce (HOST:975-1034), confirmado también en REGDIFF §A fila 0x2a0.

## 3. Mainline (árbol actual) en orden, y TODAS las diferencias

Cadena mainline (HLP:1759-1769 + ATOM:249-251/306):
1. `drm_atomic_helper_commit_crtc_enable`.
2. Bridge **pre_enable** (HLP:1645); con `prepare_prev_first = true` (PANEL:959) el DSI va **antes** que el panel:
   `dsi_mgr_bridge_pre_enable` (MGR:282-324) → `dsi_mgr_bridge_power_on` (MGR:213-263): PHY ×2 (MGR:151-166) →
   `msm_dsi_host_power_on` DSI0 y DSI1 (HOST:2677-2744: reguladores, `link_clk_set_rate/enable` :2708-2710,
   `dsi_timing_setup` :2725, `dsi_sw_reset` :2726, `dsi_ctrl_enable` :2727) → IRQ → **`msm_dsi_host_enable` DSI0 y DSI1
   (MGR:304/:311 → HOST:2630 → `dsi_op_mode_config` HOST:1256: CTRL |= VID_MODE_EN → 0x1f3)**.
   Luego el panel: `o82_prepare` (PANEL:355-510): rieles, reset (final **100 ms**, PANEL:291), 104 DCS, **PPS #1**
   (PANEL:413-463), `b3 40`/`b2 91` (:466-484), 0x11 + 120 ms (:486-488), 0x29 (:490-491).
3. Encoder **atomic_enable** (HLP:1732): `dpu_encoder_virt_atomic_enable` → esclavo y luego maestro (ENC:1367-1371) →
   `dpu_encoder_phys_vid_enable` (PVID:452-510) → `setup_timing_gen` (HINTF:112-272) + `setup_intf_cfg`; TE pendiente.
4. Bridge **enable** (HLP:1739) → `o82_enable` (PANEL:610-713): **PPS #2** ambos links (:636-638) + **12 lecturas BTA L65**
   (:672-693).
5. `flush_commit` (ATOM:306) → `dpu_encoder_prepare_for_kickoff` (DSC: ENC:2107) → CTL flush → `handle_post_kickoff`
   (ENC:2176-2177) → `dpu_encoder_phys_vid_handle_post_kickoff` (PVID:659-676) → **TIMING_ENGINE_EN=1 en TODOS los phys
   (INTF_1 y INTF_2)**.

### 3.1 Diferencias de ORDEN

| # | Diferencia | Vendor | Mainline (fichero:línea) | Plan |
|---|---|---|---|---|
| O1 | **Momento de VID_MODE_EN** | tras la PPS única, +0.25 ms (E4), y 1.68 ms antes del TE del INTF | en el pre_enable del bridge, **antes de rieles, reset y de los 104 DCS** (MGR:304,:311 → HOST:2630-2631 → HOST:1256); todos los DCS y las dos PPS salen con el motor de vídeo armado | **C2** |
| O2 | **Número y posición de la PPS** | 1 vez, +1.36 ms tras 0x29, antes del VID ON | 2 veces: #1 pre-0x11 dentro de prepare (PANEL:445-448) y #2 en enable (PANEL:636-638), esta última ya tras programar el INTF (paso 3) | **C2** (quitar #1) |
| O3 | **Lecturas DCS tras la PPS** | ninguna | 12 BTA (PANEL:672-693) entre PPS y kickoff | **C2** (quitar) |
| O4 | Retardo reset→primer DCS | 15.2 ms (kp 132.675 → 147.843) | 100 ms (PANEL:291) | **C4** |
| O5 | PHY + relojes link + CTRL ENABLE respecto a los rieles | rieles → PHY → host_init → ENABLE → link clk → soft reset → reset GPIO (P1-P7) | PHY, link clk y CTRL=0x1f1 **antes** de los rieles del panel (MGR:225-252 en el pre_enable; rieles en PANEL:300-342 después) | no tocar (K48-A ya lo trató; carriles en LP11 con reloj no continuo) |
| O6 | Programación de timing vs ENABLE | timing (P3d) antes de ctrl_en (P4) y soft reset después (P6), sin sleep | timing (HOST:2725) → sw_reset con `msleep(20)` (HOST:1232) → ctrl_enable (HOST:2727). Mismo orden relativo; solo cambia el sleep | paridad |
| O7 | VID_CFG0 (formato/widebus) vs timing | VID_CFG0 en P3c, widebus OR en P3d (tras 0x2a0) | VID_CFG0 completo en `dsi_ctrl_enable` (HOST:862-881), **después** del timing/compresión (HOST:1126-1145). Inocuo: ENABLE=0 en ambos casos | paridad funcional |
| O8 | Orden de los INTF y del TE | INTF_2 regs → split → INTF_1 regs → CTL → DSC → flush → **TE solo INTF_1** | mismo orden de programación (ENC:1367-1371; DSC en ENC:2107; flush; post_kickoff), pero **TE también en INTF_2** (ENC:2176-2177 recorre todos los phys; PVID:665-674 sin mirar `split_role`) | **C5** (medir en L76; el decomp confirma que el vendor salta el esclavo) |
| O9 | VID ON maestro/esclavo | ctrl0 y luego ctrl1 (`dsi_display_vid_engine_enable`) | DSI0 y luego DSI1 (MGR:304/:311) | C2 debe conservar dsi[0] → dsi[1] |
| O10 | DCS de post-enable | `ff 10 / fb 01 / b2 91 / b3 40` en HS +0.9 ms tras el TE, después `55 00`, `13 00`, `d1 28` | no se envían | L77+ (no afecta al negro según lo medido; el DDIC ya tiene b2 91/b3 40) |
| O11 | Backlight vs primer cuadro | KTZ ×2 ~+6 ms tras VID ON (tras el TE) | `drm_panel_enable` enciende el backlight dentro del bridge enable, **antes** del flush/TE | anotar; C6 (KTZ dual) en L77 |
| O12 | Disparo de los DCS | broadcast HW: se preparan ctrl1 y ctrl0 y dispara el maestro (CMD_DMA_CTRL bit31/bit30) | dos commits SW seguidos (`msm_dsi_manager_cmd_xfer`, MGR:497-548) | no tocar en L76 (ver REGDIFF; C3 cubre el dt) |

### 3.2 Diferencias de VALOR implicadas en el camino (detalle en `docs/historia/revision/PANEL-REVISION-REGDIFF-VENDOR-20261017.md`)

| # | Registro / dato | Vendor | Mainline | fichero:línea | Plan |
|---|---|---|---|---|---|
| V1 | VID_CFG0 DST_FORMAT | 4 (RGB101010) | 3 (RGB888) por `.format` | PANEL:814 → HOST:877 | **C1** |
| V2 | VID_CFG0 bit25 WIDEN | 1 | 0 (L71 `return false`) | HOST:840-852, :879-880 | **C1** |
| V3 | ACTIVE_H / TOTAL | 0x01cb0020 / 0x0905023b | con widebus OFF: /24 → 534 | HOST:1110-1121 | **C1** (sale solo con V2) |
| V4 | INTF width/HSYNC | 427 / 0x023c0010, CONFIG2 0x1011, DATA_HCTL 0x012a0020 | ceil /24 → 534 | PVID:133-147 | **C1** |
| V5 | **PPS bytes 8-9 pic_width** | **0x0c80 = 3200 (ancho completo) en ambos links** (`dsi-cmds-decoded.txt:217-218`) | 0x0640 = 1600 (`dsc_link.pic_width = hdisplay/2`) | **PANEL:623** (y :432 en la PPS #1) | **NO está en C1-C4: añadir a C2** (con pic_width=3200 la PPS sale byte a byte igual, REGDIFF §D.1) |
| V6 | TRIG_CTRL BLOCK_DMA_WITHIN_FRAME | 0 (0x80000004) | 1 (0x80001004) | HOST:922-924 | irrelevante si los DCS van con vídeo OFF (C2) |
| V7 | CLKOUT_TIMING_CTRL | 0 | 0x0f20 (L75) | HOST:927-929 | readback; no tocar en L76 |
| V8 | EOT_PACKET_CTRL | 0x11 | 0x01 | HOST:937-940 | solo BTA (C2 quita las lecturas) |
| V9 | ERR_INT_MASK0 | 0x13e0391f | 0x13ff3fe0 | HOST:943 | no tocar (riesgo de flood de IRQ) |
| V10 | CMD_DMA_CTRL | 0xd0000000 / 0x90000000 (broadcast) | 0x14000000 | HOST:912-914 | ver O12 |
| V11 | Soft reset | sin espera | `msleep(20)` | HOST:1232 | inocuo |
| V12 | 0x310 (mainline 0x30c) lane map | 0x00008421 | no escrito | — | **readback** en L76 (no se sabe si es reset) |
| V13 | 0x1e8 (mainline 0x1e4) TIMING_DB_MODE | 0 | no escrito (L74 escribe FLUSH en 0x1e0) | HOST:1166 | **readback** en L76 |
| V14 | LANE_CTRL | 0x01000000 | no escrito (NON_CONTINUOUS, PANEL:812-813) | HOST:957-965 | readback; probablemente reset |
| V15 | INTF ACTIVE_HCTL/ACTIVE_V | = DISPLAY (pero ACTIVE_H/V_EN=0 en el INTF_CONFIG final 0x80800000) | 0 | HINTF:141-161 | sin efecto (EN=0 en ambos) |
| V16 | DCS dt | todo 0x39 | 0x15/0x05 para cortos | PANEL:225-262 | **C3** |

## 4. Orden objetivo L76 (encaja con C1/C2 del PLAN; añade V5)

1. **pre_enable DSI (MGR:282-324)**: PHY ×2, `msm_dsi_host_power_on` DSI0/DSI1 con **C1** (widebus ON HOST:841,
   `.format = RGB101010` PANEL:814) → `dsi_timing_setup` (0x29c=0x03200b51, ACTIVE_H 0x01cb0020, TOTAL 0x0905023b,
   L74 HS_TIMER/MISR/FLUSH) → `dsi_sw_reset` → `dsi_ctrl_enable` (VID_CFG0 **0x02009140**, CTRL 0x1f1).
   **`msm_dsi_host_enable` (HOST:2625) con DSC+vídeo: solo ENABLE, sin VID_MODE_EN** (C2-a). Gate: `UKE-L76: VID diferido id=%d
   CTRL=0x000001f1` ×2; readback extra (HOST:1176-1181) de VID_CFG0, 0x29c, 0x30c, 0x1e4 (esperado 0x02009140, 0x03200b51,
   0x00008421?, 0).
2. **`o82_prepare`**: rieles → reset con final **15 ms** (C4, PANEL:291) → 104 DCS **0x39** (C3) → `b3 40`, `b2 91` → 0x11 →
   120 ms → 0x29. **Sin PPS** (C2-b: borrar PANEL:413-463). Marcar `ktime` de 0x29.
3. **Encoder enable** (sin cambios): INTF_2 y luego INTF_1 con width 427 (C1, PVID:126-148). Gate `UKE-L76-INTF`
   (HSYNC 0x023c0010, VPER 0x00142968, DHCTL 0x01ca0020, CFG2 0x00001011, DATA_HCTL 0x012a0020).
4. **`o82_enable`**: PPS **una vez** por link (dsi[0], dsi[1]) en LP **con `dsc_link.pic_width = hdisplay` (3200)**
   (**C2-d nuevo**, PANEL:623; log `UKE-L76: PPS w=3200 PPS[8..9]=0C 80`), **sin lecturas L65** (C2-c, PANEL:672-693),
   y **inmediatamente** `msm_dsi_host_video_engine_set(dsi[0]->host, true)` y luego `dsi[1]` (C2-e, HOST:1271; esperado CTRL
   0x1f3; objetivo vendor: 0x29→PPS ≈1.4 ms, PPS→VID ≈0.3 ms).
5. **flush_commit** (ATOM:306): DSC (ENC:2107) → flush → TE. Gate de orden: `VID ON` < `INTF1 TE ON`, Δ≈1-3 ms
   (vendor 1.68 ms). **C5**: en L76 solo loguear `INTF%d TE ON` en PVID:672; el decomp (`handle_post_kickoff.c:39-40`) ya
   demuestra que el vendor **no** enciende el TE del esclavo → candidato firme para L77 (`if (phys_enc->split_role ==
   ENC_ROLE_SLAVE) skip`).
6. Fuera de L76: DCS de post-enable (O10), backlight tras el primer cuadro (O11), broadcast HW (O12), ERR_INT_MASK0 (V9).

Riesgo de C2-d: L59 ya mandó 3200 por link, pero con PPS mainline (flb 12), dos veces, widebus/INTF distintos y VID desde
pre_enable: no aísla la variable. La medida vendor es directa (bytes en el cable), así que debe ir junto a C2 (misma
filosofía "paridad medida"); si se quiere bisección, C2-d puede ir como parámetro `uke_l76_pps_full=1`.

---

## 5. Resumen (≤300 palabras)

Reconstruí desde el decomp el encendido del vendor y lo crucé con las trazas (ftrace y kprobe en el mismo reloj).
**prepare**: rieles → PHY → `host_init` por ctrl (lane map; host_setup: TRIG 0x80000004, CLKOUT 0, EOT 0x11, CLK_CTRL 0x23f;
video_engine_setup: VID_CFG0 0x9140 RGB101010, DB_MODE 0; `set_video_timing`: **0x2a0=0x03200b51**, luego **widebus en
VIDEO_MODE_CTRL bit25 → 0x02009140**, ACTIVE_H 427/TOTAL 0x0905023b, HS_TIMER/MISR/FLUSH) → ENABLE (CTRL 0x1f1) → relojes de
link → soft reset → reset GPIO. **enable**: 104 DCS broadcast, 0x11, 120 ms, 0x29 → **una sola PPS (+1.36 ms, pic_width
3200)** → **VID_MODE_EN ctrl0/ctrl1 (+0.25 ms)** → `sde_encoder_virt_enable` → INTF_2 y INTF_1 (CFG2 0x1011) → DSC →
CTL flush → **TE solo de INTF_1, 1.68 ms después del VID ON** (el decomp salta el esclavo). El DSI arranca primero.

Mainline arma VID_MODE_EN en el pre_enable, antes de rieles, reset y todos los DCS (MGR:304/311 → HOST:1256); manda la PPS dos
veces (PANEL:445-448 y :636-638), lee 12 registros por BTA tras la PPS, espera 100 ms tras el reset y enciende el TE de los dos
INTF (PVID:665-674). El orden DPU (esclavo→maestro, DSC antes del flush, TE en post_kickoff) ya coincide.

Diferencia de valor que falta en el PLAN: la **PPS vendor declara pic_width 3200 en cada link**; nosotros 1600 (PANEL:623).
Con 3200 la PPS es byte a byte idéntica.

Orden objetivo L76: C1 (widebus + RGB101010 + INTF 427) → pre_enable con ENABLE sin VID → prepare sin PPS, reset 15 ms,
DCS 0x39 → encoder enable → `o82_enable`: PPS única con pic_width 3200 + VID ON dsi0→dsi1 sin lecturas → flush → TE (y
medir el TE de INTF_2 para quitarlo en L77). Gates: CTRL 0x1f1→0x1f3, VID_CFG0 0x02009140, 0x29c 0x03200b51, VID < TE.
