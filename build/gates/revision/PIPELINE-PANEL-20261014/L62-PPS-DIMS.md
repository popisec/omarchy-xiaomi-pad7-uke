# L62 — PPS con dims por link (1600x2136, no 3200) · 14-oct-2026

## 1. Hallazgo: dims a 0 REFUTADO; el valor real era FULL (con fichero:línea)
- `dsi_host.c:1750` (`dsi_host_attach`): `msm_host->dsc = dsi->dsc`, y el
  panel hace `ctx->dsi[i]->dsc = &ctx->dsc` (`panel:864`, attach `:866`):
  **el host y el panel comparten el MISMO struct** (ambos links).
- `dsi_timing_setup()` (`dsi_host.c:989`, fill `:1034-1035`) corre en
  `msm_dsi_host_power_on` (`:2564`) ← `dsi_mgr_bridge_power_on`
  (`dsi_manager.c:213`) ← pre_enable del bridge DSI, **ANTES del prepare
  del panel** (el propio comentario `:245-248` lo dice). Deja
  `pic_width = mode->hdisplay` FULL + RC calculados
  (`dsi_populate_dsc_params`, `:1898`: const/RC/scale/line_buf/chunk).
- `dsi_mgr_bridge_mode_set` (`dsi_manager.c:406-408`) guarda el modo FULL
  (3200x2136) en ambos hosts ⇒ **L59 empaquetó pic 3200x2136 por link**.
- El packer (`drm_dsc_helper.c:99-...`) copia TODO del config: dims, RC,
  delays, offsets, flatness, model_size — con el fill del host, solo las
  dims estaban mal, el resto válido (prueba: commit OK, `dsc=85 85`).
- Premisa "0" de CRITICA-L59 §4 y nota L40: ordering invertido; se corrige
  en este diff (la nota vieja se sustituye).

## 2. Por qué 1600x2136 por link
Cada link lleva 1600 px (vendor `timing@120`: 1600 activos; split bonded
`hdisplay/=2` en `dsi_timing_setup`; informe DSC: bytes/línea/interfaz =
1600). VESA DSC: pic_width = slices × slice_width de la interfaz =
2×800 = **1600** (con 3200 salen "4 slices" que no existen). El host NO usa
pic_width para sus registros (`dsi_update_dsc_timing`, `:927`: solo
slices/chunk) ⇒ el cambio solo afecta a la PPS del panel.

## 3. Cambio (`/tmp/ukefix/l62-pps-dims.diff`, dry-run + reverse OK)
Copia local `dsc_link = ctx->dsc` (el compartido con el host NO se toca);
`pic_width = desc->modes[0].hdisplay/2`, `pic_height = vdisplay`; pack de
la copia; gate `UKE-L62: PPS dims=%ux%u por link (host=%ux%u)`.

## 4. Gates / criterio
- Fuente+binario: `UKE-L62` ×1 (strings + fuente).
- Vivo: `dmesg | grep UKE-L62` ⇒ `dims=1600x2136 por link (host=3200x2136)`
  confirma el hallazgo §1 empíricamente.
- **PASA = CONTENIDO en pantalla. FALLA (negro con dims OK) ⇒ siguiente =
  `print_hex_dump` del PPS (128 B, `BUILD_BUG_ON`) vs bytes vendor**; no
  apilar (orden PPS vs 0x11/0x29 y DCS largo vs short, en reserva).

## 5. Rollback
L59 `e3511595de6b…89534e` / L58 `763d7869795e…98550`. NO build (ejecutor).
