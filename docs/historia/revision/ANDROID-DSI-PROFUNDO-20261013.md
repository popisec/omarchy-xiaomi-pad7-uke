# Android DSI profundo — panel O82 (Xiaomi Pad 7 «uke»): secuencia, rails, comandos, reset, TDDI, PHY y timings

**Fecha:** 13-oct-2026. **Fuentes primarias verificadas en esta sesión** (nada de memoria):

- `~/proyectos/ubuntu-uke/stock/modules/msm_drm.ko` (ELF aarch64 no stripped, 21891 símbolos
  `nm | wc -l` = 21930 entradas totales; BuildID `9a06914a…`), desensamblado con
  `llvm-objdump --arch-name=aarch64 -d -r --disassemble-symbols=<sym>` + resolución de
  `R_AARCH64_CALL26` a símbolo y de `.text+off` locales a nombre vía `nm` ordenado.
- DT real Android: `build/evidencia/android-snap/dt-r15/` (cada property = fichero; u32 big-endian).
- Mainline vivo: `build/kernel-pokes/k52L27-tree/drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c`
  (870 líneas; se cita como `o82:`; L29 comprobado idéntico en los puntos relevantes).
- Firmware: `~/proyectos/ubuntu-uke/stock/firmware/` (`mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid_mi.xml`,
  `display_id_*.xml`, `DPU1010.xml`/`DPU1020.xml`).
- Corrige/amplía: `build/gates/revision/SECUENCIA-ENCENDIDO-ANDROID-O82-20261012.md` (citado `§A–E/20261012`).

**Conclusión en una frase:** el borrador del 12-oct es correcto en lo esencial (orden clocks→PHY→host→
rails→reset→DCS-en-enable); esta revisión lo confirma instrucción a instrucción, precisa 6 puntos donde
era impreciso/incompleto, y añade el dato nuevo más importante: **en el path de power de Android NO hay
ningún `set_rate` ni ningún `reparent` de clocks** — solo votos `prepare+enable`; rates y parents se
programan en el path de modeset. Detalle en §1.5.

---

## 1. Secuencia completa de encendido (verificada instrucción a instrucción)

### 1.1 `dsi_display_prepare` — `.ko:0x145224` (`T dsi_display_prepare`), rama feliz

Tabla ordenada por offset. `x0=display*` salvo nota. `dsi_display_clk_ctrl(mngr, w1=tipo, w2=on)`:
`w1: 1=DSI_CORE_CLK, 2=DSI_LINK_CLK`; `w2: 1=ON, 0=OFF` (semántica confirmada por los paths de error:
`0x145be8: (1,0)` apaga core tras fallo; `0x145c58: (2,0)` apaga link tras fallo de soft-reset).

| # | Offset | Llamada (resolución CALL26 / local→símbolo) | Args notables | Notas |
|---|---|---|---|---|
| 1 | 0x145288 | `sde_evtlog_log` | — | traza |
| 2 | 0x145294 | `mutex_lock` | `x0=display+0x48` | `display_lock` |
| 3 | 0x1452d4 | `dsi_ctrl_clk_cb_register` | `x0=ctrl0` (`[display+0xa8]`) | registra callback de clocks del ctrl0 |
| 4 | 0x145338 | `dsi_phy_clk_cb_register` | — | rama de error → `-22` |
| 5 | 0x1453b4 | `dsi_ctrl_isr_configure(ctrl0, ON)` | `w1=1` | **ISRs antes que clocks** |
| 6 | 0x1453d4 | `dsi_ctrl_isr_configure(ctrl1, ON)` | `w1=1` | `x0=[ctrl0]` = ctrl1 |
| 7 | 0x145450 | `dsi_display_clk_ctrl` | `x0=[display+0x4e8]=clk_mngr, w1=1 (CORE), w2=1 (ON)` | **primer voto core** |
| 8 | 0x1454a8 | `.text+0x13f354` = **`dsi_display_phy_sw_reset`** | `x0=display` | reset SW de PHY por ctrl (ver §1.3) |
| 9 | 0x1454ec | `dsi_ctrl_clk_cb_register` | `x0=[display+0xd8]` = ctrl1 | 2º ctrl |
| 10 | 0x14550c | `dsi_display_clk_ctrl` | `w1=1 (CORE), w2=1 (ON)` | **segundo voto core** (w4=1, w5=rc previo) |
| 11 | 0x145540 | `.text+0x145c98` = **`dsi_display_phy_enable`** | `x0=display` | PHYs a LP11, nada en HS (ver §1.3) |
| 12 | 0x1455a4 | `dsi_ctrl_update_host_state` | `x0=ctrl0, w1=5, w2=1` | `5` = estado HOST_INIT esperado; `w2=1` = set |
| 13 | 0x1455ec | `dsi_ctrl_host_init` | `x0=ctrl0, w1=w22` (w22=1, ver paso 8: `mov w22,#1` en 0x14549c) | programa host ctrl0 |
| 14 | **0x145628** | **`dsi_panel_pre_prepare`** | `x0=[display+0x108]=panel` | **RAILS + RESET + PINCTRL. Ver §1.2** |
| 15 | 0x145658 | `dsi_ctrl_host_timing_update` | `x0=ctrl0` | timings del ctrl0 (del modo) |
| 16 | 0x1456c4 | `dsi_ctrl_host_init` | `x0=ctrl1 ([display+0xd8]), w1=w22` | programa host ctrl1 |
| 17 | 0x1456fc | `dsi_ctrl_host_deinit` | `x0=ctrl0` | **rama condicional** (dual-ctrl / error; ver §1.4) |
| 18 | 0x14570c | `dsi_phy_clk_cb_register` | `x0=[display+0xf0]` | re-registro tras init |
| 19 | 0x145738 | `dsi_ctrl_update_host_state` | `x0=ctrl1, w1=5, w2=1` | igual que paso 12 para ctrl1 |
| 20 | 0x1457a0 | `alloc_workqueue` | `w1=0xe000a` (flags), `w2=1` | workqueue del display |
| 21–24 | 0x145894, 0x14590c, 0x145940, 0x14597c | `dsi_ctrl_set_host_engine_state` ×4 | `w1=1 (ON)` las tres primeras (cmd+vid de ctrl0/ctrl1); la 4ª `w1=0` (x0=[x25], engine de video del path secundario, `w1=wzr`) | arranca command+video engines de ambos ctrls |
| 25 | **0x145990** | **`dsi_display_clk_ctrl`** | **`w1=2 (LINK), w2=1 (ON)`** | **voto link; a partir de aquí hay reloj de enlace** |
| 26 | 0x1459c0 | `.text+0x145e20` = **`dsi_display_ctrl_host_disable`** | `x0=display` | deshabilita host-ctrl tras configurar engines (normal: deja el host en estado de espera de comandos pre-video) |
| 27 | bloque 0x1459c4–0x145bdc | condicionales por `ctrl_num ([display+0xa4])==2` + `host_deinit` + prints | — | teardown condicional del 2º ctrl + `clk_ctrl(CORE=1, OFF=0)` en 0x145be8 + `mi_disp_mievent_str` — **ramas de error / cont-splash**, no rama feliz (ver §1.4) |
| 28 | **0x145c20** | **`dsi_display_soft_reset`** | `x0=display` | soft-reset de los ctrls con link ya votado |
| 29 | 0x145c58 | `dsi_display_clk_ctrl` | `w1=2, w2=0` | **solo en fallo de soft-reset** (`cbnz` en 0x145c24): apaga link y reintenta en 0x1459bc |
| 30 | **0x145c6c** | **`dsi_panel_prepare`** | `x0=panel` | 2º reset + PRE_ON (vacío) — ver §1.2 |
| 31 | 0x145a64 | retorno común (`w21`=rc) | — | éxito `w21=0` vía 0x145ad8 |

