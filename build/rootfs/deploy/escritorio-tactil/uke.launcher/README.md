# uke.launcher

Lanzador de aplicaciones tactil, a pantalla completa, para el shell de Omarchy en la
Xiaomi Pad 7 (uke). Sustituye a `uke.apps` + `nwg-drawer`. Tipos: `service` + `bar-widget`.

## Uso

    omarchy-shell uke.launcher toggle | open | close | status    # status -> open|closed

El boton de la barra (icono `󰀻`) hace `toggle`.

## Comportamiento

- Una capa layer-shell overlay (namespace `uke-launcher`) en el monitor enfocado, sin blur,
  fondo del tema del menu casi opaco.
- Buscador arriba (teclado `OnDemand`; no se enfoca solo, el OSK sale al tocarlo). Filtra en vivo por
  nombre, nombre generico y palabras clave, sin distinguir mayusculas ni acentos.
- Rejilla con desplazamiento vertical de todas las apps visibles (`DesktopEntries`, sin `noDisplay`
  ni las de `launcher.hides` / `OnlyShowIn`/`NotShowIn`), orden alfabetico segun locale.
  Celdas >= 160x184 px, icono de 92 px, nombre a 2 lineas.
- Tocar una app la lanza y cierra. Cierra: tocar el fondo o un hueco, boton grande arriba a la
  derecha, Escape (con el foco en la ventana), o arrastrar hacia abajo estando arriba del todo.
- Enter en el buscador lanza el primer resultado.

## Lanzamiento de apps

Copiado de `AppLibrary.launch` (`/usr/share/omarchy/shell/services/AppLibrary.qml`):
`uwsm-app -- gtk-launch <id>.desktop`, via `Util.execArgv` (sin shell intermedio).
No muestra el OSD "Launching..." de Omarchy (eso es interno del shell).

## Ligero

Sin timers ni polling. `Launcher.qml` (ventana, rejilla, `FileView` y `Process` de apps ocultas)
solo existe mientras esta abierto (`LazyLoader`). Solo hay un fundido de entrada de 120 ms.

## Seguridad

Todo texto con datos de apps usa `Text.PlainText`. Solo se aceptan toques/boton izquierdo
(`TapHandler` con `acceptedButtons: Qt.LeftButton`); no hay manejadores de clic derecho ni menus
contextuales (un clic derecho en una superficie de Quickshell hace SIGSEGV en este shell).

## Instalacion (no hecha)

Copiar la carpeta a `~/.config/omarchy/plugins/uke.launcher`, habilitarla, y sustituir `uke.apps`
por `uke.launcher` en la barra.

## Sin verificar en la tablet

Solo pasa `omarchy plugin validate` y `qmllint`; no se ha ejecutado. Por probar: tap en huecos de
la rejilla (cierre), gesto hacia abajo, foco/Escape con `OnDemand`, aparicion del OSK, iconos
instalados despues del arranque del shell (no se usa el indice de iconos de AppLibrary).
