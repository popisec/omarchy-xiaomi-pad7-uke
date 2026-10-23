# PANEL-REVISION B4 — PHY DSI + enlace físico + arranque display-ON — 2026-10-15

> Agente B4, revisión por fases. SOLO lectura de árbol y decomp; cero dispositivo, cero build.
> Fuentes: árbol vivo `build/kernel-pokes/k52-L16-tree` (estado L72, `e310fd2`), DTBO real en
> slot: `build/bootimg/s288-boot-dtbo-…img` (descompilado a /tmp con dtc: `/tmp/s288.dts`,
> nodo `fragment@1105/__overlay__/display-subsystem@ae00000`), vendor `build/vendor-re/`
> (`vendor-o82-dsi4nm.h`, `decomp/*.c`), y A1/A2/A3 + `PIPELINE-PANEL-20261014/PHY-LANE-RATE`.
> **NUEVO** = hallazgo no escrito antes en ningún informe; **SEMI** = conocido + dato nuevo al lado.

---

## 1. ¿Qué driver PHY usa el árbol para SM7675?

**No existe `dsi_phy_4nm.c`: la PHY 4nm vive en `dsi_phy_7nm.c`** (la familia 7/5/4nm comparte
`dsi_7nm_phy_enable` + `dsi_pll_7nm_init`). Cadena de binding:

| Eslabón | Valor | Fichero:línea |
|---|---|---|
| DT (palawan.dtsi y el DTBO s288 vivo) | `compatible = "qcom,palawan-dsi-phy-4nm", "qcom,sm8650-dsi-phy-4nm"` ×2 (ae95000/ae97000) | `palawan.dtsi:3549,3627`; DTBO `/tmp/s288.dts:15110,15172` |
| Match del driver | **NO existe entrada `qcom,palawan-dsi-phy-4nm`** en `dsi_phy_dt_match` → liga el **fallback** `qcom,sm8650-dsi-phy-4nm` | `dsi_phy.c:579-580` |
| cfg | `dsi_phy_4nm_8650_cfgs`: regulator 98.000 µA, `io_start {0xae95000, 0xae97000}`, `num_dsi_phy 2`, **`quirks = DSI_PHY_7NM_QUIRK_V5_2`** | `dsi_phy_7nm.c:1488-1510` |
| ops | `enable=dsi_7nm_phy_enable (:958)`, `pll_init=dsi_pll_7nm_init`, V5_2 ⇒ REFGEN-ready (:990-995) + `CMN_CTRL_4=0x04` (:1071-1074) | `dsi_phy_7nm.c:1492-1499` |

⇒ **Coincide con A2 §6.6**: igual que senemos, nuestro árbol programa la PHY del uke con las
cfgs de sm8650 (4nm v5.2). No hay cfg propia "palawan". El DSI ctrl liga 6G **v2.8 →
sm8650_dsi_cfg + 6g_v2 host ops** (`dsi_cfg.c:341-342`).

### 1a. Tabla de discrepancias PHY (config estática, registro a registro)

Campos de `dsi_7nm_phy_enable` rama V5_2 DPHY (bitclk 1,189 G < 1,5 G ⇒ `less_than_1500_mhz=1`,
`dsi_phy_7nm.c:1010`):

