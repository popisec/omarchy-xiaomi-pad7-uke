# TACTIL-FWLOAD — cargador de firmware del NT36532 por SPI (espacio de usuario)

18-oct-2026. Solo trabajo en el PC (sin tablet, sin ssh/adb/fastboot). No se ha copiado el firmware ni el `.ko` al repo
y no se ha hecho commit. Entregable: `build/rootfs/deploy/tactil/uke-touch-fwload.py` (Python puro, ioctl de spidev).
Probado aqui: `--parse-only` y `--dry-run` sobre el `.bin` real (ver §7). **Nada se ha ejecutado sobre el chip.**

Material usado (verdad = el `.ko`; el GPL solo da el esqueleto):
- `.ko`: `~/proyectos/ubuntu-uke/stock/modules/nt36532_touch.ko` (sha256 `5f0a3603…10a8a`, ELF aarch64 ET_REL **con símbolos**).
  Las direcciones de abajo son offsets en `.text` del ELF (offset de fichero = `0x49ef0` + offset), obtenidos con `llvm-objdump -dr`.
- `.bin`: `~/proyectos/ubuntu-uke/stock/firmware/novatek_nt36532_o82_fw_csot.bin` (245760 B, sha256 `a4f949fb…9b310`).
- Log de Android: `build/android/coldboot-20261017/dmesg-30s.txt` (líneas 4788-4794, 9558-9562, 10451-10512).
- RE previo: `ubuntu-permanente/criticas/ronda-29/{TOUCH-REWRITE,TOUCH-DRIVER-VS-VENDOR}.md`.

## 0. Hallazgos que cambian lo que se creía (leer primero)

1. **El chip es "Cascade Chip": el mapa de memoria correcto es `NT36532_cascade_memory_map`, no el `single`.**
   El log de Android lo dice (`nvt_ts_check_chip_ver_trim 3407: Cascade Chip`, y `fw history 0x121B3C` = campo [30] del mapa cascade).
   El `.ko` decide leyendo el **bit0 de 0x1fb12c** (1 = single, 0 = cascade; `nvt_ts_check_chip_ver_trim_loop` ko 0x8740-0x87d0).
   `EVENT_BUF` del mapa cascade = **0x11c400** (FWINFO = 0x11c478, estado de reset = 0x11c460), **no 0x125800** (mapa single).
   `uke-touch-probe.py` y el RE previo (`single_memory_map[0]`) leyeron el mapa equivocado, así que **"FWINFO = RAM sin inicializar" se midió
   en la dirección equivocada**. La conclusión «sin firmware» sigue siendo plausible: Android, **antes** de su descarga, también lee basura
   estable en el FWINFO cascade (`nvt_get_fw_info: FW info is broken! fw_ver=0xBB, ~fw_ver=0x3D`, ×4, log 10.526 s) y no hay FW alive
   hasta su `update_firmware_request` a los 17.6 s. Pero hay que **repetir la lectura con `--verify-only`**, que lee ambos mapas.
2. **Valores esperados tras cargar: `fw_ver = 0x11`, no 0x0E.** Android tras la descarga: `fw_ver=0x11, fw_type=0x01, PID=0x5993,
   abs_x_max=32000, abs_y_max=21360` (log 17.770 s) y el propio `.bin` trae FW_VER=0x11 / FW_VER_BAR=0xEE en `0x3b000/0x3b001`.
   `0x0E` es el primer byte de `chip_ver_trim`; `2136×3200` son los *defaults* del vendor (DT / "Set default" cuando FWINFO está roto);
   `32000×21360` = 3200·10 / 2136·10 (`super_resolution_factor=10`, modo THP). `rx 40 / tx 60` (x_num=40, y_num=60) sí es del FW.
3. **El vendor recarga el firmware en cada resume (el panel TDDI resetea la MCU del táctil; inferencia, no medida)**: `nvt_ts_resume` (ko 0xddf0) llama a
   `nvt_update_firmware` (0xe028) + `nvt_check_fw_reset_state` (0xe034). El probe de Android además hace un `bootloader reset` a los 3.6 s y
   **retrasa 14 s** la descarga (`queue_delayed_work_on(Boot_Update_Firmware, 3500 jiffies a HZ=250)`, ko 0x65a8 → 17.6 s en el log).
   Consecuencia operativa: **cargar el FW después del último reset del panel y volver a cargarlo tras cada resume/DPMS que re-inicialice el panel**.
