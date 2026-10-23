# P4 — BLUETOOTH en la uke (preparación completa, sin tablet)

**Fase:** P4 (BLUETOOTH) · **Fecha:** 2026-09-29 (madrugada)
**Modo:** solo lectura sobre fuentes; **0 accesos a la tablet** (sin fastboot/adb/ssh/ttyACM0).
**Salida:** este documento. Todo lo que se afirma lleva fichero + línea; lo no verificado va marcado
**hipótesis**.

---

## 0. Veredicto en una tabla

| Pregunta | Respuesta | Evidencia |
|---|---|---|
| ¿Qué chip BT? | **Qualcomm WCN6750** (combo WiFi6+BT 5.x «kiwi» del SM7675/cliffs7), BT en un **core propio con UART H4** — **no** es WCN6740/WCN6855 | §1 |
| ¿Cómo se conecta? | **HS-UART de 4 hilos** por el **QUPv3_1 SE2 = 0x888000** (`qup_uart10` en mainline). *No* USB, *no* SDIO, *no* PCIe | §1, §2 |
| Driver | `hci_uart` (serdev) → **hci_qca** (`qcom,wcn6750-bt`) + `btqca.ko` (descarga de FW) | §2 |
| ¿Estado del kernel? | Todo presente **menos `CONFIG_SERIAL_QCOM_GENI`** (driver del UART: **apagado** hoy ⇒ no existe `/dev/tty…`/serdev ⇒ BT imposible) | §2.2 |
| ¿Firmware? | `qca/msbtfw%02x.mbn`+`qca/msnv%02x.bin`. En la rootfs ya están los **v11**; los **v12** (los que el vendor usa en esta familia) están en `~/gpu-work/fw-qrd8635` y **no** en la rootfs | §3 |
| ¿Userspace? | **bluez/bluez-utils + pipewire/wireplumber: NO instalados en la rootfs**; los 4 paquetes existen en ALARM aarch64 | §4 |
| ¿Necesita WiFi/SMMU? | WiFi **no** (cores/FW independientes; solo comparten la pata de alimentación). **SMMU: sí, indirecto y duro** — el wrapper QUP es cliente de `apps_smmu`; sin él, el UART no probea | §5 |
| Bloqueante nº 1 | `CONFIG_SERIAL_QCOM_GENI` + nodo `&uart10` en el DT + módulos/FW en la rootfs | §8 |

---

## 1. Chip BT exacto, con evidencia

**Chip: Qualcomm WCN6750** («kiwi», el mismo die que da el WiFi ath11k del proyecto). No hay
chip BT separado: el BT es un core dentro del WCN6750 y **sale por UART**, igual que en las
plataformas hermanas (lamma-qrd, qcm6490-idp, sc7280-idp, sm7325-nothing-spacewar).

### 1.1 DT vendor (la prueba directa)

`~/proyectos/ubuntu-uke/stock/dtbase/base-uke.dts:16289-16314` (copia estable en el
proyecto; yo lo re-verifiqué descomprimiendo `~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img`
→ `/var/tmp/uke-base.dts` con el mismo resultado):

```
bt_wcn6750 {
        phandle = <0x496>;
        qcom,bt-vdd-ipa-2p2-supply = <0x345>;   /* pmr735a_s3   (1.6–2.4 V) */
        qcom,bt-vdd-rfa2-supply     = <0x347>;  /* pmxr2230_s2  (1.256–1.408 V) */
        qcom,bt-vdd-rfa1-supply     = <0x346>;  /* pmxr2230_s1  (1.856–2.04 V) */
        qcom,bt-vdd-rfa-0p8-supply  = <0x348>;  /* pmxr2230_s3  (0.968–1.04 V) */
        qcom,bt-vdd-rfacmn-supply   = <0x348>;
        qcom,bt-vdd-dig-supply      = <0x348>;
        qcom,bt-vdd-aon-supply      = <0x348>;
        qcom,bt-vdd-io-supply       = <0x1e0>;  /* pmxr2230_l7  (1.8 V) */
        qcom,wl-reset-gpio  = <0x16b 0x23 0x00>;   /* gpio  35 (WiFi) */
        qcom,bt-sw-ctrl-gpio = <0x16b 0x50 0x00>;  /* gpio  80  SW_CTRL */
        qcom,bt-reset-gpio   = <0x16b 0x9c 0x00>;  /* gpio 156  BT_EN  */
        mpm_wake_set_gpios = <0x50>;
        pinctrl-0 = <0x495>;                    /* grupo bt_en_sleep (gpio156) */
        pinctrl-names = "default";
        compatible = "qcom,wcn6750-bt";
};
```
(`0x16b` = `&tlmm`; alias `bluetooth = "/soc/bt_wcn6750"` en `base-uke.dts:20249`.)

Pines BT_EN/SW_CTRL no compartidos con nada más: `gpio156` solo aparece en el grupo
`bt_en_sleep` (`base-uke.dts:10244-10256`) y `gpio80` solo en el propio nodo BT.

### 1.2 El UART del BT es el SE10 (0x888000), no otro

