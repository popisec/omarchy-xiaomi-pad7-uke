#!/bin/bash
# boot/deploy-amps.sh — persistencia de E8 (altavoces): etapa 2 del audio (uke-audio-amps.service). NO carga NADA.
#   sin --go ni --check : verifica en el PC (vermagic, shas, sintaxis, harness con mocks) e imprime el plan, sin conexion.
#   --check             : lectura por SSH (shas remotos vs locales, estado de servicios).
#   --go + partes:
#     --module   copia a extra/: uke_fs19xx.ko uke_audio_e7i2c.ko uke_audio_e3.ko uke_audio_e8b.ko; preset /lib/firmware/fs19xx.fsm; /etc/modprobe.d/uke-audio-amps.conf; depmod
#     --service  uke-audio-amps.service (SIN habilitar) + uke-audio-amps-up.sh + /etc/modules-load.d/uke-fuse.conf (fuse al arrancar); daemon-reload
#     --arm      systemctl enable uke-audio-amps.service + uke-bootguard reset audio (el audio de altavoces arrancara en cada arranque)
#   --revert             deshabilita y borra servicio, script y modprobe.conf (los .ko y el preset se quedan: inocuos sin carga)
# Requisito: la etapa 1 (boot/deploy.sh --module --service --arm) ya instalada. Apagado sin reflashear: touch /etc/uke/no-audio-amps
# NUNCA toca: slot, boot.img, remoteproc, uke-audio.service, uke-bootguard (su KNOWN ya incluye 'audio'; la etapa 2 comparte ese contador).
set -u
HERE=$(cd "$(dirname "$0")" && pwd); A=$(cd "$HERE/.." && pwd); R=$(cd "$A/../../../.." && pwd)
HOSTIP=${HOSTIP:-192.168.42.129}; KEY=$R/build/rootfs/uke-arch-root; KREL=${KREL:-7.2.9-senemos.1.4054.3-ouke4}   # ouke5: KREL=7.2.9-senemos.1.4054.3-ouke5 (usa out-ouke5/)
KO=$A/out; case "$KREL" in *ouke5) KO=$A/out-ouke5;; esac
FSM=$R/build/android/cosecha-20261017/audio/fs19xx.fsm
GO=0; CHECK=0; MODULE=0; SERVICE=0; ARM=0; REVERT=0
say() { printf '[deploy-amps %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { say "ABORTADO: $*"; exit 2; }
for a in "$@"; do case "$a" in --go) GO=1;; --check) CHECK=1;; --module) MODULE=1;; --service) SERVICE=1;; --arm) ARM=1;; --revert) REVERT=1;; -h|--help) awk 'NR>1 && /^set -u/{exit} NR>1' "$0"; exit 0;; *) die "opcion desconocida: $a";; esac; done
PARTS=$((MODULE+SERVICE+ARM+REVERT))
[ "$REVERT" = 1 ] && [ $((MODULE+SERVICE+ARM)) -gt 0 ] && die "--revert no se combina con instalar"
[ "$GO" = 1 ] && [ "$PARTS" = 0 ] && die "--go sin partes: --module --service --arm (o --revert)"
SSHO="-i $KEY -o BatchMode=yes -o ConnectTimeout=8"
MODS="uke_fs19xx uke_audio_e7i2c uke_audio_e3 uke_audio_e8b"
say "== verificacion local =="
for k in $MODS; do
	[ -s "$KO/$k.ko" ] || die "falta out/$k.ko"
	[ "$(modinfo -F vermagic "$KO/$k.ko" | cut -d' ' -f1)" = "$KREL" ] || die "$k.ko no es para $KREL"
	say "  ok  $k.ko ($(sha256sum "$KO/$k.ko" | cut -c1-16))"
