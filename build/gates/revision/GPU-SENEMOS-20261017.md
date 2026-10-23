# GPU senemos (7.2.9-senemos.1.4054.3-ouke2): por que `failed to load adreno gpu` y siguiente paso

**Fecha de medicion: 17-oct-2026 ~23:0x** (tablet arriba 1 h 01 min, slot `_a` segun `qbootctl`).
**Tipo**: diagnostico por lectura de codigo + lectura del aparato (SOLO LECTURA). 0 flashes, 0 escrituras en
sysfs/debugfs, 0 modprobe/rmmod, 0 reboot. Sin `git commit`.
**Etiquetas**: MEDIDO = comando/salida o fichero:linea citado; INFERIDO = razonado, sin medida directa.
**Rutas de codigo**: relativas a `build/kernel-pokes/senemos-7.2.9/linux-7.2.9/` (abreviado `K/`).

---

## 0. Resumen (la respuesta corta)

**Causa (confianza alta, ~90 %): la GPU no tiene IOMMU porque `3da0000.kgsl-smmu` murio con -110 a los 10,98 s y nunca se
reintento; adreno arranca "sin IOMMU" y `msm_iommu_new()` devuelve -ENODEV al crear el VM de la GPU.** La raiz es de
ORDEN, no de DT ni de firmware:

1. `CONFIG_SM_GPUCC_CLIFFS=m` (y ademas `blacklist gpucc_cliffs` en la tablet) => el proveedor de relojes/genpd de la GPU
   no existe durante la ventana de `deferred_probe_timeout` (`CONFIG_DRIVER_DEFERRED_PROBE_TIMEOUT=10`, expira a 10,97 s).
2. Al expirar, el SMMU de la GPU (`power-domains = <&gpucc 0>`) recibe -ETIMEDOUT del attach de genpd y su probe **falla
   para siempre** (`probe with driver arm-smmu failed with error -110`); no queda en la lista de diferidos.
3. En el mismo instante adreno pide su IOMMU, `iommu_fwspec_init()` devuelve -ETIMEDOUT y `of_dma_configure()` lo traga
   ("carry on without it"): el dispositivo de la GPU queda **sin iommu_group**.
4. Tras `modprobe gpucc_cliffs` (2331 s) el reloj `ahb` ya resuelve, adreno llega a `msm_gpu_init()` (salen los dos
   "supply ... not found"), pero `create_vm` -> `msm_iommu_new()` -> `!device_iommu_mapped()` -> **-ENODEV**; el nucleo de
   drivers calla con -ENODEV (`drivers/base/dd.c:637-641`), por eso no hay linea `probe with driver adreno failed`.

**Siguiente paso minimo** (detalle en s6):
- **Sin flash (requiere OK del dueno, escribe en sysfs)**: dos `drivers_probe` EN ESTE ORDEN: primero `3da0000.kgsl-smmu`,
  luego `3d00000.qcom,kgsl-3d0`. El reintento de la GPU sola (el que pedia la nota de las 22:3x) es un no-op: repetiria el
  mismo -ENODEV. Dara `card1` + `renderD128` **sin arrancar el GMU** (el GMU solo arranca en el primer `open()`).
- **Config v3 (1 linea, 0 cambios de DT)**: `CONFIG_SM_GPUCC_CLIFFS=y`. Es lo que tenia el kernel palawan donde la GPU
  funcionaba (`CONFIG_CLK_PALAWAN_GPUCC=y`, `k52L76r-build/.config:6953`).
- **Lo que viene despues y NO esta resuelto** (INFERIDO, riesgo alto): el primer `open()` arranca el GMU; el port de
  senemos **omitio la configuracion de PLL0/PLL1** del gpucc OEM; la tablet no tiene watchdog armado.

---

## 1. Alcance y limitaciones (leer antes de fiarse del contraste con senemos)

- **El repo externo `/tmp/claude-1000/ext-senemos` NO EXISTE** (todo `/tmp` se vacio con el reinicio del PC de las 22:48;
  `ls /tmp` solo muestra ficheros de esa hora). No se pudo leer README, docs ni `src/boot/*adreno*`. **No se re-clono**
  (descargar requiere permiso del dueno; si se quiere cerrar este hueco: pedirlo).
- Sustitutos usados, todos locales y de la propia build:
  `K/senemos-adaptation/patches/` (copia de los 44 parches, con sus mensajes), `K/senemos-adaptation/configs/uke.config`,
  `K/native-generated-v2/ufs.dts` (el overlay del ABL ya preprocesado: incluye el contenido de
  `sm7675-uke-adreno732.dtsi`, ver `ufs.dts:15-130`), `K/arch/arm64/kernel/uke-abl.c`, y la lectura que hizo la sesion
  anterior en `docs/historia/revision/ADOPCION-SENEMOS-20261017.md`.
- Escritura en la tablet: **ninguna** salvo un script auxiliar de 1 KB que copie a `/dev/shm` (tmpfs) y **borre** de
  inmediato (verificado `ls /dev/shm` vacio); el resto de lecturas fueron por `ssh ... bash -s < script` o comandos de
  lectura. DT vivo bajado con `tar` de `/sys/firmware/devicetree/base` y descompilado en el PC (no guardado en el repo).
- Ojo con los nombres de nodo del DT vivo: **no coinciden con su `reg`** (`qcom,gmu@3d69000` tiene `reg[0]=0x3d68000`;
  `syscon@3d99168` tiene `reg=0x3d990a0`). Todo lo de abajo usa `reg`, no el sufijo.

---

## 2. Cronologia medida (log `build/logs/gpu-probe-dmesg-20261017-223258.txt`, dmesg vivo igual)

