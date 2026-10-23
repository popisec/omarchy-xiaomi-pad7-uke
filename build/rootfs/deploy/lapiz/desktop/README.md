# Integracion del lapiz con el escritorio (offline, NO instalada) — 20-oct-2026

Tests: `cd build/rootfs/deploy/lapiz/desktop && PYTHONPATH=..:. python3 -m unittest test_desktop -v` (12 OK en el PC: parche de palma sobre copia temporal, `uke-pen-sync` con `hyprctl` falso,
`luac -p`, `udevadm verify`, claves de quirks contra los `.quirks` de libinput 1.32 instalado, tabla de botones contra `uke_pen.py`).

| Fichero | Para que |
|---|---|
| `hyprland-pen.lua` | `~/.config/hypr/pen.lua`: `input.tablet.output="DSI-1"` + ganchos que reaplican la orientacion |
| `uke-pen-sync` | lee `~/.local/state/uke-rotate/{deg,touchmap,penmap}` y hace `hyprctl eval 'hl.config({input={tablet={output=..,transform=N}}})'` (`--dry-run`, `--status`) |
| `systemd/uke-pen-sync.{path,service}` | unidades de usuario: `PathChanged=%S/uke-rotate/deg` dispara el sync tras cada `uke-rotate` (sin tocar `uke-rotate`) |
| `50-uke-pen.quirks` | libinput: `AttrTabletSmoothing=0` para vendor 0x2717 / product 0x4D80 |
| `71-uke-pen.rules` | udev: refuerza `ID_INPUT_TABLET` del nodo del lapiz y deja el de botones como teclado |
| `uke-touchd-palm.patch` | rechazo de palma (se aplica sobre la copia ya parcheada con `../uke-touchd-pen.patch`; el original no se toca) |
| `botones.json` | tabla maquina-legible de botones (la validada contra `uke_pen.py`) |

## 1. Rotacion
- `uke-rotate` solo gira DSI-1 y `input:touchdevice:transform`; el nodo del lapiz comparte espacio con el dedo (3200x2136 sin rotar), asi que se le aplica `input.tablet.transform` con el MISMO mapa (`touchmap`; `penmap` lo sustituye si el lapiz saliera girado distinto).
- Sintaxis Lua (Hyprland 0.56.2, ya comprobada que `hyprctl getoption input:tablet:transform|output` existe en el PC): `hl.config({ input = { tablet = { output = "DSI-1", transform = 1 } } })`; por dispositivo `hl.device({ name = "uke-focus-pen", ... })` (el nombre de la tableta, no «Tablet Tool»).
  - https://wiki.hypr.land/Configuring/Basics/Variables/ (seccion Tablet: transform, output, region_position, region_size, absolute_region_position, relative_input, left_handed, active_area_*; Tablettool: eraser_button_*, pressure_range_min/max), consultada 20-oct-2026.
  - https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/ (`hl.device`, «use the name of the Tablet...»), consultada 20-oct-2026.
- `region_*`: no hacen falta (el nodo ya cubre todo el panel); solo servirian para acotar el area util. La rotacion sobre un monitor ya girado la hace `transform`, no la region.
- Instalar (NO hecho): `install -m755 uke-pen-sync /usr/local/bin/`; como `omarchy`: `cp hyprland-pen.lua ~/.config/hypr/pen.lua`, anadir `require("hypr.pen")` al final de `hyprland.lua`; `cp systemd/uke-pen-sync.* ~/.config/systemd/user/ && systemctl --user enable --now uke-pen-sync.path`.
- Prueba en la tablet: `uke-rotate 90; uke-pen-sync --status; ` y dibujar una linea horizontal en rnote en cada orientacion.

