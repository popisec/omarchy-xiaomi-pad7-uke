# lib.sh — comun a los scripts de medida (se hace `source`). 22-oct-2026. SOLO PC; nada se escribe aqui en la tablet.
# UKE_SSH sustituye al ssh real (pruebas en seco: selftest.sh). SYSFS = prefijo de /sys para las pruebas.
R=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}; HOST=${UKE_HOST:-root@uke}
S() { if [ -n "${UKE_SSH:-}" ]; then "$UKE_SSH" "$@"; else timeout "${T:-60}" ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 "$HOST" "$@"; fi; }
SYS=${SYSFS:-}/sys/class/power_supply
BAT=$SYS/qcom-battmgr-bat; USB=$SYS/qcom-battmgr-usb
die() { echo "ABORTADO: $*" >&2; exit "${2:-2}"; }
bat_status() { S "cat $BAT/status" 2>/dev/null; }
bat_cap() { S "cat $BAT/capacity" 2>/dev/null; }
# gate_bateria MIN_PCT ESTADO(Discharging|Charging|any)
gate_bateria() {
  local st cap; st=$(bat_status) || die "tablet inalcanzable (ssh $HOST)"; cap=$(bat_cap)
  [ -n "$cap" ] || die "sin capacity"
  [ "$cap" -ge "$1" ] || die "bateria $cap % < $1 %"
  [ "$2" = any ] || [ "$st" = "$2" ] || die "estado '$st', se esperaba '$2' (¿desenchufada/enchufada?)"
  echo "gate bateria OK: $st $cap %"
}
# gate_turno: nadie mas debe estar usando la tablet (semaforo entre sesiones: lo confirma quien lanza el script con UKE_TURNO=1)
gate_turno() { [ "${UKE_TURNO:-0}" = 1 ] || die "sin turno de tablet: pide «pido tablet» y relanza con UKE_TURNO=1"; }