| t (s) | Evento (linea del log) | Que prueba |
|---|---|---|
| 0,593 | `msm_dpu ae01000.display-controller: no GPU device was found` (1131) | benigno: `msm_open` de card0 llama `load_gpu` con `gpu_pdev=NULL` (`adreno_device.c:80`, `msm_drv.c:265-273`) |
| 10,976-10,981 | `arm-smmu 3da0000.kgsl-smmu: deferred probe timeout, ignoring dependency` + `probe with driver arm-smmu failed with error -110` (1392-1393) | el SMMU de la GPU muere por -ETIMEDOUT del genpd (ver s3) |
| 10,978821 | `adreno 3d00000.qcom,kgsl-3d0: deferred probe timeout, ignoring dependency` (1394) | su `iommus` sin proveedor: `iommu_fwspec_init` -> -ETIMEDOUT (ver s3) |
| 10,980281 | `failed to load adreno gpu` (1395) sin lineas `supply ...` | falla antes de `msm_gpu_init:959`: `get_clocks` -> `Failed to get clk index: 2 (ahb)` (1399, `devices_deferred`) |
| 1673-1676 | 7 reintentos automaticos, mismo patron (2046-2090) | `devices_deferred` re-dispara al cargar modulos; sin gpucc no avanza |
| 2330,998 | `gpu_cc-cliffs 3d90000.clock-controller: Registered GPU CC clocks` (2428) | gpucc cargado a mano |
| 2331,005-026 | `deferred probe timeout...`, `supply vdd not found`, `supply vddcx not found`, `failed to load adreno gpu` (2431-2434) | ahora SI llega a `msm_gpu_init:959-964`; falla ~16 ms despues, en silencio |
| 2401,108-127 | idem en el `drivers_probe` manual (2448-2451) | reproducible, mismo punto |

Otros hechos medidos que cierran el argumento:
- `3da0000.kgsl-smmu`: **sin symlink `driver`**; `/sys/bus/platform/drivers/arm-smmu/` solo lista `15000000.apps-smmu`;
  `/sys/class/iommu/` solo `smmu.0x0000000015000000`.
- `3d00000.qcom,kgsl-3d0` y `3d68000.qcom,gmu`: **sin `iommu_group`** (control: `1d84000.ufshc`, `800000.qcom,gpi-dma`... si lo tienen).
- `/sys/kernel/debug/devices_deferred` solo contiene `regulator.7.bdev` y `arm-scmi.0.auto`: adreno **no** esta diferido
  => su ultimo intento termino con un errno que no es -EPROBE_DEFER (coherente con -ENODEV).
- devlinks: `3d90000.clock-controller -> {3da0000.kgsl-smmu, 3d00000.qcom,kgsl-3d0, 3d68000.qcom,gmu}` estan en
  `sync_state_only=1` (fw_devlink los relajo al expirar el timeout porque el proveedor "no podia casar":
  `drivers/base/core.c:1823-1840`); `adreno` no tiene devlink hacia el SMMU (`iommus` es `.optional=true`,
  `drivers/of/property.c:1544`), asi que **nada garantiza SMMU antes que adreno salvo el -EPROBE_DEFER del IOMMU**.

---

## 3. Cadena causal con codigo (cada eslabon con fichero:linea)

1. **Config**: `K/senemos-adaptation/configs/uke.config:5` `CONFIG_SM_GPUCC_CLIFFS=m` (viene de senemos) y
   `build/kernel-pokes/senemos-build/.config` igual. En la tablet `/etc/modprobe.d/uke-senemos-guard.conf` hace
   `blacklist gpucc_cliffs`. `lsmod` solo muestra `gpucc_cliffs` desde el modprobe manual. `DRM_MSM=y`, `ARM_SMMU=y`,
   `SM_GCC_CLIFFS=y` (todo lo demas de la cadena es built-in).
   - El diseno de senemos (ADOPCION s1.4/s2.5) es `DRM_MSM=m` y todo cargado por **su initramfs** en <10 s; aqui
     `DRM_MSM=y` + gpucc por userspace con blacklist **rompe esa premisa**.
2. **SMMU de la GPU**: `platform_probe` llama `dev_pm_domain_attach` ANTES del `probe` del driver
   (`drivers/base/platform.c:1433-1436`) -> `genpd_dev_pm_attach` (`drivers/pmdomain/core.c:3448-3461`) ->
   `__genpd_dev_pm_attach`: proveedor ausente -> `return driver_deferred_probe_check_state(base_dev)`
   (`core.c:3382`) -> a partir de que `driver_deferred_probe_timeout==0` devuelve **-ETIMEDOUT** y emite el
   `dev_warn("deferred probe timeout, ignoring dependency")` (`drivers/base/dd.c:285-297`). `really_probe` lo imprime como
   `probe with driver arm-smmu failed with error -110` (`dd.c:642-646`). El DT vivo confirma que el SMMU depende de gpucc:
   `kgsl-smmu@3da0000: power-domains = <gpucc 0>`, `clocks = <gpucc 0x11, gcc 0x20, gcc 0x21, gpucc 2>`.
3. **adreno sin IOMMU**: `iommu_fwspec_init()` -> `if (!iommu) return driver_deferred_probe_check_state(dev)`
   (`drivers/iommu/iommu.c:3078-3079`) -> `of_iommu_configure` devuelve -ETIMEDOUT -> `of_dma_configure_id`
   **ignora todo error distinto de -EPROBE_DEFER**: "Take all other IOMMU errors to mean we'll just carry on without
   it" (`drivers/of/device.c:151-161`). Resultado: probe de adreno sigue con `dev->iommu_group == NULL`.
