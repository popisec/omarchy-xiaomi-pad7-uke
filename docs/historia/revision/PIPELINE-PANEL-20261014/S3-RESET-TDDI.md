# S3 — Reset/power del TDDI: fidelidad de la secuencia vs Android (14-oct-2026)

## 1. Qué he leído (lista con fichero:línea de lo relevante)

Driver mainline vivo:
- `build/kernel-pokes/k52-L16-tree/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c:258-285` (`o82_reset`), `:287-323` (`o82_power_on`, 3 rails), `:325-409` (`o82_prepare`), `:411-455` (`o82_unprepare`), `:640-654` (probe: `GPIOD_OUT_HIGH` / `GPIOD_OUT_LOW` en herencia), `:726` (`prepare_prev_first=true`), `:595-601` (`mode_flags` con `CLOCK_NON_CONTINUOUS` pese al comentario K48-A).
- `build/gates/patches/l27-fidelidad-android.diff` entero (187 líneas): 7 hunks L27, generados 12-oct, **nunca flasheados** (ROADMAP FASE 3 los reclama; el vivo L45 no los lleva — verificado: el vivo aún tiene `usleep_range(100000…)` en `:282` y `GPIOD_OUT_HIGH` en `:645-647`).
- `build/gates/patches/k49-esd-gpios.diff:1-89` (registro ESD + threaded-IRQ, ya en el vivo `:603-690`).

Vendor/Android (fuente primaria = desensamblado `msm_drm.ko`, no memoria):
- `build/gates/revision/SECUENCIA-ENCENDIDO-ANDROID-O82-20261012.md:64-104` (§A.1 pre_prepare = rails+reset+pinctrl; §A.2 prepare = **2º reset**, PRE_ON vacío), `:338-341` (reset-sequence DT `0/10,1/3,0/3,1/15` ms sobre TLMM 2 active-high).
- `docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md:336-368` (§3: `dsi_panel_reset` literal — `direction_output_raw`, loop set+`usleep_range_state`, **deja un gpio en INPUT** al final `0x156100`; tabla comparativa vs L27), `:372-414` (§4: orden rails vddio+vci → vddil8b→vsp→vsn, loads 300 mA, 2 ms post-on), `:418-433` (§5: ESD/TE no intervienen en power-on; TDDI confirmado `mi,is-tddi-flag`), `:505-518` (§8 tabla de portabilidad, ítems 5/8).
- `docs/historia/revision/ROADMAP-PANTALLA-20261013.md:85-98` (FASE 3: L27 nunca probado; **fenómeno B**: muerte del SoC en `o82_reset()`, `usleep(100ms)` con link vivo = riesgo real).
- `docs/historia/revision/ESD-MASK-TEST-20261012.md:30-52` (muerte +35,9 ms tras `w4-done`, ESD = síntoma único, no storm), `:54-65` (conclusión mecanismo TDDI).
- `build/gates/revision/HALLAZGO-L33-DEATH-20261013.md:28-43` (boot-path: reset **completa** en 123 ms, ESD ×2, muerte después en el primer DCS `video-done timeout`), `:91-102` (qué queda exonerado: PLL, clocks, prepare, power).
- `build/gates/revision/L39-PLAN-20261013.md:351-371` (L38 = reset 15 ms, «nunca flasheado ni medido» solo; L39 lo heredó empaquetado).
- `~/proyectos/ubuntu-permanente/docs/REFUTADO.md` + `LECCIONES.md`: grep `L27|L38|doble reset|GPIOD_ASIS|Hi-Z` = **0 coincidencias** (nada que prohíba esta línea).

Tablet viva (solo lectura, 14-oct-2026, boot L45 `video=DSI-1:d`):
- `/sys/kernel/debug/gpio`: `gpio2 : out low` (reset asertado desde el probe, coherente con `GPIOD_OUT_HIGH` + flag ACTIVE_LOW); `gpio168/169 : in high` (ESD en reposo HIGH, TDDI sin power); `gpio74/75 : out low` (vsp/vsn OFF, prepare nunca corrió); `gpio77 : in low func1` (TE muxado a mdp_vsync).
- DT vivo `/sys/firmware/devicetree/base/soc/display-subsystem@ae00000/dsi@ae94000/panel@0`: props = `reset-gpios` (`00 00 01 6b … 02 … 01` = TLMM 2 flag 1 ACTIVE_LOW), `esd-err-gpios` (TLMM 168/169, flags **0** — el vendor usa `0x2004`, divergencia menor sin efecto con ambos flancos armados), `vddil8b/vsp/vsn-supply`, `backlight`, `compatible=xiaomi,uke-o82-4202-0b`. **`vci-supply` AUSENTE** (compañero S1).
- `regulator_summary`: `pmxr2230_l19 2600mV use 0/0` (rail existe a voltaje vendor pero **sin voto**); vsp/vsn con consumidores del panel pero OFF (gpio74/75 low).
- `dmesg`: solo `UKE-K49` (ESD armadas val=1 + fires de armada); cero `UKE-P82 prepare/power` (el `:d` lo impide). El reset del TDDI **nunca se ha ejecutado en el vivo L45**.

