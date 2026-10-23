#!/bin/sh
# uke-carga-start.sh — pila de carga de batería para el kernel MCC45TR/senemos
# (7.2.9-senemos*). Lo ejecuta uke-carga.service en cada arranque.
#
# Sustituye a uke-adsp-load.sh (insmod de .ko palawan por vermagic; NO vale aquí).
# Lo reutilizado del viejo: ritual anti-corrupción del firmware (adsp.b40 se
# corrompió 3 veces y el TZ rechaza el arranque con AUTH_AND_RESET -22), nombre
# del remoteproc por `name`=adsp, veredicto con códigos de salida distintos.
#
# DIFERENCIAS CLAVE con su kernel (leídas en patches/7.2.9, parche 0033):
#  1. El parche 0033 pone auto_boot=true + recovery_disabled=true para el ADSP
#     de xiaomi,uke: CARGAR qcom_q6v5_pas ARRANCA EL ADSP (de forma asíncrona).
#     El "startup stays manual" de 0020/0026 quedó superado por 0033.
#     => la verificación del firmware va ANTES del modprobe de qcom_q6v5_pas, y
#        pas se carga el ÚLTIMO (y se bloquea su autoload por udev: modprobe.d).
#  2. pd_mapper es un driver auxiliary cuyo dispositivo crea qcom_common al
#     preparar el ADSP (0035: MODULE_SOFTDEP pre qcom_pd_mapper): debe estar
#     cargado ANTES. Igual qrtr + qrtr_smd (0035: "preload QRTR transport").
#  3. pmic_glink es "battery-only" (xiaomi,uke-pmic-glink, 0032): sin UCSI ni
#     altmode. NO se carga ucsi_glink (el insmod viejo daba Oops).
#  4. Sin `echo start`: se espera al auto-boot; solo si queda offline se hace UN
#     `echo start` manual (fallback; también cubre un PAS built-in).
#
# Códigos de salida: 0 verde (Charging/Full) · 2 amarillo (psy ok, no carga:
# ¿sin cargador?) · 3 rojo (sin power_supply) · 4 prerrequisito (kernel,
# modules.dep, firmware, modprobe) · 5 ADSP no llegó a running.
#
# Variables UKE_* solo para pruebas fuera de la tablet (tests/offline-test.sh).
set -u
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

REL=${UKE_REL:-$(uname -r)}
SYS=${UKE_SYS:-/sys}
FWDIR=${UKE_FWDIR:-/lib/firmware}
MODDIR=${UKE_MODDIR:-/lib/modules/$REL}
MODPROBE=${UKE_MODPROBE:-modprobe}
KMSG=${UKE_KMSG:-/dev/kmsg}
RUNDIR=${UKE_RUN:-/run}
T_AUTO=${UKE_T_AUTO:-12}	# s esperando el auto-boot antes del `echo start`
T_RUN=${UKE_T_RUN:-45}		# s máximos hasta remoteproc adsp = running
T_PSY=${UKE_T_PSY:-45}		# s máximos hasta qcom-battmgr-bat con voltaje
STATUSF=$RUNDIR/uke-carga.status

# shas del firmware (independientes del manifiesto, por si éste se corrompe)
B40_SHA=42c86837570fabc9cf1504a1f596b7d56305f44e3bbccd3a431be8bf5882b352
MDT_SHA=fd874a8d7520e8363b6345b0d5b0676161b30b4c3a0d6e5561f426bcfed6a622
DTBMDT_SHA=909cf11723a898172b654bbe0675c0c325bc014584733d0cabdfde3b7329f060

say() {
	echo "uke-carga: $*"
	[ -w "$KMSG" ] && echo "uke-carga: $*" > "$KMSG" 2>/dev/null
	return 0
}
status() { echo "$*" >> "$STATUSF" 2>/dev/null; return 0; }
finish() { # $1=resultado $2=código
	say "RESULTADO: $1 (código $2)"
	status "result=$1"
	status "code=$2"
	exit "$2"
}
rd() { cat "$1" 2>/dev/null | tr -d '\0\n'; }

: > "$STATUSF" 2>/dev/null
status "rel=$REL"
status "inicio=$(date +%s 2>/dev/null)"

say "== 0. kernel =="
case "$REL" in
*senemos*) ;;
*)
	say "kernel '$REL' no es senemos: no toco nada (aquí manda uke-adsp.service)"
	status "result=OMITIDO"
	exit 0
	;;
