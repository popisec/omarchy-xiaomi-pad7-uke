# FASE 1 — CRÍTICA REVISADA (13-oct-2026, revisor adversarial + tablet viva)

> Misión: verificar los 5 hallazgos que reescribieron el plan, auditar la Fase 1
> corregida, investigar el modeset en vivo sin flashear y diseñar el experimento óptimo.
> Método: SSH solo-lectura a `192.168.42.129` (L25-diag, `7.2.0-rc2-palawan`, cmdline con
> `video=DSI-1:d`) + lectura del árbol `build/kernel-pokes/k52L25-tree`.
> Cero flashes, cero reinicios, cero escrituras fuera de lecturas. **No se ejecutó ningún
> commit de modeset** (rationale en §C; requiere ventana con el dueño).

---

## A. Verificación de los 5 hallazgos

| # | Hallazgo | Veredicto | Evidencia |
|---|---|---|---|
| 1 | GPU = freedreno FD735 a 1066 FPS real | **CONFIRMADO con matiz** | `eglinfo -B` vivo: `FD735` en core/compat/ES (GBM, surfaceless…), `renderD128` presente, log Hyprland/aquamarine: `Renderer: FD735` sobre `renderD128`, backend DRM card1 msm-kms atómico. **Matiz**: `llvmpipe` SÍ aparece en UNA plataforma (`Platform Device platform`, enumeración CPU de secours) — la frase "no aparece en ninguna plataforma" de FASE0-RESULT es literalmente falsa, aunque irrelevante en fondo. El número 1066 FPS no se re-midió (se acepta la metodología descrita + GMU fw v4.5.1 viva + 0 faults). |
| 2 | Hyprland corre en DRM/card1 pero `grim` falla por `:d` (conector disconnected) | **CONFIRMADO** | Hyprland 0.56.2 PID 795 (sddm) vivo; `hyprctl version` responde (con env de sddm); `hyprctl clients` = `no open windows`; log aquamarine: `Starting backend for /dev/dri/card1, with driver msm-kms`, `found 2 CRTCs`, `connector DSI-1, has crtc -1`; `grim` ejecutado ahora mismo → `no wl_output`. `card1-DSI-1/status=disconnected`, `card1-Writeback-1/status=unknown`, ambos `crtc=(null)`. Nota: `hyprctl monitors` → `unknown request` (sintaxis 0.56, irrelevante). |
| 3 | `:d` se aplica a 3,960546 s (~40 ms antes de la muerte ~4,0 s); la muerte está en el commit del modeset, no en el bind | **CONFIRMADO** | Traza viva reproducida línea a línea: `vsync_clk … (-22)` @3.958704 → `bound ae94000/6000.dsi` @3.959154/66 → `dpu_kms_hw_init rev 0xa0010000` @3.960245 → **`forcing DSI-1 connector off` @3.960546** → `Initialized msm-kms 1.13.0` @3.963565 → `Cannot find any crtc or sizes` ×2 @3.963656/724 → vive. Mecanismo verificado en código: `o82_get_modes()` (`panel-xiaomi-o82-dualdsi.c:442-474`) devuelve los modos **incondicionalmente, sin comprobar `prepare()`** → sin `:d` hay conector + modos → `find_sizes` OK → commit → muerte ~4,0 s (L26/L28/s280, mismo punto). Esto **corrige** a `RESUMEN-SESION-20261012.md` §3.4/§4 ("`:d` causalmente inerte, 0,4 ms después del punto de muerte"): el punto de muerte estaba mal situado; estaba en el commit posterior, no en el bind. FASE0-RESULT §0.6 ya lo había corregido; esta auditoría lo confirma con traza independiente. **Limitación honesta heredada**: no existe `dmesg` de boot muerto para el diferencial; el "7/7 determinista" descansa en wedge-logs ACM (instrumento lossy). |
| 4 | El OPP ya siembra el SRC a 514 MHz (`dpu_kms.c:1304-1308`) antes del primer enable; `parked_cfg=0` es FALSO | **CONFIRMADO (orden + valor), con una consecuencia letal para la Fase 1** | Orden verificado: `msm_drm_init` (`msm_kms.c`) llama `priv->kms_init()` (= `dpu_kms_init`, con `opp_find_freq_floor(ULONG_MAX)` + `dev_pm_opp_set_rate` @1304-1308) en `:292` **ANTES** que `kms->funcs->hw_init()` (= `dpu_kms_hw_init`, con `pm_runtime_resume_and_get` @1162 y el `clk_bulk_prepare_enable` sospechoso) en `:307`. Tabla OPP (`palawan.dtsi:3446+`): techo = `opp-514000000` → la siembra resuelve a 514 M. Vivo: `disp_cc_mdss_mdp_clk_src … 514000000`, enable 1/1; `core` es el clkname del OPP (@1395, rama con propagación CCF al RCG → con clocks apagados solo cachea `parked_cfg`, sin tocar HW, exactamente el diseño `shared`). **Consecuencia**: `parked_cfg=0` en el primer enable del SRC es FALSO en este árbol — la hipótesis del SRC murió **por medición en vivo (0 flashes), no hacía falta s280**. |
| 5 | El header de clocks SÍ existe, ID 62 correcto; s280 falló por redundancia, no por ID | **CONFIRMADO (header + ID); IMPRECISO (el "por redundancia")** | `build/kernel-pokes/k52L25-tree/include/dt-bindings/clock/qcom,palawan-dispcc.h:72`: `DISP_CC_MDSS_MDP_CLK_SRC 62`. El ID de s280 era correcto. "Falló por redundancia" es la **mejor explicación** (SRC ya a 514 M por ABL + OPP + `clk_ignore_unused`), pero con los datos actuales **no es distinguible de "falló por irrelevante"** (ambas predicen el mismo wedge en el mismo punto). Lo afirmable: s280 no podía discriminar nada; era un flash no-informativo se mire como se mire. |

