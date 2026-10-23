# CONFRONTA-GPU #541 — Hallazgos 6/7-oct vs comportamiento Android (CM3/GMU)

**Fecha**: 7-oct-2026. **Rol**: crítico confrontador. Tablet EN FASTBOOT — cero adb/fastboot (100 % offline).
**Método**: cada hallazgo de hoy se confronta contra la captura Android FULL (`build/evidencia/android-full/
extracted-full/`), el DT vivo Android decodificado (`14-dt/dt-live.tar.gz` extraído y leído prop a prop,
rutas `/tmp/dt-live`), las FUENTES del driver vendor (`~/proyectos/ubuntu-uke/vendor-src/cliffs/`,
gpucc-cliffs.c + qcom,gpucc-cliffs.h), nuestro DT fusionado (`/var/tmp/uke-s270/m270.dts`, s271 en
`/var/tmp/uke-s271/`), el árbol k52-tree y los logs de consola reales de k58/k59 (fin de
`/var/tmp/uke-console2.log`, offsets 3.82 GB).

**Veredicto en una línea**: el hallazgo de hoy "el fw NO EJECUTA y el poll expira" sobrevive la
confrontación; la explicación dominante de INV-CM3 #540 (CB1 vacío por el hack K20) **NO sobrevive**
(k58 con dominio propio y mapas reales congeló igual); y el "freeze seco" es en realidad un **reset de
hardware instantáneo** (S3-rst0 → banner 0.000000 sin una sola línea intermedia, loop de ~10 s medido en
`uke-console2-trz.log`), lo que apunta a un actor fuera de la CPU (AOP/PDC/RSC o el propio CM3 con
SYS_BUS=1), no a un hung-task ni a un panic tardío.

---

## 1. TABLA DT vendor (vivo) vs port (m270.dts = base + s270)

### 1.1 GMU (`qcom,gmu@3d69000` — idéntica dirección en ambos)

