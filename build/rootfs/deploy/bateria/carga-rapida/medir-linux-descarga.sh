#!/bin/bash
# medir-linux-descarga.sh — SE EJECUTA EN EL PC. Drenaje real SIN cable por Tailscale (root@uke): espera a Discharging con >=20 %, y mide
# fases (pantalla encendida 90 s, DPMS off 120 s; restaura SIEMPRE la pantalla con trap y con un respaldo systemd-run en la tablet).
# W de sistema = tension*corriente de descarga (sin cargador no hay termino de entrada USB, medida directa). Salida: build/logs/drenaje-linux-<fecha>.csv
# Signo uke-bateria-lectura: w > 0 = descarga. NO usar con <20 % (UPower suspende al 2 %). El wifi/tailscale activo cuenta (~0,36 W).
set -u; HOST=${UKE_HOST:-root@uke}; MINCAP=${MINCAP:-20}
R=$(cd "$(dirname "$0")/../../../../.." && pwd); KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}
SSH() { ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 "$HOST" "$@"; }
OUT=$R/build/logs/drenaje-linux-$(date +%Y%m%d-%H%M%S).csv; mkdir -p "$R/build/logs"
echo "esperando Discharging con >=$MINCAP % (desenchufa la tablet)..." >&2
until [ "$(SSH 'cat /sys/class/power_supply/qcom-battmgr-bat/status 2>/dev/null' 2>/dev/null)" = Discharging ] && \
      [ "$(SSH 'cat /sys/class/power_supply/qcom-battmgr-bat/capacity' 2>/dev/null || echo 0)" -ge "$MINCAP" ]; do sleep 5; done
sleep 30; echo "fase 1/2 pantalla encendida; 2/2 DPMS off (la pantalla se enciende sola al final)" >&2
echo "fase,hora,status,cap,pct_exact,w_drenaje,v,i_a,temp_c,perfil" > "$OUT"
SSH bash -s >> "$OUT" <<'EOS'
H="runuser -u omarchy -- env XDG_RUNTIME_DIR=/run/user/1001 HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1001/hypr|head -1) hyprctl"
on() { $H dispatch 'hl.dsp.dpms({ action = "on" })' >/dev/null 2>&1; }
systemd-run --on-active=420 --unit=uke-drenaje-restaura -- sh -c "$H dispatch 'hl.dsp.dpms({ action = \"on\" })'" >/dev/null 2>&1
trap on EXIT
fase() { # nombre segundos
  end=$(( $(date +%s) + $2 ))
  while [ $(date +%s) -lt $end ]; do
    uke-bateria-lectura --json | python3 -c "import json,sys,time; d=json.load(sys.stdin); print('$1,%s,%s,%s,%s,%s,%s,%s,%s,%s' % (time.strftime('%T'), d['estado'], d['pct'], d['pct_exact'], d['w'], d['v'], d['i_a'], d['temp_c'], d['perfil']))"
    sleep 2
  done
}
fase pantalla_on 90
$H dispatch 'hl.dsp.dpms({ action = "off" })' >/dev/null 2>&1; sleep 8
fase dpms_off 120
on
EOS
python3 - "$OUT" <<'PY'
import csv, sys
r = list(csv.DictReader(open(sys.argv[1])))
for ph in ("pantalla_on", "dpms_off"):
    w = [float(x["w_drenaje"]) for x in r if x["fase"] == ph and x["w_drenaje"]]
    if w: print(f"{ph}: {sum(w)/len(w):.2f} W de media ({len(w)} muestras, min {min(w):.2f}, max {max(w):.2f})")
print("Referencias Linux 20-oct (con cargador, entrada constante): DPMS off 1,39 W; pantalla 5 %/60 Hz 2,43 W. Android: sin medir en reposo limpio.")
PY
echo "CSV: $OUT"
