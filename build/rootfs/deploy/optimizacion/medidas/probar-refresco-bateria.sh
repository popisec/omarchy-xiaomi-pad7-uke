#!/bin/bash
# probar-refresco-bateria.sh check|run [segundos=120]|revert — SE EJECUTA EN EL PC. Prueba de uke-refresco en bateria real (pendiente B1).
# El DUEÑO desenchufa y vuelve a enchufar durante la ventana; el script sondea (solo lectura, cada 2 s) estado del cargador y refresco del panel
# y comprueba: tras cada TRANSICION de cargador: desenchufar -> 60 Hz, enchufar -> 120 Hz, con la latencia de cada cambio (sin transicion no hay PASA). No cambia nada por si mismo (lo hace la regla udev).
# revert: `uke-refresco auto` fija el refresco que toca por el estado actual del cargador (unico cambio posible, reversible).
set -u; . "$(dirname "$0")/lib.sh"
hz() { S 'runuser -u omarchy -- env XDG_RUNTIME_DIR=/run/user/1001 HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1001/hypr|head -1) hyprctl monitors -j | jq -r ".[0].refreshRate|floor"' 2>/dev/null; }
case "${1:-}" in
check) bash -n "$0" && echo "CHECK OK";;
run) gate_turno; T=${2:-120}; ok_b=0; ok_c=0; prev_o=""; prev=""; tr_t=""; tr_o=""; t0=$(date +%s); echo "ventana ${T}s: desenchufa y luego enchufa la tablet (con 20+ s entre cada paso). Solo cuentan TRANSICIONES vistas durante la ventana."
  while [ $(( $(date +%s) - t0 )) -lt "$T" ]; do
    o=$(S "cat $USB/online" 2>/dev/null); f=$(hz); t=$(( $(date +%s) - t0 )); cur="online=$o hz=$f"
    [ "$cur" != "$prev" ] && echo "t=${t}s $cur" && prev="$cur"
    if [ -n "$prev_o" ] && [ "$o" != "$prev_o" ]; then tr_t=$t; tr_o=$o; fi        # transicion de cargador observada
    if [ -n "$tr_t" ]; then
      if [ "$tr_o" = 0 ] && [ "$f" = 60 ]; then ok_b=1; echo "  -> sin cargador: 60 Hz, latencia $((t - tr_t)) s"; tr_t=""; fi
      if [ "$tr_o" = 1 ] && [ "$f" = 120 ]; then ok_c=1; echo "  -> con cargador: 120 Hz, latencia $((t - tr_t)) s"; tr_t=""; fi
    fi
    prev_o=$o; sleep 2
  done
  [ $ok_b = 1 ] && echo "PASA bateria: tras desenchufar -> 60 Hz" || echo "NO VISTO bateria: no se observo desenchufar + 60 Hz"
  [ $ok_c = 1 ] && echo "PASA cargador: tras enchufar -> 120 Hz" || echo "NO VISTO cargador: no se observo enchufar + 120 Hz";;
revert) S "/usr/local/bin/uke-refresco auto";;
*) echo "uso: $0 check|run [segundos]|revert"; exit 2;;
esac
