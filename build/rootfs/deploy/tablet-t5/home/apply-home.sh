#!/bin/bash
# Se ejecuta en la tablet como root (por ssh). Toca solo $H (home de omarchy) con copia previa en /root/backup-t5.
set -Eeuo pipefail
H=/home/omarchy; B=/root/backup-t5; A=$H/.local/share/applications; M="# >>> uke-t5"
as() { sudo -u omarchy "$@"; }
mkdir -p "$B/files"
bk() { [ -e "$1" ] || return 0; [ -e "$B/files$1" ] || { mkdir -p "$(dirname "$B/files$1")"; cp -a "$1" "$B/files$1"; }; }
# 1) tamaños: [spacing] moderado (control-height 36)
SH=$H/.config/omarchy/shell.toml; bk "$SH"
if ! grep -q "uke-t5" "$SH"; then
cat >> "$SH" <<'T'

# >>> uke-t5 (18-oct-2026): controles tactiles moderados (por defecto 28). Revertir: borrar este bloque.
[spacing]
control-height = 36
popup-row-height = 36
# <<< uke-t5
T
chown omarchy:omarchy "$SH"; fi
# 2) mimeapps de usuario
MA=$H/.config/mimeapps.list; bk "$MA"
id_() { for f in "$@"; do [ -e /usr/share/applications/$f ] && { echo $f; return; }; done; }
FF=$(id_ firefox.desktop); NA=$(id_ org.gnome.Nautilus.desktop); PA=$(id_ org.gnome.Papers.desktop org.gnome.Evince.desktop)
LO=$(id_ org.gnome.Loupe.desktop); CE=$(id_ io.github.celluloid_player.Celluloid.desktop); TE=$(id_ org.gnome.TextEditor.desktop)
{
echo "[Default Applications]"
[ -n "$NA" ] && echo "inode/directory=$NA"
[ -n "$FF" ] && for t in x-scheme-handler/http x-scheme-handler/https x-scheme-handler/about x-scheme-handler/unknown text/html application/xhtml+xml; do echo "$t=$FF"; done
[ -n "$PA" ] && echo "application/pdf=$PA"
[ -n "$LO" ] && for t in png jpeg gif webp bmp tiff svg+xml; do echo "image/$t=$LO"; done
[ -n "$CE" ] && for t in mp4 x-msvideo x-matroska mpeg ogg webm quicktime 3gpp; do echo "video/$t=$CE"; done
[ -n "$CE" ] && for t in mpeg mp4 flac ogg x-wav x-flac; do echo "audio/$t=$CE"; done
[ -n "$TE" ] && for t in text/plain text/markdown; do echo "$t=$TE"; done
} > "$MA"; chown omarchy:omarchy "$MA"
# 3) ocultar del lanzador lo que no es tactil / no funciona (override de usuario con NoDisplay=true)
mkdir -p "$A"; chown omarchy:omarchy "$A"
for n in bssh bvnc avahi-discover cmake-gui gcr-prompter gcr-viewer kitty kitty-open foot-server footclient vim xgps xgpsspeed uuctl \
  org.freedesktop.Xwayland org.gnupg.pinentry-qt xdg-desktop-portal-gtk org.quickshell sm.puri.Squeekboard org.pulseaudio.pavucontrol \
  nvim htop btop avahi-discover nm-connection-editor mpv imv cups lstopo qv4l2 qvidcap jconsole org.gnome.Settings; do
  src=/usr/share/applications/$n.desktop; [ -e "$src" ] || continue; [ -e "$A/$n.desktop" ] && continue
  { cat "$src"; echo "NoDisplay=true"; echo "# uke-t5"; } > "$A/$n.desktop"; chown omarchy:omarchy "$A/$n.desktop"
done
# webapps de Omarchy: exigen Chromium (no instalado, el dueño eligio Firefox) -> ocultarlos
for f in Basecamp Discord "Disk Usage" Docker "Google Contacts" "Google Maps" "Google Messages" "Google Photos" HEY WhatsApp X YouTube Zoom imv mpv; do
  p="$A/$f.desktop"; [ -e "$p" ] || continue; grep -q "uke-t5" "$p" && continue
  bk "$p"; grep -q "^NoDisplay=true" "$p" || sed -i '0,/^\[Desktop Entry\]/s//[Desktop Entry]\nNoDisplay=true/' "$p"; echo "# uke-t5" >> "$p"
done
# 4) QT_IM_MODULE=fcitx y compañia (fcitx5 no instalado): sombrear el fichero del sistema con uno vacio
E=$H/.config/environment.d; mkdir -p "$E"; chown omarchy:omarchy "$E"
[ -e "$E/10-omarchy-fcitx.conf" ] || { echo "# uke-t5: fcitx5 no esta instalado; el OSK es squeekboard (text-input-v3). Revertir: borrar este fichero." > "$E/10-omarchy-fcitx.conf"; chown omarchy:omarchy "$E/10-omarchy-fcitx.conf"; }
# 5) estilo del drawer
D=$H/.config/nwg-drawer; mkdir -p "$D"; bk "$D/drawer.css"; install -o omarchy -g omarchy -m 644 /root/t5-drawer.css "$D/drawer.css"; chown omarchy:omarchy "$D"
# 6) autostart del drawer residente
AU=$H/.config/hypr/autostart.lua; bk "$AU"
grep -q "uke-t5" "$AU" || cat >> "$AU" <<'L'

-- >>> uke-t5 (18-oct-2026): lanzador tactil residente (nwg-drawer -r); se alterna con /usr/local/bin/uke-drawer-toggle. Revertir con tablet-t5/deploy.sh revert.
o.launch_on_start("/usr/local/bin/uke-drawer-toggle start")
-- <<< uke-t5
L
chown omarchy:omarchy "$AU"
# 7) boton de apps en la barra: plugin propio uke.apps + entrada en shell.json (a la derecha del boton de menu de Omarchy)
PL=$H/.config/omarchy/plugins/uke.apps; mkdir -p "$PL"; cp /root/t5-plugin/manifest.json /root/t5-plugin/BarWidget.qml "$PL/"; chown -R omarchy:omarchy "$PL"
SJ=$H/.config/omarchy/shell.json; bk "$SJ"
python3 - "$SJ" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); left=d["bar"]["layout"]["left"]
if not any(w.get("id")=="uke.apps" for w in left):
    i=[k for k,w in enumerate(left) if w.get("id")=="omarchy.menu"]
    left.insert((i[0]+1) if i else 0, {"id":"uke.apps","powerbarVisibility":"shown"})
    json.dump(d,open(p,"w"),indent=2); print("shell.json: uke.apps anadido")
PY
chown omarchy:omarchy "$SJ"
# 8) gesto: 3 dedos hacia arriba = lanzador (sustituye a pantalla completa; esa sigue en SUPER+F). Los bordes izq/der se evitan: el
#    workspace_swipe_touch nativo de Hyprland (gestures) los usa para cambiar de escritorio [documentado, sin verificar con dedo].
GC=$H/.config/uke-gestures.conf; bk "$GC"
if grep -q '^three_up = ' "$GC" && ! grep -q 'uke-drawer-toggle' "$GC"; then
  sed -i 's#^three_up = .*#three_up = /usr/local/bin/uke-drawer-toggle#' "$GC"
  U=$(id -u omarchy); sudo -u omarchy env XDG_RUNTIME_DIR=/run/user/$U systemctl --user kill -s HUP uke-gestures 2>/dev/null || true
fi
echo "home: ok"
