#!/bin/bash
# deploy.sh — optimizacion userspace (20-oct-2026).  check | apply | revert | status
# apply: journald (tope 150M, vacuum), coredump (tope 64M), THP madvise, systemd-homed deshabilitado.
# revert: quita los drop-ins, THP always, reactiva homed. NO recupera logs ya vacuados.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}; HOST=${UKE_HOST:-root@uke}
S() { timeout "${T:-60}" ssh -i "$KEY" -o BatchMode=yes "$HOST" "$@"; }
case "${1:-}" in
check) for f in $(find "$HERE/root" -type f); do [ -s "$f" ] || { echo "vacio $f"; exit 1; }; done; grep -rnE '^[A-Za-z][A-Za-z0-9]*=.*[[:space:]]#' "$HERE/root" --include=*.conf --include=*.service && { echo "comentario al final de linea: systemd >=262 lo rechaza"; exit 1; }; bash -n "$0" || exit 1; echo "CHECK OK" ;;
apply) bash "$0" check || exit 1
	S "mkdir -p /var/lib/uke-optim; [ -e /var/lib/uke-optim/antes.txt ] || { journalctl --disk-usage; cat /sys/kernel/mm/transparent_hugepage/enabled; systemctl is-enabled systemd-homed; } > /var/lib/uke-optim/antes.txt"   # solo la primera vez: conserva el estado ORIGINAL
	tar -C "$HERE/root" --owner=0 --group=0 --numeric-owner -cf - . | S "tar -x -C /"
	S "echo madvise > /sys/kernel/mm/transparent_hugepage/enabled; systemctl restart systemd-journald; journalctl --vacuum-size=150M 2>&1|tail -1; systemctl disable --now systemd-homed.service 2>&1|tail -1; sync; journalctl --disk-usage" ;;
revert) S "rm -f /etc/systemd/journald.conf.d/uke-optim.conf /etc/systemd/coredump.conf.d/uke-optim.conf /etc/tmpfiles.d/uke-thp.conf; echo always > /sys/kernel/mm/transparent_hugepage/enabled; systemctl enable --now systemd-homed.service; [ -s /var/lib/uke-optim/uke-fix.service.orig ] && cp -a /var/lib/uke-optim/uke-fix.service.orig /etc/systemd/system/uke-fix.service && rm -f /etc/tmpfiles.d/uke-sshd.conf && systemctl daemon-reload; systemctl restart systemd-journald; sync; echo revertido" ;;
status) S "journalctl --disk-usage; cat /sys/kernel/mm/transparent_hugepage/enabled; systemctl is-enabled systemd-homed; df -h / | tail -1" ;;
*) echo "uso: $0 check|apply|revert|status"; exit 2 ;;
esac
