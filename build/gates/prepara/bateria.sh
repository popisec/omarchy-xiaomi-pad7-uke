#!/usr/bin/env bash
# bateria.sh — estado legible de la ENERGIA de la Xiaomi Pad 7 "uke" (Arch aarch64)
#
# QUE HACE
#   Lee /sys/class/power_supply/* (kernel mainline: qcom_battmgr -> pmic_glink -> ADSP
#   charger_pd) y lo imprime en unidades humanas. NO necesita upower ni python.
#   Sirve de manometro local para decidir si se puede flashear sin ir a fastboot.
#
# PRERREQUISITO (importante)
#   Los nodos qcom-battmgr-* SOLO existen si la cadena del ADSP esta arriba:
#   firmware adsp.mdt en /lib/firmware + modulos + "echo start" al remoteproc.
#   Eso lo hace uke-adsp-load.sh / uke-adsp.service. Si no esta, este script lo dice
#   con exit 3 (NO inventa un 100 %: esa trampa ya la pago el proyecto hermano con
#   `|| echo 100` y un vigilante que nunca apagaba).
#
# USO
#   bateria.sh                 estado completo
#   bateria.sh --json          salida JSON de una linea (para scripts)
#   bateria.sh --watch [N]     refresca cada N s (def 5) hasta Ctrl-C
#   bateria.sh --umbral 3700   exit 0 si voltage_now >= 3700 mV (gate pre-flash)
#
# EXIT
#   0  ok (con --umbral: umbral cumplido)
#   1  error de uso
#   2  con --umbral: umbral NO cumplido
#   3  no hay bateria visible (cadena ADSP caida)
#   4  nodo presente pero ilegible
#
# NO escribe NADA fuera de stdout. Seguro para correr en bucle.

set -u

BAT_PREF=/sys/class/power_supply/qcom-battmgr-bat
PS=/sys/class/power_supply

modo=estado
watch_s=5
umbral_mv=""

while (($#)); do
  case "$1" in
    --json)    modo=json ;;
    --watch)   modo=watch; if [[ ${2:-} =~ ^[0-9]+$ ]]; then watch_s=$2; shift; fi ;;
    --umbral)  umbral_mv=${2:-}; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "uso: $0 [--json|--watch [N]|--umbral mV]" >&2; exit 1 ;;
  esac
  shift
done

# ---------- utilidades ----------
rd() { # rd <fichero> -> contenido o vacio; exit!=0 si no legible
  [[ -r $1 ]] || return 1
  local v
  v=$(cat "$1" 2>/dev/null) || return 1
  printf '%s' "$v"
}

uv_a_v() { # microvoltios -> "3.954 V"
  local uv=${1:-}
  [[ $uv =~ ^-?[0-9]+$ ]] || { printf 'n/d'; return; }
  local neg=""; (( uv < 0 )) && { neg="-"; uv=$((-uv)); }
  printf '%s%d.%03d V' "$neg" $((uv/1000000)) $(((uv%1000000)/1000))
}

ua_a_a() { # microamperios -> "0.531 A" o "531 mA"
  local ua=${1:-}
  [[ $ua =~ ^-?[0-9]+$ ]] || { printf 'n/d'; return; }
  local neg=""; (( ua < 0 )) && { neg="-"; ua=$((-ua)); }
  if (( ua >= 1000000 )); then
    printf '%s%d.%03d A' "$neg" $((ua/1000000)) $(((ua%1000000)/1000))
  else
    printf '%s%d mA' "$neg" $((ua/1000))
  fi
}

uw_a_w() {
  local uw=${1:-}
  [[ $uw =~ ^-?[0-9]+$ ]] || { printf 'n/d'; return; }
  printf '%d.%03d W' $((uw/1000000)) $(((uw%1000000)/1000))
}

dt_a_c() {
  local dt=${1:-}
  [[ $dt =~ ^-?[0-9]+$ ]] || { printf 'n/d'; return; }
  printf '%d.%d C' $((dt/10)) $(( (dt<0 ? -dt : dt) %10 ))
}

