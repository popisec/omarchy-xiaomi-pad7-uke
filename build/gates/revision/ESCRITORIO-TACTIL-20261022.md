# Escritorio táctil en la uke — 22-oct-2026 (sesión escritorio-tactil)

Omarchy 4.0.6 · Hyprland 0.56.2 (config Lua) · Quickshell 0.3.2 · Qt 6.12. Turno de tablet 16:30–16:55 (`uke-turno`), sin
reiniciar la tablet (solo `omarchy restart shell` ×3 y `hyprctl reload`). Todo reversible con
`build/rootfs/deploy/escritorio-tactil/deploy.sh <parte>-revert` y copias en `~omarchy/.local/share/uke-escritorio/`.
Lo desplegado coincide por sha256 con el repo (13 ficheros comprobados al final). Dudas para el dueño: `docs/historia/DUDAS-ESCRITORIO.md`.

## Resumen medido (antes → después)

| Qué | Antes | Después |
|---|---|---|
| Aparición del teclado al enfocar un campo (mediana) | 220 ms (147–296, 12 ciclos; **contaminada**, ver nota) | **184 ms (141–205, 20 ciclos, limpia)** |
| Teclado al pasar a un escritorio vacío | **se quedaba visible** (falso positivo) | se oculta y vuelve al regresar (6/6) |
| Sugerencias / autocorrección ES | no había | 3 sugerencias + autocorrección prudente, 11/11 pruebas |
| RSS del escritorio (Hyprland + shell + OSK + lanzador) | 720 MB | **582 MB (−138 MB)** |
| CPU en reposo 60 s, Hyprland / shell | 0,50 % / 0,63 % | 0,53 % / 0,67 % |
| Ventanas | mosaico con huecos de 14 px | una app por escritorio a pantalla completa; dividir con un gesto |
| Lanzador | nwg-drawer residente (124 MB siempre) | `uke.launcher` dentro del shell, solo existe mientras está abierto |

> **Corrección 17:xx (aviso de immich-sp-re):** entre 16:33 y 16:42 esa sesión compiló e instaló immich-nativo en la tablet
> **sin tener el turno** (lo tenía esta sesión). Afectó a la latencia base (220 ms, ~16:38) y a la primera medida tras el cambio
> (124 ms, ~16:41, **retirada: no se reproduce**). Repetida con la tablet tranquila (carga 0,6): 177 ms (144–189, 20/20) con las
> dos ventanas de prueba en escritorios distintos (incluye el cambio de escritorio) y **184 ms (141–205, 20/20) en el mismo escritorio**,
> que es lo comparable con la base. La mejora real del teclado precargado es, como mucho, ~220 → ~180 ms y **no está demostrada**
> (la base no se pudo repetir limpia sin reinstalar el plugin viejo). La CPU/RSS en reposo (16:31 y 16:46+) y el coste de las animaciones
> (16:47–16:50) quedan fuera de esa ventana.

Método: `escritorio-tactil/osk-latencia.py` (socket2 de Hyprland, del `hyprctl` que cambia el foco al evento `openlayer>>omarchy-keyboard`, restando el
arranque de `hyprctl`, 16 ms); CPU/RSS con `/proc/<pid>/stat` durante 60 s en reposo. Línea base tomada **tras mover Megapixels (abierto por
la sesión de cámaras) al escritorio 9**: con su vista previa en pantalla Hyprland gastaba 27–29 % (no es del escritorio).

## 1. Teclado en pantalla (`touch-mode/fork`, plugin `omarkyy.tablet`)

**Aparecer/desaparecer.** Ya existía la aparición automática por input-method v2. Medido hoy:
- Cambiar a otra ventana sin campo: se oculta bien. Cerrar la app: lo oculta el respaldo de `activeToplevel`.
- **Escritorio vacío: no se ocultaba.** Hyprland 0.56 no manda `deactivate` porque el foco de teclado se queda en la superficie
  oculta (`imActive` seguía `true`). Arreglo en `Service.qml`: con el evento `activewindowv2` vacío se oculta, y al volver a una ventana
  cuyo campo sigue activo se muestra otra vez.
- La ventana de Nextcloud saca el teclado al enfocarla, pero es correcto: es su formulario de login con el campo «Server address».
- **Teclado precargado**: se crea una vez al arrancar el shell y luego solo se muestra u oculta, en lugar de instanciar ~70 teclas cada
  vez. Debería acelerar la aparición, pero la mejora medida limpia es pequeña e incierta (ver la corrección de arriba).

