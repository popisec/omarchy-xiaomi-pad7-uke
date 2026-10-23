#!/usr/bin/env bash
# uke-slot-check.sh — vigilancia de la hemorragia de reintentos de slot (riesgo nº1).
#
# DOS MODOS, los dos de SOLO LECTURA:
#   uke-slot-check.sh linux      — por SSH: vuelca qbootctl (solo lee GPT con
#                                  O_RDONLY; verificado: el sha de la GPT no cambia)
#                                  y avisa si el slot actual NO está marked successful.
#   uke-slot-check.sh fastboot   — con la tablet en fastboot (coordinar con el proyecto
#                                  hermano): lee los 4 slot-retry-count + unbootable y
#                                  avisa si alguno baja de 3. Imprime la receta de reset.
#
# Todo resultado se añade con fecha a build/slot/slot-log.tsv.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LOG="$ROOT/build/slot/slot-log.tsv"
KEY="$ROOT/build/rootfs/uke-arch-root"
HOST=192.168.42.129
SSHOPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
         -o ConnectTimeout=8 -o LogLevel=ERROR -i "$KEY" "root@$HOST")

warn() { echo "⚠️  $*" >&2; }

mode="${1:-}"; [ -n "$mode" ] || { echo "uso: $0 {linux|fastboot}"; exit 2; }
[ -f "$LOG" ] || printf 'fecha\tmodo\tslot\tactive\tsuccessful\tbootable\tnota\n' > "$LOG"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

case "$mode" in
  linux)
    OUT="$(timeout 30 ssh "${SSHOPTS[@]}" 'qbootctl 2>/dev/null' 2>&1)" || \
      { warn "sin SSH a la tablet"; exit 1; }
    echo "$OUT"
    CUR="$(echo "$OUT" | sed -n 's/^Current slot: //p')"
    for s in _a _b; do
      blk="$(echo "$OUT" | grep -A3 "^SLOT $s:")"
      a="$(echo "$blk" | sed -n 's/.*Active  *: //p')"
      ok="$(echo "$blk" | sed -n 's/.*Successful  *: //p')"
      bt="$(echo "$blk" | sed -n 's/.*Bootable  *: //p')"
      printf '%s\tlinux\t%s\t%s\t%s\t%s\t\n' "$NOW" "$s" "$a" "$ok" "$bt" >> "$LOG"
    done
    if echo "$OUT" | grep -A3 "^SLOT $CUR:" | grep -q 'Successful  *: 0'; then
      warn "slot $CUR sin marcar como bueno: CADA arranque gasta 1 reintento."
      warn "NO ejecutar 'qbootctl -m' sin decisión del dueño (ver build/slot/PROCEDIMIENTO-SLOT.md)."
      exit 1
    fi
    echo "slot $CUR marcado como bueno: sin hemorragia."
    ;;
  fastboot)
    command -v fastboot >/dev/null || { warn "fastboot no instalado en el PC"; exit 1; }
    OUT="$(fastboot getvar all 2>&1)" || { warn "sin tablet en fastboot"; exit 1; }
    echo "$OUT" | grep -iE 'slot|current-slot|unbootable'
    LOW=0
    while read -r line; do
      v="$(echo "$line" | grep -oE '[0-9]+' | tail -1)"
      [ -n "$v" ] && [ "$v" -lt 3 ] && { warn "contador bajo: $line"; LOW=1; }
    done < <(echo "$OUT" | grep -iE 'slot-retry-count')
    echo "$OUT" | grep -qiE 'unbootable: *yes' && { warn "hay slot unbootable"; LOW=1; }
    printf '%s\tfastboot\t-\t-\t-\t-\t%s\n' "$NOW" "$(echo "$OUT" | grep -iE 'slot-retry-count|unbootable' | tr '\n' ';')" >> "$LOG"
    if [ "$LOW" = 1 ]; then
      echo "--- receta de reset (solo si el slot bueno es el b y está caído) ---"
      echo "fastboot set_active a && fastboot set_active b   # devuelve retry a 7"
      echo "fastboot getvar all | grep -iE 'slot-retry-count|unbootable|current-slot'"
      exit 1
    fi
    ;;
  *) echo "uso: $0 {linux|fastboot}"; exit 2 ;;
esac
