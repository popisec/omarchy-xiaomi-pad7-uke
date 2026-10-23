-- hyprland-touch-pen.lua — táctil + lápiz en Hyprland 0.56 con config Lua
-- (Omarchy 4). Cargar desde la config: require("uke-touch-pen") o equivalente.
--
-- Hyprland 0.56 expone tablet-v2 completo (verificado en el binario:
-- zwp_tablet_manager_v2 / tool / pad). El lápiz del NT36532 es "direct"
-- (INPUT_PROP_DIRECT): Hyprland lo mapea al monitor; no hay que crear pad.
--
-- TRANSFORM 1 vs 3: ver test de esquinas en P2-lapiz.md §(e). Ajustar aquí y
-- en el monitor (hl.monitor) si se rota la pantalla.

hl.config({
  input = {
    -- táctil: marco nativo 2136x3200 (retrato) sobre panel 3200x2136
    touchdevice = {
      transform = 1,
    },
    -- lápiz (NVTCapacitivePenM80p): mismo marco, misma rotación
    tablet = {
      transform = 1,
    },
  },
})

-- Opcional: atar el lápiz a un output concreto (wiki: usar el nombre del
-- "Tablet", no del "Tablet Pad"; el nombre real sale de `hyprctl devices -j`).
-- hl.device({ name = "NVTCapacitivePenM80p", output = "DSI-1" })

-- Rotación completa (si algún día se usa auto-rotación): rotar monitor Y
-- touchdevice/tablet a la vez (patrón texp-rotate/gimbal):
--   hl.monitor({ output = "DSI-1", transform = 1 })
--   hl.config({ input = { touchdevice = { transform = 1 }, tablet = { transform = 1 } } })
