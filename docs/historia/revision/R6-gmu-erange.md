# R6 — Causa raíz del `-ERANGE` (-34) en el mapeo del buffer del GMU

> ## ⚠️ CONCLUSIÓN PARCIALMENTE REFUTADA (2-oct-2026, ledger #467 / `docs/historia/revision/K31-causa-raiz-erange.md`)
> La **mecánica** que este informe acierta (`-ERANGE` sale de `io-pgtable-arm.c:599`, por el lado
> `iaext`, con el quirk **TTBR1**) **sigue siendo válida y verificada**. Lo que queda **REFUTADO**
> es el **sujeto**:
> - ❌ «el TTBR1 viene de **compartir el dominio de la GPU**» — **FALSO**. K30 lo midió con
>   `uke_gmu_shared=0` (**dominio propio, sin compartir**) y el GMU **sigue** dando `-ERANGE`
>   (`gmu init ret=-34`, por SSH). Compartir nunca fue la causa.
> - ❌ «el GMU compartía ese dominio» como explicación del rechazo — **falso como causa**: el GMU
>   hardcodea su propia ventana `0x0..0x80000000` (`a6xx_gmu.c:2052`) y pide iovas <4 GB, que un
>   contexto TTBR1 **rechaza siempre**, se comparta o no.
> - ✅ Lo que **sigue en pie**: el `-ERANGE` es el quirk **TTBR1** actuado por el lado `iaext`, y la
>   GPU no sufre porque usa la geometría del dominio (`start=max(16M, aperture_start)`, `adreno_gpu.c:217`).
> - ⚠️ **Nudo abierto**: el quirk TTBR1 sólo se concede al device **GPU (SID 0)**
>   (`arm-smmu-qcom.c:369`), pero el GMU es **SID 5** y aun así mapeó con el quirk ⇒ o `is_gpu_device`
>   lo confunde con la GPU, o hereda el contexto/CB de la GPU del bootloader. **Sin decidir.**
>   Ver `docs/historia/revision/K31-causa-raiz-erange.md` §"nudo que queda abierto".
> Este documento se conserva por su cadena de razonamiento y sus mediciones (ID1, TLB, rangos),
> **citándolo sólo como "mecánica correcta, sujeto equivocado"**.

**Conclusión en 3 líneas:**
El `-ERANGE` nace en `drivers/iommu/io-pgtable-arm.c:599` (`WARN_ON(iaext || paddr >> cfg->oas)`,
disparado por el lado `iaext` gracias al quirk `TTBR1` del dominio del GPU, que sólo admite la
mitad alta del VA); el GMU compartía ese dominio (el "no-op" de K27 es falso: `gpu->vm` ya existe
cuando corre `gmu_init`) y su `gmu->vm` de rango `[0, 0x80000000)` colocó `debug@0x60400000`
—el primer mapeo fijo, no el icache— dentro de un dominio que rechaza todo iova bajo.
El arreglo mínimo es **s263 (GPU en SID 5, sin TTBR1) + dominio compartido K20**, y revertir el
attach temprano de K27; bajo s260 no hay configuración que funcione (compartir→ERANGE, propio→EBUSY
no aplica… ver §4) y mover el `0x4000` es imposible (ABI del firmware).

**Nota de árboles:** las líneas citadas son de `build/kernel-pokes/k18-tree` (post-K27). El ciclo
#458 corrió sobre el árbol K25; el desfase medido es de ±1 línea (el ledger cita
`io-pgtable-arm.c:599` y en k18-tree el `if (WARN_ON(...))` está exactamente en la línea 599).
Donde la línea K25 pueda diferir lo marco.

---

## 1. Dónde nace el `-ERANGE`: rastreo exhaustivo del camino

Camino completo (nombres y líneas k18):

1. `a6xx_gmu_memory_alloc()` — `drivers/gpu/drm/msm/adreno/a6xx_gmu.c:1978`, llamada a
   `msm_gem_get_and_pin_iova_range()` en `a6xx_gmu.c:2004`. En error hace
   `drm_gem_object_put(bo->obj)` (`a6xx_gmu.c:2007`) y `return ret` (`a6xx_gmu.c:2008`)
   **dejando `bo->obj` colgando** (ver §1.4).
