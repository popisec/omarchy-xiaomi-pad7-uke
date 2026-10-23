# ROADMAP — Encender la pantalla en la uke (12-oct-2026)

> No es un plan de ciclos. Es el camino hasta que un píxel se encienda, con lo que cuesta cada
> tramo. Escrito tras 8 flashes, 6 builds y la auditoría adversarial de la noche del 12-oct.

## La verdad incómoda, en una tabla

Para que un panel encienda hacen falta 7 cosas. Tenemos 1 (y está rota) más la secuencia DCS.

| # | Paso | Estado | Coste restante |
|---|---|---|---|
| 1 | **El DPU bindea sin matar el SoC** | ❌ **BLOQUEO ACTUAL** | 1-3 ciclos |
| 2 | El conector detecta el panel | ❌ nunca probado | depende del 1 |
| 3 | `prepare()` corre: rails + reset | ❌ nunca probado | 1-2 ciclos |
| 4 | Host DSI + PHY + clocks a modo vídeo | ❌ nunca probado | 2-4 ciclos |
| 5 | Los 108 DCS de init | ✅ **idénticos a Android** | 0 |
| 6 | El TDDI enciende | ❌ nunca probado | 1-2 ciclos |
| 7 | Backlight + framebuffer | ❌ nunca probado | 1 ciclo |

**Los pasos 5-7 son los que se han intentado medir sin poder, porque el paso 1 mata antes.**

---

## FASE 0 — Cerrar lo que no es la pantalla (0 flashes, 1 sesión)

**Por qué antes**: si esto falla, el panel es irrelevante. Si funciona, tienes un producto
intermedio y cada flash posterior deja de ser todo-o-nada.

| # | Acción | Criterio de éxito |
|---|---|---|
| 0.1 | **Verificar la GPU real**: `eglinfo`/`vulkaninfo`/`glxinfo` por SSH; distinguir freedreno de llvmpipe; medir FPS de un glxgears | saber si la GPU renderiza por hardware o por software |
| 0.2 | **Hyprland headless**: `WLR_BACKENDS=headless` + captura `grim` cada 2 s a `/root/diag2/` | `hyprctl version` responde y hay imagen |
| 0.3 | **Espacio**: `/` en 4 GB con 510 paquetes; medir `df` y decidir `resize2fs` (la partición userdata es de 115 GB) | margen >1 GB |
| 0.4 | **e2fsck** (hay errores `doubly allocated` nuevos) | 0 errores |
| 0.5 | Leer la **contradicción `:d`**: trazar en `dmesg` del boot vivo el grafo de deferred-probe y compararlo con la hipótesis del bind | saber por qué `:d` decide vida/muerte si se aplica 0,4 ms después |

**Puerta**: si 0.2 falla (OOM/llvmpipe), la pantalla NO es el camino crítico y hay que replantear
el objetivo entero antes de gastar un slot más.

---

## FASE 1 — Matar la muerte del DPU bind (1-3 ciclos)

**Mecanismo ya entendido** (`docs/historia/revision/ANDROID-POWER-DPU-20261013.md`):

```
Android:  probe → msm_dss_clk_set_rate(SRC, 514 MHz) con clocks OFF  (solo cachea parked_cfg)
          enable → clk_prepare + clk_enable, SIN set_rate
          ⇒ el primer shared_enable RESTAURA el rate del ABL

Mainline: no siembra nada → parked_cfg = 0
          clk_bulk_prepare_enable → ESCRIBE 0 sobre el RCG vivo → glitch → muerte
```
`drivers/clk/qcom/clk-rcg2.c:1437` escribe `parked_cfg` **incondicionalmente**.

| Ciclo | Cambio | Criterio | Costo |
|---|---|---|---|
| 1a | **Sembrar el SRC desde CÓDIGO**, no desde DT: en `dpu_kms_hw_init()`, antes de `pm_runtime_resume_and_get`, `clk_set_rate(src, 514000000)` con el SRC en clk_rg2_shared | `clk_summary` muestra el SRC a 514 MHz y el boot pasa de 4 s | 1 build + 1 flash |
| 1b | Si 1a no basta: **gatear `dpu_runtime_resume`** (saltar `clk_bulk_prepare_enable` + `dpu_vbif_init_memtypes`), como el L29 ya construido | el bind pasa | 0 build (L29 ya existe) |
| 1c | Si 1b tampoco: **sembrar el SRC en `msm_mdss_init`** (antes de que nada toque los clocks), imitando el punto exacto del KMD | idem | 1 build |

**POR QUÉ el kernel y no el DT**: `s280` intentó sembrar por `assigned-clock-rates` en el dtbo y
falló. Lo más probable es que sembrar por DT no alcance el `parked_cfg` del SRC, porque el kernel
core lo calcula en `clk_rcg2_set_rate()` — y el vendor lo hace con una llamada explícita.

