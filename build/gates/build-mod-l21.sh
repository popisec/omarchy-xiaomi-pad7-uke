#!/bin/bash
# build-mod-l21.sh — módulos pwrseq del L21 (el Image no los lleva: QCOM_WCN=m).
set -euo pipefail
R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
export MAKE=/usr/bin/make ARCH=arm64 LLVM=1
export KBUILD_BUILD_USER=uke KBUILD_BUILD_HOST=palawan
export KBUILD_BUILD_TIMESTAMP="Fri Oct 10 12:00:00 CEST 2026"
O=$R/build/kernel-pokes/k52L21-build
CC="ccache clang"; HOSTCC="ccache gcc"
cd "$R/build/kernel-pokes/k52-L16-tree"
$MAKE O="$O" -j12 CC="$CC" HOSTCC="$HOSTCC" modules
ls -la "$O/drivers/power/sequencing/"*.ko
