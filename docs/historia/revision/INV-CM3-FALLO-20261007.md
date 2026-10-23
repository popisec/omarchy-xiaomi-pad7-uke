# INV-CM3 #540 — Diagnóstico OFFLINE del "CM3 no ejecuta" (GPU-on, uke/k52-tree)

**Fecha**: 7-oct-2026 (madrugada). **Autor**: investigador offline, sin tocar la tablet (congelada tras boot k57).
**Alcance**: auditoría de código del árbol k52-tree (kernel 7.2.0-rc2-palawan), DT fusionado m270.dts,
overlays s269/s270/s271, binario `gen71100_gmu.bin` (byte-level), dmesg vendor (android-full) y logs de
boot propios (k20/console2/sesion). Ledger base: #535–#539b.
**VEREDICTO ANTES DE LEER**: el "CM3 no ejecuta" de #536/#539 **no está demostrado**; dos instrumentos
que lo "demostraban" (discriminador dtcm-magic y poll FW_INIT_RESULT) están rotos por diseño en este
árbol+fw, y hay una causa raíz de código que explica que el CM3 muera (o toda la máquina) al soltar S3.

---

## 0. RESUMEN EJECUTIVO

1. **CAUSA RAÍZ #1 (mapeo del fetch del CM3, código probado)**: en los boots con GPU-on actuales
   (s270/s271), el fetch del CM3 sale por **SID 5 de la kgsl-smmu privada**, y ese stream está atachado
   al **dominio DEFAULT (vacío)** que el IOMMU core crea automáticamente cuando `a6xx_gmu_init()`
   llama `of_dma_configure()` (`a6xx_gmu.c:2861` → `iommu.c:678 iommu_setup_default_domain`). Los
   mapas del icache/HFI/log (incl. el cuerpo del fw @IOVA 0x4000) viven en el **CB0 (dominio del
   GPU)** porque el hack K20 comparte el mmu del GPU (`a6xx_gmu.c:2113 uke_gmu_shared=1`).
   **El CM3 ejecuta el vector de ITCM (no pasa por SMMU) y muere en el primer fetch fuera de ITCM.**
   El hack K20 nació bajo el dtbo **s263** (GPU iommus = SID 5 = mismo grupo que el GMU → attach
   propio daba `-EBUSY`). El fragment@1450 de s269/s270/s271 devolvió el GPU a **SID 0**
   (`s271chk.dts`: `iommus = <0x1c1 0x00 0x00>`), con lo que la premisa del hack YA NO CUAENTA y el
   dominio propio de mainline volvería a funcionar (el attach del dominio propio REEMPLAZA al default:
   `iommu.c:2360` solo da `-EBUSY` si el dominio vivo no es el default).

2. **CAUSA RAÍZ #2 (instrumentos muertos, byte-level probado)**: el discriminador "dtcm-magic" lee
   `DTCM + 0xff8` (`a6xx_gmu.c:663`) — y **0x40050001 está PRE-CARGADO EN EL PROPIO BINARIO** del fw
   (bloque `addr=0x10007fdc size=0x18` del contenedor, dato en file-offset 0x13b14). `fw_load()`
   escribe esa palabra ANTES de que `a6xx_gmu_start()` la lea ⇒ el discriminador da **STALE SIEMPRE**,
   ejecute o no el CM3 (k20 @24.107549, k55, k56: idéntico 0x40050001, determinista porque es contenido
   de la imagen). Peor: ese valor (>0x20010004) fuerza la **rama WARM del poll** (`mask=0x1ff,
   reset_val=0x100`, `a6xx_gmu.c:668-671`): en un COLD boot el fw escribe
   `FW_INIT_RESULT=0xbabeface`, que **no pasa** el check `(val & 0x1ff)==0x100` ⇒ **el poll expiraría
   incluso con un CM3 perfecto**, y el error-path re-assertea SYSRESET (K56 C, `a6xx_gmu.c:774-777`)
   matando el fw sano.

3. **La carga del fw NO es el problema**: el binario es un contenedor de segmentos que el parser
   mainline recorre EXACTO (verificado byte a byte, §3). K44 B (ITCM[0]=10007f80, ITCM[1]=00000105)
   coincide con las dos primeras palabras del binario (vector ARMv7-M: SP+reset) ⇒ la ventana ITCM
   recibe y retiene los datos. El "esperado" de K44 B viene de la propia imagen, no de un oráculo
   externo.

4. **External abort 0x96000010**: lectura → `DFSC=0x10 Synchronous External abort` (esclavo del bus
   responde error: isla sin reloj/poder en ese instante). Instrumento poco fiable; correctamente
   desactivado en k57 (`a6xx_gmu.c:755`). Detalle en §2.

