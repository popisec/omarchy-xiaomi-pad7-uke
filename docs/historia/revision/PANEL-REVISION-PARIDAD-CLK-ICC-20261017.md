# PANEL-REVISION-PARIDAD-CLK-ICC — vendor (Android, ftrace de wake) vs port (DTBO s288 + k52)

> 17-oct-2026. Solo lectura. Sin adb/fastboot/ssh. Sin commits.
> **Qué es "el DT del port"**: NO es `xiaomi-uke.dts` (ahí la pantalla está APAGADA: comentario
> `xiaomi-uke.dts:517-542`, "TODO: &mdss { status = okay }"). El DT vivo es el **DT vendor stock +
> overlay s288** (`charge/mkdtbo-s288.py`, `build/bootimg/s288-boot-dtbo-...img`), cuyos nodos
> display mainline son `mdss_ml` (`display-subsystem@ae00000`), `mdss_dsi{0,1}_ml`, `mdss_dsi{0,1}_phy_ml`,
> `mdss_mdp_ml`, `uke_panel_vsp/vsn`, `uke_pmx_sde`. Lo he fusionado en local para leerlo:
> `python3 -I build/bootimg/dtbo-extract.py <s288.img> s288.dtbo; fdtoverlay -i ~/gpu-work/ramaa/s21/dtbo-gpu/base-dtb.img -o m288.dtb s288.dtbo; dtc -I dtb -O dts m288.dtb`
> (citado abajo como **m288:LINEA**, fichero temporal regenerable; no está en el repo).
> Vendor = `build/android/vendor-harvest-20261017b/` (**V:fichero:línea**).
> Kernel = `build/kernel-pokes/k52-L16-tree` (**K:ruta:línea**).
> No repito lo ya concluido: B2 (host DSI), B3 (DPU/ICC), B4 (PHY/link), INV75, CRITICA-CLOCKS-DPU,
> HALLAZGO-OPP-BYTE-CLK, SECUENCIA-ENCENDIDO-ANDROID-O82; los cito.

## 0. Veredicto corto

**La paridad de relojes del enlace DSI y de los rieles propios del DSI/PHY es completa; no hay
ninguna diferencia en este perímetro que por sí sola explique el negro.** Lo que difiere es
(a) el mundo de votos de potencia (MMCX/MXA, rscc, ICC fuera de LLCC→EBI), que el port no hace y el
vendor sí, y cuyo efecto NO está medido; (b) una refutación importante: **B4 N-B4-5/F2 (forzar
esc = byte/8) es falso**, el vendor mide esc = 19,2 MHz; (c) un par de cosas inocuas pero que
conviene tener anotadas (pinctrl nunca aplicado, ESD edge vs level, tabla MDP palawan).

## 1. Relojes

### 1.1 Vendor (medido, awake, `clk-summary.txt`)

| Reloj | Vendor | V: |
|---|---|---|
| `disp_cc_pll0` | 1 542 MHz (en wake sube a 1 800 MHz y vuelve) | clk-summary:652; trace-offon:3242,4550 |
| `disp_cc_mdss_mdp_clk_src` / `mdp_clk` / `mdp_lut_clk` | **514 MHz** estable (600 MHz solo ~200 ms tras el wake, luego 514) | clk-summary:653-659; trace-offon:3244-3248 (600), 4551-4560 (514) |
| `disp_cc_mdss_vsync_clk_src` / `vsync_clk` / `rscc_vsync_clk` | 19,2 MHz | clk-summary:661-665 |
| `dsi0_phy_pll_out_byteclk` → `byte{0,1}_clk_src` / `byte{0,1}_clk` | **148 648 750** | clk-summary:21-35 |
| `byte{0,1}_div_clk_src` / `byte{0,1}_intf_clk` | 74 324 375 (byte/2) | clk-summary:25-33 |
| `dsi0_phy_pll_out_dsiclk` | 237 838 000 | clk-summary:11 |
| `pclk{0,1}_clk_src` / `pclk{0,1}_clk` | **158 558 666** | clk-summary:13-19 |
| `esc{0,1}_clk_src` / `esc{0,1}_clk` | **19 200 000** | clk-summary:667-671; dsi-ctrl0-state.txt (`ESC_CLK = 19200000`) |
| `dsi1_phy_pll_out_*` | sin uso (500 000 009 / 312 500 006, enable 0); ctrl1 cuelga del PLL de PHY0 | clk-summary:9-10,13,23 |
| `disp_cc_mdss_non_gdsc_ahb_clk`, `rscc_ahb_clk`, `rscc_vsync_clk` | ON (los habilita `af20000.sde_rscc`) | clk-summary:728; trace-offon:3183-3185 |