esac

if [ ! -f "$MODDIR/modules.dep" ]; then
	say "FALLO: falta $MODDIR/modules.dep — instala los módulos de ESTE kernel"
	say "       (tar de modroot/lib/modules/$REL con --keep-directory-symlink) y corre: depmod -a $REL"
	finish "SIN-MODULES-DEP" 4
fi
if ! command -v "$MODPROBE" >/dev/null 2>&1; then
	say "FALLO: no hay $MODPROBE (paquete kmod)"
	finish "SIN-MODPROBE" 4
fi

say "== 1. firmware ADSP (ANTES de cargar qcom_q6v5_pas: 0033 lo arranca solo) =="
fwfail=0
for f in adsp.mdt adsp_dtb.mdt adsp-fw.sha256; do
	[ -f "$FWDIR/$f" ] || { say "FALLO: falta $FWDIR/$f"; fwfail=1; }
done
if [ "$fwfail" = 0 ]; then
	n=$(ls "$FWDIR"/adsp.b?? 2>/dev/null | wc -l)
	nd=$(ls "$FWDIR"/adsp_dtb.b?? 2>/dev/null | wc -l)
	say "segmentos: adsp.bNN=$n (esperado 51; b24/b51 no existen, es normal) adsp_dtb.bNN=$nd (esperado 3)"
	[ "$n" -ge 49 ] 2>/dev/null || { say "FALLO: firmware ADSP incompleto"; fwfail=1; }
	[ "$nd" -ge 3 ] 2>/dev/null || { say "FALLO: firmware adsp_dtb incompleto"; fwfail=1; }
	[ "$(wc -l < "$FWDIR/adsp-fw.sha256")" -ge 56 ] 2>/dev/null \
		|| { say "FALLO: adsp-fw.sha256 truncado (<56 líneas)"; fwfail=1; }
fi
if [ "$fwfail" = 0 ]; then
	[ "$(sha256sum "$FWDIR/adsp.b40" 2>/dev/null | cut -d' ' -f1)" = "$B40_SHA" ] \
		|| { say "FALLO: adsp.b40 con sha MALA (corrupción conocida; recópialo del PC)"; fwfail=1; }
	[ "$(sha256sum "$FWDIR/adsp.mdt" 2>/dev/null | cut -d' ' -f1)" = "$MDT_SHA" ] \
		|| { say "FALLO: adsp.mdt con sha MALA"; fwfail=1; }
	[ "$(sha256sum "$FWDIR/adsp_dtb.mdt" 2>/dev/null | cut -d' ' -f1)" = "$DTBMDT_SHA" ] \
		|| { say "FALLO: adsp_dtb.mdt con sha MALA"; fwfail=1; }
fi
if [ "$fwfail" = 0 ]; then
	if (cd "$FWDIR" && sha256sum -c adsp-fw.sha256 >/dev/null 2>&1); then
		say "shas firmware OK (56/56 + b40/mdt fijados)"
	else
		say "FALLO: firmware con shas MALAS:"
		(cd "$FWDIR" && sha256sum -c adsp-fw.sha256 2>&1 | grep -v ': OK$' | head -8)
		fwfail=1
	fi
fi
[ "$fwfail" = 0 ] || finish "FIRMWARE-MALO" 4

say "== 2. módulos en orden (modprobe; deps por modules.dep) =="
load_mod() { # $1=módulo
	out=$("$MODPROBE" "$1" 2>&1)
	rc=$?
	if [ "$rc" = 0 ]; then
		say "modprobe $1 OK"
		return 0
	fi
	say "FALLO modprobe $1 rc=$rc: $out"
	return 1
}
# qrtr y su transporte SMD, locator pd-mapper y la pila de batería, TODO antes del ADSP.
for m in qrtr qrtr_smd qcom_pd_mapper pmic_glink qcom_battmgr; do
	load_mod "$m" || finish "MODULO-$m" 4
done

say "== 3. ADSP (qcom_q6v5_pas: el ÚLTIMO; 0033 lo auto-arranca) =="
find_adsp() {
	for r in "$SYS"/class/remoteproc/remoteproc*; do
		[ -e "$r/state" ] || continue
		n=$(rd "$r/name")
		fw=$(rd "$r/firmware")
		if [ "$n" = adsp ] || [ "$fw" = adsp.mdt ]; then
			echo "$r"
			return 0
		fi
	done
	return 1
}
R=$(find_adsp)
if [ -n "$R" ] && [ "$(rd "$R/state")" = running ]; then
	say "ADSP ya running ($R): no toco nada"
