# ÍNDICE DE DOCUMENTACIÓN — omarchy-uke (22-oct-2026)

> **Dónde está cada cosa.** Este fichero es el mapa. Si buscas algo, empieza aquí.
> ⚠️ Lee primero [`ESTADO.md`](ESTADO.md) (estado del aparato) y
> [`build/gates/revision/PENDIENTES-INDICE-20261022.md`](build/gates/revision/PENDIENTES-INDICE-20261022.md)
> (lo que está vivo a día de hoy, con sus bloqueos y las decisiones que faltan).

## 0. Los ficheros que mandan

| Fichero | Para qué | Estado |
|---|---|---|
| **[`ESTADO.md`](ESTADO.md)** | **Una página**: qué funciona, qué no y qué se rompe | ✅ vigente (22-oct) |
| [`docs/historia/ESTADO-VIVO.md`](docs/historia/ESTADO-VIVO.md) | El log del port por sesiones (900 líneas): el detalle de cada medida | histórico |
| **[`build/gates/revision/PENDIENTES-INDICE-20261022.md`](build/gates/revision/PENDIENTES-INDICE-20261022.md)** | **El índice de lo vivo**: qué está hecho, qué está bloqueado, qué decide el dueño | ✅ vigente (22-oct) |
| [`NOTAS-OMARCHY.md`](NOTAS-OMARCHY.md) | Bitácora viva. Toda medición fechada | ✅ vigente (~6.100 líneas) |
| [`REGLAS.md`](REGLAS.md) | Las reglas que no cambian: backup, sha256, presupuesto de ciclos | ✅ vigente |
| [`F-plan-por-fases.md`](F-plan-por-fases.md) | El plan ejecutable F0–F8, con criterio de «hecho» medible | ✅ vigente (referencia) |
| [`docs/historia/G-auditoria-documental.md`](docs/historia/G-auditoria-documental.md) | Índice maestro del cuaderno: inventario, contradicciones, huecos | ✅ vigente |
| [`CHANGELOG.md`](CHANGELOG.md) | Cronología del port por fechas | ✅ vigente |
| [`HARDWARE.md`](HARDWARE.md) | SoC, particiones, slots, panel,.kernel, módulos | ✅ vigente |
| [`BUILD.md`](BUILD.md) | Qué se puede reconstruir y qué no, y con qué herramientas | ✅ vigente |
| `~/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md` | Ledger de flashes (proyecto hermano, solo lectura) | externo, no publicado |

## 1. Informes de partida (congelados el 26-sep)

En `docs/informes/`. Son **referencia congelada**: no se editan para añadir hallazgos, solo
erratas factuales.

| Fichero | Qué es |
|---|---|
| [`A-port-omarchy-aarch64.md`](docs/informes/A-port-omarchy-aarch64.md) | Qué recompilar/parchear para aarch64; el árbol de Omarchy es agnóstico de arquitectura |
| [`B-arranque-arch-uke.md`](docs/informes/B-arranque-arch-uke.md) | initramfs, cmdline `rdinit`, BCB, contador de slots, sin UEFI/Limine |
| [`C-hyprland-quickshell-aarch64.md`](docs/informes/C-hyprland-quickshell-aarch64.md) | Hyprland con API Lua, Quickshell, shell en aarch64, Adreno 732 |
| [`D-capa-tablet-fallback.md`](docs/informes/D-capa-tablet-fallback.md) | Qué de `texp-*` (Bash/Python + `hyprctl`) funciona sin el shell de Omarchy |
| [`E-paquetes-aarch64-soc.md`](docs/informes/E-paquetes-aarch64-soc.md) | `pacman`/AUR en la tablet: kernel, firmware WCN6750 + gen71100, mesa/freedreno, libwacom, qbootctl |

## 2. Guías de referencia

En `docs/guias/`.

| Fichero | Qué es |
|---|---|
| [`RE-NOCTURNO-HALLAZGOS-20261017.md`](docs/guias/RE-NOCTURNO-HALLAZGOS-20261017.md) | Hallazgos de la revisión nocturna del 17-oct (touch, stylus, BT, audio) |
| [`LINUX-A-ANDROID-IDA-VUELTA.md`](docs/guias/LINUX-A-ANDROID-IDA-VUELTA.md) | Ida y vuelta Linux↔Android con IDA: cómo se extrajeron los protocolos del driver del fabricante |

## 3. Historia (documentos superados, se conservan por contexto)

