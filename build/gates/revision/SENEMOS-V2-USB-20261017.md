# SENEMOS-V2-USB — por qué la v1 no tenía gadget USB, el arreglo (ouke2) y los módulos

> 17-oct-2026, noche. **Solo PC**: sin adb/fastboot/ssh, sin flash, sin ledger, sin commit. Repo externo
> `/tmp/claude-1000/ext-senemos` (HEAD `43e4036`) solo lectura; no se ejecutó nada suyo. Continúa
> `SENEMOS-PRUEBA-PREP-20261017.md` (v1 = `boot-uke-senemos-7.2.9.img` `4894a841…`: display nativo OK, llega a
> `uke-arch login`, **sin USB hacia el PC**: ni ACM/NCM ni SSH a 192.168.42.129).

## 0. Resumen

| | |
|---|---|
| Causa | `dwc3` queda **diferido para siempre** (`-EPROBE_DEFER`): el overlay USB de senemos pone `usb-psy-name = "qcom-battmgr-usb"` en `&usb0` y el core DWC3 no sondea hasta que exista ese `power_supply`, que solo registra `qcom_battmgr` (`=m`, necesita `pmic_glink` + el ADSP). Nuestro initramfs no carga ninguno ⇒ **no hay `/sys/class/udc`** ⇒ no hay gadget. |
| `dr_mode` | **Descartado**: el DT final ya trae `dr_mode = "peripheral"`, `maximum-speed = "high-speed"`, `compatible = "qcom,sm7675-dwc3"`. |
| Cambio | **Una línea**: se quita `usb-psy-name` del overlay USB embebido (`dt/sm7675-uke-usb2-ouke2.dtso`). Config **idéntica** a ouke1; solo cambia el sufijo `-ouke2`. Display, UFS, cmdline, initramfs: sin tocar. |
| Imagen | `build/bootimg/boot-uke-senemos-7.2.9-v2.img` sha256 **`7848d68dbdc6dde2d60e4b3afedc266a3ee62eb8ecf3fcd1b8ad1ddedce746d4`** (96 MiB) |
| Release | `7.2.9-senemos.1.4054.3-ouke2` |
| Módulos | 1105 `.ko` en `senemos-build/modroot/lib/modules/7.2.9-senemos.1.4054.3-ouke2/`; tarball `modules-7.2.9-senemos.1.4054.3-ouke2.tar.zst` sha256 **`c0151cfb194ec6dbe673ad010414db88335c4732ec1c009ba148a96ca56bd078`** |
| Flash | `build/gates/flash-senemos-v2-gated.sh` (**NO ejecutado**): **solo `boot_a`**; `dtbo_a` ya es stock y no se escribe |

## 1. Diagnóstico (evidencia fichero:línea)

Cadena causal, de la causa al síntoma:

1. **El overlay añade la propiedad.** `/tmp/claude-1000/ext-senemos/src/boot/sm7675-uke-usb2.dtso:61`:
   `usb-psy-name = "qcom-battmgr-usb";` dentro de `&usb0` (el DT stock **no** la tiene:
   `fdtget dt/vendor-2.dtb /soc/ssusb@a600000 usb-psy-name` → `FDT_ERR_NOTFOUND`; idem `live-android-os3.dtb`).
   El DT que ve nuestro kernel (`dt/res-live-final.dtb` = vivo de Android + overlays) sí la lleva:
   `usb-psy-name = "qcom-battmgr-usb"`.
2. **El core DWC3 difiere si falta el supply.** `linux-7.2.9/drivers/usb/dwc3/core.c:2224-2226`:
   `usb_psy = power_supply_get_by_name(usb_psy_name); if (!usb_psy) return ERR_PTR(-EPROBE_DEFER);`
   y `core.c:2286-2288` (`dwc3_core_probe`): `dwc->usb_psy = dwc3_get_usb_power_supply(dwc); if (IS_ERR(...)) return dev_err_probe(..., "couldn't get usb power supply")`.
   Es lo **primero** que hace el core tras leer propiedades (antes de clocks/PHY/gadget). Lo llama el glue
   `drivers/usb/dwc3/dwc3-qcom.c:762` (`dwc3_core_probe(&probe_data)`).
   Su propio test lo fija como contrato: `tests/usb-charger-readiness-contract.sh:65-67`
   (propiedad ausente ⇒ `NULL`; propiedad presente y supply ausente ⇒ `ERR_PTR(-EPROBE_DEFER)`).
