# INFORME-K4-BUILD — kernel K4: `uke_keep_boot` + `uke_reset_mask` ("no tocar lo que dejó el bootloader")

Fecha: 2026-09-28 (noche). Autor: SG-K4.
Punto de partida: **K1+K2+K3** ya aplicados en `/var/tmp/uke-k1` (árbol) y `/var/tmp/uke-k1-build` (`O=`).
Contexto medido (K3, consola `~/proyectos/out/uke-ubuntu_console.log`, líneas 508870–508950, [47.710…]):
el probe real del apps-smmu **SOBREVIVE a todo el `cfg_probe`** (IDR0=0x4c017e6e → 110 grupos,
IDR1=0x60000047 → 71 CBs, NUMPAGENDXB=6, CB base 0x80000, IDR2=0x00005111, escritura+relectura
S2CR(0xdb4)/S2CR(109) con quirk qcom=SI, y **lectura SMR(0)=0x80000060: `valid=1, id=0x60,
mask=0x8000` — un mapeo VIVO del bootloader**) y **MUERE dentro de `arm_smmu_device_reset` fase2**:
silencio inmediatamente después de `UKE-POKE: reset fase2 SMR/S2CR x110` (sin pánico; el log salta
al siguiente arranque). El camino `uke_stream_match=0` (reset sin escribir SMR, solo S2CR) también
murió, pero su trail de consola se perdió.

Objetivo de K4, en una sola imagen: poder **omitir por partes** el reset del apps-smmu para no
destruir el estado que dejó el bootloader, y **descubrir con migas** si las escrituras del ATTACH
(probe_device/attach del mdss y demás consumidores) también son mortales — sin eso, el SMMU nunca
será utilizable por el DPU (ver §4).

> Recordatorio operativo: aquí **NO** se ha tocado la tablet (ni adb, ni fastboot, ni ssh). En
> `omarchy-uke` solo hay ficheros **NUEVOS** sin commitear. `~/gpu-work` solo lectura. Todos los
> cambios viven en `/var/tmp/uke-k1`, `/var/tmp/uke-k1-build` y `/var/tmp/uke-k4`.

---

## 0. Entregables y shas

| fichero | bytes | sha256 |
|---|---|---|
| `build/bootimg/boot-ukek4.img` | 100663296 (96 MiB exactos) | `b182ec02db105da1e06369ec219bbab6b21c5cc5315d2118c16fc1484bcc73b8` |
| `build/gates/patches/k4-keepboot.diff` | 16942 B, 400 líneas, 9 hunks, 2 ficheros, +265/−43 (267/45 con cabeceras) | `34b67980a92af0d97c2db9286a760191bb93681aaca0402d2d246395dce6ac74` |
| kernel fuente del empaquetado (`Image.gz`) | 16565056 (K3: 16562135, **+2921 B**) | `b50666369ea70599ac2f52598dc854e4226dc928c3fee853b463f39e349a5687` |
| kernel desempaquetado (`Image`) | 41355776 = 39,44 MiB (**delta 0** vs K1/K2/K3) | `314b7253b4b2879924ba495abb8959a5d01fa37cae071099fdaebff306d53958` |
| `arm-smmu.c` de K4 (K1+K2+K3+K4) | 91837 B | `44ae596fe7c4f875bbbcc52e0c230d9694754e09353e87bc29ece009c5bb2e60` |
| `arm-smmu-qcom.c` de K4 (K1+K3+K4) | 34788 B | `74403b4451ea127c527f7cde5804d955727be465ae16122bd745b81b153f0658` |

```
$ git status --short        # solo ficheros NUEVOS, sin commit (build/pkg/panel-o82/ es de otro agente)
?? build/gates/patches/k4-keepboot.diff
?? build/pkg/panel-o82/
$ git check-ignore -v build/bootimg/boot-ukek4.img
.gitignore:25:build/bootimg/*.img	build/bootimg/boot-ukek4.img
```

---

## 1. Qué escribe `arm_smmu_device_reset` de mainline, fase por fase (y qué destruye el estado del bootloader)

La función es la de mainline, instrumentada por K1 (migas) y K4 (condicionales). Citas por línea del
**árbol K4** (`/var/tmp/uke-k1/drivers/iommu/arm/arm-smmu/arm-smmu.c`; el número en el árbol de
referencia del proyecto es ~270 líneas menos, misma estructura).

