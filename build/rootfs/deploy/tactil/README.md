# Táctil NT36532 (TDDI, SPI) — uke, kernel senemos

Estado (18-oct-2026): `spi0.0` (compatible downstream `novatek,NVT-ts-spi`, bajo `spi@a90000`, 19,2 MHz, IRQ = tlmm 54
flanco de subida, sin reset propio: lo lleva el panel, `touch_reset_state`) existe pero **sin driver**; no hay input.
En Android el chip trabaja en **modo THP**: entrega rejillas crudas de capacitancia 40×60 y las coordenadas las calcula
el HAL de Xiaomi en espacio de usuario (build/android/perif-20261017/touch-dedo/README.md: cabecera 64 B + mutual u16[2400],
base ~10000, dedo +1100..1280; fila = X/21360·40, col = Y/32000·60). Firmware del chip: `novatek_nt36532_o82_fw_csot.bin`
(RAM; Android lo pide a los ~17,6 s) — copia en ~/proyectos/ubuntu-uke/stock/firmware/ (NO redistribuir).

## Pasos (requieren orden del dueño: escriben en sysfs / cargan módulo)
1. `modprobe spidev; echo spidev > /sys/bus/spi/devices/spi0.0/driver_override; echo spi0.0 > /sys/bus/spi/drivers/spidev/bind`
   → `/dev/spidev0.0` (no envía nada por el bus).
2. `uke-touch-probe.py` → lee FWINFO (0x125878). `fw_ver == ~fw_ver` ⇒ firmware vivo. Solo lecturas (+ selección de página).
3. `uke-touch-probe.py --frames 20` con y sin dedo → ¿llegan rejillas THP con cabecera válida y el dedo se ve en el pico?
Si el firmware NO está vivo, hace falta descargarlo (protocolo de bootloader del vendor): etapa aparte, con más riesgo
(el chip es TDDI: un reset mal hecho puede afectar al display).

## Plan si los frames llegan
Demonio en espacio de usuario: IRQ (gpio 54) → lectura del bloque THP → resta de línea base → blobs (umbral, componentes
conexas, centroide ponderado con interpolación) → seguimiento de IDs → eventos multitáctiles por `/dev/uinput`
(ABS_MT_SLOT/TRACKING_ID/POSITION_X/Y, 2136×3200 ó la resolución del panel con la rotación de Hyprland).

## Resultado de la sonda (18-oct ~00:35, orden del dueño)
- spidev ligado a spi0.0 (`/dev/spidev0.0`, bufsiz 16384). Lecturas a 4 MHz:
  - `0x1fb104` (chip_ver_trim) = `0e 00 04 32 65 03 10 00` ×2 → **idéntico a Android** (`buf[1..6]=0x0E 00 04 32 65 03`):
    el protocolo SPI (página + lectura con dummy) es correcto y el chip responde.
  - FWINFO `0x125878` y EVENT `0x125800` = bytes pseudoaleatorios ESTABLES entre lecturas → RAM sin inicializar:
    **el chip no tiene firmware en Linux** (en Android lo descarga `update_firmware_request` a los ~17,6 s).
  - GPIO 54: in, low, pull-down (sin actividad de IRQ, coherente con firmware ausente).
- Siguiente: cargador de firmware por SPI (protocolo del bootloader NT36532) → luego frames THP → demonio uinput.

## Demonio THP (18-oct ~01:00) — validado en el PC
- `thp_algo.py`: base plana inicial (mediana del frame; f0000 de la captura ya trae un dedo) + adaptación solo sin toque,
  picos locales ≥600 cuentas, centroide 3×3 ponderado, seguimiento de IDs por distancia.
- `thp_validate.py <frames> trace.txt getevent.txt` contra la captura de Android (verdad = HAL de Xiaomi), desfase de relojes
  por barrido: **1224 dedos emparejados, 4 falsos positivos, 1 falso negativo; error mediana 10 px, p90 31 px, máx 34 px**.
- `uke-touchd.py`: IRQ por gpio v2 (tlmm 54, flanco de subida; fallback de sondeo) → lectura del bloque THP → algoritmo →
  `/dev/uinput` multitáctil tipo B (INPUT_PROP_DIRECT, 3200×2136). Orientación ajustable (--swap-xy/--invert-*), sin probar
  en la tablet: falta el firmware del chip.

