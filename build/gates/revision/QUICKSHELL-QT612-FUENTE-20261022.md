# quickshell frente a Qt 6.12 en la tablet «uke» (investigación de solo lectura, 22-oct-2026)

Todas las mediciones son del 22-oct-2026 (caducan el 5-nov). Tablet: solo `pacman -Q/-Qi/-Si/-Qu`, `strings`, `readelf`, `grep`. Descargas hechas en el PC (a `/tmp`), nada instalado ni compilado en la tablet.

## Resumen

**No hace falta compilar.** Omarchy publica ya `quickshell 0.3.2.r7.g2b4501a-2` para aarch64 en `edge`, compilado el 21-oct-2026 contra Qt 6.12 (`rebuilt_against` aarch64 = qt6-base 6.12.0-3, qt6-declarative 6.12.0-1, qt6-wayland 6.12.0-1, justo lo que traería el `-Syu` desde ALARM). Pero **el -Syu rompe la shell igualmente** con el `omarchy 4.0.4-2` instalado, salvo que se actualice también la shell (ver punto 2).

## 1. Origen del 0.3.2-3 instalado (certeza alta)

- `pacman -Qi quickshell`: `0.3.2-3`, Packager `Omarchy <USUARIO@example.invalid>`, build 10-oct-2026 12:07 UTC, `Validated By: None` (instalado con `pacman -U`, no desde un repo configurado).
- `/var/log/pacman.log` 17-oct-2026 20:08 UTC: `pacman -U --needed --noconfirm ... ./qt6-base-6.11.2-3 ./qt6-declarative-6.11.2-2 ... ./quickshell-0.3.2-3-aarch64.pkg.tar.zst ...` (lote de ficheros locales; lo hizo el instalador/port, no hay copia en `/var/cache/pacman/pkg`).
- `/etc/pacman.conf` solo tiene `[core] [extra] [alarm] [aur]` (mirrors ALARM). **No hay repo `[omarchy]`**, así que `pacman -Syu` nunca ofrece paquetes de Omarchy: `pacman -Si quickshell` da el `0.3.2-1` de ALARM `extra` (build 9-oct-2026, URL `git.outfoxxed.me`, **ya compilado contra Qt_6.12**: `strings` del binario de ALARM da `Qt_6.12`).
- Fuente: https://github.com/omacom-io/omarchy-pkgs , carpeta `pkgbuilds/quickshell` (PKGBUILD + `load_qtquick_611.patch` + `quickshell-check.hook`). Historial: `77d62dd` (8-oct, 0.3.2 de upstream), `5fcf959` (10-oct, «Patch Quickshell to temporarily work around Qt 6.12 breakage», #935 → es el 0.3.2-3/-4), `2be7cd9` (17-oct, fija master en `2b4501a`), `d0ede79` (21-oct, `0.3.2.r7.g2b4501a-2`).
- Mi lectura del nombre «-3»: es el rebuild de 10-oct del parche #935 (hipótesis por cronología: no lo he podido contrastar con la salida de CI).
- Parche (`load_qtquick_611.patch`): activa un modo en el escáner de QML de quickshell solo si el `shell.qml` raíz lleva `//@ pragma OmarchyLoadPatch`; entonces reescribe todo `import QtQuick` sin versión a `import QtQuick 6.11`, porque Qt 6.12 añade un singleton `Color` en QtQuick que tapa el `Color` singleton de Omarchy. Aparte, el paquete añade el hook `quickshell-check.hook` (`quickshell --private-check-compat` tras actualizar qt6-base/qt6-wayland). `CRASH_REPORTER=Off`, `RelWithDebInfo`, `DISTRIBUTOR=Omarchy`.
- El 0.3.2-3 instalado contiene el parche (`strings` encuentra `OmarchyLoadPatch`, 2 apariciones), pero **la shell instalada no lo activa**: `/usr/share/omarchy/shell/shell.qml` (paquete `omarchy 4.0.4-2`) empieza por `import QtQuick`, sin pragma, y hay 103 `import QtQuick` sin versión. Los tags de basecamp/omarchy: v4.0.4 sin pragma, **v4.0.5 y v4.0.6 con `//@ pragma OmarchyLoadPatch`** (commit `51717f1`, 10-oct, «Patch all QtQuick imports to 6.11 to work around plugin Color bug»). Es decir, con Qt 6.12 y la shell 4.0.4 el parche es inerte.
- Diferencias con ALARM `0.3.2-1`: ALARM es el tag v0.3.2 sin parches; Omarchy lleva master +7 commits (`d7ee6d1`… `2b4501a`, 17-oct: scriptmodel, hyprland/ipc workspace ids, desktopentry, MOC de namespaces, lock, screencopy null screen, dep metatypes) + el parche. Para la shell de Omarchy ≥4.0.5 el parche es necesario; para la 4.0.4 instalada no lo es, pero tampoco basta.