2. `msm_gem_get_and_pin_iova_range()` → `get_and_pin_iova_range_locked()` —
   `drivers/gpu/drm/msm/msm_gem.c:526` y `:555`. Dos fases: `get_vma_locked()` (`msm_gem.c:542`)
   y `msm_gem_pin_vma_locked()` (`msm_gem.c:542`).
3. `get_vma_locked()` (`msm_gem.c:436`) → objeto sin vma → `msm_gem_vma_new()`
   (`drivers/gpu/drm/msm/msm_gem_vma.c:368`), que hace, en orden:
   - `drm_mm_insert_node_in_range()` (`msm_gem_vma.c:391`) — devuelve **`-ENOSPC`**, nunca
     `-ERANGE` (`drivers/gpu/drm/drm_mm.c:515`, todos los `return` de error son `-ENOSPC`).
   - `drm_gpuva_insert()` (`msm_gem_vma.c:415`) — fuera de rango devuelve **`-EINVAL`**
     (`drivers/gpu/drm/drm_gpuvm.c:2039`), colisión **`-EEXIST`** (`drm_gpuvm.c:1997`).
     Nunca `-ERANGE` (grep de `ERANGE` en `drm_gpuvm.c`/`drm_mm.c`: cero resultados).
   - `drm_gpuvm_bo_obtain_locked()` (`msm_gem_vma.c:422`) — sin `-ERANGE`.
4. `msm_gem_pin_vma_locked()` (`msm_gem.c:473`) → `msm_gem_get_pages_locked()` (sin `-ERANGE`
   en su camino) → `msm_gem_vma_map()` (`drivers/gpu/drm/msm/msm_gem_vma.c:299`, llamada en
   `msm_gem.c:485`) → `vm_map_op()` → `mmu->funcs->map` = `msm_iommu_map()`
   (`drivers/gpu/drm/msm/msm_iommu.c:678`): propaga tal cual el error de
   `iommu_map_sgtable()` (`msm_iommu.c:691-693`; `-EINVAL` sólo si mapea menos bytes de los
   pedidos, `msm_iommu.c:695`).
5. `iommu_map_sgtable()` → `iommu_map_sg()` (`drivers/iommu/iommu.c:2858`, sin chequeo de
   geometría/apertura en este kernel: grep de `aperture` en `drivers/iommu/iommu.c` = cero
   resultados) → `iommu_map_nosync()` → `__iommu_map_domain_pgtbl()` (sólo `-EINVAL` por
   desalineación) → `arm_smmu_map_pages()` (`drivers/iommu/arm/arm-smmu/arm-smmu.c:2696`,
   sólo `-ENODEV` propio) → `arm_lpae_map_pages()` (`drivers/iommu/io-pgtable-arm.c:585`):
   - `-EINVAL` por `pgsize` (`io-pgtable-arm.c:594`) o por `prot` (`io-pgtable-arm.c:602`).
   - **`-ERANGE` en un único sitio: `io-pgtable-arm.c:599-600`:**
     ```c
     if (WARN_ON(iaext || paddr >> cfg->oas))
             return -ERANGE;
     ```
     con `iaext = (s64)iova >> cfg->ias` (`io-pgtable-arm.c:591`) e inversión
     `iaext = ~iaext` con `IO_PGTABLE_QUIRK_ARM_TTBR1` (`io-pgtable-arm.c:597-598`).
     (La variante `arm-v7s`, `drivers/iommu/io-pgtable-arm-v7s.c:516`, no aplica: el kgsl-smmu
     negocia `ARM_64_LPAE_S1` — `pgsize 0x61311000` con 4K/2M/1G en el log lo confirma.)

**Descartadas explícitamente otras fuentes de `-ERANGE` en el camino de `a6xx_gmu_init`:**
`drivers/opp/core.c:548,580` y familia (`dev_pm_opp_find_*` devuelven `-ERANGE` sin match), pero
`a6xx_gmu_pwrlevels_probe` y `a6xx_gmu_get_arc_level` (`a6xx_gmu.c:2151-2163`) tragan el error
(`return 0` con `IS_ERR(opp)`); no puede salir como `ret` de `gmu_init`. Sin `-ERANGE` en
`msm_gem.c`, `msm_gem_vma.c`, `msm_iommu.c` ni `drm_gpuvm.c`/`drm_mm.c` (verificado por grep).

