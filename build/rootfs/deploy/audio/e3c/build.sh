#!/bin/bash
# Compila la sonda contra el arbol de build ouke4 (sin modificarlo). Salida: ../out/uke_lpi_rd.ko
set -Eeuo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../../.." && pwd); KB=${KB:-$R/build/kernel-pokes/senemos-build}
S=$(mktemp -d); trap 'rm -rf "$S"' EXIT; cp "$HERE"/uke_lpi_rd.c "$HERE"/uke_lpi_io.c "$HERE"/Kbuild "$S/"
env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL MAKE=/usr/bin/make ARCH=arm64 LLVM=1 /usr/bin/make -C "$KB" M="$S" modules > "$S/make.log" 2>&1 || { cat "$S/make.log"; exit 1; }
[ -s "$S/uke_lpi_io.ko" ] && cp "$S/uke_lpi_io.ko" "$HERE/../out/" && [ -s "$S/uke_lpi_rd.ko" ] && [ "$S/uke_lpi_rd.ko" -nt "$S/uke_lpi_rd.c" ] || { echo "no se genero el .ko (make no-op?)"; exit 1; }
grep -Ei 'warning|error' "$S/make.log" | grep -v 'Entering\|Leaving\|se entra\|se sale' && { echo avisos; exit 1; } || true
cp "$S/uke_lpi_rd.ko" "$HERE/../out/"; modinfo -F vermagic "$HERE/../out/uke_lpi_rd.ko"; modinfo -F depends "$HERE/../out/uke_lpi_rd.ko"; sha256sum "$HERE/../out/uke_lpi_rd.ko"
