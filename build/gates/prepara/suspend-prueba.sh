#!/usr/bin/env bash
# suspend-prueba.sh — verifica si SUSPENDER es seguro en uke y ejecuta la prueba si lo es.
#
# CONTEXTO (leelo antes de usar --run)
#   * El kernel 7.2-rc2-palawan tiene CONFIG_SUSPEND=y, PSCI 1.1 (OSI) y cpuidle PSCI con
#     idle-states en DT. "freeze" (s2idle) esta SIEMPRE en /sys/power/state
#     (kernel/power/suspend.c: pm_states_init). "mem" (deep) solo si el firmware soporta
#     PSCI SYSTEM_SUSPEND (psci_init_system_suspend, sin mensaje en dmesg).
#   * s2idle SOLO sale si hay un WAKEUP EVENT: pm_wakeup_pending() es la unica condicion de
#     salida (no hay s2idle_ops en ARM64 sin ACPI). Sin wake source armado, la tablet se
#     queda dormida hasta agotar bateria o hasta el reset duro del PON (long-press ~8-10 s).
#   * HOY no hay ningun wake source utilizable en mainline:
#       - PON/pwrkey: &pon_pwrkey esta "okay" en xiaomi-uke.dts PERO el PMK8550 lo descarta
#         el parche X9PMIC-skip (drivers/mfd/qcom-spmi-pmic.c) -> pmk8550-pon no bindea.
#       - gpio-keys (volumen) y xiaomi_hall (lid/table, GPIO 99/100): existen en el DT vendor,
#         NO en el DT mainline.
#       - táctil novatek: el driver no arma enable_irq_wake.
#       - dwc3/ssusb: solo si el DT trae "wakeup-source" (no lo trae) -> sin sysfs wakeup.
#       - RTC PMK8550: tambien en el nodo descartado -> no hay rtcwake.
#     => este script, por defecto, dictamina NO SEGURO y NO suspende. Es a proposito.
#
# USO
#   suspend-prueba.sh                 # chequeo (dry-run). Exit 0 si hay wake source, 1 si no.
#   suspend-prueba.sh --arm <ruta>    # intenta armar un wakeup concreto (escribe "enabled")
#   suspend-prueba.sh --run --si-seguro   # SUSPENDE de verdad (freeze). Mata el SSH.
#   suspend-prueba.sh --post          # tras despertar: lee el log y el dmesg de PM
#
# El log de la prueba vive en la TABLET: /var/log/uke-suspend.log
# Este script se puede copiar a la tablet y correr alli (recomendado, via SSH).

set -u

LOG=${UKE_SUSPEND_LOG:-/var/log/uke-suspend.log}
si_seguro=0
accion=check
arm_path=""

while (($#)); do
  case "$1" in
    --run)       accion=run ;;
    --si-seguro) si_seguro=1 ;;
    --post)      accion=post ;;
    --arm)       arm_path=${2:-}; shift ;;
    -h|--help)   sed -n '2,34p' "$0"; exit 0 ;;
    *) echo "uso: $0 [--run --si-seguro] [--arm RUTA] [--post]" >&2; exit 2 ;;
  esac
  shift
done

say()  { printf '%s\n' "$*"; }
log()  { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }

# ---------- recogida ----------
leer() { [[ -r $1 ]] && cat "$1" 2>/dev/null || printf 'n/d'; }

wakeups_armados() { # lista de ficheros .../power/wakeup con "enabled"
  local f n=0
  while IFS= read -r f; do
    if [[ $(cat "$f" 2>/dev/null) == enabled ]]; then
      printf '  %s\n' "$f"
      n=$((n+1))
    fi
  done < <(find /sys/devices -maxdepth 12 -name wakeup -type f 2>/dev/null)
  return $(( n == 0 ? 1 : 0 ))
}

informe() {
  say "== ENERGIA =="
  if [[ -x /usr/local/bin/bateria.sh ]]; then /usr/local/bin/bateria.sh || true
  else bateria_directa; fi

  say ""
  say "== SUSPEND =="
  say "  /sys/power/state      : $(leer /sys/power/state)"
  say "  /sys/power/mem_sleep  : $(leer /sys/power/mem_sleep)"
  say "  cpuidle driver        : $(leer /sys/devices/system/cpu/cpuidle/current_driver)"
  say "  cpuidle governor      : $(leer /sys/devices/system/cpu/cpuidle/current_governor_ro)"
  say "  PSCI / cpuidle PSCI   : $(dmesg 2>/dev/null | grep -c 'CPUidle PSCI') linea(s) en dmesg"

  say ""
  say "== WAKE SOURCES ARMADOS =="
  if wakeups_armados; then :; else say "  (NINGUNO)"; fi

  say ""
  say "== TERMAL (max) =="
  local tz max=0 t
  for tz in /sys/class/thermal/thermal_zone*; do
    [[ -r $tz/temp ]] || continue
    t=$(cat "$tz/temp" 2>/dev/null); [[ $t =~ ^-?[0-9]+$ ]] || continue
    (( t > max )) && max=$t
    printf '  %-24s %s.%s C (%s)\n' "$(basename "$tz")" $((t/1000)) $(( (t<0?-t:t)%10 )) "$(leer "$tz/type")"
  done
  (( max == 0 )) && say "  (sin thermal_zone legibles: comprobar que tsens bindeo)"
}