3. **Ese supply solo existe con battmgr.** `drivers/power/supply/qcom_battmgr.c:1137,1165` (`.name = "qcom-battmgr-usb"`),
   y en la config final: `CONFIG_BATTERY_QCOM_BATTMGR=m` (`.config:4054`), `CONFIG_QCOM_PMIC_GLINK=m` (`:7711`),
   `CONFIG_QCOM_Q6V5_PAS=m` (`:7625`; el ADSP arranca con `auto_boot=false`). Su sistema (dracut + systemd) carga esos
   módulos y **luego** dwc3 (que ellos también compilan `=m`, `native.config:6495`); nuestro initramfs k34-fw
   (busybox, sin kmod) no carga nada y además el rootfs aún no está montado ⇒ el supply no existe nunca.
4. **El initramfs espera un UDC que no llega.** El `/ukeinit` embebido (cpio k34-fw, bucle `while [ $i -lt 300 ]; ls /sys/class/udc`,
   `ukeinit:116-125`) espera **600 s** y emite `X9USB-UDC-no`; sin UDC no crea ni liga el gadget (`S118 RAMA C: sin UDC`)
   y sigue al `switch_root` (de ahí que la v1 llegue a `uke-arch login` pero sin USB). Tras el `switch_root`, `10-uke-usb.network`
   (`usb0` 192.168.42.129) no tiene interfaz que configurar.

**Hipótesis del encargo comprobadas y descartadas** (con el DT final y la config):

| Hipótesis | Resultado |
|---|---|
| `dr_mode` = host / rol por `usb-role-switch`/UCSI | **No**. DT final: `dr_mode = "peripheral"` (`sm7675-uke-usb2.dtso:69`), `maximum-speed = "high-speed"` (`:70`). El transform borra `interrupts-extended`, `extcon`, `usb-role-switch` de `/soc/ssusb@a600000` (`uke-abl.c:765-772`) y el glue exige peripheral (`dwc3-qcom.c:673`, parche 0013). UCSI/`pmic_glink` van deshabilitados en el overlay (`:19-31`). |
| gadget configfs / `f_ncm` / `f_acm` no están `=y` | **Sí lo están**: `CONFIG_USB_GADGET=y`(6643) `USB_LIBCOMPOSITE=y`(6671) `USB_CONFIGFS=y`(6684) `USB_F_ACM=y`(6672) `USB_F_NCM=y`(6677) `USB_CONFIGFS_{ACM,NCM,RNDIS}=y` `CONFIGFS_FS=y`(8865) `USB_DWC3=y`(6499) `USB_DWC3_QCOM=y`(6511) `USB_PHY_QCOM_UKE=y`(6642) `USB_REPEATER_QCOM_UKE=y`(6774) `USB_WCD939X_UKE=y`; `System.map`: `dwc3_core_probe`, `dwc3_qcom_probe`, `msm_eusb2_phy_probe`, `eusb2_repeater_probe`, `wcd939x_usb_uke_probe`, `configfs_composite_bind`. |
| El initramfs no espera `/sys/class/udc` | Sí espera (600 s, §1.4). No es el fallo. |
| eUSB2/repeater | PHY y repeater **no llegan a ejecutarse**: `dwc3_core_probe` aborta antes (L2286) de pedir el PHY. Estáticamente coherentes: PHY DT `qcom,param-override-seq = <0 0x58>` (lo que exige `phy-msm-snps-eusb2-uke.c:855-858`), `usb-repeater`→`pm7550ba` `eusb2-repeater@fd00` (`qcom,pmic-eusb2-repeater`, `=y`), regulador GDSC `qcom,sm7675-usb-gdsc` (`QCOM_GDSC_REGULATOR_UKE=y`). **No verificable sin el aparato**: ver §5. |
| Comparación con nuestro árbol que sí da gadget | `k52-L16-tree/drivers/usb/dwc3/core.c:2313-2380` tiene la **misma** lógica de psy, pero el DT vendor (s288 + base) **no** define `usb-psy-name`, así que `dwc3_get_usb_power_supply()` devuelve `NULL` y no difiere. La diferencia es solo esa propiedad. |

