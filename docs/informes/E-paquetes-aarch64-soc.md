# E — Paquetes aarch64 para el SoC SM7675 en Arch Linux ARM

> **ERRATA 28-sep-2026 (informe congelado; corrección factual):** donde este informe cifra
> `gen71100_sqe.fw` = 67 348 B (líneas 96, 146, 314) es el tamaño del blob del **QRD**, no del
> **vendor de esta tablet**: el vendor mide **66 036 B** en 3 copias independientes (sha
> `b6df660d…`, ver `build/gates/firmware-gpu.sha256`); se instaló vendor. Detalle en
> `NOTAS-OMARCHY.md` (28-sep-2026, integración).

**Subproyecto E** del proyecto *Omarchy en la Xiaomi Pad 7 «uke»*.
**Fecha:** 26-sep-2026 · **Modo:** investigación en solo lectura, nada ejecutado en la tablet.

**Pregunta que responde:** de todo lo que necesita el port (kernel, firmware WCN6750 + Adreno 732,
Mesa/Turnip, lápiz, utilidades de arranque A/B, herramientas táctiles), **¿qué existe YA como paquete
en Arch Linux ARM / AUR / terceros, y qué hay que construir a mano?**

Método: consultas directas a `archlinuxarm.org/packages`, RPC de `aur.archlinux.org`, índice
`APKINDEX` de Alpine (contraste), repos de `codeberg.org/palawan-mainline` (clonados), árboles git de
`mesa` y `libwacom`, y el `WHENCE` de `linux-firmware`. Cada fila lleva su fuente. Lo no comprobado
va marcado **«no verificado»**.

---

## 1. Resumen ejecutivo

### 1.1 La cifra

De **~55 componentes** que necesita la pila completa (kernel, firmware GPU/WiFi/ADSP, Mesa/Turnip,
input táctil y lápiz, OSK, utilidades de arranque A/B, herramientas de plataforma, entorno gráfico),
el reparto medido es:

| Estado | Nº aprox. | % | Qué es |
|---|---|---|---|
| **Ya empaquetado en Arch ARM (aarch64)** | ~33 | **~60 %** | Kernel genérico, mesa/`vulkan-freedreno`, libinput, libwacom, squeekboard, grim/slurp/swaybg, android-tools, dtc, evtest, hyprland, quickshell, pipewire, networkmanager… |
| **Solo en AUR (hay que compilar con `makepkg`)** | ~10 | **~18 %** | `wvkbd`, `wvkbd-deskintl`, `lisgd`, `rot8-git`, `qbootctl`, **`pd-mapper`**, `tqftpserv`, `rmtfs`, `wayshot`, `squeekboard-git` |
| **No existe en ningún sitio: construir a mano** | ~12 | **~22 %** | **Kernel palawan/lamma**, **firmware gen71100 + wpss del cliffs7**, **parche Mesa para Adreno 732**, **definición libwacom del NT36532**, paquete firmware propio, `omarchy` (repo aarch64 vacío), UCM/audio del dispositivo |

**Veredicto corto:** la **base de userspace está resuelta al ~60 %** y el trabajo de empaquetado real
se concentra en **cinco cosas**: (1) el kernel propio, (2) el firmware que Linux no distribuye,
(3) **un parche de Mesa que NO está upstream y que sin él la GPU no arranca**, (4) la definición de
lápiz, y (5) `pd-mapper`, que **sin él no aparece la interfaz WiFi**.

### 1.2 Los cuatro bloqueadores reales (en orden de dureza)

1. **Adreno 732 no está en Mesa upstream.** `src/freedreno/common/freedreno_devices.py` en Mesa
   `main` (26.3.0-devel) y en el tag `mesa-26.2.3` **no contiene el chip_id `0x43030a00`** (verificado
   con `grep -c` = 0 sobre el árbol clonado). El 735 (`0x43030B00`) sí está. Existe un parche
   comunitario *«freedreno/common: add unofficial support for Adreno 732»* (lfdevs, PR #93, merges
   28-jul-2026) que hay que transportar. **Arch ARM trae Mesa 26.2.3, que no lo lleva.** → GPU sin
   parche = `/dev/dri` sí, compositor no.
2. **Firmware `gen71100_*` inexistente en `linux-firmware`.** El `WHENCE` upstream lista
   `gen70500_*`, `gen70900_*`, `gen71500_*`, `gen71700_*`, `gen80000_*`, `gen80200_*`… y **ningún
   `gen71100`**. Verificado también en el `.apk` real de Alpine: `linux-firmware-qcom` trae
   `gen70500_gmu.bin`, `gen70900_sqe.fw`, `gen71500_gmu.bin`, `gmu_gen70000.bin`, `gmu_gen70900.bin`
   — **no** `gen71100_gmu.bin` ni `gen71100_zap.mbn`.
3. **`pd-mapper` no está en Arch ARM** (404) y solo vive en AUR. Sin `pd-mapper` **el ath11k no
   obtiene la placa**: la interfaz WiFi no aparece. (Confirmado como el bloqueador real en el port de
   Omarchy al OnePlus 6T: *«Wi-Fi on this chip needs pd-mapper and tqftpserv from the linux-msm
   project, which are not packaged for Arch ARM at all. Without pd-mapper the Wi-Fi interface never
   appears.»*)
   🟢 **MATIZ IMPORTANTE (26-sep-2026, medido en el árbol y en el config bueno):** el mapper **ya
   existe dentro del kernel**: `CONFIG_QCOM_PD_MAPPER=m` (y `ath11k=m`, `ath12k=m`) están **ya
   activos** en `~/gpu-work/palawan-linux/configs-uke/config-bueno-actual.config`; el Kconfig está en
   `drivers/soc/qcom/Kconfig:75` y el módulo en `drivers/soc/qcom/Makefile:10`
   (`qcom_pd_mapper.o`),Upstream (serie v7, abr-2024, más «Hawi» may-2026). ⇒ **El PKGBUILD del kernel
   NO tiene que activarlo: basta con cargar el módulo.** El `pd-mapper` de AUR pasa a ser plan B.
   Ojo: `tqftpserv`/`rmtfs` (los otros dos de `linux-msm`) **no** tienen equivalente in-kernel y sí
   habría que empaquetarlos.
