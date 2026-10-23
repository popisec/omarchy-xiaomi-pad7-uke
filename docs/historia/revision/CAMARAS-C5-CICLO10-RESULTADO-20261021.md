# C5b ciclo 10 — resultado (21-oct-2026 22:04, autorizado por el dueño; sin flash ni reinicio)
`c5-ciclo10.sh --go` (módulos de `out-ciclo8`): batería 99 %, chip-id OK, 0 faults SMMU/oops, descarga limpia (0 módulos). dmesg `out/c5c10-dmesg-2204.log`.

## Medido (18 streams; **0 bytes y LONG=SHORT=CRC=0 en todos**; M 2104×1560, settle calculado; entre paréntesis irq analizados de ≤400)
| 0x4800 | B: SOT4 / ECC / OVF / WECC | A: SOT4 / ECC / OVF / WECC |
|---|---|---|
| 0x74 (ref) | **220 / 207** / 0 / 0 (323) | 141 / 0 / 46 / 0 |
| 0x66 (ref) | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| **0x76** | **213 / 211** / 0 / 0 (325) | 149 / 7 / 40 / 1 |
| 0x72 | 3 / 0 / 24 / 0 | 1 / 0 / 15 / 0 |
| **0x7e** | **171 / 141** / 0 / 0 (291) | **221 / 206** / 0 / **31** (325) |
| 0x77 | 1 / 1 / 0 / 0 | 1 / 1 / 0 / 0 |
| 0x36 | 49 / 0 / 7 / 0 | 41 / 0 / 8 / 0 |
| 0x74 (repetida) | 134 / 1 / 49 / 0 | 122 / 0 / 37 / 0 |
| skew + 0x76 | 209 / **188** / 0 / 0 | **218 / 195** / 0 / **39** |
- **Cambio de régimen**: con 0x74/0x76/0x7e aparece un modo (no en todos los arranques de stream: 0x74 lo da en la primera B y no en la repetida) en el que **cada SOT de las 4 lanes va acompañado de un ECC error** (SOT4 ≈ ECC ≈ 210) y el FIFO ya **no desborda** (OVF=0). Es decir: el receptor encuentra el inicio de paquete en las 4 lanes y **lee una cabecera que no pasa el ECC**; además **`WARNING_ECC` (bit 14, errores corregidos de 1 bit) aparece 31 y 39 veces** (0x7e A, skew+0x76 A): cabeceras que a veces solo difieren en un bit.
- 0x66 y 0x77 no repiten (el 0x66 del ciclo 9 con SOT4=ECC=35 no se reprodujo: ruido entre arranques); 0x74 repetida cae de 220 a 134 SOT4 y a ECC≈0: **la señal depende del arranque** además del valor de 0x4800.

## Lectura (hipótesis)
H-SENSORCTRL (3 ciclos) cierra con resultado parcial: los bits 1, 3 y 4 de `0x4800` cambian la señal; el sensor acierta a emitir paquetes que el CSID **alcanza a enmarcar pero cuya cabecera sale con errores de 1 y de varios bits**. Eso se parece a un problema de **orden/alineación de bytes entre lanes o de temporización de muestreo del PHY**, no a «el sensor no emite». **Las pruebas de lane_assign (ciclo 7) y de settle se hicieron sin sincronía de SOT y por tanto no fueron informativas**: hay que repetirlas con el sensor en este régimen. Es una hipótesis, no una causa raíz.

## Siguiente (ciclo 11, propuesto; no preparado)
Con `0x4800` = 0x7e y 0x76: (a) **permutaciones de lane_assign** (las 24 son pocas: probar las 6 que dejan la lane de reloj fija o todas), (b) barrido de **settle** (10–60) y **skew**, midiendo ECC/WECC/LONG por stream, y repetir cada valor 2 veces (el régimen no es estable entre arranques). Criterio de éxito: LONG/SHORT o bytes > 0, o ECC→0 con SOT4 estable. Es una familia nueva (alineación de lanes en régimen sincronizado), no el cuarto intento de la anterior.
