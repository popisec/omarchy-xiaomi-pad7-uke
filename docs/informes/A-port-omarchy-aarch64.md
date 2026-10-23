# Portar Omarchy a aarch64 — disección del árbol upstream, del port de Fydetab Duo y del ecosistema ARM

**Fecha:** 26-sep-2026 · **Objetivo:** llevar Omarchy 4 (Arch + Hyprland + shell Quickshell) a una tablet ARM64 (Xiaomi Pad 7, SM7675, aarch64) · **Método:** inspección directa del código con `git clone`, `curl` a las APIs de GitHub, `raw.githubusercontent`, los repos de paquetes y el registro del marketplace. Cada afirmación va con URL. Los datos no verificados están marcados como tal en §7.

---

## 1. Resumen ejecutivo

**La conclusión grande: el problema no es portar Omarchy. El problema era el repositorio de paquetes, y ese repositorio ya existe.**

Omarchy 4 es un árbol *agnóstico de arquitectura*: 461 scripts bash, 186 ficheros QML, 128 migraciones, 22 temas y ficheros de configuración Lua. Ninguno de esos segmentos tiene código dependiente de arquitectura. Lo que sí es x86_64 con mayúsculas es:

1. `pkgs.omarchy.org/$channel/x86_64/` — el repo de paquetes propietario de Omarchy (248 paquetes, incluidos `omarchy` y `omarchy-settings`, que **son** el escritorio).
2. `mirror.omarchy.org` / `stable-mirror.omarchy.org` — mirrors de Arch x86_64.
3. El stack de arranque que arrastra la meta-dependencia `omarchy`: `limine` + `limine-mkinitcpio-hook` + `limine-snapper-sync` + `snapper` (UEFI/x86), y el kernel `linux-omarchy`.

**Estado real de aarch64 en upstream (verificado hoy, 26-sep-2026):**

| Comprobación | Resultado |
|---|---|
| `https://pkgs.omarchy.org/stable/aarch64/omarchy.db` | **200** — el repo aarch64 existe (22 paquetes) |
| `https://pkgs.omarchy.org/stable/x86_64/omarchy.db` | 200 (248 paquetes) |
| ¿Está `omarchy-4.0.4` en el repo aarch64? | **NO.** Ni `omarchy`, ni `omarchy-settings`, ni `quickshell`, ni `hyprland` |
| `https://stable-mirror.omarchy.org/core/os/aarch64/core.db` | **404** (x86_64 → 200) |
| `arch=()` en `omacom/omarchy-pkgs` | `omarchy` y `omarchy-settings` declaran `arch=('x86_64' 'aarch64')` con `depends_aarch64` y un `package()` que borra el stack x86 |
| Guard de arquitectura en el árbol | **Cero.** `uname -m` no aparece en la rama `quattro` |

Es decir: **upstream ya tiene las recetas aarch64 y un repo aarch64 parcial, pero no publica los 22 paquetes que hacen falta para instalar el escritorio.** El hueco es exactamente 22 paquetes que ya declaran `aarch64` y solo necesitan que alguien ejecute `makepkg` en una máquina ARM. (El repo aarch64 contiene solo: `aether`, `claude-code`, `claude-desktop`, `crush-bin`, `cursor-bin`, `cursor-cli`, `elsewhen`, `flea`, `github-copilot-cli`, `learn-omarchy`, `mise-bin`, `omarchy-billboard-generator`, `omaspeak-bin`, `omawake-bin`, `openai-codex-bin`, `openai-codex-desktop`, `openclaw`, `owe`, `owe-lockfeed`, `schist-bin`, `strata`, `sublime-text-4`.)

**¿Existe un port reutilizable? Sí, y es bueno: el de Fydetab Duo (RK3588S).** Repo `Linux-for-Fydetab-Duo/imagebuild`, perfil `profiles/omarchy/`. Publika imágenes `prod-omarchy-v0.2.5` (Omarchy 4.0.1, Hyprland 0.56, Quickshell) y mantiene un repo pacman rolling propio (`[fyde]`) con los paquetes de Omarchy reconstruidos para aarch64. Además hay **al menos cinco** ports aarch64 más (§3.4), dos de ellos con repositorio de paquetes firmado propio — señal de que el trabajo ya está hecho varias veces y de que se puede reutilizar.

**Dificultad por pieza:**

| Pieza | Dificultad | Por qué |
|---|---|---|
| `omarchy` + `omarchy-settings` (config, 461 scripts, QML, temas) | **Trivial** | `arch=('x86_64' 'aarch64')` ya; el `package()` ya ramifica por `CARCH` |
| Herramientas propias (Rust/Go/Qt: `omacalc`, `omacut`, `omawrite`, `ttfx`, `herdr`, `tensaku`, `aether`, `cliamp`, `mise-bin`…) | **Baja-media** | Compilan en ARM tal cual; la mayoría ya declara aarch64; ~1-2 h de máquina |
| Quickshell + shell Omarchy (`shell/`, 16 plugins) | **Trivial** | QML puro; `quickshell` está en ALARM |
| Hyprland + aquamarine + hyprtoolkit | **Media** | ALARM los tiene, pero su índice se rompe de vez en cuando (SONAME de `libaquamarine`) → hay que compilar de fuentes de Arch |
| Kernel | **Alta (pero no es de Omarchy)** | Hay que sustituir `linux-omarchy` por el kernel del SoC: en Fydetab `linux-fydetab` 6.12 cross-compilado; en SM7675 no hay kernel mainline equivalente |
| Stack de arranque (Limine/UEFI/Btrfs/snapper) | **Alta o se descarta** | Fydetab lo tira entero (U-Boot + boot.scr) y pierde snapshots en menú, factory reset e hibernación |
| GPU / vídeo / cámara / táctil en el SoC concreto | **Alta** | Panfrost/panthor en RK3588S; en SM7675 (Adreno + drm/msm) es un mundo aparte |
| **UX de tablet** (gestos, rotación, teclado en pantalla) | **La incógnita real** | Omarchy es keyboard-first; el propio port lo deja como "fase abierta" |

**Ruta recomendada (coste mínimo, máximo reutilización):** copiar la arquitectura del proyecto Fydetab (Docker x86 host + chroot aarch64 con `qemu-aarch64` binfmt con flag F, PKGBUILDs vendorizados en `pkgbuilds/`, modos `cross`/`emulated`/`noarch`, repo `[fyde]` publicable por rsync, hook `pre-refresh-pacman` que restaura el pacman.conf propio) y cambiar tres cosas: los blobs de arranque, el PKGBUILD del kernel y el overlay de hardware. Todo lo demás (los ~24 PKGBUILDs Omarchy, los hooks de arranque de imagen, el manifiesto de paquetes con las sustituciones documentadas) es reutilizable byte a byte.

---

## 2. Mapa del repo Omarchy (rama `quattro`, commit `e1614f2b`)

Fuente: `git clone --depth 1 https://github.com/basecamp/omarchy` (repo `omacom/omarchy`, antes `basecamp/omarchy`; el repo se movió — la API redirige). Versión en `version`: **`4.0.0.alpha`**. La rama por defecto **es `quattro`**, no `master`: `master` es Omarchy 3.8.5 (waybar, config `.conf`) y es un producto distinto. Clonar sin `-b` da 4.x.

```
agents/        7 ficheros   40K    guías de tarea para agentes (agents/skills/*.md)
applications/ 34            820K   .desktop propios (web apps: Basecamp, HEY, X, YouTube…)
bin/         461            2.5M   TODO el CLI omarchy-* (451 bash, 5 python3, 5 bash -p)
config/       42            320K   defaults de usuario -> package-owned /etc/skel/.config
default/     189            1.4M   árbol de referencia instalado en /usr/share/omarchy/default
docs/         10            152K   referencia de arquitectura (shell, update-process, theming…)
etc/          41            308K   drop-ins de sistema que el paquete posee
install/      85            420K   scripts de instalación (ISO: config/, hardware/, login/, user/…)
manual/       95            3.8M   manual de usuario (52 capítulos)
migrations/  128            560K   migraciones per-usuario, versionadas por epoch
plans/         7            116K   notas de diseño internas
shell/       186            2.2M   el escritorio Quickshell (shell.qml, Ui/, services/, plugins/)
test/        334            2.8M   tests de aceptación (gráficos) + CLI + shell
themes/      249             65M   22 temas (fondo + templates de tema)
TOTAL (sin .git): 80M
```

### 2.1 Qué es binario x86_64 y qué no — y la respuesta es: **nada en este repo lo es**

Comprobado byte a byte:

