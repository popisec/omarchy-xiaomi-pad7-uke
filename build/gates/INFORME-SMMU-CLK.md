# INFORME SMMU-CLK — la hipótesis *clocks/power apagados* para el bind de `apps-smmu@15000000`

**28-sep-2026 · proyecto omarchy-uke · SG-SMMU-CLK · 100 % offline** (nada tocado en la tablet, nada
compilado, `~/gpu-work/palawan-linux` solo lectura; en `omarchy-uke` solo se crea este fichero).

Convención: **[DATO]** = fichero:línea o comando + salida. **[INFERENCIA]** = deducción encadenada
sobre datos. **[NO VERIFICADO]** = no medido y no medible sin la tablet.

---

## 0. Titulares (el veredicto de la hipótesis, en 6 líneas)

1. **La hipótesis clocks/power NO cuadra** — y no cuadra por dos caminos independientes:
   - **El driver no pide relojes por compatible**: en este árbol NINGÚN dato de match lleva `clks`;
     los relojes son solo los del nodo (`devm_clk_bulk_get_all`, `arm-smmu.c:2229`) y se encienden
     en `arm-smmu.c:2236`, **antes** del primer MMIO (`:2241`). Con un nodo sin `clocks`, `num_clks=0`
     y las llamadas son no-ops.
   - **El control Android existe y es verde**: el nodo vendor del aparato **no tiene clocks** (en los
     dos msm-id, byte-idéntico) y el kernel stock — **el mismo código de clk** — bindea apps-smmu a los
     0,54 s y el sistema arranca Android completo. Y eso ocurre **después** de
     `clk: Disabling unused clocks` (0,144 s): el estado del *clk framework* en el momento del probe es
     el mismo en Android y en mainline.
2. **No hay fragmento DT posible para esta hipótesis**: no existe ni un clock ni un power-domain de
   apps-smmu en el hardware vendor (0 apariciones de "smmu" en el GCC vendor y en el del fork), así que
   un `clocks = <…>` en el nodo sería **inventar** un reloj. Por eso **no se entrega
   `FRAGMENTO-SMMU-CLK.dts`**: la vía honesta es kernel. (El método label→phandle que pedía el encargo
   queda verificado igualmente, Anexo A.)
3. **Bonus con consecuencias para el próximo ciclo**: la hipótesis H1 del informe A′ (ventana de `reg`)
   queda **refutada por el mismo control Android** (Android bindea con `reg[0] = 1 MiB`, misma math de
   CB). Y el dtbo A′ (`s253`, `reg = <0x15000000 0x200000>`) **no cumple la condición de diferir del
   kernel de pokes** (`arm-smmu.c:2158` exige `size == 0x100000`): si se flashea pokes+A′ tal cual, el
   probe corre en device_initcall y vuelve el wedge mudo. Eso hay que arreglarlo en el mismo build.
4. **Lo que sí queda como causa viva**: los accesos MMIO que mainline hace sobre apps-smmu **y que
   ningún driver funcional de este aparato ha validado nunca** — en primer lugar
   `qcom_smmu_cfg_probe` (la escritura del S2CR del último grupo; `arm-smmu-qcom.c:497`) y, en segundo,
   `arm_mmu500_reset` a 71 CBs (`arm-smmu-impl.c:118-143`). El inventario completo y el instrumento
   que discrimina cada uno es §5.
5. **El vehículo del próximo intento es el kernel**: el diff mínimo propuesto va en §4 (aceptar
   `qcom,qsmmu-v500` nativamente + diferir con **token de arming** + migas dentro de `qcom_smmu_cfg_probe`
   y por fases del reset). Sin compilar, como pedía el encargo.
6. **Riesgo operativo que hay que cerrar ANTES**: el kernel de pokes **nunca ha demostrado arrancar**
   (4 mudos, ver §6.0). El diseño incluye un *gate 0* que lo prueba con la SMMU desarmada (token off)
   y convierte cualquier mute en información, en vez de ser un quinto intento ciego.

---

## 1. El nodo vendor, extraído y comparado

### 1.1 Reproducción de la extracción [DATO]

```bash
$ file ~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img
base-dtb.img: Device Tree Blob version 17, size=475426
$ sha256sum ~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img
3f973c78f7dc6a66f1acea363be27774c51ff174fbf71117ebe74c385547562e   ← el sha del encargo
$ dtc -I dtb -O dts -o /tmp/smmuclk/base-dtb.dts ~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img
$ fdtget ~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img / qcom,msm-id
614 65536                        ← 0x266 0x10000 ("cliffs")
$ fdtget ~/gpu-work/stock-dtbs/stock-fdt2.dtb / qcom,msm-id
643 65536                        ← 0x283 0x10000 ("cliffsp" = este aparato)
```

**[DATO]** verificación pedida — el nodo es **idéntico** en los dos FDT: comparando el subárbol
completo (`kgsl-smmu@3da0000` y `apps-smmu@15000000`, con sus hijos) entre `base-dtb.dts` (0x266) y
`stock-fdt2.dts` (0x283) por igualdad de texto: **IGUALES** los dos (script de comparación, salida
`IGUALES EN 0x266 y 0x283`). Las diferencias entre ambos FDT están en otra parte, no en los SMMU.

### 1.2 `apps-smmu@15000000` completo (líneas 13180-13222 del decompilado; la lista de IRQs omitida)

