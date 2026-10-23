# P2 — Táctil y lápiz NT36532: el camino completo, preparado sin tablet

**Fecha:** 29-sep-2026 (madrugada). **Autor:** agente P2-LÁPIZ.
**Estado:** el driver COMPILA (built-in en K6 y como .ko cargable); lo que
bloquea el táctil hoy NO es código sino el DT (doble nodo con el mismo CS y
nodo vendor sin `interrupts`). Hay vía SIN FLASH: `.ko ext`.
**Artefactos:** `build/gates/prepara/novatek/` (README + .ko + patch + dt-fix +
userspace). Este documento es el informe dueño del hueco (h) de G-auditoria.

---

## TL;DR (lo que hay que saber en 10 líneas)

1. El driver existe **in-tree** en `/var/tmp/uke-k1/drivers/input/touchscreen/novatek-nt36xxx-spi.c`
   (657 líneas, protocolo verificado contra `nt36532_touch.ko`) y está
   **BUILT-IN** en el K6 (`CONFIG_TOUCHSCREEN_NOVATEK_NT36XXX_SPI=y`,
   `.config:3162`; strings del driver dentro del `Image` del 29-sep 01:02).
2. El dtbo s258 (el que está en la tablet) trae **DOS** nodos
   `compatible="novatek,NVT-ts-spi"` con `reg=<0>` bajo `spi@a90000`: el
   **vendor** (fragment@35) gana el CS 0 (`spi0.0`) pero **no tiene
   `interrupts`** → el driver muere con `-EINVAL` ("no IRQ specified",
   medido en K2/K4); el nodo **constructor** (fragment@1200) sí tiene
   `interrupts` pero pierde con "chipselect 0 already in use".
3. Los ejes del nodo vendor tampoco están: el driver cae a su default
   **1600x2136**, cuando el marco nativo medido en Android es **2136x3200**
   (`abs_x_max=2136, abs_y_max=3200`, rx=40 x tx=60). Con 1600x2136 se
   descartarían todos los toques con x>=1600 o y>=2136.
4. **Solución preparada y compilada (sin flash):** `ext/novatek-nt36xxx-spi-ext.ko`
   acepta el nodo vendor tal cual (`novatek,irq-gpio` → `gpiod_to_irq`),
   usa 2136x3200 por defecto y añade `frame_dump` para el triaje.
   Vermagic == K6; los 40 símbolos indefinidos existen en el `__ksymtab`.
5. Alternativa DT (para el próximo ciclo de dtbo): `dt-fix/touch-fix.dts` +
   candidato `touchfix-s259-candidato.img` (`04f6a866…`), gates verdes. **No
   flasheado.**
6. Userspace: la cadena evdev → udev → libinput → Hyprland tablet-v2 está
   verificada de punta a punta **en fuentes/binarios** (systemd v258 input_id,
   libinput 1.32.0, Hyprland 0.56.2-3 con `zwp_tablet_manager_v2`). libwacom
   2.20.0 **no puede** matchear el lápiz (no conoce el bus SPI) — no perder
   tiempo ahí; la presión del lápiz va por tablet-v2/GTK4, no por libwacom.
7. El **lápiz** (Focus Pen = nodo `NVTCapacitivePenM80p`): presión 0..8191,
   tilt ±60, distancia 0..1, X/Y 0..21359/31999 (super-res ×10),
   BTN_TOOL_PEN+BTN_TOUCH+KEY_WAKEUP, INPUT_PROP_DIRECT; **sin BTN_STYLUS**
   (los botones del lápiz no salen por evdev). En mainline **no hay nodo de
   lápiz todavía**: falta crear el input_dev y decodificar su record del
   paquete SPI (el layout de dedo tampoco está verificado: `point_layout`).
8. El paquete de red lo desbloquea F3; los 3 pasos post-pantalla están en §(e).

---

## (a) Árbol del driver: qué es exactamente

### a.1 El driver que corre (in-tree, del fork)

