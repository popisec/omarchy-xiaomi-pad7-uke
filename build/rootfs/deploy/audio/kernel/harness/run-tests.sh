#!/usr/bin/env bash
# run-tests.sh — pruebas de PC de los parches kernel/000{1,2,3}-*.patch (E0, 18-oct-2026).
# NO toca el arbol del kernel ni la tablet: trabaja en una copia temporal.
#
#  1. aplica 0001 (y 0003) sobre una copia limpia de arch/arm64/kernel/uke-abl.c y compila el arnes
#     (uke_abl_transform en modo usuario, libfdt) para las tres variantes: original / 0001 / 0001+0003;
#  2. sobre el DT capturado live-android-os3.dtb: las tres aceptan; la salida de 0001 difiere de la original
#     en UNA linea (status del i2c@88c000); 0001+0003 == 0001 cuando no hay audio horneado;
#  3. 14 mutaciones del DT de entrada: la original las acepta, 0001 las rechaza;
#  4. audio horneado (overlays E2+E4 sobre el DT de entrada): original y 0001 dejan `dais` disabled, 0003 lo admite
#     solo con los SIDs exactos (con otro SID: disabled y arranque aceptado);
#  5. predicado de la lista blanca del SMMU (0002): test C con el texto de la condicion sacado del fichero parcheado.
# Uso: run-tests.sh [dir-con-los-.dtbo]   (por defecto ../../out); imprime "RESULTADO: OK" o sale con 1.
set -Eeuo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
KDIR=$(cd "$HERE/.." && pwd)                       # .../deploy/audio/kernel
R=${R:-"$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"}
KT=${KT:-$R/build/kernel-pokes/senemos-7.2.9/linux-7.2.9}
DTDIR=${DTDIR:-$R/build/kernel-pokes/senemos-7.2.9/dt}
IN=$DTDIR/live-android-os3.dtb
DTBO=${1:-$KDIR/../out}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
bad() { echo "FALLO: $*"; fails=$((fails + 1)); }

[ -f "$IN" ] || { echo "falta $IN"; exit 2; }
command -v gcc >/dev/null && command -v fdtput >/dev/null && command -v dtc >/dev/null || { echo "faltan gcc/dtc/fdtput"; exit 2; }

# --- 1. variantes -----------------------------------------------------------------------------------
for v in orig m1 m3; do mkdir -p "$T/$v/arch/arm64/kernel"; cp "$KT/arch/arm64/kernel/uke-abl.c" "$T/$v/arch/arm64/kernel/"; done
(cd "$T/m1" && patch -s -p1 < "$KDIR/0001-uke-abl-admit-qup1-i2c4-amps.patch")
(cd "$T/m3" && patch -s -p1 < "$KDIR/0001-uke-abl-admit-qup1-i2c4-amps.patch" && patch -s -p1 < "$KDIR/0003-uke-abl-admit-baked-lpass-audio-client.patch")
for v in orig m1 m3; do
	gcc -O1 -Wall -Wextra -Wno-unused-parameter -Werror -DUKE_ABL_C="\"$T/$v/arch/arm64/kernel/uke-abl.c\"" \
		-I"$KT/arch/arm64/kernel" "$HERE/uke-abl-harness.c" -lfdt -o "$T/h-$v"
done
echo "1. arnes compilado (orig, 0001, 0001+0003) sin avisos con -Wall -Wextra -Werror"

run() { "$T/h-$1" "$2" "$3" | head -1 || true; }   # el arnes sale 1 al rechazar: no abortar por pipefail

# --- 2. DT capturado --------------------------------------------------------------------------------
for v in orig m1 m3; do
	r=$(run $v "$IN" "$T/out-$v.dtb")
	[[ $r == *"= 1 "* ]] || bad "$v no acepta el DT capturado: $r"
	dtc -I dtb -O dts -o "$T/out-$v.dts" "$T/out-$v.dtb" 2>/dev/null
done
n=$(diff "$T/out-orig.dts" "$T/out-m1.dts" | grep -c '^[<>]' || true)
d=$(diff "$T/out-orig.dts" "$T/out-m1.dts" | grep '^[<>]' | tr -s '\t ' ' ' | tr '\n' ';' || true)
[ "$n" -eq 2 ] && [[ $d == *'< status = "disabled";'*'> status = "ok";'* ]] \
	&& echo "2. salida 0001 vs original: 1 linea cambiada ($d)" || bad "diff original/0001 inesperado ($n lineas: $d)"