```dts
apps_smmu: apps-smmu@15000000 {
    compatible = "qcom,qsmmu-v500";
    reg = <0x15000000 0x100000 0x151fe000 0x40>;
    reg-names = "base", "tcu-base";
    #iommu-cells = <0x02>;
    qcom,use-3-lvl-tables;
    qcom,handoff-smrs = <0x1c00 0x02>;      ← el kgsl NO lo tiene
    #global-interrupts = <0x01>;
    #size-cells = <0x01>; #address-cells = <0x01>; ranges;
    dma-coherent;
    status = "ok";
    interrupts = <…>;                        ← 291 celdas = 97 IRQs (1 global + 96 de contexto)
    qcom,actlr = <…>;                        ← 31 tripletas (sid, mask, actlr)
    phandle = <0x129>;
    /* 8 hijos qcom,qsmmuv500-tbu / qcom,qtb500: anoc_1_qtb@16f1000, anoc_2_qtb@171a000,
       cam_hf_qtb@14d2000, nsp_qtb@7d3000, lpass_qtb@7b3000, pcie_qtb@16cd000, sf_qtb@1451000,
       mdp_hf_qtb@14d0000 (cada uno con qcom,stream-id-range / iova-width / interconnects) */
};
```

**[DATO]** y la lista literal de propiedades, que es la respuesta directa a «¿tiene clocks?»:

```bash
$ fdtget -p ~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img /soc/apps-smmu@15000000
compatible reg reg-names #iommu-cells qcom,use-3-lvl-tables qcom,handoff-smrs
#global-interrupts #size-cells #address-cells ranges dma-coherent status
interrupts qcom,actlr phandle
```

**NO hay `clocks`, ni `clock-names`, ni `power-domains`, ni `vdd-supply`, ni `assigned-clocks`.** Igual
en los cuatro `stock-fdt*.dtb` y en todos los dumps vendor del disco (comprobado con script sobre
`ramaa/s1/part2.dts`, `.critica-tmp/uke-vendor.dts`, `ramaa/s21/dtbo-gpu/merged-gpu.dts`: `clocks no`).

### 1.3 `kgsl-smmu@3da0000` (el que SÍ funciona) — el delta exacto [DATO]

```bash
$ fdtget -p … /soc/kgsl-smmu@3da0000
compatible reg reg-names #iommu-cells qcom,use-3-lvl-tables #global-interrupts #size-cells
#address-cells ranges dma-coherent status qcom,regulator-names vdd-supply clocks clock-names
qcom,actlr interrupts phandle
```

```dts
kgsl_smmu: kgsl-smmu@3da0000 {
    compatible = "qcom,qsmmu-v500", "qcom,adreno-smmu";   ← el 2º compatible selecciona impl adreno
    reg = <0x3da0000 0x40000 0x3de6000 0x40>; reg-names = "base", "tcu-base";
    qcom,use-3-lvl-tables; #iommu-cells = <0x02>; #global-interrupts = <0x01>;
    qcom,regulator-names = "vdd"; vdd-supply = <0x1bd>;
    clocks = <0x175 0x11 0x16e 0x20 0x16e 0x21 0x175 0x02>;
    clock-names = "gpu_cc_hlos1_vote_gpu_smmu", "gcc_gpu_memnoc_gfx",
                  "gcc_gpu_snoc_dvm_gfx", "gpu_cc_ahb";
    qcom,actlr = <0x00 0x3ff 0x32b>;
    interrupts = <…>; phandle = <0x1c1>;
    / { gpu_qtb@3de8000 { compatible = "qcom,qsmmuv500-tbu", "qcom,qtb500"; … }; };
};
```

Tabla del delta (lo único que tiene kgsl y apps no, y viceversa):

| propiedad | apps-smmu | kgsl-smmu | ¿lector en mainline? |
|---|---|---|---|
| `clocks` + `clock-names` | **NO** | 4 (2× GPUCC, 2× GCC) | sí: `arm-smmu.c:2229/2236` (si existen) |
| `vdd-supply` + `qcom,regulator-names` | **NO** | `vdd`→`gpucc`/regulador GPU | no (0 lectores de `regulator-names`; el supply lo pide el regulador si el driver lo busca — arm-smmu **no**) |
| `power-domains` | NO | NO (en el vendor) | — |
| compatible que selecciona otra rama del driver | no | `qcom,adreno-smmu` → **impl adreno** | sí: `arm-smmu-qcom.c:707` |
| `qcom,handoff-smrs` | `<0x1c00 0x02>` | no | **no** (0 lectores, en mainline y en vendor) |
| grupos/CBs | 110 / 71 | 24 / 22 | — |
| forma del resto (`reg` 2 regiones, `tcu-base`, hijos TBU, `ranges`, `actlr`) | igual | igual | refrigerado ya por el control del s238 |

Las dos conclusiones que importan:

- **[DATO→INFERENCIA] El kgsl no "tiene relojes porque mainline los pida"**: los pide *el DT*, y los
  tiene porque el bloque está detrás de compuertas de GPUCC (`gpu_cc_*`) que hay que abrir en el
  dominio GPU. No hay ninguna señal equivalente para apps-smmu: **no existe un reloj "smmu" en el GCC
  de este SoC** (§1.4). No es que falte la declaración: **falta el reloj**.
- **[DATO] El kgsl nunca ejecuta `qcom_smmu_cfg_probe`**: con `qcom,adreno-smmu` el impl elegido es
  `qcom_adreno_smmu_500_impl` (`arm-smmu-qcom.c:687-695`), que declara `init_context`,
  `def_domain_type`, `reset = arm_mmu500_reset`, `alloc_context_bank`, `write_sctlr`, `tlb_sync`,
  `context_fault`… **y ningún `.cfg_probe`**. Es decir: **la escritura del S2CR del último grupo
  (`arm-smmu-qcom.c:497`) jamás se ha ejecutado con éxito en este aparato**, en ninguna instancia.
  Ese es el candidato nº1 de §5.

### 1.4 ¿Existe algún reloj/power para apps-smmu en el hardware? [DATO]

```bash
$ grep -in "smmu" ~/kws/common/include/dt-bindings/clock/qcom,gcc-cliffs.h      → 0 líneas
$ grep -in "smmu" ~/kws/common/drivers/clk/qcom/gcc-cliffs.c                   → 0 líneas
$ grep -in "smmu" ~/gpu-work/palawan-linux/include/dt-bindings/clock/qcom,palawan-gcc.h → 0
$ grep -in "smmu" ~/gpu-work/palawan-linux/drivers/clk/qcom/gcc-palawan.c      → 0
$ grep -in "tbu"  … (los mismos cuatro ficheros)                               → 0
```

