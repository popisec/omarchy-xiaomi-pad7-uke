#!/bin/bash
set -Eeuo pipefail
H=/home/omarchy; B=/root/backup-t5/files; A=$H/.local/share/applications
# restaurar originales con copia
( cd "$B" && find . -type f ) 2>/dev/null | while read -r f; do f=${f#.}; cp -a "$B$f" "$f"; done
# quitar lo creado por T5 que no tenia original
for f in "$A"/*.desktop; do [ -e "$f" ] && grep -q "^# uke-t5" "$f" && [ ! -e "$B$f" ] && rm -f "$f"; done
[ -e "$B$H/.config/mimeapps.list" ] || rm -f "$H/.config/mimeapps.list"
rm -f "$H/.config/environment.d/10-omarchy-fcitx.conf"
[ -e "$B$H/.config/nwg-drawer/drawer.css" ] || rm -rf "$H/.config/nwg-drawer"
rm -rf "$H/.config/omarchy/plugins/uke.apps"
pkill -x nwg-drawer || true
U=$(id -u omarchy); sudo -u omarchy env XDG_RUNTIME_DIR=/run/user/$U systemctl --user kill -s HUP uke-gestures 2>/dev/null || true
echo "home revertido"
