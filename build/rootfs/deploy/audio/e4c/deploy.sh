#!/bin/bash
# e4c/deploy.sh — instala en la tablet SOLO FICHEROS de E4c (no carga nada): UKE-tplg.bin, uke_audio_e4c.ko y el WAV de prueba (-40 dBFS).
#   sin --go ni --check : solo verifica en el PC (shas, vermagic) y muestra el plan, sin conexion.
#   --check             : lectura por SSH.
#   --go                : copia /lib/firmware/qcom/sm8650/UKE-tplg.bin, /lib/modules/<krel>/extra/uke_audio_e4c.ko (+depmod) y /root/uke-1k-40dbfs.wav
#   --revert            : borra esos tres ficheros (no descarga nada cargado)
# NUNCA toca: remoteproc, ADSP, uke-audio.service, slots, boot.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); A=$(cd "$HERE/.." && pwd); R=$(cd "$A/../../../.." && pwd)
HOSTIP=192.168.42.129; KEY=$R/build/rootfs/uke-arch-root; KREL=7.2.9-senemos.1.4054.3-ouke4
GO=0; CHECK=0; REVERT=0
say() { printf '[deploy-e4c %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { say "ABORTADO: $*"; exit 2; }
for a in "$@"; do case "$a" in --go) GO=1;; --check) CHECK=1;; --revert) REVERT=1;; *) die "opcion desconocida: $a";; esac; done
SSHO="-i $KEY -o BatchMode=yes -o ConnectTimeout=8"
TPLG=$A/firmware/qcom/sm8650/UKE-tplg.bin; KO=$A/out/uke_audio_e4c.ko; WAV=$(mktemp --suffix=.wav); trap 'rm -f "$WAV"' EXIT
[ -s "$TPLG" ] && [ -s "$KO" ] || die "faltan UKE-tplg.bin o uke_audio_e4c.ko (build.sh / build-module.sh)"
[ "$(modinfo -F vermagic "$KO" | cut -d' ' -f1)" = "$KREL" ] || die "uke_audio_e4c.ko no es para $KREL"
alsatplg -d "$TPLG" -o /dev/null >/dev/null 2>&1 || alsatplg -d "$TPLG" -o "$(mktemp)" >/dev/null 2>&1 || die "alsatplg no redecodifica UKE-tplg.bin"
"$HERE/make-wav.sh" "$WAV" >/dev/null || die "make-wav"
say "verificacion local OK: tplg $(sha256sum "$TPLG" | cut -c1-16) ($(stat -c %s "$TPLG") B), e4c.ko $(sha256sum "$KO" | cut -c1-16), wav $(stat -c %s "$WAV") B"
if [ $((GO + CHECK + REVERT)) = 0 ]; then say "Nada ejecutado (sin conexion). Aplicar:  $0 --go"; exit 0; fi
rssh() { ssh $SSHO root@"$HOSTIP" "$@"; }
[ "$(rssh uname -r 2>/dev/null)" = "$KREL" ] || die "la tablet no esta en $KREL (o sin SSH)"
if [ "$REVERT" = 1 ]; then rssh "rm -fv /lib/firmware/qcom/sm8650/UKE-tplg.bin /lib/modules/$KREL/extra/uke_audio_e4c.ko /root/uke-1k-40dbfs.wav; depmod -a $KREL; sync"; exit 0; fi
if [ "$GO" = 1 ]; then
	say "== copia (solo ficheros) =="
	rssh 'mkdir -p /lib/firmware/qcom/sm8650'
	scp $SSHO "$TPLG" root@"$HOSTIP":/lib/firmware/qcom/sm8650/UKE-tplg.bin >/dev/null || die "scp tplg"
	scp $SSHO "$KO" root@"$HOSTIP":/lib/modules/$KREL/extra/uke_audio_e4c.ko >/dev/null || die "scp ko"
	scp $SSHO "$WAV" root@"$HOSTIP":/root/uke-1k-40dbfs.wav >/dev/null || die "scp wav"
	rssh "chmod 644 /lib/firmware/qcom/sm8650/UKE-tplg.bin /lib/modules/$KREL/extra/uke_audio_e4c.ko; depmod -a $KREL; sync"
fi
say "== estado remoto =="
rssh "sha256sum /lib/firmware/qcom/sm8650/UKE-tplg.bin /lib/modules/$KREL/extra/uke_audio_e4c.ko 2>&1 | cut -c1-16; ls -la /root/uke-1k-40dbfs.wav 2>&1; which aplay; lsmod | grep -E '^(apr|uke_audio|q6apm|snd_soc_sc8280xp)' | cut -d' ' -f1 | tr '\n' ' '"
