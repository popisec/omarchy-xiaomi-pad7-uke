# FINAL-INTEGRACION — Cierre del pipeline «canal de pantalla» (14-oct-2026)

Subagente final integrador. Solo lectura en tablet (no tocada) y en árboles
(solo copias en `/tmp`; `k52-L16-tree` intacto). Todo lo afirmado, verificado
por mí salvo mención explícita.

## 0. Veredicto ejecutivo

**Versión a flashear (L46 + s287): display-ON + vci (S1, driver + DT) + harness
de medición S4. Nada más.**

| Artefacto | Contenido | Escritura |
|---|---|---|
| `boot L46` | L45 + hunks driver de `docs/historia/revision/PIPELINE-PANEL-20261014/s1-vci.diff` + `docs/historia/revision/PIPELINE-PANEL-20261014/s4-instrumentacion.diff` + cmdline **sin** `video=DSI-1:d` | `flash boot_a` (1) |
| `dtbo s287` | s286 + 1 fragmento (`vci-supply = <&L19B>` al `panel@0`) | `flash dtbo_a` (1) |

Total: **2 escrituras** (dentro del gate ≤2/día). Rollback: L45 `83647c45…` + s286 `33d153f2…` (intactos, en slots ahora).

Por qué esta composición y no otra (§2): vci es el único candidato P0 que es
**precondición** de todo lo demás (sin rail analógico, ni el reset ni el host
pueden mostrar ACK); S4 no es variable funcional sino el instrumento que hace
atribuible este ciclo y todos los siguientes; S3/S2/S5a/S6 quedan aparcados
con dueño y orden asignados, cada uno con la nota del revisor que lo aparca.

## 1. Paso entero del panel, de punta a punta

Base: `build/kernel-pokes/k52-L16-tree` (el vivo, origen de L45).

