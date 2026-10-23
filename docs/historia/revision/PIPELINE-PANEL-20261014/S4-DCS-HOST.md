# S4 — Muerte del primer DCS: el camino `cmd#0 → FIFO → TIMEOUT → host-xfer` (14-oct-2026)

> Solo análisis estático + logs medidos. 0 escrituras en la tablet, 0 modificaciones a árboles.
> Árbol de referencia: `build/kernel-pokes/k52-L16-tree` (el vivo, del que salen L19/L43–L45).

## 1. Qué he leído

**Mainline (árbol vivo):**

- `drivers/gpu/drm/msm/dsi/dsi_host.c` (2709 líneas): `dsi_host_transfer:1767-1782`,
  `msm_dsi_host_xfer_prepare:2159-2192`, `msm_dsi_host_xfer_restore:2194-2210`,
  `msm_dsi_host_cmd_tx:2212-2218`, `dsi_cmds2buf_tx:1523-1565`, `dsi_cmd_dma_add:1323-1373`,
  `dsi_cmd_dma_tx:1440-1472`, `msm_dsi_host_cmd_xfer_commit:2358-2369`,
  `dsi_wait4video_eng_busy:1215-1237`, `dsi_wait4video_done:1197-1213`,
  `dsi_host_irq:1682-1708`, `dsi_error:1667-1680`, `dsi_fifo_status:1626-1640`,
  `dsi_timeout_status:1598-1608`, `dsi_err_worker:1567-1582`,
  `dsi_ctrl_enable:806-925`, `dsi_op_mode_config:1158-1181`,
  `msm_dsi_host_enable:2431-2450`, `msm_dsi_host_power_on:2483-2547`.
- `drivers/gpu/drm/msm/dsi/dsi_manager.c:493-554` (`msm_dsi_manager_cmd_xfer`,
  `msm_dsi_manager_cmd_xfer_trigger`), `dsi_manager.c:28-63` (`IS_SYNC_NEEDED` ← DT
  `qcom,sync-dual-dsi`).
- `drivers/gpu/drm/drm_mipi_dsi.c:923-951` (`mipi_dsi_dcs_write_buffer`: msg **sin** rx),
  `drm_mipi_dsi.c:1021-1030` (dual: dsi0 y luego dsi1).
- `drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c:208-256` (`o82_send_panel_cmds`,
  `UKE-K47c` en `:218`, dual-write en `:236-238`, `accum_err` en `:246-247`).
- DT vivo: `arch/arm64/boot/dts/qcom/sm8250-xiaomi-elish-common.dtsi:608-609,658-659`
  (`qcom,dual-dsi-mode;` + `qcom,sync-dual-dsi;` en ambos links).
- Generada `build/kernel-pokes/k52L33-build/drivers/gpu/drm/msm/generated/dsi.xml.h`:
  FIFO bits `:160-182`, IRQ masks `:107-115`, `REG_DSI_TIMEOUT_STATUS :515`
  (**solo el registro; cero bitfields**), `REG_DSI_FIFO_STATUS :160`.
- `drivers/gpu/drm/msm/registers/display/dsi.xml:246-254`: `LP_TIMER_CTRL`
  (`LP_RX_TO`/`BTA_TO`) y `HS_TIMER_CTRL` (`HS_TX_TO`) existen como registros pero **ningún
  `.c` de `drivers/gpu/drm/msm/` los programa** (grep 14-oct-2026: solo matches en el xml).

**Vendor/Android (solo lectura local + análisis previos del proyecto):**

- `docs/historia/revision/ANDROID-DSI-ENABLE-COMPARISON-20261013.md` (tabla §2 filas 15–17:
  `kickoff` ≈ nuestro commit; espera `DMA_DONE` 300 ms en `dsi_ctrl_dma_cmd_wait_for_done`
  `.ko:0x136d5c`; §1: Android envía los 108 DCS con el motor de vídeo **apagado** y
  `vid_engine_enable` al final `.ko:0x1473a0`; §H4: Android limpia
  `TIMEOUT←0x11111111`/`FIFO←0xCCCC0789` con disciplina clear-before-unmask).
- `docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md` §2 (los 108 DCS: todos writes
  `dt=0x39/0x15/0x05`; `dt=0x06` reads ausente) y §1.3 (PHY a LP11 antes de programar host).
- `build/gates/revision/GAPLIST-VENDOR-MAINLINE-20261013.md` §G8 (orden vendor:
  `sw_reset(PHY) → phy_enable(LP11) → host_init → … → CTRL_ENABLE → soft_reset →
  panel_prepare → 108 DCS`; pulso RESET 1 µs vs 20 ms mainline).
