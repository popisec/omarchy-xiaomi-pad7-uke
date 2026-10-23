#!/usr/bin/env bash
# build.sh — compila y verifica EN EL PC todo el juego de audio de la uke (E0, 18-oct-2026).
# No toca la tablet (ni ssh/adb/fastboot). Reproducible: genera out/*.dtbo, topology/out/UKE.conf y
# firmware/qcom/sm8650/UKE-tplg.bin; imprime que se ha verificado.
#
#   ./build.sh            compila + verifica overlays + topologia + parches del kernel (harness) + sink PipeWire
#   ./build.sh --quick    solo overlays y topologia (sin harness ni PipeWire)
#
# Entradas (rutas por defecto del repo; sobreescribibles por entorno):
#   KT    arbol del kernel senemos (solo se LEEN sus include/dt-bindings): build/kernel-pokes/senemos-7.2.9/linux-7.2.9
#   BASE  DT que ve el kernel tras uke-abl.c (resultado del port a mano check-uke-abl.py sobre el DT capturado)
#   MODS  tarball de modulos ouke3 (se extrae SOLO modules.alias a un directorio temporal)
set -Eeuo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
R=${R:-"$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"}
KT=${KT:-$R/build/kernel-pokes/senemos-7.2.9/linux-7.2.9}
BASE=${BASE:-$R/build/kernel-pokes/senemos-7.2.9/dt/res-live-final.dtb}
MODS=${MODS:-$R/build/kernel-pokes/senemos-build/modules-7.2.9-senemos.1.4054.3-ouke3.tar.zst}
OUT=$HERE/out
TOUT=$HERE/topology/out
FW=$HERE/firmware/qcom/sm8650
QUICK=0; [ "${1:-}" = "--quick" ] && QUICK=1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
bad() { echo "FALLO: $*"; fails=$((fails + 1)); }
say() { printf '\n== %s\n' "$*"; }

for c in cpp dtc fdtoverlay fdtget m4 alsatplg python3 zstd tar sha256sum; do
	command -v "$c" >/dev/null || { echo "falta $c"; exit 2; }
done
python3 -c 'import libfdt' 2>/dev/null || { echo "falta pylibfdt (python3 -c 'import libfdt')"; exit 2; }
for f in "$BASE" "$MODS" "$KT/include/dt-bindings/sound/qcom,q6dsp-lpass-ports.h"; do [ -e "$f" ] || { echo "falta $f"; exit 2; }; done
mkdir -p "$OUT" "$TOUT" "$FW"

say "herramientas"
echo "dtc: $(dtc --version)  m4: $(m4 --version | head -1)  alsatplg: $(alsatplg --version)  fdtoverlay: libfdt de $(dtc --version)"
echo "base: $BASE  sha256 $(sha256sum "$BASE" | cut -c1-16)…"

