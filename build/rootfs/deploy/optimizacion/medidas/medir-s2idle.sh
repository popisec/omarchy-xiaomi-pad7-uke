#!/bin/bash
# medir-s2idle.sh check|arm [segundos]|status|report|revert — SE EJECUTA EN EL PC. Drenaje de s2idle SIN cable (pendiente B3 de bateria).
# arm  : gates (turno, Discharging >=30 %, s2idle, gancho uke-bt-sleep) + copia tablet/uke-s2idle-run.sh a /root y lo lanza DESACOPLADO
#        (systemd-run --unit=uke-s2idle-run): la tablet se suspende a los pocos segundos y la sesion SSH se pierde (esperado); la RTC la despierta.
#        ANTES hay que desenchufar a mano (dueño). Con `uke-idle-guard` la suspension explicita sigue funcionando (solo bloquea la de reposo).
# report: lee /var/log/uke-bateria/s2idle-medidas.csv (solo lectura). status: estado de la unidad. revert: para la unidad, desarma la alarma RTC, borra el runner.
# Efectos secundarios: crea /root/uke-s2idle-run.sh y /var/log/uke-bateria/s2idle-medidas.csv. Reanudar es la ruta ya probada del gancho uke-bt-sleep.
set -u; . "$(dirname "$0")/lib.sh"
RUN=${UKE_RUN:-/root/uke-s2idle-run.sh}; UNIT=uke-s2idle-run; N=${2:-1800}; CSV=${UKE_S2CSV:-/var/log/uke-bateria/s2idle-medidas.csv}
case "${1:-}" in
check) bash -n "$0" && bash -n "$(dirname "$0")/tablet/uke-s2idle-run.sh" && echo "CHECK OK (sintaxis)";;
arm) gate_turno; gate_bateria 30 Discharging
  [ "$N" -ge 300 ] && [ "$N" -le 7200 ] || die "segundos fuera de 300..7200"
  S "cat ${SYSFS:-}/sys/power/mem_sleep" | grep -q '\[s2idle\]' || die "mem_sleep no es s2idle (no se prueba deep)"
  S "test -x ${UKE_HOOK:-/usr/lib/systemd/system-sleep/uke-bt-sleep}" || die "gancho uke-bt-sleep no instalado (el BT cargado impide dormir; bt/deploy.sh --sleep)"
  cat "$(dirname "$0")/tablet/uke-s2idle-run.sh" | S "cat > $RUN && chmod 755 $RUN" || die "no se pudo copiar el runner"
  S "systemd-run --unit=$UNIT --collect $RUN $N" && echo "armado: la tablet se suspende en segundos; despierta por RTC a los $N s. Esperar y: $0 report";;
status) S "systemctl is-active $UNIT 2>&1; systemctl status $UNIT --no-pager 2>&1 | head -8; tail -3 $CSV 2>/dev/null";;
report) S "cat $CSV" | python3 -c "
import csv,sys
r=list(csv.DictReader(sys.stdin))
if not r: sys.exit('sin medidas')
for x in r[-5:]: print(x['ts'],x['dormido_s']+' s',x['pct_antes']+'->'+x['pct_despues']+' %',x['uAh_h']+' uAh/h',x['estado'],'wake_irq',x['wakeup_irq'])
m=[float(x['uAh_h']) for x in r if float(x['dormido_s'])>=${UKE_S2MIN:-300}]
if m: print('media s2idle: %.0f uAh/h (~%.0f mW a 4,2 V). Referencia: suelo con pantalla apagada ~0,93 W despierta.'%(sum(m)/len(m),sum(m)/len(m)*4.2/1000))
"
  S "f=\$(ls -t ${CSV%.csv}-*-despertar.txt 2>/dev/null | head -1); [ -n \"\$f\" ] && { echo \"--- \$f\"; cat \"\$f\"; }";;
revert) S "systemctl stop $UNIT 2>/dev/null; rtcwake -m disable 2>&1 | tail -1; rm -f $RUN; echo \"revertido (el CSV de medidas se conserva)\"";;
*) echo "uso: $0 check|arm [segundos 300-7200]|status|report|revert"; exit 2;;
esac
