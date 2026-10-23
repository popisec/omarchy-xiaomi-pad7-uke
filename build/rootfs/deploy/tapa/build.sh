#!/usr/bin/env bash
# build.sh — compila uke-tapa.dtso, pasa el gate fdtoverlay (DT base y, si existe, DT vivo volcado) y construye uke_tapa.ko EN EL PC.
# No abre ninguna conexion. Uso: build.sh [--live-dtb FICHERO]   (FICHERO = DT vivo de la tablet: ver README)
set -Eeuo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../.." && pwd)
KT=${KT:-$R/build/kernel-pokes/senemos-7.2.9/linux-7.2.9}
KB=${KB:-$R/build/kernel-pokes/senemos-build}
BASE=${BASE:-$R/build/kernel-pokes/senemos-7.2.9/dt/res-live-final.dtb}
LIVE=""; [ "${1:-}" = "--live-dtb" ] && LIVE=${2:?fichero}
OUT=$HERE/out; mkdir -p "$OUT"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp -I "$KT/include" "$HERE/dts/uke-tapa.dtso" -o "$T/p.dts"
dtc -@ -I dts -O dtb -o "$OUT/uke-tapa.dtbo" "$T/p.dts" 2> "$T/err"; [ ! -s "$T/err" ] || { cat "$T/err"; exit 1; }
echo "dtbo $(stat -c %s "$OUT/uke-tapa.dtbo") B sha256 $(sha256sum < "$OUT/uke-tapa.dtbo" | cut -d' ' -f1)"
for B in "$BASE" ${LIVE:+"$LIVE"}; do
	fdtoverlay -i "$B" -o "$T/m.dtb" "$OUT/uke-tapa.dtbo"
	echo "fdtoverlay OK sobre $(basename "$B")"
	for n in lid-hall table-hall; do
		echo "  $n: gpios=$(fdtget -t x "$T/m.dtb" /soc/uke-hall/$n gpios | tr ' ' ,) code=$(fdtget -t u "$T/m.dtb" /soc/uke-hall/$n linux,code) type=$(fdtget -t u "$T/m.dtb" /soc/uke-hall/$n linux,input-type)"
	done
	echo "  tlmm phandle=$(fdtget -t x "$T/m.dtb" /soc/pinctrl@f000000 phandle 2>/dev/null || echo '?')"
done
env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL MAKE=/usr/bin/make ARCH=arm64 LLVM=1 UKE_OVL_DIR="$OUT" UKE_OVL_HDR="$R/build/rootfs/deploy/bt/module" \
	/usr/bin/make -C "$KB" M="$HERE/module" modules > "$T/make.log" 2>&1 || { cat "$T/make.log"; exit 1; }
cp "$HERE/module/uke_tapa.ko" "$OUT/"; modinfo "$OUT/uke_tapa.ko" | grep -E 'vermagic|description'
( cd "$OUT" && sha256sum uke-tapa.dtbo uke_tapa.ko ) | tee "$OUT/SHA256SUMS"
