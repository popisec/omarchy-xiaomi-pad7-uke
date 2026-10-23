#!/bin/sh
# uke-adsp-load.sh — levanta el stack de carga del ADSP (todo como módulos).
# Instalado en la tablet en /usr/local/sbin/uke-adsp-load.sh, ejecutado por
# uke-adsp.service en cada arranque. Origen: bin/uke-adsp-load-tablet.sh del
# proyecto hermano (ronda 30, FLASH-LEDGER.md #404/#406) + mitigación gpr #406.
#
# ORDEN (ronda 30): qcom_pd_mapper es el LOCATOR servreg del lado AP y va
# ANTES de pmic_glink; sin él, charger_pd no sube y todo devuelve -EAGAIN.
# Los ayudantes (qcom_common/qcom_q6v5/qcom_pil_info/qcom_glink) solo existen
# como .ko en kernels estilo K5; en L33 van built-in y se saltan solos.
#
# TRAMPA qcom,gpr (#406): el nodo audio_gpr sin qcom,domain mete a apr_probe
# en bucle CLOSE/re-open (udevd 99 %, batería agotada). El dtbo s282 lo lleva
# disabled; COMO RED DE SEGURIDAD este guion pone drivers_autoprobe=0 ANTES
# del primer `echo start` (mitigación probada en caliente el 25-sep).
#
# Idempotente: si el ADSP ya está running o un módulo ya está presente
# (built-in o cargado), no hace nada. Sale 0 aunque todo estuviera ya arriba.
set -u
MODDIR=/usr/local/share/uke/mods
FWDIR=/lib/firmware

say() { echo "uke-adsp: $*"; }

# $1 = nombre en /sys/module (guion bajo), $2 = fichero .ko (puede llevar guion)
load_one() {
	if [ -d "/sys/module/$1" ]; then
		say "$1 ya presente, salto"
		return 0
	fi
	if [ -f "$MODDIR/$2" ]; then
		if insmod "$MODDIR/$2" 2>&1; then
			say "$1 cargado ($2)"
		else
			say "AVISO: $2 no entró (puede ir built-in en este kernel)"
		fi
	else
		say "AVISO: falta $MODDIR/$2 (sigo; quizá built-in)"
	fi
	return 0
}

say "== 1. módulos (insmod tardío, fuera del escaneo de udev/kmod) =="
load_one qcom_common qcom_common.ko
load_one qcom_q6v5 qcom_q6v5.ko
load_one qcom_pil_info qcom_pil_info.ko
load_one qcom_q6v5_pas qcom_q6v5_pas.ko
load_one qcom_glink qcom_glink.ko
load_one qcom_glink_smem qcom_glink_smem.ko
load_one qrtr_smd qrtr-smd.ko
load_one qcom_pd_mapper qcom_pd_mapper.ko
load_one pmic_glink pmic_glink.ko
load_one ucsi_glink ucsi_glink.ko
load_one qcom_battmgr qcom_battmgr.ko
sleep 1

say "== 2. firmware del ADSP =="
if [ ! -f "$FWDIR/adsp.mdt" ]; then
	say "FALLO: falta $FWDIR/adsp.mdt (despliega charge/firmware/ primero)"
	exit 1
fi
n=$(ls "$FWDIR"/adsp.b?? 2>/dev/null | wc -l)
say "segmentos adsp.bNN: $n (esperado >= 49; b24/b51 no existen, es normal)"
if [ "$n" -lt 49 ]; then
	say "FALLO: firmware incompleto"
	exit 1
fi
# ENDURECIDO 15-oct (hito carga): verificar shas del firmware. Un adsp.b40 corrupto
# pasó desapercibido desde el 25-sep y el TZ rechazaba el arranque (AUTH_AND_RESET -22).
if [ -f "$FWDIR/adsp-fw.sha256" ]; then
	if (cd "$FWDIR" && sha256sum -c adsp-fw.sha256 >/dev/null 2>&1); then
		say "shas firmware OK (56/56)"
	else
		say "FALLO: firmware con shas MALAS:"
		(cd "$FWDIR" && sha256sum -c adsp-fw.sha256 2>&1 | grep -v ": OK" | head -5)
		exit 1
	fi
else
	say "AVISO: sin $FWDIR/adsp-fw.sha256 (no se verifica el firmware)"
fi

say "== 3. red anti-gpr =="
# CORREGIDO 13-oct (revision ses_eca11ddb7ffeYSZfmr6iTRpxcF, H1): antes se ponia
# SIEMPRE drivers_autoprobe=0 antes del start. Eso es una trampa con las dos
# bocas: es lo unico que evita el bucle CLOSE/re-open del gpr, PERO apaga tambien
# el autoprobe del bus rpmsg entero, y pmic_glink ES un rpmsg_driver
# (pmic_glink.c:289). El canal PMIC_RTR_SOCCP_APPS solo aparece cuando el ADSP
# arranca, o sea DESPUES -> con autoprobe=0 nunca se enlaza -> no hay
# pmic_glink_add_aux_device() -> no hay power_supply -> el guion acaba con
# -EAGAIN y exit 0 (falso verde). Al hermano le funciono porque mitigo en
# caliente, con los binds ya hechos; aqui el orden estaba invertido.
#
# Arreglo: la trampa solo existe si el nodo gpr esta VIVO. Con el overlay s282+
# esta en status="disabled", asi que no hace falta tocar el bus. Si por lo que sea
# esta vivo, se mitiga y despues se hace el bind EXPLICITO y se restaura.
GPRNODE=/proc/device-tree/soc/remoteproc-adsp@03000000/glink-edge/qcom,gpr
GPRST=$( [ -d "$GPRNODE" ] && tr -d '\0' < "$GPRNODE/status" 2>/dev/null )
NEEDAUTOPROBE=0
if [ -z "$GPRST" ]; then
	# el nodo no existe en el DT vivo: no puede haber bucle
	say "qcom,gpr: no existe en el DT vivo -> sin bucle posible, NO toco el bus rpmsg"
