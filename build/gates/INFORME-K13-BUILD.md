# INFORME-K13-BUILD — boot-ukek13.img (kernel K12 + FIX del GRUPO IOMMU del display + migas UKE-K13)

Fecha: 30-sep-2026 tarde. Autor: agente constructor K13. **Trabajo sin tablet** (prohibido fastboot/adb/ssh/ttyACM0).
Encargo: K12+dtbo s260 lograron arming + bind SMMU + re-probe del dpu, y `dpu_kms_mmu_init failed: -22` PERSISTE
(antes, sin iommus, era -19). El encargo daba un mecanismo hipotético (fmt/PTFS del IDR2) y mandaba **verificarlo
leyendo el código, no darlo por hecho**, y si resultaba otro, documentar y aplicar el fix que toque. Resultado:
**la hipótesis fmt/PTFS queda REFUTADA con los registros reales; el -22 real es del núcleo IOMMU: el display
comparte GRUPO con el mdss padre y `iommu_attach_device()` exige grupos de 1 dispositivo**. K13 aplica el fix
(fallback `iommu_attach_group`) y siembra migas UKE-K13 en toda la cadena para que la consola del próximo boot
localice cualquier -22 residual rama por rama.

Arena: `/var/tmp/uke-k13/` (scripts, logs, copia del .img). Árboles: **renombrados con symlinks de
compatibilidad** (decisión por tiempo, documentada en §3): `/var/tmp/uke-k12-tree` y `/var/tmp/uke-k12-build`
son ahora symlinks → `/var/tmp/uke-k13-tree` y `/var/tmp/uke-k13-build` (el estado K12 de los 3 ficheros tocados
queda reconstruible con `patch -R < build/gates/patches/k13-grupo-iommu.diff`, validado). MAKE=/usr/bin/make.
Ningún `git commit`. ~/gpu-work y el resto de ~: solo lectura.

---

## 0. Entregables y shas

| fichero | bytes | sha256 |
|---|---|---|
| **`build/bootimg/boot-ukek13.img`** (imagen final, 96 MiB) | 100663296 | **`d71ea2b5f6aaf7f8b4820748362b5b32ebed4a064f6f224bb037a7abc9707381`** |
| kernel dentro de la imagen = Image.gz del build K13 | 16577409 (gz, **+672 vs K12**) / 41355776 (crudo, mismo tamaño que K9/K11/K12) | `d8ba80e53f4c162ae2f3c5ff822c85576a5b0f4432bb1524b6b03c3aba6470ad` / crudo `aade1ecedb32a01dc83fe0acf932c27b64c232279b6641cbd8e9f66832366f3c` |
| cmdline de la imagen | **356 B** | — (copiada BYTE A BYTE de boot-ukek12.img offset 44; 0 bytes difieren de K12) |
| initramfs embebido `/var/tmp/uke-k12/uke-k12-initramfs.cpio.gz` | 1013258 | `cb10ff4096a9e4608da6c61eeafc79eae0f18291b6ada49ece4ea165f1d4169c` (== cpio K12: arming intacto, blob @35336040 byte a byte) |
| diff del kernel | 174 líneas / 3 ficheros | `build/gates/patches/k13-grupo-iommu.diff` — `facaeda22243aa770031394aea514d3d02c3a5c1c6e9c615a9242458616f5a33` |
| repack | — | `/var/tmp/uke-k13/repack-k13.py`; log `build/bootimg/repack-k13-report.txt` |
| build | — | log `/var/tmp/uke-k13/build.log` (`fbef4a30…`), rc=0 |
| bases de referencia | — | shell s240 `e3c60969…`; boot-ukek12.img `7c6bfe0d…`; dtbo s260 `6fbb5173…` (SIN cambios en K13) |
| rollback | — | boot: `build/backup-par-bueno/boot_b-lee.img` (`ffff8c51…`); dtbo: s258 (`f4663ff8…`) — K13 solo cambia boot_b |

## 1. El mecanismo del -22, verificado (file:line sobre el árbol K12 = K13 sin el parche)

### 1.1 REFUTADA la hipótesis del encargo (fmt/PTFS/ARMV7S)

