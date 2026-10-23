# PLAN DE PANTALLA — 12-oct (post-auditoría de 6 agentes)

> Base: `docs/historia/ESTADO-VIVO.md` (12-oct 03:5x). Todo lo que sigue está **medido**, no supuesto.

## Diagnóstico consolidado

**El aparato está sano.** El problema de pantalla es 100% de software, y ahora sabemos que hay
**dos锁定094 problemas distintos** que el proyecto llevaba días confundiendo:

| | **A — muerte de la imagen (boot)** | **B — muerte del SoC (prepare)** |
|---|---|---|
| Cuándo | ~0,5-1 s del boot | t≈1823 s, en el `prepare` manual |
| Qué muere | la imagen | el SoC entero, silencio total |
| Evidencia | `acm-trigger` 73 MB | `pantalla-esd-mask/witness/dmesg.log` |
| `msm_mdss_reset` | **sospechoso nº1** (3 vías convergentes) | **IMPOSIBLE** (no hay re-probe a esa hora) |

**Tres hechos que reordenan todo:**
1. La pantalla negra de L19 es `video=DSI-1:d` (conector `disabled`), **no un fallo**.
2. El aborto de L22b = **panic** (`pureason=0x800011`), y **ramoops está activo** para capturarlo.
3. El gate de la PLL **nunca disparó** (prefijo `dispcc.` vs `dispcc_sm8550.`) → L22b = 3 gates, no 4.

## Restricciones que mandan

- `slot-retry-count:a` = **7** ⚠️ — si no hay un boot exitoso, A cae a B. **`set_active a` + reboot siempre.**
- Batería **3543 mV** < gate 3700 → **conectar cargador antes de flashear**.
- `e2fsck` pendiente: 2 errores `doubly allocated` nuevos.
- Un cambio por ciclo. `panel-inherit` lleva **2 de 3 ciclos**.

## Fases

### F0 — Higiene ✅ HECHO (12-oct 03:2x–03:5x)
- [x] Diff L22b recuperado y verificado (`l22b-mdss-reset-vbif-clk.diff`)
- [x] `docs/historia/ESTADO-VIVO.md` reescrito, `NOTAS` con entrada, `docs/historia/AGENTS.md` con la IP real
- [x] Control L19 flasheado y verificado

### F1 — Dato gratis antes de gastar ciclos (SSH, cero escrituras) ✅ HECHO 12-oct 04:0x
- [x] `/proc/interrupts` (2 lecturas, 49 s de diferencia) → **H-6 REFUTADA**
- [x] `clk_summary` de dispcc → **H-2 APOYADA** (única con huella en el log)
- [x] `pm_genpd_summary` → **H-4 REFUTADA**
- [x] Estado de rails / GPIO / framebuffer

**Resultados medidos:**

| Hipótesis | Veredicto | Evidencia |
|---|---|---|
| **H-6 IRQ fantasma del mdss** | ❌ **REFUTADA** | `dsi_isr`×2 y `msm-kms` en **0 y quietas** en 49 s; `disp_rsc` en 0. No hay storm |
| **H-4 colapso del GDSC** | ❌ **REFUTADA** | `mdss_gdsc = on`; `pd_ignore_unused` funciona |
| **H-2 clobber de RCG** | ✅ **APOYADA** | `mdp_clk_src: rcg didn't update its configuration` (0,31 s) y `vsync_clk ... -22` (4,08 s) |
| ESD 86/87 | ❌ síntoma | Congeladas en 0/1; el `1` es el flanco de registro del probe, no actividad |

**Estado real del punto de partida** (lo que había que saber):

```
gpio2 (reset del panel) = out low   ← el driver lo deja en RESET desde el probe
vsp / vsn / l8 (vddil8b) = use=0   ← rails del panel APAGADOS
PLLs del DSI            = 0/0      ← apagadas (nunca hubo modeset)
disp_cc_mdss_mdp_clk    = 514 MHz  ← voto del ABL congelado por clk_ignore_unused
frame_done_cnt          = 0        ← cero tramas en ambas INTF
/dev/fb*                = NO existe
```

⇒ **El backlight 307/4095 de ESTADO-VIVO es remanente del ABL, no de Linux.** L19 nunca tocó el panel.
⇒ **Consecuencia para F3**: al quitar `:d`, el prepare tendrá que levantar rails → soltar reset →
arrancar PLLs → modeset, todo contra un `mdp_clk_src` que ya demostró resistirse a reprogramación.

