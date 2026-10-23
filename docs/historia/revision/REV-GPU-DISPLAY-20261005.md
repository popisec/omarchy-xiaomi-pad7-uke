# REV-GPU-DISPLAY — revisión de la captura integral Android (5-oct-2026)

Revisor: subagente GPU+pantalla (#528). Entrada: `build/evidencia/android-full/extracted-full/`
(raíz `EX/` en adelante; **gitignoreada**, no commitear) + árboles del port EN SOLO LECTURA
(`~/gpu-work/palawan-linux` rama `uke-ports-20260915`, `~/gpu-work/ramaa/`,
`~/gpu-work/build-uke/.config`). Nada editado fuera de este informe.

Contradicción #527 (ACD=1 sysfs vs acd_calibrate=0 de r1.5): **RESUELTA** (ver Q1).

---

## (a) VEREDICTOS POR PREGUNTA

### Q1 — ACD: el vendor corre con ACD ACTIVADO; `acd_calibrate` es un trigger, no un estado

**Veredicto: la r1.5 (#526) sacó la conclusión correcta (nuestro `qmp_send(acd,0)` es seguro y
harmless) pero del fichero equivocado. El estado EFECTIVO del ACD en el vendor es ON.**

Tres ficheros, tres significados distintos:

| Fichero | Valor | Qué es |
|---|---|---|
| `EX/01-gpu/kgsl-debugfs/kgsl-3d0/acd_calibrate` | `0` | **Knob write-only de disparo**: escribir 1 lanza la calibración ACD en runtime (downstream kgsl). Leer devuelve el último valor escrito (nunca se disparó manualmente). NO es el estado de la feature. |
| `EX/16-fixup/kgsl-3d0-sysfs/acd` | `1` | **Estado de la feature** (`/sys/class/kgsl/kgsl-3d0/acd`, lo publica el driver tras el probe del GMU). `1` = ACD negociado y activo con el fw del GMU. |
| `EX/16-fixup/kgsl-3d0-sysfs/ifpc` + `ifpc_count` | `1` + `0x18DE` | IFPC activo y con **6366 entradas en idle power collapse** → el GMU duerme/despierta por IFPC continuamente; el CM3 + fw del vendor funcionan de sobra. |

- dmesg: **cero líneas acd/ifpc** en `EX/15-common/dmesg-full.txt` (grep case-insensitive, 0 hits)
  — este build del vendor no loguea ACD, por eso r1.5 solo tenía el knob de debugfs y sacó la
  conclusión invertida.
- **La tabla ACD vive en el DT vendor**: `qcom,gpu-pwrlevel@0..8` traen `qcom,acd-level` (u32):

  | freq (MHz) | qcom,acd-level |
  |---|---|
  | 950 / 900 / 835 | `0xa8285ffd` |
  | 736 / 684 / 633 | `0x88295ffd` |
  | 500 | `0xa8295ffd` |
  | 353 | `0x882c5ffd` |
  | 255 | `0x882f5ffd` |

  (extraído de `EX/14-dt/dt-live.tar.gz` → `soc/qcom,kgsl-3d0@3d00000/qcom,gpu-pwrlevels/qcom,gpu-pwrlevel@N/qcom,acd-level`).
  El formato es **idéntico** al `qcom,opp-acd-level` que el driver upstream ya consume (mismo
  patrón `xxxxx5ffd` que x1e80100 usa en mainline).
- Nuestro código: `a6xx_gmu.c:2051-2125` — sin `qcom,opp-acd-level` en el OPP table,
  `enable_by_level=0` → `qmp_send(gmu->qmp, "{class: gpu, res: acd, val: %d}", 0)` (línea 2112)
  y la función HFI `a6xx_hfi_enable_acd` (`a6xx_hfi.c:866`) sale temprano. Comentario upstream
  explícito (líneas 2108-2110): *"AOSS is supposed to assume that ACD is disabled on system
  reset. So it is harmless if we couldn't notify 'OFF' state"*.
- **Conclusión práctica**: mantener `val: 0` durante el bring-up (el muro CM3 manda). Activar ACD
  es trabajo posterior opcional con los valores exactos ya extraídos (FIX F3).

### Q2 — Ruta del firmware: nombres SIN prefijo; nuestro DT/package tienen un mismatch pendiente

**Veredicto: el driver vendor pide los nombres pelados (`gen71100_zap.mbn`, `gen71100_gmu.bin`,
`gen71100_sqe.fw`); NO existe `qcom/uke/` en el vendor.** Evidencia (`EX/15-common/dmesg-full.txt`):

- SQE: líneas 334-339 — fallbacks `-13` (SELinux) por `/vendor/firmware_mnt/image/…`,
  `/vendor/firmware_mnt/image/kiwi/…`, `/vendor/firmware/…`,
  `/vendor/firmware/wlan/qca_cld/kiwi_v2/…`, y **`Direct firmware load for gen71100_sqe.fw failed
  with error -2`** → el nombre pedido es el pelado; ueventd lo resuelve a `/vendor/firmware/`.
- GMU: líneas 366-371, idéntico → `gen71100_gmu.bin` (también `EX/01-gpu/dmesg-gpu.txt:126-136`).
- ZAP: líneas 481-486 → `gen71100_zap.mbn`; **`ueventd: found /odm/firmware/gen71100_zap.mbn`**
  (línea 531; carga 20 ms, línea 534).
- `EX/01-gpu/firmware/listing.txt`: `/vendor/firmware/qcom/uke/` NO existe; grep de `gen7*` en
  `/vendor/firmware/qcom` y `/vendor/firmware_mnt/image` vacío (el fw de GPU no vive en image/).

**Derivación para nuestro rootfs** (driver upstream, distinto mecanismo):
- `a6xx_catalog.c:1621-1630` (0x43030b00): sqe=`gen71100_sqe.fw`, gmu=`gen71100_gmu.bin`,
  zapfw=`gen71100_zap.mbn`. GMU/SQE pasan por `adreno_request_fw` (`adreno_gpu.c:528-600`):
  prueba `qcom/<nombre>` y luego `<nombre>` pelado → **`/lib/firmware/qcom/gen71100_{sqe,gmu}` o
  `/lib/firmware/gen71100_{sqe,gmu}` sirven**; nuestro package `build/pkg/uke-gpu-firmware` ya
  instala los pelados en `usr/lib/firmware/` → cargan por la rama "legacy location". OK tal cual.
- ZAP: con `firmware-name` en DT, `adreno_zap_shader_load` (`adreno_gpu.c:73-79`) hace
  **`request_firmware_direct` SIN fallback** del literal del DT → el nombre del DT debe ser la
  ruta EXACTA. Nuestro DT pide `"qcom/uke/gen71100_zap.mbn"` (`xiaomi-uke.dts:555`) y el package
  solo lleva `usr/lib/firmware/qcom/gen71100_zap.mbn` (sin `uke/`) → **mismatch confirmado** (la
  "bomba latente" de GPU-OFENSIVA, ahora localizada en el package). FIX F1.

### Q3 — Hub clock: 200 MHz exactos en vendor; nuestro port medido a 400 MHz

**Veredicto: delta real confirmado por doble vía.**

- Vendor (`EX/15-common/clk-summary.txt`): línea 828 `gcc_gpll0 600000000`; líneas 838-846
  `gpu_cc_hub_clk_src / gpu_cc_hub_cx_int_clk / gpu_cc_ahb_clk / gpu_cc_hub_aon_clk = 200000000`;
  líneas 380-382 `gpu_cc_pll1 440000000` → `gpu_cc_cx_gmu_clk 220000000`. En
  `EX/01-gpu/clk-gpu-grep.txt`: `gpu_cc_hub_clk_src 200000000` con padre
  `gcc_gpu_gpll0_clk_src` (600 MHz) → **200 = 600/3**. El GMU consume `hub_clk` =
  `gpu_cc_hub_cx_int_clk` (DT vivo: `soc/qcom,gmu@3d69000/clock-names` = `gmu_clk cxo_clk axi_clk
  memnoc_clk ahb_clk hub_clk`).
- Nuestro port: **medido** `UKE-CM3DBG: clks core=220000195 hub=400000000 nr=7`
  (`build/logs/consola/uke-sesion-console-antes-k23b.log:20482` y 7+ repeticiones). El core 220
  coincide con vendor; el hub es exactamente 2×.
- Mecanismo: `a6xx_gmu.c:1371-1373` pide `clk_set_rate(hub, 200000000)` para la familia a740;
  `gpucc-palawan.c:155-158` solo tiene `F(200000000, P_GPLL0_OUT_MAIN, 3, 0, 0)` y `clk-rcg.h:10`
  define `F(f,s,h,...) = {f, s, (2*h - 1), ...}` → RCG divide entre `h`=3 fijo. 400 = 1200/3
  exacto ⇒ **el padre GPLL0 está a 1200 MHz en nuestro boot** (vs 600 en vendor; GPLL0 es
  `clk_alpha_pll_fixed_lucid_ole_ops`, `gcc-palawan.c:48-61`: la fija el firmware/ABL y no se
  puede reprogramar desde Linux). El `clk_set_rate` no corrige porque no hay entrada de tabla
  capaz de dar 200 desde 1200 y el RCG queda tal cual el ABL lo dejó. FIX F2.

### Q4 — Panel o82: nuestro port YA coincide con el vendor en lo estructural; faltan los modos DFPS

**Veredicto: panel activo confirmado (`qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid`, debugfs DSI +
`EX/02-display/class-drm/card0-DSI-1.txt`); el nodo vendor valida los valores de nuestro driver y
overlay casi 1:1. Diferencias reales: nº de modos y comandos (todo en código nuestro vs DT vendor).**

Datos vendor (DT vivo `soc/qcom,mdss_mdp@ae00000/qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid/`):

- Nombre: `xiaomi o82 42 02 0b vid mode dualdsi dsc panel`; tipo `dsi_video_mode`; traffic
  `non_burst_sync_event`; bpp 8 (per lane → RGB888 en 3 lanes + DSC); `mi,panel-id` =
  `"\0O82PB\x02\x0b"`; `mi,is-tddi-flag` presente (TDDI, TE interno).
- **Modos** (`qcom,dsi-supported-dfps-list` = `120 144 90 60 50 48 30`; runtime
  `card0-DSI-1.txt` = 3200x2136 @ 144/120/90/60/50/48/30). Solo **3 timings base** en
  `qcom,mdss-dsi-display-timings/` (1600x2136 POR controlador, dual-DSI → 3200 lógico):

  | timing | fps list | h-front-porch | resto |
  |---|---|---|---|
  | `timing@144` | 144 | 18 | hbp 16, hpw 16, vfp 26, vbp 146, vpw 2 |
  | `timing@120` | 120, 60 | 113 | idem |
  | `timing@90` | 90, 50, 48, 30 | 304 | idem |

- **DSC** (los 3 timings): bpc 10, bpp 8, slice 800x24, 1 slice/pkt, dsc-version 17 (=1.1), scr 0,
  compression-mode `dsc`, topology `2 2 2` (2 ctrl/2 stream/2 enc → bonded dual-DSI).
- **Backlight**: `qcom,mdss-dsi-bl-min-level 4`, `qcom,mdss-dsi-bl-max-level 4095`,
  init-level 307 (0x133), `mi,mdss-dsi-fac-bl-max-level 2047`, `mi,max-brightness-clone 4095`;
  sysfs real `EX/02-display/backlight/panel0-backlight.txt`: type raw, max 4095. → nuestro driver
  `O82_BL_MIN_LEVEL 4` / `O82_BL_MAX_LEVEL 0xfff` (líneas 40-41) **coincide**.
- **Reset**: `platform-reset-gpio` = TLMM **GPIO 2** activo-bajo; secuencia `0/10ms, 1/3ms, 0/3ms,
  1/15ms` — igual a la del overlay (`ramaa/s21/dtbo-gpu/fase4-display.dts:360-362`).
- **Alimentación** (`soc/dsi_panel_pwr_supply_O82/`): `vddil8b` 1.9 V, `vsp` 5.8 V, `vsn` 5.8 V
  (enable-load 300 µA, ramp). Reguladores reales: `display_gpio_regulator_vsp` GPIO **74** y
  `_vsn` GPIO **75** (5.8 V, active-high, boot-on, ramp 233). Nuestro overlay (fragment@4,
  `fase4-display.dts:117-142`) tiene **exactamente** GPIO 74/75, 5.8 V, ramp 233, boot-on. ✓
- **ESD**: DT declara `mi,esd-err-irq-gpio` 168 + `-second` 169; `EX/15-common/interrupts.txt:210-211`
  muestra `msmgpio 168/169 Level esd_err_irq(2)` **con contador 0** y el debugfs del panel dice
  **`ESD feature not enabled`** (`.../esd_check_mode`) → ESD declarado pero APAGADO en runtime.
  Nuestro port sin ESD = equivalente al vendor. Nada que portar.

Comparación de nodos:

| Prop/valor | DT vivo vendor | xiaomi-uke.dts | fase4-display.dts (fragment@6) |
|---|---|---|---|
| nodo panel | 68 props bajo `mdss_mdp` (formato downstream, sin reg) | **NO EXISTE aún** (TODO comentado, líneas 513-549) | `panel@0` hijo de dsi0, reg 0, dual-port |
| definición del panel | init/on/off + 3 timings EN DT | — | en el driver `panel-xiaomi-o82-dualdsi.c` (secuencias compiladas) |
| supplies | vddil8b 1.9 / vsp 5.8 / vsn 5.8 (GPIO 74/75) | — | idem ✓ |
| reset | GPIO 2 + secuencia 10/3/3/15 | — | idem ✓ |
| DSC | 1.1, 800x24, 10→8bpp, scr0, topology 2 2 2 | — | `o82_dsc_config` 1.1/800/24/10/8<<4/2 slices ✓ |
| timings | 3 (144/120/90) + DFPS 7 modos | — | **3 modos definidos, `num_modes = 1` (solo 120 Hz)**; hfp 36/226/608 = 2× vendor (coordenadas de panel completo) ✓ |
| backlight | 4..4095, init 307 | — | clamp 4..0xfff, init 0x133 ✓ |
| esd | 168/169 (apagado en runtime) | — | sin implementar = paridad ✓ |

`fragment@1105` de los payloads (s193/s195/s249, `ramaa/s21/dtbo-gpu/s249-dtbo-build.py:12`) NO es
el panel: crea/ajusta el nodo DPU (`display-controller@ae01000`, `qcom,palawan-dpu`). El nodo del
panel de nuestro lado es el `fragment@6` de `fase4-display.dts` (comparado arriba).

### Q5 — GMU log: NO capturado en esta ronda

**Veredicto: `gmu-log` no existe en el tar** (find en todo `extracted-full/`: 0 ficheros; el
debugfs kgsl de este build solo tiene 60 ficheros, `EX/01-gpu/kgsl-debugfs/` — sin gmucore, sin
gmu_log). Lo recuperable:

- dmesg: sin líneas de versión de fw GMU/SQE ni errores del GMU tras la carga (solo el ruido de
  fallback SELinux ya citado). `EX/01-gpu/dmesg-gpu.txt` no añade nada sobre init del CM3.
- `EX/16-fixup/kgsl-3d0-sysfs/gmu_ab` = `1` (feature GMU A/B presente).
- `EX/01-gpu/kgsl-debugfs/kgsl-3d0/globals`: memstore/ucode/capturescript/GMU SCRATCH/GMU RB
  presentes (GMU operativo); `events`: **context-3 last=15468960** → GPU renderizando en la
  captura (confirma "GPU VIVA" del #526/#527).
- Las versiones `GMU FW 4.5.0 / REV 0x070b0000` siguen viniendo de la ronda anterior
  (docs/historia/revision/GPU-OFENSIVA-20261003.md, línea 26), no de esta captura. GATE G5: si se repite captura, añadir
  `/sys/kernel/debug/kgsl/gmu_log` (o el ring del gmu del vendor) y `gmucore` si existiera.

Para nuestro arranque no hay pista nueva: lo único aplicable es el ya documentado (poll
FW_INIT_RESULT con DTCM stale, a6xx_gmu.c:640-648).

### Q6 — Frecuencias: vendor 9 niveles 255–950; nuestro port tiene 2 OPP extra (1000/1100)

**Veredicto: coincidencia exacta en los 9 niveles comunes (freq + voto bus); nuestro OPP table
añade 1000/1100 MHz que el vendor NO usa en este SKU.**

- Vendor sysfs `EX/16-fixup/kgsl-3d0-sysfs/gpu_available_frequencies`: `950 900 835 736 684 633
  500 353 255` (MHz); `num_pwrlevels=9`, `default_pwrlevel=8` (255 MHz al boot),
  `gpu_model=Adreno732`. DT vivo: `qcom,gpu-pwrlevel@0..8` = 950/900/835/736/684/633/500/353/255
  con `qcom,bus-freq` 9/9/8/7/7/7/4/3/1 → `qcom,bus-table-ddr` = {0, 2136718, 3000000, 6074218,
  6671875, 8171875, 10687500, 12449218, 14398437, 16500000} kBps.
- Nuestro port (`palawan.dtsi:2399-2466`): 255→2136718, 353→6074218, 500→6671875, 633/684/736→
  12449218, 835→14398437, 900/950→16500000 — **los 9 votos idénticos al vendor**. +
  `opp-1000000000` (TURBO_L1) y `opp-1100000000` (TURBO_L2) con 16500000. El A732 de este aparato
  está binado a 950 (TURBO_L0): pedir TURBO_L1/L2 a un SKU que no los fusa es un riesgo de
  undervolt en devfreq máximo (FIX F4).
- GMU: vendor `gpu_cc_cx_gmu_clk` 220 MHz (de `gpu_cc_pll1` 440) = nuestro `gmu_opp_table`
  220/550 (palawan.dtsi:2496-2510) en su nivel bajo ✓.

### Q7 — TE 77/78 y ATOS: confirmado, sin uso en vendor

**Veredicto: refuerza r1.5.**

- **TE**: el pinctrl vendor (`soc/pinctrl@f000000/pmx_sde_te/`) define `sde_te_active`
  (gpio77 → función `mdp_vsync_p`, bias-pull-down, ds2) y `sde_te1_active` (gpio78 →
  `mdp_vsync_s`), PERO: (1) `/proc/interrupts` (`EX/15-common/interrupts.txt`) **no tiene ninguna
  línea msmgpio 77 ni 78** (las únicas msmgpio: 43, 170, 168, 169, 54, 128, 116); (2)
  `qcom,panel-te-source = <0>` en `qcom,dsi-display-primary`; (3) el panel es **video mode**
  (`dsi_video_mode`, non_burst_sync_event) → no necesita TE. Pines muxeados en DT pero jamás
  reclamados. No perder tiempo.
- **ATOS**: grep `atos` (case-insensitive) en todo `extracted-full/` (dmesg completo, debugfs
  listings, sysfs): **0 hits** → no existe en el kernel vendor 6.1.138. El walk C1 seguirá
  necesitando `/dev/mem` de NUESTRO kernel o el dump de SMMU (`msm.uke_smmu_dump=1`), como ya
  está planeado.

---

## (b) FIXES CONCRETOS PRIORIZADOS (para nuestro port)

### F1 — P0 · Ruta del ZAP: alinear package ↔ DT (una línea, sin compilar kernel)
**Fichero**: `build/pkg/uke-gpu-firmware/` (PKGBUILD/package). El mismatch está verificado:
DT `xiaomi-uke.dts:555` pide `qcom/uke/gen71100_zap.mbn` con carga directa SIN fallback
(`adreno_gpu.c:76-79`) y el package solo instala `usr/lib/firmware/qcom/gen71100_zap.mbn`.

```diff
--- a/build/pkg/uke-gpu-firmware/PKGBUILD (install= o sección package())
   install -Dm644 gen71100_zap.mbn "$pkgdir"/usr/lib/firmware/qcom/gen71100_zap.mbn
+  install -Dm644 gen71100_zap.mbn "$pkgdir"/usr/lib/firmware/qcom/uke/gen71100_zap.mbn
```
(Alternativa equivalente: cambiar el DT a `firmware-name = "qcom/gen71100_zap.mbn";` — pero eso
obliga a recompilar DTB; la del package es la de menor coste.) Hacerlo AMBOS a medio plazo para
no depender de qué blob se instala. Por qué: el zap es el PAS de entrada seguro; hoy el muro CM3
impide llegar a él, pero el primer boot que lo supere moriría ahí mismo con
`Unable to load qcom/uke/gen71100_zap.mbn`.

### F2 — P0/P1 · Hub a 200 MHz: corregir la tabla del RCG en gpucc-palawan
**Fichero**: `drivers/clk/qcom/gpucc-palawan.c` (cambio de C3, ahora con causa raíz cerrada).

```diff
--- a/drivers/clk/qcom/gpucc-palawan.c
@@ -153,8 +153,8 @@
-static const struct freq_tbl ftbl_gpu_cc_ff_clk_src[] = {
-	F(200000000, P_GPLL0_OUT_MAIN, 3, 0, 0),
-	{ }
-};
+/* GPLL0 corre a 1200 MHz en uke (ABL), no a 600 como en el vendor:
+ * 1200/6 = 200 MHz (vendor clk-summary: gcc_gpll0 600000000, hub 200000000). */
+static const struct freq_tbl ftbl_gpu_cc_ff_clk_src[] = {
+	F(200000000, P_GPLL0_OUT_MAIN, 6, 0, 0),
+	{ }
+};
```
Por qué: el vendor corre `hub=200 = gpll0(600)/3`; nuestro boot tiene GPLL0=1200 (medido:
`hub=400000000` = 1200/3 en `build/logs/consola/uke-sesion-console-antes-k23b.log:20482`). El RCG
solo tiene esa entrada y no puede dar 200 desde 1200. GATE G3-1: antes de fusionar, leer en
nuestro boot el rate real de `gcc_gpll0` (debugfs clk_summary o clk_debugfs) para confirmar 1200;
si fuera otro valor, usar pre_div = gpll0/200. El gate es gratis: `UKE-CM3DBG: hub=` ya imprime
el rate efectivo tras el fix (esperado `hub=200000000`).

### F3 — P2 · ACD: mantener OFF ahora; receta completa documentada para activarlo después
**No se toca nada hoy.** Cuando la GPU esté estable (muro CM3 caído + soak), activar ACD con la
tabla extraída del DT vendor (Q1) — el driver ya la consume si existe la prop:

```diff
--- a/arch/arm64/boot/dts/qcom/xiaomi-uke.dts (override de &gpu_opp_table)
 &gpu_opp_table {
 	opp-950000000 { qcom,opp-acd-level = <0xa8285ffd>; };
 	opp-900000000 { qcom,opp-acd-level = <0xa8285ffd>; };
 	opp-835000000 { qcom,opp-acd-level = <0xa8285ffd>; };
 	opp-736000000 { qcom,opp-acd-level = <0x88295ffd>; };
 	opp-684000000 { qcom,opp-acd-level = <0x88295ffd>; };
 	opp-633000000 { qcom,opp-acd-level = <0x88295ffd>; };
 	opp-500000000 { qcom,opp-acd-level = <0xa8295ffd>; };
 	opp-353000000 { qcom,opp-acd-level = <0x882c5ffd>; };
 	/* 255 MHz: el driver empieza el bucle en i=1 (frecuencia 0 dummy); sin prop */
 };
```
Con esto `a6xx_gmu_acd_probe` envía `qmp acd val:1` + tabla HFI → paridad con el vendor (sysfs
`acd=1`, IFPC 6366 entradas = beneficio térmico/energía real medido en la captura). Gate: tras
activar, verificar que no aparecen errores `Unable to enable ACD` / `Unable to ACD table`
(a6xx_hfi.c:877,884) y que el GPU sigue estable en 950 MHz sostenido.

### F4 — P2 · Recortar OPP 1000/1100 (bin del SKU: tope 950 TURBO_L0)
**Fichero**: `arch/arm64/boot/dts/qcom/xiaomi-uke.dts` (override del base palawan.dtsi):

```diff
--- a/arch/arm64/boot/dts/qcom/xiaomi-uke.dts
@@ &gpu {
 &gpu {
 	status = "okay";
 };
+
+/* El vendor uke (Adreno732, chipid 0x43030b00) binnea a 950 MHz TURBO_L0:
+ * 9 niveles exactos (sysfs num_pwrlevels=9, DT qcom,gpu-pwrlevel@0..8). Los OPP
+ * TURBO_L1/L2 del palawan.dtsi piden niveles de voltaje que este SKU no fusa. */
+&gpu_opp_table {
+	/delete-node/ opp-1000000000;
+	/delete-node/ opp-1100000000;
+};
```
Por qué: 9 niveles con votos DDR idénticos al vendor (verificados en Q6); elimina el riesgo de
que devfreq/thermal pida un nivel sin soporte de voltaje. Gate: `gpu_available_frequencies`
debería quedar `950 … 255` sin 1000/1100.

### F5 — P3 · Panel: nada estructural que cambiar; mejoras post-bring-up
Sin cambios ahora (Q4: supplies/reset/DSC/timings/backlight ya coinciden). Mejoras futuras del
driver `drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c` (NINGUNA bloquea):
1. Exponer 60 Hz (variante del timing 120 vía DFPS; vendor `timing@120` fps-list `120 60`) —
   útil para batería; requiere escribir el comando de timing-switch HS que hoy no implementamos.
2. Igual para 90/50/48/30 (timing@90, hfp 304) y 144 (hfp 18): los 3 modos ya están en
   `o82_modes[]` pero `num_modes = 1` por seguridad (el driver solo escribe los registros de
   120 Hz, b3=0x40 b2=0x91 — riesgo de imagen corrupta si se expone sin switch).
3. ESD 168/169: vendor lo lleva APAGADO en runtime; no portarlo.

---

## (c) RIESGOS Y GATES

| Gate | Qué | Cómo se valida |
|---|---|---|
| G3-1 (F2) | Rate real de GPLL0 en nuestro boot antes de fijar pre_div=6 | debugfs clk (`/sys/kernel/debug/clk/clk_summary` con `dmesg -n 7`) en el próximo boot Arch; esperado 120000000. Tras el fix: `UKE-CM3DBG hub=200000000`. Riesgo residual: si GPLL0 cambiara de rate por ABL distinto, hub queda a gpll0/6 ≠ 200 → el print lo delata. |
| G1 (F1) | Zap cargable ANTES de necesitarlo | Tras reinstalar el package: `ls usr/lib/firmware/qcom/uke/gen71100_zap.mbn` y en el próximo boot con GPU viva, ausencia de `Unable to load qcom/uke/gen71100_zap.mbn`. |
| G4 (F4) | Sin regresión de devfreq tras recortar OPP | `gpu_available_frequencies` = 9 niveles; burn 5 min a 950 MHz sin ESR/erange. |
| G5 | gmu-log NO capturado | Si hay otra captura Android: incluir `/sys/kernel/debug/kgsl/gmu_log` y `gmucore` (para versiones fw y CM3). Esta ronda no aporta nada nuevo de GMU. |
| R1 | `qcom,opp-acd-level` (F3) con fw vendor clonado: el ACD del GMU usa la tabla HFI; un valor mal copiado = hangs silenciosos | Solo tras soak verde; valores copiados literalmente del DT vivo (Q1), no inventados. |
| R2 | La evidencia `EX/` está gitignoreada | Este informe la referencia solo por rutas; no commitear el árbol. |

## Resumen ejecutivo
1. **ACD**: vendor ON (sysfs acd=1, IFPC con 6366 entradas, tabla `qcom,acd-level` en DT vivo);
   `acd_calibrate=0` es un knob de disparo, no estado. Nuestro `qmp_send(acd,0)` se mantiene
   durante el bring-up (harmless upstream); receta de activación documentada (F3).
2. **FW**: driver vendor pide nombres pelados (`gen71100_zap.mbn` → `/odm/firmware/` por ueventd;
   gmu/sqe → `/vendor/firmware/`). Nuestro port: zap con `firmware-name` + carga directa sin
   fallback → **mismatch `qcom/uke/` vs package `qcom/` localizado y con fix de 1 línea (F1)**.
3. **Hub**: 200 MHz exactos vendor (gpll0 600/3) vs **400 medidos en nuestro port** (gpll0 1200/3)
   → fix F2 en `gpucc-palawan.c` con gate G3-1.
4. **Panel o82**: paridad estructural casi total; diferencia real = 1 modo (120 Hz) vs 7 del
   vendor (DFPS sobre 3 timings); ESD declarado pero apagado en vendor.
5. **Freqs**: 9 niveles 255-950 con votos bus idénticos; recortar 1000/1100 (F4).
6. **TE 77/78 y ATOS**: confirmado sin uso/inaexistente en vendor.
