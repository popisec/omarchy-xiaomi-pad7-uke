# PENDIENTES ANDROID — periféricos uke (17-oct-2026)

Objetivo: lista de datos de periféricos que faltan por capturar en Android (HyperOS + root Magisk) antes de salir de él.
Fuentes leídas: `docs/guias/RE-NOCTURNO-HALLAZGOS-20261017.md` (§3.x «NO VERIFICADO», §7), `build/gates/revision/PERIF-{TACTIL,BT,WIFI,AUDIO}-20261017.md`, `build/gates/revision/RE-NOCTURNO-20261017/README.md`, `RE-FOLIO-SENSORES.md`.

Convenciones de los comandos:
- Serie: el README usa `192.0.2.13:5555`. Esa IP puede estar desactualizada: comprobar con `adb devices` antes de usar. Sustituir `SERIE` por la que devuelva.
- Marcas: **[LECTURA]** solo lectura por adb, seguro. **[INTERACCIÓN]** requiere que el dueño toque, conecte o abra algo. **[REINICIO/ESCRITURA]** requiere reinicio, carga de módulo o flash; no entra en este frente de solo lectura.

## Ordenado por importancia

### 1. Táctil NT36532: frame THP real y discrepancias de tamaño (crítico)
- **Qué falta:** ningún frame real capturado. Discrepancias abiertas: frame 5748 B (BODY) vs 5176 B (cabecera del parche previo); `w3` predicho 5724 en BODY §7 pero 5152 en el gate de MT §7. Hay que resolverlo con datos.
- **Por qué importa:** sin frame real no se puede validar `thp-decode.py` ni el parche 12 (MT parser). Sin eso no hay dedos en el kernel.
- **Captura:** [LECTURA] `adb -s SERIE shell su -c 'ls -l /dev/xiaomi_touch* /dev/input/event*'`, y luego el nodo mmap del HAL (`xiaomi_touch_dev_mmap`, 160 KB) como volcado de solo lectura. [INTERACCIÓN] un dedo sobre la pantalla mientras se vuelca.
- **Nota:** capturar con dedo y con pantalla en reposo para separar blobs mutual/self/noise.

### 2. Táctil: rango y layout de dedo (crítico)
- **Qué falta:** rango vivo confirmado en `getevent` (X 21359 / Y 31999, 10 slots), pero el DT del parche 0001 pone 2136×3200 (10:1). Layout de dedo sin verificar (candidato A: registros de 6 B, INFERIDO).
- **Por qué importa:** con 2136×3200 el driver recorta la escala del dedo; afecta también al cálculo de superres ×10.
- **Captura:** [LECTURA] `adb -s SERIE shell su -c 'getevent -p /dev/input/event11'`. [INTERACCIÓN] `adb -s SERIE shell su -c 'getevent -lt /dev/input/event11'` con un dedo en esquinas y centro.

### 3. Lápiz M80p / P81c (alto)
- **Qué falta:** rangos reales de cada entrada (presión 13 b vs 14 b, twist solo P81c, tecla 0x120 solo P81c). Origen del log `Xiaomi stylus m80p/p81c` no localizado (solo sale con lápiz conectado). Chequeo de la resolución ×10 en fw (abs 32000×21360).
- **Captura:** [LECTURA] `adb -s SERIE shell su -c 'getevent -p /dev/input/event12'` y `event13`; `adb -s SERIE shell su -c 'cat /proc/NVTSPI/pen_switch'` si existe. [INTERACCIÓN] lápiz conectado/hover, luego `dmesg | grep -i stylus` (dmesg rota por el spam de wifi: volcar en cuanto se conecte).

### 4. WiFi WCN6750 / ath11k (alto)
- **Qué falta:** confirmación de la BDF `bd_o82gl` (offset 1024, 58180 B) en el arranque y del tipo de API. Payload v2 (`2b0dd75a…`) sin probar. El gate «using board api 1» solo puede verse tras flash.
- **Captura:** [LECTURA] `adb -s SERIE shell su -c 'dumpsys wifi | head -n 200'` (firmware, chip, estado). Los binarios vendor ya están extraídos; no hace falta volver a leerlos. [REINICIO/ESCRITURA] instalar payload v2 y gate de `iw scan`: **no** es de este frente.