| fase | línea K4 | qué escribe exactamente | nº accesos | ¿destruye estado del bootloader? |
|---|---|---|---|---|
| **1 sGFSR** | 1966-1968 | read de `sGFSR` (GR0+0x48) + write del mismo valor (limpia bits de fault) | 2 | No (RMW idempotente; sobrevivió en K1/K2/K3) |
| **2 SMR/S2CR** | 1980-1988 | `for i in 0..num_mapping_groups-1 (110): arm_smmu_write_sme(i)` (1983-1984) | **220 writes** | **SÍ — aquí murió K3** |
| **3 CBAR/SCTLR/FSR** | 1991-1996 | `for i in 0..70: arm_smmu_write_context_bank(i) + cb_write(CB_FSR, FAULT)` | 142 | Potencialmente **SÍ** (desactiva los 71 CBs, ver abajo) |
| **4 TLBI** | 2003-2006 | `TLBIALLH` (GR0+0x6c) y `TLBIALLNSNH` (GR0+0x68) | 2 | NO borra configuración, pero invalida TLBs de traducciones vivas |
| **5 sCR0 RMW** | 2012-2039 | read `sCR0` + modifica GFRE/GFIE/GCFGFRE/GCFGFIE, VMIDPNE, PTM, `CLIENTPD=0`, USFCFG (según `disable_bypass`), FB, BSU, VMID16EN, EXIDENABLE | 1 R + 1 W (en 2048) | Cambia la config global del SMMU (la del bootloader no se conserva) |
| **6 impl->reset** | 2041-2043 | `arm_mmu500_reset()` (`arm-smmu-impl.c:110-148`): read ID7 (0x3c), read sACR (0x10), clear `CACHE_LOCK`, set `SMTNMB_TLBEN\|S2CRB_TLBEN`, write sACR; y con `CONFIG_ARM_SMMU_MMU_500_CPRE_ERRATA=y` (`.config:7177`) **bucle 71× (read+write+read de `CB_ACTLR` = CB+0x4)** | 4 + 213 | Escribe sACR y ACTLRs de todos los CBs (bits de performance, pero toca CBs vivos) |
| **7 push** | 2046-2048 | `arm_smmu_tlb_sync_global()` (polling de `sTLBGSYNC/sTLBGSTATUS`) + write de sCR0 | poll + 1 | Aplica todo lo anterior |

**La fase 2 es la que destruye el handoff del bootloader**, y lo hace por tres vías:

1. **S2CR (110 writes)** — `arm_smmu_write_sme` (1215-1243) llama a `arm_smmu_write_s2cr`
   (1195-1213), que para el apps-smmu **no es la genérica**: el impl es `qcom_smmu_500_impl`
   (`arm-smmu-qcom.c:743`) con `.write_s2cr = qcom_smmu_write_s2cr` (636-680). Y el quirk medido
   (`bypass_quirk = true`) convierte cada S2CR lógico **BYPASS en TYPE=TRANS + cbndx=70**
   (`bypass_cbndx = num_context_banks-1`, líneas 644-661) — o sea que la fase2 **no escribe bypass**:
   apunta los 110 streams a un CB reservado que nadie ha configurado. La miga K4
   `UKE-POKE: qcom write_s2cr idx=… quirk: type=… cbndx=…` hace visible cada transformación.
2. **SMR (110 writes, solo si `smmu->smrs != NULL`)** — `arm_smmu_write_smr` (1184-1193) escribe
   `SMR(i) = id|mask|VALID` en GR0+0x800+4i. Para todo índice cuyo `smrs[i].valid == false` la
   escritura es **SMR(i)=0 (sin VALID): el mapeo del bootloader queda BORRADO**. Con el barrido
   completo (default `uke_smr_max=-1`) los que el barrido leyó como VALID se reescriben iguales,
   pero con el peldaño `uke_smr_max=0` que midió K3 **todos los índices 1..109 se invalidan**,
   tenga el hardware lo que tenga.
3. **Coherencia driver↔HW** — tras saltar la fase2 el driver cree en RAM lo del barrido
   (`s2crs[i] = BYPASS/0xff`, `smrs[i]` valid solo para lo leído) y el HW conserva lo del
   bootloader. Esa divergencia es exactamente lo que el driver vendor evita leyendo
   `qcom,handoff-smrs` del DT (este aparato trae `<0x1c00 0x02>`, el SID del mdss).