4. **Primer fallo de adreno (antes de gpucc)**: `msm_gpu_init` -> `get_clocks` -> `devm_clk_bulk_get_all`
   (`K/drivers/gpu/drm/msm/msm_gpu.c:949`, `:844`) -> `drivers/clk/clk-bulk.c:32` `Failed to get clk index: 2 (ahb)`
   (el GPU DT declara `clocks = gcc 0x20, gcc 0x21, gpucc 2`, `clock-names = memnoc, snoc, ahb`) => -EPROBE_DEFER.
5. **Fallo actual (con gpucc)**: `msm_gpu_init:973` `gpu->vm = funcs->create_vm()` ->
   `a6xx_create_vm` (`a6xx_gpu.c:2353-2368`) -> `adreno_iommu_create_vm` (`adreno_gpu.c:195-206`) ->
   `msm_iommu_gpu_new` (`msm_iommu.c:777-785`) -> `msm_iommu_new` (`msm_iommu.c:726-733`):
   `if (!device_iommu_mapped(dev)) return ERR_PTR(-ENODEV);` (`include/linux/device.h:918-921`: `dev->iommu_group != NULL`).
   `msm_gpu_init` hace `goto fail` (`msm_gpu.c:974-977`), `a6xx_gpu_init` -> `ERR_PTR(-ENODEV)` (`a6xx_gpu.c:2742-2746`),
   `adreno_bind` imprime `failed to load adreno gpu` y devuelve -ENODEV (`adreno_device.c:240-243`), `msm_drm_init` lo
   propaga (`msm_drv.c:153-158`), y `really_probe` trata -ENODEV/-ENXIO como "rechaza el match" solo con `dev_dbg`
   (`dd.c:637-641`).
   - Este ultimo punto es **evidencia negativa**: cualquier otro errno (-ENOMEM, -EINVAL, -EIO, -ETIMEDOUT) habria impreso
     `probe with driver adreno failed with error N`; no sale. Entre `msm_gpu.c:964` (ultimo mensaje visible) y el fallo no
     hay otro `return` silencioso con -ENODEV mas temprano que el de `create_vm` (solo `msm_devfreq_init`, `void`, y
     `platform_set_drvdata`). El mismo -ENODEV se repetiria en `a6xx_gmu_memory_probe` (`a6xx_gmu.c:1587`) para el GMU.
6. **Por que nada lo reintenta**: el SMMU quedo en fallo duro (no EPROBE_DEFER), adreno devolvio -ENODEV (tampoco
   reencola). El unico reintento es manual (`drivers_probe`).

**Hipotesis descartadas con evidencia** (para no volver a gastar ciclos):

| Hipotesis | Evidencia en contra |
|---|---|
| `qcom_cpucp_mbox`/SCMI hace falta | `failed to setup channel for protocol:0x10` = protocolo SCMI **base**, transporte mailbox CPUCP (CPU DVFS). El DT vivo de GPU/GMU/SMMU/gpucc no referencia `scmi`/`cpucp` (grep de las 33 456 lineas del DT: solo nodos `qcom,scmi`, `cpucp_fw_region`, ninguno enlazado a la cadena GPU). Es ruido de cada re-disparo de diferidos. |
| Falta firmware | `/lib/firmware/qcom/gen71100_{sqe.fw 66036 B, gmu.bin 80680 B, zap.mbn 12088 B}` presentes (y copias en `/lib/firmware`). Ademas el firmware se carga **perezosamente en el primer open** (`msm_drv.c:265-273` "load gpu on open", `adreno_device.c:92-100`); el probe ni lo toca. Zap: ELF de 1 segmento `0x3f4` B en paddr `0x1000` -> cabe en la region de 8 KiB `gpu_microcode_region@9899a000` (phandle `0x29e`). |
| Chip-id desconocido | `compatible = "qcom,adreno-43030b00","qcom,adreno"` + `qcom,chipid = 0x43030b00`; `find_chipid` OK y el catalogo trae `0x43030b00` (`a6xx_catalog.c:1618-1650`, parche 0036). El probe llega a `msm_gpu_init`. |
| OPP / ICC | No sale `Unable to find/set the OPP table` (`adreno_gpu.c:1118,1122`). Niveles OPP GPU 56,64,128,192,224,256,320,384,400 estan todos en `gfx.lvl` del cmd-db vivo (`/sys/kernel/debug/cmd-db`: `gfx.lvl [38 00 40 00 80 00 c0 00 e0 00 00 01 40 01 80 01 90 01 ...]`); GMU 64/128 en `cx.lvl`; `mx.lvl` cubre hasta 416; BCM `MC0`,`SH0`,`ACV` presentes; `interconnect_summary` tiene `USUARIO@example.invalid` y `ebi`. |
| Speedbin | `a6xx_read_speedbin` -> `-ENOENT` -> `a6xx_set_supported_hw` devuelve 0 (`a6xx_gpu.c:2594-2631`); el nodo no tiene `nvmem-cells`. |
| LLCC | `25000000.cache-controller` es `qcom,cliffs7-llcc` (sin driver): `llcc_slice_getd` devuelve error pero `a6xx_llc_slices_init` no lo comprueba (`a6xx_gpu.c:2060-2069`). No fatal. |
| gpucc/genpd ausente ahora | `pm_genpd_summary`: `gpu_cc_gx_gdsc off-0`, `gpu_cc_cx_gdsc off-0` registrados; `clk_summary` lista los `gpu_cc_*`. |
| GMU "sin driver" | Esperado: no existe driver de plataforma para `qcom,adreno-gmu*`; `a6xx_gmu_init` toma el `platform_device` con `of_find_device_by_node` (`a6xx_gmu.c:2291,2300`). Solo `arm-smmu-qcom.c:41,44,414` mira esos compatibles (ACTLR). |