**Tamaño y disposición.** Siempre acoplado abajo y a todo lo ancho: 40 % del alto en horizontal y 34 % en vertical.
- Se quitan el pie de ayuda, el arrastre y el asa ◢ para dar ese alto a las teclas: 5 filas de ~70 px lógicos, unos 10 mm.
- Fila de números arriba, y ñ, ç, ¡, ¿, ´ y ` como teclas muertas; AltGr con @ # € [ ] { }. Pulsación larga con variantes, como
  antes: á à â ä, ñ, ¿, «», €…
- La barra espaciadora pasa de 3,2 a 5,2 unidades y muestra el idioma. Se quitan Inicio y Fin de la fila inferior; Supr sigue en la 2.ª fila.
- Captura: `capturas-escritorio-tactil-20261022/osk-sugerencias.png`.

**Sugerencias y autocorrección** (en C, dentro de `osk-daemon`: `fork/predict.h`).
- Diccionario FrequencyWords `es_50k`: OpenSubtitles 2018, **CC-BY-SA 4.0**, sha256 `dcff3ad4…`; ver `fork/dict/README`. Son 49 617
  palabras, se cargan en 31 ms y cada consulta tarda unos 2 ms en el PC. El demonio pasa de 2,6 a 9 MB de RSS.
- La cabecera del teclado muestra 3 sugerencias, con la mejor en el centro. «tam» → también / tampoco / tan; «graci» → gracias.
  Si ya hay una tilde o ñ escrita, se respeta.
- La autocorrección salta al escribir espacio o un signo de puntuación y es conservadora:
  - Tildes que faltan cuando la forma con tilde es ≥ 10× más frecuente (tambien, cancion, aqui, telefono, ano → año).
  - Palabras inexistentes de ≥ 4 letras con un único candidato claro (hloa → hola, graicas → gracias).
  - Retroceso justo después la deshace, y esa palabra ya no se vuelve a corregir.
  - El botón «Abc✓» la apaga.
  - **Nunca actúa** en terminales, contraseñas, PIN, URL ni correo (lo indica el `content_type` del campo), ni sobre texto largo como el dictado.
- Mayúscula automática al empezar frase, solo si el campo lo pide (hint `auto_capitalization`).
- Pruebas en la tablet (`escritorio-tactil/osk-pred-test.sh`, 11/11 verde dos veces): letra a letra por IPC en un `Gtk.Entry` propio
  (`osk-entry.py`) y en foot. **Toques reales por uinput**: «h o l» → «hola / hoy / hollywood»; tocar la central → «hola ».
- `predict-test.c` en el PC: 20/20 casos.

**Respuesta háptica: no hay hardware.** No hay motor de vibración (estudio de cámaras: `vibrator.motor_not_support=true`) y ningún dispositivo
de entrada tiene `ff` (`/sys/class/input/*/device/capabilities/ff` = 0). **Clic sonoro** opcional con el botón 🔇/🔊: QtMultimedia
`SoundEffect`, cargado solo si se activa. Activo, añade **+22 MB** al shell. **Por defecto, apagado** (duda 1). No lo he oído:
falta que lo confirme el dueño.

**Swipe: no se ha hecho** (duda 3). Lo ligero acertaría poco; lo bueno es un proyecto aparte.

## 2. Ventanas (`escritorio-tactil/tablet.lua` → `~/.config/hypr/tablet.lua`)
La API está leída en la fuente de Hyprland v0.56.2 (`src/config/lua/...`) y la config se aplicó con `configerrors` vacío.
- `hl.window_rule({ match = { float = false }, workspace = "empty" })`: cada app en mosaico se abre en su propio escritorio. Los diálogos
  flotantes siguen sobre su app.
- `hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0, border_size = 0 })`: con una sola ventana ocupa **1600×1002**,
  todo bajo la barra; medido con `hyprctl clients`.
- **Dividir**: `uke_dividir()`, en el gesto de **pellizco de 3 dedos hacia dentro**. Si hay una sola app, trae al lado la última usada:
  dos de 785 px. Si ya están divididas, las vuelve a separar. Medido con dos ventanas de prueba.
- **Al cerrar** la última app de un escritorio, el foco vuelve a la app usada antes en lugar de quedarse en el fondo vacío. Medido.
- Los gestos que ya había siguen igual. 3 dedos de lado = cambiar de app (escritorio). 3 dedos arriba = lanzador nuevo. 3 dedos abajo = cerrar.
  Separar 3 dedos = pantalla completa real.

## 3. Animaciones (en `tablet.lua`)
- Ventanas: `popin 92%`, 220 ms al abrir y 150 ms al cerrar.
- Escritorios: `slide`, 200 ms. Capas: fundido de 160/120 ms. El teclado entra deslizándose desde abajo (`hl.layer_rule`).
- Sin blur ni sombras (Omarchy ya los tiene apagados); también se apagan las animaciones de borde.
- **Coste medido**: 20 cambios de app (cada uno muestra u oculta el teclado) suponen 4,1 s de CPU de Hyprland con animaciones y 1,55 s sin
  ellas. Son ~125 ms de CPU por cambio. Bajar la de escritorios de 240 a 200 ms apenas cambia la cifra (4,07 s): el coste es redibujar, no la
  duración. En reposo no cuestan nada.

## 4. Plugins
- **Lanzador `uke.launcher`** (nuevo, `escritorio-tactil/uke.launcher/`):
  - Rejilla a pantalla completa de las apps (DesktopEntries) con iconos de 92 px y buscador arriba, que saca el teclado solo al tocarlo.
  - Se cierra con ✕, Esc, tocando el fondo o deslizando hacia abajo.
  - Lanza igual que el lanzador de Omarchy (`uwsm-app -- gtk-launch <id>.desktop`).
  - Los iconos salen de un índice propio como el de `AppLibrary` de Omarchy, porque `Quickshell.iconPath` devuelve vacío en este shell.
  - Ocupa el botón de la barra de `uke.apps` (desactivado) y el gesto de 3 dedos arriba. `nwg-drawer` ya no arranca (línea comentada en `autostart.lua`).
  - **Toque real** sobre el icono de Foot: Foot se abre en su escritorio y el lanzador se cierra. Captura: `capturas-escritorio-tactil-20261022/lanzador.png`.
- `crmne.hyprmoncfg`: **movido** fuera de los plugins. Ya estaba desactivado; un solo monitor.
- `radimsem.omafind`: **desactivado**. Daba 18 avisos QML por arranque y necesita el modelo EmbeddingGemma, que no está.
- Sin cambios: `omaplug` (comprueba actualizaciones solo, duda 7), `cjkaufman.omascale`, `backmeupplz.navidrome` (desactivado; es de la sesión
  resto-apps), los `uke.*`, `p0werj0int.powerbar`.

## Segunda ronda (19:1x–19:40, con turno, todo en la tablet)
- **Gestos de 3 dedos de extremo a extremo: 9/9** (`escritorio-tactil/gestos-e2e.sh`): un táctil multitoque virtual por uinput
  (`mt-inject.py`, MT tipo B, 3200×2136 como el panel) y una instancia **de prueba** de `uke-gestures.py --device <virtual> --act`
  (el demonio real sigue con el panel). Pellizco hacia dentro = dividir y repetido = separar; 3 dedos izq./der. = otra app y vuelta;
  3 arriba = lanzador; toque en ✕ = cierra; 3 abajo = cierra la app y vuelve a la anterior. Hyprland recibe los toques como del dedo.
- **Arreglo**: 3 dedos de lado usaba `r±1` y, con una app por escritorio, caía en escritorios vacíos; ahora `m±1` (solo escritorios con
  ventanas, da la vuelta). `gestures.workspace_swipe_create_new = false` para que el deslizamiento nativo desde el borde no cree vacíos.
- **Arranque en frío** (la tablet se reinició hacia las 19:05 por otra sesión): `configerrors` vacío, `tablet.lua` cargado, teclado
  precargado (`loaded:true`), `uke.launcher` activo con 162 iconos, nwg-drawer no arranca, `uke-gestures` activo, sin errores de los plugins.
- **Buscador del lanzador**: tocarlo saca el teclado **por encima** del lanzador (capas: lanzador 0,0 1600×1068; teclado 0,641 1600×427)
  y «fire» deja solo Firefox (`capturas…/lanzador-busqueda.png`). Las sugerencias también salen en buscadores (el campo es «normal»).
- **Teclado en vertical** (`uke-rotate 90` y vuelta a 0): capa de 1068×544 (34 %) a todo lo ancho, sugerencias correctas
  (`capturas…/osk-vertical.png`).
- Visto de paso (no es de esta sesión): notificación de Omarchy «App failure: Command not found: udiskie».

## No verificado / pendiente
- El pellizco y los gestos de 3 dedos **con la mano del dueño** (probados de extremo a extremo con un táctil virtual: 9/9; el umbral de pellizco salta con radio ×0,64 frente a 0,65 configurado: la mano real pellizca más).
- El clic sonoro de oído, y la escritura con el dedo del dueño (comodidad del 40 %).
- Arranque en frío: comprobado tras el reinicio de las 19:05 (ver segunda ronda).
- Fuera del encargo: `uke-touchd-pen.py` (root) gasta entre 6 y 15 % de un núcleo en reposo (duda 8).

## Revertir
`deploy.sh hypr-revert` · `launcher-revert` · `plugins-revert` · teclado: copia del plugin anterior en
`~omarchy/.local/share/uke-touch-mode/backup-plugin-20261022-163905` (o `git checkout 37b0f24 -- build/rootfs/deploy/touch-mode && deploy.sh osk`).
