#!/bin/bash
# Build del kernel CON la instrumentacion de pokes para apps-smmu.
#
# TRAMPA YA MORIDA UNA VEZ (no repetir): la config buena es ~/gpu-work/build-uke/.config
# (3.036 lineas, CONFIG_ARCH_QCOM=y). La de w1-out/build/.config esta VACIA (2.542) y su
# olddefconfig quita CONFIG_ARCH_QCOM, lo que rompe uke-panic-fb.c (su .c es obj-y incondicional y
# el header cae al stub con IS_ENABLED(CONFIG_ARCH_QCOM)) => "redefinition of 'uke_poke'".
# Por eso el O= es un directorio PROPIO, no el del hermano.
#
# LLVM=1 es obligatorio: el arbol se compilo con clang 22.1.8; con gcc el target falla con
# "unrecognized command-line option '-mlittle-endian'".
#
# REGLA DEL PROYECTO (LECCIONES.md del hermano): en primer plano el make es un no-op silencioso
# y un build "OK" vacio es indistinguible. Por eso este script NO corre el build en primer plano:
# se relanza a si mismo DESPRENDIDO (setsid nohup ... & disown) y el que lo invoca solo ve el pid
# y el log. El build de verdad ocurre en background con todo redirigido al log.
set -euo pipefail

O="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"/build/kernel-pokes
LOG="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"/build/logs/build-pokes.log

if [ -z "${UKE_BUILD_DETACHED:-}" ]; then
    mkdir -p "$(dirname "$LOG")"
    export UKE_BUILD_DETACHED=1
    setsid nohup "$0" "$@" >>"$LOG" 2>&1 &
    disown || true
    echo "build desprendido (pid $!); log en $LOG"
    exit 0
fi

set -x
cd $HOME/gpu-work/palawan-linux
export MAKE=/usr/bin/make
export ARCH=arm64
export LLVM=1
export KBUILD_BUILD_USER=uke
export KBUILD_BUILD_HOST=palawan
make O=$O olddefconfig
# GATE: sin CONFIG_ARCH_QCOM el build rompe uke-panic-fb.c. Si la linea no esta, ABORTAR.
grep -E "^CONFIG_ARCH_QCOM" $O/.config || { echo "ABORT: falta CONFIG_ARCH_QCOM en $O/.config (.config vacio o equivocado)"; exit 1; }
make O=$O -j16 Image
# GATE: el Image tiene que existir y ser MAS NUEVO que el .config. Un build roto o vacio
# (el no-op silencioso de LECCIONES.md) deja un Image viejo o ninguno: eso ya no sale con 0.
IMG=$O/arch/arm64/boot/Image
[ -f "$IMG" ] || { echo "ABORT: no existe $IMG: el build no produjo kernel"; exit 1; }
[ "$IMG" -nt "$O/.config" ] || { echo "ABORT: $IMG es mas viejo que $O/.config: el build no reconstruyo nada"; exit 1; }
ls -l "$IMG"
sha256sum "$IMG"
echo DONE
