#!/usr/bin/env bash
# build.sh — compila y verifica EN EL PC todo lo del Bluetooth de la uke (etapa B0, 18-oct-2026).
# No toca la tablet: ni ssh, ni adb, ni fastboot, ni avahi. Genera out/*.dtbo y out/*.ko y MANIFEST.sha256.
#
#   ./build.sh             todo: overlays + fdtoverlay + arnes + modulos (2 veces, en rutas distintas, para comprobar que es
#                          reproducible) + guarda + service + script
#   ./build.sh --quick     solo overlays, fdtoverlay y arnes de la direccion BD (sin compilar los modulos)
#
# Entradas (rutas por defecto del repo; sobreescribibles por entorno):
#   KT    arbol FUENTE del kernel senemos (solo se LEEN include/dt-bindings y drivers/bluetooth/hci_qca.c)
#   KB    arbol de BUILD del kernel (por defecto el ouke5 —la release de la tablet, v5 y v6—; para el ouke4 de respaldo: KB=build/kernel-pokes/senemos-build
#         KT=build/kernel-pokes/senemos-7.2.9/linux-7.2.9 y OUT=<otra carpeta>, para no pisar out/) (make -C $KB M=<stage>; tiene .config, Module.symvers y scripts/). NO se modifica:
#         se huella antes y despues y se falla si cambia algo.
#   BASE  DT que ve el kernel tras uke-abl.c (la base del audio): build/kernel-pokes/senemos-7.2.9/dt/res-live-final.dtb
# Los modulos se construyen con LLVM=1 ARCH=arm64 (el kernel se hizo con clang 23.1.3 + lld) y MAKE explicito, con el
# entorno de make limpio (MAKEFLAGS/MFLAGS/MAKELEVEL fuera): en primer plano heredado el make puede ser un no-op silencioso,
# por eso el build REEXIGE que existan los .ko y que sean mas nuevos que las fuentes. Lanzalo desprendido si quieres:
#   setsid nohup build/rootfs/deploy/bt/build.sh > /tmp/uke-bt-build.log 2>&1 &
set -Eeuo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
R=${R:-$(cd "$HERE/../../../.." && pwd)}
KT=${KT:-$R/build/kernel-pokes/senemos-ouke5/linux-7.2.9}
KB=${KB:-$R/build/kernel-pokes/senemos-ouke5/build}
BASE=${BASE:-$R/build/kernel-pokes/senemos-7.2.9/dt/res-live-final.dtb}
OUT=${OUT:-$HERE/out}
QUICK=0; [ "${1:-}" = "--quick" ] && QUICK=1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
bad() { echo "FALLO: $*"; fails=$((fails + 1)); }
say() { printf '\n== %s\n' "$*"; }
okm() { printf '   ok  %s\n' "$*"; }

for c in cpp dtc fdtoverlay fdtget python3 clang ld.lld llvm-objcopy llvm-nm llvm-readelf make modinfo sha256sum bash cmp; do
	command -v "$c" >/dev/null || { echo "falta $c"; exit 2; }
done
python3 -c 'import libfdt' 2>/dev/null || { echo "falta pylibfdt (python3 -c 'import libfdt')"; exit 2; }
for f in "$BASE" "$KT/include/dt-bindings/gpio/gpio.h" "$KT/drivers/bluetooth/hci_qca.c" "$KB/Module.symvers" "$KB/.config" "$KB/include/config/kernel.release"; do
	[ -e "$f" ] || { echo "falta $f"; exit 2; }
done
KREL=$(cat "$KB/include/config/kernel.release")
MODALIAS=$(ls "$KB"/modroot/lib/modules/"$KREL"/modules.alias 2>/dev/null | head -1)
REFKO=$KB/modroot/lib/modules/$KREL/kernel/drivers/bluetooth/hci_uart.ko
[ -e "$MODALIAS" ] && [ -e "$REFKO" ] || { echo "falta modroot de $KREL bajo $KB (modules.alias / hci_uart.ko)"; exit 2; }
mkdir -p "$OUT"

