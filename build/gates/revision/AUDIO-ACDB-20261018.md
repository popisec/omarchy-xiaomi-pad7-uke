# AUDIO — ACDB `Forte` leído: parámetros del TDM del altavoz — 18-oct-2026

Orden del dueño. **Solo lectura**: `odm_b` (1,11 GiB, EROFS, sectores 2048..2338496 de `super`) se copió por SSH a `/var/tmp/uke-acdb/` del PC (fuera del repo); `erofs-utils 1.9.4` se compiló de fuentes (kernel.org) sin sudo; se extrajeron solo `/etc/acdbdata`, `/etc/audio` y `/etc/backend_conf.xml`. **Nada del ACDB, del qwsp ni de /etc/audio se ha commiteado**; aquí solo van valores derivados mínimos y el script de análisis.

## Qué hay
- `Forte_acdb_cal.acdb` (2,8 MB): contenedor **sin cifrar** (`ACDB` + trozos `HEAD/GKVT/GKVL/CSLU/CDLU/CDDE/CDDO/SCLU/SGIT/POOL/…`), con nombres de casos de uso (`DeviceRX_Speaker` = grafo 2, `DeviceTX_VI_TX` = 11, …).
- `Forte_workspaceFileXml.qwsp` (973 KB): **cifrado** (entropía 8,00 bits/byte), no se usa.
- `backend_conf.xml` (texto): `group_device TDM-LPAIF_VA-RX-PRIMARY rate=48000 ch=4 bits=32 slot_mask=15`; `TDM-LPAIF_VA-TX-PRIMARY` 4 ch/32 bit (retorno V/I).
- La definición de los módulos/parámetros viene del código abierto **AudioReach graph services** (BSD-3, `github.com/Audioreach/audioreach-graphservices`, `spf/api/modules/pcm_tdm_api.h`): `MODULE_ID_TDM_SINK = 0x0700100E`, `PARAM_ID_TDM_INTF_CFG = 0x0800101B` (struct de 28 B), `PARAM_ID_HW_EP_MF_CFG`, `PARAM_ID_TDM_LANE_CFG = 0x0800106A`, `PARAM_ID_HW_INTF_CLK_CFG`.

## Resultado — configuración TDM del altavoz (LPAIF_VA PRIMARY) en el ACDB (MEDIDO)
Estructura `param_id_tdm_intf_cfg_t` (bloques `[0][28]` en `POOL`), variantes por nº de canales (`slot_mask` 0x1/0x3/0x7/**0xF**):
| campo | valor | significado |
|---|---|---|
| `lpaif_type` | **3** | LPAIF_VA |
| `intf_idx` | **0** | PRIMARY |
| `sync_src` | **1** | INTERNAL (el SoC es maestro de BCLK/SYNC) |
| `ctrl_data_out_enable` | **1** | ENABLE |
| `slot_mask` | **0xF** (4 canales) | slots 0-3 |
| `nslots_per_frame` | **4** | |
| `slot_width` | **32** bit | |
| `sync_mode` | **0** | SHORT_SYNC_BIT_MODE |
| `ctrl_invert_sync_pulse` | **0** | normal |
| `ctrl_sync_data_delay` | **1** | 1 ciclo de BCLK (formato I²S/«DSP-A»-like) |
Más: `PARAM_ID_HW_EP_MF_CFG` del mismo grupo: **48 000 Hz, 32 bit, 4 canales, punto fijo** (bloque `bb80 | 0x40020 | 1`). BCLK resultante = 48 000 × 4 × 32 = **6,144 MHz**. (Existe además otra familia `LPAIF intf=1 (SECUNDARIA), sync_mode=1 (LONG), 4×32` para otro interfaz; no es el altavoz.)
Módulos del subgrafo del dispositivo (`SGIT`, subgrafo `0xb0000194`): `0x07001015`(iid 0x4032) → `0x07001010`(0x4589) → `SPLITTER 0x07001011`(0x4961) → `DATA_LOGGING 0x0700101A`(0x4b36) → **`TDM_SINK 0x0700100E` (iid 0x4b37)**; el `TDM_SINK` lleva los parámetros `HW_EP_MF_CFG`, `HW_EP_FRAME_SIZE_FACTOR`, `TDM_INTF_CFG`, `TDM_LANE_CFG` (1 carril por defecto), `HW_INTF_CLK_CFG`. Es la misma forma que los subgrafos de dispositivo de nuestra topología (HDK/QRD): solo cambia el módulo final (TDM en vez de I²S/CODEC_DMA).
**No** aparece en el ACDB ningún bloque del algoritmo `FSADSP` del amplificador FourSemi en este subgrafo del dispositivo: la protección (`speaker_protection_enabled=1`) va en el grafo del stream/PP del vendor (módulos propietarios de Xiaomi, `FSADSP … Spk:r0 tempr vbat f0 Q` en el firmware del ADSP); su calibración no es parte de lo que necesitamos para un tono de prueba, pero **sin ella no hay protección del altavoz**.

## Qué implica para E7 (altavoces)
1. **Subgrafo TDM en la topología**: sustituir en `UKE.m4` el subgrafo `device-i2s-playback` de `PRIMARY_MI2S_RX` por uno con `MODULE_ID_TDM_SINK` (0x0700100E) y los parámetros de arriba (hay que añadir el tipo de módulo y `PARAM_ID_TDM_INTF_CFG` a los m4/`audioreach.c`; el kernel de mainline no tiene TDM: parche en `audioreach.c`/`q6apm-lpass-dais.c` con un DAI `TDM-LPAIF_VA-RX-PRIMARY`).
2. **Pines**: LPI gpio6-9 función 2 (E3: ya `uke_tdm1_active` en el overlay e3; conflicto con DMIC01/23 en gpio6-9 función 1 por resolver).
3. **Amplificadores**: driver FS19xx (4× en I²C-4, `fs19xx.fsm`, reset/IRQ GPIO), configurados para recibir TDM esclavo 4 slots × 32 bit con retraso de 1 BCLK, slot por amplificador (`FSM_Scene` 7/9/11/13 = tl/tr/bl/br).
4. **Seguridad**: sin `FSADSP` limitar volumen a −40 dBFS como máximo en pruebas hasta tener la protección; E7 requiere varios ciclos de flash/I²C (presupuesto de docs/historia/AGENTS.md).

## Estado de ficheros locales (fuera del repo)
`/var/tmp/uke-acdb/`: `out/` (ACDB, qwsp, /etc/audio ≈ 31 MB), `erofs-build/` (herramientas), `ags/` (clon BSD-3), `odm_b.img` (se borra). No se subió nada.