# ---- 1. overlays ----------------------------------------------------------------------------------
say "1. compilar overlays (cpp + dtc -@)"
# Avisos de dtc tolerados, todos de comprobar un fragmento SIN conocer su nodo destino (dtc no ve la base):
#   - interrupts_property en e5-codec: los soundwire heredan interrupt-parent de /soc, igual que en sm8650.dtsi;
#   - reg_format y avoid_default_addr_size en e2-gpr: service@N usa reg de 1 celda y el nodo gpr vendor hereda #address-cells de /soc (1);
#     no se anaden #cells al gpr para no provocar "WARNING: memory leak" de of_overlay_fdt_apply (ver el .dtso).
# Cualquier otro aviso es un fallo del build.
declare -A DTCFLAGS=( [uke-audio-e5-codec]="-Wno-interrupts_property" [uke-audio-e2-gpr]="-Wno-reg_format -Wno-avoid_default_addr_size" [uke-audio-e2d-gpr-ports]="-Wno-reg_format -Wno-avoid_default_addr_size -Wno-unit_address_vs_reg" )
OVERLAYS=(uke-audio-e2d-gpr-ports uke-audio-e3-lpi uke-audio-e5-codec uke-audio-e5-card)
EXTRA=(uke-audio-e9a-card-fs19xx-wcd-capture uke-audio-e8a-card-fs19xx uke-audio-e8b-card-fs19xx-pins uke-audio-e7a-card-tdm uke-audio-e7b-card-tdm-pins uke-audio-e4a-bedais uke-audio-e4b-dais uke-audio-e4c-card uke-audio-e4-dais uke-audio-e2-gpr uke-audio-e7-amps-i2c uke-audio-e2b-fastrpc uke-audio-e2c-fastrpc-heap)
for n in "${OVERLAYS[@]}" "${EXTRA[@]}"; do
	cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp -I "$KT/include" "$HERE/dts/$n.dtso" -o "$T/$n.pp.dts"
	dtc -@ -I dts -O dtb ${DTCFLAGS[$n]:-} -o "$OUT/$n.dtbo" "$T/$n.pp.dts" 2> "$T/$n.dtc.err" || { cat "$T/$n.dtc.err"; exit 1; }
	[ -s "$T/$n.dtc.err" ] && { echo "avisos de dtc en $n:"; cat "$T/$n.dtc.err"; bad "dtc con avisos en $n"; }
	printf '   %-26s %6d B  sha256 %s\n' "$n.dtbo" "$(stat -c %s "$OUT/$n.dtbo")" "$(sha256sum "$OUT/$n.dtbo" | cut -c1-16)"
done

# ---- 2. aplicar sobre el DT vivo -------------------------------------------------------------------
say "2. fdtoverlay sobre el DT vivo (en cadena, como las aplicaria el cargador, y de una vez)"
cur=$BASE
for n in "${OVERLAYS[@]}"; do
	fdtoverlay -i "$cur" -o "$T/$n.merged.dtb" "$OUT/$n.dtbo" && echo "   + $n: aplicado"
	cur=$T/$n.merged.dtb
