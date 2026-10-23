# C5b ciclo 10 — plan (preparado 21-oct-2026 sin ejecutar; orden del dueño: «prepara el ciclo 10 (0x4800 = 0x76 y vecinos, con referencias 0x74 y 0x66, en patrón y normal) sin ejecutarlo»)
Parte de `docs/historia/revision/CAMARAS-C5-CICLO9-RESULTADO-20261021.md`: `0x4800`=0x74 (bit 4) sincroniza las 4 lanes (SOT4 148/122) en patrón y normal; 0x66 (bit 1) da cabeceras con error ECC (SOT4=ECC=35). Hipótesis: combinar ambos (0x76) aproxima a una trama decodificable. Es el **3.er y último ciclo** de la familia «control MIPI del sensor» (techo de 3).
Ejecutar requiere orden del dueño para ESTE ciclo, turno libre, batería ≥ 30 %, ACM con lector único, doble captura, sin flash ni reinicio. `build/rootfs/deploy/camaras/c5-ciclo10.sh --check | --go`; **mismos módulos que ciclos 8–9 (`out-ciclo8/`)**, sin build nuevo (`--check` OK).

## Matriz (18 streams, 2104×1560, settle calculado, máscara RX 0xfffffff0, presupuesto 400)
`0x4800` en orden: **0x74 (ref), 0x66 (ref), 0x76 (bits 1+4), 0x72, 0x7e, 0x77, 0x36, 0x74 (ref repetida)** × {B patrón, A normal} = 16; más **skew=1 + 0x76** B y A = 2. Vecinos de 0x76: 0x72 (sin bit 2), 0x7e (+bit 3), 0x77 (+bit 0), 0x36 (sin bit 6). La repetición de 0x74 al final mide la deriva entre arranques de stream.

## Criterios (pre-registrados)
- **PASS (hito 2)**: `bytes > 0` o `LONG/SHORT > 0`.
- **Señal parcial**: 0x76 (o un vecino) con SOT4 ≥ la mejor ref **y** ECC > 0 o SHORT > 0 ⇒ trama casi decodificada; próximo paso fino (ciclo 11, otra familia permitida: ajustar settle con ese 0x4800).
- **Reproducibilidad**: la segunda 0x74 debe dar SOT4 ≥ 50 % de la primera; si no, la señal de 0x74 del ciclo 9 era ruido y se anota.
- **Refutación de la familia**: ningún valor da LONG/SHORT/bytes ⇒ familia cerrada (3 ciclos). Siguiente: CSID/RDI (formato/VC/DT) o bloque alternativo (csid1/vfe1), y extraer de Android las tablas OFILM (requiere orden del dueño y arrancar Android).
- **Abortar**: Oops/SMMU, batería < 30 %, `dmesg -w` sin crecer, o relectura de `0x4800` ≠ escrito.
- Honestidad: el mapa de bits de 0x4800 sigue sin fuente; se mide, no se interpreta.
