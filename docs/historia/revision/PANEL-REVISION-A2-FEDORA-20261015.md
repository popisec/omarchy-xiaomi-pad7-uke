# PANEL-REVISION A2 — Port Fedora Uke (senemos / linuxgamer) — 2026-10-15

Investigación externa del port Fedora de la Xiaomi Pad 7 (uke, SM7675) y de todo lo
relativo a su panel o82. **Veredicto central: el display DSC nativo NO funciona en
ninguno de los dos ports.** El port Fedora/senemos arranca escritorio por
**simpledrm (framebuffer del bootloader)**; su candidato DPU/DSI nativo registra
connector+framebuffer pero **"the panel remains black with repeated DSI errors"** y
está excluido del build normal. No hay combinación mágica funcionando que copiar, pero
el repo aporta material de altísimo valor: streams OEM completos del panel (2 variantes),
tabla de modos exacta con 3 grupos de reloj, catálogo DPU SM7675, y un test host que
**verifica aritméticamente** que el byte-clock x30 sobre el modo 60 Hz O82 da
**148,6485 MHz** (el valor vendor que perseguimos).

---

## 1. Ficha de repos

| Repo | URL | Qué es | HEAD (15-oct-2026) |
|---|---|---|---|
| uke-fedora | https://github.com/linuxgamer/uke-fedora | Hub del port ("Fork of other port, but with extra stuff"); README+assets+init.sh; submódulos hacia los otros 3 | `af8efc7` ("wtf??"); submódulos: uke-mainline-linux `fe53eb0`, uke-hardware `-b35ad5e`, rootfs `-a04be7d` |
| uke-mainline-linux | https://github.com/linuxgamer/uke-mainline-linux (espejo de https://github.com/MCC45TR/senemos-uke-kernel-mainline) | **El kernel**: meta-repo con `patches/` (40 parches 7.2.10 + 44 de 7.2.9), `configs/`, `src/display/` (candidato display completo), `src/boot/`, `tests/`, `manifests/`, `reports/` | `fe53eb0` (base kernel: Linux 7.2.9 rev 1.39; candidato display sobre 7.2.10 upstream `7b20d05fd38d…`, manifest `manifests/linux-7.2.10.json`) |
| uke-hardware | https://github.com/linuxgamer/uke-hardware | Paquetes Fedora (backlight KTZ8866, touch Novatek, sensores, boot) | `-b35ad5e` |
| palawan-linux | https://codeberg.org/palawan-mainline/linux | Kernel mainline SoC SM7675 ("Palawan") — donante del catálogo DPU y del soporte msm base (sin panel uke; QRD genérico) | `94a1e2329` |
| MCC45TR/uke-linux | https://github.com/MCC45TR/uke-linux | Repo del proyecto original con la **tabla de estado de hardware** y releases | clonado /tmp/uke-linux |

Notas de identidad: "senemas" (citado en nuestro proyecto como fuente de
`patches/display/7.2.10/0001`) = **senemos** (MCC45TR, Mürşit Can Cihan). El autor
linuxgamer es un espejo/derivado del port de MCC45TR ("Fork of other port"). La revisión
donante `cf4f9317` de uke-fedora (borrador O82 archivado) fue **borrada del remoto**
(rewriting de historia; `git fetch` da "not our ref", sin forks): solo sobrevive lo
destilado en `src/display/` de uke-mainline-linux.

## 2. Estado declarado del display (MCC45TR/uke-linux README, tabla 15-oct-2026)

- `Tablet screen / local TTY` 🟢 — consola local a **3200×2136** vía framebuffer del bootloader.
- `Native panel control / refresh switching` 🔴 — *"The isolated 60 Hz DPU/DSI candidate
  registers a connector and framebuffer, but the panel remains black with repeated DSI
  errors. Normal boots retain firmware scanout; other rates and adaptive sync are
  unavailable."* (uke-linux/README.md:105)
