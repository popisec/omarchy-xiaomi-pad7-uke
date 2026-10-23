# G1 — GPU-userspace: driver a732, firmware, mesa, riesgo CM3 y runbook post-card0

> Preparado 30-sep-2026 madrugada, SIN tablet (solo lectura de árbol/logs + web).
> Árbol kernel: `/var/tmp/uke-k9-tree` (base K9/K11/K12, fork `7.2-rc2-palawan`).
> Todo con evidencia file:line o comando+salida. Nada de memoria.

---

## 1. DRIVER: soporte del a732 (chipid 0x43030b00) en nuestro árbol

| Pieza | Estado | Evidencia |
|---|---|---|
| Entrada de catálogo del a732 | **PRESENTE** | `drivers/gpu/drm/msm/adreno/a6xx_catalog.c:1618-1647`: `chip_ids = ADRENO_CHIP_IDS(0x43030b00)`, `family = ADRENO_7XX_GEN2` ("a740 family", `adreno_gpu.h:52`), `gmem = SZ_1M+SZ_512K`, quirks `HAS_CACHED_COHERENT\|HAS_HW_APRIV\|PREEMPTION`, `preempt_record_size = 4192*SZ_1K` |
| Funcs gen7 (camino a7xx con GMU, no wrapper) | **PRESENTE** | `a6xx_catalog.c:1626` `.funcs = &a7xx_gpu_funcs`; definición en `a6xx_gpu.c:2868-2906` (submit `a7xx_submit`, pm `a6xx_gmu_pm_suspend/resume`, timestamp `a6xx_gmu_get_timestamp`) |
| Firmware que pide el catálogo | **PRESENTE** | `a6xx_catalog.c:1621-1622` fw SQE `gen71100_sqe.fw` + GMU `gen71100_gmu.bin`; `:1630` `.zapfw = "gen71100_zap.mbn"` |
| GMU chipid | **PRESENTE** | `a6xx_catalog.c:1635` `.gmu_chipid = 0x70b0000`; se programa en `a6xx_gmu.c:1036-1037` (rama `adreno_is_a7xx` escribe `REG_A7XX_GMU_GENERAL_10`) |
| Parseo del compat del DT | **PRESENTE** | `xiaomi-uke.dts` (include `lamma.dtsi`, SoC SM7675): nodo `gpu@3d00000` compatible `"qcom,adreno-43030b00", "qcom,adreno"`; parseo en `adreno_device.c:143-183` (`sscanf(compat, "qcom,adreno-%08x", chipid)`); of_match `"qcom,adreno"` y `"qcom,kgsl-3d0"` en `adreno_device.c:306,311` |
| GMU del DT | **PRESENTE** | `lamma.dtsi:70-72` pisa a `&gmu` con `"qcom,adreno-gmu-732.0", "qcom,adreno-gmu"`; el driver NO filtra por la versión del compatible (solo detecta wrapper: `a6xx_gpu.c:2707-2711`, `of_parse_phandle("qcom,gmu")` + `is_compatible("qcom,adreno-gmu-wrapper")` ⇒ FALSE aquí ⇒ **camino GMU completo con firmware**, no wrapper). Regs `gmu@3d6a000` en `lamma/palawan.dtsi:2470-2473` (el `3d68000` vendor es artefacto del node-name KGSL, ver comentario en `xiaomi-uke.dts:547-549`) |
| Zap shader del DT | **PRESENTE** | `xiaomi-uke.dts:550-556`: `&gpu { status = "okay"; }` + `&gpu_zap_shader { firmware-name = "qcom/uke/gen71100_zap.mbn"; }` (memory-region `gpu_microcode_mem`, `palawan.dtsi:901`) |
| OPPs del a732 | **PRESENTE** | `lamma.dtsi` pisa la opp-table a 255–950 MHz (tope real A732, comentario `xiaomi-uke.dts:541`); sin `speedbins` en el catálogo para 0x43030b00 ⇒ `a6xx_set_supported_hw` sale por -ENOENT sin error (`a6xx_gpu.c:2617-2640`) |
| Instrumentación UKE del camino GPU | **PRESENTE** | `adreno_device.c:241-251` pokes `G1-bind`/`G2-initFAIL`/`G2-initOK`/`G3-icc`; `a6xx_gpu.c` poke `G4-llc`; `a6xx_gmu.c` pokes `F1-fwloop/F2-itcm/F2-dtcm/F3-loopOK/F4-verOK` (`:906-935`) y `S1-rst1/S2-gen9/S3-rst0/S4-poll` (`:316-335`) + `UKE-CM3DBG: dtcm-magic` (`:308-312`) que imprime si la imagen llegó a la RAM vista por el CM3 |
| Cadena de carga de firmware | **PRESENTE** | SQE/GMU vía `adreno_load_fw` → `adreno_request_fw()` (`adreno_gpu.c:591-606`, `524-592`): prueba `qcom/gen71100_*` → legacy `gen71100_*` → helper. ZAP vía `zap_shader_load_mdt` (`adreno_gpu.c:30-160`): si el DT trae `firmware-name` pide `qcom/uke/gen71100_zap.mbn` DIRECTO (`request_firmware_direct`, `:75-79`), luego `qcom_mdt_load` + `qcom_scm_pas_auth_and_reset(pasid)` (`:139-141`) — requiere `CONFIG_QCOM_SCM=y` (✓ `configs-uke/config-bueno-actual.config:2048`) |

