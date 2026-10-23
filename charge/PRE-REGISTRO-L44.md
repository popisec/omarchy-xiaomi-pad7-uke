# PRE-REGISTRO L44 — backlight externo KTZ8866 en el linaje vivo (14-oct-2026)

> Fila lista para pegar en `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md` ANTES de flashear.
> **NO flasheado aún**: build pendiente + repack pendiente de gates (y de la batería ≥3700 mV).
> Preparado por subagente (solo-PC, sin tablet, sin compilar, sin commit); pendiente de
> crítica adversarial y del build del orquestador.

## Qué es (el "peldaño backlight" del ciclo del bus I2C)

`L44 = L43 + dos piezas`, ambas ya probadas en otros árboles y traídas al linaje vivo
(`build/kernel-pokes/k52-L16-tree`, del que salieron L19 y L43):

1. **Driver KTZ8866 externo** (`drivers/video/backlight/ktz8866.c`, 209→590 líneas):
   copia byte-idéntica del port de `k52L33-tree` (verificado por `cmp` contra
   `build/gates/patches/k52L33-fuentes/ktz8866.c`; informe
   `build/gates/revision/REV-KTZ8866-UKE-20261013.md`). Extiende el driver upstream
   existente en vez de crear uno en `misc/`: añade `compatible = "ktz,ktz8866"`
   (`ktz8866.c:569-571`), `max_brightness = 4095` / `DEFAULT = 0x133` / escala no
   lineal, tabla vendor exacta `mi_bl_level_remap[2048]`, secuencia de escritura
   vendor (0x08 ← 0x7F/0x3F byte completo; 0x04/0x05), probe que exige
   `I2C_FUNC_SMBUS_BYTE_DATA`, reguladores opcionales **con `-ENODEV` tolerado (fix B1
   de la crítica L44: `regulator_get_optional` devuelve -ENODEV si el DT no declara el
   supply y el código lo propagaba ⇒ el probe fallaba SIEMPRE; nunca se había probado
   en dispositivo)**, nombre `dev_name()` (dos
   chips en el DT stock) y `dev_info "probe sucess end"`. Kconfig/Makefile **sin
   cambios** (símbolo `CONFIG_BACKLIGHT_KTZ8866` ya cableado en ambos árboles;
   `depends on I2C` =y, `REGMAP_I2C` =y, `REGULATOR` =y, `BACKLIGHT_CLASS_DEVICE` =y).
   Diff: `build/gates/patches/l44-ktz-driver.diff` (528 líneas, estilo l43; incluye el fix B1).
2. **Panel o82 con backlight externo** (`drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c`):
   port MÍNIMO del soporte `drm_panel_of_backlight` del linaje `k52L39-tree`
   (**solo** los hunks de backlight; NO se traen PPS-L37, reset-15ms-L38, ni
   cambios de herencia/pokes). Variante elegida: **L40 no-bloqueante**
   (`dev_warn`, no fallo) — porque si el KTZ aún no probeó (orden de probe, I2C
   tardío), un fallo duro dejaría al panel entero sin probar (sin card1, sin medida
   del enlace DSI); con el aviso el panel sigue y el core enciende/apaga el KTZ en
   `enable`/`disable`. NOTA L44 vs L39b: el comentario original decía "este port no
   tiene I2C"; desde L43 el bus existe (i2c-2, KTZ en 0x11, ciclo #617 VERDE), así que
   el aviso cubre ORDEN de probe, no ausencia de bus (documentado en el propio hunk).
   Se retiran `o82_bl_update_status` (DCS 0x51, que el vendor NO usa en este panel
   ID 0x14), `o82_bl_ops`, `o82_create_backlight` y los `backlight_enable/disable` de
   `prepare`/`unprepare`. Diff: `build/gates/patches/l44-panel-backlight.diff`
   (147 líneas, estilo l43; incluye el comentario one-shot corregido, C1 de la crítica).
3. **Compatibilidad DT↔driver verificada**: el s286 declara
   `compatible = "ktz,ktz8866"` (generado por `charge/mkdtbo-s283.py:82`, con gate
   que lo exige en `mkdtbo-s283.py:164`) y el driver porta exactamente
   `"ktz,ktz8866"` (`ktz8866.c:570`). Coincidencia exacta.

## Artefactos

- Kernel (pendiente de build): `build/kernel-pokes/k52L44-build/arch/arm64/boot/Image.gz`
  (comando exacto abajo; config `build/kernel-config/k52L44.config` = `k52L43.config`
  + 1 línea `CONFIG_BACKLIGHT_KTZ8866=y`, verificado que sobrevive `olddefconfig`:
  deps I2C/REGMAP_I2C/REGULATOR/BACKLIGHT_CLASS satisfechas en =y).
- Boot: `build/bootimg/boot-uke-k52L44.img` — **repack OBLIGATORIO con `--dsid`**:
  `python3 docs/historia/gates-palawan/repack-k52L44.py --dsid`
  (clon de `repack-k52L43.py`; cmdline byte-idéntica a L19/L43: 580 B con `video=DSI-1:d`
  + `msm.uke_gmu_shared=0`).