Fase 3 merece párrafo aparte: con el driver recién nascido **ningún CB tiene `cfg` asignado**, así
que `arm_smmu_write_context_bank` (794-881) entra por la rama `if (!cfg)` y escribe **SCTLR=0 en
los 71 CBs** (línea 816), incluidos los que el bootloader pueda estar usando para sostener la
pantalla en continuo. Es la segunda escritura candidata a destruir estado vivo (por eso el bit1
existe).

---

## 2. Los dos parámetros nuevos

### 2.1 `uke_keep_boot` (bool, 0644, default **0**) — `arm-smmu.c:217, 231-246`

**Solo apps-smmu** (`uke_smmu_es_apps()`, reg==0x15000000, misma guarda que el resto del parche).
Con `1`:

* el reset **omite entera la fase2**: miga
  `UKE-POKE: reset fase2 OMITIDA (uke_keep_boot=1, uke_reset_mask=0xe): NO se escribe NI UN SMR ni UN S2CR; los registros del bootloader quedan como estan`;
* `arm_smmu_test_smr_masks()` (1245-1302) **tampoco toca el HW**: mainline escribe SMR dos veces
  ahí (y lo deja con el valor de la máscara). Con keep_boot se omiten las escrituras y se asume el
  campo MASK completo (16 bits) — necesario porque `smr_mask_mask` solo lo fija ese test
  (1141) y `arm_smmu_probe_device` lo usa para validar el mask de cada maestro: si quedara a 0, el
  mdss (mask **0x02**) se rechazaría con `-EINVAL` y no habría attach que medir. Miga
  `UKE-POKE: test_smr_masks OMITIDO (uke_keep_boot=1): … smr_mask_mask=0xffff`;
* con `uke_reset_mask` sin tocar, la máscara efectiva pasa a `~bit0 = 0xe` (se saltan solo la fase2).

### 2.2 `uke_reset_mask` (int, 0644, default **0xffff**) — `arm-smmu.c:218, 249-274`

**Solo apps-smmu**; bit a 1 = **EJECUTAR** la fase, bit a 0 = saltarla:

| bit | fase | qué omite al ponerlo a 0 |
|---|---|---|
| bit0 (0x1) | fase2 | los 220 writes de SMR/S2CR |
| bit1 (0x2) | fase3 | los 142 accesos CBAR/SCTLR/FSR de los 71 CBs |
| bit2 (0x4) | fase4 | TLBIALLH/TLBIALLNSNH |
| bit3 (0x8) | fases 5+6+7 | RMW de sCR0, `impl->reset` (sACR + 71 CB_ACTLR) y tlb_sync+write sCR0 |

La fase1 (sGFSR) **se ejecuta siempre**. La máscara efectiva la decide
`uke_reset_mask_efectiva()` (276-288): para cualquier SMMU que no sea el apps-smmu vale `0xf`
(reset completo de mainline — el kgsl no cambia); para el apps-smmu, si el usuario ha escrito
`uke_reset_mask` **manda ese valor**; si no, `0xffff` normal o `0xe` con `uke_keep_boot=1`.

| keep_boot | ¿usuario tocó mask? | efectiva apps-smmu | fases |
|---|---|---|---|
| 0 | no | 0xf | 2,3,4,5-7 |
| 1 | no | **0xe** | 3,4,5-7 (fase2 NO) |
| 1 | sí, 0xffff | 0xf | 2,3,4,5-7 (override explícito: vuelve a activar fase2) |
| 1 | sí, 0xc | 0xc | 4,5-7 |
| 1 | sí, 0x8 | 0x8 | 5-7 |
| 1 | sí, 0x0 | 0x0 | ninguna (solo fase1) |

Cada fase ejecutada conserva su miga K1 (fase1..fase7, ahora con `uke_reset_mask=…` en fase2), y
cada fase saltada imprime su propia miga `reset faseN OMITIDA …` (fase2 lleva la subcadena exacta
pedida). Escribible en caliente; el valor que cuenta es el que se lee al entrar al reset (siguiente
probe, no el actual).

### 2.3 Migas nuevas para el ATTACH (lo que K4 mide por sí mismo)

La misión pedía "el propio K4 puede ser quien lo descubra con migas en apply_domain". Añadidas
(solo apps-smmu, sin tocar el kgsl):

