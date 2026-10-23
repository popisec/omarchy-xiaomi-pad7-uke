# L63 — PPS post-0x29 (hook `enable`) · 14-oct-2026

## 1. Hallazgo (`PPS-COMPARA.md`: PPS byte-equivalente tras L62)
Único delta real = ORDEN: L59/L62 envían en `o82_prepare()` (panel
dormido, pre-0x11/0x29, `:409-457`); el vendor en `dsi_display_enable`
→ `dsi_panel_update_pps` (despierto, post-0x29). 0x11 en `:482-483`,
0x29 en `:486-487` (tail del prepare, NO en `o82_init_cmds[]`).

## 2. Cambio (`/tmp/ukefix/l63-pps-post.diff`, dry-run + reverse OK)
Opción (a) elegida: nuevo `o82_enable` en `o82_panel_funcs` (no existía;
`:592-596` solo prepare/unprepare/get_modes). El core lo llama post-modeset
vía panel_bridge (cadena: `dsi_bind` `dsi.c:129-136` envuelve el panel en
panel_bridge; `bridge/panel.c:148` → `drm_panel_enable` `:240`, que tolera
`enable==NULL` y traga errores — seguro). Equivale al display-enable vendor,
con vídeo ya andando. Patrón L62 reutilizado (copia local, dims/link, ×2).
Envío pre MANTENIDO (quitarlo = 2ª variable); inherit → skip coherente.

## 3. Gates
- Fuente: `UKE-L63` ×1. Binario: `strings Image | grep -c UKE-L63` = 1.
- Vivo: `dmesg | grep UKE-L63` ⇒ `PPS post-0x29 enviada (dims=1600x2136
  por link, err=0)`; se conservan `UKE-L62`/`UKE-L37` (orden visible).
- **PASA = CONTENIDO en pantalla. FALLA (negro con luz + L63 err=0)** ⇒
  cerrar la rama PPS entera; siguiente = candidato nº2
  `docs/historia/revision/PIPELINE-PANEL-20261014/s6-noncontinuous.diff` (listo; flag en `:695-696`) y nº3 PHY.

## 4. Rollback
L62 `d52f59677af0…190f260` / L59 `e3511595de6b…89534e`. NO build (ejecutor).
