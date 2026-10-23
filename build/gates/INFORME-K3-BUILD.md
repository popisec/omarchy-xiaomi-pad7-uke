# INFORME-K3-BUILD — kernel K3: diagnóstico fino del barrido SMR (`uke_smr_max`) + palanca `uke_stream_match` (+ `boot-ukek3.img`)

Fecha: 2026-09-28 (noche). Autor: SG-K3.
Punto de partida: **K1+K2** ya estaban aplicados en las copias `/var/tmp/uke-k1` (árbol) y
`/var/tmp/uke-k1-build` (`O=`); K2 midió que el primer probe real del apps-smmu **sobrevive** a
IDR0/ID1/ID2 y a la escritura+relectura de S2CR(109), y **muere (cuelgue duro, sin abort) dentro
del barrido `leyendo SMR(0..109)`** (`build/gates/k2-migas-log.txt`, última línea, ~171.464254 s).

Los dos objetivos de K3, en **una sola imagen**:

1. **Diagnóstico fino del barrido SMR**: localizar el código, clasificarlo (¿funcional o solo
   miga?), añadir **una miga por índice ANTES de cada `readl`** (sin rate-limit) y un
   **NOOP-check** con el valor leído, más el parámetro `uke_smr_max` para recorrer la escalera
   de índices y saltar el barrido entero.
2. **Palanca de salto/reset**: parámetro `uke_stream_match` (bool, default 1). Con 0, para el
   apps-smmu (reg=0x15000000) se fuerza el camino **stream-indexing sin SMR** de mainline: ni el
   barrido ni el reset tocan un solo registro SMR.

> Recordatorio operativo: aquí **NO** se ha tocado la tablet (ni adb, ni fastboot, ni ssh). En
> `omarchy-uke` solo hay ficheros **NUEVOS** sin commitear (`??`). Se ha leído (solo lectura)
> `~/gpu-work` y, para buscar el driver vendor, el resto del disco; **no** se ha modificado nada
> fuera de `/var/tmp/uke-k1`, `/var/tmp/uke-k1-build` y `/var/tmp/uke-k3`.

---

## 0. Entregables y shas

| fichero | bytes | sha256 |
|---|---|---|
| `build/bootimg/boot-ukek3.img` | 100663296 (96 MiB exactos) | `7234ea4df72dc58bbd5e20a402ec4f003bfaa49243caf87293b627a9c3e79130` |
| `build/gates/patches/k3-smr.diff` | 10923 B, 234 líneas, 2 ficheros, 9 hunks, +161/−5 | `222099d7f18be968fefa8c295fa46628ea84dec78f6254592842cfd7091ef55c` |
| kernel fuente del empaquetado (`Image.gz`) | 16562135 | `a1a2308827397908bad036f82a3d8d8709ad388a6649f04e0b67eb769045b2ac` |
| kernel desempaquetado (`Image`) | 41355776 = 39,44 MiB | `076a39e21a8a5b60117d2260d22be628cdd7fbf89ab7b4a812d681bd9dd91382` |
| `arm-smmu.c` de K3 (K1+K2+K3) | 81925 B | `3950a78bbb527d9df6d018962a023914d5a33b1b66205c0979dc6e91013788a0` |
| `arm-smmu-qcom.c` de K3 (K1+K3) | 34189 B | `1c569b565e52c07b4db1078a1acc3c14e09e5acea40230717232edd0caa50bf8` |

```
$ ls -la build/bootimg/boot-ukek3.img
-rw-r--r-- 1 usuario usuario 100663296 sep 28 21:48 build/bootimg/boot-ukek3.img
$ sha256sum build/bootimg/boot-ukek3.img build/gates/patches/k3-smr.diff
7234ea4df72dc58bbd5e20a402ec4f003bfaa49243caf87293b627a9c3e79130  boot-ukek3.img
222099d7f18be968fefa8c295fa46628ea84dec78f6254592842cfd7091ef55c  k3-smr.diff
$ git status --short        # solo ficheros NUEVOS, sin commit (más build/pkg/panel-o82/, ajeno a K3)
?? build/gates/INFORME-K3-BUILD.md
?? build/gates/patches/k3-smr.diff
?? build/pkg/panel-o82/
$ git check-ignore -v build/bootimg/boot-ukek3.img
.gitignore:25:build/bootimg/*.img	build/bootimg/boot-ukek3.img
```

`Image` = 41355776 B, **delta 0 B** respecto a K1, K2 y al `Image` del #82 (el parche solo cambia
cadenas y unos pocos caminos de código).

---

## 1. DIAGNÓSTICO: qué es el barrido `leyendo SMR(0..109)`

### 1.1 Dónde está y de quién es (fichero y líneas)

El bucle es **código FUNCIONAL de mainline**, no una miga del proyecto:

