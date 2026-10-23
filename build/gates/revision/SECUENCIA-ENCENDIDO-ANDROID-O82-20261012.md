# Secuencia real de encendido del panel O82 en Android — 12-oct-2026

> Fuente primaria: `~/proyectos/ubuntu-uke/stock/modules/msm_drm.ko` (ELF aarch64, **no stripped**,
> BuildID `9a06914a…`, 21891 símbolos), desensamblado con `llvm-objdump --arch-name=aarch64`
> + resolución de `R_AARCH64_CALL26` a símbolo.
> Corroboración: DT real de Android `build/evidencia/android-snap/dt-r15/` y esqueleto CAF público
> `techpack/display/msm/dsi/{dsi_panel.c,dsi_display.c}` (mirror samsung_sm8250, lineage-23.0,
> copiado a `/tmp/opencode/caf_dsi_{panel,display}.c`).
> Rama vendor correcta: **`uke-v-oss`** (`5712080a`, "Xiaomi Pad 7 Android V") — el stack DSI/display
> **NO está en ese repo** (solo queda el `dsi/` antiguo + `msm_mdss.c`); vive en el repo separado
> `vendor/qcom/opensource/display-drivers` (techpack), que Xiaomi no publica. De ahí que el `.ko`
> sea la única fuente exacta del comportamiento uke.

## A. Secuencia de encendido de Android (pseudocódigo)

Orden medido en `dsi_display_prepare` (`.ko:0x145224`, ~0x86c bytes), rama feliz
(error-paths omitidos), con referencias CAF:

```
dsi_display_prepare()                                   # caf_dsi_display.c:7444
 1. mutex_lock(display_lock)
 2. dsi_ctrl_clk_cb_register() x2  +  dsi_phy_clk_cb_register()   # .ko 0x1452d4/0x145338/0x1454ec
 3. dsi_ctrl_isr_configure(ctrl0, ON); dsi_ctrl_isr_configure(ctrl1, ON)  # ¡ISRs ANTES que clocks!
 4. dsi_display_clk_ctrl(DSI_CORE_CLK=1, ON=1)           # .ko 0x145450 (w1=1,w2=1)
 5. dsi_display_phy_sw_reset()                           # .ko 0x1454a8
 6. dsi_display_clk_ctrl(DSI_CORE_CLK, ON)               # .ko 0x14550c (segundo voto core)
 7. dsi_display_phy_enable() → dsi_phy_enable() x2 DONDE phy0+phy1  # .ko 0x145540
       → lanes en LP11 (stop state), NADA en HS todavía
 8. dsi_ctrl_update_host_state() + dsi_ctrl_host_init()  # .ko 0x1455a4/0x1455ec
 9. dsi_panel_pre_prepare()  ← RAILS + RESET + PINCTRL (ver A.1)   # .ko 0x145628
10. dsi_ctrl_host_timing_update() + dsi_ctrl_host_init() (2º ctrl) # .ko 0x145658/0x1456c4
11. dsi_ctrl_set_host_engine_state() x4 (cmd+vid engines de ambos ctrls)
12. dsi_display_clk_ctrl(DSI_LINK_CLK=2, ON=1)            # .ko 0x145990 (w1=2,w2=1)
13. dsi_display_soft_reset()                              # .ko 0x145c20
14. dsi_panel_prepare() → dsi_panel_reset() + tx(PRE_ON=vacío)     # .ko 0x145c6c
    mutex_unlock()
    # NOTE CAF clásico (caf_dsi_display.c:7520-7590) llama a pre_prepare ANTES del CORE_CLK;
    # el árbol uke lo movió a DESPUÉS de phy_enable+host_init (0x145628). El efecto neto es el
    # mismo exigido por LP11_INIT: rails+reset ocurren con los lanes ya en LP11.

dsi_display_enable()  (.ko 0x146e90; cf. caf_dsi_display.c:7927)
15. cont-splash check: si splash vivo → dsi_display_config_ctrl_for_cont_splash() y SALTA todo
16. lecturas mi_ (build-id, peak-hdr-gamma) — diagnóstico, no tocan el panel
17. dsi_panel_tx_cmd_set(panel, 190)  # tipo 190 = "mi,mdss-dsi-fps-90-gamma-command"
       → AUSENTE en el DT del o82 ⇒ count=0 ⇒ no-op. (Resuelto vía tabla cmd_set_prop_map,
         `.data:0x8ee0`, entrada = type*8 → string. Tipos 0..6 = pre_on/on/vid-on/cmd-on/
         post-on/pre-off/off; límite superior 0x106 = 262 tipos por el `cmp w1,#0x106` en
         dsi_panel_tx_cmd_set (.ko 0x14ce94) y en dsi_panel_parse_cmd_sets_sub (.ko 0x14e964).)