La cadena propuesta era: IDR2 sin bits PTFS → `cfg->fmt` NONE/AARCH32_L → `alloc_io_pgtable_ops` NULL → -EINVAL.
Verificación, punto por punto:

- **El IDR2 real del apps-smmu ES 0x00005111**: `build/gates/k10-bind-exitoso-dmesg.log` línea con t=435,38 s
  (`UKE-POKE: cfg_probe ID2=0x00005111`, probe armado del apps-smmu — el mismo camino que K11/K12). El kgsl lee
  `0x00005511` (t=0,32 s).
- **0x5111 SÍ lleva bits PTFS**: `arm-smmu.h:67-69` — `PTFS_64K`=bit14, `PTFS_16K`=bit13, `PTFS_4K`=bit12.
  0x5111 = bit14 SET + bit12 SET (16K no).
- **Por tanto `cfg_probe` sí pone los FEAT_AARCH64**: `arm-smmu.c:3405-3410` (`if (id & ARM_SMMU_ID2_PTFS_4K)
  … FEAT_FMT_AARCH64_4K`, ídem 64K). La pgsize impresa lo confirma por doble cuenta: `0x61311000` = 4K+64K+1M+
  16M+2M+512M+1G, y los 512M SOLO salen de `FMT_AARCH64_64K` (`arm-smmu.c:3427-3428`).
- **`cfg->fmt` queda AARCH64, no NONE ni AARCH32_L**: `arm-smmu.c:1702-1706` — con `CONFIG_64BIT=y` y cualquier
  FEAT_FMT_AARCH64_* el fmt se fuerza AARCH64 (aunque el AARCH32_L se hubiera puesto antes en :1695).
- **El formato elegido es `ARM_64_LPAE_S1`** (`arm-smmu.c:1719-1720`, ias=36 oas=36) y
  **`CONFIG_IOMMU_IO_PGTABLE_LPAE=y`** (`/var/tmp/uke-k12-build/.config:7162`). `alloc_io_pgtable_ops` no puede
  dar NULL, y aunque lo diera su error es **-ENOMEM, no -EINVAL** (`arm-smmu.c:1797-1800`).
- **ARMV7S era una falsa pista doble**: en el .config está `CONFIG_IOMMU_IO_PGTABLE_ARMV7S=y` (:7163) — no está
  OFF — y además la rama AARCH32_S es **inalcanzable en arm64** (`arm-smmu.c:1697-1698` exige
  `!IS_ENABLED(CONFIG_64BIT)`).
- **Prueba empírica K10**: el attach de `17110040.qcom,wcn6750` (WLAN, master NORMAL — no pineado) completó
  `arm_smmu_init_domain_context` ENTERO en el apps-smmu con handoff activo: `CB 69 reservado DESDE ARRIBA`
  (log K10, 435,387 s) → `write_context_bank idx=69 cfg=asignado` → `install_s2cr idx=17 type=0 cbndx=69`,
  **sin ningún error**. El `impl->init_context` qcom (`qcom_smmu_init_context`, `arm-smmu-qcom.c:433-450`)
  devuelve 0 siempre. La rama fmt y el alloc de pgtable están descartados también experimentalmente.

### 1.2 EL MECANISMO REAL: grupo IOMMU compartido → `iommu_attach_device` -EINVAL

Cadena completa (todo verificado en código y DTB):

1. **El DT fusionado lleva la MISMA banda en DOS dispositivos vivos**: `s260-merged.dtb` (fdtget):
   `/soc/display-subsystem@ae00000` (mdss padre) `iommus = <297 7168 2>` — puesta por el s231 — Y
   `/soc/display-subsystem@ae00000/display-controller@ae01000` (el dpu) `iommus = <297 7168 2>` — la añade el
   s260 (fragment@1709). `<297 7168 2>` = `<&apps_smmu 0x1c00 0x2>`; 7168 = 0x1c00.
