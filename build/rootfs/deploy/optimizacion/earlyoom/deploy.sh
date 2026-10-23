#!/bin/bash
# earlyoom en la uke (23-oct-2026). apply | revert | status. Requiere `pacman -S earlyoom` hecho (turno de sistema).
set -u
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}; HOST=${UKE_HOST:-root@uke}
S() { timeout 60 ssh -i "$KEY" -o BatchMode=yes "$HOST" "$@"; }
case "${1:-}" in
apply) S 'command -v earlyoom >/dev/null' || { echo "ABORTADO: earlyoom no instalado"; exit 2; }
	S '[ -f /etc/default/earlyoom.orig ] || cp -a /etc/default/earlyoom /etc/default/earlyoom.orig'
	S 'cat > /etc/default/earlyoom' < "$HERE/root/etc/default/earlyoom"
	S 'systemctl enable earlyoom.service && systemctl restart earlyoom.service; sync; sleep 2; systemctl is-active earlyoom; journalctl -u earlyoom -n 12 --no-pager -o cat' ;;
revert) S 'systemctl disable --now earlyoom.service; [ -f /etc/default/earlyoom.orig ] && mv /etc/default/earlyoom.orig /etc/default/earlyoom; sync; echo "revertido (para quitar el paquete: pacman -R earlyoom)"' ;;
status) S 'systemctl is-active earlyoom; journalctl -u earlyoom -n 12 --no-pager -o cat' ;;
*) echo "uso: $0 apply|revert|status"; exit 2 ;;
esac