4. **La CRC del `.bin` es calculable** (el vendor la delega al hardware): CRC-32 poly 0x04C11DB7, MSB-first, init 0xFFFFFFFF, sin xorout,
   sobre los datos con cada palabra de 32 bits invertida; cubre `size+1` bytes en ILM/DLM y los 252 primeros en las cabeceras. Coincide con las
   CRC doradas de la cabecera para ILM, DLM y las dos cabeceras → el `.bin` es íntegro y se confirma que se escriben **size+1** bytes.

## 1. Fuentes GPL (consultadas el 18-oct-2026) y su valor

La herramienta de consulta devolvió **resúmenes**, no el texto literal; úsese solo como esqueleto, nunca como verdad del chip.

| Fuente | URL | Qué aporta |
|---|---|---|
| RFC "Input: Add Novatek NT36xxx touchscreen driver" (G. Chan, oct-2024), parche 2/3, adaptado del driver del vendor | https://lkml.rescloud.iu.edu/2410.1/11379.html | `bootloader reset` = escribir 0x69 en SWRST_N8, espera **35 ms**; `check_reset_state` lee 6 B en `EVENT_BUF\|0x60`, acepta `>= fw_state && <= 0xAF`; bank CRC: 3 B a `*_DES_ADDR` y 3 B a `*_LENGTH_ADDR`, checksum a `G_*_CHECKSUM_ADDR`; `fw_crc_enable` = 0x60←0 y 0x50←0xAE; `boot_ready` = BOOT_RDY←1 + espera 10 ms; `NT36XXX_TRANSFER_LEN = 63*1024`; estado INIT 0xA0, MAX 0xAF; cabecera: ILM/DLM `{bin, sram, size}` ×12 B + crc en 0x18, info desde 0x30 (16 B: sram, size, bin, crc), flag final "NVT"/"MOD" por sectores de 4 KiB, FW_VER+FW_VER_BAR=0xFF. **No** trae NT36532 ni cascade ni auto-copy. |
| Cover letter del mismo RFC | https://lkml.iu.edu/hypermail/linux/kernel/2410.1/11376.html | Origen: driver del vendor en LineageOS (`nt36xxx_spi/`) y `99degree/linux@nt36xxx`. |
| Driver del vendor público (LineageOS sm6250, rama lineage-21) | https://raw.githubusercontent.com/LineageOS/android_kernel_xiaomi_sm6250/lineage-21/drivers/input/touchscreen/nt36xxx_spi/nt36xxx_fw_update.c (la rama `lineage-22.0` da 404) | Nombres reales: `nvt_write_firmware` → `nvt_write_sram` (`set_page(SRAM_addr)`, `fwbuf[0]=SRAM_addr&0x7F`, `CTP_SPI_WRITE(len+1)`, `size = size+1`), `nvt_set_bld_crc_bank(DES,SRAM,LENGTH,size,G_CHECKSUM,crc)`, `nvt_download_firmware_hw_crc` (versión antigua: reset → write_firmware → set_bld_hw_crc → bld_crc_enable → fw_crc_enable → boot_ready → check_fw_reset_state(INIT), 3 intentos). |

No se encontró ninguna fuente pública para el flujo **cascade** (`nvt_tx_auto_copy_mode`, mapas NT36532/NT36523N, `cascade_2nd_header_info`): para eso solo vale el `.ko`.
Diferencias `.ko` 2024.01.13 frente a ese GPL antiguo: set_bld_crc_bank **antes** de escribir (no después), auto-copy para el 2º chip y **no** hay `bld_crc_enable` en el camino.

## 2. Formato del `.bin` (derivado del `.ko`; el GPL coincide, salvo el caso cascade)

