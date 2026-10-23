# ADD2 — `fs19xx.fsm`, secuencias, DAI/machine, TPLG y gap mainline (2026-10-17, noche)

> **ERRATA (AUDIT-ADD2-20261017, recomputado):** idx25 de calibración = `0x484A/0x4042`
> (no `0x48CA/0x4072`); §1.6 — la rama directa `0xF0xx` **sí** se usa (solo `fsm_reg_case`
> es inalcanzable). Resto del audit: PASS (CRC, slices, escenas, PLL, DAI, machine).

Adenda a `RE-AUDIO-WCD939X-FS19XX.md` y `ADD1-DECOMP` (no los modifica).
Todo lectura sola: Ghidra ya volcada (`decomp-fs19xx/`, 127 fns), `.ko` vendor,
blob `fs19xx.fsm` (4828 B), DT Android, mixer XMLs de cosecha, 3 comandos adb
de solo lectura. Direcciones = offsets en `.text` según symtab del `.ko` (NO las direcciones Ghidra 0x10xxxx, que usan otra base).

Artefactos NUEVOS (esta fase, en `artifacts/audio/`):
`fsm-blob-parser.py`, `fsm-blob-decoded.txt` (38 l.),
`fsm-blob-decoded-full.txt` (842 l.: las 51+150 entradas × 4 amps),
`fs19xx-pll-table.txt` (`g_fs19xx_pll_tbl`, 11×(A1,A2,A3)),
`fs19xx-mainline-skeleton.c` (borrador, TODO-1..7), `dts-fs19xx-add2.dtsi`.

## 1. Formato del blob de presets (HECHO; parser propio verifica todo)

### 1.1 Cabecera (offsets de fichero; `fsm_parse_preset @0x191C`)

| Offset | Tamaño | Valor en uke | Significado |
|---|---|---|---|
| 0x00 | u16 LE | `0x0100` | versión cabecera ("1.0") |
| 0x02 | 8 B ASCII | `onlybsg\0` | nombre de proyecto (`__dest+1`) |
| 0x0A | 2 B ASCII | `1\0` | nº de proyecto (`__dest+5`) |
| 0x0C | 6 B | `FE…` | relleno |
| 0x12 | u32 LE | `0x7E88727A` | fecha/código: año=2024 mes=8 día=14 f1=9 f2=58 (bitfields `>>20,>>16&F,>>11&1F,>>6&1F,&3F`) |
| 0x16 | u16 LE | 4828 | longitud total (= tamaño fichero; si ≠ falla) |
| 0x18 | u16 LE | `0x912E` | checksum (si ≠ falla con `checksum(%04X) not match(%04X)`) |
| 0x1A | u16 LE | 4 | nº de slices de device |
| 0x1C… | 4×(u16 off, u16 tipo) | `2C,0 / 4D8,0 / 984,0 / E30,0` | dir de devices, offsets ABSOLUTOS, tipo 0 |

### 1.2 Checksum (HECHO, verificado en Python contra el `.ko`)

`fsm_calc_checksum @0xBD0` + bucle de `fsm_parse_preset`: **CRC-16/MODBUS
(poly 0xA001 reflejado, init 0)** sobre bytes `[0x1A, fin)`. La tabla
`g_crc16table` NO es la del kernel: es propia del módulo
(`rodata+0x18B6`, `tab[1]=0xC0C1`; poly 0x1021 da `0x5E28` ≠ almacenado).
Recomputado: `almacenado 0x912E == calculado 0x912E` → **OK**
(`fsm-blob-parser.py` lo re-verifica en cada ejecución).

### 1.3 Slice por amp (`fsm_init_dev_list @0x11C8`: `slice = base+off`, match por I2C)

| Slice | Offset | `+0x1E` = addr I2C | Tamaño |
|---|---|---|---|
| 0 | 0x002C | 0x36 | 0x4AC (1196 B) |
| 1 | 0x04D8 | 0x37 | 0x4AC |
| 2 | 0x0984 | 0x34 | 0x4AC |
| 3 | 0x0E30 | 0x35 | 0x4AC |