---

## 4. Caminos de error de la init gen7 (orden real de ejecucion; estado MEDIDO hoy)

Clave: **PASA** = demostrado por log/estado; **FALLA** = origen de `failed to load`; **sin alcanzar** = por detras del fallo
(INFERIDO a partir del DT/estado vivo).

### 4.1 Probe (`adreno_bind`, se ejecuta al enlazar el platform device)

| # | Paso | Fichero:linea (`K/drivers/gpu/drm/msm/`) | Error posible | Estado |
|---|---|---|---|---|
| 0 | `drm_firmware_drivers_only()` | `msm_drv.c:113` | -ENODEV | PASA |
| 1 | `msm_gpu_probe` (separate_gpu_kms=1) | `adreno_device.c:272-276`, `msm_drv.c:1096-1116` | -ENOMEM, dma mask | PASA (si no, no habria `drm_dev_alloc`) |
| 2 | `find_chipid`/`adreno_info` | `adreno_device.c:221,229` | WARN + -ENXIO | PASA |
| 3 | `info->funcs->init` = `a6xx_gpu_init` | `adreno_device.c:240`; `adreno/a6xx_gpu.c:2660` | | entra |
| 3a | `BUG_ON(!node)` (falta `qcom,gmu`) | `a6xx_gpu.c:2705` | panic | PASA (GPU DT trae `qcom,gmu=<0x482>`) |
| 3b | `a6xx_llc_slices_init` | `a6xx_gpu.c:2715`, `:2060` | ninguno (no se chequea) | PASA (LLCC sin driver, no fatal) |
| 3c | `msm_ioremap(pdev,"cx_mem")` | `a6xx_gpu.c:2727` | ERR_PTR sin chequear aqui | PASA (`reg-names` trae `cx_mem`) |
| 3d | `a6xx_set_supported_hw` (speedbin) | `a6xx_gpu.c:2731,2594-2647` | `dev_err_probe` | PASA (-ENOENT => 0) |
| 3e | `adreno_gpu_init` | `a6xx_gpu.c:2742`; `adreno_gpu.c:1185-1243` | | entra |
| 3e1 | `adreno_get_pwrlevels` = `devm_pm_opp_of_add_table` (+ icc paths al alocar la tabla) | `adreno_gpu.c:1097-1137,1231` | -ENODEV/-EPROBE_DEFER + `DRM_DEV_ERROR` | PASA (sin mensajes) |
| 3e2 | `msm_gpu_init` kthread/mmio/irq | `msm_gpu.c:901,929,936,942` | | PASA (`reg-names kgsl_3d0_reg_memory`, `interrupt-names gpu`) |
| 3e3 | **`get_clocks`** (`memnoc,snoc,ahb`) | `msm_gpu.c:949,844`; `drivers/clk/clk-bulk.c:32` | -EPROBE_DEFER | FALLABA sin gpucc; PASA con gpucc |
| 3e4 | `devm_regulator_get` `vdd`/`vddcx` | `msm_gpu.c:959,964` | solo info "dummy regulator" | PASA (benigno; el nodo GPU no declara supplies) |
| 3e5 | **`create_vm`** -> `msm_iommu_new` | `msm_gpu.c:973`; `msm_iommu.c:726-733` | **-ENODEV si `!iommu_group`** | **FALLA** |
| 3e6 | `msm_gem_kernel_new(memptrs)`, rings, perfcnt | `msm_gpu.c:979,1000,1020` | -ENOMEM + `DRM_DEV_ERROR` | sin alcanzar |
| 3f | `a6xx_gmu_init` | `a6xx_gpu.c:2763`; `adreno/a6xx_gmu.c:2289-2506` | | sin alcanzar |
| 3f1 | `of_find_device_by_node(gmu)` | `a6xx_gmu.c:2291,2300` | -ENODEV | OK en DT (el device `3d68000.qcom,gmu` existe) |
| 3f2 | `of_dma_configure(gmu->dev)` | `a6xx_gmu.c:2305` | -EPROBE_DEFER | depende del SMMU |
| 3f3 | `a6xx_gmu_clocks_probe` (6 relojes, `gmu`,`hub`) | `a6xx_gmu.c:2316,2061-2077` | `ret<1` | OK en DT (indices gpucc 9,0xb,2,0x14 y gcc 0x12,0x20 validos vs `qcom,gpucc-cliffs.h`) |
| 3f4 | `a6xx_gmu_memory_probe` -> `msm_iommu_new(gmu->dev)` | `a6xx_gmu.c:2320,1583-1596` | **-ENODEV si sin SMMU** | sin alcanzar (mismo -ENODEV) |
| 3f5 | memoria GMU (debug/dummy/icache/log/hfi) | `a6xx_gmu.c:2335-2391` | -ENOMEM | sin alcanzar |
| 3f6 | mmio `gmu` + `rscc` + irq `hfi`/`gmu` | `a6xx_gmu.c:2394-2434` | -ENODEV/-EINVAL | OK en DT (`reg-names gmu,rscc,gmu_pdc`; spi 304/305) |
| 3f7 | genpd `cx` por nombre | `a6xx_gmu.c:2436` | -ENODEV/-EPROBE_DEFER | OK (`power-domain-names cx,gx`; `#power-domain-cells=1`; `gpu_cc_cx_gdsc` registrado) |
| 3f8 | `qmp_get` (aoss) | `a6xx_gmu.c:2449-2453` | -EPROBE_DEFER | OK (`c300000.power-controller` ligado a `qcom_aoss_qmp`; `qcom,qmp=<aoss_qmp>`) |
| 3f9 | genpd `gx`; `a6xx_gmu_pwrlevels_probe` (**ret ignorado**); `a6xx_gmu_acd_probe` | `a6xx_gmu.c:2463,2466,2468,1948-2059` | solo `DRM_DEV_ERROR` | OPP/cmd-db coherentes (ver s3); sin `qcom,opp-acd-level` => ACD off |
| 3g | `qcom_ubwc_config_get_data` | `a6xx_gpu.c:2774` | ERR_PTR | OK (`qcom,sm7675` anadido en parche 0036) |
| 4 | `dev_pm_opp_of_find_icc_paths` | `adreno_device.c:246` | -ENODEV | OK (`qnm_gpu`+`ebi` presentes) |