## 2. Estado real del asunto (evidencia)

Tabla punto por punto mainline-vivo vs vendor (niveles físicos, no valores gpiod):

| # | Punto | Android (medido) | Vivo L45 | Veredicto |
|---|---|---|---|---|
| 1 | Niveles/delays reset | LOW 10 ms → HIGH 3 ms → LOW 3 ms → HIGH +15 ms (DT `qcom,mdss-dsi-reset-sequence`, PROFUNDO §3) | Mismos niveles (inversión SW active-low documentada `:258-263`), pero final **100 ms** (`:282`, discriminador r7) | **DIVERGE: 100 vs 15 ms** |
| 2 | Reset en probe | Nada hasta power_on (gpio en estado ABL) | `GPIOD_OUT_HIGH` = panel **~4 s en reset** cada boot (`:645-647`; vivo: gpio2 out low) | **DIVERGE** |
| 3 | Nº de resets | **2** (pre_prepare + prepare, literal del binario, SECUENCIA §A.2) | 1 | **DIVERGE** |
| 4 | Estado reset tras secuencia | Un gpio a INPUT (`dsi_panel_reset` `0x156100`) | OUTPUT/HIGH | Divergencia menor (ver §6: NO portable — el gpio `+0x908` no está identificado) |
| 5 | Sleeps | `usleep_range_state` | `usleep_range` | Equivalente |
| 6 | Orden rails | vddio+vci → vddil8b→vsp→vsn, 300 mA + 2 ms (`:392-400`) | vddil8b→vsp→vsn OK; **vci sin votar** (DT sin `vci-supply`, L19 use 0/0 en vivo) | Hueco vci = **S1**, no S3 |
| 7 | Orden vs host/LP11 | rails+reset con PHY en LP11 + host iniciado (pasos 4→9) | `prepare_prev_first=true` (`:726`) = prepare **antes** del host | Estructural = **S2**, no S3 |
| 8 | ESD durante reset | No interviene en power-on (solo pinctrl active; PROFUNDO §5) | K49 arma 86/87 al probe; en vivo solo fires de armada val=1 | OK; ESD-MASK demuestra que el fire único val=0 es **síntoma**, no causa |

**Fenómeno B, documentado con precisión** (corrección a ROADMAP:97-98, que lo cita de memoria):
- Cara B1 (path enable vía modetest, ESD-MASK-TEST:33-43): muerte **+35,9 ms tras `w4-done`**, es decir **dentro del `usleep(100ms)` final** (`R2-ok` nunca se loguea). Reproduce 6/6.
- Cara B2 (path boot, HALLAZGO-L33:36-43): el **mismo** reset de 100 ms **completa** (`pre-rstOK` a +123 ms), ESD ×2, y la muerte se desplaza al primer DCS (`video-done timeout` 70 ms).
- Conclusión honesta: el sleep de 100 ms **no es letal per se** (B2 lo sobrevive); B1 muere en la ventana post-`w4-done` con el link vivo. La variable viva es el **timing final + estado del link**, y L38 (15 ms) **nunca se ha medido solo** (L39-PLAN:367). El doble reset de L27 **duplica la exposición** a la ventana B1: es el riesgo real de esta fase, asumido a cambio de fidelidad vendor.

## 3. Cambio propuesto (diff exacto, con fichero:línea)

`docs/historia/revision/PIPELINE-PANEL-20261014/s3-reset-tddi.diff` (formato `patch -p1`, verificado `--dry-run` OK contra el vivo). Subconjunto reset/power de L27, sin tocar vci/host/backlight (compañeros S1/S2/S6):

