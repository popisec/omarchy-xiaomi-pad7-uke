#!/usr/bin/env bash
# test-private.sh — prueba de PC de 50-uke-null-sink.conf con una instancia PRIVADA de PipeWire + WirePlumber.
# E0, 18-oct-2026. No toca tu sesion de audio ni ningun dispositivo ALSA:
#   - XDG_RUNTIME_DIR propio (socket propio) y entorno limpio (env -i);
#   - WirePlumber con el perfil `policy` (solo politica de enlazado/predeterminados, SIN monitores ALSA/BlueZ/V4L2);
#   - al salir mata solo los PIDs que lanzo y borra su directorio.
# El directorio de trabajo va en /tmp con nombre corto: el socket unix no admite rutas de >107 bytes.
# Comprueba: (1) el nodo aparece como Audio/Sink a 48 kHz FL FR con priority.session=100; (2) `wpctl status` lo muestra
# como sumidero PREDETERMINADO; (3) un flujo `pw-cat` se enlaza solo y el enlace queda `active`.
set -Eeuo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
CONF=$HERE/50-uke-null-sink.conf
RT=$(mktemp -d /tmp/ukepw.XXXXXX)
pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; wait 2>/dev/null || true; rm -rf "$RT"; }
trap cleanup EXIT
mkdir -p "$RT/cfg/pipewire/pipewire.conf.d" "$RT/home"
cp "$CONF" "$RT/cfg/pipewire/pipewire.conf.d/"
cat > "$RT/e.sh" <<EOF
#!/bin/bash
exec env -i PATH=/usr/bin HOME=$RT/home XDG_RUNTIME_DIR=$RT XDG_CONFIG_HOME=$RT/cfg \\
	XDG_DATA_HOME=$RT/home/.local/share XDG_STATE_HOME=$RT/home/.local/state "\$@"
EOF
chmod +x "$RT/e.sh"
E=$RT/e.sh
fails=0
bad() { echo "FALLO: $*"; fails=$((fails + 1)); }

"$E" pipewire > "$RT/pw.log" 2>&1 & pids+=($!)
for _ in $(seq 50); do [ -S "$RT/pipewire-0" ] && break; sleep 0.1; done
[ -S "$RT/pipewire-0" ] || { echo "pipewire privado no arranco:"; tail -3 "$RT/pw.log"; exit 2; }
"$E" wireplumber -p policy > "$RT/wp.log" 2>&1 & pids+=($!)
sleep 3

row=$("$E" pw-dump 2>/dev/null | python3 -c '
import json, sys
for o in json.load(sys.stdin):
    if o["type"] == "PipeWire:Interface:Node" and o["info"]["props"].get("node.name") == "uke-null-sink":
        p = o["info"]["props"]
        print(p.get("media.class"), p.get("audio.rate"), p.get("audio.position"), p.get("priority.session"), repr(p.get("node.description")))')
echo "1. nodo: $row"
[[ $row == "Audio/Sink 48000 [ FL FR ] 100 'Uke (sin audio fisico)'" ]] || bad "propiedades del nodo inesperadas"

st=$("$E" wpctl status 2>/dev/null)
echo "$st" | grep -E '^ [│ ] +\* +[0-9]+\. Uke \(sin audio fisico\)' >/dev/null \
	&& echo "2. wpctl status: sumidero predeterminado = Uke (sin audio fisico)" || bad "no es el predeterminado en wpctl status"
echo "$st" | sed -n '/Sinks:/,/Sources:/p' | head -4 | sed 's/^/   /'

(timeout 5 "$E" pw-cat -p --rate 48000 --channels 2 --format s16 --raw - < /dev/zero > "$RT/cat.log" 2>&1 &)
sleep 2
link=$("$E" pw-dump 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
n = {o["id"]: o["info"]["props"].get("node.name") for o in d if o["type"] == "PipeWire:Interface:Node"}
for o in d:
    if o["type"] == "PipeWire:Interface:Link":
        i = o["info"]
        print(n.get(i["output-node-id"]), "->", n.get(i["input-node-id"]), i["state"])' | sort -u)
echo "3. enlaces: $link"
[[ $link == *"pw-cat -> uke-null-sink active"* ]] || bad "pw-cat no quedo enlazado al sumidero nulo"

echo "RESULTADO: $([ $fails -eq 0 ] && echo OK || echo "$fails FALLO(S)")"
[ $fails -eq 0 ]