| Registro | Nuestro árbol | Vendor o82 (vendor-o82-dsi4nm.h / decomp) | Estado |
|---|---|---|---|
| VREG_CTRL_0 / _1 | 0x44 / 0x19 (`:1047-1048`) | 0x44/0x19 | igual (ya conocido) |
| RESCODE top/bot | 0x3c / 0x38 (`:1049-1050`) | 0x3c/0x38 | igual |
| HSTX_STR 0x88, PEMPH 0, LPTX_STR 0x55 | (`:1025,1027,1131`) | 0x88 / 0 / 0x55 | igual |
| CTRL_2 full-rate 0x40 | `:1140` | — | igual |
| TX_DCTRL por lane | `tx_dctrl_1` = 40 40 40 46 41 (no-V4_0 ⇒ `:932,937-939`) | idéntico (`vendor-o82-dsi4nm.h:106`) | igual |
| LPRX/CDRX | LPRX_CTRL(lane0)=0x3, resto 0 (`:943,920`) | vendor `dsi_phy_lane_reset` en overflow; setting estático no RE'd | igual-mecánica |
| **LANE_CFG0/1** | **0x21 / 0x84 hardcoded** (`:1108-1109`) | 0xAA / 0xAA (DT `qcom,platform-lane-config` 0xa0a×5) | **difieren**; refutada como causa del sordo por control L40-vs-L41 (`docs/historia/revision/PIPELINE-PANEL-20261014/REVIEW-S5.md:10-11`) |
| **LANE_CTRL0** | **0x1f** (`:1136`, `:1024`) | **0x15** (`vendor-o82-dsi4nm.h:125`) | **difieren**; abierta, "débil sola" (PHY-LANE-RATE §A) |
| PLL CMODE_1 | 0x10 DPHY (SSC off) | 0x00 (SSC on down-spread) | difieren; refutada L40-vs-L42 |
| **14 TIMING_CTRL** | **calculados** (`dsi_phy.c:374-470` + writes `dsi_phy_7nm.c:1162-1179`) | **fijos del DT** `00 27 0a 0a 1b 19 0a 0b 0a 02 04 00 20 0f` (`vendor-o82-dsi4nm.h:91-94`) | **difieren parcialmente — §2** |
| phy-strength/`clk-strength 0xff`/`phy-voltage 0x51` (props DT vendor) | ignoradas (grep=0 en msm/) | usadas por el vendor | conocido (G6) |

## 2. Los 14 TIMING_CTRL: la comparación exacta que pedía A1 §6.3

`msm_dsi_dphy_timing_calc_v4` (`dsi_phy.c:374-470`) **no usa `esc_rate`** (solo `ui` del
bitclk). Con el byte-clock vigente desde L70 ⇒ ui=840 (ver §3). Tabla completa
[calc árbol @1.189,188 G] vs [bytes fijos del DT vendor], mapeados a los registros que escribe
`dsi_phy_7nm.c:1162-1179`:

| Reg | Campo | calc ui=840 | vendor byte | Δ |
|---|---|---|---|---|
| T0 | — (0) | 0x00 | 0x00 | 0 |
| T1 | clk_zero | **0x27** | 0x27 | **0** |
| T2 | clk_prepare | **0x0a** | 0x0a | **0** |
| T3 | clk_trail | 0x0b | 0x0a | +1 |
| T4 | hs_exit | **0x27** | **0x1b** | **+12** |
| T5 | hs_zero | **0x24** | **0x19** | **+11** |
| T6 | hs_prepare | **0x0a** | 0x0a | **0** |
| T7 | hs_trail | 0x0a | 0x0b | −1 |
| T8 | hs_rqst | **0x07** | **0x0a** | **−3** |
| T9/T10/T11 | fijos 02/04/00 | 02/04/00 | 02/04/00 | 0 |
| T12 | clk_pre | 0x23 | 0x20 | +3 |
| T13 | clk_post | **0x1a** | **0x0f** | **+11** |

**Hallazgos NUEVOS:**

1. **N-B4-1: los 14 bytes del vendor son coherentes con bitclk 1.189.190.000 exacto.** Con
   ui=840 (la tasa del DT `0x46e19970`), el cálculo v4 del árbol reproduce *exactamente* los
   bytes vendor en clk_zero (0x27), clk_prepare (0x0a) y hs_prepare (0x0a) — el mismo valor
   que produce ui=840 y NO el que produciría la tasa vieja (a ui=1051/L67 dan 32/8/8). Es decir:
   **los bytes vendor fueron generados (por la fórmula familia downstream) a la tasa que
   nosotros ya corremos desde L70.** Los deltas restantes son diferencias de interpolación
   (percentiles mainline vs downstream), no de tasa.
2. **N-B4-2: dirección de los deltas.** En 6 campos el árbol programa timings MÁS LARGOS que el
   vendor (hs_exit +12, hs_zero +11, clk_post +11, clk_pre +3, clk_trail +1) y en 1 campo más
   corto (hs_rqst −3). Timings TX más largos son conservadores (margen); **hs_rqst más corto**
   es el único lado "apretado" del TX propio. La tabla vendor @ui=1051 (estado L67) era la que
   quedaba **fuera** de rango en 4/7 mínimos — hoy ya no.