**Falta: NADA.** Cero parches de kernel para el a732 (mismo veredicto del comentario `xiaomi-uke.dts:541-542`).

### kgsl-smmu (0x3da0000, 22 CBs / 24 grupos) vs flujo del driver: COMPATIBLE

- El nodo DT `adreno_smmu: iommu@3da0000` (`palawan.dtsi:2536-2575`) trae `"qcom,palawan-smmu-500", "qcom,adreno-smmu", "qcom,smmu-500", "arm,mmu-500"` + `#iommu-cells = <2>`.
- `arm,mmu-500` está en el of_match de arm-smmu (`arm-smmu.c:3462` — el UKE-SMMU-CLK nota explícito que "el kgsl-smmu del mismo DT ya trae `arm,mmu-500` y por eso hoy SI se probea", `arm-smmu.c:3472-3475`).
- `"qcom,adreno-smmu"` activa el impl adreno con **split pagetables**: `arm-smmu-qcom.c:843-846` elige `data->adreno_impl`; `arm-smmu-qcom.c:370-402` instala la interfaz privada GPU↔SMMU (`get_ttbr1_cfg`, `set_ttbr0_cfg`, `get_fault_info`, `set_stall`, PRR para `qcom,smmu-500`+`adreno-smmu` en `:397-402`) y solo para el device GPU (SID 0).
- El driver msm NO toca CBs a mano: crea dominios de traducción explícitos con `iommu_attach_device` (`msm_iommu.c:740-758`); el nº de CBs/grupos lo lee el driver arm-smmu del hardware (ID0/ID1), no hay constante que limite a 22/24. Mapeos: GPU `iommus = <&adreno_smmu 0 0x0>` (`palawan.dtsi:2381`), GMU `iommus = <&adreno_smmu 5 0x0>` (`palawan.dtsi:2514`).
- El parche UKE "dominio por defecto IDENTITY para todos los maestros" (`arm-smmu-qcom.c:719-740`) NO afecta a GPU/GMU: ambos piden su dominio explícito (mismo comentario, y `msm_iommu.c:752`).
- Config: `CONFIG_DRM_MSM=y` + `DRM_MSM_GPU_STATE=y` (`config-bueno-actual.config:4965-4966`), `CONFIG_ARM_SMMU=y`+`CONFIG_ARM_SMMU_QCOM=y` (`:7171,7175`), `CONFIG_IOMMU_SUPPORT=y` (`:7153`).

---

## 2. FIRMWARE: ficheros EXACTOS, dónde están, de dónde salen

### Lo que el driver pedirá al abrir el GPU (load_gpu)

