# RE lápiz + firmware táctil CSOT — sesión nocturna 2026-10-17

Módulo: `build/android/vendor-modules-20261017/nt36532_touch.ko` (1,1 MB, con símbolos).
FW: `build/android/novatek_nt36532_o82_{fw,mp}_csot.bin` (245760 B c/u, md5 iguales a `/odm/firmware/` en vivo).
DT: `build/android/dt-full-uke-android/base/soc/.../spi@a90000/novatek@0`.
Cosecha: `build/android/cosecha-20261017/01-dmesg.txt` (13.332 líneas).
Decomp nueva (SOLO esta sesión): `artifacts/touch/stylus-fw/decomp/` (filtro «pen», 32 fns)
y `decomp-full/` (233/233 fns, Ghidra 12.1.4 headless con lock).
Vivo: `adb -s 192.0.2.13:5555` (solo lectura; `su -c` con comillas dobles).

## 1. Frames del lápiz (HECHO)

### 1.1 Tres input devices (dmesg cosecha + vivo)

| input | nombre | event | phys (dumpsys) |
|---|---|---|---|
| input11 | NVTCapacitiveTouchScreen | event11 | input/ts |
| input12 | NVTCapacitivePenM80p | event12 | input/pen |
| input13 | NVTCapacitivePenP81c | event13 | input/pen_p81c |

Dmesg: `nvt_ts_probe 5155: abs_x_max=2136, abs_y_max=3200`,
`fw_ver:0x0E fw_type:0x01 nvt_pid:0x5981`, driver `nvt_version_2024.01.13-001`,
`super_resolution_factor=10`, rx=40 tx=60, lockdown `53 42 32 91 4F 81 32 FF`.
Estado vivo: `stylus_enable=0, stylus_only=0, pen_scan_rate=0` (sin lápiz conectado).

### 1.2 Ejes por lápiz (HECHO: decomp `decomp-full/nvt_ts_probe.c` + `getevent -p` vivo, coinciden)

Fórmulas vendor: `Xmax = *(u16)(ts+0xBE)*10-1`, `Ymax = *(u16)(ts+0x18)*10-1`
→ 2136*10-1 = **21359**, 3200*10-1 = **31999** (factor ×10 = `stylus-resol-double`).

M80p (`ts+0x3b8`, probe .text 0x62f8–0x64dc):
`ABS_X 0..21359, ABS_Y 0..31999, ABS_PRESSURE 0..8191 (0x1fff, 13 bits),
ABS_DISTANCE 0..1 (hover), ABS_TILT_X/Y -60..+60`,
`input_set_capability(EV_KEY, KEY_WAKEUP=143/0x8f)`,
`BTN_TOOL_PEN (0x140)` + `BTN_TOUCH (0x14a)` por `__set_bit`,
`id.bustype = 0x1c (BUS_SPI)`, `+0xd0 = 0x80`.

P81c (`ts+0x3c0`, probe .text 0x64e4–0x69cc): todo lo del M80p MÁS
`ABS_BRAKE (0x0a, ¡NO ABS_RZ!) 0..360` (twist),
`ABS_PRESSURE 0..16383 (0x3fff, 14 bits)`,
clave extra `0x120` por `__set_bit` inlined (`keybit |= 0x100000000`, ko 0x6874).
Android lo clasifica `KEYBOARD|TOUCH|JOYSTICK` (M80p: `KEYBOARD|TOUCH`).

OJO corrección a la hipótesis inicial «twist = ABS_RZ»: `ABS_RZ = 0x05`;
el eje 0x0a es `ABS_BRAKE` (`input-event-codes.h`), confirmado por dumpsys
(`AbsState: ... ABS_BRAKE=0`, Motion Range `BRAKE: JOYSTICK`).

### 1.3 Dedo vs lápiz (HECHO)

