#!/bin/bash
# deploy.sh — ESCRITORIO-TACTIL (22-oct-2026): escritorio de Omarchy cómodo con el dedo en la uke.
#   check            sintaxis local (lua con luac si existe, QML con qmllint, C del teclado + pruebas del predictor)
#   hypr             instala ~/.config/hypr/tablet.lua (una app por escritorio, dividir, animaciones) + require; valida
#   hypr-revert      quita el require y tablet.lua (copia en ~/.local/share/uke-escritorio/)
#   gestos           sube touch-mode/uke-gestures.conf (pellizco 3 dedos = dividir, 3 dedos arriba = lanzador) y recarga
#   osk              teclado nuevo (sugerencias, autocorrección, clic): touch-mode/deploy.sh apply con NORELOAD (recarga aparte)
#   launcher         instala el plugin uke.launcher, lo pone en la barra en lugar de uke.apps y para nwg-drawer
#   launcher-revert  vuelve a uke.apps + nwg-drawer residente
#   plugins          limpieza: quita crmne.hyprmoncfg (copia) y desactiva radimsem.omafind
#   plugins-revert   restaura hyprmoncfg y reactiva omafind
#   status           estado de todo
# Necesita el turno: build/rootfs/deploy/turno/uke-turno pedir escritorio-tactil "<qué>".
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$HERE/../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}
HOST=${UKE_HOST:-root@uke}
S() { timeout "${T:-120}" ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 "$HOST" "$@"; }
# órdenes como omarchy dentro de su sesión, por stdin (setpriv: sin sesión PAM ni D-Bus nuevos por llamada)
U() {
	{ cat <<'PRE'
export XDG_RUNTIME_DIR=/run/user/1001 HOME=/home/omarchy USER=omarchy WAYLAND_DISPLAY=wayland-1 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1001/hypr | head -1) LANG=C.UTF-8 OMARCHY_PATH=/usr/share/omarchy
export PATH=/usr/share/omarchy/bin:/usr/local/bin:/usr/bin
cd /home/omarchy
PRE
	cat; } | S 'setpriv --reuid=1001 --regid=1001 --init-groups sh -s'
}
HY=/home/omarchy/.config/hypr
BK=/home/omarchy/.local/share/uke-escritorio
PLD=/home/omarchy/.config/omarchy/plugins
MARK='require("hypr.tablet") -- uke ESCRITORIO-TACTIL (deploy/escritorio-tactil)'

