# Comparación Android vs mainline en la ventana `host-en → primer cmds2buf_tx` (panel o82, DSI bonded)

**Fecha:** 13-oct-2026. **Autor:** subagente kernel (solo análisis estático, 0 escrituras en la tablet).
**Ventana:** `K47-host-en` (207.967 s) → `dsi_cmds2buf_tx: wait for video done timed out` (208.181 s), log
`out/diag-L33/VENTA-MUERTE-acm-207s.txt` (ver `HALLAZGO-L33-DEATH-20261013.md`).

## 0. Cómo se ha hecho (método, reproducible)

- **Android (verdad):** `~/proyectos/ubuntu-uke/stock/modules/msm_drm.ko` (21891 símbolos `nm`, no stripped).
  Desensamblado con `llvm-objdump --arch-name=aarch64 -d -r` (los `bl` son reubicaciones
  `R_AARCH64_CALL26`; `.text+off` locales resueltos contra `nm -n`). Disasm completo en
  `/tmp/opencode/msm_drm.dis`, reubicaciones en `/tmp/opencode/msm.reloc` (28333 `CALL26`).
  Funciones estáticas (`t`) referenciadas como `.text+off`: resueltas por offset.
- **Mapa de registros del `.ko`:** offsets directos estilo CAF desplazado. Verificado: **mapa del `.ko` =
  mapa rnndb de mainline + 4 bytes** (p.ej. `TRIG_CTRL` 0x80→0x84, `CLK_CTRL` 0x118→0x11c,
  `CTRL` 0x0→0x4, `SPLIT_LINK` 0x32c→0x330). Mainline llega al mismo HW vía `io_offset`
  (`dsi_host.c:2038`), así que la comparación registro-a-registro es válida; no hay bug de offset.
- **Fuente CAF pública** (verificación cruzada de semántica):
  `github.com/kholk/msm-techpack-display-drivers`, rama `aosp/LU.UM.1.2.1.r1`,
  `msm/dsi/dsi_ctrl_hw_cmn.c` + `msm/dsi/dsi_ctrl_reg.h` (versión 2020; todas las secuencias
  comprobadas coinciden con el `.ko` salvo 3 valores anotados donde difieren).
  `dsi_ctrl_reg.h` confirma el mapa desplazado (`DSI_CTRL 0x0004`, `DSI_FIFO_STATUS 0x000C`,
  `DSI_SPLIT_LINK 0x0330`, `DSI_TIMING_FLUSH 0x01E4`, `DSI_TIMING_DB_MODE 0x01E8`, etc.).
- **Mainline:** `build/kernel-pokes/k52L33-tree/drivers/gpu/drm/msm/dsi/dsi_host.c` (2709 líneas),
  `dsi_manager.c`, `phy/dsi_phy*.c`, panel `drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c`,
  cabecera generada `build/kernel-pokes/k52L33-build/drivers/gpu/drm/msm/generated/dsi.xml.h`.
- **DT real Android:** `build/evidencia/android-snap/dt-r15/.../qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid/`
  (releído en esta sesión: `traffic-mode="non_burst_sync_event"`, `dma-trigger="trigger_sw"`,
  `mdp-trigger="none"`, bools presentes: `tx-eot-append`, `rx-eot-ignore`, `bllp-power-mode`,
  `bllp-eof-power-mode`, `panel-broadcast-mode`, `cmd-sync-wait-broadcast`; **sin** prop `split-link`).

## 1. Resumen ejecutivo

La diferencia más probable está en **los tres registros con los que Android "compromete" el timing
de vídeo y mainline no toca**: `TIMING_FLUSH=1` (`0x1e4`), `HS_TIMER_CTRL=0x4BB80` (`0xbc`) y
`TIMING_DB_MODE=0` (`0x1e8`). Mainline programa `ACTIVE/TOTAL/HSYNC/VSYNC` en
`dsi_timing_setup()` (`dsi_host.c:1081-1097`) pero nunca desactiva el doble-buffer de timing ni
hace flush, y deja el HS-timer a su valor de reset. Si el timing queda en sombra o el HS-timer
expira a cero, el motor de vídeo arranca con `VID_MODE_EN` (`host-en`) pero **no puede completar
ni una trama**: `VIDEO_MDP_FIFO_UNDERFLOW` (bit 3, incluido en el agregado `status=4` **sin**
disparar `sw_reset`, que solo lo hace el bit 7 de CMD_MDP) + `VIDEO_DONE` jamás llega → el primer
DCS se queda 70 ms en `dsi_wait4video_done()` (`dsi_host.c:1197-1212`) y muere. Es la única hipótesis
que explica **los dos síntomas a la vez** con una sola causa, y el instante exacto (el error nace
con `VID_MODE_EN`, no con el comando) la confirma: el comando es la víctima.

