#!/bin/bash
# uke-bt-up.sh — enciende el Bluetooth (WCN6750) de la uke: modulo cargador del overlay de DT + hci_uart.
# Lo lanza uke-bt.service (--service) y se puede usar a mano. NO VERIFICADO EN LA TABLET (B0, 18-oct-2026):
# el primer uso real es la etapa B4 del plan (build/gates/revision/BT-SENEMOS-20261018.md), con orden del dueño.
#
#   uke-bt-up.sh [--service]   carga uke_bt_<variante> (aplica el overlay: la UART y el nodo serdev) y luego
#                              `modprobe hci_uart` (el probe del serdev enciende el chip). Espera 'QCA setup on UART is completed'.
#                              exit 0 VERDE | 2 AMARILLO (hci0 existe, no se vio el fin del setup) | 3 ROJO | 1 no se cumple un requisito
#                              REINTENTO POR CICLOS (UKE_BT_CYCLES=N, por defecto 1 = sin reintento; el servicio lo fija a 3): si el driver se rinde
#                              (4 intentos con `0xfc00 tx timeout`), hace --down, pausa UKE_BT_CYCLE_PAUSE s (3) y vuelve a encender, hasta N ciclos.
#                              Motivo (BT-MUDO-20261019.md): ~30 % de los arranques fallan los 4 intentos, pero el chip NO queda bloqueado: el mismo
#                              --down + encendido que fallo a las 17:33 funciono a la 4.a tentativa el 19-oct. Solo se reintenta la rendicion del driver
#                              y `failed to open port`; no los fallos deterministas (modprobe, serdev ausente, firmware, sin hci0 a los 90 s, AMARILLO).
#   uke-bt-up.sh --down        descarga hci_uart y el overlay (orden inverso; BT_EN=0 y rails al soltarlos)
#   uke-bt-up.sh --status      solo lectura (modulos, serdev, hci0, WiFi, ultimas lineas de dmesg)
# El driver (hci_qca.c qca_setup) REINTENTA solo hasta MAX_INIT_RETRIES=3 veces: `command 0x.... tx timeout`, `Reading QCA version information
# failed` y `Retry BT power ON:N` son TRANSITORIOS; solo es ROJO si el driver se rinde (otro error tras `Retry ... :2` y el registro quieto) o a los 90 s.
# UKE_BT_SETTLE=N (s, 0 = sin colchon): espera hasta que uke-wifi lleve N s activo antes de encender el BT (hipotesis, ver informe BT-B0 §9).
# Variante (UKE_BT_VARIANT): b (por defecto, sin rail PA) | a (con rail PA: exige kernel v4) | u (solo UART, no enciende el chip).
# La direccion BD la pone /etc/modprobe.d/uke-bt.conf (`options uke_bt_b bdaddr=...`), generada por deploy.sh --bdaddr.
# Para pruebas en el PC (harness/test-bt-up.sh): UKE_BT_ROOT = prefijo falso de /proc /sys /etc /var /usr, UKE_BT_PATH = PATH con mocks.
set -u
PATH=${UKE_BT_PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin}
ROOT=${UKE_BT_ROOT:-}
LOG=$ROOT/var/log/uke-bt.log
VARIANT=${UKE_BT_VARIANT:-b}
FWSHA=$ROOT/usr/lib/firmware/uke-bt-fw.sha256
CONF=$ROOT/etc/modprobe.d/uke-bt.conf
SERDEV=$ROOT/sys/bus/serial/devices   # el BUS serdev se llama "serial" (serdev/core.c:428): controlador serialN, dispositivo serialN-M
HCI=$ROOT/sys/class/bluetooth
MAX_INIT_RETRIES=3      # hci_qca.c:64; el driver avisa "Retry BT power ON:N" con N = 0..MAX-1 (hci_qca.c:2060-2070) y al fallar el ultimo intento no avisa mas
GIVEUP_IDLE=6           # segundos de registro quieto, tras un error posterior al ultimo "Retry", para dar por rendido al driver
SETTLE=${UKE_BT_SETTLE:-0}
CYCLES=${UKE_BT_CYCLES:-1}           # ciclos completos (cmd_up + --down) antes de dar ROJO; 1 = el comportamiento anterior
CYCLE_PAUSE=${UKE_BT_CYCLE_PAUSE:-3} # s con el chip apagado entre ciclos
HCI_OPTS=${UKE_BT_HCI_OPTS:-}        # opciones extra de `modprobe hci_uart` (p. ej. "uke_bt_boot_ms=150": hciqca/, parametros del hci_uart parcheado); vacio = nada
RETRYABLE=0                          # lo pone cmd_up a 1 cuando el ROJO es una rendicion del driver (la unica causa que merece otro ciclo)
case "$VARIANT" in b|a|u) ;; *) echo "UKE_BT_VARIANT debe ser b, a o u" >&2; exit 1 ;; esac
MOD=uke_bt_$VARIANT; [ "$VARIANT" = u ] && MOD=uke_bt_uart