Orden de habilitación en el wake (trace-offon, `crtc_commit`, t en s): MMCX `pm_v6c_s1_mmcx_sup_level`
→ `pm_v8_s6_level` (nivel 56→384) → `vsync_clk_src`/`rscc_vsync` → `ahb_clk_src` →
`non_gdsc_ahb`/`rscc_ahb` → `gcc_disp_hf_axi` → `disp_cc_ahb_clk` → `mdp_clk_src/mdp_clk/vsync/lut`
(.2851-.2851, líneas 3182-3193) → ICC votos (.2843-.2857) → `pll0=1800` + mdp 600 (.2861) → **L8 (vddio)** (.2884)
→ **vsp** (.2909) → **vsn** (.2934) → L4 (.2959) → L2 (.2961) → **esc0/esc1** (.3012, línea 3414) →
**byte0/pclk0/byte0_intf/byte1/pclk1/byte1_intf** (.3016) → **reset 335** (.3017). Ni `clk_set_rate`
de byte/pclk/esc en el wake: las tasas se fijaron una vez (en el primer enable) y se retienen
(trace-offon: los 48 `clk_set_rate` son solo disp_cc_pll0/mdp y gpu_cc).

### 1.2 Port

| Item | Port (m288) | Paridad |
|---|---|---|
| OPP del host DSI | `mdss_dsi_opp_ml` 358/300/187.5/**148.648750** MHz (m288:~917-937; fragmento `opp-148648750` verificado además por G5 de `charge/mkdtbo-s288.py:171-178`) | IGUAL (cierra HALLAZGO-OPP-BYTE-CLK; B4 §3.4-5) |
| byte/pclk reales | L67 vivo: byte0 118,919 M, pclk 158,558 M (=vendor, Δ266 Hz); desde L70 byte = ×30/32 = 148 648 500 → ceil OPP 148 648 750; VCO 1 189 190 000 = `0x46E19970` bit-exacto | IGUAL (B4 §3 pto 4-5; PHY-LANE-RATE:33-37). **Sin `clk_summary` vivo del port con L70+ en este perímetro: la tasa efectiva final NO VERIFICADA en HW por mí** |
| byte_intf (÷2) | `byte_intf` = `DISP_CC_MDSS_BYTE{0,1}_INTF_CLK` (m288:858,925) | Esperable igual (74,32 M); NO VERIFICADO vivo |
| padres PLL | dsi0: `assigned-clocks = BYTE0_CLK_SRC, PCLK0_CLK_SRC` parent = `<&phy0 0>,<&phy0 1>`; dsi1: `BYTE1_CLK_SRC, PCLK1_CLK_SRC` **también parent phy0** (m288:~862-863, ~927-928) | IGUAL (ctrl1 cuelga del PLL de PHY0 como en vendor, clk-summary:13-35) |
| MDP rate | `mdp_opp_ml` 200/325/375/**514** (m288:~1028-1050); `dpu_kms_init` hace `opp_find_freq_floor(ULONG_MAX)` = 514 y `dev_pm_opp_set_rate` (PIPELINE-PANEL/L48-PREP.md:69) | IGUAL en régimen (514). El vendor sube a 600 un instante: **inocua** (no hay OPP 600 en el port; la tabla palawan del dispcc sí lo tiene: K:drivers/clk/qcom/dispcc-sm8550.c:600-611) |
| tabla `ftbl_..._mdp_clk_src_palawan` | 85,7/100/155/200/**342/402**/514/600, todo ÷3 sobre PLL0 | **DIFERENCIA menor**: los OPP DT 325 y 375 no existen en la tabla del dispcc (el RCG redondea a 342/402 con determine_rate); el vendor usa 200/325/375/514 en su propia tabla. **Inocua** a 514 |
| vsync | `assigned-clock-rates = 19.2 MHz` sobre `DISP_CC_MDSS_VSYNC_CLK` (idx 73 = rama, m288:~1018-1019) en vez de `VSYNC_CLK_SRC` (74) | el `-22` ya diagnosticado (CRITICA-CLOCKS-DPU §2 fila 1(ii)): no escribe, queda 19,2 MHz del ABL. **Inocua** |
| esc | nadie hace `clk_set_rate` de esc; queda en padre TCXO 19,2 MHz (B4 §3 pto 7) | **IGUAL al vendor (19,2 MHz medido)** — ver D-01 |
| PLL0 / configuración dispcc | `lucid_ole_vco[0].max_freq=2100 MHz`; `clk_lucid_ole_pll_configure` salvo `uke_skip_pll` (K:dispcc-sm8550.c:1804-1830) | cubierto por CRITICA-CLOCKS-DPU §3/§6 (L22b-4) |
| clocks de rscc | **ninguno** (`sde_rscc` sin driver; `rscc_ahb`, `rscc_vsync`, `non_gdsc_ahb` no los habilita nadie) | D-05 |
| orden clk vs rieles | `prepare_prev_first=true` (K:panel-xiaomi-o82-dualdsi.c:959): DSI/PHY (L4, L2, clocks link) **antes** de L8/vsp/vsn y reset; vendor: rieles panel → vdda DSI/PHY → clocks → reset | **inocua**: L2/L4 los deja ON el ABL (`regulator_ignore_unused`), y con `MIPI_DSI_CLOCK_NON_CONTINUOUS` las lanes siguen en LP11 (flags: K:panel-xiaomi-o82-dualdsi.c:~805-811; SECUENCIA-ENCENDIDO §A pasos 3-14) |

