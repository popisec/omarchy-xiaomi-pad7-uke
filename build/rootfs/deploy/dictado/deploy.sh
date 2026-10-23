#!/bin/bash
# deploy.sh — dictado por voz OFFLINE para el teclado en pantalla de la uke (22-oct-2026).
#   apply     copia sherpa-onnx (libs aarch64) + modelo Parakeet TDT 0.6B v3 int8, compila uke-asr en la tablet,
#             instala /usr/local/bin/uke-dictar y /etc/uke/dictado.conf (no toca el micro ni PipeWire)
#   whisper   (opcional, para comparar) compila whisper.cpp en la tablet y copia los modelos ggml
#   bench     WER y RTF de los motores con los wav de prueba (MLS español, test) -> out/
#   status    lo instalado
#   revert    borra /usr/local/share/uke/dictado, /usr/local/bin/uke-dictar y /etc/uke/dictado.conf
# Los modelos y binarios de terceros NO van al repo: viven en ~/backups/uke-dictado-modelos (SHA256SUMS).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$HERE/../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}
HOST=${UKE_HOST:-root@uke}
M=${MODELOS:-$HOME/backups/uke-dictado-modelos}
S() { timeout "${T:-900}" ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 "$HOST" "$@"; }
B=/usr/local/share/uke/dictado
SHERPA=sherpa-onnx-v1.13.8-linux-aarch64-shared-cpu

case "${1:-}" in
apply)
	(cd "$M" && sha256sum -c --quiet --ignore-missing SHA256SUMS) || { echo "sha256 de los modelos NO coincide"; exit 1; }
	S "install -d $B/bin $B/lib $B/modelos/parakeet /etc/uke /root/dictado-build"
	# libs de sherpa-onnx (solo las .so: los binarios de ejemplo no hacen falta)
	S "tar -xj -C /root/dictado-build" < "$M/$SHERPA.tar.bz2"
	S "cp -a /root/dictado-build/$SHERPA/lib/*.so $B/lib/"
	# modelo Parakeet (encoder 622 MB + decoder + joiner + tokens)
	S "tar -xj -C $B/modelos/parakeet --strip-components=1 --wildcards '*/encoder.int8.onnx' '*/decoder.int8.onnx' '*/joiner.int8.onnx' '*/tokens.txt'" < "$M/parakeet-v3-int8.tar.bz2"
	# uke-asr (C, contra la API C de sherpa-onnx v1.13.8)
	S "cat > /root/dictado-build/c-api.h" < "$M/c-api.h"
	S "cat > /root/dictado-build/uke-asr.c" < "$HERE/uke-asr.c"
	S "cd /root/dictado-build && cc -O2 -Wall -Wextra -o $B/bin/uke-asr uke-asr.c -I. -L$B/lib -lsherpa-onnx-c-api -Wl,-rpath,$B/lib && echo uke-asr compilado"
	S "install -m 755 /dev/stdin /usr/local/bin/uke-dictar" < "$HERE/uke-dictar"
	S "[ -e /etc/uke/dictado.conf ] || install -m 644 /dev/stdin /etc/uke/dictado.conf" < "$HERE/dictado.conf"
	S "chmod -R a+rX $B; ls -la $B/bin $B/modelos/parakeet; du -sh $B" ;;
whisper)
	S "install -d $B/bin $B/modelos /root/dictado-build"
	S "rm -rf /root/dictado-build/whisper.cpp-master; tar -xz -C /root/dictado-build" < "$M/whisper.cpp-master.tar.gz"
	S "cd /root/dictado-build/whisper.cpp-master && cmake -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF -DGGML_NATIVE=ON >/root/dictado-build/whisper-cmake.log 2>&1 && cmake --build build -j8 --target whisper-cli >/root/dictado-build/whisper-build.log 2>&1 && install -m 755 build/bin/whisper-cli $B/bin/ && echo whisper-cli OK || tail -20 /root/dictado-build/whisper-build.log"
	for f in ggml-small-q5_1.bin ggml-large-v3-turbo-q5_0.bin ggml-base-q5_1.bin; do
		S "[ -s $B/modelos/$f ] || cat > $B/modelos/$f" < "$M/$f"
	done
	S "chmod -R a+rX $B; ls -la $B/modelos" ;;
bench)
	mkdir -p "$HERE/out"
	S "install -d /root/dictado-build/test"
	tar -C "$M/test" -cf - . | S "tar -x -C /root/dictado-build/test"
	bash "$HERE/bench.sh" ;;
status)
	S "ls -la $B/bin $B/modelos /usr/local/bin/uke-dictar /etc/uke/dictado.conf; cat /etc/uke/dictado.conf; du -sh $B" ;;
revert)
	S "rm -rf $B /usr/local/bin/uke-dictar /etc/uke/dictado.conf; echo revertido (el plugin del teclado sigue con el boton, que dara error)" ;;
*) sed -n '2,10p' "$0"; exit 2 ;;
esac
