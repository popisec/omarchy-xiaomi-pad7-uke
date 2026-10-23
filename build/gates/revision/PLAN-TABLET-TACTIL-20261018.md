# Plan: hacer la uke usable como tablet táctil (18-oct-2026)

Ronda de investigación con 6 subagentes Haiku (escalado, rotación, teclado en pantalla, gestos, apps/paneles,
hardware) + verificación propia en la tablet y en el PC el mismo día. Lo marcado **[medido]** se comprobó con un
comando el 18-oct-2026; **[fuente]** viene de la web (URL); **[hipótesis]** está sin verificar.

## 0. Punto de partida [medido, 18-oct-2026]

| Cosa | Estado |
|---|---|
| Pantalla | DSI-1 3200x2136 @120 (modos 144/90/60/50/48/30), 237x158 mm, `scale 2` → 1600x1068 lógicos, transform 0 |
| Táctil | `uke-nt36532-thp-touchscreen` (uinput, PROP=2 DIRECT), Hyprland lo ve como *Touch*; 10 slots |
| Teclas | `pmic_pwrkey` (encendido → suspender), `pmic_resin` y `gpio-keys` (volumen) |
| Sensores | **ningún dispositivo IIO**; ADSP y WPSS `running`; `CONFIG_QCOM_FASTRPC=m`, `CONFIG_QRTR=m`, sin `/dev/fastrpc*` |
| Brillo | `/sys/class/backlight/uke-backlight` 372/2047 |
| Hyprland 0.56.2 (`version.h` con tag v0.56.2: hyprpm puede compilar plugins) | Protocolos en el binario: `zwp_input_method_v2`, `zwp_text_input_v3`, `zwp_virtual_keyboard_v1` (strings del binario del PC, misma versión) |
| Opciones Hyprland | `cursor:hide_on_touch` existe (true por defecto); `input:touchdevice:transform` y `:output` existen; `gestures:workspace_swipe_touch` existe (false) |
| Barra Omarchy | alto = `[bar] size-horizontal` en `shell.toml` (por defecto 26 px lógicos, `Commons/Style.qml:342`); fuente `[font] base-size` (ahora 14) |
| Paquetes en ALARM `extra` | squeekboard 1.43.1-6, rnote 0.14.2, xournalpp 1.3.8, nwg-drawer 0.7.5, iio-sensor-proxy 3.9, firefox 157, chromium 153, nautilus 51.1. **wvkbd no está** (solo AUR). Para hyprgrass falta `glm` (meson/ninja/cpio ya están) |

## 1. Tamaños para el dedo (fase T1, esfuerzo S, sin riesgo de arranque)

- **Mantener `scale = 2`** (1600x1068 lógicos, entero y nítido). 2.25 y 2.5 dan resoluciones lógicas no enteras
  (1422.2, 1280x854.4) [medido por aritmética]; Hyprland 0.56.2 ya no trunca escalas fraccionarias
  [fuente: linuxiac 0.56.2], pero no compensa la pérdida de nitidez.
- Agrandar lo táctil en vez de la escala:
  - `shell.toml`: `[bar] size-horizontal = 40` (≈ 7,6 mm; el mínimo recomendado de objetivo táctil es 44–48 px
    lógicos [fuente: Material 48 dp / Apple 44 pt]) y `[font] base-size = 16`.
  - Hyprland: `gaps_in/out` y `border_size` más grandes (bordes de 4–6 px para agarrar con el dedo si se usa
    redimensionado por borde).
  - `cursor:hide_on_touch` ya está activo.
- Toolkits: GTK con `GDK_SCALE=2` (ya está); Qt6 sigue la escala de Wayland; Chromium/Electron nativos en
  Wayland sin `--force-device-scale-factor` (tooltips mal colocados [fuente: bbs.archlinux.org/viewtopic.php?id=308149]).
- 120 Hz vs 60 Hz: medir consumo con la batería real antes de decidir (pendiente de la medición de consumo).

## 2. Rotación (fase T2 manual: S–M; T6 automática: L, incierta)

**Manual primero** (no hay sensores visibles):
1. Probar en vivo `hyprctl keyword monitor DSI-1,preferred,auto,2,transform,1` + `input:touchdevice:transform`
   (y comprobar si Hyprland ya rota el táctil al rotar la salida, porque el dispositivo está ligado a DSI-1).
   Si el táctil no casa, rotar en `uke-touchd.py` (ya maneja el mapeo de ejes, `--invert-y`).
2. Script `uke-rotate {0,90,180,270,next}` que aplica monitor + táctil, guarda el estado en `~/.local/state/`
   y lo restaura al iniciar sesión.
