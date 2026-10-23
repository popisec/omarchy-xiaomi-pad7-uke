# CRÍTICA-HIPÓTESIS — estrés adversarial 14-oct-2026 (solo lectura, sin flash)

Alcance: H1–H7 sesión 14-oct (veredicto+hueco+test; `fichero:línea`; ledger en `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`).

## H1 «DDIC activo decodificando negro» → DÉBIL (no verificada)

- Sostiene: luz OK + commits sin underrun + FB con contenido real
  (`CADENA-USERSPACE-DRM.md:26-31`, media R117/G49/B114, 0 negros/200k) + negro estable.
- Debilita: **cero lecturas del panel jamás**. `docs/historia/revision/PIPELINE-PANEL-20261014/S4-DCS-HOST.md:116-131`: ningún trigger
  BTA en mainline, cero reads en el init; `docs/historia/revision/PIPELINE-PANEL-20261014/REVIEW-S4.md:32` lo confirma. Todo «err=0»
  (L62: `UKE-L37…err=0`, `UKE-L62`) es `accum_err` del host — prueba que el host encoló
  bytes, no que el DDIC los aceptara. «Negro, no blanco» es inferencia: panel dormido
  (0x29 no efectivo) o stream parado también dan negro con luz.
- No medido: 0x0A (power mode) / 0x04 (ID) por BTA; si el 0x29 prendió de verdad.
- Test barato: T2 ya propuesto (`CADENA-USERSPACE-DRM.md:47-48`, DPMS 3→0, 0 flashes;
  si el negro parpadea, el DDIC responde a DCS). Definitivo: T1 modetest-SMPTE
  dumb-buffer (0 flashes, 1 sesión): patrón visible ⇒ es el fetch; negro ⇒ es salida MDP/panel.

## H2 «PPS es la causa y el orden post-0x29 lo arregla» → DÉBIL (código, no cable)

- Fuente del orden: REAL (RE del .ko, no CAF genérico):
  `build/vendor-re/decomp/dsi_display_enable.c` llama `dsi_panel_enable()` (ON=1) y
  después `dsi_panel_update_pps()` (0x14718c→0x147268), con gates (flags 0x1c90/1c91,
  bit 0x29>>6). Ver `SECUENCIA-ENCENDIDO-ANDROID-O82-20261012.md:41-53`.
- Contradicción interna sin resolver: `SECUENCIA:52` dice «PPS calculado, **no va al
  panel; el IC ya está preconfigurado**» y `docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md:484-485`
  «**Sin PPS al panel** (ambos lados de acuerdo)» — contra `PPS-COMPARA.md:32`
  «existe y **envía (DCS 0x0A)**». Ambas no pueden ser verdad; nadie lo ha dirimido.
- Cont-splash: con splash vivo el vendor salta PPS **y** los 108 cmds (`SECUENCIA:132-140`).
  Si el ABL deja splash y nuestro reset+104 cmds lo borran, el re-envío post-0x29
  *debería* bastar — salvo que el DDIC solo acepte PPS con vídeo ya andando (L63 lo
  pone en `enable`, bien) o que el IC preconfigurado nunca necesitara PPS en frío.
- No medido: tráfico DSI del vendor en cable (snapshot r15 sin traza;
  `PPS-COMPARA.md:67-70`: dmesg-FULL r15 = 0 líneas PPS/DSC).
- Test barato: **L63** (`docs/historia/revision/PIPELINE-PANEL-20261014/l63-pps-post.diff`, dry-run OK, `L63-PPS-ORDEN.md:9-16`),
  1 flash. PASA=contenido; FALLA con `UKE-L63 err=0` ⇒ **cerrar la rama PPS entera**
  (las dos posiciones ya probadas), no un cuarto flash de PPS.

## H3 «Nuestra PPS es byte-equivalente a la del vendor» → NO VERIFICADA (sobreaﬁrmada)

- Bien: el lado mainline sale de fórmulas del fuente con repro python
  (`PPS-COMPARA.md:8-28`). El lado vendor sale del RE real (`dsi_panel_update_pps.c`:
  ramas `sde_dsc_create_pps_buf_cmd` vs `sde_vdc_create_pps_buf_cmd` según flags
  0x1c90/1c91 — **rama VDC ni mencionada** en el informe; se asume DSC por el DT,
  sin verificar qué rama toma o82 en el .ko).
- El propio informe admite la salvedad que anula el «diff 0 bytes»:
  «tablas RC sde vs DRM sin cotejo entrada a entrada» (`PPS-COMPARA.md:43-45`).
  Thresholds/ranges/offsets del vendor nunca se vieron en bytes reales (no hay captura).
- No comparado contra bytes reales: NADA (toda la comparación es fórmula-vs-fórmula).
- Test barato (0 flashes): cotejar tabla RC de `sde_dsc_create_pps_buf_cmd` vs
  `drm_dsc_helper.c:316-390` offline; y con 1 flash, `print_hex_dump` de los 128 B
  enviados vs los calculados (cierra al menos nuestro lado).

