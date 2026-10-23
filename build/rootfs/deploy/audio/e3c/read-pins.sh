#!/bin/bash
# read-pins.sh — SE EJECUTA EN LA TABLET (ssh root@… 'bash -s' < read-pins.sh [pin…]). Solo lectura: una lectura de CFG por pin con uke_lpi_rd
# (votos PRM + un ioread32 por pin; sin escrituras). Sin argumentos lee gpio6..9 (TDM de los amps). Requiere E3a (e3 + driver LPI) y uke_lpi_rd.ko en extra/.
K=$(uname -r); PINS=${*:-6 7 8 9}
for p in $PINS; do
	[ "$p" -ge 0 ] 2>/dev/null && [ "$p" -le 22 ] || { echo "pin invalido: $p"; exit 2; }
	insmod /lib/modules/$K/extra/uke_lpi_rd.ko uke_lpi_go=1 uke_lpi_pin=$p || { echo "insmod fallo (pin $p)"; exit 1; }
	sleep 0.3; rmmod uke_lpi_rd
	dmesg | grep "uke_lpi_rd: CFG(gpio$p)" | tail -1 | sed 's/.*uke_lpi_rd: //'
done