- `bin/` — **461 ficheros, CERO ELF.** 451 con shebang `#!/bin/bash`, 5 `#!/usr/bin/python3`, 5 `#!/bin/bash -p` (los *security entrypoints*: `omarchy-update`, `omarchy-refresh-pacman`… que exigen bash privilegiado y saneado).
- `shell/` — QML + JavaScript (`BarModel.js`) + `manifest.json`. Nada compilado.
- `themes/` — fondos (imágenes) y 21 templates `.tpl` (`default/themed/*.tpl`) que se renderizan al cambiar de tema.
- `default/fonts/omarchy/omarchy.ttf` — la fuente de iconos de marca (el README del proyecto pide *"nunca renombrar este fichero / familia"*).
- `default/plymouth/*.png`, `default/sddm/omarchy/*` — assets.

**Consecuencia directa y central: el árbol de Omarchy se puede instalar entero en aarch64 sin tocar una línea.** El `package()` del PKGBUILD hace:

```
for bin in bin/*; do install -Dm755 "$bin" "$pkgdir/usr/bin/$base"; done
cp -a install themes migrations shell version "$pkgdir/usr/share/omarchy/"
```
(Ver `pkgbuilds/omarchy/PKGBUILD` en `https://github.com/omacom/omarchy-pkgs/blob/master/pkgbuilds/omarchy/PKGBUILD`.)

### 2.2 El problema real: la meta-dependencia y el repo

`omarchy` (el paquete) declara estas dependencias duras:

```
depends=('omarchy-keyring' "omarchy-settings=${pkgver}" 'hyprland' 'quickshell' 'uwsm' 'sddm'
         'xdg-desktop-portal-hyprland' 'wireplumber' 'pipewire' 'gnome-keyring'
         'gum' 'jq' 'git' 'perl' 'fakeroot' 'pacman-contrib' 'ttf-jetbrains-mono-nerd-basic')
depends_x86_64=('limine' 'limine-mkinitcpio-hook' 'limine-snapper-sync' 'snapper')
depends_aarch64=('iwd' 'networkmanager')
```

**Este es el punto clave del port.** `depends_x86_64` mete el stack UEFI/Limine/snapper por dependencia del **paquete**, no por el instalador: no basta con no instalar Limine, hay que **reconstruir el paquete** sin esas cuatro dependencias (o usar el `depends_aarch64` que upstream ya define). Y `omarchy-settings=${pkgver}` es un pin exacto: los dos paquetes tienen que salir del mismo commit y subir juntos.

Y el repo:

```
# default/pacman/pacman-stable.conf
[core]  Include = /etc/pacman.d/mirrorlist
[extra] Include = /etc/pacman.d/mirrorlist
[multilib] Include = /etc/pacman.d/mirrorlist
[omarchy]
Server = https://pkgs.omarchy.org/stable/$arch
```

(`default/pacman/pacman-{stable,rc,edge}.conf` y `mirrorlist-{stable,rc,edge}`; `install/post-install/pacman.sh` los copia encima de `/etc/pacman.conf` y `/etc/pacman.d/mirrorlist`. Los mirrors son `stable-mirror.omarchy.org` / `mirror.omarchy.org`, x86_64 only.)

### 2.3 Qué contiene `omarchy-settings` (el paquete que "es" el escritorio)

`pkgdesc='Omarchy user defaults, /etc/skel content, fonts, plymouth theme, and support helpers'` — 1,3 MB instalados, `arch=('x86_64' 'aarch64')`, y **`package()` con ramas explícitas por `CARCH`**:

| En aarch64 | Qué hace upstream |
|---|---|
| `config/**` → `/etc/skel/.config/` **y** `/usr/share/omarchy/config/` | igual |
| `default/**` → `/usr/share/omarchy/default/` | igual |
| `rm -rf /etc/limine-entry-tool.d /etc/mkinitcpio.conf.d` | fuera el stack de arranque x86 |
| `rm -rf /etc/systemd/oomd.conf.d`, `zram-generator.conf`, `tmpfiles.d/omarchy-zswap.conf` | fuera el stack de memoria x86; reescribe `/etc/sysctl.d/99-omarchy-sysctl.conf` dejando **solo** `net.ipv4.tcp_mtu_probing=1` |
| `rm -f /etc/modprobe.d/omarchy-usb-autosuspend.conf` | autosuspend USB al default |
| `rm -rf /usr/share/omarchy/default/limine` | plantilla de Limine solo ISO x86 |
| quita `limine-snapper-notify.desktop` de `/etc/skel/.config/autostart` | no autostart de algo inexistente |
| Unidades **user** (`/usr/lib/systemd/user/`): `bt-agent`, `omarchy-sleep-lock`, `omarchy-recover-internal-monitor`, `omarchy-migrate-notify`, `omarchy-tailscale-receive`, `omarchy-fcitx5`, `omarchy-crash-watch` | igual en ambas arquitecturas |

Es decir: **el trabajo de separar x86 de aarch64 en los ficheros de sistema ya está hecho upstream.** Lo que falta es solo compilar y publicar.

### 2.4 Interfaces del sistema (lo que "engancha" con el SO anfitrión)

Estas son las piezas que un port a otra distro/tablet tiene que respetar:

| Ruta | Qué es |
|---|---|
| `/usr/share/omarchy/` (`$OMARCHY_PATH`) | La raíz del árbol. `config/hypr/hyprland.lua` hace `dofile(os.getenv("OMARCHY_PATH") or "/usr/share/omarchy" .. "/default/hypr/bootstrap.lua")` |
| `/usr/bin/omarchy-*` | 461 comandos. **El árbol hardcodea `/usr/bin/`** (13 sitios, 5 de ellos `.service`) → instalar en `/usr/local/bin` rompe unidades y primer arranque |
| `/etc/skel/.config/` | Defaults de usuario (se copian a `~/.config/`; `omarchy-refresh-*` los re-sincroniza desde `/usr/share/omarchy/config/`) |
| `/etc/` | Drop-ins de sistema (logind, resolved, systemd, sudoers.d, udev, sysctl, faillock, plymouth, sddm) |
| `install/` | Scripts que **solo corre el instalador ISO** (85 ficheros): `config/` (docker, ufw, snapper, temas, ssh), `hardware/` (detección de hardware: 40+ scripts Intel/NVIDIA/Apple/Dell/ASUS/Lenovo/Surface/T2), `login/` (sddm), `user/` (mise, git, chromium, keyring, primer arranque), `provisioning/` (`omarchy-provision-owner.service`, `setup-form.sh`) |
| `migrations/*.sh` | 128 migraciones que corren **como el usuario** vía `omarchy-migrate`; estado en `~/.local/state/omarchy/migrations/<fichero>`. Muchas llaman `omarchy-pkg-add` |
| `default/libalpm/hooks/*.hook` | Guard de actualización (impide `pacman -Syu` a pelo), pausa/reanudación de recarga de Hyprland |
| `default/omarchy/omarchy-menu.jsonc` | 380 líneas de definición del menú (Super+Space). Las filas de *Install* son binds a `bin/omarchy-install-*` |

### 2.5 Lista de paquetes base (155 líneas, ~147 paquetes)

`install/omarchy-base.packages` (155 líneas con comentarios ≈ 147 entradas) + `install/omarchy-other.packages` (75 líneas, *todo* hardware x86: `nvidia-*`, `intel-*`, `limine`, `linux-omarchy`, `lib32-*`, `tuxedo-drivers`, `broadcom-wl-dkms`…).

Del manifiesto base, los elementos que no son Arch genérico (y por tanto son los que hay que resolver):

- **Primeros partidos de Omarchy**: `aether`, `cliamp`, `herdr`, `omacalc`, `omacut`, `omawrite`, `omarchy-nvim`, `tobi-try`, `ttfx`, `tzupdate`, `yay`, `mise-bin`, `xdg-terminal-exec`, `yaru-icon-theme`, `ufw-docker`, `localsend`, `ttf-ia-writer`, `ttf-jetbrains-mono-nerd-basic`, `elsewhen`, `quickshell`, `hyprland-preview-share-picker`, `owe`, `owe-lockfeed`, `omasnap`, `usage`, `dua-cli`, `eza`, `gum`, `asdcontrol`, `tldr`.
- **Cosas que no existen en aarch64** (ver §5): `pinta`, `obsidian`, `obs-studio`, `dotnet-runtime`, `qemu-user-static-binfmt`.
- **Comentario en el propio manifiesto**: `# OWE owns desktop video backgrounds and feeds the lock screen its frames.`

---

## 3. El caso Fydetab Duo (RK3588S) — el port de referencia

### 3.1 Repos y releases verificados

