#!/bin/bash
# deploy-speakers.sh — instala en la tablet SOLO el fichero 51-uke-speakers.conf (E9). No reinicia PipeWire ni carga nada.
#   sin --go ni --check : verifica en el PC (sintaxis, test-speakers-private.sh) sin conexion.
#   --check             : lectura por SSH (¿instalado?, ¿tarjeta UKE?, sumideros).
#   --go                : copia a /etc/pipewire/pipewire.conf.d/51-uke-speakers.conf (mode 644) y uke-nivel.sh a /usr/local/sbin.
#   --restart (con --go): reinicia PipeWire/WirePlumber de la sesion Omarchy (corta un instante el audio BT en uso).
#   --revert            : borra el fichero (y con --restart reinicia PipeWire).
# Requisito: etapa 2 del audio activa (tarjeta UKE). Quitar rapido: borrar el fichero y reiniciar pipewire.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../../.." && pwd)
HOSTIP=${HOSTIP:-192.168.42.129}; KEY=$R/build/rootfs/uke-arch-root; F=51-uke-speakers.conf; D=/etc/pipewire/pipewire.conf.d
GO=0; CHECK=0; RESTART=0; REVERT=0
say() { printf '[deploy-speakers %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { say "ABORTADO: $*"; exit 2; }
for a in "$@"; do case "$a" in --go) GO=1;; --check) CHECK=1;; --restart) RESTART=1;; --revert) REVERT=1;; *) die "opcion desconocida: $a";; esac; done
"$HERE/test-speakers-private.sh" > /tmp/uke-sp-test.$$ 2>&1 && say "ok  test-speakers-private.sh ($(tail -1 /tmp/uke-sp-test.$$))" || { tail -10 /tmp/uke-sp-test.$$; rm -f /tmp/uke-sp-test.$$; die "falla la prueba privada"; }
rm -f /tmp/uke-sp-test.$$
[ $((GO+CHECK+REVERT)) = 0 ] && { say "Nada ejecutado (sin conexion). Aplicar: $0 --go [--restart]"; exit 0; }
rssh() { ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 root@"$HOSTIP" "$@"; }
rest() { rssh 'u=omarchy; id=$(id -u $u); XDG_RUNTIME_DIR=/run/user/$id runuser -u $u -- systemctl --user reset-failed pipewire.socket pipewire pipewire-pulse.socket pipewire-pulse wireplumber; XDG_RUNTIME_DIR=/run/user/$id runuser -u $u -- systemctl --user restart pipewire.socket pipewire-pulse.socket pipewire pipewire-pulse wireplumber; sleep 3; XDG_RUNTIME_DIR=/run/user/$id runuser -u $u -- wpctl status 2>/dev/null | sed -n "/Sinks:/,/Sources:/p"'; }
if [ "$REVERT" = 1 ]; then rssh "rm -fv $D/$F; sync"; [ "$RESTART" = 1 ] && rest; exit 0; fi
if [ "$GO" = 1 ]; then
	rssh "grep -q UKE /proc/asound/cards" || die "no hay tarjeta UKE (etapa 2 del audio sin cargar)"
	scp -i "$KEY" -o BatchMode=yes "$HERE/$F" root@"$HOSTIP":$D/ >/dev/null || die "scp"
	scp -i "$KEY" -o BatchMode=yes "$HERE/uke-nivel.sh" root@"$HOSTIP":/usr/local/sbin/ >/dev/null || die "scp uke-nivel"
	rssh "chmod 644 $D/$F; chmod 755 /usr/local/sbin/uke-nivel.sh; sync"
	[ "$RESTART" = 1 ] && rest
fi
say "== estado remoto =="
rssh "ls -l $D/$F 2>&1; sha256sum $D/$F | cut -c1-16; cat /proc/asound/cards" ; sha256sum "$HERE/$F" | cut -c1-16
