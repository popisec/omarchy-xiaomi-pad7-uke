# Fedora uke: pendientes × lo atacable desde Android (17-oct-2026)

Fuente: README de /tmp/uke-fedora (estado 15-oct-2026, upstream POCO Pad X1, Fedora Rawhide +
Linux 7.2.9 r1.39). Su frase de estado: "not suitable for daily use". Lo suyo nos importa por
dos vías: (a) su kernel+DT es el segundo intento mainline del mismo SoC — cada hallazgo nuestro
le sirve y viceversa; (b) sus pendientes son la lista de frentes que quedan para hacer la
tablet usable.

## Sus pendientes y qué podemos atacar desde Android (root adb)

| Su pendiente | Estado suyo | Atacable desde Android | Lo que ya sacamos / acción |
|---|---|---|---|
| **Display nativo** (panel negro con DSI errors; simpledrm) | 🔴 | ✅ (parcial) | SU pendiente nº1 es el NUESTRO resuelto-a-medias: les sirve TODO nuestro pack panel (PPS OEM byte-exacto, tabla de relojes en vivo, diferencia FIFO vendor-limpio vs nuestro-estallido, MISR/HS_TIMER/FLUSH, y que su byte-clock x30 ya lo verificamos por 3 vías). Acción: donar los informes PANEL-REVISION-* y el dump_info del vendor. |
| **Stylus** 🔴 (ellos tienen táctil 🟢, lápiz no) | 🔴 | ✅ **HECHO HOY** | Firmware **NT36532** extraído de /odm/firmware: `novatek_nt36532_o82_fw_csot.bin` + `mp_csot.bin` (+variantes _tm) en `build/android/`. Nodos DT: `spi@a90000/novatek@0` (19,2 MHz, irq 387, lcd_id 359, panel **CSOT**, `stylus-resol-double`), inputs **M80p + P81c**. Les sirve el fw+DT; a nosotros el port `0001-touch`. |
| **Bluetooth** 🔴 (sin controlador) | 🔴 | ✅ **HECHO HOY** | BT = **WCN6750** (`qcom,wcn6750-bt`), reset GPIO **TLMM 156**, 5 supplies, pinctrl solo bt_en_sleep, SIN UART (transporte vendor = icnss2/plataforma: `17110040.qcom,wcn6750` + fw `qca6750/`). Para mainline (ambos): hci_qca serdev en UART libre + fw linux-firmware. Acción: donar el nodo y el hallazgo GPIO156. |
| **Charging** 🟡 (¡se descargaba en prueba USB!) | 🟡 | ✅ **LO TENEMOS** | Nuestro stack ADSP/battmgr funciona (Charging 1,0–1,4 A medido, hito #644). Donar `charge/` (loader con verificación de shas + servicio + guion). |
| **Audio** 🔴 | 🔴 | 🟡 (config sí, stack es ADSP) | Codec **wcd939x** en i2c@a80000/0x0e, SPF/lpass-cdc, audio en ADSP (nuestro uke-adsp ya corre). Donar nodos sound/wcd del DT completo. |
| **USB host** 🔴 / device 🟡 | 🔴/🟡 | 🟡 | Nodos type-c/role del DT (en dt-full tar local). Pendiente extraer. |
| **Brújula/proximidad** 🔴 | 🔴 | ✅ | Sensores por SSC/ADSP: `xiaomi.sensor.sar` (SAR=proximidad) + `sensortek` visibles en dumpsys. Nodos identificables en el DT local. |
| **Rotación/luz automáticas** 🟡 | 🟡 | 🟡 | Misma vía SSC. |
| **Boot reliability** 🟡 | 🟡 | ✅ | Nuestra disciplina de slots/pre-registro + el hallazgo de rehabilitación de slots (flashear+set_active rehabilita). |
| Pogo keyboard ⚪ | ⚪ | ✅ | Driver `xiaomi-keyboard` (keypad+touchpad+mouse uinput) + `xiaomi-hall` — datos ya en PERIFERICOS doc. |
| Cámaras/codecs/suspend/termal ⚪ | ⚪ | 🟡 | DT local (dt-full tar) cuando toque. |

## Botines extraídos hoy (build/android/)

- `novatek_nt36532_o82_fw_csot.bin` + `novatek_nt36532_o82_mp_csot.bin` (245 KB c/u) — firmware
  táctil NT36532 variante CSOT (existen también _tm).
- `bd_o82gl.elf` (59,9 KB) + `regdb_xiaomi.bin` (24,3 KB) — **board data ath11k del o82**
  (para nuestro `0002-wifi` y para el suyo; el vendor los carga de firmware_mnt qca6750/).
- `dt-full-uke-android.tar` (30,8 MB) — el DT COMPLETO de Android; referencia definitiva.

## Regla de juego

Todo lo de arriba es donable al repo Fedora (su táctil 🟢 ya funciona con fingers — el fw NT36532
les da el lápiz; su charging se arregla con nuestro stack; nuestro panel pack le ahorra su
pendiente nº1). A cambio, su `src/display/` y su test `dsi-clock-contract` ya nos validaron el
byte-clock. Proponer al dueño abrir canal de intercambio.
