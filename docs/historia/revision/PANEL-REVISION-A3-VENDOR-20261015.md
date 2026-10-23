# PANEL-REVISION-A3 — TABLA DE VERDAD DEL VENDOR (o82, SM7675/palawan) — 15-oct-2026

> Solo lectura local: `build/vendor-re/decomp/` (3328 .c, dirección base en línea 1 de cada
> fichero) + `build/vendor-re/disasm-coldpath/` + DTBO extraído
> `build/evidencia/android-snap/dt-r15/soc/qcom,mdss_mdp@ae00000/qcom,mdss_dsi_o82_36_02_0a_dualdsi_dsc_vid/`
> (variante de fábrica con `mi,panel-id = 004f38325036020a`). Cero dispositivos, cero ejecución.
>
> **No repite** lo ya cerrado en GAPLIST-VENDOR-MAINLINE (G1–G10), RE-ANDROID-GAPS (§1–5),
> ANGULO-DDIC (C1–C8), CRITICA-L67 y PHY-LANE-RATE §A–C; los cita como "ya conocido".
> **NUEVO** = hallazgo no escrito antes en ningún informe; **SEMI** = dato conocido, dato
> nuevo al lado. [M]=medido en fichero:línea o dirección; [H]=hipótesis.

---

## 1. SECUENCIA DE INIT COMPLETA DEL VENDOR (pseudocódigo, orden real)

Fuente del orden: `dsi_bridge_pre_enable` (decomp `dsi_bridge_pre_enable.c`, 002f55d4):
`dsi_display_set_mode → dsi_display_prepare → dsi_display_enable → dsi_display_splash_res_cleanup`.
Dentro de prepare, `dsi_display_prepare.c` (002ff604), llamadas en orden de líneas 100–320.

