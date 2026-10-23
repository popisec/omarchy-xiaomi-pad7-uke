#!/bin/bash
# test-bt-sleep.sh — prueba en el PC (sin tablet, sin red) el gancho uke-bt-sleep y el ayudante uke-bt-resume con mocks de
# bluetoothctl/systemctl y un arbol raiz falso (UKE_BT_ROOT). Demuestra: que `pre` guarda las MAC y apaga el adaptador, que no se
# cuelga si bluetoothctl se cuelga, que respeta el interruptor /etc/uke/no-bt, que `post` no bloquea, y que la reanudacion
# enciende y reconecta con reintentos y termina siempre con exit 0. Uso: test-bt-sleep.sh
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
HOOK=$HERE/../root/usr/lib/systemd/system-sleep/uke-bt-sleep
RES=$HERE/../root/usr/local/sbin/uke-bt-resume
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/root/sys/class/bluetooth/hci0" "$T/root/var/log" "$T/root/var/lib/uke" "$T/root/etc/uke" "$T/root/run" "$T/root/sys/devices/platform/soc/8c0000.qcom,qupv3_1_geni_se/888000.qcom,qup_uart/power"
cat > "$T/bin/bluetoothctl" <<'MOCK'
#!/bin/bash
echo "bluetoothctl $*" >> "$MOCK_LOG"
[ "${MOCK_HANG:-0}" = 1 ] && sleep 30
case "$1" in
	show) case "${MOCK_SHOW:-on}" in
		nocontroller) echo "No default controller available"; exit 1 ;;
		off) printf 'Controller AA:BB:CC:00:00:01 (public)\n\tPowered: no\n' ;;
		*) printf 'Controller AA:BB:CC:00:00:01 (public)\n\tPowered: yes\n' ;; esac ;;
	devices) printf 'Device AA:BB:CC:DD:EE:01 Auriculares\nDevice AA:BB:CC:DD:EE:02 Lapiz\n' ;;
	power) if [ "$2" = on ]; then n=$(cat "$MOCK_STATE.poweron" 2>/dev/null || echo 0); if [ "$n" -gt 0 ]; then echo $((n - 1)) > "$MOCK_STATE.poweron"; exit 1; fi; fi ;;
	connect) n=$(( $(cat "$MOCK_STATE.$2" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$MOCK_STATE.$2" ;;
	info) case "$2" in
			*:01) echo "	UUID: Audio Sink                (0000110b-0000-1000-8000-00805f9b34fb)"; echo "	UUID: A/V Remote Control        (0000110e-0000-1000-8000-00805f9b34fb)" ;;
			*:02) echo "	UUID: Human Interface Device    (00001124-0000-1000-8000-00805f9b34fb)" ;; esac
		n=$(cat "$MOCK_STATE.$2" 2>/dev/null || echo 0)
		if [ "$n" -ge "${MOCK_CONNECT_AFTER:-1}" ]; then echo "	Connected: yes"; else echo "	Connected: no"; fi ;;
