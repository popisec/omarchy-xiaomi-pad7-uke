# RE nocturno 17-oct-2026 — hallazgos consolidados (todo lo no-panel)

> Documento de síntesis pedido por el dueño para leer al despertar.
> Cubre la noche de RE del 17-oct-2026 (~01:00–11:00 UTC).
> Alcance: **todo menos panel/L75**, que es de la otra sesión.
> Método: **solo lectura** del repo + `adb` root contra la tablet en Android;
> Ghidra 12.1.4 serializado con `flock`; verificación independiente W2,
> reparación/re-dry-run W3/W4, y spot-check propio con REA.
> **Nada se escribió en la tablet; cero builds, cero flash, cero commits.**
> Marcadores usados en todo el documento:
> **HECHO** = medido con evidencia · **INFERIDO** = deducción marcada como tal ·
> **NO VERIFICADO** = pendiente de medir.
> Cada afirmación numérica o técnica cita una fuente rastreable
> (`ruta`, `ruta §n`, `función@0x…`, o comando+salida).
> Si un dato no está en las fuentes, no aparece aquí.
> Fecha de redacción: 2026-10-17.

Índice de la noche (fuente primaria de este consolidado):
`build/gates/revision/RE-NOCTURNO-20261017/README.md`
(12 informes + auditorías + 2 fixes + verificación).

---

## 1. Resumen ejecutivo

| Área | Hallazgo principal | Estado | Informe dueño |
|---|---|---|---|
| Táctil NT36532 | IRQ `0x2001` = ONESHOT+RISING (triple evidencia); SPI CS0 19,2 MHz MODE_0; superres ×10 → DT 21360/32000 | HECHO | `build/gates/revision/RE-NOCTURNO-20261017/RE-TOUCH-NT36532.md` |
| Lápiz M80p/P81c + FW CSOT | Ejes completos (P81c: twist `ABS_BRAKE` + presión 14 b + tecla `0x120`); FW 245760 B, magic NVT, tags suma `0xFF` | HECHO | `build/gates/revision/RE-NOCTURNO-20261017/RE-STYLUS-FW-CSOT.md` |
| Pipeline MT / frame THP | Frame real **5748 B** (no 5176); **sin puntos en el frame** (3 imágenes raw); los dedos los computa el HAL; `thp-decode.py` 9/9 | HECHO (w3=5724 predicho: INFERIDO fuerte) | `build/gates/revision/RE-NOCTURNO-20261017/RE-TOUCH-MT-LAYOUT.md`, `build/gates/revision/RE-NOCTURNO-20261017/RE-TOUCH-THP-BODY.md` |
| BT WCN6750 | `btpower.ko` (9 supplies, GPIO 156, secuencia ON); fw `msbtfw12` ELF32; NVM TLV stride 12 (63 tags, encadena); fragmento DT v2 compila con `dtc` | HECHO (`vddasd` 0,95 V: NO VERIFICADO eléctricamente) | `build/gates/revision/RE-NOCTURNO-20261017/RE-BT-WCN6750.md` |
| Audio WCD939x/FS19xx | Blob `.fsm` 4828 B (CRC-16/MODBUS OK) → tablas C `fs19xx-presets.h` 651/651; spec init→enable→vol→mute; DAI `fs16xx-aif`; machine `cliffs-mtp-snd-card`; **no hay `.tplg`** | HECHO (DEVID real: NO VERIFICADO) | `build/gates/revision/RE-NOCTURNO-20261017/RE-AUDIO-WCD939X-FS19XX.md` + `RE-AUDIO-WCD939X-FS19XX-ADD1-DECOMP.md` + `RE-AUDIO-WCD939X-FS19XX-ADD2-FSM-DRIVER.md`, `build/gates/revision/RE-NOCTURNO-20261017/AUDIT-ADD2-20261017.md` |
| WiFi | BDF **o82gl** (offset 1024, 58180 B); regdb qca6750-xiaomi; **payload v2** construido (`2b0dd75a…`, sin `amss.bin`) | HECHO | `build/gates/revision/RE-NOCTURNO-20261017/RE-WIFI-BDF.md` |
| Folio / hall / sensores | Teclado = MCU **Nanosic 803** (I2C 0x4c, 4 HID extraídos); hall por `smp2p-adsp` (gpio 99/100); sensores **solo SSC-ADSP** | HECHO (polaridad hall, protocolo Nanosic a nivel byte: NO VERIFICADO) | `build/gates/revision/RE-NOCTURNO-20261017/RE-FOLIO-SENSORES.md` |
| Omarchy offline | Killer único = snapper `1781984677`; ~25 EJECUTAR / ~80 NOOP; 3 wrappers borrador; checklist primer update | HECHO (sin contraste upstream quattro: pendiente) | `build/gates/revision/RE-NOCTURNO-20261017/ATAQUE-OMARCHY-OFFLINE.md` |
| Carga / slots (operativo) | Android slot b vivo, 4082 mV, BCB limpio; `boot_a`=L74; GAP-1 cerrado; Resultado #653 añadido al ledger | HECHO | `docs/historia/ESTADO-VIVO.md` (capa 17-oct), `NOTAS-OMARCHY.md` (entrada 17-oct) |

---

## 2. Estado del aparato esa noche

- Tablet en **Android HyperOS** (slot **b**), con **adb inalámbrico + root Magisk**
  (`192.0.2.13:5555`).
- Batería **4082 mV, cargando por AC** (medido 17-oct 01:2x).
- `boot_a` = **L74 `06a1d9fe…`** (+ dtbo s288) según el Resultado #652;
  **L75 (PHY) lo prepara la otra sesión**.
