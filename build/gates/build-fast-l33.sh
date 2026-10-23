#!/bin/bash
# build-fast.sh — receta de build COMPLETO reutilizable y RAPIDA.
# Clon de build-k52L11.sh con: ccache + -j12 + KBUILD_BUILD_TIMESTAMP fijo.
# Parametrizable por arbol (SRC), config (CFG), salida (O) y tag (TAG):
#
#   build/gates/build-fast.sh [--src DIR] [--cfg FILE] [--out DIR] [--tag TAG]
#                             [--jobs N] [--gates-only]
#   Env equivalentes: UKE_FAST_SRC / UKE_FAST_CFG / UKE_FAST_O / UKE_FAST_TAG /
#                     UKE_FAST_JOBS / CCACHE_DIR. Flags mandan sobre env.
#
# Defaults = L11 (el L12 la reutiliza con --src k52-L12-tree --cfg ... --out
# k52L12-build --tag k52L12; el TAG solo elige el log y los gates extra L12*).
#
# QUE CAMBIA respecto a build-k52L11.sh (y por que):
#   - CC="ccache clang" (+ HOSTCC="ccache gcc"): con clang NO basta PATH, hay
#     que envolver el compilador (nota del dueño). CCACHE_DIR por defecto
#     $HOME/.cache/ccache-uke (15G). CCACHE_BASEDIR=$R para que las
#     rutas absolutas bajo el repo no rompan hits entre O distintos.
#   - -j12 (16 cores/15G RAM; DEBUG_INFO_REDUCED limita el pico por TU).
#   - KBUILD_BUILD_TIMESTAMP fijo: init/Makefile lo usa SOLO para UTS_VERSION
#     (version.o + banner; el resto del arbol no depende de la fecha). Fijarlo
#     hace el banner reproducible y evita reconstruir version.o en cada build;
#     NO toca ningun gate (ninguno mira el banner/timestamp).
#   - stats de ccache al final (ccache -s).
#   - --gates-only: corre arranque desprendido + olddefconfig + gates de
#     config/fuente y PARA antes del make (para validar la receta sin quemar
#     un build completo).
#
# QUE NO CAMBIA: build desprendido (UKE_BUILD_DETACHED), MAKE/ARCH/LLVM,
# KBUILD_BUILD_USER/HOST, gates de config identicos a L11, gates de fuente
# L11-NOGOTO/L11-POLL (L12 es superconjunto de L11: tambien los pasa), gates
# de marcadores + L11-WRITE + niveles K43 copiados de L11, sha final.
# Diferencia menor: se tira el `for l in source scripts` de L11 (no-op: el
# cuerpo es `:` y no crea ningun symlink).
set -euo pipefail

R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
SRC=${UKE_FAST_SRC:-$R/build/kernel-pokes/k52-L16-tree}
CFG=${UKE_FAST_CFG:-$R/build/kernel-pokes/k52L19-build/.config}
O=${UKE_FAST_O:-$R/build/kernel-pokes/k52L21-build}
TAG=${UKE_FAST_TAG:-k52L11-fast}
JOBS=${UKE_FAST_JOBS:-12}
GATES_ONLY=

while [ $# -gt 0 ]; do
	case "$1" in
		--src)  SRC=$2; shift 2;;
		--cfg)  CFG=$2; shift 2;;
		--out)  O=$2; shift 2;;
		--tag)  TAG=$2; shift 2;;
		--jobs) JOBS=$2; shift 2;;
		--gates-only) GATES_ONLY=1; shift;;
		-h|--help)
			sed -n '2,30p' "$0"; exit 0;;
		*) echo "flag desconocido: $1 (ver --help)" >&2; exit 1;;
	esac
done

LOG=$R/build/logs/build-$TAG.log

if [ -z "${UKE_BUILD_DETACHED:-}" ]; then
	mkdir -p "$(dirname "$LOG")"
	export UKE_BUILD_DETACHED=1
	# Reenvia los valores YA resueltos como flags para que el hijo no dependa
	# del env del padre (solo CCACHE_DIR se hereda por export).
	setsid nohup "$0" --src "$SRC" --cfg "$CFG" --out "$O" --tag "$TAG" \
		--jobs "$JOBS" ${GATES_ONLY:+--gates-only} >>"$LOG" 2>&1 &
	disown || true
	echo "build $TAG desprendido (pid $!); log en $LOG"
	exit 0
