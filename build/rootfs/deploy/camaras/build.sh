#!/usr/bin/env bash
# build.sh -- compila y verifica EN EL PC todo lo de las camaras de la uke (etapa C0, 19-oct-2026).
# No toca la tablet: ni ssh, ni adb, ni fastboot. Genera out/*.dtbo, out/merged.dtb y out/*.ko y MANIFEST.sha256.
#   ./build.sh          todo (overlays + fdtoverlay + check + modulos)
#   ./build.sh --quick  sin compilar los modulos
# Entradas (sobreescribibles por entorno): KT arbol fuente senemos (solo LECTURA), KB arbol de build ouke4 (make -C $KB M=<stage>;
# NO se modifica: se huella antes y despues), BASE = DT que ve el kernel (res-live-final.dtb), BT = deploy/bt (uke-ovl.h reutilizado).
# Lanzalo desprendido para los modulos: setsid nohup build/rootfs/deploy/camaras/build.sh > /tmp/uke-cam-build.log 2>&1 &
set -Eeuo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
R=${R:-$(cd "$HERE/../../../.." && pwd)}
KT=${KT:-$R/build/kernel-pokes/senemos-7.2.9/linux-7.2.9}
KB=${KB:-$R/build/kernel-pokes/senemos-build}
BASE=${BASE:-$R/build/kernel-pokes/senemos-7.2.9/dt/res-live-final.dtb}
BT=${BT:-$R/build/rootfs/deploy/bt/module}
OUT=${OUT:-$HERE/out}; QUICK=0; [ "${1:-}" = "--quick" ] && QUICK=1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0; bad() { echo "FALLO: $*"; fails=$((fails + 1)); }; say() { printf '\n== %s\n' "$*"; }; okm() { printf '   ok  %s\n' "$*"; }
for c in cpp dtc fdtoverlay fdtget python3 clang ld.lld make modinfo sha256sum; do command -v "$c" >/dev/null || { echo "falta $c"; exit 2; }; done
python3 -c 'import libfdt' 2>/dev/null || { echo "falta pylibfdt"; exit 2; }
for f in "$BASE" "$KT/include/dt-bindings/clock/qcom,sm8650-camcc.h" "$KT/include/dt-bindings/clock/qcom,gcc-cliffs.h" "$BT/uke-ovl.h" "$KB/Module.symvers" "$KB/.config"; do
	[ -e "$f" ] || { echo "falta $f"; exit 2; }; done
KREL=$(cat "$KB/include/config/kernel.release"); mkdir -p "$OUT"
say "entradas"; echo "   kernel $KREL   base $(basename "$BASE") sha256 $(sha256sum "$BASE" | cut -c1-16)"

say "1. cabecera de phandles (de la base; solo los nodos sin etiqueta en __symbols__)"
python3 - "$BASE" "$OUT/uke-cam-ph.h" <<'PY'
import sys, libfdt
fdt = libfdt.Fdt(open(sys.argv[1], 'rb').read())
want = {
 'PH_RPMHCC': '/soc/rsc@17a00000/drv@2/clock-controller',
 'PH_MMCX_VOTER': '/soc/rsc@17a00000/drv@2/rpmh-regulator-mxclvl/regulator-pm_v6c-s6-mmcx-voter-level',
 'PH_WIDE_AVDD': '/soc/gpio-regulator@1', 'PH_FRONT_AVDD': '/soc/gpio-regulator@3',
 'PH_CCI_SCL1_ACT': '/soc/pinctrl@f000000/uke_cci_i2c_scl1_active', 'PH_CCI_SDA1_ACT': '/soc/pinctrl@f000000/uke_cci_i2c_sda1_active',
 'PH_CCI_SCL1_SUS': '/soc/pinctrl@f000000/uke_cci_i2c_scl1_suspend', 'PH_CCI_SDA1_SUS': '/soc/pinctrl@f000000/uke_cci_i2c_sda1_suspend',
 'PH_WIDE_RST_ACT': '/soc/pinctrl@f000000/cam_sensor_wide_active_rst', 'PH_WIDE_RST_SUS': '/soc/pinctrl@f000000/cam_sensor_wide_suspend_rst',
 'PH_FRONT_RST_ACT': '/soc/pinctrl@f000000/cam_sensor_front_active_rst', 'PH_FRONT_RST_SUS': '/soc/pinctrl@f000000/cam_sensor_front_suspend_rst',
}
out = ['/* GENERADO por build.sh a partir de la base; no editar */']
for k, p in want.items():
    out.append('#define %s 0x%x' % (k, fdt.get_phandle(fdt.path_offset(p))))
open(sys.argv[2], 'w').write('\n'.join(out) + '\n')
PY
cat "$OUT/uke-cam-ph.h" | sed 's/^/   /'

