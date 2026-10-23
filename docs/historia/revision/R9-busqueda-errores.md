# R9 — Búsqueda de errores (ronda solo-lectura, 2-oct-2026)

Árbol auditado: `build/kernel-pokes/k18-tree` (≈K25: sharing K20 sí, K27 no, dump K19 con gate K25).
DT auditado: `build/kernel-pokes/k18-tree/arch/arm64/boot/dts/qcom/palawan.dtsi`.
Corroborado contra: `docs/historia/revision/R6-gmu-erange.md`.

**Seguridad: ningún bug de seguridad encontrado.** Todo el código instrumentado se ejecuta en
contexto kernel por eventos de probe/resume, sin entrada controlable por userspace. Lo más
cercano es DoS por SError (B3: lectura de phys no-RAM cuelga el resume), que es
disponibilidad, no ruptura de frontera. No hay escritura arbitraria alcanzable.

**Veredicto en 3 líneas:** R6 es correcto en lo del `-ERANGE` (TTBR1, lo corroboro abajo) pero
le falta el bug más grave del sharing K20: **los dos VM comparten un `msm_mmu` sin refcount y
`msm_gem_vm_free` lo destruye dos veces** (B1: UAF real que convierte el `-ERANGE` en oops en
el unwind). El "discriminador" K24 **`uke_k19_walk_to` no puede discriminar nada**: decodifica
bits de atributo como tipo de descriptor y propaga ttbr sin alinear (B2). Y el volcado K19 en
resume lee MMIO sin runtime-PM ni validar ID1 (B3: cuelgue/SError).

---

## Prioridad 1 — B1: doble-destroy del `msm_mmu` compartido (UAF). El `-ERANGE` termina en oops

Ficheros: `drivers/gpu/drm/msm/adreno/a6xx_gmu.c:2043-2052`, `:1963-1976`,
`drivers/gpu/drm/msm/msm_gem_vma.c:159-170`, `:694`,
`drivers/gpu/drm/msm/msm_gpu.c:1055-1061`,
`drivers/gpu/drm/msm/msm_iommu.c:710-716`,
`drivers/gpu/drm/msm/adreno/a6xx_gpu.c:2772-2777`, `:2300-2324`.

Cadena verificada:

1. `a6xx_gmu_memory_probe` (`a6xx_gmu.c:2043-2045`) reutiliza `to_msm_vm(gpu->vm)->mmu`
   para `gmu->vm = msm_gem_vm_create(...)` (`:2052`). Dos `msm_gem_vm` distintos, **un solo
   `msm_mmu`, sin refcount** (`msm_gem_vm_create` en `msm_gem_vma.c:815+` no referencia al mmu).
2. `msm_gem_vm_free` (`msm_gem_vma.c:159-170`, registrado en `:694`) hace
   `vm->mmu->funcs->destroy(vm->mmu)` **incondicional**. `msm_iommu_destroy`
   (`msm_iommu.c:710-716`) hace `iommu_domain_free + kmem_cache_destroy + kfree` sin detach
   interno.
