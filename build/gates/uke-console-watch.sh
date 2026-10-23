#!/usr/bin/env bash
# uke-console-watch.sh — se queda pegado al ACM desde el instante en que aparece.
#
# POR QUÉ EXISTE. Perdi la salida temprana del arranque dos veces: (1) el capturador del
# hermano estaba parado cuando tocó, y (2) mi propio `cat` se relanzó con `>` y se
# truncó el log justo cuando empezaba el boot. Un lector que arranca "a mano" llega
# tarde: el S123 y el switch_root ocurren en los primeros 20 s.
#
# ESTE script no se queda esperando: hace poll de /dev/ttyACM0 y se engancha en cuanto
# existe, y si el reader se muere (porque el ACM se re-enumera al reiniciar) vuelve a
# engancharse. Es un lazo.
#
# Es el UNICO lector del ACM: si hay otro `cat` colgado, lo mata (regla: un solo lector,
# si el buffer se llena los write() del kernel se bloquean y el cuelgue no se registra).
set -u
LOG=/tmp/opencode/console-uke.log
PIDFILE=/tmp/opencode/uke-console-watch.pid

# ⚠️ POR QUÉ NO SE PUEDE FIJAR /dev/ttyACM0. Medido el 27-sep-2026: al reiniciar la tablet el
# host NO vuelve a crear ttyACM0, crea OTRO nodo con el índice siguiente (ttyACM1, luego
# ttyACM2...). El índice es del host, no del gadget. Un watcher atado a ttyACM0 se queda
# mirando un nodo fantasma: no captura nada y, peor, el login por consola se pierde entero
# porque la ventana del getty son 60 s. Se busca SIEMPRE el ttyACM* mas alto.
acm() { ls -1 /dev/ttyACM* 2>/dev/null | sort -V | tail -1; }

[ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null
echo $$ > "$PIDFILE"

# marca de inicio de sesión, para poder separar arranques
mark() { echo "===== $(date '+%F %T') watcher $1 =====" >> "$LOG"; }

mark "arrancado"
DEV=""
while true; do
    # si hay lectores ajenos, fuera
    for p in $(pgrep -x cat 2>/dev/null); do
        grep -qa "ttyACM" /proc/$p/cmdline 2>/dev/null && [ "$p" != "$$" ] && kill "$p" 2>/dev/null
    done
    NEW=$(acm)
    if [ -n "$NEW" ] && [ "$NEW" != "$DEV" ]; then
        DEV="$NEW"
        mark "ACM presente ($DEV) -> enganchado"
        cat "$DEV" >> "$LOG" 2>/dev/null
        mark "ACM caido ($DEV) -> reintento"
        DEV=""
        sleep 2
    else
        sleep 1
    fi
done
