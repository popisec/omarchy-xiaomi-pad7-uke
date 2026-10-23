# REVIEW-S6 — Revisión adversarial de S6-MINUCIAS-DT + s6-*.diff (14-oct-2026)

> Revisor adversarial, solo lectura. Nada modificado en árboles ni entregas.
> Método: re-leídas todas las citas contra fuentes primarias; ambos diffs
> aplicados en copias bajo `/tmp/opencode/` (s6t/s6r/s6v/s6f/s6rv); SSH
> intentado (timeout, confirma S6 §2.5). Veredicto: **OK-con-notas**.

## 1. NON_CONTINUOUS — citas OK, mecánica OK, justificación a matizar

- Flag presente en `panel-xiaomi-o82-dualdsi.c:595-596` (`MIPI_DSI_MODE_VIDEO |
  MIPI_DSI_MODE_LPM | MIPI_DSI_CLOCK_NON_CONTINUOUS`), con el comentario K48-A
  contradicho por el código (verificado por lectura directa). Cita correcta.
- Efecto mecánico verificado: `dsi_host.c:909` (`if (!(flags &
  MIPI_DSI_CLOCK_NON_CONTINUOUS))`, bloque hasta `:917`) salta
  `LANE_CTRL |= CLKLN_HS_FORCE_REQUEST` + `msm_dsi_phy_set_continuous_clock`
  con el flag. (Nota cosmética: S6 cita `:909-917` y en otro sitio `:909-916`;
  el bloque real es 909–917.) Correcto.
- Vendor verificado línea a línea en `stock_uke.dts`: `lp11-init` `:13250`,
  `traffic-mode="non_burst_sync_event"` `:13253`, `off/on-command-state`
  `:13293-13294`, `clockrate` `:13296`, DSC `:13283-13291`, porches
  `:13301-13313`, `reset-sequence` `:13242`, `bl_ctrl_external` `:13204`,
  `bl-update-flag="delay_until_first_frame"` `:13223`, `rx/tx-eot`
  `:13226-13227`, `display-topology 2 2 2` `:13265`,
  `broadcast`/`cmd-sync-wait` `:13224-13225`. Todas las citas de S6 son exactas.
- LPM se queda: justificación correcta (vendor LP-cmd ⇔ mainline LPM).
  `VIDEO_BURST` no se añade: correcto (vendor non-burst; driver sin BURST —
  `grep BURST` vacío en el driver; sheng es otro panel). EOT: no tocar, correcto.
- Herencia `dsi1 ← desc` en `:763-765` (doc dice `:764-765`; el `mode_flags`
  está en `:765`). Correcto, cubre ambos links.
- Prior-art `l37-continuous-clock.diff`: existe, base `k52L33-tree`,
  nunca aplicado (flag sigue en L16). El rebase de contenido es fiel. Correcto.
- H3 = ciclo 4 de ENABLE-COMPARISON: existe (`:143` H3, `:241` ciclo 4). Correcto.

**NOTA-1 (matiz que el orquestador debe conocer, no bloquea):** el argumento
"el flag contradice el contrato vendor" es **medio contrato**. El vendor hace
**LP11 durante el reset** (`lp11-init` + comentario K48-A: "LP11 durante toda
la secuencia de reset") **y** clock HS continuo **durante TX** (callback
`_dsi_display_continuous_clk_ctrl`). Mainline no puede expresar ambas fases:
con el flag se fideliza la fase-reset (clock no forzado) pero se pierde la
fase-TX (clock no-continuo por paquete); sin el flag se fideliza la fase-TX
pero se fuerza HS desde `power_on`, antes de rieles/reset (lo que el vendor
explícitamente no hace). Quitar el flag es la apuesta correcta **para el
síntoma actual** (muerte en el primer DCS = fase-TX), y el criterio pasa/falla
direccional de S6 §4 es el adecuado. Pero si H3 **falla con firma idéntica**,
la lectura no es solo "H3 refutada": también sugiere que la fase-reset (LP11)
podría importar, y eso apuntaría al reorden (huérfano, ver §6). Dejar
constancia en el ledger al ejecutar H3.

## 2. Fantasma `byte_cly` — cierre sin diff CORRECTO, con alcance verificado

- `byte_cly` aparece solo en `docs/historia/revision/PIPELINE-PANEL-20261014/BRIEF.md:66` (el propio encargo) y en la
  discusión de S6. Ausente en: `build/gates/`, `k52-L16-tree/drivers/`,
  `k52L39-fuentes/fase4-display.dts`, `panel-xiaomi-o82-dualdsi.c`,
  `stock_uke.dts` (grep directo, cero hits).
