# Cambios en la config del usuario omarchy (tablet) — 18-oct-2026

1. `~/.config/hypr/bindings.lua` (al final; copia previa `bindings.lua.bak.<epoch>` en la tablet):
   ```lua
   hl.unbind("XF86PowerOff")   -- esta version de Omarchy no trae o.rebind
   o.bind("XF86PowerOff", "Suspender", "/usr/local/bin/uke-power-button", { locked = true })
   ```
   Sustituye "Power menu" (`omarchy-menu toggle system`, default/hypr/bindings/utilities.lua:9); el menú sigue en el icono de
   Omarchy de la barra. `uke-power-button` ignora pulsaciones durante 3 s tras reanudar (la pulsación que despierta llega a
   Hyprland al volver) usando /run/uke-last-resume (gancho systemd-sleep `uke-resume-stamp`).
   OJO: `o.rebind` (que cita la guía de Omarchy) NO existe en Omarchy 4.0.4 edge: provocó `attempt to call a nil value`
   y dejó sin cargar el bindings.lua del usuario hasta corregirlo (configerrors vacío tras el arreglo).
2. `~/.config/omarchy/shell.json`: `idle.lock = 31536000` (un año). El shell de Omarchy bloquea con `omarchy-system-lock`
   a los 300 s; la cuenta no tiene contraseña y no hay teclado → bloqueo = sesión atascada. `0` NO desactiva (bloquearía ya:
   IdleModel.secondsFromConfig acepta 0). Salvapantallas (150 s) intacto.
