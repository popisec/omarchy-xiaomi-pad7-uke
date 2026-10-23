#!/usr/bin/env bash
# Pruebas de PC de M0 del microfono: (1) 51-uke-mic.conf no tumba PipeWire sin la tarjeta; (2) uke-mic-route.sh con un amixer falso: --dry no escribe, --apply emite los cset
# esperados y salta con aviso los controles que no existen; (3) UCM «UKE» pasa `alsaucm` (si esta instalado) con una tarjeta falsa no disponible -> solo se comprueba la sintaxis con --check de ficheros.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd); A=$(cd "$HERE/.." && pwd)
T=$(mktemp -d /tmp/ukemic.XXXXXX); trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$T"' EXIT
pass=0; fail=0
ok() { echo "  ok   $1"; pass=$((pass+1)); }; ko() { echo "  FALLA $1"; fail=$((fail+1)); }
# (1) PipeWire sobrevive sin tarjeta
mkdir -p "$T/cfg/pipewire/pipewire.conf.d" "$T/home"; cp "$A/pipewire/51-uke-mic.conf" "$T/cfg/pipewire/pipewire.conf.d/"
env -i PATH=/usr/bin HOME="$T/home" XDG_RUNTIME_DIR="$T" XDG_CONFIG_HOME="$T/cfg" pipewire > "$T/pw.log" 2>&1 & pw=$!
sleep 3
if kill -0 $pw 2>/dev/null && [ -S "$T/pipewire-0" ]; then ok "sin tarjeta UKE, PipeWire sigue vivo con 51-uke-mic.conf (nofail)"; else ko "PipeWire murio: $(grep -iE "can.t create|failed" "$T/pw.log" | head -2 | tr '\n' '|')"; fi
kill $pw 2>/dev/null; wait $pw 2>/dev/null
# (1b) control: sin nofail muere (valida que la prueba detecta el fallo)
sed '/flags = \[ nofail \]/d' "$A/pipewire/51-uke-mic.conf" > "$T/cfg/pipewire/pipewire.conf.d/51-uke-mic.conf"
env -i PATH=/usr/bin HOME="$T/home" XDG_RUNTIME_DIR="$T" XDG_CONFIG_HOME="$T/cfg" pipewire > "$T/pw2.log" 2>&1 & pw=$!
sleep 3; if kill -0 $pw 2>/dev/null; then ko "control: sin nofail deberia morir y sigue vivo"; else ok "control: sin nofail PipeWire muere (la prueba (1) es valida)"; fi
kill $pw 2>/dev/null; wait $pw 2>/dev/null
# (1c) con las DOS confs (altavoces + micro) y sin tarjeta, PipeWire sigue vivo
cp "$A/pipewire/51-uke-speakers.conf" "$A/pipewire/51-uke-mic.conf" "$T/cfg/pipewire/pipewire.conf.d/"
env -i PATH=/usr/bin HOME="$T/home" XDG_RUNTIME_DIR="$T" XDG_CONFIG_HOME="$T/cfg" pipewire > "$T/pw3.log" 2>&1 & pw=$!
sleep 3; if kill -0 $pw 2>/dev/null && [ -S "$T/pipewire-0" ]; then ok "51-uke-speakers.conf + 51-uke-mic.conf sin tarjeta: PipeWire sigue vivo"; else ko "con las dos confs PipeWire murio: $(grep -iE "can.t create|failed" "$T/pw3.log" | head -2 | tr '\n' '|')"; fi
kill $pw 2>/dev/null; wait $pw 2>/dev/null
# (2) script de ruta con amixer falso
cat > "$T/amixer" <<'EOS'
#!/bin/bash
# amixer -c CARD cget name=X | cset name=X V | controls
shift 2
case "$1" in
  cget) n="${2#name=}"; case "$n" in "ADC3 ChMap"|"AMIC3_MIXER Switch"|"TX2 MODE") exit 1;; *) exit 0;; esac ;;
  cset) echo "CSET ${2#name=} = $3" >> "$MOCK_LOG" ;;
  controls) echo "numid=1,iface=MIXER,name='TX DEC0 MUX'"; echo "numid=2,iface=MIXER,name='ADC1 MUX'" ;;
