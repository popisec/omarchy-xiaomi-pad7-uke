#!/usr/bin/env bash
# deploy.sh — NetworkManager solo para wlan0, para que el panel de red de Omarchy funcione (ver README.md).
#   ./deploy.sh check     solo lectura en la tablet (usb0, backend actual, NM instalado)
#   ./deploy.sh apply     instala ficheros y ejecuta `uke-wifi-omarchy apply` (revert automatico a 180 s; se cancela solo si VERDE)
#   ./deploy.sh revert    vuelve a wpa_supplicant + networkd
# Sin credenciales: el PSK hash ya esta en la tablet (conf de wpa_supplicant) y de ahi se migra a un keyfile de NM.
set -Eeuo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
R=$(cd "$HERE/../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}
HOST=${UKE_HOST:-192.168.42.129}
SSH=(ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 root@"$HOST")
HOOK=$HERE/../suspension/root/usr/lib/systemd/system-sleep/uke-resume-stamp
case "${1:-}" in
check) "${SSH[@]}" '/usr/local/sbin/uke-wifi-omarchy status 2>/dev/null || { ip -br a show dev usb0; ip -br a show dev wlan0; systemctl is-active wpa_supplicant-nl80211@wlan0 NetworkManager; pacman -Q networkmanager; }' ;;
apply)
	"${SSH[@]}" 'ip -4 -o addr show dev usb0 | grep -q 192.168.42.129' || { echo "usb0 no esta" >&2; exit 1; }
	tar -C "$HERE/root" --owner=0 --group=0 -cf - . | "${SSH[@]}" 'tar -C / -xf - && chmod 755 /usr/local/sbin/uke-wifi-omarchy && systemctl daemon-reload'
	[ -f "$HOOK" ] && "${SSH[@]}" 'cat > /usr/lib/systemd/system-sleep/uke-resume-stamp.new && chmod 755 /usr/lib/systemd/system-sleep/uke-resume-stamp.new && mv /usr/lib/systemd/system-sleep/uke-resume-stamp.new /usr/lib/systemd/system-sleep/uke-resume-stamp' < "$HOOK"
	# desacoplado: si la conmutacion corta algo, el apply sigue y el revert armado tambien
	"${SSH[@]}" 'setsid nohup /usr/local/sbin/uke-wifi-omarchy apply >/var/log/uke-wifi-omarchy.out 2>&1 </dev/null & sleep 1; echo lanzado'
	echo "esperando resultado (hasta 100 s)..."
	for _ in $(seq 1 50); do sleep 2; "${SSH[@]}" 'grep -E "VERDE|ROJO|ABORTO" /var/log/uke-wifi-omarchy.out' 2>/dev/null && break || true; done
	"${SSH[@]}" '/usr/local/sbin/uke-wifi-omarchy status' ;;
revert) "${SSH[@]}" '/usr/local/sbin/uke-wifi-omarchy revert' ;;
*) sed -n 2,6p "$0"; exit 1 ;;
esac
