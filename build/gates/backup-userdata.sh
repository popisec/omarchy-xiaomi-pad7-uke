#!/bin/bash
# backup-userdata.sh — copia de seguridad VERIFICADA del rootfs Linux de la tablet (userdata = /dev/sda32, ext4 8 GiB) al PC, ANTES de la ida a Android.
# BORRADOR del PC (19-oct-2026). NO ejecutado contra la tablet salvo --check (solo lectura ligera). Cada modo:
#   --check        solo lectura por SSH: dispositivo, fs, tamaño, estado, batería, espacio en el PC. No copia nada.
#   --go           copia: dd del fs (por SSH) → sha256 en la tablet Y en el PC (integridad de la transferencia) → zstd en /var/tmp/uke-userdata-backup/.
#                  La copia es de un fs MONTADO en lectura-escritura (sin diario): es «consistente ante caida», no congelada; --verify la comprueba con e2fsck.
#   --verify IMG   en el PC: e2fsck -fn, dumpe2fs, ficheros centinela con debugfs, ida y vuelta sparse (img2simg→simg2img = mismo sha). Sin root.
#   --repair IMG   copia IMG a IMG-fsck.img y ejecuta `e2fsck -fy` SOLO sobre la copia (la imagen cruda original no se toca); registra el sha de la reparada.
#   --restore-plan IMG   imprime (no ejecuta) los comandos de la vuelta a Linux con ese IMG.
# Reglas: nada de escribir en la tablet; solo lecturas (dd if=, tune2fs -l, cat). Ver AUDIO-ANDROID-REFERENCIA-PLAN-20261019.md.
set -u
HOSTIP=${HOSTIP:-192.168.42.129}; R=$(cd "$(dirname "$0")/../.." && pwd); KEY=$R/build/rootfs/uke-arch-root; SSHO="-i $KEY -o BatchMode=yes -o ConnectTimeout=8"
DEV=/dev/sda32; DEST=/var/tmp/uke-userdata-backup; mode=${1:-}
say() { printf '[backup-userdata %s] %s\n' "$(date +%H:%M:%S)" "$*"; }; die() { say "ABORTADO: $*"; exit 2; }
rssh() { ssh $SSHO root@"$HOSTIP" "$@"; }
SENT="/etc/os-release /etc/hostname /etc/fstab /root/.ssh/authorized_keys /usr/local/sbin/uke-audio-up.sh /etc/systemd/system/uke-audio.service /lib/firmware/fs19xx.fsm"
case "$mode" in
--check)
	[ "$(rssh findmnt -no SOURCE / 2>/dev/null)" = "$DEV" ] || die "el rootfs no es $DEV (o sin SSH)"
	T=$(rssh "tune2fs -l $DEV 2>/dev/null"); bc=$(echo "$T" | awk -F: '/^Block count/{gsub(/ /,"",$2);print $2}'); bs=$(echo "$T" | awk -F: '/^Block size/{gsub(/ /,"",$2);print $2}')
	[ -n "$bc" ] && [ -n "$bs" ] || die "no se pudo leer tune2fs"
	bytes=$((bc * bs)); say "fs: $bc bloques x $bs B = $bytes B ($((bytes / 1048576)) MiB); estado: $(echo "$T" | awk -F: '/Filesystem state/{gsub(/^ +/,"",$2);print $2}')"
	say "particion: $(rssh "blockdev --getsize64 $DEV") B; usado: $(rssh "df -B1 / | awk 'NR==2{print \$3}'") B; bateria: $(rssh 'cat /sys/class/power_supply/qcom-battmgr-bat/voltage_now /sys/class/power_supply/qcom-battmgr-bat/status' | tr '\n' ' ')"
	mkdir -p "$DEST"; free=$(df -B1 --output=avail "$DEST" | tail -1); need=$((bytes * 2 + 2147483648)); say "espacio libre en el PC: $free B (necesario ≈ $need B para .img + .zst)"
	[ "$free" -gt "$need" ] && say "OK: hay espacio" || say "FALTA ESPACIO";;