### 4.2 Primer `open()` del nodo DRM (NO ocurre en el probe)

`msm_open` -> `load_gpu` -> `adreno_load_gpu` (`msm_drv.c:198-209,265-273`; `adreno_device.c:68-140`):

| # | Paso | Fichero:linea | Nota |
|---|---|---|---|
| a | `adreno_load_fw` (`gen71100_sqe.fw`, `gen71100_gmu.bin`) | `adreno_device.c:92`; `adreno_gpu.c:607` | ficheros presentes |
| b | `a6xx_ucode_load` / zap `gen71100_zap.mbn`, `qcom_scm_pas_auth_and_reset` | `adreno_device.c:96`; `a6xx_gpu.c:1046,1123-1131`; `adreno_gpu.c:134-149` | SCM disponible (`qcom_scm: convention: smc arm 64`) |
| c | `pm_runtime_get_sync` -> **`a6xx_gmu_resume`** | `adreno_device.c:108`; `a6xx_gmu.c:1311` | **arranque del CM3 del GMU** |
| d | `a6xx_gmu_secure_init`: para `0x43030b00` llama `qcom_scm_gpu_init_regs(ALWAYS_EN|BCL_EN)` | `a6xx_gmu.c:1195-1212` (parche 0036) | llamada SCM sin precedente en este proyecto |
| e | `clk_set_rate(gmu->core_clk, 220 MHz)` y `hub_clk` | `a6xx_gmu.c:1329-1336` | requiere PLL1 (ver s6.5) |
| f | `a6xx_gmu_fw_start` -> release del CM3, poll `FW_INIT_RESULT` | `a6xx_gmu.c:928-969,322` | historico: aqui murieron los intentos de 27-sep/1-oct |
| g | `msm_gpu_hw_init` | `adreno_device.c:116` | |

---

## 5. Contraste con el DT vivo y con la tablet

### 5.1 Que nodo es: hibrido (ABL + overlay de senemos)

MEDIDO. Los **nombres de nodo y ruta** son los del DT del ABL (nomenclatura downstream: `/soc/qcom,kgsl-3d0@3d00000`,
`/soc/qcom,gmu@3d69000`, `/soc/kgsl-smmu@3da0000`), pero **las propiedades las reescribe el overlay de senemos**
(`sm7675-uke-adreno732.dtsi`, `K/native-generated-v2/ufs.dts:15-130`), que `uke-abl.c` fusiona tras validar el layout
legacy (`uke_legacy_layout`, `uke-abl.c:136-185`: reg de 14 celdas de la GPU, GMU de 6, 9 OPP `uke_gpu_opps:92-132`):

| Elemento | DT vivo (MEDIDO) | Esperado por el driver | Veredicto |
|---|---|---|---|
| GPU `compatible` | `qcom,adreno-43030b00`, `qcom,adreno` (el overlay sustituye `qcom,kgsl-3d0`) | `find_chipid` `qcom,adreno-%08x` | OK |
| GPU `reg`/`reg-names` | `3d00000+40000`, `3d9e000+1000`, `3d61000+800` / `kgsl_3d0_reg_memory,cx_mem,cx_dbgc` | idem mainline a7xx | OK |
| GPU `clocks` | `gcc 0x20 (memnoc)`, `gcc 0x21 (snoc)`, `gpucc 2 (ahb)` | opcional en gmu-path, pero **crea dependencia dura de gpucc** | causa del primer defer |
| GPU `iommus` | `<&kgsl_smmu 0 0>` (SID 0 = "SID de la GPU" para pagetables por proceso, `arm-smmu-qcom.c:229-246`) | | OK |
| GPU `interconnects` | `<gem_noc 0x11, mc_virt 0x200>` (`#interconnect-cells=1` de proveedor) | `gfx-mem` | OK (`qnm_gpu` presente) |
| GPU `power-domains` | **ninguno** (igual que mainline sm8550/8650: lo gestiona el GMU) | | OK |
| GPU supplies `vdd`/`vddcx` | no declarados -> dummy | benigno | OK |
| GPU `zap-shader` | `memory-region=<gpu_microcode_region@9899a000>` (8 KiB) | | OK |
| GPU residuos downstream | `qcom,gpu-pwrlevels`, `qcom,bus-table-*`, `qcom,tzone-names`, `qcom,initial-pwrlevel=8` | ignorados | inocuos |
| GMU `compatible` | `qcom,adreno-gmu-732`, `qcom,adreno-gmu` | no hay driver de plataforma (por diseno); ACTLR en `arm-smmu-qcom.c:41,44` | OK |
| GMU `reg` | `gmu 3d68000+37000`, `rscc 3d50000+10000`, `gmu_pdc b280000+10000` | `a6xx_gmu_init:2394-2415` | OK en nombres (valores: ver s5.3) |
| GMU `clocks` | `gpucc 9 (cx_gmu)`, `gpucc 0xb (cxo)`, `gcc 0x12`, `gcc 0x20`, `gpucc 2`, `gpucc 0x14 (hub_cx_int)` | `gmu`,`hub` por nombre | OK |
| GMU `power-domains` | `gpucc 0`, `gpucc 1`, nombres `cx,gx` | `a6xx_gmu.c:2436,2463` | OK (**ya hay provider**) |
| GMU `qcom,qmp` | `<&aoss_qmp>` = `power-controller@c300000` (ligado) | `qmp_get` | OK |
| GMU `iommus` | `<&kgsl_smmu 5 0>` | | OK, **depende del SMMU** |
| GMU residuos | `mboxes=<&qmp_aop 0>` (sin driver), `vdd-supply/vddcx-supply` -> gdsc downstream `status="disabled"` | no se usan | inocuos |
| SMMU GPU | `compatible = qcom,adreno-smmu, qcom,smmu-500, arm,mmu-500` (match en `arm-smmu-qcom.c:894`), `power-domains=<gpucc 0>`, 4 relojes | | **NO ligado** (causa) |
| gpucc | `qcom,cliffs-gpucc`+`syscon`, `#power-domain-cells=1`, gdscs downstream `status="disabled"` | `GPU_CC_CX_GDSC=0`, `GX=1` (`include/dt-bindings/clock/qcom,gpucc-cliffs.h`) | OK |

