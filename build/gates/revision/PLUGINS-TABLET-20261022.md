# Plugins de la shell en la uke — 22-oct-2026 (sesión plugins-tablet)

Omarchy 4.0.6 · Quickshell 0.3.2 · Powerbar como barra. Turnos con `uke-turno`. Ventanas: 18:5x y de 19:06 a 19:17.
No reinicié la tablet. Sí la reinició otra sesión, ver §4.
Solo reinicié la shell (`omarchy restart shell`, 3 veces).
Todo es reversible con `build/rootfs/deploy/plugins-tablet/deploy.sh revert`.
La copia previa está en `~omarchy/.local/share/uke-plugins/backup-20261022/` (`shell.json`, `uke.network/`).
Dudas para el dueño: `docs/historia/DUDAS-PLUGINS.md`.

## 1. Inventario y errores (journal de la shell, antes)

| Plugin | Estado | Problema medido |
|---|---|---|
| (shell) | — | **`inotifywait` no estaba instalado.** `Process failed to start … inotifywait … /plugins` en cada arranque, así que la recarga en caliente de plugins no funcionaba. |
| `uke.network` (Wi-Fi + QR) | activo | ~60 `TypeError: Cannot read property 'foreground'/'fontFamily' of null` en cada reescaneo de plugins: al desmontar, la barra desaparece antes que el panel. Además era una copia del panel de red de Omarchy anterior a la última actualización: usaba `Color` en lugar de `Commons.Color`. |
| `p0werj0int.powerbar` | barra | Los widgets «On demand» (omaplug, OmaScale, bandeja) **no se podían abrir con el dedo**: su cajón se abre con hover y en la isla central no había el asa «…» que se puede tocar (`managedStatus`: `mainVisible:false`). Avisos inocuos: `Binding loop … displayCutouts` y `PrefsTile implicitHeight`. Hubo un `JSON.parse` en `Bar.qml:2255` que no se repite en las shells de hoy. |
| `uke.bitwarden` | activo | `Commons.Translations is not a type` antes de las 17:03. Ya lo había corregido su sesión; 0 avisos en las shells nuevas. |
| `omaplug` | activo | `Unable to assign [undefined] to QColor` en `Row/Actions/Confirm.qml`, solo en shells anteriores al 22-oct. Hoy, con el panel abierto, 0 avisos. |
| `radimsem.omafind`, `crmne.hyprmoncfg` | desactivado / retirado | Lo hizo escritorio-tactil; no lo he tocado. |
| `backmeupplz.navidrome` | desactivado | 1 `TypeError … excludedCount of null` (de días anteriores). Es de resto-apps (pendiente de su visto bueno). |
| `omarchy.weather` | desactivado | Estaba en el `layout` pero desactivado. |
| `uke.bateria`, `uke.launcher`, `omarkyy.tablet` | activos | Sin errores. El lanzador y el teclado son de escritorio-tactil; no los he tocado. |

## 2. Arreglos (en la tablet y en el repo)

1. **`inotify-tools` 4.26.270-1** (ALARM `extra`; antes `pacman -S --print`: un solo paquete, no actualiza nada).
   Tras el arranque de las 19:06, `inotifywait -m -r … /home/omarchy/.config/omarchy/plugins` corre (PID en `deploy.sh check`).
2. **`uke.network` regenerado** desde el panel de red actual con `wifi-qr/patch-panel.py`, que añade el botón QR. Lleva un parche
   nuevo: alias `barFg/barFont/barUrgent` que toleran `bar == null` en lugar de `root.bar.*`.
   Resultado: 0 TypeError en las 3 shells siguientes (incluidos reescaneos). `Panel.qml` sha256 `6ce9a432…`.
3. **Powerbar**: `omaplug`, `cjkaufman.omascale` y `omarchy.tray` pasan a `visibility: shown` (IPC `powerbar setWidget`).
   `managedStatus` pasa a `[]`.
4. **`omarchy.weather` activado** (`omarchy plugin enable`).

## 3. Plugins del portátil (`omarchy plugin list` del PC)

| Plugin | Decisión |
|---|---|
| `omarchy.elsewhen` (reloj mundial con globo, first-party de Omarchy **dev**) | **Portado como `uke.elsewhen`**, ver abajo |
| `omarchy.weather` | Activado (§2) |
| `cjkaufman.omascale`, `omaplug`, `uke.bitwarden`, `p0werj0int.powerbar` | Ya estaban; ahora se abren con el dedo |
| `uke.serpbar`, `radimsem.omafind`, `crmne.hyprmoncfg`, `backmeupplz.navidrome`, `omarchy.dock`, `omarchy.remote-session` | Fuera, con el motivo en `docs/historia/DUDAS-PLUGINS.md` |

