#!/bin/bash
# m4-guion.sh [PARES...] — M4: DOS micros a la vez (canal 0 = AMICA, canal 1 = AMICB) con el guion de 8 s del dueño: 0-2 s SILENCIO; 2-4 s raspa/golpea el borde INFERIOR; 4-6 s el SUPERIOR; 6-8 s la ESPALDA.
# El micro mas cercano a la zona sube mas: «dif ch0-ch1 por ventana» (dB) da la posicion sin depender del cronometraje exacto. Por defecto: 1-4 1-5 4-5 (los micros con respuesta en M3). Se ejecuta EN la tablet con e9a cargada.
set -u
PAIRS=${*:-1-4 1-5 4-5}; M3=${UKE_MIC_M3:-/usr/local/sbin/uke-mic-m3.sh}; OUT=/root/mic-m3/m4-$(date +%H%M%S).txt; : > "$OUT"
for p in $PAIRS; do
	echo "== SIGUIENTE: pareja $p (canal 0 = AMIC${p%-*}, canal 1 = AMIC${p#*-}) en 5 s: silencio, INFERIOR, SUPERIOR, ESPALDA"; sleep 5
	r=$("$M3" "dual-$p" 8 2>&1); echo "$r" | grep -E "GRABANDO|arecord rc|canal [01]|dif ch0|read error|Invalid" | cut -c1-260
	{ echo "== pareja $p"; echo "$r" | grep -E "arecord rc|canal [01]|dif ch0" | cut -c1-260; } >> "$OUT"
	echo "-- fin $p (oops=$(dmesg | grep -cE 'Oops|Unhandled context|BUG:'))"; sleep 10
done
echo "== RESUMEN ($OUT)"; cat "$OUT"
