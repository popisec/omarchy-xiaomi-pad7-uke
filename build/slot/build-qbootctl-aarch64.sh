#!/usr/bin/env bash
# build-qbootctl-aarch64.sh — receta reproducible del qbootctl aarch64 de build/slot/.
#
# QUÉ HACE. Descarga el tarball upstream linux-msm/qbootctl 0.2.2, verifica su sha256
# (el mismo que fija el PKGBUILD de AUR), ensambla un sysroot aarch64 SIN ROOT a partir
# de paquetes ALARM cacheados en build/rootfs/pkgs/files (+ descarga del gcc aarch64
# solo para sus crt/libgcc) y cross-compila con el clang+lld del PC.
#
# POR QUÉ ASÍ. El PC no tiene cross-gcc instalado y no hay sudo. El código es C
# portable (c_std=gnu11, sin asm específico de arquitectura, verificado por grep) y el
# meson.build solo pide linux/bsg.h: basta clang --target + sysroot + lld.
#
# SALIDA. build/slot/qbootctl-aarch64 (ELF aarch64, solo necesita libc.so.6).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
WORK=/tmp/opencode/slotq
SYSROOT=/tmp/opencode/aarch64-sysroot
VER=0.2.2
SHA=e66b361f86fac413f6a96974b4045a1fbc385f9eb6cee7fa8a26e0ca77c74a51
MIRROR=http://fl.us.mirror.archlinuxarm.org/aarch64

mkdir -p "$WORK" "$SYSROOT"
cd "$WORK"

[ -f qbootctl-$VER.tar.gz ] || \
  curl -sL "https://github.com/linux-msm/qbootctl/archive/refs/tags/$VER.tar.gz" \
    -o qbootctl-$VER.tar.gz --max-time 300
echo "$SHA  qbootctl-$VER.tar.gz" | sha256sum -c - || exit 1
[ -d qbootctl-$VER ] || tar xzf qbootctl-$VER.tar.gz

# Sysroot: glibc + headers + libgcc salen de la caché del proyecto (solo lectura).
SYSROOT_ABS="$(cd "$SYSROOT" && pwd)"
CACHE_ABS="$(cd "$SCRIPT_DIR/../rootfs/pkgs/files" && pwd)"
bsdtar -xf "$CACHE_ABS/glibc-2.43+r22+g8362e8ce10b2-2-aarch64.pkg.tar.xz" -C "$SYSROOT_ABS"
bsdtar -xf "$CACHE_ABS/linux-api-headers-7.2-1-aarch64.pkg.tar.xz" -C "$SYSROOT_ABS"
bsdtar -xf "$CACHE_ABS/libgcc-16.1.1+r12+g301eb08fa2c5-1-aarch64.pkg.tar.xz" -C "$SYSROOT_ABS" usr
# crtbeginS.o/crtendS.o/libgcc.a solo vienen en el paquete gcc completo (46 MB).
[ -f gcc-aarch64.pkg.tar.xz ] || \
  curl -sL "$MIRROR/core/gcc-16.1.1+r12+g301eb08fa2c5-1-aarch64.pkg.tar.xz" \
    -o gcc-aarch64.pkg.tar.xz --max-time 300
bsdtar -xf gcc-aarch64.pkg.tar.xz -C "$SYSROOT" usr/lib/gcc

cd qbootctl-$VER
clang --target=aarch64-linux-gnu --sysroot="$SYSROOT" -fuse-ld=lld \
  -O2 -Wall -std=gnu11 -o ../qbootctl-aarch64 \
  qbootctl.c bootctrl_impl.c gpt-utils.c ufs-bsg.c crc32.c || exit 1
file ../qbootctl-aarch64
llvm-readelf -d ../qbootctl-aarch64 | grep NEEDED
sha256sum ../qbootctl-aarch64
cp ../qbootctl-aarch64 .
echo "OK — copia build/slot/qbootctl-aarch64 con el sha de arriba si coincide."
