#!/bin/sh
# uke-usb-gadget-late.sh — gadget USB (ACM + NCM) TARDÍO, idempotente.
#
# POR QUÉ. El overlay USB embebido en el kernel senemos pone en el nodo dwc3
# `usb-psy-name = "qcom-battmgr-usb"`, y dwc3_core_probe() devuelve
# -EPROBE_DEFER mientras ese power_supply no exista (drivers/usb/dwc3/core.c,
# dwc3_get_usb_power_supply). El psy lo registra qcom_battmgr, que necesita el
# ADSP, que vive en el rootfs. Resultado: el UDC aparece DESPUÉS de uke-carga y
# el initramfs (/ukeinit: ventana UDC de 600 s, luego sigue sin gadget) ya hizo
# switch_root sin enlazar nada. Este guion crea el gadget cuando el UDC sale.
# Mismo gadget que /ukeinit (S118/S119): acm.usb0 + ncm.usb0, config c.1.
# OPCIONAL: el kernel ouke2 quita esa propiedad (SENEMOS-V2-USB-20261017.md) y entonces el UDC ya
# está enlazado por el initramfs: este guion no hace nada. Solo vale para un DT con usb-psy-name.
#
# Variables UKE_* solo para pruebas fuera de la tablet.
set -u
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SYS=${UKE_SYS:-/sys}
CFG=${UKE_CFG:-$SYS/kernel/config/usb_gadget}
T_UDC=${UKE_T_UDC:-150}
G=$CFG/g1
TABLET_IP=192.168.42.129/24
say() { echo "uke-gadget-late: $*"; }

mountpoint -q "$SYS/kernel/config" 2>/dev/null || mount -t configfs configfs "$SYS/kernel/config" 2>/dev/null
[ -d "$CFG" ] || { say "sin configfs usb_gadget (¿USB_CONFIGFS?): salgo"; exit 1; }

bound() { # algún gadget ya enlazado a un UDC
	for g in "$CFG"/*/; do
		[ -n "$(cat "${g}UDC" 2>/dev/null)" ] && return 0
	done
	return 1
}

if bound; then
	say "ya hay un gadget enlazado: nada que hacer"
	exit 0
fi

i=0
UDC=""
while [ "$i" -lt "$T_UDC" ]; do
	UDC=$(ls "$SYS/class/udc" 2>/dev/null | head -1)
	[ -n "$UDC" ] && break
	bound && { say "enlazado por otro mientras esperaba"; exit 0; }
	sleep 1
	i=$((i + 1))
done
if [ -z "$UDC" ]; then
	say "sin UDC tras ${T_UDC}s (dwc3 sigue diferido: ¿battmgr/usb psy?)"
	exit 1
fi
say "UDC $UDC tras ${i}s"

if [ ! -d "$G" ]; then
	mkdir -p "$G" || exit 1
	echo 0x1d6b > "$G/idVendor"
	echo 0x0104 > "$G/idProduct"
	mkdir -p "$G/strings/0x409"
	echo UKE-SENEMOS > "$G/strings/0x409/serialnumber"
	echo "Xiaomi Pad 7 Linux" > "$G/strings/0x409/manufacturer"
	echo "UKE senemos" > "$G/strings/0x409/product"
	mkdir -p "$G/functions/acm.usb0" || { say "FALLO: acm.usb0 (¿USB_F_ACM?)"; exit 1; }
	mkdir -p "$G/configs/c.1/strings/0x409"
	echo ACM+NCM > "$G/configs/c.1/strings/0x409/configuration"
	echo 120 > "$G/configs/c.1/MaxPower"
	if mkdir -p "$G/functions/ncm.usb0"; then
		ln -s "$G/functions/ncm.usb0" "$G/configs/c.1/" || say "AVISO: ln ncm"
	else
		say "AVISO: sin ncm.usb0 (¿USB_F_NCM?), solo ACM"
	fi
	ln -s "$G/functions/acm.usb0" "$G/configs/c.1/" || say "AVISO: ln acm"
	echo high-speed > "$G/max_speed" 2>/dev/null
fi
echo "$UDC" > "$G/UDC" 2>/dev/null
if [ "$(cat "$G/UDC" 2>/dev/null)" = "$UDC" ]; then
	say "gadget ENLAZADO a $UDC"
else
	say "FALLO: bind a $UDC"
	exit 1
fi

# La IP la pone systemd-networkd (10-uke-usb.network: usb0/enx*/rndis*). Respaldo
# por si networkd no la puso en 8 s.
n=0
while [ "$n" -lt 8 ]; do
	[ -e "$SYS/class/net/usb0" ] && break
	sleep 1
	n=$((n + 1))
done
if [ -e "$SYS/class/net/usb0" ]; then
	sleep 3
	if ! ip -4 addr show dev usb0 2>/dev/null | grep -q 'inet 192.168.42.129/'; then
		ip link set usb0 up 2>/dev/null
		ip addr add "$TABLET_IP" dev usb0 2>/dev/null && say "IP de respaldo $TABLET_IP en usb0"
	else
		say "usb0 ya con 192.168.42.129 (networkd)"
	fi
else
	say "AVISO: no apareció usb0 (solo ACM, o NCM falló)"
fi
exit 0