```pseudocódigo
# ===== dsi_display_prepare (002ff604) =====
dsi_ctrl_clk_cb_register(ctrl0); dsi_phy_clk_cb_register(phy0)          # líneas 100-112
dsi_ctrl_clk_cb_register(ctrl1); dsi_phy_clk_cb_register(phy1)          # 116-125 (dual-DSI)
ctrl0.isr_ready_flag(+0x711) = 0 ; ctrl1.+0x711 = 0                     # 146-152
dsi_ctrl_isr_configure(ctrl0,1); dsi_ctrl_isr_configure(ctrl1,1)        # 157-162  [si no splash]

# ---- dsi_panel_pre_prepare (0030f7c8) ----
dsi_pwr_enable_regulator(panel.power_cfg(+0xaa), ON)                    # rails SIEMPRE en cada prepare (pre_prepare.c:17/24)
dsi_panel_reset(panel)                                                  # pre_prepare.c:56
  # dsi_panel_reset (003102b8): secuencia del DT qcom,mdss-dsi-reset-sequence:
  #   (nivel 0, 10 ms) → (1, 3 ms) → (0, 3 ms) → (1, 15 ms)             # reset.c:34-49, usleep(ms*1000, ms*1000+100)
  # después: enable_gpio(+0x5a4) → 1 (reset.c:64-70)
  #          mode_gpio(+0x5e4) ← tabla UNK_0018a060[nivel-1]          # reset.c:74-87

dsi_display_clk_ctrl(clk_mngr, LINK_CLKS(1), ON)                        # prepare.c:171
dsi_display_phy_sw_reset(display)                                       # prepare.c:173
  # dsi_ctrl_hw_cmn_phy_sw_reset (002e777c): DSI_SOFT_RESET(0x12C) ← 0x1000001;
  #   usleep(0x418958 ns≈4.3 ms); ← 0 ; usleep(0x68dbc ns≈0.43 ms)
dsi_display_phy_enable(display)                                         # prepare.c:174 (LP11)
dsi_ctrl_host_init(ctrl0, splash?) ; dsi_ctrl_host_init(ctrl1, splash?) # prepare.c:195-198
  # host_setup (002e73cc): LANE_CFG(0x84)←(ec_bits<<28|te_bpp<<24|esc_mode<<4|0x100 actual)
  #   SPLIT_LINK(0x330) SOLO si host_cfg+0x38 (o82: NO, ya conocido RE-GAPS §1)
  #   0xC4←(tclk_post<<8|tclk_pre)&0x3f3f ; 0xCC←te bits ; CLK_CTRL(0x11C)←0x23F
  #   CTRL(0x004)← eot_append<<24|eot_ignore<<20|... |0x100 ; 0x2D8←1 si video_engine
registro de handlers de error (prepare.c:240-262):
  work: FIFO_UNDERFLOW(+0x518) FIFO_OVERFLOW(+0x548) LP_RX_TIMEOUT(+0x578)
  por ctrl: callback +0x418 = dsi_display_cb_error_handler
dsi_ctrl_set_host_engine_state(ctrl0,1,splash) ; ctrl1 idem              # 276-296 = CTRL_ENABLE (0x004 bit0)
  # dsi_ctrl_hw_cmn_ctrl_en (002e85a4): CLK_CTRL(0x11C) |= 0x200B3F → dsb → CTRL(0x004) bit0 ← 1
  #   → dsb → restaurar 0x11C (pulso de clocks)
dsi_display_clk_ctrl(clk_mngr, CORE(2), ON)                             # prepare.c:298
dsi_display_soft_reset(display)                                         # prepare.c:300
  # = dsi_ctrl_hw_cmn_ctrl_reset (coldpath 12f7e0): CTRL bit1 (VID_EN) off → dsb →
  #   CLK_CTRL(0x11C) ← 0x01000A00 → SOFT_RESET(0x118) ← 1 → dsb → ← 0 → dsb → 0x11C ← 0 → CTRL bit1 restore
dsi_panel_prepare(panel)                                                # prepare.c:303
  # = dsi_panel_tx_cmd_set(panel, 0) = cmd_set[0] = BLOB INIT: 108 comandos del DT
  #   (qcom,mdsi-dsi-on-command, 1632 B, timing@120): páginas vendor 0xFF/0xFB,
  #   bloque DSC del DDIC 0x90=03 / 0x91(17B ab280018d20002b2029f000b048602dc) /
  #   0x92=10f0 / 0x9D=01, 0x51=0x0FFF, 0x53=0x24, 0xB3=0x40 + 0xB2=0x91 (timing 120 Hz),
  #   0x11 (sleep-out) con delay 120 ms, y 0x29 (display-on) al final del blob.

# ===== dsi_display_enable (00301270) =====
rama A (sin splash):                                                    # :70
dsi_panel_enable(panel)                                                 # :75 = cmd_set[1] (+gamma/csc MI)
  # dsi_panel_enable (00311028): round-corner, gamma, → dsi_panel_tx_cmd_set(1) = 0x29,
  #   y según panel-id: cmd_set[2]/[3] (HBM/AOD extras; o82 no entra)
mi_dsi_display_read_panel_build_id(display)   [SI flag +0xa0d; o82_36_02_0a: NO → skip]  # :99-101
dsi_panel_update_pps(panel)                                             # :103-110  *** PPS AQUÍ ***
  # dsi_panel_update_pps (0030fa54): rama DSC (+0x1c90):
  #   desc header: u32(+0x868) = 0x10A (dt 0x0A + flag), byte(+0x86C) = vc del dsc_cfg,
  #   u16(+0x86D) = 0x8000 (last-packet);
  #   sde_dsc_create_pps_buf_cmd(dsc_cfg(panel+0x1908), buf+3, 0, 128)
  #   dsi_panel_create_cmd_packets(1 pkt) → dsi_panel_tx_cmd_set(panel, 0x13)
dc_mode / dbi-by-temp (MI extras, o82 no)                               # :112-135
dsi_display_vid_engine_enable(display)                                  # :154
  # dsi_ctrl_set_vid_engine_state(ctrl,1,splash) (002ef904):
  #   si NO splash: video_engine_en (002e8520): CTRL(0x004) bit1 ← 1 (VÍDEO ARRANCA)
rama B (splash vivo: panel+0x40 | display+0x669):                       # :70→:164
  dsi_display_config_ctrl_for_cont_splash + dsi_display_splash_res_cleanup
  # NO rails, NO reset, NO init-DCS, NO PPS, NO engine-en (el ABL ya lo dejó corriendo)

# ===== dsi_display_post_enable =====
dsi_panel_post_enable (00311478): cmd_set[4] (qsync); para panel-id 4f38325036020a:
  cmd_set[0xf4] (dimming-on MI)
backlight: KTZ por I2C, gateado por qcom,bl-update-flag = "delay_until_first_frame"
  (primera escritura de brillo tras la 1ª trama; DT: init-level 0x133, min 4, max 0xFFF) — §7
```

**Respuesta directa a "¿qué manda el vendor al DDIC y en qué orden respecto al vídeo?":**
rieles → reset (10/3/3/15 ms) → [link clks → phy_sw_reset → phy_enable → host_init →
CTRL_EN → soft_reset] → 108 init-DCS (incluye 0x11+120 ms y **0x29** al final del blob) →
**PPS 128 B por 0x0A (cmd_set[0x13]) DESPUÉS del display-on y ANTES de encender el engine
de vídeo** → engine vídeo ON → backlight KTZ tras 1ª trama.