Segunda diferencia estructural: **orden invertido del motor de vídeo respecto a los DCS**.
Android envía los 108 DCS con el motor de vídeo **apagado** (`dsi_display_enable` → `tx_cmd_set`
y `vid_engine_enable` **al final**, `.ko:0x1473a0`) y su path de comandos **nunca espera**
`VIDEO_DONE` (espera `DMA_DONE` 300 ms, `dsi_ctrl_dma_cmd_wait_for_done`, `.ko:0x136d5c`).
Mainline enciende vídeo **antes** de los DCS (`pre_enable`: `power_on` → `host_enable`,
`dsi_manager.c:294-312`) y **cada** comando bloquea primero en `dsi_wait4video_eng_busy()`
(`dsi_host.c:1455`, dentro de `dsi_cmd_dma_tx`). Con el motor parado, el primer comando es una
sentencia de muerte garantizada aunque todo lo demás estuviera bien.

Tercera: mainline **jamás limpia** `FIFO_STATUS` (ni el resto de status) antes de armar el IRQ de
error; Android limpia (`FIFO←0xCCCC0789` entre otros, `.ko:0x12f18c`) y aplica disciplina
*clear-before-unmask* (`dsi_ctrl_hw_cmn_mask_error_intr`, fuente CAF). Bits pegajosos heredados
disparan el IRQ en el instante en que se arma.

El resto (SPLITLINK sin programar, `CLOCK_NON_CONTINUOUS` aún puesto, `sw_reset` que re-arme
`VID_MODE_EN`, sin exit de ULPS, máscara de error fija) son cofactores ordenados abajo. Ninguno
requiere más de una variable por ciclo.

## 2. Tabla comparativa registro a registro (ventana del enable)

Offsets en mapa CAF/`.ko` (mainline = −4 vía `io_offset`). `RW` = read-modify-write.

