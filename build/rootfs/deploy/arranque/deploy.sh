#!/usr/bin/env bash
# deploy.sh — WiFi y escritorio Omarchy AL ARRANQUE en el rootfs Arch de la Xiaomi Pad 7 'uke' (kernel senemos v3),
# con interruptores de seguridad y guarda anti-bucle. Por SSH, con `tar | ssh` (sin scp/sftp).
#
# Contexto: el cmdline del boot.img trae systemd.unit=multi-user.target (no se puede cambiar sin reflashear), asi que
# graphical.target nunca se alcanza y sddm no arranca solo. Aqui:
#   uke-wifi.service     WiFi (WCN6750) como servicio normal, tras uke-carga.service     (arbol de wifi/root)
#   uke-desktop.service  lanza sddm (autologin) tras uke-carga y uke-wifi                (arbol de arranque/root)
#   uke-bootguard        guarda: interruptores /etc/uke/no-wifi|no-desktop|safe-mode + dead-man de 2 arranques
# Detalle y plan de verificacion: build/gates/revision/ARRANQUE-WIFI-ESCRITORIO-20261018.md
#
# Uso:  deploy.sh [check|status|verify|apply|revert|safe-mode on|off] [--go] [--no-tz] [--no-wifi] [--no-desktop] [--host H] [--key K]
#   check        (por defecto) PC, sin red: manifiesto, sintaxis, prueba de la maquina de estados de uke-bootguard
#   status       lectura por SSH: unidades, interruptores, guarda, zona horaria, chrony, sddm
#   verify       lectura por SSH: lista de comprobaciones PASA/FALLA del arranque (para correr tras reiniciar) + linea de tiempos
#   apply        DRY-RUN salvo --go: instala root/ (+ unidad y guion del WiFi de wifi/root), crea /etc/uke y
#                /var/lib/uke/guard, daemon-reload, `systemctl enable` de las unidades, zona horaria Europe/Madrid.
#                NO arranca ni reinicia nada (el efecto es en el PROXIMO arranque). --no-tz salta la zona horaria;
#                --no-wifi / --no-desktop no habilitan esa unidad.
#   revert       DRY-RUN salvo --go: `systemctl disable` de las dos unidades + uke-bootguard reset all (los ficheros se quedan)
#   safe-mode    on|off (--go): crea/borra /etc/uke/safe-mode (ni WiFi ni escritorio en el proximo arranque)
# NUNCA toca usb0, 10-uke-usb.network, sddm/Hyprland en marcha, modulos del kernel ni /etc/modprobe.d.
set -Eeuo pipefail
trap 'echo "deploy.sh: ERROR en linea $LINENO (ultimo comando: $BASH_COMMAND)" >&2' ERR

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
R=$(cd "$HERE/../../../.." && pwd)
TREE=$HERE/root
WIFITREE=$R/build/rootfs/deploy/wifi/root
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}
HOST=${UKE_HOST:-192.168.42.129}
GO=0 TZ_SET=1 EN_WIFI=1 EN_DESKTOP=1
TZNAME=${UKE_TZ:-Europe/Madrid}
WIFI_FILES="etc/systemd/system/uke-wifi.service usr/local/sbin/uke-wifi-up.sh"
args=()
while [ $# -gt 0 ]; do
	case "$1" in
	--go) GO=1 ;;
	--no-tz) TZ_SET=0 ;;
	--no-wifi) EN_WIFI=0 ;;
	--no-desktop) EN_DESKTOP=0 ;;
	--host) HOST=${2:?--host H}; shift ;;
	--key) KEY=${2:?--key K}; shift ;;
	-h|--help) awk 'NR>1 && /^set -Eeuo/{exit} NR>1' "${BASH_SOURCE[0]}"; exit 0 ;;
	*) args+=("$1") ;;
	esac
	shift