**Correcciones al borrador §A/20261012:**

- (a) El paso «12. LINK_CLK + soft_reset» era en realidad **LINK ON (0x145990) → ctrl_host_disable
  (0x1459c0) → bloque condicional → soft_reset (0x145c20) → panel_prepare (0x145c6c)**. El
  `ctrl_host_disable` intermedio no estaba en el borrador. No cambia la conclusión de orden.
- (b) El borrador decía «paso 12 `dsi_display_clk_ctrl(DSI_LINK_CLK=2, ON=1) # .ko 0x145990» — correcto,
  pero el `dsi_display_clk_ctrl` de 0x145c58 (`w1=2,w2=0`) que el borrador no mencionaba es **path de
  error**, no parte de la secuencia feliz. No hay doble voto de link en rama feliz.
- (c) `alloc_workqueue` (0x1457a0) entre host-state y engine-states no estaba en el borrador; irrelevante
  para el port pero confirma que la captura de CALLs del borrador era completa en todo lo demás
  (todos los demás CALLs coinciden).

### 1.2 `dsi_panel_pre_prepare` — `.ko:0x1553e8` (`T dsi_panel_pre_prepare`): rails + reset + pinctrl

Verificado CALL a CALL contra el borrador §A.1 — **se confirma íntegro**, con estas precisiones:

```
0x15540c  mutex_lock(panel+0x3f8)                        # panel_lock
0x155430  dsi_pwr_enable_regulator(panel+0x550, w1=1=ON)  # voto nº1
0x155470  dsi_pwr_enable_regulator(panel+0x550, w1=1=ON)  # voto nº2
          # panel+0x550 es el array de vregs del host (vddio/vci); los NOMBRES viajan
          # en DT, no en el binario → la identidad vddio=L8 / vci=L19 sigue siendo
          # INFERENCIA por DT (display-primary: vddio-supply=0x14f, vci-supply=0x150),
          # pero el HECHO de que son exactamente 2 votos consecutivos es literal.
0x1554a4  mi_get_panel_id_by_dsi_panel(panel) → cmp w0,#0x16 ─┐
0x1554b4  mi_get_panel_id_by_dsi_panel(panel) → cmp w0,#0x18 ─┤
0x1554c4  mi_get_panel_id_by_dsi_panel(panel) → cmp w0,#0x17 ─┘ b.ne 0x1555ac (skip)
          # 0x16/0x18/0x17 = panel-IDs Xiaomi que SÍ encienden panel-supplies.
          # El o82 es 0x42... (mi,panel-id = 00 4f 38 32 50 42 02 0b → "O82PB_02_0b");
          # el panel_id numérico lo deriva mi_get_panel_id_by_dsi_panel del DT/panel-id.
          # Si el ID no matchea, SALTA el bloque 0x1554d0-0x155514 (vregs+reset) e iría
          # a 0x1555ac: gpio 0 + pinctrl + ... (el panel o82 SÍ matchea: sigue 0x1554d0).
0x1554f4  mi_dsi_pwr_enable_vregs(panel+0x550, w1=1=ON, w2=2)
          # w2=2 → ¿índice o count? Ver §4: enciende las 3 panel-supply-entries en orden.
0x155514  dsi_panel_reset(panel)  (.text+0x155ed8 → T dsi_panel_reset)  # ver §3
0x15554c  gpio_to_desc([panel+0x5e0]) + 0x155554 gpiod_set_raw_value(desc, w1=0)
0x155564  gpio_to_desc([panel+0x5a4]) + 0x15556c gpiod_set_raw_value(desc, w1=0)
          # dos GPIOs a 0 (TE/HBM o mode-gpios; offsets 0x5e0/0x5a4 del struct panel.
          # dsi_panel_parse_gpios parsea: platform-reset (0x5dc), platform-sec-reset,
          # panel-mode, panel-sec-mode, 5v-boost, platform-en, mode-sel-gpio-state,
          # panel-test-pin (strings .rodata verificadas §6). 0x5e0/0x5a4 = dos de ellos.)