1. `o82_reset()` (vivo `:262`): `gpiod_direction_output(ctx->reset_gpio, 1)` al entrar — el gpio llega en Hi-Z desde el probe (ex-L27 §E.3).
2. `o82_reset()` (vivo `:282`): final `usleep_range(100000,101000)` → `usleep_range(15000,15500)` — vendor 15 ms; revierte el discriminador r7 (ex-L27 §E.5; = L38).
3. `o82_prepare()` (vivo `:351-354`): segundo `o82_reset()` + poke `S3-rst-twice` — doble reset vendor (ex-L27 §E.5+§A.2).
4. `o82_probe()` (vivo `:640-647`): `GPIOD_OUT_HIGH / GPIOD_OUT_LOW-herencia` → `GPIOD_ASIS` + poke `S3-gpios-hiz` — Android no toca el reset hasta power_on (ex-L27 §E.3).
5. `err:` (`:406`) y `o82_unprepare()` (`:450`): `gpiod_set_value_cansleep(…,1)` → `gpiod_direction_output(…,1)` — seguro desde cualquier estado previo (Hi-Z incluido).

Coordinación (NO en este diff, propiedad de otras secciones): vci driver+DT (**S1**), `prepare_prev_first=false` (**S2**, orden host), backlight a `o82_enable()` (**S6**; el vivo L45 ya difiere BL al core vía `drm_panel_of_backlight`, `:745-758`), `CLOCK_NON_CONTINUOUS` (**S6**).

## 4. Criterio pasa/falla prefijado (comando + salida esperada)

Flash con display habilitado (quitar `:d`; requiere FASE 1 del ROADMAP viva — sin bind no hay prepare). Doble captura obligatoria (consola ACM + `dmesg -w` por SSH; LECCIONES regla 4):

- **PASA** si en `dmesg`: `K48-rst-A … K48-w4-done … K48-rst-R2-ok` aparecen **×2** (`S3-rst-twice`), `release2(15ms)` en el log, y el punto de muerte (si la hay) **se mueve** más allá del primer DCS (p.ej. `cmd#0` con respuesta o timeout distinto al `video-done` de L33). Más `gpio2` ≠ `out low` permanente tras prepare.
- **FALLA** (refuta la hipótesis «el reset infiel es lo que calla al TDDI») si: la firma de muerte es idéntica a L33 (`video-done timeout` en `cmd#0` tras doble reset completo) **o** idéntica a B1 (muerte en la ventana post-`w4-done` con 15 ms). En ambos casos anotar «secuencia vendor refutada como causa del silencio» y NO reintentar (techo 3 ciclos por hipótesis).
- Señal de peligro que **para** la línea: muerte **antes** de `K48-rst-A` (el ASIS deja flotante algo que el OUT_HIGH sujetaba) → revertir hunk 4 solo.

## 5. Riesgos y refutaciones que aplican (REFUTADO/LECCIONES)

- **Fenómeno B1**: el doble reset duplica el paso por la ventana letal post-`w4-done`. Aceptado: si la muerte se adelanta al reset (antes completaba), es señal diagnóstica, no regresión — indica acoplamiento reset↔link vivo (competencia S4/G8).
- **LECCIONES regla 2**: `dmesg -n 7` antes del disparo (los `UKE-P82`/`UKE-K47c` son KERN_INFO).
- **LECCIONES regla 5**: `sync` antes de cualquier reset; presupuesto de slots/batería por ciclo.
- **ESD-MASK-TEST:54-65**: las IRQ 86/87 son síntoma; NO enmascarar ni desarmar K49 en este ciclo (cambiaría 2 variables).
- **Herencia**: el hunk 4 elimina la rama `GPIOD_OUT_LOW` de `uke_panel_inherit()`. Si el ciclo corre sobre base con inherit activo, el reset queda flotante en vez de liberado — verificar `uke_panel_inherit()` en el boot medido; si inherit está activo, este diff NO aplica (fuera de alcance, ver §6).
- Nada en REFUTADO.md/LECCIONES.md prohíbe L27/L38/ASIS/doble-reset (grep vacío, §1).

## 6. Qué NO hacer / lo que queda fuera

- **NO** portar «gpio a INPUT tras el reset» (PROFUNDO §3, `0x156100`): el gpio afectado (`panel+0x908`) **no está identificado**; poner el reset a INPUT sería inventar. Hipótesis marcada, pendiente de RE.
- **NO** tocar `vci-supply` (S1), `prepare_prev_first` (S2), backlight-enable ni `CLOCK_NON_CONTINUOUS` (S6), ni pinctrl/TE/ESD-flags (OK o benignos, §2 tabla).
- **NO** re-probar G4/G5/G6/G7. **NO** flashear desde esta sección: el diff es propuesta para el ciclo de mañana, un cambio por ciclo (si S1 entra antes, este diff sigue aplicando — hunks disjuntos — pero el criterio §4 debe re-basarse).
- L27 contenía además esos hunks excluidos; este diff es deliberadamente el subconjunto reset/power para no apilar variables.
