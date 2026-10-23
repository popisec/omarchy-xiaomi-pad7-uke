#!/bin/bash
# aplicar-parche-msi.sh — aplica build/gates/patches/wlan-msi-orden.diff a una COPIA
# del arbol en /tmp/opencode y compila SOLO el modulo ath11k.ko ahi.
#
# REGLAS: (1) NUNCA toca $HOME/gpu-work/palawan-linux (arbol COMPARTIDO, otro
# subagente compila en el ahora mismo). (2) Re-ejecutable sin duplicar: si el
# marcador UKE-wlan-msi-orden ya esta en la copia, no re-aplica. (3) Build
# desprendido con MAKE/ARCH explicitos (LECCIONES del hermano: en primer plano el
# make es un no-op silencioso).
#
# ESTADO DEL PARCHE: REFUTADO como gatillo (hermano, ronda 9, ledger #436/#437:
# el s247-equivalente se midio y el reset NO se movio). Este script existe para
# (a) demostrar que el artefacto compila, (b) dejar el pipeline listo para
# futuros parches (H1/H3), (c) que nadie re-derive el parche creyendo que es nuevo.
set -u
HERE=$(dirname "$(readlink -f "$0")")
PATCH=$HERE/patches/wlan-msi-orden.diff
DST=${1:-/tmp/opencode/uke-hal-check}
SRC=$HOME/gpu-work/palawan-linux
MARK="UKE wlan-msi-orden (dst)"
HAL=$DST/drivers/net/wireless/ath/ath11k/hal.c
O=$DST-build-out
LOG=/tmp/opencode/uke-f3/aplicar-msi.log

[ -f "$PATCH" ] || { echo "ABORT: no existe $PATCH"; exit 1; }

# 1) Copia (rsync excluye .git y objetos; no toca el arbol compartido).
if [ ! -f "$HAL" ]; then
    echo "copiando arbol a $DST ..."
    mkdir -p "$DST"
    rsync -a --exclude=.git --exclude='*.o' --exclude='*.ko' --exclude='*.cmd' \
      --exclude='.tmp_versions' --exclude='*.mod' --exclude='*.mod.c' --exclude='*.mod.o' \
      "$SRC/" "$DST/" || { echo "ABORT: rsync fallo"; exit 1; }
fi

# 2) Idempotencia: marcador ya presente => no duplicar.
if grep -q "$MARK" "$HAL"; then
    echo "YA APLICADO (marcador presente en $HAL): no se duplica."
else
    patch -p1 -s -d "$DST" < "$PATCH" || { echo "ABORT: patch fallo"; exit 1; }
    grep -q "$MARK" "$HAL" || { echo "ABORT: marcador ausente tras patch"; exit 1; }
    echo "parche aplicado a la copia."
fi
grep -c "if (0 && (srng->flags" "$HAL" | grep -q "^0$" \
    || { echo "ABORT: el hack s248 if(0) sigue presente en la copia"; exit 1; }
echo "gate D17 OK: 0 restos de 'if (0 &&' en la copia."

# 3) Build SOLO del modulo, desprendido, en O= separado (con lock: un build
# ya en marcha no se duplica).
LOCK=/tmp/opencode/uke-f3/build-msi.lock
if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK")" 2>/dev/null; then
    echo "build ya en marcha (pid $(cat "$LOCK")); no se duplica. Log en $LOG"
    exit 0
fi
if [ -z "${UKE_MSI_BUILD_DETACHED:-}" ]; then
    export UKE_MSI_BUILD_DETACHED=1
    setsid nohup "$0" "$DST" >>"$LOG" 2>&1 &
    disown || true
    echo "build desprendido (pid $!); log en $LOG"
    exit 0
fi

set -x
echo $$ > "$LOCK"
export MAKE=/usr/bin/make ARCH=arm64 LLVM=1
cp $HOME/gpu-work/palawan-linux/configs-uke/config-bueno-actual.config "$O/.config" 2>/dev/null \
    || { mkdir -p "$O"; cp $HOME/gpu-work/palawan-linux/configs-uke/config-bueno-actual.config "$O/.config"; }
make O="$O" -C "$DST" olddefconfig
grep -E "^CONFIG_ATH11K=m" "$O/.config" || { echo "ABORT: CONFIG_ATH11K=m ausente"; exit 1; }
# GATE + paso que falta en un M= limpio: el offset del stack-protector
# (arch/arm64/Makefile:76) sale de include/generated/asm-offsets.h, que solo
# existe tras archprepare. Sin esto, clang falla con
# "invalid value '' in '-mstack-protector-guard-offset='" (medido).
make O="$O" -C "$DST" -j"$(nproc)" archprepare modules_prepare
grep -q TSK_STACK_CANARY "$O/include/generated/asm-offsets.h" \
    || { echo "ABORT: asm-offsets.h sin TSK_STACK_CANARY"; exit 1; }
make O="$O" -C "$DST" -j"$(nproc)" M=drivers/net/wireless/ath/ath11k modules
KO=$(find "$O" "$DST/drivers/net/wireless/ath/ath11k" -name ath11k.ko 2>/dev/null | head -1)
[ -n "$KO" ] || { echo "ABORT: no se produjo ath11k.ko (build vacio)"; exit 1; }
ls -la "$KO"
sha256sum "$KO"
echo "BUILD-OK: el parche compila (ath11k.ko producido en copia, arbol compartido intacto)."
