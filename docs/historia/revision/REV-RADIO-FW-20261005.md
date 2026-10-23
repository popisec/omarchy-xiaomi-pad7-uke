# REV-RADIO-FW — WiFi/BT/modem/sensores/audio/cámaras + empaquetado de firmwares (2026-10-05)

Revisión de radio y firmwares para el port Arch de la Xiaomi Pad 7 (`uke`, SM8635 "cliffs").
Fuente de evidencia: `build/evidencia/android-full/extracted-full/` (captura 2026-10-05, DT vivo en
`14-dt/dt-live.tar.gz`, extraído a `/tmp/dt-live-uke` para análisis; NO committear).
Port: `~/gpu-work/palawan-linux` (7.2.0-rc2; checkout actual en rama `s150-postclk`,
no en `uke-ports-20260915` — nota, no bloquea), DT `arch/arm64/boot/dts/qcom/xiaomi-uke.dts`,
config en `~/gpu-work/build-uke/.config`. Solo lectura; nada extraído del ROM.

Convención de citas DT vivo: `vivo:soc/<nodo>/<prop>`.

---

## 0. Veredicto ejecutivo

| Área | Veredicto | Esfuerzo |
|---|---|---|
| WiFi (WCN6750, ath11k+wpss) | **VIABLE YA** — kernel y .config listos; falta terminar DT (wpss/wifi/PMU) + empaquetar fw | P0 |
| BT (WCN6750, hci_uart+btqca) | **VIABLE YA** — UART correcto (SE10 @888000); falta nodo serdev + PMU + gpios | P0 |
| btpower vendor | **NO HACE FALTA** — se sustituye por `pwrseq-qcom-wcn` (ya en el fork) + reguladores DT | — |
| Modem (mss) | **disabled confirmado en vivo** — WiFi-only; no empaquetar mss | — |
| Sensores (LSM6DSO/QMC630x/STK3BCX/SX937x) | **POSTERGAR** — los 4 chips cuelgan del SSC (ADSP), no visibles en el DT del AP | P2 |
| Audio (lpass-cdc + swr + wcd939x) | **POSTERGAR (condicionado)** — arquitectura mainline existe en el fork (macros+QDSP6), falta trabajo DT/DAI | P1 |
| Cámaras (CAMSS cliffs) | **POSTERGAR** — camss del fork solo llega a sm8550; sin tablas cliffs | P2 |
| FM (RTC6226/bt_fm_slim) | **POSTERGAR** — sin driver mainline | P3 |

---

## 1. WiFi — ath11k + wpss remoteproc

### 1.1 Evidencia Android
- Chip: `vivo:soc/qcom,wcn6750` (compatible `qcom,wcn6750`, reg `0x17110000/0x40 + 0xc0000000/0x10000`
  msi_addr/smmu_iova_ipa, `iommus = <apps-smmu 0x1400 0x1>`, `qcom,rproc-handle -> remoteproc-wpss@9bb00000`,
  MSA `qcom,wlan-msa-fixed-region -> reserved-memory/wlan_msa_region@a6400000` 12 MB).
- Rails del chip (vivo): `vdd-cx-mx → pmxr2230_s3` (0.968–1.04 V), `vdd-1.8-xo → pmxr2230_s1`
  (1.856–2.04 V), `vdd-1.3-rfa → pmxr2230_s2` (1.256–1.408 V).
- WPSS: `vivo:soc/remoteproc-wpss@9bb00000` = **`qcom,cliffs-wpss-pas`**, status ok,
  **`firmware-name = "qca6750/wpss.mdt"`**, `memory-region = wpss_region@9bb00000` (0x9bb00000, 25 MB),
  reg 0x9bb00000+0x10000, clock xo, `qcom,qmp -> power-controller@c300000` (AOP), glink-edge "wpss"
  (remote-pid 13) + `qcom,smp2p-wpss`. dmesg: `Booting fw image qca6750/wpss.mdt, size 4844` y arranque OK
  (`08-wifi/dmesg-wifi.txt`, `15-common/dmesg-full.txt`).
