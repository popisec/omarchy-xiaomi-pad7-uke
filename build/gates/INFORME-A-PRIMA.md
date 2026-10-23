# INFORME A′ — repunte de `apps-smmu` con la VENTANA de registros corregida

**28-sep-2026 · proyecto omarchy-uke · artefacto `s253-boot-dtbo-aprima.img` — PREPARADO, SIN FLASHEAR**

Convención: **[DATO]** = fichero:línea o comando + salida. **[INFERENCIA]** = deducción mía encadenada
sobre datos. **[NO VERIFICADO]** = no se ha medido y no se puede medir sin la tablet.

Nada de este informe se ha ejecutado en la tablet. No se ha tocado `~/gpu-work/palawan-linux`
(solo lectura) ni `~/proyectos/ubuntu-permanente` (solo lectura). En `omarchy-uke` solo se han
creado ficheros nuevos (este informe, `build/bootimg/mkdtbo-s253.py`, `build/bootimg/s253-boot-dtbo-aprima.img`,
`build/gates/s253-GATES.log`).

---

## 0. Titulares

1. **A′ existe y está construido**: `build/bootimg/s253-boot-dtbo-aprima.img`, **607 714 B**,
   **sha256 `eeb57d95a5454afdfc4312264a84a612ab2fa67d29eb1c98fa3754a82765a4e1`**, cabiendo en `dtbo_b`
   (610 304 B) con 2 590 B de margen. Todas las aserciones del constructor en verde (`build/gates/s253-GATES.log`).
2. **A′ es un cambio de TRES propiedades** en `/soc/apps-smmu@15000000` (una sola diferencia semántica
   frente al `s238` que está ahora en la tablet): el `compatible` que mainline acepta, **`reg` = una sola
   región de 2 MB** (en lugar de las dos del vendor, la primera de 1 MB) y `reg-names = "base"`.
3. **El hallazgo que justifica A′ (y que explica el `s251`)**: en este driver el tamaño de `reg[0]` **no es
   decorativo**, es lo que valida la *ventana* dentro de la cual el driver sitúa los *context banks*; y la
   posición de esos CB la decide el **hardware** (IDR1), no el DT. Con el `reg` de 1 MB del vendor, si el
   silicio reporta `NUMPAGENDXB=7` el driver calcula el CB base **justo fuera de la región mapeada** y el
   primer acceso a un CB (en `arm_smmu_device_reset`) es un acceso a VA no mapeada: oops de la tarea init
   → panic → **cero consola** (ttyGS0 lo crea el init de usuarios) y sin pstore. Es la forma exacta del
   wedge mudo medido. Citas: `arm-smmu.c:2192,2201,1846-1859` + `arm-smmu.h:479,518`.
4. **Eso es la hipótesis H1 (principal, viva y NO decidida offline)**: el hardware puede reportar
   `size=0x80000` (en cuyo caso el `reg` del vendor ya estaba bien y A′ es inerte salvo el ioremap y un
   aviso) o `size=0x100000` (en cuyo caso A′ **es el arreglo**). A′ cubre las dos ramas; el aviso
   `SMMU address space size … differs from mapped region size …` que el propio driver imprime es el
   discriminador (árbol de decisión en §6).
5. **La hipótesis "la FORMA del nodo wedgea" (2 `reg` + hijos TBU) queda REFUTADA por control**: el
   `kgsl-smmu@3da0000` de este mismo aparato tiene la misma forma vendor (2 `reg`, `tcu-base`, hijo
   `gpu_qtb`) y **bindea y funciona en el kernel que está ahora en la tablet** (`arm-smmu 3da0000.kgsl-smmu:
   probing hardware configuration… SMMUv2 … 24 register groups … 22 context banks`). Ningún delta del nodo
   salvo el tamaño de `reg[0]` tiene lector en el árbol (§2). **Por eso A′ no "limpia" el nodo: solo cambia
   la ventana**, que es el único delta con lector.
6. **LO QUE A′ NO ARREGLA**: si el wedge es (H2) un acceso a un registro *decodificado* que el firmware/TZ
   no tolera, o (H4) el reset destruyendo los SMRs que dejó el bootloader, **ningún dtbo lo arregla** y A′
   wedgeará igual que `s251`. No hay palanca de DT para eso.
7. **Riesgo operativo intacto**: `CONFIG_ARM_SMMU_MMU_500_CPRE_ERRATA=y` hace que `arm_mmu500_reset`
   ejecute RMW sobre `CB_ACTLR` de los **71** context banks (`arm-smmu-impl.c:131-143`); es la mayor
   superficie de MMIO del probe. Medido en los dos `.config` del árbol; un dtbo no la reduce.
8. **Controles negativos en verde**: los mismos gates que A′ pasa **rechazan al `s238`** (compatible de
   vendor) y **al `s251`**, el dtbo que wedgeó la tablet (reg de 1 MB) — y un control unitario demuestra que
   el gate de la ventana salta *precisamente* con 1 MB.

---

## 1. Qué tiene que pasar para que el display progrese (con la línea de código)

### 1.1 La condición del `-19` (es del lado del *display*, no del SMMU)

`drivers/gpu/drm/msm/msm_kms.c:180-200`:

```c
struct drm_gpuvm *msm_kms_init_vm(struct drm_device *dev, struct device *mdss_dev)
{
	...
	if (device_iommu_mapped(mdp_dev))            /* msm_kms.c:193 */
		iommu_dev = mdp_dev;
	else if (mdss_dev && device_iommu_mapped(mdss_dev))   /* :195 */
		iommu_dev = mdss_dev;
	else {
		drm_info(dev, "no IOMMU, bailing out\n");     /* :198 */
		return ERR_PTR(-ENODEV);                      /* :199  -> -19 */
	}
```

**[DATO-offline]** `device_iommu_mapped(dev)` es `dev->iommu_group != NULL`: **lo que hay que conseguir es
que el device del display tenga `iommu_group`.** El camino:

- `/soc/display-subsystem@ae00000` (el `mdss`) lleva `iommus = <0x129 0x1c00 0x02>`
  (fuente: `build/gates/EVIDENCIA-PANTALLA-28sep.md:131-138`; y el gate G6 lo vuelve a medir en cada
  build sobre el árbol fusionado: `DPU iommus = <0x129 0x1c00 0x02>`).
- `dpu_kms.c:1105-1116` pasa al VM el **padre** (`dpu_kms->dev->dev->parent` = el mdss).
- El `iommu_group` de ese device se crea cuando **alguien con `of_xlate` y `device_group` está bindeado
  sobre el nodo al que apunta el phandle `0x129`** — y el phandle `0x129` es `apps-smmu@15000000`
  (DATO: en el fusionado de A′, `apps-smmu` conserva `phandle = <0x129>`, gate G3; en el DT stock
  `stock-fdt2.dts:13175`).
- Hoy el driver de `apps-smmu` es **ninguno**: su `compatible` es `"qcom,qsmmu-v500"`, que no está en
  ninguna tabla de match del árbol. Por eso `iommu_group` no existe y el DPU muere con `-ENODEV`
  (`dpu_kms.c:1181-1185`: `dpu_kms_mmu_init failed: -19`).

### 1.2 Qué exige el driver mainline para bindear (y para no morir antes)

Todo en `drivers/iommu/arm/arm-smmu/`. El árbol de trabajo **tiene los pokes UKE aplicados** (hay
`pr_info("UKE-POKE: …")` dentro de `arm_smmu_device_probe`, p.ej. `arm-smmu.c:2134`), así que las líneas
citadas son las del árbol *tal y como está ahora*; los números están desplazados unas decenas de líneas
respecto al upstream limpio, pero las funciones son las de siempre.

| requisito | dónde | qué pasa si no |
|---|---|---|
| `compatible` en `arm_smmu_of_match` — necesita **`arm,mmu-500`** | `arm-smmu.c:1957-1968` (entrada en `:1962`) | no hay bind. Añadir solo `qcom,smmu-500` es **inerte** para el bind (no está en esa tabla) |
| `#global-interrupts` presente | `arm-smmu.c:2044-2046` | `-ENODEV` ("missing #global-interrupts property") |
| `interrupts` ≥ `#global-interrupts` + 1 | `arm-smmu.c:2207-2213` | `-ENODEV` |
| para SMMUv2, `num_context_banks (71)` ≤ nº de IRQs de contexto | `arm-smmu.c:2244-2250` | `-ENODEV` ("found only N context irq(s) but 71 required") |
| `clocks` opcional (`clk_bulk_get_all`) | `arm-smmu.c:2229-2238` | el nodo vendor **no tiene `clocks`** → 0 clocks, sin efecto |
| **`reg[0]` mapeable y con la ventana correcta** | `arm-smmu.c:2192`, `:2201`, `:1846-1859` | §1.3 |
| `qcom,smmu-500` en `qcom_smmu_impl_of_match` | `arm-smmu-qcom.c:775-801` (entrada `:800`) | sin impl qcom: **sin `def_domain_type` del parche UKE** → los 57 maestros pedirían dominio TRADUCIDO |
| `qcom_scm` listo | `arm-smmu-qcom.c:716` | `-EPROBE_DEFER` (limpio, se reintenta) |

El impl que escoge `qcom,smmu-500` es `qcom_smmu_500_impl0_data` (`arm-smmu-qcom.c:764-770`) →
`.impl = &qcom_smmu_500_impl` (`:651-658`), que trae `.def_domain_type = qcom_smmu_def_domain_type`
(`arm-smmu-qcom.c:604-621`, con el parche UKE: `qcom,wcn6750-wifi` traducido, **el resto IDENTITY**).
Con IDENTITY el attach escribe `S2CR_TYPE_BYPASS` (`arm-smmu.c:1237-1243`,
`arm_smmu_attach_dev_type(dev, S2CR_TYPE_BYPASS)`): **no se toca ningún context bank por maestro**.

### 1.3 LA VENTANA: lo que de verdad hace `reg` en este driver **[DATO-offline, el núcleo de A′]**

```c
	/* arm-smmu.c:2192 */
	smmu->base = devm_platform_get_and_ioremap_resource(pdev, 0, &res);
	...
	/* arm-smmu.c:2201  — OJO: son BYTES */
	smmu->numpage = resource_size(res);
	...
	/* arm-smmu.c:1846-1859, dentro de arm_smmu_device_cfg_probe() */
	smmu->pgshift = (id & ARM_SMMU_ID1_PAGESIZE) ? 16 : 12;
	size = 1 << (FIELD_GET(ARM_SMMU_ID1_NUMPAGENDXB, id) + 1);
	if (smmu->numpage != 2 * size << smmu->pgshift)
		dev_warn(smmu->dev,
			 "SMMU address space size (0x%x) differs from mapped region size (0x%x)!\n",
			 2 * size << smmu->pgshift, smmu->numpage);
	smmu->numpage = size;      /* ahora en PAGINAS */

	/* arm-smmu.h:479 y :518 */
	arm_smmu_page(s, n) = smmu->base + (n << smmu->pgshift)
	#define ARM_SMMU_CB(s, n)   ((s)->numpage + (n))
```

Consecuencia, en una línea: **CB base (bytes) = base + `size` × tamaño_de_página**, y `size` sale del
**hardware** (IDR1.NUMPAGENDXB). El DT no puede cambiar `size`; el DT solo declara una región que debe
cubrir `2*size` (convenio ARM: media parte global + media parte de context banks). Y **el driver no aborta
si no cuadra: solo avisa** y sigue usando el `size` del hardware.

Las dos ramas posibles del silicio:

| rama (IDR1) | CB base que calcula el driver | los 71 CB llegan hasta | ¿cabe en `reg[0] = 0x100000` (vendor)? | ¿cabe en `reg[0] = 0x200000` (A′)? |
|---|---|---|---|---|
| `size = 0x80000` (NUMPAGENDXB=6) | `0x15080000` | `0x150C7000` | **SÍ** | SÍ (aviso, mismo CB base) |
| `size = 0x100000` (NUMPAGENDXB=7) | `0x15100000` | `0x15147000` | **NO — fuera del mapeo** | SÍ |

Y qué pasa si se sale del mapeo: `devm_platform_get_and_ioremap_resource` mapea **exactamente**
`resource_size(res)` (1 MB) y deja la guarda de vmalloc sin mapear justo después. El primer acceso a un CB
es, en el reset, `arm_smmu_write_context_bank()` para el CB 0 sin asignar:

```c
	/* arm-smmu.c:576-587 */
	if (!cfg) {                                          /* CB sin asignar */
		arm_smmu_cb_write(smmu, idx, ARM_SMMU_CB_SCTLR, 0);   /* CB base + 0x0 */
		return;
	}
```

→ escritura a `0x15100000` con el mapeo acabando en `0x15100000`: **VA del vmalloc no mapeada** → abort
de traducción en modo kernel. Y ocurre en `arm_smmu_device_reset()` (`arm-smmu.c:2282`), llamado desde el
probe, que es `module_init` → **`device_initcall`** (`arm-smmu.c:2438`: `module_init(arm_smmu_init)`, con
`CONFIG_ARM_SMMU=y` medido en ambos `.config`): antes de que exista `ttyGS0` y sin ramoops configurado.
**[INFERENCIA]** oops en la tarea init → panic → arranque mudo, y con `panic=10` (cmdline) el SoC
reinicia: eso encaja con el `slot-retry-count:b 7→0` medido (7 intentos consumidos) antes de caer a
fastboot. **[NO VERIFICADO]** el mecanismo exacto del silencio (oops→panic vs stall de bus); la lista de
posibles avisos previos a un oops es la de §6.

**Por qué A′ cambia `reg` y no otra cosa**: es el **único delta de forma del nodo vendor que el driver
lee** (§2). No es "limpiar el nodo por estética": es dar al driver una ventana en la que quepan los 71 CB
en las dos ramas posibles del hardware, sin mover ni un acceso en la rama buena.

---

## 2. La forma del nodo vendor (descompilado) y qué deltas tienen lector

### 2.1 Cuál es *nuestro* DT stock y cuál es la base de los gates

**[DATO]** `~/gpu-work/stock-dtbs/` tiene los 4 DTB del `vendor_boot` del vendor. Comando y salida:

```
$ for f in 0 1 2 3; do dtc -I dtb -O dts -o /tmp/stockf$f.dts ~/gpu-work/stock-dtbs/stock-fdt$f.dtb; done
$ grep -m1 msm-id /tmp/stockf{0,1,2,3}.dts
/tmp/stockf0.dts:6:  qcom,msm-id = <0x266 0x10000>;    <- "cliffs"
/tmp/stockf1.dts:6:  qcom,msm-id = <0x278 0x10000>;
/tmp/stockf2.dts:6:  qcom,msm-id = <0x283 0x10000>;    <- "cliffsp" = ESTE aparato
/tmp/stockf3.dts:6:  qcom,msm-id = <0x282 0x10000>;
```

**[DATO]** el fdt de este aparato es **fdt2 (msm-id 0x283)**, y su nodo es:

```
/tmp/stockf2.dts:13160-13265   (106 líneas; decompilado con dtc v1.8.1)

	apps_smmu: apps-smmu@15000000 {
		compatible = "qcom,qsmmu-v500";
		reg = <0x15000000 0x100000 0x151fe000 0x40>;      <- DOS regiones
		reg-names = "base", "tcu-base";
		#iommu-cells = <0x02>;
		qcom,use-3-lvl-tables;
		qcom,handoff-smrs = <0x1c00 0x02>;
		#global-interrupts = <0x01>;
		#size-cells = <0x01>;  #address-cells = <0x01>;  ranges;
		dma-coherent;
		status = "ok";
		interrupts = <...>;      <- 97 entradas (1 global SPI 65 + 96 de contexto)
		qcom,actlr = <...>;      <- 31 tripletas (sid, mask, actlr)
		phandle = <0x129>;
		<8 hijos> qcom,qsmmuv500-tbu / qcom,qtb500:
		  anoc_1_qtb@16f1000  anoc_2_qtb@171a000  cam_hf_qtb@14d2000  nsp_qtb@7d3000
		  lpass_qtb@7b3000    pcie_qtb@16cd000   sf_qtb@1451000      mdp_hf_qtb@14d0000
		  (cada uno: 2 reg, reg-names base/debugchain-base, qcom,stream-id-range,
		   qcom,iova-width, interconnects, qcom,num-qtb-ports)
	};
```

**[DATO]** `base-dtb.img` (la base contra la que los constructores hacen `fdtoverlay`, y contra la que se
mergea en los gates) **no es fdt2**: descompila al mismo contenido que el fdt0 (msm-id 0x266, `compatible =
"qcom,cliffs"`), recompilado con `dtc -@` (tiene `__symbols__`; es lo que permite usar etiquetas en los
overlays). Los phandles difieren en 1 en algún nodo entre fdt0 y fdt2, pero **el de `apps_smmu` es `0x129`
en los dos** (DATO: `stock-fdt2.dts` arriba y `s253-merged.dts` de los gates), así que el `iommus` del mdss
resuelve igual. **[INFERENCIA]** el ABL aplica el overlay sobre *su* base (0x283); los gates lo aplican
sobre el 0x266 por ser el que está fijado y compartido por todo el proyecto. Como A′ no introduce ni una
referencia por phandle (§5, G7b), la diferencia de numeración no puede afectarnos.

