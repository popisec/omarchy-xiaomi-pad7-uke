# P6 — Preparación de la instalación de Omarchy en el rootfs Arch de la uke

**Fecha:** 29-sep-2026 (madrugada, sin tablet) · **Autor:** agente P6-OMARCHY
**Objetivo:** dejar escrito y verificado todo lo necesario para instalar Omarchy 4 sobre el rootfs
Arch Linux ARM que ya vive en la tablet, incluida la sesión Hyprland + Quickshell y el teclado en
pantalla. Nada se ejecuta en la tablet hoy: se entrega esta memoria y `install-omarchy-uke.sh`.
**Restricciones cumplidas:** sin adb/fastboot/ssh/ttyACM0; inspección del rootfs SOLO LECTURA con
`debugfs -R` sobre `build/rootfs/arch-rootfs.img`; escritura únicamente bajo
`build/gates/prepara/`; sin `git commit`.
**Prerrequisito operativo:** `e2fsck` en frío sobre `userdata` (el ext4 está podrido, ESTADO-VIVO).
El instalador se niega a arrancar si el disco declara errores EXT4 (ver §8).

Fuentes primarias: `docs/informes/A-port-omarchy-aarch64.md`, `docs/informes/C-hyprland-quickshell-aarch64.md`,
`docs/informes/D-capa-tablet-fallback.md`, `docs/informes/E-paquetes-aarch64-soc.md`, `F-plan-por-fases.md` §F5/§F6,
`build/rootfs/INFORME-A2.md`, `build/rootfs/PACKAGES-OVERLAY.txt`, `build/rootfs/v1-write-arch.sh`,
docs/historia/ESTADO-VIVO.md, y verificación en vivo de repos/paquetes el 29-sep-2026 (cada URL con su código
HTTP y, donde aplica, huella de clave).

---

## 1. Estado actual del rootfs (evidencia debugfs, 29-sep-2026)

### 1.1 Qué imagen es y qué se escribió en la tablet

| Artefacto | Dato medido |
|---|---|
| `build/rootfs/arch-rootfs.img` | 8 589 934 592 B (8 GiB), ext4, UUID `e87e257e-a4bd-45ca-a494-c0a4e15c48c8`, label `arch-arm`; sha256 actual `6d7b3fb8254c3229f2e131d3597c7d791965640fc4673b2e147933760b86624d` |
| `build/rootfs/arch-rootfs.img.gz` | 403 133 197 B; sha256 `bca709a275c1c23c0b7bed3789e63be1ab04f19b0401b5ec3cc5f53edca5e112` — **es el artefacto que se sirvió y escribió** (el `v1-write-arch.sh` asevera ese sha antes del `dd`) |
| Diferencia img vs gz | El `.img` local tiene un retoque del 27-sep 12:26 (`/etc/systemd/system/sshd.service.d/10-runsshd.conf`, que solo añade `RuntimeDirectory=sshd`) que el `.gz` no lleva. Irrelevante para esta fase |

El rootfs de la tablet, por tanto, es el del `.gz` (sha `bca709…`). Todo lo de abajo está medido
sobre el `.img`, que salvo el drop-in de sshd es byte a byte la misma imagen.

### 1.2 Paquetes: base ALARM + overlay sin registrar (DB rancia, documentado)

- `/var/lib/pacman/local` tiene **166 entradas** (base ALARM del tarball `ArchLinuxARM-aarch64-latest.tar.gz`).
  Los paquetes del overlay se extrajeron con `bsdtar` (sin scriptlets y **sin registrarse en la DB**),
  así que la DB es **rancia a propósito**: dice `systemd-261.2-1`, `openssh-10.4p1-3`,
  `mkinitcpio-41-4`, `linux-aarch64-7.1.6-1`, mientras en disco hay versiones más nuevas de 47 de ellos
  (INFORME-A2 §(b) y §(d)).
- El overlay (171 paquetes, 173 líneas con cabecera, de `PACKAGES-OVERLAY.txt`) **sí está en disco**.
  Comprobado con `debugfs stat` (solo lectura):
  - `usr/bin/nmcli` (1 168 824 B), `usr/bin/git` (4 865 040 B), `usr/bin/sudo` (335 056 B),
    `usr/bin/NetworkManager`, `usr/bin/chronyd`, `usr/bin/wpa_supplicant`, `usr/bin/busybox`,
    `usr/lib/iio-sensor-proxy`, `usr/lib/polkit-1/`, `usr/bin/e2fsck`.
  - `sudoers`: solo `root ALL=(ALL:ALL) ALL`; `/etc/sudoers.d/` **vacío**.
- `qemu-aarch64 -L staging` smoke test de A2: `bash 5.3.20`, `systemctl 262`, `sshd -T` rc=0.

### 1.3 Lo que NO hay (esto es lo que instala P6)

Ninguno de estos existe ni en la DB ni en disco (búsqueda por nombre exacto en la lista de 166 y por
fichero):

