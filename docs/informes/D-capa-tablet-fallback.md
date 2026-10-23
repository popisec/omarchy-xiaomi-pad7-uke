# D — Capa tablet reutilizable sin el shell de Omarchy

**Proyecto:** Omarchy (Arch + Hyprland + Quickshell) en tablet ARM64 (Xiaomi Pad 7, SM7675,
Adreno 732, táctil Novatek NT36532, lápiz Xiaomi Focus Pen con presión/tilt).
**Objetivo:** extraer de `maxt.tablet-experience` (repo real:
https://github.com/gmaxxxie/omarchy-tablet-experience, v1.25.0, MIT) todo lo que funcione
sobre un **Hyprland pelado** (sin `omarchy-shell`, sin `o.*`/`hl.*`, sin Quickshell), como
capa de respaldo si el shell no compila o no arranca en aarch64.

**Estado:** análisis de código (no de READMEs) sobre el clon real, más dos repos afines:
`javon27/omarchy-surface-touch` (patch+build de `wvkbd-deskintl`) y
`alxcrt/omarchy-drawing-tablet` (mapeo de tableta gráfica). Todo lo que sigue cita fichero y
línea del repo original salvo que se indique otro.

> **Nota sobre versiones de Hyprland.** El plugin usa la **API Lua de Hyprland 0.56**
> (`hyprctl eval`, `hl.monitor()`, `hl.config()`, `hl.dispatch()`), introducida en Hyprland
> **0.55**. `hyprctl keyword` está **roto** en un Hyprland configurado en Lua
> (`"keyword can't work with non-legacy parsers. Use eval."` — `drawing/knowledge/hyprland-lua-tablet-config.md:9-13`).
> Esto es **Hyprland core**, no Omarchy: un Hyprland pelado ≥ 0.55 tiene `hyprctl eval` igual.
> **Consecuencia para la capa fallback: exigir Hyprland ≥ 0.55 y config en Lua**, o
> reescribir esas ~10 llamadas al formato clásico `hyprctl keyword monitor ...`.

---

## 1. Resumen ejecutivo

### Qué es reutilizable

De los **11 ejecutables** de `scripts/`, **9 son 100 % portables** a un Hyprland pelado en
aarch64 — 8 son Python/Bash que hablan con `hyprctl`, `evdev`, `sysfs` y binarios estándar,
y solo 2 tocan APIs de Omarchy (y en ambos casos es un único punto de fallo trivial de
sustituir: el OSD y el menú raíz). El plugin es **excepcionalmente limpio** en este sentido:
su autor ya aisló deliberadamente toda la lógica útil del shell.

| Componente | Portable sin Omarchy | Nota |
|---|---|---|
| `texp-rotate` | **Sí** | solo se pierde el OSD (`omarchy osd`) — 1 línea |
| `texp-orient` | **Sí, 100 %** | lee `/sys/bus/iio` directo; ni DBus ni Omarchy |
| `texp-touch` | **Sí** | solo se pierde `swipe-down` → menú (1 línea) |
| `texp-vk` | **Parcial (~95 %)** | pierde el theming por `omarchy theme color` (cosmético) |
| `texp-window` | **Sí** | pierde `omarchy-notification-send` (notificaciones) y el layout `scrolling` |
| `texp-close` | **Sí** | el paso "cerrar paneles Omarchy" no aplica; el resto sí |
| `texp-kbdetect` | **Sí, 100 %** | solo `sysfs` USB |
| `texp-bar-probe` | **Sí** | pero solo sirve para depurar la barra de Omarchy |
| `texp-vtext` | **Sí, 100 %** | post-proceso de dictado, puro Python |
| `texp-ink` | **Parcial (~90 %)** | mismo Python/GTK4; pierde solo el theming |
| `texp-hw-laptop-closed` | **Parcial** | el *concepto* sí; la línea PAM referencia un binario de Omarchy |
| `texp-priv-install` | **Sí** | instalador privilegiado, agnóstico |
| `config/hypr/tablet-experience.lua` | **Parcial (~70 %)** | `hl.config`/`hl.layer_rule`/`hl.bind` son Hyprland puro; `o.launch_on_start` y `omarchy-shell` no |

**Estimación global: ~85-90 % del valor funcional es reutilizable** sin Omarchy. Lo que se
pierde es una capa de *presentación y orquestación*, no de *capacidad*.

### Qué se pierde (y por qué)

1. **La máquina de estados laptop⇄tablet** y su persistencia: vive entera en `Service.qml`
   (QML/Quickshell). Sin shell hay que sustituirla por un daemon propio (Bash/Python + systemd
   user unit) que haga lo que hoy hace `Service.qml` por él mismo: vigilar el USB del teclado
   (`texp-kbdetect`), leer el estado y aplicar/deshacer rotación, barra y preload del OSK.
2. **La barra simplificada** y su **popup ⋮** (ocultar/mostrar iconos, `bar.layoutSnapshot`):
   es manipulación del JSON de la barra de Quickshell. Sin barra, no hay nada que simplificar.
3. **El popup de gestión de ventanas** y el botón ✕ de la barra: los *helpers* (`texp-window`)
   sí se reutilizan; el *UI* no existe.
4. **El panel/popup de rotación y la tira táctil sobre la barra** (`maxt-tablet-bar-strip`).
5. **El OSK en la pantalla de bloqueo de Omarchy** (ext-session-lock de Quickshell + regla
   `above_lock`). Con `hyprlock` o sin locker propio, la vía es otra (ver §3.6).
6. **El quick-switch de método de entrada** (`fcitx5-remote -t`) — el comando es portable, el
   botón de la barra no.
7. **El OSD de rotación** (`omarchy osd -i rotate-cw`): sustituible por `notify-send` o
   `swaync-client`, o simplemente un `echo` al journal.

### Lo más valioso del análisis

**La sincronización de la calibración táctil con la rotación.** Hyprland **no** rota las
coordenadas de entrada al rotar el monitor: hay que poner explícitamente el *mismo* índice de
transformación en el dispositivo táctil o los toques caen espejados. El plugin lo resuelve en
**una línea** (`texp-rotate:83`) y además documenta la convención de matrices exacta del
compositor (`texp-touch:27-29`), lo que permite reimplementar el mapeado raw→lógico en Python
para *saber dónde tocó el dedo* — algo que Hyprland no expone por IPC. Ver §2.

---

## 2. `texp-rotate` y `texp-orient` — rotación con calibración de entrada

### 2.1 `texp-rotate` (Bash, 89 líneas)

**Qué hace:** rota el monitor primario a 0°/90°/180°/270° o cicla, **preservando la escala**, y
arrastra el *transform* del dispositivo táctil en el mismo paso.

**Cómo detecta el monitor** (`texp-rotate:28-29`): primera entrada de `hyprctl monitors -j`,
override con `OMARCHY_ROTATE_DISPLAY`; fallback `eDP-1`:

```bash
DISP="${OMARCHY_ROTATE_DISPLAY:-$(hyprctl monitors -j 2>/dev/null | grep -o '"name": *"[^"]*"' | head -1 | cut -d'"' -f4 || true)}"
[ -n "$DISP" ] || DISP="eDP-1"
```

**Cómo cicla** (`texp-rotate:48-51`): lee el `transform` actual de `hyprctl monitors -j` con
`python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["transform"])'` y hace
`N = (cur + 1) % 4` para `next`, `(cur + 3) % 4` para `prev`.

**Preservación de escala** (`texp-rotate:62-78`) — el bug que documentan: llamar a
`hl.monitor()` **sin** campo `scale` re-deriva una escala por EDID/DPI y **pisa** la del
usuario (observado 1.25 → 1.6 en un ciclo laptop→tablet→laptop). El script lee la escala
*actual* del monitor emparejando por nombre y la pasa explícitamente.

**Las dos llamadas clave** — esto es el corazón del asunto (`texp-rotate:80-83`):

```bash
hyprctl eval "hl.monitor({ output = \"${DISP}\", transform = ${N}, scale = ${SCALE} })" >/dev/null
# Keep the touch device's calibration matrix in step with the screen, or taps
# land mirrored/mis-mapped on a rotated display.
hyprctl eval "hl.config({ input = { touchdevice = { transform = ${N} } } })" >/dev/null 2>&1 || true
```

Y el comentario de cabecera que explica *por qué* (`texp-rotate:20-25`):

> *Touch alignment: Hyprland does NOT re-map touch coords when the output rotates — the touch
> device keeps libinput's calibration matrix (`input:touchdevice:transform`, default 0 =
> identity), so a rotated screen would mis-map taps. We therefore set the touch-device
> transform to the SAME value as the monitor transform; the daemon in `texp-touch` mirrors
> this matrix when resolving touch points to logical coords.*

**Verificado contra el código de Hyprland 0.56.2** (el autor lo menciona en `texp-touch:22-23` y
en `DEVELOPMENT.md`): la convención de matrices es `MATRICES[8][6]` de `InputManager.hpp`, y
para los cuatro índices que usa el plugin (`texp-touch:29`):

```
t=0: (x, y)        t=1: (1 - y, x)     t=2: (1 - x, 1 - y)   t=3: (y, 1 - x)
```

Es decir: primero libinput aplica esa matriz a las coordenadas **raw ABS**, luego Hyprland
multiplica el resultado normalizado por el **tamaño lógico** del monitor (píxeles ÷ escala,
dims **intercambiadas** si el transform es 1 o 3).

**Adaptación sin Omarchy:** solo hay que tocar la línea del OSD (`texp-rotate:84-86`):

```bash
if [ "$SILENT" -eq 0 ]; then
  omarchy osd -i rotate-cw -m "Rotate: ${label}" >/dev/null 2>&1 || true
fi
```

Sustituir por `notify-send -i ... ` o por nada (ya es `|| true`, así que **el script funciona
tal cual sin Omarchy**, solo sin feedback visual). **Ninguna otra línea depende de Omarchy.**

### 2.2 `texp-orient` (Python 3, stdlib puro, 127 líneas)

**Qué hace:** clasifica la postura del dispositivo leyendo el acelerómetro **directamente de
sysfs** — sin `iio-sensor-proxy`, sin DBus, sin paquetes extra.