### 2.2 La referencia de mainline (arm64, mismo árbol)

```
arch/arm64/boot/dts/qcom/sm8550.dtsi:5545-5648   apps_smmu: iommu@15000000
	compatible = "qcom,sm8550-smmu-500", "qcom,smmu-500", "arm,mmu-500";   (:5546)
	reg = <0 0x15000000 0 0x100000>;                                        (:5547)
	#iommu-cells = <2>;  #global-interrupts = <1>;  interrupts = <97 entradas>;  dma-coherent;
	(sin `reg-names`, sin `ranges`, sin hijos, sin `qcom,actlr`, sin `clocks` ni `power-domains`)
```

**[DATO]** la lista de IRQs del nodo mainline de sm8550 es **la misma** que la del nodo vendor de este
aparato (SPI 65 + 97..118 + 181..192 + 315..345 + …): el contrato de IRQs ya coincidía con mainline. A′
no lo toca (gate G3 lo verifica: 1 global + 96 = 97 entradas).

### 2.3 Los deltas vendor↔mainline y si tienen lector en este kernel

| delta del vendor | ¿quién lo lee? | veredicto |
|---|---|---|
| `reg` en 2 entradas (`0x100000` + `0x151fe000+0x40`), `reg-names = base,tcu-base` | `arm-smmu.c:2192` lee **solo resource 0**; **el TAMAÑO** entra en `numpage` (`:2201`) → §1.3 | **EL ÚNICO DELTA CON LECTOR REAL.** A′ = 1 región de 2 MB |
| 8 hijos `qcom,qsmmuv500-tbu`/`qcom,qtb500` | `qcom_smmu_tbu_of_match` (`arm-smmu-qcom.c:831-834`) solo tiene `qcom,sc7280-tbu` y `qcom,sdm845-tbu`. Grep del árbol: `qsmmuv500-tbu`/`qtb500` → **0 lectores** | inertes (dispositivos de plataforma sin driver). A′ los deja |
| `qcom,actlr` | **0 lectores** (grep en `drivers/`): el ACTLR por cliente lo decide `qcom_smmu_actlr_client_of_match` (`arm-smmu-qcom.c:35-64`), que no tiene ningún compatible mdss/palawan | inerte. A′ lo deja |
| `qcom,handoff-smrs`, `qcom,use-3-lvl-tables` | **0 lectores** (grep árbol completo) | inertes. A′ los deja |
| `ranges` + `#address-cells/#size-cells = 1` | solo sirven a los hijos | inerte. A′ lo deja |
| `phandle = <0x129>` | lo resuelve el `iommus` del mdss | **intacto** (gate G3) |
| `interrupts` (97) / `#global-interrupts` | `arm-smmu.c:2044, 2207-2213, 2244-2250` | igual que mainline. A′ no lo toca |
| `dma-coherent` | `arm-smmu.c:2067` (`ARM_SMMU_FEAT_COHERENT_WALK`) | presente. A′ no lo toca |
| `compatible` | §1.2 | **ESO ES LO QUE HAY QUE CAMBIAR** (y lo que cambió `s251`) |

---

## 3. Por qué wedgeó `s251` (y por qué wedgeó el "arreglo A" del hermano)

### 3.1 El control que mata la hipótesis de la forma **[DATO-vivo-consola]**

El `kgsl-smmu@3da0000` **tiene la misma forma vendor** que `apps-smmu` (`/tmp/base.dts:13148-13178`:
`compatible = "qcom,qsmmu-v500", "qcom,adreno-smmu"` + `reg = <0x3da0000 0x40000 0x3de6000 0x40>` +
`reg-names = base,tcu-base` + hijo `gpu_qtb`) y con el `compatible` ampliado del dtbo `s229` que está en
la tablet **bindea en el kernel bueno**:

```
build/gates/EVIDENCIA-PANTALLA-28sep.md:123-126
  [DATO-vivo-consola] `arm-smmu 3da0000.kgsl-smmu: probing hardware configuration… SMMUv2 with:
  stage 1 translation / coherent table walk / stream matching with 24 register groups /
  22 context banks (0 stage-2 only) / Supported page sizes: 0x61311000 / Stage-1: 48-bit VA -> 36-bit IPA`
```

⇒ **Dos `reg`, `tcu-base` y los hijos TBU no pueden ser la causa del wedge.** Lo único que cambia entre
"binden los dos" y "binden solo kgsl" no es la forma, es **la instancia** (y, por tanto, lo que el driver
*hace* con ella: 110 grupos / 71 CB frente a 24/22). **[INFERENCIA]** la hipótesis "la forma del nodo
wedgea" (ronda 39 §1 del hermano, `REVISTA-PROYECTO-HERMANO.md:292`) **queda refutada como mecanismo
genérico**; y por eso A′ no "limpia el nodo", solo corrige la ventana — el único delta con lector.

### 3.2 Mecanismos candidatos, rankeados, y qué los falsaría

**H1 · El CB base calculado por el driver cae FUERA de la región mapeada (rama IDR1=7).** (§1.3)
- Evidencia a favor: seis líneas de código; el wedge es **en el arranque temprano** (el probe es
  `device_initcall`); **mudo por construcción** (sin consola ni pstore: un oops a la tarea init);
  el aviso de `:1854` es exactamente el tipo de línea que el proyecto ya sabe leer.
- Evidencia en contra / límite: **no se sabe qué reporta el silicio**; si reporta 6, el `reg` del vendor
  era correcto y H1 es falsa. (mainline declara 1 MB para `sm8550.dtsi:5547` — el mismo SoC base — lo que
  sugiere que en esa familia el hardware reporta 6; pero `cliffs` es SM7675 y **no está medido**.)
- Discriminador: el aviso `SMMU address space size (…) differs from mapped region size (…)!` en consola/
  `dmesg` y, sobre todo, si A′ arranca y da `card0`.
