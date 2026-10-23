# C5b ciclo 17 — resultado (22-oct-2026 02:33–02:35; solo insmod/rmmod, sin flash ni reinicio)
Mismos módulos que el ciclo 16 (`out-ciclo16`, `cphy_rx` 400 MHz). Barrido de controles V4L2 del sensor (`c5-ciclo17.sh`): `vertical_blanking`, `exposure`, `analogue_gain`, `digital_gain`, con `--stream-skip=2`. Registro `out/c5-ciclo17-20261022-0233.txt`, dmesg `out/c5c17-dmesg-0233.log`; RAW/PNG `out/b17-*.{raw,png}` (no versionados).

| # | vblank | exposición (líneas) | g. analógica | g. digital | min/max/media (10 bits) |
|---|---|---|---|---|---|
| E0 | 1636 | 64 (defecto) | 0x80 (1×) | 2560 | 47/82/64,1 |
| E1 | 1636 | 3188 (máx. a 30 fps) | 1× | 2560 | 46/84/64,7 |
| E2 | 1636 | 3188 | 0x200 (4×) | 2560 | 29/99/66,4 |
| E3 | 1636 | 3188 | 0x7c0 (máx.) | 4095 | 0/164/78,2 |
| E4 | 8000 | 9552 | 0x7c0 | 4095 | 0/229/108,6 |
| E5 | 8000 | 9552 | 4× | 2560 | 32/120/71,4 |

- 6/6 buffers completos, 0 faults SMMU/oops, 0 módulos al final.
- **La señal sigue a exposición × ganancia** (media 64 → 108,6) y E4 muestra el **viñeteado de la lente** (centro más claro): llega luz real por la óptica. La escena no tiene detalle (02:35, habitación oscura; la tablet probablemente boca abajo o apuntando a una superficie): para una foto reconocible hace falta luz y que la trasera mire a algo — es una cuestión de posición, no de driver.
- El tinte verde de los PNG es esperable: `raw10-to-png.py` no hace balance de blancos (vista previa).
- Rangos de controles medidos: `vertical_blanking` 38–31207 (defecto del modo 2104×1560 = 1636 tras el `set-fmt`), `analogue_gain` 128–1984, `digital_gain` 1024–4095.

## Siguiente
Con luz y la trasera hacia una escena: repetir E2/E4 (`c5-ciclo17.sh --go`) para una foto reconocible; después enfoque (VCM en `l14`), balance de blancos/demosaico en el PC, y libcamera/softISP para una app (otro ciclo de trabajo).

## Repetición con luz (22-oct 02:35, orden del dueño: «la trasera ya apunta a algo con luz»)
Mismo `c5-ciclo17.sh --go`; registro `out/c5-ciclo17-20261022-0234.txt`, dmesg `out/c5c17-dmesg-0234.log`. 6/6 buffers completos, 0 faults, 0 módulos al final. E3: 0/272/73,2; **E4 (vblank 8000, exp 9552, ganancias máx.): 0/252/93,4 con escena real** — zonas de luz y sombra con forma, **desenfocadas** (VCM sin controlar) y con ruido alto (ganancia máxima). PNG con balance gris-medio (ganancias R/G/B ≈ 1,18/0,73/1,26) + mediana 5×5: `out/b17-5-wb.png` (no versionado), enviado al dueño. **Objetivo de la sesión cumplido: frame RAW real de la trasera convertido a PNG.**
