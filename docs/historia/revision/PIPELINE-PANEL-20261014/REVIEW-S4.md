# REVIEW-S4 — Revisión adversarial de `docs/historia/revision/PIPELINE-PANEL-20261014/S4-DCS-HOST.md` + `docs/historia/revision/PIPELINE-PANEL-20261014/s4-instrumentacion.diff` (14-oct-2026)

**Veredicto: OK-con-notas.** El análisis estático es correcto en lo load-bearing, el diff aplica
limpio y cumple las reglas de método. Ninguna discrepancia exige reescribir la entrega; las 8 notas
de abajo son correcciones/precisiones que el orquestador debe trasladar al ciclo de flash como
instrucciones de lectura, no como bloqueos. No toqué ningún árbol ni entrega: solo lectura +
`patch --dry-run` sobre copia en `/tmp/opencode/s4t2` (exit=0).

## 1. Evidencia re-verificada (todo se sostiene, con 2 citas a precisar)

Releí en `build/kernel-pokes/k52-L16-tree`: `dsi_host.c` entero (líneas clave abajo),
`dsi_manager.c:493-554`, `drm_mipi_dsi.c:920-1035`, `panel-xiaomi-o82-dualdsi.c:208-256`,
DT `sm8250-xiaomi-elish-common.dtsi:608-609,658-659` (dual + sync en ambos links: OK),
generada `build/kernel-pokes/k52L33-build/drivers/gpu/drm/msm/generated/dsi.xml.h`
(existe; la entrega la cita bien como `k52L33-build`), `registers/display/dsi.xml:246-254`.

- Camino `cmd#0`: `o82_send_panel_cmds:208` → log K47c `:218` → dual `:236-238` →
  `mipi_dsi_dcs_write_buffer` (msg sin `rx_buf/rx_len`, verificado `:923-951`) →
  `dsi_host_transfer:1767` (poke K47 `:1770`) → `msm_dsi_manager_cmd_xfer:493` →
  `need_sync` (`:499`, DT sync-dual-dsi) → **DSI_0 retorna sin transmitir `:510-511`,
  literalmente `return is_read ? msg->rx_len : msg->tx_len`** → prepare ×2 → `cmd_tx:2212`
  → `cmds2buf_tx:1523` → `dma_add:1530` → `dma_tx:1553→1440` → `wait4video_eng_busy:1455`
  → trigger ambos links `:1457→manager:539-554` (commit dsi0 `:549` + propio `:551`) →
  wait `dma_comp` 200 ms `:1460-1461` → `-ETIMEDOUT :1463-1464`. **Todo OK.**
- FIFO `:1626-1640` / TIMEOUT `:1598-1608`: cualquier bit ≠0 agrega `0x4`/`0x1`; `status=5` =
  ambos. **Valor crudo no se imprime en ningún sitio** (solo agregado `status=%x` en
  `err_worker:1573`, sin `id`): confirmado. `TIMEOUT_STATUS` sin bitfields en la generada
  (`:515` solo la dirección `0xbc`): confirmado. `LP_TIMER_CTRL`/`HS_TIMER_CTRL` solo en el
  xml; **cero programaciones en `.c`** (grep 14-oct: solo hits en `dsi.xml`): confirmado.
- Completions `:1701-1705`, error path `cmds2buf_tx:1555-1556` → `drm_mipi_dsi.c:1003`
  (variante `_multi`, la que usa el camino dual: cita correcta), `accum_err → panel:246-247`: OK.
- Cero refs a BTA en `dsi_host.c` (grep vacío): confirmado. `is_read=false` en writes: OK.
- Vendor/HALLAZGO: `HALLAZGO-L33-DEATH-20261013.md:40-43` confirma `cmd#0 → host-xfer ×2 →
  wait for video done timed out`; `NOTAS-OMARCHY.md:4200,4256` confirma tabla L40/L42;
  `REFUTADO.md`/`LECCIONES.md` grep `BLOCK_DMA|DMA_DONE|HS_TX` → **0 entradas**: confirmado.

**Precisiones de cita (N1, N2 — menores):**