- **Fixable por DT (A′)**: sí, y es lo único que A′ cambia respecto a `s251`.

**H2 · Acceso a un registro *decodificado* que la plataforma/firmware no tolera (stall de bus).**
- El comentario del propio driver lo admite: `arm-smmu-impl.c:114-118` *"— And we just hope that Secure
  has also cleared SACR.CACHE_LOCK for this to take effect…"*, y ahí mismo están los 71 RMW de `CB_ACTLR`
  de la errata (`:131-143`), que con `CONFIG_ARM_SMMU_MMU_500_CPRE_ERRATA=y` (medido en los dos `.config`)
  son la mayor superficie de MMIO del probe. El proyecto ya tiene medido ese patrón para RMW a MMIO no
  decodificado: "stall de bus sin panic, sin pstore" (ledger #251 del hermano).
- A favor de que NO sea esta: `kgsl-smmu` ejecuta `arm_mmu500_reset` **también** (`qcom_adreno_smmu_500_impl`
  tiene `.reset = arm_mmu500_reset`, `arm-smmu-qcom.c:690`) y no wedgea — pero solo 22 CB, y **no** pasa por
  `qcom_smmu_cfg_probe` (el impl adreno no lo declara), así que hay dos deltas.
- Discriminador: la escalera de pokes (A′2) sobre el probe instrumentado; sin eso, indistinguible de H1.
- **NO fixable por DT.**

**H3 · Estado de hardware (clocks/power/TBU halt) que el bootloader deja de una forma para Android.**
- En contra: el ABL es el MISMO binario para los dos kernels y no sabe cuál carga **[INFERENCIA fuerte]**;
  y en Android el `arm_smmu.ko` lee esos mismos registros a los 0,41 s
  (`criticas/ufs-referencia-android/dmesg-android.txt:1337` carga del módulo; `:1733-1743` bind con
  `110 register groups` / `71 context banks` / `Adding to iommu group 0` del UFS) — es decir, el bloque
  responde con el estado que deja el bootloader.
- Nota: el nodo vendor **no tiene `clocks`** y mainline tampoco se los pide; `arm-smmu.c:2229-2238` los
  acepta vacíos.
- Discriminador: que la escalera de pokes muera en el **primer** acceso (si muere en uno concreto, sube H2).
- **NO fixable por DT.**

**H4 · El reset destruye los SMRs del bootloader (31, cuatro de ellos fuera del DT) y/o cambia a BYPASS
streams vivos.**
- `arm_smmu_device_reset` (`arm-smmu.c:1661-1721`) escribe SMR/S2CR ×110 (todos a invalid/BYPASS vía
  `arm_smmu_write_sme`) y `rmr_install_bypass_smr` (`:2073-2119`) pone `CLIENTPD` (desactiva la traducción)
  al principio. El vendor tiene `qcom,handoff-smrs = <0x1c00 0x02>` para *restaurarlos*; mainline **no lee
  esa propiedad** (0 lectores, §2.3).
- A favor: es la hipótesis que el propio banner del `s251` dejó abierta, y encaja con un wedge temprano.
- En contra: un maestro perdiendo su SMR normalmente produce *faults* (visibles en `GFSR`), no un cuelgue
  del APSS.
- **NO fixable por DT.**

**H5 · Mecánica del dtbo/ABL** (phandle literal colado, payload drift, msm-id del payload que no matchea).
**DESCARTADA**: el `s238` comparte payload y mecánica y está booteando; y los gates G7/G7b de A′ exigen
"diff de exactamente 3 propiedades" y "`__symbols__`/`__fixups__`/`__local_fixups__` + props de raíz
byte-idénticas al s238". **[DATO]** el payload del stock declara `qcom,msm-id = <0x282 … 0x278 … 0x283 …
0x266 …>` y `qcom,board-id = <0x08 0x00>` (`/tmp/s253recon/s238-payload.dts:9-10`), o sea que **cubre
0x283**.

**H6 · La forma del nodo** (2 `reg` + TBU + extras). **DESCARTADA** como mecanismo (§3.1 + §2.3).

### 3.3 Lo que NO se puede concluir offline, y por qué los ciclos anteriores están confundidos

- **`s251` en el slot b con el kernel bueno (11:52-12:03) es la única medida limpia "solo-dtbo"**: mismo
  `boot_b`, se cambia solo `dtbo_b`; 4 min mudos; `slot-retry-count:b 7→0`; rollback a `s238` y vuelve
  (`build/bootimg/mkdtbo-s251.py:9-17`). **El dtbo `s251` wedgea, eso es DATO.**
- Los **otros tres** mudos de omarchy-uke fueron `boot-pokes` **+** `s251` a la vez, y el cuarto fue
  `boot-pokes` **+** `s238` **bueno**: el común es **una imagen de `boot` nueva en el slot a**
  (`build/gates/PRE-REGISTRO-F5-B1.md:1137-1152`). **NO VERIFICADO** ese mecanismo; no es del SMMU.
- En el hermano, al menos el #431 ("`boot s244-bounce` + `dtbo s241`", 26-sep 18:58) también cambió
  **boot y dtbo a la vez** (`docs/ESTADO-ACTUAL.md`, sección (B)). Es decir: de los "6 wedgeos" del
  hermano, no todos están limpios. **[INFERENCIA]** el "6/6" es más débil como medida de lo que parece.
- Por tanto: la interpretación correcta hoy es **"`s251` (compatible solo) wedgeó en la única medida
  limpia que hay; el porqué está entre H1/H2/H4 y solo lo decide medir"**. A′ es el intento de arreglar
  H1 sin gastar el ciclo de pokes.

---

## 4. Diseño exacto de A′

### 4.1 El fragmento (literal, el que va dentro del payload)

```dts
	fragment@s253 {
		target-path = "/soc/apps-smmu@15000000";
		__overlay__ {
			compatible = "qcom,sm8550-smmu-500", "qcom,smmu-500", "arm,mmu-500";
			reg = <0x15000000 0x200000>;
			reg-names = "base";
		};
	};
```

Y el diff semántico COMPLETO contra el `s238` (la tablet ahora), medido por el gate G7 sobre el árbol
*fusionado* (`build/gates/s253-GATES.log`):

```diff
-			compatible = "qcom,qsmmu-v500";
-			reg = <0x15000000 0x100000 0x151fe000 0x40>;
-			reg-names = "base", "tcu-base";
+			compatible = "qcom,sm8550-smmu-500", "qcom,smmu-500", "arm,mmu-500";
+			reg = <0x15000000 0x200000>;
+			reg-names = "base";
```

### 4.2 Por qué es esto y no otra cosa

1. **`compatible`**: es el único camino para que `arm_smmu_of_match` binde (§1.2). El triple es el de
   mainline para sm8550 (`sm8550.dtsi:5546`). `qcom,smmu-500` es necesario para que el impl qcom (y con
   él el `def_domain_type` IDENTITY del parche UKE) entre; `arm,mmu-500` es el que **binde**.
2. **`reg` de 2 MB, una sola región**: es el arreglo de §1.3. Se elige **2 MB** y no otra cifra porque
   - cubre la rama mala (`size=0x100000` → CB 0x15100000..0x15147000) **y** la buena;
   - está dentro de lo que el propio vendor declara para este SMMU: su `reg[1]` (`0x151fe000+0x40`) está
     *dentro* de esos 2 MB **[DATO: stock-fdt2.dts:13182]**, así que la ventana no invade nada ajeno;
   - gate G3c lo verifica sobre el árbol fusionado: **ningún otro nodo reclama nada de
     `[0x15100000,0x15200000)`**;
   - y no mueve ni un acceso en la rama buena (mismo CB base, un ioremap más grande y un aviso del driver).
3. **`reg-names = "base"`** (en vez de dejarlo con dos nombres y una sola región): coherencia; nadie lee
   `reg-names` en este árbol (`grep` de G4: `tcu-base` → **0 apariciones en TODO el árbol**). Se
   **elimina** la segunda región del vendor **a propósito**: no tiene lector, está dentro de la nueva, y
   así "la segunda `reg` no mapeada" deja de existir por construcción.
4. **Lo que A′ NO toca, y por qué** (para que el siguiente lector no lo tome por un olvido): los 8 hijos
   TBU, `qcom,actlr`, `qcom,handoff-smrs`, `qcom,use-3-lvl-tables`, `ranges`, `#address/#size-cells`, la
   lista de 97 IRQs, `dma-coherent`, `phandle <0x129>`. **Todos inertes** con la evidencia de §2.3, y
   tocarlos sin un mecanismo que los lea sería "jugar a adivinar" (misma regla que aplicó el `s238` con
   los gpio compartidos). El gate G3.0 exige además que **no aparezca ni una propiedad nueva** en el nodo
   (eso caza cualquier `iommus`/`phandle` literal colado).

### 4.3 Diferencia concreta con lo wedgeado

| | arreglo A del hermano (`s223`/`s231`/`s241`) | `s251` (nuestro, wedgeado) | **A′ (`s253`)** |
|---|---|---|---|
| compatible mainline | sí | sí (mismo triple) | sí (mismo triple) |
| **`reg` / ventana** | se queda 1 MB | se queda 1 MB | **2 MB, 1 región** |
| iommus de 57 maestros | vaciados en s223/s241 | intactos | intactos (no hace falta: IDENTITY) |
| estado | WEDGE (con boot nuevo a la vez, #431) | WEDGE (medida limpia, slot b) | **SIN FLASHEAR** |

---

## 5. Gates del constructor (`build/bootimg/mkdtbo-s253.py` → `build/gates/s253-GATES.log`)

**Estado: TODO VERDE.** Todos los gates abortan con `die()`/`GateFail` (un print no es un gate). Resumen
con la línea del log:

| gate | qué exige | estado |
|---|---|---|
| G0 | `s238 = bdb361df…`, `base-dtb.img = 3f973c78…`, `s251 = 78eb2645…` (control), dtc/fdtoverlay, árbol presente | OK |
| G1 | UN `target-path` (apps-smmu), **3 props** (compatible/reg/reg-names), **sin `&`**, sin `__fixups__`, sin DPU/panel/PHY/watchdog/regulador | OK |
| G2 | `fdtoverlay` contra el DT base **REAL**; `compatible` exacto (igualdad, no subcadena); `reg` exacto; `reg-names` exacto; `status="ok"` | OK |
| G3 | **forma vs vendor**: ni una propiedad nueva ni perdida (80 props); **8 hijos TBU intactos**; extras del vendor intactos; 97 IRQs/1 global; `#iommu-cells=2`; `dma-coherent`; `phandle <0x129>` y el `iommus` del mdss resolviéndolo; la región nueva **contiene** las dos del vendor | OK |
| G3b | **LA VENTANA**: los 71 CB caben en `reg[0]` en las **dos** ramas de IDR1 (`0x80000` y `0x100000`) — con el desglose numérico impreso | OK |
| G3c | ningún otro nodo del fusionado reclama `[0x15100000,0x15200000)` | OK |
| G4 | contraste contra el **código**: `arm,mmu-500` en `of_match`; las 6 líneas de la ventana presentes; `qcom,smmu-500`→`impl0_data`→`qcom_smmu_500_impl` con `def_domain_type`; parche UKE del WLAN; **0 lectores** de `qcom,actlr`/`handoff-smrs`/`use-3-lvl-tables`/`qsmmuv500-tbu`/`qtb500`/`tcu-base`; `qcom_smmu_tbu_of_match` = {sc7280-tbu, sdm845-tbu} | OK |
| G5 | superficie de wedge de los `.config`: `CPRE_ERRATA=y` (avisa en mayúsculas), `QCOM_DEBUG=n`, `ARM_SMMU=y` | OK (con 2 avisos) |
| G6 | el DPU (`iommus = <0x129 0x1c00 0x02>`) y el resto, intactos; sin `separate_gpu_kms` | OK |
| G7 | diff semántico vs `s238` = **exactamente 3 propiedades** (6 líneas), las 3 esperadas, cada una en par −/+ | OK |
| G7b | el payload conserva `__symbols__`/`__fixups__`/`__local_fixups__` y las props de raíz (`qcom,msm-id`, `qcom,board-id`, `qcom,pmic-id`, `compatible`, `model`, `xiaomi,miboard-id`) **idénticas al s238** ⇒ **ni una referencia nueva, ni un phandle** | OK |
| G8 | `dt_table` coherente (magic, total_size, dt_size, dt_offset), roundtrip byte a byte del payload, cabe en `dtbo_b` | OK (607 714 B, margen 2 590 B) |
| G9 | **autoprobado**: `s238` y `s251` RECHAZADOS por los mismos gates (ver abajo) + 5 mutaciones | OK |
| G10 | publicación + sha releída del fichero | OK |

**Controles negativos (el corazón de G9)** — línea del log:

```
OK  s238 RECHAZADO por forma: compatible = "qcom,qsmmu-v500" (se esperaba exactamente …) + VENTANA: reg no es 1 region de 2 celdas
OK  s251 RECHAZADO por forma: reg = <0x15000000 0x100000 0x151fe000 0x40> (…) + VENTANA: reg no es 1 region de 2 celdas
OK  control unitario: con 1 MB el gate de la ventana SI salta (es el bug del s251)
       (rama size=0x100000 -> CB base=0x15100000 .. 0x15147000  FUERA de 0x15100000)
OK  'ventana 1 MB otra vez (el s251 en forma A′)'          -> RECHAZADA
OK  'reg-names incoherente (2 nombres, 1 region)'          -> RECHAZADA
OK  'phandle literal añadido (iommus colgante)'           -> RECHAZADA (extra=['iommus'])
OK  'status disabled'                                      -> RECHAZADA
OK  'sin arm,mmu-500 (compatible inerte)'                  -> RECHAZADA
```

Nota metodológica: el gate de la ventana (G3b) **tuvo que corregirse dos veces** durante la construcción
(primero calculaba la segunda rama a partir del tamaño declarado, con lo que un `reg` de 1 MB se
auto-justificaba; lo cazó el control unitario). Es exactamente el tipo de fallo que este proyecto ya tiene
documentado: un gate que muere por la razón equivocada es peor que no tenerlo.

### 5.1 Artefacto

| campo | valor |
|---|---|
| fichero | `build/bootimg/s253-boot-dtbo-aprima.img` |
| **sha256** | **`eeb57d95a5454afdfc4312264a84a612ab2fa67d29eb1c98fa3754a82765a4e1`** |
| tamaño | 607 714 B (`dtbo_b` admite 610 304 ⇒ margen 2 590 B) |
| base | `s238` (`bdb361df…`) + `base-dtb.img` (`3f973c78…`), ambas re-verificadas por sha en G0 |
| destino previsto | **`dtbo_b` SOLO** (`boot_b`, `userdata`, `vendor_boot_b`, `vbmeta`, `misc` no se tocan) |
| rollback | `dtbo_b ← s238-boot-dtbo-dedup-gpio.img` (`bdb361df…`), probado en la tablet |
| estado | **PREPARADO, SIN FLASHEAR** (no se ha ejecutado nada contra la tablet) |

---

## 6. Árbol de decisión de consola para el ciclo de flash

Antes de nada: `sha256sum` del `.img` = el de arriba; `dtbo_b` accesible; **un solo lector** de
`/dev/ttyACM0` (`build/gates/REGLA-UN-SOLO-LECTOR.md`); el par bueno del otro slot intacto; `dmesg -n 7`
antes de disparar (los `dev_notice` del SMMU son KERN_NOTICE).

**(1) ÉXITO COMPLETO** — la cadena progresa:
```
arm-smmu 15000000.apps-smmu: probing hardware configuration...
arm-smmu 15000000.apps-smmu:  SMMUv2 with:
arm-smmu 15000000.apps-smmu:   stream matching with 110 register groups
arm-smmu 15000000.apps-smmu:   71 context banks (0 stage-2 only)
...: Adding to iommu group N          <- el mdss/DPU (en Android: dmesg-android.txt:1743)
[msm_dpu]: NO aparece "no IOMMU, bailing out" / ni "dpu_kms_mmu_init failed: -19"
/dev/dri/card0  + panel
```
→ H1 era cierta **y** A′ arregló el wedge. Siguiente paso: display, no SMMU.

**(2) SMMU VIVO, DPU NO** — bindea y falla el grupo del display:
```
... (líneas de arriba hasta "71 context banks") ...
...: stream ID 0x1c00 out of range for SMMU (0x…)      <- arm-smmu.c:1462
...: SMR mask 0x2 out of range for SMMU (0x…)          <- arm-smmu.c:1467
[msm_dpu]: no IOMMU, bailing out                        <- sigue el -19
```
→ el SMMU está sano pero el master del display no entra. Es un **resultado nuevo y bueno** (el bloqueo se
movió): mirar `#iommu-cells`, el `iommus` del mdss y `test_smr_masks`. No es un wedge.

**(3) EL DISCRIMINADOR DE A′** — buscar en `dmesg`:
```
SMMU address space size (0x…) differs from mapped region size (0x…)      <- arm-smmu.c:1855
```
- **Aparece** con `(0x100000)` y `(0x200000)` ⇒ el hardware reporta `NUMPAGENDXB=7`; el `reg` de 1 MB
  calculaba el CB base **fuera del mapeo** y **H1 era la causa del wedge del `s251`**. A′ lo arregla.
- **No aparece** ⇒ el hardware reporta `size=0x80000`: **H1 queda refutada**, el `reg` del `s251` ya era
  correcto y A′ equivale a `s251` (solo cambia el ioremap). Entonces la causa es H2/H4 y **ningún dtbo la
  arregla**: cerrar el espacio dtbo y pasar al kernel de pokes (A′2), que es el único que nombra el acceso
  fatal.

**(4) WEDGE MUDO** (cero líneas, ~4 min sin gadget, `slot-retry-count` cayendo, fastboot):
```
(nada)
```
→ rollback inmediato: `fastboot flash dtbo_b s238-boot-dtbo-dedup-gpio.img` (`bdb361df…`) + reboot.
**No reintentar**: sin pokes, un wedge mudo no da dato. (Si el aviso de (3) hubiera salido, se habría
perdido: sin consola no se ve. Por eso el ciclo siguiente tiene que llevar el kernel de pokes.)

**(5) WEDGE CON COLA** — el probe muere en un acceso MMIO concreto:
```
arm-smmu 15000000.apps-smmu: probing hardware configuration...   <- y SILENCIO después
```
→ copiar literal **la última línea antes del silencio**: las migas de `arm_smmu_device_cfg_probe` /
`qcom_smmu_cfg_probe` / `arm_mmu500_reset` / `arm_smmu_device_reset` localizan el registro. Otras líneas
con lectura propia:
- `Failed to disable prefetcher for errata workarounds, check SACR.CACHE_LOCK`
  (`arm-smmu-impl.c:143`) ⇒ los RMW de `CB_ACTLR` no prenden; apunta a H2/TZ.
- `impossible number of S2 context banks!` (`arm-smmu.c:1864`) o
  `found only N context irq(s) but 71 required` ⇒ fallo **limpio** (`-ENODEV`): el DPU sigue con `-19`,
  la tablet arranca. No es wedge.
- `Limiting the stream matching groups to 128` (`arm-smmu-qcom.c:511`) ⇒ se activó el quirk de bypass;
  funcional, pero se reservó el último CB. Vigilarlo.

**Coste y red**: 1 reintento del slot b (destino `dtbo_b`), `boot_b` intacto; rollback = flash de `s238`.
Presupuesto: techo de 3 intentos de esta hipótesis (mismo criterio que el `s251`).

---

## 7. Riesgos residuales (lo que puede salir mal y por qué)

1. **H1 es falsa (el silicio reporta 6)**: A′ wedgea igual que `s251`. *Mitigación*: es el caso que el
   árbol de decisión §6(3) convierte en información (el aviso ausente) y el techo de intentos.
2. **H2/H4 (acceso intolerable / SMRs del bootloader)**: ningún dtbo puede evitarlo. *Mitigación*: el
   ciclo de pokes ya está preparado en el otro carril; no gastar más flashes de dtbo si el aviso de (3)
   no aparece.
3. **`CPRE_ERRATA=y`** ⇒ 71 RMW de `CB_ACTLR` en el reset (máxima superficie de MMIO). *Mitigación*:
   ninguna desde el DT; es la razón de que el criterio de fallo sea "wedge ⇒ no reintentar".
4. **Riesgo de la propia ventana de 2 MB**: podría chocar con un consumidor de `[0x15100000,0x15200000)`
   (daría `-EBUSY` limpio, no wedge). *Mitigación*: gate G3c lo comprueba sobre el árbol fusionado.
5. **Riesgo de mecánica del dtbo** (referencias colgantes, payload alterado): *Mitigación*: G1 (sin `&`),
   G3.0 (ni una propiedad nueva), G7 (diff de 3 propiedades), G7b (payload y tablas idénticas al `s238`),
   G9 (5 mutaciones + los dos artefactos históricos rechazados).
6. **La confusión del "boot nuevo en slot a"** sigue sin nombre en este proyecto. *Mitigación*: A′ va a
   **`dtbo_b` solo**, con el `boot_b` bueno sin tocar (ni repack, ni pokes) — un cambio, una variable.

## 8. Anexo — reproducción

```bash
# descompilar los 4 DTB stock y ver el msm-id de cada uno (§2.1)
for f in 0 1 2 3; do dtc -I dtb -O dts -o /tmp/stockf$f.dts ~/gpu-work/stock-dtbs/stock-fdt$f.dtb; done
grep -m1 msm-id /tmp/stockf{0,1,2,3}.dts

# descompilar el nodo vivo del vendor: /tmp/stockf2.dts:13160-13265   (apps-smmu@15000000)

# construir A′ y ejecutar TODOS sus gates (escribe el .img y el log lo recoge la invocación)
python3 ~/proyectos/omarchy-uke/build/bootimg/mkdtbo-s253.py
#   -> build/bootimg/s253-boot-dtbo-aprima.img
#      sha256 eeb57d95a5454afdfc4312264a84a612ab2fa67d29eb1c98fa3754a82765a4e1   (607714 B)
#   -> log de esta sesión: build/gates/s253-GATES.log
```

Relacionados (mismo ciclo, otros carriles): `build/bootimg/mkdtbo-s251.py` (el artefacto wedgeado, con su
banner de REFUTADO y la medida de las 11:52-12:03), `build/gates/PRE-REGISTRO-F5-B1.md` (§s251 y el
aislamiento), `build/gates/EVIDENCIA-PANTALLA-28sep.md` (evidencia viva del otro subagente),
`~/proyectos/ubuntu-permanente/criticas/ronda-36/gpu-a-prima-apps-smmu.md` (informe A′ base del hermano),
`~/proyectos/ubuntu-permanente/criticas/ufs-referencia-android/dmesg-android.txt` (referencia dorada).
