# AUDIO — E8 preparado en el PC: driver de los 4 FS19xx (sin tocar la tablet) — 18-oct-2026

**Estado: compilado y verificado en el PC; NADA desplegado ni cargado.** Ninguna orden a la tablet en esta etapa.

## Qué se ha hecho
| Artefacto | Qué es | Verificación (PC) |
|---|---|---|
| `fs19xx/uke_fs19xx.c` → `out/uke_fs19xx.ko` (sha `073e4410…`) | Cliente I²C `foursemi,fs16xx` ×4 + códec ASoC `fs16xx-aif` (plataforma `uke,fs19xx-codec`) | compila con LLVM contra ouke4 (vermagic `…-ouke4`, depende solo de `snd-soc-core`), sin avisos |
| `dts/uke-audio-e8a-card-fs19xx.dtso`, `e8b-…-pins.dtso` | Tarjeta TDM con ese códec en vez del `spdif-dit` (e8b añade `uke_tdm1_active`, gpio6-9) | `build.sh`: dtc + fdtoverlay OK |
| `module/uke_audio_e7i2c.c`, `e8a`, `e8b` | Cargadores de overlay (enciende `i2c@88c000`; tarjetas) | compilan; los `.ko` previos (e7a `2c4705a3…`, e7b `1e3df887…`) salen **idénticos** |
| `fs19xx/dryrun.py` | Réplica Python de la validación y de la secuencia sobre el preset real | tamaño, CRC-16/MODBUS, 4 trozos y 51+150 descriptores por amp admitidos |
| `fs19xx/deploy.sh` | Solo ficheros: 4 `.ko` en `extra/` + `/lib/firmware/fs19xx.fsm`; `--check/--go/--revert` | modo sin conexión OK |

**Preset:** no se hornea. Se carga en ejecución (`request_firmware("fs19xx.fsm")`) y se valida; `deploy.sh` copia a la tablet el que ya está en `build/android/cosecha-20261017/audio/` (4828 B, sha `f319e71d…`). No se añade ninguna copia nueva al repo.

## Comportamiento (de qué se deriva cada cosa: ADD2 §2 y decompilados `decomp-fs19xx/`)
1. **Probe I²C (etapa 0):** `reset-gpio` del DT de Android (nivel crudo: bajo 10 ms, alto 1 ms) → lee `reg 0x03` (DEVID). Solo acepta familias **0x17xx/0x29xx** (las únicas con secuencia de arranque en el vendor); otro DEVID ⇒ probe falla. **No escribe nada más.** Parámetro `uke_fs_reset=0` omite el pulso.
2. **Códec (etapa 1):** el DAI solo actúa si `uke_fs_play=1`. Al desenmudecer: por amp `reg_init` (danza `0x10`=2/1, sondeo `0x0E`=3/0x300, `0x14`=re25<<1, tabla común, tabla de escena) → `start_up` (I²S `0x17`, PLL `0xA1-A3` bajo clave `0x0B`=0xCA91, `0x11`=0xEF, volumen, `0x10`=0, `0x30`=0x210, lógica del bit 3 de `0x4C` por escena). Al enmudecer: `shut_down` (`0x30`=0x310, `0x10`=1, 35 ms, `0x11`=0).
3. Solo 48 kHz con BCLK 6,144 MHz (4 slots×32 bit del ACDB; entrada PLL idx 9 `C000/005D/0260`). Mandos: `FS19XX Volume` (≤ `uke_fs_volmax`), `FS19XX Scene` (solo con el PCM parado).

### Desviaciones deliberadas del vendor (más seguras)
- **Volumen antes de salir de standby.** La tabla de escena deja `reg 0x16` al máximo (`RMW máscara 0xFFC0 ← 0xFFC0`, medido con `dryrun.py`); el vendor escribe el volumen *después* de `0x10←0`. Aquí va **antes**, con el tope `uke_fs_volmax` (defecto 0x80; inicial 0x40).
- `reg_init` en cada arranque (el amp está parado; INFERIDO que el vendor lo hace en `fsm_try_init`).
- Todo fallo en `init`/`start_up` ⇒ `shut_down` de los amps ya habilitados y error al PCM.
- Sin hilo de vigilancia, sin IRQ, sin `fsm_work_monitor` (vendor: temperatura/sobrecorriente) ⇒ solo pruebas cortas.

