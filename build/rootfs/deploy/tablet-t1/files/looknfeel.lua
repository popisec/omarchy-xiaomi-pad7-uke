-- Change the default Omarchy look'n'feel.
-- T1 (18-oct-2026): tamaños para el dedo + gesto táctil de espacios de trabajo.

hl.config({
  general = {
    gaps_in = 8,
    gaps_out = 14,
    border_size = 4,
    -- Agarrar el borde con el dedo para redimensionar.
    resize_on_border = true,
    extend_border_grab_area = 20,
  },

  gestures = {
    -- Deslizar con 3 dedos para cambiar de espacio de trabajo.
    workspace_swipe_touch = true,
  },
})

-- Sin esto workspace_swipe_touch no hace nada: 3 dedos en horizontal = cambiar de espacio.
-- (Los gestos de borde de T4 van aparte, en su propio demonio.)
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
