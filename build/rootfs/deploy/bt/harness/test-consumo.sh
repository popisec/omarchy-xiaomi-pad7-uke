#!/bin/bash
# test-consumo.sh — prueba EN EL PC (sin tablet) consumo/bt-consumo.sh con una bateria y unos mocks falsos (potencia conocida por fase) y consumo/analiza-consumo.py
# contra deltas conocidos. Uso: test-consumo.sh
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd); BT=$(cd "$HERE/.." && pwd)
C=$BT/consumo/bt-consumo.sh; A=$BT/consumo/analiza-consumo.py
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0; ck() { local d=$1; shift; if "$@"; then printf '  OK   %s\n' "$d"; else printf '  FALLO %s\n' "$d"; fail=1; fi; }
echo "== argumentos y plan =="
ck "sintaxis" bash -n "$C"
out=$("$C" --dry-run -r 2 -R 1 -t 10 -s 60 2>&1); rc=$?
ck "--dry-run: rc 0, plan con las seis fases y la duracion" bash -c "test $rc = 0 && grep -q 's_hook, s_keepon, s_down' <<<'$out' && grep -q 'duracion estimada' <<<'$out'"
"$C" -r 0 --dry-run >/dev/null 2>&1; ck "-r 0: rc 1" test $? = 1
"$C" --sin-suspension --solo-suspension --dry-run >/dev/null 2>&1; ck "--sin-suspension con --solo-suspension: rc 1" test $? = 1
"$C" --nada >/dev/null 2>&1; ck "opcion desconocida: rc 1" test $? = 1
echo "== ejecucion con mocks (1 repeticion despierto + 1 en suspension, tiempo x0,02) =="
mkdir -p "$T/bin" "$T/bat" "$T/usb" "$T/etc"
printf '3800000\n' > "$T/bat/voltage_now"; printf -- '-500000\n' > "$T/bat/current_now"; printf '1000000\n' > "$T/bat/charge_counter"; printf '0\n' > "$T/usb/voltage_now"; printf '0\n' > "$T/usb/current_now"
cat > "$T/bin/bluetoothctl" <<'S'
#!/bin/bash
echo "bluetoothctl $*" >> "$MOCK/calls"
case "$1 $2" in "power off") printf "%s\n" -450000 > "$MOCK/bat/current_now" ;; "power on") printf "%s\n" -500000 > "$MOCK/bat/current_now" ;; esac
exit 0
S
cat > "$T/up" <<'S'
#!/bin/bash
echo "up $* [cycles=${UKE_BT_CYCLES:-}]" >> "$MOCK/calls"
case "$1" in --down) printf "%s\n" -400000 > "$MOCK/bat/current_now" ;; --service) printf "%s\n" -500000 > "$MOCK/bat/current_now" ;; esac
exit 0
S
cat > "$T/bin/rtcwake" <<'S'
#!/bin/bash
echo "rtcwake $*" >> "$MOCK/calls"; exit 0
S
cat > "$T/bin/systemctl" <<'S'
#!/bin/bash
# `systemctl suspend`: simula una suspension de 0,5 s y descuenta carga segun la variante (bt-keep-on presente = mas consumo)
echo "systemctl $*" >> "$MOCK/calls"
if [ "$1" = suspend ]; then
	sleep 0.5; q=$(cat "$MOCK/bat/charge_counter")
	if [ -e "$MOCK/etc/bt-keep-on" ]; then d=300; elif grep -q '^up --down' <(tail -n 3 "$MOCK/calls"); then d=80; else d=100; fi
	echo $((q - d)) > "$MOCK/bat/charge_counter"
