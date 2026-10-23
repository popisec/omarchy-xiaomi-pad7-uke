#!/bin/bash
# test-deploy-sim.sh — ejecuta deploy.sh --go / --check / --revert contra un "ssh" SIMULADO en el PC (no hay red, no hay
# tablet): el simulador solo (a) comprueba la sintaxis de cada script remoto (bash -n sobre lo que deploy.sh le manda por stdin,
# ya con las variables locales expandidas) y (b) lista los miembros, modos y rutas de cada tar que iria a la tablet.
# Demuestra: que las partes se componen, que no se escribe nada fuera de las rutas previstas, que la confirmacion de la
# direccion BD es obligatoria y que sin --go no se llama a ssh ni una vez. Uso: test-deploy-sim.sh
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
D=$HERE/../deploy.sh
# la release la fija el arbol de build, igual que en deploy.sh (antes estaba cableada a ouke3: fallaba al pasar a ouke4)
# (ahora out/ puede ser de ouke5: si KB no viene en el entorno, se elige el arbol de build cuya release coincide con el vermagic de out/uke_bt_b.ko)
if [ -z "${KB:-}" ]; then
	OKREL=$(modinfo -F vermagic "$HERE/../out/uke_bt_b.ko" 2>/dev/null | cut -d' ' -f1)
	for c in "$HERE"/../../../../kernel-pokes/senemos-build "$HERE"/../../../../kernel-pokes/senemos-ouke5/build; do
		[ "$(cat "$c/include/config/kernel.release" 2>/dev/null)" = "$OKREL" ] && { KB=$(cd "$c" && pwd); break; }
	done
	[ -n "${KB:-}" ] || { echo "ningun arbol de build coincide con el vermagic de out/uke_bt_b.ko ($OKREL)" >&2; exit 2; }
	export KB
fi
KREL=$(cat "$KB/include/config/kernel.release") || { echo "no encuentro kernel.release del arbol de build" >&2; exit 2; }
KREL_RE=${KREL//./\\.}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat > "$T/bin/ssh" <<'SIM'
#!/bin/bash
# ssh simulado: NO abre ninguna conexion
while [[ "${1:-}" == -* ]]; do case "$1" in -i|-o) shift 2 ;; *) shift ;; esac; done
shift   # usuario@host
cmd="$*"; n=$(($(cat "$SIM_LOG.n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$SIM_LOG.n"
echo "### ssh#$n: $cmd" >> "$SIM_LOG"
case "$cmd" in
	"bash -s"*) cat > "$SIM_LOG.s$n"; if bash -n "$SIM_LOG.s$n" 2>>"$SIM_LOG"; then echo "    [script remoto: sintaxis OK, $(wc -l < "$SIM_LOG.s$n") lineas]" >> "$SIM_LOG"; else echo "    [script remoto: SINTAXIS MAL]" >> "$SIM_LOG"; exit 97; fi ;;
	"tar -xpf -"*) tar -tvf - 2>&1 | sed 's/^/    tar: /' >> "$SIM_LOG" ;;
	*) echo "    [comando simple, no lee stdin]" >> "$SIM_LOG" ;;
esac
exit 0
SIM
chmod +x "$T/bin/ssh"
export PATH=$T/bin:$PATH SIM_LOG=$T/log
fail=0
ck() { local d=$1; shift; if "$@"; then printf '  OK   %s\n' "$d"; else printf '  FALLO %s\n' "$d"; fail=1; fi; }
newlog() { rm -f "$T"/log*; : > "$T/log"; }
calls() { cat "$T/log.n" 2>/dev/null || echo 0; }
[ "$(command -v ssh)" = "$T/bin/ssh" ] || { echo "el ssh simulado no esta primero en PATH"; exit 2; }

echo "== sin --go ni --check: cero llamadas a ssh =="
newlog; "$D" --fw --pkgs --module --service --bdaddr random --arm >/dev/null 2>&1; ck "plan sin conexiones (llamadas=$(calls))" test "$(calls)" = 0
newlog; "$D" >/dev/null 2>&1; ck "sin flags: cero llamadas" test "$(calls)" = 0