**[DATO] No hay ninguna línea de reloj (`gcc_*_smmu_*`, `*_tbu_*`, GDSC `apps_smmu`) en el GCC vendor
ni en el del fork.** Las GDSCs del GCC de cliffs que el fork porta son pcie/ufs/usb (`gcc-palawan.c:
2566-2612`), ninguna de SMMU. **[INFERENCIA]** el apps-smmu cuelga de un dominio siempre-encendido
(no computable por software desde el DT ni desde los drivers de clk del arranque), que es exactamente
lo que hace que el nodo vendor no necesite `clocks` y que Android funcione sin ellos.

> Nota: el `qcom,gdsc@150018` del DT vendor (que en el dmesg de Android aparece como
> `Fixed dependency cycle(s)`) es `gcc_usb3_phy_gdsc` (`base-dtb.dts:13692-13703`), o sea el **GDSC del
> PHY USB3**, física pero no funcionalmente vecino del SMMU (0x150018 cae dentro de la ventana de 2 MiB
> de A′). No es una power-domain del SMMU y mainline no tiene driver para ese compatible (`qcom,gdsc`
> no está en ningún `of_device_id` del árbol), así que ni alimenta ni estorba al probe.

---

## 2. El driver: ¿qué compatible pide relojes y con qué nombres?

### 2.1 Respuesta directa

**Ninguno. En este árbol ningún `compatible` qcom lleva datos de clock.** No existen `clk_names`,
`num_clks` ni nada equivalente en los datos de match:

**[DATO]** `arm-smmu-qcom.h:37-42`:

```c
struct qcom_smmu_match_data {
	const struct qcom_smmu_config *cfg;
	const struct arm_smmu_impl *impl;
	const struct arm_smmu_impl *adreno_impl;
	const struct of_device_id * const client_match;
};
```

**[DATO]** `grep -c clk arm-smmu-qcom.c` = **0**. La tabla
`qcom_smmu_impl_of_match` (`arm-smmu-qcom.c:775-802`, 26 entradas, de `msm8996-smmu-v2` a
`qcom,smmu-500`) solo lleva punteros a `qcom_smmu_match_data`; `sdm845_smmu_500_data` (`:755-762`),
`qcom_smmu_500_impl0_data` (`:764-769`)… ninguno tiene relojes. Es decir: **no hay "el compatible con
clk data" que elegir**; el encargo lo presuponía y no existe en 7.2-rc2.

### 2.2 Cómo y cuándo se encienden los relojes (orden respecto al primer MMIO)

**[DATO]** `arm-smmu.c` (líneas del árbol de trabajo actual, con los pokes ya aplicados):

```c
2192:	smmu->base = devm_platform_get_and_ioremap_resource(pdev, 0, &res);  /* solo ioremap */
2201:	smmu->numpage = resource_size(res);                                  /* tamaño, no MMIO */
2203:	smmu = arm_smmu_impl_init(smmu);                                     /* impl qcom, sin MMIO */
2229:	err = devm_clk_bulk_get_all(dev, &smmu->clks);   /* ← los clocks del DT; 0 si no hay */
2234:	smmu->num_clks = err;
2236:	err = clk_bulk_prepare_enable(smmu->num_clks, smmu->clks);
2240:	pr_info("UKE-POKE: … -> arm_smmu_device_cfg_probe …");
2241:	err = arm_smmu_device_cfg_probe(smmu);            /* ← PRIMER MMIO (IDR0 en :1754) */
…
2282:	arm_smmu_device_reset(smmu);                      /* ← reset (incluye el impl->reset) */
2283:	arm_smmu_test_smr_masks(smmu);
```

Conclusión de orden: **si el nodo tuviera `clocks`, el driver los encendería ANTES del primer acceso
MMIO**. Como no los tiene, `clk_bulk_prepare_enable(0, NULL)` no hace nada y el primer acceso ocurre
sin ningún reloj "encendido por el driver". Eso **no es un defecto del driver**: es el contrato del
bloque en este SoC (y en sm8550, §2.3).

### 2.3 La referencia mainline de la misma estirpe [DATO]

```dts
/* arch/arm64/boot/dts/qcom/sm8550.dtsi:5545-5548 (upstream en este fork) */
apps_smmu: iommu@15000000 {
    compatible = "qcom,sm8550-smmu-500", "qcom,smmu-500", "arm,mmu-500";
    reg = <0 0x15000000 0 0x100000>;        ← 1 MiB, como el vendor
    #iommu-cells = <2>; #global-interrupts = <1>; dma-coherent;
    /* SIN clocks, SIN power-domains */
};
```

**[DATO]** y **el propio port mainline del proyecto** (`palawan.dtsi:4334-4440`) tiene el mismo nodo
(`"qcom,palawan-smmu-500","qcom,smmu-500","arm,mmu-500"`), también **sin clocks ni power-domains**, con
la misma lista de IRQs que el vendor. Dos equipos independientes (upstream sm8550 y el port palawan)
modelaron este SMMU sin relojes: no es un olvido del DT vendor.

---

## 3. La referencia dorada: Android

### 3.1 dmesg stock (el aparato, kernel que arranca) [DATO]

`~/proyectos/ubuntu-permanente/criticas/ufs-referencia-android/dmesg-android.txt`:

```
:963   [    0.143994] clk: Disabling unused clocks          ← el clk core ya apagó lo "no usado"
:1337  [    0.410972] init: Loading module /lib/modules/arm_smmu.ko
:1733  [    0.543250] arm-smmu 15000000.apps-smmu: probing hardware configuration...
:1734  [    0.543252] arm-smmu 15000000.apps-smmu: SMMUv2 with:
:1737  [    0.543284] arm-smmu 15000000.apps-smmu: 	stream matching with 110 register groups
:1738  [    0.543304] arm-smmu 15000000.apps-smmu: 	71 context banks (0 stage-2 only)
:1739  [    0.543382] arm-smmu 15000000.apps-smmu: 	Supported page sizes: 0x61311000
:1740  [    0.543383] arm-smmu 15000000.apps-smmu: 	Stage-1: 36-bit VA -> 36-bit IPA
:1742  [    0.545726] arm-smmu 15000000.apps-smmu: 	preserved 0 boot mappings
:1743  [    0.550689] ufshcd-qcom 1d84000.ufshc: Adding to iommu group 0        ← y sigue arrancando
:3044  [    2.222449] arm-smmu 3da0000.kgsl-smmu: probing hardware configuration…
:4324  [    3.556829] msmdrm_smmu soc:qcom,smmu_sde_unsec_cb: Adding to iommu group 34
```

**[DATO]** y el mismo arranque, completo hasta los 524 s de userspace Android, en
`~/proyectos/ubuntu-uke/dump/fastboot-boot-gki61/dmesg-ours-on-uke.txt` (Linux
`6.1.176-android14-11-maybe-dirty`, `Machine model: … Uke based on SM8635`): `:968` clk disable,
`:1737-1745` probe del apps-smmu, `:1747` UFS en el grupo 0, y el log sigue cientos de líneas.

### 3.2 ¿Y el nodo del Android lleva clocks? [DATO]

**No.** Es el mismo FDT que hemos descompilado: los 4 `stock-fdt*.dtb` del `vendor_boot` del propio
ROM y la base del `dtbo` del vendor. Comprobado por `fdtget -p` (§1.2) y por script sobre todos los
dumps/particiones disponibles (§1.2): **ninguno tiene `clocks` en apps-smmu**. Y el kernel vendor usa
**el mismo código de relojes** que mainline:

**[DATO]** `~/kws/common/drivers/iommu/arm/arm-smmu/arm-smmu.c:2126-2133` (GKI 6.1.176):

```c
	err = devm_clk_bulk_get_all(dev, &smmu->clks);
	if (err < 0) { dev_err(dev, "failed to get clocks %d\n", err); return err; }
	smmu->num_clks = err;
	err = clk_bulk_prepare_enable(smmu->num_clks, smmu->clks);
```

Es el mismo bloque que mainline 7.2 (`arm-smmu.c:2229-2238`). **[INFERENCIA fuerte]** el bind de
Android de apps-smmu se hizo con `num_clks = 0` y funcionó. Si "cero relojes" matara el bloque, Android
no habría llegado a userspace en ese mismo aparato, en ese mismo estado del bootloader.

### 3.3 Matiz honesto [NO VERIFICADO]

El mismo árbol kws **no** tiene `qcom,qsmmu-v500` en `arm_smmu_of_match` (`:1902-1912`) ni en
`qcom_smmu_impl_of_match` (`arm-smmu-qcom.c:455-471`), y sin embargo el kernel stock sí bindea ese
nodo. Conclusión: **el binario stock lleva un parche que este snapshot de fuentes no tiene** (el
hermano documentó uno así: `ramaa/s21/s21-binding-patches.diff:32-59`, con
`arm_smmu_of_match += qsmmu-v500 → arm_mmu500` y `qcom_smmu_impl_of_match += qsmmu-v500 →
qcom_smmu_500_impl0_data`; ese snapshot se revirtió el 15-sep, `PATCHES-SNAPSHOT-…/staged.diff`).
**No se puede decidir offline si el bind de Android pasó por `qcom_smmu_cfg_probe` (impl0) o no
(impl ninguno)**. Por eso en §5 el acceso de `cfg_probe` se marca como "no validado" y no como
"culpable".

---

## 4. Veredicto y diseño del próximo intento

### 4.1 Veredicto de la hipótesis central

**NO CUADRA**, por la conjunción de:

| evidencia | fichero:línea / comando |
|---|---|
| el driver no pide clocks por compatible; los toma solo del nodo | `arm-smmu-qcom.h:37-42` (sin campos clk), `arm-smmu.c:2229,2236` |
| el nodo vendor no tiene clocks (ni en 0x266 ni en 0x283) | `fdtget -p … /soc/apps-smmu@15000000` (§1.2) |
| Android bindea con ese nodo y ese mismo código de clk | `dmesg-android.txt:1733-1743`; `kws …/arm-smmu.c:2126-2133` |
| el clk core ya había apagado lo no usado antes del probe | `dmesg-android.txt:963` (0,144 s) vs `:1733` (0,543 s) |
| no existe reloj/GDSC de SMMU en el hardware (vendor ni fork) | greps `smmu`/`tbu` = 0 en `gcc-cliffs.c`, `qcom,gcc-cliffs.h`, `gcc-palawan.c`, `qcom,palawan-gcc.h` |
| mainline sm8550 y el port palawan también modelan apps_smmu sin clocks/PD | `sm8550.dtsi:5545-5548`; `palawan.dtsi:4334-4440` |

**[DATO colateral]** La tabla de la hipótesis H1 (ventana de `reg`) queda **refutada** por el mismo
control: Android bindea apps-smmu con `reg[0] = 0x100000` y ejecuta el reset completo (71 CBs) sobre
ese mapeo de 1 MiB; si el silicio reportara la rama "mala" (`NUMPAGENDXB` ≥ 7), el driver vendor
—cuya math de `numpage`/`pgshift` es la misma que mainline (`kws …/arm-smmu.c:1791-1800`,
`arm-smmu.h:506` `ARM_SMMU_CB(s,n) = numpage + n`)— habría escrito CBs fuera del mapeo y no habría
arrancado. Además mainline declara 1 MiB para sm8550. **[INFERENCIA]** A′ (2 MiB) no arregla nada;
es inocuo, pero *no es la causa*. Corolario práctico: **arreglar la condición de diferir** (abajo).

