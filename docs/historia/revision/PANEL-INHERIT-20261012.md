# PANEL-INHERIT — herencia cont_splash del panel del ABL (param `msm.uke_panel_inherit`)

**L22 · 11/12-oct-2026 · 0 escrituras en la tablet (solo SSH lectura) · 0 commits · 0 builds.**
Escrito: `build/gates/patches/l22-panel-inherit.diff` (dry-run OK, NO aplicado) + esta nota.
Árbol: `build/kernel-pokes/k52-L16-tree` · patch -p1 · según descubrimiento del dueño:
**el panel SÍ enciende (ABL vendor) y muestra splash+log; muere cuando corre nuestro stack display.**

---

## 1. Inventario: ¿hay gancho existente de "panel heredado"? (NO)

| dónde | resultado |
|---|---|
| `grep cont_splash\|splash\|handoff\|skip_init\|bootloader` en `drivers/gpu/drm/msm/` (dsi_host.c, dsi_manager.c, dsi_phy.c, dpu1/) | **0 hits**. El `dsi_display_cont_splash_handler` del vendor NO dejó nada en mainline. |
| `panel-xiaomi-o82-dualdsi.c` (nuestro port, leído completo) | sin module_param, sin skip, sin DT prop de herencia. `prepare_prev_first=true` (:740). `o82_prepare` = `o82_power_on` (3 rieles vddil8b/vsp/vsn + load 300 mA) → `o82_reset` (0/1/0/1, 10/3/3/100 ms) → `o82_send_panel_cmds` (104 cmds verbatim) → freq_sel b3/b2 → sleep-out+120 ms → display-on → `backlight_enable`. `o82_unprepare` = off-DCS 0x28/0x10/0x4f broadcast → reset assert → rieles off. |
| DT vivo (leído por SSH en `/sys/firmware/devicetree/base/.../dsi@ae94000/panel@0`) | `compatible = xiaomi,uke-o82-4202-0b`; `reset-gpios = <ph 2 GPIO_ACTIVE_LOW>` (**TLMM 2, ACTIVE_LOW**; el arreglo del pin compartido es el s254/FRAGMENTO-GPIO, ver `INFORME-GPIO-RESET.md`); supplies vddil8b/vsp/vsn + `esd-err-gpios`. Sin ninguna prop de splash/herencia. |
| `msm_drv.c` | params existentes: `dumpstate`, `modeset`, `separate_gpu_kms`, `prefer_mdp5`. Nada de herencia. |

## 2. Estado real del boot actual (k52b2, `video=DSI-1:d`) — SSH solo-lectura

- **NO corrió `o82_prepare`**: 0 migas `UKE-P82`/K47/K48 en el dmesg (solo K49 ESD a 0.5986/0.5990 s,
  val=1; 1 sola irq ESD a 0.5994 s). Con `:d` el conector queda `disabled` (card1-DSI-1:
  status=disconnected, dpms=On) y el panel nunca se habilita → **coordinador: la hipótesis
  "power_off del panel durante el registro" queda REFUTADA: no hay ninguna llamada que apague el
  panel en el camino del registro** (no hay prepare ni unprepare; los rieles no se tocan — solo `get`).
- **El reset SÍ queda asertado desde el probe** (0.59 s): `devm_gpiod_get(..., GPIOD_OUT_HIGH)` con
  DT ACTIVE_LOW = físico LOW. Que la imagen siga viéndose después dice que este assert no mata el
  cuadro (TDDI/pin2 a caracterizar — el hunk ya lo arregla: con herencia se pide OUT_LOW).
- **Sin fb0** (`/sys/class/graphics` solo `fbcon`): lo que el dueño ve NO es fbcon — es el
  **pintor de `uke-panic-fb`** (tick ~3 s, repinta la cola del log en el splash).
- Splash intacta: `memmap=0x2B00000$0xE3940000` gana sobre el `0x1A12800` anterior; `/proc/iomem`:
  `e3940000-e643ffff reserved`; reserved-mem `splash_region ... nomap` (44 MB); el pintor pinta OK.