`nvt_get_fw_need_write_size` (ko 0xfe68-0x10038, inlinada en `nvt_update_firmware`) y `nvt_bin_header_parser` (ko 0x100e0-0x10970).
Reproduce el log de Android (`fw_need_write_size = 245760(0x3c000), NVT end flag`; `cascade_2nd_header_info = 1`;
`ovly_info = 0, ilm_dlm_num = 2, ovly_sec_num = 0, info_sec_num = 14, partition = 16`).

| Campo | Offset | Valor en el bin | Regla del `.ko` |
|---|---|---|---|
| fin de cabecera `end` | u32 @0x00 | 0x200 | = BIN_addr del ILM |
| cascade_2nd_header_info | bit1 de @0x20 | 1 (0x03) | `(b&2)>>1` |
| overlays | @0x28 | 0 | `ovly_info=(b&0x10)>>4`, `n=b&0xF` |
| ILM, DLM | 12 B desde 0x00: `{BIN, SRAM, size}`; crc en `0x18+4·i` | ILM BIN 0x200 → SRAM 0x000000, size 0x174d7, crc 0xe4bdd7f0; DLM BIN 0x22000 → SRAM 0x100000, size 0x1409f, crc 0x89495247 | ko 0x10478-0x104f4 |
| secciones Info | 16 B desde 0x30: `{SRAM, size, BIN, crc}`; cuenta = `ceil((end/2-0x30)/16)+1` (cascade) | 14 entradas: 12 vacías (size 0), `Header` @0xF0 → SRAM 0x1140a0 size 0xff BIN 0x000; `Header` @**end-16=0x1f0** → SRAM 0x1141a0 size 0xff BIN 0x100 | tras la 1ª "Header" (BIN<end y size≠0) y si cascade, `pos = end-16` (ko 0x1051c-0x1052c) |
| FW_VER / FW_VER_BAR | `need-0x1000`, `need-0xfff` | 0x11 / 0xEE (suma 0xFF) | ko 0x100b4-0x100dc |
| flag final | `need-3` | `NVT` | ko 0xfe8c-0xfeb8 |

Particiones que se escriben (size≠0), **cada una size+1 bytes** (ko 0x11638 `add w25,w10,#1`; verificado con la CRC):
ILM 95448 B → SRAM 0x000000; DLM 82080 B → SRAM 0x100000; Header 256 B → 0x1140a0; Header 256 B → 0x1141a0 (total 178040 B).
Los overlays (no hay en este bin) usan `pos = bin_map[1].BIN + 0x10·(list-2-info_sec_num)` — fórmula del `.ko` (ko 0x1053c-0x10590), **sin datos reales para comprobarla**.

## 3. Secuencia, con cita al `.ko`, registros y confianza

`nvt_update_firmware` (ko 0xfc68) elige el camino por `ts->hw_crc` (byte ts+0x338 = 2 para NT36532, ko 0x10a70 → salto a 0x10e24).
`NT36532_hw_info` (.data+0x270) = `{hw_crc=2, auto_copy=2, …, &hw_reg_addr_info}`. Bucle de descarga ko **0x10ed0-0x10f78**, 3 intentos (ko 0x10ec4 `cmp w23,#2`).
Todas las direcciones son del `NT36532_cascade_memory_map` (.rodata+0x9ecc; los índices son los campos u32 de la tabla de 51 entradas).
Cada operación de escritura es `set_page` + `CTP_SPI_WRITE([addr&0x7F | 0x80][payload])`; cada lectura `set_page` + `CTP_SPI_READ` (ver §4).

