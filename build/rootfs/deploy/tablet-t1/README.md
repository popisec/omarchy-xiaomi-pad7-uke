# tablet-t1 — T1 (tamaños para el dedo) + T6a (diario barato), 18-oct-2026

Aplicado por SSH en la config del usuario `omarchy`; no toca boot/dtbo ni reinicia Hyprland/tablet.
`./deploy.sh apply` (copia previa en `/root/backup-t1-<fecha>.tgz`) · `./deploy.sh revert /root/backup-t1-<fecha>.tgz`.
Backup original de esta sesión: `/root/backup-t1-20261018-1054.tgz` (shell.toml y looknfeel.lua previos).

| Fichero (en `files/`) | Destino | Qué |
|---|---|---|
| shell.toml | ~/.config/omarchy/shell.toml | `[font] base-size=16`, `[bar] size-horizontal=40`, `scale-with-font=false` |
| looknfeel.lua | ~/.config/hypr/looknfeel.lua | gaps 8/14, borde 4, `resize_on_border`, grab 20, `workspace_swipe_touch`, `hl.gesture` 3 dedos |
| hypridle.conf | ~/.config/hypr/hypridle.conf | 60 s → brillo 5 %, 120 s → DPMS off, 600 s → `systemctl suspend`; sin lock |
| uke-hypridle.service | ~/.config/systemd/user/ | unit propio (`hypridle -c`), enabled en graphical-session.target |

## Medido (18-oct-2026, en la tablet)
- `hyprctl configerrors` vacío tras cada cambio. `getoption`: gaps_in 8, gaps_out 14, border_size 4, resize_on_border true, extend_border_grab_area 20, `gestures:workspace_swipe_touch` true (antes false).
- **El `shell.toml` de usuario gana al del tema** (`Color.qml:202` mergeShell). El de usuario ya existía con `base-size = 14`; el tema catppuccin no trae `shell.toml` propio.
- **Trampa de la barra:** `Style.barToken` multiplica por `base-size/12` si `scale-with-font` (por defecto true). 40 con base 16 daría 53 px; por eso `scale-with-font=false` → 40 px lógicos. La capa `powerbar-clear` pasó de 162 a 186 px físicos de alto y las islas (powerbar) miden ~56 px lógicos en la captura (grim): holgado para el dedo.
- Sin `hl.gesture` el ajuste `workspace_swipe_touch` no hace nada (en input.lua el gesto está comentado): lo añadí en looknfeel.lua (3 dedos horizontal = espacio). T4 (gestos de borde) debe convivir con él.
- Brillo: `brightnessctl` escribe a `/sys/class/backlight/uke-backlight/brightness` (root:root 644, sin udev rule) **solo vía logind desde un proceso de la sesión del usuario**: falla con `sudo -u omarchy` desde SSH ("Operation not permitted") pero funciona desde `systemd-run --user` y desde un `exec_cmd` de Hyprland (372→512→368 ok). `omarchy brightness display +5% --no-osd` lanzado por Hyprland: rc=0. Hypridle (servicio de usuario) usa el mismo camino.
- Batería: `qcom-battmgr-bat` capacity 60 / upower `discharging 60%`. El widget `omarchy.power` por defecto solo pinta icono; activado `showPercentage` con `qs ipc … omarchy.power togglePercentage` (persistido por el shell en shell.json) → la barra muestra «60% 🔋».
- uke-hypridle activo; DPMS probado a mano (off/on con `hl.dsp.dpms`, instantáneo, `dpmsStatus: 1` después). El ciclo completo de 2 y 10 min NO se ha esperado (pendiente de que el dueño lo vea).