| Prop | DT vivo Android | m270.dts (port, s270) | Veredicto |
|---|---|---|---|
| compatible | `qcom,gen7-gmu` | `qcom,gen7-gmu` | ✓ igual |
| reg | `3d68000+0x37000` (gmu), `b280000+0x10000` (gmu_pdc), `3d40000+0x10000` (ao_blk_dec0) | igual **+ `3d50000+0x10000` (rscc)** | port AÑADE rscc (lo exige `a6xx_gmu_rpmh_init` mainline; el vendor NO reclama rscc en el GMU — lo reclama kgsl-3d0). **Doble reclamación rscc GPU+GMU en el port** (ya anotado #515) |
| reg-names | `gmu,gmu_pdc,gmu_ao_blk_dec0` | + `rscc` | ver arriba |
| clock-names | `gmu_clk cxo_clk axi_clk memnoc_clk ahb_clk hub_clk` (6) | `ahb gmu cxo axi memnoc hub demet` (7) | port añade `demet` (mainline sm8650 también lo lleva; inofensivo) |
| clocks (gpucc) | CX_GMU=**9**, CXO=**11**, AHB=**2**, HUB_CX_INT=**20** (numerario vendor) | AHB=**0**, CX_GMU=**7**, CXO=**9**, HUB_CX_INT=**18** (0x12), DEMET=**10** (numerario nuestro) | ✓ internamente CONSISTENTE: cada DT usa los ids de SU header. Verificado contra `qcom,gpucc-cliffs.h` (vendor: AHB=2, CX_GMU=9, CXO=11, DEMET=12, HLOS1=17, HUB_AON=18, HUB_CX_INT=20) y `qcom,palawan-gpucc.h` (AHB=0, CX_GMU=7, CXO=9, DEMET=10, HLOS1=15, HUB_CLK_SRC=17, HUB_CX_INT=18). Los GATES FÍSICOS habilitados por el GMU son los mismos. ✓ |
| clocks (gcc) | axi=gcc **18**, memnoc=gcc **32** | axi=gcc 18 (0x12), memnoc=gcc 32 (0x20) | ✓ mismo id en ambos headers (`GCC_DDRSS_GPU_AXI_CLK=18`, `GCC_GPU_MEMNOC_GFX_CLK=32`) → mismos gates físicos |
| **memory-region** | **NO EXISTE** | NO existe | ✓ PARIDAD: el vendor NO da carveout al GMU; el fw/HFI/icache van mapeados por SMMU (pregunta A) |
| qcom,gmu-fw-* | NO existe | NO existe | ✓ paridad (pregunta A) |
| iommus | `<kgsl_smmu 5 0>` (phandle 0x1c1, SID 5) | `<0x1c1 5 0>` | ✓ idéntico (SID 5 del kgsl-smmu en ambos) |
| mboxes / mbox-names | `<aop_qmp 0>` / `"aop"` | `<0x3b3 0>` / `"aop"` | ✓ heredado del vendor (el driver mainline lo IGNORA — ver E) |
| **qcom,qmp** | **NO EXISTE** en el GMU (el vendor usa mboxes) | s270: NO existe · **s271 lo añade AL NODO GPU, NO al GMU** (fragment@1712 target `/soc/qcom,kgsl-3d0@3d00000`) | **BUG s271**: `a6xx_gmu.c:3011` hace `qmp_get(gmu->dev)` → busca `qcom,qmp` en el nodo del GMU → NULL → **qmp_send(acd) NUNCA se ejecutó** (ni siquiera el OFF "harmless"). Corrige INV-CM3 #540 §1.1 |
| power-domains | NO (usa `vdd-supply`/`vddcx-supply` reguladores: gx_gdsc 0x401 / cx_gdsc 0x1bd) | `<gpucc 0>, <gpucc 1>` = CX_GDSC/GX_GDSC como PM domains (estilo mainline sm8650) | equivalente funcional (CX vivo verificado: MMIO del GMU responde) |
| qcom,gmu-freq-table | 220 MHz/0x40, 550/0x80 | opp-table 220/level 0x40, 550/0x80 | ✓ igual (formato OPP mainline) |
| qcom,iommu-dma | "disabled" | "disabled" | ✓ |
| qcom,ipc-core | 0x400000/0x140000 | igual | ✓ |
| interrupts | hfi=SPI 304, gmu=SPI 305 | igual | ✓ |

### 1.2 kgsl-smmu (`kgsl-smmu@3da0000` — el nodo del abort 0x96000010)

| Prop | DT vivo Android | m270.dts (port) | Veredicto |
|---|---|---|---|
| compatible | `qcom,qsmmu-v500`, `qcom,adreno-smmu` | `qcom,palawan-smmu-500`, `qcom,adreno-smmu`, `qcom,smmu-500`, `arm,mmu-500` | port usa la pila mainline (arm-smmu); vendor usa SU driver (el dmesg "probing hardware configuration" es igual de formato, pero el código es distinto) |
| reg | `3da0000+0x40000`, `3de6000+0x40` (tcu-base) | igual | ✓ |
| clocks (gpucc) | hlos1=**17**, ahb=**2** (numerario VENDOR: 17=HLOS1_VOTE, 2=AHB) | **mismos ids 0x11=17 y 0x02=2** — pero los consume NUESTRO header: **17=HUB_CLK_SRC, 2=CRC_AHB** | **⇒ DIFERENCIA #1 CONFIRMADA**: el port habilita HUB_CLK_SRC+CRC_AHB donde el vendor habilita HLOS1_VOTE+AHB. **HLOS1_VOTE_GPU_SMMU (id 15 nuestro) NO lo habilita NADIE en el port**; AHB solo queda on por el refcount del bulk del GMU (id 0 en la lista del GMU). Los gcc (memnoc=32, snoc=33) sí son correctos en ambos headers |
| clock-names | `gpu_cc_hlos1_vote_gpu_smmu, gcc_gpu_memnoc_gfx, gcc_gpu_snoc_dvm_gfx, gpu_cc_ahb` | idénticos | nombres bien, ids mal (solo los 2 gpucc) |
| **power-domains** | NO (usa `vdd-supply` = cx_gdsc — SU driver SÍ consume reguladores) | NO power-domains, `vdd-supply = <0x1bd>` (cx_gdsc) | **⇒ DIFERENCIA #2**: arm-smmu mainline IGNORA `vdd-supply`. El mainline de referencia (sm8650.dtsi) SÍ lleva `power-domains = <&gpucc GPU_CX_GDSC>` en este nodo — **a nuestro DT le falta**: nada ata la vida del TCU a la CX GDSC |
| qcom,actlr | `<0 0x3ff 0x32b>` | idéntico | ✓ (aunque #515 nota: vendor lo aplica a TODOS los SIDs vía su driver; mainline solo al compatible adreno → SME(0)) |
| #global-interrupts / 22 IRQs / #iommu-cells=2 / dma-coherent / use-3-lvl-tables | ✓ | ✓ | ✓ paridad |
| gpu_qtb@3de8000 (TBU) | presente, reg `3de8000+0x1000, 3dec000+0x1000`, iova-width 49, 2 qtb-ports, interconnects | presente (fusión del base) | inerte: el driver TBU mainline solo matchea `qcom,sc7280-tbu`/`qcom,sdm845-tbu` → nunca binda (archivo #515 correcto) |
| Estado clocks en captura (GPU activa-era, idle con IFPC) | hlos1 **N**, ahb **N**, cx_gmu **Y 220 MHz**, hub_cx_int **Y 200**, hub_aon **Y 200**, hub_clk_src **Y 200** | — | el vendor APAGA las gates del SMMU en idle (IFPC) — leer la SMMU con la isla dormida daría abort TAMBIÉN en Android. El abort de k56 no es anómalo en sí; el instrumento sí |

### 1.3 GPU (`qcom,kgsl-3d0@3d00000`)

| Prop | DT vivo Android | m270.dts (port, tras fragment@1450) | Veredicto |
|---|---|---|---|
| compatible | `qcom,adreno-gpu-gen7-11-0`, `qcom,kgsl-3d0` | `qcom,adreno-43030b00`, `qcom,adreno` | ✓ estilos distintos, mismo chipid |
| chipid/model | 0x43030b00 / "Adreno732" (el vivo; el base decía Adreno735) | 0x43030b00 / "Adreno735" (resto del base) | cosmético |
| **iommus** | **NO tiene** (los SIDs van en los hijos de `qcom,kgsl-iommu@3da0000`: gfx3d_user=**SID 0**, gfx3d_secure=**SID 2**) | `<kgsl_smmu 0 0>` — **solo SID 0, sin SID secure** | **⇒ DIFERENCIA #3**: el port no declara el SID seguro. Mainline sm8650 usa dos entradas (0 y 1); en ESTE hw el secure del vendor es **SID 2**. Bomba POST-CM3 (zap seguro), no el muro actual |
| clocks | gcc memnoc 32, gcc snoc 33, gpucc ahb 2, apb_pclk | **VACÍOS** (truco v3b anti-icc) | el vendor habilita memnoc/snoc/ahb desde el GPU también (refcounts); en el port quedan solo via GMU/SMMU. Riesgo de refcount, no de gate ausente (AHB/MEMNOC ya on via GMU; SNOC on via SMMU) |
| interconnects | REAL: `mc_virt MASTER_GPUSS0 → config_noc SLAVE_GPUSS` (+ bus-table-ddr de 10 votos) | **VACÍO** + opp SIN `opp-peak-kBps` | el port NO vota ancho de banda DDR del GPU. No toca el CM3 (el GMU no pasa icc); afecta rendimiento post-CM3 |
| OPP | 9 niveles 255–950 con **`qcom,acd-level`** por nivel | 9 niveles 255–950, opp-level idénticos (0x190…0x38), **sin acd-level** (F3 aplazado a propósito) | ✓ niveles paridad; ACD diferido (ver E) |
| zap-shader | `memory-region = <gpu_microcode_region@9899a000>` (8 KiB) | idéntico (0x29e → 0x9899a000+0x2000) ✓ | ✓ paridad (el vendor tampoco tiene firmware-name en el zap: usa su catálogo) |
| reg | 7 regiones (kgsl, rscc, cx_dbgc, **cx_misc** 3d9e000+0x1000, qdss…) | 7 regiones (…, **cx_mem** 3d9e000+0x2000, …) | ✓ (nombres mainline; misma ventana) |
| syscons ACD/GX en DT vendor | `gpu_cc_gx_domain_addr@3d99504`, `gx_sw_reset@3d99058`, `gx_acd_reset@3d99358`, `gx_acd_iroot_reset@3d9958c` | presentes en m270 (herencia del base; nadie los consume en mainline) | el vendor tiene un camino de reset ACD/GX por syscon que mainline NO usa (su driver los usa vía techpack kgsl). Delta estructural — ver C |

---

## 2. SECUENCIA vendor reconstruida vs NUESTRA (paso a paso)

**Vendor (medido en dmesg-full 2.3→6.3 s + debugfs/sysfs; los pasos en cursiva son inferidos del flujo
downstream gen7, no hay fuentes msm_kgsl en disco (#535))**:

| t (s) | Vendor Android |
|---|---|
| 2.344 | gpucc registra clocks (todos apagados) |
| 2.345 | **arm-smmu 3da0000.kgsl-smmu probea: SMMUv2, 22 CB, stage-1 — ANTES de que exista el driver GPU**; su driver consume `vdd-supply` (CX GDSC) y las 4 gates (hlos1=17, memnoc, snoc, ahb=2 en numerario vendor, TODAS las correctas) |
| 2.967–2.99 | kgsl core Init/Ready; grupos IOMMU: gfx3d_user=17, gfx3d_secure=18, **adreno-gen7-gmu=19 (el GMU lleva SU PROPIO dominio desde el bind)** |
| 3.015–3.117 | binds de componentes; GPU Ready **SIN firmware**; 3.142 sync_state de rpmh (AOP drenado ANTES de tocar el GMU) |
| ~6.1 (primer open de /dev/kgsl-3d0) | carga perezosa de fw: sqe 6.131, gmu.bin 6.162 (el probe del GMU ya pasó; el boot del CM3 ocurre AQUÍ, con el sistema totalmente arriba y rpmh en sync_state) |
| *inferido* | *enable CX GDSC → bulk de sus 6 clocks (gmu/cxo/axi/memnoc/ahb/hub, gates correctas) → TCM retention propio → carga de segmentos ITCM/DTCM/icache YA dentro de SU dominio CB1 (su driver kgsl-iommu programó las tablas) → HFI_QTBL/BOOT_CONFIG → release reset → poll → HFI handshake → **ACD negociado con AOP vía mbox aop_qmp** (sysfs final acd=1) → GX pasa al GMU → IFPC* |
| idle capturado | cx_gmu Y, hub_cx_int Y, **hub_aon Y**, hub_src Y; ahb/hlos1/memnoc/snoc **N** (isla colapsada por IFPC, 6366 entradas) |

**Port (medido en k59, `/var/tmp/uke-console2.log` @3.82 GB, boot 7-oct)**:

| t (s) | Port k52/s270-s271 |
|---|---|
| 0.319 | arm-smmu kgsl-smmu probea (mainline; SIN dominio CX atado, con gates equivocadas 17/2) |
| 4.120 | G2-initOK → G3-icc → resume del GMU: bulk de 7 clocks OK (rates medidos k56: core=220, hub=200) |
| 4.121–4.124 | F1-fwloop → F2-itcm → F2-dtcm×2 → F3-loopOK → F4-verOK → H7-fw (**request_firmware del GMU en probe, 4.5.1 OK**) |
| 4.124–4.125 | P1 (FW_INIT_RESULT=0, BOOT_CONFIG=0x02) → P2 (HFI_QTBL=0x60008000) → P3 (SYS_BUS/ICACHE/DCACHE=1; a7xx early-return sin PWR_COL) |
| 4.126–4.127 | S0 (lee DTCM+0xff8 = 0x40050001 **pre-cargado por fw_load — NO evidencia**) → S1/S2 (SYSRESET=1 ×2 + GENERAL_9=0) → K44 A–E (todo sane; E "esperado" mal calculado, ver §4-d) |
| 4.14 | K19-dumpOK (SMMU dump desactivado desde k57) → **S3-rst0 (SYSRESET=0)** |
| 4.14+ | **muerte instantánea: banner del siguiente boot (0.000000) SIN una línea intermedia** — ni S4-poll, ni panic ("Kernel panic" aparecería con panic=10), ni hung-task (timeout 20 s, y hung_task_panic=0 en k58), ni soft-lockup (watchdog_thresh=10). **= reset de hardware** |

Diferencias de orden ANTES del reset (pregunta F, resumen):

1. El vendor probea SU SMMU con las gates CORRECTAS y con CX atado al nodo; el port probea arm-smmu sin dominio y con 2 gates equivocadas.
2. El vendor da al GMU su propio dominio IOMMU desde el bind (grupo 19) — el port también desde k58 (`uke_gmu_shared=0`): **paridad recuperada**.
3. El vendor hace sync_state de rpmh (3.142) ANTES del boot del CM3 (6.1+); el port arranca el CM3 dentro del probe, a mitad del boot del sistema, sin sync_state garantizado.
4. El vendor deja el boot del CM3 para el primer open (sistema quieto); el port lo hace en el resume del probe (con media sonda de subsistemas arrancando en paralelo).
5. **El port escribe en el RSC/PDC ANTES del reset y el vendor NO**: `a6xx_gmu_rpmh_init` (probe) graba uCode del sequencer RSC (`SEQ_MEM` 5 palabras de era-a650) + `PDC_GPU_ENABLE_PDC=0x80000001` en el bloque AOP 0xb280000, aunque `pdc_in_aop=true` — en el vendor ESO LO HACE EL AOP y el driver jamás toca esa memoria.
6. El vendor negocia ACD por mbox antes/durante el boot del fw; el port no puede (qcom,qmp en nodo equivocado, s271) — en cold boot AOP asume ACD off, así que aquí la paridad es "ambos off".
7. El vendor tiene 4 syscons de reset ACD/GX (3d99504/3d99058/3d99358/3d9958c) que su driver usa; mainline no los toca.

---

## 3. RESPUESTAS A–F

**A. Carveout vs SMMU / memory-region del GMU.** El vendor NO usa carveout para el GMU: el nodo vivo no
tiene `memory-region` ni `qcom,gmu-fw-*`; el fw/HFI/icache viven tras el SMMU (SID 5, dominio propio
desde el bind, grupo 19 en dmesg). El ÚNICO memory-region del GPU es el zap (8 KiB @0x9899a000) y el
port lo tiene idéntico. **Nuestro DT del GMU tiene el esquema correcto** (sin memory-region, SID 5,
dominio propio desde k58). El no-ejecuta no es un carveout mal puesto.

**B. ¿El CM3 sin RELOJ al soltar el reset?** NO como causa única — medido: en k56 `core=220000195
hub=200000000` (cx_gmu y hub_cx_int on), MMIO del GMU vivo, ITCM read-back = binario (K44 B). El CM3
TIENE reloj de core y de interface al soltar S3. PERO quedan 2 gates del "anillo" que en el vendor están
ON y en el port NADIE habilita: **gpu_cc_hub_aon_clk** (vendor: Y a 200 MHz SIEMPRE, incluso en idle con
la isla colapsada; port: ni el GMU, ni el SMMU, ni gpucc la marcan CRITICAL ni la enciende nadie) y
**gpu_cc_hlos1_vote_gpu_smmu_clk** (vendor: on cuando el SMMU de la GPU está activo; port: id equivocado
en DT, habilitación imposible). El fetch del CM3 pasa por TCU+hub: con hub_aon/hlos1 fuera del circuito,
la ruta fetch puede estar muerta aunque el core tenga 220 MHz — "ni ejecuta ni fault" de forma limpia.

**C. El freeze SIN panic.** Lo medido hoy refina el hallazgo: no es una desaparición genérica del USB; es
un **reset instantáneo de hardware** (S3-rst0 → siguiente banner 0.000000 sin ninguna línea; ciclo de
~10 s en `uke-console2-trz.log` 13:05–13:09). Con `hung_task_panic=0`, `panic=10` (habría impreso),
`watchdog_thresh=10` (habría tardado) — **el reset lo da alguien que no es la CPU**: (i) la secuencia
RSC/PDC que mainline programa en el probe (uCode a650 + ENABLE_PDC=0x80000001 sobre un bloque AOP que
el vendor jamás toca): si algo dispara el sequencer al soltar el CM3, AOP ejecuta una secuencia de
power no-válida en este SoC; (ii) el propio CM3 con SYS_BUS=1 (K44 C): si su primer fetch cae en algo
VÁLIDO pero equivocado (p.ej. resto de estado de arranque), un wild-write suyo a registros de
reset/AOSS mata la máquina sin rastro; (iii) glitch de dominio GX/CX vía los syscons ACD del vendor que
mainline no controla. El paso nuestro inmediatamente anterior a S3 que toca registros del dominio: la
pareja S1/S2 (SYSRESET=1 doble + GENERAL_9) y, unos µs antes, P3 y TCM_RET_CNTL=1 — pero el freeze es
POST-S3 en el 100 % de los casos, así que el disparador es el propio release. C1 (WALK: PA real del
fetch) sigue siendo EL experimento que separa (i)/(ii) de una traducción mala.

**D. El external abort de la kgsl-smmu.** El vendor deja las gates del SMMU a SU driver (numerario
vendor: hlos1=17, ahb=2) con CX atado por `vdd-supply`; además el vendor APAGA hlos1/ahb en idle (IFPC)
— leer la ventana CB con la isla dormida daría error TAMBIÉN en Android. El port: **habilita las gates
EQUIVOCADAS** (DT heredó ids vendor 17/2; nuestro header los traduce a HUB_CLK_SRC/CRC_AHB) y **no ata
CX al nodo** (mainline sm8650 lleva `power-domains = <GPU_CX_GDSC>` en la SMMU; nuestro DT no). El
abort 0x96000010 de k56 (lectura a +0x20000, DFSC=0x10) = el bus rechaza: isla semi-viva con gates mal.
Consecuencia práctica: el volcado K19 no es instrumento válido (ya desactivado en k57), y el fix DT es
trivial: ids gpucc `hlos1=0xf (15)`, `ahb=0x0` en el nodo kgsl-smmu + `power-domains = <CX_GDSC>`.

**E. ACD heredado / qmp.** Hallazgo NUEVO que corrige #540 §1.1: **s271 añadió `qcom,qmp` al nodo
GPU (fragment@1712 target `/soc/qcom,kgsl-3d0@3d00000`), NO al GMU** — `qmp_get(gmu->dev)` dio NULL,
`acd_probe` salió temprano y **qmp_send(acd,…) no se ejecutó NI UNA VEZ** (tampoco el OFF "harmless" del
comentario upstream). No hay línea acd_probe en ningún boot k5x (verificado: 0 hits). ¿Puede un ACD=1
heredado bloquear el CM3? En cold boot no: AOP recarga y asume ACD off (comentario upstream
a6xx_gmu.c:2108-2110); todas las pruebas han sido reboot/re-flash, no arranques calientes desde
Android. **ACD queda desclasificado como causa del muro** — pero el DT bug es real y hay que mover la
prop al nodo GMU para cuando llegue la negociación real (F3).

**F. Diferencias de orden.** Ver §2 (7 deltas listados). Las que el vendor hace ANTES del reset y
nosotros no: gates correctas del SMMU desde el probe (2.345 s), CX atado a la SMMU, sync_state de rpmh
antes del boot del CM3, boot perezoso en sistema quieto, ACD negociado, syscons ACD/GX bajo su control.
Las que hacemos nosotros y el vendor NO: escribir uCode+ENABLE_PDC en el RSC/AOP (probe), bulk de 7
clocks con demet, OPP del GMU en formato mainline (cosmético), fw en probe en vez de primer open.

---

## 4. LO QUE NO ENCAJA (correcciones a los hallazgos de hoy)

a. **"La máquina entera se congela en seco"** — incompleto: la consola de k59 demuestra reset HW
instantáneo (§2/C). El "a veces falla con gracia (k55/k56)" es el otro modo real (poll timeout +
call trace con la máquina viva): hay DOS modos de fallo, y k59 con pokes completamente impresos
también congeló ⇒ la tecla "instrumentos secos vs pr_flush" de #540 §4 **queda falsada por k59**
(pokes visibles y reset igual).

b. **CAUSA RAÍZ #1 de INV-CM3 #540 (SID5→CB1 default vacío)** — desmentida como causa única: k58
restauró el dominio propio (mapas reales en CB1, S2CR/SME idénticos al vendor) y **congeló igual**.
El estado SMMU ya es indistinguible del vendor por config; lo que queda por demostrar es el CONTENIDO
(WALK PA del fetch, C1, arsenal #525-pre aún sin ejecutar).

c. **"S2CR=0x00000001 = igual que el vendor"** — coincidencia superficial: mismo encoding TRANS, pero
en el vendor CB1 lleva las tablas del fw del GMU y en el port pre-k58 era el dominio default vacío.
El volcado SMMU no discrimina contenido, solo configuración.

d. **UKE-K44 E "fence_r0=80c808a0 (esp 0/8c8008a0)"** — el "esperado" del print está mal calculado: el
código escribe `BIT(31)|(0x32<<18)|0x8a0` = **0x80C808A0** (a6xx_gmu.c:1478-1480) y la lectura da
exactamente eso. El read-back es CORRECTO; no es delta ni anomalía.

e. **"qcom,qmp añadido en s271 (llegó a ejecutarse?)"** — NO llegó a ejecutarse (prop en nodo equivocado,
§3-E). Y ACD heredado no aplica en cold boots.

f. **Fw-map "iova=0x4000 dummy=0x60000000"** — coherente con Android en el sentido que importa: el
vendor TAMBIÉN mapea icache/HFI/log por SMMU (sin carveout, A). El 0x60000000 no es físico: es el BO
dummy del vm del GMU (el binario lo referencia en su TOC type=7 — paridad mainline/vendor).

---

## 5. DIFERENCIAS RANKEADAS por probabilidad de causar no-ejecuta/freeze

| # | Diferencia vendor→port | Evidencia ambos lados | Probabilidad | Fix |
|---|---|---|---|---|
| 1 | **Gates de la kgsl-smmu mal mapeadas: HLOS1_VOTE_GPU_SMMU nunca on (y ahb del SMMU solo por refcount del GMU)** | DT vivo: ids vendor 17/2 = hlos1/ahb reales (cliffs.h:12,27); m270.dts:16350 mismos ids; nuestro header 15/0 = hlos1/ahb → 17/2 = HUB_CLK_SRC/CRC_AHB; clk-summary vendor hlos1 consumer = 3da0000 | **ALTA para no-ejecuta** (ruta TCU/fetch muerta con core con reloj) | dtbo: ids `0xf`/`0x0` en kgsl-smmu |
| 2 | **RSC uCode + ENABLE_PDC=0x80000001 escritos por mainline sobre el bloque AOP que el vendor jamás toca** | a6xx_gmu.c:1133-1231 (setup_pdc SIEMPRE, pdc_in_aop incluido); vendor: pdc en AOP (DT reg gmu_pdc 0xb280000; dmesg sin tocar) | **ALTA para el reset instantáneo** (único mecanismo propuesto que puede resetear el SoC sin rastro; disparador: primera transacción de sleep/collapse al soltar el CM3) | parche: saltar rpmh_init completo para a7xx (o ENABLE_PDC=0) — 1 línea, decide |
| 3 | **kgsl-smmu sin power-domains (CX no atado al TCU)** | sm8650.dtsi (referencia mainline): `power-domains = <GPU_CX_GDSC>` en adreno_smmu; vendor vivo: vdd-supply cx_gdsc consumido por SU driver; m270.dts: sin PD y vdd-supply ignorado por arm-smmu | MEDIA-ALTA (ventana de isla semi-alimentada en el instante S3) | dtbo: añadir PD CX |
| 4 | **hub_aon nunca habilitada en el port** | clk-summary vendor Y SIEMPRE; ni DT ni driver del port la tocan (gpucc-palawan.c:428 sin CRITICAL; fuera de las 2 listas de clocks) | MEDIA (aon del hub: puede colgar el wake/la ruta de interface) | dtbo/driver: añadir hub_aon al bulk del GMU o CRITICAL |
| 5 | **qcom,qmp en nodo equivocado (s271)** → ACD/QMP sin canal | s271.dts fragment@1712 target GPU; a6xx_gmu.c:3011 lee el GMU; 0 líneas acd en logs | BAJA para cold-boot (AOP asume off), ALTA como deuda para F3/soak | mover prop al nodo GMU |
| 6 | **GPU sin SID secure (vendor: SID 2; port: solo SID 0)** | DT vivo gfx3d_secure iommus `<0x1c1 2 0>`; m270 GPU iommus 1 entrada; sm8650 usa 2 entradas | BAJA para el muro (es post-CM3), SEGURA como siguiente pared (zap seguro) | dtbo: segunda entrada iommus con SID 2 (y mapear secure en arm-smmu-qcom) |
| 7 | **sin sync_state/boot perezoso: CM3 arranca a mitad del probe con rpmh sin drenar** | vendor: sync_state 3.142 << boot CM3 ~6.1; port: fw_start en resume 4.12 con subsistemas aún probeando (pokes W:* alrededor) | MEDIA-BAJA (no explicaría ambos modos, pero es orden distinto) | diferir fw_start tras sync_state (costoso) — solo si 1-4 fallan |
| 8 | GPU interconnects vacíos / opp sin peak-kBps / sin acd-level | vivo: icc real + acd-level; m270: vacíos | BAJA para el muro (rendimiento post-CM3) | F3/F4 ya documentados |

**Conclusión confrontada**: el muro ya NO se explica por el mapeo IOMMU (k58 lo igualó al vendor); las
dos diferencias que sobreviven con capacidad explicativa real son la **#1** (gates HLOS1_VOTE/AHB del
TCU — no-ejecuta limpio) y la **#2** (RSC/PDC sobre AOP — reset instantáneo sin rastro), y no son
excluyentes: #1 explicaría por qué el CM3 no ejecuta, #2 por qué en vez de un timeout limpio a veces la
máquina muere entera. El orden de prueba barato: fix dtbo de gates (#1+#3, un solo dtbo) + parche de
ENABLE_PDC (#2, un kernel) con C1 (`msm.uke_smmu_dump=1` + WALK) armado en la misma cmdline.

## 6. EVIDENCIA

- DT vivo Android: `build/evidencia/android-full/extracted-full/14-dt/dt-live.tar.gz` (extraído; nodos
  `soc/qcom,gmu@3d69000`, `soc/kgsl-smmu@3da0000`, `soc/qcom,kgsl-3d0@3d00000`, `soc/qcom,kgsl-iommu@3da0000`,
  `reserved-memory/gpu_microcode_region@9899a000` — decodificados byte-level en esta revisión).
- Vendor fuentes: `~/proyectos/ubuntu-uke/vendor-src/cliffs/qcom,gpucc-cliffs.h` (ids 2/9/11/17/18/20),
  `gpucc-cliffs.c:459-475` (hub_aon sin CRITICAL).
- Port DT: `/var/tmp/uke-s270/m270.dts` (:14695 GPU, :16337 kgsl-smmu, :21863 GMU, :21846 kgsl-iommu vendor),
  `/var/tmp/uke-s271/s271.dts:15375` (fragment@1712 qcom,qmp al GPU).
- Port código: `build/kernel-pokes/k52-tree/drivers/gpu/drm/msm/adreno/a6xx_gmu.c` (:655-780 start,
  :1133-1231 rpmh_init/PDC, :1478 fence, :2114 shared=0, :2550-2611 acd, :3011 qmp_get),
  `include/dt-bindings/clock/qcom,palawan-gpucc.h`, `drivers/clk/qcom/gpucc-palawan.c:428`,
  `arch/arm64/boot/dts/qcom/sm8650.dtsi:4140-4300` (referencia mainline: PD en la SMMU, qcom,qmp en el GMU).
- Logs: `/var/tmp/uke-console2.log` offsets 3.82075-3.82083 GB (k59: secuencia F→S3-rst0→banner 0.000000
  sin línea intermedia; cmdline k58 con `msm.uke_gmu_shared=0`), `/var/tmp/uke-console2-trz.log`
  (ciclos de reenumeración ~10 s, 7-oct 13:05-13:11).
- Vendor captura: `15-common/dmesg-full.txt` (:334-407 fw lazy, grupos/bind en GPU-ANDROID-INV §a),
  `15-common/clk-summary.txt` (:104-170, :837-846), `15-common/regulator_summary.txt` (:28, :134).
- Informes confrontados: docs/historia/revision/GPU-ANDROID-INV-20261006.md, docs/historia/revision/GPU-PORT-INV-20261006.md, docs/historia/revision/INV-CM3-FALLO-20261007.md,
  docs/historia/revision/REV-GPU-DISPLAY-20261005.md (correcciones puntuales: §1.1 qmp, §4 reinTerpretación freeze, K44 E).
