#!/bin/bash
# deploy.sh — Touch Mode (teclado flotante ES/US + gestos de 2/3 dedos) en la uke. 18-oct-2026.
#   check     sintaxis local (python, bash)
#   apply     instala gcc/make/pkgconf si faltan, plugin omarkyy.tablet (fork), udev uinput, demonio de gestos v2,
#             conf de gestos, desactiva squeekboard (uke-osk) y recarga el shell
#   status    estado de todo
#   test      pruebas OSK extremo a extremo en la tablet (osk-test.sh)
#   revert-osk  vuelve al teclado previo al rework (OSK-REWORK-20261020)
#   revert    deja el estado previo (squeekboard activo, gestos T4 originales, sin plugin)
#   osk-off | osk-on   solo el cambio de teclado (squeekboard <-> plugin)
#   log       el duenio prueba gestos: para el demonio y lee --log en vivo T segundos (acciones en seco; ACT=1 las ejecuta)
# No toca red, bluetooth, audio, boot ni la config de Hyprland. Copias previas en backup-previo/.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$HERE/../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}
HOST=${UKE_HOST:-root@uke}   # WiFi/Tailscale; por USB: UKE_HOST=root@192.168.42.129
S() { timeout "${T:-120}" ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 "$HOST" "$@"; }
# comandos como omarchy dentro de su sesion (shell de omarchy + Hyprland)
OM='U=$(id -u omarchy); RT=/run/user/$U; HS=$(ls -t $RT/hypr 2>/dev/null | head -1); sudo -u omarchy env XDG_RUNTIME_DIR=$RT HYPRLAND_INSTANCE_SIGNATURE=$HS OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:/usr/local/bin:/usr/bin LANG=C.UTF-8'
PL=/home/omarchy/.config/omarchy/plugins/omarkyy.tablet
GD=$R/build/rootfs/deploy/tablet-t4-gestos

osk_off() {
	S "$OM systemctl --user disable --now uke-osk.service 2>&1 | tail -2; $OM systemctl --user is-active uke-osk.service; $OM busctl --user list 2>/dev/null | grep -c sm.puri.OSK0"
	echo "squeekboard desactivado (revertir: $0 osk-on)"
}
osk_on() {
	S "$OM systemctl --user enable --now uke-osk.service 2>&1 | tail -2; $OM systemctl --user is-active uke-osk.service"
}

case "${1:-}" in
check)
	python3 -I "$HERE/test-gestures.py" >/dev/null || { echo "test-gestures FALLA"; exit 1; }
	python3 -I -c "import ast;ast.parse(open('$HERE/uke-gestures.py').read())" && bash -n "$0" && bash -n "$HERE/osk-test.sh" || exit 1
	# QML: errores que qmllint marca como fatales al cargar (p. ej. metodos con mayuscula inicial rompieron el teclado en la 1a version del rework)
	if command -v /usr/lib/qt6/bin/qmllint >/dev/null; then
		/usr/lib/qt6/bin/qmllint "$HERE/fork/Keyboard.qml" "$HERE/fork/Service.qml" 2>&1 | grep -iE "cannot begin|syntax|expected" && { echo "QML con errores"; exit 1; }
	fi
	echo "CHECK OK" ;;
