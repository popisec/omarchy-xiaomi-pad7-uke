#!/bin/bash
# build-k43.sh —construye el kernel K43 desde CERO y con todo versionado.
#
# POR QUÉ ESTE SCRIPT (1-oct-2026). Antes el kernel se compilaba a mano y el
# arbol instrumentado vivia solo en build/kernel-pokes/k18-tree/, que esta en
# .gitignore y no tiene ningun diff guardado: el K23 no era reconstruible desde
# el repo. Este script cierra el hueco:
#   fuente  = build/kernel-pokes/k18-tree  (k13-tree + ACUMULADO-...-a-k24.diff +
#             los cambios K25..K42 QUE SOLO VIVEN EN EL ARBOL — hueco reconocido en
#             #492-errata; el delta K42->K43 SI queda versionado:
#             build/gates/patches/k43-uke-poke-pr-err.diff)
#   config  = build/kernel-config/k43.config  (VERSIONADO; trae
#             INITRAMFS_SOURCE -> build/init/uke-k22-initramfs.cpio.gz, que es
#             lo que hornea los 3 firmware de la GPU en el initramfs)
#   salida  = build/kernel-pokes/k43-build
# Repack: docs/historia/gates-palawan/repack-k18.py --out boot-ukek43.img
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
O=$R/build/kernel-pokes/k43-build
CFG=$R/build/kernel-config/k43.config
LOG=$R/build/logs/build-k43.log

if [ -z "${UKE_BUILD_DETACHED:-}" ]; then
	mkdir -p "$(dirname "$LOG")"
	export UKE_BUILD_DETACHED=1
	setsid nohup "$0" "$@" >>"$LOG" 2>&1 &
	disown || true
	echo "build K43 desprendido (pid $!); log en $LOG"
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
say "OK  INITRAMFS_SOURCE -> cpio K34-fw, y el fw GPU esta DENTRO (K43)"
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
    b'UKE-K19: GEO ID0=':            'linea GEO de geometria',
    b'CBbase=0x%llx stride=0x%llx':  'calculo de CBbase/stride',
    b'type=%u=%s cbndx=%u':          'decode S2CR corregido (type=[17:16], cbndx=[7:0])',
    b'recurso del DT, exacto':       'ioremap limitado al recurso del DT',
    b'-> TRANS por CB%u':            'anotacion del CB al que apunta cada S2CR valido',
    b'L[%d] iova=0x%05llx':          'decode de descriptores LPAE',
    # --- UKE-K25 (sesion #455): el discriminador tiene que CAMINAR la tabla.
    # El volcado plano (e[0..7], y e[4] como "el del icache@0x4000") leia BASURA:
    # el arranque dice "0 stage-2 only" => traduccion de 32 bits => la tabla de
    # primer nivel tiene 4 entradas de 1 GB, y e[4..7] estan mas alla del final.
    b'UKE-K25: volcado SMMU DESACTIVADO': 'el volcado SMMU apagado (test H2)',
    b'uke_smmu_dump':               'el parametro conmutable del volcado',
    b'UKE-K38: attach dev=%s id[': 'la sonda SME(SID)->CBnDx (nudo del cuelgue S3-rst0)',
    b'WALK iova=0x%llx':             'el caminador de tabla (C1)',
    b'MAPPING ENCONTRADO':           'desenlace positivo del walk',
    b'veredicto=%s':                 'veredicto explicito del dtcm-magic',
    b'UKE-K33: dev=%s NO es la GPU': 'el fix de fondo: quitar TTBR1 al GMU',
    b'UKE-K32: RESULTADO':           'la sonda que resuelve el nudo (a) vs (b)',
    b'UKE-K32: init_context':        'la sonda: SID y quirks del dominio',
    # El blindaje del unwind (bo->obj/bo->virt = NULL tras drm_gem_object_put) NO
    # deja cadena en el binario: el compilador lo convierte en stores. Por eso NO se
    # gatea por texto; se verifica por desensamblado en flash-k42.sh. Aqui basta
    # exigir que el caminho de fallo del alloc sigue presente y con su mensaje.
    b'gmu init ret=%d':               'el camino de error del GMU sigue en su sitio',
    # --- UKE-K42 (2-oct, ledger #488): el ABL pone sus tokens AL FINAL de la
    # cmdline y el ultimo gana, asi que loglevel=4 y always_kmsg_dump=0 NUNCA
    # surtieron efecto (medido en 5 boots de K40). El tope va en el CODIGO.
    b'UKE-K41: consola tope=%d':      'el marcador del tope de consola (pr_warn en console_init)',
    # --- UKE-K43 (sesion #493): el uke_poke pasa a pr_err. El gate es BINARIO:
    # la forma err ("\x01" "3" + formato) presente y la warn ("\x01" "4") AUSENTE.
    b'\x013UKE-POKE: %s':            'uke_poke como pr_err (nivel 3 < 4: PASA el tope de K41)',
    b'gmu init ret=%d':               'el camino de error del GMU sigue en su sitio (duplicado deliberado: orden estable),', 
    # --- UKE-K42 (2-oct, ledger #491): UN SOLO CAMBIO (el marcador visible).
    # El resto es K41 intacto: NO se acota log_buf_len (refutado por la critica:
    # el tope esta en el host y el ring recortado empobrece dmesg sin quitar
    # ningun missed).
    b'UKE-K42: entrando en adreno_bind': 'el marcador VISIBLE del ladder (pr_warn en adreno_bind)',
    # NO se gatea `uke_ignore_always_dump` POR TEXTO: es un `static bool = true` y el
    # compilador lo constante-pliega, asi que el simbolo NO aparece en el Image (lo
    # cazó este gate en el intento 1, build-k42-intento1-fallido.log). Misma leccion
    # que el unwind blindado. Lo que se gatea es el marcador, y el "ignorar el
    # always_kmsg_dump del ABL" se verifica leyendo el diff, no el binario.
}
mustnt = {
    b'0x200000;':                    'ioremap de 2 MB de K23 (fuera del recurso)',
    b'\x014UKE-POKE: %s':            'la forma pr_warn del uke_poke (nivel 4: el tope la OCULTA, K42 la llevaba)', 
    # UKE-K25: el volcado plano que leia basura NO debe seguir presente.
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

say "==K43: gates de nivel del uke_poke (err presente / warn ausente)=="
# (ya comprobados arriba sobre el Image crudo)
say "==sha del kernel y del initramfs embebido=="
sha256sum "$IMG" "$IMGZ"
say "==initramfs embebido (debe ser el cpio K22, 08780e35…)=="
sha256sum "$R/build/init/uke-k22-initramfs.cpio.gz"
say "DONE K43-BUILD-OK"
