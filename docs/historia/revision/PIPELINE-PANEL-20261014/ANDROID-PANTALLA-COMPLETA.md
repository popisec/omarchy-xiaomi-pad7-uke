# ANDROID pantalla completa (vendor o82 CSOT) — referencia para cazar la pantalla negra

> Solo lectura, 14-oct-2026. MEDIDO = fichero:línea o comando+salida. HIPÓTESIS = marcada.
> Unidad CSOT (`lcd_id_value=1`); `mi,panel-id`="O82PB_02_0b". Abrevs: R15=`build/evidencia/android-snap/extracted-r15/uke-r15-20260625-114251/`, DT=`build/evidencia/android-snap/dt-r15/`, D=`build/gates/revision/`.

## 1. ABL/splash (MEDIDO parcial; bins NO disponibles)

- `~/gpu-work/abl-analysis/` contiene solo `bak/` (vacío de bins/fuentes ABL/LK). HIPÓTESIS
  inevitable: todo lo del ABL se infiere del handover, no de su código.
- El ABL pinta el logo en `splash_region` **0xE3940000+0x2B00000** (43 MiB ≈ 3 frames
  1600×2136×4): `DT/reserved-memory/splash_region/reg` = `00..e3 94 00 00 … 02 b0 00 00`
  (MEDIDO hoy por `od`). `docs/historia/revision/ANDROID-SISTEMA-INIT-20261013.md:287-304` lo describe
  `map, non-reusable`; mainline L29 lo reserva exacto (`memmap=0x2B00000$0xE3940000`, §1.1).
- Lo que deja configurado (MEDIDO por herencia): MDSS/GDSC ON (el vendor no trae
  `power-domains`/`resets` y jamás la toca: `docs/historia/revision/PIPELINE-PANEL-20261014/ANDROID-CADENA-20261014.md:103-109`);
  clocks sembrados a **514 MHz** en probe (`docs/historia/revision/PIPELINE-PANEL-20261014/ANDROID-CADENA-20261014.md:70-85`);
  vsp/vsn con `regulator-boot-on` (dtbo-stock: `D/…SECUENCIA-…:192-195`);
  KTZ8866 andando (nuestro L53 midió sus registros IDÉNTICOS al ABL: `docs/historia/revision/PIPELINE-PANEL-20261014/ANDROID-CAMINO-COMPLETO.md:18`).
- Cmdline ABL: 54 tokens, `dsi_display0=o82_42_02_0b` selector de panel
  (`DT/chosen/bootargs`, `docs/historia/revision/ANDROID-SISTEMA-INIT-20261013.md:44-107`); `vendor_boot` DTB base
  trae MDSS/DSI Ctrl/PHY pero **ningún nodo de panel** — todo el panel vive en el dtbo
  (`fragment@95`=CSOT `42_02_0b`, `fragment@96`=TM; `docs/historia/revision/ANDROID-SISTEMA-INIT-20261013.md:315-324`).

## 2. Kernel vendor: cont_splash (salta TODO) vs boot frío (secuencia completa)

- Bind panel `o82_42_02_0b_dualdsi_dsc_vid` a 3.809 s, `cont_splash enabled in 1 of 1`
  a 3.836 s (`R/07-sys/dmesg-FULL.txt:4672,4739`).
- Con splash vivo: `dsi_display_enable` (`.ko:0x146e90`) → `dsi_display_config_ctrl_for_cont_splash`
  y **SALTA todo el prepare del panel** (`SECUENCIA-…:15`, `docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md:145-146`).
  `dsi_display_cont_splash_config` (`.ko:0x13f720`): solo `pm_runtime_resume`+ISRs+`clk_ctrl` —
  ni reset PHY/host, ni reguladores, ni reset-gpio, ni un DCS. **Cero DCS entre 3.8 s y el
  primer commit (~10.84 s)**: 7 s de splash heredado (`docs/historia/revision/PIPELINE-PANEL-20261014/ANDROID-CAMINO-COMPLETO.md:25-33`).
- Boot frío (sin splash; en esta unidad nunca ocurre en vivo — el ABL siempre pinta):
  `LP11 → rails+reset+pinctrl (pre_prepare) → LINK_CLK → 2º reset+PRE_ON vacío →
  108 DCS en LP → PPS → vídeo-engine AL FINAL → post-enable` (`SECUENCIA-… §A`).
  Orden literal RE: ISRs → CORE_CLK ×2 → PHY SW-reset → PHY enable (LP11, nada HS) →
  host-init ctrl0 → **pre_prepare** (`.ko:0x145628`) → timing+init ctrl1 → engines →
  LINK_CLK (`.ko:0x145990`) → host-disable → soft-reset → `dsi_panel_prepare`
  (`docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md:26-61`). Rails+reset ocurren con PHY ya en LP11
  (`qcom,mdss-dsi-lp11-init` bool presente).
