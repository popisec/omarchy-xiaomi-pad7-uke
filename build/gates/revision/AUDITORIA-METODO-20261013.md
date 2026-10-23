# Auditoría de método e histórico — 13-oct-2026 (tarde)

Auditor escéptico, adversarial. Solo lectura + `git log`/`git show`. Sin kernel, sin flashes, sin tocar la tablet.

## 1. Veredicto en 5 líneas

1. **Sí, volver a L33 es lo correcto**: es el único punto con vida demostrada (SSH ~20 s) y el único desde el que cada variable posterior atribuye.
2. Pero **L33 no es "limpio"**: lleva `CONFIG_DRM_FBDEV_EMULATION=n` + cmdline sin `video=`, es decir, ya es un experimento respecto a la base; la escalera debe partir de él como *control definido*, no como "cero".
3. Lo que hay que hacer distinto: **un cambio por flash de verdad** (L39 llevó 4: G5+G6+L38-heredado+4×`=y`), **criterio pasa/falla escrito antes del flash**, y **grupo de control en la misma sesión** (como G4/G7, que es lo mejor del día).
4. **Congelar los flashes hasta leer el forklog de rescate**: el log de L39 puede estar ya en `/dev/sda30` y L33 es el que lo recoge; flashear antes de leerlo es tirar evidencia gratis.
5. El presupuesto está roto (ver §6): la escalera propuesta gasta ~1 escritura por peldaño y exige parar al primer "falla".

## 2. Errores de razonamiento, ordenados por gravedad

### E1. L39 = 4 variables en un flash, violando "un cambio por ciclo" (grave, estructural)
`L39-RESULTADO-20261013.md:61-68`: L39 cambia a la vez **G6 + G5 + L38-heredado (reset 15 ms, nunca flasheado solo) + 4 símbolos `=m→=y`**. Cuando el panel "emite luz" y el kernel muere antes de 3,5 s, **nada atribuye** (`L39-HALLAZGO…:101-105` lo admite: "no se sabe qué cambio lo provoca"). El commit `af1ae94` lo construye sabiendo que L38 estaba pendiente (`ea73892`: "NO existe ningún L39… violaría un cambio por ciclo") y lo hace igual.
Agravante: el `=m→=y` ya había wedgeado antes (bitácora: "cambio `=y` de config que wedgeaba") y se repite; luego se revierte en `5c82899`. Coste: 3 escrituras del día (F10+L39+L39d) para un resultado inatribuible.

### E2. "El panel emitió luz" tratado como avance sin log (grave, claim sin evidencia)
`L39-HALLAZGO-PANEL-LUZ-20261013.md:10-11`: testimonio del dueño, **ACM 0 bytes ×3 arranques** (`:23`). El propio `L39-RESULTADO…:29` dice "eso no es evidencia de ingeniería", pero el documento de hallazgo lo titula como hecho cerrado ("deja el hallazgo cerrado para que no se pierda", `:4`) y la historia posterior lo usa como premisa ("G4 es el candidato nº1", `L39-RESULTADO…:81-82`). Con `CONFIG_DRM_FBDEV_EMULATION=n` y sin `video=` **nadie pidió un commit** (`HALLAZGO…:35-36`): luz sin imagen = backlight/splash, no enlace DSI. El informe lo contempla (§4/§7: "luz sin imagen"), pero el titular sobrevive al matiz. Regla: testimonio ≠ dato; el veredicto honesto es "posible luz, sin log, sin atribuir".

### E3. El run-0-bytes de L41 atribuido a wedge de PHY, era batería (grave, casi cuesta un diagnóstico)
`VEREDICTO-G4-REFUTADO.md:33-36`: primer L41 dio 0 bytes y "se [atribuyó] a un wedge de PHY"; era **3233 mV con corte a 3150 (83 mV de margen)**. Con 3462 mV el mismo kernel arranca. Patrón repetido: L39 (0 bytes ×3) también se leyó como "muerte antes de 3,5 s" sin medir batería en el informe (slots al cierre dicen 3439 mV, `HALLAZGO…:110-112`, sin gate previo citado). La batería es variable confundente sistemática y no está en ningún criterio pasa/falla pre-flash.

