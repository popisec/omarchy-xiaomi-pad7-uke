# SENEMOS-PRUEBA-PREP — una prueba del kernel MCC45TR (display nativo O82) en nuestra uke

> 17-oct-2026, noche. **Preparación solo en el PC**: sin adb/fastboot/ssh, sin flash, sin ledger, sin commit.
> Repo externo `/tmp/claude-1000/ext-senemos` (github.com/MCC45TR/senemos-uke-kernel-mainline, HEAD `43e4036`
> "native54", clon *shallow*, MIT). El dueño autoriza probarlo. Se trató como **código no confiable**: se leyó todo
> lo que se usa (scripts de preparación, `uke-abl.c`, `uke-abl-native.h`, parches de arranque/display, overlays,
> spec, `native.config`) y **no se ejecutó nada suyo** (ni `senemos.sh`, ni Makefiles, ni tests, ni sus
> preparadores): cada paso se **reprodujo a mano** con `tar`/`git apply`/`install`/`cpp`/`dtc`/`od`.
> Complementa `docs/historia/revision/ADOPCION-SENEMOS-20261017.md` (análisis) y responde a sus puntos (2)–(5).

## 0. Resumen

| Paso | Estado | Artefacto |
|---|---|---|
| Fuente Linux 7.2.9 | sha256 `b4c5dfbe…d8ba` = `manifests/linux-7.2.9.json`; firma GPG **VALIDSIG 647F2865…693E** (Greg K-H) | `build/kernel-pokes/senemos-7.2.9/dl/` |
| Árbol .4054 (native54) | **78/78 parches limpios** (44 base + boot/0001 + 33 display) | `reproducir-arbol.sh`, `reproducir.log` |
| Config | su `native.config` + delta de 57 símbolos (~30 elegidos; el resto por `select`/dependencia/visibilidad) (§3) | `senemos-build/config-senemos-ouke1`, `config-delta-vs-su-native.diff` |
| Parche propio | rechazo del DT → **panic diferido** (reinicia con `panic=10`) en vez de `while(true)` mudo | `build/gates/patches/senemos-uke-abl-panic-en-vez-de-cuelgue.diff` |
| Build | clang/LLD 23.1.1, `LLVM=1 ARCH=arm64`, desprendido | `build/logs/build-senemos.log` → §5 |
| boot.img | `build/bootimg/boot-uke-senemos-7.2.9.img` | sha256 **`4894a841de1d1dd23f00a865e6b13169b11d498502948aeddf8295984d911eca`** (§6) |
| dtbo | **STOCK obligatorio** (`dtbo_b.img` del backup, partición `27e61d21…`); s288 → RECHAZO | §7 |
| Flash | `build/gates/flash-senemos-gated.sh` (**NO ejecutado**) | §9 |

## 1. Qué build se reproduce y por qué

- Su HEAD empaqueta **un solo perfil**: `packaging/senemos-uke-linux-kernel-mainline.spec` (7.2.9-1.4054.3) =
  44 parches de `patches/7.2.9/series` → `packaging/native/prepare.sh`, que llama a `src/boot/prepare-abl-source.sh`,
  `src/display/prepare-source.sh`, `src/display/prepare-native-abl-source.sh … 42` y al final **sustituye** el overlay
  de 60 Hz por `sm7675-uke-native-display-oem-modes.dtso` (7 modos OEM, 120 Hz preferido). Config = `packaging/native/native.config`
  (config completa, no la mezcla de fragmentos: se comprobó que `arm64-qcom`/`uke`/`fedora.config` ya están dentro salvo 5
  líneas «is not set» de símbolos inexistentes).
- **native50 / .4050** (el primer KDE nativo, con 0032, perfil `initial120`) **no es reproducible exactamente desde
  HEAD**: el clon es *shallow* (1 commit), `prepare-source.sh` aplica 0033/0034 sin opción y los 9 fuentes de
  `src/display/` (panel, `o82-data.h`, `o82-mode.h`…) ya son los de native54. Su README (17-oct) dice que **.4054 muestra
  KDE a 30/48/50/60/90/120/144 Hz** con 9 transiciones medidas: es el sucesor validado de .4050, y es lo que su spec
  construye. Se reproduce **.4054 (native54)**. Sin red salvo kernel.org, no se pudo traer la historia.
