#!/bin/bash
# uke-touch-up.sh — prepara el tactil NT36532 para uke-touchd (idempotente). 18-oct-2026.
# spi0.0 (compatible downstream novatek,NVT-ts-spi) no tiene driver en el kernel: se liga a spidev (driver_override)
# para leerlo desde espacio de usuario; uinput publica la pantalla tactil. No envia nada por el bus.
set -u
modprobe spidev 2>/dev/null; modprobe uinput 2>/dev/null
D=/sys/bus/spi/devices/spi0.0
[ -e "$D" ] || { echo "uke-touch-up: no existe spi0.0"; exit 1; }
if [ "$(basename "$(readlink "$D/driver" 2>/dev/null)")" != spidev ]; then
	[ -e "$D/driver" ] && echo spi0.0 > "$D/driver/unbind"
	echo spidev > "$D/driver_override"
	echo spi0.0 > /sys/bus/spi/drivers/spidev/bind
fi
for _ in $(seq 1 20); do [ -c /dev/spidev0.0 ] && [ -c /dev/uinput ] && exit 0; sleep 0.1; done
echo "uke-touch-up: falta /dev/spidev0.0 o /dev/uinput"; exit 1