| miga | dónde |
|---|---|
| `UKE-POKE: write_sme idx=… S2CR(0x…) type=… cbndx=… + SMR(0x…) id=… mask=… valid=…` | `arm_smmu_write_sme` (1223-1236), **antes** de cada escritura: si el reset fase2 vuelve a ejecutarse, la última línea da el índice y registro exactos del cuelgue; si el que muere es el attach, lo mismo |
| `UKE-POKE: attach: find_sme(dev=… sid=0x… mask=0x…) -> idx/N` | `arm_smmu_master_alloc_smes` (1385-1390): dice si el SID **reutiliza** un hueco del bootloader (`idx` con valid=1) o si cae en un hueco "libre" (donde la escritura pisaría territorio no leído) |
| `UKE-POKE: attach: install_s2cr idx=… type=… cbndx=… -> S2CR(0x…)` | `arm_smmu_master_install_s2crs` (1454-1456): la escritura del attach del display |
| `UKE-POKE: write_context_bank idx=… cfg=asignado/NULL (CB_SCTLR en 0x…)` | `arm_smmu_write_context_bank` (809-812): en fase3 71 líneas; en el attach del display, la del CB elegido |
| `UKE-POKE: qcom write_s2cr idx=… quirk: type=… cbndx=… reg=… en 0x…` | `qcom_smmu_write_s2cr` (`arm-smmu-qcom.c:677-678`), visible con la transformación del quirk |
| `UKE-POKE: test_smr_masks: ESCRIBO SMR(…) en 0x… = …` | 1288-1299, solo cuando el test sí corre (keep_boot=0) |

---

## 3. Build — comando exacto y gates

Incremental sobre el `O=` de K1/K2/K3 (solo `arm-smmu.o`, `arm-smmu-qcom.o` + relink):

```
$ setsid ... make -C /var/tmp/uke-k1 O=/var/tmp/uke-k1-build ARCH=arm64 LLVM=1 -j4 Image.gz
  CC      drivers/iommu/arm/arm-smmu/arm-smmu.o
  CC      drivers/iommu/arm/arm-smmu/arm-smmu-qcom.o
  …  LD vmlinux / OBJCOPY Image / GZIP Image.gz
$ grep -ci warning /var/tmp/uke-k4/build-k4.log   →  0     (y 0 errores)
$ cat /var/tmp/uke-k1-build/.version              →  4
```

Gate rc=0 con re-ejecución idempotente (0 líneas CC/GZIP, sha intacto):

```
$ sha256sum Image.gz > /tmp/k4-sha-before.txt
$ make … Image.gz ; echo RC=$?      → RC=0 ; grep -cE "CC |GZIP" = 0
$ sha256sum -c /tmp/k4-sha-before.txt → La suma coincide
```

| gate | comando | salida |
|---|---|---|
| toolchain | `.arm-smmu.o.cmd` | `clang … -DKBUILD_MODNAME='"arm_smmu"'` |
| arquitectura | `file Image` | `Linux kernel ARM64 boot executable Image, little-endian, 4K pages` |
| cabecera ARM64 | magic @56 | `0x644d5241` |
| banner | `grep -a "Linux version" Image` | `#4 SMP PREEMPT Mon Sep 28 23:51:25 CEST 2026` (K3: `#3 … 21:46:20`) |
| tamaño gz | `ls -la Image.gz` | 16565056 B (K3: 16562135 → +2921) |
| tamaño crudo | `gzip.decompress` | 41355776 B — **delta 0** vs K1/K2/K3/#82 |
| contenido | `raw.count(b"UKE-POKE")` | **45** (K3: 30; encargo: ≥24) |
| migas por objeto | `strings \| grep -c UKE-POKE` | `arm-smmu.o`=34, `arm-smmu-qcom.o`=9 |
| palancas en el binario | `raw.count(…)` | `uke_keep_boot`=5, `uke_reset_mask`=7, `uke_smmu_probe`=3, `uke_smr_max`=3, `uke_stream_match`=3 |
| cadenas K4 | `raw.count(…)` | `reset fase2 OMITIDA`=1, `test_smr_masks OMITIDO`=1, `attach: find_sme`=1, `attach: install_s2cr`=1, `write_context_bank`=1, `qcom write_s2cr`=1, `fases5-7 OMITIDAS`=1 |
| params en sysfs | tabla `__param` del `Image` | `arm_smmu.{disable_bypass,force_stage,uke_keep_boot,uke_reset_mask,uke_smmu_probe,uke_smr_max,uke_stream_match}` (7) |
| early_param fuera | tabla `__setup` | `uke_smmu_probe\0iommu.passthrough` **ausente** (K2+ no usa cmdline) |
| `nm -u` del `.o` | `nm -u arm-smmu.o` | `U param_set_int, param_get_int, param_set_bool, param_get_bool` (built-in: se resuelven en vmlinux; `param_set_int` existe, `nm vmlinux` lo confirma) |