fi

say() { echo "[$(date +%H:%M:%S)] $*"; }
fail() { say "ABORT: $*"; exit 1; }

[ -d "$SRC" ] || fail "no existe el arbol fuente $SRC"
[ -f "$CFG" ] || fail "no existe el config versionado $CFG"
[ -f "$R/build/init/uke-k52b2-diag-initramfs.cpio.gz" ] || fail "falta el cpio K34-fw (cpio K12 + fw GPU)"

# --- ccache (tiene que ir ANTES de cualquier make) ---
export CCACHE_DIR=${CCACHE_DIR:-$HOME/.cache/ccache-uke}
export CCACHE_BASEDIR=$R
export CC="ccache clang"
export HOSTCC="ccache gcc"
command -v ccache >/dev/null || fail "ccache no instalado"
say "==ccache (antes)== $(ccache -s 2>/dev/null | tr '\n' ' ' | cut -c1-200)"

say "==-config (tag=$TAG src=$SRC out=$O)--"
mkdir -p "$O"
cp -f "$CFG" "$O/.config"
cd "$SRC"
export MAKE=/usr/bin/make
export ARCH=arm64
export LLVM=1
export KBUILD_BUILD_USER=uke
export KBUILD_BUILD_HOST=palawan
# Fijo para hits reproducibles: solo entra en UTS_VERSION (banner/version.o).
export KBUILD_BUILD_TIMESTAMP="Fri Oct 10 12:00:00 CEST 2026"

say "==olddefconfig=="
make O="$O" olddefconfig

# --- GATES DE CONFIG (identicos a build-k52L11.sh) ---
grep -qE '^CONFIG_ARCH_QCOM=y' "$O/.config" || fail "falta CONFIG_ARCH_QCOM en $O/.config"
say "OK  CONFIG_ARCH_QCOM=y"
grep -qE '^CONFIG_INITRAMFS_SOURCE=".*uke-k52b2-diag-initramfs.cpio.gz"' "$O/.config" \
	|| fail "INITRAMFS_SOURCE no apunta al cpio K52b2-diag (fw GPU + UKE-DIAG)"
for f in gen71100_sqe.fw gen71100_gmu.bin gen71100_zap.mbn; do
	gzip -dc "$R/build/init/uke-k52b2-diag-initramfs.cpio.gz" | cpio -it 2>/dev/null \
		| grep -qx "lib/firmware/qcom/$f" || fail "el cpio K34-fw no lleva lib/firmware/qcom/$f"
done
say "OK  INITRAMFS_SOURCE -> cpio K34-fw, y el fw GPU esta DENTRO (K43)"
grep -qE '^CONFIG_INITRAMFS_COMPRESSION_GZIP=y' "$O/.config" \
	|| fail "falta CONFIG_INITRAMFS_COMPRESSION_GZIP"
say "OK  INITRAMFS_COMPRESSION_GZIP=y"

say "==L11-NOGOTO/L11-POLL: gates de fuente (el arbol tiene que ser L11 o posterior)=="
[ "$(grep -c '^[[:space:]]*goto uke_l8_nopoll_done;' "$SRC/drivers/gpu/drm/msm/adreno/a6xx_gmu.c")" = "0" ] \
	|| fail "L11-NOGOTO: el arbol $SRC aun lleva el goto nopoll-ok (es L10, no L11)"
say "OK  L11-NOGOTO: sin goto uke_l8_nopoll_done en a6xx_gmu.c"
grep -q '(val & 0x1ff) == 0x100, 100, 100000' "$SRC/drivers/gpu/drm/msm/adreno/a6xx_gmu.c" \
	|| fail "L11-POLL: falta la condicion VENDOR (val&0x1ff)==0x100 en el poll S4"
say "OK  L11-POLL: poll S4 con condicion VENDOR bit8 (100,100000)"
grep -q 'uke_poke("L11-pollok")' "$SRC/drivers/gpu/drm/msm/adreno/a6xx_gmu.c" \
	|| fail "L11-POLL: falta el poke L11-pollok en la fuente"
