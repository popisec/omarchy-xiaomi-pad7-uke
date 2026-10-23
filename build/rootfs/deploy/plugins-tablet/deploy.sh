#!/bin/bash
# plugins-tablet — arreglos de la shell de Omarchy en la uke y plugins portados del portatil (22-oct-2026).
# Uso: ./deploy.sh check|apply|elsewhen|revert          (UKE_HOST=root@192.168.42.129 para ir por USB)
# Antes de apply/elsewhen/revert: build/rootfs/deploy/turno/uke-turno pedir plugins-tablet "..."
#   apply    : inotify-tools (recarga en caliente de plugins), widgets «On demand» de Powerbar visibles (sin hover
#              no se podian abrir con el dedo), omarchy.weather activado, uke.network regenerado (wifi-qr) y uke.elsewhen.
#   elsewhen : solo regenera e instala uke.elsewhen (necesita el arbol de Omarchy dev del portatil).
#   revert   : vuelve al shell.json y al uke.network de la copia, y quita uke.elsewhen (no desinstala inotify-tools).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)
HOST=${UKE_HOST:-root@uke}
KEY="$ROOT/build/rootfs/uke-arch-root"
SSH=(ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=10 "$HOST")
SCP=(scp -q -i "$KEY" -o BatchMode=yes)
P=/home/omarchy/.config/omarchy/plugins
SJ=/home/omarchy/.config/omarchy/shell.json
BK=/home/omarchy/.local/share/uke-plugins/backup-20261022
OMA_DEV=${OMA_DEV:-$HOME/.local/share/omarchy}
# Ajustes del portatil (no son credenciales): zonas de Elsewhen, en °C y 24 h.
ZONES='Madrid|Europe/Madrid, Delhi|Asia/Kolkata, Tokyo|Asia/Tokyo, Los Angeles|America/Los_Angeles, New York|America/New_York'
# Lo que necesita el entorno de la sesion grafica (setpriv, no runuser: runuser en bucle lleno la cuota de D-Bus).
ASO='aso() { U=$(id -u omarchy); setpriv --reuid=omarchy --regid=omarchy --init-groups env -i LANG=C.UTF-8 HOME=/home/omarchy USER=omarchy OMARCHY_PATH=/usr/share/omarchy PATH=/usr/local/bin:/usr/bin XDG_RUNTIME_DIR=/run/user/$U WAYLAND_DISPLAY=wayland-1 HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/$U/hypr | head -1) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$U/bus "$@"; }'

elsewhen() {
	T=$(mktemp -d); trap 'rm -rf "$T"' RETURN
	python3 -I "$HERE/port-elsewhen.py" "$OMA_DEV/shell/plugins/panels/elsewhen" "$T/uke.elsewhen" --lang=es
	tar -C "$T" --owner=0 --group=0 -cf - uke.elsewhen | "${SSH[@]}" "set -e; $ASO
		rm -rf /tmp/uke-elsewhen.new; mkdir /tmp/uke-elsewhen.new; tar -C /tmp/uke-elsewhen.new -xf -
		rm -rf $P/uke.elsewhen; mv /tmp/uke-elsewhen.new/uke.elsewhen $P/; rmdir /tmp/uke-elsewhen.new
		chown -R omarchy:omarchy $P/uke.elsewhen
		aso omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true; sleep 2
		jq -e '.bar.layout.center[]? | select(.id==\"uke.elsewhen\")' $SJ >/dev/null || aso omarchy plugin enable uke.elsewhen center
		sleep 2
		jq --arg z '$ZONES' '(.bar.layout.center[] | select(.id==\"uke.elsewhen\")) += {zones: \$z, units: \"C\", hour24: true}' $SJ > /tmp/uke-sj.new
		setpriv --reuid=omarchy --regid=omarchy --init-groups cp /tmp/uke-sj.new $SJ; rm -f /tmp/uke-sj.new
		echo 'uke.elsewhen instalado (si un widget fallo antes, la shell cachea el error: omarchy restart shell)'"
}

case "${1:-}" in
check)
	"${SSH[@]}" "$ASO; pacman -Q inotify-tools 2>&1; pgrep -a inotifywait || echo 'sin inotifywait (reinicia la shell)'
		aso omarchy plugin list 2>&1 | grep -E 'uke\.|weather|powerbar|omascale|omaplug|navidrome|omafind|bitwarden'
		aso omarchy-shell powerbar managedStatus 2>/dev/null; echo
		journalctl _PID=\$(pgrep -x quickshell) -o cat | sed -E 's/\x1b\[[0-9;]*m//g' | grep -E 'WARN|ERROR' | grep -v qmlscanner | cut -c1-200 | sort | uniq -c | sort -rn | head" ;;
apply)
	"${SSH[@]}" "set -e; $ASO
		mkdir -p $BK; [ -f $BK/shell.json ] || cp -a $SJ $BK/shell.json; [ -d $BK/uke.network ] || cp -a $P/uke.network $BK/
		chown -R omarchy:omarchy $BK
		pacman -S --needed --noconfirm inotify-tools | tail -1
		for w in omaplug cjkaufman.omascale omarchy.tray; do aso omarchy-shell powerbar setWidget \$w '{\"visibility\":\"shown\"}'; sleep 2; done
		aso omarchy plugin enable omarchy.weather | tail -1"
	# uke.network: copia del panel de red actual + boton QR + alias tolerantes a bar == null (wifi-qr/patch-panel.py)
	"${SCP[@]}" "$ROOT/build/rootfs/deploy/wifi-qr/patch-panel.py" "$HOST":/root/uke-wifiqr-patch-panel.py
	"${SSH[@]}" "set -e; T=/root/uke-network.new; rm -rf \$T; mkdir \$T
		cp -aL /usr/share/omarchy/shell/plugins/panels/network/. \$T/
		python3 -I /root/uke-wifiqr-patch-panel.py \$T/Panel.qml
		jq '.id=\"uke.network\" | .name=\"Red (uke, con QR)\" | .barWidget.displayName=\"Red (uke, con QR)\" | .omarchy={clonedFrom:\"omarchy.network\"}' /usr/share/omarchy/shell/plugins/panels/network/manifest.json > \$T/manifest.json
		chown -R omarchy:omarchy \$T; rm -rf $P/uke.network; mv \$T $P/uke.network; rm -f /root/uke-wifiqr-patch-panel.py"
	elsewhen
	echo "ok. La primera vez hay que reiniciar la shell para que arranque inotifywait: omarchy restart shell" ;;
elsewhen) elsewhen ;;
revert)
	"${SSH[@]}" "set -e; $ASO
		[ -f $BK/shell.json ] && setpriv --reuid=omarchy --regid=omarchy --init-groups cp $BK/shell.json $SJ
		[ -d $BK/uke.network ] && { rm -rf $P/uke.network; cp -a $BK/uke.network $P/; chown -R omarchy:omarchy $P/uke.network; }
		rm -rf $P/uke.elsewhen; aso omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true; echo revertido" ;;
*) sed -n 2,9p "$0"; exit 1 ;;
esac
