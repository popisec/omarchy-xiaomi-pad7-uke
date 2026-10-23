# T4 — gestos de borde (18-oct-2026)

`uke-gestures.py` lee **en pasivo** (sin EVIOCGRAB) el evdev «uke NT36532 THP touchscreen» y lanza comandos del conf.
Hyprland sigue recibiendo todos los toques; el gesto también llega a la app de debajo (inevitable sin grab).

- Servicio: `uke-gestures.service` (systemd **--user** de `omarchy`, `Restart=on-failure`, habilitado con `systemctl --global`).
- Permisos: `omarchy` está en el grupo `input` y `/dev/input/event*` es `root:input 0660` → no hace falta regla udev.
- Conf: `~omarchy/.config/uke-gestures.conf` (umbrales + comando por gesto). Recarga: `systemctl --user kill -s HUP uke-gestures`.
- Rotación: lee `transform` de `hyprctl monitors -j` al tocar (caché 2 s) y mapea bordes/direcciones al aspecto VISUAL.
  Con T2 rotando por `monitor transform`, los gestos siguen a la pantalla (supone que el táctil la sigue).
- Modos: `--log` (muestra cada toque y gesto, acciones en seco; `--act` las ejecuta), `--record F`, `--replay F --transform N`.

`deploy.sh check|apply|status|log|revert`. `log` para el servicio, escucha 60 s (`T=120 ./deploy.sh log`) y lo reanuda.

Gestos por defecto: ver el conf. Borde superior ↓ = panel de energía/ajustes del shell (`omarchy-shell omarchy.power toggle`; el shell no tiene panel de notificaciones: `notifications showHistory` solo repite los avisos);
inferior ↑ = `uke-osk-toggle` (T3); izq → = escritorio anterior; der ← = siguiente; 3 dedos ↓ = cerrar ventana; 3 dedos ↑ = pantalla completa.
