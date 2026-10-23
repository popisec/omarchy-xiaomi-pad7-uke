#!/bin/bash
# build-k52L11.sh — L11 = L10 + poll VENDOR + HFI (10-oct-2026).
# Clon de build-k52L10.sh: MISMO arbol L10 MAS el hunk unico tras S3
# (build/gates/patches/k52L11-vendorpoll.diff): (1) ELIMINA el `goto
# uke_l8_nopoll_done` (bypass temporal L8/L10 del poll S4); (2) el poll S4
# pasa del criterio DTCM-magic (nunca cuadra, nota K23b) a la condicion
# VENDOR (val&0x1ff)==0x100 (FW_INIT_RESULT bit 8, fw-vivo; timing
# (100,100000) IDENTICO al vendor); (3) poke L11-pollok + pr_err + flush
# tras poll exitoso, antes de K44'; (4) la etiqueta queda como EPILOGO COMUN
# con `ret = 0` para DEJAR SEGUIR al camino HFI existente (fw_start ->
# hfi_start). C1+C2, write, wmb(), pokes L6-L10, S3 intactos.
# Si HFI queues OK / hw_init completo => GPU VIVA; si poll timeout
# (S4-pollFAIL sin L11-pollok) con CM3 suelto => el fw no responde
# (falta carga fw en ITCM o SMMU SID5).
#
#   fuente  = build/kernel-pokes/k52-L11-tree (cp -a de k52-L10-tree + diff
#             propio k52L11-vendorpoll.diff)
#   config  = build/kernel-config/k52L11-bateria.config (= k52L10: cpio 6-oct)
#   salida  = build/kernel-pokes/k52L11-build
# Gates: perfil L0 (V1) + UKE-L2/D1 + UKE-K68/D2 + UKE-K65/D3 + 11 UKE-L6 +
# 7 UKE-L7 + 2 UKE-L8 + 4 UKE-L10 (gbif/recfg args + pr_err) + 2 UKE-L11
# (pollok arg + pr_err) + negativos de
# familia SALVO los 3 testigos L5 (V2-L5) + gate L11-WRITE por desensamblado
# (el `str` del write tiene que SEGUIR) + gates de fuente L11-NOGOTO/L11-POLL.
#
# POR QUÉ ESTE SCRIPT (1-oct-2026). Antes el kernel se compilaba a mano y el
# arbol instrumentado vivia solo en build/kernel-pokes/k52-L0-tree/, que esta en
# .gitignore y no tiene ningun diff guardado: el K23 no era reconstruible desde
# el repo. Este script cierra el hueco:
#   fuente  = build/kernel-pokes/k52-L0-tree  (k13-tree + ACUMULADO-...-a-k24.diff +
#             los cambios K25..K42 QUE SOLO VIVEN EN EL ARBOL — hueco reconocido en
#             #492-errata; el delta K42->K43 SI queda versionado:
#             build/gates/patches/k43-uke-poke-pr-err.diff)
#   config  = build/kernel-config/k52L0-bateria.config  (VERSIONADO; trae
#             INITRAMFS_SOURCE -> build/init/uke-k22-initramfs.cpio.gz, que es
#             lo que hornea los 3 firmware de la GPU en el initramfs)
#   salida  = build/kernel-pokes/k52L0-build
# Repack: docs/historia/gates-palawan/repack-k18.py --out boot-ukek49-pantalla.img
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
SRC=$R/build/kernel-pokes/k52-L11-tree
O=$R/build/kernel-pokes/k52L11-build
CFG=$R/build/kernel-config/k52L11-bateria.config
LOG=$R/build/logs/build-k52L11.log

if [ -z "${UKE_BUILD_DETACHED:-}" ]; then
	mkdir -p "$(dirname "$LOG")"
	export UKE_BUILD_DETACHED=1
	setsid nohup "$0" "$@" >>"$LOG" 2>&1 &
	disown || true
	echo "build L11 desprendido (pid $!); log en $LOG"
	exit 0
