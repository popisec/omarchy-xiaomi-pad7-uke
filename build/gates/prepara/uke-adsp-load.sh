#!/usr/bin/env bash
# uke-adsp-load.sh — levanta la CADENA DE ENERGIA de uke (ADSP + glink + pmic_glink + battmgr)
#
# POR QUE EXISTE
#   El kernel k1 trae toda la cadena como MODULOS (=m) y NO la carga nadie: en los boots
#   k4..k6b no hay una sola linea de remoteproc/battmgr y /sys/class/power_supply esta
#   vacio. Cuando se cargan a mano (medido el 28-sep) aparecen qcom-battmgr-bat/-usb/-wls
#   y voltage_now=3954881 uV. Este script hace esa carga de forma ORDENADA e IDEMPOTENTE.
#
#   ADVERTENCIA (ledger #404): QRTR_SMD y BATTERY_QCOM_BATTMGR BUILT-IN wedgean el arranque
#   (sin panic, consola muda). Por eso van como modulo. NO cambiar el .config a =y.
#
# ORDEN (REV-ENERGIA F4, validado; el ADSP se arranca al FINAL para que el locator
#        servreg de pd_mapper ya este anunciado cuando el ADSP pida el PDR charger_pd):
#   qcom_sysmon -> qcom_common -> qcom_pil_info -> qcom_q6v5 -> qcom_glink_smem
#   -> qcom_q6v5_pas -> qrtr_smd -> qcom_pd_mapper -> pmic_glink -> qcom_battmgr
#   y despues: echo start > /sys/class/remoteproc/remoteprocN/state  (el ADSP)
#
#   Dependencias reales (strings .ko depends=, build fix528 5-oct):
#     qcom_q6v5_pas depende de qcom_q6v5,qcom_common,qcom_sysmon,qcom_pil_info
#     qcom_q6v5 depende de qcom_sysmon; pd_mapper y qrtr_smd sin deps.
#   pmic_glink y qcom_battmgr son BUILT-IN desde fix528 (=y en .config; no hay .ko:
#   el script lo detecta y no lo trata como fallo). El wedge #404 (QRTR_SMD/BATTMGR
#   =y colgando el arranque) era del kernel k1; el fix528 ya trae BATTMGR=y de serie.
#
#   NOTA: depmod NO resuelve bien en esta imagen (faltan modules.order/modules.builtin),
#   por eso se usa insmod con rutas explicitas y se cae a modprobe como respaldo.
#
# USO: uke-adsp-load.sh [--force] [--verbose]
# EXIT: 0 cadena OK / 1 aviso (algo no subio; se detalla) / 2 error de entorno

set -u

FW_DIR=${UKE_FW_DIR:-/usr/local/share/uke/adsp-fw}
FW_DST=${UKE_FW_DST:-/lib/firmware}
MODROOT="/lib/modules/$(uname -r)"
VERBOSE=0
FORCE=0
LOG=${UKE_ADSP_LOG:-/var/log/uke-adsp.log}

while (($#)); do
  case "$1" in
    --force)   FORCE=1 ;;
    --verbose) VERBOSE=1 ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "uso: $0 [--force] [--verbose]" >&2; exit 2 ;;
  esac
  shift
done

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }
vlog(){ (( VERBOSE )) && log "$@"; return 0; }

# ---------- 0. ya esta? ------------------------------------------------------
if [[ -d /sys/class/power_supply/qcom-battmgr-bat && $FORCE == 0 ]]; then
  log "cadena ya arriba (qcom-battmgr-bat presente); nada que hacer"
  exit 0
fi

# ---------- 1. firmware del ADSP --------------------------------------------
# adsp.mdt (8044 B, sha256 fd874a8d...) + adsp.b00..b52 (51) + adsp_dtb.mdt (4044 B)
# + adsp_dtb.b00..b02 (3). Van PLANOS en /lib/firmware.
if [[ ! -r $FW_DST/adsp.mdt ]]; then
  if [[ -r $FW_DIR/adsp.mdt ]]; then
    log "copiando firmware ADSP desde $FW_DIR a $FW_DST"
    cp -f "$FW_DIR"/adsp.mdt "$FW_DIR"/adsp_dtb.mdt "$FW_DST"/ 2>/dev/null
    cp -f "$FW_DIR"/adsp.b?? "$FW_DIR"/adsp_dtb.b?? "$FW_DST"/ 2>/dev/null
  else
    log "FALTA /lib/firmware/adsp.mdt y no hay copia en $FW_DIR"
    log "  la cadena NO puede subir sin firmware; aborto"
    exit 1
  fi
fi
nseg=$(ls "$FW_DST"/adsp.b?? 2>/dev/null | wc -l)
vlog "firmware: adsp.mdt $(wc -c < "$FW_DST/adsp.mdt" 2>/dev/null) B, $nseg segmentos adsp.b??"
(( nseg >= 40 )) || log "AVISO: solo $nseg segmentos adsp.b?? (esperados ~51)"

# ---------- 2. modulos ------------------------------------------------------
localizar() { # localizar <nombre-modulo> -> ruta .ko (imprime) o vacio
  local n=$1 f
  # ojo: el fichero puede llevar guion aunque el modulo use guion_bajo (qrtr-smd.ko)
  for f in "${n}.ko" "${n//_/-}.ko"; do
    local hit
    hit=$(find "$MODROOT" -name "$f" -print -quit 2>/dev/null)
    [[ -n $hit ]] && { printf '%s' "$hit"; return 0; }
  done
  return 1
}

