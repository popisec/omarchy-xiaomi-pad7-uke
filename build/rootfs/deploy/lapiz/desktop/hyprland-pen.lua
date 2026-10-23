-- ~/.config/hypr/pen.lua — lapiz de la uke en Hyprland 0.56 (config Lua). 20-oct-2026. NO instalado.
-- Instalar (como omarchy): cp hyprland-pen.lua ~/.config/hypr/pen.lua ; anadir  require("hypr.pen")  al final de ~/.config/hypr/hyprland.lua
--   (despues de require("hypr.bindings"), como los demas ficheros del usuario) ; cp uke-pen-sync /usr/local/bin/ (root).
-- Sintaxis: hl.config({ input = { tablet = {...} } }) — https://wiki.hypr.land/Configuring/Basics/Variables/ (seccion «Tablet», consultada 20-oct-2026):
--   transform (int, = los del monitor), output (string; «current» o nombre; vacio = todos), region_position/region_size (vec2),
--   absolute_region_position, relative_input, left_handed (gira 180), active_area_size/position (mm).
-- Por dispositivo: hl.device({ name = "uke-focus-pen", ... }) — https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/ (20-oct-2026):
--   «use the name of the Tablet and not Tablet Pad or Tablet Tool». Nombre exacto: `hyprctl devices` (suele ser el nombre en minusculas y con guiones).

-- 1) El nodo esta en coordenadas del panel (3200x2136 sin rotar, igual que el tactil): atarlo a DSI-1 evita que se reparta en otros monitores.
--    El transform NO se fija aqui: lo aplica uke-pen-sync segun la rotacion guardada por uke-rotate (mismo mapa que el tactil, penmap opcional).
hl.config({ input = { tablet = { output = "DSI-1" } } })

-- 2) Presion: libinput ya filtra el umbral de punta; el demonio emite suelo PRESSURE_FLOOR=100/8191. Sin cambios por defecto.
--    (input.tablettool.pressure_range_min/max son float 0..1, -1 = por defecto; fijarlos desactiva la deteccion de offset de libinput.)
-- hl.config({ input = { tablettool = { pressure_range_min = 0.02, pressure_range_max = 1.0 } } })

-- 3) Reaplicar la orientacion del lapiz al arrancar y tras recargar la config (la recarga devuelve transform a su valor por defecto).
--    Las rotaciones en caliente las dispara uke-pen-sync.path (unidad de usuario) al cambiar ~/.local/state/uke-rotate/deg.
hl.on("hyprland.start", function() hl.exec_cmd("sleep 4; /usr/local/bin/uke-pen-sync") end)
hl.on("config.reloaded", function() hl.exec_cmd("sleep 1.5; /usr/local/bin/uke-pen-sync") end)

-- 4) Botones fuera de rango (nodo «uke Focus Pen Buttons»: F19 / PageUp / PageDown). NO se atan PageUp/PageDown: son teclas globales
--    (romperian el desplazamiento de cualquier aplicacion con el teclado real) y su uso natural es el de presentador, dentro de la app.
--    F19 no la usa nadie: queda libre para una accion de escritorio. Ejemplo (desactivado; decision del dueno):
-- o.bind("F19", "Lapiz: boton pequeno fuera de rango", "/usr/local/bin/uke-rotate next")