---

## 2. CONFIG DEL CONTROLADOR DSI — VALOR POR VALOR

### 2a. Relojes: dos dominios INDEPENDIENTES (NUEVO — ver §8-N1)

| Valor vendor | Dónde está el valor | Cita | Equivalente mainline |
|---|---|---|---|
| **bitclk/lane = 1.189.190.000 Hz** (DT explícito) | `timing@120/qcom,mdss-dsi-panel-clockrate = 0x46e19970` | DT dt-r15, fichero `qcom,mdss-dsi-panel-clockrate` (hex `46e19970`) | mainline NO lo lee: lo deriva. `dsi_host.c:639-683` (dsi_byte_clk_get_rate, con L70: bpp=dsc->bpc*3=30) |
| **byteclk = 148.648.750 Hz** = bitclk/8 | división /8 en `dsi_clk_set_byte_clk_rate`; fila de tabla `dphy_lb[18]={600M,1500M,div 1,1}` | `vendor-o82-dsi4nm.h:57-58`; PHY-LANE-RATE §B (debugfs stock) | `dsi_host.c:676` `pclk_bpp = mult_frac(pclk_rate, 30, 32)` = 148.648.400 Hz (Δ350 Hz). Con L70+L71 vigentes: OK |
| **pclk INTF = 158.558.666 Hz** = htot×vto×fps/1000 **con H'=427 (mundo 30)** | `dsi_convert_to_drm_mode` (002f28c0): `mode->clock = (htotal&0xffff)*(vtotal&0xffff)*framerate/1000` con htotal=572·... (1745/2 world) | decomp línea `*param_2 = ...*param_1[0xb])/1000` | `dsi_host.c:590-615` dsi_adjust_pclk_for_compression → 158.558.400 Hz (Δ266 Hz). Coincide (PHY-LANE-RATE §B) |
| **fill vs drain: margen 5,3 %** | fill = 534 px × 3 B / (534/158.5584 MHz) = 564,8 MB/s; drain = 4×148,649 = 594,6 MB/s | [M] aritmética sobre los dos relojes anteriores | [H] el par (pclk,byteclk) mainline cae en el mismo punto → margen igual |

**El "mundo 24" y el /24:** `dsi_ctrl_hw_cmn_set_video_timing` (002e7b3c, líneas 51-56):
```c
uVar7 = timing[0x64];                      // denominador (bpp bits del contenedor)
uVar6 = (timing[0x64] + timing[0x60]*hact - 1) / timing[0x64];  // H' = ceil(hact*8/24) = 534
*param_2 = uVar6;                          // el resto de la función usa H' ya escalado
```
**SEMI:** el 24 = bits del pixel-time del DSI (RGB888 sin widebus); el 8 = bpp DSC. H=534 ya
conocido (RE-GAPS §3, L71). **LO NUEVO [M] — hay DOS mundos de píxel para los mismos
bytes:** el DSI programa htotal **679** de pixel-times de 24 bit (534 activos ⇒ 534×3 B =
1602 B por línea), mientras el INTF/pclk vive en el mundo de 30 bit: `dsi_convert_to_drm_mode`
(002f28c0) hace `mode->clock = htotal×vtotal×fps/1000` con el htotal del mundo-30
(**572 = 16+16+427+113**) → 572×2310×120 = **158.56 MHz** (= pclk stock medido,
PHY-LANE-RATE §B). 427 px×30 bit = 1601,25 B ≈ los mismos 1600 B comprimidos que el DSI
manda como 534×24 bit = 1602 B. Línea real = 572/158,56 MHz = 3,608 µs (120,0 Hz), tramo
HS activo = 1602 B / 594,6 MB/s = 2,694 µs, porches = 0,914 µs (coherente con
traffic-mode non_burst_sync_event + BLLP en LP del DT). Por eso el vendor usa bitclk
independiente: drain (594,6) > fill (564,8) con margen de diseño del 5,3 %.

### 2b. Timings de vídeo — registros exactos (`set_video_timing.c` 002e7b3c, líneas 44-74)

