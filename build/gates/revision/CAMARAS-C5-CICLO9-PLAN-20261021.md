# C5b ciclo 9 — plan (preparado 21-oct-2026 sin ejecutar; orden del dueño: «prepara el ciclo 9 (barrido de 0x4800 bit a bit en imagen normal y patrón) sin ejecutarlo»)
Parte de `docs/historia/revision/CAMARAS-C5-CICLO8-RESULTADO-20261021.md`: el sensor está bien configurado y transmitiendo; **`0x4800` (base 0x64) es lo único que mueve los SOT** con patrón de test (0x60 → SOT 117, 0x24 → 79, 0x44 → 0 frente a 0 de la base) y con patrón + base el FIFO se desborda sin SOT. Este ciclo mapea el efecto de CADA bit del registro (cambio único por stream). Techo: este es el 2.º ciclo de la familia «control MIPI del sensor».
Ejecutar requiere: orden del dueño para ESTE ciclo, turno libre, batería ≥ 30 %, ACM con lector único, doble captura (el script graba `dmesg -w`), sin flash ni reinicio. Script `build/rootfs/deploy/camaras/c5-ciclo9.sh --check | --go`. **Módulos: los mismos de `out-ciclo8/`** (ya tienen `uke_xreg/uke_xval/uke_skew`); no hay build nuevo (`--check` OK).

## Matriz (22 streams, modo 2104×1560, settle calculado, máscara RX 0xfffffff0, presupuesto 400 por stream)
- Sin skew, B (patrón) y A (normal) para `0x4800` = **0x64 (base, referencia), 0x65, 0x66, 0x60, 0x6c, 0x74, 0x44, 0x24, 0xe4** (base con un bit alterado: bit0, bit1, bit2, bit3, bit4, bit5, bit6, bit7) → 18.
- K: con `uke_skew=1`, B y A para 0x60 y 0x24 → 4.
Salida: `RESUMEN … bytes irq SOT SOT4 ECC LONG SHORT CRC OVF WECC` por stream y las líneas `uke-sens` (registro extra escrito y relectura a +50/+400 ms; verifica que el valor quedó y que `0100=01`).

## Criterios (pre-registrados)
- **PASS (hito 2)**: `bytes > 0` o `LONG/SHORT > 0` en cualquier stream. Anotar valor de 0x4800 y modo.
- **Señal parcial**: un valor que suba SOT4 (4 lanes sincronizadas) o baje OVF con patrón; ordenar los 9 valores por SOT4/OVF para sacar qué bit manda; en ciclo 10 combinar ese bit con settle/skew.
- **Refutación**: ningún valor de 0x4800 da LONG/SHORT y las diferencias de SOT son ruido (la base dio SOT 273 en M A, 0 en M B en el ciclo 8, así que la variación entre arranques es grande: repetir la referencia y comparar con ≥ 2× de diferencia). Entonces: ciclo 10 = otra familia (CSID/RDI formato/VC/DT, o csid1/vfe1) y extraer de Android las tablas OFILM reales (requiere orden del dueño y arrancar Android).
- **Abortar**: Oops/SMMU, batería < 30 %, `dmesg -w` sin crecer, o relectura de `0x4800` ≠ escrito.
- Honestidad: no hay datasheet con el mapa de bits de 0x4800; los bits no se interpretan, solo se miden. Un bit cambiado puede dejar el sensor en modo MIPI inválido (efecto reversible: el reset de la siguiente carga lo restaura; el script escribe el registro en cada stream desde la tabla antes de MODE_SELECT).