| # | Registro (off `.ko` / mainline) | Android (`.ko`, verificado en disasm) | Mainline (`dsi_host.c`) | ¿Igual? |
|---|---|---|---|---|
| 1 | `VID_MODE_CTRL` 0x10 / `VID_CFG0` | `video_engine_setup` (0x12df2c): TE/ext, triggers por tabla, `traffic=non_burst_sync_event`, fmt RGB888, VC0, `BLLP+EOBLLP LP`, HFP/HBP/HSA=0 (coherente con DT releído) | `dsi_ctrl_enable:806-833`: idem (SYNC_EVENT, RGB888, VC=canal, `EOF_BLLP\|BLLP` siempre) | **Sí** |
| 2 | `VID_DATA_CTRL` 0x20 / `VID_CFG1` | programado (R/G/B-sel + RGB-swap del host-cfg; 0 para o82 por ausencia en DT) | **siempre 0** (`837`) | ~Sí (valor o82 = 0 en ambos; verificar §5) |
| 3 | `TIMING_DB_MODE` 0x1e8 / — | `=0` (desactiva doble-buffer) en `video_engine_setup` | **no existe en mainline** (ni el registro ni el concepto) | **NO** |
| 4 | `ACTIVE_H/V,TOTAL,HSYNC,VSYNC,VPOS` 0x24–0x38 | `set_video_timing` (0x12d75c) + DSC | `dsi_timing_setup:1081-1097` + DSC | **Sí** (valores no comparados, §5) |
| 5 | `HS_TIMER_CTRL` 0xbc / — | `=0x4BB80` (timeout 48000 + resolución) en `set_video_timing` (fuente CAF 2020: `0x3FD08`) | **no se toca** (reset) | **NO** |
| 6 | `MISR_VIDEO_CTRL` 0xa4 / — | `=0x10100` en `set_video_timing` | **no se toca** | NO (benigno probable, solo captura) |
| 7 | `TIMING_FLUSH` 0x1e4 / — | `=1` en `set_video_timing` | **no se toca** | **NO** |
| 8 | `SPLIT_LINK` 0x330 / — | `=0x503001` (+bit8/bit4 según sublink), **condicional** a `host_cfg+0x38 != 0` (`host_setup` 0x12d054-0x12db8); o82 sin prop `split-link` en DT (§5: quizá se salta también en Android) | **no se toca** | **NO** (condicional; ver H2) |
| 9 | `CLK_CTRL` 0x11c | `=0x23F` (`host_setup`); force `\|=0x200B3F` en `ctrl_en` (0x12e1c4), restaura después | `=0x23F` (`899`, idéntico); **sin force/restore** en `op_mode_config` | ~Sí (force extra en Android; benigno) |
| 10 | `CTRL` 0x4 | `host_setup`: carriles+`CLK_EN` (bit8), **sin `ENABLE`**; `ctrl_en`: fuerza clocks, `BIT0`, restaura; `video_engine_en`: `BIT1`; `cmd_engine_en`: `BIT2` (tres writes separados) | `ctrl_enable:919-921`: `CLK_EN\|carriles\|ENABLE` de una vez; `host_enable:2436-2437` (`op_mode_config`): `VID_MODE_EN\|ENABLE` juntos | **NO** (orden y granularidad) |
| 11 | `CTRL` en `sw_reset` | `ctrl_reset` (0x12f7e0, = fuente CAF al pie): limpia `VID`, limpia `EN`, force `0x100A00`, `RESET 1→0` **sin sleep**, `CLK=0`, restaura `CTRL & ~BIT(1)` (**vídeo queda OFF**) | `dsi_sw_reset:1128-1156`: limpia `EN`, force `0x23F`, `RESET 1→0` con `msleep(20)`, **restaura CTRL íntegro (re-arme `VID_MODE_EN`)** | **NO** |
| 12 | `LANE_CTRL` 0xac | `hs_req_sel`: BIT24; `set_continuous_clk`: BIT28; `ulps_exit` (0x12d234): bits de lane + `usleep 1000-1010` | con `NON_CONTINUOUS` (o82 lo lleva, panel:622-624) **se salta todo** (`909-917`); sin ULPS-exit en ningún path de `dsi/` | **NO** |
| 13 | `LANE_MAP` 0x310 / `LANE_SWAP` 0xac | `setup_lane_map`: mapa por-lane (`0x3210` = identidad) | `LANE_SWAP_CTRL` = índice de swap (0 = identidad) | ~Sí (registros distintos, mismo efecto identidad) |
| 14 | `CMD_MDP_CTRL` 0x40, `CTRL2` 0x1b8, `DCS_CTRL` 0x44 | `cmd_engine_setup` (0x12e03c): formato+interleave, `CTRL2\|=BIT16`, wr-mem-start/continue+DCS-bit | **nada** (rama cmd de `dsi_timing_setup` solo corre en modo comando) | **NO** (solo afecta path CMD/MDP) |
| 15 | `DMA_CTRL` 0x3c | `kickoff` (0x12e30c): RMW por-comando (bcast/master/LPM/embedded BIT28) | fijo `FROM_FB\|LOW_POWER` (`864-866`) + bit LP por transferencia | ~Sí |
| 16 | `DMA_FIFO_CTRL` 0x50 | `kickoff`: `\|=0x110000` (desactiva watermarks) | **no se toca** | NO (bajo, §H8) |
| 17 | `DMA_OFFSET/LEN` 0x48/0x4c, `SW_TRIG` 0x90 | `kickoff`: offset, len&0xFFFFFF, `TRIG=1` (+`VBIF_CTRL\|=7` si versión≥7) | `cmd_xfer_commit:2363-2365`: BASE/LEN/TRIG (ídem; sin VBIF) | **Sí** |
| 18 | `ERR_INT_MASK0` 0x10c / 0x108 | base `0x7FFF3BFF` menos bits pedidos (`enable_error_interrupts` 0x12f140) + `INT_CTRL\|=BIT25` | **fijo `0x13FF3FE0`** (`895`) + solo `ERROR` irq (`897`) | **NO** (ver análisis §3-H7) |
| 19 | Status W1C (`DLN0` 0xb4, `FIFO` 0xc, `ACK` 0x68, `TIMEOUT` 0xc0, `CLK` 0x120, `STATUS` 0x8) | `enable_error_interrupts`: `0x11111 / 0xCCCC0789 / 0x11111111 / 0x1193BFFF / \|BIT16 / \|BIT31`; `mask_error_intr`: **clear-before-unmask**; `hw_dln0_phy_err`: limpia PHY antes de salir de ULPS | **ninguna limpieza previa**; solo W1C dentro del handler tras el IRQ (`1588-1665`) | **NO** |
| 20 | `DEBUG_CTRL` 0x2c8 | `=BIT28` si `phy_isolation` (`host_setup`) | **no se toca** (0) | NO (bajo) |
| 21 | `CPHY_MODE_CTRL` 0x2d8 | `=1` si CPHY | `=BIT(0)` si `cphy_mode` (`923-924`) | **Sí** |
| 22 | `EOT` 0xcc | `append_tx_eot` (=1, DT `tx-eot-append` presente) | `TX_EOT_APPEND` (sin `NO_EOT` en o82) | **Sí** |
| 23 | `TRIG_CTRL` 0x84 | `host_setup`: TE+MDP-trig por tabla; `init_trig_ctrl`: DMA-trig bits[3:0]+bit16; `cmddma_window`: 0xC/0x10000 + reg 0x104 | un solo write: `TE\|NONE\|SW\|STREAM\|BLOCK_DMA` (`868-877`) | ~Sí (repartido vs monolítico; bit12 BLOCK_DMA solo en mainline) |

Lectura de la fila 18 (decodificada contra `dsi_ctrl_reg.h` + el mapeo de `enable_error_interrupts` del
`.ko`): en semántica CAF el bit de máscara **puesto = error desactivado**. Mainline `0x13FF3FE0`
activa solo: ACK[4:0], bits 14-15 (reservados/compresión), y **HS-UNDERFLOW de los 4 lanes**
(bits 26,27,29,30 en el mapa CAF… nótese asimetría: overflows 16-19 **enmascarados**); desactiva
todo lo demás (timeouts, PLL-unlock, PHY, CMD_MDP_UF bit11, interleave). Android con "todos los
errores" activa overflows+underflows+timeouts+PLL+PHY. **Ambosvigilan HS-underflow**: la máscara no
explica por sí sola el ráfaga (ver H7), pero sí el carácter selectivo del `status=4`.

