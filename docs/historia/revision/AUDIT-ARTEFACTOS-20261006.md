# AUDIT-ARTEFACTOS 2026-10-06 (#531)

Auditoría de solo lectura de los artefactos preparados para el flash de validación fix529
(boot_a = boot-uke-fix529, dtbo_a = s268, userdata opcional = rootfs v8), previa al flash.
Método: `sha256sum`, `git log/status`, `debugfs` ext4 en modo lectura (sin montar), `dtc`
sobre payloads extraídos con `dtbo-extract.py`. Cero adb, cero fastboot, cero escrituras
en artefactos.

## Tabla de veredictos

| # | ARTEFACTO | sha esperado | sha real | veredicto |
|---|-----------|--------------|----------|-----------|
| 1a | Kernel rama `uke-fixes-20261005` (4 commits) | 603b37730, 5702c18ac, 760160d41, cc3a3dad8 | los 4 presentes, en ese orden, en HEAD | **GO** |
| 1b | `build-uke/arch/arm64/boot/Image` | `e3756f61…` | `e3756f6185dec2a1198abdb795478bf9e447ed24af66bb54441032d5440aa932` (39889408 B) | **GO** |
| 1c | `build-uke/arch/arm64/boot/Image.gz` | `02164183…` | `021641839028ac39d432c200cc3e6b5647775486eb8a2a144a44ad84c292c3a4` (15389639 B) | **GO** |
| 1d | `build-uke/.config` vs snapshot | == `fix528-build-uke.config` (config que compiló el Image) | == `fix529-build-uke.config`; difiere de fix528 en 1 línea (`CONFIG_QCOM_SPMI_ADC5_GEN3`) | **NO-GO PARCIAL** (ver I1) |
| 2 | Rootfs v8 `/var/tmp/rootfs-uke-k521.img` | `bd2b3029…` | `bd2b30294aee99897ca7e86cb4843317cdf545ee08f1694aac1bc3ccf101899c` (4294967296 B) | **GO** |
| 3 | dtbo s268 `build/bootimg/s268-boot-dtbo-validation.img` | `f2dede80…` ≤610304 B | `f2dede80e7452fd084420f841aae5f419e45d8d33a3ce0037e95e36df674c44b` (609343 B) | **GO** |
| 4 | boot fix529 `build/bootimg/boot-uke-fix529.img` | `1f1f8703…` (100663296 B) | `1f1f8703147d99467e4f7d1ee3e657af4512eb7f36c2e2d58bbbd3d8e89c33d6` (100663296 B) | **GO** |
| 5 | `docs/historia/gates-palawan/flash-fix529.sh` | existe, ejecutable, bash -n, shas internos = disco | todo OK; 3 shas internos verificados | **GO** |
| 6a | `SHA-BUENOS.txt` entradas #529/#530 | s268 + boot fix529 + v8 + fw staged | s268 ✓, payload s268 ✓, boot ✓, fw staged ✓, DTB fix529 ✓ — **falta el rootfs v8** | **CON-MATIZ** (ver I3) |
| 6b | Commits omarchy-uke | 751fe39, acd92bc, 8d696f9 | los 3 presentes (+ d43aa66 RUNBOOK #531 en HEAD) | **GO** |
| 6c | Commits ubuntu-permanente | ledger d01d2f1 | HEAD `d01d2f1` = "ledger #530: rootfs v8 + boot/dtbo s268 packaging + cierre Android"; árbol limpio | **GO** |
| 7a | `build/backup-par-bueno/` | e0ee47dc + s262 `6eda5956` + stock | e0ee47dc ✓, vendor_boot-stock `3ee6d4ac` ✓, init_boot-stock `5228e6e2` ✓ — pero contiene **s260 `6fbb5173`**, no s262 | **CON-MATIZ** (ver I4) |
| 7b | `/var/tmp/rootfs-v7-backup-20261006.img` | existe | existe, 4294967296 B, sha `5f9f00fe0704a5742bac9829b19a6107208c44e0b80c9eb47f3c487f1fdea169` | **GO** |
| 7c | `build/android/flash-b/` | f5ea7d90, b3cfc9b7, 27e61d21, 3ee6d4ac | `boot-stock.img`=`f5ea7d90c51695e4…` ✓, `init-boot-b-MAGISK.img`=`b3cfc9b787a9cb65…` ✓, `dtbo-b-stock.img`=`27e61d21fd6a0858…` ✓, `vendor-boot-stock.img`=`3ee6d4ac5fefc6ea…` ✓ | **GO** |
| 7d | ROM factory `/var/tmp/rom/uke_eea_global_images_OS3.0.303.0.WOZEUXM_16.0/images/` | userdata.img | `userdata.img` (757010984 B) + misc/metadata/super/vbmeta/vbmeta_system/vendor_boot/recovery/countrycode | **GO** |

## Detalle por artefacto

### 1. Kernel (`~/gpu-work/palawan-linux`, build `~/gpu-work/build-uke`)

- Rama actual `uke-fixes-20261005`; HEAD = `cc3a3dad8` "DT vadc NTCs (#529)" y debajo
  `760160d41` (pd_mapper #528), `5702c18ac` (DT táctil+BT+wpss+adsp #528), `603b37730`
  (hub 200MHz F2). Los 4 commits declarados están.
- Image `e3756f61…` y Image.gz `02164183…` verificados contra disco. Las copias
  `build/bootimg/Image-fix528-palawan{,.gz}` son byte-idénticas al build.
- **I1 — NO-GO PARCIAL (config).** Cronología reconstruida por mtimes:
  1. `fix528-build-uke.config` guardado 22:22:10 (tiene `# CONFIG_QCOM_SPMI_ADC5_GEN3 is not set`).
  2. vmlinux 22:22:47 → Image 22:22:48 → Image.gz 22:30:55. El Image se compiló bajo la
     config fix528 (ADC5_GEN3 **off**).
  3. 23:25:14 accidente `defconfig` x86_64 (queda en `.config.old`; irrelevante, es config x86).
  4. 23:26:54 `.config` actual = `fix529-build-uke.config` (ADC5_GEN3 **=m**), byte-idénticos
     (`diff` vacío). El delta fix528↔fix529 es EXACTAMENTE 1 línea.
  5. 23:27 `auto.conf` resincronizado; 00:05 recompilados `qcom-spmi-adc5-gen3.ko` y
     `qcom-vadc-common.ko`; 01:46-01:49 horneado del rootfs v8.
  Per el criterio fijado para esta auditoría: la config restaurada difiere de la que compiló
  el Image actual → **el Image habría que recompilarlo** para correspondencia estricta
  config↔binario. Matiz que reduce el riesgo real: el delta es un símbolo tristate de
  **módulo** (`=m` ↔ not set); el contenido de vmlinux/Image no depende de él, de modo que el
  Image `e3756f61` del boot fix529 es funcionalmente válido, y el módulo ADC5 sí está en el
  rootfs v8 (`modules.dep` línea 620-621) y en staging extra/ (sha `7741303f…` = build-uke ✓).
  Decisión del dueño: (a) recompilar Image y repack del boot, o (b) flashear así documentando
  la desviación.
- **I2 — working tree sucio.** 5 ficheros modificados sin commit, todos con mtime 24-28 sep
  (anteriores al build del 5-oct, luego **están dentro del Image compilado**): `runtime.c`
  (+19), `arm-smmu-impl.c` (+2), `arm-smmu.c` (+57), `qcom_battmgr.c` (+96),
  `uke-panic-fb.c` (+72); total +230/−16. Reconstruir desde HEAD solo no reproduciría
  `e3756f61`.

### 2. Rootfs v8 (`/var/tmp/rootfs-uke-k521.img`) — GO

Verificado con `debugfs` (lectura):
- `usr/lib/firmware/qcom/uke/gen71100_zap.mbn` (12088 B) ✓; también copia en `qcom/palawan/`.
- `gen71100_gmu.bin` (80680 B) y `gen71100_sqe.fw` (66036 B) en la **raíz** de firmware ✓
  (además duplicados en `qcom/`).
- `qca6750/wpss.mdt` + b00-b12 + qdb ✓; `adsp.mdt` + adsp.b00-b52 + adsp_dtb en raíz de
  firmware ✓; `qca/msbtfw11.mbn` + msnv11 ✓; `ath11k/WCN6750/hw1.0/board-2.bin` (927980 B) ✓.
- `lib/modules/7.2.0-rc2-palawan+`: **847** entradas en `modules.dep` (esperado ~847+) ✓;
  **no** existe `extra/` ✓ (ni en el dir ni en `modules.dep`).
- `modules.dep` contiene `kernel/drivers/iio/adc/qcom-spmi-adc5.ko` y
  `qcom-spmi-adc5-gen3.ko` ✓; **cero** menciones de `battmgr` ✓.
- `strings kernel/drivers/soc/qcom/qcom_pd_mapper.ko` → contiene `qcom,lamma` ✓.
- `etc/systemd/system/uke-adsp.service` (768 B) ✓ con symlink en
  `multi-user.target.wants/uke-adsp.service` ✓; `usr/local/bin/uke-adsp-load.sh` (7939 B,
  0755) ✓.
- Copias staged coherentes: `staging/usr/lib/modules/.../extra/qcom-spmi-adc5-gen3.ko` =
  `7741303f90364f71614a80503207162f9c6119b36d560fe7c0203bbfffbee4f1` (=
  SHA-BUENOS #529 y = build-uke actual) ✓; `qcom-vadc-common.ko` = `1602f263…` ✓.
- **I5:** el sidecar `build/rootfs/rootfs-uke-k521.img.sha256` (untracked) contiene
  `5f9f00fe…` = sha del **backup v7**, no del v8. Desactualizado; no afecta al flash (el gate
  usa el sha incrustado en flash-fix529.sh).

### 3. dtbo s268 — GO

- sha y tamaño correctos (tabla). Payload extraído: 609279 B @ offset 64,
  `04df0b698232386427fd97bc7affdb39e3c8e32cab4964c4dd5a625cd4bf893d` = el registrado en
  SHA-BUENOS #530 ✓.
- Delta s268 vs s266 payload a payload (dts descompilados, 15394 vs 15384 líneas): **SOLO**
  el fragmento nuevo, exactamente:
  `fragment@2104 → /soc/qcom,qupv3_0_geni_se@ac0000/spi@a90000/touchscreen@0` con
  `touchscreen-size-x = <0x858>` (2136), `touchscreen-size-y = <0xc80>` (3200),
  `interrupts = <0x36 0x02>` (54, falling). Coincide con los gates de
  `repack-s268-report.txt`.
- Herencia s266 intacta en s268: panel o82 (`qcom,mdss_dsi_o82_42_02_0b…`/`o82_36_02_0a…`) ✓,
  ESD (`qcom,esd-check-enabled` ×4, `esd-err-gpios` en fragment@1105, `mi,esd-err-irq-gpio`
  en los paneles o82) ✓, DPU-solo (`iommus = <0x129 0x1c00 0x02>`) ✓, GPU: fragment@1420
  `target-path /soc/qcom,kgsl-3d0@3d00000` con `status = "disabled"` ✓.
- s266 referencia intacta: `s266-boot-dtbo-esd.img` =
  `15fdbbd3d265c393baac69c2e19884fe72417e6c304692db3fafacc8fdc7d695` ✓.
- **I6 (nota, no bloquea):** el dtbo (ya desde s262 y s266, no es regresión de s268) contiene
  DOS fragmentos sobre `kgsl-3d0`: fragment@1420 (`status = "disabled"`) y fragment@1450
  (config completa adreno-43030b00 + opp-table `gpu_opp_uke` con `status = "okay"`, más tarde
  en el blob). En aplicación secuencial de overlay el último gana; el estado GPU efectivo de
  la validación depende de ese orden. Dado que s262 (flasheado y funcionando) y s266 tienen
  la misma dualidad byte a nivel de estructura, se mantiene como estado conocido del proyecto;
  se deja anotado para leer la validación con esa lupa.

### 4. boot fix529 — GO

- sha y tamaño correctos (100663296 B exactos).
- Cabecera `ANDROID!`; kernel_size@8 (LE) = 15389639 = tamaño exacto del Image.gz; payload
  @4096 empieza con magic gzip `1f8b0800` y su sha256 =
  `021641839028ac39d432c200cc3e6b5647775486eb8a2a144a44ad84c292c3a4` = **Image.gz del kernel
  nuevo, byte a byte** ✓.
- cmdline @44 (hasta NUL, 255 B): `mem=2048M rdinit=/ukeinit panic=10
  memmap=0x1A12800$0xE3940000 console=tty0 fbcon=map:0 hung_task_timeout_secs=20
  hung_task_panic=1 watchdog_thresh=10 console=ttyGS0,115200 fw_devlink=permissive
  clk_ignore_unused pd_ignore_unused arm-smmu.disable_bypass=0` = cmdline base del shell,
  **sin tokens añadidos** (es prefijo de las de k51/k49: no lleva los tokens de debug
  `arm_smmu.uke_*`, `video=`, `loglevel=`, segundo `memmap=`, etc.). Resto de los 1536 B
  todo a cero ✓.

### 5. flash-fix529.sh — GO

`docs/historia/gates-palawan/flash-fix529.sh`: existe, `-rwxr-xr-x`, `bash -n` OK. Shas incrustados vs disco:
- `DTBO_SHA f2dede80…` = s268 real ✓
- `ROOTFS_SHA bd2b3029…` = rootfs v8 real ✓
- literal exigido `FIX_BOOT_SHA 1f1f8703…` = boot fix529 real ✓
(Revisión de fondo del guion: la hace otro agente; fuera del alcance de esta auditoría.)

### 6. Registro

- `SHA-BUENOS.txt` (tracked, commit acd92bc): sección #530 con s268 + payload interno + boot
  fix529 ✓; secciones #529 con fw staged (radio/adsp/cdsp/qca/ath11k), DTB fix529
  (`bff462e1…` = disco ✓) y módulos extra/ ✓; líneas 85-86 con Image `e3756f61` y Image.gz
  `02164183` ✓; fix528.dtb `2bdc5066…` = disco ✓. **I3:** NO contiene el sha del rootfs v8
  (`bd2b3029…`). Está registrado en `ubuntu-permanente/docs/FLASH-LEDGER.md` (línea 10135,
  commit d01d2f1) y en el propio flash-fix529.sh, pero falta en SHA-BUENOS.txt donde la sesión
  lo daba por registrado.
- omarchy-uke: `751fe39` (staging fw #529), `acd92bc` (packaging #530), `8d696f9` (ESTADO-VIVO
  #530) presentes; HEAD extra `d43aa66` "RUNBOOK-FLASH-FIX529 #531". Sin ficheros **tracked**
  modificados. 12 **untracked** (ninguno bloquea; los relevantes tienen su sha registrado en
  SHA-BUENOS.txt): `build/android/flash-b/vbmeta-b-dump.img`,
  `build/android/flash-b/vbmeta-system-b-dump.img`, `build/android/uke-snapshot-r15.sh`,
  `build/android/uke-snapshot-r2.sh`, `build/bootimg/Image-fix528-palawan`,
  `build/bootimg/Image-fix528-palawan.gz`, `build/bootimg/mkdtbo-s267.py`,
  `build/bootimg/repack-boot-ukek49-c1-dump-report.txt`,
  `build/bootimg/repack-boot-ukek49-c2-shared1-report.txt`,
  `build/bootimg/xiaomi-uke-fix528.dtb`, `build/bootimg/xiaomi-uke-fix529.dtb`,
  `build/rootfs/rootfs-uke-k521.img.sha256`.
- ubuntu-permanente: HEAD `d01d2f1` = "ledger #530: rootfs v8 + boot/dtbo s268 packaging +
  cierre Android" (NOTA: en el encargo se citaba como "ledger #527 d01d2f1"; d01d2f1 es el
  ledger **#530**; el #527 es `acdc16a`). Árbol limpio, sin nada sucio. Historia: #530
  d01d2f1 ← #529 8ab9365 ← #528 36bfdad ← #527 acdc16a.

### 7. Rollback

- `build/backup-par-bueno/`: `boot-ukek13-dsid.img` = `e0ee47dc4044e9cccbcf177ab36cc8efd005ee9ef4d7cff370741578707c5c57`
  ✓ (par bueno); `vendor_boot-stock.img` = `3ee6d4ac…` ✓; `init_boot-stock.img` = `5228e6e2…`
  ✓; `vendor_boot_b-lee.img` = `init_boot_b-lee.img`… → `vendor_boot_b-lee` = `3ee6d4ac…`
  (idéntico al stock) y `init_boot_b-lee` = `5228e6e2…` (idéntico al stock) ✓.
  **I4:** contiene `s260-boot-dtbo-dpu-iommus.img` = `6fbb5173…`, **no** el s262
  `6eda5956…` citado. El s262 con el sha esperado
  (`6eda59562ae56e750b0eeffdf698adb1ba8229f9489645b8a5c2804bdae4dbcd`) existe pero en
  `build/bootimg/s262-boot-dtbo-gpu-off.img`. El dtbo del par bueno de fecha 30-sep era el
  s260; si el plan de rollback cuenta con flashear el s262 desde bootimg, OK; si se esperaba
  dentro de backup-par-bueno, copiarlo (queda fuera de esta auditoría).
  `historico/` conserva `boot_b-lee.img.PAR-28SEP-s244-bounce-ffff8c51` (base del fix529).
- `/var/tmp/rootfs-v7-backup-20261006.img`: existe, 4 GiB, `5f9f00fe…`.
- `build/android/flash-b/`: los 4 shas declarados correctos (tabla) + 2 dumps de vbmeta sin
  sha esperado (informativos).
- ROM factory completa en `/var/tmp/rom/uke_eea_global_images_OS3.0.303.0.WOZEUXM_16.0/images/`
  con `userdata.img` (757010984 B) para el rollback a Android.

## Resumen de incidencias

| ID | Gravedad | Incidencia |
|----|----------|------------|
| I1 | **NO-GO parcial (kernel)** | `.config` actual = fix529 (`ADC5_GEN3=m`), pero el Image `e3756f61` se compiló con fix528 (`ADC5_GEN3` off). Difiere en 1 símbolo tristate de módulo: el binario del Image no se ve afectado y el `.ko` ADC5 está en rootfs v8 y staging; para correspondencia estricta habría que recompilar el Image (y repack del boot) o aceptar la desviación documentada. |
| I2 | media | 5 ficheros del kernel modificados sin commit (+230/−16; runtime PM, arm-smmu ×2, qcom_battmgr, uke-panic-fb) están dentro del Image compilado (mtimes 24-28 sep): el build no es reproducible desde HEAD. |
| I3 | baja | `SHA-BUENOS.txt` no tiene la entrada del rootfs v8 (`bd2b3029…`); sí está en FLASH-LEDGER.md (#530, d01d2f1) y en flash-fix529.sh. |
| I4 | baja | `backup-par-bueno/` contiene s260 (`6fbb5173…`), no el s262 (`6eda5956…`) declarado; el s262 correcto está en `build/bootimg/`. |
| I5 | baja | Sidecar `build/rootfs/rootfs-uke-k521.img.sha256` desactualizado (contiene el sha del backup v7). |
| I6 | nota | Dualidad fragment@1420 (GPU disabled) + fragment@1450 (GPU okay) sobre kgsl-3d0, heredada de s262/s266 sin cambios: el estado GPU efectivo depende del orden de aplicación de overlays. No es regresión de s268. |

## Veredicto global

- **GO** para: rootfs v8, dtbo s268, boot fix529, flash-fix529.sh, commits/registro de ambos
  repos (con matiz I3), y todos los backups de rollback (con matiz I4 de ubicación del s262).
- **NO-GO parcial** para el kernel por I1 (drift de 1 símbolo de config entre la config que
  compiló el Image y la actual) + I2 (fuente del build sin commit). Los binarios Image.gz
  embebidos en boot fix529 son los registrados; la decisión de recompilar o flashear con la
  desviación documentada es del dueño.
