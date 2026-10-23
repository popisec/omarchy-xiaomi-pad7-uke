# ANDROID camino completo del panel o82 (14-oct-2026)

> Solo lectura. Medido = con fichero:línea o comando+salida. Hipótesis = marcada.
> Contexto: nuestro kernel ya da vídeo (commit OK, L52/L54) pero sin luz; KTZ y
> raíles descartados por medición (ledger #628/#629). El ABL sí da luz (splash).

## 1. ABL/LK — el splash (MEDIDO parcial; binarios NO disponibles)

- El ABL pinta el logo en `splash_region` **0xE3940000+0x2B00000** (43 MiB ≈ 3 frames
  1600×2136×4) y la describe `map, non-reusable` en el DT que pasa al kernel
  (`docs/historia/revision/ANDROID-SISTEMA-INIT-20261013.md:287-304`).
- Lo que deja encendido (MEDIDO por herencia, no por fuente ABL): MDSS/GDSC ON
  (el vendor no trae `power-domains`/`resets` y jamás la toca:
  `PIPELINE-PANEL-20261014/ANDROID-CADENA-20261014.md:103-109`), clocks a 514 MHz
  sembrados en probe (`:70-85`), raíles con `regulator-boot-on`
  (`~/gpu-work/ramaa/s7/dtbo-stock-decomp.dts:13720-13742`, vsp TLMM74/vsn TLMM75
  ±5.8 V), y el KTZ8866 con la config de luz (nuestro L53 midió sus registros
  IDÉNTICOS al ABL en probe 4.1 s: ledger #628/#629 — el ABL deja el KTZ andando).
- Fuentes ABL/LK: **no disponibles** — `~/gpu-work/abl-analysis/` está vacío;
  no hay bins ni fuentes de LK/aboot en `~/gpu-work/` (solo dtbo/dtb descompilados
  y `u1-prep/` con vendor_boot). Lo anterior es inferencia desde el handover,
  marcada como tal. La cmdline del ABL (54 tokens, `dsi_display0=o82_42_02_0b`)
  en `build/evidencia/android-snap/dt-r15/chosen/bootargs` (SISTEMA-INIT §1).

## 2. Kernel Android — NO re-inicializa (MEDIDO: RE + dmesg r15)

- Bind panel `o82_42_02_0b_dualdsi_dsc_vid` a 3.809 s, `cont_splash enabled in 1
  of 1 display(s)` a 3.836 s
  (`build/evidencia/android-snap/extracted-r15/uke-r15-20260625-114251/07-sys/dmesg-FULL.txt:4672,4739`).
- `dsi_display_enable` (`.ko:0x146e90`): **check cont-splash → si splash vivo,
  `dsi_display_config_ctrl_for_cont_splash` y SALTA todo el prepare del panel**
  (`SECUENCIA-ENCENDIDO-ANDROID-O82-20261012.md:15`, `docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md:145-146`).
  Cero DCS entre 3.8 s y el primer commit (~10.84 s): 7 s de splash heredado.
- Power: `sde_power_resource_enable` con guard cont-splash — enable/disable
  completos **omitidos** con splash vivo (RE `decomp/sde_power_resource_enable.c:142-161`,
  ANDROID-CADENA §1.2). Suspend/reanuda **rehusados** (`-ENODATA`) con splash
  (`decomp/sde_kms_pm_suspend.c:57-81`, `:78-102`); 700 s de dmesg sin un
  suspend de display (ANDROID-CADENA §2.1).
- `qcom,bl-update-flag = "delay_until_first_frame"` + `mi,mdss-panel-on-dimming-delay
  = 0x12c` (300 ms) (`dtbo-stock-decomp.dts:/tmp/o82.txt:23,36`): el brillo NO
  sale en enable sino por el path atómico tras la 1ª trama + 300 ms.
- Backlight case 3 (MEDIDO): panel-id `0x4f38325042020b` → `dsi_panel_set_backlight.c:246`
  va a **case 3 = `ktz8866_backlight_update_status()`** + sets 0xfb/0xfc; **DCS
  0x51 NO se usa en runtime en uke** (`NOTAS-OMARCHY.md:4141-4143`). KTZ DUAL
  (`ktz8866@11` en `qupv3_se0_i2c` y `qupv3_se12_i2c`, `dtbo-stock-decomp.dts:13800-13822`);
  primer write a **10.85 s** (`backlight 0x530, brightness 230`, dmesg-FULL:9644),
  justo tras DPMS 1→2 de 10.84 s. ESD (TLMM 168/169) registrado a 3.83 s pero
  **armado tras el primer unblank** a 10.862 s, cero ataques en 700 s (ANDROID-CADENA §3.4).

## 3. Secuencias DCS stock vs nuestra (MEDIDO: byte a byte)

- Stock `timing@120/qcom,mdss-dsi-on-command`: **108 registros, todos LP**
  (`on-command-state = "dsi_lp_mode"`), #0–103 init vendor, #104/105 `b3 40`/`b2 91`
  (120 Hz), #106 `0x11` +120 ms (único wait≠0), #107 `0x29`; OFF = `0x28`+20 ms,
  `0x10`+100 ms, `0x4f` (ANDROID-CADENA §3.2; blob en `dtbo-stock-decomp.dts:8482`).
- Nuestra `o82_init_cmds` = **byte-idéntica al vendor a nivel payload**: 104 + cola
  en código `b3 40 / b2 91 / 0x11 +120 ms / 0x29` = registros 104–107; el byte[3]
  `0x40` vs `0x00` es hint de batching del parser vendor, nunca sale al cable
  (`NOTAS-OMARCHY.md:4138-4140`, REV-DSI 13-oct).
- El `51 0f ff` del init (cmd 97) es **registro de página 0x10, no brillo DCS**;
  el init también programa `0x53 = 0x24`. Runtime = KTZ (case 3), no DCS 0x51.
- Reset stock: `(0,10 ms)(1,3 ms)(0,3 ms)(1,+15 ms)` TLMM 2 active-high, **doble**
  (pre_prepare + prepare) (`dtbo-stock-decomp.dts:/tmp/o82.txt:55`; SECUENCIA §A.1).
  Rails: `vddio`(L8 1.9 V)+`vci`(L19 2.6 V) → `vddil8b`→`vsp`→`vsn`, 300 mA, 2 ms.

## 4. Los momentos vendor (MEDIDO)

`LP11 → rails+reset+pinctrl (pre_prepare) → LINK_CLK → 2º reset+PRE_ON vacío →
108 DCS en LP → PPS → vídeo-engine AL FINAL → post-enable` (SECUENCIA §A).
**Backlight: ni en splash (heredado del ABL) ni en enable — a 10.85 s, tras la
primera trama + 300 ms.** La luz del splash (t=0→10.8 s) es 100 % estado ABL.

## 5. Conclusión: qué afirma la evidencia + hipótesis para lo que nos falta

MEDIDO: (a) el hardware enciende con la receta ABL y Android la **conserva**
(cont-splash: sin reset MDSS, sin DCS, sin tocar KTZ hasta el primer frame);
(b) nuestra secuencia DCS es correcta (payload idéntico); (c) KTZ y raíles
descartados por medición (#628: regs idénticos; #629: cleanup bloqueado sin luz).
HIPÓTESIS rankeadas para el blanco ~1 s → apagado: **H1 — re-inicializamos lo que
Android jamás toca**: nuestro prepare (reset + 104 DCS + 0x29) corre sobre el panel
vivo del ABL y el enable enciende backlight con 0 píxeles = blanco forzoso; el
vendor lo prohíbe con `delay_until_first_frame` (REV-DSI §6, `NOTAS-OMARCHY.md:4161`).
**H2 — path de brillo equivocado**: runtime vendor = KTZ case 3; el 0x51 del init
es registro, no brillo (L55 branch B lo discrimina). **H3 — ventana vídeo/dimming**:
el DDIC espera 1ª trama + 300 ms con dimming; nuestro backlight-en-prepare llega
antes del vídeo y el DDIC puede blankear; o detalle de power no registrado (AVDD
stock `boot-on` sin contraparte en nuestro DT, corrección vigente de #629).