```
hyprland  quickshell  wayland  wayland-protocols  mesa  seatd  sddm  greetd  uwsm
xdg-desktop-portal-hyprland  pipewire  wireplumber  qt6-wayland
qt6-declarative  foot  kitty  alacritty  kmscube  wayland-utils  mesa-utils  noto-fonts
ttf-dejavu  ttf-jetbrains-mono-nerd-basic  vulkan-freedreno  squeekboard
```
Además:
- **No existe `/etc/pacman.d/gnupg`** (`debugfs stat` → *File not found*): el keyring de pacman
  **nunca se inicializó**. Hay que hacer `pacman-key --init` + `--populate archlinuxarm archlinux`
  antes de cualquier instalación firmada. Los ficheros de claves sí están
  (`/usr/share/pacman/keyrings/archlinuxarm.gpg`, 3 098 B).
- Polkit **sí está en disco** por el overlay (`/usr/lib/polkit-1/polkitd` 0755, `/usr/bin/pkexec`
  04755, `polkit-127-3` en `PACKAGES-OVERLAY.txt`) pero **sin registrar en la DB**; `quickshell`
  lo declara como dependencia, así que pacman lo adoptará al instalar.
- **No hay `/etc/pacman.d/hooks`** ni `/usr/share/wayland-sessions/`.
- `locale.gen` existe (10 121 B) pero todo comentado; `locale.conf` = `LANG=C.UTF-8`.
- `/etc/hostname` = `uke-arch`. `/etc/fstab` monta `/` por `/dev/disk/by-partlabel/userdata` (ext4).
- Usuarios: `root` y `alarm` (uid 1000). **No hay usuario `omarchy`**.
- Módulos del kernel propio: `/usr/lib/modules/7.2.0-rc2-palawan+/{extra/{ath11k,ath11k_ahb,ath11k_pci,qcom_battmgr,qcom_pd_mapper}.ko}` (5 `.ko`, sin dueño en la DB).

### 1.4 pacman.conf actual (literal, debugfs)

```
Architecture = aarch64
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional
ParallelDownloads = 5
[core]  Include = /etc/pacman.d/mirrorlist
[extra] Include = /etc/pacman.d/mirrorlist
[alarm] Include = /etc/pacman.d/mirrorlist
[aur]   Include = /etc/pacman.d/mirrorlist
```
Mirrorlist actual (5 servidores, `http://`):
`fl.us`, `nj.us`, `ca.us`, `de.mirror.archlinuxarm.org` y el redirector `mirror.archlinuxarm.org`.

### 1.5 Servicios habilitados (debugfs)

`multi-user.target.wants`: `sshd.service`, `systemd-networkd.service` (+ `remote-fs.target`).
`sysinit.target.wants`: `fake-hwclock.service`, `systemd-resolved`, `systemd-timesyncd`,
`systemd-network-generator`. `timers.target.wants`: `fake-hwclock-save.timer`.
**NetworkManager está instalado en disco pero deshabilitado a propósito** (F5: nada debe tocar
`usb0` con la IP estática del init). Este diseño se mantiene: P6 no lo habilita.

---

## 2. Plan de repos (URLs verificadas el 29-sep-2026)

### 2.1 Comprobaciones con código HTTP real

| Recurso | Resultado |
|---|---|
| `https://pkgs.omarchy.org/edge/aarch64/omarchy.db` | **200**, 35 362 B |
| `https://pkgs.omarchy.org/edge/aarch64/omarchy.files` | **200**, 1 293 433 B |
| `https://pkgs.omarchy.org/edge/aarch64/omarchy.db.sig` | **404** → el índice NO está firmado |
| `https://pkgs.omarchy.org/edge/aarch64/omarchy-4.0.4-1-aarch64.pkg.tar.zst` | **200**, 120 291 356 B |
| `…/omarchy-4.0.4-1-aarch64.pkg.tar.zst.sig` | **200**, 119 B (firma ed25519 real) |
| `https://pkgs.omarchy.org/edge/aarch64/omarchy-keyring-20251027-1-any.pkg.tar.zst` | **200**, 6 918 B (+ `.sig` 200) |
| `https://pkgs.omarchy.org/stable/aarch64/omarchy.db` | 200 pero **sin `omarchy` ni `omarchy-settings`** (solo periféricos) → **usar `edge`** |
| `http://fl.us.mirror.archlinuxarm.org/aarch64/core/core.db` | 200, 256 608 B |
| `http://de.mirror.archlinuxarm.org/aarch64/core/core.db` | 200 |
| `http://mirror.archlinuxarm.org/aarch64/core/core.db` | 302 (redirector; correcto para pacman, que sigue redirecciones) |
| HTTPS en `de.` y redirector | **falla certificado** (`no alternative certificate subject name`) → el mirrorlist va en `http://` como el actual |

Contenido del índice `edge/aarch64` (**159 paquetes**, descargado y extraído): `omarchy-4.0.4-1`,
`omarchy-settings-4.0.4-4` (satisface el pin `omarchy-settings=4.0.4`), `omarchy-keyring-20251027-1`,
`hyprland-0.56.2-4`, `aquamarine-0.15.1-1.1`, `hyprtoolkit-0.5.4-5.1`, `quickshell-git-0.3.0.r20.g28771c7-4`,
`hyprland-guiutils-0.2.2-3`, `owe/owe-lockfeed-0.2.7-1`, `tensaku`, `yay-13.0.1-1`,
`ttf-jetbrains-mono-nerd-basic-3.5.1-1`, etc.