- `build/gates/revision/HALLAZGO-L33-DEATH-20261013.md` (secuencia L33 207 s:
  `K47-host-en → status=4 ×8 → cmd#0 dt=39 → host-xfer ×2 → wait for video done timed out`).
- `docs/historia/ESTADO-VIVO.md` §20:0x (tabla L40/L42: `status=4` 3–4, **`status=5` 5**, `video done` 0,
  corte en `host-xfer`/`cmd#0`; L36 lleva early-return en `dsi_wait4video_eng_busy`).
- `NOTAS-OMARCHY.md:4197-4260` (veredicto G7: misma secuencia y punto de parada L40 vs L42).
- CAF pública `kholk/msm-techpack-display-drivers@aosp/LU.UM.1.2.1.r1/msm/dsi/dsi_ctrl_reg.h`
  (fetched 14-oct-2026): confirma mapa desplazado +4 (`DSI_TIMEOUT_STATUS 0x00C0`,
  `DSI_DSI_TIMING_FLUSH 0x01E4`, `DSI_SPLIT_LINK 0x0330`) y que el header **tampoco** define
  bits de `TIMEOUT_STATUS`.
- Hermano `~/proyectos/ubuntu-permanente/docs/REFUTADO.md` + `LECCIONES.md`: grep 14-oct-2026
  (`BLOCK_DMA|DMA_DONE|BTA|HS_TX`) → **sin entradas**: este camino no está refutado ni probado.

## 2. Estado real del asunto (evidencia)

### 2.1 El camino exacto de `cmd#0` en mainline (fichero:línea)

`cmd#0` = `ff 27` (select page 0x27), DCS short-write 1 param, len 2
(`docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md` §2; log `UKE-K47c: cmd#0 off=0 dt=39`):

```
panel o82_send_panel_cmds (:208) ──log K47c (:218)
 └─ mipi_dsi_dual_dcs_write_buffer_multi (:236-238)
     ├─ dsi0: mipi_dsi_dcs_write_buffer (drm_mipi_dsi.c:1026-1027)
     └─ dsi1: mipi_dsi_dcs_write_buffer (drm_mipi_dsi.c:1028-1029)
         └─ msg {tx, SIN rx_buf/rx_len} type=DCS_SHORT_WRITE_PARAM (drm_mipi_dsi.c:926-942)
             └─ dsi_host_transfer ×2, uno por link (dsi_host.c:1767) ──log K47-host-xfer (:1770)
                 └─ msm_dsi_manager_cmd_xfer(id, msg) (dsi_manager.c:493)
                     ├─ is_read=false (:498); need_sync=true (DT sync-dual-dsi + !is_read, :499)
                     ├─ id==DSI_0 → return tx_len SIN transmitir (:510-511)   ← "la mitad" del dual
                     └─ id==DSI_1: xfer_prepare(host0) (:514) + xfer_prepare(host1) (:521)
                         ├─ xfer_prepare (dsi_host.c:2159): link_clk_set_rate+enable (:2176-2177),
                         │   CTRL|=CMD_MODE_EN|ENABLE (:2185-2188), IRQ CMD_DMA_DONE on (:2189)
                         ├─ msm_dsi_host_cmd_tx (:2212) → dsi_cmds2buf_tx (:1523)
                         │   ├─ dsi_cmd_dma_add (:1530; formato MSM :1351-1367)
                         │   └─ dsi_cmd_dma_tx (:1553 → :1440)
                         │       ├─ reinit dma_comp (:1453)
                         │       ├─ dsi_wait4video_eng_busy (:1455) → [L33: espera VIDEO_DONE 70 ms
                         │       │   (:1206-1207) → "wait for video done timed out" (:1210);
                         │       │   L36+: early-return, espera anulada]
                         │       ├─ TRIGGER ambos links (:1457 → dsi_manager.c:539-554:
                         │       │   commit DSI_0 (:549) + commit propio (:551) → true)
                         │       │   commit = DMA_BASE (:2363) + DMA_LEN (:2364) + TRIG_DMA=1 (:2365)
                         │       └─ wait dma_comp 200 ms (:1460-1461) → 0 ⇒ -ETIMEDOUT (:1463-1464)
                         └─ xfer_restore (:530 → :2194): IRQ off, restore CTRL, clk_disable
```

