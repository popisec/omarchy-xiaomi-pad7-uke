# ANDROID-CADENA — cómo funciona la cadena de display en el vendor (14-oct-2026)

> Encarago del pipeline: describir la cadena de display de ANDROID para compararla con la
> nuestra. Solo lectura; toda afirmación con `fichero:línea` o comando+salida; lo no
> disponible se marca «no disponible». Nada de memoria.
> Contexto que la hace urgente: H2/L47 — con display-ON el bind completa a 46.98 s y la
> tablet muere en silencio (reset `pureason=0x80100`), sin tráfico DRM post-bind
> (`H2-CRASH-CAPTURADO-20261014.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/CRITICA-L48.md`, `docs/historia/revision/PIPELINE-PANEL-20261014/L48-PREP.md`).

## 0. Qué he leído (fuentes primarias)

- `docs/historia/revision/ANDROID-POWER-DPU-20261013.md` (RE de `msm_drm.ko`: power/VBIF/clocks/genpd).
- `build/gates/revision/SECUENCIA-ENCENDIDO-ANDROID-O82-20261012.md` (prepare/enable, rails, reset, splash).
- `docs/historia/revision/ANDROID-DSI-PROFUNDO-20261013.md` (prepare instrucción a instrucción, 108 DCS, rails, ESD/TE, PHY).
- `docs/historia/revision/ANDROID-DSI-ENABLE-COMPARISON-20261013.md` (ventana host-en→VIDEO_DONE, H1–H8).
- `docs/historia/revision/ANDROID-SISTEMA-INIT-20261013.md` (cmdline, vendor_boot, userspace, splash regions).
- `docs/historia/revision/ANDROID-GPU-ARRANQUE-20261010.md` (secuencia GPU de referencia).
- `build/gates/revision/GAPLIST-VENDOR-MAINLINE-20261013.md` (G1–G10).
- Decompilados verificados por mí hoy: `build/vendor-re/decomp/sde_kms_handle_power_event.c`,
  `sde_power_resource_enable.c`, `msm_dss_clk_set_rate.c`, `sde_kms_pm_suspend.c`,
  `sde_kms_pm_resume.c`.
- DT Android vivo: `build/evidencia/android-snap/dt-r15/` (cada property = fichero).
- dmesg Android vivo r15: `build/evidencia/android-snap/extracted-r15/uke-r15-20260625-114251/07-sys/dmesg-FULL.txt` (13 648 líneas).
- Nuestra evidencia de contraste: `out/h2-dumps/uke-48.txt.gz` (boot L47 display-ON caído),
  árbol vivo `build/kernel-pokes/k52-L16-tree`.

## 1. Bring-up del display en Android

### 1.1 Cronología medida (dmesg r15)

| t (s) | Evento |
|---|---|
| 0.236–0.48 | `gdsc-regulator.ko`, `dispcc/gpucc` cargados (first_stage) |
| 3.7516 | `mi_disp_core_init` (`SISTEMA-INIT §4.1`) |
| 3.754/3.755 | DSI PHY0/PHY1 `Probe successful` (dmesg-FULL:4360/4372) |
| 3.756/3.7568 | DSI ctrl0/ctrl1 `Probe successful` (dmesg-FULL:4377/4385) |
| 3.759–3.829 | parseo panel o82 (1600×2136, 7 modos DFPS, topo 2-2-2 + DSC) |
| 3.809 | `Successfully bind display panel '…o82_42_02_0b_dualdsi_dsc_vid'` (dmesg-FULL:4672) |
| 3.811–3.812 | bound `dsi-display-primary` + `smmu_sde` + wb×2 + rscc + dp_display (dmesg-FULL:4684-4689) |
| 3.814 | `sde hardware revision:0xa0010000` (dmesg-FULL:4691) |
| 3.8364 | `[drm] Initialized msm_drm 1.4.0` + **`cont_splash enabled in 1 of 1`** (dmesg-FULL:4738-4739) |
| 3.844+ | touch NVT (`lcd_id=CSOT`), KTZ8866 dual OK, panel-notifier del touch |

`msm_drm.ko` se carga en **first_stage** (cola de `modules.load` de vendor_boot;
`SISTEMA-INIT §3.1`); la GPU (`msm_kgsl`) NO: probea a ~3 s sin firmware y lo pide al
primer open ~6.1 s (`GPU-ARRANQUE §4`).