| Recurso | URL | Datos |
|---|---|---|
| Código + pipeline de imagen | `https://github.com/Linux-for-Fydetab-Duo/imagebuild` | creado 2026-08-14, último push 2026-08-27, 3★, sin licencia declarada |
| Release con las imágenes | `https://github.com/Linux-for-Fydetab-Duo/imagebuild/releases/` | `prod-omarchy-v0.1.0` → **`prod-omarchy-v0.2.5`** (2026-08-27) |
| Repo pacman rolling | release tag `repo` del mismo repo: `https://github.com/Linux-for-Fydetab-Duo/imagebuild/releases/download/repo` | 56 assets; los dispositivos lo usan como `Server =` |
| Anuncio en el foro | `https://community.fydeos.io/t/topic/43275` | *"🚀 Omarchy for Fydetab Duo — first release"*, 2026-08-19, autor `wei6` |
| Guía de instalación | `https://wiki.fydetabduo.com/Available-OS/ArchLinux/arch-install` | flasheo con `rkdeveloptool` / RKDevTool |
| PKGBUILDs vendorizados de Omarchy | `pkgbuilds/OMARCHY-VENDOR.md` (24 recetas de `omacom-io/omarchy-pkgs` @ `5a73fd8`) | con las modificaciones locales documentadas |

### 3.2 Cómo construyen los paquetes Omarchy para aarch64

El proyecto es **autocontenido** (lee solo su propio directorio; lo externo se vendoriza con un `PROVENANCE.md`). Punto de entrada único: `build.sh`.

```sh
./build.sh containers          # dos contenedores de build (~830 MB la primera vez)
./build.sh sync                # espeja en ./repo los paquetes publicados que no construye
./build.sh pkg [nombre]        # construye PKGBUILDs -> ./repo (el repo pacman aarch64)
./build.sh image [perfil]      # bootstrap -> customize -> assemble -> publish
./build.sh all [omarchy]
```

- **Requisitos**: docker + un handler `qemu-aarch64` binfmt **con el flag F (fix-binary)**. `build.sh` se niega a arrancar sin ambos, porque el flag F es lo que permite ejecutar binarios aarch64 dentro del chroot destino sin copiar qemu dentro (sin él, todo paso emulado falla con un ENOENT confuso).
- **Modos de build** (`pkg/BUILDMODES`) — el corazón del sistema:

| Modo | Qué hace | Paquetes (reales del fichero) |
|---|---|---|
| `cross` | toolchain x86_64 con `ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-` | `linux-fydetab-6.12` (**único**) |
| `emulated` | `makepkg` dentro de un contenedor **Arch Linux ARM aarch64** bajo qemu binfmt | `calamares`, `mutter`, `ttfx`, `herdr`, `cliamp`, `omacalc`, `omacut`, `omawrite`, `yay`, `tensaku`, `tzupdate`, `hyprland-preview-share-picker`, `sunshine` |
| `noarch` | `makepkg` en x86_64 con `CARCH=aarch64 --ignorearch` (no compila nada) | `omarchy`, `omarchy-settings`, `omarchy-dev`, `omarchy-settings-dev`, `omarchy-emacs`, `omarchy-keyring`, `omarchy-nvim`, `ttf-*`, `tobi-try`, `ufw-docker`, `xdg-terminal-exec`, `yaru-icon-theme`, `aether`, `mise-bin`, `localsend-bin`, `omazed`, firmware, extensiones |
| `skip` | no se construye | `linux-fydetab` (superseded), `grub`, `grub-btrfs` |

- Los 24 PKGBUILDs de Omarchy van **`noarch`**, es decir: no compilan nada, `package()` solo instala ficheros y, donde hay binario, hace *repack* de un release aarch64 prebuilt. Esto confirma la tesis de §2.1.
- El `makepkg.conf` propio fuerza `CARCH="aarch64"` / `CHOST="aarch64-unknown-linux-gnu"` y se inyecta como drop-in en `/etc/makepkg.conf.d/` (no con `--config`, que se cargaría el resto del makepkg.conf).
- **Repo**: `repo/fyde/aarch64/` con el layout publicado exacto (`Server = .../pacman/repo/$repo/$arch`), publicable por rsync. Se publica en la release `repo` de GitHub. `profiles/*/pacman.conf` pone `[fyde]` **el primero** a propósito: pacman resuelve por orden de fichero, así que su `linux-fydetab` 6.12.43 gana sobre el 6.1.75 publicado.

### 3.3 Qué desactivaron y por qué (declarado por ellos)

Del plan (`docs/omarchy-profile-plan.md`) y de las notas de release:

- **Los tres pilares de infraestructura de Omarchy son x86_64-only y se puentean**: `mirror.omarchy.org` (espejo de Arch x86), `pkgs.omarchy.org/$arch` (x86), `omarchy-iso` (ISO instalador UEFI x86). Su frase: *"Portamos el escritorio, no el instalador ni la infraestructura de distribución de Omarchy."*
- **El stack UEFI/Limine/LUKS/Btrfs/snapper se tira entero** en v0.1.x: *"no UEFI, no grub: la placa arranca u-boot → boot.scr → kernel."*
- **v0.2.1 recupera btrfs+snapper** (subvolúmenes `@`, `@home`, `@log`, `@pkg`, `.snapshots`, zstd) con helper propio `fydetab-snapshot-restore`; el menú de snapshots de Omarchy funciona, pero **no** el arranque desde snapshot, ni factory reset, ni hibernación: eso necesita el menú de Limine.
- **Carencias declaradas en las notas de release** (`prod-omarchy-v0.2.1`, v0.2.5):
  - Sin cifrado de disco (la oficial lleva LUKS2 por defecto). El flujo opt-in de cifrado en primer arranque *"se implementó y se aparcó: añadía 8-10 minutos más un reinicio extra"*, en la rama `luks-encryption`.
  - *"Algunas instalaciones del menú no pueden funcionar en ARM: 1Password, Spotify, Dropbox, Cursor, LM Studio, Minecraft, Heroic/Lutris y otras apps x86-only no tienen aarch64 upstream."*
  - Arranque en modo texto (sin splash de Plymouth).
  - Sin factory reset ni hibernación.
- Del anuncio del foro: *"caveats honestos: es un release experimental — sin cifrado de disco / sin snapshots btrfs (necesitan el stack Limine que la tablet aún no puede ejecutar), **algunas apps del menú son x86-only**, y el login por defecto es omarchy/omarchy"*.
- **Paquetes omitidos a propósito**: `asdcontrol` (Apple Studio Display), `dotnet-runtime` + `pinta` (no hay dotnet en ALARM), `obs-studio`, `obsidian`, `qemu-user-static-binfmt` (concern del host de build, no del destino). Seis, los mismos que documenta el header de su `packages.list`.
- **`omarchy-chromium-bin`** (parcheado por Omarchy) se sustituye por el `chromium` stock de ALARM.
- **`walker` + `elephant`** no se vendorizan: solo los referencia el migrador 3.x→4.0; Omarchy 4 los reemplazó por el lanzador Quickshell.
- Los instaladores propietarios x86 (1password, cursor, spotify, steam, GeForce NOW, Battle.net, windows-vm, modelo de `voxtype`) se dejan en su sitio: *"fallan o no hacen nada con elegancia"*.

### 3.4 Modificaciones locales a PKGBUILDs upstream (mínimas, deliberadas)

De `pkgbuilds/OMARCHY-VENDOR.md`:

- **`omarchy/PKGBUILD`** (la única modificación estructural): **quita las deps de Limine** (`limine`, `limine-mkinitcpio-hook`, `limine-snapper-sync`) porque arranca U-Boot, no UEFI. `snapper` se conservó cuando el root pasó a btrfs. `arch` pasó a `('any')` en su copia (era la verdad entonces).
- **`tensaku`, `tzupdate`, `hyprland-preview-share-picker`**: `arch=()` ampliado a aarch64 — *"tres builds de fuentes Rust sin código específico de arquitectura; upstream simplemente nunca amplió el campo."*
- **`omarchy-nvim`**: añadido `neovim` a `makedepends` (su `build()` corre `nvim --headless "+Lazy! sync"`).
- **`sunshine`**: quitada `libmfx` de depends (QSV de Intel, ausente en ALARM aarch64); compila sin ella (encoding software).
- **`voxtype-bin`**: se añadió (reescritura aarch64 del PKGBUILD de AUR), se probó en el dispositivo el 2026-08-19 y **no funciona** → eliminado. Consecuencia: la entrada de dictado del menú no resuelve.
- **`omazed`** verbatim: desbloquea la entrada de Zed (`omarchy-pkg-add zed omazed` abortaba en el nombre no resoluble).

### 3.5 Vías muertas e infra conocida del pipeline

