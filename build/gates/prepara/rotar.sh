#!/usr/bin/env bash
# rotar.sh — rotación manual de pantalla + táctil en Hyprland 0.56 (Omarchy 4.0.4)
#
# QUÉ HACE
#   1) Cambia el transform del monitor (0=normal, 1=90, 2=180, 3=270) PRESERVANDO
#      la escala del usuario (sin esto Hyprland re-deriva la escala y la pisa).
#   2) Pone el MISMO índice en input:touchdevice:transform. Hyprland NO remapea
#      las coordenadas táctiles al rotar el monitor: hay que sincronizar la
#      matriz de calibración de libinput o los toques caen espejados/desplazados.
#      (Hyprland src/managers/input/InputManager.cpp: setTouchDeviceConfigs() lee
#      input:touchdevice:transform y llama libinput_device_config_calibration_set_matrix;
#      MATRICES[8][6] en InputManager.hpp; default -1 = sin matriz.)
#
# USO
#   rotar.sh next            # gira +90
#   rotar.sh prev            # gira -90
#   rotar.sh 0|90|180|270    # transform absoluto
#   rotar.sh normal|right|inverted|left
#   rotar.sh N               # 0..3 directo
#   Opciones: --silent  --no-touch  --monitor NOMBRE  --print
#
# ENV
#   OMARCHY_ROTATE_DISPLAY   monitor objetivo (si no, el primero de hyprctl)
#   ROTATE_OSD=omarchy|notify|none   OSD opcional tras rotar (def. none)
#
# NOTA 0.56: si la config es el parser nuevo (Lua), "hyprctl keyword" falla con
#   "keyword can't work with non-legacy parsers. Use eval." -> se usa eval primero
#   y keyword solo como respaldo (parser legacy). No mezclar ambos.
#
# INSTALACIÓN (cuando la tablet vuelva):
#   install -m755 rotar.sh /usr/local/bin/rotar.sh
#   (o ~/.local/bin/rotar.sh; lo llama autorotate.sh vía ROTATOR=...)

set -u

DISP="${OMARCHY_ROTATE_DISPLAY:-}"
SILENT=0
TOUCH=1
DOPRINT=0
OSD="${ROTATE_OSD:-none}"

die() { printf 'rotar.sh: %s\n' "$*" >&2; exit 1; }
say() { (( SILENT )) || printf '%s\n' "$*"; }

command -v hyprctl >/dev/null 2>&1 || die "hyprctl no está en PATH (¿sesión Hyprland?)"

# ---------- parseo de argumentos -------------------------------------------
[ $# -ge 1 ] || die "uso: rotar.sh next|prev|0|90|180|270 [--silent] [--no-touch] [--monitor NAME]"
ARG="$1"; shift

while [ $# -gt 0 ]; do
  case "$1" in
    --silent)    SILENT=1 ;;
    --no-touch)  TOUCH=0 ;;
    --print)     DOPRINT=1 ;;
    --monitor)   shift; DISP="${1:-}" ;;
    -h|--help)   sed -n '2,40p' "$0"; exit 0 ;;
    *)           die "opción desconocida: $1" ;;
  esac
  shift
done

# ---------- estado actual (monitor + scale + transform) ---------------------
read_state() { # -> imprime "name transform scale" del monitor objetivo
  python3 - "$DISP" <<'PY'
import json, subprocess, sys
want = sys.argv[1] if len(sys.argv) > 1 else ""
try:
    mons = json.loads(subprocess.check_output(["hyprctl", "monitors", "-j"], text=True))
except Exception as e:
    sys.stderr.write("no puedo leer hyprctl monitors -j: %s\n" % e); sys.exit(3)
if not mons:
    sys.stderr.write("no hay monitores en Hyprland\n"); sys.exit(4)
mon = None
for m in mons:
    if want and m.get("name") == want:
        mon = m; break
if mon is None:
    mon = next((m for m in mons if m.get("focused")), mons[0])
print(mon.get("name", ""), int(mon.get("transform", 0) or 0), mon.get("scale", 1))
PY
}

STATE="$(read_state)" || die "no puedo leer el estado del monitor"
set -- $STATE
NAME="${1:-}"; CUR="${2:-0}"; SCALE="${3:-1}"
[ -n "$NAME" ] || die "no encuentro monitor (¿Hyprland sin outputs?)"
DISP="$NAME"

# ---------- normalizar argumento -> N (0..3) -------------------------------
case "$ARG" in
  next)              N=$(( (CUR + 1) % 4 )) ;;
  prev)              N=$(( (CUR + 3) % 4 )) ;;
  0|normal)          N=0 ;;
  90|right)          N=1 ;;
  180|inverted|inv)  N=2 ;;
  270|left)          N=3 ;;
  1|2|3)             N="$ARG" ;;
  *) die "argumento no válido: $ARG (usa next|prev|0|90|180|270|normal|right|inverted|left)" ;;
esac

# ---------- aplicar ---------------------------------------------------------
# 1) monitor (preservando escala): Lua eval (0.56) con respaldo legacy
if hyprctl eval "hl.monitor({ output = \"${DISP}\", transform = ${N}, scale = ${SCALE} })" >/dev/null 2>&1; then
  :
else
  hyprctl keyword monitor "${DISP},preferred,auto,${SCALE},${N}" >/dev/null 2>&1 \
    || die "no pude aplicar transform=${N} en ${DISP} (eval y keyword fallaron)"
fi

# 2) táctil sincronizado (misma matriz que el monitor)
if (( TOUCH )); then
  hyprctl eval "hl.config({ input = { touchdevice = { transform = ${N} } } })" >/dev/null 2>&1 \
    || hyprctl keyword input:touchdevice:transform "$N" >/dev/null 2>&1 \
    || say "aviso: no pude fijar input:touchdevice:transform=${N} (¿device táctil aún no presente?)"
fi

# ---------- verificacion + feedback -----------------------------------------
VER="$(hyprctl monitors -j 2>/dev/null | python3 -c 'import json,sys;m=json.load(sys.stdin);print(next((x.get("transform",-1) for x in m if x.get("name")=="'"$DISP"'"),-1))' 2>/dev/null || echo "?")"
TOUCHPOS="$(hyprctl getoption input:touchdevice:transform -j 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin).get("int",-1))' 2>/dev/null || echo "?")"

say "rotar.sh: ${DISP} transform ${CUR} -> ${VER} (scale ${SCALE}) · touchdevice transform ${TOUCHPOS}"

if (( DOPRINT )); then
  printf 'monitor=%s transform=%s scale=%s touch=%s\n' "$DISP" "$VER" "$SCALE" "$TOUCHPOS"
fi

case "$OSD" in
  omarchy) command -v omarchy >/dev/null 2>&1 && omarchy osd -i rotate-cw -m "Rotate: ${N}" >/dev/null 2>&1 || true ;;
  notify)  command -v notify-send >/dev/null 2>&1 && notify-send -i video-display "Rotate: ${N}" 2>/dev/null || true ;;
  none)    : ;;
esac

[ "$VER" = "$N" ] || { say "ERROR: transform no aplicado (leído ${VER}, quería ${N})"; exit 1; }
exit 0