Completions (únicas dos salidas del wait): `CMD_DMA_DONE` → `complete(dma_comp)`
(`dsi_host_irq:1704-1705`); `VIDEO_DONE` → `complete(video_comp)` (`:1701-1702`).
Retorno de error: `dsi_cmds2buf_tx:1555-1556` (`cmd dma tx failed`) → `dev_err
"sending dcs data failed"` (`drm_mipi_dsi.c:1003`) → `accum_err` → `o82_send_panel_cmds:246-247`
aborta la secuencia de 108.

### 2.2 Qué condición exacta produce FIFO y TIMEOUT (leído, no inferido)

- **FIFO** (`dsi_fifo_status`, `dsi_host.c:1626-1640`): **cualquier** bit ≠0 en
  `REG_DSI_FIFO_STATUS` (0x08) pone `DSI_ERR_STATE_FIFO` (0x4, `:1635`). El log `status=4`
  es este agregado de software — **el valor crudo del registro no se imprime en ningún sitio**.
  Solo el bit `CMD_MDP_FIFO_UNDERFLOW` (0x80) añade acción (`sw_reset`, `:1636-1638` +
  `dsi_err_worker:1574-1575`); el resto solo se anota y se sigue (`:1578-1581`).
- **TIMEOUT** (`dsi_timeout_status`, `:1598-1608`): **cualquier** bit ≠0 en
  `REG_DSI_TIMEOUT_STATUS` (0xbc) pone `DSI_ERR_STATE_TIMEOUT` (0x1, `:1606`).
  `status=5` = FIFO+TIMEOUT a la vez. **Mainline no define ni un solo nombre de bit de este
  registro** (generada `:515`: solo la dirección) y el valor crudo tampoco se imprime.
- **Config de timeouts**: `LP_TIMER_CTRL`/`HS_TIMER_CTRL` jamás programados por mainline
  (§1, grep) ⇒ corren a valor de reset. El vendor programa `HS_TIMER_CTRL=0x4BB80`
  (ENABLE-COMPARISON fila 5, `.ko:0x12d8e8`) y limpia `TIMEOUT←0x11111111` antes de armar
  errores (§H4); mainline arma `ERROR` en `dsi_ctrl_enable:897` sin haber limpiado jamás
  ningún status (único W1C: dentro del propio handler).

### 2.3 La pregunta del BTA: el timeout es de escritura, no de respuesta (evidencia)

1. `cmd#0` (y los 108 del init) son **writes sin rx** (`drm_mipi_dsi.c:926-930`: el msg no
   lleva `rx_buf/rx_len`; `dsi_manager.c:498`: `is_read=false`). En el camino de write no
   existe ningún trigger BTA en mainline (cero refs a BTA en `dsi_host.c`; solo el bit
   `BTA_DONE` del xml) ni el vendor espera respuesta: su criterio por comando es
   `DMA_DONE` 300 ms (ENABLE-COMPARISON §1/§H8) y el blob no contiene reads (`dt=0x06`
   ausente, PROFUNDO §2).
2. Discriminante físico: **si el panel no escuchara**, el host transmitiría al vacío y
   `CMD_DMA_DONE` llegaría igual → transferencia OK, cero errores, los 108 "con éxito";
   el fallo sería invisible hasta más tarde (sin imagen/TE). **Lo observado es lo contrario**:
   `CMD_DMA_DONE` no llega en 200 ms (L36+), `VIDEO_DONE` no llega en 70 ms (L33),
   más bits FIFO+TIMEOUT pegados. **El paquete no salió del host: el stall es del lado
   escritura del host, no del panel.** (HIPÓTESIS la frase anterior en lo que asigna causa;
   los hechos citados son medidos.)
3. Corolario: `BTA_TO`/`LP_RX_TO` **no pueden** dispararse por `cmd#0` (no hay read ni BTA);
   si el valor crudo de `TIMEOUT_STATUS` los contuviera, serían colaterales/espurios — por
   eso el experimento E1 imprime el crudo en vez de adivinarlo.

### 2.4 Diferencias vendor confirmadas en este camino (una por línea, con fuente)

