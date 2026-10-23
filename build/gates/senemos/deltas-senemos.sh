#!/usr/bin/env bash
# deltas-senemos.sh — aplica al árbol «senemos» los parches PROPIOS del proyecto.
#
# El árbol que produce `reproducir-arbol.sh` es el del upstream (MCC45TR
# @43e4036e) tal cual. Sobre él va lo nuestro:
#
#   0001-uke-abl-verdict-panic.patch   (este directorio) — el cuelgue mudo del
#       ABL: si el bootloader entrega un DT ajeno, panic() en vez de cpu_relax()
#       infinito. Sin este parche, un grafo rechazado deja la tablet muda y solo
#       sale con un reset fisico.
#
# Los demás parches propios viven en sus directorios de despliegue y se aplican
# con sus propios scripts (que son idempotentes):
#
#   build/rootfs/deploy/audio/kernel/deltas-omarchy-v4.sh   0002 + 0004
#       (SIDs de LPASS y de los compute-cb de FastRPC del ADSP)
#   build/rootfs/deploy/cameras/patches/0045-*, 0046-*       (cámaras)
#
# ORDEN: el del audio y el de las cámaras tocan ficheros distintos del
# uke-abl.c, así que da igual; pero se aplican en este orden porque es el que
# se usó el 17-oct.
#
# USO:
#   bash build/gates/senemos/deltas-senemos.sh [--tree DIR]
#   SENEMOS_TREE=/ruta/al/arbol bash build/gates/senemos/deltas-senemos.sh
set -Eeuo pipefail

R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
HERE="$R/build/gates/senemos"
TREE="${SENEMOS_TREE:-$R/build/kernel-pokes/senemos-7.2.9/linux-7.2.9}"
while [ $# -gt 0 ]; do
	case "$1" in
	--tree) TREE="$2"; shift 2 ;;
	*) echo "uso: $0 [--tree DIR]" >&2; exit 2 ;;
	esac
done

say() { printf '[deltas-senemos] %s\n' "$*"; }
[ -d "$TREE" ] || { say "no existe el arbol $TREE"; exit 1; }
[ -d "$TREE/.git" ] || { say "$TREE no parece un arbol de kernel (sin .git)"; exit 1; }

# ---- 0001: el veredicto del ABL (idempotente) ----
P="$HERE/patches/0001-uke-abl-verdict-panic.patch"
F="$TREE/arch/arm64/kernel/uke-abl.c"
if grep -q 'uke_abl_verdict_check' "$F"; then
	say "0001 ya aplicado (uku_abl_verdict_check presente)"
else
	git -C "$TREE" apply --check "$P" || { say "0001 no aplica limpio"; exit 1; }
	git -C "$TREE" apply "$P"
	say "0001 aplicado: panic() en vez del bucle mudo"
fi
grep -q 'uke_abl_verdict_check' "$F" || { say "el veredicto no esta en el arbol"; exit 1; }

# ---- audio: 0002 + 0004 (script propio, idempotente) ----
say "--- audio: deltas-omarchy-v4.sh (0002 + 0004) ---"
if [ -f "$R/build/rootfs/deploy/audio/kernel/deltas-omarchy-v4.sh" ]; then
	# el script de audio apunta a su propio arbol; aqui se le indica el bueno
	( cd "$R" && SENEMOS_TREE="$TREE" bash build/rootfs/deploy/audio/kernel/deltas-omarchy-v4.sh ) || {
		say "el delta de audio fallo (¿el arbol no es el de ouke5?)"; exit 1; }
else
	say "AVISO: no encuentro build/rootfs/deploy/audio/kernel/deltas-omarchy-v4.sh"
fi

# ---- camaras: 0045 (rails) + 0046 (SMMU de la IFE) ----
say "--- camaras: 0045 (rails) + 0046 (SMMU IFE) ---"
for p in "$R/build/rootfs/deploy/camaras/patches/0045-uke-rpmh-camera-rails.patch" \
	"$R/build/rootfs/deploy/camaras/patches/0046-uke-smmu-camera-ife.patch"; do
	[ -f "$p" ] || { say "no encuentro $p"; exit 1; }
	if git -C "$TREE" apply --reverse --check "$p" 2>/dev/null; then
		say "$(basename "$p") ya aplicado"
	elif git -C "$TREE" apply --check "$p"; then
		git -C "$TREE" apply "$p"
		say "$(basename "$p") aplicado"
	else
		say "$(basename "$p") NO aplica limpio"; exit 1
	fi
done

say "OK: deltas propios aplicados"
say "SIGUIENTE: compilar con el .config de build/kernel-config/senemos-ouke5.config"