say "herramientas y entradas"
echo "   dtc $(dtc --version | sed 's/Version: //')  clang $(clang --version | head -1 | sed 's/.*version //; s/ .*//')  lld $(ld.lld --version | sed 's/LLD \([0-9.]*\).*/\1/')"
echo "   kernel $KREL   base DT $(basename "$BASE") sha256 $(sha256sum "$BASE" | cut -c1-16)…"
echo "   CONFIG_CC_VERSION_TEXT: $(sed -n 's/^CONFIG_CC_VERSION_TEXT=//p' "$KB/.config")"

# ---- 1. overlays ------------------------------------------------------------------------------------------
say "1. compilar overlays (cpp + dtc -@; cualquier aviso de dtc es un fallo)"
declare -A VFLAG=( [uart-only]="-DUART_ONLY" [B]="" [A]="-DWITH_PA_RAIL" )
VARIANTS=(uart-only B A)
for v in "${VARIANTS[@]}"; do
	# shellcheck disable=SC2086
	cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp -I "$KT/include" ${VFLAG[$v]} "$HERE/dts/uke-bt.dtso" -o "$T/$v.pp.dts"
	dtc -@ -I dts -O dtb -o "$OUT/uke-bt-$v.dtbo" "$T/$v.pp.dts" 2> "$T/$v.dtc.err" || { cat "$T/$v.dtc.err"; exit 1; }
	[ -s "$T/$v.dtc.err" ] && { cat "$T/$v.dtc.err"; bad "dtc con avisos en la variante $v"; }
	printf '   uke-bt-%-10s.dtbo %5d B  sha256 %s\n' "$v" "$(stat -c %s "$OUT/uke-bt-$v.dtbo")" "$(sha256sum "$OUT/uke-bt-$v.dtbo" | cut -c1-16)"
done

# ---- 2. fdtoverlay + comprobaciones del resultado --------------------------------------------------------
say "2. fdtoverlay sobre el DT base + check-bt.py (cada propiedad clave, phandles resueltos, nada fuera de la UART)"
for v in "${VARIANTS[@]}"; do
	fdtoverlay -i "$BASE" -o "$T/m-$v.dtb" "$OUT/uke-bt-$v.dtbo" || { bad "fdtoverlay rechaza la variante $v"; continue; }
	python3 -I "$HERE/check-bt.py" "$BASE" "$T/m-$v.dtb" "$v" "$MODALIAS" "$KT/drivers/bluetooth/hci_qca.c" > "$T/check-$v.txt" || bad "check-bt.py variante $v"
	cp "$T/check-$v.txt" "$OUT/check-$v.txt"
	echo "   $(tail -1 "$T/check-$v.txt")   ($(grep -c '^  ok' "$T/check-$v.txt") comprobaciones; detalle en out/check-$v.txt)"
