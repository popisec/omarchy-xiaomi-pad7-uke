#!/bin/bash
# m5-zona.sh ZONA [SEG=4] — M5: UBICACION de los micros con una FUENTE PUNTUAL. El dueño pega el movil (tono continuo de 1 kHz) a la ZONA indicada (inferior|superior|izquierda|derecha|espalda: tablet vertical, pantalla hacia el)
# y se graban DOS tomas seguidas de SEG s: dual-1-4 (ch0 AMIC1, ch1 AMIC4) y dual-5-3 (ch0 AMIC5, ch1 AMIC3) = los 4 micros con posible entrada. El nivel (RMS sin el chasquido inicial) mas alto = el micro mas cercano.
# Se ejecuta EN la tablet con e9a cargada. Salida resumida en /root/mic-m3/m5-ZONA-*.txt
set -u
Z=${1:?uso: $0 inferior|superior|izquierda|derecha|espalda [SEG]}; S=${2:-4}; M3=${UKE_MIC_M3:-/usr/local/sbin/uke-mic-m3.sh}; OUT=/root/mic-m3/m5-$Z-$(date +%H%M%S).txt; : > "$OUT"
echo "== ZONA $Z: movil con tono de 1 kHz PEGADO a la zona; empiezo en 3 s"; sleep 3
for p in 1-4 5-3; do
	r=$("$M3" "dual-$p" "$S" 2>&1)
	l0=$(echo "$r" | grep "^canal 0" | sed 's/.*RMS_sin_0,5s_inicial //'); l1=$(echo "$r" | grep "^canal 1" | sed 's/.*RMS_sin_0,5s_inicial //')
	echo "$Z | pareja $p | AMIC${p%-*} (ch0): $l0 | AMIC${p#*-} (ch1): $l1 | $(echo "$r" | grep -E 'arecord rc' | tr -d '\n')" | tee -a "$OUT"
	sleep 3
done
echo "oops=$(dmesg | grep -cE 'Oops|Unhandled context|BUG:')"
