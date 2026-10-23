# REV-TACTIL #528 — Revisión táctil+lápiz NT36532 del port uke (5-oct-2026)

Revisor: subagente táctil+lápiz. **La tablet NO se ha tocado** (cero adb; todo
análisis sobre la captura `android-full/extracted-full/` de #527 y sobre el
árbol del kernel en **solo lectura**).

Fuentes (evidencia):
- `build/evidencia/android-full/extracted-full/05-touch/` — `dmesg-touch.txt`,
  `getevent-lp.txt`, `input-devices.txt`, `interrupts.txt`, `proc-nvt.txt`,
  `firmware/listing.txt` (ojo: `dt-nodes-all.txt` y `novatek-paths.txt`
  salieron **vacíos** en la captura; el DT se analizó desde `14-dt/dt-live.tar.gz`).
- `build/evidencia/android-full/extracted-full/06-pen/` — `dmesg-pen.txt`,
  `input-pen.txt`, `dumpsys-input-pen.txt` (`dt-pen-nodes.txt` vacío: no hay
  nodos DT dedicados al lápiz).
- `build/evidencia/android-full/extracted-full/14-dt/dt-live.tar.gz` — DT vivo
  completo (extraído a `/tmp/dtlive` para análisis; NO commiteado).
- `build/evidencia/android-full/extracted-full/15-common/` — `dmesg-full.txt`,
  `gpio.txt`, `lsmod.txt`.
- `dt-nodes-pc/soc/qcom,qupv3_0_geni_se@ac0000/spi@a90000/novatek@0/` — props
  crudas del nodo táctil (109 props con hijos mp-criteria).
- Kernel: `~/gpu-work/palawan-linux` (rama `s150-postclk`, archivos
  leídos en solo lectura), build `~/gpu-work/build-uke/.config`.

---

## 1. Nodo DT vivo del táctil (spi@a90000/novatek@0) — decodificación completa

Fuente: `dt-nodes-pc/.../novatek@0/*` (valores big-endian crudos) + resolución
de phandles contra `14-dt/dt-live.tar.gz`.

### 1.1 Props escalares del nodo (nivel superior)

| Prop (valor crudo)                 | Decodificado                                                                 |
|------------------------------------|------------------------------------------------------------------------------|
| `compatible = novatek,NVT-ts-spi`  | exacto, mayúsculas incluidas                                                  |
| `spi-max-frequency = 0x0124f800`   | **19 200 000 Hz (19.2 MHz)**                                                  |
| `novatek,irq-gpio = <0x16b 0x36 0x2001>` | phandle `0x16b` = `/soc/pinctrl@f000000` (tlmm), **GPIO 54**, flags **0x2001** (ACTIVE_LOW + flag QCOM 0x2000, no estándar upstream) |
| `novatek,lcd_id-gpio = <0x16b 0x1a 0x0>` | **GPIO 26**, entrada de identificación de panel (vivo: `in high func0 2mA no pull`) |
| `panel = <0x6b4 0x6b5>`            | phandles de los 2 paneles: `0x6b4` = `qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid` (el ACTIVO de esta unidad, ver cmdline `msm_drm.dsi_display0=` en `02-display/cmdline-video.txt`) y `0x6b5` = `o82_36_02_0a`. El driver lo usa para elegir fw por panel |
| `pinctrl-0/1 = <0x565 0x566>`      | `mi_ts_spi_cs_active` / `mi_ts_spi_cs_suspend`; `pinctrl-names = "pmx_ts_active" "pmx_ts_suspend"` |
| `reg = <0>`                        | chip-select 0 (vivo: `spi1.0`)                                                |
| `status = "ok"`                    | —                                                                             |
| `novatek,pen-support`              | booleano VACÍO (presente) → lápiz habilitado                                   |
| `novatek,stylus-resol-double`      | booleano presente (resolución del stylus)                                      |
| `novatek,mp-support-dt`            | booleano presente (criteria MP por DT)                                         |
| `novatek,touch-game-param-config1/2/3` | u32[4]/[4]/[4]: `<2 2 1 2> <2 2 2 1> <2 2 3 1>` (game mode, cosmético)     |
| `mi_tp,*` (10 arrays: active-mode, game-mode, edge-filter, report-rate, tap-stability, up-threshold, tolerance, aim-sensitivity, expert-mode, panel-orien) | arrays u8 del framework Xiaomi (`xiaomi_touch`), NO los lee el driver NVT para funcionar |