3. Botón en la barra (plugin pequeño de Omarchy) + atajo con las teclas de volumen en combinación
   (p. ej. Vol+ y Vol- a la vez) + gesto (cuando haya gestos, §4).
4. Bloqueo de rotación = simplemente no auto-rotar.

**Automática (más tarde, proyecto de investigación):** el acelerómetro está en el SSC/Sensor Low Power Island del
ADSP. Camino de postmarketOS: `fastrpc` + `hexagonrpcd` (sirve el registro de sensores y calibraciones al DSP) +
`libssc` + `iio-sensor-proxy` con backend libssc [fuente: pmaports MR 4050 y 5953; iio-sensor-proxy MR 381].
Probado en SDM845 y alguno más nuevo; **ningún informe para SM7675/SM8550/SM8650**. Requisitos aquí: nodo DT de
fastrpc para el ADSP en nuestro kernel, cargar `fastrpc`/`qrtr`, y extraer de Android el registro de sensores
(`/vendor/etc/sensors/`, `/mnt/vendor/persist/sensors/`) — **no está en las cosechas de `build/android/`**.
Luego `iio-hyprland` o un script propio que escuche `monitor-sensor`. Techo de 3 ciclos.

## 3. Teclado en pantalla (fase T3, esfuerzo M)

- **squeekboard** (`pacman -S squeekboard`): implementa input-method-v2 + virtual-keyboard y Hyprland 0.56
  anuncia ambos protocolos y text-input-v3 [medido] → **aparición automática al enfocar un campo de texto**
  en apps GTK/Qt/Chromium que usen text-input-v3. Falta verificar: que salga en Hyprland (es el OSK de Phosh)
  y el layout español (ñ, acentos; si falta, se escribe un layout YAML propio).