say "OK  L11-POLL: poke L11-pollok presente en la fuente"

# Gates extra solo para TAG L12*: el hunk PRE-L12-FW (fwmap/fwbody) tiene que
# estar en la fuente. L11 no los lleva, por eso van condicionados al tag.
case "$TAG" in
	*L12*)
		say "==L12-FWMAP: gates de fuente extra (tag $TAG)=="
		grep -q 'uke_poke("L12-fwmap")' "$SRC/drivers/gpu/drm/msm/adreno/a6xx_gmu.c" \
			|| fail "L12-FWMAP: falta el poke L12-fwmap en la fuente"
		say "OK  L12-FWMAP: poke L12-fwmap presente en la fuente"
		grep -q 'UKE-L12: fwmap' "$SRC/drivers/gpu/drm/msm/adreno/a6xx_gmu.c" \
			|| fail "L12-FWMAP: falta el pr_err UKE-L12: fwmap"
		say "OK  L12-FWMAP: pr_err fwmap presente en la fuente"
		grep -q 'UKE-L12: fwbody' "$SRC/drivers/gpu/drm/msm/adreno/a6xx_gmu.c" \
			|| fail "L12-FWMAP: falta el pr_err UKE-L12: fwbody"
		say "OK  L12-FWMAP: pr_err fwbody presente en la fuente"
		;;
esac

if [ "${GATES_ONLY:-0}" -eq 1 ]; then
	say "GATES-ONLY: config+fuente OK; llegaria al make:"
	say "GATES-ONLY: make O=\"$O\" -j$JOBS CC=\"$CC\" HOSTCC=\"$HOSTCC\" Image.gz"
	say "DONE $TAG-GATES-OK"
	exit 0
fi

say "==make Image.gz -j$JOBS con ccache (esto es lo lento la 1a vez)== "
# CC/HOSTCC van EN LA LINEA (no basta export: Kbuild reasigna CC=clang en la
# ruta LLVM=1 e ignora el env; sin esto ccache queda bypassed: 0 objetos
# cacheados, verificado en el primer intento L12 por .cmd + ccache -s).
make O="$O" -j"$JOBS" CC="$CC" HOSTCC="$HOSTCC" Image.gz

IMG=$O/arch/arm64/boot/Image
IMGZ=$O/arch/arm64/boot/Image.gz
[ -f "$IMG" ] || fail "el build no produjo $IMG"
[ -f "$IMGZ" ] || fail "el build no produjo $IMGZ (el repack lo necesita)"
[ "$IMG" -nt "$O/.config" ] || fail "Image mas viejo que .config: el build no reconstruyo nada"
say "OK  Image $(stat -c%s "$IMG") B, mas nuevo que .config"

