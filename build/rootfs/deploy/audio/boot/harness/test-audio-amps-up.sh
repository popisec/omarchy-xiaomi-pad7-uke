#!/bin/bash
# Prueba de uke-audio-amps-up.sh en el PC con mocks (sin tocar ninguna tablet): requisitos, VERDE, AMARILLO, ROJO y --down.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT=$HERE/root/usr/local/sbin/uke-audio-amps-up.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
ko() { printf '  FALLA %s\n' "$1"; fail=$((fail+1)); }
mkroot() {
	R=$T/$1; rm -rf "$R"; mkdir -p "$R/proc/asound" "$R/var/log" "$R/bin" "$R/etc/uke" "$R/lib/firmware/qcom/sm8650" "$R/run" "$R/var/lib/uke/guard"; : > "$R/run/uke-audio-apm-ok"
	printf 'uke_audio_e2d 1 0 - Live 0x0\nsnd_q6apm 1 0 - Live 0x0\nq6prm_clocks 1 0 - Live 0x0\n' > "$R/proc/modules"; : > "$R/dmesg"; : > "$R/proc/asound/cards"
	echo x > "$R/lib/firmware/fs19xx.fsm"; echo x > "$R/lib/firmware/qcom/sm8650/UKE-tplg.bin"
	printf '#!/bin/bash\necho "${MOCK_KREL:-7.2.9-senemos.1.4054.3-ouke4}"\n' > "$R/bin/uname"
	printf '#!/bin/bash\n[ "${1:-}" = -u ] && [ -n "${2:-}" ] && { echo 1001; exit 0; }\necho 0\n' > "$R/bin/id"; printf '#!/bin/bash\nexit 0\n' > "$R/bin/sync"; printf '#!/bin/bash\nexit 0\n' > "$R/bin/sleep"
	printf '#!/bin/bash\ncat "%s/dmesg"\n' "$R" > "$R/bin/dmesg"
	cat > "$R/bin/modinfo" <<EOS
#!/bin/bash
[ -n "\${MOCK_NOMOD:-}" ] && [ "\$2" = "\$MOCK_NOMOD" ] && exit 1
echo /lib/modules/k/extra/\$2.ko
EOS
	cat > "$R/bin/amixer" <<EOS
#!/bin/bash
echo "\$@" >> "$R/amixer.log"; [ -n "\${MOCK_NOMIX:-}" ] && exit 1; exit 0
EOS
	cat > "$R/bin/modprobe" <<EOS
#!/bin/bash
M="$R/proc/modules"
n=\${2:-}; if [ "\$1" = -r ]; then n=\${n//-/_}; sed -i "/^\$n /d" "\$M"; exit 0; fi
[ "\${MOCK_FAIL:-}" = "\$1" ] && exit 1
echo "\${1//-/_} 1 0 - Live 0x0" >> "\$M"; echo "[1] \$1 ok" >> "$R/dmesg"
[ "\$1" = uke_fs19xx ] && echo "[2] uke-fs19xx-codec fs19xx-codec: probe" >> "$R/dmesg"
if [ "\$1" = uke_audio_e5 ]; then mkdir -p "$R/sys/bus/soundwire/devices/sdw:2:0:0217:010e:00:4" "$R/sys/bus/soundwire/devices/sdw:3:0:0217:010e:00:3"; st=\${MOCK_SDW:-Attached}; echo \$st > "$R/sys/bus/soundwire/devices/sdw:2:0:0217:010e:00:4/status"; echo \$st > "$R/sys/bus/soundwire/devices/sdw:3:0:0217:010e:00:3/status"; fi
if { [ "\$1" = uke_audio_e8b ] || [ "\$1" = uke_audio_e9a ]; } && [ -z "\${MOCK_NOCARD:-}" ]; then echo " 0 [UKE ]: x" > "$R/proc/asound/cards"; fi
exit 0
EOS
	cat > "$R/bin/ps" <<EOS
#!/bin/bash
[ -n "\${MOCK_PW_USER:-}" ] && echo " \$MOCK_PW_USER"; exit 0
EOS
	printf '#!/bin/bash\necho 1001\n' > "$R/bin/id.u"
	cat > "$R/bin/runuser" <<EOS
#!/bin/bash
# runuser -u USER -- cmd...
shift 3; echo "\$@" >> "$R/runuser.log"
if [ "\$1" = pw-cli ]; then [ -n "\${MOCK_PW_HASNODE:-}" ] && echo "node.name = uke-alsa-sink"; [ -n "\${MOCK_PW_HASMIC:-}" ] && echo "node.name = uke-mic"; exit 0; fi
exit 0
EOS
	chmod +x "$R"/bin/*
}
run() { UKE_AUDIO_ROOT=$R UKE_AUDIO_PATH="$R/bin:/usr/bin:/bin" UKE_AUDIO_WAIT_PROBE=1 UKE_AUDIO_WAIT_CARD=1 "$@" > "$R/out" 2>&1; echo $? > "$R/rc"; }
chk() { [ "$(cat "$R/rc")" = "$2" ] && ok "$1 (exit $2)" || { ko "$1: exit $(cat "$R/rc"), esperado $2"; tail -4 "$R/out" | sed 's/^/      /'; }; }
nomod() { loaded=$(grep -c "^$1 " "$R/proc/modules"); [ "$loaded" = 0 ]; }

echo "== requisitos =="
mkroot a; MOCK_KREL=7.2.9-senemos.1.4054.3-ouke3 run "$SCRIPT"; chk "kernel ouke3" 1
mkroot b; touch "$R/etc/uke/no-audio-amps"; run "$SCRIPT"; chk "interruptor no-audio-amps" 1
mkroot c; sed -i '/q6prm_clocks/d' "$R/proc/modules"; run "$SCRIPT"; chk "etapa 1 incompleta" 1
nomod uke_audio_e7i2c && ok "no carga nada sin etapa 1" || ko "cargo algo sin etapa 1"
mkroot d; rm "$R/lib/firmware/fs19xx.fsm"; run "$SCRIPT"; chk "falta preset" 1
mkroot e; MOCK_NOMOD=uke_fs19xx run "$SCRIPT"; chk "falta modulo uke_fs19xx" 1
mkroot f; echo "uke_audio_e2 1 0 - Live 0x0" >> "$R/proc/modules"; run "$SCRIPT"; chk "overlay alternativo e2" 1
mkroot o5; MOCK_KREL=7.2.9-senemos.1.4054.3-ouke5 run "$SCRIPT"; chk "kernel ouke5 aceptado (VERDE)" 0
echo "== carga =="
mkroot g; run "$SCRIPT"; chk "VERDE" 0
order=$(sed -n 's/^\[1\] \(.*\) ok$/\1/p' "$R/dmesg" | tr '\n' ' ')
[ "$order" = "uke_audio_e7i2c uke_audio_e3 pinctrl-sm8650-lpass-lpi uke_fs19xx uke_audio_e8b " ] && ok "orden e7i2c,e3,lpi,fs19xx,e8b" || ko "orden: $order"
grep -q 'MultiMedia1" on\|MultiMedia1 on\|MultiMedia1' "$R/amixer.log" && ok "mezclador activado" || ko "mezclador"
mkroot h; run "$SCRIPT"; run "$SCRIPT"; chk "segunda vez: nada que hacer" 0
mkroot i; MOCK_FAIL=uke_audio_e3 run "$SCRIPT"; chk "e3 falla -> ROJO" 3
nomod uke_audio_e8b && ok "sin tarjeta si falla e3" || ko "e8b cargado"
mkroot j; MOCK_FAIL=uke_audio_e8b run "$SCRIPT"; chk "e8b falla -> ROJO" 3
mkroot k; MOCK_NOCARD=1 run "$SCRIPT"; chk "sin tarjeta -> AMARILLO" 2
mkroot l; MOCK_NOMIX=1 run "$SCRIPT"; chk "sin mezclador -> AMARILLO" 2

mkroot p1; mkdir -p "$R/etc/pipewire/pipewire.conf.d"; : > "$R/etc/pipewire/pipewire.conf.d/51-uke-speakers.conf"
MOCK_PW_USER=omarchy run "$SCRIPT"; chk "PipeWire ya corria sin nodo: VERDE" 0
grep -q 'restart pipewire' "$R/runuser.log" 2>/dev/null && ok "reinicia pipewire de la sesion (tarjeta tardia)" || ko "no reinicio pipewire"
mkroot p2; mkdir -p "$R/etc/pipewire/pipewire.conf.d"; : > "$R/etc/pipewire/pipewire.conf.d/51-uke-speakers.conf"
MOCK_PW_USER=omarchy MOCK_PW_HASNODE=1 run "$SCRIPT"; chk "PipeWire con el nodo ya creado" 0
grep -q 'restart' "$R/runuser.log" 2>/dev/null && ko "reinicio pipewire sin necesidad" || ok "no reinicia si el nodo existe"
mkroot p3; mkdir -p "$R/etc/pipewire/pipewire.conf.d"; : > "$R/etc/pipewire/pipewire.conf.d/51-uke-speakers.conf"
run "$SCRIPT"; chk "sin PipeWire en marcha (arranque)" 0
grep -q 'restart' "$R/runuser.log" 2>/dev/null && ko "reinicio sin pipewire" || ok "al arrancar no toca pipewire"
mkroot p4; mkdir -p "$R/etc/pipewire/pipewire.conf.d"; : > "$R/etc/pipewire/pipewire.conf.d/51-uke-speakers.conf"
UKE_AUDIO_PW_REFRESH=0 MOCK_PW_USER=omarchy run "$SCRIPT"; chk "UKE_AUDIO_PW_REFRESH=0" 0
grep -q 'restart' "$R/runuser.log" 2>/dev/null && ko "reinicio con refresh=0" || ok "refresh=0 no reinicia"
echo "== tarjeta e9a (micro) =="
mkroot m9; UKE_AUDIO_CARD_MOD=uke_audio_e9a run "$SCRIPT"; chk "e9a: VERDE (e5 + WCD adjunto + tarjeta)" 0
order=$(sed -n 's/^\[1\] \(.*\) ok$/\1/p' "$R/dmesg" | tr '\n' ' ')
[ "$order" = "uke_audio_e7i2c uke_audio_e3 pinctrl-sm8650-lpass-lpi uke_fs19xx uke_audio_e5 uke_audio_e9a " ] && ok "orden e7i2c,e3,lpi,fs19xx,e5,e9a (sin e8b)" || ko "orden e9a: $order"
mkroot m10; MOCK_SDW=UNATTACHED UKE_AUDIO_FALLBACK=0 UKE_AUDIO_CARD_MOD=uke_audio_e9a run "$SCRIPT"; chk "e9a sin fallback: esclavos sin adjuntar -> ROJO" 3
nomod uke_audio_e9a && ok "sin fallback no carga la tarjeta si el WCD no se adjunta" || ko "cargo e9a sin WCD"
mkroot m10b; MOCK_SDW=UNATTACHED UKE_AUDIO_CARD_MOD=uke_audio_e9a run "$SCRIPT"; chk "e9a con fallback: esclavos sin adjuntar -> AMARILLO" 2
loaded_e8b=$(grep -c '^uke_audio_e8b ' "$R/proc/modules"); [ "$loaded_e8b" = 1 ] && nomod uke_audio_e9a && ok "fallback: carga e8b (altavoces) y no e9a" || ko "fallback no cargo e8b"
mkroot m11; UKE_AUDIO_FALLBACK=0 UKE_AUDIO_CARD_MOD=uke_audio_e9a MOCK_FAIL=uke_audio_e5 run "$SCRIPT"; chk "e9a sin fallback: falla e5 -> ROJO" 3
mkroot m11b; UKE_AUDIO_CARD_MOD=uke_audio_e9a MOCK_FAIL=uke_audio_e5 run "$SCRIPT"; chk "e9a con fallback: falla e5 -> AMARILLO (e8b)" 2
mkroot m11c; printf '#!/bin/bash\necho "$@" >> "%s/route.log"\n' "$R" > "$R/bin/route.sh"; chmod +x "$R/bin/route.sh"; UKE_AUDIO_CARD_MOD=uke_audio_e9a UKE_AUDIO_MIC_ROUTE=amic1 UKE_AUDIO_MIC_ROUTE_BIN="$R/bin/route.sh" run "$SCRIPT"; chk "e9a con UKE_AUDIO_MIC_ROUTE: VERDE" 0
grep -q -- "--apply amic1" "$R/route.log" 2>/dev/null && ok "aplica la ruta del micro (amic1) tras cargar e9a" || ko "no aplico la ruta del micro"
mkroot m11d; UKE_AUDIO_MIC_ROUTE=amic1 UKE_AUDIO_MIC_ROUTE_BIN="$R/bin/route.sh" run "$SCRIPT"; [ ! -s "$R/route.log" ] && ok "con e8b no aplica ruta de micro" || ko "aplico ruta con e8b"
mkroot m12; UKE_AUDIO_CARD_MOD=uke_audio_e9a run "$SCRIPT"; run "$SCRIPT" --down; chk "e9a: --down" 0
for m in uke_audio_e9a uke_audio_e5 uke_fs19xx; do nomod $m || ko "$m sigue cargado tras --down"; done
mkroot m13; run "$SCRIPT"; UKE_AUDIO_CARD_MOD=uke_audio_e9a run "$SCRIPT"; chk "e9a con e8b ya cargada: se niega" 1
mkroot p5; mkdir -p "$R/etc/pipewire/pipewire.conf.d"; : > "$R/etc/pipewire/pipewire.conf.d/51-uke-speakers.conf"; : > "$R/etc/pipewire/pipewire.conf.d/51-uke-mic.conf"
UKE_AUDIO_CARD_MOD=uke_audio_e9a UKE_AUDIO_MIC_ROUTE=amic1 UKE_AUDIO_MIC_ROUTE_BIN=/bin/true MOCK_PW_USER=omarchy MOCK_PW_HASNODE=1 run "$SCRIPT"; chk "e9a: PipeWire con uke-alsa-sink pero SIN uke-mic" 0
grep -q 'restart pipewire' "$R/runuser.log" 2>/dev/null && ok "reinicia pipewire si falta uke-mic (carrera con la ruta de micro)" || ko "no reinicio por falta de uke-mic"
mkroot p6; mkdir -p "$R/etc/pipewire/pipewire.conf.d"; : > "$R/etc/pipewire/pipewire.conf.d/51-uke-speakers.conf"; : > "$R/etc/pipewire/pipewire.conf.d/51-uke-mic.conf"
UKE_AUDIO_CARD_MOD=uke_audio_e9a UKE_AUDIO_MIC_ROUTE=amic1 UKE_AUDIO_MIC_ROUTE_BIN=/bin/true MOCK_PW_USER=omarchy MOCK_PW_HASNODE=1 MOCK_PW_HASMIC=1 run "$SCRIPT"; chk "e9a: PipeWire con los dos nodos" 0
grep -q 'restart' "$R/runuser.log" 2>/dev/null && ko "reinicio con los dos nodos" || ok "con los dos nodos no reinicia"
echo "== endurecimiento (revision critica 21-oct) =="
mkroot q1; rm -f "$R/run/uke-audio-apm-ok"; run "$SCRIPT"; chk "sin marcador de APM vivo: se omite" 1
nomod uke_audio_e7i2c && ok "no carga nada sin APM vivo" || ko "cargo sin APM"
mkroot q2; echo 1 > "$R/var/lib/uke/guard/audio-amps.fails"; UKE_AUDIO_CARD_MOD=uke_audio_e9a run "$SCRIPT"; chk "intento anterior sin completar: e9a degrada a e8b (AMARILLO)" 2
[ -e "$R/var/lib/uke/e9a-hang" ] && nomod uke_audio_e9a && nomod uke_audio_e5 && ok "marca e9a-hang y NO carga e5/e9a" || ko "no marco e9a-hang o cargo e5/e9a"
mkroot q3; mkdir -p "$R/var/lib/uke"; : > "$R/var/lib/uke/e9a-hang"; UKE_AUDIO_CARD_MOD=uke_audio_e9a run "$SCRIPT"; chk "marcador e9a-hang existente: sigue en e8b (AMARILLO)" 2
mkroot q4; MOCK_NOMOD=uke_audio_e5 UKE_AUDIO_CARD_MOD=uke_audio_e9a run "$SCRIPT"; chk "faltan los .ko de e5/e9a: cae a e8b (AMARILLO) en vez de dejar sin audio" 2
mkroot q5; MOCK_SDW=Alert UKE_AUDIO_CARD_MOD=uke_audio_e9a run "$SCRIPT"; chk "esclavos en Alert cuentan como adjuntos (VERDE)" 0
mkroot q6; MOCK_NOCARD=1 UKE_AUDIO_CARD_MOD=uke_audio_e9a UKE_AUDIO_MIC_ROUTE=amic1 UKE_AUDIO_MIC_ROUTE_BIN=/bin/true run "$SCRIPT"; chk "sin tarjeta tras e9a: AMARILLO" 2
grep -q "ruta de micro amic1 aplicada" "$R/out" && ok "aplica la ruta de micro y pw_refresh tambien en AMARILLO" || ko "no aplico la ruta en AMARILLO"
grep -q "uke-bootguard begin audio-amps" "$HERE/root/etc/systemd/system/uke-audio-amps.service" && ! grep -q "uke-bootguard begin audio$" "$HERE/root/etc/systemd/system/uke-audio-amps.service" && ok "la unidad de la etapa 2 usa su contador propio audio-amps" || ko "contador de la unidad"
echo "== down =="
mkroot m; run "$SCRIPT"; run "$SCRIPT" --down; chk "--down" 0
for m in uke_audio_e8b uke_fs19xx uke_audio_e3 uke_audio_e7i2c; do nomod $m || ko "$m sigue cargado"; done
loaded_e2d=$(grep -c '^uke_audio_e2d ' "$R/proc/modules"); [ "$loaded_e2d" = 1 ] && ok "--down no toca la etapa 1" || ko "--down toco e2d"
echo "$pass ok, $fail fallos"; [ "$fail" = 0 ]
