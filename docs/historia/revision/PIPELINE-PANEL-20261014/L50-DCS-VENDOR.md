# L50 — Primer DCS: vendor vs nuestro + ranking para muerte silenciosa (14-oct-2026)

> Solo lectura. Árbol: `build/kernel-pokes/k52-L16-tree` (ignorado por git). Captura:
> `out/CAPTURA-MUERTE-netconsole.log`. Hipótesis marcadas como tales.

## 0. Hechos medidos hoy (no hipótesis)

- Cola de muerte: `K47-pre-init` → `UKE-K47c: cmd#0 off=0 dt=39` → `K47-host-xfer` → silencio.
  `grep -c`: `K47-host-xfer`=1, `cmd#0`=1. Todo lo anterior PASÓ (`L49-phy-ok`,
  `host-vreg/clk/ctrl-ok` ×2, `pwron-ok`, reset del panel).
- La imagen flasheada LLEVA S4-DIAG (medido: `gunzip` del kernel de
  `build/bootimg/boot-uke-k52L49.img` → `S4-DIAG`×4, `K47-host-xfer`×1, `UKE-K47c`×1).
  Sin ningún print S4-DIAG (timeouts de 70/200 ms) ⇒ **wedge síncrono <70 ms tras el
  poke**, no espera agotada. Cautela: netconsole pierde la ventana final (~300 µs sin Gate B).
- `cmd#0` = `ff 27` (page-select), dt=0x39, len=2 — byte-idéntico al vendor (PROFUNDO §2).

## 1. Estado del backlog S4

- S4 = `docs/historia/revision/PIPELINE-PANEL-20261014/S4-DCS-HOST.md` (análisis) + `docs/historia/revision/PIPELINE-PANEL-20261014/s4-instrumentacion.diff` (5 `pr_err`, 0 funcional);
  `docs/historia/revision/PIPELINE-PANEL-20261014/REVIEW-S4.md`: OK-con-notas. Hipótesis: H-S4-1 (trigger retenido por vídeo muerto +
  `BLOCK_DMA`) > H-S4-2 (bits stale) > H-S4-3 (timing en sombra, dueño ENABLE-COMPARISON H1).
- Novedad L50: H-S4-1 en forma "timeout gracioso" (-ETIMEDOUT a 200 ms, como L33/L40/L42
  con máquina viva) **no encaja** con L50 — aquí no hay timeout, hay wedge <70 ms. El S4
  cumplió como termómetro. Fix funcional huérfano: reorden (b) VID-tras-DCS, "sin hunk en
  ningún diff" (REVISION-CADENA-20261014 §2).

## 2. Primer DCS: vendor (Android, maneja este panel) vs nuestro

- **(a) LP vs HS — DIFERENCIA REAL.** Vendor: 108 DCS en LP (`on-command-state="dsi_lp_mode"`,
  PROFUNDO §2). Nuestro: `mipi_dsi_dcs_write_buffer` (`drm_mipi_dsi.c:923-951`) no pone flags;
  `MIPI_DSI_MSG_USE_LPM` no aparece en panel ni DSI (solo 2 checks en `dsi_host.c:2202/2224`)
  ⇒ `xfer_prepare` ejecuta `dsi_set_tx_power_mode(0)` = **HS**. Agravante: `NON_CONTINUOUS`
  sigue puesto (`o82:623-624`) ⇒ `dsi_ctrl_enable` salta el force-HS del clock lane.
- **(b) Estado del host — DIFERENCIA REAL (V1).** Al DCS: timing programado + `sw_reset` +
  `ctrl_enable` (orden en `msm_dsi_host_power_on`, `dsi_host.c`) + `host_enable` con
  `VID_MODE_EN` (`msm_dsi_host_enable` → `dsi_op_mode_config(VIDEO)`) ×2 links **antes** del
  panel (captura: `host-en`×2 → `pan-prep`). Vendor: DCS con vídeo OFF, `vid_engine_enable`
  al final (`.ko:0x1473a0`); cada DCS nuestro además pasa por `dsi_wait4video_eng_busy`.
  Lanes: PHY OK (`L49-phy-ok`) pero sin garantía LP11 (`prepare_prev_first=true`, `:770`).
