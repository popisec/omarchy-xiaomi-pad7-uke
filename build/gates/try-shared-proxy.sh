#!/usr/bin/env bash
# try-shared-proxy.sh — probar en CALIENTE el arreglo del display SIN FLASH.
#
# POR QUE ESTO EXISTE
# ===================
# La causa raiz del panel se midio hoy en la tablet (ver build/gates/AUDITORIA-REGULADORES-Y-GPIO.md):
# gpio74 y gpio75 los piden DOS dispositivos `regulator-fixed` cada uno, y este kernel tiene un
# mecanismo de GPIO compartido PROPIO (drivers/gpio/gpiolib-shared.c + gpio-shared-proxy.c) que, con
# mas de un consumidor, marca el pin como GPIOD_FLAG_SHARED y enruta toda peticion a un chip PROXY
# `gpiolib_shared.proxy.<id>`. En la tablet hay 30 de esos dispositivos auxiliares y 0 de 30 con
# driver: `gpio-shared-proxy` NO esta construido en el kernel. Por eso los cuatro regularadores se
# quedan en -EPROBE_DEFER PARA SIEMPRE y el panel nunca propea.
#
# HAY DOS ARREGLOS, Y ESTE ES EL BARATO:
#   (A) este script: cargar el driver del proxy. 0 flashes, reversible con rmmod.
#       El hermano ya lo hizo en ESTE aparato para estos mismos rails (su ledger #410).
#   (B) `s238`: un overlay que deja un solo consumidor por pin. 1 flash, ya construido y
#       pre-registrado (build/bootimg/s238-boot-dtbo-dedup-gpio.img, sha bdb361df...).
# Se prueba (A) ANTES que (B): si funciona, no hace falta gastar un ciclo de flash ni un reintento de
# slot, que es el recurso mas escaso aqui (el contador ya llego a 0 una vez).
#
# SEGURIDAD
#   - NO toca /dev/dri, NO hace unbind de la GPU, NO lee SPMI ni el PMIC, NO instrumenta SMMU ni MMIO.
#   - NO reinicia, NO power-ciclea, NO entra en fastboot.
#   - Unica escritura: copia un .ko a /root/ y hace `insmod`. Si el modulo no carga (vermagic o
#     simbolo que falte), NO PASA NADA: el sistema queda exactamente como estaba.
#   - Rollback: `rmmod gpio_shared_proxy` (los regularadores que ya se hayan ligado se quedan
#     ligados; para volver al estado anterior haria falta reiniciar).
#   - `CONFIG_MODVERSIONS` esta OFF, asi que el vermagic es la unica puerta dura. El modulo pide
#     `devm_gpiochip_add_data_with_key`, el simbolo RENOMBRADO por este fork, asi que esta compilado
#     contra este arbol.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJ="$(cd "$HERE/../.." && pwd)"
KO_ORIGIN=~/gpu-work/ramaa/s10/build-s122/drivers/gpio/gpio-shared-proxy.ko
KO_SHA=911743742060bd7b168e27d2034802af44a718413f497862c7e3df60a1e4bfc6
SSH=(ssh -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15
     -o ServerAliveInterval=15 -i "$PROJ/build/rootfs/uke-arch-root" root@192.168.42.129)

say() { printf '\n=== %s ===\n' "$*"; }

say "0. el modulo en el PC"
[ -f "$KO_ORIGIN" ] || { echo "NO EXISTE $KO_ORIGIN"; exit 1; }
got=$(sha256sum "$KO_ORIGIN" | cut -d' ' -f1)
echo "  sha256 real : $got"
echo "  sha esperado: $KO_SHA"
[ "$got" = "$KO_SHA" ] || { echo "ABORTO: el sha no coincide. NO se copia nada."; exit 1; }
echo "  vermagic    : $(modinfo -F vermagic "$KO_ORIGIN")"
echo "  depende de  : $(modinfo -F depends "$KO_ORIGIN" | sed 's/^$/nada/')"

