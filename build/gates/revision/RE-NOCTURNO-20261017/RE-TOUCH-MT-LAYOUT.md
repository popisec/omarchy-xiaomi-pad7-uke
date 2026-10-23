# RE-TOUCH-MT-LAYOUT — layout de reports de dedo NT36532 (17-oct-2026, solo lectura)

> **CORRECCIÓN (RE-TOUCH-THP-BODY, misma noche):** el frame real es **5748 B** (no 5176);
> `w3` predicho = **5724**; el cuerpo **no contiene records de punto** (imágenes mutual/self/noise;
> los dedos los computa el HAL). Ver `RE-TOUCH-THP-BODY.md` y `artifacts/touch/mt-layout/thp-decode.py`.

Objetivo: cerrar el hueco «layout de dedo NO VERIFICADO» de RE-TOUCH-NT36532 §6.3
(el MT lo hace `xiaomi_touch`, ausente en mainline).
Resultado: el framing THP completo queda VERIFICADO byte a byte; el kernel vendor
queda probado inocente (no decodifica dedos); el record crudo de punto queda
acotado pero NO VERIFICADO (único resto). Sin builds, sin flash, sin escrituras
en la tablet, sin tocar ficheros existentes.

## 0. Material nuevo (todo en `artifacts/touch/mt-layout/`)

| Fichero | Origen |
|---|---|
| `decomp/` (114 .c) | Ghidra 12.1.4 `xiaomi_touch.ko` entero (proyecto `uke-night-mt`) |
| `hal-decomp/` (28 .c + `_XREF.txt`) | Ghidra `libtouchreport.so` (stripped), script nuevo `FindFrameParser.java` |
| `o82_nova_thp_config.ini` (36.228 B) | pull RO `/odm/firmware` (adb exec-out cat) |
| `libtouchreport.so` (1.355.440 B, stripped, NDK r22b) | pull RO `/odm/lib64` — es el decodificador HAL |
| `touch_report.log` (160.697 B, 2038 lín) | pull RO `/data/vendor/bsplog/touch/.../` — log vivo del HAL |
| `symtab-xiaomi-mt.txt` | `llvm-objdump -t` + relocs de ambos .ko |
| `frame-scan.py` | validador del layout verificado (auto-test OK/FAIL sintético) |
| `delta-mt-parser.patch` | delta borrador vs `novatek-nt36xxx-spi.c` (`patch --dry-run -p4` OK en copia /tmp, llaves balanceadas) |
| `DumpOne.java`, `FindFrameParser.java` | scripts Ghidra nuevos (reusables) |

`libnova.so` se trajo y se descartó (es de cámara/QNN, nada táctil) — no se conserva.

## 1. Hallazgo central: en kernel NO se decodifica ningún dedo [HECHO]

- `nt36532_touch.ko`: 36 sitios CALL26 a `input_event`, **cero** en `nvt_ts_work_func`
  (@0x8914, 0x754 B): 22 en 0x4xxx (gestos/pen), 9 en 0x5xxx, 5 en 0xcxxx
  [HECHO: `readelf --relocs`, conteo en `symtab-xiaomi-mt.txt`].
  `input_mt_report_slot_state` es import UND **sin ninguna reloc que lo llame**
  (importe muerto) [HECHO]. Los inlines (`input_mt_slot`, `input_report_abs`,
  `input_sync`) bajan a `input_event`: cero sitios = cero reportes. El worker normal
  solo hace `memcpy(thp_buf, buf+0x101, 0x1438)` + notifier [HECHO: `nvt_ts_work_func.c:169-196`
  del decomp previo].
- `xiaomi_touch.ko`: `notify_raw_data_update` @0x9a8 **no recibe puntero a datos**
  (solo `panel_id`): incrementa un contador y despierta al HAL [HECHO: `decomp/notify_raw_data_update.c:18-33`].
  El MT lo reporta `report_touch_event` @0xaa74 con records **ya cocinados de 28 B**
  que le entrega el HAL por `xiaomi_touch_dev_write` (CALL26 en 0x50a8; el write exige
  `len % 28 == 0`) [HECHO: `decomp/report_touch_event.c`, `decomp/xiaomi_touch_dev_write.c:83-85`].
- `xiaomitouch_input_event` @0xa37c es un filtro `input_handler` (snoop + timeline),
  no un parser [HECHO: `.data xiaomitouch_input_handler` + relocs ABS64].

## 2. Handoff NVT → HAL [HECHO, doble evidencia kernel + HAL]

Frame THP de **5176 B (0x1438)** en `EVENT_BUF + 0x100` (= `buf+0x101` del driver).
Lectura vendor: `*(u16*)(ts+0x424) + 0x101` con `0x1efe` ⇒ 0x1FFF B [HECHO].

