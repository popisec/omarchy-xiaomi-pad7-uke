#!/bin/bash
# uke-wifi-up.sh — levanta el WiFi (WCN6750 / ath11k_ahb sobre el WPSS PAS) en la Xiaomi Pad 7 'uke'
# con el kernel senemos 7.2.9 (7.2.9-senemos.1.4054.3-ouke1 y sucesores).
# Instalado en /usr/local/sbin/uke-wifi-up.sh por build/rootfs/deploy/wifi/deploy.sh.
#
# COMO ARRANCA EL WPSS EN ESTE KERNEL (leido del arbol, parches 0014-0016 de MCC45TR):
#   - cliffs_wpss_resource: auto_boot=false  ("startup manual": el remoteproc NO arranca solo al probar).
#   - ath11k_ahb_power_up() (probe de ath11k_ahb) hace, EN ESTE ORDEN: regulator_enable de las 3 rails
#     RF (vdd-cx-mx smpb3 -> vdd-1.8-xo smpb1 -> vdd-1.3-rfa smpb2, orden del icnss2 OEM) y LUEGO
#     rproc_boot(wpss). O sea: cargar ath11k_ahb ES arrancar el WPSS. NO hay que hacer
#     `echo start > /sys/class/remoteproc/*/state` (en Android lo hace init.vendor.wlan.rc porque su
#     icnss2 no llama a rproc_boot). Un start manual ANTES arrancaria el WPSS con las rails RF apagadas.
#   - ath11k pide por QMI (firmware-name de ath11k, NO del WPSS):
#       ath11k/WCN6750/hw1.0/board-2.bin  (api-2; debe NO existir: lo aparta deploy.sh)
#       ath11k/WCN6750/hw1.0/board.bin    (api-1 = bd_o82gl.elf entero -> BDF_TYPE_ELF, sin caldata)
#       ath11k/WCN6750/hw1.0/regdb.bin    (= regdb_xiaomi.bin; fallo no fatal)
#     y el remoteproc pide qca6750/wpss.mdt + wpss.b00..b10,b12 (firmware-name del DT).
#
# ORDEN DE CARGA: cfg80211 mac80211 qrtr qrtr_smd qcom_q6v5_pas -> (ath11k debug_mask) -> ath11k_ahb.
# La blacklist de /etc/modprobe.d/blacklist-ath11k.conf SE QUEDA (solo bloquea la autocarga por
# modalias; el modprobe por nombre sigue funcionando). Este guion no la toca (REGLAS §1.9).
#
# USO (root):
#   uke-wifi-up.sh               # preflight + carga + espera wlan0 + red (wpa_supplicant + networkd)
#   uke-wifi-up.sh --no-net      # solo hasta wlan0 (sin wpa_supplicant)
#   uke-wifi-up.sh --status      # no toca modulos ni hardware (solo escribe el log): estado de rproc/modulos/fw/dmesg
#   uke-wifi-up.sh --down        # para wpa_supplicant, baja wlan0 y descarga ath11k_ahb (rproc_shutdown)
#   uke-wifi-up.sh --force       # salta el aborto por board-2.bin presente (NO recomendado)
#   uke-wifi-up.sh --service     # lo usa uke-wifi.service (idem a sin argumentos)
# Entorno: UKE_WIFI_PROBE_TIMEOUT (90 s), UKE_WIFI_ASSOC_TIMEOUT (40 s),
#          UKE_WIFI_DEBUG_MASK (0x261 = AHB|BOOT|QMI|REG; solo tiene efecto con CONFIG_ATH11K_DEBUG=y).
#
# CODIGOS DE SALIDA: 0 VERDE (phy + netdev) · 2 AMARILLO (WPSS running pero sin phy/netdev: QMI/BDF)
#                    3 ROJO (el WPSS no llego a running) · 4 preflight fallido (no se toco nada).
# Cada paso va a /var/log/uke-wifi.log, a /dev/kmsg y con sync ANTES de lo que puede colgar
# (REGLAS §1.13/§1.14: la evidencia tiene que sobrevivir a un reset).
set -u
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
LOG=/var/log/uke-wifi.log
FWROOT=/usr/lib/firmware
MANIFEST=usr/lib/firmware/uke-wifi-fw.sha256       # relativo a /
HW10=$FWROOT/ath11k/WCN6750/hw1.0
WIFI_DT=/proc/device-tree/soc/qcom,wcn6750
WPSS_DT=/proc/device-tree/soc/remoteproc-wpss@9bb00000
WCN_DEV=17110040.qcom,wcn6750
T_PROBE=${UKE_WIFI_PROBE_TIMEOUT:-90}
T_ASSOC=${UKE_WIFI_ASSOC_TIMEOUT:-40}
DBGMASK=${UKE_WIFI_DEBUG_MASK:-0x261}
DEPS="cfg80211 mac80211 qrtr qrtr_smd qcom_q6v5_pas"
MODE=up
NONET=0
FORCE=0
IFACE=wlan0
DMESG_PAT='ath11k|wpss|remoteproc|qrtr|q6v5|qmi|WLAN|wlan|wcn6750|regdb|board|cfg80211|smmu|iommu|Unhandled|fault|firmware'

