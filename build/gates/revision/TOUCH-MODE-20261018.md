# Touch Mode: teclado flotante ES/US + gestos de 2 y 3 dedos (18-oct-2026)

Estado: **instalado y activo en la tablet** (sin commit). Persistencia en frío comprobada tras el reinicio de las 17:39 (uinput 0660, demonio, plugin y sin squeekboard).
Material: `build/rootfs/deploy/touch-mode/` (`deploy.sh check|apply|status|log|revert|osk-on|osk-off`).

## A. Teclado (plugin `omarkyy.tablet`, fork local)
- Upstream: github.com/alertxsto/omarchy-touch-mode, commit `69639aa` (MIT). Copia intacta en `touch-mode/upstream/`, fork en `touch-mode/fork/`,
  parche legible `uke-touch-mode.patch` (diff upstream→fork).
- **Revisión previa (leída entera)**: `input-helper.c` (cliente Wayland `zwp_virtual_keyboard_v1`, sin red, sin exec, sin root), `sensor-helper.c`
  (solo D-Bus de iio-sensor-proxy), `platform.py` (hyprctl monitor/device transform, estado en `$XDG_RUNTIME_DIR`), `*-backend.sh` (compilan con `cc` en `~/.cache/omarchy/tablet`),
  `setup.py`. Nada saca datos ni ejecuta descargas. En el fork **no se instalan** `sensor-*`, `platform.py`, `setup.py` ni tests.
