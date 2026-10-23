# PANEL-REVISION B2 — EL CONTROLADOR DSI MAINLINE (dsi_host.c) — 2026-10-15

> Agente B2 de la revisión por fases. SOLO lectura de código + este informe; nada tocado en el
> árbol. Chunk: `drivers/gpu/drm/msm/dsi/` del árbol vivo
> `build/kernel-pokes/k52-L16-tree` (estado L72: toggle retirado, ratelimit FIFO puesto).
> Entradas: A1 (evidencia), A2 (Fedora/senemos), A3 (verdad vendor). **NUEVO** = no escrito
> antes en ningún informe; **SEMI** = dato conocido + dato nuevo al lado; [M] medido,
> [C] derivado del código, [H] hipótesis. Las líneas de `dsi_host.c` son del árbol vivo (L72).

---

## 1. LA ARITMÉTICA COMPLETA DEL MUNDO L71/L72 (todas las constantes, con fichero:línea)

Modo activo (el único expuesto): **120 Hz grupo 0**, `panel-xiaomi-o82-dualdsi.c:720-732`:
3200×2136, clock **967.428 kHz** (= 3490×2310×120/1000), htotal 3490 (hfp 226, hs 32, hbp 32),
vtotal 2310 (vfp 26, vs 2, vbp 146). DSC (`:763-778`): bpc 10, bpp 8<<4, slice 800×24,
slice_count **2 por link**, `slice_chunk_size = 800` ⇒ **1600 B/línea/link**
(`msm_dsc_get_bytes_per_line` = slice_count×chunk, `msm_dsc_helper.h:22-25`). Lanes 4, RGB888,
`mode_flags = VIDEO | LPM | CLOCK_NON_CONTINUOUS` (`:803-805`) ⇒ non-burst **sync-event**,
comandos en LP, sin forced-HS-clock (K48-A). `is_dual_dsi = true`; hardware: DSI 6G **v2.9.0**
→ `sm8650_dsi_cfg` (io_start 0xae94000/0xae96000, io_offset=4) con ops v2_9
(`dsi_cfg.c:197-207, 344-345`).

### 1a. PCLK por link — `dsi_host.c:589-637` (mundo 30)

`dsi_get_pclk_rate` → `dsi_adjust_pclk_for_compression` (con dsc) + `/2` bonded (`:633-634`):

```
hdisplay      = 3200/2            = 1600                      (:602-604)
new_hdisplay  = DIV_ROUND_UP(1600·8, 10·3) = DIV_ROUND_UP(12800,30) = 427   (:606-607)
              ×2 = 854                                                        (:609-610)
new_htotal    = 3490 − 3200 + 854 = 1144                      (:612)
pclk_full     = 967.428.000 × 1144/3490 = 317.116.800         (:614)
pclk/link     = 317.116.800/2 = **158.558.400 Hz**            (:633-634)
```
Medido en L67/L71: **158,558 MHz** (vendor 158.558.666; Δ266 Hz) — COHERENTE.

### 1b. Byte clock — `dsi_host.c:639-677` (hunk L70, :660-663)

```
bpp    = 10·3 = 30 (con dsc; sin L70 sería 24 del RGB888)       (:660-663)
pclk_bpp = mult_frac(158.558.400, 30, 8·4=32) = **148.648.500 Hz**  (:670-674)
bitclk    = byteclk·8 = 1.189.188.000 (vendor DT 1.189.190.000; Δ2 kHz)  (:2494-2496)
```
Medido L70/L71: **148,648 MHz** en clk_summary — COHERENTE y = vendor (A3 §2a, N1-N5).

### 1c. ACTIVE_H / TOTAL del host DSI — `dsi_timing_setup` `:1011-1157` (mundo 24, tras L71)

Bonded halving `:1037-1043`; bloque DSC `:1045-1097`:

```
h_total = 3490/2 = 1745;  ha_start = 1745 − 3426/2 = 32;  hs_end = 32/2 = 16
h_total −= 1600                    → 145                    (:1083)
bits_per_pclk = 24  (wide_bus_enabled=false, UKE-L71)       (:1089-1091)
hdisplay = DIV_ROUND_UP(1600·8, 24) = DIV_ROUND_UP(12800,24) = **534**  (:1093)
h_total += 534 → **679**; ha_end = 32+534 = 566             (:1095-1096)
```
Registros resultantes (`:1103-1119`) — **clavados al vendor en L71** (A1 §2):
ACTIVE_H `0x02360020`, ACTIVE_V `0x08EC0094` (148‖2284), TOTAL `0x090502a6` (678‖2309),
HSYNC `0x00100000`. Widebus OFF se materializa en `msm_dsi_host_is_wide_bus_enabled`
(`:814-826`), que en modo vídeo suprime `DSI_VID_CFG0_DATABUS_WIDEN` (`:853-854`;
bit 25 de VID_CFG0, `dsi.xml:155`) — **no queda ningún sitio que lo vuelva a poner** (A1 §6.4
respondido: con el hack a `false`, ni VID_CFG0 (vídeo) ni CMD_MODE_MDP_CTRL2 (`:879-880`)
ni el INTF (ver 1d) llevan widen).

