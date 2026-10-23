# REVISIÓN DE INTEGRACIÓN — la cadena completa de punta a punta (14-oct-2026, noche)

> Revisor integrador. Solo lectura (tablet incluida: no tocada; árboles intactos;
> verificaciones por `grep`/`git show` sobre el árbol vivo `build/kernel-pokes/k52-L16-tree`
> y los commits del día). Base leída: `docs/historia/revision/PIPELINE-PANEL-20261014/BRIEF.md`, `S1-S6` + `REVIEW-S1..S6`,
> `docs/historia/revision/PIPELINE-PANEL-20261014/FINAL-INTEGRACION.md`, `H2-CRASH-CAPTURADO-20261014.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/CRITICA-L47.md`,
> `docs/historia/revision/PIPELINE-PANEL-20261014/L48-PREP.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/CRITICA-L48.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/PARA-EL-FLASH.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/MANANA.md`, `docs/historia/ESTADO-VIVO.md`
> (cabecera + secciones 14-oct), `NOTAS-OMARCHY.md` (entradas 14-oct),
> `AUDITORIA-METODO-20261013.md`, `docs/historia/revision/ROADMAP-PANTALLA-20261013.md`,
> `charge/PRE-REGISTRO-L48.md`, `charge/mkdtbo-s287.py`.
> Estado final del día: `boot_a` = L45 `83647c45…` (restaurado) + `dtbo_a` = s287
> `9f3d2b00…`, tablet en cargador de pared (docs/historia/ESTADO-VIVO.md:15-26, NOTAS 14-oct 14:4x).

## 0. Resumen (≤30 líneas)

- **Cadena por paso**: DT s283→s286→s287 (OK, vci declarado en s287) → hosts DSI
  ae94000/ae96000 + PHYs (bindean; H1: probe diferido a t≈47 s por host secundario,
  sin dueño) → bind DPU/mdss (**completa** en ambos brazos; la muerte es post-bind) →
  panel o82 (probe OK diferido; **`prepare()` no ha corrido NI UNA VEZ con display-ON**)
  → vci/KTZ (driver vci en árbol + supply en DT, **sin votar nunca**: no probado, no
  refutado) → DRM card1 (`unknown` en L48; fbcon refutado como trigger por L47 FALLA-A).
- **Huérfanos**: G9 (arreglo fino H1, sin diff ni ciclo), PPS-S5a, NON_CONTINUOUS-S6/H3,
  G8/S2-pulso, S3a (15 ms), S3b/S3c, reorden (a)→S3-futuro / (b)→S4-funcional,
  variante rewrite-en-vivo de FASE-1, ktz-undup, B1 (enable-gpios/supplies KTZ).
  Todos aparcados con criterio; ninguno toca hoy.
- **Inversión de orden**: FINAL-INTEGRACION puso S1/vci primero ("power ≺ todo") cuando
  la muerte estaba en el primer DCS. Con la muerte **pre-prepare** (H2/L47), el vci es
  **intesteable hasta que el bind sobreviva**: el camino crítico real es
  **asesino-post-bind ≺ vci-test ≺ S3a ≺ S2 ≺ s5a ≺ H3**.
- **Próximos ciclos**: (1) re-run L48 + dumper-v3 + ACM commiteado + valor opp-rate
  (1 escritura, cierra E6-vs-flaky y FASE-1a/1c); (2) cazar actor post-bind según rama
  (sddm/userspace/GDSC-VBIF diferido; 1 escritura); (3) PASA→modetest→primer prepare y
  voto vci (0 escrituras); (4) S3a 15 ms (1); (5) S2-pulso con control gemelo (1);
  (6) s5a/H3 solo tras DCS observado. **Sin sentido hoy**: s5a, H3, S2, S3, ktz-undup,
  FASE-1-sow, modetest-diagnóstico.
