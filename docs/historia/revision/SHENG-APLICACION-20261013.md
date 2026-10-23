# SHENG-APLICACION (13-oct ~19:00) — qué tiene sheng que nosotros no, y dos parches

Subagente drivers DRM/KMS. Solo lectura + edicion de parches/informe. Tablet no tocada.
Arbol auditado: `/tmp/opencode/sm8550-mainline`, rama `sheng-7.2.6`, commit `42f3b40c`
(squash unico: sin historia, `git log -- drivers/gpu/drm/msm/dsi/` devuelve solo ese commit).
Arbol a parchear: `build/kernel-pokes/k52L33-tree` (7.2-rc2-palawan + pokes hasta L34).

## 0. Lo mas importante: sheng SI lleva parches locales al driver DSI — pero NINGUNO en el power-on

`diff` sheng vs k52L33 en `drivers/gpu/drm/msm/dsi/` demuestra parches locales reales:

1. **`registers/display/dsi.xml`: +2 registros** que upstream no tiene —
   `TIMING_FLUSH @0x1e0` y `TIMING_DB_MODE @0x1e4` (con comentario
   "Logical offsets after the 6G register shift; physical 0x1e4/0x1e8").
   En k52L33 esos offsets no existen (el L34 los definio a mano como `0x1e0` literal).
2. **`dsi_host.c`: `msm_dsi_host_seamless_mode_set()` + `msm_dsi_host_timing_db_update()`**
   (sheng ~2620-2673; ausentes en k52L33) + API en `dsi_manager.c`/`dsi.h`
   (`seamless_mode_valid/set/begin/pre_kickoff/post_kickoff/complete`).
   Uso exclusivo DFPS/cambio de modo en caliente. **El power-on (`timing→reset→ctrl_enable`)
   no los toca.**
3. **Batching de comandos** (`tx_batch_len`, `MIPI_DSI_MSG_BATCH_COMMAND`, sheng
   `dsi_cmd_dma_add locking host+offset`): k52L33 no lo tiene (su `dsi_cmd_dma_add`
   lleva otra firma). Solo afecta a DFPS/post_kickoff del panel.
4. **`dsc_slice_per_pkt`** (sheng lo soporta; panel sheng lo pone a 2): k52L33 lo
   ignora (`bytes_per_pkt = slice_chunk_size`, `pkt_per_line = slice_per_intf`).
5. **`clk_round_rate(byte_clk)` en `msm_dsi_host_get_clk_rates`** (sheng 681-690):
   k52L33 no redondea. Higiene de clocks, fuera de la ventana causal (el PLL engancha:
   `status=4` sin bit `0x20`).

**Veredicto: el power-on DSI de sheng es mainline puro.** Ningun parche local explica que
encienda; todos viven en DFPS/batching, inactivos durante el light-up inicial. Esto **cierra**
la pregunta 6 del encargo al reves de lo esperado: hay parches locales, pero son inocentes.

## 1. Resumen (lo que sheng tiene que nosotros no — en el camino del commit)

**Nada estructural.** Paso a paso, el power-on bonded-video+DSC de sheng (que enciende
3048x2032 dual-DSI) es **identico al nuestro**: `dsi_timing_setup` (sin FLUSH, sin HS_TIMER,
sin DB_MODE) → `dsi_sw_reset` (restaura CTRL integro, re-arma VID_MODE_EN) → `dsi_ctrl_enable`
→ `msm_dsi_host_enable` (VID_MODE_EN **antes** de los DCS) → cada DCS bloquea en
`dsi_wait4video_eng_busy()` (70 ms a VIDEO_DONE). Con `MIPI_DSI_CLOCK_NON_CONTINUOUS` puesto.
Sin ULPS-exit. Sin limpieza de status previa. Sin SPLIT_LINK. Funciones byte-identicas
(el `diff` de `dsi_host.c`, 243 lineas, es solo: pokes UKE, batching, slice_per_pkt,
firma de `dsi_timing_setup`, L34, seamless).

Las unicas diferencias reales sheng-vs-uke estan **en el panel, no en el host**:

