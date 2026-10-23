# PANEL-REVISION INV — VERDAD VENDOR HS/LP_TIMER + LISTA MAESTRA + DISEÑO L74 — 2026-10-16

> Agente INV de la ronda L74. SOLO lectura local: `build/vendor-re/decomp/` (3.328 .c, dirección
> en línea 1), `build/vendor-re/disasm-coldpath/`, DTBO extraído `build/evidencia/android-snap/
> dt-r15/soc/**`, y el árbol vivo `build/kernel-pokes/k52-L16-tree` (estado L73: PPS mundo exacto,
> ACTIVE_H/TOTAL vendor-exactos, byte 148,648 MHz, INTF ceil /24 (L73-B2C), freno B2-A vivo,
> PANTALLA NEGRA con `S4-DIAG STATUS0=00004003/00004000 FIFO=dddd1019` acotado ~17 eventos/250 ms,
> underruns 10/10 en ~30 min). Cero dispositivos, cero builds.
>
> **NUEVO** = no escrito antes en ningún informe; **CORRECCIÓN** = contradice un informe previo;
> **SEMI** = dato conocido + dato nuevo. [M]=leído en fichero:línea/dirección; [C]=derivado;
> [H]=hipótesis. Offsets "vendor" = físicos del .ko; offsets "mainline" = lógicos de `dsi.xml`.
> Relación: **vendor = mainline_lógico + 4** (verificado §2).

---

## 1. VERDAD VENDOR: HS_TIMER_CTRL, LP_TIMER_CTRL y la ventana de set_video_timing

### 1a. Los writes exactos (decomp + disasm, cita doble)

`dsi_ctrl_hw_cmn_set_video_timing` (decomp `dsi_ctrl_hw_cmn_set_video_timing.c`, entrada **002e7b3c**;
desasm `disasm-coldpath/dsi_ctrl_hw_cmn_set_video_timing.s`). Tras los 6 registros de timing
(vendor +0x24/0x28/0x2c/0x30/0x34/0x38, líneas 66-71 del decomp), escribe **incondicionalmente**
tres registros más (decomp líneas 72-74; desasm direcciones exactas):

| Orden | Escritura | Dirección vendor | Dirección mainline | Desasm |
|---|---|---|---|---|
| 7 | `0x4bb80` | **+0xbc** | **REG_DSI_HS_TIMER_CTRL (0xb8)** | `12d8e8: mov w0,#0xbb80; movk w0,#0x4,lsl#16; add x1,x8,#0xbc` (s:117-123) |
| 8 | `0x10100` | +0xa4 | 0x00a0 (sin nombre en dsi.xml; = **MISR de vídeo**, ver §1d) | `12d8fc: mov w0,#0x100; movk w0,#0x1,lsl#16; add x1,x8,#0xa4` (s:124-130) |
| 9 | `1` | +0x1e4 | 0x01e0 (sin nombre en dsi.xml; = "FLUSH", vecino de TIMING_DB) | `12d910: mov w0,#1; add x1,x8,#0x1e4` (s:131-136) |

La rama DSC (decomp líneas 44-49) añade dos writes ANTES: el 0x2a0 vendor (mainline 0x29c
`VIDEO_COMPRESSION_MODE_CTRL` — mainline SÍ lo escribe, `dsi_host.c:1009-1011`, paridad B2 §1e)
y `+0x10 |= 0x2000000` (mainline **VID_CFG0 (0x0c) bit 25 = DATABUS_WIDEN**) gated por la
capability `*(char*)(ctrl_hw+0x23a)` — ver §3-d.

### 1b. LP_TIMER_CTRL: **el vendor TAMPOCO lo escribe — CORRECCIÓN a B2**

[Grep de los 3.328 ficheros]: NO EXISTE ninguna escritura al offset vendor +0xb0
(= mainline 0xac bajo el mapa; y el registro LP_TIMER_CTRL vendor estaría en +0xb4 bajo la
convención "LP_TIMER_CTRL justo antes de HS_TIMER" — NINGUNA de las dos es escrita como tal).
Los únicos toques a la vecindad en todo el .ko:
- `+0xb4` (= mainline **0xb0 DLN0_PHY_ERR**): máscara/clear `0x11111` en
  `dsi_ctrl_hw_cmn_enable_error_interrupts` (002e9520, línea 14) y clear en
  `dsi_ctrl_hw_cmn_clear_error_status` (002e9314, línea 28). NO es LP_TIMER.
