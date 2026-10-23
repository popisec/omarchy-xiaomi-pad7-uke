#!/bin/bash
# e3c/deploy.sh — copia a la tablet SOLO el fichero uke_lpi_rd.ko (extra/); NO lo carga. Sin --go: verificacion local. --revert borra el fichero.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); A=$(cd "$HERE/.." && pwd); R=$(cd "$A/../../../.." && pwd)
HOSTIP=192.168.42.129; KEY=$R/build/rootfs/uke-arch-root; KREL=7.2.9-senemos.1.4054.3-ouke4; SSHO="-i $KEY -o BatchMode=yes -o ConnectTimeout=8"
K=$A/out/uke_lpi_rd.ko; K2=$A/out/uke_lpi_io.ko; say() { printf '[deploy-e3c] %s\n' "$*"; }; die() { say "ABORTADO: $*"; exit 2; }
for kk in "$K" "$K2"; do [ -s "$kk" ] && [ "$(modinfo -F vermagic "$kk" | cut -d' ' -f1)" = "$KREL" ] || die "falta o no es para $KREL: $kk"; done
say "verificacion local OK: $(sha256sum "$K" | cut -c1-16); parametros: $(modinfo -F parm "$K" | cut -d: -f1 | tr '\n' ' ')"
case "${1:-}" in
	--go) [ "$(ssh $SSHO root@$HOSTIP uname -r 2>/dev/null)" = "$KREL" ] || die "tablet no esta en $KREL"
	      scp $SSHO "$K" "$K2" root@$HOSTIP:/lib/modules/$KREL/extra/ >/dev/null && ssh $SSHO root@$HOSTIP "chmod 644 /lib/modules/$KREL/extra/uke_lpi_rd.ko /lib/modules/$KREL/extra/uke_lpi_io.ko; depmod -a $KREL; sync; sha256sum /lib/modules/$KREL/extra/uke_lpi_rd.ko /lib/modules/$KREL/extra/uke_lpi_io.ko | cut -c1-16,60-";;
	--revert) ssh $SSHO root@$HOSTIP "rm -fv /lib/modules/$KREL/extra/uke_lpi_rd.ko /lib/modules/$KREL/extra/uke_lpi_io.ko; depmod -a $KREL; sync";;
	*) say "Nada ejecutado. Aplicar: $0 --go";;
esac