3. **N-B4-3: la candidata "RX timing" de A1 se debilita como explicación del sordo.** De los 14
   TIMING_CTRL, 8 son idénticos al vendor hoy (T0,T1,T2,T6,T9,T10,T11 + T7 ±1); los que
   difieren son mayoritariamente timings de TX (hs_exit/hs_zero = data-lane TX; clk_post/pre =
   clock-lane TX) donde ir MÁS LARGO es más seguro para el receptor DDIC. El lado RX nuestro es
   `LPRX_CTRL=0x3` en lane 0 (`dsi_phy_7nm.c:920`), que no depende de los TIMING_CTRL.

## 3. El PLL y la aritmética de bitclk (verificación con fichero:línea)

Cadena exacta (todas las líneas en `dsi_host.c`):

1. Modo 120 Hz full: clock 967.428 kHz, htotal 3490 (`panel-xiaomi-o82-dualdsi.c:723-732`).
2. `dsi_adjust_pclk_for_compression` (:589-615): bonded ⇒ hdisplay/2=1600; H'=ceil(1600·8/30)=
   **427**; ×2=854; htotal mundo-30 por link = **572** (= vendor A3 §2a, EXACTO).
3. `dsi_get_pclk_rate` (:617-637): pclk/link = mult_frac(967428000·1144/3490)/2 =
   **158.558.400 Hz** (vendor 158.558.666, Δ266 Hz = redondeo mult_frac).
4. `dsi_byte_clk_get_rate` (:639-683): L70 ⇒ `bpp = dsc->bpc*3 = 30` (:661-662); byte =
   mult_frac(158558400, 30, 32) = **148.648.500 Hz**; `bitclk = byte×8` =
   **1.189.188.000** (`msm_dsi_host_get_phy_clk_req:2494-2496`).
5. **N-B4-4 (NUEVO): el OPP cierra el círculo con el DT vendor.** `dsi_link_clk_set_rate_6g`
   (:381-389) llama `dev_pm_opp_set_rate(pdev, 148.648.500)`; el DTBO vivo trae
   `opp-table {opp-148648750, 187.5M, 300M, 358M}` (`/tmp/s288.dts:15073-15091`) ⇒ ceil a
   **148.648.750 Hz exacto** ⇒ PLL VCO = ×8 = **1.189.190.000 Hz = 0x46E19970**, el
   `qcom,mdss-dsi-panel-clockrate` del DT vendor, **bit a bit**. `dsi_pll_7nm_vco_set_rate`
   (`dsi_phy_7nm.c:348-375`) programa DEC/FRAC directos sin redondeo a múltiplos de pclk ⇒ el
   VCO aterriza en lo pedido. La coincidencia byte 148,648 MHz medida en L70/L71 (A1 §2) es
   esta cadena. El "1 línea DT" que pedía A3-N1 (fijar bitclk por DT) **ya está hecho** vía OPP.
6. ui = floor(1e9/1.189.188) = **840** ⇒ el cálculo de timings PHY (§2) cae exactamente en el
   mundo vendor. Con L67 (byte ×24) era ui=1051 y la tabla estaba mal — L70 lo arregló de paso.
7. `esc_clk_rate` = `clk_get_rate(esc_clk)` (:697) — **nadie hace `clk_set_rate` del esc en el
   camino 6g** (solo el path v2, :489-495) ⇒ esc queda en su padre de arranque (TCXO 19,2 MHz;
   `dispcc-sm8550.c:557-571` solo tiene F(19,2M, TCXO) en su freq_tbl). Vendor: esc = byte/8 =
   18,58 MHz. **N-B4-5 (SEMI-NUEVO): Δ esc = +3,4 %** — escala LP/BTA/turnaround; dentro de
   especificación MIPI, no explica por sí el sordo, pero es la única tasa del enlace que sigue
   sin ser la vendor.