Rutas sysfs finales (built-in, nombre de módulo `arm_smmu`):
`/sys/module/arm_smmu/parameters/{uke_smmu_probe,uke_smr_max,uke_stream_match,uke_keep_boot,uke_reset_mask}`.

---

## 4. Consecuencias funcionales de no repoblar SMR/S2CR — y si el attach del DPU podrá escribir

### 4.1 Qué queda en el hardware y qué cree el driver

Con `uke_keep_boot=1`: los 110 SMR y 110 S2CR quedan **como los dejó el bootloader**. El driver
mantiene su copia en RAM poblada por el barrido de `qcom_smmu_cfg_probe` (`smrs[i]` solo para los
leídos VALID; `s2crs[i]` a BYPASS/0xff para ellos y al init para el resto). Nada más. Efectos:

* Los grupos que el barrido no leyó (p. ej. con `uke_smr_max=0`, todos menos el 0) quedan
  `valid=false` en RAM **aunque el HW tenga mapeos**: son "huecos libres" para `find_sme`.
* `arm_smmu_test_smr_masks` se salta ⇒ `streamid_mask` se queda en el derivado de ID0 (0x7fff) y
  `smr_mask_mask` en 0xffff (cota superior del campo): los maestros con mask (mdss 0x02) pasan la
  validación de `arm_smmu_probe_device` (1579-1583). Un SID mayor que el que el silicio preserve de
  verdad sería aceptado y luego fallaría — irrelevante para 0x1c00.
* Al no ejecutarse la fase2 no se aplica la transformación del quirk (BYPASS→TRANS/CB70): los
  streams que el bootloader tenía en bypass siguen en bypass. Si el quirk lo que hace es dejar
  streams vivos apuntando a un CB sin configurar, saltarse la fase2 es justo lo que evita ese daño.

### 4.2 El ATTACH sí o sí escribirá SMR/S2CR (y no solo al re-sondear el display)

Aunque la fase2 se omita, el driver escribe SMR/S2CR en cuanto el SMMU binda, por dos caminos:

1. **`iommu_device_register()` → `bus_iommu_probe()`** (`drivers/iommu/iommu.c:307`) recorre todos
   los devices del bus y llama a `__iommu_probe_device()`; los que tienen fwspec hacia este SMMU
   entran en `arm_smmu_probe_device` → **`arm_smmu_master_alloc_smes` (`arm-smmu.c:1781,
   1358-1394`)**, que llama a `find_sme` y después a **`arm_smmu_write_sme` para cada SID** (SMR +
   S2CR). El DT declara `iommus` en ~58 nodos, así que **el propio bind del apps-smmu dispara
   decenas de escrituras nuevas** antes de que nadie re-sondee el display.
2. **`arm_smmu_attach_dev`** (1461) → `install_s2crs` (1433-1459): escribe S2CR (no SMR) del
   índice elegido con type=TRANS/cbndx del dominio.

Qué índice elige `find_sme` (1304-1344) para el mdss (`sid=0x1c00, mask=0x02`):

* si existe una entrada del bootloader que **cubra del todo** `(0x1c00, 0x02)` → devuelve su
  índice y el attach **reescribe SMR/S2CR sobre un registro vivo del bootloader** (mismo valor de
  id/mask si es la entrada handoff; el S2CR cambia a TRANS/CB del dominio);
* si no, devuelve el **primer índice con `valid=false` en RAM** y escribe allí un SMR nuevo. Si el
  barrido no leyó ese índice, **es una escritura a ciegas sobre territorio del bootloader** (con
  `uke_smr_max=0`, sobre SMR(1) muy probablemente: el SMR(0) medido es id=0x60/mask=0x8000, que no
  cubre a 0x1c00/0x02 y no produce solape → `find_sme` lo salta);
* si hubiera solape parcial con una entrada válida → `-EINVAL` (el maestro no bindea).

