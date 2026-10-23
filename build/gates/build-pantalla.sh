#!/bin/bash
# build-pantalla.sh — construye el kernel PANTALLA (K27 + PHY del 2º DSI) desde CERO.
#
# POR QUÉ ESTE SCRIPT (2-oct-2026). El panel de la tablet es DUAL-DSI
# (`qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid`): necesita los DOS enlaces. El
# segundo (mdss_dsi1/ae96000) no tenia su PHY habilitada y el arranque daba
#   msm_dsi ae96000.dsi: *ERROR* dsi_get_phy: phy driver is not ready
# con el connector en `disconnected`. El orquestador ya cambió en
# build/kernel-pokes/k18-tree/.../palawan.dtsi el nodo mdss_dsi1_phy
# (phy@ae97000) de `disabled` a `okay` (comentario UKE-K29). Este script NO toca
# ese árbol (solo lo LEE vía `make O=...`, compilación fuera del árbol): su
# trabajo es demostrar con gates que el binario lleva ese cambio y ningún otro.
#
#   fuente  = build/kernel-pokes/k18-tree  (SOLO LECTURA; propiedad del orquestador)
#   config  = build/kernel-config/pantalla.config  (copia verbatim de k27.config)
#   salida  = build/kernel-pokes/pantalla-build    (directorio NUEVO)
# Repack (lo hace el orquestador, no este script):
#   docs/historia/gates-palawan/repack-k18.py --out boot-ukepantalla.img ...
#
# REGLAS QUE ESTE SCRIPT RESPETA (por eso son gates, no comentarios):
#   - Build DESPRENDIDO: en primer plano el make es un no-op silencioso y un
#     "OK" vacio es indistinguible de un build real (REGLAS.md §1.6).
#   - MAKE/ARCH/LLVM explícitos + KBUILD_BUILD_USER/HOST (REGLAS.md §1.6).
#   - Gates de config de k27 (ARCH_QCOM / INITRAMFS_SOURCE / COMPRESSION_GZIP).
#   - Gate DT sobre el .dtb compilado (ver bloque GATE-DT abajo).
set -euo pipefail

R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
SRC=$R/build/kernel-pokes/k18-tree
O=$R/build/kernel-pokes/pantalla-build
CFG=$R/build/kernel-config/pantalla.config
LOG=$R/build/logs/build-pantalla.log
DTSI=$SRC/arch/arm64/boot/dts/qcom/palawan.dtsi

if [ -z "${UKE_BUILD_DETACHED:-}" ]; then
	mkdir -p "$(dirname "$LOG")"
	export UKE_BUILD_DETACHED=1
	setsid nohup "$0" "$@" >>"$LOG" 2>&1 &
	disown || true
	echo "build PANTALLA desprendido (pid $!); log en $LOG"
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
cd "$SRC"
export MAKE=/usr/bin/make
export ARCH=arm64
export LLVM=1
export KBUILD_BUILD_USER=uke
export KBUILD_BUILD_HOST=palawan

say "==olddefconfig=="
make O="$O" olddefconfig

# --- GATES DE CONFIG (antes de gastar 15 min de compilacion; heredados de k27) ---
grep -qE '^CONFIG_ARCH_QCOM=y' "$O/.config" || fail "falta CONFIG_ARCH_QCOM en $O/.config"
say "OK  CONFIG_ARCH_QCOM=y"
grep -qE '^CONFIG_INITRAMFS_SOURCE=".*uke-k22-initramfs.cpio.gz"' "$O/.config" \
	|| fail "INITRAMFS_SOURCE no apunta al cpio con los fw de la GPU (se perderia K22)"
say "OK  INITRAMFS_SOURCE -> cpio K22 (fw GPU dentro)"
grep -qE '^CONFIG_INITRAMFS_COMPRESSION_GZIP=y' "$O/.config" \
	|| fail "falta CONFIG_INITRAMFS_COMPRESSION_GZIP"
say "OK  INITRAMFS_COMPRESSION_GZIP=y"

say "==make dtbs (rapido: el gate DT falla ANTES del Image de 15 min)=="
make O="$O" dtbs
DTB=$O/arch/arm64/boot/dts/qcom/xiaomi-uke.dtb
[ -f "$DTB" ] || fail "el build no produjo $DTB"

