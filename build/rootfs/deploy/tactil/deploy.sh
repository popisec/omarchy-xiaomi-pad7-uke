#!/bin/bash
# deploy.sh — instala el tactil persistente en la tablet (tar | ssh). 18-oct-2026.
#   check   (PC) sintaxis + py_compile + unidad
#   apply   copia scripts/unidad, comprueba el firmware en la tablet (sha), daemon-reload, enable (NO arranca)
#   start   para la unidad transitoria de pruebas (si la hay) y arranca uke-touch.service
#   status  estado de la unidad, ultimas lineas del log y CPU
#   revert  disable + borra la unidad y uke-touch-up.sh (deja scripts y firmware)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$HERE/../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}
HOST=${UKE_HOST:-root@192.168.42.129}
FWSHA=a4f949fb89c7eaad9da85a5885cd2dcc1fffbf08bc1e7ffe9f0bb97c
S() { timeout "${T:-60}" ssh -i "$KEY" -o BatchMode=yes "$HOST" "$@"; }
case "${1:-}" in
check)
	bash -n "$HERE/root/usr/local/sbin/uke-touch-up.sh" && bash -n "$0" || exit 1
	python3 -I -c "import ast,sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]" \
		"$HERE"/uke-touchd.py "$HERE"/thp_algo.py "$HERE"/uke-touch-fwload.py || exit 1
	command -v systemd-analyze >/dev/null && systemd-analyze verify "$HERE/root/etc/systemd/system/uke-touch.service" 2>&1 | grep -v "not found\|Failed to\|ConditionPath" || true
	echo "CHECK OK" ;;
apply)
	bash "$HERE/deploy.sh" check || exit 1
	S "sha256sum /lib/firmware/novatek_nt36532_o82_fw_csot.bin 2>/dev/null | grep -q ^$FWSHA" || { echo "falta el firmware en la tablet (sha $FWSHA…)"; exit 1; }
	tar -C "$HERE" --owner=0 --group=0 --numeric-owner -cf - uke-touchd.py thp_algo.py uke-touch-fwload.py README.md | \
		S "install -d -m755 /usr/local/share/uke/tactil && tar -x -C /usr/local/share/uke/tactil && chmod 755 /usr/local/share/uke/tactil/*.py"
	tar -C "$HERE/root" --owner=0 --group=0 --numeric-owner -cf - . | S "tar -x -C / && systemctl daemon-reload && systemctl enable uke-touch.service && sync; systemctl is-enabled uke-touch.service" ;;
start)
	S "systemctl stop uke-touchd.service 2>/dev/null; systemctl reset-failed uke-touchd.service 2>/dev/null; systemctl restart uke-touch.service; sleep 6; systemctl is-active uke-touch.service; journalctl -u uke-touch -b --no-pager -o cat | tail -8" ;;
status)
	S "systemctl status uke-touch.service --no-pager | head -8; journalctl -u uke-touch -b --no-pager -o cat | tail -6; P=\$(systemctl show -p MainPID --value uke-touch); [ \"\$P\" -gt 0 ] && ps -o pid,pcpu,rss,etime,cmd -p \$P" ;;
revert)
	S "systemctl disable --now uke-touch.service; rm -f /etc/systemd/system/uke-touch.service /usr/local/sbin/uke-touch-up.sh; systemctl daemon-reload; sync; echo revertido" ;;
*) echo "uso: $0 check|apply|start|status|revert"; exit 2 ;;
esac