**CONDICIÓN DE PARADA**: 3 ciclos sin que el punto de muerte se mueva >0,5 s ⇒ la hipótesis del
SRC es **REFUTADA**, no "pausada". Se para la línea.

**RIESGO**: cada muerte es un slot (`slot-retry-count:a` entre 2 y 7). Con cargador y margen.

---

## FASE 2 — Que el conector detecte el panel (1-2 ciclos)

Solo cuando el paso 1 pasa. Criterio: `card1-DSI-1` pasa de `disconnected` a `connected` y
`modes` aparece.

**Si al pasar de `:d` a `:e` (enable) el panel no se detecta**: el problema es el bind del panel al
host DSI. Ahí hay que mirar si el `compatible` del panel está en la tabla del host y si los dos
`ports` del grafo OF resuelven (ya verificado en `ANDROID-DSI-PROFUNDO`: el panel se engancha a los
dos hosts en el probe, así que **esto debería funcionar**).

---

## FASE 3 — Que `prepare()` corra (1-2 ciclos)

Aquí por fin se ejecutan las 5 correcciones de L27, que hasta ahora **nunca se han probado**
(estaban en un build con `:d`, que impide el prepare).

| Sub-paso | Qué mirar | Criterio |
|---|---|---|
| 3.1 | Los rails suben: `regulator_summary` con `use=1` en vddil8b/vsp/vsn | los 3 rails ON |
| 3.2 | **Añadir `vci-supply` al dtbo** (L19, 2,6 V) — está portado en el driver pero el overlay no lo declara | rail L19 con `use=1` |
| 3.3 | El reset del TDDI se libera: `gpio2` sale de `out low` | gpio2 = input/hi-Z |
| 3.4 | Los DCS salen y el TDDI responde | `K47-pan-prep` > 0 y la consola muestra las respuestas |

⚠️ **Aquí es donde muere el SoC en el `o82_reset()` (fenómeno B de `ESD-MASK-TEST`)**. El
`usleep(100ms)` con el link DSI vivo es el punto conocido de muerte. **Es el riesgo real de esta fase.**

---

## FASE 4 — Modeset real (2-4 ciclos)

Solo con el panel preparado. El kernel hace un modeset completo por su cuenta (fbcon). Lo que hay
que resolver:

- DSC 1.1 a 3200×2136: mainline tiene el support pero el timing del vendor (slice 800×24, topología
  2 2 2, scr 0) hay que verificarlo
- Los porches por fps (120/144/90) y `panel-clockrate` 1189190000
- `MIPI_DSI_CLOCK_NON_CONTINUOUS`: **sigue puesto** en `mode_flags` pese al comentario que dice
  quitarlo, y contradice el contrato `lp11-init` del vendor (`ANDROID-DSI-PROFUNDO`)

---

## FASE 5 — El escritorio sobre la pantalla (depende de la 0)

Si la GPU es llvmpipe, esto es un problema **independiente del panel** y hay que atacarlo aparte.

---

## Orden de decisión

```
FASE 0 (0 flashes)
   ├─ 0.2 falla → el objetivo literal no es viable aquí. PARAR y replantear.
   └─ 0.2 vive  → seguir
FASE 1 (1-3 ciclos, con cargador y margen de slots)
   ├─ pasa     → FASE 2 → 3 → 4  (semanas, no ciclos)
   └─ 3 sin movimiento → SRC REFUTADO → DECISIÓN: seguir con bring-up serio (sheng/SM8550
                          como plantilla) o cambiar de objetivo/tablet
```

## Lo que NO es el camino

- **No más `panel-inherit`**: upstream va en dirección contraria (3 series **añaden** el reset MDSS
  a propósito) y no existe hand-off de panel en mainline para ABL.
- **No más ficheros de un solo bit**: 3 series upstream contienen la respuesta de los relojes; solo
  mainline, y esa diferencia es lo que queda.
- **No más capturas del ACM**: pierde la ventana 0,5-4,0 s. Para muertes pre-`switch_root` hace falta
  otro canal (volcado temprano en initramfs a región always-on, o ramoops con panic forzado).

## Coste total estimado

| Tramo | Ciclos | Tiempo |
|---|---|---|
| FASE 0 | 0 flashes | 1 sesión |
| FASE 1 | 1-3 | 1 noche |
| FASES 2-4 | 4-8 | **semanas** |
| FASE 5 | — | depende de la GPU |

**La honestidad**: la FASE 1 es un o dos ciclos y tiene hope real. Las FASES 2-4 son **trabajo de
bring-up**, no experiments. Si el objetivo es "Omarchy en la tablet", ese es el precio.