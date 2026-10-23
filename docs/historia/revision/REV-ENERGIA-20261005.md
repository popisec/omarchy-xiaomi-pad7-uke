# REV-ENERGIA (2026-10-05) — batería/carga, térmica, USB/Type-C y vibrador

Revisor: subagente energía/thermal/USB (#528). Entrada: captura integral Android
`build/evidencia/android-full/extracted-full/` (03-battery, 04-thermal, 13-usb, 16-fixup,
15-common, 14-dt/dt-live.tar.gz, dt-nodes-pc) + port `~/gpu-work/palawan-linux` (7.2.0-rc2,
rama s150-postclk) + `~/gpu-work/build-uke/.config`. La tablet NO se tocó (solo análisis).

Leyenda veredictos: **OK** = port correcto · **FALTA** = fix necesario · **RIESGO** = vigilancia.

---

## 0. VEREDICTO GLOBAL

**La cadena de carga del port está rota en TRES puntos (F1–F3) y ninguno es de HW:**

1. `.config`: `CONFIG_BATTERY_QCOM_BATTMGR` **no está activado** (línea 3683 de
   `build-uke/.config`: `# CONFIG_BATTERY_QCOM_BATTMGR is not set`) → sin él no existe
   `/sys/class/power_supply/battery` aunque pmic_glink esté arriba.
2. `qcom_pd_mapper.c`: la tabla `qcom_pdm_domains` tiene `qcom,cliffs`/`qcom,palawan` pero
   **NO `qcom,lamma`**, que es el compatible raíz del DT del port
   (`xiaomi-uke.dts:38 compatible = "xiaomi,uke","qcom,lamma"`). `of_machine_get_match()`
   falla → «PDM: no support for the platform» → el PDR `msm/adsp/charger_pd` nunca sube →
   pmic_glink no tiene interlocutor de carga.
3. DT: `remoteproc_adsp` queda **`status = "disabled"`** en el DTB compilado
   (`build-uke/arch/.../xiaomi-uke.dtb`, 11-sep: `remoteproc@6800000 { status = "disabled"; }`)
   → **el ADSP no arranca en el port actual**; pmic_glink (transporte) sondea y UCSI/altmode
   se quedan sin respuestas; sin ADSP no hay gestión de carga ni FG (todo corre en el ADSP).

Sin ADSP el USB gadget SÍ funciona (shell por USB del G2 es la prueba), pero batería/UCSI/DP no.
El trayecto ya se validó entero en Ubuntu (ledger #4156/#4820: ADSP `running`,
`status=Charging` 19-20 %, PDR charger_pd UP con el stack `pd_mapper→pmic_glink→battmgr`),
así que no hay incógnita de HW: son tres piezas de enchufado.

---

## 1. P1 — Cadena de carga

### 1.1 Cadena en el VIVO (Android), con evidencia

Orden de arranque en `03-battery/dmesg-battery.txt` / `15-common/dmesg-full.txt`:

| t (s) | evento | driver |
|---|---|---|
| 6.863 | `qcom,gpr 3000000.remoteproc-adsp:glink-edge.adsp_apps` + `gpr_adsp_up: Q6 is Up` | ADSP arriba (glink-edge + GPR audio) |
| 6.898 | `PDR: Indication received from msm/adsp/charger_pd, state: 0x1fffffff` (UP) | PDR sobre servreg (pd-mapper) |
| 8.545 | `qti_battery_charger soc:qcom,pmic_glink:qcom,battery_charger: battery_chg probe start/done` | `qti_battery_charger` (QCOM battmgr client) |
| 8.637 | `ucsi_glink … enter ucsi_probe` | UCSI sobre glink |
| 8.639 | `altmode-glink … enter altmode_probe` | altmode (DP/audio acc) |

DT vivo (`14-dt/dt-live.tar.gz`, extraído a /tmp para análisis):

- `/soc/qcom,pmic_glink`: compatible `qcom,pmic-glink`, `qcom,protection-domain = "tms/servreg",
  "msm/adsp/charger_pd"`, `qcom,subsys-name = "lpass"`. Hijos: `qcom,battery_charger`
  (`qcom,battery-charger`, **#cooling-cells** = cdev de carga, props `mi,*`/`qcom,thermal-mitigation-step`),
  `qcom,altmode` (`qcom,altmode-glink`), `qcom,ucsi` (`qcom,ucsi-glink` + `connector`).
- `/soc/remoteproc-adsp@03000000`: compatible **`qcom,cliffs-adsp-pas`**, reg **0x3000000**,
  `qcom,qmp = <&aoss_qmp>`, `qcom,signal-aop`, status **okay**. Memoria:
  `adspslpi_region@9d400000` (0x4500000) y `q6_adsp_dtb_region@a1900000` (0x80000).
- No hay node SMB/charger SPMI: el cargador físico (pm8550ve/bq2597x charge-pump lado Xiaomi)
  se gobierna **solo** desde el firmware del ADSP vía glink. Confirmado: PMICs presentes
  (pmk8550, pmxr2230, pm8550vs, pm8550ve, pm7550ba, pmr735a, pm8010m/n) pero sin driver
  de charger Linux local.

### 1.2 ¿Qué pasa en el port si el ADSP no arranca? (y ¿arranca?)

- **pmic_glink** (=y) sondea ok: es solo transporte rpmsg/glink. Sin servidor battmgr, las
  peticiones se quedan sin respuesta: `qcom_battmgr` no crea power_supply; UCSI da timeouts
  (role/orientation por defecto); altmode no notifica nada.
- USB gadget sigue funcionando sin ADSP — **evidencia propia**: el G2 «shell por USB» del
  12-sep se logró sin ADSP (dwc3 + configfs no dependen de glink).
- **En el DTB actual NO arranca**: veredicto en §0.3 (status disabled). Histórico: con el
  stack cargado a mano SÍ arrancó en Ubuntu (ledger #4156/#4820-4835: «ADSP running,
  status=Charging», PDR charger_pd 0x1fffffff, y el remedio del fastboot-sin-carga era
  exactamente «Ubuntu con el ADSP arriba»).
- Además, **aunque se active el nodo**, el pd-mapper in-kernel rechazaría la plataforma por el
  compatible `qcom,lamma` ausente (§0.2): doble fallo en serie. Ambos deben ir juntos.

### 1.3 CONFIGs del port (build-uke/.config, kernel 7.2.0-rc2)

Ya correctos:

| CONFIG | estado | nota |
|---|---|---|
| `QCOM_PMIC_GLINK` | =y | en 7.2 incluye altmode (`drivers/soc/qcom/Makefile:14 obj-$(CONFIG_QCOM_PMIC_GLINK) += pmic_glink_altmode.o`) |
| `UCSI_PMIC_GLINK` | =y | UCSI glink ✓ |
| `TYPEC`/`TYPEC_UCSI`/`USB_ROLE_SWITCH`/`TYPEC_DP_ALTMODE` | =y/=y/=y/=m | ✓ |
| `QCOM_PDR_HELPERS`/`QCOM_PDR_MSG` | =y | ✓ |
| `QCOM_PD_MAPPER` | =m | in-kernel pd mapper (tiene `adsp_charger_pd` en su tabla, `qcom_pd_mapper.c:262`) |
| `QCOM_Q6V5_COMMON/ADSP/MSS/PAS` | =m | PAS para ADSP ✓ (el fork añade `cliffs-adsp-pas` y `cliffs-wpss-pas`, `qcom_q6v5_pas.c:1627+`) |
| `RPMSG_QCOM_GLINK(=y)/_RPM(=y)/_SMEM(=m)`, `QRTR(=y)/QRTR_SMD(=m)`, `QCOM_SMEM(=y)` | ✓ | |
| `QCOM_AOSS_QMP(=y)`, `QCOM_QMI_HELPERS(=y)`, `AUXILIARY_BUS(=y)` | ✓ | PMIC_GLINK los exige |
| `REGULATOR_QCOM_RPMH(=y)`, `QCOM_RPMH(=y)`, `REGULATOR_QCOM_SPMI(=y)`, `REGULATOR_QCOM_USB_VBUS(=m)` | ✓ | |
| `BATTERY_QCOM_BATTMGR` | **no set** | **FALTA (F1)** — «Qualcomm PMIC GLINK battery manager support», `drivers/power/supply/Kconfig:211`; el aux `ps` de pmic_glink solo matchea con él |

Nota: `CONFIG_QCOM_PMIC_GLINK_ALTMODE` **no existe** en 7.2 (símbolo antiguo); altmode va con
PMIC_GLINK. `INPUT_PM8XXX_VIBRATOR=m` presente pero es el vibrador SSBI viejo, no sirve (§6).

---

## 2. P2 — Fuel gauge

**Veredicto: NO hay chip FG expuesto a Linux; el FG corre en el ADSP (battmgr). Suficiente.**

- `power_supply/battery` (Android) expone: capacity 9, charge_full = charge_full_design =
  8.850.000 µAh (= design: FG calibrado con la celda «O82_8850mah_45w»), voltage_now 3.719.184 µV,
  voltage_ocv, voltage_max 4.480.000 (FFC), current_now −103.274 µA (uevent; positivo=descarga),
  current_avg, power_now 55.492.920 µW, temp 270 (27,0 °C), cycle_count 91,
  charge_control_start/end_threshold 70/80, constant_charge_current 5.780.000 µA (45 W en fast).
- `qcom-battery/attrs.txt` (clase Xiaomi `xiaomi_charge`): `bq2597x_*` (bus 157 mV/5 mA,
  chip_ok 1, cell_vendor SAMSUNG, authentic 1) → hay **charge-pump bq2597x** gobernado por el
  ADSP, no por Linux. Los `pen_*` son del lápiz (hall), específicos Xiaomi.
- Mainline: no existe driver `qcom,pm8550b-fg`/smb5 para esta ruta; el camino mainline ES
  `QCOM_PMIC_GLINK` + `BATTERY_QCOM_BATTMGR` (`qcom_battmgr`). Con eso el port verá
  `battery` (cap/volt/temp/current/cycle_count/charge_control_end_threshold vía
  `qcom_battmgr_set_charge_control`), `usb` y `ac`. **Suficiente para % y carga** (probado en
  Ubuntu, ledger #4376: la corriente de `qcom-battmgr-bat` es el entero del ADSP).
- Matices port: sin ADSP no hay datos; sin `wireless` psy (battmgr solo registra wls para
  sc8280xp) — irrelevante; sin `ucsi-source-psy` (patch vendor) — irrelevante.

---

## 3. P3 — Reguladores

**Veredicto: OK en .config; DT del port solo trae los grupos necesarios para v1 (b y d).**

- Vivo: 250 reguladores (`03-battery/regulator_summary.txt`). Los define el driver RPMh
  (rails pm7550/pm8550 vía cmd-db) + GDSCs + LDOs SPMI de cámara (`camera_*_avdd_ldo`) y
  display (`display_panel_vsp/vsn` 5.8 V).
- Los 18 `rpmh-regulator-ldom*/ldon*/smpj1` de `unbound-devices.txt` (`qcom,rpmh-vrm-regulator`,
  bajo `17a00000.rsc:drv@2`) son reguladores **de nivel** (votos de pm-level de dominios
  CX/MX/GMX…) que en el downstream quedan como platform devices sin bind: artifact del vendor,
  los votos funcionan igual. **Irrelevantes para el port** (nuestro mainline usa
  `REGULATOR_QCOM_RPMH` con nodos explícitos y rpmhpd para niveles).
- Port: `REGULATOR_QCOM_RPMH=y` + `REGULATOR_QCOM_SPMI=y` ✓; DT ya trae
  `regulators-0` (pm7550 «b»: bob, s1b-s3b, l1b-l23b — incluye las de USB l2b/l3b/l4b/l17b/l7b)
  y `regulators-2` (pm8550vs «d»: UFS). Faltan (ya anotado como TODO v2 en el dts): grupos
  c/e/g + pmr735a-e para display/touch. vph_pwr fixed 3.7 V always-on ✓.

---

## 4. P4 — Thermal

### 4.1 Zonas del vivo (63), las relevantes con temp capturada

- **Silicio (tsens)**: `cpuss-0` 43.8 °C · `cpu-0-0-0…cpu-2-0-2` (11 zonas, 34–39 °C) ·
  `gpuss-0/1/2/3` 34.2–35.0 °C · `ddr` 35.8 °C · `aoss-0/1/2` 34.8–38.2 °C ·
  `nsphvx-0/1`, `nsphmx-0/1` (DSP HVX/MX) 34.6–35.8 °C · `video`/`camera-0/1` · `mdmss-0…3`
  (muertas: modem disabled) · `socd` 91 (mA).
- **PMIC**: `pmxr2230_tz` 31.6 °C, `pm7550ba_tz` 29.7, `pm8550vs_c_tz` 28.7, `pm8550ve_tz` 29.2,
  `pmr735a_tz` 37.0, `pm8010m/n_tz` (wireless); BCL/ibat (`pmxr2230-bcl-lvl0/1/2`,
  `pm7550ba-bcl-lvl0/1/2`, `pm7550ba-ibat-lvl0/1`, `pm7550ba-2s-ibat-0/1`) en mV/mA (0/−562…).
- **Piel/NTC (ADC)**: `quiet_therm` 28.4 °C · `charger_therm0` 30.3 · `xo-therm` 30.3 ·
  `conn_therm/2` 28.4/28.4 · `cpu_therm` 32.1 · `flash_therm` 28.5 · `display_therm` 29.2 ·
  `backlight_therm` 31.1 · `wifi_therm` 30.1 · `usb` 27.0 · `battery` 27.0 (zone **disabled**;
  la temp de batería entra por el charger/battmgr) · `vbat` 3.687 V · `mmw*` (no montadas).
- Governors: todos **step_wise** (sysfs `policy`). Cooling (45): `cpufreq-cpu0/3/7`
  (13–17 estados), `cpu-cluster0/1/2`, `cpu-hotplug0-7`, `pause-cpu*`, `thermal-pause-*`
  (vendor), `ufs1` (2), `display-fps` (16), `ddr-cdev` (9), `devfreq-…kgsl-3d0` (8) + `gpu`,
  `panel0-backlight`, `cdsp/cdsp_hw`, **`battery` (16 estados = mitigación de corriente de carga)**,
  `qcom,icnss_cdev1/2`.

### 4.2 Driver y port

- tsens para el silicio: `CONFIG_QCOM_TSENS=y` ✓ (DTB port: 45 zonas tsens — aoss0/1, cpuss0/1,
  cpu0-7 top/bottom, nsphvx/mx, gpuss, ddr, video, camera…; trips 110 °C hot / 115 °C critical).
- Governors: `THERMAL_GOV_STEP_WISE=y` (default) + `THERMAL_GOV_POWER_ALLOCATOR=y` ✓;
  `CPU_FREQ_THERMAL=y` + `DEVFREQ_THERMAL=y` ✓ + `ARM_QCOM_CPUFREQ_HW=y` (cdev cpufreq) ✓.
- `CONFIG_QCOM_LMH=m`: **no hay nodo lmh ni en el DT vivo ni en palawan.dtsi** → driver idle,
  inofensivo. El límite HW real lo fija AOP; sin acción.
- **Hueco real**: los NTC de piel (`quiet_therm`, `xo-therm`, `charger_therm0`, `conn_therm`…)
  no existirán en el port: `pmk8550.dtsi` del fork **no trae `vadc@9000`** (el DT vivo sí:
  `qcom,spmi@c42d000/qcom,pmk8550@0/vadc@9000` + `glink-adc` de `pmic_glink_log` para el resto).
  `QCOM_SPMI_ADC5=m`/`ADC_TM5=m` están, pero sin nodos no hacen nada → sin skin-temp no hay
  mitigación de carga por temperatura de chasis (el cdev «battery» del vendor tampoco existe en
  mainline-battmgr). RIESGO asumible en v1 (el ADSP limita por temp de celda por sí solo); fix
  F6 lo cubre.
- cooling del port: cpufreq (8 CPU), GPU devfreq, UFS devfreq. Sin backlight/display aún (v2).

---

## 5. P5 — USB / Type-C

### 5.1 Cadena del vivo

- `ssusb@a600000` (compatible downstream `qcom,dwc-usb3-msm`) con hijo `dwc3@a600000`
  (`snps,dwc3`, `dr_mode = "otg"`, `usb-role-switch`); `interrupts` pwr_event + 4 PHY IRQs;
  `USB3_GDSC-supply` + `gcc_usb30_prim_gdsc` ON (regulator_summary); `qcom,use-eusb2-phy`,
  `qcom,wcd_usbss` (SBU por el codec WCD939x).
- PHYs: `hsphy@88e3000` = **`qcom,usb-snps-eusb2-phy`** (eUSB2 + repeater pm7550ba) y
  `ssphy@88e8000` = **`qcom,usb-ssphy-qmp-dp-combo`** (USB3+DP).
- Control: `soc:qcom,pmic_glink:qcom,ucsi` → `typec/port0`: power_role `[sink]`, data_role
  `[device]`, op mode **3.0A**, PD rev 3.0, TypeC 1.3; partner (PC) sin PD. UDC
  `a600000.dwc3`: driver `dwc3-gadget`, gadget `g1` (adb), **state=configured,
  current_speed=high-speed**, maximum_speed=super-speed (`16-fixup/udc-…txt`).
- dmesg: `msm-dwc3 a600000.ssusb` estados idle→peripheral; `dwc3 a600000.dwc3: Adding to
  iommu group 47`.

### 5.2 Port

- `.config`: `USB_DWC3=y` (DUAL_ROLE), **`USB_DWC3_QCOM=y`** (matchea `qcom,snps-dwc3` — el
  glue del fork además acepta `qcom,dwc-usb3-msm`, `dwc3-qcom.c:985+`), `USB_DWC3_OF_SIMPLE=y`,
  `PHY_QCOM_QMP_COMBO=y`, `PHY_SNPS_EUSB2=y`, **`PHY_QCOM_EUSB2_REPEATER=y`**, `USB_XHCI_*`
  host ✓, gadget configfs completo (`USB_CONFIGFS=y`, `F_FS`, ACM, RNDIS…) ✓.
- DT: `usb_1` okay con `dr_mode="otg"` + role-switch; `usb_1_dwc3_hs → pmic_glink_hs_in` ✓;
  `usb_1_hsphy` (vdd l2b, vdda12 l4b, phys pm7550ba_eusb2_repeater vdd3 l17b/vdd18 l7b) ✓;
  `usb_dp_qmpphy` okay (l4b/l3b) ✓. **El modo device ya funciona en el port** (shell USB G2).
- **FALTA (F5)**: `connector@0/port@1` (SS) tiene `remote-endpoint = <0>` y `usb_dp_qmpphy_out`
  queda sin consumidor → **SuperSpeed USB3 y DP-altmode no enrutan** (por ahora HS basta para
  adb/carga; el modo 3.0A de carga ya lo negocia el ADSP por UCSI, no por las líneas SS).
- `orientation-gpios = <&tlmm 122>` sigue sin confirmar en uke (TODO ya en el dts); el vivo no
  muestra el gpio (UCSI lo reporta por glink). Verificación barata al probar con el cable
  invertido (F5 incluye test).
- Host mode: funciona como role-switch (xhci platform), pero **VBUS 5 V de salida depende del
  boost del cargador vía ADSP** (battmgr no lo expone) → usar hub alimentado al principio.

---

## 6. P6 — Vibrador

- DT vivo: `/soc/qcom,spmi@c42d000/qcom,pm7550ba@7/qcom,vibrator@df00`, compatible
  **`qcom,qpnp-vibrator-ldo`**, `qcom,vib-ldo-volt-uv = 3000000` (3.0 V), `qcom,disable-overdrive`,
  status okay. **UNBOUND también en Android** (no existe driver vendor cargado: lsmod sin él).
- Mainline: **no existe driver** (`drivers/input/misc/` solo tiene `pm8xxx-vibrator.c` del
  SSBI pm8xxx — HW distinto). Hay `pwm-vibra`/`gpio-vibra` que no aplican.
- Vale la pena: es un LDO SPMI dedicado (enable + set voltaje, ~100-150 líneas con regmap SPMI).
  Prioridad **baja** (haptics). El nodo va en pm7550ba SID7 — el mismo que el port ya incluye
  (eusb2 repeater está en `pm7550ba.dtsi:63` sin vibrator). Si se quiere: driver propio
  `qcom,pm7550ba-vibrator` o port del downstream qpnp-vibrator-ldo.

---

## 7. P7 — Clasificación de los 76 unbound del vivo

**Afectan a energía/thermal/USB en el port:**
- `qcom,vibrator@df00` → §6 (único «energético» con acción posible).
- 18× `rpmh-regulator-ldom/ldon/smpj` → artifact downstream (§3): no portar nada.

**Dominio de otros revisores:** `soc:xiaomi_wifi_gpio` (radio), `qcom,gpu-coresight-cx/gx`,
`qcom,hdcp`, dma-heaps display, `qseecom*` (DRM/TEE).

**Irrelevantes para el port:** `hypervisor`+`gunyah-vm`+`test-dbl/msgq` (hypervisor Gunyah),
`icc-test`, `regulatory`, `timer/armv8-timer`+`17420000.timer`, `0.mmio-sram`, `*.syscon` (14),
`spmi-debug`, `msm-imem`, `cpuss-sleep-stats`, `gh-qtimer`, `mpm2-sleep-counter`, `limits-stat`,
`llcc-perfmon`, `ete0-7` (coresight), `ipcc-self-ping-*`, `tlmm-vm-test`, `Fixed MDIO bus`,
`i2c-2/4/5/6/7/8/9` (adapters virtuales), `serio *`.

**Ningún dispositivo USB/Type-C/charger/FG está unbound**: la cadena energética del vendor está
100 % bound (pmic_glink + hijos + dwc3 + spmi).

---

## 8. FIXES PRIORIZADOS

### F1 — P0 · `.config`: activar el driver de batería
```diff
--- build-uke/.config (línea 3683)
-# CONFIG_BATTERY_QCOM_BATTMGR is not set
+CONFIG_BATTERY_QCOM_BATTMGR=y
```
Riesgo: nulo (compila; ya hay `qcom_battmgr.ko` viejo en el árbol fuente de una build anterior —
hacer `make prepare`/clean del fichero). Sin esto no hay `/sys/class/power_supply/battery`.

### F2 — P0 · driver: entrada `qcom,lamma` en el pd-mapper
```diff
--- a/drivers/soc/qcom/qcom_pd_mapper.c
+++ b/drivers/soc/qcom/qcom_pd_mapper.c
@@ (tabla qcom_pdm_domains, junto a qcom,palawan)
 	{ .compatible = "qcom,palawan", .data = sm8550_domains, },
+	/* uke/lamma (SM8635): el DT del port lleva compatible raiz "qcom,lamma"
+	 * (xiaomi-uke.dts); sin esta entrada of_machine_get_match() falla y el
+	 * PDR msm/adsp/charger_pd nunca resuelve => sin carga ni FG. */
+	{ .compatible = "qcom,lamma", .data = sm8550_domains, },
```
Verificación en arranque: dmesg **sin** «PDM: no support for the platform» y con
«PDR: Indication received from msm/adsp/charger_pd, state: 0x1fffffff» (igual que el vivo).
Riesgo: nulo (la tabla ya mapea cliffs/palawan a sm8550_domains; lamma es la misma familia).

### F3 — P0 · DT: arrancar el ADSP (+ alinear memoria con el vendor)
Mínimo:
```diff
--- a/arch/arm64/boot/dts/qcom/xiaomi-uke.dts
+++ b/arch/arm64/boot/dts/qcom/xiaomi-uke.dts
@@ (junto a los otros &status)
+/* ADSP: PMIC_GLINK/battmgr/UCSI/altmode (carga) + fastrpc/audio. Vendor:
+ * remoteproc-adsp@03000000 status ok (dt-live). */
+&remoteproc_adsp {
+	status = "okay";
+};
```
Alineación recomendada con el DT vivo (mismo patchset o inmediatamente después):
- compatible → `qcom,cliffs-adsp-pas` (recurso `cliffs_adsp_resource` del fork: **sin
  proxy_pd_names lcx/lmx** y `auto_boot=false`, tal como se validó) y reg → `0x03000000`
  (reg no lo usa el driver PAS — solo memory-region — pero alineamos con vendor).
- `adspslpi_mem` size 0x3200000 → **0x4500000** y `q6_adsp_dtb_mem` → **`@a1900000`**
  (valores exactos del vivo: `adspslpi_region@9d400000`/0x4500000 y
  `q6_adsp_dtb_region@a1900000`/0x80000; caben: hasta `wlan_msa@a6400000` hay libre).
  El tamaño actual 50 MB < 69 MB vendor: riesgo de no caber el fw+slpi.
Riesgo: el arranque del ADSP es manual (`echo start > state`, auto_boot=false) — no rompe el
boot si falla. Estado esperado: `/sys/class/remoteproc/remoteproc*/name = 6800000.remoteproc`
y `state=running`; PDR charger_pd UP.

### F4 — P1 · rootfs: unidad systemd de arranque ADSP + fw
- `/lib/firmware/qcom/`: `adsp.mdt/adsp.bXX…` + `adsp_dtb.mdt` (fuente: efs backup, ledger
  #4622; verificar que el rootfs v7 actual los lleva — si no, copiar antes del próximo flash).
- Servicio (ya existe como hito en el repo `bin/uke-adsp-load-tablet.sh`): orden
  `qcom_pd_mapper → qcom_q6v5_pas → qcom_glink_smem → qrtr_smd → pmic_glink → qcom_battmgr`
  y luego `echo start > /sys/class/remoteproc/remoteprocN/state`. Confirmar enabled en el
  rootfs Arch.
Riesgo: si arranca antes del pd-mapper, el PDR falla la primera vez (reintentos del ADSP);
mantener el orden.

### F5 — P1 · DT: enrutar SuperSpeed (y dejar DP listo)
```diff
@@ xiaomi-uke.dts, pmic-glink connector@0
 				port@1 {
 					reg = <1>;
 					pmic_glink_ss_in: endpoint {
-						remote-endpoint = <0>;
+						remote-endpoint = <&usb_dp_qmpphy_out>;
 					};
 				};
@@ (nuevo override, como en sm8550-qrd)
+&usb_dp_qmpphy_out {
+	remote-endpoint = <&pmic_glink_ss_in>;
+};
```
Con esto USB3 SS enumerable (y `usb_dp_qmpphy_dp_in` queda para DP-altmode v2 con el mux
SBU — `TYPEC_MUX_WCD939X_USBSS=m` ya está). Probar orientación del cable ambas caras; si
alguna falla, revisar `orientation-gpios <&tlmm 122>` contra el DTBO vendor.
Riesgo: bajo; si el QMP combo no arranca en SS, se puede volver a `<0>` sin afectar HS.

### F6 — P2 · DT/thermal: NTCs de piel (vadc + adc-tm)
Portar del vivo el `vadc@9000` de pmk8550 + canales de los NTC (`xo-therm`, `quiet_therm`,
`charger_therm0`, `conn_therm`, `cpu_therm`, `flash_therm`…) + `adc-tm5` con sus zonas
(`QCOM_SPMI_ADC5=m`/`ADC_TM5=m` ya activos). Sin esto el port no ve temperatura de chasis y
la mitigación de carga por piel no existe (el vendor usa esas zonas en thermal*.conf).
Riesgo: mapeo de canales ADC — copiar los `reg`/`qcom,hw-settle-time` del DT vivo.

### F7 — P3 · vibrador (opcional)
Driver propio `qcom,qpnp-vibrator-ldo` (SPMI pm7550ba @0xdf00, 3.0 V, overdrive off) o
port del downstream; nodo ya conocido. Haptics only.

### Notas de vigilancia
- **RIESGO térmico v1**: sin skin-therm ni cdev «battery» (mainline battmgr no registra cdev),
  la mitigación por piel depende solo del firmware del ADSP (temp de celda). Aceptar en v1;
  F6 reduce el hueco.
- `CONFIG_QCOM_LMH=m` inofensivo (no hay nodo ni en vendor ni en port) — no invertir tiempo.
- Carga en fastboot/EDL NO depende de nada de esto (ABL/EDL cargan sin OS): los umbrales
  battery-soc-ok 3500 mV del #521 siguen mandando para flashear.
- La batería nunca se ha validado arrancando el port con ADSP (hecho del enunciado): la primera
  prueba tras F1–F4 debe ser con cable puesto y vigilar `/sys/class/power_supply/battery/status`
  y `current_now` (convención: uevent negativo = cargando, como el vivo −103.274).

### Fuente de cada afirmación
Vivo: `extracted-full/03-battery/{dmesg-battery,power_supply/battery,qcom-battery/attrs,
dumpsys-battery,regulator_summary}.txt` · `04-thermal/{zones/*,cooling/*,dmesg-thermal}.txt` ·
`13-usb/{dumpsys-usb-head200,dt-usb,dmesg-usb}.txt` · `16-fixup/{udc-a600000.dwc3,
typec-port0,typec-port0-partner,paths}.txt` · `15-common/unbound-devices.txt` ·
`14-dt/dt-live.tar.gz` (nodos citados). Port: `~/gpu-work/build-uke/.config`,
`build-uke/arch/arm64/boot/dts/qcom/xiaomi-uke.dtb` (decompilado), 
`~/gpu-work/palawan-linux` (`xiaomi-uke.dts`, `palawan.dtsi`, `pm7550ba.dtsi`, `pmk8550.dtsi`,
`drivers/soc/qcom/{pmic_glink,qcom_pd_mapper}.c`, `drivers/power/supply/{Kconfig,qcom_battmgr}.c`,
`drivers/remoteproc/qcom_q6v5_pas.c`, `drivers/usb/dwc3/dwc3-qcom.c`). Historia:
`FLASH-LEDGER.md` #4156/#4376/#4622/#4820-4835/#521/#527.
