#!/bin/bash
# android-captura.sh [segundos=120] — SOLO LECTURA por adb+su. Con el CARGADOR DE PARED puesto (no el PC), mide
# cómo carga Android: tipo, PDO/APDO, bomba de carga, corriente, y las trazas BATTERY_CHG del kernel.
# Salida: build/android/bateria-20261019/carga-rapida/pared-<fecha>.txt
set -u; T=${1:-120}; SER=${ADB_SERIAL:-SERIE0001}
R=$(cd "$(dirname "$0")/../../../../.." && pwd); OUT=$R/build/android/bateria-20261019/carga-rapida; mkdir -p "$OUT"
F=$OUT/pared-$(date +%Y%m%d-%H%M%S).txt
{ echo "# android $(date) T=$T serie=$SER"
  adb -s $SER shell 'su -c sh' <<EOS
Q=/sys/class/qcom-battery; P=/sys/class/power_supply
i=0; while [ \$i -lt $T ]; do
 echo "\$(date +%T) rm=\$(cat \$Q/fg1_rm) rsoc=\$(cat \$Q/fg1_rsoc) bat_I=\$(cat \$P/battery/current_now) bat_V=\$(cat \$P/battery/voltage_now) usb_type=\$(cat \$Q/usb_real_type) qc_type=\$(cat \$Q/quick_charge_type) fastchg=\$(cat \$Q/fastchg_mode) cp_mode=\$(cat \$Q/cp_mode) pdo2=\$(cat \$Q/pdo2) apdo_max=\$(cat \$Q/apdo_max) pps_ptf=\$(cat \$Q/pps_ptf) power_max=\$(cat \$Q/power_max) adapter=\$(cat \$Q/adapter_id)/\$(cat \$Q/adapter_svid) cp_bus_I=\$(cat \$Q/bq2597x_bus_current) cp_bus_V=\$(cat \$Q/bq2597x_bus_voltage) usb_V=\$(cat \$P/usb/voltage_now) usb_I=\$(cat \$P/usb/current_now) usb_ilim=\$(cat \$P/usb/input_current_limit) ucsi_max=\$(cat \$P/ucsi*/current_max 2>/dev/null) typec=\$(cat \$Q/typec_mode)"
 i=\$((i+5)); sleep 5; done
echo "## typec"; for d in /sys/class/typec/*; do echo \$d; for f in \$d/*; do [ -f \$f ] && echo "  \$(basename \$f)=\$(cat \$f 2>/dev/null)"; done; done
echo "## usb_power_delivery"; ls -R /sys/class/usb_power_delivery 2>&1 | head -50
echo "## dmesg BATTERY_CHG / PD"; dmesg | grep -i -E "BATTERY_CHG|pdo|apdo|pps|pd_verif|ucsi|vdm" | tail -120
EOS
} > "$F" 2>&1; echo "guardado: $F"; grep -E "usb_type=" "$F" | tail -3
