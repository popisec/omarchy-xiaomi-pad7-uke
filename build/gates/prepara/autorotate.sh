#!/usr/bin/env bash
# autorotate.sh — auto-rotación de pantalla + táctil para uke / Omarchy 4.0.4 (Hyprland 0.56)
#
# FUENTES DE DATOS
#   backend proxy  : `monitor-sensor --accel` de iio-sensor-proxy 3.9 (D-Bus
#                    net.hadess.SensorProxy, propiedad AccelerometerOrientation).
#                    Es el backend natural para la uke: su IMU (LSM6DSO) vive en el
#                    Sensor Core del ADSP, y iio-sensor-proxy 3.9 (ALARM extra)
#                    habla con el SSC vía libssc (libqrtr-glib) -> /dev/fastrpc-adsp*.
#   backend sysfs  : lee /sys/bus/iio/devices/*/in_accel_*_raw (driver st_lsm6dsx)
#                    si algún día el sensor queda en un bus del AP (I2C/SPI).
#   auto (defecto) : proxy si existe; si dice "No accelerometer" 15 s y hay un
#                    device IIO, cambia a sysfs.
#
# DEBOUNCE (imprescindible): la lectura debe permanecer estable
# AUTOROTATE_STABLE_MS ms (def. 800) antes de rotar; así no "parpadea" por las
# 4 posturas al coger la tablet. No se reaplica la misma postura dos veces.
#
# APLICACIÓN: llama a rotar.sh (que rota monitor + input:touchdevice:transform).
#
# USO
#   autorotate.sh                 # corre el daemon (ideal como servicio de usuario)
#   autorotate.sh --once          # imprime UNA postura y sale
#   autorotate.sh --dry-run       # no rota; registra lo que haría
#   autorotate.sh --lock|--unlock|--status|--toggle   # bloqueo manual (/tmp/uke-rotation-locked)
#   autorotate.sh --backend proxy|sysfs|auto
#   autorotate.sh --verbose
#
# ENV
#   ROTATOR=/usr/local/bin/rotar.sh     script de rotación
#   OMARCHY_ROTATE_DISPLAY=eDP-1        monitor (lo hereda rotar.sh)
#   AUTOROTATE_STABLE_MS=800            debounce
#   AUTOROTATE_POLL_MS=400              periodo del backend sysfs
#   AUTOROTATE_LOCK=/tmp/uke-rotation-locked
#   AUTOROTATE_LABELS="normal left-up bottom-up right-up"   -> transform 0 1 2 3
#   AUTOROTATE_FLAT=4.0                 umbral m/s^2 para "unknown" (sysfs)
#   ROTATE_OSD=none|omarchy|notify      feedback visual (lo hereda rotar.sh)
#
# CALIBRACIÓN PENDIENTE (obligatoria en la uke): los nombres de postura y sus
# signos dependen del montaje del sensor. Con `monitor-sensor --accel` girando la
# tablet (o `autorotate.sh --once`) comprobar que "normal"=0, "left-up"=1 ...
# Si no cuadra, ajustar AUTOROTATE_LABELS (orden de transforms) o la tabla de
# signos de classify_sysfs(). Ver PX-rotacion.md §6/§7.
#
# UNIDAD SYSTEMD DE USUARIO (sugerida):
#   ~/.config/systemd/user/uke-autorotate.service
#     [Unit]
#     Description=uke auto-rotate (iio-sensor-proxy -> Hyprland)
#     PartOf=graphical-session.target
#     After=graphical-session.target
#     [Service]
#     ExecStart=%h/.local/bin/autorotate.sh --verbose
#     Restart=on-failure
#     [Install]
#     WantedBy=graphical-session.target

set -u

ROTATOR="${ROTATOR:-/usr/local/bin/rotar.sh}"
BACKEND="${AUTOROTATE_BACKEND:-auto}"
STABLE_MS="${AUTOROTATE_STABLE_MS:-800}"
POLL_MS="${AUTOROTATE_POLL_MS:-400}"
LOCK="${AUTOROTATE_LOCK:-${XDG_RUNTIME_DIR:-/tmp}/uke-rotation-locked}"
LABELS="${AUTOROTATE_LABELS:-normal left-up bottom-up right-up}"   # índice = transform
FLAT="${AUTOROTATE_FLAT:-4.0}"
DRY=0
VERBOSE=0
MODE=run

