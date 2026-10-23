#!/bin/bash
# e7/deploy.sh — instala en la tablet SOLO FICHEROS de E7 (soporte TDM del altavoz); NO carga nada ni reinicia.
#   sin --go ni --check : solo verifica en el PC (shas, vermagic, topologia) y muestra el plan, sin conexion.
#   --check             : lectura por SSH.
#   --go                : copia UKE-tplg.bin (con el subgrafo TDM; compatible con E4c), updates/snd-q6apm.ko (0005+0006),
#                         updates/q6apm-lpass-dais.ko (0006, ops TDM), extra/uke_audio_e7a.ko y extra/uke_audio_e7b.ko; depmod.
#                         Los modulos de updates/ solo se usan en el PROXIMO arranque o tras `uke-audio-up.sh --down` + `--service`.
#   --revert            : borra updates/q6apm-lpass-dais.ko y extra/uke_audio_e7{a,b}.ko (el snd-q6apm nuevo es superconjunto del anterior: se deja)
# NUNCA toca: remoteproc, ADSP, uke-audio.service, slots, boot.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); A=$(cd "$HERE/.." && pwd); R=$(cd "$A/../../../.." && pwd)
HOSTIP=192.168.42.129; KEY=$R/build/rootfs/uke-arch-root; KREL=7.2.9-senemos.1.4054.3-ouke4
GO=0; CHECK=0; REVERT=0
say() { printf '[deploy-e7 %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { say "ABORTADO: $*"; exit 2; }
for a in "$@"; do case "$a" in --go) GO=1;; --check) CHECK=1;; --revert) REVERT=1;; *) die "opcion desconocida: $a";; esac; done
SSHO="-i $KEY -o BatchMode=yes -o ConnectTimeout=8"
TPLG=$A/firmware/qcom/sm8650/UKE-tplg.bin
for f in "$TPLG" $A/out/snd-q6apm-uke.ko $A/out/q6apm-lpass-dais-uke.ko $A/out/uke_audio_e7a.ko $A/out/uke_audio_e7b.ko; do [ -s "$f" ] || die "falta $f"; done
for k in snd-q6apm-uke q6apm-lpass-dais-uke uke_audio_e7a uke_audio_e7b; do
	[ "$(modinfo -F vermagic "$A/out/$k.ko" | cut -d' ' -f1)" = "$KREL" ] || die "$k.ko no es para $KREL"
done
DEC=$(mktemp); trap 'rm -f "$DEC"' EXIT
alsatplg -d "$TPLG" -o "$DEC" >/dev/null 2>&1 || die "alsatplg no redecodifica UKE-tplg.bin"
grep -q "Primary TDM0 Playback" "$DEC" || die "la topologia no lleva el subgrafo TDM"
say "verificacion local OK: tplg $(sha256sum "$TPLG" | cut -c1-16) ($(stat -c %s "$TPLG") B, con TDM); q6apm $(sha256sum $A/out/snd-q6apm-uke.ko | cut -c1-16); lpass-dais $(sha256sum $A/out/q6apm-lpass-dais-uke.ko | cut -c1-16); e7a/e7b OK"
if [ $((GO + CHECK + REVERT)) = 0 ]; then say "Nada ejecutado (sin conexion). Aplicar:  $0 --go"; exit 0; fi
rssh() { ssh $SSHO root@"$HOSTIP" "$@"; }
[ "$(rssh uname -r 2>/dev/null)" = "$KREL" ] || die "la tablet no esta en $KREL (o sin SSH)"
if [ "$REVERT" = 1 ]; then rssh "rm -fv /lib/modules/$KREL/updates/q6apm-lpass-dais.ko /lib/modules/$KREL/extra/uke_audio_e7a.ko /lib/modules/$KREL/extra/uke_audio_e7b.ko; depmod -a $KREL; sync"; exit 0; fi
if [ "$GO" = 1 ]; then
	say "== copia (solo ficheros) =="
	scp $SSHO "$TPLG" root@"$HOSTIP":/lib/firmware/qcom/sm8650/UKE-tplg.bin >/dev/null || die "scp tplg"
	scp $SSHO $A/out/snd-q6apm-uke.ko root@"$HOSTIP":/root/snd-q6apm-uke.ko >/dev/null || die "scp q6apm"
	scp $SSHO $A/out/q6apm-lpass-dais-uke.ko root@"$HOSTIP":/root/q6apm-lpass-dais-uke.ko >/dev/null || die "scp lpass-dais"
	scp $SSHO $A/out/uke_audio_e7a.ko $A/out/uke_audio_e7b.ko root@"$HOSTIP":/lib/modules/$KREL/extra/ >/dev/null || die "scp e7"
	rssh "set -e; K=$KREL; install -m644 /root/snd-q6apm-uke.ko /lib/modules/\$K/updates/snd-q6apm.ko; install -m644 /root/q6apm-lpass-dais-uke.ko /lib/modules/\$K/updates/q6apm-lpass-dais.ko; chmod 644 /lib/firmware/qcom/sm8650/UKE-tplg.bin /lib/modules/\$K/extra/uke_audio_e7?.ko; depmod -a \$K; sync"
fi
say "== estado remoto =="
rssh "sha256sum /lib/firmware/qcom/sm8650/UKE-tplg.bin /lib/modules/$KREL/updates/*.ko /lib/modules/$KREL/extra/uke_audio_e7?.ko 2>&1 | cut -c1-16,60-; modinfo -n q6apm-lpass-dais; modinfo -n snd-q6apm; lsmod | grep -E '^(apr|uke_audio|q6apm|snd_q6apm)' | cut -d' ' -f1 | tr '\n' ' '"