## 4. Veredicto BTA sordo: NORMAL respecto al vendor, NO un fallo del enlace demostrado

Evidencia vendor (decomp + DTBO):

- **El vendor NO hace lecturas DCS en el flujo normal de este panel** (A3 §3): en el DTBO real
  los nodos `qcom,mdss_dsi_o82_{36_02_0a,42_02_0b}_dualdsi_dsc_vid` traen
  `mi,esd-err-irq-gpio` + `-second` (ESD por **GPIO**, `/tmp/s288.dts:3706-3708`, fragmentos
  95/96) y `mi,panel-build-id-read-needed`/`mi,feature-enabled` **vacías** ⇒
  `mi_dsi_display_read_panel_build_id` se salta (`dsi_display_enable.c:99`). Las únicas
  lecturas definidas son de fábrica (0xDA/0x01, `06 01 00 01 …`) y no se ejecutan en boot.
- El intento vendor de leer bajo splash también falló ("Panel not initialized", rc=-22 —
  PHY-LANE-RATE; y ojo: -22 es rechazo *software*, ni siquiera llegó al bus).
- **No existe en `build/vendor-re/decomp/` ninguna prueba de que este DDIC responda BTA con
  vídeo ON** — ni que el vendor programe algo específico de RX que a nosotros nos falte:
  `LP_TIMER_CTRL` (LP_RX_TO/BTA_TO, dsi.xml:246-249) **no lo escribe NI el vendor NI mainline**
  (el `+0xb4←0x11111` de `dsi_ctrl_hw_cmn_enable_error_interrupts.c` es el registro
  DLN0_PHY_ERR del mapa +4, es decir *clear* de errores, no el timer; `grep 0xb8` solo da
  usos ajenos). El reset-default 0 es el estado de ambos.
- LaPHY RX sí está habilitada en nuestro árbol: `LPRX_CTRL(lane0)=0x3` (LPRX+CDRX) al
  habilitar (`dsi_phy_7nm.c:920`); el path de lectura del host es el estándar que funciona en
  otros equipos msm (`msm_dsi_host_cmd_rx:2276+, RDBK_DATA:0x68+4`).
- **Corolario incómodo (N-B4-6):** siendo el BTA la única vía bidireccional y estando muda,
  **"init DCS byte-idéntico + err=0" solo prueba el DMA del host**; no existe ninguna
  confirmación del DDIC de haber recibido NADA (ni init, ni PPS, ni 0x29). "Negro con luz" es
  consistente tanto con feed roto como con init no entregado. El sordo es *normal* comparado
  con el vendor, pero **nos deja sin prueba de entrega**.

**Veredicto:** el BTA-sordo **no puede calificarse de fallo**: (a) el vendor opera el panel en
mono-direccional (ESD GPIO), (b) nuestro path RX está habilitado y no difiere estructuralmente
del vendor en ningún registro que el vendor programe, (c) el propio vendor nunca leyó con éxito.
Seguir siendo diagnostic como hasta ahora (L65 fail-safe). Las candidatas residuales de RX que
quedan abiertas son el `esc_clk` +3,4 % (N-B4-5) y el estado interno del DDIC (ANGULO-DDIC §2.4).

## 5. Dual-DSI bonded (DT + dsi_manager)

- DT vivo (`/tmp/s288.dts:14954-15195`): dsi0 = `qcom,master-dsi` + `sync-dual-dsi`; dsi1 sin
  master; panel@0 bajo dsi0 con `panel_in_1 → mdss_dsi1_out`; data-lanes 0-3 en ambos.
  **N-B4-7 (SEMI-NUEVO): `assigned-clock-parents` de dsi1 apuntan a `mdss_dsi0_phy_ml`**
  (`/tmp/s288.dts:15002-15007`) — PLL **única** (PHY0) alimenta byte+pixel de ambos ctrl.
  Correcto para bonded y **consistente con el vendor** (single-PLL; `dsi_manager.c:95-103`
  declara PLL0 como clock master y PHY1=SLAVE). Ojo: el `palawan.dtsi:3590-3591` upstream
  parenta dsi1→dsi1_phy (topología no-bonded); el DTBO ganó con la bonded — no "romper" esto
  al regenerar el DTBO.
