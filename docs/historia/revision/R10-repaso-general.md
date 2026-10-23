# R10 — Repaso general R5–R9: qué se hace el lunes por la mañana

**Rol**: revisor senior solo-lectura. **Único fichero escrito: este.** Nada fuera de
`docs/historia/revision/R10-repaso-general.md` tocado. Tablet no tocada.
**Proyecto**: `~/proyectos/omarchy-uke`.
**Leído íntegro**: R5, R6, R7, R8, R9, `docs/historia/revision/PLAN-2OCT-pantalla-y-gpu.md` (versión reescrita 2ª vez),
`docs/historia/ESTADO-VIVO.md` (versión reescrita 2-oct ~03:1x), `docs/historia/gates-palawan/build-k30.sh`,
`docs/historia/gates-palawan/repack-k18.py`, ledger #450–#465 más R8 (hasta línea ~6924),
y extractos verificados de `build/kernel-pokes/k18-tree`
(`a6xx_gmu.c` share-branch/dump-gate/walk, `a6xx_gpu.c` orden init, `msm_gpu.c:974`).

**Hechos fijos asumidos** (dados por el encargo, no re-discutidos): tablet en fastboot, slot `a`
con par bueno K13-dsid+s260, `b` unbootable; #465 pre-registra `boot-ukek30.img`
(sha `d1c24835…`) = K27-revertido + `uke_gmu_shared=0` sobre s260, P20/P21/P22;
`-ERANGE` = TTBR1 (`io-pgtable-arm.c:599`); s260 = grupos IOMMU 0 y 1 distintos;
s260 arranca con red aunque el GMU falle; quitar `:d` cuelga en detección.

---

## 0. Veredicto en 10 líneas

1. Los rewrites de PLAN y ESTADO son **correctos en lo grande** (K27-revertido, H2 abierta,
   `:d` nuestro, s263≠solución) pero arrastran **7 residuos factuales** (§1), dos de ellos
   load-bearing: la tabla de 6 configuraciones **etiqueta mal la fila 1** y **duplica la fila 4
   mientras borra la única config jamás probada** (s263+`shared=0`).
2. **K30 está bien planteado** para P20/P21: `shared=0` **evita B1 por construcción** y el
   caminador B2 está **dormido** (`uke_smmu_dump=0` por defecto). Pero **P22 tal como está
   escrita no es ejecutable**: `uke_smmu_dump=1` reactivaría B2 (evidencia fabricada) + B3
   (cuelgue en resume). P22 hay que partirla (§2).
3. Fixes R9: `bo->obj=NULL` + guarda de propiedad B1 + rewrite B2 + guardas B3 se aterrizan
   **en el árbol sin tocar la tablet** (0 flashes para fijarlos); **D1 espera al Paso 0**
   vivo. Orden y detalle en §3.
4. Quedan **9 contradicciones** entre los cinco informes; lista única con qué manda en §4.
5. Pista pantalla: orden **memmap-43MB > SSC-disable > auditoría o82**, y el único ciclo bien
   definido es el memmap **manteniendo `:d`** (§5).
6. Lunes por la mañana, en orden: **(1) flashear K30 + leer por SSH** (1 escritura);
   **(2) Paso 0 pantalla, 0 flashes** (DT vivo + diff contra s260); **(3) aterrizar los 4 fixes
   de código** (0 escrituras). Detalle con criterios de rotura en §6.

---

## 1. Verificación de los dos rewrites (errores de hecho, no de estilo)

### 1.1 Lo que el rewrite hace bien (consta para no re-abrirlo)

- K27 revertido con la premisa falsa nombrada: PLAN:11-13, ESTADO:47-49. Conforme con
  R7 §A.1 (`docs/historia/revision/R7-auditoria-2oct.md:57-61`) y R6 §6.1 (`docs/historia/revision/R6-gmu-erange.md:212-217`).
  Verificación propia: en k18-tree no queda `uke_gpu_mmu` en `a6xx_gpu.c` (grep vacío) y el
  orden `adreno_gpu_init` → `a6xx_gmu_init` sigue en `a6xx_gpu.c` (~:2749/:2772);
  `gpu->vm` se crea en `msm_gpu.c:974`. La rama de compartir K20 **sigue presente** en
  `a6xx_gmu.c:2043-2044` (correcto: revertir K27 ≠ quitar K20).
- H2 abierta / K25 no probó nada: PLAN:14-16, ESTADO:50-51 y 117. Conforme con
  R7 §A.5 (`docs/historia/revision/R7-auditoria-2oct.md:104-117`) y el propio #458
  (`FLASH-LEDGER.md:6466-6469`: "no puede confirmar ni refutar H2").
- `:d` es nuestro discriminador #P42, no del ABL: PLAN:38-41, ESTADO:53-59. Conforme con
  R8 §6.1 (`docs/historia/revision/R8-repaso-android.md:70`) y R5 §4 (`docs/historia/revision/R5-panel-dual-dsi.md:67-71`).