| # | sheng (vive) | uke o82 (muere) |
|---|---|---|
| mode_flags | `VIDEO\|VIDEO_BURST\|NON_CONTINUOUS\|LPM` | `VIDEO\|LPM\|NON_CONTINUOUS` (**sin BURST**; vendor o82 exige `non_burst_sync_event`, luego NO copiar BURST) |
| bpc / formato | 8 / RGB888 | **10** / RGB888 (con DPU a 10 bpc contra link a 24 bpp: candidato nuevo, no ciclado) |
| DSC | 762x16, 8bpc→8bpp, slice_count 2, **slice_per_pkt 2**, **PPS enviado** (`0x90` DSC-enable + `picture_parameter_set`) | 800x24, 10bpc→8bpp, slice_count 2, slice_per_pkt 1 (driver viejo), **sin PPS** (IC "preconfigurado" segun comentario) |
| init DCS | todo en LPM, `sleep-out`+120 ms, `display-on` | igual patron (LPM, 0x11+120 ms, 0x29), 108 cmds vendor + tail b2/b3 |
| reset | 10/3/3 ms + 15 ms final | 10/3/3 ms + **100 ms** final (r7, discriminador temporal, ya probado inocuo) |
| DTS dual-dsi | `dual-dsi-mode + sync-dual-dsi + master-dsi`, sin split-link | bonded igual, sin split-link (paridad) |

Consecuencia: **H1-fuerte, H2, H3-requisito y "orden invertido" quedan refutadas como causa
raiz por contraejemplo vivo** (sheng las incumple todas y enciende). Lo que queda en pie es
H1-debil (HS_TIMER magico `0x4BB80` del propio `.ko`), H4 (limpieza de status) y H8 (path de
comandos) — mas dos candidatos nuevos del panel (bpc=10, PPS ausente).

## 2. Respuestas a las 6 preguntas del encargo

1. **NON_CONTINUOUS**: sheng **lo lleva** (nt36532e.c:327-328) y enciende. Nosotros tambien
   (o82:622-623). Quitarlo (l37) es experimento vendor-motivado (H3), no sheng-motivado.
2. **Motor de video**: sheng lo enciende **antes** de los DCS, exactamente igual que nosotros
   (`dsi_op_mode_config(VIDEO)` en `msm_dsi_host_enable` + `dsi_wait4video_eng_busy` en cada
   `dsi_cmd_dma_tx`). CAF hace lo inverso (DCS con motor apagado, espera solo DMA_DONE 200 ms).
   La diferencia estructural CAF-vs-mainline es real, pero sheng demuestra que el orden
   mainline funciona si el motor arranca.
3. **DSC**: sheng 762x16/8bpc→8bpp/slice_per_pkt=2 **con PPS**; o82 800x24/10bpc→8bpp/
   slice_per_pkt=1 (driver sin soporte) **sin PPS**. La aritmetica de compresion del host
   (`bytes_per_pkt`, `pkt_per_line`) difiere en packetizacion.
4. **mode_flags**: sheng `VIDEO|BURST|NON_CONT| LPM`; o82 `VIDEO|LPM|NON_CONT`. Uno a uno en
   la tabla de S1. BURST no se copia (vendor o82: non-burst).
5. **ULPS-exit / limpieza de status**: **ninguno de los dos**. Ambos usan el handler upstream
   sin clear-before-unmask. Paridad total.
6. **Parches locales DSI en sheng**: **SI existen** (dsi.xml + seamless + batching +
   slice_per_pkt + round_rate) pero **ninguno corre en el power-on**. Ver S0.

## 3. Los parches (uno por ciclo, orden de aplicacion)

### l36 — `build/gates/patches/l36-no-video-wait-cmd.diff` (APLICAR PRIMERO)

