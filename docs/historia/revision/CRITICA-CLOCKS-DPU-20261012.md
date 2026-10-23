# CRÍTICA — teoría "los clocks del DPU matan el scanout" (post-L22, con timing real del dueño)

**L22 · 11-oct-2026 · 0 escrituras en la tablet · 0 commits · 0 builds.**
Entradas: docs/historia/revision/PANEL-INHERIT-20261012.md, l22-panel-inherit.diff (aplicado), código del árbol
`build/kernel-pokes/k52-L16-tree`, y el DATO DEL DUEÑO: **el apagón ocurre a ~0,5-1 s
(probe del panel), NO a los 4,1 s del dpu_runtime_resume.** Ese dato reordena todo.

---

## 1. Veredicto sobre la teoría original (clocks del DPU en dpu_runtime_resume)

**Mecanismo correcto, lugar y momento equivocados.** La pantalla ya está muerta cuando
corre `dpu_runtime_resume` (4,10 s). Lo que sí sobrevive de la teoría es el mecanismo
"toque de RCG": en dispcc, `disp_cc_mdss_mdp_clk_src` y `disp_cc_mdss_ahb_clk_src` usan
`clk_rcg2_shared_ops` (dispcc-sm8550.c:639 y :292), y **el primer enable de una rama cuyo
src es shared NO es no-op**: `clk_rcg2_shared_enable` (clk-rcg2.c:1423) fuerza-enable,
escribe `rcg->parked_cfg` (= 0, nunca fue set_rateada) sobre el CFG del RCG y pulsa
UPDATE — es decir, **reprograma el RCG que el ABL dejó corriendo**. El "clk_enable ya-on
es no-op" solo vale para la rama (CBCR); el RCG padre se cloberea. Eso es el germen real
de la teoría — pero ocurre en el bind (4,1 s), ya tarde.

## 2. Qué toca EXACTAMENTE `dpu_runtime_resume` con el hunk L22 (dpu_kms.c:1450-1485)

| orden | toque | ¿puede matar scanout? |
|---|---|---|
| 1 | `clk_bulk_prepare_enable` de 5 clocks (`nrt_bus`=GCC_DISP_HF_AXI, `iface`=AHB, `lut`, `core`=MDP, `vsync`) | **SÍ, dos veces**: (i) primer enable de la rama `core`/`iface` → `clk_rcg2_shared_enable` escribe parked_cfg=0 sobre los RCG MDP/AHB heredados; (ii) la rama `vsync` → `of_clk_set_defaults` ya falló a 4,092 s con **-22 → NO escribió nada** (un set_rate fallido no retargeta; el -22 es inocuo). GDSC: `dpu_runtime_resume` NO toca power domains explícitos; el genpd del DPU es MMCX (rpmhpd, ya ON); el MDSS_GDSC solo se tocaría con un runtime_resume del dispositivo padre mdss — que este árbol no dispara en boot (mdss_probe NO hace component_add). |
| 2 | [L22: return 0] — vbif/encoders saltados | — |

**BUG del hunk L22 (independiente del timing): el vbif se vuelve a escribir por OTRA vía.**
`dpu_kms_hw_init` (bind, tras el resume) llama `dpu_vbif_init_memtypes(dpu_kms)` en
**dpu_kms.c:1281 SIN gate**. La migas "vbif-memtype/encoders SALTADOS" es cierta para el
resume pero falsa globalmente: en el boot L22 los AMEMTYPE se reescribieron igual en el
hw_init a 4,1 s. (Hobby: no afecta al apagón de 0,5-1 s, pero hay que cerrarlo.)

## 3. Inventario del tramo temprano (0,28-0,60 s) — donde muere de verdad la pantalla

