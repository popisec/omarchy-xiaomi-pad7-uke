#!/usr/bin/env bash
# deploy.sh — despliega el WiFi (WCN6750 / ath11k_ahb) en el rootfs Arch de la Xiaomi Pad 7 'uke'
# por SSH, con `tar | ssh` (el rootfs NO tiene sftp-server: nada de scp/rsync-sftp).
#
# SIN --go: SOLO verifica el arbol local (shas, sintaxis) e imprime el plan. No abre ninguna conexion.
# CON --go: ejecuta el plan en la tablet. Necesita SSH vivo (gadget USB 192.168.42.129 por defecto).
#
# QUE INSTALA (todo bajo root/, copiado a / de la tablet con propietario 0:0):
#   /usr/lib/firmware/ath11k/WCN6750/hw1.0/{board.bin,regdb.bin}   board.bin = bd_o82gl.elf (BDF ELF)
#   /usr/lib/firmware/qca6750/wpss.{mdt,b00..b10,b12}              set vendor VIVO (sustituye el b08
#                                                                  CORRUPTO que lleva la imagen 8 GiB)
#   /usr/lib/firmware/uke-wifi-fw.sha256                           manifiesto que exige el guion
#   /usr/local/sbin/uke-wifi-up.sh                                 carga ordenada + diagnostico
#   /etc/systemd/system/uke-wifi.service                           servicio NORMAL (WantedBy=multi-user.target; se
#                                                                  habilita con --arm). Protegido por /etc/uke/no-wifi,
#                                                                  /etc/uke/safe-mode y uke-bootguard (build/rootfs/deploy/arranque)
#   /etc/systemd/network/{10-uke-wlan.link,20-uke-wlan.network}    wlan0 fijo + DHCP (networkd)
#   /etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf          (ver credenciales abajo)
# Ademas, EN LA TABLET: aparta board-2.bin de linux-firmware (api-2 ganaria a board.bin), crea
# /var/lib/uke-wifi, recarga systemd/udev/networkd y hace sync. NO toca la blacklist de ath11k.
#
# OPCIONES
#   --go               ejecuta (sin esto, plan + verificacion local)
#   --check            solo lectura en la tablet (kernel, modulos, shas del firmware, board-2.bin)
#   --modules          ademas instala (cierre de dependencias de) ath11k_ahb/qcom_q6v5_pas/qrtr_smd/
#                      cfg80211/mac80211 desde UKE_MODROOT y corre `depmod -a <krel>` en la tablet.
#                      Comprueba vermagic == nombre del directorio. Requiere el kernel v2 construido.
#   --arm              `systemctl enable uke-wifi.service` + `uke-bootguard reset wifi`: el WiFi arranca solo en cada
#                      arranque (tras uke-carga). REQUIERE build/rootfs/deploy/arranque/deploy.sh --go ya aplicado
#                      (uke-bootguard + /etc/uke). Interruptores sin reflashear: touch /etc/uke/no-wifi (o safe-mode);
#                      la guarda lo omite sola tras 2 arranques seguidos sin 'ok' (cuelgue). Ver /etc/uke/LEEME.
#                      Sin --arm el primer test es a mano:  ssh ... /usr/local/sbin/uke-wifi-up.sh
#   --host H --key K   por defecto 192.168.42.129 y build/rootfs/uke-arch-root
#   --modroot DIR      por defecto build/kernel-pokes/senemos-build/modroot (SOLO SE LEE)
#   --regen-manifest   regenera MANIFEST.sha256 de root/ (tras editar el arbol) y sale
#
# CREDENCIALES WiFi (nunca se guardan en el repo): variables de entorno al ejecutar.
#   WIFI_SSID='mi-red' WIFI_PSK='clave' [WIFI_COUNTRY=ES] ./deploy.sh --go
# La PSK se pasa por stdin a wpa_passphrase (en el PC) y a la tablet solo viaja el hash PBKDF2 (psk=hex)
# en un fichero modo 600. Sin credenciales: si no hay conf en la tablet se crea una SOLO-ESCANEO
# (country + ctrl_interface); si ya hay una, no se toca.
# Otras variables: UKE_HOST UKE_USER UKE_KEY UKE_MODROOT UKE_SSH_OPTS (opciones ssh extra).
set -Eeuo pipefail
trap 'echo "deploy.sh: ERROR en linea $LINENO (ultimo comando: $BASH_COMMAND)" >&2' ERR

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
R=$(cd "$HERE/../../../.." && pwd)
TREE=$HERE/root
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}
HOST=${UKE_HOST:-192.168.42.129}
SSHUSER=${UKE_USER:-root}
MODROOT=${UKE_MODROOT:-$R/build/kernel-pokes/senemos-build/modroot}
WIFI_COUNTRY=${WIFI_COUNTRY:-ES}
GO=0 CHECK=0 ARM=0 MODULES=0 REGEN=0
MODS_WANT="ath11k_ahb ath11k qcom_q6v5_pas qrtr_smd qrtr cfg80211 mac80211"

