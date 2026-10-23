#!/bin/bash
# uke-pstore-read.sh — rescata el log del K23b del ramoops en la PRIMERA ventana de vida.
#
# POR QUÉ (1-oct-2026). El K23b entra en bucle de cuelga->panic->reboot cada ~34 s, y
# cada uno de esos reinicios es **caliente**, asi que la DRAM reservada no se pierde. El
# DT declara `ramoops_region` en `reg=<0x0 0xa7000000 0x0 0x400000>` (DT vendor
# reconstruido:109-121) y el fork lo registra (`pstore: Registered ramoops as persistent
# store backend`, `printk: legacy console [ramoops-1] enabled`, medido en el dmesg del
# 30-sep). O sea que **el volcado del SMMU que nos interesa ya esta escrito en DRAM**,
# sin necesidad de NOTHING: solo hay que leerlo desde un sistema vivo, y el slot b
# (K13-dsid) es estable.
#
# IMPORTANTE: **no borrar nada** de /sys/fs/pstore (leer con cat no borra; rm si).
#
# USO:  build/gates/uke-pstore-read.sh [segundos]     (default 600)
set -u
R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
SSH=$R/build/gates/uke-ssh.sh
HOST=192.168.42.129
VENTANA=${1:-600}
OUT=$R/build/logs
mkdir -p "$OUT"
say() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# Primero: que la tablet lo deje en un fichero (por si se corta la conexion al mitad).
REMOTO='mount -t pstore pstore /sys/fs/pstore 2>/dev/null; ls -la /sys/fs/pstore/ > /root/ps-ls.txt 2>&1; cat /sys/fs/pstore/* > /root/ps-dump.txt 2>&1; wc -c /root/ps-dump.txt >> /root/ps-ls.txt'
# Y en local: el volcado entero, que es lo que nos sirve.
DIRECTO='mount -t pstore pstore /sys/fs/pstore 2>/dev/null; echo "=== PSTORE LS ==="; ls -la /sys/fs/pstore/; echo "=== PSTORE DUMP (ultimos 40 KB) ==="; tail -c 40000 /sys/fs/pstore/* 2>/dev/null'

fin=$(($(date +%s) + VENTANA))
n=0
while [ "$(date +%s)" -lt "$fin" ]; do
	if timeout 1 bash -c "</dev/tcp/$HOST/22" 2>/dev/null; then
		n=$((n+1))
		say "intento $n: puerto 22 responde"
		timeout 30 "$SSH" "$REMOTO" >/dev/null 2>&1 &
		f="$OUT/pstore-$n-$(date +%H%M%S).log"
		if timeout 35 "$SSH" "$DIRECTO" > "$f" 2>&1; then
			grab=$(wc -c < "$f")
			say " _volcado de $grab B -> $(basename "$f")"
			if grep -aqE 'GEO ID0=|CBpage|S3-rst0' "$f"; then
				say "  >>> ESTA EL VOLCADO DEL K23b. FIN."
				exit 0
			fi
		else
			say "  ssh se corto (zombi)"
		fi
	else
		printf '.'
	fi
	sleep 0.3
done
say "fin de ventana; ultimo fichero: $(ls -t "$OUT"/pstore-*.log 2>/dev/null | head -1)"
exit 1
