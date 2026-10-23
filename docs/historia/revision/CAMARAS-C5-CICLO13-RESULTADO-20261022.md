# C5b ciclo 13 — resultado (22-oct-2026 00:53, autorizado por el dueño con «tuya» de la gestora; sin flash ni reinicio)
`c5-ciclo13.sh --go` (módulos de `out-ciclo12`, sin captura 0x208): batería 95 %, 0 faults SMMU/oops, 0 módulos al final. dmesg `out/c5c13-dmesg-0053.log`.
## Medido
15 intentos del stream normal con `0x4800=0x7e` (A, 2104×1560, settle calculado): **0 bytes en los 15** ⇒ 0 buffers guardados, sin PNG. 12 intentos en régimen de ECC alto (SOT4≈ECC, OVF 0) y 3 (2, 8, 15) en régimen ECC≈0/OVF≈50; los tres alcanzaron SOF pero no devolvieron buffer. Reproducción del ciclo 12: **0/15** (agregado 1/17 con la misma configuración).
## Lectura
El buffer del ciclo 12 no es reproducible con lo conocido: con la misma configuración sale 1 de 17 y ningún contador de RX lo distingue. Probable dependencia de un estado que no controlamos (alineación entre arranques, fase del sensor). Ver `docs/historia/revision/CAMARAS-REVISION-SUBAGENTES-20261022.md` para el reanálisis.
