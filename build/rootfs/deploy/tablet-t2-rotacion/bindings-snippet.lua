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