| t | evento | código | efecto sobre el scanout del ABL |
|---|---|---|---|
| ~0,31 s | probe de dispcc | dispcc-sm8550.c:1793+: `clk_lucid_ole_pll_configure` (PLL0/PLL1) ×2, `regmap_update_bits(DISP_CC_MISC_CMD,0x10)`, `qcom_branch_set_clk_en(XO)` | **Riesgo**: si la tabla del kernel difiere de lo que dejó el ABL, reconfigurar la PLL que alimenta el RCG MDP es un glitch del core clock. |
| ~0,31 s | `gdsc_init` del MDSS_GDSC (flags `HW_CTRL|RETAIN_FF`, gdsc.c:422) | escribe gdscr (limpia HW_CONTROL/SW_OVERRIDE) y, si la GDSC está ON (caso ABL), **`gdsc_hwctrl(sc, true)`** → modo HW-trigger | Cambio de modo de control sobre una GDSC viva. Mientras el INTF siga escaneando el voto HW se mantiene → probablemente benigno; el WARN "rcg didn't update its configuration" de disp_cc_mdss_mdp_clk_src a 0,31 s (update que no ackuea) es coherente con este remezón. |
| ~0,4-0,5 s | **probe de mdss** (`mdss_probe` → `msm_mdss_init`, y las dtsi dan `resets = <&dispcc DISP_CC_MDSS_CORE_BCR>`) | msm_mdss.c:372→:309: `reset_control_assert` + **msleep(20)** + `deassert` — **INcondicional, mainline** | **RESET DURO de todo el MDSS core (DPU + hosts DSI) mientras escanea.** Los registros vuelven a valores de reset: el INTF deja de emitir vídeo, el TDDI pierde señal y se apaga, el scanout NO se reanuda jamás (nadie reprograma nada hasta el bind de 4,1 s, que no hace modeset). Deassert≠restaurar config. |
| ~0,5 s | probe de dsi ctrl (creado por `of_platform_populate` en mdss_probe:487) | driver core aplica `assigned-clock-parents` (BYTE0/PCLK0_CLK_SRC → PLL del PHY) y `dsi_get_config` (dsi_host.c:203) hace enable de AHB | Reparent: el ABL ya usaba esa PLL → escritura del mismo índice, pulso corto → probablemente benigno. Enable de AHB → otro clobber del RCG AHB compartido (parked a XO): registros accesibles pero AHB más lento. No candidata nº1. |
| 0,5517 s | probe del panel (L22: reset pedido **liberado**) | `GPIOD_OUT_LOW` + ACTIVE_LOW → nivel físico HIGH = reset desasertado ✓ | En L22 el probe NO toca el panel (sin rieles/DCS/backlight). En k52b2 (OUT_HIGH=asertado) el negro de ~0,6 s era el panel en reset — eso enmascaraba el estado real del scanout. |
| 0,5986 s | K49: lectura ESD val=1 + 1 irq | panel probe | El TDDI ya reporta error ⇒ el link llevaba muerto decenas de ms (coherente con el BCR ~0,5 s). |

**La ventana del apagón (~0,5-1 s) es exactamente la del BCR reset de mdss_probe**, que va
justo antes del probe del panel (0,55 s) y del ESD val=1 (0,60 s).

## 4. Evaluación de las alternativas

- **(a) GDSC mdss** — Parcialmente válida como coadyuvante: no hay ciclo off/on de genpd en
  boot (el mdss parent no runtime-resume), pero `gdsc_init` SÍ reescribe gdscr y pasa a
  HW-ctrl a 0,31 s; y si el BCR para el INTF, el voto HW cae y la GDSC puede colapsar
  (con RETAIN_FF los regs se retienen, pero el BCR ya los reseteó). No es la causa nº1.
- **(b) PHY/host DSI reiniciados** — REFUTADA para el tramo temprano: `dsi_phy_driver_probe`
  (dsi_phy.c:614) solo ioremap/gets/pm_clk — **cero escrituras**; `msm_dsi_phy_enable` y
  `dsi_link_clk_enable_6g` solo corren en bridge-enable/modeset, que con `video=DSI-1:d`
  jamás ocurre. El host DSI no se reinicia en el probe (solo lectura de versión con AHB).
- **(c) Muerte antes de 4,1 s** — CONFIRMADA por el dueño. La correlación antigua
  "muerte=bind DPU" era un artefacto: el bind de 4,1 s fue simplemente la primera actividad
  display del kernel DESPUÉS de que la pantalla ya estaba negra.
- **(d) Scanout apuntando a otro buffer** — REFUTADA como causa del apagón: el dueño VE las
  3 líneas que el pintor escribe en 0xE3940000 ⇒ ese buffer ES el escaneado mientras hay
  imagen. El write invisible por /dev/mem se explica sin reubicación: **el scanout murió
  antes** (BCR), la RAM retiene los bytes pero nadie los barre.
- **(e) Reset del panel asertado desde el probe** — Válida SOLO para k52b2 (OUT_HIGH+ACTIVE_LOW
  = físico LOW desde 0,59 s; un panel en reset se pone negro y el DPU sigue barriendo en
  modo vídeo sin colgarse — no hay BTA que espere). En L22 está arreglado (OUT_LOW=liberado)
  y la pantalla muere igual ⇒ **no es el asesino actual**; fue el enmascarador anterior.

## 5. RANKING de causas (código como evidencia)