## 2. libinput / udev / libwacom
- libinput exige a un tablet `ABS_X/Y` con resolucion, `BTN_TOOL_PEN` y `BTN_STYLUS` (https://wayland.freedesktop.org/libinput/doc/latest/tablet-debugging.html, 20-oct-2026): el nodo ya los anuncia (res 13). No hace falta hwdb (`60-evdev.hwdb` solo corrige resolucion) ni calibracion (el demonio ya emite pixeles del panel; Hyprland aplica la rotacion).
- libwacom: solo se necesita para el modo zurdo (https://wayland.freedesktop.org/libinput/doc/latest/tablet-support.html, 20-oct-2026); un uinput con bus 0x18 no lo casa y no se aporta `.tablet`.
- Quirks validos (doc https://wayland.freedesktop.org/libinput/doc/latest/device-quirks.html, 20-oct-2026): `AttrTabletSmoothing=1|0`, `AttrPressureRange=N:M`, `AttrEventCode`, `AttrInputProp`, `AttrSizeHint`, `AttrResolutionHint`, `Match{UdevType,Bus,Vendor,Product,Name,...}`. No existen `AttrEventCodeDisable`/`AttrInputPropEnable` (se usa `+`/`-`). `AttrTabletSmoothing` esta ademas en `/usr/share/libinput/50-system-lenovo.quirks` (libinput 1.32.0 del PC). **`AttrPressureRange` solo lo usan touchpads en los .quirks de sistema (19/19)**: no se activa; para la presion del lapiz, `input.tablettool.pressure_range_min/max` de Hyprland.
- Instalar (NO hecho): `install -Dm644 50-uke-pen.quirks /etc/libinput/local-overrides.quirks`; `install -m644 71-uke-pen.rules /etc/udev/rules.d/`; `udevadm control --reload; udevadm trigger -s input`. Comprobar: `udevadm info /dev/input/eventN | grep ID_INPUT`, `libinput quirks list /dev/input/eventN`, `libinput record`/`libinput debug-tablet` (paquete `libinput-tools`, no instalado en el PC).

## 3. Palma
- Problema (§28/§29): tras levantar el lapiz el dedo/palma vuelve a los 0,25–0,5 s; el parche original suelta el dedo con un touch-up normal (posible clic).
- `uke-touchd-palm.patch` (sin ejecutar en hardware): `PalmGuard` bloquea dedos con el lapiz en rango y `--palm-hold` s (0,5) tras el ultimo frame 0x509; los toques que aparecieron durante el bloqueo se ignoran hasta levantarse (por `tid`); el dedo apoyado al empezar se cancela con `ABS_MT_TOOL_TYPE=MT_TOOL_PALM` (`--palm-mode palm`, o `lift`); `--palm-area N` opcional (area >= N = palma siempre, desactivado). Quita el `tr.reset()` del camino del lapiz para conservar los `tid`.
- Aplicar a mano (el test lo hace en temporal): ver cabecera del `.patch`. Despliegue: se copia como `uke-touchd-pen.py` (como el resto del modo lapiz).
- SIN VERIFICAR: que libinput 1.32 convierta `MT_TOOL_PALM` de una pantalla tactil en cancelacion (si no, usar `--palm-mode lift`); que el tracker conserve `tid` tras una rafaga larga de lapiz; que el chip entregue frames de dedo mientras hay frames de lapiz; que 0,5 s sea el margen adecuado.

## 4. Botones y efectos (datos: `uke_pen.py`, `botones.json`)
| Fisico | Evento Linux (lapiz en rango) | Evento fuera de rango | Accion propuesta |
|---|---|---|---|
| Punta | `BTN_TOUCH` + `ABS_PRESSURE` 0..8191 (suelo 100 con contacto) | — | trazo; la curva de presion en la app |
| Boton pequeno | `BTN_STYLUS` (0x14B) por el nodo `uke Focus Pen` | `KEY_F19` (189) por `uke Focus Pen Buttons` | rnote: Ajustes > atajos de lapiz (boton del lapiz → p. ej. borrador); Xournal++: Preferencias > dispositivos, «Pen button 1» (SIN VERIFICAR en 0.x actual); Krita: atajo de «clic derecho»/opcion de eventos de raton, o Canvas Input Settings (SIN VERIFICAR); Hyprland: F19 libre |
| Grande arriba | NUNCA `BTN_STYLUS2` (SIGSEGV de quickshell/Qt, §28) | `KEY_PAGEUP` (104) | pasar de pagina en el visor/presentador; sin bind global |
| Grande abajo | NUNCA `BTN_STYLUS3` (no estandar en libinput) | `KEY_PAGEDOWN` (109) | idem hacia delante; sin bind global |
| Goma | no existe (no se anuncia `BTN_TOOL_RUBBER`) | — | emularla con el boton pequeno en la app |
| Inclinacion | no anunciada (sin decodificar) | — | — |
- Hyprland: solo F19 queda libre (ejemplo comentado en `hyprland-pen.lua`). **No** se atan PageUp/PageDown: son teclas globales del teclado fisico; si se quisiera, `hl.device` con `keybinds=false` para el nodo de botones no sirve (desactivaria todo) — hace falta bind por dispositivo (https://wiki.hypr.land/Configuring/Binds/ «Per-Device Binds», NO leido).
- rnote: sus novedades confirman atajos configurables de boton (stylus, raton) desde 0.4.0 y opcion para desactivarlos desde 0.11.0 (changelog en https://github.com/flxzt/rnote/blob/main/crates/rnote-ui/data/app.metainfo.xml.in.in, 20-oct-2026). Krita: https://docs.krita.org/en/reference_manual/preferences/tablet_settings.html (20-oct-2026) solo documenta «Use Mouse Events for Right and Middle clicks» para botones.