| Petición | Origen de la petición | Ruta probada 1ª | Ruta legacy |
|---|---|---|---|
| `qcom/gen71100_sqe.fw` | `a6xx_catalog.c:1621` (ADRENO_FW_SQE) | `/usr/lib/firmware/qcom/gen71100_sqe.fw` | `/usr/lib/firmware/gen71100_sqe.fw` |
| `qcom/gen71100_gmu.bin` | `a6xx_catalog.c:1622` (ADRENO_FW_GMU) | `/usr/lib/firmware/qcom/gen71100_gmu.bin` | `/usr/lib/firmware/gen71100_gmu.bin` |
| `qcom/uke/gen71100_zap.mbn` | `xiaomi-uke.dts:555` (firmware-name del zap-shader), petición DIRECTA sin fallback (`adreno_gpu.c:75-79`) | `/usr/lib/firmware/qcom/uke/gen71100_zap.mbn` | — (sin fallback real: solo `qcom/gen71100_zap.mbn` del catálogo si el DT NO tuviera firmware-name) |

### Inventario y verificación

1. **Staged en el repo y VERIFICADO HOY (sha256sum ejecutado sobre `build/pkg/uke-gpu-firmware/`)**:
   - `gen71100_gmu.bin` = `435c7bac9a328b8a100df930b84b65b4d579e42be44785d0e60e3729291bb864` ✓
   - `gen71100_sqe.fw`  = `b6df660d109504dbea5a266910b037a33d893a11c6de52f524a5fd112008c401` ✓
   - `gen71100_zap.mbn` = `0c86e4ae6ed618101949965df451510a3216e0f0de1aef4920bd1888a15ea8e6` ✓
   - Idénticos a `build/gates/firmware-gpu.sha256` y al PKGBUILD (`build/pkg/uke-gpu-firmware/PKGBUILD:34-37`). Paquete construido: `uke-gpu-firmware-1-1-any.pkg.tar.zst` (sha `06f75971fde91cf2…`, 106 856 B).
   - Procedencia de los 3 blobs: volcado vendor de ESTA tablet (`proyectos/ubuntu-uke/stock/firmware/`), publicados en uke-staging SHA256SUMS del hermano (11-sep-2026) — cabecera de `firmware-gpu.sha256`. **El zap del QRD (a6a4265b…) NO sirve**: va firmado por SKU (`uke-staging/firmware/README.md`).
2. **En la tablet VIVA: YA INSTALADO** (27-sep, `pacman -U`): `pacman -Qk uke-gpu-firmware` = 14 files 0 missing, con los 8 ficheros en sus rutas y sus shas impresos (`VERIFICACION-ORQUESTADOR.md:793-802`).
3. **En la imagen rootfs `build/rootfs/arch-rootfs.img`: NO ESTÁ** (verificado hoy con debugfs):
   - `debugfs -R "ls /usr/lib/firmware/qcom" …` → `File not found by ext2_lookup` (no existe ni el dir `qcom/`).
   - `debugfs -R "stat /usr/lib/firmware/gen71100_gmu.bin" …` → `File not found by ext2_lookup`.
   - Coherente con `INFORME-A2.md:66-67` ("no hay dir `qcom/` en este snapshot de linux-firmware") y con R2 §6: se instaló DESPUÉS sobre el sistema vivo.
4. **Upstream linux-firmware: NO LO TIENE** (verificado hoy, web):
   - `git.kernel.org/…/linux-firmware.git/tree/qcom` → hay `gen70500_*`, `gen70900_*`, `gen71500_*`, `gen71700_*` pero **ningún `gen71100_*`**.
   - `WHENCE` (plain) → 0 menciones de gen71100.
   - Subdirs `qcom/a730/`, `qcom/a740/` → 404 (no existen).
   - ⇒ **La única fuente es el volcado vendor**, que ya está staged+paquetizado+instalado. `linux-firmware` del repo (rootfs: `linux-firmware-20260622-1`, debugfs `ls /var/lib/pacman/local`) NO trae nada útil para la GPU y NO se necesita.

### Regla operativa (lección del hermano, ya horneada en el paquete)

Sin las copias legacy (raíz de `/usr/lib/firmware`), el `fw_load` del GMU NO da error: se queda en el
usermode helper ~60 s POR FICHERO — parece cuelgue y no lo es (`paquete-firmware-gpu.sh:14-18`,
`measure-cm3.sh:44-48`). El paquete instala las 8 rutas (PKGBUILD:40-47): `qcom/`, `qcom/uke/`,
`qcom/palawan/` y raíz. **Si se re-flashea el rootfs desde la imagen, reinstalar `pacman -U
build/pkg/uke-gpu-firmware/uke-gpu-firmware-1-1-any.pkg.tar.zst`** (R2 §6).

