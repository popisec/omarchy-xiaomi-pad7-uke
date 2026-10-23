#!/usr/bin/env bash
# build-hciqca.sh — compila EN EL PC un hci_uart.ko con el parche de tiempos del WCN6750 (hci_qca-uke-tiempos.patch) y un hci_uart.ko de CONTROL
# (mismas fuentes SIN parche) para comprobar que la reconstruccion fuera del arbol equivale al modulo de serie. No toca la tablet ni el arbol del kernel.
#
#   hciqca/build-hciqca.sh            -> out-hciqca/hci_uart.ko (parcheado) y out-hciqca/hci_uart-control.ko (sin parche)
#
# Entradas (sobreescribibles por entorno): KT = fuente del kernel (solo se LEE drivers/bluetooth), KB = arbol de BUILD (make -C $KB M=<stage>; NO se modifica).
# Por defecto el arbol ouke5 (el kernel v6 de camara conserva la release «ouke5» y tiene el mismo hci_qca.c: sha comprobado). El .ko se instala en
# /usr/lib/modules/<krel>/extra/hci_uart.ko (depmod prefiere extra/ sobre kernel/): sustituye al de serie SIN reflashear; para volver atras, borrar ese fichero + depmod -a.
# Verifica: vermagic == release del arbol; mismos alias y dependencias que el de serie (modroot); mismos simbolos indefinidos que el de serie (control);
# el parcheado solo anade los tres parametros uke_bt_* con defaults 50/50/0 (= serie). Compilacion con LLVM=1 ARCH=arm64 y MAKE explicito (no-op silencioso en primer plano).
set -Eeuo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); BT=$(cd "$HERE/.." && pwd); R=$(cd "$BT/../../../.." && pwd)
KT=${KT:-$R/build/kernel-pokes/senemos-ouke5/linux-7.2.9}
KB=${KB:-$R/build/kernel-pokes/senemos-ouke5/build}
OUT=${OUT:-$BT/out-hciqca}
PATCH=$HERE/hci_qca-uke-tiempos.patch
WANT_SHA=ef9ec1ceaacf   # sha256 (12 primeros) del hci_qca.c de ouke5/ouke6 contra el que se hizo el parche
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0; bad() { echo "FALLO: $*"; fails=$((fails + 1)); }; okm() { printf '   ok  %s\n' "$*"; }; say() { printf '\n== %s\n' "$*"; }
for c in clang ld.lld llvm-nm make modinfo patch sha256sum; do command -v "$c" >/dev/null || { echo "falta $c"; exit 2; }; done
for f in "$KT/drivers/bluetooth/hci_qca.c" "$KB/Module.symvers" "$KB/.config" "$KB/include/config/kernel.release" "$PATCH"; do [ -e "$f" ] || { echo "falta $f"; exit 2; }; done
KREL=$(cat "$KB/include/config/kernel.release"); STOCK=$KB/modroot/lib/modules/$KREL/kernel/drivers/bluetooth/hci_uart.ko
[ -e "$STOCK" ] || { echo "falta el hci_uart.ko de serie en $STOCK"; exit 2; }
[ "$(sha256sum "$KT/drivers/bluetooth/hci_qca.c" | cut -c1-12)" = "$WANT_SHA" ] || { echo "hci_qca.c de $KT no es el que espera el parche ($WANT_SHA)"; exit 2; }
mkdir -p "$OUT"
say "kernel $KREL; objetos de hci_uart segun .config del arbol"
OBJS="hci_ldisc.o"
for pair in SERDEV:hci_serdev H4:hci_h4 BCSP:hci_bcsp LL:hci_ll ATH3K:hci_ath 3WIRE:hci_h5 INTEL:hci_intel BCM:hci_bcm QCA:hci_qca AG6XX:hci_ag6xx MRVL:hci_mrvl AML:hci_aml; do
	grep -q "^CONFIG_BT_HCIUART_${pair%%:*}=y" "$KB/.config" && OBJS="$OBJS ${pair#*:}.o"