| Dato | Valor | Evidencia |
|---|---|---|
| Fichero | `/var/tmp/uke-k1/drivers/input/touchscreen/novatek-nt36xxx-spi.c` (657 líneas) | leído entero |
| Naturaleza | **nuevo driver SPI** del fork (no es el mainline `novatek-nvt-ts.c`, que es I2C-only) | cabecera del fichero |
| Protocolo | verificado contra el `.ko` vendor (`CTP_SPI_READ` 0x4e8, `nvt_set_page` 0x9a0, `work_func` 0x8914, EVENT_BUF 0x125800, frame 257 B, sync 0xFD/0xFE, checksum 64+1, dedos = head u16>>3) | cabecera + comentarios |
| `compatible` | `novatek,NVT-ts-spi` (exacto del vendor) y `novatek,nt36xxx-spi` | `nvt_spi_of_match[]`, líneas 637-641 |
| `spi_device_id` | **no hay** (solo `of_match`) → el aviso de boot `SPI driver novatek-nt36xxx-spi has no spi_device_id for novatek,NVT-ts-spi` es benigno | driver + `k4-migas-log.txt:1140` |
| Kconfig | `CONFIG_TOUCHSCREEN_NOVATEK_NT36XXX_SPI`, `tristate`, `depends on SPI` | `Kconfig:704-718`; `Makefile:72` |
| Config del K6 | `CONFIG_TOUCHSCREEN_NOVATEK_NT36XXX_SPI=y` (built-in) | `.config:3162` |
| Bus | `CONFIG_SPI_QCOM_GENI=y` (`spi@a90000`, QUP0 SE4; sin DMA → FIFO) | `.config:3521`; `k4-migas-log.txt:1583-1585` |
| Otras | `CONFIG_INPUT=y`, `CONFIG_INPUT_EVDEV=y`, `CONFIG_INPUT_TOUCHSCREEN=y` | `.config:3007/3019/3114` |
| Compilado | `novatek-nt36xxx-spi.o` del 28-sep 20:54 en `/var/tmp/uke-k1-build`; strings del driver dentro del `Image` del 29-sep 01:02 | `strings Image \| grep NT36xxx` |
| Limitación | **el layout del record de dedo NO está verificado** (3 candidatos, module param `point_layout`) y **no hay lápiz** | comentario grande antes de `nvt_spi_parse_point` |

### a.2 El trabajo previo W5 (`~/gpu-work/w5-touch/`): qué se usó y qué no

- `novatek-nt36532-spi.c` (221 líneas): **esqueleto que NO compila**
  ("Status: DOES NOT COMPILE yet"), con `compatible` preferido
  `novatek,nt36532-ts-spi` + alias `novatek,NVT-ts-spi`. Fue el plan inicial;
  el driver in-tree actual lo **sustituye** (mismo espíritu, protocolo real en
  vez de TODO). OJO: el in-tree **no acepta** `novatek,nt36532-ts-spi`; un DT
  nuevo debe usar `novatek,NVT-ts-spi` o `novatek,nt36xxx-spi`.
- `xiaomi-uke-touch.dtsi`: fragmento DT con pines SPI (gpio16-19), IRQ
  (gpio54), lcd_id (gpio26) y `&spi_touch` — **no se usó** (el DT del boot es
  el vendor + dtbo; el fork no lleva nodo de táctil: `xiaomi-uke.dts:533` dice
  literalmente "TODO: touch novatek nt36532 ... driver por portar").
- `fw-note.txt` / `Kconfig-Makefile.patch`: siguen siendo referencia para el
  firmware (`novatek_nt36532_o82_fw_csot.bin`, selección por lcd_id gpio 26,
  MP criteria 5993/5994). **No hacen falta para el táctil básico**: Android no
  descarga firmware al arrancar (el chip arranca con el panel, TDDI) — ver
  dmesg Android (no hay `request_firmware` de NVT; solo `fw_version`/historial).
  El firmware solo sería necesario para un *update* o para el selftest MP, que
  el driver in-tree no implementa.
- `novatek,nt36532-ts-spi.yaml`: binding del esqueleto; el driver in-tree no
  lo usa.

### a.3 Qué faltaba para compilarlo: NADA (ya está compilado)

- El `.o` ya estaba construido con el kernel (28-sep 20:54) y el driver va
  **dentro** del `Image` del K6. No hay que tocar `Kconfig`/`Makefile`/
  `defconfig`: todo está aplicado en `/var/tmp/uke-k1` (que NO se modifica).
- Lo único que "falta" es **DT + probe**:
  - `spi->irq` (nodo vendor sin `interrupts`);
  - ejes (2136x3200);
  - y, para el lápiz, el nodo de lápiz (no existe en mainline).

---

## (b) Compilación: hecha, con evidencia

### b.1 Qué se compiló y cómo

```sh
MAKE=/usr/bin/make KBUILD_MODPOST_WARN=1 /usr/bin/make -C /var/tmp/uke-k1 \
    O=/var/tmp/uke-k1-build ARCH=arm64 LLVM=1 M=<dir> modules
```
- El árbol `/var/tmp/uke-k1` **solo se lee**; la escritura va a
  `/var/tmp/uke-k1-build` (libre). Toolchain: clang/LLD 22.1.8 (el mismo del
  kernel: `INFORME-K1-BUILD.md:155-159,183`).