say() {
	local m
	m="uke-wifi[$(cut -d' ' -f1 /proc/uptime)]: $*"
	printf '%s\n' "$m"
	printf '%s %s\n' "$(date +%F_%T)" "$m" >> "$LOG" 2>/dev/null
	printf '%s\n' "$m" > /dev/kmsg 2>/dev/null
}
die() { say "ABORTA: $1"; exit "${2:-4}"; }

while [ $# -gt 0 ]; do
	case "$1" in
	--status) MODE=status ;;
	--down) MODE=down ;;
	--no-net) NONET=1 ;;
	--force) FORCE=1 ;;
	--service) : ;;
	-h|--help) awk 'NR>1 && /^set -u/{exit} NR>1' "$0"; exit 0 ;;
	*) echo "argumento no reconocido: $1 (usa --help)" >&2; exit 4 ;;
	esac
	shift
done
[ "$(id -u)" = 0 ] || { echo "hay que ser root" >&2; exit 4; }
mkdir -p "$(dirname "$LOG")"

# ------------------------------------------------------------------ utilidades
rproc_wpss() {
	local r
	for r in /sys/class/remoteproc/remoteproc*; do
		[ -e "$r/name" ] || continue
		if [ "$(cat "$r/name" 2>/dev/null)" = wpss ] || readlink -f "$r/device" 2>/dev/null | grep -q 9bb00000; then
			echo "$r"; return 0
		fi
	done
	return 1
}

# presente = cargado (/sys/module o /proc/modules) o built-in (modinfo -F filename = (builtin))
mod_present() {
	[ -d "/sys/module/$1" ] && return 0
	grep -q "^$1 " /proc/modules 2>/dev/null && return 0
	[ "$(modinfo -F filename "$1" 2>/dev/null)" = "(builtin)" ]
}