- **(c) FIFO vs DMA — NO HAY DIFERENCIA.** Ambos usan cmd-DMA (vendor `kickoff` + `DMA_DONE`
  300 ms, ENABLE-COMPARISON fila 17; nuestro `msm_dsi_host_cmd_xfer_commit`: DMA_BASE/LEN/TRIG).
  Vía SMMU/IOVA: otro subagente, no duplico.
- **(d) Broadcast dual — verificado.** `mipi_dsi_dual_dcs_write_buffer_multi`
  (`drm_mipi_dsi.c:1021-1030`) llama dsi[0] (=primario DSI_0, probe `:767`) → manager
  (`dsi_manager.c:493-511`) early-return éxito **sin transmitir ni pokear** → luego dsi[1] →
  DSI_1 hace todo (prepare h0+h1, `cmd_tx`, trigger ambos, wait `dma_comp` propia).
  DT: `sync-dual-dsi` en ambos links (`elish-common.dtsi:608-609/658-659`). **1 poke = caso
  sync; la muerte está dentro del path DSI_1** (prepare/dma/trigger/wait, <70 ms).

## 3. Ranking por "wedge silencioso sub-segundo del SoC (PMIC, sin traza)"

| # | Diferencia | Por qué puede matar en silencio | Fuerza |
|---|---|---|---|
| R1 | Re-voto link-clocks en `xfer_prepare` (`set_rate+enable` **por transferencia**; primer re-vote del boot contra SRCs con padre=PLL — F1 de L49-PREP) | Glitch ⇒ colapso árbol display ⇒ el siguiente MMIO cuelga la CPU sin traza | Fuerte |
| R2 | Trigger dual con `BLOCK_DMA_WITHIN_FRAME` + motor vídeo stalled (sin FLUSH/HS_TIMER/DB_MODE) | Si el interlock cuelga el esclavo AHB en vez de retener, todo MMIO posterior muere; L33-L42 mostraban la variante graciosa | Media |
| R3 | Primer burst en HS con clock lane sin forzar + sin ULPS-exit (vendor: todo LP) | Normalmente daría `HS_TX_TO` gracioso; solo contención eléctrica explicaría silencio | Media-baja |
| R4 | Commit dual (writes a DSI_0 desde contexto DSI_1) | Ambos hosts powered; paridad con el bcast vendor | Baja |
| R5 | Panel (bytes = vendor; rails/reset OK) | Un write DCS no puede resetear el PMIC del SoC | Nula (descartado) |

No explican silencio: `-ETIMEDOUT`/`accum_err` (graciosos), BTA (cero reads en init),
ESD/TE (armados tras unblank, ANDROID-CADENA §3.4).

## 4. Fixes candidatos (una variable por ciclo; nada de SMMU/IOVA)

- **F-b (primero): VID-tras-DCS** — no poner `VID_MODE_EN` en `host_enable`; encender vídeo
  tras el prepare. Saca `wait4video` + interlock de la ventana DCS (orden vendor).
- **F-c (alternativo a F-b, no junto): quitar `BLOCK_DMA_WITHIN_FRAME`** (1 línea en
  `dsi_ctrl_enable`) — trigger sin gate de motor stalled.
- **F-a: DCS en LP** — no limpiar `LOW_POWER` en `xfer_prepare` si el modo trae LPM
  (iguala `dsi_lp_mode` del vendor; elimina el primer burst HS).
- **F-e: quitar `NON_CONTINUOUS`** (H3, 1 línea `mode_flags`) — clock continuo para el HS.
- **F-d: ciclos 1a-1c** de ENABLE-COMPARISON (`TIMING_FLUSH`/`HS_TIMER`/`DB_MODE`) — motor vivo.
- **F-f: guarda en `xfer_prepare`** (saltar `set_rate` si el rate ya está vigente) — quita R1
  sin cambiar arquitectura. Orden: F-b/F-c > F-a/F-e > F-d > F-f.

## 5. NO verificado

- Mapeo ctx->dsi[1]↔DSI_1 por construcción del probe (leído, no trazado en vivo).
- Sub-punto dentro del path DSI_1 (prepare vs dma vs trigger): 2 pokes internos o S4-DIAG
  extendido (ACK/PHY/CLK, REVIEW-S4 N4) lo dirimirían — otro ciclo.
- Estado lanes/PHY (¿LP11?) y cotas con JTAG: sin fuente.
- `SPLIT_LINK`/valores VID exactos del vendor: reservas §5 de ENABLE-COMPARISON, no bloquean.