| # | causa | sitio exacto | por qué |
|---|---|---|---|
| **1** | **`msm_mdss_reset()`: assert 20 ms + deassert de DISP_CC_MDSS_CORE_BCR en el probe de mdss** | msm_mdss.c:372 (llamada) / :309-333 (función); DT palawan.dtsi:3368 | Única vía incondicional de mainline que resetea el DPU+DSI vivo, a 0,4-0,5 s (antes del panel 0,55 y del ESD 0,60); explica imagen negra + scanout muerto + /dev/mem invisible + por qué L22 (gate a 4,1 s) no hizo nada |
| 2 | Primer enable de ramas con RCG compartido: `clk_rcg2_shared_enable` escribe parked_cfg=0 sobre los RCG MDP/AHB heredados | clk-rcg2.c:1423-1446 vía dpu_runtime_resume:1461 (dpu_kms.c) y dsi_get_config (dsi_host.c:220) | La "teoría clocks" correcta en mecanismo, tardía (4,1 s): sería el asesino #1 si se gatea el BCR y no esto. El -22 del vsync NO escribe (inocuo); el WARN de 0,31 s sí delata escritura fallida de update |
| 3 | `dpu_vbif_init_memtypes` SIN gate en `dpu_kms_hw_init` (dpu_kms.c:1281) — agujero del hunk L22 | dpu_kms.c:1281 | Los AMEMTYPE se reescriben igual a 4,1 s pese al gate del resume; bug a cerrar en L22b |
| 4 | GDSC: cambio de modo + `gdsc_hwctrl(true)` en dispcc probe; colapso posible si el INTF se para (sinergia con #1) | gdsc.c:446,476-481; dispcc-sm8550.c:1639 | Con INTF escaneando el voto HW se sostiene → probablemente benigno si se gatea #1 |
| 5 | Reparent BYTE0/PCLK0_CLK_SRC en el probe del dsi ctrl (assigned-clock-parents) | dsi_host DT (palawan.dtsi:3491+) | Misma PLL que el ABL → escritura de igual valor; solo relevante si L22b-1 no basta |
| 6 | Reconfig de PLL0/PLL1 en dispcc probe | dispcc-sm8550.c:1806-1807 | Solo si la tabla difiere del estado ABL; defensivo |
| — | vsync -22 (4,092 s) | of_clk_set_defaults | Falló ⇒ no escribió ⇒ inocuo (quedó a 38,4 MHz del ABL) |
| — | SMMU | ledger #445 | Ya refutada (P9x) |

## 6. Diseño del gate L22b (funciones y condiciones, sin diff)

1. **L22b-1 (el gate nº1)** — `msm_mdss.c`, `msm_mdss_init()`: envolver la llamada
   `msm_mdss_reset(&pdev->dev)` con `if (!uke_panel_inherit()) {...}` + migas
   `UKE-P82-INHERIT: mdss-reset BCR SALTADO`. (include uke-poke.h; mismo patrón que L22.)
2. **L22b-2** — `dpu_kms.c`, `dpu_kms_hw_init()`: gate en la línea 1281
   (`if (!uke_panel_inherit()) dpu_vbif_init_memtypes(dpu_kms);`) — cierra el agujero del L22.
3. **L22b-3** — `dpu_kms.c`, `dpu_runtime_resume()`: con herencia, saltar TAMBIÉN
   `clk_bulk_prepare_enable` (devolver 0 antes de él). Los clocks siguen físicamente ON por
   el ABL, así que `irq_preinstall` puede escribir MMIO; el coste es quedar con
   prepare_count=0 (documentar: un futuro clk_disable WARNearía). Alternativa no tomada:
   dejar el prepare_enable y aceptar el clobber del RCG (mataría el splash en el bind).
4. **L22b-4 (defensivo)** — `dispcc-sm8550.c`, `disp_cc_sm8550_probe()`: para
   palawan + herencia, saltar los dos `clk_lucid_ole_pll_configure` (la PLL ya está
   configurada y en uso; reescribir L/M/N es riesgo de glitch a 0,31 s). Dejar
   MISC_CMD y XO_CLK (benignos).
5. **NO se toca**: gdsc_init/GDSC (gate #4 genérico, invasivo; se prueba tras L22b-1: si el
   INTF sigue escaneando, el voto HW sostiene la GDSC), assigned-clock-parents del DSI (DT;
   solo si L22b-1 no basta), msm_mdss_enable (no corre en boot en este árbol).

**Criterio de éxito del experimento L22b**: el log del pintor sobrevive a 0,6 s y a 4,1 s.
**Lectura si falla**: (i) sigue muriendo ~0,5 s → siguiente sospechoso = reparent
BYTE0/PCLK0 (quitar assigned-clock-parents del dtsi del repack) o el propio K49; (ii) muere
ahora a 4,1 s → quedó algo en el bind (mdss parent resume/irq_preinstall) → iterar con migas.

## 7. ¿Discrimina el test del dueño (timing)?

El dato "~0,5-1 s" YA discriminó: descarta dpu_runtime_resume/vbif/encoders (4,1 s) como
asesino principal y desplaza la causa a la ventana dispcc/mdss/dsi probe. Para afinar DENTRO
de esa ventana sin hardware nuevo: un boot L22b con los gates 1-4 resuelve por dicotomía —
si vive, era el trío BCR/vbif/RCG-clobber; el siguiente flash que falle dirá en qué migas
de dmesg estaba (0,31 dispcc vs 0,5 mdss/dsi). El ojo humano (0,3 vs 0,5 s) NO discrimina
más; el dmesg con las migas nuevas sí.
