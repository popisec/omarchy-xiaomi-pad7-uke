-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- uke (18-oct-2026): boton de encendido = suspender (s2idle validado). Sustituye a "Power menu" (omarchy-menu toggle system),
-- que sigue disponible desde el icono de Omarchy de la barra.
hl.unbind("XF86PowerOff")   -- esta version de Omarchy no trae o.rebind
o.bind("XF86PowerOff", "Suspender", "/usr/local/bin/uke-power-button", { locked = true })
-- >>> uke-t2-rotacion
-- uke T2 (18-oct-2026): rotacion manual. Gestionado por tablet-t2-rotacion/deploy.sh (no editar entre marcas).
-- Vol+ y Vol- a la vez = rotar; una sola = volumen (uke-vol-key distingue con 250 ms de retardo).
hl.unbind("XF86AudioRaiseVolume")
hl.unbind("XF86AudioLowerVolume")
o.bind("XF86AudioRaiseVolume", "Volume up (o rotar con Vol-)", "/usr/local/bin/uke-vol-key up", { locked = true, repeating = true })
o.bind("XF86AudioLowerVolume", "Volume down (o rotar con Vol+)", "/usr/local/bin/uke-vol-key down", { locked = true, repeating = true })
o.bind("SUPER + ALT + R", "Rotar pantalla", "/usr/local/bin/uke-rotate next")
-- La orientacion guardada se reaplica al iniciar sesion y si una recarga de config vuelve a la regla de monitors.lua.
hl.on("hyprland.start", function() hl.exec_cmd("sleep 3; /usr/local/bin/uke-rotate restore") end)
hl.on("config.reloaded", function() hl.exec_cmd("sleep 1; /usr/local/bin/uke-rotate restore") end)
-- <<< uke-t2-rotacion