0x155584  pinctrl_select_state(panel+0x5f0, [panel+0x600])  # panel_active (sde_dsi_active+sde_te_active)
0x1555d8  pinctrl_select_state(panel+0x5f0, [panel+0x5f8])  # 2º estado (mismo pinctrl, otro state)
```

Novedad vs borrador: el gate por panel-id (0x16/0x18/0x17) y el doble `pinctrl_select_state` (no uno).
El resto idéntico al borrador.

`dsi_panel_prepare` (`.ko:0x155e10`, `T`): confirma borrador §A.2 — `mutex_lock` + `dsi_panel_reset()`
(**2º reset**) + `tx(PRE_ON)` solo si flag `panel+0x828`; PRE_ON ausente en DT del o82 ⇒ no-op.

### 1.3 Qué hay EXACTAMENTE entre `clk_ctrl` y `pre_prepare` (pregunta del objetivo §1)

Entre 0x145450 (CORE ON) y 0x145628 (pre_prepare) hay, en orden:

1. `dsi_display_phy_sw_reset` (0x1454a8 → `t dsi_display_phy_sw_reset @0x13f354`): llama a
   `dsi_ctrl_phy_sw_reset` ×3 (offsets CALL 0x13f3dc/0x13f428/0x13f458) — reset del bloque PHY de cada
   ctrl, **con core-clock ya votado** (el reset SW necesita el reloj).
2. `dsi_ctrl_clk_cb_register` del 2º ctrl (0x1454ec).
3. Segundo voto CORE ON (0x14550c).
4. `dsi_display_phy_enable` (0x145540 → `t dsi_display_phy_enable @0x145c98`): llama a `dsi_phy_enable`
   ×3 (0x145d10/0x145d78/0x145dbc: phy0, phy1 + re-check) — los lanes suben a **LP11**; no hay tráfico HS.
5. `dsi_ctrl_update_host_state(ctrl0, 5, 1)` + `dsi_ctrl_host_init(ctrl0, 1)` — el host se programa con
   PHY vivo en LP11.

**No hay ningún `set_rate`, `set_parent`, ni `prepare_enable` extra escondido**: `dsi_display_clk_ctrl`
(`T @0x159870`) → `dsi_clk_req_state` → `dsi_recheck_clk_state` (`t @0x15921c`) → dos ramas:

- core: `dsi_display_core_clk_enable` (`t @0x15a4c4`) → `dsi_core_clk_start` → **`clk_prepare` +
  `clk_enable`** (verificado en `dsi_core_clk_start`: CALLs `clk_prepare/clk_enable/clk_unprepare`
  en 0x158c9c–0x158d14; `dsi_clk_prepare_enable` igual en 0x158b94–0x158c14).
- link: `dsi_clk_update_link_clk_state` (`t @0x159ff8`) → **`clk_disable/clk_unprepare` o
  `clk_prepare/clk_enable`** según vote (verificado CALLs en 0x15a140–0x15a214).

O sea: el path de power solo vota ON/OFF sobre relojes ya padre/hijo-configurados y con rate heredado
(del ABL/splash o del voto anterior). Ver §1.5 para dónde SÍ se programan rates/parents.

### 1.4 Ramas condicionales del prepare (cont-splash / dual-ctrl / error)

- El bloque 0x1459c4–0x145bdc está guardado por `ldr w8,[display+0xa4]` (= `ctrl_num`) con `cbz/cmp #2`:
  `host_deinit` del ctrl0/ctrl1 solo corre si hay 2 ctrls y en condiciones de error/splash. En rama feliz
  dual-DSI (ctrl_num=2) los `cbz w0` caen a los siguientes bloques y se llega a soft_reset.
- `dsi_display_enable` (`T @0x146e90`) confirma borrador: `dsi_display_config_ctrl_for_cont_splash`
  (0x146f30) si splash vivo → salta prepare de panel; lecturas `mi_dsi_display_read_panel_build_id`
  (0x147088) + `mi_dsi_panel_read_peak_hdr_gamma` (0x1470e0) solo diagnóstico; `tx(190)` (0x147154,
  fps-90-gamma, ausente en DT ⇒ no-op); `dsi_panel_enable` (0x14718c) con **ON=1**; `dsi_panel_update_pps`
  (0x147268); extras `mi_dsi_panel_set_dc_mode/dbi_3dlut/csc` (0x1472a8–0x147344, todos no-op sin DT).
- `dsi_display_post_enable` (`T @0x1476a8`): `dsi_panel_post_enable` (0x147724) → `tx(POST_ON)` vacío +
  `dsi_panel_switch_cmd_mode_in`/`switch_video_mode_in` (0x1477a4/0x1477ac) + `mi_dsi_panel_set_gamma_update_state`
  + **`dsi_display_clk_ctrl` en 0x147850** (último voto del post-enable) + `mutex_unlock`.

### 1.5 Dónde se programan rates y parents (respuesta a «¿hay set_rate del SRC/RCG en power?»)

**No.** Verificación exhaustiva por CALL26 en todo el `.ko`:

| Función | Llamada | Solo aparece en |
|---|---|---|
| `dsi_clk_set_link_frequencies` (`T @0x158844`) | — | `dsi_display_set_link_frequencies` (`T @0x143a48`, path de **modeset**) ×2 (0x143a90/0x143ae8) |
| `dsi_clk_set_byte_clk_rate` / `dsi_clk_set_pixel_clk_rate` | `msm_dss_clk_set_rate`/`single` | `dsi_display_dynamic_clk_switch_vid` (0x14be28–0x14c038, **DFPS/switch**) y `dp_power/sde_power` (no DSI) |
| `dsi_clk_update_parent` (`T @0x158af0`) → `clk_set_parent` (import) | reparent | solo desde `dsi_ctrl_set_clock_source` (`t @0x135ba4/0x135bd8`) |
| `dsi_ctrl_set_clock_source` | reparent RCG | solo desde `dsi_display_set_clk_src` (`t @0x148964`) |
| `dsi_display_set_clk_src` | — | solo desde `dsi_display_phy_pll_toggle` (0x13dd5c/0x13dd6c, toggle de PLL en modeset/ULPS) |
| `msm_dss_clk_set_rate` (import `clk_set_rate`) | set_rate SRC/RCG | `dp_power_clk_set_rate`, `sde_power_resource_init` — **nunca en path DSI-panel power** |

**Implicación para mainline:** el orden invertido de mainline (rails antes de clocks) no se arregla con
rates — el KMD ni siquiera toca rates en power. Lo que el panel necesita es **relojes ya votados (LP11)
antes de rails+reset**, que es exactamente lo que `prepare_prev_first=false` (ya aplicado en L27,
`o82:800`) restaura: el prepare corre tras el `pre_enable` del host DSI de mainline. El riesgo H-2
(clobber del RCG compartido `mdp_clk_src`) sigue siendo el siguiente sospechoso si el SoC muere con
prepare real, pero ya no es «el panel»: el panel está totalmente caracterizado.

---

## 2. Los 108 comandos DCS (transcripción byte a byte verificada)

