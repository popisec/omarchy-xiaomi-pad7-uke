# AUDIO sobre senemos v3 (ouke3) — inventario, estado del kernel y plan por etapas (FASE 1, solo lectura)

Fecha de medición: 18-oct-2026, 00:0x CEST (22:0x UTC, reloj de la tablet). Tablet: `7.2.9-senemos.1.4054.3-ouke3`, slot a.
Alcance de esta fase: investigación + plan. **No se cargó ni descargó ningún módulo, no se escribió en sysfs/debugfs, no se
tocó remoteproc, red, servicios ni sesión gráfica, ni se volcó MMIO/regmap.** En la tablet solo se hicieron lecturas
(`cat /proc/device-tree/...`, `ls /sys/...`, `lsmod`, `dmesg`, `pacman -Q`, `ls /lib/{firmware,modules}`, `blockdev`-equivalente por
`/sys/block/*/size` y un `dd` de 1 bloque de `super` para ver su magic).
Convención: **MEDIDO** = comando+salida o fichero:línea de este repo; **INFERIDO** = deducción mía, a refutar.
Rutas relativas a `~/proyectos/omarchy-uke` (en adelante `R/`). Comando base de acceso:
`ssh -i R/build/rootfs/uke-arch-root -o BatchMode=yes root@192.168.42.129 '<lectura>'`.

---

## 0. Resumen ejecutivo

