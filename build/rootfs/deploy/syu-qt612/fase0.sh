#!/usr/bin/env bash
# FASE 0 del -Syu a Qt 6.12 en la tablet uke (22-oct-2026). Solo PREPARACION: no actualiza ni instala nada.
# Uso: fase0.sh precheck|backup|push|descarga|todo      (desde el PC; SOLO tras el «libre» de la sesion gestora)
# Informes: build/gates/revision/QT612-IMPACTO-20261022.md y QUICKSHELL-QT612-FUENTE-20261022.md
set -euo pipefail
REPO="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
K=$REPO/build/rootfs/uke-arch-root
PK=$HOME/backups/uke-qt612-20261022      # paquetes de Omarchy stable bajados y verificados en el PC
T() { ssh -i "$K" -o BatchMode=yes -o ConnectTimeout=10 root@uke "$@"; }
BK=/root/syu-qt612-20261022
CONF=$BK/pacman-syu.conf                  # copia de /etc/pacman.conf con IgnorePkg; /etc/pacman.conf NO se toca
SHA_OMARCHY=27cd6d88fda0be6c269c14dd65dad6a014384fedc3ea4eb5c742b2b972b10494
SHA_SETTINGS=f653d97a7832eaa6b71dae1a6ce0480cb2631d6ca9a3350534a579cb08c6b309
SHA_QS=e1227d2930f84b78284cdffab8331e6a47632b2f65ee64945d785da1eb659fef

fase=${1:-}
case "$fase" in
precheck)   # solo lectura
  T 'uptime; cat /sys/class/power_supply/*/capacity | head -2; systemctl --failed --no-legend; pgrep -a pacman || echo "sin pacman en marcha"; df -h / | tail -1; free -m | sed -n 2p; ip -br a | grep -E "usb0|wlan0"'
  (cd "$PK" && sha256sum -c <<<"$SHA_OMARCHY  omarchy-4.0.6-1-aarch64.pkg.tar.zst
$SHA_SETTINGS  omarchy-settings-4.0.6-1-aarch64.pkg.tar.zst
$SHA_QS  quickshell-0.3.2.r7.g2b4501a-1-aarch64.pkg.tar.zst")
  ;;
backup)     # escribe SOLO en /root/syu-qt612-20261022
  T "set -e; mkdir -p $BK
    pacman -Q > $BK/pacman-Q.txt; pacman -Qqe > $BK/pacman-Qqe.txt; cp /var/log/pacman.log $BK/
    tar czf $BK/etc.tgz /etc 2>/dev/null
    tar czf $BK/firmware-propio.tgz -C / usr/lib/firmware/qcom usr/lib/firmware/qca6750 usr/lib/firmware/ath11k/WCN6750 usr/lib/firmware/qca 2>/dev/null || true
    for p in quickshell qt6-base qt6-declarative qt6-svg qt6-wayland qt6-imageformats; do
      pacman -Qlq \$p | grep -v '/\$' | tar czf $BK/\$p-\$(pacman -Q \$p | cut -d' ' -f2).files.tgz -T - --no-recursion 2>/dev/null || true
      pacman -Qi \$p > $BK/\$p.Qi.txt
    done
    sha256sum /usr/bin/quickshell > $BK/quickshell.sha256
    ls -la $BK; du -sh $BK; df -h / | tail -1"
  ;;
push)       # copia los paquetes de Omarchy stable al directorio de la tablet y los verifica alli
  T "mkdir -p /root/qs-new"
  scp -i "$K" -o BatchMode=yes "$PK"/*.pkg.tar.zst root@uke:/root/qs-new/
  T "cd /root/qs-new && sha256sum -c <<<\"$SHA_OMARCHY  omarchy-4.0.6-1-aarch64.pkg.tar.zst
$SHA_SETTINGS  omarchy-settings-4.0.6-1-aarch64.pkg.tar.zst
$SHA_QS  quickshell-0.3.2.r7.g2b4501a-1-aarch64.pkg.tar.zst\""
  ;;
descarga)   # -Syuw: sincroniza las DB y DESCARGA a la cache; no instala. Tras esto la DB va por delante: NO usar pacman -S suelto hasta el -Syu
  T "set -e; IGN=\$(pacman -Qq | grep -E '^linux-(aarch64|firmware)' | tr '\\n' ' '); echo \"IgnorePkg = \$IGN\"; du -sh /var/cache/pacman/pkg; df -h /var/cache | tail -1
    grep -v '^#\\?IgnorePkg' /etc/pacman.conf | sed \"/^\\[options\\]/a IgnorePkg = \$IGN\" > $CONF
    OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman --config $CONF -Syuw --noconfirm 2>&1 | tail -25
    echo '--- simulacion de lo que haria el -Su:'; pacman --config $CONF -Su --print --print-format '%n %v' | wc -l
    pacman --config $CONF -Su --print --print-format '%n %v' | grep -E '^(qt6-|systemd |systemd-libs|openssh|util-linux|mkinitcpio|hyprland|quickshell|mesa|linux)' || true
    du -sh /var/cache/pacman/pkg; df -h /var/cache | tail -1"
  ;;
todo) "$0" precheck && "$0" backup && "$0" push && "$0" descarga ;;
*) echo "uso: $0 precheck|backup|push|descarga|todo"; exit 1;;
esac
