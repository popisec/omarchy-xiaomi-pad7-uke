# PANEL-REVISION INV75b — Tabla PHY vendor byte-exacta + diseño del override L75 — 17-oct-2026

> Agente INV75b (ronda L75). Solo lectura + este informe; cero dispositivo, cero build.
> Fuentes: DTBO stock decodificado (`build/evidencia/android-snap/dt-r15/soc/qcom,mdss_mdp@ae00000/
> qcom,mdss_dsi_o82_{36_02_0a,42_02_0b}_dualdsi_dsc_vid/`), header vendor RE
> `build/vendor-re/vendor-o82-dsi4nm.h`, decomp CAF `build/vendor-re/decomp/`
> (`dsi_phy_hw_v4_0_commit_phy_timing.c`, `dsi_phy_hw_calculate_timing_params.c`, `calc_*.c`,
> `dsi_phy_hw_v4_0_cache_phy_timings.c`, `dsi_panel_get_phy_props.c`),
> árbol vivo `build/kernel-pokes/k52-L16-tree/drivers/gpu/drm/msm/dsi/phy/` (los parches
> `l73-panel-composite.diff` y `l74-hstimer-misr-flush.diff` NO tocan dsi_phy*.c ⇒ los números
> de línea valen para el L75), B4 (`docs/historia/revision/PANEL-REVISION-B4-PHY-LINK.md`), cosecha Android
> (`docs/historia/revision/ANDROIDE-COSECHA-20261017.md`). **CORREGIDO** = corrige una celda de B4; **NUEVO** = no
> escrito antes.

---

## 1. Tabla vendor extraída (bytes exactos)

La propiedad del panel es **`qcom,mdss-dsi-panel-phy-timings`** (14 bytes, u8) — NO existe en
este DTBO ni `qcom,mdss-dsi-panel-timings` legacy ni `-8550` ni `-phy-v2` (grep sobre todo
`dt-r15`: cero matches para "mdss-dsi-panel-timings"; la familia 4nm solo usa `-phy-timings`).

```
valor (hex): 00 27 0a 0a 1b 19 0a 0b 0a 02 04 00 20 0f
```

- Fuente primaria (ficheros volcados del dtbo): `…/o82_42_02_0b…/qcom,mdss-dsi-display-timings/
  timing@{120,90,144}/qcom,mdss-dsi-panel-phy-timings` — **14 B, idénticos en los tres modos**
  (120/90/144). La variante hermana `o82_36_02_0a` trae LA MISMA tabla en sus tres modos.
- Fuente secundaria (RE del msm_drm.ko): `vendor-o82-dsi4nm.h:91-94` (`o82_phy_timings[14]`),
  byte-idéntica. `qcom,mdss-dsi-panel-clockrate` = `0x46E19970` = **1.189.190.000 Hz** en los
  tres modos (la tasa del arranque vendor).
- Consecuencia: **una sola tabla sirve para todos los modos**; el gate por tasa (§4b) solo
  necesita cubrir la tasa de arranque (120 Hz).

## 2. Mapeo DT-vendor → registros mainline: IDENTIDAD

**CORREGIDO (hipótesis del encargo):** el orden del CAF para v4/v5 NO es el legacy
`[clk_pre, clk_post, clk_zero(2B), hs_prepare(2B), hs_exit, hs_zero(2B), hs_trail, hs_rqst(2B)]`
— ese es el layout del `qcom,mdss-dsi-panel-timings` antiguo (v2/v3), ausente aquí. Para
`-phy-timings` el mapeo es **byte[i] → TIMING_CTRL_i** (registro PHY+0xB4+4·i), sin permutación.
Prueba tripla:

1. Decomp `dsi_phy_hw_v4_0_commit_phy_timing.c` (== v5_0): escribe `array[0..13]` 1:1 a
   `PHY+0xB4, 0xB8, 0xBC, 0xC0 … 0xE8` = TIMING_CTRL_0..13.
2. Los bytes fijos del array **[9]=0x02, [10]=0x04, [11]=0x00** caen en T9/T10/T11, exactamente
   los writes fijos `0x02/0x04/0x00` de mainline (`dsi_phy_7nm.c:1172-1174`). Coincidencia
   imposible si el orden no fuera el de registro.
3. El orden de campos que mainline escribe en DPHY (`dsi_phy_7nm.c:1163-1178`):
   T0=00 fijo, T1=clk_zero, T2=clk_prepare, T3=clk_trail, T4=hs_exit, T5=hs_zero,
   T6=hs_prepare, T7=hs_trail, T8=hs_rqst, T9=02, T10=04, T11=00, T12=clk_pre, T13=clk_post —
   reproduce la semántica de B4 §2 y hace cuadrar los bytes 1..8 y 12..13 con el cálculo.