| # | Paso (función del vendor, dirección ko) | Transferencias (registros y valores) | Espera vendor / script | Confianza |
|---|---|---|---|---|
| 0 | Identificación (`nvt_ts_check_chip_ver_trim_loop`, 0x8370) — **solo lectura en el script** | leer 6 B en `chip_ver_trim` 0x1fb104 → debe dar `.. .. .. 32 65 03` (tabla trim, entrada 0, máscara 00 00 00 01 01 01); leer bit0 de 0x1fb12c (0 = cascade) | — | Alta (log de Android y rodata coinciden). El vendor hace aquí su propio `bootloader reset` y 6 B de ceros en 0x1fb104; el script no los hace |
| 1 | `nvt_bootloader_reset` (0x320c) | `0x69 → 0x1fb43e` (swrst_sif, hw_reg_addr_info[1]) | vendor `__const_udelay(5000)` = 5 ms; script 35 ms (GPL RFC) | Alta: dirección y valor en el log + desensamblado; el GPL lo confirma (0x69) |
| 2 | `nvt_set_bld_crc_bank` ×2 (0x11c18; llamadas en 0x10ed8-0x10f1c) | ILM: `set_page(0x1fb528)`; `0x1fb528 ← SRAM(24b)=0x000000`; `0x1fb518 ← size(24b)=0x0174d7`; `0x1fb500 ← crc(32b)=0xe4bdd7f0`. DLM: `0x1fb52c ← 0x100000`; `0x1fb530 ← 0x01409f`; `0x1fb504 ← 0x89495247` (las 3 caen en la misma ventana de 128 B) | — | Alta en valores y orden (campos [41],[38],[43] / [42],[39],[44]); nombres ILM_DES/LENGTH/G_CHECKSUM inferidos por el papel de cada argumento. LENGTH con 3 B de datos porque hw_crc==2 (ko 0x11cb4-0x11cc4) |
| 3 | `nvt_tx_auto_copy_mode` (0x2b48), **solo si cascade_2nd_header_info** (ko 0x10f20 lee .bss+0x578, no ts->auto_copy) | `0x56 → 0x1fc925` (auto_copy==2 → 0x56; ==1 → 0x69) | — | Alta (log: `tx auto copy mode 2 enable`) |
| 4 | `nvt_write_firmware` (0x11598) | por cada partición con size≠0: `set_page(SRAM)`, `[SRAM&0x7F\|0x80][size+1 bytes]`; el vendor trocea a 0xFC00 (64512) B; el script a **16256 B** (≤ bufsiz-1, múltiplo de 128 → el byte de comando no cambia) y repite `set_page` por bloque | — | Alta en destino/orden/longitud (verificado con CRC y en SRAM virtual); **Media** en el troceado de 16 KB (el vendor nunca lo hace) |
| 5 | `nvt_wait_auto_copy` → `nvt_check_tx_auto_copy` (0x305c / 0x2e58) | repetir `set_page(0x1fc925)` + leer 1 B hasta 0 (200 × 1 ms) | 1 ms | Alta (lógica); el valor 0 = terminado está en el desensamblado |
| 6 | `nvt_fw_crc_enable` (0x2a04) | `set_page(0x11c400)`; `[0xE0][00×6]` (0x60←0, 6 B); `[0xD0, 0xAE, 0x00]` (0x50←0xAE, 0x00) | — | Alta (desensamblado; GPL: RESET_COMPLETE=0x60←0, HOST_CMD=0x50←0xAE) |
| 7 | `nvt_boot_ready` (0x2ad0) | `0x01 → 0x1fb50d` (BOOT_RDY, campo [33]); con hw_crc≠0 no hay más escrituras | vendor 5 ms; script 10 ms | Alta |
| 8 | `nvt_check_fw_reset_state(0xA0)` (0x3618) | `set_page(0x11c400)`; leer 6 B desde 0x11c460 (CTP_SPI_READ len 6 → 5 B de datos); OK si `0xA0 ≤ b[0] ≤ 0xAF`; hasta 10 reintentos × 10 ms (50 si state≠0xA0) | 10 ms | Alta (desensamblado); el GPL RFC usa el mismo criterio |
| 9 | `nvt_get_fw_info` (0x37f4) | `set_page(0x11c400)`; leer 39 B desde 0x11c478 (len 39 → 38 B): `fw_ver`, `~fw_ver`, x_num, y_num, `abs_x_max` BE16, `abs_y_max` BE16, … `fw_type`@13, `PID` LE16@34; válido si `fw_ver+~fw_ver==0xFF`; 4 intentos | — | Alta (layout); valores esperados: ver §0.2 |
| — | Fallo de estado | `nvt_read_bld_hw_crc` (0x118fc, solo lecturas): 0x1fb533 (bit2 crc_done, bit0 ilm, bit1 dlm), golden 0x1fb500/0x1fb504, resultado 0x1fb520/0x1fb524; reintento completo (3 intentos) | — | Alta |

