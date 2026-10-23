# INFORME-K1-BUILD — kernel K1 + dos `boot.img` (gate 0 / gate 1)

Fecha: 2026-09-28 (tarde). Autor: SG-K1-BUILD.
Objetivo: construir el kernel **K1** diseñado en `build/gates/INFORME-SMMU-CLK.md` §4.3.1
(K1 = aceptar `qcom,qsmmu-v500` + fix del defer + arming por token + migas) y empaquetar
**dos** `boot.img` listos para `boot_b`, **sin flashear nada**.

> Recordatorio operativo: aquí NO se ha tocado la tablet (ni adb, ni fastboot, ni ssh).
> `~/gpu-work` se ha usado SOLO en lectura. En `omarchy-uke` solo hay ficheros NUEVOS
> (sin commit; `git status` los muestra como `??`).

---

## 0. Entregables y shas

| fichero | bytes | sha256 |
|---|---|---|
| `build/bootimg/boot-ukek1-gate0.img` | 100663296 (96 MiB) | `83677679b9d8fedc07fd7326e9e710d5ba4e70c3cabd842327931392ca01d40e` |
| `build/bootimg/boot-ukek1-gate1.img` | 100663296 (96 MiB) | `a1eb174ecfb8176e1301f1d9084ad5be2ea4b83e0a786f472fc738065aad654c` |
| `build/gates/patches/k1-arm-smmu.diff` | 8149 B | (diff aplicado, 75 líneas añadidas / 1 sustituida) |
| kernel fuente del empaquetado | 16560891 B (`Image.gz`) | `304db709107bac786d03fee41a315a79cce4e63d9845a371f0d2f666de25c2ed` |
| kernel desempaquetado (`Image`) | 41355776 B = 39,44 MiB | (idéntico TAMAÑO al del #82) |

```
$ ls -la build/bootimg/boot-ukek1-gate*.img
-rw-r--r-- 1 usuario usuario 100663296 sep 28 21:02 boot-ukek1-gate0.img
-rw-r--r-- 1 usuario usuario 100663296 sep 28 21:02 boot-ukek1-gate1.img
$ sha256sum build/bootimg/boot-ukek1-gate0.img build/bootimg/boot-ukek1-gate1.img
83677679b9d8fedc07fd7326e9e710d5ba4e70c3cabd842327931392ca01d40e  boot-ukek1-gate0.img
a1eb174ecfb8176e1301f1d9084ad5be2ea4b83e0a786f472fc738065aad654c  boot-ukek1-gate1.img
```

---

## 1. Desviaciones de entorno (leer; son dos y están justificadas)

**(D1) `/tmp` es tmpfs de 7,7 GiB con solo 3,5 GiB libres** (`/tmp/opencode` ocupa 4,1 GiB, de otro
agente) y la RAM ya venía con 2,9 GiB libres y **swap al 98 %**. La copia del árbol (1,8 GiB) + el
`O=` de un build de kernel (~3 GiB) no caben y, en tmpfs, además son RAM. Se conservan **las rutas
pedidas** creando enlaces simbólicos al disco real (157 GiB libres):

```
$ ls -la /tmp/uke-k1 /tmp/uke-k1-build
lrwxrwxrwx ... /tmp/uke-k1 -> /var/tmp/uke-k1
lrwxrwxrwx ... /tmp/uke-k1-build -> /var/tmp/uke-k1-build
```

Todos los comandos de este informe usan literalmente `/tmp/uke-k1` y `/tmp/uke-k1-build`; el
almacenamiento real es `/var/tmp/*`. El árbol compartido sigue intacto (solo lectura).

**(D2) build con `-j8` en vez de `-j$(nproc)`=16.** Con 4,6 GiB disponibles y swap lleno, un
`-j16` de kernel (picos de 6-10 GiB) arriesgaba el OOM-killer sobre la sesión de escritorio del
usuario (firefox/ZCode). `-j8` tardó ~9 min (20:46:18 → 20:55:43) sin un solo OOM. La regla que
importa (§14.8 de LECCIONES) se respetó: `MAKE=` explícito, `ARCH=arm64`, `LLVM=1`, desprendido.

**Config:** se copió `~/gpu-work/ramaa/s10/build-s122/.config` tal cual y **no hizo falta
`olddefconfig`** (no hubo cambio de opciones; el `SYNC include/config/auto.conf` del arranque es el
automático de siempre):

```
$ sha256sum /tmp/uke-k1-build/.config ~/gpu-work/ramaa/s10/build-s122/.config
02354acedeea263654ff13073a7e5067d1fa24548bf0a69382149fb594f2fbdf  /tmp/uke-k1-build/.config
02354acedeea263654ff13073a7e5067d1fa24548bf0a69382149fb594f2fbdf  .../build-s122/.config
$ cmp /tmp/uke-k1-build/.config .../build-s122/.config && echo IDÉNTICO
IDÉNTICO byte a byte (no hubo olddefconfig)
$ grep -E "^CONFIG_(DRM_PANEL_XIAOMI_O82_DUALDSI|ARM_SMMU|ARM_SMMU_QCOM)" .config
CONFIG_DRM_PANEL_XIAOMI_O82_DUALDSI=y
CONFIG_ARM_SMMU=y
CONFIG_ARM_SMMU_QCOM=y
```

---

## 2. Copia del árbol y gate del bloque UKE-POKE

```
$ rsync -a --exclude=.git --exclude='*.o' --exclude='*.ko' --exclude='*.cmd' \
    --exclude='.tmp_versions' --exclude='*.mod' --exclude='*.mod.c' --exclude='*.mod.o' \
    ~/gpu-work/palawan-linux/ /tmp/uke-k1/
$ du -sh /tmp/uke-k1   →  1,8G
$ grep -n "UKE-POKE" /tmp/uke-k1/drivers/iommu/arm/arm-smmu/arm-smmu.c
2138: pr_info("UKE-POKE: arm_smmu_device_probe ENTRANDO, dev=%s\n", ...);
2163: pr_info("UKE-POKE: apps-smmu @%p base=0x%x: primer probe DIFFERIDO ...");
2168: pr_info("UKE-POKE: apps-smmu: REINTENTO del probe, consola ya viva...");
2240: pr_info("UKE-POKE: apps-smmu: -> arm_smmu_device_cfg_probe ...");
2281: pr_info("UKE-POKE: apps-smmu: -> arm_smmu_device_reset ...");
```

Gate PASS: el bloque UKE-POKE está en la copia (árbol original verificado, no se tocó).

---

## 3. Qué se aplicó exactamente (diff K1) y cada adaptación

Diff final: **`build/gates/patches/k1-arm-smmu.diff`** (2 ficheros, 75 líneas añadidas, 1
sustituida). Contenido obligatorio (a)-(d) del encargo, todo presente:

| pieza | dónde | estado |
|---|---|---|
| (a) `{ .compatible = "qcom,qsmmu-v500", .data = &arm_mmu500 }` | `arm_smmu_of_match` | aplicado |
| (a bis) `{ .compatible = "qcom,qsmmu-v500", .data = &qcom_smmu_500_impl0_data }` | `qcom_smmu_impl_of_match` | aplicado |
| (b) defer acepta `0x100000` **y** `0x200000` | bloque UKE-POKE de `arm_smmu_device_probe` | aplicado |
| (c) `early_param("uke_smmu_probe", ...)` + `uke_smmu_armado`; sin token: `-EPROBE_DEFER` + línea informativa | `arm-smmu.c` (junto a `force_stage`/`disable_bypass`) | aplicado |
| (d) migas `cfg_probe` tras ID0/ID1/ID2 + fases 1-7 del reset + migas de `qcom_smmu_cfg_probe` | `arm-smmu.c`, `arm-smmu-qcom.c` | aplicado |

### 3.1 Adaptaciones respecto al diff *literal* de §4.3.1 (todas cosméticas o de compilación)

1. **`+#include <linux/init.h>`** en `arm-smmu.c`: el fichero NO lo incluía y `early_param()` vive
   ahí. Sin esto no compila (no es un cambio semántico).
2. **Colocación del bloque del token**: tras `using_legacy_binding, using_generic_binding`
   (≈línea 70) y no entre el `module_param(disable_bypass)` y el `#define s2cr_init_val`. El diseño
   decía "junto a disable_bypass/force_stage (56-63)": misma zona, sin partir el bloque
   param+macro.
3. **La miga de ID1 va una línea más abajo** que en el diff literal: después de
   `smmu->pgshift = ...`. Así `pgshift` ya tiene valor en el `%u` (el diseño imprimía `pgshift`
   inmediatamente tras el read, cuando aún valía 0). El volcado del IDR sigue siendo el primero
   después de la lectura.
4. **Cast `(unsigned int)` en todos los `FIELD_GET`** impresos con `%u`: `FIELD_GET` devuelve
   `unsigned long` y el diseño mezclaba `%u`/`%lu`. Evita warnings de formato (no hay
   `CONFIG_WERROR`, pero se deja limpio). Verificado: **0 warnings** en los dos ficheros.
5. **`n_validos`**: el diseño imprimía `validos=%u` con una variable que **no existía** en
   `qcom_smmu_cfg_probe`. Se añadió `unsigned int n_validos = 0;` y el `n_validos++` dentro del
   `if (FIELD_GET(ARM_SMMU_SMR_VALID, smr))`.
6. **`mmio=%u B` = `smmu->numpage`** tal cual (es `unsigned int`): en ese punto es el tamaño CRUDO
   del recurso (`arm-smmu.c:2258` en la copia parcheada, `smmu->numpage = resource_size(res)`),
   antes de que ID1 lo reescriba (línea `smmu->numpage = size`). Es el dato que distingue "el DT
   mapea 0x200000" de "0x100000".
7. **Comentarios** `UKE-SMMU-CLK` reescritos (mismo contenido) y con dos datos medidos de hoy: el
   `of_match` aclara que el kgsl del mismo DT ya trae `"arm,mmu-500"` (por eso ya se probea hoy y
   K1 no lo cambia), y el de `qcom_smmu_impl_of_match` que la rama adreno se elige antes
   (`arm-smmu-qcom.c:707`).
8. El resto del diff (`fase1..fase7`, `desarmado`, `VOY a ESCRIBIR S2CR`, `relectura`, `leyendo
   SMR`, `SMR loop OK`, `VOY a leer ID0/ID1/ID2`) es **literal** al diseño.

### 3.2 Dato del DT que hace crítico el punto (b)

`/tmp/s257-final.dts` (dtbo vigente) y `/tmp/g2/merged-s257.dts` (DT fusionado real):

```
apps-smmu@15000000: compatible = "qcom,qsmmu-v500";  reg = <0x15000000 0x200000>;  uke,canary-smmu = <0x01>;
kgsl-smmu@3da0000:  compatible = "qcom,palawan-smmu-500", "qcom,adreno-smmu", "qcom,smmu-500", "arm,mmu-500";
```

Es decir: **el dtbo vigente mapea 2 MiB** (variante A′). Sin el fix (b), la condición de defer
`size == 0x100000` sería falsa con el DT actual y el probe habría corrido de verdad en el
arranque (~0,5 s), sin consola: exactamente el wedge mudo que se quiere evitar. Con el fix, el
defer dispara igual (se aceptan ambos tamaños) y el gate 0 es seguro con *cualquiera* de los dos
dtbo (0x100000 o 0x200000).

---

## 4. Build — comando exacto y gates

```
$ setsid nohup env MAKE=/usr/bin/make /usr/bin/make -C /tmp/uke-k1 O=/tmp/uke-k1-build \
    ARCH=arm64 LLVM=1 -j8 Image.gz  >> /tmp/uke-k1-build/build.log 2>&1 &
$ head -4 /tmp/uke-k1-build/build.log
== K1 build ==
cmd: MAKE=/usr/bin/make make -C /tmp/uke-k1 O=/tmp/uke-k1-build ARCH=arm64 LLVM=1 -j8 Image.gz
start: 2026-09-28T20:46:18+02:00
tree: /tmp/uke-k1 -> /var/tmp/uke-k1
$ tail -4 /tmp/uke-k1-build/build.log
  OBJCOPY arch/arm64/boot/Image
  GZIP    arch/arm64/boot/Image.gz
make[1]: se sale del directorio '/var/tmp/uke-k1-build'
make: se sale del directorio '/var/tmp/uke-k1'
$ grep -cE "^ERROR|error:" /tmp/uke-k1-build/build.log
0
```

Gate rc=0 con re-ejecución idempotente (prueba de que el build está completo y no fue un no-op):

```
$ sha256sum Image.gz > /tmp/k1-sha-before.txt
$ /usr/bin/make -C /tmp/uke-k1 O=/tmp/uke-k1-build ARCH=arm64 LLVM=1 MAKE=/usr/bin/make Image.gz; echo RC=$?
RC=0
$ sha256sum -c /tmp/k1-sha-before.txt
/tmp/uke-k1-build/arch/arm64/boot/Image.gz: La suma coincide   ← "no-op" real, nada que rehacer
```

| gate | comando | salida |
|---|---|---|
| toolchain | `grep -o "clang[^;]*arm-smmu.c" .../.arm-smmu.o.cmd` | `clang -Wp,-MMD,... -nostdinc -I/var/tmp/uke-k1/arch/arm64/include ...` |
| arquitectura | `file arch/arm64/boot/Image` | `Linux kernel ARM64 boot executable Image, little-endian, 4K pages` |
| banner | `strings Image \| grep "Linux version"` | `Linux version 7.2.0-rc2-palawan (usuario@pc-build) (clang version 22.1.8, LLD 22.1.8) #1 SMP PREEMPT Mon Sep 28 20:55:43 CEST 2026` |
| tamaño gz | `ls -la .../Image.gz` | 16560891 B (el #82: 16559711 B → **+1180 B**) |
| tamaño crudo | `python3 (gzip.decompress)` | 41355776 B = 39,44 MiB — **idéntico al `Image` del #82** (41355776) |
| contenido | `strings Image.gz-descomprimido \| grep -c UKE-POKE` | **22** (≥6 exigido) |
| token | `grep -c uke_smmu_probe` en el Image | 2 (nombre del param + texto de "desarmado") |
| compat vendor | `grep -c "qcom,qsmmu-v500"` | 2 (of_match + impl_match) |
| **`nm -u` del .o** | `nm -u drivers/iommu/arm/arm-smmu/arm-smmu.o \| grep of_property` | `U of_property_read_u32_index` |
| migas en el .o | `strings arm-smmu.o \| grep -c UKE-POKE` | 16 |
| sin warnings | `grep -i warn` sobre líneas de arm-smmu*.o | (ninguna) |

Cadenas relevantes presentes en el **binario final** (`arm-smmu: ` lo pone `pr_fmt`):

```
arm-smmu: UKE-POKE: arm_smmu_device_probe ENTRANDO, dev=%s
arm-smmu: UKE-POKE: apps-smmu @%p base=0x%x: primer probe DIFFERIDO para que el reintento caiga con la consola viva
arm-smmu: UKE-POKE: apps-smmu: desarmado (falta uke_smmu_probe=1); no se toca el bloque. Arranque sano.
arm-smmu: UKE-POKE: apps-smmu: REINTENTO del probe, consola ya viva. Lo que viene a continuación es el probe de verdad.
arm-smmu: UKE-POKE: cfg_probe ID0=0x%08x (SMS=%u groups)
arm-smmu: UKE-POKE: cfg_probe ID1=0x%08x pgshift=%u NUMPAGENDXB=%u CBs=%u; CB base=0x%llx (mmio=%u B)
arm-smmu: UKE-POKE: cfg_probe ID2=0x%08x
arm-smmu: UKE-POKE: reset fase1 sGFSR … fase7 tlb_sync_global + write sCR0
UKE-POKE: qcom_cfg_probe: VOY a ESCRIBIR S2CR(0x%x) reg=0x%08x / relectura=0x%08x (TYPE=%u; quirk=%s) /
          leyendo SMR(0..%u) / SMR loop OK (validos=%u)
```

---

## 5. Empaquetado (patrón del hermano, sin tocar su árbol)

Script adaptado: `/tmp/uke-k1-repack.py` (derivado de `ramaa/s21/s244-boot-repack.py`, que se leyó
y NO se modificó). Shell de partida: `ramaa/s21/avb/boot-s240-mem2g.img`
(sha256 `e3c60969269c0b36f23a37db5b1772128891232517c8d7979bd967b88acab206`), el MISMO shell del
`boot-s244-bounce.img` que está hoy en `boot_b`:

```
$ s244 vs shell: difieren solo en kernel_size@8 y la región del kernel; cmdline y footer AVB
  idénticos byte a byte  (gate del script)
$ python3 /tmp/uke-k1-repack.py
kernel K1: 16560891 B gz (sha16 304db709107bac78), 22 cadenas UKE-POKE, token+desarmado+fases OK
s244 == shell + kernel (solo kernel y kernel_size cambian; cmdline y footer identicos)  OK
shell boot-s240-mem2g.img sha256 e3c60969269c0b36... OK; cmdline s244 255 B exacta; kernel base 16560041 B
== boot-ukek1-gate0.img ==  sha256 83677679b9d8fedc07fd7326e9e710d5ba4e70c3cabd842327931392ca01d40e
== boot-ukek1-gate1.img ==  sha256 a1eb174ecfb8176e1301f1d9084ad5be2ea4b83e0a786f472fc738065aad654c
gate0 vs boot_b de hoy: 16491842 bytes distintos (kernel_size@8+kernel [4096,35438592)); cmdline y footer identicos  OK
gate0 vs gate1: 17 bytes distintos, todos en la cmdline [299,315)  OK
unpack_bootimg gate0: kernel == build OK;  avbtool info_image gate0: rc=0 (footer AVB0+AVBf)  OK
unpack_bootimg gate1: kernel == build OK;  avbtool info_image gate1: rc=0 (footer AVB0+AVBf)  OK
GATE COMPLETO: OK
```

Gates por imagen (evidencia independiente):

```
$ ls -la build/bootimg/boot-ukek1-gate{0,1}.img        → 100663296 B los dos (96 MiB exactos)
$ dd if=... bs=1 skip=8 count=4 | od -An -tu4          → 16560891 (= kernel_size del build)
$ dd if=... bs=1 skip=35438592 count=4                 → AVB0     (inicio de la firma)
$ dd if=... bs=1 skip=$((100663296-64)) count=4        → AVBf     (footer AVB)
$ unpack_bootimg --boot_img boot-ukek1-gate0.img --out ...
  kernel_size: 16560891
  command line args: mem=2048M rdinit=/ukeinit panic=10 memmap=0x1A12800$0xE3940000 console=tty0
    fbcon=map:0 hung_task_timeout_secs=20 hung_task_panic=1 watchdog_thresh=10 console=ttyGS0,115200
    fw_devlink=permissive clk_ignore_unused pd_ignore_unused arm-smmu.disable_bypass=0
$ unpack_bootimg --boot_img boot-ukek1-gate1.img ...
  command line args:  ídem + " uke_smmu_probe=1" al final
$ python3 -c "... gate1 cmdline: len 272, count token 1, termina en token: True"
```

**Longitud y encaje del token (punto que pedía el encargo):** la cmdline del s244 son **255 B** en
el campo contiguo `cmdline[512] + extra_cmdline[1024]` = **1536 B** de la cabecera v4
(`offset 44..1580`; tras el NUL todo son ceros). El token `" uke_smmu_probe=1"` son **17 B** →
**272 B**, NUL-terminado, con 1264 B de sobra: **cabe en el mismo campo**, no hizo falta usar ningún
hueco aparte. El límite del kernel es mayor: `COMMAND_LINE_SIZE = 2048` en arm64
(`arch/arm64/include/uapi/asm/setup.h:25`). Verificado con `unpack_bootimg` (arriba) y por bytes.

Las dos imágenes difieren **solo** en 17 bytes (la cmdline, offsets absolutos 299..315), así que
gate 0 y gate 1 comparten kernel, shell, cmdline-base y footer.

---

## 6. Cómo validar el gate 0 en la tablet (kernel vivo, SMMU diferido)

Del lado de la tablet (lo ejecuta quien flashee, NO este agente):

1. `fastboot flash boot_b build/bootimg/boot-ukek1-gate0.img` + `fastboot reboot`, con el **mismo
   dtbo s257** ya vigente y `boot_b` en el slot b. Un solo lector de consola
   (`REGLA-UN-SOLO-LECTOR.md`), `dmesg -n 7` al inicio (el guion del hermano ya lo hace).
2. Gate de "kernel vivo": banner NUEVO
   `Linux version 7.2.0-rc2-palawan ... clang version 22.1.8, LLD 22.1.8 #1 SMP PREEMPT Mon Sep 28 20:55:43 CEST 2026`
   y el arranque llega a userspace como el s244.
3. Gate del SMMU ("diferido para siempre"): deben aparecer
   * `arm-smmu: UKE-POKE: arm_smmu_device_probe ENTRANDO, dev=...`
   * `arm-smmu: UKE-POKE: apps-smmu @<ptr> base=0x15000000: primer probe DIFFERIDO ...`
   * y, en el reintento de `late_initcall_sync`, `...: desarmado (falta uke_smmu_probe=1); no se
     toca el bloque. Arranque sano.`
   * **NO** debe aparecer `REINTENTO del probe, consola ya viva` (eso significaría que el token
     está puesto) ni ninguna miga `cfg_probe`/`reset faseN` **de apps-smmu**.
4. **Cómo no confundirse con el kgsl**: `kgsl-smmu@3da0000` ya se probea de verdad hoy (su
   compatible incluye `"arm,mmu-500"`, medido en `/tmp/g2/merged-s257.dts`), así que en gate 0
   SALDRÁN sus propias líneas (`ENTRANDO dev=3da0000.kgsl-smmu`, `cfg_probe ID0/1/2`, `reset
   fase1..7`) — no son de apps-smmu. La frontera es la línea `REINTENTO`: a partir de ahí lo que
   imprima es apps-smmu. Con token OFF, tras el `REINTENTO` (que no existe) no hay nada.
5. Para leer todo: `dmesg | grep -E "UKE-POKE|arm-smmu"`.

Interpretación (árbol de decisión de §5 del INFORME-SMMU-CLK): banner + `ENTRANDO` de ambos +
`DIFFERIDO`/`desarmado` de apps-smmu ⇒ **KERNEL VIVO**; se puede pasar al gate 1 (mismo binario,
misma imagen + token), donde todo lo que imprima apps-smmu antes del cuelgue es el diagnóstico.

---

## 7. Riesgos (lo que hay que saber antes de flashear el gate 0)

**El mayor riesgo del gate 0 es el propio Image nuevo, no el SMMU.** El delta funcional respecto
al binario que arranca hoy está acotado a:

1. **el nodo apps-smmu pasa de "sin driver" a "con driver que difiere siempre"**. Los consumidores
   (mdss, UFS…) no distinguen ambos estados: en los dos casos el driver **nunca registra las ops**
   (`iommu_device_register` está en `arm-smmu.c:2347` de la copia parcheada, DESPUÉS de los
   `return -EPROBE_DEFER` del bloque UKE-POKE, `arm-smmu.c:2208-2223`), y `iommu_fwspec_init()`
   devuelve `driver_deferred_probe_check_state()`
   (`drivers/iommu/iommu.c:3078-3079`) tanto si el nodo no matchea como si difiere. Con
   `fw_devlink=permissive` (ya en la cmdline) los enlaces de proveedor no bloquean. Y con el token
   OFF el driver hace **cero MMIO**: no hay ningún acceso al bloque que pueda colgar;
2. las migas `pr_info` (nivel 6; solo visibles con `dmesg -n 7`).

Por tanto, si el gate 0 va mal, lo más probable es que sea el Image en sí (regresión del build) o el
camino de flasheo/slot — no el experimento del SMMU. Antecedente a tener presente: el Image de
`build/kernel-pokes` dio **cuatro arranques mudos** (§6.1 del INFORME-SMMU-CLK), pero con OTRO
config (75 opciones distintas) y en el **slot A**; este build usa el config del #82 (idéntico byte
a byte) y el tamaño del `Image` descomprimido coincide exactamente con el del #82, lo que acota
mucho esa clase de fallo. Aun así, el gate 0 es precisamente el instrumento para separar "el Image
no arranca" de "el probe del SMMU cuelga": **no se debe gastar el gate 1 sin un gate 0 verde**.

Riesgo secundario (de diseño, ya conocido): si el token llegase a la cmdline por error
(p. ej. copiando la imagen equivocada), el probe de apps-smmu correría a los ~30 s con el sistema
vivo; el gate 0 se distingue sin ambigüedad por la presencia de `desarmado` y la ausencia de
`REINTENTO`.

---

## 8. Qué NO se ha hecho

- No se ha flasheado nada, ni se ha hablado con la tablet (sin adb/fastboot/ssh).
- `~/gpu-work` no se ha modificado (ni el árbol compartido, ni `ramaa/s21/*`): solo lecturas.
  El script del hermano vive adaptado en `/tmp/uke-k1-repack.py`.
- En `omarchy-uke` no se ha editado ningún fichero existente ni se ha commiteado: solo se han
  creado `build/bootimg/boot-ukek1-gate{0,1}.img` (ignoradas por git:
  `$ git check-ignore -v build/bootimg/boot-ukek1-gate0.img` → `.gitignore:25:build/bootimg/*.img`),
  `build/gates/patches/k1-arm-smmu.diff` y este informe (`git status --short` los deja como `??`).
- No se ha usado `olddefconfig` (el config bueno se usó tal cual, verificado por sha).

## 9. Copias de trabajo (se pueden borrar cuando ya no hagan falta)

| ruta | tamaño | contenido |
|---|---|---|
| `/tmp/uke-k1` → `/var/tmp/uke-k1` | 1,8 G | copia del árbol con K1 aplicado |
| `/tmp/uke-k1-build` → `/var/tmp/uke-k1-build` | 3,1 G | `O=` (`.config` bueno + `build.log` + `Image.gz` + `vmlinux`) |
| `/tmp/uke-k1-repack.py`, `/tmp/uke-k1-repack-report.txt`, `/tmp/uke-k1-arm-smmu.diff` | KB | script de empaquetado, su log y el diff |

Reproducibilidad del diff entregado (aplica limpio sobre el árbol compartido, sin tocarlo):

```
$ patch -p1 --dry-run -d <copia-pristina> < build/gates/patches/k1-arm-smmu.diff
checking file drivers/iommu/arm/arm-smmu/arm-smmu.c
checking file drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c
RC=0
```
