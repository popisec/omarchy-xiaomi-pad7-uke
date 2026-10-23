# T5 — Implementación (18-oct-2026)

Paquete: `build/rootfs/deploy/tablet-t5/` (`deploy.sh status|install|apply|revert`). Alcance y decisiones del dueño:
`T5-ALCANCE-20261018.md`. No toca red, Bluetooth, audio, `boot` ni `dtbo`. Copias previas en `/root/backup-t5/files/` (una vez).
Sin commit; `NOTAS-OMARCHY.md` y `docs/historia/ESTADO-VIVO.md` sin tocar.

## Qué se hizo y se comprobó

| # | Cambio | Comprobación (18-oct, ~16:20–16:35) |
|---|---|---|
| 1 | `pacman -S firefox nwg-drawer nautilus papers loupe celluloid gnome-text-editor rnote` (+ deps) | instalación sin errores; `/` pasó de 3,2 G a **2,2 G libres** (72 %) |
| 2 | Firefox: `/etc/firefox/policies/policies.json` (telemetría y estudios off, protección de rastreo **strict**, cookies de terceros bloqueadas, sin sugerencias patrocinadas, sin asistente de bienvenida) + `/usr/lib/firefox/{defaults/pref/autoconfig.js,mozilla.cfg}` (`ui.click_hold_context_menus=true`, `apz.allow_zooming`, `apz.allow_double_tap_zooming`, `dom.w3c_touch_events.enabled=2`, `browser.uidensity=2` táctil, portal de ficheros, privacidad) | `about:policies` (headless, captura) lista las políticas activas; Firefox arrancó con la barra en densidad táctil (el `mozilla.cfg` se carga). **No verificado:** que cada pref de `mozilla.cfg` aparezca en `about:config` (la página pide aceptar el aviso) |
| 3 | `~/.config/mimeapps.list`: http/https/html → Firefox; carpetas → Nautilus; PDF → Papers; imágenes → Loupe; vídeo/audio → Celluloid; texto → Text Editor | fichero escrito; `xdg-mime` no lanzado en esta sesión |
| 4 | `shell.toml`: bloque `# >>> uke-t5` con `[spacing] control-height = 36`, `popup-row-height = 36` | shell reiniciado con `omarchy-restart-shell`, la barra y los paneles cargan |
| 5 | **Lanzador:** `nwg-drawer -r -ovl -k -nocats -nofs -is 96 -c 5 -spacing 24 -closebtn right -wm uwsm` residente, alternado con `/usr/local/bin/uke-drawer-toggle [toggle\|start\|open\|close]` (SIGUSR1); autostart con `o.launch_on_start` en `hypr/autostart.lua`; estilo catppuccin mocha en `~/.config/nwg-drawer/drawer.css` | captura (grim): rejilla 5 columnas con 8 apps, texto legible, botón de cierre a la derecha. **Toque virtual (uinput) en el botón de la barra → drawer visible; toque en el icono de Firefox → drawer cierra y Firefox arranca** (ventana `Mozilla Firefox` en `hyprctl clients`) |
| 6 | **Botón de barra:** plugin propio `~/.config/omarchy/plugins/uke.apps` (manifest + `BarWidget.qml`, icono nf-md-apps) y entrada `{"id":"uke.apps"}` en `shell.json`, a la derecha del icono de Omarchy | captura: el icono de rejilla aparece tras el menú de Omarchy; el toque virtual lo activa |
| 7 | T5.6: `NoDisplay=true` en overrides de usuario para ~25 `.desktop` no táctiles (kitty, vim, bssh, bvnc, avahi, cmake-gui, gcr, Xwayland, pinentry, portal, quickshell, squeekboard, pavucontrol, uuctl, xgps, mpv, imv, qv4l2…) y en los 13 **webapps** de Omarchy (necesitan Chromium, no instalado) | el drawer muestra solo: Celluloid, Document Viewer, Files, Firefox, Foot, Image Viewer, Rnote, Text Editor |
| 8 | T5.8: `~/.config/environment.d/10-omarchy-fcitx.conf` vacío sombrea el del sistema (`QT_IM_MODULE=fcitx`, `XMODIFIERS`, `SDL_IM_MODULE`, `INPUT_METHOD`) | tras el reinicio de la tablet el entorno de Hyprland **ya no contiene `fcitx`** (0 coincidencias en `/proc/<Hyprland>/environ`); `omarchy-fcitx5.service` ya estaba enmascarado por T3 |
| 9 | T5.7: Rnote instalado | aparece en el drawer; sin abrir ni probar dibujo |

## Gesto de apertura (decisión)

- **Elegido: 3 dedos hacia arriba** (`three_up` de `uke-gestures.conf`) → `uke-drawer-toggle`. **Sustituye** a «pantalla completa»
  (queda en el atajo de teclado de Omarchy). Motivo: no choca con nada nativo.