**¿Podrá el DPU escribir sin morir?** Es exactamente la pregunta que K4 deja medida:

* Si las escrituras de `write_sme`/`install_s2cr` del attach también matan (para el mdss o para
  cualquiera de los ~58 maestros), el SMMU **nunca será utilizable por el DPU**: no hay camino en
  mainline que instale una traducción sin escribir SMR/S2CR (el dominio IDENTITY también escribe
  S2CR). Las migas de K4 dirán **qué device, qué sid y qué registro** lo mató (los `pr_info` van
  justo antes de cada escritura), y eso convierte "el SMMU no se puede usar" en un dato localizado.
* Si sobrevive al bind + los probe_device de todos los maestros, entonces las escrituras de la
  fase2 eran mortales **por lo que escriben en los 110 índices** (el barrido completo de S2CR con
  la transformación del quirk y/o el reescribir SMR de índices no leídos), no por "escribir SMR en
  general" — y el SMMU sería utilizable al menos para el handoff del DT.
* La pregunta "¿la escritura del attach choca con lo protegido?" se responde en la consola: si
  muere en el `write_sme` del mdss, la última miga da `idx`, y la de `find_sme` dice si ese idx
  era del bootloader o un hueco. Con eso se decide si hay que parsear `qcom,handoff-smrs` en un K5
  (sintetizar `smrs[]`/`s2crs[]` desde el DT sin leer ni escribir el banco) o si basta keep_boot.

---

## 5. Empaquetado (`boot-ukek4.img`)

Script: `/var/tmp/uke-k4/repack-k4.py` (patrón K1-K3; el árbol del hermano NO se toca). Shell de
partida: `~/gpu-work/ramaa/s21/avb/boot-s240-mem2g.img`, sha256
`e3c60969269c0b36f23a37db5b1772128891232517c8d7979bd967b88acab206` (el mismo del s244/K2/K3).
**Una sola imagen, cmdline del s244 EXACTA (255 B, sin token)** — verificada byte a byte contra la
de `boot-ukek3.img`.

```
$ python3 /var/tmp/uke-k4/repack-k4.py       # salida resumida
  OK  base s240-mem2g e3c60969269c0b36... (100663296 B)
  OK  kernel K4 b50666369ea70599 (16565056 B gz)
  OK  cmdline == s244/K3 byte a byte, 255 B, sin token
  OK  UKE-POKE = 45 (K3: 30; encargo: >=24)
  OK  uke_keep_boot x5 / uke_reset_mask x7 / reset fase2 OMITIDA / test_smr_masks OMITIDO …
  OK  96 MiB, ANDROID!, kernel_size=16565056, AVB0@35438592, AVBf@100663232
  OK  cabecera 0..4096 intacta salvo kernel_size@8
  OK  cola 16569152..100663296 identica byte a byte (initramfs/dtb/second/AVB intactos)
  OK  delta vs K3: 16496023 bytes, TODOS en kernel_size@8+kernel [4096,16569152)
  sha256 = b182ec02db105da1e06369ec219bbab6b21c5cc5315d2118c16fc1484bcc73b8
```

Gates independientes sobre el fichero final:

```
$ ls -la build/bootimg/boot-ukek4.img            → 100663296 B (96 MiB exactos)
$ dd … skip=8 count=4 | od -An -tu4              → 16565056 (= Image.gz del build)
$ dd … skip=35438592 count=4                     → AVB0
$ dd … skip=100663232 count=4                    → AVBf
$ unpack_bootimg --boot_img … --out /var/tmp/uke-k4/unpack → rc=0
  kernel == build/arch/arm64/boot/Image.gz (cmp IDÉNTICO; sha b50666369ea70599…)
  command line args: mem=2048M rdinit=/ukeinit … arm-smmu.disable_bypass=0  (255 B)
$ avbtool info_image --image …                   → rc=0 (footer AVB presente)
```

---

## 6. PROCEDIMIENTO DE USO (lo ejecuta quien flashee, NO este agente)

Reglas de siempre: **un solo lector de consola**; doble captura (consola serie + `ssh` con
`dmesg -n 7; dmesg -w`), el `dmesg -w` **al PC en `~/proyectos/out/` (NUNCA `/tmp`)**, y sin
`flush_work` en el `.set` (el `echo` vuelve en el acto aunque el probe se cuelgue). Gates de
batería/USB/consola/rescate del proyecto (PRE-REGISTRO) aplican: este agente no toca hardware.

