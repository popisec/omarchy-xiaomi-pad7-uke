#!/bin/sh
# Intenta conectar el lapiz (anuncia solo un rato tras pegarlo) y, al conectar, lanza el handshake BLE. Log en /root/lapiz-run.log
P=02:00:5E:00:00:07
: > /root/lapiz-run.log
btmon -w /root/lapiz-btmon7.snoop >/dev/null 2>&1 &
BM=$!
end=$(( $(date +%s) + ${1:-120} ))
while [ $(date +%s) -lt $end ]; do
  if bluetoothctl info $P | grep -q "Connected: yes"; then echo "$(date +%T) conectado" >> /root/lapiz-run.log; break; fi
  timeout 6 bluetoothctl connect $P >> /root/lapiz-run.log 2>&1
  sleep 1
done
if bluetoothctl info $P | grep -q "Connected: yes"; then
  for i in 1 2 3 4 5 6 7 8 9 10; do bluetoothctl info $P | grep -q "ServicesResolved: yes" && break; sleep 1; done
  echo "$(date +%T) lanzando handshake" >> /root/lapiz-run.log
  python3 -I /root/lapiz-handshake.py --hall 0 >> /root/lapiz-run.log 2>&1
  sleep 5
  echo "$(date +%T) fin handshake" >> /root/lapiz-run.log
else
  echo "$(date +%T) no se pudo conectar" >> /root/lapiz-run.log
fi
kill $BM
