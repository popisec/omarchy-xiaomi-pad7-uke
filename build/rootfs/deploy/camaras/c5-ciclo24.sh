#!/usr/bin/env bash
# c5-ciclo24.sh — C5b ciclo 24 (preparado 22-oct-2026, NO EJECUTADO): frontal OV08D10 sin buffers (ciclo 23: el RDI ve INFO_INPUT_SOL/EOL y
# VCDT_GRP1_SEL pero ninguna linea sale: sin EPOCH ni BUF_DONE). Hipotesis: los paquetes largos no casan con el VC/DT del grupo 0 del RDI
# (VC 0 / DT 0x2b) o el crop/drop sin ventana de mainline los descarta. NUEVA REGLA tras el oops del ciclo 23: los overlays se aplican UNA
# vez por arranque y NUNCA se descargan en caliente.
#   ./c5-ciclo24.sh --check          solo PC
#   ./c5-ciclo24.sh --load           (1 vez por arranque) sube los .ko y carga todo con persist/uke-camaras-up.sh (marca /run/uke-camaras.done)
#   ./c5-ciclo24.sh --test           solo streams (sin insmod/rmmod): repetible
# Turno «camaras-2» en --load y --test. Host USB por defecto (UKE_HOST para cambiarlo).
set -u
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../.." && pwd)
HOST=${UKE_HOST:-root@192.168.42.129}; export UKE_HOST=$HOST
SSH=(ssh -o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=4 -i "$R/build/rootfs/uke-arch-root" -o BatchMode=yes "$HOST")
TURNO="$R/build/rootfs/deploy/turno/uke-turno"
DIR=/usr/lib/uke-camaras   # mismo sitio que usara uke-camaras.service; aqui solo se copia, no se habilita la unidad
K24="uke_cam_camcc.ko camcc-cliffs-uke.ko uke_cam_rear.ko uke_ov13b10.ko uke_cam_camss.ko uke_cam_front.ko uke_ov08d10.ko uke-camss.ko"
K18="uke_rpmh_ldob14.ko uke_cam_lens.ko uke_dw9714.ko"
check() {
	for f in $K24; do [ -s "$HERE/out-ciclo24/$f" ] || { echo "falta out-ciclo24/$f"; exit 2; }; done
	for f in $K18; do [ -s "$HERE/out-ciclo18/$f" ] || { echo "falta out-ciclo18/$f"; exit 2; }; done
	modinfo -F parm "$HERE/out-ciclo24/uke-camss.ko" | grep -q '^uke_rdi_vc:' || { echo "camss sin uke_rdi_vc"; exit 2; }
	strings "$HERE/out-ciclo24/uke-camss.ko" | grep -qx qcom-camss || { echo "camss no es qcom-camss"; exit 2; }
	bash -n "$HERE/persist/uke-camaras-up.sh" || exit 2
}
check
case "${1:-}" in
--load)
	OUT=$HERE/out/c5-ciclo24-load-$(date +%Y%m%d-%H%M).txt; exec > >(tee "$OUT") 2>&1
	echo "# C5b ciclo 24 --load $(date -Is) host=$HOST"
	"${SSH[@]}" '[ -e /run/uke-camaras.done ]' && { echo "ya cargado en este arranque: usar --test"; exit 0; }
	[ "$("${SSH[@]}" 'lsmod | grep -cE "uke_cam|camcc|camss|ov13|ov08|dw9714|ldob14"')" = 0 ] || { echo "ABORTO: hay modulos de camara de otro arranque/ciclo"; exit 3; }
	"$TURNO" pedir --recurso sistema camaras-2 "ciclo 24 --load: carga unica de las camaras (sin descarga)" 1800 || exit 3
	trap '"$TURNO" soltar --recurso sistema camaras-2' EXIT
	T=$(mktemp -d); for f in $K24; do cp "$HERE/out-ciclo24/$f" "$T/"; done; for f in $K18; do cp "$HERE/out-ciclo18/$f" "$T/"; done; cp "$HERE/persist/uke-camaras-up.sh" "$T/"
	(cd "$T" && sha256sum *) | sort -k2 > "$T.sha"
	(cd "$T" && tar cf - .) | "${SSH[@]}" "mkdir -p $DIR && tar xf - -C $DIR && sync -f $DIR/* && cd $DIR && sha256sum *" | sort -k2 | diff - "$T.sha" && echo "sha iguales" || { echo "ABORTO: sha distintos"; exit 3; }
	DL=$HERE/out/c5c24-dmesg-load-$(date +%H%M).log; "${SSH[@]}" 'dmesg -n 7; timeout 60 dmesg -w' > "$DL" 2>&1 &
	"${SSH[@]}" "UKE_CAM_DIR=$DIR $DIR/uke-camaras-up.sh; echo rc=\$?; ls /dev/media* /dev/video0 2>&1 | head -3; dmesg | grep -aE 'chip id|Oops|Unhandled' | tail -4 | cut -c15-160"
	wait; echo "# fin --load; dmesg en $DL"
	;;
--test)
	OUT=$HERE/out/c5-ciclo24-test-$(date +%Y%m%d-%H%M).txt; exec > >(tee "$OUT") 2>&1
	echo "# C5b ciclo 24 --test $(date -Is) host=$HOST"
	"${SSH[@]}" '[ -e /run/uke-camaras.done ] && [ -e /dev/media0 ]' || { echo "ABORTO: falta --load en este arranque"; exit 3; }
	"$TURNO" pedir --recurso sistema camaras-2 "ciclo 24 --test: streams de camara (sin insmod)" 1800 || exit 3
	trap '"$TURNO" soltar --recurso sistema camaras-2' EXIT
	"${SSH[@]}" "bash -s" <<'REMOTE'