- PPS: `dsi_panel_update_pps()` corre en enable **después** de los 108 DCS y **antes** del
  vídeo-engine (`SECUENCIA-…:52-54`); es **calculada, no va al panel** (el IC viene
  preconfigurado por el bloque `0x90/0x91/0x92/0x9D` del init, cmds #100-103).
- Power framework: `sde_power_resource_enable` con guard cont-splash — enable/disable
  completos **omitidos** con splash (`decomp/sde_power_resource_enable.c:142-161`,
  `docs/historia/revision/PIPELINE-PANEL-20261014/ANDROID-CADENA-20261014.md:48-62`); suspend/reanuda **rehusados** (`-ENODATA`) con splash
  (`sde_kms_pm_suspend.c:57-81`); 700 s de dmesg sin un suspend de display, conector en
  power-mode 2 de 10.84 s a 711 s (`docs/historia/revision/PIPELINE-PANEL-20261014/ANDROID-CADENA-20261014.md:126-140`).
- Lecturas al panel: en enable solo diagnóstico (`build-id`, `peak-hdr-gamma`, `tx(190)`
  no-op por ausente en DT); `lockdown_info_read` a 3.868 s da `Panel not initialized`
  = **benigno bajo splash** (dmesg-FULL.txt:4831); `cell_id read` falla parse (`rc=-22`,
  dmesg-FULL.txt:4444). Es decir: el vendor **casi no lee nada** del panel en boot.

## 3. Secuencia DCS + config DSC (MEDIDO byte a byte)

- `timing@120/qcom,mdss-dsi-on-command` = **998 B = 108 registros**, cabecera 7 B,
  todos `dt=0x39`, `on-command-state="dsi_lp_mode"` (todos en LP).
  #0–103 init vendor (páginas `ff 27/23/25/2a/26/22/f0/20/10`, gammas, `0x51=0x0FFF`,
  `0x53=0x24`; `0x11`/`0x29` intermedios son registros de página, no DCS);
  #104/105 `b3 40`/`b2 91` (120 Hz); **#106 `0x11`+120 ms (ÚNICO wait≠0)**; **#107 `0x29`**
  (`docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md:176-307`, tabla completa #0–107).
  OFF = `0x28`+20 ms, `0x10`+100 ms, `0x4f` (LP). Switch-video: único set en HS.
- Reset: TLMM 2 active-high `(0,10 ms)(1,3 ms)(0,3 ms)(1,+15 ms)`, **doble**
  (pre_prepare + prepare), un gpio queda en INPUT al final (`DT/…/qcom,mdss-dsi-reset-sequence`
  = `0 10 1 3 0 3 1 15`, MEDIDO hoy por `od`; RE `dsi_panel_reset @0x155ed8`).
- DSC (campos del nodo `timing@120`, MEDIDOS hoy por `od -tx1`): `compression-mode="dsc"`,
  version **0x11 (=1.1)**, scr 0, bpc **10**, bpp **8**, slice **0x320=800 × 0x18=24**,
  slice/pkt **1**, block-pred presente, `display-topology = 2 2 2`,
  `default-topology-index = 0`. Mainline `o82_dsc_config` idéntico
  (`docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md:469-490`).
- Origen de cada campo: todo sale del dtbo (overlay), nada de firmware: los
  `mdss_dsi_o82_*_mi.xml` son **solo calibración de color** del composer HAL
  (`docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md:499-502`); el DPU/DSI hace **cero `request_firmware`**
  en 13 648 líneas de dmesg (`docs/historia/revision/ANDROID-SISTEMA-INIT-20261013.md:268-285`).

## 4. Clocks/PHY/reguladores EFECTIVOS (dumps r15, MEDIDO)

- DSI0 PLL (el que gobierna): `dsi0_phy_pll_out_dsiclk` **237 832 851 Hz**,
  `pll_byte_clk0` **148 645 532 Hz**; `pclk0/1` **158 555 234 Hz** c/u;
  `byte_intf` 74 322 766 Hz (`R/02-clk/clk-summary-FULL.txt`, líneas `dsi0_phy_pll…`).
  SSC apagado (`ssc disable…ssc-disable`, dmesg-FULL.txt:4357).
- MDSS (`DT/soc/qcom,mdss_mdp@ae00000/clock-rate`, MEDIDO hoy): `branch/core/lut` =
  **514 000 000**, `vsync` 19.2 MHz, `gcc_bus/iface` 0; `clock-max-rate` 600 MHz.
  Sembrados en probe + enable sin `set_rate` (RE `msm_dss_clk_set_rate.c:1-31`;
  `docs/historia/revision/PIPELINE-PANEL-20261014/ANDROID-CADENA-20261014.md:63-85`). En el power path DSI **no hay ningún
  `set_rate`/`reparent`** — solo votos ON/OFF; rates/parents se programan en modeset
  (`docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md:154-172`).
- PHY timings DT: `00 27 0a 0a 1b 19 0a 0b 0a 02 04 00 20 0f` (14 B, igual en los 3 timings);
  `clk-strength=255`, `phy-voltage=81 (0x51)` (MEDIDO hoy; mainline no los programa).
- Rails (walk de phandles, `docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md:374-403`): `vddio`=L8 **1.9 V**
  + `vci`=L19 **2.6 V** (init, max 3.544 V) → `vddil8b`(L8)→`vsp`(TLMM74 **+5.8 V**)→
  `vsn`(TLMM75 **−5.8 V**), enable-load **300 mA**, 2 ms post-on; vsp/vsn `regulator-boot-on`.

## 5. Modo vídeo (MEDIDO) y primer commit

- `dsi_video_mode`, `trigger_sw`/`none`, VC 0, RGB888 (`qcom,mdss-dsi-bpp`=0x1e=30 raw),
  dual-DSI (`qcom,dsi-ctrl/phy`=2 ctrls+2 phys, broadcast+`cmd-sync-wait-broadcast`).
  BLLP/eof-power-mode y lane-states **vacíos** = 4 lanes ON, BLLP en LP.
  Timing@120 por link: **1600×2136, hfp 113, hbp/hpw 16, vfp 26, vbp 146, vpw 2**,
  `panel-clockrate` **1189190000** (igual en 120/144/90; hfp 18 en 144, 304 en 90);
  DFPS 7 modos `120 144 90 60 50 48 30` por porches VFP (MEDIDO hoy + dmesg-FULL.txt:4708-4729).
  TE = TLMM 77 (`sde_te_active`, `mdp_vsync_p`); `hw_vsync_info: fps 119.992,
  panel_mode:dsi_video` (`R/03-display/mi-display.txt`).
- Primer commit: composer 6.06 s → surfaceflinger 6.42 s → bootanim 8.80 s
  (`ro.boottime.*`, `docs/historia/revision/ANDROID-SISTEMA-INIT-20261013.md:245-266`); primer DPMS on
  (`power mode 1→2`) a **10.84 s** (dmesg-FULL.txt:9643), DFPS 120→144 right after.
  ESD (TLMM 168/169, flags 0x2004) registrada a 3.83 s pero **armada tras el primer
  unblank** a 10.862 s; cero ataques en 700 s (`docs/historia/revision/PIPELINE-PANEL-20261014/ANDROID-CADENA-20261014.md:203-213`).

## 6. Backlight/KTZ (resumen; detalle en `docs/historia/revision/PIPELINE-PANEL-20261014/ANDROID-CAMINO-COMPLETO.md:39-48`)

- Runtime vendor = **KTZ externo, NO DCS 0x51** (`bl-pmic-control-type=bl_ctrl_external`;
  el `51 0f ff` del init es registro de página 0x10; `0x53=0x24` programado en init).
  `bl-update-flag=delay_until_first_frame` + `mi,mdss-panel-on-dimming-delay`=**300 ms**
  (0x12c): el brillo sale por el path atómico **tras la 1ª trama + 300 ms**.
- KTZ8866 **DUAL** (`2-0011` + `7-0011` probe OK a 3.75 s, dmesg-FULL.txt:4314/4329);
  primer write a **10.85 s** (`backlight 0x530, brightness 230`, dmesg-FULL.txt:9644),
  rampa 232→255 hasta 16.2 s. Min 4 / max-init 4095/307 (0x133). Nunca se apaga en 700 s.

## 7. Agujeros declarados (sin evidencia)

1. **ABL**: sin bins/fuentes — init exacto del panel por el ABL, valor PPS que escribe
   (si escribe), y si deja DSC/PPS programados en el DDIC: HIPÓTESIS (se infiere del handover).
2. Boot frío vendor **jamás observado en vivo** (el ABL siempre deja splash): la secuencia
   §2 es RE del `.ko` (`~/proyectos/ubuntu-uke/stock/modules/msm_drm.ko`), no traza.
   Árbol vendor `uke-v-oss` **no contiene el stack display** (techpack separado no publicado).
3. Identidad exacta de los 2 votos `dsi_pwr_enable_regulator` (vddio/vci = inferencia por DT).
4. `qcom,mdss-dsi-bpp` raw 0x1e sin decodificar del todo (nota de rigor en DSI-PROFUNDO §6).
5. Sin `super.img` extraída: los `.rc` de composer/sf/bootanim se infieren por `getprop`.