## 2. Interconnect

### 2.1 Votos vendor (trace-offon `icc_set_bw`, solo display; unidades kB/s)

| Path (dev) | avg | peak | t |
|---|---|---|---|
| `qnm_mdp-qns_llcc` (mdss_mdp, "data-bus0" = mmss_noc MDP → gem/LLCC) | 0 | **2 500 000** | trace-offon:3161-3165 (.2843) |
| `llcc_mc-ebi` (mdss_mdp, "ebi-bus") | 0 | **800 000** | idem (.2844) |
| `chm_apps-qhs_display_cfg` (mdss_mdp, "reg-bus") | 0 | 14 000 → 310 000 | .2847, .2853; tras 1.º frame vuelve a 14 000 (:4226) |
| `qnm_mdp_disp-ebi_disp` (`af20000.sde_rscc`, DRV display) | 26 500 000 → 2 884 683 (→ 8 654 049 → ...) | 10 351 562 → 1 126 829 (→ 3 380 488 ...) | .2857, luego .4879, 32212.02... |

DT vendor mdp: `interconnect-names = "qcom,sde-data-bus0","qcom,sde-ebi-bus","qcom,sde-reg-bus"`,
`interconnects = <0x1bf 0x15 0x1a2 0x22b>,<0x188 3 0x188 0x200>,<0x1a2 2 0x3cc 0x20c>`
(m288 nodo `qcom,mdss_mdp@ae00000`, líneas ~21985-21986) y `qcom,sde-ib-bw-vote = <2500000 0 800000>`,
`reg-bus vectors-KBps = 0/14000/140000/310000`.

### 2.2 Port

* `mdss_ml`: **una sola** ruta, `interconnect-names = "mdp0-mem"`, `interconnects = <0x188 3 0x188 0x200>` =
  mc_virt MASTER_LLCC→SLAVE_EBI1 (m288:~829-832). El DPU (`mdss_mdp_ml`) **no declara interconnects**: `msm_icc_get`
  cae al padre (K:drivers/gpu/drm/msm/msm_io_utils.c:143-163) → el DPU vota sobre esa única ruta
  (`dpu_core_perf.c:225-250`, `num_paths=1`).
* Votos del port: `msm_mdss_enable` pone `MIN_IB_BW = 400 MB` de pico (`msm_mdss.c:26,245`) y el DPU
  vota por CRTC (B3 §4: 4,25 GB/s fullscreen). `mdp1-mem` y **`cpu-cfg` ausentes** → `reg_bus_path` = NULL
  (K:msm_mdss.c:57-72); `icc_set_bw(NULL)` es no-op (`msm_mdss.c:247`).
* **"L66 icc" NO es del display**: el parche L66 es el revert de L19 para el ADSP
  (`gates/repack-k52L66.py:4-8`) y el fragmento `@2404` de s288 repunta solo
  `/soc/remoteproc-adsp@03000000` a `<0x188 3 0x188 512>` (`charge/mkdtbo-s288.py:92-100`).

