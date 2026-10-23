# BRIEF — Pipeline de subagentes «canal de pantalla» (noche 14-oct-2026)

> Este fichero es el contexto común para TODOS los subagentes del pipeline. Léelo entero
> antes de trabajar. El objetivo de la noche: dejar el canal de pantalla de la uke
> **entendido de punta a punta**, con los cambios exactos propuestos, revisados y listos
> para un ciclo de flash por la mañana.

## Estado vivo (medido, no memoria)

- `boot_a` = **L45** `83647c45…` + `dtbo_a` = **s286** `33d153f2…`. Tablet **viva por SSH**
  (`ssh -i build/rootfs/uke-arch-root -o BatchMode=yes root@192.168.42.129`), display
  **apagado por diseño** (`video=DSI-1:d` en la cmdline del repack `--dsid`).
- Verde y cerrado: bus I2C (`i2c-2`, L43), driver KTZ8866 + `backlight` (`2-0011`, L44),
  **enlace panel↔KTZ** (L45: `sin backlight externo`=0, `UKE-L45`=1). Ledger #613–#619.
- **El crux pendiente**: con display encendido, muere el **primer DCS**:
  `cmd#0 → FIFO → TIMEOUT → host-xfer → silencio` («el panel no escucha»). El modelo
  «el enlace está mal configurado» está agotado (G4/G7 refutados con control; G5/G6 inertes).
  Candidatos vivos: **vci (P0)**, **G8**, **reset/power del TDDI**, físico.
- Lectura obligatoria antes de hipotetizar: `build/gates/revision/AUDITORIA-METODO-20261013.md`
  (escalera + errores E1–E10), `docs/historia/revision/ROADMAP-PANTALLA-20261013.md`, `GAPLIST-VENDOR-MAINLINE-20261013.md`,
  `INDICE-DOCUMENTACION.md`, `docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md`, `docs/historia/revision/ANDROID-DSI-ENABLE-COMPARISON-20261013.md`,
  `docs/historia/revision/ANDROID-POWER-DPU-20261013.md`, `HALLAZGO-MUERTE-DSI.md`, `L39-{PLAN,RESULTADO,HALLAZGO}*`,
  `VEREDICTO-G4-REFUTADO.md`, `VEREDICTO-G7-*.md`, y del proyecto hermano
  `~/proyectos/ubuntu-permanente/docs/REFUTADO.md` + `LECCIONES.md`.

## Reglas (no negociables)

1. **Solo lectura en la tablet**: SSH para inspeccionar (dmesg, sysfs, `/proc`), nunca escribir,
   nunca flashear, nunca `reboot`. No tocar `/dev/ttyACM0`.
2. **NO modificar** `build/kernel-pokes/k52-L16-tree` ni ningún árbol vivo. Los cambios se
   proponen como **diffs en el directorio del pipeline** (formato `diff -u` aplicable con `patch -p1`).
3. **Evidencia o no es nada**: cada afirmación con `fichero:línea`, comando+salida, o URL.
   Hipótesis = marcadas como hipótesis. Prohibido «de memoria».
4. **Un cambio por ciclo** y criterio **pasa/falla prefijado**. No apilar variables.
5. Antes de proponer una hipótesis, comprobar que no está en `REFUTADO.md`/`LECCIONES.md`
   (ya hay ~56 refutaciones; no repitas rondas).
6. **Techo de honestidad**: si no hay señal que pida un cambio, dilo («no tocar» es un resultado).
7. Documentos en **español**, con fecha. Tu entrega va al fichero indicado en tu sección.
8. Devuelve al orquestador un **resumen ≤25 líneas** (el detalle vive en tu fichero).

## Material disponible

- Árbol vivo: `build/kernel-pokes/k52-L16-tree` (de él salen L19/L43/L44/L45).
- Linaje L39 (para portes): `build/kernel-pokes/k52L39-tree` (y k52L33-tree, k52L27-tree…).
- Parches históricos: `build/gates/patches/*.diff` (p.ej. `l27-fidelidad-android.diff`,
  `l37-continuous-clock.diff`, `l34-timing-flush.diff`, `l44-ktz-driver.diff`, `l45-panel-defer.diff`).
