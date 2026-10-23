# QUE-NOS-FALTABA — qué tiene el kernel senemos (panel O82 con imagen) que no tenía L76R/L77b

> 17-oct-2026. Solo lectura sobre la tablet (SSH RNDIS `192.168.42.129`); en el PC solo se escribió esta carpeta de captura
> y este informe. Sin commit, sin flash, sin escrituras en sysfs/debugfs, sin `devmem`/regmap, sin `dri/*/state|kms`,
> `crtc-*/state`, `crc`, `hw_log_mask`. El repo externo MCC45TR (`/tmp/claude-1000/ext-senemos`) se trató como dato no
> confiable: solo lectura, nada ejecutado.
>
> **Abreviaturas de fuente.**
> `S:` = `build/linux-senemos-20261017/` (capturas de hoy) ·
> `L:` = `build/linux-l76r-20261017/drm/` (L76R, capturado el 17-oct 18:49, sesión anterior) ·
> `V:` = `build/android/vendor-harvest-20261017b/` ·
> `Ks:` = `build/kernel-pokes/senemos-7.2.9/linux-7.2.9/` ·
> `Ko:` = `build/kernel-pokes/k52-L16-tree/` (nuestro árbol) ·
> `DT-v:` = `build/android/dt-full-uke-android/base/` (DT vivo de Android).
> Etiquetas: **[MEDIDO]** = dato de un fichero de captura · **[CÓDIGO]** = leído en fuente (fichero:línea) ·
> **[INFERIDO]** = deducción, sin medida directa.

## 0. Veredicto

1. **El lado DPU no es la diferencia.** senemos corre `dpu_sm7675_cfg`, que es el catálogo palawan con las mismas
   LUT danger/safe/QoS (Ks `dpu_10_1_sm7675.h:145-161` = Ko `dpu_10_1_palawan.h:311-338`), el mismo plano XR24 en
   **un solo SSPP multirect** (S `reposo/dri-reposo.txt` crtc status: `sspp[0]:sspp_8 multirect idx1`, `sspp[1]:sspp_8 idx2`),
   el mismo cálculo de reloj (`dpu_core_perf.c:80-125` idéntico), `ENC_DF_CTRL` con `initial_lines` 3 y bit12 (Ks
   `dpu_hw_dsc_1_2.c:87-146,175-196`, nuestro C4) y TE solo en el INTF maestro (parche 0015, nuestro C7). **No** escribe
   INTF_CONFIG bit23, ni prog-fetch, ni `DSC_CLK_CTRL`, ni split 0/0 (Ks `dpu_hw_top.c:29-60`, `dpu_hw_intf.c`) y da
   **0 underruns**. Quedan descartados como causa necesaria C4, C7, el trío vendor de L77b, las LUT de QoS y el multirect.
2. **Lo que sí cambia está fuera de los registros del DPU**: (a) interconnect real con BCM y QoS de NoC, que además aquí
   está votado al máximo por defecto; (b) ACTLR=1 en el CB del display y handoff VBIF→BCR→SMR; (c) reloj MDP 600 MHz
   frente a 514; (d) votos MMCX/MXA a nivel 384; (e) PHY/PLL (strength, CLK_EN_SEL, FLL) y el carril L8 del panel,
   que afectan al "negro con luz" más que al underrun.
3. **Medido hoy en senemos**: plano XR24 3200×2136 sostenido, 120 Hz, `underrun: 0` en INTF1 e INTF2 y `IRQ[0,26]`/`[0,28]`
   (underrun) con contador 0 con las IRQ armadas, vsync 10 556→13 757 (3 201) en la 1ª ejecución, `vblank fps:119`,
   sin ninguna línea nueva en `dmesg` (S `plano/dri-plano-t5.txt`, `t15`, `t2`, `post`, `plano/dmesg.txt`).
   En L76R: `underrun: 108` en cada INTF con `vsync: 109` (L `dri1.txt:4270-4271`, `core_irq` 4341-4343).
4. **Aviso importante sobre cómo leer el 0 de senemos**: todos los nodos de NoC/LLCC/EBI de senemos muestran el agregado
   `2147483647` (voto por defecto de arranque, `sync_state` pendiente) y tiene BCM `keepalive` en MC0/SH0. Es decir, la NoC y
   el DDR están, con alta probabilidad, **al máximo** aunque el display solo pida ~4 GB/s. Sirve de prueba de que "con el
   fabric al máximo no hay underrun", no de que su voto de display sea el correcto.

