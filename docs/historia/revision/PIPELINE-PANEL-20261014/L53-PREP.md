# L53 — Instrumento: volcado de registros del KTZ8866 (estado ABL vs nuestro) — 14-oct-2026

> Solo-PC. Diff: `l53-ktz-dump.diff` (aplicado al árbol; build k52L53 en curso).
> Base medida: KTZ digitalmente perfecto por I2C (`0x08=0x7F`, nivel `0x7FF`, `0x02=0x53`/
> `0x03=0xCD`, sin fault) y **sin luz**; el dueño ve el splash del ABL con luz + un flash
> blanco (~1 s) al arrancar. Verificaciones: **la luz siempre fue del ABL** (hermano + k52b2),
> ningún kernel propio encendió el panel.

## 1. Objetivo

Cazar la **diferencia de configuración** del KTZ entre:
- el estado que deja el **ABL** (que SÍ enciende: splash + flash blanco), y
- el nuestro (post-driver, medido por I2C y sin luz).

Si el chip no fue reseteado en el handover, `probe-entry` mostrará la config del ABL ⇒ el diff
es la escritura que falta. Si muestra los default/lo mismo que ahora ⇒ el ABL no usó el KTZ
(o el chip se resetea antes) ⇒ branch B (DCS 0x51 interno, recomendación k52b2).

## 2. Instrumento (`l53-ktz-dump.diff`, inerte)

`uke_ktz_dump(ktz, tag)`: `regmap_read` de `0x00..0x10` (17 regs) + `pr_err("UKE-K53: <tag>: ...")`.
Fallos de read ⇒ `0xdead`.

| Llamada | Sitio | Qué revela |
|---|---|---|
| `probe-entry (estado ABL)` | tras `devm_regmap_init_i2c`, **antes de cualquier write** | la config del ABL (si persiste) |
| `post-init` | tras `ktz8866_init(ktz)` | tras las escrituras de props (0x08=0x3F…) |
| `post-first-update` | tras el primer `backlight_update_status` | tras enable+brightness del probe |
| `update-in` / `update-out` | en `ktz8866_backlight_update_status` | por update (incluida la del commit ~55 s): ¿algo resetea el chip entre medias? |

## 3. Cmdline y gates

- Cmdline **608→624 B**: append `-video=DSI-1:d,iomem=relaxed,arm_smmu.uke_disp_reclaim=1,ignore_loglevel`.
  `ignore_loglevel` es necesario: los dumps del probe son a ~4,17 s, antes de que el userspace
  baje `console_loglevel` a 1 (regla del proyecto: subir+verificar en runtime; aquí no hay runtime).
- Gates del repack L53: `UKE-K53` (literal del pr_err), los 5 tags ×1, `ignore_loglevel` en cmdline,
  `FIX-A1b`×6, viejo `FIX-A1:`×0, `UKE-POKE`=121, `K50-`×18, S4-DIAG×4.

## 4. Criterio

**PASA** = los 5 dumps en el netconsole + comparación hecha (`probe-entry` vs `post-first-update`/
`update-in`) con veredicto explícito: registros que difieren ⇒ la config que falta; o
"ABL no usó KTZ/reseteado" ⇒ branch B. **FALLA** = sin dumps (canal/ignore_loglevel) o boot roto
(rollback L52 `0cd89f96…`). **Coste**: 1 escritura (`boot_a`); sddm OFF; dtbo s287 se queda.

## 5. Qué NO hacer

Nada de SMMU/DT/GDSC/OPP; no volcar regmap MMIO (lección #627); no dos lectores ACM; no tocar
`uke_write_mask`; nada de msleep en el path.