## 2. El cambio

- `build/kernel-pokes/senemos-7.2.9/dt/sm7675-uke-usb2-ouke2.dtso` = el `.dtso` de senemos **sin** la línea 61
  (diff: `build/gates/patches/senemos-usb-sin-usb-psy-name.diff`). No se edita el repo externo.
- `deltas-omarchy-v2.sh` (idempotente): compila el overlay (`cpp`+`dtc -@`, igual que `reproducir-arbol.sh`; se comprobó que
  el procedimiento reproduce byte a byte el `usb.dtbo` y el `uke-abl-overlays.h` de ouke1), lo deja en `linux-7.2.9/native-generated-v2/`
  (`ufs.dtbo`/`display.dtbo` copiados de ouke1, **idénticos**), regenera `arch/arm64/kernel/uke-abl-overlays.h` (cambia solo el array
  `uke_usb_overlay`: 5716 B → 5671 B) y fija `.config == config-senemos-ouke1` (copiada a `config-senemos-ouke2`).
  ouke1 queda respaldado en `senemos-build/ouke1-artefactos/` (Image, Image.gz, System.map, .config) y `native-generated/ouke1/`.
- **DT final comprobado** con el port del transform (`dt/check-uke-abl.py`) sobre el DT vivo de Android y las bases 1/2/3 + dtbo stock:
  `uke_abl_transform = 1 (ADMITIDO)` y `uke_abl_native = OK` ×4; control negativo con s288: `RECHAZO`. `dtc` del DT final v1 vs v2:
  **la única diferencia es la línea `usb-psy-name`**; `dr_mode = peripheral`, `high-speed` y `compatible` intactos.
- Efecto colateral (inocuo ahora): con `dwc->usb_psy == NULL`, `dwc3_gadget_vbus_draw()` devuelve `-EOPNOTSUPP`
  (`gadget.c:3161`) — es el comportamiento upstream sin supply — y no se pide presupuesto de corriente a la batería. **No hay carga ni
  en v1 ni en v2** (sin ADSP/battmgr). **Pendiente para el ciclo de carga**: al cargar `battmgr` por módulo habrá que reenlazar dwc3 con su
  supply (parche «late bind» en `dwc3_gadget_vbus_draw`/`dwc3_vbus_draw_work`, o volver a poner `usb-psy-name` cuando el ADSP arranque
  antes de dwc3). No se hace ahora: un cambio por ciclo.

## 3. Build y empaquetado

- `build/kernel-pokes/senemos-7.2.9/build-senemos-v2.sh`, desprendido (`setsid nohup`), `LOCALVERSION=-senemos.1.4054.3-ouke2`,
  `ARCH=arm64 LLVM=1 LLVM_IAS=1`, clang 23.1.1, `-j12`; objetivos `Image.gz dtbs modules` + `modules_install` + tarball.
  Log: `build/logs/build-senemos-v2.log` (0 errores, 0 warnings: `Image.gz` en 28 s (incremental), 1105 `.ko` en ~10 min, 21:39→21:50).