### 2.2 Clave del repo Omarchy (bootstrap verificado)

- `omarchy-keyring` instala `usr/share/pacman/keyrings/omarchy{,.gpg,-trusted,-revoked}` y su `.INSTALL`
  ejecuta `pacman-key --populate omarchy`.
- Clave extraída del paquete y leída con `gpg --show-keys`:
  `ed25519 2025-08-28 · uid "Omarchy <USUARIO@example.invalid>" · huella
  **40DFB630FF42BCFFB047046CF0134EE680CAC571**` — coincide con el emisor de la firma del propio
  `omarchy-keyring` (`xxd` de la firma: `…16210440dfb630ff42bcffb047046cf0134ee680cac571`).
- Como el `.db` no está firmado, el `[omarchy]` no puede exigir firma de base de datos:
  `SigLevel = Required DatabaseOptional` (el global ya lo es).

### 2.3 `/etc/pacman.conf` EXACTO a escribir

```ini
# /etc/pacman.conf — uke (Arch Linux ARM + repo Omarchy edge/aarch64)
# Escrito por install-omarchy-uke.sh. Backup del original en /var/backups/uke/<fecha>/.
[options]
HoldPkg     = pacman glibc
Architecture = aarch64
CheckSpace
ParallelDownloads = 5
DownloadUser = alpm

SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

# uke: el kernel se entrega por boot.img (7.2.0-rc2-palawan+), NO por paquete.
# Ignorarlo evita que un -Syu traiga linux-aarch64 7.2.8 y dispare mkinitcpio -P
# (presets sin /boot/Image en esta imagen y drop-in de Omarchy con hook plymouth).
IgnorePkg = linux-aarch64 linux-aarch64-headers

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[alarm]
Include = /etc/pacman.d/mirrorlist

[aur]
Include = /etc/pacman.d/mirrorlist

# Omarchy edge/aarch64 (los paquetes del escritorio SOLO existen en edge, no en stable).
# Va el ULTIMO a proposito: con nombres duplicados (hyprland, hyprland-guiutils,
# hyprtoolkit, aquamarine, quickshell-git vs quickshell) gana ALARM, que es el
# stack verificado en C §4 (hyprland 0.56.2-3 + quickshell 0.3.1-1).
# El .db no tiene .sig (404) -> DatabaseOptional; los paquetes SI van firmados.
[omarchy]
SigLevel = Required DatabaseOptional
Server = https://pkgs.omarchy.org/edge/$arch
```

### 2.4 `/etc/pacman.d/mirrorlist` EXACTO a escribir

```
Server = http://fl.us.mirror.archlinuxarm.org/$arch/$repo
Server = http://nj.us.mirror.archlinuxarm.org/$arch/$repo
Server = http://ca.us.mirror.archlinuxarm.org/$arch/$repo
Server = http://de.mirror.archlinuxarm.org/$arch/$repo
Server = http://mirror.archlinuxarm.org/$arch/$repo
```

### 2.5 Por qué `[omarchy]` el último y no el primero

| Criterio | `[omarchy]` primero (estilo Fydetab `[fyde]`) | `[omarchy]` último (elegido) |
|---|---|---|
| hyprland | 0.56.2-4 del repo (aquamarine 0.15.1-1.1, hyprtoolkit 0.5.4-5.1 del repo) | 0.56.2-3 de ALARM |
| quickshell | `quickshell-git` (conflicts `quickshell`) | `quickshell 0.3.1-1` de ALARM |
| Riesgo SONAME | el repo sombrea `hyprtoolkit` (5 vs el 6.0.0-1 de ALARM), `hyprland-guiutils`, `aquamarine`; mezcla peor documentada (A §8.6, omarchy-mac) | ALARM manda; C §4.4 ya verificó que la cadena `omarchy -> hyprland/quickshell` cierra con estos binarios |
| `ttf-jetbrains-mono-nerd-basic` | repo | repo (no está en ALARM core/extra: se resolverá desde `[omarchy]`) |

La cadena de SONAMEs está hoy alineada (ALARM `aquamarine 0.15.1-1` **PROVIDES
`libaquamarine.so=14-64`**, igual que el repo; `hyprutils 0.14.2-1` provee `libhyprutils.so=13-64`),
pero la opción "último" es la que menor superficie de mezcla tiene y la que C §4.4 validó. Queda
anotado como decisión revisable: si ALARM rompe el índice (caso histórico `libaquamarine.so=13` vs
`14`), el plan B es subir `[omarchy]` al principio y quedarse con su stack Hyprland completo.

---

## 3. Lista pacman EXACTA de la sesión mínima (con estado en el rootfs)

Los paquetes con `(auto)` no hace falta pedirlos: vienen por dependencias. La columna "ya está"
distingue DB (registrado) de **fichero** (overlay sin registrar).

### 3.1 Núcleo del escritorio