### 1d. El lado INTF/DPU — `dpu_encoder_phys_vid.c` + `dpu_hw_intf.c` (mundo 24 del feed)

El modo llega COMPLETO a cada phys encoder y se divide por split_role ≠ SOLO
(`dpu_encoder_phys_vid.c:287-300`): hdisplay 1600, htotal 1745, hsync_start 1713,
hsync_end 1729 ⇒ hbp 16, hs 16, hfp 113 (= porches per-link del DT vendor, A3 §2b).
`timing->wide_bus_en = dpu_encoder_is_widebus_enabled` (`:99`) →
`msm_dsi_wide_bus_enabled` (`dsi.c:20-23`) → nuestro hack L71 = **false**.
`timing->compression_en = dpu_encoder_is_dsc_enabled` (`:100`) = true. Luego L71-intf24
(`:133-143`):

```
width = 1600 × 8 / 24 = **533**  (¡división ENTERA, 12800/24 = 533.33!)
xres = 533;  dce_bytes_per_line = 1600
hsync_period = 16+16+533+113 = **678** px/línea  (dpu_hw_intf.c:106-107)
data_width   = DIV_ROUND_UP(1600, 3) = **534** (dce, wide_bus off)  (dpu_hw_intf.c:191-203)
INTF_CONFIG2 bit12 (DCE_DATA_COMPRESS) = ON  (mdss major 10 ≥ 7)    (:201-203, :264-269)
DATA_HCTL_EN OMITIDO (compression_en && !wide_bus_en)               (:265-266)
```

### 1e. Los registros DSC del host DSI — `dsi_update_dsc_timing` `:949-1009`

Modo vídeo (`:1005-1008`, REG 0x29c `VIDEO_COMPRESSION_MODE_CTRL`, `dsi.xml:369-375`):
EN=1, DATATYPE=0x0B (compressed pixel stream), PKT_PER_LINE=slice_per_intf/1>>1 = **1**,
**WC = slice_chunk_size = 800** (fix 1/3 Nie/Marek ya vivo), EOL_BYTE_NUM = 1600%3 = **1**.
El registro 0x29c+io4 = **0x2a0 del vendor** (A3 §2b "DSC-side 0x2a0"): el vendor escribe
`(…)<<5 | …<<16 | …<<4 | 0xb01` — el 0xb01 descompone en EN(bit0)+DATATYPE 0xb(bits8-11),
mismo mapa de campos que mainline. **Paridad estructural CONFIRMADA**; único campo sin
cerrar: el valor exacto de EOL_BYTE_NUM vendor (`dsc+0x9c`).

### 1f. VEREDICTO DE COHERENCIA

| Par | Valor | ¿Coherente? |
|---|---|---|
| Feed INTF | 1600 B/línea en 534 px (data_width, DCE) | sí, = ventana activa DSI (534 px) |
| ACTIVE_H DSI | 534 px × 3 B = 1602 B ≥ 1600 B | sí (2 B de padding EOL) |
| Drenaje enlace | 4 × 148,6485 = 594,6 MB/s | sí: fill real = 1600 B / (678 px @158,56 = 4,277 µs) = **374,1 MB/s** ⇒ 59 % de holgura; explica underruns 1/1 de L71 (solo arranque) vs 1929/1929 de L69 |
| **Línea INTF vs DSI** | INTF hsync_period **678** (por el truncado 533) vs DSI TOTAL **679** | **NO exacto**: 1 px/línea de sesgo (FIX-3) |
| **Refresh efectivo** | 158.558.400 / (679 × 2310) = **101,1 Hz** (INTF 101,25) | **NUEVO [C]**: el pclk se deriva con el htotal del mundo-30 (572) pero la línea real del DSI/INTF es 679/678 px del mundo-24 ⇒ el modo "120 Hz" corre a ~101 Hz. El vendor programa EXACTAMENTE los mismos 3 registros con el mismo pclk stock (158,558) — o su panel también va a ~101 Hz en este grupo, o su pclk no pacea el motor de vídeo (variante de N1: "dos mundos" ya documentados; la parte del REFRESH es nueva). No explica el negro ni el flood, pero sí por qué "120 Hz" y 158,558 MHz no cuadraban aritméticamente |