- **Consumir los scripts `install/` de upstream tal cual: imposible.** Probaron `omarchy apply system --defer-provisioning`: `config/firewall.sh` aborta el apply completo (ufw sobre `iptables-nft` emulado no puede abrir socket netlink bajo qemu-user), **36 de 51 pasos sondean el hardware del HOST de build** (`lspci`, `cpuinfo`, DMI desde arch-chroot), y `post-install/pacman.sh` reemplaza `/etc/pacman.conf` + mirrorlist por los x86. Solo 15 de 51 pasos son chroot-safe → decidieron mantener un árbol de hooks propio.
- **Escape sancionado para pacman**: `omarchy-refresh-pacman` fuerza `default/pacman/pacman-$channel.conf` sobre `/etc/pacman.conf`. El hook sancionado es `~/.config/omarchy/hooks/pre-refresh-pacman.d/` → shippean `restore-fydetab-repos` que restaura sus repos. (Con `NoExtract` para los drop-ins x86 de mkinitcpio en `overlay/etc/pacman.conf`.)
- **`iio-sensor-proxy` no tiene `[Install]`** → solo se puede habilitar con symlink `.wants` manual.
- **`omarchy-provision-owner`** en tty1 antes de SDDM: exige **teclado físico** (no hay OSK en tty1 ni en el greeter SDDM); autologin solo del primer arranque, con unidad autoborrable.
- **Problemas reales que encontraron y su lección**: `omarchy-update-restart` busca `/usr/lib/modules/<ver>/vmlinuz` (existe en Arch x86, **no** en ALARM, que pone `Image` en `/boot`) → pide reiniciar en cada update para siempre; lo resuelven con un wrapper en `/usr/local/bin`. En ARM, `omarchy-pkg-add` aborta si un nombre no existe y **tumba todo `omarchy-update`** → wrapper que separa repo/AUR/desconocido y salta lo no resoluble. Las migraciones se *sellan* (se marcan todas como hechas) para que un install limpio nazca en el estado final.

### 3.6 Arranque

Blobs prebuilt de la cadena Rockchip escritos a offsets fijos, **sin receta de build en el proyecto**:

| Fichero | LBA | Tamaño |
|---|---|---|
| `idblock.bin` | 64 | 239 616 |
| `uboot.img` | 16384 | 4 194 304 |
| `resource.img` | 24580 | 12 964 352 |

Particiones: p1 FW (64s–65535s, reserva), p2 ESP FAT32 512 MiB (mounted `/boot`; `boot.cmd` hardcodea `setenv bootpart 2`), p3 ROOTFS btrfs (`rootpart 3`, `rootflags=subvol=/@`). El `boot.scr` **no es un blob**: se genera con `mkimage` desde `profiles/arch-gnome/boot/boot.cmd`. `uboot.img` se reemplazó el 2026-08-13 por uno que **sí resume de DEEP suspend** (el BL31 antiguo reiniciaba la placa al despertar, verificado en hardware). La release `prod-omarchy-v0.2.5` se flashea con `rkdeveloptool`/RKDevTool (Loader mode).

**UEFI/Limine: evaluado y diferido.** Requiere sustituir el firmware de arranque: U-Boot mainline con `EFI_LOADER` (port de placa; recuperación rehacible como script de env con la tecla ADC) o **EDK2-rk3588** (port más pesado). *El problema duro en ambos casos*: el menú de snapshots de Limine necesita salida DSI en fase de firmware y entrada de teclado USB, si no el rollback es solo por serie. Ya existe un port EDK2-rk3588 FydetabDuo local (`~/workspace/edk2-rk3588`, panel DSI cableado, nunca validado en dispositivo).

---

## 4. Tabla maestra: componente → origen → cómo se porta → dificultad

Leyenda de "origen": **[X]** = solo existe como binario/paquete x86_64 · **[A]** = existe en repos aarch64 (ALARM / Arch Linux ARM) · **[R]** = receta propia a recompilar · **[S]** = script/config (agnóstico).

| Componente | Origen | Cómo se porta | Dificultad | Fuente |
|---|---|---|---|---|
| `omarchy` (meta + 461 bin + install/ + migrations/ + themes/ + shell/) | **[S]** pero empaquetado **[X]** | `makepkg` del PKGBUILD con `OMARCHY_SRC=` o del repo; en aarch64 hay que quitar `depends_x86_64` (limine×3 + snapper) o usar el `depends_aarch64` que upstream ya declara | **Trivial** | `omacom/omarchy-pkgs/pkgbuilds/omarchy/PKGBUILD` |
| `omarchy-settings` (skel, /etc, fonts, temas SDDM, plymouth, unidades user) | **[S]**, paquete **[X]** | Igual; upstream ya ramifica `package()` por `CARCH` y borra el stack x86 | **Trivial** | `pkgbuilds/omarchy-settings/PKGBUILD` |
| Shell Quickshell (`shell/`, 16 plugins: bar, menu, lock, osd, notifications, polkit, clipboard, emojis, reminders, panels, image-picker, services, background, agents, dev-gallery) | **[S]** (QML) + **`quickshell`** runtime | QML no compila; `quickshell` está en ALARM (0.3.x). Upstream pinnea `quickshell-git` (`arch=(x86_64 aarch64)`) | **Trivial** | `docs/omarchy-shell.md`, `shell/plugins/README.md` |
| `hyprland` + `hyprland-guiutils` + `hyprtoolkit` + `aquamarine` | **[A]** con roturas | ALARM los tiene; cuando su índice se rompe por SONAME, compilar **desde las recetas de Arch** (`omacom/omarchy-pkgs` también los tiene: `pkgbuilds/hyprland`, `hyprtoolkit`, `hyprland-guiutils`, `aquamarine`) | **Media** | `docs/omarchy-profile-plan.md` (defecto `libaquamarine.so=13 vs 14`) |
| Config Hyprland en **Lua** (ejecutado dentro del compositor) | **[S]** | ALARM enlaza `lua` en hyprland → **toda la capa de config corre sin modificar**. Ojo: si el panel es portrait, Hyprland/aquamarine **ignora** `panel orientation` → `monitor = DSI-1, preferred, auto, 1, transform, 3` explícito | **Trivial** | `default/hypr/*.lua`, `config/hypr/hyprland.lua` |
| `uwsm`, `sddm`, `xdg-desktop-portal-hyprland`, `wireplumber`, `pipewire`, `gnome-keyring`, `gum`, `jq`, `perl`, `fakeroot`, `pacman-contrib` | **[A]** | Instalar de ALARM | **Trivial** | deps de `omarchy` |
| `linux-omarchy` (kernel propio, x86) | **[X]** | **Sustituir** por el kernel del SoC. Fydetab: `linux-fydetab` 6.12.43 con `ARCH=arm64 CROSS_COMPILE=` (modo `cross`, PKGBUILD sin editar); para la tablet Snapdragon, el kernel equivalente de drm/msm | **Alta** | `pkg/BUILDMODES`, `docs/build-internals.md` |
| `limine` + `limine-mkinitcpio-hook` + `limine-snapper-sync` | **[X]** (x86/UEFI) | **Dropear** o portar UEFI completo. Fydetab lo dropea y pierde menú de snapshots, factory reset e hibernación | **Alta / descartar** | `pkgbuilds/omarchy/PKGBUILD` |
| `snapper` + btrfs | **[A]** (`snapper`, `btrfs-progs`) | Funciona si el root es btrfs con el layout `@`/`@home`/`@log`/`@pkg`/`.snapshots`. `omarchy-snapshot` funciona; el rollback es un CLI propio, no menú de arranque | **Media** | `docs/storage-stack-plan.md` |
| Plymouth (splash) | **[A]** | Paquete + tema shippean, pero *"Plymouth nunca corre: a nuestro mkinitcpio HOOKS le falta `plymouth` y a boot.cmd `splash`"* (y sin verificar que renderice en VOP2/DSI) | **Baja** | `docs/omarchy-feature-gaps.md` §10 |
| **Herramientas propias**: `omacalc`, `omacut`, `omawrite` | **[R] Qt6/C++ (qmake+make)** | `arch=(x86_64 aarch64)` ya; `makedepends=(gcc make qt6-base qt6-declarative)`. Compilan tal cual | **Baja** | PKGBUILDs respectivos |
| `ttfx` (Rust), `herdr` (Zig+Rust), `tensaku` (Rust, gtk4), `hyprland-preview-share-picker` (Rust) | **[R] Rust/Zig** | `arch=(x86_64 aarch64)`; `ttfx` incluso tiene `makedepends_x86_64=(nasm)` (el ensamblador solo hace falta en x86). `herdr` usa Zig 0.15.2 exacto (`zig-aarch64-linux-0.15.2.tar.xz`) | **Baja-media** (~12 min `ttfx`) | PKGBUILDs + `ARTICULO.md` |
| `aether`, `cliamp` (Go), `yay` (Go) | **[R] Go** | `source_aarch64` ya existe (`aether-linux-arm64`). Portables directos | **Baja** | PKGBUILDs |
| `mise-bin`, `localsend`, `omarchy-chromium-bin` | **[R] repack de binario upstream** | Ya tienen `source_aarch64` (tarball arm64 de mise, AppImage/paquete arm64 de LocalSend, `.pkg.tar.zst` aarch64 de omarchy-chromium). **`localsend` no está en ALARM por nombre → sustituir por `localsend-bin`** | **Trivial** | PKGBUILDs + `packages.list` |
| `omarchy-nvim`, `tobi-try`, `elsewhen`, `ttf-ia-writer`, `ttf-jetbrains-mono-nerd-basic`, `xdg-terminal-exec`, `ufw-docker`, `yaru-icon-theme`, `omarchy-emacs`, `omazed` | **[S] / `arch=any`** | Ni compilan: son datos/scripts/fuentes. Únicos ajustes: `omarchy-nvim` necesita `neovim` en `makedepends` | **Trivial** | `OMARCHY-VENDOR.md` |
| `owe` + `owe-lockfeed` (fondos de vídeo + frames al lock) | **[R] meson/C** | `arch=(x86_64 aarch64)`; `makedepends=(meson ninja gcc pkgconf wayland-protocols)` | **Baja** | PKGBUILD |
| `omasnap` (Qt6 + tesseract), `omarchy-task-manager` (C++/Rust) | **[R]/[S]** | `omasnap` declara aarch64; **`omarchy-task-manager` declara `arch=('x86_64')` a secas** → añadir aarch64 o descartar | **Baja** | PKGBUILDs |
| `voxtype` / dictado | **[X] binarios** | El repack aarch64 de Fydetab **no funcionó en dispositivo** (2026-08-19). Alternativa: OSK (`wvkbd`, `squeekboard`) que Omarchy no trae | **Media-Alta** | `OMARCHY-VENDOR.md` |
| `quickshell-git` (por si hace falta post-release) | **[R] CMake/C++/Qt** | `arch=(x86_64 aarch64)`, `cmake -GNinja`; ALARM ya trae `quickshell` release | **Media** (~compila todo QML/Qt) | PKGBUILD |
| `chromium` / theming de navegador | **[A]** | ALARM trae `chromium` stock (151). El parcheado de Omarchy (`omarchy-chromium-bin`) tiene aarch64 upstream pero va por detrás de ALARM: es una **decisión** (branding vs versión) | **Baja** | `omarchy-pkgs-coverage.md` (Open flags) |
| `graphics stack`: panthor + Mesa/panfrost + `vulkan-panfrost` + firmware `arm/mali/arch10.8/mali_csffw.bin` | **[A]** | No es de Omarchy: el driver del SoC. Fydetab dejó de usar el blob `mali_kbase` y `mesa-panfork-git` | **Alta** (varía por SoC) | `docs/build-internals.md` |
| Apps del menú *Install* del todo x86 | **[X]** | Ver §5.3. Salen del menú o se dejan en "falla con elegancia" | **Imposible** | `docs/omarchy-pkgs-coverage.md` |
| UX de tablet (gestos, rotación, OSK) | **[S]** pero ausente | Omarchy es keyboard-first; `touchegg` es X11-only (inerte bajo Hyprland). Rotación: `iio-sensor-proxy` + helper propio; el port lo deja como **fase abierta** | **Alta (la incógnita)** | `docs/omarchy-profile-plan.md` §Phase 4 |

