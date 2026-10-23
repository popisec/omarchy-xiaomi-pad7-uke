#!/bin/sh
# Sesion larga: btsnoop + handshake BLE (hall=1) + escucha HID; el modo lapiz del chip se arranca aparte con lapiz-penenable.sh.
btmon -w /root/lapiz-btmon8.snoop >/dev/null 2>&1 &
BM=$!
python3 -I /root/lapiz-handshake.py --hall 1 > /root/lapiz-run5.log 2>&1
sleep 1
/root/lapiz-hid-listen.sh ${1:-250}
kill $BM
