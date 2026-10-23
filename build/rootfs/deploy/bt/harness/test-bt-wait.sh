#!/bin/bash
# test-bt-wait.sh — prueba en el PC (sin tablet) uke-bt-wait con mocks de systemctl y busctl: que espera a org.bluez, que es
# ACOTADO, que no espera cuando no debe y que SIEMPRE sale con 0. Uso: test-bt-wait.sh
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
W=$HERE/../root/usr/local/sbin/uke-bt-wait
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/root/var/log" "$T/root/etc/uke" "$T/root/var/lib/uke/guard"
cat > "$T/bin/systemctl" <<'MOCK'
#!/bin/bash
case "$1" in
	is-enabled) case "$3" in uke-bt.service) exit "${MOCK_UKEBT_ENABLED:-0}" ;; bluetooth.service) exit "${MOCK_BT_ENABLED:-0}" ;; esac ;;
	is-active) [ "$2" = uke-bt.service ] && { echo "${MOCK_UKEBT_STATE:-activating}"; exit 0; } ;;
esac
exit 0
MOCK
cat > "$T/bin/busctl" <<'MOCK'
#!/bin/bash
# lista "NAME PID PROCESS ..." ; org.bluez aparece cuando existe $MOCK_BUS_READY
echo "org.freedesktop.DBus 1 systemd -"
# como busctl real: org.bluez figura SIEMPRE como activable (PID '-') y solo con PID cuando bluetoothd esta en marcha
if [ -e "$MOCK_BUS_READY" ]; then echo "org.bluez 123 bluetoothd -"; else echo "org.bluez - - - (activatable) - - -"; fi
exit 0
MOCK
chmod +x "$T/bin/"*
export UKE_BT_ROOT=$T/root UKE_BT_PATH=$T/bin:/usr/bin:/bin MOCK_BUS_READY=$T/ready UKE_BT_TICK=0.1 UKE_BT_WAIT_MAX=2 UKE_BT_WAIT_HARD=2
fail=0; n=0
ck() { local d=$1; shift; n=$((n + 1)); if "$@"; then printf '  OK   %s\n' "$d"; else printf '  FALLO %s\n' "$d"; fail=1; fi; }
reset() { rm -f "$T/ready" "$T/root/var/log/uke-bt.log" "$T/root/etc/uke/"* "$T/root/var/lib/uke/guard/"*; export MOCK_UKEBT_ENABLED=0 MOCK_BT_ENABLED=0 MOCK_UKEBT_STATE=activating; }
dur() { local a b r; a=$(date +%s.%N); "$@" >/dev/null 2>&1; r=$?; b=$(date +%s.%N); echo "$r" > "$T/rc"; awk -v a="$a" -v b="$b" 'BEGIN{printf "%.2f", b - a}'; }
lt() { awk -v t="$1" -v m="$2" 'BEGIN{exit !(t < m)}'; }
ge() { awk -v t="$1" -v m="$2" 'BEGIN{exit !(t >= m)}'; }