## 3. Hipótesis ordenadas (una diferencia por hipótesis)

### H1 — El timing de vídeo nunca se compromete: faltan `TIMING_FLUSH=1` + `HS_TIMER_CTRL=0x4BB80` (+ `TIMING_DB_MODE=0`). **Probabilidad: la más alta.**
- **(a) Observado.** `.ko:set_video_timing` (0x12d75c) escribe, tras los 6 registros de
  timing: `HS_TIMER_CTRL←0x4BB80` (`12d8e8: mov w0,#0xbb80; movk w0,#0x4,lsl#16`),
  `MISR_VIDEO_CTRL←0x10100`, `TIMING_FLUSH←1` (`12d910: mov w0,#1`). Y `video_engine_setup`
  (0x12df2c) deja `TIMING_DB_MODE←0`. Mainline (`dsi_timing_setup`, `dsi_host.c:1077-1097`)
  escribe los mismos 6 registros de timing y **ninguno** de los otros tres (grep en `dsi/`
  confirma: no existen `TIMING_FLUSH`, `TIMING_DB_MODE`, `HS_TIMER` en todo el árbol mainline
  salvo el `phy`).
- **(b) Por qué encaja.** Si el bloque de timing usa doble-buffer por defecto y nadie lo
  desactiva ni hace flush, los `ACTIVE/TOTAL` quedan en sombra: el motor arranca con timing de
  reset (ceros) → pide píxeles que el MDP no puede dar con esa geometría →
  `VIDEO_MDP_FIFO_UNDERFLOW` (bit 3 = parte del agregado `FIFO`, y —clave— es de los bits que
  **no** disparan `dsi_sw_reset`, `dsi_host.c:1636-1638` solo mira el bit 7 de CMD_MDP) →
  `status=4` en el instante de `VID_MODE_EN`, sin reset, y el motor no completa trama →
  `VIDEO_DONE` nunca llega → `dsi_wait4video_done` agota sus 70 ms con el primer DCS ya encolado.
  El HS-timer a cero es un segundo mecanismo independiente hacia el mismo punto (timeout de TX
  en HS inmediato). Cualquiera de los dos da exactamente `FIFO + VIDEO_DONE perdido`.
- **(c) Cambio mínimo (un ciclo = una variable).** Ciclo 1a: `dsi_write(msm_host, 0x1E4, 1)`
  (offset efectivo con `io_offset`; en nombres mainline no existe → literal `+0x1E4` sobre la
  base ya desplazada… en la práctica `dsi_write(msm_host, REG_DSI_T_CLK_PRE_EXTEND + off)`
  no; hacerlo explícito: define local `DSI_TIMING_FLUSH = 0x1e0` canónico) al final de
  `dsi_timing_setup()`, rama vídeo. Si 1a no mueve nada, ciclo 1b: `HS_TIMER_CTRL←0x4BB80`;
  ciclo 1c: `TIMING_DB_MODE←0`. No juntarlos: la regla es una variable por ciclo.

### H2 — `SPLIT_LINK` sin programar en DSI bonded. **Probabilidad: alta si aplica, con una reserva.**
- **(a) Observado.** `.ko:host_setup` (`12d05c-12d0b8`): si `host_cfg+0x38`: lee `SPLIT_LINK`
  (0x330), limpia bits[22:20] y [14:12], pone `0x503000` (`DMA_LINK_SEL=0x3` + `MDP0_LINK_SEL=0x5`)
  + `EN=1`, más bit8/bit4 según sublink. Fuente CAF: `dsi_split_link_setup()` — idéntico.
  Mainline: **cero referencias** a split-link en `drivers/gpu/drm/msm/` (grep vacío).
  **Reserva:** el write es condicional y el DT del o82 **no trae** prop `split-link`
  (verificado §0); si el byte `0x38` deriva de esa prop, Android también lo salta y H2 decae a
  "paridad por omisión mutua". Hay que resolverlo antes del ciclo (ver §5, comando dado).
- **(b) Por qué encaja.** `MDP0_LINK_SEL` reparte el flujo de píxeles del MDP entre los dos
  links; a reset (0) el encaminamiento del modo bonded es indefinido → el motor de vídeo de
  cada link se muere de hambre igual que en H1 (misma firma: underflow de vídeo + no DONE).
- **(c) Cambio mínimo.** Si la reserva se resuelve a "Android sí lo programa": escribir
  `SPLITLINK←0x503001` en `dsi_ctrl_enable()` cuando `is_bonded_dsi`. Un solo valor, sin las
  variantes de sublink en este ciclo.