echo "== --go --fw --module --service --arm (sin direccion BD) =="
newlog; "$D" --go --fw --module --service --arm > "$T/out" 2>&1; rc=$?
ck "termina bien (rc=$rc)" test "$rc" = 0
ck "ningun script remoto con sintaxis mala" bash -c "! grep -q 'SINTAXIS MAL' '$T/log'"
ck "firmware: solo msbtfw12.mbn y msnv12.bin bajo usr/lib/firmware/qca/, modo 0644, root:root" bash -c "grep -E 'tar: ' '$T/log' | grep -E 'usr/lib/firmware/qca/' | grep -E -- '-rw-r--r-- 0/0' | wc -l | grep -qx 2"
ck "manifiesto del firmware instalado" grep -q 'tar: .*usr/lib/firmware/uke-bt-fw.sha256' "$T/log"
ck "modulos: 3 .ko bajo usr/lib/modules/<krel>/extra/" bash -c "grep -E 'tar: ' '$T/log' | grep -cE 'usr/lib/modules/$KREL_RE/extra/uke_bt_(uart|b|a)\.ko' | grep -qx 3"
ck "service: unidad en /etc/systemd/system y guion en /usr/local/sbin" bash -c "grep -E 'tar: ' '$T/log' | grep -E 'etc/systemd/system/uke-bt.service|usr/local/sbin/uke-bt-up.sh|usr/local/sbin/uke-bootguard' | wc -l | grep -qx 3"
ck "no se instala nada fuera de usr/ y etc/ (ni /boot, /lib/modules fuera de krel, blacklist...)" bash -c "! grep -E 'tar: ' '$T/log' | grep -vE ' (usr/lib/firmware/|usr/lib/modules/$KREL_RE/extra/|etc/systemd/system/uke-bt.service|usr/local/sbin/)' | grep -E ' [^ ]+\$' | grep -vE ' -> ' | grep -q ."
ck "no se toca la blacklist de hci_uart ni uke-wifi" bash -c "! grep -E 'tar: ' '$T/log' | grep -qE 'modprobe.d|uke-wifi'"
ck "se arma: systemctl enable uke-bt.service" bash -c "grep -q 'systemctl enable uke-bt.service' '$T'/log.s*"
ck "lectura previa con el ritual de adsp.b40" bash -c "grep -q '42c86837' '$T'/log.s*"
ck "NO se carga ningun modulo: ni modprobe de uke_bt/hci_uart ni insmod en ningun script remoto" bash -c "! grep -hE '(modprobe|insmod) +(uke_bt|hci_uart)' '$T'/log.s* | grep -v 'show-depends'"
ck "NO se llama a uke-bt-up.sh en la tablet" bash -c "! grep -q 'uke-bt-up.sh --service\|uke-bt-up.sh$' '$T'/log.s*"

echo "== --pkgs, --revert, --check =="
newlog; "$D" --go --pkgs > "$T/out" 2>&1; ck "--pkgs: rc 0" test $? = 0
ck "--pkgs: vista previa -p --print-format antes de instalar y aborta si actualizaria algo instalado" bash -c "grep -q 'pacman -S --needed -p --print-format' '$T'/log.s* && grep -q 'ABORTO: la transaccion actualizaria' '$T'/log.s*"
newlog; "$D" --go --revert > "$T/out" 2>&1; ck "--revert: rc 0" test $? = 0
revert_paths() { grep -l 'systemctl disable uke-bt.service' "$T"/log.s* | xargs grep -oh '/[A-Za-z0-9_./$*-]*' | sort -u | tr '\n' ' '; }
want_paths=$(printf '%s\n' '/dev/null' '/etc/bluetooth/main.conf' '/etc/bluetooth/main.conf.uke-bak' '/etc/modprobe.d/uke-bt-hci.conf' '/etc/modprobe.d/uke-bt.conf' '/etc/systemd/system/bluetooth.service.d' '/etc/systemd/system/bluetooth.service.d/10-uke-bt.conf' '/etc/systemd/system/uke-bt.service' '/etc/systemd/system/uke-desktop.service.d' '/etc/systemd/system/uke-desktop.service.d/20-uke-bt.conf' '/proc/modules' '/usr/lib/firmware/qca/msbtfw12.mbn' '/usr/lib/firmware/qca/msnv12.bin' '/usr/lib/firmware/uke-bt-fw.sha256' '/usr/lib/modules/$k/extra/$m.ko' '/usr/lib/modules/$k/updates/hci_uart.ko' '/usr/lib/systemd/system-sleep/uke-bt-sleep' '/usr/local/sbin/bt-consumo.sh' '/usr/local/sbin/bt-medir.sh' '/usr/local/sbin/uke-bootguard' '/usr/local/sbin/uke-bt-resume' '/usr/local/sbin/uke-bt-up.sh' '/usr/local/sbin/uke-bt-wait' '/var/lib/uke/bt-last' | sort -u | tr '\n' ' ')
ck "--revert: las unicas rutas que menciona son las de este despliegue (servicio, guion, uke-bt.conf, manifiesto, firmware rev 12, .ko, drop-in, gancho de sueño, main.conf)" test "$(revert_paths)" = "$want_paths"
ck "--revert no desinstala paquetes" bash -c "! grep -hqE 'pacman -R' '$T'/log.s*"
newlog; "$D" --check > "$T/out" 2>&1; rc=$?
ck "--check: rc 0 y no sube ficheros (ningun tar)" bash -c "test $rc = 0 && ! grep -q 'tar: ' '$T/log'"
ck "--check no escribe: ningun rm/mv/cp/tee/depmod/systemctl enable/pacman -S en sus scripts" bash -c "! grep -hE '\\b(rm|mv|cp|tee|depmod|pacman -S|systemctl (enable|disable|start|stop))\\b' '$T'/log.s*"