find_wlan_iface() {
	local p n
	for p in /sys/class/net/*/phy80211; do
		[ -e "$p" ] || continue
		n=${p#/sys/class/net/}; n=${n%/phy80211}
		if readlink -f "/sys/class/net/$n/device" 2>/dev/null | grep -q "$WCN_DEV"; then
			echo "$n"; return 0
		fi
	done
	return 1
}

snap_regs() {
	local f=/sys/kernel/debug/regulator/regulator_summary
	[ -r "$f" ] || { say "regulator_summary no disponible (debugfs no montado)"; return 0; }
	say "reguladores WLAN/WPSS ($1):"
	grep -E 'wcn6750|wpss|smpb[123]|pmxr2230-s[123]' "$f" 2>/dev/null | sed 's/^/    /' | tee -a "$LOG"
}

dump_diag() {
	local f="/var/log/uke-wifi-dmesg-$(date +%Y%m%d-%H%M%S).txt" r
	dmesg > "$f" 2>/dev/null; sync
	say "dmesg completo guardado en $f"
	r=$(rproc_wpss) && say "rproc $r name=$(cat "$r/name") state=$(cat "$r/state") firmware=$(cat "$r/firmware" 2>/dev/null)"
	[ -r /sys/kernel/debug/devices_deferred ] && { say "devices_deferred:"; sed 's/^/    /' /sys/kernel/debug/devices_deferred | tee -a "$LOG"; }
	say "modulos: $(lsmod | awk 'NR>1{print $1}' | grep -E 'ath11k|cfg80211|mac80211|qrtr|q6v5|qcom_common|sysmon|glink' | tr '\n' ' ')"
	say "dmesg (filtrado, ultimas 70):"
	dmesg | grep -aE "$DMESG_PAT" | tail -n 70 | sed 's/^/    /' | tee -a "$LOG"
}

# ------------------------------------------------------------------ --status
status() {
	local r
	say "== estado (solo lectura) =="
	say "kernel $(uname -r)  uptime $(cut -d' ' -f1 /proc/uptime)s"
	r=$(rproc_wpss) && say "rproc $r name=$(cat "$r/name") state=$(cat "$r/state") firmware=$(cat "$r/firmware" 2>/dev/null)" || say "rproc wpss: NO existe (qcom_q6v5_pas no cargado o nodo ausente)"
	say "modulos: $(lsmod | awk 'NR>1{print $1}' | grep -E 'ath11k|cfg80211|mac80211|qrtr|q6v5|qcom_common|sysmon|glink' | tr '\n' ' ')"
	say "phy: $(ls /sys/class/ieee80211 2>/dev/null | tr '\n' ' ')  iface: $(find_wlan_iface || echo -)"
	say "firmware: $(cd / && sha256sum -c --quiet "$MANIFEST" 2>&1 | head -3 | tr '\n' ' ')$( [ -e "$HW10/board-2.bin" ] && echo ' [board-2.bin PRESENTE]')"
	dmesg | grep -aE 'ath11k|wpss' | tail -n 25 | sed 's/^/    /'
	exit 0
}

# ------------------------------------------------------------------ --down
down() {
	say "== bajando WiFi =="
	systemctl stop 'wpa_supplicant-nl80211@*.service' 2>/dev/null
	local i; i=$(find_wlan_iface) && ip link set "$i" down 2>/dev/null
	sync
	if [ -d /sys/module/ath11k_ahb ]; then
		say "modprobe -r ath11k_ahb ath11k (rproc_shutdown del WPSS + rails RF off)"
		timeout 60 modprobe -r ath11k_ahb ath11k 2>&1 | tee -a "$LOG"
	fi
	local r; r=$(rproc_wpss) && say "rproc $r state=$(cat "$r/state")"
	sync
	exit 0
}

case "$MODE" in status) status ;; down) down ;; esac

# ------------------------------------------------------------------ 1. preflight (sin efectos)
say "== 1. preflight =="
krel=$(uname -r)
bad=0
say "kernel $krel, uptime $(cut -d' ' -f1 /proc/uptime)s, host $(hostname)"

if [ -d /sys/module/ath11k_ahb ]; then
	say "ath11k_ahb ya esta cargado: salto la carga y paso a esperar/diagnosticar"
	ALREADY=1
else
	ALREADY=0
fi

if [ ! -d "$WIFI_DT" ]; then
	say "FALLO: no existe $WIFI_DT en el DT vivo"; bad=1
else
	tr -d '\0' < "$WIFI_DT/compatible" | grep -q 'xiaomi,uke-wcn6750-wifi' || { say "FALLO: compatible del wifi != xiaomi,uke-wcn6750-wifi (sin el parche 0015 ath11k no toma las rails RF)"; bad=1; }
	st=$(tr -d '\0' < "$WIFI_DT/status" 2>/dev/null); [ "$st" = okay ] || [ "$st" = ok ] || { say "FALLO: $WIFI_DT status='$st'"; bad=1; }
fi
[ -d "$WPSS_DT" ] && tr -d '\0' < "$WPSS_DT/compatible" | grep -q 'qcom,cliffs-wpss-pas' || { say "FALLO: nodo WPSS cliffs-wpss-pas ausente del DT vivo"; bad=1; }

if [ ! -f "/usr/lib/modules/$krel/modules.dep" ]; then
	say "FALLO: no hay /usr/lib/modules/$krel/modules.dep (instalar modulos del kernel + depmod -a; deploy.sh --modules)"; bad=1
fi
for m in ath11k_ahb ath11k qcom_q6v5_pas qrtr_smd cfg80211 mac80211; do
	if [ -d "/sys/module/$m" ] || modinfo -n "$m" >/dev/null 2>&1; then :; else say "FALLO: modulo $m no encontrable para $krel"; bad=1; fi
done

out=$(cd / && sha256sum -c --quiet "$MANIFEST" 2>&1) || { say "FALLO: firmware no casa con $MANIFEST:"; printf '%s\n' "$out" | head -8 | sed 's/^/    /'; bad=1; }
for f in $FWROOT/qca6750/wpss.b12 $FWROOT/qca6750/wpss.mdt $HW10/board.bin $HW10/regdb.bin; do
	[ -f "$f" ] || { say "FALLO: falta $f"; bad=1; }
done
if [ -e "$HW10/board-2.bin" ]; then
	if [ "$FORCE" = 1 ]; then
		say "AVISO: board-2.bin (linux-firmware) presente: ath11k intentara api-2 ANTES que board.bin"
	else
		say "FALLO: $HW10/board-2.bin presente (api-2 gana a board.bin: calibracion ajena posible). deploy.sh lo aparta; --force para ignorar"; bad=1
	fi
fi
[ -f /etc/modprobe.d/blacklist-ath11k.conf ] || say "AVISO: falta la blacklist de ath11k (se autocargaria por modalias; REGLAS §1.9)"

[ "$bad" = 0 ] || die "preflight fallido (no se ha cargado nada)" 4
say "preflight OK"

# ------------------------------------------------------------------ 2. dependencias
if [ "$ALREADY" = 0 ]; then
	say "== 2. dependencias: $DEPS =="
	for m in $DEPS; do
		modprobe -q "$m" >> "$LOG" 2>&1
		mod_present "$m" || die "modprobe $m no lo dejo presente (revisa $LOG)" 4
		say "  $m OK"
	done
	for _ in $(seq 1 15); do R=$(rproc_wpss) && break; sleep 1; done
	[ -n "${R:-}" ] || die "no aparece el remoteproc wpss (qcom_q6v5_pas sin bindear: ¿pd_ignore_unused/regulador cx-mx/aoss_qmp?)" 4
	say "rproc: $R name=$(cat "$R/name") state=$(cat "$R/state") firmware=$(cat "$R/firmware" 2>/dev/null)"
	say "  (auto_boot=false: debe estar 'offline' hasta que ath11k_ahb haga rproc_boot)"
fi

# ------------------------------------------------------------------ 3. disparo (lo unico que puede colgar)
snap_regs antes
base=$(dmesg | wc -l)
if [ "$ALREADY" = 0 ]; then
	say "== 3. modprobe ath11k (debug_mask=$DBGMASK) + ath11k_ahb  [sync antes: esto puede resetear] =="
	say "   marcador: UKE-WIFI-PROBE-BEGIN (busca esto en dmesg/pstore si hay reset)"
	sync
	timeout 30 modprobe ath11k debug_mask="$DBGMASK" 2>&1 | tee -a "$LOG"
	mod_present ath11k || die "modprobe ath11k no dejo el modulo" 4
	sync
	timeout -k 5 "$T_PROBE" modprobe ath11k_ahb 2>&1 | tee -a "$LOG"
	rc=${PIPESTATUS[0]}
	say "modprobe ath11k_ahb rc=$rc (124 = timeout: probe colgado)"
fi

# ------------------------------------------------------------------ 4. espera phy/netdev
say "== 4. espera de wlan (hasta ${T_PROBE}s) =="
t0=$(date +%s); last=-1; IF=
while :; do
	el=$(( $(date +%s) - t0 ))
	R=$(rproc_wpss) || R=
	st=$([ -n "$R" ] && cat "$R/state" 2>/dev/null)
	if IF=$(find_wlan_iface); then break; fi
	if [ $((el / 5)) -ne "$last" ]; then
		last=$((el / 5)); say "  t+${el}s rproc=${st:-?} phy=[$(ls /sys/class/ieee80211 2>/dev/null | tr '\n' ' ')]"
	fi
	[ "$el" -ge "$T_PROBE" ] && break
	sleep 1
done
sync
snap_regs despues

if [ -n "$IF" ]; then
	IFACE=$IF
	say "VERDE (parcial): phy+netdev  iface=$IFACE mac=$(cat /sys/class/net/$IFACE/address 2>/dev/null) phy=$(ls /sys/class/ieee80211 | tr '\n' ' ')"
	dmesg | tail -n +$((base + 1)) | grep -aE 'ath11k|qmi|wcn6750|board|regdb|fw_version|chip_id' | head -30 | sed 's/^/    /' | tee -a "$LOG"
	dump_diag >/dev/null 2>&1
	verdict=0
elif [ -n "${R:-}" ] && [ "$(cat "$R/state" 2>/dev/null)" = running ]; then
	say "AMARILLO: WPSS running pero NO hay phy/netdev tras ${T_PROBE}s -> QMI/BDF/regdb/caldata (mira las lineas ath11k de abajo)"
	dump_diag
	verdict=2
else
	say "ROJO: el WPSS no esta running (estado='$(cat "${R:-/nonexistent}/state" 2>/dev/null)') -> PAS/TZ/rails/proxy (mira devices_deferred y dmesg)"
	dump_diag
	verdict=3
fi
[ "$verdict" = 0 ] || exit "$verdict"

# ------------------------------------------------------------------ 5. red
if [ "$NONET" = 1 ]; then
	say "--no-net: me quedo en wlan0 sin red"; exit 0
fi
say "== 5. red (wpa_supplicant-nl80211@$IFACE + systemd-networkd) =="
# ath11k deja la MAC a ceros (no la lee de OTP/BDF) y el .link (10-uke-wlan.link) la fija en el evento 'add'
# de udev. Si por lo que sea no llego a aplicarse ('ip link set up' daria 'Cannot assign requested address';
# pasaba con el .link mal casado, 18-oct), se re-dispara aqui. Solo actua con la MAC a ceros.
if [ "$(cat "/sys/class/net/$IFACE/address" 2>/dev/null)" = 00:00:00:00:00:00 ]; then
	say "MAC a ceros en $IFACE: re-disparo udev 'add' para que el .link la fije"
	udevadm trigger --action=add --subsystem-match=net --sysname-match="$IFACE" 2>&1 | tee -a "$LOG"
	udevadm settle --timeout=10 2>&1 | tee -a "$LOG"
	say "MAC ahora: $(cat "/sys/class/net/$IFACE/address" 2>/dev/null)"
fi
conf=/etc/wpa_supplicant/wpa_supplicant-nl80211-$IFACE.conf
if [ ! -f "$conf" ] && [ -f /etc/wpa_supplicant/wpa_supplicant-nl80211-wlan0.conf ]; then
	ln -s wpa_supplicant-nl80211-wlan0.conf "$conf"
fi
[ -f "$conf" ] || { say "AVISO: sin $conf; ejecuta deploy.sh (crea una conf solo-escaneo) y reintenta"; exit 0; }
ip link set "$IFACE" up 2>&1 | tee -a "$LOG"
systemctl start "wpa_supplicant-nl80211@$IFACE.service" 2>&1 | tee -a "$LOG"
sleep 2
if grep -q '^network={' "$conf"; then
	t0=$(date +%s); ok=0
	while [ $(( $(date +%s) - t0 )) -lt "$T_ASSOC" ]; do
		s=$(wpa_cli -i "$IFACE" status 2>/dev/null | sed -n 's/^wpa_state=//p')
		[ "$s" = COMPLETED ] && { ok=1; break; }
		sleep 1
	done
	say "wpa_state=${s:-?} (esperado COMPLETED)"
	if [ "$ok" = 1 ]; then
		for _ in $(seq 1 20); do ip -4 -o addr show dev "$IFACE" 2>/dev/null | grep -q inet && break; sleep 1; done
		say "ip: $(ip -4 -br addr show dev "$IFACE" 2>&1)"
		say "ruta: $(ip route show default 2>&1 | head -2 | tr '\n' ';')"
		wpa_cli -i "$IFACE" status 2>/dev/null | sed 's/^/    /' | tee -a "$LOG"
		say "VERDE: asociado y con IP. Siguiente: ping de la puerta de enlace y 'dmesg | grep ath11k' tras 300 s de uptime."
	else
		say "AMARILLO: wlan0 existe pero no asocia (¿PSK/SSID, regdom, 6 GHz?). scan:"
		wpa_cli -i "$IFACE" scan_results 2>&1 | head -15 | sed 's/^/    /' | tee -a "$LOG"
		verdict=2
	fi
else
	say "conf sin network={...}: solo escaneo (equivale al 'iw scan' del gate)"
	wpa_cli -i "$IFACE" scan >/dev/null 2>&1; sleep 6
	n=$(wpa_cli -i "$IFACE" scan_results 2>/dev/null | tail -n +2 | wc -l)
	say "scan_results: $n redes"
	wpa_cli -i "$IFACE" scan_results 2>&1 | head -25 | sed 's/^/    /' | tee -a "$LOG"
	[ "$n" -gt 0 ] && say "VERDE: escaneo OK ($n redes). Para asociar: deploy.sh con WIFI_SSID/WIFI_PSK." || { say "AMARILLO: 0 redes (¿regdom/antena/BDF?)"; verdict=2; }
fi
sync
exit "$verdict"
