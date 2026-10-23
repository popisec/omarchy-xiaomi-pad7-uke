# Cálculo de modo, OPP de byte-clock y DSC: vendor CAF vs mainline L33

Fecha: 2026-10-13. Ingeniero: subagente RE (aarch64 / Qualcomm display).
Restricciones respetadas: sin commit, sin tocar la tablet. Todo verificado en
ficheros locales citados con línea. Lo no determinable se marca como tal.

Fuentes primarias:
- Decompilado vendor (Ghidra 12.1.4): `build/vendor-re/decomp/*.c` (de `msm_drm.ko` de stock).
- Mainline L33: `build/kernel-pokes/k52L33-tree/drivers/gpu/drm/msm/` + panel
  `drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c` + `drivers/opp/core.c`.
- DT vendor: `~/proyectos/ubuntu-uke/stock/dtbo/stock_uke.dts` (nodo
  `qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid`, línea 13193) y
  `~/proyectos/ubuntu-uke/stock/dtbase/base-uke.dts`.
- DT vivo (overlay display): `~/gpu-work/ramaa/s21/dtbo-gpu/fase4-display.dts`.
- Verdad-terreno de stock Android:
  `build/evidencia/android-full/extracted-full/02-display/debugfs-dsi/.../dsi-ctrl-0/state_info`.
- Firma del fallo: `out/diag-L33/VENTA-MUERTE-acm-207s.txt` + `NOTAS-OMARCHY.md` (§L33).

Corrección previa al enunciado: `panel-clockrate = 0x46e19970` = **1.189.190.000 Hz**,
no 1.190.269.040 (diferencia 1.079.040 Hz, 0,09 %). Todos los cálculos de este
informe usan 1189190000.

---

## 1. El cálculo de byte-clock del vendor, al revés

### 1.1 Punto de partida (DT)

Nodo `timing@120` (`stock_uke.dts`): por link 1600 px activos, hfp `0x71`=113,
hbp `0x10`=16, hpw `0x10`=16 → htotal **1745**; 2136 + vfp 26 + vbp `0x92`=146 +
vpw 2 → vtotal **2310**; `panel-clockrate = 0x46e19970` = **1189190000**;
`qcom,mdss-dsi-bpp = 0x1e` = **30**; 4 lanes (`lane-0..3-state`); DSC 8bpp
(§4); topología `2,2,2`.

`panel-clockrate` es el **bit-clock por lane** (el clock serie HS), no un pixel clock:
1745×2310×120 = 483.714.000 Hz es el pixel clock nativo por link, y ningún
múltiplo/divisor de 1189190000 da 483,7 MHz. La prueba aritmética (§1.3) lo confirma.

### 1.2 Dónde está el `/8` (y el `/7`, y el factor DSC) en el código

Hay DOS funciones que calculan lo mismo por caminos distintos:

**A. `dsi_display_update_dsi_bitrate()`** (`build/vendor-re/decomp/dsi_display_update_dsi_bitrate.c`):
- `uVar14 = C × lanes` (línea 54; `C` = `param_2`, `uVar15` = nº lanes por popcount, l. 41-42).
- `uVar13 = uVar14 / bpp` (l. 57; `bpp` = tabla `bits_per_pixel[dst_format]`, l. 48-53).
- Sin DSC (`+0x49c == 0`): `byte = uVar14/lanes >> 3` (l. 60-64, **el `/8`**),
  `intf = byte / intf_div` (l. 67; `intf_div` = `+0x4b4` = 2, fijado por
  `dsi_display_update_byte_intf_div()`, `dsi_display_update_byte_intf_div.c:8-9`).
- Con DSC: `byte = C / 7`, `intf = C / 7`, `pix = (C×lanes/bpp)×0x10/7` (l. 70-74,
  **el `/7` y el factor `×16/7`**).
- Almacena `+0x580 = byte`, `+0x584 = intf`, `+0x588 = pix`, `+0x638 = C` (l. 81-84);
  `dsi_display_set_link_frequencies()` (`dsi_display_set_link_frequencies.c:18-20`)
  los vota tal cual vía `dsi_clk_set_link_frequencies()` — **sin cuantización a OPP**.

