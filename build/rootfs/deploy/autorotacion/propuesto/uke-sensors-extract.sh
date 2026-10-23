#!/bin/bash
# uke-sensors-extract.sh — SOLO LECTURA. Saca de Android (particiones de la tablet) lo que necesita el PD de sensores.
# Ejecutar EN LA TABLET como root (o via ssh). Produce /root/uke-sensors-android.tar.gz. No escribe en ninguna particion.
#   odm_b   (EROFS dentro de `super`)  -> /odm/etc/sensors/config/*      (json.lst primero: sin el, el PD se rinde)
#   vendor_b(EROFS dentro de `super`)  -> /vendor/etc/sensors/sns_reg_config, /vendor/dsp/adsp/sns_tppe.so
#   persist (ext4, /dev/disk/by-partlabel/persist) -> /sensors/ (via debugfs rdump, sin montar: no hay journal replay)
# Los offsets salen de `lpdump` sobre las primeras 4 MiB de super (18-oct-2026): odm_b sector 2048, vendor_b sector 12400640.
set -Eeuo pipefail
SUP=/dev/disk/by-partlabel/super; W=$(mktemp -d /root/sensx.XXXXXX); O=$W/out
cleanup() { for m in odm vendor; do umount "$W/$m" 2>/dev/null || true; done; losetup -j "$SUP" -O NAME -n 2>/dev/null | xargs -r losetup -d || true; rm -rf "$W"; }
trap cleanup EXIT
mkdir -p "$W/odm" "$W/vendor" "$O/odm/etc/sensors" "$O/vendor/etc/sensors" "$O/vendor/dsp/adsp" "$O/persist"
mnt() {   # nombre sector_inicio sectores
	local dev magic
	magic=$(dd if=$SUP bs=512 skip=$(($2 + 2)) count=1 2>/dev/null | od -An -tx1 -N4 | tr -d ' ')
	[ "$magic" = e2e1f5e0 ] || { echo "$1: no es EROFS ($magic)"; exit 1; }
	dev=$(losetup -r -f --show -o $(($2 * 512)) --sizelimit $(($3 * 512)) $SUP)
	mount -t erofs -o ro "$dev" "$W/$1"
}
mnt odm 2048 2336448
mnt vendor 12400640 2397256
cp -a "$W/odm/etc/sensors/config" "$O/odm/etc/sensors/config"
cp -a "$W/vendor/etc/sensors/sns_reg_config" "$O/vendor/etc/sensors/"
cp -a "$W/vendor/dsp/adsp/sns_tppe.so" "$O/vendor/dsp/adsp/" 2>/dev/null || echo "aviso: sin sns_tppe.so"
debugfs -R "rdump /sensors $O/persist" /dev/disk/by-partlabel/persist 2>/dev/null
[ -f "$O/odm/etc/sensors/config/json.lst" ] || { echo "FALTA json.lst"; exit 1; }
tar -C "$O" --owner=0 --group=0 -czf /root/uke-sensors-android.tar.gz .
find "$O" -type f | wc -l
sha256sum /root/uke-sensors-android.tar.gz