| Reg | Escritura vendor | Valor o82 | Mainline |
|---|---|---|---|
| ACTIVE_H 0x24 | `writel((hbp+hsync)&0xffff \| ((hbp+hsync+H')<<16), +0x24)` | **0x02360020** (32 ‖ 566) | `dsi_host.c:1096-1124` (UKE-L68 imprime), mundo 24 tras L71: igual |
| ACTIVE_V 0x28 | `vbp+vsync \| (vbp+vsync+vact)<<16` | **0x08EC0094** (148 ‖ 2284) | igual |
| TOTAL 0x2c | `(hfp+hs_end)-1 \| (vfp+vs_end)-1<<16` | **0x090502a6** (678=679-1 ‖ 2309=2310-1) | igual (hfp 113, vfp 26) |
| HSYNC 0x30 | `hsync<<16` | **0x00100000** (16) | igual |
| VPOS 0x34 | 0 | 0 | igual |
| VSYNC 0x38 | `vsync<<16` | **0x00020000** (2) | igual |
| **HS_TIMER 0xbc** | `0x4bb80` fijo | 310.000 ciclos | mainline no existe el registro (H1) |
| **MISR 0xa4** | `0x10100` fijo | — | idem |
| **FLUSH 0x1e4** | `1` fijo | — | idem (los tres ya conocidos, PANTALLA §4; **nueva cita: se escriben AQUÍ, dentro de set_video_timing, incondicionalmente**) |
| **DSC-side 0x2a0** (solo rama DSC, líneas 30-46) | `(dsc+0x90 & 0x7ffffe)<<5 \| (dsc+0x98)<<16 \| (dsc+0x9c)<<4 \| 0xb01` | — | sin equivalente identificado; 0xb01 base + slice fields. **NUEVO como observación** (semántica exacta sin cerrar) |

Porches del DT (timing@120): hbp=16, hsync=16, hfp=113, vbp=146, vsync=2, vfp=26; width 1600
(link), height 2136; `qcom,mdss-dsi-bpp = 0x1e (30)` con dst-format 24 (NUEVO-dato: el DT
del vendor declara bpp=30 para el modelo de tráfico; `dsi_panel_get_mode.c:146-156`:
bpp≥8 → dst bits 0x18=24); traffic `non_burst_sync_event`; `bllp-power-mode` vacío = BLLP
en LP; `qcom,mdss-dsi-underflow-color = 0xff`; lane-states vacíos; `qcom,dsi-ctrl-num = 2`,
`qcom,dsi-phy-num = 2`, `display-topology = 2 2 2` (2 LM/2 INTF/2 enc, dual-DSI bonded,
sin split-link — ya conocido RE-GAPS §1).

### 2c. Lane/format/escape
Lane count 4 por link (`data-lanes <0 1 2 3>` en ambos endpoints del fork; vendor DT
`qcom,mdss-dsi-lane-*-state` × 4 vacíos = habilitados). Formato destino RGB888 (dst 24).
Escape: `0xC4←tclk_pre/post` (host_setup 002e73cc:34); `T_CLK_POST/PRE` del vendor vienen
del struct host_cfg, no de fórmula. **SEMI:** 14 bytes de PHY timings = fijos del DT
`00 27 0a 0a 1b 19 0a 0b 0a 02 04 00 20 0f` (ya conocido G6; PHY-LANE-RATE los tiene como
candidata nº1 de BTA-sordo, no de vídeo).

---

## 3. LA VÍA DE PPS 0x0A

- **Función exacta:** `dsi_panel_update_pps` (decomp `dsi_panel_update_pps.c`, 0030fa54).
  Rama DSC (mode_priv+0x1c90): `sde_dsc_create_pps_buf_cmd(panel+0x1908, buf+3, 0, 128)`;
  header del desc: `u32@0x868 = 0x10A` (tipo 0x0A + flag), `byte@0x86C = vc`,
  `u16@0x86D = 0x8000` (last-packet); tipo DCS **long-write 0x0A** =
  MIPI_DSI_PICTURE_PARAMETER_SET. **1 solo paquete** (`create_cmd_packets(…,1,…)`) enviado
  por `dsi_panel_tx_cmd_set(panel, 0x13)` — slot 19 = PPS (ya conocido RE-GAPS §2; cita
  reforzada).
- **Los 128 bytes NO están en el binario como tabla**: se generan en runtime desde el
  dsc_cfg parseado del DT (bpc 10, bpp 8, slice 800×24, scr 0, ver 1.1, block-pred vacío).
  Empaquetador: `sde_dsc_create_pps_buf_cmd` (002c6510) — VESA puro (idéntico esquema a
  `drm_dsc_pps_payload_pack`). Por tanto la PPS del vendor es funcionalmente la de
  PPS-COMPARA (nuestra L62/L63 ya byte-equivalente). **No hay PPS estática que volcar.**