- `0017-uke-bonded-video-split-flush` queda **fuera**, como en su preparador (README: «retained for attribution and
  excluded from the active preparation queue»).

## 2. Reconstrucción (`build/kernel-pokes/senemos-7.2.9/reproducir-arbol.sh`, log `reproducir.log`)

Orden exacto (cada `git apply --check` + `git apply`, raíz con `git init` propio como hace su spec):
1. **Base 44** `patches/7.2.9/0001…0044` (sha de los 44 + 3 fragmentos == `source-lock`; serie == manifiesto).
2. **`prepare-abl-source`**: `patches/boot/0001-arm64-uke-abl-dt-hook.patch` con
   `--exclude=drivers/regulator/qcom-rpmh-regulator-uke.c --exclude=drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c`
   (solo Kconfig `QCOM_UKE_ABL_DT`, Makefile, `setup.c`, `lib/Makefile`); `install uke-abl.c`; `fdt_check.c` (sha ==
   `vendor/source.json`, DTC 1.7.2-g53373d13 comprobado); wrappers `lib/fdt_overlay.c`/`lib/fdt_check.c`;
   `cpp+dtc -@` de `sm7675-uke-ufs.dtso` (`ufs.dtbo` `c24953ea…`) y `sm7675-uke-usb2.dtso` (`usb.dtbo` `082dd8c5…`)
   → `arch/arm64/kernel/uke-abl-overlays.h` (arrays `__initdata`).
3. **`prepare-source` (display)**: `display/7.2.10/0001-native-display-providers` (pese al directorio, su preparador lo
   usa para 7.2.9 y 7.2.10), 0003, 0004, 0006, 0007…0016, 0018…0034; después `install` de los 9 fuentes de `src/display/` sobre los
   que crea 7.2.10/0001 (`dpu_10_1_sm7675.h`, `panel-xiaomi-o82.c`, `o82-data.h`, `uke-dispcc-votes.c`,
   `cliffs-display-icc.h`, `uke-display-smmu.c`, `uke-mdss-handoff.c`, `qcom-uke-display.h`, `uke-o82-mode.h`).
4. **`prepare-native-abl-source 42`**: `install uke-abl-native.h`; 0002 (entrada nativa en `uke-abl.c`) y 0005.
5. **`prepare.sh`**: `display.dtbo` (oem-modes, `e3a3b627…`) + selector
   `msm_drm.dsi_display0=qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid:` → `arch/arm64/kernel/uke-native-display.h`;
   comprobado `xiaomi,oem-refresh-modes;` en el dtbo.

Resultado: **78 parches, todos limpios, sin avisos**. `olddefconfig` sobre su `native.config` reproduce su config
(solo difieren los 3 símbolos de initramfs ocultos con fuente vacía y `OPENSSL_SUPPORTS_ML_DSA`, capacidad del host).
Revisión de seguridad del build: los parches solo tocan `drivers/`, `include/`, DTS, bindings y `arch/arm64/kernel`,
`lib/Makefile`; las líneas añadidas a Makefiles son `obj-$(CONFIG_…) +=` normales (ningún `$(shell …)` ni script de host).

## 3. Config: su `native.config` + deltas (`deltas-omarchy.sh`; diff completo en `senemos-build/config-delta-vs-su-native.diff`)

Su sistema arranca con initramfs dracut/systemd que carga módulos; el nuestro (k34-fw, busybox, sin kmod) **no carga
ninguno**, y sus módulos no se instalan en nuestro rootfs (`/lib/modules/7.2.0-rc2-palawan`). Criterio: `=y` solo para
lo que el arranque hasta SSH y el display necesitan; el resto **como en su config**. Para no adivinar se listaron los
`compatible` de los nodos **habilitados del DT final** (salida del transform sobre el DT vivo, §7) y se mapearon a su
símbolo Kconfig (`dt/enabled-compats.py`, `dt/map-compats.py` → `dt/compat-map.tsv`): 31 drivers enlazados al DT eran `=m`.

