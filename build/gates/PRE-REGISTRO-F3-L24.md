# PRE-REGISTRO F3/L24 — 12-oct (obligatorio antes de flashear)

> Regla del proyecto: **sha256 pre-registrado ANTES de flashear**, y verificación por lectura de vuelta
> hasheando **al tamaño exacto de la imagen** (anula el pad de ceros; patrón ledger #241).
> Este fichero sustituye al `PRE-REGISTRO-PANTALLA.md` que termina en #P52 (los shas viven en el ledger
> hermano; ver `docs/historia/AGENTS.md` §semáforo inter-proyecto).

## Contexto

- **Base / control**: `boot_a` = L19 `71d89ca6e875941b75af012ac24d20fb7690de407fa341923f2d896557ee51a9`
  + `dtbo_a` = s275-r2 **sin tocar**. `current-slot:a`.
- **Slots antes**: `slot-retry-count:a` = **7** ⚠️ · `b` = 6 · `unbootable:a` = no.
- **Batería**: **3543 mV** ⚠️ (gate del proyecto: ≥3700 mV). **Exige cargador antes de ejecutar.**
- **Ledger hermano**: #612 dice `Resultado #612: (pendiente del flash)` — **el aborto de L22b NO está
  registrado todavía**. Hay que cerrarlo antes de abrir esta fila.

## Objetivo del experimento

**Una sola variable**: ¿el reset duro del MDSS (`msm_mdss_reset`, assert 20 ms sobre
`DISP_CC_MDSS_CORE_BCR` en el probe de mdss) mata la imagen?

Para que sea medible hacen falta **dos** cambios respecto a L19, y son inseparables por diseño:

| # | Cambio | Por qué |
|---|---|---|
| 1 | Quitar `video=DSI-1:d` de la cmdline | Con `:d` el conector queda `disabled` y **`o82_prepare` nunca corre** (medido: 0 marcas `UKE-P82:`). Sin esto el test no existe |
| 2 | `msm.uke_skip_mdss_reset=1` (hunk en `msm_mdss.c`) | La variable que se prueba |

> ⚠️ **Esto no es un multigate.** El cambio 1 no es un gate: es *habilitar el panel*. Sin él no hay
> prepare y por tanto no hay nada que el BCR pueda matar. El cambio 2 es el único gate.
> Se aparta de la la regla regla de "un cambio por ciclo" **a conciencia y con justificación**:
> un solo factor experimental, pero dos condiciones necesarias para que el factor sea observable.

## Artefacto

- **Kernel**: `boot-uke-k52L24.img`, **100663296 B** (exacto = `partition-size:boot_a`)
- **sha256**: `<<SHA_A_PONER>>`
- **Árbol**: `build/kernel-pokes/k52L24-tree` (**sin** gates de herencia: `grep uke_panel_inherit` = 0)
- **Diff**: `build/gates/patches/l24-skip-mdss-reset.diff` (un solo hunk, `msm_mdss.c`)
- **Repack**: `docs/historia/gates-palawan/repack-k52L24.py` (cmdline = L19 580 B − `video=DSI-1:d` + el param)
- **Reparto**: `dtbo_a` = s275-r2 **sin tocar**. `userdata` **sin tocar**.

## Preflight (obligatorio, en orden, TODOS deben pasar)

1. [ ] **`slot-retry-count:a` < 7** o reiniciar el contador con un boot exitoso. Si llega a 8 → A
       unbootable y cae a B sin avisar.
2. [ ] **Batería ≥ 3700 mV** (`fastboot getvar battery-voltage`) con cargador puesto.
3. [ ] `fastboot flash boot_a boot-uke-k52L24.img` → **verificar lectura de vuelta hasheando a
       100663296 B** (no el tamaño del fichero).
4. [ ] **`fastboot set_active a`** — sin esto el ABL cae al slot B (lección #596).
5. [ ] Lector ACM armado **antes** del reboot (`out/acm-loop.sh`).
6. [ ] `fastboot reboot`.

## Criterios de lectura (literales, decididos ANTES del flash)

| Medida | Dónde | Qué significa |
|---|---|---|
| ¿Aparecen marcas `UKE-P82:` de prepare? | `dmesg \| grep UKE-P82` | Si **cero** → el prepare no corrió: el test es inválido |
| ¿El log de fbcon sobrevive a 0,6 s y a 4,1 s? | ACM / `dmesg` | **Criterio de éxito** |
| ¿`gpio2` sale de `out low`? | `cat /sys/kernel/debug/gpio` | ¿Se soltó el reset del panel? |
| ¿`vsp/vsn/l8` a `use=1`? | `regulator_summary` | ¿Se levantaron los rails? |
| `bootinfo.pureason` | `tr ' ' '\n' < /proc/cmdline` | Si hubo wedge: **ramoops está activo**, el panic se persiste |
| `/sys/fs/pstore/` | tras el reboot | Si hay ficheros → **el panic del F3 está capturado** |

## Interpretación pre-registrada (para no racionalizar a posteriori)

| Resultado | Lectura |
|---|---|
| **Imagen + log vivo** | BCR = asesino nº1. **Primer display real del port** |
| **Log vivo, negro** | El prepare corrió y sobrevivió al BCR ⇒ el asesino está en la ventana 0,3-0,6 s y NO es el BCR. Siguiente: glitch de pinctrl en `gpio2` (el F1 lo dejó en `out low`) |
| **Wedge / panic** | Fenómeno **B** (muerte del SoC en el prepare). Bloquea el objetivo final hasta resolverlo |
| **0 marcas `UKE-P82:`** | Test inválido: el prepare no corrió. **No cuenta como ciclo** de la hipótesis |

## Contabilidad

- `panel-inherit` lleva **2 de 3 ciclos** (#611 L22, #612 L22b). **Este es el 3º y último.**
- Si sale negativo → la hipótesis se anota **REFUTADA** y se pasa a **F5** (modeset propio,
  plantilla Xiaomi Pad 6S Pro "sheng"), que es el objetivo real para Hyprland.