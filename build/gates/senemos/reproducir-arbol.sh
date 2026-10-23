#!/usr/bin/env bash
# reproducir-arbol.sh — reconstruye el árbol fuente del kernel del port.
#
# QUÉ HACE. Reproduce A MANO, en el mismo orden, lo que hacen los scripts de
# preparación del upstream, sobre el tarball oficial de kernel.org:
#
#   packaging/senemos-uke-linux-kernel-mainline.spec  (%prep: 44 parches de patches/7.2.9/series)
#   packaging/native/prepare.sh, que llama a:
#     src/boot/prepare-abl-source.sh        (patches/boot/0001 con 2 --exclude, uke-abl.c,
#                                            fdt_check.c, wrappers lib/fdt_*.c, overlays UFS/USB)
#     src/display/prepare-source.sh         (display/7.2.10/0001, 0003, 0004, 0006, 0007..0016,
#                                            0018..0034 — 0017 EXCLUIDO por ellos — + copia de fuentes)
#     src/display/prepare-native-abl-source.sh 42 (0002 + 0005, uke-abl-native.h, overlay 60 Hz)
#   y finalmente el overlay "oem-modes" (7 modos, 120 Hz preferido) que sustituye al de 60 Hz.
#
# NO ejecuta ningún script del upstream: replica sus pasos a mano, con el
# sha256 de cada fichero comprobado contra su propio manifiesto
# (manifests/linux-7.2.9.json). Es la misma precautions que se took al
# inspeccionar el clon: no ejecutar código de terceros sin revisarlo.
#
# DE DÓNDE SALE CADA COSA (todo público y verificable):
#   - el tarball del kernel: https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.9.tar.xz
#     (oficial y firmado; su sha256 está en el manifiesto del upstream)
#   - los parches y las fuentes: https://github.com/MCC45TR/senemos-uke-kernel-mainline
#     (MIT), commit 43e4036e
#
# DESPUÉS hay que aplicar los parches PROPIOS del proyecto (que viven en el repo):
#   bash build/rootfs/deploy/audio/kernel/deltas-omarchy-v4.sh
#
# USO:
#   bash build/gates/senemos/reproducir-arbol.sh [--dest DIR]
#
# ENTORNO:
#   SENEMOS_UPSTREAM  ruta a un clon ya hecho del upstream (si no, se clona)
#   SENEMOS_COMMIT    commit del upstream (por defecto 43e4036e)
#   SENEMOS_SRC_TAR   tarball linux-7.2.9.tar.xz (si no, se descarga)
#
# Solo usa: tar, git, curl, install/cp, cpp, dtc, od, sed, sha256sum, fdtdump, jq.
set -Eeuo pipefail

R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
W="${SENEMOS_WORK:-$R/build/kernel-pokes/senemos-7.2.9}"
K="$W/linux-7.2.9"
GEN="$K/native-generated"
DL="$W/dl"
TAR="$DL/linux-7.2.9.tar.xz"
UPSTREAM_URL="https://github.com/MCC45TR/senemos-uke-kernel-mainline.git"
UPSTREAM_COMMIT="${SENEMOS_COMMIT:-43e4036e}"
EXT="${SENEMOS_UPSTREAM:-$W/ext-senemos}"
SRC_URL="https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.9.tar.xz"
SIGN_URL="https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.9.tar.sign"
# Clave de firma de las releases estables de Linux (Greg Kroah-Hartman).
LINUX_KEY="${LINUX_KEY:-647F28654894E3BD457199BE38DBBDC86092693E}"

# el destino se puede cambiar con --dest
while [ $# -gt 0 ]; do
	case "$1" in
	--dest)
		W="$2"
		K="$W/linux-7.2.9"
		GEN="$K/native-generated"
		DL="$W/dl"
		TAR="$DL/linux-7.2.9.tar.xz"
		EXT="${SENEMOS_UPSTREAM:-$W/ext-senemos}"
		shift 2 ;;
	*) echo "uso: $0 [--dest DIR]" >&2; exit 2 ;;
	esac
done

# El destino tiene que ser ABSOLUTO: los parches se aplican con
# "git -C $K apply $K/senemos-adaptation/patches/...", y git resuelve esa ruta
# desde $K. Con un --dest relativo, la ruta se resolvia dos veces y no
# encontraba ningun parche.
mkdir -p "$W"
W="$(cd "$W" && pwd)"
K="$W/linux-7.2.9"
GEN="$K/native-generated"
DL="$W/dl"
TAR="$DL/linux-7.2.9.tar.xz"
EXT="${SENEMOS_UPSTREAM:-$W/ext-senemos}"