En `docs/historia/`: los planes v1–v4, los runbooks antiguos, los `DUDAS-*` ya respondidos y el
README interno original. Y en `docs/historia/revision/`, los **292 informes de ciclo archivados**
(con su [`README.md`](docs/historia/revision/README.md)); el paquete completo —519 ficheros— está
también en el [release v0.2.0](https://github.com/popisec/omarchy-xiaomi-pad7-uke/releases/download/v0.2.0/evidencia-omarchy-uke-2026-10.tar.gz). **No son el plan vigente**: para eso están `F` y `PENDIENTES-INDICE`.

## 4. `build/`

| Ruta | Contenido |
|---|---|
| `build/gates/` | **El motor del proyecto.** 69 scripts de shell + 19 de Python (build, empaquetado, verificación, flasheo) y 54 informes de ciclo |
| `build/gates/revision/` | Los **227 informes vivos** (los que cita la documentación de la raíz): el ciclo en curso y lo que se lee para saber qué funciona hoy |
| `build/gates/patches/` | Parches del kernel y fuentes de drivers (panel o82, ktz8866, DPU…) |
| `build/kernel-config/` | Un `.config` por cada kernel probado (`k23b`…`k52L76r`) |
| `build/rootfs/deploy/<tema>/` | Despliegues sobre la tablet: 35 temas (audio, bt, camaras, lapiz, touch-mode, bateria, suspension, wifi, escritorio-tactil, plugins de la shell…) |
| `build/pkg/` | PKGBUILD que empaquetan firmware **que tienes que extraer tú** |
| `build/slot/`, `build/cm3-ladder/`, `build/tools/` | Utilidades de slot, medición del CM3 y herramientas (Ghidra) |
| `build/linux-l76r-20261017/`, `build/linux-senemos-20261017/` | Capturas de estado del kernel (`dmesg`, DRM, clocks) de dos builds concretos |

### 4.1 Los informes de `build/gates/revision/`

Están por fecha y tema. Los que importan hoy:

| Fichero | Qué es |
|---|---|
| [`PENDIENTES-INDICE-20261022.md`](build/gates/revision/PENDIENTES-INDICE-20261022.md) | **El índice de lo vivo** (22-oct) |
| [`PLUGINS-TABLET-20261022.md`](build/gates/revision/PLUGINS-TABLET-20261022.md) | Plugins de la shell (22-oct) |
| [`ESCRITORIO-TACTIL-20261022.md`](build/gates/revision/ESCRITORIO-TACTIL-20261022.md) | Escritorio táctil (22-oct) |
| [`RESTO-APPS-DICTADO-20261022.md`](build/gates/revision/RESTO-APPS-DICTADO-20261022.md) | Dictado offline en el teclado en pantalla (22-oct) |
| [`CAMARAS-MEGAPIXELS-20261022.md`](build/gates/revision/CAMARAS-MEGAPIXELS-20261022.md) | Cámaras en Megapixels (22-oct) |
| [`WIFI-QR-20261019.md`](build/gates/revision/WIFI-QR-20261019.md) | Captura de WiFi por QR (19-oct) |

## 5. `charge/`

Overlays DT de la cadena de carga (ADSP, `pmic_glink`) y sus scripts de reempaquetado:
`charge/mkdtbo-s282.py`…`s289`, `charge/uke-adsp.service`, `charge/uke-charge-run.sh`.

## 6. `tools/`

| Fichero | Qué hace |
|---|---|
| [`tools/check-links.py`](tools/check-links.py) | Comprueba que las referencias a ficheros del repo existen. La CI lo corre en cada push (con baseline) |
| [`tools/link-baseline.txt`](tools/link-baseline.txt) | Las referencias rotas ya conocidas (ficheros que solo viven en el repo privado) |

## 7. Cómo se lee esto

1. [`README.md`](README.md) — qué es esto y qué **no** hay.
2. [`HARDWARE.md`](HARDWARE.md) — sobre qué aparato.
3. [`ESTADO.md`](ESTADO.md) + `PENDIENTES-INDICE-20261022.md` — qué funciona hoy.
4. [`REGLAS.md`](REGLAS.md) — antes de tocar la tablet, las reglas que no cambian.
5. [`F-plan-por-fases.md`](F-plan-por-fases.md) — el plan con el orden y los criterios de «hecho».
6. [`NOTAS-OMARCHY.md`](NOTAS-OMARCHY.md) — la bitácora, para saber cómo se llegó a cada medida.

## 8. Lo que este índice NO cubre

- Los informes de ciclo: los **227 vivos** en `build/gates/revision/` y los **292 archivados** en
  `docs/historia/revision/`. Se buscan por fecha y tema; `grep` sobre el directorio es más rápido que
  mantener una lista. Los 519 en un paquete están en el [release](https://github.com/popisec/omarchy-xiaomi-pad7-uke/releases/download/v0.2.0/evidencia-omarchy-uke-2026-10.tar.gz).
- El proyecto hermano `~/proyectos/ubuntu-permanente`: no se publica.
