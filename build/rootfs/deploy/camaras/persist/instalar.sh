#!/usr/bin/env bash
# instalar.sh — carga de las camaras en el arranque (22-oct-2026). Desde el PC, con turno «camaras-2».
#   ./instalar.sh --copiar      copia modulos y scripts a /usr/lib/uke-camaras, unidades a /etc/systemd/system y la conf de ejemplo
#                               (sin pisar /etc/uke/camaras.conf); NO habilita nada. Verifica con sha256 (y sync -f antes de copiar).
#   ./instalar.sh --habilitar   systemctl enable uke-camaras.service uke-camaras-lente.service — SOLO con OK directo del duenio. No reinicia.
#   ./instalar.sh --deshabilitar
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../../.." && pwd)
HOST=${UKE_HOST:-root@192.168.42.129}; export UKE_HOST=$HOST
SSH=(ssh -o ConnectTimeout=8 -i "$R/build/rootfs/uke-arch-root" -o BatchMode=yes "$HOST")
TURNO="$R/build/rootfs/deploy/turno/uke-turno"
C=$HERE/..
K24="uke_cam_camcc.ko camcc-cliffs-uke.ko uke_cam_rear.ko uke_ov13b10.ko uke_cam_camss.ko uke_cam_front.ko uke_ov08d10.ko uke-camss.ko"
K18="uke_rpmh_ldob14.ko uke_cam_lens.ko uke_dw9714.ko"
case "${1:-}" in
--copiar)
	T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
	for f in $K24; do cp "$C/out-ciclo24/$f" "$T/"; done; for f in $K18; do cp "$C/out-ciclo18/$f" "$T/"; done
	cp "$HERE/uke-camaras-up.sh" "$HERE/uke-camaras-lente.sh" "$HERE/uke-camaras.service" "$HERE/uke-camaras-lente.service" "$HERE/camaras.conf.ejemplo" "$T/"
	(cd "$T" && sha256sum *) | sort -k2 > "$T.sha"
	"$TURNO" pedir --recurso sistema camaras-2 "copiar la carga de camaras al arranque (sin habilitar)" 3000; trap '"$TURNO" soltar --recurso sistema camaras-2; rm -rf "$T"' EXIT
	(cd "$T" && tar cf - .) | "${SSH[@]}" 'set -e; D=/root/uke-camaras-inst; rm -rf $D; mkdir -p $D; tar xf - -C $D; cd $D; sync -f *
		mkdir -p /usr/lib/uke-camaras /etc/uke
		for f in *.ko uke-camaras-up.sh uke-camaras-lente.sh; do install -m 755 $f /usr/lib/uke-camaras/$f; done
		install -m 644 uke-camaras.service uke-camaras-lente.service /etc/systemd/system/
		[ -e /etc/uke/camaras.conf ] || install -m 644 camaras.conf.ejemplo /etc/uke/camaras.conf
		sync; systemctl daemon-reload
		cd /usr/lib/uke-camaras && sha256sum *.ko uke-camaras-up.sh uke-camaras-lente.sh; cd /etc/systemd/system && sha256sum uke-camaras.service uke-camaras-lente.service
		systemctl is-enabled uke-camaras.service uke-camaras-lente.service || true' | sort -k2 > "$T.remote"
	grep -v -e enabled -e disabled "$T.remote" | diff <(grep -v camaras.conf "$T.sha") - && echo "copiado y verificado (sha256); unidades: $(grep -E "^(enabled|disabled)" "$T.remote" | tr "\n" " ")(--copiar no cambia el estado)"
	;;
--habilitar)
	"$TURNO" pedir --recurso sistema camaras-2 "habilitar la carga de camaras al arranque (sin reiniciar)" 3000; trap '"$TURNO" soltar --recurso sistema camaras-2' EXIT
	"${SSH[@]}" 'systemctl enable uke-camaras.service uke-camaras-lente.service && systemctl is-enabled uke-camaras.service uke-camaras-lente.service'
	;;
--deshabilitar)
	"$TURNO" pedir --recurso sistema camaras-2 "deshabilitar la carga de camaras al arranque" 3000; trap '"$TURNO" soltar --recurso sistema camaras-2' EXIT
	"${SSH[@]}" 'systemctl disable uke-camaras.service uke-camaras-lente.service; systemctl is-enabled uke-camaras.service uke-camaras-lente.service || true'
	;;
*) echo "uso: $0 --copiar | --habilitar | --deshabilitar"; exit 2 ;;
esac