done
fdtoverlay -i "$BASE" -o "$T/all.dtb" $(for n in "${OVERLAYS[@]}"; do printf '%s ' "$OUT/$n.dtbo"; done)
cmp -s "$cur" "$T/all.dtb" && echo "   cadena == de una vez: identico" || bad "cadena y aplicacion conjunta difieren"
fdtoverlay -i "$BASE" -o "$T/e7.dtb" "$OUT/uke-audio-e7-amps-i2c.dtbo" && echo "   + uke-audio-e7-amps-i2c (sola): aplicado"
st=$(fdtget -t s "$T/e7.dtb" /soc/qcom,qupv3_1_geni_se@8c0000/i2c@88c000 status)
[ "$st" = okay ] && echo "   i2c@88c000 status: disabled -> $st" || bad "e7: status=$st"
fdtoverlay -i "$BASE" -o "$T/e2b.dtb" "$OUT/uke-audio-e2b-fastrpc.dtbo" && echo "   + uke-audio-e2b-fastrpc (sola): aplicado"
c=$(fdtget -t s "$T/e2b.dtb" /soc/remoteproc-adsp@03000000/glink-edge/qcom,msm_fastrpc_rpmsg compatible)
[ "$c" = "qcom,fastrpc" ] && echo "   fastrpc rpmsg compatible: qcom,msm-fastrpc-rpmsg -> $c" || bad "e2b: compatible=$c"
for cb in 3 4 5 6 7; do fdtget "$T/e2b.dtb" "/soc/remoteproc-adsp@03000000/glink-edge/qcom,msm_fastrpc_rpmsg/compute-cb@$cb" iommus >/dev/null || bad "e2b: falta compute-cb@$cb"; done
fdtget -p "$T/e2b.dtb" /soc/remoteproc-adsp@03000000/glink-edge/qcom,msm_fastrpc_rpmsg | grep -q -E 'qcom,vmids|memory-region' && bad "e2b no debe llevar vmids ni memory-region en la primera prueba" || echo "   e2b sin qcom,vmids ni memory-region (primera prueba)"
# E4c: tarjeta minima sobre e2d+e4a+e4b (alternativa a e5-card)
fdtoverlay -i "$BASE" -o "$T/e4c.dtb" "$OUT/uke-audio-e2d-gpr-ports.dtbo" "$OUT/uke-audio-e4c-card.dtbo" && echo "   + e2d (con bedais/dais)+e4c (tarjeta minima): aplicado"
[ "$(fdtget -t s "$T/e4c.dtb" /sound model)" = UKE ] && [ "$(fdtget -t s "$T/e4c.dtb" /spdif-dit compatible)" = linux,spdif-dit ] && echo "   e4c: model=UKE, codec ficticio linux,spdif-dit" || bad "e4c: nodos sound/spdif-dit incorrectos"
fdtget -l "$T/e4c.dtb" /sound | grep -q mi2s-playback-dai-link && echo "   e4c: un unico dai-link de backend (mi2s-playback-dai-link)" || bad "e4c: falta el dai-link"
# E7a/E7b: tarjeta TDM del altavoz sobre e2d (+e3 para los pines)
fdtoverlay -i "$BASE" -o "$T/e7a.dtb" "$OUT/uke-audio-e2d-gpr-ports.dtbo" "$OUT/uke-audio-e7a-card-tdm.dtbo" && echo "   + e2d+e7a (tarjeta TDM sin pines): aplicado"
fdtoverlay -i "$BASE" -o "$T/e7b.dtb" "$OUT/uke-audio-e2d-gpr-ports.dtbo" "$OUT/uke-audio-e3-lpi.dtbo" "$OUT/uke-audio-e7b-card-tdm-pins.dtbo" && echo "   + e2d+e3+e7b (tarjeta TDM con pines gpio6-9): aplicado"
fdtget -l "$T/e7a.dtb" /sound | grep -q tdm-playback-dai-link && echo "   e7a: dai-link tdm-playback (cpu PRIMARY_TDM_RX_0 = 24)" || bad "e7a: falta el dai-link"
[ "$(fdtget -t u "$T/e7a.dtb" /sound/tdm-playback-dai-link/cpu sound-dai | awk '{print $2}')" = 24 ] && echo "   e7a: cpu sound-dai = bedais 24" || bad "e7a: el cpu no es el DAI 24"
fdtget -p "$T/e7a.dtb" /sound | grep -q pinctrl && bad "e7a no debe llevar pinctrl" || echo "   e7a sin pinctrl (no toca los pines LPI)"
fdtget -p "$T/e7b.dtb" /sound | grep -q "pinctrl-0" && echo "   e7b: pinctrl-0 presente (uke_tdm1_active)" || bad "e7b: falta pinctrl-0"
# E9a (micro, M0): e2d+e3+e5-codec+e9a (tarjeta TDM FS19xx + WCD Capture); e9a no puede ir con e5-card (mismo /sound "UKE")
fdtoverlay -i "$BASE" -o "$T/e9a.dtb" "$OUT/uke-audio-e2d-gpr-ports.dtbo" "$OUT/uke-audio-e3-lpi.dtbo" "$OUT/uke-audio-e5-codec.dtbo" "$OUT/uke-audio-e9a-card-fs19xx-wcd-capture.dtbo" && echo "   + e2d+e3+e5-codec+e9a (tarjeta TDM FS19xx + captura WCD): aplicado" || bad "e9a no se aplica"
[ "$(fdtget -t s "$T/e9a.dtb" /sound model)" = UKE ] && fdtget -l "$T/e9a.dtb" /sound | grep -q wcd-capture-dai-link && fdtget -l "$T/e9a.dtb" /sound | grep -q tdm-playback-dai-link && echo "   e9a: model=UKE con tdm-playback-dai-link y wcd-capture-dai-link" || bad "e9a: faltan dai-links"
fdtget -l "$T/e9a.dtb" /sound | grep -q wcd-playback-dai-link && bad "e9a no debe llevar WCD Playback" || echo "   e9a sin WCD Playback (no toca la ruta RX/USB-C)"
[ "$(fdtget -t u "$T/e9a.dtb" /sound/wcd-capture-dai-link/cpu sound-dai | awk '{print $2}')" = 120 ] && echo "   e9a: cpu de captura = bedai 120 (TX_CODEC_DMA_TX_3 = 120)" || bad "e9a: cpu de captura no es 120 (TX_CODEC_DMA_TX_3): $(fdtget -t u "$T/e9a.dtb" /sound/wcd-capture-dai-link/cpu sound-dai)"
# e8b/e9a/e8a/e7*/e4c comparten /sound: fdtoverlay FUSIONA nodos del mismo nombre (e8b+e9a da UN /sound con los dos enlaces), asi que NO hay chequeo estructural posible aqui;
# la defensa real es en el cargador: uke-ovl.h con UKE_OVL_REFUSE_IF_PATH "/sound" rechaza (-EEXIST) un overlay de tarjeta si ya hay /sound en el DT vivo.
grep -q 'UKE_OVL_REFUSE_IF_PATH' "$HERE"/module/uke_audio_e8b.c "$HERE"/module/uke_audio_e9a.c && echo "   e8b/e9a: el cargador rechaza una segunda tarjeta (/sound existente)" || bad "los cargadores de tarjeta no definen UKE_OVL_REFUSE_IF_PATH"
# orden incorrecto debe fallar (e4 necesita el service@1 de e2)
if fdtoverlay -i "$BASE" -o "$T/bad.dtb" "$OUT/uke-audio-e5-codec.dtbo" 2>/dev/null; then bad "e5-codec sin e2d/e3 NO deberia aplicarse"; else echo "   e5-codec sin e2d/e3: rechazado (orden obligatorio e2d -> e3 -> e5-codec -> e5-card)"; fi

