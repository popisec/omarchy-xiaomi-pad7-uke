#!/bin/bash
# bench.sh — mide los motores de dictado EN LA TABLET con los wav de prueba (MLS español test, 8 frases, 113 s).
# Para cada configuracion: tiempo de proceso por frase (RTF), WER (wer.py, en el PC) y pico de RAM (ru_maxrss).
# Nucleos SM7675: 0-2 A520 (1,9 GHz), 3-6 A720 (2,6 GHz), 7 X4 (2,8 GHz).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$HERE/../../../.." && pwd)
S() { timeout 1800 ssh -i "$R/build/rootfs/uke-arch-root" -o BatchMode=yes -o ConnectTimeout=8 "${UKE_HOST:-root@uke}" "$@"; }
B=/usr/local/share/uke/dictado
T=/root/dictado-build/test
O="$HERE/out"; mkdir -p "$O"
REF=${MODELOS:-$HOME/backups/uke-dictado-modelos}/test/ref.tsv
# ejecuta un comando en la tablet y deja en stderr "rss_mb=<pico>"
RUN='python3 -I -c "import resource,subprocess,sys; subprocess.run(sys.argv[1], shell=True); print(\"rss_mb=%d\" % (resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss//1024), file=sys.stderr)"'

par() {   # nombre hilos [taskset]
	S "$RUN '${3:+taskset -c $3 }$B/bin/uke-asr $B/modelos/parakeet $2 $T/*.wav'" > "$O/hip-$1.tsv" 2> "$O/err-$1.txt"
	echo "== $1  ($(tr '\n' ' ' < "$O/err-$1.txt"))"; python3 -I "$HERE/wer.py" "$REF" "$O/hip-$1.tsv" | tail -1
}
whi() {   # nombre modelo hilos [taskset]
	S "for w in $T/*.wav; do n=\$(basename \$w .wav); a=\$(date +%s.%N); x=\$(${4:+taskset -c $4 }$B/bin/whisper-cli -m $B/modelos/$2 -l es -t $3 -nt -np --prompt 'Hola, ¿qué tal? Esto es un dictado en español.' -f \$w 2>/dev/null | tr '\n' ' '); b=\$(date +%s.%N); printf '%s\t%s\t%s\n' \$n \$(awk \"BEGIN{print \$b-\$a}\") \"\$x\"; done" > "$O/hip-$1.tsv"
	S "$RUN '${4:+taskset -c $4 }$B/bin/whisper-cli -m $B/modelos/$2 -l es -t $3 -nt -np -f $T/mls000.wav >/dev/null 2>&1'" 2> "$O/err-$1.txt"
	echo "== $1  ($(tr '\n' ' ' < "$O/err-$1.txt"))"; python3 -I "$HERE/wer.py" "$REF" "$O/hip-$1.tsv" | tail -1
}
case "${1:-all}" in
parakeet|all)
	par parakeet-t4-grandes 4 3-6
	par parakeet-t5-grandes 5 3-7
	par parakeet-t8 8
	par parakeet-t6 6 ;;&
whisper|all)
	S "[ -x $B/bin/whisper-cli ]" || { echo "sin whisper-cli (deploy.sh whisper)"; exit 0; }
	whi whisper-small-q5-t5 ggml-small-q5_1.bin 5 3-7
	whi whisper-turbo-q5-t5 ggml-large-v3-turbo-q5_0.bin 5 3-7
	whi whisper-base-q5-t5 ggml-base-q5_1.bin 5 3-7 ;;
esac