while [ $# -gt 0 ]; do
	case "$1" in
	--go) GO=1 ;;
	--check) CHECK=1 ;;
	--arm) ARM=1 ;;
	--modules) MODULES=1 ;;
	--regen-manifest) REGEN=1 ;;
	--host) HOST=${2:?--host H}; shift ;;
	--key) KEY=${2:?--key K}; shift ;;
	--modroot) MODROOT=${2:?--modroot DIR}; shift ;;
	-h|--help) awk 'NR>1 && /^set -Eeuo/{exit} NR>1' "${BASH_SOURCE[0]}"; exit 0 ;;
	*) echo "argumento no reconocido: $1 (usa --help)" >&2; exit 2 ;;
	esac
	shift
done

# shellcheck disable=SC2206
SSH_BASE=(ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 ${UKE_SSH_OPTS:-})
S() { "${SSH_BASE[@]}" "$SSHUSER@$HOST" "$@"; }
say() { printf '[deploy-wifi %s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# ------------------------------------------------------------------ regenerar manifiesto local
if [ "$REGEN" = 1 ]; then
	(cd "$TREE" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$HERE/MANIFEST.sha256"
	say "MANIFEST.sha256 regenerado ($(wc -l < "$HERE/MANIFEST.sha256") ficheros)"
	exit 0
fi

# ------------------------------------------------------------------ verificacion LOCAL (siempre)
say "== verificacion local del arbol =="
[ -d "$TREE" ] || { echo "falta $TREE" >&2; exit 2; }
if [ -f "$HERE/MANIFEST.sha256" ]; then
	(cd "$TREE" && sha256sum -c --quiet "$HERE/MANIFEST.sha256") || { echo "el arbol no casa con MANIFEST.sha256 (¿lo editaste? --regen-manifest)" >&2; exit 2; }
	say "  MANIFEST.sha256 OK"
else
	say "  AVISO: sin MANIFEST.sha256 (ejecuta --regen-manifest)"
fi
(cd "$TREE" && sha256sum -c --quiet usr/lib/firmware/uke-wifi-fw.sha256) || { echo "firmware != uke-wifi-fw.sha256" >&2; exit 2; }
say "  uke-wifi-fw.sha256 OK (15 ficheros de firmware)"
[ "$(head -c4 "$TREE/usr/lib/firmware/ath11k/WCN6750/hw1.0/board.bin" | od -An -tx1 | tr -d ' \n')" = 7f454c46 ] \
	|| { echo "board.bin no es un ELF (debe ser bd_o82gl.elf completo)" >&2; exit 2; }
say "  board.bin = ELF (BDF_TYPE_ELF, sin caldata)"
[ ! -e "$TREE/usr/lib/firmware/ath11k/WCN6750/hw1.0/board-2.bin" ] || { echo "el arbol NO debe llevar board-2.bin" >&2; exit 2; }
bash -n "$TREE/usr/local/sbin/uke-wifi-up.sh" && say "  sintaxis uke-wifi-up.sh OK"
bash -n "${BASH_SOURCE[0]}" && bash -n "$HERE/modclosure.sh" && say "  sintaxis deploy.sh/modclosure.sh OK"
[ -f "$KEY" ] || say "  AVISO: no existe la clave SSH $KEY"
say "  $(find "$TREE" -type f | wc -l) ficheros, $(du -sh "$TREE" | cut -f1) en root/"

# ------------------------------------------------------------------ credenciales -> conf wpa_supplicant (en memoria)
HAVE_CREDS=0
if [ -n "${WIFI_SSID:-}" ] || [ -n "${WIFI_PSK:-}" ]; then
	[ -n "${WIFI_SSID:-}" ] && [ -n "${WIFI_PSK:-}" ] || { echo "WIFI_SSID y WIFI_PSK van juntas" >&2; exit 2; }
	[ "${#WIFI_PSK}" -ge 8 ] && [ "${#WIFI_PSK}" -le 63 ] || { echo "WPA-PSK: la clave debe tener 8-63 caracteres" >&2; exit 2; }
	command -v wpa_passphrase >/dev/null || { echo "falta wpa_passphrase en el PC" >&2; exit 2; }
	HAVE_CREDS=1
fi
gen_wpa_conf() {
	printf 'ctrl_interface=/run/wpa_supplicant\nctrl_interface_group=0\nupdate_config=1\ncountry=%s\n' "$WIFI_COUNTRY"
	if [ "$HAVE_CREDS" = 1 ]; then
		printf '%s\n' "$WIFI_PSK" | wpa_passphrase "$WIFI_SSID" 2>/dev/null | grep -v '^[[:space:]]*#psk='
	fi
}

# ------------------------------------------------------------------ modulos (opcional, solo lectura del modroot)
KREL="" MODLIST=""
if [ "$MODULES" = 1 ]; then
	say "== modulos desde $MODROOT =="
	MD=""
	for d in "$MODROOT"/lib/modules/*/ "$MODROOT"/usr/lib/modules/*/; do
		[ -f "$d/modules.dep" ] && { MD=${d%/}; break; }
	done
	[ -n "$MD" ] || { echo "no hay modules.dep bajo $MODROOT (¿ha terminado el build v2 con modules_install?)" >&2; exit 2; }
	KREL=$(basename "$MD")
	say "  krel=$KREL  ($MD)"
	errf=$(mktemp)
	set +e
	# shellcheck disable=SC2086
	MODLIST=$("$HERE/modclosure.sh" "$MD/modules.dep" $MODS_WANT 2>"$errf")
	rc=$?
	set -e
	sed 's/^/  /' "$errf" >&2 || true
	rm -f "$errf"
	for need in ath11k_ahb ath11k qcom_q6v5_pas qrtr_smd cfg80211 mac80211; do
		n=${need//_/[-_]}
		echo "$MODLIST" | grep -Eq "/${n}\.ko$" || { echo "FALTA en el modroot un modulo imprescindible: $need" >&2; exit 2; }
	done
	[ "$rc" -eq 0 ] || say "  (algun modulo opcional no esta en modules.dep: normal si es built-in en esta config; imprescindibles OK)"
	for f in $MODLIST; do
		vm=$(strings -a "$MD/$f" | sed -n 's/^vermagic=\([^ ]*\) .*/\1/p' | head -1)
		[ "$vm" = "$KREL" ] || { echo "vermagic de $f = '$vm' != $KREL" >&2; exit 2; }
	done
	say "  $(echo "$MODLIST" | wc -l) modulos en el cierre, vermagic == $KREL"
	echo "$MODLIST" | sed 's/^/    /'
fi

# ------------------------------------------------------------------ plan
say "== plan =="
if [ "$MODULES" = 1 ]; then PLAN_MOD="modulos ($KREL) + depmod -a   [--modules]"; else PLAN_MOD="(sin --modules: los modulos del kernel v2 los instalas tu / el otro agente; uke-wifi-up.sh avisa si faltan)"; fi
if [ "$HAVE_CREDS" = 1 ]; then PLAN_WPA="con red '$WIFI_SSID' (PSK hasheada, modo 600; copia .bak si existia)"; else PLAN_WPA="solo-escaneo si no existe; si existe no se toca"; fi
if [ "$ARM" = 1 ]; then PLAN_ARM="ARMAR: systemctl enable uke-wifi.service + uke-bootguard reset wifi (WiFi en cada arranque; interruptor /etc/uke/no-wifi + guarda)"; else PLAN_ARM="sin --arm: unidad instalada pero NO enabled; test manual"; fi
cat <<EOF
  destino : $SSHUSER@$HOST  (clave $KEY)
  1. preflight remoto (root, tar, sha256sum, systemctl, >=50 MB libres, / en rw)
  2. $PLAN_MOD
  3. tar|ssh de root/ -> /   (firmware, uke-wifi-up.sh, unidad, .link/.network)
  4. board-2.bin de linux-firmware -> board-2.bin.stock-linux-firmware   (api-2 ganaria a board.bin)
  5. sha256sum -c del firmware EN LA TABLET (detecta el b08 corrupto de la imagen si algo falla)
  6. wpa_supplicant conf: $PLAN_WPA
  7. daemon-reload, udevadm control --reload, networkctl reload, sync
  8. $PLAN_ARM
EOF

if [ "$GO" = 0 ] && [ "$CHECK" = 0 ]; then
	say "Nada ejecutado (falta --go). Para aplicar:  $0 --go [--modules] [--arm]"
	exit 0
fi

# ------------------------------------------------------------------ --check (solo lectura remota)
remote_check() {
	S 'bash -s' <<'REMOTE'
echo "kernel: $(uname -r)   uptime: $(cut -d' ' -f1 /proc/uptime)s   host: $(hostname)"
echo "modulos instalados: $(ls /usr/lib/modules 2>/dev/null | tr '\n' ' ')"
for m in ath11k_ahb qcom_q6v5_pas qrtr_smd cfg80211 mac80211; do printf '  modinfo %-16s %s\n' "$m" "$(modinfo -n $m 2>&1 | head -1)"; done
H=/usr/lib/firmware/ath11k/WCN6750/hw1.0
ls -l $H 2>&1 | sed 's/^/  /'
[ -e $H/board-2.bin ] && echo "  !! board-2.bin presente"
echo "wpss.b08 en la tablet: $(sha256sum /usr/lib/firmware/qca6750/wpss.b08 2>&1 | cut -c1-16) (correcto: 0de7c47d174666be)"
[ -f /usr/lib/firmware/uke-wifi-fw.sha256 ] && (cd / && sha256sum -c --quiet usr/lib/firmware/uke-wifi-fw.sha256 && echo "  uke-wifi-fw.sha256 OK") || echo "  firmware WiFi: NO desplegado o NO casa"
echo "blacklist ath11k: $( [ -f /etc/modprobe.d/blacklist-ath11k.conf ] && echo presente || echo AUSENTE )"
echo "phy: $(ls /sys/class/ieee80211 2>/dev/null | tr '\n' ' ')"
REMOTE
}
if [ "$CHECK" = 1 ] && [ "$GO" = 0 ]; then
	say "== --check remoto (solo lectura) =="
	remote_check
	exit 0
fi

# ------------------------------------------------------------------ --go
say "== 1. preflight remoto =="
S 'bash -s' <<'REMOTE'
set -e
[ "$(id -u)" = 0 ] || { echo "no soy root en la tablet" >&2; exit 1; }
for b in tar sha256sum systemctl modprobe depmod ip wpa_supplicant wpa_cli networkctl timeout udevadm; do
	command -v "$b" >/dev/null || { echo "FALTA en la tablet: $b" >&2; exit 1; }
done
free=$(df -Pk / | awk 'NR==2{print $4}')
[ "$free" -ge 51200 ] || { echo "poco espacio en /: ${free} KB" >&2; exit 1; }
echo "tablet: kernel $(uname -r), uptime $(cut -d' ' -f1 /proc/uptime)s, libres ${free} KB"
mount | grep -E ' / ' | grep -q '[( ,]ro[, )]' && { echo "/ esta montado SOLO LECTURA: aborto" >&2; exit 1; }
true
REMOTE

if [ "$MODULES" = 1 ]; then
	say "== 2. modulos $KREL =="
	{
		printf '%s\n' $MODLIST
		for x in modules.builtin modules.builtin.modinfo modules.order; do [ -f "$MD/$x" ] && echo "$x"; done
	} | tar -C "$MD" --no-recursion --owner=0 --group=0 --numeric-owner \
		--transform="s,^,usr/lib/modules/$KREL/," -cf - -T - \
		| S 'tar -xpf - --no-overwrite-dir -C / && depmod -a '"$KREL"' && echo "depmod -a '"$KREL"' OK" && sync'
fi

say "== 3. tar|ssh de root/ -> / =="
(cd "$TREE" && find . -type f -print0) \
	| tar -C "$TREE" --no-recursion --null --owner=0 --group=0 --numeric-owner -cf - -T - \
	| S 'tar -xpf - --no-overwrite-dir -C / && sync'

say "== 6. wpa_supplicant conf =="
if [ "$HAVE_CREDS" = 1 ]; then
	gen_wpa_conf | S 'umask 077; mkdir -p /etc/wpa_supplicant; c=/etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf; [ -f $c ] && cp -p $c $c.bak; cat > $c.new && mv $c.new $c && chmod 600 $c && echo "conf escrita (red con PSK hasheada)"'
else
	gen_wpa_conf | S 'umask 077; mkdir -p /etc/wpa_supplicant; c=/etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf; if [ -f $c ]; then cat >/dev/null; echo "conf existente: no se toca"; else cat > $c && chmod 600 $c && echo "conf solo-escaneo creada"; fi'
fi

say "== 4,5,7,8. post-instalacion remota =="
S "bash -s -- $ARM" <<'REMOTE'
set -eu
ARM=$1
cd /
H=usr/lib/firmware/ath11k/WCN6750/hw1.0
chmod 0755 usr/local/sbin/uke-wifi-up.sh
mkdir -p /var/lib/uke-wifi
# 4) board-2.bin de linux-firmware: api-2 se prueba ANTES que board.bin (calibracion ajena posible)
if [ -e $H/board-2.bin ] && [ ! -e $H/board-2.bin.stock-linux-firmware ]; then
	mv $H/board-2.bin $H/board-2.bin.stock-linux-firmware && echo "board-2.bin -> board-2.bin.stock-linux-firmware"
elif [ -e $H/board-2.bin ]; then
	rm -f $H/board-2.bin && echo "board-2.bin (reinstalado por pacman?) eliminado; copia previa ya existia"
fi
# 5) sha EN LA TABLET
sha256sum -c --quiet usr/lib/firmware/uke-wifi-fw.sha256 && echo "firmware OK en la tablet (15 ficheros)"
# la blacklist de ath11k se queda (REGLAS 1.9)
[ -f etc/modprobe.d/blacklist-ath11k.conf ] && echo "blacklist ath11k: presente (intacta)" || echo "AVISO: falta la blacklist ath11k"
# 7)
systemctl daemon-reload
udevadm control --reload 2>/dev/null || true
networkctl reload 2>/dev/null || true
# 8)
if [ "$ARM" = 1 ]; then
	[ -x /usr/local/sbin/uke-bootguard ] || { echo "FALTA /usr/local/sbin/uke-bootguard: aplica antes build/rootfs/deploy/arranque/deploy.sh --go (sin la guarda la unidad se omite sola)" >&2; exit 1; }
	rm -f /var/lib/uke-wifi/armed
	/usr/local/sbin/uke-bootguard reset wifi
	systemctl enable uke-wifi.service
	echo "ARMADO: uke-wifi.service enabled; el WiFi arrancara en cada arranque (apagarlo: touch /etc/uke/no-wifi)"
else
	echo "uke-wifi.service instalada, NO enabled. Test manual: /usr/local/sbin/uke-wifi-up.sh"
fi
sync
REMOTE

say "== hecho. Siguiente (a mano, por SSH, con sesion persistente abierta) =="
cat <<EOF
  ssh -i $KEY $SSHUSER@$HOST '/usr/local/sbin/uke-wifi-up.sh --status'
  ssh -i $KEY $SSHUSER@$HOST '/usr/local/sbin/uke-wifi-up.sh --no-net'   # etapa A: rails+WPSS+ath11k hasta wlan0
  ssh -i $KEY $SSHUSER@$HOST '/usr/local/sbin/uke-wifi-up.sh'            # etapa B: + wpa_supplicant + DHCP
  Si el SSH muere: es un wedge. Al volver, 'journalctl -b -1 -k' / /var/log/uke-wifi.log / pstore.
EOF
