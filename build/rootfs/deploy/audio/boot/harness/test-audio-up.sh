#!/bin/bash
# Prueba de uke-audio-up.sh en el PC con mocks (sin tocar ninguna tablet). Cubre: requisitos (kernel, snd-q6apm de updates/, vermagic, overlay
# alternativo, ADSP), VERDE, AMARILLO, ROJO (CMD timeout / modprobe apr fallido con retirada del overlay) y --down.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT=$HERE/root/usr/local/sbin/uke-audio-up.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
ko() { printf '  FALLA %s\n' "$1"; fail=$((fail+1)); }
mkroot() { # mkroot NOMBRE
	R=$T/$1; rm -rf "$R"; mkdir -p "$R/proc" "$R/sys/class/remoteproc/remoteproc1" "$R/var/log" "$R/bin" "$R/run"
	: > "$R/proc/modules"; : > "$R/dmesg"
	echo adsp > "$R/sys/class/remoteproc/remoteproc1/name"; echo running > "$R/sys/class/remoteproc/remoteproc1/state"
	cat > "$R/bin/uname" <<EOS
#!/bin/bash
echo "\${MOCK_KREL:-7.2.9-senemos.1.4054.3-ouke4}"
EOS
	cat > "$R/bin/id" <<EOS
#!/bin/bash
echo 0
EOS
	printf '#!/bin/bash\nexit 0\n' > "$R/bin/sync"; printf '#!/bin/bash\nexit 0\n' > "$R/bin/sleep"
	cat > "$R/bin/dmesg" <<EOS
#!/bin/bash
cat "$R/dmesg"
EOS
	cat > "$R/bin/modinfo" <<EOS
#!/bin/bash
# modinfo -n NOMBRE | modinfo -F vermagic NOMBRE
if [ "\$1" = -n ]; then
  case "\$2" in
    uke_audio_e2d) echo /lib/modules/k/extra/uke_audio_e2d.ko ;;
    snd-q6apm) echo "\${MOCK_Q6APM:-/lib/modules/k/updates/snd-q6apm.ko}" ;;
    *) exit 1 ;;
  esac
elif [ "\$1" = -F ]; then echo "\${MOCK_VERMAGIC:-7.2.9-senemos.1.4054.3-ouke4} SMP preempt mod_unload aarch64"; fi
EOS
	cat > "$R/bin/modprobe" <<EOS
#!/bin/bash
# modprobe [-r] mod : simula carga/descarga en proc/modules y las lineas de dmesg
M="$R/proc/modules"
if [ "\$1" = -r ]; then sed -i "/^\$2 /d" "\$M"; exit 0; fi
case "\$1" in
  uke_audio_e2d) echo "uke_audio_e2d 12288 0 - Live 0x0" >> "\$M"; echo "[1.0] uke_audio_e2d: overlay aplicado" >> "$R/dmesg" ;;
  apr) [ -n "\${MOCK_APR_FAIL:-}" ] && exit 1
       for m in apr snd_q6apm q6apm_dai q6apm_lpass_dais q6prm; do echo "\$m 1 0 - Live 0x0" >> "\$M"; done
       case "\${MOCK_APM:-ok}" in
         ok) echo "[2.0] qcom-apm gprsvc:service:2:3: uke: estado APM (async) = 1" >> "$R/dmesg"; echo "q6prm_clocks 1 0 - Live 0x0" >> "\$M" ;;
         noclk) echo "[2.0] qcom-apm gprsvc:service:2:3: uke: estado APM (async) = 1" >> "$R/dmesg" ;;
         timeout) echo "[2.0] qcom-apm gprsvc:service:2:3: CMD timeout for [1001021] opcode" >> "$R/dmesg" ;;
         none) ;;
       esac ;;
  *) exit 1 ;;
