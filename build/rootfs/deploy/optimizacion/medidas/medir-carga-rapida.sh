#!/bin/bash
# medir-carga-rapida.sh check|run [segundos=180] — SE EJECUTA EN EL PC. Envuelve bateria/carga-rapida/medir-linux-carga-rapida.sh con gates (pendiente B3/B4). SOLO LECTURA.
# Gates: turno, bateria <80 % (a >90 % la corriente cae por fin de carga), cargador conectado (usb online=1) y SIN cable al PC (la tablet alcanzable por Tailscale/WiFi).
# Revert: nada que revertir (no escribe en la tablet). Salida: build/logs/carga-rapida-linux-<fecha>.csv
set -u; . "$(dirname "$0")/lib.sh"
case "${1:-}" in
check) bash -n "$0" && bash -n "$R/build/rootfs/deploy/bateria/carga-rapida/medir-linux-carga-rapida.sh" && echo "CHECK OK";;
run) gate_turno; gate_bateria 0 Charging; cap=$(bat_cap); [ "$cap" -lt 80 ] || die "bateria $cap % >= 80 %: la carga rapida ya decae (descarga antes)"
  [ "$(S "cat $USB/online")" = 1 ] || die "usb online != 1"
  [ "$HOST" != root@192.168.42.129 ] || die "medir por Tailscale, no por el USB del PC (el cable del PC limita a 500 mA)"
  echo "usb_type: $(S "cat $USB/usb_type")  ICL: $(S "cat $USB/input_current_limit")"
  bash "$R/build/rootfs/deploy/bateria/carga-rapida/medir-linux-carga-rapida.sh" "${2:-180}";;
*) echo "uso: $0 check|run [segundos]"; exit 2;;
esac