- Código (`dsi_manager.c`): `dsi_mgr_phy_enable` (:147-183) habilita **ambas** PHYs con el
  mismo clk_req (los dos hosts derivan byte_clk_rate idéntico de `dsi_calc_clk_rate_6g:689-698`
  con `is_bonded_dsi`); `dsi_mgr_bridge_power_on` (:220-267) hace power_on de host+host1;
  `pre_enable` (:282-324) salta al slave y habilita host0→host1. Ambos links arrancan
  idénticos: no hay dato que salga solo por un link en el flujo de init (init DCS va a ambos,
  `mipi_dsi_dual_dcs_write_buffer_multi`, `panel-xiaomi-o82-dualdsi.c:245-247`; PPS a ambos,
  `:632-639`). El feed de vídeo va INTF1→dsi0 / INTF2→dsi1 (DT ports) — los underruns 1929/1
  en "ambos intf" (A1 §1) son feed DPU, no asimetría de link.
- La asimetría que sí existe en los reads (CRITICA-L67 I3: link0 manda en writes sincronizados)
  no aplica a los reads (`need_sync=false` con rx_buf; anotado en el propio código L65,
  `panel-xiaomi-o82-dualdsi.c:654-660`).

## 6. Arranque display-ON: cronología con fichero:línea y riesgos de orden

1. t≈0,7 s: panel probea; el secundario `ae96000.dsi` aún no (`phy driver is not ready` en su
   primer probe) ⇒ `of_find_mipi_dsi_host_by_node` → `-EPROBE_DEFER`
   (`panel-xiaomi-o82-dualdsi.c:930-935`). Riesgo documentado en ESTADO-VIVO:228.
2. t≈4,3 s: KTZ8866 probea (I2C-2); el re-probe del panel por `-EPROBE_DEFER` (fix L45,
   `:973-977`) resuelve el backlight one-shot (ESTADO-VIVO:246).
3. **t≈47 s: el deferral del host secundario solo se limpia cuando OTRO probe reactiva la cola
   deferred** (medido: lo disparó el táctil, H1, ESTADO-VIVO:229). El bonding **no se rompe**
   (el panel se adjunta a AMBOS hosts en el mismo probe, `:1002-1010`; `dsi_manager` exige los
   dos `msm_dsi` para bonded, `:52-63`) — lo que se rompe es la **latencia**: sin un evento de
   probe externo, no hay card1, ni modeset, ni DCS, ni voto vci. Riesgo real de arranque frío:
   la pantalla depende de una cola de probe no propia.
4. Enable (ya con ambos links): bridge pre_enable (PHY+hosts, `dsi_manager.c:282-324`) →
   panel prepare (rieles/reset/init L37) → **mode_set + commit con `video=DSI-1` sin `:d`**
   (docs/historia/revision/PIPELINE-PANEL-20261014/BRIEF.md:12 lo apunta a `--dsid` del repack; con `:d` el conector queda disabled) →
   panel enable = `o82_enable` con PPS-post (L63) + BTA L65 (fail-safe) → KTZ via
   `drm_panel_of_backlight`. `prepare_prev_first=true` (:938) ⇒ el DSI host queda en vídeo
   antes del init (K48-A: bitclk HS continuo evitado con `CLOCK_NON_CONTINUOUS`, :798-804).
5. Riesgo de orden concreto detectado esta pasada: **ninguno nuevo en PHY** — el estado L70/L71
   dejó bitclk/ACTIVE_H/TOTAL clavados al vendor (A1 §2) y la tabla de timings PHY cayó en el
   mundo correcto (§2/§3). El residuo de orden es el (3).

## 7. Fixes candidatos (diff EXACTOS, qué arregla / riesgo / verificación / independencia)

