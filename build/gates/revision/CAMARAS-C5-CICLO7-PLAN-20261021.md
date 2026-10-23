# C5b ciclo 7 — plan (preparado 21-oct-2026 sin ejecutar; orden del dueño: «prepara el ciclo 7… sin ejecutarlo»)
Parte de `docs/historia/revision/CAMARAS-C5-CICLO6-RESULTADO-20261021.md`: SOT en las 4 lanes + ECC error + overflow, 0 paquetes ⇒ los datos HS llegan pero las cabeceras salen corruptas. Hipótesis de este ciclo (una familia, «muestreo/alineación HS»): **H-SETTLE**, **H-SKEW**, **H-LANE**. Techo restante: 3 ciclos para esta familia.
Ejecutar requiere: orden del dueño para ESTE ciclo, turno libre (BT/audio dicen «libre»), batería ≥ 30 %, ACM con lector único, doble captura (el script graba `dmesg -w` por ssh), sin flash ni reinicio. `build/rootfs/deploy/camaras/c5-ciclo7.sh --check | --go`; módulos `out-ciclo7/` (ouke5, 0 avisos; `--check` OK; gawk 5.4.1 presente en la tablet).

## Cambios de código (todos por defecto = comportamiento anterior)
- `uke_skew` (PHY): 1 = escribe el bloque skew-cal del vendor 2.2.1 (por lane `+0x94=D7 +0x5C=04 +0x60=BD +0x64=7F`; mainline sm8650 lo omite, el vendor lo aplica solo si `mipi_flags` lo pide).
- `uke_lane_assign` (CSID): si ≥ 0 sustituye `phy->lane_assign` (4 bits por lane; 0x3210 = identidad).
- `uke_settle`, `uke_ctl7`, `uke_ctl0_post` ya existían.

## Matriz (16 streams de 1 frame; patrón de test salvo A; máscara RX 0xfffffff0; presupuesto 400 IRQ repuesto por stream)
| grupo | variantes |
|---|---|
| S | settle 10, 19, 25, 30 (≈ calculado), 40, 60, 80 (sin skew, DT lane_assign, secuencia mainline) |
| K | skew=1 con settle 19 y 30 |
| KV | skew=1 + `ctl7=0x7a` + `ctl0_post=0x02` con settle 19 y 30 |
| L | lane_assign 0x0123, 0x1032, 0x2301 (settle calculado) |
| A | stream normal (test_pattern=0): skew st19; skew+vendor st30 |
Salida: una línea `RESUMEN` por stream: `bytes irq SOT SOT4 ECC LONG SHORT CRC OVF WECC` (cuentas de mensajes de IRQ con ese bit, de ≤400).

## Criterios (pre-registrados)
- **PASS (hito 2)**: algún stream con `bytes > 0`, o `LONG > 0`. Anotar la variante mínima.
- **Señal parcial**: baja de la proporción ECC/irq (baseline ciclo 6 V0/B ≈ 73 de ~400 con SOT en 4 lanes) en un valor concreto de settle/skew/lane ⇒ ajustar fino (ciclo 8); o aparecen SHORT (frame start) sin LONG.
- **Refutación de la familia**: ECC y OVF iguales (±20 %) en todos los grupos ⇒ H-SETTLE/H-SKEW/H-LANE refutadas; siguiente: tabla de IRQ del PHY del vendor (`0x102c…`), velocidad real del enlace del sensor (¿el modo 4208×3120/MIPI rate del OV13B10 que usa el driver coincide con el 1,12 Gbps/lane de Android?) y reloj del sensor.
- **Abortar**: Oops/SMMU fault, batería < 30 %, o `dmesg -w` sin crecer; el script descarga módulos al final.
- Honestidad: el barrido de settle de 12–55 del ciclo 4 se hizo sin IRQ visible y sin skew; aquí se mide ECC, que es la métrica directa. Que 0x0123/0x1032/0x2301 sean significativas es especulativo (Android usa 0x3210 = el nuestro).