3. Camino probe-fallo (exactamente el #458 con `-ERANGE`): `a6xx_gmu_memory_alloc` falla →
   `err_memory` → `a6xx_gmu_memory_free` (`a6xx_gmu.c:1963-1976`: `detach(mmu)` +
   `drm_gpuvm_put(gmu->vm)` → **destruye el mmu compartido**) → retorno con error →
   `a6xx_gpu_init` (`a6xx_gpu.c:2772-2777`) llama `a6xx_destroy` → (`:2300-2324`)
   `a6xx_gmu_remove` (no-op: `initialized==false`, `a6xx_gmu.c:2598-2602`) →
   `adreno_gpu_cleanup` → `msm_gpu_cleanup` (`msm_gpu.c:1055-1061`: `detach(mmu)` +
   `drm_gpuvm_put(gpu->vm)` → `msm_gem_vm_free` **destruye el mismo `msm_mmu` por segunda
   vez**). Doble `iommu_domain_free` + doble `kfree` = **use-after-free en slab**; el segundo
   `detach` toca un `domain` ya liberado.
4. Camino unbind con probe OK: el mismo doble-free (los dos `put` llegan a cero cada uno).

Modo de fallo concreto: tras cualquier fallo de `gmu_init` (incluido el `-ERANGE`), el unwind
emite la tormenta de WARNING/oops **encima** del doble-`put` de BOs que describe R6 §1.3
(son dos doble-free independientes, este es del objeto MMU, aquel de los GEM); y en re-probe
el dominio/CB liberado y reutilizado deja el SMMU en estado incoherente (candidato a los
`-EBUSY`/`-16` "en la GPU" de #459/#460 y al "GPU no probea" del ciclo s260+`shared=0` si el
slab se corrompió antes). **Fix mínimo:** `bo->obj = NULL` no basta aquí; hay que no compartir
el `mmu` sin dueño claro — p. ej. refcount en `msm_mmu`, o que `a6xx_gmu_memory_free` no haga
`detach/destroy` cuando `mmu == mmu-del-GPU` (el dueño es el vm del GPU).

Nota: adjudico a favor de R6 §6.1 contra la premisa K27 — `gpu->vm` **sí** existe en
`gmu_init`: `adreno_gpu_init` (`adreno_gpu.c:1185-1242`) retorna `msm_gpu_init(...)` (`:1242`),
que crea `gpu->vm` (`msm_gpu.c:974`) antes de volver a `a6xx_gpu_init` → `a6xx_gmu_init`
(`a6xx_gpu.c:2772`). La rama de compartir **sí** se tomaba en #458. K27 resolvía un problema
inexistente y R6 §4.2 tiene razón en pedir su reversión (además K27 reintroduciría este mismo
B1 por la vía del mmu cacheado).

## Prioridad 2 — B2: `uke_k19_walk_to` informa basura en todos los niveles bajo la raíz

Fichero: `drivers/gpu/drm/msm/adreno/a6xx_gmu.c:395-492`.
Referencia correcta: `drivers/iommu/io-pgtable-arm.c:67-72` (tipo en bits[1:0]: 01=bloque,
11=tabla/página), `:168-183` (`iopte_leaf`/`iopte_table`), `:74`
(`ARM_LPAE_PTE_ADDR_MASK = GENMASK_ULL(47,12)`).

Dos bugs independientes, ambos deterministas:

- **B2a — el `fmt` no es el tipo.** `fmt = (d>>2)&0x7` (`a6xx_gmu.c:152,385,441,480`)
  lee bits[4:2] = AttrIndx, no el tipo. La condición "es tabla, bajar"
  (`((desc>>2)&0x7)!=0`, `:435`) y "es hoja fmt==0" (`:480`) dependen de atributos:
  un puntero a tabla con AttrIndx=0 se informa como **"HOJA… MAPPING ENCONTRADO" con
  phys = dirección de la tabla L1** (`:437-442`); un bloque-hoja con AttrIndx≠0 se trata
  como tabla y se recursa dentro de phys de RAM mapeada como pagetable. Cada veredicto
  `MAPPING ENCONTRADO`/`HUECO` bajo la raíz es indistinguible de ruido. Modo de fallo:
  el proyecto puede dar por bueno (o por ausente) el mapeo del icache con evidencia
  fabricada por el propio instrumento.
- **B2b — ttbr hijo sin alinear y máscara corta.** `:436` y `:486-487` propagan
  `(desc & 0x0000ffffffffffULL)`: conservan los 12 bits bajos de flags (todo descriptor
  válido termina en `1/3/7…`) y cortan en el bit 40 (la máscara real llega al 47).
  `memremap` alinea por dentro, así que no peta: **lee la tabla desplazada 1-7 bytes**,
  todos los `desc` de nivel ≥1 son basura. (El TTBR raíz de `dump_kgsl` sí se enmascara
  bien con `& ~0xfffULL` en `:580`; inconsistente.) Incluso con B2a arreglado, el walk
  seguiría leyendo entradas desalineadas.

Secundarios del mismo bloque (no cuelgan, solo confunden): raíz modelada como "LPAE-32,
4 entradas" (`:429-431`) cuando el dominio es `ARM_64_LPAE_S1` (para IAS=32 son 4 vivas y
el idx=0 del 0x4000 coincide por accidente; con IAS>32 e iova≥4GB el idx trunca);
`max_idx=1024` en niveles 2+ (`:460`: con grano 4K son 512 entradas de 9 bits —
`bits_per_level = 12-3`, `msm_iommu.c:500-505`) con guarda `idx*8>=4096` (`:464`) que
convierte iovas con el bit 21 puesto en falso "ABORTA (geometria inesperada)"; el volcado
plano `e[4..7]` (`:602-605`, mapeo de solo 64 B) lee palabras válidas pero —según el
propio comentario `:606-613`— más allá del final de una raíz de 4 entradas.

## Prioridad 3 — B3: el volcado K19 cuelga el resume (PM + ID1 sin validar + WB a ciegas)

