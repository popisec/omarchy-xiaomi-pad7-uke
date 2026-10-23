#!/bin/bash
#
# seal-migrations-uke.sh — sellado de migraciones Omarchy en la uke (BORRADOR).
#
# ESTADO: borrador, NO ejecutado (sin acceso a la tablet esta noche).
#
# POR QUÉ. `omarchy-migrate` (omarchy 4.0.4-2) corre cada
# /usr/share/omarchy/migrations/*.sh sin marcador en
# ~/.local/state/omarchy/migrations/<nombre>, con `bash -euo pipefail`, y con
# `set -euo pipefail` en el propio migrador: la PRIMERA migración que falle
# aborta TODA la tanda, no deja marcador y se reintenta en cada login y en
# cada `omarchy update` (que lo llama tras update-system-pkgs). En la uke el
# usuario `alarm` es anterior a las semillas de /etc/skel, así que las 106
# figuran pendientes (ledger #634: "106 migraciones pendientes") y al menos
# una (1781984677, snapper) falla seguro: no hay snapper, no hay limine, el
# rootfs es ext4.
#
# DISEÑO (respeta el de Omarchy, no lo puentea):
#   - El estado sigue siendo el fichero-marcador por migración que usa
#     upstream (omarchy-migrate: "si no existe el marcador, corre; al éxito,
#     touch"). Un install limpio futuro ya nace sellado vía /etc/skel (el
#     paquete trae las 106 semillas); este script es solo para el `alarm`
#     actual, que es anterior a ellas.
#   - SELLAR = crear el marcador SIN ejecutar, solo para la lista SELLAR
#     (abajo) con motivo registrado en el log. Todo lo demás SE EJECUTA de
#     verdad con el mismo intérprete y flags que omarchy-migrate.
#   - A diferencia de omarchy-migrate, un fallo NO aborta la tanda: se anota y
#     se sigue; al final se sale 1 con la lista de pendientes para reintento
#     manual. Así un fallo sorpresa no secuestra las 100+ restantes.
#
# USO (como usuario `alarm`, con sudo con caché caliente):
#   bash seal-migrations-uke.sh --pending   # solo lista lo pendiente
#   bash seal-migrations-uke.sh --dry-run   # qué haría con cada una
#   bash seal-migrations-uke.sh             # ejecuta + sella + reporta
#   bash seal-migrations-uke.sh --verify    # difiere migraciones vs marcadores
#
# LISTA SELLAR (no ejecutar; motivo en ATAQUE-OMARCHY-OFFLINE.md §1):
#   1781984677  Normalize Snapper snapshot services — sin snapper/limine/ext4
#               el repair falla seguro y dejaría el migrate atascado.

set -uo pipefail

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
MIGRATIONS_DIR="$OMARCHY_PATH/migrations"
STATE_DIR="${OMARCHY_MIGRATION_STATE:-$HOME/.local/state/omarchy/migrations}"
LOG="$HOME/.local/state/omarchy/seal-uke.log"

# Marcadores a crear sin ejecutar: <fichero>:<motivo corto>
SELLAR=(
  "1781984677.sh:sin snapper/limine, rootfs ext4; el repair falla seguro (ver informe §1)"
)

mode="run"
case "${1:-}" in
  --pending) mode="pending" ;;
  --dry-run) mode="dryrun" ;;
  --verify) mode="verify" ;;
  "") mode="run" ;;
  -h | --help)
    sed -n '2,/^$/p' "$0"
    echo "Uso: $0 [--pending|--dry-run|--verify]"
    exit 0
    ;;
  *)
    echo "Opción desconocida: $1" >&2
    exit 1
    ;;
esac

[[ -d $MIGRATIONS_DIR ]] || {
  echo "Sin dir de migraciones: $MIGRATIONS_DIR" >&2
  exit 1
}

pending_list() {
  local f n
  for f in "$MIGRATIONS_DIR"/*.sh; do
    [[ -f $f ]] || continue
    n=$(basename "$f")
    [[ -f $STATE_DIR/$n ]] || printf '%s\n' "$n"
  done
}

in_sellar() {
  local n="$1" e
  for e in "${SELLAR[@]}"; do
    [[ ${e%%:*} == "$n" ]] && {
      printf '%s\n' "${e#*:}"
      return 0
    }
  done
  return 1
}

if [[ $mode == "pending" ]]; then
  pending_list
  exit 0
fi

if [[ $mode == "verify" ]]; then
  echo "migraciones: $(ls "$MIGRATIONS_DIR"/*.sh | wc -l)  marcadores: $(ls "$STATE_DIR" 2>/dev/null | wc -l)"
  echo "--- pendientes:"
  pending_list
  exit 0
fi

mkdir -p "$STATE_DIR"
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }

failed=()
sealed=()
applied=()

while IFS= read -r name; do
  [[ -n $name ]] || continue
  reason=""
  if reason=$(in_sellar "$name"); then
    if [[ $mode == "dryrun" ]]; then
      echo "SELLAR  $name  ($reason)"
    else
      touch "$STATE_DIR/$name"
      sealed+=("$name")
      log "SELLADA $name — $reason"
    fi
    continue
  fi
  if [[ $mode == "dryrun" ]]; then
    echo "EJECUTAR $name"
    continue
  fi
  log "ejecutando $name"
  if OMARCHY_PATH="$OMARCHY_PATH" bash -euo pipefail "$MIGRATIONS_DIR/$name" 3<&-; then
    touch "$STATE_DIR/$name"
    applied+=("$name")
    log "OK $name"
  else
    failed+=("$name")
    log "FALLO $name (sigue con la siguiente; marcador NO creado)"
  fi
done < <(pending_list)

echo "--- aplicadas: ${#applied[@]}  selladas: ${#sealed[@]}  fallidas: ${#failed[@]}"
if ((${#failed[@]} > 0)); then
  printf '  FALLO: %s\n' "${failed[@]}"
  echo "Reintentar a mano tras corregir; NO re-ejecutar todo (las OK ya tienen marcador)."
  exit 1
fi
exit 0
