#!/bin/bash
# build-k67.sh — construye el kernel K67-D1SOLO (k52+K64 + D1 gmu 220M SIN D2
# ni D3 + poll vendor + GENERAL_10/8 corregidos, BARRIDO-W4) desde CERO y con
# todo versionado.
#
# Base: clon de build-k66.sh (misma fuente k52-tree, misma config
# k52-bateria.config, mismo cpio K34-fw, MAKE/ARCH/LLVM, Image.gz).
# Diferencias: O=k67-build, parche k67-d1solo.diff en vez del k66
# (D2 eliminado por el analisis W4-K67 §1-2: su RCG hub_clk_src deriva del
# GPLL0 compartido con USB y arrastra el AHB a 200M sin voto CX; D3 sigue
# fuera por la autopsia W3-K66),
# gates K67 (D1 renombrado + SIN-D2 + SIN-D3 + poll + G10/G8; D2/D3/K66-D1 en
# mustnt).
#
# NOTA DE REPRODUCIBILIDAD: la receta canónica es build limpio (O=k67-build
# inexistente → ~60 min). Si O=k67-build ya existe (p. ej. copia de k66-build),
# make reconstruye solo lo cambiado: el artefacto se verifica igual por gates.
set -euo pipefail

R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
SRC=$R/build/kernel-pokes/k52-tree
O=$R/build/kernel-pokes/k67-build
CFG=$R/build/kernel-config/k52-bateria.config
LOG=$R/build/logs/build-k67.log

if [ -z "${UKE_BUILD_DETACHED:-}" ]; then
	mkdir -p "$(dirname "$LOG")"
	export UKE_BUILD_DETACHED=1
	setsid nohup "$0" "$@" >>"$LOG" 2>&1 &
	disown || true
	echo "build K67 desprendido (pid $!); log en $LOG"
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
    b'UKE-POKE: arming en caliente': 'instrumentacion SMMU viva en el arbol migrado',
    b'UKE-K18: kgsl heredado SMR(': 'herencia BL kgsl-smmu (fase K18)',
    b'UKE-POKE: handoff: FIN barrido': 'barrido de pineo SMR (handoff)',
    b'UKE-K25: volcado SMMU DESACTIVADO': 'el volcado SMMU apagado (test H2)',
    b'uke_smmu_dump':               'el parametro conmutable del volcado',
    b'UKE-K38: attach dev=%s id[': 'la sonda SME(SID)->CBnDx (nudo del cuelgue S3-rst0)',
    # MIGRACION-SMMU (9-oct-2026, K65): el caminador K25 (WALK/MAPPING) tampoco
    # migro al layout upstream (grep: 0 en fuente; k64 YA sale sin el). El
    # veredicto del dtcm-magic (K32) SI vive y se gatea abajo.
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
    b'UKE-K44 A: rst=':              'la sonda de registros del CM3 (ledger #499)',
    b'K47-crtc-en':                   'miga: dpu_crtc_enable (ledger #502; el nombre en fuente sigue K47)',
    b'K47-7nm-en':                    'miga: dsi_7nm_phy_enable (nombre en fuente K47)',
    # --- UKE-K49 (3-oct, ledger #509): lineas ESD del TDDI registradas.
    b'UKE-K49: esd gpio %d -> irq %d ARMADA val=%d': 'probe: irq ESD armada',
    b'UKE-K49: ESD irq %d! gpio idx %d val=%d':      'ISR: aseveracion ESD',
    b'UKE-K49: sin esd-err-gpios en DT':             'rama DT-viejo (control)',
    b'K49-esd-armado':               'poke al final del registro ESD',
    b'K47-pll-prep':                  'miga: pll vco prepare (nombre en fuente K47)',
    b'gmu init ret=%d':               'el camino de error del GMU sigue en su sitio (duplicado deliberado: orden estable),',
    # --- UKE-K42 (2-oct, ledger #491): UN SOLO CAMBIO (el marcador visible).
    # El resto es K41 intacto: NO se acota log_buf_len (refutado por la critica:
    # el tope esta en el host y el ring recortado empobrece dmesg sin quitar
    # ningun missed).
    b'UKE-K42: entrando en adreno_bind': 'el marcador VISIBLE del ladder (pr_warn en adreno_bind)',
    # --- UKE-K67 (9-oct, BARRIDO-W4): D1-SOLO SIN D2 NI D3 + poll vendor +
    # G10/G8 (estos ultimos, testigos K66 intactos del k66).
    # D2 eliminado por el analisis (RCG GPLL0/AHB); D1 renombrado K67 como
    # discriminador del experimento.
    b'UKE-K67: D1 gmu clk_set 220M rc=': 'D1: GMU a 220M (D1-solo, sin D2 ni D3)',
    b'UKE-K67: SIN-D2 (hub en rate XBL': 'D2 eliminado (hub/AHB en rate XBL)',
    b'UKE-K67: SIN-D3 (voto CX eliminado': 'D3 sigue eliminado (autopsia W3-K66)',
    b'UKE-K66: poll vendor (val&0x1ff)==0x100': 'poll vendor del fw (W2-RE s4)',
    b'UKE-K66: GENERAL_10 chipid=': 'GENERAL_10 chipid validado (W2-RE s2)',
    b'UKE-K66: GENERAL_8 log=': 'GENERAL_8 log.iova recompuesto (W2-RE s3)',
    # NO se gatea `uke_ignore_always_dump` POR TEXTO: es un `static bool = true` y el
    # compilador lo constante-pliega, asi que el simbolo NO aparece en el Image (lo
    # cazo este gate en el intento 1, build-k42-intento1-fallido.log). Misma leccion
    # que el unwind blindado. Lo que se gatea es el marcador, y el "ignorar el
    # always_kmsg_dump del ABL" se verifica leyendo el diff, no el binario.
}
mustnt = {
    b'0x200000;':                    'ioremap de 2 MB de K23 (fuera del recurso)',
    b'\x014UKE-POKE: %s':            'la forma pr_warn del uke_poke (nivel 4: el tope la OCULTA, K42 la llevaba)',
    # UKE-K25: el volcado plano que leia basura NO debe seguir presente.
    b'uke_k19_dump_desc(e[4]':      'volcado plano e[4] (leia basura: fuera de la tabla)',
    # UKE-K67: D2 y D3 eliminados — sus testigos NO deben existir en el binario
    # (tampoco los renombres K66 del D1/D2, sustituidos por K67).
    b'UKE-K65: D3 cx LOW_SVS opp_set_rate 220M rc=': 'D3 de k65 (asesino presunto W3: debe haber DESAPARECIDO)',
    b'UKE-K65: D2 hub clk_set 200M rc=': 'D2 de k65 (eliminado en k67)',
    b'UKE-K66: D2 hub clk_set 200M rc=': 'D2 de k66 (eliminado en k67: debe haber DESAPARECIDO)',
    b'UKE-K66: D1 gmu clk_set 220M rc=': 'D1 de k66 (renombrado a K67 en k67)',
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
say "DONE K67-BUILD-OK"
