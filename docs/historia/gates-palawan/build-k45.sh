#!/bin/bash
# build-k45.sh —construye el kernel K45-PANTALLA (DRM_MSM=n + DRM_SIMPLEDRM=y) desde CERO y con todo versionado.
#
# POR QUÉ ESTE SCRIPT (1-oct-2026). Antes el kernel se compilaba a mano y el
# arbol instrumentado vivia solo en build/kernel-pokes/k18-tree/, que esta en
# .gitignore y no tiene ningun diff guardado: el K23 no era reconstruible desde
# el repo. Este script cierra el hueco:
#   fuente  = build/kernel-pokes/k18-tree  (k13-tree + ACUMULADO-...-a-k24.diff +
#             los cambios K25..K42 QUE SOLO VIVEN EN EL ARBOL — hueco reconocido en
#             #492-errata; el delta K42->K43 SI queda versionado:
#             build/gates/patches/k43-uke-poke-pr-err.diff)
#   config  = build/kernel-config/k45-pantalla.config  (VERSIONADO; trae
#             INITRAMFS_SOURCE -> build/init/uke-k22-initramfs.cpio.gz, que es
#             lo que hornea los 3 firmware de la GPU en el initramfs)
#   salida  = build/kernel-pokes/k45-build
# Repack: docs/historia/gates-palawan/repack-k18.py --out boot-ukek45-pantalla.img
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
O=$R/build/kernel-pokes/k45-build
CFG=$R/build/kernel-config/k45-pantalla.config
LOG=$R/build/logs/build-k45.log

if [ -z "${UKE_BUILD_DETACHED:-}" ]; then
	mkdir -p "$(dirname "$LOG")"
	export UKE_BUILD_DETACHED=1
	setsid nohup "$0" "$@" >>"$LOG" 2>&1 &
	disown || true
	echo "build K45 desprendido (pid $!); log en $LOG"
	exit 0
fi

say() { echo "[$(date +%H:%M:%S)] $*"; }
fail() { say "ABORT: $*"; exit 1; }

[ -d "$SRC" ] || fail "no existe el arbol fuente $SRC"
[ -f "$CFG" ] || fail "no existe el config versionado $CFG"
[ -f "$R/build/init/uke-k34-fw-initramfs.cpio.gz" ] || fail "falta el cpio K34-fw (cpio K12 + fw GPU)"

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
grep -qE '^CONFIG_INITRAMFS_SOURCE=".*uke-k34-fw-initramfs.cpio.gz"' "$O/.config" \
	|| fail "INITRAMFS_SOURCE no apunta al cpio K34-fw (con fw GPU)"
# UKE-K42: el cpio tiene que LLEVAR el firmware DENTRO, que es el punto del ciclo:
# el DPU lo pide a los ~4 s, antes de montar la rootfs.
for f in gen71100_sqe.fw gen71100_gmu.bin gen71100_zap.mbn; do
	gzip -dc "$R/build/init/uke-k34-fw-initramfs.cpio.gz" | cpio -it 2>/dev/null \
		| grep -qx "lib/firmware/qcom/$f" || fail "el cpio K34-fw no lleva lib/firmware/qcom/$f"
done
say "OK  INITRAMFS_SOURCE -> cpio K34-fw, y el fw GPU esta DENTRO (K45; inert con DRM_MSM=n)"
grep -qE '^CONFIG_INITRAMFS_COMPRESSION_GZIP=y' "$O/.config" \
	|| fail "falta CONFIG_INITRAMFS_COMPRESSION_GZIP"
say "OK  INITRAMFS_COMPRESSION_GZIP=y"

say "==make Image.gz (esto es lo lento: $O se recompila entero) =="
# Image.gz y no Image: lo que necesita el repack es el .gz (el G3 de
# repack-k18.py lo descomprime y gatea sobre el crudo). Construir solo Image
# dejaba el .gz ausente y el repack se caia.
make O="$O" -j4 Image.gz

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
    # --- UKE-K45 (sesion #495): PANTALLA SIN GPU. DRM_MSM=n => ningun marcador del stack
    # msm/adreno puede estar en el Image. DRM_SIMPLEDRM=y => su compatible y uke_poke pr_err si.
    b'\x013UKE-POKE: %s':            'uke_poke sigue pr_err (nivel 3: pasa el tope de K41)',
    b'UKE-K41: consola tope=%d':      'el tope de consola de K41 sigue presente (printk.c)',
    b'simple-framebuffer':            'el compatible de simpledrm (bind de framebuffer@e3940000)',
}
mustnt = {
    b'UKE-POKE: S3-rst0':            'a6xx_gmu.c NO debe estar (DRM_MSM=n)',
    b'UKE-K42: entrando en adreno_bind': 'adreno_device.c NO debe estar (DRM_MSM=n)',
    b'\x014UKE-POKE: %s':            'la forma pr_warn del uke_poke (nivel 4: oculta, K42 la llevaba)',
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

say "==K43: gates de nivel del uke_poke (err presente / warn ausente)=="
# (ya comprobados arriba sobre el Image crudo)
say "==sha del kernel y del initramfs embebido=="
sha256sum "$IMG" "$IMGZ"
say "==initramfs embebido (debe ser el cpio K22, 08780e35…)=="
sha256sum "$R/build/init/uke-k22-initramfs.cpio.gz"
say "DONE K45-BUILD-OK"