| # | Vendor (Android/`.ko`) | Mainline (vivo) | Efecto en `cmd#0` |
|---|---|---|---|
| V1 | 108 DCS con motor de vídeo **OFF**; `vid_engine_enable` al final (ENABLE-COMPARISON §1, `.ko:0x1473a0`) | `VID_MODE_EN` puesto en `host_enable:2436-2437` **antes** de los DCS; **cada** DCS espera a vídeo (`dsi_cmd_dma_tx:1455`) | L33 muere en esa espera (70 ms) aunque el DCS esté bien encolado |
| V2 | Espera por comando = `DMA_DONE` 300 ms (`.ko:0x136d5c`), sin espera de vídeo | Espera = vídeo (70 ms) + DMA (200 ms) encadenadas | Doble termómetro; L36 quemó el 1º (early-return) y el fallo se movió al 2º |
| V3 | `DMA_FIFO_CTRL\|=0x110000` por kickoff + `VBIF_CTRL\|=7` (ENABLE-COMPARISON fila 16) | Nada de lo primero; sin VBIF | Watermarks del FIFO de CMD-DMA activos (sospechoso menor) |
| V4 | Clear-before-unmask de los 6 status + limpieza PHY-err pre-ULPS-exit (filas 19, §H4) | Sin limpieza previa; solo W1C post-IRQ (`:1588-1665`) | Ráfaga `status=4` en `host-en` compatible con bits heredados/nivel (§H4) |
| V5 | `HS_TIMER_CTRL=0x4BB80`, `TIMING_FLUSH=1`, `TIMING_DB_MODE=0` (filas 3,5,7) | Ninguno existe en mainline | Motor de vídeo con timing en sombra → mismo DONE-perdido (dueño: informe ENABLE-COMPARISON H1) |
| V6 | `sw_reset` restaura CTRL **sin** `VID_MODE_EN` (fila 11) | `dsi_sw_reset:1152-1155` restaura CTRL íntegro (re-arme de vídeo) | Re-modesets arrancan sobre motor tocado (dueño: H5) |

### 2.5 Lectura honesta de "corta en `host-xfer`" (L40) / "corta en `cmd#0`" (L42)

`K47-host-xfer` es lo **primero** de `dsi_host_transfer` (`:1770-1778`); que sea la última
línea admite dos lecturas y ACM-lossy impide dirimir (doctrina del auditor):
(a) wedge duro dentro del xfer (p.ej. MMIO contra dominio parado —cuMeter: sin prueba—), o
(b) el error sí se imprimió (`cmd dma tx failed` + `sending dcs data failed`) y la cola se
perdió en el reset. Lo que **sí** es señal aunque se pierda cola: `status=5` (TIMEOUT se
suma al FIFO solo en L40/L42, nunca en L33) y `video done`=0 (coherente con el early-return
L36, no con salud del vídeo). El `cmd#0 ×5` son reintentos del modeset/sddm, no del DCS:
el driver aborta al primer `accum_err` (`panel:246-247`) — cada `cmd#0` nuevo es un intento
nuevo de enable, no el mismo comando reintentado.

## 3. Cambio propuesto (diff exacto, con fichero:línea)

**Solo instrumentación de arranque** (`docs/historia/revision/PIPELINE-PANEL-20261014/s4-instrumentacion.diff`, `patch -p1` desde la raíz
del árbol). Cinco `pr_err` (nivel 3: visibles sin `dmesg -n 7`, eluden la trampa E2 del
auditor) en puntos que **ya leen esos registros hoy** (mismo contexto IRQ/workqueue;
cero volcados de rangos, cero SMMU/regmap — regla 3 del método):

1. `dsi_fifo_status` (`dsi_host.c:1626`): imprime `id` + valor crudo de `FIFO_STATUS`.
2. `dsi_timeout_status` (`dsi_host.c:1598`): imprime `id` + valor crudo de `TIMEOUT_STATUS`.
3. `dsi_err_worker` (`dsi_host.c:1573`): añade `id` al `status=` (hoy no se sabe qué link habla
   en dual-DSI; el ráfaga ×8/×10 queda sin atribuir).
4. `dsi_cmd_dma_tx` (`dsi_host.c:1460-1466`): en timeout de `dma_comp`, imprime
   `id/len/STATUS0/FIFO/TIMEOUT` (foto del stall en el instante del fallo).
5. `dsi_wait4video_done` (`dsi_host.c:1209-1210`): en timeout, añade `STATUS0` (bit
   `VIDEO_MODE_ENGINE_BUSY`) + `FIFO` (distingue "motor parado" de "motor colgado").

Sin cambios funcionales: ni máscaras, ni orden, ni timings. Riesgo ~0 (solo formateo en
paths de error ya existentes + una lectura extra de `STATUS0` en un timeout ya declarado).

## 4. Criterio pasa/falla prefijado

Tras flashear el kernel instrumentado (un ciclo, display encendido), leer por SSH
(solo lectura) o ACM el primer intento de enable. **Pasa** (el diff cumplió: la próxima
hipótesis queda decidida por tabla, sin adivinar):