Fichero: `drivers/gpu/drm/msm/adreno/a6xx_gmu.c:495-629`, llamado en `:702-703`.

- **B3a — MMIO sin runtime-PM.** `uke_k19_dump_kgsl` hace `ioremap(0x3da0000)` + decenas de
  `readl` al kgsl-smmu sin `pm_runtime_get`. El SMMU cuelga de `GPU_CC_CX_GDSC`
  (`palawan.dtsi:2576`); en el camino de resume ese reloj puede estar gated → el primer
  `readl` cuelga el bus (mismo modo de fallo que el machine-check del #449 citado en el
  propio comentario `:687-701`). Solo es seguro en probe temprano con relojes del BL.
- **B3b — `cb_base` sin validar, underflow.** Si `ID1` sale basura (reloj gated: `0xFFFFFFFF`):
  `pgshift=16, numpage=256, cb_base=0x1000000` (`:519-525`); `cb_end > SIZE` (`:533`) calcula
  `(0x40000-0x1000000)` en u64 (wrap) truncado a `u32` (`:534`) → `numcb` gigante → capado a
  128 (`:538-539`) → hasta 128 `readl` en `base+0x1000000+i*0x10000` (físico ≈`0x4DA0000+`,
  fuera del recurso, quizá sobre TZ/RAM ajena). Falta la guarda `cb_base >= SIZE → abortar`.
- **B3c — `MEMREMAP_WB` sobre phys no verificado.** `memremap(ttbr,4096,MEMREMAP_WB)` (`:420`)
  y `memremap(ttbr,64,…)` (`:595`) solo exigen `ttbr < 4G` (`:408,:589`). Un TTBR stale que
  apunte a MMIO (<4G, p. ej. al propio `0x3da0000`) o a memoria segura → SError en el resume.
  (La elección WB es coherente con `dma-coherent` del nodo, `palawan.dtsi:2577`, para RAM;
  el problema es la ausencia de prueba de "es RAM").

Estado actual: con `uke_smmu_dump=0` por defecto (BSS, `0444` solo-cmdline, `:360-363`) el
volcado **no** corre — conforme con docs/historia/AGENTS.md r3. Pero `a6xx_gmu_start` **sí corre en cada
resume**: `pm_resume` (`a6xx_gpu.c:2132-2137`, `needs_hw_init=true`) → `hw_init`
(`:1544-1553`) → `a6xx_gmu_start` (`a6xx_gmu.c:1467` en `hw_init`), también vía submit tras
idle y `recover` (`:1564+`). Con él corren siempre: ~30 `uke_poke` (S0/S1/S2/K19/S3/S4,
F1/F2/F3/F4, H1-H10, P1-P3, G5-G9, Z4) y el `gmu_read` DTCM de S0 (`:639-641`). `uke_poke`
(`uke-panic-fb.c:240-257`) es solo escritura a RAM + `pr_info`: no lee MMIO/SMMU, no viola
r3, pero cada poke son ~512 KB de `__raw_writel` + pintado de texto en el camino caliente
del resume (lento, no colgante). **Cualquier `uke_smmu_dump=1` en cmdline reactiva B3a-c en
ese camino.** El lado arm-smmu está limpio en runtime: todos los `UKE-*` con MMIO están en
probe/reset/attach (`arm-smmu.c`, `arm-smmu-qcom.c`, `arm-smmu-impl.c`), solo `pr_info` en
`attach` (`arm-smmu.c:2561-2569`, una relectura GR0 del apps-smmu, una vez por attach).

---

## El `-ERANGE`: posición (corrobora R6, añade el eslabón B1)

Corroborado por lectura directa (mismas líneas que R6): único `-ERANGE` del camino en
`io-pgtable-arm.c:599-600` (`WARN_ON(iaext || paddr>>oas)`); con TTBR1
(`:597-598`, `iaext=~iaext`) **todo** iova bajo falla; TTBR1 solo para SID 0
(`arm-smmu-qcom.c:371-372` retorno temprano si no-GPU, `:379-382` quirk + geometría
mitad-alta en `arm-smmu.c:1904-1906`); el VM del GPU vive arriba
(`adreno_gpu.c:217`, `start=max(SZ_16M, aperture_start)`) mientras el del GMU es fijo
`[0,0x80000000)` (`a6xx_gmu.c:2052`) y el primer fijo en caer es `debug@0x60400000`
(`:2808`), no el icache. Bajo s260 (GPU SID 0 en `palawan.dtsi:2381`, GMU SID 5 en `:2501`)
compartir→ERANGE y propio→OK-mapeos; bajo s263 (GPU a SID 5) propio→EBUSY y compartir→OK.
Nada que añadir al diagnóstico; **lo que R6 no vio es que ese `-ERANGE` dispara B1** (§1.3 de
R6 describe el doble-`put` de BOs; el doble-`destroy` del mmu es otro bug, peor: corrompe
slab y deja el dominio/CB en estado indefinido para el siguiente probe).