| # | Etapa | Estado vivo (fichero:línea) | Qué falta / está mal | Cambio propuesto y dueño | Veredicto |
|---|---|---|---|---|---|
| 1 | Rails vddil8b/vsp/vsn | `panel-…o82-dualdsi.c:84-88` (tabla 3 supplies), `:291-323` (`o82_power_on` con load 300 mA + 2 ms) | OK (orden vendor, PROFUNDO §4) | — | Verde, no tocar |
| 2 | Rail **vci/L19** | Driver: `grep -c vci` = **0** (`:48-61` struct sin campo, `:635-638` probe solo bulk). DT: `fase4-display.dts:358-364` sin `vci-supply`. Rail existe a 2,6 V sin voto (testimonio S3 §1:20-23, pendiente re-medir D3) | **Faltan las DOS mitades** (S1 §2; REVIEW-S1 §1 lo confirma por conteo directo L16=0/L29=27/L33=0) | `docs/historia/revision/PIPELINE-PANEL-20261014/s1-vci.diff` (**S1**): campo + voto 2,6 V antes de los 3 rails + `get_optional` + `fragment@10` | **ENTRA en L46/s287** (P0, precondición) |
| 3 | Probe / herencia | `:640-654` (`GPIOD_OUT_HIGH/OUT_LOW` según `uke_panel_inherit()`), `:726` (`prepare_prev_first=true`) | Herencia OFF por defecto (`msm_drv.c:69` sin init; cmdline L45 sin token — medido §5 F-INT-3) → prepare correrá | — (S3-hunk-4 aparcado por N-HERED) | Precondición verificable pre-flash |
| 4 | Reset GPIO del panel | `:262-285` (`o82_reset`: niveles vendor OK, final **100 ms** `:282`) | Diverge 100 vs 15 ms vendor; 1 reset vs 2 vendor; reset asertado desde probe | `docs/historia/revision/PIPELINE-PANEL-20261014/s3a-reset15ms.diff` = solo hunk-2 de S3 (**S3a**, generado §2.4); resto aparcado | **Aparcado** hasta veredicto S1 (N-BLOQ) |
| 5 | Host: pulso sw_reset | `dsi_host.c:1147-1149` (`msleep(20)`), `:36` define | Vendor 1 µs (probado S2 §2c; REVIEW-S2 lo re-verifica independiente) | `docs/historia/revision/PIPELINE-PANEL-20261014/s2-g8.diff` (**S2**) | **Aparcado** (detrás de power; NOTA E/F) |
| 6 | Host: orden ENABLE/VID/DCS | `:919-921` (CLK+lanes+ENABLE juntos), `op_mode_config:1158-1181` write `:1180` (VID\|ENABLE antes de DCS), panel DCS en prepare antes de `pre_enable` (`:726`) | Rediseño estructural, **huérfano S2↔S3** (REVIEW-S6 §6) | (a) asignado a **S3-futuro**; (b) VID-tras-DCS a **S4-funcional post-E1** | Sin hunk en este pipeline (correcto) |
| 7 | Los 108 DCS + muerte cmd#0 | `:208-256` (`o82_send_panel_cmds`, dual `:236-238`, aborta al primer `accum_err` `:246-247`); camino host verificado S4 §2.1 línea a línea (REVIEW-S4 §1: todo OK) | Crudos FIFO/TIMEOUT no impresos; `status=4/5` agregados sin `id`; LP/HS_TIMER sin programar | `docs/historia/revision/PIPELINE-PANEL-20261014/s4-instrumentacion.diff` (**S4**, 5 `pr_err` en error-paths) | **ENTRA en L46** como harness (0 funcional) |
| 8 | PPS DSC | Ausente en vivo; bloque L37+L40 en `docs/historia/revision/PIPELINE-PANEL-20261014/s5a-pps-dual-link.diff` | Inalcanzable hasta que la muerte pase `w4-done` (lección L37: `L37-pps` ×0) | `s5a` (**S5**) | **Aparcado** (precondición de orden; compilar antes, N6) |
| 9 | Clock continuo | `:595-596` flag `CLOCK_NON_CONTINUOUS` puesto contra su comentario | Contradice fase-TX vendor; pero quitarlo rompe fase-reset LP11 (medio-contrato, REVIEW-S6 NOTA-1) | `docs/historia/revision/PIPELINE-PANEL-20261014/s6-noncontinuous.diff` (**S6**, H3 = ciclo 4) | **Aparcado** (detrás de S2) |
| 10 | Backlight/KTZ | Verde L44+L45 (`UKE-L45`=1; defer `:745-758`) | OK | — | Verde, no tocar |
| 11 | DT higiene: `ktz_bl_1` fantasma, typo `byte_cly`, DSC/timings | Fantasma real pero benigno; typo **inexistente** (cierre correcto); DSC/timings coinciden | Higiene, no diagnóstico | `docs/historia/revision/PIPELINE-PANEL-20261014/s6-ktz-undup.diff` en ciclo dtbo propio futuro | **Aparcado** (s287 = solo vci) |
| 12 | Framebuffer | Vivo lleva `FBDEV_EMULATION=y` (REVIEW-S5 N5: por delante de L39) → con display-ON el kernel hace modeset solo (fbcon) y `prepare()` corre sin sddm | — | Quitar `:d` es la llave (FASE 1 ROADMAP) | Parte de L46 (precondición, no variable) |

### Caza de lógica: orden, dependencias, contradicciones

- **Dependencia real nº1 (power ≺ todo):** sin vci votado, el TDDI puede estar
  sordo por alimentación; ningún resultado de S3a/S2/S5a/H3 sería atribuible
  (un fallo idéntico se leería como «reset/host/DSC» cuando la causa sería el
  rail). Por eso S1 va primero aunque la escalera del 13-oct pusiera el reset
  (peldaño 2) antes: la escalera se escribió creyendo el driver-con-vci
  (ROADMAP FASE 3.2: «está portado en el driver pero el overlay no lo
  declara»), y **S1 demuestra que es falso** (0 hits en el vivo; pérdida
  L29→L33, REVIEW-S1 §1). La premisa cambió ⇒ el orden cambia. (C-3)
- **Dependencia real nº2 (muerte ≺ PPS):** s5a es código muerto hasta que el
  punto de muerte pase `w4-done` (S5 §4; lección L37). Orden forzoso S1→S3a→s5a.
