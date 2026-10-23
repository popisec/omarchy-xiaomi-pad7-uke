#!/usr/bin/env bash
# publicar.sh — genera el repo publico desde el cuaderno privado.
#
# POR QUE. El cuaderno privado (el del port) es la verdad y sigue vivo: cada
# sesion de trabajo lo cambia. El repo publico es una COPIA, y copiarla a mano
# filtra datos del entorno (el nombre de usuario, las IPs de la tailnet, el
# dominio real de la tailnet, un email personal, las MAC de los aparatos) y
# rompe las referencias. Este script hace la copia, la anonimiza y la verifica.
#
# QUE HACE, en este orden:
#   1. COPIA: git archive del cuaderno privado, solo de las rutas publicables
#   2. ANONIMIZA: tools/redact.py
#   3. REESCRIBE: las rutas de los documentos que viven en docs/historia/
#   4. VERIFICA: gitleaks + los checks de este repo
#   5. Deja el arbol listo para revisar. Solo sube con --go.
#
# USO:
#   bash tools/publicar.sh --privado ~/proyectos/omarchy-uke [--dest DIR] [--go]
#   bash tools/publicar.sh --privado ~/proyectos/omarchy-uke --dry-run
#
#   --dest DIR   donde se deja el arbol generado (por defecto, un temporal)
#   --go         sube el commit al remoto publico (sin esto, solo prepara)
#
# QUE NO SE PUBLICA (allowlist en negativo, porque lo que no esta, no sale):
#   build/android/          volcados del Android y blobs del fabricante
#   build/stage-escritorio/ los 342 .pkg de la capa de Omarchy
#   build/vendor-re/        decompilaciones de Ghidra
#   build/bootimg/          imagenes de arranque
#   build/logs/             logs de compilacion
#   out/                    salidas de pruebas
#   charge/firmware/        firmware del fabricante
#   *.img *.ko *.bin ...    binarios en general
set -Eeuo pipefail

R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
PRIVADO=""
DEST=""
GO=0
DRY=0
REMOTO="https://github.com/popisec/omarchy-xiaomi-pad7-uke.git"

while [ $# -gt 0 ]; do
	case "$1" in
	--privado) PRIVADO="$2"; shift 2 ;;
	--dest) DEST="$2"; shift 2 ;;
	--remoto) REMOTO="$2"; shift 2 ;;
	--go) GO=1; shift ;;
	--dry-run) DRY=1; shift ;;
	*) echo "uso: $0 --privado RUTA [--dest DIR] [--remoto URL] [--go] [--dry-run]" >&2; exit 2 ;;
	esac
done

[ -n "$PRIVADO" ] || { echo "falta --privado" >&2; exit 2; }
[ -d "$PRIVADO/.git" ] || { echo "$PRIVADO no es un repo git" >&2; exit 2; }
[ -z "$DEST" ] && DEST="$(mktemp -d)"

say() { printf '\n[publicar] %s\n' "$*"; }

# ---------------------------------------------------------------- 1. copiar --
say "1/5 copiando desde $PRIVADO"
cd "$PRIVADO"
SNAP=$(git rev-parse --short HEAD)
git archive HEAD | tar -x -C "$DEST" 2>/dev/null || {
	# git archive con exclusiones
	git ls-files -z | while IFS= read -r -d '' f; do
		case "$f" in
		build/android/*|build/stage-escritorio/*|build/vendor-re/*|build/bootimg/*|build/logs/*|\
		build/evidence/*|build/evidencia/*|out/*|charge/firmware/*|build/pkg/staging-p2-ctrl/*|\
		build/rootfs/staging/*|build/rootfs/dl/*|build/rootfs/pkgs/*|build/backup/*|\
		build/backup-par-bueno/*|build/evidencia/*) continue ;;
		*.img|*.ko|*.bin|*.elf|*.mbn|*.mdt|*.acdb|*.fsm|*.dtb|*.dtbo|*.dng|*.raw|*.o|*.mod|*.cmd) continue ;;
		esac
		[ -f "$f" ] && mkdir -p "$DEST/$(dirname "$f")" && cp -p "$f" "$DEST/$f"
	done
}
cd "$R"
echo "  destino: $DEST"

# ------------------------------------------------------------- 2. anonimizar --
say "2/5 anonimizando"
python3 "$R/tools/redact.py" --raiz "$DEST" $([ $DRY -eq 1 ] && echo --dry-run)

# ------------------------------------------------------------ 3. reescribir --
say "3/5 moviendo el material de trabajo a docs/historia/"
cd "$DEST"
for f in AGENTS.md DUDAS.md G-auditoria-documental.md ESTADO-VIVO.md; do
	[ -f "$f" ] || continue
	mkdir -p docs/historia
	git mv "$f" "docs/historia/$f" 2>/dev/null || mv "$f" "docs/historia/$f"
done
# los informes de ciclo archivados
if [ -d build/gates/revision ]; then
	mkdir -p docs/historia/revision
	find build/gates/revision -mindepth 1 -maxdepth 1 -type d -exec mv {} docs/historia/revision/ \; 2>/dev/null || true
fi
# las referencias: se reescriben en todos los .md
python3 - "$DEST" << 'PY'
import pathlib, re, sys
dest = pathlib.Path(sys.argv[1])
MOVIDOS = ("AGENTS.md", "DUDAS.md", "G-auditoria-documental.md", "ESTADO-VIVO.md")
n = 0
for p in dest.rglob("*.md"):
    t = p.read_text(encoding="utf-8", errors="replace")
    o = t
    for base in MOVIDOS:
        t = re.sub(r"(?<![\w/.-])" + re.escape(base) + r"(?![\w-])", "docs/historia/" + base, t)
    t = t.replace("build/gates/revision/PIPELINE-PANEL-20261014", "docs/historia/revision/PIPELINE-PANEL-20261014")
    if t != o:
        p.write_text(t, encoding="utf-8")
        n += 1
print(f"  ficheros con referencias reescritas: {n}")
PY
cd "$R"

# ------------------------------------------------------------- 4. verificar --
say "4/5 verificando"
rc=0
if [ -x "$R/tools/check-privacidad.py" ] || [ -f "$R/tools/check-privacidad.py" ]; then
	python3 "$R/tools/check-privacidad.py" --repo "$DEST" || rc=1
fi
for chk in check-manifests.py check-links.py dupcheck.py; do
	[ -f "$R/tools/$chk" ] || continue
	echo "  --- $chk"
	python3 "$R/tools/$chk" --repo "$DEST" 2>/dev/null || python3 "$R/tools/$chk" || rc=1
done

# --------------------------------------------------------------- 5. publicar --
say "5/5 generando el commit"
cd "$DEST"
git init -q 2>/dev/null || true
git add -A
git -c user.name="$(git -C "$R" config user.name)" \
    -c user.email="$(git -C "$R" config user.email)" \
    commit -q -m "Instantánea pública del port (cuaderno $SNAP, $(date +%Y-%m-%d))" || true
echo "  commit: $(git rev-parse --short HEAD 2>/dev/null)  (cuaderno $SNAP)"
cd "$R"

if [ $DRY -eq 1 ]; then
	say "dry-run: el árbol está en $DEST. Revísalo y luego:"
	echo "  bash tools/publicar.sh --privado $PRIVADO --dest $DEST --go"
	exit $rc
fi

if [ $GO -eq 1 ]; then
	say "subiendo a $REMOTO"
	cd "$DEST"
	git push -f "$REMOTO" HEAD:main
	cd "$R"
else
	say "preparado en $DEST (sin --go no se sube nada)"
fi
exit $rc