---

## 3. MESA/FREEDRENO: veredicto — el a732 ESTÁ reconocido

| Pregunta | Respuesta | Evidencia |
|---|---|---|
| ¿Mesa conoce el chipid 0x43030b00? | **SÍ** — dispositivo **FD735** (nomenclatura freedreno; FD730=a730, FD740=a740) | `src/freedreno/common/freedreno_devices.py` (mesa main): `GPUId(chip_id=0x43030B00, name="FD735")`, junto al gen a7xx-Gen2. Presente en las tags **mesa-24.3.0, mesa-25.3.0 y mesa-26.2.0** (verificado por fetch de las 3) |
| ¿Desde qué versión? | Al menos desde **24.3.0** (la rework a7xx de Rob Clark entró en 24.3) | fetch raw `mesa-24.3.0/…/freedreno_devices.py` contiene la línea exacta |
| ¿Versión en ALARM aarch64? | **mesa 1:26.2.3-1 (repo extra)** — la reconoce de sobra | `archlinuxarm.org/packages/aarch64/mesa` (fetch hoy) |
| ¿libdrm en ALARM? | **2.4.134-1** (trae `modetest`, `proptest`, `modeprint`, `vbltest`, `drmdevice` en `/usr/bin`) | `archlinuxarm.org/packages/aarch64/libdrm` + file list de `archlinux.org/packages/extra/x86_64/libdrm/files/` |
| ¿Backend GL? | freedreno **fd6** cubre 6xx–7xx (docs.mesa3d.org/drivers/freedreno.html) | docs Mesa |
| Nodos | Con card0 vivo: `/dev/dri/card0` + `/dev/dri/renderD128` (la GPU es componente del mismo DRM device que el display — NO hay card1 salvo `separate_gpu_kms=1`, `msm_drv.c:57-59` vía R2 §6) | R2 §6 |
| Env útiles | `FD_MESA_DEBUG=info` (info del device/compilación ir3), `MESA_DEBUG=1` (errores GL), `MESA_LOADER_DRIVER_OVERRIDE=zink` NO usar (turnip/freedreno es el camino). En kernel: `dmesg` verá `adreno` faults | docs freedreno |

**Veredicto mesa: OK sin compilar nada.** El paquete del repo (26.2.3) reconoce el a732 por chipid.
(R3/obj-5 "Mesa main ya lo conoce" queda CONFIRMADO, y de hecho lleva desde ≤24.3.)

---

## 4. RIESGO CM3/GMU: mecanismo, condición que evita el cuelgue y mitigación

### La cadena que dispara el CM3 (no hay que hacer nada para provocarlo)

Abrir card0 llama `msm_open` → `load_gpu` → `adreno_load_gpu` → hw_init → **boot del CM3 del GMU**.
Cadena literal en R2 §4.4 (`revision/R2-display-cadena.md:357-371`): `drm_client_setup` (cliente
fbdev, `msm_kms.c:380-387`) → `drm_client_open` → `msm_open` (`msm_drv.c:265-272`, verificado hoy:
`load_gpu(dev)` en `msm_drv.c:198-207`) → `a6xx_gmu_resume` → `a6xx_gmu_fw_start`.
**⇒ "card0 sin CM3" NO existe**: basta que el master bind termine (card0 registrada) y el cliente
fbdev la abre en el mismo initcall (`R2:376-377`). Ni siquiera hace falta modetest.

### El mecanismo del cuelgue (por qué era riesgo abrir card0 "a ciegas")

1. La secuencia CM3 (`a6xx_gmu.c`, pokes del fork): carga de la imagen por bloques a ITCM/DTCM
   (`F2-itcm/F2-dtcm`) → lectura del magic de fin de DTCM (`UKE-CM3DBG: dtcm-magic`, `:308-312`) →
   `CM3_SYSRESET=1` (S1) → `SYSRESET=0` (S3-rst0) → **sondeo `readl_poll_timeout` de
   `REG_A6XX_GMU_CM3_FW_INIT_RESULT`** (`:334-335`).