## H4 «Wedge L60 = battmgr (R-32)» → DÉBIL (cita errónea + confounds vivos)

- La cita es falsa como «precedente medido»: `REFUTADO.md:94-98` declara **FALSADO**
  tanto R-32 (pmic_glink desblacklisteado) como R-33 (nodo DT). La evidencia real es
  el ledger **#404**: bisección K1/K2 (árbol de septiembre) ⇒ culpables
  `QRTR_SMD` y/o `BATTERY_QCOM_BATTMGR` **=y**, por camino de init (no probe),
  wedge mudo sin panic. Pero: (a) otro árbol/config, (b) implicaba a la PAREJA.
- A favor, débil: `k52L59.config:1604` ya trae `QRTR_SMD=y` y bootaba ⇒ el delta L60
  de 3 líneas (`docs/historia/revision/PIPELINE-PANEL-20261014/L60-FALLO-ARRANQUE.md:16-17`) deja battmgr+glink+ucsi; el modo de
  fallo coincide con #404.
- En contra: el propio informe admite que los 3 probes no bloquean y el mecanismo
  «probe colgado ⇒ stall ⇒ panic» **no encaja** (`docs/historia/revision/PIPELINE-PANEL-20261014/L60-FALLO-ARRANQUE.md:22-28`); la
  cmdline sin `panic_on_rcu_stall`/oops es igual en L58/L59 (nada distintivo de L60);
  el guard anti-doble-nodo es código NUEVO jamás boot-testeado (solo «strings»,
  `:29-30`); y el dtbo s287 trae **DOS nodos** `qcom,pmic-glink` (`:32-35`) cuyo
  2º probe (-EBUSY) corría por primera vez justo en L60. Tres sospechosos, un veredicto.
- No medido: captura ACM del wedge (el rollback «intenta→falla→fastboot» no cita log);
  `glink+ucsi=y` sin battmgr jamás probado.
- Test barato: `fastboot boot` del L60 (**0 escrituras**; caveat R-12: usa dtbo del
  slot) con ACM único + `dmesg -n 7`; o L61 (glink+ucsi=y sin battmgr, 1 flash).
  Y corregir la cita R-32/R-33 → #404.

## H5 «set_active resetea la hemorragia de slot» → SÓLIDA (medida repetida)

- Medido: flash+`set_active a` pasa `unbootable:a yes→no`, retry 0→7 (#614/#P52);
  «rehabilita por 3ª vez» (NOTAS). qbootctl innecesario. Matiz: medido juntos,
  sin set_active solo ni doc ABL; operativamente basta.
- Riesgo: a=3 hoy ⇒ ~3 boots de margen si H6 es por-boot. Test de coste cero: leer
  `slot-successful` en el próximo `getvar all`; si nunca es `yes`, nada marca éxito.

## H6 «El retry se gasta por arranque» → MEDIA-DÉBIL (encaja, sin aislar)

- Datos: #634 deja a=5 → flash+set_active (→7) → boots L58 / L60-fail / L58-rb / L62
  → #640 mide **a=3**. ~4 intentos ⇒ 7→3 encaja con −1/boot sin success-marking
  (sin HAL bootcontrol/qbootctl nada marca `successful`; cada boot cuesta 1).
- Pero jamás medido con getvar antes/después de UN boot aislado; la serie está
  contaminada por flashes (cada uno resetea a 7 y enmascara). «Cada fallo» queda
  descartado (boots exitosos L57/L58 también preceden caídas) ⇒ **por-boot** es la
  inferencia, no la medida. Ojo: a=3 se midió tras L62 (#640), no tras L58.
- Test barato: `getvar all` → 1 boot L58 sin flash → `getvar all`. 0 escrituras.

## H7 KTZ «0x02=0x52 ⇒ I2C-only y luz garantizada» → SÓLIDA (cerrar)

- Medido 2×: flip en vivo («SE ENCENDIO» + rampa sysfs) y L57 (`UKE-L56` a 4,27 s,
  `0x02=0x52`; `KTZ-PWM-ENABLE.md:70-79`). Pegas menores no refutadoras: el driver
  nunca reescribe 0x02 (persiste); CABC/PWM futuro sin pin en árbol; L56 limpia en probe.

## 3 acciones de más valor ahora

1. **Flashear L63** (diff listo): único test que confirma o **cierra la rama PPS
   entera**. Si FALLA con err=0 ⇒ nº2 `docs/historia/revision/PIPELINE-PANEL-20261014/s6-noncontinuous.diff` (listo), luego PHY.
2. **Medición slot coste-cero** (H5+H6): `getvar all` (incl. `slot-successful`) →
   1 boot sin flash → `getvar all`; y decidir `mark-successful`/qbootctl con el dueño
   **antes** de que a=3 llegue a 0.
3. **Atribuir L60 con evidencia** (H4): `fastboot boot` L60 + ACM (0 escrituras) o
   L61 sin battmgr; hoy la cita R-32/R-33 es errónea y el doble-nodo s287 confunde.
   Sin esto, el próximo ciclo de carga se construye sobre un culpable sin probar.
