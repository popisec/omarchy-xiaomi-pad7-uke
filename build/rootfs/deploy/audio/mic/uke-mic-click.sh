#!/bin/bash
# uke-mic-click.sh — M7: mide el CHASQUIDO de arranque de la captura (primeros ~0,5 s a -19…-28 dBFS sobre un suelo de -40…-50) y prueba variantes de hardware para reducirlo. BORRADOR del PC (21-oct-2026), NO probado.
# Se ejecuta EN la tablet (root) con e9a cargada. Para cada variante: 3 capturas de 2 s por hw:UKE,2 (2 canales S16/48 kHz) con la ruta amic1 + el ajuste, y `uke-mic-rms.py --click` (ventanas de 50 ms:
# delta = pico de los primeros 0,5 s − suelo, y ms hasta estabilizarse). Variantes: base; TX0 MODE ADC_LP / ADC_HIFI; ADC1 Volume 4 / 14; TX_DEC0 Volume 84; y «seguidas» (2.ª captura 0,2 s despues de la 1.ª, ¿el
# chasquido solo ocurre con el ADC frio?). Al final restaura la ruta amic1 por defecto. Sin hablar ni golpear: silencio en la sala. Salida: /root/mic-m3/click-HHMMSS.txt
set -u
R=${UKE_MIC_ROUTE:-/usr/local/sbin/uke-mic-route.sh}; RMS=${UKE_MIC_RMS:-/usr/local/sbin/uke-mic-rms.py}; OUT=/root/mic-m3/click-$(date +%H%M%S).txt; mkdir -p /root/mic-m3; : > "$OUT"
cap() { timeout 10 arecord -D hw:UKE,2 -f S16_LE -r 48000 -c 2 -d 2 "$1" >/dev/null 2>&1; }
run() { # run NOMBRE [cset...]
	local n=$1; shift
	"$R" --apply amic1 >/dev/null 2>&1
	while [ $# -ge 2 ]; do amixer -c UKE cset name="$1" "$2" >/dev/null 2>&1 || echo "(no existe $1)"; shift 2; done
	local i f
	for i in 1 2 3; do f=/tmp/click-$n-$i.wav; cap "$f"; echo "$n #$i: $(python3 -I "$RMS" --click "$f" 2>&1 | grep '^click canal 0' | cut -c1-200)" | tee -a "$OUT"; sleep 6; done
}
echo "== chasquido de arranque (silencio en la sala)" | tee -a "$OUT"
run base
run TX0_LP "TX0 MODE" ADC_LP
run TX0_HIFI "TX0 MODE" ADC_HIFI
run ADC1_vol4 "ADC1 Volume" 4
run ADC1_vol14 "ADC1 Volume" 14
run DEC0_vol84 "TX_DEC0 Volume" 84
"$R" --apply amic1 >/dev/null 2>&1
echo "== seguidas (2.ª captura 0,2 s despues de la 1.ª)" | tee -a "$OUT"
for i in 1 2 3; do cap /tmp/click-s1.wav; sleep 0.2; cap /tmp/click-s2.wav; echo "seguidas #$i  1.ª: $(python3 -I "$RMS" --click /tmp/click-s1.wav | grep '^click canal 0' | cut -c1-140)  2.ª: $(python3 -I "$RMS" --click /tmp/click-s2.wav | grep '^click canal 0' | cut -c1-140)" | tee -a "$OUT"; sleep 6; done
"$R" --apply amic1 >/dev/null 2>&1; echo "ruta por defecto amic1 restaurada; resumen en $OUT"
echo "oops=$(dmesg | grep -cE 'Oops|Unhandled context|BUG:')"