- FW WLAN adicional que carga el vendor (icnss2): `qca6750/regdb_xiaomi.bin` (regulatory vendor) y
  `qca6750/bd_o82gl.elf` (BDF del panel o82). **Ninguno sirve para ath11k** (formato vendor);
  ath11k usa `board-2.bin` de linux-firmware (el commit d9c42df0c ya arranca "sin fichero de
  calibración"). `wlan_mac.bin` tampoco aplica (MAC de efuse/BDF).
- Driver Android: `qca_cld3_qca6750` + `icnss2` (DLKM) — se sustituye por ath11k en el port.

### 1.2 Estado del port
- **ath11k mainline soporta WCN6750**: `drivers/net/wireless/ath/ath11k/ahb.c` tiene
  `compatible = "qcom,wcn6750-wifi"` con ops PCI-window dedicadas (líneas 35–196 del fork). ✓
- **.config ya lo tiene**: `CONFIG_ATH11K=m`, `CONFIG_ATH11K_AHB=m`, `CONFIG_ATH11K_PCI=m`,
  `MAC80211=m`, `CFG80211=m`, `QCOM_Q6V5_PAS=m`, `QCOM_PDR_HELPERS=y`, `QCOM_PIL_INFO=m`,
  `QCOM_SYSMON=m`, `QCOM_SMP2P=y`, `QCOM_SMEM=y`, `QCOM_AOSS_QMP=y`, `QRTR=y`,
  `POWER_SEQUENCING=y`, `POWER_SEQUENCING_QCOM_WCN=m`. **No falta ningún CONFIG para WiFi/BT.**
- **DT base (palawan.dtsi) ya trae el esqueleto**: `wifi@17110040` (`qcom,wcn6750-wifi`,
  `iommus <&apps_smmu 0x1400 0x1>` — mismo SID que el vivo —, `qcom,rproc = <&remoteproc_wpss>`,
  `memory-region = <&wlan_msa_mem>`, smp2p-wlan-1/2/3) y `remoteproc_wpss@9bb00000` con reg/memoria
  que CASAN con el vivo (wpss 0x1900000; wlan-msa 0xc0000000… idénticos).
- **Parche uke ya en el fork** (d9c42df0c): ath11k-ahb enciende el PMU vía `pwrseq_get("wlan")`
  (empareja por `vddaon-supply` del nodo WLAN → regulador virtual del PMU), SMMU deja el WLAN en
  dominio TRADUCIDO y el resto IDENTITY, sin MSI de anillos.
- **Gaps DT**: `&wifi` y `&remoteproc_wpss` siguen `disabled` en `xiaomi-uke.dts`; el wpss lleva
  compatible `qcom,palawan-wpss-pas` (→ `sc7280_wpss_resource` con **proxy_pd_names cx/mx**, que el
  propio fork documenta como -ENODATA en cliffs) y sin `firmware-name`.

### 1.3 FIXES WiFi (P0)
1. En `xiaomi-uke.dts`:
   ```dts
   &remoteproc_wpss {
       compatible = "qcom,cliffs-wpss-pas";          /* entrada ya en qcom_q6v5_pas.c:1628 */
       firmware-name = "qca6750/wpss.mdt";
       cx-supply = <&vreg_s3b_1p04>;                  /* vivo: cx -> rail 0.968–1.04 (qcom_pas_init_regulator la usa opcional) */
       status = "okay";
   };
   &wifi { status = "okay"; };                        /* vddaon-supply -> regulador virtual del PMU (ver §3) */
   ```
   (El `reg` del wpss coincide ya; los `power-domains` rpmhpd del nodo base quedan inertes con el
   compatible cliffs, que no adjunta proxy-PDs.)
2. Empaquetar fw (tabla §8, filas W1–W4).
3. Tras el primer QMI OK, volver a probar MSI de anillos (hoy desactivado por experimento s248).

---

## 2. BT — hci_uart + btqca por UART (SE10)

### 2.1 Evidencia Android
- UART de BT: alias `hsuart0 = /soc/qcom,qupv3_1_geni_se@8c0000/qcom,qup_uart@888000`
  (compatible `qcom,msm-geni-serial-hs`, status ok), **QUP1-SE2 = SE10 global, GPIOs 40/41/42/43**,
  función `qup1_se2_l0..l3`, drive-strength 2 (vivo:`soc/pinctrl@f000000/qupv3_se10_4uart_pins/*`).
- Nodo BT vendor: `vivo:soc/bt_wcn6750` (compatible `qcom,wcn6750-bt`):
  - `qcom,bt-reset-gpio = <tlmm 156>`, `qcom,bt-sw-ctrl-gpio = <tlmm 80>` (MPM wake 80),
    `qcom,wl-reset-gpio = <tlmm 35>` (enable WLAN del mismo PMU).
  - Reguladores: `vdd-aon/dig/rfa-0p8/rfacmn → pmxr2230_s3`, `vdd-io → pmxr2230_l7` (1.8 V),
    `vdd-rfa1 → pmxr2230_s1`, `vdd-rfa2 → pmxr2230_s2`, `vdd-ipa-2p2 → pmr735a_s3` (1.6–2.4 V).
- Módulos Android: `hci_uart`, `btqca`, `btpower`, `bt_fm_slim`, `radio_i2c_rtc6226_qca`.

### 2.2 Estado del port
- El SoC base ya define `uart10: serial@888000` (`qcom,geni-uart`, IRQ GIC_SPI 584,
  pinctrl `qup_uart10_default` gpio42/43 `qup1_se2` + `qup_uart10_cts_rts` gpio40/41) — **es el
  mismo UART que el vivo**; solo falta `status = "okay"` + nodo hijo en `xiaomi-uke.dts`.
- **.config completo**: `SERIAL_DEV_BUS=y`, `BT=m`, `BT_HCIUART=m`, `BT_HCIUART_H4=y`,
  `BT_HCIUART_SERDEV=y`, `BT_HCIUART_QCA=y`, `BT_QCA=m`.
- **Driver**: `hci_qca.c` del fork tiene `qcom,wcn6750-bt` (línea 2781) y
  `qca_soc_data_wcn6750` con **9 vregs exigidos**: `vddio, vddaon, vddbtcxmx, vddrfacmn,
  vddrfa0p8, vddrfa1p7, vddrfa1p2, vddrfa2p2, vddasd` (devm_regulator_bulk_get; los que falten
  en DT caen al dummy regulator — verificado en `drivers/regulator/core.c:2435` con
  `regulator_dummy_init()` incondicional, aviso "supply … not found, using dummy regulator").
  Nota: `lamma-qrd.dts` (in-tree) usa OTROS nombres (vddwlcx/vddwlmx/vddrfa1p3/vddrfa1p8, 8 sin
  vddio/vddasd) — no casan con la tabla del driver de este fork; usar la tabla del driver.
- **FW BT va en linux-firmware, NO el de Android**: `btqca.c` para QCA_WCN6750 pide
  `qca/msbtfw<rom>.mbn` (ELF, fallback `qca/msbtfw<rom>.tlv`) y NVM `qca/msnv<rom>.bin`
  (btqca.c:828/929). Con ROM ver 0x11 del WCN6750: **`qca/msbtfw11.mbn` + `qca/msnv11.bin`
  (+ segmentos `msnv11.b09/b0a` que ya acompañan al bin en linux-firmware)**. El `BTFM.bin`
  del ROM fastboot no se usa en mainline. Host Arch ya lo tiene (`/lib/firmware/qca/msbtfw11.mbn`).

### 2.3 FIXES BT (P0)
```dts
&uart10 {
    status = "okay";
    bluetooth {
        compatible = "qcom,wcn6750-bt";
        vddrfacmn-supply = <&vreg_pmu_rfa_cmn>;    /* PMU virtual (patrón qcm6490-idp.dts) */
        vddaon-supply    = <&vreg_pmu_aon_0p59>;
        vddbtcxmx-supply = <&vreg_pmu_btcmx_0p85>;
        vddrfa0p8-supply = <&vreg_pmu_rfa_0p8>;
        vddrfa1p7-supply = <&vreg_pmu_rfa_1p7>;
        vddrfa1p2-supply = <&vreg_pmu_rfa_1p2>;
        /* vddio/vddrfa2p2/vddasd: dummy si se omiten; si hci_qca se queja:
           vddio=<&vreg_l7b_1p8>, vddrfa2p2=<pmr735a s3>, vddasd=<idem> */
        max-speed = <3200000>;
    };
};
```
Verificación: `hciconfig`/`bluetoothctl list` tras `modprobe hci_uart` + `btattach`-no (serdev
automático); el flow-control y power pulses ya los maneja hci_qca para WCN6750.

---

## 3. btpower — sustituto mainline

- **No existe `qcom,btpower` en mainline** (es techpack vendor DLKM). **Se prescinde de él**:
  - Secuencia de energía del PMU del WCN6750 → **`pwrseq-qcom-wcn`** (mainline, ya en el fork,
    compatible `qcom,wcn6750-pmu`, vregs `vddaon,vddasd,vddpmu,vddrfa0p8,vddrfa1p2,vddrfa1p7,
    vddrfa2p2`, enable por target). Referencia exacta in-tree: `qcm6490-idp.dts:199–256`.
  - El BT_EN (gpio 156) lo conmuta `hci_qca` vía `enable-gpios`/PMU (`bt-enable-gpios` del PMU);
    el WLAN_EN (gpio 35, vivo `qcom,wl-reset-gpio`) va como `wlan-enable-gpios` del PMU (el
    ath11k-ahb parcheado llama `pwrseq_power_on("wlan")` antes de `rproc_boot`).
- Nodo propuesto en `xiaomi-uke.dts` (rails = evidencia vivo §2.1):
  ```dts
  wcn6750-pmu {
      compatible = "qcom,wcn6750-pmu";
      vddaon-supply     = <&vreg_s3b_1p04>;   /* 0.968–1.04 V */
      vddpmu-supply     = <&vreg_s3b_1p04>;
      vddrfa0p8-supply  = <&vreg_s3b_1p04>;
      vddrfa1p2-supply  = <&vreg_s2b_1p4>;    /* 1.256–1.408 V */
      vddrfa1p7-supply  = <&vreg_s1b_2p04>;   /* 1.856–2.04 V  */
      vddrfa2p2-supply  = <&vreg_s3e_2p4>;    /* pmr735a s3 — añadir grupo regulators-3 */
      vddasd-supply     = <&vreg_s3e_2p4>;    /* OPEN: rail "asd" sin equivalente claro en vivo; idem 2p2 como 1er intento */
      bt-enable-gpios   = <&tlmm 156 GPIO_ACTIVE_HIGH>;
      wlan-enable-gpios = <&tlmm 35 GPIO_ACTIVE_HIGH>;
      regulators { /* ldo0..ldo7 del patrón idp, SIN pcie (WCN6750 no lleva PCIe aquí) */ };
  };
  ```
  y `apps_rsc { regulators-3 { compatible = "qcom,pmr735a-rpmh-regulators"; qcom,pmic-id = "e";
  s3 { 1.6–2.4 V … } } }` (vivo: `pmr735a_s3` alimenta vdd-ipa-2p2/rfa2p2; el
  `pmr735a.dtsi` del fork no trae bloque de reguladores — el TODO ya estaba anotado en
  xiaomi-uke.dts).

---

## 4. Modem (mss) — WiFi-only confirmado

- Vivo: `soc/remoteproc-mss@04080000` compatible `qcom,cliffs-modem-pas` **status=disabled**;
  `getprop-modem.txt` con rild stopped; sin fw `modem*` en `/vendor/firmware`
  (`09-modem/firmware/listing.txt` vacío). ✓
- Port: `palawan.dtsi` trae `remoteproc_mpss@4080000` (`qcom,palawan-mpss-pas`) ya **disabled**. ✓
- Conclusión: el port no necesita `mss` ni su fw (mpss_region 0xcd00000 se reserva igualmente —
  respetar la carve del XBL). ADSP/CDSP/WPSS sí: ADSP (audio+charger pmic_glink+sensor_pd) y WPSS
  (WiFi) obligatorios; CDSP opcional (compute/cámara).

---

## 5. ADSP/CDSP del port vs vivo (pre-req de audio/carga; afecta a radio vía sensor_pd)

Comparación props clave (vivo `remoteproc-adsp@03000000` / `remoteproc-cdsp@32300000` contra
`palawan.dtsi` tal como lo usa hoy `xiaomi-uke.dts`, que NO los sobreescribe):

| Prop | Vivo (uke) | Port hoy | Fix |
|---|---|---|---|
| adsp compatible | `qcom,cliffs-adsp-pas` | `qcom,palawan-adsp-pas` → sm8550_adsp_resource (proxy lcx/lmx) | cambiar compatible (entrada ya en el fork) |
| adsp reg | `0x03000000+0x10000` | `0x6800000+0x10000` | cosmético para PAS (el boot va por TZ/SCM), alinear por claridad |
| adsp memory-region | `adspslpi@9d400000` **0x4500000** + `q6_adsp_dtb@a1900000` | `adspslpi@9d400000` **0x3200000** + `q6_adsp_dtb@a0600000` | **CORREGIR reserved-memory** (ver abajo) |
| wpss compatible | `qcom,cliffs-wpss-pas` | `qcom,palawan-wpss-pas` → sc7280 (proxy cx/mx) | cambiar compatible |
| wpss memory-region | `wpss@9bb00000` 0x1900000 ✓ | igual ✓ | — |
| cdsp compatible | `qcom,cliffs-cdsp-pas` | `qcom,palawan-cdsp-pas` → sm8650 (proxy cx/mxc/nsp) | cambiar compatible — **la entrada cliffs-cdsp NO existe aún en el of_match del fork**; añadirla igual que cliffs-adsp (sin proxy pds, cx/mx/nsp por supplies) o dejar CDSP disabled de momento |
| mss | disabled ✓ | disabled ✓ | — |

**FIX reserved-memory (importante, riesgo de corrupción del carveout del XBL):** el vivo reserva
`adspslpi_region@9d400000` con tamaño **0x4500000** (69 MB, termina en 0xa1900000 donde va el DTB
del ADSP). El port reserva solo 0x3200000 y pone el `q6_adsp_dtb` en 0xa0600000: la zona
0xa0600000–0xa1900000 la usa el firmware ADSP/SLPI pero quedaría libre para el alocador de Linux.
En `xiaomi-uke.dts`:
```dts
/ { reserved-memory {                       /* overrides */
    /delete-node/ q6-adsp-dtb@0xa0600000;   /* nombre exacto según palawan.dtsi */
    adspslpi_mem@9d400000 { reg = <0 0x9d400000 0 0x4500000>; };
    q6_adsp_dtb_mem: q6-adsp-dtb@a1900000 { reg = <0 0xa1900000 0 0x80000>; no-map; };
}; };
```
(Validar nombres/etiquetas reales al editar; el tamaño vivo es la carved real del ABL.)

FW ADSP ya cargado por el port según sus notas (carga via TZ); los ficheros van en
`/lib/firmware/adsp*.{mdt,bXX}` + `adsp_dtb*` (tabla §8, filas A1–A3).

---

## 6. Sensores — POSTERGAR (documentado)

- **Los 4 chips NO cuelgan de un I2C del AP.** En el DT vivo no existe NINGÚN nodo
  lsm6dso/qmc/stk/sx9 (búsqueda exhaustiva de `compatible` en todo el árbol: 0 resultados). En
  cambio el dmesg muestra `PDR msm/adsp/sensor_pd … is up` + `adsprpc … sensor_pd`
  (`10-sensors/dmesg-sensors.txt`) y el HAL es `vendor.sensors-hal-multihal` (SSC/QSEE):
  los chips están cableados al **I2C del SSC (núcleo de sensores en ADSP)**.
- Refuerzo: los adaptadores I2C que ve Android (`i2c-2,4,5,6,7,8,9`, `15-common/unbound-devices.txt`)
  no tienen clientes de sensores; los hijos reales de los buses enabled son cámara (i2c@880000),
  smartPA foursemi fs16xx @0x34–37 (i2c@88c000), backlight ktz8866/wcd939x (i2c@a80000).
- Drivers mainline si algún día se cablea: LSM6DSO → `st_lsm6dsx` (config `IIO_ST_LSM6DSX=m` ya
  presente, aunque sin nodo donde colgar); **QMC630x → sin driver mainline**; **STK3BCX → sin
  driver mainline** (stk3310 no lo cubre); **SX937x → sin driver mainline** (los `sx9310/9324/9360`
  son primos, no el mismo chip).
- Veredicto: **postergar**. Única alternativa real = stack SSC completo (fastrpc + fw sensor_pd del
  ADSP + userspace ssc/sensors-hal) — coste alto, no recomendado ahora.

## 7. Audio y cámaras

**Audio (cliffs-mtp-snd-card) — postergar condicionado.**
- Android: `qcom,pineapple-asoc-snd` sobre `spf_core_platform` + `lpass-cdc` (vivo:`soc/spf_core_platform/lpass-cdc`
  con `rx-macro@6AC0000`, `tx-macro@6AE0000`, `wsa-macro@6B00000`, `va-macro@6D44000`,
  `wcd937x-codec` disabled, `wcd939x-codec`) + swr (dmesg: `lpass_cdc_va_macro … swr pin state`,
  `swr-mgr … version 0x2010000`) + `wcd939x_i2c@e` (i2c@a80000, mbhc/auriculares) y 4x
  `fs16xx` smartPA (i2c@88c000, fw `fs19xx.fsm`). WSA881x no enabled.
- "lpass-cdc" como tal **no existe en mainline**; PERO el fork ya trae el esqueleto mainline
  equivalente en `palawan.dtsi`: macros rx/tx/wsa/va con compatibles
  `qcom,palawan-*-macro,"qcom,sm8550-*"` (mismas direcciones 6ac0000/6ae0000/6b00000/6d44000),
  `gpr/q6apm` bajo el glink-edge del ADSP, y `.config` con `SND_SOC_QDSP6=m`, macros,
  `SND_SOC_WCD939X=m`, `SOUNDWIRE_QCOM=m`.
- Lo que falta para audio real: fw del ADSP ya en rootfs (§8), nodo `sound` (estilo sm8550.dtsi),
  nodos soundwire rx/tx/va + wcd939x-sdw, adaptar `lpasscc` de cliffs (mismo patrón que el
  "dispcc sin rpm" ya hecho), y mixer/UCM derivado de `11-audio/vendor-etc/mixer_paths*.xml`
  (copiados en la evidencia). Esfuerzo medio → **P1, tras WiFi/BT**. La postergación documentada
  aquí es veredicto válido.

**Cámaras — postergar documentado.**
- Android: stack 100% vendor DLKM (`camera` 4.9 MB, `msm_eva`, fw `CAMERA_ICP.mbn` en
  firmware_mnt; 4 cámaras, sensores o82_ofilm_ov13b10_wide (0x20, id 0xd42) y o82_aac_ov08d10_front
  (0x20, id 0x5647) por CCI/i2c).
- Fork: `drivers/media/platform/qcom/camss` existe y `VIDEO_QCOM_CAMSS=m`, pero su tabla más
  moderna es `qcom,sm8550-camss`; **no hay tablas cliffs/sm8635** (csid-gen3/csiphy/vfe específicos).
  Portarlas es un proyecto en sí → **P2**.

**Extras:** FM `radio_i2c_rtc6226_qca` + `bt_fm_slim`: sin driver mainline → P3. NFC `fm,fm19511`
(i2c@890000 @0x57, Android carga `nxp_nci`): opcional, mainline tiene `nfc/nxp-nci` — P3 con DT
nodo i2c. Vibrador `qpnp-vibrator-ldo` sin driver en Android (unbound) — bonus separado.

---

## 8. TABLA DE FIRMWARES A EMPAQUETAR (rootfs del port: `/lib/firmware/`)

Origen de extracción (NO extraer aún):
- **NON-HLOS.bin** del ROM `~/proyectos/ubuntu-uke/ROM-OS3.0.303.0.WOZEUXM.tgz`
  (`uke_eea_global_images_OS3.0.303.0.WOZEUXM_16.0/images/NON-HLOS.bin` = partición modem =
  `/vendor/firmware_mnt` en Android; montar RO y sacar `image/…`).
- **linux-firmware** (ya instalado en el host; comprimir como el paquete hace o soltar `.zst`).
- super.img **solo** aportaría `/vendor/firmware/wlan/qca_cld/*/wlan_mac.bin` y
  `/vendor/firmware` del GPU ya cubierto — **no se necesita abrir super.img para radio**.
- El tgz **NO traja** nada equivalente a `/vendor/firmware/wlan/qca_cld/kiwi_v2/regdb_xiaomi.bin`
  (esa está en super.img→vendor) — no se necesita (ath11k no la usa).

| # | Fichero Android (origen) | Destino port `/lib/firmware/` | De dónde sacarlo | Estado |
|---|---|---|---|---|
| W1 | `firmware_mnt/image/qca6750/wpss.mdt` (4.844 B) | `qca6750/wpss.mdt` | NON-HLOS.bin (tgz) | **P0** |
| W2 | `firmware_mnt/image/qca6750/wpss.b00 … b10, b12` (13 fich; **sin b11** — así está en la ROM) | `qca6750/wpss.bXX` | NON-HLOS.bin (tgz) | **P0** |
| W3 | `firmware_mnt/image/qca6750/wpss.qdb` | `qca6750/wpss.qdb` (opcional; el remoteproc mainline no lo pide) | NON-HLOS.bin (tgz) | opcional |
| W4 | — (ath11k board data) | `ath11k/WCN6750/hw1.0/board-2.bin` (+ `wpss.mdt` de referencia upstream) | **linux-firmware** (ya en host) | **P0** |
| B1 | — (BTFM.bin del ROM **no se usa**) | `qca/msbtfw11.mbn` | **linux-firmware** | **P0** |
| B2 | — | `qca/msnv11.bin` (+ `msnv11.b09`, `msnv11.b0a` si existen en el paquete) | **linux-firmware** | **P0** |
| A1 | `firmware_mnt/image/adsp.mdt + adsp.b00…b52` | `adsp.mdt` + `adsp.bXX` (ya usados por el port para carga/carga-rails) | NON-HLOS.bin (tgz) | P1 (verificar ya en rootfs) |
| A2 | `firmware_mnt/image/adsp_dtb.mdt + b01/b02` | `adsp_dtb.mdt` + segmentos | NON-HLOS.bin (tgz) | P1 |
| A3 | `firmware_mnt/image/cdsp.mdt + cdsp.b00…b15` (+`cdsp_dtb*`) | `cdsp.mdt`… (solo si se activa CDSP) | NON-HLOS.bin (tgz) | opcional |
| GPU | `gen71100_{sqe,gmu,zap}` — ya cubierto por la revisión GPU (zap en `qcom/uke/`) | — | ya resuelto | hecho |
| SEN | sin fw AP-side (el fw de sensores va DENTRO del adsp) | — | — | n/a |
| AUD | `fs19xx.fsm` (smartPA foursemi, /vendor/firmware) — sin driver mainline | — | super.img→vendor | no aplica aún |
| RAD | `regdb_xiaomi.bin`, `bd_o82gl.elf`, `wlan_mac.bin`, `WCNSS_qcom_cfg.ini` | NO empaquetar (formato vendor, ath11k no los consume) | — | descartado |
| MSS | mpss/nv — **no empaquetar** (modem disabled) | — | — | descartado |

Notas de destino: la ruta `qca6750/…` respeta el `firmware-name` del DT vivo y evita chocar con el
`ath11k/WCN6750/hw1.0/wpss.mdt` de linux-firmware (que en upstream viene SIN segmentos .bXX y no
sirve para qcom_q6v5_pas tal cual; alternativa válida: copiar W1/W2 a
`ath11k/WCN6750/hw1.0/` y poner `firmware-name = "ath11k/WCN6750/hw1.0/wpss.mdt"` como hace
`sc7280-chrome-common.dtsi:133` — elegir UNA de las dos y ser consistente).

---

## 9. Lista de FIXES priorizados

**P0 — WiFi + BT funcionales**
1. DT `xiaomi-uke.dts`: `&remoteproc_wpss` → compatible `qcom,cliffs-wpss-pas` + `firmware-name =
   "qca6750/wpss.mdt"` + `cx-supply = <&vreg_s3b_1p04>` + status ok; `&wifi` status ok (con
   `vddaon-supply` al regulador virtual wlan del PMU).
2. DT: nodo `wcn6750-pmu` (§3) + `regulators-3` pmr735a (s3, 1.6–2.4 V).
3. DT: `&uart10` status ok + nodo `bluetooth` `qcom,wcn6750-bt` (§2.3) con max-speed 3200000.
4. Empaquetar W1–W4 + B1–B2 (tabla §8).
5. Reserved-memory ADSP: `adspslpi` 0x4500000 y `q6_adsp_dtb@a1900000` (§5) — obligatorio antes de
   fiar el ADSP para sensores/carga.

**P1 — audio**
6. Alinear ADSP: compatible `qcom,cliffs-adsp-pas` (reg 0x03000000) y añadir entrada
   `cliffs-cdsp-pas` al of_match si se quiere CDSP.
7. Nodo sound + soundwire + wcd939x-sdw + lpasscc cliffs (documentación en §7).

**P2/P3 — postergados**
8. Sensores (SSC), cámaras (camss cliffs), FM, NFC — §6/§7.

**CONFIG**: sin huecos para radio. Confirmados presentes: `ATH11K/AHB/PCI=m`, `BT_HCIUART(=_SERDEV/_H4/_QCA)=m/y`,
`BT_QCA=m`, `SERIAL_DEV_BUS=y`, `QCOM_Q6V5_PAS=m`, `QCOM_PDR_HELPERS=y`, `QCOM_PIL_INFO=m`,
`QCOM_SYSMON=m`, `QCOM_SMP2P=y`, `QCOM_SMEM=y`, `QCOM_AOSS_QMP=y`, `POWER_SEQUENCING=y`,
`POWER_SEQUENCING_QCOM_WCN=m`, `MAC80211/CFG80211=m`, `VIDEO_QCOM_CAMSS=m`,
`SND_SOC_QDSP6=m`+macros+WCD939X+SDW (audio futuro). Opcionales no críticos:
`NFC_NXP_NCI_I2C` (NFC fm19511), `IIO_ST_LSM6DSX` (ya =m, inútil sin bus AP).

---

## 10. Fuentes citadas (extractos)

- vivo DT: `soc/qcom,wcn6750`, `soc/remoteproc-wpss@9bb00000` (`qcom,cliffs-wpss-pas`,
  `firmware-name=qca6750/wpss.mdt`), `soc/remoteproc-mss@04080000` (disabled),
  `soc/bt_wcn6750` (gpios 156/80/35), `soc/qcom,qupv3_1_geni_se@8c0000/qcom,qup_uart@888000` +
  `pinctrl@f000000/qupv3_se10_4uart_pins` (gpio40–43, `qup1_se2_l0..3`), `reserved-memory/*`
  (adspslpi 0x4500000, q6_adsp_dtb a1900000, wpss 0x1900000, wlan_msa 0xc00000),
  `soc/spf_core_platform/{lpass-cdc,sound}`.
- dmesg: `08-wifi/dmesg-wifi.txt` (wpss.mdt 4844 B, icnss2 regdb/bdf), `07-bluetooth/dmesg-bt.txt`,
  `09-modem/dmesg-modem.txt` (cdsp en firmware_mnt), `10-sensors/dmesg-sensors.txt`
  (sensor_pd PDR), `11-audio/dmesg-audio.txt` (lpass_cdc macros, swr, wcd939x), `15-common/dmesg-full.txt`.
- Port: `drivers/net/wireless/ath/ath11k/ahb.c` (wcn6750), `drivers/bluetooth/hci_qca.c:2171,2781`
  (9 vregs wcn6750), `drivers/bluetooth/btqca.c:828,929` (msbtfw/msnv), `drivers/remoteproc/qcom_q6v5_pas.c:1396–1447,1627–1643`
  (cliffs-adsp/wpss), `drivers/power/sequencing/pwrseq-qcom-wcn.c:348,580` (wcn6750-pmu),
  `arch/arm64/boot/dts/qcom/palawan.dtsi` (wifi@17110040, remoteproc_*, uart10, memory), `lamma-qrd.dts`,
  `qcm6490-idp.dts:199` (patrón PMU), `sc7280-chrome-common.dtsi:133` (firmware-name wpss upstream),
  commit d9c42df0c (pwrseq+SMMS SMMU).
- ROM: `~/proyectos/ubuntu-uke/ROM-OS3.0.303.0.WOZEUXM.tgz` (listado: NON-HLOS.bin, BTFM.bin,
  super.img, dspso.bin, qupv3fw.elf; 112 ficheros — sin modem.img aparte: NON-HLOS.bin ES el
  firmware_mnt).