### E4. Afirmaciones sobre capturas lossy presentadas como hechos (grave, recurrente, parcialmente autocorregido)
- "FIFO 8→12" inventado (`NOTAS-OMARCHY.md:3654-3666`, autocorregido: son 10/10/10 + `pr_err_ratelimited`).
- "El punto de muerte se movió porque ACM no mostraba K48-w4-done": FALSO, autocorregido en `af1ae94` (w4-done línea 284 < rst-R2-ok línea 295; si se ve lo segundo, lo primero corrió y lo perdió el ACM).
- Pero el hábito sobrevive: `HALLAZGO-MUERTE-DSI.md:49-52` ("sin pánico, sin watchdog… el kernel deja de emitir") infiere ausencia desde ACM, que es lossy por doctrina propia (`docs/historia/AGENTS.md:90-93`, regla 4: doble captura obligatoria). Y G4/G7 comparan **recuentos de reintentos** (5 vs 4, 7 vs 4) que el propio veredicto declara variables (`VEREDICTO-G4:17`, `VEREDICTO-G7:16-17`): correcto veredicto, pero la tabla invita a leer ruido como señal. Los veredictos G4/G7 son buenos *a pesar* de sus tablas, no gracias a ellas: lo que refuta es **secuencia + punto de parada idénticos**, no los conteos.

### E5. G4 `0xAA/0xAA` flasheado como hipótesis cuando la derivación estaba rota (medio-grave, autocorregido tarde)
`af1ae94` (commit message): "G4 NO entra: no se ha encontrado la instrucción que produce 0xAA, y la deducción desde `<0xa0a…>` está rota". Bien. Pero `HALLAZGO-MUERTE-DSI.md:65-69` había vendido G4 como "exactamente el síntoma medido" con fórmula `byte[0x12c]|byte[0x12d]<<4` → `0xAA`, y `b81f733` lo flashea (L41) sabiendo que `LANE_CFG1=0xAA` "no tiene respaldo — bajo bytes consecutivos daría 0x00" (`VEREDICTO-G4:28-31`). Flashear una hipótesis que el propio plan declara con la derivación rota es gastar un ciclo para confirmar lo que ya se sabía. El control es impecable; la decisión de flashearlo, no.

### E6. L33 vs L34+ declarados comparables cuando no lo son; L36 = 2 variables (medio, autocorregido)
`NOTAS-OMARCHY.md:3684-3703` (autocorrección): L35/L36 corren modo 60 Hz inexistente vs preferido ~120 Hz de L33; L36 cambia flush + early-return a la vez ("gate tautológico; quemó el termómetro video_done"). L34 "nunca se probó limpio" (sddm auto-arrancaba, `:49-50` del ESTADO). Consecuencia viva: el "punto de muerte BLANDO en K48-w4-done" (`INDICE §5b:124-127`) mezcla muertes medidas con muertes autoinfligidas. La escalera del §3 lo corrige fijando modo preferido siempre.

### E7. G1 sigue en los documentos como candidato cuando su premisa murió dos veces (medio)
`GAPLIST…:22-37` presenta G1 (skip VBIF) como "candidato nº1 a la muerte de L26 / de 4,03 s". Pero: (a) la muerte de ~4 s era fbdev auto-commit, eliminada por L33 (`ESTADO-VIVO:40-46`, `INDICE §5:106` marca G1 "REFUTADO como causa"); (b) el síntoma actual es FIFO/TIMEOUT en host-xfer, firma de enlace, no de VBIF (`INDICE §5:104-105` lo dice). El GAPLIST no lo dice y `INDICE §5b:129-133` vuelve a listar candidatos sin tachar G1. Documento refutado sin que el documento lo diga — justo lo que pedía la pregunta 3.