- Respaldo: botón en la barra que alterne la visibilidad (squeekboard por D-Bus `sm.puri.OSK0 SetVisible`);
  wvkbd solo en AUR y con informe de cierre en Hyprland [fuente: jjsullivan5196/wvkbd#65].
- Omarchy tiene la discusión #10028 «omarchy-osk» (3-sep-2026) [fuente: github.com/basecamp/omarchy/discussions]:
  revisarla antes de construir lo nuestro.
- fcitx5: no hace falta para el OSK; el servicio `omarchy-fcitx5.service` que falla en bucle se resuelve
  enmascarándolo o instalando fcitx5 (decidir; no aporta táctil).
- La pantalla de bloqueo necesita OSK o desbloqueo táctil (discusiones #9600 y #14341 de Omarchy); por ahora el
  bloqueo está desactivado y el botón suspende sin contraseña.

## 4. Gestos (fase T4, esfuerzo M, riesgo: plugin alpha)

1. Nativo y sin riesgo: `gestures:workspace_swipe_touch = true` (deslizar con el dedo entre escritorios).
2. **hyprgrass** (horriblename/hyprgrass, alpha, ya con API Lua `hl.plugin.hyprgrass.*` [fuente: docs/configuration.md]):
   `pacman -S glm` + `hyprpm add … && hyprpm enable hyprgrass`; recompilar tras cada actualización de Hyprland.
   Mapa propuesto:
   - borde superior ↓ → panel de notificaciones / ajustes rápidos de la barra;
   - borde inferior ↑ → lanzador (o mostrar teclado);
   - 3 dedos ← → → cambiar de escritorio; 3 dedos ↓ → cerrar ventana; 3 dedos ↑ → pantalla completa/flotar;
   - pulsación larga en borde de ventana → redimensionar (`resize_on_border_long_press`);
   - pellizco con 3 dedos → vista general.
   Salida de emergencia: `hyprpm disable hyprgrass` por SSH (siempre hay USB/SSH).
3. Plan B sin plugin: **lisgd** (lee el evdev del táctil y lanza comandos por borde/dirección/dedos).
   Alternativa propia: como el táctil ya pasa por **nuestro demonio**, `uke-touchd.py` puede detectar los gestos
   de borde él mismo y lanzar `hyprctl`/`qs ipc` sin plugin — la vía más robusta en este aparato.
- Clic derecho con pulsación larga: libinput lo rechaza [fuente: bugs.freedesktop.org 104033]; lo hacen las apps
  (Firefox `ui.click_hold_context_menus`, GTK4/Qt6 por su cuenta) o hyprgrass `longpress` con `mouse=true` [hipótesis].

## 5. Paneles desplegables, lanzador y apps (fase T5, esfuerzo S–M)

- Comprobar que los paneles del shell de Omarchy (ajustes rápidos, audio, wifi, bluetooth, calendario) se abren
  y se manejan con el dedo: son `MouseArea` de Qt Quick, que reciben el toque como clic izquierdo [fuente: doc Qt
  TapHandler/QTBUG-96030]; probar sliders (arrastre) y scroll en listas.
- Lanzador táctil: **nwg-drawer** (rejilla de apps a pantalla completa, en `extra`) en el gesto del borde inferior
  o en un botón de la barra; el menú de Omarchy queda para teclado.
- Apps: Firefox (pinch y scroll táctil nativos en Wayland; `ui.click_hold_context_menus=true`), Nautilus (GTK4),
  **Rnote** o **Xournal++** para notas (con lápiz cuando exista), visor de PDF GTK4 (Papers/Evince).
  Las TUI y la terminal no son táctiles: dejarlas para teclado.

## 6. Hardware que falta para uso diario

| Ítem | Estado | Camino | Esfuerzo |
|---|---|---|---|
| Brillo manual | `brightnessctl -l` ve `uke-backlight` 372/2047 [medido] | slider de brillo de la barra / binds `XF86MonBrightness*`; comprobar que el OSD de Omarchy lo usa | S |
| Segundo chip KTZ8866 (7-0011) | pendiente; solo se controla el primero (`docs/historia/ESTADO-VIVO.md`) | ampliar el driver de backlight a los dos | M |
| Auto-brillo | ALS stk3bcx detrás del SSC (`RE-FOLIO-SENSORES.md:82-90`) | mismo muro que T7 | L |
| Teclas de volumen | `pmic_resin` = KEY_VOLUMEDOWN (114), `gpio-keys` = KEY_VOLUMEUP (115) [medido por bitmap de `/proc/bus/input/devices`] | Omarchy ya bindea `XF86AudioRaise/LowerVolume` → OSD; útil en cuanto haya audio; mientras, Vol± a la vez = rotar | S |
| Batería en la barra | `qcom-battmgr-bat` capacity 61, Charging [medido]; upower instalado | verificar que powerbar la muestra | S |
| Apagar pantalla por inactividad sin bloquear | hypridle 0.1.8 instalado pero no corre; DPMS off/on ya probado con recarga del táctil (`deploy/tactil/README.md`) | hypridle: atenuar 60 s → DPMS off 2 min → suspender 10 min, sin `lock` | S |
| Tapa magnética (funda) | Android: `lid_hall` SW_LID gpio 99, `table_hall` SW_TABLET_MODE gpio 100 (`RE-FOLIO-SENSORES.md:42-63`) | nodo `gpio-keys` en el overlay dtbo → cerrar tapa = suspender (necesita ciclo de flash) | S–M |
| Teclado Focus (pogo) | MCU Nanosic 803 en i2c@a8c000 0x4c, HID teclado/ratón/touchpad identificados; protocolo sin resolver | RE + driver i2c-hid o propio | M–L |
| Lápiz | ejes conocidos (presión 13/14 bit, tilt ±60), datos en el stream THP que parsea el HAL; borrador de parche, sin captura de frames de pluma | capturar frames de pluma en Android → ampliar `uke-touchd.py` con un dispositivo uinput tablet (BTN_TOOL_PEN, ABS_PRESSURE, ABS_TILT) | L |
| Altavoces | tras el audio (sesión aparte, E2 pendiente de autorización) | — | M |
| Cámaras / vibración | sin estudio | fuera de alcance por ahora | XL / ? |

## 7. Orden propuesto

| Fase | Qué | Esfuerzo | Riesgo | Depende de |
|---|---|---|---|---|
| T1 | Tamaños: barra 40, fuente 16, bordes; workspace_swipe_touch | S | nulo (config de usuario) | — |
| T2 | Rotación manual: `uke-rotate` + botón + atajo; táctil rotado | S–M | bajo | — |
| T3 | squeekboard con aparición automática + layout español + botón | M | bajo | — |
| T4 | Gestos de borde (demonio propio o hyprgrass) | M | medio (plugin alpha) | T2 (rotar gestos) |
| T5 | Paneles desplegables y lanzador táctil, apps táctiles | S–M | nulo | T1, T4 |
| T6a | Diario barato: brillo, hypridle (DPMS sin bloqueo), batería en barra, Vol± | S | nulo | — |
| T6b | Tapa magnética por gpio-keys (overlay) | S–M | ciclo de flash dtbo | ledger |
| T6c | Lápiz (captura en Android + uinput tablet) | L | bajo (userspace) | captura |
| T6d | Teclado Focus / segundo KTZ | M–L | según vía | RE |
| T7 | Auto-rotación por SSC (fastrpc + hexagonrpcd + libssc) | L | alto, incierto | registro de sensores de Android |

Cada fase se aplica por SSH en la config del usuario `omarchy`, con copia previa y paquete en
`build/rootfs/deploy/<fase>/`, y el dueño la valida con el dedo antes de seguir. Ninguna toca boot/dtbo.
