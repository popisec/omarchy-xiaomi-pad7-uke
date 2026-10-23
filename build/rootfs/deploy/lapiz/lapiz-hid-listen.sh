#!/bin/sh
# Escucha los informes HID del lapiz (ya con handshake hecho): activa notify en los informes 1 (raton), 2 (teclado), 5 (vendor, presion) y 0x38 (fe12).
# Uso: lapiz-hid-listen.sh [segundos]. Log en /root/lapiz-hid-listen.log (solo lectura de notificaciones; escribe CCCD).
D=/org/bluez/hci0/dev_70_61_EE_XX_XX_XX
( echo "menu gatt"
  for c in service0034/char0037 service001c/char0025 service001c/char0029 service001c/char002d; do echo "select-attribute $D/$c"; echo "notify on"; sleep 0.5; done
  sleep ${1:-60}
  echo "back"; echo "quit" ) | bluetoothctl > /root/lapiz-hid-listen.log 2>&1