- `base-uke.dts:439` → `hsuart0 = "/soc/qcom,qupv3_1_geni_se@8c0000/qcom,qup_uart@888000"`.
- `base-uke.dts:14523-14536` → ese nodo es `compatible = "qcom,msm-geni-serial-hs"`,
  **4 hilos** (`qupv3_se10_*_cts/rts/tx/rx`), `qcom,wakeup-byte = <0xfd>`, `status = "ok"`.
- Los **pines del SE10 del vendor son gpio40 (CTS), 41 (RTS), 42 (TX), 43 (RX) con función
  `qup1_se2`** (`base-uke.dts:7725-7845`), **idénticos** a los del nodo mainline
  `uart10: serial@888000` de nuestro árbol (`palawan.dtsi:1344-1364`, pinctrl
  `qup_uart10_cts_rts`/`qup_uart10_default` en `palawan.dtsi:4171-4187`). Es el mismo hardware,
  misma dirección, mismo reloj (`GCC_QUPV3_WRAP1_S2_CLK`) y mismos pines.
- Sólo hay **dos** UART activos en todo el DT vendor: se5 (consola, `a94000`) y **se10 (888000)**.
  Como el BT necesita UART, el BT *tiene* que ser el se10.

### 1.3 dmesg Android (golden)

`~/proyectos/ubuntu-permanente/criticas/ufs-referencia-android/dmesg-android.txt`:

| línea | contenido | qué prueba |
|---|---|---|
| 2928 | `Bluetooth: HCI UART protocol QCA registered` | transporte = UART QCA |
| 2877 | `Loaded kernel module …/drivers/bluetooth/btqca.ko` | descarga de FW por btqca |
| 3335 | `888000.qcom,qup_uart: ttyHS0 at MMIO 0x888000` | el HS-UART del BT es el 888000 |
| 4189 | `__mount(…by-name/bluetooth_a, /vendor/bt_firmware, vfat)` | **el FW BT vive en una partición propia** |
| 6769 | `started service 'vendor.bluetooth-1-1-qti'` | HAL BT QTI |
| 8267 | `populate_snd_card_dailinks(): WCN BT support present` | el SCO del vendor va por ADSP/BTFM (no por HCI) |
| 4602 | `qca_cld3_qca6750: Loading driver v5.2.1.91G` | el combo es **qca6750/WCN6750** |

Conclusión §1: **WCN6750**, BT por UART en **0x888000 (SE10)**, enable en **gpio156**,
handshake en **gpio80**, FW en `qca/ms*`, y el WiFi del mismo chip es el `qca6750`/ath11k.

---

## 2. Cadena kernel completa

```
[QUPv3_1 wrapper 0x8c0000]  geni-se-qup (qcom-geni-se, CONFIG_QCOM_GENI_SE=y)
        │  iommus = <&apps_smmu 0x423 0>   ← ¡cliente del SMMU! (ver §5)
        └── serial@888000 «uart10»  qcom,geni-uart (qcom_geni_serial = CONFIG_SERIAL_QCOM_GENI)
                │  pinctrl: gpio40/41 CTS-RTS (qup1_se2) + gpio42/43 TX-RX   [palawan.dtsi:4171-4187]
                └── bluetooth { compatible = "qcom,wcn6750-bt"; }   ← serdev child (DT)
                        │  enable-gpios(gpio156) | swctrl-gpios(gpio80) | 9 reguladores | max-speed 3200000
                        └── hci_uart.ko (incluye hci_qca.o) → H4 → btqca.ko (descarga FW) → hci0
```

- **Es serdev, no `btattach`.** El nodo BT cuelga del UART en el DT y `hci_uart` lo bindea por
  serdev (`CONFIG_BT_HCIUART_SERDEV=y`). **`btattach` NO sirve de plan B para el WCN6750**:
  sin serdev, `qca_soc_type()` devuelve `QCA_ROME`
  (`hci_qca.c:241-254`) y el driver no hace la secuencia de power del 6750
  (reguladores+BT_EN) ni elige los ficheros `ms*`; además pediría `qca/rampatch_%08x.bin`.
  ⇒ **el nodo DT es obligatorio**.
- El driver exige **9 reguladores** por nombre (`devm_regulator_bulk_get`, no opcional:
  `hci_qca.c:2358-2385` lee `qca_soc_data_wcn6750`, `hci_qca.c:2171-2184`): `vddio, vddaon,
  vddbtcxmx, vddrfacmn, vddrfa0p8, vddrfa1p7, vddrfa1p2, vddrfa2p2, vddasd`.
  Si falta uno ⇒ `-ENODEV` en probe (ejemplo bueno a copiar: `sm7325-nothing-spacewar.dts:1384-1406`,
  que sí lleva los 9; **ojo: `lamma-qrd.dts:929-946` está obsoleto** y usa nombres de WCN6855
  — no copiarlo tal cual).
- `max-speed = <3200000>` (3.2 Mbaud; igual que lamma-qrd/spacewar/sc7280).

### 2.2 `CONFIG_` exactos (de NUESTRO `.config`: `/var/tmp/uke-k1-build/.config`)