**Descubrimiento del dispositivo** (`texp-orient:32-57`): los números de `iio:deviceN` **no
son estables entre arranques** (documentado: `accel_3d` pasó de `device0` a `device1`), así que
primero busca por nombre y luego cae a "cualquier device con `in_accel_*_raw`":

```python
base = "/sys/bus/iio/devices"
accel_name = {"accel_3d", "accel_3d_0", "accelmountable", "accel_3d_inv", "accel_3d_normal"}
for dev in sorted(os.listdir(base)):
    ...
    if name in accel_name or ("accel" in name and "gyro" not in name):
        if os.path.exists(f"{path}/in_accel_scale") or os.path.exists(f"{path}/in_accel_x_raw"):
            return path
```

**Lectura** (`texp-orient:60-76`): escala de `in_accel_scale` (o `_scale_available`), y
`raw * scale` por eje → vector de gravedad en m/s².

**Clasificación por eje dominante** (`texp-orient:79-100`):

```python
dom = max(range(3), key=lambda i: abs(g[i]))
val = g[dom]
if abs(val) < 4.0:                      # near-flat fallback threshold
    return "unknown"
return ["left-up", "bottom-up", "bottom-up"][dom] if val > 0 \
    else ["right-up", "normal", "normal"][dom]
```

Tabla de calibración completa en el docstring (`texp-orient:84-93`), medida **físicamente** en
un ThinkPad X12 (4 posiciones). El propio autor advierte (`texp-orient:15-19`) que **el montaje
y los signos de los ejes cambian por placa** y que hay que recalibrar
(`texp-orient --watch`) — **crítico para el Xiaomi Pad 7**: esa tabla habrá que rehacerla.

> **Nota valiosa:** el comentario de `texp-orient:90-93` dice explícitamente que **NO usan el
> mapeo de `iio-sensor-proxy`** porque su propiedad D-Bus se queda en `"undefined"` en esa
> placa: *"the previous mapping followed the iio convention on X/Y which was rotated vs. this
> accelerometer's actual mounting."* La lectura directa de sysfs es **más robusta** y sin
> dependencias.

**Subcomandos:** `once` (default, una línea legible), `--json` (`{"g": [...], "label": "..."}`),
`--watch` (loop a 5 Hz para calibrar).

**Dependencias: cero.** Python 3 estándar. **100 % portable a aarch64.**

> **Contraste con `auto-rotate` de `omarchy-surface-touch`** (`surface/auto-rotate/auto-rotate.sh:63`):
> ese usa `monitor-sensor --accel` de `iio-sensor-proxy` y hace el *debounce* cancelando y
> relanzando un `sleep` en background (`:75-79`) — solo la lectura llega en `DELAY` segundos se
> aplica. Es una alternativa válida, y su README (`surface/auto-rotate/README.md:30-34`)
> confirma la misma técnica de rotación + calibración táctil:
> ```bash
> hyprctl eval "hl.monitor({ output = \"$MONITOR\", mode = \"$MODE\", position = \"$POS\", scale = $SCALE, transform = $transform })"
> hyprctl eval "hl.config({ input = { touchdevice = { transform = $transform } } })"
> ```
> El *debounce* es lo único que le falta a `texp-orient`: si se escribe un daemon de auto-rotación
> sin él, la pantalla "flashea" por todas las orientaciones al coger la tablet. **Portar el
> debounce de `auto-rotate.sh:70-80` al daemon propio.**

---

## 3. `texp-touch` y la capa de entrada

### 3.1 Cómo detecta el dispositivo (`texp-touch:294-326`)

Escanea `/dev/input/event*` con `python-evdev`, se queda con el que expone
`ABS_MT_POSITION_Y` **y** cuyo nombre contiene todas las claves de `TOUCH_NAME_KEYS`
(default `"wacom finger"`, configurable con `OMARCHY_TOUCH_NAME`) y **toma el último**
(`matches[-1]`). Maneja explícitamente el caso *"sin permisos todavía"*: ignora los nodos que no
puede abrir en vez de abortar, y el daemon reintenta cada 3 s (`texp-touch:462-479`).

> **Para el Xiaomi Pad 7 (Novatek NT36532) habrá que cambiar `OMARCHY_TOUCH_NAME`** al nombre
> del device del kernel (`Novatek`/`nt36532`...). Verificarlo con `evtest` / `python-evdev`.
> Hay además un caso de forma de stream que el código contempla (`texp-touch:218-226`): los
> streams de un solo contacto **omiten el prefijo `S`** (`ABS_MT_SLOT`) por completo y los
> frames mixtos etiquetan solo el 2º/3er contacto, así que un evento "desnudo" hereda el último
> slot visto.

**Lectura pasiva, sin `grab()`** (`texp-touch:5-6` y `texp-vk:33-34`): *"Passive listener on
the Wacom finger device (NO grab, like texp-vk)"*. Los eventos solo se observan, nunca se
consumen, así que Hyprland sigue recibiendo todo el táctil. Esto es lo que hace la técnica
compatible con el compositor.

### 3.2 Gestos (`texp-touch:231-247` y `:499-538`)

Máquina de estados por *slot* (`Tracker`, `texp-touch:173-226`) y clasificación al soltar el
último dedo (`texp-touch:231-247`):

| Gesto | Acción | Línea |
|---|---|---|
| 2 dedos, tap | **clic derecho** vía `ydotool click 3` | `:529` |
| 3 dedos, tap | `texp-vk toggle` | `:531` |
| 2 dedos, swipe ← | `hyprctl dispatch workspace +1` | `:533` |
| 2 dedos, swipe → | `hyprctl dispatch workspace -1` | `:535` |
| 2 dedos, swipe ↓ | menú raíz de Omarchy | `:537-538` |
| 1 dedo, tap | **enfocar** la ventana bajo el dedo | `:519-520` |

Constantes (`texp-touch:48-52`): segundo dedo en ≤ 700 ms del primero, tap con deriva ≤ 220
unidades raw y ≤ 1500 ms, swipe con recorrido ≥ 1250 unidades raw, cooldown 1.2 s.

**Ninguna acción sintetiza input táctil** (salvo el clic derecho): *"Gestures NEVER synthesise
input — they only run omarchy CLI/hyprctl, so they cannot fight Hyprland's own handling"*
(`texp-touch:6-7`). Detalle importante: las swipes de 2 dedos **no** son las de Hyprland (esas
son de 3 dedos), así que no compiten.

### 3.3 El clic derecho — `ydotool` y su disponibilidad en aarch64

`texp-touch:522-529`:

```python
if action == "tap2":
    # v1.12.2: two-finger tap = RIGHT CLICK ... Hyprland already moves the cursor to the touch
    # point on touch, so a bare `ydotool click 3` right-clicks exactly
    # where the fingers were (ydotoold must be running — install.sh /
    # the ydotool.service enable it).
    dlog("-> tap2 right-click at %s %s" % (lx, ly))
    run(["ydotool", "click", 3])
```

Y la infraestructura en `install.sh:473-496`: regla udev para `/dev/uinput`
(`KERNEL=="uinput", GROUP="input", MODE="0660", TAG+="uaccess"`, `install.sh:478-481`) y
`systemctl --user enable ydotool.service` (`install.sh:492`).

**¿ydotool en aarch64?** **Sí — paquete oficial de Arch Linux ARM**:
`https://archlinuxarm.org/packages/aarch64/ydotool` → **ydotool 1.0.4-2**, repo *extra*,
136 KiB instalados (verificado por HTTP 200 y `<h1>ydotool 1.0.4-2`). No está en Alpine
(probado, sin resultados), pero como el objetivo es Arch ARM, **no hay problema**.

> **Alternativa superior: `wtype`.** `wtype` **también existe en ALARM** (0.4-2, verificado) y
> es wlroots-nativo (`zwp_virtual_keyboard`, sin daemon, sin `/dev/uinput`, sin udev). Para
> **teclas y texto** es preferible. Para **botones de ratón** `wtype` no sirve, así que
> `ydotool` sigue siendo necesario para el clic derecho — o se usa el **protocolo Wayland
> directo** como hace `alxcrt/omarchy-drawing-tablet` en su v1.2.0
> (`drawing/knowledge/pen-buttons-and-pads-on-hyprland.md:60-65`): *"Hyprland offers
> `zwlr_virtual_pointer_manager_v1` (v2) and `zwp_virtual_keyboard_manager_v1` (v1) to every
> client, so the helper now speaks the Wayland wire protocol directly (standard library only:
> unix socket, `wl_registry.bind`, `create_virtual_pointer(seat)`, `button` + `frame` ...)"*.
> Eso **elimina `ydotoold`, `/dev/uinput` y la regla udev** — más limpio todavía, y **muy
> relevante en ARM**: cero dependencias binarias.

**Gotcha crítico del clic derecho** (`drawing/knowledge/pen-buttons-and-pads-on-hyprland.md:66-70`):
Quickshell 0.3.1 sobre Qt 6.11.2 **segfaultea** en `QQuickDeliveryAgentPrivate::contextMenuTargets`
cuando un clic derecho (`QContextMenuEvent`) llega a una de **sus** ventanas (fondo de pantalla,
barra, cualquier panel) — 14 crashes en una tarde. Pero **eso es un bug de Quickshell**: si no
hay shell de Omarchy, **no existe**. **El clic derecho por `ydotool` es más seguro sin Omarchy
que con él.**

### 3.4 El mapeado raw → lógico (lo que hay que reimplementar sí o sí)

Hyprland **no expone por IPC dónde tocó el dedo**. El plugin lo calcula en Python
(`texp-touch:123-141`), replicando exactamente el camino del compositor:

```python
def raw_to_logical(rx, ry, xmin, xmax, ymin, ymax, transform, mon):
    """Mirror Hyprland: calibration matrix on the touch device, then
    normalized * monitor logical size + monitor position."""
    fx = (rx - xmin) / (xmax - xmin if xmax > xmin else 1)
    fy = (ry - ymin) / (ymax - ymin if ymax > ymin else 1)
    if transform == 1:
        nx, ny = 1 - fy, fx
    elif transform == 2:
        nx, ny = 1 - fx, 1 - fy
    elif transform == 3:
        nx, ny = fy, 1 - fx
    else:
        nx, ny = fx, fy
    # monitor logical size (hyprctl width/height are PHYSICAL m_pixelSize)
    w = float(mon.get("width", 0)) / float(mon.get("scale") or 1)
    h = float(mon.get("height", 0)) / float(mon.get("scale") or 1)
    if int(mon.get("transform") or 0) % 2 == 1:      # 90/270: dims swap
        w, h = h, w
    return float(mon.get("x", 0)) + nx * w, float(mon.get("y", 0)) + ny * h
```

Tres detalles que **hay que copiar tal cual** o el mapeado sale mal:

1. **`transform` se lee del dispositivo táctil, no del monitor** (`texp-touch:144-152`) vía
   `hyprctl getoption input:touchdevice:transform -j` → campo `int`. Como `texp-rotate:83` lo
   sincroniza con el monitor, coinciden — pero el *source of truth* del mapeado es el del touch.
2. **`width`/`height` de `hyprctl monitors -j` son el tamaño FÍSICO** (`m_pixelSize`), hay que
   dividir por `scale` (`texp-touch:136-138`).
3. **En 90°/270° las dimensiones lógicas se intercambian** (`texp-touch:139-140`).

Hay incluso un **autotest con casos conocidos** (`texp-touch:550-589`) que valida las 4
transformaciones con monitor/scale dados — ejecutable con `texp-touch selftest`. **Es la pieza
más valiosa para portar/reproducir y verificar un mapeado propio.**

Para qué sirve ese mapeado más allá del clic derecho:
- **`focus_at(lx, ly)`** (`texp-touch:405-420`): Hyprland **no enfoca al tocar** (`Touch.cpp`
  *"routes the event but keeps keyboard focus"*), así que un tap dispara
  `hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'address:0x...' }))"`.
- **`record_last_touch(lx, ly)`** (`texp-touch:352-377`): guarda `"<lx> <ly> <addr>"` en
  `~/.local/state/texp-touch/touch-state` (0600, escritura atómica con `O_NOFOLLOW`, dir 0700 —
  líneas `:330-349`) para que `texp-close`/`texp-window` sepan qué ventana tocó el usuario.
- **`on_layer_surface(lx, ly)`** (`texp-touch:380-402`): consulta `hyprctl layers -j` y descarta
  toques sobre *layer surfaces* de nivel ≥ 2 (barra/paneles), para no registrar un toque en la
  interfaz como "última ventana tocada".

### 3.5 Dependencias de `texp-touch`

| Dep | ¿ALARM aarch64? | Fuente |
|---|---|---|
| `python-evdev` | **Sí** — 2.0.0-1 | archlinuxarm.org/packages/aarch64/python-evdev |
| `ydotool` | **Sí** — 1.0.4-2 (extra) | archlinuxarm.org/packages/aarch64/ydotool |
| `hyprctl` | **Sí** (parte de Hyprland) | — |
| regla udev `TAG+="uaccess"` en `/dev/input/event*` | — | copiar de `install.sh:444-451` |
| regla udev `/dev/uinput` | — | copiar de `install.sh:477-481` |

### 3.6 Nota: el screensaver

`texp-touch:423-450` implementa *tap-to-dismiss* del screensaver de Omarchy matando el proceso
por `pkill -TERM -f org.omarchy.screensaver`. **No aplica** sin Omarchy (no hay tal
screensaver), pero el patrón (detectar el locker y desbloquear con un toque) sí es
replicable contra `hypridle`/`hyprlock` matando el proceso de bloqueo o llamando a
`hyprlock`'s IPC.

---

## 4. `texp-vk` y el teclado virtual

### 4.1 El daemon y el backend

`texp-vk` (Python 3, 425 líneas) es **backend-agnóstico**: prefiere `wvkbd-deskintl` y cae a
`squeekboard` (`texp-vk:151-154`):

```python
def vk_backend():
    """Return the binary name to control: wvkbd-deskintl if present, else squeekboard."""
    return VK_WVKBD if shutil.which(VK_WVKBD) else VK_SQUEEK
```

**Arranque del OSK** (`texp-vk:202-219`) — decisivo: se lanza con `setsid`, oculto, con alturas
de 350 px en las dos orientaciones:

```python
subprocess.run(["setsid", VK_WVKBD, "--hidden",
                "-H", VK_HEIGHT_PORTRAIT, "-L", VK_HEIGHT_LANDSCAPE]
               + vk_theme_args(),
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
               start_new_session=True)
```

**Control de visibilidad** (`texp-vk:222-233`) — **wvkbd por señales, squeekboard por D-Bus**:

```python
if name == VK_WVKBD:
    # wvkbd: SIGUSR2 = show, SIGUSR1 = hide
    subprocess.run(["pkill", "-USR2" if visible else "-USR1", "-x", VK_WVKBD], capture_output=True, timeout=3)
else:
    subprocess.run(["busctl", "--user", "call", DBUS_SVC, DBUS_PATH, DBUS_IFACE, "SetVisible", "b",
                    "true" if visible else "false"], capture_output=True, timeout=3)
```

(Servicio D-Bus de squeekboard: `sm.puri.OSK0` / `/sm/puri/OSK0`, `texp-vk:95-97`.)

**Estado de visibilidad** (`texp-vk:165-176`): espejado a `$XDG_STATE_HOME/texp-vk/visible`
(`"visible\n"` / `"hidden\n"`) para que el shell lo pueda sondear sin introspección D-Bus.
**Portable tal cual.**

**Gesto de borde** (`daemon`, `texp-vk:297-405`): swipe de **un dedo** que empieza en el 12 %
inferior y sube ≥ 150 unidades raw → mostrar (`:394-399`); arrastre hacia abajo ≥ 220 unidades
empezando por debajo del 68 % inferior → ocultar (`:400-405`). **Desactivado por defecto desde
v1.2.1** (`texp-vk:10-13`) — se re-habilita añadiendo `o.launch_on_start("texp-vk daemon")`.

> **Gotcha de memoria ya resuelto** (`texp-vk:346-349`): la versión vieja hacía `touches.pop(-1)`
> al soltar, lo que **fugaba** cada tracking ID real (release se reporta como `TRACKING_ID=-1`
> en el *slot activo*). El código actual borra el tid **ligado a ese slot**, no la clave literal
> `-1`, y capa el diccionario a 16 (hallazgo 1 de la revisión de seguridad). **Si se reimplementa
> el gesto, copiar esta lógica.**

### 4.2 Theming: el único acoplamiento a Omarchy

`texp-vk:179-199` resuelve 13 colores desde `omarchy theme color --all` (TAB-separado
`key<TAB>#hex`) y los pasa como flags `--bg`, `--fg`, `--press`, `--text`... **Si la llamada
falla, usa un fallback Gruvbox hardcodeado** (`texp-vk:79-93`). O sea: **sin Omarchy el teclado
funciona igual, solo con la paleta por defecto**. Sustituible por una lista de colores propia o
por `OMARCHY_VK_THEME=off`.

Detalle ya aprendido (`texp-vk:196-198`): *"wvkbd-deskintl does NOT accept a '#' prefix on color
args (a '#' hex is silently ignored and the default palette is used) — strip it."* — el `.lstrip("#")`
es obligatorio.

### 4.3 OSK en lock/login

- **Lock de Omarchy** (`config/hypr/tablet-experience.lua:40-48`): regla de capa `above_lock = 2`
  para el namespace `wvkbd` — *"render the virtual keyboard ABOVE the Quickshell
  ext-session-lock surface ... and keep it interactive; `above_lock`: 2 = visible above +
  interactive on lock"*. Y `texp-vk:248-253`: `start-hidden` pre-arranca el backend **antes** de
  bloquear, para que el lock lo muestre por señal *"instead of opening a new Wayland client under
  the lock"* — técnica reutilizable con cualquier locker (si el locker es una layer surface
  propia, hay que darle a `wvkbd` una regla de capa equivalente).
- **Login SDDM** (`texp-sddm-vk`, Bash, 65 líneas): SDDM lanza su **propio** compositor
  Hyprland con `config/sddm/tablet-hyprland.lua`, que ejecuta el script una vez al arrancar el
  compositor (`hl.on("hyprland.start", ...)`, `tablet-hyprland.lua:25-27`). El script tiene una
  lógica de 3 pasos **100 % aparcable de Omarchy**:
  1. ¿teclado folio conectado por USB (`17ef:60fe`)? → no hacer nada (`texp-sddm-vk:34-42`);
  2. ¿hay táctil? (`grep -riE 'touchscreen|wacom|elan.*touch' /sys/class/input/input*/name`, `:46-49`) → si no, nada;
  3. elige el primer binario disponible de `wvkbd-deskintl wvkbd-mobintl wvkbd squeekboard` y lo lanza visible con `setsid "$VK" -H 350 -L 350` (`:52-65`).
  El *drop-in* de SDDM está en `texp-priv-install:87-93`: `/etc/sddm.conf.d/100-tablet.conf`
  con `CompositorCommand=start-hyprland -- --config /usr/share/sddm/tablet-hyprland.lua`.
  **Todo esto vale para un SDDM normal, sin Omarchy** (solo cambia la ruta del config del
  compositor del greeter, que hay que escribir a mano).

### 4.4 `wvkbd-deskintl` — por qué no basta el AUR y cómo compilarlo

**Dos patches distintos, dos repos, ambos necesarios en tablet real:**

#### (a) `hide-key` (▼) — de `maxt.tablet-experience`

Motivo (`texp-install-wvkbd:6-16`): el paquete AUR `wvkbd` **solo trae `wvkbd-mobintl`**
(estilo teléfono, sin Super/Alt/Ctrl), así que hay que compilar la variante `deskintl`. Y *"it
ALSO applies the project's 'hide-key' patch: a visible ▼ collapse key on the bottom row, so
touch users can fold the on-screen keyboard away on the lock screen, the SDDM login screen and
in normal tablet use (wvkbd has no built-in dismiss key)."*