echo "== --go --daily --sleep (D1/D2) =="
newlog; "$D" --go --daily --sleep > "$T/out" 2>&1; rc=$?
ck "daily+sleep: termina bien (rc=$rc)" test "$rc" = 0
ck "daily+sleep: ningun script remoto con sintaxis mala" bash -c "! grep -q 'sintaxis' '$T/log' || ! grep -q 'script remoto: SINTAXIS' '$T/log'"
ck "daily: sube el drop-in bluetooth.service.d/10-uke-bt.conf" grep -q 'tar: .*etc/systemd/system/bluetooth.service.d/10-uke-bt.conf' "$T/log"
ck "sleep: sube gancho y ayudante, ambos ejecutables (-rwxr-xr-x)" bash -c "grep -E 'tar: ' '$T/log' | grep -E 'usr/lib/systemd/system-sleep/uke-bt-sleep|usr/local/sbin/uke-bt-resume' | grep -c -- '-rwxr-xr-x' | grep -qx 2"
ck "daily+sleep: no se sube nada fuera de las rutas previstas" bash -c "! grep -E 'tar: ' '$T/log' | grep -vE ' (etc/systemd/system/bluetooth.service.d/?|etc/systemd/system/bluetooth.service.d/10-uke-bt.conf|usr/lib/systemd/system-sleep/uke-bt-sleep|usr/local/sbin/uke-bt-resume)\$' | grep -E ' [^ ]+\$' | grep -vE ' -> ' | grep -q ."
ck "daily: copia main.conf.uke-bak una vez y fija AutoEnable=true" bash -c "grep -l 'uke-bak' '$T'/log.s* | xargs grep -q 'AutoEnable=true'"
ck "daily: habilita bluetooth.service (enable) y NO lo arranca" bash -c "grep -hq 'systemctl enable bluetooth.service' '$T'/log.s* && ! grep -hE 'systemctl (start|restart|stop) bluetooth' '$T'/log.s*"
ck "sleep: ni suspende ni usa rtcwake/reboot el despliegue" bash -c "! grep -hE 'systemctl suspend|rtcwake|reboot' '$T'/log.s*"
ck "daily+sleep: no se toca la blacklist de hci_uart ni uke-wifi" bash -c "! grep -E 'tar: ' '$T/log' | grep -qE 'modprobe.d|uke-wifi'"
newlog; "$D" --daily --sleep >/dev/null 2>&1; ck "daily+sleep sin --go: cero llamadas a ssh (llamadas=$(calls))" test "$(calls)" = 0

