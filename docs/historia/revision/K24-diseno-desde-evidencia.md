# K24 — diseño REVISADO (1-oct-2026, tras auditoría de 3 subagentes)

> ## ⚠️ LECTURA OBLIGATORIA ANTES QUE NADA DE ESTE DOCUMENTO (2-oct-2026)
>
> **Las secciones §1, §2, §4 y §5b están SUPERADAS por auditorías posteriores.** Los banners
> locales de §3/§4 **no fueron suficientes**: hay que leer este aviso, no los banners.
>
> - **La "evidencia" de §1/§2/§4/§5b viene de una captura (18:12) hecha por un kernel ANTERIOR al
>   K19, que no contenía la instrumentación que esas secciones citan** (lo admite el propio §5a de
>   este mismo documento). No es evidencia de este diseño.
> - **§4 ("basta `status=okay` en `phy@ae97000`") es ERROR**: el overlay vivo **ya** trae esa PHY en
>   `okay`, y el `disabled` está en el BASE **por diseño** (el enablement vive en el overlay); además
>   editar el base no sirve porque el repack **no transporta** el `.dtb`. Ver `docs/historia/revision/R5-panel-dual-dsi.md`
>   y `docs/historia/revision/R7-auditoria-2oct.md` §A.6.
> - **§5b (el volcado no es el wedge, "K25 lo probó") es ERROR**: K25 murió en `gmu_init` y **no
>   llegó** a la escalera del CM3, así que **no puede** probar H2. Que no llegue **invalida** el
>   test, no lo supera. **H2 sigue ABIERTA.** Ver `R7` §A.5.
> - **Lo que SÍ se sostiene de este documento**: el diseño del caminador de tabla `uke_k19_walk_to()`
>   (C1) y el veredicto del `dtcm-magic` (OK/STALE). Ambos verificados y en producción.
> - **Ojo con la premisa `gpu->vm == NULL`**: es **FALSA** (`msm_gpu_init` crea el vm en
>   `msm_gpu.c:974` **antes** de `gmu_init`). Sobre ella se construyó el fix UKE-K27, que ya está
>   **revertido**. Ver `R7` §A.1.
>
> **Este documento reemplaza a la versión anterior del mismo nombre.** No la borres sin leer la
> sección «Correcciones» del §0: la versión anterior contenía un error de lectura que invertiría
> una de las tres patas del diagnóstico.

## §0 Correcciones que hizo la 1ª auditoría (léase primero)

1. **«`dtcm-magic=0x40050001` es correcto ⇒ el CM3 arrancó y ejecutó» era FALSO.**
   La comprobación real del código es `(val & mask) == reset_val`; con `val=0x40050001`,
   `mask=0x1ff`, `reset_val=0x100` sale `0x1 != 0x100` ⇒ **NO cuadra**. Además el registro se
   lee **antes** de soltar el reset (`a6xx_gmu_start`, línea 493: `gmu_read(CM3_DTCM_START+0xff8)`
   y el `S1-rst1` viene después), así que es el DTCM **stale de la ejecución anterior**. Por tanto
   **no se puede afirmar que el CM3 llegara a arrancar**. Esto **refuerza** (no debilita) la
   hipótesis del fetch: es consistente con «el icache@0x4000 no llegó a la RAM del CM3».
   *(Corregido también el `DRM_DEV_INFO` en el árbol para que el próximo arranque imprima el
   veredicto explícito y no haya que reinterpretar el número a mano.)*

2. **«K23c es solo cmdline, sin rebuild» era una verdad a medias.** La instrumentación
   `CBpage`/`GEO` **ya existe y ya está activa** en el árbol (`uke_k19_dump_kgsl`, llamada
   incondicional en la línea 526, **justo antes** de `S3-rst0` en la 530). No hay que escribir
   código: hay que **repackar** el K23b con otra cmdline. Pero un repack **es un artefacto
   nuevo**: sha nuevo, 1 escritura y riesgo de slot. «Sin rebuild» ≠ «gratis».

