#!/bin/bash
# test-bt-up.sh — prueba EN EL PC el flujo de control de root/usr/local/sbin/uke-bt-up.sh con mocks
# (modprobe, dmesg, uname, id, modinfo, sleep, sync, wpa_cli) y un /proc /sys /etc /var falsos (UKE_BT_ROOT/UKE_BT_PATH).
# No carga nada, no toca el sistema, no abre ninguna conexion. Uso: test-bt-up.sh [ruta/a/uke-bt-up.sh]
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
S=${1:-$HERE/../root/usr/local/sbin/uke-bt-up.sh}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
M=$T/mock; mkdir -p "$M"
fail=0
cat > "$M/modprobe" <<'MOCK'
#!/bin/bash
echo "modprobe $*" >> "$UKE_BT_ROOT/calls"
[ "${1:-}" = -r ] && { [ "$(cat "$UKE_BT_ROOT/fail-unload" 2>/dev/null)" = "$2" ] && exit 1; n=$2; sed -i "/^$n /d" "$UKE_BT_ROOT/proc/modules"; [ "$n" = hci_uart ] && rm -rf "$UKE_BT_ROOT/sys/class/bluetooth/hci0"; case $n in uke_*) rm -rf "$UKE_BT_ROOT"/sys/bus/serial/devices/*;; esac; exit 0; }
n=$1
[ "$(cat "$UKE_BT_ROOT/fail-modprobe" 2>/dev/null)" = "$n" ] && exit 1
echo "$n 16384 0 - Live 0x0000000000000000" >> "$UKE_BT_ROOT/proc/modules"
case $n in
	uke_bt_b|uke_bt_a)	# el bus serdev se llama "serial": controlador serial0 y dispositivo serial0-0
		[ -f "$UKE_BT_ROOT/no-ctrl" ] || mkdir -p "$UKE_BT_ROOT/sys/bus/serial/devices/serial0"
		[ -f "$UKE_BT_ROOT/no-ctrl" ] || [ -f "$UKE_BT_ROOT/ctrl-only" ] || mkdir -p "$UKE_BT_ROOT/sys/bus/serial/devices/serial0-0" ;;
	hci_uart)	# k-esima carga de hci_uart: usa hci-lines.k / hci-late.k si existen (guion por ciclo), si no hci-lines / hci-late
		k=$(( $(cat "$UKE_BT_ROOT/hci-loads" 2>/dev/null || echo 0) + 1 )); echo "$k" > "$UKE_BT_ROOT/hci-loads"
		L=$UKE_BT_ROOT/hci-lines; [ -f "$L.$k" ] && L=$L.$k
		E=$UKE_BT_ROOT/hci-late; [ -f "$E.$k" ] && E=$E.$k
		[ -f "$UKE_BT_ROOT/make-hci0" ] && mkdir -p "$UKE_BT_ROOT/sys/class/bluetooth/hci0"
		[ -f "$L" ] && cat "$L" >> "$UKE_BT_ROOT/dmesg"
		[ -f "$E" ] && cp "$E" "$UKE_BT_ROOT/late-lines" ;;
esac
exit 0
MOCK
printf '#!/bin/bash\ncat "$UKE_BT_ROOT/dmesg"\n' > "$M/dmesg"
printf '#!/bin/bash\necho "${MOCK_KERNEL:-7.2.9-senemos.1.4054.3-ouke3}"\n' > "$M/uname"
printf '#!/bin/bash\necho 0\n' > "$M/id"
printf '#!/bin/bash\n[ -f "$UKE_BT_ROOT/no-modinfo" ] && exit 1\necho /lib/modules/x/extra/$2.ko\n' > "$M/modinfo"
cat > "$M/sleep" <<'MOCK'
#!/bin/bash
# registra la espera y, si hay lineas "tardias", entrega UNA por llamada (simula dmesg que crece con el tiempo)
echo "$*" >> "$UKE_BT_ROOT/sleeps"
if [ -s "$UKE_BT_ROOT/late-lines" ]; then
	head -1 "$UKE_BT_ROOT/late-lines" >> "$UKE_BT_ROOT/dmesg"
	tail -n +2 "$UKE_BT_ROOT/late-lines" > "$UKE_BT_ROOT/late-lines.tmp"; mv "$UKE_BT_ROOT/late-lines.tmp" "$UKE_BT_ROOT/late-lines"
fi
exit 0
MOCK
printf '#!/bin/bash\nexit 0\n' > "$M/sync"
printf '#!/bin/bash\n# systemctl show uke-wifi.service -p ActiveEnterTimestampMonotonic --value\ncat "$UKE_BT_ROOT/wifi-ts" 2>/dev/null\n' > "$M/systemctl"
printf '#!/bin/bash\necho wpa_state=COMPLETED\n' > "$M/wpa_cli"
chmod +x "$M"/*
export UKE_BT_PATH=$M:/usr/bin:/bin

new_root() { # crea un /proc /sys /etc /var /usr falsos con firmware falso y su manifiesto
	R=$T/root$1; rm -rf "$R"; export UKE_BT_ROOT=$R
	mkdir -p "$R"/{proc,sys/bus/serial/devices,sys/class/bluetooth,etc/modprobe.d,var/log,usr/lib/firmware/qca}
	: > "$R/proc/modules"; : > "$R/calls"
	printf 'fake1' > "$R/usr/lib/firmware/qca/msbtfw12.mbn"; printf 'fake2' > "$R/usr/lib/firmware/qca/msnv12.bin"
	(cd "$R" && sha256sum usr/lib/firmware/qca/msbtfw12.mbn usr/lib/firmware/qca/msnv12.bin > usr/lib/firmware/uke-bt-fw.sha256)
	printf 'options uke_bt_b bdaddr=02:11:22:33:44:55\n' > "$R/etc/modprobe.d/uke-bt.conf"
	printf '[    1.000000] unrelated line\n' > "$R/dmesg"
	printf '22.90 100.00\n' > "$R/proc/uptime"
}
run() { "$S" "$@" > "$T/out" 2>&1; echo $?; }
t() { # t "desc" esperado_rc comando...
	local d=$1 want=$2 rc; shift 2; rc=$("$@")
	if [ "$rc" = "$want" ]; then printf '  OK   %s (rc=%s)\n' "$d" "$rc"; else printf '  FALLO %s (rc=%s, esperado %s)\n' "$d" "$rc" "$want"; sed 's/^/       /' "$T/out"; fail=1; fi
}
chk() { local d=$1; shift; if "$@"; then printf '  OK   %s\n' "$d"; else printf '  FALLO %s\n' "$d"; sed 's/^/       /' "$T/out"; fail=1; fi; }
calls() { cat "$UKE_BT_ROOT/calls"; }
GREEN='[   10.000000] Bluetooth: hci0: QCA controller version 0x00130200
[   12.000000] Bluetooth: hci0: QCA setup on UART is completed'

echo "== variante B, camino feliz =="
new_root 1; touch "$R/make-hci0"; printf '%s\n' "$GREEN" > "$R/hci-lines"
t "verde: carga uke_bt_b y luego hci_uart" 0 run --service
chk "orden de modprobe: uke_bt_b, hci_uart" test "$(calls)" = "modprobe uke_bt_b
modprobe hci_uart"
chk "log menciona VERDE" grep -q VERDE "$T/out"
t "segunda vez: hci0 ya existe -> nada que hacer" 0 run --service
chk "sin modprobe extra" test "$(calls | wc -l)" = 2
t "--status no falla" 0 run --status
t "--down descarga hci_uart y el overlay" 0 run --down
chk "ya no hay modulos uke/hci" test ! -s "$R/proc/modules"
chk "orden de descarga: hci_uart primero" test "$(calls | tail -2)" = "modprobe -r hci_uart
modprobe -r uke_bt_b"

echo "== solo cuentan las lineas NUEVAS de dmesg =="
new_root 2; touch "$R/make-hci0"; printf '%s\n' "$GREEN" > "$R/dmesg"     # 'completed' VIEJO, de un intento anterior
t "amarillo: hci0 existe pero el 'completed' es viejo" 2 run --service

echo "== fallos =="
new_root 3; printf '[   11.000000] Bluetooth: hci0: QCA Failed to download firmware (-2)\n' > "$R/hci-lines"
t "rojo: un fallo aislado de firmware sin reintentos ni setup: no se da por bueno (rc 3 a los 90 s)" 3 run --service
new_root 4
t "rojo: sin hci0 ni lineas en 90 s" 3 run --service
new_root 5; echo uke_bt_b > "$R/fail-modprobe"
t "rojo: modprobe uke_bt_b falla" 3 run --service
chk "y no sigue con hci_uart" test "$(calls)" = "modprobe uke_bt_b"
new_root 6; echo hci_uart > "$R/fail-modprobe"
t "rojo: modprobe hci_uart falla" 3 run --service

echo "== el overlay no crea el dispositivo serdev (hipotesis 1 refutada): rojo y NO se carga hci_uart =="
new_root 12; touch "$R/ctrl-only" "$R/make-hci0"; printf '%s\n' "$GREEN" > "$R/hci-lines"
t "solo el controlador serial0, sin serial0-0: rojo" 3 run --service
chk "no carga hci_uart" test "$(calls)" = "modprobe uke_bt_b"
chk "el mensaje dice que no hay dispositivo serdev" grep -q 'no creo ningun dispositivo serdev' "$T/out"
new_root 13; touch "$R/no-ctrl" "$R/make-hci0"
t "ni siquiera controlador: rojo" 3 run --service
chk "el mock usa el bus real (/sys/bus/serial) y no inventa otro" bash -c "test -d '$R/sys/bus/serial/devices' && test ! -e '$R/sys/bus/'serdev"

echo "== el driver REINTENTA solo: los errores transitorios no son ROJO (fallo real del primer arranque en frio, 18-oct) =="
LATE_OK='[   22.817000] Bluetooth: hci0: setting up wcn6750
[   24.959000] Bluetooth: hci0: command 0xfc00 tx timeout
[   24.959100] Bluetooth: hci0: Reading QCA version information failed (-110)
[   25.063000] Bluetooth: hci0: Retry BT power ON:0
[   27.199000] Bluetooth: hci0: command 0xfc00 tx timeout
[   27.303000] Bluetooth: hci0: Retry BT power ON:1
[   27.419000] Bluetooth: hci0: QCA controller version 0x00130200
[   28.136000] Bluetooth: hci0: QCA setup on UART is completed'
new_root 14; touch "$R/make-hci0"; printf '%s\n' "$LATE_OK" > "$R/hci-late"
t "dos intentos fallidos y exito al 3o, con el dmesg creciendo: VERDE" 0 run --service
chk "anota los reintentos" grep -q 'VERDE (tras 2 reintento' "$T/out"
new_root 15; touch "$R/make-hci0"; printf '%s\n' "$LATE_OK" > "$R/hci-lines"
t "lo mismo con todo el dmesg ya presente: VERDE" 0 run --service
new_root 16; touch "$R/make-hci0"; printf '%s\n' "$GREEN" > "$R/hci-late"
t "sin reintentos: VERDE y sin mencionarlos" 0 run --service
chk "no habla de reintentos" bash -c "! grep -q 'reintento' '$T/out' || ! grep 'VERDE' '$T/out' | grep -q 'reintento'"
RETRY3_FAIL='[   22.817000] Bluetooth: hci0: setting up wcn6750
[   24.959000] Bluetooth: hci0: command 0xfc00 tx timeout
[   25.063000] Bluetooth: hci0: Retry BT power ON:0
[   27.199000] Bluetooth: hci0: command 0xfc00 tx timeout
[   27.303000] Bluetooth: hci0: Retry BT power ON:1
[   29.439000] Bluetooth: hci0: command 0xfc00 tx timeout
[   29.543000] Bluetooth: hci0: Retry BT power ON:2
[   31.679000] Bluetooth: hci0: command 0xfc00 tx timeout
[   31.679100] Bluetooth: hci0: Reading QCA version information failed (-110)'
new_root 17; touch "$R/make-hci0"; printf '%s\n' "$RETRY3_FAIL" > "$R/hci-late"
t "tres reintentos y el cuarto intento tambien falla: ROJO (se rindio)" 3 run --service
chk "el mensaje dice que el driver se rindio" grep -q 'el driver se rindio tras 3 reintentos' "$T/out"
chk "se rinde pronto: no espera los 90 s" bash -c "test \$(grep -c '^1\$' '$R/sleeps') -lt 40"
new_root 18; touch "$R/make-hci0"; head -5 <<<"$RETRY3_FAIL" > "$R/hci-late"
t "solo 2 fallos y luego silencio (sin 'Retry ...:2'): no es rendicion, AMARILLO a los 90 s" 2 run --service
chk "no dice que se rindio" bash -c "! grep -q 'se rindio' '$T/out'"
new_root 19; touch "$R/make-hci0"; { head -7 <<<"$RETRY3_FAIL"; printf '%s\n' "$GREEN"; } > "$R/hci-late"
t "fallo tras el ultimo Retry pero luego 'completed' a tiempo: VERDE" 0 run --service
new_root 20; printf '[   25.000000] Bluetooth: hci0: failed to open port\n' > "$R/hci-lines"
t "el driver no puede reabrir el puerto: ROJO inmediato" 3 run --service
chk "mensaje de puerto" grep -q 'no pudo reabrir el puerto' "$T/out"

echo "== reintento por ciclos completos (UKE_BT_CYCLES): --down + nuevo encendido si el driver se rinde =="
loads() { cat "$R/hci-loads" 2>/dev/null || echo 0; }
mkcycles() { # mkcycles N_root ciclo1 ciclo2 ... (cada ciclo = nombre de variable con las lineas del dmesg de esa carga de hci_uart)
	new_root "$1"; touch "$R/make-hci0"; shift; local k=1 v
	for v in "$@"; do printf '%s\n' "${!v}" > "$R/hci-late.$k"; k=$((k + 1)); done
}
CALLS_OK2='modprobe uke_bt_b
modprobe hci_uart
modprobe -r hci_uart
modprobe -r uke_bt_b
modprobe uke_bt_b
modprobe hci_uart'
mkcycles 30 RETRY3_FAIL LATE_OK
UKE_BT_CYCLES=3 UKE_BT_CYCLE_PAUSE=7 t "ciclo 1: el driver se rinde; ciclo 2: VERDE" 0 run --service
chk "secuencia: encender, --down (hci_uart y overlay) y volver a encender" test "$(calls)" = "$CALLS_OK2"
chk "dos cargas de hci_uart, no mas" test "$(loads)" = 2
chk "dice que reintenta por ciclos" grep -q 'ciclo 1/3: el chip no respondio; --down, pausa de 7 s y nuevo ciclo' "$T/out"
chk "dice el resultado final del ciclo 2" grep -q 'ciclo 2/3: resultado final rc=0 tras 1 ciclo(s) fallido(s)' "$T/out"
chk "hace la pausa entre ciclos (7 s)" grep -qx 7 "$R/sleeps"
chk "el VERDE final es el del ciclo 2 (con sus reintentos del driver)" grep -q 'VERDE (tras 2 reintento' "$T/out"
mkcycles 31 RETRY3_FAIL RETRY3_FAIL GREEN
UKE_BT_CYCLES=3 t "ciclos 1 y 2 fallan, el 3.o acierta: VERDE" 0 run --service
chk "tres cargas de hci_uart" test "$(loads)" = 3
chk "dos descargas completas entre ciclos" test "$(calls | grep -c '^modprobe -r hci_uart')" = 2
chk "dice ciclo 3/3" grep -q 'ciclo 3/3: resultado final rc=0 tras 2 ciclo(s) fallido(s)' "$T/out"
mkcycles 32 RETRY3_FAIL RETRY3_FAIL RETRY3_FAIL
UKE_BT_CYCLES=3 t "los 3 ciclos fallan: ROJO definitivo" 3 run --service
chk "exactamente 3 cargas de hci_uart (no un 4.o ciclo)" test "$(loads)" = 3
chk "termina con el chip descargado solo entre ciclos: 2 --down (el ultimo estado queda para diagnostico)" test "$(calls | grep -c '^modprobe -r hci_uart')" = 2
chk "mensaje de agotados" grep -q 'ROJO definitivo: agotados los 3 ciclo(s) de encendido' "$T/out"
chk "no espera los 90 s por ciclo" bash -c "test \$(grep -c '^1\$' '$R/sleeps') -lt 120"
mkcycles 33 RETRY3_FAIL
t "sin UKE_BT_CYCLES (por defecto 1): un fallo es ROJO como siempre" 3 run --service
chk "no hace --down ni segundo ciclo" bash -c "test \"\$(grep -c '^modprobe -r' '$R/calls')\" = 0 && test '$(loads)' = 1"
chk "no habla de ciclos" bash -c "! grep -q 'ciclo' '$T/out'"
mkcycles 34 RETRY3_FAIL GREEN
UKE_BT_CYCLES=basura t "UKE_BT_CYCLES invalido: se trata como 1 ciclo" 3 run --service
mkcycles 35 RETRY3_FAIL GREEN
UKE_BT_CYCLES=0 t "UKE_BT_CYCLES=0: se trata como 1 ciclo" 3 run --service
new_root 36; touch "$R/make-hci0"; printf '[   25.000000] Bluetooth: hci0: failed to open port\n' > "$R/hci-late.1"; printf '%s\n' "$GREEN" > "$R/hci-late.2"
UKE_BT_CYCLES=3 t "'failed to open port' en el ciclo 1 tambien se reintenta: VERDE al 2.o" 0 run --service
mkcycles 37 RETRY3_FAIL GREEN; echo hci_uart > "$R/fail-unload"
UKE_BT_CYCLES=3 t "no se puede descargar hci_uart para reintentar: ROJO" 3 run --service
chk "lo dice y no vuelve a cargar" bash -c "grep -q 'no pude descargar' '$T/out' && test '$(loads)' = 1"
echo "-- fallos deterministas: NO se reintentan aunque UKE_BT_CYCLES=3 --"
new_root 38; printf '[   11.000000] Bluetooth: hci0: QCA Failed to download firmware (-2)\n' > "$R/hci-lines"
UKE_BT_CYCLES=3 t "fallo de firmware sin 'rendicion' ni hci0 (ROJO a los 90 s): un solo ciclo" 3 run --service
chk "una sola carga de hci_uart y ningun --down" bash -c "test '$(loads)' = 1 && test \"\$(grep -c '^modprobe -r' '$R/calls')\" = 0"
new_root 39; echo uke_bt_b > "$R/fail-modprobe"
UKE_BT_CYCLES=3 t "modprobe uke_bt_b falla: no se reintenta" 3 run --service
chk "una sola llamada a modprobe" test "$(calls)" = "modprobe uke_bt_b"
new_root 40; touch "$R/ctrl-only" "$R/make-hci0"
UKE_BT_CYCLES=3 t "overlay sin dispositivo serdev: no se reintenta" 3 run --service
chk "no carga hci_uart ni descarga" test "$(calls)" = "modprobe uke_bt_b"
new_root 41; printf 'corrupto' > "$R/usr/lib/firmware/qca/msnv12.bin"
UKE_BT_CYCLES=3 t "firmware que no casa: rc 1 sin tocar nada" 1 run --service
chk "no llama a modprobe" test ! -s "$R/calls"
new_root 42; touch "$R/make-hci0"; head -5 <<<"$RETRY3_FAIL" > "$R/hci-late.1"
UKE_BT_CYCLES=3 t "AMARILLO (hci0 existe, silencio sin rendicion): no se reintenta" 2 run --service
chk "una sola carga" test "$(loads)" = 1
new_root 43; touch "$R/make-hci0"; printf '%s\n' "$GREEN" > "$R/hci-lines"
UKE_BT_CYCLES=3 t "VERDE al primer ciclo con CYCLES=3: no cambia nada" 0 run --service
chk "sin mensajes de ciclo ni descargas" bash -c "! grep -q 'ciclo' '$T/out' && test \"\$(grep -c '^modprobe -r' '$R/calls')\" = 0"
new_root 44; touch "$R/make-hci0"; printf '%s\n' "$GREEN" > "$R/hci-lines"
UKE_BT_VARIANT=u UKE_BT_CYCLES=3 t "variante U con CYCLES=3: igual que antes" 0 run --service

echo "== opciones de hci_uart (UKE_BT_HCI_OPTS): para el hci_uart parcheado (hciqca/) =="
new_root 45; touch "$R/make-hci0"; printf '%s\n' "$GREEN" > "$R/hci-lines"
UKE_BT_HCI_OPTS="uke_bt_boot_ms=150 uke_bt_swctrl_ms=300" t "con UKE_BT_HCI_OPTS: VERDE" 0 run --service
chk "las opciones llegan a 'modprobe hci_uart' (y solo a ese)" test "$(calls)" = "modprobe uke_bt_b
modprobe hci_uart uke_bt_boot_ms=150 uke_bt_swctrl_ms=300"
chk "el log las menciona" grep -q 'hci_uart cargado (opciones: uke_bt_boot_ms=150 uke_bt_swctrl_ms=300)' "$T/out"
new_root 46; touch "$R/make-hci0"; printf '%s\n' "$GREEN" > "$R/hci-lines"
t "sin UKE_BT_HCI_OPTS: modprobe hci_uart sin argumentos (como antes)" 0 run --service
chk "llamadas exactas" test "$(calls)" = "modprobe uke_bt_b
modprobe hci_uart"
chk "el log no habla de opciones" bash -c "! grep -q 'opciones:' '$T/out'"
mkcycles 47 RETRY3_FAIL GREEN
UKE_BT_CYCLES=3 UKE_BT_HCI_OPTS="uke_bt_low_ms=80" t "las opciones se repiten en cada ciclo de reintento" 0 run --service
chk "las dos cargas de hci_uart llevan las opciones" test "$(calls | grep -c '^modprobe hci_uart uke_bt_low_ms=80$')" = 2

echo "== colchon tras uke-wifi (UKE_BT_SETTLE) =="
settle_sleeps() { grep -vE '^(1|0\.2)$' "$R/sleeps" 2>/dev/null | tr '\n' ' '; }
new_root 22; touch "$R/make-hci0"; printf '%s\n' "$GREEN" > "$R/hci-lines"; printf '22560000\n' > "$R/wifi-ts"
UKE_BT_SETTLE=8 t "WiFi activo hace 0,34 s: espera lo que falta" 0 run --service
chk "una sola espera de ~7,66 s" test "$(settle_sleeps)" = "7.66 "
chk "dice por que espera" grep -q 'colchon: uke-wifi quedo activo hace 0.3 s' "$T/out"
new_root 23; touch "$R/make-hci0"; printf '%s\n' "$GREEN" > "$R/hci-lines"; printf '2000000\n' > "$R/wifi-ts"
UKE_BT_SETTLE=8 t "WiFi activo hace 20,9 s: no espera" 0 run --service
chk "sin esperas extra" test -z "$(settle_sleeps)"
new_root 24; touch "$R/make-hci0"; printf '%s\n' "$GREEN" > "$R/hci-lines"
UKE_BT_SETTLE=8 t "uke-wifi sin marca (omitido/apagado): no espera" 0 run --service
chk "sin esperas extra" test -z "$(settle_sleeps)"
new_root 25; touch "$R/make-hci0"; printf '%s\n' "$GREEN" > "$R/hci-lines"; printf '22560000\n' > "$R/wifi-ts"
t "UKE_BT_SETTLE sin definir (manual): no espera" 0 run --service
chk "sin esperas extra" test -z "$(settle_sleeps)"
new_root 26; printf '22560000\n' > "$R/wifi-ts"
UKE_BT_VARIANT=u UKE_BT_SETTLE=8 t "variante U (sin chip): no espera" 0 run --service
chk "sin esperas extra" test -z "$(settle_sleeps)"
new_root 27; touch "$R/make-hci0"; printf '%s\n' "$GREEN" > "$R/hci-lines"; printf '22560000\n' > "$R/wifi-ts"
UKE_BT_SETTLE=basura t "UKE_BT_SETTLE invalido: se ignora" 0 run --service

echo "== requisitos (rc=1, sin cargar nada) =="
new_root 7; printf 'corrupto' > "$R/usr/lib/firmware/qca/msnv12.bin"
t "firmware que no casa con el manifiesto" 1 run --service
chk "no llamo a modprobe" test ! -s "$R/calls"
new_root 8; touch "$R/no-modinfo"
t "modulo cargador ausente (modinfo falla)" 1 run --service
chk "no llamo a modprobe" test ! -s "$R/calls"
new_root 9
MOCK_KERNEL=7.2.0-rc2-palawan+ t "kernel que no es senemos" 1 run --service
chk "no llamo a modprobe" test ! -s "$R/calls"
new_root 10; echo "uke_bt_a 16384 0 - Live 0x0" > "$R/proc/modules"
t "otra variante ya cargada: no mezclo" 1 run --service
chk "no llamo a modprobe" test ! -s "$R/calls"
UKE_BT_VARIANT=z "$S" --status >/dev/null 2>&1; rc=$?
if [ "$rc" = 1 ]; then echo "  OK   variante invalida (rc=1)"; else echo "  FALLO variante invalida (rc=$rc, esperado 1)"; fail=1; fi

echo "== variante U (solo UART) =="
new_root 11; printf 'corrupto' > "$R/usr/lib/firmware/qca/msnv12.bin"      # la U no necesita firmware
UKE_BT_VARIANT=u t "verde sin firmware ni chip" 0 run --service
chk "carga uke_bt_uart y NO hci_uart" test "$(calls)" = "modprobe uke_bt_uart"
UKE_BT_VARIANT=u t "--down la descarga" 0 run --down

echo "== uso =="
t "argumento desconocido" 1 run --nada
[ "$fail" = 0 ] && echo "TODO OK" || echo "HAY FALLOS"
exit "$fail"
