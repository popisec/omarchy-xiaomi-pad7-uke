#!/bin/bash
# osk-test.sh — prueba extremo a extremo del teclado en pantalla (OSK-REWORK-20261020) en la tablet, via la IPC del plugin
# (servicio -> osk-daemon -> input method / teclado virtual) y comparando con el texto REAL de un campo en foot, gnome-text-editor
# (GTK4) y Firefox (GTK3, perfil temporal). Uso: osk-test.sh [ime|keys|both]   (por defecto ime). Abre ventanas en el
# espacio de trabajo 9 y devuelve el foco al original. NO tocar la tablet mientras corre (las ventanas roban el foco).
# Sale con 1 si algun caso falla.
HERE=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$HERE/../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}
HOST=${UKE_HOST:-root@uke}
MODE=${1:-ime}
ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=10 "$HOST" 'U=$(id -u omarchy); RT=/run/user/$U; HS=$(ls -t $RT/hypr | head -1); WD=$(cd $RT; ls -d wayland-[0-9] | head -1); sudo -u omarchy env XDG_RUNTIME_DIR=$RT HYPRLAND_INSTANCE_SIGNATURE=$HS WAYLAND_DISPLAY=$WD DBUS_SESSION_BUS_ADDRESS=unix:path=$RT/bus OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:/usr/local/bin:/usr/bin LANG=C.UTF-8 HOME=/home/omarchy bash -s -- '"$MODE" <<'REMOTE'
MODE=$1
IPC() { omarchy-shell omarkyy.tablet "$@" 2>&1 | grep -v -E "WARN|Qt depends|If this causes|for more information" ; }
TYPE() { IPC type "$1" >/dev/null; sleep ${2:-0.5}; }
KEY() { IPC key "$1" "$2" >/dev/null; sleep 0.25; }
ENTER() { KEY 28 0; }
CTRL() { KEY "$1" 1; }
FOCUS() { # espera a que la ventana de la clase $1 tenga el foco
  for i in $(seq 1 40); do hyprctl activewindow | grep -qi "class: $1" && return 0; sleep 0.5; done; return 1; }
cd /tmp
FAIL=0
ok() { echo "PASS  $*"; }
ko() { echo "FAIL  $*"; FAIL=1; }
cmp_case() { # nombre esperado obtenido
  if [ "$2" = "$3" ]; then ok "$1"; else ko "$1"; printf '      esperado: %s\n      obtenido: %s\n' "$2" "$3"; fi; }