Ninguno lleva binarios: OmaScale es Python y Elsewhen es QML/JS, así que no hubo que recompilar nada para aarch64.
No he copiado credenciales: Navidrome sigue sin URL ni contraseña.

**`uke.elsewhen`** se genera con `deploy/plugins-tablet/port-elsewhen.py` a partir del árbol `dev` del portátil (MIT, Jason Fried).
El 4.0.6 de la tablet no tiene varias piezas de `dev`, que se calzan así:
- `Commons.I18n` → `UkeI18n.js`, con el catálogo `en` + `es-MX` del propio Omarchy y el idioma fijado al generar (`--lang=es`).
- `Style.duration(x)` → `x`.
- `ShellIpc` → `IpcHandler`.
- `KeyboardPanel` sin contenido perezoso → `UkeKeyboardPanel.qml`, una subclase de 30 líneas con `content`/`loadedContent`/`ensureContent()`.

Cambios para el uso táctil:
- Botón «Agregar una ciudad», campo de búsqueda y resultados a ≥ 48 px.
- La ✕ de quitar ciudad salía solo con hover: ahora también en la fila tocada, y mide ≥ 40 px.

Ajustes copiados del portátil: las 5 zonas (Madrid, Delhi, Tokio, Los Ángeles y Nueva York), °C y 24 h. La tablet tiene `LANG=C.UTF-8` y el portátil `es_ES`.

Comprobado: el contenido del plugin en la tablet coincide por sha256 con lo que genera el repo (21 ficheros).

## 4. Pruebas con el dedo (puntero absoluto por uinput, `touch-mode/osk-click.py`; capturas con `grim` como omarchy y `setpriv`)

| Widget | Toque → resultado |
|---|---|
| `uke.elsewhen` | Abre el panel: 5 ciudades, texto en español, 18 °C. Al tocar la fila de Delhi aparece su ✕ (`capturas-plugins-tablet-20261022/elsewhen-es-fila-tocada.png`) |
| `omarchy.weather` | Abre el panel: 15 °C y la previsión de 3 días |
| `cjkaufman.omascale` | Abre la lista de equipos de Tailscale con «Copy»/«Ping» |
| `uke.network` | Abre el panel de Wi-Fi con la red conectada; en la cabecera, el botón QR |
| `omarchy.audio`, `omarchy.power` | Abren sus paneles (salida/entrada UKE, perfil de batería) |
| `uke.bateria` | Cada toque pasa al **siguiente perfil** (journal: `uke-perfil root-set …`). Así está diseñado, ver duda. Lo dejé en «ahorro», como estaba |
| `omaplug` | Abre el panel. Enfoca el buscador y aparece el teclado, que tapa la mitad (`omaplug-con-teclado.png`) |
| `omarchy.tray` | Se abre, pero vacío: no hay ningún `StatusNotifierItem` registrado (`busctl --user`) |
| Puntos de la derecha | Abren las preferencias de Powerbar |

Mosaico: `capturas-plugins-tablet-20261022/mosaico-toques.png`.
Journal tras todas las pruebas: solo los 2 bucles de binding de Powerbar y avisos de `textinput` de Qt.

**No verificado:**
- Con el dedo real del dueño: el puntero simulado no es táctil, y Quickshell sintetiza el ratón a partir del toque.
- El «primer toque perdido» (3 veces, siempre el primero tras reiniciar la shell o tras un rato): está en las dudas.

**Incidencia ajena:** a las 18:58:34 una sesión hizo `systemctl poweroff` por SSH, sin turno visible porque el cerrojo vive en `/run`.
La tablet volvió en «modo carga» (sin escritorio) y a las ~19:05 arrancó normal.
Mi turno se perdió con el reinicio y lo volví a pedir. Avisé a la sesión de batería.

## 5. udiskie (19:27, orden del dueño)
`pacman -S --print` → 3 paquetes nuevos (`udiskie` 2.7.0-2, `python-yaml` 6.0.3-2, `python-docopt` 0.6.2-16), ninguno actualizado; `udisks2` ya estaba.
Instalados con turno y lanzados con el comando del autostart de Omarchy (`udiskie --automount --no-notify --no-tray`): proceso vivo como omarchy.
Quita la notificación «App failure: Command not found: udiskie» del arranque (a verificar en el próximo inicio de sesión).

## Revertir
- Configuración y plugins: `UKE_HOST=root@uke build/rootfs/deploy/plugins-tablet/deploy.sh revert`.
- `inotify-tools` no se desinstala: es inocuo, lo usa la propia shell de Omarchy.
- Para quitar solo Elsewhen: `omarchy plugin disable uke.elsewhen`.