| Paquete | Repo | Versión verificada | Ya en rootfs |
|---|---|---|---|
| `omarchy-keyring` | omarchy | 20251027-1 | no |
| `omarchy` | omarchy | 4.0.4-1 | no |
| `omarchy-settings` | omarchy | 4.0.4-4 | no |
| `hyprland` | ALARM extra | 0.56.2-3 | no |
| `quickshell` | ALARM extra | 0.3.1-1 | no |
| `uwsm` | ALARM extra | 0.27.0-1 | no |
| `xdg-desktop-portal-hyprland` | ALARM extra | 1.4.1-2 | no |
| `xdg-desktop-portal` (auto) | ALARM extra | 1.22.1-2 | no |
| `sddm` (auto, **queda deshabilitado**) | ALARM extra | 0.21.0-7 | no |
| `ttf-jetbrains-mono-nerd-basic` | omarchy | 3.5.1-1 | no (no está en ALARM) |
| `gum`, `jq`, `git`, `perl`, `fakeroot`, `pacman-contrib`, `iwd`, `networkmanager` | ALARM | según extra/core | git/NetworkManager/nmcli **en fichero**; resto no |

### 3.2 Audio, portales, entorno

| Paquete | Repo | Nota |
|---|---|---|
| `pipewire`, `wireplumber` | extra | deps de `omarchy` |
| `pipewire-pulse`, `pipewire-alsa` | extra | para apps x11/pulse (Firefox, etc.) |
| `gnome-keyring`, `polkit` | extra | `polkit` ya es dep de `quickshell` |
| `foot` | extra | terminal por defecto del manifiesto Omarchy (`omarchy-base.packages` línea 41) |
| `xdg-terminal-exec` | extra | 0.14.3-2; lo usan los binds `omarchy-launch-terminal` |
| `brightnessctl`, `pamixer`, `upower` | extra | helpers que invoca el shell (C §4.3) |
| `wl-clipboard`, `wtype` | extra | portapapeles del shell; `wtype` para lápiz/dictado (F7) |
| `sudo` | extra | **está en disco (overlay) pero sin registrar**; al instalarlo pacman lo adopta (lo usan `omarchy-refresh-pacman` y el propio usuario) |
| `bluez`, `bluez-utils` | extra | opcional en esta fase (BT es F3); el shell lo pide |
| `libinput`, `aquamarine`, `seatd`, `hyprtoolkit`, `hyprland-guiutils`, `hyprcursor`, `hyprutils`, `hyprlang`, `hyprwire` | extra (auto) | entran por dependencias; `seatd` viene de `aquamarine` |

### 3.3 Fuentes (español + iconos de barra)

`noto-fonts` (1:2026.09.01-1), `ttf-dejavu` (2.37+18), `noto-fonts-emoji` (1:2.051-1),
`ttf-jetbrains-mono-nerd-basic` (repo Omarchy), `noto-fonts-cjk` (opcional). **Ninguna está** en el
rootfs actual; sin `noto-fonts`/`ttf-dejavu` el texto latino sale con fallback feo en Quickshell/GTK.

### 3.4 Teclado en pantalla

| Paquete | Repo | Nota |
|---|---|---|
| `squeekboard` | ALARM extra | 1.43.1-5; **la vía sin compilar**. Deps (`dconf`, `feedbackd`, `gnome-desktop`, `gtk3`) todas en ALARM |
| `wvkbd-deskintl` | AUR | NO está en ALARM (404). Opcional; compilar con `yay` + `base-devel` (`--with-aur`) |

### 3.5 Herramientas de prueba (gate GPU/EGL)

| Paquete | Repo | Nota |
|---|---|---|
| `mesa-utils` | extra | `eglinfo`/`glxinfo` → **el gate de F2** (`freedreno` + GLES 3.2) |
| `wayland-utils` | extra | `wayland-info` |
| `vulkan-tools` + `vulkan-freedreno` | extra | `vkcube`/`vulkaninfo`; Mesa 1:26.2.3-1 |
| `glmark2` | extra | línea base de rendimiento (C §5.1) |
| `grim`, `slurp`, `wlr-randr` | extra | capturas y modos |
| `strace`, `htop` | extra/core | diagnóstico |
| `kmscube` | **AUR** | **404 en ALARM**: no disponible por pacman; alternativa AUR o `modetest` (libdrm) |

### 3.6 Opcionales (flag `--with-aur`)

`yay` (está en `[omarchy]` aarch64, 13.0.1-1) + `base-devel` (para compilar AUR: `wvkbd-deskintl`,
`kmscube`). No entran en la instalación mínima: `base-devel` son ~50 paquetes.

### 3.7 Comando exacto (simulación con `pacman -Sp` antes de instalar)

```bash
# 1) nucleo
pacman -S --needed omarchy-keyring omarchy-settings omarchy
# 2) resto de la sesion + OSK + pruebas (resuelve desde ALARM + [omarchy])
pacman -S --needed hyprland quickshell uwsm xdg-desktop-portal-hyprland \
  pipewire wireplumber pipewire-pulse pipewire-alsa gnome-keyring \
  foot xdg-terminal-exec noto-fonts ttf-dejavu noto-fonts-emoji squeekboard \
  brightnessctl pamixer upower wl-clipboard wtype bluez bluez-utils sudo \
  mesa-utils wayland-utils vulkan-tools vulkan-freedreno glmark2 \
  grim slurp wlr-randr strace htop
```
`ttf-jetbrains-mono-nerd-basic` llega como dependencia de `omarchy` desde `[omarchy]`.