### 4.2 La vía DT: cerrada para clocks, y qué NO se entrega

No se crea `FRAGMENTO-SMMU-CLK.dts` porque **no hay ningún reloj que declarar**: el reloj de
apps-smmu no existe como línea de clk del SoC (no está en el GCC vendor). Un fragmento con
`clocks = <&gcc N>` sería inventar evidencia y además activaría compuertas que no son del SMMU
(p. ej. las de GPU). Regla del proyecto: no se flashea lo que no tiene mecanismo leído por el driver.
(Queda en el Anexo A la *mecánica* verificada, por si algún día existe un reloj real: etiquetas, nunca
literales, R-24.)

La única variable DT con lector (`compatible`) ya está medida: `s253d` (compatible triple) → wedge;
`s256` (reg 2 MiB, compatible intacto) → nada, porque no bindea. **El espacio DT está agotado.**

### 4.3 El diseño elegido: kernel (K1 + arming por token + migas)

**Qué cambia respecto al kernel de pokes actual (`build/kernel-pokes`, ya compilado el 28-sep 13:56):**

1. **K1 — aceptar el nombre del vendor** (no tocar el DT): dos entradas de 3 líneas. Esto hace que el
   kernel bindee **el nodo vendor tal cual** (el mismo que usa Android, con sus 2 `reg`, su
   `tcu-base`, etc.), sin ningún dtbo nuevo. Se elige esto y no el dtbo A′ porque (a) aísla la variable
   (el **dtbo** queda idéntico al que ya arranca; lo único nuevo es el kernel), y (b) **respeta la
   condición de diferir existente** (`reg[1] == 0x100000`), que A′ rompería.
2. **Arming por token** (`uke_smmu_probe=1`, early_param): sin el token, el probe de apps-smmu
   **difiere siempre** y el arranque es sano; con el token, el reintento procede. Permite el *gate 0*
   (kernel vivo) con el MISMO binario y el MISMO dtbo: la única diferencia entre gate 0 y stage 1 es
   una palabra de la cmdline (que el reempaquetador ya sabe tocar con gates).
3. **Fix de la condición de diferir**: aceptar `0x100000` **y** `0x200000` (defensa en profundidad;
   si alguien vuelve a A′, el defer no se pierde).
4. **Migas dentro de `qcom_smmu_cfg_probe` y por fases del reset** (hoy no hay ninguna dentro de
   `arm-smmu-qcom.c`; el `.o` compilado tiene 0 cadenas UKE-POKE).
5. **Volcado de IDR0/1/2** en `arm_smmu_device_cfg_probe`: cierra la pregunta de `numpage`/CB base
   para siempre y distingue "primer acceso" de "acceso a CB".

#### 4.3.1 Diff propuesto (literal, NO compilado — solo el diseño; los números de línea son del árbol actual con pokes)

