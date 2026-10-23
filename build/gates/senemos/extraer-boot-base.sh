#!/usr/bin/env bash
# extraer-boot-base.sh — saca el `boot.img` base del aparato y comprueba su sha.
#
# POR QUE NO ESTA EL FICHERO EN EL REPO. El `boot.img` de la particion `boot`
# de la tablet es material del fabricante: la politica del proyecto (ver el
# README, "Que NO hay") es no redistribuirlo, y la CI lo bloquea. Lo que si se
# publica es COMO sacarlo y SHA con el que comprobarlo.
#
# QUE HACE.
#   1. Entra en fastboot (el cable USB en modo fastboot, con la pantalla de
#      "Fastboot" o `adb reboot bootloader`).
#   2. `fastboot fetch boot` -> la particion `boot` del slot activo, tal cual.
#   3. Comprueba el sha256 contra el esperado (el del artefacto que uso el
#      proyecto) y avisa si no coincide.
#
# USO:
#   bash build/gates/senemos/extraer-boot-base.sh [--out FICHERO] [--slot a|b]
#
# NOTA. El fichero que el proyecto usa como base del repack es
# "boot-s240-mem2g.img": es la particion `boot` con el kernel de memoria
# ajustada (2G) que el port modifico. Sacarlo de la tablet da el `boot` de
# Android ORIGINAL, que es el punto de partida, no el intermedio. El
# intermedio se genera con los scripts de repack del port.
set -Eeuo pipefail

R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
OUT="$R/build/bootimg/boot-base.img"
SLOT=""
# sha256 esperado del boot.img base (el que usa el port como punto de partida)
WANT="${UKE_BOOT_BASE_SHA:-e3c60969269c0b36f23a37db5b1772128891232517c8d7979bd967b88acab206}"

while [ $# -gt 0 ]; do
	case "$1" in
	--out) OUT="$2"; shift 2 ;;
	--slot) SLOT="$2"; shift 2 ;;
	*) echo "uso: $0 [--out FICHERO] [--slot a|b]" >&2; exit 2 ;;
	esac
done

say() { printf '[extraer-boot] %s\n' "$*"; }
command -v fastboot >/dev/null || { say "falta fastboot (android-tools)"; exit 1; }
fastboot devices | grep -q . || { say "no hay ningun aparato en fastboot"; exit 1; }

mkdir -p "$(dirname "$OUT")"
if [ -n "$SLOT" ]; then
	say "sacando la particion boot del slot $SLOT"
	fastboot --slot "$SLOT" fetch boot "$OUT"
else
	say "sacando la particion boot del slot activo"
	fastboot fetch boot "$OUT"
fi

GOT=$(sha256sum "$OUT" | cut -d' ' -f1)
say "sha256 del fichero extraido: $GOT"
if [ "$GOT" = "$WANT" ]; then
	say "OK: es el boot.img que espera el repack del port"
else
	say "QUE ESPERAR: el repack del port (build/gates/repack-senemos-v7.py) usa el"
	say "  intermedio 'boot-s240-mem2g.img' (el boot con el kernel de memoria"
	say "  ajustada a 2G), con sha256:"
	say "    $WANT"
	say "  El fichero que sale de 'fastboot fetch boot' es el boot ORIGINAL de"
	say "  Android, que NO es ese: el intermedio se genera con los scripts del"
	say "  port (charge/ y build/gates/). Ver build/gates/repack-senemos-v7.py."
fi
say "fichero en $OUT ($(stat -c%s "$OUT") bytes)"
say "siguiente: reempaquetar con build/gates/repack-senemos-v7.py"