### 1.1 Condición exacta que dispara el `-ERANGE`

O bien `paddr >= 2^oas` (lado físico), o bien `iaext != 0` (lado iova). Para un dominio **con
TTBR1**, `iaext = ~((s64)iova >> ias)` es `~0` para **cualquier** `iova < 2^ias`: **todo mapeo
bajo falla por diseño** (el dominio TTBR1 sólo cubre la mitad alta; su geometría es
`aperture_start = ~0UL << ias, aperture_end = ~0UL`, `arm-smmu.c:1904-1906`).

### 1.2 Cuál de los dos lados disparó en #458 (deducción cerrada)

- Lado `paddr`: **imposible**. Cmdline con `mem=2048M` (log `build/logs/console-cm3-wedge-1818.log:113`)
  ⇒ toda la RAM está por debajo de 4 GB ⇒ `paddr >> oas == 0` para cualquier `oas >= 32`, y el
  mínimo decodificable es 32 (`arm_smmu_id_size_to_bits`, `arm-smmu.c:3299`: `case 0: return 32`).
- Lado `iaext` sin TTBR1: **imposible** para `0x4000`/`0x60400000` con `ias >= 14` (el mínimo real
  es 32: `0x60400000 >> 32 == 0`).
- Lado `iaext` con TTBR1: **dispara siempre** para esos iovas. **Es la única rama consistente con
  el `WARNING … io-pgtable-arm.c:599` + `ret=-34` medidos en #458.**

Corolario: **el dominio donde falló el mapeo TENÍA `IO_PGTABLE_QUIRK_ARM_TTBR1`**. Y precisión
al ledger #458: el primer mapeo fijo que falla no es el icache, es el **`debug@0x60400000`**
(`a6xx_gmu.c:2814`, anterior al `dummy@0x60000000` de `a6xx_gmu.c:2823` y al `icache@0x4000` de
`a6xx_gmu.c:2832` para este Adreno 735 = familia `ADRENO_7XX_GEN2`, `a6xx_catalog.c:1618`).
El icache ni siquiera se intenta. (Si el log del #458 identificó literalmente al icache, no lo
puedo verificar — no hay captura del #458 en este proyecto; el efecto es el mismo: ningún iova
bajo es colocable en ese dominio.)

### 1.3 El doble-free del unwinding (verificado en código, explica todos los WARNING del #458)

`a6xx_gmu_memory_alloc` libera el objeto y retorna con `bo->obj` colgando (`a6xx_gmu.c:2007-2008`).
`err_memory` llama a `a6xx_gmu_memory_free()` (`a6xx_gmu.c:2980-2981`), que hace `msm_gem_kernel_put`
**incondicional** de los seis BOs (`a6xx_gmu.c:1963-1976`):
`put_vaddr` sobre objeto con `vmap_count == 0` → `GEM_WARN_ON(msm_obj->vmap_count < 1)`
(`msm_gem.c:782`, el `WARNING: msm_gem.c:782` del ledger) → `unpin` con `pin_count 0 → -1` →
`GEM_WARN_ON(msm_obj->pin_count < 0)` (`msm_gem.c:497/516`) → segundo `drm_gem_object_put`
sobre memoria ya liberada → `refcount_t: underflow; use-after-free`. Luego `a6xx_destroy` →
`msm_gpu_cleanup` → `iommu_detach` sobre dominio a medio construir (los WARNING de
`__iommu_unmap`/`iommu_detach_device` del ledger). Bug latente también en upstream: el camino de
error debería hacer `bo->obj = NULL` tras el `put` (`msm_gem_kernel_put` ya tolera NULL,
`msm_gem.c:1373-1376`).

## 2. Por qué el iova bajo no se puede colocar (y qué parte del encuadre sobra)

- `msm_gem_vm_create(drm, mmu, "gmu", 0x0, 0x80000000, true)` (`a6xx_gmu.c:2052`, rama no-compartida;
  idénticos args en la rama compartida) crea `drm_mm` con `drm_mm_init(&vm->mm, va_start, va_size)`
  (`msm_gem_vma.c:865`): **espacio `[0, 0x80000000)` sin recorte**. El `drm_mm` acepta `0x4000` y
  `0x60400000` sin problema. **El VM no es el problema.**
