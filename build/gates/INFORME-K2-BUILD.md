# INFORME-K2-BUILD — kernel K2: arming del apps-smmu por `module_param` escribible en caliente (+ `boot-ukek2.img`)

Fecha: 2026-09-28 (noche). Autor: SG-K2.
Objetivo: **K2 = K1** con el **arming del probe del apps-smmu cambiado de token en cmdline a
parámetro de módulo escribible en caliente**. El K1 (build de las 20:55) muere pre-consola cuando
el token va en la cmdline: con `uke_smmu_probe=1` el reintento del deferred probe entra demasiado
pronto (~late_initcall), antes de que la consola/SSH estén vivos. K2 invierte el orden: **nada en
la cmdline**, el arranque es el del s244 (s258 + panel vivo, dpu -19 como hoy) y el experimento se
arma **desde el sistema vivo** con un `echo`. Las migas del K1 (ID0/ID1/ID2, fases 1-7, S2CR/SMR)
se quedan tal cual y ahora llegan a la consola antes de cualquier cuelgue.

> Recordatorio operativo: aquí **NO** se ha tocado la tablet (ni adb, ni fastboot, ni ssh).
> `~/gpu-work` se ha usado **solo en lectura**. En `omarchy-uke` solo hay ficheros **NUEVOS**
> (sin commit; `git status` los muestra como `??` y la imagen está ignorada por `.gitignore:25`).

---

## 0. Entregables y shas