| pieza | fichero:línea (árbol prístino, `~/gpu-work/palawan-linux`, solo lectura) |
|---|---|
| función que lo contiene | `drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c:450` (`qcom_smmu_cfg_probe`) |
| bucle del barrido | `arm-smmu-qcom.c:516-530` |
| el `readl` que mata | `arm-smmu-qcom.c:517` — `smr = arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_SMR(i));` |
| escritura+relectura de S2CR previa (quirk) | `arm-smmu-qcom.c:494-505` |

El texto `leyendo SMR(0..109)` que aparece en el log de K2 **sí es de K1** (miga), no del bucle:
K1 añadió un `pr_info` justo antes del bucle, la declaración de `n_validos`, un `n_validos++` y
otro `pr_info` después. Prueba: el diff prístino→K1 (`k1-arm-smmu.diff`) añade en esa función **10
líneas y 0 eliminaciones** (4 `pr_info` + 2 de `n_validos`); las otras 7 líneas que K1 añade a ese
fichero son el comentario y la entrada `qcom,qsmmu-v500` del `of_match`. El parche de pokes
(`build/gates/patch-uke-smmu-pokes.py`) **no** toca este bucle (`grep SMR/S2CR` en él solo
encuentra texto de las migas de `arm-smmu.c`), así que la respuesta a la pregunta del encargo es:
**el barrido es del `qcom_smmu_cfg_probe` de mainline; la miga que lo precede es de K1; el parche
de pokes no tiene nada que ver.**

En la copia K3 el bucle queda en `arm-smmu-qcom.c:589-616` (con las migas nuevas), ver §2.

### 1.2 Qué hace con los valores leídos (es funcional: puebla `smmu->smrs`/`s2crs`)

Por cada SMR que lee `VALID=1`, el bucle puebla el estado en RAM del driver:

* `smmu->smrs[i].id/.mask/.valid = true` (`arm-smmu-qcom.c:519-525`);
* `smmu->s2crs[i] = { type=BYPASS, privcfg=DEFAULT, cbndx=0xff }` (`arm-smmu-qcom.c:527-529`).

Consecuencias (todas verificadas en el código de la copia K3):

1. **El reset reescribe esas entradas en vez de invalidarlas.** `arm_smmu_device_reset()`
   (`arm-smmu.c:1774`) hace `for (i = 0; i < num_mapping_groups; ++i) arm_smmu_write_sme(smmu, i)`
   (`arm-smmu.c:1789-1790`); `arm_smmu_write_sme` (`arm-smmu.c:1097-1102`) escribe S2CR y, si hay
   `smrs`, el SMR con el id/mask preservados y `VALID` (si `smrs[i].valid`).
2. **Los grupos que el firmware dejó grabados se consideran "ocupados"**: `arm_smmu_find_sme()`
   (`arm-smmu.c:1141-1180`) no reutilizará un índice con `valid=1`, así que un maestro nuevo no
   puede pisar un mapeo del bootloader (devuelve `-EINVAL` si hay solape parcial).
3. **`arm_smmu_test_smr_masks()`** (`arm-smmu.c:1108-1142`, llamada en `arm-smmu.c:2498` tras el
   reset) se salta su test si no encuentra un SMR libre — es decir, si el firmware dejó todos
   ocupados, el driver **confía** en las máscaras leídas del hardware y no las prueba.

Es, por tanto, el equivalente mainline de lo que el driver vendor hace leyendo
`qcom,handoff-smrs`: **preservar los mapeos de stream del bootloader a través del reset del
driver** (quedan como BYPASS). El DT de este aparato trae justamente esa propiedad:

```
apps_smmu: apps-smmu@15000000 { compatible = "qcom,qsmmu-v500"; qcom,handoff-smrs = <0x1c00 0x02>; ... }
mdss_ml: display-subsystem@ae00000 { iommus = <0x129 0x1c00 0x02>; ... }   # apps_smmu = phandle 0x129
```

(medido en `/tmp/g2/merged-s257.dts:16366` y `:857`; el SID 0x1c00 con máscara 0x02 es el del
**mdss**). El driver vendor **no barre** los 110 SMR: programa solo los handoff del DT. El
mainline, en cambio, reconstruye el estado leyendo los registros — y aquí es donde se cuelga.

### 1.3 Qué pasaría al saltarlo (y por qué NO es gratis)

* **Estado del driver**: sin el barrido, `smmu->smrs[]` queda todo a cero (invalid) y el reset
  escribe `SMR(i)=0` (sin `VALID`) para los 110 grupos: los mapeos del bootloader se pierden. Los
  streams que el firmware tenía mapeados pasan a "unmatched": con `arm-smmu.disable_bypass=0`
  (cmdline de esta imagen) `sCR0.USFCFG=0` ⇒ bypass, que es **el mismo efecto neto** que les daría
  el camino preservado (S2CR=BYPASS)… pero el driver ya no conoce esos mapeos: los 110 grupos
  cuentan como libres y el primer attach puede reutilizarlos.