# busca la bateria: preferimos qcom-battmgr-bat; si no, cualquier type=Battery
enc_bat() {
  if [[ -d $BAT_PREF ]]; then printf '%s' "$BAT_PREF"; return 0; fi
  local d t
  for d in "$PS"/*; do
    [[ -d $d ]] || continue
    t=$(rd "$d/type") || continue
    [[ $t == Battery ]] && { printf '%s' "$d"; return 0; }
  done
  return 1
}

# ---------- recogida ----------
bat=$(enc_bat) || {
  if [[ $modo == json ]]; then
    printf '{"presente":false,"cadena_adsp":"caida"}\n'
  else
    printf 'BATERIA: no visible en %s\n' "$PS"
    printf '  cadena ADSP caida o incompleta. No hay voltage_now/capacity.\n'
    printf '  Cargala con: sudo uke-adsp-load.sh   (o: systemctl start uke-adsp.service)\n'
    printf '  Sin datos NO se asume nada: el gate de tension no es evaluable.\n'
  fi
  exit 3
}

present=$(rd "$bat/present" || true)
status=$(rd "$bat/status" || true)
cap=$(rd "$bat/capacity" || true)
vnow=$(rd "$bat/voltage_now" || true)
inow=$(rd "$bat/current_now" || true)
pnow=$(rd "$bat/power_now" || true)
temp=$(rd "$bat/temp" || true)
salud=$(rd "$bat/health" || true)
soh=$(rd "$bat/state_of_health" || true)   # no siempre existe
cyc=$(rd "$bat/cycle_count" || true)
cnow=$(rd "$bat/charge_now" || true)
cfull=$(rd "$bat/charge_full" || true)
cdes=$(rd "$bat/charge_full_design" || true)
model=$(rd "$bat/model_name" || true)

# fiabilidad: el fuel gauge Xiaomi tarda en estabilizar; capacity=0 con V alta es sintoma
fiab="ok"
avisos=()
if [[ $cap == 0 && $vnow =~ ^[0-9]+$ ]] && (( vnow > 3500000 )); then
  fiab="dudosa"; avisos+=("capacity=0 con V alta (fuel gauge sin estabilizar)")
fi
if [[ -n ${vnow:-} && $vnow =~ ^[0-9]+$ ]] && (( vnow < 2500000 )); then
  fiab="dudosa"; avisos+=("voltage_now=${vnow} uV es fisicamente absurdo para Li-ion")
fi
if [[ -z $vnow ]]; then fiab="sin voltage_now"; fi

# ---------- salida ----------
if [[ $modo == json ]]; then
  printf '{"presente":%s,"status":"%s","capacity":%s,"voltage_uV":%s,"current_uA":%s,"power_uW":%s,"temp_dC":%s,"health":"%s","fiabilidad":"%s","nodo":"%s"}\n' \
    "${present:-?}" "${status:-?}" "${cap:-null}" "${vnow:-null}" "${inow:-null}" "${pnow:-null}" "${temp:-null}" "${salud:-?}" "$fiab" "$bat"
else
  printf 'Nodo        : %s\n' "$bat"
  printf 'Presente    : %s\n' "${present:-n/d}"
  printf 'Estado      : %s\n' "${status:-n/d}"
  printf 'Carga       : %s %%\n' "${cap:-n/d}"
  printf 'Voltaje     : %s\n' "$(uv_a_v "${vnow:-}")"
  printf 'Corriente   : %s\n' "$(ua_a_a "${inow:-}")"
  printf 'Potencia    : %s\n' "$(uw_a_w "${pnow:-}")"
  printf 'Temperatura : %s\n' "$(dt_a_c "${temp:-}")"
  printf 'Salud       : %s%s\n' "${salud:-n/d}" "${soh:+ (soh=${soh}%)}"
  [[ -n $cyc ]]   && printf 'Ciclos      : %s\n' "$cyc"
  [[ -n $cnow ]]  && printf 'Carga now   : %s uAh\n' "$cnow"
  [[ -n $cfull ]] && printf 'Carga full  : %s uAh%s\n' "$cfull" "${cdes:+ (diseno $cdes uAh)}"
  [[ -n $model ]] && printf 'Modelo      : %s\n' "$model"
  printf 'Fiabilidad  : %s\n' "$fiab"
  for a in ${avisos[@]+"${avisos[@]}"}; do printf '  AVISO: %s\n' "$a"; done

  # resto de supplies (cargador)
  for d in "$PS"/*; do
    [[ -d $d && $d != "$bat" ]] || continue
    t=$(rd "$d/type" || true); o=$(rd "$d/online" || true)
    [[ -n $o ]] || continue
    printf 'Supply      : %s type=%s online=%s' "$(basename "$d")" "${t:-?}" "$o"
    [[ -r $d/usb_type ]]    && printf ' usb_type=%s' "$(rd "$d/usb_type")"
    [[ -r $d/voltage_now ]] && printf ' V=%s' "$(uv_a_v "$(rd "$d/voltage_now")")"
    [[ -r $d/input_current_limit ]] && printf ' ilimit=%s' "$(ua_a_a "$(rd "$d/input_current_limit")")"
    printf '\n'
  done

  printf 'REGLA       : para saber si CARGA no mires current_now (convencion ambigua);\n'
  printf '              mira voltage_now subiendo de forma sostenida.\n'
fi

# ---------- gate opcional ----------
if [[ -n $umbral_mv ]]; then
  if [[ ! $vnow =~ ^[0-9]+$ ]]; then
    printf 'GATE: voltage_now ilegible -> NO evaluable\n' >&2; exit 4
  fi
  vmv=$((vnow/1000))
  if (( vmv >= umbral_mv )); then
    printf 'GATE: %d mV >= %d mV -> PASA\n' "$vmv" "$umbral_mv"; exit 0
  else
    printf 'GATE: %d mV < %d mV -> NO PASA (no flashear)\n' "$vmv" "$umbral_mv" >&2; exit 2
  fi
fi

# ---------- bucle ----------
if [[ $modo == watch ]]; then
  while :; do
    printf '\n[%s] cap=%s%% %s %s\n' "$(date +%H:%M:%S)" "${cap:-?}" "$(uv_a_v "${vnow:-}")" "${status:-?}"
    vprev=$vnow
    sleep "$watch_s"
    vnow=$(rd "$bat/voltage_now" || true)
    cap=$(rd "$bat/capacity" || true)
    status=$(rd "$bat/status" || true)
    if [[ $vprev =~ ^[0-9]+$ && $vnow =~ ^[0-9]+$ ]]; then
      printf '            dV=%d mV en %ss\n' $(( (vnow-vprev)/1000 )) "$watch_s"
    fi
  done
fi

exit 0