- `Firmware DRM` 🟡 — simpledrm para scanout + Adreno 732 experimental (Freedreno) para render.
- Touch Novatek NT36532 🟢, backlight KTZ8866 (banco dual, curva OEM) 🟡, GPU/OpenGL/Vulkan 🟡 experimental.
- `uke.config` solo activa `CONFIG_DRM_SIMPLEDRM=y`, `CONFIG_SYSFB_SIMPLEFB=y`;
  **ni CONFIG_DRM_MSM ni el panel O82 están en el build normal** (`patches/display/7.2.10/0001`
  "does not enable a native DT graph", `src/display/prepare-source.sh` solo lo prepara en
  un árbol aparte).

## 3. Configuración COMPLETA del display del candidato senemos

### 3.1 Driver de panel — `panel-xiaomi-o82` (creado por ellos)

Fichero: `/tmp/uke-mainline-linux/src/display/panel-xiaomi-o82.c` (349 líneas, no está
en mainline; se instala con el parche display 0001 sobre 7.2.10).

- Compatibles (`panel-xiaomi-o82.c:334-338`): `xiaomi,o82-36-02-0a` y `xiaomi,o82-42-02-0b`
  (dos variantes de panel; la unidad real del autor = 42_02_0b). Cada una con sus propios
  streams OEM (estructura `o82_profile`: `on`/`switch`/`off` por grupo de timing).
- Dual-DSI: `dsi[2]`; el secundario se registra contra el host del port@1 vía
  `of_graph_get_remote_node` + `mipi_dsi_device_register_full` (`:265-274`). Los comandos
  se envían **serializados a ambos links** (`o82_send`, `:56-87`); tipo 57=0x39 (DCS long
  write) LPM, se respeta delay_ms incluso si falla.
- DSC (`:275-282`): `dsc_version_major/minor = 1/1`, `slice_width = 800`,
  `slice_height = 24`, `slice_count = 2`, `bits_per_component = 10`,
  `bits_per_pixel = 8 << 4` (8 bpp comprimido), `block_pred_enable = true`.
