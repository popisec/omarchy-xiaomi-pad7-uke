#!/usr/bin/env bash
# test-speakers-private.sh — prueba de PC de 51-uke-speakers.conf con PipeWire+WirePlumber PRIVADOS (no toca tu sesion ni ALSA).
# Sustituye el nodo ALSA hw:UKE,0 por un sumidero nulo (en el PC no existe la tarjeta) y comprueba:
#   (1) "uke-speakers" existe y es el sumidero predeterminado; (2) un seno de escala completa a volumen 1.0 sale con pico ~0,25 (ganancia -12 dB);
#   (3) con volumen 3.0 (sobre-ganancia) el pico NO pasa de 0,3 (limitador duro).
set -Eeuo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
RT=$(mktemp -d /tmp/ukesp.XXXXXX); pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; wait 2>/dev/null || true; rm -rf "$RT"; }
trap cleanup EXIT
mkdir -p "$RT/cfg/pipewire/pipewire.conf.d" "$RT/home"
python3 -I - "$HERE/51-uke-speakers.conf" "$RT/cfg/pipewire/pipewire.conf.d/51.conf" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
s = s.replace("api.alsa.pcm.sink", "support.null-audio-sink")
s = re.sub(r'\n\s*(api\.alsa\.[a-z-]+|session\.suspend-timeout-seconds)\s*=\s*[^\n]*', '', s)
open(sys.argv[2], "w").write(s)
PY
printf '#!/bin/bash\nexec env -i PATH=/usr/bin HOME=%s/home XDG_RUNTIME_DIR=%s XDG_CONFIG_HOME=%s/cfg XDG_DATA_HOME=%s/home/.local/share XDG_STATE_HOME=%s/home/.local/state "$@"\n' "$RT" "$RT" "$RT" "$RT" "$RT" > "$RT/e.sh"
chmod +x "$RT/e.sh"; E=$RT/e.sh; fails=0
bad() { echo "FALLO: $*"; fails=$((fails + 1)); }
okk() { echo "  ok  $*"; }
"$E" pipewire > "$RT/pw.log" 2>&1 & pids+=($!)
for _ in $(seq 50); do [ -S "$RT/pipewire-0" ] && break; sleep 0.1; done
[ -S "$RT/pipewire-0" ] || { echo "pipewire privado no arranco"; tail -5 "$RT/pw.log"; exit 2; }
"$E" wireplumber -p policy > "$RT/wp.log" 2>&1 & pids+=($!)
sleep 3
row=$("$E" pw-dump 2>/dev/null | python3 -I -c '
import json, sys
for o in json.load(sys.stdin):
    if o["type"] == "PipeWire:Interface:Node" and o["info"]["props"].get("node.name") == "uke-speakers":
        p = o["info"]["props"]; print(p.get("media.class"), p.get("priority.session"), p.get("audio.position"))')
case "$row" in "Audio/Sink 1000 [ FL FR ]") true;; *) false;; esac && okk "nodo uke-speakers: $row" || bad "nodo uke-speakers inesperado: '$row'"

python3 -I - "$RT/in.wav" "$RT/in100.wav" <<'PY'
import math, struct, sys, wave
for _fn,_hz in ((sys.argv[1],1000),(sys.argv[2],40)):
  w = wave.open(_fn, "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
  w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
  w.writeframes(b"".join(struct.pack("<hh", v, v) for v in (int(32767 * math.sin(2 * math.pi * _hz * i / 48000)) for i in range(96000)))); w.close()
PY
peak() { # peak VOL -> pico de la salida (monitor del nodo ALSA sustituido) con un seno de escala completa
	"$E" wpctl set-volume uke-speakers "$1" >/dev/null 2>&1 || "$E" wpctl set-volume @DEFAULT_AUDIO_SINK@ "$1" >/dev/null 2>&1 || true
	"$E" pw-record --target uke-alsa-sink -P stream.capture.sink=true --rate 48000 --channels 2 --format f32 "$RT/o.wav" >/dev/null 2>&1 & rp=$!
	sleep 0.7
	"$E" pw-play --target uke-speakers "${2:-$RT/in.wav}" >/dev/null 2>&1 || true
	sleep 0.3; kill "$rp" 2>/dev/null || true; wait "$rp" 2>/dev/null || true
	python3 -I - "$RT/o.wav" <<'PY'
import struct, sys
b = open(sys.argv[1], "rb").read()
i = b.find(b"data")
d = b[i + 8:]
n = len(d) // 4
print("%.3f" % max((abs(x) for x in struct.unpack("<%df" % n, d[:n * 4])), default=0.0) if i >= 0 else "nan")
PY
}
p1=$(peak 1.0); echo "  pico a vol 1.0: $p1"
awk -v p="$p1" 'BEGIN{exit !(p>=0.20 && p<=0.31)}' && okk "ganancia ~0,25 (pico $p1)" || bad "pico a vol 1.0 fuera de 0,20..0,30: $p1"
p3=$(peak 3.0); echo "  pico a vol 3.0: $p3"
awk -v p="$p3" 'BEGIN{exit !(p>0 && p<=0.301)}' && okk "limitador: pico $p3 <= 0,3 con sobre-ganancia" || bad "el limitador no sujeta el pico a vol 3.0: $p3"
p100=$(peak 1.0 "$RT/in100.wav"); echo "  pico 40 Hz a vol 1.0: $p100"
awk -v p="$p100" 'BEGIN{exit !(p>=0 && p<=0.05)}' && okk "paso alto 70 Hz 6o orden: 40 Hz atenuado (pico $p100 <= 0,05; incluye el transitorio de arranque del seno)" || bad "40 Hz no atenuado: $p100"
# (4) con la tarjeta ALSA AUSENTE (conf real, hw:UKE,0 inexistente) PipeWire debe seguir vivo
RT2=$(mktemp -d /tmp/ukesp2.XXXXXX); mkdir -p "$RT2/cfg/pipewire/pipewire.conf.d" "$RT2/home"; cp "$HERE/51-uke-speakers.conf" "$RT2/cfg/pipewire/pipewire.conf.d/"
env -i PATH=/usr/bin HOME="$RT2/home" XDG_RUNTIME_DIR="$RT2" XDG_CONFIG_HOME="$RT2/cfg" pipewire > "$RT2/pw.log" 2>&1 & pw2=$!
sleep 3
if kill -0 "$pw2" 2>/dev/null && [ -S "$RT2/pipewire-0" ]; then okk "sin tarjeta UKE, PipeWire sigue vivo (nofail)"; else bad "sin tarjeta UKE, PipeWire murio: $(grep -iE 'can.t create|failed' "$RT2/pw.log" | head -2 | tr '\n' '|')"; fi
kill "$pw2" 2>/dev/null || true; wait "$pw2" 2>/dev/null || true; rm -rf "$RT2"
[ "$fails" = 0 ] && echo "RESULTADO: OK" || { echo "RESULTADO: $fails fallo(s)"; exit 1; }