```diff
--- a/drivers/iommu/arm/arm-smmu/arm-smmu.c
+++ b/drivers/iommu/arm/arm-smmu/arm-smmu.c
@@ -1957,6 +1957,11 @@ static const struct of_device_id arm_smmu_of_match[] = {
 	{ .compatible = "cavium,smmu-v2", .data = &cavium_smmuv2 },
 	{ .compatible = "nvidia,smmu-500", .data = &arm_mmu500 },
 	{ .compatible = "qcom,smmu-v2", .data = &qcom_smmuv2 },
+	/*
+	 * UKE-SMMU-CLK: el DT VENDOR de este aparato declara apps-smmu y kgsl-smmu como
+	 * "qcom,qsmmu-v500". Es el mismo silicio que mainline llama "qcom,sm8550-smmu-500"
+	 * (SMMU-500 clase v2 con tablas de 3 niveles). Sin esta entrada mainline jamas
+	 * bindea el nodo y el mdss muere con -ENODEV (no IOMMU, bailing out).
+	 */
+	{ .compatible = "qcom,qsmmu-v500", .data = &arm_mmu500 },
 	{ },
 };
@@
 static int arm_smmu_device_probe(struct platform_device *pdev)
 {
@@   /* --- bloque UKE-POKE actual: elige a que SMMU aplica --- */
 		if (np && of_property_read_u32(np, "reg", &base) == 0 &&
 		    of_property_read_u32_index(np, "reg", 1, &size) == 0 &&
-		    (u32)base == 0x15000000 && (u32)size == 0x100000) {
+		    (u32)base == 0x15000000 &&
+		    ((u32)size == 0x100000 || (u32)size == 0x200000)) {   /* vendor y A' */
 			static bool ya_diferido;
 
 			if (!ya_diferido) {
 				ya_diferido = true;
 				pr_info("UKE-POKE: apps-smmu @%p base=0x%x: primer probe DIFFERIDO …\n",
 					dev, (unsigned int)base);
 				return -EPROBE_DEFER;
 			}
+			/*
+			 * UKE: ARMING. Sin el token el bloque no se toca NUNCA: el gate 0
+			 * (kernel nuevo con el dtbo bueno) tiene que arrancar sano y dejar
+			 * que la consola demuestre que el Image arranca. Con
+			 * uke_smmu_probe=1 en la cmdline, el reintento procede y todo lo
+			 * que imprima antes del cuelgue es el diagnostico.
+			 */
+			if (!uke_smmu_armado) {
+				pr_info("UKE-POKE: apps-smmu: desarmado (falta uke_smmu_probe=1); "
+					"no se toca el bloque. Arranque sano.\n");
+				return -EPROBE_DEFER;
+			}
 			pr_info("UKE-POKE: apps-smmu: REINTENTO del probe, consola ya viva. "
 				"Lo que viene a continuacion es el probe de verdad.\n");
 		}
@@   /* al principio del fichero, junto a disable_bypass/force_stage (arm-smmu.c:56-63) */
+static bool uke_smmu_armado __ro_after_init;
+static int __init uke_smmu_armado_setup(char *s)
+{
+	uke_smmu_armado = (s && (s[0] == '1' || s[0] == 'y'));
+	return 0;
+}
+early_param("uke_smmu_probe", uke_smmu_armado_setup);
@@   /* arm_smmu_device_cfg_probe: volcado tras cada IDR (H1 definitivo) */
 	/* ID0 */ 1754: id = arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_ID0);
+	pr_info("UKE-POKE: cfg_probe ID0=0x%08x (SMS=%u groups)\n", id,
+		FIELD_GET(ARM_SMMU_ID0_NUMSMRG, id));
 	/* ID1 */ 1849: id = arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_ID1);
+	pr_info("UKE-POKE: cfg_probe ID1=0x%08x pgshift=%u NUMPAGENDXB=%u CBs=%u; "
+		"CB base=0x%llx (mmio=%u B)\n", id, smmu->pgshift,
+		(unsigned int)FIELD_GET(ARM_SMMU_ID1_NUMPAGENDXB, id),
+		(unsigned int)FIELD_GET(ARM_SMMU_ID1_NUMCB, id),
+		(u64)(1u << (FIELD_GET(ARM_SMMU_ID1_NUMPAGENDXB, id) + 1)) << smmu->pgshift,
+		smmu->numpage);
 	/* ID2 */ 1875: id = arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_ID2);
+	pr_info("UKE-POKE: cfg_probe ID2=0x%08x\n", id);
@@   /* arm_smmu_device_reset (arm-smmu.c:1661): migas por fase */
-	reg = arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_sGFSR);           /* 1667 */
-	… for SMR/S2CR (1674-1675) … for CBs (1678-1681) …
-	… TLBIALLH/NSNH (1684-1685) … sCR0 (1687) … impl->reset (1715-1716) …
-	tlb_sync_global + write sCR0
+	pr_info("UKE-POKE: reset fase1 sGFSR\n");            antes de 1667
+	pr_info("UKE-POKE: reset fase2 SMR/S2CR x%u\n", smmu->num_mapping_groups);  antes de 1674
+	pr_info("UKE-POKE: reset fase3 CBAR/SCTLR/FSR x%u\n", smmu->num_context_banks); antes de 1678
+	pr_info("UKE-POKE: reset fase4 TLBIALLH/TLBIALLNSNH\n");                    antes de 1684
+	pr_info("UKE-POKE: reset fase5 RMW de sCR0\n");                             antes de 1687
+	pr_info("UKE-POKE: reset fase6 impl->reset (arm_mmu500_reset)\n");          antes de 1715
+	pr_info("UKE-POKE: reset fase7 tlb_sync_global + write sCR0\n");            antes de 1719
@@
--- a/drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c
+++ b/drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c
@@ -797,6 +797,9 @@ static const struct of_device_id __maybe_unused qcom_smmu_impl_of_match[] = {
 	{ .compatible = "qcom,sm8450-smmu-500", .data = &qcom_smmu_500_impl0_data },
 	{ .compatible = "qcom,smmu-500", .data = &qcom_smmu_500_impl0_data },
+	/* UKE-SMMU-CLK: el nombre del vendor tambien entra por impl0 (cfg_probe + reset
+	 * + def_domain_type IDENTITY del parche UKE). La rama adreno se elige ANTES
+	 * (qcom_smmu_impl_init, :707), asi que kgsl no cambia de comportamiento. */
+	{ .compatible = "qcom,qsmmu-v500", .data = &qcom_smmu_500_impl0_data },
 	{ }
 };
@@   /* qcom_smmu_cfg_probe (:470-535): migas alrededor de los dos accesos "unico" */
 	if (smmu->num_mapping_groups > 128)
 		last_s2cr = ARM_SMMU_GR0_S2CR(127);
 	else
 		last_s2cr = ARM_SMMU_GR0_S2CR(smmu->num_mapping_groups - 1);
+	pr_info("UKE-POKE: qcom_cfg_probe: VOY a ESCRIBIR S2CR(0x%x) reg=0x%08x\n", last_s2cr, reg);
 	arm_smmu_gr0_write(smmu, last_s2cr, reg);                    /* :497 — 1er WRITE del probe */
 	reg = arm_smmu_gr0_read(smmu, last_s2cr);                    /* :498 */
+	pr_info("UKE-POKE: qcom_cfg_probe: relectura=0x%08x (TYPE=%lu; quirk=%s)\n", reg,
+		FIELD_GET(ARM_SMMU_S2CR_TYPE, reg),
+		FIELD_GET(ARM_SMMU_S2CR_TYPE, reg) != S2CR_TYPE_BYPASS ? "SI" : "no");
 …
+	pr_info("UKE-POKE: qcom_cfg_probe: leyendo SMR(0..%u)\n", smmu->num_mapping_groups - 1);
 	for (i = 0; i < smmu->num_mapping_groups; i++) {
 		smr = arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_SMR(i));      /* :517 */
 		…
 	}
+	pr_info("UKE-POKE: qcom_cfg_probe: SMR loop OK (validos=%u)\n", n_validos);
```

**Por qué cada pieza**:

- **K1** es la versión que ya existió en `ramaa/s21/s21-binding-patches.diff:49-58` (y se revirtió el
  15-sep sin motivo documentado: [NO VERIFICADO]). Con las migas + token, repetirla no repite el
  problema: la primera vez fue sin instrumentación.
- El **token** convierte el nuevo Image en un arma con seguro. Sin él, cualquier boot con el kernel
  nuevo ya ejecutaría el probe de riesgo a los ~30 s, y no habría forma de separar "el Image no
  arranca" de "el probe cuelga".
- El **fix de la condición** evita el bug-clase que ya costó un ciclo entero (`patch-uke-smmu-pokes.py`
  documenta el `read_u32` vs `read_u32_index`; este es el mismo tipo de trampa en el `size`).
- Las **migas de `qcom_smmu_cfg_probe`** son las que faltan justo en el acceso nunca validado (§5).

