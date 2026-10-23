#!/bin/bash
# Compila la sonda contra el arbol de build ouke4 (sin modificarlo). Salida: ../out/uke_spfcore_probe.ko
set -Eeuo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../../.." && pwd); KB=${KB:-$R/build/kernel-pokes/senemos-build}
S=$(mktemp -d); trap 'rm -rf "$S"' EXIT; cp "$HERE"/uke_spfcore_probe.c "$HERE"/Kbuild "$S/"
env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL MAKE=/usr/bin/make ARCH=arm64 LLVM=1 /usr/bin/make -C "$KB" M="$S" modules > "$S/make.log" 2>&1 || { cat "$S/make.log"; exit 1; }
[ -s "$S/uke_spfcore_probe.ko" ] && [ "$S/uke_spfcore_probe.ko" -nt "$S/uke_spfcore_probe.c" ] || { echo "no se genero el .ko (make no-op?)"; exit 1; }
grep -Ei 'warning|error' "$S/make.log" | grep -v 'Entering\|Leaving\|se entra\|se sale' && { echo avisos; exit 1; } || true
cp "$S/uke_spfcore_probe.ko" "$HERE/../out/"; modinfo -F vermagic "$HERE/../out/uke_spfcore_probe.ko"; modinfo -F depends "$HERE/../out/uke_spfcore_probe.ko"; sha256sum "$HERE/../out/uke_spfcore_probe.ko"