# --- GATE-DT: el PHY del segundo DSI va habilitado en el DT compilado ---
# MÉTODO ELEGIDO: (a) `fdtget` sobre xiaomi-uke.dtb recién compilado.
#   POR QUÉ (a) Y NO (b):
#   - (a) lee la propiedad tal como la verá el kernel: post-DTC, con los
#     includes ya resueltos (xiaomi-uke.dts -> lamma.dtsi -> palawan.dtsi),
#     sin ruido de preprocesador ni comentarios. La ruta se averiguó con
#     `fdtget -l ... /soc/display-subsystem@ae00000` (hijos: dsi@ae94000,
#     phy@ae95000, dsi@ae96000, phy@ae97000) y se verificó contra el dtb de
#     k27-build: el método funciona (devuelve okay/disabled según el nodo).
#   - (b) buscar el texto en el Image embebido NO sirve: en este árbol el DT
#     viaja SEPARADO del Image (sección dtb del boot.img / dtbo), así que el
#     Image puede no contenerlo; y aunque lo contuviera, `status = "okay"` /
#     "disabled" son cadenas demasiado genéricas para grepear (aparecen en
#     restos de debug, __initdata y nodos no relacionados): presencia en el
#     Image no prueba qué dtb pasará el bootloader. (b) queda descartado.
P1=/soc/display-subsystem@ae00000/phy@ae97000
st1=$(fdtget "$DTB" "$P1" status 2>&1) || fail "fdtget no pudo leer $P1 status ($st1)"
[ "$st1" = "okay" ] || fail "phy@ae97000 status='$st1', se esperaba 'okay' (el cambio UKE-K29 no esta en el dtb)"
say "OK  GATE-DT positivo: phy@ae97000 (2º DSI) = okay"