- `+0xbc` (= mainline 0xb8 HS_TIMER_CTRL): solo set_video_timing (§1a).

**CORRECCIÓN de B2 §5.1/D5**: B2 escribió "LP_TIMER_CTRL … vendor (no visto en host_setup; sus
reads de fábrica sí corren)". La verdad dura es: **el vendor jamás escribe LP_TIMER_CTRL en
ninguna parte del binario** (ni host_setup, ni set_video_timing, ni probe). LP_RX_TO/BTA_TO
quedan en reset de HW **también en el vendor**. Consecuencias: (a) la hipótesis "BTA_TO=0
cuelga el BTA" queda SIN soporte vendor — el propio vendor opera el DDIC con los valores de
reset y sus lecturas de fábrica fallaron igual que las nuestras (A3 §3/N4); (b) escribir
LP_TIMER en L74 sería **divergir del vendor**, no paridad. Candidata LP_TIMER: **MUERTA**.

### 1c. Mapa vendor↔mainline verificado contra el XML (encargo 1c)

- Mainline mapea el registro lógico R en físico `base + 4 + R`:
  `dsi_cfg.h:39` `#define DSI_6G_REG_SHIFT 4`; `dsi_cfg.c:197-204` `sm8650_dsi_cfg`
  (`.io_start = {0xae94000, 0xae96000}`, `.io_offset = DSI_6G_REG_SHIFT`);
  `dsi_host.c:2162-2163` `msm_host->ctrl_base += cfg->io_offset` (una vez, tras
  `dsi_get_config`, que por eso suma a mano en `dsi_host.c:77`);
  `dsi_read/dsi_write` (`dsi_host.c:196-204`) usan la base ya desplazada.
- El registro mainline 0xb8 es EXACTAMENTE `REG_DSI_HS_TIMER_CTRL`:
  `registers/display/dsi.xml:250-254` y generado `k52L73-build/.../generated/dsi.xml.h:499`
  (`#define REG_DSI_HS_TIMER_CTRL 0x000000b8`, campos `HS_TX_TO[15:0]`,
  `TIMER_RESOLUTION[19:16]`, `HS_TX_TO_STOP_EN[28]`). El vecino 0xb4 es
  `REG_DSI_LP_TIMER_CTRL` (`LP_RX_TO[15:0]`, `BTA_TO[31:16]`, dsi.xml:246-249;
  dsi.xml.h:484). **No hay otro registro en 0xb8** — la correspondencia es única.
- Estado en mainline: los dos macros existen en el header generado pero **NINGÚN .c del árbol
  los referencia** (grep en `drivers/gpu/drm/msm/dsi/` + `disp/`: 0 usos; B2 §5.1 ya lo
  documentó para L72; re-verificado en el árbol L73). Quedan en reset de HW.

### 1d. Identidad de los otros dos writes de la ventana ("los 3 writes")

- **MISR de vídeo (+0xa4 vendor / 0x00a0 mainline)**: `dsi_ctrl_hw_cmn_setup_misr`
  (decomp `dsi_ctrl_hw_cmn_setup_misr.c`, 002e7938) confirma la identidad: para "vídeo"
  (parámetro ≠2) escribe en `+0xa4` el valor `0x10000 | min(frames,0xff)<<8`; para "cmd"
  escribe `+0xa0` con bit 28. El valor de set_video_timing `0x10100` = enable(bit16) +
  **1 frame** (1<<8). `dsi_ctrl_hw_cmn_collect_misr` (002e79e4) lee la firma en `+0x140`
  (mainline 0x13c) si el bit enable sigue puesto. Es la unidad MISR de captura de firma:
  **100 % diagnóstico**, no toca el flujo de datos.
- **FLUSH (+0x1e4 vendor / 0x01e0 mainline)**: registro SIN nombre en dsi.xml y sin lector en
  todo el .ko. Vecino inmediato de TIMING_DB: `dsi_ctrl_hw_cmn_set_timing_db` (002e7aa4)
  escribe `+0x1e8` (mainline 0x1e4) con 0/1 (double-buffer de timing), y
  `dsi_ctrl_hw_cmn_video_engine_setup` (002e830c, línea 19) escribe `+0x1e8 ← 0`.
  La única escritura del FLUSH en todo el binario es la de set_video_timing. Semántica
  probable (no cerrada): commit/flush del bloque de timing/pipeline. **Siempre se escribe 1,
  incondicional, al final de cada setup de timing de vídeo.**