## 1. Cómo se midió y qué límites tiene

- Capturas en `S:` (ver `S README.md`): `reposo/` (fbcon, modo 120 Hz activo) y `plano/` (modetest `-s 36@79:#0 -v` con
  page-flip, dos ejecuciones). **ICC, relojes, reguladores, genpd, IOMMU, OPP y votos de nivel son idénticos en reposo y en
  plano** (`diff` vacío salvo contadores de UFS y cpu-pd). El pipeline de senemos ya está en su estado final desde el
  arranque (el display se inicializa en `dmesg` 0,59–0,90 s, S `reposo/dmesg.txt:1125-1201`); modetest solo cambia el fb.
- El `underrun: 0` en reposo no vale por sí solo: con `has_idle_pc` las IRQ de underrun se dan de baja entre commits
  (en reposo `core_irq` solo lista `[0,27]`). Vale el de `plano/`, donde `[0,26]` y `[0,28]` están armadas y en 0.
- Lecturas **fuera de la lista blanca del encargo** (todas de estado software, sin MMIO ni WARN en `dmesg`): `crtc-0/status`
  (de ahí sale el multirect), `encoder-0/bridges`, `dri/bridges`, `clients`, `name`, `interconnect_graph`,
  `regulator/<rail>/*` (votos por consumidor), `opp/*display*`, estado de remoteproc y `mailbox_summary`.
  No se leyó nada de lo vetado (`state`, `kms`, `crtc-*/state`, `crc`, `hw_log_mask`, MMIO).
- L76R no se re-midió hoy (la tablet corre senemos). Los datos L76R son los de `L:` del 17-oct 18:49 y el volcado de
  PHY del propio `L: dri1.txt` (`dsi0_phy`/`dsi1_phy`, ya existente). No tengo captura de L77b; L77b también dio underrun
  según el encargo.
- No se leyó `crtc-*/state` en senemos, así que el `core_clk_rate` pedido por el crtc (931 MHz en L76R, `L: dri1.txt:4292`)
  no está medido en senemos; el código es idéntico, así que se infiere el mismo cálculo recortado a su `max_core_clk_rate`.
- Lo que requiere MMIO (ACTLR del CB, fuerza real del PHY, FLL, SMMU) no se midió en senemos. Para PHY hay un dato L76R
  (volcado `dsi*_phy` previo) frente al vendor; para ACTLR solo código y el DT vendor.

## 2. Tabla: pieza | L76R | senemos | vendor | ¿explica el underrun?