### 1.2 Framework de power del SDE — orden exacto (RE)

Cadena (`POWER-DPU §1.1`): `sde_kms_pd_enable/disable` (solo runtime-resume/idle, nada más)
→ `msm_runtime_resume/suspend` → `sde_power_resource_enable(h,en)`, **ambos con guard
cont-splash** (`[handle+0x1b0]`; offsets `.ko:0x164188/0x164130`). Con splash vivo el
enable/disable completo **se omite**: los clocks del ABL siguen corriendo.

Rama ENABLE de `sde_power_resource_enable` (verificado por mí en
`decomp/sde_power_resource_enable.c:142-161`): `rsc_client_create` → `rsc_client_state_update`
→ **`msm_dss_enable_clk(clks, n, 1)`** → callbacks de eventos. La rama DISABLE
(`:30-80`): `rsc_client_state_update` → **restaura `reserve_rate` con el clock TODAVÍA
habilitado** (`msm_dss_single_clk_set_rate`, `:74`) → `msm_dss_enable_clk(...,0)` →
reg-bus/vreg/data-bus a 0. Verificado: **el enable NO contiene ningún `set_rate`**
(ningún `clk_set_rate`/`set_parent` en el camino; el único `single_clk_set_rate` del
fichero está en la rama disable).

### 1.3 `msm_dss_clk_set_rate` con clocks OFF (el patrón parked_cfg)

`decomp/msm_dss_clk_set_rate.c:1-31`: bucle pelado sobre `msm_dss_single_clk_set_rate`,
sin lógica de estado. Se llama **una vez en el probe** (`sde_power_resource_init`,
`POWER-DPU §1.3`) con los clocks CCF-deshabilitados ⇒ para un RCG compartido solo
cachea `parked_cfg`, sin tocar HW. Valores sembrados del DT (`POWER-DPU §3.1`,
`dt-r15/soc/qcom,mdss_mdp@ae00000/clock-{rate,max-rate}`):

| clock | rate | max-rate |
|---|---|---|
| `gcc_bus` / `iface_clk` | 0 | 0 |
| `branch_clk` | **514 000 000** | 600 000 000 |
| `core_clk` | **514 000 000** | 600 000 000 |
| `vsync_clk` | 19 200 000 | 19 200 000 |
| `lut_clk` | 514 000 000 | 600 000 000 |

514 MHz = el rate que deja el ABL. Tres protecciones estructurales (`POWER-DPU §7`):
(1) siembra en probe + enable sin `set_rate`; (2) `branch_clk` es **no-op por nombre**
en `single_clk_set_rate` (verificado `.ko:0xc6a54→0xc6ad0`); (3) skip completo con splash.
Además: **el SRC (`DISP_CC_MDSS_MDP_CLK_SRC`) no existe para el SDE** — no está en el DT,
no se pide, no se vota; todo rate va a ramas (`POWER-DPU §3.1`, verificado por ausencia
en `strings` del `.ko`).

### 1.4 GDSC: las `adf*` NO son de display

Medido hoy por `regulator-name` en `dt-r15/soc/qcom,gdsc@*`:

| Nodo | `regulator-name` (medido) | Dominio |
|---|---|---|
| `adf0004` | `cam_cc_bps_gdsc` | cámara |
| `adf0080` | `cam_cc_ipe_0_gdsc` | cámara |
| `adf1004` | `cam_cc_ife_0_gdsc` | cámara |
| `adf2004` | `cam_cc_ife_1_gdsc` | cámara (nótese: es `adf2004`, no `adf2000`; `adf2000` no existe) |
| `adf2054` | `cam_cc_ife_2_gdsc` | cámara |
| `adf3058` | `cam_cc_sfe_0_gdsc` | cámara |
| `adf30a8` | `cam_cc_sfe_1_gdsc` | cámara |
| `adf32bc` | `cam_cc_titan_top_gdsc` | cámara |
| **`af09000`** | **`disp_cc_mdss_core_gdsc`** | **display — la ÚNICA** |