| CONFIG | Estado | ¿sirve? |
|---|---|---|
| `CONFIG_BT` | `=m` | OK (bluetooth.ko) |
| `CONFIG_BT_BREDR` / `CONFIG_BT_LE` | `=y` | OK (A2DP/HFP clásico + BLE) |
| `CONFIG_BT_HCIUART` | `=m` | OK |
| `CONFIG_BT_HCIUART_SERDEV` | `=y` | OK (imprescindible) |
| `CONFIG_BT_HCIUART_H4` | `=y` | OK |
| `CONFIG_BT_HCIUART_QCA` | `=y` | OK (mete `hci_qca.o` en `hci_uart.ko`, `Makefile:48`) |
| `CONFIG_BT_QCA` | `=m` | OK (`btqca.ko` = descarga de FW, `Makefile:26`) |
| `CONFIG_BT_HIDP` / `CONFIG_BT_RFCOMM` | `=m` / `=y` | OK (HID y serie; opcionales) |
| `CONFIG_SERIAL_DEV_BUS` | `=y` | OK |
| `CONFIG_SERIAL_CORE` | `=y` | OK |
| `CONFIG_QCOM_GENI_SE` | `=y` | OK (driver del wrapper QUP) |
| **`CONFIG_SERIAL_QCOM_GENI`** | **`# … is not set`** | **FALTA — bloqueante**. Sin este driver no existe el UART del BT (ni consola en uart5) |
| `CONFIG_RFKILL` | `=m` | OK |
| `CONFIG_POWER_SEQUENCING_QCOM_WCN` | `=m` | OK (sólo si se elige la ruta «PMU» de §8.B) |

> `SERIAL_QCOM_GENI` ya aparece en `configs-uke/opciones-perdidas-s89.txt:397` (se cayó en la
> limpieza del config s89 y nunca se echó de menos porque la consola del proyecto va por USB ACM).

### 2.3 Módulos que hay que dejar en la rootfs (están como `=m`)

De `make modules_install` a `/usr/lib/modules/7.2.0-rc2-palawan+/kernel/…`:

```
net/bluetooth/bluetooth.ko        (CONFIG_BT)
net/bluetooth/hidp/hidp.ko        (opcional)
net/bluetooth/rfcomm/rfcomm.ko    (opcional)
net/rfkill/rfkill.ko
drivers/bluetooth/hci_uart.ko     (contiene hci_qca.o)
drivers/bluetooth/btqca.ko        (dependencia de símbolos de hci_uart)
```

Hoy en la imagen `arch-rootfs.img` **sólo** hay `extra/{ath11k,ath11k_ahb,ath11k_pci,qcom_battmgr,qcom_pd_mapper}.ko`
y un `modules.dep` de 139 B ⇒ **los 4-6 módulos BT no están**. Instalarlos en `extra/` + `depmod`
(mismo patrón que ath11k) o, si se prefiere no depender de módulos, hornear `CONFIG_BT=y`,
`CONFIG_BT_HCIUART=y`, `CONFIG_BT_QCA=y` y `CONFIG_SERIAL_QCOM_GENI=y`.

---

## 3. Firmware — nombres y rutas exactos

Nombres que pedirá el driver (`btqca.c`):
- rampatch: **`qca/msbtfw%02x.mbn`** (`btqca.c:834`; si el `.mbn` no existe, reintenta
  **`qca/msbtfw%02x.tlv`**, `btqca.c:863`) — `%02x` = **rom_ver** que se lee del chip.
- NVM: **`qca/msnv%02x.bin`** (`btqca.c:931`). Si el DT trae `firmware-name` sin extensión, se
  construye `qca/msnv%02x.b0X` con el board-id leído del chip (`btqca.c:734-767`).

| Vía | Ficheros | ¿En la rootfs `arch-rootfs.img`? |
|---|---|---|
| **Android stock** | partición **`bluetooth_a`** (vfat) montada en `/vendor/bt_firmware` (dmesg:4189). Los nombres no salen en el dmesg ⇒ **verificar post-tablet con `adb shell ls -l /vendor/bt_firmware/`** | — |
| **linux-firmware** (host `20260916-1`, subpkg `linux-firmware-atheros`) | `qca/msbtfw11.mbn` (202 508 B), `qca/msbtfw11.tlv` (190 296 B), `qca/msnv11.bin`, `qca/msnv11.b09`, `qca/msnv11.b0a` (5 899 B c/u) | **SÍ** — `/usr/lib/firmware/qca/…` ya presentes y **descomprimidos** (verificado con `debugfs`) |
| **vendor qrd8635** (clon local `~/gpu-work/fw-qrd8635`, `codeberg.org/palawan-mainline/firmware-qualcomm-qrd8635`) | `msbtfw12.mbn` (113 860 B, ELF 32-bit ARM, sha256 `24c906641d6d5a39e77b09874b3fb744ca92c5a803f077fc6d3345d1fb22654d`), `msnv12.bin` (6 316 B, sha256 `66eb3eb2f796be1aca76fe9f7c66a09b9abbb98c23343c01d2545b5a7220d99f`) | **NO** ⇒ copiar a `/usr/lib/firmware/qca/` |