cargar() { # cargar <nombre> [critico]
  local n=$1 crit=${2:-0} ko rc
  if grep -q "^${n} " /proc/modules 2>/dev/null; then vlog "$n ya cargado"; return 0; fi
  # built-in desde fix528 (pmic_glink, qcom_battmgr): sin .ko pero presente
  if [[ -d /sys/module/${n//-/_} ]]; then vlog "$n es built-in (presente)"; return 0; fi
  if ko=$(localizar "$n"); then
    if timeout 20 insmod "$ko" 2>>"$LOG"; then log "insmod $n OK"; return 0; fi
    rc=$?
    # "File exists" (17) = ya estaba (built-in o carrera): no es fallo
    if grep -q "^${n} " /proc/modules 2>/dev/null; then log "$n ya estaba (insmod dijo $rc)"; return 0; fi
    log "insmod $n FALLO (rc=$rc)"
  else
    # sin .ko y sin /sys/module: built-in sin entrada en sysfs o falta de verdad
    if modprobe "$n" 2>>"$LOG"; then log "modprobe $n OK"; return 0; fi
    if (( crit )); then
      log "$n es CRITICO: no hay .ko en $MODROOT ni /sys/module"
      return 1
    fi
    vlog "$n sin .ko: asumo built-in (no criticos: pmic_glink/battmgr van =y)"
    return 0
  fi
  if timeout 20 modprobe "$n" 2>>"$LOG"; then log "modprobe $n OK"; return 0; fi
  (( crit )) && log "$n es CRITICO y no cargo"
  return 1
}

# Fase 1: stack del ADSP (orden de dependencias insmod; sysmon primero)
for m in qcom_sysmon qcom_common qcom_pil_info qcom_q6v5 qcom_glink_smem qcom_q6v5_pas; do
  cargar "$m" 1 || log "AVISO: $m no cargo; el ADSP probablemente no subira"
done

# ---------- 3. transporte + locator + pmic_glink (ANTES de arrancar el ADSP, F4) ----
cargar qrtr_smd 1 || log "AVISO: qrtr_smd no cargo"
cargar qcom_pd_mapper 1 || log "AVISO: qcom_pd_mapper no cargo (sin el no sube el PDR charger_pd)"
cargar pmic_glink 0 || log "AVISO: pmic_glink no cargo"
cargar qcom_battmgr 0 || log "AVISO: qcom_battmgr no cargo (¿built-in?)"

# ---------- 4. arrancar el ADSP (el ultimo paso de la secuencia, F4) ---------------
rproc=""
for r in /sys/class/remoteproc/remoteproc*; do
  [[ -e $r ]] || continue
  [[ "$(cat "$r/name" 2>/dev/null)" == adsp ]] && rproc=$r
done
if [[ -z $rproc ]]; then
  log "no aparece el remoteproc del ADSP (¿qcom_q6v5_pas sin cargar? ¿DT?)"
else
  st=$(cat "$rproc/state" 2>/dev/null)
  if [[ $st == running ]]; then
    vlog "ADSP ya running"
  else
    log "arrancando ADSP en $rproc (estado=$st)"
    if timeout 40 sh -c "echo start > '$rproc/state'" 2>>"$LOG"; then
      sleep 1
      log "ADSP estado=$(cat "$rproc/state" 2>/dev/null)"
    else
      log "FALLO al arrancar el ADSP (timeout/err); revisa dmesg"
    fi
  fi
fi

# ---------- 5. esperar la bateria (y reintentar el lookup de PDR) ----------
esperar_bat() { # $1 = segundos
  local t=0 lim=$1
  while (( t < lim )); do
    [[ -d /sys/class/power_supply/qcom-battmgr-bat ]] && return 0
    sleep 1; t=$((t+1))
  done
  return 1
}

if esperar_bat 20; then
  log "CADENA OK: $(ls /sys/class/power_supply/ | tr '\n' ' ')"
  log "  capacity=$(cat /sys/class/power_supply/qcom-battmgr-bat/capacity 2>/dev/null)%" \
      "voltage_now=$(cat /sys/class/power_supply/qcom-battmgr-bat/voltage_now 2>/dev/null) uV" \
      "status=$(cat /sys/class/power_supply/qcom-battmgr-bat/status 2>/dev/null)"
  exit 0
fi

# Reintento: si el locator se anuncio DESPUES del lookup de pmic_glink, este no lo vera.
# Recargar pmic_glink fuerza un lookup nuevo. (Medido: el PDR charger_pd tarda ~0,1-0,5 s
# tras el "start" del ADSP, pero el orden importa.)
log "la bateria no aparece; reintento recargando pmic_glink (lookup de PDR)"
for m in qcom_battmgr pmic_glink; do
  grep -q "^${m} " /proc/modules 2>/dev/null && timeout 20 rmmod "$m" 2>>"$LOG" || true
done
cargar pmic_glink 0 || true
cargar qcom_battmgr 0 || true

if esperar_bat 15; then
  log "CADENA OK tras reintento: $(ls /sys/class/power_supply/ | tr '\n' ' ')"
  exit 0
fi

log "CADENA INCOMPLETA: no hay qcom-battmgr-bat. dmesg util:"
dmesg 2>/dev/null | grep -iE 'remoteproc|q6v5|glink|qrtr|PDR|pmic_glink|battmgr|charger_pd' | tail -15 | tee -a "$LOG" >&2
exit 1
