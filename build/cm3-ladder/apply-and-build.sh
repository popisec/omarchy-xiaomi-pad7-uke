#!/bin/bash
# Aplica uke-cm3-ladder.diff a una COPIA del arbol y compila.
# NO toca el arbol compartido: la fuente solo se lee (cp -al = hardlinks,
# el parche rompe el hardlink del unico fichero modificado).
# Uso:
#   ./apply-and-build.sh [SRC] [REFCONFIG] [WORKBASE]
#   FULL=1 ./apply-and-build.sh   # ademas Image (lento, ~30-60 min)
# Reglas del proyecto hermano que cumple:
#   - build desprendido (setsid nohup) + ARCH/LLVM explicitos (ronda 20.8)
#   - por defecto solo el objeto a6xx_gmu.o (validacion rapida del parche)
set -u
HERE="$(dirname "$0")"
DIFF="$HERE/uke-cm3-ladder.diff"
SRC="${1:-$HOME/gpu-work/palawan-linux}"
REFCONFIG="${2:-$HOME/gpu-work/ramaa/s10/build/.config}"
WORKBASE="${3:-/tmp/opencode/cm3-build}"
WORK="$WORKBASE/src"
OUT="$WORKBASE/out"
LOG="$WORKBASE/build.log"

say() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$LOG"; }
die() { say "ABORTO: $*"; exit 1; }

mkdir -p "$WORKBASE"
: > "$LOG"
say "=== UKE-CM3 ladder build ==="
say "SRC=$SRC (solo lectura)"
say "REFCONFIG=$REFCONFIG"
[ -f "$DIFF" ] || die "no existe $DIFF"
[ -d "$SRC" ] || die "no existe SRC $SRC"
[ -f "$REFCONFIG" ] || die "no existe REFCONFIG $REFCONFIG"

command -v clang >/dev/null 2>&1 || die "clang no instalado (el build usa LLVM=1)"

# 0. Huella del arbol compartido ANTES (para demostrar que no se toco)
BEFORE="$(cd "$SRC" && git status --short | md5sum | cut -d' ' -f1)"
say "SRC git-status md5 antes: $BEFORE"

# 1. Copia (instantanea por hardlinks si mismo fs; completa si no).
#     Se limpia WORK antes: si un intento previo dejo el esqueleto de dirs,
#     `cp SRC WORK` copiaria DENTRO (WORK/palawan-linux) y el parche no aplica.
if [ -d "$WORK" ] && [ -f "$WORK/drivers/gpu/drm/msm/adreno/a6xx_gmu.c" ] \
   && [ -z "${REBUILD_SRC:-}" ]; then
  say "WORK ya existe y contiene el fichero (se reutiliza; REBUILD_SRC=1 para rehacer)"
else
  rm -rf "$WORK"
  mkdir -p "$WORK"
  if cp -al "$SRC/." "$WORK/" 2>/dev/null; then
    say "cp -al OK (hardlinks, mismo fs)"
  else
    say "cp -al no posible (distinto fs): cp -a completo (lento, ~2 GB)"
    cp -a "$SRC/." "$WORK/" || die "cp -a fallo"
  fi
fi
[ -f "$WORK/drivers/gpu/drm/msm/adreno/a6xx_gmu.c" ] \
  || die "la copia no contiene a6xx_gmu.c (copia rota)"

# 2. Parche en la COPIA
say "-- patch -p1 en WORK --"
cd "$WORK" || die "no puedo entrar a $WORK"
patch -p1 --dry-run < "$DIFF" >/dev/null || die "dry-run del parche falla"
patch -p1 < "$DIFF" >>"$LOG" 2>&1 || die "patch fallo (ver $LOG)"
say "lineas UKE-CM3: en la copia: $(grep -c 'UKE-CM3:' drivers/gpu/drm/msm/adreno/a6xx_gmu.c)"

# 3. OUT propio con la config de referencia (la del s10: ARCH_QCOM=y, DRM_MSM=y built-in)
if [ ! -f "$OUT/.config" ]; then
  say "-- OUT nuevo con REFCONFIG --"
  mkdir -p "$OUT"
  cp "$REFCONFIG" "$OUT/.config"
fi

# 4. Compila (desprendido, como manda la ronda 20.8)
TARGET="drivers/gpu/drm/msm/adreno/a6xx_gmu.o"
[ "${FULL:-0}" = 1 ] && TARGET="Image modules"
say "-- make $TARGET (desprendido) --"
setsid nohup make -C "$WORK" ARCH=arm64 LLVM=1 O="$OUT" -j"$(nproc)" "$TARGET" \
  >"$WORKBASE/make.log" 2>&1 &
MPID=$!
say "make pid=$MPID, esperando..."
wait "$MPID"
RC=$?
tail -n 15 "$WORKBASE/make.log" | tee -a "$LOG"
[ "$RC" = 0 ] || die "make fallo con rc=$RC (ver $WORKBASE/make.log)"
[ "${FULL:-0}" = 1 ] || [ -f "$OUT/$TARGET" ] || die "no se genero $OUT/$TARGET"

# 5. Huella del arbol compartido DESPUES (debe ser identica)
AFTER="$(cd "$SRC" && git status --short | md5sum | cut -d' ' -f1)"
say "SRC git-status md5 despues: $AFTER"
[ "$BEFORE" = "$AFTER" ] || die "EL ARBOL COMPARTIDO CAMBIO (antes=$BEFORE despues=$AFTER)"
say "=== OK: parche compila, arbol compartido intacto ==="
