#!/bin/bash
# uke-mic-auto.sh [-p AB] [-n RAFAGAS=3] [-s "7 9 11 13"] [-d SALIDA]  — M6: mapa de micros con los 4 altavoces como FUENTES PUNTUALES, sin intervencion humana.
# Se ejecuta EN la tablet (root), tarjeta e9a cargada, SIN nadie hablando ni tocandola (silencio de sala). Por cada escena de altavoz (FS19XX Scene 7/9/11/13 = TL/TR/BL/BR, INFERIDO):
#   fija la escena (con el PCM de altavoz parado), aplica la ruta dual-A-B, arranca arecord (hw:UKE,2, S16/48k/2ch), reproduce la secuencia de chirps por uke-speakers,
#   y analiza con uke_chirp.py (retardo inter-canal, ratio, ruido, SNR, respuesta, HD2/HD3). Al final: escena 0, ruta --off. Resultado en SALIDA/resumen.txt
# Requisitos (la orden del dueño debe cubrir TODO esto): altavoces a nivel bajo (uke-nivel.sh 1 = -18 dBFS de cadena; el chirp va a -18 dBFS => muy bajo), cargador, vigia, doble captura (dmesg -w),
# dmesg -n 7, `sync` al final. Un solo lector de ACM. NO se usa ningun PCM mas que hw:UKE,0 (via PipeWire) y hw:UKE,2. Duracion total ~ 4 escenas x (7+8*N/3) s ~ 2 min.
# Entorno: UKE_ROUTE (def /usr/local/sbin/uke-mic-route.sh)  UKE_PY (def python3)  UKE_CHIRP (def junto al script)  UKE_PLAY (def: runuser -u omarchy -- pw-play --target uke-speakers)  UKE_DRY=1 -> solo imprime.
set -u
PAIR=1-4; NB=3; SC="7 9 11 13"; HERE=$(cd "$(dirname "$0")" && pwd); OUT=/root/mic-auto/$(date +%Y%m%d-%H%M%S)
while getopts "p:n:s:d:" o; do case $o in p) PAIR=$OPTARG;; n) NB=$OPTARG;; s) SC=$OPTARG;; d) OUT=$OPTARG;; *) exit 1;; esac; done
R=${UKE_ROUTE:-/usr/local/sbin/uke-mic-route.sh}; PY=${UKE_PY:-python3}; CH=${UKE_CHIRP:-$HERE/uke_chirp.py}
PLAY=${UKE_PLAY:-runuser -u omarchy -- env XDG_RUNTIME_DIR=/run/user/$(id -u omarchy) pw-play --target uke-speakers}
run() { if [ "${UKE_DRY:-0} " = "1 " ]; then echo "[dry] $*"; else "$@"; fi; }
mkdir -p "$OUT"; dmesg -n 7 2>/dev/null
$PY -I "$CH" gen "$OUT/seq.wav" --bursts "$NB" --amp -18 --out-json "$OUT/meta.json" || exit 1
TOT=$($PY -I -c "import json;print(json.load(open('$OUT/meta.json'))['total_s'])")
[ "${UKE_DRY:-0}" = "1" ] || [ -r "$OUT/seq.wav" ] || exit 1
# linea base de silencio (ruido propio sin altavoz): 4 s
run "$R" --apply "dual-$PAIR" | grep -c ' ok ' | sed 's/^/ruta dual-'"$PAIR"' campos ok: /'
echo "== silencio (4 s)"; run timeout 10 arecord -D hw:UKE,2 -f S16_LE -r 48000 -c 2 -d 4 "$OUT/silencio.wav" 2>&1 | tail -1
: > "$OUT/resumen.txt"
for S in $SC; do
	echo "== escena $S"
	run amixer -c UKE cset name='FS19XX Scene' "$S" >/dev/null     # solo con el PCM de altavoz parado
	sleep 1
	run timeout $((${TOT%.*} + 8)) arecord -D hw:UKE,2 -f S16_LE -r 48000 -c 2 -d $((${TOT%.*} + 3)) "$OUT/escena$S.wav" 2>"$OUT/arecord$S.err" &
	AP=$!; sleep 0.5
	run timeout $((${TOT%.*} + 10)) $PLAY "$OUT/seq.wav"
	wait $AP; echo "arecord rc=$?"
	if [ "${UKE_DRY:-0}" != "1" ]; then
		$PY -I "$CH" analyze "$OUT/escena$S.wav" --meta "$OUT/meta.json" > "$OUT/escena$S.json" 2>"$OUT/analyze$S.err" || echo "analisis FALLO escena $S"
		$PY -I -c "
import json,sys;r=json.load(open('$OUT/escena$S.json'));i=r['inter_channel'];c=r['channels']
print('escena $S | g0 %.1f g1 %.1f dB | ch0-ch1 %.2f dB | dt(ch1-ch0) %.2f muestras (MF) %.2f (PHAT) = %.0f mm | SNR %.0f/%.0f dB | ruido %.0f/%.0f dBFS | HD2 %.0f/%.0f dB'%(c[0]['gain_db_mean'],c[1]['gain_db_mean'],i['ratio_db_ch0_minus_ch1'],i['delay_samples_mean'],i['delay_samples_gccphat'],i['delay_mm'],c[0]['snr_db'],c[1]['snr_db'],c[0]['noise_dbfs'],c[1]['noise_dbfs'],c[0]['hd2_db'],c[1]['hd2_db']))" | tee -a "$OUT/resumen.txt"
	fi
	sleep 2
done
run amixer -c UKE cset name='FS19XX Scene' 0 >/dev/null
run "$R" --off | grep -c ok | sed 's/^/rutas desactivadas: /'
sync; echo "oops=$(dmesg | grep -cE 'Oops|Unhandled context|BUG:') ; resumen en $OUT/resumen.txt"
