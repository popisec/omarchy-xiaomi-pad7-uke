# PLAN — VÍA DE FUERZA BRUTA CONTRA QUALCOMM (display)

> Escrito 12-oct 05:5x a petición del dueño: "quiero esta vía de fuerza bruta". Este documento **NO** es
> una recomendación: es el enunciado de la estrategia fuerte para que la critiquen. Los subagentes de
> crítica tienen como tarea principal **refutarla**, no refinarla.

## Diagnóstico heredado (lo que ya sabemos, todo medido)

| Hecho | Evidencia |
|---|---|
| L25 (`:d` presente + skip BCR) **vive**; panel probean x5, engancha 2 DSI, DPU bindea a 3,965 s | `NOTAS` 05:1x |
| L26 (sin `:d`) **muerto a 4,03 s**, `K47-pan-probe`=0 | `NOTAS` 05:5x |
| `:d` no es el asesino del panel: es lo que deja llegar vivo al probe | L26 |
| El BCR es *load-bearing* para el bind con splash vivo, pero no es el asesino | L24 vs L25 |
| `o82_prepare` nunca ha corrido en ningún ciclo | `K47-pan-prep` = 0 en L19/L24/L25/L26 |
| Android: DT sin `resets` en mdss; su `msm_drm.ko` **no stripped**, tiene `sde_kms_cont_splash_config` | `stock/modules`, `android-snap` |
| El fuente vendor es público y accesible (`xiaomi-uke-dev/…`, rama `air-t-oss`) | `git ls-remote` OK |

## Las 4 vías fuertes que se consideran

### BF-1 — Raw modeset sobre el kernel que ya vive (L25)

**Idea**: L25 tiene *todo* bound (panel, 2 DSI, DPU, tx-alloc). Lo único que falta es un modeset.
En vez de quitar `:d` por cmdline (que mata el bind), **forzar el modeset desde userspace** con
`modetest` / un cliente de KMS, gateando el path que hoy se come al SoC en `dpu_kms_hw_init`.

- **Compra**: un binario. Si el panel enciende, tenemos display **sin reescribir el driver**.
- **Riesgo**: `modetest` ya colgó en intentos previos (veto #P43) — el driver se defendant's..
- **Pregunta abierta**: ¿el bind muere por el `drm_fb_helper` de fbcon, o por el propio
  `dpu_kms_hw_init`? Sin resolver eso, "forzar modeset" puede ser lo mismo que L26 con otro nombre.

### BF-2 — Secuencia de panel copiada del vendor, a pelo

**Idea**: traer `dsi_display.c` + el `dsi-panel-*.dtsi` del o82 del repo `air-t-oss` y **replicar su
`prepare` literalmente** (orden de rieles, secuencia de reset, DCS, timings), sin depender de que
mainline infiera nada. Es decir: sustituir el "modo de descubrir" por el "modo de copiar".

- **Compra**: el orden correcto de rebote, que es justo lo que hemos fallado en estimar.
- **Riesgo**: los DCS vendor usan extensionesQualcomm (`0x00-0xFF` proprietary sets) que el
  controlador TDDI de mainline puede no traducir igual; el timing dual-DSI/DSC también.

### BF-3 — Replay de registros (el splitter más bestial)

**Idea**: el ABL deja el DPU escaneando un framebuffer estático en `0xE3940000` y funciona. Volcar
**el estado completo de registros del DPU+DSI que deja el ABL** (`dmesg`/`devmem` en probe temprano,
nunca en runtime — regla 3 del proyecto) y escribir un blob que lo restaure tras el probe de mainline.

- **Compra**: no depende de entender la secuencia; depende solo de reproducir bytes.
- **Riesgo**: volcar rangos de MMIO/regmap **cuelga la tablet** (LECCIONES ronda 33, regla dura).
  Es la vía con más probabilidad de brick y la que menos información da si funciona.

### BF-4 — Kernel vendor (SDE) + rootfs Omarchy

**Idea**: arrancar el kernel Android stock (`stock/images`, o el `-oss`) que **sí** tiene display
funcionando, y meter encima laraíz de Omarchy. El panel lo maneja `msm_drm.ko` (SDE).

- **Compra**: display garantizado (Android lo hace), sin tocar el driver.
- **Riesgo**: SDE no expone KMS estándar ⇒ **Hyprland no arranca**. El objetivo (escritorio Omarchy)
  no se cumple aunque la pantalla encienda. Además la GPU passa a KMD y se pierde el freedreno de
  mainline que hoy funciona (FD735 verificado).

## Qué se le pide a la crítica

Cada subagente debe, **con datos del proyecto**:
1. **Refutar** su vía asignada con evidencia concreta (no opiniones).
2. Decidir si es **ejecutable con los artefactos que ya tenemos** (L25 vivo, DT, `msm_drm.ko`, red).
3. Si la vía es un callejón, **nombrar la alternativa más barata**.
4. Estimar **ciclos de flash** y **coste de recuperación** (recordar: `slot-retry-count` va justo).

## Decisión que hay que tomar antes de tocar la tablet

- [ ] ¿Se acepta BF-3 (volcado de registros) sabiendo que puede colgar/brickear?
- [ ] ¿Se acepta BF-4 (kernel vendor) sabiendo que mata el objetivo de Hyprland?
- [ ] ¿O BF-1/BF-2, que no comprometen el objetivo?

---

> **Estado**: este plan está **pendiente de crítica**. No se ha ejecutado nada de él.
> La tablet está en el último estado bueno (L25 flashed, SSH, FD735, panel probean x5).