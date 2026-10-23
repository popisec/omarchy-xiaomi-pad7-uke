# AUDIO — estado consolidado de los altavoces (E8) — 19-oct-2026 10:25

**Resultado: la ruta Linux→ADSP→TDM→FS19xx funciona hasta donde se puede medir, pero NO suena nada por los altavoces.** Todo lo de abajo está medido en la tablet, salvo lo marcado INFERIDO.

## Demostrado (funciona)
- Pila AudioReach en frío y persistente (`uke-audio.service` VERDE), SMMU del LPASS, relojes PRM, DMA con `hw_ptr` a 48 kHz, grafo `TDM_SINK` con los parámetros del ACDB (E7a).
- Pines TDM LPI gpio6-9 en función 2 (`CFG` 0x6c8/0x6c9 como se predijo, E7b); lectura/escritura MMIO del TLMM LPI estable.
- Bus I²C-4 operativo (overlay corregido) y **los 4 FS19xx contestan `DEVID 0x2900`**; driver propio `uke_fs19xx` (preset `fs19xx.fsm` por `request_firmware`, reg_init/start_up/shut_down del vendor, DAI `fs16xx-aif`, mandos de volumen y escena, debugfs `regs`/`ctl`).
- Los 4 amps se **habilitan y paran sin errores** (`rc 0`), el registro de volumen toma el valor (0x20…0xF3) y **detectan el BCLK**: con el PCM en marcha, en los 4 amps cambian los mismos registros (`0x00` 0200→0240, `0x0C` fe→69, `0x19` bit 7) respecto a «habilitados sin PCM» (D4-1).

## Descartado (medido)
- Nivel del tono (−40, −30, −24, −18 dBFS a vol 0xF3); 4 canales (slots 0-3, topología `UKE-tplg-4ch`); formato TDM (retraso 0/1/2 × sync 0/1/2 × inversión 0/1: 18 combinaciones, sin ningún cambio en los registros del amp ni sonido); línea de datos (lane_mask 1 y 2; 3 es inválido con 2 canales); `data_oe` (es un flag de compartición, no una máscara).
- **Método inválido (retirado):** leer `VALUE.IN` del LPI para ver el reloj (D2-1/D3-1/E3d): `IN` vale 0 siempre, incluso en pines libres con pull-up.
- Dato de 32 bit: S32 no se abre (el frontend `q6apm-dai` solo ofrece S16/S24); **S24 hace caer el `audio_process` del ADSP** (fatal) al arrancar el stream; tras el reinicio del ADSP con la pila cargada hay además un Oops en `q6apm_is_adsp_ready`/`pdr_indack_wq` (mainline no tolera el stop/start con la pila cargada).

## Lo que queda (INFERIDO, por orden)
1. **Cadena del grafo de Android**: antes del `TDM_SINK` hay `MFC` (0x07001015) → `SAL` (0x07001010) → `SPLITTER` → `LOG` con un mapa de canales `{1,2,8,9}` y `HW_EP_MF_CFG` de **32 bit/4 canales**; nosotros solo `LOG → TDM_SINK` con bit_width 16. El formato que llega al sumidero puede no ser el que el ADSP espera para sacar datos reales (el S24 reventó el ADSP: el módulo es sensible a esto). Requiere reconstruir el subgrafo (MFC + SAL, formato 32 bit) en la topología.
2. **Estado interno del amp**: no sabemos qué bits de `0x00/0x0C/0x19` son «PLL bloqueado», «I²S detectado», «fallo» o «mute»; sin hoja de datos. Una comparativa con el estado real de Android (adb root sobre la otra ranura) lo resolvería.
3. **Protección del altavoz** (`FSADSP` del vendor, módulos propietarios en el firmware): el amp podría quedar enmudecido a la espera de la calibración (no documentado).
4. Cableado de la línea de datos (SD0/SD1) y mapa de canales: sin datos.

## Estado de la tablet y del repo
Arranque limpio; `uke_fs_play=N` (los amps no se tocan salvo prueba autorizada); topología original (`c3ff8ed1…`); módulos de prueba (e7i2c, e3, e8b, uke_fs19xx…) **en `extra/` pero sin carga automática**; `snd-q6apm` con los parches 0005-0007 en `updates/` (parámetros `uke_tdm_*` modificables, `uke_tdm_lane=0` por defecto = comportamiento previo). Todo el trabajo commiteado; sin firmware ni ACDB en el repo.
## Recomendación
Seguir solo si el dueño quiere invertir en (1) (reconstruir MFC+SAL con formato 32 bit, medio-alto esfuerzo) o en (2) (arrancar Android en la otra ranura y volcar los registros de los amps con sonido real: requiere flash/ranura, fuera de las reglas actuales sin su decisión). Con lo medido, **no hay evidencia de un fallo de hardware**; el audio por altavoces es viable pero no está terminado.
