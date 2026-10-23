# EVIDENCIA-PANTALLA-28sep — cadena de display del uke (DATO vivo + reconstrucción verificada)

> **SG-EVIDENCIA**, 28-sep-2026 ~18:00 CEST. Encargo: recoger evidencia viva de la cadena de display
> de la tablet y consolidarla. **Cero escrituras en la tablet** (solo lectura por SSH). Nada de
> `/dev/ttyACM0` (hay captura única corriendo). Nada de `~/gpu-work` salvo lectura.
>
> ## ⚠️ AVISO DE ACCESO — el enlace USB se cayó a mitad del trabajo
> Mientras se preparaba la recogida, el **USB de la tablet desapareció del PC a las 17:43:46**:
> `usb usb3-port3: disabled by hub (EMI?), re-enabling...` + `USB disconnect, device number 42` +
> `cdc_ncm ... unregister` (`usb-caida-1743.txt`). Desde entonces **no ha vuelto a enumerar**
> (comprobado cada 10 s hasta las 18:00; sin `lsusb` Xiaomi, sin `/dev/ttyACM*`, sin
> `enp0s20f0u3`, `ping 192.168.42.129` sin respuesta). El último byte de consola capturado es de
> **17:43:25** (mtime del log).
>
> **Por eso**: todo lo que exige SSH **no se pudo leer en vivo** en esta pasada. Lo que sigue está
> construido con (a) la **consola ACM capturada** (log del PC, no es dmesg), y (b) una
> **reconstrucción del DT vivo** a partir de los artefactos EXACTOS que están en los slots — cadena
> de verificación en §2. Está etiquetado en todo momento:
> **[DATO-vivo-consola]**, **[DATO-offline]**, **[RECONSTRUCCIÓN]**, **[INFERENCIA]**,
> **[NO VERIFICADO]**.
>
> Los comandos exactos para completar la parte viva en cuanto el USB vuelva están en §11
> (y en el script listo `/tmp/uke-recolecta.sh`).

---

## 1. Qué se pudo y qué no

| Encargo | Estado |
|---|---|
| 1. DT vivo (`/proc/device-tree`) | ❌ bloqueado (SSH caído). Sustituido por **[RECONSTRUCCIÓN] verificada** del DT (base vendor + dtbo s238) — §3 y §9 |
| 2. Bindings (`driver` symlinks, `devices_deferred`, `iommu_groups`, `lsmod`) | ❌ bloqueado. Parcial **[DATO-vivo-consola]** de los probes/errores de dmesg impresos en consola (§5) + **[DATO-offline]** de las tablas de match del kernel (§4) |
| 3. dmesg del boot actual | ❌ bloqueado. Se guarda la **consola del último boot** (`consola-ultimo-boot-28sep.txt`) — **NO es dmesg**: hay `[missed 18746 bytes]` y orden mezclado en fronteras de boot |
| 4. Config del kernel | ✅ por la vía alternativa documentada: `.config` de `~/gpu-work/ramaa/s10/build-s122` **verificado como el del kernel en marcha** (§2.3) |
| 5. Backlight | ❌ bloqueado (solo el DATO de consola: el device existe y systemd falla al usarlo) |
| 6. cmdline / qbootctl / batería | cmdline ✅ **[DATO-vivo-consola]** (línea del boot actual). Slots y batería ❌ bloqueados |

---

## 2. Cadena de verificación (por qué la reconstrucción ES el DT vivo)

### 2.1 El dtbo que está en `dtbo_b` es el s238 pre-registrado [DATO-offline]
```
sha256sum build/bootimg/s238-boot-dtbo-dedup-gpio.img
bdb361dff87de52dd7d4581c7f4007abdaf98ac145d47658ef2a29bc458f0022
```
Coincide con el sha pre-registrado en `build/gates/s238-GATES.log` (última línea). El payload
extraído con `build/bootimg/dtbo-extract.py` da `payload_bytes 607470`,
`payload_sha256 5be4cdf641bc4cc14df9490faa771b1e40aaef730421563146515486c20c60bf`.

