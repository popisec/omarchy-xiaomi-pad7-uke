#!/bin/bash
# compilar-panel-o82.sh — compila drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c
# como MODULO (CONFIG_DRM_PANEL_XIAOMI_O82_DUALDSI=m) sobre una COPIA del arbol
# del fork, sin tocar $HOME/gpu-work/palawan-linux (compartido).
#
# Patron heredado LITERALMENTE de build/gates/aplicar-parche-msi.sh, cuyos tres
# tropiezos documentados se evitan aqui:
#   T1) el arbol compartido NUNCA se compila (rsync sin .git y sin objetos).
#   T2) un build "limpio" con M= revienta en clang por el offset del
#       stack-protector -> se hace archprepare modules_prepare ANTES.
#   T3) los .ko caen en la COPIA ($DST/drivers/...), no en O= -> se busca en
#       los dos sitios.
#   T4) SIN Module.symvers el modpost no puede resolver los simbolos del
#       vmlinux (drm_panel_*, mipi_dsi_*) -> se reutiliza el Module.symvers de
#       ~/gpu-work/ramaa/s10/build-s122 (SOLO LECTURA), que es del MISMO config.
#
# Uso:  ./compilar-panel-o82.sh            (detached, log en /tmp/opencode/sg-panel-build.log)
#       UKE_PANEL_BUILD_FG=1 ./...         (primer plano, para depurar)
set -u
DST=${1:-/tmp/opencode/sg-panel}
SRC=$HOME/gpu-work/palawan-linux
CFG=$SRC/configs-uke/config-bueno-actual.config
SYMVERS=$HOME/gpu-work/ramaa/s10/build-s122/Module.symvers
O=$DST-build-out
LOG=/tmp/opencode/sg-panel-build.log
MODDIR=drivers/gpu/drm/panel
KO=$DST/$MODDIR/panel-xiaomi-o82-dualdsi.ko
PKG="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"/build/pkg/panel-o82

[ -f "$SRC/$MODDIR/panel-xiaomi-o82-dualdsi.c" ] || { echo "ABORT: no existe el driver"; exit 1; }
[ -f "$CFG" ] || { echo "ABORT: no existe $CFG"; exit 1; }
[ -f "$SYMVERS" ] || { echo "ABORT: no existe $SYMVERS"; exit 1; }

mkdir -p /tmp/opencode
if [ ! -f "$DST/$MODDIR/panel-xiaomi-o82-dualdsi.c" ]; then
    echo "copiando arbol a $DST ..."
    mkdir -p "$DST"
    rsync -a --exclude=.git --exclude='*.o' --exclude='*.ko' --exclude='*.cmd' \
      --exclude='.tmp_versions' --exclude='*.mod' --exclude='*.mod.c' --exclude='*.mod.o' \
      "$SRC/" "$DST/" || { echo "ABORT: rsync fallo"; exit 1; }
fi

if [ -z "${UKE_PANEL_BUILD_FG:-}" ]; then
    setsid nohup env UKE_PANEL_BUILD_FG=1 "$0" "$DST" >>"$LOG" 2>&1 &
    disown || true
    echo "build desprendido (pid $!); log en $LOG"
    exit 0
fi

set -x
echo "=== inicio $(date -Is) ==="
export MAKE=/usr/bin/make ARCH=arm64 LLVM=1
mkdir -p "$O"
cp "$CFG" "$O/.config"
# Unica desviacion respecto al config bueno: el driver del panel pasa a modulo.
# OJO (medido): "scripts/config -m -e SYM" NO deja =m (-e gana y deja =y o sin set);
# el orden correcto es SOLO -m.
"$DST/scripts/config" --file "$O/.config" -m DRM_PANEL_XIAOMI_O82_DUALDSI 2>/dev/null \
  || sed -i 's/^CONFIG_DRM_PANEL_XIAOMI_O82_DUALDSI=.*/CONFIG_DRM_PANEL_XIAOMI_O82_DUALDSI=m/' "$O/.config"
make O="$O" -C "$DST" olddefconfig || { echo "ABORT: olddefconfig"; exit 1; }
grep -E "^CONFIG_DRM_PANEL_XIAOMI_O82_DUALDSI=m" "$O/.config" || { echo "ABORT: el config no quedo en =m"; exit 1; }
grep -E "^CONFIG_DRM_MSM_DSI_7NM_PHY=y" "$O/.config" || { echo "ABORT: falta DRM_MSM_DSI_7NM_PHY"; exit 1; }

# Module.symvers del build bueno: sin el, modpost no resuelve los simbolos
# exportados por el vmlinux (drm_panel_alloc, mipi_dsi_*, backlight_*).
cp "$SYMVERS" "$O/Module.symvers"
make O="$O" -C "$DST" -j"$(nproc)" archprepare modules_prepare || { echo "ABORT: archprepare"; exit 1; }
grep -q TSK_STACK_CANARY "$O/include/generated/asm-offsets.h" || { echo "ABORT: asm-offsets.h sin TSK_STACK_CANARY"; exit 1; }

make O="$O" -C "$DST" -j"$(nproc)" M=$MODDIR modules
rc=$?
KO2=$(find "$O" "$DST/$MODDIR" -name panel-xiaomi-o82-dualdsi.ko 2>/dev/null | head -1)
if [ -z "$KO2" ]; then
    echo "ABORT: no se produjo panel-xiaomi-o82-dualdsi.ko (rc=$rc)"
    echo "=== ultimas 80 lineas del log de make ==="
    exit 1
fi
echo "KO=$KO2"
ls -la "$KO2"
sha256sum "$KO2"
mkdir -p "$PKG"
cp -f "$KO2" "$PKG/panel_xiaomi_o82_dualdsi.ko"
sha256sum "$PKG/panel_xiaomi_o82_dualdsi.ko" | tee "$PKG/sha256.txt"
echo "=== fin $(date -Is) ==="
echo "BUILD-OK"