`+0x1A`=nsec(3). Dir de secciones en `+0x28/+0x2A` por pares
(u16 off relativo a `slice+0x28`, u16 tipo): **tipo 1 = info (17 words),
tipo 2 = registros comunes (51), tipo 3 = registros por escena (150)**
(`fsm_get_data_list @0x1504`, `fsm_write_reg_tbl @0x1DA4`). Tablas en
`slice+0x28+off`: tipo1@+0x0C, tipo2@+0x30, tipo3@+0xFE en los 4.

### 1.4 Escenas por amp (HECHO blob + mixer; esquina INFERIDA fuerte)

Tipo 3: registros de 6 B `(u16 mask_escena, u16 desc_reg, u16 val)`; solo se
escriben los de la escena activa (`mask & escena`). 150 = 10 escenas × 15 regs,
agrupados y en orden ascendente. Máscaras por amp:

| Amp I2C | Escenas (bit→nº) | Propias |
|---|---|---|
| 0x34 | 0,1,2,3,4,5,6,**7,8**,15 | 7, 8 |
| 0x35 | 0,1,2,3,4,5,6,**9,10**,15 | 9, 10 |
| 0x36 | 0,1,2,3,4,5,6,**11,12**,15 | 11, 12 |
| 0x37 | 0,1,2,3,4,5,6,**13,14**,15 | 13, 14 |

Mixer (`odm-mixer_paths_overlay_static.xml`, HECHO): `speaker`=escena 0/vol 243,
`speaker-tl`=7, `speaker-tr`=9, `speaker-bl`=11, `speaker-br`=13 (vol 235),
`speaker-mono-2`=1, `handset`=15 (+`FSM_SW_GPIO`=1). Cadena escena→slice:
**0x34=TL, 0x35=TR, 0x36=BL, 0x37=BR** (INFERIDO: la correlación
mixer-path→escena→máscara es HECHO; choca con el orden supuesto de los nombres
pinctrl en `dt-fs19xx-props.txt`, que queda NO VERIFICADO). Escenas pares
8/10/12/14 y 2,3,4,5,6: sin uso en mixer (¿fábrica/paisaje/ultrasonidos?) —
NO VERIFICADO. Escena 15 (handset) existe en los 4 slices.

### 1.5 Respuesta a la pregunta del objetivo: ¿portar `fsm_parse_preset`?

**No.** El parser es trivial (cabecera + CRC + 3 tablas) y ya está replicado en
`fsm-blob-parser.py`. El port debe **pre-extraer las tablas a C** (51 comunes +
10×15 por amp; ver `fsm-blob-decoded-full.txt`). Falta un `--emit-c`
(TODO-1 del skeleton). Solo 2 regs de la tabla común difieren por amp
(idx 24: reg `0x1A` = `33/11/22/00`; idx 25: reg `0x1C` = `4C4E/4446/48CA/4072`
para 0x36/0x37/0x34/0x35): calibración por esquina, no promediar. Info (tipo 1)
idéntica salvo word[16] (`4/1/8/2` = índice de posición por amp) — INFERIDO.

### 1.6 Codificación de registros (`fsm_reg_update_bits @0x950`; I2C 8-bit addr + 16-bit BE en cable, `fsm_i2c_reg_write @0x55BC`)

`desc` de 16 bits: `ancho-1 = bits15:12, shift = bits11:8, addr = bits7:0`
(RMW: `val = (old & ~m) | (v<<shift & m)`). `0xF0xx` = write completo 16 bits;
`0x0F3C`-estilo = 1 bit (p.ej. bit 15 de `0x3C`). Las ramas de escritura
directa/`fsm_reg_case` (delays/polls) son **inalcanzables** con este blob
(HECHO por análisis de condiciones; ningún registro las dispara).

## 2. Spec init→enable→volumen→mute→shutdown (HECHO por decompilado)

