# wifi-qr — boton «Escanear QR» en el panel de Wi-Fi + claves Wi-Fi del sistema (19-oct-2026)

## Que hace
1. **Plugin de usuario `uke.network`** (`~omarchy/.config/omarchy/plugins/uke.network`): copia del panel `omarchy.network`
   (`manifest.omarchy.clonedFrom=omarchy.network`, asi puede seguir invocando speedtest/wifiqr y el IPC `omarchy.network`)
   parcheada por `patch-panel.py` (idempotente, aborta si cambian los anclajes tras una actualizacion de Omarchy) con un
   boton con el icono de QR-scan en la cabecera, junto al interruptor. `/usr/share/omarchy` NO se toca. Sustituye a
   `omarchy.network` en la barra (backup de `shell.json` en `shell.json.bak-wifiqr-20261019`).
2. **`/usr/local/bin/uke-wifi-qr`** (Python stdlib): menu fuzzel «Region de la pantalla / Elegir imagen / Camara».
   - region: `slurp` + `grim` -> `zbarimg` (si no decodifica, reintenta ampliada x2 con ffmpeg).
   - imagen: lista de las 40 imagenes mas recientes de Imagenes/Descargas/Screenshots (o `uke-wifi-qr file RUTA`).
   - camara: hook `/usr/local/lib/uke-wifi-qr/camera-hook`, **desactivado** (`/etc/uke/wifi-qr.conf` `CAMERA=0`; ademas
     exige `/dev/video*` o `cam`). Sin probar: la camara aun no funciona en Linux.
   - Parsea `WIFI:T:WPA|WPA3|WEP|nopass;S:;P:;H:;;` con escapes `\; \: \\ \,` y SSID/clave entre comillas. EAP: rechazado.
   - Crea (o actualiza si ya hay un perfil con ese SSID) el perfil con `nmcli connection add` + `connection edit` por
     **stdin** (la clave no pasa por argv ni /proc), fija `psk-flags 0`, lo verifica y hace `connection up`.
   - Notificaciones solo con el SSID. `uke-wifi-qr --check IMG` decodifica y muestra SSID/tipo sin clave.
3. **`uke-wifi-normalize` + `uke-wifi-normalize.path`**: vigila `/etc/NetworkManager/system-connections`; deja cada perfil Wi-Fi con
   `psk-flags=0`, sin `permissions=` de usuario y fichero root 600. No lee claves; idempotente (no rebota). Arregla el perfil
   existente sin tocar su clave (hoy ya estaba bien: `psk-flags` ausente = 0).

## Paquetes (medido 19-oct)
`zbar` faltaba; `grim 1.5.0-2` y `slurp 1.5.0-2` ya estaban. `zbar 0.23.95-1` depende de `graphicsmagick` e `imagemagick`:
instalados de ALARM `extra` (mirror de.mirror.archlinuxarm.org, con .sig, verificados por pacman) junto a `liblqr` y `libraqm`;
son las 5 unicas nuevas, ninguna actualiza un paquete existente (`pacman -S --print zbar` y comparacion de sonames NEEDED
contra `ldconfig -p` de la tablet: solo faltan plugins opcionales de ImageMagick —openexr, libraw, libultrahdr, libwmf— y los
bindings Qt5 de zbar, no usados). `./deploy.sh pkgs` lo repite. El revert no los desinstala.

## Uso
`./deploy.sh check|pkgs|apply|test|revert`. `test` genera en el PC un QR de la red ficticia `uke-qr-test` (clave inventada),
lo decodifica en la tablet, crea el perfil, comprueba `psk-flags=0` y lo borra.
Tambien: `omarchy-shell omarchy.network scanQr` (IPC) o `uke-wifi-qr region`.

## Limites
- Pulsar una entrada de fuzzel con el dedo no esta probado.
- El boton solo aparece si el backend NetworkManager y wlan0 existen. Si Omarchy actualiza el panel, el clon no recibe los cambios.
