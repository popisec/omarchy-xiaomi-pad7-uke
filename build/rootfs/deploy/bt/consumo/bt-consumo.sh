#!/bin/bash
# bt-consumo.sh — EN LA TABLET (root): consumo del Bluetooth despierto y en SUSPENSION (s2idle), con el metodo de la sesion de bateria
# (CONSUMO-DESGLOSE-20261020.md: sistema = descarga neta de la bateria -V·I + entrada USB V·I, a 1 Hz, 8 s de asentamiento + 45 s por fase, linea base repetida
# entre fases, un delta < ~0,1 W no es significativo). Las fases se intercalan con la base y en orden aleatorio por repeticion.
#
#   bt-consumo.sh [-r REPS] [-R REPS_SUSP] [-t SEG] [-s SEG_SUSP] [--sin-suspension | --solo-suspension] [-o LOG] [--dry-run]
#     -r  repeticiones despierto (por defecto 3)   -R  repeticiones en suspension (2)   -t  segundos de medida por fase despierta (45)   -s  segundos de cada suspension (300)
# FASES DESPIERTAS (pantalla como este; lo normal para medir es DPMS apagado):
#     base       BT como esta (adaptador encendido, lo que haya conectado)
#     bt_off     `bluetoothctl power off` (BT_EN bajo, hci caido; el modulo sigue cargado)      -> vuelve con `power on`
#     bt_down    `uke-bt-up.sh --down` (hci_uart y overlay descargados)                         -> vuelve con `uke-bt-up.sh --service`
# FASES EN SUSPENSION (ΔQ del contador de carga de la bateria entre el inicio y el final de una suspension real con alarma RTC; necesita USB DESENCHUFADO):
#     s_hook     el gancho por defecto: adaptador apagado, despertar por UART desactivado
#     s_keepon   /etc/uke/bt-keep-on: adaptador ENCENDIDO al dormir (despertar por UART desactivado)
#     s_down     `uke-bt-up.sh --down` antes de dormir (el gancho no encuentra hci0)
# Deja el BT encendido y sin /etc/uke/bt-keep-on al terminar o al abortar. Salida: lineas `FASE ...` y `SUSP ...`; analisis en el PC:
#     python3 consumo/analiza-consumo.py LOG
# Entorno (pruebas en el PC): BT_BAT, BT_USB (directorios de sysfs), BT_UP (uke-bt-up.sh), BT_ETC (prefijo de /etc/uke), BT_SCALE (factor de tiempo, p. ej. 0.01).
set -u
BAT=${BT_BAT:-/sys/class/power_supply/qcom-battmgr-bat}; USB=${BT_USB:-/sys/class/power_supply/qcom-battmgr-usb}; UP=${BT_UP:-/usr/local/sbin/uke-bt-up.sh}
ETC=${BT_ETC:-/etc/uke}; SCALE=${BT_SCALE:-1}
REPS=3; SREPS=2; T=45; TS=300; SUSP=1; AWAKE=1; DRY=0; LOG=/root/bt-consumo-$(date +%Y%m%d-%H%M%S).log
while [ $# -gt 0 ]; do case "$1" in
	-r) REPS=${2:?-r N}; shift ;; -R) SREPS=${2:?-R N}; shift ;; -t) T=${2:?-t seg}; shift ;; -s) TS=${2:?-s seg}; shift ;; -o) LOG=${2:?-o fichero}; shift ;;
	--sin-suspension) SUSP=0 ;; --solo-suspension) AWAKE=0 ;; --dry-run) DRY=1 ;;
	-h|--help) awk 'NR>1 && /^set -u/{exit} NR>1' "$0"; exit 0 ;; *) echo "uso: $0 [-r N] [-t seg] [-s seg] [--sin-suspension|--solo-suspension] [-o log] [--dry-run]" >&2; exit 1 ;; esac; shift; done
for v in "$REPS" "$SREPS" "$T" "$TS"; do case "$v" in ''|*[!0-9]*|0) echo "-r/-R/-t/-s deben ser enteros > 0" >&2; exit 1 ;; esac; done
[ "$AWAKE$SUSP" = 00 ] && { echo "--sin-suspension y --solo-suspension a la vez no dejan nada que medir" >&2; exit 1; }
log() { echo "$*" | tee -a "$LOG"; }
if [ "$DRY" = 1 ]; then
	echo "PLAN: despierto=$AWAKE ($REPS rep., $T s por fase + 8 s de asentamiento; base, bt_off, bt_down) | suspension=$SUSP ($SREPS rep., $TS s por suspension; s_hook, s_keepon, s_down). Log: $LOG"
	echo "  orden por repeticion: BASE, X, BASE, Y, BASE con X,Y = las otras dos fases en orden aleatorio (despierto y, aparte, suspension)"
	est=$(( AWAKE * REPS * 5 * (T + 8 + 6) + SUSP * SREPS * 5 * (TS + 40) )); echo "  duracion estimada: ~$((est / 60)) min"; exit 0