command -v python3 >/dev/null 2>&1 || { printf 'autorotate.sh: falta python3\n' >&2; exit 2; }

log()  { printf '[autorotate] %s\n' "$*" >&2; }
vlog() { (( VERBOSE )) && log "$@"; return 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --once)     MODE=once ;;
    --dry-run)  DRY=1 ;;
    --lock)     : >"$LOCK"; log "bloqueo activado ($LOCK)"; exit 0 ;;
    --unlock)   rm -f "$LOCK"; log "bloqueo quitado"; exit 0 ;;
    --toggle)   if [ -e "$LOCK" ]; then rm -f "$LOCK"; log "desbloqueado"; else : >"$LOCK"; log "bloqueado"; fi; exit 0 ;;
    --status)   if [ -e "$LOCK" ]; then printf 'locked\n'; else printf 'unlocked\n'; fi; exit 0 ;;
    --backend)  shift; BACKEND="${1:-auto}" ;;
    --verbose|-v) VERBOSE=1 ;;
    -h|--help)  sed -n '2,72p' "$0"; exit 0 ;;
    *) printf 'autorotate.sh: opción desconocida: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

case "$BACKEND" in auto|proxy|sysfs) : ;; *) log "backend inválido: $BACKEND"; exit 2 ;; esac
if [ "$MODE" = run ] && [ "$DRY" = 0 ] && [ ! -x "$ROTATOR" ]; then
  log "aviso: ROTATOR=$ROTATOR no ejecutable (¿falta instalar rotar.sh?)"
fi

# ---------------------------------------------------------------------------
# mapas postura -> transform
# ---------------------------------------------------------------------------
label2transform() { # $1 = postura ; imprime índice 0..3 o vacío
  local i=0
  for l in $LABELS; do
    [ "$1" = "$l" ] && { printf '%s' "$i"; return 0; }
    i=$((i + 1))
  done
  return 1
}

# ---------------------------------------------------------------------------
# backend sysfs: clasificación por eje dominante (misma tabla que texp-orient)
# ---------------------------------------------------------------------------
SYSFS_DEV=""
find_iio_accel() {
  local d
  for d in /sys/bus/iio/devices/iio:device*; do
    [ -f "$d/in_accel_x_raw" ] || continue
    case "$(cat "$d/name" 2>/dev/null)" in
      *gyro*) continue ;;
    esac
    SYSFS_DEV="$d"; return 0
  done
  return 1
}

read_sysfs_label() {
  [ -n "$SYSFS_DEV" ] || find_iio_accel || { printf ''; return 1; }
  python3 - "$SYSFS_DEV" "$FLAT" <<'PY'
import sys, os
d, flat = sys.argv[1], float(sys.argv[2])
def rd(p, default="1"):
    try:
        with open(p) as f: return float(f.read().strip())
    except Exception: return float(default)
sc = rd(os.path.join(d, "in_accel_scale"), "1")
try:
    g = [rd(os.path.join(d, f"in_accel_{a}_raw"), "0") * sc for a in "xyz"]
except Exception:
    print(""); sys.exit(0)
dom = max(range(3), key=lambda i: abs(g[i]))
val = g[dom]
if abs(val) < flat:
    print("unknown"); sys.exit(0)
if val > 0:
    print(["left-up", "bottom-up", "bottom-up"][dom])
else:
    print(["right-up", "normal", "normal"][dom])
PY
}

# ---------------------------------------------------------------------------
# máquina de estados (debounce) + aplicación
# ---------------------------------------------------------------------------
applied=""
cand=""; cand_t=0
no_accel_since=0
start_ts=0

now_ms() { date +%s%3N; }

apply_maybe() { # $1 = postura leída
  local label="$1" now stable t
  [ -n "$label" ] || return 0
  now="$(now_ms)"
  if [ "$label" != "$cand" ]; then
    cand="$label"; cand_t="$now"; vlog "candidata: $label"
  fi
  stable=$(( now - cand_t ))
  (( stable >= STABLE_MS )) || return 0
  [ "$label" = "unknown" ] && return 0
  [ "$label" = "undefined" ] && return 0
  [ "$label" = "$applied" ] && return 0

  if [ -e "$LOCK" ]; then
    vlog "bloqueado: no aplico $label"
    return 0
  fi
  if ! t="$(label2transform "$label")"; then
    log "postura desconocida '$label' (AUTOROTATE_LABELS='$LABELS')"
    return 0
  fi
  if (( DRY )); then
    log "dry-run: aplicaría transform=$t (postura $label)"
  else
    if "$ROTATOR" "$t" >/dev/null 2>&1; then
      log "postura $label -> transform $t"
    else
      log "FALLO al aplicar transform $t (rotar.sh rc=$?)"
    fi
  fi
  applied="$label"
}

