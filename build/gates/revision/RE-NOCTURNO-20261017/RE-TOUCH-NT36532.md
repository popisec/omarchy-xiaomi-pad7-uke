# RE-TOUCH-NT36532 — vendor nt36532_touch.ko vs driver mainline (17-oct-2026, solo lectura)

> **NOTA (misma noche):** los tamaños de frame/THP citados aquí quedan precisados en
> `RE-TOUCH-MT-LAYOUT.md` y `RE-TOUCH-THP-BODY.md` (frame mmap = **5748 B**; `0x1438` es el
> buffer del notifier kernel, no el tamaño de frame).

Alcance: RE del driver vendor de táctil (lado táctil; el panel solo se cita como vecino).
Prohibiciones nocturnas respetadas: ningún fichero existente editado, sin builds/flash,
sin escrituras en la tablet, sin /dev/ttyACM0.

## 0. Material y huellas

- Vendor: `build/android/vendor-modules-20261017/nt36532_touch.ko` (1.063.304 B, con
  símbolos: `llvm-objdump -t`), `xiaomi_touch.ko` (308.600 B).
- Decomp previo reusado: `build/vendor-re/decomp-touch/` (≈180 funciones en C).
- DT vendor vivo: `build/android/dt-full-uke-android/base/soc/qcom,qupv3_0_geni_se@ac0000/spi@a90000/novatek@0/`.
- Cosecha: `build/android/cosecha-20261017/01-dmesg.txt` (boot Android de hoy).
- Nuestro driver: `build/kernel-pokes/k52-L16-tree/drivers/input/touchscreen/novatek-nt36xxx-spi.c`
  (657 lín) + upstream `novatek-nvt-ts.c`; parche `PIPELINE-PANEL-20261014/ports/0001-touch-nt36532.patch`.
- Artefactos nuevos (solo lectura, byte-exactos): `artifacts/touch/driver/`
  (`dmesg-touch-excerpt.txt`, `symtab-touch.txt`, `dt-novatek-node.txt`,
  `live-verify.txt`, `delta-0002-touch-superres-pen.patch`).

## 1. Probe / DT / GPIO / pinctrl / SPI / reset / chip-id / LCD (pregunta 1)

- Compatible: `novatek,NVT-ts-spi` [HECHO: `dt-novatek-node.txt:2`, dmesg
  "SPI driver NVT-ts has no spi_device_id for novatek,NVT-ts-spi"].
- `nvt_parse_dt` @ .text 0x7838; `nvt_pinctrl_init` @ 0x7fd0; `nvt_gpio_config` @ 0x8278;
  `nvt_ts_probe` @ 0x554c (ver `symtab-touch.txt`).
- `novatek,irq-gpio` = phandle 0x16b (tlmm), gpio **54**, flags **0x2001** [HECHO:
  `dt-novatek-node.txt:5`, raw `00 00 01 6b 00 00 00 36 00 00 20 01`; dmesg
  `nvt_parse_dt 2381: novatek,irq-gpio=387` — 387 es el nº GPIO Linux, 54 el pin TLMM].
- **0x2001 = IRQF_ONESHOT (0x2000) + EDGE_RISING (1)** [HECHO, triple evidencia]:
  (a) probe hace `request_threaded_irq(…, *flags | 0x2000, …)` (`nvt_ts_probe.c:491-492`,
  `nvt_touch_doze_analysis.c:117-118`); (b) dmesg vivo `nvt_ts_probe 5351:
  int_trigger_type=1` (1 = `IRQ_TYPE_EDGE_RISING`); (c) `/proc/interrupts` vivo:
  `359: … msmgpio 54 Edge xiaomi_tp` con contadores >0 (IRQ viva, flanco).
  La alternativa FALLING del parche 0001 puede retirarse.
- IRQ Linux nº **359** (`request irq 359 succeed`, dmesg), vía `gpio_to_irq(387)`.
- SPI: `reg=<0>` (CS0), `spi-max-frequency` raw `01 24 f8 00` = **19.200.000 Hz** [HECHO],
  sin props `spi-cpol/cpha` en el nodo ⇒ **SPI_MODE_0, 8 bits** [INFERIDO, estándar del core SPI].
