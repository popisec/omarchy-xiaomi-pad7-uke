# libinput / Hyprland / kernel: secuencias de touch peligrosas (consulta 20-oct-2026)

Fuentes leidas en local (clones --depth 1, no instalados):
- libinput 1.32.0 (tag), `src/evdev-fallback.c` (gitlab.freedesktop.org/libinput/libinput; la web raw esta tras Anubis, se uso `git clone`).
- Hyprland v0.56.2 (github.com/hyprwm/Hyprland), `src/managers/input/Touch.cpp`, `src/pointer/PointerManager.cpp`, `src/managers/SeatManager.cpp`, `src/protocols/core/Seat.cpp`.
- aquamarine master (be8909b), `src/backend/Session.cpp`.
- Kernel: `drivers/input/input.c`, `input-mt.c`, `misc/uinput.c` (git.kernel.org, torvalds master 20-oct-2026) y https://docs.kernel.org/input/multi-touch-protocol.html

## Hechos verificados

1. **Kernel filtra por estado (input.c `input_handle_abs_event`, l.156-205).** `ABS_MT_SLOT` solo se "prepara" (`mt->slot`) y se emite al llegar el siguiente evento MT que cambie algo. Cualquier ABS MT (incl. TRACKING_ID, X, Y) cuyo valor sea igual al guardado en ese slot se descarta (`*pold == *pval -> IGNORE`). Consecuencias: TRACKING_ID=-1 en slot ya inactivo = nada; mismo id en el mismo slot = nada; un evento sin SLOT previo se aplica al slot "staged" por el ultimo SLOT recibido. uinput llama `input_mt_init_slots(nslot=max+1)` (uinput.c l.344-346).
2. **EV_KEY se deduplica** (input.c l.235-247): BTN_TOUCH solo pasa si cambia el bit.
3. **libinput ignora BTN_TOUCH en dispositivos MT** (evdev-fallback.c `fallback_process_key` l.595-598, `if (!device->is_mt)`). Desincronizar BTN_TOUCH es inocuo para libinput; solo manda TRACKING_ID.
4. **Slot fuera de rango**: libinput lo recorta al ultimo slot y registra bug (l.636-644).
5. **TRACKING_ID>=0 marca BEGIN; <0 marca END** (l.646-675), y el estado por slot se resuelve **al SYN**, no por evento. Si en el mismo frame un slot recibe -1 y luego un id nuevo, queda BEGIN, no se emite `touch_up`, y `fallback_flush_mt_down` ve `seat_slot != -1` -> "driver sent multiple touch down for the same slot" (l.358-363) y **descarta el down**: el dedo viejo sigue vivo y el nuevo se pierde. Inverso (down+up en un frame): queda END con `seat_slot==-1`, el toque se pierde en silencio.
6. **seat_slot = bit libre mas bajo de `seat->slot_map` (uint32, compartido entre dispositivos)** (l.365-371). `fallback_flush_mt_down` devuelve false si no hay hueco. aquamarine entrega ese `seat_slot` como `touchID` (Session.cpp l.733). Un slot que nunca recibe -1 retiene su bit (fuga hasta cancel/remove).
7. **`touch_frame` solo se emite si el ultimo slot sucio devolvio true**: `fallback_flush_mt_events` hace `sent = ...` (no `|=`) en l.997-1019 y devuelve `sent` (l.1044); `fallback_handle_state` emite `touch_notify_frame` solo si es true. HIPOTESIS: un frame cuyo ultimo slot sucio no produce evento (motion filtrada por defuzz, up de slot sin seat_slot) pierde el `wl_touch.frame`; GTK/Qt procesan gestos en `frame`. No probado.
8. **Hyprland ignora `touch cancel`**: `PointerManager.cpp` l.1089 `listener->cancel = ... [] { }` vacio, y `sendTouchCancel` nunca se llama. Un `TOUCH_CANCEL` de libinput (solo por MT_TOOL_PALM o `cancel_touches`) deja el dedo "vivo" para el cliente. Para dispositivos uinput sin TOOL_TYPE no aplica; si se reintroduce ABS_MT_TOOL_TYPE, **no sirve como cancelacion**.
9. **Contadores en Hyprland**: `sendTouchDown` hace `m_touchLocks++`, `sendTouchUp` `--` (SeatManager.cpp l.467-495, ignora up si <=0); `CWLTouchResource::m_fingers` (Seat.cpp l.41,52-57) al llegar a 0 borra `m_currentSurface`. Un down no entregado (nada bajo el dedo, o gesto de swipe de workspace en curso, Touch.cpp l.54-73,115) con su up si entregado desbalancea contadores. `onTouchUp` solo reenvia si `touchFocusSurface` esta puesto (l.135). Con `workspace_swipe_touch` activo, un down en el borde empieza el swipe y los demas toques **no se propagan** hasta el up de ese id (l.54).
10. **Tiempo minimo up->down**: no hay ninguno en libinput ni Hyprland (no encontrado en el codigo). Los timestamps vienen del kernel/uinput.