### E8. "G8 refutado porque el reset completa" va demasiado rápido (medio-leve)
`af1ae94` (commit message): "G8 NO entra: el log muestra que el reset COMPLETA, así que la premisa (fallo en power-up) queda refutada". Lo que completa es el **reset GPIO del panel por el host** (`rst-R2-ok`); G8 habla del **orden de CTRL_ENABLE y del pulso de 20 ms vs 1 µs**, que afecta a la PHY/host, no al GPIO. Que el GPIO complete no refuta un mal orden de enable del host. G8 sigue abierto (no probado), no refutado. Reclasificar: "aparcado", no "refutado".

### E9. Historia OPP contada de forma que parece contradicción (leve, de redacción)
Primero "FASE 1a/1c CANCELADAS: el OPP ya siembra 514 MHz" (`ESTADO-VIVO:64-70`), después "HALLAZGO PRINCIPAL: el OPP del host sube el link 26%" (`NOTAS:4075-4092`). Son **dos OPP distintos** (DPU 514 MHz vs host DSI 187,5 MHz) y no se contradicen, pero ningún documento lo dice en una frase; un lector ve "el OPP ya estaba bien" seguido de "el OPP era el bug". Una línea lo cierra (propuesta en §4).

### E10. Bitácora con hueco L39 + ESTADO-VIVO con capas contradictorias (leve, ya auditado)
`NOTAS-OMARCHY.md:4116-4126` (nota de auditoría): 3 escrituras sin entrada en bitácora; `docs/historia/ESTADO-VIVO.md:3-10` marcado caducado por el propio auditor. El mecanismo de autocorrección funcionó (se detectó y se marcó el mismo día). No es error vivo, es constancia de que el protocolo `docs/historia/AGENTS.md:137` se saltó bajo presión de flashes.

## Historia de "qué se cree que causa la muerte" (cómo evolucionó y dónde dejó de tener razón)

