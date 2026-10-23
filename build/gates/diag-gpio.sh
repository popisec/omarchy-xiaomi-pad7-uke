#!/bin/sh
# diag-gpio.sh — el diagnostico que decide el bloqueo del display. 0 flashes, 0 escrituras.
#
# SE EJECUTA EN LA TABLET:   sh /tmp/diag-gpio.sh
# (o por SSH: build/gates/uke-ssh.sh 'sh /tmp/diag-gpio.sh'  tras copiarlo)
#
# POR QUE ESTE SCRIPT Y NO UN ARREGLO
# ===================================
# `s234` y `s236` fueron dos overlays que costaron un ciclo de flash cada uno y los dos fueron
# no-ops o retrocesos. La auditoria (build/gates/AUDITORIA-REGULADORES-Y-GPIO.md) LLEGO a un punto
# donde ya no se puede avanzar por leitura: la cadena del lookup del GPIO tiene un eslabon que solo
# se puede medir en el aparato. Este script mide ese eslabon y nada mas.
#
# LO QUE SE SABE (medido, no supuesto)
# -----------------------------------
#   reg-fixed-voltage: can't get GPIO  =  ERR_PTR(-EPROBE_DEFER)
# porque `of_get_named_gpiod_flags()` (drivers/gpio/gpiolib-of.c:432-437) devuelve
# ERR_PTR(-EPROBE_DEFER) cuando `of_find_gpio_device_by_xlate()` no localiza el chip GPIO.
# O sea: NO es que falte la propiedad, es que el chip del phandle 0x16b no se encuentra.
# Y afecta a 4 nodos, incluidos dos que NO tienen `enable-gpios` (por eso `s236` no los arreglo).
#
#   gpiochip0 esta REGISTRADO del todo. La ausencia de base/ngpio/label en sysfs NO es una averia:
#   en este kernel no existe ni un DEVICE_ATTR de esos (modelo nuevo de gpio_device). Lo unico que
#   crea el ultimo paso, gpiochip_setup_dev() (gpiolib.c:929), es el chardev "dev", que si existe.
#
# EL UNICO ESLABON SIN VERIFICAR
# -----------------------------
#   device_match_of_node(&chip->gpiodev->dev, gpiospec->np)
# o sea: que el `of_node` del gpiochip sea realmente /soc/pinctrl@f000000, que es el nodo al que
# apunta el phandle 0x16b. Todo lo demas de la cadena ya esta revisado y encaja.
#
# QUE DECIDE CADA RESULTADO
# ------------------------
#   (1) SI   -> el gpiochip esta registrado bajo OTRO nodo DT. La causa raiz esta encontrada y es
#               de codigo (msm_gpio_init / chip->fwnode) o de DT. NO tocar regulator-fixed.
#   (1) NO   -> hay que seguir. El paso siguiente es (3): el texto del lookup dira donde falla.
#   (3) "parsed ... status (0)"  -> el lookup FUNCIONA. Entonces el diferido viene de otro sitio y el
#                                  texto de (3) es la pista.
#   (3) "can't parse ..."        -> la propiedad esta mal formada (no es el caso segun el DT).
#   (3) nada                    -> el chip no aparece en la lista; el arreglo es de registro.

# dmesg -n 7 ANTES de nada: los pr_debug del lookup son KERN_DEBUG y con el nivel por defecto
# no salen, y "no hay linea" se confundiria con "no hay evidencia".
dmesg -n 7 2>/dev/null

echo
echo "############ 1) EL ESLABON: ¿de qué nodo DT es el gpiochip? ############"
echo "--- destino de of_node del gpiochip (tiene que ser el nodo del phandle 0x16b) ---"
ls -l /sys/bus/gpio/devices/gpiochip0/ 2>&1
printf "  gpiochip0/of_node -> "; readlink -f /sys/bus/gpio/devices/gpiochip0/of_node 2>&1
printf "  phandle 0x16b     -> "; readlink -f /proc/device-tree/soc/pinctrl@f000000 2>&1
echo "  bytes del phandle del nodo pinctrl (od -An -tx1, BIG-ENDIAN):"
printf "    "; od -An -tx1 /proc/device-tree/soc/pinctrl@f000000/phandle 2>&1 | tr -d ' \n'; echo
echo "  (00 00 01 6b = 0x16b. OJO: od -tx4 invierte el orden en un host little-endian y da falsos"
echo "   positivos; ESTA es la trampa que ya me hizo retractar una conclusion.)"

echo
echo "--- el phandle que realmente usan los regularadores, leido del DT vivo ---"
for n in uke-regulator-display-vsp uke-regulator-display-vsn \
         display_gpio_regulator_vsp display_gpio_regulator_vsn; do
  d=/proc/device-tree/soc/$n
  [ -d "$d" ] || { echo "  $n: NO EXISTE"; continue; }
  printf "  %-28s gpio=" "$n"
  od -An -tx1 "$d/gpio" 2>/dev/null | tr -d ' \n'
  printf "  enable-gpios="
  od -An -tx1 "$d/enable-gpios" 2>/dev/null | tr -d ' \n'
  echo
done