**El punto abierto es `rom_ver` (0x11 vs 0x12)**: linux-firmware sólo trae la **11**; la familia
cliffs/palawan (qrd8635) usa la **12** (y el informe `docs/informes/E-paquetes-aarch64-soc.md:319` ya lo apuntaba:
«BT del cliffs7, variante 12, no 11»). **Mitigación barata: dejar las dos parejas en
`/usr/lib/firmware/qca/`** (11 y 12) — así el driver acierte con el nombre por defecto. El propio
driver imprime `QCA controller version 0x…` en dmesg, de donde se deduce `rom_ver` en el primer boot.

Escape hatch documentado en el binding (`Documentation/devicetree/bindings/net/bluetooth/qcom,wcn6750-bt.yaml`,
ejemplo `firmware-name = "msnv11.bin";`) y precedente en el árbol
(`sdm845-lg-judyp.dts:37`): en el nodo BT se puede **fijar el nombre**
`firmware-name = "msnv12.bin", "msbtfw12.mbn";` — **el orden importa: [0]=NVM, [1]=rampatch**
(`hci_qca.c:256-276` + `btqca.c` `qca_uart_setup()`), y **sin** el prefijo `qca/`.

---

## 4. Userspace (Omarchy / Arch aarch64)

La rootfs actual (`arch-rootfs.img`, paquetes `20260622`) **no trae bluez ni pipewire**
(verificado con `debugfs`: no hay `/usr/bin/bluetoothctl`, ni `/etc/bluetooth/main.conf`, ni
`/usr/lib/systemd/system/bluetooth.service`; sólo `rfkill`). Los paquetes existen **ya para
aarch64** en `extra` de ALARM (`build/rootfs/pkgs/extra.db`, descargado el 26-sep-2026):

| Paquete (versión en ALARM) | Para qué |
|---|---|
| **bluez 5.87-2** + **bluez-utils 5.87-2** (+ `bluez-libs`) | stack HCI, `bluetoothd`, `bluetoothctl`, `btmgmt` |
| **pipewire 1:1.6.9-1** + **pipewire-pulse** (+ `pipewire-audio`) | servidor de audio y puente PulseAudio |
| **wireplumber 0.5.17-2** | session manager: es quien gestiona los perfiles A2DP/HFP de las tarjetas bluez |
| `libfreeaptx 0.2.2-1`, `libldac 2.0.2.6-1`, `sbc 2.2-1` | códecs (aptX / LDAC / SBC). SBC va siempre; aptX/LDAC son opcionales |
| `bluez-deprecated-tools` | sólo si se quieren `hciconfig`/`hcitool` viejos (no necesario) |

Configuración mínima:
1. `systemctl enable --now bluetooth` (unit de bluez; el demonio necesita DBus, ya presente).
2. Nada especial en `/etc/bluetooth/main.conf` para empezar (autoconnect/`JustWorksRepairing`
   sólo si se quiere). Sin `btattach` ni unidades propias: el transporte lo levanta el kernel.
3. PipeWire/WirePlumber como usuario de escritorio (unit `wireplumber.service` de usuario y
   `pipewire-pulse.socket`) — **es justo lo que Omarchy ya asume** para el escritorio, así que
   los dotfiles de Omarchy no necesitan nada específico de BT; el indicador del shell
   (Quickshell/Waybar) es cosmético y va aparte del gate.
4. `rfkill` ya está en la rootfs (util-linux).
5. HFP: el WCN6750 de este árbol **no** expone `QCA_CAP_HFP_HW_OFFLOAD` (`hci_qca.c:2171-2184`;
   sólo WCN6855/7850 lo tienen) ⇒ el audio de voz irá por **SCO sobre HCI** con el códec del
   propio chip, no por el `btfmslim`/ADSP del vendor (ver §7-R7).

---

## 5. Dependencias cruzadas

1. **WiFi / coex (mismo chip): NO es requisito.** BT y WiFi son cores distintos con firmwares
   distintos (BT=rampatch por UART; WiFi=WPSS/`wpss.mdt` + ath11k por PCIe, dmesg:6647-6676) y el
   nodo vendor del BT tiene su propio reset (`gpio156`) y sus propias patas. **Comparten** eso sí:
   (a) el paquete WCN6750, (b) las patas **S1B/S2B/S3B** del pmxr2230 y **pmr735a_s3**, que el nodo
   WiFi del vendor también vota (icnss: `vdd-1.8-xo=S1B`, `vdd-1.3-rfa=S2B`, `vdd-cx-mx=S3B`), y
   (c) la coexistencia RF dentro del chip (la resuelve el FW). Como los reguladores RPMH son *votos*
   y en mainline van `always-on`, no hay dependencia de orden de arranque. ⇒ El BT se puede probar
   **antes** de que ath11k/WiFi funcione (hipótesis razonable, no medida en esta tablet).
2. **IOMMU/SMMU: sí, indirecto y duro.** El wrapper `geniqup@8c0000` es cliente del apps-smmu
   (`iommus = <&apps_smmu 0x423 0>`, `palawan.dtsi:1235`; el de qup0 lleva `0xa3`). Si el
   apps-smmu no bindea (el bloqueante actual del proyecto), **el UART no probea nunca** (deferred
   eterno). Opciones:
   (a) camino K7 (bind del SMMU en la ventana Android), o
   (b) **traza de bring-up**: `&qupv3_id_1 { /delete-property/ iommus; };` (+ quitar `dma-coherent`
   si estorba) — el UART en modo FIFO/IRQ no necesita traducción; **probar sólo como experimento**
   (no hay propiedad `iommu-optional` en este árbol: comprobado). Ojo: qup1 se estrena aquí en
   mainline (hoy no hay ningún SE de qup1 en uso), así que el primer probe es también el del wrapper.