2. El cuelgue duro medido por el hermano (24-sep, `ramaa/s21/uke-cm3-test.sh:6-12`): **la última
   marca visible es `UKE-POKE: S3-rst0`; el primer `readl` del sondeo de `FW_INIT_RESULT` no
   vuelve (`S4-poll` nunca sale) y la tablet se reinicia**. Es decir: el bus al GMU se wedgea
   (el readl de MMIO no retorna ⇒ ni timeout ⇒ ni oops ⇒ ni pstore; consola y ssh mueren).
3. Causa plausible instrumentada en el fork (`a6xx_gmu.c:308-312`): si la imagen del firmware no
   llegó a la RAM que el CM3 fetcha (vía SMMU SID 5 del kgsl-smmu), el CM3 arranca con contenido
   stale ⇒ wedge. El print `dtcm-magic` distingue "imagen no llegó" (0/basura) de "llegó y el CM3
   no termina".
4. Sin watchdog activo ⇒ el cuelgue exige **reset físico** (`R2:378-380`, `docs/historia/PLAN-PANTALLA.md:47`).

### Condición que evita el cuelgue "falso" (el atasco del helper, distinto del wedge)

- Con el firmware COMPLETO en las 8 rutas (paquete instalado), `fw_load` termina (`F4-verOK`,
  `Loaded GMU firmware v…`, `a6xx_gmu.c:937`) y el risk real queda en el arranque del CM3
  propiamente dicho. Sin las copias legacy, `request_firmware` se queda ~60 s por fichero en el
  helper — atasco ANTES de F1, no cuelgue (`measure-cm3.sh:44-48`).
- **pd-mapper NO interviene en el GPU** (es para fastrpc/ADSP; el zap va por
  `qcom_scm_pas_auth_and_reset`, `adreno_gpu.c:139-141`, con `CONFIG_QCOM_SCM=y`). Lo que sí
  necesita: TZ accesible (SCM), gpucc/gmu clocks y votes del DT — ya en el árbol.
- El firmware correcto **antes de abrir card0** ya está garantizado en la tablet viva (§2.2).

### Mitigación preparada (escalera CM3, sin flashear)

| Artefacto | Qué hace | Estado | Dónde |
|---|---|---|---|
| `measure-cm3.sh` | Procedimiento en caliente: G0 ssh → P1 `dmesg -n 7` → G1 **gate de firmware** (lista `/lib/firmware` legacy+y `qcom/`: si falta legacy, PARAR — atasco de helper ≠ wedge) → G2 localiza el device GPU + runtime_status → P2 **doble captura VIVA antes del trigger** (dmesg -w a fichero + consola ACM, con marcador en `/dev/kmsg` que DEBE verse en el fichero) → P3 trigger T1 (`power/control=on` = resume runtime PM) o T2 (unbind/bind) → veredicto por la última línea | `bash -n` OK, pendiente de tablet | `build/cm3-ladder/measure-cm3.sh` |
| `uke-cm3-ladder.diff` | Escalera L00–L16 sobre `a6xx_gmu.c`: PRE/POST `uke_poke()`+printk en cada acceso, con **canario L14** = un único `readl` de `FW_INIT_RESULT` antes del sondeo; la última línea pinta el acceso exacto. Lógica intacta (3 if/else rellaveados, 0 borrados) | aplica -p1 limpio, **compilado OK** (`apply-and-build.sh`, `CC a6xx_gmu.o`) | `build/cm3-ladder/INFORME-CM3.md` §1 |
| Harness | 3 escenarios probados: hang (última kmsg = `PRE canary`, última marca `L14-pre-canary`), garbage (completa: basura ≠ cuelgue), ok | **ejecutado, 3/3 pasan** | `INFORME-CM3.md` §2 |
| Kernel K ya lleva | Pokes F1–F4 + S1–S4 + `UKE-CM3DBG: dtcm-magic` (granularidad media: distingue fw-no-cargado de CM3-no-arranca; el canario fino requiere el diff) | en `/var/tmp/uke-k9-tree` | `a6xx_gmu.c:308-335,906-935` |

