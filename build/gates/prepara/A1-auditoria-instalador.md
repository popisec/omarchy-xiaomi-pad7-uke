# A1 — Auditoría hostil del instalador `install-omarchy-uke.sh` + `P6-omarchy-install.md`

**Fecha:** 30-sep-2026 · **Agente:** A1-OMARCHY · **Modo:** sin tablet (solo host).
**Alcance:** `build/gates/prepara/install-omarchy-uke.sh` (897 líneas) y `P6-omarchy-install.md`.
**Método y evidencia (todo re-verificado HOY, no heredado de P6):**

- Rootfs real: `debugfs -R` (solo lectura) sobre `build/rootfs/arch-rootfs.img` (8 GiB ext4, label `arch-arm`, UUID `e87e257e-…`; 166 entradas en `/var/lib/pacman/local` — coincide con P6 §1.2).
- Repos en vivo: descarga y extracción de `https://pkgs.omarchy.org/edge/aarch64/omarchy.db` (35 629 B, HOY 200), `http://fl.us.mirror.archlinuxarm.org/aarch64/{extra,core,alarm,aur}/…db` (200 HOY) y del keyring `omarchy-keyring-20251027-1-any.pkg.tar.zst` (+`.sig`, 119 B).
- Huella Omarchy re-verificada HOY con `gpg --show-keys`: **40DFB630FF42BCFFB047046CF0134EE680CAC571** — coincide.
- Cierre de dependencias calculado (429 paquetes) resolviendo `%DEPENDS%/%PROVIDES%` contra las tres DBs, e intersección con el overlay sin registrar en la DB.
- **Dry-run del script ejecutado en el PC** (`/var/tmp/a1-audit/dry-run-pc.out`): exit 0; todos los pasos con efecto quedan en no-op real (`dry()`/`ensure_file`); checks de red activos → pkgs.omarchy.org **200** y mirror ALARM **200**.

**Veredicto: NO-GO** tal cual está. 2 bloqueantes (B1, B2). Con esos dos fixes aplicados y los 3 riesgos altos parcheados, GO.

---

## 1. Tabla maestra hallazgos