---

## 5. Los "x86-only": lista concreta con stack y por qué

### 5.1 Lo que **NO** es x86-only aunque parezca que sí

Dos correcciones de hecho que circulan mal y que conviene fijar:

1. **`omarchy` y `omarchy-settings` no tienen NADA de código no portable.** El 2026-09-02, el commit `4ed5f14` de `omacom/omarchy-pkgs` les puso `arch=('x86_64' 'aarch64')` con `depends_<arch>` y un `package()` que borra el stack x86 en ARM. Lo x86_64-only es **el repositorio donde se publica**, no la receta. (Verificado hoy en el PKGBUILD: `arch=('x86_64' 'aarch64')`, `depends_aarch64=('iwd' 'networkmanager')`.)
2. **Omarchy 4 no tiene guard de arquitectura.** Omarchy 3.x sí: `install/preflight/guard.sh` línea 25, `[[ $(uname -m) != "x86_64" ]] && abort`. En `quattro` el directorio `preflight/` no existe y **`uname -m` aparece cero veces**. El bloqueo pasó de "se niega" a "no hay repo de dónde instalar", que es un problema mucho más pequeño.
3. **`omarchy` NO es `arch=('any')`** (error que circuló porque era verdad en agosto): ver nota en `ggalancs/omarchy-arm-utm` README, que corrige su propia afirmación el 2026-09-04.

### 5.2 EL x86-only real y medible

Lo que **hoy (26-sep-2026) existe solo para x86_64** y bloquea una instalación:

| Elemento | Qué es | Estado |
|---|---|---|
| `https://stable-mirror.omarchy.org/core/os/aarch64/core.db` | espejo de Arch | **404** (x86_64 → 200) |
| `pkgs.omarchy.org/*/aarch64/` | repo de paquetes Omarchy | **existe pero no publica `omarchy` ni `omarchy-settings`** (22 paquetes, ninguno del escritorio) |
| `linux-omarchy` | kernel propio de Omarchy (x86) | x86 only; repo aarch64 solo tiene su variante **para Asahi** (`uboot-asahi`, sin publicar) |
| `limine`, `limine-mkinitcpio-hook`, `limine-snapper-sync` | bootloader UEFI | x86/UEFI |
| `omarchy-chromium-bin` | Chromium parcheado por Omarchy | tiene aarch64 upstream, va por detrás de ALARM |
| `linux-omarchy-{bore,muqss}` + `-headers` | variantes de kernel | x86 |
| Toda la lista `install/omarchy-other.packages` | `nvidia-*`, `intel-*`, `lib32-*`, `tuxedo-drivers`, `broadcom-wl-dkms`, `macbook12-spi-driver-dkms`, `yt6801-dkms` | x86 hardware enablement |

### 5.3 Apps del menú con stack conocido — el inventario que pidió el §4

Clasificación por **lenguaje/stack real** (de los PKGBUILDs de `omacom/omarchy-pkgs`, del sheets de `omarchy-mac/omarchy-pkgs-aarch64` y del análisis de `ARTICULO.md`):

| App / componente | Stack real | ¿Porta a aarch64? | Detalle |
|---|---|---|---|
| `omacalc`, `omawrite`, `omacut` | **Qt6 / C++ (qmake + make)** | **Sí, ya declarado** | `arch=(x86_64 aarch64)`; dependen de `qt6-base qt6-declarative` (+`qt6-multimedia` en omacut) |
| `tensaku` (editor de capturas) | **Rust + GTK4** | Sí | `arch=(x86_64 aarch64)`; `rust` + `gtk4 gtk4-layer-shell libadwaita libepoxy` |
| `ttfx` (efectos de salvapantallas) | **Rust** | Sí | `cargo`; `makedepends_x86_64=(nasm)` — el ensamblador es solo x86 |
| `herdr` | **Zig + Rust** (`libghostty-vt`) | Sí (con cuidado) | **Zig 0.15.2 exacto**; el PKGBUILD de AUR está roto (invoca `zig fetch` con semántica 0.15 contra repos 0.16) y el de `omarchy-pkgs` ya baja el tarball `zig-aarch64-linux-0.15.2.tar.xz` |
| `aether` (temas desde el fondo) | **Go** (binario prebuilt) | Sí | `source_aarch64=…/aether-linux-arm64` |
| `cliamp` (reproductor TUI) | **Go** | Sí | `makedepends=(go)` |
| `yay` | **Go** | Sí | `arch` ya incluye `aarch64` (y hasta `riscv64`) |
| `tzupdate` | **Rust** | Sí | `makedepends=(cargo)`; `arch` ampliado localmente por Fydetab |
| `hyprland-preview-share-picker` | **Rust + GTK4** | Sí | `makedepends=(cargo)`, `arch` ampliado localmente |
| `mise-bin` | **Rust (binario de jdx)** | Sí | `source_aarch64` del release oficial |
| `localsend` / `localsend-bin` | **Flutter / Dart** | Sí | Tarball arm64; **nombre distinto en ALARM** |
| `owе`, `owe-lockfeed` | **C / meson** | Sí | `arch=(x86_64 aarch64)` |
| `omasnap` | **C++ / CMake + Qt6 + tesseract** | Sí | declara aarch64 |
| `omarchy-task-manager` | **C++/Qt6 + Rust/cmake/ninja** | **NO declarado** (`arch=('x86_64')`) | añadir aarch64 o descartar |
| `strata` (navegador de ficheros GTK4) | **Rust + GTK4** | Sí (declara aarch64) | deps largas: gtk4, gtksourceview5, poppler-glib, gst… |
| `flea` (gestor de ficheros en sandbox) | **Rust** | Sí (declara aarch64) | depende de `quickshell`, `qt6-webengine`, `omarchy` |
| `quickshell-git` | **C++ / Qt6 / CMake** | Sí (`arch=(x86_64 aarch64)`) | |
| `sunshine` (game streaming) | **C++ / CMake** | Sí, con parche | quitar `libmfx` (QSV Intel); ARtículos: `makedepends_aarch64=(vulkan-headers)` |
| `omarchy-chromium` | **Chromium (C++/GN)** | Sí, binario upstream | aarch64 existe en el repo de releases |
| `obs-studio` | **C++ / CMake, CEF para el browser dock** | **Sí, con recorte** | `omarchy-mac` compila `ENABLE_BROWSER=OFF` porque el CEF prebuilt de obsproject es x86_64 only; ALARM no lo tiene |
| `pinta` | **C# / .NET (GTK)** | **Sí** | .NET oficial arm64 de Microsoft; el `.deb`/PKGBUILD de AUR es `arch=('x86_64')` y hardcodea `linux-x64` |
| `obsidian` | **Electron** | Sí (hay arm64 upstream) | no en ALARM |
| `zed` | **Rust** | Sí (release aarch64 del vendor) | Arch lo tiene `x86_64` only; Omarchy pide el nombre `zed` exacto |
| `cursor-bin` | **Electron (AppImage)** | Sí | AppImage `linux-arm64` del vendor; receta omarchy x86-only |
| `grok-bot` | **Electron** | Sí | repack del `.deb` `linux-arm64` |
| **Imposible (propietario x86 prebuilt)** | — | **No** | `1password` (+beta), `spotify`, `dropbox` (+`-cli`), `steam`, `typora`, `lmstudio-bin`, `minecraft-launcher`, `heroic-games-launcher-bin`, `bambustudio-bin`, `basecamp-cli`, `dbxcli-bin` |
| **JIT x86** | — | **No** | `libretro-blastem` (JIT x86) — mantiene muerta la entrada de RetroArch |
| Otros sin aarch64 en ALARM | — | depende | `ghostty` (toolchain Zig), `ollama`, `bitwarden`, `drople...`, `symfony-cli` (¡el vendor sí publica arm64!) |