| Paso | Función @off | Registros y valores |
|---|---|---|
| probe HW | `fsm_i2c_probe @0x6F6C` | vddd on → reset low,10 ms,high,1 ms → DEVID=`reg 0x03` (`&FFF0==5B0`, alto en `05/06,0B/17,29`) |
| reg_init | `fs19xx_reg_init @0x390C` | `0x10←2`, leer, 15 ms, `0x10←1`, poll **`0x0E`→3/0x300** (5 intentos) → `0x14←re25<<1` (re25=info[2]=`0x102`) → tabla común + tabla escena |
| i2s | `fs19xx_start_up @0x3BF0` | srate→bits `0x17[15:12]`: 8000→1, 16000→3, 32000→7, 44100→8, **48000→9**, 88200→10, 96000→11, 176400→12, 192000→13; bit 11 de `0x17` = update |
| pll | id. | bclk=rate·width·4 (+0x20 si 32 kHz) → idx 0..10 (256000…12288000); trío `0xA1/A2/A3` bajo `access_key`  (**tabla `g_fs19xx_pll_tbl @rodata+0x1AD8`: EXTRAÍDA, ver artefacto `fs19xx-pll-table.txt`) |
| enable | id. | `0x11←0xEF`, `0x10←0`, volumen, `0x30←0x210`, 10 ms, RMW `0x4C`, RMW `0x34C` según escena |
| volumen | `fsm_config_vol @0x21F8` | global 0..255 (clamp); variante vieja `0x06←vol<<8`, uke **`0x16←(vol<<8)\|0xC0`** (ó `\|0x80` si devid>>8==`0x17`) |
| mute | `fsm_mute_stream @0x6DC8` | playback: mute=0→`speaker_onn`, mute=1→`speaker_off`; capture se ignora (log) |
| escena | `fsm_set_scene @0x28F0` | `speaker_off` (si on), 20 ms, `mask=1<<n`, `shut_down` si cambia, `switch_preset` en amps con `mask&dev_mask`, `speaker_onn`. Quirk: escena 0 con cierto flag → máscara `0x10` (NO VERIFICADO uso) |
| shutdown | `fs19xx_shut_down @0x4144` | `0x30←0x310`, `0x10←1`, 35 ms, `0x11←0` |
| calib | `fs19xx_pre_calib @0x41B8` | limpia bits `0xF3C`, `0xE4C/0x34C` (`0x4C`), `0xEBC/0xFBC` (`0xBC`); fija `0x34C`; `dev_scene=0` |

Valores live de referencia (tinymix + mixer, HECHO): idle `Scene 0, Volume 255,
Stop On, AMP_ON Off`; música `Scene 0/243`, esquinas `7/9/11/13/235`.

## 3. DAI/driver ASoC vendor y qué escribir (HECHO por relocs del `.ko`)

`fsm_codec_register @0x4FB4`: `snd_soc_register_component(dev,
&soc_codec_dev_fsm, &fsm_aif_dai, 1)` — **1 DAI**, solo el primer amp
(`misc_register` + `set_smartpa_codec` + `set_smartpa_type("fs19xx",7)`).
Codec driver = solo `{probe @+0x38 →.text+0x6B3C, remove @+0x40}` (relocs
ABS64 en `.data+0x120/0x128`); `probe` añade **7 kcontrols** (`fsm_snd_controls
@rodata+0x1CF0`, 7×80 B, `SOC_SINGLE_EXT` con `snd_soc_info_volsw`):
`FSM_Scene/Volume/Stop/AMP_ON/Rotation/Ultrasound_Enable/SW_GPIO` (nombres por
relocs a rodata: `0xEBE/0x89F/0x15B2/0x7D3/0xE9F/0x13F4/0x120D`).

### 3.1 `fsm_aif_dai` (`@.data+0x258`, 224 B; `.name→"fs16xx-aif"` reloc +0x00)