Separación total: el dedo va por el nodo MT (`ABS_MT_SLOT max 9 = 10 dedos,
ABS_MT_TOUCH_MAJOR 0..255, ABS_MT_POSITION_X/Y 0..21359/31999 — también ×10,
ABS_MT_TRACKING_ID, ABS_MT_PRESSURE 0..1`), el lápiz por sus dos nodos
dedicados sin slots. El reporte normal (finger+pen) NO está en este .ko:
`nvt_ts_work_func` copia 0x1438 = 5176 B al frame DMA y llama a
`notify_raw_data_update(0)` (export de `xiaomi_touch.ko`); es xiaomi_touch
quien parsea y reporta (con `Touch_Stylus_Quick_Note_Mode`,
`pen_connect_strategy`, `update_stylus_connect_status_value` importado por el .ko).

### 1.4 Path de gestos con checksum (HECHO, `decomp-full/nvt_ts_work_func.c`, ko 0x8914)

`nvt_ts_work_func` tiene dos caminos (flag `ts+0x26c`):
- **A** (lectura 0x101 B de EVENT_BUF 0x125800): si `data[1..6]` son `0xFD/0xFE`
  → idle; si no, checksum **sum(data[1..0x40]) + data[0x41] == 0** → válido:
  `nvt_ts_wakeup_gesture_report(data[1]>>3, ...)` y, si `pen-support (ts+0x3b1)`,
  `nvt_ts_pen_gesture_report(data[0x42])`.
- **B** (lectura `*(u16)(ts+0x424)+0x101`): valida cabecera
  `{id @+0x105, magic 0x509/0x4BF @+0x109, ~id @+0x10d, ~magic @+0x111}`
  o byte `@+0x101 == 0xFF`; `memcpy` 0x1438 B + `notify_raw_data_update`.
- Recuperación: 10 frames idle seguidos → `nvt_update_firmware("novatek_ts_fw.bin")`.

`nvt_ts_pen_gesture_report` (ko 0x48b8): si `data[0x42] == 0x19`
(single click) → `report_single_click_pen_input` (ko 0x472c) sobre
`ts+0x3c0` si `ts+0x3c8 == 2`, o `ts+0x3b8` si `== 1`.
Secuencia exacta del click: `X=Y=PRESSURE=TILT_X/Y=1, BTN_TOUCH=1,
TOOL_PEN(0x140)=1, SYN; suelta con DISTANCE=1, BTN_TOUCH=TOOL_PEN=0, SYN`.
`report_release_pen_event` (ko 0x5460): todo a 0 + SYN.

### 1.5 Modos pen e hopping (HECHO decomp + INFERIDO nombres)

- `nvt_set_pen_inband_mode_1(u16, u8)` (ko 0x11e00): write 5 B a página 0x50,
  poll de ACK en `0xFF50 == 0` (5 reintentos × 10 ms). `nvt_set_pen_normal_mode`
  (ko 0x12034): write 3 B + mismo poll. (INFERIDO: inband = el IC genera la
  portadora del pen al panel; normal = pen pasivo.)
- `nvt_set_pen_switch(id)` (ko 0x12d70): write `[0x50, 0x7b, id]` (reg 0x7B50),
  10 reintentos × 10–11 ms, guarda en `ts+0x188c`; si `ts+0x310` (suspend) → `-0x10`.
  Llamado desde `update_pen_status` (ko 0x5030) tras
  `nvt_xm_htc_set_stylus_enable = nvt_set_extend_custom_cmd(4, val)` (ko 0x169ac4).
- Hopping: `nvt_set_pen_hopping_ack` (ko 0xe6f4: toggle `0x7C50` + poll `0xFF50`,
  5 rondas); `nvt_pen_hopping_frequency` (ko 0xebf4) y `nvt_pen_AG_update`
  (ko 0xedec) emiten uevent **`MIPP_PEN_STATE=%d`** con valor
  `(p2&0xff | (p1&0xff)<<8 | 0x310000)`; `pen_hopping_write` (proc, ko 0xf610)
  parsea 2 dígitos ASCII; `nvt_switch_FreqHopEnDis` toca página 0x50 + `0x23`.
- Scan rate: `nvt_xm_htc_get_pen_scan_rate = nvt_get_extend_custom_cmd(0xb)` (ko 0x16254).
- MP/probe de pen: `nvt_mp_parse_pen_array` + `c_pen_1d_diff_show` + `nvt_read_pen_raw`
  (arrays PenTip/Ring X/Y Raw/Diff/Max/Min para selftest de fábrica).

