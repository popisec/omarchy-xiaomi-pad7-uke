# DUDAS para el dueño (sesiones nocturnas)

## 22-oct-2026 ~03:50 — sesión gráfica de la tablet congelada (D-Bus) — sesión notas-nextcloud — **RESUELTO 11:37** (reinicio hecho por la sesión principal; uke-lapiz parado mientras se arregla)
**Qué pasa.** A las 03:50:38 el `dbus-broker` del sistema (1,1 GB de RSS, cuota de 512 MB) empezó a expulsar pares por falta
de recursos: `systemd-logind` perdió su nombre en el bus (`org.freedesktop.login1` sale «activatable», `loginctl` ve 0 sesiones,
«Failed to start session scope … Transport endpoint is not connected»), y el libseat de Hyprland («Sending user's quota exceeded»,
«Ping failed») soltó los evdev y **perdió el DRM master**: `hyprland.log` repite `atomic drm request: failed to commit: Permission
denied`. La pantalla queda congelada en el último fotograma; IPC, SSH, Tailscale y `notas-sync` siguen funcionando.
**Causa probable.** `uke-lapiz.service` (`uke_lapiz_ble.py`, PID 1714, en `nanosleep`) dejó de leer la tubería de su
`busctl --json=short monitor org.bluez` (PID 1720, bloqueado en `anon_pipe_write`). Ese monitor dejó de vaciar su cola y fue
llenando la cuota de root en el broker. Lo agravó esta sesión: unos 140 `runuser` (cada uno abre sesión PAM/logind y genera
señales) para hablar con Hyprland en bucle. **Ya los he cambiado por `setpriv`**, que no abre sesión.
**Ampliación 04:20:** también NetworkManager perdió el bus («sup-iface … The connection is closed») y a las 04:06:49 soltó la WiFi
(`deauthenticating … by local choice`); `wlan0` DOWN. **Solo queda el USB** (`root@192.168.42.129`), así que Tailscale y la sync no
tienen red. Lo detectó la sesión resto-apps.
**Recuperación propuesta (no ejecutada; avisada la sesión principal), todo por USB:** `systemctl restart uke-lapiz` → `systemctl restart
systemd-logind` → `systemctl restart wpa_supplicant NetworkManager` → reiniciar la sesión de omarchy (Hyprland). Son servicios, no un reinicio de la tablet, pero pueden cortar a
otras sesiones. **Arreglo de fondo** para quien lleve el lápiz: el bucle del cliente BLE no puede dormir sin leer la tubería de
busctl (o que lea con un hilo dedicado); además, que la unidad lleve `WatchdogSec`.

## 22-oct-2026 — IA de notas (Token Spy): sigue bloqueada
Hace falta del dueño: qué modelo del router `https://SERVIDORhost.tailnet-ejemplo.ts.net:18012/v1` tiene visión, si la imagen puede
salir a un modelo remoto (privacidad) y la clave. Con eso se crea `~/.config/notas/ia.toml` (600) en PC y tablet y se prueba
`notas-ia correct` con una página real. Desde la tablet se llega por el proxy (`https_proxy=http://127.0.0.1:1055`).

## 23-oct-2026 — el táctil esperaba al WiFi: **RESUELTO** (aplicado al repo; falta redesplegar en la tablet)

**Qué pasa.** `uke-touch.service` tiene `After=local-fs.target systemd-udevd.service uke-carga.service
uke-wifi.service`. `uke-wifi.service` es `Type=oneshot` con `TimeoutStartSec=300` (5 min). Con WiFi
lento, o en el estado AMARILLO, **la pantalla táctil no existe hasta 5 minutos**, y
`uke-desktop.service` (que solo ordena tras `uke-wifi`) arranca antes la sesión de Omarchy: se ve el
escritorio sin poder tocarlo.

**Por qué se sospecha que no hace falta.** `uke-touch-up.sh` solo necesita `spidev` y `uinput`
(`CONFIG_SPI_SPIDEV=m`, `CONFIG_INPUT_UINPUT=m`, ambos presentes en el `.config`), y ninguno de los
dos depende del WiFi. La dependencia real es con `uke-carga.service` (el firmware del táctil entra por
SPI sobre el PMIC), y esa ya está.

**Propuesta (UNA línea, requiere redesplegar la unidad en la tablet).** Quitar `uke-wifi.service` del
`After=` de `uke-touch.service`:

```
-After=local-fs.target systemd-udevd.service uke-carga.service uke-wifi.service
+After=local-fs.target systemd-udevd.service uke-carga.service
```

**Lo que se ha hecho.** El dueño lo aprobó: la unidad versionada en
`build/rootfs/deploy/tactil/root/etc/systemd/system/uke-touch.service` ya NO lleva `uke-wifi.service`
en el `After=` (con el comentario del cambio en la propia unidad), y ese despliegue no tiene
manifiesto de sha que regenerar.

**Lo que queda pendiente (operativo, en la tablet).** Redesplegar la unidad cambiada
(`build/rootfs/deploy/tactil/deploy.sh apply`) y comprobar que el táctil aparece antes que el WiFi.

**Efecto colateral a tener en cuenta.** `uke-bootguard` cuenta los fallos de `touch`: si el táctil
empieza a arrancar antes y algo no está listo, el guardián lo omite a los 2 fallos seguidos (y hay
que hacer `uke-bootguard reset touch` para rearmarlo). Ese camino ya está contemplado desde que
`touch` entró en la lista `KNOWN` del guardián (antes no lo estaba, y quedaba apagado en silencio).
