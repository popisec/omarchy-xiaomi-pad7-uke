#!/bin/sh
# Diagnóstico del regulador L8B y de los regularadores del panel, para la tablet uke.
# Se ejecuta en la tablet: sh /tmp/diag-l8b.sh
N=/proc/device-tree/soc/rsc@17a00000/drv@2/rpmh-regulator-ldob8/regulator-pmxr2230-l8

echo "=== 1) el nodo L8B en el DT vivo ==="
printf "  compatible    : "; tr '\0' '|' < "$N/compatible"; echo
printf "  regulator-name: "; tr '\0' ''  < "$N/regulator-name" 2>/dev/null; echo
printf "  phandle       : "; od -An -tx1 "$N/phandle" | tr -d ' \n'; echo
printf "  props         : "; ls "$N" 2>/dev/null | tr '\n' ' '; echo

echo
echo "=== 2) quien lo reclama (rpmh-regulator-ldob8) ==="
for d in /sys/bus/platform/devices/*ldob8*; do
  [ -e "$d" ] || continue
  echo "  device: $(basename "$d")"
  if [ -L "$d/driver" ]; then
    echo "    driver: $(basename "$(readlink "$d/driver")")"
  else
    echo "    driver: NINGUNO (nadie lo ha ligado)"
  fi
done

echo
echo "=== 3) el regulator-dummy: de que nodo sale ==="
grep -i dummy /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | sed 's/^/  /'

echo
echo "=== 4) los cuatro nodos regulador de display: enabledgpio y registro ==="
for n in display_gpio_regulator_vsp display_gpio_regulator_vsn \
         uke-regulator-display-vsp uke-regulator-display-vsn; do
  d=/proc/device-tree/soc/$n
  [ -d "$d" ] || { echo "  $n: NO EXISTE"; continue; }
  printf "  %-30s " "$n"
  printf "enable-gpios="; od -An -tx1 "$d/enable-gpios" 2>/dev/null | tr -d ' \n'
  printf "  gpio="; od -An -tx1 "$d/gpio" 2>/dev/null | tr -d ' \n'
  echo
done

echo
echo "=== 5) dmesg: todos los errores de regulador, sin filtrar por palabra clave ==="
dmesg | grep -iE "regulator|reg-fixed|ENOTRECOVERABLE|devm_regulator" \
  | grep -viE "dependency cycle|reserved mem" | tail -14

echo
echo "=== 6) el resumen completo de reguladores ==="
cat /sys/kernel/debug/regulator/regulator_summary 2>/dev/null
