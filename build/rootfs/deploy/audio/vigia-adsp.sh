#!/bin/bash
# Vigia de solo lectura del ADSP (plan AUDIO-SENEMOS §5). Se ejecuta EN la tablet, desprendido:
#   setsid nohup /root/vigia-adsp.sh >/dev/null 2>&1 &      ; parar: kill $(cat /run/vigia-adsp.pid)
# Log: /root/vigia-adsp.log (cada 2 s una linea de estado; las alarmas empiezan por "ALARMA"); el dmesg filtrado va a /root/vigia-adsp-dmesg.log.
# No escribe en sysfs ni toca modulos. Alarmas: remoteproc1 != running, recovery != disabled, battmgr deja de leerse o no esta Charging
# (con cargador), voltage_now congelado 20 s, wpss != running, wlan0 != up, y patrones de fallo en dmesg.
R=/sys/class/remoteproc/remoteproc1; B=/sys/class/power_supply/qcom-battmgr-bat
echo $$ > /run/vigia-adsp.pid; LOG=/root/vigia-adsp.log; DL=/root/vigia-adsp-dmesg.log
PAT='crash detected|fatal error|watchdog|q6v5|Unhandled context fault|arm-smmu|PDR:|gpr|unknown message|apr|q6apm|q6prm|uke_audio|soundwire|Oops|Internal error|BUG:'
dmesg -w --time-format iso 2>/dev/null | grep --line-buffered -E -i "$PAT" >> "$DL" &
last=; lastchg=$(date +%s); prevV=
while sleep 2; do
  st=$(cat $R/state 2>&1); rec=$(cat $R/recovery 2>&1); bs=$(cat $B/status 2>&1); v=$(cat $B/voltage_now 2>&1)
  wp=$(cat /sys/class/remoteproc/remoteproc0/state 2>&1); wl=$(cat /sys/class/net/wlan0/operstate 2>&1)
  now=$(date +%s); [ "$v" != "$prevV" ] && { prevV=$v; lastchg=$now; }
  a=""
  [ "$st" = running ] || a="$a adsp=$st"; [ "$rec" = disabled ] || a="$a recovery=$rec"
  [ "$bs" = Charging ] || a="$a battmgr=$bs"; [ $((now-lastchg)) -gt 20 ] && a="$a Vcongelado"
  [ "$wp" = running ] || a="$a wpss=$wp"; [ "$wl" = up ] || a="$a wlan0=$wl"
  line="$(date +%T) adsp=$st bat=$bs v=$v wlan=$wl"; [ -n "$a" ] && line="ALARMA[$a ] $line"
  s="${a:+A}$st$bs$wl"; [ "$s" != "$last" ] || [ -n "$a" ] && echo "$line" >> $LOG; last=$s
  [ $((now % 60)) -lt 2 ] && echo "$line" >> $LOG
done