| Cambio | Por qué |
|---|---|
| `CMDLINE_FORCE` **n**, `CMDLINE_FROM_BOOTLOADER` **y**, `CMDLINE="rdinit=/ukeinit panic=10 clk_ignore_unused pd_ignore_unused regulator_ignore_unused"` (solo respaldo) | su cmdline forzada (`rdinit=/usr/lib/systemd/systemd root=PARTLABEL=linux …`) ignora la del boot.img; manda la nuestra (§6). Cae `INITRAMFS_FORCE` (depende de FORCE): el ABL vuelve a pasar el ramdisk de vendor_boot encima, **igual que hoy con palawan** |
| `INITRAMFS_SOURCE=…/uke-k34-fw-k52b2-initramfs.cpio.gz` (`ebc2de46…`), gzip | el initramfs de nuestro esquema, embebido como en L76R |
| `SCSI_UFS_QCOM`, `PHY_QCOM_QMP`, `PHY_QCOM_QMP_UFS` (+`QCOM_INLINE_CRYPTO_ENGINE` por select) | raíz en UFS (`ufshc` + `sm7675-qmp-ufs-phy`); el resto de la pila UFS/SD/ext4/GPT ya era `=y` |
| `USB_DWC3`, `USB_DWC3_QCOM`, `USB_PHY_QCOM_UKE` (eUSB2), `USB_REPEATER_QCOM_UKE` | `/sys/class/udc` para el gadget (su overlay USB fija `dr_mode="peripheral"`, high-speed) |
| `USB_LIBCOMPOSITE`, `USB_CONFIGFS`, `USB_F_ACM/NCM/RNDIS`, `USB_U_SERIAL`, `USB_U_ETHER` (+ resto de `USB_F_*` por select) | `ukeinit` crea `acm.usb0` + `ncm.usb0`; rootfs: `10-uke-usb.network` (usb0 192.168.42.129) |
| `I2C_QCOM_GENI`, `QCOM_GPI_DMA` | `wcd939x_i2c@e` (ruta USB) y los dos KTZ8866 cuelgan de GENI I2C con DMA GPI |
| `DRM_MSM`, `DRM_PANEL_XIAOMI_O82`, `BACKLIGHT_KTZ8866`, **`SM_DISPCC_8550`** | display nativo; `qcom,sm7675-dispcc` lo sirve `dispcc-sm8550.c` (que incluye `uke-dispcc-votes.c`): sin él MDSS no tiene relojes |
| `QCOM_LLCC`, `QCOM_OCMEM`, `QCOM_UBWC_CONFIG` (+`DRM_*` helpers, `CEC_CORE`, `QCOM_MDT_LOADER` por select) | `DRM_MSM` depende de `QCOM_LLCC \|\| QCOM_LLCC=n` (idem OCMEM): con `=m` Kconfig topa MSM a `m`. Ningún nodo habilitado casa con LLCC/OCMEM (no prueban) |
| `NVMEM_SPMI_SDAM`, `NVMEM_REBOOT_MODE`, `POWER_RESET_QCOM_PON` | **ayuda al rollback**: `reboot bootloader` desde SSH (su overlay convierte `reboot_reason` en `nvmem-reboot-mode`, celda SDAM 0x48, bootloader=0x02) |

**No se cambia** (queda `=m` = ausente en esta prueba): GPU (`SM_GPUCC_CLIFFS`; con `msm.separate_gpu_kms=1` KMS no
lo necesita), ADSP/pmic_glink/battmgr/QRTR (§8), Wi-Fi/BT, audio, SPI touch, CPUCP/SCMI (cpufreq), PON-temp/RTC.
Comparado con `k52L76r.config`: lo que nuestro initramfs/rootfs/SSH necesita (devtmpfs, tmpfs, configfs, debugfs,
pstore, ext4, GPT, IPv4/6, packet, unix, cgroups, seccomp, BPF, autofs, fhandle) ya es `=y` en su config.

## 4. Parche propio: rechazo → panic diferido (punto 3 de la adopción)