### 5.2 Estado de la tablet relevante (MEDIDO)

- Proveedores presentes: gcc (built-in), gpucc (modulo, cargado), `qcom_aoss_qmp`, `cmd-db`, `rpmh`, interconnect
  (`qnoc-cliffs-usb`), `qcom_scm`. **Sin driver**: LLCC (`qcom,cliffs7-llcc`), `qcom,qmp-aop` (mbox downstream).
- `/proc/cmdline`: `clk_ignore_unused pd_ignore_unused regulator_ignore_unused fw_devlink.strict=0
  msm.separate_gpu_kms=1 systemd.unit=multi-user.target`. `sddm` esta **enabled** pero inactivo (`multi-user.target` por
  cmdline); nadie tiene `/dev/dri` abierto (`ls -l /proc/*/fd | grep -c /dev/dri` = 0).
- Watchdog: `/dev/watchdog0` es `gunyah-wdt`; `systemctl show RuntimeWatchdogUSec=0` => **no armado**. Un cuelgue exige
  reset fisico.
- `gpu_cc_pll0` y `gpu_cc_pll1`: `rate 0`, `enable N` en `clk_summary` (el Android estable los muestra a 510/440 MHz,
  `docs/historia/revision/INV-GMU-ESTADO-20261008.md` s2.1). `gpu_cc_cx_gmu_clk`, `gpu_cc_hub_cx_int_clk`, `gpu_cc_hub_aon_clk` aparecen `Y`.

### 5.3 Una trampa de lectura ya aclarada
`gds_hw_ctrl = 0x90a0` del gpucc de senemos (`K/drivers/clk/qcom/gpucc-cliffs.c:569`) **coincide** con el `reg` real del
syscon `gpu_cc_cx_gdsc_hw_ctrl` del DT vivo (`0x3d990a0`; el *nombre* del nodo dice `3d99168`). No es una discrepancia.

### 5.4 Que documenta senemos (limitado a lo local, ver s1)
- Config propia: `SM_GPUCC_CLIFFS=m` (`uke.config:5`), `DRM_MSM=m`; todo cargado por su initramfs en <10 s
  (ADOPCION s1.4). **Cmdline forzada con `msm.separate_gpu_kms=1`** (ADOPCION s1.4, `CMDLINE_FORCE`) -> sus dos
  nodos DRM son el esquema que tenemos.
- Su GPU usa el **DT del ABL transformado** (DTB vendor + dtbo stock transformado dentro del kernel por `uke-abl.c`);
  su `sm7675-uke-adreno732.dtsi` es un overlay sobre ese DT (`ufs.dts`), no un DT propio (el DTS independiente del
  parche 0007 "solo se compila").
- Sus parches de GPU son un **candidato** sin aceptacion fisica: el 0036 dice "Keep preemption, IFPC and high GPU
  operating points outside this candidate", el README de 0021 "do not establish DRM or accelerated graphics", y el 0039
  describe un fallo observado con `separate_gpu_kms=0` y sin master de display (el componente nunca llego a enlazar).
  **No hay evidencia local de que senemos haya llegado a abrir `renderD128` en Uke.**

---

## 6. Siguiente paso minimo y experimentos

### 6.1 Lo que NO hay que hacer
- **No** repetir `drivers_probe` solo de `3d00000.qcom,kgsl-3d0`: es un no-op (mismo -ENODEV; ya se hizo a las 2401 s).
- **No** abrir `/dev/dri/renderD128` (ni `eglinfo`/`vulkaninfo`/`modetest -M msm`/arrancar `sddm`) hasta decidirlo
  expresamente: el `open()` es el arranque del GMU (s4.2). Con `sddm` enabled, arrancarlo = primer open automatico.

### 6.2 Experimento E1 (propuesto, NO ejecutado; sin flash; requiere OK explicito del dueno)

Prerrequisitos (docs/historia/AGENTS.md): `dmesg -n 7`; **un solo** lector de consola ACM + `ssh ... 'dmesg -w' > fichero` (doble
captura); `sync`; confirmar `systemctl is-active sddm greetd` = inactive y `fuser /dev/dri/*` vacio.

