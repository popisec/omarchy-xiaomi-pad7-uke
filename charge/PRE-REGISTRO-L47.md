# PRE-REGISTRO L47 — migas del enable-path + `FBDEV_EMULATION=n` (14-oct-2026, tarde)

> Fila lista para el ledger ANTES de flashear. **NO flasheado aún** (crítica en curso → build).

## Qué es

`L47 = L46 + 7 migas nuevas del camino pre-CRTC-enable + CONFIG_DRM_FBDEV_EMULATION=n`.

- **Motivo (H2, `H2-CRASH-CAPTURADO-20261014.md`)**: con display-ON el boot muere tras el
  modeset del fbcon (`fbcon_init: unhandled fb_set_par error -16`, `Console: switching to
  colour frame buffer device 400x133`, `sys_imageblit/sys_fillrect: framebuffer is not in
  virtual address space`) y **de los 21 tags K47 ya presentes solo dispararon `tx-alloc` +
  `pan-modes`** ⇒ la muerte es **antes del CRTC enable** (commit/DPU/kms).
- **Migas nuevas** (×1 c/u, parche `l47-migas-enable.diff`, verificado): `K47-atom-tail`
  (msm_atomic_commit_tail), `K47-dpu-hw-in` (dpu_kms_hw_init), `K47-kms-en-commit`
  (dpu_kms_enable_commit), `K47-dpu-res` (dpu_runtime_resume), `K47-enc-en`
  (dpu_encoder_virt_atomic_enable), `K47-brg-pre-en` (dsi_mgr_bridge_pre_enable),
  `K47-mgr-phy-en` (dsi_mgr_phy_enable). (`K47-crtc-en` y `K47-phy-en` ya existían.)
- **Variable**: `FBDEV_EMULATION=n` (era la config de la era L33; sin fbcon no hay
  auto-modeset al arrancar).

## Artefactos (a completar con el build)

- Kernel: `build/kernel-pokes/k52L47-build/` (config `build/kernel-config/k52L47.config`).
- Boot: `build/bootimg/boot-uke-k52L47.img` (repack display-ON, cmdline 566 B) — **sha256
  `b320616bc4414537ac5bc5d2277c064bcd9ab23edf2de98251ff47027f0660d0`** (Image.gz `4c9a334c…`).
  Gates: 7 migas ×1 + FBDEV=n efectivo (drmfb=0) + L11/L43/L44/L45/L46 intactos.
- **dtbo: s287 se queda** (sin cambios).

## Criterio pasa/falla (4 ramas prefijadas — CRITICA-L47 §3.1)

- **PASA-A**: vive >6 min con `=n` y **sin `K47-atom-tail`** ⇒ `=n` retira el trigger de
  boot; **modetest OBLIGATORIO en el mismo ciclo** (sin escritura extra).
- **PASA-B**: el modetest completa el modeset **sin muerte** (con o sin luz) ⇒ el enable-path
  funciona sin fbcon; el asesino era del cliente fbdev/takeover. Siguiente: vci/DCS con
  modeset userspace.
- **FALLA-B**: muerte **con `K47-atom-tail`** (+ migas hasta el punto X) ⇒ H2-fbdev
  confirmado como trigger; el asesino está en X (última miga impresa). Siguiente: clocks/
  GDSC en X.
- **FALLA-A**: muerte en la ventana 47–70 s con `=n` pero **SIN `atom-tail`** ⇒ **H2-fbdev
  REFUTADO** como trigger (muerte independiente del modeset); releer H2.
- **FALLA-C**: muerte <20 s (estilo L33/L39) ⇒ otra vía; no concluye sobre H2.
- **INCONCLUYENTE**: 0 B / sin SSH con batería <gate (E3).
- Regla de lectura (E6 bien aplicado): la última miga = «murió EN o DESPUÉS»; `dpu-res`/
  `dpu-hw-in` aislados NO valen (solo en la secuencia `atom-tail → kms-en-commit → dpu-res`).

## Runbook

1. `fastboot flash boot_a` L47 + `set_active a` + reboot (dtbo intacto).
2. Verificar: SSH; uptime >5 min; `dmesg | grep K47` (qué migas dispararon); `card1-DSI-1` status.
3. Si vive: **solo lectura** `modetest -M msm-kms -c` (medido: abre card1 y lista; `-M msm`
   da `drmModeGetResources failed`) → ver `card1-DSI-1: connected` + modos; después **UN SOLO
   INTENTO** `modetest -M msm-kms -s 36@<crtc>:<modo>` con un modo **DE LA LISTA** (prohibido
   inventar 60 Hz). Si cuelga: reset físico, parar (sin 2º intento hoy), fallback reflash L45.
   Ojo riesgo-slot (H2 quemó a:6→0 en ~5 boots) y R-42 (sin recuperación automática).
4. Doble captura (ACM + `uke-dump`); si muere: dumps + último K47.

## Rollback

`fastboot flash boot_a` L45 `83647c454709c1e895ef9904879cff79b3ed8ac7196988cec104b6711ccab059`
(o L46 `32cc4329…`); dtbo s287 intacto.