**F1 — Tabla de 14 TIMING_CTRL con los bytes del DT vendor (quirk `USE_DT_TIMINGS`).**
```c
// drivers/gpu/drm/msm/dsi/phy/dsi_phy_7nm.c, tras msm_dsi_dphy_timing_calc_v4 (:977-985)
if (phy->quirk_dt_timings) {              // nuevo bool, de DT "qcom,phy-timings-vendor"
    static const u8 o82_t[14] = {0x00,0x27,0x0a,0x0a,0x1b,0x19,0x0a,0x0b,
                                 0x0a,0x02,0x04,0x00,0x20,0x0f};
    timing->clk_zero=o82_t[1]; timing->clk_prepare=o82_t[2]; timing->clk_trail=o82_t[3];
    timing->hs_exit=o82_t[4]; timing->hs_zero=o82_t[5]; timing->hs_prepare=o82_t[6];
    timing->hs_trail=o82_t[7]; timing->hs_rqst=o82_t[8];
    timing->shared_timings.clk_pre=o82_t[12]; timing->shared_timings.clk_post=o82_t[13];
}
```
- **Qué arregla**: paridad registro-a-registro completa con el vendor (§2). Efecto esperado
  pequeño: nuestros valores son MÁS largos (más seguros) salvo hs_rqst (−3); el único escenario
  real es que el DDIC sea estricto con hs_rqst/hs_trail en el extremo TX.
- **Riesgo**: bajo (bytes auditados contra el binario). Mejora medible marginal.
- **Verificación post-boot**: dump `dsi0_phy` snapshot (`msm_dsi_phy_snapshot`) o devmem de
  TIMING_CTRL_0..13 = bytes vendor; BTA L65 sigue `ret=0` o cambia.
- **Independencia**: total (no toca clocks/INTF/host). **Peso: BAJO** — no es el eslabón del vídeo.

**F2 — Forzar `esc_clk` = byte/8 (paridad N-B4-5).** En `dsi_link_clk_set_rate_6g`
(`dsi_host.c:381`), tras el OPP: `clk_set_rate(msm_host->esc_clk,
clk_get_rate(msm_host->byte_clk)/8);` (requiere reparent a `DSI0_PHY_PLL_OUT_BYTECLK`,
padre ya disponible en `disp_cc_parent_data_5`, `dispcc-sm8550.c:223-227`).
- **Qué arregla**: única tasa de enlace aún no vendor (19,2 → 18,58 MHz); escala todos los
  timings LP/BTA/turnaround del host al mundo vendor. Candidata RX residual de mayor pureza.
- **Riesgo**: medio-bajo (3,4 % más lento en LP: init de ~110 cmds LP se alarga ~3,4 %; sin
  cambios de orden). Cuidado con `clk_get_rate` antes de OPP (usar byte_clk_rate ×1/8).
- **Verificación**: `clk_summary | grep esc` = 18,581 MHz en ambos links; BTA L65 A/B.
- **Independencia**: total del resto del mundo de vídeo.

**F3 — Reducir el ping de arranque del host secundario (riesgo del §6.3).** En
`drivers/gpu/drm/msm/dsi/dsi.c`/`dsi_manager.c:114-118` ya se registra slave antes que master;
el deferral real viene del PHY "not ready" del primer probe del host1 (ESTADO-VIVO:228).
Fix mínimo: hacer que el probe del host DSI espere activo (retry corto) o asegurar que un
driver que probea pronto (KTZ) corra antes del display en el orden de linker-init. Fuera de mi
chunk el detalle exacto; el riesgo es de **latencia/ausencia de display**, no de bonding.
- **Independencia**: total. **Verificación**: `UKE-P82` probe < 5 s en dmesg.

**NO recomendado ahora**: LANE_CFG 0xAA/0xAA, LANE_CTRL0 0x15, SSC on — refutados por los
controles L40/L41/L42 (REVIEW-S5:10-11) como causa del sordo; tocarlos reintroduce variables
sin hipótesis que los sostenga.

## 8. Veredicto final: ¿está bien la PHY o es el eslabón flojo?