fi
exit 0
S
printf '#!/bin/bash\nexit 0\n' > "$T/bin/sync"
printf '#!/bin/bash\necho 0\n' > "$T/bin/id"
chmod +x "$T/bin/"* "$T/up"
export MOCK=$T BT_BAT=$T/bat BT_USB=$T/usb BT_UP=$T/up BT_ETC=$T/etc BT_SCALE=0.02 PATH=$T/bin:$PATH
mkdir -p "$T/root"; export BT_ROOT=$T/root
"$C" -r 1 -R 1 -t 45 -s 300 -o "$T/consumo.log" > "$T/out.txt" 2>&1; rc=$?
ck "rc 0" test "$rc" = 0
[ "$rc" = 0 ] || tail -8 "$T/out.txt" | sed "s/^/       /"
ck "despierto: 5 lineas FASE (base, X, base, Y, base) con las dos fases una vez cada una" bash -c "test \$(grep -c '^FASE' '$T/consumo.log') = 5 && test \$(grep -c 'name=base' '$T/consumo.log') = 3 && grep -q 'name=bt_off' '$T/consumo.log' && grep -q 'name=bt_down' '$T/consumo.log'"
ck "las fases no-base van siempre entre dos bases" bash -c "grep '^FASE' '$T/consumo.log' | awk '{print \$2}' | sed 's/name=//' | tr '\n' ' ' | grep -qE '^base (bt_off bt_down|bt_down bt_off)' || grep '^FASE' '$T/consumo.log' | awk '{print \$2}' | sed 's/name=//' | tr '\n' ' ' | grep -qE '^base (bt_off|bt_down) base (bt_off|bt_down) base'"
ck "suspension: 5 lineas SUSP (s_hook, X, s_hook, Y, s_hook)" bash -c "test \$(grep -c '^SUSP' '$T/consumo.log') = 5 && test \$(grep -c 'name=s_hook' '$T/consumo.log') = 3"
ck "bt_off apaga y vuelve a encender el adaptador; bt_down descarga y vuelve con UKE_BT_CYCLES=3" bash -c "grep -q 'bluetoothctl power off' '$T/calls' && grep -q 'bluetoothctl power on' '$T/calls' && grep -q '^up --down' '$T/calls' && grep -q '^up --service \[cycles=3\]' '$T/calls'"
ck "cada suspension va precedida de rtcwake y de systemctl suspend (corre el gancho)" bash -c "test \$(grep -c '^rtcwake' '$T/calls') = 5 && test \$(grep -c '^systemctl suspend' '$T/calls') = 5"
ck "al terminar no queda bt-keep-on y se anota la restauracion" bash -c "test ! -e '$T/etc/bt-keep-on' && grep -q 'restaurado: BT encendido' '$T/consumo.log'"
ck "la corriente final es la de la base (BT encendido de nuevo)" test "$(cat "$T/bat/current_now")" = "-500000"
echo "== analiza-consumo.py: deltas conocidos =="
out=$(python3 -I "$A" "$T/consumo.log" 2>&1)
ck "bt_off: delta ~ -0,19 W (1,71 vs 1,90) y MENOS consumo" bash -c "grep -E '^ +bt_off ' <<<'$out' | grep -qE ' -0\\.1[89][0-9]' && grep -E '^ +bt_off ' <<<'$out' | grep -q 'MENOS consumo'"
ck "bt_down: delta ~ -0,38 W (1,52 vs 1,90) y MENOS consumo" bash -c "grep -E '^ +bt_down ' <<<'$out' | grep -qE ' -0\\.3[78][0-9]' && grep -E '^ +bt_down ' <<<'$out' | grep -q 'MENOS consumo'"
ck "suspension: s_keepon consume MAS que s_hook y s_down MENOS (por el descuento de carga simulado)" bash -c "grep -q 'delta s_keepon - s_hook: +' <<<'$out' && grep -q 'delta s_down - s_hook: -' <<<'$out'"
python3 -I - "$T/sint.log" <<'PY'
import sys
L = ['# sintetico']
def f(name, w, sem=0.01): L.append(f"FASE name={name} rep=1 t=00:00:00 dur=45 n=45 sys_w={w} sys_sem={sem} bat_w={w} usb_w=0.0 cpu_busy=1")
f('base', 1.400); f('bt_off', 1.402); f('base', 1.398); f('bt_down', 1.290); f('base', 1.400)       # bt_off ~ +0,003 (n.s.), bt_down ~ -0,11 (significativo)
def s(name, q1, usb='0.0', irq='184'): L.append(f"SUSP name={name} rep=1 t=00:00:00 dur_s=300.0 q0_uah=1000000 q1_uah={q1} v_uv=3800000 usb_w={usb} wake_irq={irq}")
s('s_hook', 999990); s('s_keepon', 999950); s('s_hook', 999991); s('s_down', 999993, usb='1.2'); s('s_hook', 999990); s('s_down', 999992, irq='120'); s('s_hook', 999991)
open(sys.argv[1], 'w').write('\n'.join(L) + '\n')
PY
out=$(python3 -I "$A" "$T/sint.log" 2>&1)
ck "sintetico: bt_off ~ +0,003 W = no significativo" bash -c "grep -E '^ +bt_off ' <<<'$out' | grep -q 'no significativo'"
ck "sintetico: bt_down ~ -0,11 W = MENOS consumo" bash -c "grep -E '^ +bt_down ' <<<'$out' | grep -q 'MENOS consumo'"
ck "sintetico: s_hook = (10 uAh · 3,8 V)/(300 s/3600) = 0,456 mW → 0,0004 W; s_keepon 50 uAh → 0,0023 W" bash -c "grep -E '^ +s_hook ' <<<'$out' | grep -qE ' 0\\.000[34]' && grep -E '^ +s_keepon ' <<<'$out' | grep -qE ' 0\\.002[23]'"
ck "sintetico: se descartan las suspensiones con USB conectado y con despertar distinto" bash -c "test \$(grep -c 'DESCARTADA' <<<'$out') = 2 && grep -q 'usb_w=1.2' <<<'$out' && grep -q 'wake_irq=120' <<<'$out'"
[ "$fail" = 0 ] && echo "TODO OK" || echo "HAY FALLOS"
exit "$fail"