| Paso | Escritura | Esperado si la hipotesis es correcta | Riesgo de cuelgue (INFERIDO) |
|---|---|---|---|
| E1.1 | `echo 3da0000.kgsl-smmu > /sys/bus/platform/drivers_probe` (gpucc ya cargado) | aparece `arm-smmu 3da0000.kgsl-smmu: probing hardware configuration...`; symlink `driver -> arm-smmu`; `/sys/class/iommu/smmu.0x0000000003da0000`; sin WARN | **bajo-medio, ~5 %**: enciende el CX GDSC del gpucc (`gpu_cc_cx_gdsc`, VOTABLE, `gdscr 0x908c`, `hw_ctrl 0x90a0`) y escribe registros de contexto del SMMU de la GPU (sin clientes activos). Precedente de la serie: el SMMU de la GPU probo bien en el kernel palawan ("grupo 0 = GPU, grupo 1 = GMU", NOTAS 27-sep tarde); el wedge de s251 fue `apps-smmu`, no este. Modos de fallo recuperables: `WARN "gpu_cc_cx_gdsc status stuck at 'on'"` (`drivers/clk/qcom/gdsc.c:192`) + -ETIMEDOUT. |
| E1.2 | `echo 3d00000.qcom,kgsl-3d0 > /sys/bus/platform/drivers_probe` | `[drm] Initialized msm 1.13.0 for 3d00000.qcom,kgsl-3d0 on minor 1`; `/dev/dri/card1` y `renderD128`; `iommu_group` en GPU y GMU | **bajo, ~3 %**: todo es del lado CPU (SMMU, memoria del GMU, tablas de votos RPMh); `pm_runtime_enable` y el firmware NO ocurren aqui (`adreno_load_gpu` es lazy). |

Si E1.1 falla, la linea de dmesg dice cual de estas es la siguiente hipotesis (en este orden de probabilidad):
(H2) CX GDSC no sube (WARN `status stuck`) -> revisar rail CX (`vdd_cx` rpmh) y `gds_hw_ctrl`;
(H3) arm-smmu rechaza el contexto (`qcom_adreno_smmu_init_context`, `arm-smmu-qcom.c:358-410`);
(H4) clk `hlos` `gpu_cc_hlos1_vote_gpu_smmu_clk` no habilita. Si E1.2 falla con -EPROBE_DEFER, mirar
`a6xx_gmu_init` (3f2/3f7/3f8).
**Criterio de aborto**: si la sesion SSH no responde 30 s tras el `echo`, NO repetir; reset fisico, sin recuperacion
automatica (watchdog no armado); registrar el ciclo y no reintentar mas de una vez (regla de 3 ciclos).

### 6.3 Experimento E2 (propuesto; persistente sin flash de boot.img; alternativa a E1 o complemento)
Un unit `systemd` oneshot `Before=sysinit.target` que haga `modprobe gpucc_cliffs` (mas quitar el `blacklist` de
`uke-senemos-guard.conf`), para que gpucc este disponible a ~2-3 s en vez de a los 10,97 s del timeout. **Requiere
reiniciar** (con `sync`; sin `reboot -f`) y gasta un reintento de slot. Riesgo: ~5 % de cuelgue en arranque (el mismo
codigo corrio sin cuelgue en caliente); `systemd.unit=multi-user.target` evita que `sddm` abra el nodo. No determinista
como la config, pero sin recompilar.

### 6.4 Cambio v3 recomendado (kernel, DT sin tocar)
1. **`CONFIG_SM_GPUCC_CLIFFS=y`** (`senemos-build/.config` / script de deltas). El driver ya esta escrito para ello
   (`subsys_initcall`, `gpucc-cliffs.c:681`); la Kconfig depende de `SM_GCC_CLIFFS` (=y). Efecto esperado: `gpucc`
   registra antes que `arm-smmu`/`adreno`, ambos ligan en el arranque, `renderD128` existe sin ningun modprobe.
   Es **exactamente** la configuracion del kernel donde la GPU funciono (`CONFIG_CLK_PALAWAN_GPUCC=y` en
   `build/kernel-pokes/k52L76r-build/.config:6953` y `l39-config`), con el mismo `DRIVER_DEFERRED_PROBE_TIMEOUT=10`.
2. Quitar `blacklist gpucc_cliffs` (queda sin efecto) y **mantener** `systemd.unit=multi-user.target` mientras el primer
   open no este validado.
3. (Un cambio por ciclo) **No** mezclarlo con la correccion de PLL de abajo.

### 6.5 Lo que viene DESPUES de tener `renderD128` (INFERIDO; alto riesgo)

- **PLL0/PLL1 sin configurar.** El gpucc OEM (`~/gpu-work/uke-oss/drivers/clk/qcom/gpucc-cliffs.c:619-631`,
  identico a `~/proyectos/ubuntu-uke/vendor-src/cliffs/gpucc-cliffs.c`) en el probe llama
  `clk_lucid_ole_pll_configure(&gpu_cc_pll0/pll1, ...)` (L=0x1a/alpha 0x9000 => 510 MHz; L=0x16/alpha 0xeaaa => 440 MHz),
  fuerza siempre-encendidos `0x9004` (CXO_AON) y `0x900c` (DEMET) y limpia `0x9534`. El `gpucc-cliffs.c` de senemos
  (`K/drivers/clk/qcom/gpucc-cliffs.c:624-656`) **no hace nada de eso** ("retain firmware PLLs"), y el estado vivo es
  `gpu_cc_pll1 rate 0` (L=0). `gpu_cc_gmu_clk_src` toma 220/550 MHz de `PLL1/2` con `CLK_SET_RATE_PARENT`
  (`gpucc-cliffs.c:186-214`) y el parche 0036 fija el GMU a 220 MHz (`a6xx_gmu.c:1329-1331`). Prediccion (INFERIDO):
  el primer `a6xx_gmu_resume` falla en `clk_set_rate`/lock de PLL (error suave -ETIMEDOUT) o arranca el CM3 con reloj
  invalido. Candidato a segundo ciclo: portar esas 8 lineas (un cambio, con fila de ledger).
