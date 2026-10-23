#!/bin/bash
# Compila uke_fs19xx.ko contra el arbol ouke4 (senemos-build) sin modificarlo. Salida: ../out/uke_fs19xx.ko
set -Eeuo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); A=$(cd "$HERE/.." && pwd); R=$(cd "$A/../../../.." && pwd)
KB=${KB:-$R/build/kernel-pokes/senemos-ouke5/build}
OUT=${OUT:-$A/out-ouke5}
REL=$(cat "$KB/include/config/kernel.release" 2>/dev/null) || { echo "KB=$KB sin kernel.release"; exit 1; }
S=$(mktemp -d); trap 'rm -rf "$S"' EXIT
cp "$HERE/uke_fs19xx.c" "$HERE/Kbuild" "$S/"
env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL MAKE=/usr/bin/make ARCH=arm64 LLVM=1 /usr/bin/make -C "$KB" M="$S" modules > "$S/make.log" 2>&1 || { cat "$S/make.log"; exit 1; }
[ -s "$S/uke_fs19xx.ko" ] && [ "$S/uke_fs19xx.ko" -nt "$S/uke_fs19xx.c" ] || { echo "no se genero uke_fs19xx.ko (make no-op?)"; exit 1; }
grep -Ei 'warning|error' "$S/make.log" | grep -v 'Entering\|Leaving\|se entra\|se sale' && { echo avisos; exit 1; } || true
mkdir -p "$OUT"; cp "$S/uke_fs19xx.ko" "$OUT/"
K=$OUT/uke_fs19xx.ko
[ "$(modinfo -F vermagic "$K" | cut -d" " -f1)" = "$REL" ] || { echo "ABORTADO: uke_fs19xx vermagic != $REL"; exit 1; }
echo "uke_fs19xx: vermagic $(modinfo -F vermagic "$K" | cut -d' ' -f1); depends '$(modinfo -F depends "$K")'"
modinfo -F parm "$K" | cut -c1-100
sha256sum "$K"