3. **Pines: exclusivos.** BT_EN `gpio156`, SW_CTRL `gpio80`, UART `gpio40-43`; el táctil
   (novatek) usa `irq-gpio = gpio54` y `lcd_id-gpio = gpio26` (`uke-dtbo.dts:2597-2598`), el
   UFS reset `gpio178`. **Sin solapes.** El único "vecino" es el `wl-reset-gpio` (gpio35, WiFi).
4. **Audio:** el HFP del vendor pasa por el SLIMbus/ADSP (`slim@6C40000/ngd@1/btfmslim-driver`,
   alias `slimbus`; dmesg:8267 «WCN BT support present»). Mainline no tiene `btfmslim` ⇒ ver §7-R7.
5. **Sin dependencia** de display/GPU/ADSP/UFS para el BT (nada del nodo BT referencia esos nodos).

---

## 6. Plan de prueba paso a paso (para cuando haya tablet)

> Escalonado: primero sólo lectura de Android (barato y decisivo), luego bring-up en Arch.
> Regla del proyecto: un cambio por ciclo, con fila pre-registrada, consola ACM armada y
> ≥3700 mV. Sólo el paso 0 es adb (lectura).

**Paso 0 — evidencia en Android (read-only, resuelve las dos incógnitas caras)**
1. `adb shell ls -l /vendor/bt_firmware/` → **nombres exactos del FW del vendor** ⇒ fija
   `rom_ver` (11 vs 12) y el board-id del NVM. *Si sale sólo un `image/` o vfat con
   `msbtfw12.mbn/msnv12.*`, usamos los ficheros del qrd8635.*
2. `adb shell 'dmesg | grep -iE "btqca|QCA controller|hci_qca|msbtfw|msnv"'`
3. `adb shell 'cat /sys/kernel/debug/regulator/regulator_summary | grep -iE "asd|wcn|bt"'` →
   mapping del rail **VDD_ASD** (§7-R2).
4. `adb shell 'ls /proc/device-tree/soc/bt_wcn6750/'` para confirmar propiedades runtime.

**Paso 1 — kernel + DT nuevos (build K+1)**
5. `.config`: añadir `CONFIG_SERIAL_QCOM_GENI=y` (y `CONFIG_SERIAL_QCOM_GENI_UART_PORTS=8`,
   default). Nada más hace falta (tabla §2.2).
6. DT: pegar el fragmento del **Anexo A** en `xiaomi-uke.dts` (uart10 + bluetooth + pinctrl +
   grupo `regulators-3` del pmr735a).
7. Gate de DT **antes de flashear**: `dtc`/`fdtoverlay` en verde + `bin/uke-dtbo-check.py`.

**Paso 2 — bring-up del transporte (en Arch, por consola ACM/SSH)**
8. `dmesg -n 7` y luego `dmesg | grep -iE "888000|geni|serdev|hci|bluetooth|qca"`.
   *Esperado*: el wrapper qup1 probea, `serial@888000` aparece, `hci_uart` bindea el serdev y
   salen `Bluetooth: hci0: QCA controller version 0x…`, `QCA Downloading qca/msbtfw…`,
   `QCA Downloading qca/msnv…`, `hci0: … address …`.
9. Módulos/firmware: `ls /usr/lib/firmware/qca/ | grep ms`, `modprobe -v hci_uart btqca`
   (o confiar en el autoload por modalias OF), `modprobe rfkill`; `ls /sys/class/bluetooth/`
   (debe salir `hci0`).
10. `rfkill list` → `phy0 … bluetooth`; si `Soft blocked: yes` → `rfkill unblock bluetooth`.
11. `hciconfig -a` (o `bluetoothctl show`): debería verse `UP RUNNING`, el BD address y las
    features/versión LMP del chip.

**Paso 3 — radio (scan/pair)**
12. `systemctl start bluetooth`; `bluetoothctl` → `power on`, `agent on`, `default-agent`.
13. `bluetoothctl scan on` (con un móvil/auricular cerca): deben aparecer MACs con nombre.
    `scan off`, `pair <MAC>`, `trust <MAC>`, `connect <MAC>`, `info <MAC>`.
14. Prueba BLE: `bluetoothctl` → `menu gatt` + `list-attributes <MAC>` con un dispositivo BLE
    (valida el core LE del FW, que es lo que usa el lápiz BLE de otros dispositivos).

**Paso 4 — audio (A2DP y HFP)**
15. Con un auricular A2DP: `wpctl status` / `pactl list cards short` deben mostrar la tarjeta
    `bluez_card.<MAC>`; `wpctl set-default <id>` y reproducir (`pw-play`/`aplay`/`mpv`) → sonido.
    Empezar por **SBC**; luego probar `aptX`/`LDAC` (con `libfreeaptx`/`libldac` instalados) y
    anotar el códec activo (`pw-dump | grep -i codec`).