* **Función de la GPU/display**: el mdss (SID 0x1c00) no depende de que su SMR esté preservado
  para el bypass, pero **sí** de que exista la traducción si su dominio es TRANSLATED
  (`msm_iommu.c` pide `iommu_domain_alloc+attach`); ahí el SMR lo escribe el driver al attachar.
* Por eso el encargo tiene razón en que saltarlo **no** es una solución de producción: para
  conservar la semántica habría que **parsear `qcom,handoff-smrs`** (una lista de pares
  sid/mask; aquí `<0x1c00 0x02>`) y sintetizar `smmu->smrs[]`/`s2crs[]` desde el DT **sin leer el
  banco SMR**. Es la alternativa propuesta (ver §6, riesgo 5). Nota: el árbol vendor con esa
  implementación **no está en el disco** (búsqueda read-only en `~/gpu-work` —palawan-linux,
  palawan-build, palawan-mainline, ramaa— y en `~`; `~/kws/common` es mainline y no
  contiene el driver `msm` de SMMU: no hay ningún `handoff` en sus fuentes). Solo se han podido
  citar los DTS volcados del stock.

### 1.4 CORRECCIÓN de una premisa del encargo: el kgsl NO barre sus SMR

El encargo decía "el kgsl-smmu@3da0000 sí barre sus 24 SMRs sin morir (AP-owned)". **No es
cierto** y conviene no apoyarse en ello: el nodo del kgsl es `qcom,adreno-smmu`, y
`qcom_smmu_create()` (`arm-smmu-qcom.c:785-810`) elige para él `data->adreno_impl` =
`qcom_adreno_smmu_500_impl` (`arm-smmu-qcom.c:775-783`), que **no tiene `.cfg_probe`** ⇒
`arm_smmu_device_cfg_probe()` no llama a `qcom_smmu_cfg_probe` para el kgsl (`arm-smmu.c:2091`).
Evidencia en el log de K2: para kgsl salen `stream matching with 24 register groups`,
`preserved 0 boot mappings` y `reset fase2 SMR/S2CR x24`, pero **ninguna** línea
`leyendo SMR(...)` / `VOY a ESCRIBIR S2CR` (solo las del apps-smmu). Lo único que el kgsl
demuestra es que **escribir** los 24 SMR de *su propio* SMMU (AP-owned) no cuelga: `reset fase2
SMR/S2CR x24` a 0.318690 s y la miga siguiente 3 ms después. Del **read** de SMR en este aparato
el único dato que existe es la muerte del apps-smmu en K2. La escalera de K3 es justo la que
resuelve si es la región entera (SMR(0) = 0x800) o un índice concreto.

---

## 2. Los dos parámetros nuevos

### 2.1 `uke_smr_max` — palanca de la escalera (diagnóstico)

* Definido en `arm-smmu-qcom.c:482` (`module_param`, int, **0644**, default **-1**), con
  `MODULE_PARM_DESC` (`arm-smmu-qcom.c:483-485`) y comentario largo en `:451-481`.
* Semántica, implementada en el barrido (`arm-smmu-qcom.c:579-618`):
  * `-1` (defecto) o cualquier valor ≥ `num_mapping_groups-1` (109): **bucle completo** (idéntico
    a K1/K2, que es lo que murió — así el primer disparo de K3 reproduce el K2);
  * `0..108`: solo se leen `SMR(0..uke_smr_max)` (`:583-585`);
  * `-2`: **no se lee ni un SMR** (`:573-577`).
* Miga por índice, sin rate-limit (`:589-602`), 2 líneas por SMR (220 en el barrido completo,
  aceptable):
  ```
  UKE-POKE: SMR[i] -> readl(0x8xx)                       ← ANTES de la lectura (la que mata)
  UKE-POKE: SMR[i] = 0x%08x (valid=%u id=0x%x mask=0x%x) ← NOOP-check con el valor leído
  ```
  y cabecera/cierre: `leyendo SMR(0..%u) [uke_smr_max=%d grupos=%u]` y `SMR loop OK (leidos=%u
  validos=%u)`.
* Guarda añadida (`:560-568`): si `smmu->smrs == NULL` (modo sin stream matching por
  `uke_stream_match=0`, o hardware sin SMS) el barrido se salta con miga — sin `smrs` no hay
  nada que poblar y no se debe tocar la región.

**Nota importante sobre el alcance de `-2`**: salta **solo** el barrido. El reset
(`arm-smmu_write_sme`, `arm-smmu.c:1097-1102`) sigue escribiendo los 110 SMR y
`arm_smmu_test_smr_masks` (`arm-smmu.c:2498`) sigue leyendo/escribiendo SMR(0). Si el cuelgue es
la **región** y no un índice, `-2` morirá igual en `reset fase2 SMR/S2CR x110` (la miga queda
justo antes del bucle, `arm-smmu.c:1788-1790`) — para ese caso está la otra palanca.

