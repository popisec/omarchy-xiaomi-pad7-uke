# P8 — AUDIO Y PERIFÉRICOS (audio, haptics, LED, USB-C/DP, GPS/NFC)

Preparador: P8-AUDIO-PERIFERICOS · fecha: 2026-09-29 madrugada · **sin tablet** (prohibido
fastboot/adb/ssh/ttyACM0; solo lectura de logs). No se ha modificado nada fuera de
`build/gates/prepara/`. No se ha tocado `/var/tmp/uke-k1` (solo lectura).

Fuentes usadas (todas de solo lectura):
- `~/proyectos/ubuntu-permanente/criticas/ufs-referencia-android/dmesg-android.txt` (dmesg stock)
- `~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img` → `fdtdump` a `/var/tmp/p8/base-dtb.dts` (DT SoC cliffs)
- `~/proyectos/ubuntu-uke/devicetree/uke.dts` (DTBO vendor descompilado, **la fuente buena de placa**;
  `stock/dtbase/base-uke.dts` para direcciones de bus)
- `~/proyectos/out/p1-vivo...` = `~/proyectos/ubuntu-uke/dump/p1-vivo-20260903/dmesg.txt` (dmesg vivo stock)
- `~/proyectos/out/wifi-dmesg-r10e.log` (arranque mainline 26-sep con ADSP up), `uke-adsp-load.log`,
  `uke-console-viva.log`, `k6-migas.log`, `k6b-migas.log`