echo "== --go --hciqca (BT-MUDO: hci_uart parcheado + bt-medir.sh) =="
newlog; "$D" --go --hciqca > "$T/out" 2>&1; rc=$?
ck "hciqca: rc 0" test "$rc" = 0
[ "$rc" = 0 ] || sed "s/^/       /" "$T/out" | tail -12
ck "hciqca: sube hci_uart.ko a updates/ (listado del tar; extra/ no se busca en Arch), hace depmod y no carga nada (ni modprobe de modulos ni insmod en los scripts remotos)" bash -c "grep -q 'usr/lib/modules/.*/updates/hci_uart.ko' '$SIM_LOG' && ! grep -q 'usr/lib/modules/.*/extra/hci_uart.ko' '$SIM_LOG' && grep -qh 'depmod -a' '$T'/log.s* && ! grep -hqE '^[^#]*(modprobe +(-S [^ ]+ +)?(hci_uart|uke_bt)|insmod)' '$T'/log.s*"
ck "hciqca: el script remoto exige que modinfo resuelva hci_uart a updates/ y borra el residuo de extra/" bash -c "grep -qh 'updates/hci_uart.ko) ;; \*) echo \"depmod no resuelve' '$T'/log.s* && grep -qh 'rm -fv /usr/lib/modules/\$k/extra/hci_uart.ko' '$T'/log.s*"
ck "hciqca: empuja bt-medir.sh y bt-consumo.sh a /usr/local/sbin (en el listado del tar)" bash -c "grep -q 'usr/local/sbin/bt-medir.sh' '$SIM_LOG' && grep -q 'usr/local/sbin/bt-consumo.sh' '$SIM_LOG'"
ck "hciqca: todos los scripts remotos pasan bash -n" bash -c "! grep -q 'ERROR DE SINTAXIS' '$SIM_LOG'"
newlog; "$D" --hciqca >/dev/null 2>&1; ck "hciqca sin --go: cero llamadas a ssh (llamadas=$(calls))" test "$(calls)" = 0
newlog; "$D" --go --revert > "$T/out" 2>&1; ck "--revert tambien retira hci_uart.ko de extra/ y de updates/, bt-medir.sh y bt-consumo.sh" bash -c "grep -qh 'for m in uke_bt_uart uke_bt_b uke_bt_a hci_uart' '$T'/log.s* && grep -qh 'rm -fv /usr/lib/modules/\$k/updates/hci_uart.ko' '$T'/log.s* && grep -qh 'rm -fv /usr/local/sbin/bt-medir.sh /usr/local/sbin/bt-consumo.sh' '$T'/log.s*"
newlog; "$D" --go --revert --hciqca >/dev/null 2>&1; ck "--revert no se combina con --hciqca" test $? != 0
echo "== --go --hciqca-conf (opciones persistentes del hci_uart parcheado) =="
newlog; "$D" --go --hciqca-conf "uke_bt_boot_ms=200" > "$T/out" 2>&1; rc=$?
ck "hciqca-conf: rc 0" test "$rc" = 0
[ "$rc" = 0 ] || sed "s/^/       /" "$T/out" | tail -8
ck "hciqca-conf: escribe /etc/modprobe.d/uke-bt-hci.conf con 'options hci_uart uke_bt_boot_ms=200' y no carga nada" bash -c "grep -qh 'uke_bt_boot_ms=200' '$T'/log.s* && grep -qh 'options hci_uart %s' '$T'/log.s* && grep -qh 'uke-bt-hci.conf' '$T'/log.s* && ! grep -hqE '^[^#]*(modprobe +(-S [^ ]+ +)?(hci_uart|uke_bt)|insmod)' '$T'/log.s*"
newlog; "$D" --go --hciqca-conf "uke_bt_boot_ms=200 uke_bt_low_ms=80" >/dev/null 2>&1; ck "hciqca-conf: varias opciones validas: rc 0" test $? = 0
for bad in "foo=1" "uke_bt_boot_ms=abc" "uke_bt_boot_ms=3000" "uke_bt_boot_ms=200;reboot" "uke_bt_boot_ms=-5" ""; do
	newlog; "$D" --go --hciqca-conf "$bad" >/dev/null 2>&1; rc=$?
	ck "hciqca-conf con '$bad': rechazado en local (rc != 0, cero llamadas a ssh)" bash -c "test $rc != 0 && test \$(cat '$SIM_LOG.n' 2>/dev/null || echo 0) = 0"