Orden de power-up del vendor para display: **ninguno dirigido**. El nodo
`qcom,mdss_mdp@ae00000` **no trae `power-domains`, ni `#power-domain-cells`, ni
`resets`** (verificado: `ls` del nodo; `mmcx-supply = <0x149>` = `pm_v8-s6-level`
con la entry `mmcx` a voltajes/cargas **0**). Sin `#power-domain-cells`, el
`pm_genpd_init` del vendor se salta (`POWER-DPU §4`, `.ko:0x97e60-0x97efc`) ⇒ el KMD
**no toca jamás** la GDSC: queda como la dejó el ABL (ON, con el splash escaneando).
Las `adf*` de cámara las gobierna la cámara, no el display.

### 1.5 `mdss` padre vs DPU: el padre NO existe en el vendor

En `dt-r15/soc/` **no hay ningún nodo `qcom,mdss@ae00000`** (verificado por `ls` + grep
de `compatible="qcom,mdss"` con 0 resultados). Solo existen `qcom,mdss_mdp@ae00000`
(`compatible = "qcom,sde-kms"`), los 2 ctrls y los 2 phys. El `interrupt-parent`
de `qcom,mdss_dsi_ctrl0@ae94000` es el phandle `0x486` = **el propio `mdss_mdp`**
(resuelto por walk de phandles hoy): el SDE es su propio dominio de IRQs.
Contraste: mainline SÍ tiene padre `mdss: display-subsystem@ae00000`
(`palawan.dtsi:3357-3382`) con `power-domains = <&dispcc MDSS_GDSC>`
(`dispcc-sm8550.c:1644-1651`, `PWRSTS_OFF_ON + HW_CTRL`) y `resets = <&dispcc
DISP_CC_MDSS_CORE_BCR>` — dos piezas que el vendor no tiene y mainline debe gestionar
(el reset ya gateado por `P82-INHERIT` en `msm_mdss.c:323` del árbol vivo).

## 2. Después del bring-up: idle, suspend, watchdog

### 2.1 El vendor NO suspende el display (evidencia doble: RE + 700 s de dmesg)

- RE: `sde_kms_pm_suspend` (`decomp/sde_kms_pm_suspend.c:57-81`) y `sde_kms_pm_resume`
  (`decomp/sde_kms_pm_resume.c:78-102`) iteran los encoders y, si alguno está en
  cont-splash **y activo**, retornan `-ENODATA` (`0xffffffea`): **rehúsan
  suspender/reanudar**. Con splash vivo (siempre, hasta el primer commit real que
  limpia el flag), el suspend del DRM es un no-op.
- dmesg r15: el conector vive en **power mode 2 (on)** de 10.84 s a 711 s con
  **solo cambios DFPS** (`_sde_kms_drm_check_dpms … power mode 2->2, fps 120↔144↔50`,
  dmesg-FULL:9664-13248). Cero `suspend/resume` del mdss/dsi, cero `power collapsed`
  de display (el único es `msm_cvp: pwr: cvp (eva) power collapsed`, vídeo, no
  display, dmesg-FULL:8914). Primer DPMS on (`1->2`) a 10.84 s = primera vez que el
  composer toca el panel; antes, splash heredado 3.8→10.8 s sin un solo DCS.
- `qcom,sde-has-idle-pc` existe como bool en el DT, pero en la captura no hay ningún
  power-collapse del display: con pantalla encendida el vendor **mantiene todo ON**.

### 2.2 Watchdog: hay, pero nada lo ata al display

- Android arma `qcom_wdt_core.ko` (0.416 s) + `gh_virt_wdt.ko` + `gh-watchdog` con
  **`wdog bark_time 20000`** = 20 s (dmesg-FULL:1369-1430).
- En `msm_drm.ko` decompilado: **0 resultados** para `watchdog|wdt|bark|bite`
  (grep sobre `build/vendor-re/decomp/`, verificado hoy). No hay watchdog/timeout
  asociado al mdss/dpu en el material RE — «no disponible» más allá de este negativo.
- Contraste con nuestro kernel (relevante para H2): `uke-48` muestra
  `watchdog: Hard watchdog permanently disabled` (línea 1249) y ninguna línea de
  probe/bark/pet de ningún wdt en todo el dump; coherente con `NOTAS-OMARCHY.md:789-794`
  (`qcom_wdt: error -EBUSY`, sin `/dev/watchdog`). **Nuestro kernel no tiene quién
  muerda**: un reset `0x80100` (warm reset, `NOTAS-OMARCHY.md:558`) tras un silencio
  sin panic apunta a colapso de bus/GDSC o a un watchdog fuera del APSS — fuente
  exacta «no disponible» (nuestro dump no trae `PMIC PON log`; el vendor sí lo trae,
  dmesg-FULL:1632-1675, siempre `PS_HOLD` en boot normal).