### 2.2 El DTB base es el primero del `vendor_boot` stock [DATO-offline]
`~/uke-backups/vendor_boot-stock.img` (sha `3ee6d4ac…`, el stock que
`docs/historia/ESTADO-VIVO.md`/`NOTAS-OMARCHY.md` dan por presente en el slot b sin tocar) contiene en su sección
`dtb` (offset `0x207b000`) CUATRO FDT concatenados. El primero (475 426 B, *"Qualcomm
Technologies, Inc. Cliffs SoC"*, `qcom,cliffs`, `qcom,msm-id = <0x266 0x10000>`) es **byte a byte
igual** a `~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img` (comparación en Python → `True`;
sha256 de ambos `3f973c78f7dc6a66f1acea363be27774c51ff174fbf71117ebe74c385547562e`).
Los otros tres FDT del vendor_boot son cliffs7 (0x278), cliffs7p (0x283) y cliffsp (0x282) — no son
el nuestro.

### 2.3 El kernel en marcha y su config [DATO-offline]
De `boot-s244-bounce.img` (la imagen de `boot_b`, per ESTADO-VIVO): el kernel va gzip; al
descomprimir, `sha256 = 156910550c0028d701bc6e9b97fe0f164daa817a4234deebfcfe593a62b266dc`, que es
**idéntico** a `~/gpu-work/ramaa/s10/build-s122/arch/arm64/boot/Image`, y las cadenas del binario
dicen `Linux version 7.2.0-rc2-palawan+ … #82 SMP PREEMPT Sat Sep 26 17:01:40 CEST 2026` — el mismo
banner del último boot de consola. El `.config` de `build-s122` (`CONFIG_LOCALVERSION="-palawan"`,
`# Linux/arm64 7.2.0-rc2`) es por tanto **el config del kernel en marcha** (guardado en
`config-kernel.txt`). El árbol fuente que lo construyó es `~/gpu-work/palawan-linux` (sus tablas de
match explican los probes, §4).

### 2.4 Reconstrucción [RECONSTRUCCIÓN]
`fdtoverlay -i base-dtb.img -o merged.dtb /tmp/s238.dtbo` → rc=0; `dtc` → 34 050 líneas de DTS
(el gate G1 de s238 dice 34 051; diferencia de conteo). El resultado está en
`dt-reconstruido/dt-fusionado-s238.dts` y los nodos clave extraídos en `dt-nodos-clave.txt`.
**Salvedad**: esto es la fusión fdtc/`fdtoverlay` (= semántica ABL) de los artefactos exactos; el
dump del `/proc/device-tree` vivo queda pendiente por el USB. **[NO VERIFICADO]** contra el árbol
vivo.

---

## 3. La cadena de display en el DT (fusión base + s238)

Convención: los nodos de **forma mainline** (los que el kernel palawan sí conoce) están bajo
`/soc/display-subsystem@ae00000/…`; los nodos **vendor** siguen presentes al nivel `/soc/…` y no
tienen driver en este kernel. Phandles tal como quedan en la fusión (→ §9 tabla).

### 3.1 SMMU de aplicaciones (EL muro)

```
/soc/apps-smmu@15000000                       [RECONSTRUCCIÓN · base DTB]
  compatible = "qcom,qsmmu-v500";             ← ÚNICA entrada
  reg = <0x15000000 0x100000 0x151fe000 0x40>;  reg-names = "base","tcu-base"
  #iommu-cells = <0x02>;  #global-interrupts = <0x01>;
  qcom,use-3-lvl-tables;  qcom,handoff-smrs = <0x1c00 0x02>;
  status = "ok";  phandle = <0x129>;
  hijos (8): anoc_1_qtb@16f1000, anoc_2_qtb@171a000, cam_hf_qtb@14d2000,
             nsp_qtb@7d3000, lpass_qtb@7b3000, pcie_qtb@16cd000,
             sf_qtb@1451000, mdp_hf_qtb@14d0000
             compatible = "qcom,qsmmuv500-tbu", "qcom,qtb500";
             reg = <base 0x1000, debugchain-base 0x1000>; qcom,stream-id-range = <OFF 0x400>;
```
**DATO clave**: el nodo vivo **ya tiene la forma vendor** (2 `reg` + hijos TBU `qsmmuv500-tbu`) —
no es ahí donde está el hueco. Lo que hace que no bindee es el **compatible**: `arm-smmu.c`
(`arm_smmu_of_match`, tabla en la línea 1957; el bloque `qcom,qsmmu-v500` está bajo
`#ifdef CONFIG_ARM_SMMU_LEGACY_DT_BINDINGS`, líneas 114-205) no lista `qcom,qsmmu-v500` con el
config actual, y `CONFIG_ARM_SMMU_LEGACY_DT_BINDINGS` **no está puesto**. La tabla de quirk
`qcom_smmu_impl_of_match` (`arm-smmu-qcom.c:774-802`) tampoco tiene entrada cliffs/palawan/sm8650.
→ **[INFERENCIA]** A′ no necesita “repuntar la forma”: basta con que el nodo lleve un compatible que
mainline acepte (`qcom,smmu-500` → `qcom_smmu_500_impl0_data`, o `arm,mmu-500`), como ya hace el
kgsl-smmu. Validez de esa vía: **[NO VERIFICADO]** (el plan A′ es de otro subagente).

### 3.2 SMMU de la GPU (sí es el que bindea)

```
/soc/kgsl-smmu@3da0000                        [RECONSTRUCCIÓN · base DTB]
  compatible = "qcom,palawan-smmu-500", "qcom,adreno-smmu", "qcom,smmu-500", "arm,mmu-500";
  reg = <0x3da0000 0x40000 0x3de6000 0x40>; reg-names = "base","tcu-base";
  #iommu-cells = <2>; #global-interrupts = <1>; status = "ok"; phandle = <0x1c1>;
  vdd-supply = <0x1bd>; qcom,actlr = <0x00 0x3ff 0x32b>;
  hijo: gpu_qtb@3de8000 (qcom,qsmmuv500-tbu)
```
Bindea porque `arm,mmu-500` está en `arm_smmu_of_match` (DATO-offline) y la consola lo confirma
**[DATO-vivo-consola]**: `arm-smmu 3da0000.kgsl-smmu: probing hardware configuration… SMMUv2 with:
stage 1 translation / coherent table walk / stream matching with 24 register groups / 22 context
banks (0 stage-2 only) / Supported page sizes: 0x61311000 / Stage-1: 48-bit VA -> 36-bit IPA`
(p. ej. log consola líneas 281191-281196; en el último boot 332288-332296).

### 3.3 MDSS / DPU

```
/soc/display-subsystem@ae00000  (mdss_ml)     [RECONSTRUCCIÓN · overlay s229/s238]
  compatible = "qcom,palawan-mdss";  reg = <0xae00000 0x1000>;  status = "okay";
  iommus = <0x129 0x1c00 0x02>;      power-domains = <0x154 0>;  resets = <0x154 0>;
  clocks = <0x154 2 0x16e 0x15 0x154 0x3d>;  interrupts = <0 0x53 4>;  phandle = <0x6f7>;
  → driver: msm_mdss matchea "qcom,palawan-mdss" (msm_mdss.c:534). [DATO-offline]

/soc/display-subsystem@ae00000/display-controller@ae01000 (mdss_mdp_ml)
  compatible = "qcom,palawan-dpu";   reg = <0xae01000 0x8f000 0xaeb0000 0x3000>;
  clock-names = "nrt_bus","iface","lut","core","vsync";  interrupts-extended = <0x6f7 0>;
  SIN propiedad `iommus` propia → el IOMMU lo toma del padre mdss (msm_kms.c:190-199).
  → driver: dpu_kms.c:1514 tiene "qcom,palawan-dpu". [DATO-offline]
```
**[DATO-vivo-consola]** (boots de hoy): `msm-mdss ae00000.display-subsystem: deferred probe
timeout, ignoring dependency` (13.9 s) y `msm_dpu ae01000.display-controller:
[drm:msm_drm_kms_init] *ERROR* kms hw init failed: -19` (16.4-16.5 s). En boots anteriores del mismo
log consta la variante textual `[drm] no IOMMU, bailing out` (líneas 137547, 147293, 156609,
166177, 175405). Mecanismo exacto en el árbol: `msm_kms_init_vm()` (msm_kms.c:180-199) exige que el
device del DPU **o** el del MDSS estén `device_iommu_mapped()`; si no, `-ENODEV` → el −19.

### 3.4 DSI y PHYs (forma mainline)

```
/soc/display-subsystem@ae00000/dsi@ae94000   (mdss_dsi0_ml, master)
  compatible = "qcom,palawan-dsi-ctrl", "qcom,mdss-dsi-ctrl";
  reg = <0xae94000 0x400>; status = "okay"; phandle = <0x708>;
  phys = <0x6f5>; phy-names = "dsi";  qcom,dual-dsi-mode; qcom,master-dsi; qcom,sync-dual-dsi;
  vdda-supply = <0x14e> (pmxr2230 L4);  clocks = <0x154 0x04 0x154 0x07 0x154 0x42 0x154 0x38
                                             0x154 0x02 0x16e 0x15>;
  interrupts-extended = <0x6f7 0x04>;  hijo: panel@0 (§3.5)

/soc/display-subsystem@ae00000/dsi@ae96000   (mdss_dsi1_ml)
  igual forma; phandle = <0x709>; phys = <0x6f6>; vdda-supply = <0x14e>;
  interrupts-extended = <0x6f7 0x05>

/soc/display-subsystem@ae00000/phy@ae95000   (mdss_dsi0_phy_ml)
  compatible = "qcom,palawan-dsi-phy-4nm", "qcom,sm8650-dsi-phy-4nm";
  reg = <0xae95000 0x200 0xae95200 0x280 0xae95500 0x400>;
  reg-names = "dsi_phy","dsi_phy_lane","dsi_pll";  vdds-supply = <0x14d> (pmxr2230 L2);
  clocks = <0x154 0x02 0x16c 0x00>; clock-names = "iface","ref";  status = "okay";
  #clock-cells = <1>; #phy-cells = <0>;  phandle = <0x6f5>

/soc/display-subsystem@ae00000/phy@ae97000   (mdss_dsi1_phy_ml)
  idéntico salvo regs 0xae97000/0xae97200/0xae97500; phandle = <0x6f6>
```
**[DATO-offline]** el compatible mainline del PHY **ya está traducido**: `dsi_phy_dt_match`
(dsi_phy.c:578) contiene `"qcom,sm8650-dsi-phy-4nm" → dsi_phy_4nm_8650_cfgs`; y el driver usa
exactamente los 3 `reg-names` que tiene el nodo (dsi_phy.c:653 `dsi_pll`, :659 `dsi_phy_lane`).
**[DATO-vivo-consola]** aun así, en los boots de hoy: `msm_dsi ae96000.dsi: [drm:dsi_dev_probe]
*ERROR* dsi_get_phy: phy driver is not ready` (13.94 s) — que en el código significa que el
platform_device del PHY existe pero **no tiene driver bindeado** (dsi.c:25-53: `phy_pdev` sin
drvdata o inexistente → `-EPROBE_DEFER`). Para el DSI0 no hay mensaje de error y **el panel sí llega
a existir** como `mipi-dsi ae94000.dsi.0` → **[INFERENCIA]** phy@ae95000 sí quedó listo y
phy@ae97000 no (asimétrico); la causa del defer del phy1 **[NO VERIFICADO]** (necesita `driver`
symlinks + dmesg vivos).

### 3.5 Panel (el nodo mainline que el driver del proyecto espera)

```
/soc/display-subsystem@ae00000/dsi@ae94000/panel@0   [RECONSTRUCCIÓN · overlay]
  compatible = "xiaomi,uke-o82-4202-0b";  reg = <0x00>;  status = "ok";
  vddil8b-supply = <0x14f>;   (L8B / pmxr2230-l8)
  vsp-supply = <0x6fe>;       (uke-regulator-display-vsp)
  vsn-supply = <0x6ff>;       (uke-regulator-display-vsn)
  reset-gpios = <0x16b 0x02 0x01>;    ← tlmm gpio2, ACTIVE_LOW
  pinctrl-names = "default","sleep";  pinctrl-0 = <0x700>; pinctrl-1 = <0x701>;
  ports: panel_in_0 (0x6fd) ↔ mdss_dsi0_out (0x702);  panel_in_1 (0x705) ↔ mdss_dsi1_out (0x703)
  NO tiene propiedad `backlight` ni nodos `backlight` propios.  phandle propio: no lo tiene.
```
**[DATO-offline]** `panel-xiaomi-o82-dualdsi.c:663-665` matchea exactamente
`"xiaomi,uke-o82-4202-0b"`, y el config lo tiene `=y` (§6).
**[DATO-vivo-consola]** el probe del panel CORRE y difiere:
`mipi-dsi ae94000.dsi.0: deferred probe pending: panel-xiaomi-o82-dualdsi: failed to get reset gpio`
(13.94 s; p. ej. línea 281244 del log). El driver hace `devm_gpiod_get(dev, "reset",
GPIOD_OUT_HIGH)` (panel-xiaomi-o82-dualdsi.c:591) y `dev_err_probe` registra el motivo.

### 3.6 Reguladores del panel y L8B

```
/soc/uke-regulator-display-vsp   compatible="regulator-fixed"; regulator-name="uke_panel_vsp";
    gpio = <0x16b 0x4a 0x00> (tlmm gpio74, activo alto); regulator-boot-on;
    enable-ramp-delay=0xe9; min=max=0x588040 (5.8 V); phandle = <0x6fe>
/soc/uke-regulator-display-vsn   ídem con gpio = <0x16b 0x4b 0x00> (gpio75); phandle = <0x6ff>
/soc/…/rpmh-regulator-ldob8/…/L8B: regulator-pmxr2230-l8
    regulator-name="pmxr2230_l8"; min = max = 0; qcom,init-voltage = 0x1cfde0;
    qcom,proxy-consumer-enable; qcom,set = 0x03; phandle = <0x14f>
```
Los duplicados vendor (`display_gpio_regulator_vsp/vsn`) quedaron `status = "disabled"` por s238
(los gates G4/G6 de `s238-GATES.log` lo verifican). **[DATO-offline]** re-verificado en la fusión:
no aparecen con consumidores reales de gpio74/75 (2 referencias cada uno: la del `uke-regulator` y
la del nodo disabled).

### 3.7 Otros nodos pedidos

| Nodo | Datos exactos (fusión) |
|---|---|
| `watchdog@17c10000` | `compatible = "qcom,kpss-wdt"; reg = <0x00 0x17c10000 0x00 0x1000>; clocks = <0x16d>` (sleep_clk, fixed-clock 32 kHz). Sin `status` (⇒ enabled). Sin `iommus`. La entrada lo añade el overlay (fragment del s229). `qcom-wdt.c:372` matchea `qcom,kpss-wdt` [DATO-offline]. `/dev/watchdog` en vivo: **[NO VERIFICADO]** (el plan dice que hoy no existe). |
| `tlmm: pinctrl@f000000` | `compatible = "qcom,cliffs-pinctrl"; reg = <0xf000000 0x1000000>; gpio-controller; #gpio-cells = <2>; #interrupt-cells = <2>; phandle = <0x16b>`. Hijos del panel: `uke-pmx-sde/uke-dsi-reset-active` (0x700) y `…-suspend` (0x701). |
| `dispcc: clock-controller@af00000` | `compatible = "qcom,palawan-dispcc"`; `#clock-cells=<1>`, `#reset-cells=<1>`, reg 0xaf00000 0x20000; vdd_mm=0x149 (pm_v8_s6_level), vdd_mxa=0x14c (pm_v8_s8_level); clocks incluyen los PHYs (0x6f5/0x6f6). El driver que se liga es **disp_cc_sm8550** (traza de consola: `disp_cc_sm8550_probe+0x144/0x1b0`) y su probe **avisa**: `disp_cc_mdss_mdp_clk_src: rcg didn't update its configuration` + `WARNING: drivers/clk/qcom/clk-rcg2.c:136 update_config+0xdc/0xf8` [DATO-vivo-consola]. |
| `gpu@3d00000` (mainline) | El overlay reescribe el nodo vendor `qcom,kgsl-3d0@3d00000` (fragment@1450 de `s229.dts`): `compatible = "qcom,adreno-43030b00","qcom,adreno"`; `iommus = <0x1c1 0x00 0x00>`; `qcom,gmu = <0x482>`; `status="okay"`; **`clocks;` y `clock-names;` quedan VACÍOS** (propiedades sin valor, adrede) — ojo para el camino GPU. Consola: `adreno 3d00000.qcom,kgsl-3d0: supply vdd not found, using dummy regulator` (+vddcx) [DATO-vivo-consola]. |
| Vendor MDP | `/soc/qcom,mdss_mdp@ae00000`: `compatible = "qcom,sde-kms"`; `qti,smmu-proxy-cb-id = <1>`; `connectors = <…>`; **sin `status`** (enabled). Sin driver en este kernel. |
| Vendor DSI/PHY | `qcom,mdss_dsi_ctrl0@ae94000` y `@ae96000` → `compatible = "qcom,dsi-ctrl-hw-v2.8"`; `qcom,mdss_dsi_phy0@ae95500` y `…phy1@ae97500` → `compatible = "qcom,dsi-phy-v5.2"`. Siguen **enabled** en el DT ([[NO VERIFICADO]] el estado `driver` en vivo, pero no existe driver mainline para ninguno). |
| Paneles vendor | Bajo el MDP vendor: `qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid` (línea 22410 del dts) y `qcom,mdss_dsi_o82_36_02_0a_dualdsi_dsc_vid` (22179): cada uno con `qcom,platform-reset-gpio = <0x16b 0x02 0x00>` (gpio2) y timings; sin `status` (enabled). Son los que el cmdline del vendor selecciona (`msm_drm.dsi_display0=…o82_42_02_0b…`). |

---

## 4. Qué bindea y qué no (estado del arte)

**Por el árbol del kernel (tablas de match) [DATO-offline]:**

| Dispositivo | Compatible vivo | Driver mainline que lo matchea | ¿Bindeo? |
|---|---|---|---|
| apps-smmu@15000000 | `qcom,qsmmu-v500` | ninguno (arm-smmu: no listado; LEGACY_DT_BINDINGS **no** puesto) | **NO** |
| kgsl-smmu@3da0000 | `…, "arm,mmu-500"` | arm-smmu (`arm_mmu500`) | SÍ |
| display-subsystem@ae00000 | `qcom,palawan-mdss` | msm_mdss (msm_mdss.c:534) | SÍ (con defer previo) |
| display-controller@ae01000 | `qcom,palawan-dpu` | dpu_kms.c:1514 | SÍ matchea; falla en `hw_init` por IOMMU |
| dsi@ae94000 / @ae96000 | `…, "qcom,mdss-dsi-ctrl"` | msm_dsi (dsi.c:195) | DSI0 aparentemente sí; DSI1 defiere por phy |
| phy@ae95000 / phy@ae97000 | `…, "qcom,sm8650-dsi-phy-4nm"` | dsi_phy (dsi_phy.c:578) | phy0 sí (inferido), phy1 no (dato consola) |
| panel@0 | `xiaomi,uke-o82-4202-0b` | panel-xiaomi-o82-dualdsi (línea 664) | matchea; **defiere por reset gpio** |
| clock-controller@af00000 | `qcom,palawan-dispcc` | disp_cc_sm8550 (por la traza) | Sí, con WARN de RCG |
| watchdog@17c10000 | `qcom,kpss-wdt` | qcom-wdt (qcom-wdt.c:372) | `driver` vivo **[NO VERIFICADO]** |
| gpu@3d00000 | `qcom,adreno-43030b00`,`qcom,adreno` | adreno (msm) | probe corre (dummy regulators) |
| apps-smmu (vendor TBUs) | `qcom,qsmmuv500-tbu` | ninguno | N/A |

**Lo que la consola confirma (últimos boots de hoy) [DATO-vivo-consola]** — misma secuencia en los
boots de las líneas 255531, 269011, 281105, 315534 del log:
1. `0.31 s` WARN `clk-rcg2.c:136` + `disp_cc_mdss_mdp_clk_src: rcg didn't update its configuration`.
2. `0.32 s` `arm-smmu 3da0000.kgsl-smmu` probe OK (SMMUv2, 24 grupos, 22 ctx banks).
3. `13.91 s` `msm-mdss ae00000.display-subsystem: deferred probe timeout, ignoring dependency`.
4. `13.93 s` `clk: couldn't set disp_cc_mdss_vsync_clk clk rate to 19200000 (-22), current rate: 38400000`.
5. `13.94 s` `msm_dsi ae96000.dsi: dsi_get_phy: phy driver is not ready`.
6. `13.94 s` `mipi-dsi ae94000.dsi.0: deferred probe pending: panel-xiaomi-o82-dualdsi: failed to get reset gpio`.
7. `16.3 s` `adreno …: supply vdd/vddcx not found, using dummy regulator`.
8. `16.4 s` `msm_dpu ae01000.display-controller: [drm:msm_drm_kms_init] *ERROR* kms hw init failed: -19`.
9. Usuarios: `systemd-backlight: Failed to start Load/Save Screen Brightness of backlight:ae94000.dsi.0`
   (el device de backlight existe; el servicio falla) — repetido en cada boot.

La recogida de `driver` symlinks / `devices_deferred` / `iommu_groups` / `lsmod` en vivo queda
pendiente (§11).

---

## 5. dmesg / consola del boot actual

- **No hay dmesg vivo**: SSH caído. Lo que hay es la **consola ACM** (§1): guardada como
  `consola-ultimo-boot-28sep.txt` (segmento desde el último `Linux version` del log hasta el final;
  12 997 líneas) — contiene mucho spam de `X9UFS-CLK` y `[missed 18746 bytes]` del capturador, así
  que sirve para mensajes concretos, **no** como log ordenado.
- **[AVISO]** la atribución de las primeras líneas de cada frontera de boot del log es dudosa:
  el gadget ACM no existe en los primeros segundos del boot de la tablet (lo levanta el init), de
  modo que las líneas con uptime 0,0-20 s que aparecen justo tras una frontera pueden ser de un boot
  anterior entregadas al PC al reabrir el tty (el capturador reabre `/dev/ttyACM0` en cada vuelta).
  **[NO VERIFICADO]** por tanto a qué boot pertenece cada bloque; para eso hace falta el dmesg vivo.
- **[DATO-vivo-consola]** cmdline del boot actual: en el log aparece **partida en dos líneas
  consecutivas** (líneas 331762 y 331763 del log; ambas guardadas en `consola-cmdline-live.txt`),
  lo que es artefacto del capturador y no dos prints distintos:
  ```
  [0.000000] Kernel command line: loglevel=6 kpti=0 log_buf_len=256K swiotlb=noforce loop.max_part=7
    pcie_ports=compat irqaffinity=0-2 cpufreq.default_governor=performance sysctl.kernel.sched_pelt_multiplier=4
    kasan=off cgroup.memory=nokmem,nosocket disable_dma32=on kernel.panic_on_rcu_stall=1 fw_devlink.strict=1
    service_locator.enable=1 rcupdate.rcu_expedited=1 rcu_nocbs=0-7 no-steal-acc printk.console_no_auto_verbose=0
    can.stats_timer=0 ftrace_dump_on_oops firmware_class.path=… pci-msm-drv.pcie_sm_regs=0x1D07000,0x1040,0x1048,0x3000,0x1
    video=vfb:640x400,bpp=32,memsize=3072000 swinfo.fingerprint=uke:14/OS3.0.303.0.WOZEUXM:user
    mtdoops.fingerprint=… bootconfig mem=2048M rdinit=/ukeinit panic=10 memmap=0x1A12800$0xE3940000 console=tty0
    fbcon=map:0 hung_task_timeout_secs=20 hung_task_panic=1 watchdog_thresh=10 \
  [0.000000] Kernel command line: console=ttyGS0,115200 fw_devlink=permissive clk_ignore_unused pd_ignore_unused
    arm-smmu.disable_bypass=0 bootinfo.pureason=0x80011 bootinfo.pdreason=0x2 msm_sharedmem.cma_already_panic=0
    debug_ext.initrd_size=35510 spidev.bufsiz=16384 hwid.hwid_value=1638400 hwid.project=11 hwid.build_adc=51246
    hwid.project_adc=90 msm_drm.dsi_display0=qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid: msm_drm.oled_wp=99807e
    msm_drm.debugpolicy=0x20 msm_drm.build_id=c3 rootwait ro init=/init silent_boot.mode=nonsilent log_buf_len=2M
    loglevel=6 console=ttynull block2mtd.block2mtd=/dev/block/by-name/oops,2097152 mtdoops… boot_index=5403
  ```
  (el `\` final de la primera mitad es artefacto del log). La concatenación de ambas mitades
  reproduce `build/bootimg/cmdline-orig.txt` salvo `bootinfo.*`/`hwid.*`/`boot_index`, que los añade
  el bootloader en cada arranque (1403→5403). **No** lleva `separate_gpu_kms` (coherente con el
  plan), pero **sí** `video=vfb:640x400,bpp=32,memsize=3072000`, `fbcon=map:0` y `console=tty0`.
- Traza del WARN de dispcc en el boot actual: `boot-console-full.txt` líneas 590-821
  (`WARNING: drivers/clk/qcom/clk-rcg2.c:136 at update_config+0xdc/0xf8, CPU#7: swapper/0/1`).

---

## 6. Config del kernel (la del kernel en marcha, §2.3)

Extracto (`config-kernel-display.txt`; el completo en `config-kernel.txt`):

```
CONFIG_ARM_SMMU=y                    CONFIG_ARM_SMMU_QCOM=y
# CONFIG_ARM_SMMU_LEGACY_DT_BINDINGS is not set     ← por esto no matchea qcom,qsmmu-v500
CONFIG_ARM_SMMU_MMU_500_CPRE_ERRATA=y              CONFIG_ARM_SMMU_DISABLE_BYPASS_BY_DEFAULT=y
CONFIG_QCOM_IOMMU=y                  CONFIG_ARM_SMMU_V3=y
CONFIG_DRM_MSM=y                     CONFIG_DRM_MSM_KMS=y
CONFIG_DRM_MSM_DPU=y                 CONFIG_DRM_MSM_MDSS=y
CONFIG_DRM_MSM_DSI=y                 CONFIG_DRM_MSM_DSI_7NM_PHY=y   (aquí vive el 4nm)
CONFIG_DRM_MSM_KMS_FBDEV=y           CONFIG_DRM_FBDEV_EMULATION=y
CONFIG_DRM_PANEL=y                   CONFIG_DRM_PANEL_XIAOMI_O82_DUALDSI=y   ← el panel del proyecto
CONFIG_DRM_PANEL_NOVATEK_NT36672A=m  CONFIG_DRM_PANEL_NOVATEK_NT36672E=m
CONFIG_DRM_PANEL_NOVATEK_NT37801=m   CONFIG_DRM_PANEL_SIMPLE=m
CONFIG_PHY_QCOM_QMP_UFS=y            CONFIG_PHY_QCOM_QMP_USB=y   …
CONFIG_QCOM_WDT=y                    CONFIG_QCOM_COMMAND_DB=y    CONFIG_QCOM_SCM=y
```
Nota: no existe símbolo `panel-xiaomi`/`panel-o82` aparte; el del proyecto es
`CONFIG_DRM_PANEL_XIAOMI_O82_DUALDSI` (built-in en el kernel en marcha, **no** módulo).

---

## 7. Backlight

- **[NO VERIFICADO en esta pasada]** el contenido de `/sys/class/backlight/ae94000.dsi.0/` y el
  `readlink device` (SSH caído). Lo que sí dice la consola: el **device existe** (systemd intenta
  cargar/guardar su brillo y **falla** en cada boot: `Failed to start Load/Save Screen Brightness of
  backlight:ae94000.dsi.0`). El nombre `ae94000.dsi.0` corresponde al device mipi-dsi del panel
  (hijo de `ae94000.dsi`), así que **[INFERENCIA]** el backlight lo registró el driver del panel
  (o el subsistema DRM al crear el conector) — su `readlink device` lo confirmará en vivo.
- El plan (`docs/historia/PLAN-PANTALLA.md`) da por resuelto “nodo panel + backlight”; el binomio
  nodo-panel ✅ (existe y matchea driver) / backlight ⚠️ (existe pero systemd no puede usarlo)
  merece la comprobación viva de §11.

---

## 8. Slots y batería

- **[NO VERIFICADO]**: `qbootctl` y `voltage_now`. `docs/historia/ESTADO-VIVO.md` dice slot b = par bueno
  (`boot_b` s244-bounce, `dtbo_b` s238) y batería ~3399-3432 mV en el último ciclo; el encargo
  mismo reporta la tablet viva con SSH. No re-medido aquí (USB caído).
- El cmdline vivo (§5) sí se capturó y es coherente con slot b (s238: `dsi_display0` vendor y
  sin `separate_gpu_kms`).

---

## 9. Phandles vivos de referencia (fusión s238)

| phandle | Nodo | Para qué se usa |
|---|---|---|
| `0x129` | `/soc/apps-smmu@15000000` | `iommus = <0x129 0x1c00 0x02>` del MDSS (y ~58 nodos más) |
| `0x1c1` | `/soc/kgsl-smmu@3da0000` | `iommus = <0x1c1 0x00 0x00>` de la GPU |
| `0x16b` | `/soc/pinctrl@f000000` (tlmm) | reset del panel (`0x02 0x01`), vsp/vsn (gpio74/75 = `0x4a`/`0x4b`) |
| `0x14f` | `…/L8B: regulator-pmxr2230-l8` | `vddil8b-supply` del panel |
| `0x6fe` / `0x6ff` | `uke-regulator-display-vsp` / `-vsn` | `vsp-supply` / `vsn-supply` del panel |
| `0x6f5` / `0x6f6` | `phy@ae95000` / `phy@ae97000` | `phys` de DSI0/DSI1 y clocks del dispcc |
| `0x6f7` | `display-subsystem@ae00000` (mdss) | `interrupts-extended` de dpu/dsi |
| `0x707` / `0x708` / `0x709` | `display-controller@ae01000` / `dsi@ae94000` / `dsi@ae96000` | caminos mainline |
| `0x154` | `dispcc clock-controller@af00000` | clocks/resets/power-domains de mdss/dsi/dpu |
| `0x26a` | `gpu@3d00000` (adreno) | `qcom,gmu = <0x482>` apunta a la GMU |
| `0x14d` / `0x14e` | `pmxr2230_l2` (L2B) / `pmxr2230_l4` (L4B) | `vdds-supply` de los PHYs / `vdda-supply` de los DSI |
| `0x149` / `0x14c` | `pm_v8_s6_level` (mmcx.lvl) / `pm_v8_s8_level` (mx.lvl) | vdd_mm/vdd_mxa del dispcc |
| `0x16d` | `sleep_clk` (fixed-clock 32 kHz) | clock del watchdog |

---

## 10. Imprevistos (cosas que contradicen lo documentado)

1. **El driver del panel SÍ existe, está compilado y su probe corre** —
   `CONFIG_DRM_PANEL_XIAOMI_O82_DUALDSI=y` y
   `panel-xiaomi-o82-dualdsi: failed to get reset gpio` en consola. `docs/historia/PLAN-PANTALLA.md` lo describe
   como “mainline no tiene driver” (Hueco 3) y F1(b) manda “compilar `panel-xiaomi-o82-dualdsi.c`
   como módulo … nunca compilado ni probado”. **DATO**: ya está built-in y probando. (Aparte: hay
   una sesión construyendo un `.ko` en `/tmp/opencode/sg-panel` → posible duplicación módulo vs
   built-in; aviso para F1.)
2. **El “Hueco 2” (compatible del DSI PHY) ya está traducido en el dtbo**: los nodos
   `phy@ae95000/@ae97000` llevan `qcom,sm8650-dsi-phy-4nm` (matchea `dsi_phy_dt_match`). El
   `qcom,dsi-phy-v5.2` que el plan cita es el nodo **vendor**, que sigue en el DT pero **sin
   usuario** (el msm_dsi usa los nodos mainline). El error “phy driver is not ready” que se sigue
   viendo es de **DSI1** y huele a defer por dependencias del phy1, no a compatible.
3. **El nodo apps-smmu vivo YA tiene la forma vendor** (2 `reg` + 8 hijos `qsmmuv500-tbu`) en el
   DTB base. La afirmación del plan “vía no construida: A′ = repuntar el nodo con la FORMA vendor”
   describe algo que en el DT vivo ya está; lo que falta es **compatible** (o el flag de legacy
   bindings), y el postmortem de s251/#431 debería reescribirse en esos términos. **[INFERENCIA]**
4. **gpio2 (reset del panel) tiene 4 referencias en el DT fusionado**: `panel@0` (`reset-gpios`)
   + 3 instancias de `qcom,platform-reset-gpio` en DOS nodos vendor o82
   (`qcom,mdss_dsi_o82_36_02_0a_dualdsi_dsc_vid` línea 22240 del dts; y
   `qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid` líneas 22471 y 22681). El kernel palawan trae su
   mecanismo propio de GPIO compartido (`drivers/gpio/gpiolib-shared.c`): cuenta propiedades que
   acaban en `-gpio`/`-gpios` con 2 celdas y **sólo ignora nodos `disabled`** (línea ~132); con >1
   referencia marca el descriptor como shared (línea 539-565) y las peticiones pasan por un chip
   proxy. **Eso es exactamente lo que produce el `-EPROBE_DEFER` del panel** visto en consola. Los
   gates de s238 sólo cubrieron gpio74/75 (G6) — **gpio2 quedó fuera**.
   **[INFERENCIA]** (código + DT + mensaje de consola). Arreglo candidato: misma receta que s238
   (dejar UN consumidor: p.ej. vaciar `qcom,platform-reset-gpio` de los paneles vendor o
   deshabilitarlos). **Sin verificar en vivo.**
   **Matiz medido**: en los boots recientes el módulo del proxy **sí está cargado**
   (`Modules linked in: gpio_shared_proxy`, log líneas 185780/255832/269210) y aun así el panel
   seguía difiriendo por el reset gpio ⇒ o el proxy no llegó a enlazar con ese pin, o el defer
   tiene otra causa (orden de probes). Desambiguarlo exige `dmesg` + `/sys/kernel/debug/gpio`
   vivos (§11).
5. **El nodo GPU del overlay deja `clocks;` y `clock-names;` VACÍOS** (fragment@1450 de
   `s229.dts`, línea 15117) — DATO. Para el camino GPU (F1a) conviene saberlo.
6. **`disp_cc_mdss_mdp_clk_src: rcg didn't update its configuration`** en TODOS los boots
   (WARN en `clk-rcg2.c:136` desde `disp_cc_sm8550_probe`), y
   `clk: couldn't set disp_cc_mdss_vsync_clk clk rate to 19200000 (-22), current rate: 38400000`.
   No está en el plan: es un problema de **relojes del display** que puede morder cuando se
   desatasque el SMMU.
7. **El cmdline vivo lleva `video=vfb:640x400,bpp=32,memsize=3072000` y `fbcon=map:0`** además de
   `console=tty0` (DATO).
8. **La consola no es una fuente completa**: el capturador deja `[missed 18746 bytes]` y en las
   fronteras de boot mezcla líneas (2 lectores ACM entre 14:11-15:01, `REGLA-UN-SOLO-LECTOR.md`).
   Cualquier cronología fina de hoy debe dudarse.
9. `docs/historia/ESTADO-VIVO.md` dice que el dtbo_b actual es s238 y que es el “par bueno”; la fusión que he
   reconstruido **incluye el nodo vendor MDP/DSI/PHY y los paneles vendor o82 enabled** — es decir,
   el DT vivo arrastra el árbol de display vendor entero, aunque sin driver.

---

## 11. Pendiente para completar la evidencia (en cuanto vuelva el USB)

Script preparado y listo: **`/tmp/uke-recolecta.sh`** (solo lectura; usa `uke-ssh.sh`; no toca
`/dev/ttyACM0`). Comandos concretos:

```sh
cd ~/proyectos/omarchy-uke/build/gates
# 0) conectividad
./uke-ssh.sh -i
# 1) DT vivo completo (binario por base64; decodificar en el PC)
./uke-ssh.sh 'cd /proc/device-tree && tar -cf - . 2>/dev/null | gzip -1 | base64 -w0'
# 2) nombres exactos y nodos clave
./uke-ssh.sh 'ls /proc/device-tree/soc/ | grep -iE "smmu|display|mdss|dsi|dpu|pinctrl|watchdog|gpu|dispcc"'
./uke-ssh.sh 'for n in /proc/device-tree/soc/*smmu* /proc/device-tree/soc/*display* /proc/device-tree/soc/*dsi*; do echo "## $n"; od -An -tx1 $n/reg 2>/dev/null; cat $n/compatible 2>/dev/null | tr "\0" " "; echo; ls -l $n | head; done'
# 3) bindings
./uke-ssh.sh 'ls -l /sys/bus/platform/devices/*/driver 2>/dev/null | grep -iE "smmu|dpu|mdss|dsi|disp|gpu|panel|phy"'
./uke-ssh.sh 'cat /sys/kernel/debug/devices_deferred; ls /sys/kernel/iommu_groups/; for g in /sys/kernel/iommu_groups/*; do echo $g; ls $g/devices; done; lsmod'
# 4) dmesg + config
./uke-ssh.sh 'dmesg'                     # guardar entero
./uke-ssh.sh 'zcat /proc/config.gz | base64 -w0'   # si no existe, decirlo
# 5) backlight / cmdline / slots / batería
./uke-ssh.sh 'ls -la /sys/class/backlight/*/; cat /sys/class/backlight/*/max_brightness /sys/class/backlight/*/brightness /sys/class/backlight/*/bl_power; readlink /sys/class/backlight/ae94000.dsi.0/device'
./uke-ssh.sh 'cat /proc/cmdline; qbootctl -a; cat /sys/class/power_supply/qcom-battmgr-bat/voltage_now'
# 6) los 4 checks que desambiguan los imprevistos:
./uke-ssh.sh 'cat /sys/kernel/debug/gpio 2>/dev/null | grep -iE "shared|gpio-2 |gpio-74|gpio-75"'   # ¿gpio2 shared?
./uke-ssh.sh 'cat /sys/kernel/debug/gpio 2>/dev/null | head -40'                                    # proxy chip
./uke-ssh.sh 'ls /sys/bus/platform/drivers/ | grep -iE "dsi|phy|panel|adreno|smmu|mdss|dispcc"'
./uke-ssh.sh 'for d in $(ls -d /sys/bus/platform/devices/*dsi* /sys/bus/platform/devices/*phy* 2>/dev/null); do echo "$d -> $(readlink $d/driver 2>/dev/null || echo SIN-DRIVER)"; done'
```

**Checks mínimos para cerrar los huecos de este informe**: (a) `driver` symlink de
apps-smmu/kgsl-smmu/dsi/phy/panel/watchdog; (b) `devices_deferred` (¿sigue el panel por reset
gpio?); (c) `iommu_groups` (¿grupos del apps-smmu? ¿del kgsl?); (d) `dmesg` del boot actual
(¿phy1 y panel deferidos hoy?); (e) `readlink /sys/class/backlight/ae94000.dsi.0/device`;
(f) `/sys/kernel/debug/gpio` para ver si gpio2 (y 74/75) están marcados/shared y si hay chip proxy.

**Nota operativa**: yo no puedo re-enganchar el USB (no toco hardware). Cuando vuelva, el perfil
NetworkManager `uke-ncm` está configurado y la interfaz debería subir sola; el watcher que dejé
corriendo (hasta ~18:33) reintenta SSH cada 10 s.

---

## 12. Ficheros de evidencia (`build/evidencia/2026-09-28/`)

| Fichero | Qué es |
|---|---|
| `dt-reconstruido/dt-fusionado-s238.dts` / `.dtb` | DT RECONSTRUIDO (base vendor + dtbo s238), 34 050 líneas |
| `dt-reconstruido/dt-base-vendor.dts` | DTB base (primer FDT del vendor_boot stock) descompilado |
| `dt-reconstruido/overlay-s238.dts` | payload del dtbo_b s238 descompilado |
| `dt-nodos-clave.txt` | Extracción de los nodos clave con su contenido literal (apps-smmu, kgsl-smmu, mdss/dsi/panel/mdp, reguladores, L8B, watchdog, gpu, tlmm, dispcc, nodos vendor) |
| `config-kernel.txt` / `config-kernel-display.txt` | `.config` del kernel en marcha (verificado) + extracto de display/SMMU/WDT |
| `consola-ultimo-boot-28sep.txt` | Segmento de consola del último boot (NO es dmesg; ver §5) |
| `consola-cmdline-live.txt` | Línea `Kernel command line` del boot actual |
| `usb-caida-1743.txt` | Eventos USB del PC que documentan la caída (17:27 alta, 17:43:46 baja) |
| `ssh-comandos-lote1.txt` | (si existe) salida del lote de comandos cuando se recupere el SSH |
| `device-tree.tar.gz`, `dmesg-arch.txt` | **PENDIENTES** (§11) — no se han podido generar sin SSH |

Generado por SG-EVIDENCIA sin escribir nada en la tablet ni en `~/gpu-work`; sin commits.