**B. `dsi_ctrl_update_host_config()`** (`build/vendor-re/decomp/dsi_ctrl_update_host_config.c`,
camino normal del modeset inicial, llamado desde `dsi_display_set_mode.c`):
- Rama vídeo (`*param_2 == 2`): deriva el bitrate total del *transfer time* DSC y el fps
  (l. 56-74; el ajuste DSC `uVar9 = uVar9×0x10/7` está en l. 66-68).
- Rama explícita (`*(param_2+0x24) = C ≠ 0`, l. 106-124): con DSC,
  `byte = ((C×lanes×16/7)>>4)/lanes = C/7`, `pix = C` (l. 110-123);
  sin DSC, `byte = redondeo_par(C)/8` (l. 96-104:
  `uVar12 = (uVar9+4>>3)+1 & 0x3ffffffffffffffe`, l. 99).
- También sin OPP: `+0x580/+0x584/+0x588` exactos (l. 135-137).

A nivel PLL (`dsi_pll_byteclk_recalc_rate.c:17-28`): `byte = VCO/div_reg` y después
`>>3` si `+0x9c == 0`, `/7` en caso contrario — la dualidad /8 vs /7 existe hasta en
el propio PLL. El VCO se programa fraccional-exacto para el rate pedido
(`dsi_pll_4nm_configure.c`, sin tabla de OPP): **el vendor no cuantiza**.

### 1.3 Los números (prueba de qué rama corre en el arranque)

Verdad-terreno, Android stock, `dsi-ctrl-0/state_info`:

```
BYTE_CLK = 148648750, PIXEL_CLK = 158558666, ESC_CLK = 19200000
```

Encaje exacto con **C = 1189190000, lanes = 4, bpp = 30** por la rama **sin `/7`**:

| señal | fórmula vendor | resultado | medido |
|---|---|---|---|
| byteclk | C/8 = 1189190000/8 | **148.648.750** | 148648750 ✅ exacto |
| pixclk | C×4/30 = 4756760000/30 | **158.558.666** (truncado) | 158558666 ✅ exacto |
| intfclk | byte/2 | 74.324.375 | (no capturado; ver §5.5) |
| bitclk/lane | C | 1.189.190.000 | (PLL lock OK en L33) |

Las ramas `/7` darían byte = 1189190000/7 = 169.884.285, **incompatible** con los
148.648.750 medidos. Conclusión: en el arranque el link corre a **bitclk = panel-clockrate
(1189,19 Mbps/lane), byte = bitclk/8 (148,65 MHz), pix = bitclk×lanes/30 (158,56 MHz)**,
con bpp=30 (`qcom,mdss-dsi-bpp = 0x1e`). El flag DSC interviene en el dominio de
transfer-time/pixel, no en el divisor del byte-clock, que es /8.

**No determinado**: qué rama exacta (transfer-time derivada vs C explícita) ejecuta el
vendor en el boot — el mapeo del campo modo en `+0x90` no se recupera del decompilado
solo. Es irrelevante para los números: ambas dan lo mismo con bpp=30, y el debugfs
dirime.

Margen del vendor: payload comprimido por link = 1600 px×8 bpp = 1600 B/línea
(+overhead ≈ 1616 B) en 3,6077 µs → ≈ 896 Mbps/lane necesarios; corre a 1189 → **+33 %**.

---

## 2. El cálculo de mainline, al revés (`dsi_host.c:639-682`)

Cadena completa, modo 120 Hz del panel (`panel-xiaomi-o82-dualdsi.c:589-601`:
clock 967428 kHz, hdisplay 3200, htotal 3490 — ya duplicado para sobrevivir al split):

1. `dsi_adjust_pclk_for_compression()` (`dsi_host.c:591-615`):
   `new_hdisplay = ceil(1600×8/30) = 427` por link (×2 = 854 en modo full),
   `new_htotal = 3490 − 3200 + 854 = 1144`.
2. `dsi_get_pclk_rate()` (`dsi_host.c:617-637`):
   `pclk_full = 967428000×1144/3490 = 317.116.800`; bonded (`dsi_manager.c:58`,
   `qcom,dual-dsi-mode` vivo en el overlay, `fase4-display.dts:314`) → `/2`:
   **pclk por link = 158.558.400**.
3. `dsi_byte_clk_get_rate()` (`dsi_host.c:639-660`): formato RGB888 → bpp=24,
   4 lanes: `byte = 158558400×24/32` = **118.918.800 Hz** (el "118,92 MHz").