- `KBUILD_MODPOST_WARN=1` es **obligatorio** aquí: `/var/tmp/uke-k1-build` no
  tiene `Module.symvers` (el kernel se construyó solo `Image.gz`; no se corrió
  `make modules`). Con `CONFIG_MODVERSIONS` off no afecta al `insmod`.
- Gate de símbolos: los 40 símbolos indefinidos del `.ko ext` existen como
  `__ksymtab_*` en `/var/tmp/uke-k1-build/vmlinux` (verificado con `llvm-nm`;
  0 ausentes). Vermagic idéntico al K6:
  `7.2.0-rc2-palawan SMP preempt mod_unload aarch64`.

| Artefacto | Tamaño | sha256 (primeros 16) | Cargable en K6 |
|---|---|---|---|
| `novatek/src/novatek-nt36xxx-spi.ko` (verbatim) | 377 880 B | `068af171b8c100fd` | **NO** (mismo `driver.name` que el built-in → `-EBUSY`) |
| `novatek/ext/novatek-nt36xxx-spi-ext.ko` (ext) | 384 552 B | `e248c61e06c17761` | **SÍ** |
| `novatek/novatek-nt36xxx-spi-bringup.patch` | 180 líneas | `f3ff716ffb008f7d` | (patch para el árbol in-tree) |

### b.2 Qué cambia la variante EXT (generada por `mk-ext.py`, reproducible)

1. `driver.name = "novatek-nt36xxx-spi-ext"` (convive con el built-in).
2. **IRQ**: si `spi->irq == 0`, `devm_gpiod_get(dev, "novatek,irq", GPIOD_IN)`.
   gpiolib prueba `novatek,irq-gpios` y luego `novatek,irq-gpio`
   (`gpiolib.c:106` `gpio_suffixes={"gpios","gpio"}`;
   `gpiolib-of.c:705`), y `gpiod_to_irq()`. El `GPIOD_IN` además muxea el pin a
   GPIO en el TLMM (`msm_gpio_template.request = gpiochip_generic_request` →
   `pinctrl_gpio_request` → `msm_pinmux_request_gpio` → mux GPIO;
   `pinctrl-msm.c:276,812`). El IRQ se pide con `IRQ_TYPE_EDGE_RISING`
   (Android: `int_trigger_type=1`).
3. **Ejes**: `max_x`/`max_y` module params (default 2136x3200). El nodo vendor
   no trae `touchscreen-size-*`, así que `touchscreen_parse_properties()` deja
   el absinfo que fija el driver (`drivers/input/touchscreen.c:85-88`).
4. **`frame_dump`**: volcado hex de los primeros N frames no-idle
   (`echo 40 > /sys/module/novatek_nt36xxx_spi_ext/parameters/frame_dump`) —
   para verificar `point_layout` y para el RE del lápiz.

### b.3 Por qué el built-in falla y el ext no (secuencia exacta del boot)

```
[13.897] geni_spi a90000.spi: FIFO mode ... (bus OK)
[13.898216] novatek-nt36xxx-spi spi0.0: no IRQ specified        <- nodo VENDOR
[13.898227] probe with driver novatek-nt36xxx-spi failed with error -22
[13.898267] spi spi0.0: chipselect 0 already in use
[13.898270] spi_master spi0: spi_device register error .../touchscreen@0  <- nodo CONSTRUCTOR
```
(`k4-migas-log.txt:1583-1592`; idéntico en K2 y en `k4c-consola-trail.txt`.)
Tras el fallo de probe, el driver core hace `device_unbind_cleanup()` →
`dev->driver = NULL` (`drivers/base/dd.c:608-623`) y el dispositivo queda
**libre**. Al `insmod` del ext, `driver_register` → `driver_attach` re-engancha
`spi0.0`. Si por lo que sea no lo hace solo:
`echo spi0.0 > /sys/bus/spi/drivers/novatek-nt36xxx-spi-ext/bind`.

### b.4 Vía DT (alternativa, para el próximo dtbo; no necesaria con el .ko)

`dt-fix/touch-fix.dts` añade dos fragmentos al payload del dtbo:
- `fragment@2104` sobre `.../spi@a90000/novatek@0`: `interrupt-parent=<0x16b>`
  (tlmm), `interrupts=<0x36 0x01>` (54, rising) y
  `touchscreen-size-x=<0x858>` (2136) / `-y=<0xc80>` (3200);
- `fragment@2105` sobre `.../touchscreen@0`: `status="disabled"` (quita el
  conflicto de CS).