bateria_directa() { # mini-lectura si no esta bateria.sh
  local b=/sys/class/power_supply/qcom-battmgr-bat
  if [[ -d $b ]]; then
    printf '  %s: %s%% %s %s\n' "$(basename "$b")" "$(leer "$b/capacity")" \
      "$(leer "$b/voltage_now") uV" "$(leer "$b/status")"
  else
    printf '  sin qcom-battmgr-bat: cadena ADSP caida\n'
  fi
}

veredicto() {
  local n=0
  while IFS= read -r f; do
    [[ $(cat "$f" 2>/dev/null) == enabled ]] && n=$((n+1))
  done < <(find /sys/devices -maxdepth 12 -name wakeup -type f 2>/dev/null)

  say ""
  if (( n == 0 )); then
    say "VEREDICTO: NO SEGURO. 0 wake sources armados."
    say "  s2idle no tiene condicion de salida (pm_wakeup_pending nunca sera true) y no hay RTC."
    say "  Recuperacion si suspendieras: long-press PON (~8-10 s) = reset duro (se pierde el estado)."
    say "  Vias para habilitarlo (fuera del alcance de esta fase, son DT/kernel):"
    say "    1) PMK8550 PON: quitar el X9PMIC-skip del pmk8550 (requiere arreglar el freeze SPMI)."
    say "    2) gpio-keys volumen y/o xiaomi_hall en el DT mainline + wakeup-source."
    say "    3) 'wakeup-source' en el nodo usb_1_dwc3 (dwc3-qcom lo lee: drivers/usb/dwc3/dwc3-qcom.c:862)."
    return 1
  fi
  say "VEREDICTO: hay $n wake source(s) armado(s). Revisa QUE son antes de fiarte."
  say "  Si alguno es el PON o el USB del PC, la prueba es razonable. Si es un IRQ ruidoso,"
  say "  la tablet despertara sola y mediras un consumo que no es el de reposo."
  return 0
}

# ---------- modos ----------
case "$accion" in
  post)
    say "== ULTIMA PRUEBA (log $LOG) =="
    [[ -r $LOG ]] && tail -40 "$LOG" || say "  (sin log)"
    say ""
    say "== dmesg PM =="
    dmesg 2>/dev/null | grep -iE 'PM: suspend|PM: resume|suspend entry|suspend exit|Freezing|s2idle' | tail -20
    say ""
    say "== uptime / marca =="
    cat /proc/uptime
    say "  Si el reloj de pared avanzo mas que uptime, hubo tiempo dormido (compara con date)."
    exit 0
    ;;
esac

if [[ -n $arm_path ]]; then
  if [[ -w $arm_path ]]; then
    echo enabled > "$arm_path" && log "armado wakeup: $arm_path -> $(cat "$arm_path")"
  else
    log "NO puedo escribir $arm_path (¿no existe el atributo power/wakeup? ver contexto)"
  fi
fi

informe
veredicto; v=$?

if [[ $accion == check ]]; then
  exit $v
fi

# --run
if (( ! si_seguro )); then
  say ""
  say "ABORTADO: --run exige --si-seguro (y un wake source verificado)."
  exit 1
fi
if (( v != 0 )); then
  say ""
  say "ABORTADO: el veredicto es NO SEGURO; no se suspende."
  exit 1
fi

log "=== INICIO prueba de suspend (freeze) ==="
informe >> "$LOG" 2>&1
sync
log "escribiendo freeze en /sys/power/state; el SSH se cortara ahora"
if ! echo freeze > /sys/power/state; then
  log "ERROR: no se pudo escribir freeze (¿state vacio? ¿mem_sleep sin s2idle?)"
  exit 4
fi
# al volver (si hay wake source), seguimos aqui:
log "=== RESUME: volvio del suspend ==="
informe >> "$LOG" 2>&1
log "=== FIN prueba ==="
exit 0