### H3 — `MIPI_DSI_CLOCK_NON_CONTINUOUS` sigue puesto: el carril de clock no se fuerza a HS.
**Probabilidad: media-alta.**
- **(a) Observado.** `panel-xiaomi-o82-dualdsi.c:622-624`: `mode_flags = VIDEO|LPM|NON_CONTINUOUS`
  (el comentario K48-A dice que se quitó, **pero el flag sigue** — regresión ya señalada en
  `docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md` §6). Con él, `dsi_ctrl_enable` (`dsi_host.c:909-917`)
  **salta** el bloque `LANE_CTRL |= CLKLN_HS_FORCE_REQUEST` + `msm_dsi_phy_set_continuous_clock`.
  Android, en cambio, gobierna el clock continuo por callback en cada voto de clocks
  (`_dsi_display_continuous_clk_ctrl`, `.ko:0x13e574`, llamado desde `pre_clkoff/post_clkon_cb`):
  `hs_req_sel` (BIT24) + `set_continuous_clk` (BIT28 = el mismo `CLKLN_HS_FORCE_REQUEST`) +
  `phy_set_continuous_clk` (hasta `dsi_phy_hw_v5_0_set_continuous_clk`).
- **(b) Por qué encaja.** Sin clock HS forzado/continuo, las transiciones LP↔HS del carril de
  clock en el arranque del motor pueden dejar al engine sin bit-clock estable en sus primeras
  tramas → FIFOs a medio llenar + DONE que no llega. Es además la acción ya aceptada como P0
  y aún pendiente: cuesta un ciclo barato.
- **(c) Cambio mínimo.** Quitar `MIPI_DSI_CLOCK_NON_CONTINUOUS` de `mode_flags` (una línea).
  Nada más en ese ciclo.

### H4 — Sin limpieza de status pegajosos antes de armar el IRQ de error. **Probabilidad: media
(como cofactor del ráfaga; no explica el DONE por sí sola).**
- **(a) Observado.** Android limpia al armar errores: `FIFO←0xCCCC0789` (bits 31,30,27,26,23,22,
  19,18,10,9,8,7,3,0: under/overflows HS + CMD_DMA + CMD_MDP_UF + VIDEO_MDP_UF/OF),
  `DLN0←0x11111`, `TIMEOUT←0x11111111`, `ACK←0x1193BFFF`, `CLK|=BIT16`, `STATUS0|=BIT31`
  (`.ko:0x12f15c-0x12f1e8`), más disciplina *clear-before-unmask* en `mask_error_intr` y
  limpieza de PHY-err antes de salir de ULPS (`hw_dln0_phy_err`, fuente CAF). Mainline arma
  `ERROR` en `dsi_ctrl_enable` (`897`) **sin haber limpiado jamás** ningún status register; el
  único W1C vive dentro del propio handler.
- **(b) Por qué encaja (y su límite).** Bits pegajosos heredados (del ABL/splash o del
  `sw_reset` previo) disparan `dsi_error()` en el instante en que se arma el IRQ → `status=4`
  inmediato aunque el motor estuviera sano. **Límite honesto:** el ráfaga cae en `host-en`
  (207.967), 20–50 ms **después** de armarse el IRQ en `host-pwr` (207.918/207.945); unos bits
  puramente heredados habrían disparado entonces, no con `VID_MODE_EN`. Por eso H4 es cofactor,
  no causa raíz del DONE. El matiz que la mantiene viva: varios bits de `FIFO_STATUS`
  (`EMPTY/FULL`) son de **nivel**, no pegajosos, y solo existen como condición cuando el motor
  corre — un nivel heredado-mal-configurado también nace en `host-en`.
- **(c) Cambio mínimo.** W1C de los 6 status (`FIFO/ACK/TIMEOUT/DLN0/STATUS0/CLK`, mismos valores
  que Android) al final de `msm_dsi_host_power_on()`, antes de `enable_irq`. Solo limpieza, sin
  tocar la máscara en este ciclo.

### H5 — `dsi_sw_reset()` re-arme el motor de vídeo (Android, no). **Probabilidad: media-baja.**
- **(a) Observado.** `.ko:ctrl_reset` (0x12f7e0 = fuente CAF `dsi_ctrl_hw_cmn_ctrl_reset` al
  pie de la letra): `CTRL&=~BIT1; CTRL&=~3; CLK←0x100A00; RESET 1→0` (sin sleep en el `.ko`;
  `udelay(1)` en la CAF 2020); `CLK←0; CTRL←guardado&~BIT1` (**vídeo queda OFF**).
  Mainline (`1128-1156`): `CTRL&=~EN` (deja `VID_MODE_EN` puesto si lo estaba), force `0x23F`,
  `RESET 1→0` con `msleep(20)`, **restaura CTRL íntegro** (re-arme de vídeo en mitad del reset).
- **(b) Por qué encaja.** Re-armar `VID_MODE_EN` dentro del reset deja al motor arrancando
  sobre relojes forzados y timing a medio programar (en `power_on` el orden es
  timing→reset→`ctrl_enable`; el restore re-enciende vídeo **antes** de `ctrl_enable`). Si el
  motor queda colgado-ahí, el `host-en` posterior es un no-op sobre un motor ya tocado.
  Menos probable que H1 porque en `power_on` el CTRL parte de 0 (el restore es inocuo la
  primera vez), pero pica en re-modesets y en el `disable` (`host_disable→sw_reset`).
