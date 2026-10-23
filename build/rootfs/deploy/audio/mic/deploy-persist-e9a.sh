#!/bin/bash
# mic/deploy-persist-e9a.sh — PERSISTENCIA de la tarjeta combinada e9a (altavoces + micro) al arrancar. BORRADOR del PC (21-oct-2026). Solo FICHEROS: no carga modulos, no reinicia, no toca PipeWire en marcha.
#   sin --go ni --check : verifica en el PC (harnesses de audio, mic y altavoces; vermagic ouke5) sin conexion.
#   --check             : lectura por SSH (¿instalado?, tarjeta actual).
#   --go                : instala (1) lo de deploy-amps.sh --service (script con fallback a e8b, gancho de ruta de micro) y los .ko del micro (deploy-mic.sh --go);
#                         (2) el drop-in uke-audio-amps.service.d/e9a.conf (selecciona e9a y la ruta amic1); (3) /etc/pipewire/pipewire.conf.d/51-uke-mic.conf (fuente `uke-mic`, nofail); daemon-reload.
#                         Surte efecto en el PROXIMO arranque (o a mano: UKE_AUDIO_CARD_MOD=uke_audio_e9a uke-audio-amps-up.sh con la etapa 2 parada).
#   --revert            : borra el drop-in y 51-uke-mic.conf (vuelve a e8b en el siguiente arranque).
# HOSTIP por entorno (por defecto Tailscale `uke`). Gates antes de reiniciar: cargador, vigia, doble captura, ACM; apagado rapido: touch /etc/uke/no-audio-amps.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); A=$(cd "$HERE/.." && pwd); R=$(cd "$A/../../../.." && pwd)
HOSTIP=${HOSTIP:-uke}; KEY=$R/build/rootfs/uke-arch-root; KREL=7.2.9-senemos.1.4054.3-ouke5
GO=0; CHECK=0; REVERT=0
say() { printf '[persist-e9a %s] %s\n' "$(date +%H:%M:%S)" "$*"; }; die() { say "ABORTADO: $*"; exit 2; }
for a in "$@"; do case "$a" in --go) GO=1;; --check) CHECK=1;; --revert) REVERT=1;; *) die "opcion desconocida: $a";; esac; done
for h in "$A/boot/harness/test-audio-up.sh" "$A/boot/harness/test-audio-amps-up.sh" "$HERE/harness/test-mic.sh" "$A/pipewire/test-speakers-private.sh"; do
	"$h" >/tmp/uke-persist-test.$$ 2>&1 || { tail -6 /tmp/uke-persist-test.$$; rm -f /tmp/uke-persist-test.$$; die "falla $(basename "$h")"; }
	say "ok  $(basename "$h") ($(tail -1 /tmp/uke-persist-test.$$))"
done
rm -f /tmp/uke-persist-test.$$
[ -s "$A/boot/root/etc/systemd/system/uke-audio-amps.service.d/e9a.conf" ] && [ -s "$A/pipewire/51-uke-mic.conf" ] || die "faltan ficheros locales"
[ $((GO+CHECK+REVERT)) = 0 ] && { say "Nada ejecutado (sin conexion). Aplicar: HOSTIP=uke $0 --go"; exit 0; }
SSHO="-i $KEY -o BatchMode=yes -o ConnectTimeout=8"; rssh() { ssh $SSHO root@"$HOSTIP" "$@"; }
[ "$(rssh uname -r 2>/dev/null)" = "$KREL" ] || die "la tablet no esta en $KREL (o sin SSH)"
if [ "$REVERT" = 1 ]; then rssh "rm -fv /etc/systemd/system/uke-audio-amps.service.d/e9a.conf /etc/pipewire/pipewire.conf.d/51-uke-mic.conf; systemctl daemon-reload; sync"; exit 0; fi
if [ "$GO" = 1 ]; then
	HOSTIP=$HOSTIP KREL=$KREL "$A/boot/deploy-amps.sh" --go --service > /tmp/uke-persist-amps.$$ 2>&1 || { tail -8 /tmp/uke-persist-amps.$$; rm -f /tmp/uke-persist-amps.$$; die "deploy-amps.sh --go --service"; }; rm -f /tmp/uke-persist-amps.$$
	HOSTIP=$HOSTIP "$HERE/deploy-mic.sh" --go > /tmp/uke-persist-mic.$$ 2>&1 || { tail -8 /tmp/uke-persist-mic.$$; rm -f /tmp/uke-persist-mic.$$; die "deploy-mic.sh --go"; }; rm -f /tmp/uke-persist-mic.$$
	rssh "mkdir -p /etc/systemd/system/uke-audio-amps.service.d /etc/pipewire/pipewire.conf.d /lib/modules/$KREL/extra; test -x /usr/local/sbin/uke-bootguard && test -s /lib/firmware/fs19xx.fsm" || die "faltan uke-bootguard o fs19xx.fsm en la tablet (etapa 2 no instalada)"
	scp $SSHO "$A/boot/root/etc/systemd/system/uke-audio-amps.service.d/e9a.conf" root@"$HOSTIP":/etc/systemd/system/uke-audio-amps.service.d/ >/dev/null || die "scp drop-in"
	scp $SSHO "$A/pipewire/51-uke-mic.conf" root@"$HOSTIP":/etc/pipewire/pipewire.conf.d/ >/dev/null || die "scp 51-uke-mic.conf"
	rssh "chmod 644 /etc/systemd/system/uke-audio-amps.service.d/e9a.conf /etc/pipewire/pipewire.conf.d/51-uke-mic.conf; systemctl daemon-reload; sync"
fi
say "== estado remoto =="
rssh "ls -l /etc/systemd/system/uke-audio-amps.service.d/ /etc/pipewire/pipewire.conf.d/ 2>&1 | grep -E 'e9a|mic|speakers'; systemctl cat uke-audio-amps 2>/dev/null | grep -E 'UKE_AUDIO'; cat /proc/asound/cards | head -1"