done
[ "$(stat -c %s "$FSM" 2>/dev/null)" = 4828 ] || die "falta el preset $FSM (4828 B)"
for f in root/usr/local/sbin/uke-audio-amps-up.sh root/etc/systemd/system/uke-audio-amps.service root/etc/modprobe.d/uke-audio-amps.conf root/etc/modules-load.d/uke-fuse.conf; do [ -s "$HERE/$f" ] || die "falta $f"; done
bash -n "$HERE/root/usr/local/sbin/uke-audio-amps-up.sh" && say "  ok  sintaxis"
"$HERE/harness/test-audio-amps-up.sh" > /tmp/uke-amps-test.$$ 2>&1 && say "  ok  harness ($(tail -1 /tmp/uke-amps-test.$$))" || { tail -15 /tmp/uke-amps-test.$$; rm -f /tmp/uke-amps-test.$$; die "falla la prueba con mocks"; }
rm -f /tmp/uke-amps-test.$$
cat <<EOP
PLAN: --module ($MODULE) .ko + preset + modprobe.d + depmod | --service ($SERVICE) unit + script, sin enable | --arm ($ARM) enable + guard reset | --revert ($REVERT)
EOP
[ $((GO+CHECK)) = 0 ] && { say "Nada ejecutado (sin conexion)."; exit 0; }
rssh() { ssh $SSHO root@"$HOSTIP" "$@"; }
[ "$(rssh uname -r 2>/dev/null)" = "$KREL" ] || die "la tablet no esta en $KREL (o sin SSH)"
rssh "systemctl is-enabled uke-audio.service >/dev/null && test -x /usr/local/sbin/uke-bootguard" >/dev/null 2>&1 || die "la etapa 1 (uke-audio.service) no esta instalada y habilitada"
if [ "$GO" = 1 ]; then
	if [ "$REVERT" = 1 ]; then
		rssh "systemctl disable uke-audio-amps.service; rm -fv /etc/systemd/system/uke-audio-amps.service /usr/local/sbin/uke-audio-amps-up.sh /etc/modprobe.d/uke-audio-amps.conf /etc/modules-load.d/uke-fuse.conf; systemctl daemon-reload; sync"
	fi
	if [ "$MODULE" = 1 ]; then
		for k in $MODS; do scp $SSHO "$KO/$k.ko" root@"$HOSTIP":/lib/modules/$KREL/extra/ >/dev/null || die "scp $k"; done
		scp $SSHO "$FSM" root@"$HOSTIP":/lib/firmware/fs19xx.fsm >/dev/null || die "scp preset"
		scp $SSHO "$HERE/root/etc/modprobe.d/uke-audio-amps.conf" root@"$HOSTIP":/etc/modprobe.d/ >/dev/null || die "scp conf"
		rssh "chmod 644 /lib/modules/$KREL/extra/uke_{fs19xx,audio_e7i2c,audio_e3,audio_e8b}.ko /lib/firmware/fs19xx.fsm /etc/modprobe.d/uke-audio-amps.conf; depmod -a $KREL; sync"
	fi
	if [ "$SERVICE" = 1 ]; then
		scp $SSHO "$HERE/root/usr/local/sbin/uke-audio-amps-up.sh" root@"$HOSTIP":/usr/local/sbin/ >/dev/null || die "scp script"
		scp $SSHO "$HERE/root/etc/systemd/system/uke-audio-amps.service" root@"$HOSTIP":/etc/systemd/system/ >/dev/null || die "scp unit"
		scp $SSHO "$HERE/root/etc/modules-load.d/uke-fuse.conf" root@"$HOSTIP":/etc/modules-load.d/ >/dev/null || die "scp fuse conf"
		rssh "chmod 755 /usr/local/sbin/uke-audio-amps-up.sh; chmod 644 /etc/systemd/system/uke-audio-amps.service /etc/modules-load.d/uke-fuse.conf; systemctl daemon-reload; sync"
	fi
	if [ "$ARM" = 1 ]; then rssh "systemctl enable uke-audio-amps.service && /usr/local/sbin/uke-bootguard reset audio; sync"; fi
fi
say "== estado remoto =="
for k in $MODS; do printf '%s  local %s  remoto %s\n' "$k" "$(sha256sum "$KO/$k.ko" | cut -c1-12)" "$(rssh "sha256sum /lib/modules/$KREL/extra/$k.ko 2>/dev/null | cut -c1-12")"; done
rssh "systemctl is-enabled uke-audio-amps.service 2>&1; systemctl is-active uke-audio-amps.service 2>&1; ls /etc/modprobe.d/uke-audio-amps.conf /usr/local/sbin/uke-audio-amps-up.sh 2>&1; lsmod | grep -cE '^(uke_fs19xx|uke_audio_e8b) '"
