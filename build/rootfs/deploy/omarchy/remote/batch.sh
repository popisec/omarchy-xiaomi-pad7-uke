#!/bin/bash
# batch.sh <N> -- corre EN LA TABLET (root). Lo lanza deploy.sh con `setsid nohup` y lo sondea por SSH:
# si el enlace NCM se cae a mitad, pacman SIGUE (no muere por SIGPIPE/SIGHUP) y el estado queda en disco.
#
# Entrada (la deja deploy.sh por tar|ssh, sin sftp):
#   $RD/pkgs/*.pkg.tar.*        paquetes de la tanda N (se borran al terminar OK: el rootfs va justo)
#   $RD/batch-N.tsv             filas de manifest/instalar.tsv de esta tanda
# Salida: $RD/log/batch-N.log y $RD/state/batch-N.rc  (0 ok; 10 sha; 20 conflicto de ficheros; 30 pacman; 31 -Qk;
#         42 sin espacio; 43 pacman ya corriendo)
#
# Garantias: transaccion unica por tanda (los ciclos reales libglvnd<->mesa y gdk-pixbuf2<->glycin<->librsvg
# viajan en la misma tanda); `--needed` => idempotente/reanudable; df-gate ANTES de tocar la DB; sha256 ANTES de
# instalar; --overwrite SOLO si la tanda contiene paquetes con ficheros sin dueno conocidos (ver
# manifest/overlay-sin-dueno.tsv: el rootfs v8 trae 171 paquetes volcados sin registrar en pacman).
set -uo pipefail
RD=${RD:-/root/uke-omarchy}
N=${1:?uso: batch.sh N}
MARGIN_MB=${MARGIN_MB:-150}
mkdir -p "$RD/log" "$RD/state"
LOG=$RD/log/batch-$N.log
RC=$RD/state/batch-$N.rc
rm -f "$RC"
exec >>"$LOG" 2>&1
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
fin() { log "FIN rc=$1 ${2:-}"; echo "$1" >"$RC.tmp" && mv "$RC.tmp" "$RC"; exit "$1"; }

TSV=$RD/batch-$N.tsv
[ -s "$TSV" ] || fin 1 "falta $TSV"
cd "$RD/pkgs" || fin 1 "falta $RD/pkgs"
log "=== tanda $N: inicio (PID $$) libres=$(df -Pm / | awk 'NR==2{print $4}')MiB MemAvail=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)MiB"

# 1) sha256 de TODO lo que llego (corte de USB/NCM = fichero truncado)
awk -F'\t' '!/^#/ && NF>=9 {print $9 "  " $3}' "$TSV" >"$RD/state/batch-$N.sha256"
if ! sha256sum -c --quiet "$RD/state/batch-$N.sha256"; then
  fin 10 "sha256 NO cuadra: repite el envio de la tanda (deploy.sh install $N)"
fi
log "sha256 OK ($(wc -l <"$RD/state/batch-$N.sha256") ficheros)"

# 2) pendientes = los que no estan ya exactamente a esa version (los modetest de L76R, p.ej., se saltan solos)
PEND=(); NAMES=(); NEED_KB=0; OVL=0
while IFS=$'\t' read -r _b _l file name ver _cs isize ovl _sha; do
  case "$_b" in \#*|"") continue ;; esac
  inst=$(pacman -Q "$name" 2>/dev/null | awk '{print $2}')
  [ "$inst" = "$ver" ] && continue
  PEND+=("./$file"); NAMES+=("$name"); NEED_KB=$((NEED_KB + isize / 1024 + 1)); [ "$ovl" = 1 ] && OVL=1
done <"$TSV"
if [ "${#PEND[@]}" -eq 0 ]; then
  log "nada pendiente (todo ya instalado a esa version)"
  rm -f ./*.pkg.tar.* 2>/dev/null
  fin 0 "ya instalado"
fi
NEED_MB=$(((NEED_KB + 1023) / 1024 + MARGIN_MB))
FREE_MB=$(df -Pm / | awk 'NR==2{print $4}')
log "pendientes: ${#PEND[@]} pkgs, ~$((NEED_KB / 1024)) MiB instalados; piden $NEED_MB MiB (con margen), libres $FREE_MB MiB; overlay=$OVL"
if [ "$FREE_MB" -lt "$NEED_MB" ]; then
  fin 42 "ESPACIO INSUFICIENTE: nada tocado. Libera espacio y repite."
fi

# 3) nadie mas usando pacman; lock huerfano (apagon/corte) solo si no hay proceso
if pgrep -x pacman >/dev/null 2>&1; then fin 43 "hay otro pacman en marcha"; fi
if [ -e /var/lib/pacman/db.lck ]; then log "db.lck huerfano: se elimina"; rm -f /var/lib/pacman/db.lck; fi

# 4) instalar. OMARCHY_ALLOW_DIRECT_PACMAN=1: el guard 00-omarchy-update-guard.hook solo bloquea -Syu, pero asi
#    la tanda es re-ejecutable tambien despues de instalar `omarchy`.
OW=()
if [ "$OVL" = 1 ]; then
  OW=(--overwrite '*')
  log "tanda con paquetes de overlay: --overwrite '*' (solo puede pisar los ficheros sin dueno ya medidos)"
elif [ "${OVERWRITE_ALL:-0}" = 1 ]; then
  OW=(--overwrite '*')
fi
log "pacman -U --needed --noconfirm ${OW[*]:-} (${#PEND[@]} ficheros)"
OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -U --needed --noconfirm --noprogressbar "${OW[@]}" "${PEND[@]}" >"$RD/log/batch-$N.pacman" 2>&1
rc=$?
cat "$RD/log/batch-$N.pacman" >>"$LOG"
if [ "$rc" -ne 0 ]; then
  if grep -qiE 'conflicting files|exists in filesystem' "$RD/log/batch-$N.pacman"; then
    fin 20 "conflicto de ficheros SIN cubrir por el overlay conocido: no se pisa nada. Revisa $RD/log/batch-$N.pacman (OVERWRITE_ALL=1 solo si se entiende)"
  fi
  fin 30 "pacman rc=$rc (la transaccion es atomica: la DB sigue como antes salvo corte a mitad)"
fi
ldconfig 2>/dev/null || true
sync

# 5) detector de extraccion truncada: los ficheros registrados deben existir
bad=0
for n in "${NAMES[@]}"; do
  out=$(pacman -Qk "$n" 2>&1)
  case "$out" in *" 0 missing files"*) ;; *) log "FALTAN ficheros: $out"; bad=1 ;; esac
done
[ "$bad" = 0 ] || fin 31 "pacman -Qk: faltan ficheros (rootfs posiblemente tocado)"

rm -f ./*.pkg.tar.* 2>/dev/null
log "OK tanda $N: libres ahora $(df -Pm / | awk 'NR==2{print $4}')MiB"
fin 0 "ok"
