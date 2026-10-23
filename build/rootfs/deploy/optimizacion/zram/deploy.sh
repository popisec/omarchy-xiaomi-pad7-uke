#!/bin/bash
# deploy.sh — zram (22-oct-2026).  check | apply | revert | status.  SOLO tras arrancar el kernel v7 (CONFIG_ZRAM). NO aplicado.
# 23-oct: v7 trae zstd DENTRO del kernel, pero quedaron 2 .ko huerfanos de v6 (kernel/lib/zstd/zstd_compress.ko, kernel/crypto/zstd.ko) y
# depmod hace que zram dependa de ellos -> 'Exec format error' (exports duplicate symbol). huerfanos: los aparta a /root/modulos-huerfanos-v6 + depmod.
# apply: gate (el kernel tiene zram: modinfo zram), instala unidad+script+sysctl, habilita y arranca. revert: para, deshabilita y borra todo.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}; HOST=${UKE_HOST:-root@uke}
S() { timeout "${T:-60}" ssh -i "$KEY" -o BatchMode=yes "$HOST" "$@"; }
case "${1:-}" in
check) bash -n "$HERE/root/usr/local/sbin/uke-zram-up" || exit 1; grep -rnE '^[A-Za-z][A-Za-z0-9]*=.*[[:space:]]#' "$HERE/root" --include=*.conf --include=*.service && { echo "comentario al final de linea: systemd >=262 lo rechaza"; exit 1; }; echo "CHECK OK";;
apply) bash "$0" check || exit 1
	S 'modinfo zram >/dev/null 2>&1' || { echo "ABORTADO: el kernel de la tablet no trae zram (¿v7 sin --post-modules?)"; exit 2; }
	tar -C "$HERE/root" --owner=0 --group=0 --numeric-owner -cf - . | S "tar -x -C / && chmod 755 /usr/local/sbin/uke-zram-up && systemctl daemon-reload && sysctl --system >/dev/null && systemctl enable --now uke-zram.service; sync; swapon --show; free -m | sed -n 1,3p" ;;
revert) S "systemctl disable --now uke-zram.service 2>/dev/null; rm -f /etc/systemd/system/uke-zram.service /usr/local/sbin/uke-zram-up /etc/sysctl.d/99-uke-zram.conf; systemctl daemon-reload; sysctl vm.swappiness=60 vm.page-cluster=3 >/dev/null; sync; echo revertido" ;;
huerfanos) S 'set -e; M=/lib/modules/$(uname -r); B=/root/modulos-huerfanos-v6; zcat /proc/config.gz | grep -q "^CONFIG_ZSTD_COMPRESS=y" || { echo "ABORTADO: zstd no es built-in"; exit 2; }
	mkdir -p $B/kernel/lib/zstd $B/kernel/crypto; for f in kernel/lib/zstd/zstd_compress.ko kernel/crypto/zstd.ko; do [ -f $M/$f ] && { sha256sum $M/$f >> $B/SHA256; mv $M/$f $B/$f; }; done; depmod -a; sync; modprobe -n -v zram' ;;
huerfanos-revert) S 'M=/lib/modules/$(uname -r); B=/root/modulos-huerfanos-v6; mkdir -p $M/kernel/lib/zstd; for f in kernel/lib/zstd/zstd_compress.ko kernel/crypto/zstd.ko; do [ -f $B/$f ] && mv $B/$f $M/$f; done; depmod -a; sync; echo restaurados' ;;
status) S "swapon --show; sysctl vm.swappiness vm.page-cluster; systemctl is-active uke-zram.service" ;;
*) echo "uso: $0 check|huerfanos|huerfanos-revert|apply|revert|status"; exit 2 ;;
esac