¿Coincide con el vendor? **En fórmula, no; en pixel, sí; en byte, no**:

| | vendor (medido) | mainline (pedido) |
|---|---|---|
| fórmula byte | bitclk/8 | pclk_comprimido×24/(8×lanes) |
| fórmula pixel | bitclk×lanes/30 | mode_clock×new_htotal/htotal/2 |
| pixel/link | 158.558.666 | 158.558.400 (Δ 266 Hz, despreciable) |
| byte pedido | 148.648.750 | 118.918.800 |
| byte real | 148.648.750 (exacto) | **187.500.000 (OPP, §3)** |

Nótese la simetría curiosa: el vendor mete bpp=30 (no comprimido) sobre el bitclk y
mainline mete bpp=24 (formato RGB888) sobre el pclk comprimido; ambos aterrizan en
≈158,56 MHz de pixel. Pero el byte pedido difiere: 148,65 vs 118,92.

Por qué mainline pide menos: dimensiona el link para el payload comprimido
(118,92 ≈ necesidad real ≈ 112 + overhead, §1.3: margen +6 %), mientras el vendor
dimensiona con la convención bitclk/8 (margen +33 %). Ambos serían suficientes…
si mainline corriera a lo que pide. No lo hace (§3).

---

## 3. ⭐ Qué pasa con el link al 26 % más alto (análisis hardware)

### 3.1 El hecho: de 118,92 pedidos a 187,5 reales

El overlay de display vivo (`fase4-display.dts:390-401`) dota a los nodos DSI de
`mdss_dsi_opp_ml = {187,5 / 300 / 358 MHz}`. Ruta mainline 6g
(`dsi_link_clk_set_rate_6g`, `dsi_host.c:386-396`):
`dev_pm_opp_set_rate(dev, 118918800)` → ceil al OPP → **byte = 187.500.000**,
`bitclk = byte×8` (`dsi_host.c:2481`) = **1500 Mbps/lane**.
Ratio vs vendor: 1500000000/1189190000 = **1,2614 (+26,1 %)**. Verificado que el
overlay está vivo: el log base muestra los nodos mainline (`dsi@ae94000/panel@0`,
`out/diag-L33/BASE-pre-sddm.txt:549-557`) y `dual-dsi-mode` + `operating-points-v2`
están en el propio overlay (l. 307, 314). (El `boot-uke-k52L33.img` no trae DTB
—`dtb_size=0` medido en cabecera— y el DT vendor base/dtbo **no** trae OPP de DSI:
la única `opp-table` de `base-uke.dts` es la de SDHC. Sin el overlay no habría ceil;
con él, sí.)

### 3.2 Lo que el TDDI espera (y lo que no)

Afirmación de hardware, sin especulación: **DSI HS es fuente-síncrona** (clock lane
DDR + data lanes; el receptor muestrea con el clock reenviado, sin CDR ni "lock" de
frecuencia). El TDDI o82 **no conoce ni verifica** `panel-clockrate`: sigue el clock
lane que le llegue. Un bitclk un 26 % más rápido **no impide por sí mismo** la
adquisición de los lanes, siempre que esté dentro del máximo rated del TDDI
(**máximo del o82 no determinado** — 1500 Mbps/lane está dentro de lo habitual en
TDDI, así que la velocidad en sí probablemente no sea el asesino).

### 3.3 El mecanismo real: timings de PHY programados para otra velocidad

El cálculo de timings del PHY usa el rate **pedido**, pero el PHY corre al rate **OPP**:

- `msm_dsi_host_get_phy_clk_req()` (`dsi_host.c:2462-2485`): `bitclk_rate = byte_pedido×8`
  = **951.350.400 bps**. Ningún redondeo OPP interviene aquí.
- `msm_dsi_dphy_timing_calc_v4()` (`phy/dsi_phy.c:374-471`) traduce la norma MIPI a
  cuentas de ciclos de byteclk para 951 Mbps; `dsi_7nm_phy_enable()`
  (`phy/dsi_phy_7nm.c:966-983`) las programa.
- El PLL, en cambio, engancha a 1500 Mbps (sin bit `PLL_UNLOCKED` en L33: firma compatible).

Todo tiempo programado en ciclos sale un factor 951,35/1500 = **0,634** en nanosegundos
reales. Réplica exacta de las fórmulas del driver (ver §herramienta: `linear_inter` en
`phy/dsi_phy.c:18-29`):