| Path vendor | ¿Port? |
|---|---|
| `llcc_mc-ebi` ("ebi-bus") | **Sí, es exactamente `mdp0-mem`** (mismo `<0x188 3 0x188 0x200>`). Pico: vendor 0,8 GB/s en wake; port 0,4 GB/s mínimo y 4,25 GB/s con commit. Sobra. |
| `qnm_mdp-qns_llcc` (mmss_noc MDP→LLCC, pico 2,5 GB/s) | **FALTA** (B3 D5 / F2: palawan.c define `palawan_mmss_noc` MASTER_MDP; B3 lo dejó "ortogonal, segunda línea") |
| `chm_apps-qhs_display_cfg` (reg-bus, 14→310 MB/s) | **FALTA** (`cpu-cfg`) |
| `qnm_mdp_disp-ebi_disp` (rscc, 26,5→2,9 GB/s) | **FALTA** (no hay driver rscc; es el DRV display del RSC) |
| `mdp1-mem` | no existe en el vendor tampoco (solo 3 rutas) |

Nota de unidades: B3 §4 compara 4,25 GB/s con la "necesidad real 3,28 GB/s". El vendor, con panel 120 Hz
en pantalla de reposo, vota solo 2,2-2,9 GB/s avg y 0,85-1,1 GB/s pico (trace-offon :~4879, 32213.35)
y 26,5 GB/s avg (!) en el primer instante del wake por la ruta rscc. Es el único voto "grande" del vendor y
el port no tiene equivalente.

## 3. Reguladores y GDSC

| Suministro | Vendor | Port (m288) | Paridad |
|---|---|---|---|
| vsp / vsn | `display_panel_vsp/vsn`, **5800 mV** fijo, carga 300 mA, GPIO 407/408 (= tlmm 74/75) enable (V:regulator-summary:8-11; trace-offon: `gpio_value: 407 set 1`, `408 set 1`) | `uke_panel_vsp/vsn` `regulator-fixed`, min=max=`0x588040`=5 800 000 µV, gpio tlmm 0x4a/0x4b, `ramp-delay=0xe9`=233 µs, `regulator-boot-on` (m288:~1086-1110). Driver pide `set_load(300 mA)` (K:panel...:51,329; inofensivo en regulator-fixed) | IGUAL (tensión, GPIO, rampa 0,4 ms vendor vs 0,23 ms port) |
| vddio / vddil8b | `pmxr2230_l8` **1900 mV** (V:regulator-summary:194-195, load 300 mA) | `vddil8b-supply=<0x14f>` = L8B; DT min/max=0/0 + `qcom,init-voltage=0x1cfde0`=1,9 V que el driver vendor del port aplica (K:drivers/regulator/qcom-rpmh-regulator.c:2079-2093) | IGUAL en tensión efectiva (1,9 V por init-voltage); load 300 mA vía `regulator_set_load` |
| vdda ctrl 1p2 (ctrl0/1) | `pmxr2230_l4` 1200 mV, **16 mA** (V:regulator-summary:172-184) | `vdda-supply=<0x14e>`=L4 (m288:~851,911); load `sm8650_dsi_regulators` 16 600 µA (K:dsi_cfg.c:193-195) = `0x40d8` vendor | IGUAL |
| vdda PHY 0p9 (phy0/1) | `pmxr2230_l2` 880-950 mV, **98 mA** (V:regulator-summary:158-166) | `vdds-supply=<0x14d>`=L2 (m288:~840,903); load `dsi_phy_7nm_98000uA_regulators` (K:dsi_phy_7nm.c:1309-1311, 8650 cfg 1543-1546) = `0x17ed0` | IGUAL |
| vci | `pmxr2230_l19` (`vci-supply`), rango 2,6-3,544 V | `vci-supply=<0x150>` + `regulator_set_voltage(2,6-3,544 V)`+enable (K:panel...:306-322) | IGUAL (L27) |
| MMCX (`pm_v6c_s1_mmcx_sup_level` → `pm_v8_s6_level`) | en wake se vota 56→384 ANTES de los relojes (trace-offon:3170-3179,3240-3241), `af00000.clock-controller-vdd_mm` y `ae00000.mdss_mdp-mmcx` son consumidores (regulator-summary:35-37) | **sin voto**: `mdss_mdp_ml` y `mdss_dsi_opp_ml`/`mdp_opp_ml` no tienen `power-domains`/`required-opps` (m288:~1015-1050); `dispcc` solo conserva `vdd_mm-supply` que el driver mainline no usa (m288:~14367). Ya anotado: R3-vendor-diff.md:316, ANDROID-POWER-DPU:228-235 | **DIFERENCIA, D-04** |
| MXA (`pm_v8_s8_level` 256-416 → 384-416) | votado en wake (trace-offon:3178,3188,3241) | sin voto (idem) | **DIFERENCIA, D-04** |
| `disp_cc_mdss_core_gdsc` (mdss GDSC) | **fast (HW-ctrl)**, nunca se cicla en el wake (cero `gdsc_time`/`regulator_enable` de disp_cc; solo UFS/GPU, trace-offon) (V:regulator-summary:99-101) | `mdss_gdsc` flags `POLL_CFG_GDSCR\|HW_CTRL\|RETAIN_FF_ENABLE` (K:dispcc-sm8550.c:1644-1651); `mdss_ml power-domains=<&dispcc 0>` (m288:~826) | IGUAL en modo; el vendor tiene `sde_rscc` como único consumidor, el port `mdss`. Ver CRITICA-CLOCKS-DPU §5 fila 4 |
| gdsc PHY (`mdss_dsi_phyN-gdsc`) | consumidores de `regulator-dummy` (V:regulator-summary:4-5) = no existen | — | IGUAL (nada) |
| `pm_genpd_summary` vendor | **NO VERIFICADO** (`pm-gdsc.txt` falló: ruta inaccesible) | — | — |

