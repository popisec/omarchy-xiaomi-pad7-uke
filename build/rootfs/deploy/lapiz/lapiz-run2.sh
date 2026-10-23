#!/bin/sh
# Handshake con hall=1 (lapiz despegado/en uso) y a continuacion escucha de informes HID. Log en /root/lapiz-run2.log y /root/lapiz-hid-listen.log
python3 -I /root/lapiz-handshake.py --hall 1 > /root/lapiz-run2.log 2>&1
sleep 1
/root/lapiz-hid-listen.sh ${1:-75}