16. HFP: auricular con micro; `bluetoothctl connect`; en PipeWire debe aparecer el perfil
    `headset-head-unit`/`hfp`; grabar con `pw-record`/`arecord` y comprobar que hay señal.
    **Riesgo alto** (ver R7): aquí es donde el vendor usa ADSP/BTFM y mainline usa HCI SCO.
17. Coexistencia: con el BT activo, encender WiFi (cuando ath11k funcione) y hacer un `iperf` +
    música A2DP a la vez; buscar `disconnect`/`reason` en `dmesg`.
18. Suspensión: `systemctl suspend` → despertar → `bluetoothctl info` sigue OK (si no, añadir el
    IRQ de wake del RX como hace `sm7325-nothing-spacewar.dts:1371-1374`; ver Anexo A nota 3).

**Paso 5 — cierre**
19. Volcar evidencia (dmesg + `bluetoothctl info` + `pactool` + `lsusb`-equivalente de BT),
    hashear los ficheros usados (`/usr/lib/firmware/qca/ms*`) y anotar la fila en el ledger.

---

## 7. Riesgos (ordenados por probabilidad × daño)

| # | Riesgo | Detalle | Mitigación |
|---|---|---|---|
| **R1** | **`rom_ver` equivocado (11 vs 12)** | linux-firmware trae v11; la familia cliffs/palawan usa v12. Si el chip reporta 12 y no hay fichero ⇒ `qca_download_firmware` falla y **no hay hci0** | Instalar **las dos parejas** en `/usr/lib/firmware/qca/` (ya tenemos v12 en `~/gpu-work/fw-qrd8635`), o fijar `firmware-name = "msnv12.bin","msbtfw12.mbn"`; confirmar nombres con el Paso 0 |
| **R2** | **`vddasd` sin mapear** | El DT vendor **no** modela `bt-vdd-asd` (8 patas, no 9). El driver exige las 9 por nombre ⇒ `-ENODEV` y BT muerto. (En sc7280/spacewar `vddasd` es un rail de 2.8 V; aquí no existe) | Provisoriamente apuntar `vddasd` a la pata de 1.04 V del propio BT (`vreg_s3b_1p04`, carga 200 µA, el driver **no** fija tensión) y validar; **plan B**: parche de 3 líneas en `qca_init_regulators` para que las patas *deprecated* del binding (`vddio`, `vddbtcxmx`, `vddrfa2p2`, `vddasd`) se pidan como opcionales. Confirmar con `regulator_summary` de Android (Paso 0.3) |
| **R3** | **SMMU/QUP** | Sin `apps_smmu` vivo, `geniqup@8c0000` defer ⇒ no hay UART ⇒ el BT parece «inexistente» | Camino K7; o `/delete-property/ iommus` en qup1 como traza; diagnosticar con `ls /sys/bus/platform/devices/ | grep geniqup` y el log de deferred probe |
| **R4** | **Firma/atestación del FW** | Como el WiFi (que en Android falla con `-13` al cargar `/vendor/firmware/wlan/...` por SELinux/secure), podría exigirse un rampatch «firmado» distinto del de linux-firmware | Tener a mano **ambos** juegos (linux-firmware + vendor qrd8635 + los del `bluetooth_a` que se leerán en el Paso 0); el log dice exactamente qué fichero pide y con qué error |
| **R5** | **BD address / NVM de placa** | El NVM `msnv1X.bin` es el genérico; puede traer una MAC inválida o no ser el de la placa ⇒ dirección aleatoria o `00:00:…` | `qcom,local-bd-address-broken` (precedente en `sm7325-nothing-spacewar.dts:1405`) y/o usar el NVM con board-id (`firmware-name = "msnv"` sin extensión → `qca/msnv11.b0X`) |
| **R6** | **Sin plan B de `btattach`** | WCN6750 sin serdev = `QCA_ROME` ⇒ no soportado | Asumir que el DT es obligatorio; si el serdev no aparece, es problema de DT/SMMU/UART, no de userspace |
| **R7** | **HFP (voz) por camino distinto** | Android usa BTFM/SLIMbus+ADSP para SCO (dmesg:8267); mainline no tiene ese driver ⇒ SCO irá por HCI. A2DP (L2CAP) no se ve afectado | Medir en el Paso 4.16; si HFP no tira, queda como limitación documentada (no bloquea A2DP/música) |
| **R8** | **UART a 3.2 Mbaud (FIFO) en qup1** | Primer SE de qup1 en mainline; 3.2 M con FIFO de 64 B puede dar overruns | Bajar `max-speed` a 3000000/1500000 y medir; mirar `dmesg` por `rx overrun` |
| **R9** | **Despliegue olvidado** | Los 4-6 `.ko` y las FW v12 **no están** en la rootfs | Meterlo en el checklist del Anexo B (y verificar con `debugfs` tras reconstruir la imagen) |
| **R10** | **Estado del SW_CTRL** | El driver sólo *lee* `gpio80` (diagnóstico, `hci_qca.c:1813`), pero si el strap no está no se detecta el «clock shrug» | Configurar el pin como en upstream (`bias-pull-down`); si BT_EN no levanta el chip, replicar **exactamente** el grupo vendor `bt_en_sleep` (`drive-strength 2`, `bias-pull-down`, `output-low`) |