2. **`find_sme` REUTILIZA el SME**: `arm-smmu.c:2107-2109` — un SMR ya válido con `(mask & smrs[i].mask)==mask`
   e ids compatibles devuelve el MISMO índice. El primero de los dos que probea (el mdss padre) reclama el SME
   de la banda; el segundo (el dpu) lo REUTILIZA (count++).
3. **`arm_smmu_device_group` los funde en UN grupo**: `arm-smmu.c:2884-2886` — si el SME ya tiene grupo,
   devuelve `iommu_group_ref_get(group)` en vez de crear uno nuevo. Grupo del display = {mdss, dpu}, 2 dispositivos.
4. **El core rechaza el attach**: `iommu.c:2205-2207` dentro de `iommu_attach_device()` (iommu.c:2191):
   ```c
   ret = -EINVAL;
   if (list_count_nodes(&group->devices) != 1)
       goto out_unlock;
   ```
   — se ejecuta ANTES de llamar a `ops->attach_dev` (`arm_smmu_attach_dev`). Esto explica EXACTAMENTE la
   observación del orquestador: **cero migas "CB reservado" en el boot K12** (nunca se llega al
   `init_domain_context`) y el error sale como `-EINVAL` = **-22**.
5. **La cadena msm encaja**: `dpu_kms.c:1181` `_dpu_kms_mmu_init` → `msm_kms.c:180` `msm_kms_init_vm`
   (con s260, `device_iommu_mapped(mdp_dev)` = verdad → iommu_dev = mdp_dev) → `msm_iommu.c:726`
   `msm_iommu_new` → `iommu_paging_domain_alloc` (bien, dominio fresco) → `iommu_attach_device`
   (`msm_iommu.c:752`) → **-EINVAL** → `ERR_PTR(-22)` → `[dpu error] dpu_kms_mmu_init failed: -22`
   (`dpu_kms.c:1183`). Ni `msm_gem_vm_create` (solo -ENOMEM) ni `domain_alloc_paging` (no puede -EINVAL).
6. **El fix que toca existe en el core**: `iommu_attach_group()` (`iommu.c:2384`) hace el MISMO attach sin el
   check de count (solo rechaza con -EBUSY si el grupo ya lleva un dominio no-default; aquí lleva el default
   IDENTITY, así que pasa).

Nota honesta K11: con s258 (iommus SOLO en el padre) el grupo del display sería de 1 y este mecanismo no explica
por sí solo el -22 de K11; no hay captura de consola K11 en este PC para re-derivarlo. K13 resuelve el mecanismo
verificado del mundo s260 (el que está en el DTB del aparato HOY) y deja migas en TODAS las ramas de error de la
cadena (§2), de modo que si un segundo mecanismo sigue vivo, la consola lo nombrará (la escalera §5).

## 2. El parche (`build/gates/patches/k13-grupo-iommu.diff`, 3 ficheros)

1. **`drivers/gpu/drm/msm/msm_iommu.c` — EL FIX**: en `msm_iommu_new()`, si `iommu_attach_device` devuelve
   -EINVAL y el grupo tiene >1 dispositivo (contado con `iommu_group_for_each_dev`, porque `struct iommu_group`
   es opaca en msm), se hace **fallback a `iommu_attach_group(iommu->domain, group)`**: el grupo entero
   {mdss, dpu} pasa al dominio del KMS — semántica correcta, la banda 0x1c00 es UNA sola traducción física
   compartida. Migas: `UKE-K13: msm_iommu_new: iommu_attach_device rc=%d`, `UKE-K13: msm_iommu_new: grupo con
   %u dispositivos … -> iommu_attach_group`, `UKE-K13: msm_iommu_new: iommu_attach_group rc=%d`. Los grupos de
   UN dispositivo (todos los demás masters y targets) **no entran al fallback**: su camino es idéntico a K12.
   El `iommu_detach_device` de teardown queda como estaba (WARN pre-existente del doble-fini; el sistema ya lo
   sobrevivía).
2. **`drivers/gpu/drm/msm/msm_kms.c` — migas**: `UKE-K13: msm_kms_init_vm: iommu_dev=%s (mdp=%s mdss=%s)` (lo
   que pedía la fila 2 del informe K12: qué dispositivo se elige) y `UKE-K13: msm_kms_init_vm:
   msm_iommu_disp_new(%s) rc=%pe` (errno intermedio).