| # | Hallazgo | Severidad | Fix concreto |
|---|---|---|---|
| B1 | **32 paquetes del cierre de instalación ya están en disco (overlay `bsdtar` sin registrar) → `pacman` aborta con "exists in filesystem"** en PASO 8 y PASO 9. P6 §1.2/§3.2 afirma que "pacman lo adopta": **falso**, pacman no adopta ficheros sin dueño. | **BLOQUEA** | Nuevo PASO 5b (después de `pacman -Sy`, antes de `-Syu`): registrar el overlay con `pacman_do -S --needed --overwrite '\*' <lista de 42>` (los 42 de §2.1; versión idéntica en ALARM hoy). Alternativa mínima: solo los 32 de §2.2. |
| B2 | **Preset mkinitcpio muerto dispara el hook libalpm y mata el script**: `/etc/mkinitcpio.d/linux-aarch64.preset` apunta a `7.1.6-1-aarch64-ARCH` cuyo `/usr/lib/modules` **no existe** (solo hay `7.2.0-rc2-palawan+`). El PASO 7 (upgrade de `mkinitcpio` 41-4→42-1 escribe `/usr/lib/initcpio/**`) y el PASO 8 (instalación de `plymouth`, que también escribe en `/usr/lib/initcpio/`) disparan `90-mkinitcpio-install.hook` → `mkinitcpio` falla. Con `ExitOnHookFailure` (pacman ≥7.1, default `yes`) pacman **sale con código ≠ 0** → `set -e` mata el script con la transacción ya hecha y los pasos 8-11 sin ejecutar. | **BLOQUEA** | En PASO 2 (tras escribir el conf): `rm -f /etc/mkinitcpio.d/linux-aarch64.preset` (nadie regenera initramfs: el kernel viaja en boot.img; es exactamente la misma razón del `IgnorePkg`). No basta `IgnorePkg mkinitcpio`: el hook también salta con `plymouth`. |
| R1 | **Gate de red inoperante**: líneas 199 y 203 usan `[ dry ] \|\| die …`. `[ dry ]` (literal "dry") es **siempre verdadero** → `die` nunca dispara. Sin red, el script sigue y muere luego en `pacman -Sy` con error confuso (tras haber reescrito pacman.conf y keyring; hay backup). | **RIESGO** (medio) | Sustituir por `dry \|\| die "…"` en ambas líneas. |
| R2 | **Symlinks de unidades de usuario colgantes**: `ln -sfn ../../uke-osk.service "${home}/.config/systemd/user/graphical-session.target.wants/…"`. La ruta relativa resuelve a `~/.config/systemd/uke-osk.service`, que **no existe** (las unidades están en `/etc/systemd/user/`). Resultado: `uke-osk`, `uke-osk-autoshow` y `uke-monitor` **nunca arrancan** con la sesión gráfica. | **RIESGO** (alto impacto funcional) | Symlinks absolutos: `ln -sfn /etc/systemd/user/uke-osk.service "${w}/uke-osk.service"` (×3). |
| R3 | **`sb_visible()` llama a un método inexistente**: `busctl --user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 GetVisible` — `GetVisible` no existe; la visibilidad es la **propiedad** `Visible` (verificado: API documentada de squeekboard/OSK0; `SetVisible` sí es método, ese uso es correcto). Efecto: `toggle` siempre muestra (nunca oculta), `status` siempre "oculto", y `uke-osk-autoshow` toma decisiones con estado falso. | **RIESGO** | `sb_visible() { busctl --user get-property sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 Visible 2>/dev/null \| grep -q true; }` |
| R4 | **`sudoers` y el hook `99-uke-restore-repos`**: el rootfs solo trae `root ALL=(ALL:ALL) ALL` y `/etc/sudoers.d/` vacío. El hook (corre dentro de `omarchy-refresh-pacman`) hace `sudo cp …` **no interactivo**: si `omarchy-settings` no añade NOPASSWD para wheel (no verificado en el paquete aarch64), el hook falla silencioso y un `omarchy update` posterior deja el pacman.conf x86 por los suelos. | **RIESGO** | Escribir `/etc/sudoers.d/uke-restaurar-repos`: `omarchy ALL=(root) NOPASSWD: /usr/bin/cp -f /usr/local/share/uke/pacman.conf /etc/pacman.conf, …` (o validar que omarchy-settings lo trae y documentarlo). |
| R5 | **Cache de pacman sin limpieza**: PASO 7 (-Syu: 47 paquetes rancios + `linux-firmware*` ~centenares de MB) + PASO 8/9 (cierre 429 pkgs: **0,50 GiB** descarga, **1,93 GiB** instalado bruto). Libre real: **6,67 GiB** (dumpe2fs: 1 747 309 bloques × 4 KiB) → margen > 4 GiB, pero el cache conserva todo y un segundo intento tras un fallo duplica la descarga. | **RIESGO** (bajo) | Al final del PASO 11: `pacman_do -Sc` o `paccache -rk1` (pacman-contrib ya entra como dep de `omarchy`). |
| C1 | `omarchy-settings` reescribe `/etc/os-release`, `/etc/nsswitch.conf`, `/etc/security/faillock.conf`, `/etc/skel/.bashrc` (en su `.INSTALL`; ya documentado en P6 §6.2-5). Colateral aceptado; revisar que ningún script de F5/P7 dependa de `PRETTY_NAME="Arch Linux ARM"`. | COSMÉTICO | Nada (documentado). |
| C2 | `omarchy` arrastra `sddm` + `xorg-server` + stack Qt6 (~0,4 GiB) que **no se usan** (no greeter). Espacio OK. | COSMÉTICO | Nada (aceptado; no habilitar display-manager). |
| C3 | El gate `pacman -Sp` (PASO 5) valida resolución pero **no** colisiones de ficheros: dio falsa confianza frente a B1. Tras B1 es inofensivo. | COSMÉTICO | Nota en el script. |

---

## 2. Evidencia detallada de los bloqueantes

### 2.1 Overlay sin registrar en la DB (42 paquetes)

DB local de la imagen = **166 entradas** (verificado con debugfs; sin `git`, `perl`, `polkit`, `sudo`, `networkmanager`, `wpa_supplicant`, `iwd`, `busybox`, `chrony`, `iio-sensor-proxy`…). Overlay (`PACKAGES-OVERLAY.txt`, 171 pkgs extraídos con `bsdtar` sin scriptlets) → **42 nombres NO registrados**:

```
abseil-cpp busybox chrony db5.3 duktape fake-hwclock git gtest iio-sensor-proxy libdaemon
libevdev libgudev libmbim libmm-glib libndp libnewt libnm libpgm libqmi libqrtr-glib libsodium
libssc libteam libwacom mobile-broadband-provider-info networkmanager nspr nss pcre pcsclite
perl perl-error perl-mailtools perl-timedate polkit protobuf protobuf-c slang sudo
wpa_supplicant zeromq zlib-ng
```

### 2.2 Los 32 que chocan con el cierre de instalación (abortan PASO 8/9)

Cierre resuelto hoy (429 pkgs) ∩ overlay sin dueño → `pacman: error: failed to commit transaction (conflicting files)`, transacción entera abortada, `set -e` mata el script:

```
abseil-cpp (←hyprtoolkit/re2/webrtc, vía hyprland)  duktape (←libproxy, polkit)
git (←omarchy)          gtest (←abseil-cpp/re2/highway)   libdaemon (←avahi, libteam)
libevdev (←libinput, plymouth)   libgudev (←upower, libwacom, feedbackd)   libmm-glib, libndp,
libnewt, libnm, libteam, slang, mobile-broadband-provider-info, wpa_supplicant (←networkmanager)
libpgm, libsodium, zeromq (←libteam)   nspr, nss (←networkmanager/libnm)   pcre (←slang)
pcsclite (←wpa_supplicant)   perl, perl-error, perl-mailtools, perl-timedate (←omarchy/git)
polkit (←quickshell, upower)   zlib-ng (←git)   sudo (target explícito del PASO 9)
libwacom (←libinput, vía hyprland)
```

Paso afectado: **PASO 8** (`pacman -S --needed omarchy-keyring omarchy-settings omarchy`: polkit/git/perl/NM/duktape/libevdev/libgudev/libwacom/abseil/gtest/libdaemon/nss/nspr/pcre/pcsclite/zeromq/zlib-ng/slang…) y **PASO 9** (`sudo`, y el resto si 8 sobreviviera). Las versiones del overlay coinciden con las actuales de ALARM (polkit 127-3, sudo 1.9.17.p2-6, git 2.55.0-1, perl 5.42.2-2, networkmanager 1.58.1-1), así que el fix de re-registro no arrastra cambios de versión.

---

## 3. Lo que está BIEN (verificado hoy; no repetir trabajo)