Streams: `capture.stream_name→"AIF Capture"` (+0x80), `playback→"AIF Playback"`
(+0xA8); `.ops→fsm_aif_dai_ops` (+0x70). Formatos **`0x100000444` =
S16_LE|S24_LE|S32_LE|S24_3LE** (bits 2,6,10,32, `asound.h` del árbol k52).
Rates: máscara `0x7FE` + `constraint_list` de **6: 8000/16000/32000/44100/48000/
96000** (`fsm_constraints @rodata+0x1FD8` = `{list→0x1FE8, count=6}`).
Canales 1..4 INFERIDO (u32s crudos; layout vendor ≠ k52, no se afirma).

### 3.2 `fsm_aif_dai_ops` (`@rodata+0x1F20`, 184 B; 6 relocs, offsets propios)

| +off | Función @.text | Semántica (decompilado) |
|---|---|---|
| 0x00 | `set_sysclk @0x6D34` | solo log, return 0 |
| 0x20 | `set_fmt @0x6D68` | solo log, return 0 |
| 0x60 | `mute_stream @0x6DC8` | on/off altavoces (ver §2) |
| 0x68 | `startup @0x6E14` | `constraint_mask64(FORMAT)` + `constraint_list(rates)` |
| 0x70 | `shutdown @0x6EA0` | noop |
| 0x78 | `hw_params @0x6EA8` | `set_i2s_clocks(rate, rate·width·4)` → `start_up` (i2s+pll+enable) |

OJO: estos offsets **no coinciden** con `struct snd_soc_dai_ops` de k52-7.2
(set_sysclk=+0x20 allí); el vendor (GKI anterior) usa otro layout — NO portar
offsets, portar el CONJUNTO de 6 ops. NO VERIFICADO: versión exacta del GKI
vendor (modinfo sin vermagic legible en el volcado).

### 3.3 Machine (`machine_dlkm.ko` + DT + `proc-asound.txt`)

Tarjeta **`cliffs-mtp-snd-card`** (DT `qcom,model`; `qcom,pineapple-asoc-snd`),
53 links. Smartpa: `set/check_smartpa_type`, `smartpa_type="fs19xx"`;
`smartpa_dai_link_select` → **3 links TDM-VA con codec `fs16xx.4-0034` dai
`fs16xx-aif`**: `TDM-LPAIF_VA-RX-PRIMARY`, `TDM-LPAIF_VA-RX-PRIMARY-VIRT-2`
(playback) y `TDM-LPAIF_VA-TX-PRIMARY` (capture) — strings HECHO.
Props DT que lee (HECHO `dt-sound-nodes.txt` §3): `qcom,model`,
`asoc-codec-names` (`msm-stub-codec.1, lpass-cdc, wcd939x_codec, wsa-codec1/2`),
`qcom,wsa-max-devs=0`, audio-routing, mi2s/auxpcm/tdm-intf, mbhc, dmic-gpios,
`wcd939x-i2c-handle`. WSA inerte (`wsa_max_devs=0`, macros disabled).

## 4. TPLG (HECHO, tablet solo lectura)

- `find /vendor /odm -iname '*tplg*'` → **vacío** (17-oct-2026, adb root).
- `find / -maxdepth 4 -iname '*tplg*'` → **vacío**.
- `/vendor/firmware_mnt/image/adsp.b00…bNN` presentes → DSP AudioReach: el grafo
va **dentro del FW del ADSP**, sin `.tplg` separado (coherente con fase 1).
- Dónde iría en mainline: `/lib/firmware/qcom/cliffs/*` o topología embebida en
la machine (`q6apm + topology.c` existen en k52, ver §5). Sin pull posible: no
hay fichero que traer. **Nada que portar aquí; gate = PCM capture por VA-TX
con UCM mínimo antes de pensar en topology.**

## 5. Gap mainline (k52-L16 = 7.2-rc2, HECHO por grep) y orden de ataque

