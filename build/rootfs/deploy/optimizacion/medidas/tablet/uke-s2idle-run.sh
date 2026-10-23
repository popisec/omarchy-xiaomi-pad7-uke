#!/bin/bash
# uke-s2idle-run.sh [segundos=1800] — SE EJECUTA EN LA TABLET (lo lanza medir-s2idle.sh con systemd-run). 22-oct-2026.
# Mide el drenaje de s2idle: lee la bateria, arma la alarma RTC, suspende y, al reanudar, anota Δ de carga y tiempo suspendido.
# Salida: /var/log/uke-bateria/s2idle-medidas.csv  (ts,dormido_s,pct_antes,pct_despues,uah_antes,uah_despues,uAh_h,estado,wakeup_irq)
# Revert: medir-s2idle.sh revert (rtcwake -m disable, borra este fichero). No toca ficheros del sistema ni modules.
SYS=${SYSFS:-}/sys; N=${1:-1800}; B=$SYS/class/power_supply/qcom-battmgr-bat; OUT=${S2IDLE_OUT:-/var/log/uke-bateria/s2idle-medidas.csv}
RTCWAKE=${RTCWAKE:-rtcwake}; SUSPEND=${SUSPEND_CMD:-systemctl suspend}
mkdir -p "$(dirname "$OUT")"
[ -s "$OUT" ] || echo "ts,dormido_s,pct_antes,pct_despues,uah_antes,uah_despues,uAh_h,estado,wakeup_irq" > "$OUT"
st=$(cat $B/status); [ "$st" = Discharging ] || { echo "s2idle-run: estado $st (no Discharging): abortado" >&2; exit 3; }
a_p=$(cat $B/capacity); a_u=$(cat $B/charge_counter); t0=$(date +%s)
# 22-oct: fuentes de despertar. Antes/despues: wakeup_sources (debugfs) y /proc/interrupts; pm_debug_messages=1 durante la suspension para que el
# kernel anote los despertares internos de s2idle. Detalle en $OUT-<ts>-despertar.txt (solo si existe debugfs; nunca impide medir).
WS=$SYS/kernel/debug/wakeup_sources; PMD=$SYS/power/pm_debug_messages; pmd0=$(cat $PMD 2>/dev/null)
cat $WS > /run/uke-s2idle-ws0 2>/dev/null; cat ${SYSFS:-}/proc/interrupts > /run/uke-s2idle-irq0 2>/dev/null; echo 1 > $PMD 2>/dev/null
"$RTCWAKE" -m no -s "$N" || { echo "s2idle-run: rtcwake fallo" >&2; echo "${pmd0:-0}" > $PMD 2>/dev/null; exit 4; }
if ! $SUSPEND; then "$RTCWAKE" -m disable 2>/dev/null; echo "${pmd0:-0}" > $PMD 2>/dev/null; echo "s2idle-run: la suspension fallo (inhibidor?): alarma RTC desarmada, sin fila" >&2; exit 5; fi
t1=$(date +%s); b_p=$(cat $B/capacity); b_u=$(cat $B/charge_counter); irq=$(cat $SYS/power/pm_wakeup_irq 2>/dev/null)
echo "${pmd0:-0}" > $PMD 2>/dev/null
{ echo "# s2idle $t0 -> $t1, wakeup_irq=$irq"; echo "## wakeup_sources con event_count cambiado (nombre antes despues)"
  [ -r /run/uke-s2idle-ws0 ] && cat $WS 2>/dev/null | awk 'NR==FNR{a[$1]=$3;next} FNR>1 && a[$1]!=$3 {print $1, a[$1], $3}' /run/uke-s2idle-ws0 -
  echo "## IRQ con mas cuentas durante la suspension"
  [ -r /run/uke-s2idle-irq0 ] && cat ${SYSFS:-}/proc/interrupts 2>/dev/null | awk 'function s(){t=0;for(i=2;i<=9;i++)if($i~/^[0-9]+$/)t+=$i;return t} NR==FNR{a[$1]=s();next} {d=s()-a[$1]; if(d>0)print d, $0}' /run/uke-s2idle-irq0 - | sort -rn | head -12
  echo "## kernel (PM) durante la suspension"; journalctl -k --since @$t0 --no-pager 2>/dev/null | grep -E "PM:|wakeup|Wakeup" | head -40
} > "${OUT%.csv}-$t1-despertar.txt" 2>/dev/null
dt=$((t1 - t0)); [ "$dt" -gt 0 ] || dt=1
python3 - "$OUT" "$t1" "$dt" "$a_p" "$b_p" "$a_u" "$b_u" "$(cat $B/status)" "${irq:-}" <<'PY'
import sys
out, ts, dt, ap, bp, au, bu, st, irq = sys.argv[1:]
dt, au, bu = float(dt), float(au), float(bu)
rate = (au - bu) / dt * 3600       # uAh/h consumidos (>0 = descarga)
open(out, "a").write("%s,%d,%s,%s,%d,%d,%.0f,%s,%s\n" % (ts, dt, ap, bp, au, bu, rate, st, irq))
print("s2idle: %.0f s dormida, %s%%->%s%%, %.0f uAh/h (~%.0f mW a 4,2 V)" % (dt, ap, bp, rate, rate * 4.2 / 1000))
PY