3. **`drivers/iommu/arm/arm-smmu/arm-smmu.c` — migas en `arm_smmu_init_domain_context`**: la miga pedida tras la
   selección de fmt (`UKE-K13: init_domain_context(%s): fmt=%d features_fmt=0x%lx ias=%lu oas=%lu stage=%d`,
   solo apps-smmu; fmt 0=NONE 1=AARCH64 2=AARCH32_L 3=AARCH32_S) **y una miga en CADA ret de error**: fmt==NONE,
   stage default, `alloc_context_bank` rc, `impl->init_context` rc, `alloc_io_pgtable_ops` NULL. Total 6 migas.
   **Boot esperado de la miga principal**: `fmt=1 features_fmt=0x180 ias=36 oas=36 stage=1` (AARCH64, 4K+64K,
   ARM_64_LPAE_S1) — la verificación del §1.1 hecha consola.

**Lo que NO se aplicó y por qué**: el fix propuesto en el encargo (forzar `ARM_SMMU_FEAT_FMT_AARCH64_4K` en
cfg_probe para el apps-smmu) es un **no-op demostrado**: el FEAT ya se pone del IDR2=0x5111 (`arm-smmu.c:3405`)
y el fmt ya es AARCH64 (§1.1). Forzarlo no cambiaría un bit del comportamiento; en su lugar va la instrumentación
de la miga fmt (que deja la verificación visible en consola) y el fix real del §2.1.

Marcadores verificados en el binario: `UKE-POKE`=113 (intacto), `UKE-K12`=1 (intacto), `UKE-K13`=**11**
(6 arm-smmu + 3 msm_iommu + 2 msm_kms), `PINADO sin estar vivo`=0, params `uke_smmu_probe/uke_write_mask/
uke_handoff/uke_keep_boot` presentes, blob initramfs @35336040 == cpio K12 byte a byte.

## 3. Arena y build (decisión por tiempo, documentada)

- **Renombrado + symlinks** (en vez de `rsync`+`cp -a`, ~7 GB): `mv /var/tmp/uke-k12-tree → /var/tmp/uke-k13-tree`
  y `mv /var/tmp/uke-k12-build → /var/tmp/uke-k13-build`, con symlinks de compatibilidad
  `/var/tmp/uke-k12-tree → /var/tmp/uke-k13-tree` y `/var/tmp/uke-k12-build → /var/tmp/uke-k13-build`. Los `.cmd`
  del build (caliente, K12) referencian rutas absolutas `uke-k12-tree` que ahora resuelven al MISMO contenido
  (mtimes preservados por el rename) ⇒ **recompilación incremental**: solo los 3 ficheros parcheados + relink
  de vmlinux + Image.gz. Minutos en vez de las ~3600 objetos de K12. `source` symlink del build apunta a
  `uke-k12-tree` → resuelve al árbol K13. El estado K12 de los 3 ficheros queda reproducible con
  `patch -R -p1 < build/gates/patches/k13-grupo-iommu.diff` (validado con `--dry-run`).
- Compile: `make -C /var/tmp/uke-k13-tree O=/var/tmp/uke-k13-build ARCH=arm64 LLVM=1 MAKE=/usr/bin/make -j16
  Image.gz` → **rc=0**, cero warnings nuevos (dos corridas intermedias corrigieron: format u32→cast unsigned
  long en las migas features; `struct iommu_group` opaca → contador por `iommu_group_for_each_dev`; return
  ERR_CAST en msm_kms). Log `/var/tmp/uke-k13/build.log`.

## 4. Gates del repack boot-ukek13.img (todos VERDES — `build/bootimg/repack-k13-report.txt`)