- No existe `iova_offset` ni mínimo de alineación en el camino msm (grep en
  `drivers/gpu/drm/msm/`: cero resultados); alineación efectiva `PAGE_SIZE` vía
  `drm_mm_insert_node_in_range` (`msm_gem_vma.c:391`), `0x4000`/`0x60000000` alineados. Sin problema.
- Tamaño/hueco: VM fresco, `SZ_16M-SZ_16K` en `[0x4000, 0x1000000)` no colisiona con nada (los otros
  fijos viven en `[0x60000000, …)`). Sin problema.
- **Geometría del dominio: es la única capa que rechaza, y no es "apertura pequeña" sino TTBR1.**
  `arm-smmu.c:1904-1911`: con TTBR1 la apertura es la mitad alta; sin TTBR1 es `[0, 2^ias-1]`
  (`aperture_start` queda a 0 por inicialización). El lado msm **nunca consulta la geometría** para
  colocar: `drm_mm` y dominio van por libre. El desajuste `[0, 0x80000000)`-vs-mitad-alta sólo se
  descubre al mapear, con `-ERANGE`.
- El `iommus` del DT sí existe para el GMU (`arch/arm64/boot/dts/qcom/palawan.dtsi:2501`:
  `iommus = <&adreno_smmu 5 0x0>`; GPU en `:2381` con SID 0). Si faltara, `msm_iommu_new`
  devolvería `-ENODEV` (`msm_iommu.c:738-739`), no `-34`. No es el caso.

## 3. La diferencia GPU-vs-GMU (el nudo, con precisión)

- Dominio GPU bajo s260: `msm_iommu_gpu_new(&pdev->dev, …)` (`adreno_gpu.c:195-240`) sobre dispositivo
  con **SID 0** ⇒ `qcom_adreno_smmu_is_gpu_device()` true
  (`arm-smmu-qcom.c:224-241`, `QCOM_ADRENO_SMMU_GPU_SID 0` en `arm-smmu-qcom.c:222`) ⇒
  `qcom_adreno_smmu_init_context()` pone `IO_PGTABLE_QUIRK_ARM_TTBR1`
  (`arm-smmu-qcom.c:379-382`, requiere además S1 + AARCH64, que se cumplen) ⇒ geometría mitad-alta
  ⇒ `adreno_iommu_create_vm()` calcula `start = max(SZ_16M, aperture_start)` = dirección alta
  (`adreno_gpu.c:225-230`). **El VM del GPU vive arriba; nunca pide iovas bajos.**
- Dominio propio del GMU bajo s260: `msm_iommu_new(gmu->dev, 0)` (`a6xx_gmu.c:2046`) sobre SID 5 ⇒
  **sin TTBR1** (retorno temprano en `arm-smmu-qcom.c:371-372`) ⇒ dominio plano `[0, 2^ias)` ⇒
  `0x4000` mapearía bien ahí. (Coherente con K24: s260 + `shared=0` **supera** los mapeos y llega a
  la escalera S3/F3/F4 — el `-ERANGE` no existe en dominio propio.)