- **Dependencia real nº3 (E1-instrumentación):** sin los crudos S4, el veredicto
  de CUALQUIER ciclo display-ON se lee sobre agregados `status=4/5` + ACM lossy
  (E4). S4 no cambia comportamiento ⇒ no es variable E1 ⇒ viaja con S1.
- **Contradicción C-1 (huérfano del reorden, REVIEW-S6 §6):** S2 asigna el orden
  del prepare a S3 (S2:125,197-198); S3 lo devuelve a S2 (S3:37,55,77).
  Decisión: sub-item (a) `prepare_prev_first` → **dueño S3-futuro** (toca el
  probe `:640-654`, menor coste marginal, aunque lo rehusó); sub-item (b)
  VID-tras-DCS → **dueño S4-funcional** (hipótesis H-S4-1, ciclo post-E1).
  Ninguno entra hoy (rediseño ≠ un cambio).
- **Contradicción C-2 (S1 «no acumulable»):** S1 §6 declara su diff alternativa
  a S3 «no acumulable salvo decisión explícita del dueño». Esta es esa
  decisión explícita: lo acumulado con S1 es **S4-harness (medición, 0
  funcional)**, no S3. E1 prohíbe apilar variables funcionales; los pokes de
  medición viajan en todos los ciclos por precedente (K47/K48/K49/L37).
- **Tensión C-5 (medidas S3 vs SSH de S1):** S3 §1:20-23 da medidas vivas sin
  log archivado (REVIEW-S3 D3: testimonio, no dato) y S1 §1:21 reporta SSH
  caído la misma mañana. No son contradictorias si son de horas distintas,
  pero S3 debe fechar/horar sus lecturas y el ciclo L46 las **re-mide**
  (gates en PARA-EL-FLASH) antes de flashear.
- **Afirmación S3 D4 («~4 s en reset»):** sin fuente; con `:d` el reset queda
  asertado indefinidamente, no 4 s. No usar ese número en ningún criterio.
- **Tesis S4 («stall del host, no panel sordo»):** se sostiene como heurística
  fuerte con contraejemplos de contención/reloj (REVIEW-S4 §2); el diff E1
  decide en los 4 casos principales salvo cautela N5 (orden temporal
  IRQ-prints vs snapshot-DMA por W1C-clear) y hueco N4 (sin ACK/PHY/CLK).
  Trasladado al criterio de lectura en PARA-EL-FLASH.

## 2. Decisión de la versión a flashear

### 2.1 Incluidos

1. **S1-driver (4 hunks de `docs/historia/revision/PIPELINE-PANEL-20261014/s1-vci.diff`, rutas repo-relativas):** campo `vci`,
   voto 2,6 V antes de los 3 rails + `L27-vci-ok`, disable en `err` de power_on
   y en `unprepare`, `get_optional` + `L27-vci-absent`. Restauración literal de
   L27 (REVIEW-S1 §3: byte-aditivo, fuzz 0, disjunto de s3/s5a en ambos
   órdenes). Omisión declarada del disable en `err` de prepare → vuelve en
   hardening (REVIEW-S1 §3c).
2. **S1-DT (`fragment@10`, `vci-supply = <&L19B>`):** sin él, el driver degenera
   a `L27-vci-absent` = ciclo quemado. Driver-solo y DT-solo son no-ops
   respectivos ⇒ **son dos mitades de UNA variable** (justificación E1 §2.6).
   Resolución verificada más fuerte que el revisor: el símbolo `L19B` existe en
   la **base viva** `base-dtb.img` (símbolo línea 20917; F-INT-1 §5); el gate
   `fdtoverlay` del script s287 lo confirma en build de todos modos.
3. **S4-harness (`docs/historia/revision/PIPELINE-PANEL-20261014/s4-instrumentacion.diff`, 5 `pr_err`):** dry-run OK (REVIEW-S4
   §3); 0 funcional; coste runtime nulo en display sano; necesario para leer
   la tabla E1 con cautela N5. Declarado como harness, no como variable.