Cabecera `F[0..0x17]` (offsets desde F = inicio del frame):

| Offset | Campo | Evidencia |
|---|---|---|
| F+0 .. F+3 | desconocido (¿tipo/contador?) | [NO VERIFICADO] |
| F+4 (u16) | id | NVT `work_func` +0x105; HAL lo exige |
| F+8 (u32) | magic ∈ {0x509, 0x4BF} | ambas partes |
| F+12 (u16) | ~id (`^ 0xFFFF`) | ambas partes |
| F+16 (u32) | ~magic (`^ 0xFFFFFFFF`) | ambas partes |
| F+20 .. F+23 | desconocido (4 B) | [NO VERIFICADO] |

Aceptación: magic+complementos OK **o** `F[0]==0xFF` (frame vacío)
[HECHO: `nvt_ts_work_func.c:169-173`, `hal-decomp/..._001d920c...c:87`].

## 3. Framing del cuerpo THP [HECHO, verificado insn a insn]

`thp_crc_check` @ libtouchreport `.text 0xd920c` (724 B, FDE 0xd920c–0xd94e0).
Cuerpo en `F+0x18`, longitud `w3 = u16LE @F+0x1b` (≥ 4); total `0x18+w3`
(frame normal: `w3 = 5152 = 0x1420`, total 5176):

```
F+0x18 ........... F+0x25 : 14 B de datos (incluye w3 en 0x1b..0x1c)
F+0x26 .. F+0x27      : head-cksum = SUMA PLANA bytes F[0x18..0x25] (u16LE)
F+0x28 ..               : datos (puntos + blobs raw, ver §5)
F+0x18+w3-4 .. +3       : body-cksum (u32LE)
body-cksum = u16LE(F[0x18]) + SUM u16LE(F[0x1a], F[0x1c], ...) hasta F+0x18+w3-5
```

Diagrama (frame normal 5176 B):

```
0x0000 +--------------------------------------------------+
       | F[0..3]=? | id | magic 0x509 | ~id | ~magic | ?=4B |  24 B cabecera
0x0018 +--------------------------------------------------+
       | 14 B datos (len w3 en +0x1b) | head-cksum u16     |  16 B head
0x0028 +--------------------------------------------------+
       | datos: puntos + blobs (raw mutual/diff)           |  ~5108 B
0x1420 +--------------------------------------------------+
       | body-cksum u32                                    |   4 B
```

Verificación cruzada: el u16-sum con semilla + u32 final coincide con el patrón
del driver propio solo en la idea (el nuestro usa suma de 64+1); los algoritmos
son distintos y ambos están copiados tal cual al delta + `frame-scan.py`
(auto-test: frame sintético OK, byte corrupto ⇒ BODY-CKSUM MAL + rc=1) [HECHO].

## 4. Modelo de puntos del HAL [HECHO]

- 12 slots: bucles con tope 12 (`w15=12`, `0x840/0xb0`, stride 7848 B/176 B)
  [HECHO: disasm 0x94604-0x946b0, 0xd1f80-0xd2004, `alg_input_report`].
- ids de dedo pequeños (`uVar20 < 10`), `raw_finger_bits` = máscara de 12 bits
  (popcount bits 0–11 en `FUN_00195710:273-276`) [HECHO].
- `Touch Down/Up: id: N` con N ∈ {0,1} en `touch_report.log` vivo [HECHO].
- Escala: `newX = rawX*k + c` (`madd`, super_resolution=10 normal, 8/16 en juego;
  ini `display 2136x3200`, `frame_data_type=3`) ⇒ rango 21360x32000, coincide con
  `getevent event11` (X 0-21359, Y 0-31999) y `register_touch_panel:469`
  (`x=2136 y=3200 rx=40 tx=60 sr=10 frame 2x10 raw 8x5`) [HECHO triple].
- Records cocinados HAL→kernel (28 B, u32 LE): `buf[0]` = panel id; por record
  `{slot @+4, pressed @+8, X @+12, Y @+16, +12 B sin uso}`; `count=0` libera los
  10 slots; **solo X/Y, sin presión/área** [HECHO: `report_touch_event.c:47-68`].
- Geometría input: `register_xiaomi_input_dev` fija X 0..param, Y 0..param,
  10 slots + `TOUCH_MAJOR/MINOR 0..0xff` [HECHO: `register_xiaomi_input_dev.c:55-59`].
- `report_coordinate` (FW extend-cmd 0x15, espejo en `ts+0x88... 0x1881`) en vivo = **0**
  [HECHO: `/proc/xm_htc_report_coordinate`]; es el único conmutador de formato del FW.
- Mmap vivo confirmado: `/dev/xiaomi-touch` 0x28000 (160 KB) rw-s + 0x14000
  (80 KB) r--s en `/proc/1808/maps` [HECHO] (= 8·5·4K y 2·10·4K del dmesg).

