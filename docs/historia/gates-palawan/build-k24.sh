#!/bin/bash
# build-k24.sh —construye el kernel K24 desde CERO y con todo versionado.
#
# POR QUÉ ESTE SCRIPT (1-oct-2026). Antes el kernel se compilaba a mano y el
# arbol instrumentado vivia solo en build/kernel-pokes/k18-tree/, que esta en
# .gitignore y no tiene ningun diff guardado: el K23 no era reconstruible desde
# el repo. Este script cierra el hueco:
#   fuente  = build/kernel-pokes/k18-tree  (que a su vez es k13-tree + el diff
#             acumulado build/gates/patches/ACUMULADO-k13-a-k24.diff)
#   config  = build/kernel-config/k24.config  (VERSIONADO; trae
#             INITRAMFS_SOURCE -> build/init/uke-k22-initramfs.cpio.gz, que es
#             lo que hornea los 3 firmware de la GPU en el initramfs)
#   salida  = build/kernel-pokes/k24-build
# Repack: docs/historia/gates-palawan/repack-k18.py --out boot-ukek24.img
#
# REGLAS QUE ESTE SCRIPT RESPETA (por eso son gates, no comentarios):
#   - Build DESPRENDIDO: en primer plano el make es un no-op silencioso y un
#     "OK" vacio es indistinguible de un build real (LECCIONES.md del hermano).
#   - MAKE/ARCH/LLVM explicitos, y kernel.org exige >= 6.12 para mainline
#     arm64; este arbol es 7.2-rc2 con clang 22.1.8.
#   - Gate CONFIG_ARCH_QCOM: sin el, el objeto uke-panic-fb.c (obj-y
#     incondicional) revienta con "redefinition of uke_poke".
#   - Gate INITRAMFS_SOURCE: si olddefconfig la tira, el kernel sale SIN los
#     firmware de la GPU y se pierde lo que midio K22 (fw cargado a 4,07 s).
#   - Gates de MARCADORES sobre el Image crudo: comprueban que el binario
#     lleva el dump corregido y que NO lleva las formulas que se refutaron.
set -euo pipefail

R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
SRC=$R/build/kernel-pokes/k18-tree
O=$R/build/kernel-pokes/k24-build
CFG=$R/build/kernel-config/k24.config
LOG=$R/build/logs/build-k24.log

if [ -z "${UKE_BUILD_DETACHED:-}" ]; then
	mkdir -p "$(dirname "$LOG")"
	export UKE_BUILD_DETACHED=1
	setsid nohup "$0" "$@" >>"$LOG" 2>&1 &
	disown || true
	echo "build K24 desprendido (pid $!); log en $LOG"
	exit 0
fi

say() { echo "[$(date +%H:%M:%S)] $*"; }
fail() { say "ABORT: $*"; exit 1; }

[ -d "$SRC" ] || fail "no existe el arbol fuente $SRC"
[ -f "$CFG" ] || fail "no existe el config versionado $CFG"
[ -f "$R/build/init/uke-k22-initramfs.cpio.gz" ] || fail "falta el cpio con los fw de la GPU"

say "==-config--"
mkdir -p "$O"
cp -f "$CFG" "$O/.config"
# El source tree necesita symlinks a fuentes (Kbuild falla sin ellos).
for l in source scripts; do :; done
cd "$SRC"
export MAKE=/usr/bin/make
export ARCH=arm64
export LLVM=1
export KBUILD_BUILD_USER=uke
export KBUILD_BUILD_HOST=palawan

say "==olddefconfig=="
make O="$O" olddefconfig

# --- GATES DE CONFIG (antes de gastar 15 min de compilacion) ---
grep -qE '^CONFIG_ARCH_QCOM=y' "$O/.config" || fail "falta CONFIG_ARCH_QCOM en $O/.config"
say "OK  CONFIG_ARCH_QCOM=y"
grep -qE '^CONFIG_INITRAMFS_SOURCE=".*uke-k22-initramfs.cpio.gz"' "$O/.config" \
	|| fail "INITRAMFS_SOURCE no apunta al cpio con los fw de la GPU (se perderia K22)"