### 1.6 DT (HECHO, dump en `ev-dt-novatek-node.txt`)

Nodo `spi@a90000/novatek@0`: `compatible = novatek,NVT-ts-spi`,
`novatek,pen-support` (bool vacío), `novatek,stylus-resol-double` (bool vacío),
`novatek,mp-support-dt` (bool), `spi-max-frequency = 0x0124f800` (19,2 MHz),
game-params 1/2/3, arrays `mi_tp,*`, `panel`, pinctrl `pmx_ts_active/suspend`.
En vivo: `pen-support=1, stylus-resol-double=1, lcd_id=1 → panel CSOT`.

## 2. Driver mainline (HECHO) + parche borrador

- `novatek-nvt-ts.c` (349 lín.): driver upstream **I2C para NT11205** (Acer Iconia),
  sin pen. No sirve para uke.
- `novatek-nt36xxx-spi.c` (657 lín.): rewrite uke; transporte/eventos verificados
  vs el .ko, pero pen sin implementar (`pen_support` solo loguea el aviso) y el
  layout de dedo sigue NO verificado (candidatos A/B/C).
- Parche borrador (NO COMPILADO, NO PROBADO):
  `artifacts/touch/stylus-fw/novatek-nt36xxx-spi-pen-draft.patch`.
  Crea ambos nodos pen con los ejes verificados (§1.2), `KEY_WAKEUP`,
  `BTN_TOOL_PEN/BTN_TOUCH`, `phys`/`BUS_SPI` idénticos al vendor, helpers de
  click/suelta con la secuencia exacta del vendor, y hook de gesto `0x19`
  en el path idle (con LIMITACIÓN declarada: selector M80p/P81c `ts+0x3c8`
  cableado a M80p por defecto; el reporte normal requiere el frame DMA de
  5176 B + formato xiaomi_touch, fuera de alcance).
  Tampoco incluye updater de FW (el mainline no tiene `nvt_update_firmware/
  nvt_write_firmware/nvt_bootloader_reset`; habría que portarlo con
  `request_firmware(novatek_nt36532_o82_fw_csot.bin)` → `/lib/firmware/`).

## 3. FW CSOT (HECHO salvo indicación)

- Tamaño 245760 B = 0x3C000 = 60 bloques de 4 KB; magic **`NVT` en EOF-3**
  (el driver lo busca bajando de bloque en bloque: `nvt_get_fw_need_write_size`).
- Tag de 2 B a `@0x3B000` (y copia idéntica a `@0x352D0`): `fw = 11 EE`,
  `mp = 91 6E`; **suma = 0xFF en ambos** (pre-chequeo del driver, verificado
  en código + aritmética; el log vivo `fw_need_write_size = 245760, NVT end flag`
  lo confirma).
- Nombres (HECHO, `decomp-full/nvt_update_firmware.c:56-75`):
  `novatek_ts_fw.bin` → `novatek_nt36532_o82_fw_{csot|tm}.bin` según `ts+0x5d`
  (lcd_id; CSOT=1); `novatek_ts_mp.bin` → `mp_{csot|tm}`. El path de
  recuperación de work_func pide `novatek_ts_fw.bin` → **en esta tablet resuelve
  a `fw_csot`**.
- Carga viva (HECHO, dmesg l.10692-10717, t≈17,9 s, fuera del probe):
  `update_firmware_request: filename is novatek_nt36532_o82_fw_csot.bin` →
  falla en `firmware_class.path` (avc denied) → sysfs fallback → ueventd sirve
  **`/odm/firmware/novatek_nt36532_o82_fw_csot.bin` en 2 ms** →
  `bin_header_parser: cascade_2nd_header_info=1, ovly_info=0, ilm_dlm_num=2,
  ovly_sec_num=0, info_sec_num=14, partition=16` → `bootloader_reset` →
  `tx auto copy mode 2` → **`Update firmware success! <128397 us>`**.
  `frame_len = 5176` (coherente con el `memcpy 0x1438` de work_func).