done
echo "   $OBJS"
build_stage() { # build_stage DIR [patch]
	local S=$1 P=${2:-}
	rm -rf "$S"; mkdir -p "$S"
	for f in $(echo "$OBJS" | sed 's/\.o/.c/g') hci_uart.h btqca.h btbcm.h btintel.h; do cp "$KT/drivers/bluetooth/$f" "$S/"; done
	if [ -n "$P" ]; then (cd "$S" && patch -p1 -d "$S" --quiet --directory="$S" -i "$P" 2>&1 || true); fi
	printf 'obj-m += hci_uart.o\nhci_uart-y := %s\n' "$OBJS" > "$S/Makefile"
	env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL MAKE=/usr/bin/make ARCH=arm64 LLVM=1 /usr/bin/make -C "$KB" M="$S" modules > "$S/make.log" 2>&1 || { cat "$S/make.log"; return 1; }
	[ -s "$S/hci_uart.ko" ] && [ "$S/hci_uart.ko" -nt "$S/hci_qca.c" ] || { echo "no se genero hci_uart.ko (¿make no-op?)"; return 1; }
	grep -Ei 'warning|error' "$S/make.log" | grep -v 'Entering\|Leaving' > "$S/warn.txt" || true
}
# el parche espera la ruta drivers/bluetooth/hci_qca.c: se aplica sobre un arbol falso con esa estructura y se copia el resultado
apply_patch_stage() {
	local S=$1; local W=$T/patchwork; rm -rf "$W"; mkdir -p "$W/drivers/bluetooth"; cp "$KT/drivers/bluetooth/hci_qca.c" "$W/drivers/bluetooth/"
	(cd "$W" && patch -p1 --quiet -i "$PATCH") || return 1
	cp "$W/drivers/bluetooth/hci_qca.c" "$S/hci_qca.c"
}
say "1. control (sin parche) y parcheado"
build_stage "$T/ctl" || bad "compilacion del control"
rm -rf "$T/pat"; mkdir -p "$T/pat"
for f in $(echo "$OBJS" | sed 's/\.o/.c/g') hci_uart.h btqca.h btbcm.h btintel.h; do cp "$KT/drivers/bluetooth/$f" "$T/pat/"; done
apply_patch_stage "$T/pat" || bad "el parche no aplica"
printf 'obj-m += hci_uart.o\nhci_uart-y := %s\n' "$OBJS" > "$T/pat/Makefile"
env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL MAKE=/usr/bin/make ARCH=arm64 LLVM=1 /usr/bin/make -C "$KB" M="$T/pat" modules > "$T/pat/make.log" 2>&1 || { cat "$T/pat/make.log"; bad "compilacion del parcheado"; }
[ -s "$T/pat/hci_uart.ko" ] && [ "$T/pat/hci_uart.ko" -nt "$T/pat/hci_qca.c" ] || bad "no se genero el hci_uart.ko parcheado"
grep -Ei 'warning|error' "$T/pat/make.log" | grep -v 'Entering\|Leaving' > "$T/pat/warn.txt" || true
for s in ctl pat; do [ -s "$T/$s/warn.txt" ] && { cat "$T/$s/warn.txt"; bad "avisos al compilar ($s)"; }; done
[ "$fails" = 0 ] && okm "compilados sin avisos"
say "2. comparacion con el modulo de serie ($STOCK)"
SVM=$(modinfo -F vermagic "$STOCK")
for s in ctl pat; do
	vm=$(modinfo -F vermagic "$T/$s/hci_uart.ko"); [ "$vm" = "$SVM" ] && okm "$s: vermagic == $vm" || bad "$s: vermagic '$vm' != '$SVM'"
	[ "$(modinfo -F alias "$T/$s/hci_uart.ko" | sort)" = "$(modinfo -F alias "$STOCK" | sort)" ] && okm "$s: mismos alias que el de serie" || bad "$s: alias distintos"
	[ "$(modinfo -F depends "$T/$s/hci_uart.ko")" = "$(modinfo -F depends "$STOCK")" ] && okm "$s: dependencias iguales ($(modinfo -F depends "$STOCK"))" || bad "$s: dependencias distintas"
	[ "$(modinfo -F name "$T/$s/hci_uart.ko")" = hci_uart ] || bad "$s: el nombre del modulo no es hci_uart"