- `Image.gz` 15 991 940 B sha256 `df51a0d5b2587b72510a13b1e9aa39b5e95d46cb0af3e00b0cdc7c604ac00372` (v1: `cce61fdf…`).
- Repack: `python3 build/gates/repack-senemos.py --v2` (la v1 se conserva ya construida: `boot-uke-senemos-7.2.9.img` + `senemos-build/ouke1-artefactos/`; sin `--v2` el script aborta por build rancio/banner, no puede pisarla). Gates nuevos G3: `usb.dtbo` v2 **sin**
  `usb-psy-name`/`qcom-battmgr-usb`, con `peripheral`/`high-speed`/`qcom,sm7675-dwc3`; el overlay USB de ouke1 **ya no** está embebido;
  `ufs.dtbo` y `display.dtbo` byte a byte iguales a los de ouke1 (display intacto); la cadena `qcom-battmgr-usb` no aparece en el Image.
  Resto de gates (cmdline, initramfs k34-fw `ebc2de46…`, entrada nativa O82-42, 96 MiB, AVB, deltas confinados, `unpack_bootimg`) en verde.
  Informe: `build/bootimg/repack-senemos-7.2.9-v2-report.txt`.

| Artefacto | sha256 |
|---|---|
| `boot-uke-senemos-7.2.9-v2.img` (100 663 296 B) | `7848d68dbdc6dde2d60e4b3afedc266a3ee62eb8ecf3fcd1b8ad1ddedce746d4` |
| `boot-uke-senemos-7.2.9.img` (v1, rollback) | `4894a841de1d1dd23f00a865e6b13169b11d498502948aeddf8295984d911eca` |
| `native-generated-v2/usb.dtbo` (5671 B) | `e62c1ba77d50d385ebb5438716107cf5291e308be34f6f136d96268cfea3cec0` |
| `native-generated/ouke1/usb.dtbo` (5716 B) | `082dd8c5e0a28fb66c5d14a91bc7fd1fa205e8daf6cf20527805810a6bd6cacc` |
| `config-senemos-ouke2` (== ouke1) | `163bde55d0ca6cc69780b899f57325db1d5b7e897fda8869b9d772c0fadf779a` |
| `modules-7.2.9-senemos.1.4054.3-ouke2.tar.zst` | `c0151cfb194ec6dbe673ad010414db88335c4732ec1c009ba148a96ca56bd078` |

## 4. Módulos (`modroot` + tarball)

Los drivers que se cargarán luego **ya existían** como `=m`/`=y` en la config (no hizo falta tocarla):

| Función | Símbolos (config final) | Módulos generados (`kernel/…`) |
|---|---|---|
| ADSP / remoteproc | `QCOM_Q6V5_PAS=m` `QCOM_Q6V5_COMMON=m` `QCOM_SYSMON=m` `QCOM_PIL_INFO=m` `QCOM_RPROC_COMMON=m` (`QCOM_MDT_LOADER=y`, `QCOM_SMP2P=y`, `QCOM_SMEM=y` built-in) | `drivers/remoteproc/{qcom_q6v5_pas,qcom_q6v5,qcom_sysmon,qcom_common,qcom_pil_info}.ko` |
| QRTR / GLINK / PDR | `QRTR=m` `QRTR_SMD=m` `RPMSG_QCOM_GLINK_SMEM=m` `QCOM_PD_MAPPER=m` `QCOM_PDR_HELPERS=m` (`RPMSG_QCOM_GLINK=y`) | `net/qrtr/{qrtr,qrtr-smd}.ko`, `drivers/rpmsg/qcom_glink_smem.ko`, `drivers/soc/qcom/{qcom_pd_mapper,pdr_interface,qcom_pdr_msg,qmi_helpers}.ko` |
| pmic_glink / battmgr / UCSI | `QCOM_PMIC_GLINK=m` `BATTERY_QCOM_BATTMGR=m` `TYPEC_UCSI=m` `UCSI_PMIC_GLINK=m` (`xiaomi,uke-pmic-glink` en `pmic_glink.c:393-414`, IDs Uke en `qcom_battmgr.c`) | `drivers/soc/qcom/{pmic_glink,pmic_glink_altmode}.ko`, `drivers/power/supply/qcom_battmgr.ko`, `drivers/usb/typec/ucsi/ucsi_glink.ko` |
| Wi-Fi WCN6750 | `ATH11K=m` `ATH11K_AHB=m` `CFG80211=m` `MAC80211=m` `MHI_BUS=m` | `drivers/net/wireless/ath/ath11k/{ath11k,ath11k_ahb}.ko`, `net/wireless/cfg80211.ko`, `net/mac80211/mac80211.ko` |
| WPSS | lo atiende `QCOM_Q6V5_PAS` (`qcom_q6v5_pas.c:1588`, `cliffs_wpss_resource`, `qca6750/wpss.mdt`) | `qcom_q6v5_pas.ko` |
| GPU msm / Adreno | `DRM_MSM=y` (el driver GPU va dentro de `msm`), `SM_GPUCC_CLIFFS=m`, `DRM_GPUVM=y` | `drivers/clk/qcom/gpucc-cliffs.ko` |
| Sonido | `SND_SOC_QCOM=m` `SND_SOC_QCOM_COMMON=m` `SND_SOC_SM8250=m` `SND_SOC_SC8280XP=m` `SND_SOC_X1E80100=m` `SND_SOC_QDSP6=m` `QCOM_APR=m` `SOUNDWIRE_QCOM=m` `SND_SOC_WCD939X=m` `SND_SOC_WSA883X=m` `SND_SOC_WSA884X=m` `SND_SOC_LPASS_*_MACRO=m` | `sound/soc/qcom/{snd-soc-*,qdsp6/*}.ko` (33), `sound/soc/codecs/snd-soc-{wcd939x,wcd939x-sdw,wsa883x,wsa884x,lpass-*-macro}.ko`, `drivers/soundwire/soundwire-qcom.ko`, `drivers/soc/qcom/apr.ko` |
| USB (referencia, ya `=y`) | `USB_DWC3=y` `USB_DWC3_QCOM=y` `USB_PHY_QCOM_UKE=y` `USB_REPEATER_QCOM_UKE=y` `USB_WCD939X_UKE=y` | en `modules.builtin` (dentro del Image) |