# ---- 3. comprobaciones del resultado ---------------------------------------------------------------
say "3. check-overlays.py (nodos, simbolos, phandles, cobertura de compatibles en el kernel ouke3)"
mkdir -p "$T/mods"
tar --zstd -xf "$MODS" -C "$T/mods" --wildcards --warning=no-timestamp 'lib/modules/*/modules.alias'
python3 -I "$HERE/check-overlays.py" "$BASE" "$T/all.dtb" "$(ls "$T"/mods/lib/modules/*/modules.alias)" | tee "$OUT/check-overlays.txt" | sed 's/^/   /' \
	| grep -v '^   +' | cut -c1-170
[ "${PIPESTATUS[0]}" -eq 0 ] || bad "check-overlays.py"

echo "   check-overlays.py sobre la cadena que se despliega (e2d+e3+e5-codec+e9a):"
python3 -I "$HERE/check-overlays.py" "$BASE" "$T/e9a.dtb" "$(ls "$T"/mods/lib/modules/*/modules.alias)" 2>&1 | grep -E "RESULTADO|FALLO|SIN MODULO" | sed 's/^/     /'
[ "${PIPESTATUS[0]}" -eq 0 ] || bad "check-overlays.py sobre e9a"
echo "   audio-routing de e9a (captura): cada extremo existe como widget en wcd939x y tx macro:"
python3 -I - "$T/e9a.dtb" "$KT/sound/soc/codecs" <<'PY2' || bad "audio-routing de e9a con widgets inexistentes"
import glob, sys, libfdt
f = libfdt.Fdt(open(sys.argv[1], "rb").read())
v = bytes(f.getprop(f.path_offset("/sound"), "audio-routing"))
names = [x.decode() for x in v.split(b"\0") if x]
src = "".join(open(p, errors="replace").read() for p in glob.glob(sys.argv[2] + "/wcd939x.c") + glob.glob(sys.argv[2] + "/lpass-tx-macro.c"))
bad = [n for n in sorted(set(names)) if '"%s"' % n not in src]
print("     %d extremos distintos, %d sin widget%s" % (len(set(names)), len(bad), (": " + ", ".join(bad)) if bad else ""))
sys.exit(1 if bad else 0)
PY2
echo "   audio-routing de la tarjeta: cada extremo existe como widget en los drivers del kernel ouke3 (wcd939x, rx/tx macro):"
python3 -I - "$T/all.dtb" "$KT/sound/soc/codecs" <<'PY' || bad "audio-routing con widgets inexistentes"
import glob, sys, libfdt
f = libfdt.Fdt(open(sys.argv[1], "rb").read())
v = bytes(f.getprop(f.path_offset("/sound"), "audio-routing"))
names = [x.decode() for x in v.split(b"\0") if x]
src = "".join(open(p, errors="replace").read() for p in glob.glob(sys.argv[2] + "/wcd939x.c") +
              glob.glob(sys.argv[2] + "/lpass-rx-macro.c") + glob.glob(sys.argv[2] + "/lpass-tx-macro.c"))
