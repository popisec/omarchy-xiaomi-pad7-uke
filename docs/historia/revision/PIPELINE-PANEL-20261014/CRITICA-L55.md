# CRÍTICA L55 — Backlight interno DCS 0x51 — 14-oct-2026 (solo lectura)

Árbol verificado: `build/kernel-pokes/k52-L16-tree/.../panel-xiaomi-o82-dualdsi.c` (diff ya aplicado).

## 1. Diff: CORRECTO, revierte L44 fielmente
- `o82_bl_update_status` aplicado ≡ k47 original (`k47-fuentes/...:462-500`, difiere
  solo en corte de ventana del `diff`; payload `{MSB,LSB}` por
  `mipi_dsi_dcs_set_display_brightness_large` en ambos links = `drm_mipi_dsi.c:1501-1513` OK).
- Limpio: cero llamadas a `drm_panel_of_backlight` en código (2 menciones solo en
  comentarios `:47,:831`), `UKE-L45` ×0, campo `backlight` usado, sin restos L44/L45.
- Enable en prepare tras display-on (`:439-440`) / disable en unprepare (`:466`):
  simétricos, no-herencia; en herencia ambos saltan (correcto: no tocar panel vivo).
- Compilación: sin strings partidos, llaves 71/71, `clamp` sin include explícito como
  otros paneles (`st7701.c`), `backlight.h` da enable/disable NULL-safe + `bl_get_data` +
  `BACKLIGHT_SCALE_NON_LINEAR`. Riesgo compile ≈ 0. Declaración tras `uke_poke` es C99-OK.

## 2. DCS 0x51: correcto; 2 matices
- (a) El enable **ATENÚA**: el init programa `0x51=0x0FFF` (`:188-189`) y el enable
  reescribe INIT `0x133` (307). Si hay luz débil, puede pasarse por alto.
  **Corrección**: INIT a `0xFFF` para el primer encendido, o barrido sysfs en runbook.
- (b) `0x53=0x24` ya está en el init (`:189`); omitirlo en runtime es correcto.
  Incertidumbre asumida por el preparador (HIPÓTESIS §3): que el 0x51 mueva LEDs sin
  boost del KTZ no está probado — este ciclo lo discrimina. OK.

## 3. Convivencia: OK
- KTZ huérfano sin updates del core (nombres sysfs distintos: `ae94000.dsi.0` vs
  `dev_name(client)` del KTZ → sin colisión `-EEXIST`). Su `update_status` propio en
  probe es preexistente e inocuo. Perder el defer L45 no importa (el interno no usa I2C).
- Gate sysfs `ae94000.dsi.0/brightness` = nombre correcto (`dev_name(dsi[0])` en `:583`).

## 4. Gates/criterio/riesgo — 3 CORRECCIONES
- G1Gate `drm_panel_of_backlight(` ×0 **falla literal** (2× en comentarios). Cambiar a:
  `grep -v '^\s*\*' ... | grep -c drm_panel_of_backlight` = 0.
- G2 `failed to create backlight` debe ser **×0** (ausente), no ×1. `K47-pan-bl` relajar a **≥1**
  (resume/fb-blank con `BL_CORE_SUSPENDRESUME` puede re-disparar).
- G3 Riesgo display: el único DCS nuevo corre tras display-on y su `ret` se ignora
  (no tumba el prepare). Riesgo residual: si `o82_create_backlight` falla, el probe
  falla duro y se pierde el display que funciona. Colisión improbable (ver §3);
  alternativa segura: `dev_warn` + seguir (`enable/disable` son NULL-safe,
  `backlight.h:315-330`). Acepto el fail-duro actual, pero que conste.
- Criterio PASA=luz / FALLA=igual→hardware: correcto. Rollback L54 `1d641e63…` /
  L53 `c6b64752…` (`NOTAS-OMARCHY.md:4705,4715`) + cold boot: correcto.

## 5. Más barato/mejor
- Añadir al runbook: `echo 4095 > .../ae94000.dsi.0/brightness` (+ barrido 4..4095) por
  SSH antes de declarar FALLA — gratis y cubre el matiz 2(a). Sin esto, un glow débil
  se lee como "igual".

## VEREDICTO: **PASA flashear L55** con G1, G2 y barrido sysfs aplicados.
