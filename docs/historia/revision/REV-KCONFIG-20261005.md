# REV-KCONFIG — revisión config kernel port vs Android GKI — `uke` — 2026-10-05

Revisión kconfig (#528, subagente config kernel). Comparación de la config efectiva del
kernel Android (GKI 6.1.138-android14, `/proc/config.gz` de la captura FULL) contra la de
nuestro build (`~/gpu-work/build-uke/.config`, kernel 7.2.0-rc2,
fuente `palawan-linux` rama `uke-ports-20260915`), área por área del port.

- Config Android extraída (FUERA del repo, gitignoreado por ley): `/var/tmp/android-gki-config/.config`
  (origen: `build/evidencia/android-full/extracted-full/00-meta/config.gz` — la ruta
  `proc-config.gz` citada en la tarea no existe; el fichero real es `config.gz`).
- lsmod vendor (504 DLKM): `build/evidencia/android-full/extracted-full/15-common/lsmod.txt`.
- Contexto: `CAPTURA-FULL-20261005.md` y FLASH-LEDGER #527.
- La tablet sigue en Android: cero adb en esta ronda (solo ficheros ya capturados).

**Método/leyenda.** Para cada símbolo: valor en GKI (`A=`) y en nuestro build (`O=`),
`y`=built-in, `m`=módulo, `n`=explícitamente off, `—`=símbolo no declarado en esa config
(en GKI esto es lo normal para todo lo vendor: GKI apaga el SoC y lo carga como DLKM).
El veredicto juzga lo que NOSOTROS necesitamos (built-in o módulo sirve; para boot temprano
ya está casi todo `=y` en nuestro build y no toco esa decisión salvo drivers nuevos).

---

## Veredicto global

**El `.config` del build-uke ya trae activo prácticamente TODO el stack SoC** (pinctrl, clk
palawan, SMMU+qcom impl, remoteproc PAS con los compatibles cliffs/palawan, USB+PHYs,
typec/pmic-glink, DRM_MSM, UFS, thermal, GENI serial, watchdog, pstore, RPMH/reguladores,
interconnect palawan). El trabajo previo del port ya está plasmado en kconfig.

Solo quedan **3 símbolos disponibles-en-árbol que FALTAN** (panel, táctil, governor
thermal userspace), **1 símbolo EXTRA recomendable apagar** (QCOM_IOMMU legacy), y **2 gaps
reales de árbol que NO se arreglan con kconfig** (charger qti_battery_charger inexistente;
verificar chipid del Adreno732 en el catálogo) + 1 gap menor (minidump).

---

## a) IOMMU / SMMU

| CONFIG | Android GKI | nuestro .config | veredicto |
|---|---|---|---|
| IOMMU_SUPPORT | y | y | OK |
| IOMMU_IO_PGTABLE_LPAE | y | y | OK |
| ARM_SMMU | n | y | OK (GKI lo apaga porque el SoC lo trae el vendor; en mainline es obligatorio) |
| ARM_SMMU_QCOM | — | y | OK (impl qcom, en `arm-smmu-qcom.c` in-tree) |
| ARM_SMMU_QCOM_DEBUG | — | n | OK (debug del vendor, innecesario) |
| QCOM_IOMMU | n | **y** | **EXTRA** — driver legacy de MMU per-device (pre-SMMU); en SM8635 no aplica. Recomendado `n` |
| IOMMU_DEFAULT_DMA_STRICT | y | y | OK |
| IOMMU_DEFAULT_DMA_LAZY / PASSTHROUGH | n | n | OK (coincide con GKI; el port ya usa IDENTITY puntual por DT para WLAN) |

## b) pinctrl

| CONFIG | Android GKI | nuestro .config | veredicto |
|---|---|---|---|
| PINCTRL_MSM | n | y | OK |
| PINCTRL_PALAWAN | — | y | OK — nuestro DTS declara `qcom,palawan-tlmm` (pinctrl@f100000 en palawan.dtsi) |
| PINCTRL_CLIFFS | — | — | NO APLICA hoy — solo si se adopta el compatible vivo `qcom,cliffs-pinctrl` (FDT vendor, pinctrl@f000000); el driver existe (`pinctrl-cliffs.c`, Kconfig.msm:286) |
| PINCTRL_PALAWAN_LPASS_LPI | — | m | OK |
| PINCTRL_LPASS_LPI | n | m | OK |
| PINCTRL_QCOM_SPMI_PMIC | n | y | OK |

## c) clk

Drivers in-tree (`drivers/clk/qcom/`): el port usa nombres **tree-specific** `CLK_PALAWAN_*`
(no los `GCC_SM8x50` de upstream salvo DISPCC). NO hay `dispcc-palawan`: el port reusa
`dispcc-sm8550.c` (`SM_DISPCC_8550`) retocado (sin runtime PM, commit d1c7ef2e0).

| CONFIG | Android GKI | nuestro .config | veredicto |
|---|---|---|---|
| COMMON_CLK_QCOM | n | y | OK |
| CLK_PALAWAN_GCC | — | y | OK (`gcc-palawan.o`) |
| CLK_PALAWAN_GPUCC | — | y | OK (`gpucc-palawan.o`) |
| CLK_PALAWAN_CAMCC | — | y | OK (cámaras, para después) |
| SM_DISPCC_8550 | — | y | OK (dispcc cliffs) |
| QCOM_CLK_RPMH | — | y | OK |

Nota: los módulos vendor `clk_qcom` (DLKM) no son comparables — GKI no trae ninguno de estos drivers.

## d) remoteproc

Todos los drivers existen (`qcom_q6v5_pas.c` con compatibles `qcom,cliffs-adsp-pas`,
`qcom,cliffs-wpss-pas`, `qcom,palawan-{adsp,cdsp,mpss,wpss}-pas`; nuestro DTS usa los
`palawan-*`). El modem está disabled en el vendor (DT, WiFi-only).

| CONFIG | Android GKI | nuestro .config | veredicto |
|---|---|---|---|
| REMOTEPROC / REMOTEPROC_CDEV | y / y | y / y | OK |
| QCOM_RPROC_COMMON | — | m | OK (vendor: `rproc_qcom_common` DLKM) |
| QCOM_PIL_INFO | — | m | OK |
| QCOM_Q6V5_COMMON | — | m | OK |
| QCOM_Q6V5_PAS | — | m | OK (adsp/cdsp/wpss; vendor: `qcom_q6v5_pas` DLKM) |
| QCOM_SYSMON | n | m | OK |
| QCOM_MDT_LOADER | — | y | OK |
| QCOM_SMP2P / QCOM_SMEM | n / n | y / y | OK (imprescindibles para los q6v5; GKI los apaga, DLKM vendor) |
| RPMSG_QCOM_GLINK_SMEM | — | m | OK |
| QCOM_WCNSS_CTRL | n | m | OK (WPSS/WLAN fw service) |

## e) USB (host/gadget + PHYs)

| CONFIG | Android GKI | nuestro .config | veredicto |
|---|---|---|---|
| USB / USB_XHCI_HCD / USB_XHCI_PLATFORM | y | y | OK |
| USB_DWC3 | y | y | OK |
| USB_DWC3_DUAL_ROLE | y | y | OK |
| USB_DWC3_QCOM | **y** | y | OK (en este árbol compila además `dwc3-qcom-legacy.o`; vendor: `dwc3_msm` DLKM) |
| USB_DWC3_OF_SIMPLE | y | y | OK |
| PHY_QCOM_QMP_COMBO | — | y | OK (`usb_dp_qmpphy` del DTS; vendor: `phy_msm_ssusb_qmp`) |
| PHY_QCOM_QMP_USB | — | y | OK |
| PHY_SNPS_EUSB2 | — | y | OK (`usb_1_hsphy` compatible `qcom,palawan-snps-eusb2-phy`; vendor: `phy_msm_snps_eusb2`) |
| PHY_QCOM_EUSB2_REPEATER | — | y | OK (repeater pm7550ba; vendor: `repeater_qti_pmic_eusb2`) |
| USB_GADGET / USB_CONFIGFS | y | y | OK |

## f) typec

| CONFIG | Android GKI | nuestro .config | veredicto |
|---|---|---|---|
| TYPEC | y | y | OK |
| TYPEC_UCSI | y | y | OK |
| UCSI_PMIC_GLINK | — | y | OK (equivalente upstream de `ucsi_glink` DLKM; símbolo local de este árbol) |
| TYPEC_DP_ALTMODE | y | m | OK (vendor: `altmode_glink`) |
| QCOM_PMIC_GLINK | — | y | OK — en este árbol el build de `pmic_glink_altmode.o` va dentro de QCOM_PMIC_GLINK (no hay símbolo separado) |
| TYPEC_MUX_WCD939X_USBSS | — | — | OPCIONAL: el driver existe upstream (`wcd939x-usbss`, retimer/mux USBSS; vendor carga `wcd_usbss_i2c`) pero nuestro DTS aún no instancia el nodo. Solo si aparece un nodo retimer en el DTS |

## g) GPU

Kconfig OK; el riesgo está FUERA del kconfig (ver gaps).

| CONFIG | Android GKI | nuestro .config | veredicto |
|---|---|---|---|
| DRM_MSM | n (GKI: `msm_kgsl` techpack DLKM) | y | OK |
| DRM_MSM_DP / DRM_MSM_DSI | — | y / y | OK |
| DRM_MSM_GPU_STATE | — | y | OK |
| QCOM_UBWC_CONFIG | — | y | OK (entradas `qcom,cliffs[-mtp]` añadidas en d1c7ef2e0) |
| QCOM_LLCC | n | y | OK (slices LLCC del GPU) |
| KGSL | — | — | N/A: techpack vendor, no existe en mainline ni en este árbol (correcto: vamos por DRM_MSM) |

Gap driver (no kconfig): el catálogo `a6xx_catalog.c` NO tiene entrada para el Adreno732
del uke por nombre; el vendor usa **fw gen71100** (`gen71100_zap.mbn` en /odm/firmware,
hallazgo #527.2) → candidato natural la entrada `chip_ids 0x43030b00` (gen71100, gmu_chipid
0x70b0000, ya en catálogo). Si al arrancar DRM_MSM reporta un chipid distinto (p.ej.
0x43050d01 estilo "735"), habrá que añadir la entrada al catálogo. El commit ecbf7efd7 ya
instrumenta este bring-up.

## h) display

| CONFIG | Android GKI | nuestro .config | veredicto |
|---|---|---|---|
| DRM_MSM_DSI | — (DLKM `msm_drm`) | y | OK (phy DSI 7nm in-tree, parte del driver msm) |
| DRM_MIPI_DSI / DRM_DISPLAY_DSC_HELPER | y / — | y / y | OK (DSC 1.1 del panel dual-DSI) |
| **DRM_PANEL_XIAOMI_O82_DUALDSI** | — | **FALTA** | **=y recomendado** — driver in-tree (`panel-xiaomi-o82-dualdsi.c`, Kconfig:1349), deps OF+MIPI_DSI+BACKLIGHT ya y |
| BACKLIGHT_CLASS_DEVICE | y | y | OK (el panel lleva backlight propio) |

OJO (no kconfig): `xiaomi-uke.dts` aún tiene el TODO de `&mdss { status = "okay" }` +
nodos `mdss_dsi0/dsi1` + panel — sin DT no hay pantalla aunque el .config esté perfecto.

## i) input / táctil

| CONFIG | Android GKI | nuestro .config | veredicto |
|---|---|---|---|
| INPUT / INPUT_EVDEV / INPUT_UINPUT | y | y / y / m | OK |
| **TOUCHSCREEN_NOVATEK_NT36XXX_SPI** | — (`nt36532_touch` DLKM) | **FALTA** | **=y recomendado** — driver in-tree (`novatek-nt36xxx-spi.c`) portado contra el módulo vendor; compatibles `novatek,NVT-ts-spi` (el del FDT vivo) y `novatek,nt36xxx-spi`. El lápiz entra por el mismo driver (`novatek,pen-support`) |
| INPUT_PM8941_PWRKEY | — (`pm8941_pwrkey` DLKM) | y | OK (pwrkey/resin por PON) |

## j) mmc / storage

| CONFIG | Android GKI | nuestro .config | veredicto |
|---|---|---|---|
| MMC / MMC_BLOCK / MMC_SDHCI / MMC_SDHCI_PLTFM | y | y | OK |
| MMC_SDHCI_MSM | n | y | OK (vendor: `sdhci_msm` DLKM; para uke es UFS igualmente) |
| MMC_CQHCI | n | y | OK |
| SCSI / BLK_DEV_SD | y | y | OK |
| SCSI_UFSHCD / SCSI_UFSHCD_PLATFORM / SCSI_UFS_QCOM | y / y / n | y / y / y | OK (vendor: `ufs_qcom`) |
| SCSI_UFS_CRYPTO + QCOM_INLINE_CRYPTO_ENGINE | y | y | OK |
| PHY_QCOM_QMP_UFS | — | y | OK |

## k) thermal

| CONFIG | Android GKI | nuestro .config | veredicto |
|---|---|---|---|
| THERMAL / THERMAL_OF / THERMAL_GOV_STEP_WISE / THERMAL_GOV_POWER_ALLOCATOR | y | y | OK |
| **THERMAL_GOV_USER_SPACE** | **y** | **FALTA (n)** | **=y recomendado** — paridad GKI; sin él thermald/powerprofiles no pueden votar |
| QCOM_TSENS | — (`qcom_tsens` DLKM) | y | OK |
| QCOM_LMH | — (`msm_lmh_dcvs` DLKM) | m | OK |
| QCOM_SPMI_ADC_TM5 | n | m | OK |
| QCOM_SPMI_TEMP_ALARM | n | y | OK |
| QCOM_VADC_COMMON | — | m | OK |

## l) batería / charger

| CONFIG | Android GKI | nuestro .config | veredicto |
|---|---|---|---|
| POWER_SUPPLY | y | y | OK |
| QCOM_PMIC_GLINK | — | y | OK (transporte; incluye altmode en este árbol) |
| **QTI_BATTERY_CHARGER** | — (`qti_battery_charger` DLKM) | **FALTA — y NO EXISTE en el árbol** | **GAP REAL**: `drivers/power/supply/qcom/` no existe en palawan-linux (ni Kconfig ni driver). El vendor gestiona la carga 100% vía pmic_glink→ADSP (`qti_battery_charger`). Hay que PORTAR el driver upstream (`qti_battery_charger.c` + entrada Kconfig/Makefile), no es un toggle |
| QCOM_PMIC_PDCHARGER_ULOG | — | n | OK (log opcional del vendor `charger_ulog_glink`) |

## m) tty / serial

| CONFIG | Android GKI | nuestro .config | veredicto |
|---|---|---|---|
| SERIAL_QCOM_GENI | **y** | y | OK (GKI lo trae built-in; vendor también `msm_geni_serial`) |
| SERIAL_QCOM_GENI_CONSOLE | y | y | OK |
| QCOM_GENI_SE | y | y | OK |
| SERIAL_DEV_BUS (serdev) | y | y | OK |

## n) misc (watchdog / pstore / rtc / minidump)

| CONFIG | Android GKI | nuestro .config | veredicto |
|---|---|---|---|
| QCOM_WDT | n | m | OK (vendor lo lleva builtin al GKI-vendor) |
| PSTORE / PSTORE_RAM / PSTORE_CONSOLE / PSTORE_PMSG | y | y | OK (ramoops listo; los pokes ya están instrumentados) |
| QCOM_COINCELL | — | m | OK |
| RTC_DRV_PM8XXX | — | m | OK |
| QCOM_STATS | — | m | OK |
| QCOM_MINIDUMP | — | — | GAP menor: no existe en el árbol (vendor: `minidump`/`qcom_va_minidump` DLKM). No crítico para boot; ramoops/pstore ya cubren la depuración básica |

## BASE soc (transversal, soporte de todo lo anterior)

| CONFIG | Android GKI | nuestro .config | veredicto |
|---|---|---|---|
| ARCH_QCOM / QCOM_SCM / QCOM_SOCINFO | y / — / — | y / y / y | OK |
| QCOM_SMEM / QCOM_SMEM_STATE / QCOM_SMP2P / QCOM_SMSM | n* | y | OK |
| QCOM_RPMH / QCOM_COMMAND_DB / QCOM_RPMHPD / REGULATOR_QCOM_RPMH | n* | y | OK (reguladores pm7550/pm8550vs por rpmh en el DTS) |
| QCOM_AOSS_QMP / QCOM_QMI_HELPERS / QCOM_PDR_HELPERS / QCOM_PD_MAPPER | n* | y / y / y / m | OK |
| INTERCONNECT / INTERCONNECT_QCOM / INTERCONNECT_QCOM_PALAWAN / OSM_L3 / QCOM_ICC_BWMON | y / y / — | y / y / y / m / y | OK (icc directo cliffs en d1c7ef2e0) |
| CPUFREQ_DT / ARM_QCOM_CPUFREQ_HW | n | y / y | OK |
| QCOM_FASTRPC | n | m | OK (adsprpc, sensors/audio DSP) |
| NVMEM_QCOM_QFPROM | n | y | OK (speedbin GPU/CPU) |

\* GKI los apaga: en Android todo esto llega como DLKM vendor compilado fuera del GKI
(los `qcom_*`, `cmd_db`, `qcom_rpmh`, `qcom_glink_smem`, `qmi_helpers`, `pdr_interface`… del
lsmod). Por eso los valores GKI solo sirven de pista en lo común (USB, typec, serial,
pstore, governors), nunca en lo vendor.

---

## Gaps REALES del árbol (no se arreglan con .config)

1. **`drivers/power/supply/qcom/` NO existe** — sin `qti_battery_charger` (y su entrada
   Kconfig/Makefile) no hay gestión de carga/batería en Linux; el vendor la hace 100% por
   pmic_glink→ADSP (#527.4). El ADSP ya es arrancable (PAS `cliffs-adsp` sin proxy_pd).
   Portar desde upstream (fichero único + glink aux) o escribir cliente mínimo.
2. **Chipid del Adreno732 sin confirmar en el catálogo** — el vendor usa fw gen71100
   (`gen71100_zap.mbn`), que coincide con la entrada `0x43030b00` del catálogo; si el chipid
   real difiere, añadir entrada (drms/msm/adreno) — el bring-up ya está instrumentado
   (ecbf7efd7). Al copiar fw a `/lib/firmware/qcom/`: sqe+gmu de gen71100 y zap desde el
   path que use el port.
3. **DT display pendiente** — TODO en `xiaomi-uke.dts`: `&mdss`/`&mdss_dsi0`/`&mdss_dsi1`
   + panel o82 dual-DSI (el driver de panel ya está; sin nodos no sonda).
4. **DT battery pendiente** — cuando exista el driver (1), el nodo pmic-glink necesitará el
   child `battery` (hoy solo trae el `usb-c-connector` para ucsi/altmode).
5. (menor) `QCOM_MINIDUMP` inexistente; WLAN sigue siendo techpack (icnss2/cnss — fuera de
   upstream, trabajo WLAN aparte); retimer USBSS WCD939x existe upstream pero sin nodo DT.

---

## LISTA FINAL priorizada — cambios a `~/gpu-work/build-uke/.config`

| # | símbolo | valor hoy | nuevo | motivo |
|---|---|---|---|---|
| 1 | `CONFIG_DRM_PANEL_XIAOMI_O82_DUALDSI` | (ausente) | **=y** | Panel o82 dual-DSI DSC: único driver de panel del aparato, in-tree; sin él no hay display aunque mdss arranque |
| 2 | `CONFIG_TOUCHSCREEN_NOVATEK_NT36XXX_SPI` | (ausente) | **=y** | Táctil NT36532 por SPI + lápiz; compatibles ya alineados con el FDT vendor (`novatek,NVT-ts-spi`) |
| 3 | `CONFIG_THERMAL_GOV_USER_SPACE` | n | **=y** | Governor userspace (paridad GKI): sin él no hay control térmico desde userspace |
| 4 | `CONFIG_QCOM_IOMMU` | y | **n** | Limpieza: driver legacy MMU-40x pre-SMMU, no aplica a SM8635; evita sorpresas de binding |
| 5 | (opcional) `CONFIG_TYPEC_MUX_WCD939X_USBSS` | (ausente) | =m | Solo cuando entre el nodo del retimer USBSS al DTS (SS/DP fiable por el redriver que el vendor sí usa) |

TODO LO DEMÁS: sin cambios (el resto del stack ya está =y/=m correctamente).

NO-KCONFIG bloqueantes para el objetivo (en orden): port `qti_battery_charger` (1),
verificar chipid Adreno732 vs catálogo (2), cablear `&mdss*`+panel en `xiaomi-uke.dts` (3).

---

## Anexo: ficheros consultados

- `/var/tmp/android-gki-config/.config` (extraído de `extracted-full/00-meta/config.gz`, 2162 CONFIG)
- `~/gpu-work/build-uke/.config` (3036 CONFIG, clang/LLD, arm64 7.2.0-rc2) — SOLO LECTURA
- `palawan-linux`: `drivers/{clk,qcom,pinctrl/qcom,phy/qualcomm,iommu,remoteproc,usb/dwc3,usb/typec,gpu/drm/msm,mmc/host,thermal/qcom,power/supply,regulator,input/touchscreen,watchdog,rtc}`, `drivers/soc/qcom/Kconfig`, `arch/arm64/boot/dts/qcom/{palawan,lamma,xiaomi-uke}.dts*`
- `extracted-full/15-common/lsmod.txt`, `extracted-full/16-fixup/kgsl-3d0-sysfs/{gpu_model,gpu_available_frequencies}`, `extracted-full/01-gpu/dmesg-gpu.txt`
- FLASH-LEDGER #527, CAPTURA-FULL-20261005.md