### Paso 0 — arranque sano (K4 + dtbo bueno, s258)

```
fastboot flash boot_b build/bootimg/boot-ukek4.img
fastboot reboot
```
Esperado: banner **`#4 SMP PREEMPT Mon Sep 28 23:51:25 CEST 2026`**, panel vivo, dpu -19 como hoy,
y del apps-smmu solo las migas de arranque (`ENTRANDO`, `primer probe DIFFERIDO`, `desarmado`).
**NO** debe salir `REINTENTO`/`ARMADO`.

```
# for p in uke_smmu_probe uke_keep_boot; do echo -n "$p="; cat /sys/module/arm_smmu/parameters/$p; done
# cat /sys/module/arm_smmu/parameters/uke_reset_mask   → 65535
# cat /sys/module/arm_smmu/parameters/uke_smr_max      → -1
# cat /sys/module/arm_smmu/parameters/uke_stream_match → Y
```

### Paso 1 — captura
```
ssh … "dmesg -n 7; dmesg -w" > ~/proyectos/out/k4-migas.log 2>&1 &
```
(y la consola serie del PC en paralelo — un solo lector por canal).

### Paso 2 — primer disparo (el de mínimo riesgo: no repoblar ni barrer)

```
# echo 0 > /sys/module/arm_smmu/parameters/uke_smr_max     # solo SMR(0), ya medido seguro
# echo 1 > /sys/module/arm_smmu/parameters/uke_keep_boot   # (miga de confirmación)
# echo 1 > /sys/module/arm_smmu/parameters/uke_smmu_probe  # arma y dispara el probe real
```
Desenlace esperado si todo va bien:
`ARMADO` → `cfg_probe ID0/ID1/ID2` → quirk → `SMR[0]=0x80000060` → `SMR loop OK` →
`reset fase1` → **`reset fase2 OMITIDA (uke_keep_boot=1…)`** → `fase3 CBAR/SCTLR/FSR x71` (71 migas
`write_context_bank`) → `fase4` → `fase5/6/7` → `test_smr_masks OMITIDO` → `iommu_device_register`
→ **bind** (`ls /sys/bus/platform/drivers/arm-smmu/` lista `15000000.apps-smmu`) → y en el mismo
bind, la tormenta de attach: `attach: find_sme(dev=… sid=0x…)` + `write_sme` + `install_s2cr` de
cada maestro con `iommus`.

### Paso 3 — escalera de saltos (un peldaño por arranque si el anterior cuelga)

| si muere en… | nueva jugada | qué se aprende |
|---|---|---|
| `SMR[i] -> readl` (barrido, solo con `uke_smr_max=-1`) | repetir con `uke_smr_max=k-1` (o `-2`); con keep_boot la fase2 no necesita `smrs[]` completo | el índice k que mata la **lectura** |
| `reset fase2 …` (con mask tocado a 0xffff) | volver a dejarlo en default (keep_boot=1, sin tocar mask) — no debería pasar | reproducir K3 y confirmar que la fase2 era la muerta |
| `reset fase3` | `echo 0xc > …/uke_reset_mask` (salta fase2+3) | si sobrevive, la fase3 (SCTLR=0 x71) también destruía estado vivo |
| `reset fase4` | `echo 0x8 > …/uke_reset_mask` (solo fases 5-7) | TLBI o nada |
| fases 5-7 | `echo 0 > …/uke_reset_mask` (solo fase1) | sCR0/impl/tlb |
| `attach: find_sme/write_sme/install_s2cr` | anotar dev/sid/idx/registro de la última miga; NO hay más saltos: el attach es inevitable → K5 (handoff desde DT) o aceptar que el SMMU no es usable | **si el DPU podrá usar el SMMU** |

Entre peldaños que SOBREVIVEN: `unbind`/`bind` por sysfs (como K3 §5) o reboot. Si un peldaño
cuelga, hace falta ciclo de alimentación. Nota: si el peldaño que sobrevive deja el SMMU bindeado,
los `probe_device` de los maestros ya habrán ocurrido; para re-medir el attach del display hay que
unbind/bind de su driver (`msm`) o reboot + re-armado.

---

## 7. Riesgos (los relevantes primero)