- Orden vendor completo en la ventana: `0x2a0 (DSC) → [+0x10 |= bit25 si widebus-cap] →
  ACTIVE_H/V/TOTAL/HSYNC/VPOS/VSYNC → HS_TIMER → MISR → FLUSH → evtlog`.

---

## 2. MECANISMO, CON ESCEPTICISMO (encargo 2)

### 2a. Aritmética de HS_TX_TO

- Campos del valor vendor 0x4bb80: `HS_TX_TO = 48000`, `TIMER_RESOLUTION = 4`,
  `HS_TX_TO_STOP_EN = 0`.
- **Deadline = 48000 × 4 = 192.000 ciclos de byte-clock** (el timer cuenta a
  byteclk/resolución = 148.648.500/4 = 37,162 MHz; tick = 26,9 ns).
  `192.000 / 148.648.500 = 1,2917 ms`.
- Línea a pclk 158,5584 MHz con htotal DSI 679 px (mundo 24): `679 / 158.558.400 = 4,2815 µs`.
  El deadline cubre `1,2917 ms / 4,2815 µs ≈ 301,7 líneas` (~13 % de un frame de 2.310 líneas
  = 9,892 ms; ≈ 480 bursts HS de línea, que duran 1.600 B×8 / 4×1,18919 G = 2,69 µs cada uno).
- Veredicto de plausibilidad: es un **watchdog de "burst HS colgado"** (escala ms), no un
  timeout por línea. Generoso por diseño; con el modo non_burst_sync_event + BLLP-LP del panel,
  cada línea es un burst separado y el timer se re-arma por transferencia (el vendor corre este
  valor exacto en este modo a 120 Hz — práctica vendor = semántica por-transferencia).
- `STOP_EN = 0`: si el timeout dispara, el HW **no** corta el burst por sí solo; solo señala.

### 2b. ¿Puede un HS_TIMER ausente producir `FIFO=dddd1019` y pantalla negra?

**NO como causa; solo como reporting.** Cadena de evidencia:

1. `FIFO_STATUS` (0x08) bit0 (VIDEO_MDP OVERFLOW) y bit3 (VIDEO_MDP UNDERFLOW) son señales de
   las **FIFOs de vídeo** (llenado por el INTF vs drenado por el motor HS) —
   `dsi.xml:119-121`. El contador HS_TX_TO no participa en fill/drain: escribe en
   `TIMEOUT_STATUS` (0xbc) vía la máquina de timeouts, no en FIFO_STATUS. Con HS_TX_TO=0 el
   watchdog está **apagado** (así ha corrido mainline siempre en otras placas): lo único que se
   pierde es la DETECCIÓN, no el flujo. Un timer ausente no puede crear underflow ni overflow;
   un timer presente no drena FIFOs.
2. Los flags de carril `dddd` (DLN0..3 HS FIFO EMPTY+OVERFLOW simultáneos) son el latch de
   desincronización ya diagnosticado (B2 §2b, huella del toggle L68); en L73 sin toggle son
   bits sticky residuales/re-disparados, no producidos por el timer.
3. La única vía real por la que HS_TIMER podría afectar comportamiento es `STOP_EN=1` (cortaría
   el burst al vencer el deadline) — y el vendor lo deja a **0**. Escribir 0x4bb80 sin bit 28
   solo AÑADE detección.

**Pero ojo, la inversa también es cierta y es lo valioso**: hoy, si el burst HS se cuelga
>1,29 ms, NADIE lo apunta (TIMEOUT_STATUS queda en 0; el S4-DIAG solo enseña FIFO/STATUS0).
Escribir el valor vendor **enciende el único detector de "enlace HS congelado"** que el HW
tiene. La firma viva (under/overflow lento + carriles) es compatible con "el INTF alimenta,
el DSI drena casi siempre, y hay eventos raros"; el watchdog L74 discriminará si esos eventos
raros son cuelgues de burst (TIMEOUT_STATUS≠0) o transitorios de arranque (TIMEOUT=0 siempre).