**NO hay** en el nodo vendor: `reset-gpios`, `*-supply` (vdd/vddio),
`fw-name`, `touchscreen-size-*`, `swap/flip`. Es **TDDI** (el chip táctil
comparte troquel con el panel; los rieles vienen del panel y el fw ya está en
flash interna del IC — ambos nodos de panel llevan `mi,is-tddi-flag`).

### 1.2 Hijos `novatek-mp-criteria-5993@0` y `novatek-mp-criteria-5994@0`

Criteria de MP (fabricación) por pid; valores: `X_Channel=Y_Channel=
IC_X_CFG_SIZE=IC_Y_CFG_SIZE = 0x3c/0x28` = **60 canales X, 40 canales Y**
(coincide con `/proc/nvt_fw_version`: `fw_ver=17, x_num=60, y_num=40`), más
límites PS_Config_Lmt_* (rawdata/diff/open/short/CC y **PenTip/PenRing X/Y**).
Ojo: los nodos son para pids **0x5993/0x5994**; el chip vivo reporta pid
**0x5981** (sin criteria propia). Para mainline: irrelevantes (son de fábrica).

### 1.3 Pinctrl referenciado (resuelto del DT vivo)

- `mi_ts_spi_cs_active` (0x565): `pins="gpio19"`, `function="qup0_se4_l3"`,
  `bias-disable`, `drive-strength=6` (mux), y config `gpio19` bias-disable DS6.
- `mi_ts_spi_cs_suspend` (0x566): gpio19 gpio function, `output-low`,
  `bias-pull-down`, DS2.
- El controlador `spi@a90000` (QUP0 **SE4**) usa `pinctrl-0 = <0x206 0x207 0x561>`
  = `qupv3_se4_spi_pins/qupv3_se4_spi_mosi_active`, `..._miso_active`,
  `mi_ts_spi_clk_active` y `pinctrl-1 = <0x562..0x564>` = mosi/miso/clk suspend.
  Pines del bus: **MISO gpio16, MOSI gpio17, CLK gpio18, CS gpio19**.
- Estados suspend residuales `pmx_ts_int_suspend` (gpio129) y
  `pmx_ts_reset_suspend` (gpio128) del árbol vendor corresponden al hermano
  `goodix-berlin@0` del mismo bus (nodo casi vacío, no probed) — no del Novatek.

### 1.4 Estado vivo real (runtime)

- `/proc/interrupts:248` → `359: ... msmgpio 54 Edge xiaomi_tp` (2858 eventos
  en la captura). **IRQ = msmgpio 54, Edge.**
- `15-common/gpio.txt` (gpiochip0 = f000000.pinctrl, GPIOs 333-511):
  `gpio16 in func0`, `gpio17 out func0`, `gpio18 in func0`,
  **`gpio19 out func1 6mA no pull`** (= qup0_se4 CS activo),
  **`gpio54 in low func0 2mA pull down`**, `gpio26 in high`, `gpio128/129 in high`.
- `15-common/lsmod.txt`: `xiaomi_touch 176128 4 nt36532_touch` — el driver del
  vendor es el módulo **`nt36532_touch`** sobre el framework `xiaomi_touch`.

## 2. Diff prop-a-prop con nuestro `xiaomi-uke.dts`

`arch/arm64/boot/dts/qcom/xiaomi-uke.dts` (556 líneas, HEAD `59e9e0f6e`)
**NO tiene NADA de táctil**: ni nodo SPI, ni INT, ni pinctrl propio. Lo único
que ya existe es infraestructura del SoC:

| Pieza vendor (vivo)                        | Nuestro árbol (palawan.dtsi/uke.dts)                          | Estado |
|--------------------------------------------|----------------------------------------------------------------|--------|
| `spi@a90000` QUP0 SE4, `qcom,spi-geni`, IRQ GIC 357 | `spi4: spi@a90000` (palawan.dtsi:1978, `qcom,geni-spi`, `GIC_SPI 357`) | EXISTE, `status` no ok |
| pinctrl bus MISO16/MOSI17/CLK18 (qup0_se4) | `qup_spi4_data_clk` (palawan.dtsi:4155: gpio16/17/18, `qup0_se4`, DS6 bias-disable) | **IDÉNTICO al vendor** |
| pinctrl CS gpio19 qup0_se4_l3 DS6          | `qup_spi4_cs` (palawan.dtsi:4148: gpio19, `qup0_se4`, DS6 bias-disable) | **IDÉNTICO al vendor** |
| nodo hijo `novatek@0` (compatible, freq 19.2M, CS0) | **AUSENTE** → FIX F1                                    | FALTA TODO |
| INT gpio54 Edge                            | gpio54 libre (el `gpio-reserved-ranges <56 5>` del QRD no se copió, bien) | FALTA `interrupts-extended` |
| `mi_ts_spi_cs_active/suspend` custom       | no hacen falta: el pinctrl `default` de `spi4` ya muxa CS      | opcional |

Conclusión del diff: **solo hay que añadir** el `&spi4 { status ok }` + nodo
hijo táctil con IRQ. Cero pinctrl nuevo obligatorio (el del dtsi coincide pin a
pin y función a función con el DTBO vendor).

## 3. IRQ 54 — verificación cruzada

- Vendor DT: `novatek,irq-gpio = <&tlmm 54 0x2001>` (el driver vendor hace
  `gpio_to_irq`; flags 0x2001 = activo-bajo + flag privado QCOM).
- Vivo: `msmgpio 54 Edge xiaomi_tp` (`05-touch/interrupts.txt:248`), pin en
  `in func0 2mA pull down`.
- Nuestro port: el driver (`novatek-nt36xxx-spi.c:612`) usa `spi->irq` con el
  trigger que venga del DT (`irq_get_trigger_type`). `interrupts-extended =
  <&tlmm 54 IRQ_TYPE_EDGE_FALLING>` es la traducción correcta (Novatek clásico
  = flanco de bajada, consistente con ACTIVE_LOW del vendor). **Reserva**: si
  en hw no llegan eventos, probar `IRQ_TYPE_EDGE_RISING` (el vivo lee la línea
  "low" en reposo con este fw; una sola línea que cambiar).
- No hay que tocar tlmm para el mux (func0/gpio es el estado correcto de una
  IRQ de entrada; el `bias-pull-down` vivo es del driver vendor y no es
  requisito del nuestro).

## 4. Driver — veredicto