say() { printf '[reproducir] %s\n' "$*"; }
ap() { # git apply con --check previo, igual que sus scripts
	local p=$1; shift
	git -C "$K" apply --check "$@" "$p"
	git -C "$K" apply "$@" "$p"
	say "  aplicado limpio: ${p#$EXT/}"
}

# ---------------------------------------------------------------- upstream --

mkdir -p "$W" "$DL"
if [ ! -d "$EXT/.git" ]; then
	say "clonando el upstream $UPSTREAM_COMMIT (puede tardar)"
	git clone -q "$UPSTREAM_URL" "$EXT"
fi
if ! git -C "$EXT" cat-file -e "$UPSTREAM_COMMIT^{commit}" 2>/dev/null; then
	say "el commit $UPSTREAM_COMMIT no esta en el clon; descargando el historico"
	git -C "$EXT" fetch -q --unshallow origin 2>/dev/null || git -C "$EXT" fetch -q origin
fi
git -C "$EXT" checkout -q "$UPSTREAM_COMMIT"
say "upstream en $UPSTREAM_COMMIT ($(git -C "$EXT" rev-parse --short HEAD))"

# ------------------------------------------------------------------ tarball --

LOCK="$EXT/manifests/linux-7.2.9.json"
[ -f "$LOCK" ] || { say "falta el manifiesto $LOCK"; exit 1; }
WANT_TAR=$(jq -r '.source_sha256' "$LOCK")
say "sha del tarball segun el manifiesto del upstream: $WANT_TAR"

if [ ! -f "$TAR" ]; then
	say "descargando el tarball oficial de kernel.org (~160 MB)"
	curl -fL --retry 3 -o "$TAR" "$SRC_URL"
	curl -fL --retry 3 -o "$TAR.sign" "$SIGN_URL" || true
fi
[[ $(sha256sum "$TAR" | cut -d' ' -f1) == "$WANT_TAR" ]] || { say "sha del tarball MAL"; exit 1; }
say "sha del tarball OK"

# La FIRMA: la de kernel.org firma el .tar SIN comprimir, asi que se verifica
# sobre el flujo descomprimido. Sin gpg la comprobacion del sha basta (el sha
# esta en el manifiesto del upstream y en las sums de kernel.org), pero si hay
# gpg y la clave, se verifica tambien la firma.
# La firma: kernel.org firma el .tar SIN comprimir, asi que se verifica sobre
# el flujo descomprimido. La clave de las releases estables la firma Greg
# Kroah-Hartman (no Linus). El servidor de keys.openpgp.org sirve la clave
# SIN UID, que gpg rechaza, asi que va el de keyserver.ubuntu.com.
if command -v gpg >/dev/null 2>&1 && [ -f "$TAR.sign" ]; then
	if ! gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys "$LINUX_KEY" >/dev/null 2>&1; then
		say "AVISO: no pude traer la clave $LINUX_KEY; el sha si cuadra"
	elif xz -dc "$TAR" | gpg --verify "$TAR.sign" - >/dev/null 2>&1; then
		say "firma verificada"
	else
		say "ABORTA: la firma del tarball NO verifica"
		exit 1
	fi
else
	say "AVISO: sin gpg, la firma no se verifica (el sha si cuadra)"
fi

[[ ! -e $K ]] || { say "ya existe $K (borralo a mano para rehacer)"; exit 1; }
tar -xJf "$TAR" -C "$W"
say "linux-7.2.9 extraido (sha tarball OK = source_sha256 de manifests/linux-7.2.9.json)"

# ------------------------------------------------------------- %prep del spec --

mkdir -p "$K/senemos-adaptation/patches" "$K/senemos-adaptation/configs"
cp "$EXT"/patches/7.2.9/* "$K/senemos-adaptation/patches/"
cp "$EXT"/configs/{arm64-qcom,uke,fedora}.config "$K/senemos-adaptation/configs/"
cp "$EXT/manifests/linux-7.2.9.json" "$K/senemos-adaptation/source-lock.json"
jq -r '.patches[].path | split("/") | last' "$K/senemos-adaptation/source-lock.json" > "$K/senemos-expected-patches.txt"
cmp "$K/senemos-expected-patches.txt" "$K/senemos-adaptation/patches/series"
while IFS=$'\t' read -r path expected; do
	case "$path" in
	patches/*) staged="$K/senemos-adaptation/patches/${path##*/}" ;;
	configs/*) staged="$K/senemos-adaptation/configs/${path##*/}" ;;
	*) exit 1 ;;
	esac
	[[ $(sha256sum "$staged" | cut -d' ' -f1) == "$expected" ]] || { say "sha MAL $path"; exit 1; }
