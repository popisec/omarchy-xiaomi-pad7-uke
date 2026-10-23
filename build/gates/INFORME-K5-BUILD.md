# INFORME-K5-BUILD — kernel K5: instrumentación y control de la fase de ATTACH

Fecha: 2026-09-29 (madrugada). Autor: SG-K5.
Punto de partida: **K1+K2+K3+K4** ya aplicados en `/var/tmp/uke-k1` (árbol) y `/var/tmp/uke-k1-build` (`O=`).
Contexto medido (#P11, trail `build/gates/k4c-consola-trail.txt`, segmento boot_index 5462):
con `uke_keep_boot=1` el probe real del apps-smmu **completa el reset entero** (fase2 omitida, fase3
CBAR/SCTLR/FSR ×71, fase4 TLBI, fase6 `arm_mmu500_reset`, fase7 sCR0, `test_smr_masks` omitido) y la
consola enmudece **inmediatamente después** (`[39.212930] test_smr_masks OMITIDO` es la última línea;
el segmento siguiente es el arranque boot_index 5463). Justo detrás del reset viene
`iommu_device_register()` → `bus_iommu_probe()`: la **tormenta de attach** (un `probe_device` por cada
maestro con `iommus`, ~58 devices en el DT). **Ninguna** miga de attach de K4 llegó a imprimir.

Objetivo de K5: (a) migas por maestro **flush-eadas a consola ANTES** de cada escritura, para que la
primera línea impresa identifique sin ambigüedad el maestro/índice que mata; (b) dos palancas para
**no tocar los índices vivos del bootloader** durante el attach (`uke_attach_log=2` preserva;
`uke_protect_smr0=1` reubica); (c) cerrar la laguna de medición del S2CR(0) real del bootloader
(lectura) y corregir la decodificación del MASK que K3/K4 imprimían mal.

> Recordatorio operativo: aquí **NO** se ha tocado la tablet (ni adb, ni fastboot, ni ssh). En
> `omarchy-uke` solo hay ficheros **NUEVOS** sin commitear. `~/gpu-work` solo lectura. Todos los
> cambios viven en `/var/tmp/uke-k1`, `/var/tmp/uke-k1-build` y `/var/tmp/uke-k5`.

---

## 0. Entregables y shas

| fichero | bytes | sha256 |
|---|---|---|
| `build/bootimg/boot-ukek5.img` | 100663296 (96 MiB exactos) | `520940ab4ee6f0373c2fd776111b0e2ce63a40014fba271f3260dc3a0f8e18e5` |
| `build/gates/patches/k5-attach.diff` | 20588 B, 470 líneas, 10 hunks, 2 ficheros, +381/−6 (383/8 con cabeceras) | `0623d0ca4f6006b6f61f53d25b231e8c0b37e861ed7de95a648eb351403ec6b3` |
| kernel fuente del empaquetado (`Image.gz`) | 16564346 (K4: 16565056, **−710 B**) | `274e452ac3b95c8de7d9a7d3c121dd7c21f8aacf303fb89d29aa45feb88444a4` |
| kernel desempaquetado (`Image`) | 41355776 = 39,44 MiB (**delta 0** vs K1-K4) | `49bfd30a968aa0bf035baaea9a62cd180d876b7dad7c774788b78ff3028dae5a` |
| `arm-smmu.c` de K5 (K1+K2+K3+K4+K5) | 108332 B | `f52b34a380db2ee177058b542526caa3a0e9767024dec7e0350e260b44ef7043` |
| `arm-smmu-qcom.c` de K5 (K1+K3+K4+K5) | 35126 B | `3ed87c75b708798027aa7b6c8e40441e47178e5cdca5d2e132a6688e6af55974` |

```
$ git status --short        # solo ficheros NUEVOS, sin commit (build/pkg/panel-o82/ es de otro agente)
?? build/gates/patches/k5-attach.diff
?? build/pkg/panel-o82/
$ git check-ignore -v build/bootimg/boot-ukek5.img
.gitignore:25:build/bootimg/*.img	build/bootimg/boot-ukek5.img
```

K5 **no cambia nada de K4** (todos los params y migas de K1-K4 siguen con la misma semántica); solo
añade el bloque K5 (params nuevos + migas + preservación) y corrige la decodificación del MASK.

---

## 1. El camino exacto entre `test_smr_masks` y el primer `arm_smmu_probe_device`

Citas por línea del árbol K5 (`/var/tmp/uke-k1/drivers/iommu/arm/arm-smmu/arm-smmu.c` y
`/var/tmp/uke-k1/drivers/iommu/iommu.c`).

| # | sitio | qué pasa | ¿MMIO? |
|---|---|---|---|
| 1 | `arm-smmu.c:3074` `uke_dump_bl_state(smmu)` | **K5**: lectura de SMR(0)/S2CR(0) y de cada idx BL-válido (solo con `uke_attach_log>=1`) | 2-4 R (lecturas) |
| 2 | `arm-smmu.c:3077-3078` `arm_smmu_device_reset()` + `arm_smmu_test_smr_masks()` | ya medidos en K4 (fase2 omitida con keep_boot; test omitido) | reset |
| 3 | `arm-smmu.c:3080` `iommu_device_sysfs_add()` | crea `/sys/.../iommu` | no |
| 4 | `arm-smmu.c:3085` `iommu_device_register(&smmu->iommu, &arm_smmu_ops, dev)` | **entra en el core** | no |
| 5 | `iommu.c:289-307` `iommu_device_register()` | añade el iommu a `iommu_device_list` y recorre `iommu_buses[]` → `bus_iommu_probe(platform_bus)` (línea 307) | no |
| 6 | `iommu.c:1954-1957` `bus_iommu_probe()` | `bus_for_each_dev(bus, NULL, &group_list, probe_iommu_group)` — **aquí empieza la tormenta** | no |
| 7 | `iommu.c:1801-1806` `probe_iommu_group()` | por device: `__iommu_probe_device(dev, group_list)` (línea 1806) | no |
| 8 | `iommu.c:627-660` `__iommu_probe_device()` | si el device ya está en un grupo → return; si no, `iommu_init_device(dev)` (línea 661) | no |
| 9 | `iommu.c:469-508` `iommu_init_device()` | `dev_iommu_get`; si `!fwspec && !driver && dma_configure` llama `dma_configure` (solo **parsea** la fwspec vía `of_xlate`; sin MMIO) y luego `ops->probe_device(dev)` (línea 508) | no |
| 10 | `arm-smmu.c:2086` `arm_smmu_probe_device()` | `arm_smmu_get_by_fwnode` (RAM), validación sid/mask (2109-2122), `kzalloc` cfg, `arm_smmu_rpm_get` (sin pm_runtime → 0), `arm_smmu_master_alloc_smes(dev)` (2140) | no |
| 11 | `arm-smmu.c:1582` `arm_smmu_master_alloc_smes()` | **1er bucle** (1601-1675): `find_sme` (1528: **RAM pura**, recorre `smmu->smrs[]`), miga K4 1620, detección BL K5 1637-1649 | no |
| 12 | `arm-smmu.c:1677` **2º bucle** «It worked! Now, poke the actual hardware» | miga K5 «ESCRIBIR SME …» (1703) + `pr_flush` (1726) → `arm_smmu_write_sme(smmu, idx)` (1729) | **W** |
| 13 | `arm-smmu.c:1439` `arm_smmu_write_sme()` | miga K4 (1443-1458) y después `arm_smmu_write_s2cr` (1460) y `arm_smmu_write_smr` (1462) | **W** |
| 14 | `iommu.c:1964-1980` (final de `bus_iommu_probe`) | por cada grupo de la lista: `iommu_setup_default_domain(group, 0)` (1977) → `arm_smmu_attach_dev*` (1820/…) → `arm_smmu_master_install_s2crs` (1759) + `write_context_bank` | **W** |

**Conclusión (la pregunta del encargo):** entre el `return` de `test_smr_masks` y el primer
`arm_smmu_write_sme` **no hay ni un solo acceso MMIO en todo el camino**: `find_sme` es RAM pura
(`arm-smmu.c:1528-1568`), `of_xlate` es parseo de DT, `device_group`/`iommu_device_link` son
sysfs/RAM. Los únicos accesos de la fase son `write_sme` (S2CR+SMR), `install_s2crs` (S2CR) y
`write_context_bank` (CBAR/TCR/TTBR/SCTLR del CB del dominio). Y **las tres funciones tienen su miga
ANTES del acceso** (K4/K5). Por tanto el silencio de K4 **no** puede ser «murió en un acceso no
instrumentado»:

* la miga de `find_sme` de K4 (`1620`) va **después** de la llamada, pero la llamada no toca el HW:
  no puede matar;
* la miga de `write_sme` de K4 (`1443-1458`) va **antes** de las dos escrituras;
* luego el acceso letal es, con toda probabilidad, **el primer `write_sme`** (idx 0, ver §2) y su
  miga quedó en el ring buffer **sin llegar a `ttyGS0`**: los freeze medidos (K2, K3) congelan la
  máquina entera, y el hilo de consola no tuvo tiempo de vaciar la línea antes del cuelgue. El
  freeze impide además cualquier miga posterior (no hay panic; el watchdog reinicia: 5462→5463).

**Corrección de orden que aplica K5:** miga + `pr_flush(500, false)` **inmediatamente antes** de
cada acceso candidato (`arm-smmu.c:1726` antes de `write_sme`; `1036` antes del primer acceso de
`write_context_bank`; `1815` antes de `arm_smmu_write_s2cr` de `install_s2crs`; `503` tras el
volcado BL). Con `uke_attach_log>=1` la última línea que llegue al cable es el punto de muerte real.

---

## 2. Dos correcciones de medición (y la hipótesis nº1 de #P11, refutada)

### 2.1 `SMR(0)` no tenía `mask=0x8000`: su mask real es **0x0000**

La miga del barrido (K3/K4) decodificaba `mask = FIELD_GET(ARM_SMMU_SMR_MASK, smr)` con
`ARM_SMMU_SMR_MASK = GENMASK(31,16)` (`arm-smmu.h:102`). El campo real del SMR es **30:16**; el bit
31 es `VALID` (`arm-smmu.h:101`) y FIELD_GET lo colaba dentro del valor extraído. El propio mainline
lo sabe y limpia el bit antes de extraer (`arm-smmu-qcom.c:607`, «Ignore valid bit for SMR mask
extraction»). `SMR(0)=0x80000060` es por tanto:

```
bit31 VALID = 1
bits30:16 MASK = 0x0000      <-- NO 0x8000 (eran los 5 bits altos del nibble VALID)
bits15:0  ID   = 0x0060
```

K5 corrige la decodificación en la miga del barrido (`arm-smmu-qcom.c:598-610`, ahora imprime
`[mask sin el bit VALID]`) y en el volcado BL (`uke_smr_mask_leido`, `arm-smmu.c:460`).

### 2.2 El índice 0 lo reutiliza **ufshc (sid 0x60)**, no el mdss (sid 0x1c00)

Aritmética de `arm_smmu_find_sme` (`arm-smmu.c:1528-1568`) contra `smrs[0]={id=0x60, mask=0x0000, valid=1}`:

* **ufshc** (`iommus = <&apps_smmu 0x60 0x00>`): `(mask & 0) == mask` → `0==0` ✔ y
  `!((0x60 ^ 0x60) & ~0)` ✔ → **devuelve 0** (reutiliza el índice del BL).
* **mdss** (`iommus = <&apps_smmu 0x1c00 0x02>`): `(0x02 & 0x0000)=0 ≠ 0x02` (no «entirely matched»)
  y `((0x1c00 ^ 0x60) & ~(0x0000|0x02)) = 0x1c60 & 0xfffd ≠ 0` (sin solape) → **primer hueco
  libre** (1 si nadie lo ocupó antes). El mdss **no** toca el índice 0.

La hipótesis «mask 0x8000 cubre el rango 0x0060..0x8060, incluido 0x1c00» era doblemente falsa:
el mask real es 0 (casa solo con 0x0060), y con mask=0x8000 el rango sería {0x0060, 0x8060}, nunca
0x1c00. El maestro del índice vivo es **`ufshc@1d84000`** (`stockuke.dts:12589`; phandle 0x129 =
`apps_smmu`, `stockuke.dts:13195`) — **el UFS del que cuelga el rootfs**. Dato extra: el DT vendor
declara `qcom,handoff-smrs = <0x1c00 0x02>` (el mdss), que **no** es el mapeo que el BL dejó vivo
en SMR(0) (ufshc); el handoff declarado y el handoff real no coinciden.

Lista completa de maestros con `iommus` al apps-smmu (69 entradas → 58 devices): **anexo A**.

### 2.3 La laguna `s2crs[]` (y cómo la cierra K5 a medias)

`qcom_smmu_cfg_probe` (`arm-smmu-qcom.c:486`) puebla `s2crs[i] = {type=BYPASS, cbndx=0xff}`
(líneas 617-620) para cada `smrs[i].valid` **sin leer nunca el S2CR real del HW**. Con
`uke_keep_boot=1` la RAM (s2crs[0]) no refleja el S2CR(0) del bootloader: no se sabía si el BL dejó
UFS en BYPASS (pasa directo), en TRANS a un CB con tablas propias, o en FAULT. K5 lo **lee** (lectura;
SMR(0) ya se leyó en K3/K4 y S2CR(109) se escribió+leyó en K2/K3) en `uke_dump_bl_state`
(`arm-smmu.c:470-504`, miga en 480) y en la miga pre-write del idx 0 (`arm-smmu.c:1714-1722`, miga
«idx=0 AHORA en HW»). Solo se leen idx 0 y los índices que la RAM marca BL-válidos: un índice
arbitrario de SMR **no** está medido como seguro (K2 murió dentro del barrido completo de lecturas).

---

## 3. Los dos parámetros nuevos

### 3.1 `uke_attach_log` (int, 0644, default **0**) — `arm-smmu.c:364-382`

| valor | qué hace |
|---|---|
| 0 | silencio (comportamiento K4: solo las migas K1-K4) |
| 1 | (a) **volcado BL** antes del reset (`uke_dump_bl_state`): SMR(0)/S2CR(0) reales + cada idx BL-válido; (b) por **cada maestro** y **antes** de `write_sme`: miga `ESCRIBIR SME idx=… dev=… -> SMR=0x… (id/mask/valid) | S2CR nominal=0x… (type/cbndx) [impl->write_s2cr: quirk qcom reescribe]`; si `idx==0`, además `idx=0 AHORA en HW: SMR(0)=… S2CR(0)=…`; (c) `pr_flush(500)` tras cada miga → **la línea está en el cable antes del acceso** |
| 2 | además, si `find_sme` devuelve un índice que la RAM conoce como vivo del BL (`smrs[idx].valid && s2crs[idx].count==0`), el SME **no se escribe**: ni SMR ni S2CR en `write_sme` (miga `SME idx=%d PRESERVADO (BL vivo)`), ni el S2CR del attach de dominio en `install_s2crs` (`arm-smmu.c:1778`) — el maestro queda con el mapeo del BL. El attach sigue (grupo/dominio en RAM). |

Detalle de la detección: `uke_sme_es_bl` (`arm-smmu.c:413`) exige `valid && count==0`, o sea que el
barrido lo marcó (lo puso el BL) y **ningún maestro lo ha reclamado todavía**; los índices ya
preservados se recuerdan en `uke_preservados_bl` (`arm-smmu.c:410`) para que un segundo maestro que
case el mismo SID no vuelva a escribir el índice vivo. Requiere el barrido (`uke_smr_max>=0`);
con `uke_smr_max=-2` (barrido saltado) K5 no conoce ningún índice vivo.

### 3.2 `uke_protect_smr0` (bool, 0644, default **0**) — `arm-smmu.c:384-402`

Si el idx elegido es un SME vivo del BL, se busca el **primer índice libre alto** (de
`num_mapping_groups-1` hacia abajo, `!smrs[i].valid && s2crs[i].count==0`, sin tocar el 0;
`uke_sme_libre_alto`, `arm-smmu.c:421`) y el maestro se reclama/escribe **ahí**: miga
`protect_smr0: idx %d es del BL -> … se reubica en el idx libre alto %d`. SMR(0)/S2CR(0) del BL no
se tocan. Precedencia: con `uke_attach_log>=2`, **preservar gana** (no se escribe nada).

### 3.3 Qué pasa funcionalmente con cada opción (para el maestro del índice 0: ufshc/UFS)

| opción | HW de idx 0 | traducción que usa UFS | riesgo |
|---|---|---|---|
| `log=0` (K4) | `write_sme(0)`: S2CR(0)→nominal BYPASS→**quirk TRANS cbndx=70** + SMR(0) reescrito (id=0x60, mask=0, valid=1) | la que deje el CB 70 reservado (S1_TRANS_S2_BYPASS → equivale a bypass) | **el candidato a matar** (K3 murió en la 1ª escritura de SME; el SMR(0) vivo es el único registro que se reescribe) |
| `log=2` | **no se escribe nada** (ni en el attach de maestro ni en el de dominio) | la del **BL** (la que tiene ahora y le funciona): si `S2CR(0)` BL es BYPASS → directo; si es TRANS cbndx=X → tablas del BL | el core cree que el device está en dominio IDENTITY (bypass) mientras el HW usa la traducción BL: si el BL tenía TRANS, es el estado actual (UFS funcionando); si el BL tenía BYPASS, idéntico al core. El riesgo real es no saberlo hasta leer S2CR(0) (K5 lo imprime) |
| `protect_smr0=1` | se escribe en un **idx libre alto** (p.ej. 109): SMR(109)=id 0x60/mask 0 + S2CR(109)=BYPASS→**quirk TRANS cbndx=70** | ambigua: **dos SMR casan el sid 0x60** (el del BL y el nuevo). Si el HW elige el nuevo (precedencia no garantizada), UFS va a TRANS cbndx 70 (CB reservado sin tablas) y sus accesos pueden fallar | peor que `log=2` para UFS: crea un segundo mapeo en vez de no tocar nada. Es la palanca si `log=2` resulta no ser suficiente para aislar la causa |

**Recomendación de escalera: `log=1` (observar) → `log=2` (preservar) → `protect_smr0` solo como
diagnóstico alternativo.** En este aparato el índice vivo es el del UFS (rootfs), así que la opción
que menos toca es `log=2`.

### 3.4 Nota funcional del dominio por defecto (para leer bien la parte final del attach)

`qcom_smmu_def_domain_type` (`arm-smmu-qcom.c`) devuelve **IDENTITY** para todo salvo el wcn6750
(traducido). Los maestros del apps-smmu se atan por tanto a un dominio IDENTITY: el attach de
dominio (`iommu_setup_default_domain` → `arm_smmu_attach_dev_identity` → `install_s2crs(BYPASS,0)`)
escribe **S2CR=BY PASS** (el quirk lo convierte a TRANS cbndx 70: el CB reservado que el propio quirk
configuró como S1_TRANS_S2_BYPASS). No programa tablas ni IOVAs: es el "bypass emulado" del vendor.
Con `log=2`, para el idx preservado **tampoco** se escribe ese S2CR (`arm-smmu.c:1778`).

---

## 4. Empaquetado (`boot-ukek5.img`)

Script: `/var/tmp/uke-k5/repack-k5.py` (patrón K1-K4). Shell de partida:
`~/gpu-work/ramaa/s21/avb/boot-s240-mem2g.img`, sha256
`e3c60969269c0b36f23a37db5b1772128891232517c8d7979bd967b88acab206` (el mismo del s244/K2/K3/K4).
**Una sola imagen, cmdline del s244/K4 EXACTA (255 B, sin token)** — verificada byte a byte contra
`boot-ukek4.img`.

```
$ python3 /var/tmp/uke-k5/repack-k5.py       # salida resumida
  OK  base s240-mem2g e3c60969269c0b36... (100663296 B)
  OK  kernel K5 274e452ac3b95c8d (16564346 B gz)
  OK  cmdline == s244/K4 byte a byte, 255 B, sin token
  OK  UKE-POKE = 60 (K4: 45; encargo: >=24)
  OK  uke_attach_log x2 / uke_protect_smr0 x2 / PRESERVADO (BL vivo) x3 /
      SME VIVO DEL BOOTLOADER / BL estado idx=0 / ESCRIBIR SME idx= /
      mask sin el bit VALID / NO se escribe el S2CR / S2CR(0) HW AHORA
  OK  tabla __param con uke_attach_log y uke_protect_smr0 (9 params UKE)
  OK  96 MiB, ANDROID!, kernel_size=16564346, AVB0@35438592, AVBf@100663232
  OK  cabecera 0..4096 intacta salvo kernel_size@8
  OK  cola 16568442..100663296 identica byte a byte (initramfs/dtb/second/AVB intactos)
  OK  delta vs K4: 16493296 bytes, TODOS en kernel_size@8 + ventana kernel
      [4096,16569152) (fin K4=16569152, fin K5=16568442)
  sha256 = 520940ab4ee6f0373c2fd776111b0e2ce63a40014fba271f3260dc3a0f8e18e5
```

Nota del gate G7: K5 es 710 B **más pequeño** que K4; los 699 B que «difieren» respecto a K4 entre
`end_K5` y `end_K4` son los bytes del shell base que K5 restaura (correcto). El gate admite la
ventana completa hasta el fin del kernel mayor.

Gates independientes sobre el fichero final:

```
$ ls -la build/bootimg/boot-ukek5.img            → 100663296 B (96 MiB exactos)
$ dd … skip=8 count=4 | od -An -tu4              → 16564346 (= Image.gz del build)
$ dd … skip=35438592 count=4                     → AVB0
$ dd … skip=100663232 count=4                    → AVBf
$ unpack_bootimg --boot_img … --out /var/tmp/uke-k5/unpack → rc=0
  kernel == build/arch/arm64/boot/Image.gz (cmp IDÉNTICO; sha 274e452ac3b95c8d…)
  command line args: mem=2048M rdinit=/ukeinit … arm-smmu.disable_bypass=0  (255 B)
$ avbtool info_image --image …                   → rc=0 (footer AVB presente)
```

---

## 5. Qué debe salir por consola (K5) — formato exacto de las migas nuevas

```
UKE-POKE: uke_attach_log=1 (0=nada; 1=miga por maestro con flush antes de escribir + volcado BL; ...)
UKE-POKE: BL estado idx=0: SMR(0) HW=0x00000060 (valid=1 id=0x60 mask=0x0) S2CR(0) HW=0x........ (TYPE=n CBNDX=nn PRIVCFG=n)
UKE-POKE: attach: find_sme(dev=15000000.apps-smmu:...  sid=0x... mask=0x...) -> N
UKE-POKE: attach: dev=... sid=0x60 mask=0x0 -> find_sme elige idx=0, SME VIVO DEL BOOTLOADER (id=0x60 mask=0x0 valid=1)
UKE-POKE: attach: ESCRIBIR SME idx=0 dev=... -> SMR=0x80000060 (id=0x60 mask=0x0 valid=1) | S2CR nominal=0x000100ff (type=1 cbndx=255) [impl->write_s2cr: quirk qcom reescribe]
UKE-POKE: attach: idx=0 AHORA en HW: SMR(0)=0x80000060 (valid=1 id=0x60 mask=0x0) S2CR(0)=0x........ (TYPE=n CBNDX=nn)
UKE-POKE: qcom write_s2cr idx=0 quirk: type=0 cbndx=70 reg=0x00000046 en 0xc00     <-- la escritura real
```

Con `log=2` las dos últimas se sustituyen por:

```
UKE-POKE: attach: SME idx=0 PRESERVADO (BL vivo): se omite write_sme (no se toca SMR/S2CR)
UKE-POKE: attach: install_s2cr idx=0 PRESERVADO (BL vivo): NO se escribe el S2CR (el HW sigue con el mapeo del BL)
```

(La primera línea «BL estado …» da el dato que faltaba: el `TYPE`/`CBNDX` **reales** del S2CR(0) del
bootloader. `TYPE=1` = BYPASS; `TYPE=0` = TRANS (mirar CBNDX); `TYPE=2` = FAULT.)

---

## 6. PROCEDIMIENTO DE USO (lo ejecuta quien flashee, NO este agente)

Reglas de siempre: **un solo lector de consola**; doble captura (consola serie + `ssh` con
`dmesg -n 7; dmesg -w` al PC en `~/proyectos/out/`), y sin `flush_work` en el `.set` (el `echo`
vuelve en el acto aunque el probe se cuelgue). Gates de batería/USB/consola/rescate del
PRE-REGISTRO aplican: este agente no toca hardware.

### Paso 0 — arranque sano (K5 + dtbo bueno, s258)

```
fastboot flash boot_b build/bootimg/boot-ukek5.img     # sha 520940ab… (pre-registrar ANTES)
fastboot reboot
```

Esperado: banner `7.2.0-rc2-palawan … #8 SMP PREEMPT Tue Sep 29 00:44:57 CEST 2026` (K4 era #4),
panel vivo, dpu -19 como hoy,
y del apps-smmu solo las migas de arranque (`ENTRANDO`, `primer probe DIFFERIDO`, `desarmado`).
**NO** debe salir `REINTENTO`/`ARMADO`. Comprobar params:

```
# for p in uke_smmu_probe uke_keep_boot uke_reset_mask uke_smr_max uke_stream_match uke_attach_log uke_protect_smr0; do echo -n "$p="; cat /sys/module/arm_smmu/parameters/$p; done
uke_smmu_probe=N uke_keep_boot=N uke_reset_mask=65535 uke_smr_max=-1 uke_stream_match=Y uke_attach_log=0 uke_protect_smr0=N
```

### Paso 1 — captura
```
ssh … "dmesg -n 7; dmesg -w" > ~/proyectos/out/k5-migas.log 2>&1 &
```
(y la consola serie del PC en paralelo — un solo lector por canal.)

### Paso 2 — PELDAÑO A: observar (`uke_attach_log=1`), el de mínimo riesgo

```
# echo 0 > /sys/module/arm_smmu/parameters/uke_smr_max      # solo SMR(0), ya medido seguro
# echo 1 > /sys/module/arm_smmu/parameters/uke_keep_boot    # reset sin fase2
# echo 1 > /sys/module/arm_smmu/parameters/uke_attach_log   # migas por maestro + flush + volcado BL
# echo 0 > /sys/module/arm_smmu/parameters/uke_protect_smr0
# echo 1 > /sys/module/arm_smmu/parameters/uke_smmu_probe   # dispara el probe real (secuencia #P11)
```

Si el kworker se queda mudo antes del `REINTENTO` (como #P10), alternativa: `echo 15000000.apps-smmu
> /sys/bus/platform/drivers/arm-smmu/bind` como **última** orden (bind síncrono en el hilo del ssh).

Trail esperado: `ARMADO` → cfg_probe (SMR[0], ahora con `mask=0x0`) → **`BL estado idx=0: … S2CR(0)
HW=…`** → reset (fase2 OMITIDA, fase3 ×71, TLBI, sCR0) → `test_smr_masks OMITIDO` →
`iommu_device_sysfs_add`/register → **bloque de attach**: por cada maestro `find_sme` + `ESCRIBIR
SME idx=…` (flush-eadas) → si muere, **la última línea «ESCRIBIR SME» es el punto exacto**
(dev, idx, SMR/S2CR). Si sobrevive a los `ESCRIBIR`, siguen `install_s2cr …` y `write_context_bank
cfg=asignado`: los otros dos candidatos, también flush-eados.

### Paso 3 — PELDAÑO B: preservar (`uke_attach_log=2`) si A muere en el `write_sme` del idx vivo

```
# echo 2 > /sys/module/arm_smmu/parameters/uke_attach_log
# echo 1 > /sys/module/arm_smmu/parameters/uke_smmu_probe      # o bind al final
```
Esperado: `SME idx=0 PRESERVADO (BL vivo): se omite write_sme` y
`install_s2cr idx=0 PRESERVADO (BL vivo)`. Si con esto el bind completa: **grupos** →
`ls /sys/kernel/iommu_groups/` + `find /sys/kernel/iommu_groups/ -type l | grep 15000000` y
desaparece de `/sys/kernel/debug/devices_deferred`. Registro: el UFS sigue con el mapeo del BL
(buen resultado: el handoff es viable).

### Paso 4 — PELDAÑO C (solo si B no basta): `uke_protect_smr0=1`

```
# echo 0 > /sys/module/arm_smmu/parameters/uke_attach_log     # o 1 para tener migas
# echo 1 > /sys/module/arm_smmu/parameters/uke_protect_smr0
# echo 1 > /sys/module/arm_smmu/parameters/uke_smmu_probe
```
Esperado: `protect_smr0: idx 0 es del BL -> … se reubica en el idx libre alto 109 …`. OJO (anexo B):
crea un segundo SMR que casa el sid 0x60; si el HW elige el nuevo, el UFS puede empezar a fallar
(pérdida de I/O). Es diagnóstico, no configuración final.

### Paso 5 — si el bind completa

Con `dtbo_b` = s258 (panel vivo) y el SMMU bindeado: re-bindear el master DPU/mdss
(`echo 15000000.apps-smmu…` ya está; si no, unbind/bind de su driver) y comprobar `Adding to iommu
group` del mdss/dpu y **card0** en `/sys/class/drm/`. Con `uke_attach_log=2` el mdss no se preserva
(su idx no es BL-vivo): su attach escribirá SMR/S2CR libres y el de dominio (BYPASS→quirk). Si eso
mata, la última línea flush-eada lo dirá (y significaría que las escrituras en índices libres
también matan — dato nuevo, contra K3).

### Tabla de decisión (un peldaño por arranque si el anterior cuelga)

| desenlace | siguiente jugada | qué se aprende |
|---|---|---|
| muere justo tras `BL estado idx=0` | el volcado BL (lectura) mata → anotar y parar | lectura de S2CR(0) no es segura en este HW |
| muere en `ESCRIBIR SME idx=0` (ufshc) | **B**: `uke_attach_log=2` | el attach de mainline no puede tocar el SMR/S2CR vivo del UFS |
| muere en `ESCRIBIR SME idx=k>0` (idx libre) | anotar dev/idx; probar `uke_smr_max=-2` (barrido saltado → `smrs[]` todo invalid) y/o `uke_attach_log=2` | distingue "la escritura de SMR en general mata" (contradice K3) de "solo el vivo mata" |
| muere en `install_s2cr …` | log=2 (si el idx es el preservado) o anotar: el S2CR del attach mata | el dominio IDENTITY (BYPASS→TRANS cbndx 70) es mortal en algún idx |
| muere en `write_context_bank cfg=asignado` | anotar CB; `uke_reset_mask` no ayuda (es attach, no reset) | el CB del dominio pisa un CB vivo del BL |
| bind completo (sin muerte) | Paso 5 (grupos, dpu, card0) | **el SMMU es utilizable con handoff** |

---

## 7. Riesgos (los relevantes primero)

1. **`log=1` es solo observación, pero escribe como mainline**: si el índice vivo es letal, el
   peldaño A cuelga la tablet (una vez, con la miga flush-eada como premio). Es exactamente lo que
   el ciclo quiere medir: qué maestro/índice mata.
2. **`log=2` deja al UFS fuera del control del IOMMU mainline**: el core cree IDENTITY (bypass)
   sobre el device; si el S2CR(0) del BL era TRANS, el HW sigue traduciendo con tablas del BL (el
   estado actual, que funciona). Es el "handoff puro" que el encargo pide; documentado como
   configuración **de diagnóstico**, no fiel a mainline.
3. **`protect_smr0` duplica el match del sid 0x60** (dos SMR) y escribe S2CR(109)=TRANS cbndx 70
   (CB reservado sin tablas): si el HW elige el nuevo, el UFS puede perder I/O. Usarlo solo si
   log=2 no basta.
4. **La detección BL depende del barrido** (`uke_smr_max>=0`). El peldaño A usa `uke_smr_max=0`
   (medido seguro). No usar `-1` (K2 murió en el barrido completo).
5. **La escritura de S2CR(0) del BL sigue siendo un desconocido hasta la primera lectura**; el
   volcado BL la resuelve ANTES del reset, así que el peldaño A la responde incluso si muere
   después.
6. La consola es ttyGS0 (gadget USB del initramfs); los freeze duros pueden cortar el stream antes
   de la última línea. Por eso K5 **flush-ea antes de cada acceso**; aun así, la primera línea que
   falte respecto al formato esperado es, en sí misma, información.

---

## 8. Qué NO se ha hecho

* No se ha flasheado nada ni se ha hablado con la tablet (sin adb/fastboot/ssh en este encargo).
* `~/gpu-work` no se ha modificado (solo lectura). `~` solo lectura.
* En `omarchy-uke` no se ha editado ningún fichero existente ni se ha commiteado: los únicos
  ficheros **nuevos de K5** son `build/gates/patches/k5-attach.diff`,
  `build/bootimg/boot-ukek5.img` (ignorada por `.gitignore:25`) y este informe.
* No se ha usado `olddefconfig` (el `.config` del #82 se ha seguido usando tal cual).

## 9. Copias de trabajo y reproducibilidad

| ruta | contenido |
|---|---|
| `/var/tmp/uke-k1` | árbol con **K1+K2+K3+K4+K5** (`arm-smmu.c f52b34a3…`, `arm-smmu-qcom.c 3ed87c75…`) |
| `/var/tmp/uke-k1-build` | `O=` (config del #82, `Image.gz` K5 `274e452a…`, `vmlinux`, logs) |
| `/var/tmp/uke-k5/` | `repack-k5.py`, `repack-k5-report.txt`, `unpack/`, `repro/`, `k5-attach.diff` |
| `build/gates/patches/k5-attach.diff` | el parche de K5 (contra K4) |

Cadena completa sobre el árbol de referencia (solo lectura), reproducida y comparada byte a byte:

```
$ cp <referencia>/arm-smmu{,‑qcom}.c /var/tmp/uke-k5/repro/drivers/iommu/arm/arm-smmu/
$ patch -p1 -d repro < build/gates/patches/k1-arm-smmu.diff     # K1
$ patch -p1 -d repro < build/gates/patches/k2-arming.diff       # K2
$ patch -p1 -d repro < build/gates/patches/k3-smr.diff          # K3
$ patch -p1 -d repro < build/gates/patches/k4-keepboot.diff     # K4: 44ae596f… / 74403b44…
$ patch -p1 -d repro < build/gates/patches/k5-attach.diff       # K5: f52b34a3… / 3ed87c75… (cmp IDÉNTICO)
```

Es decir: `k1-arm-smmu.diff` + `k2-arming.diff` + `k3-smr.diff` + `k4-keepboot.diff` +
`k5-attach.diff`, en ese orden, reproducen exactamente el árbol con el que se ha construido y
empaquetado `boot-ukek5.img`.

---

## Anexo A — maestros con `iommus` al apps-smmu (69 entradas, DT vendor `stockuke.dts`)

| sid | mask | device |
|---|---|---|
| 0x0040 | 0x00 | `ssusb@a600000/dwc3@a600000` |
| **0x0060** | **0x00** | **`ufshc@1d84000`  ← el idx 0 vivo del BL** |
| 0x00a3 | 0x00 | `qcom,qupv3_0_geni_se@ac0000` |
| 0x00b6 | 0x00 | `qcom,gpi-dma@a00000` |
| 0x0140 | 0x00 | `sdhci@8804000` |
| 0x0400 ×5 | 0x00 | `iommu_test_device/usecase0..4` |
| 0x0423 | 0x00 | `qcom,qupv3_1_geni_se@8c0000` |
| 0x0436 | 0x00 | `qcom,gpi-dma@800000` |
| 0x0480/0x0481/0x0483 | 0x00 | `qcedev@1de0000` (+subnodos ns/s) |
| 0x04a0/0x04a1/0x04a2/0x04a4 | 0x00 | `qcom,ipa@3e00000` (ap/wlan/uc/11ad) |
| 0x04c0/0x04e0 | 0x20 | `tmc@10048000` |
| 0x0500 | 0x00 | `tmc@1004f000` |
| 0x0800 | 0x20 | `cci1@ac16000/msm_cam_smmu_ife` |
| 0x0c01..0x0c09, 0x0c0c..0x0c0e | 0x00 | `qcom,msm_fastrpc` (×12) |
| 0x1001/0x1061 | 0x80/0x00 | `spf_core_platform/qcom,msm-audio-ion` |
| 0x1003..0x1007 | 0x80/0x40 | `qcom,msm_fastrpc` |
| 0x1043..0x1046 | 0x20 | `qcom,msm_fastrpc` |
| 0x1067/0x1087 | 0x00 | `qcom,msm_fastrpc` |
| 0x100b | 0x00 | `usb_audio_qmi_dev` |
| 0x1800/0x1820/0x1840/0x1880/0x18c0 | 0x00 | `cci1@ac16000/msm_cam_smmu_icp` |
| 0x1860 | 0x00 | `msm_cam_smmu_cdm` |
| 0x18a0 | 0x00 | `msm_cam_smmu_jpeg` |
| 0x18e0 | 0x00 | `msm_cam_smmu_cre` |
| 0x1920/0x1920 | 0x00 | `cvp@ab00000/cvp_non_secure_cb` + `cvp_dsp_cb` |
| 0x1923/0x1924 | 0x00 | `cvp@ab00000` (secure pixel/nonpixel) |
| 0x1940/0x1941/0x1943/0x1944/0x1947 | 0x00/0x04 | `vidc@aa00000` (non_secure/secure/etc) |
| **0x1c00** | **0x02** | **`qcom,smmu_sde_unsec_cb` (mdss) ← NO casa SMR(0); `qcom,handoff-smrs` del DT** |
| 0x1c01 | 0x00 | `qcom,smmu_sde_sec_cb` |

(`phandle 0x129 = apps-smmu`, `stockuke.dts:13195`; `qcom,handoff-smrs = <0x1c00 0x02>` en
`stockuke.dts:13186`; `qcom,actlr` incluye `<0x1c00 0x02 0x01>`.)

## Anexo B — por qué `log=2` (y no `protect_smr0`) es la segunda jugada

El índice vivo es **ufshc** (rootfs). Con `log=2` no se escribe NADA sobre SMR(0)/S2CR(0): el UFS
sigue exactamente como está ahora (funcionando con el mapeo del BL) y el experimento mide el resto
del attach. Con `protect_smr0=1` se crea un SMR nuevo (idx 109) con el mismo id/mask: el HW tiene
dos entradas que casan el sid 0x60 y la precedencia no está garantizada; si gana la nueva, el S2CR
asociado (BYPASS→quirk TRANS cbndx 70) puede romper el acceso a disco. `protect_smr0` es por tanto
un **discriminante** ("¿el problema es tocar el registro vivo, o cualquier match del sid?"), no la
jugada de producción.