- **(c) Cambio mínimo (dos sub-ciclos, en orden).** 5a: restaurar `ctrl & ~DSI_CTRL_VID_MODE_EN`.
  5b (solo si 5a no mueve): force `0x100A00` en vez de `ENABLE_CLKS` (ojo: bits 20/11/9 son
  adiciones v2.8 `DYNAMIC_FORCE_ON` de la CAF; documentarlo en el commit).

### H6 — Sin exit de ULPS al votar link-clocks. **Probabilidad: baja para el primer commit, alta
para re-modesets/resume.**
- **(a) Observado.** Android sale de ULPS por callback en cada voto de clocks
  (`post_clkon_cb` 0x13ed7c: `phy_enable → idle_ctrl → set_ulps(EXIT) → continuous_clk`;
  `ulps_exit` 0x12d234 escribe `LANE_CTRL` + `usleep_range(1000,1010)`; y limpia PHY-err antes).
  Al quitarlos: `pre_clkoff_cb` (`lane_reset → soft_reset → set_ulps(ENTER)`). Mainline: **cero**
  llamadas ULPS en `dsi/` (grep `ulps` vacío) y el PHY-7nm `enable` deja los pads en LP11/STOP,
  no en ULPS — por eso el primer commit probablemente no la necesita.
- **(b) Por qué encaja poco hoy y mucho mañana.** Si algún estado previo (ABL, intento
  anterior —recuérdese que el modeset fallido **envenena** el arranque, HALLAZGO §"Efecto
  secundario"—) dejó lanes en ULPS, el motor no transmite jamás: misma firma. Tras cada muerte
  como la de L33, el siguiente arranque ya no es "fresco".
- **(c) Cambio mínimo.** Secuencia `ulps_exit` (LANE_CTRL por lanes + 1 ms) + limpieza
  `DLN0_PHY_ERR` en `msm_dsi_host_power_on()`, antes de `dsi_timing_setup()`. Solo eso.

### H7 — Máscara de error fija `0x13FF3FE0` vs calculada. **Probabilidad: baja (higiene).**
- **(a) Observado.** Fila 18 de la tabla: ambas vigilan HS-underflow; mainline además enmascara
  overflows/timeouts/PLL/PHY/CMD_MDP_UF que Android con "todos" vigila. El `status=4` observado
  es compatible con ambas máscaras.
- **(b)** No explica el DONE; solo cambia qué se reporta. No gastar un ciclo aquí hasta agotar
  H1–H5. Se lista para que no se re-descubra.
- **(c)** Alinear a la calculada desde `0x7FFF3BFF` con todos los errores del o82. Último ciclo.

### H8 — Path de comandos: `DMA_FIFO_CTRL`, `VBIF_CTRL`, CMD-engine en modo vídeo, force de
clocks por transferencia. **Probabilidad: baja.**
- **(a) Observado.** `kickoff` desactiva watermarks (`DMA_FIFO_CTRL|=0x110000`) y toca
  `VBIF_CTRL|=7` (v≥7); `cmd_engine_setup` programa `CMD_MDP_CTRL/CTRL2/DCS_CTRL` también en
  modo vídeo; `transfer_prepare` (0x133070) hace `pm_resume` + voto de clocks sin tocar `CTRL`.
  Mainline: nada de lo primero, y `xfer_prepare` (`2159-2192`) mete `CMD_MODE_EN|ENABLE` +
  IRQ `CMD_DMA_DONE` alrededor de cada transferencia.
- **(b)** Todo esto vive **después** del DONE-perdido en la cadena causal (el timeout ocurre en
  `dsi_cmd_dma_tx:1455` **antes** del trigger). Solo importaría si, arreglado el vídeo, un DCS
  concreto fallara — y los 108 DCS son byte-idénticos a Android. No gastar ciclos aquí primero.
- **(c)** Si se llega: `DMA_FIFO_CTRL|=0x110000` en `cmd_xfer_commit`, una variable.

## 4. Cambios de una variable, en orden, para los próximos ciclos

| Ciclo | Cambio (uno solo) | Dónde | Hipótesis | Falsador |
|---|---|---|---|---|
| 1a | `TIMING_FLUSH ← 1` tras programar timing vídeo | `dsi_timing_setup()`, rama vídeo (`dsi_host.c:~1097`) | H1 | el ráfaga `status=4` desaparece o el DONE llega |
| 1b | `HS_TIMER_CTRL ← 0x4BB80` | mismo sitio | H1 | idem |
| 1c | `TIMING_DB_MODE ← 0` en `dsi_ctrl_enable()` | `dsi_host.c:~899` | H1 | idem |
| 2 | W1C de los 6 status (valores §H4) antes de `enable_irq` | `msm_dsi_host_power_on()` | H4 | ráfaga ausente aunque el DONE siga perdido (disocia H1/H4) |
| 3 | `SPLITLINK ← 0x503001` si bonded (**solo si §5-reserva dice que Android lo programa**) | `dsi_ctrl_enable()` | H2 | idem 1a |
| 4 | Quitar `MIPI_DSI_CLOCK_NON_CONTINUOUS` de `mode_flags` | panel o82 `:~622` | H3 | idem 1a |
| 5a | `sw_reset`: restaurar `ctrl & ~VID_MODE_EN` | `dsi_sw_reset()` (`~1152`) | H5 | supervivencia en re-modeset |
| 5b | `sw_reset`: force `0x100A00` | mismo | H5 | idem |
| 6 | ULPS-exit + limpiar `DLN0_PHY_ERR` en `power_on` | `msm_dsi_host_power_on()` | H6 | arranques post-muerte dejan de envenenarse |
| 7 | Máscara de error calculada desde `0x7FFF3BFF` | `dsi_ctrl_enable()` (`:895`) | H7 | reporte (no supervivencia) |
| 8 | `DMA_FIFO_CTRL \|= 0x110000` en el commit | `cmd_xfer_commit()` (`:2358`) | H8 | DCS sueltos |

Nota de método: el ciclo 2 es deliberadamente el discriminador H1/H4 (si limpia el ráfaga pero
el DONE sigue perdido, H1 queda confirmada como causa del DONE y H4 como cosmética del
reporte). Si el ciclo 1a arregla ambas cosas, H4–H8 se aparcan sin gastar slots.

## 5. Lo que NO se ha podido determinar y por qué

1. **Si Android programa `SPLIT_LINK` para el o82** (reserva de H2). El write es condicional
   (`host_cfg+0x38`) y el DT no trae prop `split-link`. Falta trazar `dsi_panel_get_host_cfg_for_mode`
   (`.ko:0x15523c`) hasta el parseo DT que rellena ese byte. Hace falta: desensamblar esa función
   (≈30 min) o leer el registro en vivo tras un prepare Android (imposible: prohibido tocar la
   tablet). Sin esto, H2 no debe ciclarse antes que H1/H4.
2. **Valores exactos de `VID_CFG0/VID_CFG1` del o82 en Android** (fila 2 de la tabla). El `.ko`
   los construye desde el host-cfg (struct en memoria, alimentado por DT). Los inputs DT están
   (traffic/dma/mdp-triggers/EOT/BLLP, §0) y dan igualdad estructural con mainline, pero los
   bytes de swap (`+0x24/25/26`) y `last_line_interleave` no se leyeron del DT en esta sesión.
   Hace falta: leer 6 props/bytes más del mismo nodo DT (5 min, solo lectura local).
3. **Máscara de errores efectiva en Android** (qué `errors` pasa el llamador indirecto a
   `enable_error_interrupts`). La función es ops (puntero en tabla, solo refs `ADRP/ADD` en
   `catalog_setup+0xf0`); el argumento viaja por `blr` y no se resolvió. La base `0x7FFF3BFF`
   y el mapeo bit-a-bit sí quedaron verificados contra la CAF pública.
4. **Semántica exacta de `0x100/0x104`** (`configure_cmddma_window`, `.ko:0x130294`) y de
   `0x194` (`cmd_engine_setup`, `COMMAND_MODE_MDP_IDLE_CTRL` en la CAF 2020). La CAF 2020 no
   trae `0x100/0x104`; hace falta una cabecera v2.7+ (CodeLinaro `dsi_ctrl_hw_2_8` o similar).
   Viven en el path de comandos, fuera de la ventana causal del DONE: no bloquean H1–H6.
5. **Stale-vs-live en el ráfaga ×8.** El worker usa `pr_err_ratelimited` (10/5 s): 8 líneas
   impresas no distinguen "8 eventos reales y silencio" (stale limpiado por el propio W1C del
   handler) de "condición continua con el resto suprimido" (stall vivo). Hace falta: traza con
   ratelimit desactivado o lectura viva de `FIFO_STATUS` — ambas fuera de alcance estático.
   El argumento temporal (§H4: el IRQ se arma en `host-pwr`, el ráfaga nace en `host-en`)
   favorece live, pero no es prueba.
6. **Valores de timing que programa mainline** (¿son siquiera correctos para 1600×2136 DSC?).
   `dsi_timing_setup` parte `mode->*` a la mitad por bonded; la aritmética se declara verificada
   en comentarios del panel, pero no se re-ejecutó aquí. Si H1a/H1b no mueven nada, el siguiente
   paso estático es dumpear el `drm_display_mode` efectivo y recalcular a mano (no un ciclo de flash).
7. **Lado PHY v5.2 del vendor** (`dsi_phy_hw_v5_0_*` existen en el `.ko`; mainline usa su
   `dsi_phy_7nm`/4nm genérico). Comparar timings de PHY queda fuera de esta ventana: el PLL
   engancha (`status` sin `0x20`) y eso exonera al PHY como causa del DONE en este ciclo.

## 6. Respuestas directas a las 6 preguntas del encargo

1. **MDP FIFO / burst / packet-size:** Android programa en modo vídeo `CMD_MDP_CTRL(0x40)`,
   `CTRL2|=BIT16`, `DCS_CTRL(0x44)` (`cmd_engine_setup`) y por-comando `DMA_FIFO_CTRL|=0x110000`;
   mainline ninguno de los cuatro. Pero el bit que habría delatado al CMD-MDP (bit 7 → `status`
   con `0x8` sumado + `sw_reset`) **no aparece**: el FIFO roto es del lado vídeo/MDP-vídeo, no
   del CMD. Por eso H1/H2 (hambre del motor de vídeo) preceden a H8.
2. **`DSI_CTRL`:** Android lo construye en 4 writes separados (carriles+CLK_EN en setup;
   `EN` con force-clocks en `ctrl_en`; `VID_MODE_EN` en `video_engine_en` **tras los DCS**;
   `CMD_MODE_EN` aparte) y su `sw_reset` restaura **sin** `VID_MODE_EN`. Mainline:
   `CLK_EN|carriles|EN` juntos en `power_on`, `VID_MODE_EN|EN` juntos en `host-en` **antes de
   los DCS**, y `sw_reset` que re-arme vídeo. El orden "vídeo-antes-de-DCS + espera-a-vídeo-en-
   cada-DCS" es el mecanismo próximo de la muerte.
3. **ULPS:** Android sale de ULPS (con limpieza de PHY-err previa y 1 ms de sleep) en cada voto
   de link-clocks vía `post_clkon_cb`, y entra al quitarlos; mainline no tiene ni un solo
   ULPS-exit en `dsi/`. Para el primer commit pesa poco (el PHY arranca en LP11/STOP); para los
   reintentos tras una muerte, mucho (H6).
4. **`set_mode`:** Android lo reparte —timing/host-cfg en `prepare` (con CORE, sin LINK) y
   rates+`timing_update` en `set_mode` (modeset) vía `dsi_display_set_mode` (0x144620):
   `update_host_config + async_timing_update + set_link_frequencies + phy_set_timing_params`.
   Mainline: timing en `power_on` con LINK ya votado, rates en `calc_clk_rate` del mismo path.
   Inversión documentada; no causal por sí sola.
5. **Máscara y limpieza previa:** §filas 18-19 y §H4/H7. Lo esencial: Android limpia status
   pegajosos al armar errores y antes de des-enmascarar; mainline jamás limpia antes del primer
   IRQ. El valor fijo `0x13FF3FE0` de mainline vigila HS-underflows y ACK, igual que el
   subconjunto correspondiente de Android: la máscara no es la causa, la falta de limpieza sí
   puede ser el ráfaga.
6. **`DEBUG_CTRL`/aislamiento y `STATUS`:** `DEBUG_CTRL(0x2c8)=BIT28` solo si el panel lo pide
   (o82: flag en `+0x238`, valor no resuelto — presumiblemente 0); `STATUS0` solo aporta el bit
   31 (interleave) en ambos. Nada causal aquí; DSPP es lado DPU, fuera de esta ventana.

## 7. Fuentes y comandos de reproducción

```bash
K=~/proyectos/ubuntu-uke/stock/modules/msm_drm.ko
# Secuencia prepare de Android (offsets citados en ANDROID-DSI-PROFUNDO):
llvm-objdump --arch-name=aarch64 -d -r --disassemble-symbols=dsi_display_prepare $K | grep -E 'CALL26|mov\s+w[12]'
# Host setup (SPLITLINK, CTRL, CLK_CTRL):
llvm-objdump --arch-name=aarch64 -d -r --disassemble-symbols=dsi_ctrl_hw_cmn_host_setup $K | sed -n '1,60p'
# Timing de vídeo (FLUSH, HS_TIMER, MISR):
llvm-objdump --arch-name=aarch64 -d -r --disassemble-symbols=dsi_ctrl_hw_cmn_set_video_timing $K | sed -n '85,125p'
# Reset (restaura sin VID) y enables (force-clocks):
llvm-objdump --arch-name=aarch64 -d -r --disassemble-symbols=dsi_ctrl_hw_cmn_ctrl_reset $K | sed -n '5,60p'
llvm-objdump --arch-name=aarch64 -d -r --disassemble-symbols=dsi_ctrl_hw_cmn_ctrl_en $K | sed -n '5,30p'
# Máscara/limpieza de errores:
llvm-objdump --arch-name=aarch64 -d -r --disassemble-symbols=dsi_ctrl_hw_cmn_enable_error_interrupts $K | sed -n '5,40p'
# Llamadores (vía reubicaciones; las estáticas van como .text+off):
readelf -rW $K | grep -E 'dsi_display_vid_engine_enable|set_video_timing' | head
# CAF pública (semántica): kholk/msm-techpack-display-drivers@aosp/LU.UM.1.2.1.r1
#   msm/dsi/dsi_ctrl_hw_cmn.c  (split_link_setup, ctrl_reset, kickoff_command, mask_error_intr …)
#   msm/dsi/dsi_ctrl_reg.h     (mapa: CTRL 0x0004 … SPLIT_LINK 0x0330, TIMING_FLUSH 0x01E4 …)
# Mainline: dsi_host.c:806-925 (ctrl_enable), :989-1126 (timing), :1128-1181 (reset/opmode),
#   :1197-1237 (video_done/busy), :1440-1472 (dma_tx), :2431-2450 (host_enable), :2483-2547 (power_on)
```
