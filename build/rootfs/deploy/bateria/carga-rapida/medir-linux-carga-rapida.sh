#!/bin/bash
# medir-linux-carga-rapida.sh [segundos=180] — SE EJECUTA EN EL PC. Mide la carga en Linux por SSH (Tailscale root@uke, respaldo USB),
# SOLO LECTURA, con el cargador de pared PD/PPS (33 W) puesto y SIN cable al PC (la tablet sigue alcanzable por WiFi/Tailscale).
# Salida: build/logs/carga-rapida-linux-<fecha>.csv + resumen. Comparar con build/android/bateria-20261019/carga-rapida/pared-*.txt
# Signo en Linux (qcom_battmgr): current_now > 0 = CARGA. Mejor con la bateria <80 % (a >90 % la corriente cae por fin de carga).
set -u; T=${1:-180}; HOST=${UKE_HOST:-root@uke}
R=$(cd "$(dirname "$0")/../../../../.." && pwd); KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}
OUT=$R/build/logs/carga-rapida-linux-$(date +%Y%m%d-%H%M%S).csv; mkdir -p "$R/build/logs"
echo "hora,status,cap,charge_counter_uAh,bat_I_uA,bat_V_uV,charge_type,usb_online,usb_V_uV,usb_I_uA,input_current_limit,usb_type,temp_dC,perfil" > "$OUT"
timeout $((T + 60)) ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 "$HOST" bash -s >> "$OUT" <<EOS
B=/sys/class/power_supply/qcom-battmgr-bat; U=/sys/class/power_supply/qcom-battmgr-usb
end=\$((\$(date +%s) + $T))
while [ \$(date +%s) -lt \$end ]; do
 echo "\$(date +%T),\$(cat \$B/status),\$(cat \$B/capacity),\$(cat \$B/charge_counter),\$(cat \$B/current_now),\$(cat \$B/voltage_now),\$(cat \$B/charge_type),\$(cat \$U/online),\$(cat \$U/voltage_now),\$(cat \$U/current_now),\$(cat \$U/input_current_limit),\$(grep -o '\[[^]]*\]' \$U/usb_type | tr -d '[]'),\$(cat \$B/temp),\$(cat /var/lib/uke-bateria/perfil)"
 sleep 3
done
EOS
python3 - "$OUT" <<'PY'
import csv, sys
r = list(csv.DictReader(open(sys.argv[1])))
if not r: sys.exit("sin muestras (¿tablet alcanzable por root@uke?)")
f = lambda k: [float(x[k]) for x in r]
I, V, uV, uI = f("bat_I_uA"), f("bat_V_uV"), f("usb_V_uV"), f("usb_I_uA")
w = [i * v / 1e12 for i, v in zip(I, V)]
print(f"{len(r)} muestras · cap {r[0]['cap']}->{r[-1]['cap']} % · tipo USB {sorted({x['usb_type'] for x in r})} · ICL {sorted({x['input_current_limit'] for x in r})}")
print(f"batería (+ = carga): media {sum(w)/len(w):.2f} W, pico {max(w):.2f} W (I máx {max(I)/1e6:.2f} A) · VBUS medio {sum(uV)/len(uV)/1e6:.2f} V, IBUS medio {sum(uI)/len(uI)/1e6:.3f} A")
print("Referencia Linux 20-oct (PD/PPS): +4,45 A a 4,43 V = 19,7 W al 93 %; Android 19-oct: +2,6-2,9 A a 4,45 V ≈ 12 W al 72 %.")
PY
echo "CSV: $OUT"