- DSI (`:288-297`): `lanes = 4` en ambos links, `format = MIPI_DSI_FMT_RGB888`
  (comentario `:290-293`: "DSC carries the compressed stream. The isolated host patch
  uses DSC input depth for byte clocks, not this RGB888 container depth"),
  `mode_flags = MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_LPM` (**video mode, non-burst**;
  sin SYNC_PULSE, sin CLOCK_NON_CONTINUOUS, sin burst).
- Supplies (`:234-237`): `vddio` 1,9 V, `vsp` 5,8 V, `vsn` 5,8 V; load 300 mA c/u;
  power-down en orden inverso con msleep(2) por rail (`:101-125`).
- Reset (`:163-174`): GPIOD_ASIS en probe (conserva splash), secuencia
  0 →(10 ms)→ 1 →(3 ms)→ 0 →(3 ms)→ 1 →(15 ms)→ init streams.
- 7 modos fijos (`o82_get_modes`, `:206-226`): 30/48/50/60/90/120/144 Hz;
  **preferido = 60 Hz**; `bpc = 10`, 237×158 mm.
- Backlight: `drm_panel_of_backlight` → reutiliza el KTZ8866 apareado existente.

### 3.2 Modos y grupos de timing — `o82-data.h:928-935`

Panel **3200×2136** (landscape; 237×158 mm). Tres grupos de reloj OEM:

| Grupo | clock (kHz) | htotal | hfp/hs/hsu | vtotal por modo | Refresco | Modo |
|---|---|---|---|---|---|---|
| 0 | **967.428** | 3490 | 226/32/32 | 2310 → **120 Hz**; 4620 → **60 Hz** (vfp ×2: vsync_start 4472) | 60/120 | "120 Hz timing group" (el revisado; 60 Hz = modo preferido) |
| 1 | **1.097.712** | 3300 | 36/32/32 | 2310 | 144 | 144 Hz |
| 2 | **804.988** | 3872 | 608/32/32 | 6930/4331/4158/2310 | 30/48/50/**90** | grupo lento |

`src/display/README.md:12-14`: las tasas bajas extienden el front porch vertical
(cálculo downstream); "The first native test must use the 60 Hz mode from the reviewed
120 Hz timing group".

**Streams OEM** (`o82-data.h`, 936 líneas): 861 DCS long-writes + 18 short-writes por
variante×grupo, payloads ≤17 bytes, bancos 0xff 0x27/0x23/0x25/0x2a/0x26/0x22/0x20/0x10/0xf0,
delay 120 ms en Sleep-Out (0x11) y 20/100 ms en Display-Off/Sleep-In. **NO hay ningún PPS**:
payload máximo 17 bytes, ningún write de 128 bytes (PPS) ni registro 0xA0+ de parámetros DSC.
El PPS no se envía en ningún sitio de este port — gap reconocido
(`src/display/README.md:65`: "compare DSC PPS and PHY timings" = trabajo pendiente).

### 3.3 DSI host — hunk dsi_host.c (EL QUE YA COGIMOS, aquí identificado con precisión)

`patches/display/7.2.10/0001-native-display-providers.patch:358-371` — parchea
`drivers/gpu/drm/msm/dsi/dsi_host.c` en 7.2.10, dentro de `dsi_byte_clk_get_rate()`
(la versión 7.2.x de lo que era `dsi_calc_clk_rate_v2/6g`):

```diff
--- a/drivers/gpu/drm/msm/dsi/dsi_host.c
+++ b/drivers/gpu/drm/msm/dsi/dsi_host.c
@@ -658,6 +658,10 @@
 	unsigned long pclk_rate = dsi_get_pclk_rate(mode, msm_host->dsc, is_bonded_dsi);
 	unsigned long pclk_bpp;

+	/* Compression adjusted the pixel clock using DSC input component depth. */
+	if (msm_host->dsc)
+		bpp = msm_host->dsc->bits_per_component * 3;
+
 	if (lanes == 0) {
```

Contexto upstream 7.2.x (palawan `dsi_host.c:638-659`, igual en 7.2.10 vanilla):
`byte = pclk_comp_half * bpp / (8 * lanes)`. El hunk sustituye bpp (24 del RGB888) por
`bpc*3 = 30` **solo en el byte clock**. El pclk ya viene comprimido por
`dsi_adjust_pclk_for_compression()` (`dsi_host.c:595-614` upstream):

```c
new_hdisplay = DIV_ROUND_UP(hdisplay * drm_dsc_get_bpp_int(dsc), dsc->bits_per_component * 3);
new_htotal = mode->htotal - mode->hdisplay + new_hdisplay;
pclk = mult_frac(mode->clock * 1000u, new_htotal, mode->htotal);
```

**Y la fórmula de ACTIVE_H del host DSI** (`dsi_timing_setup`, `dsi_host.c:1003-1075` upstream):

```c
bool wide_bus_enabled = msm_dsi_host_is_wide_bus_enabled(...);   // = dsc && DSI >= 6G v2.5.0  → SIEMPRE true con DSC
if (wide_bus_enabled) {
    if (mode_flags & MIPI_DSI_MODE_VIDEO) bits_per_pclk = dsc->bits_per_component * 3;  // 30
    else bits_per_pclk = 48;
} else bits_per_pclk = 24;
hdisplay = DIV_ROUND_UP(msm_dsc_get_bytes_per_line(dsc) * 8, bits_per_pclk);
```

### 3.4 Números verificados por SU propio test host (claves para nosotros)

`tests/dsi-clock-contract.sh` ejecuta las funciones REALES del `dsi_host.c` preparado
(con el hunk aplicado) con el modo O82 60 Hz: `{clock=967428, hdisplay=3200, htotal=3490}`,
`dsc{bpc=10, bpp=8<<4}`, lanes=4, bonded:

- `dsi_byte_clk_get_rate(bonded)*8 == 1189188000` → **byte = 148,6485 MHz** (lane rate 1,189188 Gbps)
  → **coincide EXACTAMENTE con el 148,6 MHz vendor de nuestros ciclos L59-L72.**
- `bpc=8` → byte·8 = 1.129.312.800 (112,93 MHz).
- Sin DSC: 362.7855 MHz (bonded) / 725.571 MHz (no bonded).
- Derivado vanilla (sin hunk, bpp=24): 148,6485·24/30 = **118,9188 MHz** = nuestro 118,9.

Derivación pclk comprimido (60 Hz O82): new_hdisplay/intf = DIV_ROUND_UP(1600·8/30) = **427**
→ new_htotal = 1144 → pclk_comp_full ≈ 317,12 MHz → half ≈ 158,56 MHz →
byte·30/32 = 148,6485 MHz. **El 427 de nuestros registros = esta fórmula upstream (divisor /30).**

### 3.5 DPU/catálogo — `dpu_10_1_sm7675.h` (donante: Palawan `dpu_10_1_palawan.h`, commit `0d9f7fdf`)

- MDSS ver 10.1 (`:153-156`); DPU base 0xae01000; vbif sm8650.
- DSC (`:105-115`): `dce_0_0`(DSC_0) y `dce_0_1`(DSC_1) **comparten base 0x80000**
  ("slice DSC encoders so both share same base address"), + `dce_1_0`(DSC_2) @0x81000;
  todos con `.features = BIT(DPU_DSC_NATIVE_42x_EN)`.
- INTF (`:117-130`): `intf_1` @0x35000 (DSI ctrl 0) y `intf_2` @0x36000 (DSI ctrl 1),
  `prog_fetch_lines_worst_case = 24`, intr_underrun TOP0 bit 26/28, tear INTF1/2_TEAR bit 2.
- Perf (`:133-150`): max_bw_high 26.5 GB/s, min_prefill_lines 35, qos LUT sc7180
  ("explicitly unvalidated integration gate").

### 3.6 DT del display nativo — `sm7675-uke-native-display.dtso` (overlay offline, no arrancado)

Nodos (`sm7675-uke-native-display.dtso`):

| Nodo | Dirección | Clave |
|---|---|---|
| uke_mdss | `@ae00000` + handoff-vbif `@aeb0000` (0x1074) | `qcom,sm7675-mdss`; irq GIC SPI 83; `qcom,display-smmu`, `qcom,display-dispcc`; ICC mdp0-mem mmss_noc 21→mc_virt 512 |
| uke_dpu | `@ae01000` | `qcom,sm7675-dpu`; iommus `<&apps_smmu 0x1c00 0x2>`; OPPs MDP 200/342/402/514 MHz; ports 0→dsi0_in, 1→dsi1_in |
| uke_dsi0 | `@ae94000` | `qcom,mdss-dsi-ctrl`; clocks `byte, byte_intf, pixel, core, iface, bus`; `qcom,dual-dsi-mode; qcom,master-dsi; qcom,sync-dual-dsi`; **byte/pixel clks ← PHY PLLs** (`assigned-clock-parents` DSI_BYTE_PLL_CLK/DSI_PIXEL_PLL_CLK); `vdda-supply = &L3B` |
| uke_dsi1 | `@ae96000` | ídem sin master; `qcom,dual-dsi-mode` |
| uke_phy0/1 | `@ae95000` / `@ae97000` | `qcom,sm7675-dsi-phy-4nm` → **usa `dsi_phy_4nm_8650_cfgs`** ("Uke OEM: v5.2, two PHY windows and 98 mA vdds load", patch 0001:149-160); `vdds-supply = &L1B` |
| panel@0 | bajo dsi0 | `xiaomi,o82-42-02-0b`; vddio L8B, vsp/vsn regulators PMIC; `reset-gpios = <&tlmm 2 0>`; backlight = KTZ8866 primario; port@0→dsi0_out, port@1→dsi1_out; **data-lanes <0 1 2 3> ambos links** |
| dispcc | retarget | `qcom,sm7675-dispcc` + `syscon`; se le inyectan los 4 clocks de las 2 PHYs; **NO reconfigura las PLLs** ("Firmware still scans out until the MDSS handoff drains display DMA", patch 0001:131-137) |

No hay propiedades widebus en DT: en mainline widebus sale automático con DSC (v2.5.0+).

### 3.7 Plomería del handoff (lo que probablemente nos falte a nosotros)

- `src/display/uke-mdss-handoff.c`: al sondear el MDSS — verifica revisión HW `0xa001`,
  **hala el VBIF de display (halt XINs 0/1/4/5/9/13/14, espera ack en +0x204), asserts
  DISP_CC_MDSS_CORE_BCR (0x8000 bit0), retira los SMRs 0x1c00/mask-2 del SMMU de boot,
  deassert, y solo entonces reanuda**. Hasta entonces el MDSS pide ICC fija
  **8 GB/s** (patch 0001 `msm_mdss.c`: `Bps_to_icc(8000000000ULL)` mientras
  `!uke_handoff_complete`) y **salta el reset de mdss** y la lectura de versión.
- `src/display/uke-display-smmu.c`: solo retira SMRs unsecure (SID 0x1c00 mask 2),
  conserva context banks viejos reservados; dominios display nuevos en otro banco.
- `src/display/uke-dispcc-votes.c`: tablas de tensión/rate OEM del vendor
  (commit Xiaomi `5712080a`): vdd_mm PLL 615M/1.1G/1.6G/2G; **mdp 155/200/342/402/514/600M;
  byte 140.63/187.5/300/358M; pixel 225/300/480/625M**; ops vendedoras
  (clk_byte2_ops/clk_pixel_ops/rcg2_shared) sobre los clocks sm8550-dispcc existentes;
  proxy vote hasta sync_state. Frec tabla MDP src (patch 0001): …342/402/514/600 MHz.
- ICC: `cliffs-display-icc.h` — MASTER_MDP (qnm_mdp, 2 canales, buswidth 32, qosbox
  0xad000/0xae000) → qns_mem_noc_hf → qnm_mnoc_hf; qhs_display_cfg en CN1; mmss_noc nuevo
  `"qcom,cliffs-mmss_noc"`.
- Panel-handoff para simpledrm: `patches/7.2.10/0038-uke-handoff-panel-metadata.patch`
  (completo abajo).

## 4. Diffs completos de display

### 4.1 `patches/display/7.2.10/0001-native-display-providers.patch` (370 líneas — las partes C)

**dpu_hw_catalog.c** `+ #include "catalog/dpu_10_1_sm7675.h"` tras dpu_10_0_sm8650 (línea 796 upstream).
**dpu_hw_catalog.h** `+ extern const struct dpu_mdss_cfg dpu_sm7675_cfg;`.
**dpu_kms.c** dt_match `+ { .compatible = "qcom,sm7675-dpu", .data = &dpu_sm7675_cfg },`.
**panel/Makefile + Kconfig**: `obj-$(CONFIG_DRM_PANEL_XIAOMI_O82) += panel-xiaomi-o82.o`; tristate experimental.
**dispcc-sm8550.c**:
- nueva `ftbl_disp_cc_mdss_mdp_clk_src_sm7675`: 19.2M(tcxo)/85.7M/100M/155M/200M/342M/402M/514M/600M.
- desc `const` → mutable; match `+ { .compatible = "qcom,sm7675-dispcc" }`; `#include "uke-dispcc-votes.c"`;
  en probe: si sm7675 → `uke_dispcc_voltage_init()` y freq_tbl sm7675;
  **no ejecuta `clk_lucid_ole_pll_configure`** para sm7675 (firmware scanout vivo);
  `.sync_state = uke_dispcc_sync_state`.
**dsi_phy.c**: `+ { .compatible = "qcom,sm7675-dsi-phy-4nm", .data = &dsi_phy_4nm_8650_cfgs }` ("Uke OEM: v5.2, two PHY windows and 98 mA vdds load").
**qnoc-cliffs-usb.c**: incluye `cliffs-display-icc.h`; añade qhs_display_cfg a qsm_cfg y bcm_cn1,
qnm_mnoc_hf a bcm_sh1 y gem_noc, SLAVE_DISPLAY_CFG=524 en cnoc_cfg_nodes, MASTER_MNOC_HF_MEM_NOC=23
en gem_noc_nodes, match `+ { .compatible = "qcom,cliffs-mmss_noc", .data = &cliffs_mmss_noc }`.
**arm-smmu.h/qcom.c**: flag `uke_display_quiesced`; `#include "uke-display-smmu.c"`;
alloc_context_bank especial para display (valida actlr contra OEM, banco libre);
impl `.init_context = qcom_uke_display_init_context`.
**msm_mdss.c**: `#include "uke-mdss-handoff.c"`; sm7675: ICC mínima 8 GB/s hasta handoff,
exige paths ICC, salta msm_mdss_reset() y lectura de versión hasta `uke_handoff_complete`,
llama `uke_mdss_handoff(mdss)` en probe; match `+ { .compatible = "qcom,sm7675-mdss", .data = &data_57k }`.
**dsi_host.c**: hunk completo en §3.3 (única línea lógica: `bpp = dsc->bits_per_component * 3` en
`dsi_byte_clk_get_rate`).

(Tal cual: `/tmp/uke-mainline-linux/patches/display/7.2.10/0001-native-display-providers.patch`.)

### 4.2 `patches/7.2.10/0038-uke-handoff-panel-metadata.patch` (34 líneas, completo)

```diff
Subject: [PATCH] drm/sysfb: identify the Uke firmware handoff as an internal DSI panel

The admitted Uke handoff describes its physical panel through the standard
simple-framebuffer panel phandle. Keep other framebuffer connectors unchanged.
This enables desktop backlight matching; native DPU/DSI modes remain separate.

--- a/drivers/gpu/drm/sysfb/simpledrm.c
+++ b/drivers/gpu/drm/sysfb/simpledrm.c
@@ -652,6 +652,7 @@
 	struct drm_device *dev;
 	int width, height, stride;
 	u16 width_mm = 0, height_mm = 0;
+	bool uke_internal_panel = false;
 	struct device_node *panel_node;
 	const struct drm_format_info *format;
 	struct resource *res, *mem = NULL;
@@ -731,6 +732,9 @@
 			ret = simplefb_get_panel_height_mm_of(dev, panel_node);
 			if (ret > 0)
 				height_mm = ret;
+			uke_internal_panel = width_mm && height_mm &&
+				of_machine_is_compatible("xiaomi,uke") &&
+				of_device_is_compatible(panel_node, "xiaomi,uke-panel-handoff");
 			of_node_put(panel_node);
 		}
 	} else {
@@ -868,6 +872,7 @@

 	connector = &sdev->connector;
 	ret = drm_connector_init(dev, connector, &simpledrm_connector_funcs,
+				 uke_internal_panel ? DRM_MODE_CONNECTOR_DSI :
 				 DRM_MODE_CONNECTOR_Unknown);
 	if (ret)
 		return ERR_PTR(ret);
```

### 4.3 Resto de parches (40 en `patches/7.2.10/`, 44 en `patches/7.2.9/`)

Ninguno más toca display (clock handoff, rpmh, tlmm, icc, smmu, usb, dts `0007-uke-independent-dts`
— DT de arranque **sin nodos de display**, UFS, wlan, backlight KTZ8866 `0022/0025/0034`,
GPU adreno732 `0036/0037`, epss `0040`). Boot: `patches/boot/0001-arm64-uke-abl-dt-hook.patch`
(hook ABL: traduce el DT del bootloader — conserva framebuffer/SMMU rules; `src/boot/uke-abl.c`).

## 5. Tabla comparativa: senemos vs nuestro estado L71 (mundo 24 vendor + byte x30)

Modo de referencia: O82 60 Hz (grupo 0): 3200×2136, clock 967.428 kHz, htotal 3490, vtotal 4620; DSC 10bpc→8bpp, slices 800×24 ×2/link, dual-DSI bonded video-mode.

| Parámetro | senemos (candidato 7.2.10) | upstream 7.2.x vanilla | nuestro L71 (vendor "mundo 24") | Evidencia senemos (fichero:línea) |
|---|---|---|---|---|
| Byte clock | **x30 → 148,6485 MHz** | x24 → 118,9188 MHz | x30 → 148,6 MHz (ya tomado, dsi_host.c:644) | tests/dsi-clock-contract.sh (assert 1189188000) |
| ACTIVE_H host DSI (por INTF) | **427** (widebus ON implícito, bits_per_pclk = bpc·3 = 30) | 427 | **534** (bits_per_pclk 24) | dsi_host.c upstream 1045-1067 (palawan :1035-1067) |
| Widebus DSI | **ON (forzado por msm con DSC ≥v2.5.0)** — video mode | ON | **OFF (mundo 24)** | dsi_host.c:796-800 msm_dsi_host_is_wide_bus_enabled |
| Divisor INTF DPU | **/30 sin tocar** (no parchea dpu intf) | /30 | /24 | patch 0001 no toca dpu_hw_intf/dpu_encoder |
| Panel | panel-xiaomi-o82 propio; DSC 8bpp/10bpc, slice 800×24×2, block-pred | — | (nuestro driver) | panel-xiaomi-o82.c:275-296 |
| PPS al panel | **NO se envía (gap reconocido)** | — | (¿lo enviamos? verificar) | src/display/README.md:65; o82-data.h max 17 bytes |
| Modo/timings | 3200×2136; grupo 0: 967.428 MHz; 60 Hz = vtotal 4620 | — | (nuestros 427/534 implican 3200 ancho) | o82-data.h:928-935 |
| INIT panel | 861 long-writes OEM por grupo (2 variantes) | — | — | o82-data.h |
| Scanout real | **simpledrm** (nativo negro + errores DSI) | — | (nuestro: sin contenido + flood FIFO) | uke-linux/README.md:105 |

**Lectura clave:** senemos también falla, pero en el **mundo mixto opuesto**: byte x30
(148,6 MHz, = vendor) **manteniendo ACTIVE_H 427 y /30** (mainline). Nosotros probamos el
mundo vendor completo (534 + /24 + byte x30) y fallamos con flood FIFO. El byte x30 está
verificado dos veces (vendor y su test host). El 534 vendor implica `bits_per_pclk=24` en la
fórmula de `dsi_timing_setup` — que en mainline solo ocurre con widebus OFF, mientras el
byte x30 (bpc·3) es exactamente la rama **widebus ON + video mode**. Es decir, en el vendor
los dos divisores conviven (DSI serializa 30 bits-equivalentes/pclk comprimidos mientras la
ruta INTF→DSI mueve 24 bits/pclk); en mainline ambas cosas cuelgan del mismo booleano
`wide_bus_enabled`, por eso el vanilla no puede expresar el mundo vendor sin parchear.

## 6. Diferencias accionables concretas

1. **byte x30 confirmado** (ya lo teníamos): `bpp = dsc->bits_per_component*3` en
   `dsi_byte_clk_get_rate` (7.2.10 ~línea 658). El 148,6485 MHz sobre el modo 967.428 kHz
   está verificado por el test host de senemos.
2. **Probar el mundo mixto de senemos** (ACTIVE_H 427 + byte x30): para replicarlo solo
   hace falta el hunk de dsi_host (nada más): widebus vuelve a ON automático y
   `dsi_timing_setup` recalcula hdisplay a 427. Nuestro L71 forzó 534; senemos dejó 427.
   Es una celda de matriz que no habíamos probado (nosotros venimos de 427+/30+byte118,9 →
   ahora 534+/24+byte148,6; falta 427+/30+byte148,6 y 534+/24+byte118,9).
3. **PPS: hueco común a ambos ports.** El panel o82 recibe su PPS desde el DT vendor
   (`dsi-panel-o82-42-02-0b-dualdsi-dsc-lcd-video.dtsi`, propiedad tipo
   `qcom,mdss-dsc-pps`); senemos NO lo transmite (driver sin PPS; README lo lista como
   pendiente: "compare DSC PPS and PHY timings"). Si nuestro port tampoco envía el PPS OEM
   (128 bytes) el decodificador DSC del panel queda mal configurado → negro. **El PPS hay
   que sacarlo del vendor**: Xiaomi kernel commit `5712080a4b0c0b1a879e6d145c601c649ddaddfd`
   y display DT `4a3e1c391130237c5e8c2b250d1c94f3e25b9b11` (los SHAs están pinned en
   `src/display/README.md:30-39`; el repo senemos deliberadamente no distribuye los dtsi,
   solo los streams de comandos).
4. **Init OEM**: comparar nuestra secuencia init con `o82-data.h` (variante 42_02_0b):
   861 long-writes, sleep-out con 120 ms, switches de grupo vía 0xff 0x10/0xb2/0xb3. Si
   nuestra secuencia no es la OEM completa, el panel queda en otro estado.
5. **Handoff VBIF/SMMU/ICC**: si nuestro intento nativo no hace el drenaje
   (`uke-mdss-handoff.c`: halt XINs VBIF + reset CORE_BCR + retiro SMR 0x1c00 + ICC 8 GB/s
   previa) podemos tener fallos DSI por DMA/fabric viejo del splash — candidato directo para
   explicar el "flood FIFO" (underrun = no llega dato, típico cuando el SMMU/VBIF sigue
   mapeando el dominio viejo o el ICC está en mínimo).
6. **PHY**: usan `dsi_phy_4nm_8650_cfgs` para `qcom,sm7675-dsi-phy-4nm` — comprobar qué
   cfgs usa nuestro PHY; el clock provider del byte clock viene del PLL de la PHY
   (`assigned-clock-parents`), no de dispcc.
7. **Anomalía interna detectada en senemos** (aprovechable): el overlay DT declara
   `interrupts = <0 83 4>` en mdss (SPI 83, como palawan.dtsi:3339) pero su propio test
   `tests/native-display-dt-contract.sh:17` exige `'0 53 4'`. El DT de arranque ABL
   probablemente usa SPI 53. Revisar qué SPI usa nuestro mdss (83 vs 53) — si está mal,
   o no llega interrupción o llegan de otra fuente.
8. **Tablas de rate OEM** (`uke-dispcc-votes.c`): byte máx 358 MHz @ VDD_LOW_L1 — el
   148,65 MHz está holgado; pixel 625 MHz; MDP 600 MHz. Útiles para validar que nuestros
   votes DISPCC cubren el modo.

## 7. Rutas locales (dejar para otros agentes)

- `/tmp/uke-fedora` — hub (con submódulos; incluye `assets/screenshots/uke-fedora-kde-2026-10-14.png`)
- `/tmp/uke-mainline-linux` — **kernel meta-repo** (patches/, src/display/, tests/, configs/, manifests/, reports/)
- `/tmp/uke-hardware` — paquetes Fedora (backlight/touch/sensores)
- `/tmp/uke-linux` — MCC45TR/uke-linux (tabla de estado de hardware, releases)
- `/tmp/palawan-linux` — kernel SoC Palawan (Codeberg) con drivers/gpu/drm/msm 7.2.x de referencia
  (dsi_host.c, dpu_10_1_palawan.h, palawan.dtsi)

Ficheros display senemos (ruta exacta bajo /tmp/uke-mainline-linux/src/display/):
`panel-xiaomi-o82.c`, `o82-data.h`, `o82-data.cpp` (decodificador host), `o82-oem.dts`,
`sm7675-uke-native-display.dtso`, `dpu_10_1_sm7675.h`, `uke-mdss-handoff.c`,
`uke-display-smmu.c`, `uke-dispcc-votes.c`, `cliffs-display-icc.h`, `qcom-uke-display.h`,
`prepare-source.sh`, `README.md`.

## 8. Conclusión para el gate

- El "senemas/senemos" citado como fuente de `patches/display/7.2.10/0001` es
  MCC45TR/senemos-uke-kernel-mainline; su hunk dsi_host = byte x30 (ya integrado por
  nosotros). No aportan una solución funcionando; **nadie ha hecho scanout DSC estable en uke**.
- Lo nuevo aprovechable: (a) el modo OEM 60 Hz exacto (967.428 MHz / htotal 3490 / vtotal 4620),
  (b) streams init OEM completos de las dos variantes, (c) la verificación aritmética del
  148,6485 MHz, (d) el handoff VBIF/SMMU/ICC de 8 GB/s como causa probable de floods,
  (e) la pista de que falta el PPS OEM en ambos ports (extraerlo del vendor kernel `5712080a`),
  (f) la matriz de mundos incompleta: probar 427+/30+byte148,6 (el suyo, también negro,
  descarta el mundo mixto) y contrastar SPI de interrupción 53 vs 83.