done
UART=/soc/qcom,qupv3_1_geni_se@8c0000/qcom,qup_uart@888000
echo "   claves con fdtget (variante B fusionada):"
printf '     status=%s compatible=%s clock-names=%s\n' "$(fdtget -t s "$T/m-B.dtb" $UART status)" "$(fdtget -t s "$T/m-B.dtb" $UART compatible)" "$(fdtget -t s "$T/m-B.dtb" $UART clock-names)"
printf '     pinctrl-names=%s  pinctrl-0=%s  pinctrl-1=%s\n' "$(fdtget -t s "$T/m-B.dtb" $UART pinctrl-names)" "$(fdtget -t x "$T/m-B.dtb" $UART pinctrl-0 | tr ' ' ',')" "$(fdtget -t x "$T/m-B.dtb" $UART pinctrl-1 | tr ' ' ',')"
printf '     interrupts-extended=%s\n' "$(fdtget -t x "$T/m-B.dtb" $UART interrupts-extended | tr ' ' ',')"
printf '     enable-gpios=%s swctrl-gpios=%s\n' "$(fdtget -t x "$T/m-B.dtb" $UART/bluetooth enable-gpios | tr ' ' ',')" "$(fdtget -t x "$T/m-B.dtb" $UART/bluetooth swctrl-gpios | tr ' ' ',')"
printf '     supplies B: %s\n' "$(for p in vddio vddaon vddbtcxmx vddrfacmn vddrfa0p8 vddrfa1p7 vddrfa1p2; do printf '%s=%s ' "$p" "$(fdtget -t x "$T/m-B.dtb" $UART/bluetooth $p-supply)"; done)"
printf '     supplies A (+PA): vddrfa2p2=%s\n' "$(fdtget -t x "$T/m-A.dtb" $UART/bluetooth vddrfa2p2-supply)"
if fdtget "$T/m-B.dtb" $UART/bluetooth vddrfa2p2-supply >/dev/null 2>&1; then bad "la variante B lleva vddrfa2p2"; else okm "variante B sin vddrfa2p2"; fi
# las variantes son excluyentes por diseno, pero la pila uart-only -> B debe aplicarse (por si se cargan los dos modulos)
fdtoverlay -i "$BASE" -o "$T/stack.dtb" "$OUT/uke-bt-uart-only.dtbo" "$OUT/uke-bt-B.dtbo" 2>/dev/null \
	&& okm "pila uart-only -> B: fdtoverlay la acepta (se deben descargar en orden inverso; las variantes siguen siendo excluyentes)" \
	|| okm "pila uart-only -> B: fdtoverlay la rechaza (variantes excluyentes: descarga una antes de cargar otra)"

# ---- 3. arnes de la direccion BD ------------------------------------------------------------------------
say "3. arnes de la direccion BD (parseo + sustitucion del marcador; clang con ASan/UBSan)"
clang -std=gnu11 -Wall -Wextra -Werror -g -fsanitize=address,undefined -fno-sanitize-recover=all -o "$T/test-patch" "$HERE/harness/test-patch.c"
"$T/test-patch" | tee "$OUT/test-patch.txt" | sed 's/^/   /'
[ "${PIPESTATUS[0]}" -eq 0 ] || bad "test-patch"
for v in "${VARIANTS[@]}"; do
	n=$("$T/test-patch" --count "$OUT/uke-bt-$v.dtbo")
	want=1; [ "$v" = uart-only ] && want=0
	[ "$n" = "$want" ] && okm "uke-bt-$v.dtbo lleva $n marcador(es) local-bd-address" || bad "uke-bt-$v.dtbo lleva $n marcadores (esperado $want)"
done
# direccion de PRUEBA (no es de nadie): parchea el .dtbo B y comprueba con fdtoverlay+fdtget que llega al nodo invertida
TESTADDR=02:11:22:33:44:55
"$T/test-patch" --blob "$OUT/uke-bt-B.dtbo" "$T/B-patched.dtbo" "$TESTADDR"
fdtoverlay -i "$BASE" -o "$T/Bp.dtb" "$T/B-patched.dtbo"
got=$(fdtget -t bx "$T/Bp.dtb" $UART/bluetooth local-bd-address)
[ "$got" = "55 44 33 22 11 2" ] && okm "con $TESTADDR el nodo lleva local-bd-address = $got (LSB primero, como lo lee hci_dev_get_bd_addr_from_property)" || bad "local-bd-address = '$got'"
python3 -I - "$T/Bp.dtb" "$T/m-B.dtb" <<'PY' && okm "el parcheado difiere del B fusionado SOLO en esa propiedad" || bad "el parcheado difiere en mas de local-bd-address"
import sys, libfdt
a = libfdt.Fdt(open(sys.argv[1], "rb").read()); b = libfdt.Fdt(open(sys.argv[2], "rb").read())
p = "/soc/qcom,qupv3_1_geni_se@8c0000/qcom,qup_uart@888000/bluetooth"
def props(f):
    o = f.path_offset(p); d = {}; q = f.first_property_offset(o, libfdt.QUIET_NOTFOUND)
    while q >= 0:
        x = f.get_property_by_offset(q); d[x.name] = bytes(x); q = f.next_property_offset(q, libfdt.QUIET_NOTFOUND)
    return d