18. dsi_panel_enable() → dsi_panel_tx_cmd_set(panel, ON=1): **los 108 comandos** (ver A.3),
    en LP (on-state = "dsi_lp_mode"), terminando en 0x11 +120 ms y 0x29.
    + extras mi_ (round-corner, gamma, csc, dc, dbi — todos ausentes en DT del o82 ⇒ no-ops).
19. dsi_panel_update_pps() — PPS de DSC (calculado, no va al panel; el IC ya está preconfigurado).
20. dsi_display_vid_engine_enable() — arranca el stream de vídeo.

dsi_display_post_enable()  (.ko 0x1476a8)
21. dsi_panel_post_enable() → tx(POST_ON=4, vacío) + tx(244, mi_, vacío)
22. switch a video-mode + mi_dsi_panel_set_gamma_update_state()

Backlight: NO va en prepare/enable. `qcom,bl-update-flag = "delay_until_first_frame"`
    + `mi,mdss-panel-on-dimming-delay = 300` ⇒ el 0x51 sale tras la 1ª trama + 300 ms,
    vía el path atómico del sde_encoder (dsi_panel_set_backlight ← bl_ctrl_external, 12 bit).
```

### A.1 `dsi_panel_pre_prepare` = rails + reset + pinctrl (`.ko:0x1553e8`)

Equivale a `dsi_panel_power_on()` del CAF (`caf_dsi_panel.c:459`: vregs → pinctrl → reset),
pero Xiaomi lo inlinó y lo condicionó por panel-id (comparaciones con 0x16/0x18/0x17 tras
`mi_get_panel_id_by_dsi_panel`, `.ko 0x1554a0-0x1554cc`):

```
  dsi_pwr_enable_regulator(vddio = L8 pmxr2230, ON)      # .ko 0x155430 (x0=panel+0x550)
  dsi_pwr_enable_regulator(vci   = L19 pmxr2230, ON)     # .ko 0x155470
      (identidades inferidas del DT: el nodo display declara vddio-supply=0x14f=L8,
       vci-supply=0x150=L19; ver tabla de rails abajo. No resoluble al 100% por
       desensamblado estático — marcado como INFERENCIA.)
  mi_dsi_pwr_enable_vregs() → las 3 panel-supply-entries, en orden:   # .ko 0x1554f4
      [0] vddil8b = L8,  1.9 V (0x1cfde0), enable-load 300 mA (0x493e0), post-on/off 2 ms
      [1] vsp     = TLMM74, +5.8 V (0x588040), enable-load 300 mA, post 2 ms
      [2] vsn     = TLMM75, −5.8 V (0x588040), enable-load 300 mA, post 2 ms
  dsi_panel_reset() → secuencia DT qcom,mdss-dsi-reset-sequence:     # .ko 0x155514→0x155ed8
      nivel 0 × 10 ms → nivel 1 × 3 ms → nivel 0 × 3 ms → nivel 1 (suelta, +15 ms)
      sobre qcom,platform-reset-gpio = TLMM 2, flags 0 (= active-high ⇒ nivel físico LOW/HIGH
      directos; el driver usa gpiod_direction_output_raw + gpiod_set_raw_value +
      usleep_range_state; al final deja el gpio en INPUT, .ko 0x156100)
  gpio_set(TE/HBM, 0) x2 + pinctrl_select_state(panel_active) x2      # .ko 0x15554c-0x1555d8
      (mux TLMM: reset 2, TE 77, ESD 168/169; estados panel_active/panel_suspend del nodo display)