### 2c. LP (LP_RX_TO/BTA_TO)

Con la verdad §1b (el vendor también va con reset), la ausencia **no puede colgar el escape LP
en el vendor** — luego el estado de reset es operativo para el vendor en frío (su cold path
nunca lee por BTA, y sus lecturas de fábrica fallaron bajo splash por otras causas). El
argumento B2 §5.1 ("BTA_TO=0 ⇒ BTA aborta al instante") asume que el reset es 0, lo cual NO
está verificado; si el reset no fuera 0, el vendor demostraría que ese valor funciona. En
cualquier caso LP solo afecta a BTA/comandos (el "sordo"), **no al vídeo HS**. Reclasificada:
experimento fuera de vendor-truth, no para L74.

### 2d. ¿Y el underrun lento (10/10 en ~30 min)?

≈1 evento / 3 min / link ≈ 1 cada ~17.600 frames. Eso **refuta inanición de ancho de banda**
como causa dominante (el margen real fill/drain es 25 %, B3 §1-D4; una inanición daría eventos
por-frame o por-vsync como L69: 1.929/1.929). Es la firma de transitorios raros (arranques,
recovery de `dsi_sw_reset` de 20 ms con el INTF alimentando, gateos de energía) más el latch
residual — el freno B2-A los ha acotado exactamente como el vendor prohíbe por diseño (16/250 ms,
A3 §5a/§8-N3).

---

## 3. BARRIDO VENDOR↔MAINLINE DEL ENABLE DE VÍDEO (encargo 3) — LISTA MAESTRA

Secuencia vendor por ctrl (A3 §1 + lecturas propias): host_setup 002e73cc → set_video_timing
002e7b3c → video_engine_setup 002e830c → ctrl_en 002e85a4 → vid_engine_en 002e8520.
Mainline: `msm_dsi_host_power_on` (`dsi_host.c:2614-2681`): sfpb → vregs → link clks →
`dsi_timing_setup` (:2662) → `dsi_sw_reset` (:2663) → `dsi_ctrl_enable` (:2664) →
(bridge) `dsi_op_mode_config(true,true)` (:1193-1216, VID_MODE_EN).

