# RE folio + hall + sensores — sesión nocturna 17-oct-2026

Lectura + RE estática + Ghidra. Sin builds, sin flash, sin escritura en tablet.
Artefactos: `artifacts/folio-sensores/` (módulos, decompilados, HID bin/hex, sensorservice, DTS borradores).

## 1. Teclado folio — HECHO

Cadena completa: **MCU Nanosic 803 por I2C → driver vendor la re-exporta como 4 HID → filtro vendor los observa**.

- **Transporte (HECHO)**: nodo DT `/soc/qcom,qupv3_0_geni_se@ac0000/i2c@a8c000/nanosic@4c`,
  compatible `nanosic,803`, `reg=0x4c`. Driver `nanosic_driver.ko` (358128 B, md5 b97ec7f5…,
  autor USUARIO@example.invalid) con `alias: of:N*T*Cnanosic,803` + `i2c:nanosic,803`
  (`modinfo`, HECHO). Vivo en tablet como `5-004c` en `i2c-5` (= `i2c@a8c000`, confirmado
  por `readlink …/i2c-5/of_node`, HECHO). Depende de `xiaomi_keyboard_driver,panel_event_notifier`.
- **GPIOs (HECHO, celdas BE)**: irq_pin TLMM 116 (flags 0x2001), reset 127, sleep 98, status 128.
  pinctrl `nanosic_keyboard_mcu`: default=gpio127+128 (drive 2, bias-disable), sleep=gpio98 (pull-down).
- **Supplies (HECHO)**: vdd=`pmxr2230_l22` 3,3 V fijo, dvdd=`pmxr2230_l23` 1,8 V fijo
  (phandles 0x357/0x358 resueltos por barrido de `phandle`; coincide con suppliers en
  `/sys …/5-004c`: ldob22/ldob23).
- **HID (HECHO, structs en .rodata + `llvm-objdump`)**: el driver monta un `Nanosic_hid_ll_driver`
  (`hid_allocate_device`/`hid_add_device`/`hid_input_report` en imports) con **bus forzado a 6
  (=BUS_BLUETOOTH), VID 0x15d9** y 4 descriptores embebidos en tabla en offset `0x1878`:
  keyboard PID 0x00a3 (61 B), mouse 0x00a2 (56 B), touch 0x00a1 (277 B, página Digitizer 0x0d),
  consumer 0x00a4 (25 B). Extraídos a `hid-desc-*.bin/.hex` (sha ea3772c6/3eef32d1/ba58e86f/5921bb88).
  Esto explica `/proc/bus/input/devices` en tablet: `0006:15D9:00A1-A4` → `Xiaomi Touch/Mouse/
  Keyboard/Consumer` (HECHO, `adb … cat /proc/bus/input/devices`).
- **Filtro (HECHO, Ghidra `decomp-keyboard/`)**: `xiaomi_keyboard_driver.ko` (69 KB) **NO es driver
  de bus**: `xiaomi_keyboard_ids` es tabla cero (=casa con todo) y `xiaomi_keyboard_input_connect`
  solo se engancha por nombre a `Xiaomi Touch|Consumer|Keyboard` (coincide con Handlers
  `xiaomi_keyboard` en input7/9/10, NO en Mouse). Crea `/proc/last_keypad_events`,
  `/proc/last_touchpad_events` + filtro de bordes/gestos touchpad con los params del DT
  (edge left 0-320, right 2879-3199, top 0-427, bottom 1708-2135; límites swipe en §DT).
  El `uinput-xiaomi` (0666:0888) lo crea el lado nanosic (chardev `Nanosic_input_write`), no este filtro.
- **Keylayout (HECHO)**: `ls /system/usr/keylayout|/vendor/usr/keylayout|/system/usr/idc | grep 15d9`
  → vacío. Sin `.kl`/`.idc` propios: usa `Generic.kl`. Nada que portar aquí.
- **Conclusión**: el folio por pogo-pines es **protocolo Nanosic propietario sobre I2C**
  (`bootID … not match`, `waiting for 803 i2c controller`, chardev propio), NO HID-over-I2C
  estándar. Mainline exige **driver nuevo** i2c→HID reutilizando los 4 descriptores extraídos;
  el filtro xiaomi_keyboard es prescindible (era telemetría+gestos MIUI). Borrador:
  `dts-nanosic-folio.dtsi`.

## 2. Hall — HECHO

- **Driver (HECHO, Ghidra `decomp-hall/xiaomi_hall_probe.c`)**: platform driver `xiaomi_hall`,
  **sin MODALIAS** (`modinfo` sin alias → casa por nombre con el nodo). Por cada hijo lee
  `label`, `linux,code`, `linux,input-type`, `hall_pin` (`of_get_named_gpio_flags`) y
  `open_irq`/`close_irq` (`of_irq_get_byname`), pide threaded IRQ (flags 0x2001,
  nombres `<label>_open/_close`) y registra input `xiaomi-hall`/`xiaomi-hall/input0`
  (bustype 0x19). Chardev `/dev/xiaomi_hall` + sysfs `disable_algo` (modo GPIO puro).
- **DT (HECHO)**: `/soc/xiaomi_hall`, compatible `xiaomi-hall`, status ok. Hijos:
  `lid_hall` (EV_SW=5, **SW_LID=0**, TLMM gpio 99) y `table_hall` (EV_SW=5,
  **SW_TABLET_MODE=1**, TLMM gpio 100). En tablet: input `xiaomi-hall` con `EV=21 SW=3`
  (HECHO, `/proc/bus/input/devices`).
- **Cl