`uke_abl_prepare_fdt()` hacía `pr_crit + while(true) cpu_relax()` en `setup_machine_fdt()`, antes de cualquier consola
(cuelgue mudo, reset físico). Ahora: si el transform/la entrada nativa **rechaza** (o el grafo es **foráneo**, modelo
distinto), se devuelve el FDT original intacto, se anota el veredicto y un `early_initcall` hace
`panic("UKE-SENEMOS: … stock vendor_boot DTB + stock dtbo required")`. A esa altura ya están PSCI (reset) y
`panic=10` de la cmdline → **reinicia en 10 s** (gasta un reintento de slot). Panic en `setup_machine_fdt` no
serviría: aún no hay PSCI ni `panic_timeout` (su `CONFIG_PANIC_TIMEOUT=0` colgaría igual). Antes del initcall el
kernel solo hace `setup_arch`/IRQ/timer con el DT vendor (sin drivers). Parche: `build/gates/patches/senemos-uke-abl-panic-en-vez-de-cuelgue.diff`.

## 5. Build

`build/kernel-pokes/senemos-7.2.9/build-senemos.sh`, lanzado con `setsid nohup`, `MAKE=/usr/bin/make ARCH=arm64 LLVM=1
LLVM_IAS=1 -j8` (su spec también limita a 8), `LOCALVERSION=-senemos.1.4054.3-ouke1`, objetivos `Image.gz dtbs`
(módulos **no**: no se instalan). Toolchain clang/LLD **23.1.1** (ellos 23.1.2 Fedora). Log `build/logs/build-senemos.log`.

Resultado (17-oct 20:45→20:54, **0 errores, 0 warnings**), `kernelrelease = 7.2.9-senemos.1.4054.3-ouke1`:

| Artefacto | Tamaño | sha256 |
|---|---|---|
| `senemos-build/arch/arm64/boot/Image` | 50 297 344 B (image_size cabecera 53 084 160) | `caaadc6964a79dddee90aae636eee6afa1e07cb0fe3f1dbbe303c01bafedcfb2` |
| `senemos-build/arch/arm64/boot/Image.gz` | 15 992 009 B | `cce61fdf8f6541139937d5fd5e8673706497e4b7ea4d6a874d145d99537166e6` |
| `senemos-build/.config` (= `config-senemos-ouke1`) | — | `163bde55d0ca6cc69780b899f57325db1d5b7e897fda8869b9d772c0fadf779a` |
| `dts/qcom/sm7675-xiaomi-uke.dtb` (solo compila; **no se usa**: el FDT lo da el ABL) | 5 217 B | `f56014471bfb5bbcd5a02ab8d21506747f15ff076aaca1c840dd1f99a8239229` |

`System.map` confirma built-in: `uke_abl_prepare_fdt`, `uke_abl_native`, `uke_abl_verdict_check`, `ufs_qcom_probe`,
`dwc3_qcom_probe`, `acm_alloc_instance`, `ncm_alloc_inst`, `geni_i2c_probe`, `gpi_probe`, `ktz8866_probe`,
`disp_cc_sm8550_probe`, `msm_drv_probe`, `dpu_dev_probe`, `dsi_dev_probe`, `o82_probe`, `nvmem_reboot_mode_probe`.
Ojo: el Image crudo (50,3 MB) es mayor que el de L76R (41,7 MB, que el ABL ya descomprime); no hay fuente primaria del
techo del ABL (se supone 64 MiB, R-12): gate en el repack < 64 MiB.

## 6. Empaquetado: `build/gates/repack-senemos.py`

Clon de `repack-k52L76r.py`: misma base v4 (`boot-s240-mem2g.img` `e3c60969…`), `Image.gz` @4096, initramfs embebido,
`ramdisk_size 0`, cmdline en el campo de cabecera, AVB0/AVBf en sitio, deltas confinados. Gates nuevos (sin marcadores
UKE-L7x): config == `config-senemos-ouke1`; banner `Linux version 7.2.9-senemos.1.4054.3-ouke1`; cpio embebido ==
k34-fw (trae `/ukeinit`); **los tres overlays (`ufs`/`usb`/`display.dtbo`) embebidos byte a byte x1**; selector O82-42,
mensaje de la entrada nativa, mensaje `UKE-SENEMOS` del parche propio y modelo Uke presentes; **ausentes**
`root=PARTLABEL=linux` y `rdinit=/usr/lib/systemd/systemd`; Image < 64 MiB; `unpack_bootimg` (kernel y cmdline).

