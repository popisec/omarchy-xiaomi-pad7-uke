# CRÍTICA-W6-HIPÓTESIS — auditoría de la cadena D1/D2/D3 (2026-10-09)

> Solo lectura. Tablet en fastboot/colgada, PROHIBIDO flashear. N=1 por kernel.
> Hechos: ledger #553 (k65 D1+D2+D3 → silencio 4 min, 0 bytes), #554 (k52b2+s273
> arranca por SSH; **k64 nunca se flasheó**; s273 inocuo-efecto-principal), #555
> (k66 D1+D2 sin D3 → silencio 6+ min), #556 (k67 D1 sin D2 ni D3 → silencio 4+ min).
> Dtbo s273 constante en los 3 flashes. Verificación binaria propia de esta
> auditoría (Image descomprimidos, 41490944 B los 4): k52b2 = 0×K64/0×D1-D3;
> k52-build(=k64) = K64×3 + register_config; k65 = +K65×3; k66 = K66 D1/D2 +
> SIN-D3 + poll-vendor + G10×2 + G8; k67 = K67 D1 + SIN-D2 + SIN-D3 + poll + G10/G8.
> Orden en resume (parches): D1-set_rate → D2-set_rate → [D3] → pr_flush →
> `clk_bulk_prepare_enable` (común) → writes/S1-reset/K64-register_config.

## 0. Hipótesis refutadas DE VERDAD (se sostienen)

- **R1. "D3 vota CX LOW_SVS".** Refutada en fuente (W3 §1a, no necesita flash):
  el pm_domain del GMU son GDSC sin `set_performance_state` → no-op por construcción.
- **R2. "El oops-D3 es la explicación ÚNICA/NECESARIA del silencio".** Refutada por
  #555: k66 sin D3 en binario (gate negativo) calla idéntico. El *mecanismo* del oops
  en k65 sigue siendo posible; lo muerto es su *necesidad*.
- **R3. "s273 causa el silencio".** Refutada por #554: k52b2+s273 arranca (SSH, card0).
  Solo efecto principal; la interacción s273×kernel queda viva (ver C1).
- **R4. "D2 es necesario para el silencio".** Refutada por #556: k67 sin D2 calla igual.
- **R5. "k66 difiere de k65 en una sola variable".** Refutada por lectura de diffs:
  k65→k66 cambia CUATRO cosas (D3 fuera + poll-vendor + G10-chipid + G8-log).
  Válidos como parejas 1-variable: k64→k65 (solo diff-k65) y k66→k67 (solo D2 fuera).