| fichero | bytes | sha256 |
|---|---|---|
| `build/bootimg/boot-ukek2.img` | 100663296 (96 MiB exactos) | `62553cc3fda56ccdba65ec87b579dd053de2faceeba3be21d631f7461a606ebd` |
| `build/gates/patches/k2-arming.diff` | 6623 B, 145 líneas, 3 hunks, 1 fichero (+87/−17) | `f4b8597bc4e188bf808c48e21bd14bcc9df65f57d14af03a66556c13d6f8cbaf` |
| kernel fuente del empaquetado (`Image.gz`) | 16561740 B | `f85153dc0fb8eaa3e2676dabe49568e65e2647573be1c86aaca4a7b5015952ed` |
| kernel desempaquetado (`Image`) | 41355776 B = 39,44 MiB | (mismo TAMAÑO que el K1 y que el #82, delta 0) |
| fuente `arm-smmu.c` de K2 (una sola pieza tocada) | 77360 B | `87abc5265be9b33044fefb2779598d32d53b5d348befd7c5cee03fc6691dd020` |

```
$ ls -la build/bootimg/boot-ukek2.img
-rw-r--r-- 1 usuario usuario 100663296 sep 28 21:22 build/bootimg/boot-ukek2.img
$ sha256sum build/bootimg/boot-ukek2.img build/gates/patches/k2-arming.diff
62553cc3fda56ccdba65ec87b579dd053de2faceeba3be21d631f7461a606ebd  build/bootimg/boot-ukek2.img
f4b8597bc4e188bf808c48e21bd14bcc9df65f57d14af03a66556c13d6f8cbaf  build/gates/patches/k2-arming.diff
$ git status --short
?? build/gates/patches/k2-arming.diff
?? build/gates/INFORME-K2-BUILD.md
$ git check-ignore -v build/bootimg/boot-ukek2.img
.gitignore:25:build/bootimg/*.img	build/bootimg/boot-ukek2.img
```

---

## 1. El cambio K2, exacto

**Una sola pieza tocada**: `drivers/iommu/arm/arm-smmu/arm-smmu.c`. `arm-smmu-qcom.c` queda
byte a byte igual al del K1 (comprobado, §8). Diff completo: `build/gates/patches/k2-arming.diff`.
Tres ediciones + una declaración externa:

| # | dónde (líneas en la copia K2) | qué |
|---|---|---|
| 1 | `arm-smmu.c:73-147` (bloque del param) | fuera `early_param`; entra `module_param_cb(uke_smmu_probe, …)` con perm **0644**, `MODULE_PARM_DESC` y un `.set` que guarda el valor **y llama a `driver_deferred_probe_trigger()`**; `extern void driver_deferred_probe_trigger(void);`; helper `uke_smmu_es_apps()`; variable del rate-limit |
| 2 | `arm-smmu.c:2282-2302` (bloque defer) | mientras `!uke_smmu_armado`: defer + print `desarmado (echo 1 > /sys/module/arm_smmu/parameters/uke_smmu_probe)` **limitado a 1/s con jiffies** (el primero sale siempre) |
| 3 | `arm-smmu.c:1837-1847` (`cfg_probe`) | miga nueva **justo antes de leer ID0** (el primer MMIO del probe real): `UKE-POKE: ARMADO — probe real del apps-smmu, lo que sigue puede colgar` |

Lo que **NO** se ha tocado (se queda del K1, como pedía el encargo): el `of_match`
`qcom,qsmmu-v500` (las dos tablas), el defer que acepta `0x100000`/`0x200000`, las migas
`ENTRANDO`/`DIFFERIDO`/`REINTENTO`/`cfg_probe ID0/ID1/ID2`/`fases 1-7`/`qcom_cfg_probe`, el
`#include <linux/init.h>` que añadió K1 (inofensivo: `module.h` lo re-incluye) y todo
`arm-smmu-qcom.c`.

### 1.1 Por qué `module_param_cb` y no `module_param_named`

El encargo pedía el nombre `uke_smmu_probe` con permiso 0644 y, además, que el armado **fuerce el
reintento**. Con `module_param_named` no hay callback: no se puede disparar nada al escribir. Se usa
`module_param_cb` con `ops = { .set = uke_smmu_probe_set, .get = param_get_bool }`, donde el `.set`
hace `param_set_bool(val, kp)` (la misma semántica `y/Y/1` que el resto del kernel; acepta el `\n`
del `echo` porque `kstrtobool` mira `s[0]`) y luego, solo si el valor es 1, dispara el reintento.
Efecto en sysfs: **idéntico** al que habría tenido `module_param_named` (misma entrada, mismo
`0644`, `cat` devuelve `Y`/`N`).

### 1.2 Por qué `driver_deferred_probe_trigger()` y no otra vía

* `driver_deferred_probe_trigger()` (`drivers/base/dd.c:189`) mueve la **lista de pendientes a la
  activa y encola el work** del deferred probe: el nodo apps-smmu, que lleva difiriéndose desde el
  arranque, se reintenta **inmediatamente** con el probe real.
* **No está exportada a módulos**: en `dd.c` solo `driver_deferred_probe_check_state()` lleva
  `EXPORT_SYMBOL_GPL` (`dd.c:312`); la declaración pública está en `drivers/base/base.h:245`, que es
  privado de `drivers/base`. Por eso se declara a mano (`extern`, línea 113). Es legal porque
  `arm_smmu` es **built-in** (`CONFIG_ARM_SMMU=y`): el símbolo se resuelve al enlazar contra
  `vmlinux` (`nm vmlinux` → `T driver_deferred_probe_trigger`; `nm -u arm-smmu.o` → `U
  driver_deferred_probe_trigger`). Si alguien compilara `=m`, modpost lo rechazaría: queda anotado
  en el propio comentario del código.
* La función se protege sola: con `driver_deferred_probe_enable == false` (antes de
  `late_initcall`, `dd.c:358`) retorna sin tocar nada; así un armado temprano (p. ej. desde la
  cmdline, ver §6) no dispara nada antes de tiempo.
* **Es deliberado NO hacer `flush_work`**: el `echo 1` vuelve en el acto y la sesión SSH sobrevive
  aunque el probe real se cuelgue. Alternativas descartadas: `device_reprobe()`/`device_attach()`
  sobre el device concreto (requiere guardar el `struct device *` y su refcount; más código y más
  superficie de error) y escribir en `/sys/bus/platform/drivers/arm-smmu/bind` (depende del nombre
  exacto del device y no retira el nodo de la lista de diferidos).

### 1.3 El límite de prints

El deferred probe reintenta el nodo **cada vez que otro driver se bindea** (el nodo vuelve a la
lista de pendientes). Con el token quitado, sin límite la consola se llenaría de la misma línea.
Se usa jiffies: `if (!uke_smmu_ultimo_print || time_after(jiffies, uke_smmu_ultimo_print + HZ))`
→ **máximo 1 línea/s**, y la **primera siempre sale** (el contador arranca a 0). No se usa
`printk_once`/`pr_info_once` a propósito: interesa ver *que sigue vivo y desarmado* en cada
reintento, no solo la primera vez. `jiffies`/`time_after`/`HZ` ya están disponibles
(`<linux/delay.h>` y `<linux/pm_runtime.h>` incluyen `jiffies.h`): no ha hecho falta ningún include
nuevo.

### 1.4 El nombre del módulo en sysfs: **`arm_smmu`** (verificado, no asumido)

El driver se llama `arm-smmu` (prefijo de las migas vía `pr_fmt`), pero el parámetro cuelga del
**módulo**, cuyo `KBUILD_MODNAME` es **`arm_smmu`** (guiones → guiones bajos; el Makefile del
directorio es un objeto compuesto `arm_smmu-objs`). El `.cmd` del build lo confirma:

```
$ grep -o "\-DKBUILD_MODNAME=[^ ]*" .../.arm-smmu.o.cmd | head -1
-DKBUILD_MODNAME='"arm_smmu"'
```

Y hay **evidencia dura en el binario**: la tabla `__param` del `Image` contiene las dos entradas
seguidas (así crea `param_sysfs_builtin()` los params de lo built-in, cortando por el primer punto
de `kernel_param->name`):

```
$ python3 -c "…raw.count(b'arm_smmu.disable_bypass\x00arm_smmu.uke_smmu_probe\x00')…"
1
```

⇒ ruta final: **`/sys/module/arm_smmu/parameters/uke_smmu_probe`** (vecina del ya existente
`…/parameters/disable_bypass`, que este kernel ya trae).

Y el reverso, para probar que el `early_param` **ya no está**: en el K1 la cadena
`uke_smmu_probe` vivía en la tabla de `__setup`/early params (pegada a `iommu.passthrough`); en el
K2 ya no está ahí:

```
cruce K1/K2: K1 tenia early_param (tabla __setup) y 0 'arm_smmu.uke_smmu_probe'; K2 al reves  OK
cruce K1/K2: K1 decia 'falta uke_smmu_probe=1', K2 ya no (ahora cita la ruta sysfs)  OK
```

---

## 2. Mecánica verificada en el árbol (no asumida)

Todo comprobado leyendo el árbol de K2 (mismo `drivers/base/dd.c` que el K1, ya venía instrumentado
con `X9WAVE-try`/`uke_poke` por el proyecto):

| pieza | dónde | dato |
|---|---|---|
| el nodo se añade a la lista de diferidos | `dd.c:915` (`driver_deferred_probe_add`) tras el `-EPROBE_DEFER` del probe | sí: el probe de apps-smmu devuelve `-EPROBE_DEFER` |
| `dev_can_match` está puesto **antes** del probe | `dd.c:871` (`dev_set_can_match`, en `__driver_probe_device`) | sí: el `add()` no se descarta |
| el trigger | `dd.c:189-209` | mueve pending→active + `queue_work` |
| guard del trigger | `dd.c:191` `if (!driver_deferred_probe_enable) return;` | se habilita en `dd.c:358` (`late_initcall`); **nunca se vuelve a deshabilitar** |
| timeout de 10 s | `CONFIG_DRIVER_DEFERRED_PROBE_TIMEOUT=10`, `dd.c:305-330` | al expirar hace trigger+flush y **avisa**, pero **no vacía la lista ni deshabilita los triggers** ⇒ a los 10 s el nodo sigue pendiente y retryable |
| el work reintenta | `dd.c:137` `bus_probe_device(dev)` | vuelve a entrar en `arm_smmu_device_probe` |
| la función no está exportada | `dd.c:312` solo `driver_deferred_probe_check_state`; `base.h:245` | de ahí el `extern` (built-in) |
| `param_set_bool`/`param_get_bool` | `kernel/params.c:310-325`, ambos `EXPORT_SYMBOL` | usados por el `.set`/`.get` |

Flujo del arming (lo que verá el operador):

1. Alguien escribe `1` → `param_attr_store` (`kernel/params.c:577`) → nuestro `.set` (contexto de
   proceso del que escribe, con el mutex de params del módulo cogido; el trigger no bloquea).
2. `.set` imprime `UKE-POKE: arming en caliente: uke_smmu_probe=1` y llama al trigger.
3. El work del deferred probe recorre los pendientes (imprimiendo `X9WAVE-try <dev>`); al llegar al
   apps-smmu entra en `arm_smmu_device_probe` y el bloque UKE-POKE **ahora sí** imprime
   `REINTENTO del probe, consola ya viva`.
4. El probe sigue: DT, `devm_*`, clocks → y como **primer MMIO** la lectura de ID0, precedida de la
   miga `ARMADO`.
5. Desde ahí, todas las migas del K1 (`ID0/ID1/ID2`, `S2CR`, `SMR`, `fases 1-7`) hasta el desenlace.

---

## 3. Build — comando exacto y gates

Incremental sobre el `O=` del K1 (solo se recompila `arm-smmu.o` + relink):

```
$ setsid nohup env MAKE=/usr/bin/make /usr/bin/make -C /tmp/uke-k1 O=/tmp/uke-k1-build \
    ARCH=arm64 LLVM=1 -j8 Image.gz  >> /var/tmp/uke-k2/build-k2.log 2>&1 &
$ head -5 /var/tmp/uke-k2/build-k2.log
== K2 build ==
cmd: MAKE=/usr/bin/make make -C /tmp/uke-k1 O=/tmp/uke-k1-build ARCH=arm64 LLVM=1 -j8 Image.gz
start: 2026-09-28T21:19:26+02:00
tree: /tmp/uke-k1 -> /var/tmp/uke-k1
arm-smmu.c sha256: 87abc5265be9b33044fefb2779598d32d53b5d348befd7c5cee03fc6691dd020
$ tail -3 /var/tmp/uke-k2/build-k2.log
  OBJCOPY arch/arm64/boot/Image
  GZIP    arch/arm64/boot/Image.gz
make: se sale del directorio '/var/tmp/uke-k1'
$ grep -cE "^ERROR|error:" /var/tmp/uke-k2/build-k2.log   →  0     (y 0 "warning")
$ ls -la .../arm-smmu.o   →  395264 B, 21:19 (recompilado; el K1 era de las 20:52)
```

Gate rc=0 con re-ejecución idempotente (prueba de que no fue un no-op a medias):

```
$ sha256sum Image.gz > /tmp/k2-sha-before.txt
$ /usr/bin/make -C /tmp/uke-k1 O=/tmp/uke-k1-build ARCH=arm64 LLVM=1 MAKE=/usr/bin/make Image.gz; echo RC=$?
RC=0
$ sha256sum -c /tmp/k2-sha-before.txt
/tmp/uke-k1-build/arch/arm64/boot/Image.gz: La suma coincide
```

| gate | comando | salida |
|---|---|---|
| toolchain | `head -c 220 .../.arm-smmu.o.cmd` | `clang -Wp,-MMD,… -nostdinc -I/var/tmp/uke-k1/arch/arm64/include …` |
| arquitectura | `file arch/arm64/boot/Image` | `Linux kernel ARM64 boot executable Image, little-endian, 4K pages` |
| cabecera ARM64 | magic @56 | `0x644d5241` |
| banner | `strings Image \| grep "#2 SMP"` | `Linux version 7.2.0-rc2-palawan (usuario@pc-build) (clang version 22.1.8, LLD 22.1.8) #2 SMP PREEMPT Mon Sep 28 21:19:35 CEST 2026` (K1: `#1 … 20:55:43`) |
| tamaño gz | `ls -la .../Image.gz` | 16561740 B (K1: 16560891 → **+849 B**) |
| tamaño crudo | `gzip.decompress` | 41355776 B — **idéntico al K1** (41355776) y al `Image` del #82 |
| contenido | `raw.count(b"UKE-POKE")` | **24** (K1: 22; ≥22 exigido) |
| migas nuevas | `raw.count(...)` | `arming en caliente`=1, `ARMADO`=1, `/sys/module/arm_smmu/parameters/uke_smmu_probe`=1 |
| param en sysfs | tabla `__param` | `arm_smmu.disable_bypass\0arm_smmu.uke_smmu_probe` presente |
| early_param fuera | tabla `__setup` | `uke_smmu_probe\0iommu.passthrough` **ausente** (en K1 presente) |
| `nm -u` del `.o` | `nm -u …/arm-smmu.o \| grep deferred` | `U driver_deferred_probe_trigger` (+ `U param_set_bool`, `U param_get_bool`) |
| enlace built-in | `nm vmlinux \| grep -w driver_deferred_probe_trigger` | `T driver_deferred_probe_trigger` |
| migas en el `.o` | `strings arm-smmu.o \| grep -c UKE-POKE` | 18 |
| sin warnings | `grep -ci warning` sobre el log | 0 (y 0 errores) |

---

## 4. Empaquetado (`boot-ukek2.img`)

Script: `/tmp/uke-k2-repack.py` (adaptado del `/tmp/uke-k1-repack.py`, que a su vez deriva del
`ramaa/s21/s244-boot-repack.py` del hermano; su árbol NO se ha tocado). Shell de partida:
`ramaa/s21/avb/boot-s240-mem2g.img` (sha256 `e3c60969269c0b36…`, el mismo del `boot-s244-bounce.img`
que está hoy en `boot_b`). **Una sola imagen, con la cmdline del s244 EXACTA (255 B, SIN token).**

```
$ python3 /tmp/uke-k2-repack.py
kernel K2: 16561740 B gz (sha16 f85153dc0fb8eaa3), 24 cadenas UKE-POKE, ARMADO+arming+desarmado+fases OK
param K2 en tabla __param como 'arm_smmu.uke_smmu_probe' (junto a arm_smmu.disable_bypass)  OK
early_param eliminado: fuera de la tabla __setup (donde K1 lo tenia, junto a iommu.passthrough)  OK
K1 dentro de boot-ukek1-gate0.img: Image.gz 16560891 B sha16 304db709107bac78 -> Image 41355776 B
Image K2 41355776 B vs Image K1 41355776 B: delta 0 B (gate +-2 KB)  OK
cruce K1/K2: K1 tenia early_param (tabla __setup) y 0 'arm_smmu.uke_smmu_probe'; K2 al reves  OK
cruce K1/K2: K1 decia 'falta uke_smmu_probe=1', K2 ya no (ahora cita la ruta sysfs)  OK
s244 == shell + kernel (solo kernel y kernel_size cambian; cmdline y footer identicos)  OK
shell boot-s240-mem2g.img sha256 e3c60969269c0b36... OK; cmdline s244 255 B exacta
== ~/proyectos/omarchy-uke/build/bootimg/boot-ukek2.img ==
  sha256 62553cc3fda56ccdba65ec87b579dd053de2faceeba3be21d631f7461a606ebd
  cmdline 255 B (identica byte a byte a la del s244 / gate0 K1): mem=2048M rdinit=/ukeinit panic=10
    memmap=0x1A12800$0xE3940000 console=tty0 fbcon=map:0 hung_task_timeout_secs=20 hung_task_panic=1
    watchdog_thresh=10 console=ttyGS0,115200 fw_devlink=permissive clk_ignore_unused pd_ignore_unused
    arm-smmu.disable_bypass=0
  kernel_size@8 = 16561740 ; AVB0@35438592 ; AVBf@100663232 (ultimos 4 B de los 96 MiB)  OK
boot-ukek2 vs boot_b de hoy (s244): 16492589 bytes distintos (kernel_size@8+kernel [4096,35438592)); cmdline y footer identicos  OK
boot-ukek2 vs boot-ukek1-gate0: 16487630 bytes distintos, TODOS en kernel_size@8+kernel [4096,35438592); cmdline y footer AVB identicos  OK
unpack_bootimg: kernel == build (16561740 B, sha16 f85153dc0fb8eaa3)  OK
  kernel_size: 16561740
  command line args: mem=2048M rdinit=/ukeinit panic=10 … arm-smmu.disable_bypass=0
avbtool info_image: rc=0 (footer AVB presente)  OK
GATE COMPLETO: OK
```

Gates pedidos, uno a uno:

| gate | resultado |
|---|---|
| sha256 | `62553cc3fda56ccdba65ec87b579dd053de2faceeba3be21d631f7461a606ebd` |
| tamaño | 100663296 B = **96 MiB exactos** |
| `kernel_size@8` | 16561740 (= `Image.gz` del build) |
| AVBf al final | `dd … skip=$((100663296-64)) count=4` → `AVBf`; `AVB0` en 35438592; `avbtool info_image` rc=0 |
| cmdline byte a byte = s244 | 255 B, idéntica al `boot-s244-bounce.img`, al shell `boot-s240-mem2g.img` y al `gate0` del K1; **0 apariciones de "uke_smmu_probe" en la cmdline** |
| Image ARM64 ±2 KB del K1 | `file` → ARM64 4K pages; tamaño crudo 41355776 = **delta 0 B** |

Nota AVB: la firma/footer se copian verbatim del shell (el `boot-s244-bounce.img` que arranca hoy es
exactamente ese shell con otro kernel, patrón ya validado en el K1 y en el s244). El kernel va en
`[4096, 35438592)` con relleno a ceros; **nada más cambia** respecto al s244 salvo `kernel_size@8`
y esa región (16492589 bytes).

---

## 5. PROCEDIMIENTO EXACTO DE ARMING EN LA TABLET

Lo ejecuta quien flashee (NO este agente). Un solo lector de consola
(`REGLA-UN-SOLO-LECTOR.md`); el arranque se hace con el **mismo dtbo s258** ya vigente y este kernel.

**Paso 1 — arrancar con s258 + K2 (arranque NORMAL, sin armar nada)**

```
fastboot flash boot_b build/bootimg/boot-ukek2.img     # (slot/fastboot según el guion de siempre)
fastboot reboot
```

Gates de "kernel vivo" (arranque como el s244: panel vivo, dpu -19 como hoy):

* banner NUEVO: `Linux version 7.2.0-rc2-palawan (usuario@pc-build) (clang version 22.1.8,
  LLD 22.1.8) #2 SMP PREEMPT Mon Sep 28 21:19:35 CEST 2026` (`#2` y hora 21:19:35 = **K2**;
  el K1 decía `#1 … 20:55:43`).
* del apps-smmu deben aparecer **solo**:
  * `arm-smmu: UKE-POKE: arm_smmu_device_probe ENTRANDO, dev=…`
  * `arm-smmu: UKE-POKE: apps-smmu @… base=0x15000000: primer probe DIFFERIDO …`
  * `arm-smmu: UKE-POKE: apps-smmu: desarmado (echo 1 > /sys/module/arm_smmu/parameters/uke_smmu_probe); no se toca el bloque. Arranque sano.`
* del apps-smmu **NO** debe aparecer `REINTENTO del probe` ni `ARMADO` ni ninguna miga de
  `cfg_probe`/`fases` **de apps-smmu**. (El **kgsl-smmu** del mismo DT sí imprime las suyas en el
  arranque normal —`ENTRANDO dev=3da0000.kgsl-smmu`, `-> arm_smmu_device_cfg_probe`, `cfg_probe
  ID0/1/2`, `fases 1-7`—; la frontera sigue siendo `REINTENTO`/`ARMADO`, que solo salen armados.)

**Paso 2 — comprobar que el parámetro existe y está desarmado**

```
# cat /sys/module/arm_smmu/parameters/uke_smmu_probe     →  N
# ls /sys/module/arm_smmu/parameters/                    →  disable_bypass  uke_smmu_probe
```

Si no existiera, parar: el nombre del módulo sería otro (no debería: §1.4).

**Paso 3 — doble captura (regla del proyecto)**

* consola serie (ttyGS0) a fichero, y en el PC:
* `ssh … 'dmesg -n 7; dmesg -w'` (doble captura consola + ssh). `dmesg -n 7` para que los `pr_info`
  salgan también por consola; el ring buffer los guarda igual.

Opcional pero muy recomendable **antes** de armar: ver la lista de diferidos (es exactamente lo que
el trigger va a re-sondear, ver §6):

```
# mount -t debugfs none /sys/kernel/debug 2>/dev/null
# grep -A2 15000000 /sys/kernel/debug/devices_deferred   # (o cat entero)
```

**Paso 4 — ARMAR** (como root: el param es 0644)

```
# echo 1 > /sys/module/arm_smmu/parameters/uke_smmu_probe     # vuelve en el acto (no hay flush)
# cat /sys/module/arm_smmu/parameters/uke_smmu_probe          →  Y
```

Secuencia esperada en la consola (prefijo `arm-smmu: ` de `pr_fmt`):

```
1  UKE-POKE: arming en caliente: uke_smmu_probe=1
2  X9WAVE-try <dev> …                                        (instrumentación del deferred work)
3  UKE-POKE: apps-smmu: REINTENTO del probe, consola ya viva. Lo que viene a continuación es el probe de verdad.
4  UKE-POKE: apps-smmu: -> arm_smmu_device_cfg_probe (lectura IDR0/1/2 y PIDR; …)
5  UKE-POKE: ARMADO — probe real del apps-smmu, lo que sigue puede colgar
6  UKE-POKE: cfg_probe ID0=0x… / ID1=0x… / ID2=0x…
7  UKE-POKE: qcom_cfg_probe: VOY a ESCRIBIR S2CR(…) … relectura=… / leyendo SMR(0..N) / SMR loop OK
8  UKE-POKE: apps-smmu: -> arm_smmu_device_reset … + fase1..fase7
```

**Paso 5 — leer migas hasta el desenlace.** Interpretación (árbol de decisión):

* **frontera = `ARMADO`**. Si la última línea es la 3 (no llega a la 4), el cuelgue es del *plumbing*
  previo a `cfg_probe` (lo típico en esta placa: `clk_bulk_prepare_enable`). Si la última línea es la
  **5 (`ARMADO`) y luego silencio**, el cuelgue es **la lectura de ID0**, el primer acceso al bloque
  apps-smmu. Entre la 4 y la 5 no hay MMIO alguno (solo la entrada en `cfg_probe`).
* Si salen `ID0/ID1/ID2`, el bloque **lee**: sigue el reset (`fases 1-7`) y el quirk de S2CR
  (`VOY a ESCRIBIR S2CR` → `relectura=…`); `SMR loop OK` significa que el `qcom_smmu_cfg_probe`
  completó. Un cuelgue en `fase1..7` acota a un registro concreto del reset.
* Tras el desenlace, si el sistema sobrevive: `dmesg | grep -E "UKE-POKE|arm-smmu"` en la sesión ssh
  (segunda fuente) y **no volver a armar**: para dejar el estado limpio, `echo 0 > …` y reboot.

---

## 6. Riesgos (el mayor primero)

1. **El trigger re-sondea TODOS los diferidos, no solo el apps-smmu.** `driver_deferred_probe_trigger()`
   mueve la lista entera de pendientes a la activa: si otro device diferido cuelga al reintentarse
   (en este árbol hay probes que cuelgan: el comentario del propio `dd.c` del proyecto cita
   `spmi-debug`, `icc`, …), el *work* del deferred probe se queda atascado en él. Mitigación: el
   `grep devices_deferred` del paso 3 muestra la lista **antes** de armar, y las migas `X9WAVE-try
   <dev>` dicen exactamente en qué device se quedó. El resto del sistema (y el ssh) sigue vivo
   mientras el work esté colgado, salvo cuelgue duro de la máquina.
2. **El probe real puede colgar la máquina** (es justo el objetivo del experimento): `ID0` es el
   primer MMIO del apps-smmu y el reset escribe SMR/S2CR/CBAR/TLBI. Mitigación: doble captura, sin
   `flush_work` en el `.set` (el `echo` no se queda colgado), y todo lo impreso queda en consola.
3. **Límite de prints**: el aviso `desarmado` sale como mucho 1/s (el primero siempre). Si algo se
   re-intenta en ráfaga, se pierden líneas intermedias (solo informativo).
4. **Un armado por cmdline NO arma temprano pero puede armar el retry de `late_initcall`**: el
   parámetro también es accesible como `arm_smmu.uke_smmu_probe=1` en la cmdline; el `.set` corre
   antes de `driver_deferred_probe_enable=true`, así que el trigger es un no-op… pero `uke_smmu_armado`
   quedaría a 1 y el primer reintento (late_initcall) haría el probe real → **repetiría el fallo del
   K1**. Esta imagen **no** lleva ese token (gate del §4: cmdline byte a byte la del s244) y el
   procedimiento lo prohíbe.
5. **`=m` no compila**: si alguien cambiara `CONFIG_ARM_SMMU=m`, modpost falla por el símbolo no
   exportado (anotado en el código). K2 es un kernel built-in-only, como el del #82.
6. **No confundir apps-smmu con kgsl**: en el arranque normal el kgsl imprime migas de `cfg_probe` y
   `fases` (su nodo ya bindea hoy). El discriminante de K2 es `REINTENTO`/`ARMADO`, que solo existen
   armados, y `ARMADO` solo sale para el nodo `reg=<0x15000000…>`.

---

## 7. Qué NO se ha hecho

- No se ha flasheado nada ni se ha hablado con la tablet (sin adb/fastboot/ssh).
- `~/gpu-work` no se ha modificado: solo lecturas (árbol compartido, `ramaa/s21/*`, config del #82).
- En `omarchy-uke` **no se ha editado ningún fichero existente ni se ha commiteado**: los únicos
  ficheros nuevos son `build/bootimg/boot-ukek2.img` (ignorado por `.gitignore:25`),
  `build/gates/patches/k2-arming.diff` y este informe (`??` en `git status`).
- No se ha usado `olddefconfig`: el `.config` del K1 (idéntico byte a byte al del #82) se ha usado
  tal cual, con `O=` incremental.

## 8. Copias de trabajo y reproducibilidad

| ruta | tamaño | contenido |
|---|---|---|
| `/tmp/uke-k1` → `/var/tmp/uke-k1` | 1,8 G | árbol con **K1+K2** aplicados (arm-smmu.c sha `87abc526…`) |
| `/tmp/uke-k1-build` → `/var/tmp/uke-k1-build` | 3,1 G | `O=` (config del #82, `Image.gz` K2, `vmlinux`, logs) |
| `/var/tmp/uke-k2/` | KB | `build-k2.log`, `repro/` (árbol de comprobación de parches) |
| `/tmp/uke-k2-repack.py`, `/tmp/uke-k2-repack-report.txt`, `/tmp/uke-k2/k2-delta.diff` | KB | script de empaquetado, su log y el delta |

Reproducibilidad del par de parches sobre el árbol pristino (`~/gpu-work/palawan-linux`, solo lectura),
con la comprobación por sha de cada paso:

```
$ mkdir -p /var/tmp/uke-k2/repro/drivers/iommu/arm/arm-smmu && cd …
$ cp <pristino>/drivers/iommu/arm/arm-smmu/arm-smmu{,‑qcom}.c repro/drivers/iommu/arm/arm-smmu/
$ patch -p1 --dry-run -d repro < build/gates/patches/k1-arm-smmu.diff   → checkeo OK
$ patch -p1 -d repro < build/gates/patches/k1-arm-smmu.diff
  sha256 arm-smmu.c == 26a16af10206e70dbdedb967cfd22652001648c0a3da975587892913b3617787  (estado K1)
$ patch -p1 --dry-run -d repro < build/gates/patches/k2-arming.diff     → checkeo OK (solo arm-smmu.c)
$ patch -p1 -d repro < build/gates/patches/k2-arming.diff
  sha256 arm-smmu.c == 87abc5265be9b33044fefb2779598d32d53b5d348befd7c5cee03fc6691dd020  (estado K2 = árbol de trabajo)
  sha256 arm-smmu-qcom.c == 14ea069dbbd99316efbfde9cee8eed71501b4e757bb4cd1e90292b2be6ec87bc (idéntico al árbol de trabajo: K2 no lo toca)
```

Es decir: `k1-arm-smmu.diff` + `k2-arming.diff` aplicados en ese orden reproducen exactamente el
árbol con el que se ha construido y empaquetado `boot-ukek2.img`.
