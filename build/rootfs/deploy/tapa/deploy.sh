#!/usr/bin/env bash
# deploy.sh — hall de la funda (uke-tapa) en la tablet por SSH (tar|ssh: el rootfs no tiene sftp).
#   (sin args)  solo verifica el arbol local y muestra el plan (sin red)
#   --check     lectura por SSH (estado de modulo, input, logind, gpio)
#   --install   instala uke_tapa.ko + depmod + drop-in de logind + uke-tapa.service (SIN cargar, SIN habilitar, SIN recargar logind)
#   --load      modprobe uke_tapa (APLICA el overlay de DT en caliente) y reinicia nada
#   --arm       systemctl enable uke-tapa.service (carga el overlay en cada arranque; hazlo tras verificar --load)
#   --revert    rmmod uke_tapa, disable+borra servicio, drop-in y .ko, depmod
# Tablet sin cambios de slot/boot. Nunca toca debugfs.
set -Eeuo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../.." && pwd)
KEY=${UKE_KEY:-$R/build/rootfs/uke-arch-root}; HOST=${UKE_HOST:-192.168.42.129}
KO=${KO:-$HERE/out/uke_tapa.ko}; KREL=${KREL:-7.2.9-senemos.1.4054.3-ouke5}   # ouke4: KO=out-ouke4/uke_tapa.ko KREL=...-ouke4
sshq() { ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 "root@$HOST" "$@"; }
MODE=${1:-plan}
[ "$(cd "$HERE/out" && sha256sum -c SHA256SUMS >/dev/null 2>&1 && echo ok)" = ok ] || { echo "out/ no coincide con SHA256SUMS: corre build.sh"; exit 1; }
[ "$(modinfo -F vermagic "$KO" | cut -d' ' -f1)" = "$KREL" ] || { echo "vermagic != $KREL"; exit 1; }
case $MODE in
plan) echo "arbol local OK (sha y vermagic). Modos: --check --install --load --arm --revert" ;;
--check) sshq 'uname -r; grep -E "^uke_tapa " /proc/modules || echo "uke_tapa: no cargado"; grep -A4 "uke-lid-hall\|uke-hall" /proc/bus/input/devices | head -12; systemctl is-enabled uke-tapa.service 2>&1; ls /etc/systemd/logind.conf.d/; grep -E "gpio(99|100) " /sys/kernel/debug/gpio' ;;
--install)
	[ "$(sshq uname -r)" = "$KREL" ] || { echo "la tablet no corre $KREL"; exit 1; }
	sshq 'mkdir -p /usr/lib/modules/'$KREL'/extra' && cat "$KO" | sshq 'cat > /usr/lib/modules/'$KREL'/extra/uke_tapa.ko'
	tar -C "$HERE/root" -cf - etc | sshq 'tar -C / -xf -'
	sshq 'depmod -a '$KREL' && systemctl daemon-reload && sha256sum /usr/lib/modules/'$KREL'/extra/uke_tapa.ko' ;;
--load) sshq 'modprobe uke_tapa && dmesg | grep uke_tapa | tail -3' ;;
--arm) sshq 'systemctl enable uke-tapa.service' ;;
--revert) sshq 'rmmod uke_tapa 2>&1; systemctl disable uke-tapa.service 2>&1; rm -f /etc/systemd/system/uke-tapa.service /etc/systemd/logind.conf.d/30-uke-tapa.conf /usr/lib/modules/'$KREL'/extra/uke_tapa.ko; depmod -a '$KREL'; systemctl daemon-reload' ;;
*) echo "modo desconocido"; exit 2 ;;
esac