say() { local m="uke-bt-up: $*"; printf '%s %s\n' "$(date +%H:%M:%S)" "$m"; printf '%s %s\n' "$(date -u +%FT%TZ)" "$m" >> "$LOG" 2>/dev/null; return 0; }
loaded() { grep -q "^$1 " "$ROOT/proc/modules"; }
serdev_devs() { ls "$SERDEV" 2>/dev/null | grep -- '-'; }   # solo dispositivos (serialN-M), no controladores (serialN)
# Colchon tras el WiFi: el BT del primer arranque en frio (18-oct) fallo 2 veces cuando se encendio 0,3 s despues de uke-wifi. Espera lo que falte
# hasta que uke-wifi lleve SETTLE s activo (marca monotonica de systemd; /proc/uptime es BOOTTIME: coinciden hasta la 1a suspension, despues el
# colchon simplemente no espera). Sin uke-wifi activo (omitido/apagado) no espera.
settle() {
	local ts up rem
	[ "$VARIANT" = u ] && return 0
	case "$SETTLE" in ''|0|*[!0-9.]*) return 0 ;; esac
	ts=$(systemctl show uke-wifi.service -p ActiveEnterTimestampMonotonic --value 2>/dev/null)
	case "$ts" in ''|0|*[!0-9]*) return 0 ;; esac
	up=$(cut -d' ' -f1 "$ROOT/proc/uptime")
	rem=$(awk -v n="$SETTLE" -v ts="$ts" -v up="$up" 'BEGIN{r = n - (up - ts / 1e6); if (r > n) r = n; if (r > 0.05) printf "%.2f", r}')
	[ -n "$rem" ] || return 0
	say "colchon: uke-wifi quedo activo hace $(awk -v ts="$ts" -v up="$up" 'BEGIN{printf "%.1f", up - ts / 1e6}') s; espero $rem s (UKE_BT_SETTLE=$SETTLE) antes de encender el BT"
	sleep "$rem"
}
dmesg_bt() { dmesg 2>/dev/null | grep -iE 'uke_bt|Bluetooth|hci0|QCA|wcn6750|geni' | tail -"${1:-25}"; }

cmd_status() {
	echo "kernel $(uname -r)  variante=$VARIANT ($MOD)"
	grep -E '^(uke_bt_[a-z]+|hci_uart|btqca|btbcm|bluetooth) ' "$ROOT/proc/modules" | cut -d' ' -f1-3 | sed 's/^/  mod: /'
	echo "  bus serial (serdev): $(ls "$SERDEV" 2>/dev/null | tr '\n' ' ')  bluetooth: $(ls "$HCI" 2>/dev/null | tr '\n' ' ')"
	[ -f "$CONF" ] && echo "  /etc/modprobe.d/uke-bt.conf presente" || echo "  sin /etc/modprobe.d/uke-bt.conf (el overlay llevaria local-bd-address a ceros)"
	local g=$ROOT/sys/bus/platform/devices/8c0000.qcom,qupv3_1_geni_se/iommu_group   # la UART mainline usa DMA por el SID 0x423 del wrapper
	if [ -e "$g" ]; then echo "  wrapper QUP1: iommu_group $(basename "$(readlink -f "$g")")"; else echo "  wrapper QUP1: SIN iommu_group (el DMA de la UART no tendria dominio: no cargar)"; fi
	command -v wpa_cli >/dev/null && echo "  WiFi: $(wpa_cli -i wlan0 status 2>/dev/null | grep -E '^wpa_state=' || echo '(sin wpa_cli/wlan0)')"
	echo "  ultimas lineas de dmesg:"; dmesg_bt 15 | sed 's/^/    /'
	return 0
}

