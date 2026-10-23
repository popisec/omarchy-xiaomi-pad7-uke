#!/bin/bash
# m3-guion.sh [OPCIONES...] — M3 en lote: para cada ruta avisa, espera 5 s, graba 8 s con el guion del dueño y resume. Se ejecuta EN la tablet (root) con la tarjeta e9a cargada.
# GUION DEL DUEÑO por grabacion (8 s): 0-2 s SILENCIO; 2-4 s golpea el borde INFERIOR; 4-6 s el borde SUPERIOR; 6-8 s la ESPALDA (junto a la camara trasera). Pausa de 10 s entre rutas.
# Por defecto: amic3 amic5 amic2 (rutas mainline: ADC1 + SWR_MIC0 con CH1_AMICn; las rutas «vendor» dan EIO en M3). Resumen final: canal 0 por ruta.
set -u
LIST=${*:-amic3 amic5 amic2}; M3=${UKE_MIC_M3:-/usr/local/sbin/uke-mic-m3.sh}; OUT=/root/mic-m3/resumen-$(date +%H%M%S).txt; : > "$OUT"
for o in $LIST; do
	echo "== SIGUIENTE: $o en 5 s (silencio, INFERIOR, SUPERIOR, ESPALDA)"; sleep 5
	r=$("$M3" "$o" 8 2>&1); echo "$r" | grep -E "GRABANDO|arecord rc|canal 0|read error|Invalid" | cut -c1-230
	echo "$o: $(echo "$r" | grep -E "arecord rc" | tr -d '\n') | $(echo "$r" | grep -E "canal 0" | sed 's/.*RMS/RMS/' | cut -c1-200)" >> "$OUT"
	echo "-- fin $o (oops=$(dmesg | grep -cE 'Oops|Unhandled context|BUG:'))"; sleep 10
done
echo "== RESUMEN ($OUT)"; cat "$OUT"