- **N1.** «`host_enable:2436-2437` enciende `VID_MODE_EN`» es indirecto: `:2436-2437` es la
  llamada a `dsi_op_mode_config`; el bit se pone en `dsi_op_mode_config:1171-1172`. El fondo
  (vídeo ON antes de los DCS) es correcto. Corrección: citar `dsi_host.c:1171-1172 vía :2436`.
- **N2.** El early-return DSI_0 (`:510-511`) devuelve `tx_len` = **éxito**. Consecuencia que la
  entrega no explicita: el link 0 jamás reporta error; solo el camino del link 1 puede abortar
  la secuencia vía `accum_err`. Refuerza (no debilita) el análisis; pedir que conste en la
  lectura del ciclo.

## 2. La tesis fuerte («panel sordo = DMA_DONE igual; lo observado = stall del host»)

**Se sostiene como heurística fuerte, no como certeza lógica.** A favor: en writes sin BTA no
hay trigger de lectura/respuesta en mainline ni espera de respuesta en vendor (criterio
`DMA_DONE` 300 ms); `CMD_DMA_DONE` es IRQ del motor DMA local, independiente del panel. En
contra (contraejemplos que la entrega no lista): un panel/PHY que contiende las líneas LP
podría producir errores observables en escritura (`DLN0_PHY_ERR`, `ACK_ERR`) aunque el DMA
complete; un carril de clock que no entra en HS produciría `HS_TX_TO` sin que el panel tenga
culpa ni el trigger esté retenido. La entrega acota bien lo primero (corolario §2.3: BTA/LP_RX
en un write serían colaterales) pero **el diff no imprime `ACK_ERR_STATUS` / `DLN0_PHY_ERR` /
`CLK_STATUS`** (ver N4). La tabla E1 sigue decidiendo en los 4 casos principales; el hueco es
solo para stalls con firma ACK/PHY/reloj.

## 3. El diff: aplica limpio y cumple método

- `patch -p1 --dry-run` sobre copia: **exit=0**, 5/5 hunks. Símbolos verificados:
  `DSI_STATUS0_VIDEO_MODE_ENGINE_BUSY` (generada `:155`), `REG_DSI_STATUS0/FIFO/TIMEOUT`
  (generada `:151/:160/:515`), `msm_host->id` (struct `:109`), `len`/`dev`/`status` en scope
  en sus hunks. `dsi_host.c` ya usa `pr_err` y `DSI_STATUS0_VIDEO_MODE_ENGINE_BUSY` (`:1229`),
  así que compila por construcción (verificación sintáctica, no build completo: no hay
  toolchain aarch64 invocada; riesgo residual mínimo).
- Método: solo paths de error de arranque, **cero volcados de rangos**, cero SMMU/regmap, cero
  cambios funcionales/máscaras/orden/timings. Los `dsi_read` extra son registros individuales
  ya leídos hoy en esos contextos (clocks activos: dentro del xfer / tras timeout declarado).
  Coste en runtime caliente: nulo en display sano (solo fires en error). **OK.**
- **N3 (nota, no bloqueo).** Los dos `pr_err` nuevos en `dsi_fifo_status`/`dsi_timeout_status`
  no llevan ratelimit (el worker sí lo conserva). Acotado por diseño (el handler desarma
  `ERROR-IRQ` y el worker lo rearma: como mucho un print por ráfaga), aceptable para un ciclo.
- **N4 (recomendación).** Añadir en un ciclo posterior (NO en este: un cambio por ciclo) los
  crudos de `ACK_ERR_STATUS`, `DLN0_PHY_ERR` y `CLK_STATUS`, o justificar su exclusión. Si el
  stall es de reloj/contención, E1-actual subdetermina.
- **N5 (carrera de lectura, importante para interpretar E1).** El snapshot del timeout-DMA
  puede correr DESPUÉS de que el handler de error hiciera W1C-clear de `TIMEOUT_STATUS`:
  `TIMEOUT=0` junto a `status=5` previo no prueba por sí solo «stale en origen»; al leer el
  resultado, **ordenar por timestamp**: valen los prints `S4-DIAG TIMEOUT/FIFO` (origen IRQ)
  por encima del snapshot del momento del timeout. La fila 2 de la tabla debe leerse con esta
  cautela (el dueño H4 sigue siendo el consumidor correcto de ese caso).