**Dato de conjunto** de `docs/omarchy-pkgs-coverage.md`: de las ausencias del manifiesto, **~16 eran construibles** solo ejecutando `makepkg` en ARM, **~13 son permanentemente x86**, y las que quedan en zona gris son entrada por entrada del menú (una entrada del menú que pida *un solo* nombre irresoluble **aborta la transacción entera**; 13 entradas están permanentemente muertas).

### 5.4 Los agentes de IA (bloque grande del menú *Install > AI*)

No son código C: son **stubs de `mise`** en `~/.local/bin` (nada se descarga hasta el primer uso) más algunos repacks. De `manual/17-ai.md`:

| Comando | Agente | Stack de distribución |
|---|---|---|
| `claude` | Claude Code | stub mise (nativo por arquitectura) |
| `codex` | OpenAI Codex | stub mise |
| `opencode` | OpenCode | stub mise |
| `agy`, `copilot`, `crush`, `grok`, `pi`, `omp`, `ori`, `muse`, `cursor-agent` | varios | stubs mise / repacks |
| `hermes` | Hermes (Nous) | **excepción**: no hay stub; elegirlo instala **Hermes Desktop** (`hermes-desktop`), que crea un checkout en `~/.hermes` con su venv y se actualiza con `hermes update` |
| Apps gráficas | ChatGPT desktop (`openai-codex-desktop`), Claude desktop (`claude-desktop`), Grok Bot, Hermes Desktop, OpenClaw, Perplexity | repacks en el repo de Omarchy |

En el repo **aarch64** ya están publicados `claude-code`, `claude-desktop`, `crush-bin`, `cursor-bin`, `cursor-cli`, `github-copilot-cli`, `openai-codex-bin`, `openai-codex-desktop`, `openclaw`, `strata`, `schist-bin`, `flea`, `learn-omarchy`. **Es decir: la parte de agentes de IA de Omarchy ya es aarch64 en upstream.** Los que faltan en aarch64 son `grok-bot`, `perplexity`, `hermes-desktop`, `t3code-bin`, `basecamp-cli`.

---

## 6. El sistema de plugins (Omarchy 4) y qué implica para aarch64

### 6.1 Cómo se declara un plugin

Un plugin es **un repo git con un `manifest.json` en la raíz**. Esquema `schemaVersion: 1`:

```json
{
  "schemaVersion": 1,
  "id": "my.org.cool-clock",
  "name": "Cool clock",
  "version": "1.0.0",
  "author": "You",
  "description": "A clock that does cool things",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "Widget.qml" },
  "barWidget": {
    "displayName": "Cool clock",
    "category": "Time",
    "allowMultiple": false,
    "defaultSection": "left",
    "defaults": { "format": "HH:mm" },
    "schema": [ { "key": "format", "type": "string", "label": "Format" } ]
  }
}
```

Claves reales observadas en los manifests shippeados: `schemaVersion`, `id`, `name`, `version`, `author`, `description`, `license`, `kinds`, `entryPoints`, `keepLoaded`, `activation`, `omarchy`, `barWidget.{displayName,category,description,defaultSection,allowMultiple,defaults,schema,settingsForm,aliases}`.

**`kinds`**: `bar-widget`, `bar`, `panel`, `overlay`, `menu`, `service`. Solo un `bar` está activo a la vez. `keepLoaded: true` sobrevive entre summons y entre hot-reloads (por eso `omarchy.lock` no se destruye mientras Hyprland sostiene el bloqueo).

**Clasificación de origen**: los de primera parte viven en `$OMARCHY_PATH/shell/plugins/` y se marcan `__isFirstParty: true`; los de terceros en `~/.config/omarchy/plugins/<id>/` y reciben **facades con capacidades limitadas** (no acceden a servicios de autenticación; siguen compartiendo la escena QML, así que no es un sandbox).

### 6.2 La API que se expone

Son **tres superficies distintas**, y conviene no confundirlas (la tarea mencionaba `o.launch_on_start` y `hl.monitor`, que **no son API de plugin**, son API de config de usuario):

| Superficie | Quién la usa | Ejemplo |
|---|---|---|
| **Lua de Hyprland** (`hl.*` y `o.*`) | La config del usuario/compositor, cargada por `default/hypr/bootstrap.lua` | `hl.config({...})`, `hl.monitor({ output = "DP-2", disabled = true })`, `hl.gesture({...})`, `hl.unbind(...)`, `o.bind(...)`, `o.rebind(...)`, `o.launch_on_start("hyprsunset")`, `o.window("qemu", {workspace="5"})` |
| **IPC** `omarchy-shell <target> <method> [args]` | CLIs y scripts | `omarchy-shell shell ping`, `omarchy-shell shell summon omarchy.menu '{"menu":"root"}'`, `omarchy-shell shell toggle omarchy.menu …`, `omarchy-shell omarchy.indicators refresh`, `omarchy-shell image-selector open …` (posicional, con `imageRowsB64` base64) |
| **Propiedades inyectadas al cargar** | El propio plugin (QML) | `omarchyPath`, `shell`, `manifest`, `pluginRegistry`, `barWidgetRegistry` |

**Métodos IPC documentados del target `shell`**: `ping`, `summon <id> <payloadJson>`, `hide <id>`, `toggle <id> <payloadJson>`, `togglePanelAt <section> <index>`, `call <id> <method> <arg>`, `listPlugins`, `rescanPlugins`… Targets: `shell`, `image-selector`, `background`, `osd`, `media`, `notifications`, y por-widget (`omarchy.clock`, `omarchy.power`). **No hay target `bar`** (el bar se maneja con `omarchy bar use|reset|defaults|position|transparent|put|move|set`).

Notas de comportamiento: `omarchy-shell` **falla si el shell no está corriendo** (`-q` lo hace best-effort); `OMARCHY_SHELL_IPC_TIMEOUT` acota la espera; `$OMARCHY_PATH/shell/shell.qml` debe existir o el comando falla explícitamente.

**El ciclo de vida del plugin es 100 % QML/bash/JSON** — el shell lo arranca `omarchy-launch-shell` como un único proceso Quickshell (`QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 systemd-cat -t omarchy-shell -- quickshell -n -p "$OMARCHY_PATH/shell"`), con supervisión propia y hasta 5 relanzamientos por minuto.

### 6.3 El Plugin Marketplace: **asume x86_64 por omisión, sin decirlo**