3. **«`hung_task_panic=0` protege el slot» era FALSO.** El ABL marca `unbootable` y consume
   reintentos en **cualquier arranque sin marca de éxito**, haya habido panic o no. Lo que
   hace `hung_task_panic=0` es que un wedge **cueste un reintento en vez de los siete** (el `=1`
   convierte un cuelgue en un bucle de panic-reboot automático de ~34 s que los quema todos).
   **Formulación correcta: mitiga, no protege.**

4. **El paso `eglinfo -B` sobra (valor de información ≈ 0).** Recorre el **mismo**
   `a6xx_gmu_resume → S1 → S2 → S3` que ya wedgeó con `modetest`, y **no imprime `CBpage`**
   (eso solo lo hace el dump del kernel). O wedgea (y no aporta nada nuevo) o no wedgea
   (y contradice lo medido sin mecanismo propuesto). Para el mismo precio, el arranque
   instrumentado da el wedge **más** el discriminador.

5. **El fix s260/s263 NO se toca sobre el par bueno.** El desajuste (`uke_gmu_shared=1` exige
   s263; el kernel con s260) es real, pero solo afecta a los K-20+, y el slot A actual
   (K13-dsid + s260) es **coherente** porque K13 no contiene ese parámetro. Se resuelve **dentro
   del artefacto experimental**, nunca flasheando s263 sobre el par bueno.

6. **«Flashear limpia `slot-unbootable`» no está aislado.** El ciclo hizo flash + `set_active` +
   reboot, y `REGLAS.md §2` ya dice que `set_active` repone contadores. Sin un control
   (`set_active` sin flash) no se puede atribuir el efecto al flash. **Veredicto honesto: «tras
   flash×2 + set_active el flag quedó en no; el mecanismo (flash vs set_active) no está
   separado».**

7. **El pstore se pierde por VOLATILIDAD, no por el ABL.** Atribuirlo al ABL excede la evidencia;
   un power-cycle borra cualquier RAM sin alimentación. La conclusión operativa (usar la consola
   ACM) no cambia, pero el mecanismo que se escribe debe ser el correcto.

## §1 Qué está realmente medido

Escalera del CM3 (consola ACM, 1-oct 18:12:38, kernel K13-dsid):

```
… F3-loopOK  F4-verOK  [Loaded GMU firmware v4.5.1]
UKE-CM3DBG: fw-map icache iova=0x4000 (3ff0 KiB) dummy=0x60000000 debug=0x60400000 …
… P3-pwrOK   UKE-CM3DBG: dtcm-magic=0x40050001 mask=0x1ff reset_val=0x100   <-- NO cuadra (ver §0.1)
S1-rst1 → S2-gen9 → [FIN DEL LOG]
```

- El **firmware carga y verifica** (F3/F4 OK, v4.5.1) ⇒ no es un fw corrupto.
- La **power sale OK** (P3-pwrOK) ⇒ no es un problema de rails.
- El **magic del DTCM NO cuadra** ⇒ evidencia *a favor* de que la imagen no llegó a la RAM del CM3.
- El log para **antes de `S3-rst0`** ⇒ el cuelgue es al soltar el reset, el primer fetch.
- **`icache iova=0x4000`** ⇒ la dirección pedida es la correcta (⚠️ ver §2: esto es el iova
  *solicitado*; el *alcanzado* lo dice el mismo log pero conviene no sobreinterpretarlo).

## §2 La hipótesis, y lo que la distingue de las alternativas

**K24**: el CM3 pide su icache por IOVA a través del SMMU con **SID 5**, cuyo `S2CR` está en
**TRANS hacia CB1** (decode correcto: `TYPE=bits[17:16]=0`, `CBNDX=bits[7:0]=1`). Si la página
`0x4000` **no está mapeada en la tabla de CB1**, el primer fetch aborta y cuelga el AHB.

⚠️ **Matiz que la auditoría mortificó**: el hecho de que el log imprima
`icache iova=0x4000` es el iova **devuelto por el pin**, lo que hace *probable* (no probado) que
la dirección sea la pedida. Si el discriminador sale «cero en ambos CB», hay que considerar que el
mapping **ni se creó** (fallo del attach) y no solo «se creó en otro CB».

### Alternativas que la evidencia NO descarta (auditoría, §E de sus preguntas)