`dt-fix/mk-dtbo-touchfix.py` lo construye desde el s258 real con gates
(fdtoverlay rc=0, fdtget de las 4 props, `touchscreen@0` disabled, SPI
intacto, tamaño < 610304 B, roundtrip byte a byte) y deja
`candidato/touchfix-s259-candidato.img` = `04f6a8662fbb7c17…` (608 789 B,
margen 1 515 B). **NO flasheado**: es un candidato; el protocolo de dtbo
(sha + slot bueno + rollback) es el de siempre. Si se usa el .ko ext, este
dtbo no hace falta.

---

## (c) Cadena userspace: `/dev/input` → app

### c.1 Qué habrá en `/dev/input` y cómo lo clasifica udev

El driver in-tree crea **un** nodo (táctil). El nodo de lápiz habrá que
añadirlo (§d). Clasificación de `systemd-udevd` (verificada en fuente v258,
`src/udev/udev-builtin-input_id.c`):

| Nodo | Caps | Tag udev |
|---|---|---|
| `Novatek NT36xxx Touchscreen` (driver actual) | `ABS_MT_POSITION_X/Y` + `BTN_TOUCH` + `INPUT_PROP_DIRECT` (lo pone `input_mt_init_slots(INPUT_MT_DIRECT)`, `input-mt.c:82`) | `ID_INPUT_TOUCHSCREEN=1` (rama MT: `has_mt_coordinates` + `is_direct`; input_id.c:252-258) |
| `NVTCapacitivePenM80p` (a implementar) | `ABS_X/Y` + `BTN_TOOL_PEN` + `BTN_TOUCH` + `INPUT_PROP_DIRECT` | `ID_INPUT_TABLET=1` **y NO** touchscreen (la rama tablet gana: `has_abs_coordinates` + `has_pen` → `is_tablet=true`; input_id.c:236-238) |

Consecuencia (libinput 1.32.0, `src/evdev.c`): la rama tablet exige
`(udev_tags & (TABLET|TOUCHPAD|TOUCHSCREEN)) == TABLET` — con el tag correcto,
el lápiz entra como tablet tool; **no hay restricción de bus** en libinput (no
importa que sea SPI). El táctil entra como touchscreen y acepta
`input:touchdevice:transform`.

### c.2 libinput

- Versión en ALARM: `libinput 1.32.0-1` (lib) + `libinput-tools 1.32.0-1`
  (`libinput list-devices`, `debug-events`, `record`). **No está instalado
  aún** en el rootfs (ver §g).
- Táctil: `libinput list-devices` debe listarlo con `Size` (si se pone el
  hwdb de ejes) y `Capabilities: touch`; `properties` del evdev con bit 1
  (`INPUT_PROP_DIRECT`) — es el gate de OBJETIVOS nº7.
- Lápiz: `libinput debug-events` muestra eventos `TABLET_TOOL` (PROXIMITY_IN,
  TIP, AXIS pressure/tilt/distance). Es la verificación más directa sin
  compositor.

### c.3 libwacom: el hueco REAL (corrección a E §2.4/§3.6)

Verificado en el paquete 2.20.0-1 del rootfs y en fuente upstream:
- `bus_from_str()` solo conoce **usb, serial, bluetooth, i2c** (no "spi").
- `match_from_string()` exige `bus|vid|pid` (3 campos); un **nombre a pelo no
  es un match válido** — el único sin tuberías es el literal `generic`.
- `libwacom-update-db.py` **solo genera hwdb para usb/bluetooth** (dict
  `bustypes`); i2c/spi/nombre se saltan. `65-libwacom.rules` consulta el hwdb
  con prefijo `libwacom:name:<name>:`.
- El nodo del lápiz es **virtual** (Bus=001c SPI, Vendor=0000, Product=0000,
  sin `ID_BUS` en udev) → la búsqueda cae en el sentinel `generic`
  (bus UNKNOWN, 0:0) que ya existe (`/usr/share/libwacom/generic.tablet`,
  `Stylus=true`, `IntegratedIn=Display;System`).
**Conclusión:** no hace falta (ni se puede) una entrada específica hoy; el
borrador `userspace/xiaomi-uke.tablet` queda documentado como inerte. La
presión del lápiz NO depende de libwacom (va por libinput/Wayland/GTK4).

### c.4 Hyprland 0.56.2-3

Verificado en el binario 0.56.2 del host (misma versión que el repo ALARM):
- contiene `zwp_tablet_manager_v2`, `zwp_tablet_tool_v2`, `zwp_tablet_pad_v2`
  y la config de tools de libinput (`pressure_range`, `eraser_button`);