fi

say() { echo "[$(date +%H:%M:%S)] $*"; }
fail() { say "ABORT: $*"; exit 1; }

[ -d "$SRC" ] || fail "no existe el arbol fuente $SRC"
[ -f "$CFG" ] || fail "no existe el config versionado $CFG"
[ -f "$R/build/init/uke-k34-fw-k52b2-initramfs.cpio.gz" ] || fail "falta el cpio K34-fw (cpio K12 + fw GPU)"

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
grep -qE '^CONFIG_INITRAMFS_SOURCE=".*uke-k34-fw-k52b2-initramfs.cpio.gz"' "$O/.config" \
	|| fail "INITRAMFS_SOURCE no apunta al cpio K34-fw (con fw GPU)"
# UKE-K42: el cpio tiene que LLEVAR el firmware DENTRO, que es el punto del ciclo:
# el DPU lo pide a los ~4 s, antes de montar la rootfs.
for f in gen71100_sqe.fw gen71100_gmu.bin gen71100_zap.mbn; do
	gzip -dc "$R/build/init/uke-k34-fw-k52b2-initramfs.cpio.gz" | cpio -it 2>/dev/null \
		| grep -qx "lib/firmware/qcom/$f" || fail "el cpio K34-fw no lleva lib/firmware/qcom/$f"
done
say "OK  INITRAMFS_SOURCE -> cpio K34-fw, y el fw GPU esta DENTRO (K43)"
grep -qE '^CONFIG_INITRAMFS_COMPRESSION_GZIP=y' "$O/.config" \
	|| fail "falta CONFIG_INITRAMFS_COMPRESSION_GZIP"
say "OK  INITRAMFS_COMPRESSION_GZIP=y"

say "==L11-NOGOTO/L11-POLL: gates de fuente (el arbol tiene que ser L11)=="
# El bypass L8/L10 tiene que estar ELIMINADO (el `goto` pelado, no la
# etiqueta, que queda como epilogo comun). Si el arbol fuera L10, el build
# de 15 min seria rancio: se aborta aqui.
[ "$(grep -c '^[[:space:]]*goto uke_l8_nopoll_done;' "$SRC/drivers/gpu/drm/msm/adreno/a6xx_gmu.c")" = "0" ] \
	|| fail "L11-NOGOTO: el arbol $SRC aun lleva el goto nopoll-ok (es L10, no L11)"
say "OK  L11-NOGOTO: sin goto uke_l8_nopoll_done en a6xx_gmu.c"
grep -q '(val & 0x1ff) == 0x100, 100, 100000' "$SRC/drivers/gpu/drm/msm/adreno/a6xx_gmu.c" \
	|| fail "L11-POLL: falta la condicion VENDOR (val&0x1ff)==0x100 en el poll S4"
say "OK  L11-POLL: poll S4 con condicion VENDOR bit8 (100,100000)"
grep -q 'uke_poke("L11-pollok")' "$SRC/drivers/gpu/drm/msm/adreno/a6xx_gmu.c" \
	|| fail "L11-POLL: falta el poke L11-pollok en la fuente"