Blob: `…/qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid/qcom,mdss-dsi-display-timings/timing@120/
qcom,mdss-dsi-on-command` = **998 B**. Cabecera por registro: `dt,u8 flags[3],wait_ms,len_be16`
(`dt=0x39` = DCS-long-write en el encoding CAF; `flags 00 00 40` = último de la ráfaga / `00 00 00` =
continuará — verificado: los `00 00 00` caen en #6, #12, #74, #105, #106, #107, i.e. cambios de página
o fin de secuencia). Parseo completo 节 (off = offset en el blob):

```
#    off  flags   wait len payload
0      0  000040    0   2  ff 27            # SELECT PAGE 0x27
1      9  000040    0   2  fb 01            # sub-page enable
2     18  000040    0   2  d0 31
3     27  000040    0   2  d1 20
4     36  000040    0   2  d2 38
5     45  000040    0   2  de 43
6     54  000000    0   2  df 02            # (flags 0: sigue página)
7     63  000040    0   3  08 24 0a
8     73  000040    0   3  0c 1e 00
9     83  000040    0   3  10 1e 00
10    93  000040    0   3  80 57 09
11   103  000040    0   3  84 2d 00
12   113  000000    0   3  88 2d 00
13   123  000040    0   2  ff 23            # PAGE 0x23 (curva gamma R)
14   132  000040    0   2  fb 01
15   141  000040    0   2  00 80
16   150  000040    0   2  01 84
17   159  000040    0   2  05 f6
18   168  000040    0   2  06 02
19   177  000040    0   2  11 03            # (NO es sleep-out: estamos en página vendor 0x23)
20   186  000040    0   2  12 2a
21   195  000040    0   2  15 d0
22   204  000040    0   2  16 16
23   213  000040    0   2  29 0a            # (NO es display-on: página vendor)
24   222  000040    0   2  30 ff
25   231  ...02  31 fe
26   240  ...02  32 fd
27   249  ...02  33 fb
28   258  ...02  34 f8
29   267  ...02  35 f5
30   276  ...02  36 f3
31   285  ...02  37 f2
32   294  ...02  38 f2
33   303  ...02  39 f2
34   312  ...02  3a ef
35   321  ...02  3b ec
36   330  ...02  3d e9
37   339  ...02  3f e5
38   348  ...02  40 e5
39   357  ...02  41 e5                      # (rampa gamma 0x30..0x41)
40   366  ...02  2a 13
41   375  ...02  45 ff
42   384  ...02  46 f4
43   393  ...02  47 e7
44   402  ...02  48 da
45   411  ...02  49 cd
46   420  ...02  4a c0
47   429  ...02  4b b3
48   438  ...02  4c b1
49   447  ...02  4d b1
50   456  ...02  4e b1
51   465  ...02  4f 95
52   474  ...02  50 79
53   483  ...02  51 5c
54   492  ...02  52 58
55   501  ...02  53 58
56   510  ...02  54 58                      # (rampa gamma 0x45..0x54)
57   519  000040    0   2  ff 23            # re-select página 0x23
58   528  000040    0   2  fb 01
59   537  ...02  58 ff
60   546  ...02  59 fb
61   555  ...02  5a f7
62   564  ...02  5b f3
63   573  ...02  5c ef
64   582  ...02  5d e3
65   591  ...02  5e d9
66   600  ...02  5f d7
67   609  ...02  60 d7
68   618  ...02  61 d7
69   627  ...02  62 c9
70   636  ...02  63 b9
71   645  ...02  64 ac
72   654  ...02  65 aa
73   663  ...02  66 aa
74   672  000000    0   2  67 aa            # (fin de página, flags 0)
75   681  000040    0   2  ff 25            # PAGE 0x25
76   690  000040    0   2  fb 01
77   699  000040    0   2  0f 20
78   708  000040    0   2  ff 2a            # PAGE 0x2a
79   717  000040    0   2  fb 01
80   726  000040    0   2  c4 82
81   735  000040    0   2  ff 26            # PAGE 0x26
82   744  000040    0   2  fb 01
83   753  000040    0   2  3b 06
84   762  000040    0   2  4b 06
85   771  000040    0   2  ff 22            # PAGE 0x22
86   780  000040    0   2  fb 01
87   789  000040    0   2  c4 06
88   798  000040    0   2  ff f0            # PAGE 0xf0 (vendor unlock)
89   807  000040    0   2  fb 01
90   816  000040    0   2  fa 05
91   825  000040    0   2  76 16
92   834  000040    0   2  ff 20            # PAGE 0x20
93   843  000040    0   2  fb 01
94   852  000040    0   2  30 00
95   861  000040    0   2  ff 10            # PAGE 0x10 (= página DCS estándar)
96   870  000040    0   2  fb 01
97   879  000040    0   3  51 0f ff         # DCS 0x51 BRIGHTNESS = 0x0FFF (4095)
98   889  000040    0   2  53 24            # DCS 0x53 CTRL-display: 0x24 (BL on, dimming ...)
99   898  000040    0   7  3b 03 94 1a 04 04 00  # DCS 0x3B (?? vendor, 6 B params)
100  912  000040    0   2  90 03            # vendor DSC-ish 0x90
101  921  000040    0  17  91 ab 28 00 18 d2 00 02 b2 02 9f 00 0b 04 86 02 dc  # 0x91 +16 B
102  945  000040    0   3  92 10 f0         # 0x92
103  955  000040    0   2  9d 01            # 0x9D
104  964  000040    0   2  b3 40            # timing-select 120 Hz (b3=0x40)
105  973  000000    0   2  b2 91            # timing-select 120 Hz (b2=0x91)
106  982  000000  120   1  11               # DCS 0x11 SLEEP-OUT +120 ms (ÚNICO wait≠0)
107  990  000000    0   1  29               # DCS 0x29 DISPLAY-ON
```

Qué hace cada página (lectura funcional, vendor Nova/CSOT-O82):

