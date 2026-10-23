#!/bin/bash
# deploy.sh — gestos de borde T4 (18-oct-2026). Solo instala un servicio de usuario; no toca boot/dtbo/hyprland.
#   check   sintaxis local
#   apply   copia script+unidad, conf (sin pisar uno existente), enable global y arranca para omarchy
#   status  estado + ultimas lineas del journal
#   log     el duenio hace los gestos: para el servicio y lee `--log` en vivo 60 s (acciones en seco)
#   revert  para, desactiva y borra script y unidad (deja el conf)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$HERE/../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}
HOST=${UKE_HOST:-root@192.168.42.129}
S() { timeout "${T:-60}" ssh -i "$KEY" -o BatchMode=yes "$HOST" "$@"; }
UM='U=$(id -u omarchy); sudo -u omarchy env XDG_RUNTIME_DIR=/run/user/$U'
case "${1:-}" in
check)
	python3 -I -c "import ast;ast.parse(open('$HERE/uke-gestures.py').read())" && bash -n "$0" && echo "CHECK OK" ;;
apply)
	bash "$0" check || exit 1
	tar -C "$HERE" --owner=0 --group=0 --numeric-owner -cf - uke-gestures.py README.md | \
		S "install -d -m755 /usr/local/share/uke/gestures && tar -x -C /usr/local/share/uke/gestures && chmod 755 /usr/local/share/uke/gestures/uke-gestures.py"
	tar -C "$HERE/root" --owner=0 --group=0 --numeric-owner -cf - . | S "tar -x -C /"
	cat "$HERE/uke-gestures.conf" | S 'f=/home/omarchy/.config/uke-gestures.conf; if [ -e $f ]; then cat >/dev/null; echo "conf existente, no se pisa"; else cat >$f && chown omarchy:omarchy $f && echo "conf instalado"; fi'
	S "systemctl --global enable uke-gestures.service; $UM systemctl --user daemon-reload; $UM systemctl --user restart uke-gestures.service; sleep 2; $UM systemctl --user is-active uke-gestures.service" ;;
status)
	S "$UM systemctl --user status uke-gestures.service --no-pager | head -8; $UM journalctl --user -u uke-gestures -n 8 --no-pager -o cat 2>&1 | tail -8" ;;
log)
	S "$UM systemctl --user stop uke-gestures.service; $UM timeout ${T:-60} /usr/bin/python3 -I /usr/local/share/uke/gestures/uke-gestures.py --log; $UM systemctl --user start uke-gestures.service" ;;
revert)
	S "systemctl --global disable uke-gestures.service; $UM systemctl --user stop uke-gestures.service; rm -rf /etc/systemd/user/uke-gestures.service /usr/local/share/uke/gestures; $UM systemctl --user daemon-reload; echo revertido" ;;
*) echo "uso: $0 check|apply|status|log|revert"; exit 2 ;;
esac