4. **Display-ON (quitar `video=DSI-1:d`):** precondición FASE 1 (sin bind no hay
   prepare), no variable bajo test. Herencia OFF por defecto verificado
   (F-INT-3): cmdline L45 sin token + `msm_drv.c:69` default false.

### 2.2 Excluidos (con la nota del revisor que los excluye)

| Diff | Motivo + nota |
|---|---|
| S3 completo (5 hunks) | **N-BLOQ** (REVIEW-S3 §3): 3 variables (timing/nº-resets/estado-inicial), repetiría E1 a escala menor. + **N-HERED**: ASIS deja reset flotante bajo inherit; precondición sin-herencia exigible y aún no medida en display-ON |
| S3a (15 ms solo) | Orden power≺timing (§1 C-3): entra **inmediatamente después** del veredicto S1 (escalera peldaño 2). Diff ya generado y verificado (`docs/historia/revision/PIPELINE-PANEL-20261014/s3a-reset15ms.diff`, dry-run OK) |
| S2 (pulso 1 µs) | Sólido pero detrás de power (un panel sin rail no da ACK aunque el pulso sea perfecto) + escalera peldaño 5 + NOTA E (restore no-op condicionado a herencia) + NOTA F (re-anclar a control gemelo). Siguiente tras S3a |
| S5a (PPS dual) | Su propio criterio lo prohíbe antes de que la muerte pase `w4-done` (S5 §4); hoy el punto de muerte display-ON es desconocido (primero desde L39). **Compilar en copia antes del ciclo** (REVIEW-S5 N6), flashear en peldaño 3 |
| S6-noncontinuous | H3 = ciclo 4 de ENABLE-COMPARISON (tras 1a–3) + medio-contrato LP11 (REVIEW-S6 NOTA-1: si falla idéntico, apunta al reorden huérfano, no a más variables) |
| S6-ktz-undup | Higiene con criterio propio «firma DSI no cambia» (S6 §4): ciclo dtbo propio futuro; s287 lleva **solo** vci (un cambio también en el eje DT) |
| Reorden / VID-tras-DCS | Huérfano asignado (§1 C-1); rediseño, no un cambio |
| G4/G5/G6/G7/G1 | Refutados/inertes (BRIEF; auditoría §2). No re-probar |

### 2.3 Orden de aplicación de los diffs (bases distintas — REVIEW-S6 NOTA-3, REVIEW-S3 D5)

- `docs/historia/revision/PIPELINE-PANEL-20261014/s1-vci.diff`: **desde la raíz del repo, `patch -p1`** (mezcla hunks
  repo-relativos `build/gates/…` y `build/kernel-pokes/k52-L16-tree/…`; dry-run
  OK verificado §5). Solo se aplican sus hunks de **driver** al árbol de build;
  el hunk DT va al script s287, NO al dtbo.
- `docs/historia/revision/PIPELINE-PANEL-20261014/s4-instrumentacion.diff`: **desde `build/kernel-pokes/k52-L16-tree`,
  `patch -p1`** (rutas `a/drivers/…`; dry-run OK por REVIEW-S4 §3).
- Disjuntos por fichero/línea (verificado S1 §3, REVIEW-S1 §3, REVIEW-S6 §5).
- Commit único en el árbol + `fase4`/scripts: `L46: vci + S4-DIAG harness
  (display-ON por cmdline)`. `docs/historia/revision/PIPELINE-PANEL-20261014/s3a-reset15ms.diff` se archiva **sin aplicar**
  (parked para el ciclo siguiente).

### 2.4 Hunks re-generados

- **`docs/historia/revision/PIPELINE-PANEL-20261014/s3a-reset15ms.diff`** (nuevo, en este directorio): hunk `@@ -279` de
  `docs/historia/revision/PIPELINE-PANEL-20261014/s3-reset-tddi.diff` verbatim, cabecera tree-rooted `a/drivers/…`,
  `patch -p1` desde el árbol. Dry-run OK en copia (§5). Exigencia N-BLOQ
  cumplida por construcción.

