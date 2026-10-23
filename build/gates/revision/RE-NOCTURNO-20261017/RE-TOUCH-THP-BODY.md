# RE-TOUCH-THP-BODY — cuerpo del frame THP: layout de blobs + fin del mito del punto crudo (17-oct-2026, solo lectura)

Cierra el hueco residual §5.1 de `RE-TOUCH-MT-LAYOUT.md` ("record crudo de punto").
Resultado: **en el frame no hay puntos**. El cuerpo son 3 imágenes raw
(mutual/self/noise); los dedos se computan en el HAL por procesado de imagen.
De paso corrige el tamaño del frame: **5748 B (w3=5724 predicho), no 5176**.

## 1. Piezas que parsean el frame [HECHO, tablet solo lectura]

| Pieza | Dato |
|---|---|
| `/odm/lib64/libtouchreport.so` (1.355.440 B, stripped) | md5 `ececace7…9b5b` = idéntico al pull previo; es el decodificador HAL (vive en `vendor.xiaomi.hw.touchfeature-service`, pid 1808) |
| `/odm/bin/touch_report_debug` (986.752 B) | binario de debug del mismo stack — NO examinado (vía alternativa) |
| `/vendor/lib64/vendor.xiaomi.hw.touchfeature-V1-ndk*.so` | binder del servicio, no parsea frames (vía alternativa menor) |
| `/odm/lib64/libtouchsensor.so`, `libtensorflowlite_touch_c.so` | sensor/ML, fuera de la ruta del frame |

Comando: `su -c "find /vendor /odm -iname '*touch*' -name '*.so'"` + `md5sum` (ambos md5 iguales).
`/proc/1808/mem` es ilegible (I/O error aun como root Magisk; igual que el intento
PFNMAP previo) → los globales del HAL se resolvieron por RE estática, no por live-dump.

## 2. Layout del cuerpo THP [HECHO]

Parser: `copy_frame_data_from_mmap` = `FUN_001d920c` (.text file `0xd920c`, 724 B).
Geometría de blobs: `init` en .text file `0xb8644-0xb8690` lee ini con defaults;
longitudes de blob: `DAT+0xac0/0xac4/0xac8` (file `.bss 0x189ac0/4/8`).

| Clave ini (rodata file) | Global | Default | Valor vivo (`o82_nova_thp_config.ini` pull RO) |
|---|---|---|---|
| `hal_node_num` (@0x4cc36) | +0xac0 | 2400 | 2400 |
| `hal_snode_num` (@0x4301e) | +0xac4 | 100 | 100 |
| `hal_nnode_num` (@0x482c7) | +0xac8 | 240 | 240 |
| `hal_row_num` (@0x47742) → cfg+0xd7 | — | 60 (!) | 40 |
| `hal_col_num` (@0x4ad30) → cfg+0xd8 | — | 40 (!) | 60 |

(!) defaults de fila/columna cruzados en el vendor (disasm `0xb85a8 w2=40` para
`hal_col_num`, `0xb85fc w2=60` para `hal_row_num`); inofensivo porque el ini trae
ambas claves. Producto `row*col=2400=node` verificado en `0xd89e0 umull`.

Offsets en F (= inicio del frame; cabecera F[0..0x17] sin cambios):

| Offset | Tamaño | Contenido |
|---|---|---|
| F+0x00 | 202 B | cabecera fija copiada (incluye id/magic, `w3`@0x1b, zona head-cksum 0x18..0x25) |
| F+0xCA | 4800 B | blobA: `u16[2400]` mutual 40×60 (contiguo, sin solape: la copia fija llega a 0xC9) |
| F+0x138A | 16 B | 2×u64 fijos (contadores; `dest+0xf6/0xfe`) |
| F+0x139A | 200 B | blobB: `u16[100]` self (40+60) |
| F+0x1462 | 38 B | struct fija 0x26 |
| F+0x1488 | 480 B | blobC: `u16[240]` noise |
| F+0x1668 | 12 B | cola: u64 + u32 |
| **total** | **5748 B = 0x1674** | `0xCA + 2·(2400+100+240) + 16 + 38 + 12` |

Evidencia: `hits_..._001d920c.c:113-137` (memcpys + offsets `0xca/0xda/+0x26`),
disasm `0xd88fc-0xd8918` (globales ← `ldrh cfg+0xda/dc/de`), `0xd8934-0xd893c`
(`lsl` ×2 = bytes), inits `calloc(1,328)+calloc(blob)` por slot.

## 3. Corrección al informe previo [HECHO la aritmética, INFERIDO el w3]

