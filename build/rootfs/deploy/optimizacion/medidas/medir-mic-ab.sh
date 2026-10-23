#!/bin/bash
# medir-mic-ab.sh check|run [segundos_por_tramo=150]|revert — SE EJECUTA EN EL PC. Coste en bateria del «micro siempre abierto» (audio: 51-uke-mic.conf variante
# pause-on-idle=false/always-process; ADC y bias encendidos). A/B alternado A B A B con la pantalla en DPMS off (como el suelo medido: 0,93 W) y, opcional, un s2idle por estado.
# Usa audio/pipewire/mic-abierta.sh (--check/--go/--revert, solo ficheros) y reinicia pipewire/wireplumber del usuario omarchy tras cada cambio (corta el audio unos segundos).
# Gates: turno, Discharging >=40 %, mic-abierta.sh presente. Estado inicial (base o variante) se RESTAURA siempre (trap), tambien si se aborta.
# Salida: build/logs/mic-ab-<fecha>.csv (estado,tramo,w_medio) + resumen con el delta en W y en %/h. Si ΔW > 0,05 W => proponer al dueño dejar la base.
# s2idle por estado: NO automatico (la sesion SSH se pierde al dormir): medir-s2idle.sh arm 600 a mano en cada estado y comparar los report.
set -u; . "$(dirname "$0")/lib.sh"
MIC=${MICABIERTA:-$R/build/rootfs/deploy/audio/pipewire/mic-abierta.sh}; TR=${2:-150}
pw_restart() { S 'systemctl --user -M omarchy@ restart pipewire.service wireplumber.service pipewire-pulse.service 2>&1 | tail -1; sleep 8; systemctl --user -M omarchy@ is-active pipewire wireplumber | tr "\n" " "'; }
estado() { S "grep -c \"pause-on-idle = false\" ${UKE_MICCONF:-/etc/pipewire/pipewire.conf.d/51-uke-mic.conf}" 2>/dev/null; }
poner() { case "$1" in A) bash "$MIC" --revert >/dev/null 2>&1;; B) bash "$MIC" --go >/dev/null 2>&1;; esac || return 1; pw_restart >/dev/null 2>&1; e=$(estado); { [ "$1" = A ] && [ "${e:-x}" = 0 ]; } || { [ "$1" = B ] && [ "${e:-0}" -ge 1 ] 2>/dev/null; }; }
muestras() { T=$(( $1 + ${MIC_SETTLE:-10} + 60 )) S "end=\$((\$(date +%s)+$1)); H=\"setpriv --reuid=1001 --regid=1001 --init-groups env XDG_RUNTIME_DIR=/run/user/1001 HYPRLAND_INSTANCE_SIGNATURE=\$(ls /run/user/1001/hypr|head -1) hyprctl\"
  \$H dispatch 'hl.dsp.dpms({ action = \"off\" })' >/dev/null 2>&1; sleep ${MIC_SETTLE:-10}
  while [ \$(date +%s) -lt \$end ]; do uke-bateria-lectura --short 2>/dev/null | tr '|' ' ' ; sleep 3; done
  \$H dispatch 'hl.dsp.dpms({ action = \"on\" })' >/dev/null 2>&1"; }
case "${1:-}" in
check) bash -n "$0" && echo "CHECK OK";;
run) gate_turno; gate_bateria 40 Discharging; [ -f "$MIC" ] || die "falta $MIC"
  INI=$(estado); case "${INI:-}" in 0) E0=A;; [1-9]*) E0=B;; *) die "no se pudo leer el estado inicial del micro (ssh?): no se mide a ciegas";; esac; echo "estado inicial: $E0 (se restaura al final)"
  trap 'poner $E0 || echo "*** AVISO: no se pudo restaurar el estado inicial ($E0) del micro: ejecutar $0 revert o mic-abierta.sh --go/--revert ***" >&2; S "setpriv --reuid=1001 --regid=1001 --init-groups env XDG_RUNTIME_DIR=/run/user/1001 HYPRLAND_INSTANCE_SIGNATURE=\$(ls /run/user/1001/hypr|head -1) hyprctl dispatch \"hl.dsp.dpms({ action = \\\"on\\\" })\"" >/dev/null 2>&1' EXIT
  OUT=$R/build/logs/mic-ab-$(date +%Y%m%d-%H%M%S).csv; mkdir -p "$R/build/logs"; echo "estado,tramo,w" > "$OUT"; n=0
  for st in A B A B; do n=$((n+1)); echo "tramo $n: estado $st"; poner $st || die "no se pudo poner el estado $st del micro (se restaura el inicial)"
    muestras "$TR" | awk -v s=$st -v n=$n 'NF>=4 && $4=="Discharging" && $2 ~ /^-?[0-9.]+$/ {print s","n","$2}' >> "$OUT"
    gate_bateria 25 Discharging >/dev/null || die "bateria < 25 % o enchufada durante la medida (se restaura el estado inicial)"
    [ -n "${MIC_S2IDLE:-}" ] && echo "  (s2idle: NO se lanza solo; hacerlo a mano en cada estado: UKE_TURNO=1 bash medir-s2idle.sh arm $MIC_S2IDLE y luego report)"
  done
  WH=$(S "awk '{printf \"%.2f\", \$1/1e6*3.9}' $BAT/charge_full" 2>/dev/null); WH=${WH:-34.5}; echo "capacidad estimada: $WH Wh (charge_full x 3,9 V); W medidos por corriente (~20-24 % por encima del gauge)"
  python3 - "$OUT" "$WH" <<'P'
import csv,sys,statistics as st
r=list(csv.DictReader(open(sys.argv[1])))
m={}
for x in r: m.setdefault(x['estado'],[]).append(float(x['w']))
if len(m)<2: sys.exit("muestras insuficientes (revisar formato de uke-bateria-lectura --short)")
a,b=st.mean(m['A']),st.mean(m['B']); d=b-a; wh=float(sys.argv[2])
print(f"A (base) {a:.3f} W · B (micro siempre abierto) {b:.3f} W · ΔW = {d:+.3f} W (~{d/ (a or 1)*100:+.0f} % sobre el suelo, ~{d/wh*100:.2f} %/h de bateria de {wh:.1f} Wh)")
print("PROPONER al dueño dejar la base" if d>0.05 else "coste despreciable (<= 0,05 W): se puede dejar abierto")
P
  echo "CSV: $OUT";;
revert) bash "$MIC" --revert; pw_restart;;
*) echo "uso: $0 check|run [segundos]|revert"; exit 2;;
esac