- **N6 (aclaración §2.5/§4-fila-3).** `dsi_wait4video_eng_busy:1229` retorna pronto si
  `!BUSY`; luego el print nuevo en `wait4video_done` solo dispara si BUSY se vio al entrar.
  Su `STATUS0` al expirar distingue «BUSY seguía puesto» (motor colgado) de «BUSY se cayó
  durante la espera» (motor que se paró): ambas lecturas son señal, y es justo lo que la
  entrega pide. Sin corrección, solo constancia de que el diseño es correcto también contra
  el árbol vivo (que NO lleva el early-return L36: el primer stall puede darse en la espera
  de vídeo estilo L33; el diff cubre ambas muertes. Bien elegido).
- **N7 (consola).** §6 «no leer `/dev/ttyACM0`» sobrelee la regla 1 del BRIEF («no tocar»);
  conservador e inofensivo, pero el ciclo SIGUE necesitando **un único lector ACM durante el
  arranque** (docs/historia/AGENTS.md: el kernel se bloquea escribiendo sin lector) + **doble captura**
  ACM + `ssh dmesg -w` (E4). Trasladar al orquestador: el criterio pasa/falla debe leerse
  sobre la captura SSH/dmesg, no solo ACM (doctrina lossy).

## 4. Coherencia con auditoría y proyecto hermano

- E4 (capturas lossy): la entrega lo interioriza (§2.5 lecturas (a)/(b), fila 5 de la tabla
  «puede confundir otra vez» → decide wedge vs lossy por presencia de prints). **Coherente.**
- «Modelo del enlace agotado»: la entrega no re-propone configuración del enlace; solo
  instrumenta. **Coherente.** No duplica H1 de ENABLE-COMPARISON (H-S4-3 lo cita como dueño).
- G4/G7/G5/G6/G1: exclusiones correctas y citadas con fuente (`docs/historia/ESTADO-VIVO.md §20:0x`).

## 5. Hipótesis y tabla de decisión

H-S4-1 > H-S4-2 > H-S4-3, cada una con experimento discriminante (E1) y ciclo funcional
posterior con dueño asignado. La tabla decide de verdad SALVO la cautela N5 (fila 2) y el
hueco N4 (firmas ACK/PHY/reloj). La fila 4 («`cmd#0` avanza») es la respuesta a la pregunta
clave: **sí, E1 da señal incluso con panel sordo** (ese es exactamente su veredicto). Y si el
wedge es duro antes de todo print (lectura (a)), la entrega lo declara «Falla» en vez de
inventar señal: honesto.

## 6. Qué falta para cerrar la lógica (tras E1, no ahora)

1. Orden temporal IRQ-prints vs snapshot-DMA (N5) + doble captura obligatoria (N7).
2. Crudos ACK/PHY/CLK o justificación (N4).
3. Si E1 confirma H-S4-1: el ciclo funcional (quitar `BLOCK_DMA_WITHIN_FRAME` o mover
   `VID_MODE_EN`) pertenece a S5/orquestador, con su propio criterio; no apilarlo en este.

**Resumen para el orquestador (≤20 líneas):** veredicto OK-con-notas; camino cmd#0→DMA
verificado línea por línea OK; FIFO/TIMEOUT-agregado y crudo-no-impreso confirmados;
LP/HS_TIMER sin programar confirmado; DSI_0-early-return confirmado (devuelve éxito:
solo link-1 puede abortar — N2); diff aplica limpio (dry-run exit=0) y cumple método
(solo-error-paths, sin rangos/SMMU, coste runtime nulo); tesis fuerte válida como
heurística con contraejemplos de contención/reloj (N-dos); tabla E1 decide de verdad
con dos cautelas: carrera W1C-vs-snapshot en fila 2 (N5) y falta de crudos ACK/PHY/CLK
(N4); citas a precisar host_enable→op_mode_config:1171 (N1); ciclo necesita lector ACM
único + doble captura SSH (N7); nada que rechazar.