- **dtbo: NO se toca** — sigue el `s286` `33d153f2cec617e2a7c8512559d57a06e1a9c15844b57106ee0891374aa2f419`
  flasheado en #616 (ya trae el nodo `ktz8866@11` y `panel@0/backlight = <&ktz_bl_0>`).
- Gates del repack: heredados de L43 (`UKE-L43-ICC` x1 + `X9I2C-icc-get-ok` x1) +
  nuevos 3 strings KTZ built-in x1 c/u (`ktz8866 backlight 0x%02x ,exponential
  brightness %d` + `probe sucess end` + `ktz8866 backlight out of 4095 too large!!!`;
  los 3 llevan prefijo `ktz8866`, verificado únicos **a nivel de fichero** por `grep -rlF` —
  por eso NO hizo falta añadir marcador `UKE-L44-*`). G0 vigila 11 fuentes por mtime
  (las 10 de L43 + `drivers/video/backlight/ktz8866.c`).
- Build (NO ejecutado; lo corre el orquestador, desprendido por el propio script,
  log en `build/logs/build-k52L44.log`):
  `build/gates/build-fast.sh --src ~/proyectos/omarchy-uke/build/kernel-pokes/k52-L16-tree --cfg ~/proyectos/omarchy-uke/build/kernel-config/k52L44.config --out ~/proyectos/omarchy-uke/build/kernel-pokes/k52L44-build --tag k52L44`

## Criterio pasa/falla (prefijado, comandos exactos)

PASA (tras el boot, por SSH; display apagado — este ciclo NO enciende imagen):
1. `dmesg | grep -c 'UKE-L43-ICC'` ≥ 1 **y** `dmesg | grep -c 'X9I2C-icc-get-ok'` ≥ 1
   (sin regresión L43; nivel 6/pr_info: **no salen en consola con `loglevel=4`** —
   hace falta `dmesg` por SSH, doble captura ACM + SSH).
2. `dmesg | grep -c 'probe sucess end'` ≥ 1 (sic, con la errata vendor) **y**
   `cat /sys/bus/i2c/devices/2-0011/driver` no vacío (el KTZ bindea al driver;
   en L43 ese enlace estaba vacío).
3. `/sys/class/backlight/` NO vacío (`ls` muestra p.ej. `2-0011`); `cat
   /sys/class/backlight/*/max_brightness` = **4095**.
3b. **`dmesg | grep -c 'sin backlight externo'` = 0** (el `dev_warn` del panel NO
   debe aparecer: prueba que `drm_panel_of_backlight` del probe resolvió el KTZ.
   El aviso es ONE-SHOT: si aparece, es orden de probe panel<KTZ y la parte panel
   del ciclo FALLA aunque el KTZ por sysfs pase — anotarlo así).
4. Escritura de brillo mueve el chip: `echo <N> > /sys/class/backlight/*/brightness`
   (p. ej. N=307) y `i2cget`/`i2cdump` del KTZ (addr 0x11, bus 2) muestra cambios en
   **0x04/0x05** (BRT LSB/MSB) y **0x08** = 0x7F (encendido) / con N=0, 0x08 = 0x3F
   (apagado). Bonus: con B1 corregido el probe ya fija brightness 0x133 y llama a
   `update_status` ⇒ la luz del panel **puede encenderse al arrancar**; anotar si se ve.
FALLA: wedge / 0 B de consola / regreso a fastboot / `2-0011` sin driver **con**
`probe sucess end` ausente / `backlight` vacío **sin** el `dev_warn` del panel /
cualquier regresión L43 (bus i2c-2 ausente, sin ACK en 0x11).

## Rollback (nombres y shas exactos)

- `boot_a` ← `build/bootimg/boot-uke-k52L43.img` sha
  `5a6d1dee3ee111c5c0a7c40869cc9bf0b8933a7ee7daa9d30e882867e3ec9d6d` (ciclo #617
  VERDE; el que VIVE ahora).
- `dtbo_a` ← NO se toca (solo si hiciera falta) `build/bootimg/s286-boot-dtbo-gpu-display-gpi-i2c-ktz.img` sha
  `33d153f2cec617e2a7c8512559d57a06e1a9c15844b57106ee0891374aa2f419`.
- `boot` bueno histórico: `build/bootimg/boot-uke-k52L19.img` sha
  `71d89ca6e875941b75af012ac24d20fb7690de407fa341923f2d896557ee51a9`.

## Gates del flash

Batería ≥3700 mV (medida en fastboot), `slot-retry-count` leído antes/después, lector ACM único
armado antes del reboot, `fastboot set_active a` SIEMPRE, sha pre-registrado en el ledger antes de
escribir, y `fastboot reboot` (sin `-f`).

## Nota de alcance (honesta)

Este ciclo **no enciende imagen**: enciende el **BACKLIGHT** (el canal sysfs→I2C→KTZ→LEDs,
con display apagado). El panel sigue sin PPS/host-video en este linaje (eso vive en el
linaje L39, no traído aquí a propósito: un cambio por ciclo). Lo que este ciclo prueba es
que el kernel del linaje vivo puede **probea el panel contra un backlight externo real**
(`drm_panel_of_backlight` resuelve) y **encender/apagar su luz por sysfs**. Si PASA, el
siguiente candidato es traer el path de vídeo (PPS/host) o restaurar `vci` según decida
el orquestador.