## Secuencias peligrosas (prioridad para el validador)

1. Escribir eventos de un slot sin `ABS_MT_SLOT` explicito cuando el ultimo SLOT emitido (o el "staged" del kernel) no es ese. Tras la suelta masiva el slot staged es el ultimo liberado: el dedo 2 se convierte en update del slot equivocado -> pellizco muerto, 1 dedo OK. **Emitir SLOT siempre antes de cada slot en cada frame** (el kernel lo deduplica gratis).
2. -1 e id nuevo en el mismo slot dentro de un SYN (hecho 5).
3. Down+up del mismo slot en un SYN (toque perdido).
4. TRACKING_ID distinto >=0 sobre slot activo sin -1 previo (re-id): "multiple touch down", ignorado.
5. Estado del daemon != estado del kernel/libinput por slot (tras suelta, el daemon cree inactivo lo que ya lo esta, o al reves): el kernel descarta -1 repetidos y ids repetidos; validar contra un espejo con la semantica de `input_handle_abs_event`.
6. Mas de 10 slots activos / slot >= 10 / mas de 32 toques a nivel de asiento.
7. Frame mixto (up de unos + motion de otros) con el ultimo slot sin efecto (hipotesis hecho 7); preferir frames homogeneos.
8. BTN_TOUCH/BTN_TOOL_FINGER inconsistentes con el numero de slots activos: inocuo para libinput, pero mantenerlos coherentes (cambian solo en 0<->1 dedos).
9. Reutilizar el mismo TRACKING_ID en slots distintos a la vez: el kernel lo admite y libinput no mira el valor; no es causa probable, pero evitarlo (ids monotonos).

## Patron mas seguro para cancelar todos los dedos

Un SYN por transicion y sin mezclar:
1. SYN_REPORT de vaciado de lo pendiente (si hay movimiento sin emitir).
2. Para cada slot activo, en orden ascendente: `ABS_MT_SLOT=n`, `ABS_MT_TRACKING_ID=-1`. Despues `BTN_TOUCH=0` (y `BTN_TOOL_*` a 0) y **un unico SYN_REPORT** para todos (un frame de ups: `touch_up` por slot + un solo frame; libinput los vacia en `fallback_flush_mt_up`). Si se quiere maxima cautela con hecho 7, un SYN por slot es equivalente y evita el `sent=` colapsado.
3. Marcar todos los slots como inactivos en el daemon solo tras escribir; no emitir nada para slots ya inactivos.
4. Esperar al menos un frame (p. ej. >= 10-20 ms, valor empirico, sin fuente) antes de reanudar; al reanudar, `ABS_MT_SLOT=n` explicito, id nuevo monotono, X, Y, y BTN_TOUCH=1 en el frame del primer dedo.
No usar MT_TOOL_PALM como cancelacion (Hyprland ignora cancel).