- Reset/power: **sin reset-gpio ni supplies** en el nodo vendor [HECHO: `ls` del nodo en
  `dt-novatek-node.txt` — solo irq-gpio, lcd_id-gpio, pen-support, stylus-resol-double,
  mp-support-dt, game-config1..3, arrays mi_tp]. TDDI: el FW del touch vive con el panel.
  El reset es por comando (`nvt_eng_reset` @ 0x3164, `nvt_bootloader_reset` @ 0x320c,
  `nvt_sw_reset` @ 0x319c, `nvt_sw_reset_idle` @ 0x31d4).
- `novatek,pen-support` (booleano, size 0), `novatek,stylus-resol-double` (booleano),
  `novatek,mp-support-dt` (booleano) [HECHO]; `novatek,spi-rd-fast-addr` **ausente**
  (dmesg: "not support novatek,spi-rd-fast-addr"); `novatek,lcd_id-gpio` = tlmm pin 0x1a=26
  (nº Linux 359), valor **lcd_id=1 ⇒ panel CSOT** [HECHO dmesg `nvt_parse_dt 2394`].
  FW aplicable: `novatek_nt36532_o82_fw_csot.bin` (+`_mp_csot.bin`), 245.760 B en `/odm/firmware`
  [HECHO vivo]; existe variante `_tm` (no es este panel).
- pinctrl: estados `pmx_ts_active`/`pmx_ts_suspend` (`pinctrl-names`), seleccionados con
  `pinctrl_select_state` en probe/suspend [HECHO: strings `pinctrl_lookup_state`,
  `pinctrl_state_active/suspend`; `nvt_pinctrl_init.c`]. Sin pinctrl ⇒ el driver sigue
  (solo log "Target does not use pinctrl") — el parche 0001 no añade pinctrl: correcto.
- Chip-id: trim `chip_ver_trim_addr=0x1fb104, swrst_sif_addr=0x1fb43e, crc_err_flag_addr=0x1fb535`;
  lectura `buf=0x0E 00 04 32 65 03`, "This is NVT touch IC", **"Cascade Chip"**
  [HECHO dmesg 3352-3424]; `NT36532_single_memory_map` @ .rodata 0x9e00, primer u32 LE
  `00 58 12 00` = **EVENT_BUF 0x125800** [HECHO: coincide con `novatek-nt36xxx-spi.c:60`].
  FW: `fw_ver 0x0E, fw_type 0x01, pid 0x5981`; driver `nvt_version_2024.01.13-001`;
  xiaomi-touch `2024.09.02-01`; lockdown `53 42 32 91 4f 81 32 ff`; geometría
  **rx=40, tx=60, x=2136, y=3200, super_resolution_factor=10** [HECHO dmesg 5530-5537].

## 2. Cadena de arranque (pregunta 2)

Orden en `nvt_ts_probe` (`nvt_ts_probe.c`, dmesg 5018-5596) [HECHO]:
1. `spi controller thread prio 99` → `nvt_parse_dt` (gpio 387, pen=1, dbl=1, lcd gpio 359,
   lcd_id=1 CSOT, game-config1 `[2,2,1,2,1]` / config2 `[2,2,2,2,1]` / config3 `[2,2,3,2,1]`).
2. `nvt_pinctrl_init` → estado active; `nvt_gpio_config` (solo irq-gpio; reset por comando).
3. `nvt_eng_reset()` @ 0x3164 → `nvt_ts_check_chip_ver_trim_loop()` @ 0x8370
   (5 intentos × 3 addrs trim; deja `EVENT_BUF=0x125800`, `max fingers=10`).
4. Crea 3 input devices: `NVTCapacitiveTouchScreen` + `NVTCapacitivePenM80p` +
   `NVTCapacitivePenP81c` (solo si pen-support) [HECHO dmesg + `dumpsys input` vivo:
   event11/12/13].
5. `gpio_to_irq(387)=359` → `request_threaded_irq(flags|0x2000)` → `nvt_irq_enable`
   (empieza **disabled**, `enable=0 depth=1`; se habilita al final, `enable=1 depth=0`).
