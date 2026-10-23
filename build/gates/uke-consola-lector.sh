#!/bin/bash
# uke-consola-lector.sh — LECTOR ÚNICO de la consola serie de la tablet, a prueba de
# re-enumeracion del gadget.
#
# POR QUE timeout 5 Y NO `cat` PLANO (1-oct-2026, MEDIDO en el arranque del K23b).
# La version anterior hacia `exec cat /dev/ttyACM0` y al reiniciar la tablet el gadget
# re-enumera: el nodo se llama IGUAL (ttyACM0) pero es OTRO dispositivo, y el `cat` se
# queda pegado al descriptor del nodo viejo. El bucle queda ciego PARA SIEMPRE: asi se
# perdio el arranque del K23b (el log no crecio ni un byte en 11 h de bucle de reinicio).
# El aviso de "si re-enumeracion = loop ciego" del plan (O6) era justo esto.
#
# El compromiso: `timeout 5 cat` + reapertura INMEDIATA. El hueco entre lecturas es de
# ~10 ms cada 5 s, asi que la ventana de 0,23 s del arranque (3,95-4,18 s, que es donde
# muere el modeset y donde el patron #P40 demostro que se puede perder) sigue cubierta, y
# una re-enumeracion se detecta en 5 s en vez de nunca. Ademas se compara el inode del
# nodo en cada ciclo, por si el minor cambia sin que llegue a expirar el cat.
#
# REGLAS QUE RESPETA:
#   - UN SOLO LECTOR: antes de arrancar mata cualquier cat/timeout huerfano (si el buffer
#     del gadget se llena, los write() del kernel se bloquean y el cuelgue no se puede ni
#     registrar).
#   - No toca la tablet: solo lee.
#
# USO:  build/gates/uke-consola-lector.sh            (arranca en segundo plano)
#       build/gates/uke-consola-lector.sh --stop
#       build/gates/uke-consola-lector.sh --status
set -u
R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
LOG=/var/tmp/uke-sesion-console.log
PIDF=/var/tmp/uke-consola-lector.pid
TRZ=/var/tmp/uke-consola-lector.log
NODES=${UKE_CONSOLE_NODES:-"/dev/ttyACM0 /dev/ttyACM1 /dev/ttyACM2"}

status() {
	if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then
		echo "lector VIVO (pid $(cat "$PIDF")) -> $LOG ($(stat -c%s "$LOG" 2>/dev/null || echo 0) B, mtime $(stat -c%y "$LOG" 2>/dev/null | cut -d. -f1))"
	else
		echo "lector NO vivo"
	fi
	echo "nodo: $(ls /dev/ttyACM* 2>/dev/null | tr '\n' ' ')(si no hay ninguno, esta en espera)"
	echo "ultimas lineas del lector:"; tail -4 "$TRZ" 2>/dev/null | sed 's/^/   /'
	echo "procesos:"; pgrep -af 'ttyACM' | grep -v pgrep | sed 's/^/   /' | head -3
}

stop() {
	if [ -f "$PIDF" ]; then
		p=$(cat "$PIDF")
		pkill -P "$p" 2>/dev/null
		kill "$p" 2>/dev/null
		rm -f "$PIDF"
		echo "lector parado (pid $p)"
	fi
	pkill -f 'timeout 5 cat /dev/ttyACM' 2>/dev/null
	pkill -f 'timeout .* cat /dev/ttyACM' 2>/dev/null
	pkill -f 'cat /dev/ttyACM' 2>/dev/null
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
			[ -n "$NODE" ] || { sleep 0.5; continue; }
			INO=$(stat -c %i "$NODE" 2>/dev/null)
			echo "[$(date +%H:%M:%S)] abierto $NODE ino=$INO" >> '"$TRZ"'
			timeout 5 cat "$NODE" >> '"$LOG"' 2>/dev/null
			INO2=$(stat -c %i "$NODE" 2>/dev/null)
			[ "$INO" = "$INO2" ] || echo "[$(date +%H:%M:%S)] RE-ENUMERADO $NODE ($INO -> $INO2)" >> '"$TRZ"'
		done
	' >/dev/null 2>&1 &
	echo $! > "$PIDF"
	echo "lector arrancado (pid $(cat "$PIDF")) -> $LOG  [timeout 5 + reapertura inmediata]"
	sleep 2
	status
	;;
esac