| # | Hipótesis alternativa | Qué la distinguiría |
|---|---|---|
| A1 | El problema es el **DTCM**, no el icache: `dtcm_base=0x10004000` en a7xx vs el fw que se escribe en `0x00040000`. | Si el discriminador CB1 sale limpio, mirar el offset de DTCM: el bloque del fw que cae fuera de `in_range(blk->addr, dtcm_base, SZ_16K)` se pierde en silencio (el `else` del bucle solo avisa si `fw_block_mem` también falla). |
| A2 | **Secuencia reset/power**: el CM3 necesita más de un ciclo de `SYSRESET` o un orden distinto. | Un kernel de solo instrumentación que lea `FW_INIT_RESULT` **después** de `S3-rst0` con timeout largo: si el poll *vuelve* (con o sin valor), el reset no es el problema. |
| A3 | El fw **no corresponde** a esta GPU / la versión no valida de verdad. | `F4-verOK` lee `CORE_FW_VERSION`; si major/minor no es el esperado para gen71100, el fw es otro. |
| A4 | **Pérdida de líneas en la captura**: el log "termina antes de S3" podría ser captura truncada, no cuelgue. | Búsqueda de `missed`/truncamiento en el log (regla: la consola ACM pierde cola al reset). Si hay pérdida, la localisation del wedge es frágil. |