---

## 1. AUDITORÍA PASO A PASO DEL GPU-ON (power-on → S3-rst0)

Todo en `build/kernel-pokes/k52-tree/drivers/gpu/drm/msm/adreno/a6xx_gmu.c` salvo indicación.
Puntos de entrada: `adreno_load_gpu()` (adreno_device.c:69) → `pm_runtime_get_sync` (:109) →
`adreno_runtime_resume` → `a6xx_gmu_resume()` (:1804).

| # | Paso | Línea(s) | Veredicto |
|---|------|----------|-----------|
| H1 | `pm_runtime_get_sync(gmu->dev)` | 1817 | **OK**: el dev del GMU no tiene dominio PM propio; el CX GDSC sube por el device-link (H2/H1 camino cxpd). Evidencia: los MMIO del GMU responden (K44 A-E con valores plausibles). |
| H2 | `a6xx_gmu_gxpd_get()` | 1753-1774, 1820 | **OK aparente** (GX GDSC refcount; A6x/A7x "no hace nada" real: el vendor también dice GX no gobernable, #535). |
| H3 | rates + `clk_bulk_prepare_enable(7 clocks)` | 1824-1831 | **OK**: 7 clocks del DT (§1.1); K56 A: `hub=200000000` (C3 aplicado). En un boot k5x antiguo se vio `core=220000195 hub=400000000` (uke-sesion-console.log:114872) — antes del fix. |
| H3.1 | print clks | 1838-1840 | OK. |
| H3.5 | `a6xx_gmu_secure_init()` | 1695-1751, 1842 | **DESPISTADO (no toca)**: sólo aplica a a750/a8xx (SCM fuse); gen71100 (ADRENO_7XX_GEN2) no entra por a750/a8 ni a740 (:1706,:1743). No-op. |
| H4 | clr/mask IRQ GMU + `enable_irq` | 1853-1856 | OK. |
| H5 | cold/warm: a7xx lee `CX_MISC_TCM_RET_CNTL` (reg "cx_mem" 0x3d9e000; a6xx_gpu.c:2732, a6xx_gpu.h:258-261) | 1859-1871, 1873-1877 | **OK**: `UKE-K56 A: boot=COLD TCM_RET=0` — el ESTADO se detecta BIEN aquí. (Ojo: este `status` correcto NO llega a `a6xx_gmu_start`, ver F-BUG.) |
| H6 | `a6xx_gmu_fw_start(gmu, COLD)` → FAL veto (`CX_FAL_INTF`, 1424-1429); TCM retention `TCM_RET_CNTL=1` vía cx_misc (1433-1434); `a6xx_rpmh_start()` (1438, 1073-1101: sólo si bit PDC_SLEEP; en el primer resume es no-op por diseño upstream) | 1412-1443 | **OK** (pokes H6-rsc en logs). |
| H7 | `a6xx_gmu_fw_load()` (COLD) | 1445-1455, 1329-1410 | **OK — verificado byte-level (§3)**: ITCM 2 bloques, icache BO 1 bloque, DTCM 2 bloques de cola. `F1/F2-itcm/F2-dtcm×2/F3/F4` en logs exactamente como predice el parser. |
| P1 | `FW_INIT_RESULT=0`; `BOOT_CONFIG=0x02` | 1459-1460 | OK (escritura). (BOOT_CONFIG=0x02 = upstream; el vendor puede usar otro valor, no medible offline — no es sospechoso primario.) |
| P2 | HFI_QTBL_ADDR=iova(HFI), INFO=1 | 1464-1465 | Escritura OK; el VALOR (0x60008000) sólo sirve si el S1 del SID5 traduce (aquí está el nudo, §4). |
| P2.5 | fence range 0x8a0/0x32 (a7xx), `CM3_CFG=0x4052`, chipid=0x70b0000 (`gmu_chipid`, a6xx_catalog.c:1625) | 1468-1520 | OK. |
| P3 | `a6xx_gmu_power_config()` | 1533, 1267-1307 | **OK**: SYS_BUS/ICACHE/DCACHE=1 (K44 C los lee=1 ✓); a7xx: early-return (:1278), no toca PWR_COL. |
| S0 | **LECTURA dtcm-magic** `DTCM_START+0xff8` | 662-671 | **ROTO**: lee 0x40050001 **pre-cargado por H7** (§3.2) ⇒ rama WARM `mask=0x1ff/reset=0x100` en CADA cold boot. |
| S1/S2 | SYSRESET=1 (×2, con wmb) + GENERAL_9/resp=0 | 696-711 | OK. |
| K44 | lecturas ITCM/ICACHE_CFG/HFI_QTBL/fence | 719-737 | **OK como lectura**; K44 B "esperado" = contenido del binario (no prueba ejecución). |
| K19 | dump SMMU (+0x20000) | 755-756 | **NO-OK como instrumento**: external abort (§2); k57 lo desactiva. |
| S3 | **SYSRESET=0** (suelta CM3) | 762 | OK como escritura; a partir de aquí el CM3 depende del S1 del SID5 (§4). |
| S4 | poll `FW_INIT_RESULT` | 770-777 | **ROTO (rama WARM)**: espera `(v&0x1ff)==0x100`; un fw COLD sano escribe 0xbabeface (0xbabeface&0x1ff=0xce) ⇒ **falso FAIL**; y si falla, re-assert SYSRESET mata el fw (774-777). |
| H8+ | hfi_start, HFI IRQ, freq inicial | 1553-1558, 1885-1901 | No llega. |

### 1.1 Clocks y dominios (DT fusionado m270.dts, nodo GMU :21863)

- `clock-names = "ahb","gmu","cxo","axi","memnoc","hub","demet"`;
  `clocks = <gpucc 0>, <gpucc 7>, <gpucc 9>, <gcc 0x12>, <gcc 0x20>, <gpucc 0x12>, <gpucc 0x0a>`
  → con `qcom,palawan-gpucc.h`: **GPU_CC_AHB_CLK(0), CX_GMU_CLK(7), CXO_CLK(9), DEMET(10),
  HUB_CX_INT_CLK(18)** + 2 de gcc. `a6xx_gmu_clocks_probe()` (2616-2632) hace
  `devm_clk_bulk_get_all` + busca "gmu" y "hub" **por nombre** ⇒ coincide con los nombres del DT
  vendor. **OK**.
- `power-domains = <gpucc 0>, <gpucc 1>` (= **CX_GDSC, GX_GDSC**, gpucc.h:53-54) con
  `power-domain-names = "cx","gx"` ⇒ `dev_pm_domain_attach_by_name("cx"/"gx")` (2994, 3021) funciona.
  **OK** (CX vivo: los MMIO del GMU responden).
- `reg-names = "gmu","gmu_pdc","gmu_ao_blk_dec0","rscc"`, `gmu_pdc` = 0xb280000 (AOP): a7xx es
  `pdc_in_aop` (1153-1155) ⇒ no necesita `gmu_pdc_seq`. **PDC seq OK** (y en cold boot ni corre:
  PDC_SLEEP no está seteado). Registers CM3: ITCM=+0x1b400, DTCM=+0x1c400, SYSRESET=+0x1f800,
  FW_INIT_RESULT=+0x1f81c (registers/adreno/a6xx_gmu.xml:45-67), dentro del recurso `gmu`
  (0x3d68000+0x37000). **Ventana correcta.**
- `qcom,qmp = <&aoss_qmp>` lo añade s271 (fragment@1712) ⇒ `a6xx_gmu_acd_probe()` (2546-2614) corre
  y hace `qmp_send(... acd, 0)` (2607) — limpia el ACD heredado de Android (el OPP table UKE no lleva
  `qcom,opp-acd-level` ⇒ `enable_by_level=0` ⇒ envía OFF sin fallo). **OK/DESPISTADO** (no es el
  bloqueo actual).

### 1.2 SMMU/camino de los BOs (el nudo)

- `of_dma_configure(gmu->dev, node, true)` — **a6xx_gmu.c:2861** — dispara
  `__iommu_probe_device()` → **`iommu_setup_default_domain(group,0)`** (iommu.c:678) ⇒ el grupo del
  SID5 se queda con un **dominio default (DMA, paginas vacías) ATTACHADO** ⇒ arm-smmu programa
  SMR(5)/S2CR(5)→**CB1** (la asignación de CB para no-GPU empieza en 1:
  `arm-smmu-qcom.c:332-351`; el GPU (SID0, `QCOM_ADRENO_SMMU_GPU_SID`, arm-smmu-qcom.c:222) se lleva
  CB0). Esto cuadra EXACTO con el volcado k55: `SME(0) TRANS→CB0`, `SME(1) TRANS→CB1`
  (ledger #536) — **no es "igual que vendor" por configuración nuestra: CB1 es el dominio default del GMU, vacío**.
- `a6xx_gmu_memory_probe()` (2123-2142): con `uke_gmu_shared=1` (default, :2113) el vm del GMU
  **comparte el mmu del GPU** ⇒ `icache@0x4000`, `dummy@0x60000000`, `debug@0x60400000`,
  `log@0x60004000`, `hfi@0x60008000` (allocs en 2889-2949; rango no-fijo 0x60000000+4K..0x80000000
  en 2062-2065) se mapean con `msm_gem_get_and_pin_iova_range` (2078) en el **dominio del GPU (CB0)**.
- El CM3 fetch-ea: vector desde **ITCM** (sin SMMU, OK) y TODO lo demás (código @0x4000+, DTCM/BOs)
  por **SID5 → CB1 (vacío)** ⇒ **fallo de traducción garantizado en el primer fetch fuera de ITCM**.
  El CM3 no escribe FW_INIT_RESULT ni DTCM; el poll (ya mal-branched) expira; en ~la mitad de los
  boots la tormenta de faults/wedges el AHB del GMU y la máquina muere (k53/k54/k57), en el resto
  falla con gracia (k55).

---

## 2. EXTERNAL ABORT 0x96000010 — decodificación exacta

`ESR_EL1 = 0x96000010` (uke-k20-boot.log:14173; mismo código en uke-console2.log y k56):

| Campo | Valor | Significado |
|---|---|---|
| EC [31:26] | 0b100101 (0x25) | **Data Abort from a lower Exception level** (normal en arm64: abort de datos tomado en EL1) |
| IL [25] | 1 | longitud de síndrome 32-bit |
| ISV [24] | 0 | sin síndrome de instrucción (no es SAS/SRT decodeable) |
| SAS/LSE/SRT/SF/AR/CM | 0 | acceso de **32 bits** |
| **WnR [6]** | **0** | **LECTURA** |
| S1PTW [7] | 0 | no es fallo de walk stage-1 |
| FnV [10] | 0 | la FAULTing address es válida (no es "fault not valid") |
| EA [8] | 0 | (clasificación EA no marcada) |
| **DFSC [5:0]** | **0b010000 = 0x10 (16)** | **Synchronous External abort** (no es fallo de traducción ni de permisos; sin nivel) |

**Interpretación**: la lectura MMIO (el `readl` de `uke_k19_dump_kgsl` a `0x3da0000+0x20000`, ventana
CB del MMU-500) llegó al esclavo del NoC y éste devolvió **error (SLVERR/DECERR)**: el objetivo no
tenía reloj/alimentación (o la ventana no responde en ese estado). NO es un problema de traducción
del acceso CPU (los accesos CPU a MMIO no pasan por la SMMU) y no es "basura": **el bus rechaza**.

**¿Por qué la SMMU private no responde?**
- El nodo `kgsl_smmu` (m270.dts:16337) NO tiene `power-domains`; tiene 4 clocks:
  `gpu_cc_hlos1_vote_gpu_smmu (id 0x11)`, `gcc_gpu_memnoc_gfx (0x20)`, `gcc_gpu_snoc_dvm_gfx (0x21)`,
  `gpu_cc_ahb (0x02)`. **DISCREPANCIA DETECTADA**: con nuestro header
  `qcom,palawan-gpucc.h` (HLOS1_VOTE=**15/0xf**, AHB=**0**), el id **0x11** es **GPU_CC_HUB_CLK_SRC(17)**
  y el id **0x02** es **GPU_CC_CRC_AHB_CLK(2)** ⇒ `arm-smmu` habilita (por orden del DT,
  `devm_clk_bulk_get_all`) **HUB_CLK_SRC y CRC_AHB en lugar de HLOS1_VOTE_GPU_SMMU y AHB**.
  El vendor gestiona esas gates por nombre (clk-summary vendor: `gpu_cc_hlos1_vote_gpu_smmu_clk`
  consumer = `3da0000.kgsl-smmu`, enable count 0 en idle ⇒ el vendor la APAGA en idle: **leyendo la
  SMMU con GPU dormida, aunque sea en el vendor, no está garantizado**). Esto explica el
  **basura/abort boot-a-boot** en la ventana CB (k54 basura, k55 basura+globals coherentes, k56 abort)
  y NO debe usarse como discriminador. (Caveat: el probe de arm-smmu a t=0.32s leyó IDs OK
  (k24-boot110-console.log:74-79), así que la interfaz global vivió sin esas gates explícitas — el
  mapeo exacto de gates por id queda por medir; la discrepancia de ids es un hallazgo sólido, su
  consecuencia exacta no.)
- El estado del dump (k56) era MEDIO-resume: clocks del GMU ya puestas, CX arriba, pero el resto de la
  isla (TCU/TBU) en estado variable. **El instrumento mata el probe antes de S3** (k56: "el abort mató
  el probe del GMU antes de soltar el reset", #539) ⇒ k56 no aporta NADA sobre el CM3.

---

## 3. EL BINARIO `gen71100_gmu.bin` (byte-level)

Fuente: `build/pkg/uke-gpu-firmware/gen71100_gmu.bin` (80.680 bytes; md5 `a02e73fe916137b2c974951c314fac2d`;
**idéntico** al del initramfs uke-k34 `lib/firmware/qcom/gen71100_gmu.bin` y al del paquete instalado —
comparado por md5). Es el mismo nombre/fichero que carga el vendor (`/vendor/firmware/gen71100_gmu.bin`,
dmesg-gpu.txt:126-136, driver `adreno-gen7-gmu 3d68000.qcom,gmu`).

### 3.1 Formato: GMU Binary Layout con TOC + segmentos (NO es sqe-legacy)

Cabecera de bloque (mainline `a6xx_gmu.c:1309-1315`): `{u32 addr; u32 size; u32 type; u32 value; data[]}`.
El fichero tiene una **TOC de 11 registros con size=0** (que el driver SALTA: `if (blk->size == 0) continue;`,
línea 1364) y luego **4 bloques reales** (marker `0xefbeadde` = DEADBEEF LE):

| file-off | addr | size | destino en el driver |
|---|---|---|---|
| 0x000b0 | 0x00000000 | 0x1dc | **ITCM** (+0x0): vector ARMv7-M: `[0]=0x10007f80 (MSP)`, `[1]=0x00000105 (reset, Thumb)` = **exactamente las palabras "esperadas" del K44 B** |
| 0x00029c | 0x00004000 | 0x1381c | **BO icache** (0x4000..0x1000000, 16M-16K) |
| 0x013ac8 | 0x10007f98 | 0x28 | **DTCM** (base 0x10004000 para a7xx, :1341-1344) |
| 0x013b00 | 0x10007fdc | 0x18 | **DTCM** cola |

`NEXT_BLK` recorre exactamente esos 4 y termina en EOF (0x13b28) — **el parser de nuestro árbol
consume el contenedor CORRECTAMENTE** (verificado programáticamente). Los pokes del log
`F2-itcm, F2-dtcm, F2-dtcm` (uke-console2.log boot @4.15s) confirman el recorrido en vivo.
El vendor usa el MISMO contenedor (su loader gen7 lo parsea) ⇒ **el formato NO es el problema**.

### 3.2 LA PALABRA MALIGNA: 0x40050001 pre-cargada

El bloque de cola (file-off 0x13b00) escribe en DTCM:

```
DTCM 0x10007fdc (+0xff7): ffffffff
DTCM 0x10007fe0 (+0xff8): 40050001   <<<< EXACTAMENTE lo que lee a6xx_gmu_start() en S0 (línea 663)
DTCM 0x10007fe4 (+0xff9): ffffffff
DTCM 0x10007fe8 (+0xffa): 40000024
DTCM 0x10007fec (+0xffb): 00000000
DTCM 0x10007ff0 (+0xffc): 20060001
```

Consecuencias encadenadas:
1. El discriminador "dtcm-magic" (STALE/OK) **mide el contenido de la imagen**, no la ejecución:
   **SIEMPRE STALE**. Todas las conclusiones "el fw NO llegó a la RAM del CM3" (#536, #539) basadas en
   este veredicto **quedan invalidadas**. (La autocorrección del comentario en a6xx_gmu.c:677-694 ya
   sospechaba que el OK/STALE era frágil; lo que nadie vio es que el valor NI SIQUIERA es runtime.)
2. `0x40050001 > 0x20010004` ⇒ rama **WARM** del poll (`mask=0x1ff/reset_val=0x100`, :668-671).
   En un cold boot real el fw escribe `FW_INIT_RESULT=0xbabeface` (rama COLD: `mask=0xffffffff`,
   `reset_val=0xbabeface`) ⇒ `(0xbabeface & 0x1ff)=0xce != 0x100` ⇒ **S4-pollFAIL aunque el CM3
   ejecute perfecto**; el error path re-assertea SYSRESET (:774-777) y mata un fw sano.
   Nota upstream: en los binarios mainline (a6xx/a7xx de linux-firmware) la cola DTCM no pre-carga un
   valor >umbral en +0xff8 — este gen71100 viene del vendor kgsl, que usa su propia detección de boot,
   no la heurística de mainline. **El choque heurística-vs-binario es nuestro.**

### 3.3 ¿Qué hay en 0x60000000?

Nada físico del DT: **0x60000000 es la IOVA del BO "dummy"** en el vm del GMU (alloc fija en
a6xx_gmu.c:2902-2903; rango no-fijo 0x60001000..0x80000000 en :2064). El propio binario referencia
0x60000000/0x60001000 (TOC type=7, 2×0x1000) — por eso mainline clava el dummy ahí. El fw-map real del
boot (k55/k56): `icache iova=0x4000 (3ff0 KiB) dummy=0x60000000 debug=0x60400000 hfi=0x60008000
log=0x60004000` (uke-sesion-console.log:114894). Todos viven (hoy) en el dominio del GPU (CB0).

---

## 4. RANKING DE HIPÓTESIS DEL "DTCM STALE / CM3 no ejecuta"

| # | Hipótesis | Veredicto | Evidencia |
|---|---|---|---|
| 1 | **Fetch del CM3 por SID5→CB1 (dominio default VACÍO)** | **CONFIRMADA por código+logs** | iommu.c:678 (default domain attach en of_dma_configure), iommu.c:2360 (cuándo hay -EBUSY), arm-smmu-qcom.c:332-351 (CB0=GPU SID0, resto desde CB1), a6xx_gmu.c:2113+2128 (compartir mmu del GPU), s271chk.dts fragment@1450 (GPU=SID0, ya no s263), volcado k55 SME(0)→CB0/SME(1)→CB1 |
| 2 | **Poll mal-branched (WARM en COLD) por magic pre-cargado** | **CONFIRMADA byte-level** | binario §3.2; a6xx_gmu.c:663-671 y 770-777; dtcmR val=0x40050001 en TODOS los boots |
| 3 | Reloj del CM3 off (cx_gmu/hub) | DESCARTADA como causa única | clocks bulk OK (H3), rates correctos (k56 hub=200M), MMIO del GMU vivo, ITCM read-back OK (K44 B) |
| 4 | GDSC CX/GX off | DESCARTADA | GMU MMIO responde ⇒ CX on; GX es no-gobernable igual que vendor (#535) y el CM3 vive en CX |
| 5 | Reset no se suelta (write buffer / power collapse) | POCO PROBABLE | SYSRESET=1×2 + wmb (:696-711); el freeze POST-S3 (k53/k54/k57) implica que el CM3 SÍ salió y tocó algo |
| 6 | ITCM escrito en dirección equivocada | DESCARTADA | mapa de registros correcto (xml :45-67, ventana gmu 0x37000), read-back K44 B = binario |
| 7 | fw.bin equivocado (gen70900 vs gen71100) | DESCARTADA | md5 idéntico en paquete/initramfs; chipid DT 0x43030b00 → catálogo gen71100 (a6xx_catalog.c:1618-1652) |
| 8 | ACD/IFPC heredado | DESPISTADO (no medible offline) | s271 añade qmp y envía ACD OFF; no es el bloqueo actual (ni llega a ejecutarse el fw) |
| 9 | El parse del contenedor (sospechoso #1 original) | **REFUTADA** | §3.1: recorrido exacto, EOF limpio, destinos correctos |

**Reinterpretación del fenómeno "a veces congela, a veces falla con gracia"**: con CB1 vacío, el CM3
hace fetch fuera de ITCM → fault en el TCU. Si el fault queda contenido (respuesta de error al CM3,
éste se para), el driver sólo ve poll-FAIL (k55, k56-hasta-abort). Si la racha de faults satura el
AHB/NoC del island, el siguiente acceso CPU al GMU cuelga → hung_task/RCU-stall → panic →
**reboot automático (cmdline `panic=10 hung_task_panic=1`) que en consola parece "congelación"**
(verificado: uke-sesion-console.log:114894-114900 — tras S3-rst0 el siguiente bloque es el banner de
un kernel nuevo). La carrera k53/k54 vs k55 es timing de quién llega antes: instrumentos con
pr_flush (k55) vs secos (k53/k54/k57).

---

## 5. COMPARACIÓN CON EL VENDOR (secuencia)

| Aspecto | Vendor Android | Nuestro port |
|---|---|---|
| Driver GMU | `adreno-gen7-gmu 3d68000.qcom,gmu` (dmesg-gpu.txt:126) | mainline msm a6xx_gmu |
| Fw GMU | mismo `gen71100_gmu.bin` (contenedor de segmentos), lazy a los 6s; probe 150ms sin fw | mismo binario, request_firmware en probe, fw_load en COLD |
| SMMU del GPU | **`qcom,kgsl-smmu-v2` (driver vendor propio)** en 0x3da0000 (DT: kgsl_msm_iommu :21842); GMU→CB1 TRANS con **sus** tablas; clocks `hlos1_vote` gestionados por su driver (clk-summary) | **arm-smmu MMU-500 mainline** (k24-boot110-console.log:74-79); SID5→CB1 = dominio default VACÍO |
| GPU SID | gfx3d_user SID0 (su driver) | GPU SID0 (fragment@1450) — correcto |
| ACD | ACD=1/IFPC=1 vía AOP | s271: qmp_send ACD OFF (sin opp-acd-level) |
| GX | no gobernable desde CPU | igual (gxpd refcount) |
| PDC/RSC | AOP (pdc_in_aop) | igual (reg gmu_pdc=0xb280000) |

El vendor **no hace nada que nosotros no podamos hacer**: su ventaja es que SU driver del SMMU
programa CB1 para el GMU con mapeos reales. Nuestro equivalente (dominio propio del GMU, mainline)
está DESACTIVADO por `uke_gmu_shared=1` desde la era s263.

---

## 6. LOS 3 PASOS SIGUIENTES (ordenados por probabilidad de curar)

### PASO 1 — k58: restablecer el dominio propio del GMU + arreglar el poll (2 parches, un solo boot de validación)

**Parche A (SMMU, el importante)** — `a6xx_gmu.c:2113`:
```c
- static int uke_gmu_shared = 1;
+ static int uke_gmu_shared = 0;   /* s269+ tienen GPU=SID0: la premisa s263 del hack K20 ya no existe */
```
Con 0, `a6xx_gmu_memory_probe()` (2123-2142) llama `msm_iommu_new(gmu->dev, 0)` (2132) →
`iommu_paging_domain_alloc` + `iommu_attach_device` → **reemplaza el dominio default del grupo SID5**
(iommu.c:2360 permite reemplazar el default; el -EBUSY de la era K20 exigía un dominio NO-default
vivo, que solo existía con el GPU en el mismo grupo s263) → arm-smmu le da CB1 (start=1,
arm-smmu-qcom.c:346) con **nuestras** tablas (icache@0x4000 dentro) y `is_gpu_device`=false ⇒ sin
quirk TTBR1, correcto para un vm 32-bit. Extra: el fault handler UKE-K39 (msm_iommu.c:767) queda
instalado en el dominio del GMU ⇒ **un fault del fetch imprimirá `*** fault: iova=...`** (pr_warn,
visible a loglevel 4+).

**Parche B (poll)** — `a6xx_gmu.c:655` recibe el `status` ya computado en resume (1859-1871) y
elimina la heurística envenenada:
```c
- static int a6xx_gmu_start(struct a6xx_gmu *gmu)
+ static int a6xx_gmu_start(struct a6xx_gmu *gmu, unsigned int boot_state)
  ...
-	val = gmu_read(gmu, REG_A6XX_GMU_CM3_DTCM_START + 0xff8);
-	if (val <= 0x20010004) { mask = 0xffffffff; reset_val = 0xbabeface; }
-	else                   { mask = 0x1ff;        reset_val = 0x100; }
+	if (boot_state == GMU_COLD_BOOT) { mask = 0xffffffff; reset_val = 0xbabeface; }
+	else                             { mask = 0x1ff;      reset_val = 0x100; }
+	/* informativo: +0xff8 contiene 0x40050001 PRE-CARGADO por fw_load (inv #540 §3.2) */
```
(llamada en :1536 pasa el `state` que ya recibe `a6xx_gmu_fw_start`).

**Boot de validación (UNO solo decide)**: k58 + s271 + v8.1, cmdline
`msm.uke_gmu_shared=0 msm.uke_smmu_dump=0 loglevel=7` + los params arm_smmu ya presentes
(`uke_attach_log=2` dará la miga del attach del GMU: SME idx/CB). Qué leer en dmesg:
1. `UKE-K13: msm_iommu_new: iommu_attach_device rc=0` para `3d68000.qcom,gmu` (attach OK),
   `UKE-K32: init_context dev=3d68000.qcom,gmu ... cbndx=1 ttbr1=0`.
2. **S4-pollOK** ⇒ el CM3 ejecuta; caso cerrado. (Si falla, ya NO es el poll: ver 3.)
3. Si hay fault: `*** fault: iova=0x...` o `arm-smmu 3da0000.kgsl-smmu: Unhandled context fault... cb=1 iova=0x...`
   ⇒ el iova impreso dice QUÉ acceso murió primero (0x4000 = fetch del icache = mapeo; otra cosa =
   siguiente capa).

### PASO 2 — si S4 sigue fallando con attach rc=0: verificar que CB1 quedó programado y la isla viva

Sin volcados crudos (regla del abort): añadir poke post-attach en arm-smmu (path attach) que imprima
para el maestro SID5: `S2CR(sme)` y `CB_SCTLR(cbndx)`/`CB_TTBR0(cbndx)` **después** de
`arm_smmu_write_sme/context` (mismas lecturas que ya hace el driver, no crudas desde el GMU) +
`clk_get_rate/enable_count` de los 4 clocks del kgsl-smmu. Validará (a) SID5→CB1 TRANS,
(b) CB1.SCTLR.M=1 con TTBR0 nuestro, (c) gates de la SMMU vivas. Si CB1 está bien pero el CM3 no
arranca, las sospechas pasan a (c) gates (discrepancia de ids hlos1/ahb, §2) y se prueba el fix del
DT: en `kgsl-smmu` cambiar los ids a los correctos de `qcom,palawan-gpucc.h`
(`hlos1_vote=0xf`, `ahb=0x0`) — dtbo-only.

### PASO 3 — si CB1/attach/gates OK y el CM3 aún no escribe FW_INIT: capa "fw real"

Comparar lo que el vendor escribe ANTES de soltar el reset que nosotros no: (a) `GMU_CM3_BOOT_CONFIG`
(el vendor kgsl puede usar otro valor que 0x02 para gen7.2 — capturable del snapshot vendor si
aparece en los debugfs ya extraídos); (b) el estado IFPC/ACD heredado: probar módulo
`disable_acd=true` y, en paralelo, revisar `REG_A6XX_GMU_AO_HOST_INTERRUPT_STATUS` tras S3 (un
`HOST_AHB_BUS_ERROR` ahí = el fetch murió por bus, no por traducción). Nada de esto requiere tablet
nueva: es el MISMO boot del PASO 1 si los prints se incluyen desde el principio.

**Regla de oro para k58**: ningún `readl` a la kgsl-smmu fuera del driver arm-smmu (lección k56);
todos los discriminadores nuevos por prints que ya existen (K13/K32/K39/attach_log) o por registros
del PROPIO GMU (FW_INIT_RESULT, AO_HOST_INTERRUPT_STATUS).

---

## 7. EVIDENCIA CITADA (rutas)

- Código: `build/kernel-pokes/k52-tree/drivers/gpu/drm/msm/adreno/{a6xx_gmu.c,a6xx_gpu.c,a6xx_gmu.h,a6xx_catalog.c}`,
  `.../msm/msm_iommu.c`, `drivers/iommu/iommu.c`, `drivers/iommu/arm/arm-smmu/{arm-smmu.c,arm-smmu-qcom.c}`,
  `drivers/clk/qcom/gpucc-palawan.c`, `include/dt-bindings/clock/qcom,palawan-gpucc.h`,
  `drivers/gpu/drm/msm/registers/adreno/a6xx_gmu.xml`.
- DT: `/var/tmp/uke-s270/m270.dts` (:14695 gpu, :16337 kgsl_smmu, :21842 kgsl_msm_iommu vendor, :21863 gmu),
  `/var/tmp/uke-s271/s271chk.dts` (fragment@1450 GPU SID0, fragment@1712 qmp).
- Binario: `build/pkg/uke-gpu-firmware/gen71100_gmu.bin` (md5 a02e73fe…) = initramfs k34 (md5 igual).
- Logs: `build/evidencia/k24-boot110-console.log` (arm-smmu probe nuestro),
  `/var/tmp/uke-k20-boot.log` (abort + secuencia F/P), `/var/tmp/uke-console2.log` (freeze post-S2,
  boots con F2-itcm/F2-dtcm×2), `/var/tmp/uke-sesion-console.log:114860-114960` (boot completo:
  fw-map, dtcmR 0x40050001, S3-rst0 → reboot por panic).
- Vendor: `build/evidencia/android-full/extracted-full/01-gpu/dmesg-gpu.txt` (:110-147 carga sqe/gmu/zap),
  `.../01-gpu/clk-summary.txt` (hlos1_vote ↔ 3da0000.kgsl-smmu),
  `.../15-common/regulator_summary.txt` (:31).
- Ledger: #535, #536, #538, #539, #539b (`~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`).

## 8. LÍMITES DE ESTE ANÁLISIS

- No hay volcado del resultado del boot k57 (seco): el "k57 congela" se infiere de la tablet wedged,
  no de un log. El boot del PASO 1 es el que decide.
- La discrepancia de clock-ids del nodo kgsl-smmu (§2) es un hallazgo sólido del DT vs nuestro header;
  su consecuencia exacta (qué gate deja la ventana CB muerta) necesita la medición del PASO 2.
- `BOOT_CONFIG=0x02` y la semántica exacta de FW_INIT del fw gen71100 se asumen upstream (no hay
  fuentes kgsl vendor en disco, #535).