- El pre-registro #653 cita L73 por error de arrastre — leer #653 siempre con #652
  (nota de lectura en el propio Resultado #653).
- `misc` BCB **limpio** (primeros 32 B a ceros, leído por adb).
- Mapa vivo by-name: `boot_a→sde11`, `boot_b→sde39`, `dtbo_a→sde15`,
  `dtbo_b→sde43`, `userdata→sda32`.
- **NADA se escribió en la tablet** en toda la noche (adb solo lectura;
  sin `/dev/ttyACM0`; sin builds ni flash).
- Refs:
  - `docs/historia/ESTADO-VIVO.md` (capa 17-oct ~05:0x).
  - `NOTAS-OMARCHY.md` (entrada 2026-10-17 madrugada).
  - `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`
    (filas #651 resultado L73, #652 resultado L74, #653 + Resultado #653 Android slot b).

---

## 3. Hallazgos por área

### 3.1 Táctil NT36532

Fuente: `build/gates/revision/RE-NOCTURNO-20261017/RE-TOUCH-NT36532.md`.

HECHO:

- Vendor: `build/android/vendor-modules-20261017/nt36532_touch.ko`
  (**1.063.304 B**, con símbolos: `llvm-objdump -t`).
- Compañero: `xiaomi_touch.ko` (308.600 B).
- Decomp previo reusado: `build/vendor-re/decomp-touch/` (~180 funciones en C).
- DT vendor vivo: `build/android/dt-full-uke-android/base/soc/qcom,qupv3_0_geni_se@ac0000/spi@a90000/novatek@0/`.
- Cosecha: `build/android/cosecha-20261017/01-dmesg.txt` (boot Android del día).
- Driver propio: `build/kernel-pokes/k52-L16-tree/drivers/input/touchscreen/novatek-nt36xxx-spi.c`
  (657 lín) + upstream `novatek-nvt-ts.c`
  (`RE-TOUCH-NT36532.md §0`).
- Compatible: `novatek,NVT-ts-spi`
  (`artifacts/touch/driver/dt-novatek-node.txt:2`;
  dmesg "SPI driver NVT-ts has no spi_device_id").
  (`RE-TOUCH-NT36532.md §1`).
- `nvt_parse_dt`@0x7838; `nvt_pinctrl_init`@0x7fd0; `nvt_gpio_config`@0x8278;
  `nvt_ts_probe`@0x554c (ver `symtab-touch.txt`). (`§1`).
- `novatek,irq-gpio` = TLMM pin **54**, flags **`0x2001`**
  (raw `00 00 01 6b 00 00 00 36 00 00 20 01`; dmesg `novatek,irq-gpio=387`
  = nº GPIO Linux; IRQ **359** vía `gpio_to_irq`). (`§1`).
- **0x2001 = IRQF_ONESHOT (0x2000) + EDGE_RISING (1), triple evidencia**:
  (a) probe hace `request_threaded_irq(..., *flags | 0x2000, ...)`
  (`nvt_ts_probe.c:491-492`, `nvt_touch_doze_analysis.c:117-118`);
  (b) dmesg vivo `nvt_ts_probe 5351: int_trigger_type=1`
  (1 = `IRQ_TYPE_EDGE_RISING`);
  (c) `/proc/interrupts` vivo: `359: ... msmgpio 54 Edge xiaomi_tp`
  con contadores >0 (IRQ viva, flanco).
  La alternativa FALLING del parche 0001 puede retirarse. (`§1`).
- SPI: `reg=<0>` (CS0); `spi-max-frequency` raw `01 24 f8 00` = **19.200.000 Hz**;
  sin props `spi-cpol/cpha` ⇒ **SPI_MODE_0, 8 bits**
  (INFERIDO, estándar del core SPI). (`§1`).
- **Sin reset-gpio ni supplies** en el nodo vendor (TDDI: el FW del touch vive
  con el panel; reset por comando: `nvt_eng_reset`@0x3164,
  `nvt_bootloader_reset`@0x320c, `nvt_sw_reset`@0x319c,
  `nvt_sw_reset_idle`@0x31d4). (`§1`).
- `novatek,pen-support` + `novatek,stylus-resol-double` +
  `novatek,mp-support-dt` (booleanos); `novatek,spi-rd-fast-addr` **ausente**;
  `novatek,lcd_id-gpio` = pin 26, valor **lcd_id=1 ⇒ panel CSOT** (dmesg
  `nvt_parse_dt 2394`). (`§1`).
- FW aplicable: `novatek_nt36532_o82_fw_csot.bin` (+`_mp_csot.bin`), 245.760 B
  en `/odm/firmware`; existe variante `_tm` (no es este panel). (`§1`).
- pinctrl: estados `pmx_ts_active`/`pmx_ts_suspend`; sin pinctrl el driver sigue
  (solo log) — el parche 0001 no añade pinctrl: correcto. (`§1`).
- Chip-id: trim `0x1fb104 / 0x1fb43e / 0x1fb535`; lectura
  `buf=0x0E 00 04 32 65 03`, "This is NVT touch IC", **"Cascade Chip"**
  (dmesg 3352-3424). (`§1`).
- `NT36532_single_memory_map`@.rodata 0x9e00, primer u32 LE `00 58 12 00` =
  **EVENT_BUF 0x125800** (coincide con `novatek-nt36xxx-spi.c:60`). (`§1`).
- FW: `fw_ver 0x0E, fw_type 0x01, pid 0x5981`;
  driver `nvt_version_2024.01.13-001`; xiaomi-touch `2024.09.02-01`;
  lockdown `53 42 32 91 4f 81 32 ff`; geometría **rx=40, tx=60, x=2136,
  y=3200, super_resolution_factor=10** (dmesg 5530-5537). (`§1`).
- Probe (`nvt_ts_probe.c`, dmesg 5018-5596): prio SPI 99 → `nvt_parse_dt`
  (gpio 387, pen=1, dbl=1, lcd gpio 359, lcd_id=1 CSOT,
  game-config1 `[2,2,1,2,1]` / config2 `[2,2,2,2,1]` / config3 `[2,2,3,2,1]`)
  → pinctrl active → `nvt_eng_reset()`@0x3164 →
  `nvt_ts_check_chip_ver_trim_loop()`@0x8370 (5 intentos × 3 addrs;
  deja `EVENT_BUF=0x125800`, `max fingers=10`). (`§2`).
- Crea 3 input devices: `NVTCapacitiveTouchScreen` + `NVTCapacitivePenM80p` +
  `NVTCapacitivePenP81c` (dmesg + `dumpsys input`: event11/12/13). (`§2`).
- `gpio_to_irq(387)=359` → `request_threaded_irq(flags|0x2000)`; IRQ empieza
  **disabled** (`enable=0 depth=1`), se habilita al final. (`§2`).
- `/proc/NVTSPI` → ~25 nodos extra → `/proc/nvt_selftest` → lockdown + fw
  version → **`nvt_init_touchmode_data()`@0xc9ec** (42 modos 0-41, §6) →
  `register_touch_panel` (xiaomi_touch, `panel_register_mask=1`) → misc
  `tpdbg` + `pen_hopping_frequency` → `bTouchIsAwake=1` → IRQ enable →
  `edge_filter_params` → workqueue `nvt_fwu_wq` con `Boot_Update_Firmware`
  diferido. (`§2`).
- Worker: `nvt_ts_work_func_irq_handler`@0x8908 (top-half mínimo) /
  `nvt_ts_work_func`@0x8914. (`§3`).
- Doze/gesto: lee **0x101 = 257 B**; normal: `*(u16*)(ts+0x424) + 0x101` con
  `*(ts+0x424)=0x1efe` ⇒ **0x1FFF = 8191 B**
  (buffer `ts[0x85]` de 0x2000 B). (`nvt_ts_work_func.c:60,136`, `§3`).
- Idle/gesto: `data[1..6]+3 < 2` (bytes 0xFD/0xFE); checksum aditivo
  `sum(data[1..0x40]) + data[0x41]==0`; tras >10 frames idle/gesto en doze:
  recovery (sw_reset_idle + fw history + update + reload). (`§3`).
- Camino normal (no-doze): valida header DMA en `buf+0x105`
  (`{id u16, magic 0x509/0x4BF, ~id, ~magic}`) y entrega el frame crudo a
  xiaomi_touch (`notify_raw_data_update`, 5176 B);
  **el MT lo reporta xiaomi_touch, no este .ko**
  (`nvt_ts_work_func.c:169-196`). (`§3`).
- Handshake TX-auto-copy/DMA (`nvt_check_spi_dma_tx_info`@0x2c54,
  `nvt_tx_auto_copy_mode`@0x2b48, `nvt_check_tx_auto_copy`@0x2e58,
  `nvt_wait_auto_copy`@0x305c; poll ≤200×1 ms de flag a 0):
  sin este handshake, si el chip sale de reset en auto-copy las lecturas
  devuelven basura con checksum malo persistente — el rescue del módulo lo
  cubre, el nuestro no. (`§3`, `§6.4`).
- `CTP_SPI_READ`@0x4e8: full-duplex, `cmd & 0x7F`, rx separado,
  `memcpy(buf+1, rbuf+2, len-1)`, 5 reintentos — coincide con
  `novatek-nt36xxx-spi.c:165-203`. (`§3`).
- `CTP_SPI_WRITE`@0x754; `nvt_set_page`@0x9a0 (`[0xFF][A>>15][A>>7]`). (`§3`).
- Suspend (`nvt_ts_suspend`@0xe438): `gesture_switch==0` ⇒ `nvt_irq_enable(0)`
  (IRQ muda total); ≠0 ⇒ doze (`nvt_enable_gesture_mode(1)`);
  handshake `0x7c50/0xff50` con reintentos. (`§4`).
- Notifiers del .ko táctil: **power_supply** (`nvt_power_supply_work`@0x9410,
  dmesg "Power supply state:0/1") y **pen-charge**
  (`nvt_pen_charge_state_notifier_callback`@0x9460, "pen_charge_connect is 0").
  **NO** usa FB_BLANK ni DRM directo: del display solo le llega estado vía
  xiaomi_touch; depends: `xiaomi_touch,qti_battery_charger,msm_drm,metis`. (`§4`).
- xiaomi_touch.ko: dueño de MT/gestos/modos/notifiers;
  `xiaomi_register_panel_notifier` / `xiaomi_unregister_panel_notifier`
  (EXPORTADOS) sobre `panel_event_notifier`. (`§5`).
- Sysfs: `panel_color/panel_display/panel_vendor`, `pen_connect_strategy`,
  `palm_sensor`, `Touch_Game_Mode/Report_Rate/Resist_RF/Tolerance/
  Panel_Orientation/Edge_Filter/Suspend`, `Touch_Stylus_Gamemode_Enable`;
  proc: `tp_fw_version`, `tp_lockdown_info`, `tp_selftest`, `tp_data_dump`,
  `last_touch_events`. (`§5`).
- Gestos: `xiaomi_get_gesture_type` (EXPORTADO); mmap double-buffer 80 KB frame
  + 160 KB raw para el HAL (`xiaomi_touch_dev_mmap`, dmesg 8.70). (`§5`).
- Modos **1000/1004/3001-3045**: `nvt_set_cur_value`@0xaf30 trata `mode==1000`
  como conmutador de `op_mode`; al arrancar el HAL fija `mode 1004 ← 1`;
  `nvt_htc_ic_{get,set}ModeValue` aceptan rango HTC **0xBB9-0xBE5 = 3001-3045**.
  **"1071" no aparece** en strings de ninguno de los dos .ko ni en dmesg
  (NO VERIFICADO — probable ID del HAL TouchFeature, no del kernel). (`§5`).
- Contraste mainline §6: **(1)** rango vivo `getevent event11` X **21359** /
  Y **31999** (10 slots, TOUCH_MAJOR 255, PRESSURE 0/1) — el DT del 0001 H3
  (2136×3200) recortaría 10:1; **(2)** RISING confirmado;
  **(3)** layout de dedo NO VERIFICADO (upstream `novatek-nvt-ts.c`, I2C
  NT11205, usa records de **6 B** → apoya candidato A; INFERIDO);
  **(4)** sin handshake TX-auto-copy (riesgo medio);
  **(5)** sin pen (0001 no declara `novatek,pen-support`);
  **(6)** sin gestos-doze/FW-updater (correcto para bring-up);
  **(7)** transporte idéntico al vendor, sin cambios.
- Verificación viva 17-oct ~01:36 UTC (`live-verify.txt`): `dumpsys input`
  event11/12/13; `getevent -il event11` 10 slots X 0-21359 Y 0-31999;
  `/proc/interrupts` 359 con miles de eventos; `/proc` con 24 `xm_htc_*`;
  `tp_fw_version`: `fw_ver:0x0E fw_type:0x01 pid:0x5981`,
  hal `2025.11.28-0001`; `/odm/firmware` con fw/mp csot+tm +
  `o82_nova_{thp,tm_thp}_config.ini`; `touchfeature-service` +
  `toucheventcheck` corriendo; `persist.stylus.palm.reject=1`. (`§7`).

Artefactos: `build/gates/revision/RE-NOCTURNO-20261017/artifacts/touch/driver/`
(`dmesg-touch-excerpt.txt`, `symtab-touch.txt`, `dt-novatek-node.txt`,
`live-verify.txt`, `delta-0002-touch-superres-pen.patch` — NO aplicable tal cual,
ver §6).

Pendiente: plegar el DELTA en 0001/fase4-touch (resuelto en W3 como parche `11`,
ver §6); evtest 1 dedo + esquinas (`point_layout`, escala ×10); fase 2: updater
+ doze + poll TX-auto-copy; aclarar "1071" contra el HAL. (`§8`).

### 3.2 Lápiz M80p/P81c + FW CSOT

Fuente: `build/gates/revision/RE-NOCTURNO-20261017/RE-STYLUS-FW-CSOT.md`.

HECHO:

- Tres inputs (dmesg cosecha + vivo): input11/event11 touch (`input/ts`),
  input12/event12 M80p (`input/pen`), input13/event13 P81c (`input/pen_p81c`).
  (`§1.1`).
- dmesg probe 5155: `abs_x_max=2136, abs_y_max=3200`;
  `fw_ver:0x0E fw_type:0x01 nvt_pid:0x5981`;
  driver `nvt_version_2024.01.13-001`; `super_resolution_factor=10`;
  rx=40 tx=60; lockdown `53 42 32 91 4F 81 32 FF`. (`§1.1`).
- Vivo: `stylus_enable=0, stylus_only=0, pen_scan_rate=0`
  (sin lápiz conectado). (`§1.1`).
- Fórmulas vendor: `Xmax = *(u16)(ts+0xBE)*10-1`,
  `Ymax = *(u16)(ts+0x18)*10-1` → 2136*10-1 = **21359**,
  3200*10-1 = **31999** (factor ×10 = `stylus-resol-double`). (`§1.2`).
- M80p (`ts+0x3b8`, probe .text 0x62f8–0x64dc): `ABS_X 0..21359`,
  `ABS_Y 0..31999`, `ABS_PRESSURE 0..8191` (0x1fff, 13 bits),
  `ABS_DISTANCE 0..1` (hover), `ABS_TILT_X/Y -60..+60`,
  `KEY_WAKEUP=143/0x8f`, `BTN_TOOL_PEN (0x140)` + `BTN_TOUCH (0x14a)`,
  `id.bustype = 0x1c (BUS_SPI)`, `+0xd0 = 0x80`. (`§1.2`,
  decomp `decomp-full/nvt_ts_probe.c` + `getevent -p` vivo, coinciden).
- P81c (`ts+0x3c0`, probe .text 0x64e4–0x69cc): todo lo del M80p MÁS
  `ABS_BRAKE (0x0a, NO ABS_RZ) 0..360` (twist),
  `ABS_PRESSURE 0..16383` (0x3fff, 14 bits),
  tecla extra `0x120` (`keybit |= 0x100000000`, ko 0x6874).
  Android: `KEYBOARD|TOUCH|JOYSTICK` (M80p: `KEYBOARD|TOUCH`). (`§1.2`).
- Corrección a la hipótesis inicial «twist = ABS_RZ»: `ABS_RZ = 0x05`;
  el eje 0x0a es `ABS_BRAKE` (`input-event-codes.h`), confirmado por dumpsys
  (`AbsState: ABS_BRAKE=0`, Motion Range `BRAKE: JOYSTICK`). (`§1.2`).
- Dedo vs lápiz: separación total — dedo por nodo MT (10 slots,
  `ABS_MT_TOUCH_MAJOR 0..255`, `ABS_MT_POSITION_X/Y 0..21359/31999` también
  ×10, `ABS_MT_TRACKING_ID`, `ABS_MT_PRESSURE 0..1`); lápiz por sus dos nodos
  dedicados sin slots. (`§1.3`).
- Reporte normal (finger+pen) NO está en este .ko: `nvt_ts_work_func` copia
  0x1438 = 5176 B al frame DMA y llama a `notify_raw_data_update(0)`
  (export de `xiaomi_touch.ko`); es xiaomi_touch quien parsea y reporta. (`§1.3`).
- Path de gestos (`decomp-full/nvt_ts_work_func.c`, ko 0x8914), dos caminos
  (flag `ts+0x26c`): **A** (lectura 0x101 B de EVENT_BUF 0x125800):
  `data[1..6]` = `0xFD/0xFE` → idle; si no, checksum
  `sum(data[1..0x40]) + data[0x41] == 0` → válido:
  `nvt_ts_wakeup_gesture_report(data[1]>>3, ...)` y, si pen-support,
  `nvt_ts_pen_gesture_report(data[0x42])`; **B** (lectura
  `*(u16)(ts+0x424)+0x101`): valida cabecera
  `{id @+0x105, magic 0x509/0x4BF @+0x109, ~id @+0x10d, ~magic @+0x111}`
  o byte `@+0x101 == 0xFF`; `memcpy` 0x1438 B + `notify_raw_data_update`.
  Recuperación: 10 frames idle → `nvt_update_firmware("novatek_ts_fw.bin")`.
  (`§1.4`).
- `nvt_ts_pen_gesture_report` (ko 0x48b8): `data[0x42] == 0x19`
  (single click) → `report_single_click_pen_input` (ko 0x472c) sobre
  `ts+0x3c0` si `ts+0x3c8 == 2` (P81c), o `ts+0x3b8` si `== 1` (M80p).
  Secuencia exacta del click: `X=Y=PRESSURE=TILT_X/Y=1, BTN_TOUCH=1,
  TOOL_PEN(0x140)=1, SYN; suelta con DISTANCE=1, BTN_TOUCH=TOOL_PEN=0, SYN`.
  `report_release_pen_event` (ko 0x5460): todo a 0 + SYN. (`§1.4`).
- `nvt_set_pen_inband_mode_1(u16, u8)` (ko 0x11e00): write 5 B a página 0x50,
  poll ACK `0xFF50 == 0` (5 reintentos × 10 ms);
  `nvt_set_pen_normal_mode` (ko 0x12034): write 3 B + mismo poll.
  (INFERIDO: inband = el IC genera la portadora del pen; normal = pasivo.)
  (`§1.5`).
- `nvt_set_pen_switch(id)` (ko 0x12d70): write `[0x50, 0x7b, id]`
  (reg 0x7B50), 10 reintentos × 10–11 ms, guarda en `ts+0x188c`;
  llamado desde `update_pen_status` (ko 0x5030). (`§1.5`).
- Hopping: `nvt_set_pen_hopping_ack` (ko 0xe6f4: toggle `0x7C50` + poll
  `0xFF50`, 5 rondas); `nvt_pen_hopping_frequency` (ko 0xebf4) y
  `nvt_pen_AG_update` (ko 0xedec) emiten uevent **`MIPP_PEN_STATE=%d`**;
  `pen_hopping_write` (proc, ko 0xf610) parsea 2 dígitos ASCII;
  `nvt_switch_FreqHopEnDis` toca página 0x50 + `0x23`. (`§1.5`).
- Scan rate: `nvt_xm_htc_get_pen_scan_rate = nvt_get_extend_custom_cmd(0xb)`
  (ko 0x16254). (`§1.5`).
- DT: `compatible = novatek,NVT-ts-spi`; `novatek,pen-support`,
  `novatek,stylus-resol-double`, `novatek,mp-support-dt` (bools);
  `spi-max-frequency = 0x0124f800` (19,2 MHz); game-params 1/2/3;
  arrays `mi_tp,*`; pinctrl `pmx_ts_active/suspend`
  (dump en `ev-dt-novatek-node.txt`). (`§1.6`).
- FW CSOT: tamaño 245760 B = 0x3C000 = 60 bloques de 4 KB; magic **`NVT`
  en EOF-3**; tag de 2 B a `@0x3B000` (y copia a `@0x352D0`):
  `fw = 11 EE`, `mp = 91 6E`; **suma = 0xFF en ambos**
  (pre-chequeo del driver; log vivo `fw_need_write_size = 245760`). (`§3`).
- Nombres (`nvt_update_firmware.c:56-75`): `novatek_ts_fw.bin` →
  `novatek_nt36532_o82_fw_{csot|tm}.bin` según `ts+0x5d` (lcd_id; CSOT=1);
  path de recuperación → **en esta tablet resuelve a `fw_csot`**. (`§3`).
- Carga viva (dmesg l.10692-10717, t≈17,9 s, fuera del probe):
  `update_firmware_request: ..._fw_csot.bin` → falla `firmware_class.path`
  (avc denied) → sysfs fallback → ueventd sirve
  `/odm/firmware/novatek_nt36532_o82_fw_csot.bin` en 2 ms →
  `bin_header_parser: cascade_2nd_header_info=1, ovly_info=0, ilm_dlm_num=2,
  ovly_sec_num=0, info_sec_num=14, partition=16` → `bootloader_reset` →
  `tx auto copy mode 2` → **`Update firmware success! <128397 us>`**.
  `frame_len = 5176`. (`§3`).
- `fw` vs `mp` (diff por páginas 4K): 28/60 páginas difieren — código
  `0x0000-0x17FFF` + 1 B en `0x2B3DC` (`0x11` vs `0x91`, INFERIDO flag
  normal/MP) + 3 B en `0x35000` (tag) + 102 B en `0x36000` (INFERIDO tabla
  de criterios MP) + 3 B en `0x3B000` (tag).
  Conclusión: **mp = variante de fábrica/selftest**, fw = runtime. (`§3`).
- Versión corriendo: `fw_ver 0x0E, fw_type 0x01, pid 0x5981`.
  (NO VERIFICADO: offset exacto de estos campos dentro del .bin; el driver
  lee SRAM del IC. CRC de fichero: suma16/CRC16/CCITT no coinciden con el
  tag → NO es checksum global; la integridad la verifica el IC por HW CRC:
  `nvt_set_bld_crc_bank/read_bld_hw_crc/fw_crc_enable`.) (`§3`).
- Tabla M80p vs P81c (`§4`): input12/event12 `input/pen` vs
  input13/event13 `input/pen_p81c`; presión 0..8191 (13 b) vs 0..16383 (14 b);
  twist solo P81c (`ABS_BRAKE 0..360`); tecla extra `0x120` solo P81c;
  común: X/Y ×10, DISTANCE hover, TILT ±60, KEY_WAKEUP, TOOL_PEN+TOUCH;
  `ts+0x3b8` sel==1 vs `ts+0x3c0` sel==2.
- (NO VERIFICADO: qué función emite los logs `Xiaomi stylus m80p/p81c` —
  strings en .rodata @0x1234/0x126c sin xref en el export 233/233 ni relocs;
  solo aparecerían con lápiz conectado.) (`§4`).
- Parche borrador (NO COMPILADO, NO PROBADO):
  `artifacts/touch/stylus-fw/novatek-nt36xxx-spi-pen-draft.patch`
  (ambos nodos pen, secuencia click/suelta exacta, hook gesto `0x19`;
  LIMITACIÓN declarada: selector M80p/P81c cableado a M80p; reporte normal
  y updater de FW fuera de alcance). (`§2`).

Artefactos: `build/gates/revision/RE-NOCTURNO-20261017/artifacts/touch/stylus-fw/`
(`decomp/` 32 fns filtro «pen» + `decomp-full/` 233 fns Ghidra 12.1.4 con lock;
`ev-getevent-pens.txt`, `ev-dumpsys-input-full.txt` 1627 lín,
`ev-dt-novatek-node.txt`, `ev-fw-csot-parse.txt`, borrador pen-draft).

Pendiente: formato frame DMA 5176 B (finger+pen normal — necesita
`xiaomi_touch.ko` o captura con lápiz); offsets versión/pid en el .bin;
origen del log `Xiaomi stylus m80p/p81c`; compilar+probar el parche;
`ABS_MT_PRESSURE max 1` (raro pero HECHO en decomp y vivo). (`§Pendiente`).

### 3.3 Pipeline MT / frame THP

Fuentes: `build/gates/revision/RE-NOCTURNO-20261017/RE-TOUCH-MT-LAYOUT.md`,
`build/gates/revision/RE-NOCTURNO-20261017/RE-TOUCH-THP-BODY.md`.

HECHO (MT-LAYOUT):

- En kernel NO se decodifica ningún dedo: `nt36532_touch.ko` tiene 36 sitios
  CALL26 a `input_event`, **cero** en `nvt_ts_work_func` (@0x8914, 0x754 B):
  22 en 0x4xxx (gestos/pen), 9 en 0x5xxx, 5 en 0xcxxx
  (`readelf --relocs`, `symtab-xiaomi-mt.txt`).
  `input_mt_report_slot_state` es import UND **sin ninguna reloc que lo llame**
  (importe muerto). El worker normal solo hace
  `memcpy(thp_buf, buf+0x101, 0x1438)` + notifier
  (`nvt_ts_work_func.c:169-196` del decomp previo). (`MT §1`).
- `xiaomi_touch.ko`: `notify_raw_data_update`@0x9a8 **no recibe puntero a datos**
  (solo `panel_id`): incrementa un contador y despierta al HAL
  (`decomp/notify_raw_data_update.c:18-33`).
  El MT lo reporta `report_touch_event`@0xaa74 con records **ya cocinados de
  28 B** que le entrega el HAL por `xiaomi_touch_dev_write` (CALL26 en 0x50a8;
  el write exige `len % 28 == 0`)
  (`decomp/report_touch_event.c`, `decomp/xiaomi_touch_dev_write.c:83-85`).
  (`MT §1`).
- `xiaomitouch_input_event`@0xa37c es un filtro `input_handler`
  (snoop + timeline), no un parser
  (`.data xiaomitouch_input_handler` + relocs ABS64). (`MT §1`).
- Frame THP de 5176 B (0x1438) en `EVENT_BUF + 0x100`;
  lectura vendor `*(u16*)(ts+0x424) + 0x101` con `0x1efe` ⇒ 0x1FFF B. (`MT §2`).
- Cabecera `F[0..0x17]`: F+4 (u16) id; F+8 (u32) magic ∈ {0x509, 0x4BF};
  F+12 (u16) ~id; F+16 (u32) ~magic; F+0..3 y F+20..23 desconocidos
  (NO VERIFICADO). Aceptación: magic+complementos OK **o** `F[0]==0xFF`
  (frame vacío) (`nvt_ts_work_func.c:169-173`,
  `hal-decomp/..._001d920c...c:87`). (`MT §2`).
- Framing del cuerpo: `thp_crc_check` @ libtouchreport `.text 0xd920c`
  (724 B, FDE 0xd920c–0xd94e0); cuerpo en `F+0x18`, longitud
  `w3 = u16LE @F+0x1b` (≥ 4); total `0x18+w3`. (`MT §3`).
- Modelo de puntos del HAL: 12 slots (bucles tope 12, stride 7848 B/176 B;
  disasm 0x94604-0x946b0, 0xd1f80-0xd2004, `alg_input_report`); ids de dedo
  pequeños (`uVar20 < 10`); `raw_finger_bits` = máscara de 12 bits
  (popcount bits 0–11 en `FUN_00195710:273-276`);
  `Touch Down/Up: id: N` con N ∈ {0,1} en `touch_report.log` vivo. (`MT §4`).
- Escala: `newX = rawX*k + c` (`madd`, super_resolution=10 normal, 8/16 en
  juego; ini `display 2136x3200`, `frame_data_type=3`) ⇒ rango 21360x32000;
  coincide con `getevent event11` y `register_touch_panel:469`
  (`x=2136 y=3200 rx=40 tx=60 sr=10 frame 2x10 raw 8x5`) — triple HECHO. (`MT §4`).
- Records cocinados HAL→kernel (28 B, u32 LE): `buf[0]` = panel id; por record
  `{slot @+4, pressed @+8, X @+12, Y @+16, +12 B sin uso}`; `count=0` libera
  los 10 slots; **solo X/Y, sin presión/área**
  (`report_touch_event.c:47-68`). (`MT §4`).
- `report_coordinate` (FW extend-cmd 0x15) en vivo = **0**
  (`/proc/xm_htc_report_coordinate`); único conmutador de formato del FW. (`MT §4`).
- Mmap vivo: `/dev/xiaomi-touch` 0x28000 (160 KB) rw-s + 0x14000 (80 KB) r--s
  en `/proc/1808/maps` (= 8·5·4K y 2·10·4K del dmesg). (`MT §4`).
- El `fingers = head >> 3` del driver propio queda **sin apoyo**: `>>3` solo
  aparece en el path de gestos (`wakeup_gesture_report(buf[1]>>3)`); no usarlo
  para contar dedos en frames normales. (`MT §5.3`).
- Direcciones (MT §8): xiaomi_touch `report_touch_event` 0xaa74/0x240,
  `notify_raw_data_update` 0x9a8/0xfc, `dev_write` 0x4ec8 (call en 0x50a8),
  `register_xiaomi_input_dev` 0xa774, `xiaomitouch_input_event` 0xa37c;
  HAL `thp_crc_check` 0xd920c/724, `process/match_finger` 0x95710/7060,
  `alg_input_report` 0x98f60, `hal_frame_fetch` 0x1b7428,
  `vendor_get_frame_data` 0x1b5f5c.
- Vías intentadas sin éxito (no repetir): `libnova.so` (es cámara),
  `/proc/PID/mem` en mmap PFNMAP (I/O error), `dev_read` (records comunes
  520 B), nodos `nvt_*` (mutual, no dedos). (`MT §8`).

HECHO (THP-BODY — corrige a MT-LAYOUT §3/§7):

- El frame real es **5748 B = 0x1674** (no 5176); el 0x1438 del `memcpy` kernel
  es solo el tamaño del `thp_buf` del notifier
  (`nvt_ts_work_func.c:211`) — número circular sin ningún frame capturado.
  Predicción falsable: un frame real válido trae **`w3 = 5724 = 0x165C`**.
  El SPI lee 0x1FFF B (`nvt_ts_work_func.c:172`), cabe de sobra. (`BODY §3`).
- Parser: `copy_frame_data_from_mmap` = `FUN_001d920c` (.text file `0xd920c`,
  724 B); geometría de blobs: `init` en .text file `0xb8644-0xb8690`;
  longitudes: `DAT+0xac0/0xac4/0xac8` (file `.bss 0x189ac0/4/8`). (`BODY §2`).
- Claves ini ↔ globales ↔ defaults ↔ valores vivos
  (`o82_nova_thp_config.ini` pull RO): `hal_node_num` (@0x4cc36) +0xac0,
  default 2400, vivo 2400; `hal_snode_num` (@0x4301e) +0xac4, 100/100;
  `hal_nnode_num` (@0x482c7) +0xac8, 240/240;
  `hal_row_num` (@0x47742) → 60 default(!) / **40** vivo;
  `hal_col_num` (@0x4ad30) → 40 default(!) / **60** vivo
  (defaults de fila/columna cruzados en el vendor, inofensivo porque el ini
  trae ambas; producto `row*col=2400=node` verificado en `0xd89e0 umull`).
  (`BODY §2`).
- Layout del cuerpo (F = inicio del frame; cabecera F[0..0x17] sin cambios):
  F+0x00 202 B cabecera fija; **F+0xCA 4800 B blobA `u16[2400]` mutual
  40×60**; F+0x138A 16 B 2×u64 fijos; **F+0x139A 200 B blobB `u16[100]`
  self (40+60)**; F+0x1462 38 B struct fija; **F+0x1488 480 B blobC
  `u16[240]` noise**; F+0x1668 12 B cola (u64+u32);
  **total 5748 B = `0xCA + 2·(2400+100+240) + 16 + 38 + 12`**.
  Evidencia: `hits_..._001d920c.c:113-137`, disasm `0xd88fc-0xd8918`,
  `0xd8934-0xd893c` (`lsl` ×2), inits `calloc(1,328)+calloc(blob)`. (`BODY §2`).
- **En el frame no hay puntos**: el pipeline
  (`caller_0017cb58`: `FUN_0019a220 → 0019acac → 0019b0a4 → … → 0019c178 →
  00195710 match/process_finger → 001949dc → 00198f60 alg_input_report`)
  mueve **imágenes** (`memcpy Glas row*col`), no listas de puntos; genera
  candidatos de 300 B y los asocia por distancia húngara
  (matrices `DAT_00256d60/00257ed0`, `link:%d`). (`BODY §4`).
- `point_cnt` / `raw_finger_bits` del log son **computados** (conteo de bucle
  y popcount en `00195710:273-276`), no campos del frame; sin checksum por
  punto (solo head + body). (`BODY §4`).
- El ×10 (`super_resolution`, default 10 en `00198f60:105`) se aplica en
  `alg_input_report` al escalar coordenadas computadas (`madd`);
  el frame lleva u16 raw de sensor; ids 0..11 los asigna el tracker;
  `pressed` es estado del tracker; presión/área no existen ni en el frame
  ni en los records de 28 B. (`BODY §4`).
- Decodificador nuevo `artifacts/touch/mt-layout/thp-decode.py`:
  longitud dinámica (`total=0x18+w3`), blobs por geometría parametrizable
  (`--node/--snode/--nnode`), stats por blob + mapa ASCII del mutual;
  `--selftest`: **9/9 PASS** (frame sintético 5748 válido, byte corrupto ⇒
  BODY mal, head corrupto ⇒ HEAD mal, magic malo, vacío `0xFF`, geometría
  errónea, corto). (`BODY §5`).
- INFERIDO (fuerte): blobA=mutual / blobB=self / blobC=noise (tamaños 40×60,
  40+60, nombres `hal_*node*`); w3=5724 en frames reales; gap1 = contadores.
  (`BODY §7`).
- NO VERIFICADO: ningún frame real capturado (day-test de MT §7, con
  `thp-decode.py` en vez de `frame-scan.py`); qué `data_type` selecciona
  `001d920c` frente a `001d9f44/001db27c`; semántica fina de gap2/cola;
  `touch_report_debug` (986.752 B, NO examinado — vía alternativa). (`BODY §7`).
- Material nuevo (MT §0): `decomp/` (114 .c, Ghidra `xiaomi_touch.ko` entero,
  proyecto `uke-night-mt`); `hal-decomp/` (28 .c + `_XREF.txt`, Ghidra
  `libtouchreport.so` stripped + script nuevo `FindFrameParser.java`);
  `o82_nova_thp_config.ini` (36.228 B, pull RO); `libtouchreport.so`
  (1.355.440 B, stripped, NDK r22b, pull RO `/odm/lib64`);
  `touch_report.log` (160.697 B, 2038 lín, pull RO);
  `symtab-xiaomi-mt.txt`; `frame-scan.py` (auto-test OK/FAIL sintético);
  `delta-mt-parser.patch` (dry-run `-p4` OK en copia /tmp);
  `DumpOne.java`, `FindFrameParser.java`.
  `libnova.so` se trajo y descartó (cámara/QNN) — no se conserva.
- Lib md5 `ececace7…9b5b` = idéntico al pull previo; vive en
  `vendor.xiaomi.hw.touchfeature-service`, pid 1808; `/proc/1808/mem`
  ilegible (I/O error aun como root) → globales resueltos por RE estática.
  (`BODY §1`).

Artefactos: `build/gates/revision/RE-NOCTURNO-20261017/artifacts/touch/mt-layout/`
(`thp-decode.py`, `frame-scan.py`, `delta-mt-parser.patch`, decomp/, hal-decomp/,
ini, lib, log, symtab, scripts java).

Pendiente: day-test táctil vivo (insmod con `thp_frame=1 dump_thp=1`, un dedo +
esquinas, doble captura consola+ssh si hay reboot; pasar volcado por
`frame-scan.py` — debe dar OK + `w3=5152` — y por `thp-decode.py`;
correlacionar `F[0xCA..]` con `evtest`); con UN frame con dedo + evtest
simultáneo se cierra N1. `point_layout`: no existe tal concepto en el vendor
kernel; el único selector es `report_coordinate` (=0 en vivo). (`MT §7`).

### 3.4 BT WCN6750

Fuente: `build/gates/revision/RE-NOCTURNO-20261017/RE-BT-WCN6750.md`.
Leyenda del informe: **[H]** HECHO / **[I]** INFERIDO / **[N]** NO VERIFICADO.

HECHO:

- `build/android/vendor-modules-20261017/btpower.ko` (141.920 B, `fdbc8e3a…`);
  Ghidra `artifacts/bt/decomp/` (47 fns); disasm `artifacts/bt/btpower-disasm.txt`;
  FW `build/android/msbtfw12.{mbn,ver}` + `msnv12.bin`;
  árbol `build/kernel-pokes/k52-L16-tree` (hci_qca.c 2841 lín, binding
  `qcom,wcn6750-bt.yaml`, `palawan.dtsi`, `xiaomi-uke.dts`, `lamma-qrd.dts`);
  `build/kernel-config/k37.config`. (`RE-BT §1` cabecera).
- Platform driver `bt_power`, compatible `qcom,wcn6750-bt` (también
  `qcom,qca6174/wcn3990/qca6390/qca6490/kiwi/peach-bt/bt-qca-converged`).
  `modinfo`: `MSM Bluetooth power control driver`,
  vermagic `6.1.68-android14-11`, depends `smcinvoke_dlkm,pinctrl-msm,rfkill`.
  Exporta `btpower_register_slimdev` + `btpower_get_chipset_version`.
  **NO toca UART/baud**: solo reguladores+GPIOs+reloj; el transporte lo abre el
  HAL QTI sobre `/dev/ttyHS0` (grupo `bluetooth`) con protocolo QCA en
  `hci_uart.ko`. Sin refs a tty/serial/baud en decompilado ni strings. (`§1`).
- Probe (`bt_power_probe`, decomp 155 lín): kmalloc `pwr_data` → flag
  `qcom,peach-bt` (ausente en uke) → workqueue/waitqueues/mutexes →
  `bt_power_populate_dt_pinfo` → `rfkill_alloc("bt_power",
  RFKILL_TYPE_BLUETOOTH)` + sysfs `extldo`,
  `rfkill_init_sw_state(blocked)` → `rfkill_register` → `btpower_aop_mbox_init`
  → `probe_finished=1`. El probe **NO enciende**: el ON llega por
  rfkill-unblock → `btpower_toggle_radio` → `power_regulators`. (`§1`).
- Parse DT: por cada nombre de la tabla match-data lee `<nombre>-supply` +
  `<nombre>-config` (16 B BE: min_uV, max_uV, load_uA, enable_flag).
  GPIOs: `qcom,bt-reset-gpio`, `qcom,wl-reset-gpio` (compartido WLAN),
  `mpm_wake_set_gpios`, `qcom,bt-sw-ctrl-gpio`, `qcom,bt-debug-gpio`
  (opcional), `qcom,xo-clk-gpio` (opcional); `clocks` ausentes en uke →
  reloj omitido. (`§1`).
- Valores dump uke (`soc/bt_wcn6750`, TLMM phandle 0x16b):
  reset=`<0x16b 156 0>`, sw-ctrl=`<0x16b 80 0>`, wl-reset=`<0x16b 35 0>`,
  `mpm_wake_set_gpios=<80>`, `pinctrl-names="default"`. (`§1`).
- Supplies → regulador (resuelto por phandle): aon/dig/rfa0p8/rfacmn→
  `pmxr2230-s3` (0x348, 968000–1040000); rfa1→`pmxr2230-s1` (0x346,
  1856000–2040000); rfa2→`pmxr2230-s2` (0x347, **1256000–1408000** —
  corrección a PERIF-BT que decía 1.25–1.35M);
  ipa-2p2→`pmr735a-s3` (0x345, 1600000–2400000);
  io→`pmxr2230-l7` (0x1e0, 1800000 fijo). Ventanas coinciden con los
  `regulator-min/max-microvolt` de los nodos destino. (`§1`).
- Secuencia ON: **1º reguladores** (en orden de tabla:
  `regulator_set_voltage(min,max)` → `regulator_set_load(load)` →
  `regulator_enable`), **2º GPIOs** (`bt_configure_gpios(1)`): request reset
  (`"bt_sys_rst_n"`) → reset=0 → **msleep(50)** →
  `msm_gpio_mpm_wake_set(80,1)` → chequeo wl-reset (si WLAN apagado: reset=0 →
  **msleep(100)** `"BTON: WLAN OFF waiting for 100ms delay"`) → xo_clk on →
  reset=1 → xo_clk off → **msleep(50)** → sw-ctrl a entrada.
  **OFF**: reset=0 → **msleep(100)** → `vreg_disable` todos → `gpio_free` →
  clk disable. Nombres de vregs en tabla (orden [I]):
  `qcom,bt-vdd-{io,aon,dig,rfa1,rfa2,rfacmn,rfa-0p8,ipa-2p2}`. (`§1`).
- `msbtfw12.ver` (45 B): `BTFW.MOSELLE.1.2.0-00268.2-PATCHZ-1.76686.25` →
  ROM **1.2**, SoC Moselle. (`§2`).
- `msbtfw12.mbn` (109248 B, `3efbd7fa…`): ELF32-ARM EXEC, entry `0x23dc4`,
  3 phdrs: PH0 NULL (148 B cabecera), PH1 `off 0x1000 filesz 4616 memsz 8192
  → paddr 0x3d000`, PH2 `PT_LOAD off 0x3000 filesz 96960 memsz 100724
  (+3764 BSS) → paddr 0x23dc4 = entry`, flags RWX; el segmento termina
  **exacto a EOF** (slack 0). btqca lo pide como `qca/msbtfw12.mbn`
  (`ELF_TYPE_PATCH`, btqca.c:832-834) y lo emite por segmentos. (`§2`).
- `msnv12.bin` (6206 B, `52553c8a…`): NVM TLV tipo 2, `len 6202`
  (6202+4 = tamaño exacto). Con stride real 12 B (`struct tlv_type_nvm`,
  `btqca.h:134-140`): 63 tags hasta `end_idx==length==6202`
  (RESUELTO a favor por W2 §2b — el [N] «walker no encadena» era falsa alarma;
  testigos: `msnv11/apnv11/cmnv12/hmtnv20` de linux-firmware local, mismo
  esqueleto). Tag BD_ADDR @0x50, datos @0x5c = `ad 5a 00 00 00 00`
  (NO ceros; el kernel los COPIA); blob @0x62 (6108 B). (W2 §2b/2c corrige al
  informe §2, que con stride 4 describía tags (0,0)@0x48/0x4c y blob @0x5a —
  NO usar esa anatomía.)
- hci_qca.c: `qcom,wcn6750-bt` (2781) como **serdev**;
  `qca_soc_data_wcn6750` (2171-2186): 9 vregs `vddio 5mA, vddaon 26mA,
  vddbtcxmx 126mA, vddrfacmn 12.5mA, vddrfa0p8 102mA, vddrfa1p7 302mA,
  vddrfa1p2 257mA, vddrfa2p2 1700mA, vddasd 200µA`, caps wideband+LE.
  Con `enable-gpios`: `bt_en` + pulso 0→50ms→1→50ms en setup (1807-1817).
  `swctrl` **opcional** (`devm_gpiod_get_optional`, solo `IS_ERR` aborta;
  W2 §3c corrige al informe §3 que lo decía obligatorio; sin `enable-gpios`
  NO hay pwrseq `bluetooth` en wcn6750). OFF: bt_en=0 → 100 ms →
  reguladores off (2271-2280). (`§3`, W2 §3b/3c).
- UART: vendor `qup_uart@888000` (`qcom,msm-geni-serial-hs`, reg 888000/4000,
  wakeup-byte 0xFD, wakeup IRQ TLMM **43**, 4 pinctrl) == nuestro `uart10:
  serial@888000` (disabled, palawan.dtsi:1344; pinctrl gpio42/43 TX-RX +
  40/41 CTS-RTS, qup1_se2). `uart5` a94000 = consola: no tocar. (`§3`).
- Reguladores nuestros: `vreg_s3b_1p04` 968–1040 ✓ (4 rails),
  `vreg_s1b_2p04` 1856–2040 ✓, `vreg_s2b_1p4` 1256–1408 ✓ (calca vendor),
  `vreg_l7b_1p8` 1800 ✓. **Falta** grupo pmr735a (plantilla
  `lamma-qrd.dts:397`) para `vddrfa2p2`. **Cita lamma corregida por W2 §3c**:
  lamma:414-418 trae **3.008–3.96 V** (los 1.6–2.4 V son del vendor uke).
  (`§3`).
- **Hallazgo**: `vddasd` sin equivalente vendor pero `qca_init_regulators`
  hace `bulk_get` de los 9 (hci_qca.c:2358-2374) → sin `vddasd-supply` el
  probe falla; el borrador propone fixed always-on 0.95 V
  (**[N]** eléctricamente; alternativa: colgarlo de rail existente). (`§3`).
- Kconfig apta (`build/kernel-config/k37.config`): `BT=m, BT_QCA=m,
  BT_HCIUART=m, HCIUART_SERDEV/H4/QCA=y, SERIAL_DEV_BUS=y`
  (líneas 1630-1673, 3343). (`§3`).
- `xiaomi_wifi_gpio.ko` = driver de test GPIO WiFi/SAR (`xiaomi,xiaomi-wifi`),
  sin relación con BT; `wlan_firmware_service.ko` sin refs BT.
  **`bt_fm_slim.ko` no existe** en `vendor-modules-20261017/`
  (btpower + wifi_gpio + wlan_firmware_service). Sin gestor de GPIO
  compartido: el 156 lo maneja btpower en exclusiva (coordinar con
  `pwrseq-qcom-wcn` del frag wifi). (`§3`).
- FW a rootfs: `msbtfw12.mbn + msnv12.bin → /lib/firmware/qca/`
  (linux-firmware trae solo rev 11). Marcador: `hci0` +
  `QCA controller version` en dmesg; `sw_ctrl`(80)=1 con BT on. (`§3`).
- Verificación viva: `vendor.bt_firmware` en `sde35`;
  `soc:bt_wcn6750` presente; `rfkill0=bt_power state 0 (SOFT BLOCKED,
  coherente con `rfkill_init_sw_state(blocked)`)`, `rfkill1=phy0/wlan state 1`;
  `/dev/ttyHS0` 488:0 grupo bluetooth; `/sys/class/bluetooth` vacío
  (BT apagado, no se tocó). (`§4`).
- Target baud: init 115200 → oper `max-speed` (3.2M propuesto) o 3M proto;
  el NVM tag 17 (HCI) lo parchea el kernel en runtime (baud + bit IBS)
  (btqca.c:437-453). (`§2`).

Artefactos: `build/gates/revision/RE-NOCTURNO-20261017/artifacts/bt/`
(`parse_msbtfw.py` → `fw-tables.txt`; `wcn6750-bt-fragment.dtsi` v1 superado;
ver §6 para el v2 vigente en `artifacts/parches/`).

Pendiente: aceptación de `msnv12.bin` por `qca_tlv_check_data` en target
(`dmesg | grep -E "QCA Downloading|QCA,|tlv"` tras insmod hci_uart);
`vddasd` sin rail vendor; GPIO 156 egpio + colisión pwrseq wifi (mitigado);
baud 3.2M vs 3M; `bt_fm_slim.ko` ilocalizable (si existe en otra partición,

### 3.5 Audio WCD939x / FS19xx

Fuentes: `build/gates/revision/RE-NOCTURNO-20261017/RE-AUDIO-WCD939X-FS19XX.md`,
`.../RE-AUDIO-WCD939X-FS19XX-ADD1-DECOMP.md`,
`.../RE-AUDIO-WCD939X-FS19XX-ADD2-FSM-DRIVER.md`.

HECHO (informe base):

- `fs19xx_dlkm.ko` v4.0.7, FourSemi, GPL, `depends=miev,machine_dlkm`
  (`.modinfo`, `syms-evidence.txt`). (`§1`).
- Único `compatible`: **`foursemi,fs16xx`** (of_match + `alias=i2c:fs16xx`).
  El nombre del fichero ("fs19xx") ≠ compatible: el chip real es FS16xx
  aunque todo (nodo DT, firmware, kcontrols) se llame fs19xx
  (rodata `1cb0: fs16xx`, DT x4). (`§1`).
- Bus y direcciones: **i2c-4** (`qcom,i2c-geni` @0x88c000), 4 amps en
  **0x34, 0x35, 0x36, 0x37** (reg u32 = dirección 7 bit);
  nodos `fs19xx_smartpa@{34..37}`, todos `status ok`. (`§1`).
- GPIOs (TLMM phandle 0x16b; celdas `<phandle gpio flags>`): irq
  47/69/31/129 (flags 0x2008), reset 30/149/124/123 (flags 0x0).
  Pinctrl `default/sleep` por amp (8 estados `fs19xx_irq_{active,sleep}_*`).
  Números HECHO; qué esquina es cada amp INFERIDO (nombres
  bottom/top-left/right; correlación phandle↔nombre NO VERIFICADA — ver
  AUDIT que lo resuelve). (`§1`, `dt-fs19xx-props.txt`).
- Props que parsea el driver: `reset-gpio`, `fsm,rst-gpio`, `spksw-gpio`,
  `I2cAddress`, `fsm,re25-dft`, más `FS19XX_IRQ` / `FS19XX_RST_%02X` /
  `FS19XX_SPKSW`. En el DT Android **solo existen**
  compatible/reg/irq-gpio/reset-gpio/pinctrl — el resto usa defaults. (`§1`).
- Secuencia probe (símbolos+relocs): `fsm_i2c_probe` → `I2C_FUNC_I2C` →
  `of_get_named_gpio_flags` → `devm_gpio_request_one` + `gpiod_to_irq` +
  `devm_request_threaded_irq` → `regulator_get("fsm_vddd")`+`set_voltage/
  enable` → `fsm_detect_device` (lee DEVID) → `fsm_init_dev_list` (ndev:4)
  → `fsm_firmware_init` (`request_firmware_nowait`, fichero **`fs16xx.fsm`**
  por defecto; en uke carga `/odm/firmware/fs19xx.fsm` vía `fsm_set_fw_name`)
  → `fsm_codec_probe` (`snd_soc_register_component`,
  `set_smartpa_type("fs19xx")`) → "i2c probe completed".
  Arquitectura HECHO; valores de registros NO VERIFICADOS. (`§1`).
- DAI: **`fs16xx-aif`**, streams "AIF Playback"/"AIF Capture". (`§1`).
- Kcontrols ALSA (driver + tinymix en vivo, coinciden 1:1): `FSM_Scene`,
  `FSM_Volume`, `FSM_Stop`, `FSM_AMP_ON`, `FSM_Rotation`,
  `FSM_Ultrasound_Enable`, `FSM_SW_GPIO`. Estado idle real: Scene 0,
  Volume 255, Stop On, AMP_ON Off
  (`tinymix-uke-20261017.txt`, 310 líneas). (`§1`).
- IRQ/fault: threaded IRQ por amp (`fsm_irq_hander`→`fsm_work_interrupt`),
  monitor periódico (`fsm_work_monitor`: fault OC/UV/OV/OT/DC/SR/OTW;
  `vbat/tempr`, `fsm_get_amb_tempr`, calibración `re25`). Mecanismo HECHO. (`§1`).
- Firmware `fs19xx.fsm` 4828 B: cabecera ASCII **`00 01 "onlybsg" 00 "1"`**
  + preset binario (proyecto 1, fecha 20240814); formato propietario
  FourSemi (escenas+regs+ecualización). Bytes HECHO; semántica parcial
  INFERIDA. (`§1`).
- Machine (`machine_dlkm.ko`): `ALSA SoC msm`, alias
  `platform:pineapple-asoc-snd` + of `qcom,pineapple-asoc-snd[/-stub]`;
  tarjeta **`cliffs-mtp-snd-card`**; 53 links (proc-asound). (`§2`).
- Handshake smartpa: tipos `aw882xx/aw884xx/fs19xx/sia91xx/tfa98xx`; en uke
  **`smartpa_type="fs19xx"`**, `smartpa_num` INFERIDO 4;
  `smartpa_dai_link_select` elige para FS19XX los links
  **TDM-LPAIF_VA-RX-PRIMARY + -VIRT-2 (playback 42/43) y TDM-LPAIF_VA-TX-
  PRIMARY (capture 44)** con codec **`fs16xx.4-0034`** (solo el primer amp)
  dai **`fs16xx-aif`**; el driver amp replica a los 4 en modo sync. (`§2`).
- WSA: `wsa_max_devs=0`, slaves wsa883x/884x disabled → sin amplis WSA. (`§2`).
- WCD939x: `wcd939x_dlkm.ko` (+`_slave`, `wcd_core`, `wcd9xxx`), codec atado
  a SoundWire: `wcd939x-rx-slave` → SDW `e01170224`,
  `wcd939x-tx-slave` → `e01170223`; nodo `wcd939x-codec` compat
  **`qcom,wcd939x-codec`** + `qcom,split-codec`; `wcd939x-i2c@e` es el switch
  USB-C (usbss), NO el audio; supplies `cdc-vdd-{rx,tx,mic-bias,buck,px}`
  (rx/tx 1.8V, mic-bias ~3.296V…); mapas `rx_swr_ch_map/tx_swr_ch_map`. (`§3`).
- Variante: todo apunta a **WCD9395** (ficheros `*_wcd9395.xml`, strings
  `WCD939X_1_0`/`WCD939X_1_1`) pero el ID del chip NO se pudo verificar
  (dmesg rotado por spam wifi, uptime 3596s). **INFERIDO 9395,
  NO VERIFICADO a nivel registro.** (`§3`).
- Mainline (`k52-L16-tree/sound/soc/codecs/`): `wcd939x.c` + `wcd939x-sdw.c`
  existen y cubren **ambas variantes** (`CHIPID_WCD9390=0x0`/`WCD9395=0x5`,
  DT `qcom,wcd9390-codec`/`qcom,wcd9395-codec`, supplies
  `vdd-{rxtx,io,buck,mic-bias,px}`, `reset_gpio`, MBHC, slaves SDW).
  Diferencias vendor→mainline: nombre de supplies (`cdc-vdd-*` vs `vdd-*`),
  compat genérico (mainline exige 9390/9395 explícito), extras Xiaomi.
  Codec reutilizable con ajuste de DT. (`§3`).
- TPLG: `find /vendor /odm -iname '*tplg*'` → **vacío**; ruta AudioReach/APM:
  el grafo va dentro de `adsp.b00-bNN`, sin firmware separado.
  `/vendor/etc/audio/`: `sku_{cliffs,pineapple}[_qssi]` (uke usa
  `sku_cliffs/*wcd9395*`); `/odm/etc/audio`: `.wav` de calibración
  (tl/tr/bl/br-spk[_hp], spk_cal_silence, spk_dsm_test…),
  `misound_*spk*.bin`, `mis_*spk*.bin`. Sin `.acdb` visibles. (`§4`).
- Mixers de fábrica para música por altavoz (de
  `odm-mixer_paths_overlay_static.xml` + tinymix idle): ruta = TDM-VA → amps
  (NO pasa por WSA); `FSM_Scene=0` (stereo) / `7,9,11,13` (esquinas
  tl/tr/bl/br) / `1` (mono-2); `FSM_Volume=243` (stereo) / `235`
  (esquinas); `FSM_Stop=1` en reposo; `FSM_Ultrasound_Enable=0`;
  `FSM_SW_GPIO=0` (1 = handset/ultrasonidos); `FSM_AMP_ON`/`FSM_Rotation=0`;
  base añade `RX_HPH PCM=1`, ADC/IIR de micrófonos para speaker-mic. (`§5`).
- Gap mainline: **(1)** NO existe driver FS16xx/FS19xx (`fs210x.c`+
  `fs-amp-lib.c` solo FS2104/FS2105S, `foursemi,fs2105s`, DEVID 0x45/0x20);
  **(2)** NO existe machine pineapple+wcd939x+FS (`x1e80100.c` sin
  wcd93xx/smartpa); **(3)** WCD939x SÍ existe → solo DT+supplies;
  q6apm/q6prm/audioreach existen (`qdsp6/` completo). (`§6`).
- Orden barato-primero: **(a)** q6apm contra ADSP (BE `CODEC_DMA`/VA-TX,
  PCM capture de mics por SWR); **(b)** driver amp (I2C probe+DEVID+reset+
  irq+firmware+`fs16xx-aif`, scenes 0/7/9/11/13); **(c)** machine 3 links
  TDM-VA + UCM que replique §5; **(d)** WCD939x RX/headset al final. (`§6`).

HECHO (ADD1 — Ghidra `fs19xx_dlkm.ko`, 127/127 funciones;
`artifacts/audio/decomp-fs19xx/`; direcciones = offsets del .ko):

- `fsm_i2c_probe` (0x6f6c, 1692 B): `I2C_FUNC_I2C` →
  `check_smartpa_type("fs19xx")` → `fsm_parse_dts` inlined (lee
  **`reset-gpio`** → request `FS19XX_RST_%02X`, fatal si falla;
  **`interrupts`** → request `FS19XX_IRQ`; **`fsm,re25-dft`** default 0;
  **`spksw-gpio`** opcional) → `fsm_vddd_on` → reset GPIO **low, 10 ms,
  high, 1 ms** → `fsm_probe(dev, i2c_addr)` (si falla: evento mievent
  `PA i2c exception`) → workqueues + IRQ `devm_request_threaded_irq(...,
  NULL, fsm_irq_hander, 0x2002, "fs19xx", ...)` + `disable_irq` inicial
  (`0x2002` = ONESHOT + flanco) → `set_smartpa_type("fs19xx", 7)` →
  `fsm_codec_register` (solo primer amp). (`ADD1 §fsm_i2c_probe`).
- Hallazgo: el código pide la prop **`interrupts`**, pero el DT trae
  **`irq-gpio`** → IRQ inválido y `fsm_request_irq` lo omite: en uke los 4
  amps trabajan **sin IRQ** (solo monitor por workqueue). Un port mainline
  puede cablear `interrupts` correctamente o replicar el polling.
  (Código HECHO; comportamiento en boot NO VERIFICADO.) (`ADD1`).
- `fsm_probe` (0x316c): lee **registro 0x03** como DEVID; flag
  `(devid&0xfff0)==0x5B0`; `fsm_detect_device(dev, devid>>8)`: byte alto
  **0x05** / **0x06,0x0B** / **0x17,0x29** → `fs19xx_ops`.
  FS16xx de uke cae en la rama fs19xx (INFERIDO 0x17/0x29; lectura del reg
  0x03 en tablet NO VERIFICADA). (`ADD1`).
- `fs19xx_reg_init` (0x390c): `reg 0x10 ← 2`, leer, **15 ms**,
  `reg 0x10 ← 1`, poll **`reg 0x0E`** hasta `3`/`0x300` (5 intentos; si no →
  `fs19xx_i2c_reset` + `-0x6E`); `reg 0x14 ← re25<<1` (re25 de
  `fsm,re25-dft`, 0 en uke); `fsm_write_reg_tbl(dev, 0xFFFF)` (común) +
  `fsm_write_reg_tbl(dev, preset escena)`. **Los valores viven en el `.fsm`**,
  no hardcodeados. (`ADD1`).
- `fs19xx_start_up`: `fs19xx_get_srate_bits`: 8000→1, 16000→3, 32000→7,
  44100→8, 48000→9, 96000+ (rama aparte). Música Android 48 kHz/24-bit
  packed. Formatos DAI exactos NO VERIFICADOS. (`ADD1`).

HECHO (ADD2 — blob, secuencias, DAI/machine, TPLG, gap;
direcciones = offsets `.text` según symtab):

- Cabecera blob (offsets de fichero; `fsm_parse_preset @0x191C`): 0x00 u16
  LE `0x0100` (versión "1.0"); 0x02 8 B `onlybsg\0`; 0x0A 2 B `1\0`;
  0x0C 6 B relleno; 0x12 u32 LE `0x7E88727A` (año=2024 mes=8 día=14 f1=9
  f2=58); 0x16 u16 4828 (= tamaño; si ≠ falla); 0x18 u16 `0x912E`
  (checksum); 0x1A u16 4 (slices); 0x1C… 4×(u16 off, u16 tipo)
  `2C,0 / 4D8,0 / 984,0 / E30,0` (offsets ABSOLUTOS, tipo 0). (`ADD2 §1.1`).
- Checksum: **CRC-16/MODBUS (poly 0xA001 reflejado, init 0)** sobre bytes
  `[0x1A, fin)` (`fsm_calc_checksum @0xBD0`); tabla `g_crc16table` propia
  del módulo (`rodata+0x18B6`, `tab[1]=0xC0C1`); recomputado
  `almacenado 0x912E == calculado 0x912E` → **OK**
  (`fsm-blob-parser.py` lo re-verifica). (`ADD2 §1.2`).
- Slices (`fsm_init_dev_list @0x11C8`): slice 0 @0x002C addr **0x36**,
  1 @0x04D8 addr **0x37**, 2 @0x0984 addr **0x34**, 3 @0x0E30 addr **0x35**;
  tamaño 0x4AC c/u; `+0x1A`=nsec(3); secciones tipo **1 = info (17 words),
  2 = comunes (51), 3 = por escena (150)** (`fsm_get_data_list @0x1504`,
  `fsm_write_reg_tbl @0x1DA4`); tipo1@+0x0C, tipo2@+0x30, tipo3@+0xFE.
  (`ADD2 §1.3`).
- Escenas: tipo 3 = regs de 6 B `(u16 mask_escena, u16 desc_reg, u16 val)`;
  150 = 10 escenas × 15 regs, agrupados en orden ascendente. Máscaras:
  0x34: 0,1,2,3,4,5,6,**7,8**,15; 0x35: …**9,10**,15; 0x36: …**11,12**,15;
  0x37: …**13,14**,15. Mixer: `speaker`=0/vol 243, `speaker-tl`=7,
  `-tr`=9, `-bl`=11, `-br`=13 (vol 235), `speaker-mono-2`=1, `handset`=15
  (+`FSM_SW_GPIO`=1). Cadena escena→slice: **0x34=TL, 0x35=TR, 0x36=BL,
  0x37=BR** (correlación mixer-path→escena→máscara HECHO; choca con el orden
  supuesto de pinctrl en `dt-fs19xx-props.txt`, NO VERIFICADO — ver AUDIT).
  Escenas pares 8/10/12/14 y 2,3,4,5,6 sin uso en mixer (NO VERIFICADO).
  (`ADD2 §1.4`).
- Respuesta a «¿portar `fsm_parse_preset`?»: **No** — parser trivial ya
  replicado en `fsm-blob-parser.py`; el port pre-extrae las tablas a C
  (51 comunes + 10×15 por amp). Solo 2 regs de la común difieren por amp
  (idx 24: reg `0x1A` = `33/11/22/00`; idx 25: reg `0x1C` — ver AUDIT para
  los valores correctos): calibración por esquina, no promediar. Info
  idéntica salvo word[16] (`4/1/8/2` = índice de posición — INFERIDO).
  (`ADD2 §1.5`; AUDIT §2.1 corrige idx25).
- Codificación de registros (`fsm_reg_update_bits @0x950`; I2C 8-bit addr +
  16-bit BE, `fsm_i2c_reg_write @0x55BC`): `desc` 16 bits:
  `ancho-1 = bits15:12, shift = bits11:8, addr = bits7:0`
  (RMW: `val = (old & ~m) | (v<<shift & m)`); `0xF0xx` = write completo
  16 bits. **Corrección AUDIT §2.2**: la rama directa `0xF0xx` **sí** se usa
  (camino dominante, 804/804 entradas clase B); solo `fsm_reg_case`
  (especiales `0x1xxx/0x2xxx`) es inalcanzable. (`ADD2 §1.6`).
- Spec secuencias (`ADD2 §2`): probe HW `fsm_i2c_probe @0x6F6C`;
  reg_init `fs19xx_reg_init @0x390C` (`0x10←2/1`, poll `0x0E→3/0x300`,
  `0x14←re25<<1` con re25=info[2]=`0x102`, tabla común + escena);
  i2s `fs19xx_start_up @0x3BF0` (srate→bits `0x17[15:12]`: 8000→1 … **48000→9**
  … 192000→13; bit 11 de `0x17` = update);
  pll (bclk=rate·width·4 (+0x20 si 32 kHz) → idx 0..10;
  trío `0xA1/A2/A3` bajo `access_key`; tabla `g_fs19xx_pll_tbl
  @rodata+0x1AD8` EXTRAÍDA en `fs19xx-pll-table.txt`);
  enable (`0x11←0xEF`, `0x10←0`, volumen, `0x30←0x210`, 10 ms, RMW `0x4C`,
  RMW `0x34C` según escena);
  volumen `fsm_config_vol @0x21F8` (global 0..255 clamp; uke
  **`0x16←(vol<<8)|0xC0`** — ó `|0x80` si devid>>8==`0x17`);
  mute `fsm_mute_stream @0x6DC8` (playback: mute=0→`speaker_onn`,
  mute=1→`speaker_off`; capture se ignora);
  escena `fsm_set_scene @0x28F0` (`speaker_off` si on, 20 ms,
  `mask=1<<n`, `switch_preset` en amps con `mask&dev_mask`);
  shutdown `fs19xx_shut_down @0x4144` (`0x30←0x310`, `0x10←1`, 35 ms,
  `0x11←0`); calib `fs19xx_pre_calib @0x41B8`.
  Valores live: idle Scene 0/Volume 255/Stop On/AMP_ON Off; música
  Scene 0/243, esquinas 7/9/11/13/235. (`ADD2 §2`).
- DAI (`ADD2 §3`): `fsm_codec_register @0x4FB4`:
  `snd_soc_register_component(dev, &soc_codec_dev_fsm, &fsm_aif_dai, 1)` —
  **1 DAI**, solo el primer amp. Codec driver = solo probe/remove
  (relocs `.data+0x120/0x128`); probe añade **7 kcontrols**
  (`fsm_snd_controls @rodata+0x1CF0`, 7×80 B, `SOC_SINGLE_EXT`):
  nombres por relocs a rodata `0xEBE/0x89F/0x15B2/0x7D3/0xE9F/0x13F4/0x120D`.
- `fsm_aif_dai` (`.data+0x258`, 224 B; `.name→"fs16xx-aif"`): streams
  `capture→"AIF Capture"` (+0x80), `playback→"AIF Playback"` (+0xA8);
  formatos **`0x100000444` = S16_LE|S24_LE|S32_LE|S24_3LE** (bits 2,6,10,32);
  rates máscara `0x7FE` + constraint_list de **6:
  8000/16000/32000/44100/48000/96000**
  (`fsm_constraints @rodata+0x1FD8` = `{list→0x1FE8, count=6}`).
  Canales 1..4: de INFERIDO a HECHO por AUDIT (u32 crudos `min=1 max=4`).
  (`ADD2 §3.1`; AUDIT §1e).
- `fsm_aif_dai_ops` (`@rodata+0x1F20`, 184 B; 6 relocs):
  set_sysclk @0x6D34 (solo log), set_fmt @0x6D68 (solo log),
  mute_stream @0x6DC8, startup @0x6E14 (constraints),
  shutdown @0x6EA0 (noop), hw_params @0x6EA8
  (`set_i2s_clocks(rate, rate·width·4)` → `start_up`).
  OJO: estos offsets **no coinciden** con `struct snd_soc_dai_ops` de
  k52-7.2 (set_sysclk=+0x20 allí) — NO portar offsets, portar el CONJUNTO.
  (`ADD2 §3.2`; AUDIT §1e).
- Machine (`ADD2 §3.3`): tarjeta `cliffs-mtp-snd-card`
  (DT `qcom,model`; `qcom,pineapple-asoc-snd`), 53 links; 3 links TDM-VA con
  codec `fs16xx.4-0034` dai `fs16xx-aif`; props DT (`dt-sound-nodes.txt` §3):
  `qcom,model`, `asoc-codec-names`, `qcom,wsa-max-devs=0`,
  audio-routing, mi2s/auxpcm/tdm-intf, mbhc, dmic-gpios, `wcd939x-i2c-handle`.
- TPLG (`ADD2 §4`): `find /vendor /odm -iname '*tplg*'` → **vacío**;
  `find / -maxdepth 4 -iname '*tplg*'` → **vacío**;
  `/vendor/firmware_mnt/image/adsp.b00…bNN` presentes → DSP AudioReach
  (grafo dentro del FW del ADSP). En mainline: `/lib/firmware/qcom/cliffs/*`
  o topología embebida (`q6apm + topology.c` existen en k52).
  **Gate = PCM capture por VA-TX con UCM mínimo antes de topology.**
- Gap mainline k52-L16=7.2-rc2 (`ADD2 §5`): FS16xx NO existe (fs210x solo
  0x20/0x45); machine pineapple+wcd939x+FS NO existe (k52 trae hasta
  `x1e80100.c`; plantilla de link VA: `sc8280xp.c`-estilo); WCD939x SÍ
  existe (9390=`0x0`/9395=`0x5`); q6apm/audioreach/topology SÍ existen.
  Riesgos: DEVID real sin leer (bloquea match `17/29` y volumen `|0xC0` vs
  `|0x80`); offsets `dai_ops` vendor ≠ 7.2; escenas pares sin uso conocido;
  `re25=0x102` del preset manda sobre DT.

HECHO (AUDIT-ADD2 — auditoría recomputada; `.ko` vendor 156168 B, ELF
aarch64, BuildID `30b03b1c…5b9c`, copia de trabajo en /tmp):

- (a) Cabecera y CRC — **PASS**: `ver 0x0100`, `onlybsg\0`, `1\0`, `FE×6`,
  dateword `0x7E88727A` (2024-8-14/9/58), `len 4828 == fichero`,
  `stored 0x912E == calc 0x912E`; `g_crc16table @rodata+0x18B6`:
  `tab[0..3] = 0, C0C1, C181, 0140`. (`AUDIT §1a`).
- (b) Slices e I2C — **PASS**: dir `2C/4D8/984/E30` tipo 0;
  `slice+0x1E` = `0x36/0x37/0x34/0x35`; los 4 slices son contiguos exactos
  de `0x4AC` y las 3 secciones teselan sin huecos (tipo1@+0x0C/17w,
  tipo2@+0x30/51, tipo3@+0xFE/150). (`AUDIT §1b`).
- (c) Escena↔amp y TL/TR/BL/BR — **PASS, inferencia REFORZADA**: máscaras
  recomputadas `0x34:{7,8} 0x35:{9,10} 0x36:{11,12} 0x37:{13,14}`;
  mixer verificado en cosecha (`speaker-tl/tr/bl/br = 7/9/11/13`,
  vol 235; `speaker = 0`, 243; `handset = 15 + FSM_SW_GPIO=1`).
  NUEVO (doble fuente): phandles pinctrl del DT resuelven
  `0x617=top_left→@34`, `0x619=top_right→@35`,
  `0x61b=bottom_left→@36`, `0x61d=bottom_right→@37` — la misma asignación
  que mixer+blob. El "choque" que ADD2 dejaba NO VERIFICADO queda resuelto
  a favor de ADD2. (`AUDIT §1c`).
- (d) Tabla PLL — **PASS 11/11**: volcada de `rodata+0x1AD8`, idéntica a
  `fs19xx-pll-table.txt` (idx 9 = `C000/005D/0260`,
  bclk 6144000 = 48 kHz×32×4 ✓). Símbolo existe en symtab (132 B).
  `words[3..5]` sin uso en `start_up`: sigue NO VERIFICADO. (`AUDIT §1d`).
- (e) DAI — **PASS**, con mejora (ver arriba: canales 1..4 HECHO; 6 relocs
  ops → `.text+0x6D34/6D68/6DC8/6E14/6EA0/6EA8`; kcontrols stride 80,
  nombres + `info_volsw` + get/put pares). (`AUDIT §1e`).
- (f) Machine — **PASS**: leído en vivo `machine_dlkm.ko` (strings `fs19xx`,
  3 links TDM-VA, `fs16xx.4-0034`, `fs16xx-aif`,
  `set/check/get_smartpa_type`); `/proc/asound/cards` =
  `cliffs-mtp-snd-card` ✓; DT `compatible = qcom,pineapple-asoc-snd` ✓.
  (`AUDIT §1f`).
- (g) Secuencias §2 — **PASS** (spot-check decompilado): probe `reg 0x03`,
  `(devid&0xFFF0)==0x5B0` + `detect_device(devid>>8)` acepta
  `05/06/0B/17/29` ✓; `reg_init` ✓; volumen `0x06←vol<<8` vs
  `0x16←(vol<<8)|0xC0` (`|0x80` si byte devid `==0x17`) ✓; quirk escena
  `mask 1 → 0x10` con flag `0x40040&==0x40000` ✓;
  srates `32000→7, 0xAC44→8, 16000→3…` ✓. (`AUDIT §1g`).
- Tablas C generadas: `fsm-blob-emit-c.py` (parsea con asserts) →
  `fs19xx-presets.h` (807 l.: `fs19xx_common[51]`, `fs19xx_calib[4]`,
  `fs19xx_scenes[4][10][15]` de `(mask,desc,val)`, `fs19xx_amps[4]`,
  `fs19xx_pll[11]`); `gcc -fsyntax-only -Wall` limpio; roundtrip CRC;
  conteos 51 + 600; **FULL MATCH 651/651** contra el blob; 3 entradas al
  azar confirmadas en `fsm-blob-decoded-full.txt`. Cubre TODO-1 del
  skeleton. (`AUDIT §3`).
- DEVID real — PENDIENTE con evidencia nueva: `/dev/i2c-*` NO existe en
  Android (sin `i2c-dev`; `i2cdump/i2cdetect` presentes pero sin nodo) →
  el gate "i2cdump 4 0x34" del ADD2 **no es ejecutable como está escrito**.
  Vías: printk de `fsm_probe` en arranque en frío (doble captura),
  ioctl vendor `/dev/fsm_misc` (semántica sin verificar: NO intentado),
  o kernel con `i2c-dev`. Cero escrituras realizadas. (`AUDIT §4`).

Artefactos: `build/gates/revision/RE-NOCTURNO-20261017/artifacts/audio/`
(`tinymix-uke-20261017.txt`, `fs19xx.fsm`, `dt-fs19xx-props.txt`,
`dts-fs19xx-draft.dtsi` BORRADOR, `syms-evidence.txt`, `decomp-fs19xx/`
127 fns, `fsm-blob-parser.py`, `fsm-blob-decoded.txt` 38 l.,
`fsm-blob-decoded-full.txt` 842 l., `fs19xx-pll-table.txt`,
`fs19xx-mainline-skeleton.c` borrador TODO-1..7, `dts-fs19xx-add2.dtsi`,
`fsm-blob-emit-c.py`, `fs19xx-presets.h`).

Pendiente: `fsm_write_reg_tbl`/`fsm_parse_preset` (formato ya resuelto por
ADD2/AUDIT — queda `--emit-c`, HECHO vía `fs19xx-presets.h`);
`fsm_codec_register` (dai_driver completo), `fs19xx_pre_calib` (re25/calib);
DEVID real (gate reformulado); `words[3..5]` del PLL; escenas pares
8/10/12/14; `dai_ops` con layout 7.2; orden de ataque (a)→(d) del ADD2 §5.


### 3.6 WiFi (BDF o82gl + payload v2)

Fuente: `build/gates/revision/RE-NOCTURNO-20261017/RE-WIFI-BDF.md`.

HECHO:

- `bd_o82gl.elf`: ELF32 LE ARM, EXEC, entry 0x8000, 1 PT_LOAD, 6 secciones
  (`file` + `readelf -h/-S/-l`); `.data` PROGBITS en **file offset 0x400 =
  1024, tamaño 0xE344 = 58180 B** (vaddr 0x1000). (`§1`).
- Símbolos `_binary_tempDir_O82GL_bin_{start,size,end}` → wrapper de
  `objcopy -I binary` renombrado; `.noinit` tamaño 0 (ceros del offset
  0x52 al 0x400). (`§1`).
- `dd skip=1024` a secas da 58904 B (arrastra tablas ELF, sha a0fb4c8f… —
  NO usar). Extracción correcta: `dd bs=1 skip=1024 count=58180` → sha
  `da424c03ef32bc4f…` = el esperado
  (`artifacts/wifi/board-o82gl-data58180.bin`). (`§1`).
- Cabecera BDF (`xxd`): `01 00 04 04 00… 38 6e 26 92 …` — sin magic ASCII;
  se pasa crudo por QMI en api-1. INFERIDO: u16 en offset 10
  (`0x9226` o82gl vs `0xA6DD` o82) = campo de variante; resto NO VERIFICADO.
  (`§1`).
- Variantes en la tablet (`ls /vendor/firmware_mnt/image/qca6750/`):
  8 `bd_*.elf` (o82, o82gl, o82in, n9, n9in, n16t, n16tgl, n16tin) +
  `bdwlan.b{01..20}`/`bdwlan.e{01..20}`/`bdwlan.bin` (58180 B crudos) +
  `Data.msc`. (`§2`).
- Payload de `bd_o82.elf` = `2a63af3f…` **== `board.bin` del payload v1 byte
  a byte** (`cmp` limpio) → v1 = variante o82, NO la del uke.
  `bd_o82.elf` también 58180 B de `.data`. (`§2`).
- `cmp -l` o82 vs o82gl: solo **159 bytes difieren de 58180** (cabecera ID +
  zonas de calibración ~6K/12K/44K). Misma estructura, distinta calibración
  → usar BDF ajeno = riesgo real. (`§2`).
- `bdwlan.b01` (58180) difiere de AMBOS en byte 11 → tercera variante
  (ficheros por-placa del vendor; mainline api-1 no los usa).
  `amss.bin` de kiwi en tablet == `amss.bin` de v1 (`c42e06f5…`, pull 7 MB
  verificado) → v1.amss era kiwi, no qca6750. (`§2`).
- regdb: tres blobs distintos de 24278 B; sin magic/firma ELF; entradas país
  (`41 46 41 46`="AF AF"); 14 B de ceros al final. Primeros u16 distinguen
  build: v1-staged `c68d`, tablet `qca6750/regdb.bin` `c66d`,
  **`qca6750/regdb_xiaomi.bin` `f836` = nuestro `fca5bbfa…`**. (`§3`).
- `cmp -l`: v1-regdb vs tablet-genérico = 684 B; tablet-genérico vs xiaomi =
  624 B; **kiwi/regdb_xiaomi.bin (`237fc609…`) vs qca6750/regdb_xiaomi.bin =
  905 B** → ni los dos "xiaomi" son iguales. El que pide el Android vivo
  (`qca6750/regdb_xiaomi.bin`) es `fca5bbfa…` → ese va en v2. Destino
  mainline: `ath11k/WCN6750/hw1.0/regdb.bin`. (`§3`).
- Nombres mainline (árbol k52-L16, grep): `ATH11K_FW_DIR="ath11k"`
  (`hw.h:74-82`); `board-2.bin` (api-2), `board.bin` (api-1), `amss.bin`,
  `m3.bin`, `regdb.bin`; ruta = `ath11k/<fw.dir>/<fichero>`
  (`core.h:1342-1359`); WCN6750 `fw.dir="WCN6750/hw1.0"` (`core.c:579-585`,
  `board_size=256 KiB` — caben .elf 59928 y BDF 58180). (`§4`).
- `core.c:630` (bloque wcn6750): `supports_regdb=true`,
  **`m3_fw_support=false`**, `fixed_fw_mem=true`.
  `qmi.c:2600`: `ath11k_qmi_m3_load` solo si `m3_fw_support` → **m3.bin NO se
  pide**; `mhi.c:357`: `amss.bin` solo lo pide el camino MHI/PCI → **en AHB
  no se pide**. (`§4`).
- `qmi.c:2414-2445`: BDF con `\x7fELF` → `BDF_TYPE_ELF`, si no → `BIN`;
  regdb → `BDF_TYPE_REGDB` (no fatal, `qmi.c:2987`). Con BDF BIN crudo sigue
  a caldata: `cal-ahb-*.bin`/`caldata.bin` → **OJO: este árbol lleva poke
  local** (`qmi.c:2484-2502`, comentario "UKE (kiwi/uke, 26-sep)") que
  devuelve 0 sin cal en vez de -ENOENT. Sin ese poke, el probe abortaría.
  El poke existe en k52-L16: verificar que el kernel del próximo test lo
  incluye (NO VERIFICADO en imagen de boot). (`§4`).
- Veredicto v1 (`tar -tzf` + shas): `board.bin` MAL (o82), `regdb.bin` MAL
  (genérico de otro build), `amss.bin` SOBRA (7,4 MB muertos, era kiwi);
  no hay `board-2.bin`/`m3.bin` (bien — no añadir `board-2.bin` de
  linux-firmware: colisión de calibración ajena). (`§4`).
- Extra vendor .ko (`strings` sobre copias PC,
  `build/android/vendor-modules-20261017/`): `xiaomi_wifi_gpio.ko` (65 KB,
  vermagic 6.1.68-android14) = driver GPIO de test/SAR
  (`xiaomi,xiaomi-wifi`, autor USUARIO@example.invalid; INFERIDO: SAR/CN fuera
  de P4); `wlan_firmware_service.ko` (98 KB) = cliente QMI WLFW
  (`qcom,wlan`, `bdf_download`, `cal_download/report`, `m3_info`,
  `mac_addr`, `qdss_trace`, `respond_mem`) = homólogo vendor de
  `ath11k_qmi.c` (INFERIDO: confirma el protocolo). (`§5`).
- Hallazgo lateral (pull `wpss.mdt` 4844 B): el WPSS de v1 NO es el del
  vendor vivo — `wpss.mdt` tablet = `b3451c51…` ==
  `build/pkg/uke-fw-radio/wpss.mdt` ≠ v1 (`e2d14e4f…`); tamaños de los 13
  segmentos idénticos en los tres lados. El `.mdt` porta los hashes →
  el set v1 es otro build (stage s21). NO se mezcla: v2 conserva el set v1
  intacto ("levanta" según #441). Gate propuesto v3: pull de los 13
  `wpss.b*` del vendor, comparar shas, decidir swap del SET COMPLETO
  (nunca solo el .mdt). (`§6`).
- Payload v2 — construido y verificado: `preparar-wifi-payload.sh` no acepta
  sustituciones → reconstrucción manual con idéntica estructura que v1
  (`tar xzf v1`, sustituir `WCN6750/hw1.0/board.bin` (da424c03) y
  `regdb.bin` (fca5bbfa), borrar `amss.bin`, reempaquetar mismos top-dirs,
  reverificar por extracción). Salida:
  `build/pkg/uke-wifi-payload-v2.tar.gz` (**24.646.368 B**),
  sha `2b0dd75a7db86e0889a53d91830a2138a9651d14f31f59321f0924ead49f4c4c`
  (`build/pkg/uke-wifi-payload-v2.sha256`); v1 sha `dfca8884…` (28 MB).
  Diff v1→v2 (listados): **solo** `- usr/lib/firmware/ath11k/WCN6750/hw1.0/
  amss.bin`; `board.bin`/`regdb.bin` mismo path, contenido sustituido
  (shas verificados post-extracción); módulos (7.2.0-rc2-palawan, blacklist
  incluida) y WPSS intactos de v1. Uso en tablet:
  `tar xzf uke-wifi-payload-v2.tar.gz -C / && depmod -a`. (`§7`).
- Qué cambia para el próximo test WiFi + gate: BDF o82gl correcto, regdb
  Xiaomi del path vivo, −7,4 MB muertos; resto idéntico a v1. Gate en
  nuestro Linux (modprobe manual con wifi en blacklist, DT solo-wifi):
  `dmesg` debe mostrar `using board api 1` + `bdf_type 0` (BIN, NUESTRO BDF
  CRUDO — no 2/ELF salvo que se sirva el .elf) + `fetched regdb` +
  `qmi-chip-id/qmi-board-id` + `fw_ready` + `wlan0` + `iw scan` OK + SSH con
  uptime > 300 s. Avisos: (a) el kernel del test debe llevar el poke
  caldata de `qmi.c`; (b) WPSS v1≠vendor (§6) — si el wpss no levanta, el
  siguiente paso es el set vendor, no reintentar BDF. (`§8`).

Artefactos: `build/gates/revision/RE-NOCTURNO-20261017/artifacts/wifi/` +
`build/pkg/uke-wifi-payload-v2.tar.gz` (+ `.sha256`).

Pendiente: ver §8 (gate) y §6 (gate v3 del set WPSS vendor completo).

### 3.7 Teclado folio / hall / sensores

Fuente: `build/gates/revision/RE-NOCTURNO-20261017/RE-FOLIO-SENSORES.md`.

HECHO (folio):

- Cadena completa: **MCU Nanosic 803 por I2C → driver vendor la re-exporta
  como 4 HID → filtro vendor los observa**. (`§1`).
- Transporte: nodo DT `/soc/qcom,qupv3_0_geni_se@ac0000/i2c@a8c000/nanosic@4c`,
  compatible `nanosic,803`, `reg=0x4c`. Driver `nanosic_driver.ko`
  (358128 B, md5 b97ec7f5…, autor USUARIO@example.invalid) con
  `alias: of:N*T*Cnanosic,803` + `i2c:nanosic,803` (`modinfo`).
  Vivo como `5-004c` en `i2c-5` (= `i2c@a8c000`, confirmado por
  `readlink …/i2c-5/of_node`). Depende de
  `xiaomi_keyboard_driver,panel_event_notifier`. (`§1`).
- GPIOs (celdas BE): irq_pin TLMM 116 (flags 0x2001), reset 127, sleep 98,
  status 128. pinctrl `nanosic_keyboard_mcu`: default=gpio127+128
  (drive 2, bias-disable), sleep=gpio98 (pull-down). (`§1`).
- Supplies: vdd=`pmxr2230_l22` 3,3 V fijo, dvdd=`pmxr2230_l23` 1,8 V fijo
  (phandles 0x357/0x358 resueltos por barrido de `phandle`; coincide con
  suppliers en `/sys …/5-004c`: ldob22/ldob23). (`§1`).
- HID (structs en .rodata + `llvm-objdump`): `Nanosic_hid_ll_driver`
  (`hid_allocate_device`/`hid_add_device`/`hid_input_report` en imports)
  con **bus forzado a 6 (=BUS_BLUETOOTH), VID 0x15d9** y 4 descriptores
  embebidos en tabla en offset `0x1878`: keyboard PID 0x00a3 (61 B), mouse
  0x00a2 (56 B), touch 0x00a1 (277 B, página Digitizer 0x0d), consumer
  0x00a4 (25 B). Extraídos a `hid-desc-*.bin/.hex`
  (sha ea3772c6/3eef32d1/ba58e86f/5921bb88). Explica
  `/proc/bus/input/devices`: `0006:15D9:00A1-A4` → `Xiaomi Touch/Mouse/
  Keyboard/Consumer` (`adb … cat /proc/bus/input/devices`). (`§1`).
- Filtro (Ghidra `decomp-keyboard/`): `xiaomi_keyboard_driver.ko` (69 KB)
  **NO es driver de bus**: `xiaomi_keyboard_ids` es tabla cero y
  `xiaomi_keyboard_input_connect` solo se engancha por nombre a
  `Xiaomi Touch|Consumer|Keyboard` (Handlers `xiaomi_keyboard` en
  input7/9/10, NO en Mouse). Crea `/proc/last_keypad_events`,
  `/proc/last_touchpad_events` + filtro de bordes/gestos touchpad con
  params del DT (edge left 0-320, right 2879-3199, top 0-427, bottom
  1708-2135). El `uinput-xiaomi` (0666:0888) lo crea el lado nanosic
  (chardev `Nanosic_input_write`), no este filtro. (`§1`).
- Keylayout: `ls /system/usr/keylayout|/vendor/usr/keylayout|/system/usr/idc
  | grep 15d9` → vacío. Sin `.kl`/`.idc` propios: usa `Generic.kl`.
  Nada que portar aquí. (`§1`).
- Conclusión: el folio por pogo-pines es **protocolo Nanosic propietario
  sobre I2C** (`bootID … not match`, `waiting for 803 i2c controller`,
  chardev propio), NO HID-over-I2C estándar. Mainline exige **driver nuevo**
  i2c→HID reutilizando los 4 descriptores extraídos; el filtro
  xiaomi_keyboard es prescindible (telemetría+gestos MIUI).
  Borrador: `dts-nanosic-folio.dtsi`. (`§1`).

HECHO (hall):

- Driver (Ghidra `decomp-hall/xiaomi_hall_probe.c`): platform driver
  `xiaomi_hall`, **sin MODALIAS** (`modinfo` sin alias → casa por nombre).
  Por cada hijo lee `label`, `linux,code`, `linux,input-type`, `hall_pin`
  (`of_get_named_gpio_flags`) y `open_irq`/`close_irq`
  (`of_irq_get_byname`); pide threaded IRQ (flags 0x2001, nombres
  `<label>_open/_close`); registra input `xiaomi-hall`/`xiaomi-hall/input0`
  (bustype 0x19). Chardev `/dev/xiaomi_hall` + sysfs `disable_algo`
  (modo GPIO puro). (`§2`).
- DT: `/soc/xiaomi_hall`, compatible `xiaomi-hall`, status ok. Hijos:
  `lid_hall` (EV_SW=5, **SW_LID=0**, TLMM gpio 99) y `table_hall` (EV_SW=5,
  **SW_TABLET_MODE=1**, TLMM gpio 100). En tablet: input `xiaomi-hall` con
  `EV=21 SW=3` (`/proc/bus/input/devices`). (`§2`).
- Clave: los `interrupts-extended` NO van al TLMM sino a
  `qcom,smp2p-adsp/qcom,hall-in-lid` (phandle 0x55c, entry `mi_hall_lid`) y
  `…/hall-in-table` (0x55d, `mi_hall_table`), ambos
  `interrupt-controller` con `#interrupt-cells=2`. **Mainline `smp2p.c` del
  árbol k52 YA implementa irq_domain para inbound entries**
  (`grep irq_domain|irqchip drivers/soc/qcom/smp2p.c`: `smp2p_irq_map`,
  `smp2p_irq_get_irqchip_state`). Ruta SMP2P portable. (`§2`).
- Recomendación: **ruta A `gpio-keys` sobre TLMM 99/100** (cero código,
  `wakeup-source`, verificar polaridad con evtest); ruta B = portar
  `xiaomi_hall.c` + nodos smp2p si A falla.
  Borrador con ambas: `dts-xiaomi-hall.dtsi`. (`§2`).

HECHO (sensores — tabla §3; `dumpsys sensorservice` completo en
`tablet-sensorservice.txt`, 1370 líneas, «Total 53 h/w sensors»):

- **Ningún sensor físico cuelga de buses I2C del AP** (barrido de todos los
  hijos `i2c@*` de QUP0/QUP1: solo ktz8866, wcd939x, nanosic, cámaras,
  smartpa, ntag; `grep -ril lsm6ds|qmc6|stk3|sip1328|sx937…` en DT solo da
  nodos slpi/mem). Todo va por **SSC dentro del ADSP** (HAL
  `sensors.qsh.so`, servicios `vendor.qsap.sensors`/`vendor.sensors
  running`; fw `adsp.mdt`+`adsp.bXX` presente; `adspslpi_region@9d400000`
  en DT; sin ficheros `slpi*` sueltos = SLPI fusionado en ADSP).
  `qti_qmi_sensor_v2.ko` (40 KB, md5 d79f2bd1) es solo cliente QMI
  **térmico** (`qcom,qmi-sensors`, `QMI_BEAMER_*_THERM`), no IMU/luz. (`§3`).
- Físicos y ruta mainline k52:
  STMicro lsm6dso (acc+gyro ≤416 Hz) → SSC; driver SÍ existe
  (`iio/imu/st_lsm6dsx`, lista LSM6DSO en `st_lsm6dsx.h`).
  QST qmc630x (mag) → SSC; driver NO (`grep -ril qmc63 drivers/iio` vacío).
  Sensortek stk3bcx (ALS+prox+CCT) → SSC; driver NO (`stk3310.c` no
  menciona stk3b*). SI sip1328 (back-lux+flicker) → SSC; driver NO
  (cero hits en todo el árbol). Semtech sx937x (SAR) → SSC; parcial
  (sx9310/24/60 sí, **sx937x NO**). Virtuales → SSC algoritmos QTI/Xiaomi.
- Recomendación: ruta **SSC-ADSP** (llevar ADSP `remoteproc-adsp@03000000`
  + firmware vendor y hablar SEE/QMI), NO IIO directo: 4 de 5 físicos
  carecen de driver y buses/IRQ/supplies ni existen en el DT del AP.
  Es un port grande, detrás de táctil/BT/pantalla.
  (`grep sensors-see` en `drivers/iio` vacío.) (`§3`).

Artefactos: `build/gates/revision/RE-NOCTURNO-20261017/artifacts/folio-sensores/`
(pulls `nanosic_driver.ko`, `qti_qmi_sensor_v2.ko`; `decomp-keyboard/`
36 .c + `decomp-hall/` 14 fns Ghidra 12.1.4, 0 fallos;
`hid-desc-{keyboard,mouse,touch,consumer}.{bin,hex}`;
`tablet-sensorservice.txt`; `dts-{nanosic-folio,xiaomi-hall}.dtsi`
BORRADORES sin probar). (`§4`).

Pendiente (NO VERIFICADO): polaridad hall para gpio-keys; protocolo I2C
Nanosic a nivel byte. (`§5`).

### 3.8 Omarchy offline

Fuente: `build/gates/revision/RE-NOCTURNO-20261017/ATAQUE-OMARCHY-OFFLINE.md`.
Objetivo F6 + F8; sin tablet accesible; verificado contra
`build/stage-escritorio/` (pkgs 11-oct) y ledger hermano (solo lectura).
Ningún fichero existente editado; artefactos nuevos en
`artifacts/omarchy/`.

HECHO:

- `omarchy update` = `update-requires-free-space` → prune →
  `snapshot create` (sin snapper: exit 127, tolerado) → `update-dev` →
  `update-keyring` → **`update-system-pkgs` (`pacman -Syu`)** →
  **`omarchy-migrate`** → hook post-update → aur → mise → orphans →
  analyze → status → `update-restart`.
  Fuente: `omarchy-4.0.4-2/usr/bin/omarchy-update:28-63`. (`§0`).
- `omarchy-migrate` corre cada `/usr/share/omarchy/migrations/*.sh` sin
  marcador en `~/.local/state/omarchy/migrations/<fichero>` con
  `bash -euo pipefail`, y él mismo lleva `set -euo pipefail`: **el primer
  fallo aborta la tanda, no deja marcador y se reintenta en cada
  login/update**. Fuente: `usr/bin/omarchy-migrate:88-97`. (`§0`).
- **Sellado oficial**: el paquete trae las 106 semillas en
  `etc/skel/.local/state/omarchy/migrations/` → un usuario NUEVO nace con
  todo marcado. El `alarm` de la uke es anterior a las semillas ⇒ 106
  pendientes (ledger #634). Sellar = crear el marcador (misma semántica
  que upstream, sin puentear nada). (`§0`).
- 106 migraciones en pkg (contadas del tarball) = las "106 pendientes" del
  ledger. Las 128 de `docs/informes/A-port-omarchy-aarch64.md:63` corresponden a un commit
  anterior; el número vigente es 106. (`§0`).
- Clasificación (detalle en `artifacts/omarchy/migrations-uke-lists.txt`):
  **SELLAR 1**: `1781984677` (snapper normalize). Sin
  `/etc/snapper/configs/root` fuerza el repair vía
  `install/config/snapper.sh`, que exige binario snapper ausente (y rootfs
  ext4): **fallo seguro → atasca migrate + cada update**. Es el único
  killer confirmado. (`§1`).
- **EJECUTAR ~25** (resuelven en ALARM extra u `omarchy.db` edge/aarch64
  del 11-oct, 178 entradas): todos los `omarchy-pkg-add` de migraciones
  resuelven (mpv-mpris, dua-cli, udiskie, cups-pk-helper, ddcutil,
  lsp-plugins, libvips, qrencode, qt6-imageformats, yt-dlp, zbar,
  sof-firmware, vulkan-intel, networkmanager, herdr, omacalc, tensaku,
  ttfx, libfprint-git, mise-bin, quickshell-git…). `paru` no existe en
  ningún repo pero **ninguna migración lo usa** (AUR va por `yay`,
  presente en edge). Queridas en uke: `1782002156` (NM enable),
  `1784568652` (mask NM-wait-online), `1784914435` (wifi powersave off),
  `1781793381` (udiskie, que DESKTOP-OMARCHY-REVISION §6 echa en falta).
  Vigilar: `1784672586` (cambia a quickshell-git; `1787399318` lo revierte
  luego al empaquetado — orden temporal, compatibles),
  `1788124236` (sshd hardening con patrón `skip()`+exit 0, no bloquea;
  **verificar `authorized_keys` de alarm antes**: la tablet vive del SSH
  por NCM). (`§1`).
- **NOOP ~80** por guardas verificadas en fuente: `1789325478`
  (`uname -m==x86_64 || exit 0`), `1789444024` (solo si kernel presente),
  T2/Broadcom/NVIDIA/Limine (`lspci` en condición `if`,
  `omarchy-cmd-present limine-mkinitcpio || exit 0`, guards de fichero),
  `1784809452` (`command -v snapper || exit 0`), `1784401744` (array hw
  vacío en Qualcomm), `1782049344` (`rm -f` + `|| true`). Resto: config de
  usuario sin deps de arch. (`§1`).
- Wrappers (borradores en `artifacts/omarchy/`, NO instalados):
  (a) `omarchy-pkg-add-tolerant.sh` (clasifica por `pacman -Q` / `pacman
  -Si` / resto skip exit 0; UNA transacción; DBs obsoletas ⇒ aviso
  `pacman -Sy`; instalación prevista `/usr/local/bin` por precedencia
  PATH, `/usr/bin` intacto); (b) `omarchy-update-restart-uke.sh` (si
  `/usr/lib/modules/$(uname -r)` existe pero ningún paquete lo posee →
  kernel externo boot.img, omite prompt; si un paquete posee módulos de
  otra versión → prompt); (c) `seal-migrations-uke.sh` (ejecuta cada
  pendiente aislada, sella solo SELLAR con motivo,
  `--pending/--dry-run/--verify`; uso como `alarm` con sudo caliente).
  (`§2`).
- Checklist primer `omarchy update` por NCM/USB (`§3`): pre PC
  (`build/gates/uke-ssh.sh` a 192.168.42.129; `df /` ≥10 GiB o
  `update-requires-free-space` aborta; bypass solo
  `OMARCHY_UPDATE_FORCE=1`); G0 tablet (`slot-retry-count:b`≥3, batería
  ≥3700 mV, consola ACM con lector único); G1 DBs (`pacman -Sy` +
  `pacman -Si herdr quickshell-git`); G2 sellado (`--dry-run`, luego run;
  fallidas=0 salvo reintento manual); G3 update (`omarchy update -y`;
  NUNCA `pacman -Syu` directo — guard `00-omarchy-update-guard.hook`
  AbortOnFail; bypass `OMARCHY_ALLOW_DIRECT_PACMAN=1` solo para
  `-S <paquete>` puntuales; NUNCA `omarchy refresh pacman` — reescribe
  `pacman.conf` con plantilla `[multilib]` x86-only; personalizar vía hook
  `~/.config/omarchy/hooks/pre-refresh-pacman.d/`); avisos esperados no
  fatales (`archlinux-keyring` "target not found" — ALARM usa
  archlinuxarm-keyring, exit 0; "No Snapper configs" exit 1 tolerado);
  G4 post (`omarchy-migrate --pending` vacío — exit 1 = sin pendientes es
  el "todo OK"; `pgrep quickshell` + `hyprctl version`, sddm vivo).
  **Abortar si**: cae NCM a mitad de transacción (re-lanzar `omarchy
  update`, que reanuda), OOM (MemTotal debe ser 7,2 GiB, no 1,6), o prompt
  de conflicto sin dueño (dejar pendiente, anotar).
- sddm / primer arranque (`§4`): ledger #609 sddm ya `enabled`;
  `omarchy-settings` aporta `etc/sddm.conf.d/{10-theme,10-wayland}.conf`;
  autologin `Session=omarchy` hecho a mano (DESKTOP-OMARCHY-REVISION §1,
  contenido no verificado); `omarchy-provision-owner` corre en tty1 ANTES
  de sddm y su `keyboard_form` + user/pass por `chpasswd` exigen **teclado
  USB físico** (sin OSK en tty1/greeter). Si el usuario `alarm` ya existe
  y el primer arranque gráfico ya ocurrió (#634), provision-owner
  probablemente ya consumió su marcador
  (`/var/lib/omarchy/provisioning/pending`); verificar antes de enchufar
  teclado: si el marcador no existe, no hace falta teclado.
  `provision-first-run` (login) instala hooks post-update y habilita user
  units; sus pasos fallidos reintentan al próximo login (no bloquean).
- Riesgos y pendientes (`§5`): deriva edge (`omarchy.db` local 11-oct trae
  `hyprland-0.56.2-5` vs staged `-4`; `omarchy-chromium{,-bin}-148` existe
  en edge/aarch64 — mitiga "chromium x86-only"; re-validar `pacman -Si`
  el día del update); `1784672586` instala `quickshell-git` desde edge
  (si rompe el shell, `1787399318` lo devuelve al empaquetado); sin red
  NCM no hay update (keyring `--recv-keys keys.openpgp.org`, `mise up`,
  yay); esta noche NO se pudo contrastar upstream (`omacom/omarchy` rama
  quattro) por falta de tiempo/web — la clasificación usa solo pkg staged
  + DBs locales (evidencia autocontenida).
- Evidencia: `F-plan-por-fases.md` F6 (~1140-1210) y F8 (~1340-1370);
  `docs/informes/A-port-omarchy-aarch64.md:63,85,143-144,214,226,233-234,258-259,437,
  455-457,500`; `docs/informes/C-hyprland-quickshell-aarch64.md:319`;
  `build/gates/revision/PIPELINE-PANEL-20261014/DESKTOP-OMARCHY-REVISION.md:1-76`;
  ledger `#609` (510 pkgs, sddm enabled), `#634` (escritorio en pie, 106
  pendientes), `#635-637`;
  `build/stage-escritorio/{omarchy-4.0.4-2,omarchy-settings-4.0.4-6,
  db-sync/sync/omarchy.db}`.
- Nota W2 §6g: «ledger #634/#635-637» NO localizados en el hermano
  (termina en #614) — localizar o corregir la ref (¿ledger propio?).

Artefactos: `build/gates/revision/RE-NOCTURNO-20261017/artifacts/omarchy/`
(`migrations-uke-lists.txt`, `omarchy-pkg-add-tolerant.sh`,
`omarchy-update-restart-uke.sh`, `seal-migrations-uke.sh`).

### 3.9 Carga / energía y slots (estado operativo)

- Auditoría de carga 16-oct
  (`build/gates/revision/CARGA-AUDITORIA-20261016.md`): veredicto **SÍ, CON
  CONDICIÓN** — stack completo, verificado en PC (módulos, firmware 56/56,
  servicio, loader endurecido) y probado en vivo en el MISMO rootfs
  (boot L71 `5e13addf…`: `Charging 1,098 A`), pero la tablet NO se recupera
  desde fastboot con USB de PC (no carga, descarga ~7 mV/min): condición =
  **cargador de pared ≥45 W, apagada, `off-mode-charge=1` (ya puesto),
  HORAS, hasta ≥3700 mV** + ritual anti-corrupción (adsp.b40 se corrompió
  2 veces en el rootfs).
- Procedimiento slots (`build/slot/PROCEDIMIENTO-SLOT.md`, estado
  27-sep-2026): vigilar solo lectura (`build/gates/uke-slot-check.sh
  linux|fastboot`; log en `build/slot/slot-log.tsv`); reset por
  `fastboot set_active a && fastboot set_active b` (devuelve retry a 7);
  herramienta `build/slot/qbootctl-aarch64` (build:
  `build-qbootctl-aarch64.sh); falta la decisión de marcar el arranque
  como bueno (`qbootctl`: `Successful: 0` = hemorragia de reintentos).
- Ledger esa noche: #651 resultado L73 (flash único, batería 3414 mV con
  excepción, ARRANCA); #652 resultado L74 (`boot_a` = `06a1d9fe`, SSH
  vivo); #653 + Resultado #653 (Android HyperOS slot b, adb root,
  4082 mV, BCB limpio) — ver §2.

## 4. Set de parches para el día D

Fuente: `build/gates/revision/RE-NOCTURNO-20261017/artifacts/parches/00-ESTADO.md`
(W4) + `.../FIXES-W3-20261017.md` + `.../FIXES-W4-20261017.md`.
Base verificada: `build/kernel-pokes/k52-L16-tree/` (solo lectura; pruebas en
copias `/tmp/opencode/w3-fix/`, `/tmp/opencode/w4-fix/`).

| # | Fichero en `artifacts/parches/` | Toca | Requisito |
|---|---|---|---|
| 10 | `10-touch-nt36532-base.patch` (sha `278757bb…4141`) | `pinctrl-cliffs.c` + `xiaomi-uke.dts` | Ninguno (árbol limpio). Copia byte-idéntica de `build/gates/revision/PIPELINE-PANEL-20261014/ports/0001-touch-nt36532.patch`. |
| 11 | `11-touch-dt-superres-pen-support.patch` (sha `30d85dd1…`) | `xiaomi-uke.dts` (nodo `&spi4/touchscreen@0`) | Después del 10. Convierte el delta no aplicable `delta-0002…` en parche máquina: `touchscreen-size 2136/3200 → 21360/32000` + `novatek,pen-support` + nota IRQ RISING. |
| 12 | `12-touch-mt-parser-thp-v2.patch` (sha `ab00084b…7ddd`) | `novatek-nt36xxx-spi.c` | Después del 10 (independiente del 11). Supersede a `superseded-12-touch-mt-parser-thp.patch` (sha `73d0590f…0a92`): pliega el delta THP-body — `NVT_THP_FRAME_LEN 0x1674` (5748), longitud dinámica `total=0x18+w3` (acepta 5176 y 5748, manda w3), `dump_thp` vuelca `F[0xCA..0xDA]` + w3 + gap1 (0x138A, solo si total=5748), postura «no decodificar dedos en kernel». |
| 13 | `13-touch-pen-m80p-p81c-v3.patch` (sha `076c7f85…86a5`) | `novatek-nt36xxx-spi.c` | **Después del 12v2** (reasentado sobre post-12v2). Supersede a `superseded-13-touch-pen-m80p-p81c-v2.patch` (sha `97831a5a…47`): suma el **hook de probe** (H4: crea `pen_m80p`/`pen_p81c` tras `touchscreen_parse_properties` si `pen_support`, + bit `0x120` solo en P81c). |
| 20 | `20-bt-wcn6750-fragment-v2.dtsi` (sha `7b69ea40…`) | — (no es parche; fragmento DT suelto) | Integrar vía fdtoverlay o en `xiaomi-uke.dts` el día D. Corrige `artifacts/bt/wcn6750-bt-fragment.dtsi` (bloque 0 descomentado + citas). Comprobado con dtc contra harness con stubs. |

Comando día D (tras `cd <árbol>`):

`for n in 10 11 12 13; do patch -p1 < <dir-parches>/$n-*.patch || exit 1; done`

(los `*.patch` aceptan el glob porque solo hay uno por número: los
`superseded-…` quedan fuera del glob a propósito). (`00-ESTADO.md`).

Convención de escala ÚNICA (cierra W2-1d): el ×10 vive **SOLO en el DT**
(parche 11: sizes `21360/32000`; `touchscreen_parse_properties` hace
`max=size-1` → `prop.max 21359/31999`, verificado en
`drivers/input/touchscreen.c:85-123` del árbol). El driver usa
`prop.max_x/max_y` **tal cual** (parche 13: `pen_max = data->prop.max_x/
max_y` SIN multiplicar; el borrador hacía `(prop.max_x+1)*10-1` = `213599`,
×100). (`00-ESTADO.md`, FIXES-W3 §2).

Resultado dry-run (W4: `patch --dry-run -p1 --verbose` + `git apply --check`,
17-oct-2026): **17/17 hunks OK en la línea declarada, 0 offsets, 0 fuzz,
0 fallos**; aplicación real secuencial rc=0 (estado final byte-idéntico al
árbol de trabajo):

- 10: H1 `pinctrl-cliffs.c:1568` OK; H1 `xiaomi-uke.dts:530`, H2 `:553` OK.
- 11: H1 `xiaomi-uke.dts:577` OK.
- 12v2: H1 `:9`, H2 `:31`, H3 `:88`, H4 `:137`, H5 `:165`, H6 `:351`,
  H7 `:473`, H8 `:568`, H9 `:738` OK (9/9).
- 13v3: H1 `:166` (struct + defines), H2 `:581` (helpers pen),
  H3 `:679` (gancho IRQ + nota), H4 `:932` (hook de probe) OK (4/4).
- BT v1 (fallo de referencia): `dtc` →
  `ERROR (phandle_references): ... Reference to non-existent node or label
  "vreg_s3e_2p4"`.
- BT v2: `dtc -O dtb` exit 0, solo warnings del harness; el .dtb trae
  `regulators-3/vreg_s3e_2p4`, `vreg_bt_asd`, `bluetooth`
  (`enable-gpios=<tlmm 156>`, `max-speed=0x30d400`=3200000).
  (`00-ESTADO.md`, FIXES-W4 §3).

Riesgos / qué falta compilar y probar el día D (`00-ESTADO.md` §Riesgos):

1. **Compilar el driver** (`CONFIG_TOUCHSCREEN_NOVATEK_NT36XXX_SPI`; con
   `W=1` comprobar `__set_bit(0x120)` y el `static bool` sin warnings) —
   fuera del encargo W3/W4. Luego `getevent -p`: ABS_X/Y 21359/31999 en
   ambos pens.
2. **Dedos sin decodificar en kernel** (postura W4): el 12v2 solo valida el
   frame THP en log (`thp_frame=1`, `dump_thp=1` vuelca mutual/w3/gap1);
   el day-test con **`thp-decode.py`** sigue pendiente, y el MT por frame
   crudo requiere el port del HAL (vía relay/debugfs, no diseñada aún).
3. **BT `vddasd` sin verificar eléctricamente**: fixed-regulator
   `vreg_bt_asd` 0.95V/200µA conservador; revisar contra esquema/ABL antes
   de hornear (alternativa: colgarlo de un rail existente). Además el
   fragmento v2 asume que los rails `vreg_{l7b,s3b,s1b,s2b}` existen en el
   DT destino con esos nombres.
4. **IRQ**: RISING confirmado (nota en el 11); no gastar un ciclo en FALLING
   salvo panel TM díscolo.
5. Si `evtest` muestra ejes permutados, intercambiar `size-x/size-y`
   (1 línea, 1 ciclo).
6. 12v2: 5748/511 = 11.25 → 12 tramos SPI (`nvt_spi_read` exige
   `len+1 ≤ 512`); otro w3 válido que quepa en el búfer se valida igual con
   `dev_info` una sola vez (`len_warned` estático). (FIXES-W4 §1).
7. Relay/debugfs para exponer el frame crudo: diseñado en comentario, no
   implementado (1 ciclo, tras el day-test). (FIXES-W4 §4.3).

## 5. Verificación y erratas

### 5.1 Qué verificó W2

Fuente: `build/gates/revision/RE-NOCTURNO-20261017/VERIFICACION-W2-20261017.md`
(2026-10-17 ~04:00 UTC; copias en `/tmp/opencode/w2-verify/`; repo y tablet
intactos; ADD2 aparecido a mitad: no auditado por W2 — lo auditó AUDIT-ADD2):

- 1a 0001-touch aplica: **PASS** (`git apply --check` + apply real en /tmp).
- 1b delta-0002: **FAIL (formato)** — no es parche máquina (cabeceras
  `--- 0001…`, sin `@@`); contenido OK (las 5 líneas `-` existen verbatim
  en el 0001).
- 1c pen-draft: **FAIL (formato) / contenido OK con offsets** — 3 cabeceras
  con cuentas mal (H1 +53/son 35, H2 +84/87, H3 +19/24; sin newline final);
  con cabeceras recalculadas (solo /tmp) aplica con offsets 8/5/3, fuzz 1
  en H3; contexto existe en árbol (`pen_support` l.100/683).
- 1d delta ↔ pen-draft: **FAIL (incompatibles tal cual)** — doble ×10
  (`pen_max=(prop.max_x+1)*10-1` da 21359/31999 solo con DTS sin escalar;
  con el delta daría 213599).
- 2a `parse_msbtfw.py` reproduce `fw-tables.txt`: **PASS** (byte-idéntico;
  mbn 109248 B sha `3efbd7fa…` ✓; PH2 termina exacto a EOF ✓).
- 2b riesgo [N] «walker no encadena»: **RESUELTO a favor (falsa alarma)** —
  con stride 12 (`struct tlv_type_nvm`, `btqca.h:134-140`) msnv12.bin
  encadena 63 tags hasta `end_idx==length==6202`; igual que
  apnv11/cmnv12/crnv21/hmtnv20 de linux-firmware local.
- 2c anatomía NVM en RE-BT §2: **FAIL (contenido)** — artefacto del stride
  erróneo (ver §5.3).
- 3a fragmento BT v1 compila: **FAIL (tal cual)** — bloque `&apps_rsc`
  dentro del comentario (l.14–28); `dtc`: `Reference to non-existent node
  vreg_s3e_2p4`; descomentado en /tmp: compila (solo warnings de stubs).
- 3b fragmento vs binding yaml + hci_qca.c: **PASS con notas** — 9 supplies
  == `qca_soc_data_wcn6750` (nombres y cargas
  5m/26m/126m/12.5m/102m/302m/257m/1700m/200µ idénticos); required del
  binding cubiertos; cero props inválidas; GPIOs 156/80/35+mpm80
  confirmados en dump vendor (`0x16b 0x9c/0x50/0x23`) ✓; uart10:1344 +
  pinctrl 40/41/42/43 qup1_se2 ✓; ventanas xiaomi-uke.dts ✓; k37.config
  BT ✓.
- 3c «swctrl obligatorio / sin enable→pwrseq» (RE-BT §3): **FAIL (inexacto
  ×2)** — `devm_gpiod_get_optional` + solo `IS_ERR` aborta (2492-2500):
  ausente=NULL se tolera; sin `enable-gpios`, wcn6750 pone
  `power_ctrl_enabled=false`; `pwrseq "bluetooth"` solo existe en brazos
  QCA6390/default (2455/2512). Cita «lamma-qrd.dts:397 vreg_s3e_2p4
  1.6-2.4V ✓» falsa: lamma:414-418 trae **3.008-3.96V** (los 1.6-2.4V del
  fragmento son del vendor, bien, pero no de lamma).
- 4 payload WiFi v2: **PASS todo** — `sha256sum -c` OK; 80 entradas (v1 81,
  único diff: fuera `amss.bin`); board.bin=`da424c03…` ✓ (==
  `board-o82gl-data58180.bin`); regdb=`fca5bbfa…` ✓; sin amss ✓;
  `preparar-wifi-payload.sh` sin modificar (git limpio) ✓. Citas ath11k ✓
  (`hw.h:74-82` exactas, `core.c:582/630` bloque wcn6750, `mhi.c:357`,
  `qmi.c:2438-44/2600`, regdb no fatal §2987, poke UKE 2483).
- 5 scripts omarchy (`bash -n` + lógica): **PASS con notas** — los 3 parsean
  OK; sin rutas peligrosas (solo pacman/marcadores en $HOME). Mecánica del
  problema verificada contra el tarball staged: `pkg-add:10-12,18`
  (`|| exit 1` + `pacman -Q`) ✓; bucle `vmlinuz` de `update-restart:12-25`
  idéntico al citado (bug real sin vmlinuz) ✓. Notas: `seal --dry-run`
  hace `mkdir -p $STATE_DIR` (efecto menor); `--verify` usa `ls *.sh` sin
  guarda (inocuo); `3<&-` sin justificar.
- 6a RE-TOUCH (3 afirmaciones): **PASS + 2 citas FAIL menor** — .ko
  1063304/308600 B ✓; driver 657 lín + `EVENT_BUF 0x125800` en l.60 ✓;
  `0x2001`=ONESHOT+RISING ✓ (cosecha 13352 lín, `int_trigger_type=1` en
  probe:5351 ✓; `54 Edge xiaomi_tp` ✓); superres ×10 ✓ (getevent
  21359/31999, dmesg 5530-37). Citas mal: irq-raw está en
  `dt-novatek-node.txt:6`, no :5; getevent en `live-verify.txt:~55-60`,
  no :31-38.
- 6b RE-STYLUS (3 afirmaciones): **PASS + 1 NOTA** — FWs 245760 B + `NVT`
  en EOF-3 + tags `11ee/916e` suma 0xFF + md5: byte-verificado ✓. Ejes
  §1.2 == `getevent -p` exactos (M80p 21359/31999/8191/tilt±60/
  008f-0140-014a; P81c +BRAKE360/16383/0120) ✓✓. decomp/ 32 .c ✓,
  `0x1c`=BUS_SPI ✓. NOTA: decomp-full trae **230 .c** en disco vs
  «233/233» (el log Ghidra dice written=233): conciliar 3.
- 6c RE-BT (3 afirmaciones): **PASS salvo §2/§3 (ver 2c/3c)** — btpower sha
  `fdbc8e3a…` + modinfo (desc/vermagic/depends) ✓; 8 compatibles en
  strings ✓; decomp 47 .c ✓; hci_qca.c 2841 lín ✓;
  `msbtfw12.mbn` vía `qca/msbtfw%02x.mbn` (~btqca.c:829-834) ✓;
  `qca_soc_data_wcn6750` 2171-2186 ✓; config BT ✓.
- 6d RE-AUDIO + ADD1 (3 afirmaciones): **PASS** — fs19xx modinfo
  v4.0.7/depends/`foursemi:fs16xx` ✓; `fs19xx.fsm` 4828 B +
  `00 01 onlybsg 00 1` ✓; tinymix 310 lín + idle
  Scene0/Vol255/StopOn/AMP_OFF ✓; decomp 127 .c ✓ (+`fsm_i2c_probe.c`
  existe); `fs19xx_smartpa@{34-37}` en `i2c@88c000` ✓;
  `CHIPID_WCD9390=0x0/9395=0x5` ✓; gap fs210x (solo 2104/2105S) ✓;
  `cliffs-mtp-snd-card` en DT+proc-asound ✓ (no en strings del .ko: solo
  fuente DT/vivo).
- 6e RE-WIFI (3 afirmaciones): **PASS** — `.data` en offset 0x400 tamaño
  0xE344=58180 ✓; `cmp` o82 vs o82gl = **159 B exactos** ✓; amss
  v1=`c42e06f5…` ✓; `bdwlan.b01` difiere en byte 11 (0x49 vs 0x26) ✓;
  trío regdb documentado sin contradicción (237fc6 kiwi-pull ≠ fca5bbfa
  bueno en v2) ✓.
- 6f RE-FOLIO (3 afirmaciones): **PASS + 1 FAIL menor** — nanosic 358128 B
  md5 `b97ec7f5…` ✓; HID 61/56/277/25 B + 4 shas exactos ✓; sensorservice
  1370 lín + «Total 53 h/w sensors» literal ✓; lsm6dso en `st_lsm6dsx.h` ✓;
  qmc63/stk3b/sip1328/sx937/see vacíos ✓; hall DT + keyboard 69176 B
  («69 KB») ✓. FAIL: decomp-keyboard trae **36 .c** (todos no triviales),
  no «31» (hall 14 ✓).
- 6g ATAQUE-OMARCHY (3 afirmaciones): **PASS + 1 NOTA** — cadena update
  (free-space→prune→snapshot→dev→keyring→system-pkgs→migrate→aur→mise→
  restart) ✓ en tarball; `migrate` con `set -euo` + `bash -euo
  pipefail`+touch (aborto en 1er fallo real) ✓; 106 migraciones + 106
  semillas ✓; killer 1781984677 (`needs_repair`→snapper.sh sin snapper) ✓;
  «106 pendientes» corroborado por NOTAS-OMARCHY:4827 ✓. NOTA: «ledger
  #634/#635-637» NO localizados (hermano termina en #614); A:63/128
  coherente con la nota de deriva ✓.
- 7 crudos + repo intacto: **PASS** — todos los .ko citados existen con los
  tamaños citados; `git status --porcelain | grep -v '^??'` vacío
  (19 untracked, 0 tracked modificados).

Acciones correctivas W2 (§2, ordenadas): **(1)** BT §2: reescribir anatomía
NVM con stride 12 y cerrar el [N] como resuelto; **(2)** parches: regenerar
pen-draft con cabeceras correctas + decidir escala única (DTS escalado +
quitar `*10` del driver); convertir el delta en parche aplicable;
**(3)** fragmento BT: descomentar bloque 0, corregir citas
(swctrl/pwrseq/lamma 3.0-3.96V), marcar `vddasd` [N] como bloqueante de
horneado; **(4)** citas menores (touch `:5`→`:6`, `:31-38`→`:~55-60`,
folio «31»→36 .c, stylus 233 vs 230 .c); **(5)** omarchy: localizar ref
«ledger #634»; `seal --dry-run` sin `mkdir`.

Resumen W2 (§3): de 7 frentes, WiFi-v2, audio, stylus-ejes/FW,
folio-sensores y mecánica omarchy PASS; el «riesgo» NVM queda RESUELTO
(63 tags, end==length); 0001 aplica limpio; delta y pen-draft NO aplican
tal cual (formato) y son incompatibles entre sí (doble ×10); fragmento BT
no compila tal cual (con el bloque activo sí); payload WiFi v2 impecable;
scripts omarchy sanos; repo intacto (0 tracked modificados); ADD2 no
auditado por W2.

### 5.2 Qué reparó W3/W4

- W3 (FIXES-W3 §1): **(1)** `delta-0002` no es parche máquina (sin `@@`,
  sin rutas `a/ b/`); **(2)** pen-draft con 3 cabeceras mal
  (reproducido `patch: **** malformed patch at line 39`); **(3)** doble
  ×10 (delta escala el DT y el borrador multiplica de nuevo → `213599`);
  **(4)** `delta-mt-parser.patch` sano (el `-p4` de W2 era por lanzar
  `patch` desde `drivers/input/touchscreen/`); **(5)** fragmento BT v1 con
  bloque `&apps_rsc` dentro de un comentario + 2 citas inexactas. (FIXES-W3).
- W3 (FIXES-W3 §2): convención única ×10 SOLO en el DT (`11`: sizes
  `21360/32000`); **11** convertido en parche `-p1` real (1 hunk,
  `xiaomi-uke.dts:577`, generado por edición real + `diff -u`);
  **13** rehecho (3 hunks por `diff -u`; elimina `NVT_PEN_XY_SCALE`,
  `pen_max = data->prop.max`, derivación `(2135+1)*10-1` en comentarios);
  **10/12** copias byte-idénticas (shas `278757bb…`, `73d0590f…`);
  **20** bloque 0 activo, lamma 3.008–3.96 V, swctrl `optional`,
  `vddasd` con aviso eléctrico. (FIXES-W3).
- W3 orden (FIXES-W3 §3): `10` → `11` (tras 10) → `12` (tras 10,
  independiente del 11) → `13` (**tras 12**); `20` no se parchea (vía
  fdtoverlay/DT). Comando:
  `for n in 10 11 12 13; do patch -p1 < $P/$n-*.patch || exit 1; done`.
- W3 dry-run (FIXES-W3 §4): **15/15 OK en línea declarada, 0
  offsets/fuzz/fallos**; BT v1 → `ERROR (phandle_references)` (referencia);
  v2 → exit 0 (harness con stubs, cpp + `dtc -O dtb`, DTC v1.8.1; .dtb con
  `regulators-3`, `vreg_bt_asd`, `bluetooth`).
- W4 (FIXES-W4 §1): nuevo `12-touch-mt-parser-thp-v2.patch` (sha
  `ab00084b…7ddd`, 9 hunks) que supersede al `12`: `NVT_THP_FRAME_LEN`
  0x1438 → **0x1674** (5748 B; bucle SPI por tramos de 511 B: 5748/511 =
  11.25 → 12 tramos); validación dinámica `total = 0x18 + w3` (manda w3;
  acepta 5176 y 5748; otro w3 válido avisa una vez con `len_warned`
  estático); `dump_thp` vuelca `F[0xCA..0xCA+16]` + w3 + total + gap1
  `F[0x138A..0x139A]` solo si total==5748; defines `NVT_THP_MUTUAL_OFF`,
  `NVT_THP_GAP1_OFF`, `NVT_THP_W3_LIVE` (5724 = 0x165C, PREDICHO);
  postura explícita **el kernel NO decodifica dedos**.
- W4 (FIXES-W4 §2): nuevo `13-touch-pen-m80p-p81c-v3.patch` (sha
  `076c7f85…86a5`, 4 hunks) que supersede al `13v2`: H1–H3 = v2 verbatim;
  **H4 nuevo** en `nvt_spi_probe()` tras el chequeo de tamaño (hereda
  `prop.max` superres sin ×10): crea M80p (`input/pen`, 8191, sin twist)
  y P81c (`input/pen_p81c`, 16383, con `ABS_BRAKE`), `return
  dev_err_probe` si `IS_ERR`, `__set_bit(0x120, pen_p81c->keybit)`.
  Limpio sin forzar: `nvt_spi_pen_create` definida antes del probe
  (~623 < ~931); `IS_ERR` idiomático (5 drivers hermanos); `0x120 = 288 <
  KEY_MAX`; `keybit[4]|=0x100000000` (ko 0x6874) = bit 32 de la palabra 4
  = key 288 = 0x120; balance `{}`/`()`/`[]` = 0/0/0 (code-only), termina
  en `\n`. Con el hook, `pen_create/click/release` quedan usadas.
- W4 dry-run (FIXES-W4 §3): copia fresca, secuencial:
  10 rc=0; 11 H1 ok en 577; 12v2 H1:9 H2:31 H3:88 H4:137 H5:165 H6:351
  H7:473 H8:568 H9:738 (9/9); 13v3 H1:166 H2:581 H3:679 H4:932 (4/4).
  **17/17 hunks, 0 offsets, 0 fuzz, 0 FAILED**; aplicación real rc=0 y
  estado final byte-idéntico (`diff` vacío); `git apply --check -p1` OK
  en los 4. Nota: el 13v2 viejo aplicaba sobre 12v2 con offsets 15/37/37
  — por eso se reasentó en 13v3.
- W3/W4 límite honesto: sin compilación ni HW, la corrección es sintáctica
  (dry-run/dtc) + aritmética, no funcional. (FIXES-W3 §5; FIXES-W4 §4).

### 5.3 Spot-check REA + erratas que este documento NO propaga

- Spot-check externo con REA (README §Reproducir):
  `nvt_ts_work_func`@**0x15e06c** — 25 callees, **cero** `input_event`.
  Confirma de forma independiente el diseño MT (el kernel no reporta
  dedos). HECHO.
- Errata ADD2 idx25 (AUDIT §2.1): este documento da `0x484A/0x4042`
  (NO `0x48CA/0x4072`). Ver §3.5.
- Errata BT §2/§3 (W2 §2c/§3c): este documento describe el NVM con stride
  12 (BD_ADDR datos `ad5a…` @0x5c, blob @0x62) y swctrl opcional + lamma
  3.008–3.96 V (NO la anatomía stride-4 ni «swctrl obligatorio» ni lamma
  1.6–2.4 V). Ver §3.4.
- Corrección tamaño de frame (BODY §3): este documento da **5748 B /
  w3=5724 predicho** (NO 5176/w3=5152 como tamaño de frame; el 0x1438 del
  vendor queda citado solo como `memcpy` fijo del .ko). Ver §3.3.
- Citas menores aplicadas: `dt-novatek-node.txt:6` (no :5); decomp-keyboard
- Citas menores aplicadas: `dt-novatek-node.txt:6` (no :5); decomp-keyboard
  36 .c (no 31); decomp-full 230 .c en disco vs 233 written (conciliar 3).
  (W2 §1b–1d, §6a/6b/6f).

## 6. Deudas cerradas esa noche

- GAP-1 (`charge/uke-charge-run.sh`): el script no copiaba `adsp-fw.sha256`
  al manifest en el PC — aplicado (copia a `/lib/firmware/`).
  (NOTAS-OMARCHY.md entrada 17-oct; docs/historia/ESTADO-VIVO.md capa 17-oct.)
- Fila Resultado #653 del ledger: el pre-registro #653 quedó sin fila de
  resultado — añadida desde la sesión RE nocturna con evidencia adb en
  vivo (Android arranca en slot b, 4082 mV, BCB limpio; nota de lectura
  #653-con-#652). Ledger dirty por la otra sesión: NO commitear desde
  aquí. (`~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md`.)
- Refutación del gate `modinfo`: la recomendación §1 de
  `CARGA-AUDITORIA-20261016` (cambiar el gate a
  `strings | grep -qx "vermagic=$REL …"` porque `modinfo` del host da
  vermagic vacío sobre .ko aarch64) no aplica — refutación local de la
  noche: `modinfo` SÍ lee vermagic de `.ko` aarch64; gate intacto.
  (NOTAS-OMARCHY.md entrada 17-oct.)

## 7. Pendiente por bloques

### (a) Requiere tablet / hardware

- Compilar el driver táctil + aplicar el set 10/11/12v2/13v3 el día D
  (ver §4, riesgos 1–7).
- Day-tests: `thp_frame=1 dump_thp=1` + `thp-decode.py` (w3=5724 si el ini
  vivo manda); evtest 1 dedo + esquinas (`point_layout`, escala ×10,
  posible permuta de ejes); `getevent -p` de ambos pens (21359/31999).
- DEVID fs19xx real (gate reformulado: sin `/dev/i2c-*`; vías: printk en
  arranque en frío con doble captura, ioctl `/dev/fsm_misc`, o kernel con
  `i2c-dev`). (AUDIT §4).
- Payload WiFi v2 en tablet (`tar xzf ... -C / && depmod -a`) + gate §3.6
  (`using board api 1`, `bdf_type 0`, `fetched regdb`, `wlan0`, `iw scan`,
  SSH uptime > 300 s); kernel del test con el poke caldata de `qmi.c`.
- Gate v3: pull de los 13 `wpss.b*` del vendor + swap del SET COMPLETO si el
  wpss v1 no levanta. (RE-WIFI §6).
- `qbootctl` en tablet (marcar arranque bueno; hemorragia de reintentos —
  falta la decisión del dueño). (`build/slot/PROCEDIMIENTO-SLOT.md`).
- Backup del par L74+s288 antes de cualquier experimento (sha pre-registrado
  en el ledger ANTES de flashear; verificación por sha256 de lectura vuelta
  al tamaño exacto de la imagen).
- Polaridad hall para gpio-keys (evtest); protocolo I2C Nanosic a nivel
  byte; `report_coordinate`; origen del log `Xiaomi stylus m80p/p81c`
  (requiere lápiz conectado); offsets versión/pid en el .bin CSOT.

### (b) Decisiones / otra sesión

- Panel/L75: de la otra sesión (alcance excluido aquí por diseño).
- Commit del ledger hermano: la fila Resultado #653 se añadió con el ledger
  dirty por la otra sesión — NO commitear desde aquí.
- H/I pendientes (restauración y lápiz operativo) y F6–F8: usan estos
  hallazgos pero los decide/ejecuta el dueño (ver ATAQUE §3–§5).
- ACUMULADO diferido: el árbol `k52-L16-tree` ya lleva ediciones **L75-prep**
  de la otra sesión (`dsi_phy_7nm.c` tocado 03:0x) — regenerar cuando cierre
  el ciclo L75, o el diff capturará estado en vuelo.
  (`NOTAS-OMARCHY.md` entrada 17-oct; commit `768db63` lo precisa.)
- Refresco de `ESTADO-VIVO`/`INDICE` (los toca también la otra sesión).
- Refs «ledger #634/#635-637» del ATAQUE: localizar o corregir (¿ledger
  propio?). (W2 §6g).
- Contraste upstream `omacom/omarchy` rama quattro (clasificación con pkg
  staged + DBs locales solamente). (ATAQUE §5).

### (c) Abierto por diseño (puertos grandes, detrás de táctil/BT/pantalla)

- Detector de dedos del HAL (Kalman, jitter, palm, game-mode): port a
  userspace con frame crudo por relay/debugfs (1 ciclo tras el day-test;
  diseñado en comentario, no implementado). (FIXES-W4 §4.3; 00-ESTADO
  riesgo 2).
- Port SSC-ADSP (sensores: SEE/QMI; 4 de 5 físicos sin driver; buses/IRQ/
  supplies inexistentes en el DT del AP). (RE-FOLIO §3).
- Driver fs19xx real (`fs19xx.c` mínimo o extender `fs-amp-lib`; TODO-1..7
  del skeleton; TODO-1 cubierto por `fs19xx-presets.h`).
- Machine pineapple+wcd939x+FS (3 links TDM-VA + BEs q6apm + auxiliares
  wcd939x; plantilla `sc8280xp.c`-estilo). (ADD2 §5).
- UCM/tplg: inexistente en vendor (grafo dentro de `adsp.bNN`); gate = PCM
  capture por VA-TX con UCM mínimo. (ADD2 §4).
- WCD939x RX/headset al final (música por altavoz no lo necesita).
  (informe base §6).
- Escenas pares 8/10/12/14 sin uso conocido (no cablear en UCM hasta medir);
  `words[3..5]` del PLL; `dai_ops` con layout 7.2. (ADD2 §5; AUDIT §5).
- `touch_report_debug` (986.752 B, NO examinado — podría traer parser con
  más símbolos). (BODY §7).
- `bt_fm_slim.ko` ilocalizable (si existe en otra partición, re-chequear
  FM/BT). (RE-BT §Riesgos).
- Baud operativo BT 3.2M vs 3M (quitar `max-speed` si inestable). (RE-BT).

## 8. Artefactos y commits + reproducir el RE

### 8.1 Rutas clave

| Ruta (desde la raíz del repo) | Qué es |
|---|---|
| `build/gates/revision/RE-NOCTURNO-20261017/README.md` | Índice de la noche (orden de lectura, artefactos, reproducir en 2 min) |
| `build/gates/revision/RE-NOCTURNO-20261017/RE-TOUCH-NT36532.md` | Táctil vendor vs mainline |
| `build/gates/revision/RE-NOCTURNO-20261017/RE-STYLUS-FW-CSOT.md` | Lápiz + FW CSOT |
| `build/gates/revision/RE-NOCTURNO-20261017/RE-TOUCH-MT-LAYOUT.md` | MT/HAL + framing THP |
| `build/gates/revision/RE-NOCTURNO-20261017/RE-TOUCH-THP-BODY.md` | Cuerpo THP 5748 B + fin del mito del punto crudo |
| `build/gates/revision/RE-NOCTURNO-20261017/RE-BT-WCN6750.md` | BT btpower + FW + plan mainline |
| `build/gates/revision/RE-NOCTURNO-20261017/RE-AUDIO-WCD939X-FS19XX.md` | Audio base |
| `build/gates/revision/RE-NOCTURNO-20261017/RE-AUDIO-WCD939X-FS19XX-ADD1-DECOMP.md` | ADD1 decomp fs19xx |
| `build/gates/revision/RE-NOCTURNO-20261017/RE-AUDIO-WCD939X-FS19XX-ADD2-FSM-DRIVER.md` | ADD2 blob/secuencias/DAI |
| `build/gates/revision/RE-NOCTURNO-20261017/AUDIT-ADD2-20261017.md` | Auditoría ADD2 + tablas C |
| `build/gates/revision/RE-NOCTURNO-20261017/RE-WIFI-BDF.md` | WiFi BDF + payload v2 |
| `build/gates/revision/RE-NOCTURNO-20261017/RE-FOLIO-SENSORES.md` | Folio/hall/sensores |
| `build/gates/revision/RE-NOCTURNO-20261017/ATAQUE-OMARCHY-OFFLINE.md` | Omarchy offline |
| `build/gates/revision/RE-NOCTURNO-20261017/FIXES-W3-20261017.md` | Reparación parches + orden + dry-run 15/15 |
| `build/gates/revision/RE-NOCTURNO-20261017/FIXES-W4-20261017.md` | Pliegue THP-body + hook pen + dry-run 17/17 |
| `build/gates/revision/RE-NOCTURNO-20261017/VERIFICACION-W2-20261017.md` | Verificación mecánica W2 |
| `build/gates/revision/RE-NOCTURNO-20261017/artifacts/parches/` | Set día D: `00-ESTADO.md`, `10/11/12v2/13v3`, `20-v2.dtsi`, `superseded-…` |
| `build/gates/revision/RE-NOCTURNO-20261017/artifacts/touch/mt-layout/thp-decode.py` | Decodificador THP (+9 autotests OK) |
| `build/gates/revision/RE-NOCTURNO-20261017/artifacts/touch/mt-layout/frame-scan.py` | Validador layout (auto-test OK/FAIL sintético) |
| `build/gates/revision/RE-NOCTURNO-20261017/artifacts/bt/parse_msbtfw.py` | Parser fw BT → `fw-tables.txt` |
| `build/gates/revision/RE-NOCTURNO-20261017/artifacts/audio/fs19xx-presets.h` | Tablas C del blob (807 l., 651/651) |
| `build/gates/revision/RE-NOCTURNO-20261017/artifacts/audio/fsm-blob-parser.py` | Parser blob (re-verifica CRC) |
| `build/gates/revision/RE-NOCTURNO-20261017/artifacts/audio/fsm-blob-emit-c.py` | Emisor del header C |
| `build/gates/revision/RE-NOCTURNO-20261017/artifacts/audio/fs19xx-pll-table.txt` | Tabla PLL 11×(A1,A2,A3) |
| `build/gates/revision/RE-NOCTURNO-20261017/artifacts/audio/fs19xx-mainline-skeleton.c` | Esqueleto driver (TODO-1..7) |
| `build/gates/revision/RE-NOCTURNO-20261017/artifacts/audio/dts-fs19xx-add2.dtsi` | DTS audio ADD2 |
| `build/gates/revision/RE-NOCTURNO-20261017/artifacts/folio-sensores/dts-nanosic-folio.dtsi` | DTS folio (borrador) |
| `build/gates/revision/RE-NOCTURNO-20261017/artifacts/folio-sensores/dts-xiaomi-hall.dtsi` | DTS hall A+B (borrador) |
| `build/gates/revision/RE-NOCTURNO-20261017/artifacts/omarchy/` | Listas + 3 wrappers borrador |
| `build/pkg/uke-wifi-payload-v2.tar.gz` + `.sha256` | Payload WiFi v2 (sha `2b0dd75a…`) |
| `build/android/vendor-modules-20261017/00-listing.txt` | Censo de los 320 módulos vendor |
| Decompilados Ghidra (`artifacts/**/decomp*`) | Derivados; **fuera de git** |
| Blobs grandes (`artifacts/wifi/amss-kiwi-tabletProbe.bin`, 7,2 MB) | Fuera de git; shas en los informes |

### 8.2 Commits de la noche (este repo)

- `742a24a` — RE nocturno 17-oct (12 subagentes, todo lo no-panel) + GAP-1 +
  ESTADO-VIVO/NOTAS + fila #653 al ledger (hermano, sin commitear: dirty por
  la otra sesión).
- `768db63` — NOTAS: precisión del pendiente ACUMULADO (diferido: el árbol
  lleva L75-prep de la otra sesión).
- `e863d1a` — Cierre W4 del set táctil (12v2 + 13v3; dry-run cadena 17/17;
  00-ESTADO + FIXES-W4; ESTADO-VIVO/NOTAS al día).

### 8.3 Reproducir el RE (tal como está en el README)

```bash
# 1) módulos vendor desde la tablet (solo lectura)
mkdir -p build/android/vendor-modules-20261017
for m in nt36532_touch xiaomi_touch btpower fs19xx_dlkm machine_dlkm wcd939x_dlkm \
         wcd939x_slave_dlkm wcd9xxx_dlkm wcd_core_dlkm xiaomi_keyboard_driver \
         xiaomi_hall wlan_firmware_service xiaomi_wifi_gpio; do
  adb -s 192.0.2.13:5555 exec-out "su -c 'cat /vendor/lib/modules/$m.ko'" \
    > build/android/vendor-modules-20261017/$m.ko
done
# 2) decompilar (Ghidra serializado; JAVA_HOME=java-27-openjdk)
flock /tmp/opencode/ghidra.lock ~/tools/ghidra_12.1.4_PUBLIC/support/analyzeHeadless \
  ~/ghidra-projects uke-night -import build/android/vendor-modules-20261017/nt36532_touch.ko \
  -processor AARCH64:LE:64:v8A -overwrite -scriptPath build/tools/ghidra \
  -postScript ExportAllDecompiled.java /tmp/opencode/decomp
```

(`build/gates/revision/RE-NOCTURNO-20261017/README.md` §Reproducir;
`build/android/vendor-modules-20261017/00-listing.txt` guarda el censo de
los 320 módulos vendor.)

---

*Fin del consolidado. Fuentes primarias: los 15 .md de
`build/gates/revision/RE-NOCTURNO-20261017/` + `artifacts/parches/00-ESTADO.md`
+ `docs/historia/ESTADO-VIVO.md` (capa 17-oct) + `NOTAS-OMARCHY.md` (entrada 17-oct) +
`build/gates/revision/CARGA-AUDITORIA-20261016.md` +
`build/slot/PROCEDIMIENTO-SLOT.md` + filas #651/#652/#653 (+Resultado) de
`~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md` +
`build/gates/revision/PIPELINE-PANEL-20261014/DESKTOP-OMARCHY-REVISION.md`.
`wc -l` y `file` ejecutados sobre este MD según la regla del proyecto;
10 referencias comprobadas al azar (ver resumen final de la sesión).*