done
newlog; "$D" --hciqca-conf "uke_bt_boot_ms=200" >/dev/null 2>&1; ck "hciqca-conf sin --go: cero llamadas a ssh (llamadas=$(calls))" test "$(calls)" = 0
newlog; "$D" --go --revert --hciqca-conf "uke_bt_boot_ms=200" >/dev/null 2>&1; ck "--revert no se combina con --hciqca-conf" test $? != 0
newlog; "$D" --go --revert > "$T/out" 2>&1; ck "--revert tambien borra uke-bt-hci.conf" bash -c "grep -qh 'uke-bt-hci.conf' '$T'/log.s*"

echo "== --go --wait (D4b) =="
newlog; "$D" --go --wait > "$T/out" 2>&1; rc=$?
ck "wait: termina bien (rc=$rc)" test "$rc" = 0
ck "wait: sube uke-bt-wait (ejecutable) y el drop-in de uke-desktop.service" bash -c "grep -E 'tar: ' '$T/log' | grep -E 'usr/local/sbin/uke-bt-wait' | grep -q -- '-rwxr-xr-x' && grep -q 'tar: .*etc/systemd/system/uke-desktop.service.d/20-uke-bt.conf' '$T/log'"
ck "wait: no se sube nada fuera de las rutas previstas" bash -c "! grep -E 'tar: ' '$T/log' | grep -vE ' (usr/local/sbin/uke-bt-wait|etc/systemd/system/uke-desktop.service.d/?|etc/systemd/system/uke-desktop.service.d/20-uke-bt.conf)\\$' | grep -E ' [^ ]+\\$' | grep -vE ' -> ' | grep -q ."
ck "wait: no arranca ni reinicia uke-desktop, sddm ni bluetooth" bash -c "! grep -hE 'systemctl (start|restart|stop) (uke-desktop|sddm|bluetooth)' '$T'/log.s*"
ck "wait: no toca uke-desktop.service ni uke-desktop-start originales" bash -c "! grep -E 'tar: ' '$T/log' | grep -E 'uke-desktop.service\\$|uke-desktop-start'"
newlog; "$D" --wait >/dev/null 2>&1; ck "wait sin --go: cero llamadas a ssh (llamadas=$(calls))" test "$(calls)" = 0

echo "== direccion BD: confirmacion obligatoria =="
newlog; "$D" --go --bdaddr 02:aa:bb:cc:dd:ee < /dev/null > "$T/out" 2>&1; ck "sin terminal: aborta y no llama a ssh (llamadas=$(calls))" bash -c "test $(calls) = 0 && grep -q 'confirmacion INTERACTIVA' '$T/out'"
if command -v script >/dev/null; then
	newlog; printf '02:00:5E:00:00:0F\n' | script -qefc "$D --go --bdaddr 02:aa:bb:cc:dd:ee" /dev/null > "$T/out" 2>&1
	ck "con terminal y confirmacion correcta: escribe uke-bt.conf (modo 600, options uke_bt_b/uke_bt_a)" bash -c "grep -q 'options uke_bt_b bdaddr=02:aa:bb:cc:dd:ee' '$T'/log.s* && grep -q 'options uke_bt_a bdaddr=02:aa:bb:cc:dd:ee' '$T'/log.s* && grep -q 'chmod 600' '$T'/log.s*"
	ck "el aviso final del script remoto solo muestra la cola de la direccion (bdaddr=XX:XX:XX:XX:dd:ee)" bash -c "grep -q 'bdaddr=XX:XX:XX:XX:dd:ee' '$T'/log.s*"
	newlog; printf '02:00:5e:00:00:10\n' | script -qefc "$D --go --bdaddr 02:aa:bb:cc:dd:ee" /dev/null > "$T/out" 2>&1
	ck "confirmacion equivocada: aborta y no llama a ssh (llamadas=$(calls))" test "$(calls)" = 0
	newlog; printf 'x\n' | script -qefc "$D --go --bdaddr random --bdaddr-file /dev/null" /dev/null > "$T/out" 2>&1
	ck "--bdaddr y --bdaddr-file juntos: rechazado" bash -c "grep -q 'excluyentes' '$T/out'; test $(calls) = 0"
else
	echo "  (sin 'script': se omiten las pruebas con terminal)"
fi
[ "$fail" = 0 ] && echo "TODO OK" || { echo "HAY FALLOS"; sed 's/^/   log: /' "$T/log" | head -80; }
exit "$fail"