echo
echo "############ 2) ¿existen y son validas las lineas 74 y 75? ############"
echo "  (gpiochip_line_is_valid: el unico filtro es qcom,gpios-reserved = 8 9 10 11 56 57 58 59 60)"
printf "  qcom,gpios-reserved: "
tr '\0' ' ' < /proc/device-tree/soc/pinctrl@f000000/qcom,gpios-reserved 2>/dev/null; echo
echo "--- /sys/kernel/debug/gpio: primera linea y las 70-80 ---"
head -1 /sys/kernel/debug/gpio 2>&1
sed -n '70,82p' /sys/kernel/debug/gpio 2>&1
echo "  (las lineas ausentes = GPIO reservadas o sin asignar)"

echo
echo "############ 3) EL VEREDICTO DEL LOOKUP, EN TEXTO ############"
echo "  pr_debug de of_get_named_gpiod_flags (solo visible con dmesg -n 7, hecho arriba)"
dmesg 2>/dev/null | grep -iE "of_get_named_gpiod_flags|of_find_gpio|parsed '|can't parse" | tail -30
echo "  ---"
echo "  Fallback: si el kernel compila CONFIG_DYNAMIC_DEBUG, los pr_debug necesitan esto:"
echo "    echo 'func of_get_named_gpiod_flags +p' > /sys/kernel/debug/dynamic_debug/control"
echo "  (sin .config local no se puede comprobar cual de los dos casos es, asi que un 'nada' aqui"
echo "   es AMBIGUO: haz el fallback antes de concluir nada.)"
echo "  si no sale NADA: el lookup no llego a completarse. Abrir dmesg entero y buscar 'gpio'."
dmesg 2>/dev/null | grep -inE "gpio|pinctrl" | tail -25

echo
echo "############ 4) REGULADORES: ¿existe vddil8b? ############"
echo "  (el 'dummy' regulator-fixed de s234/s236 es CODIGO MUERTO: rpmh_regulator_vendor_probe()"
echo "   se come el nodo hijo en proceso, asi que ningun segundo driver puede ligar.)"
echo "  ESPERADO con s236: rpmh-regulator-ldob8 AUSENTE y vddil8b sin regulador."
echo "  ESPERADO con s237: rpmh-regulator-ldob8 PRESENTE y vddil8b resuelto."
echo "  OJO con la tension que se lea: NO tiene que ser 1900000. La rejilla es de 8000 uV, asi que"
echo "  el selector cacheado por apply_init sera el punto de rejilla mas proximo a 1900000, que es"
echo "  1896000 o 1904000. Ver 1896000 NO es un fallo: es la rejilla. (DT-RAILS-L.md)"
grep -iE "pmxr2230_l(8|22)|display_(gpio_)?regulator|regulator-vsp|regulator-vsn" \
    /sys/kernel/debug/regulator/regulator_summary 2>&1
echo "--- los rails L* registrados, en una linea ---"
grep -oE "pmxr2230_l[0-9]+" /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | sort -u -V | tr '\n' ' '
echo
echo "--- dmesg: los -131 de L8/L22 (deben ser 0 con s237 en L8) ---"
dmesg 2>/dev/null | grep -nE "ENOTRECOVERABLE|devm_regulator_register|failed to register regulator" | tail -20
echo "  BUSCA TAMBIEN la linea de info que DEBE preceder a cada -131 (regla de la rejilla):"
echo "    Setting 3300000-3300000uV"
echo "  Si aparece 'Setting' y aun asi hay -131, la REGLA ES FALSA. Si no aparece nunca y hay -131,"
echo "  tambien: entonces el -131 viene por otro sitio y la auditoria queda refutada."
echo "  (con s237: 0 lineas para uke-l8b-stub/pmxr2230_l8. pmxr2230_l22 SEGUIRA fallando con -131:"
echo "   es preexistente del overlay bueno y el panel NO lo usa.)"

echo
echo "############ 5) EL PANEL: ¿que supplies le faltan ahora? ############"
dmesg 2>/dev/null | grep -iE "panel-xiaomi|failed to get regulators|deferred probe pending" | tail -20

echo
echo "############ 6) ¿QUE DTO ESTA PUESTO DE VERDAD? ############"
P=/proc/device-tree/soc/rsc@17a00000/drv@2/rpmh-regulator-ldob8/regulator-pmxr2230-l8
echo "  props de L8B: $(ls $P 2>/dev/null | tr '\n' ' ')"
printf "  regulator-name: "; tr '\0' '' < "$P/regulator-name" 2>/dev/null; echo
printf "  min/max: "; od -An -tu4 --endian=big "$P/regulator-min-microvolt" 2>/dev/null | tr -d ' \n'
printf " / "; od -An -tu4 --endian=big "$P/regulator-max-microvolt" 2>/dev/null | tr -d ' \n'; echo
echo "  (con s236: compatible=regulator-fixed, name=uke-l8b-stub, min=max=1900000  <-- MAL)"
echo "   con s229/s237: sin compatible, name=pmxr2230_l8, min=max=0             <-- BIEN)"
printf "  root compatible: "; tr '\0' '|' < /proc/device-tree/compatible 2>/dev/null; echo
echo "  GPU: $(cat /sys/bus/platform/devices/3d00000.qcom,kgsl-3d0/driver 2>/dev/null | xargs -r basename)"
echo "  /dev/dri: $(ls /dev/dri 2>&1 | tr '\n' ' ')"

echo
echo "=== fin. NO se ha escrito nada en la tablet con este script. ==="