S1='Camión, pingüino, ¿qué?, ¡ñandú! @€'
S2='ÁÉÍÓÚ ÑÜ áéíóú ñü àèìòù âêîôû ÿ'
S3='[]{}\|~#½¬ºª <>;:_-+*'
ORIG=$(hyprctl activeworkspace | head -1 | sed -E 's/.*workspace ID ([0-9]+).*/\1/')
hyprctl dispatch 'hl.dsp.focus({workspace="9"})' >/dev/null; sleep 1
echo "== estado: $(IPC status)  modo=$MODE  espacio original=$ORIG"
mkdir -p /tmp/osk-test; rm -f /tmp/osk-test/*

run_mode() {
  M=$1; IPC inputmode $M >/dev/null; echo "== modo de entrega: $M"
  # ---- foot: el campo es `cat > fichero` ----
  rm -f /tmp/osk-test/foot.txt
  foot --title osk-test-foot -e sh -c 'cat > /tmp/osk-test/foot.txt' & FP=$!
  if FOCUS foot; then sleep 1
    echo "   foot imActive: $(IPC status | grep -o '"imActive":[a-z]*')"
    TYPE "$S1"; ENTER; TYPE "$S2"; ENTER; TYPE "$S3"; ENTER; TYPE abcX; KEY 14 0; ENTER; TYPE línea; KEY 15 0; TYPE tab; ENTER
    KEY 32 1; sleep 0.7
    cmp_case "foot[$M] S1" "$S1" "$(sed -n 1p /tmp/osk-test/foot.txt)"
    cmp_case "foot[$M] S2 (mayusculas/acentos)" "$S2" "$(sed -n 2p /tmp/osk-test/foot.txt)"
    cmp_case "foot[$M] S3 (AltGr y simbolos)" "$S3" "$(sed -n 3p /tmp/osk-test/foot.txt)"
    cmp_case "foot[$M] Retroceso" "abc" "$(sed -n 4p /tmp/osk-test/foot.txt)"
    cmp_case "foot[$M] Tab" "línea	tab" "$(sed -n 5p /tmp/osk-test/foot.txt)"
  else ko "foot[$M] no tomo el foco"; fi
  kill $FP 2>/dev/null; sleep 0.5
  # ---- gnome-text-editor (GTK4): se lee con Ctrl+A Ctrl+C ----
  gnome-text-editor --standalone --new-window >/dev/null 2>&1 & GP=$!
  if FOCUS org.gnome.TextEditor; then sleep 2
    for n in 1 2 3; do
      eval "X=\$S$n"; CTRL 30; KEY 111 0; TYPE "$X"; CTRL 30; CTRL 46 ; sleep 0.4
      cmp_case "gnome-text-editor[$M] S$n" "$X" "$(wl-paste -n 2>/dev/null)"
    done
    CTRL 30; KEY 111 0; TYPE abcX; KEY 14 0; CTRL 30; CTRL 46; sleep .4; cmp_case "gnome-text-editor[$M] Retroceso" "abc" "$(wl-paste -n 2>/dev/null)"
  else ko "gnome-text-editor[$M] no tomo el foco"; fi
  pkill -f "gnome-text-editor" ; sleep 1; pkill -9 -f "gnome-text-editor"
  # ---- Firefox con perfil temporal (se escribe en su barra de direcciones) ----
  mkdir -p /tmp/osk-test/ffprof
  firefox --no-remote --profile /tmp/osk-test/ffprof --new-window 'data:text/html,<title>osk</title><h1>osk</h1>' >/dev/null 2>&1 & FF=$!
  if FOCUS firefox; then sleep 9; KEY 38 1; sleep 0.5      # Ctrl+L: barra de direcciones (campo GTK3 real)
    for n in 1 2 3; do
      eval "X=\$S$n"; CTRL 30; KEY 111 0; TYPE "$X"; CTRL 30; CTRL 46 ; sleep 0.4
      cmp_case "firefox[$M] S$n" "$X" "$(wl-paste -n 2>/dev/null)"
    done
  else ko "firefox[$M] no tomo el foco"; fi
  kill $FF 2>/dev/null; sleep 1; pkill -f "osk-test/ffprof"
}
case "$MODE" in
  ime) run_mode ime ;;
  keys) run_mode keys ;;
  both) run_mode ime; run_mode keys ;;
  *) run_mode auto ;;
esac
IPC inputmode auto >/dev/null
# ---- el demonio muere: el servicio debe levantarlo solo ----
pkill -x osk-daemon; sleep 4
st=$(IPC status); echo "$st" | grep -q '"daemon":true' && ok "reconexion tras matar osk-daemon ($st)" || ko "el demonio no volvio: $st"
# ---- ping al mostrar ----
rm -f /tmp/osk-test/p.txt
foot --title osk-test-foot2 -e sh -c 'cat > /tmp/osk-test/p.txt' & FP=$!
FOCUS foot && { sleep 1; TYPE "ñandú"; KEY 32 1; sleep .5; cmp_case "tras reconexion: escribe" "ñandú" "$(cat /tmp/osk-test/p.txt)"; }
kill $FP 2>/dev/null
hyprctl dispatch "hl.dsp.focus({workspace=\"$ORIG\"})" >/dev/null
[ $FAIL = 0 ] && echo "RESULTADO: TODO OK" || echo "RESULTADO: HAY FALLOS"
exit $FAIL
REMOTE