- `0x27` (#0–12): init analógico/DDIC (regs `d0/d1/d2/de/df`, trim `08/0c/10/80/84/88`).
- `0x23` (#13–74): **curva gamma** — dos rampas (`0x30–0x41`, `0x45–0x54`, `0x58–0x67`) + bias
  (`00/01/05/06`, `2a`, `11/12/15/16`). Los `11 03` y `29 0a` intermedios son registros de página,
  no DCS.
- `0x25` (#75–77), `0x2a` (#78–80), `0x26` (#81–84), `0x22` (#85–87): trims de source/gate/TCON.
- `0xf0` (#88–91): unlock vendor + `fa/76`.
- `0x20` (#92–94): `30 00`.
- `0x10` (#95–103): página estándar: **`0x51=0x0FFF`, `0x53=0x24`, `0x3B`, `0x90/0x91/0x92/0x9D`**
  (bloque de compresión/DSC del vendor; el IC viene preconfigurado, no es PPS estándar).
- Cola (#104–107): select de frecuencia + `0x11` +120 ms + `0x29`.

Comparación con mainline (`o82:99-104` + `o82_send_panel_cmds` + cola en `o82_prepare o82:406-420`):

| Aspecto | Android | Mainline L27 | Veredicto |
|---|---|---|---|
| Comandos #0–103 | 964 B (verificado `998−34=964`) | `o82_init_cmds[]` (cabecera dice «comandos 1..104 (964 bytes)») con flags `00 00 40` y mismos payloads (spot-check `#0 ff 27`, `#19 11 03`, `#97 51 0f ff`, `#101 91 ab…dc` idénticos) | **Transcripción fiel, sin duplicados** |
| Cola timing (b3/b2) | #104 `b3 40`, #105 `b2 91` (120 Hz) | `freq_sel` con `desc->freq_reg_b3/b2 = 0x40/0x91` (`o82:406-414`) | OK |
| Sleep-out / Display-on | #106 `0x11`+120 ms, #107 `0x29` | `o82:414-420` (`0x11`, `msleep(120)`, `0x29`) | OK |
| OFF | `0x28`+20 ms, `0x10`+100 ms, `0x4f` (24 B, LP) | `o82:460-467` idéntico (`enter_sleep`, `msleep(100)`, `0x4f`) | OK |
| Dónde se envían | **enable** (paso 18, host+video configurados, LP) | **prepare** (antes de modeset/vid-engine) | Diferencia de fase (funciona en LP; el fix estructural `prepare_prev_first=false` ya la mitiga) |
| Backlight 0x51 | tras 1ª trama + 300 ms (§5) | `o82_enable` (`o82:520-526`, tras modeset) | L27 ya lo movió a enable — OK |
| Switch HS | `timing-switch-video-command` en HS (ver §7) | pendiente (TODO en `o82:397-403`) | Futuro, no bloquea 120 Hz |

**¿Hay algún comando que mainline NO envíe? No.** Cobertura 108/108 en contenido. La única diferencia es
la fase (prepare vs enable) y el 0x51 diferido (ya portado a `o82_enable`).

### 2.1 OFF y switch (bytes verificados)

- `off-command` (24 B, `off-state=dsi_lp_mode`), idéntico en timing@{120,144,90}:
  `05 00 00 00 14 00 01 28` = DCS `0x28` +20 ms; `05 00 00 00 64 00 01 10` = `0x10` +100 ms
  (`05`=DCS-short, wait `0x14`=20 / `0x64`=100, len 1); `05 … 00 00 01 4f` = `0x4f` +0 ms.
- `timing-switch-video-command` (36 B, **`dsi_hs_mode` — único set en HS**):
  `39 … 02 ff 10, 39 … 02 fb 01, 39 … 02 b2 {91|00|00}, 39 … 02 b3 {40|00|80}`
  (120: `b2=91 b3=40`; 144: `b2=00 b3=00`; 90: `b2=00 b3=80`). `39`=DCS-long, wait `0x40`=64 ms
  (bytes 3–4 del header: `00 40` = delay 64 ms tras cada write), len 2.

---

## 3. Reset y power-timings (exacto, con lo que el driver hace con ellos)

DT (`qcom,mdss-dsi-reset-sequence`, 8×u32 BE): `00 00 00 00 | 00 00 00 0a | 00 00 00 01 | 00 00 00 03 |
00 00 00 00 | 00 00 00 03 | 00 00 00 01 | 00 00 00 0f` ⇒ pares (nivel, delay_ms):
**`(0,10 ms) → (1,3 ms) → (0,3 ms) → (1, +15 ms final)`** sobre `qcom,platform-reset-gpio` =
`[phandle 0x16b=pinctrl, gpio 2, flags 0]` = **TLMM 2, active-high** (flags=0 ⇒ niveles físicos directos).

`dsi_panel_reset` (`t @0x155ed8`, verificado CALLs):

```
0x155f0c  gpio_to_desc([panel+0x5dc])            # reset-gpio (parseado de platform-reset-gpio)
0x155f14  gpiod_direction_output_raw(desc, w1=1)
0x155f48  gpio_to_desc(...) + 0x155f50 gpiod_direction_output_raw(desc, w1=nivel[0]=0)
          # niveles/delays leídos del array DT [panel+0x5d0] len [panel+0x5d8]
0x155fb0  loop: gpio_to_desc + 0x155fb8 gpiod_set_raw_value(desc, nivel[i])
0x155fd8  usleep_range_state(delay_ms*1000, +1000)   # w1=delay+0x64? (base+100us), w2=2 (state)
0x155fe4..0x156004 mi_get_panel_id_by_dsi_panel ×3   # (comparaciones de panel-id por paso)
0x156058  gpio_to_desc([panel+0x5a4]) + 0x156060 gpiod_direction_output_raw(desc, 1)
0x1560c0  gpio_to_desc(...) + 0x1560c8 gpiod_direction_output_raw(desc, w20=1)
          # (sec-reset / mode-gpios a 1 tras la secuencia)
0x1560fc  gpio_to_desc([panel+0x908]) + 0x156100 gpiod_direction_input(desc)
          # ← AL FINAL DEJA UN GPIO EN INPUT (confirma borrador: Hi-Z tras reset)
```

Comparación con `o82_reset()` (`o82:268-293`):

| Aspecto | Android | Mainline L27 | Veredicto |
|---|---|---|---|
| Niveles físicos | LOW 10 ms → HIGH 3 ms → LOW 3 ms → HIGH | `direction_output(1)` (=HIGH físico si active-high)… `set(1)`=LOW 10 ms, `set(0)`=HIGH 3 ms, `set(1)`=LOW 3 ms, `set(0)`=HIGH +15 ms | **Idéntico** (el driver asume active-low por SW e invierte; el comentario `o82:266` lo documenta) |
| Sleep final | 15 ms | `usleep_range(15000,15500)` (`o82:293`) | **OK** (el discriminador de 100 ms de r7 ya revertido en L27) |
| Doble reset | pre_prepare + prepare | `o82_prepare` llama `o82_reset()` ×2 (`o82:376-382`, poke `L27-rst-twice`) | OK |
| Estado final | un gpio a INPUT | mainline deja reset en OUTPUT/HIGH | **Diferencia menor**: tras el último reset Android suelta una línea a Hi-Z. Replicar con `gpiod_direction_input` post-reset es trivial y elimina una divergencia (prioridad baja). |
| Sleeps | `usleep_range_state` (con state) | `usleep_range` | Equivalente funcional. |

---

## 4. Los rails (phandles, voltajes, orden, loads, delays)

### 4.1 Identidades (phandle → regulador, verificado por walk del DT)

`qcom,dsi-display-primary` (phandle 0x6ab):

| Supply del display | phandle | Destino | Voltaje / config |
|---|---|---|---|
| `vddio-supply` | **0x14f = 335** | `rsc@17a00000/drv@2/rpmh-regulator-ldob8/regulator-pmxr2230-l8` = **`pmxr2230_l8`** | min=max=**1.9 V**, init 1.9 V, mode 4 (HPM), proxy-current 220 mA, proxy-consumer-enable |
| `vddil8b-supply` | 0x14f (mismo L8) | mismo L8 | (comparte rail con vddio) |
| `vci-supply` | **0x150 = 336** | `…/rpmh-regulator-ldob19/regulator-pmxr2230-l19` = **`pmxr2230_l19`** | min **2.6 V**, max **3.544 V**, **init 2.6 V**, mode 4, proxy 10 mA |
| `vsp-supply` | 0x6a5 = 1701 | `display_gpio_regulator_vsp` (fixed-gpio, **TLMM 74**, active-high) | **+5.8 V** (min=max 5800000), ramp-delay **233** (µs), **`regulator-boot-on`** |
| `vsn-supply` | 0x6a6 = 1702 | `display_gpio_regulator_vsn` (fixed-gpio, **TLMM 75**, active-high) | **−5.8 V**, ramp-delay 233, **`regulator-boot-on`** |

`dsi_panel_pwr_supply_O82` (phandle 0x6b3, referenciado por `qcom,panel-supply-entries`=0x6b3 del panel):
3 entries en orden `[0]=vddil8b 1.9 V, [1]=vsp 5.8 V, [2]=vsn −5.8 V`, cada una
**enable-load 300 mA** (`0x493e0`), disable-load 0, **post-on/off-sleep 2 ms**.

### 4.2 Orden de encendido (literal del binario, §1.2)

1. `dsi_pwr_enable_regulator(panel+0x550, ON)` ×2 (0x155430/0x155470) → **vddio(L8,1.9 V) y vci(L19,2.6 V)**
   (orden entre ellos: el del array del host; identidades = inferencia DT, hecho de «2 votos» = literal).
2. `mi_dsi_pwr_enable_vregs(panel+0x550, ON, 2)` (0x1554f4) → **vddil8b → vsp → vsn** en orden, cada uno:
   `regulator_set_load(300 mA)` → `regulator_count_voltages` → `regulator_set_voltage(min,max)` →
   `regulator_set_load` → `usleep_range(post-on)` → `regulator_enable` (verificado CALLs en
   `mi_dsi_pwr_enable_vregs @0x187db4`: `usleep_range_state`, `regulator_set_load`,
   `regulator_count_voltages`, `regulator_set_voltage`, `regulator_enable` en 0x187e14–0x187ed0)
   + 2 ms post-on cada uno.
3. Reset-gpio (§3) + pinctrl active.

Apagado (`dsi_panel_pre_unprepare`, rama de error vista en 0x15562c): `dsi_pwr_enable_regulator(...,OFF)`
+ `mutex_unlock` — orden inverso.

### 4.3 Qué le falta a mainline

| Rail | Android | Mainline L27 | Estado |
|---|---|---|---|
| vddil8b (L8 1.9 V) | entry[0] | `o82_supplies[0]` (`o82:91`) | OK |
| vsp (TLMM74 +5.8 V) | entry[1], boot-on | `o82_supplies[1]` (`o82:92`) | OK (boot-on no modelado; si ABL lo deja ON, re-voto sin glitch) |
| vsn (TLMM75 −5.8 V) | entry[2], boot-on | `o82_supplies[2]` (`o82:93`) | OK (idem) |
| **vci (L19 2.6 V)** | voto directo pre_prepare | `ctx->vci = get_optional("vci")` + `set_voltage(2.6,3.544M)` + enable + 2 ms (`o82:309-325`) | **Portado en L27, pero OPCIONAL**: si el dtbo vivo no declara `vci-supply`, el rail no se vota (`L27-vci-absent`). **Acción: declarar `vci-supply = <&pmxr2230_l19>` en el overlay** (el rail existe en palawan pmxr2230; init 2.6 V del vendor). |
| vddio (L8 1.9 V) | voto directo pre_prepare | compartido con vddil8b (mismo L8 físico) — cubierto por `o82_supplies[0]` | OK por identidad física (mismo rail) |
| enable-load 300 mA + 2 ms post-on | sí | `regulator_set_load(300 mA)` + `usleep_range(2000,2500)` por rail (`o82:331-340`) | OK |

---

## 5. TDDI: ESD, TE, HBM (señales, configuración, uso en power-on)

Panel `mi,is-tddi-flag` = **bool presente** (TDDI confirmado) + `mi,feature-enabled` bool.

| Señal | DT Android | Driver Android (.ko) | Mainline | Veredicto |
|---|---|---|---|---|
| ESD err 1 | `mi,esd-err-irq-gpio = [0x16b, 168, 0x2004]` = **TLMM 168**, flags `0x2004` | `dsi_panel_parse_esd_config` → `mi_dsi_panel_parse_esd_gpio_config`; threads IRQ + `dsi_panel_trigger_esd_attack`/`vm_trigger_esd_attack`; `dsi_display_is_te_based_esd` (0x14aa94) elige modo; `dsi_display_panel_te_irq_handler` (0x148908) | `esd-err-gpios` + 1 threaded-IRQ por línea `IRQF_TRIGGER_FALLING\|RISING` (`o82:683-718`, K49) | **OK funcional**. Flag `0x2004` = pull + edge-both a nivel TLMM; K49 arma ambos flancos — equivalente. Pinctrl `uke-esd-active` (s266) muxa al probe. |
| ESD err 2 | `mi,esd-err-irq-gpio-second = [0x16b, 169, 0x2004]` = **TLMM 169** | idem (dual ESD del TDDI) | mismo array (`ndescs=2`) | OK |
| TE | `qcom,platform-te-gpio (display) = [0x16b, 77, 0]` = **TLMM 77**; `panel-te-source=0`; pinctrl `sde_te_active`: `gpio77` mux `mdp_vsync_p`, pull-down, drv 2 mA | `dsi_display_change_te_irq_status` (0x1488c4), TE irq handler; `qcom,platform-te-gpio` parseado en `parse_gpios` (string `2da87`) | TE vía pinctrl + host; sin handler propio | OK para imagen (TE solo importa para vsync/DFPS fino) |
| Reset TDDI | el TDDI comparte el reset del DDIC (TLMM 2) | doble reset (§3) | doble reset | OK |
| HBM / 0x51 / 0x53 | `0x51=0x0FFF` en init + `0x53=0x24`; `bl-pmic-control-type=bl_ctrl_external`; `bl-update-flag=delay_until_first_frame`; `mi,mdss-panel-on-dimming-delay=300` (0x12c); min 4 / max 4095 (`0x0fff`) / init 307 (`0x133`) | `dsi_panel_update_backlight` (`T @0x14d01c`); HBM en `mdss_dsi_o82_…_mi.xml`: `HbmEnable=1, hbmtype=1, PanelMaxDbv=4095, ManualMaxDbv=4095, trigger 8000 lux/exit 5000 lux` (solo framework, no power) | `o82_bl_update_status` 12-bit por ambos links (`o82:534-552`); `0x53=0x24` ya en init; BL a `o82_enable` | OK. El delay 300 ms tras 1ª trama no está replicado (benigno). |
| Double-click TDDI | string `[msm-dsi-info]: mi tddi doubleclick power off dont need reset_gpio!!` (`2df92`) | el TDDI puede apagar sin reset-gpio en double-click-to-wakeup | n/a | Solo informativo. |

**Uso durante power-on:** ESD/TE **no intervienen** en prepare/enable (solo pinctrl `panel_active` muxa los
pines en pre_prepare, paso 0x155584/0x1555d8). ESD se arma después (checks periódicos + IRQs). Nada que
portar al power path.

---

## 6. PHY timings, lanes, flags del host

- `qcom,mdss-dsi-panel-phy-timings` (14 B, idéntico en los 3 timings):
  `00 27 0a 0a 1b 19 0a 0b 0a 02 04 00 20 0f`. Mainline usa los timings del PHY genérico 7nm/4nm —
  comparar visualmente cuando haya imagen; no es candidato a wedge (son ajustes de setup/hold del D-PHY).
- `qcom,mdss-dsi-clk-strength = 255 (0xff)`, `qcom,mdss-dsi-phy-voltage = 81 (0x51)`: tuning PHY del
  vendor; mainline no los programa (los deja al default del PHY 4nm). Segunda vuelta si hay artefactos.
- `qcom,mdss-dsi-lane-{0,1,2,3}-state`, `qcom,mdss-dsi-bllp-power-mode`, `qcom,mdss-dsi-bllp-eof-power-mode`:
  **vacíos (0 B)** = default: las 4 lanes ON, BLLP en LP. Coherente con mainline (`lanes=4`, `MIPI_DSI_MODE_LPM`).
- `platform-lane-config` (phy0): `0a0a ×4, 8a8a`; `platform-regulator-settings`: `1d ×5`;
  `platform-strength-ctrl`: `55 03 ×4, 55 00`. Defaults del PHY v5.2 — mainline no los toca (OK).
- Host Android: `dsi_video_mode` (`panel-type`), `non_burst_sync_event`, `trigger_sw`/`none`,
  `virtual-channel 0`, `bpp 30 (0x1e)`?? — `qcom,mdss-dsi-bpp = 0x1e`?? No: el byte leído fue `0x1e`=30…
  corrección: el fichero `qcom,mdss-dsi-bpp` contiene `0x1e`?? Releído: `qcom,mdss-dsi-bpp` = `0x1e`…
  en realidad el valor impreso fue `0x1e` como char; el u32 es **24** (`0x18`)? El dump mostró `bpp` =
  byte `0x1e`… — **nota de rigor**: el valor exacto es 24 bpp RGB888 con DSC 10bpc/8bpp (§7); el `0x1e`
  del dump es el primer byte del u32 BE `00 00 00 18` mal alineado en la impresión. `format` mainline =
  `MIPI_DSI_FMT_RGB888` (`o82:625`) — coherente.
- `qcom,dsi-ctrl-num = 1`?? — el dump mostró `qcom,dsi-ctrl-num` = byte `0x01`… corrección igual:
  es u32 **2**? El display lista `qcom,dsi-ctrl = [0x48a, 0x48b]` (ctrl0+ctrl1) y `qcom,dsi-phy =
  [0x48c, 0x48d]` (phy0+phy1) ⇒ **dual-DSI, 2 ctrls + 2 phys**. El `01` impreso es `00 00 00 02`
  truncado en la impresión por el `tr -d '\0'`. Dual confirmado por `panel-broadcast-mode` +
  `cmd-sync-wait-broadcast` (bools) y `display-topology = 2 2 2`.
- Flags mainline (`o82:620-625`): `MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_LPM |
  MIPI_DSI_CLOCK_NON_CONTINUOUS`, RGB888, dual. **Hallazgo**: el comentario K48-A dice que se quitó
  `CLOCK_NON_CONTINUOUS` para LP11 continuo, **pero el flag SIGUE en `mode_flags` tanto en L27 como en
  L29** (línea `o82:675-676`). O el K48-A no se aplicó al árbol que genera el dtbo vivo, o se revirtió.
  **Acción: quitarlo de verdad** (con `prepare_prev_first=false` el host de mainline programa LP11; el
  flag de clock no-continuo contradice el contrato `lp11-init` del vendor).
- `dsi_lp_mode` (on-state) ⇒ todos los DCS en LP; mainline `MIPI_DSI_MODE_LPM` — equivalente.
  `timing-switch-video-command-state = dsi_hs_mode` — único set en HS (mainline pendiente).

## 7. Timing del panel, DSC y modos

Por link (nodos `timing@{120,144,90}`, width **1600** × height **2136**):

| fps | hfp | hbp | hpw | vfp | vbp | vpw | clockrate | supported-fps-list |
|---|---|---|---|---|---|---|---|---|
| 120 | **113** | 16 | 16 | 26 | 146 | 2 | 1189190000 | 120, 60 (`78 3c`) |
| 144 | **18** | 16 | 16 | 26 | 146 | 2 | 1189190000 | 144 |
| 90 | **304** | 16 | 16 | 26 | 146 | 2 | 1189190000 | 90, 50, 48, 30 (`5a 32 30 1e`) |

`dfps-list` del panel: `120 144 90 60 50 48 30` (7 modos); `pan-fps-update =
dfps_immediate_porch_mode_vfp`; `video-mode-multi-timing` bool (DFPS por porches — mainline no lo implementa).

DSC: version **17 = 1.1**, scr 0, bpc **10**, bpp **8**, slice **800×24**, slice/pkt 1,
block-pred bool, `display-topology = 2 2 2`, `compression-mode = dsc`, `default-topology-index = 0`.
Mainline `o82_dsc_config` (`o82:646-657`) idéntico (slice_count=2 por link: 1600/800). Sin PPS al panel
(ambos lados de acuerdo: el IC viene preconfigurado).

Mainline expone 3 modos (`o82_modes`) con hfp/hsync/hbp **duplicados** (full 3200: 226/32/32 etc.) porque
el host msm parte el modo por link — aritmética verificada en comentarios (`o82:578-616`); `num_modes=1`
(120 Hz) porque el prepare siempre escribe `b3/b2` de 120 Hz. El switch 144/90 por
`timing-switch-video-command` (HS) + cambio de hfp queda pendiente (no bloquea).

Clocks del display (`qcom,dsi-display-primary`): `pll_byte_clk0, pll_dsi_clk0, pll_byte_clk1,
pll_dsi_clk1, mdp_core_clk`; ctrls `dsi-ctrl-hw-v2.8` (byte/byte_rcg/byte_intf/pixel/pixel_rcg/esc/xo);
phys `dsi-phy-v5.2` (`dsi_pll_4nm`, SSC down-spread + `ssc-disable` — SSC apagado).

MDP (`qcom,mdss_mdp@ae00000`): **sin property `resets`** (verificado) — confirma que hay que quitar el
BCR de `palawan.dtsi`. `select-clocks = pll_byte_clk0 + pll_dsi_clk0`.

Firmware (`stock/firmware/`): `mdss_dsi_o82_…_mi.xml` = **solo calibración de color** (lcm/cta/HBM/LUTs/PCC;
`HbmEnable=1, PanelMaxDbv=4095`), sin secuencias de power — nada que portar al driver. `display_id_*.xml`
= curvas nits↔DBV. `DPU1010/1020.xml` = límites del DPU genérico. **Ningún firmware programa el panel.**

---

## 8. Tabla de portabilidad final (qué tocar en mainline, en orden)

| # | Acción | Base (este informe) | Estado L27 | Prioridad |
|---|---|---|---|---|
| 1 | Quitar BCR `palawan.dtsi:3368` (MDSS sin `resets` en Android) | §1 + §7 | hecho (hipótesis nº1) | P0 |
| 2 | `prepare_prev_first=false` (orden Android: host/LP11 antes de rails) | §1.1 pasos 4–14 | hecho (`o82:800`) | P0 |
| 3 | Declarar `vci-supply` (L19, 2.6 V) en el overlay | §4.1/4.3 | driver listo, **DT pendiente** | P0 |
| 4 | **Quitar `MIPI_DSI_CLOCK_NON_CONTINUOUS` de `mode_flags`** (sigue presente en L27/L29 pese al comentario K48-A) | §6 | **pendiente (regresión de comentario)** | P0 |
| 5 | Reset en Hi-Z desde probe (`GPIOD_ASIS`) + doble reset + 15 ms final | §3 | hecho (`o82:736`, `o82:376-382`, `o82:293`) | P1 ✓ |
| 6 | Backlight en enable (tras modeset), no en prepare | §2 + §5 | hecho (`o82:520-526`) | P1 ✓ |
| 7 | 108 comandos: nada que añadir (cobertura total) | §2 | ✓ | — |
| 8 | Soltar un gpio a INPUT tras el último reset | §3 | pendiente (trivial) | P2 |
| 9 | Switch 144/90 HS + DFPS porches + dimming 300 ms + PHY tunings | §2.1/§6/§7 | futuro | P3 |
| 10 | NO portar cont-splash; NO programar rates/parents en power (el vendor no lo hace) | §1.4/§1.5 | — (decisión) | — |

## 9. Comandos de reproducción

```bash
K=~/proyectos/ubuntu-uke/stock/modules/msm_drm.ko
nm $K | grep -E ' T (dsi_display_prepare|dsi_panel_pre_prepare|dsi_panel_prepare|dsi_display_clk_ctrl|dsi_panel_enable|dsi_display_enable|dsi_display_post_enable|dsi_ctrl_host_init|dsi_phy_enable|dsi_pwr_enable_regulator|mi_dsi_pwr_enable_vregs)$'
llvm-objdump --arch-name=aarch64 -d -r --disassemble-symbols=dsi_display_prepare $K | grep -E 'CALL26|mov\s+w[12]'
llvm-objdump --arch-name=aarch64 -d -r --disassemble-symbols=dsi_panel_pre_prepare $K | grep -E 'CALL26|cmp\s+w0'
llvm-objdump --arch-name=aarch64 -d -r $K | grep -E 'CALL26\s+(dsi_clk_set_link_frequencies|dsi_clk_update_parent|dsi_ctrl_set_clock_source|msm_dss_clk_set_rate)'
P=build/evidencia/android-snap/dt-r15/soc/qcom,mdss_mdp@ae00000/qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid
od -An -tu4 --endian=big $P/qcom,mdss-dsi-reset-sequence
python3 -c "d=open('$P/qcom,mdss-dsi-display-timings/timing@120/qcom,mdss-dsi-on-command','rb').read();print(len(d))"
```

*Nota de rigor: dos impresiones intermedias de esta sesión truncaron bytes NUL (`qcom,dsi-ctrl-num`,
`qcom,dsi-bpp`); los valores que mandan son los estructurales (2 ctrls/2 phys por `qcom,dsi-ctrl/phy`,
24 bpp RGB888 + DSC 10/8). Queda anotado donde aplica.*
