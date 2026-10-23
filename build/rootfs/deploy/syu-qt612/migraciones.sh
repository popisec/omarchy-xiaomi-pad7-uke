#!/usr/bin/env bash
# Migraciones pendientes de Omarchy 4.0.6 en la tablet uke (22-oct-2026): marcarlas como hechas SIN ejecutarlas.
# Uso: migraciones.sh plan|backup|aplicar|verificar      (desde el PC; aplicar exige EJECUTAR=si)
#
# MECANISMO (leido en /usr/bin/omarchy-migrate, omarchy 4.0.6):
#  - Una migracion es /usr/share/omarchy/migrations/<ts>.sh. Esta HECHA si existe el fichero
#    $OMARCHY_MIGRATION_STATE (def. $HOME/.local/state/omarchy/migrations)/<ts>.sh (marcador VACIO, `touch`).
#    omarchy-migrate lo crea tras ejecutar la migracion con exit 0. NO hay directorio skipped/ ni estado
#    de sistema (/var/lib/omarchy no existe): el estado es solo por usuario (aqui: omarchy, uid 1001).
#  - No existe un comando oficial de «saltar»: lo equivalente es crear el marcador a mano (touch).
#  - `omarchy-migrate --pending` imprime los pendientes (exit 0) o nada (exit 1). Lo usa omarchy-migrate-notify
#    (omarchy-migrate-notify.service, oneshot en cada login tras graphical-session.target), que envia UNA
#    notificacion critica persistente «Pending Omarchy Migrations» (guardada en
#    ~/.local/state/omarchy/notifications/*.json por el shell). Marcar no la retira: hay que descartarla con
#    `omarchy-shell -q notifications dismiss "Pending Omarchy Migrations"` (o reiniciar sesion: no se reenvia
#    si no hay pendientes). Ojo: omarchy-migrate usa 'bash -euo pipefail' y toca marcador solo si la migracion sale 0.
#
# QUE EJECUTAR REALMENTE: ninguna aporta valor seguro aqui (8 no-op, 5 tocan config innecesariamente,
# 1791403252 = pacman -Syu completo sin IgnorePkg: PELIGROSA). Se marcan las 14 sin ejecutar.
set -euo pipefail
K="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"/build/rootfs/uke-arch-root
T() { ssh -i "$K" -o BatchMode=yes -o ConnectTimeout=10 root@192.168.42.129 "$@"; }
BK=/root/syu-qt612-20261022
ST=/home/omarchy/.local/state/omarchy/migrations
# Solo se marcan estas (revisadas); cualquier otra pendiente nueva se deja sin tocar y se avisa.
ESPERADAS="1788996284 1789095456 1789130779 1790017600 1790114905 1790282866 1790397381 1791265613 1791403252 1791581004 1791621765 1791934674 1791935188 1792334754"
declare -A NOTA=(
 [1788996284]="no-op (nvim: no hay ~/.config/nvim)"
 [1789095456]="tocaria config: crea ~/Work y mise trust (no hay mise)"
 [1789130779]="tocaria config: conf WirePlumber KEF + REINICIA wireplumber (cortaria audio)"
 [1790017600]="tocaria config: retira Hermes de mise (no hay mise)"
 [1790114905]="no-op (afinado altavoces Omarchy, sin conf)"
 [1790282866]="no-op (NVIDIA)"
 [1790397381]="no-op (exit 0)"
 [1791265613]="no-op (Dell XPS)"
 [1791403252]="PELIGROSA: acaba en pacman -Syu sin IgnorePkg (kernel/firmware/mesa)"
 [1791581004]="no-op (limine)"
 [1791621765]="no-op (limine)"
 [1791934674]="tocaria config: hyprland-mimeapps.list y navegador por defecto"
 [1791935188]="tocaria config: flags/policies de Firefox"
 [1792334754]="no-op (OpenClaw no instalado)"
)
# Entorno de la sesion del usuario omarchy (uid 1001), como lo ve el shell Quickshell.
RUNO='runuser -u omarchy -- env HOME=/home/omarchy XDG_RUNTIME_DIR=/run/user/1001 OMARCHY_PATH=/usr/share/omarchy PATH=/usr/local/bin:/usr/bin:/bin:/home/omarchy/.local/bin'

pendientes() { T "$RUNO omarchy-migrate --pending" 2>/dev/null | sed 's/\.sh$//' || true; }

case "${1:-}" in
plan)   # solo lectura
  p=$(pendientes); n=$(grep -c . <<<"$p" || true)
  echo "Pendientes segun omarchy-migrate --pending: $n   (estado: $ST)"
  while read -r m; do [ -n "$m" ] || continue
    if grep -qw "$m" <<<"$ESPERADAS"; then echo "  $m  -> MARCAR sin ejecutar: ${NOTA[$m]}"
    else echo "  $m  -> NUEVA, no revisada: NO se toca"; fi
  done <<<"$p"
  for m in $ESPERADAS; do grep -qw "$m" <<<"$p" || echo "  $m  (ya no pendiente)"; done
  echo "Accion: touch $ST/<ts>.sh como omarchy (sin ejecutar nada); luego descartar el toast con omarchy-shell."
  ;;
backup)  # escribe solo en $BK
  f=$BK/migraciones-estado-$(date +%Y%m%d-%H%M%S).tgz
  T "set -e; mkdir -p $BK; tar czf $f -C /home/omarchy/.local/state/omarchy migrations notifications; ls -l $f; tar tzf $f | wc -l"
  ;;
aplicar)
  [ "${EJECUTAR:-}" = si ] || { echo "Falta EJECUTAR=si (nada hecho). Usa 'plan' para ver que se marcaria."; exit 1; }
  "$0" backup
  p=$(pendientes)
  for m in $ESPERADAS; do
    grep -qw "$m" <<<"$p" || continue
    T "$RUNO sh -c 'mkdir -p $ST && touch $ST/$m.sh'"
    echo "marcada $m  (${NOTA[$m]})"
  done
  # Descarta el toast persistente (best-effort: si el shell no esta, -q no falla)
  T "$RUNO omarchy-shell -q notifications dismiss 'Pending Omarchy Migrations'" || true
  "$0" verificar
  ;;
verificar)  # solo lectura
  p=$(pendientes)
  if [ -z "$p" ]; then echo "OK: omarchy-migrate --pending sin pendientes"; else echo "PENDIENTES:"; echo "$p"; fi
  echo "-- notificaciones guardadas con el aviso:"
  T "grep -l 'Pending Omarchy Migrations' /home/omarchy/.local/state/omarchy/notifications/*.json 2>/dev/null || echo ninguna"
  echo "Si el toast sigue: $RUNO omarchy-shell -q notifications dismiss 'Pending Omarchy Migrations'  (o omarchy-restart-shell, que lo reinicia todo)."
  [ -z "$p" ]
  ;;
*) sed -n 2,3p "$0"; exit 2 ;;
esac
