#!/bin/bash
# build-senemos-v4.sh — 18-oct-2026. Build ouke4 = ouke3 + parches 0002+0004 (arm-smmu-qcom.c; deltas-omarchy-v4.sh)
# (deltas-omarchy-v4.sh; informe build/gates/revision/GPU-SENEMOS-20261017.md) + MODULOS:
#   Image.gz + dtbs + modules, luego modules_install -> senemos-build/modroot y el tarball
#   senemos-build/modules-<release>.tar.zst (+ .sha256). DESPRENDIDO (regla 6: setsid nohup,
#   MAKE/ARCH explicitos). Uso:
#     bash deltas-omarchy-v4.sh   # antes, una vez
#     setsid nohup bash build-senemos-v4.sh > /dev/null 2>&1 &   (log en build/logs/build-senemos-v4.log)
set -euo pipefail
R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
K=$R/build/kernel-pokes/senemos-7.2.9/linux-7.2.9
B=$R/build/kernel-pokes/senemos-build
LOG=$R/build/logs/build-senemos-v4.log
LV=-senemos.1.4054.3-ouke4
REL=7.2.9$LV
JOBS=${JOBS:-12}
mkdir -p "$(dirname "$LOG")"
exec >"$LOG" 2>&1
echo "[build-senemos-v4] inicio $(date -Is) jobs=$JOBS clang=$(clang --version | head -1)"
export ARCH=arm64 LLVM=1 LLVM_IAS=1 MAKE=/usr/bin/make
export KBUILD_BUILD_USER=omarchy-uke KBUILD_BUILD_HOST=pc KBUILD_BUILD_VERSION=4
export KBUILD_BUILD_TIMESTAMP="2026-10-18 12:30:00 UTC"
cmp "$B/.config" "$B/config-senemos-ouke4" || { echo "[build-senemos-v4] .config != config-senemos-ouke4"; exit 1; }
TC='^[<>] CONFIG_(CC_VERSION_TEXT|CLANG_VERSION|AS_VERSION|LLD_VERSION|RUSTC_VERSION|RUSTC_LLVM_VERSION)='   # toolchain 23.1.1 -> 23.1.3
cmp "$B/config-senemos-ouke3" "$B/config-senemos-ouke4" || { echo "[build-senemos-v4] ouke4 != ouke3"; exit 1; }
grep -q "sid == 0x401007" "$K/drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c" || { echo "[build-senemos-v4] faltan los parches 0002+0004 (bash deltas-omarchy-v4.sh)"; exit 1; }
/usr/bin/make -C "$K" O="$B" LOCALVERSION="$LV" olddefconfig
cmp "$B/.config" "$B/config-senemos-ouke4" || { echo "[build-senemos-v4] olddefconfig cambio la config"; exit 1; }
/usr/bin/make -C "$K" O="$B" LOCALVERSION="$LV" -j"$JOBS" Image.gz dtbs
KREL=$(/usr/bin/make -s -C "$K" O="$B" LOCALVERSION="$LV" kernelrelease)
echo "[build-senemos-v4] kernelrelease=$KREL"
[ "$KREL" = "$REL" ] || { echo "[build-senemos-v4] kernelrelease inesperado"; exit 1; }
ls -la "$B/arch/arm64/boot/Image" "$B/arch/arm64/boot/Image.gz"
sha256sum "$B/arch/arm64/boot/Image" "$B/arch/arm64/boot/Image.gz" "$B/.config"
echo "[build-senemos-v4] Image.gz listo $(date -Is); empiezan los modulos"
/usr/bin/make -C "$K" O="$B" LOCALVERSION="$LV" -j"$JOBS" modules
echo "[build-senemos-v4] modulos compilados $(date -Is): $(find "$B" -name '*.ko' | wc -l) .ko"
rm -rf "$B/modroot"
/usr/bin/make -C "$K" O="$B" LOCALVERSION="$LV" modules_install INSTALL_MOD_PATH="$B/modroot"
# 'build' y 'source' apuntan al arbol del PC: fuera del paquete para la tablet
rm -f "$B/modroot/lib/modules/$REL/build" "$B/modroot/lib/modules/$REL/source"
ls "$B/modroot/lib/modules/"
[ -d "$B/modroot/lib/modules/$REL" ] || { echo "[build-senemos-v4] no hay lib/modules/$REL"; exit 1; }
depmod -b "$B/modroot" -a "$REL" -F "$B/System.map"   # idempotente; deja modules.dep/alias/symbols
TB="$B/modules-$REL.tar.zst"
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='2026-10-18 12:30:00 UTC' \
    -C "$B/modroot" -cf - lib/modules | zstd -19 -T0 -q -f -o "$TB"
( cd "$B" && sha256sum "$(basename "$TB")" > "$(basename "$TB").sha256" )
echo "[build-senemos-v4] tarball: $(ls -la "$TB")"
cat "$TB.sha256"
echo "[build-senemos-v4] FIN OK $(date -Is)"