No bloquear comandos en `VIDEO_DONE`: early-return en `dsi_wait4video_eng_busy()`.
Con el motor parado, cada DCS agota 70 ms y muere; CAF nunca espera VIDEO_DONE por DCS
(solo DMA_DONE 200 ms, que se conserva intacta en `dsi_cmd_dma_tx`). No reordena nada:
si el motor arranca, el comportamiento observable es el mismo menos la espera.
Si el SoC sigue muriendo tras l36, el VIDEO_DONE no era el mecanismo de muerte (falsador
limpio). Compila: `dsi_host.o` OK con los flags del proyecto
(`ARCH=arm64 LLVM=1 LD=ld.lld CLANG_TRIPLE=aarch64-linux-gnu-`); `patch --dry-run -p0` OK;
arbol dejado limpio (parche sin aplicar en el tree).

```diff
--- build/kernel-pokes/k52L33-tree/drivers/gpu/drm/msm/dsi/dsi_host.c
+++ build/kernel-pokes/k52L33-tree/drivers/gpu/drm/msm/dsi/dsi_host.c
@@ -1257,7 +1257,25 @@
 
 static void dsi_wait4video_eng_busy(struct msm_dsi_host *msm_host)
 {
+	/*
+	 * L36 (13-oct, ciclo 4 de L35): no bloquear la transmision de
+	 * comandos en VIDEO_DONE.
+	 *
+	 * Evidencia: el vendor CAF nunca espera VIDEO_DONE en el path de
+	 * comandos; solo espera DMA_DONE 200 ms (dsi_ctrl_dma_cmd_wait_for_done,
+	 * dsi_ctrl.c:371-403; DSI_CTRL_TX_TO_MS = 200). En CAF los DCS de
+	 * encendido se envian con el motor de video APAGADO (dsi_display_enable
+	 * llama a dsi_panel_enable ANTES que a dsi_display_vid_engine_enable).
+	 * Mainline, en cambio, enciende video antes de los DCS y cada comando
+	 * bloquea 70 ms en VIDEO_DONE: con el motor parado (nuestro caso:
+	 * status=4 + VIDEO_DONE perdido) el primer DCS es sentencia de muerte.
+	 * La espera DMA_DONE de dsi_cmd_dma_tx() (200 ms, abajo) se conserva:
+	 * es la que CAF usa. Ver docs/historia/revision/ANDROID-DSI-ENABLE-COMPARISON-20261013.md H8
+	 * y vendor-caf-dsi.md S8.
+	 */
 	u32 data;
+	(void)msm_host;
+	return;
 
 	if (!(msm_host->mode_flags & MIPI_DSI_MODE_VIDEO))
 		return;
```

Justificacion por linea: el comentario fija la evidencia (CAF S8, COMPARISON H8);
`(void)msm_host; return;` es el unico cambio de comportamiento (el `u32 data` se mantiene
para que el codigo inalcanzable posterior siga compilando); nada mas se toca.

### l37 — `build/gates/patches/l37-continuous-clock.diff` (UN CICLO DESPUES, solo si l36 no basta)

Quitar `MIPI_DSI_CLOCK_NON_CONTINUOUS` del o82: con el flag, `dsi_ctrl_enable` salta el
bloque `LANE_CTRL |= CLKLN_HS_FORCE_REQUEST` y el clock no queda continuo. Es H3 (P0
pendiente) + regresion documentada (K48-A decia quitarlo, seguia puesto). Compila:
`panel-xiaomi-o82-dualdsi.o` OK (1 warning preexistente en ESD, intacto);
`patch --dry-run -p0` OK.

