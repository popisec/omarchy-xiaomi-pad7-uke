#!/bin/bash
# try-apps-smmu-bind.sh — ENLZA apps-smmu EN CALIENTE, con la consola ya viva.
#
# QUE ES Y POR QUE
#   s251 (dtbo) wedgeó: el probe de arm-smmu cuelga el bus en un arch_initcall, cuando ttyGS0
#   todavía no existe, y por eso no hay ni una línea de consola (medido: 4 min de nada, luego el
#   ABL cae a fastboot con slot-retry-count 0).
#
#   ESTE script hace lo mismo SIN flash y SIN build de kernel: cambia el `compatible` del nodo con
#   un overlay de configfs (mecanismo YA PROBADO en esta tablet con el rail L8) y luego escribe el
#   nombre del device en `/sys/bus/platform/drivers/arm-smmu/bind`, que es un poke manual.
#   La diferencia que lo hace informativo: el probe corre con la CONSOLA YA EXISTENTE, así que
#   dmesg y la consola ACM enseñan exactamente en qué acceso MMIO se para.
#
#   El device 15000000.apps-smmu ya existe y no tiene driver (medido), que es la condición para
#   poder enlazarlo a mano.
#
# COSTE
#   0 flashes. 0 reintentos de slot. La tablet puede quedar colgada y necesitar reset físico: eso
#   es lo que hace el bus stall. El rootfs persiste y no se toca.
#
# CRITERIO, ESCRITO ANTES DE EJECUTAR
#   ÉXITO   : aparece "arm-smmu 15000000.apps-smmu: <context banks>" => el probe pasa. El SMMU del
#             display queda vivo y el DPU debería dejar de decir "no IOMMU, bailing out".
#   FALLO   : el probe se para antes. La ÚLTIMA línea de dmesg dice en qué punto, y eso es
#             exactamente el dato que no tenemos de los 8 intentos anteriores.
#   WEDGE   : la consola ACM muestra "arm-smmu 15000000.apps-smmu:" y luego silencio. Entonces ya
#             sabemos que el cuelgue es DENTRO del probe y no antes, y con qué última línea.
set -uo pipefail

OVL=/root/appssmmu.dtbo
O=/sys/kernel/config/device-tree/overlays
DEV=15000000.apps-smmu
BIND=/sys/bus/platform/drivers/arm-smmu/bind
NODEDT=/proc/device-tree/soc/apps-smmu@15000000

echo "=== 0. precondiciones ==="
dmesg -n 7 >/dev/null 2>&1
[ -d "$O" ] || { echo "ABORT: no hay configfs de DT ($O). NO FLASHAR, no seguir."; exit 1; }
[ -f "$OVL" ] || { echo "ABORT: no esta el overlay en $OVL"; exit 1; }
[ -e "/sys/bus/platform/devices/$DEV" ] || { echo "ABORT: no existe el device $DEV"; exit 1; }
if [ -n "$(readlink /sys/bus/platform/devices/$DEV/driver 2>/dev/null)" ]; then
    echo "ABORT: $DEV YA TIENE DRIVER. No se toca."; exit 1
fi
if [ ! -e "$BIND" ]; then
    echo "AVISO: no existe $BIND (el driver arm-smmu no esta registrado). No se puede hacer el poke."
    exit 1
fi
echo "  configfs DT: OK"
echo "  device $DEV: existe, SIN driver: OK"
echo "  $BIND: presente: OK"
echo "  compatible actual: $(tr -d '\0' < $NODEDT/compatible 2>/dev/null)"
echo "  grupos iommu antes: $(ls /sys/kernel/iommu_groups 2>/dev/null | wc -l)"

echo
echo "=== 1. overlay: cambiar SOLO el compatible de apps-smmu ==="
if [ "$(tr -d '\0' < $NODEDT/compatible 2>/dev/null)" = "qcom,qsmmu-v500" ]; then
    rm -rf "$O/uke-apps-smmu" 2>/dev/null
    mkdir -p "$O/uke-apps-smmu" || { echo "ABORT: mkdir configfs"; exit 1; }
    cat "$OVL" > "$O/uke-apps-smmu/dtbo" || { echo "ABORT: escribir dtbo"; exit 1; }
    echo go > "$O/uke-apps-smmu/status" 2>/dev/null
    echo "  status: $(cat $O/uke-apps-smmu/status 2>&1 | tr -d '\n')"
else
    echo "  ya aplicado, no lo vuelvo a aplicar (un 2o 'echo go' da EACCES y confunde)"
fi
COMP=$(tr -d '\0' < $NODEDT/compatible 2>/dev/null)
case "$COMP" in
    *arm,mmu-500*) echo "  compatible AHORA: $COMP  => el nodo DEBERIA enlazar" ;;
    *) echo "  ABORT: el compatible no ha cambiado: '$COMP'. No seguir."; exit 1 ;;
esac

echo
echo "=== 2. el poke: enlazar el device a mano, con la consola ya viva ==="
echo "  (esto es lo que s251 hacia en un arch_initcall, aqui con ttyGS0 ya creado)"
date +%H:%M:%S
echo "$DEV" > "$BIND" 2>/dev/null
RC=$?
date +%H:%M:%S
echo "  bind: rc=$RC"

echo
echo "=== 3. que paso ==="
sleep 3
echo "  driver ahora: $(basename $(readlink /sys/bus/platform/devices/$DEV/driver 2>/dev/null) 2>/dev/null || echo NINGUNO)"
echo "  grupos iommu:  $(ls /sys/kernel/iommu_groups 2>/dev/null | wc -l)"
echo "  --- dmesg del SMMU ---"
dmesg | grep -aE "arm-smmu|apps-smmu|context bank|out of range|impossible number|Limiting|15000000" | tail -20
echo "  --- dmesg del DPU ---"
dmesg | grep -aiE "no IOMMU|dpu_kms_mmu|kms hw init|dpu hardware|bound ae" | tail -8
echo "  --- las ultimas 25 lineas de dmesg, enteras ---"
dmesg | tail -25
echo
echo
echo "=== VEREDICTO ==="
# La senal real es el symlink del driver, no dmesg: el driver NO imprime "context bank" en exito
# (esa frase solo sale en comentarios), asi que la rama de EXITO por dmesg era inalcanzable.
# Si basename(readlink .../driver) == arm-smmu, el probe paso y el bind enlazo de verdad.
DRV_AHORA="$(basename "$(readlink /sys/bus/platform/devices/$DEV/driver 2>/dev/null)" 2>/dev/null || echo NINGUNO)"
[ -n "$DRV_AHORA" ] || DRV_AHORA="NINGUNO"
if [ "$DRV_AHORA" = "arm-smmu" ]; then
    echo "  EXITO: $DEV enlazado a arm-smmu (driver=$DRV_AHORA). El SMMU del display esta vivo."
elif dmesg | grep -qa "arm-smmu $DEV"; then
    echo "  FALLO LOCALIZADO: el probe empezo y se paro (driver=$DRV_AHORA). Las lineas de arriba dicen donde."
else
    echo "  NO-OP: el bind no llego a invocar el probe (driver=$DRV_AHORA). Ver el bind rc y si el device se reenumeró."
fi