say "OK  L11-POLL: poke L11-pollok presente en la fuente"

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
    b'UKE-K17: dtcmR val=':            'dtcmR K17 original (L0 lo lleva; K58 lo renombro despues)',
    # --- UKE-L5 (9-oct, L5=D1+D2+D3): testigos discriminadores verbatim de
    # los 3 diffs-solo (las lineas SIN-D2/SIN-D1/SIN-D3 se ELIMINAN por
    # falsas en combinacion; ver mustnt V2-L5).
    b'UKE-L2: D1 gmu clk_set 220M rc=%d': 'D1: core a 220M (testigo L2 verbatim)',
    b'UKE-K68: D2 hub clk_set 200M rc=%d': 'D2: hub a 200M (testigo L4a/K68 verbatim)',
    b'UKE-K65: D3 cx LOW_SVS opp_set_rate 220M rc=%d': 'D3: voto CX-OPP 220M (testigo L4c/K65 verbatim)',
    # --- UKE-L6 (10-oct, L6=L5+openpokes): los 11 testigos del tramo ciego,
    # cada uno pr_err + pr_flush(120) para sobrevivir al cuelgue en la ACM.
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
    # --- UKE-L7 (10-oct, L7=L6+s2s3): los 7 testigos del tramo K44→S3,
    # cada uno pr_err + pr_flush(120) para sobrevivir al cuelgue en la ACM.
    b'UKE-L7: k44b-ok': 'L7: tras K44-B (ITCM)',
    b'UKE-L7: k44c-ok': 'L7: tras K44-C (icache/dcache/sysbus)',
    b'UKE-L7: k44d-ok': 'L7: tras K44-D (HFI)',
    b'UKE-L7: k44e-ok': 'L7: tras K44-E (fence)',
    b'UKE-L7: k25-ok': 'L7: tras el bloque K25',
    b'UKE-L7: pre-rst': 'L7: antes del write SYSRESET=0',
    b'UKE-L7: post-rst': 'L7: entre el write y S3 (write vs poll)',
    # --- UKE-L8 (10-oct, L8=L7+nopoll): bypass temporal del poll S4.
    # L10 lo conserva TODO (write RESTAURADO + write-done/nopoll-ok x1) y suma
    # el fix vendor C1+C2. L11 ELIMINA el `goto` pero CONSERVA la etiqueta
    # como epilogo comun (las cadenas write-done/nopoll-ok SIGUEN x1 en el
    # binario; en traza L11 nopoll-ok = "epilogo post-poll", no "salto").
    # write-done sale justo tras el write (pre-rst sin write-done => mata
    # el write); el discriminador del poll es S4-pollOK/FAIL + L11-pollok.
    b'UKE-L8: write-done': 'L8: write SYSRESET=0 ejecutado, CM3 suelto',
    b'UKE-L8: nopoll-ok': 'L8/L11: epilogo FW_START (en L11: tras poll VENDOR)',
    # --- UKE-L10 (10-oct, L10=L9+fix vendor C1+C2 §3 CRITICA-HW): los 4
    # testigos del hunk pre-release (args de poke + pr_err, x1 c/u).
    b'L10-gbif': 'L10: GBIF saneado (C1)',
    b'L10-recfg': 'L10: CM3 re-programado (C2)',
    b'UKE-L10: gbif-ok': 'L10: pr_err tras GBIF (C1)',
    b'UKE-L10: recfg-ok': 'L10: pr_err tras reconfig (C2)',
    # --- UKE-L11 (10-oct, L11=L10+poll VENDOR): los 2 testigos del poll
    # real (arg del poke + pr_err, x1 c/u). Salen SOLO si el fw responde
    # (bit 8 de FW_INIT_RESULT); su ausencia con CM3 suelto = fw mudo.
    b'L11-pollok': 'L11: poll VENDOR superado (fw-vivo)',
    b'UKE-L11: pollok': 'L11: pr_err tras poll VENDOR superado',
    # NO se gatea `uke_ignore_always_dump` POR TEXTO: es un `static bool = true` y el
    # compilador lo constante-pliega, asi que el simbolo NO aparece en el Image (lo
    # cazó este gate en el intento 1, build-k42-intento1-fallido.log). Misma leccion
    # que el unwind blindado. Lo que se gatea es el marcador, y el "ignorar el
    # always_kmsg_dump del ABL" se verifica leyendo el diff, no el binario.
}
mustnt = {
    b'0x200000;':                    'ioremap de 2 MB de K23 (fuera del recurso)',
    b'\x014UKE-POKE: %s':            'la forma pr_warn del uke_poke (nivel 4: el tope la OCULTA, K42 la llevaba)', \
    # UKE-K25: el volcado plano que leia basura NO debe seguir presente.
    b'uke_k19_dump_desc(e[4]':      'volcado plano e[4] (leia basura: fuera de la tabla)',
    # UKE-L5 (V2-L5): familia posterior AUSENTE, SALVO los 3 testigos L5.
    # Los negativos genericos 'D1 gmu'/'D2 hub'/'D3 cx'/'UKE-K65:'/'UKE-K68:'
    # se RETIRAN porque los testigos L5 los contienen; la ausencia de D
    # ajeno la cubren los testigos ESPECIFICOS (k65-D1/k65-D2/K66/K67/
    # K68-SIN-D1/G10/G8/poll/L2-SIN-D2/L2-SIN-D3). Todo lo demas es fuga.
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
    # UKE-L10 introduce "UKE-L10: ..." que CONTIENE el substring "UKE-L1":
    # el negativo se ancla con ':' (todos los pr_err del linaje usan
    # "UKE-Lx: ", asi que el hunk del gemelo L1 seguiria cazandose).
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

say "==L11-WRITE: desensamblado de a6xx_gmu_start (vmlinux)=="
# El write gmu_write(SYSRESET,0) RESTAURADO es un writel => un `str w?, [xMMIO, #off]`.
# Entre el `bl pr_flush` del bloque pre-rst y el `bl uke_poke` que consume
# "L8-write-done" tiene que haber AL MENOS UN store con base != sp (en L9 la
# ventana eran 2 insns sin stores; el control negativo de L9 cazo `str w20, [x8]`).
# Anclas por cadenas exactas (cada una x1 en el binario): el arg del poke
# "L7-pre-rst"/"L8-write-done" (los pr_err usan "UKE-L7: pre-rst", distinto).
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
# fileoff -> vaddr via PT_LOAD (los adrp/add del desensamblado dan vaddrs)
loads = []
out = subprocess.run(['readelf', '-lW', vmlinux], capture_output=True, text=True)
for line in out.stdout.splitlines():
    m = re.match(r'\s*LOAD\s+(0x[0-9a-f]+)\s+(0x[0-9a-f]+)\s+(0x[0-9a-f]+)\s+(0x[0-9a-f]+)', line)
    if m:
        loads.append((int(m.group(1), 16), int(m.group(2), 16), int(m.group(4), 16)))
def to_vaddr(off):
    # el segmento cuyo rango [base, base+filesiz) contiene off
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
insns = []  # (addr, texto)
for line in dis.stdout.splitlines():
    m = re.match(r'^\s*([0-9a-f]+):\s+([0-9a-f ]+)\s+(.*)$', line)
    if m:
        insns.append((int(m.group(1), 16), m.group(3).strip()))
# adrp+add -> direccion de la cadena cargada en x0 (arg del uke_poke).
# OJO: llvm-objdump ya muestra en el adrp la pagina ABSOLUTA resuelta, no el
# inmediato relativo: la pagina ES el operando (mascara 4K por seguridad).
adrp_page = {}
targets = {}  # indice de insn 'add' -> direccion destino
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
# bl pr_flush posterior al poke pre-rst (el flush de su bloque)
flush_bl = None
for i in range(pre_add, done_adrp):
    if re.match(r'bl\s+.*\bpr_flush\b', insns[i][1]):
        flush_bl = i
        break
if flush_bl is None:
    print('GATE L11-WRITE: sin `bl pr_flush` entre pre-rst y write-done')
    sys.exit(1)
# El compilador INTERCALA codigo (visto en L8: el adrp/add de "write-done"
# queda entre el dmb y el str del writel), asi que la ventana llega hasta el
# `bl uke_poke` que CONSUME la cadena write-done, no hasta su adrp.
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
# (ya comprobados arriba sobre el Image crudo)
say "==sha del kernel y del initramfs embebido=="
sha256sum "$IMG" "$IMGZ"
say "==initramfs embebido (cpio K34-fw 6-oct, el que exige el gate)=="
sha256sum "$R/build/init/uke-k34-fw-k52b2-initramfs.cpio.gz"
say "DONE L11-BUILD-OK"
