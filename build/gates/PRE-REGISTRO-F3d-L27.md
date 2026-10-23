# PRE-REGISTRO F3d/L27 — 12-oct (fidelidad Android, 5 correcciones)

## Advertencia metodológica (registrada ANTES de ejecutar)

Este build mete **5 cambios en un ciclo**, contra la regla del proyecto de "un cambio por ciclo"
(que L22b ya violó y por eso su resultado fue inatribuible). Se hace **a conciencia**, con estas
justificaciones:

- Los 5 son **correcciones de fidelidad**, no hipótesis nuevas: replican el comportamiento real de
  Android medido del `msm_drm.ko` (`SECUENCIA-ENCENDIDO-ANDROID-O82-20261012.md`).
- El objetivo es **atacar la divergencia estructural nº1** (`prepare_prev_first`), que sola explica
  el orden invertido frente a vendor.
- **Si L27 falla, el resultado NO es atribuible a un cambio concreto.** Queda registrado.

## Artefacto

- **sha256**: `41a7e6547d8c0f91158cb4f508e1d7a437afe532ab7051b2f2228694942c21cf`
- **Tamaño**: 100663296 B
- **Kernel**: `k52L27-build` sobre `k52L27-tree` (= L25 + 5 correcciones)
- **Diff**: `build/gates/patches/l27-fidelidad-android.diff` (dry-run OK)
- **Cmdline**: 606 B = L19 (580 B) **+ ` msm.uke_skip_mdss_reset=1`**, con **`video=DSI-1:d` PRESENTE**
  (igual que L25, el boot bueno — no se repite L26)

## Los 5 cambios

| # | Cambio | Migas | Justificación |
|---|---|---|---|
| 1 | **`prepare_prev_first=false`** | `L27-prev-first-off` | **Estructural nº1**: mainline corría prepare (rails+reset+DCS) ANTES del pre_enable del host; Android lo hace DESPUÉS (PHY/LP11/clocks primero) |
| 2 | Reset no asertado en probe (`GPIOD_ASIS`/Hi-Z) | `L27-gpios-hiz` | Android no toca el reset hasta `power_on`; mainline lo mantenía en reset ~4 s |
| 3 | Rail `vci`/L19 (2,6 V) | `L27-vci-ok` / `L27-vci-absent` | Android lo vota; mainline no. **Degradado a opcional** (el dtbo vivo no declara `vci-supply`) |
| 4 | Sleep final del reset 100 → **15 ms** | (sin miga) | El vendor usa `0/10,1/3,0/3,1/15` ms. Se revierte el discriminador r7 |
| 5 | Backlight a `enable()` (post-modeset) + **doble reset** | `L27-bl-enable`, `L27-rst-twice` | El 0x51 del vendor sale tras la 1ª trama, no en prepare |

**No aplicado**: `pinctrl active` explícito (requiere estados DT nuevos — fuera de un build solo-`boot.img`).

## Tabla de lectura pre-registrada

| Resultado | Lectura |
|---|---|
| **Imagen + log vivo** | El **orden** era el bloqueo. El panel enciende en mainline. |
| **`K47-pan-prep` > 0 pero negro** | El prepare corrió con el orden correcto y el panel **no** enciende ⇒ el problema está en el TDDI/link, no en el orden |
| **Wedge durante prepare** | Fenómeno B (muerte del SoC). Los tracks `K47-pan-pwron`/`-ok` dicen si los rails levantaron |
| **Wedge antes de `K47-pan-prep`** | El bind/modeset vuelve a matar ⇒ siguiente puerta es gatear `dpu_runtime_resume` (vbif+clk_bulk) |

## Medición válida (regla 4 — doble captura obligatoria)

El ACM es **lossy**: se pierden las marcas de la ventana 0,5–4,0 s. **Toda conclusión sale de `dmesg`
por SSH, NUNCA del ACM.** Antes de leer: `dmesg -n 7`.

## Preflight

- [ ] Batería, `slot-retry-count:a` (⚠️ cerca del techo)
- [ ] sha verificado antes de escribir
- [ ] `set_active a` **siempre**
- [ ] lector ACM armado antes del reboot

## Recuperación probada

```
fastboot flash boot_a build/bootimg/boot-uke-k52L25.img   # sha 04cd49803b9a…
fastboot set_active a
fastboot reboot
```