**cmdline** (nueva; no hereda la cadena de bytes L57…L77):
```
rdinit=/ukeinit panic=10 console=tty0 fbcon=map:0 fbcon=font:TER16x32 consoleblank=0 console=ttyGS0,115200
hung_task_timeout_secs=20 hung_task_panic=0 watchdog_thresh=10 clk_ignore_unused pd_ignore_unused
regulator_ignore_unused fw_devlink.strict=0 msm.separate_gpu_kms=1 systemd.unit=multi-user.target
printk.always_kmsg_dump=0 plymouth.enable=0 iomem=relaxed
```
- **Fuera**: `memmap=` (x86, sin efecto en arm64), `arm_smmu.uke_*`/`msm.uke_*` (no existen aquí),
  `arm-smmu.disable_bypass=0` y `fw_devlink=permissive` (senemos corre con los valores por defecto).
- **Dentro, de su cmdline**: `msm.separate_gpu_kms=1`, `consoleblank=0`, `fbcon=font:TER16x32`, `*_ignore_unused`,
  `systemd.unit=multi-user.target` (sin sddm: sin GPU no hay compositor y `modetest` necesita el maestro DRM libre).
- **`fw_devlink.strict=0`**: el `/chosen/bootargs` del DT vendor trae `fw_devlink.strict=1` (y `kpti=0`,
  `swiotlb=noforce`, `rcu_nocbs`…); con `CMDLINE_FORCE` senemos nunca los veía. Va detrás → gana.
- Orden real de `bootargs` (medido): DT vendor (684 B) + vendor_boot (154 B) + **boot.img** + añadidos del ABL
  (`msm_drm.dsi_display0=…`, `console=ttynull`, `init=/init`…). La cmdline mide 360 B y nuestros tokens acaban en ~1200 < 2048
  (`COMMAND_LINE_SIZE`). El selector que exige `uke-abl-native.h` se lee de la propiedad FDT completa, no de
  `/proc/cmdline` (truncada).

**boot.img**: `build/bootimg/boot-uke-senemos-7.2.9.img` — **sha256 `4894a841de1d1dd23f00a865e6b13169b11d498502948aeddf8295984d911eca`** (`.sha256` al lado; informe
`build/bootimg/repack-senemos-7.2.9-report.txt`).

## 7. DTBO: hace falta el STOCK (y se comprobó que el transform lo admite)

Su `uke-abl.c` no usa DT propio: copia el FDT del ABL a 2 MiB y exige ~25 grupos OEM exactos (modelo
`Qualcomm Technologies, Inc. Uke based on SM8635`, `qcom,board-id <8 0>`, `qcom,cliffs-mtp`, regs UFS, celda de
reboot, Wi-Fi, layout GPU/GMU/SRAM/SDAM, OPP GPU, bus y DMA del KTZ secundario, grafo SPI/novatek, 20 pines); luego
aplica overlays UFS/USB, empareja KTZ, deshabilita los consumidores no admitidos del apps-smmu, crea simplefb, y la
entrada nativa exige además `xiaomi,uke`, el selector O82-42 en `/chosen/bootargs`, KTZ primario y `vsp/vsn`, y aplica
el overlay de display.

**Checker propio** `dt/check-uke-abl.py`: port a mano de esas comprobaciones/transformaciones (pylibfdt) con los
overlays aplicados por `fdtoverlay` (mismo `fdt_overlay_apply` de libfdt). `dt/abl-root-merge.py` emula lo que el ABL
hace y `fdtoverlay` no: copiar las propiedades de la raíz del dtbo (modelo/board-id), lo que confirma el DT vivo.

| Entrada (vendor_boot OS3 `3ee6d4ac…` + dtbo) | Transform | Nativo |
|---|---|---|
| **DT vivo de Android OS3** (`build/android/dt-full-uke-android/base`, ABL real, dtbo stock) | **ADMITIDO** (47 consumidores SMMU deshabilitados) | **OK** |
| base 0/1/2/3 (Cliffs/7/7P/P) + **dtbo stock** (`dtbo_b-0` `e8f991e3…`) | **ADMITIDO** (51/51/47/47) | **OK** (×4) |
| base 0–3 + **s288** (`dtbo_a`) | **RECHAZO** ×4: `legacy_layout` (kgsl `reg` `<0x3d9e000 0x2000>` ≠ `0x1000`), `backlight_bus` y `spi_graph` (compatibles reescritos) | — |

