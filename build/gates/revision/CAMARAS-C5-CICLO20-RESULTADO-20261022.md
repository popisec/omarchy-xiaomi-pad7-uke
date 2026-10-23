# C5b ciclo 20 — calidad de imagen de la trasera: revelado real y 13 MP (22-oct-2026 02:49–02:52; orden del dueño «demosaico y balance reales, solo PC y ciclos insmod/rmmod»)
Mismos módulos que los ciclos 18–19 (sin kernel nuevo). Dos ejecuciones de `c5-ciclo20.sh --go` (02:49 y 02:50; la primera tenía un fallo del script, ver abajo); 0 faults SMMU/oops; 0 módulos al final.

## Revelado en el PC (`raw-develop.py`, solo numpy + PIL; no hay OpenCV/scipy y no se instaló nada)
Promedio de ráfaga → negro 64 → sombreado de lente radial `1+0,55·r²` (**aproximado**) → balance de blancos gris en tonos medios **por superpíxeles 2×2** → recorte de altas luces a blanco neutro → demosaico **Malvar-He-Cutler** → CCM genérica de OmniVision (**aproximada**, filas suman 1) → exposición (p99 → 0,92) → ruido: crominancia gaussiana σ≈3, luminancia suave con preservación de bordes → máscara de enfoque → sRGB + contraste suave.
- Fallo encontrado y corregido: el primer balance elegía tonos medios **píxel a píxel** sobre el mosaico; los umbrales dejaban fuera los G claros y los R/B oscuros → ganancias 1,34/1,37 y tinte verde. Con superpíxeles: **1,61/1,63** y techo neutro (RGB 133/132/131).
- Altas luces saturadas salían magenta (R/B escalados sobre G recortado): ahora se recortan a 1,0 tras el WB y se neutralizan.

## Captura (tablet)
- AE que prefiere exposición a ganancia: vblank 6000, exposición 7552 líneas, g. analógica 1129 (≈ 8,8× en vez de 15,5×).
- AF con `ukeaf.py` v2 (bloques de 16 px sobre casi todo el frame; la v1 miraba solo el centro, plano en esta escena): curva limpia 0→480→960 = 684 761 → **769 456** → 595 554; **DAC 480** en las dos ejecuciones.
- **Ráfaga 2104×1560 ×8** (32,9 MB) y **ráfaga 4208×3120 ×4** (`sizeimage` 16 423 680, `bytesperline` 5264): **13 MP funciona** (en los ciclos 8 y 14 dio 0/6 por el reloj de 19,2 MHz).
- Fallo del script en la 1.ª ejecución: la media de la AE se guardaba en `M`, que es el comando `media-ctl` → el cambio de formato a 13 MP no se aplicó. Corregido (`MM`).

## Resultado (PNG/JPG no versionados, enviados al dueño)
`out/b20-burst8-dev.png` (2104×1560, 8 frames), `out/b20-13mp-dev.{png,jpg}` (4208×3120, 4 frames), `out/b20-13mp-recorte.png` (100 %): colores neutros, ruido bajo, la marca de la caja legible y la textura del cartón resuelta. Defectos que quedan: blancos de la etiqueta quemados (la AE mide la media de una escena dominada por el techo), CCM y LSC sin calibrar.

## Pendiente
CCM/LSC/AWB reales del módulo OFILM (tabla del `com.qti.tuned.o82_ofilm_ov13b10_wide_i.bin`, formato Chromatix sin parsear; o calibración con una carta), AE por histograma (proteger altas luces), V4L2/libcamera para una app, frontal, persistencia.