---

## 8. Anexo A — DT listo para pegar (en `xiaomi-uke.dts`)

**A) Pinctrl nuevo (dentro de `&tlmm { … }` que ya existe):**
```dts
	bt_en_default: bt-en-default-state {
		pins = "gpio156";
		function = "gpio";
		drive-strength = <2>;
		bias-disable;
		output-low;
	};

	bt_sw_ctrl: bt-sw-ctrl-state {
		pins = "gpio80";
		function = "gpio";
		bias-pull-down;
	};
```

**B) Grupo del pmr735a (hoy NO existe en nuestro DTS; hace falta para `vddrfa2p2`):**
pegar dentro de `&apps_rsc { … }` junto a `regulators-0`/`regulators-2`:
```dts
	regulators-3 {
		compatible = "qcom,pmr735a-rpmh-regulators";
		qcom,pmic-id = "e";

		vreg_s3e_2p4: smps3 {
			regulator-name = "vreg_s3e_2p4";
			regulator-min-microvolt = <1600000>;
			regulator-max-microvolt = <2400000>;
			regulator-initial-mode = <RPMH_REGULATOR_MODE_HPM>;
		};
	};
```

**C) UART + nodo BT:**
```dts
&uart10 {			/* QUPv3_1 SE2 @ 0x888000 = «hsuart0» del vendor = BT */
	status = "okay";

	bluetooth: bluetooth {
		compatible = "qcom,wcn6750-bt";

		pinctrl-names = "default";
		pinctrl-0 = <&bt_en_default>, <&bt_sw_ctrl>;

		enable-gpios = <&tlmm 156 GPIO_ACTIVE_HIGH>;	/* vendor: qcom,bt-reset-gpio  */
		swctrl-gpios = <&tlmm 80 GPIO_ACTIVE_HIGH>;	/* vendor: qcom,bt-sw-ctrl-gpio */

		vddio-supply     = <&vreg_l7b_1p8>;	/* pmxr2230_l7  1.8 V   */
		vddaon-supply    = <&vreg_s3b_1p04>;	/* pmxr2230_s3  1.04 V  */
		vddbtcxmx-supply = <&vreg_s3b_1p04>;
		vddrfacmn-supply = <&vreg_s3b_1p04>;
		vddrfa0p8-supply = <&vreg_s3b_1p04>;
		vddrfa1p7-supply = <&vreg_s1b_2p04>;	/* pmxr2230_s1  2.04 V  */
		vddrfa1p2-supply = <&vreg_s2b_1p4>;	/* pmxr2230_s2  1.4 V   */
		vddrfa2p2-supply = <&vreg_s3e_2p4>;	/* pmr735a_s3   2.2 V   */
		vddasd-supply    = <&vreg_s3b_1p04>;	/* ← PROVISORIO, ver R2 */

		max-speed = <3200000>;
		/* firmware-name = "msnv12.bin", "msbtfw12.mbn";	[0]=NVM [1]=rampatch */
	};
};
```
Notas: (1) los 9 nombres son **obligatorios** y deben ser exactamente los de
`qca_soc_data_wcn6750` (no los de lamma-qrd). (2) El driver no fija tensiones, sólo vota enable +
`load_uA`: lo que importa es que cada nombre apunte a la pata física correcta (tabla de §1.1).
(3) Opcional (suspend/wake): como en `sm7325-nothing-spacewar.dts:1371-1374`,
`&uart10 { /delete-property/ interrupts; interrupts-extended = <&intc GIC_SPI 584 IRQ_TYPE_LEVEL_HIGH>, <&tlmm 43 IRQ_TYPE_EDGE_FALLING>; };`.

