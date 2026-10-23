#!/bin/bash
# uke-consola-lector2.sh — lector de la consola ACM que NO abre huecos. (2-oct-2026)
#
# POR QUÉ ESTE SEGUNDO LECTOR (medido en el arranque de K30, boot_index=137):
#   El lector v1 (`uke-consola-lector.sh`) hace `timeout 5 cat /dev/ttyACM0` en bucle:
#   cierra el fd cada 5 s y lo reabre. docs/historia/AGENTS.md dice (y esta sesion lo vio cumplirse)
#   que el kernel **se bloquea al ESCRIBIR si no hay lector**. Con huecos de ~10 ms cada
#   5 s, si el kernel entra a imprimir justo en el hueco, se cuelga DENTRO del printk.
#   Medicion del boot 137 frente a un boot bueno, mismo lector:
#       boot 136 (par bueno) -> 16.602 lineas capturadas
#       boot 137 (K30)       ->   146 lineas capturadas, PARADAS en [36.9 s]
#   y el sistema no llegó ni al target "Hardware activated USB gadget" => sin red => sin
#   SSH. Compatible (NO probado) con que el cuelgue fuera el propio lector.
#   El lector v1 ya no se usa para arranques: cierra el fd mientras el kernel imprime.
#
# DISEÑO:
#   - UN SOLO lector (si hay dos, el buffer se llena y el cuelgue sí es real).
#   - El fd SE ABRE UNA VEZ y se mantiene abierto con `cat` sin timeout. Cero huecos.
#   - Un watchdog compara el INODE del nodo cada 2 s. Si cambia (el gadget re-enumera al
#     reiniciar, con el MISMO nombre de nodo), mata el cat y reabre. Asi se conserva lo
#     que arregló el v1 (detectar re-enumeracion) sin crear huecos.
#   - Escribe el log de datos en $LOG y el diagnostico del watchdog en $TRZ.
#
# USO:
#   build/gates/uke-consola-lector2.sh            # arranca en segundo plano
#   build/gates/uke-consola-lector2.sh --stop
#   build/gates/uke-consola-lector2.sh --status
set -u
LOG=${UKE_CONSOLE_LOG:-/var/tmp/uke-console2.log}
TRZ=${UKE_CONSOLE_TRZ:-/var/tmp/uke-console2-trz.log}
PIDF=/var/tmp/uke-console2.pid
NODES=${UKE_CONSOLE_NODES:-"/dev/ttyACM0 /dev/ttyACM1 /dev/ttyACM2"}

status() {
	if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then
		echo "lector2 VIVO (pid $(cat "$PIDF")) -> $LOG ($(stat -c%s "$LOG" 2>/dev/null || echo 0) B, mtime $(stat -c%y "$LOG" 2>/dev/null | cut -d. -f1))"
	else
		echo "lector2 NO vivo"
	fi
	echo "nodo: $(ls /dev/ttyACM* 2>/dev/null | tr '\n' ' ')(si no hay ninguno, esta en espera)"
	echo "cat abiertos (deben ser 1): $(pgrep -c -f 'cat <pgrep -c -f 'cat -f' 2>/dev/null3' 2>/dev/null || echo 0)"
	echo "ultimas del watchdog:"; tail -3 "$TRZ" 2>/dev/null | sed 's/^/   /'
}

stop() {
	if [ -f "$PIDF" ]; then
		p=$(cat "$PIDF")
		pkill -P "$p" 2>/dev/null
		kill "$p" 2>/dev/null
		rm -f "$PIDF"
		echo "lector2 parado (pid $p)"
	fi
	# OJO: el patron NO puede ser 'lector2' — el command line de ESTE script lo contiene y
	# el pkill se mataria a si mismo (pasó al probarlo). Solo el bucle interno y el cat.
	pkill -f 'uke-console2-trz' 2>/dev/null
	pkill -f 'cat <&3' 2>/dev/null
	sleep 0.3
}

case "${1:-}" in
--stop)   stop ;;
--status) status ;;
*)
	stop
	setsid nohup bash -c '
		while :; do
			NODE=""
			for n in '"$NODES"'; do [ -e "$n" ] && { NODE=$n; break; }; done
			[ -n "$NODE" ] || { sleep 0.1; continue; }
			INO=$(stat -c %i "$NODE" 2>/dev/null)
			echo "[$(date +%H:%M:%S)] abierto $NODE ino=$INO (fd PERMANENTE)" >> '"$TRZ"'
			# cat sobre el fd 3, sin timeout: no hay hueco en el que el kernel pueda
			# quedarse bloqueado escribiendo.
			exec 3< "$NODE" || { sleep 0.1; continue; }
			cat <&3 >> '"$LOG"' 2>/dev/null &
			CATPID=$!
			# watchdog: si el nodo re-enumera, el inode cambia y hay que reabrir.
			# UKE-K34 (2-oct, ledger #471-bis): el sondeo era de 2 s y eso costs los
			# primeros segundos de consola, que es donde el kernel muere al quitar
			# el flag video= (boot 154 se quedo en [0.000000]). Baje a 0.2 s.
			while kill -0 "$CATPID" 2>/dev/null; do
				sleep 0.2
				INO2=$(stat -c %i "$NODE" 2>/dev/null)
				if [ "$INO" != "$INO2" ]; then
					echo "[$(date +%H:%M:%S)] RE-ENUMERADO $NODE ($INO -> $INO2): reabro" >> '"$TRZ"'
					kill "$CATPID" 2>/dev/null
					break
				fi
			done
			exec 3<&- 2>/dev/null
			wait "$CATPID" 2>/dev/null
		done
	' >/dev/null 2>&1 &
	echo $! > "$PIDF"
	echo "lector2 arrancado (pid $(cat "$PIDF")) -> $LOG  [fd permanente, watchdog de inode]"
	sleep 2
	status
	;;
esac