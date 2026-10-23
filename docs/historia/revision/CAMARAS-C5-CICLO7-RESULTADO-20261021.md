# C5b ciclo 7 — resultado (21-oct-2026 21:08, autorizado por el dueño; sin flash ni reinicio)
`c5-ciclo7.sh --go`: batería 100 %, sha iguales, chip-id OK, 0 faults SMMU/oops, descarga limpia (0 módulos). Registros: `out/c5-ciclo7-*.txt`, dmesg `out/c5c7-dmesg-2108.log`.

## Medido (16 streams, ≤400 IRQ cada uno; columnas: SOT = mensajes con algún bit 4–7, SOT4 = los 4, ECC bit 20, OVF desbordes)
- **0 bytes y LONG=SHORT=CRC=0 en los 16.** Ni paquete corto (frame start) ni largo en ningún valor.
- **Settle** 10/19/25/30/40: SOT≈0–2, OVF crece con el settle (0 → 36 → 148 → 161 → 323); a 60 solo 57 IRQ y a 80 ninguno (el RX deja de interrumpir: el PHY ya no engancha nada). Sin ventana buena.
- **Skew-cal del vendor** es lo único con efecto: settle 30 → SOT 103 (12 con las 4 lanes) frente a 1; con stream normal (A) + skew+secuencia vendor + settle 30 → **SOT 187, SOT4 53, ECC 7, WECC 8**, OVF bajo (11). Más inicios de transmisión reconocidos, pero ningún paquete decodificado.
- **lane_assign** 0x0123/0x1032/0x2301: sin SOT, mismo OVF que la base ⇒ la permutación no es el problema (H-LANE refutada; 0x3210 sigue siendo el valor bueno).
- **Los ECC×73 del ciclo 6/V0/B no se reproducen aquí** (ECC=0 en la línea base): la actividad del RX varía entre arranques de stream; no tratar los contadores sueltos como señal.

## Lectura (hipótesis)
H-SETTLE y H-LANE refutadas. H-SKEW: mejora parcial y repetible en SOT pero insuficiente (sin paquetes) ⇒ la alineación del PHY ayuda, no es la causa raíz. Con ciclos 5–7 sumados, el patrón es siempre el mismo: **EOT constante en las 4 lanes (bits 0–3 y 12), SOT esporádicos, sin cabecera de paquete decodificada**. Eso se parece más a un enlace que no transporta una trama CSI-2 continua (el sensor no está emitiendo una trama estable en las 4 lanes, o el reloj de lane no es el esperado) que a un fallo de muestreo. El patrón de test tampoco da paquetes.

## Siguiente (ciclo 8, propuesto, no preparado)
Lado sensor, con lecturas I2C de registros concretos (sin volcados de rango): comprobar `0x0100` (streaming), el registro de control MIPI/lanes y el modo (nº de lanes y bps reales del OV13B10 configurados por el driver frente a 4 lanes/1,12 Gbps de Android), `0x5080` (patrón), y si el reloj de lane es continuo; revisar el driver `uke_ov13b10` frente a la secuencia de arranque de Android (`dumpsys`/logcat de cámara). Uso: ciclos restantes de esta familia 2 de 3 (el 8 sería de otra familia: H-SENSMODE).