## 3. Runbook de build+flash

Ver **`docs/historia/revision/PIPELINE-PANEL-20261014/PARA-EL-FLASH.md`** (mismo directorio): comandos exactos de build
(`build-fast.sh --src k52-L16-tree --cfg k52L45-build/.config --out
k52L46-build --tag k52L46`), clon `repack-k52L46.py` (display-ON por
`--cmdline-append=-video=DSI-1:d` + gates actualizados: POKE 113→115, G2/G6
sin `:d`), clon `charge/mkdtbo-s287.py` (s286 + fragment@2302 vci + gates
`fdtoverlay`/fdtget/paridad), gates nuevos esperados, criterio pasa/falla
prefijado endurecido (D6/D7/NOTA F: secuencia/punto-de-parada, tercer brazo,
manda dmesg-SSH per N7), doble captura + lector ACM único, y rollback L45/s286.

## 4. Correcciones documentales exigidas por las revisiones (erratas, sin editar entregas)

- **REVIEW-S5 N1 (factual, la grave):** S5 §2.1-H5/§5 «L34-flush hizo daño
  medido (8→12 `status=4`)» — número **refutado** por `NOTAS-OMARCHY.md:3654-3665`
  («FALSO, inventado»; 10/10/10 + ratelimit) y degradado a «blando» en
  `:4024-4026`. Justificación correcta del NO-porte H5: «sin señal atribuible
  (modos distintos, ACM-only, gate tautológico) + contraejemplo sheng». El
  veredicto (no portar) no cambia.
- **REVIEW-S1 N1 (cita):** «`vci-supply=0x150` en stock2:6956» — stock2 tiene 0
  hits de `vci`; la evidencia es `dt-fusionado-s238.dts:1280,1300` (+ identidad
  `:7989-7998`); stock2 solo aporta nodo/tensión/símbolo L19. Igual
  «PROFUNDO:380-381» → fila vci en `:382`. Hecho cierto, atribución a corregir.
- **REVIEW-S3 D1:** «7 hunks L27» → son **11** (`grep -c '^@@'`).
  **D2:** «SECUENCIA…:338-341» → es `docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md:338-341`
  (SECUENCIA tiene 259 líneas). **D5:** declarar raíz de `docs/historia/revision/PIPELINE-PANEL-20261014/s3-reset-tddi.diff`
  (árbol, no proyecto). **D6/D7/D8:** endurecer PASA + tercer brazo + reformular
  «duplica la exposición» (dos pasadas × ventana 6,7× más corta).
- **REVIEW-S2 NOTA A–D:** cita `delay.c:76` → `include/asm-generic/delay.h:59-66`
  (`UDELAY_CONST_MULT`); `:1221+1226` → `:1158-1181` (write `:1180`); «file-offset»
  → «offset en `.text`» (`.ko` es ET_REL); ruta `HALLAZGO-MUERTE-DSI.md` →
  `build/evidencia/L40/`. **NOTA E:** «restore no-op en primer arranque»
  condicionado a herencia ABL. Fondo del pulso intacto.
- **REVIEW-S4 N1:** `host_enable:2436-2437` → bit en `op_mode_config:1171-1172
  vía :2436`. **N2:** DSI_0 early-return devuelve éxito ⇒ solo link-1 aborta
  (refuerza el análisis; que conste en la lectura).
- **REVIEW-S5 N2/N3:** «4 símbolos» → **3**; líneas `.config` L45
  (`3855/6346/7293`, KTZ `5226`) vs L39. **N4:** inventario H9 omite 3 hunks de
  herencia del panel (solo-vivo, mismo veredicto). **N5:** fbdev no es «fuera
  del display path» (determina si el commit corre); argumento correcto: «el
  vivo ya va por delante».
- **REVIEW-S6:** cosmética `:909-917` (no `:909-916`); herencia `mode_flags` en
  `:765` (no `:764-765`); cobertura grep S6 no reproducible en exhaustivo (sin
  impacto build/boot). NOTA-1/§6 trasladados a §1 C-1/C-3.