- **R6 (premisa, no hipótesis). "k64 daba USB/consola".** Falsa: #554 reconstruye que
  k64 nunca se flasheó (#550b era inferencia). Todo "muere ANTES que k64" cae con ella.

## 1. Inferencias DÉBILES con su fallo exacto

- **W1. "D3 EXONERADO" (#555). Fallo: confunde ¬necesario con inocente.**
  k66-silencio prueba que el silencio es posible sin D3 (D3 no necesario), NO que D3
  no matara a k65. Con 4 variables cambiando a la vez, el escenario de dos asesinos
  (D3 mata k65, otro mata k66 — sobredeterminación) es compatible con todo lo observado.
  Formulación válida: "D3 exonerado como causa única/necesaria; como causa suficiente
  en k65 sigue vivo".
- **W2. "D2 EXONERADO" (#556). Fallo doble: (a) el mismo que W1** (k67 prueba
  ¬necesidad, no inocencia); **(b) enmascaramiento por orden.** D1 corre ANTES que D2
  en k65/k66; si la muerte está en `D1-set_rate` o justo después, D2 nunca llegó a
  ejecutar en esos flashes y su letalidad-cuando-se-alcanza vale ~0 información.
  k68 (D2-solo) sigue siendo obligatorio para probar suficiencia de D2.
- **W3. "D1 sospechoso nº1" (#556). Fallo: confusión perfecta D1×K64.**
  D1 y K64-register_config co-ocurren en los 3 silencios y co-ausentan en el único
  que arranca (k52b2: verificado 0×K64, 0×D). K64 jamás ha probado estar vivo
  (su único kernel, k64, nunca se flasheó). Atribuir a D1 exige suponer K64 inocente
  sin una sola medición que lo respalde. D1 es *candidato*, no nº1.
- **W4. Baseline k63/k64 (W3 §0).** k64 inexistente como medición; de k63 (el que
  estaba en A a las 02:50) no hay conducta USB documentada. Comparar tiempos de
  muerte contra un control no medido no es evidencia.
- **W5. "Cero bytes ⇒ muerte sin testigos".** La consola observada es el gadget ACM
  (vive tras enumerar USB, muy posterior a resume). Los testigos van con pr_flush a
  pstore/UART, que sobreviven al cuelgue — **y el pstore jamás se ha leído** en esta
  oleada. Ausencia de bytes ACM ≠ ausencia de testigos; la localización de la muerte
  (en-D1 / en-enable / post-testigo) está sin medir teniéndola a un reboot de distancia.
- **W6. Ranking D2>D1 (W4 §2).** Mecanismo plausible (AHB-a-200M-sin-CX vs PLL1
  dedicado) pero sin medición; como heurística de orden (k67-barata primero) fue
  correcta y es inofensiva. No usarla como veredicto.

## 2. Confusores no controlados (todos vivos)

- **C1. dtbo s273 constante.** Efecto principal controlado (#554), interacción NO:
  s273-"gmu-map" decide si la tabla OPP existe (condición del oops-D3) y trae F1+F2
  experimentales. Interacción s273×(D1/D2/K64) sin estimar.
- **C2. ABL/reintentos/BCB.** Solo boot_a flasheado; retries 7:7→6:6 a la deriva,
  flags successful, posible BCB/misc persistente entre ensayos. Sin reset ni
  misc-wipe registrado por ensayo, el camino ABL difiere entre k65/k66/k67.
- **C3. n=1 secuencial sin réplica ni intercalado.** Orden fijo k65→k66→k67 confunde
  con batería (4025→4013→4018 mV), térmico, cargador y hora. Un silencio podría ser
  estado (batería/thermal/ABL) y no kernel. Sin k52b2-intercalado no hay cómo saberlo.
- **C4. Orden D1-antes-D2.** Ver W2b: muerte temprana en D1 deja a D2 sin ejecutar;
  los testigos D2 nunca discriminan nada en k65/k66.
- **C5. Enable-path común intacto.** `clk_bulk_prepare_enable` + gmu R/W + S1-reset +
  writes K64 (+RSC) corren DESPUÉS de los rates en los 3. Cualquier asesino ahí
  reproduce exactamente "silencio idéntico al quitar D3/D2". Nunca variado (plan-C
  de K68 §4: enables diferidos tras USB — sin ejecutar).
- **C6. K64/enable nunca aislados** (desarrollo en §3).
- **C7. Cmdline/cmdline-append y cpio idénticos** (580 B =k64, K22): bien constantes,
  pero vuelven el diseño ciego a cualquier bug que viva ahí (constante compartida
  también puede ser la causa; p.ej. un token que cuelga con relojes nuevos).
- **C8 (menor). Ventanas 4/6/4 min y "cero bytes"** sin umbral pre-registrado de
  WDT/abotono; criterio de muerte por tiempo, no por evento.

## 3. La inferencia fuerte alternativa: el asesino puede ser K64 o el enable

Tabla 2×2 observada (P' = poll-vendor+G10/G8; En = enable-path; S = s273+cmdline+cpio):

| kernel | D1 | K64 | resto nuevo | resultado |
|---|---|---|---|---|
| k52b2 (ref, arranca) | — | — | — | SSH ok |
| k65 | D1+D2+D3 | K64 | — | silencio |
| k66 | D1+D2 | K64 | P' | silencio |
| k67 | D1 | K64 | P' | silencio |

Contraste arranca-vs-calla = (D1, K64, P', D2/D3) conjuntamente. D2/D3 eliminados
por R2/R4 (como necesarios). P' solo está en 2 de 3 silencios → P' no necesario.
Quedan **D1 ∧ K64 ∧ En ∧ S, cuatro sospechosos perfectamente confundidos**:
todo lo que "incrimina" a D1 incrimina igual a K64 y al enable.

- **K64, superficie de riesgo concreta** (INV-KGSL-RE §4): 17 escrituras vendor-only
  portadas del .ko con valores runtime ([x+0xb8], [dev-0x2d0], chipid<<8) cuyo contexto
  en mainline puede ser otro; RSCC 0x02003B11 + RSC-wake con poll; BOOT_CONFIG=2,
  SYS_BUS_CONFIG=1, FENCE-unlock — todo ANTES de S3, todo sin haber corrido vivo
  jamás. Un K64 que cuelga el bus/RSC da exactamente silencio pre-USB con 0 bytes ACM.
- **Enable, riesgo concreto**: levanta padres que XBL dejó en estado desconocido;
  el vendor hace antes cx_gdsc + ahb-timeout-detect + cx-timer-init (INV-KGSL-RE §1:
  pasos 2/4/5) que mainline no replica igual; el primer `gmu_write` tras el enable
  sobre AHB/CX a rates nuevos sin voto CX puede colgar el NOC = muerte SoC-wide.
  La muerte "por D1" y la muerte "por enable×D1" son indistinguibles sin el
  experimento de enables diferidos.
- **k68 no rompe este empate.** k68 = D2+K64+En+P' sin D1: si calla, candidatos =
  {D2, K64, En}; si habla, candidatos = {D1, K64×D1, En×D1}. En ningún desenlace
  separa D1 de K64. Útil contra D2, inútil para la pregunta de §3.

## 4. Discriminador mínimo (1 flash + 0-flash previos)

**Lecturas coste-0 antes de flashear:** (i) pstore/ramoops del estado colgado —
si aparecen `UKE-K67: D1…` / `SIN-D2` / `CM3DBG`, la muerte es POST-testigo
(enable/S1/K64, no el set_rate); si ni pstore los trae, la muerte es EN resume
temprano; (ii) golden-state en Android vivo (clk_summary/genpd) como referencia.

**El flash: D1-sobre-base-limpia.** Base = k52b2 (sin K64, sin P', poll/G10/G8
mainline) + SOLO `clk_set_rate(core,220M)` + testigo + pr_flush. Nada más.
Celda faltante del 2×2 (D1∧¬K64):

- **Calla igual → D1 SUFICIENTE.** K64 queda exonerado como necesario; "D1 asesino"
  confirmado (matiz: D1-solo incluye su interacción con el enable-stock, que es
  exactamente lo que se afirma).
- **Arranca (USB/S3) → D1 refutado como asesino-en-solitario.** El asesino exige
  K64 (solo o en interacción D1×K64); siguiente flash: K64-sobre-base-limpia
  (sin D1/D2) para cerrar K64-solo vs interacción.

**Por qué este y no otro:** es el único diseño de 1 flash que parte la confusión
D1×K64; parche mínimo (2 líneas, riesgo menor que K64 con 17 writes); misma
cmdline 580 B / dtbo s273 / slot boot_a; gates negativos (K64/D2/D3/poll/G10/G8
ausentes, POKE=113). **Controles del ensayo:** k52b2-intercalado antes/después,
retry+batería registrados, réplica n≥2 si calla, lectura pstore ADEMÁS de ACM,
stage=3 y luego stage=2.

## 5. Veredicto en una línea

Refutado de verdad: D3-necesario, D2-necesario, s273-suficiente, voto-CX-D3,
"1-variable k65→k66", "k64-daba-USB". Débil: "D3/D2 exonerados" (solo como únicos),
"D1 nº1" (empatado con K64 y enable). El siguiente flash que informa no es k68
sino **D1-sobre-k52b2-limpio**.