- `fw` vs `mp` (HECHO, diff por páginas 4K): 28/60 páginas difieren —
  todo el código `0x0000-0x17FFF` + 1 B en `0x2B3DC` (`0x11` vs `0x91`,
  INFERIDO flag normal/MP) + 3 B en `0x35000` (tag) + 102 B en `0x36000`
  (INFERIDO tabla de criterios MP: fw trae datos reales, mp trae patrones
  `01…` y `12345678`) + 3 B en `0x3B000` (tag). Idénticas: `0x18000-0x2A000`,
  `0x2C000-0x34000` y las páginas cero `0x18000-0x21000, 0x37000-0x3A000`.
  Conclusión: **mp = variante de fábrica/selftest**, fw = runtime normal.
  (INFERIDO: el bloque duplicado tag+16 B en `0x352D0`/`0x3B000` es
  constante inmediata de código ARM duplicado ILM/DLM — `ilm_dlm_num=2`.)
- Versión corriendo (HECHO dmesg): `fw_ver 0x0E, fw_type 0x01, pid 0x5981`.
  (NO VERIFICADO: offset exacto de estos campos dentro del .bin; el driver lee
  la versión de SRAM del IC, no del fichero. CRC de fichero: suma16/CRC16/CCITT
  no coinciden con el tag → NO es checksum global; la integridad la verifica el
  propio IC por HW CRC: `nvt_set_bld_crc_bank/read_bld_hw_crc/fw_crc_enable`.)
- Escritura (HECHO parcial): `nvt_write_firmware` itera `bin_map` (entradas
  0x1c) con `nvt_set_page` + `CTP_SPI_WRITE` por partición.

## 4. P81c vs M80p (HECHO)

| | M80p | P81c |
|---|---|---|
| input/event/phys | input12/event12, `input/pen` | input13/event13, `input/pen_p81c` |
| clases Android | KEYBOARD\|TOUCH | KEYBOARD\|TOUCH\|**JOYSTICK** |
| presión | 0..8191 (13 b) | 0..16383 (14 b) |
| twist | no | **ABS_BRAKE 0..360** |
| tecla extra | no | **0x120** (→ LTRIGGER/BRAKE en Android) |
| común | X/Y ×10, DISTANCE hover, TILT ±60, KEY_WAKEUP, TOOL_PEN+TOUCH | idem |
| `ts+` | dev `0x3b8`, sel `0x3c8==1` | dev `0x3c0`, sel `0x3c8==2` |

(NO VERIFICADO: qué función emite los logs `Xiaomi stylus m80p/p81c` y
`ts->pen_static_status` — strings en .rodata @0x1234/0x126c sin xref hallada
en el export completo 233/233 ni en relocs; candidatas: work de
`pen_charge_state_notifier` con `ts+0x188c` como id de pen. Solo aparecerían
con lápiz conectado.)

## Artefactos (todos NUEVOS, ninguna edición de ficheros existentes)

- `artifacts/touch/stylus-fw/decomp/` + `decomp-full/` (+ `decomp-ghidra-*.log`)
- `artifacts/touch/stylus-fw/ev-getevent-pens.txt` (39 lín., los 3 devices)
- `artifacts/touch/stylus-fw/ev-dumpsys-input-full.txt` (1627 lín.)
- `artifacts/touch/stylus-fw/ev-dt-novatek-node.txt` (props del nodo)
- `artifacts/touch/stylus-fw/ev-fw-csot-parse.txt` (magic/tag/md5/páginas)
- `artifacts/touch/stylus-fw/novatek-nt36xxx-spi-pen-draft.patch` (borrador)

## Pendiente

1. Formato del frame DMA 5176 B (finger+pen normal) — necesita `xiaomi_touch.ko`
   o captura `notify_raw_data_update` con lápiz presente.
2. Offsets de versión/pid dentro del .bin; confirmaricon FW leída post-update.
3. Origen del log `Xiaomi stylus m80p/p81c` (requiere lápiz conectado).
4. Compilar y probar el parche (fuera de alcance nocturno: sin builds/flash).
5. Resolver `ABS_MT_PRESSURE max 1` del nodo touch (raro pero HECHO en decomp y vivo).