| Byte | T-reg | Campo | Vendor |
|---|---|---|---|
| 0 | TIMING_CTRL_0 | — (fijo 00) | 0x00 |
| 1 | TIMING_CTRL_1 | clk_zero | 0x27 |
| 2 | TIMING_CTRL_2 | clk_prepare | 0x0a |
| 3 | TIMING_CTRL_3 | clk_trail | 0x0a |
| 4 | TIMING_CTRL_4 | hs_exit | 0x1b |
| 5 | TIMING_CTRL_5 | hs_zero | 0x19 |
| 6 | TIMING_CTRL_6 | hs_prepare | 0x0a |
| 7 | TIMING_CTRL_7 | hs_trail | 0x0b |
| 8 | TIMING_CTRL_8 | hs_rqst | 0x0a |
| 9 | TIMING_CTRL_9 | — (fijo 02) | 0x02 |
| 10 | TIMING_CTRL_10 | — (fijo 04) | 0x04 |
| 11 | TIMING_CTRL_11 | — (fijo 00) | 0x00 |
| 12 | TIMING_CTRL_12 | clk_pre | 0x20 |
| 13 | TIMING_CTRL_13 | clk_post | 0x0f |

**NUEVO:** los bytes sin registro mainline equivalente NO existen en esta tabla — los 14 bytes
caen todos en TIMING_CTRL_0..13. El `rs_w0/rs_w1` y demás strength/registro de drive (HSTX_STR,
LPTX_STR, RESCODE, VREG_CTRL, LANE_CTRL0) **no viajan en estos bytes** (van por código/otras
props DT y ya están en paridad vendor, B4 §1a). El decomp downstream `dsi_phy_hw_calculate_
timing_params` + `calc_*` confirma que la fórmula downstream es la misma familia (percentiles),
pero para ESTE panel el vendor ni la usa: la tabla del DT es lo que aterriza en registros.

## 3. Nuestra tabla computada (C-exacta) y deltas COMPLETOS

Emulación C-exacta de `msm_dsi_dphy_timing_calc_v4` (`dsi_phy.c:374-470`) con `mult_frac`
(TRUNCA: include/linux/math.h), `S_DIV_ROUND_UP` (ceil) y `linear_inter` tal cual el árbol:
**ui = mult_frac(1e6, 1000, 1189188) = 840** — CORREGIDO (crítica MN1): `mult_frac` TRUNCA
(no redondea), ui=840 como decían B4 y el encargo; antes se escribió 841 por error (inmaterial: ui=840 y ui=841 producen la MISMA tabla; la tabla
tampoco cambia entre bitclk pedido 1.189.188.000 y VCO 1.189.190.000). v4 no usa esc_rate (solo
lo valida ≠0): la esc (19,2 MHz, paridad ya medida en cosecha) no afecta.

| T-reg | Campo | calc ui=840 (=841, misma tabla) | vendor | Δ (calc−vend) | tras override |
|---|---|---|---|---|---|
| T0 | fijo | 0x00 | 0x00 | 0 | 0x00 |
| T1 | clk_zero | 0x27 | 0x27 | 0 | 0x27 |
| T2 | clk_prepare | 0x0a | 0x0a | 0 | 0x0a |
| T3 | clk_trail | **0x0c** | 0x0a | **+2** | 0x0a |
| T4 | hs_exit | 0x27 | 0x1b | **+12** | 0x1b |
| T5 | hs_zero | **0x25** | 0x19 | **+12** | 0x19 |
| T6 | hs_prepare | 0x0a | 0x0a | 0 | 0x0a |
| T7 | hs_trail | 0x0b | 0x0b | 0 | 0x0b |
| T8 | hs_rqst | 0x07 | 0x0a | **−3** | 0x0a |
| T9 | fijo | 0x02 | 0x02 | 0 | 0x02 |
| T10 | fijo | 0x04 | 0x04 | 0 | 0x04 |
| T11 | fijo | 0x00 | 0x00 | 0 | 0x00 |
| T12 | clk_pre | 0x23 | 0x20 | **+3** | 0x20 |
| T13 | clk_post | 0x1a | 0x0f | **+11** | 0x0f |

- Calc completo: `00 27 0a 0c 27 25 0a 0b 07 02 04 00 23 1a`.
- **CORREGIDO vs B4 §2**: T3 clk_trail calc = **0x0c** (B4: 0x0b; Δ real +2, no +1) y
  T5 hs_zero calc = **0x25** (B4: 0x24; Δ real +12, no +11). B4 mezcló floor/ceil: clk_zero
  solo cuadra con ceil (0x27); con la misma aritmética ceil, T3 y T5 suben 1. La forma del
  hallazgo no cambia (5 campos más largos en mainline, 1 más corto, 8 iguales), pero los
  deltas exactos son los de esta tabla.
