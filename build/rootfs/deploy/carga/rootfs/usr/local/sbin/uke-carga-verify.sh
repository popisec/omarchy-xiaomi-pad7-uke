#!/bin/sh
# uke-carga-verify.sh — checklist de verificación de la pila de carga (kernel senemos).
#   uke-carga-verify.sh --pre            prerrequisitos, SIN efectos (antes de instalar/arrancar)
#   uke-carga-verify.sh [--post]         estado tras uke-carga.service (por defecto)
#   uke-carga-verify.sh --watch N [SEG]  N muestras cada SEG s (def. 6 x 30 s): carga sostenida
# Salida: líneas [OK]/[FALLA]/[AVISO]; código 1 si hay algún FALLA, 0 si no.
# Variables UKE_* solo para pruebas fuera de la tablet (tests/offline-test.sh).
set -u
PATH=${UKE_PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}
REL=${UKE_REL:-$(uname -r)}
SYS=${UKE_SYS:-/sys}
DT=${UKE_DT:-/proc/device-tree}
FWDIR=${UKE_FWDIR:-/lib/firmware}
MODDIR=${UKE_MODDIR:-/lib/modules/$REL}
MR=${UKE_MODROOT:-}	# solo pruebas: modroot del PC (modinfo -b / modprobe -d)
minfo() { if [ -n "$MR" ]; then modinfo -b "$MR" -k "$REL" "$@"; else modinfo -k "$REL" "$@"; fi; }
mprobe() { if [ -n "$MR" ]; then modprobe -d "$MR" -S "$REL" "$@"; else modprobe "$@"; fi; }
MODE=post
case "${1:-}" in
--pre) MODE=pre ;;
--post | "") MODE=post ;;
--watch) MODE=watch ;;
*) echo "uso: $0 [--pre|--post|--watch N [SEG]]"; exit 64 ;;
esac

NOK=0 NFAIL=0 NWARN=0
ok() { NOK=$((NOK + 1)); echo "[OK]    $*"; }
fail() { NFAIL=$((NFAIL + 1)); echo "[FALLA] $*"; }
warn() { NWARN=$((NWARN + 1)); echo "[AVISO] $*"; }
rd() { cat "$1" 2>/dev/null | tr -d '\0\n'; }
isnum() { case "${1:-}" in '' | *[!0-9-]*) return 1 ;; *) return 0 ;; esac; }
BAT=$SYS/class/power_supply/qcom-battmgr-bat
USB=$SYS/class/power_supply/qcom-battmgr-usb
CHAIN="qrtr qrtr_smd qcom_pd_mapper pmic_glink qcom_battmgr qcom_q6v5_pas"

# cargado como .ko (/sys/module/<m>) o built-in (modules.builtin; - y _ equivalen)
modloaded() {
	h=$(echo "$1" | tr _ -)
	[ -d "$SYS/module/$1" ] && return 0
	grep -qE "/($1|$h)\.ko\$" "$MODDIR/modules.builtin" 2>/dev/null
}

gate_kernel() {
	case "$REL" in
	*senemos*) ok "kernel $REL (senemos)" ;;
	*) fail "kernel $REL no es senemos: esta pila es SOLO para ese kernel" ;;
	esac
}

gate_firmware() {
	if [ ! -f "$FWDIR/adsp-fw.sha256" ]; then
		fail "falta $FWDIR/adsp-fw.sha256"
		return
	fi
	if (cd "$FWDIR" && sha256sum -c adsp-fw.sha256 >/dev/null 2>&1); then
		ok "firmware: 56/56 shas OK (adsp.b40 = $(sha256sum "$FWDIR/adsp.b40" | cut -c1-12)…)"
	else
		fail "firmware con shas MALAS (copiar del PC charge/firmware/):"
		(cd "$FWDIR" && sha256sum -c adsp-fw.sha256 2>&1 | grep -v ': OK$' | head -6)
	fi
}