- **Huecos de método**: dumper-v3 sin aplicar (dumps por uptime rotan entre boots y se
  pisan); ACM de L47/L48 sin commitear (el "~50 s" y el "~5-11 min" son testimonio);
  valor numérico de `K48-opp-rate` sin registrar; gates de batería (3640/3447 mV) y
  ≤2/día excedidos de facto; presunción "migas inertes" herida por L48 (E6 candidato).
- **Contradicciones**: 6 (C1–C6 abajo), la grave: el inventario de `out/h2-dumps/`
  (`uke-1015…2530`, uptimes de hasta ~42 min) no cuadra con el resumen "~5-11 min".

## 1. Inventario del camino real (árbol vivo `build/kernel-pokes/k52-L16-tree`)

| # | Paso | Estado | Evidencia (fichero:línea / medición) | Dependencias |
|---|---|---|---|---|
| 1 | DT overlays s283→s286→s287 | **Funciona** | s283 = base GPU+display+OPP148+nogpr+bl; s286 = +GPI + 1 bus I2C (KTZ) (ciclo #617 VERDE, NOTAS 13-oct); s287 = s286 + `fragment@2403 { vci-supply = <&L19B> }` (`charge/mkdtbo-s287.py:126-130`, gates G4 fixup verificado `:168-172`); `vci-supply=0x150`=L19 verificado en DT vivo (#620, NOTAS 14-oct 11:3x) | Base de todo; s287 se queda |
| 2 | Hosts DSI ae94000/ae96000 + PHYs ae95500/ae97500 | **Funciona con H1 abierto** | Primer probe del secundario `dsi_get_phy: phy driver is not ready` → `-EPROBE_DEFER`; panel OK al 5º intento t≈47 s, gatillo = probe del táctil (NOTAS 14-oct 11:3x, 12:0x) | H1 retrasa card1 a ~47 s en TODOS los ciclos display-ON |
| 3 | Bind DPU/mdss (`msm_drm_bind → hw_init → irq_install → Initialized`) | **Completa** (ambos brazos) | L47: `K47-dpu-hw-in` → `dpu-res`×2 → `Initialized msm-kms minor 1` 46.98 s, sin `atom-tail` (H2 §1 blob `976f714`, CRITICA-L47 §2.1); L48: `K48-post-init` + `alive-1` a 50.2 s (docs/historia/ESTADO-VIVO.md:19-21) | Precede a todo modeset con FBDEV=n |
| 4 | Muerte post-bind (~50 s L46/L47; ~5-11 min L48) | **Sin resolver** | Silencio tras burst `sync_state` disp_cc/gcc + GDSCs; `pureason=0x80100`; slot agotado (H2 §1, NOTAS 13:0x/14:4x) | Es EL cuello de botella |
| 5 | Panel o82 probe | **Funciona (diferido)** | `UKE-L45`=1 a t≈47 s, `tx-alloc`×2 (H2 §1) | H1 |
| 6 | Panel o82 `prepare()` / `power_on()` / DCS | **NUNCA ejecutado con display-ON** | 0 `K47-pan-prep`, 0 S4-DIAG en H2 y L47 (H2 §1, CRITICA-L47) | Requiere commit (userspace con FBDEV=n) + supervivencia al bind |
| 7 | vci/L19 (driver + DT) | **A bordo, sin probar** | Driver en árbol: campo `:58`, voto 2.6 V `:301-317`, disables `:345-346`/`:479-480`, `get_optional` `:689-690` (verificado por grep hoy); DT: s287 fragment@2403. Sin `power_on` ⇒ sin voto ⇒ **ni confirma ni refuta S1** | Requiere paso 6 |
| 8 | KTZ8866 backlight + enlace panel↔KTZ | **VERDE, cerrado** | L44 canal sysfs→I2C→KTZ→LEDs; L45 `UKE-L45`=1, `sin backlight externo`=0 (NOTAS 14-oct 00:4x, docs/historia/ESTADO-VIVO.md:73-89) | No tocar |
| 9 | DRM card1 / fbdev / modeset | **Aislado** | L46 (=y): fbcon pidió modos y murió en enable (H2 §1, líneas fbcon `uke-48:2926-2933` en blob); L47 (=n): sin `atom-tail` ⇒ fbcon **REFUTADO** como trigger (FALLA-A, NOTAS 13:0x); L48: `card1-DSI-1: unknown` | Con =n, el modeset solo lo dispara userspace (modetest/sddm) |
| 10 | OPP/siembra SRC 514 MHz (FASE-1a/1c) | **Muerta en código; medida pendiente** | Cadena OPP→`parked_cfg`=514 verificada eslabón a eslabón (L48-PREP §3, CRITICA-L48 §3); `K48-opp-rate` imprime en `dpu_kms.c:1329` (verificado hoy) pero **el valor numérico no está registrado** (docs/historia/ESTADO-VIVO.md:26) | L48 re-run la cierra en vivo |

Notas de árbol (verificado hoy por grep): S2 **ausente** (`msleep(DSI_RESET_TOGGLE_DELAY_MS)` en
`dsi_host.c:1148`, define en `:36`); S3a **ausente** (`usleep_range(100000,101000)` en
`panel-…o82-dualdsi.c:286`); H3 **pendiente** (`MIPI_DSI_CLOCK_NON_CONTINUOUS` en `:624`);
`prepare_prev_first=true` en `:770`; PPS **ausente** (0 hits `pps`/`PPS` en el driver);
FBDEV=n en `k52L47-build/.config:4861` y `k52L48-build/.config:4861` (=y en L46).
S4-DIAG: presencia en el árbol **no verificada hoy** (L46 lo llevó; L47/L48 no lo retiran por
construcción, pero nadie lo ha grepado tras los preps — comprobar antes de contar con él).

## 2. Huérfanos y piezas sin dueño (estado + cuándo tocan)

| Pieza | Dónde vive | Estado | Toca en |
|---|---|---|---|
| G9 — modo final del DT (`Fixed dependency cycle(s)` display↔clock-controller; arreglo fino H1) | NOTAS 14-oct 12:0x (una línea, sin diff) | Sin diff, sin dueño, sin criterio | Tras el asesino-post-bind; es el que adelanta card1 de 47 s a ~4 s |
| PPS dual S5a (`docs/historia/revision/PIPELINE-PANEL-20261014/s5a-pps-dual-link.diff`) | PIPELINE-PANEL-20261014/ | Parked, precondición "muerte más allá de `w4-done`" (S5 §4) — hoy ni siquiera hay prepare | Tras el primer DCS observado |
| NON_CONTINUOUS S6/H3 (`docs/historia/revision/PIPELINE-PANEL-20261014/s6-noncontinuous.diff`) | id. | Parked ciclo 4 de ENABLE-COMPARISON; medio-contrato LP11 (REVIEW-S6 NOTA-1) | Tras S2, con DCS en vuelo |
| G8/S2-pulso (`docs/historia/revision/PIPELINE-PANEL-20261014/s2-g8.diff`) | id. | Sólido pero detrás de power + pendiente re-ancla a control gemelo (REVIEW-S2 NOTA F) y condicionado a herencia (NOTA E) | Tras S3a |
| S3a reset 15 ms (`docs/historia/revision/PIPELINE-PANEL-20261014/s3a-reset15ms.diff`, generado por FINAL-INTEGRACION §2.4) | id. | Parked "inmediatamente después del veredicto S1" — veredicto que **no existe** (vci sin probar) | Tras el primer prepare (re-basar su criterio: su PASA pedía firma post-DCS) |
| S3b (ASIS/Hi-Z) / S3c (doble reset) | dentro de `docs/historia/revision/PIPELINE-PANEL-20261014/s3-reset-tddi.diff` | Aparcados por N-BLOQ + N-HERED (REVIEW-S3 §3-4); S3c solo si S3a sobrevive al 1er reset | Tras S3a |
| Reorden (a) `prepare_prev_first` → S3-futuro; (b) VID-tras-DCS → S4-funcional | Asignado en FINAL-INTEGRACION §1 C-1, **sin hunk en ningún diff** | Huérfano con dueño nominal pero sin artefacto | (b) tras E1/S4-DIAG con señal; (a) con G9 (toca el mismo secuenciado) |
| FASE-1-variante "rewrite-en-vivo" (1b/inherit-gate, `clk-rcg2.c:1437` incondicional) | CRITICA-L48 §3 (acotación) | Sobrevive a la cancelación de 1a/1c; sin diff, sin ciclo | Solo si `opp-rate=514M` + FALLA-BIND/POST con clocks implicados |
| ktz-undup (`docs/historia/revision/PIPELINE-PANEL-20261014/s6-ktz-undup.diff`) | id. | Higiene con criterio propio; ciclo dtbo propio futuro | Cuando sobre una escritura de dtbo (acompaña a G9) |
| B1 (enable-gpios/supplies KTZ: cadena LED solo con camino de encendido) | NOTAS 14-oct 00:4x (contexto L45) | Abierto, sin diff | Con la primera prueba de luz (PASA-MODESET) |
| modetest userspace | CRITICA-L47 §3.2 (comandos) | Pre-autorizado solo-en-PASA; nunca intentado | En el primer boot que viva >6 min |
| S4-DIAG extendido (ACK/PHY/CLK, REVIEW-S4 N4) + 2 pokes suspend (ya en `l48-migas-susp.diff`, aplicados al árbol según `bff4c17`) | árbol (`K48-dpu-susp` en `dpu_kms.c:1459`, `K48-mdss-susp` en `msm_mdss.c:446` — verificados hoy) | Susp aplicados pero **nunca medidos** (L48 fue el primer flash con ellos; sus dumps rotaron) | Re-run L48 los mide gratis |

## 3. El siguiente cuello de botella y los próximos 4-6 ciclos

**Cuello real**: el asesino post-bind (muerte sin tráfico DRM, tras `Initialized`, en ventana
de clocks/GDSC ya resueltos por `sync_state`). Candidatos vivos (L48-PREP §2 C2/C3/C5/C6):
VBIF reescrito sobre scanout ABL, GDSC/MMCX, actor diferido-no-DRM (sddm/servicio tardío),
flaky/entorno. **E6 (las migas movieron la muerte 50 s → 5-11 min) vs flakiness está sin
dirimir** — y mientras no se dirima, la presunción "instrumento inerte" no es utilizable para
futuros ciclos con crumbs.

| # | Ciclo | Contenido | Criterio / cierra | Coste |
|---|---|---|---|---|
| 1 | **Re-run L48** (misma imagen `0b1d22c4…`, nada nuevo que compilar) + **dumper-v3** (boot-id, 0 escrituras, vía SSH) + **ACM commiteado** (`out/acm-L48*.log`) | Dirime E6-vs-flaky (¿reproduce 5-11 min o vuelve a 50 s?); registra el **valor de `K48-opp-rate`** (cierra FASE-1a/1c en vivo); mide `susp-ok` (¿clocks ON/OFF post-bind?); captura el contexto del boot largo | 1 escritura |
| 2 | **Caza del actor post-bind** (lectura del ciclo 1, 0 escrituras nuevas si el ciclo 1 da `alive`+`L6-open`/sddm; si exige migas nuevas, 1 escritura) | `L6-open` post-bind ⇒ pista GPU/GMU; `atom-tail` ⇒ FALLA-COMMIT (enable-path del commit); `post-init` sin commit ⇒ FALLA-POST (sddm/servicio/GDSC) | 0-1 escrituras |
| 3 | **PASA → modetest** (0 escrituras, pre-autorizado CRITICA-L47 §3.2 + PASA-MODESET CRITICA-L48 §4.1) | Primer `prepare()` real ⇒ voto vci ⇒ veredicto S1 (PASA/FALLA de `docs/historia/revision/PIPELINE-PANEL-20261014/s1-vci.diff` §4) ⇒ DCS ⇒ S4-DIAG por fin habla | 0 escrituras |
| 4 | **S3a** (15 ms, `docs/historia/revision/PIPELINE-PANEL-20261014/s3a-reset15ms.diff`, parked) | Peldaño 2 de la escalera; criterio re-basado a firma post-DCS (REVIEW-S3 D6/D7) | 1 escritura |
| 5 | **S2-pulso** con control gemelo misma sesión | Criterio endurecido secuencia/punto-de-parada (REVIEW-S2 §6) | 1 escritura |
| 6 | **s5a → H3** solo con DCS en vuelo | Sus precondiciones por fin cumplibles | 1+1 escrituras |

**Sin sentido todavía** (flashearlos hoy quema ciclos sin atribuir): s5a, H3/S6-noncontinuous,
S2, S3 (completo o S3a), ktz-undup como diagnóstico, FASE-1-sow (muerta salvo `opp-rate≠514M`),
modetest fuera de PASA, G9 antes de que el bind sobreviva de rutina, cualquier variable sobre
el link DSI (el modelo "enlace mal configurado" sigue agotado: G4/G5/G6/G7 cerrados).

## 4. Huecos de método (qué instrumentación/evidencia falta; qué gates fallaron)

1. **Dumper-v3 sin aplicar** (docs/historia/ESTADO-VIVO.md:24-25, SSH caído al intentarlo). Los dumps se
   nombran por uptime y **rotan entre boots**: la evidencia H2 original solo sobrevive en el
   blob `976f714` + `out/h2-dumps-l46/` (restaurado en `bff4c17` — bien), pero los dumps L47/L48
   ya se pisaron entre sí. Sin v3, el ciclo 1 del §3 vuelve a ser inatribuible entre boots.
2. **ACM sin commitear**: `out/acm-flash-20261014.log` termina en t≈9.5 s sin el boot L47
   (CRITICA-L48 §1.2); el "~50 s" de L47 y el "~5-11 min" de L48 son **testimonio del
   orquestador**, no evidencia archivada. Por la regla que la propia CRITICA-L48 impone
   (§1.2, §2.4-B), las ramas FALLA-POST de L47/L48 son hoy **INCONCLUYENTES**, no diagnósticos.
3. **Valor de `K48-opp-rate` sin registrar** (docs/historia/ESTADO-VIVO.md:26: "presente" el tag, pendiente el
   valor). El tag sin el número no cierra FASE-1a/1c; es medio-cierre.
4. **Gates excedidos de facto**: batería 3640 mV (L47) y 3447 mV (L48) bajo el gate 3700;
   ~6+ escrituras el 14-oct contra ≤2/día (CRITICA-L47 §3.3 lo declara eximido por el dueño,
   pero la exención vive en un informe, no en la fila del ledger — debe constar por ciclo).
   Slots: `a:6→0` quemado dos veces (H2 y L47/L48); el presupuesto `b<3 ⇒ solo lectura`
   (L48-PREP §6) no se evaluó por escrito.
5. **E6 herido**: L48 = L47 + migas "inertes" y la muerte se movió un orden de magnitud.
   O las migas no son inertes (~30 `pr_err` del baile mdss temprano + `delayed_work` nuevo,
   matiz que CRITICA-L48 §2.1 declara pero no cubre X9 s166/s167) o L47 fue flaky/entorno
   (C6: flash a 3640 mV, slot tocado). Ambas lecturas exigen el ciclo 1 del §3; ninguna
   permite seguir apilando crumbs como si fueran gratis.
6. **S4-DIAG transportado sin estrenar**: el harness viaja desde L46 pero ningún DCS ha llegado
   al host; dos ciclos pagando su coste de revisión sin una sola línea de señal. No es un error
   (criterio E1 sigue válido), pero su extensión N4 (ACK/PHY/CLK) no debe entrar sin señal previa.
7. **Pre-registro, bien**: filas #618-#622 con sha antes del flash + `readback` al tamaño exacto
   se cumplieron (NOTAS 14-oct). Lo que falla es la **post-captura**, no el pre-registro.

## 5. Contradicciones (estilo E1–E10 de la auditoría)

- **C1 (grave, orden).** FINAL-INTEGRACION §1 C-3 pone S1/vci primero ("sin rail analógico,
  ningún resultado de S3a/S2/S5a/H3 sería atribuible"). Con la muerte pre-prepare (H2/L47,
  posteriores al informe), el vci **no puede votar en ningún ciclo**: la dependencia de
  atribución sigue siendo cierta pero el orden operativo se invierte (bind ≺ vci-test).
  El informe era correcto contra la muerte-en-DCS; con la muerte-en-bind, su orden quema
  ciclos esperando un veredicto S1 inalcanzable. **Reescribir el orden, no el análisis.**
- **C2 (inventario).** NOTAS 14-oct 14:4x resume L48 como "boots de ~5-11 min", pero
  `out/h2-dumps/` contiene `uke-1015…uke-2530.txt.gz` (listado `ls` de hoy: uptimes de
  ~17 a ~42 min). O esos dumps son de la serie control L45 mal archivada junto a los de L48,
  o algún boot vivió ~42 min y el resumen es falso. **El inventario por boot (qué dump es de
  qué boot) no existe** — es exactamente el hueco que v3 debía cerrar, y contamina el veredicto
  "la muerte SE MOVIÓ".
- **C3 (stale).** `docs/historia/revision/PIPELINE-PANEL-20261014/MANANA.md:7-9` deja la tablet en "L45 + s286 cargando"; el estado real es
  L45 + **s287** (s286 no volverá salvo rollback). El fichero de la mañana quedó caducado por
  el día sin banner.
- **C4 (stale en árbol).** Los comentarios vci del driver (`panel-…o82-dualdsi.c:55-57`,
  `:301-303`, `:684`) dicen "el dtbo vivo aun no declara vci-supply" — falso desde s287.
  Cosmético, pero la próxima lectura de ese fichero tropezará.
- **C5 (premisa caducada).** BRIEF §Estado vivo: "Tablet viva por SSH". A la noche SSH caído
  (S1 §1:21, S6 §2.5, docs/historia/ESTADO-VIVO.md:25). Las secciones que dependen de SSH (re-medir L19,
  `of_node` 2-0011, dumper-v3) lo declaran; el BRIEF no debe citarse como estado.
- **C6 (criterio).** L48-PREP §5 PASA ("vive >6 min sin `atom-tail` ⇒ entorno") no nombra C6
  en FALLA-POST, y su "NO modetest" contradecía el PASA-MODESET que CRITICA-L48 §4.1 añadió
  después. El criterio vigente es el de 6 ramas (PRE-REGISTRO-L48.md), no el de 5 — citar
  siempre el segundo.

## 6. Lo que está bien (haber integrador)

El pipeline S1–S6 + 6 revisiones + 2 críticas es el mejor método del proyecto desde G4/G7:
cada diff con base de aplicación declarada (REVIEW-S6 NOTA-3 resolvió el lío de raíces),
cada exclusión con su nota (FINAL-INTEGRACION §2.2), disjunción verificada por aplicación
real en ambos órdenes (REVIEW-S1 §3, REVIEW-S5, REVIEW-S6 §5), erratas factuales cazadas con
fichero:línea (N1/D1/D2/A–D), rescate de evidencia H2 en `out/h2-dumps-l46/`, y dos ramas de
criterio que habrían quedado fuera (PASA-MODESET, triage `L6-open`). La cadena de hoy es
atribuible hasta el bind; lo que falta es todo post-bind, y está nombrado.