- Cambios del fork: (1) `input-helper.c`: dos keymaps xkb reales (`es` por defecto y `us`), orden `L es|us` que recrea el teclado virtual, bit 32 = AltGr (Mod5);
  (2) `Keyboard.qml`: filas ISO-ES (º ¡ ñ ç ´ ¨ < > AltGr con @ # € ~ \ [ ] { } ¬), teclas muertas ´ `, vocales con **pulsación larga (420 ms) = acento agudo**
  (la vocal sale al soltar; Shift → mayúscula acentuada), selector **ES·US** y botón **⟳ 90°** en la cabecera, se recoloca abajo al girar la pantalla, **acoplado por defecto: ancho completo, pegado a las esquinas inferiores, 44 % de la altura** (movible/redimensionable, el tamaño no se recuerda);
  (3) `Service.qml`: sin acelerómetro ni «modo tableta»; el giro llama a **`/usr/local/bin/uke-rotate next`** (monitor + táctil); distribución persistida en `~/.local/state/uke-touch-mode/layout`;
  IPC `omarkyy.tablet`: `keyboard|show|hide|rotate|rotateTo <grados>|layout|status`; (4) `BarWidget.qml`: izq. = teclado, der. = girar 90°, medio = ES/US; (5) `input-backend.sh --build`.
- Instalado en `~omarchy/.config/omarchy/plugins/omarkyy.tablet`, habilitado con `omarchy plugin enable omarkyy.tablet --section right` (el widget del teclado está en la barra, derecha). Instalados `gcc make pkgconf` (pacman, 45 MB; el helper se compila en la tablet, ~1 s).
- **Medido**: captura grim en horizontal (1240×420 abajo, ñ/ç/¡/¿ y etiquetas AltGr) y en vertical tras `rotate` (transform 1, teclado recolocado abajo, 1044 px). Escritura por el helper
  en `foot`: `ñ á É @ $ ¡ ? à`, y tras `L us` → `; @` (ES→US conmutado en caliente). `omarchy restart shell` conserva plugin y widget.
- **squeekboard: OPCIÓN 1, desactivado** (`uke-osk.service` disable --now; `./deploy.sh osk-off`). Evidencia: T3 mostró que su layer `osk` (top, 1600×356, y=712) aparece solo al enfocar un campo
  (text-input-v3), y el teclado del plugin es un layer overlay de 420 px en el mismo borde inferior (y=632): saldrían dos teclados apilados. El del plugin no hace aparición automática (limitación upstream), así que
  **→ añadido después: aparición automática propia** (ver «Auto-teclado»). Revertir: `./deploy.sh osk-on` (y poner `edge_bottom = /usr/local/bin/uke-osk-toggle` en el conf). `uke-osk-toggle` y su paquete siguen instalados; `omarchy-fcitx5` sigue enmascarado.
- Gesto borde inferior ↑ y botón de la barra: `omarchy-shell omarkyy.tablet keyboard`.

### Auto-teclado (como Android; añadido 18-oct tras la petición del dueño)
- `ime-helper.c` (+ `input-method-unstable-v2.xml`, de wlroots 0.18.2, bajado de gitlab.freedesktop.org) se registra como *input method* v2 y solo observa `activate/deactivate`
  (un campo de texto enfocado / ya no). `Service.qml` muestra el teclado en `active` y lo oculta (retardo 250 ms) en `inactive`; el gesto y el botón siguen funcionando.
- Medido con `foot`: abre foot → layer `omarchy-keyboard` aparece; se cierra foot → desaparece. Tocar el propio teclado no cambia el foco (no se cierra).
- Solo puede haber un input method por seat: **squeekboard debe seguir parado** (si no, el helper dice `unavailable` y el auto-teclado se desactiva).
- IPC `omarchy-shell omarkyy.tablet auto` lo activa/desactiva (persistido en `~/.local/state/uke-touch-mode/auto`; `status` muestra `auto`).
- **Respaldo añadido**: al matar Firefox con SIGTERM el compositor no mandó `inactive` y el teclado se quedó colgado; ahora `Service.qml` también lo oculta cuando `Hyprland.activeToplevel` queda vacío (sin ventana enfocada).
- **Pruebas en apps reales (18-oct, ~21:00)**: Firefox 157 (GTK3): sale con la barra de direcciones enfocada, se oculta al pasar el foco a la página (Esc) y al cerrar Firefox. `foot`: sale/entra. **GTK4: no probado — `gnome-text-editor` y `nautilus` no arrancan**
  (`libadwaita 1.10.0` pide símbolos de gtk4 4.24, la tablet tiene `gtk4 4.22.5`; `pacman -S gtk4` falló porque `mirror.archlinuxarm.org` no respondió). Es un problema previo de T5/paquetes, no del teclado: hay que actualizar gtk4 (hay 112 paquetes pendientes en la tablet).
- Teclado acoplado comprobado con `uke-rotate 90/180/270/0`: layer `0 598 1600 470` (0°/180°) y `0 896 1068 704` (90°/270°), siempre ancho completo y pegado abajo; la pantalla quedó en 0°.

## B. Gestos (`uke-gestures.py` v2, `touch-mode/uke-gestures.py`; parche `uke-gestures-v2.patch` sobre el de T4)
Lectura sigue siendo pasiva (sin grab): scroll y pellizco de 2 dedos en medio de la pantalla siguen siendo de las apps; el demonio **no** dispara nada en ellos (test sintético).
Inyección: `/dev/uinput` (regla `/etc/udev/rules.d/71-uke-uinput.rules`: grupo `input` 0660, `omarchy` ya está en `input`). El demonio crea un **puntero absoluto** y un **teclado** virtuales.
Medido: `--inject rightclick 0.25 0.25` mueve el cursor a `399,266` (esperado 400,267) y `--inject key w` escribe `w` en foot (el clic en sí no se ha visto abrir un menú: hace falta app con menú contextual).
Conf: `~omarchy/.config/uke-gestures.conf` (copia previa `.bak-touchmode`; versión en el repo = `touch-mode/uke-gestures.conf`). Todos los umbrales están ahí.

| Gesto | Acción por defecto |
|---|---|
| toque con 2 dedos (≤350 ms, <50 px, simultáneos ≤150 ms) | clic derecho donde tocas (`@rightclick`) |
| 2 dedos desde borde superior ↓ | panel de audio |
| 2 dedos desde borde inferior ↑ | girar 90° (`omarkyy.tablet rotate`) |
| 2 dedos desde borde izq. → / der. ← | Atrás / Adelante (`@key alt+left` / `alt+right`) |
| 3 dedos ↓ / ↑ | cerrar ventana / lanzador (ya existían) |
| 3 dedos ←/→ | escritorio siguiente/anterior (`hl.dispatch(hl.dsp.focus({workspace="r±1"}))`); el gesto nativo de Hyprland no actuaba con el táctil (commit e324a48) |
| pellizco de 3 dedos: separar / juntar | pantalla completa / (vacío: Omarchy/Hyprland **no tiene vista general**, haría falta hyprexpo) |
| 1 dedo borde sup./inf. | panel de energía / teclado del plugin (inf. cambiado) |

Todo respeta la rotación (transform leído de hyprctl). Tests: `touch-mode/test-gestures.py` (15 casos sintéticos, también con transform 1: OK). `./deploy.sh log` para probar en vivo (acciones en seco, `ACT=1` las ejecuta).

## Qué debe probar el dueño con el dedo
1. Botón del teclado en la barra / deslizar 1 dedo desde el borde inferior hacia arriba: abre y cierra. Escribir «mañana», «¿qué tal?», «USUARIO@example.invalid» (AltGr), mantener «a» → «á». ES·US en la cabecera.
2. ⟳ 90° del teclado y 2 dedos desde abajo: gira pantalla y el táctil debe seguirla; el teclado se recoloca.
3. Tocar con 2 dedos a la vez en un enlace/archivo: menú contextual (clic derecho). Comprobar que scroll y zoom con 2 dedos en Firefox siguen igual.
4. 2 dedos desde el borde izquierdo/derecho (¿atrás/adelante en Firefox, o salta de escritorio por el gesto nativo de 1 dedo? Si se duplica, vaciar `two_edge_left/right`).
5. 3 dedos izq./der.: ¿cambia de escritorio una sola vez? Separar 3 dedos: pantalla completa. Tocar un campo de texto en Firefox: ¿sale el teclado grande? Tocar fuera/otra ventana sin campo: ¿se va?
6. Reinicio en frío (no hecho): el plugin y el demonio se inician solos; squeekboard no debe aparecer.

## Pendiente / límites
- El teclado no aparece solo al enfocar un campo de texto (squeekboard sí lo hacía). Se puede añadir un disparador por text-input si lo echa de menos.
- Solo se probó con `foot`; Firefox/GTK no instalados.
- `apply` de T4 (`tablet-t4-gestos/deploy.sh`) reinstalaría el demonio v1 y no pisa el conf; usar este deploy.