```

**Punto clave para mainline**: rails+reset ocurren con **PHY ya en LP11 + host inicializado +
link clocks a punto de encenderse (paso 12)**. El panel NUNCA ve sus rails subir con los lanes
en ULPS/reset, y el reset corre con relojes DSI vivos. `qcom,mdss-dsi-lp11-init` (presente,
booleano) es la declaración de este contrato.

### A.2 `dsi_panel_prepare` (`.ko:0x155e10`) — reset + PRE_ON vacío

```
mutex_lock(panel_lock); dsi_panel_reset();               # 2º reset (!)
if (panel_initialized_flag (+0x828)) dsi_panel_tx_cmd_set(panel, PRE_ON=0);
      # "qcom,mdss-dsi-pre-on-command" NO existe en el DT del o82 ⇒ no-op
mutex_unlock()
```
O sea: el prepare de Android **re-asevera el reset y (para este panel) no manda ningún DCS**.
Toda la init DCS va en el paso 18 (enable). El doble reset (pre_prepare + prepare) es literal
del binario, no una suposición.

### A.3 Los 108 comandos: contenido verificado byte a byte

`timing@120/qcom,mdss-dsi-on-command` = **998 bytes = 108 registros** (cabecera 7 B:
`dt,flags[3],wait_ms,len_be16`; todos `dt=0x39`), `on-command-state = "dsi_lp_mode"`:

- #0..103: init genérico (páginas ff 27/23/25/2a/26/22/f0/20/10, gammas, 0x51=0x0fff,
  0x53=0x24, 0x3b, 0x90/0x91/0x92/0x9d = bloque DSC/PPS-ish del vendor…).
- #104/105: `b3 40`, `b2 91` (timing-select 120 Hz).
- **#106: `0x11` (sleep-out) con wait 120 ms — el ÚNICO wait no-cero del blob.**
- **#107: `0x29` (display-on), wait 0.**
- Registros `0x11`/`0x29` intermedios (#19 `11 03`, #23 `29 0a`) son escrituras a paginas
  del vendor (prefijados ff/fb), no los DCS reales.

`off-command` (24 B, `off-state = "dsi_lp_mode"`): `0x28` +20 ms, `0x10` +100 ms, `0x4f`.
`timing-switch-video-command` (36 B, **`dsi_hs_mode`** — el único set en HS):
`ff 10, fb 01, b2 {91|00|00}, b3 {40|00|80}` según timing.

Timings (por link; el host uke parte el modo entre los 2 ctrls):
`timing@{120,144,90}/`: width **1600** height 2136, hfp **113/18/304**, hbp 16, hpw 16,
vfp 26, vbp 146, vpw 2, borders/skew 0, `panel-clockrate = 1189190000` (igual en los 3),
dfps-list del panel = `120 144 90 60 50 48 30` (7 modos; solo 120/144/90 tienen nodo timing).
DSC: version 17 (=1.1), scr 0, bpc 10, bpp 8, slice 800x24, 1 slice/pkt, block-pred = true,
`display-topology = 2 2 2`, `compression-mode = "dsc1"`, `default-topology-index = 0`.
PHY timings (`panel-phy-timings`, 14 B): `00 27 0a 0a 1b 19 0a 0b 0a 02 04 00 20 0f`.
Backlight: min 4, max 4095, init 307 (0x133), `bl-pmic-control-type = bl_ctrl_external`.

### A.4 Splash handoff (cont_splash) — qué se salta Android

- `dsi_display_cont_splash_config` (`.ko:0x13f720`): `pm_runtime_resume` + `isr_configure` x2 +
  `clk_ctrl` + `clk_mngr_update_splash_status`. **Ni reset de PHY/host, ni reguladores, ni
  reset-gpio, ni un solo DCS.** Solo toma posesión de clocks/ISRs y marca el splash.
- `sde_kms_cont_splash_config` (`.ko:0x9967b4`): mapea la memoria del splash del ABL
  (`_sde_kms_splash_mem_get`), iguala el modo DRM al heredado y marca
  `sde_encoder/crtc_update_cont_splash_settings`.
- En `dsi_display_prepare`, si `is_cont_splash_enabled`: se saltan `pre_prepare`,
  `soft_reset` y `panel_prepare` (`caf_dsi_display.c:7505-7512, 7571-7592`: *"skip panel pre
  prepare since the regulator vote is already taken care in splash resource init"*).
- Selección del panel: cmdline `msm_drm.dsi_display0=qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid:`.
- El nodo `qcom,mdss_mdp@ae00000` de Android **NO declara `resets`** (verificado: ninguna
  property `reset*`; solo clocks/interconnects/sde-reg-*). Mainline `palawan.dtsi:3368` sí
  (`resets = <&dispcc DISP_CC_MDSS_CORE_BCR>`), ejecutado incondicionalmente en
  `msm_mdss_init` (`msm_mdss.c:309-333`: assert + msleep(20) + deassert).

## B. Comparación con `panel-xiaomi-o82-dualdsi.c` (mainline)

| # | Aspecto | Android (medido) | Mainline actual | Veredicto |
|---|---|---|---|---|
| 1 | Clocks/PHY/host antes de rails | CORE_CLK→PHY(LP11)→host→LINK_CLK y **después** rails+reset (A pasos 4-9) | `o82_prepare`: rails→reset→DCS **sin tocar un solo clock**; con `prepare_prev_first=true` (:741) el prepare corre **antes** del pre_enable del host DSI ⇒ orden **invertido** respecto a Android | **DIFERENCIA ESTRUCTURAL nº1** |
| 2 | Reset en el probe | Nada: el gpio solo se maneja en power_on; antes manda el estado del ABL | `o82_probe` (:665) pide `GPIOD_OUT_HIGH` + ¿active-low? ⇒ **panel en reset físico desde ~0,55 s** hasta el prepare (coherente con F1: `gpio2 = out low`) | Diferencia: mainline mantiene el panel reseteado todo el boot |
| 3 | Polaridad del reset | `platform-reset-gpio` flags=0 (active-high); secuencia `0/10,1/3,0/3,1/15` ms físicos | Comentario :260-263 asume active-low e invierte por software; resultado físico idéntico (LOW 10 ms…) **salvo el sleep final**: 100 ms vs 15 ms del vendor | OK en niveles; **final 100 ms vs 15 ms** (el r7 lo alargó a propósito como discriminador — revertir a 15 al portar) |
| 4 | Doble reset | reset en pre_prepare **y** en prepare (literal del binario) | Un solo reset | Menor; replicar es trivial (reset dos veces con sus sleeps) |
| 5 | Rail `vci` (L19, 2,6-3,5 V) | Votado en pre_prepare (`vci-supply=0x150` = `pmxr2230_l19`, init 2,6 V) | **No existe**: el driver solo pide vddil8b/vsp/vsn (:86-90) | **Hueco**: si el ABL no lo deja ON, el DDIC-analógico queda sin alimentación |
| 6 | Contenido init DCS | 108 cmds, LP, con 0x11+120 ms y 0x29 al final | Blob :99-181 = cmds #0..103 (964 B) + cola b3/b2/0x11/0x29 (:367-383) ⇒ **contenido idéntico, sin duplicados** (verificado: 998−34=964) | **OK, transcripción fiel** |
| 7 | Dónde van los DCS | Prepare ≈ vacío; los 108 cmds van en **enable** (paso 18), con host+video ya configurados | Todo en `prepare`, antes del modeset/vid-engine | Diferencia de fase: en mainline los DCS salen sin stream configurado (suele funcionar en LP, pero no es lo del vendor) |
| 8 | Backlight 0x51 | Tras 1ª trama + 300 ms (`delay_until_first_frame` + on-dimming 300) | `backlight_enable()` al final del prepare (:391), **pre-video** | Diferencia; benigna en la práctica pero moverla tras modeset acerca al vendor |
| 9 | OFF | 0x28+20, 0x10+100, 0x4f, LP | Idéntico (:415-430) | OK |
| 10 | Broadcast dual-DSI | `panel-broadcast-mode` + `cmd-sync-wait-broadcast` | `mipi_dsi_dual_dcs_write_buffer_multi` a ambos | Equivalente |
| 11 | Pinctrl | `pinctrl_select_state(panel_active)` en power_on; `panel-te-gpio` = TLMM 77 | El driver no toca pinctrl (depende del estado por defecto + s266 esd-active) | Revisar que reset/TE/ESD queden muxados antes del prepare |
| 12 | LP11 durante reset | Garantizado por diseño (pasos 7→9) + `lp11-init` | Parche K48-A (`CLOCK_NON_CONTINUOUS` quitado, :620-621) intenta lo mismo pero **sin evidencia de que el host esté en LP11 durante el prepare** (nunca hubo prepare real) | El orden del punto 1 es lo que lo garantiza, no solo el flag |
| 13 | ESD | `mi,esd-err-irq-gpio` = TLMM **168/169**, flags 0x2004 | Portado como esd-err-gpios + IRQs (:673-704) | OK (verificar flags/pull del 0x2004 = pull-up + thread?) |
| 14 | Freq-select por timing | ON trae b3/b2 del timing; switch posterior por `timing-switch-video-command` en **HS** | Solo 120 Hz (`num_modes=1`, :608), switch pendiente | OK como fase 1; el switch HS+N hfp es trabajo futuro (ya identificado en el driver) |

## C. Propiedades del DT de Android que mainline ignora (candidatas)

Nodo panel: `soc/qcom,mdss_mdp@ae00000/qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid/` (+`timing@{120,144,90}/`):

1. **`qcom,mdss-dsi-lp11-init`** (bool) — el contrato "lanes en LP11 durante power_on". Mainline
   lo aproxima con el flag de modo, pero sin el ORDEN del §A no se cumple.
2. **`qcom,platform-reset-gpio` + `qcom,mdss-dsi-reset-sequence`** — mainline los replica en
   código (:264-287), OK, salvo el sleep final (15 vs 100).
3. **`vci-supply` (L19)** del nodo display — sin equivalente mainline (§B.5).
4. **`qcom,mdss-dsi-panel-phy-timings`** (`00 27 0a 0a 1b 19 0a 0b 0a 02 04 00 20 0f`) — mainline
   usa los timings del PHY genérico 7nm; comparar cuando haya imagen.
5. **`qcom,mdss-dsi-clk-strength = 255`, `qcom,mdss-dsi-phy-voltage = 81`** — tuning del PHY.
6. **`qcom,mdss-dsi-display-timings` completos** (porches por fps + clockrate 1189190000) —
   mainline los transcribió a mano (:538-575); cotejar hfp×2 (el split por link) contra sheng.
7. **`qcom,mdss-dsi-timing-switch-video-command`** (HS) — sin equivalente (futuro).
8. **`qcom,dsi-supported-dfps-list` / `mi,video-mode-multi-timing`** — DFPS no implementado.
9. **`qcom,bl-update-flag`, `mi,mdss-panel-on-dimming-delay=300`** — backlight diferido (§B.8).
10. **`qcom,mdss-dsi-bllp-{eof-,}power-mode`, `qcom,mdss-dsi-{lane-0..3-state}`** (todos presentes
    vacíos = lanes ON, BLLP en LP) — coherentes con el modo mainline actual.
11. **`qcom,cmd-sync-wait-broadcast/trigger`** — el host mainline no hace broadcast real; el dual-write
    actual es equivalente funcional.
12. **`mi,panel-id = 01 22 e7 00 00 00 04 71`** (+`mi,mdss-dsi-fac-*`, build-id/wp-read cmds) —
    solo diagnóstico/gamma Xiaomi; no needed para imagen.
13. A nivel SoC: **`qcom,mdss_mdp` sin `resets`** (ya recogido en ESTADO-VIVO) y
    `display_gpio_regulator_{vsp,vsn}` con **`regulator-boot-on`** + ramp-delay 233 —
    mainline los modela como fixed-gpio sin boot-on: si el ABL los deja ON, el prepare de
    mainline los re-vota sin glitch; si los deja OFF, el enable los levanta (verificar orden
    vsp→vsn y los 2 ms post-on, ya en :311).

## D. Comandos usados (reproducible)

```bash
K=~/proyectos/ubuntu-uke/stock/modules/msm_drm.ko
nm $K | wc -l                                     # 21891 (no stripped)
nm $K | grep -E ' T ' | grep -i dsi_panel | head # prepare/pre_prepare/enable/...
nm $K | grep -i splash                            # cont_splash_config, sde_kms_cont_splash_config…
llvm-objdump --arch-name=aarch64 -d -r --disassemble-symbols=dsi_display_prepare $K
python3 /tmp/opencode/callseq.py dsi_display_prepare   # lista CALL en orden (script: umaddl→entry*24,
python3 /tmp/opencode/callseq.py dsi_panel_pre_prepare #  + resolución .text+N a símbolo vía nm)
python3 /tmp/opencode/callseq.py dsi_panel_prepare
python3 /tmp/opencode/propmap.py                     # cmd_set_prop_map (.data:0x8ee0): tipo→property
strings -a $K | grep -E 'mdss-dsi-.*command' | sort -u # qué command-sets parsea el driver
# DT (cada property = fichero; u32 = big-endian → od --endian=big):
P=build/evidencia/android-snap/dt-r15/soc/qcom,mdss_mdp@ae00000/qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid
od -An -tu4 --endian=big $P/qcom,mdss-dsi-reset-sequence   # 0 10 1 3 0 3 1 15
od -An -tx1 $P/qcom,mdss-dsi-display-timings/timing@120/qcom,mdss-dsi-on-command | wc
python3 -c '...'  # parseo cabeceras 7B del on-command: 108 cmds, #106=0x11+120ms, #107=0x29
git ls-remote --heads https://github.com/xiaomi-uke-dev/opensource_xiaomi_uke-kernel | grep uke
# → uke-v-oss; el stack display NO está ahí (solo dsi/ antiguo): techpack separado, no publicado.
```

## E. Conclusión: ¿es portable sin el KMD?

**Sí, el orden y los timings son portables; no hace falta nada del KMD salvo lo que ya se sabía.**
Concretamente, por orden de ejecución en mainline (fase F5):

1. **Quitar el BCR de `palawan.dtsi:3368`** (o gatearlo): Android demuestra que el MDSS nunca se
   resetea en el boot; el reset es exclusivo de mainline y cae en plena ventana del splash
   (~0,4-0,5 s). Sin esto nada más importa. (Ya es la hipótesis nº1; este informe la eleva a
   **divergencia confirmada contra el vendor**, no solo sospecha por timing.)
2. **Añadir el rail `vci` (L19, 2,6 V)** al DT/overlay del panel o como supply del host, con su
   init-voltage. Es el único voto de potencia que mainline pierde respecto a Android.
3. **No mantener el reset asertado desde el probe**: pedir el gpio sin `GPIOD_OUT_HIGH`
   (dejarlo en Hi-Z/input hasta el prepare, como hace Android) o replicar el estado ABL.
   Hoy el panel pasa ~4 s en reset antes de cada prepare.
4. **Reordenar el prepare hacia el orden Android**: con `prepare_prev_first=true` el DCS sale
   antes de que el host programe LP11/clocks. Opciones: (a) quitar `prepare_prev_first` para
   que el prepare corra tras el pre_enable del host (los DCS ya funcionan en LP — L19 lo
   demostró con el 0x51); (b) mejor: mover rails+reset a `prepare` tardío no es posible en el
   modelo DRM — lo realista es (a) + verificar por traza que el host ya dejó LP11 antes del
   primer DCS. El K48-A (quitar `CLOCK_NON_CONTINUOUS`) va en la dirección correcta pero es
   insuficiente sin (a).
5. **Detalles de fidelidad** (segunda vuelta): sleep final 15 ms (revertir r7), doble reset,
   backlight tras primera trama (o al menos tras modeset), pinctrl active explícito.
6. **Cont_splash**: NO portar. Es gestión de memoria del splash del ABL +.takeover de recursos;
   en mainline el objetivo F5 es modeset propio desde cero, y el BCR quitado ya deja el
   hardware en un estado equivalente al que el KMD espera encontrar (clocks del ABL vivos +
   `clk_ignore_unused`). Si el modeset propio reprograma todo (PLL/PHY/host desde reset
   controlado), el handoff es innecesario.

**Qué NO se pudo determinar** (explícito): (i) la identidad exacta de los dos
`dsi_pwr_enable_regulator` de pre_prepare (vddio/vci es inferencia por el DT, no por símbolo;
los nombres de regulador viajan en DT, no en el binario); (ii) el tipo-244 de post_enable
(set mi_ sin property en este DT ⇒ no-op igualmente); (iii) si el ABL deja `vci`/L19 ON
(solo medible en vivo: `regulator_summary` tras quitar `:d`); (iv) el significado de los
bytes de estado +0x978/+0x828 del struct uke (lp11/power flags presuntos por posición).

**Riesgo principal del port**: el punto B.1. Si al quitar el BCR el SoC sigue muriendo con el
prepare real (fenómeno B del plan), el siguiente sospechoso con nombre y apellidos tras este
análisis es el **clobber del RCG compartido** (H-2, ya apoyada en F1: `mdp_clk_src: rcg didn't
update…`), no el panel. El panel, por su parte, ya no tiene secretos: rails, reset, 108
comandos y timings están todos sobre la mesa.