### F2 — e2fsck ✅ HECHO 12-oct 04:0x (diagnóstico) 
- [x] `e2fsck -n /dev/sda32` (solo lectura) — **36 inodos** con `dtime=0`, **1 huérfano** (41094),
      diferencias de block/inode bitmap, free-blocks descuadrado en 2. **0 bloques dobles, 0 malos.**
- [x] `/forcefsck` creado
- **Hallazgo**: el fs está en `/dev/sda32` = **4.0 GB** (no 115 GB; ese es el tamaño de la partición
  `userdata`, el fs dentro está en 4 GB) — por eso el escritorio casi no cabía.
- **No hace falta reparar a mano**: `ukeinit-arch` (paso 7) corre `e2fsck -f -p` **obligatorio** sobre
  userdata en cada arranque. Los errores hallados son tipo preen (rc 0/1) ⇒ el próximo cold boot repara.
- Log: `build/evidencia/e2fsck-20261012-sda32.txt`

### F3 — El experimento que sí discrimina (1 build, 1 flash) — EN CURSO
**Objetivo único**: ¿el BCR mata un `prepare` **real**?

⚠️ **Corrección del plan original (12-oct, por el agente de build)**: el primer intento (L23) usó los
gates L22 de herencia, que hacen que `o82_prepare` haga `return 0` y **no ejecute la secuencia**. Eso
hace imposible probar el BCR sobre un prepare que no corre. **Se rehace como L24**: partir de L19 (sin
herencia), aplicar **solo** el hunk de `msm_mdss.c`, y cmdline **sin `video=DSI-1:d`** + el param del skip.

- Cmdline: **base L19 (580 B) − `video=DSI-1:d` + `msm.uke_skip_mdss_reset=1`** (sin `panel_inherit`)
- Migas esperadas: `UKE-P82:` de prepare **Y** la del reset saltado
- **Criterio de éxito**: el log de fbcon sobrevive a 0,6 s y a 4,1 s **con imagen**
- **Lectura de los 3 resultados posibles**:
  | Resultado | Significado |
  |---|---|
  | Pantalla con imagen | BCR = asesino nº1 **y** hay display. Huge |
  | Log vivo pero negro | El prepare corrió y sobrevivió al BCR ⇒ el asesino es otro de 0,3-0,6 s (p. ej. glitch de pinctrl en gpio2, que el F1 dejó en `out low`) |
  | Wedge / panic | Fenómeno **B** confirmado; `pureason` + ramoops lo capturan (ramoops **sí** está activo) |
- Los tres son informativos. No es un lottery donde solo hay premio.

> Nota: `PANEL-INHERIT §4` decía que `uke_panel_inherit` salía x1 en el Image; **medido: x2**
> (vive en `__param` y en `__ksymtab` por el `EXPORT_SYMBOL`). Corrección de conteo.

### F4 — Si F3 no basta: separar la PLL bien
- Arreglar el prefijo: `dispcc_sm8550.uke_skip_pll=1` (o leer `uke_panel_inherit()`)
- **Nunca más** un token sin verificar contra `KBUILD_MODNAME`

### F5 — Transición al objetivo real (modeset propio)
- Dejar `panel-inherit` como instrumento. El objetivo es un `prepare` completo + modeset propio
- Plantilla: **Xiaomi Pad 6S Pro "sheng"** (SM8550, display funcionando en mainline)
- Extraer la secuencia real del kernel downstream de Xiaomi (`xiaomi-uke-dev/opensource_xiaomi_uke-kernel`)
- Herramienta: `linux-mdss-dsi-panel-driver-generator`

## Críticas que se DEBEN cumplir

- ❌ Nada de multigate (L22b ya gastó un ciclo sin atribuir nada)
- ❌ Nada de flashes sin `set_active a` + reboot
- ❌ Nada de parches en el árbol sin diff (ya corregido una vez esta noche)
- ✅ Una variable por ciclo, con criterio de éxito **medible** antes de flashear
- ✅ Todo hallazgo a fichero + commit (protocolo de notas de `docs/historia/AGENTS.md`)

## Pregunta abierta (debe resolver el dueño)

El project's techo de 3 ciclos dice que a `panel-inherit` le queda **1 ciclo**. F3 es ese ciclo.
Si F3 falla, ¿se abandona el enfoque o se concede uno más? La evidencia upstream (3 series que
*añaden* el reset) y la de Android (sin `resets`) sugieren **abandonar** y pasar a F5.