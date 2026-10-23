# C5b ciclo 6 — resultado (21-oct-2026 20:35, autorizado por el dueño; sin flash ni reinicio)
`c5-ciclo6.sh --go`: batería 100 %, sha iguales, chip-id 0x560d42 OK, 0 faults SMMU/oops, descarga limpia (0 módulos). Registros: `out/c5-ciclo6-20261021-2035.txt`, dmesg `out/c5c6-dmesg-2035.log`. Lector ACM único vivo.

## Medido
8 streams (V0..V3 × B patrón de test / A normal): **0 bytes en los 8**. Pero el RX del CSID ya no solo ve EOT. Sobre 3200 IRQ registrados (bit: veces): EOT 0–3 ≈ 3000 cada uno, bit 12 = 3144, **SOT 4–7 = 158/158/154/123**, FIFO overflow lane0/1/2/3 (bits 15–18) = 593/117/760/950, **ECC error (bit 20) = 79**, warning ECC (14) = 1. **Nunca** long/short packet (8–9) ni CRC (19), VC/DT (21–22).
- V0 (mainline, línea base) con patrón de test: `0x001010ff` ×73 = SOT en las 4 lanes + ECC error; es decir, **ya en la línea base llegan inicios de transmisión y cabeceras que fallan el ECC** (en el ciclo 5 no se veía por la máscara y el presupuesto).
- V1/V2 (`ctl0_post=0x02`): aparecen overflows de FIFO (0x6900f, 0x2900f…) ⇒ las lanes empujan datos al FIFO del RX sin que se decodifiquen paquetes. V3 (`ctl7=0x7a` solo): SOT más frecuentes en A (0x107f/0x10ff), sin overflow. Variante V1 completa (vendor) no produce bytes.
- Se confirma: `CTRL0=0x02` y `CTRL7=0x7a` se escriben (log); no arreglan nada por sí solos.

## Lectura (hipótesis)
H-PHYSEQ **no basta** (1 ciclo de 3): no hay bytes en ninguna variante. Pero el diagnóstico avanza: **los datos HS llegan al CSID (SOT en las 4 lanes + overflow) y las cabeceras de paquete salen corruptas (ECC error)**. Eso apunta a muestreo/alineación HS (settle o calibración de la lane, `0x0094`/skew), orden o polaridad de lanes, o velocidad del enlace distinta de la que el PHY espera; ya no a «el sensor no emite». El bit 12 + EOT constantes seguirían siendo el estado de lane/reloj del PHY (sin identificar para D-PHY).

## Ciclo 7 propuesto (sin ejecutar; requiere orden del dueño)
Con visibilidad de IRQ (máscara 0xfffffff0, presupuesto por stream, patrón de test): (a) barrido de settle (`uke_settle` 10, 19, 25, 40, 60, 80) midiendo la proporción de ECC error vs SOT; (b) con skew calibration ON (`0x0094=0xD7`, `0x005C=0x04`, `0x0060=0xBD`, `0x0064=0x7F`, que mainline sm8650 omite) como parámetro; (c) si siguen ECC, permutaciones de `lane_assign`. Criterio de éxito: aparece `LONG_PKT` (0x100) o bytes > 0. Techo restante para H-LANE/H-SKEW: 3 ciclos.
