#!/bin/sh
# NO EJECUTAR SIN AUTORIZACION DEL DUENO. Tras la prueba del 19-oct el tactil de la tablet quedo sin respuesta (causa no determinada, ver
# LAPIZ-20261018.md §21). Version endurecida segun la revision independiente: la trap tambien captura HUP/QUIT, vigia que reanuda uke-touchd
# pase lo que pase, timeout con -k, y arranque con setsid. Requiere consola ACM + `dmesg -w` capturando (docs/historia/AGENTS.md reglas 4-5).
P=$(pgrep -f "uke/tactil/uke-touchd.py" | head -1)
[ -n "$P" ] || { echo "uke-touchd no encontrado"; exit 1; }
SEC=${1:-40}
( sleep $((SEC + 40)); kill -CONT "$P" 2>/dev/null ) &       # vigia independiente
WD=$!
trap 'kill -CONT $P 2>/dev/null; kill $WD 2>/dev/null' EXIT INT TERM HUP QUIT
kill -STOP "$P"
timeout -k 5 $((SEC + 25)) python3 -I /root/lapiz-penswitch-test.py "$SEC"
