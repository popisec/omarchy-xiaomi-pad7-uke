#!/bin/sh
# paquete-firmware-wlan.sh — paquete de firmware del WLAN al rootfs (F3/A8).
#
# QUÉ: los 16 ficheros que YA FUNCIONAN (cadena hasta "qmi firmware ready" +
#   rings + HTC; ledger #434 resultado, #441 §3) copiados a las rutas que fija
#   el driver (no el DT): ath11k/WCN6750/hw1.0/{amss,board,regdb}.bin +
#   qca6750/{wpss.mdt,wpss.b00..b10,b12} (#422 §1-4: .fw.dir="WCN6750/hw1.0",
#   m3.bin innecesario, board.bin API1 evita adivinar board-id, b11 no existe).
# FUENTE (solo lectura): wifi-fw-stage/ del hermano
#   ($HOME/gpu-work/ramaa/s21/wifi-fw-stage, 16 ficheros, 15,7 MB, #422).
#   Shas esperados: firmware-wlan.sha256 (mismo dir; 4 coinciden con el ledger,
#   12 generados nuevos — ver cabecera del manifiesto).
# DESTINO: staging/lib/firmware/ (fuente del mkfs.ext4 -d, INFORME-A2 §a.8).
#   El staging trae linux-firmware de stock SIN qca6750/ y SIN qcom/ (INFORME-A2
#   §b): este paquete es AUTOCONTENIDO, no depende de ningún paquete de firmware.
#
# TODO LOCAL, 100% offline: NO copia nada a la tablet. Modo por defecto
#   --dry-run (verifica fuentes+shas e informa qué haría). El modo real
#   --instalar escribe SOLO en staging/ local (ni tablet, ni flash, ni dd).
# Lecciones aplicadas: mkdir -p ANTES de copiar (R-49: scp sin mkdir falla);
#   nada bajo /tmp (tmpfs: se pierde al reinicio); sync tras copiar (ronda 39 §4).
#
# Uso: sh build/gates/paquete-firmware-wlan.sh [--dry-run|--instalar]

set -eu
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GATES="$REPO/build/gates"
STAGE_SRC="$HOME/gpu-work/ramaa/s21/wifi-fw-stage"
MANIFIESTO="$GATES/firmware-wlan.sha256"
DSTBASE="$REPO/build/rootfs/staging/lib/firmware"
MODE="${1:---dry-run}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FALLO: $1"; }
[ "$MODE" = "--dry-run" ] || [ "$MODE" = "--instalar" ] || { echo "uso: $0 [--dry-run|--instalar]"; exit 2; }

echo "== A8 paquete-firmware-wlan ($MODE) =="
echo "-- gate 0: rutas fuera de /tmp y manifiesto presente --"
case "$STAGE_SRC $DSTBASE" in *tmp*) bad "ruta bajo /tmp"; exit 1;; *) ok "fuente y destino fuera de /tmp";; esac
[ -f "$MANIFIESTO" ] || { bad "falta $MANIFIESTO"; exit 1; }
ok "manifiesto $MANIFIESTO"
[ -d "$STAGE_SRC" ] || { bad "fuente ausente: $STAGE_SRC"; exit 1; }
ok "fuente accesible (solo lectura)"

echo "-- gate 1: los 16 ficheros existen y su sha == manifiesto --"
N=0
while read -r sha rel; do
    case "$sha" in \#*|"") continue;; esac
    N=$((N+1)); f="$STAGE_SRC/$rel"
    [ -f "$f" ] || { bad "falta $rel"; continue; }
    got="$(sha256sum "$f" | cut -d' ' -f1)"
    size="$(stat -c%s "$f")"
    if [ "$got" = "$sha" ]; then ok "$rel  $size B  sha ✓"; else bad "$rel sha DISTINTO (esperado $sha, medido $got)"; fi
done < "$MANIFIESTO"
[ "$N" -eq 16 ] && ok "recuento de manifiesto: 16 ficheros" || bad "manifiesto trae $N, esperados 16"

echo "-- gate 2: sin colisiones con el linux-firmware de stock del staging --"
# (nuestros nombres no pisan stock: board.bin vs board-2.bin; qca6750/ no existe)
for rel in lib/firmware/ath11k/WCN6750/hw1.0/amss.bin \
           lib/firmware/ath11k/WCN6750/hw1.0/board.bin \
           lib/firmware/ath11k/WCN6750/hw1.0/regdb.bin; do
    if [ -e "$DSTBASE/../../$rel" ] || [ -e "$REPO/build/rootfs/staging/$rel" ]; then
        bad "colisión: staging ya trae $rel (se pisaría stock)"
    else ok "sin colisión: $rel es NUEVO en staging"; fi
done
[ -e "$DSTBASE/qca6750" ] && bad "staging ya trae qca6750/ (inesperado)" \
                          || ok "staging sin qca6750/ (se creará)"

if [ "$MODE" = "--instalar" ]; then
    echo "-- modo real: mkdir -p (R-49) + copia + cmp + sync --"
    while read -r sha rel; do
        case "$sha" in \#*|"") continue;; esac
        d="$DSTBASE/$(dirname "$rel")"
        mkdir -p "$d"
        cp -a "$STAGE_SRC/$rel" "$d/$(basename "$rel").tmp-$$"
        mv "$d/$(basename "$rel").tmp-$$" "$d/$(basename "$rel")"
        cmp -s "$STAGE_SRC/$rel" "$d/$(basename "$rel")" \
            && ok "copiado $rel" || { bad "cmp tras copia: $rel"; exit 1; }
    done < "$MANIFIESTO"
    sync && ok "sync ejecutado"
fi

echo "-- gate 3: recuento final en staging --"
c_qca="$(find "$DSTBASE/qca6750" -type f 2>/dev/null | wc -l)"
c_wcn="$(find "$DSTBASE/ath11k/WCN6750" -type f 2>/dev/null | wc -l)"
c_gen="$(find "$DSTBASE/qcom" -maxdepth 1 -name 'gen71100_*' 2>/dev/null | wc -l)"
echo "  staging/lib/firmware/qca6750/            = $c_qca ficheros (esperado tras --instalar: 13)"
echo "  staging/lib/firmware/ath11k/WCN6750/     = $c_wcn ficheros (stock: board-2.bin+Notice+sc7280+qcm6490; +3 nuestros tras --instalar)"
echo "  staging/lib/firmware/qcom/gen71100_*     = $c_gen (GPU, ámbito F1/F2: INFORME-A2 §b dice que este snapshot no trae dir qcom/)"
if [ "$MODE" = "--instalar" ]; then
    [ "$c_qca" -eq 13 ] && ok "qca6750/ completo (13)" || bad "qca6750/ trae $c_qca, esperados 13"
    for b in amss.bin board.bin regdb.bin; do
        [ -f "$DSTBASE/ath11k/WCN6750/hw1.0/$b" ] && ok "WCN6750/hw1.0/$b presente" || bad "falta WCN6750/hw1.0/$b"
    done
else
    echo "  (dry-run: no se escribe nada; el modo real es --instalar, NO invocado aquí)"
fi

echo "== resultado: $PASS ok, $FAIL fallos =="
[ "$FAIL" -eq 0 ]