**Ruta alternativa (B') — «PMU» al estilo QRD** (`qcm6490-idp.dts:199-240`): crear un nodo
`wcn6750-pmu { compatible = "qcom,wcn6750-pmu"; … }` con las patas reales + `bt-enable-gpios` +
reguladores dummy, y que el nodo BT referencie esos `vreg_pmu_*` (el driver usa entonces
`devm_pwrseq_get(… "bluetooth")`, `hci_qca.c:2447-2462`, y **no** pide los 9 reguladores).
Ventaja: se saltan los *deprecated*. Inconveniente: hay que fabricar el PMU y sigue necesitando
`vddasd`. **Recomendado como plan B** sólo si R2 muerde.

---

## 9. Anexo B — Checklist de lo que falta (para el gate de ejecución)

| # | Acción | Dónde | Estado |
|---|---|---|---|
| 1 | `CONFIG_SERIAL_QCOM_GENI=y` (+ `…_UART_PORTS=8`) y rebuild | `/var/tmp/uke-k1-build/.config` | ❌ pendiente |
| 2 | Pegar Anexo A (pinctrl + regulators-3 + `&uart10`) | `arch/arm64/boot/dts/qcom/xiaomi-uke.dts` | ❌ pendiente |
| 3 | Resolver `vddasd` (mapa provisorio o parche de 3 líneas) | DT o `hci_qca.c` | ⚠️ decisión |
| 4 | Copiar `msbtfw12.mbn` + `msnv12.bin` a `/usr/lib/firmware/qca/` (dejar también los v11) | rootfs | ❌ pendiente |
| 5 | Instalar `.ko` BT (bluetooth, rfkill, hci_uart, btqca [+hidp, rfcomm]) en `extra/` + depmod | rootfs | ❌ pendiente |
| 6 | Instalar bluez, bluez-utils, pipewire, pipewire-pulse, pipewire-audio, wireplumber, libfreeaptx, libldac, sbc | rootfs (ALARM extra) | ❌ pendiente |
| 7 | `systemctl enable bluetooth` (+ wireplumber de usuario) | rootfs | ❌ pendiente |
| 8 | Verificar `rom_ver`, nombres FW, rail ASD (sólo lectura) | tablet Android | ⏳ cuando haya tablet |
| 9 | Prueba §6 pasos 8-18 | tablet Arch | ⏳ |

---

## 10. Índice de evidencia (rutas absolutas)

**DT / hardware**
- `~/proyectos/ubuntu-uke/stock/dtbase/base-uke.dts` — DT base vendor: nodo `bt_wcn6750`
  (16289-16314), `bt_en_sleep` (10244-10256), `hsuart0` (439), `qup_uart@888000` (14523-14536),
  pines SE10 (7725-7845), alias `bluetooth` (20249).
- `~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img` (4 DTBs concatenados;
  verificado a mano: el nodo BT está en el primero) y `…/dtbo-gpu/dtbo_b-payload.dtb` (nodo WiFi
  `qcom,wcn6750`/icnss2, gpios del táctil, `pmr735a_s3`…). Descompilados en `/var/tmp/uke-base.dts`,
  `/var/tmp/uke-dtbo.dts`.
- `~/proyectos/ubuntu-permanente/criticas/ufs-referencia-android/dmesg-android.txt`
  — líneas 2301, 2836-2841, 2844, 2877, 2880, 2924-2928, 3335, 4189, 4602, 6647-6676, 6769, 8267.

**Kernel (nuestro árbol y su build)**
- `/var/tmp/uke-k1/drivers/bluetooth/hci_qca.c` — `qca_soc_data_wcn6750` (2171-2184),
  `qca_init_regulators` (2358-2385), probe/9 reguladores + pwrseq (2447-2500), match table (2781).
- `/var/tmp/uke-k1/drivers/bluetooth/btqca.c` — nombres FW (834, 863, 931), `firmware-name` /
  board-id (734-767, 890-900), fallback NVM (289-300).
- `/var/tmp/uke-k1/drivers/bluetooth/Makefile` — 7/26/48 (hci_uart + btqca).
- `/var/tmp/uke-k1/drivers/tty/serial/Kconfig` — 915-936 (`SERIAL_QCOM_GENI`, `…_UART_PORTS`).
- `/var/tmp/uke-k1-build/.config` — tabla §2.2.
- `/var/tmp/uke-k1/arch/arm64/boot/dts/qcom/palawan.dtsi` — `uart10` (1344-1364), pinctrl
  (4171-4187), `geniqup@8c0000`+`iommus` (1226-1243), `geniqup@ac0000` (1658).
- Plantillas: `sm7325-nothing-spacewar.dts:1384-1406` (los 9 reguladores + gpios; **mejor modelo**),
  `sc7280-idp.dtsi:1098-1107`, `qcs6490-rb3gen2.dts` (ruta PMU), `lamma-qrd.dts:929-946` (obsoleto),
  `Documentation/devicetree/bindings/net/bluetooth/qcom,wcn6750-bt.yaml`.

**Firmware / rootfs / paquetes**
- `~/gpu-work/fw-qrd8635/{msbtfw12.mbn,msnv12.bin}` (clon de
  `codeberg.org/palawan-mainline/firmware-qualcomm-qrd8635`) — sha256 en §3.
- `/usr/lib/firmware/qca/ms*` (host, uncompressed sizes) y
  `~/proyectos/omarchy-uke/build/rootfs/arch-rootfs.img` (`debugfs`:
  `/usr/lib/firmware/qca/msbtfw11.mbn` = 202 508 B, `msbtfw11.tlv` = 190 296 B,
  `msnv11.{bin,b09,b0a}` = 5 899 B; `/usr/lib/modules/7.2.0-rc2-palawan+/extra/` sin módulos BT;
  sin `bluetoothctl`/`bluetooth.service`).
- `~/proyectos/omarchy-uke/build/rootfs/pkgs/{extra.db,core.db,alarm.db,aur.db}`
  — bluez 5.87-2, bluez-utils 5.87-2, pipewire 1:1.6.9-1, pipewire-pulse, pipewire-audio,
  wireplumber 0.5.17-2, libfreeaptx 0.2.2-1, libldac 2.0.2.6-1, sbc 2.2-1.
- Documentos del proyecto: `docs/informes/E-paquetes-aarch64-soc.md` (§2.2 firmware, §3.3 «BT del cliffs7,
  variante 12»), `docs/historia/AGENTS.md`, `docs/historia/ESTADO-VIVO.md`, `configs-uke/opciones-perdidas-s89.txt:397`.