- Lo real detrás del item verificado: `clock-names` difieren por diseño
  (vendor `byte_clk,…` para binding `sde-kms`; overlay `byte,byte_intf,…`
  que es lo que pide el driver: `dsi_host.c:272` `byte_intf`, `:331` `byte`,
  `:337` `pixel`, `:2055` OPP `byte`). Correcto, no tocar.

**NOTA-2 (honestidad de cobertura):** el `grep` repo-completo de S6 no es
reproducible aquí (timeout: el árbol es demasiado grande para un barrido
exhaustivo en el presupuesto). Mi verificación cubre **todos los lugares con
impacto en build/boot** (driver, overlay, DTBO stock, `build/gates/`). Si el
typo existiera en algún doc no barrido, su impacto en compilación/flash es
cero. Cierre sin diff confirmado.

## 3. KTZ duplicado — citas OK, diff correcto, riesgo residual cubierto

- Cadena de evidencia verificada: `stock2:14016` se0=`i2c@a80000`, `:14562`
  se12=`i2c@890000`; `stock2:442` `aliases i2c2 → …/i2c@a80000`; ledger
  confirma bind `2-0011` + `UKE-L45`=1 (L44). Luego chip físico en se0 ⇒
  bueno = `ktz_bl_0` (fragment@7), fantasma = `ktz_bl_1` (fragment@8). Correcto.
- Stock: frag@105/106 con `ktz8866@11` de solo `reg/status/compatible`
  (`:13793-13819`) y targets `<0xffffffff>` resueltos por símbolos
  (`:3700` →se0, `:3789` incluye frag@106→se12). "El duplicado viene del
  stock" — correcto.
- Nadie referencia `ktz_bl_1`: único uso en `fase4-display.dts:550`
  (definición) + `:564` ata `ktz_bl_0`; resto de menciones son el histórico
  `build/gates/FRAGMENTO-KTZ8866.dts:56` (no compilado al s286) y docs.
  El diff elimina exactamente fragment@8 y retoca el comentario. Correcto.
- Probe con I/O verificado: `ktz8866.c` llama `backlight_update_status()` al
  final del probe (rango `:540-551`), luego el fantasma sí genera NACKs/ruido.
  "Higiene, no diagnóstico" — honesto y correcto.
- Post-apply en copia: `ktz_bl_1|fragment@8` queda 1 mención = el comentario.
  Hueco de numeración (7,9): legal en overlays, sin renumerar — correcto.
- SSH caído (timeout 10 s, 14-oct noche): pendientes `of_node` de `2-0011` y
  `fdtoverlay` en verde pre-flash (el doc ya lo exige en §4). Sin SSH no hay
  regresión posible hoy; el rollback es el s286 intacto.

## 4. DSC/timings — spot-check completo, cero divergencias confirmado

- Vendor: slice `0x320×0x18` = 800×24, 1/pkt, bpp 8, bpc 0x0a=10, block-pred,
  versión `0x11`=1.1, scr 0; link-120 `0x640×0x858`=1600×2136, hfp `0x71`=113,
  hbp/hpw `0x10`=16, vfp `0x1a`=26, vbp `0x92`=146, vpw 2,
  clockrate `0x46e19970`=1189190000. Todo coincide con la tabla S6.
- Mainline: `slice 800×24, count 2, bpc 10, bpp 8<<4, block_pred` ✓;
  modo-120 `(3200+226+32+32)×(2136+26+146+2)` = full duplicado con
  226/32/32 + 26/146/2 ✓; 144: hfp 36=18×2 ✓ (vendor timing@144 `0x12`=18);
  90: hfp 608=304×2 ✓ (vendor timing@90 `0x130`=304); `num_modes=1` en `:583` ✓
  (conservador y correcto: el prepare escribe siempre b3/b2 de 120 Hz).
- Dual-DSI overlay `:320-324` (`dual-dsi-mode` + `sync-dual-dsi`) ✓.
- `panel-clockrate` clasificado como R1/G5/G6/S5, fuera de S6 — correcto
  (BRIEF excluye G5/G6; S5 lo porta).

## 5. Aplicación limpia y disjunción — VERIFICADO en copias

- `docs/historia/revision/PIPELINE-PANEL-20261014/s6-noncontinuous.diff` (base `k52-L16-tree`, `-p1`): dry-run **OK** en copia
  con estructura de árbol; post-apply el flag desaparece del código y solo
  quedan 2 menciones en comentarios del propio hunk (coincide con S6 §4).
- `docs/historia/revision/PIPELINE-PANEL-20261014/s6-ktz-undup.diff` (base raíz repo, `-p1`): dry-run y apply **OK**.
- Secuencial driver (base árbol): s3→s5a→s6 **OK** los tres.
  Secuencial dts (base repo): s6→s1 y s1→s6 **OK** (con offset −14 esperado).
  s2→s4 en `dsi_host.c` **OK**.
