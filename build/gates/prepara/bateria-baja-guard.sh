#!/usr/bin/env bash
# bateria-baja-guard.sh — proteccion de bateria baja en uke (Arch aarch64)
#
# QUE HACE
#   Vigila /sys/class/power_supply/qcom-battmgr-bat y, con HISTERESIS, avisa al 15 % y
#   actua al 8 % (apagado por defecto). Pensado para systemd timer (uke-bateria-baja.timer).
#
# POR QUE ASI (trampas ya pagadas en el proyecto)
#   1. NO se asume un valor si falta el nodo. El hermano tenia
#      `capacity=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo 100)`
#      y su vigilante NUNCA apagaba (la ruta era la de Android, inexistente en Arch).
#      Aqui: sin nodo -> exit 4 y se GRITA en el log. Nunca se inventa un 100.
#   2. NO se actua con UNA sola lectura: el fuel gauge Xiaomi recien despierto da
#      capacity=0 y voltage_now absurdo (2,59 V medidos el 28-sep). Se exigen N muestras
#      consecutivas + un voltage_now plausible (>= 3,0 V).
#   3. NO se suspende por defecto: hoy no hay wake source y s2idle seria irrecuperable
#      (ver suspend-prueba.sh). La accion por defecto es poweroff.
#   4. current_now no se usa para decidir (convencion ambigua en este driver).
#
# USO
#   bateria-baja-guard.sh [--once] [--dry-run] [--umbral N] [--apagado N] [--accion X]
#     --once        una pasada (lo normal desde el timer)
#     --dry-run     no ejecuta poweroff/suspend; solo loguea lo que haria
#     --umbral N    umbral de AVISO en % (def 15, o $UKE_UMBRAL_AVISO)
#     --apagado N   umbral de ACCION en % (def 8,  o $UKE_UMBRAL_APAGADO)
#     --accion X    poweroff | suspend | log   (def poweroff, o $UKE_ACCION)
#
# VARIABLES
#   UKE_BAT_NODO     ruta del supply (def /sys/class/power_supply/qcom-battmgr-bat)
#   UKE_MUESTRAS     muestras consecutivas exigidas (def 3)
#   UKE_ESTADO       fichero de contadores (def /run/uke-bateria-baja.state)
#   UKE_LOG          log (def /var/log/uke-bateria.log)
#
# EXIT  0 ok / 2 umbral alcanzado y accion tomada / 3 umbral alcanzado (dry-run o accion=log)
#       4 sin bateria visible / 5 lectura no fiable / 1 error de uso
#
# INSTALACION: /usr/local/bin/bateria-baja-guard.sh + uke-bateria-baja.{service,timer}
#   systemctl daemon-reload && systemctl enable --now uke-bateria-baja.timer

set -u

BAT=${UKE_BAT_NODO:-/sys/class/power_supply/qcom-battmgr-bat}
UMBRAL_AVISO=${UKE_UMBRAL_AVISO:-15}
UMBRAL_APAGADO=${UKE_UMBRAL_APAGADO:-8}
MUESTRAS=${UKE_MUESTRAS:-3}
ACCION=${UKE_ACCION:-poweroff}
ESTADO=${UKE_ESTADO:-/run/uke-bateria-baja.state}
LOG=${UKE_LOG:-/var/log/uke-bateria.log}
dry=0

while (($#)); do
  case "$1" in
    --once)    : ;;
    --dry-run) dry=1 ;;
    --umbral)  UMBRAL_AVISO=${2:-}; shift ;;
    --apagado) UMBRAL_APAGADO=${2:-}; shift ;;
    --accion)  ACCION=${2:-}; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "uso: $0 [--once] [--dry-run] [--umbral N] [--apagado N] [--accion poweroff|suspend|log]" >&2; exit 1 ;;
  esac
  shift
done

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }
rd()  { [[ -r $1 ]] && cat "$1" 2>/dev/null || return 1; }

# lock: una sola instancia (el timer puede solaparse). /run si se puede, si no /tmp.
if [[ -w /run ]]; then exec 9>/run/uke-bateria-baja.lock 2>/dev/null; else exec 9>/tmp/uke-bateria-baja.lock 2>/dev/null; fi
flock -n 9 || { log "ya hay una instancia corriendo; salgo"; exit 0; }