| parámetro | programado (cuentas @951M) | mínimo MIPI en cuentas @1500M | veredicto a 1500M reales |
|---|---|---|---|
| clk_zero | 32 | 48 | ❌ **−33 % bajo el mínimo** |
| clk_trail | 9 | 12 | ❌ bajo el mínimo |
| hs_prepare | 8 | 9 | ❌ bajo el mínimo (42,62 ns vs mín 42,66 ns) |
| hs_trail | 8 | 11 | ❌ bajo el mínimo |
| clk_prepare | 8 | [8,17] | ✅ justo en el borde |
| hs_zero / hs_exit | 35 / 36 | [20/18, 255] | ✅ (saturan en interpolación) |
| (referencia vendor @1189M: hs_prepare=10, hs_trail=11 — en spec a su velocidad) | | | |

`T_HS_PREPARE` y `T_HS_TRAIL`/`T_CLK_*` fuera de spec en el lado TX significan que el
receptor puede no detectar la entrada en HS o corromper el EOT: **los lanes no
enganchan a nivel protocolo aunque el clock llegue**. Ese es el "link más rápido de
lo esperado impide el lock", con números, no con intuición.

### 3.4 Compatibilidad con la firma (PLL lock OK + FIFO + 10-15 DCS)

- **PLL lock OK (sin `0x20`)**: esperado. El VCO engancha a 1500 Mbps sin problema;
  el fallo está en los tiempos de entrada/salida de HS, que el bit `PLL_UNLOCKED`
  (`dsi_clk_status()`, `dsi_host.c:1725-1734`) no vigila. ✅ compatible.
- **`status=4` (`DSI_ERR_STATE_FIFO`, `dsi_host.c:92`, vía `REG_DSI_FIFO_STATUS`,
  `dsi_fifo_status()` en `dsi_host.c:1696-1710`)**: son FIFOs del **controlador TX**
  (CMD_DMA/DMA/VIDEO under/overflow), no del panel. En L33 disparan **10 veces en
  `K47-host-en` (207,967 s) ANTES de los resets del panel (207,979 s+)**
  (`VENTA-MUERTE-acm-207s.txt:118-136`): el motor de vídeo arranca contra un link
  con HS roto y sus FIFOs yerran sin que el panel haya intervenido. ✅ compatible,
  y además **exculpa al panel/PHY-RX como causa primera**: el error nace en el TX.
- **10-15 DCS ya enviados**: van en **LP mode**, temporizado por `esc_clk`
  (ruta 6g: `esc = clk_get_rate()` existente, `dsi_host.c:680` — LP no depende del
  byte OPP). Que los comandos LP funcionen con el vídeo HS roto es exactamente lo
  esperado. ✅ compatible.
- **`VIDEO_DONE` nunca**: el motor no completa ni una trama contra HS inválido;
  el timeout de 70 ms (`dsi_wait4video_done()`, mainline-only) es el síntoma, no la causa.

Salvedades explícitas: (a) el byteclk vivo real (187,5) es **inferido** de código+DT,
no medido con `clk_summary` — falta esa captura; (b) el máximo rated del TDDI o82 es
desconocido; (c) `TIMING_FLUSH` (L34, §5.2) es un sospechoso independiente en la misma
zona del síntoma y este informe no lo excluye.

---

## 4. DSC: configuración exacta y papel en el cálculo

### 4.1 Vendor (DT + drivers)

DT (`stock_uke.dts`, `timing@120`): `bit-per-pixel = 8`, `bit-per-component = 10`,
`slice-width = 0x320` = **800**, `slice-height = 0x18` = **24**,
`slice-per-pkt = 1`, `scr-version = 0` (pre-SCR), `version = 0x11` (1.1),
`block-prediction-enable`, topología `2,2,2` (= 2 LM / 2 DSC / 2 interfaces).
Parámetros derivados estándar: `slice_count` por interfaz = 1600/800 = **2**,
`chunk_size = ceil(800×8/8)` = **800**, bytes/línea/interfaz = **1600**,
`eol = 1600 % 3` = **1**, `pkt_per_line` = 2.
Lado DPU/vendor: `sde_dsc_populate_dsc_config.c`, `sde_dsc_parse_dt.c`,
PPS generada en runtime (`sde_dsc_create_pps_buf_cmd.c`).
(Las tablas RC del vendor no se compararon entrada a entrada con las del DRM —
punto abierto menor.)

