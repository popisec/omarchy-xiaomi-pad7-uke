#!/bin/bash
# build-v8b.sh — kernel «v8b» (23-oct-2026) = v8a (build7 + initramfs v8a) + ouke8.config.delta BLOQUE A (PSI, MGLRU dormido, THP madvise)
# con RELEASE NUEVA 7.2.9-senemos.1.4054.3-ouke8 (cambia la ABI de task_struct/mm_struct/folio: los .ko viejos se rechazan por vermagic).
# Bloques B y C de la delta: NO (B = decision del dueno; DEBUG_INFO ademas no cabe en el disco del PC; C = ciclo propio).
# DESPRENDIDO (AGENTS.md regla 6): setsid nohup bash build/gates/build-v8b.sh >/dev/null 2>&1 &
# No flashea nada. build8 vive en build/kernel-pokes/ (ignorado por git). Compila Image.gz + dtbs + modulos y deja el tarball.
set -euo pipefail
R=/home/USUARIO/proyectos/omarchy-uke
D=$R/build/kernel-pokes/optim-ouke6
K=$D/linux-7.2.9
B7=$D/build7
B=$D/build8
CPIO=$D/v8a/uke-k34-fw-v8a-initramfs.cpio.gz
LV=-senemos.1.4054.3-ouke8
mkdir -p "$B"
exec >"$D/build8.log" 2>&1
echo "[build-v8b] inicio $(date -Is)"
[ "$(sha256sum "$CPIO" | cut -d' ' -f1)" = af355bb9e46df36ac969473bfdb4d29ded3c4f7e756521fd60bc31d1d5d21591 ] || { echo "cpio v8a con sha distinto"; exit 1; }
[ "$(clang --version | head -1)" = "clang version 23.1.3" ] || { echo "toolchain distinto de build7"; exit 1; }
export ARCH=arm64 LLVM=1 LLVM_IAS=1 MAKE=/usr/bin/make LOCALVERSION=$LV
export KBUILD_BUILD_USER=omarchy-uke KBUILD_BUILD_HOST=pc KBUILD_BUILD_VERSION=8
export KBUILD_BUILD_TIMESTAMP="2026-10-23 13:00:00 UTC"
cp "$B7/.config" "$B/.config"
"$K/scripts/config" --file "$B/.config" --set-str INITRAMFS_SOURCE "$CPIO" \
  --enable PSI --disable PSI_DEFAULT_DISABLED \
  --enable LRU_GEN --disable LRU_GEN_ENABLED --disable LRU_GEN_STATS \
  --disable TRANSPARENT_HUGEPAGE_ALWAYS --enable TRANSPARENT_HUGEPAGE_MADVISE
/usr/bin/make -C "$K" O="$B" olddefconfig
echo "[build-v8b] diff .config build7 -> build8:"
diff "$B7/.config" "$B/.config" > "$B/config-diff-build7.txt" || true
cat "$B/config-diff-build7.txt"
# gate: solo cambian los simbolos esperados (+ la dependencia automatica LRU_GEN_WALKS_MMU)
CH=$(grep -E '^[<>]' "$B/config-diff-build7.txt" | grep -oE 'CONFIG_[A-Z0-9_]+' | sort -u | tr '\n' ' ')
WANT="CONFIG_INITRAMFS_SOURCE CONFIG_LRU_GEN CONFIG_LRU_GEN_ENABLED CONFIG_LRU_GEN_STATS CONFIG_LRU_GEN_WALKS_MMU CONFIG_PSI CONFIG_PSI_DEFAULT_DISABLED CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS CONFIG_TRANSPARENT_HUGEPAGE_MADVISE "
[ "$CH" = "$WANT" ] || { echo "diff de .config inesperado: '$CH'"; exit 1; }
for l in CONFIG_PSI=y CONFIG_LRU_GEN=y CONFIG_TRANSPARENT_HUGEPAGE_MADVISE=y "# CONFIG_PSI_DEFAULT_DISABLED is not set" "# CONFIG_LRU_GEN_ENABLED is not set" "# CONFIG_MODVERSIONS is not set"; do
  grep -qxF "$l" "$B/.config" || { echo "falta '$l'"; exit 1; }; done
/usr/bin/make -C "$K" O="$B" -j14 Image.gz dtbs modules
KREL=$(/usr/bin/make -s -C "$K" O="$B" kernelrelease)
echo "[build-v8b] kernelrelease=$KREL"
[ "$KREL" = "7.2.9$LV" ] || { echo "release inesperada"; exit 1; }
rm -rf "$B/modinst"; /usr/bin/make -C "$K" O="$B" INSTALL_MOD_PATH="$B/modinst" INSTALL_MOD_STRIP=1 modules_install
rm -f "$B/modinst/lib/modules/$KREL/build" "$B/modinst/lib/modules/$KREL/source"
tar -C "$B/modinst" --owner=0 --group=0 --sort=name --mtime="2026-10-23 00:00:00 UTC" -cf - lib/modules | zstd -T8 -3 > "$B/modules-$KREL.tar.zst"
sha256sum "$B/arch/arm64/boot/Image" "$B/arch/arm64/boot/Image.gz" "$B/.config" "$B/modules-$KREL.tar.zst"
echo "[build-v8b] FIN OK $(date -Is)"