cmp -s "$T/out-m1.dts" "$T/out-m3.dts" && echo "2. 0001+0003 == 0001 sobre el DT sin audio horneado" || bad "0003 cambia la salida sin audio horneado"
st=$(fdtget -t s "$T/out-m1.dtb" /soc/qcom,qupv3_1_geni_se@8c0000/i2c@88c000 status)
[ "$st" = ok ] || bad "i2c@88c000 con 0001 no queda ok: $st"
st=$(fdtget -t s "$T/out-m1.dtb" /soc/qcom,qupv3_1_geni_se@8c0000/spi@88c000 status)
[ "$st" = disabled ] || bad "spi@88c000 (misma direccion) no queda disabled: $st"

# --- 3. mutaciones ----------------------------------------------------------------------------------
B=/soc/qcom,qupv3_1_geni_se@8c0000/i2c@88c000
P=/soc/pinctrl@f000000/qupv3_se11_i2c_pins/qupv3_se11_i2c_sda_active/mux
muts=0
mut() { # nombre, args de fdtput (sin el fichero)
	local name=$1; shift
	cp "$IN" "$T/neg.dtb"; fdtput "$T/neg.dtb" "$@" >/dev/null 2>&1 || { bad "fdtput fallo en '$name'"; return; }
	local a b; a=$(run orig "$T/neg.dtb" "$T/o.dtb"); b=$(run m1 "$T/neg.dtb" "$T/o.dtb")
	muts=$((muts + 1))
	[[ $a == *"= 1 "* && $b == *RECHAZADO* ]] && printf '   %-44s original: aceptado   0001: RECHAZADO\n' "$name" \
		|| bad "mutacion '$name': original=[$a] 0001=[$b]"
}
echo "3. mutaciones del DT de entrada:"
mut "dmas: SE 3->2"              -t x $B dmas 228 0 2 3 40 2 228 1 2 3 40 2
mut "dmas: protocolo I2C->SPI"   -t x $B dmas 228 0 3 1 40 2 228 1 3 1 40 2
mut "interconnects != bus KTZ"   -t x $B interconnects 1d8 25 1d8 23d 1a2 2 1a3 21d 189 7 188 201
mut "interrupts SPI 585->586"    -t x $B interrupts 0 24a 4
mut "reg 0x88c000->0x890000"     -t x $B reg 890000 4000
mut "compat del bus != geni-i2c" -t s $B compatible qcom,spi-geni
mut "amp 0x34 -> reg 0x38"       -t x $B/fs19xx_smartpa@34 reg 38
mut "amp 0x35 -> reg 0x34 (dup)" -t x $B/fs19xx_smartpa@35 reg 34
mut "amp compat distinto"        -t s $B/fs19xx_smartpa@36 compatible foo,bar
mut "amp reset-gpio 30->31"      -t x $B/fs19xx_smartpa@34 reset-gpio 16b 1f 0
mut "amp irq-gpio flags->0"      -t x $B/fs19xx_smartpa@37 irq-gpio 16b 81 0
mut "pin SDA gpio44->46"         -t s $P pins gpio46
mut "pin SDA funcion->gpio"      -t s $P function gpio
cp "$IN" "$T/neg.dtb"; fdtput -c "$T/neg.dtb" $B/fs19xx_smartpa@38 >/dev/null
a=$(run orig "$T/neg.dtb" "$T/o.dtb"); b=$(run m1 "$T/neg.dtb" "$T/o.dtb"); muts=$((muts + 1))
[[ $a == *"= 1 "* && $b == *RECHAZADO* ]] && printf '   %-44s original: aceptado   0001: RECHAZADO\n' "quinto amplificador (hijo extra)" \
	|| bad "mutacion 'quinto amplificador': original=[$a] 0001=[$b]"
[ "$muts" -eq 14 ] || bad "se esperaban 14 mutaciones, hubo $muts"

# --- 4. audio horneado ------------------------------------------------------------------------------
if [ -f "$DTBO/uke-audio-e2-gpr.dtbo" ] && [ -f "$DTBO/uke-audio-e4-dais.dtbo" ]; then
	D=/soc/remoteproc-adsp@03000000/glink-edge/qcom,gpr/service@1/dais
	fdtoverlay -i "$IN" -o "$T/baked.dtb" "$DTBO/uke-audio-e2-gpr.dtbo" "$DTBO/uke-audio-e4-dais.dtbo"
	for v in orig m1 m3; do run $v "$T/baked.dtb" "$T/baked-$v.dtb" >/dev/null; done
	so=$(fdtget -t s "$T/baked-orig.dtb" $D status 2>&1 || true); s1=$(fdtget -t s "$T/baked-m1.dtb" $D status 2>&1 || true)
	s3=$(fdtget -t s "$T/baked-m3.dtb" $D status 2>&1 || true)
	[ "$so" = disabled ] && [ "$s1" = disabled ] && echo "4. horneado: original y 0001 dejan dais en '$so' (el transform lo corta)" \
		|| bad "horneado: original=[$so] 0001=[$s1], se esperaba disabled"
	[[ $s3 == *FDT_ERR_NOTFOUND* ]] && echo "4. horneado + 0003: dais sin status (habilitado)" || bad "horneado + 0003: dais status=[$s3]"
	cp "$T/baked.dtb" "$T/neg2.dtb"; fdtput -t x "$T/neg2.dtb" $D iommus 129 1002 80 129 1061 0
	r=$(run m3 "$T/neg2.dtb" "$T/o2.dtb"); s=$(fdtget -t s "$T/o2.dtb" $D status 2>&1 || true)
	[[ $r == *"= 1 "* && $s == disabled ]] && echo "4. horneado + 0003 con SID 0x1002: dais disabled, arranque aceptado" \
		|| bad "SID erroneo: transform=[$r] status=[$s]"
