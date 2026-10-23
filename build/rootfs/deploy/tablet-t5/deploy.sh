#!/usr/bin/env bash
# deploy.sh — T5 lanzador tactil, apps tactiles y tamaños. Uso: deploy.sh [status|install|apply|revert] [--host H] [--key K]
#  install: pacman -S --needed firefox nwg-drawer nautilus papers loupe celluloid gnome-text-editor rnote (solo paquetes; no toca config)
#  apply:   copia previa en /root/backup-t5 (una vez) y escribe: policies+autoconfig de Firefox, mimeapps, [spacing] de shell.toml,
#           drawer.css, autostart del drawer, overrides NoDisplay del lanzador, sombra de 10-omarchy-fcitx.conf, uke-drawer-toggle.
#  revert:  restaura lo copiado y borra lo creado (NO desinstala paquetes). No toca red, bluetooth, audio, boot ni dtbo.
set -Eeuo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KEY=${UKE_KEY:-$HERE/../../uke-arch-root}; HOST=${UKE_HOST:-192.168.42.129}; CMD=status
while [ $# -gt 0 ]; do case $1 in --host) HOST=$2; shift;; --key) KEY=$2; shift;; *) CMD=$1;; esac; shift; done
S() { ssh -i "$KEY" -o BatchMode=yes root@"$HOST" "$@"; }
PKGS="firefox nwg-drawer nautilus papers loupe celluloid gnome-text-editor rnote"
case $CMD in
status) S "pacman -Q $PKGS 2>&1; df -h / | tail -1; xdg-mime query default x-scheme-handler/https 2>/dev/null; ls /root/backup-t5 2>&1 | head -3; pgrep -ax nwg-drawer; grep -c uke-t5 /home/omarchy/.config/omarchy/shell.toml" ;;
install) S "pacman -S --needed --noconfirm $PKGS" ;;
apply)
	tar --owner=0 --group=0 -C "$HERE/root" -cf - etc usr | S 'tar -C / -xf -; chmod 755 /usr/local/bin/uke-drawer-toggle'
	S 'cat > /root/t5-drawer.css' < "$HERE/home/drawer.css"
	S 'mkdir -p /root/t5-plugin'
	tar -C "$HERE/home/plugin-apps" -cf - manifest.json BarWidget.qml | S 'tar -C /root/t5-plugin -xf -'
	S 'bash -s' < "$HERE/home/apply-home.sh" ;;
revert)
	S 'bash -s' < "$HERE/home/revert-home.sh"
	S 'rm -f /etc/firefox/policies/policies.json /usr/lib/firefox/defaults/pref/autoconfig.js /usr/lib/firefox/mozilla.cfg /usr/local/bin/uke-drawer-toggle /root/t5-drawer.css' ;;
*) echo "uso: $0 [status|install|apply|revert]" >&2; exit 2 ;;
esac
