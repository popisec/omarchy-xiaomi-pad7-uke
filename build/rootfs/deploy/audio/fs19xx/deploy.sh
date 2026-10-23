#!/bin/bash
# fs19xx/deploy.sh — instala en la tablet SOLO FICHEROS de E8 (driver de los 4 FS19xx); NO carga nada ni reinicia.
#   sin --go ni --check : verifica en el PC (shas, vermagic, preset) y muestra el plan, sin conexion.
#   --check             : lectura por SSH.
#   --go                : copia extra/uke_fs19xx.ko, extra/uke_audio_e7i2c.ko, extra/uke_audio_e8a.ko, extra/uke_audio_e8b.ko y
#                         /lib/firmware/fs19xx.fsm (preset del Android, 4828 B, ya presente en build/android/cosecha-20261017/audio/); depmod.
#   --revert            : borra esos cinco ficheros.
# NUNCA toca: remoteproc, ADSP, uke-audio.service, slots, boot, ni carga modulos.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); A=$(cd "$HERE/.." && pwd); R=$(cd "$A/../../../.." && pwd)
HOSTIP=192.168.42.129; KEY=$R/build/rootfs/uke-arch-root; KREL=7.2.9-senemos.1.4054.3-ouke4
FSM=$R/build/android/cosecha-20261017/audio/fs19xx.fsm; FSM_SHA=$(sha256sum "$FSM" 2>/dev/null | cut -d' ' -f1)
GO=0; CHECK=0; REVERT=0
say() { printf '[deploy-e8 %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { say "ABORTADO: $*"; exit 2; }
for a in "$@"; do case "$a" in --go) GO=1;; --check) CHECK=1;; --revert) REVERT=1;; *) die "opcion desconocida: $a";; esac; done
SSHO="-i $KEY -o BatchMode=yes -o ConnectTimeout=8"
MODS="uke_fs19xx uke_audio_e7i2c uke_audio_e8a uke_audio_e8b"
for k in $MODS; do
	[ -s "$A/out/$k.ko" ] || die "falta out/$k.ko (build.sh / build-module.sh)"
	[ "$(modinfo -F vermagic "$A/out/$k.ko" | cut -d' ' -f1)" = "$KREL" ] || die "$k.ko no es para $KREL"
done
[ -s "$FSM" ] && [ "$(stat -c %s "$FSM")" = 4828 ] || die "falta el preset $FSM (4828 B)"
python3 -I "$HERE/dryrun.py" "$FSM" >/dev/null || die "el preset no pasa dryrun.py"
say "verificacion local OK: uke_fs19xx $(sha256sum $A/out/uke_fs19xx.ko | cut -c1-16); e7i2c/e8a/e8b OK; preset $(echo "$FSM_SHA" | cut -c1-16) (4828 B, CRC/descriptores validados)"
if [ $((GO + CHECK + REVERT)) = 0 ]; then say "Nada ejecutado (sin conexion). Aplicar:  $0 --go"; exit 0; fi
rssh() { ssh $SSHO root@"$HOSTIP" "$@"; }
[ "$(rssh uname -r 2>/dev/null)" = "$KREL" ] || die "la tablet no esta en $KREL (o sin SSH)"
if [ "$REVERT" = 1 ]; then rssh "rm -fv /lib/firmware/fs19xx.fsm /lib/modules/$KREL/extra/uke_fs19xx.ko /lib/modules/$KREL/extra/uke_audio_e7i2c.ko /lib/modules/$KREL/extra/uke_audio_e8?.ko; depmod -a $KREL; sync"; exit 0; fi
if [ "$GO" = 1 ]; then
	say "== copia (solo ficheros) =="
	scp $SSHO "$FSM" root@"$HOSTIP":/lib/firmware/fs19xx.fsm >/dev/null || die "scp preset"
	for k in $MODS; do scp $SSHO "$A/out/$k.ko" root@"$HOSTIP":/lib/modules/$KREL/extra/ >/dev/null || die "scp $k"; done
	rssh "set -e; chmod 644 /lib/firmware/fs19xx.fsm /lib/modules/$KREL/extra/uke_fs19xx.ko /lib/modules/$KREL/extra/uke_audio_e7i2c.ko /lib/modules/$KREL/extra/uke_audio_e8?.ko; depmod -a $KREL; sync"
fi
say "== estado remoto =="
rssh "sha256sum /lib/firmware/fs19xx.fsm /lib/modules/$KREL/extra/uke_fs19xx.ko /lib/modules/$KREL/extra/uke_audio_e7i2c.ko /lib/modules/$KREL/extra/uke_audio_e8?.ko 2>&1 | cut -c1-16,60-; lsmod | grep -E '^(uke_fs19xx|uke_audio)' | cut -d' ' -f1 | tr '\n' ' '"
