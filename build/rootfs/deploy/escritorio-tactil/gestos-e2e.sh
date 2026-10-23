#!/bin/bash
# gestos-e2e.sh — gestos de 3 dedos de extremo a extremo EN LA TABLET (ESCRITORIO-TACTIL 22-oct-2026).
# Táctil multitoque virtual (mt-inject.py) + una instancia DE PRUEBA de uke-gestures.py enganchada solo a él (--device, --act):
# el demonio real sigue con el panel. Abre dos ventanas propias (osk-entry.py) y comprueba el estado de Hyprland tras cada gesto.
# Necesita el turno. Sale con 1 si algo falla. Copia antes a /tmp de la tablet: mt-inject.py, osk-entry.py.
HERE=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$HERE/../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}
HOST=${UKE_HOST:-root@uke}
for f in mt-inject.py osk-entry.py; do ssh -i "$KEY" -o BatchMode=yes "$HOST" "cat > /tmp/$f" < "$HERE/$f"; done
{ cat <<'PRE'
export XDG_RUNTIME_DIR=/run/user/1001 HOME=/home/omarchy USER=omarchy WAYLAND_DISPLAY=wayland-1 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1001/hypr | head -1) LANG=C.UTF-8 OMARCHY_PATH=/usr/share/omarchy
export PATH=/usr/share/omarchy/bin:/usr/local/bin:/usr/bin
PRE
cat <<'REMOTE'
cd /tmp
FAIL=0
ok() { echo "PASS  $*"; }
ko() { echo "FAIL  $*"; FAIL=1; }
wsof() { hyprctl clients -j | python3 -c "import json,sys;print(next((c['workspace']['id'] for c in json.load(sys.stdin) if c['class']=='$1'),'-'))"; }
act() { hyprctl activewindow -j | python3 -c 'import json,sys;print(json.load(sys.stdin).get("class","-"))'; }
actws() { hyprctl activeworkspace -j | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])'; }
python3 -I /tmp/osk-entry.py --sin-campo >/dev/null 2>&1 & A=$!; sleep 2
python3 -I /tmp/osk-entry.py >/dev/null 2>&1 & B=$!; sleep 2
# un dispositivo virtual y una instancia de prueba de uke-gestures POR GESTO (sin tuberias ni estado compartido)
g() {
  rm -f /tmp/mt.path
  python3 -I /tmp/mt-inject.py --path-file /tmp/mt.path --wait 2.5 "$1" >> /tmp/mt.out 2>&1 & M=$!
  for i in $(seq 25); do [ -s /tmp/mt.path ] && break; sleep 0.2; done
  python3 -I /usr/local/share/uke/gestures/uke-gestures.py --device "$(cat /tmp/mt.path)" --log --act >> /tmp/ge.out 2>&1 & G=$!
  wait $M; sleep 0.3; kill $G 2>/dev/null; wait $G 2>/dev/null; sleep ${2:-1}
}
: > /tmp/mt.out; : > /tmp/ge.out
echo "== inicio: sin-campo ws $(wsof uke.osksincampo), entry ws $(wsof uke.oskprueba), activa $(act)"
[ "$(wsof uke.osksincampo)" != "$(wsof uke.oskprueba)" ] && ok "dos apps en escritorios distintos" || ko "dos apps en escritorios distintos"
g pinch_in;  [ "$(wsof uke.osksincampo)" = "$(wsof uke.oskprueba)" ] && ok "pellizco 3 dedos dentro = dividir" || ko "pellizco = dividir"
g pinch_in;  [ "$(wsof uke.osksincampo)" != "$(wsof uke.oskprueba)" ] && ok "pellizco otra vez = separar" || ko "pellizco = separar"
W0=$(actws)
g swipe3_left;  W1=$(actws); [ "$W1" != "$W0" ] && [ "$(hyprctl activeworkspace -j | python3 -c 'import json,sys;print(json.load(sys.stdin)["windows"])')" -gt 0 ] && ok "3 dedos izq: otra app ($W0 -> $W1, no vacio)" || ko "3 dedos izq ($W0 -> $W1)"
g swipe3_right; W2=$(actws); [ "$W2" = "$W0" ] && ok "3 dedos der: vuelve ($W1 -> $W2)" || ko "3 dedos der ($W1 -> $W2, esperado $W0)"
g swipe3_up; [ "$(omarchy-shell uke.launcher status 2>/dev/null | cut -d' ' -f1)" = open ] && ok "3 dedos arriba = lanzador" || ko "3 dedos arriba = lanzador"
g tap1:0.953,0.057; [ "$(omarchy-shell uke.launcher status 2>/dev/null | cut -d' ' -f1)" = closed ] && ok "toque en ✕ cierra el lanzador" || ko "✕ cierra el lanzador"
# la app "anterior" queda definida: primero sin-campo, luego entry (la que se cierra)
hyprctl eval "hl.dispatch(hl.dsp.focus({ window = \"class:uke.osksincampo\" }))" >/dev/null; sleep 1
hyprctl eval "hl.dispatch(hl.dsp.focus({ window = \"class:uke.oskprueba\" }))" >/dev/null; sleep 1
g swipe3_down 2; kill -0 $B 2>/dev/null && ko "3 dedos abajo = cerrar" || ok "3 dedos abajo cierra la app activa"
[ "$(act)" = uke.osksincampo ] && ok "al cerrar vuelve a la app anterior" || ko "al cerrar vuelve a la anterior (activa: $(act))"
echo "== gestos reconocidos por la instancia de prueba:"; grep -E "GESTO" /tmp/ge.out | sed 's/^/   /'
kill $A $B 2>/dev/null
echo "RESULTADO: $([ $FAIL = 0 ] && echo OK || echo FALLOS)"
exit $FAIL
REMOTE
} | ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=10 "$HOST" 'setpriv --reuid=1001 --regid=1001 --init-groups bash -s'
