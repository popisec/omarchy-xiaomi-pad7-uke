#!/usr/bin/env bash
# build-vcm.sh -- modulos del VCM de la trasera (ciclo 18): uke_rpmh_ldob14.ko (riel l14), uke_cam_vcm.ko (overlay), uke_vcm.ko (driver).
# Solo PC. Salida en ../out-ciclo18. KB/KT = arbol ouke5.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../../.." && pwd)
KT=${KT:-$R/build/kernel-pokes/senemos-ouke5/linux-7.2.9}; KB=${KB:-$R/build/kernel-pokes/senemos-ouke5/build}
BT=$R/build/rootfs/deploy/bt/module; OUT=${OUT:-$HERE/../out-ciclo18}; MERGED=$HERE/../out-ciclo16/merged.dtb
KREL=$(cat "$KB/include/config/kernel.release"); mkdir -p "$OUT"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
for o in vcm lens; do
	dtc -@ -Wno-reg_format -Wno-avoid_default_addr_size -Wno-unit_address_vs_reg -Wno-i2c_bus_reg -I dts -O dtb -o "$OUT/uke-cam-$o.dtbo" "$HERE/uke-cam-$o.dtso" 2> "$T/dtc.err"; [ -s "$T/dtc.err" ] && { cat "$T/dtc.err"; exit 1; }
done
fdtoverlay -i "$MERGED" -o "$T/l.dtb" "$OUT/uke-cam-lens.dtbo"
echo "fdtoverlay lens OK: lens-focus del sensor = $(fdtget -t x "$T/l.dtb" /soc/qcom,cci0@ac15000/i2c-bus@1/camera@10 lens-focus), phandle de lens@c = $(fdtget -t x "$T/l.dtb" /soc/qcom,cci0@ac15000/i2c-bus@1/lens@c phandle)"
fdtoverlay -i "$MERGED" -o "$T/m.dtb" "$OUT/uke-cam-vcm.dtbo"
echo "fdtoverlay OK sobre out-ciclo16/merged.dtb: $(fdtget -t s "$T/m.dtb" /soc/qcom,cci0@ac15000/i2c-bus@1/lens@c compatible) vdd-supply=$(fdtget -t x "$T/m.dtb" /soc/qcom,cci0@ac15000/i2c-bus@1/lens@c vdd-supply)"
S=$T/stage; mkdir -p "$S/blobs"; cp "$OUT"/uke-cam-vcm.dtbo "$OUT"/uke-cam-lens.dtbo "$S/blobs/"; cp "$HERE"/uke_cam_vcm.c "$HERE"/uke_vcm.c "$HERE"/uke_cam_lens.c "$HERE"/Kbuild "$S/"
python3 -I "$HERE/gen-ldob14.py" "$KT" "$S"
python3 -I "$HERE/gen-dw9714.py" "$KT" "$S"
env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL MAKE=/usr/bin/make ARCH=arm64 LLVM=1 UKE_OVL_DIR="$S/blobs" UKE_OVL_INC="$BT" /usr/bin/make -C "$KB" M="$S" modules > "$S/make.log" 2>&1 || { tail -40 "$S/make.log"; exit 1; }
for m in uke_rpmh_ldob14 uke_cam_vcm uke_vcm uke_cam_lens uke_dw9714; do
	[ -s "$S/$m.ko" ] || { echo "no se genero $m.ko"; exit 1; }
	[ "$(modinfo -F vermagic "$S/$m.ko" | cut -d' ' -f1)" = "$KREL" ] || { echo "$m vermagic"; exit 1; }
	cp "$S/$m.ko" "$OUT/"; printf '%-20s %7d B %s\n' "$m.ko" "$(stat -c %s "$OUT/$m.ko")" "$(sha256sum "$OUT/$m.ko" | cut -c1-16)"
done
grep -Ei 'warning|error' "$S/make.log" | grep -v 'Entering\|Leaving' > "$OUT/make-warnings-vcm.txt" || true
echo "avisos: $(wc -l < "$OUT/make-warnings-vcm.txt")"; cp "$S/uke_rpmh_ldob14.c" "$S/uke_dw9714.c" "$OUT/"; echo "RESULTADO: OK ($KREL)"