done
undef() { llvm-nm -u "$1" | awk '{print $NF}' | sort -u; }
undef "$STOCK" > "$T/u-stock"; undef "$T/ctl/hci_uart.ko" > "$T/u-ctl"; undef "$T/pat/hci_uart.ko" > "$T/u-pat"
if cmp -s "$T/u-stock" "$T/u-ctl"; then okm "control: mismos simbolos indefinidos que el de serie ($(wc -l < "$T/u-stock"))"; else echo "   diferencias (serie < control):"; diff "$T/u-stock" "$T/u-ctl" | head -8; bad "el control no equivale al de serie en simbolos indefinidos"; fi
EXTRA=$(diff "$T/u-ctl" "$T/u-pat" | grep '^[<>]' || true)
if [ -z "$EXTRA" ]; then okm "parcheado: mismos simbolos indefinidos que el control"
elif [ "$EXTRA" = "> param_ops_uint" ]; then okm "parcheado: solo anade el simbolo param_ops_uint (module_param uint), esperado"
else echo "$EXTRA" | head -8; bad "el parcheado anade simbolos indefinidos inesperados"; fi
parms() { modinfo -F parm "$1" | sed 's/:.*//' | sort | tr '\n' ' '; }
SP=$(parms "$STOCK"); CP=$(parms "$T/ctl/hci_uart.ko"); PP=$(parms "$T/pat/hci_uart.ko")
EXPECT=$(echo "$SP uke_bt_boot_ms uke_bt_low_ms uke_bt_swctrl_ms" | tr ' ' '\n' | grep -v '^$' | sort | tr '\n' ' ')
[ "$CP" = "$SP" ] && okm "control: mismos parametros que el de serie ($SP)" || bad "control: parametros '$CP' != serie '$SP'"
[ "$PP" = "$EXPECT" ] && okm "parcheado: parametros de serie + uke_bt_low_ms, uke_bt_boot_ms, uke_bt_swctrl_ms ($PP)" || bad "parcheado: parametros '$PP' != '$EXPECT'"
say "2b. W=1: el parche no anade avisos respecto al control (los avisos de W=1 que ya trae el codigo de serie no cuentan)"
w1() { # w1 DIR : recompila con W=1 y deja los avisos normalizados (sin numero de linea) en DIR/w1.txt
	local S=$1
	rm -f "$S"/*.o "$S"/*.ko "$S"/.*.cmd 2>/dev/null || true
	env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL MAKE=/usr/bin/make ARCH=arm64 LLVM=1 /usr/bin/make -C "$KB" M="$S" W=1 modules > "$S/make-w1.log" 2>&1 || { tail -5 "$S/make-w1.log"; return 1; }
	grep -E 'warning:' "$S/make-w1.log" | sed -E 's/:[0-9]+:[0-9]+:/:/' | sort > "$S/w1.txt" || true
}
w1 "$T/ctl" && w1 "$T/pat" || bad "compilacion con W=1"
NEW=$(comm -13 "$T/ctl/w1.txt" "$T/pat/w1.txt" || true)
if [ -z "$NEW" ]; then okm "W=1: el parcheado no anade avisos ($(wc -l < "$T/ctl/w1.txt") heredados del codigo de serie)"; else echo "$NEW" | head; bad "W=1: el parche anade avisos"; fi
[ -s "$T/pat/hci_uart.ko" ] || { cp "$OUT/hci_uart.ko" "$T/pat/hci_uart.ko" 2>/dev/null || true; }
say "3. salida"
cp "$T/pat/hci_uart.ko" "$OUT/hci_uart.ko"; cp "$T/ctl/hci_uart.ko" "$OUT/hci_uart-control.ko"
printf '   %s  %s B  sha256 %s\n   %s  %s B  sha256 %s\n' "out-hciqca/hci_uart.ko" "$(stat -c %s "$OUT/hci_uart.ko")" "$(sha256sum "$OUT/hci_uart.ko" | cut -c1-16)" "out-hciqca/hci_uart-control.ko" "$(stat -c %s "$OUT/hci_uart-control.ko")" "$(sha256sum "$OUT/hci_uart-control.ko" | cut -c1-16)"
[ "$fails" = 0 ] && { echo; echo "RESULTADO: OK"; exit 0; } || { echo; echo "RESULTADO: $fails FALLO(S)"; exit 1; }
