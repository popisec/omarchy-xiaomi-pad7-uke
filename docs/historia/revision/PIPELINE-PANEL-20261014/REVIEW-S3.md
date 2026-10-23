# REVIEW-S3 — Revisión adversarial de S3-RESET-TDDI + docs/historia/revision/PIPELINE-PANEL-20261014/s3-reset-tddi.diff (14-oct-2026)

Veredicto: **OK-con-notas** (con una nota bloqueante: **no flashear los 5 hunks juntos**; ver N-BLOQ).

Revisor adversarial, solo lectura. Árboles intactos (dry-run sobre copia en `/tmp/opencode/s3t`, sin tocar `k52-L16-tree` ni las entregas).

## 1. Verificaciones que PASAN (evidencia comprobada)

- **V1. Diff aplica limpio**: `patch -p1 --dry-run` sobre copia del fichero vivo → `DRYRUN_EXIT=0`, los 5 hunks (`@@ -261`, `-279`, `-350`, `-403`, `-447`, `-637`) aplican sin fuzz ni rechazo.
- **V2. Anclas del vivo correctas**: `usleep_range(100000,101000)` en `:282`, `gpiod_set_value_cansleep(reset)` en `:265/270/275/280/406/450`, `gpiod_get … GPIOD_OUT_LOW : GPIOD_OUT_HIGH` en `:646-647`, `prepare_prev_first=true` en `:726`, `mode_flags` en `:595` — todas las citas de líneas de S3 §1/§3 existen (verificado por grep sobre `k52-L16-tree/.../panel-xiaomi-o82-dualdsi.c`).
- **V3. L27 nunca flasheado y ausente del vivo**: el vivo conserva `100ms` + `GPIOD_OUT_HIGH`; `l27-fidelidad-android.diff` existe (187 líneas) y el vivo no lleva ninguno de sus hunks. Correcto.
- **V4. B1 verificado**: `docs/historia/revision/ESD-MASK-TEST-20261012.md:30-52` — tabla temporal con muerte **+35,9 ms tras `w4-done`** (`:45`), sin `R2-ok` en la secuencia, título `6/6` (`:30`), ESD ×1 por línea antes de `w4-done`, conclusión «síntoma, no causa» (`:54-65`). Evidencia cruda en `build/evidencia/pantalla-esd-mask-20261012/`.
- **V5. B2 verificado**: `HALLAZGO-L33-DEATH-20261013.md:28-43` — `K47-pre-rst … [207.979]` → `K47-pre-rstOK [208.102]` (= 123 ms, reset completa), `K49-esd-irq ×2`, `cmd#0 → host-xfer → video-done timeout [208.181]`. Correcto.
- **V6. L38 nunca medido solo**: `L39-PLAN-20261013.md:351-371` — tabla «L38: nunca flasheado ni medido». Correcto.
- **V7. Doble reset vendor literal**: `SECUENCIA-…:A.2` (`dsi_panel_prepare` = `mutex_lock + dsi_panel_reset()`, 2º reset; «literal del binario, no suposición»). Correcto.
- **V8. Reset-sequence DT + INPUT final**: `docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md:338-356` (pares `(0,10)→(1,3)→(0,3)→(1,15)`, `usleep_range_state`, `0x156100 gpiod_direction_input`). Correcto el contenido.
- **V9. Orden rails + vci**: PROFUNDO §4 (`:380-414`) — vddio+vci → vddil8b→vsp→vsn, 300 mA + 2 ms. Correcto; S3 lo deriva bien a S1.
- **V10. REFUTADO/LECCIONES**: `grep -n "L27\|L38\|doble reset\|GPIOD_ASIS\|Hi-Z"` en ambos docs del proyecto hermano → **0 coincidencias**. Correcto, vía libre.
- **V11. K49 ya en el vivo**: bloque ESD `o82_esd_irq_thread` + `esd-err-gpios` en vivo `:603-665`; `k49-esd-gpios.diff` = 89 líneas como citado. Correcto.
- **V12. Disjunción con otros diffs**: S2 y S4 tocan solo `dsi_host.c` (otro fichero); S5a (`@@ -29`, `-360`) y S6-noncontinuous (`@@ -588`) no intersectan los contextos de S3 (`-261/-279/-350/-403/-447/-637`); `l45-panel-defer.diff` toca `:743+` (backlight defer) frente al hunk S3 que termina en `~:663`. Sin pisadas.
- **V13. Corrección honesta a ROADMAP**: B1/B2 demuestra que el sleep de 100 ms no es letal per se (B2 lo sobrevive) — mejora real sobre `docs/historia/revision/ROADMAP-PANTALLA-20261013.md:93-98`, que lo declara «punto conocido de muerte» sin distinguir caras. Crédito al autor.
- **V14. NO al gpio-INPUT**: excluir el `direction_input` post-reset (`panel+0x908` sin identificar) es lo correcto; inventarlo habría sido una variable fantasma.

