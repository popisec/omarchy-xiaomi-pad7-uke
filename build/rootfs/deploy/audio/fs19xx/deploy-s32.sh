#!/bin/bash
# deploy-s32.sh — copia a la tablet SOLO ficheros del test de dato de 32 bit: UKE-tplg-${V:-s32}.bin (junto a la normal; NO la sustituye). El WAV S32_LE ya se copio (/root/uke-1k-m18-s32.wav).
set -u
HERE=$(cd "$(dirname "$0")" && pwd); A=$(cd "$HERE/.." && pwd); R=$(cd "$A/../../../.." && pwd)
HOSTIP=192.168.42.129; KEY=$R/build/rootfs/uke-arch-root; SSHO="-i $KEY -o BatchMode=yes -o ConnectTimeout=8"
V=${V:-s32}; T=$A/firmware/qcom/sm8650/UKE-tplg-$V.bin
[ -s "$T" ] || { echo "falta $T"; exit 2; }
D=$(mktemp); alsatplg -d "$T" -o "$D" >/dev/null 2>&1; if [ "$V" = chain ]; then grep -q "device24.sal1" "$D"; else grep -q "$(echo $V | tr s S)_LE" "$D"; fi; rc=$?; rm -f "$D"; [ $rc = 0 ] || { echo "la topologia no es la $V"; exit 2; }
echo "[deploy-$V] local OK: tplg-$V $(sha256sum "$T" | cut -c1-16)"
[ "${1:-}" = --go ] || { echo "Nada ejecutado. Aplicar: $0 --go"; exit 0; }
scp $SSHO "$T" root@$HOSTIP:/lib/firmware/qcom/sm8650/UKE-tplg-$V.bin >/dev/null && ssh $SSHO root@$HOSTIP "chmod 644 /lib/firmware/qcom/sm8650/UKE-tplg-$V.bin; sync; sha256sum /lib/firmware/qcom/sm8650/UKE-tplg*.bin | cut -c1-16,60-"
