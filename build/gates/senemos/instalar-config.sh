#!/usr/bin/env bash
# instalar-config.sh — pone la config publicada del kernel en el directorio de
# build, con la ruta del initramfs en absoluto.
#
# POR QUE HACE FALTA. La config versionada lleva el initramfs con ruta
# RELATIVA al repo ("build/init/uke-k34-fw-k52b2-initramfs.cpio.gz"), para que
# el fichero sea el mismo en cualquier maquina (y no lleve la ruta de quien lo
# compilo). Kbuild, en cambio, la resuelve relativa al arbol del kernel, asi
# que al copiarla al directorio de build hay que convertirla en absoluta.
#
# USO:
#   bash build/gates/senemos/instalar-config.sh <dir-de-build> [config]
#
#   <dir-de-build>  el O= del make (p.ej. build/kernel-pokes/senemos-build)
#   config          por defecto build/kernel-config/senemos-ouke5.config
set -Eeuo pipefail

R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
B="${1:?uso: $0 <dir-de-build> [config]}"
CFG_IN="${2:-$R/build/kernel-config/senemos-ouke5.config}"

[ -f "$CFG_IN" ] || { echo "no existe la config $CFG_IN" >&2; exit 1; }
mkdir -p "$B"

cp -f "$CFG_IN" "$B/.config"
cp -f "$CFG_IN" "$B/config-senemos-ouke5"

# ruta absoluta del initramfs
INIT_ABS="$R/build/init/uke-k34-fw-k52b2-initramfs.cpio.gz"
if grep -q '^CONFIG_INITRAMFS_SOURCE="build/init/' "$B/.config"; then
	sed -i "s#^CONFIG_INITRAMFS_SOURCE=\"build/init/#CONFIG_INITRAMFS_SOURCE=\"$R/build/init/#" "$B/.config"
	cp -f "$B/.config" "$B/config-senemos-ouke5"
fi

grep -q "^CONFIG_INITRAMFS_SOURCE=\"$INIT_ABS\"" "$B/.config" \
	|| { echo "AVISO: el initramfs no apunta a $INIT_ABS" >&2; grep '^CONFIG_INITRAMFS_SOURCE' "$B/.config" >&2; }
# El initramfs tiene que EXISTIR: sin el, el kernel sale sin los firmware de la GPU
# y sin el arranque (que es justo lo que comprueba el gate INITRAMFS_SOURCE).
[ -f "$INIT_ABS" ] || {
	echo "FALTA el initramfs: $INIT_ABS" >&2
	echo "  No se publica: lleva firmware del fabricante. Y los mkcpio-*.py NO lo" >&2
	echo "  generan: lo CONSUMEN como entrada." >&2
	echo "  Para compilar sin el: bash build/gates/senemos/build-ouke5.sh --sin-initramfs" >&2
	exit 1
}

echo "config instalada en $B/.config"
echo "  initramfs: $(grep '^CONFIG_INITRAMFS_SOURCE' "$B/.config")"
echo "  sha config: $(sha256sum "$B/.config" | cut -d' ' -f1)"
echo "  sha origen: $(sha256sum "$CFG_IN" | cut -d' ' -f1)"
