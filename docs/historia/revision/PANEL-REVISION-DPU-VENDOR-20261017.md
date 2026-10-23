# DPU/DSI del vendor (Android, tablet viva, 17-oct) - lectura solo-lectura

Crudo en `build/android/vendor-harvest-20261017b/dpu/`: `sde-blocks-raw-awake.txt` (todos los bloques, cabecera con off/len/readback/wakefulness=Awake),
`dsi-ctrl-awake-rereads.txt`, `dt-sde-blocks.txt` (bases del DT), `sde-valid-offsets-step100.txt` + `sde-valid-ranges-exact.txt` (whitelist del debugfs).
Modo activo unico leido: `3200x2136x120vid` (967428 kHz, htotal 3490, vtotal 2310). No se cambio de modo (hacerlo = tocar ajustes de Android; prohibido).

## 1. Por que la lectura de INTF salia truncada a 0x5c
- `sde_off` acepta `"<off_hex> <len_hex>"`; el valor por defecto es `0x00000000 5c`.
- El nodo **solo acepta rangos contenidos en un rango de dump registrado** (whitelist del catalogo SDE). Si `off+len` no cae entero dentro de un rango, el write falla con rc=1 **sin error visible y deja el off/len anterior**. La cosecha previa leyo con len=0x5c residual.
- Rangos validos medidos escribiendo solo `_off` (no lee HW): TOP 0x1000..0x1380; CTL 0x16000..0x19fff (0x1000 c/u); INTF_n 0x35000/36000/37000/38000 len 0x300; LM 0x45000..0x48000 len 0x400; MERGE_3D 0x4f000/0x50000/0x67700/0x7f700 len 8; PP (4 B + 0xc4 + 0x38 por PP); WB 0x65000/0x66000 len 0x2c8; DSC top 0x81000/0x82000 (4 B), enc 0x81100/0x81200/0x82100 (0x9c), ctl 0x81f00/0x81f80/0x82f00 (0x24). Todo coincide con el DT (`qcom,sde-*-off`, enc 0x100/0x200, ctl 0xf00/0xf80, intf-type dp,dsi,dsi,dp).
- Tras leer se restauro `0 5c`. Pantalla despertada con KEYCODE_WAKEUP antes de cada bloque (Android duerme la pantalla en segundos); cada cabecera registra `mWakefulness=Awake`.

## 2. Tabla decodificada (valores medidos)
| Bloque | Reg | Valor | Decodificado |
|---|---|---|---|
| INTF_1 (0x36000, DSI) | TIMING_ENGINE_EN 0x00 | 1 | activo (master, CTL_INTF_MASTER=bit1) |
| | INTF_CONFIG 0x04 | 0x80800000 | sin ACTIVE_H/V_EN (bits 29/30=0) |
| | HSYNC_CTL 0x08 | 0x023c0010 | periodo 572 px, pulso 16 |
| | VSYNC_PERIOD 0x0c | 0x142968 | 1321320 = 572 x 2310 |
| | VSYNC_PULSE 0x14 | 0x478 | 1144 = 2 lineas |
| | DISPLAY_V_START/END 0x1c/0x24 | 0x14ab0 / 0x13ef4f | linea 148 .. 2284 (2136 activas) |
| | ACTIVE_V 0x2c/0x34 | igual | igual |
| | DISPLAY_HCTL 0x3c | 0x01ca0020 | start 32, end 0x1ca -> 427 px (/30) |
| | ACTIVE_HCTL 0x40 | 0x01ca0020 | idem (no habilitado) |
| | POLARITY 0x50 | 0 | HSYNC/VSYNC activos en bajo (0) |
| | INTF_CONFIG2 0x60 | 0x1011 | **bit0 DATABUS_WIDEN=1**, bit4 DATA_HCTL_EN=1, bit12 DCE_DATA_COMPRESS=1 |
| | DATA_HCTL 0x64 | 0x012a0020 | 267 px (=ceil(800 B*8/24), una slice) |
| INTF_2 (0x37000, DSI) | TIMING_ENGINE_EN | **0** | mismos registros que INTF_1 pero motor NO habilitado (CTL_INTF_ACTIVE=INTF1+INTF2) |
| DSC_0 enc 0x81100 / DSC_1 enc 0x81200 | | idénticos | pic h 0x858=2136, slice w 0x320=800, chunk 800, init_xmit_delay 0x200, init_dec_delay 0x2b2, first_line_bpg_offset 0x0d (=13, coincide con quirk RC OEM) |
| DSC_0/1 top 0x81000 | | 0x101 | DSC_2 top 0x82000=0x80 (sin uso: enc 0x82100 casi vacío) |
| DSC ctl 0x81f00/0x81f80 | +0 | 0 / 1 | +4=0x1001, +8=0x2c688, +c=0xc0000000 |
| MERGE_3D_0..3 | MUX/MODE | **0** | MERGE_3D no usado |
| CTL_0 | DSC_ACTIVE 0xe8 | 3 | DSC_0+DSC_1; MERGE_3D_ACTIVE 0xe4=0; INTF_ACTIVE 0xf4=6 (INTF1+2); INTF_MASTER 0x134=2 (INTF_1); FETCH_PIPE 0xfc=0x18 |
| LM_0 / LM_1 | OUT_SIZE 0x04 | 0x08580640 | 1600x2136 por LM; LM_1 +0=0x80000002 (slave del par); LM_2/3 vacios |
| PP_0..2 (0x6a300/6b300/6c300) | +0x64 | 3 | PP_0/1/2 configurados parecido (+0x90=0x80000000); PP_3.. solo 0x...0f |
| DSI ctrl0/1 | ACTIVE_H 0x24 | 0x01cb0020 | start 32, end 459 -> **427 px** |
| | ACTIVE_V 0x28 | 0x08ec0094 | 148..2284 |
| | TOTAL 0x2c | 0x0905023b | h 572 (0x23b+1), v 2310 |
| | HSYNC 0x30 / VSYNC 0x38 | 0x00100000 / 0x00020000 | 16 / 2 |
| | VIDEO_COMPRESSION 0x2a0 | 0x03200b51 | compresion DSC on, 0x320=800 B/pkt, DT 0x0b |