### 4.4 Si en el futuro alguien insiste en la vía DT

Sería `s253` (compatible triple) pero **con el kernel de pokes armado**, que es lo mismo que §4.3 con
una variable más (el dtbo). No aporta: la única diferencia leída por el driver entre "compatible triple
por dtbo" y "qsmmu-v500 por kernel" es *cero* (ambos terminan en `qcom_smmu_500_impl0_data` +
`arm_mmu500`). Por eso se elige no tocar el DT.

---

## 5. Plan B — inventario de primeros accesos y qué instrumento los distingue

Orden real del probe tal y como está el árbol (con el defer delante; sin defer, en device_initcall):

| # | acceso (primer MMIO de cada bloque) | fichero:línea | ¿validado por un control vivo? | qué lo distingue |
|---|---|---|---|---|
| 0 | `ioremap` + `clk_bulk_get_all` | `arm-smmu.c:2192,2229` | n/a (no tocan el bus) | — |
| 1 | **IDR0** (0x0), IDR1 (0x4), IDR2 (0x8) | `arm-smmu.c:1754,1849,1875` | **sí**: Android lee los mismos a 0,54 s | miga "VOY a cfg_probe" + volcado IDR (§4.3); si muere AQUÍ con consola viva es estado del bloque (H3′) |
| 2 | **S2CR(109) ← BYPASS\|0xff** (0xDB4) + relectura | `arm-smmu-qcom.c:497-498` | **NO** (kgsl no lo ejecuta; Android [NO VERIFICADO]) | migas de `qcom_smmu_cfg_probe` §4.3 |
| 2b | rama quirk: CB70 SCTLR=0, GR1 CBAR(70) | `arm-smmu-qcom.c:505,508` | no | la relectura impresa dice si entró en la rama |
| 3 | **barrido SMR(0..109)** (0x800+n·4) | `arm-smmu-qcom.c:517` | **NO** | migas antes/después del bucle |
| 4 | `sGFSR` RMW | `arm-smmu.c:1667-1668` | sí (Android hace el mismo reset) | fase 1 del reset |
| 5 | **110× SMR/S2CR writes** (invalidate) | `arm-smmu.c:1674-1675` | sí | fase 2 |
| 6 | **71× CB SCTLR/FSR** (CB base+0/0x58) | `arm-smmu.c:1678-1681` | sí | fase 3 (si muere aquí, H1/CB-window viva por fin) |
| 7 | TLBIALLH/NSNH | `arm-smmu.c:1684-1685` | sí | fase 4 |
| 8 | `sCR0` RMW | `arm-smmu.c:1687-1713` | sí | fase 5 |
| 9 | **`arm_mmu500_reset`**: ID7 (0x3c), sACR (0x10) RMW, **71× CB_ACTLR (0x4) RMW** | `arm-smmu-impl.c:118,122-130,132-143` | **solo a 22 CBs** (kgsl); a 71 CBs no | fase 6 (ya hay miga dentro) |
| 10 | `tlb_sync_global` (0x70 write + poll 0x74) | `arm-smmu.c:1719` (+`arm-smmu-qcom.c:88`) | sí | fase 7 |
| 11 | `arm_smmu_test_smr_masks` (SMR(0)/S2CR(0)) | llamada `arm-smmu.c:2283` (cuerpo `:995`) | sí | miga justo antes |

**Lectura del resultado (el árbol de decisión del próximo ciclo)** — este es el entregable que
convierte 8 wedges mudos en una única línea:

```
Gate 0 (token OFF, dtbo s238, kernel nuevo):
  (a) `Linux version 7.2.0-rc2-palawan+ … <banner NUEVO>`
      + `UKE-POKE: arm_smmu_device_probe ENTRANDO, dev=3da0000.kgsl-smmu`
      + `UKE-POKE: … -> arm_smmu_device_cfg_probe` (del kgsl)
      + `UKE-POKE: … REINTENTO`/`desarmado` para 15000000.apps-smmu      → KERNEL VIVO, seguir
  (b) cero líneas / sin banner nuevo  → NO SEGUIR; forense del Image (ver §6.1)

Stage 1 (token ON, mismo binario, mismo dtbo):
  `ENTRANDO`(apps) → `primer probe DIFFERIDO` → (t≈30 s) `REINTENTO` →
  `-> arm_smmu_device_cfg_probe` → `probing hardware configuration…` + IDR0/1/2 →
      ├─ muere tras IDR1/IDR2      ⇒ H3′ (estado del bloque al primer READ)  → kernel/imagen, no DT
      ├─ muere en `qcom_cfg_probe` ⇒ H2a (S2CR write / SMR sweep)            → probe quirúrgico
      ├─ muere en fase 2–5          ⇒ H4 (reset core)                        → comparar con Android
      ├─ muere en fase 6            ⇒ H2b (sACR/CB_ACTLR ×71)                → reducir CBs o quirk
      ├─ muere en fase 7 / tras ella⇒ TLB sync / test_smr_masks              → fin del probe
      └─ `Adding to iommu group` del mdss y NO `no IOMMU, bailing out` ⇒ SMMU VIVO: pasar a display
```

---

## 6. Riesgos y cosas NO VERIFICADAS (leer antes de ejecutar)

### 6.1 El kernel de pokes nunca ha demostrado arrancar [DATO del ledger]