bad = [n for n in sorted(set(names)) if '"%s"' % n not in src]
print("     %d extremos distintos, %d sin widget%s" % (len(set(names)), len(bad), (": " + ", ".join(bad)) if bad else ""))
sys.exit(1 if bad else 0)
PY

# ---- 4. topologia ---------------------------------------------------------------------------------
say "4. topologia AudioReach (m4 -> alsatplg)"
m4 -I "$HERE/topology/src" -I "$HERE/topology/uke" "$HERE/topology/UKE.m4" > "$TOUT/UKE.conf" 2> "$T/m4.err"
[ -s "$T/m4.err" ] && { cat "$T/m4.err"; bad "m4 con avisos"; }
alsatplg -c "$TOUT/UKE.conf" -o "$FW/UKE-tplg.bin" 2> "$T/tplg.err" || bad "alsatplg fallo"
# variante de diagnostico con 4 canales en MultiMedia1 y en el backend TDM (UKE_CH=4); el build normal no cambia
m4 -DUKE_CH=4 -I "$HERE/topology/src" -I "$HERE/topology/uke" "$HERE/topology/UKE.m4" > "$TOUT/UKE-4ch.conf" 2> "$T/m4-4ch.err"
[ -s "$T/m4-4ch.err" ] && { cat "$T/m4-4ch.err"; bad "m4 (4ch) con avisos"; }
alsatplg -c "$TOUT/UKE-4ch.conf" -o "$FW/UKE-tplg-4ch.bin" 2> "$T/tplg4.err" || bad "alsatplg (4ch) fallo"
# variante de diagnostico con dato de 32 bit (UKE_FMT=S32_LE)
m4 -DUKE_FMT=S32_LE -I "$HERE/topology/src" -I "$HERE/topology/uke" "$HERE/topology/UKE.m4" > "$TOUT/UKE-s32.conf" 2> "$T/m4-s32.err"
[ -s "$T/m4-s32.err" ] && { cat "$T/m4-s32.err"; bad "m4 (s32) con avisos"; }
alsatplg -c "$TOUT/UKE-s32.conf" -o "$FW/UKE-tplg-s32.bin" 2> "$T/tplg32.err" || bad "alsatplg (s32) fallo"
# variante S24_LE (el frontend q6apm-dai solo ofrece S16/S24: S32 no se puede abrir)
m4 -DUKE_FMT=S24_LE -I "$HERE/topology/src" -I "$HERE/topology/uke" "$HERE/topology/UKE.m4" > "$TOUT/UKE-s24.conf" 2> "$T/m4-s24.err"
[ -s "$T/m4-s24.err" ] && { cat "$T/m4-s24.err"; bad "m4 (s24) con avisos"; }
alsatplg -c "$TOUT/UKE-s24.conf" -o "$FW/UKE-tplg-s24.bin" 2> "$T/tplg24.err" || bad "alsatplg (s24) fallo"
# variante con la cadena de Android en el dispositivo TDM (MFC -> SAL -> LOG -> TDM_SINK)
m4 -DUKE_CHAIN=1 -I "$HERE/topology/src" -I "$HERE/topology/uke" "$HERE/topology/UKE.m4" > "$TOUT/UKE-chain.conf" 2> "$T/m4-chain.err"
[ -s "$T/m4-chain.err" ] && { cat "$T/m4-chain.err"; bad "m4 (chain) con avisos"; }
alsatplg -c "$TOUT/UKE-chain.conf" -o "$FW/UKE-tplg-chain.bin" 2> "$T/tplgc.err" || bad "alsatplg (chain) fallo"
sed -n "s/.*undefined \(sink\|source\) widget\/stream '\(.*\)'.*/\2/p" "$T/tplg.err" | sort -u > "$T/undef.txt"
echo "   widgets/streams 'no definidos' (los crea el kernel: DAIs de q6apm-lpass-dais):"
while read -r w; do
	[ -n "$w" ] || continue
	dai=${w% Playback}; dai=${dai% Capture}
	tdm=""; case "$dai" in *" TDM"[0-7]) tdm="Q6AFE_TDM_(PB|CAP)_DAI\(\"${dai%% TDM*}\", ${dai##* TDM},"; esac   # DAI TDM: stream "<pre> TDM<n> Playback" (macro Q6AFE_TDM_PB_DAI)
	if grep -qE "stream_name = \"$w\"|Q6AFE_CDC_DMA_(RX|TX)_DAI\($dai\)${tdm:+|$tdm}" "$KT/sound/soc/qcom/qdsp6/q6dsp-lpass-ports.c"; then
		echo "     '$w' -> definido por el kernel (q6dsp-lpass-ports.c)"
	else
		echo "     '$w' -> NO ENCONTRADO en el kernel"; bad "stream sin definir '$w'"
	fi