reset; touch "$T/ready"; t=$(dur "$W"); rc=$(cat "$T/rc")
ck "org.bluez ya en el bus: sale al instante con 0 (${t}s)" bash -c "test $rc = 0 && awk -v t=$t 'BEGIN{exit !(t < 0.5)}'"
reset; ( sleep 0.8; touch "$T/ready" ) & t=$(dur "$W"); rc=$(cat "$T/rc"); wait
ck "org.bluez aparece a los ~0,8 s: espera hasta entonces y sale con 0 (${t}s)" bash -c "test $rc = 0 && awk -v t=$t 'BEGIN{exit !(t >= 0.6 && t < 1.8)}'"
reset; t=$(dur "$W"); rc=$(cat "$T/rc")
ck "org.bluez no aparece nunca: sale por el limite de 2 s con 0 (${t}s) y lo registra" bash -c "test $rc = 0 && awk -v t=$t 'BEGIN{exit !(t >= 1.8 && t < 3.5)}' && grep -q 'timeout de 2 s' '$T/root/var/log/uke-bt.log'"
reset; t=$(dur "$W"); rc=$(cat "$T/rc")
ck "org.bluez solo ACTIVABLE (PID '-', como busctl real con bluetoothd parado): NO cuenta, espera hasta el limite (${t}s)" bash -c "test $rc = 0 && awk -v t=$t 'BEGIN{exit !(t >= 1.8)}'"
reset; touch "$T/root/etc/uke/no-bt"; t=$(dur "$W"); rc=$(cat "$T/rc")
ck "interruptor /etc/uke/no-bt: no espera (${t}s)" bash -c "test $rc = 0 && awk -v t=$t 'BEGIN{exit !(t < 0.5)}'"
reset; touch "$T/root/etc/uke/safe-mode"; t=$(dur "$W"); rc=$(cat "$T/rc")
ck "interruptor safe-mode: no espera (${t}s)" bash -c "test $rc = 0 && awk -v t=$t 'BEGIN{exit !(t < 0.5)}'"
reset; touch "$T/root/var/lib/uke/guard/bt.tripped"; t=$(dur "$W"); rc=$(cat "$T/rc")
ck "guarda bt disparada: no espera (${t}s)" bash -c "test $rc = 0 && awk -v t=$t 'BEGIN{exit !(t < 0.5)}'"
reset; export MOCK_UKEBT_ENABLED=1; t=$(dur "$W"); rc=$(cat "$T/rc")
ck "uke-bt.service no habilitado: no espera (${t}s)" bash -c "test $rc = 0 && awk -v t=$t 'BEGIN{exit !(t < 0.5)}'"
reset; export MOCK_BT_ENABLED=1; t=$(dur "$W"); rc=$(cat "$T/rc")
ck "bluetooth.service no habilitado: no espera (${t}s)" bash -c "test $rc = 0 && awk -v t=$t 'BEGIN{exit !(t < 0.5)}'"
reset; export MOCK_UKEBT_STATE=failed; t=$(dur "$W"); rc=$(cat "$T/rc")
ck "uke-bt.service fallido: no espera mas (${t}s)" bash -c "test $rc = 0 && awk -v t=$t 'BEGIN{exit !(t < 0.8)}' && grep -q 'fallo' '$T/root/var/log/uke-bt.log'"
# plazo extendido mientras uke-bt.service siga 'activating' (ciclos de reintento del encendido del chip)
reset; ( sleep 3; touch "$T/ready" ) & t=$(UKE_BT_WAIT_HARD=6 dur "$W"); rc=$(cat "$T/rc"); wait
ck "uke-bt activando y org.bluez aparece a los ~3 s (> MAX=2): espera hasta verlo y sale con 0 (${t}s)" bash -c "test $rc = 0 && awk -v t=$t 'BEGIN{exit !(t >= 2.8 && t < 4.5)}' && grep -q 'org.bluez en el bus' '$T/root/var/log/uke-bt.log'"
reset; t=$(UKE_BT_WAIT_HARD=4 dur "$W"); rc=$(cat "$T/rc")
ck "uke-bt activando y org.bluez no aparece nunca: tope duro de 4 s con 0 y lo registra (${t}s)" bash -c "test $rc = 0 && awk -v t=$t 'BEGIN{exit !(t >= 3.8 && t < 5.5)}' && grep -q 'timeout duro de 4 s' '$T/root/var/log/uke-bt.log'"
reset; export MOCK_UKEBT_STATE=active; t=$(UKE_BT_WAIT_HARD=4 dur "$W"); rc=$(cat "$T/rc")
ck "uke-bt ya NO esta activando (active) y no hay org.bluez: se corta en MAX=2 s, no sigue hasta el tope duro (${t}s)" bash -c "test $rc = 0 && awk -v t=$t 'BEGIN{exit !(t >= 1.8 && t < 3.0)}' && grep -q 'timeout de 2 s' '$T/root/var/log/uke-bt.log'"
reset; export MOCK_UKEBT_STATE=failed; t=$(UKE_BT_WAIT_HARD=4 dur "$W"); rc=$(cat "$T/rc")
ck "uke-bt fallo durante la espera extendida: sale al instante con 0 (${t}s)" bash -c "test $rc = 0 && awk -v t=$t 'BEGIN{exit !(t < 0.8)}'"
reset; t=$(UKE_BT_WAIT_HARD=1 dur "$W"); rc=$(cat "$T/rc")
ck "UKE_BT_WAIT_HARD menor que MAX: manda MAX (sin acortar el plazo normal) (${t}s)" bash -c "test $rc = 0 && awk -v t=$t 'BEGIN{exit !(t >= 1.8 && t < 3.5)}'"
ck "sintaxis" bash -n "$W"
ck "el script no arranca, para ni reinicia nada (solo lee systemctl/busctl)" bash -c "! grep -E 'systemctl (start|stop|restart|reload|enable|disable)|reboot|rfkill|bluetoothctl' '$W'"
echo
if [ "$fail" = 0 ]; then echo "TODO OK ($n comprobaciones)"; else echo "HAY FALLOS"; exit 1; fi