---

## 4. Sesión: cómo se lanza Hyprland (decisión y ficheros)

**Decisión: sin greeter.** No se usa SDDM (aunque se instala como dependencia de `omarchy`):
en una tablet sin teclado físico el greeter es una ratonera (A §3.5, F6 paso 5), y SDDM en ALARM
arrastra un greeter que no aporta nada aquí. El arranque es:

```
systemd (graphical.target)
  └─ getty@tty1 (autologin omarchy)          ← /etc/systemd/system/getty@tty1.service.d/autologin.conf
       └─ login shell (~/.bash_profile)
            └─ exec uwsm start -e -D Hyprland hyprland.desktop   ← /usr/share/wayland-sessions/hyprland.desktop
                 └─ start-hyprland  →  Hyprland 0.56.2 + config Lua
                      └─ (autostart Omarchy) omarchy-launch-shell → quickshell -p /usr/share/omarchy/shell
```

Evidencia de que las piezas existen:
- ALARM `hyprland` instala `/usr/bin/Hyprland`, `/usr/bin/hyprland`, `/usr/bin/start-hyprland`,
  `/usr/share/wayland-sessions/hyprland.desktop` y `hyprland-uwsm.desktop`
  (contenido verificado descargando el paquete).
- `omarchy-settings` instala `/usr/local/share/wayland-sessions/omarchy.desktop`
  (`Exec=uwsm start -g -1 -e -D Hyprland hyprland.desktop`) y `/etc/sddm.conf.d/10-wayland.conf`.
  Ese `.desktop` NO se usa tal cual: encadenaría `uwsm start` dentro de `uwsm start`. Se llama al
  `hyprland.desktop` de Hyprland.
- `uwsm` recomienda en su README exactamente este patrón en el perfil del login shell
  (`if uwsm check may-start && uwsm select; then exec uwsm start default; fi`). Aquí se quita el
  `uwsm select` (menú whiptail: inservible sin teclado) y se fija la sesión.

### 4.1 Ficheros exactos (los escribe el instalador)

`/etc/systemd/system/getty@tty1.service.d/autologin.conf`
```ini
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin omarchy %I $TERM
```

`~omarchy/.bash_profile` (y copia en `/etc/skel/.bash_profile`)
```bash
# uke: arranca la sesion uwsm+Hyprland solo en tty1
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "${XDG_VTNR:-1}" = "1" ] && [ "$(tty)" = "/dev/tty1" ]; then
  if uwsm check may-start; then
    exec uwsm start -e -D Hyprland hyprland.desktop
  fi
fi
```

- SDDM: instalado, **no** `systemctl enable` (no se toca `display-manager.service`).
- SSH en root sigue siendo el canal de rescate (sshd ya habilitado).
- Si el shell muere, la política de Omarchy es relanzarlo (`omarchy-launch-shell` supervisa), pero
  el agente polkit vive DENTRO del shell (C §7.3): tener SSH como TTY de rescate es el plan B.

### 4.2 Config de usuario: `~/.config/hypr/uke.lua` + `uke-perf.lua`

`omarchy-settings` deja en `/etc/skel/.config/hypr/` los ficheros de Omarchy
(`hyprland.lua`, `monitors.lua` con `GDK_SCALE=2` y `scale="auto"`, `input.lua`, …). El instalador
añade al final de `hyprland.lua` (usuario y skel):

```lua
-- uke: overrides de tablet (anadido por install-omarchy-uke.sh)
-- pcall: si algo de uke.lua falla, la sesion de Omarchy sigue arrancando
local _uke_ok, _uke_err = pcall(require, "hypr.uke")
if not _uke_ok then print("[uke] hypr.uke no cargado: " .. tostring(_uke_err)) end
```
El `pcall` es deliberado: C §5.3 documenta que un nombre de opción inventado en la config Lua da
error y tumba la carga; así un fallo de `uke.lua` no se lleva la sesión por delante.

`~/.config/hypr/uke.lua`:
```lua
-- uke: monitor/panel, OSK y overrides de rendimiento
hl.env("GDK_SCALE", "1")

-- Panel o82 2136x3200: 60 Hz, escala entera 1 (144 Hz y scale=2 son inviables en Adreno 732)
hl.monitor({ output = "DSI-1", mode = "2136x3200@60", position = "auto", scale = 1 })

-- Teclado en pantalla: toggle manual (ademas del autoshow)
hl.bind("SUPER + K", hl.dsp.exec_cmd("uke-osk toggle"))
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("uke-monitor-rotate next"))
-- El OSK debe poder dibujarse por encima del lock del shell
hl.layer_rule({ match = { namespace = "squeekboard" }, above_lock = 2 })

-- Rendimiento: en pcall para que un nombre de opcion equivocado no tumbe la sesion
local ok, err = pcall(dofile, (os.getenv("HOME") or "/home/omarchy") .. "/.config/hypr/uke-perf.lua")
if not ok then print("[uke] uke-perf.lua no cargado: " .. tostring(err)) end
```

