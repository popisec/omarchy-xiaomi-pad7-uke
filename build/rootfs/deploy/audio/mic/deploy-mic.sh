#!/bin/bash
# mic/deploy-mic.sh — instala en la tablet SOLO FICHEROS de las etapas M1-M3 del micro. NO carga modulos, NO toca PipeWire, NO reinicia. BORRADOR M0 (20-oct-2026).
#   sin --go ni --check : verifica en el PC (vermagic ouke5 de los .ko, harness) sin conexion.
#   --check             : lectura por SSH (¿estan los ficheros?; tarjeta cargada actual).
#   --go                : copia uke_audio_e5.ko y uke_audio_e9a.ko a /lib/modules/<krel>/extra (+depmod), uke-mic-route.sh a /usr/local/sbin, el UCM «UKE» a /usr/share/alsa/ucm2/
#                         y 51-uke-mic.conf a /root/uke-mic/51-uke-mic.conf.pendiente (NO a /etc/pipewire: eso es M5).
#   --revert            : borra esos ficheros.
# HOSTIP por entorno (por defecto Tailscale `uke`: el USB puede caer si el WCD comparte rail con el usbss del USB-C).
set -u
HERE=$(cd "$(dirname "$0")" && pwd); A=$(cd "$HERE/.." && pwd); R=$(cd "$A/../../../.." && pwd)
HOSTIP=${HOSTIP:-uke}; KEY=$R/build/rootfs/uke-arch-root; KREL=7.2.9-senemos.1.4054.3-ouke5; O=$A/out-ouke5
GO=0; CHECK=0; REVERT=0
say() { printf '[deploy-mic %s] %s\n' "$(date +%H:%M:%S)" "$*"; }; die() { say "ABORTADO: $*"; exit 2; }
for a in "$@"; do case "$a" in --go) GO=1;; --check) CHECK=1;; --revert) REVERT=1;; *) die "opcion desconocida: $a";; esac; done
for k in uke_audio_e5 uke_audio_e9a; do [ "$(modinfo -F vermagic "$O/$k.ko" 2>/dev/null | cut -d' ' -f1)" = "$KREL" ] || die "$k.ko no es para $KREL"; done
bash -n "$HERE/uke-mic-route.sh" && bash -n "$HERE/uke-mic-m3.sh" && bash -n "$HERE/uke-mic-click.sh" && "$HERE/harness/test-mic.sh" >/tmp/uke-mic-test.$$ 2>&1 && say "ok  harness ($(tail -1 /tmp/uke-mic-test.$$))" || { tail -8 /tmp/uke-mic-test.$$; rm -f /tmp/uke-mic-test.$$; die "falla el harness"; }
rm -f /tmp/uke-mic-test.$$
[ $((GO+CHECK+REVERT)) = 0 ] && { say "Nada ejecutado (sin conexion)."; exit 0; }
SSHO="-i $KEY -o BatchMode=yes -o ConnectTimeout=8"; rssh() { ssh $SSHO root@"$HOSTIP" "$@"; }
[ "$(rssh uname -r 2>/dev/null)" = "$KREL" ] || die "la tablet no esta en $KREL (o sin SSH)"
if [ "$REVERT" = 1 ]; then rssh "rm -fv /etc/systemd/system/uke-audio-amps.service.d/e9a.conf /lib/modules/$KREL/extra/uke_audio_e5.ko /lib/modules/$KREL/extra/uke_audio_e9a.ko /usr/local/sbin/uke-mic-route.sh /usr/local/sbin/uke-mic-m3.sh /usr/local/sbin/m3-guion.sh /usr/local/sbin/uke-mic-rms.py /usr/share/alsa/ucm2/conf.d/sm8650/UKE.conf /usr/share/alsa/ucm2/Qualcomm/uke/HiFi.conf /root/uke-mic/51-uke-mic.conf.pendiente; rm -rf /root/uke-mic-auto; depmod -a $KREL; sync"; exit 0; fi
if [ "$GO" = 1 ]; then
	scp $SSHO "$O/uke_audio_e5.ko" "$O/uke_audio_e9a.ko" root@"$HOSTIP":/lib/modules/$KREL/extra/ >/dev/null || die "scp .ko"
	scp $SSHO "$HERE/uke-mic-route.sh" "$HERE/uke-mic-m3.sh" "$HERE/m3-guion.sh" "$HERE/m4-guion.sh" "$HERE/m5-zona.sh" "$HERE/uke-mic-click.sh" root@"$HOSTIP":/usr/local/sbin/ >/dev/null || die "scp route/m3"
	scp $SSHO "$HERE/uke-mic-rms.py" root@"$HOSTIP":/usr/local/sbin/ >/dev/null || die "scp rms"
	rssh "mkdir -p /root/uke-mic-auto"; scp $SSHO "$HERE/auto/uke_chirp.py" "$HERE/auto/uke-mic-auto.sh" root@"$HOSTIP":/root/uke-mic-auto/ >/dev/null || die "scp auto"
	rssh "mkdir -p /usr/share/alsa/ucm2/conf.d/sm8650 /usr/share/alsa/ucm2/Qualcomm/uke /root/uke-mic"
	scp $SSHO "$HERE/ucm2/conf.d/sm8650/UKE.conf" root@"$HOSTIP":/usr/share/alsa/ucm2/conf.d/sm8650/ >/dev/null || die "scp ucm card"
	scp $SSHO "$HERE/ucm2/Qualcomm/uke/HiFi.conf" root@"$HOSTIP":/usr/share/alsa/ucm2/Qualcomm/uke/ >/dev/null || die "scp ucm hifi"
	scp $SSHO "$A/pipewire/51-uke-mic.conf" root@"$HOSTIP":/root/uke-mic/51-uke-mic.conf.pendiente >/dev/null || die "scp pw conf"
	rssh "chmod 644 /lib/modules/$KREL/extra/uke_audio_e5.ko /lib/modules/$KREL/extra/uke_audio_e9a.ko; chmod 755 /usr/local/sbin/uke-mic-route.sh /usr/local/sbin/uke-mic-m3.sh /usr/local/sbin/m3-guion.sh /usr/local/sbin/uke-mic-rms.py; depmod -a $KREL; sync"
fi
say "== estado remoto =="
for k in uke_audio_e5 uke_audio_e9a; do printf '%s local %s remoto %s\n' "$k" "$(sha256sum "$O/$k.ko" | cut -c1-12)" "$(rssh "sha256sum /lib/modules/$KREL/extra/$k.ko 2>/dev/null | cut -c1-12")"; done
rssh "ls -l /usr/local/sbin/uke-mic-route.sh /usr/share/alsa/ucm2/Qualcomm/uke/HiFi.conf /root/uke-mic 2>&1 | tail -4; cat /proc/asound/cards | head -2"
