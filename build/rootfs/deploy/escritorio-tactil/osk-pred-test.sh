#!/bin/bash
# osk-pred-test.sh — prueba en la tablet de sugerencias y autocorrección del teclado (ESCRITORIO-TACTIL 22-oct-2026).
# Escribe LETRA A LETRA por la IPC del plugin (como el dedo) en un Gtk.Entry propio (osk-entry.py, GTK4) y en foot, y lee
# el texto real (fichero que vuelca el campo; `cat > fichero` en foot). Copiar antes osk-entry.py a /tmp de la tablet. Abre sus propias ventanas y solo cierra esas (por PID).
# NO tocar la tablet mientras corre. Sale con 1 si algún caso falla.
HERE=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$HERE/../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}
HOST=${UKE_HOST:-root@uke}
{ cat <<'PRE'
export XDG_RUNTIME_DIR=/run/user/1001 HOME=/home/omarchy USER=omarchy WAYLAND_DISPLAY=wayland-1 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1001/hypr | head -1) LANG=C.UTF-8 OMARCHY_PATH=/usr/share/omarchy
export PATH=/usr/share/omarchy/bin:/usr/local/bin:/usr/bin
PRE
cat <<'REMOTE'
cd /tmp
IPC() { omarchy-shell omarkyy.tablet "$@" 2>&1 | grep -v -E "WARN|Qt depends|If this causes|for more information"; }
LETRAS() { local s=$1 i; for ((i = 0; i < ${#s}; i++)); do IPC type "${s:i:1}" >/dev/null; sleep 0.12; done; sleep 0.4; }
KEYC() { IPC key "$1" "$2" >/dev/null; sleep 0.3; }
FOCUS() { for i in $(seq 1 40); do hyprctl activewindow | grep -qi "class: $1" && return 0; sleep 0.5; done; return 1; }
FAIL=0
cmp_case() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1"; printf '      esperado: [%s]\n      obtenido: [%s]\n' "$2" "$3"; FAIL=1; fi; }
LEE() { sleep 0.3; cat /tmp/osk-entry.txt; }
BORRA() { KEYC 30 1; KEYC 111 0; }
IPC inputmode auto >/dev/null
python3 -I /tmp/osk-entry.py >/dev/null 2>&1 & GP=$!     # campo GTK4 propio (no toca borradores de otras apps)
if FOCUS uke.oskprueba; then sleep 1.5
  echo "== estado: $(IPC status)"
  BORRA; LETRAS "tambien "; cmp_case "autocorrige tilde: tambien -> también" "también " "$(LEE)"
  BORRA; LETRAS "hola tambien "; KEYC 14 0; cmp_case "Retroceso deshace la corrección" "hola tambien" "$(LEE)"
  LETRAS " "; cmp_case "la palabra rechazada no se vuelve a corregir" "hola tambien " "$(LEE)"
  BORRA; LETRAS "esta "; cmp_case "palabra válida sin tocar (esta)" "esta " "$(LEE)"
  BORRA; LETRAS "graci"; S=$(IPC status); echo "      status: $S"
  echo "$S" | grep -q '"sugs":\[[^]]*"[Gg]racias"' && echo "PASS  sugiere gracias" || { echo "FAIL  sugiere gracias"; FAIL=1; }
  IPC pick 0 >/dev/null; sleep 0.5; cmp_case "elegir sugerencia" "gracias " "$(LEE)"
  BORRA; LETRAS "cancion,"; cmp_case "autocorrige ante puntuación" "canción," "$(LEE)"
  BORRA; IPC autocorrectToggle >/dev/null; LETRAS "tambien "; IPC autocorrectToggle >/dev/null
  cmp_case "autocorrección desactivada no toca" "tambien " "$(LEE)"
  BORRA; IPC type "Camión, pingüino, ¿qué?" >/dev/null; sleep 0.6; cmp_case "texto largo (dictado) intacto" "Camión, pingüino, ¿qué?" "$(LEE)"
  BORRA
else echo "FAIL  osk-entry no tomó el foco"; FAIL=1; fi
kill $GP 2>/dev/null; sleep 1; kill -9 $GP 2>/dev/null
# foot = terminal: sin autocorrección (content purpose terminal) — lo que se escribe llega tal cual
rm -f /tmp/osk-pred-foot.txt
foot --title osk-pred-foot -e sh -c 'cat > /tmp/osk-pred-foot.txt' & FP=$!
if FOCUS foot; then sleep 1; LETRAS "tambien ls"; KEYC 28 0; sleep 0.5
  cmp_case "foot: sin autocorrección" "tambien ls" "$(sed -n 1p /tmp/osk-pred-foot.txt)"
else echo "FAIL  foot no tomó el foco"; FAIL=1; fi
kill $FP 2>/dev/null
echo "RESULTADO: $([ $FAIL = 0 ] && echo OK || echo FALLOS)"
exit $FAIL
REMOTE
} | ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=10 "$HOST" 'setpriv --reuid=1001 --regid=1001 --init-groups bash -s'
