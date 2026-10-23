#!/bin/sh
# Sesion de prueba del modo lapiz INTEGRADO (autorizada por el dueno 19-oct; corregida tras la revision del 20-oct): sustituye
# temporalmente uke-touch.service por la copia parcheada (uke-touchd-pen.py --pen) durante ${1:-600} s, con el cliente BLE y un
# monitor de eventos. El tactil con dedos sigue funcionando (el demonio parcheado hace lo mismo que el original).
# GARANTIA: el servicio original vuelve (a) en cuanto sale el demonio parcheado (plazo por reloj de pared, fallo o senal), (b) por el vigia,
# que se cancela al restaurar. Sin `wait` sobre el vigia (antes dejaba 60 s sin tactil).
# Variables: VERBOSE=1 (una linea por frame con dedo), ASSUME_DETACHED=1 (por defecto: arrancar como despegado hasta el 1.er 53 01 xx).
SEC=${1:-600}
L=/root/lapiz-session/$(date +%Y%m%d-%H%M%S)
mkdir -p $L
ln -sfn $L /root/lapiz-session/ultima
WPID=""
restore() {
  [ -n "$WPID" ] && kill $WPID 2>/dev/null
  [ -n "$NPID" ] && kill $NPID 2>/dev/null; pkill -f "tail -F -n0 $L/touchd-pen.log" 2>/dev/null
  pkill -f uke-touchd-pen.py 2>/dev/null; pkill -f uke_lapiz_ble.py 2>/dev/null; pkill -f lapiz-evmon.py 2>/dev/null
  sleep 1
  systemctl start uke-touch
  echo "$(date +%T) restaurado uke-touch.service: $(systemctl is-active uke-touch)" >> $L/session.log
}
trap restore EXIT INT TERM HUP QUIT
echo "$(date +%T) inicio (${SEC}s)" > $L/session.log
# PLAZO POR RELOJ DE PARED: `timeout`/`sleep` no avanzan durante la suspension de la tablet (20-oct: la sesion siguio viva horas despues
# y coexistio con el demonio original, que cayo al sondeo sin IRQ). El vigia mira `date +%s` y termina la sesion al vencer el plazo.
DEADLINE=$(( $(date +%s) + SEC ))
BAT=/sys/class/power_supply/qcom-battmgr-bat
( n=0
  while [ $(date +%s) -lt $DEADLINE ]; do
    sleep 3; n=$((n+1))
    # proteccion: con la bateria <=3 % y sin cargar se termina la sesion (UPower apagaria la tablet)
    cap=$(cat $BAT/capacity 2>/dev/null || echo 100); st=$(cat $BAT/status 2>/dev/null)
    if [ "$cap" -le 3 ] && [ "$st" != "Charging" ]; then echo "$(date +%T) bateria ${cap}% sin cargar: fin de sesion" >> $L/session.log; break; fi
    # registro cada 30 s (solo lectura): bateria, corriente y CPU del demonio parcheado
    if [ $((n % 10)) -eq 0 ]; then echo "$(date +%T) bat=${cap}% $st I=$(cat $BAT/current_now)uA cpu_touchd_pen=$(ps -o pcpu= -p $(pgrep -f uke-touchd-pen.py | head -1) 2>/dev/null)" >> $L/bateria.log; fi
  done
  pkill -TERM -f uke-touchd-pen.py; pkill -TERM -f uke_lapiz_ble.py; pkill -TERM -f lapiz-evmon.py
  sleep 5; systemctl start uke-touch ) & WPID=$!
systemctl stop uke-touch
sleep 1
ls /dev/spidev0.0 >> $L/session.log 2>&1
cd /usr/local/share/uke/tactil
VF=""; [ -n "$VERBOSE" ] && VF="--verbose"
LAPIZ_STACKS=$L/pilas python3 -u uke-touchd-pen.py --pen $VF > $L/touchd-pen.log 2>&1 & TPID=$!
sleep 3
if ! kill -0 $TPID 2>/dev/null; then echo "$(date +%T) el demonio parcheado NO arranco: $(tail -3 $L/touchd-pen.log)" >> $L/session.log; exit 1; fi
cd /usr/local/share/uke/lapiz
LAPIZ_STACKS=$L/pilas LAPIZ_DEBUG=1 LAPIZ_ASSUME_DETACHED=${ASSUME_DETACHED:-1} python3 -u uke_lapiz_ble.py > $L/ble.log 2>&1 &
( sleep 8; python3 -I /root/lapiz-evmon.py 86400 $L/evmon.log > $L/evmon.out 2>&1 ) &   # lo termina el vigia
# aviso visual (mejor esfuerzo): cuando el chip queda en modo lapiz, cartel en pantalla con hyprctl notify (el usuario omarchy)
NPID=""
( SIG=$(ls /run/user/1001/hypr 2>/dev/null | head -1)
  tail -F -n0 $L/touchd-pen.log 2>/dev/null | while read -r line; do
    case "$line" in
      *"activar modo lapiz del chip -> ok"*) MSG="LAPIZ LISTO: despegalo y usalo ahora";;
      *"DESACTIVADO"*) MSG="LAPIZ: error, desactivado (el tactil sigue)";;
      *) continue;;
    esac
    runuser -u omarchy -- env XDG_RUNTIME_DIR=/run/user/1001 HYPRLAND_INSTANCE_SIGNATURE=$SIG hyprctl notify 1 8000 "rgb(30c030)" "$MSG" >/dev/null 2>&1
  done ) & NPID=$!
wait $TPID
echo "$(date +%T) el demonio parcheado salio rc=$?" >> $L/session.log
