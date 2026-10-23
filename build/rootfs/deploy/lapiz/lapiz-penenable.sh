#!/bin/sh
# Pausa uke-touchd (SIGSTOP, reversible) mientras corre lapiz-penenable.py y lo reanuda SIEMPRE (trap + vigia independiente).
P=$(pgrep -f "uke/tactil/uke-touchd.py" | head -1)
[ -n "$P" ] || { echo "uke-touchd no encontrado"; exit 1; }
SEC=${1:-40}
( sleep $((SEC + 45)); kill -CONT "$P" 2>/dev/null ) &
WD=$!
trap 'kill -CONT $P 2>/dev/null; kill $WD 2>/dev/null' EXIT INT TERM HUP QUIT
kill -STOP "$P"
timeout -k 5 $((SEC + 30)) python3 -I /root/lapiz-penenable.py "$SEC" ${2:-1}