cmd_down() {
	[ "$(id -u)" = 0 ] || { echo "hace falta root" >&2; return 1; }
	sync
	if loaded hci_uart; then modprobe -r hci_uart && say "hci_uart descargado" || { say "ROJO: no pude descargar hci_uart"; return 3; }; fi
	local m
	for m in uke_bt_b uke_bt_a uke_bt_uart; do
		if loaded "$m"; then modprobe -r "$m" && say "$m descargado (overlay retirado)" || { say "ROJO: no pude descargar $m"; return 3; }; fi
	done
	sync
	return 0
}

cmd_up() {
	[ "$(id -u)" = 0 ] || { echo "hace falta root" >&2; return 1; }
	case "$(uname -r)" in *senemos*) ;; *) say "kernel $(uname -r) no es senemos: no hago nada"; return 1 ;; esac
	[ "$VARIANT" = a ] && say "AVISO: variante A (rail PA) sin kernel v4 se queda diferida (fw_devlink.strict=1)"
	[ "$VARIANT" = u ] || (cd "${ROOT:-/}" && sha256sum -c --quiet "usr/lib/firmware/uke-bt-fw.sha256") >/dev/null 2>&1 || { say "los ficheros de firmware no casan con $FWSHA (¿deploy.sh --fw?)"; return 1; }
	modinfo -n "$MOD" >/dev/null 2>&1 || { say "no encuentro el modulo $MOD (¿deploy.sh --module? ¿depmod?)"; return 1; }
	[ -e "$HCI/hci0" ] && { say "hci0 ya existe: nada que hacer"; return 0; }
	for m in uke_bt_b uke_bt_a uke_bt_uart; do
		loaded "$m" && { say "ya esta cargado $m (descarga primero con --down): no mezclo variantes"; return 1; }
	done
	[ "$VARIANT" = u ] || [ -f "$CONF" ] || say "AVISO: sin /etc/modprobe.d/uke-bt.conf: local-bd-address a ceros, el controlador quedara sin configurar"
	say "variante $VARIANT, kernel $(uname -r); WiFi: $(wpa_cli -i wlan0 status 2>/dev/null | grep -E '^wpa_state=' || echo n/d)"
	settle
	sync
	modprobe "$MOD" || { say "ROJO: modprobe $MOD fallo (dmesg: $(dmesg_bt 3 | tr '\n' '|'))"; return 3; }
	say "$MOD cargado (overlay aplicado)"
	[ "$VARIANT" = u ] && { say "VERDE: solo la UART (sin chip)"; return 0; }
	local i mark new
	for i in $(seq 1 25); do [ -n "$(serdev_devs)" ] && break; sleep 0.2; done
	if [ -z "$(serdev_devs)" ]; then
		say "ROJO: el overlay no creo ningun dispositivo serdev en $SERDEV (solo: $(ls "$SERDEV" 2>/dev/null | tr '\n' ' ')); no cargo hci_uart. Descarga con --down. dmesg: $(dmesg_bt 4 | tr '\n' '|')"
		return 3
	fi
	say "serdev: $(serdev_devs | tr '\n' ' ')"
	mark=$(dmesg 2>/dev/null | wc -l)
	# shellcheck disable=SC2086
	modprobe hci_uart $HCI_OPTS || { say "ROJO: modprobe hci_uart fallo (dmesg: $(dmesg_bt 3 | tr '\n' '|'))"; return 3; }
	say "hci_uart cargado${HCI_OPTS:+ (opciones: $HCI_OPTS)}; espero el setup del chip (hasta 90 s; el driver reintenta solo hasta $MAX_INIT_RETRIES veces)"
	# solo cuentan las lineas NUEVAS de dmesg (no las de un intento anterior del mismo arranque)
	local retries err_after idle=0 nl prev_nl=-1 last=$((MAX_INIT_RETRIES - 1))
	for i in $(seq 1 90); do
		new=$(dmesg 2>/dev/null | tail -n +$((mark + 1)))
		retries=$(grep -c 'Retry BT power ON:' <<<"$new")
		if grep -q 'QCA setup on UART is completed' <<<"$new"; then
			say "VERDE$([ "$retries" -gt 0 ] && echo " (tras $retries reintento(s) del driver)"): $(grep -E 'QCA controller version|QCA setup on UART' <<<"$new" | tail -2 | tr '\n' '|')"; return 0
		fi
		if grep -q 'failed to open port' <<<"$new"; then
			say "ROJO: el driver no pudo reabrir el puerto serie en un reintento: $(tail -6 <<<"$new" | tr '\n' '|')"; RETRYABLE=1; return 3
		fi
		# error DESPUES del ultimo "Retry BT power ON:MAX-1" = el ultimo intento tambien fallo; si ademas el registro queda quieto, se rindio
		err_after=0
		if grep -q "Retry BT power ON:$last" <<<"$new"; then
			sed -n "/Retry BT power ON:$last/,\$p" <<<"$new" | tail -n +2 | grep -qE 'tx timeout|failed|Failed' && err_after=1
		fi
		nl=$(wc -l <<<"$new")
		if [ "$nl" = "$prev_nl" ]; then idle=$((idle + 1)); else idle=0; fi
		prev_nl=$nl
		if [ "$err_after" = 1 ] && [ "$idle" -ge "$GIVEUP_IDLE" ]; then
			say "ROJO: el driver se rindio tras $retries reintentos y el ultimo intento tambien fallo: $(tail -8 <<<"$new" | tr '\n' '|')"; RETRYABLE=1; return 3
		fi
		sleep 1
	done
	if [ -e "$HCI/hci0" ]; then say "AMARILLO: hci0 existe pero no vi el fin del setup en 90 s ($retries reintento(s) del driver)"; return 2; fi
	say "ROJO: sin hci0 tras 90 s ($retries reintento(s) del driver): $(dmesg_bt 8 | tr '\n' '|')"; return 3
}