### Cadena de correcciones (para que no se pierda)

`RESUMEN-12oct` ("`:d` inerte, lo letal = skip BCR") → `FASE0-RESULT-13oct` ("muerte en el
commit, `:d` sí causal") → **esta auditoría: CONFIRMA lo segundo con traza y código
independientes**. Queda cerrado: no reabrir "`:d` inerte".

---

## B. Veredicto sobre la FASE 1 (ROADMAP §FASE 1: 1a sembrar SRC en código / 1b gatear runtime_resume L29 / 1c sembrar en `msm_mdss_init`)

**Veredicto: CANCELAR 1a y 1c, REDEFINIR 1b. No ejecutar la Fase 1 tal como está escrita.**

| Ciclo | Qué proponía | Auditoría |
|---|---|---|
| 1a (sembrar SRC desde código en `dpu_kms_hw_init`) | Atacar `parked_cfg=0` | **CANCELADO: el problema que ataca no existe.** El OPP ya siembra 514 M antes del primer enable (§A.4). Sembrar otra vez es s280 con otro disfraz. Coste evitado: 1 build + 1 flash + 1 slot. |
| 1c (sembrar SRC en `msm_mdss_init`) | Lo mismo, más temprano | **CANCELADO por el mismo motivo.** Mismo SRC, mismo `parked_cfg` ya-no-cero, misma predicción (wedge idéntico). |
| 1b (gatear `dpu_runtime_resume`, L29 ya construido) | Saltar `clk_bulk_prepare_enable` + `dpu_vbif_init_memtypes` | **REDEFINIR, no repetir a ciegas.** L29 ya se probó → boot loop **posterior** al punto 4,0 s (gadget enumeró, sin `ttyACM0`, 0 bytes = sin dato, no sin evento). El gate mueve el punto de muerte, no lo elimina — hay un **segundo punto de muerte** (candidato: `disable_unprepare` sobre clocks no preparados / `clk_disable_unused` apagando RCG, ver NOTAS 13-oct 00:4x). Repetir L29 sin UKE-DIAG es quemar otro slot para el mismo "sin dato". |

### B.1 — ¿Es 1a' (`pr_info` en `clk_rcg2_shared_enable/set_rate`) "sin cambio de comportamiento"?

**No. Tres objeciones, en orden de gravedad:**

1. **Mide parcialmente lo incorrecto.** Los enables del bind ocurren **idénticos** con y sin
   `:d` (el bind sobrevive en ambos mundos). El delta vivo/muerto está en los enables del
   **commit** (~4,0 s, solo sin `:d`). 1a' instrumenta el camino común y deja el
   discriminante en penumbra, salvo que el diferencial se capture en un boot muerto (que
   exige el flash que se quería evitar).
2. **No es neutra en timing.** `shared_enable` corre bajo `enable_lock` (spinlock, irqs off);
   `printk` no duerme pero vuelca a consolas síncronas (`ttyGS0` gadget a 115200 entre
   ellas) → jitter de milisegundos **dentro de la secuencia del RCG que la propia hipótesis
   declara sensible a glitches**. En el mejor caso es ruido; en el peor, desplaza el punto
   de muerte y se lee como señal. "Imprimir no cambia nada" es falso aquí por el mismo
   motivo por el que el ACM es lossy: la consola lenta forma parte del sistema medido.
3. **Riesgo de hang: bajo pero no cero.** `pr_info` bajo spinlock es práctica común y no
   cuelga por sí mismo; el riesgo real es (2), no un deadlock. Aun así, spam (cada enable
   de rama compartida) + consoles lentas en el path de power = combinación que no se mete
   en un kernel de bring-up sin necesidad.

### B.2 — Si `:d` ya resuelve el diagnóstico, ¿hace falta la Fase 1?

No. La Fase 1 asumía "el bind es el bloqueo" y proponía sembrar un SRC que ya está sembrado.
El bloqueo real es **el commit atómico con conector habilitado**, y sus candidatos vivos NO
son el SRC: son el path de enable DSI/PHY/link-clocks, `dpu_vbif_init_memtypes`
incondicional (`dpu_kms.c:1281` y `:1466`, sin guards — el vendor los salta por partida
doble con splash, `ANDROID-POWER-DPU` §2), y el segundo punto de muerte que L29 insinuó.
**Gastar 1-3 ciclos en 1a/1c sería cometer por segunda vez el error que esta auditoría
tiene orden de impedir: flashear una hipótesis ya refutada por medición en vivo.**

### B.3 — Experimento mejor que 1a' con lo que ya se sabe

Sí, y cuesta **0 builds + 0 flashes**: traza `ftrace` de clocks armada **en vivo** +
commit de writeback (§D). Los eventos `clk_enable/clk_prepare/clk_set_rate` **existen** en
este kernel (`/sys/kernel/debug/tracing/events/clk/`, verificado) y son observación con
**cero perturbación del timing** (buffer en RAM, sin consolas). 1a' queda obsoleta antes de
escribirse: todo lo que sus `pr_info` dirían lo dice `ftrace`, sin build, sin flash y sin
jitter de consola.

---

## C. Lo que se puede hacer HOY sin flashear (ejecutado en esta sesión)

| Prueba | Resultado |
|---|---|
| `eglinfo`, `hyprctl`, `grim`, `clk_summary`, `dri/1/state`, `clients`, log aquamarine | Ver §A (todo solo-lectura, reversible, seguro) |
| `modetest` como vía de modeset | **Descartado por dos motivos independientes**: (1) el binario existe (`/usr/bin/modetest`) pero `-M msm` abre `card0` (GPU-compute, sin KMS → `drmModeGetResources: Operation not supported`) y no hay forma de dirigirlo a `card1`; (2) aunque la hubiera, **Hyprland es master de `card1`** (`clients`: `Hyprland … y … master`) y ningún otro cliente puede hacer commit mientras lo sea. |
| Sink writeback | **Existe y está libre**: `connector[38]: Writeback-1`, `crtc=(null)`, `status=unknown`, `modes` vacío (normal en writeback: el modo se pone explícito), 2 CRTCs con `enable=0`, encoders presentes. Un commit writeback-only **no toca DSI/PHY/panel/`prepare`/backlight**: es el discriminador DPU-vs-DSI perfecto. |
| Commit de modeset en vivo | **NO ejecutado (correctamente)**. Requiere ser master → parar `sddm`/Hyprland + herramienta DRM propia (`python3` + `libdrm` + headers presentes en la tablet; sin `gcc` → ctypes o binario cruzado desde PC). **Riesgo**: si el commit cuelga el SoC, el watchdog está roto y haría falta reset físico + recuperación por el dueño. Propuesta con rationale y criterio en §D; no se hace sin ventana acordada. |

Rationale del no-commit (para el registro): el commit writeback ejercita `dpu_runtime_resume`
+ programación de VBIF/CRTC/planos con los clocks ya a 514 M y sin scanout activo — el
clobber del SRC, de existir, ya habría ocurrido en el bind (que sobrevivió). Riesgo
estimado BAJO pero con cola catastrófica (pérdida de SSH hasta intervención física);
la regla del proyecto ("sin dato" ≠ "sin evento", instrumento garantizado) exige además
`ftrace` + `drm.debug` armados ANTES, no después. Hacerlo ahora, sin dueño delante,
violaría "pruebas reversibles y SEGURAS".

---

## D. El experimento óptimo propuesto (0 builds, 0 flashes, 1 ventana con el dueño)

**D-0 (hoy, 0 riesgo, por SSH):** armar `ftrace` (`events/clk/*_enable/*_prepare/*_set_rate*`,
`drm.debug=0x1e` opcional) y validar el instrumento con un enable cualquiera. Cierra B.3.

**D-1 (el discriminador, con el dueño delante):**
1. `systemctl stop sddm` (Hyprland suelta el master; SSH intacto; reversible con `start`).
2. Herramienta mínima (ctypes/`libdrm`): `open(/dev/dri/card1)` → `SET_MASTER` →
   `ADD_FB2` (dumb, p. ej. 1600×1068, formato con modifiers de los 41 que exponen los
   planos) → commit atómico `Writeback-1@crtc-0` con modo explícito + `WRITEBACK_FB_ID`
   + `OUT_FENCE_PTR`, bajo `ftrace` clk armado.
3. **Criterio de éxito**: el commit retorna 0, el out-fence seala y el dumb buffer de
   writeback contiene datos no-ceros → **DPU + VSYNC + memtypes PROBADOS**; el asesino vive
   en el path DSI/PHY/`prepare` y la Fase 1 queda enterrada para siempre.
   **Lectura si cuelga**: la traza `ftrace` (en RAM; si se pierde, UKE-DIAG la persiste)
   dice el último `clk_enable/set_rate` antes del silencio → el siguiente gate va con
   nombre y apellido, no con ranking.
4. `systemctl start sddm` → Hyprland recupera el master; estado final = estado inicial.

**D-2 (ramas, según D-1):**
- Si D-1 OK → el siguiente experimento es el enable DSI **sin panel** (bridge `pre_enable`
  con el TDDI en reset sostenido por `gpio2`), mismo instrumento. El panel deja de ser
  sospechoso hasta que el link funcione.
- Si D-1 cuelga → redefinir 1b con la traza: gatear **solo** lo que la traza señale, con
  UKE-DIAG como lector garantizado. Prohibido re-flashear L29 tal cual.

**Coste comparativo**: Fase 1 (1a+1c) = 2 builds + 2 flashes + 2 slots para una hipótesis
muerta. D-0+D-1 = 0 builds + 0 flashes + 1 ventana supervisada para una respuesta
definitiva DPU-vs-DSI. **No hay empate.**

### Errores a no repetir (del historial, vinculantes para D)

1. ACM lossy: "0 bytes / 0 marcas" = "sin dato", nunca "sin evento" (4 veces pagado).
2. No flashear hipótesis refutadas en vivo (s280 ← `parked_cfg=0`; no repetir con 1a/1c).
3. Un cambio por ciclo; todo gate con diff (L22b sigue siendo la referencia de lo que NO).
4. `dmesg -n 7` / `loglevel` antes de declarar ausencias; `ftrace` antes que `pr_info`
   en paths sensibles a timing.

---

## Resumen de veredictos

- Hallazgos: 1 CONFIRMADO con matiz · 2 CONFIRMADO · 3 CONFIRMADO (y entierra a RESUMEN-§3.4)
  · 4 CONFIRMADO (y entierra a 1a/1c) · 5 CONFIRMADO en header+ID, IMPRECISO en "redundancia".
- Fase 1: **1a CANCELADA, 1c CANCELADA, 1b REDEFINIDA**. 1a' (`pr_info`) rechazada: no neutra,
  mide el camino común, `ftrace` la obsoletiza.
- Hoy sin flashear: todo §A + descarte de `modetest` (card0/master) + writeback libre
  y apto como sink. Sin commits: pendiente de ventana con el dueño.
- Experimento óptimo: **D-0 (ftrace en vivo) + D-1 (commit writeback-only supervisado)**.
  0 builds, 0 flashes, respuesta definitiva DPU-vs-DSI.