El patch (`config/wvkbd/wvkbd-hide-key.patch`, 2632 bytes) toca 4 ficheros:
- `keyboard.h`: nuevo tipo de tecla `Hide` (`patch:8-10`);
- `keyboard.c`: `extern void hide_keyboard(void);` + `case Hide: hide_keyboard(); break;` (`patch:21-34`);
- `main.c`: `void hide_keyboard() { hide(); }` (`patch:43-47`);
- `layout.deskintl.h`: añade `{"▼", "▼", 1.0, Hide, .scheme = 1}` a **dos** layouts (`patch:55-68`).

**El build es trivial** (`texp-priv-install:294-339`): descarga el tarball pinned
`https://git.sr.ht/~proycon/wvkbd/archive/v0.20.tar.gz` (SHA-256
`330e7d41e2ccf3f984af701c0d055d919cff66710dfe05ce9d77e4ae6e1adc16`), verifica, extrae, aplica
el patch con `patch -p1`, y:

```python
subprocess.run(["make", "LAYOUT=deskintl"], cwd=src, check=True)
```

El propio script de usuario (`texp-install-wvkbd:35-36`) lista las deps de build:

```
sudo pacman -S --needed cairo pango wayland libxkbcommon scdoc
```

**Todas verificadas en ALARM aarch64:** `cairo` 1.18.4-1, `pango` 1:1.58.2-1, `wayland`
1.26.0-1, `libxkbcommon` 1.13.2-1, `scdoc` 1.11.5-1. Más `make`, `cc`, `curl`, `tar`, `patch`,
`sha256sum` (`texp-install-wvkbd:87-89`) — todos estándar. **Compila en aarch64 sin nada
especial** (es C puro + cairo/pango/wayland).

> **Advertencia de versión:** el patch está hecho contra **wvkbd v0.20** (`patch:2`). El fork
> de `surface` usa **v0.19.4** (`surface/wvkbd/build.sh:13`), o sea **los dos patches NO se
> aplican juntos limpiamente**: hay que elegir una base y rehacer el otro patch a mano.

#### (b) `keyboard.c` flicker/no-repeat — de `javon27/omarchy-surface-touch`

`surface/wvkbd/README.md:10-25` describe el bug: `kbd_motion_key()` en `keyboard.c` corre en
**cada** evento de movimiento y, fuera de modo swipe, hace **incondicionalmente**
`kbd_unpress_key(kb, time)`. Los táctiles reales reportan *jitter* sub-píxel constante, así que
se dispara a los pocos frames: *"the highlight clears right after it appears (flicker), and
whatever repeat-timer state depends on 'key is still held' gets cancelled immediately (no
repeat)."*

El fix (`surface/wvkbd/keyboard.c.patch:16-19`):

```c
} else {
    struct key *current_key = kbd_get_key(kb, x, y);
    if (current_key != kb->last_press) {
        kbd_unpress_key(kb, time);
    }
}
```

**Este fix es obligatorio en un táctil real** (Novatek NT36532 dará el mismo jitter). Su
`build.sh` (`surface/wvkbd/build.sh:20-38`) hace exactamente lo mismo que el camino de
`texp-priv-install` pero **sin privilegios**, instalando a `~/.local/bin`:
descarga v0.19.4 de `git.sr.ht/~proycon/wvkbd/archive/v0.19.4.tar.gz`, `patch -p1`, `make -C
"$SRC_DIR" LAYOUT=deskintl || true` (ignora el fallo de `scdoc`, que es opcional) y
`install -m 755`. **Aviso de PATH** (`build.sh:40-42`): si `~/.local/bin` no va antes que
`/usr/bin`, se ejecuta el `wvkbd-deskintl` del AUR **sin** el fix.

#### Receta unificada para aarch64

El AUR ya tiene **`wvkbd-deskintl 0.19.4-1`** (verificado vía RPC: `aur.archlinux.org/rpc/v5/search/wvkbd`
→ `wvkbd 0.20-1`, `wvkbd-deskintl 0.19.4-1`, `wvkbd-git v0.18.r0.ged702f9-1`). Y `wvkbd` en
ALARM: **404 — no está en ALARM**, solo AUR. Ruta recomendada:

```bash
# Base: AUR wvkbd-deskintl 0.19.4 (trae ya el layout deskintl) + patch de flicker (v0.19.4)
yay -S --needed --makedeps wvkbd-deskintl cairo pango wayland libxkbcommon
git clone https://github.com/javon27/omarchy-surface-touch
cd omarchy-surface-touch/wvkbd && INSTALL_DIR=/usr/local/bin ./build.sh   # o ~/.local/bin primero en PATH
# Y añadir el hide-key ▼ a mano (el patch de texp es para v0.20): ver config/wvkbd/wvkbd-hide-key.patch
```

Alternativa limpia: clonar `wvkbd-deskintl` del AUR, meter **los dos** cambios en el `prepare()`
del PKGBUILD y `makepkg -si`. **No hay nada específico de x86 en wvkbd: compila en aarch64.**

---

## 5. El panel de tinta (`texp-ink`) y el lápiz

### 5.1 Qué es

`texp-ink` (Python 3 + GTK4, **42 KB / 1198 líneas**) es un panel de escritura a mano con
reconocimiento **offline** (PP-OCRv6 rec ONNX) cuyo resultado se inyecta en el cursor con
`wtype`. Precedente declarado (`texp-ink:5`): *"用笔或手指在面板上写字，识别结果通过 wtype 打进当前光标处（与 voxtype 语音输入同一套机制，CJK 可用）"* — el mismo camino que el dictado por voz, por eso funciona en terminales y en todo toolkit, también con CJK.

Modelo: `~/.local/share/texp-ink/models/ppocrv6_<tier>_rec.onnx` + `dict_v6.txt` (18708
caracteres). Tres tiers `tiny|small|medium`; **default `small`** (medido el más rápido *y* el
más preciso, `texp-ink:169-171`).

### 5.2 Captura de la presión del lápiz — GTK4 `GestureStylus`

`texp-ink:481-521`. Dos controladores separados y **excluyentes**:

```python
# --- 触控笔 ---
st = Gtk.GestureStylus()
st.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
st.connect("down", self._pen_down)
st.connect("motion", self._pen_motion)
st.connect("up", self._pen_up)
self.add_controller(st)

# --- 手指 / 鼠标 ---
dr = Gtk.GestureDrag()
dr.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
...
```

Y el filtro para no duplicar (el gesto de dedo ignora el lápiz, `texp-ink:523-534`):

```python
@staticmethod
def _is_pen(g) -> bool:
    ev = g.get_current_event()
    dev = ev.get_device() if ev else None
    if dev is None:
        return False
    src = dev.get_source()
    return src in (Gdk.InputSource.PEN, Gdk.InputSource.TABLET)
```

**La presión** (`texp-ink:509-521`):

```python
@staticmethod
def _pressure(g) -> float:
    try:
        v = g.get_axis(Gdk.AxisUse.PRESSURE)
    except Exception:
        return 1.0
    ...
    if v <= 0.0:
        return 1.0
    return min(v, 1.0)
```

Y se **usa de verdad** para modular el grosor (`texp-ink:298-302`):

```python
# 按压力调制线宽（0.55x ~ 1.0x），无压力数据时用满宽
press = 0.5 * (p0[2] + p1[2])
cr.set_line_width(max(self.stroke_w * (0.55 + 0.45 * press), 1.5))
```

→ **Presión capturada del Xiaomi Focus Pen vía GTK4 sin una sola línea de evdev.** Esto es
importantísimo: **la presión no necesita el shell de Omarchy en absoluto** — es GTK4 sobre
Wayland (`zwp_tablet_tool_v2`), que Hyprland expone. **Y además es la vía para escribir una app
de dibujo propia reutilizable** (ver §7).

> **Nota:** `texp-ink:299-301` también menciona que el eraser del lápiz AES funciona en apps de
> dibujo normales; el *tilt* no se usa en `texp-ink` (solo presión).

### 5.3 Salida con `wtype` y el truco de `keyboard_mode=none`

`texp-ink:930-941`:

```python
def _commit(self, text: str, replace: bool = False):
    if not text: return
    if replace and self.last_commit:
        self._key("BackSpace", repeat=len(self.last_commit))
    try:
        subprocess.Popen(["wtype", "--", text], ...)
```

Y el punto **crítico** de todo el diseño del panel — `LayerShell.set_keyboard_mode(NONE)`
(`texp-ink:669-672`):

```python
# 关键：不抢键盘焦点 → wtype 才能把字打进原来的应用
LayerShell.set_keyboard_mode(self.win, LayerShell.KeyboardMode.NONE)
if not LayerShell.is_layer_window(self.win):
    log("警告：layer-shell 未生效 —— wtype 可能把字打进面板自身")
```

Si el panel tomara el foco de teclado, `wtype` escribiría **dentro del propio panel** en vez de
en la app del usuario. Es el detalle que hace o rompe la funcionalidad y **es 100 % Hyprland
(layer-shell), nada de Omarchy**.

**El requisito de `LD_PRELOAD`** (`texp-ink:60-79`) — sí es un gotcha de empaquetado:

```python
_PRELOAD = "/usr/lib/libgtk4-layer-shell.so"
if (os.path.exists(_PRELOAD)
    and os.environ.get("TEXP_INK_NO_PRELOAD") != "1"
    and _PRELOAD not in os.environ.get("LD_PRELOAD", "")
    and ("__run" in sys.argv or "__selftest" in sys.argv)):
    _env = dict(os.environ)
    _env["LD_PRELOAD"] = (_PRELOAD + ":" + _env.get("LD_PRELOAD", "")).strip(":")
    os.execve(sys.executable, [sys.executable, os.path.abspath(__file__)] + sys.argv[1:], _env)
```

Comentario original: *"gtk4-layer-shell 必须早于 libwayland-client 载入（链接顺序问题）。发行版自带一个专用的 preload 库，用它自我重启一次即可。"* → **gtk4-layer-shell debe cargarse antes que libwayland-client**;
el script se re-ejecuta a sí mismo con `LD_PRELOAD`. **Anotar la ruta real del `.so` en Arch
ARM** (`/usr/lib/libgtk4-layer-shell.so` es la ruta que asume; verificar con
`pacman -Ql gtk4-layer-shell`).