say "2. overlays (cpp + dtc -@; cualquier aviso es un fallo)"
STAGES=(camcc rear camss front)
CPPX=${CPPX:-}   # p.ej. CPPX=-DWITH_IOMMU para el overlay de camss de C5b (kernel con 0046)
# avisos inherentes a un fragmento de overlay (no ve #address-cells/interrupt-parent del destino): la validez la comprueban fdtoverlay y check-cam.py
DTCW="-Wno-reg_format -Wno-avoid_default_addr_size -Wno-avoid_unnecessary_addr_size -Wno-interrupts_property -Wno-unique_unit_address -Wno-pci_device_reg -Wno-pci_device_bus_num -Wno-simple_bus_reg -Wno-i2c_bus_reg -Wno-spi_bus_reg -Wno-graph_port"
for v in "${STAGES[@]}"; do
	cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp $CPPX -I "$KT/include" -I "$OUT" "$HERE/dts/uke-cam-$v.dtso" -o "$T/$v.pp.dts"
	# la cabecera de phandles solo se incluye donde hace falta (los dtso usan los PH_* por nombre)
	dtc -@ $DTCW -I dts -O dtb -o "$OUT/uke-cam-$v.dtbo" "$T/$v.pp.dts" 2> "$T/$v.err" || { cat "$T/$v.err"; exit 1; }
	[ -s "$T/$v.err" ] && { cat "$T/$v.err"; bad "dtc con avisos en $v"; }
	printf '   uke-cam-%-6s.dtbo %5d B  sha256 %s\n' "$v" "$(stat -c %s "$OUT/uke-cam-$v.dtbo")" "$(sha256sum "$OUT/uke-cam-$v.dtbo" | cut -c1-16)"
done

say "3. fdtoverlay acumulativo sobre la base + comprobaciones"
args=(); for v in "${STAGES[@]}"; do args+=("$OUT/uke-cam-$v.dtbo"); done
fdtoverlay -i "$BASE" -o "$OUT/merged.dtb" "${args[@]}" || bad "fdtoverlay (las 4 etapas en orden)"
for n in 1 2 3; do  # tambien cada prefijo, que es lo que ocurre en la tablet etapa a etapa
	fdtoverlay -i "$BASE" -o "$T/p$n.dtb" "${args[@]:0:$n}" || bad "fdtoverlay prefijo de $n etapas"; done
[ -s "$OUT/merged.dtb" ] && { python3 "$HERE/check-cam.py" "$BASE" "$OUT/merged.dtb" | tee "$OUT/check-cam.txt" | tail -n 70 || bad "check-cam.py"; }
grep -q 'RESULTADO: OK' "$OUT/check-cam.txt" || bad "check-cam.py no termina en OK"

if [ "$QUICK" = 0 ]; then
	say "4. modulos (make -C <senemos-build> M=<stage> LLVM=1 ARCH=arm64), en una carpeta de trabajo limpia"
	S=$T/stage; mkdir -p "$S/blobs"
	python3 -I "$HERE/patches/gen-modules.py" "$KT" "$S" | sed 's/^/   /'
	cp "$HERE"/module/*.c "$HERE/module/Kbuild" "$S/"; cp "$OUT"/uke-cam-*.dtbo "$S/blobs/"
	fp() { stat -c '%Y %s' "$KB/Module.symvers" "$KB/.config"; }; F0=$(fp)
	env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL MAKE=/usr/bin/make ARCH=arm64 LLVM=1 UKE_OVL_DIR="$S/blobs" UKE_OVL_INC="$BT" \
		/usr/bin/make -C "$KB" M="$S" modules > "$S/make.log" 2>&1 || { tail -n 40 "$S/make.log"; exit 1; }
	[ "$F0" = "$(fp)" ] || bad "el arbol de build del kernel cambio"
	for m in uke_cam_camcc uke_cam_rear uke_cam_camss uke_cam_front camcc-cliffs-uke uke_ov13b10 uke_ov08d10 uke-camss; do
		[ -s "$S/$m.ko" ] && [ "$S/$m.ko" -nt "$S/Kbuild" ] || { bad "no se genero $m.ko (¿make no-op?)"; continue; }
		vm=$(modinfo -F vermagic "$S/$m.ko" | cut -d' ' -f1); [ "$vm" = "$KREL" ] || bad "$m.ko vermagic $vm != $KREL"
		cp "$S/$m.ko" "$OUT/"; printf '   %-18s %7d B  vermagic %s  depends=%s\n' "$m.ko" "$(stat -c %s "$S/$m.ko")" "$vm" "$(modinfo -F depends "$S/$m.ko")"
	done
	grep -Ei 'warning|error' "$S/make.log" | grep -v 'Entering\|Leaving' > "$OUT/make-warnings.txt" || true
	printf '   avisos de compilacion: %s\n' "$(wc -l < "$OUT/make-warnings.txt")"
	cp "$S/camcc-cliffs-uke.c" "$S/uke_ov13b10.c" "$S/uke_ov08d10.c" "$OUT/" 2>/dev/null || true
fi

say "5. manifiesto"
if [ "$OUT" != "$HERE/out" ]; then echo "   (OUT personalizado: sin manifiesto; artefactos en $OUT)"; echo; [ "$fails" = 0 ] && { echo "RESULTADO: OK"; exit 0; } || { echo "RESULTADO: FALLOS=$fails"; exit 1; }; fi
( cd "$HERE" && sha256sum dts/*.dtso module/* patches/* check-cam.py build.sh deploy.sh c1-baseline.sh dt-dump.py out/*.dtbo out/merged.dtb out/uke-cam-ph.h out/*.ko 2>/dev/null ) > "$HERE/MANIFEST.sha256"
wc -l "$HERE/MANIFEST.sha256" | sed 's/^/   /'
echo; if [ "$fails" = 0 ]; then echo "RESULTADO: OK"; else echo "RESULTADO: FALLOS=$fails"; exit 1; fi