- **¿Cuándo?** DESPUÉS del cmd_set[1] (0x29) de `dsi_panel_enable` y ANTES de
  `dsi_display_vid_engine_enable` (`dsi_display_enable.c` 00301270: orden de llamadas
  :75 → :103-110 → :154). **Con splash vivo NO se envía nunca** (rama B :164-216 no toca
  panel ni PPS). Nuestro port: PPS pre-en-prepare (panel-xiaomi-o82-dualdsi.c:394-455,
  L37/L62) **+** post-0x29 (:597+, L63) — el post-0x29 replica la posición vendor; el
  pre en prepare no existe en el vendor (inofensivo: LP antes de 0x11).
- **Readback DCS del vendor en el flujo normal: NO HAY.** [M] El nodo o82_36_02_0a:
  `mi,panel-build-id-read-needed` y `mi,feature-enabled` = **propiedades vacías** → el
  `mi_dsi_display_read_panel_build_id` de `dsi_display_enable.c:99` se salta. ESD por
  **GPIO** (`mi,esd-err-irq-gpio` + second), no por polling DCS. Las únicas lecturas
  definidas son de fábrica: `mi,mdss-dsi-panel-build-id-read-command = 06 01 00 01 00 00 01 DA`
  (RX_DCS_1 @ 0xDA) y `wp-read-command = 06 01 00 01 00 00 01 01` con pre-tx
  `39 00 00 00 00 00 02 FF 22` (page-switch 0xFF=0x22), len 3. **Ya conocido en parte**
  (PHY-LANE-RATE: el propio vendor falló sus reads bajo splash — "Panel not initialized").
  El BTA 0x04/0x0A del L67/L65 es una sonda NUESTRA, no parte del flujo vendor.

---

## 4. INTF/DSC DEL LADO MDP (DPU)

- **INTF compression:** vendor `sde_hw_intf_enable_compressed_input` (002a9b80):
  `INTF 0x60 (CONFIG2) |= 0x1000` (bit 12) si ver mayor ≥7 (o ==6 con 2º arg) — gate por
  versión HW. Mainline: `dpu_hw_intf.c:592-601` program_intf_cmd_cfg y `:203`
  (`INTF_CFG2_DCE_DATA_COMPRESS`, reg 0x060 en :41) — **paridad estructural**; el bit
  llega vía `timing->compression_en = dpu_encoder_is_dsc_enabled()` en
  `dpu_encoder_phys_vid.c:100`.
- **El DSC encoder del DPU:** `sde_hw_dsc_config` (002c0bfc): DSC_ENC = `nlanes&3 |
  (native_422&3)<<7 | ...`, y las constantes de sliect/flush por bpp (0x95c0000/0x12bc0000/
  0x257c0000/0x4ac0000 según native-420/422), PPS pane `dsc+0x7e<<28` etc. Equivalente
  mainline `disp/dpu1/dpu_hw_dsc.c` + `dpu_hw_dsc_1_2.c` (mismas fórmulas VESA).
- **El /24 no existe como divisor MDP**: se materializa una sola vez en el DSI host
  (`set_video_timing` §2a: H'=ceil(hact×8/24)) y en el modelo de reloj del DT (bpp=30 para
  byteclk, dst 24 para formato). El DPU programa el INTF con htotal=679/la mitad del modo
  y pclk 158,56 MHz (ambos lados derivan igual). **No hay registro MDP→DSI de "compresión"
  adicional**: solo CONFIG2.bit12 + el DSC block + el 0x2a0 del host (§2b).
- `sde_encoder_dce_setup.c` (00236e84 región 480-640): recalcula `dsc->pending_…`,
  chunk sizes y `sde_dsc_populate_dsc_private_params` (RC params en runtime) — equivalente
  mainline `dpu_hw_dsc_1_2.c` calc_rc_params. Sin desviación visible para 800×24×10bpc.

---

## 5. GESTIÓN DE ERRORES FIFO (por qué el vendor no inunda)

### 5a. ISR (`dsi_ctrl_isr.c` 002f0b14) — **NUEVO: anti-flood cuantificado**
- Lee INT_STATUS + ERROR_STATUS (`get_error_status` 002e90e0: compone de 0x0C/0x68/0xB4/
  0xC0/0x120/0x08) y **borra inmediatamente** (`clear_error_status` 002e9314).
- **Freno de inundación [M]:** jiffies base en ctrl+0x770, contador en ctrl+0x778.
  Si `now - base < 0xfa` (250 ms) y contador ≥ **0x10 (16)** → `bVar5 = flood` (evtlog
  ">=16 in <250ms"). Si la ventana venció: reset contador=1.
- Si **no** flood (o flag flood=0): re-arma `enable_error_interrupts` (+0x220 con 1).
- Si flood **y** ctrl+0x711 (panel listo): llama fn+0x108 = `dsi_ctrl_hw_cmn_ctrl_reset`
  (soft-reset del host, §1) **en lugar de re-armar**; y marca `display+0xa0 = true`
  (flood persistente visto por el display).