**Reconocimiento** (`texp-ink:257-365`): `onnxruntime.InferenceSession(model,
providers=["CPUExecutionProvider"])`, render de los trazos a escala de grises 48 px de alto con
`cairo`, normalización `img/127.5 - 1.0`, replica a 3 canales, salida `[1, T, C]` y **dos
decodificadores**:
- `candidates()` (`:340-353`): pico por clase sobre el eje tiempo → 12 candidatos de un carácter (modo 单字);
- `sequence()` (`:356-365`): CTC greedy (salta repetidos y blank) → palabras en inglés / escritura conectada (modo 整行).

**Adaptación sin Omarchy:** lo único acoplado es `theme_colors()` (`texp-ink:370-...`), que
llama a `omarchy theme color --all` **con fallback hardcodeado** (5 colores, `:370-377`).
Sustituir por lectura de un color propio o por el fallback. **Todo lo demás funciona igual.**

### 5.4 ¿Es portable a aarch64?

**Sí, con una condición: `onnxruntime`.**

| Dep | ¿ALARM aarch64? | Estado |
|---|---|---|
| `gtk4` | **Sí** — 1:4.22.5-1 | ✅ |
| `gtk4-layer-shell` | **Sí** — 1.3.0-1 | ✅ |
| `python-cairo` | **Sí** — 1.29.1-1 | ✅ (200) |
| `python-numpy` | **Sí** — 2.5.3-1 | ✅ |
| `python-gobject` / Gir | (en `python-gobject`) | asumido ✅ |
| `wtype` | **Sí** — 0.4-2 | ✅ |
| **`onnxruntime`** | **NO en ALARM** (404) | ⚠️ **hay que instalarlo por otra vía** |

**El problema real: `onnxruntime` no está en Arch Linux ARM.** Verificado: `onnxruntime`,
`onnxruntime-cpu`, `python-onnxruntime`, `python-onnxruntime-cpu` → **todos 404 en
archlinuxarm.org**. En x86_64 el repo `extra` sí los tiene (`onnxruntime-cpu 1.29.0`,
`python-onnxruntime-cpu 1.29.0` — ambos **x86_64**) y el AUR tiene `onnxruntime-git`,
`onnxruntime-genai`, pero **no un paquete `python-onnxruntime` directo**.

Tres vías, de menos a más esfuerzo:

