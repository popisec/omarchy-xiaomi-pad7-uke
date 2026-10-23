#!/bin/bash
# uke-pmtest.sh — prueba de suspension por etapas en la uke (18-oct-2026). Se lanza DESACOPLADO (systemd-run): el SSH
# y la consola USB caen durante el intento. Log con sync en /var/log/uke-pmtest.log (+ dmesg del intento).
# Uso: uke-pmtest.sh freezer|devices|s2idle [segundos]   (s2idle = rtcwake -m freeze -s N, despertar por alarma RTC)
set -u
L=/var/log/uke-pmtest.log
M=${1:?freezer|devices|s2idle}; N=${2:-20}
log() { echo "[$(date +%T.%N | cut -c1-12)] $*" >> $L; sync; }
echo 1 > /sys/power/pm_print_times; echo 1 > /sys/power/pm_debug_messages
dmesg -n 7
S0=$(cat /sys/power/suspend_stats/success) F0=$(cat /sys/power/suspend_stats/fail)
log "=== $M (N=$N) uptime $(cut -d' ' -f1 /proc/uptime) stats ok=$S0 fail=$F0 mem_sleep=$(cat /sys/power/mem_sleep)"
dmesg -c > /dev/null 2>&1 || true
case $M in
freezer|devices)
	echo "$M" > /sys/power/pm_test; log "pm_test=$(cat /sys/power/pm_test) -> echo freeze > state"
	echo freeze > /sys/power/state 2>>$L; rc=$?
	echo none > /sys/power/pm_test ;;
s2idle)
	echo none > /sys/power/pm_test; log "rtcwake -m freeze -s $N"
	rtcwake -m freeze -s "$N" >> $L 2>&1; rc=$? ;;
*) log "modo desconocido"; exit 2 ;;
esac
log "vuelta rc=$rc stats ok=$(cat /sys/power/suspend_stats/success) fail=$(cat /sys/power/suspend_stats/fail) last_failed_dev=$(cat /sys/power/suspend_stats/last_failed_dev 2>/dev/null) wakeup_irq=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)"
dmesg > /var/log/uke-pmtest-$M-dmesg.txt; sync
log "dmesg del intento: /var/log/uke-pmtest-$M-dmesg.txt ($(wc -l < /var/log/uke-pmtest-$M-dmesg.txt) lineas)"
