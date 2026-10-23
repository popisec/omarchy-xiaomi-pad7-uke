#!/bin/sh
# Lanzador: pausa uke-touchd (SIGSTOP, reversible), captura 40 s y lo reanuda siempre (aunque falle o expire el timeout).
P=$(pgrep -f "uke/tactil/uke-touchd.py" | head -1)
[ -n "$P" ] || { echo "uke-touchd no encontrado"; exit 1; }
trap 'kill -CONT $P' EXIT INT TERM
kill -STOP "$P"
timeout 60 python3 -I /root/lapiz-thp-capture.py "${1:-/root/lapiz-thp-frames.bin}"