`~/.config/hypr/uke-perf.lua` (bloque C §5.3, nombres corregidos contra la wiki 0.56):
```lua
hl.config({
  decoration = { blur = { enabled = false }, shadow = { enabled = false }, rounding = 0 },
  animations = { enabled = false },
  misc = { vfr = true, render_unfocused_fps = 5, disable_autoreload = true },
  render = { new_render_scheduling = true, direct_scanout = 0, use_fp16 = 0 },
  cursor  = { no_hardware_cursors = 1, hide_on_touch = true },
})
```
Si el panel no se llama `DSI-1` en este kernel, `hl.monitor` lo ignora sin error; para el caso real
está `uke-monitor-apply` (§4.3), que detecta el output por `hyprctl monitors -j` y aplica
modo/escala/transform en vivo con `hyprctl eval` (Hyprland 0.56 ya no acepta `hyprctl keyword`).

### 4.3 Unidades de usuario

`~/.config/systemd/user/uke-monitor.service` → `ExecStart=/usr/local/bin/uke-monitor-apply boot`
`~/.config/systemd/user/uke-osk.service` → `ExecStart=/usr/local/bin/uke-osk start-hidden` +
`uke-osk-autoshow` (unidades con `WantedBy=graphical-session.target`).
Se habilitan por symlink manual en `~/.config/systemd/user/graphical-session.target.wants/`
porque en el momento de instalar no hay gestor de usuario vivo; `omarchy-provision-first-run` ya
habilitará las unidades de Omarchy en el primer login.

---

## 5. Teclado en pantalla (OSK): qué trae Omarchy y qué se instala

**Omarchy NO trae OSK.** Verificado sobre los paquetes reales (no sobre READMEs):
`grep -riE 'wvkbd|squeek|virtual.?keyboard|text-input' /etc/skel /usr/share/omarchy/default` del
paquete `omarchy-settings-4.0.4-4` solo devuelve una mención a "Omarchy OSD" (on-screen display) y
un comentario sobre `wtype`. Omarchy es teclado-físico-first (A §4, §8.8): ni `squeekboard` ni
`wvkbd` ni `wlogout` tienen nada que ver aquí.

**Elegido: `squeekboard` (ALARM extra 1.43.1-5)** como OSK por defecto, porque:
1. está empaquetado en ALARM aarch64 (cero compilación) — E §2.6, verificado en extra.db;
2. expone control por D-Bus (`sm.puri.OSK0` / `/sm/puri/OSK0`, método `SetVisible(b)`, confirmado en
   `src/dbus.c` de squeekboard y en D §4.2), que es lo que necesita el wrapper;
3. es el fallback que ya contempla `texp-vk` (D §4.1) y el que usa media comunidad Phosh/tablet.

**Alternativa probada en Hyprland: `wvkbd-deskintl`** (D §4.4, `omarchy-surface-touch`): NO está en
ALARM (404), se compila del AUR (0.19.4) o de fuente (v0.20) con `cairo/pango/wayland/libxkbcommon`
(todos en ALARM); se controla por señales (`SIGUSR2` mostrar, `SIGUSR1` ocultar) y arrastra dos
parches conocidos (flicker de `keyboard.c` en v0.19.4 y la tecla de ocultar en v0.20). El wrapper
`uke-osk` lo soporta si se compila después (`--with-aur`).

### 5.1 El "hook de foco de texto": la verdad

**Hyprland 0.56 no implementa `text-input-v3`/`input-method-v2`** (es un compositor de teclado
físico), así que **no existe un evento de "foco en campo de texto"** al que engancharse. Lo que sí
hay, y es lo que implementan los ports reales (D §4.3, §8.3; `omarchy-surface-touch`; `moarchy`):
- mostrar/ocultar bajo demanda desde la barra o un gesto, y
- un **watcher de ventana activa** como heurística.

El instalador implementa el watcher `uke-osk-autoshow`:
```bash
# bucle 0.7 s: hyprctl activewindow -j | jq -r .class
# si class esta en ~/.config/uke/osk-classes (foot,kitty,alacritty,chromium,firefox,...) -> mostrar
# si no -> ocultar (configurable UKE_OSK_PIN=1 para no ocultar nunca)
```
Más un toggle manual por bind (`SUPER+K` en `uke.lua`) y, para el lock, la `layer_rule` con
`above_lock`. Cuando se compila `wvkbd`, el mismo comando cambia de backend por señales.
Limitaciones documentadas: (a) heurística por clase de ventana, no foco real; (b) el OSK en el
greeter no existe (no hay greeter); (c) en el lock de Quickshell el OSK vive fuera del shell: hay que
precargarlo antes de bloquear (patrón `texp-vk start-hidden`, D §8.6).

---

## 6. Orden de instalación SEGURO (interactivo, dry-run primero)

El script `install-omarchy-uke.sh` hace **siempre dry-run salvo `--go`**. No usa `--noconfirm` por
defecto (hay que pedirlo explícitamente); los pasos son:

