#!/bin/bash
# build-v8a.sh — kernel «v8a» (23-oct-2026) = v7 (build7, release -ouke5) RE-ENLAZADO con otro initramfs embebido
# (uke-k34-fw-v8a-initramfs.cpio.gz de mkcpio-v8a.py). Nada mas cambia: misma .config salvo CONFIG_INITRAMFS_SOURCE,
# mismo arbol fuente, mismo toolchain (clang/lld 23.1.3), misma LOCALVERSION => mismos .ko (no se compilan modulos).
# Solo se reconstruyen usr/initramfs_data.o, init/version-timestamp.o (banner #8) y el enlace de vmlinux/Image.
# DESPRENDIDO (AGENTS.md regla 6): setsid nohup bash build/gates/build-v8a.sh >/dev/null 2>&1 &
# No flashea nada. build8a vive en build/kernel-pokes/ (ignorado por git).
set -euo pipefail
R=/home/USUARIO/proyectos/omarchy-uke
D=$R/build/kernel-pokes/optim-ouke6
K=$D/linux-7.2.9
B7=$D/build7
B=$D/build8a
CPIO=$D/v8a/uke-k34-fw-v8a-initramfs.cpio.gz
LV=-senemos.1.4054.3-ouke5
mkdir -p "$B"
exec >"$D/build8a.log" 2>&1
echo "[build-v8a] inicio $(date -Is)"
[ -f "$CPIO" ] || { echo "falta $CPIO (mkcpio-v8a.py)"; exit 1; }
[ "$(clang --version | head -1)" = "clang version 23.1.3" ] || { echo "toolchain distinto de build7"; exit 1; }
# copia del arbol de objetos de v7 SIN modinst ni tarball (no hacen falta: misma release, mismos .ko)
rsync -a --delete --exclude=/modinst --exclude='/modules-*.tar.zst' --exclude=/build.log "$B7"/ "$B"/
"$K/scripts/config" --file "$B/.config" --set-str INITRAMFS_SOURCE "$CPIO"
export ARCH=arm64 LLVM=1 LLVM_IAS=1 MAKE=/usr/bin/make LOCALVERSION=$LV
export KBUILD_BUILD_USER=omarchy-uke KBUILD_BUILD_HOST=pc KBUILD_BUILD_VERSION=8
export KBUILD_BUILD_TIMESTAMP="2026-10-23 12:00:00 UTC"
/usr/bin/make -C "$K" O="$B" olddefconfig
/usr/bin/make -C "$K" O="$B" -j14 Image.gz
KREL=$(/usr/bin/make -s -C "$K" O="$B" kernelrelease)
echo "[build-v8a] kernelrelease=$KREL"
[ "$KREL" = "7.2.9$LV" ] || { echo "release inesperada"; exit 1; }
echo "[build-v8a] diff .config build7 -> build8a:"
diff "$B7/.config" "$B/.config" || true
sha256sum "$B/arch/arm64/boot/Image" "$B/arch/arm64/boot/Image.gz" "$B/.config"
echo "[build-v8a] FIN OK $(date -Is)"
