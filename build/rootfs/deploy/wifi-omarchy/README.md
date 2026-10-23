# wifi-omarchy — NetworkManager solo para wlan0 (panel de red de Omarchy)

El panel de red y la píldora de la barra de Omarchy usan el backend **NetworkManager** de Quickshell
(`Networking.backend === NetworkBackendType.NetworkManager`, `plugins/panels/network/Panel.qml:68`); con wpa_supplicant+networkd
salen vacíos/apagados. Este despliegue pone NM **solo** para wlan0 (`unmanaged-devices=except:interface-name:wlan0`);
usb0 sigue siendo de systemd-networkd y NM no la ve.

    ./deploy.sh check     # solo lectura
    ./deploy.sh apply     # instala + migra + verifica; revert automático a 180 s si no queda VERDE
    ./deploy.sh revert    # vuelve a wpa_supplicant + networkd

Tras `apply` hay que reiniciar el shell una vez (`omarchy-restart-shell` como usuario `omarchy`) para que Quickshell detecte NM.

Qué hace en la tablet (`/usr/local/sbin/uke-wifi-omarchy apply`): keyfile NM con el PSK hash leído del conf de wpa_supplicant
(nunca sale de la tablet ni pasa por el repo); aparta `20-uke-wlan.network` y el conf de wpa_supplicant (`*.disabled-by-wifi-omarchy`,
originales en `/var/lib/uke-wifi-omarchy/`); `uke-wifi-nm.service` (After=uke-wifi.service, respeta `/etc/uke/no-wifi|safe-mode`) arranca NM
en cada arranque; el hook `uke-resume-stamp` (fuente en `../suspension`) pasó a ser consciente del backend (nmcli si NM está activo).
Un drop-in de `systemd-networkd-wait-online` lo limita a `--interface=usb0` (si no, falla por timeout al no gestionar networkd ya wlan0).
Si no hay ssid+psk de 64 hex en el conf, aborta: que el dueño meta la clave en el panel.