## 4. GPIO y pinctrl

| Línea | Vendor | Port | Paridad |
|---|---|---|---|
| reset | tlmm gpio2 (= 335), `out high func0 8 mA no pull` en awake (V:gpio.txt:83); secuencia física 0 (10,1 ms) → 1 (3,2) → 0 (3,2) → 1 (queda) (trace-offon:3436-3447; panel-on-timeline:12-17) | `reset-gpios = <&tlmm 2 ACTIVE_LOW>` (m288:~959), driver: assert 10 ms / release 3 / assert 3 / release (K:panel...:273-291) | IGUAL en forma. **Espera post-reset: vendor 15 ms hasta el 1.er DCS, port 100 ms** (r7) — ya recogido en B1 (L73 lo baja a 15) |
| pinctrl reset | `panel_active`: gpio2 bias-disable 8 mA; `panel_suspend`: pull-down 2 mA (V:pinctrl-handles:1461-1510) | `uke-dsi-reset-active/suspend` (m288:~8695-8710) | mismos valores |
| TE | gpio **77** `mdp_vsync_p`, pull-down 2 mA (config `0x103/0x209`), en ambos estados; `qcom,platform-te-gpio=0x4d` (V:pinctrl-handles:1481-1490,1511-1520; gpio.txt:149 `func1`; m288:1253,1273) | **ninguno** (panel sin TE, video mode) | Ausencia. **Inocua** (modo vídeo, sin TE en el path; el vendor muxa el pin pero el puerto no lo necesita) |
| ESD err | tlmm 168/169, flags `0x2004` = nivel alto + oneshot (V: m288:22202-22203); IRQ vistos como **`msmgpio 168/169 Level`** (V:interrupts.txt:322-323); en reposo `in low func0 2 mA pull down` (V:gpio.txt:240-241) | `esd-err-gpios = <&tlmm 168 0>, <&tlmm 169 0>` (m288:~958); IRQ `IRQF_TRIGGER_RISING\|FALLING\|ONESHOT` (K:panel...:906-911, `Edge` en el port) | **DIFERENCIA D-06** (edge vs level). Inocua demostrada por ESD-MASK-TEST (§4: un par de edges, no tormenta) |
| pinctrl del panel port | — | `pinctrl-names = "sleep"` (overlay `fragment@2103`, s288.dts:15227-15233) con `pinctrl-0`=reset_active+esd_active, `pinctrl-1`=reset_suspend+esd_active | **DIFERENCIA D-07**: no hay estado `default` → el core pinctrl **no aplica nunca** pinctrl-0 al probe; el driver no hace `pinctrl_select_state` (único `pinctrl` del .c es un comentario que dice lo contrario, K:panel...:891). El pin queda como lo dejó el ABL (reset 8 mA sin pull — idéntico al vendor — y ESD pull-down — idéntico al vendor, aunque el DT diga `bias-pull-up` en `uke-esd-active`, m288:~8689). **Inocua hoy**, pero el comentario del driver y el DT mienten |
| vsp/vsn GPIO | gpio 74/75 `out high func0 16 mA pull up` (V:gpio.txt:146-147) | gpio tlmm 74/75 en `regulator-fixed` con boot-on | IGUAL (el ABL los deja a 1) |