| # | Paso | Interactivo | Por qué en este orden |
|---|---|---|---|
| 0 | Gates: aarch64, root, EXT4 (§8), espacio libre ≥ 4 GB, **red hacia pkgs.omarchy.org y el mirror ALARM**, respaldo previo | no | Ver §8 y §0 del script (`--skip-net` para omitir la red). Sin esto, no se toca nada |
| 1 | Backup: `/var/backups/uke/<fecha>/{pacman-Qqe.txt,etc.tar.gz,pacman.conf,mirrorlist,dmesg-before.txt}` | no | Poder reconstruir `/etc` sin re-`dd` la imagen |
| 2 | Escribir `pacman.conf` + `mirrorlist` (con backup de ambos) | no | Necesario para que exista `[omarchy]` |
| 3 | `pacman-key --init` + `--populate archlinuxarm archlinux` | no (tarda) | El keyring no existe; sin él falla todo |
| 4 | Bootstrap de la clave Omarchy: descargar keyring, verificar huella `40DFB630…C571`, `pacman-key --add` + `--lsign-key`, `pacman -U` del keyring | sí (pacman) | Circular keyring↔firma resuelto por huella pineada |
| 5 | `pacman -Sy` y **simulación**: `pacman -Sp --print-format '%r/%n-%v' <lista>` | no | Gate de resolución: si un nombre no existe, ABORT antes de tocar el sistema |
| 6 | Comprobar pin: `omarchy` y `omarchy-settings` mismos 4.0.4; `hyprland` y `quickshell` resueltos | no | El pin `omarchy-settings=<pkgver>` es duro |
| 7 | `pacman -Syu` (con `IgnorePkg` del kernel) | **sí** | Actualiza la base rancia ANTES de instalar nada de Omarchy (el guard de `pacman -Syu` aún no existe) |
| 8 | `pacman -S --needed` núcleo: `omarchy-keyring omarchy-settings omarchy` | **sí** | Trae hyprland/quickshell/uwsm/sddm de ALARM por dependencias |
| 9 | `pacman -S --needed` resto de la lista §3.7 (+ `--with-aur` si se pide) | **sí** | |
| 10 | Post: usuario `omarchy`, autologin tty1, `uke.lua`/`uke-perf.lua`, OSK, unidades, hook `pre-refresh-pacman`, wrapper `omarchy-pkg-add`, paquete marcador de kernel | no | §4/§5 |
| 11 | Verificación: `uke-f6-verify` + recuento EXT4 post-install | no | §9 |

Orden clave: **`-Syu` antes de que exista `/usr/share/libalpm/hooks/00-omarchy-update-guard.hook`**
(paquete `omarchy`). Ese hook aborta cualquier `pacman -Syu` posterior salvo
`omarchy update` o `OMARCHY_ALLOW_DIRECT_PACMAN=1` (texto literal del guard, verificado extrayendo el
script del paquete). El script exporta `OMARCHY_ALLOW_DIRECT_PACMAN=1` en su propio `-Syu` para ser
re-ejecutable, y lo documenta.

### 6.1 Rollback (rootfs ext4: no hay btrfs/snapshots)

- **No hay snapshots de Omarchy** (sin UEFI/Limine, A §3.3; idéntico a Fydetab). El rollback se hace
  por partes:
  1. `/etc` completo: `tar czf /var/backups/uke/<fecha>/etc.tar.gz -C / etc` (excluye `pacman.d/gnupg`
     regenerable) + `pacman -Qqe > pacman-Qqe.txt` → permite deshacer configs y ver qué paquetes
     había antes (`pacman -Rns` de lo añadido).
  2. Paquetes: lo instalado por P6 es todo de repos; desinstalable con
     `pacman -Rns omarchy omarchy-settings` + `pacman -Rdd` si algo bloquea. La DB rancia previa se
     conserva en el backup.
  3. Imagen completa: el `.gz` de `build/rootfs/` (sha `bca709…`) sigue siendo el seguro; para
     volver al estado F5 se re-escribe con `v1-write-arch.sh` (desde el shell de rescate, con
     `userdata` SIN montar). El slot A/B del `boot.img` no se toca en P6.
  4. Nada de esto toca `boot`/`dtbo`: un fallo de software en userspace no impide volver por SSH
     (sshd va en el rootfs; si el rootfs queda inarrancable, se vuelve por el `.gz`).

### 6.2 Riesgos del instalador (por orden)

1. **Disco podrido (ext4 con ~880 errores, ESTADO-VIVO).** El mayor: pacman escribe cientos de
   ficheros. Gate §8 + `e2fsck` en frío obligatorio. Si el fs está peor que antes, el propio
   instalador puede empeorarlo; el `.gz` es el seguro.
2. **`edge` es un canal móvil.** `omarchy-4.0.4` casa con `omarchy-settings-4.0.4-4` hoy; mañana el
   pin puede quedar roto (A §8: upstream mueve el árbol varias veces al día). El paso 6 aborta si no
   casa, pero un `-Syu` futuro puede romperlo: Omarchy congela versiones internas.