1. **`pip install onnxruntime` en un venv** — la opción más práctica **si** existe wheel
   `manylinux_2_28_aarch64` para la versión de Python. Históricamente PyPI **no** publicaba
   wheels ARM64 para Linux (sí para macOS arm64); hay PRs abiertos para añadirlos
   (`microsoft/onnxruntime#27760` "Add aarch64 wheel build to CUDA 13 Python packaging
   pipelines") y varios blogs confirman que en aarch64 el camino normal es **compilar**.
   **Verificar primero** con `pip index versions onnxruntime` / `pip download --only-binary=:all: --platform manylinux_2_28_aarch64 onnxruntime` antes de dar nada por hecho.
2. **Compilar desde fuente** (`onnxruntime`): `./build.sh --config RelWithDebInfo --build_shared_lib --parallel` (docs oficiales de inferencing). En ARM64 con 8 hilos tarda horas y necesita ~8-16 GB de RAM. Viable pero caro.
3. **AUR `onnxruntime-git`** (1.20.0.r11453) — es *git*, compila desde fuente igual; no ahorra nada real.

**Mitigación inteligente:** el panel **no necesita** el OCR para ser útil. El 90 % del valor
(captura de trazos con presión, panel layer-shell, inyección con `wtype`) funciona **sin
`onnxruntime`**: basta con sustituir el `Recognizer` por (a) guardar el trazo a PNG/SVG para
pasarlo luego por un OCR en otro sitio (p. ej. el host x86_64 por SSH), o (b) un
reconocedor alternativo ya presente en aarch64. **Arquitectura recomendada: separar "panel de
tinta" (portable, sin deps raras) de "motor OCR" (pluggable).**

**Modelo y diccionario:** el `install.sh` del plugin los descarga de
`PaddlePaddle/PP-OCRv6_*_rec_onnx` en HuggingFace y el diccionario de
`raw.githubusercontent.com/PaddlePaddle/PaddleOCR/main/ppocr/utils/dict/ppocrv6_dict.txt`
(`install.sh:420-426`) — descarga estática, **independiente de la arquitectura**.

---

## 6. Los 8 helper daemons — tabla completa

| Helper | Qué hace | Lang | Depende de Omarchy | Deps externas | ¿aarch64? | Cómo adaptarlo |
|---|---|---|---|---|---|---|
| `texp-rotate` | Rota monitor + calibra táctil, preserva escala | Bash | **No** (solo el OSD, 1 línea `:84-86`) | `hyprctl` (≥0.55, Lua), `python3` | ✅ | Quitar/sustituir el `omarchy osd` |
| `texp-orient` | Postura por acelerómetro (eje dominante) | Python3 stdlib | **No** | `/sys/bus/iio` | ✅ (recalibrar signos) | Ajustar tabla `classify()` a la placa; **añadir debounce** |
| `texp-touch` | Gestos 2/3 dedos por evdev pasivo (sin grab) | Python3 | **No** (solo `swipe-down`, `:537`) | `python-evdev`, `ydotool`, `hyprctl` | ✅ | Cambiar `OMARCHY_TOUCH_NAME` a Novatek; sustituir `swipe-down` |
| `texp-vk` | OSK: rellenar/ocultar/estado + gesto de borde | Python3 | **Parcial** (theming `:186`) | `python-evdev`, `wvkbd-deskintl`/`squeekboard` | ✅ | `OMARCHY_VK_THEME=off` o colores propios |
| `texp-window` | Resolver/cerrar/mover ventana tocada; layout de workspace | Bash | **No** (notificaciones `:169`) | `hyprctl`, `python3` | ✅ | Sustituir `omarchy-notification-send` |
| `texp-close` | Cierra ventana tocada (o panel abierto) | Bash | **Parcial** (paso 1 del panel) | `hyprctl`, `python3` | ✅ | Saltar el bloque de paneles Omarchy (`:43-85`) |
| `texp-kbdetect` | ¿teclado folio USB puesto? (sysfs) | Bash | **No, cero** | `/sys/bus/usb` | ✅ (cambiar VID:PID) | `OMARCHY_KB_VENDOR`/`PRODUCT` |
| `texp-bar-probe` | Inyecta taps uinput para probar la barra | Python3 | **Sí (concepto)** | `python-evdev` (uinput) | ⚠️ necesita `/dev/uinput` | Solo depuración; **no aplicar** sin barra |
| `texp-vtext` | Post-proceso de dictado (tabla de reemplazos) | Python3 stdlib | **No, cero** | — | ✅ | Tal cual |
| `texp-ink` | Panel de tinta + OCR PP-OCRv6 + `wtype` | Python3 GTK4 | **Parcial** (theming) | `gtk4`, `gtk4-layer-shell`, `cairo`, `numpy`, `onnxruntime`, `wtype` | ⚠️ `onnxruntime` **NO en ALARM** | Ver §5.4 |
| `texp-hw-laptop-closed` | Gate PAM: sin lector de huella en modo tablet | Bash | **No** (referenciado por PAM de Omarchy) | `/proc`, `/sys`, DMI | ✅ (ajustar DMI) | Añadir el DMI del Pad 7 o usar los overrides |
| `texp-priv-install` | Instalador privilegiado con digests pinneados | Python3 | **No** | — | ✅ | Tal cual |
| `texp-sddm-vk` | OSK para el greeter SDDM | Bash | **No** | `wvkbd`/`squeekboard`, `/sys` | ✅ | Tal cual (config del greeter a mano) |

**Los 3 que son 100 % portables sin tocar nada:** `texp-orient`, `texp-kbdetect`, `texp-vtext`.
**Los 2 que son Hyprland puro sin ningún rastro de Omarchy:** `texp-rotate` y `texp-touch`
(salvo 1 línea cada uno de presentación).

---

## 7. El plugin de dibujo (`alxcrt/omarchy-drawing-tablet`)

**Qué hace:** mapea una tableta gráfica (Wacom, Huion, XP-Pen, Gaomon, Ugee, o el
"Artist mode" de OpenTabletDriver) a una pantalla concreta y **mantiene el mapeo en hotplug y
tras cada reload de Hyprland** (`README.md:5-6`). Panel de UI en la barra + editor expandido
con preview, área personalizada en mm, left-handed, rotación en display tablets, modo ratón,
rango de presión, botones del lápiz → clics reales.

**Cómo aplica el mapeo** — **`hyprctl eval` puro, sin Omarchy** (`Model.js:95-97`):

```javascript
function hyprctlEvalCommand(lua) {
  return ["hyprctl", "eval", String(lua || "")]
}
```

Y la sentencia generada (`Model.js:1018-1042`):

```javascript
// The `hl.device` statement for one tablet. Every field is emitted, including
var fields = ["name = " + luaString(hyprlandDeviceName(name))]
...
return { lua: "hl.device({ " + fields.join(", ") + " })", notes: notes }
```

Más `hl.config({ input = { tablettool = { pressure_range_min = ... } } })` (`Model.js:1051`) y
`hl.config({ cursor = { hide_on_tablet = ... } })` (`Model.js:1060`).

**Verificado contra Hyprland 0.56.2** (`knowledge/hyprland-lua-tablet-config.md:9-13`):

```
hyprctl eval 'hl.device({ name = "wacom-one-by-wacom-m-pen", output = "desc:...", region_size = {2304, 1440} })'
```

Campos aceptados (`knowledge/hyprland-lua-tablet-config.md:20-23`): `enabled`, `output`,
`transform` (-1..7), `rotation`, `left_handed`, `relative_input`, `region_position`,
`region_size`, `absolute_region_position`, `active_area_position`, `active_area_size`.

**Cómo mantiene el mapeo** (`Service.qml`): un `Process` con
`udevadm monitor --udev --subsystem-match=input` como señal de hotplug (Hyprland **no** tiene
evento IPC para dispositivos de entrada — `knowledge/hyprland-lua-tablet-config.md:32-35`), un
`Connections { target: Hyprland; onRawEvent }` que re-aplica en `configreloaded` /
`monitoradded` / `monitorremoved`, y un debounce de 1.2 s.

**¿Reutilizable sin Omarchy? SÍ, y es de los más reutilizables.** La lógica pura está en
`Model.js` (64 KB de JavaScript sin dependencias de shell: parseo de udev/sysfs, libwacom,
geometría, generación de Lua) y `TabletEngine.qml` **solo** la envuelve. Para un Hyprland
pelado basta con:

1. un daemon (Bash o Python) que reproduzca `Service.qml`: `udevadm monitor` +
   `hyprctl` + debounce;
2. portar las funciones de `Model.js` que generan el Lua (`applyStatement`,
   `stylusStatement`, `cursorStatement` ~ `Model.js:1018-1060`) — o reescribirlas: son
   ~40 líneas de string-building;
3. llamar `hyprctl eval "<lua>"`.

**Y hay dos hechos de oro en su base de conocimiento** (`knowledge/`), todos verificados leyendo
el código de Hyprland 0.56.2:

- **`tablet-mapping-units.md`**: `region_size` va en **píxeles lógicos del output** (tamaño del
  modo ÷ escala, ejes intercambiados si el monitor está rotado → **recalcular en cada apply**,
  nunca almacenar píxeles); `active_area_*` va en **milímetros** de la tableta (el kernel expone
  `ID_INPUT_WIDTH_MM`/`ID_INPUT_HEIGHT_MM`).
- **`libinput-rotation-and-left-handed.md:16-28`**: **la rotación solo funciona en "display
  tablets"**. Hyprland rota pasando una matriz de calibración a libinput, y libinput **solo
  inicializa calibración** si el device tiene `INPUT_PROP_DIRECT`, o libwacom lo marca
  `IntegratedIn=Display|System`, o libwacom **no lo conoce**. *"Otherwise the call returns
  'unsupported' and Hyprland ignores the status, so a 90° or 270° request on an external tablet
  silently does nothing."* → **Aplicación directa a nuestro caso**: el táctil **integrado** del
  Xiaomi Pad 7 sí debe ser `DIRECT` (es una pantalla que el dedo toca), así que
  `input:touchdevice:transform` **debe** funcionar; pero si algún día se conecta una tableta
  gráfica externa (Focus Pen aparte), la rotación por `hl.device({transform=...})` no hará nada.
  **Verificar `properties` del táctil: `cat /sys/class/input/eventN/device/properties` — bit 1
  debe estar puesto.**
- **`tablet-identity-from-sysfs.md`**: para identidad de dispositivo, `/sys/class/input/eventN/device/id`
  (`vendor`, `product`, `bustype` — `0x18` = I²C para el táctil integrado de una tablet) y `uniq`.
- **`hyprland-ignores-enabled-for-tablets.md`** y **`stylus-options-are-global.md`**: los
  campos `pressure_range_*`/`eraser_button_*` **no** están en la allowlist por-dispositivo
  (`DEVICE_FIELDS`) y son **globales**; y hay un gotcha con el campo `enabled`.

---

## 8. Receta: capa tablet mínima sobre Hyprland pelado

### 8.0 Arquitectura propuesta

```
~/.local/bin/
  texp-rotate          # copiar tal cual, quitar el omarchy osd
  texp-orient          # copiar tal cual, RECALIBRAR classify()
  texp-touch           # copiar, cambiar OMARCHY_TOUCH_NAME, sustituir swipe-down
  texp-vk              # copiar, OMARCHY_VK_THEME=off
  texp-window          # copiar, quitar omarchy-notification-send
  texp-close           # copiar, saltar el bloque de paneles
  texp-kbdetect        # copiar, ajustar VID:PID
  texp-ink             # copiar si hay onnxruntime; si no, modo "captura sin OCR"
  texp-auto-rotate     # NUEVO: daemon propio (Service.qml no existe)
  texp-tablet-mode     # NUEVO: máquina de estados (Service.qml no existe)
~/.config/hypr/
  tablet-experience.conf     # o tablet-experience.lua si Hyprland ≥0.55 en Lua
  autostart.conf             # exec-once de los daemons
```

### 8.1 Rotación + calibración táctil (el núcleo)

Fichero `~/.local/bin/texp-rotate` — copia literal de `scripts/texp-rotate` con **un** cambio.
Las dos líneas que hacen todo el trabajo (`texp-rotate:80-83`):

```bash
hyprctl eval "hl.monitor({ output = \"${DISP}\", transform = ${N}, scale = ${SCALE} })" >/dev/null
hyprctl eval "hl.config({ input = { touchdevice = { transform = ${N} } } })" >/dev/null 2>&1 || true
```

Y el OSD sustituido (`texp-rotate:84-86`):

```bash
if [ "$SILENT" -eq 0 ]; then
  notify-send -i video-display "Rotate: ${label}" 2>/dev/null || true
fi
```

**Si el `libgtk4-layer-shell` no está o se quiere evitar `hyprctl eval`** (Hyprland < 0.55,
config formateada en `hyprland.conf` clásico), el equivalente es:

```
# en hyprland.conf (monitor: nombre,resolución,posición,escala,transform)
monitor = eDP-1, preferred, auto, auto, 1
input { touchdevice { transform = 1 } }

# en runtime:
hyprctl keyword monitor "eDP-1, preferred, auto, auto, 1"
hyprctl keyword input:touchdevice:transform 1
```

⚠️ **No mezclar**: si la config está en Lua, `hyprctl keyword` falla con *"keyword can't work
with non-legacy parsers. Use eval."* (`drawing/knowledge/hyprland-lua-tablet-config.md:9-11`).

**Preservar la escala** (copiar `texp-rotate:62-78`) — sin esto se pierde la escala del usuario
en cada rotación. Es un bug observado, no teórico (1.25 → 1.6).

### 8.2 Auto-rotación (daemon nuevo con el debounce de `surface`)

`texp-orient` solo da una lectura puntual. El daemon propio debe unir: sondeo de `texp-orient
--json` a ~5 Hz + **debounce** (copiar el patrón de `surface/auto-rotate/auto-rotate.sh:70-80`)
+ llamada a `texp-rotate -s N` + un fichero de bloqueo (`/tmp/rotation-locked`) para el toggle
manual. Esbozo:

```bash
#!/bin/bash
# texp-auto-rotate — sigue el acelerómetro y rota pantalla + táctil (con calibración)
LAYOUT=(normal left-up bottom-up right-up)   # índice = transform 0..3
TRANSFORM=(0 1 2 3)
LOCK="/tmp/rotation-locked"
DELAY="${ROTATE_DELAY:-0.5}"
pending=""
while :; do
  [ -f "$LOCK" ] && { sleep 0.3; continue; }
  lbl="$(texp-orient 2>/dev/null | awk -F' \\|' '{print $1}')"   # normal|left-up|right-up|bottom-up|unknown
  for i in 0 1 2 3; do
    if [ "$lbl" = "${LAYOUT[$i]}" ]; then
      [ -n "$pending" ] && kill "$pending" 2>/dev/null      # debounce: cancela el apply anterior
      ( sleep "$DELAY"; texp-rotate -s "${TRANSFORM[$i]}" 2>/dev/null ) &
      pending=$!
    fi
  done
  sleep 0.2
done
```

**Recalibrar primero** (obligatorio en el Pad 7, los signos cambian por placa —
`texp-orient:15-19`):

```bash
texp-orient --watch          # gira la tablet por las 4 posturas y lee g_raw + label
# si la etiqueta no cuadra con la postura, editar classify() (texp-orient:94-100)
# y la tabla del docstring (texp-orient:84-93)
```

### 8.3 OSK (wvkbd-deskintl) + toggle

1. **Compilar el OSK** (§4.4): `wvkbd-deskintl` (AUR 0.19.4) + patch de flicker
   (`surface/wvkbd/build.sh`) + hide-key ▼ a mano. Deps de build todas en ALARM (§4.4).
2. **Copiar `texp-vk`** con `OMARCHY_VK_THEME=off` en el entorno (o exportarlo en la unit).
3. **Bind de teclas** en `~/.config/hypr/bindings.conf` (o `.lua`):
   ```
   bind = SUPER, U, exec, texp-vk toggle
   ```
   En Lua (`hl.bind` — es Hyprland core, `config/hypr/tablet-experience.lua:50-52` tal cual):
   ```lua
   hl.bind("SUPER + U", hl.dsp.exec_cmd("texp-vk toggle"), { description = "Toggle virtual keyboard" })
   ```
4. **Modo libre de foco** — imprescindible para que las teclas lleguen a la app:
   `LayerShell.set_keyboard_mode(NONE)` es cosa del propio wvkbd (es wlroots-nativo), así que
   **ya funciona**; solo hay que asegurar la regla de capa si hay locker (§8.6).
5. **Arranque**: `exec-once = texp-vk start-hidden` (pre-arranca sin mostrar;
   `texp-vk:248-253`).

### 8.4 Gestos (texp-touch)

```bash
# 1. Identificar el device táctil real (Xiaomi Pad 7 / Novatek NT36532)
python3 -c "
import evdev
for p in evdev.list_devices():
    d = evdev.InputDevice(p)
    caps = d.capabilities()
    if 53 in [c[0] if isinstance(c,tuple) else c for c in caps.get(3,())]:
        print(p, repr(d.name))
"
# 2. Exportar el nombre como clave (el match es 'todas las palabras presentes en el nombre')
export OMARCHY_TOUCH_NAME="novatek"     # ajustar al nombre real (lowercase)
# 3. Permisos: udev uaccess (install.sh:444-451) + grupo input
#    /etc/udev/rules.d/99-tablet-experience-input.rules
#      SUBSYSTEM=="input", KERNEL=="event*", TAG+="uaccess"
# 4. clic derecho (install.sh:477-496): /dev/uinput + ydotool.service
#      KERNEL=="uinput", GROUP="input", MODE="0660", TAG+="uaccess"
systemctl --user enable --now ydotool.service
# 5. lanzar el daemon
texp-touch daemon
```

**Sustituir el `swipe-down`** (menú de Omarchy, `texp-touch:536-538`) por algo propio, p. ej.
un lanzador (`rofi`/`fuzzel`/`wofi`) o `hyprctl dispatch exec`. **Único cambio necesario.**

**Verificar el mapeado antes de fiarse** (el selftest ya está en el script):

```bash
texp-touch selftest      # valida las 4 matrices y el disparo de on_touch (texp-touch:550-589)
```

### 8.5 Permisos de input (paso que la gente omite y rompe todo)

De `install.sh:430-471`, dos concesiones complementarias e idempotentes:
1. **regla udev** `SUBSYSTEM=="input", KERNEL=="event*", TAG+="uaccess"` → logind concede ACLs
   de lectura a la sesión del seat activo (garantizado al añadir el device en el siguiente
   arranque);
2. **`usermod -aG input $USER`** → vía garantizada para toda sesión posterior.
   Para la sesión **actual**: `newgrp input -c 'texp-touch daemon'`.

Sin esto los daemons mueren al login y no hay gestos (`texp-touch:475-479`).

### 8.6 OSK en lock/login (sin Quickshell)

- **Lock:** si se usa un locker que crea su propia layer surface, hay que darle a `wvkbd` una
  regla de capa para quedar por encima. Con la API Lua de Hyprland (misma que usa el plugin,
  `config/hypr/tablet-experience.lua:40-43`):
  ```lua
  hl.layer_rule({ match = { namespace = "wvkbd" }, above_lock = 2 })
  ```
  `above_lock = 2` = *"visible above + interactive on lock"* (comentario en
  `tablet-experience.lua:27`). **Y precargar el OSK con `texp-vk start-hidden` antes de
  bloquear** — si no, hay que abrir un cliente Wayland *bajo* el lock (`texp-vk:248-253`).
  Con `hyprlock` (que no es layer-shell del mismo modo) puede no aplicar; ahí la vía es lanzar
  `wvkbd` ya visible antes de bloquear.
- **SDDM:** replicar `texp-sddm-vk` (`scripts/texp-sddm-vk`, portable tal cual salvo la ruta del
  config del compositor del greeter). El `CompositorCommand` del drop-in está en
  `texp-priv-install:87-93`:
  ```
  [Wayland]
  CompositorCommand=start-hyprland -- --config /usr/share/sddm/tablet-hyprland.lua
  ```
  Y el config del greeter (`config/sddm/tablet-hyprland.lua:13-27`) es Hyprland puro +
  `hl.on("hyprland.start", function() hl.exec_cmd("/usr/local/bin/texp-sddm-vk") end)`.

### 8.7 Panel de tinta

```bash
# deps (todas en ALARM salvo onnxruntime)
pacman -S --needed gtk4 gtk4-layer-shell python-gobject python-cairo python-numpy wtype
# onnxruntime: ver §5.4 (pip en venv, o compilar)
python3 -c "import onnxruntime" || echo "sin OCR: usar modo captura"
# fichero de preload REAL (comprobar la ruta)
pacman -Ql gtk4-layer-shell | grep '\.so'
```

Bind (`tablet-experience.lua:65-67` tal cual, es `hl.bind` = Hyprland core):

```lua
hl.bind("SUPER + I", hl.dsp.exec_cmd("texp-ink toggle"), { description = "Ink panel" })
```

### 8.8 Máquina de estados laptop⇄tablet (lo que NO existe fuera del shell)

`Service.qml` (64 KB) es lo que hoy une todo. Un sustituto mínimo (Bash + systemd user unit)
que replique lo esencial:

```bash
#!/bin/bash
# texp-tablet-mode — alterna modo al conectar/desconectar el teclado folio
MODE=f
while :; do
  kb="$(OMARCHY_KB_VENDOR=<vid> OMARCHY_KB_PRODUCT=<pid> texp-kbdetect)"
  want=t; [ "$kb" = attached ] && want=l
  if [ "$want" != "$MODE" ]; then
    MODE="$want"
    if [ "$MODE" = t ]; then
      texp-rotate -s 0                     # entrar a tablet: no rotar (v1.4); snapshot de escala
      texp-ink start-hidden 2>/dev/null     # pre-cargar el panel de tinta
      texp-vk start-hidden                  # pre-cargar el OSK
    else
      texp-rotate -s 0 --scale "$SAVED"    # salir a laptop: SIEMPRE 0° y restaurar escala
      texp-vk hide; texp-ink hide 2>/dev/null
    fi
  fi
  sleep 2
done
```

Reglas que el README documenta y hay que respetar (son decisiones de diseño, no accidentes):
**entrar a modo tablet NUNCA rota solo** (v1.4), y **salir a modo laptop SIEMPRE vuelve a 0°
landscape restaurando la escala** (el reset se encola si hay una rotación en curso).

### 8.9 Mapeo de tableta gráfica (si se conecta una Focus Pen como tableta externa)

Reutilizar el enfoque de `alxcrt/omarchy-drawing-tablet`: daemon con
`udevadm monitor --udev --subsystem-match=input` + `hyprctl eval "hl.device({...})"` +
`hl.config({input={tablettool={pressure_range_min=...}}})`. La lógica de generación de Lua está
en `Model.js:1018-1060` y el aviso de rotación (§7) aplica.

---

## 9. Dependencias en aarch64 — tabla con fuentes

Verificado por consulta HTTP a `archlinuxarm.org/packages/aarch64/<pkg>` y a la API RPC del AUR
(`aur.archlinux.org/rpc/v5`) el 26-sep-2026. `ALARM` = Arch Linux ARM, repo oficial aarch64.

| Dep | En ALARM aarch64 | Versión / repo | AUR | Alternativa | Notas |
|---|---|---|---|---|---|
| `python-evdev` | ✅ **Sí** | 2.0.0-1 (extra) | — | `pip install evdev` | Necesario: `texp-touch`, `texp-vk`, `texp-bar-probe` |
| `iio-sensor-proxy` | ✅ **Sí** | 3.9-1 | `iio-sensor-proxy-git` | **NO se necesita**: `texp-orient` lee sysfs directo | Solo si se usa el enfoque `monitor-sensor` de `surface` |
| `gtk4-layer-shell` | ✅ **Sí** | 1.3.0-1 | `gtk4-layer-shell-git` | — | Para `texp-ink`; **verificar ruta del `.so`** para `LD_PRELOAD` |
| `gtk4` | ✅ **Sí** | 1:4.22.5-1 | — | — | Trae `Gtk.GestureStylus` y `Gdk.AxisUse.PRESSURE` |
| `squeekboard` | ✅ **Sí** | 1.43.1-5 | `squeekboard-git` | — | Fallback de OSK (y trae variantes de layout en `config/squeekboard/`) |
| `wvkbd` / `wvkbd-deskintl` | ❌ **No** (404) | — | ✅ `wvkbd 0.20-1`, `wvkbd-deskintl 0.19.4-1`, `wvkbd-git` | **Compilar** (§4.4) | C puro + cairo/pango/wayland → compila en aarch64 sin problemas |
| `onnxruntime` | ❌ **No** (404) | — | `onnxruntime-git`, `onnxruntime-genai` (compilan de fuente) | `pip` (verificar wheel aarch64) o compilar | **El único bloqueo real del panel de tinta** |
| `wtype` | ✅ **Sí** | 0.4-2 | — | — | Inyección de texto wlroots-nativa; **sin daemon ni uinput** |
| `ydotool` | ✅ **Sí** | 1.0.4-2 (extra) | — | protocolo `zwlr_virtual_pointer_v1` | Necesario solo para el **clic derecho** |
| `voxtype` | ❌ **No** (404) | — | ✅ `voxtype 1.1.0-1`, `-bin`, `-cuda`, `-tray`, `-tui` | — | Dictado local (opcional; el `-cuda` no aplica a Mali/Adreno) |
| `fcitx5` | ✅ **Sí** | 5.1.23-1 | — | — | IME chino; `fcitx5-remote` es portable, el indicador de barra no |
| `python-cairo` | ✅ **Sí** | 1.29.1-1 | — | — | Render de trazos en `texp-ink` |
| `python-numpy` | ✅ **Sí** | 2.5.3-1 | — | — | Inferencia en `texp-ink` |
| `cairo`/`pango`/`wayland`/`libxkbcommon` | ✅ **Sí** | 1.18.4-1 / 1:1.58.2-1 / 1.26.0-1 / 1.13.2-1 | — | — | Deps de build de wvkbd |
| `scdoc` | ✅ **Sí** | 1.11.5-1 | — | opcional (`make ... \|\| true`) | Páginas man de wvkbd |
| `jq` | ✅ **Sí** | 1.8.2-1 | — | — | Lo usa `auto-rotate.sh` de `surface` |
| `libinput` / `libwacom` | ✅ **Sí** | 1.32.0-1 / 2.20.0-1 | — | — | Necesarios para la *base de datos* de `drawing-tablet` |
| `udev-hid-bpf` | ❌ 404 | — | — | instalar de Arch x86 no vale; compilar | Solo para pads de Huion/XP-Pen nuevos (no aplica al Pad 7) |

**En Alpine (si se barajara):** `py3-evdev` existe en el repositorio `testing`/`community` de
Alpine; **`iio-sensor-proxy` sí existe** en Alpine edge (`community`); pero `ydotool` **no
aparece** y `gtk4-layer-shell`/`onnxruntime`/`wvkbd` requieren compilar. **Alpine es
sensiblemente peor para esto que Arch ARM** — la ruta buena es Arch ARM + AUR.

> **Nota metodológica:** las consultas a `pkgs.alpinelinux.org` y al endpoint de búsqueda del
> AUR devolvieron respuestas vacías en varias pruebas (probable *rate-limit* o cambio de API);
> por eso la columna AUR se verificó con `aur.archlinux.org/rpc/v5/search/<name>`, que sí
> respondió. Los ✅ de ALARM están confirmados por HTTP 200 + `<h1>` del paquete.

---

## 10. Qué NO se puede replicar sin el shell de Omarchy

| Capacidad | Dónde vive | Por qué no se puede replicar | Sustituto |
|---|---|---|---|
| Barra simplificada + popup ⋮ de iconos | `BarWidget.qml` (20 KB), `Service.qml` | Manipula el JSON de la barra de Quickshell y su `bar.layoutSnapshot`; sin barra no hay "barra simplificada" | Barra propia (waybar) o **ninguna**; el heartbeat del plugin es que la barra *está* |
| Popup de gestión de ventanas (✕/mover a ws) | `BarWidget.qml` + `texp-window` | El UI no existe; el helper sí | Bind de teclado + `texp-window`; o un panel propio con `fuzzel`/`rofi` |
| Botón ✕ de cierre "a la ventana que tocaste" | `BarWidget.qml` + `texp-close` | El helper sí; el botón vivía en la barra | Bind + `texp-close` (usa el `touch-state` del daemon) |
| Tira táctil sobre la barra (`maxt-tablet-bar-strip`) | `config/hypr/tablet-experience.lua:35-37` + QML | Es un `zindex` sobre la barra de Omarchy | Bind de teclado o **swipe de borde** (ya lo hace `texp-vk`) |
| OSK en la pantalla de bloqueo de Omarchy | `Service.qml` + `above_lock` + IPC del lock | El lock es una *layer surface* de Quickshell con su propio IPC para mostrar el teclado | Ver §8.6: `above_lock` sí vale para cualquier layer-shell; con `hyprlock` hay que pre-lanzar el OSK |
| OSD de rotación (`omarchy osd`) | `texp-rotate:84-86` | CLI de Omarchy | `notify-send`, `swayosd`, o nada |
| Toggle EN⇄中 y su indicador | `BarWidget.qml` | El comando (`fcitx5-remote -t`) es portable; el botón no | Bind de teclado |
| Notificaciones de acciones | `texp-window:164-170` | `omarchy-notification-send` | `notify-send` |
| Máquina de estados persistente (sobrevive reloads del shell) | `Service.qml` + `shell.json` | La orquestación está en QML | Daemon propio (§8.8) + persistir estado en un fichero |
| Layout `scrolling` del workspace | `texp-window:228-266` | Es una extensión de layouts de Omarchy (no está en Hyprland core) | Usar `dwindle`/`master` de Hyprland; el helper ya detecta el layout actual |
| Filtro de huella en PAM | `texp-hw-laptop-closed` + PAM parcheado | El *concepto* es portable, pero la línea PAM referencia `/usr/bin/omarchy-hw-laptop-closed` | Adaptar el script (DMI del Pad 7 + el VID:PID correcto) e insertar la línea PAM propia |

---

## 11. Riesgos y no verificado

### No verificado (hechos que habría que comprobar en el hardware)

1. **`OMARCHY_TOUCH_NAME` para el Novatek NT36532.** El default es `"wacom finger"`. **Habrá
   que descubrir el nombre real del device** en el Pad 7 (`evdev.InputDevice(p).name`) y fijar
   la variable. Si el nombre no contiene las palabras buscadas, el daemon **no encuentra el
   táctil y sale con error** (`texp-touch:324-326`).
2. **Calibración de `texp-orient`.** La tabla de signos está medida **en un ThinkPad X12**
   (`texp-orient:82-93`). **El Xiaomi Pad 7 tendrá montaje y signos distintos** → hay que
   recalibrar con `--watch` y editar `classify()`. Los ejes X/Y en particular *"followed the iio
   convention ... which was rotated vs. this accelerometer's actual mounting"* — apunta
   precisamente a este tipo de desajuste.
3. **¿Existe un acelerómetro IIO en el Pad 7 y con qué driver?** `texp-orient` asume
   `/sys/bus/iio/devices/*` con `in_accel_x_raw`. En tablets ARM64 a veces el sensor va por el
   *sensor hub* del SoC (SM7675) o solo por `iio-sensor-proxy`. `monitor-sensor --accel`
   (de `iio-sensor-proxy`, que **sí está en ALARM**) es el primer test a correr.
4. **`INPUT_PROP_DIRECT` en el táctil del Pad 7.** Sin ese bit, `input:touchdevice:transform`
   puede ser ignorado por libinput (mecanismo confirmado en
   `drawing/knowledge/libinput-rotation-and-left-handed.md:16-28`) y la calibración de rotación
   **no funcionará**, por mucho que se copie el script. Comprobar
   `cat /sys/class/input/eventN/device/properties` (bit 1).
5. **`onnxruntime` en aarch64 por `pip`.** No verificado si existe wheel
   `manylinux_2_28_aarch64`. **Probar antes de diseñar nada en torno al OCR.** Si no hay wheel,
   horquillar: panel sin OCR.
6. **Los dos patches de wvkbd juntos.** `hide-key` es contra **v0.20**, el de flicker contra
   **v0.19.4**. **No se aplican simultáneamente sin ajuste**; hay que elegir base y portar el
   otro. No verificado cuál es más fácil de adaptar (probablemente el de flicker, que es un
   hunk de 12 líneas).
7. **Comportamiento del wvkbd bajo el locker que se elija.** `above_lock = 2` es una función de
   Hyprland (documentada en `tablet-experience.lua:23-27`), pero solo se ha probado contra el
   ext-session-lock de Quickshell. Con `hyprlock` **no verificado**.
8. **Que wvkbd compila en ALARM sin sorpresas.** Todos los headers están (verificado), pero no
   se ha ejecutado el build en aarch64.
9. **El renderizado `ARGB32 little-endian → R` de `texp-ink`** (`texp-ink:314`:
   `gray = arr[:, :, 2].astype(np.float32)`) asume endianness little-endian. **aarch64 es LE
   por defecto**, así que debería ser correcto — pero no está probado en este modelo.

### Riesgos

- **`hyprctl eval` exige Hyprland ≥ 0.55 con config en Lua.** Si la distro trae Hyprland < 0.55
  o una config clásica, **todos** los `hl.*` del plugin (rotación, mapeo de tableta, layout,
  layer rules) fallan. Hay que decidir **antes de empezar** qué estilo de config se usa y no
  mezclar (los `hyprctl keyword` no funcionan en modo Lua).
- **Condición de carrera al arrancar.** Los daemons de gestos necesitan `/dev/input` legible,
  lo que depende de que logind haya concedido las ACLs. El código ya reintenta
  (`texp-touch:465-479`, `texp-vk:309-323`), pero **sin la regla udev + grupo `input` es
  inútil**. Hacer esa parte **antes** de depurar gestos.
- **El `_spawn` de `texp-ink` con `LD_PRELOAD`** es frágil ante cambios de ruta del `.so` entre
  versiones del paquete. Verificar tras cada upgrade de `gtk4-layer-shell`.
- **Superficie de cambio:** este análisis es sobre **v1.25.0**. El proyecto va por 1.2x y
  cambia rápido (v1.12 → v1.25 con cambios grandes: OSK, ink, lock). **Pinnear el commit** al
  que se haga la portabilidad y revisar diffs, no seguir `main`.
- **`texp-window` interpola valores en expresiones Lua** — el propio código lo advierte
  (`texp-window:172-192`, hallazgo 2 de la revisión de seguridad) y valida con regex anclada
  (`^0x[0-9a-fA-F]{8,16}$`) antes de interpolar. **Conservar esas validaciones** al adaptar: es
  un path con `hyprctl eval`, no un `exec`.
- **El `texp-priv-install` tiene digests SHA-256 pinneados** (`texp-priv-install:67-80`,
  `:99-106`). Cualquier edición de los ficheros que instala **rompe la instalación privilegiada**
  hasta actualizar el digest. Relevante si se adaptan `tablet-hyprland.lua` o `texp-sddm-vk`.
- **`ytdotool` + `/dev/uinput`** o la alternativa `zwlr_virtual_pointer_v1` (preferible en ARM,
  cero deps binarias) — decidir cuál: `ydotool` ya está en ALARM, así que la vía rápida es
  `ydotool`; la limpia es el protocolo directo.

---

## 12. Conclusión

**La capa tablet de `maxt.tablet-experience` está inusualmente bien desacoplada del shell.** El
autor separó deliberadamente la lógica (`scripts/`, Python/Bash hablando con `hyprctl`/evdev/sysfs)
de la presentación (QML/Quickshell). De los 11 ejecutables, **9 son directamente portables** a un
Hyprland pelado: `texp-orient`, `texp-kbdetect` y `texp-vtext` **sin tocar una línea**, y
`texp-rotate`, `texp-touch`, `texp-window`, `texp-close`, `texp-ink` con **1-2 líneas** de
sustitución de presentación (OSD, notificaciones, menú).

**Las tres piezas que justifican el análisis:**

1. **La calibración táctil sincronizada con la rotación** (`texp-rotate:80-83`) — una línea que
   resuelve un problema que Hyprland no resuelve, con la convención de matrices documentada
   (`texp-touch:27-29`) y un **autotest ejecutable** (`texp-touch selftest`) para validarla.
2. **La captura de presión del lápiz con GTK4 puro** (`texp-ink:481-521`) — **cero** dependencia
   del shell, sirve igual para escribir una app de dibujo propia.
3. **La inyección de texto wlroots-nativa** (`wtype` + `keyboard_mode=none`) — portable y sin
   daemon, con `wtype` y `ydotool` **ambos disponibles en Arch Linux ARM aarch64**.

**Los dos únicos bloqueos reales:**

- **`onnxruntime` no está en ALARM** → el OCR del panel de tinta hay que resolverlo por `pip`
  (verificar wheel aarch64) o compilando. **Todo el resto del panel funciona sin él.**
- **`wvkbd-deskintl` no está en ALARM** → hay que compilarlo (~5 min, todas las deps en ALARM) y
  hay que **fusionar dos patches de dos repos distintos** hechos contra versiones diferentes.

**Lo que se pierde es orquestación y UI, no capacidad:** la máquina de estados, la barra
simplificada, los popups y el locker. Todo eso es sustituible por un daemon propio de ~50 líneas
+ binds de teclado + notificaciones estándar.