- Tras override: **paridad 14/14 con el vendor**, incluido el único lado apretado del TX propio
  (hs_rqst 0x07→0x0a, el vendor manda request más largo). El override ACORTA T3/T4/T5/T12/T13
  hacia el mundo vendor: ese mundo (DT byte-exacto) es el único validado en este hardware.

## 4. Diseño del override (kernel-only, boot_a)

**(a) Dónde inyectar.** Único punto de escritura de TIMING_CTRL en mainline: `dsi_7nm_phy_enable`
(`dsi_phy_7nm.c`), que es la ops.enable de `dsi_phy_4nm_8650_cfgs` (`:1488-1510`, quirk V5_2,
`dsi_phy.c:579` fallback `qcom,sm8650-dsi-phy-4nm`). Inyección **tras el cálculo y antes de los
writes**, línea 986 del árbol (entre el cierre del `if (ret)` del calc, `:981-985`, y el check
`dsi_phy_hw_v4_0_is_pll_on`, `:987`). Parche en la convención del repo:
`build/gates/patches/l75-phy-timings-vendor.diff` (ni l73 ni l74 tocan `dsi_phy_7nm.c` ⇒ las
líneas aguantan).

```diff
--- a/drivers/gpu/drm/msm/dsi/phy/dsi_phy_7nm.c
+++ b/drivers/gpu/drm/msm/dsi/phy/dsi_phy_7nm.c
@@ -985,6 +985,26 @@ static int dsi_7nm_phy_enable(struct msm_dsi_phy *phy,
 		return -EINVAL;
 	}

+	/*
+	 * L75 (uke, 17-oct-2026): tabla de la PHY del DTBO vendor
+	 * qcom,mdss-dsi-panel-phy-timings (42_02_0b y 36_02_0a; identica en
+	 * 120/90/144). El commit CAF la escribe 1:1 en TIMING_CTRL_0..13
+	 * (dsi_phy_hw_v4_0_commit_phy_timing), y los bytes fijos 02/04/00 de
+	 * mainline (T9/T10/T11) coinciden con las posiciones 9/10/11. El calc v4
+	 * (ui=841) difiere en 6 campos: T3 -2, T4 -12, T5 -12, T8 +3, T12 -3,
+	 * T13 -11. Override solo a la tasa del panel; el resto de builds/rates
+	 * siguen con el calc mainline.
+	 */
+	if (!phy->cphy_mode && clk_req->bitclk_rate == 1189188000U) {
+		static const u8 o82_t[14] = { 0x00, 0x27, 0x0a, 0x0a, 0x1b, 0x19,
+					      0x0a, 0x0b, 0x0a, 0x02, 0x04, 0x00,
+					      0x20, 0x0f };
+		timing->clk_zero                = o82_t[1];
+		timing->clk_prepare             = o82_t[2];
+		timing->clk_trail               = o82_t[3];
+		timing->hs_exit                 = o82_t[4];
+		timing->hs_zero                 = o82_t[5];
+		timing->hs_prepare              = o82_t[6];
+		timing->hs_trail                = o82_t[7];
+		timing->hs_rqst                 = o82_t[8];
+		timing->shared_timings.clk_pre  = o82_t[12];
+		timing->shared_timings.clk_post = o82_t[13];
+		pr_info("UKE-L75: PHY timings vendor @%u Hz: %*ph (T0/T9/T10/T11 fijos 00/02/04/00)\n",
+			clk_req->bitclk_rate, (int)sizeof(o82_t), o82_t);
+	}

 	if (dsi_phy_hw_v4_0_is_pll_on(phy))
 		pr_warn("PLL turned on before configuring PHY\n");
```

**(b) Gate.** `clk_req->bitclk_rate == 1189188000U` — el valor que `dsi_calc_clk_rate_6g` →
`msm_dsi_host_get_phy_clk_req` entrega a la PHY (byte 148.648.500 ×8; B4 §3.4). No es la tasa
OPP (1.189.190.000) sino la pedida, y ambas producen la misma tabla, así que el gate exacto es
seguro. Falla cerrado: cualquier otra tasa (o otro build) ⇒ calc mainline intacto y **el
marcador no aparece**, señal inequívoca de gate fallido. Se cubre el caso CPHY con
`!phy->cphy_mode` (esta tasa nunca ocurre en CPHY; defensa gratuita).

**(c) Marcador UKE-L75.** `pr_info` con los 14 valores (`%*ph`) más la tasa — aparece **×2**
(PHY0 `ae95000` + PHY1 `ae97000`; `dsi_manager_phy_enable` habilita ambas con el mismo
clk_req) y en cada re-enable (resume). El print va antes de los writes ⇒ lo impreso es lo que
aterriza en TIMING_CTRL_0..13.