# --- GATE NEGATIVO: el PHY del PRIMER DSI sigue disabled, y nada más cambió ---
# Vector completo de los 4 nodos display del DT compilado: si cualquier otro
# cambio de DT hubiera flipado un status (p. ej. habilitar dsi@ae96000 por
# error), este gate lo caza aunque el positivo siga verde.
exp_ok=1
for spec in "dsi@ae94000:disabled" "phy@ae95000:disabled" "dsi@ae96000:disabled"; do
	node=${spec%%:*}; want=${spec##*:}
	got=$(fdtget "$DTB" "/soc/display-subsystem@ae00000/$node" status 2>&1) \
		|| { say "GATE NEGATIVO: no se pudo leer $node ($got)"; exp_ok=0; continue; }
	if [ "$got" = "$want" ]; then
		say "OK  GATE negativo: $node = $want"
	else
		say "GATE NEGATIVO: $node='$got', se esperaba '$want'"
		exp_ok=0
	fi
done
[ "$exp_ok" = 1 ] || fail "gate negativo fallido (ver arriba)"

# Chequeo a nivel fuente (SOLO LECTURA del árbol del orquestador): el cambio es
# de un solo nodo. Se exige que el bloque mdss_dsi0_phy contenga
# `status = "disabled"`, que el bloque mdss_dsi1_phy contenga exactamente un
# `status = "okay"` y la marca UKE-K29 (ancla: es EL cambio conocido, no otro).
python3 - "$DTSI" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
def block(label):
    # Anclado a inicio de linea: mas arriba hay REFERENCIAS (&mdss_dsi0_phy en
    # assigned-clock-parents) que no son la definicion del nodo.
    m = re.search(r'^([ \t]*)' + re.escape(label) + r':[^\n]*\{', src, re.M)
    assert m, 'no se encuentra el nodo %s' % label
    start = m.end()
    # Los nodos PHY no tienen hijos: el primer cierre a su indentacion los termina.
    m2 = re.search(r'\n' + m.group(1) + r'\};', src[start:])
    assert m2, 'no se encuentra el cierre de %s' % label
    return src[start:start + m2.start()]
b0 = block('mdss_dsi0_phy')
b1 = block('mdss_dsi1_phy')
bad = []
if 'status = "disabled";' not in b0:
    bad.append('mdss_dsi0_phy NO contiene status = "disabled" (el 1er DSI se movio!)')
if b1.count('status = "okay";') != 1:
    bad.append('mdss_dsi1_phy no tiene EXACTAMENTE un status = "okay"')
if 'UKE-K29' not in b1:
    bad.append('mdss_dsi1_phy sin marca UKE-K29 (cambio desconocido, no el del orquestador)')
if bad:
    for b in bad:
        print('GATE FUENTE:', b)
    sys.exit(1)
print('GATE OK  fuente: dsi0_phy=disabled, dsi1_phy=okay x1, marca UKE-K29 presente')
PY
[ $? -eq 0 ] || fail "gate a nivel fuente fallido (ver arriba)"

# Comparación contra el dtb de referencia k27-build (fdtdump, determinista).
# LÍMITE EXPLÍCITO: NO existe ningún build "sin el cambio" contra el que
# comparar: el árbol fuente es COMPARTIDO y se mutó in situ (el dtb de k27-build
# se reconstruyó 7 s DESPUÉS del cambio: palawan.dtsi 02:04:20, xiaomi-uke.dtb
# 02:04:27 del 2-oct-2026), así que la referencia YA lleva el okay. Este gate
# NO prueba "pre vs post"; prueba "cero deriva desde el estado conocido": si el
# árbol se movió desde entonces, el diff lo muestra y se aborta.
REF=$R/build/kernel-pokes/k27-build/arch/arm64/boot/dts/qcom/xiaomi-uke.dtb
if [ -f "$REF" ]; then
	fdtdump "$REF" > "$O/.ref-fdtdump.txt"
	fdtdump "$DTB" > "$O/.new-fdtdump.txt"
	if diff -q "$O/.ref-fdtdump.txt" "$O/.new-fdtdump.txt" >/dev/null; then
		say "OK  sin deriva DT: fdtdump identico a la referencia k27-build (post-cambio)"
	else
		say "GATE DERIVA: el dtb difiere de la referencia k27-build:"
		diff "$O/.ref-fdtdump.txt" "$O/.new-fdtdump.txt" | head -30 | sed 's/^/    /'
		fail "deriva DT no explicada (el arbol se movio desde el estado conocido)"
	fi
else
	say "SKIP comparacion contra referencia: no existe $REF (comparar el .dtb"
	say "     nuevo contra un build sin el cambio es INVIABLE: no hay copia"
	say "     pristina pre-cambio del arbol; el gate que lo sustituye es el"
	say "     vector de 4 status + el chequeo fuente de un solo nodo, arriba)"
fi

say "==make Image.gz (esto es lo lento: $O se compila entero) =="
make O="$O" -j"$(nproc)" Image.gz

IMG=$O/arch/arm64/boot/Image
IMGZ=$O/arch/arm64/boot/Image.gz
[ -f "$IMG" ] || fail "el build no produjo $IMG"
[ -f "$IMGZ" ] || fail "el build no produjo $IMGZ (el repack lo necesita)"
[ "$IMG" -nt "$O/.config" ] || fail "Image mas viejo que .config: el build no reconstruyo nada"
say "OK  Image $(stat -c%s "$IMG") B, mas nuevo que .config"

# --- GATES DE MARCADORES (heredados de k27): el binario es el MISMO kernel ---
# instrumentado, solo cambia el DT. Si el árbol C se moviera, esto lo cazaría.
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
    b'UKE-K27: mmu de la GPU creado temprano': 'el fix de fondo UKE-K27 (mmu cacheado)',
    b'UKE-K25: volcado SMMU DESACTIVADO': 'el volcado SMMU sigue apagado (test H2)',
    b'uke_smmu_dump':               'el parametro conmutable del volcado',
}
mustnt = {
    b'0x200000;':                    'ioremap de 2 MB de K23 (fuera del recurso)',
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
say "==dtb con el PHY habilitado (lo que verifica el gate DT)=="
sha256sum "$DTB"
say "==initramfs embebido (debe ser el cpio K22, 08780e35…)=="
sha256sum "$R/build/init/uke-k22-initramfs.cpio.gz"
say "DONE PANTALLA-BUILD-OK"