done < "$T/undef.txt"
grep -vE "undefined (sink|source) widget/stream" "$T/tplg.err" | sed 's/^/   alsatplg: /' || true
alsatplg -d "$FW/UKE-tplg.bin" -o "$T/UKE.decoded.conf" 2>/dev/null && echo "   UKE-tplg.bin se redecodifica con alsatplg -d ($(stat -c %s "$FW/UKE-tplg.bin") B, $(wc -l < "$T/UKE.decoded.conf") lineas de conf)" || bad "UKE-tplg.bin no se redecodifica"
m4 -I "$HERE/topology/src" "$HERE/topology/src/SM8550-HDK.m4.upstream" > "$T/HDK.conf"
echo "   SectionWidget: UKE $(grep -c '^SectionWidget' "$TOUT/UKE.conf") vs upstream SM8550-HDK.m4 (= fuente de SM8650-QRD-tplg.bin) $(grep -c '^SectionWidget' "$T/HDK.conf"): UKE quita WSA y DisplayPort"
(cd "$HERE/topology/src" && sha256sum -c --quiet UPSTREAM.sha256) && echo "   includes vendorizados intactos (UPSTREAM.sha256, upstream 35e482d2)" || bad "los includes vendorizados no coinciden con UPSTREAM.sha256"

# ---- 5. harness del kernel + sink PipeWire -----------------------------------------------------------
if [ "$QUICK" -eq 0 ]; then
	say "5. parches de kernel (harness de uke_abl_transform + lista blanca SMMU)"
	R="$R" KT="$KT" "$HERE/kernel/harness/run-tests.sh" "$OUT" | tee "$OUT/kernel-tests.txt" | sed 's/^/   /'
	[ "${PIPESTATUS[0]}" -eq 0 ] || bad "kernel/harness/run-tests.sh"
	say "6. sumidero nulo de PipeWire (instancia privada)"
	"$HERE/pipewire/test-private.sh" | tee "$OUT/pipewire-test.txt" | sed 's/^/   /'
	[ "${PIPESTATUS[0]}" -eq 0 ] || bad "pipewire/test-private.sh"
fi

# ---- 6. manifiesto ---------------------------------------------------------------------------------
say "manifiesto"
(cd "$HERE" && sha256sum out/*.dtbo firmware/qcom/sm8650/UKE-tplg.bin topology/out/UKE.conf kernel/*.patch dts/*.dtso topology/UKE.m4 \
	pipewire/50-uke-null-sink.conf > MANIFEST.sha256 && sed 's/^/   /' MANIFEST.sha256)
echo
echo "RESULTADO: $([ $fails -eq 0 ] && echo OK || echo "$fails FALLO(S)")"
[ $fails -eq 0 ]