esac
EOS
chmod +x "$T/amixer"; export MOCK_LOG="$T/cset.log"; : > "$MOCK_LOG"
R="$A/mic/uke-mic-route.sh"
AMIXER="$T/amixer" "$R" --dry amic1 > "$T/dry.out"; [ ! -s "$MOCK_LOG" ] && grep -q "cset name='ADC1 MUX' CH1_AMIC1" "$T/dry.out" && ok "--dry amic1: imprime los cset y no escribe" || ko "--dry escribio o no imprimio"
AMIXER="$T/amixer" "$R" --apply amic1 > "$T/ap.out"; grep -q "CSET ADC1 MUX = CH1_AMIC1" "$MOCK_LOG" && grep -q "CSET TX SMIC MUX0 = SWR_MIC0" "$MOCK_LOG" && grep -q "CSET MultiMedia3 Mixer TX_CODEC_DMA_TX_3 = 1" "$MOCK_LOG" && ok "--apply amic1: emite ADC1 MUX, TX SMIC MUX0 y MultiMedia3" || ko "--apply amic1 incompleto: $(cat "$MOCK_LOG" | tr '\n' ';')"
: > "$MOCK_LOG"; AMIXER="$T/amixer" "$R" --apply amic3-vendor > "$T/ap3.out"; grep -q "(no existe) ADC3 ChMap" "$T/ap3.out" && grep -q "CSET TX DEC5 MUX = SWR_MIC" "$MOCK_LOG" && ok "--apply amic3-vendor: salta con aviso los controles inexistentes y sigue" || ko "amic3-vendor no salto/avisó bien"
: > "$MOCK_LOG"; AMIXER="$T/amixer" "$R" --apply estereo-vendor >/dev/null; [ "$(grep -c "SWR_MIC" "$MOCK_LOG")" -ge 4 ] && ok "--apply estereo-vendor: dos canales (SWR_MIC4 y SWR_MIC9)" || ko "estereo-vendor"
: > "$MOCK_LOG"; AMIXER="$T/amixer" "$R" --off >/dev/null; grep -q "CSET ADC1 MUX = CH1_AMIC_DISABLE" "$MOCK_LOG" && grep -q "CSET MultiMedia3 Mixer TX_CODEC_DMA_TX_3 = 0" "$MOCK_LOG" && ok "--off: deshabilita ADC y MultiMedia3" || ko "--off"
: > "$MOCK_LOG"; AMIXER="$T/amixer" "$R" --apply dual-1-4 >/dev/null; grep -q "CSET ADC1 MUX = CH1_AMIC1" "$MOCK_LOG" && grep -q "CSET ADC2 MUX = CH2_AMIC4" "$MOCK_LOG" && grep -q "CSET TX SMIC MUX1 = SWR_MIC1" "$MOCK_LOG" && grep -q "CSET TX_AIF1_CAP Mixer DEC1 = 1" "$MOCK_LOG" && ok "--apply dual-1-4: ADC1<-AMIC1 (DEC0) y ADC2<-AMIC4 (DEC1)" || ko "dual-1-4"
"$R" 2>/dev/null; [ $? = 1 ] && ok "sin argumentos: uso (exit 1)" || ko "uso"
# (2b) analizador RMS con un WAV sintetico (1 s de silencio + 2 s de tono -14 dBFS): RMS de ventana ~ -17 dBFS y rango > 100 dB
python3 -I - "$T/t.wav" <<'PY2'
import math, struct, sys, wave
w = wave.open(sys.argv[1], "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(48000)
w.writeframes(b"".join(struct.pack("<h", int(32767 * (0.0 if i < 48000 else 0.2) * math.sin(2 * math.pi * 440 * i / 48000))) for i in range(48000 * 3))); w.close()
PY2
out=$(python3 -I "$HERE/uke-mic-rms.py" "$T/t.wav"); echo "$out" | grep -q "pico -14.0 dBFS" && echo "$out" | grep -q -- "-17 -17" && ok "uke-mic-rms.py mide el tono sintetico (pico -14,0; ventanas -17 dBFS)" || ko "rms: $out"
bash -n "$HERE/uke-mic-m3.sh" && bash -n "$HERE/m5-zona.sh" && bash -n "$HERE/m4-guion.sh" && ok "uke-mic-m3/m4/m5: sintaxis" || ko "sintaxis de los guiones"
echo "$out" | grep -q "RMS_sin_0,5s_inicial -18.0" && ok "rms: RMS sin los primeros 0,5 s (-18,0 dBFS: 0,5 s de silencio + 2 s de tono a -17)" || ko "rms sin inicial: $out"
# (2c) rms con 2 canales: dif por ventana
python3 -I - "$T/t2.wav" <<'PY3'
import math, struct, sys, wave
w = wave.open(sys.argv[1], "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
fr = []
for i in range(48000 * 2):
    a = 0.2 * math.sin(2 * math.pi * 440 * i / 48000); b = 0.02 * math.sin(2 * math.pi * 440 * i / 48000)
    fr.append(struct.pack("<hh", int(32767 * a), int(32767 * b)))
w.writeframes(b"".join(fr)); w.close()
PY3
python3 -I "$HERE/uke-mic-rms.py" "$T/t2.wav" | grep -q "dif ch0-ch1 por ventana (dB; >0 = canal 0 mas fuerte): +20 +20 +20 +20" && ok "uke-mic-rms.py: dif entre canales +20 dB (0,2 frente a 0,02)" || ko "rms dos canales"
# (2d) analizador del chasquido de arranque sobre un WAV sintetico (0,08 decayendo en 0,15 s + ruido): delta > 25 dB y estabiliza en 400-800 ms
python3 -I - "$T/c.wav" <<'PY4'
import math, random, struct, sys, wave
random.seed(1); w = wave.open(sys.argv[1], "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
w.writeframes(b"".join(struct.pack("<hh", int(32767 * (0.08 * math.exp(-(i / 48000) / 0.15) + 0.003 * random.uniform(-1, 1))), 0) for i in range(96000))); w.close()
PY4
python3 -I "$HERE/uke-mic-rms.py" --click "$T/c.wav" | grep -E "click canal 0: .* delta (2[5-9]|3[0-9])\.[0-9] dB, estable a los (4|5|6|7|8)[0-9][0-9] ms" >/dev/null && ok "uke-mic-rms.py --click mide delta y tiempo de estabilizacion del chasquido sintetico" || ko "--click: $(python3 -I "$HERE/uke-mic-rms.py" --click "$T/c.wav" | grep 'canal 0')"
# (3) sintaxis UCM: el fichero de tarjeta y el HiFi existen y los Include apuntan a ficheros reales de alsa-ucm-conf
U=/usr/share/alsa/ucm2; miss=0
for f in $(grep -ohE 'File "[^"]+"' "$A/mic/ucm2/Qualcomm/uke/HiFi.conf" "$A/mic/ucm2/conf.d/sm8650/UKE.conf" | sed 's/File "//;s/"$//'); do [ -e "$U$f" ] || [ -e "$A/mic/ucm2$f" ] || { echo "     falta $f"; miss=1; }; done
[ $miss = 0 ] && ok "UCM «UKE»: todos los Include/File existen (alsa-ucm-conf o nuestros)" || ko "UCM con ficheros inexistentes"
echo "$pass ok, $fail fallos"; [ "$fail" = 0 ]