- **no hay que activar nada**: Hyprland crea el tablet_v2 para cualquier device
  que libinput clasifique como tablet tool; aparecerá en `hyprctl devices`
  (sección `Tablets:`) y en `hyprctl devices -j` (clave `"tablets"`). OJO:
  **`hyprctl tablets` NO existe en 0.56.2** ("unknown request") — usar
  `hyprctl devices`;
- opciones: `input:tablet:transform`, `input:tablet:left_handed`,
  `input:touchdevice:transform` (existen; `hyprctl getoption` responde);
- config Lua 0.56: `hl.config({ input = { touchdevice = {...}, tablet = {...} } })`
  y `hl.device({ name=..., output=... })` (D §5.1/§7; el binario tiene el API).
Snippets listos en `userspace/hyprland-touch-pen.conf` (clásico) y
`userspace/hyprland-touch-pen.lua` (Lua/Omarchy 4).

### c.5 udev rules y hwdb

- `userspace/70-uke-input.rules` → `/etc/udev/rules.d/70-uke-input.rules`
  (`SUBSYSTEM=="input", KERNEL=="event*", TAG+="uaccess"`). Necesario para
  `evtest`/`libinput`/`wev`/`python-evdev` como usuario: systemd 70-uaccess
  solo da uaccess a joysticks; los event* quedan root:input (alternativa:
  `usermod -aG input`). **OJO**: en `/etc/udev/rules.d/`, no en `/etc/udev/`
  (lección B §7 Fase 9).
- `userspace/60-uke-evdev.hwdb` → `/etc/udev/hwdb.d/` (resolución 13.5
  unidades/mm para que libinput tenga tamaño físico; opcional).
- Estado del rootfs actual (`build/rootfs/arch-rootfs.img`): `/etc/udev/rules.d`
  **vacío**; `/usr/share/libwacom/` completo; `/etc/libwacom` no existe;
  libwacom/libevdev están **extraídos sin registro en pacman** (no aparecen en
  `/var/lib/pacman/local`) → `pacman -S` los reinstalará limpiamente.

---

## (d) El lápiz (Focus Pen): qué reporta el NT36532 y qué falta

### d.1 Evidencia del Android dorado (nada inventado)

Del dmesg stock (`ubuntu-permanente/criticas/ufs-referencia-android/dmesg-android.txt`)
y de `ubuntu-uke/dump/20260903-073613/pen/` (getevent con root):

- El driver vendor crea **tres** input devices en probe:
  `NVTCapacitiveTouchScreen`, `NVTCapacitivePenM80p`, `NVTCapacitivePenP81c`
  (dmesg:4704-4711). Los crea siempre (haya o no lápiz).
- **M80p = el Focus Pen** (`proc-bus-input-devices.txt`):
  `Bus=001c (SPI) Vendor=0000 Product=0000`, `Phys=input/pen`, `PROP=2`
  (INPUT_PROP_DIRECT), name `NVTCapacitivePenM80p`.
  Caps exactas (`getevent-p.txt`):
  - `KEY_WAKEUP (0x8f)`, `BTN_TOOL_PEN (0x140)`, `BTN_TOUCH (0x14a)`;
  - `ABS_X` 0..21359, `ABS_Y` 0..31999 (¡marco ×10: super_resolution_factor=10
    del dmesg:4809!);
  - `ABS_PRESSURE` **0..8191**, `ABS_DISTANCE` 0..1,
    `ABS_TILT_X/Y` **-60..60**;
  - **NO hay `BTN_STYLUS`/`BTN_STYLUS2`**: los botones del lápiz no salen por
    evdev (el log `getevent-event12-botones.log` solo tiene BTN_DIGI/BTN_TOUCH).
- **P81c** (otro modelo de lápiz): `ABS_PRESSURE` 0..16383 y un `0x120`
  (BTN_TRIGGER) extra — probable botón lateral de ese lápiz. Con el Focus Pen
  el nodo P81c está mudo (`HARDWARE-KNOWN-PLAN.md:23`).
- Presión medida a fondo: rampa 1 → 0x3a7 → … → 0x644 (1580) en el log vivo;
  el máximo de la escala es 8191 (0x1fff). Tilt medido -68..+46 en M80p
  (HARDWARE-KNOWN-PLAN) — ojo: la escala del evdev dice ±60.
- El vendor **detecta el modelo de lápiz** ("Xiaomi stylus m80p" / "p81c",
  strings del `.ko`) y expone `/proc/xm_htc_stylus_enable`,
  `nvt_pen_switch`, `xm_htc_pen_scan_rate` (dmesg:4726-4735): hay modo lápiz
  en el FW. En Android arranca funcionando sin escribir nada (el HAL
  `touchfeature-service` existe pero el getevent se hizo con root y el lápiz
  respondía ya en boot).
