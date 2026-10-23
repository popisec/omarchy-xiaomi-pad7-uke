#!/bin/bash
# deploy-ouke5-pre.sh — PREPARA el audio para el kernel ouke5 mientras la tablet aun corre ouke4. SOLO ficheros; no carga nada, no reinicia.
# Valido con la tablet en ouke4 (antes del flash) o ya en ouke5 (si se arranco sin este paso: audio mudo hasta hacerlo).
# Complementa a build/gates/flash-senemos-v5-gated.sh --pre (que instala los .ko de out-ouke5/ en /lib/modules/<ouke5>/extra/ y el arbol de modulos):
# el audio ademas necesita snd-q6apm y q6apm-lpass-dais PARCHEADOS en /lib/modules/<ouke5>/updates/ (el gate de uke-audio-up.sh lo exige).
#   sin --go ni --check : verifica en el PC (vermagic ouke5 de los 8 .ko, harness con ouke5) sin conexion.
#   --check             : lectura por SSH: ¿existe /lib/modules/<ouke5> (flash --pre hecho)?, ¿estan los .ko en extra/ con su sha?, ¿updates/?
#   --go                : copia los dos scripts de arranque con gate ouke[45] a /usr/local/sbin y updates/snd-q6apm.ko y updates/q6apm-lpass-dais.ko (ouke5), depmod -a <ouke5> y comprueba que modinfo -k <ouke5> -n snd-q6apm sale de updates/.
#   --revert            : borra esos dos ficheros de updates/ de ouke5 + depmod. (ouke4 NO se toca nunca: rollback.)
set -u
HERE=$(cd "$(dirname "$0")" && pwd); A=$(cd "$HERE/.." && pwd); R=$(cd "$A/../../../.." && pwd)
HOSTIP=${HOSTIP:-192.168.42.129}; KEY=$R/build/rootfs/uke-arch-root; K5=7.2.9-senemos.1.4054.3-ouke5; K4=7.2.9-senemos.1.4054.3-ouke4; O=$A/out-ouke5
GO=0; CHECK=0; REVERT=0
say() { printf '[deploy-ouke5-pre %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { say "ABORTADO: $*"; exit 2; }
for a in "$@"; do case "$a" in --go) GO=1;; --check) CHECK=1;; --revert) REVERT=1;; *) die "opcion desconocida: $a";; esac; done
MODS="uke_audio_e2d uke_audio_e3 uke_audio_e7i2c uke_audio_e8a uke_audio_e8b uke_fs19xx snd-q6apm-uke q6apm-lpass-dais-uke"
for k in $MODS; do
	[ -s "$O/$k.ko" ] || die "falta out-ouke5/$k.ko"
	[ "$(modinfo -F vermagic "$O/$k.ko" | cut -d' ' -f1)" = "$K5" ] || die "$k.ko no es para $K5"
done
for f in "$O"/*.ko; do [ "$(modinfo -F vermagic "$f" | cut -d' ' -f1)" = "$K5" ] || die "$f no es ouke5 (el flash --pre abortaria)"; done
say "ok  8 .ko en out-ouke5/ con vermagic $K5 (solo ouke5 en la carpeta)"
"$HERE/harness/test-audio-up.sh" >/dev/null 2>&1 && "$HERE/harness/test-audio-amps-up.sh" >/dev/null 2>&1 && say "ok  harness de las dos etapas (incluye ouke5)" || die "fallan los harness"
[ $((GO+CHECK+REVERT)) = 0 ] && { say "Nada ejecutado (sin conexion)."; exit 0; }
SSHO="-i $KEY -o BatchMode=yes -o ConnectTimeout=8"; rssh() { ssh $SSHO root@"$HOSTIP" "$@"; }
RUN=$(rssh uname -r 2>/dev/null); { [ "$RUN" = "$K4" ] || [ "$RUN" = "$K5" ]; } || die "la tablet no esta en $K4 ni $K5 (o sin SSH)"
rssh "test -d /lib/modules/$K5/kernel" || die "no existe /lib/modules/$K5/kernel: ejecuta antes flash-senemos-v5-gated.sh --pre"
if [ "$REVERT" = 1 ]; then rssh "rm -fv /lib/modules/$K5/updates/snd-q6apm.ko /lib/modules/$K5/updates/q6apm-lpass-dais.ko; depmod -a $K5; sync"; exit 0; fi
if [ "$GO" = 1 ]; then
	rssh "mkdir -p /lib/modules/$K5/updates"
	scp $SSHO "$O/snd-q6apm-uke.ko" root@"$HOSTIP":/lib/modules/$K5/updates/snd-q6apm.ko >/dev/null || die "scp snd-q6apm"
	scp $SSHO "$HERE/root/usr/local/sbin/uke-audio-up.sh" "$HERE/root/usr/local/sbin/uke-audio-amps-up.sh" root@"$HOSTIP":/usr/local/sbin/ >/dev/null || die "scp gates"
	rssh "chmod 755 /usr/local/sbin/uke-audio-up.sh /usr/local/sbin/uke-audio-amps-up.sh"
	scp $SSHO "$HERE/root/etc/systemd/system/uke-audio.service" "$HERE/root/etc/systemd/system/uke-audio-amps.service" root@"$HOSTIP":/etc/systemd/system/ >/dev/null || die "scp units"
	rssh "chmod 644 /etc/systemd/system/uke-audio.service /etc/systemd/system/uke-audio-amps.service; systemctl daemon-reload"
	scp $SSHO "$O/q6apm-lpass-dais-uke.ko" root@"$HOSTIP":/lib/modules/$K5/updates/q6apm-lpass-dais.ko >/dev/null || die "scp q6apm-lpass-dais"
	rssh "chmod 644 /lib/modules/$K5/updates/*.ko; depmod -a $K5; sync"
fi
say "== estado remoto =="
for k in uke_audio_e2d uke_audio_e3 uke_audio_e7i2c uke_audio_e8b uke_fs19xx; do printf '%-18s local %s  remoto %s\n' "$k" "$(sha256sum "$O/$k.ko" | cut -c1-12)" "$(rssh "sha256sum /lib/modules/$K5/extra/$k.ko 2>/dev/null | cut -c1-12" || true)"; done
rssh "modinfo -k $K5 -n snd-q6apm; modinfo -k $K5 -n q6apm-lpass-dais; ls -l /lib/modules/$K5/updates 2>&1 | tail -3"