4. ~~**`omarchy` no publica aarch64.** `pkgs.omarchy.org` devuelve **404** en todo.~~ 🔴
   **CORREGIDO 26-sep-2026 (verificado en vivo, dos veces): ESTA AFIRMACIÓN ES FALSA.**
   Lo que este informe midió fueron **rutas de directorio** (`/`, `/aarch64/`, `/x86_64/`), que sí
   dan 404; los **`.db` existen**:
   ```
   $ curl -sI https://pkgs.omarchy.org/edge/aarch64/omarchy.db   | head -1   → HTTP/2 200
   $ curl -sI https://pkgs.omarchy.org/stable/aarch64/omarchy.db | head -1   → HTTP/2 200
   $ curl -s …/edge/aarch64/omarchy.db   | zstd -dc | tar tf - | grep -c '/desc$'  → 148
   $ curl -s …/stable/aarch64/omarchy.db | zstd -dc | tar tf - | grep -c '/desc$'  → 22
   $ …/edge/aarch64/ | tar tf - | grep '^omarchy-4'  → omarchy-4.0.4-1/
   $ curl -sI …/edge/aarch64/omarchy-4.0.4-1-aarch64.pkg.tar.zst   → HTTP/2 200  (114 MB)
   $ curl -sI …/stable/aarch64/omarchy-4.0.4-1-aarch64.pkg.tar.zst → 404
   ```
   **Estado real:** `edge/aarch64` → 200 con **148 paquetes, incluido `omarchy-4.0.4-1`**;
   `stable/aarch64` → 200 con **22 paquetes SIN el núcleo del escritorio**. Solo 404: las rutas de
   directorio y el paquete de `stable`. **La vía para la uke es `edge`, nunca `stable`** (C:311).
   **Causa del error:** la cita de `omarchy-mac/omarchy-pkgs-aarch64` («both return 404») era cierta
   cuando se escribió (bug #8645, 27-ago-2026) y **hoy su propio README dice lo contrario**
   («`pkgs.omarchy.org` now serves `edge/aarch64`», push 26-sep-2026 05:10 UTC). Dato caducado de
   terceros sin re-medir.
   → **Consecuencia: NO hay que construir el repo aarch64 de Omarchy.** Se tira el plan de §3.5-c y
   el riesgo R7. Ver `docs/informes/C-hyprland-quickshell-aarch64.md:19,261,311` y §3.1 de
   `docs/historia/G-auditoria-documental.md`, que ya había llegado a este veredicto por otra vía.

### 1.3 Los tres hallazgos que cambian el plan a mejor

- **`palawan-mainline` ya tiene un repo de firmware con EXACTAMENTE lo que falta.**
  `codeberg.org/palawan-mainline/firmware-qualcomm-qrd8635` contiene **682 ficheros**, y entre ellos
  `gen71100_gmu.bin` (80 680 B), `gen71100_sqe.fw` (67 348 B), `gen71100_zap.mbn` (12 088 B) y un
  `wpss.mdt` + `wpss.b00…b12` + `wpss.qdb` completos, más `adsp`, `cdsp`, `modem`, `battmgr`,
  `msbtfw12`/`msnv12` (BT) y `vpu33_4v`. **Esto es el PKGBUILD de firmware, ya empaquetable.**
- **El kernel del fork ya soporta el chip.** El clon de `palawan/v7.2-rc2` trae (leído del árbol):
  `a6xx_catalog.c` con `.chip_ids = ADRENO_CHIP_IDS(0x43030b00)` → `gen71100_sqe.fw`,
  `gen71100_gmu.bin`, `.zapfw = "gen71100_zap.mbn"` (líneas 1618-1630), `lamma.dtsi` con
  `&gmu { compatible = "qcom,adreno-gmu-732.0" }`, y config `arch/arm64/configs/palawan.config`
  (1121 líneas) con `CONFIG_LOCALVERSION="-palawan"`.
- **DanctNIX demuestra que el modelo Arch-ARM-en-tablet funciona y se puede copiar.** Su repo
  `archmobile.mirror.danctnix.org/danctnix/aarch64/` tiene **~115 paquetes propios** ya construidos,
  con la misma forma que necesitaríamos: `linux-pinetab2-7.1.8.danctnix1`, `lisgd`, `wvkbd`,
  `wys`, `wayout`, `superd`, `device-pine64-*`, `danctnix-keyring`, incluso varias
  `*-firmware-*` (`bes2600-firmware`, `brcm-firmware`). Es la plantilla de PKGBUILD + repo + clave.

---

## 2. Tabla grande: componente por componente

Leyenda de la columna **«Construir»**:
`—` = nada que hacer · `AUR` = `makepkg` desde AUR · `PKG` = PKGBUILD propio · `PARCHE` = código a tocar.

### 2.1 Kernel y parches

| Componente | Arch ARM (aarch64) | AUR | Alternativa | Construir | Fuente |
|---|---|---|---|---|---|
| **Kernel genérico** | `linux-aarch64` **7.2.8** (`core`, 375 MiB, 26-sep-2026) — *multi-platform*, **NO sirve**: no tiene palawan/lamma/cliffs7 | `linux-aarch64` no existe en AUR | `linux-aarch64-chromebook`; kernels de DanctNIX | **PKG** (ver §3.1) | [archlinuxarm.org/packages/aarch64/linux-aarch64](https://archlinuxarm.org/packages/aarch64/linux-aarch64) |
| **Headers** | `linux-aarch64-headers` 7.2.8 | — | — | `PKG` (van juntos) | idem |
| **Kernel palawan/lamma** | ❌ **no existe** | ❌ | `linux-pinetab2` (DanctNIX, 7.1.8) como plantilla; `linux-megi` 6.18.39 | **PKG** desde `codeberg.org/palawan-mainline/linux` | API Codeberg: branch `palawan/v7.2-rc2` @ `0d9f7fdf720a` |
| **Fork comunitario del SoC** | — | — | — | **usar** | **[codeberg.org/palawan-mainline/linux](https://codeberg.org/palawan-mainline/linux)** — default branch `palawan/v7.1`, activo 9-jul-2026; espejo de `gitlab.com/palawan-mainline/linux` |
| **Fork U-Boot** | — | — | — | **vacío hoy** | `palawan-mainline/u-boot`: repo **vacío** (`size: 0`, `empty: true`). [codeberg.org](https://codeberg.org/palawan-mainline/u-boot) |
| **Config del SoC** | — | — | — | **existe**: `arch/arm64/configs/palawan.config`, 1121 líneas, `CONFIG_LOCALVERSION="-palawan"`, `CONFIG_SPI_QCOM_GENI=y`, `CONFIG_SCSI_UFS_QCOM=y` | árbol clonado, verificado |
| **Soporte GPU en el fork** | — | — | — | **ya está**: catálogo Adreno con `0x43030b00` → `gen71100_*` | `arch/arm64/boot/dts/qcom/palawan.dtsi:2354-2365`, `a6xx_catalog.c:1618-1630` |
| **DT para *uke*/cliffs7** | — | — | — | ❌ **NO existe**: hay `palawan.dtsi` (SM8635), `palawan-qrd.dts`, `lamma.dtsi`, `lamma-qrd.dts` — **cero menciones a `uke`/`cliffs`** (grep sobre todo el árbol) | verificado en el clon |
| **a6xx_gmu en el fork** | — | — | — | ya soporta 732/735 vía `a7xx` | `a6xx_gmu.c` (108 refs a `adreno_is_a7xx`) |

**Qué es upstreameable (juicio, marcado como tal):** el fork es *casi todo* `dt-bindings` +
`dtsi` iniciales (los ~50 commits son en su mayoría bindings de Palawan/Lamma y `drm/msm` параметros
de DPU/MDSS/GPU). Es material de **serie de parches `[PATCH 0/N] arm64: dts: qcom: Add Palawan/Lamma
support`**, exactamente el patrón que el wiki de pmOS describe como *«current mainlining is being done
by community only»*. Los puntos del enunciado que **no aparecen** en este fork y son específicos del
dispositivo/tu árbol: `pd_mapper` «cliffs», `qcom_battmgr` dialecto Xiaomi, `ath11k`/WPSS, `swiotlb`.
Ver §3.2 para el reparto.

### 2.2 Firmware

| Componente | Arch ARM | AUR | Alternativa | Construir | Fuente |
|---|---|---|---|---|---|
| **`linux-firmware` (base)** | **sí**, `core`, `any`, 17-sep-2026; **0 B** propio: es un metapaquete | — | — | `—` | archlinuxarm.org/packages/any/linux-firmware |
| **`linux-firmware-qcom`** | **sí**, `core`, 537 MiB (¡el subpaquete grande!) | — | — | `—` pero **insuficiente** | idem |
| **Adreno `gen71100_gmu.bin`** | ❌ **NO** (Alpine tampoco: su `linux-firmware-qcom` tiene gen70500/70900/71500/71700/80000/80200, no 71100) | ❌ | **✅ en palawan-mainline** (80 680 B) | **PKG** de firmware | `.apk` de Alpine descargado e inspeccionado con `tar tzf`; [palawan-mainline/firmware-qualcomm-qrd8635](https://codeberg.org/palawan-mainline/firmware-qualcomm-qrd8635) |
| **`gen71100_sqe.fw`** | ❌ | ❌ | ✅ palawan-mainline (67 348 B) | **PKG** | idem |
| **`gen71100_zap.mbn`** | ❌ | ❌ | ✅ palawan-mainline (12 088 B) | **PKG** | idem |
| **WPSS del WCN6750 del cliffs7** | **parcial**: upstream solo trae `sc7280/wpss.mbn`, `qcm6490/wpss.mbn` y `wpss.mdt`→`sc7280/wpss.mbn` | ❌ | ✅ palawan-mainline trae `wpss.mdt` + `wpss.b00…b12` + `wpss.qdb` | **PKG** | `WHENCE` upstream + `tar tzf` del `.apk` Alpine |
| **ath11k WCN6750 (`board-2.bin`, `Notice.txt`)** | ✅ **sí**, en `linux-firmware-qcom` (verificado en el `.apk`: `ath11k/WCN6750/hw1.0/board-2.bin.zst`) | — | — | `—` | `tar tzf linux-firmware-ath11k-20260810-r0.apk` |
| **BT WCN6750 (`qca/msbtfw11/msnv11`)** | ✅ **sí**, en `linux-firmware-qca` | — | — | `—` | idem, `fw_qca.apk` |
| **ADSP del SM7675** | ❌ (solo ADSPs de otros SoC) | ❌ | ✅ palawan-mainline: `adsp.b00…b56`, `adsp2.*` | **PKG** (opcional) | tree API Codeberg |
| **CDSP / modem / `battmgr.jsn`** | ❌ para este SoC | ❌ | ✅ palawan-mainline | **PKG** (opcional) | idem |
| **`/lib/firmware` total del aparato** | — | — | — | referencia: tu inventario son **422 ficheros / 46 MB**; el repo qrd8635 son **682 ficheros** (incluye `modem_pr` con ~150 perfiles de operador, prescindibles) | — |

**Consecuencia práctica:** el subpaquete `linux-firmware-qcom` de Arch ARM (537 MiB) es enorme y **aun
así no trae lo que necesitas**. El PKGBUILD propio no debe *depender* de él: mejor un paquete de
firmware mínimo con los ficheros del qrd8635 + `qca/*6750*` + `ath11k/WCN6750/*` recortados.

### 2.3 Gráficos: Mesa / Freedreno / Turnip (Adreno 732)

| Componente | Arch ARM (aarch64) | AUR | Alternativa | Construir | Fuente |
|---|---|---|---|---|---|
| **`mesa`** | ✅ **`1:26.2.3-1`** en `extra` (17-sep-2026), 64 MiB | `mesa-git` 26.3.0_devel.228038 (**192 votos**) | — | `—` (pero ver parche) | [archlinuxarm.org/packages/aarch64/mesa](https://archlinuxarm.org/packages/aarch64/mesa) |
| **`vulkan-freedreno`** (Turnip) | ✅ **sí**, `extra`, 15 MiB, trae el `provides=vulkan-driver` | — | — | **PARCHE obligatorio** | [archlinuxarm.org/packages/aarch64/vulkan-freedreno](https://archlinuxarm.org/packages/aarch64/vulkan-freedreno) |
| **`vulkan-swrast`** | ✅ sí (fallback software) | — | — | `—` | archlinuxarm.org WSR |
| **`libva-mesa-driver` / `mesa-libgl`** | ✅ (subpaquetes de `mesa`) | — | — | `—` | ficha de `mesa` (col. `provides`) |
| **`mesa-utils` / `mesa-demos`** | ✅ sí | — | — | `—` | archlinuxarm.org |
| **Adreno 732 (`0x43030a00`) en Mesa** | ❌ **NO está upstream** — 0 ocurrencias en `main` (26.3.0-devel) **y 0 en el tag `mesa-26.2.3`** | ❌ (ni `mesa-git`) | parche de **lfdevs PR #93** (28-jul-2026) *«freedreno/common: add unofficial support for Adreno 732»*; builds Turnip «Gmem» de k1mch11 / Mr Purple | **PARCHE** sobre `freedreno_devices.py` → `mesa-git` local | `grep -c 43030a00` = **0** en `git cat-file ... mesa-26.2.3:src/freedreno/common/freedreno_devices.py`; [PR #93](https://github.com/lfdevs/mesa-for-android-container/pull/93) |
| **Adreno 735 (`0x43030B00`)** | ✅ sí en Mesa main (`GPUId(chip_id=0x43030B00, name="FD735")`, `[a7xx_base, a7xx_gen2, ...]`) | — | — | `—` | `freedreno_devices.py` líneas 1216-1217 |
| **Familia/generación correcta a usar** | — | — | 732 debe heredar `a7xx_gen2` (el 735 usa `a7xx_gen2` con `num_ccu=3`, `tile_align_w=96`) | dato para el parche | idem |
| **`libdrm`** | ✅ `extra` | — | — | `—` | archlinuxarm.org |

**Nota técnica para el parche:** el 732 es la versión recortada del X1-45/735. La fila a duplicar es la
de `0x43030B00`/`Adreno X1-45` (`num_ccu=3`), cambiando el `chip_id` a `0x43030a00` y su
`speedbin`/`opp-table` a los del `lamma.dtsi` del fork (que ya trae 255 MHz → 950 MHz con los
`RPMH_REGULATOR_LEVEL_*` correctos). Un comentario en el árbol de Mesa advierte que soporte para
710/720/732/735 *«has been removed and restored more than once»* → **guardar copia del parche que
funcione**.

### 2.4 Input, táctil y lápiz (NT36532)

| Componente | Arch ARM (aarch64) | AUR | Alternativa | Construir | Fuente |
|---|---|---|---|---|---|
| **`libinput`** | ✅ `extra` (lib `libinput.so=10-64`), 18-sep-2026 | — | — | `—` | archlinuxarm.org |
| **`libinput-tools`** | ✅ (subpaquete) → da `libinput record`/`debug-events` | — | — | `—` | idem |
| **`libwacom`** | ✅ `extra`, **1.8 MiB**, 8-sep-2026 | `libwacom-surface` (parche MS), `lib32-libwacom` | upstream 2.20.0 | `—` binario; **PKG** de la definición | archlinuxarm.org; [libwacom](https://github.com/linuxwacom/libwacom) |
| **Definición `.tablet` del NT36532** | ❌ no existe | ❌ | **`/etc/libwacom/*.tablet` propio** (precedencia sobre `/usr/share/libwacom/`) | **CONFIG**, no compilar | [wiki: Tablet Definition Files](https://github.com/linuxwacom/libwacom/wiki/Tablet-Definition-Files) |
| **Comodín «genérico» de libwacom** | — | — | ✅ **existe** `data/generic.tablet`: `Name=Generic`, `DeviceMatch=generic`, `IntegratedIn=Display;System;`, `Stylus=true` | usar como base | `libwacom-repo/data/generic.tablet` (clonado, verificado) |
| **Plantilla integrada-de-pantalla** | — | — | ✅ `data/lenovo-ideapad-duet.tablet`: `Class=ISDV4`, `DeviceMatch=i2c\|27c6\|0e30`, `IntegratedIn=Display;System`, `Touch=true` | copiar y adaptar | idem |
| **⚠️ Limitación dura: bus SPI** | — | — | libwacom **solo conoce `usb`, `serial`, `bluetooth`, `i2c`** (`bus_from_str()` en `libwacom-database.c:168-179`; `WBUSTYPE_*` en `libwacom.h:151-155`; `get_bus_vid_pid()` mapea `bus_id` 3/5/24 → usb/bt/i2c). **No hay `spi`.** | **PARCHE** en libwacom **o** declarar el lápiz por otro bus | `libwacom.c:154-168` y `libwacom-database.c:168-179` |
| **Udev/hwdb de libwacom** | ✅ viene con el paquete: `65-libwacom.rules` + `65-libwacom.hwdb` generado por `libwacom-update-db.py` | — | — | `—`; para un `.tablet` en `/etc/libwacom` hay que **regenerar el hwdb** | `tools/65-libwacom.rules.in`, `tools/libwacom-update-db.py` |
| **`wacom-hid-descriptors` (sysinfo)** | — | — | ✅ script oficial que **autogenera un `.tablet`** | usar en la tablet | wiki: Adding a new device |
| **Resolución del eje (hwdb 60-evdev)** | — | — | editable en `/etc/udev/hwdb.d/` | **CONFIG** | — |
| **`evtest`** | ✅ `extra`, 68 KiB | — | — | `—` | archlinuxarm.org |
| **`libevdev` / `python-libevdev`** | ✅ `extra` ambos | — | — | `—` | idem |
| **`wtype`** | ✅ `extra` | — | — | `—` | idem |
| **`wlrctl`** | ❌ 404 | — | — | `PKG` trivial (meson) | — |
| **Driver de kernel del NT36532** | ❌ | — | — | **PORT nuevo** (fuera de alcance de este informe; el doc base `informe-stylus-linux-2026.md` que cita **no está en esta máquina**) | — |

**Conclusión del bloque lápiz:** el binario de libwacom **ya está** en Arch ARM. Lo que falta es
(a) la entrada del dispositivo y (b) que libwacom **entienda el bus del NT36532**. Si el táctil
acaba apareciendo como `i2c` o `unknown` en `udev`, la entrada con `DeviceMatch=usb|…`/`i2c|…` es
directa; si aparece como `spi`, hace falta el parche de 3 líneas en `bus_from_str()`.

### 2.5 Arranque A/B, fastboot y herramientas de plataforma

| Componente | Arch ARM (aarch64) | AUR | Alternativa | Construir | Fuente |
|---|---|---|---|---|---|
| **`qbootctl`** | ❌ **404** | ✅ **`qbootctl 0.2.2-1`** (maint. `taotieren`, 0 votos, subido 5-feb-2025) | **Alpine: `qbootctl 0.2.2-r1` + `qbootctl-openrc` + `qbootctl-systemd`** (maint. *Casey Connolly* — el autor de pmOS) | **AUR** (`makepkg` en aarch64) | [AUR/qbootctl](https://aur.archlinux.org/packages/qbootctl); [github.com/linux-msm/qbootctl](https://github.com/linux-msm/qbootctl); `APKINDEX` Alpine |
| **¿Es independiente de pmOS?** | — | — | ✅ **SÍ**: es meson + C, de **AOSP `bootctrl`** *«bastardised to build and run on a musl/glibc system»*. Dependencias: `zlib-dev`, `meson`, `cmake`, `linux-headers`. **Nada de pmOS** | — | `README.md` de linux-msm/qbootctl |
| **Qué necesita del kernel** | — | — | acceso a **UFS** (`/dev/…`), **GPT** de las particiones A/B, y el `misc`/BCB. Opción `-i`: *«still write the GPT headers even if the UFS bLun can't be changed»* | — | `README.md` (uso: `-c -m -s -u -b -n -x`) |
| **`android-tools` (fastboot/adb)** | ✅ **`extra`, 18 MiB**, 7-sep-2026 | — | — | `—` | archlinuxarm.org |
| **`dtc` + `libfdt`** | ✅ `extra` (`libfdt.so=1-64`), 6-jul-2026 | `dtc-git` 1.4.1 | Alpine 1.7.2 | `—` | idem |
| **`fdtoverlay`** | ✅ viene con `dtc` | — | — | `—` (¡clave para validar dtbo!) | ficha `dtc` |
| **`abootimg`** | ❌ | ✅ `abootimg-git r38.7e127fe` (**31 votos**) + `abootimg 0.6-1` | — | **AUR** | AUR RPC |
| **`mkbootimg`** | ❌ | ✅ `mkbootimg-git 2022.11.09.r1.g9d010816` (fork de osm0sis) | — | **AUR** (o script propio, ver §3) | AUR RPC |
| **`avbtool`** | ❌ | ❌ **no existe** | repo de `android-platform-tools`; `avbtool` es Python puro | **PKG** trivial o copia del script | — |
| **`ueventd`** | ❌ | ❌ | — | **PKG** (nim, de pmOS) | — |
| **`unpackbootimg`** | ❌ | ✅ `fso-unbootimg 0.1.2` | `mkbootimg-git` lo incluye | **AUR** | AUR RPC |
| **`pd-mapper`** ⚠️ | ❌ **404** | ✅ `pd-mapper 1.1-1` + `pd-mapper-git`; maint. `supertecnogym` | Alpine lo tiene; **sin él no hay WiFi** | **AUR crítico** | AUR RPC + 404 de Arch ARM |
| **`tqftpserv`** ⚠️ | ❌ 404 | ✅ `tqftpserv 1.2-1` | Alpine | **AUR crítico** | idem |
| **`rmtfs`** | ❌ 404 | ✅ `rmtfs 1.2-1` | Alpine | **AUR** (para modem/ADSP) | idem |
| **`fastboot` en la tablet** | — | — | `android-tools` ✅ | `—` | — |

> ⚠️ **Trampa AUR en aarch64:** los PKGBUILD de AUR suelen traer `arch=('x86_64')`. `makepkg` en
> aarch64 los rechaza salvo `--ignorearch` **o** parcheando el `arch=`. Comprobado en un port real de
> CachyOS/Arch-ARM a tablet Xiaomi: *«CachyOS Package Installer — currently broken in AUR for aarch64,
> gets skipped during build»*, y en el fork `omarchy-pkgs-aarch64`: *«the AUR recipe is
> arch=('x86_64')… ours is that recipe with arch=('aarch64')»*. **Plan: mantener un mini-repo propio
> con los PKGBUILD re-archivados.**

### 2.6 Utilidades de tablet, OSK, sensores y entorno

| Componente | Arch ARM (aarch64) | AUR | Alternativa | Construir | Fuente |
|---|---|---|---|---|---|
| **`iio-sensor-proxy`** | ✅ **`extra`**, 202 KiB, 3-mar-2026 | `iio-sensor-proxy-git`, `-tuxedo`, `iio-niri 2.3.1` | Alpine 3.9 | `—` | archlinuxarm.org; Alpine APKINDEX |
| **`rot8`** | ❌ 404 | ✅ **`rot8-git 1.0.0+r112`** (5 votos, maint. `gigs`) | — | **AUR** | AUR RPC |
| **`lisgd`** | ❌ 404 | ✅ **`lisgd 0.4.0-1`** (maint. `arenm`) | DanctNIX lo tiene (`lisgd-0.4.0-1-aarch64`) | **AUR o DanctNIX** | AUR RPC; repo DanctNIX |
| **`wvkbd`** | ❌ **404** | ✅ **`wvkbd 0.20-1`** (8 votos) + **`wvkbd-deskintl 0.19.4-1`** ⭐ (el que usa el plugin `maxt.tablet-experience` de Omarchy) + `wvkbd-git` | DanctNIX `wvkbd-0.20-1-aarch64`; Alpine 0.20 | **AUR** | [AUR/wvkbd-deskintl](https://aur.archlinux.org/packages/wvkbd-deskintl) |
| **`squeekboard`** | ✅ **`extra`, 5.8 MiB**, 29-may-2026 (`provides=phosh-osk-provider`) | `squeekboard-git 1.43.0.r13` | Alpine 1.43.1 | `—` | archlinuxarm.org |
| **`maliit-keyboard`** | ❌ 404 | ✅ `maliit-keyboard 2.3.1-3` | — | **AUR** | AUR RPC |
| **`qt6-virtualkeyboard`** | ✅ `extra`, 7.2 MiB | — | — | `—` | archlinuxarm.org |
| **`ydotool`** | ✅ **`extra`**, 136 KiB — ⚠️ **última build 14-jul-2024** (antiguo) | `ydotool-git 1:1.0.4` (18 votos) | — | `—` (o git si falla) | archlinuxarm.org |
| **`wlr-randr`** | ✅ `extra`, 69 KiB | — | Alpine 0.5.0 | `—` | idem |
| **`grim`** | ✅ `extra`, 70 KiB | — | Alpine 1.5.0 | `—` | idem |
| **`slurp`** | ✅ `extra`, 71 KiB | — | Alpine 1.5.0 | `—` | idem |
| **`wayshot`** | ❌ | ✅ `wayshot 1.6.0-1` (10 votos) + `-git`/`-bin`/`-gnome` | Alpine 1.3.1 | **AUR** | AUR RPC |
| **`swaybg`** | ✅ `extra`, 70 KiB | `swaybg-git` (18 votos) | — | `—` | archlinuxarm.org |
| **`superd` / `wys` / `wayout`** | ❌ | ❌ | ✅ DanctNIX los tiene en aarch64 | **DanctNIX** | repo DanctNIX |
| **`hyprland`** | ✅ **`extra`, 64 MiB**, 15-sep-2026, **versión `0.56.2-3`** ✅ (medido 26-sep-2026 en `archlinuxarm.org/packages/aarch64/hyprland`; también dentro de `edge/aarch64/omarchy.db`) | — | Alpine 0.54.3 (**más viejo**) | `—` (0.56 confirmado) | archlinuxarm.org |
| **`quickshell`** | ✅ **`extra`, 7.2 MiB**, 21-ago-2026 | — | Alpine: ❌ no existe | `—` | archlinuxarm.org |
| **`hyprlock`/`hypridle`/`hyprpaper`/`hyprpicker`/`hyprsunset`** | ✅ **todos** en `extra` | — | — | `—` | archlinuxarm.org |
| **`xdg-desktop-portal-hyprland`** | ✅ `extra` | — | — | `—` | idem |
| **`hyprland-qtutils` / `hyprsysteminfo`** | ❌ 404 | ❌ | — | **PKG** | — |
| **`qt6-wayland` / `qt6-declarative` / `layer-shell-qt`** | ✅ todos (`qt6-declarative` 137 MiB) | — | — | `—` | archlinuxarm.org |
| **`pipewire` / `wireplumber` / `pipewire-pulse`** | ✅ todos | — | — | `—` | idem |
| **`networkmanager`** + `nmcli` | ✅ `extra`, 20 MiB (nota: se llama `networkmanager`, no `nmcli`) | — | — | `—` | idem |
| **`bluez` / `bluez-utils`** | ✅ `extra` | — | — | `—` | idem |
| **`polkit` / `at-spi2-core` / `libcanberra`** | ✅ todos | — | — | `—` | idem |
| **`mako`, `fuzzel`, `foot`, `waybar`, `mako`, `fcitx5`** | ✅ todos en `extra` | — | — | `—` | idem |
| **`greetd`** + `-agreety` | ✅ `extra` | — | DanctNIX `greetd-phrog` | `—` | archlinuxarm.org |
| **Fuentes/iconos** (`adwaita-icon-theme`, `cantarell-fonts`, `otf-font-awesome`, `ttf-jetbrains-mono-nerd`) | ✅ todos | — | — | `—` | idem |
| **`snapper` / `btrfs-progs` / `limine`** | ✅ los tres (aunque Limine no se puede usar sin UEFI) | — | DanctNIX demuestra Btrfs+snapshot con **U-Boot + kernel propio** | `—` | archlinuxarm.org |
| **`efibootmgr`** | ✅ (inútil aquí: no hay UEFI) | — | — | `—` | idem |
| **`google-chrome`** | ❌ 404 | — | Firefox/Vivaldi aarch64 | `—` | — |

---

## 3. Lo que hay que construir a mano, en orden

### 3.1 PKGBUILD de kernel propio (`linux-uke` o `linux-palawan`)

Plantilla: combinar el PKGBUILD de `linux-aarch64` de Arch ARM con la forma del `linux-pinetab2`
de DanctNIX (`linux-pinetab2-7.1.8.danctnix1-1-aarch64.pkg.tar.xz`, con su `-headers` separado).

Puntos que la evidencia marca como obligatorios:

| Paso | Detalle | Por qué |
|---|---|---|
| `_kernelname` | usar sufijo propio (`-uke` o `-palawan`) | convivencia con `linux-aarch64` del repo |
| `config` | partir de `arch/arm64/configs/palawan.config` (1121 líneas, ya trae `CONFIG_LOCALVERSION="-palawan"`) | es la config que el fork mantiene |
| Fuente | `git+https://codeberg.org/palawan-mainline/linux#branch=palawan%2Fv7.2-rc2` (`0d9f7fdf720a`) | rama verificada |
| `Image.gz` | Arch ARM usa `Image.gz`; el `mkbootimg` del port necesita el **Image descomprimido + DTB al final** | el port de OnePlus 6T *«appends the fajita device tree to the kernel and wraps both in an Android boot image with mkbootimg»* |
| Módulos + `depmod` | `make modules_install` + `depmod -a` en `build()`/`package()` | ADSP/GPU/ath11k son módulos |
| Firmware en `depends` | `linux-firmware-qca` (BT) + `linux-firmware-ath11k`+ el **paquete propio de firmware** | ver §3.3 |
| **Trampa de compilación del fork** | `ARCH=arm64` **obligatorio** y lanzar con `setsid nohup`: *«sin `ARCH` compila para x86; el entorno rompe `$(MAKE)` por `argv[0]`, y en primer plano es un noop silencioso»* | documentado en la skill del port |
| Herramienta de empaquetado | `makepkg -A` en la tablet, o `--ignorearch`; o cross-compilar desde x86_64 con `aarch64-linux-gnu-gcc` + `ccache` | el port de CachyOS bajó de ~2 h a **10-15 min** cross-compilando |

### 3.2 Qué subir a `palawan-mainline` (parches)

| Parche | Estado | Destino sugerido |
|---|---|---|
| Serie `dt-bindings` + `dtsi` Palawan/Lamma (~50 commits del fork) | ya en el fork | **ya está** en `palawan/v7.2-rc2`; es la base para una serie `[PATCH 0/N]` a `linux-arm-msm` |
| `drm/msm/adreno: Add Adreno 735 support` | **ya en el fork** (`lamma.dtsi` → `adreno-gmu-732.0`) | upstream-able |
| `drm/msm/dpu` + `mdss: Add Palawan support` | **ya en el fork** | upstream-able |
| `remoteproc: qcom_q6v5_pas: Add Palawan ADSP/CDSP/MPSS/WPSS` | **ya en el fork** | upstream-able |
| `scsi: ufs: qcom: Add Palawan compatible` | **ya en el fork** | upstream-able |
| **`dts: qcom: lamma-xiaomi-uke`** | ❌ **NO existe** (0 menciones a `uke`/`cliffs`) | **el parche que falta**: es el DT del dispositivo, y es tuyo |
| **`qcom_battmgr`: dialecto Xiaomi** | ❌ no en el fork | ⚠️ **ya hay trabajo upstream activo**: serie *«power: supply: qcom_battmgr: add Xiaomi taoyao support»* (v4, 15-sep-2026) que resuelve exactamente el problema del desplazamiento de IDs de propiedades (`BATT_CONSTANT_CURRENT` ID 12). **Mirar esa serie antes de escribir la propia.** |
| **`pd_mapper` «cliffs»** | ❌ no en el fork | verificar si el nombre del fichero JSON de `pd-mapper` necesita una entrada nueva |
| **`ath11k` / WPSS** | ❌ no en el fork | ver §3.3: el problema es doble (firmware ausente + selección de la variante `wpss.mbn`) |
| **`arm-smmu-qcom`, `a6xx_gmu`, `swiotlb`** | ya cubiertos por `palawan.dtsi` (`qcom,palawan-smmu-500`, `adreno_smmu`) | **no verificado** cuáles de tus 27 ficheros sin commitear son realmente netos |
| **U-Boot** | repo `palawan-mainline/u-boot` **vacío** | si se quiere arranque propio sin `boot.img`, hay que empezarlo de cero (DanctNIX usa `uboot-pinetab2-2026.07` como referencia) |

### 3.3 PKGBUILD de firmware propio (`uke-firmware` o `qcom-sm7675-firmware`)

Fuente ya lista: **`codeberg.org/palawan-mainline/firmware-qualcomm-qrd8635`** (682 ficheros).

Recorte recomendado para el `install` (evita los 537 MiB de `linux-firmware-qcom`):

```
/usr/lib/firmware/
├── qcom/gen71100_gmu.bin        80680 B    ← NO está en linux-firmware ni en Alpine
├── qcom/gen71100_sqe.fw         67348 B    ← idem
├── qcom/gen71100_zap.mbn        12088 B    ← idem
├── qcom/adsp.mdt + adsp.b00..b56           ← opcional (audio)
├── qcom/wpss.mdt + wpss.b00..b12           ← opcional (WiFi/ADSP coop)
├── qcom/battmgr.jsn / adspr.jsn / …
├── qca/msbtfw12.* / msnv12.*               ← BT del cliffs7 (variante 12, no 11)
└── ath11k/WCN6750/hw1.0/{board-2.bin,Notice.txt}   ← viene de linux-firmware-qca/ath11k
```

⚠️ **Ojo con la variante de WPSS.** El `WHENCE` y el `.apk` de Alpine solo empaquetan
`ath11k/WCN6750/hw1.0/sc7280/wpss.mbn` y `…/qcm6490/wpss.mbn`, con `wpss.mdt → sc7280/wpss.mbn`.
El `wpss` del qrd8635 (`wpss.b02` 461 KB, `wpss.b06` 6,08 MB) es de **palawan/lamma**, no de sc7280.
Hay que decidir si se copia a `ath11k/WCN6750/hw1.0/palawan/wpss.mbn` y se selecciona por DT, o se
sobrescribe `wpss.mdt`. **No verificado cuál es la ruta que el ath11k del fork espera** — hay que
grepear `drivers/net/wireless/ath/ath11k/qmi.c` / `core.c` en el árbol del fork.

Reutilizable de la comparativa: **Alpine es la mejor referencia de empaquetado de firmware aquí** —
parte `linux-firmware` en **105 subpaquetes** (`-ath11k`, `-qca`, `-qcom`, `-adreno`-like
`-powervr`…) con `*.zst` por fichero. Copiar ese esquema es más limpio que el `core/linux-firmware-qcom`
de Arch ARM.

### 3.4 Parche de Mesa para Adreno 732

1. Clonar `mesa-git` del AUR (o el PKGBUILD de `mesa` de Arch ARM).
2. Aplicar el parche de **lfdevs PR #93** (`freedreno/common: add unofficial support for Adreno 732`),
   que añade `GPUId(chip_id=0x43030a00, …)` heredando de `a7xx_gen2` (fila a copiar: la de
   `0x43030B00`/`Adreno X1-45`, `num_ccu=3`).
3. **Verificar con `vulkaninfo` / `vkcube` / `glxinfo`** y con `DISPLAY`/Wayland real.
4. **Guardar el parche versionado**: el comentario de la fuente avisa que este soporte se ha
   *«removed and restored more than once»*.
5. Alternativa rápida para probar: usar un build Turnip *«Gmem»* ya parcheado (k1mch11 / Mr Purple)
   **solo para validar** que la GPU funciona, nunca como paquete final (los builds de Android usan
   el backend **KGSL**, no DRM/MSM — no aplican aquí).

### 3.5 Repo de Omarchy aarch64

- 🔴 **CORREGIDO 26-sep-2026.** ~~El repo oficial **no publica aarch64**.~~ **Falso**: los `.db` dan
  200 en los dos canales. **`edge/aarch64` = 148 paquetes con `omarchy-4.0.4-1` y
  `omarchy-settings-4.0.4-2`**; `stable/aarch64` = 22 sin el núcleo. **Usar `edge`** (arreglo 8–9 de
  `G §6`, aplicado). El camino (a) reutilizar `omarchy-mac/omarchy-pkgs-aarch64` y el (c) construir el
  repo **quedan innecesarios hoy**. Ver el bloque 4 de §1.1 y `G §3.1`.
- **Dos caminos** (el segundo solo si `edge` deja de servirse, que es lo que aún no se sabe —
  incógnita 13 de `F §8.1`):
  - **(a) reutilizar** `github.com/omarchy-mac/omarchy-pkgs-aarch64` (buildea *«unmodified from
    omacom-io/omarchy-pkgs PKGBUILDs»*, con `dotnet-*-bin`, `pinta`, `zed`, `cursor-bin` repackeados
    con `arch=('aarch64')`).
  - **(b) usar el sistema oficial de build**: `omacom-io/omarchy-pkgs` tiene
    `bin/repo release --arch aarch64` (usa **QEMU**, lento) y `.omarchy/upstream.sh` que reporta
    `{"pkgver": …, "sha256sums": {"x86_64": [...], "aarch64": [...]}}`.
- Esto es materia del **subproyecto A**, no del E; aquí queda registrado que **el hueco existe**.

### 3.6 Definición libwacom + hwdb del NT36532

```ini
# /etc/libwacom/xiaomi-uke.tablet  (precedencia sobre /usr/share/libwacom/)
[Device]
Name=<nombre exacto que reporte el kernel en /proc/bus/input/devices>
ModelName=
DeviceMatch=i2c|<vid>|<pid>      ; o el bus que reporte udev — ver aviso de SPI
Width=<mm>
Height=<mm>
IntegratedIn=Display;System
Styli=@generic-with-eraser      ; o @generic-no-eraser

[Features]
Stylus=true
Touch=true
Reversible=false
```

Pasos: (1) recoger el *sysinfo* con el script de `wacom-hid-descriptors`; (2) copiar
`generic.tablet` o `lenovo-ideapad-duet.tablet` como base; (3) probar en `/etc/libwacom/`;
(4) **regenerar el hwdb** con `libwacom-update-db.py` → `65-libwacom.hwdb` (o el `udevadm hwdb`
equivalente), porque las reglas de `65-libwacom.rules` consultan el hwdb, no el `.tablet`
directamente; (5) resolver el eje con `60-evdev.hwdb`.

---

## 4. Estado real de `codeberg.org/palawan-mainline` (leído, no supuesto)

Organización creada **23-abr-2026**. Tres repos:

| Repo | Estado | Detalle medido |
|---|---|---|
| **`linux`** | ✅ **el bueno y activo** | Default branch **`palawan/v7.1`**; ramas: `palawan/v7.1` (`94a1e2329fc9`) y **`palawan/v7.2-rc2`** (`0d9f7fdf720a`, 3-jun-2026). **0 tags, 0 releases, 0 issues abiertos, 0 PRs**. Tamaño 4,98 GB. Último push **9-jul-2026**. Espejo de `gitlab.com/palawan-mainline/linux`. Licencia: kernel. Lenguaje: C. **Autor de los commits: `Alexandr Zubtsov <USUARIO@example.invalid>`** — todos los commits del clon llevan la misma autoría. |
| **`u-boot`** | ❌ **VACÍO** | `size: 0`, `empty: true`, default `main`, último push 19-jun-2026. Espejo de gitlab. **No hay bootloader propio.** |
| **`firmware-qualcomm-qrd8635`** | ✅ **oro puro** | 682 ficheros / ~90 MB. *«Non-free firmware blobs for Qualcomm Reference Devices (QRD)»*. Contiene **`gen71100_gmu.bin`, `gen71100_sqe.fw`, `gen71100_zap.mbn`**, `wpss.*` completo (15 ficheros), `adsp`/`adsp2` (+`_dtb`), `cdsp`, `modem` (+ `modem_pr` con ~150 perfiles `mcfg_sw`), `battmgr`, `ipa_fws`, `msbtfw12`/`msnv12`, `vpu33_4v`. Último push 19-jun-2026. **No hay PKGBUILD ni script de instalación — es un volcado crudo.** |

**Qué contiene `linux` exactamente (leído del clon `--depth 1`):**

- `Makefile`: `VERSION=7 PATCHLEVEL=2 SUBLEVEL=0 EXTRAVERSION=-rc2`. **Nombre clave: `palawan/v7.2-rc2`.**
- `arch/arm64/boot/dts/qcom/`: `palawan.dtsi`, `palawan-qrd.dts`, `lamma.dtsi`, `lamma-qrd.dts`,
  `pm7550.dtsi`, `pm7550ba.dtsi`, `pm7550ba-eliza.dtsi`, `pm8550*`, `pmiv0104.dtsi`.
  **NO hay `uke.dts`, `cliffs.dts` ni `cliffs7`** (grep = 0).
- `arch/arm64/configs/`: **`palawan.config`** (1121 líneas).
- `drivers/gpu/drm/msm/adreno/`: soporta **`0x43030b00`** (Adreno 732/735, familia `ADRENO_7XX_GEN2`)
  con `gen71100_sqe.fw` + `gen71100_gmu.bin` + `gen71100_zap.mbn`; y **`0x43030c00`** (X1-45) con
  `gen71500_*`. Familia `ADRENO_7XX_GEN2` = la correcta para el 732.
- El tag de la versión de `palawan.config` incluye: `CONFIG_NR_CPUS=8`, `CONFIG_CLK_PALAWAN_GCC/GPUCC=y`,
  `CONFIG_PINCTRL_PALAWAN=y`, `CONFIG_INTERCONNECT_QCOM_PALAWAN=y`, `CONFIG_SCSI_UFS_QCOM=y`,
  `CONFIG_SPI_QCOM_GENI=y`, `CONFIG_VIDEO_QCOM_IRIS=m`, `CONFIG_QCOM_FASTRPC=m`.
  **La config del QRD es de panel `visionox,vtdr6130` + táctil `goodix,gt9916`** — el target del
  *uke* es `novatek,o82` + `novatek,nt36532`. **Los drivers de táctil/panel del dispositivo NO están
  en `palawan.config`.**

**Respuesta directa a las preguntas del enunciado:**
- *¿Qué contiene?* Un fork de kernel Linux 7.2-rc2 con Palawan/Lamma (`dtsi`, `dts` de QRD,
  bindings y soporte `drm/msm`/`remoteproc`/`ufs`), un repo de firmware QRD, y un U-Boot vacío.
- *¿Hay dts para cliffs/uke?* **No.** Hay `lamma` (= `cliffs7` / SM7675) **a nivel de SoC**, con DTS
  de **QRD** (placa de referencia de Qualcomm).
  🟢 **CORREGIDO 27-sep-2026: el DTS del uke YA EXISTE** (esta respuesta era falsa). Medido en
  `~/gpu-work/palawan-linux`: `arch/arm64/boot/dts/qcom/xiaomi-uke.dts`, **556 líneas**, **trackeado**,
  último commit `27a08bc20` («dts: xiaomi-uke v3 GPU — encender a732 (0x43030b00) + zap firmware
  uke»), y **compila**: `arch/arm64/boot/dts/qcom/Makefile:46` lo añade a
  `dtb-$(CONFIG_ARCH_QCOM)`. Tiene `model = "Xiaomi Pad 7"` y `compatible = "xiaomi,uke",
  "qcom,lamma"`. **Lo que le falta es la capa de display**, y el propio fichero lo declara en sus
  comentarios (líneas 518-536): `&mdss`, `&mdss_dsi0` con el panel o82, `&mdss_dsi1`, las dos PHY
  con su `vdds-supply`, los grupos de reguladores, y el táctil NT36532 por SPI.
  ⇒ **El trabajo real no es «escribir el DTS» (556 líneas ya están) sino «rellenar ~5 nodos de
  display».** Sigue siendo trabajo del proyecto, pero de otra magnitud.
- *¿Estado?* Activo pero **parado y monocultor**: un solo autor, último push **9-jul-2026** (~2,5
  meses), 0 issues, 0 PRs, 0 releases, 0 estrellas, 1 watcher. Es un *dump* de trabajo personal, no
  un proyecto comunitario con proceso. **No asumas que acepten PRs rápido** — pero la infraestructura
  de firma/bindings sí es de calidad.

---

## 5. Riesgos y no verificado

### 5.1 Riesgos duros

| # | Riesgo | Evidencia | Mitigación |
|---|---|---|---|
| R1 | **Sin el parche de Mesa, no hay GPU usable.** El compositor no arranca (no es config, es driver). | `grep -c 43030a00` = **0** en `main` y en `mesa-26.2.3` | mantener el PKGBUILD `mesa-git` con el parche versionado *antes* de intentar Hyprland |
| R2 | **`pd-mapper` solo en AUR y con `arch=('x86_64')` muy probablemente** → hay que re-archivar | 404 en Arch ARM; AUR maint. `supertecnogym` (mismo mantenedor para los tres `linux-msm`) | repo propio; es un proyecto meson pequeño |
| R3 | **La variante de `wpss.mbn` no está decidida**: upstream solo trae sc7280/qcm6490, el qrd8635 es de palawan | `WHENCE` + `tar tzf` del `.apk` | leer `ath11k/core.c`/`qmi.c` del fork antes de empaquetar; probar ambas rutas |
| R4 | **`linux-firmware-qcom` de Arch ARM pesa 537 MiB y aun así no trae gen71100** | ficha del paquete + inventario del `.apk` | NO depender de él; paquete propio mínimo |
| R5 | **libwacom no soporta el bus `spi`** — el NT36532 va por SPI | `bus_from_str()` solo usb/serial/bluetooth/i2c | parche de 3 líneas en libwacom **o** verificar qué bus reporta udev realmente |
| R6 | **Padre de AUR/aarch64:** los PKGBUILD llegan con `arch=('x86_64')` | documentado en `omarchy-pkgs-aarch64` y en el port de CachyOS | mini-repo propio con PKGBUILD re-archivados |
| R7 | ~~**`omarchy` aarch64 = 404 en todos los canales**~~ **RETIRADO 26-sep-2026: falso.** `edge/aarch64` → 200 con 148 paquetes y `omarchy-4.0.4-1`; `stable/aarch64` → 200 con 22 sin escritorio. Solo 404 las rutas de directorio y el paquete de `stable` | medición en vivo (comando pegado en §1.1 bloque 4) + `G §3.1` | **usar `edge/aarch64`**; no construir repo. Reverificar antes de fijar el mirrorlist (puede ser transitorio: `last-modified` de los `.db` = 23-sep y 26-sep) |
| R8 | **El kernel `linux-aarch64` 7.2.8 de Arch ARM es multi-platform y NO lleva palawan** | no hay `palawan.dtsi` en mainline 7.2 | el kernel propio no es opcional; **es el único camino** |
| R9 | **`palawan-mainline` tiene 1 autor y 0 PRs** — puede no aceptar contribución o morir | metadatos API Codeberg | bifurcar (`fork`) y mantener tu serie propia; publicar los bindings a `linux-arm-msm` |
| R10 | **`linux-firmware` `any` es metapaquete de 0 B** → no se puede "arreglar" añadiendo ficheros ahí | ficha Arch ARM: `Package Size 0` | paquete de firmware independiente, con `conflicts`/`replaces` cuidados |

### 5.2 No verificado (no rellenar con suposiciones)

- Qué hay **realmente** en los **27 ficheros sin commitear** de tu árbol y en tus 29 commits: no los
  he visto. La clasificación «upstream-able» de §3.2 sale de la estructura del fork comunitario,
  **no de tu `git diff`**.
- ~~Si tu árbol ya tiene un DTS `uke` sin commitear~~ ✅ **CONFIRMADO 27-sep-2026**: existe, está
  **trackeado y commiteado** (`27a08bc20`), 556 líneas, con los TODOs de display explícitos en sus
  comentarios. No es un riesgo: es trabajo conocido.
- La **versión exacta de `hyprland`** en Arch ARM. ✅ **RESUELTO 26-sep-2026: `0.56.2-3`**
  (`archlinuxarm.org/packages/aarch64/hyprland`, y presente en `edge/aarch64/omarchy.db`).
  Requisito de Omarchy: **0.56 con config Lua** → cumplido. (Lo confirma C:18, C:202.)
- Si **`iio-sensor-proxy` 3.x de Arch ARM detecta el acelerómetro** de este SoC (el driver IIO del
  SM7675 puede no estar en el fork: `palawan.config` no lo lista explícitamente en lo inspeccionado).
- Si **`qbootctl` funciona en este bootloader** de Xiaomi: la lista de dispositivos validados está en
  la wiki de pmOS (`Android_AB_Slots`), que **no pude leer** (Anubis). **Verificar antes de confiar en
  el marcado de slot.**
- Los **subpaquetes exactos de `linux-firmware` en Arch ARM** (`linux-firmware-ath11k` y
  `linux-firmware-qca` existen en **Alpine**, y Arch ARM tiene el mismo conjunto de 18 subpaquetes,
  pero **no confirmé file-by-file** que el de Arch ARM incluya `WCN6750`). La evidencia
  file-by-file es de Alpine.
- **Omarchy 4.0.3 vs. aarch64**: el análisis del port de OnePlus 6T dice que en 4.0.3 los paquetes
  núcleo pasaron de `arch=any` a `x86_64` *«con 1172 ficheros y cero binarios ELF»*, y que `pacman`
  rechaza un paquete de arquitectura ajena → **eso pincharía un `pacman -U`** hasta re-archivar.

---

## 6. Conclusión operativa (orden recomendado)

```
[0] Recolectar el sysinfo del NT36532 con el script de wacom-hid-descriptors   (antes de tocar nada)
[1] PKGBUILD del kernel: linux-uke  ← codeberg.org/palawan-mainline/linux @ palawan/v7.2-rc2
      └─ + palawan.config + DTS uke (existe; faltan los nodos de display) + ARCH=arm64 + Image.gz + depmod
[2] PKGBUILD de firmware: uke-firmware  ← palawan-mainline/firmware-qualcomm-qrd8635
      └─ recorte: gen71100_* + wpss.* + adsp (opc) + qca/msbtfw12 + ath11k/WCN6750
      └─ resolver ANTES la ruta de wpss.mbn leyendo ath11k/core.c del fork
[3] paquetes críticos desde AUR re-archivados a aarch64:
      pd-mapper · tqftpserv · rmtfs · qbootctl · wvkbd-deskintl · lisgd · rot8-git
      (con arch=(aarch64) en el PKGBUILD; mantener mini-repo propio firmado)
[4] mesa-git+ADRENO732  ← parche lfdevs PR #93 sobre freedreno_devices.py
      └─ validar con vulkaninfo/vkcube ANTES de intentar Hyprland
[5] /etc/libwacom/xiaomi-uke.tablet + regenerar 65-libwacom.hwdb + 60-evdev.hwdb (ejes)
[6] Repo Omarchy aarch64 (subproyecto A) — el hueco está confirmado
[7] Anclar el slot: habilitar qbootctl -m en multi-user.target (patrón DanctNIX/CachyOS)
```

**Lo que esta investigación NO ha hecho:** no se ha ejecutado nada en la tablet, no se ha compilado
nada, no se ha escrito ningún PKGBUILD todavía. Es el inventario y el mapa de dependencias.

---

### Fuentes citadas

| Fuente | URL | Qué se sacó |
|---|---|---|
| Arch Linux ARM · paquetes | https://archlinuxarm.org/packages | fichas y versiones de ~50 paquetes aarch64 |
| AUR RPC v5 | https://aur.archlinux.org/rpc/v5 | existencia, versión, votos y mantenedor |
| Alpine APKINDEX edge | https://dl-cdn.alpinelinux.org/alpine/edge/{main,community}/aarch64/APKINDEX.tar.gz | contraste y **file-list de firmware** vía `.apk` |
| palawan-mainline/linux | https://codeberg.org/palawan-mainline/linux | ramas, commits, DTS, `palawan.config`, catálogo Adreno |
| palawan-mainline/firmware-qualcomm-qrd8635 | https://codeberg.org/palawan-mainline/firmware-qualcomm-qrd8635 | los 682 ficheros de firmware |
| Mesa · freedreno_devices.py | https://gitlab.freedesktop.org/mesa/mesa (clon) | ausencia de `0x43030a00` en main y en `mesa-26.2.3` |
| lfdevs/mesa-for-android-container PR #93 | https://github.com/lfdevs/mesa-for-android-container/pull/93 | parche «unofficial support for Adreno 732» |
| linux-firmware WHENCE | git.kernel.org (mirror) | inventario de firmware upstream |
| linux-msm/qbootctl | https://github.com/linux-msm/qbootctl | independencia de pmOS, deps, uso |
| libwacom | https://github.com/linuxwacom/libwacom | `generic.tablet`, buses soportados, `65-libwacom.rules` |
| DanctNIX Pine64-Arch | https://codeberg.org/DanctNIX/Pine64-Arch + `archmobile.mirror.danctnix.org` | ~115 paquetes aarch64 propios, modelo de repo |
| FisiFla/nabu-cachyos | https://github.com/FisiFla/nabu-cachyos | precedente Arch-ARM en tablet Xiaomi; qbootctl en boot |
| omarchy-pkgs / omarchy-pkgs-aarch64 | https://github.com/omacom-io/omarchy-pkgs · https://github.com/omarchy-mac/omarchy-pkgs-aarch64 | build multi-arch oficial vs. **caducado**: su README hoy dice que `pkgs.omarchy.org` **sí** sirve `edge/aarch64` (26-sep-2026) |
| pmOS wiki (vía extractor) | https://wiki.postmarketos.org/wiki/Qualcomm_Snapdragon_8s_Gen_3/7%2B_Gen_3_(Palawan/Lamma) | estado por componente, «community only» |
| Omarchy en OnePlus 6T (write-up) | https://danieljohnmorris.com/writing/omarchy-on-a-oneplus-6t | `pd-mapper` como bloqueador real de WiFi en Arch ARM |