M="media-ctl -d /dev/media0"; P=/sys/module/uke_camss/parameters; VID=$($M -e msm_vfe0_video0)
pkill -f "why=C5c24" 2>/dev/null; (setsid nohup systemd-inhibit --what=sleep:idle --who=camara --why=C5c24 sleep 900 >/dev/null 2>&1 &)
trap 'pkill -f "v4l2-ctl -d /dev/video" 2>/dev/null; pkill -f "why=C5c24" 2>/dev/null' EXIT
dmesg -n 7; rm -f /root/b24-*.raw
echo 1 > $P/uke_stat; echo 0 > $P/uke_rdi_budget; echo $((0xfffffff0)) > $P/uke_rx_mask
reset_links() { $M -r; }
route() {  # $1 entidad del sensor  $2 csiphy  $3 W  $4 H  $5 codigo
  reset_links
  $M -l "\"msm_$2\":1->\"msm_csid0\":0[1]"; $M -l "\"msm_csid0\":1->\"msm_vfe0_rdi0\":0[1]"
  local f="fmt:$5/$3x$4"
  $M -V "\"$1\":0[$f],\"msm_$2\":0[$f],\"msm_$2\":1[$f],\"msm_csid0\":0[$f],\"msm_csid0\":1[$f],\"msm_vfe0_rdi0\":0[$f],\"msm_vfe0_rdi0\":1[$f]" 2>&1 | tail -1
  local pf; case $5 in SBGGR10_1X10) pf=pBAA;; SGRBG10_1X10) pf=pgAA;; esac
  v4l2-ctl -d $VID --set-fmt-video=width=$3,height=$4,pixelformat=$pf >/dev/null
}
n=0
shot() {  # $1 etiqueta $2 subdev del sensor $3 cap_ctrl $4 rdi_vc $5 rdi_cfg1 $6 test_pattern
  n=$((n+1)); echo $3 > $P/uke_cap_ctrl; echo 4 > $P/uke_cap_n; echo 4 > $P/uke_rx_budget; echo $4 > $P/uke_rdi_vc; echo $5 > $P/uke_rdi_cfg1
  v4l2-ctl -d $2 -c test_pattern=$6 >/dev/null 2>&1; dmesg -C; rm -f /root/c24.raw
  timeout 6 v4l2-ctl -d $VID --stream-mmap=3 --stream-count=1 --stream-to=/root/c24.raw > /root/c24.v4l 2>&1
  local BY=$(stat -c %s /root/c24.raw 2>/dev/null || echo 0)
  echo "######## $n $1 cap=$3 vc=$4 cfg1=$5 tp=$6 bytes=$BY"
  dmesg | grep -aE 'uke-rdi0|uke-cap|RX_IRQ' | cut -c15-240 | head -10
  head -c 700 $P/uke_statline | head -4
  if [ "$BY" -gt 0 ]; then echo "  nonzero=$(tr -d '\000' < /root/c24.raw | wc -c)"; sync -f /root/c24.raw; cp /root/c24.raw /root/b24-$n.raw; fi
  echo 0 > $P/uke_rx_budget; echo -1 > $P/uke_cap_ctrl; echo -1 > $P/uke_rdi_vc; echo -1 > $P/uke_rdi_cfg1
}
FS=$($M -e "$($M -p | awk '/entity.*ov08d10/{sub(/.*: /,""); sub(/ \(.*/,""); print; exit}')")
RS=$($M -e "$($M -p | awk '/entity.*ov13b10/{sub(/.*: /,""); sub(/ \(.*/,""); print; exit}')")
FE=$($M -p | awk '/entity.*ov08d10/{sub(/.*: /,""); sub(/ \(.*/,""); print; exit}'); RE=$($M -p | awk '/entity.*ov13b10/{sub(/.*: /,""); sub(/ \(.*/,""); print; exit}')
echo "frontal=$FE ($FS) trasera=$RE ($RS) video=$VID"
route "$FE" csiphy4 1632 1224 SBGGR10_1X10
shot "F cap VC0 DT2b"        $FS $((0x2b3))                  -1 -1      1
shot "F cap VC1 DT2b"        $FS $((0x2b3 | 1<<10 | 1<<15))  -1 -1      1
shot "F cap VC2 DT2b"        $FS $((0x2b3 | 2<<10 | 2<<15))  -1 -1      1
shot "F cfg1 sin crop/drop"  $FS -1                          -1 $((0x8400)) 1
shot "F RDI vc=1"            $FS -1                           1 -1      1
shot "F RDI vc=2"            $FS -1                           2 -1      1
route "$RE" csiphy1 2104 1560 SGRBG10_1X10
shot "R control"             $RS $((0x2b3))                  -1 -1      1
reset_links
echo "fallos SMMU/oops: $(dmesg | grep -acE 'Unhandled (context|stream) fault|Oops')"
REMOTE
	"${SSH[@]}" 'cd /root && ls b24-*.raw 2>/dev/null | xargs -r tar cf -' | { rm -f "$HERE"/out/b24-*.raw; tar xf - -C "$HERE/out/" 2>/dev/null; }; ls -l "$HERE"/out/b24-*.raw 2>/dev/null
	echo "# fin --test"
	;;
*) echo "check OK"; (cd "$HERE/out-ciclo24" && sha256sum $K24 | cut -c1-16,65-); (cd "$HERE/out-ciclo18" && sha256sum $K18 | cut -c1-16,65-) ;;
esac