esac
exit 0
MOCK
cat > "$T/bin/systemctl" <<'MOCK'
#!/bin/bash
[ "$1" = is-active ] && exit "${MOCK_BT_ACTIVE:-0}"
exit 0
MOCK
# systemd-run simulado: registra la llamada y ejecuta la orden DESACOPLADA (como una unidad transitoria); MOCK_SRUN_FAIL=1 -> falla como si no hubiera systemd
cat > "$T/bin/systemd-run" <<'MOCK'
#!/bin/bash
echo "systemd-run $*" >> "$MOCK_SRUN"
[ "${MOCK_SRUN_FAIL:-0}" = 1 ] && exit 1
while [ $# -gt 0 ]; do case "$1" in --*) shift ;; *) break ;; esac; done
( "$@" >/dev/null 2>&1 < /dev/null & )
exit 0
MOCK
cat > "$T/up" <<'MOCK'
#!/bin/bash
echo "$* [cycles=${UKE_BT_CYCLES:-}]" >> "$MOCK_UP"
exit "${MOCK_UP_RC:-0}"
MOCK
chmod +x "$T/bin/bluetoothctl" "$T/bin/systemctl" "$T/bin/systemd-run" "$T/up"
export UKE_BT_ROOT=$T/root UKE_BT_PATH=$T/bin:/usr/bin:/bin UKE_BT_TMO=2 UKE_BT_TRIES=3 UKE_BT_PAUSE=0 UKE_BT_WAIT=1 MOCK_LOG=$T/calls MOCK_SRUN=$T/srun MOCK_STATE=$T/st MOCK_UP=$T/upcalls UKE_BT_UP=$T/up
fail=0; n=0
ck() { local d=$1; shift; n=$((n + 1)); if "$@"; then printf '  OK   %s\n' "$d"; else printf '  FALLO %s\n' "$d"; fail=1; fi; }
UW="$T/root/sys/devices/platform/soc/8c0000.qcom,qupv3_1_geni_se/888000.qcom,qup_uart/power/wakeup"
reset() { unset MOCK_SHOW MOCK_UP_RC UKE_BT_RECOVER; rm -f "$T"/calls "$T"/srun "$T"/upcalls "$T"/st.* "$T/root/var/lib/uke/bt-last" "$T/root/var/log/uke-bt.log" "$T/root/etc/uke/no-bt" "$T/root/run/uke-bt-uartwake"; echo enabled > "$UW"; : > "$T/calls"; : > "$T/srun"; unset MOCK_HANG; export MOCK_BT_ACTIVE=0 MOCK_CONNECT_AFTER=1; }
calls() { grep -c . "$T/calls"; }
since() { local a b; a=$(date +%s.%N); "$@"; b=$(date +%s.%N); awk -v a="$a" -v b="$b" 'BEGIN{printf "%.2f", b - a}'; }

echo "== gancho: pre/suspend =="
reset; "$HOOK" pre suspend; rc=$?
ck "pre con bluetooth activo: rc 0" test "$rc" = 0
ck "pre: guarda en bt-last solo la MAC de AUDIO (el lapiz HID/LE se omite)" bash -c "test \"\$(cat '$T/root/var/lib/uke/bt-last')\" = 'AA:BB:CC:DD:EE:01'"
ck "pre: lo anota (conectados=2, de audio guardados=1)" grep -q 'conectados=2, de audio guardados=1' "$T/root/var/log/uke-bt.log"
ck "pre: llama a 'bluetoothctl power off'" grep -q '^bluetoothctl power off' "$T/calls"
ck "pre: el orden es devices Connected y luego power off" bash -c "test \"\$(grep -n 'devices Connected' '$T/calls' | cut -d: -f1)\" -lt \"\$(grep -n 'power off' '$T/calls' | cut -d: -f1)\""
reset; export MOCK_BT_ACTIVE=1; "$HOOK" pre suspend; rc=$?
ck "pre con bluetooth.service inactivo: rc 0 y cero llamadas a bluetoothctl" bash -c "test $rc = 0 && test $(calls) = 0 && ! test -e '$T/root/var/lib/uke/bt-last'"
reset; touch "$T/root/etc/uke/no-bt"; "$HOOK" pre suspend; rc=$?
ck "interruptor /etc/uke/no-bt: no hace nada (rc 0, cero llamadas)" bash -c "test $rc = 0 && test $(calls) = 0"
reset; rm -rf "$T/root/sys/class/bluetooth/hci0"; "$HOOK" pre suspend; rc=$?
ck "sin hci0: no hace nada (rc 0, cero llamadas)" bash -c "test $rc = 0 && test $(calls) = 0"
mkdir -p "$T/root/sys/class/bluetooth/hci0"
reset; "$HOOK" pre hibernate; rc=$?
ck "pre/hibernate (no es suspension): no hace nada" bash -c "test $rc = 0 && test $(calls) = 0"
reset; export MOCK_HANG=1; t=$(since "$HOOK" pre suspend)
ck "bluetoothctl colgado: el gancho vuelve en < 8 s (timeout) y con rc 0 (tardo ${t}s)" bash -c "awk -v t=$t 'BEGIN{exit !(t < 8)}'"
unset MOCK_HANG
reset; MOCK_SHOW=nocontroller; export MOCK_SHOW; t=$(since "$HOOK" pre suspend); rc=$?
ck "sin controlador (chip mudo): rc 0, sin 'power off' y rapido (${t}s < 1 s; antes esperaba el timeout)" bash -c "test $rc = 0 && ! grep -q 'power off' '$T/calls' && awk -v t=$t 'BEGIN{exit !(t < 1)}'"
ck "sin controlador: bt-last queda VACIO (no queda una lista vieja)" bash -c "test ! -s '$T/root/var/lib/uke/bt-last'"
ck "sin controlador: lo anota" grep -q 'sin controlador' "$T/root/var/log/uke-bt.log"
reset; printf 'AA:BB:CC:DD:EE:01\n' > "$T/root/var/lib/uke/bt-last"; MOCK_SHOW=nocontroller "$HOOK" pre suspend
ck "una lista vieja de una suspension anterior se vacia" bash -c "test ! -s '$T/root/var/lib/uke/bt-last'"
reset; MOCK_SHOW=off "$HOOK" pre suspend; rc=$?
ck "adaptador ya apagado: rc 0, sin 'power off' ni consulta de dispositivos" bash -c "test $rc = 0 && ! grep -q 'power off' '$T/calls' && ! grep -q 'devices' '$T/calls' && grep -q 'ya apagado' '$T/root/var/log/uke-bt.log'"
reset; export MOCK_HANG=1; "$HOOK" pre suspend >/dev/null 2>&1; unset MOCK_HANG
ck "bluetoothctl colgado: no llama a 'power off' (una sola espera, no varias)" bash -c "test \$(grep -c '^bluetoothctl' '$T/calls') = 1"

reset; touch "$T/root/etc/uke/bt-keep-on"; "$HOOK" pre suspend; rc=$?
ck "bt-keep-on: rc 0, NO apaga el adaptador (sin 'power off', sin consultar dispositivos)" bash -c "test $rc = 0 && ! grep -q 'power off' '$T/calls' && ! grep -q 'devices' '$T/calls'"
ck "bt-keep-on: aun asi desactiva el despertar por el UART (si no, s2idle saldria al instante) y lo anota" bash -c "test \"\$(cat '$UW')\" = disabled && grep -q 'bt-keep-on' '$T/root/var/log/uke-bt.log'"
ck "bt-keep-on: bt-last queda vacio (nada que reconectar al volver)" bash -c "test ! -s '$T/root/var/lib/uke/bt-last'"
rm -f "$T/root/etc/uke/bt-keep-on"

echo "== gancho: despertar por el UART (IRQ 229) =="
reset; "$HOOK" pre suspend
ck "pre: desactiva power/wakeup del UART del BT (estaba enabled)" test "$(cat "$UW")" = disabled
ck "pre: lo registra en el log" grep -q 'despertar por el UART del BT desactivado' "$T/root/var/log/uke-bt.log"
reset; export MOCK_BT_ACTIVE=1; "$HOOK" pre suspend
ck "pre con bluetooth.service inactivo: el UART tambien queda sin despertar (hci_uart cargado a mano)" test "$(cat "$UW")" = disabled
reset; touch "$T/root/etc/uke/no-bt"; "$HOOK" pre suspend
ck "pre con /etc/uke/no-bt: no toca el UART" test "$(cat "$UW")" = enabled
reset; rm -rf "$T/root/sys/devices/platform/soc"; "$HOOK" pre suspend; rc=$?
ck "pre sin dispositivo del UART (overlay descargado): rc 0 y sin error" test "$rc" = 0
mkdir -p "$T/root/sys/devices/platform/soc/8c0000.qcom,qupv3_1_geni_se/888000.qcom,qup_uart/power"
reset; "$HOOK" pre suspend; UKE_BT_RESUME=$T/no-existe "$HOOK" post suspend
ck "post: restaura power/wakeup a su valor anterior (enabled)" test "$(cat "$UW")" = enabled
ck "post: lo registra en el log" grep -q "despertar por el UART del BT restaurado a 'enabled'" "$T/root/var/log/uke-bt.log"
reset; echo disabled > "$UW"; "$HOOK" pre suspend; UKE_BT_RESUME=$T/no-existe "$HOOK" post suspend
ck "post: si ya estaba disabled antes, lo deja disabled (no inventa)" test "$(cat "$UW")" = disabled
echo "== gancho: post/suspend =="
reset; cat > "$T/slowres" <<'SLOW'
#!/bin/bash
sleep 3; echo hecho > "$UKE_BT_ROOT/resume-ran"
SLOW
chmod +x "$T/slowres"; rm -f "$T/root/resume-ran"
t=$(UKE_BT_RESUME=$T/slowres since "$HOOK" post suspend)
ck "post: el gancho vuelve al instante aunque el ayudante tarde (volvio en ${t}s, ayudante de 3 s)" bash -c "awk -v t=$t 'BEGIN{exit !(t < 1.5)}'"
ck "post: el ayudante se lanzo y termina por su cuenta" bash -c "for i in \$(seq 1 40); do [ -e '$T/root/resume-ran' ] && exit 0; sleep 0.2; done; exit 1"
ck "post: lanza el ayudante con systemd-run --no-block --collect (unidad transitoria, no un proceso suelto del cgroup de systemd-suspend)" bash -c "grep -q 'systemd-run --no-block --collect --unit=uke-bt-resume-' '$T/srun' && grep -q 'slowres' '$T/srun'"
reset; rm -f "$T/root/resume-ran"; MOCK_SRUN_FAIL=1 UKE_BT_RESUME=$T/slowres "$HOOK" post suspend
ck "post: sin systemd-run (falla), plan B desacoplado: el ayudante corre igualmente" bash -c "for i in \$(seq 1 40); do [ -e '$T/root/resume-ran' ] && exit 0; sleep 0.2; done; exit 1"
ck "post: el log distingue el plan B" grep -q 'sin systemd-run' "$T/root/var/log/uke-bt.log"
reset; touch "$T/root/etc/uke/no-bt"; rm -f "$T/root/resume-ran"; UKE_BT_RESUME=$T/slowres "$HOOK" post suspend; sleep 0.3
ck "post con /etc/uke/no-bt: no lanza el ayudante" bash -c "! test -e '$T/root/resume-ran'"
reset; UKE_BT_RESUME=$T/no-existe "$HOOK" post suspend; rc=$?
ck "post con ayudante inexistente: rc 0 igualmente" test "$rc" = 0

echo "== ayudante: uke-bt-resume =="
reset; export MOCK_BT_ACTIVE=0 MOCK_CONNECT_AFTER=2; printf 'AA:BB:CC:DD:EE:01\nAA:BB:CC:DD:EE:02\n' > "$T/root/var/lib/uke/bt-last"
"$RES"; rc=$?
ck "reanudacion: rc 0" test "$rc" = 0
ck "primero enciende el adaptador (power on) y despues conecta" bash -c "test \"\$(grep -n 'power on' '$T/calls' | head -1 | cut -d: -f1)\" -lt \"\$(grep -n 'connect' '$T/calls' | head -1 | cut -d: -f1)\""
ck "reintenta: con 'conecta a la 2.a orden' cada dispositivo recibe exactamente 2 connect y al comprobar la 3.a vez ya figura conectado" bash -c "test \"\$(grep -c 'connect AA:BB:CC:DD:EE:01' '$T/calls')\" = 2 && test \"\$(grep -c 'connect AA:BB:CC:DD:EE:02' '$T/calls')\" = 2"
ck "registra OK para los dos (con la MAC enmascarada)" bash -c "test \"\$(grep -c 'reconexion de AA:BB:CC:XX:XX:XX OK' '$T/root/var/log/uke-bt.log')\" = 2 && ! grep -q 'AA:BB:CC:DD:EE' '$T/root/var/log/uke-bt.log'"
reset; export MOCK_BT_ACTIVE=0 MOCK_CONNECT_AFTER=99; printf 'AA:BB:CC:DD:EE:01\n' > "$T/root/var/lib/uke/bt-last"
"$RES"; rc=$?
ck "si el dispositivo no conecta: tras 3 intentos termina con rc 0 y lo registra" bash -c "test $rc = 0 && test \"\$(grep -c 'connect AA:BB:CC:DD:EE:01' '$T/calls')\" = 3 && grep -q 'NO tras 3 intentos' '$T/root/var/log/uke-bt.log'"
reset; export MOCK_BT_ACTIVE=1; printf 'AA:BB:CC:DD:EE:01\n' > "$T/root/var/lib/uke/bt-last"
"$RES"; rc=$?
ck "con bluetooth.service inactivo: no toca nada (rc 0, cero llamadas)" bash -c "test $rc = 0 && test $(calls) = 0"
reset; export MOCK_BT_ACTIVE=0; "$RES"; rc=$?
ck "sin bt-last: enciende el adaptador y no intenta conectar nada" bash -c "test $rc = 0 && grep -q 'power on' '$T/calls' && ! grep -q 'connect' '$T/calls'"
reset; touch "$T/root/etc/uke/no-bt"; printf 'AA:BB:CC:DD:EE:01\n' > "$T/root/var/lib/uke/bt-last"; "$RES"; rc=$?
ck "con /etc/uke/no-bt: no hace nada" bash -c "test $rc = 0 && test $(calls) = 0"
echo "-- ayudante: solo audio y recuperacion del chip mudo --"
reset; export MOCK_BT_ACTIVE=0 MOCK_CONNECT_AFTER=1; printf 'AA:BB:CC:DD:EE:01\n' > "$T/root/var/lib/uke/bt-last"
"$RES"; rc=$?
ck "camino normal: power on bien -> no se llama a uke-bt-up.sh" bash -c "test $rc = 0 && test ! -e '$T/upcalls'"
reset; export MOCK_BT_ACTIVE=0 MOCK_CONNECT_AFTER=1; printf 'AA:BB:CC:DD:EE:01\n' > "$T/root/var/lib/uke/bt-last"; echo 1 > "$T/st.poweron"
"$RES"; rc=$?
ck "power on falla una vez: recuperacion con --down y luego --service con UKE_BT_CYCLES=3" bash -c "test $rc = 0 && test \"\$(cat '$T/upcalls')\" = '--down [cycles=]
--service [cycles=3]'"
ck "tras la recuperacion enciende y lo anota" grep -q 'adaptador encendido tras la recuperacion' "$T/root/var/log/uke-bt.log"
ck "y luego reconecta el dispositivo de audio" grep -q 'reconexion de AA:BB:CC:XX:XX:XX OK' "$T/root/var/log/uke-bt.log"
reset; export MOCK_BT_ACTIVE=0; echo 5 > "$T/st.poweron"; printf 'AA:BB:CC:DD:EE:01\n' > "$T/root/var/lib/uke/bt-last"
"$RES"; rc=$?
ck "power on no responde ni tras la recuperacion: ROJO registrado y rc 0 (nunca bloquea)" bash -c "test $rc = 0 && grep -q 'ROJO: el adaptador no enciende ni tras la recuperacion' '$T/root/var/log/uke-bt.log'"
reset; export MOCK_BT_ACTIVE=0 MOCK_UP_RC=3; echo 1 > "$T/st.poweron"; printf 'AA:BB:CC:DD:EE:01\n' > "$T/root/var/lib/uke/bt-last"
"$RES"; rc=$?
ck "uke-bt-up.sh falla (rc 3): se registra su rc y el ayudante termina con rc 0" bash -c "test $rc = 0 && grep -q 'recuperacion: uke-bt-up.sh rc=3' '$T/root/var/log/uke-bt.log'"
reset; export MOCK_BT_ACTIVE=0 UKE_BT_RECOVER=0; echo 1 > "$T/st.poweron"; printf 'AA:BB:CC:DD:EE:01\n' > "$T/root/var/lib/uke/bt-last"
"$RES"; rc=$?
ck "UKE_BT_RECOVER=0: sin recuperacion aunque falle el power on" bash -c "test $rc = 0 && test ! -e '$T/upcalls'"
ck "sintaxis de gancho y ayudante" bash -c "bash -n '$HOOK' && bash -n '$RES'"
ck "ni el gancho ni el ayudante escriben direcciones BD ni usan rfkill/hciconfig/reboot" bash -c "! grep -E 'hciconfig|rfkill|reboot|systemctl (restart|stop|start)' '$HOOK' '$RES'"

echo
if [ "$fail" = 0 ]; then echo "TODO OK ($n comprobaciones)"; else echo "HAY FALLOS"; exit 1; fi
