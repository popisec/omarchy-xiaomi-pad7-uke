# K31 — CAUSA RAÍZ del `-ERANGE` del GMU (2-oct-2026, ledger #467)

> ## ⚠️ ACTUALIZADO 2-oct (ledger #470): **K31 midió con un parámetro que NUNCA se aplicó**
> `K33`Midió que el nombre real del parámetro es **`msm.uke_gmu_shared`** (el kernel antepone el
> nombre del módulo a los `module_param` del código built-in), así que **`uke_gmu_shared=0` a secas
> fue SIEMPRE ignorado**. Consecuencias, y esto es lo importante:
> - **Todos los ciclos "con dominio propio" (K24, K30, K33) corrieron en realidad con `shared=1`**:
>   el GMU compartía el mmu de la GPU (`UKE-K20: gmu vm COMPARTIENDO…`).
> - ⇒ **La "config #4" (dominio propio) nunca se midió** ni en K24 ni en K30/K33. El `-ERANGE` medido
>   ahí sigue siendo **el del dominio TTBR1 de la GPU compartido**, coherente con `R6`.
> - **[Añadido 2-oct, #477 + C1] La repetición CORRECTA sí salió**: con `msm.uke_gmu_shared=0`
>   (el nombre correcto) el GMU **mapea y NO da `-ERANGE`** ⇒ la cadena TTBR1 de este documento
>   **queda CONFIRMADA**. Y `R6` **tenía razón en el sujeto** (el GMU con dominio compartido
>   hereda el quirk), no sólo en la mecánica. Las hipótesis (a)/(b) del §"nudo que queda abierto"
>   **se disuelven**: no hacen falta, porque `qcom_adreno_smmu_init_context` ya hace `return 0`
>   para todo dominio que no sea la GPU (`arm-smmu-qcom.c:369`).
> - ⇒ **El fix UKE-K33 tampoco llega a probarse**: sin dominio propio, `init_context` del GMU no
>   corre y la línea `UKE-K33: dev=… NO es la GPU` no aparece.
> **Esto no invalida la cadena técnica de este documento** (el TTBR1 rechaza todo iova <4 GB, el GMU
> hardcodea iovas <4 GB), pero **sí invalida la afirmación de que "con dominio propio también falla"**
> (§"El nudo que queda abierto" y la tabla de configs). Ver `K31` §Revisión de 2-oct.

> ## ESTE DOCUMENTO REEMPLAZA LA EXPLICACIÓN DEL `-ERANGE` DE `docs/historia/revision/R6-gmu-erange.md`
> R6 decía: «el `-ERANGE` es el **quirk TTBR1 del dominio de la GPU**, y por eso compartir el mmu no
> ayuda». **K30 lo ha REFUTADO**: con `uke_gmu_shared=0` (dominio **propio**, sin compartir) el GMU
> **sigue** dando `-ERANGE` (medido: `gmu init ret=-34`). Compartir el dominio **no era la causa**.
> R6 acertó en la *mecánica* (`io-pgtable-arm.c:599`, quirk TTBR1) pero **se equivocó en el
> sujeto**: el TTBR1 no viene de «compartir el dominio de la GPU», sino de que **el GMU pide iovas
> por debajo de 4 GB y un contexto TTBR1 jamás los admite**.

## Resumen en 4 líneas

El GMU fija su VM a `0x0..0x80000000` y pide BOs en iovas fijos **bajos** (`icache=0x4000`,
`dummy=0x60000000`, `debug=0x60400000`). El SMMU de la GPU es **TTBR1-capable**: con ese quirk la
apertura del dominio se fuerza a **≥4 GB** y `arm_lpae_map_pages` **rechaza todo iova <4 GB**. La
primera reserva del GMU (`debug@0x60400000`) falla por tanto con `-ERANGE`, siempre, y da igual que
comparta o no el dominio. La GPU no sufre nada porque usa la **geometría** del dominio
(`start=max(16M, aperture_start)`), no una ventana fija.

## La cadena, con fichero:línea (verificada en el árbol, no de memoria)

| # | Hecho | Dónde |
|---|---|---|
| 1 | La VM del GMU se crea con ventana **fija `0x0..0x80000000`** | `a6xx_gmu.c:2052` — `msm_gem_vm_create(drm, mmu, "gmu", 0x0, 0x80000000, true)` |
| 2 | Sus BOs se piden en iovas fijos **todos <4 GB** | `a6xx_gmu.c:2808` `debug=0x60400000` · `:2817` `dummy=0x60000000` · `:2826` `icache=0x04000` |
| 3 | Con quirk TTBR1, la apertura del dominio se fuerza a **≥4 GB** | `arm-smmu.c:1904-1907` — `aperture_start = ~0UL << ias` |
| 4 | Con ese quirk, **todo iova <4 GB ⇒ `-ERANGE`** | `io-pgtable-arm.c:592-600` — `iaext=(s64)iova>>ias` (=0) ⇒ `iaext=~0=-1` ⇒ `WARN_ON` ⇒ `-ERANGE` |
| 5 | La GPU sí usa la geometría (y por eso no falla) | `adreno_gpu.c:217` — `start = max(SZ_16M, geometry->aperture_start)` |

## Medición que lo prueba (K30, por SSH — `dmesg`, no la consola ACM)

```
WARNING drivers/iommu/io-pgtable-arm.c:599 at arm_lpae_map_pages   (núcleo tainted: W)
   x1 (iova) = 0x60400000     ← mitad BAJA del VA
   x2 (paddr)= 0xb6e62000     ← RAM normal, paddr>>oas == 0  ⇒ la causa es `iaext`, no paddr
   x0        = 0xffffffde     = -34 = -ERANGE
[4.091668] adreno … UKE-GPU: gmu init ret=-34
```
Como `paddr` cabe en `oas`, el único modo de disparar el `WARN_ON` es `iaext`, y `iaext` sólo se
invierte (se hace `~iaext`) **cuando el quirk TTBR1 está activo**. Es decir: **el cfg con el que
mapó el GMU tenía TTBR1 ⇒ ese cfg venía de un contexto TTBR1**, no del dominio "plano" que
`uke_gmu_shared=0` debería darle.

## El nudo que queda abierto (NO se afirma como resuelto)

`arm-smmu-qcom.c:369-382` concede el quirk TTBR1 **sólo al device GPU (SID 0)**:
`if (!qcom_adreno_smmu_is_gpu_device(dev)) return 0;` antes de fijarlo. El GMU es **SID 5** ⇒ en
principio `return 0` y **sin** quirk. Pero el `WARN` demuestra que el quirk **estaba** activo al
mapear el GMU. Dos hipótesis, aún sin decidir:

- **(a)** `is_gpu_device()`/`fwspec` del GMU resuelve mal el SID y lo confunde con la GPU.
- **(b)** El GMU mapea a través del **contexto/CB heredado de la GPU** del bootloader
  (`qcom_adreno_smmu_get_ttbr1_cfg`, `arm-smmu-qcom.c:246`, devuelve el cfg del contexto ya
  inicializado). Los `S2CR` que dejó el BL (`S2CR(n)=0x00020000` para n=0..5, medido) apuntan a un
  CB concreto; si el GMU (SID 5) resuelve al mismo CB que la GPU (SID 0), hereda su TTBR1.

⚠️ `uke_attach_log`/`uke_keep_boot` en este build **sólo instrumentan apps-smmu**, así que el
`find_sme`/CBnDx/S2CR **real del GMU no sale en el log**. Distinguir (a) de (b) requiere una sonda
mínima en `init_context`/`map_pages` (imprime `dev`, SID resuelto, `quirks` efectivo del cfg). **No
se ha flasheado esa sonda.** Hasta entonces, (a) y (b) siguen **abiertas**.

## Dirección del arreglo (a validar; nada flasheado)

El GMU **no puede mover sus iovas** (el firmware espera `icache` en `0x4000` y las regiones en
`0x60000000`/`0x60400000`), así que subir la ventana no es opción. El arreglo es que el GMU **no
mapee por un contexto TTBR1**:

- **F1 (preferido)**: que el GMU mapée por un contexto **sin** TTBR1 — que es justo lo que el
  código actual *dice* que debería pasar (su `init_context` no fija el quirk por ser SID≠0). Si la
  causa real es (b) — herencia del CB del GPU —, F1 es la forma de romper esa herencia.
- **F2**: si (a) resultara ser un bug de resolución de SID, corregir `is_gpu_device` para que el
  GMU nunca tome la rama GPU.

En ambos casos, **antes de tocar nada**: blindar el **Oops del unwind** (ver abajo), porque un
unwind que salta a un puntero corrupto es peor que un `-ERANGE` limpio.

## El OOPS del unwind (segundo bug, independiente del `-ERANGE`)

Cuando `gmu_init` devuelve error, el unwind **no es limpio**:
```
[4.091976] Oops: paging request at 000000010000000c
   pc : 0x10000000c     ← puntero de función corrupto
  __iommu_unmap→…→msm_gem_kernel_put→msm_ringbuffer_destroy→msm_gpu_cleanup
  →adreno_gpu_cleanup→a6xx_destroy→a6xx_gpu_init→adreno_bind
```
Con `shared=0` el GMU ya **no comparte** `msm_mmu`, así que **este UAF no es el de R9-B1** (aquel
era doble-destroy del `msm_mmu`); es un **doble-unmap/doble-put a nivel GEM** en la cadena de
cleanup del GPU. Aun así confirma la predicción de R9: **el unwind de un `gmu_init` fallido rompe**.