- Disjunción por fichero/línea: panel-driver s1(@@52,294,319) / s3(@@261,279,
  350,403,447,637) / s5a(@@29,360) / s6(@@588) — disjuntos (el más estrecho:
  s1@@294 vs s3@@279, separados por 1 línea de contexto; la prueba
  secuencial lo confirma). `dsi_host.c`: s2(@@33,1145) vs s4(@@1206,1460,
  1570,1604,1619) — disjuntos. s6 no toca `dsi_host.c`.

**NOTA-3 (procedimiento, no defecto de S6):** las bases difieren por diff y
S6 declara las suyas correctamente, pero que conste para el orquestador:
`docs/historia/revision/PIPELINE-PANEL-20261014/s1-vci.diff` mezcla en un solo fichero hunks base-repo (`build/gates/…`) y
hunks base-árbol (`build/kernel-pokes/k52-L16-tree/…`) ⇒ s1 solo aplica desde
la raíz del repo; s2/s3/s4/s5a/s6-noncontinuous aplican desde
`build/kernel-pokes/k52-L16-tree`; s6-ktz-undup desde la raíz. No mezclar
órdenes de aplicación sin respetar la base de cada diff.

## 6. Pregunta clave: el reorden ENABLE/VID/DCS — S6 difiere bien, pero el dueño parcial está en disputa

Mapeo verificado de quién dice qué:

- (a) `prepare_prev_first=true` (`:726` verificado): el panel corre
  rails→reset→DCS **antes** del `pre_enable` del host; el vendor hace
  host_init×2 → rails+reset → LINK_CLK → ENABLE → … → DCS → VID al final.
- (b) `VID_MODE_EN` antes de los DCS (`host_enable:2436-2437`,
  `dsi_op_mode_config:1221+1226` según S6 §6.1; S4:139 lo documenta como V1
  con espera por comando en cada DCS).

Propiedad declarada por sección:

| Sub-item | S2 dice | S3 dice | S4 dice | ¿Hunk en el pipeline? |
|---|---|---|---|---|
| (a) orden del prepare | "solapa con S3" (S2:125) / lo difiere (S2:197-198) | "Estructural = S2, no S3" (S3:37); lo asigna a S2 (S3:55) y lo excluye (S3:77) | — | **NO, huérfano: S2→S3→S2** |
| (b) VID-antes-de-DCS | S4 (S2:193-198, H5-5a/5b) | — | lo analiza (S4:139,185,199-204) pero S4 solo entrega instrumentación | dueño analítico S4, **sin hunk de fix** |
| backlight-en-enable | — | lo asigna a S6 (S3:55) | — | cerrado por S6 §6.2 con evidencia (`:745-758` verificado: `drm_panel_of_backlight` en `:745`) ✓ |

Conclusión: S6 hace lo correcto al no producir ese hunk (rediseño del
secuenciado, violaría un-cambio-por-ciclo y su propio alcance). Pero su
formulación "propiedad de S3 (dónde corre el prepare) + S4" adopta la
asignación de S2, que **S3 rechaza explícitamente**. El sub-item (a) queda
**huérfano sin dueño implementador** salvo que el orquestador lo asigne
(rebote S2↔S3 documentado arriba). El sub-item (b) tiene dueño analítico
(S4) pero ningún diff de fix en este pipeline. Recomendación: el orquestador
asigna (a) explícitamente antes del ciclo (candidatos: S3, que ya toca el
probe en `:640-654`, al menor coste marginal — aunque S3 lo rehusó — o un
hunk propio de S2); (b) queda como hipótesis H-S4 post-instrumentación.

## 7. Incidencias para el orquestador (heredadas/confirmadas)

- SSH caído (timeout 14-oct noche; BRIEF decía "viva por SSH" — premisa
  caducada; MANANA contaba con carga nocturna/ACM). Sin SSH: ni `of_node`,
  ni `clock-names` fusionados, ni `clk_summary` (R1). El ciclo de mañana
  empieza por restablecer acceso.
- Batería 3682 mV (MANANA:8) < gate 3700 — re-medir antes de flashear.
- REFUTADO/LECCIONES: `grep -c` = 0/0 para `NON_CONTINUOUS|lp11|ktz|mode_flags`
  (verificado). Sin colisiones.

## Veredicto: **OK-con-notas**

Los dos diffs son correctos, mínimos, aplican limpio y son disjuntos del
resto del pipeline; los tres cierres sin diff están justificados con
evidencia. Las notas NOTA-1 (medio-contrato LP11/continuo), NOTA-2 (cobertura
del grep), NOTA-3 (bases de aplicación) y §6 (reorden (a) huérfano S2↔S3)
deben acompañar la entrega al ciclo de mañana, no bloquean su aceptación.