## 5. Interrupciones

| IRQ | Vendor | Port | Paridad |
|---|---|---|---|
| mdss padre | GIC **115** = SPI 83 (`msm_drm`) (V:interrupts.txt:356) | `mdss_ml interrupts = <GIC_SPI 0x53 LEVEL_HIGH>` = SPI 83 (m288:~835) | IGUAL |
| dsi ctrl 0 / 1 | `sde 4 / sde 5 Edge dsi_ctrl` (V:interrupts.txt:357-358) | `mdss_dsi0_ml interrupts-extended=<&mdss 4>`, dsi1 `<&mdss 5>` (m288:~866,935) | IGUAL |
| MDP (INTF/ctl) | colgado del mismo `sde` (hwirq 0) | `mdss_mdp_ml interrupts-extended=<&mdss 0>` (m288:~1020) | IGUAL |
| ESD 168/169 | level | edge (arriba) | D-06 |
| RSC display | GIC 161 `disp_rsc-drv-0` (482/544/282 disparos) (V:interrupts.txt:26) | ninguno (sin driver rscc) | D-05 |
| DP | `sde 12 dp_display_isr` | — | irrelevante |
| TE / vsync GPIO | — (sin IRQ de TE; `mdp_vsync_p` solo muxado) | — | IGUAL |

## 6. Lista de diferencias con gravedad

Leyenda: **NEGRO?** = candidata a causa; **INOCUA** = demostrada o razonada sin efecto; **DESCONOCIDA** = hay diferencia, no hay medida que la absuelva ni la condene.

