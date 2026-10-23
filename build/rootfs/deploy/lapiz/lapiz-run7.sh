#!/bin/sh
# Secuencia disparada por la conexion del lapiz (solo se anuncia justo tras pegarlo a la tablet):
#  1) espera/reintenta la conexion BLE (hasta ${1:-150} s)  2) handshake (hall=1)  3) escucha HID en segundo plano
#  4) espera 10 s (el dueno lo despega)  5) modo lapiz del chip 60 s con captura de frames.  Logs: /root/lapiz-run7.log, lapiz-penenable.log
P=02:00:5E:00:00:07
: > /root/lapiz-run7.log
btmon -w /root/lapiz-btmon9.snoop >/dev/null 2>&1 &
BM=$!
end=$(( $(date +%s) + ${1:-150} ))
while [ $(date +%s) -lt $end ]; do
  bluetoothctl info $P | grep -q "Connected: yes" && break
  timeout 6 bluetoothctl connect $P >/dev/null 2>&1
  sleep 1
done
if ! bluetoothctl info $P | grep -q "Connected: yes"; then echo "$(date +%T) no conecto" >> /root/lapiz-run7.log; kill $BM; exit 1; fi
echo "$(date +%T) conectado" >> /root/lapiz-run7.log
for i in 1 2 3 4 5 6 7 8 9 10; do bluetoothctl info $P | grep -q "ServicesResolved: yes" && break; sleep 1; done
python3 -I /root/lapiz-handshake.py --hall 1 > /root/lapiz-run5.log 2>&1
echo "$(date +%T) handshake hecho" >> /root/lapiz-run7.log
( /root/lapiz-hid-listen.sh 100 & )
sleep 10
echo "$(date +%T) modo lapiz" >> /root/lapiz-run7.log
/root/lapiz-penenable.sh 60 1 > /root/lapiz-penenable.log 2>&1
echo "$(date +%T) fin" >> /root/lapiz-run7.log
sleep 45
kill $BM