| # | Registro vendor (físico) | Mainline (lógico) | Valor vendor | ¿Escribe mainline? | Confianza | Efecto esperado en contenido |
|---|---|---|---|---|---|---|
| M1 | +0xbc → **HS_TIMER_CTRL 0xb8** | REG_DSI_HS_TIMER_CTRL | **0x4bb80** | **NUNCA** (grep árbol L73) | **SEGURA** (paridad exacta, §1a) | Bajo: reporting-only (§2b); abre canal TIMEOUT_STATUS |
| M2 | +0xa4 → 0x00a0 (MISR vídeo) | (sin nombre) | **0x10100** (enable+1 frame) | **NUNCA** | **SEGURA** (setup_misr 002e7938) | Nulo funcional; canal de diagnóstico MISR (firma de líneas) |
| M3 | +0x1e4 → 0x01e0 (FLUSH) | (sin nombre) | **1** | **NUNCA** | SEGURA como paridad; **semántica desconocida** (§1d) | Desconocido; candidato especulativo de commit de timing |
| M4 | +0x10 VID_CFG0 bit25 (DATABUS_WIDEN) | REG_DSI_VID_CFG0 | `|= 0x2000000` en rama DSC si capability +0x23a | Sí condicional (`:857-858`); nuestro hack L71 = false | capability NO resoluble estático (versiones 4-7 del enum, `dsi_catalog_ctrl_setup.c:74-76`); **contradicción**: con bit25 el ACTIVE_H del vendor tendría que ser 267/800, y stock/DECOMP dan **534** (mundo 24 verificado) | NO ACCIONAR (rompería el mundo verificado) |
| M5 | +0x1e8 TIMING_DB ← 0 (video_engine_setup:19) | 0x01e4 (sin nombre) | 0 | NUNCA | probablemente default de reset | Especulativo; no accionar |
| M6 | +0x2c8 ← 0x10000000 (host_setup:47, si flag +0x238) | 0x02c4 (sin nombre; "deskew") | no se ejecuta: la bool DT no existe en `qcom,mdss_dsi_ctrl0@ae94000` (§ abajo) | NUNCA | n/a (o82 NO lo ejecuta) | ninguno |
| M7 | CTRL +0x4: bits 24/20 (CRC_CHECK/ECC_CHECK) ← host_cfg | REG_DSI_CTRL | no se ejecutan: DT del ctrl/panel no trae las bools (sin `qcom,mdss-dsi-ecc-check`/`crc-check` en el nodo o82) | Sí sin esos bits (`:927-947`) | paridad REAL (descartado como hueco) | ninguno (solo activarían chequeo de paquetes) |
| M8 | TRIG_CTRL +0x84: MDP_TRIGGER = tabla[ver]&7, TE | REG_DSI_TRIG_CTRL (`:894-903`) | **CORRECCIÓN A3 §2c**: +0x84 es TRIG_CTRL (bit31 TE, bits 4-6 MDP_TRIGGER), NO "LANE_CFG". Con `qcom,mdss-dsi-mdp-trigger = "none"` y `dma-trigger = trigger_sw` (DT o82, leídos) ⇒ **paridad exacta** con mainline (NONE/SW) | Sí | paridad (cerrado) | ninguno |
| M9 | +0xc4 CLKOUT t_post/t_pre | REG_DSI_CLKOUT_TIMING_CTRL (`:905-907`) | de la PHY | Sí (igual) | paridad | — |
| M10 | +0xcc EOT tx/rx | REG_DSI_EOT_PACKET_CTRL (`:915-918`) | de host_cfg (o82: append sí, rx_ignore no) | Sí (TX_EOT_APPEND) | paridad | — |
| M11 | +0x11c CLK_CTRL 0x23f (host_setup:38) | REG_DSI_CLK_CTRL (`:925`, ENABLE_CLKS=0x23F) | 0x23f | Sí (igual) | paridad | — |
| M12 | +0x11c pulso `|= 0x200b3f` en ctrl_en (002e85a4, transitorio, restaurado) | — | transitorio | No | transitorio (no persiste) | ninguno demostrable |
| M13 | +0x330 SPLIT_LINK (host_setup:31) | 0x032c (sin nombre) | NO ejecutado para o82 (RE-GAPS §1) | No existe en mainline | n/a | ninguno |

DT del controlador verificado: `dt-r15/soc/qcom,mdss_dsi_ctrl0@ae94000/` solo tiene
`cell-index, clock-names, clocks, compatible, frame-threshold-time-us, interrupt-parent,
interrupts, label, name, phandle, qcom,ctrl-supply-entries, reg, reg-names, vdda-1p2-supply`
— **sin** bools widebus/deskew/ecc/crc ⇒ M6/M7 no se ejecutan en el vendor (los flags del
probe `dsi_ctrl_dev_probe.c:75-81` = `of_property_read_bool` = false).

**Lista maestra final de L74 (lo que el vendor escribe en vídeo y mainline no): M1, M2, M3.**
Todo lo demás es paridad (M8-M12, verificada esta ronda) o contraindicado (M4-M7).

---

## 4. ICC F2 (mmss_noc) — ¿vía runtime sin re-flashear dtbo? (encargo 4)

**No hay vía runtime razonable; diferir.**

1. El framework de interconnect solo expone debugfs de LECTURA:
   `drivers/interconnect/core.c:1262-1265` crea `interconnect_summary` e `interconnect_graph`
   con `0444`. No existe sysfs/debugfs de escritura para crear peticiones.
2. Las APIs exportadas para consumidores (`of_icc_get` core.c:607, `devm_of_icc_get` :444,
   `icc_set_bw` :765) requieren un `device_node` con la propiedad `interconnects` — que es
   exactamente lo que parchea el DTBO (`fase4-display.dts:196-201`). No hay API exportada para
   fabricar un path entre nodos arbitrarios (los `icc_node_*` exportados son para proveedores).
   Un módulo externo (CONFIG_MODULES=y, sin CONFIG_MODULE_SIG) no puede votar mmss_noc por el
   mdss sin DT.
3. La alternativa kernel (quirk en `msm_mdss.c:57-70` que parseara una segunda ruta) sigue
   necesitando el DT real para `of_icc_get` ⇒ mismo bloqueo.