- **La muerte de la IMAGEN (~4.09-4.10 s, tras verse el log del pintor) es el bind del DPU**:
  dmesg 4.0920 s `clk: couldn't set disp_cc_mdss_vsync_clk rate to 19200000 (-22), current 38400000`,
  4.0930/4.0931 `msm_dpu ... bound ae94000.dsi / ae96000.dsi`, 4.0967 `dpu hardware revision:0xa0010000`.
  En ese `pm_runtime_resume_and_get` → `dpu_runtime_resume()` (`dpu_kms.c:1449`) se ejecuta
  `clk_bulk_prepare_enable()` + **`dpu_vbif_init_memtypes()`** → `dpu_hw_set_mem_type()` que
  **ESCRIBE** `VBIF_OUT_AXI_AMEMTYPE(_CONF1)` sobre el pipeline del ABL andando (sospechoso nº1:
  si el memtype difiere del del ABL, se rompe el fetch AXI del framebuffer heredado → vídeo-mode
  sin stream → TDDI se apaga → negro). Sospechoso nº2: el churn/retarget de clocks disp_cc (el -22
  del vsync). P9x lo discriminó ANTES: SMMU refutada (ledger #445).

## 3. Diseño del hunk (`patches/l22-panel-inherit.diff`, 7 hunks, 4 ficheros)

Param único **`msm.uke_panel_inherit=1`** (bool, 0644) en `msm_drv.c` + helper exportado
`bool uke_panel_inherit(void)` declarado en `include/linux/uke-poke.h` (patrón uke_poke;
CONFIG_DRM_MSM=y y el panel son builtin, link directo).

1. `msm_drv.c`: param + helper + comentario de diseño. Migas: ninguna.
2. `panel-xiaomi-o82-dualdsi.c` `o82_probe`: con herencia el reset se pide **GPIOD_OUT_LOW**
   (físico HIGH = liberado) en vez de OUT_HIGH; miga `UKE-P82-INHERIT: probe: reset pedido
   liberado...` + `uke_poke("P82-inh-probe")`.
3. `o82_prepare`: **(a)** NO power_on, **(b)** NO reset, **(c)** NO init-DCS/freq_sel/sleep-out/
   display-on, sin backlight_enable → `return 0`; migas `UKE-P82-INHERIT: prepare SALTADO...` +
   `uke_poke("P82-inh-prep")`.
4. `o82_unprepare`: con herencia **no apaga** (off-DCS/reset/rieles prohibidos: un dpms-off no
   puede matar al heredado); miga `UKE-P82-INHERIT: unprepare SALTADO...`.
5. `dpu_kms.c` `dpu_runtime_resume`: tras `clk_bulk_prepare_enable` (los clocks SÍ se habilitan:
   `irq_preinstall` escribe regs MDP después y escribir MMIO con clock gateado es riesgo NoC),
   **salta `dpu_vbif_init_memtypes` y el bucle de encoders** → `return 0`; migas
   `UKE-P82-INHERIT: dpu_runtime_resume: vbif-memtype/encoders SALTADOS (scanout ABL vivo)` +
   `uke_poke("P82-inh-dpu")`.

**Lectura del experimento (bisect por pantalla)**: con el param a 1 y `:d`, si el log del pintor
SOBREVIVE a los ~4.1 s → el asesino era el vbif; si muere igual → siguiente gate = churn de clocks
del vsync (-22) en el mismo resume (solo hay que mover el gate del `clk_bulk_prepare_enable`).
**Riesgos documentados**: (i) host DSI mainline para el FUTURO modeset propio: hay que saltar/gatear
también `dsi_mgr_bridge_power_on` (msm_dsi_host_power_on), `msm_dsi_phy_enable` (reconfig de PLL
mata el bitclk andando), `msm_dsi_host_enable`→`dsi_ctrl_enable` (dsi_host.c:909-916 fuerza clock
lane HS continuo desde power_on) y el `mode_set`/DSC del DPU — fase 2, NO en este hunk;
(ii) `irq_preinstall/postinstall` escriben regs IRQ del MDP con clocks ya habilitados — se permite;
(iii) el pintor de `uke-panic-fb` ya pinta sobre el splash: con herencia la pantalla queda como
**consola de splash** todo el boot (efecto deseado).

## 4. Conteos nuevos para los gates del repack (repack-k52L22 = clon de repack-k52L21.py)

En el Image crudo (G3), respecto de L21:

| token | L21 | L22 esperado | gate sugerido |
|---|---|---|---|
| `UKE-POKE` | 113 | **113** (sin cambio: `uke_poke(tag)` no duplica la cadena; ningún pr nuevo la contiene) | `!= 113` → fail (igual) |
| `UKE-P82` | 21 (≥20) | **25** (21 + 4 pr "UKE-P82-INHERIT: …") | mantener `>= 20` |
| `UKE-P82-INHERIT` | 0 | **4 exactos** (probe/prepare/unprepare/dpu) | NUEVO `== 4` |
| `P82-inh-` | 0 | **3 exactos** (`P82-inh-probe`, `P82-inh-prep`, `P82-inh-dpu`, x1 c/u) | NUEVO `== 3` |
| `uke_panel_inherit` | 0 | **1 exacto** (nombre del param) | NUEVO `== 1` |
| K13=11, K16=1, K11=0, K19=21, "UKE-K17: dtcmR"=1, WALK=8, MAPPING=15, testigos L2/L6/L7/L8/L10/L11 x1, S0-dtcmR≥1, uke_kgsl_keep=1, volcado K18≥1 | — | **SIN CAMBIO** (verificado: ningún string nuevo colisiona con los tokens exactos ni con la lista de negativos: sin `UKE-POKE`/`WALK`/`MAPPING`/`UKE-K*`/`UKE-L1:`/`UKE-C1` en los strings añadidos) | sin cambio |
| G2 cmdline | `video=DSI-1:d` (DSID) | añadir `msm.uke_panel_inherit=1` a `CMD_REQUIRE`, **mantener** `video=DSI-1:d` | NUEVO |

## 5. Plan de build (mismos parámetros del build del 11-oct = L21)

1. `patch -p1 -d build/kernel-pokes/k52-L16-tree < build/gates/patches/l22-panel-inherit.diff`
   (dry-run ya verificado: 4 ficheros, 7 hunks, OK; NO aplicar hasta aprobación del dueño).
2. `build/gates/build-fast.sh --src k52-L16-tree --cfg build/kernel-pokes/k52L19-build/.config
   --out build/kernel-pokes/k52L22-build --tag k52L22` (defaults = L21: ccache clang, -j12,
   KBUILD_BUILD_TIMESTAMP fijo; ccache debería ir casi todo hit salvo los 4 ficheros tocados).
3. Gates de fuente del build-fast (L11-NOGOTO/L11-POLL/K43): sin cambio esperado.
4. `repack-k52L22.py` = clon de `repack-k52L21.py` con: DSID=True (cmdline con `video=DSI-1:d`),
   `CMD_REQUIRE += ["msm.uke_panel_inherit=1"]`, G3 con los conteos de §4.
5. Validación sin USB: el dueño VE la pantalla → con herencia el log del pintor tiene que seguir
   vivo pasados los ~4.1 s (antes moría ahí). Lectura remota posterior: `dmesg | grep P82-INHERIT`.
6. NO flashear sin aprobación. Módulo wifi L21 (build-mod-l21.sh) no afectado (hunk builtin).