`build/gates/PRE-REGISTRO-F5-B1.md:1137-1163` documenta el intento de aislamiento (28-sep ~14:35):
`boot-pokes.img` (`11cf3482…`) + dtbo **s238 bueno** en slot A ⇒ **cuarto arranque mudo**, cero líneas
(incluso el banner). Caveat del propio ledger: tramo contaminado por dos lectores de consola; veredicto
apoyado en el rollback limpio. **Hipótesis abiertas**: (i) el Image nuevo no arranca (config/repack);
(ii) tema de slot A/vbmeta ("imagen de boot nueva en slot A" es el común de los 4 mudos).
**Diferencias de config medidas hoy** (kernel bueno `ramaa/s10/build-s122/.config` vs
`build/kernel-pokes/.config`): 75 opciones solo en el bueno y 20 solo en el nuevo — entre ellas
`CONFIG_INITRAMFS_SOURCE=…s181-initramfs.cpio.gz`, `CONFIG_PANIC_TIMEOUT=10`,
`CONFIG_DETECT_HUNG_TASK=y`, `CONFIG_MTD_BLOCK2MTD=y`, `CONFIG_DRM_PANEL_XIAOMI_O82_DUALDSI=y`,
`CONFIG_LOCKUP_DETECTOR=y`, y el `CONFIG_CMDLINE` por defecto con `rdinit=/init panic=10 loglevel=7
clk_ignore_unused pd_ignore_unused`. **[NO VERIFICADO]** cuál de ellas (o el repack) explica el mute;
el gate 0 existe justo para no gastar el intento del SMMU antes de cerrarlo.

### 6.2 Otros riesgos

1. **El wedge puede ser un stall de bus que también se lleva la consola**: por eso el kernel debe
   diferir el probe (el wedge ocurre con el resto del sistema ya arrancado y el buffer de consola
   vaciado; la última línea *se ve*). Requisitos: UN solo lector de `/dev/ttyACM0`
   (`REGLA-UN-SOLO-LECTOR.md`), `dmesg -n 7`.
2. **K1 cambia el comportamiento de kgsl para el impl**: `qcom_smmu_impl_init` mira
   `qcom,adreno-smmu` ANTES (`arm-smmu-qcom.c:707`), así que kgsl sigue con impl adreno. Verificable en
   el gate 0 (mismas líneas que hoy).
3. **A 30 s, UFS/USB ya están vivos**: el probe reprograma SMR/S2CR de todos los grupos. Es
   intrínseco al experimento; Android lo hace en el primer segundo. Si el sistema muere *después* de
   "Adding to iommu group", el veredicto es "el bind es viable pero el orden/estado no": siguiente
   palanca sería el propio defer (probar con `deferred_probe_timeout` distinto) o el dtbo.
4. **La inestabilidad medida de s253d** (un boot a login sin red, otro mudo pre-consola) sugiere un
   componente dependiente de estado (estado del bootloader/reboot previo, no solo el acceso). El
   volcado de IDR + el orden de las migas permiten comparar el *mismo* binario en dos boots; anotar en
   cada intento si vino de fastboot-reboot o de apagado/encendido (dato que hoy no se registra).
5. **La vía DT no está "reservada"**: A′ (`s253`) sigue construido y verificado (`eeb57d95…`), pero
   **no debe usarse con el kernel de pokes actual** (condición de defer) salvo con el fix §4.3.

---

## Anexo A — la mecánica DT, verificada (aunque hoy no haya reloj que poner)

**[DATO]** phandles reales del base (por etiqueta, nunca literales; R-24):

```
$ python3 … (parseo de __symbols__ de base-dtb.img)
gcc      -> /soc/clock-controller@100000     (phandle 0x16e)
gpucc    -> /soc/clock-controller@3d90000    (phandle 0x175)
dispcc   -> /soc/clock-controller@af00000
camcc    -> /soc/clock-controller@ade0000
aoss_qmp -> /soc/power-controller@c300000
tlmm     -> /soc/pinctrl@f000000
apps_smmu-> /soc/apps-smmu@15000000
kgsl_smmu-> /soc/kgsl-smmu@3da0000
```

**[DATO]** un overlay de prueba (en `/tmp`, NO en el repo, NO flashable) con
`clocks = <&gcc 0>, <&gpucc 0>` sobre apps-smmu se fusiona y **resuelve**:

```
$ fdtoverlay -i base-dtb.img -o merged-test.dtb test-label.dtbo && echo FDT-OVERLAY-OK
FDT-OVERLAY-OK
clocks resueltos: 0x16e 0x00 0x175 0x00      ← las etiquetas resolvieron a los phandles reales
```

Si algún día existe una compuerta real de apps-smmu, así se declara (etiqueta; el ABL reubica vía
`__fixups__`). Hoy **no se entrega** `FRAGMENTO-SMMU-CLK.dts` porque los `clocks` a poner no existen
(§4.2), y hacerlo sería evidencia fabricada.

## Anexo B — comandos de reproducción (todo offline)

```bash
dtc -I dtb -O dts -o /tmp/smmuclk/base-dtb.dts ~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img
fdtget -p  ~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img /soc/apps-smmu@15000000
fdtget -p  ~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img /soc/kgsl-smmu@3da0000
grep -c clk ~/gpu-work/palawan-linux/drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c      # 0
sed -n '775,802p;1957,1968p' ~/gpu-work/palawan-linux/drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c \
                             ~/gpu-work/palawan-linux/drivers/iommu/arm/arm-smmu/arm-smmu.c
diff <(grep -E '^CONFIG_' ~/gpu-work/ramaa/s10/build-s122/.config | sort) \
     <(grep -E '^CONFIG_' ~/proyectos/omarchy-uke/build/kernel-pokes/.config | sort)
python3 ~/proyectos/omarchy-uke/build/gates/patch-uke-smmu-pokes.py   # (NO ejecutar ahora; solo lectura)
```

## Anexo C — lo que este informe NO ha podido cerrar

1. Qué impl exacto usó el bind de apps-smmu en el kernel stock (el snapshot `kws/common` no tiene la
   entrada `qsmmu-v500`; el binario stock sí, §3.3). Si el stock pasó por `qcom_smmu_cfg_probe`, el
   candidato nº1 de §5 se debilita y sube el reset a 71 CBs.
2. Por qué un `boot.img` nuevo en slot A dio 4 mudos (§6.1).
3. Si el silicio reporta `NUMPAGENDXB` 6 o 7 — el volcado de IDR propuesto lo decide en el primer
   boot instrumentado.