else
	echo "4. (omitido: faltan los .dtbo en $DTBO; ejecuta build.sh antes)"
fi

# --- 5. lista blanca del SMMU (0002) ----------------------------------------------------------------
mkdir -p "$T/smmu/drivers/iommu/arm/arm-smmu"
cp "$KT/drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c" "$T/smmu/drivers/iommu/arm/arm-smmu/"
(cd "$T/smmu" && cp drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c before.c && patch -s -p1 < "$KDIR/0002-uke-smmu-admit-lpass-audio-sids.patch")
python3 - "$T/smmu" <<'PY'
import re, sys
d = sys.argv[1]
def cond(path):
    s = open(path).read()
    m = re.search(r'\t\tif \((sid != 0x40.*?)\)\n\t\t\treturn dev_err_probe\(dev, -EOPNOTSUPP, "outside Uke boot SMMU scope', s, re.S)
    c = m.group(1).replace('of_device_is_compatible(smmu->dev->of_node, "qcom,sm7675-boot-smmu")', 'boot')
    return c
for tag, path in (("before", d + "/before.c"), ("after", d + "/drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c")):
    open(f"{d}/{tag}.h", "w").write("static int rejected_%s(unsigned int sid, int boot) { return %s; }\n" % (tag, cond(path)))
PY
cat > "$T/smmu/t.c" <<'EOF'
#include <stdio.h>
#include "before.h"
#include "after.h"
int main(void)
{
	/* sid, boot-smmu, esperado antes (1=rechazado), esperado despues */
	static const struct { unsigned int sid; int boot, before, after; const char *why; } t[] = {
		{ 0x801001, 1, 1, 0, "audio 0x1001/0x80 con boot-smmu" },
		{ 0x1061,   1, 1, 0, "audio 0x1061/0 con boot-smmu" },
		{ 0x801001, 0, 1, 1, "audio sin compat boot-smmu: sigue rechazado" },
		{ 0x1061,   0, 1, 1, "audio sin compat boot-smmu: sigue rechazado" },
		{ 0x1001,   1, 1, 1, "0x1001 SIN mascara: rechazado" },
		{ 0x1062,   1, 1, 1, "SID vecino 0x1062: rechazado" },
		{ 0x801000, 1, 1, 1, "0x1000/0x80: rechazado" },
		{ 0x881001, 1, 1, 1, "mascara 0x88: rechazado" },
		{ 0x11400,  1, 0, 0, "WLAN 0x1400/1: sigue admitido" },
		{ 0x423,    1, 0, 0, "QUP1 wrapper: sigue admitido" },
		{ 0x40,     0, 0, 0, "USB: sigue admitido" },
		{ 0xb6,     0, 0, 0, "GPI0: sigue admitido" },
	};
	int bad = 0;
	for (unsigned i = 0; i < sizeof(t) / sizeof(t[0]); i++) {
		int b = rejected_before(t[i].sid, t[i].boot), a = rejected_after(t[i].sid, t[i].boot);
		printf("   sid 0x%06x boot=%d antes=%-9s despues=%-9s %s%s\n", t[i].sid, t[i].boot, b ? "rechazado" : "admitido",
		       a ? "rechazado" : "admitido", t[i].why, (b == t[i].before && a == t[i].after) ? "" : "   <-- NO ESPERADO");
		bad += !(b == t[i].before && a == t[i].after);
	}
	return bad;
}
EOF
gcc -O0 -Wall -o "$T/smmu/t" "$T/smmu/t.c" -I"$T/smmu"
echo "5. lista blanca del SMMU (condicion copiada del fichero parcheado):"
"$T/smmu/t" || bad "predicado SMMU: resultados no esperados"

echo "RESULTADO: $([ $fails -eq 0 ] && echo OK || echo "$fails FALLO(S)")"
[ $fails -eq 0 ]