fi
[ "$(id -u)" = 0 ] || { echo "hace falta root" >&2; exit 1; }
[ -r "$BAT/voltage_now" ] || { echo "no leo la bateria ($BAT)" >&2; exit 1; }
[ -e "${BT_ROOT:-}/sys/class/bluetooth/hci0" ] || [ -n "${BT_ROOT:-}" ] || { echo "no hay hci0: arranca el BT antes (uke-bt-up.sh)" >&2; exit 1; }
cleanup() { rm -f "$ETC/bt-keep-on"; [ -e "${BT_ROOT:-}/sys/class/bluetooth/hci0" ] || UKE_BT_CYCLES=3 "$UP" --service >/dev/null 2>&1; bluetoothctl power on >/dev/null 2>&1; log "# restaurado: BT encendido, sin bt-keep-on"; }
trap cleanup EXIT; trap 'echo abortado; exit 130' INT TERM
sampler() { # sampler NAME SEG -> una linea JSON (medias, error tipico, CPU ocupada); 1 Hz como samp.py de la sesion de bateria
python3 -I - "$1" "$2" "$BAT" "$USB" "$SCALE" <<'PY'
import sys, time, json, statistics as st
name, dur, B, U, sc = sys.argv[1], float(sys.argv[2]), sys.argv[3] + "/", sys.argv[4] + "/", float(sys.argv[5])
def n(p):
    try: return int(open(p).read())
    except Exception: return None
def cpu():
    f = list(map(int, open("/proc/stat").readline().split()[1:])); return sum(f), f[3] + f[4]
s0 = cpu(); t0 = time.time(); end = t0 + dur * sc; bw = []; uw = []; tick = 1.0 * sc
while time.time() < end:
    v, c, uv, uc = n(B + "voltage_now"), n(B + "current_now"), n(U + "voltage_now"), n(U + "current_now")
    if None not in (v, c): bw.append(-v * c / 1e12)
    if None not in (uv, uc): uw.append(uv * uc / 1e12)
    time.sleep(max(tick - (time.time() - t0) % tick, 0.001))
s1 = cpu(); sysw = [a + b for a, b in zip(bw, uw)] if len(bw) == len(uw) else bw
ms = lambda x: (round(st.mean(x), 4), round(st.stdev(x) / len(x) ** 0.5, 4)) if len(x) > 1 else (None, None)
print(json.dumps({"n": len(sysw), "sys": ms(sysw), "bat": ms(bw), "usb": ms(uw), "cpu_busy_pct": round(100 * (1 - (s1[1] - s0[1]) / max(s1[0] - s0[0], 1)), 2)}))
PY
}
fase() { # fase NAME REP : aplica la accion de la fase, asienta, mide y restaura
	local name=$1 rep=$2 j
	case $name in
		bt_off) bluetoothctl power off >/dev/null 2>&1 ;;
		bt_down) "$UP" --down >/dev/null 2>&1 ;;
	esac
	sleep "$(awk -v s=8 -v k="$SCALE" 'BEGIN{print s * k}')"
	j=$(sampler "$name" "$T")
	case $name in
		bt_off) bluetoothctl power on >/dev/null 2>&1 ;;
		bt_down) UKE_BT_CYCLES=3 "$UP" --service >/dev/null 2>&1; sleep "$(awk -v k="$SCALE" 'BEGIN{print 4 * k}')" ;;
	esac
	log "FASE name=$name rep=$rep t=$(date +%T) dur=$T $(python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); print("n=%s sys_w=%s sys_sem=%s bat_w=%s usb_w=%s cpu_busy=%s" % (d["n"], d["sys"][0], d["sys"][1], d["bat"][0], d["usb"][0], d["cpu_busy_pct"]))' "$j")"
}
qn() { cat "$BAT/charge_counter" 2>/dev/null; }
susp() { # susp NAME REP : prepara la variante, duerme TS s con alarma RTC y registra el delta del contador de carga
	local name=$1 rep=$2 q0 q1 u0 u1 v usbw
	case $name in
		s_keepon) touch "$ETC/bt-keep-on" ;;
		s_down) "$UP" --down >/dev/null 2>&1 ;;
	esac
	sync; sleep "$(awk -v k="$SCALE" 'BEGIN{print 3 * k}')"
	usbw=$(python3 -I -c 'import sys; f=lambda p: int(open(p).read()); print(round(f(sys.argv[1]+"/voltage_now")*f(sys.argv[1]+"/current_now")/1e12, 3))' "$USB" 2>/dev/null || echo 0)
	q0=$(qn); u0=$(cut -d' ' -f1 /proc/uptime); v=$(cat "$BAT/voltage_now")
	rtcwake -m no -s "$(awk -v s="$TS" -v k="$SCALE" 'BEGIN{printf "%d", s * k + 0.5}')" >/dev/null 2>&1
	systemctl suspend >/dev/null 2>&1
	q1=$(qn); u1=$(cut -d' ' -f1 /proc/uptime)
	log "SUSP name=$name rep=$rep t=$(date +%T) dur_s=$(awk -v a="$u0" -v b="$u1" 'BEGIN{printf "%.1f", b - a}') q0_uah=$q0 q1_uah=$q1 v_uv=$v usb_w=$usbw wake_irq=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)"
	rm -f "$ETC/bt-keep-on"
	[ "$name" = s_down ] && UKE_BT_CYCLES=3 "$UP" --service >/dev/null 2>&1
	sleep "$(awk -v k="$SCALE" 'BEGIN{print 25 * k}')"   # deja que uke-bt-resume reenganche
}
log "# bt-consumo $(date -Is) kernel=$(uname -r) reps=$REPS sreps=$SREPS t=$T ts=$TS despierto=$AWAKE suspension=$SUSP"
if [ "$AWAKE" = 1 ]; then
	for r in $(seq 1 "$REPS"); do
		fase base "$r"
		for x in $(printf 'bt_off\nbt_down\n' | shuf); do fase "$x" "$r"; fase base "$r"; done
	done
fi
if [ "$SUSP" = 1 ]; then
	log "# suspension: el USB debe estar DESENCHUFADO para que ΔQ sea el consumo real; usb_w > 0,3 W invalida la fila"
	for r in $(seq 1 "$SREPS"); do
		susp s_hook "$r"
		for x in $(printf 's_keepon\ns_down\n' | shuf); do susp "$x" "$r"; susp s_hook "$r"; done
	done
fi
log "# FIN $(date -Is)"
