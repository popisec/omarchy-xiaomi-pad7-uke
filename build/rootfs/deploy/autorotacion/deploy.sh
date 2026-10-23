#!/bin/bash
# deploy.sh — instala uke-autorotate en la tablet (NO la activa). 18-oct-2026.  check | apply | revert | status
# `apply` solo copia ficheros; el servicio no se habilita y no arranca sin /dev/fastrpc-adsp (ConditionPathExists).
set -u
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}; HOST=${UKE_HOST:-root@192.168.42.129}
S() { timeout "${T:-60}" ssh -i "$KEY" -o BatchMode=yes "$HOST" "$@"; }
case "${1:-}" in
check) bash -n "$0" && bash -n "$HERE/root/usr/local/bin/uke-autorotate" && echo "CHECK OK" ;;
apply) bash "$0" check || exit 1
	tar -C "$HERE/root" --owner=0 --group=0 --numeric-owner -cf - . | S "tar -x -C / && chmod 755 /usr/local/bin/uke-autorotate && sync"
	echo "copiado. Activar (como omarchy, cuando R4 este verde): systemctl --user enable --now uke-autorotate" ;;
revert) S "systemctl --user -M omarchy@ disable --now uke-autorotate 2>/dev/null; rm -f /usr/local/bin/uke-autorotate /etc/systemd/user/uke-autorotate.service /etc/uke/autorotate.conf.example; sync" ;;
status) S "uke-autorotate status; systemctl --user -M omarchy@ is-active uke-autorotate 2>&1" ;;
*) echo "uso: $0 check|apply|revert|status"; exit 2 ;;
esac
