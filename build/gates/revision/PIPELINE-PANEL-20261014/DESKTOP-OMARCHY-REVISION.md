# DESKTOP-OMARCHY — revisión userspace/sesión · 14-oct-2026 ~20:45

**Veredicto: el único bloqueo medido es la RAM (1,6 GB por `mem=2048M`, D16→L57).
La cadena de sesión está completa y es aarch64 nativa. NADA se pintó porque el
OOM mató a quickshell (el que dibuja fondo+barra) antes/durante el primer frame.
Puntos 2 y 4 del encargo: BLOQUEADOS — la tablet no está accesible (ver §5).**

## 1. Qué lanza la sesión (medido: pkgs staged + upstream `omacom/omarchy@quattro` + file(1))

- `sddm` (autologin `Session=omarchy`) → `/usr/local/share/wayland-sessions/omarchy.desktop`
  (hecho a mano en la tablet hoy; Exec reportado `uwsm start -g -1 -e -D Hyprland hyprland.desktop`;
  contenido NO verificado — sin USB) → `uwsm` 0.27.0 → `Hyprland` 0.56.2-4.
- `~/.config/hypr/hyprland.lua` (copiado hoy de `/usr/share/omarchy/config`) hace
  `dofile(.../default/hypr/bootstrap.lua)` + `require("default.hypr.omarchy")` (+ overrides
  monitors/input/bindings/looknfeel/autostart del usuario).
- `default/hypr/autostart.lua` (upstream, 912 B) lanza en `hyprland.start`, uno a uno:
  `omarchy-launch-shell` · `omarchy-provision-first-run` · `omarchy-powerprofiles-init` ·
  `omarchy-hyprland-monitor-watch` · `udiskie --automount --no-notify --no-tray` ·
  `sleep 2 && omarchy-hook post-boot` (+ import-environment/dbus-update).
- `omarchy-launch-shell` (upstream, leído entero) = supervisor que ejecuta
  `quickshell -n -p $OMARCHY_PATH/shell` con `systemd-cat -t omarchy-shell` y lo
  relanza (máx 5/min). **Fondo + barra + launcher los dibuja quickshell (QML en
  `/usr/share/omarchy/shell/`) — sin quickshell vivo no hay NADA de Omarchy.**
- NO hay swww/hyprpaper/waybar en la cadena quattro (fondo lo pone el shell;
  `hyprpaper` y `waybar` están instalados pero no autostarteados; `swww` ni existe
  en el stage). Portales (`xdg-desktop-portal-hyprland` 1.4.1-2) son lazy, no pintan.

## 2. Journal de los intentos: NO accesible (evidencia previa citada, no re-medida)

- `ssh root@192.168.42.129` → timeout; `ping` 100% loss; `lsusb` sin gadget (§5).
  Sin journal no puedo confirmar ni desmentir las líneas del encargo (dos intentos
  12:14:36–12:15:59, `wayland-wm@hyprland… oom-kill`): quedan como **reportadas, no verificadas**.
- Lo verificado en repo: #632 (ledger) «sesión ARRANCA (Hyprland+quickshell, ~17 s,
  pico 1,1 GB) y la mata el OOM»; FASE0 (13-oct) greeter+sddm ~230 MB sin OOM;
  NOTAS:793 shell quickshell RSS 197 MB (ref. moarchy/Pixel 3a).

## 3. Binarios/configs: existen y son ARM aarch64 (medido con file(1) sobre el stage)

```
quickshell-0.3.2-3: ELF 64-bit LSB pie, ARM aarch64, /lib/ld-linux-aarch64.so.1
hyprland-0.56.2-4:  ELF 64-bit LSB pie, ARM aarch64, idem
hyprland pkg: usr/share/wayland-sessions/hyprland{,-uwsm}.desktop presentes
omarchy-4.0.4-2: usr/bin/omarchy-launch-shell + /usr/share/omarchy/shell/*.qml presentes
.PKGINFO omarchy: deps = keyring settings hyprland quickshell uwsm sddm xdph wireplumber
  pipewire gnome-keyring gum jq git perl fakeroot pacman-contrib fonts networkmanager
  → TODAS en build/stage-escritorio/ (473 pkgs). Nada que falte, nada x86.
```

## 4. Reproducción en vivo: NO ejecutada (bloqueada, sistema intacto)

- `systemctl restart sddm` **no ejecutado**: sin USB no hay cómo observar ni recuperar.
  Comandos pendientes para la próxima sesión con enlace (baratos, <10 MB):
  `journalctl -b _UID=1000`, `journalctl -b|grep -i oom -B3 -A3`,
  `ps -eo pid,etime,rss,comm --sort=-rss|head -20` a +4/+8/+12 s,
  `cat /run/user/1000/hypr/*/hyprland.log | grep -iE 'monitor|commit|render|master|drm'`.

## 5. Bloqueo de acceso (medido 20:41 CEST)

- `journalctl -k`: `20:22:47 cdc_ncm … renamed from usb0` → `20:37:49 USB disconnect`
  → desde entonces solo `descriptor read error -71` (preludio de boot, sin re-enumerar
  NCM). `lsusb` = 4 hubs + cámara + BT; `/sys/class/net` sin `enp0s20f0u3`.
  **Cable desenchufado o gadget caído; la tablet NO es alcanzable.**

## 6. Conclusión

(a) OOM: picos medidos greeter 230 MB + sesión 1,1 GB en 1,6 GB sin swap → quickshell
muere → sin fondo/barra → la sesión colapsa → vuelve el greeter. El dueño solo pudo
ver el greeter. Orden exacto de víctimas: **no verificado** (requiere journal).
(b) Bloqueos adicionales con 8 GB: NINGUNO estructural. Menores no-bloqueantes:
`udiskie` no está en el stage ni es dependencia (línea de autostart falla en silencio);
`omarchy.desktop` de /usr/local hecho a mano (contenido por verificar, pero la sesión
ARRANCÓ ⇒ funcionalmente OK); `omarchy-provision-first-run` puede querer red (proxy).
Panel 3200×2136 ≈ 27 MB/frame: pesado pero viable con RAM completa.
(c) Bien, no tocar: binarios aarch64, deps cerradas, cadena uwsm→Hyprland→quickshell,
greeter con DRM+modeset+freedreno (FASE0), panel con commit de vídeo (L52), backlight vivo.
**Siguiente: L56 (luz) → L57 (RAM) → reintentar sesión y leer el journal entonces.**
