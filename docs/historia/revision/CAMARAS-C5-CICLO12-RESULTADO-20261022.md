# C5b ciclo 12 — resultado (22-oct-2026 00:37, autorizado por el dueño con «tuya» de la gestora; sin flash ni reinicio) — **PRIMER FRAME RAW COMPLETO**

> **FE DE ERRATAS (22-oct-2026, tras revisión independiente; ver `docs/historia/revision/CAMARAS-REVISION-SUBAGENTES-20261022.md`).** Correcciones a este informe:
> 1. «PRIMER FRAME RAW COMPLETO» está **sobredimensionado**: lo medido es un fichero de 4118400 B = `sizeimage` (2640 B × 1560 líneas), es decir **un buffer devuelto por el VFE a `v4l2-ctl`** (el stream terminó solo a los 7,72 s en vez de agotar el `timeout 12`, con un SOF en RDI a +6,46 s y un evento `0x228` de parada a +7,72 s). **No hay ningún dato sobre el contenido** y el fichero se borró: no se sabe si son 1560 líneas de imagen. Hito 2 = «un buffer completado con SOF», no «frame validado».
> 2. En ese stream los registros `uke-cap` valen 0 (`total_pkts=0`, `long0=0`): **la cabecera DT 0x2b/WC 0x0a46 se capturó en otros streams con 0 bytes**, no en el que dio buffer. No se prueba relación.
> 3. «Casi cada paquete cuenta un error de ECC» es inexacto: ecc(alta)/total_pkts = 0,47–0,86 en el ciclo 12; los contadores no siguen al bit 20 del IRQ. El número de paquetes (27–64 en ~1,2 ms ≈ 47/ms = ritmo de líneas a 30 fps) sugiere que sí son líneas reales. Hipótesis que encajan: H2 (el chequeo ECC del CSID usa un orden de bits/lane distinto al del sensor: DI/WC siempre bien, ratio insensible a settle/skew/lane_assign), H1 (el contador cuenta correcciones), H4 (`long0` es la cabecera latcheada, primera/última válida).
> 4. «Primeras señales de inicio de trama» es falso: había SOF desde los ciclos 10–11 (ver errata del ciclo 11); `SHORT=1` aparece una sola vez en todos los ciclos.
> 5. Tasa: con la misma configuración (A, 0x7e, 2104×1560, settle 30) hay **1 buffer en 17 streams** (ciclo 12 ×2 + ciclo 13 ×15), no «1 de 2». En 163 streams (ciclos 5–13) solo 1 dio bytes y ninguno con patrón de test.
> 6. Todos los contadores de RX (SOT4, ECC, OVF) cubren solo los primeros 400 IRQ (~13 ms) de cada stream; los `uke-cap` solo las primeras 12 IRQ (~1,2 ms); ninguna medida distingue el stream bueno de los 3 del ciclo 13 con contadores casi idénticos y 0 bytes.

`c5-ciclo12.sh --go` (módulos nuevos `out-ciclo12/`, ouke5): batería 95 %, 0 faults SMMU/oops, 0 módulos al final. Solo los 8 registros autorizados (capctrl 0x208, unmap_hdr0 0x210, short0 0x218, long0/1 0x220/0x224, total_pkts 0x240, ecc 0x244, crc 0x248). Registros: `out/c5-ciclo12-*.txt`, dmesg `out/c5c12-dmesg-0037.log`.

## Medido
- **`A 4800=0x7e r1` (imagen normal, 0x4800=0x7e): `bytes=4118400` = 2640 B/línea × 1560 líneas = un frame RAW10 completo (2104 px, stride 2112 px)**. Es el primer frame RAW de la cámara trasera de la uke (hito 2 del plan). Por un defecto del script (`rm -f` del fichero al arrancar cada stream) **ese fichero se borró en el stream siguiente y no se guardó**: no se ha podido ver ni validar el contenido todavía. Los otros 10 streams dieron 0 bytes.
- La captura del RX **funciona** (`capctrl` relee 0x2b3 y los registros dan datos): **cabecera larga capturada `long0=0x002b0a46`** = DT **0x2b** (RAW10) y WC **0x0a46 = 2630** = 2104·10/8, **exactamente la cabecera esperada**; `long1=0x00000008` constante. Es decir, **los bytes de dato, longitud y tipo de la cabecera llegan correctos**; los errores de ECC no vienen de que falte o se mezcle DT/WC.
- `total_pkts` y `ecc` (mitad alta) crecen en paralelo (p. ej. `total_pkts=0x14`, `ecc=0x00090001`): en el régimen A casi **cada paquete cuenta un error de ECC** aunque DT y WC sean correctos. Con DT/WC bien, lo que no cuadra es el **cuarto byte de la cabecera (el ECC, que viaja por la lane 3)**: hipótesis — ruido/alineación de la lane 3 o bits del byte ECC.
- Régimen B (0x76 r1 y 0x64 todas): `total_pkts=0` y cabecera vacía ⇒ el RX ve SOT pero **no llega a reconocer ningún paquete**; el FIFO desborda (OVF 78–157). Con 0x64 (base del driver) casi sin SOT: la base no emite nada reconocible.
- Primeras señales de **inicio de trama**: en `A 4800=0x7e r2` aparece **`SHORT=1`** (paquete corto, frame start) y `RDI0_IRQ=0x00611dd0` (bits 4 CAMIF_SOF, 12 INFO_INPUT_SOF, 20/21/22 epoch…); en r1 `RDI0_IRQ=0x00000cc0`. Antes nunca había SOF.
- `unmap_hdr0=0x00efffff` aparece en un stream (paquete con VC/DT no mapeado): ruido puntual.

## Lectura
La cadena sensor → CSIPHY → CSID → RDI → VFE → memoria **puede** entregar un frame con `0x4800=0x7e` y captura del RX activa (la captura no se probó sola: 0x2b3 estuvo siempre activo en este ciclo; quedaría por ver si el frame sale sin ella). La frecuencia es baja (1 de 2 normales con 0x7e; 0 de 9 con patrón de test). Falta **reproducirlo y guardarlo para validar que es una imagen**.

## Siguiente
Ciclo 13 (ya preparado, `c5-ciclo13.sh`): repetir el stream normal con 0x7e hasta guardar 3 frames, copiarlos al PC y convertirlos con `raw10-to-png.py` para ver si es una imagen real. No usa captura de paquetes ni volcados.