`RE-TOUCH-MT-LAYOUT.md §3/§7` daba "frame normal 5176 B, w3=5152". Ese número era
circular (0x1438 del `memcpy` kernel — que es solo el tamaño del `thp_buf` del
notifier, `nvt_ts_work_func.c:211`) sin ningún frame capturado. Con los valores
vivos del ini la copia HAL exige **5748 B**. Predicción falsable: un frame real
válido de este path trae **`w3 = 5724 = 0x165C`**. El SPI lee 0x1FFF B
(`nvt_ts_work_func.c:172`), cabe de sobra. `frame-scan.py` sigue compatible
(su matemática es w3-dinámica; solo su gate mínimo 5176 y el comentario
"w3=5152" quedan obsoletos).

## 4. Los puntos no están en el frame [HECHO]

- El pipeline (`caller_0017cb58`: `FUN_0019a220 → 0019acac → 0019b0a4 → … →
  0019c178 → 00195710 match/process_finger → 001949dc → 00198f60
  alg_input_report`) mueve **imágenes** (`memcpy Glas row*col` en
  `caller_0017d5a4`), no listas de puntos; genera candidatos de 300 B y los
  asocia por distancia húngara (matrices `DAT_00256d60/00257ed0`, `link:%d`).
- `point_cnt` / `raw_finger_bits` del log son **computados** (conteo de bucle y
  popcount de bitmask de tracking en `00195710:273-276`), no campos del frame.
- Sin checksum por punto: solo head-cksum + body-cksum (`001d920c`, dos ramas
  de error y nada más).
- El ×10 (`super_resolution`, default 10 en `00198f60:105`) se aplica en
  `alg_input_report` al escalar coordenadas computadas (`madd` + `fVar24`,
  `00198f60:363-369`); el frame lleva u16 raw de sensor. Ids 0..11 los asigna
  el tracker; `pressed` es estado del tracker. Presión/área: no existen en el
  frame ni en los records cocinados de 28 B (solo slot/pressed/X/Y).

## 5. Decodificador `thp-decode.py` (+9 autotests OK)

Nuevo en `artifacts/touch/mt-layout/thp-decode.py`: valida con longitud dinámica
(`total=0x18+w3`), trocea blobs por geometría parametrizable
(`--node/--snode/--nnode`), imprime stats por blob y mapa ASCII del mutual.
`--selftest`: frame sintético 5748 válido (w3=5724, cksums OK en `frame-scan.py`
y aquí), byte corrupto ⇒ BODY mal, head corrupto ⇒ HEAD mal, magic malo,
vacío `0xFF`, geometría errónea y corto. 9/9 PASS.

## 6. Qué le falta al parche `12-touch-mt-parser-thp.patch` (propuesta, sin tocarlo)

El parche asume `NVT_THP_FRAME_LEN 0x1438` / "w3=5152" y vuelca `F[0x28..0x48]`
como "point region". Delta propuesto (`12+thp-body`, a redactar sobre
`artifacts/parches/`):

1. `NVT_THP_FRAME_LEN 0x1674` (5748) y lectura SPI por tramos que lo cubra;
   validar con `total=0x18+w3` dinámico (aceptar 5176 y 5748: el w3 manda).
2. Cambiar `dump_thp` a volcar `F[0xCA..0xCA+16]` (primeras muestras mutual) +
   `w3` + gap1, no `F[0x28..]` (eso es cabecera fija, no puntos).
3. **No decodificar dedos en kernel**: el algoritmo vive en el HAL (Kalman,
   jitter, palm, game-mode). El parche debe exponer el frame crudo (relay o
   debugfs binario) para que el userspace lo procese; el input MT seguirá
   viniendo de `report_touch_event` hasta que exista un port del HAL.
4. Actualizar el comentario "w3=5152" a "w3=5724 (predicho) con ini 2400/100/240".

## 7. Marcadores

HECHO: tabla §2, claves ini↔globales↔defaults, valores vivos, ausencia de
puntos/checksums-por-punto en el frame, ×10 en `alg_input_report`, md5 de la
lib, incompatibilidad silenciosa de `/proc/PID/mem`.
INFERIDO (fuerte): blobA=mutual / blobB=self / blobC=noise (por tamaños
40×60, 40+60, y nombres `hal_*node*`); w3=5724 en frames reales; gap1 =
contadores de frame.
NO VERIFICADO: ningún frame real capturado (sigue pendiente el day-test de
`RE-TOUCH-MT-LAYOUT.md §7` con `thp-decode.py` en vez de `frame-scan.py`);
qué `data_type` selecciona `001d920c` frente a `001d9f44/001db27c`;
semántica fina de gap2/cola; `touch_report_debug` (podría traer su propio
parser con más símbolos).