| Valor crudo observado | Decisión |
|---|---|
| `TIMEOUT_STATUS` con solo bit(s) de TX (típ. HS_TX_TO) + `FIFO` con underflows HS | H-S4-1 confirmada (stall de escritura) → ciclo funcional: quitar `BLOCK_DMA_WITHIN_FRAME` o `VID_MODE_EN`-antes-de-DCS |
| `TIMEOUT_STATUS = 0` pese a `status=5` previo / o bits BTA/LP_RX en un write | H-S4-2 (stale/nivel heredado) → ciclo funcional: clear-before-unmask (dueño: ENABLE-COMPARISON H4/ciclo 2) |
| `STATUS0` sin `VIDEO_MODE_ENGINE_BUSY` en el timeout de vídeo | Motor parado, no colgado → H-S4-3 (timing en sombra, dueño H1) manda |
| `CMD_DMA_DONE` llega y `cmd#0` avanza (siguen `cmd#1…`) | El host transmite: el modelo "panel no escucha" vuelve a la mesa (S3/vci) |
| `dma_comp` expira pero SÍ hay prints de error después | "Corta en host-xfer" era ACM-lossy (b), no wedge (a) |

**Falla** (revertir): ningún print nuevo aparece (el enable no llega al xfer) o el boot no
llega a userspace por causa ajena al display (verificar con `video=DSI-1:d` de control).

## 5. Hipótesis ranqueadas y refutaciones que aplican

- **H-S4-1 (HIPÓTESIS, primera): el trigger CMD-DMA queda retenido por el motor de vídeo
  muerto.** `dsi_ctrl_enable:874-876` arma `TRIG_CTRL.BLOCK_DMA_WITHIN_FRAME` ("el HW espera
  a que el cmd-mdp esté idle", comentario `dsi_host.c:2165-2169`) y `host_enable:2436-2437`
  enciende `VID_MODE_EN` antes de los DCS. Con el motor de vídeo stalled (timing en sombra,
  dueño H1), el HW no abre ventana al CMD-DMA → `CMD_DMA_DONE` jamás llega → 200 ms →
  `-ETIMEDOUT`, más FIFO/TIMEOUT de nivel por el motor parado. El vendor no puede sufrirlo:
  sus DCS corren con vídeo OFF (V1). Experimento discriminante: E1 (arriba); funcional (un
  ciclo posterior, dueño S5/orquestador): una sola línea — no poner `BLOCK_DMA_WITHIN_FRAME`
  en modo vídeo, o mover `VID_MODE_EN` tras los DCS.
- **H-S4-2 (HIPÓTESIS, segunda): bits pegajosos/de nivel heredados.** Sin clear-before-unmask
  (V4), el ráfaga en `host-en` puede ser cosmética del reporte mientras el DONE se pierde por
  otra causa. La disocia E1: si el crudo es estable y de nivel con motor corriendo, es live;
  si es 0 o BTA/LP_RX en un write, es stale. (Dueño: ENABLE-COMPARISON H4.)
- **H-S4-3 (HIPÓTESIS, tercera, compartida): el motor de vídeo nace muerto por timing en
  sombra** (`TIMING_FLUSH`/`HS_TIMER`/`DB_MODE`, V5). Dueño: informe ENABLE-COMPARISON H1 y
  sus ciclos 1a–1c — **no duplicar aquí**; E1 la confirma o la descarta vía `STATUS0`.
- **No repetir**: G4 (lane map, refutado con control L40/L42), G7 (SSC, refutado con control),
  G5/G6 (inertes en paquete) — `docs/historia/ESTADO-VIVO.md` §20:0x. G1 (VBIF) es causa de muerte a ~4 s,
  no de este stall a ~10/207 s. Refutado del hermano: sin entradas sobre este camino (§1).

## 6. Qué NO hacer / lo que queda fuera

- No tocar `LP_TIMER_CTRL`/`HS_TIMER_CTRL` en este ciclo (semántica de reset del valor 0 no
  verificada en fuente primaria; programar `0x4BB80` es el ciclo 1b del informe
  ENABLE-COMPARISON, no este).
- No cambiar `ERR_INT_MASK0`, ni orden de enables, ni `BLOCK_DMA_WITHIN_FRAME`, ni
  `sw_reset`: son ciclos funcionales de otros dueños (S2/S5/orquestador) con "un cambio por
  ciclo".
- No instrumentar en runtime ni volcar rangos MMIO/regmap (regla 3 del método); no leer
  `/dev/ttyACM0` (regla 1 del pipeline); no decodificar bits de `TIMEOUT_STATUS` "de memoria":
  hasta E1, el crudo manda.
- Fuera de alcance: vci (S1), G8 (S2), reset TDDI (S3), porte L39 (S5), minucias DT (S6).