1. **La fase3 puede matar por sí sola** (SCTLR=0 en los 71 CBs, incluidos los del bootloader vivo):
   por eso su bit y por eso el peldaño `0xc`. Si el primer disparo muere en fase3, ya sabemos que el
   reset mainline no es compatible con el handoff ni siquiera sin tocar SMR/S2CR.
2. **El barrido completo (default -1) puede morir** en algún índice de lectura (K2 murió con el
   barrido entero sin migas por índice): el primer disparo usa `uke_smr_max=0`; el barrido completo
   es un experimento aparte (y sus migas dan el índice).
3. **El attach escribe aunque no se repueble** (§4.2): el bind del SMMU dispara `write_sme` de
   todos los maestros con `iommus`. Si esas escrituras son mortales, el SMMU no es utilizable por
   el DPU y el camino es K5 (sintetizar `qcom,handoff-smrs` en RAM **sin** escribir la fase2, pero
   el attach seguirá escribiendo: la pregunta abierta es exactamente si eso mata).
4. **Divergencia driver↔HW** con la fase2 saltada: `find_sme` puede escribir en índices que el
   bootloader tenía ocupados pero que el barrido no leyó (mitigable con el barrido completo si
   sobrevive, o con `uke_smr_max` alto pero no total). Es una configuración de diagnóstico, no de
   producción.
5. **Saltarse `test_smr_masks`** deja `streamid_mask=0x7fff` y `smr_mask_mask=0xffff` como cotas:
   acepta cualquier máscara/SID de 15 bits sin comprobarlo contra el silicio.
6. **`uke_keep_boot` y `uke_reset_mask` solo aplican al apps-smmu**: el kgsl (y cualquier otro SMMU)
   hacen el reset completo de mainline; no se altera el arranque de la GPU.
7. Los params son 0644 y se leen al vuelo: cambiar la mask a mitad de un probe no afecta a ese
   probe; el valor que cuenta es el del siguiente.

---

## 8. Qué NO se ha hecho

* No se ha flasheado nada ni se ha hablado con la tablet (sin adb/fastboot/ssh).
* `~/gpu-work` no se ha modificado (solo lectura). `~` solo lectura.
* En `omarchy-uke` no se ha editado ningún fichero existente ni se ha commiteado: los únicos
  ficheros **nuevos de K4** son `build/gates/patches/k4-keepboot.diff`, `build/bootimg/boot-ukek4.img`
  (ignorada por `.gitignore:25`) y este informe. (`build/pkg/panel-o82/`, sin commitear, es de otro
  agente; no se ha tocado.)
* No se ha usado `olddefconfig` (el `.config` del #82 se ha seguido usando tal cual).

## 9. Copias de trabajo y reproducibilidad

| ruta | contenido |
|---|---|
| `/var/tmp/uke-k1` | árbol con **K1+K2+K3+K4** (arm-smmu.c `44ae596f…`, arm-smmu-qcom.c `74403b44…`) |
| `/var/tmp/uke-k1-build` | `O=` (config del #82, `Image.gz` K4 `b5066636…`, `vmlinux`, logs) |
| `/var/tmp/uke-k4/` | `build-k4.log`, `repack-k4.py`, `repack-k4-report.txt`, `unpack/`, `repro/` |
| `build/gates/patches/k4-keepboot.diff` | el parche de K4 (contra K3) |

Cadena completa sobre el árbol de referencia (solo lectura), reproducida y comparada byte a byte:

```
$ cp <referencia>/arm-smmu{,‑qcom}.c /var/tmp/uke-k4/repro/drivers/iommu/arm/arm-smmu/
$ patch -p1 -d repro < build/gates/patches/k1-arm-smmu.diff
  arm-smmu.c 26a16af1… / qcom 14ea069d…            (K1)
$ patch -p1 -d repro < build/gates/patches/k2-arming.diff
  arm-smmu.c 87abc526…                              (K2)
$ patch -p1 -d repro < build/gates/patches/k3-smr.diff
  arm-smmu.c 3950a78b… / qcom 1c569b56…             (K3)
$ patch -p1 -d repro < build/gates/patches/k4-keepboot.diff
  arm-smmu.c 44ae596f… / qcom 74403b44…             (K4 = árbol de trabajo, cmp IDÉNTICO)
```

Es decir: `k1-arm-smmu.diff` + `k2-arming.diff` + `k3-smr.diff` + `k4-keepboot.diff`, en ese orden,
reproducen exactamente el árbol con el que se ha construido y empaquetado `boot-ukek4.img`.