## 2. Discrepancias (con fichero:línea y corrección)

- **D1 (menor, conteo).** S3 §1:7 dice «7 hunks L27». `grep -c '^@@'` sobre `build/gates/patches/l27-fidelidad-android.diff` = **11** (`@@ -53/-263/-281/-297/-323/-344/-389/-431/-473/-665/-740`). Corregir a «11 hunks (7 temas)» o quitar el número.
- **D2 (cita a fichero equivocado).** S3 §1:11 cita «`SECUENCIA-…:338-341` (reset-sequence DT …)». `SECUENCIA-ENCENDIDO-ANDROID-O82-20261012.md` tiene **259 líneas**; los bytes `0/10,1/3,0/3,1/15` están en `docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md:338-341`. Corregir el nombre del fichero.
- **D3 (medida sin archivo).** S3 §1:20-23 (gpio2 out low, ESD in high, vsp/vsn OFF, TE func1, L19 `use 0/0`) no tiene ningún log archivado: `grep -rln "gpio2\|out low\|use 0/0"` en `out/` + pipeline solo devuelve S3 y S1 (que lo cita de S3). Son lecturas SSH del propio autor, no evidencia re-auditable. Exigir: volcar `gpio + regulator_summary + DT panel@0` a `out/diag-S3/` con fecha antes del ciclo; hasta entonces son testimonio, no dato. Tensión adicional: S1 §1:21 reporta **SSH inaccesible (2 timeouts) la misma mañana ~09:1x** — S3 debería fechar/horar sus lecturas para que no parezcan contradictorias.
- **D4 («~4 s en reset», sin fuente).** S3 §2-fila 2 y §3-hunk 4: «panel ~4 s en reset cada boot». Sin cita ni medida. Peor: con `video=DSI-1:d` (boot L45 actual) el prepare **nunca corre**, luego el reset queda asertado **indefinidamente**, no 4 s; y en boots con display el intervalo probe→prepare no está medido en ningún log citado. Corregir a «asertado desde el probe hasta el prepare (intervalo sin medir; con `:d`, indefinido)» o aportar la medida.
- **D5 (raíz de aplicación no declarada).** `docs/historia/revision/PIPELINE-PANEL-20261014/s3-reset-tddi.diff` usa rutas `a/drivers/…` (se aplica desde la **raíz del árbol**), mientras `docs/historia/revision/PIPELINE-PANEL-20261014/s1-vci.diff` usa `a/build/kernel-pokes/k52-L16-tree/…` (desde la **raíz del proyecto**). Aplicar ambos con el mismo `patch -p1` desde el mismo cwd falla para uno. S3 §3 dice solo «formato `patch -p1`». Añadir: «aplicar desde `build/kernel-pokes/k52-L16-tree`» (S1 ya declara su propia raíz; el integrador debe anotar ambas).
- **D6 (PASA demasiado laxo).** S3 §4: «timeout distinto al `video-done` de L33» cuenta como PASA. Cualquier timeout distinto (p.ej. un timeout nuevo introducido por el propio doble reset) es señal, no éxito. Endurecer: PASA = `cmd#0` con **respuesta/ACK** o imagen; «timeout distinto» = señal direccional a registrar, no pasa.
- **D7 (hueco en pasa/falla).** Muerte en la ventana post-`w4-done` del **segundo** reset con 15 ms no es «idéntica a B1» (B1 era ventana de 100 ms) ni «idéntica a L33». El criterio no la nombra. Añadir tercer brazo: muerte en 2º-reset/15 ms = «exposición B1 confirmada en ventana corta; refuta L38 como atenuante, no refuta la secuencia vendor».
- **D8 («duplica la exposición», sin cuantificar).** El riesgo real combina dos efectos de signo opuesto: pasadas por la ventana 1→2 (×2) **y** duración de ventana 100→15 ms (÷6,7). «Duplica» cuenta ventanas, no muertes: la P(muerte|pasada) en el path prepare es desconocida (B2 sobrevivió una pasada de 100 ms; el 6/6 de B1 es del path modetest). Reformular: «dos pasadas por una ventana 6,7× más corta; efecto neto sin medir».

## 3. Nota bloqueante: son 3 variables, no un cambio (N-BLOQ)

Los 5 hunks son **un tema (fidelidad reset/power) pero 3 variables independientes**, cada una con perfil de riesgo distinto:

- **V-a (timing final)**: hunk 2, 100→15 ms. Es exactamente el peldaño 2 de `AUDITORIA-METODO-20261013.md:85` («L33 + reset 15 ms, **solo** L38-variable»).
- **V-b (nº de resets)**: hunk 3, 1→2 + poke `S3-rst-twice`. Es la que duplica la exposición B1 (D8) y la única sin precedente medido en ningún path.
- **V-c (estado inicial/dirección)**: hunks 1+4+5 (ASIS + `direction_output` al entrar + err/unprepare). Cambia el nivel eléctrico entre probe y prepare.

S3 §2 admite que «L38 nunca se ha medido solo» y a continuación propone un diff en el que **L38 vuelve a no poder medirse solo** — repite a escala menor el error E1 que la auditoría condena (L39 = 4 variables, L36 = 2). Si el ciclo mueve la firma, nada atribuye entre V-a/V-b/V-c. Decisión exigida:

1. **Flashear primero S3a = solo hunk 2** (15 ms). Es el peldaño 2 de la escalera, tal cual.
2. **Aparcar S3b (hunks 1+4+5) y S3c (hunk 3)** hasta el veredicto de S3a. S3c solo entra si S3a sobrevive al primer reset (si no, es añadir pasadas a una ventana letal confirmada).
3. Si el dueño decide empaquetar igual, que conste en el ledger como violación consciente de un-cambio-por-ciclo, no como «un cambio temático».

## 4. Riesgo no declarado: herencia + ASIS (N-HERED)

S3 §5 menciona que el hunk 4 «elimina la rama `GPIOD_OUT_LOW`» y condiciona («si inherit está activo, este diff NO aplica»), pero deja la verificación para el momento del flash. El problema es estructural, no condicional:

- En boots con herencia (`uke_panel_inherit()` true, el caso del splash ABL vivo), `o82_prepare` retorna temprano (`vivo :79-83`) **antes** de `o82_reset`. Con ASIS, el reset queda **flotante desde el probe sin que nada lo conduzca jamás** (antes, `OUT_LOW` lo sujetaba liberado). L45 agrava la ventana: el probe del panel va diferido al KTZ (`l45-panel-defer.diff`, `:743+`).
- El criterio §4 no contempla este caso: si el ciclo corre con inherit activo, no habrá `S3-rst-twice` ni muerte desplazada — el resultado es **ambiguo**, no falla. Exigir precondición explícita en §4: «solo flashear sobre boot sin herencia verificada (`P82-inh-prep` ausente en el `dmesg` frío anterior); si hay herencia, S3b no aplica y el ciclo es S3a».
- Detalle menor: el doble reset de S3 es **dos resets consecutivos**, no el equivalente vendor (entre pre_prepare y prepare median LINK_CLK + soft_reset + host enable; aquí `prepare_prev_first` sigue `true`). El comentario del diff lo marca como «aproximación», bien; el texto §2 («fidelidad vendor») lo vende mejor de lo que es. Rebajar a «aproximación sin KMD» en el cuerpo también.

## 5. Coherencia con método y documentos

- Conforme con `AUDITORIA-METODO` E8/GAPLIST (orden host → S2, no tocado aquí), FASE 3 (L27 nunca probado; este diff lo rescata correctamente como subconjunto), doctrina doble captura + `dmesg -n 7` + `sync`/slots (todas citadas en §4/§5), techo 3 ciclos (citado en §4).
- En contra de `AUDITORIA` E1 y BRIEF regla 4 (un cambio por ciclo) por N-BLOQ; en contra de la escalera §3-peldaño 2 por empaquetar V-b/V-c sobre L38.
- El subconjunto sí es fiel a L27 (contenido de los 5 hunks = hunks L27 `@@ -263/-281/-344/-431/-665` parciales, con pokes renombrados `L27-*→S3-*` y la extensión inherit de D-hunk-4). Nada de vci/host/backlight se cuela: la separación S1/S2/S6 declarada en §6 es real (V12).

## 6. Qué debe corregir el autor antes del ciclo (checklist)

1. [ ] D1: «7 hunks» → 11 (o quitar el número). D2: cita reset-sequence → PROFUNDO:338-341.
2. [ ] D3: archivar `gpio+regulator_summary+DT` en `out/diag-S3/` con fecha/hora; D4: retirar o medir los «~4 s».
3. [ ] D5: declarar raíz de aplicación del diff (árbol, no proyecto).
4. [ ] D6/D7: endurecer PASA (ACK/imagen) + tercer brazo (muerte en 2º reset/15 ms).
5. [ ] D8: reformular «duplica» con los dos efectos.
6. [ ] **N-BLOQ**: partir en S3a (hunk 2, flasheable) + S3b/S3c (aparcados). Sin esto, el veredicto para el flash es RECHAZADO aunque el análisis sea OK.
7. [ ] **N-HERED**: precondición sin-herencia en el criterio + análisis del flotante en inherit.