4. **¿Consistencia de inanición?** Un VIDEO_MDP *underflow* ES el síntoma correcto de inanición
   (el MDP no llena la FIFO y el motor la vacía), PERO el ritmo lo refuta como causa activa:
   10 eventos/30 min ≈ 1/17.600 frames (§2d), el control L67 dio **0 underruns con el mismo
   ICC** (B3 §3), y el voto DPU actual (4,25 GB/s sobre el path mc_virt) cubre el scanout
   (3,28 GB/s). El hueco mmss_noc (B3 §4-D5) es estructural y real, pero **segunda línea**.
5. Coste: F2 = 2ª escritura flash (dtbo) con `a=3` sangrando (A1 §6.10). Conclusión: **diferir
   F2** hasta que el canal L74 (MISR/TIMEOUT) pruebe que el host sí fluye y el residuo siga
   siendo underflow físico; entonces F2 es el siguiente flash natural.

---

## 5. DISEÑO L74 (boot_a only, kernel, sin dtbo) (encargo 5)

**Veredicto honesto primero: HS_TIMER SOLO NO SACA CONTENIDO** (§2b: reporting-only). El
composite L74 = **paridad vendor exacta de la ventana de timing (M1+M2+M3) + los dos canales
de diagnóstico que hoy están apagados (watchdog HS + firma MISR)**. Su objetivo declarado es
(i) cerrar la ventana vendor↔mainline a cero y (ii) generar los DOS datos que deciden el
siguiente ciclo: ¿el burst HS se cuelga? ¿pasan líneas por el DSI? Ambos son precondición para
elegir entre PHY-RX-TIMING (sordo/protocolo) y DPU/INTF-side (feed).

### L74-A (MUST) — HS_TIMER + MISR + FLUSH en `dsi_timing_setup`

`drivers/gpu/drm/msm/dsi/dsi_host.c`, rama vídeo de `dsi_timing_setup` (tras el write de
`REG_DSI_ACTIVE_VSYNC_VPOS`, línea 1123 del árbol L73; posición equivalente al vendor: al final
del bloque de timing, antes del readback L68). OJO: usar offsets LÓGICOS (el driver suma +4 en
`dsi_host.c:2162`).

```diff
--- a/drivers/gpu/drm/msm/dsi/dsi_host.c
+++ b/drivers/gpu/drm/msm/dsi/dsi_host.c
@@ -1117,6 +1117,33 @@ static void dsi_timing_setup(struct msm_dsi_host *msm_host, bool is_bonded_dsi)
 		dsi_write(msm_host, REG_DSI_ACTIVE_HSYNC,
 			DSI_ACTIVE_HSYNC_START(hs_start) |
 			DSI_ACTIVE_HSYNC_END(hs_end));
 		dsi_write(msm_host, REG_DSI_ACTIVE_VSYNC_HPOS, 0);
 		dsi_write(msm_host, REG_DSI_ACTIVE_VSYNC_VPOS,
 			DSI_ACTIVE_VSYNC_VPOS_START(vs_start) |
 			DSI_ACTIVE_VSYNC_VPOS_END(vs_end));
+
+		/*
+		 * L74-A (16-oct): paridad vendor de la ventana de timing.
+		 * El vendor (set_video_timing 002e7b3c, desasm 12d8e8-12d918)
+		 * escribe INCONDICIONALMENTE tras los 6 registros de timing:
+		 *   HS_TIMER_CTRL (0xb8) = 0x4bb80  = HS_TX_TO(48000) |
+		 *     TIMER_RESOLUTION(4): watchdog de burst HS a
+		 *     192000 ciclos de byteclk = 1,29 ms (~302 lineas).
+		 *     STOP_EN=0: solo REPORTA en TIMEOUT_STATUS, no corta.
+		 *   MISR video (0x00a0, sin nombre en dsi.xml) = 0x10100
+		 *     (enable + 1 frame; setup_misr 002e7938).
+		 *   FLUSH (0x01e0, sin nombre en dsi.xml) = 1 (siempre).
+		 * Mainline nunca escribe ninguno (grep arbol L73). El
+		 * watchdog es el unico detector de burst-HS colgado del HW;
+		 * MISR da la firma de que las lineas PASAN por el DSI.
+		 * LP_TIMER_CTRL (0xb4) NO se toca: el vendor TAMPOCO lo
+		 * escribe (INV 2026-10-16, correccion a B2 D5).
+		 */
+#define REG_DSI_UKE_MISR_VIDEO_CTRL	0x00a0	/* vendor +0xa4 */
+#define REG_DSI_UKE_MISR_VIDEO_DATA	0x013c	/* vendor +0x140 */
+#define REG_DSI_UKE_FLUSH		0x01e0	/* vendor +0x1e4 */
+		uke_poke("L74-hstimer");
+		dsi_write(msm_host, REG_DSI_HS_TIMER_CTRL, 0x4bb80);
+		dsi_write(msm_host, REG_DSI_UKE_MISR_VIDEO_CTRL, 0x10100);
+		dsi_write(msm_host, REG_DSI_UKE_FLUSH, 1);
+		pr_info("UKE-L74: id=%d HS_TIMER=0x%08x (rd 0x%08x) MISR=0x%08x (rd 0x%08x) FLUSH=1 (rd 0x%08x)\n",
+			msm_host->id, 0x4bb80,
+			dsi_read(msm_host, REG_DSI_HS_TIMER_CTRL),
+			0x10100,
+			dsi_read(msm_host, REG_DSI_UKE_MISR_VIDEO_CTRL),
+			dsi_read(msm_host, REG_DSI_UKE_FLUSH));
 		/* L68 (uke): readback de los registros de timing escritos; el
```

