# C — Hyprland 0.56 (config Lua) + shell Quickshell en aarch64, con GPU Adreno 732

**Proyecto:** Omarchy 4 «Quattro» en la Xiaomi Pad 7 «uke» (SM7675, Snapdragon 7+ Gen 3, Adreno 732 vía Mesa/freedreno, 12 GB RAM, aarch64).
**Fecha del informe:** 26-sep-2026.
**Alcance:** (1) la verdad sobre la config Lua, (2) Quickshell en aarch64, (3) dependencias del shell, (4) rendimiento en GPU modesta, (5) precedentes ARM, (6) riesgos.

> Regla del proyecto: **cada afirmación lleva URL**. Lo que no se ha podido verificar se marca explícitamente como **[NO VERIFICADO]**. Las versiones de paquete son las que servían `archlinuxarm.org` y `pkgs.omarchy.org` a 26-sep-2026 y **caducan**: reverificar antes de usarlas como verdad.

---

## 1. Resumen ejecutivo

**Veredicto: VIABLE, y bastante menos difícil de lo que el nombre «port» sugiere.** La mayor parte del trabajo que se temía —Hyprland recompilado, el shell Quickshell, todo el stack de dependencias— **ya está empaquetado para aarch64** en tres sitios distintos, y uno de ellos es un precedente exacto en una tablet ARM.

Los cuatro hechos que deciden el resultado:

1. **La config Lua no es de Omarchy: es de Hyprland.** Hyprland 0.55 (mayo 2026) deprecó su lenguaje propio `hyprlang` y pasó a **Lua nativo**; 0.56 lo endurece (elimina `hyprctl keyword` en favor de `hyprctl eval`). Omarchy 4 simplemente **escribe sus configs en esa Lua**. Wiki: *«Since Hyprland 0.55, hyprlang is deprecated in favor of lua»* (<https://wiki.hypr.land/Configuring/Basics/Monitors/>). Es decir: **no hay capa propietaria de Omarchy que portar** — hay una API upstream estable y documentada.
2. **Hyprland y Quickshell YA están en Arch Linux ARM (`extra`, aarch64).** `hyprland 0.56.2-3` (<https://archlinuxarm.org/packages/aarch64/hyprland>) y `quickshell 0.3.1-1` (<https://archlinuxarm.org/packages/aarch64/quickshell>). **No hay que compilar ninguno de los dos.**
3. **El propio repo de paquetes de Omarchy ya sirve aarch64.** `https://pkgs.omarchy.org/edge/aarch64/omarchy.db` → **200**, con **`omarchy-4.0.4-1-aarch64`**, `omarchy-settings-4.0.4-2-aarch64` y ~148 paquetes (verificado por descarga y `zstd -dc | tar t`, §3). El bug #8645 de Omarchy («pkgs.omarchy.org has no aarch64 tree», 27-ago-2026) **está resuelto**.
4. **Existe el precedente exacto.** Fydetab Duo (RK3588S, Mali-G610, **aarch64**) corre **Hyprland 0.56 + el shell Quickshell de Omarchy** de forma nativa, mantenido por el equipo de FydeOS, con los paquetes Omarchy recompilados a aarch64 en su repo rolling (<https://community.fydeos.io/t/topic/43275>, <https://wiki.fydetabduo.com/Available-OS/omarchy>). Y en un Pixel 3a el shell Quickshell entero renderiza con freedreno GLES 3.2 (<https://github.com/SimonSchubert/moarchy>).

**La dificultad no está en el software gráfico. Está en tres cosas, por orden de riesgo:**

| Riesgo | Por qué es el problema real | ¿Bloquea? |
|---|---|---|
| **Contexto GLES 3.x en freedreno con el kernel propio** | Hyprland **aborta sin GLES 3.2 o 3.0** (`RASSERT(false, "EGL: failed to create a context with either GLES3.2 or 3.0")`, `src/render/OpenGL.cpp:228`). En freedreno eso exige que el msm/adreno del kernel palawan exponga la GPU y que Mesa cargue `freedreno_dri.so`. El Adreno 732 es A7xx y **sí** da GLES 3.2 en freedreno, pero solo si el kernel lo declara bien. | **Sí, es el gate duro.** |
| **Rotación + táctil de tablet** | Hyprland **no trae** rotación automática ni transform de táctil coherente. Hay issues abiertos/crónicos: `input:tablet:transform` «se setea pero no hace nada» (<https://github.com/hyprwm/Hyprland/discussions/11944>), transform de tableta no aplicado (<https://github.com/hyprwm/Hyprland/issues/4856>), y **las gestures nuevas (0.55+) son solo de trackpad, no de pantalla táctil** (<https://github.com/hyprwm/Hyprland/discussions/12041>). Hay que resolverlo a mano en Lua (ver §5.4, y en detalle el informe D). | **Sí, pero es resoluble** (hay solución *upstream-idiomática*: <https://github.com/mechanicsunlocked/gimbal>). |
| **Sin UEFI/Limine → sin snapshots de Omarchy** | Omarchy asume Btrfs+Snapper+Limine para rollback; el port de Fydetab lo declara fuera de alcance («needs the Limine stack the tablet can't run yet», <https://wiki.fydetabduo.com/Available-OS/omarchy>). La uke arranca por `boot.img` Android. | **No bloquea**, pero hay que asumirlo y no depender del rollback. |

**Lo que NO es problema** (contra la intuición, y contra la nota vieja de la skill sobre «Mali-400 tops out at GLES 2.0»):

- **No hay que compilar Hyprland.** El de ALARM es 0.56.2-3, exactamente la serie que Omarchy 4 necesita.
- **No hay que compilar Quickshell.** Está en `extra/aarch64`.
- **`omarchy` y `omarchy-settings` existen como binarios aarch64** en `[omarchy]`.
- **El consumo de repo AUR x86-only del menú Install no impide arrancar**: son apps (Spotify, Cursor…), no el escritorio. El bug #8645 lo documenta como 9 entradas del menú + 5 más de PKGBUILD con `aarch64` pero sin repo (<https://github.com/omacom/omarchy/issues/8645>).

**Coste estimado**: el software gráfico se resuelve con `pacman` (días). La rotación/táctil y el pulido de una GPU modesta es lo que consume tiempo (semanas de iteración, no de compilación).

---

## 2. La verdad sobre la config Lua: **es Hyprland nativo, no una capa de Omarchy**

Esta era la pregunta crítica y la respuesta es tajante: **Lua es de Hyprland**. Omarchy es un *consumidor* de esa API.

### 2.1 Evidencia upstream (Hyprland)

| Hecho | Evidencia |
|---|---|
| Hyprland 0.55 hizo Lua el formato oficial y **deprecó `hyprlang`** | Wiki Hyprland, nota literal al pie: *«Looking for the old hyprlang syntax? Check the 0.54 wiki pages. Since Hyprland 0.55, hyprlang is deprecated in favor of lua.»* — <https://wiki.hypr.land/Configuring/Basics/Monitors/> |
| La versión **mínima es 0.55**; la API está documentada en la wiki en vivo | El selector de versión de la wiki tiene 0.54 con hyprlang y «Latest git» con Lua. <https://wiki.hypr.land/version-selector/> |
| La ruta preferida es `~/.config/hypr/hyprland.lua` | *«The config is located in `$XDG_CONFIG_HOME/hypr/hyprland.lua`. In most cases, that maps to `~/.config/hypr/hyprland.lua`.»* — <https://reasoncore.dev/post/hyprland-055-switches-configuration-to-lua> |
| El **ejemplo oficial** del repo es Lua | `example/hyprland.lua` en la rama v0.55+, con `hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })` y autostart vía `hl.on("hyprland.start", function() ... end)`. <https://github.com/hyprwm/Hyprland/blob/v0.55.2-b/example/hyprland.lua> |
| `hyprlang` sigue funcionando «unos releases», pero está en cuenta atrás | <https://sonto.tech/articles/hyprland-055-kills-hyprlang-moves-configs-to-lua> («Existing hyprlang configs will still load for a few releases») |
| **0.56 elimina `hyprctl keyword` para parsers no-legacy** | `hyprctl keyword monitor HDMI-A-1,disable` → `keyword can't work with non-legacy parsers. Use eval.` — reportado y verificado en <https://github.com/basecamp/omarchy/issues/6968> |

### 2.2 Qué trae exactamente la API Lua (y qué usa Omarchy)

**La API tiene dos namespaces**, y la distinción importa:

- **`hl.*`** — el compositor: `hl.monitor`, `hl.config`, `hl.bind`, `hl.device`, `hl.window_rule`, `hl.workspace_rule`, `hl.layer_rule`, `hl.exec_cmd`, `hl.dispatch`, `hl.timer`, y *getters* (`hl.get_active_window()`, `hl.get_monitors()`, `hl.get_config()`, `hl.is_key_down()`…). Referencia completa: <https://wiki.hypr.land/configuring/core/advanced-configuration/lua-utilities/> y <https://github.com/hyprwm/Hyprland/blob/v0.55.2-b/example/hyprland.lua>.
- **`o.*`** — **capa de conveniencia de Omarchy**, NO de Hyprland. Es el azúcar que Omarchy pone encima para sus binds: `o.bind("SUPER + SHIFT + W", "Omawrite", { launch = "omawrite" })` (<https://github.com/omacom/omarchy/pull/6231>). El release v4.0.0 lo describe literalmente como *«Convert the Hyprland configuration to Lua: bindings, monitors, and toggles are now expressive Lua (`o.bind(...)`»* (<https://github.com/omacom/omarchy/releases>, v4.0.0).

**Conclusión precisa, porque la pregunta era crítica:** si alguien ve `hl.monitor` en un wiki oficial, es **Hyprland**. Si ve `o.bind`, es **Omarchy**. Omarchy **no** parchea Hyprland para añadir Lua; escribe ficheros `.lua` que el parser de Hyprland ejecuta, usando su propio helper `o.*` cargado desde `bootstrap.lua` (que además deja `package.path` con `~/.config/?.lua`, según <https://github.com/mechanicsunlocked/gimbal/blob/master/ARCHITECTURE.md>).

### 2.3 Detalles de la API que tocan directamente a la tablet

**Monitores** (`hl.monitor`) — el campo `transform` es **exactamente lo que necesita la rotación**:

```lua
-- API real, campos documentados en https://wiki.hypr.land/configuring/core/monitors/
hl.monitor({
  output   = "DSI-1",        -- o desc:<prefijo de descripción>
  mode     = "preferred",    -- preferred | highrr | highres | "2136x3200@144"
  position = "auto",
  scale    = 1,              -- "auto" usa el PPI del panel
  transform = 0,             -- 0–7 (1=90°, 2=180°, 3=270°, 4–7 = versiones espejadas)
  disabled = false,
  vrr = 0,
  reserved_area = { top = 10, bottom = 10, left = 0, right = 0 },
})
```

Tabla completa de campos (bitdepth, cm, sdr_eotf, supports_hdr, luminance…) en <https://wiki.hypr.land/configuring/core/monitors/> y en la referencia no-oficial pero muy útil <https://alejandrominaya.github.io/hyprland-lua-docs/>.

**Dispositivos por nombre** (`hl.device`) — la vía para el táctil:

```lua
-- https://wiki.hypr.land/configuring/core/devices/
hl.device({ name = "my-epic-keyboard", sensitivity = -0.5 })
-- Para tablets: "puedes usar el ajuste output para unirlos a un monitor".
-- Nombre obtenido con: hyprctl devices
```

La wiki dice explícitamente: *«You can also use the `output` setting for tablets to bind them to outputs»* y *«Remember to use the name of the Tablet and not Tablet Pad or Tablet Tool»* (<https://wiki.hypr.land/configuring/core/devices/>). Esto es la pieza que permite atar el digitizador a la rotación.

**Runtime con `eval`** — para scripts y paneles (lo que Omarchy hizo mal en #6968 y arregló en PR #7036):

```bash
hyprctl eval 'hl.monitor({ output = "HDMI-A-1", disabled = true })'
hyprctl dispatch 'hl.dsp.window.set_prop({prop="border_size", value="0", window="address:0x..."})'
```
Fuente: <https://github.com/basecamp/omarchy/issues/6968> y <https://git.jeena.net/jeena/hypr-dotfiles/commit/496fd6fc67e67f804d7be784c486c736e8580133> («Hyprland 0.56 removed the string form of `hyprctl dispatch` and `hyprctl keyword` entirely»).

**Config modular con `require()`** — importante para el port, porque aísla fallos:

```lua
require("hypr.gimbal")   -- patrón recomendado por la wiki y por Omarchy (bootstrap.lua pone ~/.config/?.lua en package.path)
```
<https://reasoncore.dev/post/hyprland-055-switches-configuration-to-lua> (patrón `require()` con aislamiento de errores) y <https://github.com/mechanicsunlocked/gimbal/blob/master/ARCHITECTURE.md>.

### 2.4 Trampa de versión que sí afecta a este proyecto

`quickshell` **está enlazado contra la ABI de Qt6**, y hay un fallo real en producción que lo demuestra: Omarchy 4.0.1 instaló un quickshell compilado contra **Qt 6.11.2** en sistemas con Qt **6.11.1** → `symbol lookup error` + exit 127, shell en bucle de relanzado, «cursor on black» (<https://github.com/omacom/omarchy/issues/8438>). En Arch ARM, `qt6-declarative 6.11.2-2` y `qt6-wayland 6.11.2-1` van alineados con el `quickshell 0.3.1-1`, así que **en ALARM el riesgo es menor que en x86** — pero la lección es: **no mezclar Qt a mano**; dejar que pacman resuelva el set completo.

Y una nota de compatibilidad del propio proyecto Quickshell: *«Wayland integration relies on features that are not part of the public Qt API… Updating quickshell's dependencies without ensuring that the current Qt version is supported WILL result in quickshell failing to build or misbehaving at runtime»* (<https://git.outfoxxed.me/quickshell/quickshell/src/branch/master/BUILD.md>).

---

## 3. Quickshell en aarch64: **empaquetado, no hay que compilar**

### 3.1 Disponibilidad

| Canal | Paquete | Versión | Arquitectura | Fuente |
|---|---|---|---|---|
| **Arch Linux ARM `extra`** | `quickshell` | **0.3.1-1** (build 21-ago-2026) | aarch64 | <https://archlinuxarm.org/packages/aarch64/quickshell> |
| Arch Linux ARM `extra` (versión previa en caché) | `quickshell` | `0.3.0-2` (build 05-jun-2026) | aarch64 | misma URL, snapshot histórico |
| Arch Linux x86_64 `extra` | `quickshell` | `0.3.1-1` | x86_64 | <https://security.archlinux.org/package/quickshell> |
| AUR | `quickshell` / `quickshell-git` | 0.2.0 / `0.3.0.r0.g59e9c47` | build local | <https://aur.archlinux.org/packages/quickshell> · <https://aur.archlinux.org/packages/quickshell-git> |
| **`[omarchy]` (repo de Omarchy)** | `quickshell-git` | `0.3.0.r20.g28771c7-3` | **aarch64** (y x86_64) | `https://pkgs.omarchy.org/edge/aarch64/omarchy.db` (descargado y verificado) |

**Conclusión operativa:** en la uke, `sudo pacman -S quickshell` desde ALARM `extra` **funciona y da la 0.3.1**. No hace falta `yay`, ni AUR, ni compilar.

### 3.2 Qué necesita (dependencias reales de build)

De `BUILD.md` oficial (<https://git.outfoxxed.me/quickshell/quickshell/src/branch/master/BUILD.md>):

**Base (siempre):**
- `cmake`, `qt6base`, `qt6declarative`, `libdrm`
- build-time: `qtshadertools`, `spirv-tools`, `pkg-config`
- estática: `cli11`
- **cabeceras privadas** de `qt6declarative` (y `qt6wayland` si Qt < 6.10)
- recomendadas: `qt6svg` (sin ella no hay SVG ni iconos del sistema), **Qt ≥ 6.6**

**Features (todas ON por defecto) y sus dependencias** — en negrita las que usa el shell de Omarchy:

| Feature | Flag para desactivar | Deps |
|---|---|---|
| Crash handler | `-DCRASH_HANDLER=OFF` | `cpptrace` (o `-DVENDOR_CPPTRACE=ON` + `libunwind`, `libdwarf`) |
| Jemalloc | `-DUSE_JEMALLOC=OFF` | `jemalloc` — **dejarlo ON**: enmascara la fragmentación del motor QML y evita la «fuga de memoria» percibida |
| Unix sockets (IPC) | `-DSOCKETS=OFF` | ninguna |
| Wayland | `-DWAYLAND=OFF` | `qt6wayland` (Qt<6.10), `wayland`, `wayland-scanner` (build), `wayland-protocols` (estática) |
| ↳ **wlr-layer-shell** | `-DWAYLAND_WLR_LAYERSHELL=OFF` | ninguna — **la necesita la barra** |
| ↳ session-lock | `-DWAYLAND_SESSION_LOCK=OFF` | ninguna — **el lock screen de Omarchy** |
| ↳ foreign-toplevel / screencopy | `-DWAYLAND_TOPLEVEL_MANAGEMENT=OFF` / `-DSCREENCOPY=OFF` | ninguna / `libgbm`+`vulkan-headers` (build) |
| X11 (paneles) | `-DX11=OFF` | `libxcb` |
| **Pipewire** | `-DSERVICE_PIPEWIRE=OFF` | `libpipewire` — **volumen del shell** |
| StatusNotifier / MPRIS | `-DSERVICE_STATUS_NOTIFIER=OFF` / `-DSERVICE_MPRIS=OFF` | `qt6dbus` |
| **PAM** | `-DSERVICE_PAM=OFF` | `pam` — **lock screen** |
| **Polkit** | `-DSERVICE_POLKIT=OFF` | `polkit`, `glib` — **el agente polkit del shell** |
| Hyprland | `-DHYPRLAND=OFF` | ninguna — **esencial aquí** (subfeatures: global shortcuts, focus grab) |
| i3/Sway IPC | `-DI3=OFF` | ninguna (el plan B de compositor) |

El espejo de runtime lo confirma: **`qt6-wayland` es *depend* declarada de `quickshell`** en Arch — cosa que `quickshell-git` **no** declaraba, de ahí otro fallo real documentado en #8438.

### 3.3 Si hubiera que compilar (comando exacto, por si acaso)

**No es necesario en ALARM**, pero se documenta porque el informe B/E puede acabar necesitando un pin propio (p. ej. si ALARM va por delante o detrás del Qt que necesita Omarchy):

```bash
# Prerrequisitos (Arch ARM / aarch64) — todos existen en ALARM 'extra':
#   cmake qt6-base qt6-declarative qt6-wayland qt6-shadertools qt6-svg qt6-imageformats \
#   libdrm spirv-tools pkgconf cli11 jemalloc cpptrace wayland wayland-protocols libpipewire \
#   polkit glib2 pam libgbm vulkan-headers libxcb
cmake -GNinja -B build -DCMAKE_BUILD_TYPE=Release \
  -DDISTRIBUTOR="ALARM (quickshell)" \
  -DINSTALL_QML_PREFIX="lib/qt6/qml"
cmake --build build
sudo cmake --install build
```
Flags tomados de `BUILD.md` (<https://git.outfoxxed.me/quickshell/quickshell/src/branch/master/BUILD.md>). Nota del propio autor: **clang compila mucho más rápido que gcc** — en la uke (8 núcleos, 12 GB) eso vale horas. `-DINSTALL_QML_PREFIX` «usualmente es lo que quieres».

### 3.4 Estado de Quickshell en aarch64: ¿hay issues?

- **NixOS aarch64**: hubo un fallo real, `quickshell: fails to launch on aarch64-linux` — **cerrado** el 7-jul-2025 (<https://github.com/NixOS/nixpkgs/issues/420685>). El peticionario lo quería justo para «una Pi como handheld con shell propio».
- **Arch Linux ARM**: paquete en `extra` desde al menos jun-2026, sin issues abiertos encontrados.
- **Evidencia de que funciona en ARM real** (lo más fuerte): el Pixel 3a con **Adreno 615 y GLES 3.2 en freedreno** corre Omarchy 4.x completo con Quickshell — *«the whole quickshell shell — bar, launcher, notifications, OSD»* (<https://github.com/SimonSchubert/moarchy>) — y el `shell.qml` real de Omarchy v4.0.2 arrancó allí alcanzando `INFO: Configuration Loaded` y manteniéndose vivo con RSS 197 MB (<https://github.com/SimonSchubert/moarchy/blob/main/docs/omarchy-4x-feasibility.md>).
- **[NO VERIFICADO]** No he encontrado ningún issue específico de Quickshell sobre **Adreno a7xx**. La búsqueda de «quickshell aarch64 issue» devuelve sobre todo el de NixOS y repos de terceros.

---

## 4. Dependencias del shell de Omarchy en aarch64 — tabla de componentes

El release v4.0.0 «Quattro» describe qué sustituyó: *«Waybar, Walker, Mako, SwayOSD, hyprlock, hypridle, swaybg, and polkit-gnome are all gone, replaced by one coherent, fully-themed, IPC-scriptable shell»* (<https://github.com/basecamp/omarchy/releases>). El shell es **un solo proceso Quickshell de larga vida** con `shell.qml` y plugins (<https://github.com/omacom/omarchy/tree/quattro/shell>).

### 4.1 Componentes del shell y de Hyprland

Estado consultado en `archlinuxarm.org/packages/aarch64/<pkg>` el 26-sep-2026. ✅ = existe, ❌ = no existe, ⚙️ = solo AUR/Omarchy.

| Componente del shell | ¿Existe en Arch ARM / AUR? | Cómo se obtiene | Dificultad | Fuente |
|---|---|---|---|---|
| **`quickshell`** (el shell entero) | ✅ `0.3.1-1` en `extra/aarch64` | `pacman -S quickshell` | **Trivial** | <https://archlinuxarm.org/packages/aarch64/quickshell> |
| **`hyprland`** (compositor) | ✅ `0.56.2-3` en `extra/aarch64` (split `hyprpm`) | `pacman -S hyprland` | **Trivial** | <https://archlinuxarm.org/packages/aarch64/hyprland> |
| **`omarchy`** (scripts+shell en `/usr/share/omarchy`) | ✅ **`omarchy-4.0.4-1-aarch64`** en `[omarchy]` edge | repo `pkgs.omarchy.org/edge/aarch64` (**200** verificado) | **Baja** (ver §4.3) | descarga y `zstd -dc \| tar t` del `omarchy.db` aarch64 |
| **`omarchy-settings`** | ✅ `omarchy-settings-4.0.4-2-aarch64` en `[omarchy]` edge | idem | Baja | idem |
| **Agente polkit** | ✅ integrado en el shell (`SERVICE_POLKIT`: `polkit`, `glib`); `hyprpolkitagent 0.2.0-1` **también** existe en ALARM | `pacman -S hyprpolkitagent` (o el del shell) | Trivial | <https://archlinuxarm.org/packages/aarch64/hyprpolkitagent> · BUILD.md |
| **Idle / screensaver** | ✅ integrado en el shell (idle+lock del shell); `hypridle 0.1.8-2` y `hyprlock 0.9.6-3` siguen en ALARM como alternativa | `pacman -S hypridle hyprlock` | Trivial | <https://archlinuxarm.org/packages/aarch64/hypridle> · <https://archlinuxarm.org/packages/aarch64/hyprlock> |
| **Portapapeles unificado** | ✅ en el shell (QML + `wl-clipboard 1:2.3.0-1`) | `pacman -S wl-clipboard` | Trivial | <https://archlinuxarm.org/packages/aarch64/wl-clipboard> |
| **OSD (brillo/volumen)** | ✅ en el shell (`SERVICE_PIPEWIRE`, `UPower`) | `pacman -S pipewire libpipewire upower` | Trivial | BUILD.md · <https://archlinuxarm.org/packages/aarch64/upower> |
| **Notificaciones** | ✅ en el shell; `mako 1.11.0-1` existe en ALARM si se quiere el viejo | `pacman -S mako` (opcional) | Trivial | <https://archlinuxarm.org/packages/aarch64/mako> |
| **Lock screen** | ✅ en el shell (`WAYLAND_SESSION_LOCK` + `SERVICE_PAM`) | incl. en quickshell | Trivial | BUILD.md |
| **Wallpaper / fondos animados** | ✅ `[omarchy]` trae **`owe-0.2.6-1`** + `owe-lockfeed` **aarch64** | repo `[omarchy]` | Baja | `omarchy.db` aarch64 (verificado) |
| **Menú Omarchy (JSONC en el shell)** | ✅ dentro de `omarchy` | — | — | <https://github.com/omacom/omarchy/pull/6231> |
| **Barra** | ✅ dentro del shell (`omarchy.bar`) | — | — | <https://github.com/omacom/omarchy/tree/quattro/shell> |

### 4.2 Componentes Hyprland que Omarchy usa y siguen vivos

| Componente | ¿Existe en Arch ARM? | Cómo | Fuente |
|---|---|---|---|
| `hyprland-guiutils` | ✅ `0.2.2-4` | `pacman` | <https://archlinuxarm.org/packages/aarch64/hyprland-guiutils> |
| `hyprpicker` | ✅ `0.4.7-4` | `pacman` | <https://archlinuxarm.org/packages/aarch64/hyprpicker> |
| `hyprsunset` | ✅ `0.4.0-3` | `pacman` | <https://archlinuxarm.org/packages/aarch64/hyprsunset> |
| `hyprpaper` | ✅ `0.8.4-9` | `pacman` | <https://archlinuxarm.org/packages/aarch64/hyprpaper> |
| `hyprtoolkit` | ✅ `0.6.0-1` | `pacman` | <https://archlinuxarm.org/packages/aarch64/hyprtoolkit> |
| `hyprland-qt-support` | ✅ `0.1.0-14` | `pacman` | <https://archlinuxarm.org/packages/aarch64/hyprland-qt-support> |
| `hyprcursor` / `hyprutils` / `hyprlang` / `aquamarine` | ✅ los cuatro | `pacman` | `archlinuxarm.org/packages/aarch64/{hyprcursor,hyprutils,hyprlang,aquamarine}` |
| `xdg-desktop-portal-hyprland` | ✅ `1.4.1-2` | `pacman` | <https://archlinuxarm.org/packages/aarch64/xdg-desktop-portal-hyprland> |
| `hyprqt6engine` | ❌ **404 en ALARM** | — | consulta directa → 404. **[NO VERIFICADO]** si Omarchy 4 lo requiere; no aparece en `omarchy-base.packages` |
| `uwsm` (session manager de Omarchy) | ✅ `0.27.0-1` | `pacman` | <https://archlinuxarm.org/packages/aarch64/uwsm> |

### 4.3 Helpers CLI que el shell invoca

Todos verificados uno a uno en `archlinuxarm.org/packages/aarch64/`:

| Helper | Versión ALARM | Cómo | Fuente |
|---|---|---|---|
| `pamixer` | ✅ 1.6-3 | pacman | <https://archlinuxarm.org/packages/aarch64/pamixer> |
| `brightnessctl` | ✅ 0.5.1-3 | pacman | <https://archlinuxarm.org/packages/aarch64/brightnessctl> |
| `bluetoothctl` (`bluez-utils`) | ✅ 5.87-2 | pacman | <https://archlinuxarm.org/packages/aarch64/bluez-utils> |
| `bluez-tools` | ✅ 0.2.0-6 | pacman | <https://archlinuxarm.org/packages/aarch64/bluez-tools> |
| `nmcli` (`networkmanager`) | ✅ 1.58.1-1 | pacman | <https://archlinuxarm.org/packages/aarch64/networkmanager> |
| `jq` | ✅ 1.8.2-1 | pacman | <https://archlinuxarm.org/packages/aarch64/jq> |
| `curl` | ✅ 8.22.0-1 | pacman | <https://archlinuxarm.org/packages/aarch64/curl> |
| `wl-clipboard` | ✅ 1:2.3.0-1 | pacman | arriba |
| `wireplumber` | ✅ | pacman | `omarchy` lo lista como dep; existe en ALARM |
| `playerctl`, `pavucontrol` | ✅ ambos | pacman | `archlinuxarm.org/packages/aarch64/{playerctl,pavucontrol}` |
| `grim`, `slurp`, `satty` | ✅ los tres | pacman | `archlinuxarm.org/packages/aarch64/{grim,slurp,satty}` |
| `wtype`, `wl-clip-persist`, `cliphist` | ✅ los tres | pacman | `archlinuxarm.org` |
| `sddm` (display manager) | ✅ 0.21.0-7 | pacman | `omarchy` lo lista como dep |
| `lua51`, `luajit`, `lua` | ✅ 5.1.5-13, 2.1, **lua 5.5.1-1** | pacman | `omarchy-base.packages` trae `lua51`+`luarocks` |
| `tesseract` (OCR de capturas) | ❌ **404 en ALARM** | — | consulta directa → 404. Confirmado independientemente: *«OCR capture (`tesseract` has no aarch64 build)»* — <https://github.com/SimonSchubert/moarchy> |

**Lo que NO existe en aarch64 y hay que asumir como pérdida** (todas del listado del port de moarchy, <https://github.com/SimonSchubert/moarchy>):
- **`tesseract`** (OCR de capturas) — sin build aarch64.
- **`voxtype`** (dictado) — x86-only (el bug #8645 lo confirma como `voxtype-bin`).
- Apps propietarias del menú Install: `1password`, `spotify`, `obsidian`, `typora`, `cursor-bin`, `lmstudio-bin`, `dropbox`, `symfony-cli`, `microsoft-edge-stable-bin`, `ollama` (AUR `arch=('x86_64')`)… lista completa y razonada en <https://github.com/omacom/omarchy/issues/8645>.

**Ninguna de esas pérdidas impide que el escritorio arranque.** Son apps, no el shell.

### 4.4 El repo `[omarchy]` para aarch64: verificado, y con una corrección importante

El bug #8645 (27-ago-2026) documentó que `pkgs.omarchy.org/stable/aarch64/omarchy.db` daba **404**. **Hoy da 200.** Lo comprobé descargando el índice y listando su contenido:

```
$ curl -o /dev/null -w '%{http_code}' https://pkgs.omarchy.org/stable/aarch64/omarchy.db   -> 200
$ curl -o /dev/null -w '%{http_code}' https://pkgs.omarchy.org/edge/aarch64/omarchy.db     -> 200
$ curl -s https://pkgs.omarchy.org/edge/aarch64/omarchy.db | zstd -dc | tar t | wc -l      -> 148 entradas
```

Entre ellas, las que importan:
```
omarchy-4.0.4-1                        (ARCH aarch64, URL upstream github.com/basecamp/omarchy)
omarchy-settings-4.0.4-2               (aarch64)
hyprland-0.56.2-3                      (aarch64, dentro de [omarchy] también)
quickshell-git-0.3.0.r20.g28771c7-3    (aarch64)
hyprland-guiutils / hyprpm / hyprtoolkit / hyprshade / wayfreeze
omarchy-nvim / omarchy-zsh / omarchy-fish / omarchy-emacs / omarchy-walker
owe-0.2.6-1 + owe-lockfeed-0.2.6-1
tensaku / yay / walker / elephant-*
```

El `desc` de `omarchy-4.0.4-1-aarch64` lo dice sin ambigüedad:
```
%NAME% omarchy
%ARCH% aarch64
%FILENAME% omarchy-4.0.4-1-aarch64.pkg.tar.zst
%DEPENDS% omarchy-keyring omarchy-settings=4.0.4 hyprland quickshell uwsm sddm
          xdg-desktop-portal-hyprland wireplumber pipewire gnome-keyring gum jq git perl
          fakeroot pacman-contrib ttf-jetbrains-mono-nerd-basic iwd networkmanager
%URL%  https://github.com/basecamp/omarchy
```

Es decir: **`omarchy` aarch64 declara `quickshell` y `hyprland` como dependencias**, y los dos están en ALARM `extra`. La cadena cierra sin compilar nada. Verifiqué además que **`omarchy-keyring`** (primera dependencia, sin la cual no vale la firma del repo) también está en el árbol aarch64.

**⚠️ Matiz importante que cambia el plan de instalación: en aarch64 el par `omarchy`/`omarchy-settings` solo está publicado en el canal `edge`, NO en `stable`.** Comprobado contra los dos índices:

```
# aarch64: stable NO trae el núcleo de Omarchy (solo periféricos)
$ zstd -dc <stable/aarch64/omarchy.db> | tar t | grep -v '/desc$'
aether, claude-code, claude-desktop, cursor-bin, elsewhen, flea, learn-omarchy,
mise-bin, omarchy-billboard-generator, owe, owe-lockfeed, ...   <- NO hay "omarchy" ni "omarchy-settings"

# aarch64: edge SÍ
$ zstd -dc <edge/aarch64/omarchy.db> | tar t | grep -v '/desc$' | grep -E '^omarchy-4|^omarchy-settings-4'
omarchy-4.0.4-1/
omarchy-settings-4.0.4-2/

# x86_64 (control): stable SÍ los trae -> la asimetría es de arquitectura, no de release
omarchy-4.0.4-1/        omarchy-settings-4.0.4-1/
```

**Consecuencia operativa:** en la uke hay que apuntar `[omarchy]` a **`edge`** (`https://pkgs.omarchy.org/edge/aarch64`), no a `stable` — o los dos paquetes que importan no aparecerán. Es coherente con cómo lo hace el fork de Mac (*«Mac pacman.conf sets [omarchy] to Usage = Sync: the db is refreshed, and only three explicit Hyprland targets…»*, <https://github.com/omarchy-mac/omarchy-pkgs-aarch64>) y con que Omarchy publique las versiones `edge` de su propio par con `release_ring: fast` para todas las arquitecturas (<https://github.com/omacom/omarchy-pkgs>). **[NO VERIFICADO]** si esto es transitorio (el núcleo aarch64 recién promovido) o intencionado; reverificar antes de fijar el mirrorlist.

El propio repo `omarchy-pkgs` confirma que aarch64 es oficial: *«**Multi-Architecture**: Supports both x86_64 and aarch64 (ARM64)»*, con `PUBLISHED_ARCHES="${OMARCHY_ARCHES:-x86_64}"` y builds emulados por QEMU para arquitecturas foráneas (<https://github.com/omacom/omarchy-pkgs>).

**[NO VERIFICADO]** No he podido comprobar si el `[omarchy]` aarch64 cubre **todas** las dependencias del install de Omarchy (el `omarchy-base.packages` tiene ~150 nombres) ni si `omarchy update` funciona end-to-end desde un ALARM limpio. Lo que sí está verificado es que el par crucial (`omarchy`, `omarchy-settings`) y el shell (`quickshell`) existen como binarios aarch64.

### 4.5 Ojo: `omarchy` aarch64 no implica que *todo* Omarchy sea aarch64

El bug #8645 sigue siendo verdad en su diagnóstico de fondo: **`bin/omarchy-pkg-add` es pacman-only y nada en el árbol comprueba la arquitectura** — *«`grep -rIn 'x86_64\|aarch64\|uname -m\|arm64\|HOSTTYPE\|MACHTYPE' bin default install config etc shell` returns no hits»* (<https://github.com/omacom/omarchy/issues/8645>). Hay PRs en curso para arreglarlo (`#8039` guardas de install, `#8316` fallback source-build con `omarchy-hw-x86-64-v3`). Consecuencia práctica para la uke: **el menú Install ofrecerá entradas que fallarán con `error: target not found`** en una ventana flotante que se cierra sola. No rompe el escritorio, pero sí sorprende. Se mitiga no usando el menú Install para apps x86-only.

---

## 5. Rendimiento en Adreno 732 (freedreno) y ajustes concretos

### 5.1 Qué es el Adreno 732 y cómo lo ve Linux

- Specs: **Adreno 732 @ 950 MHz**, 768 shaders, LPDDR5X ~67,2 GB/s, **~1,46 TFLOPS FP32**, en el Snapdragon 7+ Gen 3 (**SM7675**) de la Xiaomi Pad 7 (12 GB, panel 2136×3200 @144 Hz 3:2). Fuentes: <https://hmc-tech.com/gpus/qualcomm-adreno-732> y <https://www.devicespecifications.com/en/model-battery/756361e0>.
- **Es A7xx.** En Mesa es la familia Adreno Gen 7, con soporte en freedreno desde Mesa 24.3 para la serie 700 inicial (<https://www.phoronix.com/news/Mesa-24.3-Freedreno-A7xx>) y evolución continua.
- **El nivel GLES que da es lo que decide si Hyprland arranca.** Freedreno implementa **hasta GLES 3.2 y GL 4.5** (<https://docs.mesa3d.org/drivers/freedreno.html>). Hyprland exige **GLES 3.2 o 3.0** y aborta si no:

```c
// src/render/OpenGL.cpp:215,228 (rama main, verificado con curl)
LOG(Log::WARN, "EGL: Failed to create a context with GLES3.2, retrying 3.0");
RASSERT(false, "EGL: failed to create a context with either GLES3.2 or 3.0");
```
Fuente: <https://raw.githubusercontent.com/hyprwm/Hyprland/main/src/render/OpenGL.cpp>. **El Adreno 732 cumple de sobra** (GLES 3.2). El riesgo no es el hardware, es **que el kernel palawan exponga la GPU a Mesa** (que `/dev/dri` exista y `eglinfo` reporte `renderer: Freedreno` y no `llvmpipe`).

**Prueba concreta que hay que hacer en la uke antes de nada:**
```bash
ls /dev/dri                                   # debe existir renderD128
eglinfo -B 2>/dev/null | grep -A2 "OpenGL ES profile"
# ESPERADO: vendor "freedreno", renderer con el nombre del Adreno, version "OpenGL ES 3.2 ..."
# SI SALE llvmpipe: la GPU no está; Hyprland irá por software (o no irá).
```
Este es **el mismo diagnóstico** que tumbó a otro usuario en un Snapdragon X Elite con ALARM: `renderer: llvmpipe (LLVM 19.1.7…)` en ALARM frente a `renderer: Adreno X1-85` en Ubuntu — el problema era el kernel/DTB, no Mesa ni Hyprland (<https://www.reddit.com/r/linuxquestions/comments/1l8z3nu/opengl_on_snapdragon_x_elite/>).

### 5.2 Soporte A7xx en Mesa: estado y matiz sobre el a732 concreto

- Upstream Mesa (`main`) tiene el **A735** (`GPUId(chip_id=0x43030B00, name="FD735")`) como `CHIP.A7XX` con **gen2** y `enable_tp_ubwc_flag_hint = True`, 3 CCU, tile 96×32, GMEM/VSC completos (<https://gitlab.freedesktop.org/mesa/mesa/-/raw/main/src/freedreno/common/freedreno_devices.py>).
- **Matiz importante y accionable:** el **Adreno 732 no tiene su propio ID upstream en Mesa `main`** — lo verifiqué con `grep`. La entrada «a732 como a735 binneado» (`0xffff43030b00` any-speedbin + `0x43030a00` «speculative a732 own id») **solo existe en un fork de terceros** (`lfdevs/mesa-for-android-container`, PR #93 «freedreno/common: add unofficial support for Adreno 732», mergeado 28-jul-2026: <https://github.com/lfdevs/mesa-for-android-container/pull/93>).

  ```
  # fork lfdevs (NO upstream):
  GPUId(chip_id=0x43030B00, name="FD735")
  GPUId(chip_id=0xffff43030b00, name="FD735")  # any-speedbin fallback (covers a732 = binned a735 theory)
  GPUId(chip_id=0x43030a00, name="FD735")      # speculative a732 own id
  GPUId(chip_id=0xffff43030a00, name="FD735")  # speculative a732 any-speedbin
  ```

  **Implicación para el proyecto:** si el kernel palawan reporta un chip_id que Mesa `main` no conoce, freedreno podría **no cargar**. Dos salidas: (a) que el driver msm/adreno del kernel anuncie el chip con un id ya soportado (`0x43030B00` = a735), que es lo que hace el kernel mainline para los A7xx, o (b) llevar un parche como el del fork. **[NO VERIFICADO]** cuál de las dos ocurre con el DT/driver de la uke — es una comprobación de una línea (`cat /sys/kernel/debug/dri/*/device 2>/dev/null` o el log de `msm`), y **debe hacerse antes de dar el rendimiento por bueno**.

- Kernel: el soporte A7xx en `drm/msm/adreno` existe desde 2023 (A730 en SM8450, A740 en SM8550) — <https://lists.freedesktop.org/archives/dri-devel/2023-September/424293.html>. A8xx llegó después (<https://www.phoronix.com/news/Freedreno-Lands-Adreno-Gen-8>, <https://lists.freedesktop.org/archives/freedreno/2025-November/042251.html>).
- **Vulkan/Turnip** también existe para A6xx/A7xx (Vulkan 1.4.x en builds 2026: <https://github.com/The412Banner/Banners-Turnip/releases>), pero **Hyprland no usa Vulkan**: su renderer es GLES. Turnip importa si se quiere correr apps Vulkan (juegos), no para el escritorio.
- En Arch ARM: **`mesa 1:26.2.3-1`** y **`vulkan-freedreno 1:26.2.3-1`** (verificado en `archlinuxarm.org/packages/aarch64/mesa`). Es Mesa **26.2.3** — muy por delante del 24.3 que introdujo A7xx. **Las optimizaciones A7xx de LRZ bidireccional, LRZ feedback y fast-clear a valor arbitrario están en el driver** (<https://docs.mesa3d.org/drivers/freedreno/hw/lrz.html>), y concurrent binning se mergeó para a7xx en ago-2025 (<https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/36590>).

### 5.3 Bloques de config de rendimiento (Lua) para GPU modesta

**Realidad del panel de la uke:** 2136×3200 a 144 Hz es **muchísimo** para un Adreno 732. El coste dominante no son las apps: es **blur de superficies grandes + sombras + bordes con degradado**, todo por píxel. Palancas en orden de impacto (fuente de cada opción: <https://wiki.hypr.land/configuring/core/config-options/>, salvo donde se indique).

**Bloque 1 — Apagar los efectos caros (el mayor ahorro).** La wiki de rendimiento recomienda esto *literalmente*: *«`hl.config({ ["decoration.blur.enabled"] = false })` to disable fancy, but hungry effects»* (<https://wiki.hypr.land/configuring/extra/performance/>).

```lua
hl.config({
  decoration = {
    blur    = { enabled = false },   -- mayor ahorro de todos
    shadow  = { enabled = false },   -- segunda pasada por ventana
    rounding = 0,                    -- 0 = sin esquinas redondeadas (masking por píxel)
  },
  animations = { enabled = false },  -- o dejar 1-2 y bajar duration
})
```

**Bloque 2 — Escalado entero y refresco honesto.** La wiki: *«If you have problems with your graphics card having high usage or Hyprland feeling laggy, try setting the scaling to integer numbers such as 1 or 2»* (<https://wiki.hypr.land/configuring/extra/performance/>). Fraccionario (1.5) fuerza render a resolución mayor + downscale.

```lua
hl.monitor({ output = "DSI-1", mode = "preferred", position = "auto", scale = 1 })
hl.monitor({ output = "DSI-1", mode = "2136x3200@60" })  -- 144 Hz es inviable aquí; campo `mode` en /configuring/core/monitors/
```

**Bloque 3 — `misc`/`render` marcados en la wiki para conservar recursos.**

```lua
hl.config({
  misc = {
    disable_autoreload = true,   -- "Might save on battery"
    vfr = true,                  -- DEFAULT true: "Heavily recommended to leave enabled to conserve resources"
    render_unfocused_fps = 5,    -- FPS de ventanas sin foco (default 15; rango 1-120)
    disable_hyprland_logo = true, disable_splash_rendering = true, force_default_wallpaper = 0,
  },
  render = {
    direct_scanout = 0,          -- DEFAULT 0. En GPU débil dejarlo OFF: DS añade fragilidad con dmabufs
    new_render_scheduling = true,-- "improves FPS on underpowered devices"
    use_fp16 = 0,                -- FP16 interno: puede ahorrar ancho de banda en Adreno, pero probar
    xp_mode = false,             -- "Disables back buffer and bottom layer rendering"
  },
  general = { allow_tearing = false },
  cursor  = { no_hardware_cursors = 1, hide_on_touch = true },
})
```

> ⚠️ **Corrección a nombres que circulan:** **`render.explicit_sync` NO EXISTE** en la wiki 0.56 (verificado el listado completo de `render`), y **`misc.no_direct_scanout` tampoco** — el campo real es **`render.direct_scanout`**. `misc.vfr` **sí** existe (default `true`). Un config con los nombres inventados dará **error de parseo**. Si el informe previo los citaba, quedan corregidos aquí contra la fuente primaria. **[NO VERIFICADO]** de dónde salieron esos nombres.

**Bloque 4 — Blur barato, si se quiere conservar algo de la identidad visual de Omarchy.**

```lua
hl.config({ decoration = { blur = {
  enabled = true,
  new_optimizations = true,  -- DEFAULT true: "will massively improve performance"
  size = 3,                  -- DEFAULT 8; menor = mucho menos muestreo
  passes = 1,                -- subirlo multiplica coste
  xray = true,               -- "Will reduce overhead on floating blur significantly"
  special = false,           -- "(note: expensive)"
  popups = false,
  variant = "kawase",        -- NO usar acrylic/aurora/water/fluid_jar: "may significantly increase GPU and CPU usage"
} } })
```
La wiki sobre `variant`: *«May significantly increase GPU and CPU usage»*; sobre `passes`: *«higher blur.passes will place more strain on the GPU»*. Limitar el blur con `layer_rule`/`window_rule` a lo que importa (<https://wiki.hypr.land/configuring/core/rules/layer-rules/>).

**Bloque 5 — Cursor hardware.** `cursor.no_hardware_cursors`: `0` = usar si se puede, `1` = no usarlos, `2` = auto. freedreno ha dado problemas de cursor hardware en Wayland; si aparece parpadeo o el cursor se pierde tras rotar, **probar `1`**.

**Bloque 6 — Térmico.** La pista de la wiki (subir el mínimo de frecuencia de GPU Intel) **no aplica a freedreno** (sin ese sysfs). Equivalentes para la uke: **limitar el refresco** (bloque 2, el mayor ahorro térmico) y `misc.render_unfocused_fps = 5`. El `Adreno 732 @950 MHz` bajará por térmica en sostenido. **[NO VERIFICADO]** la ruta exacta de frecuencia: con kgsl sería `/sys/class/kgsl/kgsl-3d0/gpuclk`, con msm/devfreq `/sys/class/devfreq/*/cur_freq` — comprobar en la tablet.

### 5.4 Rotación y táctil: la solución existe y es Lua puro

Esto es rendimiento-adyacente pero es *el* problema real de una tablet, y **tiene una respuesta excelente y upstream-idiomática**:

**`gimbal`** hace detección de tablet + auto-rotación en **~200 líneas de Lua cargadas en la propia config de Hyprland**, sin daemon, sin socket, sin unidad systemd (<https://github.com/mechanicsunlocked/gimbal/blob/master/ARCHITECTURE.md>):

```lua
-- ~/.config/hypr/hyprland.lua   (Omarchy invita a esto: "Add any other personal Hyprland configuration below")
require("hypr.gimbal")
```

| Necesidad | Mecanismo Lua | Evidencia citada por gimbal |
|---|---|---|
| Entrar/salir de modo tablet | `hl.bind("switch:on\|off:gpio-keys", …, {locked=true})` | binds disparan en ambas direcciones |
| Estado inicial | ángulo de bisagra ≥ 200° desde `cros-ec-lid-angle` | los binds son edge-triggered |
| Orientación | `io.open` sobre `in_accel_{x,y,z}_raw` a 4 Hz | 82 µs medio / 291 µs peor por lectura de 3 ejes |
| **Aplicar rotación** | **`hl.monitor{transform=…}` + `hl.config{input={touchdevice,tablet}}`** | aplicado y revertido en vivo |
| Bloquear rotación | `hl.bind("SUPER + R", …)` | — |

**La pieza clave para la uke:** `hl.monitor({ transform = N })` **rota la pantalla**, y `hl.config({ input = { touchdevice = …, tablet = … } })` aplica la transformación correspondiente al **táctil y al lápiz**. Ese par es exactamente la «calibración del táctil que rota con la pantalla» que se quería del plugin `maxt.tablet-experience`. Y el precedente de Surface Pro con Omarchy 4.x lo confirma en otro dispositivo: `auto-rotate/` funciona y **detecta el táctil por capacidad (`INPUT_PROP_DIRECT`) en vez de por nombre**, y lee output/mode/position/scale de `hyprctl monitors -j` (<https://github.com/javon27/omarchy-surface-touch>).

**Advertencias importantes sobre el táctil/gestos en Hyprland:**
- `input:tablet:transform` **no funciona** (issue/discussion abierta) — hay que hacerlo por `hl.monitor{transform}` + `hl.config{input.touchdevice/tablet}`, **no** por el transform de tableta: <https://github.com/hyprwm/Hyprland/discussions/11944> y <https://github.com/hyprwm/Hyprland/issues/4856>.
- Issue crónico de calibración/transform de pantalla táctil, cerrado como *not planned*: <https://github.com/hyprwm/Hyprland/issues/8814>.
- **Las gestures de Hyprland 0.55+ son solo de trackpad**, no de pantalla táctil: <https://github.com/hyprwm/Hyprland/discussions/12041>. En una tablet los gestos hay que montarlos a mano (el port de moarchy los implementa como plugin Quickshell que captura el borde inferior como layer surface, <https://github.com/SimonSchubert/moarchy>).
- **OSK**: `wvkbd` es la vía probada (<https://github.com/jjjsullivan5196/wvkbd>), y omarchy-surface-touch trae un **parche de un bug de parpadeo/no-repetición** de wvkbd-deskintl, además de un trackpad virtual en Quickshell (<https://github.com/javon27/omarchy-surface-touch>). Esto conecta con el informe D.

**Nota de combinación con el bloque 3:** al rotar con `transform`, el coste de blur/cursor cambia (las rotaciones de 90° rompen algunas optimizaciones — la wiki avisa: `use_shader_blur_blend` tiene glitches «on rotated screens», y `render.direct_scanout` se desaconseja con ciertos contenidos). Es decir: **si la uke va rotada en vertical, apagar blur es aún más rentable.** Fuente: <https://wiki.hypr.land/configuring/core/config-options/>.

---

## 6. Precedentes ARM: qué reporta cada uno

### 6.1 Fydetab Duo — **el precedente gemelo** (tablet ARM, Hyprland 0.56 + Quickshell Omarchy)

- **Hardware:** RK3588S, Mali-G610 MP4 (panthor + Mesa), 8 GB, panel 2560×1600. <https://wiki.postmarketos.org/wiki/Fydetab_Duo_(fyde-fydetabduo)>
- **Qué corre:** *«Hyprland 0.56 + the Quickshell Omarchy shell»*, Wi-Fi/BT, GPU Mali G610 (panthor + Mesa), suspend/resume profundo con lock-on-suspend, firewall/zram/tematización/LocalSend de Omarchy, y **dicción con Voxtype recompilada a aarch64 en su propio repo** (<https://community.fydeos.io/t/topic/43275>).
- **Cómo lo resolvieron:** *«we build all the Omarchy…»* — **recompilan los paquetes Omarchy a aarch64** y sirven un **repo rolling**; `omarchy-update` se actualiza desde ahí. Lo declaran **experimental**, y **sin cifrado de disco ni rollback por snapshots btrfs** (<https://wiki.fydetabduo.com/Available-OS/omarchy>, y el anuncio en chino: <https://community.fydeos.com/t/topic/55961>).
- **Lección para la uke:** el camino «escritorio aarch64 con shell Quickshell» **ya está recorrido en una tablet ARM**, y **las dos cosas que este proyecto daba por asumidas (sin Limine → sin rollback) son exactamente las que el port de Fydetab también declara fuera de alcance.** No es una limitación de la uke; es común a todo port de Omarchy sin UEFI.

### 6.2 moarchy (Pixel 3a, Sway en lugar de Hyprland) — **el precedente que más informa del trabajo fino**

- **Hardware:** SDM670, **Adreno 615 en freedreno, GLES 3.2 y Vulkan**, 4 GB, 1080×2220, `scale 3` → 360×740 lógicos (<https://github.com/SimonSchubert/moarchy>).
- **Qué corre:** **Omarchy v4.0.4** (`c668141`), escrito en el `manifest.toml`; **el shell Quickshell entero** (barra, launcher, notificaciones, OSD), el sistema `omarchy-menu`, las **22 temas** upstream con cambio en vivo, y **plugin de gestos táctiles en Quickshell** que posee el borde inferior como layer surface.
- **Por qué Sway y no Hyprland:** *«Hyprland cannot run on this device. Its renderer… aborts without a GLES 3.x context»*, con el error real `RASSERT(false, "EGL: failed to create a context with either GLES3.2 or 3.0")` y `OpenGL ES 2.0 Mesa 26.2.1` medido en el dispositivo. **El Mali-400 es GLES 2.0** y Hyprland 0.50 ya quitó el renderer GLES2 → compositor obligado: Sway (<https://github.com/SimonSchubert/moarchy/blob/main/docs/build-log.md>).
- **Cuánto QML está acoplado a Hyprland:** **5 de 95 ficheros `.qml`** importan `Quickshell.Hyprland`; los otros 90 usan módulos agnósticos (`Quickshell.Io`, `Quickshell.Wayland`, Pipewire, UPower, SystemTray, Pam, Notifications, Mpris). Traducen `Quickshell.Hyprland` → `Quickshell.I3` con un parche «mecánico» (`pkgbuilds/omarchy-config/port-4x.patch`); el único hueco real es `HyprlandFocusGrab`, sin equivalente I3, que pierde «click-outside-to-dismiss» (<https://github.com/SimonSchubert/moarchy/blob/main/docs/omarchy-4x-feasibility.md>).
- **Medido en el dispositivo:** `shell.qml` real de Omarchy **v4.0.2** alcanzó `INFO: Configuration Loaded` y **siguió vivo, RSS 197 MB**; GPU Adreno 615 on freedreno con GLES 3.2 y Vulkan (<https://github.com/SimonSchubert/moarchy/blob/main/docs/omarchy-4x-feasibility.md>).
- **Lo que perdieron y por qué** (aplicable solo en parte a la uke): blur, sombras, esquinas redondeadas, animaciones, bordes con degradado y `hyprlock` — **no por falta de soporte de Omarchy, sino porque su GPU es GLES 2.0 y no puede con ellos**. **En la uke el Adreno 732 sí es GLES 3.2 → NO hace falta renunciar a blur/sombras por imposibilidad**; solo por presupuesto de rendimiento (§5.3).
- **Dato reutilizable:** `tesseract` no tiene build aarch64 y `voxtype` es x86-only → OCR/dictado se caen en ARM (<https://github.com/SimonSchubert/moarchy>).

### 6.3 omarchy-mac / Asahi (aarch64 en Mac) — **el precedente de Omarchy 4 completo en aarch64**

- **Omarchy Mac** es *«the Omarchy 4 generation, and the first release of Omarchy Mac to fully target Apple Silicon»*, con **paquetes aarch64 pre-construidos servidos desde el org omarchy-mac** y *«graceful fallback for packages that have no ARM build»* (<https://github.com/omarchy-mac/omarchy-mac/releases>).
- Existe repo dedicado: **`omarchy-pkgs-aarch64`**, *«Unofficial aarch64 builds of Omarchy's own packages, for Apple Silicon Macs running Asahi Linux»* (<https://github.com/omarchy-mac/omarchy-pkgs-aarch64>) — y otro fork para UTM/QEMU (<https://github.com/riverscn/omarchy-pkgs-aarch64>).
- **Trampa documentada y relevante:** `omarchy-upgrade-to-quattro` **reescribe el mirrorlist a x86_64 y rompe pacman en aarch64** — por eso existe `omarchy-upgrade-to-quattro-mac`. *«Do not run omarchy-upgrade-to-quattro on a Mac — it rewrites the mirrorlist to x86_64 mirrors and breaks pacman on aarch64»* (<https://github.com/omarchy-mac/omarchy-mac/releases>). **Aplicable a la uke: no usar el upgrade script de x86 sobre ALARM.**
- **Reporte de campo de un M1 real:** instalación de ALARM + Omarchy 4 siguiendo el README del fork; *«that repository was x86-only, so on ARM everything had to be compiled on your machine, and my install took about 40 minutes. The fork now publishes an aarch64 repo of its own, and the README measures a current install at around fifteen minutes with almost nothing built locally»* (<https://grzegorzsmajdor.com/blog/2026-omarchy-asahi-arch-m1>). **Esa es exactamente la mejora que la uke hereda hoy con `[omarchy]` aarch64.**

### 6.4 Raspberry Pi 5 — realidad de ARM en Hyprland

- *«It ran fine on my RPi 5 last I checked»* (u/taylor85345) y *«Yes hyprland runs on a rpi5, and runs normally as one would expect it to»* (u/jloc0), en el mismo hilo donde se avisa: *«The dev doesn't really target ARM so it's not especially optimized»* (<https://www.reddit.com/r/hyprland/comments/1kd9noz/arch_linux_arm/>).
- Otro usuario, Pinebook: *«It ran on my pinebook, it was just very laggy»* (u/AnEagleisnotme, mismo hilo) — coherente: GPU débil, no bug.
- Hay fork con scripts ARM64 para Pi 5: <https://github.com/WillyV3/raspberry-pi-hyprland>. Y en Pi 5 el paquete **existe** en ALARM `extra` (`hyprland 0.56.2-3` aarch64, ver §4.1).
- Hilo de viabilidad en Pi5: <https://www.reddit.com/r/hyprland/comments/1mut3kc/is_it_feasible_to_run_hyprland_on_a_pi5/> (respuestas positivas, con el aviso de que el soporte por distro es el problema, no el compositor).

### 6.5 ThinkPad X13s (Snapdragon 8cx Gen 3) — el caso Qualcomm ARM

- No encontré un informe de «Hyprland en X13s» con números; sí el estado del hardware: el X13s (SC8280XP) tiene buen soporte Linux mainline con ramas WIP de Johan Hovold (<https://github-wiki-see.page/m/jhovold/linux/wiki/X13s>), wiki de aarch64-laptops (<https://github.com/aarch64-laptops/aarch64-laptops.github.io/blob/main/_laptop/thinkpad_x13s.md>) y de Gentoo (<https://wiki.gentoo.org/wiki/Lenovo_ThinkPad_X13s>, con tabla de estado por dispositivo). **[NO VERIFICADO]** rendimiento reportado de Hyprland en X13s: no hay fuente con números.

### 6.6 Snapdragon X Elite + ALARM — **el contraejemplo que más importa**

- Usuario consiguió arrancar ALARM (genérico arm64 + kernel/DTB de Ubuntu) en un HP Omnibook x 14 y **Hyprland no usaba la GPU**: `eglinfo -B` daba `renderer: llvmpipe (LLVM 19.1.7, 128 bits)` y errores `MESA: error: fd_pipe_new2:34: allocation failed`, `MESA-LOADER: failed to retrieve device information` — mientras en Ubuntu el mismo hardware daba `renderer: Adreno X1-85` (<https://www.reddit.com/r/linuxquestions/comments/1l8z3nu/opengl_on_snapdragon_x_elite/>).
- **Por qué importa para la uke:** demuestra que **el fallo típico en Qualcomm+ARM no es el compositor ni Mesa, es el kernel/DTB que no expone la GPU correctamente**. Es la razón por la que §5.1 insiste en el `eglinfo` como prueba previa.

### 6.7 Otros precedentes Omarchy-en-tablet (software, no hardware)

- **`omarchy-surface-touch`** (Surface Pro 7+, Omarchy 4.x, Arch+Hyprland): OSK sin parpadeo (wvkbd parcheado), trackpad virtual en Quickshell + inyector uinput, dos dedos = click derecho, **auto-rotación por acelerómetro con rotación de pantalla *y* táctil**, screensaver descartable con toque, lock con PIN y teclado en pantalla (<https://github.com/javon27/omarchy-surface-touch>). Es prácticamente la lista de tareas de una tablet y está **escrita específicamente para Omarchy 4.x**.
- **`omarchy-drawing-tablet`**: mapea tableta de dibujo a la pantalla correcta desde la barra, y **re-aplica el mapeo tras `configreloaded`, hotplug udev y cambios de monitor** — porque *«Hyprland forgets runtime input settings whenever its configuration reloads»* (<https://github.com/alxcrt/omarchy-drawing-tablet>). **Aplicable al lápiz de la uke.**
- **`maxt.tablet-experience`**: mencionado en el README del proyecto como el plugin que ya hace rotación+calibración+OSK+lápiz con ONNX. **ERRATA (27-sep-2026, ver `G` §6-bis, arreglo 14):** la fuente exacta es **`https://github.com/gmaxxxie/omarchy-tablet-experience`, v1.25.0 (MIT)** — no el plugin de marketplace `cavacuz.tablet` que devolvía esta investigación por la búsqueda. `D:6` y `D:1169` ya dan esa identidad; aquí quedaba la búsqueda divergente.

---

## 7. Riesgos, incógnitas y lo NO verificado

### 7.1 Bloqueantes reales (por orden)

1. **GPU no expuesta / llvmpipe.** Si el kernel palawan no da contexto freedreno GLES 3.2, **Hyprland no arranca de ninguna manera** (RASSERT). Es el gate #1 y se comprueba con una línea (`eglinfo -B`). Precedente del fallo: §6.6.
2. **chip_id del Adreno 732 no reconocido por Mesa `main`.** El a732 sin ID upstream (§5.2); el fork de lfdevs lo cubre como a735 binneado. Si el kernel reporta un ID que Mesa no tiene, freedreno no carga. **Medir el chip_id antes de dar nada por bueno.**
3. **Rotación+táctil.** Resoluble (§5.4, gimbal + omarchy-surface-touch), pero **es trabajo de iteración**, y los issues de Hyprland sobre transform de táctil están cerrados como *not planned* → no habrá arreglo upstream.
4. **Sin rollback.** Sin UEFI/Limine → sin Snapshots de Omarchy. Asumido; idéntico al port de Fydetab.
5. **Menú Install roto en aarch64** (`target not found` en ventana que se cierra). Cosmético pero confuso; el diagnóstico está en #8645.

### 7.2 Incógnitas técnicas que quedan abiertas

- **[NO VERIFICADO]** Si `omarchy update` funciona end-to-end desde un ALARM limpio con `[omarchy]` aarch64, o si algún paquete del `omarchy-base.packages` (~150 nombres) falta en aarch64.
- **[NO VERIFICADO]** Si el `install/` de Omarchy 4 sigue exigiendo limine/btrfs/Snapper (el port de Fydetab dice que sí, fuera de alcance). El guard de x86 sí desapareció en la rama `quattro` (confirmado por dos fuentes independientes: <https://github.com/ggalancs/omarchy-arm-utm> y <https://www.nyk.dev/blog/omarchy-on-mac-utm>), pero eso **no** implica que el instalador sirva para la uke — la uke arranca por `boot.img`, no por UEFI.
- **[NO VERIFICADO]** Números de FPS concretos de Hyprland 0.56 + Quickshell sobre Adreno 732. **No existe** ningún informe público de este SoC concreto; todos los precedentes ARM (§6) son de GPU distintas. La estimación hay que hacerla en la tablet.
- **[NO VERIFICADO]** `render.explicit_sync` y `misc.no_direct_scanout` **no existen con esos nombres** en la wiki 0.56 (verificado por ausencia en el listado completo de opciones). **Si el informe previo los citaba, eran nombres inventados.** Los reales son `render.direct_scanout` y `misc.vfr`.
- **[NO VERIFICADO]** Si `hyprqt6engine` (404 en ALARM) lo necesita alguna parte de Omarchy 4; no aparece en `omarchy-base.packages`.
- **[NO VERIFICADO]** El repositorio de `maxt.tablet-experience` (ver §6.7).
- **[NO VERIFICADO]** Rendimiento de Hyprland en ThinkPad X13s (§6.5): sin fuente con números.

### 7.3 Advertencias de operación (heredadas del proyecto + descubiertas)

- **No ejecutar `omarchy-upgrade-to-quattro`** sobre ALARM: reescribe el mirrorlist a x86_64 y **rompe pacman** (<https://github.com/omarchy-mac/omarchy-mac/releases>).
- **No mezclar versiones de Qt a mano.** `quickshell` va atado a la ABI de Qt6 y el fallo real (exit 127, shell en bucle) costó un «cursor on black» y no se puede arreglar desde la propia sesión porque **el agente polkit vive dentro del shell** → hay que hacerlo desde una TTY (<https://github.com/omacom/omarchy/issues/8438>). **Nota de diseño para la uke: si el shell se cae, no hay polkit. Tener una segunda sesión o TTY accesible.**
- **Al cambiar config de Hyprland, los ajustes de input en runtime se pierden** → re-aplicar (patrón de `omarchy-drawing-tablet` que escucha `configreloaded`).
- **Blur y rotación no se llevan bien** (`use_shader_blur_blend` «glitched on rotated screens») — relevante si la tablet va en vertical.

---

## 8. Recomendación de secuencia (para el proyecto, no ejecutado)

1. **Prueba de una línea, antes de todo:** en la uke, con el kernel palawan y ALARM arrancado, `ls /dev/dri` + `eglinfo -B | grep -A2 "OpenGL ES profile"`. **Si no dice `freedreno` y `OpenGL ES 3.2`, no seguir con Hyprland** — el trabajo pasa al kernel/DTB (informe B).
2. **Instalar la vía barata:** `pacman -S hyprland quickshell uwsm xdg-desktop-portal-hyprland` desde ALARM `extra` (todo existe), apuntar `[omarchy]` a **`https://pkgs.omarchy.org/edge/aarch64`** (⚠️ **no `stable`**: ahí no está el núcleo en aarch64, §4.4) y `pacman -S omarchy omarchy-settings`. Verificar que `pacman -Qi omarchy` resuelve `quickshell` y `hyprland`.
3. **Arrancar Hyprland con la config Lua de Omarchy** (sin la capa `o.*` si estorba: empezar por `hl.*` puro) y **medir** con los bloques de §5.3 desde el primer minuto: blur off, `scale = 1`, `mode = 2136x3200@60`, `render_unfocused_fps = 5`.
4. **Solo después** la capa tablet: `require("hypr.gimbal")` adaptado (§5.4) para rotación + `hl.config{input.touchdevice/tablet}`, y el OSK (wvkbd + el parche de omarchy-surface-touch). Esto solapa con el informe D.
5. **Dejar fuera de alcance, explícitamente:** snapshots/rollback, OCR (`tesseract`), dictado (`voxtype`), y las apps del menú Install con AUR `x86_64`.

**Coste esperado en tiempo:** unpack+install+primer arranque: **un día** (todo son paquetes). Rotación+táctil+OSK usables: **semanas de iteración en dispositivo**, no de compilación. La GPU (Adreno 732/GLES 3.2/8 núcleos/12 GB) está **muy por encima** del Pixel 3a (Adreno 615/4 GB) donde el shell Quickshell de Omarchy 4 ya se midió vivo con RSS 197 MB.

---

## Apéndice A — Comandos de verificación (reproducibles)

```bash
# ¿Está el escritorio para aarch64? ¿Qué versión?
curl -s https://archlinuxarm.org/packages/aarch64/hyprland    # -> hyprland 0.56.2-3, repo extra
curl -s https://archlinuxarm.org/packages/aarch64/quickshell  # -> quickshell 0.3.1-1, repo extra
curl -s https://archlinuxarm.org/packages/aarch64/mesa        # -> mesa 1:26.2.3-1  (A7xx cubierto)

# ¿Existe el repo [omarchy] para aarch64 y qué trae?
curl -o /dev/null -w '%{http_code}\n' https://pkgs.omarchy.org/edge/aarch64/omarchy.db    # -> 200
curl -s https://pkgs.omarchy.org/edge/aarch64/omarchy.db | zstd -dc | tar t | sed 's#/$##' | sort
#   -> omarchy-4.0.4-1, omarchy-settings-4.0.4-2, omarchy-keyring, quickshell-git-0.3.0.r20..., hyprland-0.56.2-3 ...

# ¿Qué declara omarchy aarch64 como dependencias? (¿cierra la cadena en ALARM?)
curl -s https://pkgs.omarchy.org/edge/aarch64/omarchy.db | zstd -dc | tar x -C /tmp/ox
grep -A30 '%DEPENDS%' /tmp/ox/omarchy-4.0.4-1/desc
#   -> omarchy-keyring omarchy-settings=4.0.4 hyprland quickshell uwsm sddm
#      xdg-desktop-portal-hyprland wireplumber pipewire gnome-keyring gum jq git perl
#      fakeroot pacman-contrib ttf-jetbrains-mono-nerd-basic iwd networkmanager

# ¿Existe cada helper en aarch64?
for p in pamixer brightnessctl bluez-utils networkmanager jq curl wl-clipboard upower polkit pam; do
  printf '%-16s ' $p
  curl -s "https://archlinuxarm.org/packages/aarch64/$p" | grep -o '<h1[^>]*>[^<]*</h1>' | head -1
done

# ¿Tiene el Adreno 732 entrada propia en Mesa upstream?
curl -s https://gitlab.freedesktop.org/mesa/mesa/-/raw/main/src/freedreno/common/freedreno_devices.py | grep -n '43030\|FD73'
#   -> sólo FD735 (0x43030B00). a732 NO tiene id upstream (sí en el fork lfdevs, PR #93)

# LA PRUEBA EN LA TABLET (antes de nada):
ls /dev/dri && eglinfo -B 2>/dev/null | grep -A2 "OpenGL ES profile"
#   ESPERADO: vendor "freedreno" + "OpenGL ES 3.2".  Si sale "llvmpipe", Hyprland no arrancará.
```

## Apéndice B — Fuentes primarias (todas consultadas 26-sep-2026)

**Hyprland / Lua**
- <https://wiki.hypr.land/Configuring/Basics/Monitors/> · <https://wiki.hypr.land/configuring/core/monitors/> · <https://wiki.hypr.land/configuring/core/config-options/> · <https://wiki.hypr.land/configuring/core/devices/> · <https://wiki.hypr.land/configuring/core/advanced-configuration/lua-utilities/> · <https://wiki.hypr.land/configuring/extra/performance/>
- <https://github.com/hyprwm/Hyprland/blob/v0.55.2-b/example/hyprland.lua> · <https://raw.githubusercontent.com/hyprwm/Hyprland/main/src/render/OpenGL.cpp>
- <https://reasoncore.dev/post/hyprland-055-switches-configuration-to-lua> · <https://sonto.tech/articles/hyprland-055-kills-hyprlang-moves-configs-to-lua> · <https://alejandrominaya.github.io/hyprland-lua-docs/>
- Issues de tablet/táctil: <https://github.com/hyprwm/Hyprland/discussions/11944> · <https://github.com/hyprwm/Hyprland/issues/4856> · <https://github.com/hyprwm/Hyprland/issues/8814> · <https://github.com/hyprwm/Hyprland/discussions/12041>

**Omarchy 4 «Quattro»**
- <https://github.com/basecamp/omarchy/releases> (v4.0.0) · <https://github.com/omacom/omarchy/pull/6231> · <https://github.com/omacom/omarchy/tree/quattro/shell> · <https://github.com/omacom/omarchy-pkgs>
- Issues: <https://github.com/omacom/omarchy/issues/6968> (Lua/hyprctl) · <https://github.com/omacom/omarchy/issues/8438> (Qt ABI) · <https://github.com/omacom/omarchy/issues/8645> (aarch64)
- Manual: <https://learn.omacom.io/2/the-omarchy-manual> · manual en repo: <https://raw.githubusercontent.com/omacom/omarchy/quattro/README.md>

**Quickshell**
- <https://git.outfoxxed.me/quickshell/quickshell/src/branch/master/BUILD.md> · <https://quickshell.org/docs/guide/install-setup> · <https://github.com/NixOS/nixpkgs/issues/420685>

**Arch Linux ARM / paquetes**
- <https://archlinuxarm.org/packages/aarch64/quickshell> · <https://archlinuxarm.org/packages/aarch64/hyprland> · y consultas directas a `archlinuxarm.org/packages/aarch64/<pkg>` para todos los de las tablas §4
- <https://aur.archlinux.org/packages/quickshell> · <https://aur.archlinux.org/packages/quickshell-git> · <https://security.archlinux.org/package/quickshell>

**Mesa / freedreno / Adreno**
- <https://docs.mesa3d.org/drivers/freedreno.html> · <https://docs.mesa3d.org/drivers/freedreno/hw/lrz.html> · <https://mesamatrix.net>
- <https://gitlab.freedesktop.org/mesa/mesa/-/raw/main/src/freedreno/common/freedreno_devices.py> · <https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/36590>
- <https://github.com/lfdevs/mesa-for-android-container/pull/93> (a732 no-oficial) · <https://www.phoronix.com/news/Mesa-24.3-Freedreno-A7xx> · <https://www.phoronix.com/news/Freedreno-Lands-Adreno-Gen-8>
- <https://lists.freedesktop.org/archives/dri-devel/2023-September/424293.html> (A7xx en drm/msm) · <https://hmc-tech.com/gpus/qualcomm-adreno-732> · <https://www.devicespecifications.com/en/model-battery/756361e0>

**Precedentes ARM**
- Fydetab Duo: <https://community.fydeos.io/t/topic/43275> · <https://wiki.fydetabduo.com/Available-OS/omarchy> · <https://wiki.postmarketos.org/wiki/Fydetab_Duo_(fyde-fydetabduo)>
- moarchy: <https://github.com/SimonSchubert/moarchy> · <https://github.com/SimonSchubert/moarchy/blob/main/docs/build-log.md> · <https://github.com/SimonSchubert/moarchy/blob/main/docs/omarchy-4x-feasibility.md>
- Asahi/Omarchy Mac: <https://github.com/omarchy-mac/omarchy-mac/releases> · <https://github.com/omarchy-mac/omarchy-pkgs-aarch64> · <https://grzegorzsmajdor.com/blog/2026-omarchy-asahi-arch-m1> · <https://github.com/ggalancs/omarchy-arm-utm> · <https://www.nyk.dev/blog/omarchy-on-mac-utm>
- Pi 5 / ARM general: <https://www.reddit.com/r/hyprland/comments/1kd9noz/arch_linux_arm/> · <https://www.reddit.com/r/hyprland/comments/1mut3kc/is_it_feasible_to_run_hyprland_on_a_pi5/> · <https://github.com/WillyV3/raspberry-pi-hyprland>
- Snapdragon X Elite negativo: <https://www.reddit.com/r/linuxquestions/comments/1l8z3nu/opengl_on_snapdragon_x_elite/>
- Tablet sobre Omarchy: <https://github.com/javon27/omarchy-surface-touch> · <https://github.com/alxcrt/omarchy-drawing-tablet> · <https://github.com/mechanicsunlocked/gimbal/blob/master/ARCHITECTURE.md>
- X13s (estado HW, sin números de Hyprland): <https://github-wiki-see.page/m/jhovold/linux/wiki/X13s> · <https://wiki.gentoo.org/wiki/Lenovo_ThinkPad_X13s>

**Hardware objetivo**
- Xiaomi Pad 7 / SM7675 / Adreno 732: <https://www.gsmarena.com/xiaomi_pad_7-13475.php> · <https://www.devicespecifications.com/en/model-battery/756361e0> · <https://hmc-tech.com/gpus/qualcomm-adreno-732>
