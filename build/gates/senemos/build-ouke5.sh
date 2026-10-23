#!/usr/bin/env bash
# build-ouke5.sh — compila el kernel de la variante vigente (senemos ouke5) con
# el .config versionado en este repo.
#
# POR QUE EXISTE. La cadena de reproduccion (reproducir-arbol.sh ->
# deltas-senemos.sh -> instalar-config.sh) llegaba hasta el ARBOL, pero no
# habia ningun script que llegara al Image.gz: build-senemos-v4.sh compila la
# ouke4 y pide configs (config-senemos-ouke3/ouke4) que no se publican. Con
# este, un tercero tiene un kernel compilable sin la tablet.
#
# QUE HACE.
#   1. instala el .config publicado en el directorio de build (con la ruta del
#      initramfs en absoluto)
#   2. olddefconfig, y COMPRUEBA que no ha cambiado ni una linea
#   3. make Image.gz dtbs
#   4. comprueba los marcadores del kernel (el veredicto del ABL, que es el
#      parche propio 0001) y saca los sha
#
# USO:
#   bash build/gates/senemos/build-ouke5.sh [--dest DIR] [--sin-initramfs] [--jobs N]
#
#   --dest DIR        directorio de build (por defecto build/kernel-pokes/senemos-build)
#   --sin-initramfs   compila SIN CONFIG_INITRAMFS_SOURCE (el initramfs vivo
#                     lleva firmware del fabricante y no se publica: sirve para
#                     verificar que el kernel compila, no para arrancar)
#   --jobs N          parallelism (por defecto: nproc)
#
# REQUISITOS: clang 23.1.x, lld, make, flex, bison, libelf, bc, dtc, python3.
# El banner del kernel lleva la version de la toolchain, asi que una toolchain
# distinta cambia el sha que comparan los gates de flasheo (ver BUILD.md §3).
set -Eeuo pipefail

R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
HERE="$R/build/gates/senemos"
DEST="$R/build/kernel-pokes/senemos-build"
K="${SENEMOS_TREE:-$R/build/kernel-pokes/senemos-7.2.9/linux-7.2.9}"
JOBS="$(nproc 2>/dev/null || echo 4)"
SIN_INITRAMFS=0

# El release string que exigen los gates de despliegue (vermagic).
LV="-senemos.1.4054.3-ouke5"
REL="7.2.9$LV"

while [ $# -gt 0 ]; do
	case "$1" in
	--dest) DEST="$2"; shift 2 ;;
	--sin-initramfs) SIN_INITRAMFS=1; shift ;;
	--jobs) JOBS="$2"; shift 2 ;;
	*) echo "uso: $0 [--dest DIR] [--sin-initramfs] [--jobs N]" >&2; exit 2 ;;
	esac
done

say() { printf '[build-ouke5] %s\n' "$*"; }
die() { say "ABORTA: $*"; exit 2; }

[ -d "$K" ] || die "no existe el arbol del kernel en $K (primero: reproducir-arbol.sh)"
[ -f "$HERE/../../kernel-config/senemos-ouke5.config" ] || die "falta el .config publicado"

command -v clang >/dev/null || die "falta clang"
say "clang: $(clang --version | head -1)"

mkdir -p "$DEST"

# 1) el .config publicado, con la ruta del initramfs en absoluto
if [ $SIN_INITRAMFS = 1 ]; then
	say "modo --sin-initramfs: el initramfs lleva firmware del fabricante y no se publica"
	sed -e 's#^CONFIG_INITRAMFS_SOURCE=.*#CONFIG_INITRAMFS_SOURCE=""#' \
		"$HERE/../../kernel-config/senemos-ouke5.config" > "$DEST/.config"
else
	INIT_ABS="$R/build/init/uke-k34-fw-k52b2-initramfs.cpio.gz"
	[ -f "$INIT_ABS" ] || die "falta el initramfs $INIT_ABS
   (no se publica: lleva firmware del fabricante, y los mkcpio-*.py lo CONSUMEN
    como entrada, no lo generan). Para compilar sin el: --sin-initramfs"
	sed -e "s#^CONFIG_INITRAMFS_SOURCE=.*#CONFIG_INITRAMFS_SOURCE=\"$INIT_ABS\"#" \
		"$HERE/../../kernel-config/senemos-ouke5.config" > "$DEST/.config"
fi

# 2) olddefconfig, y que no cambie nada
export ARCH=arm64 LLVM=1 LLVM_IAS=1 MAKE=/usr/bin/make
/usr/bin/make -C "$K" O="$DEST" LOCALVERSION="$LV" olddefconfig >/dev/null
say "olddefconfig hecho; comparando con el .config publicado"
# Se comparan sin las opciones del initramfs: en el publicado la ruta es
# relativa al repo y aqui va a ser absoluta, y en modo --sin-initramfs
# olddefconfig borra TODO el bloque CONFIG_INITRAMFS_* (compression, uid, gid).
# El resto tiene que coincidir linea a linea.
sin_init() { grep -vE '^(# )?CONFIG_INITRAMFS_' "$1"; }
if ! diff -q <(sin_init "$DEST/.config") <(sin_init "$HERE/../../kernel-config/senemos-ouke5.config") >/dev/null; then
	diff <(sin_init "$HERE/../../kernel-config/senemos-ouke5.config") \
		<(sin_init "$DEST/.config") | head -20
	die "olddefconfig cambio el .config publicado: el .config del repo no corresponde a este arbol"
fi
say "el .config publicado y olddefconfig coinciden"

# 3) el kernel
say "compilando (jobs=$JOBS); esto tarda del orden de 20-30 min"
/usr/bin/make -C "$K" O="$DEST" LOCALVERSION="$LV" -j"$JOBS" Image.gz dtbs

KREL=$(/usr/bin/make -s -C "$K" O="$DEST" LOCALVERSION="$LV" kernelrelease)
say "kernelrelease=$KREL"
[ "$KREL" = "$REL" ] || die "kernelrelease inesperado ($KREL != $REL): el LOCALVERSION o la config no son los de esta variante"

# 4) marcadores: el veredicto del ABL (el parche propio 0001) tiene que estar
# DENTRO del kernel, no solo en el arbol.
if grep -q "UKE-SENEMOS" "$DEST/arch/arm64/boot/Image" 2>/dev/null; then
	say "OK: el veredicto del ABL esta en el Image (parche 0001 aplicado)"
else
	say "AVISO: no encuentro el marcador del ABL en el Image; comprueba que se aplico el parche 0001"
fi

sha256sum "$DEST/arch/arm64/boot/Image" "$DEST/arch/arm64/boot/Image.gz" "$DEST/.config"
say "listo: $DEST/arch/arm64/boot/Image.gz"
say "el modulo de los .ko tiene que llevar este vermagic: $KREL"
