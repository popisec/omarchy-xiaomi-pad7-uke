# prepara/novatek — camino del táctil y el lápiz (NT36532), listo para usar

Preparado el 29-sep-2026 (madrugada) por el agente P2-LÁPIZ. Contexto completo,
diagnóstico y plan: **`../../P2-lapiz.md`** (hermano de este directorio).

## Qué hay aquí

| Fichero | Qué es |
|---|---|
| `src/novatek-nt36xxx-spi.c` + `src/Makefile` | copia VERBATIM del driver in-tree (`/var/tmp/uke-k1/drivers/input/touchscreen/novatek-nt36xxx-spi.c`) y su Kbuild externo |
| `src/novatek-nt36xxx-spi.ko` | módulo compilado (referencia; NO cargable sobre K6: mismo `driver.name` que el built-in) |
| `ext/novatek-nt36xxx-spi-ext.c` + `ext/Makefile` | variante EXT (generada por `mk-ext.py`): IRQ desde `novatek,irq-gpio`, `max_x/max_y` params, `frame_dump` |
| `ext/novatek-nt36xxx-spi-ext.ko` | **el que se usa**: cargable sobre K6 (driver.name distinto) |
| `novatek-nt36xxx-spi-bringup.patch` | diff `src` → `ext` (con `driver.name` original) para el PRÓXIMO build de kernel in-tree |
| `mk-ext.py` | generador reproducible del ext (falla si la base cambia) |
| `dt-fix/touch-fix.dts` | fragmentos DT (opción A: arreglar el nodo vendor + desactivar el constructor) |
| `dt-fix/mk-dtbo-touchfix.py` | construye un candidato de dtbo con gates (fdtoverlay + fdtget + roundtrip). NO flashea |
| `candidato/touchfix-s259-candidato.img` | candidato empaquetado (`04f6a866…`), **sin flashear** |
| `userspace/` | regla udev, hwdb de ejes, `.tablet` (borrador inerte), config Hyprland 0.56 (conf + Lua), `test-touch.sh` |

## Por qué el .ko (y no el built-in) — en una frase

El dtbo s258 tiene DOS nodos `novatek,NVT-ts-spi` con `reg=<0>`: el vendor gana
el CS 0 (`spi0.0`) pero NO tiene `interrupts` (solo `novatek,irq-gpio`), y el
driver in-tree exige `spi->irq` → `-EINVAL`. El `.ko ext` acepta el nodo vendor
tal cual (gpiod → `gpiod_to_irq`) y arregla los ejes (2136x3200, no 1600x2136).
Cero flashes.

## Compilar (reproducible; ya hecho)

```sh
MAKE=/usr/bin/make KBUILD_MODPOST_WARN=1 /usr/bin/make -C /var/tmp/uke-k1 \
    O=/var/tmp/uke-k1-build ARCH=arm64 LLVM=1 M=<dir> modules
```
- El árbol `/var/tmp/uke-k1` NO se modifica (solo se lee); todo se escribe en
  `/var/tmp/uke-k1-build` (que no tiene `Module.symvers` porque el kernel se
  construyó solo `Image.gz` → de ahí `KBUILD_MODPOST_WARN=1`; con
  `CONFIG_MODVERSIONS` off no afecta al `insmod`).
- Toolchain: clang 22.1.8 + LLD (el mismo del kernel). Vermagic de ambos .ko:
  `7.2.0-rc2-palawan SMP preempt mod_unload aarch64` (== K6).
- Los 40 símbolos indefinidos del ext existen en `__ksymtab` del `vmlinux` del
  K6 (verificado con `llvm-nm`); carga garantizada a nivel de símbolos.

## Instalar en la tablet (post-pantalla, por SSH)

```sh
# 1. copiar (el .ko ext; el src no hace falta en la tablet)
scp ext/novatek-nt36xxx-spi-ext.ko root@<uke>:/root/

# 2. cargar. El built-in ya intentó probe y FALLÓ (queda desligado), así que
#    el ext engancha spi0.0 solo al registrarse:
ssh root@<uke> 'insmod /root/novatek-nt36xxx-spi-ext.ko && dmesg | tail -20'
#    Esperado: "IRQ N desde novatek,irq-gpio (nodo vendor s258)" y
#              "NT36xxx SPI probe ok: irq N ... 2136x3200 ..."
#    Si no engancha solo:
ssh root@<uke> 'echo spi0.0 > /sys/bus/spi/drivers/novatek-nt36xxx-spi-ext/bind'

# 3. (opcional) frame_dump para el triaje del layout / lápiz
ssh root@<uke> 'echo 40 > /sys/module/novatek_nt36xxx_spi_ext/parameters/frame_dump'

# 4. quitar
ssh root@<uke> 'rmmod novatek_nt36xxx_spi_ext'
```
Notas:
- NO hace falta `depmod` (es un `insmod` directo; `depmod` solo para módulos
  instalados en `/lib/modules`).
- El módulo `src/…-spi.ko` NO se puede cargar sobre K6 (el built-in ya registró
  ese `driver.name` en el bus SPI → `-EBUSY`). Solo sirve para kernels futuros
  sin el driver in-tree.
- Si se quiere el driver en el kernel (sin .ko), aplicar
  `novatek-nt36xxx-spi-bringup.patch` en `/var/tmp/uke-k1` (copia, no la rama
  viva) y reconstruir `Image.gz`; el DT no necesita cambios en ese caso.
- `dt-fix/`: la vía DT (candidato `touchfix-s259-candidato.img`) NO es
  necesaria si se usa el .ko ext; queda para el siguiente ciclo de dtbo. No
  flashear sin el protocolo de siempre (sha + slot bueno + rollback).

## Paquetes (en la tablet, cuando haya red)

`libinput` `libinput-tools` `evtest` `libwacom` (ya está en el rootfs) +
`python-evdev` `wtype` `ydotool` `wev`; Hyprland/GTK4 vienen con el set de
Omarchy. Detalle y versiones exactas en `P2-lapiz.md §(c)`.