da, db = props(a), props(b)
sys.exit(0 if {k for k in set(da) | set(db) if da.get(k) != db.get(k)} == {"local-bd-address"} else 1)
PY

# ---- 4. modulos ---------------------------------------------------------------------------------------------
if [ "$QUICK" -eq 0 ]; then
	say "4. modulos cargadores (make -C <senemos-build> M=<stage> LLVM=1 ARCH=arm64), dos veces en rutas distintas"
	khuella() { (cd "$KB" && sha256sum .config Module.symvers System.map Makefile include/config/kernel.release include/generated/autoconf.h modules.order && find include scripts -type f -newer .config | wc -l); }
	khuella > "$T/kb-before.txt"
	MODS=(uke_bt_uart uke_bt_b uke_bt_a)
	declare -A MODBLOB=( [uke_bt_uart]=uke-bt-uart-only.dtbo [uke_bt_b]=uke-bt-B.dtbo [uke_bt_a]=uke-bt-A.dtbo )
	build_stage() { # build_stage DIR : copia fuentes + dtbo y compila
		local S=$1
		rm -rf "$S"; mkdir -p "$S/blobs"
		cp "$HERE"/module/* "$S/"
		cp "$OUT"/uke-bt-*.dtbo "$S/blobs/"
		env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL MAKE=/usr/bin/make ARCH=arm64 LLVM=1 UKE_OVL_DIR="$S/blobs" \
			/usr/bin/make -C "$KB" M="$S" modules > "$S/make.log" 2>&1 || { cat "$S/make.log"; return 1; }
		local m
		for m in "${MODS[@]}"; do
			[ -s "$S/$m.ko" ] || { echo "no se genero $m.ko (¿make no-op?)"; cat "$S/make.log"; return 1; }
			[ "$S/$m.ko" -nt "$S/$m.c" ] || { echo "$m.ko no es mas nuevo que su fuente"; return 1; }
		done
		grep -Ei 'warning|error' "$S/make.log" | grep -v 'se entra\|se sale\|Entering\|Leaving' > "$S/warn.txt" || true
		return 0
	}
	build_stage "$T/stage1" || { bad "compilacion de los modulos (stage 1)"; }
	build_stage "$T/other-path/stage2-longer-name" || { bad "compilacion de los modulos (stage 2)"; }
	[ -s "$T/stage1/warn.txt" ] && { cat "$T/stage1/warn.txt"; bad "avisos al compilar los modulos"; }
	khuella > "$T/kb-after.txt"
	cmp -s "$T/kb-before.txt" "$T/kb-after.txt" && okm "el arbol de build del kernel no cambio (.config, Module.symvers, System.map, Makefile, autoconf.h, scripts/include)" \
		|| { diff "$T/kb-before.txt" "$T/kb-after.txt" || true; bad "el build de los modulos modifico el arbol de build del kernel"; }

	REFVM=$(modinfo -F vermagic "$REFKO")
	echo "   vermagic de referencia (hci_uart.ko del modroot $KREL): $REFVM"
	[ "$REFVM" = "$KREL SMP preempt mod_unload aarch64" ] || bad "el vermagic de referencia no es el esperado para $KREL"
	for m in "${MODS[@]}"; do
		K=$T/stage1/$m.ko
		cp "$K" "$OUT/$m.ko"
		vm=$(modinfo -F vermagic "$K")
		[ "$vm" = "$REFVM" ] && okm "$m.ko vermagic == $vm" || bad "$m.ko vermagic '$vm' != '$REFVM'"
		[ "$(strings -a "$K" | grep -c "^vermagic=$REFVM\$")" = 1 ] || bad "$m.ko: 'strings' no ve exactamente un vermagic=$REFVM"
		[ "$(modinfo -F depends "$K")" = "" ] && okm "$m.ko sin dependencias de modulos (solo simbolos del nucleo)" || bad "$m.ko depende de otros modulos"
		[ "$(modinfo -F license "$K")" = GPL ] || bad "$m.ko sin licencia GPL (of_overlay_* son EXPORT_SYMBOL_GPL)"
		# todo simbolo sin definir existe en el Module.symvers del kernel
		und=$(llvm-nm -u "$K" | awk '{print $NF}' | sort -u)
		miss=""
		for s in $und; do awk -v s="$s" '$2==s{f=1} END{exit !f}' "$KB/Module.symvers" || miss="$miss $s"; done
		[ -z "$miss" ] && okm "$m.ko: $(echo $und | wc -w) simbolos sin definir, todos en Module.symvers ($(echo $und | tr '\n' ' '))" || bad "$m.ko: simbolos fuera de Module.symvers:$miss"
		for s in of_overlay_fdt_apply of_overlay_remove; do
			awk -v s="$s" '$2==s && $4=="EXPORT_SYMBOL_GPL"{f=1} END{exit !f}' "$KB/Module.symvers" || bad "$s no es EXPORT_SYMBOL_GPL en $KB/Module.symvers"
		done
		# el dtbo embebido == el compilado (seccion .uke_ovl volcada con llvm-objcopy)
		llvm-objcopy --dump-section=.uke_ovl="$T/$m.blob" "$K" "$T/$m.tmp.ko"
		cmp -s "$T/$m.blob" "$OUT/${MODBLOB[$m]}" && okm "$m.ko: el .dtbo embebido (seccion .uke_ovl, $(stat -c %s "$T/$m.blob") B) es byte a byte $(basename "${MODBLOB[$m]}")" \
			|| bad "$m.ko: el .dtbo embebido NO coincide con out/${MODBLOB[$m]}"
		llvm-readelf -S "$K" | grep -E '\.uke_ovl' | grep -q ' A ' || bad "$m.ko: la seccion .uke_ovl no es ALLOC"
		case $m in
			uke_bt_uart) modinfo -F parm "$K" | grep -q . && bad "$m.ko no debe llevar parametros" || true ;;
			*) modinfo -F parm "$K" | grep -q '^bdaddr:' && okm "$m.ko: parametro bdaddr" || bad "$m.ko sin parametro bdaddr" ;;
		esac
		# reproducible: mismo sha256 compilando en otra ruta
		a=$(sha256sum < "$T/stage1/$m.ko"); b=$(sha256sum < "$T/other-path/stage2-longer-name/$m.ko")
		[ "$a" = "$b" ] && okm "$m.ko reproducible (2 builds, rutas distintas): sha256 ${a:0:16}…" || bad "$m.ko NO es reproducible entre rutas"
	done
fi

# ---- manifiesto (antes de la seccion 5: deploy.sh lo verifica; mismo codigo que deploy.sh --regen-manifest) -------------
"$HERE/deploy.sh" --regen-manifest > /dev/null

# ---- 5. guarda, service y scripts ----------------------------------------------------------------------------
say "5. guarda (uke-bootguard + test), unidad, scripts"
for f in "$HERE/build.sh" "$HERE/deploy.sh" "$HERE/root/usr/local/sbin/uke-bt-up.sh" "$HERE/root/usr/lib/systemd/system-sleep/uke-bt-sleep" "$HERE/root/usr/local/sbin/uke-bt-resume" "$HERE/root/usr/local/sbin/uke-bt-wait" "$HERE/harness/test-bt-up.sh" "$HERE/harness/test-bt-sleep.sh" "$HERE/harness/test-bt-wait.sh" "$HERE/harness/test-deploy-sim.sh" "$HERE/harness/test-consumo.sh" "$HERE/harness/test-ciclo.sh" "$HERE/ciclo-prueba.sh" "$HERE/consumo/bt-consumo.sh" "$HERE/hciqca/bt-medir.sh"; do bash -n "$f" || bad "bash -n $f"; done
okm "bash -n build.sh deploy.sh uke-bt-up.sh uke-bt-sleep uke-bt-resume test-bt-up.sh test-bt-sleep.sh test-deploy-sim.sh"
"$HERE/harness/test-bt-wait.sh" > "$OUT/test-bt-wait.txt" 2>&1 && okm "test-bt-wait.sh (espera acotada del escritorio con mocks): $(tail -1 "$OUT/test-bt-wait.txt")" || { tail -25 "$OUT/test-bt-wait.txt"; bad "test-bt-wait.sh"; }
grep -q '^ExecStartPre=-/usr/local/sbin/uke-bt-wait$' "$HERE/root/etc/systemd/system/uke-desktop.service.d/20-uke-bt.conf" && okm "drop-in uke-desktop.service.d: ExecStartPre con '-' (nunca bloquea)" || bad "el drop-in de uke-desktop no usa ExecStartPre=-"
"$HERE/harness/test-bt-sleep.sh" > "$OUT/test-bt-sleep.txt" 2>&1 && okm "test-bt-sleep.sh (gancho de sueno y reanudacion con mocks): $(tail -1 "$OUT/test-bt-sleep.txt")" || { tail -25 "$OUT/test-bt-sleep.txt"; bad "test-bt-sleep.sh"; }
systemd-analyze verify --man=no "$HERE/root/etc/systemd/system/bluetooth.service.d/10-uke-bt.conf" >/dev/null 2>&1 || true
grep -q '^After=uke-bt.service$' "$HERE/root/etc/systemd/system/bluetooth.service.d/10-uke-bt.conf" && grep -q '^Wants=uke-bt.service$' "$HERE/root/etc/systemd/system/bluetooth.service.d/10-uke-bt.conf" \
	&& okm "drop-in bluetooth.service.d: After= y Wants= uke-bt.service" || bad "el drop-in de bluetooth.service no ordena tras uke-bt.service"
AR=$R/build/rootfs/deploy/arranque
grep -qE '^KNOWN="([a-z]+ )*bt( [a-z]+)*"$' "$AR/root/usr/local/sbin/uke-bootguard" && okm "uke-bootguard: KNOWN incluye bt" || bad "uke-bootguard no lista bt en KNOWN"
"$AR/test-bootguard.sh" > "$OUT/test-bootguard.txt" 2>&1 && okm "test-bootguard.sh: $(tail -1 "$OUT/test-bootguard.txt") ($(grep -c '^  OK' "$OUT/test-bootguard.txt") comprobaciones)" || { tail -20 "$OUT/test-bootguard.txt"; bad "test-bootguard.sh"; }
(cd "$AR/root" && sha256sum -c --quiet ../MANIFEST.sha256) && okm "arranque/MANIFEST.sha256 al dia" || bad "arranque/MANIFEST.sha256 desfasado (deploy.sh regen-manifest en arranque/)"
"$HERE/harness/test-bt-up.sh" > "$OUT/test-bt-up.txt" 2>&1 && okm "test-bt-up.sh (flujo de uke-bt-up.sh con mocks): $(tail -1 "$OUT/test-bt-up.txt") ($(grep -c '^  OK' "$OUT/test-bt-up.txt") comprobaciones)" || { tail -20 "$OUT/test-bt-up.txt"; bad "test-bt-up.sh"; }
"$HERE/harness/test-hciqca.sh" > "$OUT/test-hciqca.txt" 2>&1 && okm "test-hciqca.sh (parche hci_qca, bt-medir.sh con mocks, analisis): $(tail -1 "$OUT/test-hciqca.txt")" || { tail -20 "$OUT/test-hciqca.txt"; bad "test-hciqca.sh"; }
"$HERE/harness/test-consumo.sh" > "$OUT/test-consumo.txt" 2>&1 && okm "test-consumo.sh (bt-consumo.sh con bateria/mocks y analisis contra deltas conocidos): $(tail -1 "$OUT/test-consumo.txt")" || { tail -20 "$OUT/test-consumo.txt"; bad "test-consumo.sh"; }
"$HERE/harness/test-ciclo.sh" > "$OUT/test-ciclo.txt" 2>&1 && okm "test-ciclo.sh (orquestador del ciclo de pruebas con ssh SIMULADO: compuertas, etapas, veredicto): $(tail -1 "$OUT/test-ciclo.txt") ($(grep -c '^  OK' "$OUT/test-ciclo.txt") comprobaciones)" || { tail -25 "$OUT/test-ciclo.txt"; bad "test-ciclo.sh"; }
"$HERE/harness/test-deploy-sim.sh" > "$OUT/test-deploy-sim.txt" 2>&1 < /dev/null \
	&& okm "test-deploy-sim.sh (deploy.sh --go/--check/--revert contra un ssh SIMULADO): $(tail -1 "$OUT/test-deploy-sim.txt") ($(grep -c '^  OK' "$OUT/test-deploy-sim.txt") comprobaciones)" \
	|| { tail -30 "$OUT/test-deploy-sim.txt"; bad "test-deploy-sim.sh"; }
# rutas de sysfs del script contra el FUENTE (los mocks comparten supuestos con el script: aqui se contrastan con el kernel)
busname=$(sed -n '/serdev_bus_type = {/,/};/s/.*\.name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$KT/drivers/tty/serdev/core.c")
[ "$busname" = serial ] && grep -q '^SERDEV=$ROOT/sys/bus/serial/devices' "$HERE/root/usr/local/sbin/uke-bt-up.sh" \
	&& okm "uke-bt-up.sh mira /sys/bus/$busname/devices: el bus serdev se llama '$busname' (serdev/core.c); controlador serial%d, dispositivo %s-%d (core.c:503,111)" \
	|| bad "la ruta del bus serdev de uke-bt-up.sh no casa con serdev/core.c (bus '$busname')"
# el vigilante de uke-bt-up.sh contra el FUENTE: reintentos del driver y mensajes que reconoce
QCA=$KT/drivers/bluetooth/hci_qca.c
mr=$(sed -n 's/^#define MAX_INIT_RETRIES[[:space:]]*\([0-9]*\).*/\1/p' "$QCA")
sr=$(sed -n 's/^MAX_INIT_RETRIES=\([0-9]*\).*/\1/p' "$HERE/root/usr/local/sbin/uke-bt-up.sh")
[ -n "$mr" ] && [ "$mr" = "$sr" ] && okm "uke-bt-up.sh: MAX_INIT_RETRIES=$sr == hci_qca.c (el driver reintenta solo; 'Retry BT power ON:0..$((sr - 1))')" || bad "MAX_INIT_RETRIES del script ($sr) != hci_qca.c ($mr)"
miss=""
grep -q 'bt_dev_warn(hdev, "Retry BT power ON:%d", retries)' "$QCA" || miss="$miss Retry"
grep -q 'bt_dev_err(hdev, "failed to open port")' "$QCA" || miss="$miss open-port"
grep -q 'bt_dev_err(hdev, "command 0x%4.4x tx timeout", opcode)' "$KT/net/bluetooth/hci_core.c" || miss="$miss tx-timeout"
grep -q 'Reading QCA version information failed' "$KT/drivers/bluetooth/btqca.c" "$QCA" || miss="$miss read-version"
grep -q 'QCA setup on UART is completed' "$KT/drivers/bluetooth/btqca.c" || miss="$miss setup-completed"
[ -z "$miss" ] && okm "los mensajes que reconoce uke-bt-up.sh existen en el fuente (Retry BT power ON, failed to open port, command tx timeout, Reading QCA version information failed, QCA setup on UART is completed)" || bad "mensajes del driver que el script espera y no estan en el fuente:$miss"
grep -rn 'sys/bus/serdev' "$HERE/root" "$HERE/harness" "$HERE/deploy.sh" "$HERE/dts" | grep -v 'no usa /sys/bus/serdev' > "$T/serdev-refs.txt" \
	&& { cat "$T/serdev-refs.txt"; bad "queda alguna referencia a /sys/bus/serdev (no existe)"; } || okm "ninguna referencia a /sys/bus/serdev (no existe) en root/, harness/, deploy.sh, dts/"
sv=$(timeout 30 systemd-analyze verify --man=no "$HERE/root/etc/systemd/system/uke-bt.service" "$R/build/rootfs/deploy/wifi/root/etc/systemd/system/uke-wifi.service" 2>&1 | grep -i 'uke-bt' | grep -v 'Command .* is not executable\|No such file or directory' || true)
[ -z "$sv" ] && okm "systemd-analyze verify uke-bt.service: sin avisos propios" || { echo "$sv" | sed 's/^/     /'; bad "systemd-analyze verify uke-bt.service"; }
grep -q '^ExecCondition=/usr/local/sbin/uke-bootguard begin bt$' "$HERE/root/etc/systemd/system/uke-bt.service" \
	&& grep -q '^ConditionPathExists=!/etc/uke/no-bt$' "$HERE/root/etc/systemd/system/uke-bt.service" \
	&& grep -q 'After=.*uke-wifi.service' "$HERE/root/etc/systemd/system/uke-bt.service" && okm "uke-bt.service: After=uke-wifi.service, /etc/uke/no-bt, ExecCondition=uke-bootguard begin bt" || bad "uke-bt.service no cumple lo pedido"
for f in msbtfw12.mbn msnv12.bin; do
	exp=$(awk -v f="usr/lib/firmware/qca/$f" '$2==f{print $1}' "$HERE/root/usr/lib/firmware/uke-bt-fw.sha256")
	[ -f "$R/build/android/$f" ] && [ "$(sha256sum < "$R/build/android/$f" | cut -d' ' -f1)" = "$exp" ] && okm "firmware $f (build/android, NO copiado al repo) sha256 ${exp:0:16}… == uke-bt-fw.sha256" || bad "firmware $f no casa con uke-bt-fw.sha256"
done
[ -z "$(find "$HERE" -name 'msbtfw*' -o -name 'msnv*' -o -name '*.mbn' | grep -v 'uke-bt-fw.sha256')" ] && okm "ningun fichero de firmware dentro de deploy/bt/" || bad "hay firmware dentro de deploy/bt/"
if grep -rIE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' "$HERE"/dts "$HERE"/module "$HERE"/root | grep -vE '02:11:22:33:44:55|AA:BB:CC:DD:EE:FF|FF:FF|00:00:00' >/dev/null; then bad "hay algo con pinta de direccion BD en dts/module/root"; else okm "ninguna direccion BD real en dts/, module/ ni root/"; fi

# ---- resultado ------------------------------------------------------------------------------------------------
say "manifiesto (deploy.sh lo verifica antes de cualquier --go)"
(cd "$HERE" && sha256sum -c --quiet MANIFEST.sha256 && echo "   $(wc -l < MANIFEST.sha256) ficheros, MANIFEST.sha256 OK")
echo
echo "RESULTADO: $([ $fails -eq 0 ] && echo OK || echo "$fails FALLO(S)")"
[ $fails -eq 0 ]