## Corrección: mapa CASCADE (18-oct ~01:10)
El chip es "Cascade Chip" (bit0 de 0x1fb12c = 0): EVENT_BUF = **0x11c400** (FWINFO 0x11c478, estado de reset 0x11c460), no
0x125800 (mapa single, el que leyó la sonda). `uke-touch-fwload.py --verify-only` en la tablet: FWINFO cascade = `bb 3d …`,
**idéntico al "FW info is broken! fw_ver=0xBB ~fw_ver=0x3D" de Android antes de su descarga (10,5 s)** → sin firmware, confirmado.
Tras la descarga Android lee fw_ver 0x11, PID 0x5993, 32000×21360 (17,77 s). uke-touchd.py ya usa 0x11c400.

## TÁCTIL FUNCIONANDO (18-oct ~01:25, orden del dueño)
- `uke-touch-fwload.py --execute` (fw en /lib/firmware, sha a4f949fb…): descarga en **0,20 s**, 58 transferencias, estado de
  reset `a0` OK, FWINFO `fw_ver 0x11 PID 0x5993 32000×21360` (= Android). Display intacto (underrun 0).
- `uke-touchd.py` (unidad transitoria de systemd): IRQ por gpiochip6 línea 54, **120 frames/s válidos, 0 malos**; dispositivo
  "uke NT36532 THP touchscreen" (event3). Orientación medida tocando esquinas: X correcto, **Y invertido** (ahora por defecto).
- **El dueño confirma: "el táctil reacciona donde toco"** en el escritorio Omarchy.
- Límites: no persiste (spidev, firmware y demonio son en caliente); un reset del panel (apagado de pantalla / suspend) borra
  el firmware del chip (el vendor lo recarga en cada resume); el demonio en Python gasta ~36 % de un núcleo a 120 Hz.

## Persistente + recarga tras reset del panel (18-oct ~01:45)
- `uke-touch.service` (enabled; `deploy.sh apply|start|status|revert`): ExecStartPre `uke-touch-up.sh` (spidev + uinput +
  bind de spi0.0), demonio con uke-bootguard (`touch`) e interruptores `/etc/uke/no-touch` / `safe-mode`. Restart=on-failure.
- El demonio vigila `touch_reset_state` del panel O82 (senemos: "<generación> <listo>" + sysfs_notify): con listo=0 se pausa;
  con generación nueva y listo=1 recarga el firmware (subproceso uke-touch-fwload.py --execute --force). Si no llegan IRQ en
  3 s con el panel listo, comprueba FWINFO y recarga si hace falta.
- Medido: DPMS off (`hl.dsp.dpms({action="off"})`) → `2 0`; on → `3 1` → **recarga en 0,32 s, FWINFO OK**; underrun 0.
- CPU: vía rápida de reposo (max() en C + base cada 16 frames) → **3,4 % de un núcleo en reposo** (antes ~36 %); misma
  precisión en la validación contra Android (`thp_validate.py --fast`: 1224/4/1, mediana 10 px).
- **El dueño confirma que el táctil responde tras el apagado/encendido de pantalla.**
- Sin probar: arranque en frío con el servicio (orden respecto a sddm: si el modeset resetea el panel, la recarga lo cubre).

## Consumo de CPU (19-oct-2026)
Medido en la tablet con el demonio en reposo (sin tocar), `/proc/<pid>/stat` durante 30 s:
- antes: **36 %** de un núcleo (32 % user + 3 % sys): el chip lanza ~180 IRQ/s y se procesaba cada frame en Python.
- después: **10 %** (`--idle-div 3`, por defecto): en reposo procesa 60 frames/s y duerme entre ellos (los flancos se acumulan en
  el fd del GPIO y se vacían de una vez); con dedo, o durante `--hold-ms 500` tras levantarlo, procesa todos. Además, sin
  repack del `spi_ioc_transfer` ni `memset`/copia de 5 KB por frame, y solo se leen cabecera+rejilla (4864 B).
  Coste: el primer toque tras el reposo se detecta hasta ~16 ms más tarde. El chip no espera a que se lea el frame (las IRQ
  siguen a 180/s aunque se salten lecturas). Algoritmo intacto: `thp_validate.py --fast` igual (1224 dedos, 4 FP, 1 FN).