done
CMD=${args[0]:-check}
ARG1=${args[1]:-}
SSH_BASE=(ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
S() { "${SSH_BASE[@]}" "root@$HOST" "$@"; }
say() { printf '[deploy-arranque %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { echo "ABORTA: $*" >&2; exit 2; }
mut() { [ "$GO" = 1 ] && return 0; say "DRY-RUN: $* (anade --go)"; return 1; }

cmd_check() {
	say "== check local (sin red) =="
	[ -d "$TREE" ] || die "falta $TREE"
	(cd "$TREE" && sha256sum -c --quiet "$HERE/MANIFEST.sha256") && say "  MANIFEST.sha256 OK" || die "el arbol no casa con MANIFEST.sha256 (¿editado? deploy.sh regen-manifest)"
	local f
	for f in usr/local/sbin/uke-bootguard usr/local/sbin/uke-desktop-start; do
		bash -n "$TREE/$f" && say "  bash -n $f OK"
		[ -x "$TREE/$f" ] || die "$f no es ejecutable"
	done
	bash -n "${BASH_SOURCE[0]}" && bash -n "$HERE/test-bootguard.sh" && say "  bash -n deploy.sh/test-bootguard.sh OK"
	bash -n "$WIFITREE/usr/local/sbin/uke-wifi-up.sh" && say "  bash -n uke-wifi-up.sh OK"
	(cd "$R/build/rootfs/deploy/wifi" && cd root && sha256sum -c --quiet ../MANIFEST.sha256) && say "  wifi/MANIFEST.sha256 OK"
	if [ -n "${UKE_PC_VERIFY:-}" ] && command -v systemd-analyze >/dev/null; then
		timeout 20 systemd-analyze verify --man=no "$TREE/etc/systemd/system/uke-desktop.service" "$WIFITREE/etc/systemd/system/uke-wifi.service" 2>&1 \
			| grep -vE "Command .* is not executable|Failed to prepare|does not exist|Cannot find" | sed 's/^/  verify: /' || true
		say "  (systemd-analyze verify del PC: solo sintaxis; los ejecutables no existen en el PC)"
	fi
	"$HERE/test-bootguard.sh" | tail -n 4
	say "CHECK OK"
}

cmd_regen() {
	(cd "$TREE" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$HERE/MANIFEST.sha256"
	say "MANIFEST.sha256 regenerado ($(wc -l < "$HERE/MANIFEST.sha256") ficheros)"
}

need_ssh() { [ -f "$KEY" ] || die "falta la clave $KEY"; S 'echo "ssh OK: $(uname -r) up $(cut -d" " -f1 /proc/uptime)s"' || die "sin SSH a root@$HOST"; }

cmd_status() {
	need_ssh
	S 'bash -s' <<'REMOTE'
echo "== unidades"
for u in uke-carga uke-wifi uke-desktop sddm wpa_supplicant-nl80211@wlan0 chronyd; do
	printf '  %-34s enabled=%-9s active=%s\n' "$u" "$(systemctl is-enabled $u.service 2>&1 | head -1)" "$(systemctl is-active $u.service 2>&1 | head -1)"
done
echo "== interruptores (/etc/uke)"; ls -l /etc/uke 2>&1 | sed 's/^/  /'
echo "== guarda"; /usr/local/sbin/uke-bootguard status 2>&1 | sed 's/^/  /'
echo "== decisiones de la guarda en este arranque"; journalctl -b -t uke-bootguard --no-pager -o cat 2>/dev/null | tail -n 12 | sed 's/^/  /'
echo "== zona horaria / hora"; timedatectl 2>&1 | sed 's/^/  /'
echo "== chrony"; chronyc tracking 2>&1 | head -4 | sed 's/^/  /'
echo "== red"; ip -br a | sed 's/^/  /'; ip route | sed 's/^/  /'
REMOTE
}

cmd_verify() {
	need_ssh
	S 'bash -s' <<'REMOTE'
pass=0 bad=0
g() { if [ "$2" = 1 ]; then printf '  PASA   %s\n' "$1"; pass=$((pass+1)); else printf '  FALLA  %s\n' "$1"; bad=$((bad+1)); fi; }
up=$(cut -d. -f1 /proc/uptime)
echo "kernel $(uname -r) | uptime ${up}s | $(date '+%F %T %Z')"
echo "== unidades"
[ "$(systemctl is-enabled uke-wifi.service 2>&1)" = enabled ] && g "uke-wifi.service enabled" 1 || g "uke-wifi.service enabled" 0
[ "$(systemctl is-enabled uke-desktop.service 2>&1)" = enabled ] && g "uke-desktop.service enabled" 1 || g "uke-desktop.service enabled" 0
[ -e /etc/uke/safe-mode ] || [ -e /etc/uke/no-wifi ] || [ -e /etc/uke/no-desktop ] && { echo "  AVISO  hay interruptores en /etc/uke: $(ls /etc/uke | grep -v LEEME | tr '\n' ' ')"; }
systemctl is-active -q uke-carga.service && g "uke-carga activo (ADSP/carga)" 1 || g "uke-carga activo" 0
systemctl is-active -q uke-wifi.service && g "uke-wifi activo (exited = hecho)" 1 || g "uke-wifi activo" 0
systemctl is-active -q uke-desktop.service && g "uke-desktop activo (exited = hecho)" 1 || g "uke-desktop activo" 0
systemctl is-active -q sddm.service && g "sddm activo" 1 || g "sddm activo" 0
pgrep -x Hyprland >/dev/null && g "Hyprland vivo" 1 || g "Hyprland vivo" 0
pgrep -x quickshell >/dev/null && g "quickshell vivo" 1 || g "quickshell vivo" 0
echo "== guarda (uke-bootguard)"
journalctl -b -t uke-bootguard --no-pager -o cat 2>/dev/null | grep -E "^uke-bootguard: (wifi|desktop)" | sed 's/^/  /'
journalctl -b -t uke-bootguard --no-pager -o cat 2>/dev/null | grep -qE "DISPARADA|omitido" && g "la guarda NO omitio nada" 0 || g "la guarda NO omitio nada" 1
if [ "$up" -ge 200 ]; then
	[ -e /var/lib/uke/guard/wifi.pending ] || [ -e /var/lib/uke/guard/desktop.pending ] && g "pending limpiado tras 180 s (ok)" 0 || g "pending limpiado tras 180 s (ok)" 1
else echo "  (uptime ${up}s < 200: el 'ok' de 180 s aun no ha saltado; repite luego)"; fi
echo "== WiFi"
IP=$(ip -4 -br a show wlan0 2>/dev/null | awk '{print $3}')
[ -n "$IP" ] && g "wlan0 con IPv4 ($IP)" 1 || g "wlan0 con IPv4" 0
[ "$(cat /sys/class/net/wlan0/address 2>/dev/null)" != 00:00:00:00:00:00 ] && g "MAC de wlan0 distinta de ceros ($(cat /sys/class/net/wlan0/address 2>/dev/null))" 1 || g "MAC de wlan0" 0
wpa_cli -i wlan0 status 2>/dev/null | grep -q '^wpa_state=COMPLETED' && g "wpa_state=COMPLETED" 1 || g "wpa_state=COMPLETED" 0
ip route | grep -q '^default via .* dev wlan0' && g "ruta por defecto por wlan0" 1 || g "ruta por defecto por wlan0" 0
ping -c2 -W3 1.1.1.1 >/dev/null 2>&1 && g "ping 1.1.1.1" 1 || g "ping 1.1.1.1" 0
ip -4 -br a show usb0 2>/dev/null | grep -q '192.168.42.129' && g "usb0 intacto (192.168.42.129)" 1 || g "usb0 intacto" 0
echo "== hora"
[ "$(timedatectl show -p Timezone --value)" = Europe/Madrid ] && g "zona horaria Europe/Madrid" 1 || g "zona horaria Europe/Madrid" 0
[ "$(timedatectl show -p NTPSynchronized --value)" = yes ] && g "reloj sincronizado (chrony)" 1 || g "reloj sincronizado (chrony; con WiFi recien arriba puede tardar ~1 min)" 0
echo "== GPU"
n=$(dmesg | grep -c 'Loaded GMU firmware')
[ "$n" -ge 1 ] && g "GMU cargado ($n vez; dmesg: $(dmesg | grep 'Loaded GMU firmware' | head -1 | cut -c1-14))" 1 || g "GMU cargado (la GPU no se uso)" 0
holders=$(for p in /proc/[0-9]*; do ls -l $p/fd 2>/dev/null | grep -qE '/dev/dri/(card0|renderD128)' && printf '%s(%s) ' "$(cat $p/comm)" "${p#/proc/}"; done)
echo "  procesos con la GPU abierta: ${holders:-ninguno}"
echo "== errores del kernel (sin lineas = bien)"
bad_k=$(dmesg | grep -aE 'ath11k.*([Ff]ail|[Ee]rror|[Tt]imeout)|Internal error: Oops|\bBUG:|blocked for more than|GMU.*([Tt]imeout|[Ff]ail)|(smmu|iommu).*\bfault\b|Unhandled (context )?fault|underrun: *[1-9]' | grep -vE 'Country regulatory setting|failed to process regulatory info|modprobe ath11k_ahb rc=0' | head -8)
[ "$(dmesg | grep -c 'regulatory')" -gt 0 ] && echo "  INFO   ath11k: $(dmesg | grep -c regulatory) avisos de 'regulatory' (-22 al fijar el pais; ya salen en build/logs anteriores, sin diagnosticar; el WiFi funciona)"
[ -z "$bad_k" ] && g "dmesg sin errores de ath11k/GMU/SMMU/Oops" 1 || { g "dmesg sin errores de ath11k/GMU/SMMU/Oops" 0; echo "$bad_k" | cut -c1-200 | sed 's/^/    /'; }
echo "== linea de tiempos (s desde el arranque)"
journalctl -b -o short-monotonic --no-pager 2>/dev/null | grep -v audit | grep -E "Finished uke: pila de carga|Starting uke: WiFi|Finished uke: WiFi|Starting uke: arrancar el escritorio|Starting Simple Desktop|Started Simple Desktop|VERDE: asociado|Loaded GMU firmware|Reached target Multi-User" | sed -E 's/^\[ *([0-9.]+)\] [^ ]+ /  \1  /' | cut -c1-150
echo
echo "RESULTADO: $pass pasan, $bad fallan"
[ "$bad" = 0 ]
REMOTE
}

cmd_apply() {
	[ -d "$TREE" ] || die "falta $TREE"
	cmd_check >/dev/null || die "check local fallo (deploy.sh check)"
	say "== plan =="
	cat <<EOF
  1. preflight remoto (root, systemd-run, chronyc, firmware WiFi OK, / en rw)
  2. tar|ssh de arranque/root (uke-bootguard, uke-desktop-start, uke-desktop.service, /etc/uke/LEEME)
     + del arbol del WiFi: uke-wifi.service y uke-wifi-up.sh (nueva unidad normal con guarda; MAC defensiva)
  3. mkdir /var/lib/uke/guard y /etc/uke; chmod; systemctl daemon-reload; systemd-analyze verify en la tablet
  4. systemctl enable: $( [ "$EN_WIFI" = 1 ] && echo -n 'uke-wifi.service ' )$( [ "$EN_DESKTOP" = 1 ] && echo -n 'uke-desktop.service' )   (sin arrancar nada)
  5. zona horaria: $( [ "$TZ_SET" = 1 ] && echo "timedatectl set-timezone $TZNAME" || echo "(saltada --no-tz)" )
  6. sync. Efecto: PROXIMO arranque. Interruptores: touch /etc/uke/no-wifi | no-desktop | safe-mode
EOF
	mut "aplicar el plan en root@$HOST" || return 0
	need_ssh
	S 'bash -s' <<'REMOTE'
set -e
[ "$(id -u)" = 0 ] || { echo "no soy root" >&2; exit 1; }
for b in systemctl systemd-run chronyc udevadm sync sha256sum timedatectl; do command -v $b >/dev/null || { echo "FALTA en la tablet: $b" >&2; exit 1; }; done
mount | grep -E ' / ' | grep -q '[( ,]ro[, )]' && { echo "/ en SOLO LECTURA: aborto" >&2; exit 1; }
(cd / && sha256sum -c --quiet usr/lib/firmware/uke-wifi-fw.sha256) || { echo "firmware WiFi no casa: aplica antes wifi/deploy.sh --go" >&2; exit 1; }
echo "preflight OK (kernel $(uname -r))"
REMOTE
	say "== instalar ficheros =="
	# dos arboles: se envian por separado para conservar las rutas relativas
	(cd "$TREE" && find . -type f -print0) | tar -C "$TREE" --no-recursion --null --owner=0 --group=0 --numeric-owner -cf - -T - | S 'tar -xpf - --no-overwrite-dir -C /'
	(cd "$WIFITREE" && for f in $WIFI_FILES; do printf '%s\0' "$f"; done) | tar -C "$WIFITREE" --no-recursion --null --owner=0 --group=0 --numeric-owner -cf - -T - | S 'tar -xpf - --no-overwrite-dir -C /'
	say "== post-instalacion remota =="
	S "bash -s -- $EN_WIFI $EN_DESKTOP $TZ_SET $TZNAME" <<'REMOTE'
set -eu
EN_WIFI=$1 EN_DESKTOP=$2 TZ_SET=$3 TZNAME=$4
chmod 0755 /usr/local/sbin/uke-bootguard /usr/local/sbin/uke-desktop-start /usr/local/sbin/uke-wifi-up.sh
chmod 0644 /etc/systemd/system/uke-desktop.service /etc/systemd/system/uke-wifi.service /etc/uke/LEEME
mkdir -p /var/lib/uke/guard /etc/uke
systemctl daemon-reload
systemd-analyze verify --man=no /etc/systemd/system/uke-wifi.service /etc/systemd/system/uke-desktop.service 2>&1 | sed 's/^/  verify: /' || true
rm -f /var/lib/uke-wifi/armed
/usr/local/sbin/uke-bootguard reset all >/dev/null
[ "$EN_WIFI" = 1 ] && systemctl enable uke-wifi.service
[ "$EN_DESKTOP" = 1 ] && systemctl enable uke-desktop.service
if [ "$TZ_SET" = 1 ]; then
	[ -f "/usr/share/zoneinfo/$TZNAME" ] || { echo "no existe /usr/share/zoneinfo/$TZNAME (tzdata)" >&2; exit 1; }
	timedatectl set-timezone "$TZNAME"
fi
sync
echo "== estado final"
for u in uke-wifi uke-desktop; do printf '  %-14s enabled=%s\n' "$u" "$(systemctl is-enabled $u.service 2>&1 | head -1)"; done
timedatectl | grep -E 'Local time|Time zone'
REMOTE
	say "hecho (no se ha arrancado nada: el efecto es en el proximo arranque). Verificacion: deploy.sh status"
}

cmd_revert() {
	mut "deshabilitar uke-wifi.service y uke-desktop.service, uke-bootguard reset all" || return 0
	need_ssh
	S 'systemctl disable uke-wifi.service uke-desktop.service 2>&1; /usr/local/sbin/uke-bootguard reset all; sync; echo "(ficheros y /etc/uke se quedan; borrar a mano si se quiere)"'
}

cmd_safe() {
	[ "$ARG1" = on ] || [ "$ARG1" = off ] || die "uso: safe-mode on|off"
	mut "safe-mode $ARG1" || return 0
	need_ssh
	if [ "$ARG1" = on ]; then S 'mkdir -p /etc/uke && touch /etc/uke/safe-mode && sync && echo "safe-mode ON: el proximo arranque sin WiFi ni escritorio"'
	else S 'rm -f /etc/uke/safe-mode && sync && echo "safe-mode OFF"'; fi
}

case $CMD in
	check) cmd_check ;;
	regen-manifest) cmd_regen ;;
	status) cmd_status ;;
	verify) cmd_verify || exit $? ;;
	apply) cmd_apply ;;
	revert) cmd_revert ;;
	safe-mode) cmd_safe ;;
	*) die "subcomando desconocido: $CMD (deploy.sh --help)" ;;
esac
