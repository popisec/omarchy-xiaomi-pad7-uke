# `build/gates/patches/` — los parches del kernel

Aquí están los parches que se aplican al árbol del kernel. **No hay un
`series`**: los parches se aplican a mano, uno a uno, según el ciclo, y cada
aplicación va con su fila en el ledger de flashes.

## Los dos linajes

**Decisión del dueño (23-oct-2026): el port sigue sobre el árbol «senemos» de
terceros, con los parches propios encima.** El linaje «palawan» queda como
histórico: su código y sus scripts se conservan, pero no se mantienen.

| Linaje | Base | Qué parches son estos |
|---|---|---|
| **palawan** (26-sep → 17-oct) — **HISTÓRICO** | [palawan-mainline/linux](https://codeberg.org/palawan-mainline/linux), rama `palawan/v7.2-rc2` | Los de este directorio: `k17`…`k69`, `l44`…`l59`, `ACUMULADO-*.diff`… |
| **senemos** (17-oct → hoy) — **VIGENTE** | [MCC45TR/senemos-uke-kernel-mainline](https://github.com/MCC45TR/senemos-uke-kernel-mainline) @ `43e4036e` (MIT) | Los de `build/rootfs/deploy/camaras/patches/` (0045, 0046) y `build/rootfs/deploy/audio/kernel/` (0001–0009) |

⚠️ **Un parche de un linaje no aplica en el otro.** Los parches de aquí son del
linaje palawan; los del vigente están en los directorios de despliegue que se
indican arriba.

## Cómo se aplican

- **El `-pN` no es uniforme.** La mayoría van con `-p1`, pero algunos llevan
  rutas absolutas o prefijos propios (`l44-panel-backlight.diff` y
  `l44-ktz-driver.diff` usan nombres `.orig`; `l37-continuous-clock.diff`
  apunta a `build/kernel-pokes/k52L33-tree/…`). **No hay una receta única**:
  cada script `build-k*.sh` aplica los suyos con su propio `-pN`.
- **El acumulador.** `ACUMULADO-palawan-d1c7ef2e0-a-k24.diff` sí es autocontenido
  (aplica limpio sobre `d1c7ef2e0` y reproduce el árbol byte a byte), y su
  cabecera dice que los `k1`…`k18` «siguen siendo historial, pero NO hay que
  aplicarlos».
- **Las fuentes de driver** (`k47-fuentes/`, `k52L33-fuentes/`,
  `k52L39-fuentes/`) son **copias de ficheros mainline** (Linux Foundation / QIC),
  no código del fabricante. Son GPL-2.0-only, compatible con el kernel.

## Parches que se citan y no están

Algunos documentos citan parches que no están aquí. No es un error de los
documentos: son parches que se aplicaron en su momento y no se versionaron.

| Citado en | Ruta que falta |
|---|---|
| `build/gates/revision/RE-L12-20261010.md` | `build/gates/patches/k52L13-bisect.diff` |
| `build/gates/revision/PIPELINE-PANEL-20261014/L66-ADSP-ICC.md` | `build/gates/patches/k52L66-icc-revert.diff` |
| `build/gates/revision/PIPELINE-PANEL-20261014/VERIF-K52B2-PANTALLA.md` | `build/gates/patches/k49-fuentes/` |

Los que sí están pero **duplicados** se resolvieron con enlaces simbólicos
(`tools/dupcheck.py` lo vigila en la CI).

## Lo que falta para que sea reproducible

Un `series` con el orden y el `-pN` de cada parche, y el árbol base con su
sha256. Ver [`../../BUILD.md`](../../BUILD.md) §2.