# --- GATES DE MARCADORES: copiados de build-k52L11.sh ---
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
    b'UKE-K25: volcado SMMU DESACTIVADO': 'el volcado SMMU apagado (test H2)',
    b'uke_smmu_dump':               'el parametro conmutable del volcado',
    b'UKE-K38: attach dev=%s id[': 'la sonda SME(SID)->CBnDx (nudo del cuelgue S3-rst0)',
    b'WALK iova=0x%llx':             'el caminador de tabla (C1)',
    b'MAPPING ENCONTRADO':           'desenlace positivo del walk',
    b'veredicto=%s':                 'veredicto explicito del dtcm-magic',
    b'UKE-K33: dev=%s NO es la GPU': 'el fix de fondo: quitar TTBR1 al GMU',
    b'UKE-K32: RESULTADO':           'la sonda que resuelve el nudo (a) vs (b)',
    b'UKE-K32: init_context':        'la sonda: SID y quirks del dominio',
    b'gmu init ret=%d':               'el camino de error del GMU sigue en su sitio',
    b'UKE-K41: consola tope=%d':      'el marcador del tope de consola (pr_warn en console_init)',
    b'\x013UKE-POKE: %s':            'uke_poke como pr_err (nivel 3 < 4: PASA el tope de K41)',
    b'UKE-K44 A: rst=':              'la sonda de registros del CM3 (ledger #499)',
    b'K47-crtc-en':                   'miga: dpu_crtc_enable (ledger #502; el nombre en fuente sigue K47)',
    b'K47-7nm-en':                    'miga: dsi_7nm_phy_enable (nombre en fuente K47)',
    b'UKE-K49: esd gpio %d -> irq %d ARMADA val=%d': 'probe: irq ESD armada',
    b'UKE-K49: ESD irq %d! gpio idx %d val=%d':      'ISR: aseveracion ESD',
    b'UKE-K49: sin esd-err-gpios en DT':             'rama DT-viejo (control)',
    b'K49-esd-armado':               'poke al final del registro ESD',
    b'K47-pll-prep':                  'miga: pll vco prepare (nombre en fuente K47)',
    b'UKE-K42: entrando en adreno_bind': 'el marcador VISIBLE del ladder (pr_warn en adreno_bind)',
    b'UKE-K17: dtcmR val=':            'dtcmR K17 original (L0 lo lleva; K58 lo renombro despues)',
    b'UKE-L2: D1 gmu clk_set 220M rc=%d': 'D1: core a 220M (testigo L2 verbatim)',
    b'UKE-K68: D2 hub clk_set 200M rc=%d': 'D2: hub a 200M (testigo L4a/K68 verbatim)',
    b'UKE-K65: D3 cx LOW_SVS opp_set_rate 220M rc=%d': 'D3: voto CX-OPP 220M (testigo L4c/K65 verbatim)',
    b'UKE-L6: open-enter': 'L6: entrada de msm_open',
    b'UKE-L6: fw-enter': 'L6: entrada de adreno_load_fw',
    b'UKE-L6: fw-exit-ok': 'L6: salida de adreno_load_fw',
    b'UKE-L6: ucode-enter': 'L6: entrada de ucode_load',
    b'UKE-L6: ucode-exit-ok': 'L6: salida de ucode_load',
    b'UKE-L6: rpm-enter': 'L6: entrada de pm_runtime_get_sync',
    b'UKE-L6: rpm-exit-ok': 'L6: salida de pm_runtime_get_sync',
    b'UKE-L6: hwinit-enter': 'L6: entrada de msm_gpu_hw_init',
    b'UKE-L6: gmu-pm-resume-enter': 'L6: corre a6xx_gmu_pm_resume (via GMU)',
    b'UKE-L6: pm-resume-enter': 'L6: corre a6xx_pm_resume (via sin-GMU)',
    b'UKE-L6: gmu-resume-enter': 'L6: entrada de a6xx_gmu_resume pre-WARN',
    b'UKE-L7: k44b-ok': 'L7: tras K44-B (ITCM)',
    b'UKE-L7: k44c-ok': 'L7: tras K44-C (icache/dcache/sysbus)',
    b'UKE-L7: k44d-ok': 'L7: tras K44-D (HFI)',
    b'UKE-L7: k44e-ok': 'L7: tras K44-E (fence)',
    b'UKE-L7: k25-ok': 'L7: tras el bloque K25',
    b'UKE-L7: pre-rst': 'L7: antes del write SYSRESET=0',
    b'UKE-L7: post-rst': 'L7: entre el write y S3 (write vs poll)',
    b'UKE-L8: write-done': 'L8: write SYSRESET=0 ejecutado, CM3 suelto',
    b'UKE-L8: nopoll-ok': 'L8/L11: epilogo FW_START (en L11: tras poll VENDOR)',
    b'L10-gbif': 'L10: GBIF saneado (C1)',
    b'L10-recfg': 'L10: CM3 re-programado (C2)',
    b'UKE-L10: gbif-ok': 'L10: pr_err tras GBIF (C1)',
    b'UKE-L10: recfg-ok': 'L10: pr_err tras reconfig (C2)',
    b'L11-pollok': 'L11: poll VENDOR superado (fw-vivo)',
    b'UKE-L11: pollok': 'L11: pr_err tras poll VENDOR superado',
}
mustnt = {
    b'0x200000;':                    'ioremap de 2 MB de K23 (fuera del recurso)',
    b'\x014UKE-POKE: %s':            'la forma pr_warn del uke_poke (nivel 4: el tope la OCULTA, K42 la llevaba)',
    b'uke_k19_dump_desc(e[4]':      'volcado plano e[4] (leia basura: fuera de la tabla)',
    b'UKE-K55':                      'ventana CB K55 (posterior)',
    b'UKE-K56':                      'hunks K56 (posterior)',
    b'UKE-K57':                      'one-liner K57 (posterior)',
    b'UKE-K58':                      'renombre K58 (posterior; L1 lleva K17 original)',
    b'UKE-K59':                      'map K59 (posterior)',
    b'UKE-K60':                      'hunk RSC/PDC K60 (posterior)',
    b'UKE-K61':                      'megabloque K61 (posterior)',
    b'UKE-K62':                      'rescue/hold K62 (posterior)',
    b'UKE-K63':                      'breadcrumb K63 (posterior)',
    b'UKE-K64':                      'register_config K64 (dominio L1, no L5)',
    b'register_config':              'frame K64/L1 (ausente en L0 y L5)',
    b'UKE-K65: D1':                  'D1 de k65 (L5 lleva D1 con prefijo UKE-L2)',
    b'UKE-K65: D2':                  'D2 de k65 (L5 lleva D2 con prefijo UKE-K68)',
    b'UKE-K66:':                     'rama K66 chipid/poll (posterior)',
    b'UKE-K67:':                     'rama K67 D1-solo (posterior)',
    b'UKE-L2: SIN-D2':               'linea SIN-D2 del diff-solo (eliminada en L5)',
    b'UKE-L2: SIN-D3':               'linea SIN-D3 del diff-solo (eliminada en L5)',
    b'UKE-K68: SIN-D1':              'linea SIN-D1 del diff-solo (eliminada en L5)',
    b'UKE-K68: GENERAL_10':          'G10 de k68 (L5 es SIN-G10)',
    b'UKE-K68: GENERAL_8':           'G8 de k68 (idem)',
    b'UKE-K68: poll vendor':         'poll de k68 (idem)',
    b'UKE-K70':                      'plan-C C2 K70 (posterior)',
    b'UKE-C1':                       'voto RDPM C1 (posterior; dominio L3)',
    b'UKE-C3':                       'stub C3 (posterior)',
    b'UKE-L1:':                      'hunk del gemelo L1 (su arbol, no el mio)',
    b'uke_s3_stage':                 'params staged K61 (posterior)',
    b'uke_rescue':                   'rescue K61/K62 (posterior)',
    b'poll vendor':                  'poll vendor K66/K68 (L5 es SIN-poll)',
    b'GENERAL_10':                   'chipid G10 (L5 es SIN-G10)',
    b'GENERAL_8':                    'log G8 (L5 es SIN-G8)',
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

# Marcadores L12 en binario (solo tag L12*): el hunk fwmap deja 3 cadenas.
case "$TAG" in
	*L12*)
		python3 - "$IMG" <<'PY'
