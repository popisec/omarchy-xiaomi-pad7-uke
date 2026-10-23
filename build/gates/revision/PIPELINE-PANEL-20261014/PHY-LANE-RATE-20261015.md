# PHY / lane-map / rate / contexto-BTA — 15-oct-2026 (solo lectura, 0 flash, 0 SSH)

L67 MEDIDO: 20 DCS-reads (0x0A/0B/0C/0D+0x04 ×2 links) post-PPS en `o82_enable`, vídeo ON →
todas `ret=0`, 0 bytes, ambos links. PLLs lock (vco 951.35M, byte0 118.919M,
pclk 158.558M=vendor), 0 underruns, rails on, KTZ luz OK, writes `err=0`.
Vendor también falló sus lecturas bajo splash ("Panel not initialized", cell_id rc=-22).

## A) PHY: qué bindea y qué diverge (veredicto por candidata)

Bindeo MEDIDO: ctrl `qcom,mdss-dsi-ctrl` → DSI 6G **v2.8** → `sm8650 cfg + 6g_v2 ops`
(`dsi_cfg.c:341-342`, `calc_clk_rate_6g`); PHY `qcom,palawan-dsi-phy-4nm` → fallback
`dsi_phy_4nm_8650_cfgs`, `QUIRK_V5_2`, mismo `dsi_7nm_phy_enable` (`dsi_phy_7nm.c:958`).
Vendor: `qcom,dsi-phy-v5.2` + `dsi_pll_4nm`, SSC on down-spread
(`stock2-Cliffs7P-uke.dts:15827-15844`).

| Divergencia | Estado | ¿Explica "sordo total"? |
|---|---|---|
| VREG 0x44/0x19, RESCODE 0x3c/0x38, HSTX 0x88, LPTX 0x55, CTRL_2 0x40 | **Coinciden** (NOTAS:3991) | No |
| `clk-strength 0xff` / `phy-voltage 0x51` (props panel) | Mainline las **ignora** (grep=0 en `msm/`); el tuning real va por `platform-strength-ctrl=[55 03…]` por-lane, no comparado registro a registro | Posible, no probado |
| LANE_CFG 0x21/0x84 vs 0xAA/0xAA | **REFUTADA con control L40-vs-L41** (`docs/historia/revision/PIPELINE-PANEL-20261014/REVIEW-S5.md:10-11`) | No |
| SSC off vs on | **REFUTADA con control L40-vs-L42** (`docs/historia/revision/PIPELINE-PANEL-20261014/REVIEW-S5.md:10-11`) | No |
| LANE_CTRL0 0x1F vs 0x15 | Abierta, sin test | Débil sola |
| 14 TIMING_CTRL: calculados `@951M` (`dsi_phy.c:374-471`) vs **fijos del DT** `00 27 0a…0f` (`timing@120`, vía `timing_val_v5_0`+`commit_phy_timing`) | Abierta. Son timings **RX** (settle/trail): writes-LP OK + reads-RX cero bytes encaja exactamente | **Candidata nº1 (P≈0.4)** |
| Widebus ACTIVE_H 0x01CB0020 (H=427) vs vendor 0x02360020 (H=534) | Abierta (`dsi_host.c:798-804,1062-1071`; vendor sin rama widebus, `docs/historia/revision/PIPELINE-PANEL-20261014/L67-PREP.md:52-58`). Registro de **timing de vídeo**: explica "sin contenido", **NO** explica BTA sordo | Nº1 solo para vídeo (P≈0.15 conjunta) |

**Cambio mínimo candidata nº1:** programar los 14 `TIMING_CTRL` con los 14 bytes del DT
vendor (1 tabla en `dsi_7nm_phy_enable`, tras el cálculo, o quirk `USE_DT_TIMINGS`).
0-flash previo: ninguno posible (solo lectura de registros tras commit).

## B) Link rate: de dónde salen 118.9M; forzar 148.6M

Cadena MEDIDA en código (`dsi_host.c:589-637,639-660`): modo full 967428 kHz →
`adjust_pclk_for_compression` (1600px/link×8/30 → H'=427) → pclk/link **158558400**
(=vendor 158558666, Δ266 Hz) → `byte = pclk×24/(8×4lanes)` (bpp=24 RGB888) =
**118918800 Hz**; `bitclk = byte×8` = 951.35M (`:2444-2446`). Vendor: `C/8` con
C=`panel-clockrate` 1189190000 → byte **148648750**, bitclk 1189.19M
(`INFORME-MODO-OPP-DSC §1.3`, debugfs stock). **Vivo L67: byte0=118.919M** ⇒ el link
corre al pedido (el ceil-OPP a 187.5M de `HALLAZGO-OPP` **no se materializó**: R1
REFUTADO como causa actual; timings calculados y ejecutados coherentes @951M).
El vendor dimensiona con bpp=30/bitclk (+33% margen); mainline con payload
comprimido (+6% margen): el link va **−20% bajo lo validado** por el DDIC.
Forzar 148.6M: **1 línea DT** (`opp-148648750` en `mdss_dsi_opp_ml`) haría a
`dev_pm_opp_set_rate(118918800)` aterrizar en 148.65M — PERO resucita el mismatch
R1 (timings @951M corriendo @1189M, 4/7 bajo mínimos MIPI). Riesgo medio-alto sin
recalcular timings post-OPP. No hacerlo antes de agotar A (timings-RX) y C.

## C) Contexto BTA: el vendor lee con vídeo OFF; nosotros con vídeo ON

Mainline MEDIDO: `prepare_prev_first=true` (`o82:938`) ⇒ orden enable:
host `pre_enable` (`dsi_manager.c:282-324`: `power_on` + `msm_dsi_host_enable` que
pone `DSI_CTRL_VID_MODE_EN` en `dsi_op_mode_config`, `dsi_host.c:1158-1183`) →
panel `prepare` (rails/reset/DCS) → panel `enable` = **`o82_enable` con BTA**
(vía `panel_bridge_atomic_enable`, `bridge/panel.c:131-148`). **No existe ventana
"vídeo OFF + panel alimentado+display-on" en el path de enable.**
Vendor MEDIDO (`dsi_display_enable.c` decomp + orden de calls en
`disasm-coldpath/dsi_display_enable.s`): reads diagnósticas (build_id ~call 162/296,
gamma 196) **antes** de `panel_enable` (255) y `update_pps` (322);
`dsi_display_vid_engine_enable` al **final** (offset 5373). ⇒ el vendor **sí lee con
vídeo OFF**. Si el DDIC NAKea BTA con stream activo, L67 es falso negativo.

**Diseño L68 (mínimo, 1 hunk + 1 helper):** exportar en `dsi_host.c` junto a
`dsi_op_mode_config:1158` un `msm_dsi_host_video_engine_set(host,bool)` (clear/set
bit `DSI_CTRL_VID_MODE_EN` de `REG_DSI_CTRL`; declarar en `dsi.h`); en `o82_enable`
envolver el bloque L65: engine OFF en ambos hosts → `usleep 100` (~25 líneas de
vídeo) → 20 reads → engine ON. Sin nueva API no hay acceso a registros desde el
panel. Controles: repetir con vídeo ON en el mismo boot (A/B intra-boot); juzgar
por `ret` por link (`CRITICA-L67 I1–I3`: 0x0B/0x0C/0x0D con `ret==1` valen aunque
el byte sea 0x00).
