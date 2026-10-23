#!/usr/bin/env bash
# ciclo-prueba.sh — EN EL PC: ejecuta de una vez el CICLO de pruebas del BT cuando vuelva la tablet y el dueno lo autorice (BT-MUDO-FIX-20261021.md §5 y
# BT-ESTADO-20261021.md). Etapas, cada una con su compuerta y su registro en build/logs/bt-ciclo-<fecha>/:
#   deploy      deploy.sh --go --service --sleep --hciqca  (gancho de sueno mejorado, uke-bt-up.sh con UKE_BT_HCI_OPTS, hci_uart parcheado; NO carga nada)
#   medir       bt-medir.sh -n RONDAS (4 configuraciones intercaladas)                    -> analiza-medicion.py (hipotesis H1: carrera de 50 ms)
#   carga       bt-medir.sh con el control solo + trafico WiFi (-w) y + carga de CPU (-l)  -> analiza-medicion.py (hipotesis H2: contencion en el arranque)
#   suspension  `rtcwake -m no -s 25` + `systemctl suspend` con los auriculares CONECTADOS (--con-auriculares) -> comprueba el despertar por la alarma RTC, el gancho,
#               el ayudante y la reconexion automatica
#   consumo     bt-consumo.sh --sin-suspension (fases despiertas; la parte en suspension exige DESENCHUFAR el USB: ver los comandos que imprime)
# Uso:  ciclo-prueba.sh --check                      lectura: compuertas y plan (hace ssh de solo lectura)
#       ciclo-prueba.sh [--etapas "deploy medir carga suspension consumo"] [--rondas N] [--con-auriculares] [--go]
#       Sin --go solo imprime el plan (cero ssh). Etapas por defecto: "deploy medir carga".
# Compuertas (todas por USB, NO por Tailscale: las pruebas pueden tumbar el WiFi o la sesion): host 192.168.42.129; un lector ACM abierto; el vermagic de los .ko
# de out/ == la release que corre; bateria >= 30 % o cargando; BT arriba. Cualquier fallo de una etapa para el ciclo; el BT se deja encendido.
set -Eeuo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}; HOST=${UKE_HOST:-192.168.42.129}; ACM=${UKE_ACM:-/dev/ttyACM0}
DEPLOY=${CICLO_DEPLOY:-$HERE/deploy.sh}; TS=$(date +%Y%m%d-%H%M%S); OUTD=${CICLO_OUT:-$R/build/logs/bt-ciclo-$TS}
ETAPAS="deploy medir carga"; RONDAS=20; GO=0; CHECK=0; AUR=0
while [ $# -gt 0 ]; do case "$1" in
	--check) CHECK=1 ;; --go) GO=1 ;; --etapas) ETAPAS=${2:?--etapas "..."}; shift ;; --rondas) RONDAS=${2:?--rondas N}; shift ;; --con-auriculares) AUR=1 ;;
	-h|--help) awk 'NR>1 && /^set -Eeuo/{exit} NR>1' "$0"; exit 0 ;; *) echo "uso: $0 [--check] [--etapas \"...\"] [--rondas N] [--con-auriculares] [--go]" >&2; exit 1 ;; esac; shift; done