import sys
raw = open(sys.argv[1], 'rb').read()
for tok in (b'L12-fwmap', b'UKE-L12: fwmap', b'UKE-L12: fwbody'):
    c = raw.count(tok)
    print('GATE L12-BIN: %r x%d' % (tok, c))
    if c < 1:
        sys.exit(1)
PY
		[ $? -eq 0 ] || fail "gates L12 en binario fallidos"
		;;
esac

say "==L11-WRITE: desensamblado de a6xx_gmu_start (vmlinux)=="
python3 - "$O/vmlinux" <<'PY'
import re, subprocess, sys
vmlinux = sys.argv[1]
raw = open(vmlinux, 'rb').read()
offs = {}
for s in (b'L7-pre-rst\x00', b'L8-write-done\x00'):
    c = raw.count(s)
    if c != 1:
        print('GATE L11-WRITE: cadena %r aparece x%d (esperado x1)' % (s, c))
        sys.exit(1)
    offs[s] = raw.find(s)
    print('GATE L11-WRITE: %r x1 fileoff=%d' % (s, offs[s]))
loads = []
out = subprocess.run(['readelf', '-lW', vmlinux], capture_output=True, text=True)
for line in out.stdout.splitlines():
    m = re.match(r'\s*LOAD\s+(0x[0-9a-f]+)\s+(0x[0-9a-f]+)\s+(0x[0-9a-f]+)\s+(0x[0-9a-f]+)', line)
    if m:
        loads.append((int(m.group(1), 16), int(m.group(2), 16), int(m.group(4), 16)))