6. `nvt_flash_proc_init` (`/proc/NVTSPI`) → `nvt_extra_proc_init` (≈25 nodos) →
   `nvt_mp_proc_init` (`/proc/nvt_selftest`) → `nvt_lockdown_info_read` +
   `nvt_fw_version_info_read` → **`nvt_init_touchmode_data()` @ 0xc9ec** (tabla 42 modos 0-41,
   ver §6) → `register_touch_panel` (xiaomi_touch, `panel_register_mask=1`) →
   misc `tpdbg` + `pen_hopping_frequency` → `bTouchIsAwake=1` → IRQ enable →
   `edge_filter_params` → workqueue `nvt_fwu_wq` con `Boot_Update_Firmware` diferido.
   Cierra con `Lockdown:… / READ LOCKDOWN!!! / end`.
- `nvt_check_fw_reset_state` @ 0x3618 y `nvt_boot_ready` @ 0x2ad0 actúan en resume/ESD,
  no en probe [HECHO: llamadas en `nvt_ts_suspend.c`, `nvt_ts_work_func.c:recovery_cnt>10`
  → `nvt_update_firmware("ERROR")` + `nvt_fw_reload_recovery`].

## 3. IRQ/worker y parsing (pregunta 3)

- `nvt_ts_work_func_irq_handler` @ 0x8908 (top-half mínimo) / `nvt_ts_work_func` @ 0x8914.
- Doze/gesto: lee **0x101 = 257 B**; normal: `*(u16*)(ts+0x424) + 0x101` con `*(ts+0x424)=0x1efe`
  ⇒ **0x1FFF = 8191 B** (buffer `ts[0x85]` de 0x2000=8192 B) [HECHO `nvt_ts_work_func.c:60,136`].
- Idle/gesto: `data[1..6]+3 < 2` (bytes 0xFD/0xFE); checksum aditivo `sum(data[1..0x40]) +
  data[0x41]==0` (nota: con offset +1 por el byte de comando; equivale al `data[0..0x3f]+data[0x40]`
  de nuestro driver) [HECHO `nvt_ts_work_func.c:63-82`]. Tras >10 frames idle/gesto en doze:
  recovery (sw_reset_idle + fw history + update + reload).
- Camino normal (no-doze): valida header DMA en `buf+0x105`: `{id u16, magic 0x509/0x4BF,
  ~id, ~magic}` y entrega el frame crudo a xiaomi_touch (`notify_raw_data_update`, 5176 B);
  **el MT lo reporta xiaomi_touch, no este .ko** [HECHO `nvt_ts_work_func.c:169-196`].
- `nvt_check_spi_dma_tx_info` @ 0x2c54 / `nvt_tx_auto_copy_mode` @ 0x2b48 /
  `nvt_check_tx_auto_copy` @ 0x2e58 / `nvt_wait_auto_copy` @ 0x305c: handshake TX-auto-copy
  (poll ≤200×1 ms de flag a 0) elegido según `ts->mmap[…]` (tipo 1=DMA, 2=auto-copy)
  [HECHO `nvt_check_spi_dma_tx_info.c:98-132,349-369`]. Clave mainline: el chip tras reset
  puede quedar en modo auto-copy; sin este handshake las lecturas devuelven basura con
  checksum malo persistente — el rescue del módulo lo cubre, el nuestro no (ver §6).
- `CTP_SPI_READ` @ 0x4e8: full-duplex, `cmd & 0x7F`, rx separado, `memcpy(buf+1, rbuf+2, len-1)`,
  5 reintentos [HECHO `CTP_SPI_READ.c:122,159-195` — coincide con `novatek-nt36xxx-spi.c:165-203`].
  `CTP_SPI_WRITE` @ 0x754, `nvt_set_page` @ 0x9a0 (`[0xFF][A>>15][A>>7]`).

## 4. Suspend/resume/doze/pen-charge (pregunta 4, solo táctil)

- `nvt_ts_suspend` @ 0xe438: si `gesture_switch==0` ⇒ `nvt_irq_enable(0)` (IRQ muda total);
  si ≠0 ⇒ deja IRQ y `nvt_enable_gesture_mode(1)` (doze: solo gestos + `wakeup_gesture_report`
  + `pen_gesture_report`); `bTouchIsAwake=0`; handshake `0x7c50/0xff50` con reintentos
  [HECHO `nvt_ts_suspend.c:125-138`].
- `nvt_ts_resume` @ 0xddf0 / `nvt_pm_suspend` @ 0xf890 / `nvt_pm_resume` @ 0xfa7c /
  `nvt_ts_resume_suspend` @ 0x9938 (para xiaomi_touch `ic_resume_suspend`).