**El mecanismo exacto de L69** (ledger #648, "feed, ACTIVE_H y byte en el MISMO mundo"):
L69 puso el INTF en mundo-24 (width 533/534, ventana de datos de 534 px) pero dejó el DSI en
mundo-30 (ACTIVE_H 427, h_total 572, widebus ON). Resultado: ventana de PETICIÓN del DSI
(427 px ≈ 1601 B) ≠ ventana de ENTREGA del INTF (534 px ≈ 1600 B) y longitudes de línea
572 vs 678 px. Los datos que el INTF entrega fuera de la ventana activa del DSI no tienen
consumidor → `VIDEO_MDP_FIFO_OVERFLOW` + underrun 1:1 con vsync en ambos INTF. No es un
problema de tasa (el byteclk era el mismo): es un problema de VENTANA/LONGITUD desalineada.

---

## 2. EL PATH DEL VIDEO ENGINE Y EL MECANISMO DEL FLOOD

### 2a. Encendido normal (sin toggle)

`msm_dsi_host_power_on` (`:2566-2633`): clocks → `dsi_timing_setup` (`:2614`) →
`dsi_sw_reset` (`:2615`) → `dsi_ctrl_enable` (`:2616`), que escribe VID_CFG0
(BLLP_POWER_STOP+EOF_BLLP siempre en LP `:848-849`, traffic sync-event `:850`, dst RGB888,
VC0), CMD_DMA_CTRL=FROM_FRAME_BUFFER|LOW_POWER (`:886-888`), TRIG_CTRL con
**MDP_TRIGGER=TRIGGER_NONE** (`:893`), CLKOUT (t_pre/post de la PHY, `:901-903`), EOT append
(`:911-914`), `ERR_INT_MASK0=0x13ff3fe0` (`:917`), **arma DSI_IRQ_MASK_ERROR** (`:919`) y
CTRL=CLK_EN|lanes|ENABLE (`:941-943`). VID_MODE_EN llega después vía
`msm_dsi_host_enable`→`dsi_op_mode_config(true,video)` (`:2514-2533`, `:1189-1212`) en el
pre_enable del bridge — el INTF del DPU arranca DESPUÉS, con lo que el motor queda ARMADO
esperando datos (S4-DIAG histórico: BUSY=0 con motor parado). IRQs de error armadas en AMBOS
links (`dsi_manager.c:250-252`).

### 2b. El toggle L68 y el flood (mecanismo completo)

El helper sigue VIVO en el árbol: `msm_dsi_host_video_engine_set` (`:1214-1230`,
EXPORT_SYMBOL; el llamador se retiró en L72, `panel-xiaomi-o82-dualdsi.c:686-692`). Hace
`CTRL &= ~VID_MODE_EN` (bit 1, `dsi.xml:98`) **manteniendo ENABLE** y `wmb()`. Evidencia
combinada (A1 §3): L67 sin toggle = limpio; L68/L69/L70/L71 con toggle = flood en CUALQUIER
mundo; FIFO_STATUS latcheado = **0xdddd1011**. Decodificado contra `dsi.xml:118-144`:

```
0xdddd1011 = bit0  VIDEO_MDP_FIFO_OVERFLOW
           | bit4  (reservado en XML mainline)
           | bit12 DLN0_LP_FIFO_EMPTY
           | bits 16/18, 20/22, 24/26, 28/30 = DLN0..3_HS_FIFO_EMPTY + _OVERFLOW
```
EMPTY **y** OVERFLOW simultáneos en los 4 carriles HS = las máquinas de estado de las FIFOs
de carril quedaron latchadas en un estado inconsistente al cortar el motor (un overflow
anotado con la FIFO ya vacía). El bit0 es el overflow de la FIFO vídeo-MDP.

Bucle del flood, código en mano:
1. IRQ de nivel lee ISRs y llama `dsi_error` (`:1743-1756`) → `dsi_fifo_status` (`:1698-1716`)
   limpia el sticky por write-back (`:1706`), pone `DSI_ERR_STATE_FIFO`, encola `err_work`.
2. `dsi_err_worker` (`:1635-1651`): el patrón VIDEO no tiene bit7 (CMD_MDP underflow) ⇒
   **`dsi_sw_reset` NO se dispara** (ledger #650 confirmado en código `:1643-1644`);
   limpia `err_work_state` y **RE-ARMA `DSI_IRQ_MASK_ERROR` incondicionalmente** (`:1650`).
3. La condición latcheada re-dispara al instante → IRQ → worker → re-arm → … 143k líneas/20 s
   en 2 links (L71).
4. Aunque el bit7 existiera, `dsi_sw_reset` (`:1159-1187`) cae `DSI_CTRL_ENABLE` durante
   **msleep(20)** (`:36`, `:1178-1180`) con el INTF alimentando ⇒ re-error garantizado. El
   vendor resetea con pulso instantáneo y otro gateo de CLK_CTRL (N2: `dsi_ctrl_hw_cmn_ctrl_reset`,
   0x11C←0x01000A00, 0x118 vendor(=REG_DSI_RESET mainline 0x114) 1/0 con dsb, sin dormir).
   Mapa de offsets: vendor +0x118 ↔ mainline `REG_DSI_RESET` 0x114 (io_offset 4).

**Respuesta a la pregunta 2 del encargo:** el flood NO es re-armado de IRQ "mientras el motor
está apagado" ni FIFO residual pasajero: es el **latch de desincronización** que el toggle
deja en las FIFOs vídeo/carril (0xdddd1011 es su huella), sostenido por el re-armado sin freno.
La reinserción de VID_MODE_EN no resincroniza nada: no hay FLUSH, no hay realineación de línea
ni de frame (MDP_TRIGGER=NONE), y el `dsi_sw_reset` de `msm_dsi_host_disable` (`:2547`) nunca
interviene en el camino de error. Por eso el flood sobrevive a CUALQUIER mundo de timing.

### 2c. Dual-DSI bonded en el host (encargo item 6)

- Bonding por DT: `qcom,dual-dsi-mode` + `qcom,master-dsi` + `qcom,sync-dual-dsi`
  (`dsi_manager.c:48-67`). PLL0 (PHY master) alimenta ambos links (`:100-103`).
- `mode_set`: el MISMO adjusted_mode a ambos hosts (`:406-408`); `power_on`: ambos hosts con
  `is_bonded_dsi=true` (`:230-244`) ⇒ `dsi_timing_setup`+`dsi_ctrl_enable` IDÉNTICOS en los
  dos links (misma matemática halved). **SPLIT_LINK no existe en mainline** (no hay registro
  en `dsi.xml`) y el vendor tampoco lo usa para o82 (RE-GAPS §1) — paridad.
- pre_enable solo en el link master (`:294-296`); IRQs de ambos (`:250-252`).
- Comandos: writes con `need_sync` se emiten UNA vez pero con `cmd_xfer_commit` a AMBOS hosts
  (`msm_dsi_manager_cmd_xfer_trigger :550-565`; DSI_0 finge éxito `:517-518`). Los triggers
  son **software-secuenciales** (skew ~µs entre links; el vendor también serializa por ctrl).
- Reads: `need_sync=false` (por `!is_read`, `:503`) ⇒ cada link lee por su cuenta (así lo
  explotaron L65/L67/L68). Asimetría DSI_0 solo afecta writes sincronizados.

---

## 3. GESTIÓN DE ERRORES FIFO (los S4-DIAG) y FRENO ESTILO VENDOR

Estados actuales: `dsi_err_worker` re-arm incondicional (`:1650`) + `dsi_sw_reset` solo para
`DSI_ERR_STATE_MDP_FIFO_UNDERFLOW` (`:1643-1644`); prints: FIFO ya con ratelimit L72
(`:1710`), `dsi_timeout_status` **sin ratelimit** (`:1677-1678`), `dsi_wait4video_done` sin
ratelimit (`:1262-1265`), CMD_DMA timeout one-shot (`:1524-1531`). El vendor (A3 §5a/5b):
contadores +0x770/+0x778 con ventana 0xfa jiffies (250 ms) y umbral 0x10 (**16**); al superar
el umbral NO re-arma y delega en soft-reset de host → (en overflow) `dsi_ctrl_reset(0x100000)`
+ `dsi_phy_lane_reset` + re-en del engine → panel_dead/re-prepare. A1 §6.1 y A3 N3 lo pedían;
abajo está el port EXACTO (B2-A) y los ratelimits (B2-B).

---

## 4. compression_en / CONFIG2 bit12 (encargo item 4) — RESPUESTA

**Sí: nuestro lado DPU lo programa.** `timing->compression_en` viene de
`dpu_encoder_is_dsc_enabled` (`dpu_encoder_phys_vid.c:100`) y `dpu_hw_intf.c:201-203` pone
`INTF_CFG2_DCE_DATA_COMPRESS` (bit 12, `:100`) en `INTF_CONFIG2` (0x060) cuando
`mdss_ver->core_major_ver >= 7` — SM7675 = mdss 10.1 ⇒ ON. El vendor hace lo mismo
(`sde_hw_intf_enable_compressed_input` 0x60|=0x1000, A3 §4). **Paridad estructural
verificada en código (cierra la hipótesis H-C de A3 en su mitad mainline).** Verificación
post-boot barata: `devmem 0xaeae060`/`0xaeaf060` no hace falta — el discriminante ya medido
es ACTIVE_H 0x02360020 + underruns 1/1. Lo que SÍ falta de paridad en el host DSI es el
registro de compresión 0x2a0: mainline lo escribe (`:1005-1008`) con WC=800/EOL=1;
el vendor escribe el mismo registro con su propio empaquetado (campo EOL sin resolver, §1e).
El lado INTF usa `data_width = DIV_ROUND_UP(1600,3)=534` del `dce_bytes_per_line`
— correcto; el residuo del L71-intf24 es solo el TRUNCADO del width (FIX-3).

---

## 5. COMANDO-DMA Y BTA: ¿por qué el DDIC está MUDO? (encargo item 5)

Hallazgos del host relevantes al RX, todos verificados por grep (ninguna referencia a
`LP_TIMER_CTRL` ni `HS_TIMER_CTRL` en `drivers/gpu/drm/msm/dsi/` ni `disp/`):

1. **NUEVO [C]: `REG_DSI_LP_TIMER_CTRL` (0xb4: LP_RX_TO, BTA_TO, `dsi.xml:246-249`) y
   `REG_DSI_HS_TIMER_CTRL` (0xb8: HS_TX_TO/RESOLUTION/STOP_EN, `dsi.xml:250-254`) NUNCA se
   escriben.** Quedan en reset de HW. Si BTA_TO=0 ⇒ el BTA aborta al instante ⇒ RDBK_DATA
   queda a 0 ⇒ `dsi_cmd_dma_rx` lee ceros (`:1579-1583`) ⇒ `buf[0]=0` → caso default
   "Invalid response cmd" → **ret=0 con 0 bytes, SIN ningún error**: exactamente el síntoma
   L67/L68 (20/20 ret=0, vídeo ON y OFF). Esta es la candidata nº2 del sordo, tras los 14
   TIMING_CTRL RX de la PHY (nº1, PHY-LANE-RATE §A) — y es la mitad que me toca: la PHY
   condiciona el LP-RX eléctrico, el host condiciona los TIMERS del BTA.
2. El propio vendor **no lee en flujo normal** (N4): sus únicas lecturas son de fábrica y
   también fallaron en vivo. El mudo no contradice al vendor; es un diagnóstico nuestro.
3. Config del TX/RX en modo vídeo: `xfer_prepare` enciende `CMD_MODE_EN` SOBRE el motor de
   vídeo vivo (`:2263-2267`), CMD_DMA_CTRL LOW_POWER fijo (`:886-888`; LPM del panel ⇒ no se
   apaga en `:2260-2261`), EOT RX_IGNORE sin poner (`:911-914`), SET_MAX_RETURN_PACKET +
   clear de RDBK por lectura (`:2330-2355`). Writes err=0 (DMA del host OK); el ack-error
   del DDIC llegaría por ACK_ERR_STATUS (`:1653-1665`) — silencio total = nada volvió por la
   lane, consistente con timers/RX-PHY, no con el DMA.
4. **NUEVO [H]: `dsi_wait4video_eng_busy`** duerme `usleep(2000,4000)` "para saltar el BLLP"
   (`:1290-1292`) — calibrado para BLLPs de ms en modos antiguos; en nuestro modo el BLLP
   (porches) dura 145 px ≈ **0,91 µs** y el frame 9,9 ms: la siesta de 2-4 ms cae en la
   SIGUIENTE línea activa. Puede meter comandos LP en mitad del HS de una línea (contención
   interleave: STATUS0 bit31). No explica el mudo OFF-contexto (L68), pero sí puede
   contaminar lecturas ON-contexto. Bajo prioridad.
5. El BTA_DONE IRQ (bit 20, `dsi.xml:84`) existe pero mainline no lo usa (solo CMD_DMA_DONE
   para completar la lectura, `:1777-1781`).

---

## 6. TABLA DE DISCREPANCIAS vs VENDOR (fichero:línea)

| # | Punto | Mainline/L72 | Vendor (A3) | Estado |
|---|---|---|---|---|
| D1 | Byteclk x30 derivado del pclk | `dsi_host.c:660-663` | bitclk del DT independiente (N1) | conocido (L70); riesgo latente si cambia el modo |
| D2 | **Refresh efectivo 101,1 Hz** con pclk 158,558 + línea 679 px | `:589-615` vs `:1083-1096` | mismos registros, `dsi_convert_to_drm_mode` | **NUEVO** (§1f; coherente con N1, añade la dimensión fps) |
| D3 | **INTF /24 truncado: width 533, línea INTF 678 vs DSI 679** | `dpu_encoder_phys_vid.c:141` | ceil(1600·8/24)=534, `set_video_timing.c:51-56` | **NUEVO** (el /24 era conocido; el sesgo de 1 px no) |
| D4 | **HS_TIMER nunca escrito** | grep: 0 referencias (`dsi.xml:250-254` sin writer) | 0x4bb80 (=HS_TX_TO 48000, RES 4) fijo en set_video_timing | H-D conocido; **NUEVO** el "mainline jamás lo escribe" |
| D5 | **LP_TIMER_CTRL (LP_RX_TO/BTA_TO) nunca escrito** | grep: 0 referencias (`dsi.xml:246-249`) | (no visto en host_setup; sus reads de fábrica sí corren) | **NUEVO** — candidata nº2 del BTA-sordo |
| D6 | Error: re-arm incondicional + sw_reset solo CMD_MDP | `:1643-1651` | freno 16/250 ms + capas de recuperación (N3) | conocido (ledger #650) |
| D7 | sw_reset msleep(20)+CLK_CTRL 0x23F | `:36`, `:1174-1180` | pulso instantáneo, CLK_CTRL 0x01000A00 (N2) | conocido |
| D8 | ERR_INT_MASK0 0x13ff3fe0 vs multi-registro vendor | `:917` | `enable_error_interrupts` (A3 §5a) | conocido |
| D9 | REG compresión DSI 0x29c(+4=0x2a0): WC=800, EOL=1600%3=1 | `:1005-1008` | mismo mapa (0xb01…), EOL vendor sin resolver | **SEMI-NUEVO** (paridad confirmada, §1e) |
| D10 | INTF CONFIG2 bit12 DCE ON | `dpu_hw_intf.c:201-203` | idem | **SEMI** (era H-C; ahora verificado, §4) |
| D11 | VID_CFG0: BLLP/EOF en LP, sync-event, RGB888 | `:848-851` | bllp-LP + non_burst_sync_event del DT | paridad (conocido) |
| D12 | **Helper del toggle sigue vivo** (código muerto peligroso) | `:1214-1230` EXPORT_SYMBOL | no existe | **NUEVO** — retirar para evitar re-uso |
| D13 | **Siesta 2-4 ms "skip BLLP" desajustada** (0,91 µs real) | `:1290-1292` | n/a | **NUEVO [H]**, bajo |
| D14 | Sin SPLIT_LINK (bonded = misma programación 2 links) | dsi_manager (§2c) | tampoco o82 (RE-GAPS §1) | paridad (conocido) |
| D15 | Trigger de writes software-secuencial entre links | `:550-565` | igual de secuencial por ctrl | paridad |

---

## 7. DIFFS EXACTOS PARA EL ÚNICO FLASH (independientes entre sí; árbol L72)

### B2-A (MUST) — Freno anti-flood estilo vendor (16 eventos / 250 ms, no re-armar)

`drivers/gpu/drm/msm/dsi/dsi_host.c`. Qué arregla: acota CUALQUIER ráfaga de error (el flood
de clase L68-L71 y futuros underruns) a ≤16 worker-runs + 1 línea de log por 250 ms y por
link; el bucle IRQ→worker→re-arm deja de ser infinito. Riesgo: BAJO — los eventos >16 de una
ventana se pierden hasta que abra la siguiente (250 ms), y el re-arm queda pospuesto mientras
esté frenado; autorecuperable (ventana nueva cada 250 ms). No toca timing de vídeo.
Verificación post-boot: `dmesg | grep -c 'S4-DIAG'` acotado (~≤130/min por link en el peor
caso) y `devmem 0xae94008` / `0xae96008` (FIFO_STATUS crudo) para ver si la CONDICIÓN
persiste bajo el freno (el freno trata el síntoma; el FIFO crudo dice si la causa vive).
Independencia: sí (solo worker de error).

```diff
--- a/drivers/gpu/drm/msm/dsi/dsi_host.c
+++ b/drivers/gpu/drm/msm/dsi/dsi_host.c
@@ -6,6 +6,7 @@
 #include <linux/clk.h>
 #include <linux/uke-poke.h>
 #include <linux/delay.h>
+#include <linux/jiffies.h>
 #include <linux/dma-mapping.h>
@@ -150,6 +151,10 @@ struct msm_dsi_host {
 	u32 err_work_state;
 	struct work_struct err_work;
 	struct workqueue_struct *workqueue;
+	/* B2-A: freno anti-flood estilo vendor (16 eventos / 250 ms, A3 §5a). */
+	unsigned long err_win_start;
+	u32 err_win_count;
 
 	/* DSI 6G TX buffer*/
 	struct drm_gem_object *tx_gem_obj;
@@ -1635,18 +1640,36 @@ static void dsi_err_worker(struct work_struct *work)
 	struct msm_dsi_host *msm_host =
 		container_of(work, struct msm_dsi_host, err_work);
 	u32 status = msm_host->err_work_state;
+	bool braked;
+
+	/* B2-A (15-oct): el vendor cuenta eventos con ventana de 250 ms
+	 * (dsi_ctrl_isr, umbral 0x10) y al superarlos DEJA de re-armar la IRQ
+	 * de error. Nuestro handler re-arma incondicionalmente (:1650) y con
+	 * una condicion latcheada (toggle L68 -> FIFO 0xdddd1011) eso es un
+	 * bucle de nivel infinito: 143k lineas/20 s (L71). Ventana nueva cada
+	 * 250 ms re-habilita la deteccion (autorecuperable). */
+	if (time_after(jiffies,
+		       msm_host->err_win_start + msecs_to_jiffies(250))) {
+		msm_host->err_win_start = jiffies;
+		msm_host->err_win_count = 0;
+	}
+	braked = ++msm_host->err_win_count > 16;
+	if (braked)
+		pr_err_ratelimited("S4-DIAG: id=%d flood frenado (%u eventos/250ms), IRQ error NO re-armada\n",
+				   msm_host->id, msm_host->err_win_count);
 
 	/* S4-DIAG (arranque): atribuir el rafaga a su link en dual-DSI. */
 	pr_err_ratelimited("%s: id=%d status=%x\n", __func__, msm_host->id, status);
-	if (status & DSI_ERR_STATE_MDP_FIFO_UNDERFLOW)
+	if (!braked && (status & DSI_ERR_STATE_MDP_FIFO_UNDERFLOW))
 		dsi_sw_reset(msm_host);
 
 	/* It is safe to clear here because error irq is disabled. */
 	msm_host->err_work_state = 0;
 
-	/* enable dsi error interrupt */
-	dsi_intr_ctrl(msm_host, DSI_IRQ_MASK_ERROR, 1);
+	/* enable dsi error interrupt (B2-A: salvo freno activo) */
+	if (!braked)
+		dsi_intr_ctrl(msm_host, DSI_IRQ_MASK_ERROR, 1);
 }
```
Limitación documentada: si la condición desaparece con la IRQ enmascarada, el re-arm llega
con el siguiente evento o en el próximo ciclo enable/modeset (aceptable en este estado de
plataforma; el vendor tampoco re-arma tras flood — delega en re-prepare, que no tenemos).

### B2-B (MUST) — Ratelimit de los prints S4 que quedan sin freno

`dsi_host.c`. Qué arregla: las clases TIMEOUT y video-done-timeout pueden saturar el log por
sí solas (cada `dsi_error` las recorre). Riesgo: CERO. Verificación: tamaño de journal.
Independencia: sí.

```diff
--- a/drivers/gpu/drm/msm/dsi/dsi_host.c
+++ b/drivers/gpu/drm/msm/dsi/dsi_host.c
@@ -1259,12 +1259,13 @@ static void dsi_wait4video_done(struct msm_dsi_host *msm_host)
 	if (ret == 0) {
 		/* S4-DIAG (arranque): distingue "motor parado" de "motor colgado". */
 		u32 st0 = dsi_read(msm_host, REG_DSI_STATUS0);
 		u32 fifo = dsi_read(msm_host, REG_DSI_FIFO_STATUS);
-		DRM_DEV_ERROR(dev,
+		DRM_DEV_ERROR_RATELIMITED(dev,
 			"S4-DIAG: wait for video done timed out, id=%d STATUS0=%08x FIFO=%08x (BUSY=%d)\n",
 			msm_host->id, st0, fifo,
 			!!(st0 & DSI_STATUS0_VIDEO_MODE_ENGINE_BUSY));
 	}
@@ -1676,8 +1677,8 @@ static void dsi_timeout_status(struct msm_dsi_host *msm_host)
 		dsi_write(msm_host, REG_DSI_TIMEOUT_STATUS, status);
 		msm_host->err_work_state |= DSI_ERR_STATE_TIMEOUT;
 		/* S4-DIAG (arranque): el agregado status=5 no dice QUE timeout.
 		 * B2-B: ratelimit (misma leccion del flood L68-L71). */
-		pr_err("S4-DIAG: %s: id=%d TIMEOUT_STATUS=%08x\n",
+		pr_err_ratelimited("S4-DIAG: %s: id=%d TIMEOUT_STATUS=%08x\n",
 			__func__, msm_host->id, status);
 	}
```

### B2-C (RECOMENDADO) — Ceil en el INTF /24: alinea línea INTF (679) con línea DSI (679) y con el vendor (534)

`drivers/gpu/drm/msm/disp/dpu1/dpu_encoder_phys_vid.c:139-143`. Qué arregla: el sesgo de
1 px/línea (hsync_period 678→679) y da paridad EXACTA con la fórmula vendor ceil
(`set_video_timing.c:51-56`). Riesgo: BAJO pero no cero (toca timing vivo del INTF; el mundo
L71 ya funciona con 533 — esto es pulir, no desatascar). Verificación: underruns siguen 1/1,
`TOTAL` del INTF vía dmesg DPU sin cambios de vsync, readback ACTIVE_H intacto.
Independencia: sí.

```diff
--- a/drivers/gpu/drm/msm/disp/dpu1/dpu_encoder_phys_vid.c
+++ b/drivers/gpu/drm/msm/disp/dpu1/dpu_encoder_phys_vid.c
@@ -138,9 +138,11 @@
-		uke_poke("L71-intf24");
-		timing->width = timing->width * drm_dsc_get_bpp_int(dsc) / 24;
+		uke_poke("L72-intf24ceil");
+		/* B2-C: ceil como el vendor (set_video_timing: H'=ceil(hact*8/24)
+		 * = 534); el truncado dejaba hsync_period INTF=678 vs DSI TOTAL=679
+		 * (1 px/linea de sesgo). */
+		timing->width = DIV_ROUND_UP(timing->width * drm_dsc_get_bpp_int(dsc), 24);
 		timing->xres = timing->width;
 		timing->dce_bytes_per_line = msm_dsc_get_bytes_per_line(dsc);
```

### B2-D (OPCIÓN, recomiendo NO incluir en este flash) — HS_TIMER del vendor

`dsi_host.c`, insertar en `dsi_ctrl_enable` tras el write de REG_DSI_CLKOUT_TIMING_CTRL
(`:903`). Qué arregla (teórico): deadline de HS del motor de vídeo (H-D de A3 §9: sin él,
con margen fino y jitter de arbitraje, el drenaje llega tarde). En nuestro mundo actual hay
59 % de holgura (§1f), así que el beneficio esperado es bajo. Riesgo: MEDIO — registro sin
validar en este HW desde mainline; un HS_TX_TO mal puesto crearía una NUEVA fuente de
errores (que el freno B2-A absorbería). Decisión: gate por evidencia del boot L72 (si
FIFO_STATUS crudo muestra errores con B2-A puesto, esto es el siguiente candidato).

```diff
--- a/drivers/gpu/drm/msm/dsi/dsi_host.c
+++ b/drivers/gpu/drm/msm/dsi/dsi_host.c
@@ -901,6 +901,13 @@ static void dsi_ctrl_enable(struct msm_dsi_host *msm_host,
 	data = DSI_CLKOUT_TIMING_CTRL_T_CLK_POST(phy_shared_timings->clk_post) |
 		DSI_CLKOUT_TIMING_CTRL_T_CLK_PRE(phy_shared_timings->clk_pre);
 	dsi_write(msm_host, REG_DSI_CLKOUT_TIMING_CTRL, data);
+
+	/* B2-D (opcional): el vendor escribe HS_TIMER (+0xbc vendor = 0x4bb80
+	 * = HS_TX_TO(48000) | TIMER_RESOLUTION(4)) dentro de set_video_timing;
+	 * mainline nunca escribe REG_DSI_HS_TIMER_CTRL (grep). Solo si el boot
+	 * L72 muestra FIFO viva con B2-A activo. */
+	dsi_write(msm_host, REG_DSI_HS_TIMER_CTRL, 0x4bb80);
```

### B2-E (LIMPIEZA, sin riesgo) — Retirar el helper del toggle (código muerto)

`dsi_host.c:1214-1230` (función + EXPORT_SYMBOL) y el `extern` del panel
(`panel-xiaomi-o82-dualdsi.c:41`). Qué arregla: elimina la única vía para re-crear el flood
L68. Riesgo: CERO (ningún llamador queda). Verificación: compila.

---

## 8. VEREDICTO: por qué nuestro DSI entra en flood perpetuo y cómo se cierra

**Causa (cadena completa):** el toggle L68 (`CTRL.VID_MODE_EN` off→on en caliente,
`:1214-1230`) corta el motor de vídeo SIN resincronización — no hay FLUSH, no hay realine de
línea/frame, y el re-arranque hereda FIFOs de carril y de vídeo latchadas en estado
inconsistente (huella 0xdddd1011: VIDEO_MDP OVERFLOW + los 4 carriles HS EMPTY+OVERFLOW a la
vez). A partir de ahí, el bucle es estructuralmente infinito en mainline: `dsi_error`
(`:1743`) limpia el sticky, `dsi_err_worker` (`:1635-1651`) no encuentra bit7 de CMD_MDP
(así que ni sw_reset) y **re-arma la IRQ de nivel incondicionalmente** (`:1650`) →
143k líneas/20 s en dos links. El recovery que podría romper el bucle (`dsi_sw_reset`,
`:1159-1187`) es de 20 ms con ENABLE caído y con el INTF alimentando se re-dispara a sí
mismo — el vendor lo prohíbe por diseño (freno 16/250 ms + capas, N3). El flood es
independiente del mundo de timing (L68-L71 lo demostraron) porque la causa es el LATCH, no
el timing; los problemas de timing de L69-L71 solo cambiaron el contenido de los errores.

**Cierre seguro del ÚNICO flash (L72+):**
1. **Ya en el árbol (correcto):** toggle retirado (`panel-xiaomi-o82-dualdsi.c:686-692`) —
   vuelve al estado L67, que fue LIMPIO con el mismo bloque de lecturas video-ON. El ratelimit
   del print FIFO (`:1710`) es la mitigación secundaria.
2. **Añadir B2-A (freno)** para que NINGÚN flood futuro pueda volver a tumbar el root ni a
   uke-adsp — es la paridad mínima con el vendor y hace el boot seguro aunque el FIFO vuelva
   a latcharse por otra causa.
3. **Añadir B2-B** (ratelimits residuales) y **B2-C** (ceil 534/679, paridad exacta vendor).
4. **Retirar B2-E** (helper muerto). **Diferir B2-D** (HS_TIMER) a un flash posterior
   gateado por `devmem 0xae94008/0xae96008` crudo del boot L72.
5. **El flood NO es el bloqueo del contenido**: con L71 los 3 registros del vendor están
   clavados, el feed es coherente (underruns 1/1) y aun así no hay imagen — el residuo del
   negro vive FUERA de este chunk (PHY TIMING_CTRL RX / handoff VBIF-SMMU-ICC de A2 §3.7 /
   PPS-timing vendor, por ese orden según A1 §4 y A2 §6.5). El gate del flash debe medir
   FIFO_STATUS crudo, no solo contar líneas (A1 §6.2).
6. **Dato nuevo para el siguiente ciclo (no accionar ahora):** el modo "120 Hz" corre
   efectivamente a ~101 Hz (§1f). Si el panel exigiera 120 reales, el camino vendor es
   bitclk/pclk independientes (N1), no otra vuelta por dsi_host.