## 2. ¿Hay build para Qt 6.12 en aarch64? (certeza alta)

| Fuente | Versión | Qt del binario | sha256 |
|---|---|---|---|
| `https://pkgs.omarchy.org/edge/aarch64/quickshell-0.3.2.r7.g2b4501a-2-aarch64.pkg.tar.zst` (2090883 B, build 21-oct 14:20 CEST) | 0.3.2.r7.g2b4501a-2 | `Qt_6.12` | `241fc07e516a52279d72dcb2fb4ec9706445549883ead156234ea735bf5603c2` |
| `https://pkgs.omarchy.org/stable/aarch64/quickshell-0.3.2.r7.g2b4501a-1-aarch64.pkg.tar.zst` (build 17-oct 08:06 CEST) | …-1 | `Qt_6.12` | `e1227d2930f84b78284cdffab8331e6a47632b2f65ee64945d785da1eb659fef` |
| ALARM `extra` `quickshell-0.3.2-1` (9-oct) | 0.3.2-1 | `Qt_6.12` | (sin parche Omarchy) |

- Los dos son descargables hoy (HTTP 200). `edge`/`stable` también tienen `omarchy`: edge `4.5.0rc1-1`, stable `4.0.6-1` (+`omarchy-settings` de la misma versión); `stable` es la opción prudente.
- Dependencias del paquete Omarchy: las mismas que el instalado (cpptrace, jemalloc, libdrm, libpipewire, qt6-base/declarative/svg/wayland…), todas disponibles en ALARM.
- Upstream: no hay release posterior a v0.3.2 (8-oct-2026). El problema de Qt 6.12 NO está resuelto en upstream: issue https://github.com/quickshell-mirror/quickshell/issues/1295 (abierto, 11-oct): «qs.* imports resolve singletons to their type instead of the instance under Qt 6.12», afecta a 0.3.1 y 0.3.2 (y rompe la shell Omarchy 4: colores sin inicializar, pantalla negra en la SUPER+SPACE). Ese issue explica por qué Omarchy usa el parche de import 6.11 en vez de esperar. #1296 (SIGSEGV en `QWaylandWindow::handleScreensChanged`, 11-oct) cerrado. Otras roturas 6.11→6.12 que afecten a APIs privadas: no encontré más fuentes primarias; el aviso a vigilar es que `--private-check-compat` falle.
- Qué falta fuera de quickshell: el `-Syu` completo (110 paquetes pendientes) arrastra qt6-base/declarative/svg/wayland/translations 6.11.2→6.12.0.

## 3. Receta de reconstrucción (por si se quiere compilar igualmente)