**(d) Verificación post-boot (criterio nº1 = flood).** En kmsg del arranque:
1. `grep UKE-L75` → 2 líneas, `00 27 0a 0a 1b 19 0a 0b 0a 02 04 00 20 0f` y `1189188000 Hz`.
2. **El burst de `VIDEO_MDP` over/underflow (17 eventos/250 ms, ambos links, en cada commit
   desde L67; latch `dddd1019`) debe DESAPARECER** (contador ≈ 0). Ese es el criterio nº1.
3. `S4-DIAG`/`TIMEOUT_STATUS` (L74-B) sin empeorar; init err=0 como hoy.
4. **PASA = CONTENIDO en pantalla.**
5. Matriz de salida: flood 0 + contenido ⇒ cerrado. Flood 0 + negro ⇒ la paridad PHY 14/14
   conseguida no era el eslabón: el residuo apunta al camino TDDI (NVT-ts, candidato nº1 de la
   cosecha). Flood persistente ⇒ el flood no nacía de la PHY y se descarta definitivamente
   (dato duro para la ronda). Marcador ausente ⇒ gate fallido (verificar clk_req).

**(e) Riesgos.**
- **No se toca nada fuera de los 10 campos de timing.** Strength/regs de drive (VREG_CTRL_0/1
  0x44/0x19, RESCODE 0x3c/0x38, HSTX_STR 0x88, PEMPH 0, LPTX_STR 0x55, LANE_CTRL0) van en
  registros aparte, ya en paridad vendor (B4 §1a) y siguen escritos por el código hardcodeado
  V5_2 — no viajan en estos 14 bytes, confirmado en §2.
- T9/T10/T11 (02/04/00) son writes fijos ya idénticos al vendor; no se modifican.
- Únicos consumidores de `shared_timings.clk_pre/clk_post` en este driver son los writes
  T12/T13 (`dsi_phy_7nm.c:1153,1156,1175,1177`); no hay otra ruta que lea esos campos.
- `less_than_1500_mhz` y todas las ramas V5_2 de regulators/RESCODE no dependen del timing.
- Composición con L73/L74: parches sobre ficheros distintos (panel/dpu/dsi_host); sin
  interferencia. Rollback trivial (quitar el diff).
- Riesgo eléctrico: el override acorta 5 timings TX hacia el mundo OEM validado en hardware
  (Android corre exactamente estos valores) y alarga hs_rqst. El mundo destino es el probado,
  no una interpolación nueva.

## 5. Nota de contexto (cosecha)

`docs/historia/revision/ANDROIDE-COSECHA-20261017.md` deja esta tabla como candidato vivo nº2 ("kernel-only vía DT de
la PHY o tabla verbatim") y mata la hipótesis esc_clk (el vendor también corre 19,2 MHz — el
F2 de B4 queda descartado). Este informe entrega esa vía nº2 lista para flash: bytes verbatim,
mapeo probado, gate y criterio de éxito medibles.

## 6. Fuentes

- DTBO stock decodificado: `build/evidencia/android-snap/dt-r15/soc/qcom,mdss_mdp@ae00000/
  qcom,mdss_dsi_o82_{36_02_0a,42_02_0b}_dualdsi_dsc_vid/qcom,mdss-dsi-display-timings/timing@{120,90,144}/`
  (`qcom,mdss-dsi-panel-phy-timings`, `qcom,mdss-dsi-panel-clockrate`).
- `build/vendor-re/vendor-o82-dsi4nm.h:86-94` (tabla 1:1 a PHY+0xB4..0xE8), `…/decomp/
  dsi_phy_hw_v4_0_commit_phy_timing.c`, `dsi_phy_hw_calculate_timing_params.c`, `calc_*.c`,
  `dsi_phy_hw_v4_0_cache_phy_timings.c`, `dsi_phy_hw_v5_0_get_phy_timing.c`,
  `dsi_panel_get_phy_props.c`.
- Árbol: `build/kernel-pokes/k52-L16-tree/drivers/gpu/drm/msm/dsi/phy/dsi_phy.c:15-30,374-470`
  (helpers + calc v4), `dsi_phy_7nm.c:958-992` (enable + punto de inyección),
  `:1151-1178` (writes TIMING), `:1488-1510` (cfgs 4nm).
- Informes: `docs/historia/revision/PANEL-REVISION-B4-PHY-LINK.md` §2/§3 (base; 2 celdas corregidas aquí),
  `docs/historia/revision/ANDROIDE-COSECHA-20261017.md`, `docs/historia/revision/CRITICA-L74-20261016.md`.
- Aritmética: emulación C-exacta de `msm_dsi_dphy_timing_calc_v4` (mult_frac/S_DIV_ROUND_UP/
  linear_inter) a bitclk 1.189.188.000 y 1.189.190.000 — resultados idénticos.