- `modules_install INSTALL_MOD_PATH=build/kernel-pokes/senemos-build/modroot` (+ `depmod -F System.map`); se retiran los enlaces `build`/`source`
  (apuntaban al árbol del PC). Sin firma de módulos (`# CONFIG_MODULE_SIG is not set`) ni compresión: el `insmod`/`modprobe` busybox/kmod los carga tal cual.
- **1105 `.ko`**, 73 MiB (`modroot` 75 MB), vermagic `7.2.9-senemos.1.4054.3-ouke2 SMP preempt mod_unload aarch64` (sin `modversions`: solo valen con **este** Image); `modules.dep` 1105 líneas, `modules.alias` 9997; `modprobe --show-depends` resuelve bien `qcom_battmgr` (→ `qmi_helpers`, `qcom_pdr_msg`, `pdr_interface`, `pmic_glink`), `qcom_q6v5_pas` y `ath11k_ahb`. Tarball `modules-7.2.9-senemos.1.4054.3-ouke2.tar.zst` 13 696 667 B (`tar --sort=name --owner=0 --group=0`, `zstd -19`), 1453 entradas, sha256 `c0151cfb194ec6dbe673ad010414db88335c4732ec1c009ba148a96ca56bd078` (+ `.sha256` al lado).
- Instalación en la tablet (otro ciclo, con SSH): `tar --zstd -xf modules-7.2.9-senemos.1.4054.3-ouke2.tar.zst -C /` (deja `/lib/modules/7.2.9-senemos.1.4054.3-ouke2/`).
  Los `.ko` palawan que carga hoy `uke-adsp.service` **no** sirven con este kernel (vermagic `7.2.0-rc2-palawan`).
- Orden de carga previsto para carga/ADSP (cuando se haga): `qrtr`, `qcom_glink_smem`, `qcom_pd_mapper`, `qcom_q6v5_pas` (ADSP; `echo start`),
  `pmic_glink`, `qcom_battmgr`; Wi-Fi: `ath11k` + `ath11k_ahb` (WPSS vía `qcom_q6v5_pas`, `cliffs_wpss_resource`).