# ---------------------------------------------------------------------------
# backend proxy: monitor-sensor --accel
# ---------------------------------------------------------------------------
proxy_available() {
  command -v monitor-sensor >/dev/null 2>&1 || return 1
  return 0
}

run_proxy_forever() {
  local line rc label
  while :; do
    exec 3< <(monitor-sensor --accel 2>&1)
    vlog "monitor-sensor lanzado (fd3)"
    while :; do
      IFS= read -r -t 0.5 -u 3 line; rc=$?
      if [ "$rc" -eq 0 ]; then
        case "$line" in
          *"Accelerometer orientation changed:"*)
            label="${line##*: }"; vlog "proxy: $label"; apply_maybe "$label"
            if [ "$label" != "unknown" ]; then no_accel_since=0; fi
            ;;
          *"Has accelerometer (orientation:"*)
            label="${line#*orientation: }"; label="${label%%,*}"
            vlog "proxy inicial: $label"; apply_maybe "$label"
            ;;
          *"No accelerometer"*)
            [ "$no_accel_since" = 0 ] && { no_accel_since="$(now_ms)"; log "iio-sensor-proxy informa: sin acelerómetro"; }
            ;;
          *"vanished, waiting"*)
            : # normal si el servicio aún no arrancó; se reintenta solo
            ;;
          *)
            vlog "proxy: $line"
            ;;
        esac
      elif [ "$rc" -gt 128 ]; then
        # timeout de 0.5 s: re-evalúa el debounce aunque no lleguen eventos nuevos
        # (monitor-sensor solo emite al CAMBIAR de postura) y, si procede, cae a sysfs.
        [ -n "$cand" ] && apply_maybe "$cand"
        if [ "$no_accel_since" != 0 ]; then
          if [ $(( $(now_ms) - no_accel_since )) -ge 15000 ] && [ "$BACKEND" = auto ]; then
            if find_iio_accel; then
              log "sin acelerómetro por D-Bus; hay IIO en $SYSFS_DEV -> backend sysfs"
              exec 3<&-
              run_sysfs_forever
              return 0
            fi
          fi
        fi
      else
        vlog "monitor-sensor terminó (rc=$rc); relanzo en 1 s"
        break
      fi
    done
    exec 3<&-
    sleep 1
  done
}

# ---------------------------------------------------------------------------
# backend sysfs: sondeo periódico
# ---------------------------------------------------------------------------
run_sysfs_forever() {
  log "backend sysfs (device ${SYSFS_DEV:-auto})"
  local label
  while :; do
    label="$(read_sysfs_label 2>/dev/null || true)"
    if [ -z "${SYSFS_DEV:-}" ]; then
      vlog "sin device IIO con in_accel_x_raw; reintento"
    else
      apply_maybe "$label"
    fi
    sleep "$(python3 -c 'import sys;print(max(50,int(sys.argv[1]))/1000.0)' "$POLL_MS")"
  done
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
case "$MODE" in
  once)
    if [ "$BACKEND" = sysfs ] || { [ "$BACKEND" = auto ] && ! proxy_available; }; then
      read_sysfs_label || true
    else
      timeout 12 monitor-sensor --accel 2>&1 | python3 -c '
import sys, re
last = ""
for line in sys.stdin:
    m = re.search(r"Accelerometer orientation changed: (\S+)", line)
    if m: last = m.group(1)
    m = re.search(r"Has accelerometer \(orientation: (\S+?)[,)]", line)
    if m and not last: last = m.group(1)
print(last)
'
    fi
    ;;
  run)
    log "arranque: backend=$BACKEND estable=${STABLE_MS}ms lock=$LOCK rotator=$ROTATOR"
    case "$BACKEND" in
      proxy) run_proxy_forever ;;
      sysfs) run_sysfs_forever ;;
      auto)
        if proxy_available; then run_proxy_forever; else
          log "monitor-sensor no está; arranco en sysfs"
          run_sysfs_forever
        fi
        ;;
    esac
    ;;
esac
