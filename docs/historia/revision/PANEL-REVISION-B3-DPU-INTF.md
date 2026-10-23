# PANEL-REVISION B3 — Lado MDP/DPU: feeding INTF, underrun, ICC, handoff y DSC (2026-10-15)

> Agente B3 de la revisión por fases. SOLO lectura de árbol + DT; cero dispositivo, cero build.
> Fuentes: árbol vivo `build/kernel-pokes/k52-L16-tree` (estado L72), DTBO vivo
> `~/gpu-work/ramaa/s21/dtbo-gpu/fase4-display.dts` (s288 en slot a), vanilla de
> referencia `/tmp/palawan-linux`, material senemos `/tmp/uke-mainline-linux`, y A1/A2/A3.
> **NUEVO** = no escrito en ningún informe previo; **SEMI** = dato conocido + algo nuevo al lado.
> [M] = medido/leído en fichero:línea; [H] = hipótesis con discriminador propuesto.

---

## 1. Aritmética completa de feeding del INTF en L71/L72 (constantes con fichero:línea)

Modo DRM (full panel, `panel-xiaomi-o82-dualdsi.c:721-733`): 3200×2136@120, hfp 226, hs 32,
hbp 32 → **htotal 3490**; vfp 26, vsync 2, vbp 146 → **vtotal 2310**; clock = 3490·2310·120/1000
= **967.428 kHz** (= grupo OEM 0 de 120 Hz del A2, `o82-data.h:928-935`, byte-idéntico).
DSC (`:761-781`): 10 bpc → 8 bpp (`bits_per_pixel = 8<<4`), slices **800×24, slice_count 2
por link**, block-pred on, RGB, DSC 1.1 pre-SCR.

**Cadena por link (dual-DSI bonded):**

| Paso | Fórmula | Valor | Dónde |
|---|---|---|---|
| Split por INTF | hdisplay/htotal `>>=1` (ENC_ROLE≠SOLO) | 1600 / 1745 (hfp 113, hs 16, hbp 16) | `dpu_encoder_phys_vid.c:287-300`, porches `:81-86` |
| **pclk** (mundo 30) | `new_hdisplay = ceil(1600·8/30) = 427`; ×2; `new_htotal = 3490−3200+854 = 1144`; `967.428.000·1144/3490 = 317.116.800`; bonded `/2` | **158.558.400 Hz** | `dsi_host.c:589-615` (`/30` en `:606-607`), `:617-637` (`/2` en `:633-634`) |
| pclk vendor | stock debugfs PIXEL_CLK = **158.558.666** = C·4/30 = 1.189.190.000·4/30 | Δ **267 Hz** | docs/historia/revision/INFORME-MODO-OPP-DSC-20261013.md:75,83 |
| **byte clock** (L70) | `mult_frac(pclk, bpc·3=30, 8·4)` | **148.648.500 Hz** | `dsi_host.c:660-680` |
| byte vendor | bitclk/8 = 148.648.750 | Δ 250 Hz | INFORME-MODO-OPP-DSC:75; A1 §2 |
| **DSI hdisplay** | `ceil(bytes_per_line·8 / bits_per_pclk)`; bytes/line = `slice_count·slice_chunk = 2·800 = 1600` (`msm_dsc_helper.h:22-25`); bits/pclk = **24** (widebus OFF, L71) | **534** | `dsi_host.c:1084-1093`; widebus OFF forzado `:814-826` |
| **DSI h_total** | `1745−1600+534 = 679` → TOTAL `0x090502a6`, ACTIVE_H `0x02360020` (ha_start 32 = (3490−3426)/2, ha_end 566) | = **vendor EXACTO** (medido L71, A1 §2) | `dsi_host.c:1037-1111`, readback `:1123-1128` |
| **INTF width** (L71) | `timing->width·8/24` con división ENTERA (floor): `1600·8/24 = 533` (533·24 = 12792, resto 8) | **533** ⚠️ | `dpu_encoder_phys_vid.c:133-144` |
| **INTF hsync_period** | `hbp+hs+width+hfp = 16+16+533+113` | **678** ⚠️ vs DSI **679** | `dpu_hw_intf.c:128-131`, `:167` |
| INTF ventana de DATOS | `data_width = DIV_ROUND_UP(dce_bytes_per_line,3) = ceil(1600/3) = 534`; `display_data_hctl = (565<<16)\|32`; DATA_HCTL_EN OFF (compresión 1px/clk); `INTF_CFG2_DCE_DATA_COMPRESS` ON (major 10 ≥ 7) | 534 ticks ✓ cubre los bytes | `dpu_hw_intf.c:175-206`, `:246-253`, `:203-205` |
| ACTIVE_HCTL | width==xres → sin ventana activa explícita (`active_hctl=0`, ACTIVE_H_EN off) | — | `dpu_hw_intf.c:141-162` |
| PROG_FETCH | vbp+vsw = 148 ≥ worst-case 24 → **no fetch programado** | — | `dpu_encoder_phys_vid.c:179-216`; catálogo `catalog/dpu_10_1_palawan.h:287,296` |