**La PHY no es el eslabón flojo del vídeo.** Tras L70/L71, el enlace corre al bitclk EXACTO del
DT vendor (0x46E19970, vía OPP, N-B4-4), pclk idéntico (Δ266 Hz), los tres registros de vídeo
que A1 midió clavados, y la tabla de timings PHY calculada está en el mundo correcto con 8/14
bytes idénticos al vendor y el resto en el lado conservador (§2). Lo que queda de PHY es fino:
hs_rqst −3 (F1), esc +3,4 % (F2). El eslabón flojo **no está en la PHY sino fuera de ella**:
(a) la **entrega al DDIC sigue sin verificar** (N-B4-6: cero lecturas desde el día 1 ⇒ init/
PPS/0x29 no confirmados) — sin un canal bidi o un signo eléctrico no se puede cerrar la causa
del negro; y (b) el feed DPU→INTF→DSI (mundo 24/30, handoff VBIF/SMMU/ICC de A2 §3.7) que es
donde apuntan el flood y los underruns. Recomendación de orden: **F2 (esc) es el único fix PHY
con hipótesis viva**; F1 es barato y sumable; después, el peso debe ir al handoff/INTF y a
conseguir UNA señal de vida del DDIC (read LP con vídeo OFF **antes** de `dsi_mgr` poner
VID_MODE_EN, p. ej. en prepare antes de 0x11 — ventana que sí existe en mainline, contraria a
lo que decía PHY-LANE-RATE §C: `prepare_prev_first` pone vídeo en pre_enable, pero
`prepare_prev_first` solo reordena prepare/enable del *panel*, no impide un read LP antes del
primer 0x11 dentro de prepare… el video engine ya está ON, pero el DDIC en sleep aún no
escanea: esa lectura alternativa es la que queda por probar).

---

## Resumen (≤350 palabras)

El árbol no tiene driver PHY 4nm propio: la DT declara `qcom,palawan-dsi-phy-4nm` con fallback
`qcom,sm8650-dsi-phy-4nm` (`dsi_phy.c:579`) → `dsi_phy_4nm_8650_cfgs` con quirk V5_2
(`dsi_phy_7nm.c:1488-1510`), idéntico al binding de senemos (A2). VREG/RESCODE/HSTX/LPTX/
TX_DCTRL coinciden registro a registro con el vendor; difieren LANE_CFG 0x21/0x84 vs 0xAA/0xAA,
LANE_CTRL0 0x1f vs 0x15 y SSC (los tres refutados como causa del sordo por los controles
L40-L42), y los 14 TIMING_CTRL.

NUEVO: con ui=840 (la tasa vigente desde L70), el cálculo v4 del árbol reproduce exactamente
los bytes vendor de clk_zero/clk_prepare/hs_prepare; los deltas restantes (hs_exit +12,
hs_zero +11, clk_post +11, clk_pre +3, clk_trail +1, hs_rqst −3) son interpolación y quedan en
el lado conservador del TX. La aritmética cierra con el vendor: pclk/link 158.558.400,
byte 148.648.500 → OPP ceil 148.648.750 → **VCO 1.189.190.000 = 0x46E19970 bit-exacto**
(NUEVO; la "1 línea DT" de A3-N1 ya está hecha vía OPP). Única tasa no-vendor: esc_clk queda a
19,2 MHz TCXO (nadie la fija en el camino 6g) vs byte/8 = 18,58 MHz vendor (NUEVO, +3,4 %).

BTA sordo: NORMAL, no fallo demostrado — el vendor no lee este panel (ESD por GPIO, props de
build-id vacías; confirmado en el DTBO vivo), no programa LP/BTA timers (como mainline), la PHY
RX está habilitada (LPRX 0x3 lane 0) y su propio read bajo splash también falló. Pero implica
que nunca hemos confirmado que el DDIC reciba nada.

Dual-DSI: bonding correcto; DTBO parenta los clocks de dsi1 a la PLL de PHY0 (single-PLL,
consistente con vendor) — no regenerarlo con parents propios. Init/PPS van a ambos links.

Arranque: el deferral del host secundario (t≈47 s, disparado por el probe del táctil) retrasa
card1/modeset/DCS/vci; no rompe el bonding. Fix: acortar esa latencia, no tocar la PHY.

Veredicto: la PHY NO es el eslabón flojo del vídeo. Fixes PHY viables: F2 (esc=byte/8), F1
(timings vendor, barato). El peso va al handoff/INTF y a obtener una señal de vida del DDIC.
