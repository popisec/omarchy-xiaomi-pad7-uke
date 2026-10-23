#!/usr/bin/env bash
# deploy.sh — boton «Escanear QR» en el panel de Wi-Fi de Omarchy + perfiles Wi-Fi con clave del sistema (ver README.md).
#   ./deploy.sh check    solo lectura: paquetes, plugin, unit, perfiles (SIN claves)
#   ./deploy.sh pkgs     baja zbar+deps del mirror ALARM aarch64 (PC), scp y `pacman -U --needed` (solo si faltan)
#   ./deploy.sh apply    instala uke-wifi-qr, normalizador+path unit y el plugin usuario uke.network (clon parcheado de omarchy.network)
#   ./deploy.sh test     QR FICTICIO «uke-qr-test»: lo decodifica y crea el perfil via uke-wifi-qr, verifica psk-flags=0 y lo BORRA
#   ./deploy.sh revert   quita plugin, units y scripts y restaura shell.json (los paquetes zbar se quedan)
set -Eeuo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
R=$(cd "$HERE/../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}
HOST=${UKE_HOST:-192.168.42.129}
SSH=(ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 root@"$HOST")
SCP=(scp -q -i "$KEY" -o BatchMode=yes)
PLUG=/home/omarchy/.config/omarchy/plugins/uke.network
SJ=/home/omarchy/.config/omarchy/shell.json
SJBAK=/home/omarchy/.config/omarchy/shell.json.bak-wifiqr-20261019
MIRROR=http://de.mirror.archlinuxarm.org/aarch64/extra
PKGS=(liblqr-0.4.3-1 libraqm-0.11.0-1 graphicsmagick-1.3.49-2 imagemagick-7.1.2.34-1 zbar-0.23.95-1)
# ejecutar como omarchy dentro de su user manager (misma situacion que el shell) con el entorno del compositor
USERRUN='systemd-run --user --machine=omarchy@.host --pipe --wait -q --setenv=XDG_RUNTIME_DIR=/run/user/1001 --setenv=OMARCHY_PATH=/usr/share/omarchy'

case "${1:-}" in
check)
	"${SSH[@]}" 'ip -4 -o addr show dev usb0 | cut -d" " -f2,7; pacman -Q zbar grim slurp 2>&1; ls -la '"$PLUG"' 2>&1 | head -4
	systemctl is-enabled uke-wifi-normalize.path 2>&1; ls -l /usr/local/bin/uke-wifi-qr 2>&1
	for f in /etc/NetworkManager/system-connections/*; do echo "$f $(stat -c "%U %a" "$f") psk-flags=$(sed -n "s/^psk-flags=//p" "$f" | head -1) psk=$(grep -q "^psk=" "$f" && echo presente || echo ausente)"; done' ;;
pkgs)
	"${SSH[@]}" 'pacman -Q zbar >/dev/null 2>&1' && { echo "zbar ya instalado"; exit 0; }
	d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
	for p in "${PKGS[@]}"; do for e in "" ".sig"; do curl -fsS -o "$d/$p-aarch64.pkg.tar.xz$e" "$MIRROR/$p-aarch64.pkg.tar.xz$e"; done; done
	"${SSH[@]}" 'rm -rf /root/wifi-qr-pkgs; mkdir -p /root/wifi-qr-pkgs'
	"${SCP[@]}" "$d"/* root@"$HOST":/root/wifi-qr-pkgs/
	# dependencias comprobadas antes: solo estas 5 son nuevas, el resto ya esta instalado; --needed no actualiza nada mas
	"${SSH[@]}" 'cd /root/wifi-qr-pkgs && pacman -U --noconfirm --needed '"$(printf '%s-aarch64.pkg.tar.xz ' "${PKGS[@]}")" ;;
apply)
	"${SSH[@]}" 'ip -4 -o addr show dev usb0 | grep -q 192.168.42.129' || { echo "usb0 no esta" >&2; exit 1; }
	"${SSH[@]}" 'command -v zbarimg grim slurp >/dev/null' || { echo "faltan zbarimg/grim/slurp: ./deploy.sh pkgs" >&2; exit 1; }
	tar -C "$HERE/root" --owner=0 --group=0 -cf - . | "${SSH[@]}" 'tar -C / -xmf - && chmod 755 /usr/local/bin/uke-wifi-qr /usr/local/sbin/uke-wifi-normalize /usr/local/lib/uke-wifi-qr/camera-hook && systemctl daemon-reload && systemctl enable --now uke-wifi-normalize.path && systemctl start uke-wifi-normalize.service'
	"${SCP[@]}" "$HERE/patch-panel.py" root@"$HOST":/root/uke-wifiqr-patch-panel.py
	"${SSH[@]}" 'set -e
	[ -f '"$SJBAK"' ] || cp -a '"$SJ"' '"$SJBAK"'
	rm -rf '"$PLUG"'; mkdir -p '"$PLUG"'
	cp -aL /usr/share/omarchy/shell/plugins/panels/network/. '"$PLUG"'/
	python3 -I /root/uke-wifiqr-patch-panel.py '"$PLUG"'/Panel.qml
	jq ".id=\"uke.network\" | .name=\"Red (uke, con QR)\" | .barWidget.displayName=\"Red (uke, con QR)\" | .omarchy={clonedFrom:\"omarchy.network\"}" /usr/share/omarchy/shell/plugins/panels/network/manifest.json > '"$PLUG"'/manifest.json
	chown -R omarchy:omarchy '"$PLUG"'
	'"$USERRUN"' /bin/sh -c "omarchy-shell shell rescanPlugins; sleep 1; omarchy-plugin-enable uke.network"'
	"${SSH[@]}" 'rm -f /root/uke-wifiqr-patch-panel.py'
	echo "ok. Si el panel no cambia: reiniciar el shell (omarchy-restart-shell) o cerrar y abrir sesion." ;;
test)
	T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
	command -v qrencode >/dev/null || { echo "falta qrencode en el PC" >&2; exit 1; }
	qrencode -s 10 -m 4 -o "$T/t.png" 'WIFI:T:WPA;S:uke-qr-test;P:ficticia clave\;7391;H:false;;'
	"${SCP[@]}" "$T/t.png" root@"$HOST":/root/uke-qr-test.png
	"${SSH[@]}" 'set -e
	chmod 644 /root/uke-qr-test.png; install -m 644 /root/uke-qr-test.png /tmp/uke-qr-test.png
	echo "-- decodificacion (sin clave):"; /usr/local/bin/uke-wifi-qr --check /tmp/uke-qr-test.png
	echo "-- crear perfil como omarchy (en su user manager):"
	'"$USERRUN"' /usr/local/bin/uke-wifi-qr file /tmp/uke-qr-test.png || true
	f=/etc/NetworkManager/system-connections/uke-qr-test.nmconnection
	ls -l "$f"; echo "psk-flags=$(nmcli -g 802-11-wireless-security.psk-flags connection show uke-qr-test)  permisos=[$(nmcli -g connection.permissions connection show uke-qr-test)]  psk-en-fichero=$(grep -q "^psk=" "$f" && echo si || echo NO)"
	nmcli connection delete uke-qr-test; rm -f /tmp/uke-qr-test.png /root/uke-qr-test.png; ls /etc/NetworkManager/system-connections/' ;;
revert)
	"${SSH[@]}" 'set -e
	'"$USERRUN"' /bin/sh -c "omarchy-plugin-disable uke.network" || true
	[ -f '"$SJBAK"' ] && cp -a '"$SJBAK"' '"$SJ"' && chown omarchy:omarchy '"$SJ"'
	rm -rf '"$PLUG"'
	systemctl disable --now uke-wifi-normalize.path 2>/dev/null || true
	rm -f /etc/systemd/system/uke-wifi-normalize.path /etc/systemd/system/uke-wifi-normalize.service /usr/local/sbin/uke-wifi-normalize /usr/local/bin/uke-wifi-qr
	rm -rf /usr/local/lib/uke-wifi-qr; systemctl daemon-reload
	'"$USERRUN"' /bin/sh -c "omarchy-shell shell rescanPlugins" || true
	echo "revertido (config /etc/uke/wifi-qr.conf y paquetes zbar se conservan)"' ;;
*) sed -n 2,8p "$0"; exit 1 ;;
esac