1. **FS16xx: NO existe.** `fs210x.c` solo `0x20/0x45` (FS2105S/FS2104); el
fsm-vendor (escenas/sync-4-dev/misc/mievent) no es reutilizable. Vía barata:
nuevo `fs19xx.c` mínimo (probe+DEVID+reg_init+6 ops+7 kcontrols+tablas
horneadas) o extender `fs-amp-lib`. Gate: `i2cdump 4 0x34` lee `0x03`
(solo lectura, root) para fijar DEVID antes de escribir el match.
2. **Machine pineapple+wcd939x+FS: NO existe.** k52 trae hasta `x1e80100.c`
(sin `wcd93xx`/smartpa; no hay `sm8550/sm8650`). Hay que escribirla:
3 links TDM-VA + BEs `q6apm` + auxiliares wcd939x. Gate: reutilizar
`sc8280xp.c`-estilo como plantilla de link VA.
3. **WCD939x: SÍ existe** (`wcd939x.c` + `-sdw.c`, variantes 9390=`0x0`/
9395=`0x5`, compats `qcom,wcd9390/9395-codec`). Solo DT: traducir supplies
`cdc-vdd-{rx,tx,mic-bias,buck,px}` → `vdd-{rxtx,io,buck,mic-bias,px}` y
compat genérico → `qcom,wcd9395-codec` (variante INFERIDA 9395, §3 fase 1).
4. **q6apm/audioreach/topology: SÍ existen** (`qdsp6/` completo: `q6apm.c`,
`q6apm-lpass-dais.c`, `audioreach.c`, `topology.c`).
- Orden (barato primero): **(a)** BE `CODEC_DMA`/VA-TX contra ADSP con UCM
mínimo (PCM capture de mics; sin amps); **(b)** `fs19xx.c` mínimo
(DEVID+reset+irq/común+escenas 0/7/9/11/13, tabla PLL ya extraída);
**(c)** machine 3 links + UCM §2/valores mixer; **(d)** WCD939x RX/headset
al final (música por altavoz no lo necesita).
- Riesgos: DEVID real sin leer (bloquea
DEVID real sin leer (bloquea match exacto `17/29`); volumen `|0xC0` vs `|0x80`
depende de ese DEVID; offsets `dai_ops` vendor ≠ 7.2 (no copiar structs a ciegas);
escenas pares 8/10/12/14 sin uso conocido (no cablear en UCM hasta medir).

## Evidencia (trazabilidad)

Blob: `fsm_parse_preset @0x191C`, `fsm_calc_checksum @0xBD0`,
`g_crc16table @rodata+0x18B6` (`tab[1]=0xC0C1`), `fsm_write_reg_tbl @0x1DA4`,
`fsm_reg_update_bits @0x950`, `fsm_init_dev_list @0x3BC0`,
`fsm_init_info @0x3FB4`; parser + salidas en artefactos (CRC re-OK).
Secuencias: `fsm_i2c_probe @0x6F6C`, `fs19xx_reg_init @0x390C`,
`fs19xx_start_up @0x65E8`, `fs19xx_shut_down @0x4144`,
`fs19xx_pre_calib @0x41B8`, `fsm_config_vol @0x4BF0`,
`fsm_mute_stream @0x6DC8`, `fsm_set_scene @0x52E8`,
`fsm_speaker_onn/off @0x2C9C/0x2B0C`, `fsm_stub_switch_preset @0x22F4`.
DAI: `fsm_codec_register @0x4FB4`, `fsm_codec_probe @0x6B3C`,
relocs ABS64 `.data+0x120/0x128/0x258/0x2C8/0x2D8/0x300`,
`rodata+0x1F20/40/80/88/90/98`, kcontrols `rodata+0x1CF0`,
`fsm_constraints @rodata+0x1FD8{count=6}` + rates `@0x1FE8`.
Machine: strings `TDM-LPAIF_VA-{RX-PRIMARY,RX-PRIMARY-VIRT-2,TX-PRIMARY}`,
`fs16xx.4-0034`, `fs16xx-aif`, `pineapple-asoc-snd`, `cliffs-mtp-snd-card`
(DT). TPLG: 2×`find` vacíos + `adsp.b0N` en `/vendor/firmware_mnt/image`
(comandos adb §4, 17-oct-2026). Mainline: greps §5 en k52-L16.