### 2.2 `uke_stream_match` — palanca "sin stream matching" (reset incluido)

* Definido en `arm-smmu.c:180-184` (`module_param`, bool, **0644**, default **1**), con
  comentario largo en `:149-179`.
* **Verificación de mainline (lo que el encargo pedía comprobar)**: en este driver **no existe**
  un campo `smmu->stream_matching`. El modo stream matching ES el par
  `(ARM_SMMU_FEAT_STREAM_MATCH en smmu->features) && (smmu->smrs != NULL)`, decidido en
  `arm_smmu_device_cfg_probe()` a partir del bit `SMS` de IDR0 (`arm-smmu.c:1986-1999`). El
  camino "sin stream matching" es el de **stream indexing** de mainline:
  * `arm_smmu_find_sme()` devuelve el **stream ID crudo** como índice (`arm-smmu.c:1149-1151`:
    "Stream indexing is blissfully easy: if (!smrs) return id;");
  * `arm_smmu_write_sme()` escribe S2CR y **no** escribe SMR (`arm-smmu.c:1097-1102`);
  * el reset fase2 **sí** recorre `num_mapping_groups` escribiendo S2CR (`arm-smmu.c:1789-1790`)
    pero sin SMR;
  * `arm_smmu_test_smr_masks()` retorna en el acto (`arm-smmu.c:1112-1114`).
* Dónde se aplica (`arm-smmu.c:1946-1976`): en la lectura de **ID0**, antes de alojar `smrs` y
  antes del barrido. (Hacerlo "justo antes del reset" NO serviría: el barrido ya habría leído los
  SMR.) Si `!uke_stream_match && uke_smmu_es_apps(smmu)` se limpia `ID0.SMS` y el driver sigue el
  camino stream-indexing de mainline.
* **Desviación deliberada y documentada** (`arm-smmu.c:2004-2011`): con `SMS=0`, mainline dejaría
  `num_mapping_groups = 1<<NUMSIDB`. Aquí ID0=0x4c017e6e ⇒ `NUMSIDB=15` ⇒ 32768: el reset
  escribiría 32768 S2CR (`0xc00..0x20bfc`) y el attach del mdss (SID 0x1c00=7168) `S2CR(7168)` en
  `0x7c00`, **fuera del banco comprobado** (0xc00..0xdb8 = S2CR(0..109), el 109 lo releyó K2 con
  éxito). Para no cambiar un cuelgue por otro: `s2crs` se aloja con 32768 entradas (ningún SID de
  15 bits desborda el array) pero `num_mapping_groups` se **capa a NUMSMRG=110**, así el quirk
  test (`S2CR(109)`) y el reset (`S2CR(0..109)`) se quedan en el banco ya probado. Es una
  configuración **no fiel** a mainline; sirve para responder "¿el probe llega al final (bind) sin
  tocar ni un SMR?", no para dejar el SMMU traduciendo de verdad.
* **¿Funciona la traducción para el mdss sin SMR?** Con `smrs==NULL` el índice de S2CR es el SID,
  así que el mdss (0x1c00) usaría `S2CR(7168)` (`0x7c00`). Este SMMU declara `SMS=1, NUMSMRG=110`:
  solo los 110 primeros S2CR están en el banco "architected" del modo stream-matching; `S2CR(7168)`
  es territorio no probado (como mucho RAZ/WI, y en el peor caso cuelgue de bus). El `-ENODEV`
  (-19) del DPU (no hay `iommu_group`) se resuelve con el **bind**; la **traducción real** del mdss
  en este modo queda pendiente de un segundo experimento (re-sondear el DPU tras el bind) y está
  documentada como riesgo (§6.3).

---

## 3. Build — comando exacto y gates

Incremental sobre el `O=` de K1/K2 (solo se recompilan `arm-smmu.o` y `arm-smmu-qcom.o` + relink):

```
$ setsid nohup env MAKE=/usr/bin/make /usr/bin/make -C /tmp/uke-k1 O=/tmp/uke-k1-build \
    ARCH=arm64 LLVM=1 -j4 Image.gz >> /var/tmp/uke-k3/build-k3.log 2>&1 &
$ head -6 /var/tmp/uke-k3/build-k3.log
== K3 build ==
cmd: MAKE=/usr/bin/make make -C /tmp/uke-k1 O=/tmp/uke-k1-build ARCH=arm64 LLVM=1 -j4 Image.gz
2026-09-28T21:46:08+02:00
tree: /tmp/uke-k1 -> /var/tmp/uke-k1
3950a78bbb527d9df6d018962a023914d5a33b1b66205c0979dc6e91013788a0  .../arm-smmu.c
1c569b565e52c07b4db1078a1acc3c14e09e5acea40230717232edd0caa50bf8  .../arm-smmu-qcom.c
$ grep -E "CC |Image|GZIP" /var/tmp/uke-k3/build-k3.log | head -4
  CC      drivers/iommu/arm/arm-smmu/arm-smmu.o
  CC      drivers/iommu/arm/arm-smmu/arm-smmu-qcom.o
  OBJCOPY arch/arm64/boot/Image
  GZIP    arch/arm64/boot/Image.gz
$ grep -ci warning /var/tmp/uke-k3/build-k3.log   →  0     (y 0 errores)
```

