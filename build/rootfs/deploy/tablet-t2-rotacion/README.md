# T2 — rotación manual (uke, 18-oct-2026)

- `/usr/local/bin/uke-rotate {0|90|180|270|next|restore|status|touchmap "a b c d"}` — monitor DSI-1 (`hl.monitor`, transform 0..3
  = 0/90/180/270) + `input:touchdevice:transform`. Estado en `~omarchy/.local/state/uke-rotate/{deg,touchmap}`. Verifica el
  transform leído de `hyprctl monitors -j` y reintenta (una orden idéntica a la anterior a veces no se aplicaba).
- `/usr/local/bin/uke-vol-key up|down` — Vol+ y Vol- a la vez = `uke-rotate next`; una sola = volumen (retardo 250 ms).
- `bindings-snippet.lua` — se añade a `~omarchy/.config/hypr/bindings.lua` entre marcas `uke-t2-rotacion`: binds de Vol±,
  `SUPER+ALT+R` (teclado Focus futuro) y restauración en `hyprland.start` y `config.reloaded`.
- `deploy.sh check|apply|revert|status`. El demonio `uke-touchd.py` NO se ha modificado.

Si el dueño ve el táctil mal en alguna orientación: `uke-rotate touchmap "0 3 2 1"` (90↔270) y reaplica solo.