ave (HECHO)**: los `interrupts-extended` NO van al TLMM sino a
  `qcom,smp2p-adsp/qcom,hall-in-lid` (phandle 0x55c, entry `mi_hall_lid`) y
  `…/hall-in-table` (0x55d, `mi_hall_table`), ambos `interrupt-controller` con
  `#interrupt-cells=2`. **Mainline `smp2p.c` del árbol k52 YA implementa irq_domain
  para inbound entries** (HECHO, `grep irq_domain|irqchip drivers/soc/qcom/smp2p.c`:
  `smp2p_irq_map`, `smp2p_irq_get_irqchip_state`). Ruta SMP2P portable.
- **Recomendación**: **ruta A `gpio-keys` sobre TLMM 99/100** (cero código, `wakeup-source`,
  verificar polaridad con evtest); ruta B = portar `xiaomi_hall.c` + nodos smp2p si A falla.
  Borrador con ambas: `dts-xiaomi-hall.dtsi`.

## 3. Sensores — HECHO (tabla)

`dumpsys sensorservice` completo en `tablet-sensorservice.txt` (53 sensores hw).
**Ningún sensor físico cuelga de buses I2C del AP** (barrido de todos los hijos
`i2c@*` de QUP0/QUP1: solo ktz8866, wcd939x, nanosic, cámaras, smartpa, ntag —
HECHO; `grep -ril lsm6ds|qmc6|stk3|sip1328|sx937…` en DT solo da nodos slpi/mem,
HECHO). Todo va por **SSC dentro del ADSP** (HAL `sensors.qsh.so`, servicios
`vendor.qsap.sensors`/`vendor.sensors running`; fw `adsp.mdt`+`adsp.bXX` presente;
`adspslpi_region@9d400000` en DT; sin ficheros `slpi*` sueltos = SLPI fusionado en ADSP).
`qti_qmi_sensor_v2.ko` (40 KB, volcado, md5 d79f2bd1) es solo cliente QMI **térmico**
(`qcom,qmi-sensors`, `QMI_BEAMER_*_THERM`), no IMU/luz.

| Sensor físico | Vía | Bus/addr AP | IRQ AP | Supplies AP | Compatible DT AP | Driver mainline k52 | Ruta |
|---|---|---|---|---|---|---|---|
| STMicro lsm6dso (acc+gyro, ≤416 Hz) | SSC/ADSP | — | — | — | — (ninguno) | **SÍ** `iio/imu/st_lsm6dsx` (lista LSM6DSO en `st_lsm6dsx.h`, HECHO) | SSC (fusión QTI/Xiaomi en ADSP) o IIO directo si se localiza el bus SSC — NO VERIFICADO |
| QST qmc630x (magnetómetro) | SSC/ADSP | — | — | — | — | **NO** (`grep -ril qmc63 drivers/iio` vacío; solo memsic mmc*, HECHO) | SSC; IIO directo exigiría driver nuevo |
| Sensortek stk3bcx (ALS+prox+CCT frontal) | SSC/ADSP | — | — | — | — | **NO** (`stk3310.c` no menciona stk3b*, HECHO) | SSC; driver nuevo si directo |
| SI sip1328 (back-lux + flicker) | SSC/ADSP | — | — | — | — | **NO** (cero hits en todo el árbol, HECHO) | SSC |
| Semtech sx937x (SAR) | SSC/ADSP | — | — | — | — | parcial: sx9310/24/60 sí, **sx937x NO** mencionado, HECHO | SSC |
| Virtuales (gravity, RV, steps, pickup…) | SSC algoritmos QTI/Xiaomi | — | — | — | — | n/a | SSC |

**Recomendación sensores**: ruta **SSC-ADSP** (llevar ADSP `remoteproc-adsp@03000000` +
firmware vendor y hablar SEE/QMI), NO IIO directo: 4 de 5 físicos carecen de driver y los
buses/IRQ/supplies ni siquiera existen en el DT del AP. Es un port grande, detrás del
táctil/BT/pantalla. Verificar a futuro si el árbol k52 trae algo SEE (`grep sensors-see`
en `drivers/iio` vacío, HECHO).

## 4. Ficheros nuevos (esta sesión)

- `artifacts/folio-sensores/{nanosic_driver.ko,qti_qmi_sensor_v2.ko}` (pulls `exec-out`, md5 arriba)
- `artifacts/folio-sensores/decomp-{keyboard,hall}/` (Ghidra 12.1.4, 31+14 funciones, 0 fallos)
- `artifacts/folio-sensores/hid-desc-{keyboard,mouse,touch,consumer}.{bin,hex}`
- `artifacts/folio-sensores/tablet-sensorservice.txt` (1370 líneas)
- `artifacts/folio-sensores/dts-{nanosic-folio,xiaomi-hall}.dtsi` (BORRADORES sin probar)

## 5. Líneas de evidencia (comandos)

- `modinfo …/nanosic_driver.ko` → alias of/i2c nanosic,803 + depends xiaomi_keyboard_driver
- `adb … 'cat /proc/bus/input/devices'` → xiaomi-hall EV=21 SW=3; 0006:15D9:00A1-A4
- `adb … readlink /sys/bus/i2c/devices/i2c-5/of_node` → `…/i2c@a8c000`; `5-004c` name `803`
- `od -An -tx1` + barrido `phandle` → 0x16b=tlmm, 0x55c/0x55d=smp2p hall, 0x357/0x358=ldob22/23
- `dumpsys sensorservice` → lsm6dso/qmc630x/stk3bcx/sip1328/sx937x, todos tras QSH/SSC
- Pendiente (NO VERIFICADO): polaridad hall para gpio-keys; protocolo I2C Nanosic a nivel byte.
