#!/bin/bash
# Compila snd-q6apm.ko y q6apm-lpass-dais.ko con los parches kernel/0005 + 0006 (copia de las fuentes de qdsp6; el arbol NO se modifica).
# Salida: ../out/snd-q6apm-uke.ko y ../out/q6apm-lpass-dais-uke.ko  (instalar como /lib/modules/<krel>/updates/{snd-q6apm,q6apm-lpass-dais}.ko).
set -Eeuo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); A=$(cd "$HERE/.." && pwd); R=$(cd "$A/../../../.." && pwd)
KT=${KT:-$R/build/kernel-pokes/senemos-ouke5/linux-7.2.9}; KB=${KB:-$R/build/kernel-pokes/senemos-ouke5/build}; Q=sound/soc/qcom/qdsp6
OUT=${OUT:-$A/out-ouke5}; mkdir -p "$OUT"
REL=$(cat "$KB/include/config/kernel.release" 2>/dev/null) || { echo "KB=$KB sin kernel.release"; exit 1; }   # defectos = ouke5 (kernel en marcha); ouke4: KT/KB de senemos-7.2.9/senemos-build y OUT=$A/out   # ouke5: OUT=$A/out-ouke5 KB=…/senemos-ouke5/build KT=…/senemos-ouke5/linux-7.2.9
S=$(mktemp -d); trap 'rm -rf "$S"' EXIT; mkdir -p "$S/$Q" "$S/sound/soc/qcom"
cp "$KT"/sound/soc/qcom/common.h "$S"/sound/soc/qcom/
cp "$KT/$Q"/q6apm.c "$KT/$Q"/audioreach.c "$KT/$Q"/topology.c "$KT/$Q"/q6apm-lpass-dais.c "$KT/$Q"/*.h "$S/$Q/"
for P in 0005-q6apm-src-port-from-svc-id 0006-q6apm-tdm-sink-support 0007-q6apm-tdm-lane-cfg 0008-q6apm-tdm-chain-format 0009-q6apm-cancel-apm-work; do
  (cd "$S" && patch -p1 --dry-run < "$A/kernel/$P.patch" >/dev/null && patch -p1 < "$A/kernel/$P.patch" >/dev/null)
done
cp "$HERE/Kbuild" "$S/$Q/Kbuild"
env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL MAKE=/usr/bin/make ARCH=arm64 LLVM=1 /usr/bin/make -C "$KB" M="$S/$Q" modules > "$S/make.log" 2>&1 || { cat "$S/make.log"; exit 1; }
for m in snd-q6apm q6apm-lpass-dais; do
  [ -s "$S/$Q/$m.ko" ] && [ "$S/$Q/$m.ko" -nt "$S/$Q/q6apm.c" ] || { echo "no se genero $m.ko (make no-op?)"; exit 1; }
done
grep -Ei 'warning|error' "$S/make.log" | grep -v 'Entering\|Leaving\|se entra\|se sale' && { echo avisos; exit 1; } || true
cp "$S/$Q/snd-q6apm.ko" "$OUT/snd-q6apm-uke.ko"; cp "$S/$Q/q6apm-lpass-dais.ko" "$OUT/q6apm-lpass-dais-uke.ko"
for m in snd-q6apm:snd-q6apm-uke q6apm-lpass-dais:q6apm-lpass-dais-uke; do
  n=${m%%:*}; o=${m##*:}; K=$OUT/$o.ko
  [ "$(modinfo -F vermagic "$K" | cut -d" " -f1)" = "$REL" ] || { echo "ABORTADO: $n vermagic != $REL"; exit 1; }
  echo "== $n: vermagic $(modinfo -F vermagic "$K" | cut -d' ' -f1); depends $(modinfo -F depends "$K")"
  OR=$KB/$Q/$n.ko
  if [ -f "$OR" ]; then
    diff <(llvm-nm "$OR" | grep -E ' [TDRB] ' | awk '{print $3}' | sort) <(llvm-nm "$K" | grep -E ' [TDRB] ' | awk '{print $3}' | sort) | grep -E '^[<>]' || echo "   simbolos globales identicos al del arbol"
    diff <(modprobe --dump-modversions "$OR" 2>/dev/null | sort) <(modprobe --dump-modversions "$K" 2>/dev/null | sort) >/dev/null && echo "   modversions (importados) identicos" || echo "   modversions DIFIEREN (revisar)"
  fi
  sha256sum "$K"
done
modinfo -F parm "$OUT/snd-q6apm-uke.ko" | grep -E "tdm" | cut -c1-90