case "${1:-}" in
check)
	command -v luac >/dev/null && { luac -p "$HERE/tablet.lua" || exit 1; }
	bash -n "$0" || exit 1
	bash "$HERE/../touch-mode/deploy.sh" check || exit 1
	cc -std=c11 -O2 -Wall -Wextra -Werror -I"$HERE/../touch-mode/fork" "$HERE/../touch-mode/predict-test.c" -o /tmp/uke-predict-test &&
		/tmp/uke-predict-test "$HERE/../touch-mode/fork/dict/es.txt" | tail -1 | grep -q OK || { echo "predictor FALLA"; exit 1; }
	[ -d "$HERE/uke.launcher" ] && /usr/lib/qt6/bin/qmllint "$HERE"/uke.launcher/*.qml 2>&1 | grep -iE "syntax|expected|cannot begin" && { echo "QML del lanzador con errores"; exit 1; }
	echo "CHECK OK" ;;
hypr)
	S "install -d -o omarchy -g omarchy $BK; cp -a $HY/hyprland.lua $BK/hyprland.lua.\$(date +%Y%m%d-%H%M%S)"
	S "cat > $HY/tablet.lua && chown omarchy:omarchy $HY/tablet.lua" < "$HERE/tablet.lua"
	S "grep -q 'require(\"hypr.tablet\")' $HY/hyprland.lua || sed -i '/^require(\"hypr.autostart\")/a $MARK' $HY/hyprland.lua; grep -n 'hypr.tablet' $HY/hyprland.lua"
	echo 'hyprctl reload >/dev/null; sleep 1; echo "configerrors:"; hyprctl configerrors' | U ;;
hypr-revert)
	S "sed -i '/require(\"hypr.tablet\")/d' $HY/hyprland.lua; [ -f $HY/tablet.lua ] && install -d -o omarchy -g omarchy $BK && mv $HY/tablet.lua $BK/tablet.lua.retirado-\$(date +%Y%m%d-%H%M%S); true"
	echo 'hyprctl reload >/dev/null; sleep 1; hyprctl configerrors' | U ;;
gestos)
	S 'f=/home/omarchy/.config/uke-gestures.conf; cp -a $f /home/omarchy/.local/share/uke-escritorio/uke-gestures.conf.$(date +%Y%m%d-%H%M%S) 2>/dev/null || { install -d -o omarchy -g omarchy /home/omarchy/.local/share/uke-escritorio; cp -a $f /home/omarchy/.local/share/uke-escritorio/; }'
	S "cat > /home/omarchy/.config/uke-gestures.conf; chown omarchy:omarchy /home/omarchy/.config/uke-gestures.conf" < "$HERE/../touch-mode/uke-gestures.conf"
	echo 'systemctl --user kill -s HUP uke-gestures; sleep 1; systemctl --user is-active uke-gestures' | U ;;
osk)
	NORELOAD=1 bash "$HERE/../touch-mode/deploy.sh" apply ;;
launcher)
	[ -d "$HERE/uke.launcher" ] || { echo "falta uke.launcher/"; exit 1; }
	S "rm -rf $PLD/uke.launcher; install -d -o omarchy -g omarchy $PLD/uke.launcher"
	tar -C "$HERE/uke.launcher" --owner=omarchy --group=omarchy -cf - . | S "tar -x -C $PLD/uke.launcher && chown -R omarchy:omarchy $PLD/uke.launcher"
	S "cp -a /home/omarchy/.config/omarchy/shell.json $BK/shell.json.\$(date +%Y%m%d-%H%M%S)"
	cat <<'EOF' | U
omarchy-shell shell rescanPlugins >/dev/null 2>&1; sleep 2
omarchy plugin enable uke.launcher --section left 2>&1 | tail -1
omarchy plugin disable uke.apps 2>&1 | tail -1
sleep 2; omarchy-shell uke.launcher status
EOF
	# nwg-drawer deja de arrancar solo (se comenta su línea de autostart) y se para el residente
	S "sed -i 's|^o.launch_on_start(\"/usr/local/bin/uke-drawer-toggle start\")|-- (ESCRITORIO-TACTIL: sustituido por uke.launcher) &|' $HY/autostart.lua; pkill -x nwg-drawer; grep -n drawer $HY/autostart.lua" ;;
launcher-revert)
	S "sed -i 's|^-- (ESCRITORIO-TACTIL: sustituido por uke.launcher) ||' $HY/autostart.lua"
	cat <<'EOF' | U
omarchy plugin disable uke.launcher 2>&1 | tail -1
omarchy plugin enable uke.apps --section left 2>&1 | tail -1
/usr/local/bin/uke-drawer-toggle start
EOF
	;;
plugins)
	S "install -d -o omarchy -g omarchy $BK/plugins; [ -d $PLD/crmne.hyprmoncfg ] && mv $PLD/crmne.hyprmoncfg $BK/plugins/; ls $BK/plugins"
	echo 'omarchy plugin disable radimsem.omafind 2>&1 | tail -1; omarchy-shell shell rescanPlugins 2>&1 | tail -1' | U ;;
plugins-revert)
	S "[ -d $BK/plugins/crmne.hyprmoncfg ] && mv $BK/plugins/crmne.hyprmoncfg $PLD/; true"
	echo 'omarchy plugin enable radimsem.omafind 2>&1 | tail -1; omarchy-shell shell rescanPlugins 2>&1 | tail -1' | U ;;
status)
	cat <<'EOF' | U
echo "== hypr"; grep -n 'hypr.tablet' ~/.config/hypr/hyprland.lua; hyprctl configerrors
echo "== plugins"; omarchy plugin list | grep -E "uke\.|omarkyy|omafind|hyprmoncfg"
echo "== osk"; omarchy-shell omarkyy.tablet status
echo "== launcher"; omarchy-shell uke.launcher status 2>&1 | tail -1; pgrep -a nwg-drawer
EOF
	;;
*) echo "uso: $0 check|hypr|hypr-revert|gestos|osk|launcher|launcher-revert|plugins|plugins-revert|status"; exit 2 ;;
esac