- `/var/tmp/uke-k1` + `/var/tmp/uke-k1-build/.config` (config del kernel que vuela hoy)
- `~/proyectos/ubuntu-uke/stock/INVENTARIO-VENDOR-UKE.md`, `HARDWARE-KNOWN-PLAN.md`,
  `~/proyectos/omarchy-uke/NOTAS-OMARCHY.md` (ledger #404–408, #442)
- Upstream: `git.kernel.org` (mainline `sound/soc/qcom`, `sound/soc/codecs`, `sc8280xp.c`,
  `linux-firmware/qcom` no accesible por timeout)
- Firmware: `~/gpu-work/uke-rom-edl/.../images/dspso.bin` (ext4, `debugfs`), `~/gpu-work/ramaa/s24/adsp-fw/`

---

## 0. Resumen ejecutivo

| Periférico | Hardware en la uke | Vía mainline HOY | Veredicto |
|---|---|---|---|
| **Audio altavoces** (4× Foursemi FS19xx en TDM de la VA-macro) | Sí, 4 smart PA en I2C (SE11, 0x34–0x37) | **No.** Falta driver codec FS19xx + DAI-links DT + `.tplg` | **No hoy.** Mayor brecha: **codec driver FS19xx** (bloquea el sonido) y el `.tplg` |
| ADSP (base de todo el audio) | Sí | **Sí**: ya arranca en mainline (evidencia r10e) | Listo a nivel kernel; en Arch falta servicio+firmware |
| Audio por USB-C (puente) | UAC por host USB | Parcial: `SND_USB_AUDIO=m`, pero **host USB no probado** (hoy solo gadget ttyGS0) | **Tampoco hoy**; más corto arreglar el codec |
| Audio por BT (WCN6750) | Sí | WCN6750 BT sin camino (el frente WiFi sigue abierto) | No hoy |
| **Haptics** | **NO HAY MOTOR** (`ro.odm.mm.vibrator.motor_not_support=true`) | N/A | **Descartado** (nodo PMIC es decorado) |
| **LED** | tri-led PWM del PMIC + flash LED "ok" en DT, población física sin confirmar | Compatibles incompatibles (AOSP vs mainline) | Poco valor; verificación barata |
| **USB-C rol/PD/altmode** | pmic_glink+UCSI+altmode, wcd939x-usbss | Drivers existen; **ucsi_glink panickea hoy**; altmode necesita `drm_aux_hpd_bridge` | **Arreglable** (bloqueo concreto y acotado) |
| **DP externo** | dp_display@ae154000 + PHY combo sm8650 | Driver DP en mainline soporta `qcom,sm8650-dp`; PHY cliffs sin verificar | Bloqueado por **DPU/display** (dependencia) |
| **GPS/GNSS** | **No existe** (sin nodo gnss en DT) | N/A | Descartado |
| **NFC** | Solo **etiqueta NFC** Xiaomi (`fm,fm19511`, "MI-NFCTAG" en I2C 0x57); no hay lector NFC | Sin driver mainline | Descartado (no aporta) |

---

## 1. AUDIO

### 1.1 La cadena física que exige cliffs (según DT vendor + dmesg stock)

```
[APSS] ──remoteproc PAS("qcom,cliffs-adsp-pas", 0x3000000)──► [ADSP / audio PD "avs/audio"]
   │                                                              │
   │ GPR (glink "adsp_apps", reg=0x02)                            │ AudioReach (SPF)
   ▼                                                              ▼
[q6apm (APM) + q6prm (LPASS clocks)]  ◄──── q6prmcc (LPASS_HW_*_VOTE, MCLK)
   │
   ├─ BE LPAIF TDM "TDM-LPAIF_VA-*" ──► 4× FS19xx smart PA (I2C, 0x34/35/36/37) ──► 4 altavoces
   ├─ WSA-macro SWR .......... NO HAY AMPLIFICADORES WSA ("Unexpected number of WSAs, wsa_max_devs: 0")
   ├─ RX/TX macro SWR ──► WCD939x (SDW: mics SWR_MIC0..3 y ruta de captura/USB-C)
   └─ VA-macro ──► DMIC1..6 (pines LPI del VA macro, pinctrl dmic01..dmic67)
```

Datos duros de la uke (no del QRD):
- Machine driver stock: **`pineapple-asoc-snd`** sobre `spf_core_platform:sound`, compatible
  `"qcom,pineapple-asoc-snd"` (base-dtb.dts:12943 → `sound{compatible="qcom,pineapple-asoc-snd";
  qcom,ext-disp-audio-rx=0; qcom,wcn-bt=0; qcom,auxpcm-audio-intf=1; qcom,mi2s-audio-intf=1}`).
- 4 smart PA **Foursemi `foursemi,fs16xx`** (chip FS19xx) en `/soc/qcom,qupv3_1_geni_se@8c0000/i2c@88c000`
  (qupv3_se11, **SDA/SCL = tlmm 44/45**), 0x34–0x37, con reset/IRQ:
  | I2C | reset (tlmm) | irq (tlmm) | nombre vendor |
  |---|---|---|---|
  | 0x34 | 30 | 47 | top_left |
  | 0x35 | 149 | 69 | top_right |
  | 0x36 | 124 | 31 | bottom_left |
  | 0x37 | 123 | 129 | bottom_right |
  (`uke.dts` fragment@76; pinctrl `fs19xx_irq_*` en fragment@78)
- DAI-links stock: `TDM-LPAIF_VA-RX-PRIMARY`, `TDM-LPAIF_VA-RX-PRIMARY-VIRT-2`, `TDM-LPAIF_VA-TX-PRIMARY`
  → los altavoces cuelgan del **TDM de la VA-macro**, no de SWR.
- Firmware de los PA: `fs19xx.fsm` (falla el load en stock con -13 y cae a sysfs fallback; el vendor
  sigue adelante). Es un smart PA con DSP propio.
- WCD939x presente como códec (SDW rx/tx slave 0x0e), con 4 entradas `SWR_MIC0..3`.

### 1.2 Qué EXISTE ya en nuestro árbol/config (medido)

- **ADSP remoteproc: ya arranca en mainline.** `qcom_q6v5_pas` tiene resource propia
  (`cliffs_adsp_resource`, sin proxy_pd, auto_boot=false) y en el arranque r10e se ve:
  `remoteproc1: powering up adsp` → `Booting fw image adsp.mdt, size 8044` → **`remote processor adsp is now up`**
  + `PDR: Indication received from msm/adsp/charger_pd` y battmgr funcionando. (Evidencia:
  `~/proyectos/out/wifi-dmesg-r10e.log`, líneas ~2523/2533/2547; receta: ledger #404–408 y
  `uke-adsp-load.log`.) Es decir: **el escalón más alto de la cadena está subido.**
- Firmware del ADSP ya extraído: `~/gpu-work/ramaa/s24/adsp-fw/` (58 ficheros: `adsp.mdt` 8044 B sha
  `fd874a8d…`, 49 segmentos `.bNN`, `adsp_dtb.mdt`, `MANIFEST.txt`). Origen: partición `dsp`
  (`dspso.bin` ext4 de la ROM) + `modem/NON-HLOS.bin` para los `.mdt`. Va **plano** a `/lib/firmware/`.
- Config `.config` del kernel vivo:
  `CONFIG_QCOM_Q6V5_PAS=m`, `CONFIG_QCOM_APR=y`, `CONFIG_QCOM_FASTRPC=m`, `CONFIG_QCOM_PMIC_GLINK=m`,
  `CONFIG_QCOM_PDR_MSG=y/PDR_HELPERS=y`, `CONFIG_SND=m`, `CONFIG_SND_SOC_QCOM=m`,
  `CONFIG_SND_SOC_QDSP6=m` (+ q6apm/q6prm/q6apm-dai/q6apm-lpass-dais/audioreach/topology),
  `CONFIG_SND_SOC_LPASS_{RX,TX,VA,WSA}_MACRO=m`, `CONFIG_SND_SOC_WCD939X{,_SDW}=m`,
  `CONFIG_SND_SOC_WSA884X=m`, `CONFIG_SND_SOC_QCOM_SDW=m`, `CONFIG_SND_USB_AUDIO=m`,
  `CONFIG_SND_SOC_USB=m` (+ offload, para el USB-C offload).
- **Machine driver: EXISTE y ya matchea nuestro SoC.** `sound/soc/qcom/sc8280xp.c` (upstream, verificado
  en kernel.org) tiene `{ .compatible = "qcom,sm8650-sndcard", ... }` (y sm8550/sm8750). Es un driver
  genérico que **construye la tarjeta a partir de los `dai-link` del DT** (`qcom_snd_parse_of`), aplica
  fixups y helpers SDW. **No hay que escribir machine driver nuevo**; hay que escribir el *sound node*
  con sus dai-links en el DTS de uke. OJO: **hoy no está compilado** —
  `# CONFIG_SND_SOC_SC8280XP is not set` en `/var/tmp/uke-k1-build/.config` (sus deps sí:
  `QCOM_APR=y`, `SOUNDWIRE=m`, `SOUNDWIRE_QCOM=m`). Es una línea de config: `CONFIG_SND_SOC_SC8280XP=m`.
- El SoC ya trae el plumbing de audio en `palawan.dtsi` (= `sm8650.dtsi` upstream, 2860–2910):
  `remoteproc_adsp` con `glink-edge`, `gpr` con `q6apm` (`bedais`/`dais`) y `q6prm`
  (`q6prmcc`), y los cuatro `codec@6ac0000/6ae0000/6b00000/6d44000` con compatibles
  `qcom,palawan-lpass-*-macro` + fallback `qcom,sm8550-lpass-*` (driver mainline). El `lpass_tlmm`
  (pinctrl LPI) con estados `rx_swr/tx_swr/dmic01..67` también está.
- **Codecs de la familia correcta** en el árbol: `lpass-rx/tx/va/wsa-macro`, `wcd939x`, `wsa884x`.
- Topology: la carga es `qcom/<card->driver_name>/<card->name>-tplg.bin`
  (`sound/soc/qcom/qdsp6/topology.c:1312`, `audioreach_tplg_init`). **No existe ningún `.tplg` para
  sm8650/uke ni en el árbol ni (hasta donde se ve) en linux-firmware.**

### 1.3 Qué NO existe (y es lo que bloquea)

1. **Driver codec para los altavoces FS19xx**: no hay `foursemi,fs16xx` en el árbol ni en mainline
   (búsqueda en `sound/soc/`: 0 coincidencias). Sí existe, y es una **plantilla muy cercana**:
   `sound/soc/codecs/fs210x.c` + `fs-amp-lib.[ch]` (upstream, "FS2104/5S", compatible
   `foursemi,fs2105s`) — mismo fabricante, misma familia de registers; `CONFIG_SND_SOC_FS210X` no está
   seteado (da igual: el chip es otro). El vendor tiene `fs19xx_dlkm.ko` (no está en
   `stock/modules/`, sí en la ROM).
2. **`sound` node + dai-links de placa** en nuestro DTS: hoy `xiaomi-uke.dts` (556 líneas) no tiene
   absolutamente nada de audio (ni `sound`, ni I2C de los PA, ni `lpass` habilitado).
3. **Topology `.tplg`** de AudioReach para esta placa (grafo APM→TDM VA→codec). Sin ella, los PCMs de
   `q6apm-dai` no tienen grafo que abrir → no hay tarjeta sonando aunque todo lo demás esté.
4. No hay `wcd939x-i2c`/`wcd-usbss` en el árbol para la parte I2C del códec (sí está
   `drivers/usb/typec/mux/wcd939x-usbss.c`, compatible `qcom,wcd9390-usbss`), pero eso solo afecta a la
   ruta USB-C/BU y a la conmutación SBU, **no a los altavoces**.

### 1.4 Las 3 brechas ordenadas por dificultad (para poner los altavoces a sonar)

| # | Brecha | Tamaño | Notas |
|---|---|---|---|
| **1** | **ADSP persistente en Arch** (firmware + módulos + `uke-adsp.service`) | **Pequeña, 0 recompilas** | Ya probado en Ubuntu. En los logs de Arch (`uke-console-viva.log`) el servicio existe y **falla**; el volcado de la consola no enseña el porqué → primer paso: `systemctl status uke-adsp` / journal. Sin ADSP no hay nada. |
| **2** | **Codec driver FS19xx + DAI-links DT** | **Mediana-grande** | Portar el driver vendor (`fs19xx_dlkm`, ~1–2 k líneas) al modelo ASoC mainline usando `fs210x.c`+`fs-amp-lib` como plantilla (I2C regmap, DAPM, sound-name-prefix, reset/IRQ GPIOs, `.fsm` opcional). Añadir a `xiaomi-uke.dts`: habilitar `i2c@88c000` (SE11) + 4 nodos `foursemi,fs16xx` + `sound{compatible="qcom,sm8650-sndcard"}` con dai-links (FE `q6apmdai`, BE `q6apmbedai` TDM-VA ↔ codec). |
| **3** | **Topology `.tplg` AudioReach** | **Grande y opaca** | Hay que generar `qcom/<driver_name>/<card name>-tplg.bin` (tooling `alsatplg` + fuentes de grafo AudioReach) e iterar contra el firmware ADSP de Xiaomi. Es la parte con más incógnitas (nombres de módulos/IDs del firmware vendor). |

**Estimación honesta** (sin tablet, con la tablet delante): brecha 1 = 1 sesión; brecha 2 = **1–2 semanas**
de trabajo de driver+DTS (con hardware para probar); brecha 3 = **1–3 semanas** más de iteración (o
aparece alguien con un `.tplg` de SM8650 y baja a días). **Sonido estéreo funcional: ni hoy ni por un
truco; es un frente de semanas, pero la base (ADSP+APM+clocks) ya está y no hay que inventar machine
driver.** Si se quiere solo *un* PCM de prueba antes, el orden es 1 → 2 → 3; no hay atajo que salte el
codec (los PA no se despiertan sin I2C).

### 1.5 Alternativa puente

- **USB-C audio (UAC)**: `CONFIG_SND_USB_AUDIO=m` está; un dongle USB-C con DAC debería funcionar en
  cuanto exista **host USB**. Hoy el dwc3 solo se usa como **gadget** (`configfs-gadget.g1`, consola
  `ttyGS0`); no hay evidencia de `xhci`/host en ningún log. → El puente depende de un frente que aún no
  está (host USB), y encima hace falta el role-switch (pmic_glink) que sí está a medias.
- **BT audio**: el offload está declarado en el vendor (`qcom,wcn-bt=0` y WCN BT support en stock) pero
  el WCN6750 en mainline está en plena pelea (ledger r9/r10) → no es un puente realista ahora.
- Conclusión: **el camino más corto al sonido es el propio codec FS19xx**, no un puente.

---

## 2. HAPTICS

**Veredicto: la uke NO tiene motor de vibración. No hay nada que preparar.**

Evidencia (esta unidad, stock):
- `ro.odm.mm.vibrator.motor_not_support = true` (`dump/20260903-073613/system/props-root.txt`).
- `dumpsys input`: `support Vibrator:false` (la línea `enable system haptic vibrator:true` es solo una
  feature del teclado).
- En dmesg stock el framework no encuentra `android.hardware.vibrator.IVibrator/default` ("No
  alternative instances declared in VINTF").

Lo que sí hay en DT (y por qué no significa nada):
- `pm7550ba@7/qcom,vibrator@df00` con `compatible="qcom,qpnp-vibrator-ldo"`, `status="okay"`,
  `qcom,vib-ldo-volt-uv=0x2dc6c0`, `qcom,disable-overdrive` — es el nodo por defecto del PMIC.
- `swr_haptics@f0170220` (`qcom,pm8550b-swr-haptics`) en `rx_swr_master`: **`status="disabled"`**.
- Los módulos vendor `awinic_haptic` (v0.5.1.1) y `sih_haptic` cargan en Android pero **no bindean**
  (no hay nodos I2C para ellos en el DT): ruido del kernel vendor.

Mainline: `drivers/input/misc/pm8xxx-vibrator.c` soporta `qcom,pm8058-vib / pm8921-vib / pm8916-vib /
pmi632-vib`; **no hay compatible para `qcom,qpnp-vibrator-ldo`** ni driver `swr-haptics`.
Usuario: Hyprland/Quickshell/Omarchy no tienen nada que integrar aquí (no hay `feedbackd` ni
`libfeedback` que rascar: sin hardware). Coste de verificación en el día D: 30 s
(`ls /sys/class/input/`, `cat /proc/bus/input/devices | grep -i vib`, y comprobar que no existe
`/sys/class/leds/*vib*`). **No gastar más tiempo aquí.**

---

## 3. LED / carga

DT (`uke.dts`, nodos heredados del PMIC, no de placa):
- `qcom,leds@ef00` `compatible="qcom,tri-led"` con 3 hijos `red/green/blue` (`pwms` del LPG,
  `linux,default-trigger="timer"`). Sin `status` explícito → "okay".
- `qcom,flash_led@ee00` `compatible="qcom,pm8350c-flash-led"`, `status="ok"`, con 4 `flash_*`,
  4 `torch_*` y switches (driver AOSP `qti-flash`, que en stock **sí probea**: "qti-flash:
  get_custom_max_current: flash led no custom max current count found").
- No hay evidencia en los dumps de LEDs visibles (no capturamos `/sys/class/leds`); en la Pad 7 no hay
  indicador de notificación ni flash trasero de cámara que yo pueda confirmar documentalmente →
  **probablemente son nodos decorativos del PMIC**, pero es barato comprobarlo.

Mainline: `drivers/leds/rgb/leds-qcom-lpg.c` tiene `qcom,pm8350c-pwm`/`pmk8550-pwm`… pero **no el
compatible `qcom,tri-led`** (grep exacto: 0 coincidencias). El flash mainline
(`drivers/leds/flash/leds-qcom-flash.c`) solo matchea `qcom,spmi-flash-led`, **no** `pm8350c-flash-led`.

Integración/plan (poco valor, 0 prisa):
1. En el día D: `ls /sys/class/leds; for l in /sys/class/leds/*; do echo 255 > $l/brightness; done`
   y mirar. Si no sale luz, cerrar el tema (hardware ausente).
2. Si sale luz y se quiere integrar: [RECOMPILA DTS] reescribir el nodo tri-led a la forma
   `qcom,pm8350c-pwm` (o añadir compatible `qcom,tri-led` al driver LPG, ~20 líneas) y, para el flash,
   pasar el nodo a `qcom,spmi-flash-led`.
3. **Carga/batería** (lo útil): `qcom_battmgr` vía pmic_glink **ya funciona** con el ADSP arriba
   (`qcom-battmgr-bat/usb/wls` en `/sys/class/power_supply`; payload Xiaomi 0x13 parcheado). No tiene
   nada que ver con LEDs.

---

## 4. USB-C / altmode DP

DT vendor:
- `qcom,pmic_glink` con hijos `qcom,ucsi` (`compatible="qcom,ucsi-glink"`) y `qcom,altmode`
  (`qcom,altmode-glink`, `#altmode-cells`) + `connector` (`usb-c-connector`) enlazado a `ssusb@a600000`
  (base-dtb.dts:10903-10928 y ciclos de dependencia en todos los dmesg).
- `qcom,dp_display@ae154000` con `qcom,altmode-dev`, USBs: `hsphy@88e3000`
  (`qcom,usb-snps-eusb2-phy`), `qcom,usb-ss-phy` zebra (el stub `usb_dp_qmpphy@88e8000` sigue **TODO**
  en nuestro `sm7675.dtsi`, cf. HARDWARE-KNOWN-PLAN §"Aceptado F2"), `eusb2-repeater@fd00` en pm7550ba.
- Switch SBU/BU: `wcd939x_i2c@e` en `qupv3_0/i2c@a80000` (`qcom,wcd939x-i2c`, reset tlmm 119,
  `qcom,dp-aux-switch`, nvmem `usb_mode`, `wcd-usb-sbu-compliance`).

Mainline, qué hay y qué no:
- `drivers/soc/qcom/pmic_glink.c`, `drivers/usb/typec/ucsi/ucsi_glink.c` y
  `drivers/soc/qcom/pmic_glink_altmode.c` **están en el árbol** y la config los tiene
  (`QCOM_PMIC_GLINK=m`, `UCSI_PMIC_GLINK=m`). `DRM_AUX_BRIDGE=y` y `DRM_AUX_HPD_BRIDGE=m` (esto último
  es nuevo: en el arranque r10e `pmic_glink_altmode` no cargaba por "Unknown symbol
  devm_drm_dp_hpd_bridge_alloc / drm_aux_hpd_bridge_notify"). → En el prólogo hay que **cargar
  `drm_aux_hpd_bridge` antes** de `pmic_glink_altmode`.
- **Bloqueo concreto y actual: `ucsi_glink` panickea al probar.** En `wifi-dmesg-r10e.log`
  (26-sep 22:58, líneas 2296–2360): tras `pmic_glink_altmode: Unknown symbol…`, la carga de
  `ucsi_glink` acaba en `Unable to handle kernel execute from non-executable memory…` con la traza
  `pmic_glink_ucsi_probe+0x2d0/0x2f0 [ucsi_glink] → _dev_err → device_node_string → fwnode_get_name`.
  Es un `dev_err` con `%pOFn` sobre un fwnode inválido (`ucsi_glink.c:432`, "missing reg property of
  %pOFn"): el probe falla porque el nodo `connector`/hijo no tiene lo que espera y **al imprimir el
  error revienta** (puntero basura). Hay que (a) dar al DT el/los hijos con `reg` que espera el driver, y
  (b) blindar ese `dev_err` (es un bug de diagnóstico fácil: usar `fwnode_get_name()` con check).
- Nuestro `xiaomi-uke.dts` **ya** tiene el nodo `pmic-glink` (`qcom,lamma-pmic-glink` + fallback
  `qcom,sm8550-pmic-glink`) con `connector@0` y `orientation-gpios = <&tlmm 122>` (valor QRD, **TODO
  confirmar** en el DT vendor). Puede que el fallo del `ucsi_glink` sea justamente que al `connector@0`
  le faltan subnodos/ports que el driver recorre.
- DP externo: el driver `msm` **soporta `qcom,sm8650-dp`** (`dp_display.c` of_match, verificado) y el
  PHY combo tiene `qcom,sm8650-qmp-usb3-dp-phy`; el catálogo DPU `dpu_10_0_sm8650.h` tiene bloques
  `INTF_DP`. Pero: (a) el PHY de cliffs no está mapeado en nuestro DTS (stub/TODO), (b) **el display de
  la uke aún no está cerrado** → DP es dependencia dura de DPU/display. Para el switch SBU, el driver
  mainline existe (`wcd939x-usbss.c`, compatible `qcom,wcd9390-usbss`: habría que añadir el de 939x o
  usar fallback).
- UCSI/PD en sí (rol de datos, cargador, DisplayPort altmode) **es alcanzable**: el ADSP ya arranca,
  pmic_glink ya habla con él, y el único crash es el de `ucsi_glink`.

Plan literal (día D): ver §6.4.

---

## 5. GPS / NFC / otros

- **GNSS: no existe.** No hay nodo `gnss`/`gps` en `uke.dts` ni en el base-dtb (búsqueda explícita: 0
  coincidencias), y la uke es WiFi-only (el ADSP/MPSS está, pero no hay receptor GNSS). **Descartado
  para siempre.**
- **NFC: no hay lector NFC.** El nodo I2C 0x57 es `fm,fm19511` ("NtagDrv: loading FM NTAG I2C driver"),
  y al leer su memoria el propio dmesg stock vuelca:
  `…mi_connect_service:externaltype…MI-NFCTAG…TAG_DISCOVER…MIRROR…02:00:5E:00:00:06` → es una **etiqueta
  NFC de emparejamiento Xiaomi** (Mi Connect / accesorios), no un controlador NFC de tarjetas. El
  módulo `st21nfc` 2.2.0.19 y `stm_nfc_i2c.ko` cargan pero **no hay nodo DT para ST** (no bindea), y
  `init.svc.nqnfcinfo = stopped`. Sin driver mainline ni HAL → **no hay camino hoy y no aporta nada al
  port**. (Si algún día se quisiera leer la etiqueta, sería un driver misc nuevo: no merece la pena.)
- Otros periféricos "de placa" ya viven en otros frentes (no los repito): teclado pogo
  (`xiaomi_keyboard`), lápiz activo (nanosic/novatek), hall lid/table, huella goodix, cámaras, sensores
  (LSM6DSO del ADSP, que **dependen del mismo remoteproc** que el audio: otro motivo para tener el
  ADSP persistente en Arch).

---

## 6. PLAN para cuando haya tablet (pasos literales; `[RECOMPILA]` = requiere recompilar)

### 6.0 Prolegómeno común (audio+typec+LED) — 0 recompilas
0. Ya existe en esta misma carpeta `prepara/`: `uke-adsp-load.sh` + `uke-adsp.service` (preparado por
   otro frente) → usar eso como base y confirmar el arranque del ADSP en Arch antes que nada.
1. `journalctl -u uke-adsp -b --no-pager` y `systemctl status uke-adsp` → entender por qué falla hoy
   (el servicio está instalado pero falla en `uke-console-viva.log`).
2. Firmware ADSP: `ls -l /lib/firmware/adsp.mdt /lib/firmware/adsp_dtb.mdt; ls /lib/firmware/adsp.b* | wc -l`
   (deben ser 49+2; fuente `~/gpu-work/ramaa/s24/adsp-fw/`, o extraer de `dspso.bin` + `NON-HLOS.bin`).
3. Orden de módulos (los del ledger #404, **no built-in** o wedgea el boot):
   `qcom_q6v5_pas qcom_pil_info qcom_common qcom_glink_smem rpmsg_qcom_glink_smem qcom_q6v5` →
   `echo start > /sys/class/remoteproc/remoteprocN/state` → esperar `remote processor adsp is now up`
   y `PDR: Indication received from msm/adsp/<pd>`.
4. Solo entonces: `modprobe pmic_glink qcom_battmgr drm_aux_hpd_bridge pmic_glink_altmode`.

### 6.1 Audio — altavoces
- **Paso 1 (0 recompilas)**: prolegómeno 6.0 + `modprobe snd-soc-qdsp6 snd-soc-sc8280xp
  snd-soc-lpass-rx-macro snd-soc-lpass-tx-macro snd-soc-lpass-va-macro snd-soc-lpass-wsa-macro`
  y anotar si el `q6apm` recibe el PDR `avs/audio` (`dmesg | grep -i 'audio_pd\|q6apm\|tplg'`).
  Aquí ya se ve si el firmware vendor expone APM (esperado: sí, es AudioReach).
- **Paso 2 [RECOMPILA] config + DTS**: en el config `CONFIG_SND_SOC_SC8280XP=m` (hoy `is not set`);
  en `xiaomi-uke.dts`:
  ```dts
  &{/soc@0/qupv3_1_geni_se@8c0000/i2c@88c000} { /* SE11: SDA/SCL tlmm 44/45 */
      status = "okay"; clock-frequency = <400000>;
      spk_tl: speaker@34 { compatible = "foursemi,fs16xx"; reg = <0x34>;
          reset-gpios = <&tlmm 30 GPIO_ACTIVE_LOW>;  irq-gpios = <&tlmm 47 GPIO_ACTIVE_LOW>;
          /* …35: 149/69, 36: 124/31, 37: 123/129 … */ };
  };
  sound { compatible = "qcom,sm8650-sndcard"; model = "Xiaomi Pad 7";
      /* dai-links FE (q6apmdai) + BE (q6apmbedai TDM-VA ↔ fs16xx) al estilo
         de qcom_snd_parse_of; ver plantilla en sm8650-qrd/hdk upstream */ };
  ```
  (Los árboles de referencia exactos: `palawan-qrd.dts` en el árbol no trae tarjeta; copiar la forma de
  un `sound` node de `sm8650-hdk.dts` y adaptar los `dai-link` a TDM-VA + fs16xx.)
- **Paso 3 [RECOMPILA] driver**: portar `fs19xx` a ASoC usando `fs210x.c`+`fs-amp-lib.c` como esqueleto
  (I2C regmap, DAPM, `SOUND_SOC_ENUM`/volume limits, reset+IRQ, firmware `.fsm` opcional desde
  `/lib/firmware/`). Alternativa más rápida: adaptar el `fs19xx_dlkm` vendor (está en la ROM) a la API
  mainline. Probar con `aplay -D hw:0,0` y un WAV.
- **Paso 4**: construir `qcom/sm8650/<card name>-tplg.bin` (alsatplg + fuentes de grafo AudioReach) e
  iterar; si falla, `aplay` dirá "tplg firmware loading … failed" (se ve en dmesg).
- **Atajo a considerar**: antes de escribir el codec, probar si basta con un "dummy codec" para
  verificar que la ruta ADSP→TDM suena en el TDM (no sonará por los altavoces, pero valida
  q6apm+tplg sin depender del driver). Útil para separar variables.

### 6.2 Haptics
- Nada. 30 s de verificación (no hay motor) y cerrar.

### 6.3 LED
- (0 recompilas) `ls /sys/class/leds` → si no hay nada visible, cerrar. Si lo hay y se quiere:
  [RECOMPILA DTS] nodo tri-led a `qcom,pm8350c-pwm` (o patch de 20 líneas al LPG) y flash a
  `qcom,spmi-flash-led`.

### 6.4 USB-C / PD / altmode / DP
1. (0 recompilas) `modprobe drm_aux_hpd_bridge; modprobe pmic_glink_altmode` → debe dejar de dar
   "Unknown symbol"; si carga, `ls /sys/class/typec` / `cat /sys/class/typec/port0/*`.
2. (0 recompilas, lectura) `journalctl -k -b | grep -A40 ucsi` para capturar el Oops completo de
   `ucsi_glink` con la tablet delante y confirmar la rutina que revienta (`ucsi_glink.c:432`).
3. [RECOMPILA] fix del driver (guard en el `dev_err` del fwnode) + DTS: completar los hijos que el probe
   recorre (`connector@0` con sus `ports`/`reg`, y el `qcom,ucsi`/`qcom,altmode` que faltan en nuestro
   `pmic-glink`). Confirmar `orientation-gpios` (¿tlmm 122 del QRD o el real de uke? → DT vendor
   fragment@77/78 y `wcd_usbss` reset tlmm 119, nvmem `usb_mode`).
4. [RECOMPILA DTS] switch SBU: nodo `wcd939x-i2c` (i2c@a80000) + `typec-mux` (`qcom,wcd939x-usbss` /
   fallback `qcom,wcd9390-usbss`) para DP-AUX y compliance.
5. DP externo: **no hasta que DPU/display esté cerrado**; después, mapear `dp_display@ae154000`
   (`qcom,sm8650-dp`) + PHY combo (`qcom,sm8650-qmp-usb3-dp-phy`, verificar regs cliffs) y el
   `drm_aux_hpd_bridge` (dependencia: frente display).

### 6.5 GPS/NFC
- Nada. Documentado como no existente/no aplicable.

---

## 7. Evidencia (para no repetir búsquedas)

- DT placa (cliffs): `/var/tmp/p8/base-dtb.dts` ← `~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img`
  (`sound{compatible="qcom,pineapple-asoc-snd"}` 12943; pmic_glink 10903-10928; dp_display 13480 con
  `qcom,altmode-dev`; lpass-cdc 12913; wcd939x_i2c@e 11779).
- DT uke: `~/proyectos/ubuntu-uke/devicetree/uke.dts` → fs19xx (8679-8730 + fragment@76/78),
  swr_haptics disabled (8207-8213), pm7550ba vibrator@df00 okay (1960-1965 y 3649), tri-led/flash
  (655-700), ntag@57 (2460-2473), wcd_usbss/usbss (8732-8740), sound fragment@72 (4562).
- Buses: `qupv3_se11_i2c = /soc/qupv3_1_geni_se@8c0000/i2c@88c000` (SDA/SCL tlmm 44/45);
  `wcd939x_i2c@e` en `/soc/qupv3_0_geni_se@ac0000/i2c@a80000`
  (`stock/dtbase/base-uke.dts:21394-21427`, 14036, 14286).
- Stock dmesg: `dump/p1-vivo-20260903/dmesg.txt` (fs16xx 4-0034..37 y `.fsm`; machine
  `pineapple-asoc-snd` con `wsa_max_devs: 0`; `fsm_codec_register`; sin vibrator HAL).
- Mainline ADSP up: `~/proyectos/out/wifi-dmesg-r10e.log` (2523/2533/2547/2548) y `uke-adsp-load.log`.
- `ucsi_glink` Oops: `wifi-dmesg-r10e.log` 2296-2360; `ucsi_glink.c:432` en el árbol.
- Kernel: `sound/soc/qcom/sc8280xp.c:166-180` (sm8650-sndcard, upstream confirmado en kernel.org);
  `sound/soc/qcom/qdsp6/topology.c:1312-1336` (ruta y nombre del `.tplg`);
  `sound/soc/codecs/fs210x.c` + `fs-amp-lib.[ch]` (plantilla FourSemi upstream);
  `drivers/input/misc/pm8xxx-vibrator.c:283-289` (sin pm7550ba);
  `drivers/leds/flash/leds-qcom-flash.c:972` (`qcom,spmi-flash-led`);
  `drivers/leds/rgb/leds-qcom-lpg.c:1823-1835` (sin `qcom,tri-led`);
  `drivers/usb/typec/mux/wcd939x-usbss.c:762` (`qcom,wcd9390-usbss`);
  `drivers/phy/qualcomm/phy-qcom-qmp-combo.c:5040` (`qcom,sm8650-qmp-usb3-dp-phy`);
  `drivers/gpu/drm/msm/dp/dp_display.c:172` (`qcom,sm8650-dp`); `dpu_10_0_sm8650.h:353,379` (INTF_DP);
  `drivers/remoteproc/qcom_q6v5_pas.c:1396-1421` (`cliffs_adsp_resource`).
- Config: `/var/tmp/uke-k1-build/.config` (claves citadas en §1.2; `# CONFIG_SND_SOC_SC8280XP is not
  set` ← **hay que activarlo**, `# CONFIG_SND_SOC_FS210X is not set`, `# CONFIG_SND_SOC_SM8250 is not
  set`, `CONFIG_SOUNDWIRE=m`, `CONFIG_DRM_AUX_BRIDGE=y`,
  `CONFIG_DRM_AUX_HPD_BRIDGE=m`, `CONFIG_TYPEC_MUX_WCD939X_USBSS=m`).
- Turd party (upstream no accesible en esta ventana): `linux-firmware/qcom` dio timeout; no se pudo
  confirmar si existe un `.tplg` de sm8650 en linux-firmware → **comprobar en la próxima ventana de red**
  (sería el mayor acelerador de la brecha 3).