- Dominio compartido bajo s260 (lo que **realmente** ocurrió en #458, ver §6): VM `[0, 0x80000000)`
  sobre mmu **TTBR1 del GPU** ⇒ todo iova bajo → `-ERANGE` en el primer fijo (`debug@0x60400000`).
- Bajo **s263** el GPU pasa a **SID 5** (`s263-boot-dtbo-gpu-sid5.img`, `fragment@1450`:
  `iommus = <0x1c1 0x05 0x00>` — verificado descompilando el dtbo con `dtc`; el GMU ya era SID 5):
  `is_gpu_device` false ⇒ **el dominio compartido deja de ser TTBR1** ⇒ apertura `[0, 2^ias)` ⇒
  `debug/dummy/icache/log/hfi` mapean (evidencia: `UKE-CM3DBG: fw-map icache iova=0x4000…` en
  `build/logs/console-cm3-wedge-1818.log:20493` y líneas análogas). Por eso #448 (s263+compartir)
  supera el attach. Y por eso s263+dominio-propio da `-EBUSY`: GPU y GMU ya comparten grupo SID 5 y
  el segundo `attach` choca (el fallback `iommu_attach_group` de `msm_iommu.c:778-798` no salva un
  grupo que ya tiene dominio).

## 4. Arreglo mínimo propuesto (en el orden pedido)

**a) Mover el icache a la apertura real: NO.** Doble refutación: (i) con TTBR1 la "apertura real"
son direcciones `~0UL<<ias`, inalcanzables para el uso del CM3; (ii) `0x4000` es **ABI del firmware**:
`fw_block_mem()` copia con `bo->virt + blk->addr - bo->iova` (`a6xx_gmu.c:1248-1255`) y el bloque
cuerpo viene en `blk->addr == 0x4000` (el `in_range(blk->addr, itcm_base, SZ_16K)` de
`a6xx_gmu.c:1298` lo excluye del ITCM por un pelo: `0x4000 == 16K` cae fuera del rango semiabierto
y aterriza en el icache); mover el iova sin mover los bloques rompería la aritmética del `memcpy`
y, sobre todo, el fetch del CM3 espera la imagen en `0x4000` vía SMMU. El comentario `UKE-CM3DBG`
de `a6xx_gmu.c:1327-1333` lo dice bien.

**b) Cambiar el rango del `msm_gem_vm_create` del GMU: NO.** El rango `[0, 0x80000000)` ya contiene
los iovas y el `drm_mm` los concede; el rechazo ocurre una capa debajo (io-pgtable vs quirk del
dominio). Cambiar el rango no mueve el `-ERANGE`.

**c) GMU en el dominio del GPU: SÍ, pero sólo bajo s263 (sin TTBR1), y sin K27.** El compartir K20
ya era funcional; con s263 el dominio compartido es plano y todo mapea (evidencia resume). Choques:
(i) bajo s260 el dominio compartido es TTBR1 ⇒ incompatible con cualquier iova bajo — compartir
ahí está condenado, hay que elegir s263; (ii) un solo `attach` por grupo: el compartir debe ser del
`mmu`, nunca dos dominios (el `-EBUSY` de s263+propio). Trade-off de s263 que debe constar: sin
TTBR1 el mecanismo de pagetables por-instancia del GPU (`set_ttbr0_cfg`/`get_ttbr1_cfg`,
`arm-smmu-qcom.c:243-307`) pierde su base; para probe + CM3 + `card0` basta, para userspace 3D
habrá que revisitar (posible dominio por-instancia sólo para usuarios o TTBR1 sólo-GPU con el GMU
en dominio propio… que hoy choca por grupo: callejón conocido, no bloqueante para el brings-up).

**d) Nada que tocar en `msm_iommu_new` / `msm_iommu_gpu_new`.** La geometría la dictan SMMU+SID
(`arm-smmu.c:1904-1911` + `arm-smmu-qcom.c:353-406`); los wrappers msm son fieles. Forzar o quitar
TTBR1 a mano rompería el invariante del driver adreno-smmu (mitad-alta↔TTBR1↔`aperture_start`↔
`adreno_iommu_create_vm`). No hay flag mínimo ahí.

**Recomendación operativa (0 flashes para decidir lo ya decidible):**
1. `grep "COMPARTIENDO" en la captura del #458` (predicción falsable de este informe: debe aparecer
   `UKE-K20: gmu vm COMPARTIENDO…`; si no aparece, mi §6 cae y el `-ERANGE` en dominio propio
   quedaría sin explicación — avísame y reabro).
2. Revertir K27 (el `uke_gpu_mmu` temprano de `a6xx_gpu.c:2792` y el consumo en
   `adreno_gpu.c:208-216`): no arregla nada bajo s260 (el mmu temprano sigue siendo TTBR1) y añade
   un `attach` temprano que, ante `deferred probe`, deja el dominio colgado y convierte el
   re-probe en `-EBUSY` "en la GPU" (candidato a explicar #460; **no verificado**: falta el log
   con el punto exacto del `-16` post-K27).
3. Aplicar el fix del doble-free (`bo->obj = NULL` tras `drm_gem_object_put` en
   `a6xx_gmu.c:2007`): convierte cualquier futuro fallo de mapeo en un `gmu_init ret=` limpio en
   vez de oops + `a6xx_destroy`.
