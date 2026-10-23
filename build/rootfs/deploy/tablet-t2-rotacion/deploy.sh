#!/bin/bash
# deploy.sh — instala la rotacion manual (T2) en la tablet. 18-oct-2026.
#   check | apply | revert | status
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$HERE/../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}
HOST=${UKE_HOST:-root@192.168.42.129}
B=/home/omarchy/.config/hypr/bindings.lua
S() { timeout "${T:-60}" ssh -i "$KEY" -o BatchMode=yes "$HOST" "$@"; }
BEG='-- >>> uke-t2-rotacion'; END='-- <<< uke-t2-rotacion'
strip() { S "sed -i '/^$BEG/,/^$END/d' $B"; }
case "${1:-}" in
check) bash -n "$0" && bash -n "$HERE/root/usr/local/bin/uke-rotate" && sh -n "$HERE/root/usr/local/bin/uke-vol-key" && echo "CHECK OK" ;;
apply)
	bash "$0" check || exit 1
	tar -C "$HERE/root" --owner=0 --group=0 --numeric-owner -cf - . | S "tar -x -C / && chmod 755 /usr/local/bin/uke-rotate /usr/local/bin/uke-vol-key"
	S "cp -n $B $B.bak.t2"
	strip
	{ echo "$BEG"; cat "$HERE/bindings-snippet.lua"; echo "$END"; } | S "cat >> $B; chown omarchy:omarchy $B"
	S "sync"; echo "aplicado; recarga: hyprctl reload (como omarchy) y hyprctl configerrors" ;;
revert)
	strip; S "rm -f /usr/local/bin/uke-rotate /usr/local/bin/uke-vol-key; sync"
	echo "revertido (recarga Hyprland para soltar los binds; la orientacion actual se queda hasta recargar)" ;;
status) S "uke-rotate status; grep -c uke-t2-rotacion $B" ;;
*) echo "uso: $0 check|apply|revert|status"; exit 2 ;;
esac
