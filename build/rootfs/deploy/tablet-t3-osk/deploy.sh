#!/usr/bin/env bash
# deploy.sh — T3 teclado en pantalla (squeekboard) en la uke. Uso: deploy.sh [status|apply|revert] [--host H] [--key K]
# apply: pacman -S squeekboard; instala uke-osk-toggle y uke-osk.service (unit de USUARIO, global en /etc/systemd/user);
#        la habilita para 'omarchy'; gsettings (screen-keyboard-enabled, sources es); enmascara omarchy-fcitx5.service.
#        NO toca autostart.lua, bindings.lua, shell.toml ni nada de arranque/boot. No reinicia.
# revert: deshabilita/borra la unidad y el toggle, desenmascara fcitx5, restablece gsettings (no desinstala el paquete).
set -Eeuo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KEY=${UKE_KEY:-$HERE/../../uke-arch-root}; HOST=${UKE_HOST:-192.168.42.129}; CMD=status
while [ $# -gt 0 ]; do case $1 in --host) HOST=$2; shift;; --key) KEY=$2; shift;; *) CMD=$1;; esac; shift; done
S() { ssh -i "$KEY" -o BatchMode=yes root@"$HOST" "$@"; }
# Ejecuta como omarchy con su bus de sesion
O='U=$(id -u omarchy); o(){ sudo -u omarchy env XDG_RUNTIME_DIR=/run/user/$U DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$U/bus WAYLAND_DISPLAY=wayland-1 "$@"; }'
case $CMD in
status) S "$O; pacman -Q squeekboard; o systemctl --user is-enabled uke-osk.service omarchy-fcitx5.service; o systemctl --user is-active uke-osk.service; uke-osk-toggle status; o gsettings get org.gnome.desktop.input-sources sources" || true ;;
apply)
	S 'pacman -S --needed --noconfirm squeekboard'
	tar -C "$HERE/root" -cf - usr etc | S 'tar -C / -xf -; chmod 755 /usr/local/bin/uke-osk-toggle'
	S "$O; o gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled true
	 o gsettings set org.gnome.desktop.input-sources sources \"[('xkb','es')]\"
	 o systemctl --user stop uke-osk-test.service 2>/dev/null || true
	 o systemctl --user daemon-reload
	 o systemctl --user enable uke-osk.service
	 o systemctl --user stop omarchy-fcitx5.service 2>/dev/null || true
	 o systemctl --user mask omarchy-fcitx5.service
	 o systemctl --user restart uke-osk.service; sleep 2; o systemctl --user is-active uke-osk.service" ;;
revert)
	S "$O; o systemctl --user disable --now uke-osk.service || true; o systemctl --user unmask omarchy-fcitx5.service || true
	 o gsettings reset org.gnome.desktop.input-sources sources; o gsettings reset org.gnome.desktop.a11y.applications screen-keyboard-enabled
	 rm -f /etc/systemd/user/uke-osk.service /usr/local/bin/uke-osk-toggle; o systemctl --user daemon-reload" ;;
*) echo "uso: $0 [status|apply|revert]" >&2; exit 2 ;;
esac