- Sitio: `https://plugins.omarchy.org` → sirve un proyecto Cloudflare Pages que es el **marketplace comunitario** `omacom/omarchy-plugin-marketplace` (307★, últimos cambios 26-sep-2026). El sitio real de descubrimiento es **`https://omarchyplugins.com`** (también 200), con portal de desarrollo en `/develop.html`.
- Datos: `registry.json` (7,5 MB, 4198 entradas). **Lo inspeccioné entero: no existe ningún campo de arquitectura.** Búsqueda de `aarch64`, `arm64`, `x86_64`, `architectur`, `platform` → **0 ocurrencias**; "binary" 121 veces (en prosa de descripciones), `rust` 9, `cargo` 1.
- Los campos de una entrada: `repo`, `repositoryIdentity` (nodeId/databaseId/previousRepositories), `type`, `addedAt`, `listingValidatedCommit/At/Branch`, `previewPath/Width/Height`, `catalog.{id,name,description,author,version,category,tags,accent,initials,kind,status}`, `plugins`, `automatedSecurityBaseline`, `maintainerVerificationReview(History)`.
- **Distribución**: `omarchy plugin add <url-git>` clona a `~/.config/omarchy/plugins/<id>/` y **no ejecuta nada del plugin** (ni hooks de instalación, ni sudo): clona ficheros, valida el manifest y cambia un bit por IPC. Actualizar es un fast-forward con diff previo; `remove` deshabilita y borra (o mueve a backup si no es un repo git).
- **El único punto donde la arquitectura importa** está en el propio `docs/historia/AGENTS.md` del marketplace (línea ~148): *"Root community plugins default to the generated standard Omarchy install command… Use a manual installation override only when that command cannot produce a functioning plugin, **such as when a required native binary is absent or a mandatory build must run before enablement**"*, y en `SECURITY.md`/baseline: *"Treat executable binaries as review capabilities, narrowly scoped root-owned helpers as review cases rather than automatic blockers"*. Es decir: existe la noción de "plugin que necesita un binario nativo o un build" y se resuelve con un `plugins.<id>.installation` de `mode: "manual"` + nota. **No hay categoría de arquitectura.**

**Implicación para aarch64, en claro:**

1. **Un plugin puramente QML/JSON funciona en aarch64 sin que nadie lo declare** — es el caso mayoritario, porque el plugin es QML.
2. Un plugin que **llame a un binario** (CLI en `PATH`, helper en `/usr/bin`) funcionará en aarch64 exactamente con la misma probabilidad con la que ese binario exista en aarch64. El marketplace no lo filtra, no lo marca y no lo verifica: **el coste cae sobre el usuario.**
3. Un plugin que **traiga un binario propio** (p. ej. un helper Rust prebuilt x86_64) fallará en aarch64 sin aviso; el marketplace lo tratará como "capability de binario ejecutable" (revisión de seguridad), no como incompatibilidad de arquitectura.
4. El marketplace **clona HEAD mutable** upstream y no está atado a un SHA verificado: no sirve como fuente de reproducibilidad, y menos aún como garantía multiplataforma.

**Esto es, en la práctica, el hueco más fácil de cerrar de todo el port y el de mayor retorno.** El `registry.json` es un fichero estático generado por CI: añadir un campo de arquitectura (o, mejor, un `platforms[]` derivado del manifest) y filtrar en la UI es trabajo de una tarde en `omacom/omarchy-plugin-marketplace`, y convertiría el marketplace en algo que un usuario ARM puede usar sin sorpresas.

---

## 7. Precedentes adicionales de Omarchy en aarch64

Búsqueda en la API de GitHub (`q=omarchy aarch64`) — 19 repos, ordenados por relevancia. Tabla comparativa de lo que funcionó / se rompió:

| Proyecto | Plataforma | Estrategia | Qué funcionó | Qué se rompió / costó |
|---|---|---|---|---|
| **`Linux-for-Fydetab-Duo/imagebuild`** (perfil `omarchy`) | RK3588S (Fydetab Duo) | Docker x86 host + chroot aarch64 emulado + repo pacman propio (`[fyde]`) + U-Boot | Escritorio completo, Wi-Fi/BT, GPU panthor, suspend profundo con lock-on-suspend, ufw, zram, theming, LocalSend, `omarchy-update` funciona | Stack Limine/btrfs-snapshots/factory reset/hibernación (v0.1.x), sin cifrado, Plymouth, ~13 entradas de menú x86, `voxtype` |
| **`ggalancs/omarchy-arm-utm`** (35★) | VM aarch64 en Apple Silicon (HVF) | **Reproduce a mano el paquete `omarchy`** (no existe para ARM); 18 paquetes construidos de fuente (9 propios de Omarchy + 9 de AUR con `arch` ampliado) | Desktop completo, `omarchy-update` con hook post-update, snapper pre-update, clipboard SPICE | Software rendering por defecto (bug UTM 4.7 GPU); `/usr/local/bin` rompió 13 rutas hardcodeadas y los 6 `.service` de usuario; `omarchy-update-restart` pide reinicio infinito (`vmlinuz` no existe en ALARM); migraciones históricas tumban `omarchy-update` (hay que sellarlas) |
| **`riverscn/omarchy-aarch64-image`** (46★) + `riverscn/omarchy-pkgs-aarch64` | VM UEFI aarch64 genérica (QEMU `virt`/UTM QEMU) | **Repo pacman aarch64 firmado propio**, imagen con UKI + **Limine** (`EFI/BOOT/BOOTAA64.EFI`), btrfs `@/@home/@log/@pkg`, primer arranque en tty1 | Menú de arranque de Limine con entradas de snapshot y recovery, Plymouth, `@factory` read-only, VirtIO/SPICE, 9p | Construye en runner `ubuntu-24.04-arm`; excluye `gpu-screen-recorder` y OBS; sin `linux-firmware` (perfil virtual); sin cifrado (a propósito) |
| **`omarchy-mac/omarchy-pkgs-aarch64`** (4★, activo hoy) | Apple Silicon / Asahi | Colección de builds aarch64 de los paquetes de Omarchy; `[omarchy]` con `Usage = Sync` + 3 targets explícitos de Hyprland de edge | Recetas in-tree para `obs-studio` (`ENABLE_BROWSER=OFF`), `pinta` (dotnet arm64), `cursor-bin`, `grok-bot`, `zed`, `avd-fw`, `libva-v4l2_request-avd` | *"no debe instalar de `pkgs.omarchy.org/edge/aarch64`"*: ensanchar `[omarchy]` a Install normal es "cómo consigues que el Hyprland oficial pelee con el SONAME de `libaquamarine` de ALARM" |
| **`wakatara/omarchy-aarch64`** (0★, nov-2025) | Asahi ALARM | Fork del árbol 3.1.5 con `install.sh` propio | Precedente más antiguo (Omarchy 3, waybar) | Congelado en 3.1.5; **no sirve para 4.x** |
| **`alexisraitano-myffu/omarchy-arm`** (9★) | "Apple Silicon, Raspberry Pi 5, VM aarch64" | Instalador sobre Arch Linux ARM ya en marcha | — | Último push ago-2026; README 404 en `main` (no verificado) |
| **`NaustudentX18/omarchy-pi5-quattro`** (1★) | Raspberry Pi 5 | Imagen flash-and-go "estilo Omarchy" | PCIe Gen3 NVMe, control de ventilador | 1★, no verificado |
| **`SimonSchubert/omarchy-mobile`** (5★) | VM aarch64 + UI móvil | Omarchy sin modificar + UI móvil **encima**, no en lugar de | Enfoque interesante para tablet | No verificado a fondo |
| Otros | `kim-raaschou/omarchy-aarch64` (script único, feb-2026), `happybigmtn/omarchy-arm-fixes` (ago-2025), `maralcbr/omarchy-aarch64-*` (recetas "factory" para varios binarios), `ZacharyZhang-NY/omarchy-pkgs-aarch64` | — | — | Bajo impacto / bit-rot |

**No encontrados / no verificados**: no aparece ningún port específico para **Snapdragon / ThinkPad X13s / Windows Dev Kit 2023 / Arm laptops**. En `manual/49-omarchy-on.md` upstream solo lista Asahi (guía `omarchy-mac`), VM Parallels/VirtualBox/VMware, Steam Deck (`deckarchy`) y NixOS (`omarchy-nix`). El canal del Discord `#omarchy-on-other` es donde vive lo no documentado.

### Lecciones transversales de los precedentes (todas verificadas en fuente)

1. **La lista de paquetes de una distro es una afirmación sobre su arquitectura, no un inventario** (*"Yo la completé con lo que recordaba de la versión anterior"* — el `walker`/`elephant` muerto). Auditar **por resolución de nombre por transacción**, nunca por "¿hay un sustituto funcional?".
2. **"No disponible" no es una categoría.** Hay que separar *imposible* (1Password, Spotify, Obsidian, Typora) de *nadie lo ha construido todavía* (casi todo lo demás). Meter `pinta` en el cajón de imposibles costó semanas sin editor de imágenes.
3. **Muchos PKGBUILDs declaran `arch=(x86_64)` por omisión del mantenedor, no por incompatibilidad.** Basta `sed` sobre `arch=()` si es Rust/Go/C++ portable.
4. **Mirar primero si upstream ya lo resolvió.** `herdr` parecía requerir compilar Zig 0.15 desde fuente; el PKGBUILD de `omarchy-pkgs` ya bajaba el tarball aarch64 correcto.
5. **`/usr/bin` no es negociable**: el árbol hardcodea `/usr/bin/omarchy-*` en 13 sitios, 5 de ellos unidades systemd. Instalar en `/usr/local/bin` rompe el primer arranque y las notificaciones de forma silenciosa y permanente.
6. **`omarchy-pkg-add` aborta toda la transacción con un solo nombre irresoluble**, y muchos flujos (migraciones, primer arranque, update) dependen de él: en ARM hace falta un wrapper tolerante.
7. **El kernel de Arch Linux ARM no deja `vmlinuz` en `/usr/lib/modules/<ver>/`** → `omarchy-update-restart` pide reiniciar para siempre. Wrapper o parche.

