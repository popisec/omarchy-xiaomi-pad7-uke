#!/usr/bin/env bash
# try-l8-runtime.sh — arreglar `vddil8b` EN CALIENTE, sin flash. 0 particiones tocadas.
#
# POR QUE
# ======
# Estado medido (28-sep): de los tres bloqueos del panel, dos ya estan resueltos:
#   - vsp/vsn -> ARREGLADO con gpio-shared-proxy.ko (ya instalado y persistente en el rootfs).
#   - gpio74/75 ya no son problema.
#   - SOLO queda `vddil8b`, que es el rail `pmxr2230-l8`.
#
# L8 falla con -131 porque `s236` (el dtbo que hay ahora) le puso a mano
# `regulator-min-microvolt = 1900000`, y 1900000 esta a 49,5 pasos de la rejilla de 8 mV del
# hw_data `pmic5_vendor_pldo` (1504000 + n*8000) => su rango no contiene NINGUN punto =>
# `regulator_map_voltage_linear_range()` devuelve -EINVAL y el registro muere.
# (regla y tabla: build/gates/DT-RAILS-L.md)
#
# `s229` deja L8B con `min = max = 0` justamente para que eso no pase. Arreglarlo por DT es lo que
# hace `s238`, y `s238` es UN FLASH: con la bateria en el suelo, no puedo flashear todavia.
#
# ESTE SCRIPT PRUEBA LA MISMA COSA EN CALIENTE, con un overlay de device tree por configfs:
# poner min=max=0 en L8B y re-disparar el probe del contenedor RPMh. Si el panel propea y aparece
# /dev/dri, la pantalla esta SIN GASTAR UN CICLO DE FLASH. Y ademas valida la hipotesis de s238
# antes de arriesgar el unico recurso escaso (el reintento de slot).
#
# SEGURIDAD
#   - NO toca ninguna particion. NO reinicia. NO entra en fastboot. NO abre /dev/dri. NO lee SPMI.
#   - Un overlay por configfs es un CAMBIO EN MEMORIA del device tree: no sobrevive al reinicio.
#     Si funciona, sestaclusion es para el proximo arranque, no permanente. El gateway permanente es
#     `s238`. Por eso este script es DIAGNOSTICO + prueba, no la solucion final.
#   - Reversible: `rmdir` del overlay (que en realidad no lo deshace; solo reiniciar lo deshace).
#     Es aceptable porque el estado al que vuelve es el de ahora, que ya sabemos que es "sin display".
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJ="$(cd "$HERE/../.." && pwd)"
OV_LOCAL=/tmp/uke-l8-min0.dtbo
SSH=(ssh -n -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=25
     -o ServerAliveInterval=10 -i "$PROJ/build/rootfs/uke-arch-root" root@192.168.42.129)
say() { printf '\n=== %s ===\n' "$*"; }

# ---------- construir el overlay en el PC ----------
say "1. construir el overlay: L8B con min = max = 0"
cat > /tmp/uke-l8-min0.dts <<'EOF'
/dts-v1/;

/ {
	fragment@0 {
		target-path = "/soc/rsc@17a00000/drv@2/rpmh-regulator-ldob8/regulator-pmxr2230-l8";
		__overlay__ {
			regulator-min-microvolt = <0>;
			regulator-max-microvolt = <0>;
		};
	};
};
EOF
dtc -I dts -O dtb -o "$OV_LOCAL" /tmp/uke-l8-min0.dts 2>&1 | head -3
[ -f "$OV_LOCAL" ] || { echo "  dtc fallo"; exit 1; }
echo "  $(stat -c %s "$OV_LOCAL") B, sha $(sha256sum "$OV_LOCAL" | cut -c1-16)"

say "2. estado ANTES"
"${SSH[@]}" 'M=/usr/lib/modules/$(uname -r)/extra
echo "  proxy cargado   : $(lsmod | grep -c shared_proxy)"
echo "  gpiochips       : $(ls /sys/bus/gpio/devices/ | wc -l)"
echo "  vsp/vsn         : $(grep -cE "panel_vsp|panel_vsn" /sys/kernel/debug/regulator/regulator_summary 2>/dev/null)"
echo "  L8              : $(grep -c pmxr2230_l8 /sys/kernel/debug/regulator/regulator_summary 2>/dev/null)"
echo "  /dev/dri        : [$(ls /dev/dri 2>&1 | tr "\n" " ")]"
echo "  configfs DT     : $([ -d /sys/kernel/config/device-tree/overlays ] && echo disponible || echo NO-MONTADO)"
echo "  L8B min/max     : $(od -An -tu4 --endian=big /proc/device-tree/soc/rsc@17a00000/drv@2/rpmh-regulator-ldob8/regulator-pmxr2230-l8/regulator-min-microvolt | tr -d " ")/$(od -An -tu4 --endian=big /proc/device-tree/soc/rsc@17a00000/drv@2/rpmh-regulator-ldob8/regulator-pmxr2230-l8/regulator-max-microvolt | tr -d " ")"' 2>&1 | sed 's/\r$//'