- Eventos al display vía `dsi_display_cb_error_handler` (003071b0): evento **1** = bajo
  0xf0000 (bits 16-19, FIFO) transitorio, **2** = 0xf00000 (bits 20-23), **3** = (0xe0&0xa0)
  → encolan UNDERFLOW / OVERFLOW / LP_RX_TIMEOUT works (prepare.c:240-262).
  Antes de encolar, **re-lee** el error y solo notifica si ya se limpió (transitorio).

### 5b. Handlers en workqueue — **NUEVO: receta de recuperación exacta**
- `dsi_display_handle_fifo_underflow` (00306a58): gate `panel_state+0x830 == 0` (no dead)
  y vídeo → `clk_ctrl(byte,ON)` → **`dsi_ctrl_soft_reset(ctrl0)` y `ctrl1`** (pulso 0x118,
  sin dormir) → `clk_ctrl(OFF)`; si flag panel_dead_enabled (+0x478):
  `sde_connector_schedule_status_work` + `sde_connector_report_panel_dead` (re-prepare
  completo por la vía ESD/panel-dead).
- `dsi_display_handle_fifo_overflow` (00306c44): solo video-mode (+0x4f4==1); si
  hw_version > 0x20020000: **`dsi_ctrl_reset(ctrl, 0x100000)`** (máscara de bits de CTRL a
  tumbar — incl. VID_EN) + **`dsi_phy_lane_reset(phy)`** ×2 links → notifica evento 2 →
  **`dsi_ctrl_vid_engine_en(ctrl,1)` re-arranca el stream** → `usleep(0xd1b78 ≈ 859 µs)`;
  si el flag de panel-dead: report_panel_dead.
- Mainline: `dsi_host.c:1636-1652` `dsi_err_worker`: si MDP_FIFO_UNDERFLOW →
  `dsi_sw_reset` (`:1159-1181`, baja DSI_CTRL_ENABLE, CLK_CTRL=ENABLE_CLKS, pulso
  **REG_DSI_RESET con msleep(20 ms)**, `:36`) → **re-arma siempre**
  `dsi_intr_ctrl(DSI_IRQ_MASK_ERROR, 1)` con **umbral 0 = nunca se rinde ni degrada**;
  no hay lane reset, no hay reporte panel_dead, no hay ventana de gracia.
  Mask de error IRQs mainline: `REG_DSI_ERR_INT_MASK0 = 0x13ff3fe0` (`:917`).
  Vendor `enable_error_interrupts` (002e9520): `0xb4←0x11111, 0xc←0xcccc0789,
  0xc0←0x11111111, 0x68←0x1193bfff, 0x120|=0x10000, 0x8|=0x80000000, 0x110/0x10c…`.

**Diferencia estructural [NUEVO-N3]:** el vendor nunca re-arma indefinidamente: 16
eventos/250 ms ⇒ deja de re-armar + soft-reset del host + (en overflow) lane-reset +
re-arranque del engine + panel_dead si persiste. Mainline = bucle cerrado
(sw_reset→re-arm) que si la causa raíz sigue, se re-dispara él mismo — eso es nuestro flood.

---

## 6. HANDOFF ABL→KERNEL (splash)

`~/gpu-work/abl-analysis/` está **vacío** (directorio de 12-sep sin contenido): no hay RE
del ABL que citar. La verdad del lado kernel vendor:

- `dsi_display_cont_splash_config` (002f9b00): `display+0x40 = 1` (cont_splash_enabled),
  `clk_mngr_update_splash_status(1)`, configura ISRs, `clk_ctrl(byte, ON)`,
  **`dsi_panel_bl_handoff`** (00308a00: lee el brillo vigente — KTZ ya programado por el
  ABL — y lo recoge como estado inicial).
- `dsi_display_enable` rama splash (00301270:70→164): **NO re-power rails, NO reset, NO
  init-DCS, NO PPS, NO engine-en**; solo `config_ctrl_for_cont_splash` + `splash_res_cleanup`.
- `dsi_panel_set_vid_engine_state`/`prepare` con splash: **no tocan hardware** (param_3
  splash → skip de writes, 002ef904).
- `sde_kms_handle_power_event` evento 8 (ya conocido GAPLIST G1): con splash_alive NO
  reprograma VBIF.