### L74-B (MUST, diagnóstico) — MISR en el print S4-DIAG

El mismo fichero, `dsi_wait4video_done` (árbol L73 :1262-1270). Añade la lectura de la firma
MISR al volcado que ya sale en cada timeout (ratelimited por L73-B2B). MISR_DATA≠0 ⇒ las
líneas están atravesando el pipeline de vídeo del DSI (host OK ⇒ el residuo es PHY-RX/protocolo
de panel); MISR_DATA=0 con BUSY=1 ⇒ el motor nunca movió datos (problema de feed/INTF).

```diff
@@ -1262,9 +1289,11 @@ static void dsi_wait4video_done(struct msm_dsi_host *msm_host)
 	if (ret == 0) {
 		/* S4-DIAG (arranque): distingue "motor parado" de "motor colgado". */
 		u32 st0 = dsi_read(msm_host, REG_DSI_STATUS0);
 		u32 fifo = dsi_read(msm_host, REG_DSI_FIFO_STATUS);
+		/* L74-B (16-oct): firma MISR de video (0x10100 armado en L74-A).
+		 * DATA != 0 => lineas pasando por el pipeline DSI. */
+		u32 misr = dsi_read(msm_host, REG_DSI_UKE_MISR_VIDEO_DATA);
 		DRM_DEV_ERROR_RATELIMITED(dev,
-			"S4-DIAG: wait for video done timed out, id=%d STATUS0=%08x FIFO=%08x (BUSY=%d)\n",
-			msm_host->id, st0, fifo,
+			"S4-DIAG: wait video done id=%d STATUS0=%08x FIFO=%08x MISR=%08x (BUSY=%d)\n",
+			msm_host->id, st0, fifo, misr,
 			!!(st0 & DSI_STATUS0_VIDEO_MODE_ENGINE_BUSY));
 	}
```

### NO va en L74 (y por qué)

- **LP_TIMER_CTRL**: el vendor tampoco lo escribe (§1b) — escribirlo es experimento sin verdad
  vendor, y solo afecta BTA/comandos, no vídeo.
- **DATABUS_WIDEN bit25 (M4)**: rompería el mundo 534/679 verificado en stock y en L71/L73.
- **ECC/CRC CTRL (M7), deskew (M6), TIMING_DB (M5), pulso CLK_CTRL 0x200b3f (M12)**: no
  ejecutados por el vendor en o82, transitorios o default — sin efecto esperado.
- **F2 ICC (dtbo)**: sin vía runtime (§4), ritmo de errores incompatible con inanición (§2d),
  2ª escritura flash. Diferido.
- Freno B2-A, ratelimits B2-B, ceil INTF L73-B2C: ya vivos, no se tocan.

### Criterio post-boot

1. **Marcador**: dos líneas `UKE-L74: id=0/1 HS_TIMER=0x4bb80 (rd 0x4bb80) MISR=0x10100 (rd
   0x10100) FLUSH=1 (rd 0x1)` — los readbacks DEBEN ecoar lo escrito (el +4 del mapa está
   verificado §1c; un eco distinto indicaría un mapa mal y se aborta la interpretación).