---

## 8. Riesgos, límites y lo NO verificado

**Verificado con fuente primaria en esta sesión (26-sep-2026):**

- Estructura y conteos del árbol Omarchy en `quattro` @ `e1614f2b` (clonado), tipos de fichero de `bin/` (461 ficheros, 0 ELF).
- Contenido literal de `install/omarchy-base.packages` (155 líneas), `install/omarchy-other.packages` (75), `pkg/BUILDMODES` de Fydetab, `profiles/omarchy/packages.list` (262 líneas), `profiles/omarchy/image.conf`, `overlay/etc/pacman.conf`, hooks 50/60/65/70/80/90.
- Códigos HTTP de los repos (`pkgs.omarchy.org/{stable}/{x86_64,aarch64}/omarchy.db`, `stable-mirror…/{x86_64,aarch64}/core.db`) y **contenido real del `.db` aarch64** (descargado y extraído: 22 paquetes, ninguno del escritorio) y del x86_64 (248 paquetes).
- PKGBUILDs de `omacom/omarchy-pkgs` (repo redirige desde `omacom-io`): `arch=`, `depends*`, `source*`, `package()` con ramas `CARCH` de `omarchy` y `omarchy-settings`; ~35 PKGBUILDs individuales consultados.
- `manifest.json` schema, `docs/omarchy-shell.md`, `manual/32-shell-plugins.md`, `shell/plugins/README.md`, `docs/omarchy-shell.md` IPC.
- `registry.json` del marketplace (7,5 MB, 4198 entradas): **cero campos de arquitectura**.
- Documentación y notas de release completas de Fydetab (`prod-omarchy-v0.1.5`, `v0.2.1`, `v0.2.5`), `docs/omarchy-profile-plan.md`, `omarchy-feature-gaps.md`, `omarchy-pkgs-coverage.md`, `OMARCHY-VENDOR.md`, `build-internals.md`.
- Post del foro FydeOS (`/t/topic/43275.json`), README y ARTICULO.md del port UTM, README y esquema de releases del port `riverscn`.

**NO verificado / incógnitas abiertas:**

1. **SM7675 (Xiaomi Pad 7): no hay ni un solo dato.** No existe port de Omarchy, ni kernel mainline equivalente, ni evidencia de soporte del SoC en ALARM. Todo lo del Fydetab es **RK3588S** (Mali G610 + panthor/panfrost); la tablet es **Adreno + drm/msm**. **La GPU, el panel, el táctil y el kernel son trabajo desde cero que este informe no cubre.**
2. **El repo aarch64 de upstream puede cambiar de un día para otro.** Hoy tiene 22 paquetes y no incluye el escritorio; `ggalancs` documenta que hace semanas estaba *vacío* o *solo con `omarchy-keyring`*. **Comprobar antes de invertir en el port** — si upstream publica `omarchy`/`omarchy-settings` en aarch64, el 80 % del trabajo desaparece.
3. **`arch=('x86_64' 'aarch64')` no garantiza build verde.** En `omarchy-settings` el `package()` ramifica por `CARCH`, y el comentario del propio PKGBUILD dice que el árbol `/etc` "no es el mismo en cada arquitectura". No he ejecutado un `makepkg` aarch64: no hay evidencia de build reproducible, solo de receta declarada.
4. **Rendimiento de `emulated` bajo qemu-user**: no medido. Fydetab habla de "lento, resérvalo para paquetes que lo necesiten"; el material de `ggalancs` menciona ~12 min para `ttfx` y ~70 min por build completa. En la Ryzen 3700X el orden de magnitud será similar o peor.
5. **Quickshell en aarch64 con la versión exacta que el shell espera.** ALARM trae 0.3.x release; upstream pinnea `quickshell-git` a un commit. Fydetab advierte: *"si su QML necesita features post-release, hay que construir quickshell-git"*. No verificado si hace falta.
6. **Rotura eventual del índice de ALARM** (el caso `libaquamarine.so=13` vs `14` documentado por `ggalancs`): implica mantener builds propios de `hyprland`/`hyprtoolkit`/`aquamarine` desde las recetas de Arch. No verificado si es un problema crónico o puntual.
7. **El "panel orientation" en tablets.** Hyprland/aquamarine **ignora** la propiedad DRM de orientación del panel (lo que sí honra mutter): hay que fijar `transform` y mapear el táctil al output explícitamente. Confirmado en Fydetab; en la Xiaomi Pad 7 no verificado (probablemente igual o peor).
8. **UX de tablet sin resolver en ningún port.** El propio plan de Fydetab lo marca como "fase abierta": gestos táctiles, rotación vía `iio-sensor-proxy` (Hyprland no tiene handler nativo → hace falta un helper) y **teclado en pantalla** (`voxtype` no funcionó; candidatos `wvkbd`/`squeekboard`, que Omarchy no trae). *"Esa fase decide si el perfil es un acompañante con dock de teclado o una experiencia de tablet completa."*
9. **El marketplace seguirá sin saber de arquitecturas** salvo que alguien parchee `omacom/omarchy-plugin-marketplace`; y clona HEAD mutable, así que ni siquiera es reproducible dentro de la misma arquitectura.
10. **Precios legales/redistribución**: servir desde un repo público los repacks de binarios propietarios (`sublime-text-4`, `visual-studio-code-bin`, `nordvpn-bin`, `once-bin`) implica redistribuir esos blobs. Fydetab lo dejó anotado como decisión pendiente.
11. **`omarchy-other.packages` completo** (75 líneas) no lo he revisado línea a línea para separar "x86 hardware" de "dependencia funcional empaquetada por error"; el header y las primeras 60 líneas sí.

**Riesgo estructural del proyecto:** Omarchy 4 upstream mueve el árbol varias veces al día (último push 26-sep-2026 19:49, y este informe se está escribiendo el 26-sep). El pin `omarchy-settings=${pkgver}` obliga a que un port rebasado mantenga los dos paquetes del mismo commit. Un port a otra tablet tendría que decidir entre rebasar contra `quattro` (trabajo continuo) o congelar un tag (deriva). Los ports existentes han elegido congelar y rebasar a mano.

---

## 9. Plan de acción recomendado (para la tablet)

Orden de ataque, con el mínimo de trabajo nuevo:

1. **Antes de nada: re-check de `pkgs.omarchy.org/stable/aarch64/omarchy.db`.** Si ya trae `omarchy` + `omarchy-settings`, el port se reduce a: kernel del SoC + repo + overlay de hardware.
2. **Clonar `Linux-for-Fydetab-Duo/imagebuild` y borrar el perfil `arch-gnome`.** Reutilizar: `build.sh`, `container/` (los dos Dockerfiles), `pkg/BUILDMODES`, `pkg/build-pkg.sh`, `pkg/sync-published.sh`, `pkgbuilds/` completo (los 24 de Omarchy + `yay`, `tzupdate`…), `profiles/omarchy/hooks/` (50/60/65/70/80/90), `overlay/` entero menos lo específico del RK3588S, y `docs/` como documentación viva del port.
3. **Cambiar exactamente tres cosas**: (a) `pkgbuilds/linux-fydetab*` → PKGBUILD del kernel del SoC en modo `cross`; (b) `profiles/omarchy/firmware/` + `stages/03-image.sh` → cadena de arranque del SoC; (c) `profiles/omarchy/image.conf` (particiones, `KERNEL_PKG`, `KERNEL_IMAGE`, `KERNEL_DTB`).
4. **Aceptar y documentar las carencias ya conocidas**: sin menú de snapshots de Limine, sin factory reset, sin hibernación, sin Plymouth al principio. Con btrfs + `snapper` + helper de rollback por CLI (Fydetab demuestra que se puede).
5. **Construir en `emulated` las 13 herramientas Rust/Go/Qt** y en `noarch` los 16 paquetes de config/fuentes. Nada de esto es nuevo: son los mismos 24 PKGBUILDs.
6. **Arreglar los tres bugs de ARM que ya están caracterizados por terceros** (son los que dan la peor experiencia): wrapper de `omarchy-pkg-add` tolerante, wrapper de `omarchy-update-restart` (`vmlinuz`), sellado de migraciones en primer arranque. Están escritos y probados en `build-omarchy-arm.sh`.
7. **Dejar la UX de tablet para el final, con presupuesto propio.** Es el único bloque que ningún port ha resuelto y no tiene recetas reutilizables.