| Área | Evidencia |
|---|---|
| Paquetes EXTRA_PKGS: **todos existen** en ALARM aarch64 HOY con las versiones esperadas | hyprland 0.56.2-3, quickshell 0.3.1-1, uwsm 0.27.0-1, squeekboard 1.43.1-5, xdg-desktop-portal-hyprland 1.4.1-2, glmark2 2023.01-2, vulkan-freedreno 1:26.2.3-1, mesa 1:26.2.3-1, mesa-utils 9.0.0-7, wayland-utils 1.3.0-1, foot 1.28.0-2, xdg-terminal-exec 0.14.3-2, wtype 0.4-2, pamixer 1.6-3, brightnessctl 0.5.1-3, upower 1.91.4-1, wl-clipboard 2.3.0-1, bluez/-utils 5.87-2, grim 1.5.0-2, slurp 1.5.0-2, wlr-randr 0.5.0-1, strace 7.2-1, htop 3.5.3-1, pipewire 1:1.6.9-1 (+pulse/alsa), wireplumber 0.5.17-2, gnome-keyring 50.0-1, noto-fonts 1:2026.09.01-1, noto-fonts-emoji 2.051-1, ttf-dejavu 2.37+18-8, vulkan-tools 1.4.357.0-1 |
| `[omarchy]` edge/aarch64 HOY | `omarchy-4.0.4-1`, `omarchy-settings-4.0.4-4` (pin 4.0.4 OK), `omarchy-keyring-20251027-1`, `yay-13.0.1-1`, `ttf-jetbrains-mono-nerd-basic-3.5.1-1`; `omarchy.db.sig` sigue sin existir → `DatabaseOptional` correcto; paquetes firmados (ed25519, huella re-verificada) |
| Repos ALARM HOY | `core.db`, `extra.db`, `alarm.db`, `aur.db` todos 200 en fl.us; espejos en `http://` (HTTPS de de./redirector roto, como ya decía P6 §2.1) |
| Keyring pacman | `pacman-key --populate archlinuxarm archlinux` OK: `/usr/share/pacman/keyrings/{archlinux,archlinuxarm}.gpg` presentes en la imagen; `/etc/pacman.d/gnupg` NO existe → `--init` necesario y el script lo hace. Entropía: no-issue con kernel 7.2 (getrandom) |
| `DownloadUser = alpm` | `alpm` uid 970 **ya existe** en `/etc/passwd` de la imagen; pacman ALARM = `7.1.0.r9.g54d9411-2` (idéntico al overlay, no se actualiza). Mismo setup que este PC (DownloadUser activo, cache `root:root 755`) donde funciona → no-bloqueante |
| Kernel | `IgnorePkg = linux-aarch64 linux-aarch64-headers` correcto: DB tiene `linux-aarch64-7.1.6-1` pero su `/usr/lib/modules/7.1.6-1-*` fue borrado; solo existe `7.2.0-rc2-palawan+` (5 `.ko` ath11k/qcom, sin dueño). `uke-kernel-marker`: el dir existe **sin** `vmlinuz` → `pacman -U` sin conflicto; DB sin dueño del dir. Nada del script instala `linux*`/`uboot*` que pise el kernel de boot.img |
| EXT4 gate (P6 §8) | Aborta en PASO 0 con `die` ANTES de tocar nada; `pacman.conf` no tocado aún. Limpio. Umbral `UKE_EXT4_MAX_ERRORS=0` coherente con e2fsck en frío |
| Sesión sin greeter | `sddm` NO se habilita; `getty@tty1` + drop-in autologin (sintaxis `\\u` correcta, `/sbin` symlink OK); `~/.bash_profile` + `uwsm check may-start` → `uwsm start -e -D Hyprland hyprland.desktop`; `hyprland` ALARM instala `hyprland.desktop` y depende de `lua` (config Lua de 0.56 real); `hyprctl eval` correcto para 0.56 |
| Usuario/grupos | `wheel/network/power/audio/input/render/storage/video/rfkill` existen en `/etc/group` (grupo `seat` NO existe → el guard `getent` del script lo salta; correcto: libseat usa logind, `seatd.service` no se habilita — bien) |
| systemd --user | `dbus.socket` en `sockets.target.wants` de user → sesión de usuario con bus; sshd habilitado + `/root/.ssh/authorized_keys` presente (canal de rescate intacto); `systemd-networkd` habilitado con `10-uke-usb.network` (192.168.42.129/24) |
| OSK | `squeekboard` 1.43.1-5 en ALARM (404 solo `wvkbd-deskintl`, correcto en P6 §3.4); `busctl call … SetVisible b` es la API correcta; `jq` entra como dep de `omarchy` (uke-osk-autoshow/monitor-apply/f6-verify lo usan) |
| Guard de Omarchy | `OMARCHY_ALLOW_DIRECT_PACMAN=1` exportado en cada `pacman_do` (re-ejecutable tras instalar el guard); `-Syu` en PASO 7 llega antes del guard (diseño correcto de P6 §6) |
| DRY-RUN | Ejecutado en PC: exit 0, sin writes fuera de mktemp, checks de red activos (200/200 HOY). En PC aborta con `--go` (uname ≠ aarch64) — correcto |
| Espacio | 6,67 GiB libres vs ~1,2 GiB descarga total + ~2,5 GiB crecimiento con cache → margen > 4 GiB (con R5 sobra) |

---

## 4. Método EXACTO de internet por USB (NCM), sin WiFi

La tablet ya trae el gadget (kernel `CONFIG_USB_CONFIGFS_NCM/RNDIS/F_FS`, B §938) y el rootfs trae `10-uke-usb.network` (`Name=usb0 enx* rndis*` → `192.168.42.129/24`, `DNS=192.168.42.1`, `RequiredForOnline=no`). El PC es `192.168.42.1` **sin DHCP** → todo manual:

**En el PC (Arch/EndeavourOS):**
```bash
# 1. Conectar el cable USB-C y localizar la interfaz del gadget (aparece como enp0s20f0u3/enx…)
ip link                                            # anota <IF>, p.ej. enp0s20f0u3
nmcli dev set <IF> managed no                      # para que NetworkManager no la toque
# 2. IP del lado PC (la tablet ya se da su 192.168.42.129 con networkd)
sudo ip addr add 192.168.42.1/24 dev <IF>
sudo ip link set <IF> up
ping -c2 192.168.42.129                            # debe responder
ssh -i ~/proyectos/omarchy-uke/build/rootfs/uke-arch-root root@192.168.42.129
# 3. NAT hacia la LAN/WiFi del PC (<WAN> = la interfaz con internet del PC, p.ej. wlan0)
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -o <WAN> -j MASQUERADE
#    (equivalente nft: sudo nft add table ip nat; sudo nft add chain ip nat post '{ type nat hook postrouting priority 100; }'; \
#     sudo nft add rule ip nat post oifname "<WAN>" masquerade)
```

**En la tablet (sesión SSH):**
```bash
ip route add default via 192.168.42.1 dev usb0     # el .network NO pone gateway a propósito
resolvectl dns usb0 1.1.1.1 9.9.9.9                # el PC no sirve DNS en 192.168.42.1
                                                   # (alternativa: dnsmasq en el PC --listen-address 192.168.42.1)
date                                               # TLS exige reloj sano; si va mal:
date -s '2026-09-30 12:30:00'                      # (o timedatectl set-ntp true una vez haya ruta)
curl -sI https://pkgs.omarchy.org/edge/aarch64/omarchy.db | head -1   # → HTTP/2 200
curl -s -o /dev/null -w '%{http_code}\n' http://fl.us.mirror.archlinuxarm.org/aarch64/core/core.db  # → 200
```

**Plan B (sin NAT, solo el enlace punto a punto):** proxy HTTP para el curl de pacman — en el PC `tinyproxy` con `Listen 192.168.42.1` (puerto 8888) y en la tablet lanzar el instalador con `sudo -E env https_proxy=http://192.168.42.1:8888 http_proxy=http://192.168.42.1:8888 ./install-omarchy-uke.sh --go` (curl hereda las variables; el check de red del PASO 0 también las honra).

---

## 5. Anexo — reverificación repetible (30-sep, ejecutada)

```bash
# repos y keyring (todos los códigos medidos hoy)
curl -s https://pkgs.omarchy.org/edge/aarch64/omarchy.db | zstd -dc | tar t | grep -E '^omarchy(-settings)?-4|^omarchy-keyring'
curl -s http://fl.us.mirror.archlinuxarm.org/aarch64/extra/extra.db | zstd -dc | tar t | grep -E '^(hyprland|quickshell|squeekboard|uwsm|glmark2|vulkan-freedreno)-'
curl -s -o kg.tzst https://pkgs.omarchy.org/edge/aarch64/omarchy-keyring-20251027-1-any.pkg.tar.zst
zstd -dc kg.tzst | tar xO usr/share/pacman/keyrings/omarchy.gpg | gpg --show-keys --with-colons - | awk -F: '/^fpr:/{print $10; exit}'
# estado rootfs (solo lectura)
debugfs -R 'ls -l /var/lib/pacman/local' build/rootfs/arch-rootfs.img
debugfs -R 'cat /etc/mkinitcpio.d/linux-aarch64.preset' build/rootfs/arch-rootfs.img
dumpe2fs -h build/rootfs/arch-rootfs.img | grep -E 'Free blocks|Block size'
```

**Fuentes web usadas:** pacman(8) `DownloadUser` ("the specified user must have permission to access the cache directory") y sandbox alpm ([ostechnix](https://ostechnix.com/pacman-7-0-0-will-now-download-packages-as-a-separate-user/), [pacman man](https://pacman.archlinux.page/pacman.8.html), [Arch BBS](https://bbs.archlinux.org/viewtopic.php?id=299480)); semántica de hooks pacman Pre/Post + `ExitOnHookFailure` ([Arch BBS](https://bbs.archlinux.org/viewtopic.php?id=302408), [ArchWiki pacman/Tips](https://wiki.archlinux.org/title/Pacman/Tips_and_tricks)); API D-Bus de squeekboard (`SetVisible` método / `Visible` propiedad: [Purism developer docs](https://developer.puri.sm), [sway(5)](https://man.freebsd.org/cgi/man.cgi?query=sway)).