def to_vaddr(off):
    for base, virt, siz in loads:
        if base <= off < base + siz:
            return virt + (off - base)
    print('GATE L11-WRITE: off %d fuera de todo LOAD' % off)
    sys.exit(1)
pre_addr = to_vaddr(offs[b'L7-pre-rst\x00'])
done_addr = to_vaddr(offs[b'L8-write-done\x00'])
print('GATE L11-WRITE: vaddrs pre-rst=%x write-done=%x' % (pre_addr, done_addr))
dis = subprocess.run(['llvm-objdump', '-d', '--disassemble=a6xx_gmu_start', vmlinux],
                     capture_output=True, text=True)
if dis.returncode != 0 or 'a6xx_gmu_start>:' not in dis.stdout:
    print('GATE L11-WRITE: llvm-objdump no desensamblo a6xx_gmu_start')
    print(dis.stderr[-2000:])
    sys.exit(1)
insns = []
for line in dis.stdout.splitlines():
    m = re.match(r'^\s*([0-9a-f]+):\s+([0-9a-f ]+)\s+(.*)$', line)
    if m:
        insns.append((int(m.group(1), 16), m.group(3).strip()))
adrp_page = {}
targets = {}
for i, (addr, t) in enumerate(insns):
    m = re.match(r'adrp\s+(x\d+),\s*(-?0x[0-9a-f]+)', t)
    if m:
        adrp_page[m.group(1)] = int(m.group(2), 16) & ~0xfff
        continue
    m = re.match(r'add\s+(x\d+),\s*(x\d+),\s*#?(0x[0-9a-f]+|\d+)', t)
    if m and m.group(1) == m.group(2) and m.group(2) in adrp_page:
        targets[i] = adrp_page[m.group(2)] + int(m.group(3), 16)
pre_add = done_adrp = None
for i, a in targets.items():
    if a == pre_addr:
        pre_add = i
    elif a == done_addr:
        done_adrp = i
if pre_add is None or done_adrp is None or done_adrp < pre_add:
    print('GATE L11-WRITE: anclas pre-rst/write-done no localizadas '
          '(pre_add=%s done_adrp=%s)' % (pre_add, done_adrp))
    sys.exit(1)
flush_bl = None
for i in range(pre_add, done_adrp):
    if re.match(r'bl\s+.*\bpr_flush\b', insns[i][1]):
        flush_bl = i
        break
if flush_bl is None:
    print('GATE L11-WRITE: sin `bl pr_flush` entre pre-rst y write-done')
    sys.exit(1)
done_bl = None
for i in range(done_adrp, len(insns)):
    if re.match(r'bl\s+.*\buke_poke\b', insns[i][1]):
        done_bl = i
        break
if done_bl is None:
    print('GATE L11-WRITE: sin `bl uke_poke` tras write-done')
    sys.exit(1)
window = insns[flush_bl + 1:done_bl]
print('GATE L11-WRITE: ventana pre-rst~write-done = %d insns:' % len(window))
for addr, t in window:
    print('    %x: %s' % (addr, t))
bad = [(a, t) for a, t in window
       if re.search(r'\bstr[bh]?\b[^;]*\[(?!sp[,\]])', t)]
if not bad:
    print('GATE L11-WRITE: FALLO: cero stores al MMIO entre pre-rst y write-done (el write NO volvio)')
    sys.exit(1)
print('GATE L11-WRITE: OK, %d store(s) al MMIO entre pre-rst y write-done (el write esta DE VUELTA):' % len(bad))
for a, t in bad:
    print('    %x: %s' % (a, t))
PY
[ $? -eq 0 ] || fail "gate L11-WRITE fallido (el write NO esta en el binario)"

say "==K43: gates de nivel del uke_poke (err presente / warn ausente)=="
say "==sha del kernel y del initramfs embebido=="
sha256sum "$IMG" "$IMGZ"
say "==initramfs embebido (cpio K34-fw 6-oct, el que exige el gate)=="
sha256sum "$R/build/init/uke-k52b2-diag-initramfs.cpio.gz"
say "==ccache (despues)=="
ccache -s || true
say "DONE $TAG-BUILD-OK"