Gate rc=0 con re-ejecución idempotente (prueba de que el build no fue un no-op a medias):

```
$ sha256sum Image.gz > /tmp/k3-sha-before.txt
$ /usr/bin/make -C /tmp/uke-k1 O=/tmp/uke-k1-build ARCH=arm64 LLVM=1 MAKE=/usr/bin/make Image.gz; echo RC=$?
RC=0
$ sha256sum -c /tmp/k3-sha-before.txt
/tmp/uke-k1-build/arch/arm64/boot/Image.gz: La suma coincide     ← 0 líneas CC/GZIP: no había nada que rehacer
$ cat /var/tmp/uke-k1-build/.version   →  3
```

| gate | comando | salida |
|---|---|---|
| toolchain | `.arm-smmu-qcom.o.cmd` | `clang … -DKBUILD_MODNAME='"arm_smmu"' …` |
| arquitectura | `file arch/arm64/boot/Image` | `Linux kernel ARM64 boot executable Image, little-endian, 4K pages` |
| cabecera ARM64 | magic @56 | `0x644d5241` |
| banner | `grep -a "Linux version" Image` | `Linux version 7.2.0-rc2-palawan (usuario@pc-build) (clang version 22.1.8, LLD 22.1.8) #3 SMP PREEMPT Mon Sep 28 21:46:20 CEST 2026` (K2: `#2 … 21:19:35`) |
| tamaño gz | `ls -la Image.gz` | 16562135 B (K2: 16561740 → **+395 B**) |
| tamaño crudo | `gzip.decompress` | 41355776 B — **delta 0** vs K1, K2 y #82 |
| contenido | `raw.count(b"UKE-POKE")` | **30** (K2: 24; encargo: ≥24) |
| palancas en el binario | `raw.count(...)` | `uke_smr_max`=3, `uke_stream_match`=3, `arm_smmu.uke_smr_max`=1, `arm_smmu.uke_stream_match`=1 |
| migas nuevas | `raw.count(...)` | `-> readl(0x%x)`=1, `SMR[%d] = 0x%08x`=1, `barrido SMR SALTADO ENTERO`=1, `smrs==NULL (sin stream matching)`=1, `STREAM-INDEXING`=1, `SMR loop OK (leidos=%u`=1 |
| params en sysfs | tabla `__param` del `Image` | `arm_smmu.force_stage`, `arm_smmu.disable_bypass`, `arm_smmu.uke_smmu_probe`, `arm_smmu.uke_stream_match`, `arm_smmu.uke_smr_max` (los 5 del módulo `arm_smmu`) |
| early_param fuera | tabla `__setup` | `uke_smmu_probe\0iommu.passthrough` **ausente** |
| migas por objeto | `strings \| grep -c UKE-POKE` | `arm-smmu.o`=20, `arm-smmu-qcom.o`=8 |
| `nm -u` del `.o` (qcom) | `nm -u arm-smmu-qcom.o` | `U param_set_…`, `U arm_mmu500_reset`, … (sin símbolos nuevos raros) |

Los nombres de param que aparecen en la tabla son los de **built-in** (`arm_smmu.xxx`), así que
las rutas sysfs finales son:
`/sys/module/arm_smmu/parameters/{uke_smmu_probe,uke_smr_max,uke_stream_match}` (el nombre del
módulo se verificó por `KBUILD_MODNAME` en el `.cmd`, igual que en K2).

---

## 4. Empaquetado (`boot-ukek3.img`)

Script: `/tmp/uke-k3-repack.py` (adaptado del `/tmp/uke-k2-repack.py`; el árbol del hermano NO se
ha tocado). Shell de partida: `ramaa/s21/avb/boot-s240-mem2g.img` (sha256 `e3c60969269c0b36…`),
el mismo del `boot-s244-bounce.img` de hoy y del K2. **Una sola imagen, cmdline del s244 EXACTA
(255 B, sin token).**

