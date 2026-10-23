#!/bin/bash
# fsck-resize.sh — backup + e2fsck en "frio" + ampliar / a toda la particion (20-oct-2026).
#   backup   : tar del rootfs de la tablet al PC (solo lectura en la tablet). Seguro, hacerlo antes.
#   fsck     : mask journald, remount ro, e2fsck -fy x2, -fn x2 (flujo de NOTAS 1-oct, ledger #450). NO reinicia.
#   reboot   : sync + reinicio (sysrq-b tras sync). Tras el reinicio: desenmascarar journald (lo hace 'resize').
#   resize   : desenmascara journald, comprueba fs limpio y ejecuta resize2fs en caliente a toda la particion.
# Requiere al dueno presente con la consola ACM leida (un solo lector) durante 'reboot'. Un cambio por ciclo.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}; HOST=${UKE_HOST:-root@uke}
S() { timeout "${T:-900}" ssh -i "$KEY" -o BatchMode=yes "$HOST" "$@"; }
BK=${UKE_BK:-$HOME/backups/uke-rootfs-$(date +%Y%m%d).tar.zst}
case "${1:-}" in
backup) mkdir -p "$(dirname "$BK")"; S "tar -C / --one-file-system --exclude=./proc --exclude=./sys --exclude=./dev --exclude=./run --exclude=./tmp -cf - ." | zstd -T4 -3 > "$BK" \
	&& zstd -t "$BK" && sha256sum "$BK" | tee "$BK.sha256" && ls -la "$BK" ;;
fsck) S 'set -e; systemctl mask --now systemd-journald.service systemd-journald.socket systemd-journald-dev-log.socket 2>&1|tail -1 || true
	sync; mount -o remount,ro,norecovery / ; findmnt -n / ; e2fsck -fn /dev/sda32 | tail -15 | tee /root/e2fsck-inventario.txt || true
	for i in 1 2; do e2fsck -f -y /dev/sda32 | tail -8; echo rc=$?; done; e2fsck -fn /dev/sda32 | tail -3; echo "rc=$?"; tune2fs -l /dev/sda32|grep "state"' ;;
reboot) S 'sync; sync; echo s > /proc/sysrq-trigger; sleep 2; echo b > /proc/sysrq-trigger' ;;
resize) S 'systemctl unmask systemd-journald.service systemd-journald.socket systemd-journald-dev-log.socket; systemctl start systemd-journald.socket systemd-journald.service
	tune2fs -l /dev/sda32|grep "state"; dmesg|tail -2; resize2fs /dev/sda32; sync; df -h /' ;;
*) echo "uso: $0 backup|fsck|reboot|resize"; exit 2 ;;
esac