```diff
--- build/kernel-pokes/k52L33-tree/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c
+++ build/kernel-pokes/k52L33-tree/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c
@@ -615,12 +615,23 @@
 	/* Vendor: video mode, non_burst_sync_event, LP tx for commands,
 	 * EOT append (default in msm).
 	 */
-	/* K48-A (#507): lp11-init del vendor — sin CLOCK_NON_CONTINUOUS,
-	 * dsi_ctrl_enable (dsi_host.c:909-916) fuerza bitclk HS CONTINUO en el
-	 * carril de clock desde power_on, ANTES de rieles y reset; el vendor
-	 * tiene LP11 durante toda la secuencia de reset. */
-	.mode_flags = MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_LPM |
-		      MIPI_DSI_CLOCK_NON_CONTINUOUS,
+	/*
+	 * L37 (13-oct): sin CLOCK_NON_CONTINUOUS -> clock HS continuo.
+	 *
+	 * Evidencia: el vendor gobierna clock continuo por callback en cada
+	 * voto de clocks (_dsi_display_continuous_clk_ctrl: hs_req_sel BIT24 +
+	 * set_continuous_clk BIT28 = CLKLN_HS_FORCE_REQUEST) y programa
+	 * LANE_CTRL en consecuencia; con NON_CONTINUOUS, dsi_ctrl_enable
+	 * (dsi_host.c:909-917) salta ese bloque y el carril de clock no queda
+	 * en HS estable para las primeras tramas. Es la accion P0 aceptada y
+	 * pendiente (H3) y lo que K48-A ya contemplaba. El comentario K48-A
+	 * decia que se quito, pero el flag seguia puesto (regresion).
+	 * No se toca VIDEO_BURST: el vendor o82 declara
+	 * traffic-mode="non_burst_sync_event" y Android funciona asi; sheng
+	 * usa BURST pero es otro panel (LCD Tianma vs AMOLED o82).
+	 * Ver docs/historia/revision/ANDROID-DSI-ENABLE-COMPARISON-20261013.md H3.
+	 */
+	.mode_flags = MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_LPM,
 	.format = MIPI_DSI_FMT_RGB888,
 	.is_dual_dsi = true,
 	.freq_reg_b3 = 0x40,
```

## 4. Que NO se ha podido determinar

1. Base upstream exacta de sheng (squash unico, sin tags upstream en el clon): los
   "parches locales" de S0 podrian incluir backports de 7.2.x estables (batching,
   slice_per_pkt, round_rate existen en upstream posterior). Irrelevante para el gate:
   ninguno toca el power-on en ninguna version.
2. Si el SM7675 resetea `TIMING_DB_MODE=1` por defecto (H1-debil sigue viva solo por esto).
3. `bpc=10` con RGB888: de donde sale y si el DPU compone a 10 bpc contra el link —
   candidato nuevo sin evidencia; requiere leer el DT vendor del o82
   (`qcom,mdss-dsi-bpp` / `qcom,mdss-dsi-panel-...`) o el `.ko` (5 min, solo lectura).
4. PPS ausente: si el IC o82 lo exige aunque el comentario diga "preconfigurado".
   El vendor init de 108 DCS no contiene PPS (verificar con el blob: 2 min).
5. El mecanismo fisico de la muerte del SoC (AXI stall vs watchdog): l36 lo disocia —
   si tras l36 los DCS salen y el SoC vive con pantalla negra, el VIDEO_DONE era el
   mecanismo; si muere igual, es el enlace (HS_TIMER/limpieza) o el panel (bpc/PPS).
6. PHY 7nm vs SM7675: `dsi_phy*.c` identicos salvo pokes; el PLL engancha, PHY exonerado
   para este ciclo (pendiente solo si l36+l37 no mueven nada).

## 5. Comandos de reproduccion

```bash
SM=/tmp/opencode/sm8550-mainline; UK=build/kernel-pokes/k52L33-tree
diff $SM/drivers/gpu/drm/msm/dsi/dsi_host.c $UK/drivers/gpu/drm/msm/dsi/dsi_host.c  # 243 lineas, §S0
diff $SM/drivers/gpu/drm/msm/registers/display/dsi.xml $UK/drivers/gpu/drm/msm/registers/display/dsi.xml  # +2 regs
diff -rq $SM/drivers/gpu/drm/msm/dsi/phy/ $UK/drivers/gpu/drm/msm/dsi/phy/  # solo pokes
sed -n '314,341p' $SM/drivers/gpu/drm/panel/panel-novatek-nt36532e.c  # desc sheng
patch --dry-run -p0 < build/gates/patches/l36-no-video-wait-cmd.diff
patch --dry-run -p0 < build/gates/patches/l37-continuous-clock.diff
```