- El `.ko` vendor tiene `nvt_ts_pen_gesture_report` (T @0x48b8) y entrega el
  paquete crudo a `xiaomi_touch.ko` (el layout de dedo lo decodifica
  xiaomi_touch, no el .ko de transporte).

### d.2 Qué falta exactamente en mainline para "puntas"

1. **Crear el input_dev del lápiz** (no existe en el driver in-tree): name
   `NVTCapacitivePenM80p`, `BUS_SPI`, `INPUT_PROP_DIRECT`,
   `ABS_X/Y` 0..(2136|3200)*10-1, `ABS_PRESSURE` 0..8191,
   `ABS_DISTANCE` 0..1, `ABS_TILT_X/Y` -60..60, `BTN_TOOL_PEN`, `BTN_TOUCH`
   (+ `BTN_TOOL_RUBBER` si se confirma goma).
2. **Decodificar el record del lápiz** del paquete SPI. El paquete de 256 B
   (sub-paquete útil de 64+1 B con checksum) es el mismo para dedo y lápiz; el
   layout del lápiz no está documentado en el `.ko` (lo decodifica
   xiaomi_touch.ko). **Herramienta ya lista**: `frame_dump` del .ko ext +
   comparación de frames con/sin lápiz en rango.
3. **Modo lápiz del FW**: si los frames con el lápiz no aparecen, probar los
   equivalentes a `xm_htc_stylus_enable`/`nvt_pen_switch` (direcciones no
   verificadas; el vendor las escribe por proc). En Android el lápiz funciona
   "de fábrica", así que el default probablemente ya está activo.
4. **Goma/eraser**: no anunciada por el vendor en evdev (ni BTN_TOOL_RUBBER ni
   tool type). No prometerla hasta medirla.

### d.3 Orden de RE propuesto (cuando el táctil ya funcione)

1. `insmod` del ext con `frame_dump=200`; tocar con el dedo y con el lápiz;
   volcar `dmesg` a fichero.
2. Comparar frames: dedo (1 contacto) vs lápiz en hover vs lápiz con punta.
   Los frames del lápiz deberían aparecer aunque el dedo no toque (el vendor
   tiene nodo aparte; el IRQ es compartido).
3. Fijar `point_layout` con el dedo primero (1 dedo, esquinas opuestas) — sin
   eso, cualquier decodificación del lápiz es ruido.
4. Implementar el nodo de lápiz + parser en el .ko ext (iterar por insmod, sin
   recompilar kernel), validar con `evtest`/`libinput debug-events`
   (`TABLET_TOOL`) y `wev` (tablet-v2) y una app GTK4.

---

## (e) Plan de prueba (post-pantalla, en orden)

**Paso 0 (prerequisito de fiabilidad):** `e2fsck` en frío del rootfs Arch
(ESTADO-VIVO: "el ext4 cada vez más podrido"). Sin eso, el canal de pruebas es
frágil.

**Paso 1 — probar el driver sin flash (el .ko ext):**
```sh
scp build/gates/prepara/novatek/ext/novatek-nt36xxx-spi-ext.ko root@uke:/root/
ssh root@uke 'insmod /root/novatek-nt36xxx-spi-ext.ko; dmesg | grep -iE "novatek|NT36xxx" | tail'
```
Esperado: `IRQ N desde novatek,irq-gpio (nodo vendor s258)` +
`NT36xxx SPI probe ok: irq N ... 2136x3200 ... point_layout=0`.
Gate de control negativo: sin el módulo, `dmesg` muestra `-EINVAL` y
`/dev/input` no tiene el nodo.

**Paso 2 — táctil en evdev (gate de OBJETIVOS nº7):**
```sh
sh userspace/test-touch.sh                 # (copiar antes)
ls /dev/input/event*                        # -> Novatek NT36xxx Touchscreen
cat /sys/class/input/eventN/device/properties   # -> bit 1 (INPUT_PROP_DIRECT)
evtest /dev/input/eventN                    # -> ABS_MT_* con 1..10 dedos
```
Gates: `libinput list-devices | grep -i novatek` (con `Capabilities: touch`),
`libinput debug-events --device /dev/input/eventN` con coordenadas ABS.
Si las coordenadas bailan (ids/slots raros): probar
`echo 2 > /sys/module/novatek_nt36xxx_spi_ext/parameters/point_layout`
(y 1). Si solo hay valores múltiplos raros, stride/endian: mismo procedimiento.
`frame_dump=20` deja los frames crudos en dmesg para decidir.