- s263 = fábrica pero no solución: PLAN:85-87, ESTADO:95-96 y 119. Conforme con
  R8 §4 (`docs/historia/revision/R8-repaso-android.md:59-61`) matizado por R7 §A.4
  (`docs/historia/revision/R7-auditoria-2oct.md:88-102`). Sin objeción.
- K30 = K27-revertido + `shared=0` sobre s260, sha `d1c24835…`, P20/P21/P22:
  PLAN:96-104, ESTADO:63-77. Conforme con #465 (`FLASH-LEDGER.md:6830-6901`).
  Verificación propia del árbol: `uke_gmu_shared` default 1 en `a6xx_gmu.c:2028`
  (el `=0` vendrá por cmdline, como dice #465-G2), dump default 0 en
  `a6xx_gmu.c:360-361` con gate en `:702-705`, walk confinado en `:395-492` y llamado
  solo dentro del dump (`:624`). Coherente con lo pre-registrado.

### 1.2 Residuos factuales (ordenados por gravedad)

**E1 (grave) — La tabla de 6 configuraciones etiqueta mal la fila 1.**
PLAN:76 y ESTADO:37 dicen `s260 + dominio propio → -ERANGE (-34)`.
Pero K25 (#458) corrió con `uke_gmu_shared` en su **default 1** (`FLASH-LEDGER.md:6411`,
`6442-6444`), y R6 demuestra que la rama de compartir **sí se tomaba** porque `gpu->vm`
ya existe (`docs/historia/revision/R6-gmu-erange.md:212-217`; verificado en `msm_gpu.c:974` + orden de
`a6xx_gpu.c`). La fila 1 fue **s260 + compartido-TTBR1 → -ERANGE**, no dominio propio.
El propio #464 deja abierta la comprobación del marcador COMPARTIENDO
(`FLASH-LEDGER.md:6809-6813`), así que afirmar "dominio propio" es afirmar justo lo que
está sin decidir. **Manda R6**; corregir la etiqueta a `s260 + shared=1 (K25)`.
(Esta es además la premisa que P20/P21 van a decidir: con la etiqueta actual, P21
"dominio propio también lo tiene" pierde sentido.)

**E2 (grave) — La fila 5 es un duplicado vacío y la config jamás probada desaparece.**
PLAN:79-81 y ESTADO:40-42 listan como #4 y #5 dos veces `s260 + shared=0 / GPU no probea`.
El ledger #464 (`FLASH-LEDGER.md:6814-6822`) lista en cambio como #6
`s263 + shared=0 — (no se probó nunca)`. El rewrite **borra del mapa la única
combinación sin medir** y la sustituye por una fila vacía. **Manda el ledger #464**:
restaurar la fila `s263 + shared=0 = no probada`.

**E3 (medio) — "El nudo que queda" reabre lo que R6 cerró.**
PLAN:93-94: "por qué el dominio —con o sin el quirk TTBR1— rechaza el iova 0x4000".
R6 §3 establece lo contrario con evidencia: en dominio **plano** (propio s260, o
compartido s263) el `0x4000` **sí mapea** (`fw-map icache iova=0x4000` en
`console-cm3-wedge-1818.log:20493`, citado en `docs/historia/revision/R6-gmu-erange.md:141-148`), y el primer
fijo en caer bajo TTBR1 es `debug@0x60400000`, no el icache (`docs/historia/revision/R6-gmu-erange.md:84-90`,
corroborado por R9 en `docs/historia/revision/R9-busqueda-errores.md:135-148`). La frase "con o sin TTBR1
rechaza" es **falsa en la mitad "sin"**. Reformular: el rechazo bajo es propiedad
**exclusiva** del dominio TTBR1-compartido; lo no diagnosticado es solo K24
(s260+`shared=0`), que es exactamente lo que K30 re-mide.

**E4 (medio-leve) — Doble "más barato" en Pista A.**
PLAN:53 ("[SSC] Es el más barato: sólo DT de overlay") vs PLAN:57 ("[memmap] este es el
candidato más barato (sólo cmdline, sin DT)"). Ambos no pueden serlo; **el memmap es
estrictamente más barato** (repack solo-cmdline, sin rebuild de DT ni gate `fdtoverlay`;
el SSC exige editar overlay + gate + flash de dtbo). Ver §5 para el orden que se sigue.

**E5 (leve, pero load-bearing para el próximo lector) — ESTADO paso 2 obsoleto al nacer.**
ESTADO:105-106 ordena "reescribir Pista A/B de PLAN-2OCT (hoy Ignora R5 y R6: R7 lo marca
como ERROR)". Pero PLAN **ya está reescrito** (banner PLAN:3-18, cita R5/R6/R7/R8).
Ejecutar el paso 2 tal como está redactado sería re-reescribir lo ya corregido.
**Este informe R10 ES esa ronda**; el paso debe pasar a "leer R10 y aplicar E1–E4".

**E6 (leve) — Taquigrafía del icache como víctima.**
ESTADO:44-45 y PLAN:82-84 repiten "el icache@0x4000 cae en la baja [y por eso -ERANGE]".
R6 §6.2 corrigió la precisión: la primera víctima es `debug@0x60400000`
(`docs/historia/revision/R6-gmu-erange.md:84-90`); el icache ni se intenta. No cambia ninguna decisión, pero es
la 4ª vez que la versión imprecisa sobrevive a una reescritura — fijar "debug primero,
icache ni intentado".

**E7 (nota de contabilidad, no error) — Criterio de "escrituras hoy".**
PLAN:120-121 dice "7 el 1-oct … 0 la noche del 1→2-oct hasta el flash de K30".
R7 §E (`docs/historia/revision/R7-auditoria-2oct.md:260-266`) advirtió la ambigüedad sesión-vs-día-natural.
El rewrite la usa sin fijar el criterio. Sin incumplimiento (exención #456 vigente),
pero cuando la exención expire el "≤2/día" necesita el criterio escrito. Una línea basta.

### 1.3 Verificaciones propias que SÍ cuadran (para cerrarlas)

- Grupos IOMMU distintos bajo s260 (PLAN:88-91, ESTADO:79-91, #465 en
  `FLASH-LEDGER.md:6831-6839`): coherente con R6 §3 (s260: GPU SID 0 grupo propio, GMU
  SID 5 grupo propio → sin `-EBUSY`) y con R7 §A.3. Nada que objetar; es además la base
  física de por qué K30 evita B1 (§2).
- `boot-ukek13-dsid-vid.img` (sha `990fbd6f…`) marcado "YA FALLÓ — no reutilizar"
  (PLAN:65-66): conforme con #463 (`FLASH-LEDGER.md:6756-6775`). Correcto y debe
  mantenerse como fila negativa.
- K27-revertido "byte-idéntico al fork base" en 3 ficheros (ESTADO:47-49, #465 en
  `FLASH-LEDGER.md:6869-6874`): verificado **parcialmente** por mí (ausencia de
  `uke_gpu_mmu` en `a6xx_gpu.c`; rama K20 intacta en `a6xx_gmu.c:2043-2044`;
  parámetros y walker conservados). El `diff` byte a byte es afirmación del autor;
  mis spot-checks son consistentes con ella. **Hipótesis residual**: ninguna señal en
  contra.
- `build-k30.sh` exige en el binario los marcadores del walker (`WALK iova`,
  `MAPPING ENCONTRADO`, `veredicto`) en `build-k30.sh:100-108`: coherente con que K30
  conserva el caminador dormido. Ojo: esto **fosiliza el código B2** como requisito de
  build — cualquier rewrite de B2 obligará a tocar también estos gates (§3).

---

## 2. ¿Es K30 el experimento correcto, dados los bugs de R9?

### 2.1 B1 (doble-destroy del `msm_mmu` compartido, `docs/historia/revision/R9-busqueda-errores.md:21-63`)

**K30 lo evita por construcción. Verificado en código, no por relato.**

- Cadena de B1: `a6xx_gmu_memory_probe` reutiliza `to_msm_vm(gpu->vm)->mmu`
  (`a6xx_gmu.c:2043-2045`) → dos `msm_gem_vm`, un `msm_mmu`, sin refcount
  (`msm_gem_vma.c:815+`) → `msm_gem_vm_free` destruye incondicional
  (`msm_gem_vma.c:159-170`) → doble `destroy` en `err_memory` + `a6xx_destroy`.
- K30 pone `uke_gmu_shared=0` por cmdline (#465-G2: `FLASH-LEDGER.md:6875-6877`).
  Con `shared=0`, la condición `uke_gmu_shared && !IS_ERR_OR_NULL(shared_mmu)`
  (`a6xx_gmu.c:2043`) es **falsa siempre** → el GMU crea su dominio vía
  `msm_iommu_new(gmu->dev, 0)` (`a6xx_gmu.c:2046`) → **dos mmu distintos, cada uno con
  un solo dueño**. El doble-`destroy` es inalcanzable en este camino.
- ¿Y si K30 falla con `-ERANGE` (P21)? El unwind recorrerá `a6xx_gmu_memory_free` +
  `drm_gpuvm_put` sobre un mmu **no compartido**: el doble-`put` de BOs de R6 §1.3
  (`docs/historia/revision/R6-gmu-erange.md:92-104`) seguiría posible, pero el doble-`destroy` del MMU no.
  La tormenta de WARNING será menor y el dominio del GPU quedará intacto para el
  re-probe. **B1 no contamina la lectura P20/P21.**
- Nota de higiene: la corrupción de slab que B1 pudo dejar en ciclos anteriores
  (K25/K26) **no sobrevive a un reboot** (slab = RAM). K30 arranca limpio. No hay
  arrastre entre ciclos por esta vía.

### 2.2 B2 (el caminador fabrica evidencia, `docs/historia/revision/R9-busqueda-errores.md:65-98`)

**Inocuo para P20/P21, letal para P22 tal como está escrita.**

- El walk (`uke_k19_walk_to`, `a6xx_gmu.c:395-492`) solo se invoca desde
  `uke_k19_dump_kgsl` (`:624`), que solo corre si `uke_smmu_dump != 0` (`:702-705`).
  Default 0 por BSS (`:360-361`, solo-cmdline `0444`). La cmdline final de K30 lleva
  **un solo token añadido** (`uke_gmu_shared=0`; el gate que pedía `uke_smmu_dump=0`
  se corrigió porque el default ya lo garantiza: `FLASH-LEDGER.md:6875-6879`).
  ⇒ En K30 el dump **no corre**, el walk **no corre**, B2a (fmt=AttrIndx,
  `a6xx_gmu.c:441,480`) y B2b (máscara corta sin alinear, `:436,486-487`) **no pueden
  fabricar nada**. P20/P21 leen `gmu init ret=` por SSH: camino limpio.
- Pero P22 (ESTADO:76-77, PLAN:103-104, #465 en `FLASH-LEDGER.md:6896-6897`) propone
  "abrir DRM una vez con `uke_smmu_dump=1`". Eso reactiva **a la vez** B2a+B2b
  (veredictos `MAPPING ENCONTRADO`/`HUECO` indistinguibles de ruido) y B3a-c
  (MMIO sin runtime-PM, `cb_base` sin validar, `MEMREMAP_WB` a ciegas en resume:
  `docs/historia/revision/R9-busqueda-errores.md:100-131`). Un "MAPPING ENCONTRADO" bajo `dump=1` **no sería
  evidencia**, y el propio volcado podría colgar el resume que pretende medir
  (precedente #449, citado en el propio código `:687-701` y en docs/historia/AGENTS.md r3).
  **P22 así redactada quema un ciclo y posiblemente la máquina a cambio de un dato
  inválido.**

### 2.3 Veredicto sobre K30 y enmienda mínima

**K30 está bien planteado como discriminador P20/P21. No rediseñarlo; enmendar P22.**

- P20 (`ret=0` o sin error → el `-ERANGE` era el TTBR1 del compartido) y P21
  (`ret=-34` → el dominio propio también falla → geometría/apertura, R9 la investiga)
  son falsables por SSH bajo s260, con red aunque el GMU falle (medido en K25:
  `FLASH-LEDGER.md:6442-6444`). El diseño "s260 como arnés de diagnóstico, no como
  solución" es correcto y debe mantenerse explícito (cfr. E3 y la decisión
  ESTADO:95-96).
- Enmienda: partir P22 en **P22a** (dump **apagado**: si el GMU mapea, ¿probean GPU,
  aparece `card0`, sobrevive el open una vez sin SMMU en el camino?) y **P22b**
  (test H2 con `dump=1`) **bloqueada hasta aterrizar B2+B3 en el árbol** (§3).
  P22a no cuesta nada extra: es el mismo boot K30.
- Si K30 estuviera mal planteado en algún escenario: solo si P21 sale `-EBUSY`
  en vez de `-34`/`0` — bajo s260 los grupos son distintos (`FLASH-LEDGER.md:6833-6835`)
  y s260 nunca dio `-EBUSY`, así que un `-EBUSY` apuntaría a regresión del revert
  (p. ej. K27 no revertido del todo) y el paso correcto sería verificar el binario
  (marcadores K27 ausentes), no otro flash. Lo dejo como rama prevista, no como
  hipótesis.

---

## 3. Orden de los fixes de R9 y qué vale la pena antes de tocar la tablet

### 3.1 Orden (justificado por dependencia, no por numeración de R9)

| Orden | Fix | Dónde | Por qué en este lugar |
|---|---|---|---|
| F1 | `bo->obj = NULL` tras el `put` en `a6xx_gmu_memory_alloc` (R6 §4.3, R9 §"Fixes" punto 5: `docs/historia/revision/R9-busqueda-errores.md:191`, `a6xx_gmu.c:~2007`) | 1 línea | Riesgo cero, convierte cualquier futuro fallo de mapeo en `ret=` limpio en vez de oops. Independiente de B1. No necesita flash para aterrizar; su efecto se ve en el **siguiente** boot que falle (p. ej. un P21). |
| F2 | Guarda de propiedad B1: `a6xx_gmu_memory_free` no hace `detach/destroy` cuando `mmu == mmu-del-GPU` (o refcount en `msm_mmu`) — `docs/historia/revision/R9-busqueda-errores.md:183-186` | ~5 líneas | Solo muerde cuando se comparte; con K30 (`shared=0`) es inerte. Pero **debe existir antes de volver a cualquier config con sharing** (hoy: P22b futuro, cualquier s263). Sin F2, el próximo `-ERANGE`/`-EBUSY` con sharing vuelve a corromper slab. |
| F3 | Rewrite del walk B2: `iopte_type` (bits[1:0]) + `ttbr = desc & GENMASK_ULL(47,12)` — `docs/historia/revision/R9-busqueda-errores.md:187-188`, referencia `io-pgtable-arm.c:67-72,168-183` | bloque `:395-492` + **gates de `build-k30.sh:100-114`** | Desbloquea P22b/H2. Exige actualizar los gates de marcadores (hoy exigen los literales del walker buggy). Verificable sin tablet: revisión contra `iopte_leaf`/`iopte_table` + compilación. |
| F4 | Guardas B3: `pm_runtime_get_if_active`, `cb_base >= SIZE → abortar`, comprobar RAM antes de `memremap` — `docs/historia/revision/R9-busqueda-errores.md:189-190` | `:495-629` | Desbloquea `dump=1` sin jugarse el resume. Verificable sin tablet (revisión + build). Mantener `uke_smmu_dump=0` por defecto (ya lo está). |
| F5 | D1 `phy1→okay` — `docs/historia/revision/R9-busqueda-errores.md:190` | dtsi u overlay del ciclo | **Último y condicional**: solo si el Paso 0 (§6-acción 2) muestra `disabled`/ausente en el DT **vivo**. R5 demuestra que el overlay vivo ya lo trae en `okay` (`docs/historia/revision/R5-panel-dual-dsi.md:20,61`); si el vivo dice `okay`, F5 es un no-op y no se flashea nada. |

### 3.2 Qué se puede resolver sin gastar un flash (respuesta directa)

**F1–F4 se aterrizan enteros sin tocar la tablet**: son edición + revisión + `build-k30.sh`
en verde (desprendido, LECCIONES r6). Ninguno necesita un boot para *existir*; solo su
*verificación conductual* (F1 ante un fallo real, F3/F4 ante `dump=1`) costará flashes
futuros. Concretamente antes del lunes-flash:

- ✅ F1 ahora mismo (1 línea, 0 riesgo, 0 escrituras).
- ✅ F2 ahora mismo (inerte bajo K30, obligatoria antes de re-compartir).
- ✅ F3+F4 ahora mismo (desbloquean P22b; los gates de build se actualizan en el mismo
  commit para no fosilizar B2 — cfr. §1.3).
- ⏳ F5 **no**: primero Paso 0 vivo (0 flashes). Si el vivo dice `okay` + driver presente
  + 1 sola línea histórica de `not ready` (criterio R5 C0 en `docs/historia/revision/R5-panel-dual-dsi.md:97`),
  D1/F5 quedan archivados sin haberse flasheado nunca.
- ⏳ Ningún dato de R9 requiere lectura del sistema salvo D1/Paso 0: B1/B2/B3 están
  cerrados por lectura de código (las líneas citadas bastan; R9 ya hizo el trabajo).

**Lo que vale la pena antes de tocar la tablet**: F1+F2 (30 min, blindan el unwind de
cualquier P21) y la decisión P22a-vs-P22b (§2.3). F3+F4 pueden ir en el mismo lote de
código del lunes tarde, pero **no bloquean el flash K30**.

---

## 4. Contradicciones entre los cinco informes (lista única consolidada)

| # | Quiénes chocan | Materia | Qué manda |
|---|---|---|---|
| C1 | #459/#461 (`gpu->vm==NULL` → no-op) vs R6 §6.1 + R7 §A.1 + R9 §B1-nota (`docs/historia/revision/R9-busqueda-errores.md:58-63`) | ¿Compartía K25 o iba en propio? | **R6/R7/R9**: `msm_gpu.c:974` + orden `a6xx_gpu.c` ⇒ el vm **existe** y la rama COMPARTIENDO se tomaba. La premisa K27 es falsa; K27-revertido es correcto. Residuo abierto (honesto): el marcador COMPARTIENDO no aparece en las capturas (#464 en `FLASH-LEDGER.md:6809-6813`; R7 §D.2: sin capturas archivadas). |
| C2 | R7 §A.2 (MATIZ, n=1, geometría pendiente) vs R6 (causa raíz cerrada) + R9 (corrobora) | ¿Está cerrado el `-ERANGE`? | **R6 en mecanismo, R7 en proveniencia**: TTBR1-compartido es la única rama consistente con `io-pgtable-arm.c:599` + `mem=2048M` (`docs/historia/revision/R6-gmu-erange.md:67-90`); pero la evidencia es n=1 **sin captura archivada** (`docs/historia/revision/R7-auditoria-2oct.md:73-74,226-231`). K30-P21 es el árbitro diseñado. No citar el `-ERANGE` como teorema hasta P21. |
| C3 | R6 §4-recomendación (s263 + compartir K20) vs medición K26 (`-EBUSY` en GMU) | ¿Vale la vía R6? | **La medición**: #464 ya registra que la propuesta R6 **es** K26 y dio `ret=-16` (`FLASH-LEDGER.md:6806-6808`). s263+sharing bloqueado a nivel de grupo (n=2: K26 lado GMU, K27 lado GPU). R6 acierta el mecanismo y falla la prescripción; quedarse con §1–§3 y §6 de R6, descartar su §4.3-operativo. |
| C4 | R8 §4 ("s263 es lo que usa fábrica, no cambiar") vs R7 §A.4 ("obligatorio para esta vía") vs uso de s260 en K30 | ¿s260 o s263? | **No hay contradicción una vez acotado** (PLAN:86 lo acota bien): s263 = fiel a fábrica y necesario-para-compartir, pero insuficiente (C3). K30 usa s260 como **arnés diagnóstico** (red viva), no como solución. Quien lea "s260" en K30 como "volvemos a s260" está malleyendo; E5/E3 piden hacerlo explícito. |
| C5 | R9 D1 (`docs/historia/revision/R9-busqueda-errores.md:152-159`: dsi1/phy1 `disabled` en k18-dtsi, link1 imposible sin `okay`) vs R5 (§2–§3: el overlay vivo ya trae todo `okay`, el base va apagado por diseño) | ¿Falta un `okay`? | **R5 para el camino de boot, R9 para la higiene del árbol**: ambos constatan el mismo `disabled` en el base; discrepan solo sobre dónde vive el enablement. Árbitro de 0 flashes: el DT **vivo** (R5 C0). Si vivo=`okay`, manda R5 y D1 se archiva; si vivo=`disabled`/ausente, manda R9-D1 y el fix va al **overlay**, nunca al base (el repack no transporta dtb: #462–#463). |
| C6 | Premisa vieja ("el ABL impone `:d`") vs R8 §6.1 + R5 §4 + #463 | ¿De quién es el `:d`? | **R8/R5/#463**: es nuestro #P42 (`docs/historia/revision/R8-repaso-android.md:70`; `FLASH-LEDGER.md:6739-6742`). Y #463 midió que quitarlo cuelga en **detección** (`FLASH-LEDGER.md:6756-6768`): el `:d` es estabilizador, no causa. Prohibido tratar `video=` como tweak de bajo riesgo (lección encapsulada en #463). |
| C7 | PLAN-viejo ("K25 probó H2") vs #458 + R7 §A.5 | ¿Sigue abierta H2? | **#458/R7**: K25 murió en `gmu_init`, no llegó a la escalera ⇒ H2 intacta (`docs/historia/revision/R7-auditoria-2oct.md:110-117`). El rewrite ya lo corrige (PLAN:14-16). No reabrir. |
| C8 | Taquigrafía "icache@0x4000 no se puede colocar" (#458/#461/ESTADO:45) vs R6 §6.2 + R9 | ¿Qué cae primero? | **R6/R9**: `debug@0x60400000` cae primero; el icache ni se intenta; en dominio plano el `0x4000` mapea (`docs/historia/revision/R6-gmu-erange.md:84-90`; `docs/historia/revision/R9-busqueda-errores.md:137-148`). Fijar la frase exacta (E6). |
| C9 | "K24: GPU ni probea" (#456/#464-fila-4) vs R6 ("K24 supera mapeos, llega a S3/F3/F4", `docs/historia/revision/R6-gmu-erange.md:137-138`) | ¿Mapeó K24 o no? | **Empate técnico = el objeto de K30**: init-OK (llegar a `gmu_start`/S3) y probe-OK (`card0`) son etapas distintas; los dos relatos pueden ser verdad a la vez (mapeó, falló después sin diagnóstico). No afirmar ninguno; P20/P21/P22a lo deciden con log por SSH. |

---

## 5. Pista pantalla: los 3 candidatos de R8 §7, ordenados

Referencia: `docs/historia/revision/R8-repaso-android.md:76-80` (SSC §2/§3-fábrica, memmap §2-splash-43MB,
auditoría o82 §3-seis-números). Restricciones vigentes: quitar `:d` cuelga (#463);
`video=` = riesgo alto, no tweak (`FLASH-LEDGER.md:6772-6775`).

### 5.1 Orden por coste y probabilidad

| Orden | Candidato | Coste real | Probabilidad de mover la aguja | Por qué aquí |
|---|---|---|---|---|
| 1º | **memmap 43 MB** (`memmap=0x2B00000$0xE3940000`, mantener `:d`) | **Mínimo**: repack solo-cmdline, sin rebuild DT/kernel, 1 escritura `boot_a` | Media-baja como causa del *hang en detección*, pero es la única reserva demostrablemente **infractor** (26 MB vs 43 MB de cont-splash + 20 MB rdump en la misma base `0xE3940000`: `docs/historia/revision/R8-repaso-android.md:44-45`) | Lo barato y lo demostrablemente roto va primero. Y distinción clave: `memmap=` **no** es `video=`: se parsea en `setup_arch` (reserva memblock), no cambia ningún camino de driver ⇒ **no** le aplica la lección de riesgo de #463. |
| 2º | **SSC-disable** en ambas PHY (`qcom,dsi-pll-ssc-disable`, s260 fragment@103/104) | Medio: editar overlay + gate `fdtoverlay` (regla 1) + flash `dtbo_a`, 1 escritura | **Media-alta** como causa de "todo bindea, pantalla negra" (fábrica lo apaga para este panel; R5 §3a ni lo menciona: hueco real). Pero hoy el síntoma medido con `:d` quitado es **hang en detección**, no "negra con todo OK" — el SSC explica el segundo, no obviamente el primero | Va segundo porque, aunque probabilísticamente es el mejor fix de *link*, exige tocar el dtbo (superficie de riesgo mayor) y su predicción ("engancha el link") solo es medible **sin** `:d`, configuración que hoy cuelga por otra causa. Hacerlo antes del memmap mezcla dos incógnitas. |
| 3º | **Auditoría o82** contra los 6 números (clockrate 1190788720, porches 113@120/18@144/304@90, reset-seq, 5,8 V/1,9 V, `o82_42_02_0b`: `docs/historia/revision/R8-repaso-android.md:49-55`) | Auditoría: 0 flashes. El fix resultante: rebuild kernel + flash `boot_a` (máximo) | Baja a corto plazo (solo muerde cuando haya modeset real; hoy no hay ni detección estable), **obligatoria** a medio plazo para imagen real | Tercero porque es trabajo de 0-flashes que **no desbloquea nada medible hoy**, pero debe hacerse en paralelo (tarde del lunes, sin tablet) para que el siguiente ciclo de pantalla lo tenga listo. |

### 5.2 El único ciclo bien definido (uno solo)

**Ciclo M1 — memmap-43MB con `:d` intacto. 1 escritura.**

- **Qué cambia**: `boot-ukek30…` no; imagen nueva desde el par bueno K13-dsid
  (o desde K30 si ya dio P20/P21 — misma base s260 en todo caso): solo la cmdline,
  `memmap=0x1A12800$0xE3940000` → `memmap=0x2B00000$0xE3940000`. **`video=DSI-1:d`
  intacto** (aisla la variable; E4 y #463 lo exigen). Resto byte-idéntico (gate G6
  del repack lo garantiza: `repack-k18.py:300-337`).
- **Predicciones pre-registrables**: M1a — con `:d` puesto el arranque sigue estable
  (red OK; si ni siquiera esto, el memmap rompió algo del arnés → revert inmediato);
  M1b — el volcado del DT vivo / `dmesg` de display no cambia (esperado: con `:d` la
  detección sigue saltada); M1c — el ciclo **no** pretende imagen, solo dejar el
  arnés con la reserva correcta para el siguiente ciclo (SSC o `:d`-off futuro).
- **Cuántas escrituras**: 1 (`boot_a`; `dtbo` se queda en s260). Rollback: par bueno
  `e0ee47dc…`, 1 escritura.
- **Qué lo rompería**: que el ABL no deje cont-splash encendido en este camino
  (entonces la reserva extra es inocua pero inútil — resultado nulo, no negativo);
  o que `0x2B00000` colisione con otra reserva del DT vivo (verificar contra
  `/proc/device-tree/reserved-memory` **antes** de flashear — 0 flashes, parte del
  Paso 0).
- **Por qué no el SSC como primer ciclo**: el SSC necesita el dtbo (regla 1 +
  `uke-dtbo-check`), su efecto solo se ve sin `:d`, y sin `:d` hoy cuelga por causa
  desconocida (C6). El SSC es el **segundo** ciclo de pantalla, condicionado a que M1
  + Paso 0 no encuentren pisada de memoria.

---

## 6. Las 3 acciones del lunes por la mañana (concretas)

### Acción 1 — Flashear K30 y leer por SSH (P20 vs P21). **1 escritura.**

- **Qué cambia**: `boot_a` ← `boot-ukek30.img` (sha `d1c24835…`, pre-registrado #465);
  `dtbo_a` se queda en s260. Nada más.
- **Medición**: por SSH (red viva bajo s260 aunque el GMU falle): `gmu init ret=` +
  log de attach (`uke_attach_log=2` ya en cmdline) + `MAPPING`/S-ladder si llega.
  Decisión P20 (`ret=0`/ausencia → era TTBR1-compartido) vs P21 (`ret=-34` → geometría
  propia, entra R9) con las predicciones ya escritas antes de medir (#465).
- **Qué la rompería**: (a) sin red → plan B: doble captura ACM + `dmesg -w` por SSH
  si revive (regla 4, precedente #428→#429 citado en R7 §D.2); (b) `ret=-16` bajo s260
  → no previsto (s260 nunca dio `-EBUSY`): parar y verificar marcadores K27 en el
  binario antes de otro flash (§2.3); (c) quemar `a` sin rollback (`b` unbootable) →
  power-cycle + fastboot + reflash del par bueno a mano (riesgo ya registrado en
  ESTADO:27-28).
- **No incluye**: P22b/`dump=1` (bloqueado hasta F3+F4). Solo P20/P21 (+P22a gratis si
  el GMU mapea: ¿aparece `card0` con el dump apagado?).

### Acción 2 — Paso 0 pantalla, R5 C0 + diff s260. **0 flashes, 0 escrituras.**

- **Qué cambia**: nada en la tablet; solo lecturas sobre el sistema vivo (K30 o par
  bueno, el que esté en slot): `cat /sys/firmware/devicetree/base/soc/phy@ae97000/status`
  (+ `ae95000`), enlace `driver` en `/sys/bus/platform/devices`, `devices_deferred`,
  `dmesg | grep -c "phy driver is not ready"`, volcado del DT vivo del panel y diff
  contra s260 fragment@95 con los 6 números de R8 §3, y
  `/proc/device-tree/reserved-memory` (pre-gate de M1).
- **Decide**: si vivo=`okay`+driver+1 línea histórica → R5 manda, D1/F5 archivados
  para siempre; si `disabled`/ausente/deferred persistente → F5 al overlay (nunca al
  base) como ciclo SSC-adjunto; si la reserva viva contradice `0xE3940000/43MB` → M1
  se rediseña antes de flashear.
- **Qué la rompería**: tablet sin red ni consola tras la Acción 1 → Paso 0 espera al
  par bueno restaurado; nunca flashear a ciegas para "poder leer".

### Acción 3 — Aterrizar F1+F2 (+F3+F4 si da la tarde) en el árbol. **0 escrituras.**

- **Qué cambia**: solo `k18-tree` (+ gates de `build-k30.sh:100-114` si F3 toca el
  walker) + commit. F1 (`bo->obj=NULL`, `a6xx_gmu.c:~2007`) y F2 (guarda de propiedad
  B1) son el mínimo del lunes; F3 (walk con `iopte_type` + máscara 47:12) y F4
  (guardas B3) desbloquean P22b/H2 y pueden ir en el mismo lote.
- **Verificación sin tablet**: `build-k30.sh` en verde (desprendido), revisión contra
  `io-pgtable-arm.c:67-72,168-183` para F3, y confirmación de que ningún marcador de
  gate fosiliza el walker viejo (§1.3).
- **Qué la rompería**: nada en la tablet (0 escrituras por definición). Riesgo único:
  editar fuera del árbol instrumentado — prohibido; el diff acumulado es la única
  fuente de verdad del kernel que flasheamos (lección de `build-k30.sh:4-13`).

### Lo que el lunes NO se hace

- No `dump=1` (P22b) hasta F3+F4 + gates actualizados (§2.2).
- No `status="okay"` en `palawan.dtsi` (refutado R5; #462 revertido;
  `FLASH-LEDGER.md:6734-6738`).
- No quitar `:d` salvo dentro de un ciclo diseñado para el hang (C6; #463).
- No s263 ni `shared=1` hasta que P21/F2 digan lo contrario (C3; el grupo SID 5
  admite un solo attach).
- No declarar H2 probada con nada que no llegue a la escalera S3 (C7).
- No flashear en lote: 1 cambio por ciclo, sha pre-registrado, 4 contadores de slot
  antes/después (R7 §D.4: K25/K26/K27 no los anotaron sistemáticamente).

---

## Apéndice — Trazabilidad mínima de este informe

- Tablas de 6 configs: PLAN:74-81, ESTADO:33-42, ledger #464 en
  `FLASH-LEDGER.md:6814-6822` (E1/E2).
- K30 pre-registro: #465 en `FLASH-LEDGER.md:6830-6901`; árbol: `a6xx_gmu.c:2028`
  (default shared), `:2043-2052` (rama compartir vs propio), `:360-361` + `:702-705`
  (dump apagado), `:395-492` + `:624` (walk dormido); `msm_gpu.c:974`;
  `build-k30.sh:90-129` (gates).
- B1/B2/B3/D1: `docs/historia/revision/R9-busqueda-errores.md:21-63,65-98,100-131,152-159,183-191`.
- Pantalla: `docs/historia/revision/R5-panel-dual-dsi.md:18,56,97-100`; `docs/historia/revision/R8-repaso-android.md:42-45,49-55,
  59-61,70,76-80`; #462–#463 en `FLASH-LEDGER.md:6697-6775`.
- H2/K25: #458 en `FLASH-LEDGER.md:6439-6481`; `docs/historia/revision/R7-auditoria-2oct.md:104-117`.
- K26/K27/retractación/restauración: #459–#461 en `FLASH-LEDGER.md:6483-6695`.
- Todo lo marcado "hipótesis" lo es; todo lo demás cita fichero:línea arriba.