4. Ciclo siguiente: **s263 + K20-compartir (sin K27) + `uke_smmu_dump=0`**, que es el que decide H2.

## 5. ¿Es el `-ERANGE` la causa del wedge del CM3? No (son dos fallos distintos)

- El `-ERANGE` (#458, s260+compartir-TTBR1) **aborta el probe**: `gmu_init` retorna antes de cargar
  firmware, no hay S3, no hay fetch, no hay `card0`. Un wedge requiere llegar a S3.
- El wedge (S3 tras `F3-loopOK`/`F4-verOK`) ocurre en configuraciones donde **los mapeos existen**:
  la línea `fw-map icache iova=0x4000 (3ff0 KiB)…` se imprime **después** de pineos exitosos
  (`a6xx_gmu.c:1334-1338`, vía `a6xx_gmu_fw_load` desde `fw_start`). "Icache no mapeado" está
  **refutado** para los boots con wedge por esa evidencia.
- Si el fetch no resolviera por falta de mapeo, el SMMU elevaría **context fault** (hay handler:
  `msm_gpu_fault_handler` vía `msm_iommu_gpu_new`, `msm_iommu.c:841`), no un freeze mudo en el
  primer `readl` del poll. El silencio apunta a otra capa (secuenciación reset/reloj del CM3,
  retención TCM, o el CB al que apunta el SID 5 — la línea K19/K24, fuera del alcance de este
  informe). La frase del ledger #458 ("el `-ERANGE` es la misma causa que el wedge, vista desde el
  probe") es incorrecta bajo este análisis: el `-ERANGE` explica por qué s260+compartir **no llega**
  a S3; no explica el cuelgue en S3 donde sí se llega.

## 6. Escepticismo aplicado: qué parte del encuadre recibido corrijo

1. **"Con `uke_gmu_shared=1` el GMU crea su propio dominio porque `gpu->vm` aún no existe" — FALSO.**
   Orden verificado: `adreno_bind` → `info->funcs->init` = `a6xx_gpu_init` (`adreno_device.c:242`)
   → `adreno_gpu_init` (`a6xx_gpu.c:2749`) → `return msm_gpu_init(…)` (`adreno_gpu.c:1252`) →
   `gpu->vm = create_vm(…)` (`msm_gpu.c:974`, con error → retorno temprano) → de vuelta en
   `a6xx_gpu_init`, `a6xx_gmu_init` (`a6xx_gpu.c:2808`). **Cuando `gmu_init` corre, `gpu->vm` existe
   siempre**; la rama de compartir de `a6xx_gmu_memory_probe` (`a6xx_gmu.c:2043-2045`, con el
   `pr_info("COMPARTIENDO…")`) **sí se tomaba en #458**. K27 parte de una premisa falsa.
2. **"El icache@0x4000 no se puede colocar" — impreciso.** En dominio plano (propio s260, o
   compartido s263) sí se coloca (evidencia resume). Lo que no se puede colocar es **ningún iova
   bajo en un dominio TTBR1**, y el primero en caer es `debug@0x60400000`, no el icache.
3. **"La diferencia de geometría es probablemente el nudo" — correcto pero invertido en el
   matiz:** el dominio del GPU bajo s260 no tiene la apertura "pequeña" sino **desplazada arriba**
   (TTBR1); el dominio propio del GMU la tiene abajo y ancha. El nudo es el desajuste
   VM-`[0,2G)`-sobre-dominio-mitad-alta, invisible para `msm_gem_vm_create`.
4. **No verificado con el código (marcado, pendiente de logs):** el punto exacto del `-EBUSY`
   "en la GPU" post-K27 (#460); la causa de "s260+`shared=0` ni probea" más allá de S3
   (si `gmu_init` tuvo éxito allí, el `-ERANGE` no interviene y el fallo es runtime); el valor
   ID2/ias/oas del kgsl-smmu en vivo (el `0x5111` del comentario K19 no tiene línea de log que lo
   respalde en este proyecto; irrelevante para la conclusión porque el lado `paddr` es 0 con
   `mem=2048M` en todo caso).