say "1. estado ANTES (para comparar)"
"${SSH[@]}" 'dmesg -n 7 >/dev/null 2>&1
echo "  proxies auxiliares: $(ls /sys/bus/auxiliary/devices/ 2>/dev/null | wc -l)"
echo "  con driver        : $(for d in /sys/bus/auxiliary/devices/*; do [ -L "$d/driver" ] && echo x; done | wc -l)"
echo "  gpiochips         : $(ls /sys/bus/gpio/devices/ 2>/dev/null | tr "\n" " ")"
echo "  /dev/dri          : $(ls /dev/dri 2>&1 | tr "\n" " ")"
echo "  panel             : $(dmesg | grep -c "panel-xiaomi-o82")"
echo "  diferidos de GPIO : $(dmesg | grep -c "can.t get GPIO")"' 2>&1 | sed 's/\r$//'

say "2. copiar el .ko e insmod"
scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$PROJ/build/rootfs/uke-arch-root" "$KO_ORIGIN" root@192.168.42.129:/root/ 2>&1
"${SSH[@]}" 'cd /root && sha256sum gpio-shared-proxy.ko
echo "--- dmesg -n 7 puesto, insmod: ---"
dmesg -n 7 >/dev/null 2>&1
M=$(dmesg | wc -l)
if insmod /root/gpio-shared-proxy.ko 2>/tmp/insmod.err; then
  echo "INSMOD: OK"
else
  echo "INSMOD: FALLIDO rc=$?  -> $(cat /tmp/insmod.err)"
  echo "  (si es Unknown symbol o version magic, el sistema queda IGUAL: no hay nada que revertir)"
fi
echo "--- chips gpio ahora: $(ls /sys/bus/gpio/devices/ 2>/dev/null | tr "\n" " ")"
echo "--- proxies con driver: $(for d in /sys/bus/auxiliary/devices/*; do [ -L "$d/driver" ] && echo x; done | wc -l) de $(ls /sys/bus/auxiliary/devices/ 2>/dev/null | wc -l)"
echo "--- dmesg nuevo ---"
dmesg | tail -n +$((M+1)) | grep -viE "ufshcd|devfreq|audit|kauditd|qmp-ufs" | head -25' 2>&1 | sed 's/\r$//'

say "3. re-disparar los 4 regularadores (los que estaban diferidos)"
"${SSH[@]}" 'M=$(dmesg | wc -l)
for d in soc:uke-regulator-display-vsp soc:uke-regulator-display-vsn \
         soc:display_gpio_regulator_vsp soc:display_gpio_regulator_vsn; do
  if echo "$d" > /sys/bus/platform/drivers/reg-fixed-voltage/bind 2>/dev/null; then
    echo "  $d: BIND OK"
  else
    echo "  $d: BIND rechazado (sigue diferido)"
  fi
done
echo "--- dmesg nuevo ---"
dmesg | tail -n +$((M+1)) | grep -viE "ufshcd|devfreq|audit|kauditd|qmp-ufs" | head -30' 2>&1 | sed 's/\r$//'

say "4. VEREDICTO"
"${SSH[@]}" 'echo "  /dev/dri              : $(ls /dev/dri 2>&1 | tr "\n" " ")"
echo "  /dev/fb               : $(ls /dev/fb 2>&1 | tr "\n" " ")"
echo "  conectores DRM        : $(ls /sys/class/drm/ 2>/dev/null | tr "\n" " ")"
echo "  L8 / L22 en el summary:"
grep -iE "pmxr2230_l(8|22)" /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | sed "s/^/    /"
echo "  vsp/vsn en el summary:"
grep -iE "panel_vsp|panel_vsn|panelvsp|panelvsn" /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | sed "s/^/    /"
echo "  el PANEL:"
dmesg | grep -iE "panel-xiaomi|failed to get regulators|mipi-dsi.*deferred|msm-mdss|deferred probe timeout" | tail -12 | sed "s/^/    /"
echo "  ultimo veredicto del lookup GPIO:"
dmesg | grep -iE "gpiolib_shared|can.t get GPIO" | tail -6 | sed "s/^/    /"' 2>&1 | sed 's/\r$//'

say "si /dev/dri aparece y el panel deja de diferir: el display esta y s238 NO hace falta"
say "si sigue 'cannot find GPIO chip': el modulo carga pero la entrada compartida no se resuelve"
say "si el panel propea pero el maestro no: siguiente paso, la carrera del display master"