El DT vivo da 47 → la base real es la 2 o la 3 (Cliffs7P/CliffsP), coherente con el `msm-id 283` del dtb palawan.
Conclusión: **con s288 este kernel no arranca** (antes: cuelgue mudo; con el parche: panic + reinicio). Plan:
`dtbo_a ← build/backup-par-bueno/android-20261017/dtbo_b.img` (partición completa de 24 MiB, sha `27e61d21…`, incluye
el pie AVB del stock; su entrada DT es la verificada). Rollback: `dtbo_a ← dtbo_a.img` del mismo backup
(`69c82e7b…` = s288 `02d403c5…` + resto de la partición). Nota: con dtbo stock, los L7x/palawan **no** sirven (les
faltan los nodos de s288): el rollback son siempre las dos particiones juntas.

## 8. Carga / ADSP (punto 5)

Su kernel trae la pila: `qcom_q6v5_pas` con `qcom,cliffs-adsp-pas` (`auto_boot=false`, `adsp.mdt` + `adsp_dtb.mdt`),
`pmic_glink` «battery-only» (`xiaomi,uke-pmic-glink`), `qcom_battmgr` con IDs Uke, `qcom_pd_mapper`, QRTR — **todo `=m`**
y no se instala. En esta prueba: **no hay remoteproc ni power_supply** → **no carga**; la batería solo baja (el test
debe ser corto y empezar ≥ 3700 mV). `uke-adsp.service` (rootfs) hará `insmod` de los `.ko` palawan → «Invalid module
format» (vermagic `7.2.0-rc2-palawan`), luego «FALLO: no hay remoteproc adsp» y `exit 1`: **inocuo** (no toca sysfs del
gpr ni nada más). Variante futura (otro ciclo): `QCOM_Q6V5_PAS/QCOM_PMIC_GLINK/BATTERY_QCOM_BATTMGR/QCOM_PD_MAPPER/
QRTR(_SMD)/RPMSG_QCOM_GLINK_SMEM=y`; nuestro loader haría `echo start` y el PAS encontraría `/lib/firmware/adsp.mdt` y
`adsp_dtb.mdt` (mismos nombres). No se hace ahora: un cambio por ciclo.

## 9. `build/gates/flash-senemos-gated.sh` (NO ejecutado)

- `--check`: gates de PC — shas (boot, dtbo stock, s288 y boots de rollback), dtbo stock de 24 MiB con su única entrada
  == `e8f991e3…`, **re-ejecuta el checker** (DT vivo + 3 bases con stock → admitido + nativo; s288 → rechazo como
  control negativo).
- `flash`: gates fastboot (batería **≥ 3700 mV** duro, `FORCE_LOWBAT=1` solo con orden; `slot-retry-count:b ≥ 3`; lector
  ACM único vivo) → **escrituras: `dtbo_a ← stock`, `boot_a ← senemos`**; `set_active a`; `reboot`; espera SSH hasta ~4 min.
- `--post` (también al final de `flash`): relectura de `boot_a` y `dtbo_a` al tamaño exacto; `uname -r`; `/proc/cmdline`
  (sin FORCE); `/chosen/bootargs` con el selector; mensaje «isolated native display graph prepared» y ausencia de
  `UKE-SENEMOS`; dmesg de msm/dpu/dsi/o82/ktz/mdss + errores/underrun/fifo; `/sys/class/drm` (conector DSI,
  status/enabled/modes); `fb0` = msm; backlights; `touch_reset_state`; debugfs `encoder-*/status`; para `sddm`; **ids reales**
  de conector/CRTC con `modetest -M msm-kms -c/-e/-p`; patrón con `sleep 30 | modetest -M msm-kms -s <con>@<crtc>:#0 -v`
  (stdin abierto) y delta de underrun/vsync en 12 s; estado de remoteproc/power_supply/uke-adsp; UDC; copia el dmesg a
  `build/logs/`.