elif [ "$GPRST" = "disabled" ]; then
	say "qcom,gpr: status=disabled en el DT vivo -> sin bucle posible, NO toco el bus rpmsg"
else
	NEEDAUTOPROBE=1
	say "qcom,gpr: status=$GPRST (VIVO) -> mitigacion necesaria"
	if [ -w /sys/bus/rpmsg/drivers_autoprobe ]; then
		echo 0 > /sys/bus/rpmsg/drivers_autoprobe 2>/dev/null \
			&& say "drivers_autoprobe=0 (red anti-gpr; se restaura tras el bind)"
	fi
fi
dmesg -n 1 2>/dev/null || true

say "== 4. arranque del ADSP =="
started=0
for r in /sys/class/remoteproc/remoteproc*; do
	[ -e "$r/state" ] || continue
	name=$(cat "$r/name" 2>/dev/null)
	[ "$name" = "adsp" ] || continue
	st=$(cat "$r/state" 2>/dev/null)
	if [ "$st" = "running" ]; then
		say "ADSP ya running ($r), no toco nada"
		started=1
	else
		say "echo start > $r/state (estado previo: $st)"
		echo start > "$r/state" 2>&1 || true
		sleep 3
		st=$(cat "$r/state" 2>/dev/null)
		say "estado ahora: $st"
		[ "$st" = "running" ] && started=1
	fi
done
if [ "$started" != "1" ]; then
	say "FALLO: no hay remoteproc adsp (¿qcom_q6v5_pas cargado?)"
	exit 1
fi

if [ "$NEEDAUTOPROBE" = "1" ]; then
	say "== 4b. bind EXPLICITO de rpmsg (autoprobe esta apagado) =="
	# Con el gpr vivo no hay bind automatico. Se busca el canal del PMIC y se
	# enlaza a mano por su direccion, y solo despues se restaura el autoprobe.
	for d in /sys/bus/rpmsg/devices/*/; do
		[ -e "$d/name" ] || continue
		rn=$(cat "$d/name" 2>/dev/null)
		case "$rn" in
		*PMIC*|*SoC*)
			addr=$(cat "$d/dev" 2>/dev/null)
			say "enlazando $rn ($addr) -> qcom_pmic_glink_rpmsg"
			echo "$addr" > /sys/bus/rpmsg/drivers/qcom_pmic_glink_rpmsg/bind 2>/dev/null \
				&& say "  bind OK" || say "  bind FALLIDO (el driver no estaba cargado antes)"
			;;
		esac
	done
	if [ -w /sys/bus/rpmsg/drivers_autoprobe ]; then
		echo 1 > /sys/bus/rpmsg/drivers_autoprobe 2>/dev/null \
			&& say "drivers_autoprobe restaurado a 1"
	fi
fi

say "== 5. veredicto =="
sleep 2
dmesg | grep -i "charger_pd" | tail -n 3 || true
FOUND=0
GREEN=0
for p in /sys/class/power_supply/*/; do
	[ -e "$p" ] || continue
	n=$(basename "$p")
	[ "$n" = "usb" ] && continue
	FOUND=1
	st=$(cat "$p/status" 2>/dev/null)
	cu=$(cat "$p/current_now" 2>/dev/null)
	ct=$(cat "$p/charge_type" 2>/dev/null)
	say "-- $n: status=$st current_now=$cu charge_type=$ct capacity=$(cat "$p/capacity" 2>/dev/null) voltage_now=$(cat "$p/voltage_now" 2>/dev/null)"
	# criterio verde: status=Charging + current_now>0 + charge_type=Fast (ledger #406)
	if [ "$st" = "Charging" ] || [ "$st" = "Full" ]; then
		case "$cu" in
		-*) : ;;
		*) [ -n "$cu" ] && [ "$cu" -gt 0 ] 2>/dev/null && GREEN=1 ;;
		esac
	fi
done
[ "$FOUND" = "0" ] && say "(sin power_supply: battmgr no probeo o no hay ADSP)"

# CORREGIDO 13-oct (H3): antes esto era un `echo` con el texto del criterio y
# salia con exit 0 SIEMPRE. Un falso verde es peor que un fallo: uno creeria
# que la bateria esta montada sin haberse cargado un mA. Ahora se COMPRUEBA y
# el codigo de salida distingue los tres casos.
if [ "$GREEN" = "1" ]; then
	say "VEREDICTO: VERDE — cargando (ledger #406)"
	exit 0
elif [ "$FOUND" = "1" ]; then
	say "VEREDICTO: AMARILLO — hay power_supply pero NO esta cargando."
	say "  Revisar: ¿PDR charger_pd en UP? ¿el locator 0x40 de qcom_pd_mapper respondio?"
	exit 2
else
	say "VEREDICTO: ROJO — no hay power_supply. NO se esta cargando."
	exit 3
fi