## 3. Panel / TDDI / backlight en Android

### 3.1 Secuencia (RE + DT)

Prepare (`SECUENCIA §A`, `DSI-PROFUNDO §1.1`, `.ko:0x145224`): ISRs primero →
CORE_CLK (×2 votos) → PHY SW-reset → PHY enable (**lanes a LP11, nada en HS**) →
host-init ctrl0 → **pre_prepare (rails+reset+pinctrl)** → timing+init ctrl1 →
engines → **LINK_CLK** → ctrl_host_disable → soft-reset → **prepare (2º reset +
PRE_ON vacío)**. Enable (`.ko:0x146e90`): check splash → `tx(190)` no-op → **los 108
DCS en LP** → PPS → **video-engine al final**. Post-enable: POST_ON vacío + paso a
video-mode. Regla de oro: **rails+reset ocurren con PHY ya en LP11 y host
inicializado; los DCS salen con el motor de vídeo configurado y se enciende
después** (`ENABLE-COMPARISON §1`, H1–H2).

### 3.2 Los 108 DCS, rails, reset (bytes verificados)

- Blob `timing@120/qcom,mdss-dsi-on-command` = **998 B = 108 registros**, cabecera
  7 B, todos `dt=0x39`, `on-command-state = "dsi_lp_mode"` (`DSI-PROFUNDO §2`,
  tabla #0–107). #0–103 init vendor (páginas 0x27/0x23/0x25/0x2a/0x26/0x22/0xf0/0x20,
  gammas, `0x51=0x0FFF`, `0x53=0x24`); #104/105 `b3 40`/`b2 91` (120 Hz); **#106
  `0x11` +120 ms (ÚNICO wait≠0)**; **#107 `0x29`**. OFF: `0x28`+20 ms, `0x10`+100 ms,
  `0x4f` (LP). Switch-video: único set en **HS** (`DSI-PROFUNDO §2.1`).
- Rails, en orden (`DSI-PROFUNDO §4`): `vddio`(L8 1.9 V) + `vci`(L19 2.6 V) →
  `vddil8b`(L8)→`vsp`(TLMM74 +5.8 V)→`vsn`(TLMM75 −5.8 V), `enable-load` 300 mA,
  2 ms post-on cada uno; **vsp/vsn con `regulator-boot-on`**.
- Reset: TLMM 2 active-high, `(0,10 ms)→(1,3 ms)→(0,3 ms)→(1,+15 ms)`; **doble reset**
  (pre_prepare + prepare); al final un gpio queda en INPUT (`DSI-PROFUNDO §3`).

### 3.3 KTZ8866: DUAL, y el vendor lo enciende tarde

- Dos nodos `ktz8866@11` (`compatible = "ktz,ktz8866"`), ambos `status = "ok"`:
  `i2c@a80000` (qupv3_0) e `i2c@890000` (qupv3_1). Ambos probean OK a 3.7498/3.7515 s
  (`ktz8866 2-0011` y `7-0011: probe sucess end`, dmesg-FULL:4314/4329).
- Ubicación del driver vendor: **no disponible** (no hay `ktz8866*.ko` en
  `stock/modules/` ni en `INDEX-vendor_dlkm_ko.txt`; casi seguro built-in — el dmesg
  lo muestra probeando en first_stage junto a `msm_drm`).
- Primera escritura de brillo a **10.85 s** (`ktz8866_backlight_update_status:
  backlight 0x530, brightness 230`, dmesg-FULL:9644), justo tras el DPMS `1->2` de
  10.84 s y el `panel set backlight dimming on` (`bl-update-flag =
  delay_until_first_frame` + `on-dimming-delay = 300 ms`; `SECUENCIA §A` paso 22).
  Rampa 16.2 s: 232→255. Relación con el panel: el KTZ es **externo** al DDIC
  (`bl-pmic-control-type = bl_ctrl_external`); el `0x51` del init va al DDIC y el
  KTZ lo gobierna `dsi_panel_set_backlight` por el path atómico. El vendor **nunca
  apaga el KTZ tras encenderlo** en la captura (solo rampas ascendentes).