- `--rollback l77ba|l76r`: `dtbo_a ← s288 (backup)`, `boot_a ← L77b-a b302714a… / L76R f75a27fd…`, relectura.
- `EB` queda relleno con el sha de §6. **`--check` ejecutado en el PC: GATES DE PC OK** (17-oct ~21:0x). Antes de ejecutarlo: **fila pre-registrada en el ledger** con los dos shas,
  semáforo inter-proyecto, y **presupuesto**: son 2 escrituras (+2 del rollback); hoy ya hubo #655–#657.

**Criterio prefijado.** PASA = el dueño ve **texto** (fbcon/getty en tty1, fuente TER16x32) o el **patrón** de modetest.
G1–G2 verdes + negro ⇒ su solución no se traslada tal cual (OS3 vs su OS2, unidad) → comparar registros con native54
antes de otro ciclo. Sin SSH ⇒ ACM: `UKE-SENEMOS` = DT rechazado (reinicia solo); silencio = cuelgue antes de `ukeinit`.

## 10. Riesgos

| Riesgo | Detalle | Mitigación |
|---|---|---|
| Rechazo del DT en el aparato | El ABL real podría diferir del merge/DT vivo de Android | Checker sobre el **DT vivo** (ABL real) admitido; si aun así rechaza: **panic + reinicio** (no cuelgue), ACM, Vol-+Power, `--rollback` |
| Cuelgue antes de consola por otra causa | p.ej. en la transformación, en drivers built-in (orden de probe distinto al de sus módulos), SMMU/handoff | Lector ACM armado; `panic=10`; reset físico; rollback de 2 particiones |
| `=m→=y` cambia el orden de probe | Ellos cargan UFS/DWC3/MSM/panel/KTZ como módulos desde dracut | Mínimo necesario; `fw_devlink` por defecto (como ellos); probes diferidos resuelven |
| Bootargs del vendor que ellos no ven | `swiotlb=noforce`, `kpti=0`, `rcu_nocbs`, `cgroup.memory=nokmem` aplican aquí (los mismos que hoy con palawan) | `fw_devlink.strict=1` anulado; el resto ya funciona con nuestro rootfs |
| Sin carga | ADSP/battmgr `=m` | ≥ 3700 mV, prueba corta, rollback pronto |
| Sin GPU | gpucc `=m`; Hyprland/sddm no arrancarían | `systemd.unit=multi-user.target`; criterio visual con fbcon/modetest |
| Slots | Fallos gastan `slot-retry-count:a`; B (Android) no es arrancable sin borrar userdata (LV-R1) | Gate retry:b ≥ 3; no tocar B; rollback por fastboot |
| Rollback | Con dtbo stock los L7x no arrancan bien | Rollback siempre `dtbo_a`+`boot_a` juntos (`--rollback`) |
| Código externo | Kernel no confiable corriendo en la tablet (autorizado) | Revisión dirigida; ningún script suyo ejecutado; build sin hooks de host |

## 11. Ficheros

- Fuente/árbol: `build/kernel-pokes/senemos-7.2.9/{dl/,linux-7.2.9/,reproducir-arbol.sh,reproducir.log,deltas-omarchy.sh,build-senemos.sh}`
- DT: `build/kernel-pokes/senemos-7.2.9/dt/` (`vendor-*.dtb`, `dtbo_{a,b}-0.dtbo`, `abl-*.dtb`, `live-android-os3.dtb`,
  `check-uke-abl.py`, `abl-root-merge.py`, `enabled-compats.py`, `map-compats.py`, `compat-map.tsv`, `res-*-final.dtb`)
- Salida: `build/kernel-pokes/senemos-build/` (`.config`, `config-senemos-ouke1`, `config-delta-vs-su-native.diff`, `arch/arm64/boot/Image.gz`)
- Gates: `build/gates/repack-senemos.py`, `build/gates/flash-senemos-gated.sh`, `build/gates/patches/senemos-uke-abl-panic-en-vez-de-cuelgue.diff`
- Imagen: `build/bootimg/boot-uke-senemos-7.2.9.img` (+`.sha256`, informe de repack)
