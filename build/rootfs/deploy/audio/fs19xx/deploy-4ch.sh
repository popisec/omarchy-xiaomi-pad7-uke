#!/bin/bash
# deploy-4ch.sh — copia a la tablet SOLO ficheros del test de 4 canales: topologia UKE-tplg-4ch.bin (junto a la normal; NO la sustituye) y el WAV de diagnostico
# /root/uke-4ch-seq-40dbfs.wav. Sin --go: verificacion local. Para PROBAR: ver AUDIO-E8-DIAG2-PREPA-20261018.md (cambio de fichero con copia de seguridad y reversa).
set -u
HERE=$(cd "$(dirname "$0")" && pwd); A=$(cd "$HERE/.." && pwd); R=$(cd "$A/../../../.." && pwd)
HOSTIP=192.168.42.129; KEY=$R/build/rootfs/uke-arch-root; SSHO="-i $KEY -o BatchMode=yes -o ConnectTimeout=8"
T=$A/firmware/qcom/sm8650/UKE-tplg-4ch.bin; W=$(mktemp --suffix=.wav); trap 'rm -f "$W"' EXIT
[ -s "$T" ] || { echo "falta $T"; exit 2; }
D=$(mktemp); alsatplg -d "$T" -o "$D" >/dev/null 2>&1; grep -q 'channels_min 4' "$D"; rc=$?; rm -f "$D"; [ $rc = 0 ] || { echo "la topologia no es la de 4 canales"; exit 2; }
"$A/e4c/make-wav4.sh" "$W" >/dev/null || exit 2
echo "[deploy-4ch] local OK: tplg-4ch $(sha256sum "$T" | cut -c1-16), wav $(sha256sum "$W" | cut -c1-16)"
[ "${1:-}" = --go ] || { echo "Nada ejecutado. Aplicar: $0 --go"; exit 0; }
scp $SSHO "$T" root@$HOSTIP:/lib/firmware/qcom/sm8650/UKE-tplg-4ch.bin >/dev/null && scp $SSHO "$W" root@$HOSTIP:/root/uke-4ch-seq-40dbfs.wav >/dev/null \
 && ssh $SSHO root@$HOSTIP 'chmod 644 /lib/firmware/qcom/sm8650/UKE-tplg-4ch.bin; sync; sha256sum /lib/firmware/qcom/sm8650/UKE-tplg*.bin /root/uke-4ch-seq-40dbfs.wav | cut -c1-16,60-'