## 5. Si sigue sin UDC (riesgo residual declarado)

Esta es una causa **demostrada por lectura de código y DT**, no por log del aparato (no hay acceso). `dwc3_core_probe` era lo primero en fallar;
tras quitarlo, el siguiente tramo (clocks GCC, interconnect USB, GDSC, PHY eUSB2 + repeater PMIC, WCD939x USB2) es el que su propio sistema usa y
está `=y` aquí, pero **no se ha podido ejecutar**. Si el panel vuelve a mostrar la terminal y sigue sin SSH:
`/sys/kernel/debug/devices_deferred` (debugfs ya montado por `ukeinit`), y el parámetro `diag_probe` del PHY
(`/sys/module/phy_msm_snps_eusb2_uke/parameters/diag_probe`, `phy-msm-snps-eusb2-uke.c:702-713`: `diag_probe/10000` = último paso alcanzado,
`diag_probe%10000` = `-ret`; 115 = `EINPROGRESS`, 517 = `EPROBE_DEFER`) y `dwc3.diag_events` (`/sys/module/dwc3/parameters/diag_events`, `gadget.c:34-45`: bit0 reset, 1 connect-done, 2 setup, 3 get-descriptor, 4 address, 5 configured).
`flash-senemos-v2-gated.sh --post` ya imprime todo esto.

## 6. `build/gates/flash-senemos-v2-gated.sh` (NO ejecutado)

Copia de `flash-senemos-gated.sh` con: **una sola escritura (`boot_a`)**; gate estático en `--check` que falla si el camino de prueba contiene
`flash_one dtbo_a` (o no tiene exactamente un `flash_one boot_a`); `dtbo_a` stock verificado antes por `fastboot fetch dtbo_a` si el bootloader lo
soporta (si no: aviso + inferencia «v1 arrancó con display ⇒ transform admitió ⇒ dtbo_a es stock; con s288 habría rechazo») y después por relectura SSH
en `--post`; gates de PC con los overlays v2; `--rollback v1` (1 escritura: `boot_a ← 4894a841…`, display OK sin USB), `--rollback l77ba|l76r`
(2 escrituras, dtbo_a ← s288) como antes; `--post` añade el bloque G5 de USB (UDC existe, `state = configured`, `devices_deferred`, DT vivo sin
`usb-psy-name`). `--check` ejecutado en el PC: **GATES DE PC OK**. Antes de usarlo: orden del dueño, fila pre-registrada en el ledger con el sha de la
imagen v2, semáforo inter-proyecto, presupuesto de escrituras (esta prueba: 1 más el rollback), batería ≥ 3700 mV, un único lector ACM.
Llegar a fastboot desde la v1 (sin USB/SSH): Vol- + Power.

**Criterio prefijado v2.** PASA = hay SSH a 192.168.42.129 **y** el panel sigue mostrando la terminal (display igual que v1). Display negro con SSH vivo ⇒
regresión (no debería: solo cambia el array USB). Sin SSH y terminal OK ⇒ otra causa para dwc3 (§5), no repetir el flash: leer primero el `devices_deferred`
(techo de 3 ciclos por hipótesis).

## 7. Ficheros

- `build/kernel-pokes/senemos-7.2.9/{deltas-omarchy-v2.sh,build-senemos-v2.sh,dt/sm7675-uke-usb2-ouke2.dtso}`; overlays en `linux-7.2.9/native-generated-v2/` (v1 en `native-generated/ouke1/`)
- Salida: `build/kernel-pokes/senemos-build/{config-senemos-ouke2,modroot/,modules-7.2.9-senemos.1.4054.3-ouke2.tar.zst(.sha256),ouke1-artefactos/}`
- Gates: `build/gates/repack-senemos.py` (`--v2`), `build/gates/flash-senemos-v2-gated.sh`, `build/gates/patches/senemos-usb-sin-usb-psy-name.diff`
- Imagen: `build/bootimg/boot-uke-senemos-7.2.9-v2.img` (+`.sha256`, `repack-senemos-7.2.9-v2-report.txt`)