1. **Todo el audio útil de la uke pasa por el ADSP** (AudioReach/SPF del firmware que ya corre por la carga). Altavoces: 4 amplificadores
   FourSemi **FS19xx** (familia `fs16xx`, DEVID 0x2900) por I2C-4 para control, pero el **dato va por TDM del LPASS** (`TDM-LPAIF_VA-RX-PRIMARY`,
   4 canales, 48 kHz, slots 32 bit) generado por el ADSP. Micrófonos: DMIC por los macros TX/VA del LPASS. Códec WCD9395 (SoundWire) solo para
   USB-C analógico/mic bias. No hay amp I2S independiente del ADSP (descartado con evidencia, §1.1 #12-13).
2. **El LPASS de cliffs es el de sm8650 de mainline** (direcciones, IRQ, SIDs de SMMU y IDs de reloj PRM idénticos; §3.4). Hay pila AudioReach completa
   en el kernel (`q6apm`, `q6prm`, `sc8280xp` card con `qcom,sm8650-sndcard`, macros, soundwire, wcd939x) y **todos esos módulos existen ya compilados** en
   `/lib/modules/…ouke3` (§3.2). Lo que falta es **DT, topología, SMMU, TDM y el driver de los amplificadores** (§3.3).
3. **El DT que ve el kernel ahora es el vendor tal cual** (compat `qcom,spf-core-platform`, `qcom,pineapple-asoc-snd`…): ningún driver de audio se liga; `msm-audio-ion`
   está `disabled` por el transform del ABL (`uke_scope_smmu_clients`) y **el bus I2C-4 de los amplis está `disabled`** (`uke_scope_qup_buses`).
4. **Bloqueos duros para altavoces** (no para "primer sonido"): (a) sin driver mainline para FS19xx (el `fs210x` es otro chip y otro formato de firmware);
   (b) `audioreach.c`/`q6apm-lpass-dais.c` no tienen TDM (solo I2S, CODEC_DMA, DP); (c) la topología (grafo) del vendor vive en ACDB `Forte` dentro de `odm_b`
   (partición lógica de `super`), no capturado; (d) SMMU del LPASS (SID 0x1001/0x80, 0x1061) no está admitido en el transform.
5. **Riesgo central = el ADSP**: `recovery_disabled=true` (parche 0033), así que un crash/fault del audio mata la carga y no se recupera solo. Cada etapa que toca el
   ADSP lleva su detección (§6) y su recuperación.
6. **Camino realista a "se oye algo"**: no es el altavoz. Es (i) un sumidero software (E1) para que Omarchy/PipeWire tengan dispositivo, y (ii) **Bluetooth A2DP**
   (WCN6750, host-side, independiente del ADSP) como primera salida audible; el altavoz (E7) es la etapa más larga. USB host está incompleto upstream
   (README senemos 15-oct: "Bluetooth, audio, USB host mode and suspend remain incomplete"), así que audio USB no es vía.
7. **Primer paso propuesto**: E0 (preparación en el PC, riesgo nulo) + E1 (sumidero software). El primer toque al ADSP que da información (E2) no necesita
   reflasheo (overlay DT en caliente), riesgo bajo.

---

## 1. Inventario del hardware de audio

### 1.1 Camino de datos (resumen con evidencia)

```
 apps (Linux) ──GLINK adsp_apps/GPR──► ADSP (SPF/AudioReach, audio_pd) ──┬─ LPAIF TDM1 (LPI gpio6-9) ──► 4x FS19xx (I2C-4 control) ──► 4 altavoces
                                                                        ├─ CODEC_DMA VA/TX ◄── macros va/tx (LPASS) ◄── DMIC (LPI gpio)  (+ MIC BIAS del WCD9395?)
                                                                        ├─ CODEC_DMA RX ──► rx-macro ──SWR──► WCD9395 ──► USB-C analógico (SBU/D+D-) (wcd-usbss)
                                                                        ├─ DISPLAY_PORT-RX (DP audio)       ├─ USB_AUDIO (offload QMI)   └─ SLIM-DEV1 (BT SCO/A2DP offload)
```

| # | Bloque | Hecho | Evidencia | Tipo |
|---|---|---|---|---|
| 1 | Tarjeta vendor | 1 tarjeta `cliffs-mtp-snd-card`, compat `qcom,pineapple-asoc-snd`, 53 dailinks, 112 dispositivos de /dev/snd | `R/build/android/cosecha-20261017/audio/proc-asound.txt:1-2,4-56`; `01-dmesg.txt:8336` ("driver name too long 'cliffs-mtp-snd-card'") | MEDIDO |
| 2 | DT vivo sound | `compatible="qcom,pineapple-asoc-snd"`, `model="cliffs-mtp-snd-card"`, `qcom,wsa-max-devs=0`, `qcom,wcn-bt=1`, `qcom,ext-disp-audio-rx=1`, `qcom,tdm-max-slots=4`, `qcom,msm-mbhc-usbc-audio-supported=1`, `qcom,quin-mi2s-gpios=<&quin_mi2s_pinctrl>`, `wcd939x-i2c-handle` | `bash -s -- soc/spf_core_platform/sound < dtdump.sh` (helper en §10), 18-oct | MEDIDO |
| 3 | Plataforma SPF | nodo `/soc/spf_core_platform` `qcom,spf-core-platform`; hijos: `lpass-cdc/`, `sound`, `qcom,msm-audio-ion`(+`-cma`), `lpi_pinctrl@6E80000`, `cdc_dmic{01,23,45,67}_pinctrl`, `fm_i2s1_pinctrl`, `quin_mi2s_pinctrl`, `{rx,tx,wsa}_swr_clk_data_pinctrl` | `find /proc/device-tree -type d` filtrado (resultado en el log de la sesión; reproducible con §10) | MEDIDO |
| 4 | GPR/ADSP | `/soc/remoteproc-adsp@03000000` = `qcom,cliffs-adsp-pas`, `glink-edge/qcom,gpr` `compatible="qcom,gpr"`, `reg=<2>`, `qcom,glink-channels="adsp_apps"`, `qcom,intents=<0x200 0x14>`; hijos vendor: `spf_core` (reg 3, `qcom,spf_core`), `q6prm` (reg 7, `qcom,audio_prm`, `qcom,sleep-api-supported`), `audio-pkt` (reg 0x17) | dump DT vivo 18-oct | MEDIDO |
| 5 | Canal GLINK abierto | el canal `adsp_apps` existe como rpmsg device sin driver (blacklist de `apr`) | `ls /sys/bus/rpmsg/devices` → `3000000.remoteproc-adsp:glink-edge.adsp_apps.-1.-1` | MEDIDO |
| 6 | Macros LPASS | rx `6ac0000`, tx `6ae0000`, va `6d44000` (`status` ausente = ok); **wsa `6b00000` `disabled`** | dump DT vivo (`soc/spf_core_platform/lpass-cdc/*`) | MEDIDO |
| 7 | SoundWire | master rx `swrm-io-base 6ad0000`, IRQ `0x9b` (SPI 155), 2 dev; master va `6d30000`, IRQs `0x1f0` (SPI 496)/`0x208`, `is-always-on`, 5 dev; master wsa `6b10000` (disabled). HW leído por el vendor = `0x2010000` vs DT `0x2000000` | dump DT vivo; `01-dmesg.txt:8281` | MEDIDO |
| 8 | Códec | **WCD9395 `WCD939X_2_0`**, `qcom,wcd939x-codec`, `qcom,split-codec`, slaves SDW `wcd939x-slave.e01170224` (rx) y `…e01170223` (tx/va); rails `cdc-vdd-{rx,tx,buck,px}` = `pmxr2230_l7` 1,8 V, `cdc-vdd-mic-bias` = `pmxr2230_bob` 3,296 V; micbias1-4 = 0xabe mV (2750); **reset = LPI gpio12** (`wcd_reset`, en reposo `out 0` = en reset) | dump DT vivo; `01-dmesg.txt:8299`; `perif-20261017/soundwire.txt:1-4`; `vendor-harvest-20261017b/gpio.txt:13` | MEDIDO |
| 9 | USB-C analógico | `wcd939x_i2c@e` en `i2c@a80000` (`qcom,sm7675-wcd939x-usb2`), reset TLMM **gpio119**, `vdd-usb-cp-supply` = **el mismo `pmxr2230_l7`** que los rails del códec; ya enlazado por el driver propio `wcd939x-usb-uke` (`drivers/usb/common/wcd939x-usb-uke.c`): este chip está **entre el PHY eUSB2 y el conector** (USB2 del puerto) | `ls /sys/bus/i2c/drivers` → `wcd939x-usb-uke`; DT vivo; parche `0006-uke-usb-v7-api.patch:109` | MEDIDO |
| 10 | Amplificadores | **4x FourSemi FS19xx** (`compatible "foursemi,fs16xx"`) en `i2c@88c000` (= i2c-4 de Android) direcciones 0x34-0x37; reset TLMM gpio 30/149/124/123, irq gpio 47/69/31/129; los cuatro leen `DEVID: 2900`; sin regulador `fsm_vddd` (dummy). Vendor driver `fs19xx_dlkm.ko` v4.0.7 (GPL, FourSemi) | DT vivo; `01-dmesg.txt:4514` (+`4689,4737,4811`); `modinfo vendor-modules-20261017/fs19xx_dlkm.ko` | MEDIDO |
| 11 | Modelo exacto del amp | solo se conoce familia y DEVID 0x2900; el nombre comercial (FS19xx concreto) NO se ha podido fijar. Mainline `fs210x` (FS2104/5S) usa DEVID 0x45/0x20 y otro formato de fw: **no aplica** | `sound/soc/codecs/fs210x.c:25-26`; `fs-amp-lib.h` `struct fs_fwm_header`; el `.fsm` empieza `00 01 'onlybsg' 00 '1' 00 fe fe…`, no encaja en esa cabecera | MEDIDO (header) / INFERIDO (modelo) |
| 12 | Enlace de audio de los amps | dai-link `TDM-LPAIF_VA-RX-PRIMARY` (+`-VIRT-2`) y `TDM-LPAIF_VA-TX-PRIMARY` → `fs16xx.4-0034 / fs16xx-aif`; ODM: `PAL_DEVICE_OUT_SPEAKER` backend `TDM-LPAIF_VA-RX-PRIMARY`, 4 canales, 48 kHz, 32 bit, `speaker_protection_enabled=1`; el TX es el retorno V/I-sense (`vi-feedback`) | `01-dmesg.txt:8214-8216`; `cosecha-20261017/audio/odm-resourcemanager_cliffs_mtp.xml:821-834`; `proc-asound.txt:46-48` | MEDIDO |
| 13 | Pines del TDM | `quin_mi2s_pinctrl` → `lpi_tdm1_{sck,ws,sd0,sd1}` = **LPI gpio6,7,8,9 `func2`**; en el volcado de Android en reposo esos 4 pines están en función 2 | DT Android `build/android/dt-full-uke-android/base/soc/spf_core_platform/lpi_pinctrl@6E80000/lpi_tdm1_*`; `vendor-harvest-20261017b/gpio.txt:7-10` | MEDIDO |
| 14 | Conflicto de pines | `dmic01_{clk,data}` = gpio6/7 `func1` y `dmic23` = gpio8/9 `func1` **colisionan** con TDM1 (gpio6-9 `func2`); `dmic45` gpio12/13 colisiona con `wcd_reset` (gpio12). El DT vendor es superconjunto de SKUs: **qué grupo DMIC lleva los micrófonos reales de la tablet no está resuelto** | DT Android (`dmic01..67_*_active/mux/pins`); `gpio.txt:7-14` | MEDIDO (conflicto) / sin resolver (cuál) |
| 15 | Micrófonos | los micros van por DMIC digital: `handset-mic` = path `dmic2` (`TX DMIC MUX2=DMIC0`, `TX_AIF1_CAP Mixer DEC2`), captura `CODEC_DMA-LPAIF_RXTX-TX-3/4` y `…VA-TX-0/1/2`. El DAPM vendor cuelga los DMIC de `MIC BIAS1/3` del WCD (`qcom,audio-routing`: "TX DMIC0 … MIC BIAS3") | `odm-mixer_paths_cliffs_mtp.xml:300-304,621`; `qcom,audio-routing` del DT vivo; `resourcemanager…xml:127,612` | MEDIDO |
| 16 | ¿DMIC dependen del WCD9395? | si el bias de los DMIC sale realmente del WCD, hace falta el códec arriba para captura | solo el routing DAPM; no medida eléctrica | INFERIDO |
| 17 | Sin WSA | 4 nodos `wsa883x/wsa884x` `disabled`, `wsa_max_devs: 0` | `dt-sound-nodes.txt` §2; `01-dmesg.txt:8217` | MEDIDO |
| 18 | Háptico | `swr_haptics@f0170220` (`qcom,pm8550b-swr-haptics`) `disabled` en rx-swr | DT vivo | MEDIDO |
| 19 | SLIMbus | `slim@6C40000` `disabled` (BT SCO/A2DP offload del vendor, `SLIM-DEV1-RX/TX-7`); 0033 lo deja contenido a propósito | DT vivo; `perif-20261017/…`; parche 0033 §README | MEDIDO |
| 20 | Stack vendor | AGM + PAL + GSL; grafos en ACDB **`/odm/etc/acdbdata/Forte/Forte_acdb_cal.acdb` + `Forte_workspaceFileXml.qwsp`** (modificado 14-nov-2024, ACDB SW 1.36.0.0); `audioadsprpcd audiopd` (fastrpc PD de audio) arranca en early-init | `coldboot-20261017/logcat-30s.txt:3224-3256`; `audio/vendor.qti.audio-adsprpc-service.rc` | MEDIDO |

### 1.2 Lo que dicen las capturas de Android sobre la secuencia de arranque del audio (referencia)

- ADSP arriba en 6,92 s (`01-dmesg.txt:8160`); GPR dev `spf_core:2:3`, `audio-pkt:2:17`, `q6prm:2:7` (`:8165-8167`); PDR de `msm/adsp/audio_pd` (`:8187`);
  `apm is up` a 6,99 s (`:8204`) — es la respuesta a `APM_CMD_GET_SPF_STATE`, el **mismo primer comando que envía `q6apm_get_apm_state()` de mainline**
  (`sound/soc/qcom/qdsp6/q6apm.c:146`).
- La card se registra a ~7,1 s tras reintentos de `msm_asoc_machine_probe` (falla "FAILED to get nvmem cell" varias veces, `:8220`), macros registrados (`:8264`),
  `wcd9395 version: WCD939X_2_0` (`:8299`); los amps ya estaban probados a 3,6 s (`:4514`) y cargan `fs19xx.fsm` en nowait (`:8311`).
- ADSP del vendor: `recovery disabled by kernel client` (`:8177`) — también en Android el recovery estaba desactivado.

### 1.3 Firmware del ADSP: es de la misma familia que el de sm8650

`strings` de `R/charge/firmware/adsp.b*` (56 ficheros, los mismos que carga la tablet): `QCOM time:Q6_BUILD_TS_Mon_Jun_24_13:25:43_PST_2024_00954.6`,
ruta `LPAIDSP.HT.1.0-00954.6-LANAI-1_20240624…`, `IMAGE_VARIANT_STRING=palawan.adsp.prodQ`. LANAI = SM8650 ("pineapple"). Contiene SPF
(`apm_gpr_cmd_handler.c`, `vcpm_response_handler.c`, `spf_*`), el cargador (`battmngr_*`) y módulos Xiaomi: `FSADSP 1..4 Spk:r0 tempr vbat f0 Q` (algoritmo
FourSemi de protección de 4 altavoces, CAPI), `mi_log` en `gpr_main.c`, referencias a `/odm/etc/audio/mis_*.bin` (efectos Misound). No contiene la cadena "tdm".
→ INFERIDO: el ADSP habla el AudioReach estándar; el protocolo `q6apm` de mainline debería valer (SM8650 funciona upstream con firmware de la misma línea),
pero **no hay prueba hasta ver `apm_get_spf_state` responder**.

---

## 2. Estado vivo de la tablet (línea base para detectar regresiones)

Medido 18-oct 00:0x CEST:
- `remoteproc0 wpss running qca6750/wpss.mdt recovery=enabled`; **`remoteproc1 adsp running adsp.mdt recovery=disabled`**.
- Módulos cargados: `ath11k_ahb ath11k mac80211 rpmsg_ctrl rpmsg_char qcom_q6v5_pas qcom_pil_info qcom_q6v5 qcom_sysmon qcom_common qcom_glink_smem qcom_pd_mapper qrtr_smd qcom_battmgr … qrtr`.
  **No** `apr`, `fastrpc`, `snd*`, `q6*`, `soundwire*`. `/proc/asound` y `/sys/class/sound` no existen; `/dev/snd` solo `timer`.
- Batería (`qcom-battmgr-bat`): `Charging`, 75 %, `voltage_now=4042270` µV.
- `dmesg`: `remote processor adsp is now up` a 4,33 s, `PDR … msm/adsp/charger_pd` (solo charger_pd: nadie ha pedido `avs/audio`).
- `/etc/modprobe.d/uke-carga.conf` blacklist: `qcom_q6v5_pas apr fastrpc ucsi_glink pmic_glink_altmode`; `uke-senemos-guard.conf`: `hci_uart coresight_funnel qcom_cpucp_mbox qcomtee`.
  (`modprobe <nombre>` explícito ignora la blacklist.)
- Rootfs: `pipewire 1.6.9`, `wireplumber 0.5.18`, `alsa-lib 1.2.16`, `alsa-ucm-conf 1.2.16` (trae `ucm2/Qualcomm/sm8650` y `…/sm8550`), `alsa-topology-conf`,
  `bluez-libs` (sin `bluez`), `linux-firmware 20260622` **sin** `qcom/` de audio: `/lib/firmware/qcom` solo tiene `gen71100_*.mbn`, `palawan/`, `uke/`.
- `pd-mapper` (parche 0028) ya sirve 5 dominios para `xiaomi,uke`: **`msm/adsp/audio_pd` instancia 74 con servicio `avs/audio`**, root, charger, sensor, cdsp
  (`drivers/soc/qcom/qcom_pd_mapper.c:253-259`, patch `0028-uke-protection-domain-map.patch:15-24`).

---

## 3. Qué hay en el kernel senemos para el audio

Árbol: `R/build/kernel-pokes/senemos-7.2.9/linux-7.2.9` (7.2.9 + 44 parches senemos + deltas). Config: `R/build/kernel-pokes/senemos-build/config-senemos-ouke3`.

### 3.1 Config (ouke3) — MEDIDO

| Pieza | CONFIG | Estado |
|---|---|---|
| ALSA/ASoC núcleo | `SND=m SND_SOC=m SND_SOC_TOPOLOGY=y SND_COMPRESS_OFFLOAD=m` | m/y |
| Transporte GPR/APR | `QCOM_APR=m` (módulo `apr`, atiende `qcom,gpr`), `QCOM_FASTRPC=m`, `QCOM_PD_MAPPER=m`, `QCOM_PDR_HELPERS=m` | m |
| AudioReach | `SND_SOC_QDSP6=m` `_CORE _COMMON _APM _APM_DAI _APM_LPASS_DAI _PRM _PRM_LPASS_CLOCKS _AFE* _ASM* _ADM _ROUTING _USB` | m |
| Card (machine) | `SND_SOC_SC8280XP=m` (compat `qcom,sm8650-sndcard`, `qcom,sm8450-sndcard`… `sound/soc/qcom/sc8280xp.c:167-179`), `SND_SOC_X1E80100=m`, `SND_SOC_SM8250=m`, `SND_SOC_QCOM_COMMON=m`, `SND_SOC_QCOM_SDW=m`, `SND_SOC_LPASS_CDC_DMA=m` | m |
| Macros LPASS | `SND_SOC_LPASS_{RX,TX,VA,WSA}_MACRO=m`, `_MACRO_COMMON=m` (compat hasta `qcom,sm8550-*`; sm8650 de mainline usa fallback sm8550) | m |
| SoundWire | `SOUNDWIRE=m SOUNDWIRE_QCOM=m REGMAP_SOUNDWIRE=m` (`qcom,soundwire-v2.0.0`, `drivers/soundwire/qcom.c:1819`) | m |
| Códec | `SND_SOC_WCD939X=m SND_SOC_WCD939X_SDW=m` (`qcom,wcd9395-codec`, `wcd939x.c:3599`; SDW id `0x0217/0x10e`), `SND_SOC_WCD_MBHC/CLASSH/COMMON=m`, `SND_SOC_WSA88{1,3,4}X=m` | m |
| Pines LPI | `PINCTRL_LPASS_LPI=m PINCTRL_SM8650_LPASS_LPI=m` (+sm8450/sm8550/…) | m |
| USB audio | `SND_USB_AUDIO=m SND_USB_AUDIO_QMI=m SND_SOC_USB=m SND_SOC_QDSP6_USB=m` | m |
| Software | `SND_ALOOP=m`; `SND_DUMMY` no | m |
| BT | `BT_HCIUART_QCA=y`, `BT_QCA=m` (hci_uart bloqueado por la guarda) | m |
| FS amps | `SND_SOC_FS210X` **no** (y no aplica) ; no existe driver FS19xx | — |
| UAC2 gadget | `USB_CONFIGFS_F_UAC2` **no** | — |
| Overlay en caliente | `OF_OVERLAY=y OF_DYNAMIC=y CONFIGFS_FS=y`, pero **no hay `OF_CONFIGFS`** (no existe en mainline) | solo vía módulo propio |
| IOMMU | `ARM_SMMU=y ARM_SMMU_QCOM=y ARM_SMMU_DISABLE_BYPASS_BY_DEFAULT=y` | y |

### 3.2 Módulos presentes en `/lib/modules/7.2.9-senemos.1.4054.3-ouke3` — MEDIDO (`find` en la tablet)

`apr.ko`, `pdr_interface`, `qcom_pdr_msg`, `qmi_helpers`; `soundwire-bus`, `soundwire-qcom`; `snd`, `snd-pcm`, `snd-compress`, `snd-soc-core`, `soc-usb`;
`sound/soc/qcom/qdsp6/{q6core,snd-q6apm,q6apm-dai,q6apm-lpass-dais,q6prm,q6prm-clocks,q6afe*,q6asm*,q6adm,q6routing,q6usb,snd-q6dsp-common}`;
`snd-soc-qcom-common`, `snd-soc-qcom-sdw`, `snd-soc-sc8280xp`, `snd-soc-x1e80100`, `snd-soc-lpass-cdc-dma`, `snd-soc-lpass-{rx,tx,va,wsa}-macro`, `snd-soc-lpass-macro-common`,
`snd-soc-wcd939x`, `snd-soc-wcd939x-sdw`, `snd-soc-wcd-{common,mbhc,classh}`, `snd-soc-wsa88{1,3,4}x`, `snd-soc-dmic`; `pinctrl-sm8650-lpass-lpi` (+ otros);
`snd-usb-audio`, `snd-usb-audio-qmi`; `drivers/slimbus/{slimbus,slim-qcom-ngd-ctrl}`; `sound/drivers/snd-aloop`. **No hay** módulo FS19xx ni nada de UAC2.

### 3.3 Qué falta / qué chocaría (MEDIDO por lectura de código salvo marca)

1. **DT**: el DT vivo no tiene ningún nodo mainline de audio. Hay que aportar (overlay o transform del ABL): hijos de `qcom,gpr` (`qcom,q6apm` reg=1, `qcom,q6prm` reg=2, `qcom,q6prm-lpass-clocks`, `qcom,q6apm-lpass-dais`, `qcom,q6apm-dais`),
   macros con compat `qcom,sm8550-lpass-*-macro`, masters `qcom,soundwire-v2.0.0`, `qcom,wcd9395-codec`, LPI pinctrl `qcom,sm8650-lpass-lpi-pinctrl`, y la card `qcom,sm8650-sndcard`.
   Plantilla: `arch/arm64/boot/dts/qcom/sm8650.dtsi:4564-4604` (gpr/apm/prm), `:4653-4811` (macros, swr, lpass_tlmm), `sm8650-qrd.dts:95-198` (card y WCD9395). `sm7675-xiaomi-uke.dts` del árbol es un esqueleto UEFI sin audio y no se usa en este arranque.
2. **Transform del ABL (`arch/arm64/kernel/uke-abl.c`) es restrictivo a propósito**:
   - `uke_scope_smmu_clients` (`:187-258`) deja **solo 7 clientes** del `apps-smmu` (ufshc, ssusb, 2×gpi-dma, 2×qupv3, wcn6750) y **deshabilita todo otro nodo con `iommus` hacia ese SMMU**
     → por eso `msm-audio-ion` sale `status="disabled"` (DT vivo). El audio del LPASS necesita SIDs `0x1001/0x80` y `0x1061/0` (idénticos en vendor `qcom,msm-audio-ion` y en `sm8650.dtsi:4585-4589`).
   - `uke_scope_qup_buses` (`:314-345`) deja en QUP1 solo `i2c@890000`/`ktz8866@11` y **deshabilita el resto (incluido `i2c@88c000`, los amps)**. DT vivo: `i2c@88c000 status="disabled"` (en Android `ok`).
     Sus `dmas` son de 5 celdas vendor; el parche 0023 solo traduce la ruta de la KTZ.
3. **Parche 0033** (`qcom_q6v5_pas.c:890-894`): `auto_boot=true`, `recovery_disabled=true` para `xiaomi,uke`; su mensaje dice "unqualified SLIM DMA path is contained in the boot DT". README senemos: "ADSP stays manual … FastRPC DMA, PDM maps, audio and sensor operation remain separately gated" (0027, 0030).
4. **Parche 0027** (`apr.c:605-615`): para `xiaomi,uke` el `qcom,gpr` toma el dominio de `reg=<2>` → `apr` **sí** probaría con el DT vivo. **Con los hijos vendor (sin `qcom,protection-domain`) `apr` solo abre el canal y registra `gprsvc:*` sin driver: no hay PDR ni tráfico** (`apr.c:516-563,640-654`).
5. **TDM**: `sound/soc/qcom/qdsp6/audioreach.c` y `q6apm-lpass-dais.c` solo definen I2S/CODEC_DMA/DP (`q6dma_ops`, `q6i2s_ops`, `q6hdmi_ops`, `:264-294`); los IDs TDM existen en los bindings por herencia de q6afe pero no hay módulo TDM de AudioReach en el kernel (`grep -i tdm audioreach.c` vacío). **Esto bloquea el camino de los 4 altavoces**: se necesita parche de kernel + los parámetros del módulo TDM (tipo de interfaz LPAIF_VA, slots, índices) que solo están en el ACDB `Forte`. INFERIDO que basta ampliar `q6apm-lpass-dais` + topología; NO se sabe si el módulo I2S del ADSP admite modo TDM.
6. **Topología**: `topology.c:1320` pide `qcom/<driver_name>/<card_name>-tplg.bin` (con `qcom,sm8650-sndcard` y `model="X"` → `/lib/firmware/qcom/sm8650/X-tplg.bin`). El repo de fuentes de topologías (`github.com/linux-msm/audioreach-topology`, consultado 18-oct) trae `.m4` de SM8450-HDK, SM8550-HDK, SM8250-MTP, X1E80100, QCM6490…; en el listado visible **no vi** un `.m4` de sm8650 (INFERIDO: no existe o no estaba a la vista). Hay que **escribir la topología de la uke** a partir de `SM8550-HDK.m4` y compilarla con `alsatplg` en el PC; ninguna viene en `linux-firmware 20260622` instalado.
7. **Amplificadores**: no hay driver (§1.1 #10-11). El `fs19xx.fsm` (4828 B, preset "onlybsg", proyecto 1, 14-ago-2024) **no es** el formato `fs_fwm_header` de `fs-amp-lib` de mainline → hay que portar el driver GPL v4.0.7 del vendor (fuente en el árbol OEM de Xiaomi que senemos ya pinea, `5712080a…`; INFERIDO que ahí está) o reimplementarlo leyendo el `.ko`.
8. **WCD9395 `reset`**: en mainline el reset es un GPIO del códec; en la uke es **LPI gpio12** (≠ el reset del usbss, TLMM gpio119; en `sm8650-qrd.dts:188` es TLMM 107). El LPI TLMM necesita votos PRM (ADSP) para existir.
9. **Autoload**: sin DT mainline no hay autoload de audio; con `apr` fuera de la blacklist se cargaría solo (`of:…Cqcom,gpr`). Mantener la blacklist hasta decidir.

### 3.4 Equivalencia cliffs ≙ sm8650 (MEDIDO, vendor DT vivo contra `sm8650.dtsi` del árbol)

| Cosa | uke (DT vivo) | sm8650.dtsi |
|---|---|---|
| rx-macro / tx / wsa / va | `6ac0000` / `6ae0000` / `6b00000` / `6d44000` | `:4653 / :4700 / :4717 / :4796` |
| swr rx / wsa / va | `6ad0000` (SPI 155) / `6b10000` / `6d30000` (SPI 496) | `:4670` (SPI 155) / `:4734` / `:4764` (SPI 496) |
| LPI TLMM | `lpi_pinctrl@6E80000`, 23 pines (GPIOs 266-288) | `lpass_tlmm @6e80000`, `gpio-ranges 0 0 23` (`:4811-4821`) |
| SIDs audio SMMU | `0x1001/0x80`, `0x1061/0` | `q6apmdai iommus` idéntico (`:4585-4589`) |
| IDs PRM | clk_id `0x307 0x30c 0x30e 0x312 0x314 0x318` (`01-dmesg.txt:4232…`) | `Q6PRM_LPASS_CLK_ID_*` `q6prm.h:58-84` idénticos |
| `qcom,gpr` | `adsp_apps`, intents `<512 20>` | `:4564-4570` idéntico |
| protección de dominio | `avs/audio`+`msm/adsp/audio_pd` (pd-mapper uke) | `:4577-4578` |

Lo único distinto: **no hay WSA**, el WCD9395 cuelga de LPI gpio12 y los amplis son FS19xx por TDM (sm8650-qrd usa WSA8845 por SWR).

---

## 4. Firmware y datos necesarios, y dónde están (solo localizar, sin redistribuir)

| Qué | Para qué | Dónde está | Estado |
|---|---|---|---|
| `adsp.mdt/bNN`, `adsp_dtb.*` (56 ficheros) | el ADSP; el AudioReach/APM va **dentro** (no hay fw "adsp_audio") | `R/charge/firmware/` (`adsp-fw.sha256`), y en el rootfs `/lib/firmware/adsp*` (53 listados) | YA CARGADO (carga) |
| Topología AudioReach `qcom/sm8650/<model>-tplg.bin` | grafo que `q6apm` carga en el ADSP | **no existe**; se compila (`.m4`→`alsatplg`) | FALTA (§3.3.6) |
| ACDB `Forte` (`Forte_acdb_cal.acdb`, `Forte_workspaceFileXml.qwsp`) | grafos y calibración del vendor; **única fuente de los parámetros TDM del altavoz**; no necesario para la primera reproducción | `odm_b` dentro de `super`: `/dev/disk/by-partlabel/super → sda31`, 11 274 289 152 B, magic LP geometry `67446c61` ("gDla") en 4096 B (MEDIDO, 18-oct). **No** está en `build/backup-par-bueno/android-20261017/` (su `particiones.txt` no lista super). Android ya no arranca sin `erase userdata`, pero `super` se puede leer en frío (lpunpack/LP parse en el PC) | LOCALIZADO, sin extraer |
| `fs19xx.fsm` | programa los 4 FS19xx por I2C | extraído: `R/build/android/cosecha-20261017/audio/fs19xx.fsm`; original en `/odm/firmware/fs19xx.fsm` (Android) | EN EL PC |
| Driver FS19xx (fuente) | control I2C, escenas, volumen | vendor `.ko` en `R/build/android/vendor-modules-20261017/fs19xx_dlkm.ko` (y `ubuntu-uke/stock/modules/`); fuente OEM: árbol que senemos pinea (`5712080a4b0c0b1a879e6d145c601c649ddaddfd`) — INFERIDO | .ko sí, fuente no |
| Mixer/PAL XML | referencia de rutas y escenas (`FSM_Scene`, `FSM_Volume`) | `cosecha-20261017/audio/odm-mixer_paths_*.xml`, `odm-resourcemanager_cliffs_mtp.xml` | EN EL PC |
| WCD9395 | no lleva firmware (regmap SDW) | — | — |
| `modem_b` (`sde34`), `dsp_b` (`sde37`, 64 MiB) | modem registries (parche 0028) y `/vendor/dsp` (libs fastrpc del audio PD, solo si hiciera falta) | `/dev/disk/by-partlabel/{modem_b,dsp_b}` | LOCALIZADOS |
| BT `msbtfw12.mbn`, `msnv12.bin` | solo para la vía Bluetooth | `R/build/android/msbtfw12.mbn`, `msnv12.bin` | EN EL PC |

---

## 5. Riesgos y vigilancia del ADSP (aplican a E2 en adelante)

**Por qué es el riesgo principal.** El ADSP lleva `battmgr` y el cargador (`battmngr_*` en su imagen). `recovery_disabled=true` y el parche 0033 advierten que el camino SLIM/DMA no está
cualificado: un fallo del audio puede dejar el remoteproc en `crashed` y la carga parada sin recuperación automática. Además USB/SSH dependen de `pmic_glink`/`battmgr`.

**Qué puede provocar el crash en audio (INFERIDO):** (a) acceso DMA del LPASS a buffers de Linux sin contexto SMMU (SID 0x1000-0x13ff, `lpass_qtb` `qcom,stream-id-range=<0x1000 0x400>`;
con `ARM_SMMU_DISABLE_BYPASS_BY_DEFAULT=y` un SID sin SMR aborta); (b) comandos APM malformados / grafo inválido; (c) votos PRM de reloj incoherentes; (d) reset del WCD9395
con el ADSP usando sus rails/pines.

**Detección (spec de un vigía de solo lectura, a armar antes de cada etapa que toque el ADSP; análogo a `uke-fastboot-watch`):**
1. `cat /sys/class/remoteproc/remoteproc1/state` ≠ `running` (alarma inmediata); `recovery` debe seguir `disabled` salvo decisión expresa.
2. `dmesg -w` filtrado: `crash detected in adsp`, `fatal error`, `watchdog`, `q6v5`, `Unhandled context fault`, `arm-smmu`, `PDR:` (estado de `msm/adsp/audio_pd` ≠ UP), `gpr`, `unknown message`.
3. `qcom-battmgr-bat`: `voltage_now` debe cambiar y `status` seguir `Charging` con cargador; si deja de actualizarse o pasa a `Discharging` con cargador = ADSP muerto o PD caído.
4. Doble captura (regla 4 de docs/historia/AGENTS.md): `ssh … 'dmesg -w' > fichero` **y** la consola ACM (un solo lector), porque un cuelgue duro puede cortar la cola.

**Recuperación (documentada en `docs/historia/revision/CARGA-SENEMOS-20261017.md` checklist 9):** `echo stop > /sys/class/remoteproc/remoteproc1/state; echo start > …`; **no** `rmmod pmic_glink`/`qcom_battmgr`;
descargar primero los módulos de audio (`snd*`, `q6*`, `apr`) en orden inverso. Si no vuelve: reset físico; red de seguridad = carga en off-mode del ABL (`docs/historia/revision/ADOPCION-SENEMOS-20261017.md:393-395`). Opción a decidir con el dueño:
activar `recovery` (`echo enabled > …/recovery`) durante los experimentos de audio para que el kernel reinicie el ADSP solo; **no se sabe** si `pmic_glink`/`battmgr` re-enganchan tras un SSR (el PDR de pmic_glink sí está soportado upstream) → probar primero un `stop/start` manual con el ADSP en reposo (ensayo controlado de recuperación, ver E2').

Otros riesgos de SoC (no del ADSP): leer registros del LPASS (macros/LPI) sin relojes votados cuelga el bus (el mainline vota antes, pero el cuelgue no deja traza → doble captura); **nunca** volcar rangos MMIO/regmap ni instrumentar el SMMU (regla 3 de docs/historia/AGENTS.md).
Riesgo para el SSH: el WCD9395 y el usbss comparten rail (`pmxr2230_l7`, refcount del regulador) y encapsulado; un reset del códec (LPI gpio12) no debería tocar el usbss (gpio119), pero está sin medir → tener **WiFi/SSH como canal de gestión alternativo** al RNDIS antes de E5.

---

## 6. Plan por etapas (de menor a mayor riesgo)

Leyenda: **ADSP** = toca el ADSP; **Flash** = requiere reflashear `boot_a` (un cambio por ciclo + ledger + gates, reglas de docs/historia/AGENTS.md); **HW** = toca hardware de audio.

| Etapa | Qué | ADSP | Flash | Riesgo | Criterio de "hecho" |
|---|---|---|---|---|---|
| **E0** | Preparación en el PC: (a) esbozar el overlay DT de audio a partir de `sm8650.dtsi`/`sm8650-qrd.dts`; (b) topología `qcom/sm8650/UKE-tplg.bin` desde `SM8550-HDK.m4` con `alsatplg`; (c) diseñar el cambio al transform del ABL (`uke_scope_smmu_clients`, `uke_scope_qup_buses`, `dmas` de 5→3 celdas o sin `dmas`); (d) leer en frío `super`→`odm_b` y volcar el ACDB `Forte` al PC (solo lectura, sin redistribuir); (e) RE de `fs19xx_dlkm.ko` v4.0.7 y del `.fsm`; (f) escribir el vigía de ADSP (§5) y el módulo cargador de overlays (`of_overlay_fdt_apply`, exportado `drivers/of/overlay.c:1090`) | no | no | **nulo** (la lectura de `super` es un `dd` de solo lectura) | ficheros listos y revisados; sin tocar la tablet salvo la lectura de `super` |
| **E1** | Sumidero software para Omarchy: sink nulo de PipeWire o `modprobe snd-aloop` (módulo presente). Solo para que la barra/volumen tengan dispositivo; **no es audio de la tablet** | no | no | **nulo** para el ADSP/HW (solo software) | `wpctl status` con un sink; sin cambios en remoteproc |
| **E2'** | (opcional pero recomendado) ensayo controlado de `stop`/`start` del ADSP con la tablet en carga y el vigía armado, para conocer el resultado real de una recuperación | **sí** (la carga se interrumpe unos segundos) | no | **medio-bajo**; si el ADSP no vuelve: reset físico + carga off-mode | mismo `adsp running`, `Charging` y `battmgr` respondiendo tras ≤45 s; decide si se usa `recovery=enabled` |
| **E2** | **Primera conversación AudioReach, sin card ni SMMU nuevo**: cargar el overlay en caliente (módulo cargador) que solo añade bajo `/soc/remoteproc-adsp@03000000/glink-edge/qcom,gpr` los servicios `service@1 qcom,q6apm` y `service@2 qcom,q6prm` (+`q6prmcc`) **con `qcom,protection-domain`**, **sin** `dais`/`bedais` (no hay `iommus`), y `modprobe apr q6core snd-q6apm q6prm q6prm-clocks` (cargar `apr` es lo que abre `adsp_apps`). `q6apm` envía `APM_CMD_GET_SPF_STATE` (igual que Android `01-dmesg.txt:8204`) y `q6prm` comprueba `q6apm_is_adsp_ready()` | **sí** | **no** (overlay en caliente) | **bajo**: es el primer comando que ya manda Android al arrancar y no hay DMA ni votos de reloj; riesgo residual: apertura del canal GLINK y PDR de `avs/audio` por primera vez | dmesg: `PDR … audio_pd` UP + q6apm/q6prm probe sin errores; `remoteproc1 running` 30 min; `battmgr` vivo; `lsmod` solo con los módulos esperados. Descarga limpia (`rmmod` en orden inverso) |
| **E3** | Votos de reloj PRM y LPI pinctrl: añadir `q6prmcc` consumidores mínimos (p. ej. `LPASS_HW_MACRO_VOTE`/`DCODEC_VOTE`), `pinctrl-sm8650-lpass-lpi` con los 23 pines (verificar tabla contra cliffs; INFERIDO igual que sm8650) | **sí** (PRM) | no | **medio**: votos de reloj/LPASS; sin DMA | `lpass_tlmm` registrado; pines legibles por gpiolib **sin** tocar el mux; ADSP estable |
| **E4** | **DMA/SMMU sin hardware de salida**: admitir en el SMMU los SIDs `0x1001/0x80`,`0x1061` (cliente `q6apmdai`), cargar `q6apm-dai`+`bedais` y reproducir hacia una interfaz **sin cableado conocido** (candidata: otra MI2S/I2S que no sea TDM1 ni gpio12; verificar, INFERIDO) con topología mínima, o a `CODEC_DMA_RX_0` sin códec. Objetivo: ver avanzar el puntero PCM/`pcm_period` sin faults. El transform del ABL deshabilita los `iommus` hacia ese SMMU antes de que exista el overlay, y el overlay llega después, así que INFERIDO que en caliente es posible (pregunta 6 de §7); si `arm-smmu` no lo acepta en runtime, **Flash** de un `boot` con el transform ajustado | **sí** | probable no; si hace falta, sí (1 cambio, 1 fila de ledger) | **medio-alto**: primera transferencia DMA del LPASS hacia memoria de Linux; el escenario de crash descrito en §5(a) | PCM avanza sin `arm-smmu … fault`, ADSP `running`, `Charging`; repetido 3 veces sin deriva; si falla, nota "refutada" a los 3 ciclos (regla 11) |
| **E5** | WCD9395 + SoundWire + macros RX/TX/VA (captura DMIC sin amps): `qcom,wcd9395-codec` con `reset-gpios=LPI gpio12`, masters `qcom,soundwire-v2.0.0`, macros `sm8550`; card `qcom,sm8650-sndcard` con enlaces de captura. Enumeración SDW y comprobación del part-id real del 9395 (el `SDW_SLAVE_ENTRY(0x0217,0x10e)` del driver es WCD9390/95, a confirmar). Aclarar quién alimenta los DMIC y qué grupo de pines los lleva (§1.1 #14-16) | **sí** | no (si E4 fue en caliente) | **alto**: pulsa el reset del WCD (LPI gpio12), accede a MMIO de macros (cuelgue duro si faltan relojes), comparte rail con el usbss (riesgo para el USB/SSH); tener WiFi/SSH como canal y doble captura | `/sys/bus/soundwire/devices/*` con los 2 slaves, `arecord -l` con captura, un buffer de DMIC con señal no nula |
| **E6** | Playback por el WCD (CODEC_DMA RX0 → rx-macro → SWR → WCD9395) a "ninguna parte" (sin jack), solo para validar el grafo de reproducción de punta a punta con piezas 100 % mainline | **sí** | no | **medio-alto** (misma superficie que E5 + RX) | `aplay` a un dispositivo WCD sin xruns; ADSP estable |
| **E7** | **Altavoces**: (1) habilitar `i2c@88c000` en el transform (con DMA traducido o en FIFO, sin `dmas`) → **Flash**; (2) driver FS19xx (porteo del vendor + lectura de `fs19xx.fsm`; DEVID 0x2900), reset/IRQ GPIO, escenas por canal (`FSM_Scene` 7/9/11/13 = tl/tr/bl/br); (3) soporte TDM en `q6apm-lpass-dais`/`audioreach.c` + topología con la interfaz LPAIF_VA/TDM1 (parámetros desde el ACDB `Forte`); (4) pinmux LPI gpio6-9 func2 (resolver el conflicto con DMIC01/23); (5) **tope de volumen**: sin el algoritmo `FSADSP` (protección de excursión) no hay protección de altavoz del lado ADSP | **sí** | **sí** (varios ciclos: I2C, driver, TDM) | **alto**: ADSP (TDM+SMMU), riesgo de **daño de altavoz** si se sube el volumen sin la protección del vendor (INFERIDO), amps desconocidos | tono de 1 kHz a −40 dBFS audible por los 4 altavoces, amps en `FSM_Stop` al terminar; ≤2 escrituras/día (presupuesto de docs/historia/AGENTS.md) |
| **E8** | Integración de usuario: UCM (`ucm2/Qualcomm/sm8650/<model>`), WirePlumber, perfiles `HiFi`, jack/USB-C, mic | no | no | bajo | `wpctl` con sink/source reales |

**Vías sin ADSP (decisión):**
- **Altavoces/mics/WCD sin ADSP: no existe camino realista.** Los datos salen del LPASS (TDM1/CODEC_DMA/SWR), controlado por el ADSP; los 4 amps no tienen entrada I2S independiente (el bus TDM1 es LPI gpio6-9, dominio LPASS). Evidencia §1.1 #12-13.
- **Bluetooth A2DP (recomendado como primera salida audible):** WCN6750 (QCA, UART `qcom,qup_uart@888000`, FW `msbtfw12.mbn`/`msnv12.bin` ya en el PC), audio por host (SBC/AAC en PipeWire), **no pasa por el ADSP**. Requiere `hci_uart` (hoy en la guarda) y `bluez`; comparte rails con el WiFi/WPSS (riesgo de interferir con WiFi, cuyo trabajo va aparte). Estado BT del proyecto: pendiente (`ESTADO-VIVO` paso 3). Esto es trabajo de otra línea, no de ésta.
- **USB audio:** descartado por ahora: el puerto está en modo gadget (SSH/ACM) y el host mode está "incompleto" aguas arriba (`github.com/MCC45TR/senemos-uke-kernel-mainline`, 15-oct); el VBUS-out depende además del ADSP (`ucsi_glink` bloqueado).
- **UAC2 gadget (la tablet como tarjeta de sonido hacia el PC):** sirve para probar PipeWire sin hardware, pero exige `CONFIG_USB_CONFIGFS_F_UAC2` (hoy no) → Flash; no aporta sonido en la tablet. Poco valor frente a E1.
- **DP audio:** también por ADSP.

---

## 7. Preguntas abiertas / hipótesis a refutar

1. ¿Responde `q6apm` del mainline a este ADSP (LANAI 954.6)? (E2 lo decide; evidencia a favor: IDs PRM idénticos y `APM_CMD_GET_SPF_STATE` como en Android.)
2. ¿Hace falta `audioadsprpcd audiopd` (fastrpc, PD de audio)? INFERIDO que no: upstream sm8650 reproduce sin él (la card usa el audio_pd estático vía `avs/audio`); sin refutar. Nota: `adspua.jsn`/`adspr.jsn` están en `firmware_mnt/image` (`sistema-20261017/firmware-sha.txt`), no usados hoy.
3. ¿Qué módulo del ADSP maneja el TDM del VA y con qué parámetros? Solo el ACDB `Forte` lo dice (E0-d).
4. ¿Qué grupo DMIC lleva los micros y quién los alimenta? Android no se puede re-capturar sin wipe; salidas posibles: ACDB/`resourcemanager` + medir en E5 con el WCD arriba.
5. ¿Los masters SWR `v2.1.0` (HW) aceptan el compat `v2.0.0` de mainline? (El vendor imprime el desajuste y funciona.)
6. ¿Basta el overlay en caliente para E4 (SMMU)? El transform corre antes de que Linux vea el DT, así que un overlay posterior no lo hereda; falta confirmar que `arm-smmu` acepta un cliente nuevo con `iommus` en runtime sin SMR de handoff.
7. Modelo exacto del FS19xx (solo DEVID 0x2900).
8. Si `OF_OVERLAY` aplica cambios de `status` y crea los platform devices al vuelo: `of_reconfig_get_state_change()` (`drivers/of/dynamic.c:111-193`, `platform.c:735`) lo hace para nodos existentes, y los hijos I2C los crea el core al registrar el adaptador (INFERIDO, sin probar en esta tablet).

## 8. Primer paso propuesto

**E0 + E1** (riesgo nulo). El primer paso que toca el ADSP con información útil es **E2** (overlay en caliente + `apr/q6apm/q6prm`, sin card ni SMMU nuevo): **riesgo bajo**, con el vigía armado y la ruta de recuperación (E2' como ensayo previo si el dueño lo autoriza). No hay que flashear nada hasta E4/E7.

## 9. Lo que NO se hizo

Nada de lo siguiente: cargar `apr`/`q6*`/`snd*`, escribir sysfs, tocar remoteproc, editar blacklists, reiniciar, fastboot, volcar MMIO. No se extrajo ni se copió el ACDB (solo se localizó `super`). No hay commit (por encargo).

## 10. Reproducción (todo solo lectura)

```bash
# DT vivo: helper que se pasa por stdin (no escribe en la tablet)
cat > dtdump.sh <<'EOF'
#!/bin/bash
for n in "$@"; do d=/proc/device-tree/$n; echo "=== $n"
  for f in "$d"/*; do [ -f "$f" ] || continue; b=$(basename "$f"); sz=$(stat -c %s "$f")
    [ "$sz" -eq 0 ] && { echo "  $b (bool)"; continue; }; [ "$sz" -gt 400 ] && { echo "  $b [${sz}B]"; continue; }
    if tr -d '\0' < "$f" | grep -q -E '^[[:print:]]+$' && [ "$(tail -c1 "$f" | xxd -p)" = "00" ]; then
      echo "  $b = \"$(tr '\0' '|' < "$f" | sed 's/|$//')\""; else echo "  $b = <$(xxd -p "$f" | tr -d '\n')>"; fi
  done; done
EOF
ssh -i build/rootfs/uke-arch-root -o BatchMode=yes root@192.168.42.129 'bash -s -- soc/spf_core_platform/sound soc/spf_core_platform/lpass-cdc soc/qcom,qupv3_1_geni_se@8c0000/i2c@88c000 soc/remoteproc-adsp@03000000/glink-edge/qcom,gpr' < dtdump.sh
# estado ADSP / canales / módulos
ssh … 'for r in /sys/class/remoteproc/remoteproc*; do echo $r $(cat $r/name $r/state $r/recovery); done; ls /sys/bus/rpmsg/devices; lsmod | cut -d" " -f1 | tr "\n" " "'
# módulos de audio disponibles en ouke3
ssh … 'cd /lib/modules/7.2.9-senemos.1.4054.3-ouke3/kernel && find sound drivers/soundwire drivers/soc/qcom/apr.ko drivers/pinctrl/qcom -name "*.ko*"'
# super: magic LP (1 bloque)
ssh … 'dd if=/dev/disk/by-partlabel/super bs=4096 skip=1 count=1 2>/dev/null | head -c4 | xxd -p'   # 67446c61
# firmware ADSP (en el PC)
cat R/charge/firmware/adsp.b* | strings -a -n 6 | grep -E 'IMAGE_VARIANT|Q6_BUILD|LPAIDSP|FSADSP|apm_gpr'
```