done < <(jq -r '.patches[], .configs[] | [.path,.sha256] | @tsv' "$K/senemos-adaptation/source-lock.json")
say "44 parches + 3 fragmentos con sha == source-lock"
git -C "$K" -c init.defaultBranch=senemos init -q
: > "$K/senemos-applied-patches.txt"
say "--- serie base patches/7.2.9 (44) ---"
while IFS= read -r patch_name; do
	[[ -n $patch_name ]] || continue
	ap "$K/senemos-adaptation/patches/$patch_name"
	printf '%s\n' "$patch_name" >> "$K/senemos-applied-patches.txt"
done < "$K/senemos-adaptation/patches/series"
cmp "$K/senemos-expected-patches.txt" "$K/senemos-applied-patches.txt"

# ------------------------------------------------ native-profile/prepare.sh --

mkdir -p "$GEN"

# ===== src/boot/prepare-abl-source.sh =====
say "--- prepare-abl-source (reproducido) ---"
HB=$EXT/src/boot
[[ $(awk '/^VERSION =/ {v=$3} /^PATCHLEVEL =/ {p=$3} /^SUBLEVEL =/ {s=$3} END {print v "." p "." s}' "$K/Makefile") == 7.2.9 ]]
for need in 0015-uke-wlan-supplies-and-dma.patch 0016-uke-wlan-ordered-rails.patch \
	0023-uke-qup1-backlight-bus.patch 0025-uke-paired-normal-backlight.patch \
	0026-cliffs-lpass-adsp-interconnect.patch 0036-uke-adreno732-render.patch \
	0037-uke-gpu-interconnect.patch; do
	grep -Fxq "$need" "$K/senemos-applied-patches.txt"
done
ap "$EXT/patches/boot/0001-arm64-uke-abl-dt-hook.patch" \
	--exclude=drivers/regulator/qcom-rpmh-regulator-uke.c --exclude=drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c
install -m644 "$HB/uke-abl.c" "$K/arch/arm64/kernel/uke-abl.c"
[[ $(sha256sum "$HB/vendor/fdt_check.c" | cut -d' ' -f1) == "$(jq -er .sha256 "$HB/vendor/source.json")" ]]
grep -F 'DTC 1.7.2-g53373d13' "$K/scripts/dtc/version_gen.h" >/dev/null
install -m644 "$HB/vendor/fdt_check.c" "$K/scripts/dtc/libfdt/fdt_check.c"
for name in overlay check; do
	{
		printf '// SPDX-License-Identifier: GPL-2.0-only\n#include <linux/libfdt_env.h>\n'
		if [[ $name == overlay ]]; then
			printf '#include <linux/kstrtox.h>\n#define strtoul simple_strtoul\n'
		fi
		printf '#include "../scripts/dtc/libfdt/fdt_%s.c"\n' "$name"
	} > "$K/lib/fdt_$name.c"
done
header=$K/arch/arm64/kernel/uke-abl-overlays.h
: > "$header"
for name in ufs usb; do
	src=$HB/sm7675-uke-ufs.dtso
	[[ $name != usb ]] || src=$HB/sm7675-uke-usb2.dtso
	cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp -I "$K/include" "$src" > "$GEN/$name.dts"
	dtc -q -@ -I dts -O dtb -o "$GEN/$name.dtbo" "$GEN/$name.dts"
	{
		printf 'static unsigned char uke_%s_overlay[] __initdata __aligned(8) = {\n' "$name"
		od -An -v -tx1 "$GEN/$name.dtbo" | sed -E 's/[a-f0-9]{2}/0x&,/g'
		printf '};\n'
	} >> "$header"
done
(cd "$GEN"; sha256sum ufs.dtbo usb.dtbo > overlay-SHA256SUMS)
say "  overlays UFS/USB compilados y embebidos en uke-abl-overlays.h"