# cmd_up con reintento por ciclos completos (ver la cabecera). Con CYCLES=1 equivale a cmd_up.
cmd_service() {
	local n=$CYCLES i rc
	case "$n" in ''|*[!0-9]*|0) n=1 ;; esac
	for i in $(seq 1 "$n"); do
		RETRYABLE=0
		cmd_up; rc=$?
		if [ "$rc" = 0 ] || [ "$rc" = 2 ]; then
			[ "$i" -gt 1 ] && say "ciclo $i/$n: resultado final rc=$rc tras $((i - 1)) ciclo(s) fallido(s)"
			return "$rc"
		fi
		if [ "$rc" != 3 ] || [ "$RETRYABLE" != 1 ]; then return "$rc"; fi
		if [ "$i" -ge "$n" ]; then [ "$n" -gt 1 ] && say "ROJO definitivo: agotados los $n ciclo(s) de encendido"; return 3; fi
		say "ciclo $i/$n: el chip no respondio; --down, pausa de $CYCLE_PAUSE s y nuevo ciclo"
		cmd_down || { say "ROJO: no pude descargar los modulos para reintentar (ciclo $i/$n)"; return 3; }
		sleep "$CYCLE_PAUSE"
	done
}

case "${1:---service}" in
	--service|--up) cmd_service; exit $? ;;
	--down) cmd_down; exit $? ;;
	--status) cmd_status; exit 0 ;;
	-h|--help) awk 'NR>1 && /^set -u/{exit} NR>1' "$0"; exit 0 ;;
	*) echo "uso: $0 [--service|--down|--status]" >&2; exit 1 ;;
esac