## Riesgos (ordenados)
| # | Riesgo | Prob./impacto | Mitigación / lo que NO sabemos |
|---|---|---|---|
| 1 | **Altavoces**: sin FSADSP ni monitor térmico; escala del volumen **INFERIDA** (255 = máx; Android usa 235-243) | media / **alto** (daño físico) | tope 0x80, inicio 0x40, contenido silencio o −40 dBFS, pruebas ≤ 3 s, `uke_fs_play=0` por defecto; **primera prueba con silencio** (`/dev/zero`). Con `uke_fs_play=1` el amp amplifica lo que reciba: sin pines no recibe reloj |
| 2 | Encender `i2c@88c000` en caliente (GENI SE11 + GPI DMA, SMMU) | baja-media / medio-alto (cuelgue duro; sin watchdog ⇒ reset físico) | INFERIDO (informe E7 y overlay): mismos interconnects/SMMU que el bus KTZ, que ya funciona. El parche 0001 es la vía definitiva (flash). **No medido** |
| 3 | Pulso de `reset-gpio` (GPIO 30/149/124/123 del TLMM) | baja / bajo | solo si `uke_fs_reset=1`; polaridad (bajo = reset) INFERIDA del vendor |
| 4 | DEVID real desconocido | media / bajo | si no es 0x17xx/0x29xx el probe falla sin escribir; se imprime el valor |
| 5 | `fsm_vddd` (1,8 V): el vendor pide el regulador; **no existe en el DT vivo** | media / medio | INFERIDO riel siempre encendido; si los amps no contestan es la 1.ª sospecha |
| 6 | **Mapa canal→slot→altavoz desconocido.** El PCM del frontend es de 2 canales (slot_mask 0x3) y hay 4 amps; el preset lleva `info[16]` = posición 8/2/4/1 (0x34/0x35/0x36/0x37) pero no se ha verificado qué slot lee cada uno | alta / bajo-medio (sonido en un subconjunto o duplicado) | requiere MFC/4 canales en el subgrafo TDM (siguiente etapa de topología); no impide la prueba de arranque |
| 7 | Pines TDM sin mux (E7b) y sin lectura de verificación (E3c) | — | `e8b` solo tras E3c + E7b; `e8a` no mueve pines |
| 8 | `rmmod` tras un oops de ASoC cuelga (`client_mutex`) | media / alto | no usar `rmmod` si hay oops; reiniciar |
| 9 | Detalles NO verificados del preset: sondeo `0x0E` (3 vs 0x300), escenas pares 8/10/12/14, escena 15 | media / bajo | `reg_init` falla cerrado si `0x0E` no llega; se registra el último valor |

## Procedimiento propuesto (cada paso lo autoriza el dueño; reglas de siempre: ACM un lector, vigía, doble captura, `dmesg -n 7`, sin `rmmod` si hay oops)
- **E8-0** `fs19xx/deploy.sh --go` (solo ficheros).
- **E8-1** `insmod uke_audio_e7i2c` (bus encendido; **aún sin driver**: los clientes quedan sin enlazar). Comprobar `dmesg` y `ls /sys/bus/i2c/devices/`. Revierte con `rmmod` o reinicio.
- **E8-2** `modprobe uke_fs19xx` con `uke_fs_play=0`: pulso de reset + lectura de DEVID + validación del preset, para cada amp. **Resultado esperado: 4 líneas «DEVID 0x…» y el DAI registrado.** Revierte con `modprobe -r uke_fs19xx`.
- **E8-3** `insmod uke_audio_e8a` + PCM de silencio con `uke_fs_play=0` (comprueba el mezclador y que `mute_stream` NO toca los amps).
- **E8-4** (después de E3c y E7b) `e8b` con `uke_fs_play=1`: silencio ≤ 3 s, luego −40 dBFS ≤ 3 s, con escucha y mano en el cable de carga. Se aborta ante cualquier error de I²C, calor o ruido anormal.

## Siguiente decisión del dueño
Autorizar **E8-0** (copiar ficheros) y, aparte, **E8-1/E8-2** (primer acceso al bus I²C de los amps; riesgo 2). E3c/E7b siguen pendientes para tener señal real.