# ===== src/display/prepare-source.sh =====
say "--- prepare-source display (reproducido) ---"
HD=$EXT/src/display
paths=(
	drivers/gpu/drm/msm/disp/dpu1/catalog/dpu_10_1_sm7675.h
	drivers/gpu/drm/panel/panel-xiaomi-o82.c
	drivers/gpu/drm/panel/o82-data.h
	drivers/clk/qcom/uke-dispcc-votes.c
	drivers/interconnect/qcom/cliffs-display-icc.h
	drivers/iommu/arm/arm-smmu/uke-display-smmu.c
	drivers/gpu/drm/msm/uke-mdss-handoff.c
	include/linux/qcom-uke-display.h
	include/drm/uke-o82-mode.h
)
for path in "${paths[@]}"; do [[ ! -e $K/$path ]]; done
ap "$EXT/patches/display/7.2.10/0001-native-display-providers.patch"
ap "$EXT/patches/display/0003-native-display-supply-admission.patch"
ap "$EXT/patches/display/0004-native-dsi-diagnostics.patch"
ap "$EXT/patches/display/0006-native-o82-dsc-rate-control.patch"
for c in 0007-native-dsc-full-ich-precision.patch 0008-native-o82-video-sequence.patch \
	0009-native-dsc-initial-lines.patch 0010-native-o82-phy-timing.patch \
	0011-native-dsi-read-transaction.patch 0012-native-dsi-invalid-rx-diagnostics.patch \
	0013-native-o82-phy-strength.patch 0014-native-o82-retime-clock-select.patch \
	0015-native-dpu-video-timing-master.patch 0016-native-o82-host-clock-timing.patch \
	0018-uke-o82-fll-cold-start.patch 0019-uke-o82-staged-command-broadcast.patch \
	0020-uke-single-ctl-bonded-video-flush.patch 0021-uke-dsi-mdp-misr-diagnostic.patch \
	0022-uke-o82-video-command-scheduling.patch 0023-uke-o82-tp-fps-command-batch.patch \
	0024-uke-o82-on-command-groups.patch 0025-uke-o82-video-hs-timer.patch \
	0026-native-o82-fifo-phase-diagnostics.patch 0027-uke-o82-preserve-live-link-clocks.patch \
	0028-uke-o82-command-overflow-cleanup.patch 0029-uke-o82-video-command-frame-block.patch \
	0030-uke-o82-powered-transfer-clocks.patch 0031-uke-o82-post-start-lp-groups.patch \
	0032-uke-o82-bonded-bias-replay.patch 0033-uke-o82-oem-refresh-modes.patch \
	0034-uke-o82-live-refresh-timing.patch; do
	ap "$EXT/patches/display/$c"
done
for path in "${paths[@]}"; do
	s=${path##*/}
	[[ $s != uke-o82-mode.h ]] || s=o82-mode.h
	install -m644 "$HD/$s" "$K/$path"
done
say "  9 fuentes de src/display instaladas sobre los creados por display/7.2.10/0001"

# ===== src/display/prepare-native-abl-source.sh 42 =====
say "--- prepare-native-abl-source 42 (reproducido) ---"
[[ -s $K/drivers/gpu/drm/panel/panel-xiaomi-o82.c ]]
cmp "$HB/uke-abl.c" "$K/arch/arm64/kernel/uke-abl.c"
git -C "$K" apply --check "$EXT/patches/display/0002-arm64-uke-native-abl-entry.patch"
git -C "$K" apply --check "$EXT/patches/display/0005-native-dpu-dsc-active-width.patch"
cpp -nostdinc -undef -D__DTS__ -DO82_PANEL_VARIANT=42 -x assembler-with-cpp \
	-I "$K/include" "$HD/sm7675-uke-native-display.dtso" > "$GEN/display-60.dts"
dtc -q -@ -I dts -O dtb -o "$GEN/display-60.dtbo" "$GEN/display-60.dts"
install -m644 "$HD/uke-abl-native.h" "$K/arch/arm64/kernel/uke-abl-native.h"
ap "$EXT/patches/display/0002-arm64-uke-native-abl-entry.patch"
ap "$EXT/patches/display/0005-native-dpu-dsc-active-width.patch"

# ===== packaging/native/prepare.sh: overlay exacto de siete modos =====
say "--- overlay oem-modes (prepare.sh, reproducido) ---"
cpp -nostdinc -undef -D__DTS__ -DO82_PANEL_VARIANT=42 -x assembler-with-cpp \
	-I "$K/include" "$HD/sm7675-uke-native-display-oem-modes.dtso" > "$GEN/display.dts"
dtc -q -@ -I dts -O dtb -o "$GEN/display.dtbo" "$GEN/display.dts"
{
	printf '#define UKE_NATIVE_PANEL_SELECTOR "msm_drm.dsi_display0=qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid:"\n'
	printf 'static unsigned char uke_native_overlay[] __initdata __aligned(8) = {\n'
	od -An -v -tx1 "$GEN/display.dtbo" | sed -E 's/[a-f0-9]{2}/0x&,/g'
	printf '};\n'
} > "$K/arch/arm64/kernel/uke-native-display.h"
fdtdump "$GEN/display.dtbo" 2>/dev/null | grep -Eq '^[[:space:]]+xiaomi,oem-refresh-modes;'
sha256sum "$GEN"/*.dtbo "$K/arch/arm64/kernel/uke-abl.c" "$K/arch/arm64/kernel/uke-abl-native.h" \
	"$K/arch/arm64/kernel/uke-abl-overlays.h" "$K/arch/arm64/kernel/uke-native-display.h" > "$GEN/reproducir-SHA256SUMS"
say "OK: arbol .4054 (native54, O82-42 siete modos) reproducido; sin initramfs ni boot.img"
say "SIGUIENTE: aplicar los parches propios con build/rootfs/deploy/audio/kernel/deltas-omarchy-v4.sh"