- **REVIEW-S1 N2 (matiz vivo):** parcialmente cerrada por mí (F-INT-1): `L19B`
  existe en la base viva; queda el gate `fdtoverlay` en el script s287.
- **REVIEW-S3 D3/D4:** medidas SSH sin archivar + «~4 s» sin fuente + tensión
  horaria con S1 — el ciclo L46 re-mide todo (gates en PARA-EL-FLASH).

## 5. Hallazgos propios de la integración (F-INT, verificados hoy)

- **F-INT-1:** `L19B` existe en la base viva (`base-dtb.img` decompilado línea
  20917 + nodo `pmxr2230_l19` línea 6956). El fixup de fragment@10 resuelve.
- **F-INT-2:** la «filosofía sin fragmentos nuevos» (`mkdtbo-s280.py:85-86`,
  REVIEW-S1 N2) está superada por s283 (`fragment@2300/2301` con labels,
  `charge/mkdtbo-s283.py:71-101`): el precedente de injerto con `dtc -@` +
  `fdtoverlay` existe ⇒ s287 = clon de `mkdtbo-s286.py` + `fragment@2302`.
- **F-INT-3:** cmdline L45 medida del `.img` (580 B): lleva `video=DSI-1:d` a
  mitad (extraíble por `--cmdline-append=-video=DSI-1:d`) y **no** lleva
  `msm.uke_panel_inherit` ⇒ inherit=false ⇒ `prepare()` correrá completo al
  quitar `:d`. Precondición N-HERED verificable pre-flash (cmdline) y post-boot
  (`P82-inh-prep` ausente).
- **F-INT-4:** `repack-k52L45.py` **fuerza display-off** (G2 exige `video=DSI-1:d`;
  G6 exige cmdline==k64). Ninguna sección lo señaló: el ciclo display-ON exige
  clon del repack con G2/G6 reescritos (hecho en docs/historia/revision/PIPELINE-PANEL-20261014/PARA-EL-FLASH.md).
- **F-INT-5:** el gate `UKE-POKE=113` del repack (G3) **rompe con S1** (+2
  call-sites ⇒ 115; S4 aporta 0). `build-fast.sh` no tiene ese gate
  (verificado por lectura). El clon lo actualiza; ningún `mustnt` colisiona
  con las cadenas nuevas (verificado).
- **F-INT-6:** con `FBDEV_EMULATION=y` en el vivo, display-ON ⇒ fbcon hace
  modeset solo al arrancar ⇒ `prepare()` corre sin sddm (mejor que L39: sin
  paso manual). Riesgo simétrico: muerte pre-USB posible ⇒ ACM manda en la
  ventana temprana (criterio con dos brazos en PARA-EL-FLASH).

## 6. Índice de la noche + lo que queda

- Entregas: S1-VCI, S2-G8, S3-RESET-TDDI, S4-DCS-HOST, S5-PORT-L39,
  S6-MINUCIAS-DT (+ diffs s1/s2/s3/s4/s5a/s6×2). Revisiones: REVIEW-S1…S6
  (todas **OK-con-notas**; 1 bloqueante N-BLOQ resuelta por S3a).
- Generado por integración: `docs/historia/revision/PIPELINE-PANEL-20261014/s3a-reset15ms.diff` (parked), `docs/historia/revision/PIPELINE-PANEL-20261014/PARA-EL-FLASH.md`.
- Mañana (en orden, un cambio por ciclo): **L46/s287** (hoy si gates dan) →
  veredicto vci → **S3a** (15 ms) → veredicto → **s5a-compile-check ya**,
  flash s5a en peldaño 3 → **S2** (con control gemelo) → **H3** →
  **ktz-undup** (dtbo propio) → reorden (a)→S3-futuro, (b)→S4-funcional.
- Deuda: re-medir L19 `use`/gpio/DT (D3); archivar en `out/diag-S3-L46/`;
  entrada en NOTAS-OMARCHY + commit; corregir citas N1/D1/D2/A–D en las
  entregas cuando sus autores las reabran (este informe es la fe de erratas).