**Deducción central [NUEVO-B3-1]:** con L71 el periodo de línea del INTF (678 pclk) **no
coincide** con el del DSI (679 pclk) ni con el vendor (679, A3 §4 "El DPU programa el INTF con
htotal=679"). La causa es floor-vs-ceil: el vendor calcula H' = `(24 + hact·8 − 1)/24` = **ceil**
(A3 §2a, `set_video_timing` 002e7b3c) y mainline usa división entera con el TODO explícito
"handle fractional part". upstream vanilla tiene el MISMO off-by-one en el mundo 30: INTF
`1600·8/30 = 426` (floor) → periodo **571** vs DSI widebus **572** (`/tmp/palawan-linux/.../
dpu_encoder_phys_vid.c:130-141`; `dsi_host.c:1093` usa ceil) — por eso el comentario TODO existe.
El DSI es tolerante a 1 tick/linea (L67: 0 underruns con 571/572), pero es un defecto real y el
vendor no lo tiene (679/679).

### La cuestión abierta del 101 Hz [NUEVO-B3-2, honesta]

Con los valores **medidos** del vendor (pclk 158.558 MHz stock, h_total DSI 679, vtotal 2310),
el refresco implícito es 158.558.666/(679·2310) = **101,1 Hz**, no 120. La aritmética fill/drain
del A3 §2a ("fill 564,8 MB/s") solo cierra con tick de 5,314 ns (= 188,19 MHz), lo que es
inconsistente con su propio pclk declarado (158,558 → fill real = 3 B·158,558 MHz =
475,7 MB/s; drain 594,6 MB/s → margen real 25 %, no 5,3 %). Como el PIXEL_CLK stock está
medido en debugfs (INFORME-MODO-OPP-DSC:75), la lectura más económica es: **el "120 Hz" del
grupo OEM 0 es la etiqueta del DT; el reloj real con H'=534/htotal 679 da ~101 Hz y al DDIC se
lo valida así**. No cambia nada accionable (clonar vendor = clonar sus 101 Hz), pero
discrimina: si el vendor real va a 120 Hz, entonces el DSI cuenta h_total en una unidad distinta
del pclk (p. ej. dominio comprimido interno) y habría que descubrir cuál (candidato: HS_TIMER
0x4bb80 y/o anchura de pixel-interface en compresión). Test: leer INTF FRAME_COUNT vs tiempo
en stock, o fotodiodo. No bloquea L72.

---

## 2. `dsi_adjust_pclk_for_compression`: ¿/24 o /30? → **/30, y hay prueba de vendor**

A1 §6.6 preguntaba si el pclk debería seguir en /(bpc·3)=30. Respuesta: **SÍ, /30 es correcto y
está confirmado por el vendor**: el PIXEL_CLK medido en debugfs stock (158.558.666) es
exactamente `bitclk × lanes / (bpc·3)` = C·4/30 (INFORME-MODO-OPP-DSC:83, "✅ exacto"). Es decir,
el vendor deriva el pclk en el mundo de profundidad DSC de entrada (30 bit/pixel-time), NO en el
contenedor de 24. El /24 solo rige la anchura del contenedor INTF→DSI y el ACTIVE_H del host.
Contraste: un /24 en el pclk daría `new_htotal = 3490−3200+2·534 = 1358` → pclk
967.428.000·1358/3490/2 = **188.219.600 Hz**, que contradice el debugfs stock y rompería el byte
clock derivado (188,2·30/32 = 176,4 MHz ≠ 148,6 vendor). El estado L71/L72 (pclk /30 + INTF /24 +
byte ×30 + widebus OFF) reproduce pclk, byte y registros DSI del vendor; solo falta el ceil del
INTF (§1).

---

## 3. Underrun: ¿inanición (ICC) o desajuste de feeding? → **desajuste de feeding; ICC NO es la causa demostrada**

La matriz de boots discrimina limpiamente (todas las cifras de A1 §1-§3):

| Boot | Mundo INTF (línea) | Mundo DSI (línea) | Δ ticks/línea | Underruns | Toggle L68 |
|---|---|---|---|---|---|
| L67 | /30 → 571 | /30 widebus → 572 | 1 | **0** | NO |
| L68 | /30 → 571 | /30 widebus → 572 | 1 | 19 | SÍ |
| L69 | /24 → 678 | /30 widebus → 572 | **106** | **1929 (1:1 vsync)** | SÍ |
| L71 | /24 → 678 | /24 → 679 | 1 | 1/1 (+flood) | SÍ |

1. **El mismatch gigante de L69 (106 ticks/línea) explica el 1:1 con vsync**: cada línea del DSI
   acaba 106 ticks antes que la del INTF; la ventana de datos se desalinea por completo →
   underrun en cada frame. Es feeding, no ancho de banda.
2. **El control L67 (mismo ICC, mismo handoff, mundo 30 coherente) = 0 underruns** con modetest
   commit funcionando (L64). Si hubiera inanición ICC, L67 también underrunearía.
3. **L71 (mundo 24 casi completo) queda en 1/frame + flood**: el 1/frame es coherente con el
   residuo de 1 tick (678 vs 679, acumulativo) MÁS la contaminación del toggle (A1 §3: el flood
   aparece en L68-L71 con CUALQUIER mundo; L72 lo retira).
4. ICC por debajo: el voto del DPU en commit fullscreen es 4,25 GB/s ≥ necesidad real 3,28 GB/s
   (§4). Y en L67, con el voto idéntico, no hubo un solo underrun.

**Veredicto**: los underruns son **desajuste de mundo de feeding** (línea INTF ≠ línea DSI, con
el caso extremo L69), agravados por el flood del toggle. La inanición ICC no está demostrada por
ninguna medición; el gap ICC existe estructuralmente (§4) pero es segunda línea.

---

## 4. ICC del DT: qué pide nuestro árbol vs el vendor

- **Nuestro DTBO vivo** (`fase4-display.dts:196-201`): `interconnects = <&mc_virt 3 &mc_virt 512>`
  ("mdp0-mem") — **workaround que salta mmss_noc**: el path es solo LLCC→EBI dentro de mc_virt
  (BCM acv/mc0, `drivers/interconnect/qcom/palawan.c:1710-1724`). El comentario del overlay
  ("el port icc no cubre cliffs-mmss_noc") está **OBSOLETO [NUEVO-B3-3]**: nuestro kernel sí
  define `palawan_mmss_noc` con MASTER_MDP (2 canales, buswidth 32, qosbox puertos
  **0xad000/0xae000** — idéntico al `cliffs-display-icc.h` del A2 §3.7; `palawan.c:674-691`,
  desc `:1749-1755`), y `palawan.dtsi:2171-2176` tiene el nodo `mmss_noc`.
- **Votos que ocurren**: mdss-enable fija `MIN_IB_BW = 400 MB` (`msm_mdss.c:26,244-248`); el DPU
  vota por CRTC `_dpu_core_perf_calc_bw` = Σ plane_fetch_bw × `bw_inefficiency_factor` 120
  (`dpu_core_perf.c:116-141,220-248`; `dpu_plane.c:140-143`: src_w·vtotal·fps·bpp). Fullscreen
  XRGB8888@120: 3200·2310·120·4 B = **3,545 GB/s** ×1,2 = **4,253 GB/s** (ab+ib en mdp0-mem).
  Necesidad real de scanout: 3200·2136·4·120 = **3,281 GB/s**. El voto alcanza — **en el segmento
  que se vota**. Los segmentos qnm_mdp→qns_mem_noc_hf→qnm_mnoc_hf→LLCC quedan **sin voto**.
- **Vendor senemos**: ICC fija **8 GB/s** hasta completar su handoff
  (`patches/display/7.2.10/0001:272-302`, `Bps_to_icc(8000000000ULL)`), y el vendor Android vota
  su propia cadena (no medida aquí). El 8 GB/s de senemos es un suelo de seguridad durante el
  scanout del firmware, no un mínimo de scanout.
- **Riesgo honesto**: con el path mc_virt-only, la QoS del fabric NOC entre MDP y LLCC depende del
  default de RPMh; no hay medición que lo acuse, pero tampoco vota. Diferencia estructural vs
  vendor y vs la intención upstream (`palawan.dtsi:3370-3375`).

---

## 5. Handoff del splash: nuestro inherit + FIX-A1b vs vendor (VBIF/CORE_BCR/SMR/ICC 8 GB/s)

| Aspecto | Nuestro inherit (uke_panel_inherit=1) | Vendor senemos (uke-mdss-handoff.c) | Vendor Android (A3 §6) |
|---|---|---|---|
| Premisa | panel VINO ENCENDIDO del ABL; scanout heredado se PRESERVA | firmware scanout hay que DRENARLO antes del nativo | splash viva ⇒ rama B: no tocar nada (rails/reset/PPS/engine skip) |
| Reset MDSS | saltado (`msm_mdss.c:315-333`, L22b) | saltado hasta handoff | sin reset |
| VBIF | **memtypes SALTADOS** (`dpu_kms.c:1289-1297,1505-1511`) | halt XINs (0x200) + ack (0x204) + deassert | con splash no reprograma VBIF (GAPLIST G1) |
| CORE_BCR | **nunca se toca** | assert/deassert 0x8000 bit0 | — |
| SMR/S2CR 0x1c00/0x2 | **FIX-A1b**: reclaim quirúrgico por force-idx, opt-in `uke_disp_reclaim` (`arm-smmu.c:439-470,1595-1640,1888-1900`) | retira SMRs unsecure del SMMU de boot conservando CBs | el ABL deja el mapa; kernel vendor lo hereda |
| Clk bulk | **saltados** en runtime_resume (`dpu_kms.c:1483-1490`: "clocks ABL") | habilita | habilita (cold) / hereda (splash) |
| ICC durante la ventana | 400 MB (`msm_mdss.c:26`) | **8 GB/s** | vota su cadena |
| Panel | prepare/enable skip rails/reset/init (`panel-xiaomi-o82-dualdsi.c:368-374`); PPS post-0x29 en .enable (L63, `:617-631`) | PPS **no enviada nunca** (gap, A2 §3.1) | PPS 0x0A tras 0x29 y antes del engine (A3 §1/§3) |

**Qué hace nuestro arranque que el vendor no**: (a) confía en que los clocks del ABL siguen ON y
no los habilita nunca por su cuenta — si cualquier PM runtime posterior los apaga, no hay
recuperación; (b) deja el VBIF y el SMMU exactamente como el ABL (FIX-A1b es opt-in por cmdline);
(c) no sube el suelo ICC durante el arranque. **Qué falta vs senemos**: el drenaje
(VBIF-halt + CORE_BCR + retiro SMR) que senemos considera imprescindible para tomar el dominio;
nuestro planteamiento es el opuesto deliberado (L22b #612: el reset mataba el scanout). Dado que
A3 §6 demuestra que el Android vendor con splash viva TAMBIÉN no resetea nada, y que el dueño ve
"negro con luz" desde siempre (¿el splash ABL ya está muerto/negro?), la hipótesis de que el
handoff senemos explique nuestro flood queda **debilitada para el flood** (L67 limpio sin drenaje)
pero **abierta para el "sin contenido"** si el scanout heredado está muerto y el DPU nunca toma
el control completo de clocks. Nota: si el splash ABL está muerto, `uke_panel_inherit=1` está
protegiendo un cadáver y saltando clk_bulk que quizá convenga habilitar.

---

## 6. DSC del DPU ↔ PPS ↔ INTF: coherencia (PASS con matices)

- **Bases**: catálogo `catalog/dpu_10_1_palawan.h:222-239` — DSC_0 (`dce_0_0`) y DSC_1
  (`dce_0_1`) **comparten base 0x80000** (sblk enc 0x100/0x200, ctl 0xF00/0xF80,
  `dpu_hw_catalog.c:447-455`), DSC_2 @0x81000 sin usar; `DPU_DSC_NATIVE_42x_EN`. **Idéntico** al
  `dpu_10_1_sm7675.h` del A2 (diff real: solo comentarios y max_linewidth 8192 vs 5120; las
  secciones DSC/INTF byte-iguales — INTF_1 @0x35000, INTF_2 @0x36000, underrun TOP0 bits 26/28).
  `dpu_hw_dsc_1_2.c:388` hace `blk_addr = addr + cfg->base` y escribe siempre vía `sblk` →
  **sin colisión** entre DSC_0/DSC_1. ✓
- **Topología**: `num_dsc = 2` con 2 INTF (`dpu_encoder.c:657-694`); RM: num_dsc==num_intf →
  alloc no-merge, PP_0→DSC_0, PP_1→DSC_1 (`dpu_rm.c:615-640`); `dpu_encoder_prep_dsc`
  (`dpu_encoder.c:2021-2065`): SPLIT_PANEL (2 DSC), **sin MULTIPLEX** (2/2), VIDEO on;
  pic_width 3200 → 1600 por encoder; `initial_lines` = ceil((92·3 + 256 + 47 + 92·3)/800) = **2**;
  max_addr NATIVE_42x → 599 (`dpu_hw_dsc_1_2.c:61-69`). Los RC params los recalcula el host con
  `drm_dsc_setup_rc_params(DRM_DSC_1_1_PRE_SCR)` y `line_buf_depth = bpc+1 = 11`
  (`dsi_host.c:1948-1986`). El host y el DPU comparten EL MISMO `drm_dsc_config`
  (`dsi_host.c:1800` `msm_host->dsc = dsi->dsc`): coherencia estructural. ✓
- **PPS**: el panel envía dims **1600×2136 por link** con slices 2×800 (L62/L63,
  `panel-xiaomi-o82-dualdsi.c:423-453,617-631`) = lo que cada encoder DSC produce por link;
  A3 §3 confirma que la PPS vendor es funcionalmente idéntica. ✓
- **INTF**: `compression_en = dpu_encoder_is_dsc_enabled()` (`dpu_encoder_phys_vid.c:100`) →
  INTF_CFG2_DCE_DATA_COMPRESS (bit 12 de 0x060) = paridad con vendor `sde_hw_intf_enable_compressed_input`
  (A3 §4). ✓. Widebus: con `msm_dsi_host_is_wide_bus_enabled()=false` NADA programa
  DSI_VID_CFG0_DATABUS_WIDEN (`dsi_host.c:853-855`) ni INTF_CFG2_DATABUS_WIDEN
  (`dpu_hw_intf.c:170-171`; `dpu_encoder.c:276-292` deriva del mismo booleano). **Cierra la
  pregunta abierta 4 de A1.** El WC (`VIDEO_COMPRESSION_MODE_CTRL`) sigue presente vía
  `dsi_update_dsc_timing` (`dsi_host.c:1006`).
- Matiz menor: el /24 lo aplica SOLO `dpu_encoder_phys_vid.c` (divisor literal 24), mientras
  vanilla divide por `(bpc·3)` — ver diff F1.

---

## 7. Modos: 572×2310@120/158,56 vs 967 MHz del A2 — son EL MISMO modo

No hay dos modos: **967.428 kHz** es el clock del modo DRM full-panel (3200 activos, sin
comprimir); **158,558 MHz** es su pclk POR LINK después de comprimir con DSC (§1) y
**572×2310** es el htotal-per-link del mundo 30 (16+16+427+113). Nuestro modo registrado
(`panel-xiaomi-o82-dualdsi.c:721-733`: clock 967428, htotal 3490 = 3200+226+32+32, vtotal 2310 =
2136+26+146+2) es **byte-idéntico al grupo OEM 0 de 120 Hz** del A2 (`o82-data.h:928-935`) y el
único expuesto (num_modes=1, correcto: solo escribimos regs de 120 Hz). El modo 60 Hz OEM
(vtotal 4620, vfp×2) del mismo grupo y el grupo 1 de 144 Hz (1.097.712 kHz) quedan fuera por
diseño. **El nuestro es válido.** Los 967 MHz no son "otro panel": es el ancho de banda sin
comprimir del mismo panel.

---

## 8. Tabla de discrepancias vs vendor / catálogo OEM (NUEVO vs conocido)

| # | Discrepancia | Nuestro estado (fichero:línea) | Vendor/catálogo | Estado |
|---|---|---|---|---|
| D1 | INTF hsync_period **678 vs 679** (floor vs ceil en el divisor DSC) | `dpu_encoder_phys_vid.c:141` | ceil → 534+145=679 (A3 §2a/§4) | **NUEVO-B3-1** |
| D2 | upstream tiene el mismo off-by-one en /30 (571 vs 572) | vanilla `dpu_encoder_phys_vid.c:130-141` + TODO | — | NUEVO-B3-1 (contexto) |
| D3 | Refresh implícita ~101 Hz con registros+pclk vendor | aritmética §1 | etiqueta DT "120" | NUEVO-B3-2 [H] |
| D4 | fill/drain real = 475,7 vs 594,6 MB/s (25 %), no 5,3 % | aritmética §1 | A3 §2a | NUEVO-B3-2 (corrige A3) |
| D5 | DTBO ICC salta mmss_noc (path mc_virt-only) y el comentario que lo justifica está obsoleto | `fase4-display.dts:196-201` vs `palawan.c:674-691,1749-1755` | senemos 8 GB/s por su cliffs-mmss_noc | **NUEVO-B3-3** |
| D6 | inherit confía clocks ABL sin habilitar clk_bulk | `dpu_kms.c:1483-1490` | vendor/senemos habilitan | SEMI (ya citado en L22b; el riesgo de no-recuperación es nuevo) |
| D7 | DATABUS_WIDEN no queda programado en ningún sitio con L71 | `dsi_host.c:853-855`, `dpu_hw_intf.c:170-171` | vendor sin widebus | **cierra A1 §6.4** |
| D8 | Bases DSC/INTF correctas e idénticas al catálogo A2 | `dpu_10_1_palawan.h:222-239,273-309` | `dpu_10_1_sm7675.h` | confirmación (A2) |
| D9 | pclk /30 correcto (PIXEL_CLK stock = C·4/30) | `dsi_host.c:606-607` | debugfs stock | **cierra A1 §6.6** |
| D10 | dsi_sw_reset mainline pierde 20 ms/evento, sin freno 16/250 ms ni lane-reset | `dsi_host.c:1159-1181,1640-1652` | A3 §5/§8-N2/N3 | ya conocido (A3); sin cambios |
| D11 | block-pred: ours true; A3 anota vendor "vacío" pero también "PPS byte-equivalente" | `panel-xiaomi-o82-dualdsi.c:779` + DSC_MAIN_CONF bit20 (`dpu_hw_dsc_1_2.c:146-147`) | ambiguo | menor, verificar byte PPS[3] si todo lo demás cae |

---

## 9. Diffs EXACTOS de fixes candidatos

### F1 — Ceil en el divisor INTF DSC (1 línea; cierra D1)

```diff
--- a/drivers/gpu/drm/msm/disp/dpu1/dpu_encoder_phys_vid.c
+++ b/drivers/gpu/drm/msm/disp/dpu1/dpu_encoder_phys_vid.c
@@ -138,7 +138,8 @@
 		/*
 		 * TODO: replace drm_dsc_get_bpp_int with logic to handle
 		 * fractional part if there is fraction
 		 */
 		uke_poke("L71-intf24");
-		timing->width = timing->width * drm_dsc_get_bpp_int(dsc) / 24;
+		/* B3 (15-oct): ceil como el vendor (set_video_timing 002e7b3c:
+		 * (24 + hact*8 - 1)/24) y como el DSI host (dsi_host.c:1093).
+		 * INTF hsync_period 679 = DSI h_total 679 = vendor. */
+		timing->width = DIV_ROUND_UP(timing->width * drm_dsc_get_bpp_int(dsc), 24);
 		timing->xres = timing->width;
 		timing->dce_bytes_per_line = msm_dsc_get_bytes_per_line(dsc);
```

- **Qué arregla**: alinea el periodo de línea del INTF (678→679) con el DSI y el vendor; elimina
  el drift de 1 tick/línea candidato del residuo 1 underrun/frame de L71.
- **Riesgo**: mínimo (533→534 ticks activos; `data_width` ya era 534; DATA_HCTL ya deshabilitado
  en 1px/clk). El DDIC ya se valida con la línea de 679 del vendor.
- **Verificación post-boot**: marcador `L71-intf24` presente; underrun counter INTF1/INTF2 = 0
  tras commit; `FIFO_STATUS` limpio (sin toggle ya en L72); opcional: readback INTF_HSYNC_CTL
  (period 679).
- **Independencia**: total de L72 (toggle/ratelimit) y de F2. Combinable en el mismo flash.

### F2 — ICC del DTBO: restaurar el path mmss_noc (1 fragmento; cierra D5)

```diff
--- a/fase4-display.dts (fragment@6, mdss_ml)
+++ b/fase4-display.dts
@@
-				/* Workaround icc (ver cabecera, punto 2): el mainline
-				 * correcto seria mmss_noc MASTER_MDP -> mc_virt EBI1
-				 * + gem_noc APPSS -> config_noc DISPLAY_CFG; el port
-				 * icc no cubre cliffs-mmss_noc y el voto DDR acaba en
-				 * mc_virt en cualquier caso. IDs = numeracion vendor.
-				 */
-				interconnects = <&mc_virt 3 &mc_virt 512>;
-				interconnect-names = "mdp0-mem";
+				/* B3 (15-oct): palawan.c YA define palawan_mmss_noc
+				 * (MASTER_MDP qnm_mdp 2ch/32, qosbox 0xad000/0xae000)
+				 * y palawan.dtsi trae el nodo mmss_noc; el workaround
+				 * mc_virt-only deja sin voto el fabric MDP->LLCC. */
+				interconnects = <&mmss_noc MASTER_MDP QCOM_ICC_TAG_ALWAYS
+						 &mc_virt SLAVE_EBI1 QCOM_ICC_TAG_ALWAYS>,
+						<&gem_noc MASTER_APPSS_PROC QCOM_ICC_TAG_ACTIVE_ONLY
+						 &config_noc SLAVE_DISPLAY_CFG QCOM_ICC_TAG_ACTIVE_ONLY>;
+				interconnect-names = "mdp0-mem",
+						     "cpu-cfg";
```
(requiere incluir `dt-bindings/interconnect/qcom,palawan-rpmh.h` y `qcom,rpmh-regulator.h`/
tags si no están; el overlay ya resuelve labels `&dispcc`/`&gcc`, así que `&mmss_noc` compila).
Regenerar DTBO y re-verificar su sha antes del flash (procedimiento s288).

- **Qué arregla**: no arregla nada medido; elimina el único gap estructural vs vendor/mainline en
  la ruta de datos (QoS del fabric MDP→LLCC votada; cpu-cfg para sync_state).
- **Riesgo**: bajo-medio. Toca DTBO (slot dtbo ya ocupado por s288; hay que regenerarlo). El
  primer `icc_set_bw` de mdss-enable (400 MB) ahora también compromete mmss_noc/gem_noc; si algún
  provider no bindeara, el probe de mdss fallaría visiblemente (fácil de ver en dmesg).
- **Verificación post-boot**: `/sys/kernel/debug/interconnect/interconnect_summary`:
  `qnm_mdp → qns_mem_noc_hf` con avg/peak ≈ 4,2 GB/s tras commit; sin iommu/fabric faults;
  underruns 0.
- **Independencia**: total de F1 y L72 (kernel untouched). Puede incluso ir sola en un flash de
  DTBO si el gate lo permite (ojo slots).

### F3 — pclk /24: **RECHAZADO** (documentado para no repetirlo)

Cambiar `dsi_adjust_pclk_for_compression` a /24 daría pclk 188,22 MHz, contradice el PIXEL_CLK
stock medido (158.558.666 = C·4/30) y desalinearía el byte clock derivado (176,4 ≠ 148,6).
Solo sería defendible si además se fijara el bitclk por DT (A3 §8-N1) — y aun así el vendor mide
158,558, así que NO.

### F4 — (opcional, NO para el flash único) suelo ICC estilo senemos

`msm_mdss.c`: votar `Bps_to_icc(8 GB/s)` hasta el primer commit si se quisiera replicar el suelo
de senemos. Riesgo bajo, beneficio no demostrado en nuestras mediciones (L67 limpio con 400 MB).
Aplazar hasta que F1+F2 fallen en aislar el "sin contenido".

---

## 10. Veredicto

**El underrun es desajuste de mundo de feeding, no inanición ICC.** El flood es el toggle L68
(cerrado por A1, retirado en L72); los underruns se explican por línea INTF ≠ línea DSI: 106
ticks en L69 (catastrófico, 1:1 vsync), 1 tick en L71 (residuo 1/frame). El ICC no tiene ninguna
medición en su contra y una a favor (L67 = 0 underruns con el mismo voto).

**Qué lo cierra en un solo flash (L72)**: L72 ya lleva el toggle fuera + ratelimit. Añadir **F1**
(ceil del divisor INTF → 679/679 = vendor) al mismo boot es 1 línea, independiente y verificable
(underruns=0 con commit + FIFO limpio). F2 (DTBO ICC) es correcto pero ortogonal: puede ir en el
mismo flash o en el siguiente; no es necesario para el diagnóstico del underrun. El pclk se
queda en /30 (F3 rechazado con prueba de debugfs stock). El "sin contenido" NO queda explicado
por nada de este lado con los datos actuales: con los registros del vendor clavados (L71) y el
feeding alineado (F1), el residuo apunta fuera del chunk DPU/INTF (DDIC/PHY-RX, Panel
heredado/estado del panel, o la cuestión B3-2 del refresco real), y las preguntas 1-3 de A1
siguen siendo las que gobiernan el siguiente paso.

---

## 11. Resumen (≤350 palabras)

He reconstruido la cadena completa encoder→INTF→DSC→DSI del árbol L72 con constantes
fichero:línea. El modo DRM (3200×2136@120, 967.428 kHz) es byte-idéntico al grupo OEM 0 del A2;
158,56 MHz es su pclk por link comprimido, no otro modo. La aritmética reproduce EXACTO los tres
registros del vendor (ACTIVE_H 0x02360020, TOTAL 0x090502a6, byte 148,6485) menos UN valor: el
INTF divide `1600·8/24 = 533` (floor) donde el vendor usa ceil (534), de modo que nuestro INTF
programa líneas de 678 pclk contra el DSI/vendor de 679 — el mismo defecto floor-vs-ceil que
upstream ya tiene en el mundo 30 (571 vs 572, con TODO en el código). Fix F1: DIV_ROUND_UP, 1
línea.

`dsi_adjust_pclk_for_compression` debe QUEDARSE en /30: el PIXEL_CLK stock del vendor medido en
debugfs (158.558.666) es exactamente bitclk·4/30; el /24 daría 188,22 MHz y rompería el byte
clock. Cierra la pregunta abierta 6 de A1. Con widebus OFF nada programa DATABUS_WIDEN (cierra
la 4 de A1).

Underruns: feeding, no inanición. La matriz L67/L69/L71 lo demuestra: mundo 30 coherente = 0
underruns con el mismo ICC; el mixto L69 (INTF 678 vs DSI 572, 106 ticks/línea) = 1929 en 1:1;
L71 (678 vs 679) = 1/frame + flood del toggle. El DPU vota 4,25 GB/s frente a 3,28 GB/s
necesarios. PERO el DTBO vive con un path ICC mc_virt-only cuyo justificante está obsoleto:
nuestro kernel sí define el mmss_noc del vendor (qnm_mdp 2ch/32, qosbox 0xad000/0xae000 idéntico
al cliffs del A2). Fix F2: restaurar `mmss_noc MASTER_MDP → mc_virt EBI1` + cpu-cfg en el DTBO.

Handoff: nuestro inherit (skip reset/clk_bulk/vbif + FIX-A1b opt-in) es filosofía
"preservar el scanout ABL", opuesta al drenaje senemos (VBIF-halt/CORE_BCR/SMR/8 GB/s) pero
próxima al vendor Android con splash viva (no toca nada). La hipótesis handoff explica mal el
flood (L67 limpio sin drenaje); queda abierta solo si el splash ABL ya está muerto.

DSC: bases correctas (DSC_0/1 comparten 0x80000 vía sblk, idéntico al catálogo A2), topología
split-panel sin multiplex, initial_lines 2, PPS 1600×2136 por link coherente con 2×800.

Veredicto único flash: L72 + F1. F2 va aparte u en el mismo boot si el gate lo admite.