notificar() { # $1 = texto
  if command -v omarchy-notification-send >/dev/null 2>&1; then
    omarchy-notification-send -g "󰁹" -u critical "Batería baja" "$1" -i battery-caution -t 60000 2>/dev/null || true
  fi
  if command -v wall >/dev/null 2>&1; then
    printf '\n*** uke: %s ***\n' "$1" | wall 2>/dev/null || true
  fi
}

# ---- 0. sin nodo: NO se asume nada ------------------------------------------
if [[ ! -d $BAT ]]; then
  log "SIN BATERIA VISIBLE ($BAT). Cadena ADSP caida o incompleta."
  log "  -> no se puede proteger nada; revisa: systemctl status uke-adsp.service"
  exit 4
fi

present=$(rd "$BAT/present" || true)
status=$(rd "$BAT/status" || true)
cap=$(rd "$BAT/capacity" || true)
vnow=$(rd "$BAT/voltage_now" || true)

[[ $present == 1 ]] || { log "bateria no presente (present='${present:-?}'); nada que hacer"; exit 0; }

# ---- 1. fiabilidad ----------------------------------------------------------
if [[ ! $cap =~ ^[0-9]+$ ]]; then
  log "capacity ilegible ('${cap:-}'); no se actua (ni se asume 100)"; exit 5
fi
if [[ ! $vnow =~ ^[0-9]+$ ]]; then
  log "voltage_now ilegible ('${vnow:-}'); no se actua"; exit 5
fi
if (( vnow < 3000000 )); then
  log "voltage_now=$((vnow/1000)) mV < 3000 mV: lectura NO FIABLE (fuel gauge sin estabilizar)."
  log "  no se actua: apagar por un dato absurdo es tan malo como no apagar nunca."
  exit 5
fi
if (( cap > 100 )); then
  log "capacity=$cap > 100: lectura no fiable; no se actua"; exit 5
fi

# ---- 2. contadores ----------------------------------------------------------
# formato: <bajas_consecutivas> <ya_avisado 0|1>
bajas=0; avisado=0
if [[ -r $ESTADO ]]; then read -r bajas avisado < "$ESTADO" 2>/dev/null || true; fi
[[ $bajas =~ ^[0-9]+$ ]] || bajas=0
[[ $avisado =~ ^[0-9]+$ ]] || avisado=0

cargando=0
case "$status" in
  Charging|Full|"Not charging") cargando=1 ;;
esac

if (( cargando )); then
  (( bajas || avisado )) && log "cargando de nuevo (status=$status); reinicio contadores"
  printf '0 0\n' > "$ESTADO"; exit 0
fi

if (( cap <= UMBRAL_AVISO )); then
  bajas=$((bajas+1))
else
  bajas=0; avisado=0
fi
printf '%d %d\n' "$bajas" "$avisado" > "$ESTADO"

log "cap=${cap}% V=$((vnow/1000))mV status=${status:-?} muestras_bajas=$bajas/$MUESTRAS (aviso<=${UMBRAL_AVISO}% accion<=${UMBRAL_APAGADO}%)"

if (( bajas < MUESTRAS )); then exit 0; fi

# ---- 3. aviso --------------------------------------------------------------
if (( cap <= UMBRAL_AVISO && !avisado )); then
  notificar "Batería al ${cap}% (V=$((vnow/1000)) mV). Enchufa el cargador de pared."
  log "AVISO emitido al ${cap}%"
  printf '%d 1\n' "$bajas" > "$ESTADO"
fi

# ---- 4. accion --------------------------------------------------------------
if (( cap > UMBRAL_APAGADO )); then exit 0; fi

case "$ACCION" in
  poweroff)
    if (( dry )); then log "DRY-RUN: systemctl poweroff (cap=${cap}%)"; exit 3; fi
    log "ACCION: apagando la tablet por bateria baja (cap=${cap}% <= ${UMBRAL_APAGADO}%)"
    notificar "Batería al ${cap}%. Apagando para no dañar la celda."
    sync
    systemctl poweroff || /sbin/poweroff || echo o > /proc/sysrq-trigger
    exit 2 ;;
  suspend)
    log "ACCION: suspend (OJO: sin wake source verificado, puede no volver; ver suspend-prueba.sh)"
    if (( dry )); then log "DRY-RUN: systemctl suspend"; exit 3; fi
    systemctl suspend; exit 2 ;;
  log|*)
    log "ACCION=log: umbral de apagado alcanzado (cap=${cap}%) pero no se apaga (dry)"
    exit 3 ;;
esac