> ⚠️ **SECCIÓN SUPERADA — NO LA EJECUTES.** Fue escrita antes de la 2ª ronda de auditoría
> (sesiones #454/#455). Sus afirmaciones fueron **refutadas** después; lo vigente está en
> **§5b/§5c**. Concretamente: (a) el discriminador `CBpage(1).L[4]` que prescribe esta
> sección **leía basura** (§5a-C1); (b) el «fix» K24-VA que propone **no es implementable
> desde el driver msm** (§5c: `MSM_BO_MAP_PRIV` solo pone bits AP; el CB lo elige
> `arm-smmu` vía `S2CR.CBNDX`); (c) la afirmación de que «con s263 la máquina sobrevive» es
> **hipótesis con n=1 y confounds** (§5d-C6), no un hecho verificado.

## §3 El discriminador (lo que falta y cómo se consigue)

**La instrumentación ya está en el binario.** No hay que escribir código: hay que **flashear el
K23b** (que ya la lleva) y abrir una vez DRM para que la escalera llegue a la línea 526.

| Lo que muestre `CBpage(1)` (descriptor `L[4]`, iova 0x4000) | Diagnóstico | Acción |
|---|---|---|
| válido **solo en CB0**, ausente en CB1 | el mapping está **en la tabla equivocada** | K24-VA: forzar el mapping también en CB1, o `uke_gmu_shared=0` |
| **cero/absente** en CB0 y CB1 | el mapping **no se creó** (attach fallido) | K24-VB: arreglar el attach / `MSM_BO_MAP_PRIV` |
| **válido en CB1** | la hipótesis del CB queda **refutada** | ir a A1/A2 (DTCM o secuencia de reset) |

⇒ **El siguiente artefacto es el K23b tal cual** (o un repack mínimo con
`hung_task_panic=0`), y el resultado del `CBpage` **es** la decisión sobre K24. No hace falta
construir K24 antes de tener ese dato.

> ⚠️ **SECCIÓN SUPERADA — NO LA EJECUTES.** Fue escrita antes de la 2ª ronda de auditoría
> (sesiones #454/#455). Sus afirmaciones fueron **refutadas** después; lo vigente está en
> **§5b/§5c**. Concretamente: (a) el discriminador `CBpage(1).L[4]` que prescribe esta
> sección **leía basura** (§5a-C1); (b) el «fix» K24-VA que propone **no es implementable
> desde el driver msm** (§5c: `MSM_BO_MAP_PRIV` solo pone bits AP; el CB lo elige
> `arm-smmu` vía `S2CR.CBNDX`); (c) la afirmación de que «con s263 la máquina sobrevive» es
> **hipótesis con n=1 y confounds** (§5d-C6), no un hecho verificado.

## §4 EL HALLAZGO QUE CAMBIA EL PLAN (auditoría de evidencia, P5 — verificado en el ledger)

**El ledger #448 dice, literalmente, de s263 + K20 (`uke_gmu_shared`)**:

> "el release del CM3 (S3) **ya NO wedgea el bus — solo estanca su propia escritura (máquina
> viva, SSH estable)**. Resto: el fetch inicial del CM3 sigue sin completar."

Y el wedge de hoy (kernel con `uke_gmu_shared=1` + dtbo **s260**) tiene la firma **de #447**
(máquina muerta: sin ping, sin SSH).

**⇒ La variable que distingue "mata la máquina" de "solo estanca su escritura" es el dtbo
(s260 vs s263), es decir el STREAM MAPPING del SID en el SMMU.** El propio código lo declara:
`uke_gmu_shared=1` "requiere s263: GPU y GMU mismo SID".

Esto **degrada K24**: el fallo no está solo en *qué CB contiene la página* (CB1), sino probablemente
en el **stream mapping del SID 5** (que el SID exista, no esté en BYPASS, y apunte al CB correcto).
Mapear la página en CB1 sería inútil si el SID no camina esa tabla.

**Consecuencia operativa (la más valiosa)**: **con s263 la máquina NO se muere**, o sea que se
pueden **leer logs, hacer preguntas y experimentar por SSH** en lugar de un power-cycle por cada
intento. Eso convierte el experimento de "ciego y caro" en "observado y barato".

## §5 Plan REVISADO PRIMERA VERSIÓN — **SUPERADO por §5b/§5c, leer antes de actuar**

Un solo ciclo, un solo cambio, y **con s263 para que la máquina sobreviva**:

1. **Reactivar el slot a con el par experimental coherente**: `boot_a` = K23b (ya lleva la
   instrumentación `GEO`/`CBpage` activa, líneas 526/530) + `dtbo_a` = **s263**. Esto NO toca el
   par bueno, que sigue intacto en **slot b** (K13-dsid + s260) como rollback.
   - Por qué s263 y no s260: no por "corregir un bug", sino porque **es lo que permite sobrevivir al
     wedge** (§4) y es lo que el propio driver exige con `uke_gmu_shared=1`.
   - ⚠️ `dtbo_a` está **libre**: su contenido actual es el par rehabilitation (K13-dsid + s260) que
     se puede volver a flashear en cualquier momento desde `build/backup-par-bueno/`.
2. **Al arrancar, abrir DRM UNA vez** (con lector ACM armado y captura doble). El dump corre en la
   línea 526, justo antes de `S3-rst0`. Se leen, en este orden:
   - (i) **SMR/S2CR del SME del SID 5** ⇒ ¿existe stream mapping válido con s263?
   - (ii) **`CBpage(1)` `L[4]` y `CBpage(0)` `L[4]`** ⇒ ¿dónde está la página 0x4000?
   - (iii) **readback de `SYSRESET` tras el write de S3** ⇒ discrimina cuelgue-en-write vs fetch.
   - (iv) **direcciones/tamaños de los bloques fw en ITCM/DTCM** (la asimetría F2-itcm ×1 vs
     F2-dtcm ×2 no está explicada).
3. **Según el resultado** (mutuamente excluyentes): K24-VA (mapping en CB0) / K24-VB (mapping
   ausente) / **stream mapping roto** (si el SID no existe o está en BYPASS) / hipótesis refutada.

**Presupuesto**: 2 escrituras (`boot_a` + `dtbo_a`) + exención, porque hoy ya se gastaron 2 en la
rehabilitación (#453) y la regla es ≤2/día. **Hace falta exención escrita del dueño.**

## §5a Correcciones de la 2ª auditoría (lo que el plan de arriba tenía MAL)

> Estas correcciones **invalidan §5 tal como estaba escrito**. Se conservan arriba por trazabilidad.

**C1. El discriminador `CBpage(1).L[4]` lee BASURA por construcción (E5, verificado).**
El arranque imprime `22 context banks (0 stage-2 only)` ⇒ traducción de **32 bits** ⇒ la tabla
apuntada por `TTBR0` es de **primer nivel con 4 entradas de 1 GB** (no 512). El código vuelca las
**8 primeras** entradas (`e[0..7]`), luego que `e[4]`…`e[7]` están **más allá del fin de la tabla**
(memoria adyacente). Y el descriptor que cubre `0x4000` **no está en la tabla de primer nivel en
ninguna geometría estándar**: hay que **caminar** la jerarquía (`L1[0]` → `L2` → `L3[4]`), cosa que
el código no hace. ⇒ El «índice 4 = icache@0x4000» es **FALSO**, y el desenlace «descriptor cero»
saldría **también con el mapping perfecto**. **El instrumento no distingue nada.**
**Corrección**: el dump debe **caminar** la tabla e imprimir la cadena de niveles con su `fmt`, o
imprimir el descriptor que cubre el intervalo que contiene `0x4000` en cada nivel.

**C2. La lectura `dtcm-magic` no la escribe este firmware (verificado parseando el fw).**
`gen71100_gmu.bin` (80.680 B) tiene 4 bloques `block_header`:

| # | addr | size | ventana | poke que explica |
|---|---|---|---|---|
| 1 | `0x00000000` | 476 | ITCM | `F2-itcm` ×1 |
| 2 | **`0x00004000`** | **79.900** | **icache** | — |
| 3 | `0x10007f98` | 40 | DTCM a7xx (offset `0x3f98`) | `F2-dtcm` |
| 4 | `0x10007fdc` | 24 | DTCM (offset `0x3fdc`) | `F2-dtcm` ×2 |

(a) El bloque del icache **existe y cae en `0x4000`** ⇒ la hipótesis «el fw no tiene bloque para el
icache» (H3) queda **REFUTADA sin flashear**. (b) Los bloques DTCM están en `0x3f98`/`0x3fdc`, pero
el magic se lee en offset **`0xff8`** ⇒ **este fw no escribe ese magic**; `0x40050001` es stale.
(c) Queda **explicada** la asimetría «F2-itcm×1 vs F2-dtcm×2»: es 1 bloque ITCM y 2 DTCM.

**C3. La captura del 18:12 la hizo un kernel ANTERIOR al K19 (E4).**
El log **no contiene** `K19-dump`, ni `K19-dumpOK`, ni `GEO`, ni `CBpage`, ni `S0-dtcmR` — todas con
`pr_flush`, imposibles de perder si se hubieran ejecutado. ⇒ **Las citas de línea de §1–§4
describen un kernel que NO es el que se colgó.** Falta fijar por escrito el par (kernel, dtbo, slot)
de ese arranque.

**C4. El dump se ejecuta en CADA resume, y eso puede ser el wedge (H2).**
`uke_k19_dump_kgsl()` va entre S2 y S3 **en cada `a6xx_gmu_start`**, incluido el re-resume en
runtime. Hace `ioremap` + `readl` del SMMU + `memremap` de la tabla: si el SMMU está sin reloj ahí,
el primer `readl` cuelga el bus con **la firma exacta observada (S2 y silencio)**, **con o sin
s263**. Precedente en el ledger: **#449** (el K19 con ioremap corto hizo machine-check y abortó el
resume antes de S3). **Regla 3 de docs/historia/AGENTS.md prohíbe exactamente esto.**

**C5. Con s263 el mapping SÍ está en la tabla ⇒ «CB1 no tiene la página» queda REFUTADO (E6).**
En #448 (s263 + shared=1) la tabla que traduce el SID 5 es la del **dominio compartido**, que **sí
contiene** el icache (se creó en `a6xx_gmu_init` y el attach lo sirve). ⇒ Cambiar a s263 **no**
discrimina el CB.

## §5b Plan FINAL propuesto

**Paso 0 — coste cero, sin tablet:**
1. Fijar por escrito el par (kernel, dtbo, slot) del arranque del 18:12 (C3).
2. Parseo del fw: **hecho** ⇒ H3 refutada, asimetría explicada (C2).
3. **Corregir el dump para que camine la tabla** (C1) — prepararlo, sin flashear todavía.

**Paso 1 — un (1) flash, un cambio, con s260 (NO s263):**
- `boot_a` = kernel K23 con **`uke_gmu_shared=0`** (el GMU usa dominio propio en vez de compartir el
  mmu del GPU), bajo el **s260 que ya está instalado**.
- **Por qué**: `shared=0` cambia **una sola variable** y ataca la **capa de attach** (la hypothesis
  más plausible, H1: con `shared=1` + s260 el grupo SID 5 del GMU nunca recibe dominio Linux).
  **No** se ataca la tabla, porque C5 demuestra que en el caso bueno la tabla ya tiene el mapping.
- ⚠️ **INFERENCIA, NO MEDIDO**: que `shared=0` **no** choque con `-EBUSY` bajo s260 es una
  deducción del comentario de `a6xx_gmu.c:1855-1859` («con s263 … `iommu_attach_group` → `-EBUSY`»),
  que solo dice que el problema era **con s263** (mismo SME/grupo). Con s260 los gruposdifieren, así
  que *debería* poder hacer su propio attach — pero **no está medido**. Si aparece `-EBUSY` /
  `gmu_init` muere con `-16`, ese ciclo **no dice nada** del wedge (falla antes) y hay que ir
  directamente a H2.
- **No tocar s263 este ciclo**: con s263 el mapping está (C5) ⇒ el experimento sería ilegible, y K13
  no tiene el parámetro.
- **Payoff asimétrico**: si **arranca** ⇒ H1 probada **y** el dump exonerado a la vez. Si **wedgea
  igual** ⇒ H1-como-causa-única queda muerta ⇒ siguiente ciclo es H2 (sacar el dump del camino
  caliente, C4).
- Slot **b** intacto como rollback.

## §5c Confirmado por la 2ª auditoría de código (y un aviso nuevo)

- **El volcado NO sale solo al arrancar**: `a6xx_gmu_start` no se llama en el probe/bind. La cadena
  real es `msm_open` → `load_gpu` → `adreno_load_gpu` → `pm_runtime_get_sync` →
  `adreno_runtime_resume` → `a6xx_gmu_resume` → `a6xx_gmu_fw_start` → `a6xx_gmu_start`. Es decir,
  **hay que abrir `/dev/dri/card0`** (`modetest`/`eglinfo`/compositor). El propio driver lo dice:
  *"load gpu on open.. to avoid firmware in initrd"*.
- ⚠️ **Aviso operativo**: el dump corre en **CADA** `resume` posterior (autosuspend, cada submit
  tras inactividad, `adreno_recover`), así que habrá **volcados repetidos**, no uno. Y eso
  multiplica el riesgo de C4/H2 (el propio dump Could be lo que cuelga el bus).
- **«Mapear 0x4000 en CB1» NO es arreglable desde el driver msm** (auditoría AF4, confirmado):
  `MSM_BO_MAP_PRIV` solo pone bits AP en la PTE; el CB lo elige el driver SMMU por Stream ID
  (`arm_smmu.c`, `S2CR.CBNDX`). Forzar CB1 exigiría tocar DT/arm-smmu. ⇒ **K24-VA tal como estaba
  escrito no es implementable en la capa msm**; solo sirve como *diagnóstico*, no como fix.
- Compartir el mmu **no programa ningún SMR**: solo reutiliza el puntero `msm_mmu`, con lo que las
  PTEs del icache caen en la **misma page table** que el SMMU ya sirve al CB del SME del SID 5.

**Presupuesto**: 1 escritura + exención escrita (hoy ya se gastaron 2 en #453).

## §5d Correcciones de la 3ª ronda de auditoría (lo que faltaba)

**D1. «Con s263 la máquina sobrevive» NO es un hecho verificado: es una hipótesis con confounds.**
Matriz real del ledger:

| Caso | Kernel | dtbo | Desenlace |
|---|---|---|---|
| #447 | K17 (pre-shared) | s260 | **muerta** |
| #448 | **K20** (`uke_gmu_shared=1`) | **s263** | viva, fetch incompleto |
| #452 | K13 (pre-shared) | s260 | **muerta** |

El caso «viva» es el **único con K20**. **`K20+s260` y `K17/K13+s263` nunca se probaron**: kernel y
dtbo covarían. El cambio K20 (dominio compartido) explica la supervivencia igual de bien: con el mmu
compartido, el stream SID 5 traduce contra una tabla que ya existe (fault limpio) en vez de colgar el
bus. ⇒ **No se puede atribuir al dtbo.** Se mantiene como hipótesis, y el plan §5b **ya no depende
de ella** (no toca s263).
⇒ **Pero hay una buena noticia que la auditado no explotó**: el arranque es **seguro por diseño**
(`msm_drv.c`: *"load gpu on open.. to avoid firmware in initrd"* ⇒ `a6xx_gmu_start` **no** se ejecuta
en el probe). O sea que **el wedge solo ocurre tras un open deliberado**, con SSH ya levantado y el
lector ACM ya armado ⇒ **el experimento es OBSERVABLE incluso con s260**. No hace falta s263 para
sobrevivir al wedge: basta con armar la captura antes del open.

**D2. «Slot b intacto como rollback» es FALSO en arrancabilidad.** El ledger #452 dejó **los dos**
slots `unbootable`; #453 solo rehabilitó **a**. El *contenido* de b es el par bueno, pero **b no
arranca** sin su propio ciclo de rehabilitación (otro `set_active` o reflash = más escrituras).
⇒ **Formulación honesta: si el experimento quema `a`, quedan CERO slots arrancables** y la vuelta
exige power-cycle físico + fastboot + reflash del par bueno desde `build/backup-par-bueno/`.

**D3. El repack puede llevar los DOS cambios de cmdline sin coste extra.** `uke_gmu_shared` es
`module_param` (tunable por cmdline) y el driver es built-in ⇒ `uke_gmu_shared=0` **no requiere
rebuild**, solo repack del K23b. Y como se repacka, **`hung_task_panic=0` cabe en el MISMO
artefacto**: sigue siendo **1 escritura** y el wedge pasa a costar 1 reintento en vez de 7.
⚠️ Esto **sí** son dos cambios lógicos en un ciclo: se acepta porque son ambos de cmdline, no
tocan código, y el que decide el experimento es `shared=0` (el panic solo afecta al coste del fallo,
no su interpretación).

**D4. El fix C1 (caminar la tabla) está en `k18-tree` desde el commit `dfe480e`.** Cualquier uso
futuro del discriminador necesita **rebuild** (el artefacto K23b `c31f098f…` no lo lleva, ni el
veredicto del dtcm-magic, ambos posteriores al build de las 15:24).

**D5. Regla del método, no solo del presupuesto.** Ejecutar §5b implica leer el SMMU en un resume,
que es justo lo que docs/historia/AGENTS.md r3 prohíbe («instrumentar el SMMU solo en el arranque, nunca en
runtime») y lo que ya woeó un ciclo (#449: machine-check por ioremap corto). ⇒ La exención del
dueño debe cubrir **el método**, no solo el presupuesto de escrituras. Está **declarado** aquí para
que sea una decisión consciente.

## §6 Reglas del ciclo (corregidas por la auditoría)

- **Cada apertura de DRM cuesta 1 reintento de slot** (`hung_task_panic=0` lo limita a 1, no a 0;
  el ABL marca `unbootable` ante cualquier arranque sin marca de éxito). Sin lector ACM único
  armado, **no abrir DRM**.
- **Un cambio por ciclo**. No tocar el par bueno de **slot b** (rollback).
- **`uke-captura-ladder.sh`**: parcheado a ≥5 s (era 0,3 s ⇒ fabricaba «zombis», #450).
- **Contabilidad de escrituras**: un `dd` a partición **cuenta** como escritura (corrige el
  «0 escrituras» que se afirmó en #452/#453).

## §7 Estado
- **Tablet**: sana en **slot a** (K13-dsid + s260), staging freedreno instalado.
- **Rollback**: ⚠️ **NO hay rollback arrancable.** El contenido del par bueno está a salvo en
  `build/backup-par-bueno/` (sha verificados), y el **slot b** lo contiene, pero **b está
  `unbootable`** desde #452 (solo se rehabilitó `a`). Si el ciclo quema `a`, la vuelta es
  **power-cycle físico + fastboot + reflash** del par bueno (D2).
- **Presupuesto**: **1 escritura** (§5b: solo `boot_a`; el s260 se queda). Exención necesaria
  porque hoy ya se gastaron 2 (#453). Y la exención debe cubrir también el **método** (D5).
- **Pendiente**: autorización del dueño para el repack + 1 flash.