**Paso 3 — rotación y calibración** (coordinar con `PX-rotacion.md`, que cubre
la rotación de monitor y su `touchdevice:transform` emparejado; aquí solo el
detalle del táctil/lápiz):
```sh
libinput debug-events --device /dev/input/eventN   # tocar las 4 esquinas
hyprctl getoption input:touchdevice:transform
```
Con la tablet apaisada, el marco nativo 2136x3200 sale rotado 90°; elegir
`transform = 1` o `3` (ver `userspace/hyprland-touch-pen.{conf,lua}`) hasta que
el toque caiga bajo el dedo en las 4 esquinas (ojo D §7: sin
INPUT_PROP_DIRECT, libinput ignora el transform — ya está cubierto).

**Paso 4 — lápiz en userspace:**
```sh
evtest /dev/input/eventP                    # (cuando exista el nodo)
libinput debug-events --device /dev/input/eventP   # TABLET_TOOL + pressure
wev                                          # (en la sesión) zwp_tablet_tool_v2
hyprctl devices -j | ... "tablets"           # -> NVTCapacitivePenM80p
```
Sub-criterio (D §5.2/OBJETIVOS): presión ≠ 0 y modulación de grosor; app GTK4
con `Gtk.GestureStylus` (`Gdk.AxisUse.PRESSURE`).

**Paso 5 — permanencia (opcional):** aplicar
`novatek-nt36xxx-spi-bringup.patch` al árbol y reconstruir `Image.gz`; o
flashear el candidato DT `touchfix-s259-candidato.img` con el protocolo de
dtbo. (Con el .ko ext no hace falta ninguno de los dos.)

---

## (f) Riesgos y cosas NO verificadas

| # | Riesgo | Estado / mitigación |
|---|---|---|
| R1 | **Doble nodo DT con el mismo CS** (vendor gana, sin IRQ; constructor pierde) | Medido (K2/K4). Mitigado por el .ko ext; el fix DT es el candidato `04f6a866…` |
| R2 | **Mux del pin de IRQ (gpio54)**: el DT no tiene grupo para él; el nodo vendor solo muxea el CS (gpio19). Android lo resuelve con `gpio_request` en el .ko | El .ko ext hace `devm_gpiod_get(GPIOD_IN)` → mux GPIO por pinctrl-msm. Con el built-in solo, el IRQ podría no disparar si ABL dejó el pin en otra función |
| R3 | **gpio54 compartido con el TE del display secundario** (`sde_dsi1_active/suspend`) | `sde_dsi1` está **disabled** y su `platform-te-gpio` es gpio78 (0x4e), no 54 → sin conflicto hoy. Si algún día se habilita el secundario, revisar |
| R4 | **Ejes 1600x2136 por defecto** → toques descartados | Corregido en ext (2136x3200) y en el candidato DT. Los tamaños son MEDIDOS en Android, no inferidos |
| R5 | **`point_layout` sin verificar** (3 candidatos) | Params + `frame_dump`; el primer test de dedo lo fija |
| R6 | **CS mux**: el pinctrl del CS vive en el nodo vendor; desactivarlo sin más rompería el SPI | Por eso el fix DT completa el nodo vendor en vez de desactivarlo |
| R7 | **libwacom no conoce el bus SPI** y su hwdb solo cubre usb/bt | No hay fix sin parchear el paquete; NO es necesario para el lápiz (tablet-v2/GTK4) |
| R8 | **Lápiz**: sin nodo input ni parser de su record | Preparado el método (frame_dump + comparación); no se puede cerrar sin tablet |
| R9 | **Botones del lápiz no salen por evdev** (no hay BTN_STYLUS) | Puede ser BLE/HAL (HARDWARE-KNOWN-PLAN:23); no prometer botones |
| R10 | **Firmware NVT**: no se descarga en boot (TDDI arranca con el panel) | No bloquea; el driver in-tree no implementa update ni MP selftest (fuera de alcance) |
| R11 | **Deferred probe**: el bus SPI/`spi0.0` aparece a ~13,9 s; el ext se carga después, a mano | Documentado en README (insmod manual); si se hornea en kernel, el built-in lo pilla en el probe normal |
| R12 | **e2fsck pendiente** | Prerequisito operativo (ESTADO-VIVO); el canal de prueba es scp/ssh |
| R13 | **`compatible` nuevo `novatek,nt36532-ts-spi`** (del esqueleto W5) NO lo acepta el driver in-tree | Usar `novatek,NVT-ts-spi` o `novatek,nt36xxx-spi` en cualquier DT nuevo |

---

## (g) Lista pacman exacta (aarch64/ALARM, verificada en los .db del proyecto)

Instalar en la tablet (F6/F7; ahora mismo el rootfs solo tiene base +
libwacom/libevdev extraídos sin registro):