- **El primer open es el punto de mayor riesgo**: la historia propia lo midio como cuelgue duro del CM3 en varios kernels
  (NOTAS 27-sep tarde "No se ha abierto renderD128... cuelgue duro"; 1-oct "EL hallazgo", muertes en `S3-rst0`); en la
  serie palawan se resolvio con parches propios (K18/K20 `kgsl-smmu`/SID 5, orden de release del vendor) que **senemos
  no tiene**. Riesgo estimado de cuelgue en el primer open con senemos tal cual: **30-60 % (INFERIDO, sin medida)**;
  consecuencia: reset fisico, retry de slot gastado. No hacerlo sin vigia, doble captura, bateria >= 3700 mV, cargador y
  fila pre-registrada.
- `qcom_scm_gpu_init_regs(ALWAYS_EN|BCL_EN)` (`a6xx_gmu.c:1209`) es una llamada SCM del parche 0036 sin precedente
  en este proyecto: si TZ la rechaza, `hw_init` falla con error (no cuelga), pero conviene saberlo al leer el log.
- LLCC sin driver: la GPU funciona sin cache de sistema (solo rendimiento).

### 6.6 Ordenacion recomendada
1. (0 flashes, si el dueno da OK) **E1.1 + E1.2**: confirma la causa y da `renderD128` sin tocar el GMU.
2. v3 con **`SM_GPUCC_CLIFFS=y`** (1 cambio) para que el resultado sobreviva al reinicio.
3. Despues, y solo despues, decidir el primer open (con la correccion de PLL como cambio separado si el primer open
   falla suave).

---

## 7. Resumen de medidas citables (todas de solo lectura)

- Cmdline, `lsmod` (solo `gpucc_cliffs`), `pm_genpd_summary` (`gpu_cc_{gx,cx}_gdsc off-0`), `clk_summary` (`gpu_cc_pll0/1`
  `rate 0 N`; `gcc_gpu_memnoc_gfx_clk`/`gcc_gpu_snoc_dvm_gfx_clk` `Y`), `devices_deferred`, `interconnect_summary`
  (`USUARIO@example.invalid`), `/sys/kernel/debug/cmd-db` (`cx.lvl`, `mx.lvl`, `gfx.lvl`, `MC0`, `SH0`, `ACV`),
  symlinks `driver`/`iommu_group`/`supplier:*` de `3da0000.kgsl-smmu`, `3d00000.qcom,kgsl-3d0`, `3d68000.qcom,gmu`,
  `/sys/class/iommu`, `/sys/bus/platform/drivers/{arm-smmu,adreno,qcom_scm,qcom-llcc}`, firmware en `/lib/firmware`,
  `systemctl`/`qbootctl`/watchdog, DT completo (`/sys/firmware/devicetree/base` -> dtc).
- Logs: `build/logs/gpu-probe-dmesg-20261017-223258.txt` (lineas citadas arriba) y dmesg vivo de las ~23:0x.

## Resultado de E1 (17-oct ~23:18, ORDEN DEL DUEÑO) — CONFIRMADO, sin cuelgue
- Lector ACM re-armado (el PC se reinició a las 22:48) + `dmesg -w` → `build/logs/gpu-e1-dmesg-20261017-231759.txt`.
- `echo 3da0000.kgsl-smmu > /sys/bus/platform/drivers_probe` → `arm-smmu 3da0000.kgsl-smmu: SMMUv2 … 22 context banks`,
  `/sys/class/iommu/smmu.0x0000000003da0000`; `3d00000.qcom,kgsl-3d0` → iommu group 8, `3d68000.qcom,gmu` → group 9.
- `echo 3d00000.qcom,kgsl-3d0 > /sys/bus/platform/drivers_probe` → driver adreno, `[drm] Initialized msm 1.13.0 for
  3d00000.qcom,kgsl-3d0 on minor 1`; `/dev/dri/card1` (adreno) + `/dev/dri/renderD128`.
- Nadie abrió renderD128 (0 fds), sddm inactive, sin líneas de GMU/zap/sqe: el GMU sigue sin arrancar (pendiente de orden).
- No persiste: tras reiniciar vuelve el -110 (gpucc =m + blacklist). Persistente = v3 `CONFIG_SM_GPUCC_CLIFFS=y`.

## Kernel v3 preparado (17-oct ~23:5x) — sin flashear (ledger #660 pre-registrado)
- `deltas-omarchy-v3.sh` + `build-senemos-v3.sh`: config-senemos-ouke3 = ouke2 + `CONFIG_SM_GPUCC_CLIFFS=y` (único cambio
  funcional; toolchain 23.1.1 → 23.1.3 por la actualización del PC). Build 0 errores / 0 warnings.
- `repack-senemos.py --v3` (G0–G8 en verde) → `build/bootimg/boot-uke-senemos-7.2.9-v3.img` sha `5c9fb2c6…`; módulos
  `modules-7.2.9-senemos.1.4054.3-ouke3.tar.zst` sha `ac993da4…`.
- `flash-senemos-v3-gated.sh`: `--pre` (en v2: módulos ouke3 + guarda sin gpucc) → fastboot manual → 1 escritura boot_a →
  post con G6 (GPU al arranque sin abrir renderD128). `--check` OK. Rollback `--rollback v2`.
- Ojo de entorno: el `HOME` de las sesiones nuevas es `~/.omarchy-home`; `repack-senemos.py` arma rutas con HOME
  → ejecutarlo con `env HOME=~`.