- `nvt_touch_doze_analysis` @ 0xc33c: switch 0..7 (0=suspend, 1=fw update, 2/3=irq on/off,
  4=re-request IRQ, 5=lcd_id, 6=suspend, 7=resume-work) [HECHO `nvt_touch_doze_analysis.c:153-316`].
- Notificadores del .ko táctil: **`power_supply_notifier`** (`nvt_power_supply_work` @ 0x9410,
  `nvt_set_charge_state` @ 0xaa70; dmesg "Power supply state:0/1") y **notificador de pen-charge**
  (`nvt_pen_charge_state_notifier_callback` @ 0x9460; dmesg "pen_charge_connect is 0" →
  `update_pen_status` → reprograma hopping/carga) [HECHO]. **NO** usa FB_BLANK ni DRM
  directamente: del display solo le llega el estado vía xiaomi_touch
  (`display_suspend_ready`, `panel_event_notifier_client`; depends del .ko:
  `xiaomi_touch,qti_battery_charger,msm_drm,metis`) [HECHO strings §5].
- Nuestro driver (solo `disable_irq` en suspend) equivale al caso gesture=0; el caso con
  gestos no existe en mainline: aceptable para bring-up, anotado como riesgo menor.

## 5. xiaomi_touch.ko (pregunta 5)

- Es el **dueño del MT, gestos, modos y notifiers**; el .ko NVT le entrega frames crudos.
  PM: `xiaomi_register_panel_notifier` / `xiaomi_unregister_panel_notifier` (símbolos
  EXPORTADOS) sobre `panel_event_notifier` + `xiaomi_drm_panel_notifier_callback`;
  energía: `xiaomi_power_supply_notifier_callback`/`xiaomi_power_supply_work`
  (battery/bms/temp) [HECHO strings §4].
- Sysfs: `panel_color/panel_display/panel_vendor`, `pen_connect_strategy`, `palm_sensor`
  (`palm_value`), `Touch_Game_Mode/Report_Rate/Resist_RF/Tolerance/Panel_Orientation/
  Edge_Filter/Suspend`, `Touch_Stylus_Gamemode_Enable`; proc: `tp_fw_version`,
  `tp_lockdown_info`, `tp_selftest`, `tp_data_dump`, `last_touch_events` [HECHO strings +
  `/proc` vivo con `NVTSPI, nvt_{fw_version,baseline,raw,diff,pen_diff,pen_switch,selftest},
  xm_htc_* (24 nodos), tp_*`].
- Gestos: `xiaomi_get_gesture_type` (EXPORTADO); juego: `game_mode_bdata`,
  `mi_tp,game-mode-array`, params DT `touch-game-param-config1..3` ([2,2,1,2,1] etc.),
  "in gamemode, will set by cmd game update"; mmap double-buffer 80 KB frame + 160 KB raw
  para el HAL (`xiaomi_touch_dev_mmap`, dmesg 8.70) [HECHO].
- **Modos 1000/1004/3001-3045**: `nvt_set_cur_value` @ 0xaf30 trata `mode==1000` como
  conmutador de `op_mode` (`nvt_xm_htc_set_op_mode(2/1)`); al arrancar el HAL fija
  `mode 1004 ← 1` (dmesg `xiaomi_touch_mode:679`); `nvt_htc_ic_{get,set}ModeValue`
  aceptan rango HTC **0xBB9-0xBE5 = 3001-3045** (0xBD1=3025 usa addr 0x12; resto lee/escribe
  interfaces THP) [HECHO `nvt_htc_ic_getModeValue.c:71-141`, `nvt_set_cur_value.c`].
  **"1071" no aparece** en strings de ninguno de los dos .ko ni en dmesg [NO VERIFICADO —
  probablemente ID del HAL TouchFeature, no del kernel].

## 6. Contraste con mainline + parche 0001 (pregunta 6)

1. **Rango de coordenadas ×10 (NUEVO, grave si no se corrige)**: vivo `getevent event11`:
   X max **21359**, Y max **31999** (10 slots, TOUCH_MAJOR 255, PRESSURE 0/1); dmesg
   `super_resolution_factor=10`, `stylus-resol-double=1`. El DT del parche 0001 H3 declara
   2136×3200 ⇒ el rango se recortaría 10:1. DELTA en
   `artifacts/touch/driver/delta-0002-touch-superres-pen.patch`: 21360×32000.
   [HECHO vivo; el parche 0001 H3 queda corto aquí].