- **Estado que deja el ABL:** DSI 0/1 en vídeo HS con el modo 120 Hz ya programado, panel
  con init+PPS+0x29 latchados, KTZ con brillo encendido. El kernel vendor asume todo eso y
  solo toma el control de clocks/IRQs/backlight. [M vendor-side; el ABL mismo no está RE'd]

Consecuencia honesta para nuestro port: nuestro U-Boot no hace splash ⇒ cada arranque es
"cold path" completo; **no existe atajo vendor documentable** más allá de reproducir el
cold path §1 exacto.

---

## 7. BACKLIGHT KTZ8866 (solo lo que toca al vídeo)

- `dsi_panel_set_backlight` (003081b8) case 3 (external): para panel-id
  `4f38325042020b` **o mi-panel-id 0x11..0x13** (nuestro 36_02_0a cae aquí [H]): al bajar
  a 0 → `dsi_panel_tx_cmd_set(0xFC)` + `usleep(6 ms)`; al subir la 1ª vez →
  `dsi_panel_tx_cmd_set(0xFB)` (dimming-on vendor). El **0x51 DCS no se usa en runtime**
  (solo init 0x51=0x0FFF): brillo 100 % por I2C KTZ (ya conocido REV-KTZ8866-UKE).
- `ktz8866_backlight_update_status` (003485a4): remap `lvl<0x800: lvl*0x5ff/0x7ff`;
  `lvl≥0x800: (lvl*0x200-0x100000)/0x7ff+0x5ff`; luego `mi_bl_level_remap[]` y **escribe a
  TODOS los KTZ de la lista** (`ktz8866_dev_list`, bucle). **NUEVO-dato:** el vendor
  actualiza las DOS chips (i2c se0+se12) en cada cambio; nuestro DT/port solo referencia
  `ktz8866_0` (uke-display-o82.dtsi:105-116 deja ktz8866_1 comentado). No explica el
  flood, pero si una mitad del panel queda sin bias, negro parcial es posible.
- DT: `qcom,bl-update-flag = "delay_until_first_frame"` (timing node), bl-min 4,
  bl-max 0xFFF, init-level 0x133.

---

## 8. DIVERGENCIAS MAINLINE — SOLO LO NUEVO

**N1 (NUEVO, el más importante): pclk y bitclk son dominios INDEPENDIENTES en el vendor.**
El vendor NO deriva el byteclk del pclk: el bitclk lo toma del DT (0x46e19970/8) y el pclk
lo calcula como htot×vto×fps (`dsi_convert_to_drm_mode` 002f28c0). La línea se compone de
un tramo HS drenado a 594,6 MB/s (dominio byteclk) + porches contados a pclk; el margen
fill/drain de 5,3 % es una ELECCIÓN del DT, no un resultado de fórmula. Mainline DERIVA
`byte = pclk×bpp/(8×lanes)` (`dsi_host.c:676`) — con bpp 24 da 141,19 MHz (drain 564,8 =
fill exacto: **0 % margen → el flood de underrun medido**); con L70 (bpp=30) da 148,65 MHz
porque pclk quedó en el mundo-427 (158,56). **Riesgo latente [H]:** el L70 acierta el
número final (148,648 MHz ≈ vendor 148,649) pero por un camino dependiente de la fórmula
pclk; si la pclk mainline se separa de 158,5584 MHz (cambio de modo 90/144 Hz), el byteclk
vuelve a desviarse del DT. Robustez: fijar bitclk por DT/OPP a 1.189.190.000/8 (ya
esbozado en PHY-LANE-RATE §B como "1 línea DT") — la cita vendor de este informe es la
justificación canónica.

**N2 (NUEVO): el reset del host en error usa CLK_CTRL=0x01000A00 y pulso instantáneo.**
`dsi_ctrl_hw_cmn_ctrl_reset` (coldpath `dsi_ctrl_hw_cmn_ctrl_reset.s:45-62`):
CTRL.bit1(VID_EN) off → `0x11C ← 0x01000A00` (¡≠ 0x23F del host_setup!) → `0x118 ← 1/0`
con dsb, **sin ningún msleep**. Mainline `dsi_sw_reset` (`dsi_host.c:1159-1181`) usa
CLK_CTRL=ENABLE_CLKS y **msleep(20 ms)** por pulso (`:36`). Consecuencia: el vendor puede
permitirse resetear en cada evento de error (work) sin perder frames; el mainline pierde
20 ms por intento y aun así re-arma.

**N3 (NUEVO): freno anti-flood del vendor: 16 eventos/250 ms y después NO re-armar.**
`dsi_ctrl_isr.c:100-125` (jiffies+0x770, cnt+0x778, ventana 0xfa, umbral 0x10) + §5a/5b:
recuperación por capas (soft-reset host → lane reset + engine re-en → panel_dead →
re-prepare). Mainline: re-arm incondicional (`dsi_host.c:1649-1652`). Nuestro flood es
exactamente lo que el vendor prohíbe por diseño.

**N4 (NUEVO): el vendor NO hace readback DCS en el flujo normal de este panel** (§3:
build-id-read-needed/feature-enabled vacíos, ESD por GPIO) — el vendor opera el DDIC en
mono-directional salvo fábrica. Implicación: el BTA-sordo (L65 ret=0 ×20) **no contradice**
al vendor; su propio read bajo splash también falló (PHY-LANE-RATE). La sonda BTA debe
tratarse como diagnóstico nuestro, no como paridad.

**N5 (SEMI-NUEVO): `qcom,mdss-dsi-bpp = 0x1e (30)` en el DT del vendor** + dst 24 en el
driver (`dsi_panel_get_mode.c:146-156`). El "mundo 30" del byteclk no es un truco de
mainline: es la declaración del vendor para el modelo de tráfico; el 24 es el formato de
destino. Legitima L70 pero además sugiere que `dsi_panel_calc_dsi_transfer_time` vendor
usa 30 bpp (colas/BLLP dimensionadas al 125 %) — mainline dimensiona BLLP con bpp
contenedor 24 (`dsi_host.c:1601-1616`, límite de cmd-in-BLLP): [H] comandos largos en LP
durante vídeo podrían no caber donde el vendor los permite.

---

## 9. HIPÓTESIS DE FLOOD PERPETUO (ranked, con test)

1. **[H-A, reforzada por N1] Margen fill/drain = 0 o negativo en el estado actual.**
   Si en el arranque vivo el byteclk real no es 148,65 MHz (p. ej. OPP ceil a 118,9 o el
   dev_frec del PLL redondea), drain < fill ⇒ underrun perpetuo con sw_reset×re-arm
   mainline = flood. **Test 0-flash:** `clk_summary` byte-intf de ambos links; el valor
   DEBE ser 148.648.750±Δ (vendor). Ya listado como hueco mayor en ANGULO §3 paso 0.
2. **[H-B, N3] Aunque el reloj sea correcto, cualquier underrun transitorio se convierte
   en flood porque mainline re-arma sin freno** (16/250 ms inexistente) y sin lane-reset.
   **Test 1-flash:** portar el freno (contador+ventana+no-re-arm) y medir si el flood
   se detiene solo. Riesgo bajo, puramente software.
3. **[H-C] El ACTIVE 534×24-bit se drena bien pero el INTF alimenta en el mundo equivocado
   si `compression_en` no llega al INTF o el DSC del DPU no declara slice 800×24** ⇒ el
   DCE mete bytes a ritmo de no-comprimido. **Test 0-flash:** leer INTF_CONFIG2 (0x60+io)
   bit12 tras enable (ya diseñado como discriminante en CRITICA-L67 B1 para ACTIVE_H; mismo
   acceso) + `dmesg` DPU dsc. Vendor escribió bit12 siempre que DSC (§4).
4. **[H-D] HS_TIMER/FLUSH ausentes (PANTALLA §4, ya conocido) + BLLP-LP vs LP11 porches**:
   sin HS_TIMER (0x4bb80) el motor no tiene deadline de HS; con el 5,3 % de margen y una
   línea de 3,6 µs, cualquier jitter de arbtraje DPU sin HS_TIMER + sin FLUSH drena tarde.
   Los tres writes viven EN set_video_timing (§2b): port barato como quirk (3 escrituras).
5. **[H-E, ya candidato PHY-LANE-RATE §A] Los 14 TIMING_CTRL** explican BTA-sordo más que
   vídeo; si A-D caen, recalcular timings al byteclk real post-OPP.

---

## 10. FICHEROS TOCADOS

Creado: `docs/historia/revision/PANEL-REVISION-A3-VENDOR-20261015.md` (este). Nada más.
Fuentes citadas: `build/vendor-re/decomp/*.c` (direcciones 00xxxxxx en cabecera de cada
fichero), `build/vendor-re/disasm-coldpath/dsi_ctrl_hw_cmn_ctrl_reset.s`,
`build/vendor-re/vendor-o82-dsi4nm.h`,
`build/evidencia/android-snap/dt-r15/soc/qcom,mdss_mdp@ae00000/qcom,mdss_dsi_o82_36_02_0a_dualdsi_dsc_vid/**`,
`build/kernel-pokes/k52-L16-tree/drivers/gpu/drm/msm/dsi/dsi_host.c`,
`.../drivers/gpu/drm/msm/disp/dpu1/dpu_hw_intf.c`, `.../dpu_encoder.c`,
`.../drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c`.