say "OK  INITRAMFS_SOURCE -> cpio K22 (fw GPU dentro)"
grep -qE '^CONFIG_INITRAMFS_COMPRESSION_GZIP=y' "$O/.config" \
	|| fail "falta CONFIG_INITRAMFS_COMPRESSION_GZIP"
say "OK  INITRAMFS_COMPRESSION_GZIP=y"

say "==make Image.gz (esto es lo lento: $O se recompila entero) =="
# Image.gz y no Image: lo que necesita el repack es el .gz (el G3 de
# repack-k18.py lo descomprime y gatea sobre el crudo). Construir solo Image
# dejaba el .gz ausente y el repack se caia.
make O="$O" -j"$(nproc)" Image.gz

IMG=$O/arch/arm64/boot/Image
IMGZ=$O/arch/arm64/boot/Image.gz
[ -f "$IMG" ] || fail "el build no produjo $IMG"
[ -f "$IMGZ" ] || fail "el build no produjo $IMGZ (el repack lo necesita)"
[ "$IMG" -nt "$O/.config" ] || fail "Image mas viejo que .config: el build no reconstruyo nada"
say "OK  Image $(stat -c%s "$IMG") B, mas nuevo que .config"

# --- GATES DE MARCADORES: el binario tiene que llevar el arreglo ---
python3 - "$IMG" <<'PY'
import sys
raw = open(sys.argv[1], 'rb').read()
must = {
    b'UKE-K19: GEO ID0=':            'linea GEO de geometria',
    b'CBbase=0x%llx stride=0x%llx':  'calculo de CBbase/stride',
    b'type=%u=%s cbndx=%u':          'decode S2CR corregido (type=[17:16], cbndx=[7:0])',
    b'recurso del DT, exacto':       'ioremap limitado al recurso del DT',
    b'-> TRANS por CB%u':            'anotacion del CB al que apunta cada S2CR valido',
    b'L[%d] iova=0x%05llx':          'decode de descriptores LPAE',
    # --- UKE-K24 (sesion #455): el discriminador tiene que CAMINAR la tabla.
    # El volcado plano (e[0..7], y e[4] como "el del icache@0x4000") leia BASURA:
    # el arranque dice "0 stage-2 only" => traduccion de 32 bits => la tabla de
    # primer nivel tiene 4 entradas de 1 GB, y e[4..7] estan mas alla del final.
    b'WALK iova=0x%llx':             'caminador de tabla (el discriminador real)',
    b'MAPPING ENCONTRADO':           'desenlace positivo del walk',
    b'HUECO':                        'desenlace negativo del walk (sin mapping)',
    b'veredicto=%s':                 'veredicto explicito del dtcm-magic (OK/STALE)',
    b'STALE/NO-OK':                  'el dtcm-magic NO cuadra (no es stale de este fw)',
}
mustnt = {
    b'0x200000;':                    'ioremap de 2 MB de K23 (fuera del recurso)',
    # UKE-K24: el volcado plano que leia basura NO debe seguir presente.
    b'uke_k19_dump_desc(e[4]':      'volcado plano e[4] (leia basura: fuera de la tabla)',
}
bad = []
for tok, what in must.items():
    if raw.count(tok) < 1:
        bad.append('FALTA %r (%s)' % (tok, what))
for tok, what in mustnt.items():
    if raw.count(tok) >= 1:
        bad.append('AUN ESTA %r (%s)' % (tok, what))
if bad:
    for b in bad:
        print('GATE MARCADOR:', b)
    sys.exit(1)
for tok in must:
    print('GATE OK  x%-3d %s' % (raw.count(tok), tok.decode('utf-8', 'replace')))
PY
[ $? -eq 0 ] || fail "gates de marcadores fallidos (ver arriba)"

say "==sha del kernel y del initramfs embebido=="
sha256sum "$IMG" "$IMGZ"
say "==initramfs embebido (debe ser el cpio K22, 08780e35…)=="
sha256sum "$R/build/init/uke-k22-initramfs.cpio.gz"
say "DONE K24-BUILD-OK"