PKGBUILD verbatim en `https://raw.githubusercontent.com/omacom-io/omarchy-pkgs/master/pkgbuilds/quickshell/PKGBUILD` (+ el `.patch` y el `.hook` de la misma carpeta, sha256 del patch `23b65d205d825f11a1cd8501acbc6e50250d09a6ce607e2ff8b3cf5d438bd0ce` y del hook `8543e21aeaaa5441b73a679160e7601a957f16c433e8d6bd9257e80bd0e94083`). Build: `cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo -DDISTRIBUTOR=Omarchy -DCRASH_REPORTER=Off -DCMAKE_INSTALL_PREFIX=/usr -DINSTALL_QML_PREFIX=lib/qt6/qml`.

makedepends vs tablet (22-oct):
- Instalados: `cmake 4.4.4`, `ninja 1.13.2`, `git 2.56.0`, `spirv-tools 1.4.363`, `wayland-protocols 1.49`, `gcc 16.1.1`, `make`, `binutils`, `fakeroot`, `pkgconf`, `makepkg`/pacman 7.1.0; runtime ya presentes (cpptrace 1.0.4-2, jemalloc, libdrm, mesa, pipewire, polkit, qt6-svg/wayland/base/declarative).
- Faltan: `cli11` 2.7.2-1 (88 KiB), `vulkan-headers` 1:1.4.363.0-1 (2.0 MiB, 42 MiB instalado), `qt6-shadertools` 6.12.0-1 (1.6 MiB, 6.3 MiB). **`qt6-shadertools` 6.12 exige qt6-base 6.12**, así que no se puede compilar contra 6.12 antes del `-Syu` en el sistema vivo; haría falta un chroot/contenedor aparte (o compilar tras el -Syu). `base-devel` no existe como grupo en ALARM (error `package not found`), irrelevante.
- Descarga estimada: ~3.7 MiB de makedepends + fuente git de quickshell (~15–25 MiB, estimación) → ~25 MiB.
- Tiempo y memoria: **no medidos** (estimación sin evidencia): ~400 unidades C++/MOC con Qt; en 8 núcleos Arm unos 15–40 min con `-j8`, 1–1,5 GB por job de cc1plus ⇒ con 7,4 GiB totales (4,2 GiB libres, sin swap) usar `MAKEFLAGS=-j4` o `cmake --build build -j4`, `nice -n 19`, `-DCMAKE_BUILD_TYPE=Release` en vez de RelWithDebInfo (menos memoria y disco), y lanzar con `setsid nohup ... &` (regla 6 de AGENTS). `/etc/makepkg.conf` ya tiene `!debug !lto`. Hay 94 GB libres.
- Mejor opción: no compilar, usar el paquete de Omarchy ya compilado (punto 2).

## 4. Plan seguro propuesto (no ejecutado)

Pre-requisito: el hook `00-omarchy-update-guard.hook` (PreTransaction, `AbortOnFail`) aborta cualquier `pacman -Syu` directo; se salta con `OMARCHY_ALLOW_DIRECT_PACMAN=1` (o pasando por `omarchy-update`). Y nada de esto debe hacerse con otra sesión usando la tablet, ni sin cargador (bajada de 110 paquetes + regeneración de initramfs: el hook `90-mkinitcpio-install` corre; ver regla 8/9 del AGENTS y el contador de slots).

