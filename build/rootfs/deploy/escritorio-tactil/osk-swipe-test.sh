#!/bin/bash
# osk-swipe-test.sh — prueba EN LA TABLET de la 2.a ronda del teclado (ESCRITORIO-TACTIL 22-oct-2026):
#  - swipe con trazos tactiles reales (mt-inject.py path:..., geometria de osk-swipe-paths.py) sobre el teclado acoplado;
#  - doble espacio = ". ", puntuacion tras sugerencia absorbe el espacio, Retroceso tras un trazo borra la palabra;
#  - palabras propias: una palabra desconocida escrita dos veces se aprende y se sugiere.
# Copia y restaura ~/.local/state/uke-touch-mode/palabras.txt (no deja palabras de prueba aprendidas). Necesita el turno y la
# tablet en horizontal (0 grados). Sale con 1 si algo falla.
HERE=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$HERE/../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}
HOST=${UKE_HOST:-root@uke}
WORDS="hola gracias casa bien para como tiempo gente ahora nada"
PATHS=$(python3 "$HERE/osk-swipe-paths.py" $WORDS)
for f in mt-inject.py osk-entry.py; do ssh -i "$KEY" -o BatchMode=yes "$HOST" "cat > /tmp/$f" < "$HERE/$f"; done
{ cat <<'PRE'
export XDG_RUNTIME_DIR=/run/user/1001 HOME=/home/omarchy USER=omarchy WAYLAND_DISPLAY=wayland-1 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1001/hypr | head -1) LANG=C.UTF-8 OMARCHY_PATH=/usr/share/omarchy
export PATH=/usr/share/omarchy/bin:/usr/local/bin:/usr/bin
PRE
echo "WORDS='$WORDS'"; echo "PATHS='$PATHS'"
cat <<'REMOTE'
cd /tmp
IPC() { omarchy-shell omarkyy.tablet "$@" 2>&1 | grep -v -E "WARN|Qt depends|If this causes|for more information"; }
LETRAS() { local s=$1 i; for ((i = 0; i < ${#s}; i++)); do IPC type "${s:i:1}" >/dev/null; sleep 0.12; done; sleep 0.4; }
KEYC() { IPC key "$1" "$2" >/dev/null; sleep 0.3; }
LEE() { sleep 0.3; cat /tmp/osk-entry.txt; }
BORRA() { KEYC 30 1; KEYC 111 0; }
FAIL=0
cmp_case() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1"; printf '      esperado: [%s]\n      obtenido: [%s]\n' "$2" "$3"; FAIL=1; fi; }
UD=$HOME/.local/state/uke-touch-mode/palabras.txt
[ -f $UD ] && cp $UD /tmp/palabras.bak || rm -f /tmp/palabras.bak
python3 -I /tmp/osk-entry.py >/dev/null 2>&1 & GP=$!
for i in $(seq 40); do hyprctl activewindow | grep -q oskprueba && break; sleep 0.5; done; sleep 1.5
echo "== teclado: $(IPC status | grep -o '"keyboard":[a-z]*\|"imActive":[a-z]*' | tr '\n' ' ')"
# --- swipe con trazos reales ---
BORRA
python3 -I /tmp/mt-inject.py --path-file /tmp/mt.path --wait 1.5 $PATHS > /tmp/mt-sw.out 2>&1
sleep 0.5
GOT=$(LEE); echo "      swipe escrito: [$GOT]"
N=0; OK=0; for w in $WORDS; do N=$((N+1)); echo " $GOT " | grep -q " $w " && OK=$((OK+1)); done
[ $OK -ge $((N * 7 / 10)) ] && echo "PASS  swipe: $OK/$N palabras exactas" || { echo "FAIL  swipe: $OK/$N palabras exactas"; FAIL=1; }
# Retroceso tras un trazo borra la palabra entera
BORRA; python3 -I /tmp/mt-inject.py --path-file /tmp/mt.path --wait 1.5 $(echo $PATHS | cut -d' ' -f1) >/dev/null 2>&1; sleep 0.4
KEYC 14 0; cmp_case "Retroceso tras un trazo borra la palabra" "" "$(LEE)"
# --- doble espacio y puntuacion ---
BORRA; LETRAS "hola  "; cmp_case "doble espacio = punto" "hola. " "$(LEE)"
BORRA; LETRAS "graci"; IPC pick 0 >/dev/null; sleep 0.4; LETRAS ","; cmp_case "la coma absorbe el espacio automatico" "gracias, " "$(LEE)"
# --- palabras propias ---
BORRA; LETRAS "uketablet uketablet "; LETRAS "uketa"
echo "$(IPC status)" | grep -q '"sugs":\[[^]]*"uketablet"' && echo "PASS  palabra propia aprendida y sugerida" || { echo "FAIL  palabra propia"; FAIL=1; }
grep -qx uketablet $UD && echo "PASS  guardada en palabras.txt" || { echo "FAIL  no guardada"; FAIL=1; }
BORRA
kill $GP 2>/dev/null
# restaurar el diccionario propio y recargar el demonio (olvida las palabras de prueba)
if [ -f /tmp/palabras.bak ]; then cp /tmp/palabras.bak $UD; else rm -f $UD; fi
IPC restart >/dev/null; sleep 1.5; echo "== demonio recargado: $(IPC status | grep -o '"daemon":[a-z]*')"
echo "RESULTADO: $([ $FAIL = 0 ] && echo OK || echo FALLOS)"
exit $FAIL
REMOTE
} | ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=10 "$HOST" 'setpriv --reuid=1001 --regid=1001 --init-groups bash -s'