say "3. aplicar el overlay por configfs"
scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$PROJ/build/rootfs/uke-arch-root" "$OV_LOCAL" root@192.168.42.129:/root/ 2>&1
"${SSH[@]}" 'O=/sys/kernel/config/device-tree/overlays
mount | grep -q "device-tree/config" || mount -t configfs none /sys/kernel/config 2>/dev/null
[ -d "$O" ] || { echo "  configfs NO disponible: este camino no vale, hace falta s238"; exit 1; }
# MEDIDO 28-sep: el PRIMER `echo go` aplica el overlay y `status` pasa a "applied". Un SEGUNDO
# `echo go` da EACCES (el atributo ya es de solo lectura), asi que hay que mirar ANTES si el nodo
# ya esta en 0/0 y no reintentar a lo tonto: si no, el script miente con un "Permission denied" que
# parece un fallo cuando en realidad el overlay SI se aplico.
if [ "$(od -An -tu4 --endian=big $L/regulator-min-microvolt | tr -d " ")" = "0" ]; then
    echo "  el overlay YA esta aplicado (min=0): no lo vuelvo a aplicar"
else
    mkdir -p $O/uke-l8 2>/dev/null
    cat /root/uke-l8-min0.dtbo > $O/uke-l8/dtbo && echo "  dtbo escrito"
    echo go > $O/uke-l8/status 2>/dev/null
    echo "  status: $(cat $O/uke-l8/status 2>&1)"
fi
L=/proc/device-tree/soc/rsc@17a00000/drv@2/rpmh-regulator-ldob8/regulator-pmxr2230-l8
echo "  L8B min/max ahora: $(od -An -tu4 --endian=big $L/regulator-min-microvolt | tr -d " ")/$(od -An -tu4 --endian=big $L/regulator-max-microvolt | tr -d " ")"' 2>&1 | sed 's/\r$//'

say "4. re-disparar el probe del contenedor RPMh (rpmh-regulator-ldob8)"
"${SSH[@]}" 'dmesg -n 7 >/dev/null 2>&1
M=$(dmesg | wc -l)
D=$(ls -d /sys/bus/platform/devices/*rpmh-regulator-ldob8 2>/dev/null | head -1)
echo "  device: ${D:-NO EXISTE}"
N=$(basename "${D:-}")
if [ -n "$N" ]; then
  if echo "$N" > /sys/bus/platform/drivers/qcom-rpmh-regulator/bind 2>/dev/null; then
    echo "  bind: OK"
  else
    echo "  bind: rechazado (puede que ya este ligado)"
  fi
fi
sleep 2
echo "  L8 en el summary: $(grep -c pmxr2230_l8 /sys/kernel/debug/regulator/regulator_summary 2>/dev/null)"
grep -iE "pmxr2230_l8|ldob8" /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | sed "s/^/    /"
echo "  --- dmesg nuevo ---"
dmesg | tail -n +$((M+1)) | grep -viE "ufshcd|devfreq|audit|kauditd|qmp-ufs" | head -18' 2>&1 | sed 's/\r$//'

say "5. VEREDICTO"
"${SSH[@]}" 'echo "  L8       : $(grep -c pmxr2230_l8 /sys/kernel/debug/regulator/regulator_summary 2>/dev/null)  (1 = REGISTRADO)"
echo "  /dev/dri : [$(ls /dev/dri 2>&1 | tr "\n" " ")]"
echo "  conectores: $(ls /sys/class/drm/ 2>/dev/null | tr "\n" " ")"
echo "  el PANEL :"
dmesg | grep -iE "panel-xiaomi|failed to get regulators" | tail -3 | sed "s/^/    /"
echo "  Setting (la prueba de la rejilla):"
dmesg | grep -E "Setting [0-9]+-[0-9]+uV" | tail -3 | sed "s/^/    /"' 2>&1 | sed 's/\r$//'

say "si L8 aparece y el panel propea: el arreglo de s238 es correcto y se puede flashear sin miedo"
say "si L8 NO aparece: el overlay no se aplico, o el probe falla por otra cosa -> leer el dmesg de arriba"