- Drivers clave (en el árbol vivo):
  - `drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c` (panel o82 dual-DSI)
  - `drivers/gpu/drm/msm/dsi/*` (host/ctrl/phy mainline) y `drivers/gpu/drm/msm/dsi/phy/*`
  - `drivers/gpu/drm/msm/disp/dpu1/*` (DPU)
  - `drivers/video/backlight/ktz8866.c`
- Evidencia Android: `build/android/`, `build/evidencia/android-full/`, `build/evidencia/android-full-gaps/`,
  `build/evidencia/android-snap/`, `docs/guias/LINUX-A-ANDROID-IDA-VUELTA.md`; informes `ANDROID-*.md` en `revision/`.
- Ledger (fuente de verdad): `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md` (#613–#619).
- Bitácora viva: `NOTAS-OMARCHY.md`; estado: `docs/historia/ESTADO-VIVO.md`.

## Las 6 secciones (un subagente por sección)

| # | Sección | Entrega |
|---|---|---|
| S1 | **vci (P0)** — alimentación del panel: driver + DT (el overlay NO declara `vci-supply`; el driver ya lo soporta) | `PIPELINE-PANEL-20261014/S1-VCI.md` + `docs/historia/revision/PIPELINE-PANEL-20261014/s1-vci.diff` |
| S2 | **G8** — orden de `CTRL_ENABLE` + pulso (20 ms vs 1 µs) del host DSI; «abierto, mal clasificado como refutado» | `docs/historia/revision/PIPELINE-PANEL-20261014/S2-G8.md` + `docs/historia/revision/PIPELINE-PANEL-20261014/s2-g8.diff` |
| S3 | **Reset/power del TDDI** — fidelidad de la secuencia `o82_prepare/reset` vs Android (gpios, delays, ESD, la muerte del `usleep` con link vivo; correcciones L27 nunca probadas) | `docs/historia/revision/PIPELINE-PANEL-20261014/S3-RESET-TDDI.md` + `s3-*.diff` |
| S4 | **Muerte del primer DCS** — cazar la lógica en el camino `cmd#0 → FIFO → TIMEOUT → host-xfer` (host mainline vs vendor), dual-DSI, cmd-mode, BTA, timeouts | `docs/historia/revision/PIPELINE-PANEL-20261014/S4-DCS-HOST.md` (+ instrumentación propuesta) |
| S5 | **Porte del linaje L39 al vivo** — qué parches del display path (PPS ×2, reset 15 ms=L38, `=y`…) deben portarse y cuáles NO (inertes/refutados) | `docs/historia/revision/PIPELINE-PANEL-20261014/S5-PORT-L39.md` + `s5-*.diff` |
| S6 | **Minucias + DT/config** — `MIPI_DSI_CLOCK_NON_CONTINUOUS` en `mode_flags`, typo `byte_cly→byte_clk`, nodo `ktz8866@11` duplicado en `i2c@890000`, DSC/timings/porches | `docs/historia/revision/PIPELINE-PANEL-20261014/S6-MINUCIAS-DT.md` + `s6-*.diff` |

## Formato de entrega (cada sección)

```
# S<N> — <título> (14-oct-2026)
## 1. Qué he leído (lista con fichero:línea de lo relevante)
## 2. Estado real del asunto (evidencia)
## 3. Cambio propuesto (diff exacto, con fichero:línea)
## 4. Criterio pasa/falla prefijado (comando + salida esperada)
## 5. Riesgos y refutaciones que aplican (REFUTADO/LECCIONES)
## 6. Qué NO hacer / lo que queda fuera
```

## Fuera de alcance de todos

- Flashear, tocar la tablet, e2fsck, la GPU/llvmpipe, Hyprland, wifi, lápiz.
- Re-probar G4/G5/G6/G7 (refutados/inertes). G1 solo como hardening, nunca como diagnóstico.
