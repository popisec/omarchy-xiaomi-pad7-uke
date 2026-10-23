-- uke ESCRITORIO-TACTIL (22-oct-2026): ventanas y animaciones de tableta.
-- Se instala en ~/.config/hypr/tablet.lua y se carga desde hyprland.lua (require("hypr.tablet")).
-- Revertir: build/rootfs/deploy/escritorio-tactil/deploy.sh revert (quita el require y este fichero).
-- API de Hyprland 0.56.2 comprobada en su fuente (src/config/lua/...), ver ESCRITORIO-TACTIL-20261022.md.

-- 1) UNA APP POR ESCRITORIO: cada ventana en mosaico se abre en un escritorio vacio y ocupa toda la pantalla
--    (los dialogos y ventanas flotantes siguen abriendose encima de su app). Cambiar de app = 3 dedos de lado.
hl.window_rule({ name = "uke-una-app-por-escritorio", match = { float = false }, workspace = "empty" })

-- Con una sola ventana: sin huecos ni borde (pantalla completa sin perder la barra). Con dos: huecos finos.
hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0, border_size = 0 })
hl.config({ general = { gaps_in = 3, gaps_out = 6, border_size = 3 } })
-- deslizar 1 dedo desde el borde (gesto nativo de Hyprland) no crea escritorios vacios al pasar del ultimo
hl.config({ gestures = { workspace_swipe_create_new = false } })

local function tiled_on(ws_id, skip)
  local r = {}
  for _, w in ipairs(hl.get_windows()) do
    if w.workspace and w.workspace.id == ws_id and not w.floating and w ~= skip and (not skip or w.address ~= skip.address) then
      r[#r + 1] = w
    end
  end
  return r
end

-- 2) DIVIDIR / UNIR con un gesto (uke-gestures: pellizco de 3 dedos hacia dentro -> hyprctl eval 'uke_dividir()').
--    Una app sola: trae al lado la ultima app usada (dwindle la pone a la derecha; en vertical, debajo).
--    Ya divididas: la otra vuelve a su propio escritorio y la activa queda a pantalla completa.
function uke_dividir()
  local ws = hl.get_active_workspace()
  if not ws or ws.special then return "sin escritorio" end
  local act = hl.get_active_window()
  local here = tiled_on(ws.id)
  if #here >= 2 then
    for _, w in ipairs(here) do
      if not act or w.address ~= act.address then
        hl.dispatch(hl.dsp.window.move({ workspace = "empty", follow = false, window = w }))
      end
    end
    return "unidas"
  end
  local best
  for _, w in ipairs(hl.get_windows()) do
    if not w.floating and w.workspace and w.workspace.id ~= ws.id and not w.workspace.special
       and (not best or w.focus_history_id < best.focus_history_id) then
      best = w
    end
  end
  if not best then return "no hay otra app" end
  hl.dispatch(hl.dsp.window.move({ workspace = ws.id, follow = false, window = best }))
  if act then hl.dispatch(hl.dsp.focus({ window = act })) end
  return "divididas"
end

-- 3) AL CERRAR la ultima app de un escritorio, volver a la app usada antes (como el «atras» de una tableta)
--    en vez de quedarse en el fondo de pantalla vacio.
hl.on("window.close", function(w)
  if not w or w.floating or not w.workspace or w.workspace.special or not w.workspace.active then return end
  if #tiled_on(w.workspace.id, w) > 0 then return end
  local best
  for _, o in ipairs(hl.get_windows()) do
    if o.address ~= w.address and not o.floating and o.workspace and o.workspace.id ~= w.workspace.id
       and not o.workspace.special and (not best or o.focus_history_id < best.focus_history_id) then
      best = o
    end
  end
  if best then hl.dispatch(hl.dsp.focus({ window = best })) end
end)

-- 4) ANIMACIONES de tableta: cortas (150-250 ms), con salida suave, sin blur ni sombras (ya apagados por Omarchy).
--    Coste: solo hay fotogramas mientras dura la animacion; a 120 Hz son ~25-30 por transicion.
hl.curve("ukeOut", { type = "bezier", points = { { 0.22, 1 }, { 0.36, 1 } } })
hl.curve("ukeInOut", { type = "bezier", points = { { 0.4, 0 }, { 0.2, 1 } } })
hl.animation({ leaf = "global", enabled = true, speed = 2.5, bezier = "ukeOut" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 2.2, bezier = "ukeOut", style = "popin 92%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.5, bezier = "ukeOut", style = "popin 92%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 2.5, bezier = "ukeOut" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.8, bezier = "ukeOut" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.5, bezier = "ukeOut" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 2.0, bezier = "ukeInOut", style = "slide" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 2.2, bezier = "ukeOut", style = "slidevert" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 1.6, bezier = "ukeOut", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.2, bezier = "ukeOut", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.6, bezier = "ukeOut" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.2, bezier = "ukeOut" })
hl.animation({ leaf = "border", enabled = false })
hl.animation({ leaf = "borderangle", enabled = false })
-- el teclado en pantalla entra y sale deslizandose desde abajo
hl.layer_rule({ name = "uke-osk-slide", match = { namespace = "omarchy-keyboard" }, animation = "slide bottom" })