```
$ python3 /tmp/uke-k3-repack.py
kernel K3: 16562135 B gz (sha16 a1a2308827397908), 30 cadenas UKE-POKE, ARMADO+arming+desarmado+fases OK
params K3 en tabla __param: arm_smmu.{uke_smmu_probe,uke_stream_match,uke_smr_max}  OK
early_param eliminado (fuera de la tabla __setup)  OK
migas K3 por indice + palancas: 'SMR[%d] -> readl', 'SMR[%d] = 0x%08x', -2, smrs==NULL, STREAM-INDEXING  OK
K2 dentro de boot-ukek2.img: Image.gz 16561740 B sha16 f85153dc0fb8eaa3 -> Image 41355776 B
Image K3 41355776 B vs Image K2 41355776 B: delta 0 B (gate +-2 KB)  OK
cruce K2/K3: K2 tenia 24 UKE-POKE y 0 'uke_smr_max'/'uke_stream_match'; K3 tiene 30 y ambas  OK
s244 == shell + kernel (solo kernel y kernel_size cambian; cmdline y footer identicos)  OK
shell boot-s240-mem2g.img sha256 e3c60969269c0b36... OK; cmdline s244 255 B exacta
== build/bootimg/boot-ukek3.img ==
  sha256 7234ea4df72dc58bbd5e20a402ec4f003bfaa49243caf87293b627a9c3e79130
  cmdline 255 B (identica byte a byte a la del s244 / K2): mem=2048M rdinit=/ukeinit panic=10
    memmap=0x1A12800$0xE3940000 console=tty0 fbcon=map:0 hung_task_timeout_secs=20 hung_task_panic=1
    watchdog_thresh=10 console=ttyGS0,115200 fw_devlink=permissive clk_ignore_unused pd_ignore_unused
    arm-smmu.disable_bypass=0
  kernel_size@8 = 16562135 ; AVB0@35438592 ; AVBf@100663232 (ultimos 4 B de los 96 MiB)  OK
boot-ukek3 vs boot_b de hoy (s244): 16493955 bytes distintos (kernel_size@8+kernel [4096,35438592)); cmdline y footer identicos  OK
boot-ukek3 vs boot-ukek2: 16488061 bytes distintos, TODOS en kernel_size@8+kernel [4096,35438592); cmdline y footer AVB identicos  OK
unpack_bootimg: kernel == build (16562135 B, sha16 a1a2308827397908)  OK
  kernel_size: 16562135
  command line args: mem=2048M rdinit=/ukeinit panic=10 … arm-smmu.disable_bypass=0
avbtool info_image: rc=0 (footer AVB presente)  OK
GATE COMPLETO: OK
```

Gates independientes (evidencia dura sobre el fichero final):

```
$ ls -la build/bootimg/boot-ukek3.img            → 100663296 B (96 MiB exactos)
$ dd if=... bs=1 skip=8 count=4 | od -An -tu4    → 16562135 (= Image.gz del build)
$ dd if=... bs=1 skip=35438592 count=4           → AVB0
$ dd if=... bs=1 skip=100663232 count=4          → AVBf
$ unpack_bootimg --boot_img ... --out /tmp/uke-k3-unpack → rc=0, kernel == build
$ avbtool info_image --image ...                 → rc=0
```

---

## 5. PROCEDIMIENTO DE USO (lo ejecuta quien flashee, NO este agente)

Regla de siempre: **un solo lector de consola**; doble captura (consola serie + `ssh` con
`dmesg -n 7; dmesg -w`), y sin `flush_work` en el `.set` (el `echo` vuelve en el acto aunque el
probe se cuelgue).

### Paso 0 — arranque sano (K3 + dtbo s258)

```
fastboot flash boot_b build/bootimg/boot-ukek3.img
fastboot reboot
```
Gates de "kernel vivo": banner **`#3 SMP PREEMPT Mon Sep 28 21:46:20 CEST 2026`**, panel vivo,
dpu -19 como hoy, y del apps-smmu solo las migas de arranque (`ENTRANDO`, `primer probe
DIFFERIDO`, `desarmado`). **NO** debe salir `REINTENTO`/`ARMADO`.

```
# cat /sys/module/arm_smmu/parameters/uke_smmu_probe    → N
# cat /sys/module/arm_smmu/parameters/uke_smr_max       → -1
# cat /sys/module/arm_smmu/parameters/uke_stream_match  → Y
```
Si alguna no existiera, parar (el nombre del módulo sería otro; no debe: §3).

### Paso 1 — la escalera (un disparo por peldaño)

Cada **disparo** es: fijar el peldaño, armar (el `.set` llama a `driver_deferred_probe_trigger()`
y el work reintenta el nodo YA) y leer migas hasta el desenlace:

```
# echo <PELDAÑO> > /sys/module/arm_smmu/parameters/uke_smr_max
# echo 1 > /sys/module/arm_smmu/parameters/uke_smmu_probe      # dispara el probe real
# dmesg | grep -E "UKE-POKE|arm-smmu"
```

