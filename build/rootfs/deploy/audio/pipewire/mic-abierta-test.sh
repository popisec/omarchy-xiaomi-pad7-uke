#!/usr/bin/env bash
# mic-abierta-test.sh — prueba de PC (PipeWire+WirePlumber PRIVADOS) de la variante «micro siempre abierta» de 51-uke-mic.conf: sustituye el adaptador ALSA por una fuente nula con
# las MISMAS propiedades de suspension y comprueba que (A) la conf base (suspension a los 5 s) deja el nodo en `suspended` y (B) la variante lo mantiene fuera de `suspended` sin clientes.
set -Eeuo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); pids=(); RT=
cleanup() { for p in "${pids[@]:-}"; do kill "$p" 2>/dev/null || true; done; wait 2>/dev/null || true; if [ -n "$RT" ]; then rm -rf "$RT"; fi; return 0; }
trap cleanup EXIT
estado() { # estado CONF -> estado del nodo uke-mic tras 14 s sin clientes
	RT=$(mktemp -d /tmp/ukemic.XXXXXX); mkdir -p "$RT/cfg/pipewire/pipewire.conf.d" "$RT/home"
	python3 -I - "$1" "$RT/cfg/pipewire/pipewire.conf.d/51.conf" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
s = s.replace("api.alsa.pcm.source", "support.null-audio-sink").replace("Audio/Source", "Audio/Source/Virtual")
s = re.sub(r'\n\s*(api\.alsa\.[a-z-]+|audio\.[a-z]+)\s*=\s*[^\n]*', '', s)
s = s.replace("args = {", 'args = {\n            audio.position = [ FL FR ]\n            object.linger = true', 1)
open(sys.argv[2], "w").write(s)
PY
	E="env -i PATH=/usr/bin HOME=$RT/home XDG_RUNTIME_DIR=$RT XDG_CONFIG_HOME=$RT/cfg XDG_DATA_HOME=$RT/home/.local/share XDG_STATE_HOME=$RT/home/.local/state"
	$E pipewire > "$RT/pw.log" 2>&1 & pids+=($!)
	for _ in $(seq 50); do [ -S "$RT/pipewire-0" ] && break; sleep 0.1; done
	$E wireplumber -p policy > "$RT/wp.log" 2>&1 & pids+=($!)
	sleep 14
	$E pw-dump 2>/dev/null | python3 -I -c '
import json, sys
for o in json.load(sys.stdin):
    if o["type"] == "PipeWire:Interface:Node" and o["info"]["props"].get("node.name") == "uke-mic":
        print(o["info"]["state"]); break
else: print("ausente")'
	for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; wait 2>/dev/null || true; pids=(); rm -rf "$RT"; RT=
}
VAR=$(mktemp /tmp/ukemicvar.XXXXXX); trap 'rm -f "$VAR"; cleanup' EXIT
"$HERE/mic-abierta.sh" --render > "$VAR"
a=$(estado "$HERE/51-uke-mic.conf"); echo "  base: $a"
b=$(estado "$VAR"); echo "  variante abierta: $b"
f=0
[ "$a" = suspended ] && echo "  ok  base se suspende" || { echo "FALLO: base no se suspendio ($a)"; f=1; }
{ [ "$b" != suspended ] && [ "$b" != ausente ]; } && echo "  ok  variante sigue abierta ($b)" || { echo "FALLO: variante $b"; f=1; }
[ $f = 0 ] && echo "RESULTADO: OK" || { echo "RESULTADO: FALLO"; exit 1; }
