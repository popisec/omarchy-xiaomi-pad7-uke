#!/bin/bash
# deploy.sh — resto de apps de la uke (22-oct-2026): salida a la tailnet por app y lanzadores para el tacto.
#   apply      /usr/local/bin/uke-tailnet y lanzadores en ~omarchy/.local/share/applications (Exec con uke-tailnet,
#              sin DBusActivatable, para que el entorno llegue a la app)
#   navidrome  (SOLO con el visto bueno del dueño) servicio uke-navidrome-fwd (socat 127.0.0.1:14533 -> PC-PORTATIL:4533)
#              y navidrome.json -> http://127.0.0.1:14533 (copia previa en $BK)
#   navidrome-fork  plugin uke.navidrome (sustituye a backmeupplz.navidrome; sin parche de Omarchy)
#   status | revert
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$HERE/../../../.." && pwd)
S() { timeout 300 ssh -i "$R/build/rootfs/uke-arch-root" -o BatchMode=yes -o ConnectTimeout=8 "${UKE_HOST:-root@uke}" "$@"; }
A=/home/omarchy/.local/share/applications
BK=/root/backup-resto-apps-20261022
APPS="cafe.avery.Delfin info.febvre.Komikku com.github.johnfactotum.Foliate org.gnome.Fractal"
case "${1:-}" in
apply)
	S "install -d $BK; install -m 755 /dev/stdin /usr/local/bin/uke-tailnet" < "$HERE/uke-tailnet"
	for a in $APPS; do
		S "f=/usr/share/applications/$a.desktop; o=$A/$a.desktop; [ -e \$o ] && cp -a \$o $BK/; sed -E -e '/^DBusActivatable=/d' -e 's#^Exec=(/usr/bin/)?#Exec=/usr/local/bin/uke-tailnet #' \$f > \$o && chown omarchy:omarchy \$o && grep -m1 ^Exec \$o"
	done
	S "setpriv --reuid=1001 --regid=1001 --init-groups update-desktop-database $A" ;;
navidrome)
	S "install -m 644 /dev/stdin /etc/systemd/system/uke-navidrome-fwd.service && systemctl daemon-reload && systemctl enable --now uke-navidrome-fwd.service && sleep 1 && curl -s -m 8 -o /dev/null -w 'navidrome por 14533: %{http_code}\n' http://127.0.0.1:14533/ping" < "$HERE/uke-navidrome-fwd.service"
	S "f=/home/omarchy/.config/omarchy/navidrome.json; install -d $BK; [ -e $BK/navidrome.json ] || cp -a \$f $BK/; sed -i 's#\"server\": *\"[^\"]*\"#\"server\": \"http://127.0.0.1:14533\"#' \$f && grep -c 127.0.0.1:14533 \$f" ;;
navidrome-fork)   # plugin uke.navidrome (fork que no necesita el parche serviceFor de Omarchy) en lugar de backmeupplz.navidrome
	PLD=/home/omarchy/.config/omarchy/plugins
	OM='setpriv --reuid=1001 --regid=1001 --init-groups env HOME=/home/omarchy XDG_RUNTIME_DIR=/run/user/1001 OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:/usr/local/bin:/usr/bin'
	S "install -d $BK; cp -a /home/omarchy/.config/omarchy/shell.json $BK/shell.json.pre-uke-navidrome"
	S "rm -rf $PLD/uke.navidrome; install -d -o omarchy -g omarchy $PLD/uke.navidrome"
	tar -C "$HERE/uke.navidrome" --owner=omarchy --group=omarchy -cf - . | S "tar -x -C $PLD/uke.navidrome && sync -f $PLD/uke.navidrome/Panel.qml"
	S "$OM omarchy plugin disable backmeupplz.navidrome 2>&1 | tail -1; $OM omarchy plugin enable uke.navidrome --section right 2>&1 | tail -1" ;;
status)
	S "systemctl is-active uke-navidrome-fwd; ls -la $A | grep -E 'Delfin|Komikku|Foliate|Fractal'; grep server /home/omarchy/.config/omarchy/navidrome.json" ;;
revert)
	S "systemctl disable --now uke-navidrome-fwd.service 2>/dev/null; rm -f /etc/systemd/system/uke-navidrome-fwd.service /usr/local/bin/uke-tailnet; for a in $APPS; do rm -f $A/\$a.desktop; [ -e $BK/\$a.desktop ] && cp -a $BK/\$a.desktop $A/; done; [ -e $BK/navidrome.json ] && cp -a $BK/navidrome.json /home/omarchy/.config/omarchy/navidrome.json; echo revertido" ;;
*) sed -n '2,8p' "$0"; exit 2 ;;
esac