### 4.2 Mainline (L33)

`o82_dsc_config` (`panel-xiaomi-o82-dualdsi.c:639-651`): v1.1, slice 800×24,
`slice_count = 2`, bpc 10, `bpp = 8<<4`, `block_pred_enable`, `convert_rgb`.
`dsi_populate_dsc_params()` (`dsi_host.c:1940-1967`): *"DPU supports only pre-SCR
panels"* + `drm_dsc_setup_rc_params(PRE_SCR)` → **equivale a scr-version = 0**;
`slice_per_pkt = 1` hardcodeado (`dsi_update_dsc_timing()`, `dsi_host.c:927-988`,
`bytes_per_pkt = chunk = 800`, `WC = 800`, `eol = 1`, `pkt_per_line = 2`).
PPS: el driver de panel la empaqueta con `drm_dsc_pps_payload_pack()` y la envía
antes del vídeo (`panel-xiaomi-o82-dualdsi.c:388-398`, fix L37) — tapando el hueco
V1 (el init vendor no trae PPS: el IC viene preconfigurado).

**Veredicto DSC: coinciden** en todos los parámetros visibles
(versión, slice 800×24, bpp 8, bpc 10, pre-SCR, 2 slices/interfaz, 1 slice/paquete,
predicción por bloques, convert_rgb, chunk 800, eol 1). No es el culpable.

### 4.3 ¿Manda el DSC el cálculo de byte-clock? Sí, en ambos

- Mainline: `dsi_adjust_pclk_for_compression()` usa `dsc.bpp_int/bpc` (§2.1). Sin el
  bloque DSC, el byte pedido sería `pclk_nativo×24/32` por link
  (= 483714000×24/32 = 362,8 MHz → OPP 358 o fallo de rango): el DSC es lo que baja
  el pedido a 118,92.
- Vendor: el factor `×16/7` y el selector `/7 vs /8` existen en ambas funciones
  (§1.2); en el arranque manda el camino `/8` con bpp=30 (§1.3), y el pixel resultante
  (158,56 MHz) es de dominio comprimido. Sin DSC no saldrían esos números.

---

## 5. Divergencias modo programado mainline vs vendor, por relevancia

**R1. OPP ceil del byte-clock + timings de PHY a velocidad equivocada (el mecanismo del §3).**
`soc/.../fase4-display.dts:390-401` (OPP {187,5/300/358}) × `dsi_host.c:386-396`
(`dev_pm_opp_set_rate(byte_pedido)`) × `dsi_manager.c:415-431` (ceil en `mode_valid`)
× `dsi_host.c:2479-2482` (phy pide `byte_pedido×8` = 951 Mbps) × `phy/dsi_phy.c:374-471`
+ `phy/dsi_phy_7nm.c:966-983` (timings para 951 Mbps corriendo a 1500).
Efecto: 4 parámetros HS bajo mínimos MIPI (§3.3). Acción propuesta: fijar el rate del
link al del vendor (pedir 148,65 MHz exactos o añadir el OPP 148,65/1500…) o calcular
los timings con el rate post-OPP, y capturar `clk_summary` vivo para confirmar el 187,5.

**R2. `TIMING_FLUSH` ausente (ya evidenciado en L34; se confirma y acredita).**
El vendor escribe `base+0x1e4` (= 0x1e0 mainline) tras programar timing
(`dsi_ctrl_hw_cmn_set_video_timing @0x12d75c`: `WRITE(base+0x1e4,1)`, ver comentario
en `dsi_host.c:1100-1125`); mainline programa 6 registros en `dsi_timing_setup()`
(`dsi_host.c:989-...`) y no hace flush: el timing queda en sombra. Explica de forma
independiente "motor que nunca arranca + FIFO en host-en antes de los resets".
No lo re-investigo; lo dejo como causa co-principal junto a R1.

**R3. Espera `VIDEO_DONE` 70 ms (mainline-only, dado del enunciado).**
`dsi_wait4video_done()` (`dsi_host.c:1246-1262` según enunciado; el árbol poke la trae
desplazada por instrumentación — `NOTAS-OMARCHY.md` la cita en `:1196-1212`/`:1301`;
verificar línea exacta contra el árbol que se flashee) + `dsi_wait4video_eng_busy()`
antes de cada DCS. El vendor solo espera `DMA_DONE` 200 ms y envía los DCS con el
motor de vídeo apagado. Convierte un link roto en muerte (cada DCS bloquea 70 ms);
L36 ya retiró el bloqueo (ver revisión adversarial en NOTAS: experimento
confundido, no concluyente).

