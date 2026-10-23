# Aviso «Setup Wi-Fi» de Omarchy / panel de red — 18-oct-2026 (medido en la tablet)

**Resultado: resuelto.** Panel de WiFi funcional (captura: lista «Known networks» con RED-EJEMPLO-3_5G Connected + «Other networks»
RED-EJEMPLO-3, RED-EJEMPLO-5, RED-EJEMPLO-2; ping, IP, gateway). Evidencia: `uke-session shot` del 18-oct 16:08 (no guardada en el repo).

## Qué espera Omarchy
- `/usr/share/omarchy/shell/plugins/panels/network/Panel.qml:68`: `networkManagerAvailable = Networking.backend === NetworkManager`;
  el panel (toggle, conectar, enterprise vía `nmcli`) depende de él. **iwd no sirve** (y `iwd` ni está instalado; `networkmanager 1.58.1` sí).
- El aviso sale de `/usr/share/omarchy/install/user/first-run/wifi.sh`: `nm-online -x` falla ⇒ notificación «Setup Wi-Fi». Es de primer arranque
  (una sola vez); el estado del panel es lo que importa y lo arregla NM.

## Vía elegida: NetworkManager solo para wlan0 (descartado iwd)
NM conf `conf.d/10-uke-wlan0-only.conf`: `unmanaged-devices=except:interface-name:wlan0`, `dns=systemd-resolved` (no toca `/etc/resolv.conf`),
sin MAC aleatoria (la fija 10-uke-wlan.link). NM usa el wpa_supplicant de siempre con ath11k (sin cambios de driver). Red guardada migrada
desde el PSK hash (keyfile 600 en la tablet). Credencial nunca en repo/chat.

## Pruebas (tablet, 18-oct)
| Prueba | Resultado |
|---|---|
| usb0 antes/durante/después | `192.168.42.129/24` UP siempre; SSH por usb0 no se cortó |
| apply #1 | VERDE en <60 s: NM `100 (connected)`, 192.0.2.15, ping a gw 192.0.2.18 por wlan0, revert automático cancelado |
| revert (probado de verdad) | vuelve a wpa_supplicant+networkd, 192.0.2.12, ping OK, usb0 OK; keyfile y ficheros apartados limpiados |
| apply #2 + reinicio de shell | VERDE; panel lista redes y marca la conectada |
| Suspensión (`rtcwake -m no -s 40` + `systemctl suspend`) | `/run/uke-last-resume` estampado, wlan0 `100 (connected)`, 192.0.2.15, ping gw OK, usb0 OK (el hook no necesitó empujar: NM reasoció solo antes de los 20 s) |
| Seguridad | `systemd-run --on-active=180` armado antes de conmutar (cancelado solo en VERDE; en ROJO el propio script revierte) |

## Límites / pendiente
- **No probado en frío** (reinicio completo). Esperado: `uke-wifi.service` ve que no hay conf de wpa_supplicant ⇒ «AVISO sin conf» exit 0 (la guarda cuenta ok),
  carga ath11k y wlan0; luego `uke-wifi-nm.service` arranca NM. Verificar tras el próximo reinicio: `deploy.sh check`.
  Interruptores `/etc/uke/no-wifi|safe-mode` siguen valiendo.
- `uke-wifi-up.sh --down` solo para wpa_supplicant@; con NM parar antes `systemctl stop uke-wifi-nm`.
- Cambio colateral: `suspension/.../uke-resume-stamp` (fuente del repo) ahora rama por backend; ya desplegado en la tablet. Original en `/var/lib/uke-wifi-omarchy/uke-resume-stamp.orig`.
- La IP de wlan0 pasó de .8 a .9 (nuevo cliente DHCP/identificador); irrelevante para el acceso (usb0).
- Nada de commit; NOTAS-OMARCHY.md y docs/historia/ESTADO-VIVO.md sin tocar (para la sesión principal).

## Anexo (18-oct 17:10, tras reinicio en frío)
- Reinicio en frío OK: wlan0 connected por NM, usb0 intacta. Efecto lateral: `systemd-networkd-wait-online` fallaba por timeout (nada que esperar). Arreglo: drop-in `systemd-networkd-wait-online.service.d/10-uke-usb0.conf` (`--interface=usb0 --timeout=15`), desplegado por `deploy.sh apply`; `restart` => rc=0 y ya no sale en `systemctl --failed`. Solo `archlinux-keyring-wkd-sync` depende de network-online.target. El revert no lo quita (inocuo).
- Siguen failed (no son de esto): fake-hwclock, shadow, uke-bt.