### 3.4 ESD/TDDI: registrado pronto, armado tras el primer unblank, cero ataques

- `mi,is-tddi-flag` presente. ESD dual TLMM **168/169** flags `0x2004`;
  registrado a 3.8298 s (`register esd irq (second) success`, dmesg-FULL:4730-4731),
  **habilitado a 10.862 s** tras el primer unblank (`esd irq [second] is enable`,
  dmesg-FULL:9646-9648). **Cero ataques/recuperaciones en 700+s** (grep
  `attack|trigger|recover` en el dmesg: 0 resultados de display).
- TE = TLMM 77 (`sde_te_active`, `mdp_vsync_p`); HBM solo framework (`PanelMaxDbv=4095`).
  ESD/TE **no intervienen** en prepare/enable (`DSI-PROFUNDO §5`).
- Nota: `Panel not initialized` (lockdown read, dmesg-FULL:4831/4910) a 3.868 s es
  benigno bajo splash (el panel lo gobierna el ABL hasta el primer commit).

## 4. Deltas concretos vs nuestra cadena mainline

| # | Paso | Android (vendor) | Nosotros (mainline L47/L48) | Estado |
|---|---|---|---|---|
| 1 | Nodo padre mdss | **No existe** (solo `mdss_mdp`; §1.5) | `mdss@ae00000` con `MDSS_GDSC` + `CORE_BCR` (`palawan.dtsi:3357-3382`) | Delta estructural; reset ya gateado (`msm_mdss.c:323`) |
| 2 | Reset duro MDSS | Nunca (sin `resets` en DT) | En probe temprano, igual en ambos brazos (no discrimina H2; `L48-PREP §2` paso C4) | Neutralizado |
| 3 | GDSC display | Nadie la toca (sin genpd; ABL la deja ON) | genpd la gestiona; `pd_ignore_unused` en cmdline (verificado en `uke-48:2`), pero el **runtime-suspend SÍ puede apagarla** | **VIVO** (ver §5 H-A) |
| 4 | VBIF memtypes | Doble guard con splash (RE §126-151) | Reescritura incondicional ×2 (`dpu_kms.c:1292` + `:1515`), salvo `uke_panel_inherit()` — que está **OFF** en L47 (0 líneas `P82-INHERIT` en `uke-48`) | Vivo pero débil (muerte 3 s después sin fault; `L48-PREP` C2) |
| 5 | Siembra SRC/clocks | Siembra 514 M en probe + enable sin `set_rate` | **Idéntico mecanismo**: OPP 514 M en `dpu_kms_init` (`dpu_kms.c:1313-1317`) → `parked_cfg`=514 (`CRITICA-L48 §3`, 5 eslabones verificados) | **CERRADO** (falta confirmación en vivo `K48-opp-rate`) |
| 6 | Runtime-suspend post-bind | **Rehusado** con splash (`-ENODATA`); display ON 700+s | **DPU suspende a +~0 ms e MDSS a +~200 ms tras `Initialized`** (`uke-48`: `K48-dpu-susp` 47.177416, `K48-mdss-susp` 47.182072; clocks OFF + `icc_set_bw(0,0)`) | **DELTA CONFIRMADO EN VIVO — el mayor** |
| 7 | Modeset en boot | Hereda splash; cero DCS; 1er commit userspace ~6 s; backlight 10.85 s | Modeset-from-scratch a 47 s (get_modes→fbcon en H2/L46; en L47 el commit no llega: `card1-DSI-1: unknown`, 0 `pan-modes`) | Delta estructural; H2 murió EN el modeset, L47 DESPUÉS del bind sin commit |
| 8 | Orden DSI/panel | LP11 → rails/reset → LINK → DCS-en-enable → vídeo al final | Prepare (rails/reset/DCS) sin garantía LP11; vídeo-ON antes de DCS; sin `TIMING_FLUSH`/`HS_TIMER`/`TIMING_DB_MODE`, sin limpieza W1C previa (`ENABLE-COMPARISON` H1–H8) | Vivo para la fase DCS (post-H2) |
| 9 | Backlight | Dual KTZ8866, tras 1ª trama + 300 ms | Un solo KTZ (L44, verde); timing en enable | Pendiente post-imagen |
| 10 | vci (L19) | Votado en pre_prepare (2.6 V) | Driver lo soporta (opcional); sin `vci-supply` no se vota (tema S1) | Vivo (S1); nótese: en `uke-48` L19 pasa `use 0→1` a 47 s (el supply del panel SÍ resolvió) |
| 11 | IOMMU | `apps-smmu` QSmmuV500 + `handoff-smrs 0x1c00` | `arm-smmu` v2, bindea con WARN benigno (6× también en el control vivo) | Neutralizado como causa |
| 12 | IRQs display | `sde_irq_update(h,1)` **lo primero** del power-enable | `msm_irq_install` tras `hw_init` (resume#2) | Orden equivalente |

## 5. Hipótesis para nuestra muerte post-bind (derivadas de la comparación)

Hecho nuevo que fija este informe (medido hoy en `uke-48`, segundo a segundo):
`hw-ok` 47.175 → **suspend DPU 47.177** → resume#2 → `Initialized` 47.178 →
**suspend MDSS 47.182** → snapshot 48 s (`DSI-1: unknown`, 0 tráfico DRM) → silencio →
reset `0x80100`. El vendor, en la ventana equivalente, **no suspende jamás** (§2.1).

| # | Hipótesis | Base en la comparación | Experimento que la discrimina (1 variable) |
|---|---|---|---|
| H-A | **El asesino está en el runtime-suspend post-bind** (o en lo que deja tras de sí: clocks OFF + `icc 0` + posible power-off de `MDSS_GDSC`/MMCX por genpd, que `pd_ignore_unused` NO impide). El vendor rehúsa este camino entero. | Delta §4-#6, el único confirmado en vivo en la ventana de muerte | Un ciclo con runtime-PM prohibido en DPU+MDSS (`pm_runtime_forbid`/`disable` en el probe, instrumento, no fix): si vive ≥6 min, H-A confirmada; si muere igual, H-A refutada y el suspend queda como normal. Los 2 pokes suspend de `CRITICA-L48 §2.4` ya viajan en L48 y dirán si la muerte cae EN el suspend (última miga = entrada sin salida) |
| H-B | Reset por watchdog vivo fuera del APSS (el nuestro está deshabilitado: `uke-48:1249`). Si H-A cuelga el bus en silencio, algo muerde a ~20-60 s. | `bark_time 20000` vendor; nuestro `0x80100` = warm reset sin panic | Leer `PMIC PON reason` en el boot siguiente + pstore; si la muerte es siempre a T fijo tras el último poke, temporizador; si es variable, evento. (Requiere driver/lectura, no un flash) |
| H-C | Actor diferido no-DRM (sddm/userspace, servicio tardío): lo único que difiere `:d` vs no-`:d` tras un bind idéntico | `CRITICA-L48 §1.3/§4.2`: 0 `L6-open` post-bind en `uke-48` (solo 9/24/39 s), `atom-tail`=0 | `K48-alive` de L48 + triage `L6-open` post-bind en el ACM; modetest condicional solo-en-PASA |
| H-D | Efecto retardado del VBIF reescrito ×2 sobre el pipe heredado (el vendor lo salta por partida doble) | Delta §4-#4 | Ya instrumentado (`K48-hw-vbif-ok`, `K48-res-vbif-ok` en L48): si la muerte cae siempre >1 s después con VBIF completo, H-D decae; el fix (una condición) es el ciclo siguiente, no este |
| H-E | vci/DDIC-analógico (L19): el panel resolvió su supply a 47 s pero el `prepare` nunca corrió en H2 | Delta §4-#10 (tema S1) | S1 (declarar `vci-supply`): si el ciclo S1 llega a `pan-prep`/DCS, H-E era parte del muro DCS; para la muerte *post-bind* H-E no aplica (el regulador ya resolvió) |

Orden propuesto (una variable por ciclo, coherente con `L48-PREP §8`/`CRITICA-L48 §5`):
**L48** (instrumentación + `opp-rate`, ya prepped) → si FALLA-POST: ciclo forbid-suspend
(H-A) → si vive: bisect del suspend (clocks vs icc vs genpd) → después, fase DCS
(H1–H8 de `ENABLE-COMPARISON`) y S1-vci. Lo que NO se toca: siembra OPP (cerrada en
código, `CRITICA-L48 §3`), BCR, máscara de error (H7).