**R4. Clock lane en HS-continuo desde `power_on` vs LP11 del vendor durante resets.**
`dsi_ctrl_enable()` (`dsi_host.c:909-916`, citado en `panel-xiaomi-o82-dualdsi.c:669-674`)
fuerza bitclk HS continuo antes de rieles/reset; el vendor declara `lp11-init` y
mantiene LP11 durante la secuencia (`stock_uke.dts`, panel node); el panel lleva
`MIPI_DSI_CLOCK_NON_CONTINUOUS` (`panel-xiaomi-o82-dualdsi.c:671-673`, L37 descartado
por la revisión). Divergencia programada real; relevancia media (el TDDI puede exigir
LP11 en reposo tras reset).

**R5. `byte_intf_clk`: 59,46 MHz (mainline) vs 74,32 MHz (vendor).**
Mainline: `byte_intf = byte_pedido[/2, div_2=true]` = 118918800/2 = **59.459.400**
(`dsi_host.c:2566-2568`, `phy/dsi_phy.c:356,462`); vendor: 148648750/2 = **74.324.375**
(§1.3; medido byte, intf inferido de `+0x584`). Además el intf mainline deriva del
rate pre-OPP: ni siquiera es coherente con su propio byte (187,5). Relevancia
baja-media (reloj de interfaz controlador↔DPU; sin evidencia de que muerda).

**R6. Timing DSI por link en dominio comprimido (coherente en ambos, verificar).**
Mainline programa por link h_total=572/hdisplay=427 (`dsi_timing_setup`,
`dsi_host.c:1016-1081`: split bonded + `h_total−=hdisplay` + `bytes_línea×8/30`);
línea = 572/158558400 = 3,60775 µs ≃ línea vendor 1745/483714000 = 3,60765 µs.
Auto-consistente; el equivalente vendor en registros no se volcó (`reg_dump` de
stock devuelve ceros — captura no válida). Sin divergencia accionable hoy.

**R7. DSC sin divergencias (§4).** Solo orden de PPS (runtime-vendor vs prepare-L37)
y tablas RC no cotejadas. No accionar.

**R8. Pixel clock Δ266 Hz (158.558.400 vs 158.558.666).** Ruido de redondeo. No accionar.

**R9. ESC (19,2 MHz vendor medidos).** Mainline reutiliza el existente; sin captura
viva. No accionar hasta medir.

---

## 6. Tabla final de números (todo en Hz salvo indicación)

| señal | vendor (stock, medido/inferido) | mainline L33 pedido | mainline L33 real |
|---|---|---|---|
| bitclk/lane | 1.189.190.000 (= panel-clockrate) | 951.350.400 (= 118918800×8) | 1.500.000.000 (= 187,5M×8) |
| byteclk | 148.648.750 (medido) | 118.918.800 | 187.500.000 (OPP ceil) |
| pixclk/link | 158.558.666 (medido) | 158.558.400 | 158.558.400 (clk_set_rate exacto) |
| intfclk | 74.324.375 (inferido /2) | 59.459.400 (/2 pre-OPP) | 59.459.400 |
| escclk | 19.200.000 (medido) | existente (≈19,2M, sin verificar) | — |
| línea vídeo | 3,60765 µs | 3,60775 µs | — |
| PHY HS timings | en spec @1189M | calculados @951M | **4/7 bajo mínimos @1500M** |

## 7. Qué falta por medir (sin tablet, queda pendiente)

1. `clk_summary` vivo (byte/px/intf/esc reales) — confirma R1 sin inferencia.
2. `REG_DSI_FIFO_STATUS` vivo (qué bit exacto dentro de `status=4`).
3. `reg_dump` con el enable CMD-DMA-stats del vendor (el capturado da ceros).
4. Tablas RC DSC vendor vs `drm_dsc_setup_rc_params(PRE_SCR)` entrada a entrada.
5. Máximo rated del TDDI o82 (para cerrar si 1500 Mbps/lane es OOS eléctrico o no).
