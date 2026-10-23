# PERIFÉRICOS — cosecha Android con root (17-oct-2026)

Método: adb inalámbrico (`192.0.2.13:5555`, root Magisk) + DT completo volcado a
`build/android/dt-full-uke-android.tar` (30,8 MB, descomprimido en /tmp/dtfull — referencia
definitiva para TODA pregunta futura de nodos, sin tocar la tablet). Dmesg vendor:
`build/android/cosecha-20261017/01-dmesg.txt`.

## TÁCTIL + LÁPIZ (NVT-ts, SPI)

- Nodo DT: `/soc/qcom,qupv3_0_geni_se@ac0000/spi@a90000/novatek@0` — **SPI geni a90000 (QUP0)**,
  compatible `novatek,NVT-ts-spi`, `spi-max-frequency` = 0x0124F800 = **19,2 MHz**, `reg=<0>`,
  status ok. `xiaomi_touch` node aparte (framework).
- GPIOs: **irq-gpio = 387**, **lcd_id-gpio = 359**, `lcd_id_value=1` → **panel CSOT** (¡nuestra
  unidad es la variante CSOT!), `novatek,pen-support=1`, `novatek,stylus-resol-double=1`.
- IC verificado NVT (`check_chip_ver_trim`, chip_ver_trim_addr=0x1fb104, swrst_sif 0x1fb43e).
- Inputs: `NVTCapacitiveTouchScreen` + **`NVTCapacitivePenM80p`** + **`NVTCapacitivePenP81c`**
  (los dos lápices Xiaomi).
- Nuestro port `0001-touch`: revisar bus (¿lo pusimos en I2C o SPI?) y GPIOs contra esto.

## BLUETOOTH (WCN6750)

- Nodo: `/soc/bt_wcn6750`, compatible **`qcom,wcn6750-bt`**, status ok (nodo de PLATAFORMA, sin
  UART padre: el transporte del vendor es su driver propio/icnss, no serdev).
- **`qcom,bt-reset-gpio` = TLMM 156** (specifier: phandle tlmm 0x16b, gpio 0x9C=156) — **el mismo
  GPIO 156** que ya identificamos como bt-enable en la causa-raíz WiFi (¡conflicto egpio confirmado
  desde el DT vendor!). `qcom,bt-sw-ctrl-gpio` aparte. pinctrl = `bt_en_sleep`.
- Reguladores: vdd-aon / vdd-dig / vdd-io / vdd-rfa-0p8 / vdd-rfa1 (phandles en DT; mainline
  definirá los suyos).
- Firmware BT: NO está en /vendor/firmware ni firmware_mnt como fichero suelto (va dentro del
  paquete kiwi). Para mainline: `linux-firmware` trae el par hpbtfw/hpnv de WCN6750.
- Port mainline: `hci_qca` soporta `qcom,wcn6750-bt` como **serdev bajo un UART** → falta
  elegir/cablear UART en NUESTRO DT (candidatos vistos: qup_uart@888000 QUP1, qup_uart@a94000
  QUP0; pinctrl qupv3_se5_2uart / qupv3_se10_4uart). Verificar qué UART está libre en nuestro
  árbol (los QUP que no use el display/touch: el táctil ya ocupa a90000; la consola usa 888000
  qup_uart como serial debug del vendor — ATENCIÓN: 888000 también es nuestro ttyMSM de consola).

## WLAN

- Chip **qca6750 = WCN6750 (kiwi)**; firmware vendor en `/vendor/firmware/wlan/qca_cld/kiwi_v2`
  (+dir `qca6750`), fw path del cmdline: `/vendor/firmware_mnt/image/kiwi`. Nuestro port ath11k
  (0002-wifi, rieles ya mapeados) usa la familia kiwi de linux-firmware.

## AUDIO

- Codec **wcd939x**: `lpass-cdc/wcd939x-codec` + `wcd939x-i2c@e` en **i2c@a80000** (¡coincide con
  el 2-000e que vimos en nuestro i2c-2 en L43!). Audio por SPF/lpass-cdc = stack en ADSP
  (misma familia que nuestro uke-adsp): port grande, hablar GPR/SPF.

## TECLADO FOLIO / HALL / SENSORES

- Driver **xiaomi-keyboard** (keypad + touchpad + mouse virtual `uinput-xiaomi`, "Xiaomi
  Keyboard/Mouse/Touch/Consumer") + `xiaomi-hall` como input (detección folio).
- **Sensores: sin IMU en IIO** — los sensores van por ADSP/SSC (port aparte, grande).

## Deuda/uso

- El DT completo está local: resolver nodos = grep en /tmp/dtfull (o re-extraer el tar).
- BT: decidir UART y validar en mainline hci_qca wcn6750 (reset 156 libre en nuestro DT egpio).
- Táctil: cuadrar nuestro 0001-touch con (SPI a90000, freq 19,2 MHz, irq 387, lcd_id 359).
- Prioridad sugerida de puerto tras la pantalla: táctil+BT (son los que hacen usable la tablet).