gate_pre() {
	echo "== PRE: prerrequisitos (sin efectos) =="
	gate_kernel
	if [ -f "$MODDIR/modules.dep" ]; then
		ok "$MODDIR/modules.dep existe"
	else
		fail "falta $MODDIR/modules.dep (instalar modroot y depmod -a $REL)"
		return
	fi
	for m in $CHAIN; do
		f=$(minfo -n "$m" 2>/dev/null)
		if [ -z "$f" ]; then
			fail "módulo $m no resoluble (modinfo)"
			continue
		fi
		if [ "$f" = "(builtin)" ]; then
			ok "módulo $m: built-in"
			continue
		fi
		vm=$(minfo -F vermagic "$m" 2>/dev/null | cut -d' ' -f1)
		if [ "$vm" = "$REL" ]; then
			ok "módulo $m: vermagic $vm"
		else
			fail "módulo $m: vermagic '$vm' != uname -r '$REL'"
		fi
	done
	# deps transitivas: que modprobe las resuelva todas (dry-run)
	for m in $CHAIN; do
		if mprobe -n -v "$m" >/dev/null 2>&1; then
			:
		else
			fail "modprobe -n $m falla (dependencia sin resolver)"
		fi
	done
	ok "cadena resuelta con modprobe -n: $CHAIN"
	# DT del ABL transformado por su kernel
	c=$(rd "$DT/soc/remoteproc-adsp@03000000/compatible")
	s=$(rd "$DT/soc/remoteproc-adsp@03000000/status")
	case "$c" in
	*qcom,cliffs-adsp-pas*) ok "DT: remoteproc-adsp compatible=$c status=$s" ;;
	*) fail "DT: remoteproc-adsp@03000000 sin qcom,cliffs-adsp-pas (compatible='$c')" ;;
	esac
	c=$(rd "$DT/pmic-glink/compatible")
	case "$c" in
	*xiaomi,uke-pmic-glink*) ok "DT: /pmic-glink compatible=$c" ;;
	*) fail "DT: falta /pmic-glink xiaomi,uke-pmic-glink (overlay usb2 de su kernel)" ;;
	esac
	if [ -d "$DT/soc/remoteproc-adsp@03000000/glink-edge/qcom,pmic_glink_rpmsg" ]; then
		ok "DT: canal rpmsg PMIC_RTR_ADSP_APPS presente"
	else
		fail "DT: falta glink-edge/qcom,pmic_glink_rpmsg"
	fi
	gate_firmware
	for m in qcom_q6v5_pas apr fastrpc; do
		[ -d "$SYS/module/$m" ] && warn "$m ya cargado ANTES de la prueba (autoload de udev; revisar /etc/modprobe.d/uke-carga.conf)"
	done
	if [ -d "$SYS/class/remoteproc" ] && ls "$SYS"/class/remoteproc/remoteproc* >/dev/null 2>&1; then
		for r in "$SYS"/class/remoteproc/remoteproc*; do
			warn "remoteproc ya presente antes de la prueba: $(rd "$r/name") = $(rd "$r/state")"
		done
	fi
	free=$(df -P / 2>/dev/null | awk 'NR==2{print int($4/1024)}')
	if [ -n "$free" ] && [ "$free" -ge 200 ]; then
		ok "espacio libre en / : ${free} MiB"
	else
		warn "poco espacio libre en / : ${free:-?} MiB (el flood DSI llenó la raíz el 15-oct)"
	fi
	if [ -d "$BAT" ]; then
		ok "ya hay $BAT (pila de carga ya arriba)"
	fi
}

find_adsp() {
	for r in "$SYS"/class/remoteproc/remoteproc*; do
		[ -e "$r/state" ] || continue
		if [ "$(rd "$r/name")" = adsp ] || [ "$(rd "$r/firmware")" = adsp.mdt ]; then
			echo "$r"
			return 0
		fi
	done
	return 1
}