esac
EOS
	chmod +x "$R"/bin/*
}
run() { UKE_AUDIO_ROOT=$R UKE_AUDIO_PATH="$R/bin:/usr/bin:/bin" UKE_AUDIO_WAIT_ADSP=1 UKE_AUDIO_WAIT_APM=2 "$@" > "$R/out" 2>&1; echo $? > "$R/rc"; cat "$R/rc"; }
rc() { cat "$R/rc"; }
chk() { [ "$(rc)" = "$2" ] && ok "$1 (exit $2)" || { ko "$1: exit $(rc), esperado $2"; sed 's/^/      /' "$R/out" | tail -4; }; }

echo "== requisitos =="
mkroot a; MOCK_KREL=7.2.9-senemos.1.4054.3-ouke3 run "$SCRIPT" >/dev/null;  chk "kernel ouke3 -> no hace nada" 1
mkroot b; MOCK_Q6APM=/lib/modules/k/kernel/sound/snd-q6apm.ko run "$SCRIPT" >/dev/null; chk "snd-q6apm sin parchear -> requisito" 1
grep -q 'NO es el parcheado' "$R/out" && ok "mensaje claro" || ko "mensaje"
mkroot c; MOCK_VERMAGIC=7.2.9-senemos.1.4054.3-ouke3 run "$SCRIPT" >/dev/null; chk "vermagic de e2d != kernel" 1
mkroot d; echo "uke_audio_e2 1 0 - Live 0x0" >> "$R/proc/modules"; run "$SCRIPT" >/dev/null; chk "overlay alternativo e2 cargado" 1
mkroot e; echo stopped > "$R/sys/class/remoteproc/remoteproc1/state"; run "$SCRIPT" >/dev/null; chk "ADSP no running" 1
grep -q 'uke_audio_e2d' "$R/proc/modules" && ko "no debe cargar nada con el ADSP parado" || ok "no cargo nada con el ADSP parado"
echo "== resultados =="
mkroot f; run "$SCRIPT" >/dev/null; chk "VERDE" 0
grep -q 'VERDE' "$R/out" && ok "dice VERDE" || ko "no dice VERDE"
[ -e "$R/run/uke-audio-apm-ok" ] && ok "VERDE deja el marcador /run/uke-audio-apm-ok" || ko "sin marcador de APM vivo"
mkroot f5; MOCK_KREL=7.2.9-senemos.1.4054.3-ouke5 MOCK_VERMAGIC=7.2.9-senemos.1.4054.3-ouke5 run "$SCRIPT" >/dev/null; chk "kernel ouke5 aceptado (VERDE)" 0
mkroot g; MOCK_APM=noclk run "$SCRIPT" >/dev/null; chk "AMARILLO: estado 1 sin q6prm_clocks" 2
mkroot h; MOCK_APM=none run "$SCRIPT" >/dev/null; chk "AMARILLO: sin ver el estado" 2
mkroot i; MOCK_APM=timeout run "$SCRIPT" >/dev/null; chk "ROJO: CMD timeout" 3
mkroot j; MOCK_APR_FAIL=1 run "$SCRIPT" >/dev/null; chk "ROJO: modprobe apr falla" 3
grep -q '^uke_audio_e2d ' "$R/proc/modules" && ko "el overlay debia retirarse si apr falla" || ok "overlay retirado si apr falla"
mkroot k; run "$SCRIPT" >/dev/null; run "$SCRIPT" >/dev/null; chk "segunda ejecucion: ya cargado, nada que hacer" 0
echo "== --down con la etapa 2 cargada =="
mkroot ld; run "$SCRIPT" >/dev/null; echo "uke_audio_e8b 1 0 - Live 0x0" >> "$R/proc/modules"; run "$SCRIPT" --down >/dev/null; chk "--down con e8b cargada: se niega" 1
grep -q 'uke_audio_e2d' "$R/proc/modules" && ok "no descarga la etapa 1 bajo una tarjeta viva" || ko "descargo la etapa 1 con e8b cargada"
echo "== --down y --status =="
mkroot l; run "$SCRIPT" >/dev/null; run "$SCRIPT" --down >/dev/null; chk "--down" 0
[ -z "$(cat "$R/proc/modules")" ] && ok "--down deja /proc/modules vacio" || ko "--down no descargo todo: $(cat "$R/proc/modules" | cut -d' ' -f1 | tr '\n' ' ')"
run "$SCRIPT" --status >/dev/null; chk "--status" 0
echo "== sintaxis y seguridad =="
bash -n "$SCRIPT" && ok "bash -n" || ko "bash -n"
! grep -nE 'echo +(stop|start) *>|/sys/class/remoteproc.*(state|recovery).*>|fastboot|dd +if=' "$SCRIPT" >/dev/null && ok "el guion no escribe en remoteproc ni toca slots" || ko "el guion toca remoteproc/slots"
echo "RESULTADO: $pass ok, $fail fallos"; [ "$fail" = 0 ]