Omitido a propósito (no hace falta para que el FW arranque): `nvt_get_xm_htc_poll_info` (lectura THP, ko 0x11158), `update_pen_status`/comandos de lápiz,
`nvt_clear_fw_status`/`nvt_check_fw_status` (solo resume), `nvt_eng_reset` (0x5A→0x7FFF80, solo camino sin hw_crc).

## 4. Protocolo de transporte (RE del `.ko`, confirmado por la sonda)

| Operación | Bytes en el bus | Cita |
|---|---|---|
| `set_page(a)` | `FF [a>>15 &FF] [a>>7 &FF]` — **3 bytes** (el vendor no manda el 0x00 final que añadía el probe; ambos funcionan) | `nvt_set_page` 0x9a0; `CTP_SPI_WRITE` fija el nº de bytes del transfer = `len` (str w26 en 0x830, sin sobrescribir) |
| escribir `a ← p` | `[(a&0x7F)\|0x80] p…` tras `set_page(a)`, transferencia solo-TX | `CTP_SPI_WRITE` 0x754 (orr #0x80 en 0x7bc) |
| leer `n` bytes | full-duplex `[a&0x7F] 00×(n+1)`; datos en `rx[2:2+n]` | `CTP_SPI_READ` 0x4e8 (len+1 bytes, `memcpy(dst+1, rx+2, len-1)` en 0x6e8-0x6fc) |
| reintentos | 5 por transferencia si falla `spi_sync` (el script igual) | 0x7c8 / 0x55c |

SPI modo 0, 8 bits. Velocidad: vendor 19,2 MHz; el script usa **4 MHz por defecto** (la que ya funcionó en la sonda): 178 KB ≈ 0,4 s a 4 MHz, ≈ 0,1 s a 19,2 MHz
(Android: 115,8 ms). `--speed 19200000` para imitar al vendor una vez validado.

## 5. Qué hace el vendor con el display encendido (TDDI)

- El nodo del táctil **no tiene GPIO de reset**: el reset de la touch-MCU va con el del panel (`touch_reset_state`). El `bootloader reset` (0x69 → 0x1fb43e)
  es un reset **software de la MCU del táctil** por el registro SIF; no toca el pin de reset del panel.
- Android lo hace **con la pantalla encendida**: a los 3.64 s en el probe (con `cont_splash` activo, sin DSI_CMD_SET_ON) y a los 17.6 s en la descarga
  (DPMS en ON desde 9.54 s, `TDDI_FB_BLANK_UNBLANK` a 9.56 s); y, según el `.ko`, en cada `nvt_ts_resume` (el log termina a los 30 s, solo muestra el suspend de 25.1 s).
  No hay en los logs ninguna traza de efecto sobre el display (tampoco se puede ver un parpadeo en un log).
- Orden que implica el `.ko`: **panel inicializado → reset táctil + descarga**. Que un reset del panel borra el FW es una **inferencia** (el vendor recarga en cada resume y,
  en Linux, el FWINFO estaba sin inicializar tras nuestro panel), no una medida directa.
- Direcciones que escribe el script: 0x1fb4xx-0x1fb5xx, 0x1fc925, 0x11c4xx y SRAM 0x000000-0x0174d7 / 0x100000-0x11429f; ninguna coincide con un registro de display conocido
  (no hay mapa de registros del DDIC en este espacio para compararlas).

## 6. Riesgos

1. **Display (TDDI, mismo die)**: bajo. Mismo reset y mismas direcciones que el vendor con panel encendido. No verificado en Linux; el panel de Linux lo inicializa nuestro driver
   (distinto del de Android), así que un efecto visual no se puede descartar. Prueba con `--verify-only` primero (no resetea) y con la pantalla visible.
2. **Chip en bootloader sin FW** si la descarga falla o se mata el script: sin táctil pero recuperable reejecutando (empieza por `bootloader reset`). No bloquea el arranque ni el SPI.
3. **Perder el FW otra vez** por un reset del panel posterior (suspend/resume, DPMS que resetee): hay que reejecutar tras cada uno. El script, si ve el FW vivo, **no recarga** salvo `--force`.
4. **Un único cliente SPI**: no debe estar corriendo `uke-touchd.py` ni otro lector durante la carga (el vendor serializa con `bus_mutex`).
5. **Mensajes de 16 KB por spidev** y SE en FIFO/DMA de spi-geni: sin probar (la sonda hizo lecturas de ~5,4 KB). Si diera `EMSGSIZE`/error, bajar `--chunk` (4096 funciona igual: 125 transferencias).
6. **Velocidad 4 MHz** más lenta que el vendor: la espera de arranque (10 × 10 ms tras `boot_ready`) no depende de ella.
7. No hay riesgo de cuelgue CM3/SMMU por esto (solo SPI de usuario, sin MMIO). No se toca `/dev/ttyACM0`, slots, ni boot.img.

## 7. Qué se probó en el PC y qué NO está verificado

Probado (PC, 18-oct): `uke-touch-fwload.py --fw <bin> --parse-only` → cabecera = log de Android (partition 16, info 14, need_write 0x3c000, FW_VER 0x11), 4 CRC OK;
`--dry-run` → 59 transferencias, 178040 B, mayor transferencia 16257 B (< 16384), **SRAM virtual reconstruida desde los bytes del bus = idéntica al bin** para las 4 particiones,
registros DES/LENGTH/G_CHECKSUM con los valores esperados; `--dry-run --verify-only` → 28 transferencias de solo lectura; sin `--execute` el script se niega a escribir.

**NO verificado (solo la tablet lo cierra):**
- que el chip arranque con esta secuencia en Linux (nada se ha ejecutado en hardware);
- que 16 KB por transferencia y 4 MHz funcionen con spidev + spi-geni de la uke; que la espera de 35 ms/10 ms baste (el vendor usa 5 ms: es un margen mayor);
- el efecto sobre el display en Linux (§6.1);
- los **nombres** de campos del mapa ([38] ILM_LENGTH etc.): inferidos por el papel de cada argumento de `nvt_set_bld_crc_bank`; los **valores** son exactos;
- la fórmula de overlays y el camino single/no-cascade (el script aborta si el bin o el chip no son cascade);
- que el FW siga vivo/si hace falta `nvt_get_xm_htc_poll_info` o comandos THP para que empiece a entregar frames (el vendor los lanza justo después de cargar; los frames THP y la IRQ 54 se miran con `uke-touch-probe.py --frames` **ajustando EVENT_BUF a 0x11c400**: el probe usa 0x125800 y está mal para este chip);
- el 0x00 final del `set_page` de la sonda frente a los 3 bytes exactos del vendor (ambos parecen aceptados; el loader usa el exacto).

## 8. Plan de prueba sugerido (con orden del dueño)

```bash
# 0. spidev ligado a spi0.0 (README paso 1) y el panel ya inicializado y estable; nadie más usando /dev/spidev0.0
F=/ruta/novatek_nt36532_o82_fw_csot.bin
python3 uke-touch-fwload.py --verify-only                 # solo lecturas: id, cascade, FWINFO en mapa cascade y single, BLD CRC
python3 uke-touch-fwload.py --fw $F --dry-run | tail -20  # (en el PC o en la tablet; no abre el dispositivo)
python3 uke-touch-fwload.py --fw $F --execute             # escribe; añadir --speed 19200000 solo tras una carga correcta
python3 uke-touch-fwload.py --verify-only                 # debe dar reset state 0xA0-0xAF y FWINFO fw_ver=0x11, PID=0x5993, 32000x21360
```
Criterio de «hecho»: `check_fw_reset_state` OK y FWINFO `fw_ver=0x11 ~fw_ver=0xEE`, 40×60, 32000×21360; después GPIO 54 con actividad y `uke-touch-probe.py --frames` (con EVENT_BUF cascade) con cabecera THP válida.
Códigos de salida: 0 ok · 2 id/bin no válidos (no escribe) · 3 descarga fallida tras 3 intentos · 4 FWINFO no coincide.