### 5. Bluetooth WCN6750 (medio)
- **Qué falta:** aceptación de `msnv12.bin` por `qca_tlv_check_data`; tensión `vddasd` 0,95 V no medida eléctricamente; firma del controlador (`QCA controller version`) real.
- **Captura:** [LECTURA] `adb -s SERIE shell su -c 'dumpsys bluetooth_manager | head -n 200'` (versión de controlador). [REINICIO/ESCRITURA] la carga `hci_uart` solo tras flash.

### 6. Audio WCD939x / FS19xx (medio)
- **Qué falta:** chip ID WCD939x (9390 vs 9395, INFERIDO 9395). DEVID real del FS19xx: no hay `/dev/i2c-*` en Android.
- **Captura:** [LECTURA] `adb -s SERIE shell su -c 'for f in /sys/bus/soundwire/devices/*/modalias; do echo $f $(cat $f); done'` (part-id SDW). `adb -s SERIE shell su -c 'for d in /sys/bus/i2c/devices/*; do echo $d $(cat $d/name 2>/dev/null); done'` (presencia FS19xx sin nodo /dev). [REINICIO] DEVID vía printk en arranque en frío, con doble captura: fuera de este frente.

### 7. Teclado folio Nanosic 803 y hall (medio)
- **Qué falta:** polaridad del hall (`lid_hall` SW_LID=0 gpio 99; `table_hall` SW_TABLET_MODE=1 gpio 100); protocolo I2C Nanosic a nivel byte.
- **Captura:** [LECTURA] `adb -s SERIE shell su -c 'cat /proc/bus/input/devices'` (nodo del hall y de los HID). [INTERACCIÓN] abrir y cerrar el folio mientras se ejecuta `getevent -lt` sobre el nodo de `xiaomi-hall`.

### 8. Batería y carga (medio)
- **Qué falta:** curva de carga con cargador de pared ≥45 W (Charging 1,098 A medido solo en L71). El estado actual 4082 mV es una foto, no una curva.
- **Captura:** [LECTURA] `adb -s SERIE shell su -c 'cat /sys/class/power_supply/*/uevent'` y `dumpsys battery`. [INTERACCIÓN] conectar el cargador y dejar muestreo periódico.

### 9. Sensores SSC-ADSP (bajo para este frente)
- **Qué falta:** solo el inventario existe (53 sensores en `tablet-sensorservice.txt`). Ningún sensor físico cuelga de I2C del AP; no hay datos vivos.
- **Captura:** [LECTURA] `adb -s SERIE shell dumpsys sensorservice` para refrescar el inventario. Datos vivos: no hay vía de solo lectura hasta el port SSC.

### 10. Cámara (bajo, sin RE)
- **Qué falta:** ningún análisis. `libnova.so` descartado (es cámara/QNN).
- **Captura:** [LECTURA] `adb -s SERIE shell su -c 'ls -l /dev/video* /dev/media*'` y `adb -s SERIE shell getprop | grep -i camera`.

### 11. Touch: `touch_report_debug` (bajo)
- **Qué falta:** 986.752 B sin examinar; podría traer más símbolos del parser de frames. Vía alternativa si el frame real falla.
- **Captura:** [LECTURA] extracción del `.ko` desde `/vendor/lib/modules/` (mismo patrón que el README).

## Resumen de lo que requiere al dueño
- Tocar la pantalla (ítems 1 y 2), conectar o acercar el lápiz (3), abrir o cerrar el folio (7), conectar el cargador (8).
- Reinicio o carga de módulo (cuentan como escritura, no solo lectura): frame THP con `insmod` (1), DEVID FS19xx (6), `hci_uart` (5), payload WiFi (4).
