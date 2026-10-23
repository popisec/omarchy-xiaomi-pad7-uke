# R7 — Auditoría escéptica de las filas #450–#461 (1–2 oct 2026)

**Rol**: revisor solo-lectura. No se ha editado nada salvo este fichero.
**Alcance**: filas #450–#461 de `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`
(leídas íntegras, 5901–6695), árbol `build/kernel-pokes/k18-tree`, `docs/historia/ESTADO-VIVO.md`,
`NOTAS-OMARCHY.md`, `docs/historia/revision/K24-diseno-desde-evidencia.md`,
`docs/historia/revision/PLAN-2OCT-pantalla-y-gpu.md`, `docs/historia/revision/R5-panel-dual-dsi.md`.
**Proyecto**: `~/proyectos/omarchy-uke`.

Convención de veredictos: **OK** (respaldada) / **MATIZ** (cierta pero Sobrestada o con
proveniencia débil) / **ERROR** (falsa o inferencia presentada como hecho).

---

## A. Auditoría de las 8 afirmaciones, una por una

### 1. «`uke_gmu_shared=1` era un no-op porque `gpu->vm` es NULL en `a6xx_gmu_init()`; fix UKE-K27» — **ERROR (mecanismo)**

El **hecho observado** (el mensaje `UKE-K20: gmu vm COMPARTIENDO…` no aparece nunca
pre-K27, ledger #459) es verosímil como lectura de log. Pero el **mecanismo que lo explica**
es incompatible con la cadena de llamadas del propio árbol:

- `adreno_bind()` → `info->funcs->init()` = `a6xx_gpu_init()`
  (`build/kernel-pokes/k18-tree/drivers/gpu/drm/msm/adreno/adreno_device.c:242`).
- Dentro de `a6xx_gpu_init()`, el orden es: `adreno_gpu_init()` (:2749) → bloque
  UKE-K27 (:2792) → `a6xx_gmu_init()` (:2808).
- `adreno_gpu_init()` termina en `return msm_gpu_init(...)` (`adreno_gpu.c:1252`), y
  `msm_gpu_init()` hace `gpu->vm = gpu->funcs->create_vm(gpu, pdev)` en
  `drivers/gpu/drm/msm/msm_gpu.c:974` — es decir, **el `vm` se crea DENTRO de
  `adreno_gpu_init`, ANTES de `gmu_init`**, no "después vía el op `.create_vm`" como
  dicen los comentarios UKE-K27 (`a6xx_gpu.c:2770-2776`, `a6xx_gmu.c:2791-2795`).

  El op `.create_vm` no es algo que ocurra "más tarde en el DRM core": es llamado
  sincrónicamente por `msm_gpu_init`. Salvo que `create_vm` fallara (y entonces el
  probe habría muerto en `msm_gpu_init`, sin llegar a `gmu_init`), `gpu->vm` **existe**
  cuando corre `a6xx_gmu_init`.

- Consecuencia: si el llamador K20 pasaba `to_msm_vm(gpu->vm)->mmu`, el `shared_mmu`
  **no podía ser NULL por ese motivo**. Que el mensaje UKE-K20 no saliera apunta a otra
  causa (p. ej. el call-site K20 pasaba NULL, o el `vm` fallaba antes) — causa que el
  ledger no aísla porque el árbol K20 intermedio no está preservado (solo existe el
  diff acumulado, que muestra el call-site pre-K20 de 2 args y el post-K27 de 4 args,
  sin el intermedio).

- Y hay evidencia **a favor de mi lectura dentro del propio ciclo K27**: el fix crea el
  mmu temprano con `msm_iommu_gpu_new()` y bajo s263 recibe `-EBUSY` (#460). Ese
  `-EBUSY` solo tiene sentido si el grupo **ya tenía dominio attachado** — es decir, si
  el mmu del `vm` creado en `msm_gpu_init` ya estaba ahí. El resultado de K27 **refuta
  la premisa "nada attachado todavía"** sobre la que se construyó el fix.

- Defecto adicional del fix (código, no medición): con K27 hay ahora **dos creaciones
  de mmu en el camino feliz** (una en `msm_gpu_init` vía `create_vm`, otra temprana en
  `a6xx_gpu_init`), y el consumo diferido en `adreno_iommu_create_vm()`
  (`adreno_gpu.c:205-213`) solo funciona si `create_vm` se llama exactamente una vez
  después. Frágil aunque no roto hoy.

**Veredicto**: el "no-op" como fenómeno observado queda en pie (MATIZ: n=pequeño, logs
no archivados — ver §D); el "porque `gpu->vm` es NULL" es **ERROR de mecanismo** y el
fix K27 puede estar atacando la causa equivocada. Antes de más ciclos "compartir",
hay que explicar por qué el mensaje K20 no salía **estando el `vm` creado** (mirar el
call-site K20 real, no el relato).

### 2. «Bajo s260 el GMU con dominio propio no puede mapear el icache@0x4000 → `-ERANGE`» — **MATIZ**

- Existe el camino de código (`msm_gem_get_and_pin_iova_range` → `-ERANGE`; el WARNING
  previo en `io-pgtable-arm.c:599 arm_lpae_map_pages` que cita #458 encaja con un fallo
  de mapeo real, no con un invento).
- Pero es **una observación (un arranque K25)** elevada a ley general ("no puede").
  Nótese además una tensión sin resolver: el `vm` del GMU se crea con rango
  `0x0..0x80000000` (`a6xx_gmu.c:2052`), donde 0x4000 **cabe**; el `-ERANGE` viene con
  pinta de geometría del dominio (`msm_iommu_new`, aperture), que el propio #461 deja
  como **PENDIENTE sin resolver**. Correcto como hallazgo, prematuro como cierre.
- Trazabilidad: la línea `gmu init ret=-34` se **cita** en #458 pero no hay captura de
  consola archivada con sha en `build/logs/` (solo `build-k25.log` del build). Ver §D.

### 3. «Bajo s263 el attach da `-EBUSY`; compartir grupo ⇒ solo un attach gana» — **OK (con matiz de n)**

- Medido **dos veces, en los dos lados del orden**: `-EBUSY` en el GMU (K26, #459) y
  `-EBUSY` en la GPU (K27, #460, en `msm_iommu_new` → `iommu_attach_device`,
  `msm_iommu.c:822-828`). Dos observaciones independientes con el mismo signo.
- "Solo un attach puede ganar" es semántica IOMMU correcta para un grupo compartido
  (GPU y GMU en SID 5 bajo s263). La premisa "mismo grupo" se apoya en
  `PRE-REGISTRO-PANTALLA.md:440` ("merge de GPU+GMU en el grupo 0, verificado vivo").
- Matiz: el ledger no cita la línea de código que forma el grupo por SID compartido;
  funciona como inferencia a partir de dos medidas coherentes. Suficiente para operar,
  insuficiente para citarlo como teorema.

### 4. «Bajo s260 compartir no ayudaría porque el CM3 (SID 5) no apunta al dominio de la GPU (SID 0) ⇒ s263 obligatorio» — **OK (inferencia sólida, proveniencia vieja)**

- Verificado en el DT del fork: GPU `iommus = <&adreno_smmu 0 0x0>` (SID 0,
  `palawan.dtsi:2381`), GMU `iommus = <&adreno_smmu 5 0x0>` (SID 5, `palawan.dtsi:2500-2501`).
- El razonamiento es correcto y es el punto más sólido del lote: el `S2CR` es **por
  SME/stream** (`S2CR.CBNDX` elige el CB), así que reutilizar el objeto `msm_mmu` en
  Linux **no re-apunta el stream del SID 5**. Bajo s260 el fetch del CM3 usa el
  SME del SID 5, no el dominio de la GPU; compartir el mmu no cambia ese camino.
  La conclusión "s263 es obligatorio **para que compartir sirva**" se sigue.
- Matices: (a) es inferencia desde DT + modelo del driver, no medición (el S2CR del
  SID 5 bajo s260 nunca se leyó con el decode corregido: el K23b no llegó a arrancar,
  `docs/historia/ESTADO-VIVO.md:32-37`); el valor S2CR TRANS→CB1 viene de evidencia anterior a
  estas filas. (b) "Obligatorio" significa "necesario para esta vía", no "suficiente":
  con s263 el grupo impide el doble attach (punto 3). El propio #461 lo dice, pero la
  frase aislada invita a leer "s263 = solución".

### 5. «El wedge es al soltar S3-rst0 (primer fetch), y NO es el volcado SMMU (K25 lo probó)» — **ERROR (la segunda mitad)**

- La localización en S3 viene de capturas de la era K13 (#447/#452: `S1-rst1 →
  S2-gen9 → fin`), **no de los ciclos K24–K27** (ninguno llegó a la escalera). Como
  localización histórica con n>1, aceptable — pero debe citarse su proveniencia, no
  presentarse como resultado de estas filas.
- **La afirmación "K25 lo probó" es falsa**: el propio #458 lo dice con honestidad
  ("este ciclo no puede confirmar ni refutar H2 — no se llegó a la escalera del
  CM3 porque el GPU no probea"). Un ciclo donde el GMU muere en `gmu_init ret=-34`
  **no testea** si el volcado entre S2 y S3 wedgea. Sin embargo
  `docs/historia/revision/PLAN-2OCT-pantalla-y-gpu.md` Pista B escribe literal: "y **no** es el volcado SMMU
  (el ciclo K25 lo probó: con el volcado apagado el GMU ni siquiera llega a la
  escalera)". Eso invierte el sentido: que el GMU no llegue a la escalera **invalida**
  el test, no lo supera. H2 sigue abierta exactamente igual que antes de K25.

### 6. «Panel dual-DSI; basta `status="okay"` en `phy@ae97000`» — **ERROR (suficiencia no probada; ya refutado en casa)**

- El propio proyecto ya contiene la refutación: `docs/historia/revision/R5-panel-dual-dsi.md`
  (líneas 20, 61, 63, 97 — verificado el fichero en disco) establece que: (a) el
  overlay vivo OVL **ya trae** `phy@ae97000` en `okay` (OVL:509) y el `disabled` citado
  está en el BASE **por diseño** (todo el display base va apagado; el enablement vive
  en overlay); (b) `okay` sin el cableado (relojes `iface`+`ref`, `vdds-supply`,
  assigned-parents al PLL de dsi0, bonded MASTER/SLAVE) **no basta**; con el OVL ya
  viene hecho; (c) el paso previo es C0 de **0 flashes**: leer el DT **vivo**
  (`/sys/firmware/devicetree/base/soc/phy@ae97000/status`), no el BASE.
- `PLAN-2OCT` Pista A no cita a R5, propone editar `palawan.dtsi` (DT base del kernel,
  que **ni siquiera es el DT que arranca** — arranca vendor+dtbo), y usa la palabra
  "basta". Triple problema: suficiencia falsa, capa equivocada (base vs overlay/vivo),
  y revisión interna ignorada. El `dsi_get_phy: phy driver is not ready` medido en #452
  es además compatible con deferral transitorio, no solo con `disabled`.
- Veredicto: la observación dual-DSI es OK; la prescripción es ERROR.

### 7. «`uke_keep_boot` solo aplica a apps-smmu ⇒ el `-EBUSY` no viene del bootloader» — **OK**

- Verificado en código: `uke_smmu_es_apps()` exige `reg == 0x15000000`
  (`arm-smmu.c:141-147`); cualquier otro SMMU recibe reset completo de mainline
  (`:314-315`). El kgsl-smmu vive en `0x3da0000`, luego el keep no lo toca. El
  comentario de la línea 217 lo documenta igual.
- El descarte del dominio heredado vía *este* mecanismo es correcto. (Alcance: es el
  único mecanismo keep del árbol; no hay otro que refutar.)

### 8. «Corrección: el GMU SÍ tiene `iommus = <&adreno_smmu 5 0x0>`» — **OK (ejemplar)**

- Verificado: `palawan.dtsi:2500-2501`. La retractación en #460 (gate de `dtc`
  `duplicate_property_names` cazando la lectura incompleta, script `mkdtbo-s264.py`
  borrado, `palawan.dtsi` verificado idéntico a HEAD) es exactamente cómo debe
  corregirse un error: con el instrumento que lo cazó, sin tocar la tablet, y
  marcando qué cae (s264 innecesario) y qué queda en pie (puntos 1–4 listados).
- Único pero: la lista "lo que queda en pie" incluye el punto 1 con el mecanismo
  erróneo del §A.1 — la retractación no alcanzó a la premisa `vm==NULL`.

---

## B. Contradicciones internas de #450–#461

1. **Resueltas con honestidad (no son problema, constan como evolución)**:
   - K24 "cerrado por refutación" (#456) → "cerrado con causa raíz" (#458). Revisión
     explícita, aceptable; pero un lector que entre por #456 se lleva la versión
     superada. (Mismo patrón que el doc K24 §3/§4 con banners — ver §C.)
   - "s263-sobre-vive" (#448, citado en #454) → degradado a hipótesis con confounds
     (#455-D1). Bien degradado; **pero** #461 no revisita si K26/K27 aportan algo a
     esa matriz (K26+s263 murió por -EBUSY antes de la escalera: también covariante).
   - "slot b intacto como rollback" → corregido en #454/#455. #461 no lo repite. Bien.

2. **No resueltas (sí son problema)**:
   - **#452 vs #461 sobre `uke_gmu_shared`/s260**: #452 (NOTAS y ledger) dice "desajuste
     real pero NO explica el wedge; el fallo es el mapeo en CB". #461 dice "s263 es
     obligatorio". El cambio de posición es legítimo (llegó evidencia), pero **ninguna
     fila marca la posición de #452 como superada**; un lector que combine ambas
     concluye "s260+s263 a la vez".
   - **#456-P4** ("con `hung_task_panic=0` el wedge cuesta 1 retry") se verificó en #457
     (retry 7→5 = 2 consumidos) — bien. Pero #452 atribuía el quemado del slot b al
     panic-reboot de `hung_task_panic=1` como hecho, cuando #454 ya había establecido
     que el ABL consume reintentos con o sin panic ("mitiga, no protege"). La
     atribución causal de #452/#453 ("el wedge quemó el slot vía panic-reboot") sigue
     sin el matiz #454. Menor, pero es la tercera vez que este matiz se pierde.
   - **La premisa `vm==NULL`** sobrevive intacta desde #459 hasta #461 pese a que el
     propio resultado de #460 (`-EBUSY` en creación temprana = grupo ya ocupado) la
     pone en cuestión. Ninguna fila la reexamina. Es el hilo que más urge tirar.

## C. Documentos de estado: lo obsoleto que sigue pareciendo vigente

1. **`docs/historia/ESTADO-VIVO.md` (cabecera: 1-oct 19:35) — obsoleto por omisión completa.**
   No contiene nada de #456–#461: ni K24/K25/K26/K27, ni `-ERANGE`/`-EBUSY`, ni el fix
   K27, ni la restauración #461, ni las 7 escrituras. Su "Plan FINAL" (paso 1:
   `uke_gmu_shared=0` bajo s260) **ya se ejecutó y falló** (K24: el GPU ni probea,
   #456) — prescribirlo hoy es prescribir un experimento refutado. Su tabla dice
   "slot b … NO tocar" y "slot a ACTIVO K13-dsid" — coincide con #461 por suerte,
   no por actualización. **Reescribir entero, no parchear.**

2. **`docs/historia/revision/K24-diseno-desde-evidencia.md` — los banners de §3/§4 NO bastaron.**
   - §1–§2 citan como evidencia la captura del 18:12, que la propia auditoría C3/E4
     (dentro del mismo documento, §5a) establece que la hizo **un kernel anterior al
     K19 que no contenía la instrumentación citada**. Las secciones de "evidencia"
     describen un kernel que no se colgó — y no llevan banner.
   - §4 ("con s263 la máquina sobrevive") sigue redactado como hecho operativo
     ("Consecuencia operativa (la más valiosa)") aunque §5d-D1 lo degrada a hipótesis;
     el banner SUPERADA solo cubre §3 y la segunda mitad de §4… no: cubre §3 y el
     bloque bajo §4 no tiene banner propio salvo el de §5 ("SUPERADO por §5b/§5c").
     Un lector en diagonal ejecuta §4.
   - §5b (el plan `shared=0`) **se ejecutó** (K24) con resultado negativo y §5c se
     ejecutó parcialmente (K25 no decisiva). Ninguno está marcado como
     ejecutado-con-resultado. El documento hoy propone lo ya probado.
   - Falta un banner de cabecera: "HISTÓRICO tras #456–#461; vigente = ledger".

3. **`NOTAS-OMARCHY.md` — sin entrada para 1–2 oct.** La última es "1-oct 19:3x".
   Todo el ciclo K24–K27 (el de más escrituras del proyecto en 48 h) no existe en la
   bitácora. La regla de protocolo (docs/historia/AGENTS.md: actualizar al terminar) se incumplió.

4. **`docs/historia/revision/PLAN-2OCT-pantalla-y-gpu.md`**:
   - Pista A: ver §A.6 (ERROR). No referencia a R5. Debe archivarse o reescribirse
     con R5 como revisión gobernante y C0 como paso previo.
   - Pista B: ver §A.5 (K25 no probó H2); tabla de 4 configuraciones sin n ni
     procedencia de cada medida; premisa `vm==NULL` sin marcar como inferencia.
     El "próximo trabajo (0 flashes)" es lo único que sigue válido tal cual.

5. **`docs/historia/revision/R5-panel-dual-dsi.md`**: correcto en contenido (verificado por encima), pero
   **huérfano**: nada lo enlaza (PLAN-2OCT, NOTAS y ESTADO no lo citan — grep vacío).
   Una refutación sin enlace es como no existir.

## D. Lo que el ledger NO registra (huecos de memoria)

1. **Procedencia del dtbo s263.** `s263-boot-dtbo-gpu-sid5.img` (`fe06fccc…`) está
   pre-registrado y en `SHA-BUENOS.txt:56`, pero **no hay constructor versionado**:
   ningún `mkdtbo-s26x.py`/`s2*.py` en `build/bootimg/` lo menciona (grep vacío) y
   ningún `.py` en `build/` lo genera. Si se construyó a mano o fuera del repo, viola
   la regla "tooling, nada a mano" que el propio #456 se dio. Un dtbo que decide dos
   ciclos (-EBUSY ×2) debe ser reproducible desde el repo.
2. **Capturas de consola de K24/K25/K26/K27.** En `build/logs/` hay `build-k24.log`,
   `build-k25.log`, `build-k27.log` (del build) y el viejo `console-cm3-wedge-1818.log`
   (era K13), pero **ninguna captura del arranque** donde salen `ret=-34`, `ret=-16`
   (×2) y `UKE-K27...-16`. Las tres líneas-load-bearing del ciclo existen solo como
   citas en el ledger. Tras el precedente #428→#429 ("consola que pierde la cola" →
   "sin errores" falso), archivar la captura con sha no es opcional.
3. **Escrituras por `e2fsck -y`.** #450 y #457 reparan userdata con `-y` (escribe
   bloques: 1347 multi-reclamados, bitmaps, contadores). La contabilidad de "7
   escrituras" (#461) cuenta solo flashes. Convención aceptable, pero debe hacerse
   explícita: **un `e2fsck -y` es una escritura al rootfs** (y en #450 dejó el sistema
   en mal estado vía máscaras persistentes — precedente de que "reparar" también
   rompe).
4. **Coste de reintentos por ciclo.** Solo #457 y #461 anotan retry antes/después
   (7→5 una vez). Para K25/K26/K27 (ciclos en bucle) no hay lectura sistemática de
   `slot-retry-count` por ciclo. Con el historial de slots quemados, cada ciclo
   debería cerrar con los 4 contadores.
5. **Decisión "s263 es obligatorio" (#461) sin experimento que la sostenga.**
   Es inferencia desde §A.4 (correcta) pero ningún ciclo probó K27+s260 ni
   compartido-bajo-s260 -ERANGE-con-fix. El ledger lo presenta dentro de "ESTADO
   DEL CONOCIMIENTO (honesto)" — bien etiquetado — pero PLAN-2OCT lo hereda ya como
   premisa dura.

## E. Contabilidad de escrituras

- **La suma cuadra**: K24 (1, #456) + restauración (1, #457) + K25 (1, #458) + s263
  (1, #459) + K27 (1, #460) + par bueno (2, #461) = **7** ✓. Cada fila describe su
  escritura con sha pre-registrado ✓. El ledger hermano tiene una entrada por ciclo,
  sin huecos (#450–#461 contiguas) ✓.
- **Ambigüedad de "hoy"**: #453 consumió "2/2 del día" el 1-oct; #456–#461 caen la
  noche 1→2 oct y #461 totaliza 7 "de hoy" excluyendo #453. Si "día" es natural,
  el 1-oct llevaría 2+5=7 y el 2-oct 2; si es "sesión overnight", 7. En ambos casos
  **todo está cubierto por la exención ilimitada del dueño (#456, cita literal)**,
  así que no hay incumplimiento — pero la exención cubre el cómputo y el ledger
  debería fijar el criterio (sesión vs día natural) para que el "≤2/día" siga siendo
  auditable cuando la exención expire.
- **Autocrítica registrada**: #444 ya discloseó flashes fuera del ledger (rachas
  Arch/Ubuntu) — anterior a estas filas, no se repite en #450–#461. Consta como
  precedente vigilado, no como reincidencia.

## F. Seguridad de datos y semáforo inter-proyecto

- **Particiones escritas en #450–#461**: solo `boot_a` y `dtbo_a` (slot experimental
  de omarchy-uke). Ni `boot_b`/`dtbo_b`, ni `vendor_boot`, ni `misc`, ni GPT, ni
  `super`, ni bootloader. ✓
- **userdata**: solo `e2fsck` (reparación, #450/#457), no reemplazo. Y userdata es
  actualmente el Arch de omarchy-uke (#444, con GO del dueño y aviso al hermano),
  no el Ubuntu del origen. Sin daño cruzado en estas filas. ✓
- **Semáforo**: el hermano está dormido desde #443; cada ciclo cita GO del dueño
  (#456 ilimitado + método SMMU explícito; #459/#460 "haz el fix y sigue"). Sin
  sesión viva concurrente que pisar. ✓
- **Riesgo latente (no materializado)**: #461 deja la tablet operativa pero el par
  bueno vive en **ambos** slots solo de nombre — `b` sigue `unbootable` desde #452
  (solo se rehabilitó `a` en #453 y se reescribió `a` en #461). Si el próximo ciclo
  quema `a`, quedan **cero slots arrancables** (ya advertido en #455-D2, sigue
  vigente). No es un error del ledger — es el estado real y está escrito — pero debe
  encabezar cualquier GO futuro.

---

## Los 5 cambios de documentación más importantes (priorizados)

1. **Reescribir `docs/historia/ESTADO-VIVO.md`** (hoy prescribe un experimento ya refutado y omite
   7 escrituras y 3 resultados negativos). Nuevo contenido mínimo: par vigente
   verificado #461, resultados K24/K25/K26+K27 en una tabla con n y procedencia,
   próximos pasos (H2 exige que el GMU llegue a la escalera; nada de `shared=0`
   otra vez sin hipótesis nueva), y el aviso de cero-slots-arrancables en cabecera.
2. **Cabecera HISTÓRICO en `docs/historia/revision/K24-diseno-desde-evidencia.md`** + banners en §1/§2 (C3:
   evidencia de un kernel que no corría), §4 (hipótesis, no hecho) y §5b/§5c
   (ejecutados: K24 negativo, K25 no decisivo). Los banners de §3/§4 no bastaron.
3. **Archivar o reescribir `PLAN-2OCT` Pista A** con R5 como revisión gobernante:
   quitar "basta", cambiar la capa (DT vivo/overlay, no `palawan.dtsi`), y poner el
   C0 de 0 flashes como paso previo obligatorio. Enlazar R5 desde PLAN-2OCT, NOTAS
   y ESTADO (hoy huérfano).
4. **Corregir `PLAN-2OCT` Pista B**: K25 no decidió H2 (citar el propio #458); marcar
   `-ERANGE`/`-EBUSY` como n=1/n=2 con capturas pendientes de archivar; y degradar
   "gpu->vm es NULL" a hipótesis en tensión con `msm_gpu.c:974` — o refutarla
   mirando el call-site K20. Sin esto, el próximo fix volverá a construirse sobre
   la premisa que K27 ya puso en duda.
5. **Añadir la entrada 1–2 oct a `NOTAS-OMARCHY.md`** (ciclo K24–K27, 7 escrituras
   con exención, restauración #461, estado del conocimiento) **y** registrar la
   procedencia del s263 (constructor o admisión de construcción manual) + archivar
   con sha las capturas de consola de K25/K26/K27. Sin esto, la trazabilidad de
   `-34`/`-16`/`-16` depende solo de citas.

---

### Nota final del auditor

El ciclo #450–#461 es, con diferencia, el mejor documentado del proyecto (predicciones
pre-registradas P1–P16, retractación #460 ejemplar, contabilidad que cuadra, GOs
citados). Los errores señalados son de **mecanismo no verificado** (§A.1), de
**alcance de una prueba** (§A.5) y de **suficiencia** (§A.6) — no de fabricación: en
los tres casos la evidencia primaria existe y el ledger la cita con honestidad en
algún punto. El riesgo real no está en lo escrito, sino en lo que **falta por
escribir**: ESTADO-VIVO desactualizado, R5 huérfana, s263 sin constructor y tres
líneas de log sin captura archivada. Quien siga sin leer este informe repetirá K24.