3. **`[omarchy]` sombrea nombres si se reordena.** Mantenerlo el último.
4. **`pacman -Syu` + guard**: tras instalar `omarchy`, cualquier `-Syu` a pelo aborta. Usar
   `omarchy update` o `OMARCHY_ALLOW_DIRECT_PACMAN=1`.
5. **`omarchy-settings` reescribe `/etc/os-release`** (pasa a `NAME="Omarchy"`, `ID=omarchy`) y
   `/etc/nsswitch.conf`, `/etc/security/faillock.conf`, `/etc/skel/.bashrc` en cada instalación
   (está en su `.INSTALL`, verificado). No es Apple Silicon (`/proc/device-tree/compatible` no lleva
   `apple,`), así que la rama de preservación **no** aplica. Aceptado: es el branding de Omarchy;
   queda anotado por si algún script de F5 comprobaba `PRETTY_NAME="Arch Linux ARM"`.
6. **Wrappers ARM**: el instalador (a) reemplaza `/usr/bin/omarchy-pkg-add` por una versión tolerante
   (guarda `.orig`) — un `-Syu`/actualización de `omarchy` lo restaura y hay que re-aplicar;
   (b) instala un paquete local `uke-kernel-marker-1.0-1-any.pkg.tar.zst` que crea
   `/usr/lib/modules/$(uname -r)/vmlinuz` (fichero marcador, propiedad de ese paquete) para que
   `omarchy-update-restart` no pida reiniciar eternamente (el loop busca `vmlinuz` y `pacman -Qo`;
   ALARM pone `Image`, no `vmlinuz`; F6 §4/lección 7 de A).
7. **Qt y GLES**: si F2 no está cerrada (`eglinfo` = llvmpipe), Hyprland aborta con `RASSERT`
   (C §1). El instalador NO comprueba GLES (se ejecuta sin sesión gráfica); lo hace `uke-f6-verify`
   en el primer login. No mezclar Qt a mano (C §2.4).
8. **bpsace**: `omarchy-settings` arrastra `plymouth` y `hicolor-icon-theme`; el drop-in
   `mkinitcpio.conf.d/omarchy_hooks.conf` referencia el hook `plymouth` y `btrfs-overlayfs`. Como el
   kernel se ignora y nadie corre `mkinitcpio -P`, queda inerte; anotado como mina si algún día se
   regenera el initramfs en la tablet.

---

## 7. Verificación (criterios de F6) — script `uke-f6-verify`

Tras el primer login en la tablet:
```bash
hyprctl version                        # Hyprland 0.56.x
hyprctl monitors -j | jq -r '.[0].name'   # output DSI del panel o82 (no vfb)
pgrep -af 'quickshell|Hyprland'        # shell vivo con shell.qml
eglinfo -B | grep -A2 'OpenGL ES profile' # vendor freedreno, GLES 3.2
journalctl --user -b -t omarchy-shell --no-pager | tail   # 'Configuration Loaded'
busctl --user status sm.puri.OSK0      # OSK presente
pacman -Qi omarchy omarchy-settings hyprland quickshell | grep -E '^(Name|Version)'
```
Sub-criterio: `hyprctl reload` y un cambio de tema no matan el shell.

## 8. Gate EXT4 / e2fsck (obligatorio)

El disco de `userdata` tiene ~880 errores EXT4 (F0 paso 7, ESTADO-VIVO). Reglas del instalador:

```bash
errs=$(dmesg --level=err,warn 2>/dev/null | grep -c 'EXT4-fs error')   # umbral por defecto: 0
[ "$errs" -le "${UKE_EXT4_MAX_ERRORS:-0}" ] || abort "disco podrido: e2fsck en frío primero"
```
Además comprueba que `/` está montado `rw` y que existen `/sbin/init` y el módulo dir del kernel en
curso. **`e2fsck` en frío (tablet apagada / partición desmontada) es PRERREQUISITO operativo** (lo
prepara el agente P7); el instalador no puede hacerlo con el rootfs montado rw. Escape consciente:
`--skip-gate` (lo imprime y sigue), pensado solo para un rootfs ya verificado.

## 9. Anexo — reverificación de URLs (repetible)

```bash
curl -o /dev/null -w '%{http_code}\n' https://pkgs.omarchy.org/edge/aarch64/omarchy.db      # 200
curl -s https://pkgs.omarchy.org/edge/aarch64/omarchy.db | zstd -dc | tar t | grep -E '^omarchy-(settings-)?4'
curl -o /dev/null -w '%{http_code}\n' https://pkgs.omarchy.org/edge/aarch64/omarchy.db.sig  # 404 (esperado)
curl -o /dev/null -w '%{http_code}\n' \
  https://pkgs.omarchy.org/edge/aarch64/omarchy-keyring-20251027-1-any.pkg.tar.zst           # 200
curl -s .../omarchy-keyring-....pkg.tar.zst | zstd -dc | tar xO usr/share/pacman/keyrings/omarchy.gpg \
  | gpg --show-keys --with-fingerprint | grep -A1 pub                                        # 40DFB630FF42BCFFB047046CF0134EE680CAC571
for m in fl.us nj.us ca.us; do curl -o /dev/null -w "$m %{http_code}\n" http://$m.mirror.archlinuxarm.org/aarch64/core/core.db; done
```