G0 entradas (s240 `e3c60969…` / K12 `7c6bfe0d…` / Image.gz `d8ba80e5…` / cpio `cb10ff40…` con sha).
G1 cabecera v4 (1584, ramdisk 0, gzip @4096). G2 cmdline 356 B == K12 byte a byte (0 B difieren), 255 base
s240 + 4 tokens `uke_`, sin probe, sin dobles espacios. G3 kernel: 16577409 B (+672), crudo 41355776,
UKE-POKE=113, UKE-K12=1, **UKE-K13=11** con las tres migas clave presentes exactamente una vez,
"PINADO sin estar vivo"=0, params uke_*, blob embebido @35336040 == cpio K12, /ukeinit con 6 migas UKE-K11 y
arming antes de switch_root. G4 ensamblado (kernel_size@8=16577409, hueco a ceros en base e imagen). G5
forma/AVB (AVB0@35438592, AVBf@100663232). G6 deltas: vs s240 confinado a kernel_size@8 + cmdline + kernel;
**vs K12: cmdline IDENTICA (0 B) + kernel recompilado (+672 de cola nueva con datos del kernel)**. G7
publicación + relectura. G8 `unpack_bootimg` rc=0 (kernel extraído == Image.gz K13) y `avbtool info_image`
(Footer 1.0, VBMeta offset 35454976 / size 1728 == K12/K11).

## 5. Escalera de disparo (#P34/K13 propuesta — ANTES de flashear)

Canal: **SOLO `fastboot flash boot_b build/bootimg/boot-ukek13.img`** (el dtbo s260 `6fbb5173…` queda como está;
K13 no toca dtbo). Gate previo: batería ≥ 3 700 000 µV por getvar, un solo lector ttyACM, watcher USB, portátil
enchufado. Rollback: boot_b-lee `ffff8c51…` + baile de slots (y dtbo s258 `f4663ff8…` si hiciera falta el dtbo).
NUNCA `unbind` del apps-smmu.

Consola esperada, línea a línea (t = K11/K12 real):

| t | línea esperada |
|---|---|
| 0,44 s | `UKE-POKE: apps-smmu @…: primer probe DIFFERIDO…` (desarmado) |
| 3,57 s | `S118 ACMOK: /dev/ttyGS0 presente t=3` |
| ~4,0 s | `UKE-K11: armando probe a Ns` → `armado rc=0` → REINTENTO → ID0/1/2 → `cfg_probe ID2=0x00005111` → `handoff: PREPARAR` → barrido → `PIN SMR(0) id=0x60 …` → `FIN barrido: PINADOS=1` (o 5 si el BL dejó más SMR vivos, como en el bind K10) |
| ~4,1 s | re-probe del display: `find_sme(dev=…display-subsystem sid=0x1c00 mask=0x2) -> N` (padre, reclama) y `find_sme(dev=…display-controller …) -> N` (dpu, REUTILIZA el mismo idx) + `UKE-K12: handoff no-vivo sid=0x1c00 -> attach normal` |
| **~4,1 s** | `UKE-K13: msm_kms_init_vm: iommu_dev=ae01000.display-controller (mdp=mapeado mdss=mapeado)` ← NUEVA |
| **~4,1 s** | `UKE-K13: msm_iommu_new: iommu_attach_device rc=-22` → `UKE-K13: msm_iommu_new: grupo con 2 dispositivos … -> iommu_attach_group` ← NUEVA (el mecanismo K13 cazado en consola) |
| **~4,1 s** | `UKE-K13: init_domain_context(ae00000.display-subsystem): fmt=1 features_fmt=0x180 ias=36 oas=36 stage=1` ← NUEVA (la verificación §1.1 en vivo) → `handoff: CB 69 reservado DESDE ARRIBA` → `wmask[ctxbank]: SILENCIADA … idx=69` → `UKE-K13: msm_iommu_new: iommu_attach_group rc=0` |
| **~4,1 s** | `dpu hardware revision:0xa0010000` y **SIN** `dpu_kms_mmu_init failed` → `msm_dpu: bound ae94000.dsi / ae96000.dsi / 3d00000.qcom,kgsl-3d0` → `[drm] Initialized msm …` → **card0** |
| 13,8 s | UFS: attach de sid 0x60 → `idx=0 PINADO (vivo del BL)` (intocado, como siempre) |
| 40-90 s | switch_root → SSH → fbcon/modetest en pantalla |