## DT (`palawan.dtsi` de k18-tree): 3 hallazgos

- **D1 — el segundo link DSI no puede funcionar con este DT.** `dsi@ae96000:3603` y
  `phy@ae97000:3643` en `disabled`, y los `dsi1_out:3620-3621` / `dsi0_out:3523-3524` sin
  `remote-endpoint` (panel cableado solo por overlay). El fix K29 (`phy1→okay`) está en el
  diff acumulado pero **no** en este dtsi → tal cual, el link 1 da
  `dsi_get_phy: phy driver is not ready` y el conector queda `disconnected` aunque el
  overlay habilite el resto. Coherente con el síntoma vivo. (El `video=DSI-1:d` fuerza OFF
  por `drm_modes.c:2007-2011`; quitarlo expone el panel a medio declarar → cuelgue: no es
  bug del DT base, es overlay incompleto + cmdline.)
- **D2 — `display-controller@ae01000` (`:3390`) sin `iommus` ni `status`.** Solo el padre
  `mdss` lleva `iommus 0x1c00/0x2` (`:3379`). El fallback `iommu_attach_group` de
  `msm_iommu.c:779-797` (K13) asume la config **del overlay s260** (mdss+mdp con la misma
  banda, dos dispositivos, un grupo). Si el overlay del ciclo no añade `iommus` al mdp, el
  K13 no se activa y `msm_kms_init_vm` usa otro `iommu_dev` del documentado en el comentario
  (`msm_kms.c` hunk K13): el comentario del código y el DT base describen hardwares
  distintos. Riesgo de `-EINVAL` silencioso en `dpu_kms_mmu_init`, no de cuelgue.
- **D3 — `gpu:2392` en `disabled` frente a `gmu:2470` sin `status` (vivo) y
  `adreno_smmu:2536` sin `status` (vivo).** Asimétrico pero benigno (el GMU no tiene driver
  propio; vive del probe del GPU). Solo anotarlo para que ningún gate "¿está el GMU
  habilitado?" lea el DT base y concluya nada: todo lo display/GPU (mdss `:3388`, dsi0
  `:3506`, phy0 `:3565`, dsi1, phy1, dp0 `:3686`, gpu) depende del overlay.

## Lista de runtime (qué instrumentación corre fuera del arranque)

| Sitio | Corre en resume/submit/recover | Lee SMMU/MMIO |
|---|---|---|
| `uke_poke*` en `a6xx_gmu_start`/fw/hw (30+) | sí | no (FB-RAM + pr_info) |
| `gmu_read` DTCM S0 (`:639`) | sí | MMIO GMU con relojes ya votados (P3 antes que H8) — OK |
| `uke_k19_dump_kgsl` + `walk_to` | sí **solo si** `uke_smmu_dump=1` (cmdline) | **sí (B3)** |
| `UKE-*` en `arm-smmu*.c` | attach una vez; resto probe/reset | no en map/unmap |
| `UKE-P82` en panel | probe del panel | no |

## Fixes mínimos sugeridos (orden)

1. B1: no compartir `msm_mmu` sin propiedad (o refcount, o skip detach/destroy del lado GMU).
   Sin esto, cada ciclo que falle `gmu_init` corrompe slab.
2. B2: reescribir el walk con `iopte_type` (bits[1:0]) y `ttbr = desc & GENMASK_ULL(47,12)`;
   hasta entonces, ignorar sus veredictos bajo la raíz.
3. B3: `pm_runtime_get_if_active` alrededor de los `readl`, guarda `cb_base >= SIZE`, y
   comprobar RAM (`region_intersects`-style como `uke-panic-fb.c:551-563`, que sí falla
   cerrado) antes de `memremap`; mantener `uke_smmu_dump=0` por defecto.
4. D1: traer el `phy1→okay` del acumulado a este dtsi o al overlay del ciclo.
5. R6 §4.3 (`bo->obj=NULL` en `a6xx_gmu.c:2007`) sigue pendiente y es independiente de B1.