--go)
	[ "$(rssh findmnt -no SOURCE / 2>/dev/null)" = "$DEV" ] || die "el rootfs no es $DEV"
	bat=$(rssh cat /sys/class/power_supply/qcom-battmgr-bat/voltage_now); [ "${bat:-0}" -ge 3700000 ] || die "bateria baja (${bat} uV; hace falta >= 3700000)"
	T=$(rssh "tune2fs -l $DEV 2>/dev/null"); bc=$(echo "$T" | awk -F: '/^Block count/{gsub(/ /,"",$2);print $2}'); bs=$(echo "$T" | awk -F: '/^Block size/{gsub(/ /,"",$2);print $2}')
	bytes=$((bc * bs)); [ $((bytes % 4194304)) = 0 ] || die "tamano del fs no multiplo de 4 MiB: $bytes"
	mkdir -p "$DEST"; free=$(df -B1 --output=avail "$DEST" | tail -1); [ "$free" -gt $((bytes * 2 + 2147483648)) ] || die "espacio insuficiente en $DEST"
	ts=$(date +%Y%m%d-%H%M%S); Z="$DEST/userdata-$ts.img.zst"; say "copiando $bytes B de $DEV (≈ 10-15 min por USB/RNDIS) → $Z"
	rssh sync
	rssh "dd if=$DEV bs=4M count=$((bytes / 4194304)) status=none | tee >(sha256sum | cut -c1-64 > /root/ud-backup.sha256) " \
		| tee >(sha256sum | cut -c1-64 > "$DEST/.pc-sha-$ts") | zstd -T0 -3 -q -o "$Z" || die "fallo la copia"
	sleep 2; rsha=$(rssh cat /root/ud-backup.sha256); psha=$(cat "$DEST/.pc-sha-$ts")
	[ "$rsha" = "$psha" ] || die "sha256 de la transferencia NO coincide (tablet $rsha / PC $psha)"
	say "transferencia íntegra: sha256 del flujo crudo = $psha"; echo "$psha  userdata-$ts.img (flujo crudo de $DEV, $bytes B)" > "$DEST/userdata-$ts.img.sha256"
	zstd -d -q -o "$DEST/userdata-$ts.img" "$Z" || die "no descomprime"; [ "$(sha256sum "$DEST/userdata-$ts.img" | cut -c1-64)" = "$psha" ] || die "la imagen descomprimida no tiene el sha del flujo"
	say "imagen cruda: $DEST/userdata-$ts.img (sha verificado). Siguiente: $0 --verify $DEST/userdata-$ts.img";;
--verify)
	IMG=${2:-}; [ -f "$IMG" ] || die "uso: $0 --verify IMG"
	say "e2fsck -fn (solo lectura; el fs estaba montado: se admiten avisos de 'not clean')"; e2fsck -fn "$IMG"; echo "e2fsck rc=$? (0 limpio, 4 errores sin corregir)"
	dumpe2fs -h "$IMG" 2>/dev/null | grep -E "Filesystem (UUID|state|features)|Block count|Block size|Free blocks" 
	say "ficheros centinela (debugfs -R cat) del IMG:"; for f in $SENT; do n=$(debugfs -R "cat $f" "$IMG" 2>/dev/null | wc -c); printf '   %-52s %s B\n' "$f" "$n"; done
	T=$(mktemp -d -p "$DEST"); trap 'rm -rf "$T"' EXIT
	img2simg "$IMG" "$T/u.simg" && simg2img "$T/u.simg" "$T/u.raw" && [ "$(sha256sum "$IMG" | cut -c1-64)" = "$(sha256sum "$T/u.raw" | cut -c1-64)" ] && say "ida y vuelta sparse: sha IGUAL (flash sparse equivalente)" || say "FALLA la ida y vuelta sparse"
	say "tamano IMG $(stat -c %s "$IMG") B vs particion userdata 113657229312 B → cabe";;
--repair)
	IMG=${2:-}; [ -f "$IMG" ] || die "uso: $0 --repair IMG"; OUTI="${IMG%.img}-fsck.img"; say "copia de $IMG a $OUTI y e2fsck -fy SOLO sobre la copia"; cp --sparse=always "$IMG" "$OUTI" || die cp
	e2fsck -fy "$OUTI"; echo "e2fsck rc=$? (0 limpio, 1 corregido)"; e2fsck -fn "$OUTI" > /dev/null && say "segunda pasada LIMPIA" || say "AUN HAY ERRORES"
	psha=$(sha256sum "$OUTI" | cut -c1-64); echo "$psha  $(basename "$OUTI") (copia reparada con e2fsck -fy desde $(basename "$IMG"), $(stat -c %s "$OUTI") B)" > "$OUTI.sha256"; say "imagen reparada: $OUTI sha256 $psha";;
--restore-plan)
	IMG=${2:-IMG}; cat <<PLAN
# VUELTA A LINUX (manual del dueño en fastboot; filas del ledger pre-registradas antes; NO ejecutar sin esas filas):
sha256sum $IMG                         # debe coincidir con $IMG.sha256
img2simg $IMG /var/tmp/userdata.simg   # (o flashear el raw: fastboot lo trocea)
fastboot getvar slot-retry-count:a ; fastboot getvar current-slot ; fastboot getvar battery-voltage   # >= 3700 mV
fastboot flash userdata /var/tmp/userdata.simg      # ~35-60 s; esperar OKAY
fastboot --set-active=a      # (doble: a, b, a si hace falta; LV-R7)
fastboot reboot
# post: SSH 192.168.42.129; misc a ceros si Android dejo bootonce-bootloader (build/misc-zeros-4m.img, ciclo aparte); ritual adsp.b40; uke-audio/uke-bt/uke-wifi
PLAN
	;;
*) sed -n 2,13p "$0"; exit 1;;
esac