Tabla desenlace → lectura (la miga que decide):

| desenlace | lectura | siguiente jugada |
|---|---|---|
| **VIVE con `Initialized msm` + card0 + fbcon** | el grupo compartido ERA el -22; receta cerrada | modetest/FOTO. Si scanout con faults esporádicos → cmdline con ` arm_smmu.uke_write_mask=0x1c0` (bit6/7/8) para escribir el mapeo en HW |
| **card0 SIN imagen / CFE de sid 0x1c00** | el fallback dejó el mapeo en RAM (`uke_write_mask=0`, §K12 nota honesta) | la jugada ya prevista: cmdline K14 con `uke_write_mask=0x1c0` (kernel K13 se queda; el barrido protege los vivos) |
| **-22 PERSISTE pero CON `UKE-K13: msm_iommu_new: iommu_attach_device rc=-22` y SIN la miga de grupo** | el grupo era de 1: hay OTRO -EINVAL en el attach | leer la miga `UKE-K13: init_domain_context` (¿apareció? ¿fmt correcto?) y las de error de init_domain_context → rama exacta |
| **-22 PERSISTE y NO aparece `UKE-K13: msm_kms_init_vm`** | el -22 nace ANTES de msm_kms_init_vm (fuera de la cadena que K13 instrumenta) | K14: migas aguas arriba de dpu_kms_hw_init |
| **MUERE / wedge** | causa fuera del SMMU/display (nunca visto en la serie) | rollback boot_b-lee; última miga visible = punto de muerte |

## 6. Fila de pre-registro propuesta (#P34/K13) — ANTES de flashear

> **#P34 — K13 (fix grupo-iommu del display + migas UKE-K13)** · artefacto `boot-ukek13.img` sha256
> `d71ea2b5f6aaf7f8b4820748362b5b32ebed4a064f6f224bb037a7abc9707381` (100663296 B; kernel_size@8=16577409;
> cmdline 356 B == K12 byte a byte; initramfs K12 intacto; dtbo SIN cambios: sigue s260 `6fbb5173…`) · kernel
> `d8ba80e5…` = K12 + `build/gates/patches/k13-grupo-iommu.diff` (msm_iommu.c: fallback `iommu_attach_group`
> cuando el grupo tiene >1 dispositivo — mdss s231 y dpu s260 comparten `<0x1c00 0x2>` → find_sme reutiliza el
> SME → mismo grupo → `iommu_attach_device` -EINVAL/-22 ANTES de attach_dev; + migas UKE-K13 en msm_iommu,
> msm_kms_init_vm y arm_smmu_init_domain_context con su miga fmt) · mecanismo refutado: fmt/PTFS (IDR2 apps =
> 0x5111, PTFS_4K+64K presentes, fmt=AARCH64/ARM_64_LPAE_S1, LPAE=y) · **canal**: solo `fastboot flash boot_b`
> · **gate previo**: batería ≥ 3 700 000 µV, watcher USB, rescate armado · **predicciones**: §5 · **rollback**:
> boot_b-lee (`ffff8c51…`) + baile de slots · **recordatorio**: NUNCA `unbind` del apps-smmu; capturar consola
> completa — la escalera se lee en las migas UKE-K13, no en un solo resultado.

Riesgos residuales declarados: (1) binario no byte a byte K12 (relink/utsversion + parche, como siempre desde
K10); (2) con `uke_write_mask=0` el mapeo del display sigue quedando en RAM (fila 2 de la tabla): K13 quita el
bloqueo del core pero NO garantiza traducción HW — por eso la jugada `uke_write_mask=0x1c0` sigue viva;
(3) el attach por GRUPO cambia también el dominio del mdss padre (identity → KMS): el mdss no hace DMA por
cuenta propia (solo registros/clocks) y el core restaura el dominio core en el teardown de los dispositivos,
pero es un cambio de semántica consciente, documentado en el propio parche; (4) el -22 de K11 con s258 (grupo
de 1) no queda re-derivado desde este PC (sin consola K11): si K13 revela un segundo mecanismo, las migas §2 lo
nombrarán.
