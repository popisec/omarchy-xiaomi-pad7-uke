# C5b ciclo 8 — resultado (21-oct-2026 21:20, autorizado por el dueño; sin flash ni reinicio)
`c5-ciclo8.sh --go`: batería 99 %, sha iguales, chip-id OK, 0 faults SMMU/oops (también en 4208×3120), descarga limpia (0 módulos). Registros: `out/c5-ciclo8-*.txt`, dmesg `out/c5c8-dmesg-2120.log`.

## Medido
- **El sensor acepta la configuración y sigue transmitiendo**: en los 7 streams, a +50 y +400 ms, `0100=01`, `0103=00`, `0305=af`, `0323..0327=04 01 a4 81 04`, `3012=07 3013=32`, `4837=0e`, `4800` = lo escrito; `5080=80` con patrón / `00` sin él; `4008=00` (2104×1560) o `02` (4208×3120). Sin lecturas `ffff`: I2C y reset correctos.
- **0 bytes y LONG=SHORT=CRC=ECC=0 en los 7.** (Línea `RESUMEN`: M = 2104×1560, F = 4208×3120, B = patrón de test, A = imagen normal.)

| stream | SOT | SOT4 | OVF |
|---|---|---|---|
| M B | 0 | 0 | 0 |
| M A | 273 | 6 | 0 |
| F B | 0 | 0 | 272 |
| F A | 176 | 2 | 14 |
| X 4800=0x44 (B) | 0 | 0 | 266 |
| X 4800=0x60 (B) | 117 | 0 | 49 |
| X 4800=0x24 (B) | 79 | 0 | 8 |
- Modo 4208×3120 (el de Android) **no cambia** el cuadro: sin paquetes, mismo SOT/OVF que 2104×1560.
- **Patrón de test: SOT=0 pero OVF alto (F B 272, X 0x44 266)** ⇒ las lanes empujan bytes al FIFO sin que el RX capture jamás la palabra de sincronía (SOT) — datos HS que el receptor no alinea. **Con imagen normal sí hay SOT** (273 / 176).
- **`0x4800` tiene efecto real** (único cambio que mueve SOT con patrón de test): borrar el bit 2 (0x60) o el bit 6 (0x24) da SOT 117 / 79 donde la base (0x64) da 0; borrar el bit 5 (0x44) no cambia nada. Los bits de 0x4800 no están descritos en ninguna fuente que tenga (hipótesis: el ciclo no identifica su significado).

## Lectura (hipótesis)
H-SENSMODE (modo/registros del sensor) **refutada en su forma simple**: la configuración está bien aplicada y el modo de Android no ayuda. Pero el control MIPI del sensor (`0x4800`) sí modifica lo que el receptor percibe, y el comportamiento «bytes en FIFO sin SOT» con patrón de test sugiere que el sensor y el PHY **no coinciden en el protocolo de las lanes** (p. ej. reloj de lane continuo/discontinuo o secuencia LP→HS que el PHY no sigue), no un error de configuración de registros. Con esto, 4 ciclos (5–8) sin un solo paquete: la hipótesis «PHY/receptor mal configurado» sigue abierta pese a todo lo probado.

## Siguiente (ciclo 9, propuesto; no preparado)
Barrido de `0x4800` bit a bit (base 0x64 ± cada bit: 0x65, 0x66, 0x60, 0x6c, 0x74, 0x44, 0x24, 0xe4) en imagen normal y con patrón, con settle calculado y con skew; y obtener las tablas OFILM reales extrayendo la librería de sensor de Android (`/vendor/lib64/camera/*ov13b10*`, solo lectura con `adb`, requiere orden del dueño: la tablet tendría que arrancar Android).
