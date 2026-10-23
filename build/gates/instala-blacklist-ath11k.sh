#!/bin/sh
# instala-blacklist-ath11k.sh — hornea la blacklist de ath11k en el rootfs (A2/F3).
#
# PROBLEMA (ledger #441 §1, LECCIONES.md ronda 39 §4): uke-wifi-trace.sh:46 hace
#   `rm -f /etc/modprobe.d/blacklist-ath11k.conf` y NO la restaura. El rootfs es
#   ext4 persistente ⇒ desde ese momento udev autocarga ath11k/ath11k_ahb por
#   modalias a t≈26 s, antes de que wifi-pmu/pwrseq estén listos (probe en
#   -EPROBE_DEFER), y cada probe completo muere en reset silencioso a ~7,33 s
#   (#441 §3: 7.319/7.333/7.350 s) GASTANDO reintentos de slot (ronda 39 §4:
#   EXT4 ya en 879 errores; "hay que crearla con sync o no sobrevive").
# REGLA QUE APLICA: un script que BORRA la blacklist tiene que RESTAURARLA,
#   siempre, incluso en error (trap). Este instalador no borra nada y además
#   re-asegura el fichero a la salida por si otro paso lo tocó.
#
# QUÉ HACE: copia etc-base/etc/modprobe.d/blacklist-ath11k.conf a
#   staging/etc/modprobe.d/ (fuente del `mkfs.ext4 -d staging`, INFORME-A2 §a.8:
#   lo que está en staging sobrevive al reinicio POR CONSTRUCCIÓN; los cambios
#   de runtime en /etc NO persisten — LECCIONES ronda 38 §5 / #434 "el rootfs
#   revierte al reiniciar").
# TODO LOCAL, 100% offline: no toca la tablet, no flash, no dd, no rebuild de
#   la imagen (eso regenera SHA-ARCH.txt y lo hace quien cierre F5).
# Uso: sh build/gates/instala-blacklist-ath11k.sh   (solo instala+verifica)

set -eu
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$REPO/build/rootfs/etc-base/etc/modprobe.d/blacklist-ath11k.conf"
DSTDIR="$REPO/build/rootfs/staging/etc/modprobe.d"
DST="$DSTDIR/blacklist-ath11k.conf"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  OK: $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FALLO: $1"; }

# --- trap-restore (la lección de #441): pase lo que pase, la blacklist queda ---
restaura() {
    if [ -f "$SRC" ]; then
        if [ ! -f "$DST" ] || ! cmp -s "$SRC" "$DST"; then
            mkdir -p "$DSTDIR"
            cp -a "$SRC" "$DST.tmp-$$" && mv "$DST.tmp-$$" "$DST"
            echo "  (trap) blacklist repuesta en $DST"
        fi
    fi
}
trap restaura EXIT INT TERM

echo "== A2 instala-blacklist-ath11k =="
echo "-- gate 0: el instalador no borra nada (auto-chequeo) --"
# Solo cuenta `rm` en posición de comando (las menciones en mensajes/cabecera no cuentan).
if grep -nE '^[[:space:]]*(command[[:space:]]+)?rm([[:space:]]|$)' "$0" >/dev/null 2>&1; then
    bad "este script contiene un comando 'rm' (prohibido por #441: lo que borra no se restaura)"; exit 1
else ok "ningún comando 'rm' en el script (solo cp tmp + mv)"; fi

echo "-- gate 1: fuente existe y destino es persistente (no /tmp) --"
[ -f "$SRC" ] || { bad "falta fuente $SRC"; exit 1; }
ok "fuente $SRC"
case "$DSTDIR" in /tmp/*|*/tmp/*) bad "destino bajo /tmp (tmpfs, LECCIONES)"; exit 1;; *) ok "destino fuera de /tmp: $DSTDIR";; esac
[ -d "$DSTDIR" ] || { mkdir -p "$DSTDIR"; echo "  (creado $DSTDIR — mkdir -p previo, lección R-49)"; }
[ -d "$DSTDIR" ] || { bad "no se pudo crear $DSTDIR"; exit 1; }

echo "-- gate 2: instalación atómica (tmp + mv, sin rm) --"
cp -a "$SRC" "$DST.tmp-$$" && mv "$DST.tmp-$$" "$DST"
ok "instalado $DST"

echo "-- gate 3: byte-idéntico fuente == instalado --"
cmp -s "$SRC" "$DST" && ok "cmp fuente/instalado idéntico" || { bad "difieren"; exit 1; }

echo "-- gate 4: semántica (los 3 módulos bloqueados, sintaxis modprobe.d) --"
for m in ath11k ath11k_ahb ath11k_pci; do
    grep -Eq "^blacklist[[:space:]]+$m([[:space:]]|$)" "$DST" \
        && ok "blacklist $m" || { bad "falta 'blacklist $m'"; exit 1; }
done
if grep -Eqv '^(#|$|blacklist[[:space:]]+[A-Za-z0-9_.-]+([[:space:]]|$))' "$DST"; then
    bad "línea con sintaxis no reconocida por modprobe.d"; exit 1
else ok "todas las líneas: comentario/vacía/blacklist válida"; fi

echo "-- gate 5: módulo NO cargado aquí + sync antes de dar nada por bueno --"
if lsmod 2>/dev/null | grep -q '^ath11k'; then
    bad "ath11k cargado en esta máquina (lsmod)"
else ok "ath11k no cargado (lsmod, alcance: este PC)"; fi
sync && ok "sync ejecutado (LECCIONES ronda 39 §4)"

echo "-- gate 6: estado de la imagen construida (solo lectura, debugfs) --"
IMG="$REPO/build/rootfs/arch-rootfs.img"
if [ -f "$IMG" ] && command -v debugfs >/dev/null 2>&1; then
    if debugfs -R "cat etc/modprobe.d/blacklist-ath11k.conf" "$IMG" 2>/dev/null | grep -q '^blacklist ath11k'; then
        ok "la imagen construida YA la contiene"
    else
        echo "  PENDIENTE (no verificado como OK): arch-rootfs.img aún NO la contiene"
        echo "  → requiere rebuild (mkfs.ext4 -d staging, INFORME-A2 §a.8) + nuevo sha en SHA-ARCH.txt"
    fi
else echo "  (sin imagen o sin debugfs: no comprobable offline)"; fi

echo "== resultado: $PASS ok, $FAIL fallos =="
[ "$FAIL" -eq 0 ]