1. **Ronda BCR/reset (~0,5 s)**: `msm_mdss_reset()` 20 ms como asesino de la imagen (ledger #612). Convergencia de 3 vías, sin traza directa. **Dejó de tener razón** cuando L25 mostró que con BCR saltado el bind sobrevive (`ESTADO-VIVO:101-116`) y L33 vivió: el reset no mataba el SoC, mataba el splash.
2. **Ronda clocks/parked_cfg (~4 s)**: RCG compartido escribe 0. **Refutada en código** (`NOTAS:4031-4043`): `dpu_kms.c:1304` siembra al techo OPP antes de `hw_init`. La muerte de ~4 s era fbdev auto-commit (L33 la mata con `FBDEV_EMULATION=n`).
3. **Ronda panel-inherit/ESD**: ESD 86/87 como causa → refutada como síntoma (#610: 1 edge/línea, 36 ms de vida posterior). "L22 encendió" → sobreestimado (era ABL, `o82_prepare` salta antes de `backlight_enable`).
4. **Ronda commit/w4-done (L33→L37)**: punto BLANDO en `K48-w4-done`, pero L33-100 ms llegaba más lejos que L34+. La instrumentación (flush, early-return) **movió el punto que medía** (L36 quemó el termómetro). Desde aquí el proyecto mide su propio instrumento tanto como el hardware.
5. **Ronda OPP-host (F10)**: hallazgo real y verificado (148,645,532 Hz, conector a `connected` 3200x2136@120). Pero se narró como "el" hallazgo y **no movió el síntoma**.
6. **Ronda PHY/PLL (G5+G6+G4+G7)**: cada gap bien derivado del vendor, cada uno refutado o inerte con control. El síntoma `cmd#0 → FIFO → TIMEOUT → host-xfer → silencio` sobrevive a cinco configuraciones. **Aquí es donde hay que dejar de tener razón**: el modelo "el enlace está mal configurado" está agotado; lo que queda es "el panel no escucha" (reset real del TDDI nunca observado / dual-DSI / línea física) — que es exactamente lo que dice `VEREDICTO-G7:52-66`, el mejor párrafo del día.
7. **Ronda I2C (s284/s285)**: el intento de mirar desde el otro lado wedgea. Aislado a "probar los GENI por primera vez" (`VEREDICTO-WEDGE:27-28`). Riesgo: convertir "el I2C rompe" en nueva causa fetiche sin aislar cuál de los 7 fragmentos.

Lo stubbornly kept: **flashear antes de agotar la lectura** (forklog de rescate, OPP por debugfs, diff del fusionado) y **contar escrituras que el gate no permite**.

## GAPLIST: 10 gaps, estado real

| Gap | Estado real |
|---|---|
| G1 skip VBIF | **Refutado como causa** (muerte-4 s era fbdev; firma actual es de enlace). Queda como hardening. El documento no lo dice. |
| G2 tablas divisores PLL | No probado. Vivo pero subordinado: el byte_clk ya mide bien (148,645,532), así que su valor marginal bajó. |
| G3 bloque reset PLL | No probado. ~120 escrituras; riesgo bajo pero sin señal que lo pida. Aparcado. |
| G4 lane map | **Refutado con control** (L40 vs L41, misma secuencia y parada). Cerrar y tachar en GAPLIST e ÍNDICE. |
| G5 LANE_CTRL0 | Inerte (aplicado en L39, síntoma idéntico después). No tiene control limpio propio (iba empaquetado en L39): estrictamente "inerte en paquete", no "refutado solo". No re-probar solo: no hay señal. |
| G6 timings PHY | Inerte en paquete (L39). Igual que G5: no re-probar. |
| G7 SSC | **Refutado con control** (L40 vs L42). Cerrar. |
| G8 orden CTRL_ENABLE + pulso | **Abierto, mal clasificado como refutado** (ver E8). Siguiente candidato de configuración si la escalera lo pide, con criterio previo. |
| G9 DT completo en host | Abierto, trabajo ordinario, para el modo final. No es diagnóstico. |
| G10 segundo banco PLL | Abierto, solo dyn-refresh. Aparcado. |

Ruido: G1 como "candidato nº1" (premisa muerta), G4 como "exactamente el síntoma" con derivación rota, G2/G3/G10 sin señal que los pida. Bien fundamentados en origen todos (el RE es sólido); mal mantenido su estado.

## 3. La escalera incremental propuesta (desde L33, un cambio por peldaño, criterio prefijado)

Base: **L33** (`bc8b1ca6…`, slot a) + **s283** (`a8e7d4c0…`). Todo peldaño: mismo dtbo salvo que el peldaño sea el dtbo; modo **preferido** siempre (nunca 60 Hz forzado); doble captura (ACM durable + SSH); batería ≥3700 mV registrada antes; `set_active a` siempre. **Criterio general de parada**: al primer peldaño que no cumpla su "pasa", se para y se aísla; no se apila el siguiente.

| # | Peldaño (un cambio) | Pasa (prefijado) | Falla (prefijado) |
|---|---|---|---|
| 0 | **Leer el forklog de rescate** (cero flashes): flashear L33, a los ~20 s copiar `/mnt/rescue/forklog*.txt` antes del podado (carrera documentada `HALLAZGO…:89-92`) | Aparece log de L39/L40 (dmesg 0,6–3,5 s) o se demuestra vacío | Vacío demostrado → se registra y se sigue sin ese dato; no se re-flashea para buscarlo |
| 1 | L33 + **s283 recompilado = s283** (control de reproducibilidad, 1 escritura dtbo) | Log byte-comparable a `acm-L40b-s283.log.gz`: secuencia §8 de `HALLAZGO-MUERTE-DSI` idéntica, parada en `host-xfer` | No reproduce → la base se movió; parar, no subir la escalera |
| 2 | L33 + **reset 15 ms** (solo L38-variable, 1 escritura boot) | SSH ~20 s vivo + al lanzar commit: reset completa (`rst-R2-ok`) y `w4-done` presente en doble captura | Muerte antes de USB o cambio de firma → L38-variable refutada sola |
| 3 | Peldaño 2 + **PPS a los dos links** (`06708b1`, 1 escritura) | PPS ×2 en log; síntoma idéntico (se espera inerte: es corrección de corrección) | Cambio de firma → aislar |
| 4 | Peldaño 3 + **backlight-warn** (L40 una línea, 1 escritura) | `card1` existe, panel probea, síntoma FIFO/TIMEOUT idéntico | Sin `card1` → el warn no basta; no tocar I2C aún |
| 5 | Peldaño 4 + **G8** (orden CTRL_ENABLE + pulso, 1 escritura) | Criterio direccional prefijado: `status=4` desaparece o `cmd#0` recibe ACK (cualquier movimiento de firma cuenta como señal) | Firma idéntica → G8 refutado con control; se cierra la vía "configuración del enlace" |
| 6 | **s286** = s283 + GPI + **solo 1 bus I2C** (el del KTZ8866, 1 escritura dtbo, kernel del peldaño 5) | Arranca + `/sys/class/i2c-adapter` no vacío + KTZ une (`ktz8866@11`) | Wedge/0 B → ese bus aísla el wedge; probar el siguiente bus solo si el gate lo permite; **techo: 1 bus por flash** |
| 7 | Solo si 6 pasa: endurecer backlight + leer TDDI por I2C | ID del TDDI leído por I2C (observación del otro lado, primera vez) | Sin ID → el panel no sale de reset: el problema es reset/power, no DSI |

Notas: G5/G6 **no** se re-prueban (inertes en paquete, sin señal); G2/G3/G10 aparcados hasta señal; G1 solo como hardening al final, nunca como diagnóstico. Presupuesto de la escalera: peldaños 0 (cero flashes) + hasta 6 escrituras en días distintos (gate ≤2/día): **mínimo 3 días**. Si el gate no da, se hace solo 0–2 y se para.

## 4. Afirmaciones a borrar o reescribir

1. `INDICE-DOCUMENTACION.md` §5b:129-133 — lista G4 como candidato vivo ("Del RE, lo que sobrevive… **G4** lane map… → G8…"). **Reescribir**: G4 refutado, G7 refutado, G1 refutado como causa; candidatos vivos: G8 (abierto), observación por I2C. *(Corregido en este mismo commit: ver §7.)*
2. `GAPLIST-VENDOR-MAINLINE-20261013.md:22` — "G1… candidato nº1 a la muerte de L26". **Añadir**: refutado como causa (la muerte-4 s era fbdev; firma actual de enlace). Queda como hardening.
3. `GAPLIST…:53-57` (G4) — "puede ser por sí solo un no-arranque del link". **Añadir**: refutado con control 13-oct (L40 vs L41, `build/evidencia/G4/`).
4. `GAPLIST…:69-72` (G7) — gap abierto. **Añadir**: refutado con control 13-oct (L40 vs L42, `build/evidence/G7/`).
5. `L39-HALLAZGO…:1` — "El panel emitió luz. Y el kernel muere ANTES de los 3,5 s". **Reescribir titular**: "Posible luz (testimonio sin log) y muerte sin consola en 3 arranques; causa sin atribuir (4 variables en L39)".
6. `HALLAZGO-MUERTE-DSI.md:65-72` — "Eso apunta de lleno a G4… Es exactamente el síntoma". **Añadir**: refutado por control posterior (ver `build/evidencia/G4/`); la inferencia síntoma→lane-map era afirmación sin derivación completa.
7. `af1ae94` (mensaje, inmutable en git pero citado en docs): "G8… queda refutada". **Corregir en la escalera y en GAPLIST**: G8 aparcado, no refutado (ver E8).
8. `NOTAS-OMARCHY.md:4075-4092` (hallazgo OPP) — **añadir una línea**: "OPP del host DSI (187,5→148,65 MHz), distinto del OPP del DPU (514 MHz) que canceló la FASE 1; no se contradicen" (ver E9).
9. `docs/historia/ESTADO-VIVO.md` capas 12-oct/13-oct 00:3x — ya marcadas caducadas; **no borrar** (son historia), pero mover el aviso de cabecera a cada sección vieja si alguien las cita.

## 5. Lo que está bien (con nombre)

1. **Los grupos de control G4 y G7** (`build/evidencia/G4/`, `G7/`): mismo dtbo, misma tablet, misma sesión, predicción registrada antes del flash, veredicto que admite la refutación. Es el mejor método del proyecto en 39 rondas.
2. **El aislamiento del wedge en escalera s283→s284→s285** (`build/evidencia/WEDGE/`): dos cambios a la vez detectados, tercer overlay que los separa, veredicto "GPI inocuo, GENI culpable" con siguiente peldaño diseñado (s286). Manual de libro.
3. **La doctrina ACM-lossy + doble captura** (`docs/historia/AGENTS.md` regla 4): pagada con el falso "sin errores" del ledger #428→#429, aplicada para invalidar L26 (`1c3906c`) y para autocorregir w4-done (`af1ae94`). Pocos proyectos convierten un falso negativo en regla permanente.
4. **La autocorrección escrita con evidencia**: ACM perdió `w4-done`, "no existe la instrucción de 0xAA", falso "pantalla encendida", `=y` que wedgeaba, misc-que-no-limpia-slots (#P52), `0x16b`-colgante que era endianness (27-sep). Cada una con fichero, línea y commit. Inusualmente buena.
5. **El baselining L39b+s283 vs L40+s284** (`L39-RESULTADO:168-200`): "dos variables a la vez, el resultado no atribuye" escrito explícitamente, con experimento de separación diseñado. Honestidad atributiva en caliente.
6. **El techo de 3 ciclos y la regla un-cambio-por-ciclo**: existen, están escritas, y esta auditoría las invoca porque el día las violó; una regla que permite decir "violada" con cita es una regla que funciona.
7. **El ledger hermano como fuente de verdad externa** (`FLASH-LEDGER.md` #553–#612): pre-registro con sha antes del flash y medición después; cuando la bitácora calló (hueco L39), el ledger no.

## 6. Presupuesto (respuesta a la pregunta 6)

Gate: `docs/historia/AGENTS.md:114-119` ≤2 escrituras/día, batería ≥3700 mV, slots registrados. El 13-oct se hicieron **al menos 7 escrituras** (dtbo F10/s281, boot L39, boot L39d, boot L39b, boot L40, boot L41, boot L42, dtbo s284, dtbo s285 — 9 artefactos tocando flash según `git log` de hoy, 32 commits): **~4× el gate**.
Desperdicio exacto:
- **L39d** (`panic=10→600`): reflash de 96 MB para un knob que el propio informe (`L39-RESULTADO:106-109`) admite que no ayuda si la muerte es anterior al USB. Escritura con valor esperado ~0 declarado por adelantado.
- **El empaquetado L39**: G5+G6+L38+`=y` en un flash convierte hasta 4 escrituras futuras de aislamiento en deuda; el "ahorro" de un ciclo costó la atribuibilidad de todos.
- **s284 con 9 fragmentos**: viola un-cambio-por-ciclo en el eje DT; el aislamiento (s285) costó un flash que el diseño inicial habría ahorrado (1 bus por flash desde el principio).
- **L41-run-1 a 3233 mV**: flash bajo el gate de batería; resultado 0 B ininterpretable que casi se archiva como "wedge de PHY".
- **Flashes sin entrada de bitácora** (hueco L39): el coste no es la escritura, es la trazabilidad; obligó a una auditoría para reconstruir el día.

## 7. Corrección documental aplicada en este commit

`INDICE-DOCUMENTACION.md` §5b: lista de candidatos del RE actualizada al estado auditado (G4/G7/G1 refutados como causa, G8 abierto, vía I2C como siguiente observación). Un commit, sin kernel, sin flashes.