- **Qué hace el `gestures:workspace_swipe_touch` nativo: no verificado.** Intenté medirlo inyectando toques por uinput
  (dispositivo `uke-t5-test`, reconocido por Hyprland como *Touch*): ni un deslizamiento de 1 dedo desde el borde izquierdo/derecho ni uno de
  3 dedos horizontal cambió de escritorio, pero con un único escritorio vacío el resultado no es concluyente. La documentación de Hyprland
  describe `workspace_swipe_touch` como «deslizar el escritorio desde el borde de la pantalla táctil» (**[hipótesis]** sin fuente re-medida
  aquí), por eso se evitaron los bordes izquierdo/derecho y se descartó 3 dedos ←/→ (los tiene `hl.gesture`). Queda para el dueño: probar con el
  dedo qué dispara cada borde.
- **Aplicado** tras el reinicio (paso 8 de `apply-home.sh`, `three_up = /usr/local/bin/uke-drawer-toggle`, HUP a `uke-gestures`). Sin probar con el dedo.

## Incidente

Hacia las 16:36 el SSH a `192.168.42.129` pasó a «Connection refused» y luego a «timed out» (el ping respondió un rato). No se tocó nada que lo
explique en esta sesión (último cambio: reinicio del shell y arranque de Firefox); coincide con la actividad de otras sesiones (audio, ouke4).
La tablet volvió reiniciada (`up 0 min`). Comprobado después: `nwg-drawer -r` arrancó solo (autostart OK), `quickshell` corre, `three_up` aplicado, sin `fcitx` en el entorno.

## Para revertir

`./deploy.sh revert` restaura `shell.toml`, `shell.json`, `autostart.lua`, `uke-gestures.conf`, los `.desktop` de usuario y `mimeapps.list`
desde `/root/backup-t5/files`, borra el plugin `uke.apps`, el CSS, el sombreado de fcitx, las políticas y `mozilla.cfg`; **no** desinstala
paquetes (`pacman -Rns firefox nwg-drawer nautilus papers loupe celluloid gnome-text-editor rnote` a mano; recupera ~1 GB). Avisos: el
revert restaura `uke-gestures.conf` desde la copia de T5, así que pisaría cambios posteriores de otras sesiones en ese fichero.

## Lista para que el dueño pruebe con el dedo

1. **Botón de apps** en la barra (rejilla, a la derecha del icono de Omarchy): un toque abre el lanzador; otro toque en el botón de cerrar (arriba a la derecha) lo cierra.
2. **Gesto de 3 dedos hacia arriba** abre el lanzador (cuando el paso 8 esté aplicado). Comprobar que 3 dedos ↓ sigue cerrando ventana y que 3 dedos ←/→ cambia de escritorio.
3. **Lanzador:** tocar Firefox, Files, Image Viewer, Rnote y Text Editor abre cada app y **cierra** la rejilla; desplazar con el dedo no lanza nada por error; el campo de búsqueda saca el teclado en pantalla solo (si no, borde inferior).
4. **Bordes izquierdo y derecho:** deslizar desde cada uno y anotar qué ocurre (¿cambia de escritorio? ¿solo con 3 dedos?).
5. **Firefox:** desplazar con el dedo; pellizcar para ampliar; doble toque para zoom; **pulsación larga sobre un enlace → menú contextual**; tocar la barra de direcciones saca el teclado; ver que la barra y las pestañas son lo bastante grandes; probar una página con vídeo.
6. **Firefox — privacidad:** `about:preferences#privacy` → protección contra rastreo «Estricta»; `about:policies` activo; ningún asistente de bienvenida.
7. **Archivos (Nautilus):** abrir una carpeta, pulsación larga → menú, abrir un PDF (Papers: arrastrar y pellizcar), una imagen (Loupe: pellizcar) y un vídeo (Celluloid: botones grandes).
8. **Rnote / Text Editor:** abrir, dibujar con el dedo en Rnote, escribir en Text Editor con el OSK.
9. **Sliders de los paneles** (volumen, brillo): arrastrar de 0 a 100 %, ¿se pierde el arrastre al desviar el dedo en vertical? (si sí: `preventStealing` en una copia de `PanelSlider.qml`, T5.4 ampliado). Controles ahora a 36 px lógicos: ¿bien o hay que subir a 40–44?
10. **Paneles** (audio, red, bluetooth, reloj, power) y menú de Omarchy: abrir/cerrar con el dedo, scroll de listas. En red/BT **solo mirar**, no conectar.
11. **Tras cerrar sesión y volver a entrar:** que el OSK siga saliendo y no haya `QT_IM_MODULE=fcitx` (`hyprctl` → `printenv`), y que el lanzador esté residente (`pgrep nwg-drawer`).
12. **Clic derecho por pulsación larga en la barra** (tray, medios): sigue sin existir (T5.10, aplazado).

## Anotado como mejora posterior (no implementado)

- **Rejilla de apps propia en Quickshell** (opción B del alcance): sustituiría a nwg-drawer con el mismo tema y sin proceso aparte.
- Pulsación larga = clic derecho en el shell (T5.10); botón de teclado dentro del menú de Omarchy (T5.11); `preventStealing` en sliders.
- Chromium no instalado: los webapps de Omarchy (WhatsApp, YouTube…) quedan ocultos. Si se quieren, hace falta Chromium (439 MiB; hoy 2,2 GB libres) o convertirlos en accesos directos de Firefox.
- Disco: `/` al 72 %.
