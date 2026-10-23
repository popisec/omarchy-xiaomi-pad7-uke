# H2 CAPTURADO — La muerte del boot display-ON es del **enable del display** (14-oct-2026, sesión #620+)

> Experimento: re-flash de L46 (`32cc4329…`) + `dtbo s287` con el **volcador `uke-dump`**
> (dmesg cada 20 s → LOGFS gzip, instalado hoy). La tablet crash-loopó (~50-60 s por boot,
> no 13 min: los «13 min» de la mañana incluían el tiempo en fastboot) hasta agotar el slot
> (a: 6→0, `unbootable:yes`) → fastboot. **Evidencia: `out/h2-dumps/uke-{8,28,48}.txt.gz`**
> (el boot caído) + la serie `uke-6780…6901` (boot L45 display-off, control).

## 1. La cronología del boot que muere (dump `uke-48`, el último)

| t (s) | Evento (dmesg) |
|---|---|
| 8.28 | **Oops** `000000008600000f` — `Comm: insmod`, `Modules: ucsi_glink(O+) pmic_glink(O)`, `lr: fwnode_get_name+0x38`. **No fatal** (el boot sigue). Issue aparte (módulos OOT). |
| 47.041 | `panel-xiaomi-o82-dualdsi ae94000.dsi.0: UKE-L45: backlight externo resuelto` → **probe del panel OK** (el 5º intento, gatillo del táctil). |
| 47.043 | `K47-tx-alloc` ×2 (dsi_host.c:1248) — se asigna un transfer DSI. |
| 47.045/47.052 | `K47-pan-modes` ×2 (panel:488, `o82_get_modes`) — **el DRM pide los modos**. |
| 47.045 | `UKE-P82: get_modes: entrada` → **`fbcon_init: detected unhandled fb_set_par error, error code -16`** → `Console: switching to colour frame buffer device 400x133` → **`fb0: sys_imageblit/sys_fillrect: framebuffer is not in virtual address space`** → `fb0: msm-kmsdrmfb frame buffer device` → 2º `pan-modes` (uke-48:2926-2933; son el eslabón get_modes→fbdev-setup→commit). |
| 47.05 | Burst `sync_state() pending due to …` de **`disp_cc-sm8550`** y `gcc-palawan`: mdss_mdp, **dsi_ctrl0/1**, dp_display, smmu_sde, dsi-display-primary, wb-display@1/2… → **los clocks del display se están habilitando**. |
| 47.05→47.6 | Cola normal (audit, ufs clk). |
| **48–68** | **SILENCIO** (el dump de t=68 s no existe) → **reset duro** (`pureason=0x80100`; el reboot limpio es 0x800001). |

**No aparece `K47-pan-prep`** (panel:352, el inicio de `o82_prepare`) ni `K47-pre-rst`, ni
`K47-host-xfer` (dsi_host.c:1791), ni **S4-DIAG** (0 líneas: no hubo timeout DSI).
⇒ **La muerte es ANTES del `prepare()` del panel y del DCS**: en el **enable del DRM/DSI**
(CRTC/encoder enable → clocks/GDSC/PHY), justo cuando `disp_cc`/`gcc` habilitan los clocks del
display. El DCS (el crux clásico) **no llegó a ejecutarse** en este ciclo.

## 2. Control (display-off): la serie `uke-6780…6901` (boot L45+s287)

- `card1-DSI-1: disconnected` (por `video=DSI-1:d`), `UKE-L45=1` (probe OK a 47 s), `K47=2`
  (solo `tx-alloc`), sin modeset, **sin muerte** (uptime 6901 s = 1.9 h).
- ⇒ El factor desencadenante es el **modeset con display-ON**, no el probe ni el vci.

## 3. Consecuencias

1. **H2 no es un bug nuevo**: es la familia «silencio» de siempre, pero **localizada en el
   enable del display** (clocks/GDSC), no en el DCS. La prioridad se reordena:
   **enable-path ≺ DCS**.
2. **vci sigue sin probarse** (no hubo `prepare`): el ciclo no refuta vci.
3. **El Oops de 8.28 s** (pmic_glink/ucsi_glink, `insmod`, OOT) es no-fatal pero ensucia la
   ventana temprana; anotado como issue aparte.
4. **Instrumentación**: los marcadores K47 cubren probe/modes/prepare/xfer; para el
   enable-path hacen falta migas en el camino de clocks/GDSC/PHY del DPU/DSI (próximo ciclo).
5. **Línea de investigación siguiente** (hipótesis, marcada como tal): el enable de los clocks
   del display con el RCG compartido (`clk_rcg2` `parked_cfg`, ROADMAP FASE 1 /
   `docs/historia/revision/ANDROID-POWER-DPU-20261013.md`) y/o los GDSC (`pd_ignore_unused` en cmdline). La firma
   (silencio tras `sync_state` de disp_cc) es compatible.

## 4. Estado tras el experimento

- **L45 restaurado** (`83647c45…`, 1 escritura) + s287; panel OK (probe 47 s, card1
  disconnected por `:d`), dumper activo, slot a rehabilitado (`set_active a`).
- Evidencia: `out/h2-dumps/` (10 dumps) commiteada. Volcador: rootfs (`uke-dump.service`,
  LOGFS) + initramfs k22b (`fa40a1bb…`, PARTLABEL) listos para el próximo repack.

## 5. Notas de la crítica L47 (añadidas 14-oct)

- El `-16` del `fb_set_par` es **EBUSY/marcador, no asesino** (el boot sigue hasta 47.6 s).
- Divergencia anotada: el `k39.config` **versionado** dice `FBDEV=y` pero el **real** de
  `k52L39-build/.config:4861` era `=n` (y L33 igual, `k52L33-build/.config:4861`) — la era
  L33/L39 llevaba `=n` real; L39 murió a <3.5 s (44 s antes de la ventana H2) ⇒ no testea
  H2-fbdev. Con `=n` el sistema vive y el modeset lo dispara userspace (diseño L47+modetest).
- Mecanismo `=n` verificado en árbol: `drm_client_setup()` (`drivers/gpu/drm/clients/drm_client_setup.c:42-53`)
  no hace nada con `=n`; `msm_drm_kms_post_init` (`msm_kms.c:399`) la llama siempre.
