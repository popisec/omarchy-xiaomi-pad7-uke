#!/bin/bash
# Compila el modulo cargador de overlays de audio (E2) contra el arbol de build ouke3, sin modificarlo. Ver README.
set -Eeuo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../.." && pwd)
KB=${KB:-$R/build/kernel-pokes/senemos-ouke5/build}   # defecto = kernel EN MARCHA (ouke5); ouke4 (rollback): KB=…/senemos-build OUT=$HERE/out
OUT=${OUT:-$HERE/out-ouke5}   # .ko de salida (defecto out-ouke5; ouke4: OUT=$HERE/out)
mkdir -p "$OUT"
REL=$(cat "$KB/include/config/kernel.release" 2>/dev/null) || { echo "KB=$KB sin kernel.release: no es un arbol de build"; exit 1; }
[ -s "$HERE/out/uke-audio-e2-gpr.dtbo" ] || "$HERE/build.sh" --quick
S=$(mktemp -d); trap 'rm -rf "$S"' EXIT; mkdir "$S/blobs"
cp "$HERE"/module/* "$S/"; cp "$HERE"/out/uke-audio-e2-gpr.dtbo "$HERE"/out/uke-audio-e2b-fastrpc.dtbo "$HERE"/out/uke-audio-e2c-fastrpc-heap.dtbo "$HERE"/out/uke-audio-e2d-gpr-ports.dtbo "$HERE"/out/uke-audio-e3-lpi.dtbo "$HERE"/out/uke-audio-e4a-bedais.dtbo "$HERE"/out/uke-audio-e4b-dais.dtbo "$HERE"/out/uke-audio-e4c-card.dtbo "$HERE"/out/uke-audio-e7a-card-tdm.dtbo "$HERE"/out/uke-audio-e7b-card-tdm-pins.dtbo "$HERE"/out/uke-audio-e7-amps-i2c.dtbo "$HERE"/out/uke-audio-e8a-card-fs19xx.dtbo "$HERE"/out/uke-audio-e8b-card-fs19xx-pins.dtbo "$HERE"/out/uke-audio-e5-codec.dtbo "$HERE"/out/uke-audio-e9a-card-fs19xx-wcd-capture.dtbo "$S/blobs/"
env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL MAKE=/usr/bin/make ARCH=arm64 LLVM=1 UKE_OVL_DIR="$S/blobs" \
  /usr/bin/make -C "$KB" M="$S" modules > "$S/make.log" 2>&1 || { cat "$S/make.log"; exit 1; }
for m in uke_audio_e2 uke_audio_e2b uke_audio_e2c uke_audio_e2d uke_audio_e3 uke_audio_e4a uke_audio_e4b uke_audio_e4c uke_audio_e7a uke_audio_e7b uke_audio_e7i2c uke_audio_e8a uke_audio_e8b uke_audio_e5 uke_audio_e9a; do
  [ -s "$S/$m.ko" ] && [ "$S/$m.ko" -nt "$S/$m.c" ] || { echo "no se genero $m.ko (make no-op?)"; exit 1; }
done
grep -Ei 'warning|error' "$S/make.log" | grep -v 'Entering\|Leaving\|se entra\|se sale' && { echo "avisos"; exit 1; } || true
for m in uke_audio_e2 uke_audio_e2b uke_audio_e2c uke_audio_e2d uke_audio_e3 uke_audio_e4a uke_audio_e4b uke_audio_e4c uke_audio_e7a uke_audio_e7b uke_audio_e7i2c uke_audio_e8a uke_audio_e8b uke_audio_e5 uke_audio_e9a; do
  cp "$S/$m.ko" "$OUT/"
  [ "$(modinfo -F vermagic "$OUT/$m.ko" | cut -d" " -f1)" = "$REL" ] || { echo "ABORTADO: $m.ko vermagic != $REL (¿KB equivocado?)"; exit 1; }
  echo "$m: vermagic $(modinfo -F vermagic "$OUT/$m.ko") depends '$(modinfo -F depends "$OUT/$m.ko")'"; sha256sum "$OUT/$m.ko"
done