gate_post() {
	echo "== POST: estado de la pila de carga =="
	gate_kernel
	# 1. servicios
	if command -v systemctl >/dev/null 2>&1; then
		st=$(systemctl is-active uke-carga.service 2>/dev/null)
		case "$st" in
		active) ok "uke-carga.service active" ;;
		*) fail "uke-carga.service = $st (journalctl -u uke-carga -b)" ;;
		esac
		st=$(systemctl is-active uke-adsp.service 2>/dev/null)
		case "$st" in
		active) fail "uke-adsp.service (el VIEJO) está active: debe quedar omitido en este kernel" ;;
		*) ok "uke-adsp.service viejo = $st (omitido por ConditionKernelVersion)" ;;
		esac
	fi
	# 2. módulos
	for m in qrtr qrtr_smd qcom_pd_mapper pmic_glink qcom_battmgr qcom_q6v5_pas qcom_sysmon qcom_glink_smem; do
		if modloaded "$m"; then
			ok "módulo $m cargado"
		else
			fail "módulo $m NO cargado"
		fi
	done
	for m in ucsi_glink pmic_glink_altmode apr fastrpc; do
		modloaded "$m" && warn "módulo $m cargado (no hace falta para cargar; ¿autoload?)"
	done
	# 3. firmware
	gate_firmware
	# 4. remoteproc
	R=$(find_adsp)
	if [ -z "$R" ]; then
		fail "no hay remoteproc adsp"
	else
		st=$(rd "$R/state")
		fw=$(rd "$R/firmware")
		if [ "$st" = running ]; then
			ok "remoteproc adsp $R state=running firmware=$fw"
		else
			fail "remoteproc adsp $R state=$st (esperado running; si crashed: echo stop; echo start)"
		fi
	fi
	# 5. dmesg
	if command -v dmesg >/dev/null 2>&1; then
		d=$(dmesg 2>/dev/null)
		echo "$d" | grep -Ei 'remote processor .*is now up|charger_pd' | tail -n 4 | sed 's/^/        /'
		if echo "$d" | grep -q 'charger_pd.*state: 0x1fffffff'; then
			ok "PDR charger_pd UP (0x1fffffff)"
		else
			fail "sin 'PDR … charger_pd … state: 0x1fffffff' en dmesg (¿pd_mapper/qrtr?)"
		fi
		bad=$(echo "$d" | grep -Ei 'Domain ID not specified|auth.*reset.*fail|AUTH_AND_RESET|crash detected in adsp|fatal error received|watchdog bite|Direct firmware load for adsp.*failed|BUG:|Oops|Call trace|battmgr.*unknown message' | head -6)
		if [ -z "$bad" ]; then
			ok "dmesg sin patrones de error (gpr/auth/crash/Oops/firmware)"
		else
			fail "dmesg con errores:"
			echo "$bad" | sed 's/^/        /'
		fi
	fi
	# 6. power_supply
	if [ ! -d "$BAT" ]; then
		fail "falta $BAT (battmgr no probó)"
		ls "$SYS"/class/power_supply/ 2>/dev/null | sed 's/^/        psy: /'
		return
	fi
	ok "power_supply presentes: $(ls "$SYS"/class/power_supply/ | tr '\n' ' ')"
	st=$(rd "$BAT/status")
	v=$(rd "$BAT/voltage_now")
	i=$(rd "$BAT/current_now")
	cap=$(rd "$BAT/capacity")
	echo "        bat: status=$st voltage_now=$v uV current_now=$i uA capacity=$cap% charge_type=$(rd "$BAT/charge_type") temp=$(rd "$BAT/temp") charge_counter=$(rd "$BAT/charge_counter")"
	if isnum "$v" && [ "$v" -gt 0 ]; then
		ok "voltage_now medible: $v uV"
	else
		fail "voltage_now vacío/0 (ADSP arriba pero sin telemetría del gauge)"
	fi
	case "$st" in
	Charging | Full) ok "status=$st" ;;
	*) warn "status=$st (¿cargador de pared conectado? sin cable es Discharging)" ;;
	esac
	if isnum "$i"; then
		echo "        current_now=$i uA (el SIGNO no decide; en CV ~0 es normal)"
	fi
	if [ -d "$USB" ]; then
		echo "        usb: online=$(rd "$USB/online") usb_type=$(rd "$USB/usb_type") input_current_limit=$(rd "$USB/input_current_limit") current_max=$(rd "$USB/current_max")"
		ok "psy usb presente"
	else
		warn "falta qcom-battmgr-usb"
	fi
	if ls "$SYS"/class/udc/* >/dev/null 2>&1; then
		ok "UDC: $(ls "$SYS"/class/udc | tr '\n' ' ')"
	else
		warn "sin UDC (dwc3 espera al psy qcom-battmgr-usb si el DT trae usb-psy-name)"
	fi
}

gate_watch() {
	N=${2:-6}
	S=${3:-30}
	echo "== WATCH: $N muestras cada ${S}s (carga SOSTENIDA: manda voltage_now, no el signo de current_now) =="
	first=""
	last=""
	capf=""
	capl=""
	k=0
	while [ "$k" -lt "$N" ]; do
		v=$(rd "$BAT/voltage_now")
		i=$(rd "$BAT/current_now")
		cap=$(rd "$BAT/capacity")
		st=$(rd "$BAT/status")
		echo "t+$((k * S))s  $st  V=$v uV  I=$i uA  cap=$cap%  usb(online=$(rd "$USB/online") type=$(rd "$USB/usb_type") ilim=$(rd "$USB/input_current_limit"))"
		if isnum "$v" && [ "$v" -gt 0 ]; then
			[ -z "$first" ] && first=$v
			last=$v
		fi
		[ -z "$capf" ] && [ -n "$cap" ] && capf=$cap
		[ -n "$cap" ] && capl=$cap
		k=$((k + 1))
		[ "$k" -lt "$N" ] && sleep "$S"
	done
	if [ -z "$first" ]; then
		fail "sin voltage_now en ninguna muestra"
	else
		d=$((last - first))
		if [ "$d" -gt 0 ]; then
			ok "voltage_now SUBE: ${first} -> ${last} uV (Δ=+${d})"
		elif [ "$d" -eq 0 ]; then
			warn "voltage_now plano (${first} uV): normal en CV o con batería llena; si status=Charging y capacity<95 alarga la ventana"
		else
			fail "voltage_now BAJA: ${first} -> ${last} uV (Δ=${d}) — NO está cargando de verdad"
		fi
		[ -n "$capf" ] && [ -n "$capl" ] && echo "        capacity: ${capf}% -> ${capl}%"
	fi
}

case "$MODE" in
pre) gate_pre ;;
post) gate_post ;;
watch) gate_watch "$@" ;;
esac
echo "== resumen: OK=$NOK AVISO=$NWARN FALLA=$NFAIL =="
[ "$NFAIL" -eq 0 ]