| ID | Diferencia | Gravedad | Evidencia |
|---|---|---|---|
| **D-01** | **B4 N-B4-5 / F2 ("vendor esc = byte/8 = 18,58 MHz", forzar `esc` a byte/8) es FALSO.** El vendor tiene esc0/esc1 = **19,2 MHz** (TCXO) | **Corrección de informe previo; F2 NO debe aplicarse.** El port ya está en paridad (19,2 MHz TCXO) | V:clk-summary:667-671; V:dsi-ctrl0-state.txt (`ESC_CLK = 19200000`); ya estaba en `evidencia/android-full/.../dsi-ctrl-0/state_info:7` e INFORME-MODO-OPP-DSC:334. Contradice B4:112-116, 218-226, 277 |
| D-02 | Reloj MDP 600 MHz transitorio en el wake (PLL0 1,8 GHz) y OPP/tabla 325/375 vs 342/402 | INOCUA | trace-offon:3242-3248; K:dispcc-sm8550.c:600-611 vs m288 `mdp_opp_ml` |
| D-03 | Faltan en el port las rutas ICC `qnm_mdp-qns_llcc` (mmss_noc, 2,5 GB/s pico), `chm_apps-qhs_display_cfg` (14/310 MB/s) y `qnm_mdp_disp-ebi_disp` (rscc, hasta 26,5 GB/s avg en el wake). Solo existe `llcc_mc-ebi` | DESCONOCIDA (probable inocua en estado estacionario: B3 §3 lo descarta como causa del underrun con L67=0 underruns; **el voto grande del vendor es el de rscc y no tiene análogo**) | V:trace-offon icc_set_bw display; m288:~829-832; B3 §4 D5/F2 |
| D-04 | **Sin votos de MMCX (`pm_v8_s6_level` 384) ni MXA (`pm_v8_s8_level` 384-416)** antes de subir MDP/DSI. El vendor los sube explícitamente en cada wake antes de habilitar relojes. El port no tiene `power-domains`/`required-opps` en mdp/dsi/dispcc | DESCONOCIDA (la más sustancial de este informe). Con splash heredado el nivel lo fija el ABL/firmware (no medido) y `MDP=514 MHz` + PLL0 1,5 GHz necesitan nivel ≥ nom; si el nivel real fuera menor, el DPU/DSI correrían sub-volt. **NO VERIFICADO el nivel MMCX del port**; verificable con `cat /sys/kernel/debug/regulator/regulator_summary` y `cmd-db`/AOP en el port | trace-offon:3170-3179,3188,3240-3241; V:regulator-summary:35-37,28-34; R3-vendor-diff:316 |
| D-05 | `sde_rscc` (af20000) sin driver: no se habilitan `disp_cc_mdss_rscc_ahb/vsync` ni `non_gdsc_ahb`, no hay IRQ 161, no hay voto ICC rscc, el mdss GDSC pierde su único consumidor vendor | DESCONOCIDA/baja (video mode, el vendor lo usa para idle-PC/vsync-timestamp; no hay evidencia de que el scanout simple lo requiera) | clk-summary:662,728; interrupts.txt:26; trace-offon:3183-3185, 3214-3226 |
| D-06 | ESD IRQ: vendor nivel-alto (0x2004), port edge ambos sentidos + `bias-pull-up` solo declarado | INOCUA (ya probada: ESD-MASK-TEST §4; ocurre un par de edges y el SoC sigue vivo) | m288:22202-22203; interrupts.txt:322-323; K:panel...:906-911 |
| D-07 | `pinctrl-names="sleep"`: ningún estado pinctrl del panel se aplica nunca (reset/ESD heredan ABL) | INOCUA hoy (valores del ABL = vendor), **pero** el comentario K:panel...:889-891 es falso y s266 `uke-esd-active` no actúa; si algún día el ABL no deja gpio2 así, cambia | s288.dts:15227-15233; K:panel...:891 |
| D-08 | Sin TE (gpio77 `mdp_vsync_p`) | INOCUA (video mode) | V:pinctrl-handles:1481-1520; V:gpio.txt:149 |
| D-09 | Orden: link clocks/PHY/L2/L4 antes de L8/vsp/vsn+reset (port) vs rieles→vdda→clocks→reset (vendor) | INOCUA (L2/L4 ya ON; lanes LP11) | trace-offon:3352-3447; K:panel...:959 |
| D-10 | Post-reset: 100 ms (port, L70-L75) vs 15 ms vendor hasta el 1.er DCS | DESCONOCIDA/baja (ya conocida y propuesta a 15 ms en B1/L73) | panel-on-timeline:17-19; K:panel...:291 |
| D-11 | Backlight: vendor programa **dos** `ktz8866@11` (i2c-7 → a80000 e i2c-2 → 890000: 08=3f, 04=00, 05=00 tras la 1.ª trama; luego 08=7f, 04=06, 05=23). El port solo enlaza `backlight=<&ktz_bl_0>` (a80000); s289 añade el 2.º label pero el driver no lo usa | **NEGRO?** solo en sentido "pantalla encendida pero sin luz": si cada KTZ ilumina la mitad, medio panel o nada oscuro. NO VERIFICADO el reparto de LED entre chips. Ya cubierto por KTZ-DUAL-S289-20261017 y README del harvest | trace-offon:4303-4345, 4988-5000; m288 (`ktz_bl_0`) |

Sin diferencias en: tensión/GPIO/rampa de vsp-vsn, L8 1,9 V, vci, vdda ctrl/PHY (tensiones y cargas),
tasas byte/pclk/esc, OPP 148,648750, padres de los PLL, IRQs mdss/dsi/mdp, modo de la GDSC mdss,
secuencia física de reset.

## 7. Qué mirar en el port (solo lectura, ninguna acción de este informe)

1. `regulator_summary` + nivel real de `pm_v8_s6_level`/MMCX con la pantalla viva (cierra D-04).
2. `clk_summary` real con L70+/L75: confirmar `byte0_clk 148648750`, `pclk0 158558666`, `esc0 19200000`,
   `mdp 514000000`, `vsync 19200000` (todo lo de §1.2 que dice "NO VERIFICADO vivo").
3. `interconnect_summary` del path `mdp0-mem`.
4. Descartar F2 de B4.

## Referencias internas
`docs/historia/revision/PANEL-REVISION-B3-DPU-INTF.md` §3-§5 · `docs/historia/revision/PANEL-REVISION-B4-PHY-LINK.md` §3 · `docs/historia/revision/PANEL-REVISION-INV75-PHY-20261017.md`
· `docs/historia/revision/CRITICA-CLOCKS-DPU-20261012.md` · `HALLAZGO-OPP-BYTE-CLK-20261013.md` · `docs/historia/revision/ESD-MASK-TEST-20261012.md`
· `SECUENCIA-ENCENDIDO-ANDROID-O82-20261012.md` · `R3-vendor-diff.md:316` · `KTZ-DUAL-S289-20261017.md`.