```sh
pacman -S --needed libinput libinput-tools evtest libwacom libevdev \
                   python-evdev wtype ydotool wev
```
| Paquete | Versión en el repo | Para qué |
|---|---|---|
| `libinput` | 1.32.0-1 | pila de entrada (Hyprland lo trae igualmente) |
| `libinput-tools` | 1.32.0-1 | `libinput list-devices/debug-events/record` |
| `evtest` | 1.36-1 | gate de OBJETIVOS nº7 |
| `libwacom` | 2.20.0-1 | ya extraído; reinstalar para registrarlo |
| `libevdev` | 1.13.7-1 | ya extraído; idem |
| `python-evdev` | 2.0.0-1 | `texp-touch` (D §8) |
| `wtype` | 0.4-2 | teclado virtual/texto (D) |
| `ydotool` | 1.0.4-2 | inyección de eventos (texp-touch) |
| `wev` | 1.1.0-1 | verificar tablet-v2 (`zwp_tablet_tool_v2`) |

Vienen con el set de Omarchy/F6 (no instalar a mano ahora): `hyprland
0.56.2-3` (ya contiene tablet-v2 y las opciones `input:tablet:*`), `gtk4
1:4.22.5-1` (`Gtk.GestureStylus`), `squeekboard 1.43.1-5` (OSK). NO existe en
ALARM: `hyprland-qtutils`/`hyprsysteminfo` (404, E §2.4) — no hacen falta.

---

## (h) Artefactos (todo bajo `build/gates/prepara/novatek/`)

```
README.md                                  instrucciones de instalación (scp + insmod)
src/novatek-nt36xxx-spi.c (+Makefile)      copia verbatim del in-tree
src/novatek-nt36xxx-spi.ko                 068af171b8c100fd  (referencia; NO cargable en K6)
ext/novatek-nt36xxx-spi-ext.c (+Makefile)  variante ext (generada por mk-ext.py)
ext/novatek-nt36xxx-spi-ext.ko             e248c61e06c17761  (cargable en K6)
novatek-nt36xxx-spi-bringup.patch          f3ff716ffb008f7d  (para el próximo kernel)
mk-ext.py                                  generador reproducible del ext
dt-fix/touch-fix.dts                       fragmentos DT (opción A)
dt-fix/mk-dtbo-touchfix.py                 constructor + gates del candidato
candidato/touchfix-s259-candidato.img      04f6a8662fbb7c17  (NO flasheado)
candidato/s258-fused-touchfix.dtb          df8dfa309898ba6b  (fusionado de los gates)
userspace/70-uke-input.rules               uaccess para las herramientas
userspace/60-uke-evdev.hwdb                resolución de ejes (opcional)
userspace/xiaomi-uke.tablet                borrador INERTE (ver §c.3)
userspace/hyprland-touch-pen.conf / .lua   transform de táctil/lápiz
userspace/test-touch.sh                    secuencia de verificación
```
Hashes completos en `sha256sum` de cada fichero (los de arriba son los 16
primeros dígitos).

## Referencias

- Driver: `/var/tmp/uke-k1/drivers/input/touchscreen/novatek-nt36xxx-spi.c`;
  `Kconfig:704-718`; `Makefile:72`; `.config:3162`.
- Hermano de rotación (monitor + touchdevice:transform emparejados):
  `build/gates/prepara/PX-rotacion.md` (§4-§5; allí se documenta que
  `touchdevice:transform` NO cubre los tablet tools → aquí `input:tablet:transform`).
- Boots con el fallo: `build/gates/k4-migas-log.txt:1583-1592`,
  `k4c-consola-trail.txt:104-108`, `k2-migas-log.txt:1586-1590`.
- Android: `proyectos/ubuntu-permanente/criticas/ufs-referencia-android/dmesg-android.txt:4660-4810`;
  `proyectos/ubuntu-uke/dump/20260903-073613/pen/*`.
- Hardware: `proyectos/ubuntu-uke/HARDWARE-KNOWN-PLAN.md:23,56,57`.
- Plan: `F-plan-por-fases.md §F4`; `docs/informes/D-capa-tablet-fallback.md §5.2,§7,§8.5`;
  `docs/informes/E-paquetes-aarch64-soc.md §2.4,§3.6` (corregido en §c.3);
  `docs/historia/G-auditoria-documental.md` hueco (h).
- Userspace verificado en fuente: systemd v258 `udev-builtin-input_id.c`;
  libinput 1.32.0 `src/evdev.c`; libwacom 2.20.0 `libwacom-database.c` +
  `libwacom-update-db`; Hyprland 0.56.2 binario (`zwp_tablet_*`).