No leidos: registros de **TOP del DSC mux / WB mux**: no estan en ningun rango registrado de `sde_off` (TOP solo 0x1000..0x1380, ahi solo HW_VERSION=0xa0010000, +0x1c=0x1000, +0x2bc=0x04400000). No hay forma segura de verlos sin devmem. Offsets no verificados no se leyeron.

## 3. Reconciliacion ACTIVE_H=534 / 0x090502a6 vs 427 / 0x0905023b
- **534 / 0x090502a6 NUNCA se midio en el vendor.** Es una derivacion del RE (`RE-ANDROID-GAPS-20261015.md:78-84`, "Bit abierto (HIPOTESIS)": ceil(1600*8/24)=534 porque el DT DSI no tiene `qcom,widebus-enable`). Lo unico medido con esos numeros fue **nuestro Linux L71 con widebus forzado OFF** (A1 §2 "vendor EXACTO" compara contra la derivacion, no contra lectura Android).
- Lo medido en Android (3 lecturas: cosecha de la mañana, relectura de hoy dsi0 y dsi1, mismo registro 0x24/0x2c del controlador DSI, mismo valor) es 427 / 0x0905023b, que ademas coincide con la traza `dsi_ctrl_hw_cmn_set_video_timing 0x905/0x23b`.
- Cierre con numeros independientes del DSI: INTF_1 HSYNC periodo = 572 (=0x23b+1), VSYNC_PERIOD=572x2310; 158 558 666 Hz / 1 321 320 = 120,00 Hz. Con 679 px/linea harian falta pclk 188,2 MHz para 120 Hz (no es el pclk medido). INTF_CONFIG2 bit0 DATABUS_WIDEN=1 y DISPLAY_HCTL 427 px confirman **widebus ON** en el vendor (el widebus lo decide el hardware/driver, no un prop del DT).
- Consecuencia: el "mundo 24" (INTF /24 + widebus OFF, L71-L73) NO es el vendor; el vendor es widebus ON (H=427, h_total 572), que es lo que Linux L70 mostraba (`ACTIVE_H=0x01cb0020`). La paridad de ACTIVE_H que se creia cerrada estaba en realidad en el lado contrario; nuestro "mainline" original ya coincidia (427). Tampoco hay diferencia entre dsi0 y dsi1 en 0x24/0x28/0x2c (identicos).
- Otras modos (144/90/60/50/48/30) NO re-leidos: cambiar de modo exige tocar ajustes de Android.