1. Backup previo (antes de tocar nada): copiar a `/root/qs-rollback-20261022/` los ficheros del paquete actual (`pacman -Qlq quickshell | tar -czf` ... + `pacman -Qi quickshell` + sha256 de `/usr/bin/quickshell`), ya que `quickshell-0.3.2-3` **no está en la caché de pacman** y ALARM no guarda versiones antiguas. Hacer lo mismo con `qt6-base 6.11.2-3`, `qt6-declarative 6.11.2-2`, `qt6-svg`, `qt6-wayland` (tampoco están en caché: `ls /var/cache/pacman/pkg | grep qt6-` vacío). Apuntar en la nota el `.PKGINFO` del backup (no son binarios para versionar).
2. Descargar en el PC, verificar sha256 (tabla del punto 2), `scp` a `/root/qs-new/`: `quickshell-0.3.2.r7.g2b4501a-1` (stable) o `-2` (edge); y si se quiere shell que active el parche, `omarchy-4.0.6-1` + `omarchy-settings-4.0.6-1` de `stable/aarch64` (descargar también y verificar sus sha256 con `stable/aarch64/omarchy.db`). Mezclar quickshell con omarchy 4.0.4 NO sirve (pragma ausente).
3. Ensayo sin riesgo: ya que quickshell 0.3.2-3 y el nuevo comparten nombre, no se pueden tener a la vez instalados. Ensayo alternativo: extraer el nuevo `.pkg.tar.zst` a `/root/qs-new/x/` y ejecutar `LD_LIBRARY_PATH` + `x/usr/bin/quickshell --private-check-compat` solo tras el -Syu (con Qt 6.11 dará fallo, es esperable).
4. `OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -Syu` e **inmediatamente en la misma línea / mismo comando de SSH** `pacman -U --noconfirm /root/qs-new/quickshell-*.pkg.tar.zst` (y los omarchy 4.0.6 si procede). Lo fiable es una sola transacción: `pacman -Syu` y `-U` por separado dejan la ventana en que `quickshell-check.hook` avisa de incompatibilidad. Antes del reinicio de la sesión gráfica.
5. Verificación: `quickshell --version` (esperado `Quickshell 0.3.2 ... distributed by Omarchy`), `quickshell --private-check-compat` (código 0), `strings /usr/bin/quickshell | grep -o 'Qt_6\.[0-9]*'` = `Qt_6.12`, `pacman -Qkk quickshell`. Luego reiniciar la shell **desde ssh** (no desde la propia barra): `quickshell -d` / el comando que use Omarchy (`omarchy-restart-shell` si existe, no verificado) con `WAYLAND_DISPLAY`/`XDG_RUNTIME_DIR` de la sesión, y mirar `journalctl --user` / salida por «Color typeof» o pantalla negra (síntoma de #1295).
6. Rollback si la barra no sale: por ssh (o consola ACM) `pacman -U` del paquete que se guardó (para quickshell, reinstalar la copia de los ficheros del paso 1 sobre `/` con `tar -xzf -C /` si no hay paquete; los Qt 6.11 solo se recuperan desde ese backup porque no están en caché). Recuperación sin barra: Hyprland sigue funcionando sin quickshell (terminal con `Super+Return`, en ejecución ya hay sesión ssh), no depende de él para renderizar.
7. Si el parche pragma no actúa o falta (shell 4.0.4), último recurso: `-Syu` con `IgnorePkg = qt6-base qt6-declarative qt6-svg qt6-wayland qt6-translations qt6-shadertools` para congelar Qt en 6.11 hasta que se actualice a omarchy 4.0.6 (los demás paquetes sí pueden subir; cuidado con otras dependencias de Qt6 en ALARM: `pacman` lo reportará como dependencia rota, no probado).

## Lo no verificado

- Que el `-Syu` completo (110 paquetes) deje arrancable la tablet: no probado (kernel/initramfs/slots son otra gate).
- Que la shell 4.0.4 se rompa exactamente con #1295 en esta tablet: es la inferencia del issue y de la ausencia del pragma, no lo he reproducido (no se toca la tablet).
- Que omarchy 4.0.6 / hyprland 0.56.2-7 de Omarchy sean compatibles con el hyprland 0.56.2-4 local y con el port a Adreno 732: no comprobado (el README de omarchy-mac advierte conflictos de SONAME de `libaquamarine` al ensanchar `[omarchy]`).
- Tiempos y consumo de compilación (estimaciones); tamaño real del git clone.
- Cómo se numeró el `-3` en CI y si la 4.0.4-2 instalada es el último «4.0.4» (hay `omarchy-settings 4.0.4-6` y `omarchy 4.0.4-2`).
- Otras roturas Qt 6.11→6.12 más allá de #1295 (no hallé changelog upstream).