| peldaño | comando | qué se aprende |
|---|---|---|
| **A** (reproducir K2) | `uke_smr_max` sin tocar (-1) | debe morir donde K2; deja el sistema igual que #P8 |
| **B** | `echo 0` | si muere, la última línea es `SMR[0] -> readl(0x800)` ⇒ **SMR(0) ya cuelga: es la región, no un índice**; si sobrevive (sale `SMR[0] = 0x…` y `SMR loop OK (leidos=1 …)`) ⇒ SMR(0) es legible |
| **C** | `echo 4`, luego `16`, `32`, `64`, `109` | bisección del índice mortal: la última miga `SMR[k] -> readl(0x…8…4k)` sin su línea `= 0x…` da el **k exacto**. Con `109` = barrido completo |
| **D** | `echo -2` | salta el barrido entero: si el probe pasa a `reset fase2 SMR/S2CR x110` y muere ahí, el problema es la **región SMR** (escritura del reset); si llega a `reset fase7`/bind, el barrido era el único precio |
| **E** | `echo 0 > …/uke_stream_match` (+ el `uke_smr_max` que se quiera) | **cero acceso a SMR** (ni barrido ni reset): `cfg_probe: uke_stream_match=0 -> apps-smmu forzado a STREAM-INDEXING sin SMR…`, luego `reset fase2 SMR/S2CR x110` (solo S2CR) y, si todo va bien, `iommu_device_register` ⇒ el nodo **binda** (`ls /sys/bus/platform/drivers/arm-smmu/` debe listar `15000000.apps-smmu`, y `dmesg` deja de tener `-EPROBE_DEFER`) |

**Entre peldaños que SOBREVIVEN** hay que forzar un probe nuevo (el nodo ya está bindeado y el
trigger del deferred probe no lo reencola):

```
# echo 15000000.apps-smmu > /sys/bus/platform/drivers/arm-smmu/unbind
# echo <PELDAÑO> > /sys/module/arm_smmu/parameters/uke_smr_max
# echo <PELDAÑO2> > /sys/module/arm_smmu/parameters/uke_stream_match   # si aplica
# echo 15000000.apps-smmu > /sys/bus/platform/drivers/arm-smmu/bind
```
(con `uke_smmu_probe` ya a 1, el bind entra directo al probe real: el `ya_diferido` del bloque
UKE-POKE es un static de módulo y ya está a true). Si el unbind se niega (hay consumidores
attachados) o algo queda raro, **reboot** y volver al paso 0: es el camino limpio (tras reboot el
param vuelve a 0 y hay que re-armar). Si un peldaño **cuelga la máquina**, hace falta ciclo de
alimentación: no hay forma de volver atrás en caliente.

Ojo con el orden: `echo 1 > uke_smmu_probe` ya dispara el probe (no hace falta el `bind`); el
`bind` a mano es el plan B por si el work del deferred probe se quedara atascado antes en otro
device (riesgo 1 del INFORME-K2-BUILD). Hacer los dos no rompe nada: el segundo devuelve
`-EEXIST`/`-EBUSY` si el primero ya bindeó.

### Paso 2 — lectura e interpretación

* `SMR[k] -> readl(0x8...)` sin la línea siguiente ⇒ **el read de SMR(k) cuelga** (índice k).
* Si k=0 ⇒ la **región SMR entera** está muerta desde el primer registro (0x800): encaja con la
  hipótesis TZ/XPU y con que el vendor no la lea (usa `qcom,handoff-smrs`).
* Si sale `SMR loop OK (leidos=110 validos=N)` ⇒ el barrido entero es viable y el cuelgue de K2
  era otra cosa (p. ej. el `pr_info` posterior o el reset); seguir con D/E.
* Tras el bind con E: `ls /sys/bus/platform/drivers/arm-smmu/` y `dmesg | grep -i "iommu group"`
  (los grupos se crean al re-sondear cada device; el mdss ya falló con -19 y **no** se
  re-sondea solo: para probar la traducción habría que unbind/bind del driver del display, y ahí
  el attach escribiría `S2CR(7168)` — §6.3).

---

## 6. Riesgos (los relevantes primero)

1. **La escalera A/B/C puede colgar la máquina en cada peldaño** (es el objetivo). Mitigación:
   doble captura, arranque sano verificado antes, y empezar por B (1 solo SMR) para acotar el
   daño; el peldaño A es el que ya se midió en #P8 (se puede saltar si se quiere ir directo a B).
2. **`-2` no es "cero SMR"**: el reset y `test_smr_masks` siguen tocando SMR (documentado arriba).
   Para eso está `uke_stream_match=0`.
3. **`uke_stream_match=0` cambia la semántica de matching**: el mdss (SID 0x1c00) pasaría a
   `S2CR(7168)` en `0x7c00`, fuera del banco de 110 S2CR probado. Si el hardware no implementa la
   S2CR plana de 2^15 entradas, el attach del mdss (si alguien re-sondea el display) puede colgar
   el bus — pero el **bind** en sí (lo que resuelve el -19) queda dentro del banco probado. Es la
   concesión que hace el cap a NUMSMRG=110 (\§2.2).