for e in $ETAPAS; do case "$e" in deploy|medir|carga|suspension|consumo) ;; *) echo "etapa desconocida '$e'" >&2; exit 1 ;; esac; done
case "$RONDAS" in ''|*[!0-9]*|0) echo "--rondas debe ser un entero > 0" >&2; exit 1 ;; esac
say() { printf '[ciclo %s] %s\n' "$(date +%T)" "$*"; }
die() { say "ALTO: $*"; exit 1; }
S() { ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 "root@$HOST" "$@"; }
plan() {
	say "PLAN (host $HOST; registros en $OUTD):"
	for e in $ETAPAS; do case $e in
		deploy) echo "  deploy     : $DEPLOY --go --service --sleep --hciqca" ;;
		medir) echo "  medir      : bt-medir.sh -n $RONDAS (configuraciones 50:50:0 50:150:0 50:300:0 50:50:300) + analiza-medicion.py  (~$((RONDAS * 4 * 7 / 60 + 1)) min)" ;;
		carga) echo "  carga      : bt-medir.sh -c 50:50:0 -n 30 -w y -l (control con carga de WiFi y de CPU) + analiza-medicion.py  (~8 min)" ;;
		suspension) echo "  suspension : rtcwake -m no -s 25 + systemctl suspend (tras esperar a uke-idle-guard) con auriculares conectados; veredicto VERDE/ROJO: durmio >= 20 s, el ayudante reconecto y hay conectados  (~2 min; exige --con-auriculares)" ;;
		consumo) echo "  consumo    : bt-consumo.sh --sin-suspension (despierto; ~13 min); la parte en suspension (~1 h) se hace a mano con el USB desenchufado" ;;
	esac; done
}
gates() {
	say "compuertas (solo lectura)"
	[ "$HOST" = 192.168.42.129 ] || [ "${CICLO_HOST_OK:-0}" = 1 ] || die "el host debe ser el USB (192.168.42.129): estas pruebas pueden tumbar el WiFi/Tailscale; CICLO_HOST_OK=1 lo fuerza"
	[ -n "$(fuser "$ACM" 2>/dev/null)" ] || die "no hay lector en $ACM (la regla: uno y solo uno abierto antes de tocar el BT)"
	local krel vm
	vm=$(modinfo -F vermagic "$HERE/out/uke_bt_b.ko" | cut -d' ' -f1); krel=$(S 'uname -r') || die "no hay SSH a $HOST"
	[ "$krel" = "$vm" ] || die "release de la tablet '$krel' != vermagic de out/ '$vm' (usa KB/UKE_BT_OUT; ver deploy.sh)"
	local info; info=$(S 'cap=$(cat /sys/class/power_supply/qcom-battmgr-bat/capacity); st=$(cat /sys/class/power_supply/qcom-battmgr-bat/status); echo "$cap $st"; echo "$(systemctl is-active uke-bt bluetooth | tr "\n" " ")"; timeout 6 bluetoothctl show 2>&1 | grep -c "Powered: yes"') || die "no pude leer el estado"
	say "bateria/estado: $(sed -n 1p <<<"$info"); servicios: $(sed -n 2p <<<"$info"); adaptador encendido: $(sed -n 3p <<<"$info")"
	local cap st; read -r cap st <<<"$(sed -n 1p <<<"$info")"
	[ "$cap" -ge 30 ] || [ "$st" = Charging ] || die "bateria $cap % sin cargar (< 30 %)"
	[ "$(sed -n 3p <<<"$info")" = 1 ] || die "el adaptador BT no esta encendido: arranca el BT antes (uke-bt-up.sh)"
	say "compuertas OK (kernel $krel)"
}
# OJO: run_etapa se llama dentro de `|| die`, donde `set -e` NO actua: cada orden que importa lleva su `|| return 1`.
run_etapa() {
	local e=$1 d="$OUTD" f n0 new t0 t1 dur
	mkdir -p "$d"
	case $e in
		deploy) say "== deploy =="; "$DEPLOY" --go --service --sleep --hciqca 2>&1 | tee "$d/deploy.txt" | tail -12; [ "${PIPESTATUS[0]}" = 0 ] || return 1 ;;
		medir) say "== medir (H1) =="
			S "bt-medir.sh -n $RONDAS -o /root/medir-$TS.log" 2>&1 | tee "$d/medir.out" | tail -8; [ "${PIPESTATUS[0]}" = 0 ] || return 1
			S "cat /root/medir-$TS.log" > "$d/medir.log" || return 1
			python3 -I "$HERE/hciqca/analiza-medicion.py" "$d/medir.log" | tee "$d/medir-analisis.txt"; [ "${PIPESTATUS[0]}" = 0 ] || return 1 ;;
		carga) say "== carga (H2) =="
			for f in wifi:-w cpu:-l; do
				S "bt-medir.sh -c 50:50:0 -n 30 ${f#*:} -o /root/medir-${f%:*}-$TS.log" 2>&1 | tail -4; [ "${PIPESTATUS[0]}" = 0 ] || return 1
				S "cat /root/medir-${f%:*}-$TS.log" > "$d/medir-${f%:*}.log" || return 1
				say "-- carga ${f%:*}"; python3 -I "$HERE/hciqca/analiza-medicion.py" "$d/medir-${f%:*}.log" | tee "$d/medir-${f%:*}-analisis.txt"; [ "${PIPESTATUS[0]}" = 0 ] || return 1
			done ;;
		suspension) say "== suspension con auriculares =="
			[ "$AUR" = 1 ] || { say "la etapa suspension exige --con-auriculares (auriculares encendidos, emparejados y CONECTADOS)"; return 1; }
			# un lapiz BLE cuenta como «conectado» pero no se guarda ni se reconecta (solo audio): hace falta al menos un dispositivo de AUDIO conectado
			[ "$(S 'for m in $(bluetoothctl devices Connected | awk "{print \$2}"); do timeout 6 bluetoothctl info $m | grep -qE "UUID: (Audio Sink|Headset|Handsfree)" && echo $m; done | wc -l')" -ge 1 ] || { say "no hay ningun dispositivo de AUDIO conectado (el lapiz no cuenta): enciende y conecta los auriculares"; return 1; }
			# uke-idle-guard (sesion «bateria») inhibe el reposo MIENTRAS haya una sesion SSH establecida en el puerto 22: una captura `ssh ... dmesg -w` abierta bloquea `systemctl suspend`
			# (lo vimos el 21-oct 20:58: «Operation denied due to active block inhibitor»). La unica sesion permitida es la de esta orden (cuenta 1).
			nssh=$(S "ss -Htn state established '( sport = :22 )' | wc -l") || return 1
			if [ "$nssh" -gt 1 ] && [ "${CICLO_SSH_OK:-0}" != 1 ]; then
				say "ALTO: hay $((nssh - 1)) sesion(es) SSH ademas de esta (¿captura 'dmesg -w'?): uke-idle-guard bloquearia la suspension. Cierralas (usa la consola ACM) o CICLO_SSH_OK=1"; return 1
			fi
			n0=$(S 'wc -l < /var/log/uke-bt.log') || return 1
			# el guion espera a que no quede NINGUN inhibidor de modo block (el guarda tarda <= ~25 s en soltar tras cerrar el SSH) y deja el codigo de salida de `systemctl suspend`
			printf '%s\n' '#!/bin/bash' 'rm -f /run/uke-bt-susp-rc /run/uke-bt-susp-info' 'sync' \
				'for i in $(seq 1 60); do systemd-inhibit --list --no-pager 2>/dev/null | awk '"'"'$NF=="block"{f=1} END{exit !f}'"'"' || break; sleep 1; done' \
				'echo "inhibidores block restantes: $(systemd-inhibit --list --no-pager 2>/dev/null | awk '"'"'$NF=="block"'"'"' | wc -l)" > /run/uke-bt-susp-info' \
				'rtcwake -m no -s 25' 'sleep 1' 'systemctl suspend' 'echo $? > /run/uke-bt-susp-rc' > "$d/uke-bt-susp.sh"
			S 'cat > /run/uke-bt-susp.sh && chmod 755 /run/uke-bt-susp.sh' < "$d/uke-bt-susp.sh" || return 1
			S 'systemd-run --unit=uke-bt-susp-test --collect /run/uke-bt-susp.sh >/dev/null' || return 1
			say "esperando sin SSH (el guarda suelta en <= ~25 s) y durmiendo ~25 s; luego miro"; sleep "${CICLO_ESPERA:-75}"
			n=0; until S 'test -e /run/uke-bt-susp-rc' 2>/dev/null; do n=$((n + 1)); [ "$n" -lt 40 ] || { say "ROJO: la tablet no vuelve por SSH o la suspension no termino en 40 intentos"; return 1; }; sleep "${CICLO_PAUSA:-3}"; done
			sleep "${CICLO_ASENTAR:-20}"
			new=$(S "echo \"RC_SUSPEND=\$(cat /run/uke-bt-susp-rc)\"; cat /run/uke-bt-susp-info; tail -n +$((n0 + 1)) /var/log/uke-bt.log | grep -E 'uke-bt-(sleep|resume)'; echo \"pm_wakeup_irq=\$(cat /sys/power/pm_wakeup_irq 2>/dev/null) suspend_ok=\$(cat /sys/power/suspend_stats/success) suspend_fail=\$(cat /sys/power/suspend_stats/fail)\"; echo \"CONECTADOS=\$(timeout 6 bluetoothctl devices Connected | wc -l)\"") || return 1
			printf '%s\n' "$new" | tee "$d/suspension.txt"
			S 'dmesg | tail -n 600' > "$d/dmesg-tras-suspension.txt" 2>/dev/null || true   # el anillo del kernel conserva PM:/Bluetooth/IRQ de la suspension (no hace falta captura SSH abierta)
			if ! grep -qx 'RC_SUSPEND=0' <<<"$new"; then
				say "ROJO: systemctl suspend NO se ejecuto ($(grep -m1 RC_SUSPEND <<<"$new")): $(grep -m1 'inhibidores' <<<"$new"). Inhibidores ahora:"; S 'systemd-inhibit --list --no-pager' | cut -c1-200; return 1
			fi
			t0=$(grep -m1 'uke-bt-sleep: pre: .*apago el adaptador' <<<"$new" | cut -d' ' -f1); t1=$(grep -m1 'uke-bt-sleep: post: reanudacion lanzada' <<<"$new" | cut -d' ' -f1)
			if [ -n "$t0" ] && [ -n "$t1" ]; then dur=$(( $(date -d "$t1" +%s) - $(date -d "$t0" +%s) )); else dur=-1; fi
			say "dormida entre el 'pre' y el 'post' del gancho: $dur s (alarma 25 s; < 20 s = despertar prematuro)"
			grep -q 'uke-bt-resume: reconexion de .* OK' <<<"$new" || { say "ROJO: el ayudante no registro 'reconexion ... OK'"; return 1; }
			[ "$dur" -ge 20 ] || { say "ROJO: la suspension duro $dur s (< 20 s)"; return 1; }
			grep -qx 'CONECTADOS=[1-9][0-9]*' <<<"$new" || { say "ROJO: no hay dispositivos conectados tras reanudar"; return 1; }
			say "VERDE: durmio $dur s, el adaptador volvio y los auriculares se reconectaron solos" ;;
		consumo) say "== consumo despierto =="
			S "systemd-run --unit=uke-bt-consumo --collect bt-consumo.sh --sin-suspension -o /root/consumo-$TS.log >/dev/null" || { say "no pude lanzar bt-consumo.sh (¿desplegado con --hciqca?)"; return 1; }
			say "lanzado desprendido; ~13 min. Recoger: ssh -i $KEY root@$HOST 'cat /root/consumo-$TS.log' > $d/consumo.log && python3 -I $HERE/consumo/analiza-consumo.py $d/consumo.log"
			say "SUSPENSION (a mano): desenchufar el USB, lanzar 'systemd-run --unit=uke-bt-consumo-s --collect bt-consumo.sh --solo-suspension -o /root/consumo-s-$TS.log' (~1 h; mas corto: -R 1 -s 180), volver a enchufar y recoger el log" ;;
	esac
	return 0
}
plan
if [ "$CHECK" = 1 ]; then gates; exit 0; fi
[ "$GO" = 1 ] || { say "sin --go: solo plan (nada ejecutado)"; exit 0; }
gates
for e in $ETAPAS; do run_etapa "$e" || die "etapa $e fallo"; done
say "ciclo terminado; registros en $OUTD. El BT queda encendido (bt-medir.sh y bt-consumo.sh lo restauran)"
