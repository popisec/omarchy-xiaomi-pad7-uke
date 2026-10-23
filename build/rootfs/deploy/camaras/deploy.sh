#!/usr/bin/env bash
# deploy.sh -- copia a la tablet los artefactos de camara de UNA etapa. NO carga nada (insmod/rmmod son a mano, ver el plan).
#   ./deploy.sh --check            solo PC: verifica MANIFEST.sha256 y muestra el plan; no abre ninguna conexion
#   ./deploy.sh --go --push C2     (ORDEN DEL DUENO) tar|ssh de los ficheros de la etapa a /root/uke-cam/ (ext4, no tmpfs) y verifica sha256 alli
# Etapas: C2 = uke_cam_camcc.ko + camcc-cliffs-uke.ko ; C4 = + uke_cam_rear.ko + uke_ov13b10.ko ; C5 = + uke_cam_camss.ko + uke-camss.ko ;
#         C6 = + uke_cam_front.ko + uke_ov08d10.ko. No toca /lib/modules ni depmod: se carga con insmod por ruta (nada persiste tras reiniciar).
set -Eeuo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../.." && pwd); OUT=$HERE/out
declare -A FILES=( [C2]="uke_cam_camcc.ko camcc-cliffs-uke.ko" [C4]="uke_cam_rear.ko uke_ov13b10.ko" [C5]="uke_cam_camss.ko uke-camss.ko" [C6]="uke_cam_front.ko uke_ov08d10.ko" )
# El manifiesto lo genera build.sh y tiene dos clases de entradas: las FUENTES
# (que deben estar y cuadrar) y los ARTEFACTOS GENERADOS (out/*, que solo
# existen tras un build). Antes de un build, el out/ no esta, asi que el check
# fallaba entero y no decia por que. Ahora se separan.
mal_fuentes=$( cd "$HERE" && grep -v "  out/" MANIFEST.sha256 | sha256sum -c --quiet 2>&1 ) || true
if [ -n "$mal_fuentes" ]; then
	echo "MANIFEST: las FUENTES no cuadran:"
	echo "$mal_fuentes"
	exit 2
fi
n_fuentes=$(grep -cv "  out/" "$HERE/MANIFEST.sha256")
echo "manifiesto: $n_fuentes fuentes OK"
n_out=$(grep -c "  out/" "$HERE/MANIFEST.sha256")
n_out_ok=0
if [ -d "$OUT" ]; then
	n_out_ok=$( cd "$HERE" && grep "  out/" MANIFEST.sha256 | sha256sum -c --quiet 2>/dev/null | grep -c ": OK$" || true )
fi
echo "artefactos generados: $n_out_ok/$n_out (los que falten se construyen con ./build.sh)"
case "${1:-}" in
--check|"") for s in C2 C4 C5 C6; do echo "$s: ${FILES[$s]}"; done; exit 0;;
--go) [ "${2:-}" = "--push" ] && [ -n "${FILES[${3:-}]:-}" ] || { echo "uso: --go --push C2|C4|C5|C6"; exit 2; }
	st=$3; cd "$OUT"
	tar cf - ${FILES[$st]} | ssh -i "$R/build/rootfs/uke-arch-root" -o BatchMode=yes root@192.168.42.129 \
		"mkdir -p /root/uke-cam && tar xf - -C /root/uke-cam && cd /root/uke-cam && sha256sum ${FILES[$st]}"
	( cd "$OUT" && sha256sum ${FILES[$st]} ); echo "comparar las dos listas de sha256";;
*) echo "uso: --check | --go --push <etapa>"; exit 2;;
esac