4. **`smmu->smrs == NULL` con SIDs altos**: `s2crs` se aloja con 32768 entradas para que ningún
   `s2crs[sid]` de 15 bits desborde; aun así, `arm_smmu_rmr_install_bypass_smr()`
   (`arm-smmu.c:2264-2310`) desreferencia `smmu->smrs[idx]` sin comprobar NULL. En este DT no hay
   IORT/RMR (`iort_get_rmr_sids()` devuelve lista vacía y el cuerpo del bucle no se ejecuta), así
   que no dispara; queda anotado como bug latente de mainline si algún día se usa con IORT.
5. **El barrido es funcional** (§1.2): saltarlo a producción exigiría parsear `qcom,handoff-smrs`
   del DT y sintetizar `smrs[]`/`s2crs[]`. Propuesta de seguimiento (no implementada en K3): un
   `uke_handoff_dt=1` que lea los pares sid/mask de la propiedad y rellene `smmu->smrs` como si se
   hubieran leído del hardware (el DT ya trae `<0x1c00 0x02>`; el SID del mdss).
6. **Los params son 0644 y se leen al vuelo**: cambiar `uke_smr_max`/`uke_stream_match` a mitad de
   un probe no hace nada (se leen al entrar); el valor que cuenta es el del siguiente barrido.

---

## 7. Qué NO se ha hecho

* No se ha flasheado nada ni se ha hablado con la tablet (sin adb/fastboot/ssh).
* `~/gpu-work` no se ha modificado (solo lecturas). `~` solo se ha recorrido en modo
  lectura para buscar el driver vendor; no hay implementación `handoff-smrs` en el disco.
* En `omarchy-uke` no se ha editado ningún fichero existente ni se ha commiteado: los únicos
  ficheros **nuevos de K3** son `build/bootimg/boot-ukek3.img` (ignorada por `.gitignore:25`),
  `build/gates/patches/k3-smr.diff` y este informe. (`build/pkg/panel-o82/`, sin commitear, es de
  otro agente; no se ha tocado.)
* No se ha usado `olddefconfig` (el `.config` del #82 se ha seguido usando tal cual).

## 8. Copias de trabajo y reproducibilidad

| ruta | contenido |
|---|---|
| `/tmp/uke-k1` → `/var/tmp/uke-k1` | árbol con **K1+K2+K3** (arm-smmu.c `3950a78b…`, arm-smmu-qcom.c `1c569b56…`) |
| `/tmp/uke-k1-build` → `/var/tmp/uke-k1-build` | `O=` (config del #82, `Image.gz` K3 `a1a23088…`, `vmlinux`, logs) |
| `/var/tmp/uke-k3/` | `build-k3.log`, y `repro/` (árbol de comprobación de los 3 parches) |
| `/tmp/uke-k3-repack.py`, `/tmp/uke-k3-repack-report.txt`, `/tmp/uke-k3-unpack/` | script de empaquetado, su log y el unpack de gates |

Cadena completa sobre el árbol prístino (solo lectura), con sha de cada paso — reproducida y
comparada byte a byte con el árbol de trabajo:

```
$ mkdir -p /var/tmp/uke-k3/repro/drivers/iommu/arm/arm-smmu && cp <pristino>/arm-smmu{,‑qcom}.c repro/drivers/iommu/arm/arm-smmu/
$ patch -p1 -d repro < build/gates/patches/k1-arm-smmu.diff
  arm-smmu.c      26a16af10206e70dbdedb967cfd22652001648c0a3da975587892913b3617787   (estado K1)
  arm-smmu-qcom.c 14ea069dbbd99316efbfde9cee8eed71501b4e757bb4cd1e90292b2be6ec87bc
$ patch -p1 -d repro < build/gates/patches/k2-arming.diff
  arm-smmu.c      87abc5265be9b33044fefb2779598d32d53b5d348befd7c5cee03fc6691dd020   (estado K2)
$ patch -p1 -d repro < build/gates/patches/k3-smr.diff
  arm-smmu.c      3950a78bbb527d9df6d018962a023914d5a33b1b66205c0979dc6e91013788a0   (estado K3 = árbol de trabajo)
  arm-smmu-qcom.c 1c569b565e52c07b4db1078a1acc3c14e09e5acea40230717232edd0caa50bf8
$ cmp repro/drivers/iommu/arm/arm-smmu/arm-smmu.c /var/tmp/uke-k1/drivers/iommu/arm/arm-smmu/arm-smmu.c        → IDÉNTICO
$ cmp repro/drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c /var/tmp/uke-k1/drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c → IDÉNTICO
```

Es decir: `k1-arm-smmu.diff` + `k2-arming.diff` + `k3-smr.diff`, en ese orden, reproducen
exactamente el árbol con el que se ha construido y empaquetado `boot-ukek3.img`.