**Qué condición evita el cuelgue, en una frase**: firmware correcto y completo (8 rutas) ANTES de
que card0 se registre — ya instalado en la tablet — más captura viva previa; y si aun así el CM3
wedgea al soltar SYSRESET, es fallo REAL de arranque del CM3 (no de firmware ausente) y la escalera
(lo más fino con `uke-cm3-ladder.diff` aplicado a K12) dirá el acceso exacto.

---

## 5. RUNBOOK POST-CARD0 (ordenado y seguro; editar/gastar solo tras K12 en vuelo)

> Reglas vigentes: gate batería ≥3750 mV (#P29; #P32 arrancó con 4072 mV), doble captura ANTES de
> tocar nada, bind de SMMU siempre desprendido en la tablet (#P12), sync antes de reboot, cuelgue
> ⇒ reset físico (sin watchdog). **El CM3 arranca SOLO al registrarse card0 (cliente fbdev) — no
> existe "mirar card0 sin abrir" más allá de sysfs/ls.**

### (a) Verificar card0/renderD SIN abrir (seguro: sysfs + dmesg, 0 aperturas)

```sh
# consola: dmesg -n 7 YA corriendo + doble captura (ACM + dmesg -w a fichero) ANTES
ls -l /sys/class/drm/ /dev/dri/                 # card0 + renderD128 esperados
cat /sys/kernel/debug/devices_deferred          # vacío para 3d00000/3d6a000
dmesg | grep -Ei "adreno|gmu|Initialized msm"   # "bound 3d00000.qcom,kgsl-3d0" + "Initialized msm 1.13.0 … minor 0"
cat /sys/bus/platform/devices/3d00000.qcom,kgsl-3d0/power/runtime_status   # suspended = el CM3 aún NO ha corrido
```

### (b) KMS "solo display" SIN GPU: NO es posible por card0 — alternativa segura

Cualquier `open()` de card0 (modetest, drm_info, eglinfo, compositor) dispara `msm_open → load_gpu`
(R2 §4.4). Lo único que NO abre card0 es **`/dev/fb0`** (fdev del fbdev: `R2:354-355`):

```sh
ls -l /sys/class/graphics/fb0 /dev/fb0          # fbdev vivo sin abrir card0
cat /sys/class/drm/card0-DSI-1/status /sys/class/drm/card0-DSI-1/modes 2>/dev/null   # sysfs, sin open
# escribir en /dev/fb0 no llama a msm_open (R2:354): prueba de panel por fbcon/imagen, SIN CM3
# NO ejecutar modetest/kmscube "para ver solo KMS": kmscube NO existe en ALARM y modetest ABRIRÍA card0 → CM3.
```

### (c) Abrir render (eglinfo) con captura viva + gates

```sh
# 0) gates
cat /sys/class/power_supply/qcom-battmgr-bat/voltage_now   # ≥ 3750 mV, si no ABORTAR
pgrep -f uke-console-cap || { relanzar captura ACM; }        # doble captura viva
dmesg | tail -1 > /dev/kmsg-marker-check                     # comprobar que el fichero dmesg-w crece
sync
# 1) marca de partida
echo "G1-RENDER-TEST-START $(date -u +%H:%M:%S)" > /dev/kmsg
# 2) apertura única y observada (desprendido para que un ssh muerto no la corte, regla #P12)
nohup sh -c 'dmesg -n 7; eglinfo -B 2>&1 | tee /tmp/g1-eglinfo.txt' >/dev/null 2>&1 &
# 3) vigilar: si muere, ÚLTIMA MARCA = diagnóstico (S3-rst0 sin S4-poll ⇒ wedge CM3 en FW_INIT_RESULT)
```

Esperado si todo va: `Loaded GMU firmware v…` (`a6xx_gmu.c:937`), `UKE-CM3DBG: dtcm-magic=…`,
S1..S4 completos, y eglinfo listando `EGL vendor Mesa: renderer "FD735 …"`.

### (d) Si cuelga (esperable si el CM3 falla — la captura lo documentará)

1. NO insistir, NO pstore-forense (vacío siempre, regla 5): reset físico (power ~10 s).
2. Clasificar por la última línea de la captura:
   - atasco SIN `F1-fwloop` y ~60 s/fichero de silencio ⇒ firmware/helper (no debería: gate G1).
   - `F4-verOK` + `S3-rst0` sin `S4-poll` ⇒ **wedge CM3** (el riesgo documentado).
   - `UKE-CM3DBG: dtcm-magic=0|basura` ⇒ imagen no llegó al CM3 (SMMU SID 5 / transferencia).
3. Repetir con el kernel K12 + `uke-cm3-ladder.diff` (canario L14) y `measure-cm3.sh T1` —
   el canario señala el acceso exacto sin flashear nada más (procedimiento ya probado en frío,
   `INFORME-CM3.md`).

---

## 6. PAQUETES (rootfs sin nada gráfico — verificado hoy)

Estado del rootfs (debugfs sobre `build/rootfs/arch-rootfs.img`): `mesa`, `libdrm`, `mesa-utils`,
`mesa-demos`, `wayland`, `vulkan`: **AUSENTES** (pacman local = 504 entradas, 0 gráficas;
`/usr/lib` sin libdrm/libEGL/libgbm; `/usr/bin` sin eglinfo/kmscube/modetest). Firmware GPU: ausente
en la imagen (§2.3) aunque presente en la tablet viva (§2.2).

```sh
pacman -S --needed mesa mesa-utils libdrm          # mínimos render/diagnóstico (aarch64: mesa 1:26.2.3-1, libdrm 2.4.134-1, mesa-utils 9.0.0-7)
pacman -S --needed mesa-demos                      # demos GL si se quiere (sin kmscube ni eglinfo: los trae mesa-utils)
pacman -U build/pkg/uke-gpu-firmware/uke-gpu-firmware-1-1-any.pkg.tar.zst   # SOLO si se re-flashea el rootfs (en la tablet viva ya está)
# kmscube: NO existe en ALARM ni en Arch repo (verificado archlinuxarm.org/packages?q=kmscube = vacío).
#   Alternativa KMS: modetest (viene en libdrm). No es prioridad: modetest abriría card0 igualmente.
```

Prerrequisitos de proyecto antes de instalar nada grande: **e2fsck** (ESTADO-VIVO paso 3; P7-A) y
revisar espacio — cada instalación desde SSH viva, con `sync` al final (ronda 39 §4).

---

## 7. Resumen de veredictos

| Bloque | Veredicto |
|---|---|
| Kernel: a732 | **SOPORTADO** — catálogo 0x43030b00 ADRENO_7XX_GEN2, funcs a7xx, GMU chipid 0x70b0000, DT correcto (gpu ok + gmu-732.0 + zap firmware-name), config completa, 0 parches necesarios |
| kgsl-smmu | **COMPATIBLE** — bind por `arm,mmu-500`, impl adreno (split pagetables + PRR), dominios explícitos del driver; 22 CBs/24 grupos son cifras de HW que el driver no restringe |
| Firmware | **COMPLETO en tablet viva** (8 rutas, shas verificados); **ausente en arch-rootfs.img** (reinstalar paquete si re-flash); **NO está en upstream linux-firmware** (única fuente: volcado vendor, ya staged) |
| Mesa | **OK** — a732 = FD735 (0x43030B00) en freedreno_devices.py desde ≤24.3.0; ALARM mesa 1:26.2.3-1 lo trae; modetest en libdrm, eglinfo en mesa-utils; kmscube no existe en ALARM |
| Riesgo CM3 | mecanismo = wedge de bus en el primer readl de `FW_INIT_RESULT` tras `S3-rst0` (sin watchdog ⇒ reset físico); el atasco de helper (~60 s/fw) es firma DISTINTA y se detecta con el gate G1; mitigación = firmware completo previo (ya hecho) + doble captura + escalera `measure-cm3.sh`/`uke-cm3-ladder.diff` (canario L14). pd-mapper NO aplica al GPU |
| Falta para render | nada de firmware/driver/mesa; SOLO el camino K12 (iommus del display-controller + pineo-solo-vivo) para que card0 llegue a registrarse con la GPU componente |