else
	load_mod qcom_q6v5_pas || finish "MODULO-qcom_q6v5_pas" 4
	i=0
	manual=0
	while [ "$i" -lt "$T_RUN" ]; do
		R=$(find_adsp)
		if [ -n "$R" ]; then
			st=$(rd "$R/state")
			[ "$st" = running ] && break
			if [ "$st" = crashed ] && [ "$manual" = 0 ]; then
				say "ADSP crashed (recovery desactivada por 0033): stop + start manual"
				timeout 30 sh -c "echo stop > '$R/state'" 2>&1 || say "echo stop rc=$?"
				st=$(rd "$R/state")
				i=$T_AUTO	# arranque manual ya, sin esperar
			fi
			if [ "$manual" = 0 ] && [ "$i" -ge "$T_AUTO" ]; then
				manual=1
				say "auto-boot no llegó a running en ${T_AUTO}s (estado=$st): UN 'echo start' manual"
				timeout 60 sh -c "echo start > '$R/state'" 2>&1 || say "echo start rc=$?"
			fi
		fi
		sleep 1
		i=$((i + 1))
	done
	R=$(find_adsp)
	st=$( [ -n "$R" ] && rd "$R/state" )
	if [ "$st" != running ]; then
		say "FALLO: ADSP no running tras ${T_RUN}s (remoteproc=${R:-ninguno} estado=${st:-?})"
		dmesg 2>/dev/null | grep -Ei 'remoteproc|q6v5|adsp|pd-mapper|PDM|Direct firmware|auth' | tail -12
		finish "ADSP-NO-ARRANCA" 5
	fi
fi
say "ADSP running ($R, firmware=$(rd "$R/firmware"))"
status "adsp=running"

say "== 4. power_supply (qcom-battmgr-bat) =="
BAT=$SYS/class/power_supply/qcom-battmgr-bat
i=0
while [ "$i" -lt "$T_PSY" ]; do
	v=$(rd "$BAT/voltage_now")
	[ -n "$v" ] && [ "$v" -gt 0 ] 2>/dev/null && break
	sleep 1
	i=$((i + 1))
done
sleep 1
dmesg 2>/dev/null | grep -i 'charger_pd' | tail -n 3
FOUND=0
GREEN=0
for p in "$SYS"/class/power_supply/*/; do
	[ -e "$p" ] || continue
	FOUND=1
	n=$(basename "$p")
	say "-- $n: status=$(rd "$p/status") voltage_now=$(rd "$p/voltage_now") current_now=$(rd "$p/current_now") capacity=$(rd "$p/capacity") charge_type=$(rd "$p/charge_type") online=$(rd "$p/online") usb_type=$(rd "$p/usb_type")"
done
st=$(rd "$BAT/status")
v=$(rd "$BAT/voltage_now")
status "bat_status=$st"
status "bat_voltage_now=$v"
status "bat_current_now=$(rd "$BAT/current_now")"
status "bat_capacity=$(rd "$BAT/capacity")"
# Criterio (lección 13-oct): NO se exige current_now>0 ni su signo — en CV la
# corriente es legítimamente ~0 y el signo depende del dialecto. Se exige voltaje
# medible y status Charging/Full. La carga SOSTENIDA se mide en uke-carga-verify.sh --watch.
if [ -n "$v" ] && [ "$v" -gt 0 ] 2>/dev/null; then
	case "$st" in
	Charging | Full) GREEN=1 ;;
	esac
fi

if [ "$GREEN" = 1 ]; then
	finish "VERDE (bat $st, ${v} uV)" 0
elif [ -d "$BAT" ] && [ -n "$v" ]; then
	say "AMARILLO: hay batería ($st, ${v} uV) pero no carga: ¿cargador de pared conectado?"
	finish "AMARILLO ($st)" 2
else
	[ "$FOUND" = 0 ] && say "(sin power_supply: battmgr no probó; ¿PDR charger_pd? ¿pd_mapper?)"
	finish "ROJO (sin power_supply de batería)" 3
fi