apply)
	bash "$0" check || exit 1
	S 'command -v cc >/dev/null && command -v make >/dev/null && command -v pkg-config >/dev/null || pacman -S --needed --noconfirm gcc make pkgconf 2>&1 | tail -3'
	# 1) plugin (fork, REWORK OSK 20-oct-2026) -> ~omarchy/.config/omarchy/plugins/omarkyy.tablet
	#    copia previa FUERA del directorio de plugins (si no, el shell la escanearia); se vacia el dir para quitar los helpers viejos
	S "B=/home/omarchy/.local/share/uke-touch-mode/backup-plugin-\$(date +%Y%m%d-%H%M%S); [ -d $PL ] && install -d -o omarchy -g omarchy \$B && cp -a $PL/. \$B/ && echo copia previa en \$B; true"
	S "rm -rf $PL; install -d -o omarchy -g omarchy $PL"
	tar -C "$HERE/fork" --owner=omarchy --group=omarchy -cf - . | S "tar -x -C $PL && chown -R omarchy:omarchy $PL"
	S "$OM sh -c 'cd $PL && sh osk-backend.sh --build' && echo 'osk-daemon compilado'"
	S "rm -f /home/omarchy/.cache/omarchy/tablet/ime-helper /home/omarchy/.cache/omarchy/tablet/input-helper"
	# 2) permisos de uinput (el demonio inyecta clic derecho y teclas de 'atras/adelante')
	S 'printf "%s\n" "# uke-touch-mode: el demonio de gestos (usuario omarchy, grupo input) crea dispositivos virtuales" "KERNEL==\"uinput\", GROUP=\"input\", MODE=\"0660\"" > /etc/udev/rules.d/71-uke-uinput.rules; udevadm control --reload; chgrp input /dev/uinput; chmod 660 /dev/uinput; ls -l /dev/uinput'
	# 3) demonio de gestos v2 + conf
	tar -C "$HERE" --owner=0 --group=0 --numeric-owner -cf - uke-gestures.py | S "tar -x -C /usr/local/share/uke/gestures && chmod 755 /usr/local/share/uke/gestures/uke-gestures.py"
	S 'f=/home/omarchy/.config/uke-gestures.conf; [ -e $f.bak-touchmode ] || cp -a $f $f.bak-touchmode'
	S "cat > /home/omarchy/.config/uke-gestures.conf; chown omarchy:omarchy /home/omarchy/.config/uke-gestures.conf" < "$HERE/uke-gestures.conf"
	# 4) plugin activo y teclado principal
	S "$OM omarchy plugin enable omarkyy.tablet --section right 2>&1 | tail -2"
	osk_off
	S "$OM systemctl --user restart uke-gestures.service; sleep 2; $OM systemctl --user is-active uke-gestures.service"
	# 5) recargar el shell (SOLO si no hay una prueba delicada en curso): NORELOAD=1 lo omite
	if [ -z "${NORELOAD:-}" ]; then
		S "pkill -x ime-helper; pkill -x input-helper; $OM omarchy restart shell 2>&1 | tail -2; sleep 6"
	else echo "NORELOAD: el plugin nuevo se carga al reiniciar el shell (omarchy restart shell)"; fi
	S "$OM omarchy-shell omarkyy.tablet status 2>&1 | tail -2" ;;
osk-off) osk_off ;;
osk-on) osk_on ;;
status)
	S "$OM omarchy-shell omarkyy.tablet status 2>&1 | tail -1; $OM systemctl --user is-active uke-gestures uke-osk; ls -l /dev/uinput; ls $PL | head -20; $OM journalctl --user -u uke-gestures -n 6 --no-pager -o cat | tail -6" ;;
log)
	S "$OM systemctl --user stop uke-gestures.service; $OM timeout ${T:-60} /usr/bin/python3 -I /usr/local/share/uke/gestures/uke-gestures.py --log ${ACT:+--act}; $OM systemctl --user start uke-gestures.service" ;;
revert-osk)   # vuelve SOLO al teclado previo al rework (helpers input-helper + ime-helper), dejando gestos y demas
	S "pkill -x osk-daemon; rm -rf $PL; install -d -o omarchy -g omarchy $PL"
	tar -C "$HERE/backup-previo/osk-fork-20261018" --owner=omarchy --group=omarchy -cf - . | S "tar -x -C $PL && chown -R omarchy:omarchy $PL"
	S "$OM sh -c 'cd $PL && sh input-backend.sh --build && sh ime-backend.sh --build'"
	[ -z "${NORELOAD:-}" ] && S "$OM omarchy restart shell 2>&1 | tail -2" ;;
test)         # prueba automatica extremo a extremo (ver osk-test.sh)
	bash "$HERE/osk-test.sh" ;;
revert)
	S "pkill -x osk-daemon; $OM omarchy plugin disable omarkyy.tablet 2>&1 | tail -1; rm -rf $PL /home/omarchy/.cache/omarchy/tablet /home/omarchy/.local/state/uke-touch-mode; rm -f /etc/udev/rules.d/71-uke-uinput.rules; udevadm control --reload; chgrp root /dev/uinput; chmod 600 /dev/uinput"
	# gestos T4 previos
	S "cat > /usr/local/share/uke/gestures/uke-gestures.py" < "$HERE/backup-previo/usr/local/share/uke/gestures/uke-gestures.py"
	S "cat > /home/omarchy/.config/uke-gestures.conf; chown omarchy:omarchy /home/omarchy/.config/uke-gestures.conf" < "$HERE/backup-previo/.config/uke-gestures.conf"
	S "$OM systemctl --user restart uke-gestures.service"
	osk_on
	S "$OM omarchy-shell shell rescanPlugins 2>&1 | tail -1"
	echo "revertido (gcc/make/pkgconf se quedan instalados; pacman -Rns gcc make pkgconf para quitarlos)" ;;
*) echo "uso: $0 check|apply|status|revert|revert-osk|test|osk-off|osk-on|log"; exit 2 ;;
esac