2. **ÉXITO-total** (improbable pero gratis): pantalla con contenido y `dmesg | grep -c S4-DIAG`
   plano; FIFO crudo (`devmem 0xae94008`/`0xae96008`) sin dddd1019.
3. **Discriminante A (esperado si el residuo es transitorio de arranque)**: TIMEOUT_STATUS
   sigue en 0 en todos los S4-DIAG (nadie detecta cuelgues) y MISR≠0 en el primer volcado ⇒
   el host empuja vídeo real; el negro vive en PHY-RX/panel ⇒ **L75 = 14 TIMING_CTRL RX del DT
   vendor** (candidata nº1 histórica, PHY-LANE-RATE §A).
4. **Discriminante B (nuevo si aparece)**: líneas `TIMEOUT_STATUS≠0` ⇒ burst HS se cuelga
   ≥1,29 ms ⇒ el enlace muere en caliente; combina con PHY/handshake ⇒ L75 = PHY primero.
5. **Discriminante C**: MISR=0 con BUSY=1 ⇒ el motor DSI no recibe nada del INTF ⇒ L75 =
   DPU/INTF-side (y ahí sí, F2/F4 ICC como siguiente flash).
6. Continuidad esperada del residuo: underruns lentos (~10/30 min) y dddd1019 residual
   **no cambian** por este parche; el freno B2-A los mantiene acotados. Que sigan igual NO es
   fallo de L74.

### Riesgos

- **FLUSH 0x01e0 semántica desconocida** (único write no comprendido): paridad exacta del
  vendor en el mismo punto de cada boot de vídeo ⇒ riesgo de daño mínimo; cualquier error
  nuevo quedará absorbido por el freno B2-A (16/250 ms) y visible en el FIFO crudo.
- **HS_TIMER crea canal de errores nuevo**: si la semántica real fuera "por frame" (no por
  burst), dispararía ~1/8,3 ms/link; el freno B2-A lo caparía y el patrón del log sería
  inequívoco (el vendor correría mal su propio panel — improbable).
- **MISR**: unidad de firma de depuración; el write es el valor literal vendor (1 frame);
  riesgo ~0.
- Operativos conocidos y vigentes: slots `a=3` con hemorragia (A1 §6.10), batería >3,7 V antes
  de flashear, `set_active a` + reboot tras el flash, guarda DPMS si `grep -c S4-DIAG > 1500`.

---

## 6. FICHEROS

Creado: `docs/historia/revision/PANEL-REVISION-INV-HSTIMER-20261016.md` (este). Nada más tocado.
Fuentes: `build/vendor-re/decomp/{dsi_ctrl_hw_cmn_set_video_timing,dsi_ctrl_hw_cmn_host_setup,
dsi_ctrl_hw_cmn_ctrl_en,dsi_ctrl_hw_cmn_video_engine_setup,dsi_ctrl_hw_cmn_set_timing_db,
dsi_ctrl_hw_cmn_setup_misr,dsi_ctrl_hw_cmn_collect_misr,dsi_ctrl_hw_cmn_enable_error_interrupts,
dsi_ctrl_hw_cmn_clear_error_status,dsi_ctrl_hw_cmn_vid_engine_busy,dsi_ctrl_set_vid_engine_state,
dsi_ctrl_vid_engine_en,dsi_display_vid_engine_enable,dsi_ctrl_timing_setup,dsi_ctrl_host_timing_update,
dsi_catalog_ctrl_setup,dsi_catalog_cmn_init,dsi_ctrl_isr,dsi_ctrl_dev_probe}.c`,
`build/vendor-re/disasm-coldpath/dsi_ctrl_hw_cmn_set_video_timing.s`,
`build/kernel-pokes/k52-L16-tree/drivers/gpu/drm/msm/dsi/dsi_host.c` (+ `dsi_cfg.{c,h}`,
`registers/display/dsi.xml`, generado `k52L73-build/.../generated/dsi.xml.h`),
`dt-r15/soc/qcom,mdss_dsi_ctrl0@ae94000/` y `.../qcom,mdss_dsi_o82_36_02_0a_dualdsi_dsc_vid/`,
informes A1/A3/B2/B3 (2026-10-15).