2. **IRQ RISING confirmado**: 0001 H3 (`EDGE_RISING`) es correcto; retirar la nota FALLING
   (o dejarla como último recurso para paneles TM). [HECHO §1].
3. **Layout de dedo sigue NO VERIFICADO** (único unknown gordo, ya conocido): el vendor no
   decodifica en este .ko (lo hace xiaomi_touch, ausente en mainline). `point_layout` 0/1/2
   sigue siendo la mitigación; pista nueva: upstream `novatek-nvt-ts.c` (I2C NT11205, nada
   que portar — distinto bus e IC) usa records de **6 B** (`NVT_TS_TOUCH_SIZE 6`), lo que
   apoya al candidato A. [INFERIDO a favor de A].
4. **Sin handshake TX-auto-copy/DMA**: si el chip sale de reset en auto-copy, el driver
   propio leerá basura con checksum persistentemente malo y lo registrará como "chip mudo".
   Riesgo medio; mitigación: ante checksum malo persistente, probar reset + relectura
   (ya existe 1 ciclo) y, en fase 2, portar el poll de `nvt_check_spi_dma_tx_info`.
5. **Sin pen**: el vendor crea 2 inputs de stylus; el nuestro avisa y sigue. 0001 no declara
   `novatek,pen-support` aunque el DT vendor lo trae: el DELTA lo añade (documentativo).
6. **Sin gestos-doze / sin FW updater**: correcto para bring-up (TDDI exige panel vivo;
   FW `o82_fw_csot.bin` + MP + `o82_nova_thp_config.ini` ya localizados en `/odm/firmware`).
7. Transporte (`set_page`, READ full-duplex con skip de 2 B, 5 reintentos, EVENT_BUF,
   chip-id 0x1fb535, `0x1efe+0x101`) **idéntico al vendor** — sin cambios.

## 7. Verificación viva (pregunta 7, todo solo lectura 17-oct-2026 ~01:36 UTC)

- `dumpsys input`: `NVTCapacitiveTouchScreen` (event11, TOUCH_MT, enabled),
  `NVTCapacitivePenM80p` (event12), `NVTCapacitivePenP81c` (event13) [HECHO, `live-verify.txt:3-30`].
- `getevent -il event11`: 10 slots, X 0-21359, Y 0-31999 [HECHO, `live-verify.txt:31-38`].
- `/proc/interrupts`: `359: … msmgpio 54 Edge xiaomi_tp` con miles de eventos [HECHO].
- `/proc`: nodos NVT + 24 `xm_htc_*` + `tp_fw_version` presentes [HECHO]; `tp_fw_version`:
  `fw_ver:0x0E fw_type:0x01 pid:0x5981`, driver `nvt_version_2024.01.13-001`,
  hal `2025.11.28-0001`, xiaomi-touch `2024.09.02-01` [HECHO].
- `/odm/firmware`: `novatek_nt36532_o82_fw_{csot,tm}.bin`, `_mp_{csot,tm}.bin`,
  `o82_nova_{thp,tm_thp}_config.ini` [HECHO].
- `getprop`: servicios `touchfeature-service`, `toucheventcheck` corriendo;
  `persist.stylus.palm.reject=1` [HECHO]. `/proc/nvt_fw_version` devuelve "Try again"
  (nodo con lectura no re-entrante; sin importancia).
- NO VERIFICADO (exige panel encendido + DT nuestro): polaridad efectiva en nuestro
  kernel, layout de dedo, handshake auto-copy, updater de FW.

## 8. Pendiente (para el dueño / siguientes sesiones)

1. Plegar el DELTA (superres + pen-support) en 0001 o fase4-touch según la ruta DT que viva.
2. En HW: evtest 1 dedo + esquinas para fijar `point_layout` y confirmar escala ×10.
3. Fase 2: portar updater (`Boot_Update_Firmware` + `o82_fw_csot.bin`) y gestos-doze si se
   quiere suspend con wakeup; si checksum malo persistente, portar el poll TX-auto-copy.
4. Aclarar "1071" contra el HAL TouchFeature (no es ID de kernel).
