# CADENA USERSPACE→DRM (entrada del MDP) — 2026-10-14 (reloj tablet: 26-sep)

## Veredicto (una frase)
**La capa userspace/DRM coloca bien el contenido: el FB commitido en el primary
plane tiene píxeles reales (media R117.8/G49.6/B114.7, 0 negros en 200k muestras,
idéntico al `grim`). El negro se genera AGUAS ABAJO (fetch MDP o posterior:
MDP/DSI/PHY/DDIC → ver CADENA-KERNEL-HW.md). Nada que arreglar aquí.**

## 1. Qué se commitea (sesión viva, solo lectura)
- `hyprctl monitors`: `DSI-1 3200x2136@120 at 0x0, scale 2, currentFormat XRGB8888,
  dpmsStatus 1, hardwareCursorsInUse true`. Workspaces: ID 1, 0 ventanas (greeter/sddm).
- `modetest -M msm-kms -c`: **1 solo connector** `DSI-1` (id 36, encoder DSI 35),
  **1 solo modo** `3200x2136@120` (preferred, driver), `DPMS=On(0)`, `link-status=Good`.
- `modetest -p`: CRTC 85 ← fb 95 (3200x2136); plano **Primary 43 ← fb 95** en (0,0)
  full-size, zpos 0, alpha 65535, blend Pre-multiplied, rot 0. Overlays 49–73
  inactivos (fb 0). Cursor 79 ← fb 93 (512x512). Encoder Virtual 37 sin crtc.
- `debugfs dri/1/framebuffer`: `fb95 3200x2136 XR24, modifier LINEAR(0x0),
  pitch 12800 (=3200*4), allocated by Hyprland, GEM importado, vma mdp_kms mapped,
  write-fence signalled`. Doble buffer fb96 idéntico. **CTM = identidad, sin GAMMA_LUT.**
- `dmesg`: pares `K47-atom-tail + K47-kms-en-commit` continuos (1067 líneas, ~8 ms en
  animación, luego 60 s por blink cursor), **cero underrun/error/timeout** en msm/dsi/mdp/drm.
- Log Hyprland (`/run/user/1000/hypr/*/hyprland.log`, 101 líneas): backend DRM atómico en
  `/dev/dri/card1` (msm-kms), render en freedreno FD735 (card0/renderD128), sin errores.
  Solo anomalía menor: `No matching render node… falling back to renderD128` (benigno).

## 2. ¿Los buffers tienen contenido? SÍ (lectura directa del FB commitido)
- Script ctypes: `GETFB2(fb95)` + `PRIME_HANDLE_TO_FD` + `mmap` (no pide master,
  solo lectura). Resultado: `FB 95: 3200x2136 fmt XR24 pitch 12800 mod 0x0` →
  `mean R=117.8 G=49.6 B=114.7, min_sum=62, max_sum=657` → **CON-CONTENIDO**.
- `grim` fresco (6.2 MB PNG, media 117.3/49.4/114.6, 0 negros): el contenido Wayland
  coincide píxel a píxel con el FB commitido. La GPU renderiza bien y el DRM lo publica bien.

## 3. Puntos de la tarea resueltos sin tocar la sesión
- **(c) DSI-2**: no existe en DRM (solo DSI-1 + Writeback-1). El split dual-DSI vive
  dentro del driver (`panel-xiaomi-o82-dualdsi ae94000.dsi.0` en dmesg) → para el
  subagente kernel/HW: verificar que ambas mitades reciben datos, no es tema DRM-API.
- **(d) 1600x1068 del greeter**: NO es un modo DRM (DRM ofrece exactamente 1 modo).
  Es la geometría lógica a escala 2 (3200/2 × 2136/2). Sospecha descartada.
- **(e) Modo nativo**: sí, 3200x2136@120 preferred = único modo del panel.

## 4. Tests A/B propuestos (NO ejecutados: el stop de sddm se reserva a sesión coordinada)
- **T1 (decisivo)**: `systemctl stop sddm` → `modetest -M msm-kms -s 36@85:3200x2136`
  (patrón SMPTE, dumb-buffer lineal, sin GPU) → `systemctl start sddm`.
  PASA (se ve el patrón a color) ⇒ MDP/DSI/DDIC transportan bien dumb-buffers y el
  sospechoso pasa a ser el fetch de dmabuf importados (VM/SMMU-mdp). FALLA (sigue negro)
  ⇒ el negro nace en MDP-fetch o después, con contenido conocido-bueno: exime a userspace.
- **T2 (barato, sin parar nada)**: `modetest -w 36:'DPMS':3` (pantalla debe quedar igual
  de negra) → `:0` (debe seguir igual). Si el negro *parpadea/cambia* al ciclar DPMS,
  el DDIC responde a DCS y el stream de vídeo es el sospechoso, no el power.
- **T3**: `hyprctl keyword monitor DSI-1,1600x1068@120,0x0,1` (baja escala/res lógica).
  PASA (se ve algo) ⇒ el scalar del MDP a 3200px es el sospechoso. FALLA ⇒ independiente
  de escala. Revertir con `,3200x2136@120,0x0,2`.
- **T4**: `drm_info`/GETFB2 del cursor (fb93 512x512 AR24): si el cursor tampoco se ve
  siendo un buffer distinto en plano distinto, el fallo es común a todos los planos
  (apunta a salida del MDP, no a un plano/formato concreto).

## 5. Para el subagente kernel/HW
Entrada del MDP verificada buena: fb95 XR24 lineal 27.3 MB en vma mdp_kms, fence
signalled, commits atómicos sin error, CTM identidad, DPMS On, link Good. Si el DDIC
recibe frames negros con este FB, mirar: fetch/rotator/UBWC del SSPP, split dual-DSI
(mitad izquierda/derecha), DSC/PPS, y qué hace el DSI con `link-status Good` pero
contenido cero. La pista `KTZ 0x02=0x52, BL_EN=0x7f` + negro (no flash blanco) ya la
tenéis: DDIC vivo, stream negro.