| Pieza | Nuestro kernel (L76R) | senemos | Vendor | ¿Explica el underrun? |
|---|---|---|---|---|
| **Resultado** | `underrun` 108/108, vsync 109, frame_done 0 [MEDIDO L `dri1.txt:4270-4271`] | `underrun` 0/0, vsync 120 Hz, IRQ[0,26]/[0,28] = 0 [MEDIDO S `plano/dri-plano-t5.txt`, `t15`] | funciona | — |
| **ICC: topología del display** | solo `llcc_mc`+`ebi` (mc_virt) con `mdp0-mem`; sin `qnm_mdp`, `qns_mem_noc_hf`, `qnm_mnoc_hf`, `qns_llcc`, `qhs_display_cfg` [MEDIDO L `icc.txt:3-15`]. DPU sin `cpu-cfg` (`s288.dts:2688` solo `mdp0-mem`) [CÓDIGO] | ruta completa qnm_mdp→qns_mem_noc_hf→qnm_mnoc_hf→qns_llcc→llcc_mc→ebi y qsm_cfg→qhs_display_cfg [MEDIDO S `reposo/icc-graph.txt:161-191`, `icc.txt:42-107`] | `qnm_mdp` pico 2 500 000, `llcc_mc`/`ebi` pico 800 000, `qhs_display_cfg` 14 000, más RSC de display (`llcc_mc_disp`/`ebi_disp` avg 2 884 683, pico 1 126 829) [V `icc-summary.txt:32,66,95-98,242,434`] | **Sí, probable** (inferido) |
| **ICC: BCM / commits RPMh** | `mc_virt` registrado **sin `.bcms`**: cero comandos RPMh [CÓDIGO Ko `palawan.c:1855-1860`] | BCM reales, `keepalive` en CN0/MC0/QUP0/SH0/SN0/QUP1 [CÓDIGO Ks `qnoc-cliffs-usb.c:427-495`]; MM0 sobre `qns_mem_noc_hf` [Ks `cliffs-display-icc.h:70-74`]; el voter satura el voto a `BCM_TCS_CMD_VOTE_MASK` [Ks `bcm-voter.c:140-144`] | BCM reales | **Sí, probable** (inferido) |
| **ICC: valores agregados** | `llcc_mc`/`ebi` avg 2 151 741 439, pico 2 147 483 647 (INT_MAX por defecto de arranque, `inter_set`) pero sin BCM [MEDIDO L `icc.txt:3,9`] | todos los nodos de mmss/gem/llcc/ebi a 2 147 483 647 por `sync_state` pendiente (`qnm_mdp` 2 147 483 647/2 147 483 647); el voto propio del display, 4 257 792 avg/800 000 pico (+0/0/400 000), igual que L76R [MEDIDO S `reposo/icc.txt:11-22,102-107`; `reposo/dmesg.txt:1428` `sync_state() pending due to adf32bc.qcom,gdsc`] | avg 0/pico 800 000 por mdp + RSC | **El voto propio del display NO difiere** (idéntico a L76R). Lo que difiere es que en senemos el fabric está a INT_MAX **con BCM** [INFERIDO] |
| **QoS de NoC del puerto MDP** | no se programa (el `palawan_mmss_noc` no se instancia) [CÓDIGO UNDERRUN-ANALISIS H1] | `qnm_mdp` puertos `0xad000/0xae000`, `urg_fwd=1`; `qnm_mnoc_hf` `0x33000/0x73000`; `qos_required=true` [CÓDIGO Ks `cliffs-display-icc.h:18-49,85-92`] | SDE/NoC QoS del vendor | **Sí, posible** (inferido; sin medida de registros QoS) |
| **Reloj del DPU** | `disp_cc_mdss_mdp_clk` **514 MHz**, `pll0` 1 542 MHz, OPP máx 325/375/**514** [MEDIDO L `clk.txt:362-368`; `s288.dts:2715-2730`]; `core_perf/max_core_clk_rate` 514 000 000 y el crtc pide **931 392 000** (recortado) [MEDIDO L `dri1.txt:4292,4366`] | **600 MHz**, `pll0` 1 800 MHz, OPP 200/342/402/514/**600** disponibles; `core_perf/core_clk_rate` y `max` = 600 000 000 [MEDIDO S `reposo/clk.txt:142-148`, `opp.txt`, `dri-reposo.txt:68-92`]. El 600 viene del overlay oem-modes (`sm7675-uke-native-display-oem-modes.dtso:15`) [CÓDIGO] | **514 MHz**, `pll0` 1 542 MHz [MEDIDO V `clk-summary.txt:652-659`] | **Posible** (inferido): a 514 MHz 1 600 px tardan 3,11 µs de 3,61 µs de línea (86 %), a 600 MHz 2,67 µs (74 %). El vendor corre 514 con otra topología (dos SSPP, UBWC) |
| **XO / `bi_tcxo`** | **38,4 MHz** (sw), y de ahí `disp_cc_xo`, `ahb`, `esc0/1`, `vsync` a 38,4 MHz; `xo_board` 76,8 MHz [MEDIDO L `clk.txt:108,129,298,352,360`] | **19,2 MHz** y `ahb/esc/vsync` a 19,2 [MEDIDO S `tabla-relojes.txt`, `reposo/clk.txt:95,103,155,161,211`] | 19,2 MHz [MEDIDO V `clk-summary.txt:365,665,671,731`] | **Poco probable** como causa del underrun (inferido): es el rate que cree el CCF; efecto real en `vsync_clk` (`couldn't set disp_cc_mdss_vsync_clk … 19200000 (-22), current rate: 38400000`, L `dmesg.txt:1934`) y en cuentas basadas en el rate (esc/ahb). Corregir `bi_tcxo` a 19,2 es higiene |
| **RCG del MDP en el probe** | `disp_cc_mdss_mdp_clk_src: rcg didn't update its configuration` + WARN en `clk-rcg2.c:136` a 0,308 s [MEDIDO L `dmesg.txt:1012-1013,1039`] | no aparece [MEDIDO S `reposo/dmesg.txt`] | — | **Indicio** (inferido): dispcc se probó sin votos MMCX ni runtime PM |
| **MMCX / MXA / CX** | **no existe ningún regulador `*_level`** en `regulator_summary`; las 6 sondas `smpb1`, `smpb3`, `smpe1-3` y `bobb1` fallan con -22 (`qcom,regulator-type missing`), `ldob22` -131 [MEDIDO L `reg.txt` completo, `dmesg.txt:1279-1289,1333,1339`] | `pm_v8_s6_level` (MMCX): `af00000.clock-controller-vdd_mm` **384/384** + proxy 384; `pm_v8_s8_level` (MX/MXA): `vdd_mxa` 384–416; CX 384–416 [MEDIDO S `reposo/regdetail.txt:7-8,27-28,47-48,59-60`, `reg.txt:4-28`]; clases vdd_mm/vdd_mxa por tasa [CÓDIGO Ks `uke-dispcc-votes.c:10-24,99-114`] | mismos reguladores con `vdd_mm` de dispcc y además `ae00000.qcom,mdss_mdp-mmcx` [MEDIDO V `regulator-summary.txt:33-38,118`] | **Posible** (inferido). No hay medida del nivel MMCX real en L76R (lo deja ABL/AOP) |
| **genpd / GDSC** | `mdss_gdsc` on (1 usuario SW), `mdss_int2_gdsc` off; sin dominios rpmhpd [MEDIDO L `genpd.txt` / `sistema/rpmh.txt`] | igual [MEDIDO S `reposo/genpd.txt:1-8`]; sin rpmhpd tampoco | `disp_cc_mdss_core_gdsc` 1 uso | No (iguales) |
| **Carril del panel L8 (`vddil8b`/`vddio`)** | `pmxr2230_l8` **1304 mV**, `normal`, consumidor del panel con 0/0 mV (sin constraint) [MEDIDO L `reg.txt:21-22`]. El overlay s288 pone `regulator-min/max-microvolt = 0` [CÓDIGO `s288.dts:3800-3808`] | **1900 mV**, `fast`, panel 1900/1900 [MEDIDO S `reposo/reg.txt:48-49`, `regdetail.txt:77-87`] | **1900 mV**, `fast` [MEDIDO V `regulator-summary.txt:194-195`; `DT-v …/rpmh-regulator-ldob8/regulator-pmxr2230-l8/{regulator-min-microvolt,qcom,init-voltage}` = 0x1cfde0 = 1 900 000 µV] | **No** para el underrun del DPU; **sí candidato** para el "negro con luz" (inferido: el voltaje real del carril no está medido) |
| **Otros carriles del DSI** | L4 1200 mV (vdda), L2 880 mV (phy vdds), vsp/vsn 5800 mV [MEDIDO L `reg.txt:11,16,59-62`] | igual [MEDIDO S `reposo/reg.txt:32-38,60-64`] | igual [MEDIDO V `regulator-summary.txt:8-11,158-180`] | No (iguales) |
| **IOMMU: tipo de grupo** | todos `identity`, display en el grupo 17 [MEDIDO L `iommu.txt`] | todos `DMA`, display en el grupo 7; `def_domain_type` fuerza `IOMMU_DOMAIN_DMA` [MEDIDO S `reposo/iommu.txt`; CÓDIGO Ks `arm-smmu-qcom.c:852-856`] | — | Indirecto (el dominio del display es propio en ambos) |
| **SMMU: ACTLR del CB del display** | no se escribe: el CB 69 se programa a mano (CBAR/CBA2R/TCR/TTBR/MAIR/SCTLR) y `qcom_smmu_actlr_client_of_match` no tiene entrada palawan/uke (`…-mdss` de otras SoC sí) [MEDIDO L `dmesg.txt:2833-2842`; CÓDIGO Ko `arm-smmu-qcom.c:36-72`, `arm-smmu-impl.c:134-183`]; `K9 uke_write_mask=0x0` (F4 TLBI, F6 ACTLR silenciados) [MEDIDO L `dmesg.txt:1811`] | `ACTLR=1` (CMTLB) escrito y releído en el CB **nuevo**; exige que el DT lleve la regla `1c00/mask 2 → 1` [CÓDIGO Ks `uke-display-smmu.c:97-128`, `arm-smmu-qcom.c:823-826`] | DT vivo: regla `sid 0x1c00 mask 0x2 → ACTLR 0x1` (y `0x1c01 → 1`) [MEDIDO `DT-v soc/apps-smmu@15000000/qcom,actlr`, decodificado hoy] | **Sí, probable** (inferido): ~6,6 k páginas de 4 KiB por frame, ~800 k recorridos/s sin caché de contexto en el TLB principal. Cero faults SMMU y cero errores VBIF en ambos (L `irq.txt`, `UNDERRUN-ANALISIS H2`; S `irq.txt`) |
| **Handoff MDSS** | `msm_mdss_reset()` mainline (BCR sin parar los XIN antes) en `msm_mdss_init` [CÓDIGO Ko `msm_mdss.c:314-345,387`]; la SMR del display se pasa a BYPASS a los 4,0 s y a TRANS→CB 69 a los 47,3 s [MEDIDO L `dmesg.txt:1905-1911,2835-2841`] | halt de XIN en VBIF (`0x200`/`0x204`), BCR verificado, 20 ms, **release de SMR 1c00/2 → FAULT**, deassert, unhalt, y solo entonces el DPU adjunta su dominio nuevo; salta `msm_mdss_reset`; antes vota 8 GB/s de ICC [CÓDIGO Ks `uke-mdss-handoff.c:11-117`, `msm_mdss.c:247,277,385,495`] | `cont_splash` del vendor | **Posible** (inferido) |
| **Programación DPU (C4, C7, trío L77b, split, LUT, SSPP)** | C4+C7 (L76R) y, en L77b, bit23/prog-fetch/`DSC_CLK_CTRL`/split 0/0 [CÓDIGO `L77B-PREP`] | C4 y C7 sí; bit23/prog-fetch/`DSC_CLK_CTRL`/split 0/0 **no**; LUT iguales; multirect igual [MEDIDO S `reposo/dri-reposo.txt` crtc; CÓDIGO ver §0.1] | trío completo, dos SSPP | **No** (descartado: senemos da 0 sin ellos) |
| **core_perf / danger / vbif** | `min_core_ib 2 500 000`, `min_dram_ib 800 000`, `low/max_core_ab 23,9/26,5 M`, danger/safe todo 0x0, `xin_halt_timeout 16384`, OT 0 [MEDIDO L `dri1.txt:4345-4440`] | iguales salvo `core_clk_rate`/`max_core_clk_rate` = 600 M; danger/safe 0x0 también con el plano activo [MEDIDO S `reposo/dri-reposo.txt`, `plano/dri-plano-t5.txt`] | — | Solo el reloj (fila de reloj). Ojo: el danger de L76R se leyó **sin plano** (`plane-0 crtc=(null)`), no es comparable |
| **PHY: strength** | `HSTX_STR_CTRL_0` (0x0ec) **0x88**, `STR_SWI_CAL_SEL` (0x10c) **0x00** en ambas PHY [MEDIDO L `dri1.txt` bloques `dsi0_phy`/`dsi1_phy`; CÓDIGO Ko `dsi_phy_7nm.c:1067-1077`, sin override V5_2] | escribe **0xff / 0x01** para `xiaomi,uke-o82-dsi-phy-4nm` [CÓDIGO Ks `dsi_phy_7nm.c:1241-1250`] | **0xff / 0x01** en ambas PHY [MEDIDO V `full-dsi0-phy-reg.txt` offsets 0xec/0x10c, igual en dsi1] | **No** para el underrun (el INTF está antes de la PHY); **sí candidato** a "negro con luz" (inferido) |
| **PHY: `CLK_EN_SEL` / retime** | `CLK_CFG1` (0x014) **0x30** (dsi0), **0x34** (dsi1): `CLK_EN_SEL=1` [MEDIDO L `dri1.txt` `dsi*_phy`]; `RBUF_CTRL=1` en `vco_prepare` sin resync [CÓDIGO Ko `dsi_phy_7nm.c:473`] | tras los relojes de los dos hosts: `RBUF_CTRL` 0→1 en ambas PHY y `CLK_EN_SEL=0` [CÓDIGO Ks `dsi_phy_7nm.c:520-556`, `dsi_manager.c` parche 0014] | `CLK_CFG1` **0x20** (dsi0), **0x24** (dsi1) [MEDIDO V `full-dsi*-phy-reg.txt` 0x014] | como la anterior |
| **PHY: FLL del PLL maestro** | no se escribe nunca (queda lo de ABL o el reset); no hay lectura de FLL en L76R [CÓDIGO Ko `dsi_phy_7nm.c`, grep vacío; sin MEDIDO] | `FLL_CONFIG..FAST_PWRUP` = `02 11 00 00 80 00 00` antes de arrancar el PLL parado; se anuncia en `dmesg` [CÓDIGO Ks `dsi_phy_7nm.c:575-616`; MEDIDO S `reposo/dmesg.txt:1175` `Uke O82 FLL cold-start defaults applied`] | `02 11 00 00 80 00 00` (0x6d4..0x6f0) [MEDIDO V `full-dsi0-phy-reg.txt:111-113`] | como la anterior (el PLL de L76R bloquea a 1 189 187 988 Hz igual que senemos y que el vendor) |
| **Relojes de línea DSI** | `pclk0/1` 158 558 398, `byte` 148 648 498, `byte_intf` 74 324 249, VCO 1 189 187 988 [MEDIDO L `clk.txt`] | idénticos [MEDIDO S `tabla-relojes.txt`] | 158 558 666 / 148 648 750 / 74 324 375 | No (iguales) |
| **Errores de plataforma en `dmesg`** | **solo L76R**: WARN `clk-rcg2.c:136` (mdp rcg); `vsync_clk … (-22)`; rpmh-regulator `smpb1/3`, `smpe1-3`, `bobb1` -22 y `ldob22` -131; `qcom-llcc … failed -22`; ICC ausente en `geni_i2c` (`error finding src node`, `UKE-L43-ICC`) y `dwc3-qcom` (`no usb-ddr path (-22)`); `dsi_get_phy: phy driver is not ready` (defer) [MEDIDO L `dmesg.txt:1012,1060,1279-1289,1333,1339,1557-1558,1934,2005-2007`] | **solo senemos**: `kgsl-smmu` -110 y `adreno … failed to load` (GPU sin arrancar), `apps-smmu: Failed to create device link … interconnect` (QTB), `pmic-spmi 0-0d … -5` y WARN `spmi-pmic-arb.c`, `FLL cold-start defaults applied` [MEDIDO S `reposo/dmesg.txt`] | — | Relevantes al display: los de L76R sobre RCG MDP, vsync_clk e ICC; ninguno de senemos toca el display |

## 3. Medido frente a inferido (separados)

**Medido, con las dos caras (L76R y senemos) y sin ambigüedad:**
- Underrun por frame en L76R y 0 en senemos con el mismo modo y el mismo tipo de plano.
- Reloj MDP 514 vs 600 MHz, `pll0` 1 542 vs 1 800 MHz, `bi_tcxo` 38,4 vs 19,2 MHz, y que el vendor es 514 / 19,2.
- Topología ICC: L76R sin `qnm_mdp`/mnoc/gemnoc/cfg; senemos con ruta completa, aristas incluidas.
- Reguladores: senemos tiene MMCX/MXA/CX a nivel 384/384–416 con consumidores `vdd_mm` y `vdd_mxa` de dispcc;
  L76R no tiene ningún regulador de nivel registrado. L8 a 1 304 mV (sin constraint) frente a 1 900 mV.
- IOMMU: grupos `identity` frente a `DMA`.
- Cinco diferencias de PHY frente al vendor en nuestro volcado L76R (dsi0: 0x014, 0x0ec, 0x10c, 0x138, 0x13c; dsi1
  añade 0x010 `CLK_CFG0` 0xf1 vs 0x51). 0x138/0x13c no tienen nombre en `dsi_phy_7nm.xml` (probable estado/calibración).
- ICC, relojes, reguladores, genpd, IOMMU y OPP de senemos no cambian entre reposo y plano.
- Cero faults SMMU y cero errores VBIF en L76R; cero faults SMMU en senemos (`irq.txt`) y sin líneas nuevas en dmesg.

**Inferido (no se midió el efecto):**
- Que la NoC/DDR en L76R esté a un nivel bajo (ningún BCM votado) y que eso deje sin ancho de banda/latencia al fetch.
- Que senemos esté con la NoC al máximo por el INT_MAX de arranque (se mide el agregado, no el nivel del BCM).
- El efecto de ACTLR=0 vs 1 en el CB del display (no hay lectura del ACTLR de ningún kernel; no se leyó MMIO).
- Que el margen de 514 MHz sea insuficiente (cálculo de línea, no medida).
- Que el nivel MMCX de L76R sea bajo (lo que dejan ABL/AOP no se mide).
- Que el 1 304 mV de L8 sea el voltaje real del carril.
- Que el PHY/FLL/CLK_EN_SEL expliquen el negro y no el underrun.
- La narrativa de la historia: L67 (0 underruns) → L71-L74 (1/1) → L76R (uno por frame) encaja con "plataforma justa de
  margen y deltas DPU de L76 (C4/C7, correctos y presentes en senemos) que consumen ese margen".

## 4. Lectura estática pedida (valores que programa cada código)

| Elemento | senemos | nuestro | Vendor medido |
|---|---|---|---|
| ACTLR del CB del display | `arm_smmu_cb_write(…, CB_ACTLR, 1)` + readback, solo CB nuevo y parado (`Ks drivers/iommu/arm/arm-smmu/uke-display-smmu.c:107-111`); condición: regla `0x1c00/2→1` en el DT (`:115-128`); asignación de CB libre cualquiera (`arm-smmu-qcom.c:823-826`) | ninguna escritura: `qcom_smmu_actlr_client_of_match` no incluye el mdss/dpu palawan (`Ko arm-smmu-qcom.c:36-72`; DT `qcom,palawan-mdss` en `s288.dts:2687`, `qcom,palawan-dpu` en `:2705`); bucle F6 de `arm_mmu500_reset` silenciado (`Ko arm-smmu-impl.c:134-183`, `K9 mask=0x0`); CB 69 "reservado desde arriba" (`L dmesg.txt:2833`) | `0x1c00/0x2 → 0x1`, `0x1c01 → 0x1` (DT-v, decodificado) |
| Liberar la SMR de ABL del display | `uke_display_release`: SMR `1c00/mask 2` → `valid=0` verificado, `S2CR=FAULT`, `cbndx=0xff` (`Ks uke-display-smmu.c:29-74`) | `FIX-A1b reclaim`: reescribe `idx=2` en BYPASS a 4,0 s y TRANS→CB 69 a 47,3 s (`L dmesg.txt:1905-1911,2839-2841`) | `cont_splash` |
| Orden del handoff | VBIF halt (`0x200`/`0x204`, XIN 0,1,4,5,9,13,14) → BCR → SMR release → deassert → unhalt (`Ks uke-mdss-handoff.c:9,68-107`) | BCR sin halt, en probe (`Ko msm_mdss.c:387`) | — |
| ICC antes del handoff | `Bps_to_icc(8 GB/s)` hasta `uke_handoff_complete`, luego `MIN_IB_BW` (`Ks msm_mdss.c:247`) | `MIN_IB_BW` contra un provider sin BCM | — |
| Fuerza del PHY DSI | `SWI_CAL=0x01`, `HSTX_STR_0=0xff` (`Ks dsi_phy_7nm.c:1241-1250`) | `0x00` / `0x88` (`Ko dsi_phy_7nm.c:1067,1077`; V5_2 no los cambia, `:1095-1110`) | `0x01` / `0xff` |
| `CLK_EN_SEL` | `dsi_pll_cmn_clk_cfg1_update(…, CLK_EN_SEL, 0)` en ambas PHY tras los dos hosts (`Ks dsi_phy_7nm.c:553-554`) | permanece a 1 (`Ko dsi_phy_7nm.c:473`) | `CLK_CFG1` 0x20/0x24 (bit4 = 0) |
| FLL | `0x02,0x11,0,0,0x80,0,0` en `FLL_CONFIG..FAST_PWRUP` si `vco_current_rate` ∈ [1 189 187 000, 1 189 191 000] y PLL parado (`Ks dsi_phy_7nm.c:575-616`) | no se escribe | `02 11 00 00 80 00 00` |
| Votos MMCX/MXA de dispcc | `vdd_mm`/`vdd_mxa` por tasa (MDP 155/200/342/402/514/600 MHz en `VDD_LOWER_D1…VDD_HIGH`) + proxy (`Ks uke-dispcc-votes.c:10-24,99-114`) | `dispcc-sm8550.c` sin votos ni runtime PM (`Ko dispcc-sm8550.c:1791-1793`) | `vdd_mm`, `vdd_mxa` + `mdss_mdp-mmcx` |
| QoS de NoC del MDP | `urg_fwd=1`, puertos `0xad000/0xae000` y `0x33000/0x73000`; MM0 | no se programa | — |

## 5. Lista ordenada de las diferencias más probables (causa del underrun) y el experimento que las confirma

Ordenadas por probabilidad para el síntoma "underrun por frame, fetch hambriento". Todos los experimentos son medibles con el
contador `encoder-0/status` + `core_irq` + `modetest` a 120 Hz; los que escriben debugfs necesitan permiso expreso (esta sesión
no escribió nada).

1. **Fabric sin votos reales: sin BCM ni QoS de NoC (ICC no-op en L76R) frente a BCM `keepalive` + INT_MAX + `urg_fwd` en senemos.**
   Experimento (sin rebuild, en L76R): fijar el DDR al máximo desde AOSS (en senemos existe
   `/sys/kernel/debug/qcom_aoss/ddr_frequency_mhz`, solo escritura; en L76R el directorio `qcom_aoss` aparece en
   `build/linux-l76r-20261017/sistema/rpmh.txt:1-5`, falta confirmar que tenga ese fichero) y repetir modetest. Si el
   underrun cae a 0, el cuello es ancho de banda/latencia de DDR-NoC y no el DPU. La ablación equivalente en senemos
   (quitar el voto INT_MAX o los `keepalive` de MC0/SH0) exige recompilar su kernel, por lo que solo queda anotada.
   Marcador de éxito: Δunderrun = 0 con Δvsync > 100 en 20 s.

2. **ACTLR=1 (CMTLB) en el CB del display y CB/TLB nuevos tras halt de VBIF + BCR.**
   Experimento: con L76R, leer `ACTLR` del CB 69 (una lectura puntual del registro de ese CB, que esta sesión no podía
   hacer) y, si es 0, escribir `1` justo después de `write_context_bank` y antes de activar el CRTC; repetir modetest. En
   senemos la contraparte es leer el mismo registro del CB del display: debe valer 1 (comprueba que la regla del DT se aplicó).
   Marcador: Δunderrun = 0 solo cambiando ACTLR.

3. **Reloj del DPU: 600 MHz (senemos) frente a 514 MHz (L76R).**
   Experimento (el más barato y reversible): en senemos, `core_perf/fix_core_clk_rate` a 514 000 000 con modetest activo
   y ver si empieza a haber underrun; el recíproco en L76R es añadir `opp-600000000` al DPU (requiere el voto MMCX de la causa
   4). Si senemos a 514 MHz sigue limpio, el reloj no es el factor; si cae, es margen de línea (3,11 de 3,61 µs).

4. **Votos MMCX/MXA a nivel 384 (dispcc `vdd_mm`/`vdd_mxa` + proxy) frente a ninguno.**
   Experimento: medir el nivel real del ARC de MMCX en L76R (el `rpmh` `cmd-db` da la dirección de `mmcx.lvl`; el valor activo
   no se lee desde el kernel sin MMIO; una vía sin MMIO es el tracepoint `rpmh:rpmh_send_msg` de tracefs) o, más simple, registrar
   los reguladores `*_level` con el voto proxy a 384 y ver si desaparece el WARN `rcg didn't update its configuration` y el
   underrun. Marcador: ausencia del WARN `clk-rcg2.c:136` y Δunderrun = 0.

5. **Handoff sin halt de VBIF + BCR + release de SMR** (tabla §4).
   Experimento: instrumentar, solo en el arranque, un halt de los XIN con espera de ACK antes del BCR de `msm_mdss_init`,
   dejando el resto igual, y comparar el underrun. Es la menos probable de las cinco porque no explica el ritmo del fetch
   salvo que quede estado de ABL en los XIN.

**Para el "negro con luz" (síntoma distinto del underrun)**, no del DPU: strength del PHY 0xff/0x01, `CLK_EN_SEL`=0 con
resync de `RBUF_CTRL`, FLL y L8=1 900 mV (cinco diferencias de PHY medidas frente al vendor; L8 a 1 304 mV sin constraint).
Experimento: volver a tomar el volcado `dsi*_phy` de L76R tras aplicar cada una y comprobar que coincide con el vendor
(0x014 → 0x20/0x24, 0x0ec → 0xff, 0x10c → 0x01), y leer `regulator_summary` de L8.

## 6. Qué no se pudo cerrar

- Ningún registro de SMMU/PHY/PLL/NoC se leyó en senemos (regla de no MMIO), así que ACTLR, QoS de NoC, FLL y strength reales
  de senemos son código, no medida. Las lecturas de PHY son L76R frente al vendor.
- No hay medida del nivel real de DDR/BCM/MMCX en ninguno de los dos kernels.
- El `danger_status` de L76R se tomó sin plano; falta repetirlo con modetest sostenido para saber si el SSPP 8 llega a
  asertar danger (en senemos con plano es 0 en todos).
- L77b no se capturó: solo L76R.
- El vendor ejecuta con UBWC y dos SSPP: la comparación de reloj y de ancho de banda con él es cualitativa.

Capturas y script: `build/linux-senemos-20261017/` (ver su `README.md`).