## 5. Lo que queda NO VERIFICADO (hueco residual, acotado)

1. **Record crudo de punto**: offset en el cuerpo, stride, codificación X/Y
   (bits/rango/×10 en crudo), presión/área/id. Pista: la copia fija de
   `thp_crc_check` cubre `F[0x18..0xe8]` y los blobs raw van en `F+0xca`
   (largos de globales ini-dependientes); los puntos están o en la zona fija
   `F[0x28..0xca]` o en un blob (el extractor vive entre `thp_crc_check` y
   `match/process_finger @0x95710`, 7060 B de algoritmo Kalman+jitter ya volcados).
2. `F[0..3]`, `F[0x14..0x17]`, `frame_index_head = u16 @F+0x19` (nombre del log;
   ese byte SÍ entra en el head-cksum), fuente de `point_cnt`.
3. El `fingers = head >> 3` del driver propio queda **sin apoyo**: `>>3` solo
   aparece en el path de gestos (`wakeup_gesture_report(buf[1]>>3)`). No usarlo
   para contar dedos en frames normales.

## 6. Comparativa con `novatek-nt36xxx-spi.c` y delta

- Transporte (set_page, READ full-duplex skip 2 B, 5 reintentos, EVENT_BUF,
  chip-id, idle FD/FE, cksum 64+1): compatible, sin cambios.
- Parser: hay que cambiar. El delta (`delta-mt-parser.patch`, `patch --dry-run -p4`
  OK en copia /tmp, llaves 0, original intacto 657 lín) añade sin tocar el path
  actual: consts THP + `nvt_thp_frame_ok()` (cabecera + head/body cksum verificados)
  + `nvt_spi_read_frame()` (lectura por tramos de 511 B: xbuf/rbuf son de 512 B)
  + `fbuf` (0x1438) + params `thp_frame` (fetch+valida, solo log) y `dump_thp`
  (printk de `F[0x28..0x48]` en frames válidos). No cambia ningún reporte.
- Candidatos A/B/C + `point_layout` se quedan como están (packet 64 B) hasta el
  day-test; la nota nueva lo explica en el propio código.

## 7. Validación

- Offset-a-offset con frame real: **no hay frame capturado** (cosecha y /tmp sin
  frames; `/proc/1808/mem` sobre el mmap falla con I/O — páginas PFNMAP de
  `remap_pfn_range`; `dev_read` da records comunes de 520 B, no frames;
  `touch_report.log` solo trae Down/Up con id). Se deja `frame-scan.py`
  (criterio de aceptación ejecutable) + método day-test abajo.
- Método day-test (táctil vivo, solo lectura + params del módulo): insmod con
  `thp_frame=1 dump_thp=1`, un dedo + esquinas (como TOUCH-REWRITE), capturar
  `dmesg` (doble captura consola+ssh si hay reboot, regla 4 del proyecto hermano);
  pasar cada volcado por `frame-scan.py` (debe dar OK + `w3=5152`); correlacionar
  `F[0x28..]` con `evtest` (posición conocida ⇒ stride/offsets; valor ×10 ⇒
  escala cruda). Con UN frame con dedo + su evtest simultáneo se cierra N1.
- `point_layout` (sentido real): no existe tal concepto en el vendor kernel; el
  único selector es `report_coordinate` (=0 en vivo). El param nuestro nombra los
  candidatos del packet de 64 B, no un modo del FW.

## 8. Artefactos y direcciones (evidencia por función)

xiaomi_touch.ko: `report_touch_event` 0xaa74/0x240, `notify_raw_data_update` 0x9a8/0xfc,
`notify_xiaomi_touch` 0x550, `add_common_data_to_buf` 0x658, `dev_write` 0x4ec8
(call en 0x50a8), `register_xiaomi_input_dev` 0xa774, `xiaomitouch_input_event`
0xa37c, `register_touch_panel` 0xd20. nt36532: `work_func` 0x8914/0x754, calls
`notify_raw_data_update` en 0x8ccc, `get_raw_data_base` en 0x8948. HAL
libtouchreport.so: `thp_crc_check` 0xd920c/724, `thp_crc16_check` 0xd9f44,
`process/match_finger` 0x95710/7060, `alg_input_report` 0x98f60, bucle de reporte
0xd1f44, `hal_frame_fetch` 0x1b7428, `vendor_get_frame_data` 0x1b5f5c.
Vías intentadas sin éxito (no repetir): `libnova.so` (es cámara), `/proc/PID/mem`
en mmap PFNMAP (I/O error; el stack sí se lee), `dev_read` (records comunes 520 B),
nodos `nvt_*` (mutual, no dedos), strings sueltos sin xref directo (los fmt llevan
`%s:` delante: buscar 4 B antes).
