# C5b ciclo 9 — resultado (21-oct-2026 21:51, autorizado por el dueño; sin flash ni reinicio)
`c5-ciclo9.sh --go` (módulos de `out-ciclo8`): batería 99 %, chip-id OK, 0 faults SMMU/oops, descarga limpia (0 módulos). Registros: `out/c5-ciclo9-*.txt`, dmesg `out/c5c9-dmesg-2151.log`. `0x4800` relevido = escrito en cada stream.

## Medido (22 streams; **0 bytes y LONG=SHORT=CRC=0 en todos**; M 2104×1560, settle calculado; B = patrón, A = normal; `SOT4` = mensajes con SOT en las 4 lanes)
| 0x4800 | bit alterado | B: SOT / SOT4 / ECC / OVF | A: SOT / SOT4 / ECC / OVF |
|---|---|---|---|
| 0x64 base | — | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 147 |
| 0x65 | 0 | 74 / 12 / 0 / 41 | 0 / 0 / 0 / 162 |
| 0x66 | 1 | 39 / **35** / **35** / 0 | 0 / 0 / 0 / 227 |
| 0x60 | 2 | 110 / 0 / 0 / 1 | 126 / 0 / 0 / 1 |
| 0x6c | 3 | 4 / 0 / 0 / 153 | 13 / 0 / 0 / 174 |
| **0x74** | **4** | **335 / 148** / 2 / 58 | **344 / 122** / 1 / 58 |
| 0x44 | 5 | 0 / 0 / 0 / 135 | 0 / 0 / 0 / 172 |
| 0x24 | 6 | 39 / 0 / 0 / 9 | 32 / 1 / 0 / 8 |
| 0xe4 | 7 | 0 / 0 / 0 / 235 | 0 / 0 / 0 / 157 |
| skew + 0x60 | | 134 / 0 / 0 / 1 | 158 / 0 / 0 / 1 |
| skew + 0x24 | | 47 / 0 / 0 / 15 | 88 / 2 / 0 / 28 |

## Lectura (hipótesis)
- **El bit 4 (0x10) de `0x4800` es el que más mueve el receptor**: con 0x74 las **4 lanes sincronizan (SOT4 148/122) tanto con patrón como con imagen normal**, el FIFO desborda solo 58 veces y ECC≈0. Es la primera variante donde el receptor ve una transmisión alineada en las 4 lanes de forma estable en ambos modos, aun sin decodificar paquetes.
- **El bit 1 (0x02, 0x66) produce cabeceras que llegan** (SOT4=35 con **ECC=35**: el RX ve un paquete en las 4 lanes y su cabecera falla el ECC) en patrón: indicio de que con ese bit la trama empieza a alinearse.
- Bits 5 y 7 y la base: sin SOT (OVF alto): sin sincronía. Bit 2 (0x60) y bit 6 (0x24): SOT en una lane, sin SOT4. Skew no aporta sobre 0x60/0x24.
- Sigue siendo hipótesis: no hay datasheet con el mapa de bits de 0x4800 y la variación entre arranques es grande (la base dio SOT 273 en un stream del ciclo 8 y 0 aquí); pero 0x74 repite en los dos modos y 0x66 en uno, lo que se separa del ruido.

## Siguiente (ciclo 10, propuesto; no preparado)
Combinar los dos bits que mejoran el receptor: **0x76 (bits 1+4)**, más 0x72 y 0x7e como vecinos, en B y A, repitiendo 0x74 y 0x66 como referencia en el mismo arranque; con settle calculado y con skew. Criterio de éxito: LONG/SHORT o bytes > 0. Techo de la familia «control MIPI del sensor»: este era el 2.º ciclo; el 3.º es el 10.