Hallazgo principal de esta revisión: **el fork YA NO depende de portar nada**.
`~/gpu-work/palawan-linux/drivers/input/touchscreen/novatek-nt36xxx-spi.c`
(657 líneas, commit `20f0df992` "uke display/touch: panel O82 dual-DSI DSC +
touch NT36xxx SPI (bring-up)") es un port propio ya integrado:

- compatible `{"novatek,NVT-ts-spi"}` (el EXACTO del nodo vendor) + alias
  `"novatek,nt36xxx-spi"` (líneas 637-641). El comentario del propio
  `xiaomi-uke.dts:533` («driver por portar; el fork solo trae nt36672a»)
  está **desfasado**: `nt36672a` es un panel DRM, no un driver de input, y el
  driver táctil ya está escrito y cableado en
  `drivers/input/touchscreen/{Makefile:72,Kconfig:704}`
  (`CONFIG_TOUCHSCREEN_NOVATEK_NT36XXX_SPI`).
- Transporte SPI **verificado contra el .ko vendor** (`nt36532_touch.ko`
  desensamblado): write `[cmd|0x80][payload][0x00]` con 5 reintentos, page
  select 0xFF con `[A22:15][A14:7]`, lectura full-duplex con datos en
  `rbuf[2]`, EVENT_BUF 0x125800, frame 257 B con sync 0xFD/0xFE y checksum
  aditivo 64+1. NO es el driver upstream: `novatek-nvt-ts.c` (I2C, NT11004)
  y el `nt36xxx` upstream clásico no hablan este protocolo de SPI/page-select.
- Lo que lee del DT: `spi->irq`, `novatek,pen-support` (solo avisa, línea 553),
  `reset-gpios` **opcional**, `vdd`/`vddio` **opcionales** (dummies sin DT),
  `touchscreen-size-x/y` vía `touchscreen_parse_properties`.
- **Lo que NO hace aún**: (1) layout del record de dedo SIN verificar — hay 3
  candidatos seleccionables con `/sys/module/novatek-nt36xxx-spi/parameters/
  point_layout` (0=A por defecto, 1=B 7B clásico, 2=C 5B LE); (2) **lápiz no
  implementado**; (3) **no carga fw** (asume el de flash, razonable en TDDI).

**Veredicto**: usar el port propio ya existente (fase bring-up) y NO portar el
módulo cerrado `nt36532_touch` (depende de `xiaomi_touch.ko` + panel_event_notifier
+ HAL; 176 KB de infraestructura Xiaomi). Upstream no es opción para v1.

### El lápiz (P4)

- Vendor expone **3 input devices virtuales** (`05-touch/input-devices.txt:119-150`):
  `NVTCapacitiveTouchScreen` (MT slots 0-9, X 0-21359, Y 0-31999, TOUCH_MAJOR
  255, KEY_POWER/KEY_WAKEUP), `NVTCapacitivePenM80p` (X/Y idem, PRESSURE 8191,
  DISTANCE 0-1, TILT ±60, BTN_DIGI/BTN_TOUCH) y `NVTCapacitivePenP81c` (PRESSURE
  16383, + `ABS_BRAKE` 0-360 = rotación, BTN_JOYSTICK). Todos `INPUT_PROP_DIRECT`.
- El DT solo marca `novatek,pen-support` + `novatek,stylus-resol-double`; no
  hay nodos DT del lápiz (`06-pen/dt-pen-nodes.txt` vacío — correcto).
- El decodificado de tramas de pen vive en el `.ko` vendor (el frame completo
  es de 5176 B y el .ko pasa raw a `xiaomi_touch`); **ni upstream ni nuestro
  port lo soportan**. Fix F5 = port de los handlers de pen como fase 2 del
  driver propio, tras confirmar el layout de dedo (mismo bus de eventos).

### Hall del lápiz (P5)

- **No hay GPIO ni nodo DT para el hall del pen**: `pen_hall3`/`pen_hall4`
  llegan por **pmic_glink/battery** desde el ADSP
  (`06-pen/dmesg-pen.txt`: `qti_battery_charger ... POWER_SUPPLY_PEN_HALL3=0,
  POWER_SUPPLY_PEN_HALL4=1`, `pen_hall4_show`, `pen_soc_show 255`). El nodo
  `soc/xiaomi_hall` del DT vivo es otra cosa: `lid_hall` = **gpio99** y
  `table_hall` = **gpio100** (activos-bajos, IRQs own) para la tapa/teclado.
- Para el port: cuando `qcom_battmgr` esté vivo (ya hay 90 líneas de trabajo
  pendientes en el árbol), exponer esas power supply ext-props; el lápiz en sí
  no depende del hall.

## 5. Firmware (P2, nombre + ubicación)

- Nombre pedido por el driver vendor: **`novatek_nt36532_o82_fw_csot.bin`**
  (`15-common/dmesg-full.txt:17.890849` `update_firmware_request: filename is
  novatek_nt36532_o82_fw_csot.bin`; resuelto por ueventd desde
  **`/odm/firmware/`** — `05-touch/firmware/listing.txt`:
  `novatek_nt36532_o82_fw_csot.bin`, `..._fw_tm.bin`, `..._mp_csot.bin`,
  `..._mp_tm.bin`). El sufijo lo elige el driver por el panel activo:
  **42_02_0b = CSOT** (esta unidad, `dsi_display0=o82_42_02_0b...` en
  cmdline), 36_02_0a = tm. Tamaño flasheado: **245760 B (0x3c000)**, formato
  NVT "cascade" con 2º header (ilm_dlm_num=2, info_sec_num=14, partition=16).
- **Para nuestro port v1 NO hay que empaquetar nada**: nuestro driver no llama
  a `request_firmware` y el IC es TDDI con fw en flash interna (Android la
  re-flashkea cada boot; el chip arranca el fw propio con el panel).
- Si algún día el flash estuviera vacío/corrupto: copiar
  `novatek_nt36532_o82_fw_csot.bin` a `/lib/firmware/novatek/nt36532/` y
  portar el protocolo de update del .ko (formato cascade) — FASE 2, extraer el
  bin en la próxima sesión con Android (hoy la tablet no se toca).

---

## 6. FIXES priorizados

### F1 (P0) — Bloque DT listo para pegar en `arch/arm64/boot/dts/qcom/xiaomi-uke.dts`

Sintaxis del árbol real (labels de palawan.dtsi; `IRQ_TYPE_*` y `GPIO_*` ya
disponibles vía includes del dtsi). Añadir donde v2/v4 (después de `&gpu`):

```dts
/* ---- v4 (G5): táctil Novatek NT36532, QUP0 SE4 SPI, INT tlmm 54 ----
 * Nodo espejo del DTBO vendor (dt-nodes-pc/.../spi@a90000/novatek@0):
 * compatible/CS/freq exactos; INT via interrupts-extended (el vendor usa
 * novatek,irq-gpio <&tlmm 54 0x2001> + gpio_to_irq). Sin reset ni
 * supplies: TDDI, los rieles van con el panel (dependencia: fase display).
 * El pinctrl del bus (gpio16 MISO / gpio17 MOSI / gpio18 CLK / gpio19 CS,
 * function qup0_se4) ya lo trae palawan.dtsi (qup_spi4_data_clk/cs). */
&spi4 {
	status = "okay";

	touchscreen@0 {
		compatible = "novatek,NVT-ts-spi";
		reg = <0>;

		spi-max-frequency = <19200000>;
		interrupts-extended = <&tlmm 54 IRQ_TYPE_EDGE_FALLING>;

		/*
		 * Rango del vendor: abs_x_max=2136, abs_y_max=3200
		 * (dmesg-touch.txt:101). El input vendor multiplica x10 para
		 * usuarios (getevent 21359/31999), pero el IC reporta records
		 * de 12 bits => en píxeles. Ajustar swap/flip tras triaje hw.
		 */
		touchscreen-size-x = <2136>;
		touchscreen-size-y = <3200>;

		/* Sin reset-gpios / vdd / vddio: el nodo vendor no los trae y
		 * el driver los trata como opcionales. novatek,pen-support
		 * existe en vendor pero el driver aún no implementa stylus:
		 * añadirla solo imprimiría el aviso del probe. */
	};
};
```

Notas del bloque:
- `novatek,lcd_id-gpio`, `panel`, `mi_tp,*`, game-params y mp-criteria se
  **omiten a propósito**: nuestro driver no los lee.
- Si el triaje muestra que el pull-down de gpio54 hace falta en suspend, el
  driver vendor lo emula; para v1 no hace falta pinctrl extra en tlmm.

### F2 (P0) — Config del build

`~/gpu-work/build-uke/.config` **no contiene el símbolo**
`CONFIG_TOUCHSCREEN_NOVATEK_NT36XXX_SPI` (el .config es anterior al commit
`20f0df992`; solo tiene `TOUCHSCREEN_NOVATEK_NVT_TS not set`). Fijar:

```
CONFIG_TOUCHSCREEN_NOVATEK_NT36XXX_SPI=y
```

(`=y` y no `=m`: el táctil se quiere en el shell del primer boot; `INPUT_TOUCHSCREEN=y`
ya está.) Ejecutar `olddefconfig` para que el nuevo símbolo entre.

### F3 (P1) — Triaje de layout + defaults del driver

1. Boot con el DT de F1 y `evtest`: tocar con UN dedo en esquinas opuestas;
   decidir `point_layout` (0/1/2, module param ya expuesto) y swap/flip de
   size-x/y; fijar el layout elegido en el código y borrar los otros dos.
2. Los defaults del driver están mal para uke: `NVT_SPI_DEF_X_SIZE 1600`,
   `NVT_SPI_DEF_Y_SIZE 2136` (`novatek-nt36xxx-spi.c:80-81`; el comentario
   "1600x2136" del propio DTS:533 también). El vendor dice **2136x3200**. El
   DT de F1 lo corrige, pero corregir los `#define` a 2136/3200 para que un
   boot sin props de tamaño no mienta.
3. Actualizar el comentario desfasado de `xiaomi-uke.dts:533` («driver por
   portar…»): ya existe el driver y el compatible casa.

### F4 (P1) — Dependencia display (orden de enchufado)

TDDI: sin panel alimentado el IC no habla (el probe de nuestro driver lo
detectará con `chip_alive_check` y seguirá sin chip). Enchufar el nodo táctil
en el MISMO commit/etapa que la fase 4 de display (panel `xiaomi,uke-o82-4202-0b`
= 42_02_0b = CSOT, que es el panel de esta unidad según cmdline+fw). No es un
bug, es orden de integración.

### F5 (P2) — Lápiz (tras v1 táctil)

Portar los handlers de pen al driver propio: segundo registro de eventos por
frame (el frame vendor completo es 5176 B, no los 257 B del v1), targets:
`NVTCapacitivePenM80p` (X/Y 21360x32000, pressure 8191, distance, tilt ±60,
BTN_DIGI) y `NVTCapacitivePenP81c` (pressure 16383, + ABS_BRAKE 0-360 rotación,
BTN_JOYSTICK), tal y como los expone el vendor (`getevent-lp.txt:20-44`).
Requiere descodificar la zona de pen del frame grande contra el `.ko`.

### F6 (P2) — Hall del pen vía pmic_glink

Sin DT: son ext-props de la batería (`POWER_SUPPLY_PEN_HALL3/HALL4`, `pen_soc`)
que el ADSP publica por pmic_glink. Extender `qcom_battmgr.c` (ya hay trabajo
en curso en el árbol) para publicarlas; útil para uevent de "lápiz alojado",
no para el input del stylus.

## 7. Riesgos

1. **Layout de dedo sin verificar** (el .ko no decodifica, delega en
   xiaomi_touch): v1 puede requerir 1-2 iteraciones de triaje en hw con
   `point_layout` + swap/flip. Es el único unknown gordo.
2. **Polaridad del edge de gpio54**: evidence = "Edge" sin dirección; el vivo
   lee la línea low en reposo con pull-down. Si EDGE_FALLING no reporta,
   cambiar a EDGE_RISING (1 línea en F1). El driver usa `IRQF_NO_AUTOEN` y el
   trigger del DT, así que es solo DT.
3. **fw de flash**: v1 asume flash válida. Android la refrasheó en #526/#527,
   así que debería estar; si el chip llega mudo incluso con panel vivo, será
   el caso de portar el updater + `novatek_nt36532_o82_fw_csot.bin` (F4 de
   fw, fase 2).
4. **.config desfasado** (F2): si se olvida, el driver ni compila y el DT
   nuevo no tendrá driver detrás.
5. `goodix-berlin@0` comparte el SPI (CS0 también, nodo residual del vendor);
   con `CONFIG_TOUCHSCREEN_GOODIX_BERLIN_SPI=m` ya presente, si algún día ese
   nodo se poblara habría dos drivers reclamando CS0 — mantener el nodo
   goodix FUERA de nuestro DT.
6. El informe de captura (`CAPTURA-FULL-20261005.md`) es la fuente canónica;
   los ficheros `05-touch/dt-nodes-all.txt` y `novatek-paths.txt` de la
   captura están vacíos (fallos de captura menores, sustituidos por
   `14-dt/dt-live.tar.gz`).

## 8. Veredicto resumido

- **Driver**: port propio `novatek-nt36xxx-spi.c` ya en el árbol (transporte
  verificado vs .ko vendor); upstream descartado (protocolo SPI/page-select
  distinto); vendor cerrado descartado (depende de xiaomi_touch+HAL). Faltan
  triaje de layout, pen y (condicional) updater de fw.
- **DT diff**: añadir `&spi4 { status ok }` + `touchscreen@0` con
  `novatek,NVT-ts-spi`, freq 19.2 MHz, INT `<&tlmm 54 EDGE_FALLING>`,
  size 2136x3200. Cero pinctrl nuevo (qup_spi4_* ya casa gpio16-19).
- **fw**: para v1 nada; si hace falta, `novatek_nt36532_o82_fw_csot.bin`
  (0x3c000 B, formato cascade) desde `/odm/firmware/` a `/lib/firmware/`.
