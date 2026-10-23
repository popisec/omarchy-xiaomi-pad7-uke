#!/bin/bash
# flash-pantalla.sh — ciclo PANTALLA: 1 escritura (solo boot_a), luego reboot y captura.
#
# QUÉ HACE Y QUÉ NO (heredado del ciclo K24, flash-k24.sh):
#   - UNA sola escritura: `boot_a`. El dtbo NO se toca (nunca `dtbo_a`: este
#     ciclo no lleva overlay y un flash de dtbo sin gate `fdtoverlay` wedgea el
#     arranque; REGLAS.md §1.1). El par bueno vive en slot b como referencia.
#   - El artefacto es el REPACK del kernel PANTALLA (ver build-pantalla.sh).
#   - NO hace `set_active` salvo que se le pase --set-active: en este
#     bootloader `set_active` INCREMENTA el retry del slot (medido), y no hace
#     falta para flashear un slot inactivo.
#
# USO:
#   docs/historia/gates-palawan/flash-pantalla.sh --dry-run     # solo gates, no escribe
#   docs/historia/gates-palawan/flash-pantalla.sh                # flashea boot_a y rebootea
#   PANTALLA_IMG=/ruta/a/boot-xxx.img docs/historia/gates-palawan/flash-pantalla.sh --dry-run
set -u
R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
IMG=${PANTALLA_IMG:-$R/build/bootimg/boot-ukepantalla.img}
DRY=0
SETA=0
for a in "$@"; do
	case "$a" in
	--dry-run)    DRY=1 ;;
	--set-active) SETA=1 ;;
	*) echo "arg desconocido: $a"; exit 2 ;;
	esac
done
say() { echo "[$(date +%H:%M:%S)] $*"; }
die() { say "ABORT: $*"; exit 1; }

# ---------------- GATES ANTES DE ESCRIBIR NADA ----------------
say "=== GATES (sin escrituras todavia) ==="
[ -f "$IMG" ] || die "no existe el artefacto $IMG (falta el build o el repack)"
say "OK  artefacto presente: $(stat -c%s "$IMG") B"
sha=$(sha256sum "$IMG" | cut -d' ' -f1)
say "    sha256 = $sha"
[ "$sha" = "$(sha256sum "$IMG" | cut -d' ' -f1)" ] || die "sha inconsistente"

timeout 30 fastboot devices | grep -q fastboot || die "la tablet NO esta en fastboot"
say "OK  la tablet esta en fastboot"

# OJO: `fastboot getvar` escribe en STDERR, y la ultima linea de la salida es
# "Finished. Total time: 0.004s" cuyo numero se pegaba al del voltaje al hacer
# grep -E sobre todo el stream. Se coge SOLO la linea que empieza por la clave.
bat=$(timeout 30 fastboot getvar battery-voltage 2>&1 | grep -m1 '^battery-voltage:' | sed 's/^[^:]*: *//' | tr -d '\r[:space:]')
[ -n "$bat" ] || die "no pude leer battery-voltage"
case "$bat" in
	*[!0-9]*) die "battery-voltage no es un entero: '$bat' (parseo roto, no lo comparo)" ;;
esac
say "    bateria = $bat mV"
[ "$bat" -ge 3700 ] || die "bateria $bat < 3700 mV (gate docs/historia/AGENTS.md)"
say "OK  bateria >= 3700 mV"

# estado de slots ANTES (para poder comparar despues)
say "    slots ANTES:"
timeout 30 fastboot getvar all 2>&1 | grep -E 'current-slot|slot-unbootable|slot-retry-count' | sed 's/^/      /'

if [ "$DRY" = 1 ]; then
	say "=== DRY-RUN: gates superados, NO se ha escrito nada ==="
	exit 0
fi

# ---------------- LA UNICA ESCRITURA ----------------
# POR QUÉ solo boot_a y nunca dtbo_a: el cambio de este ciclo viaja en el
# kernel/DT empaquetado en el boot.img; el dtbo del slot se queda como está
# (un `flash dtbo_a` sin gate fdtoverlay previo es vía de wedgeo, REGLAS.md
# §1.1, y no hay overlay que flashear en este ciclo).
say "=== la escritura: flash boot_a (la UNICA; dtbo_a no se toca) ==="
timeout 300 fastboot flash boot_a "$IMG" 2>&1 | tail -2 || die "fallo el flash"
say "OK  boot_a escrito"

if [ "$SETA" = 1 ]; then
	say "=== set_active a (ojo: INCREMENTA el retry en este bootloader) ==="
	timeout 60 fastboot set_active a 2>&1 | tail -1
fi

say "    slots DESPUES del flash:"
timeout 30 fastboot getvar all 2>&1 | grep -E 'current-slot|slot-unbootable|slot-retry-count' | sed 's/^/      /'

say "=== ARMANDO lector ACM antes de rebootear (regla: nunca arrancar sin lector) ==="
setsid nohup bash "$R/build/gates/uke-consola-lector.sh" start >/dev/null 2>&1 < /dev/null &
disown || true
sleep 3
bash "$R/build/gates/uke-consola-lector.sh" status 2>&1 | head -1 | sed 's/^/  /'

say "=== reboot ==="
timeout 60 fastboot reboot 2>&1 | tail -1
say "DONE FLASH-PANTALLA-OK (sha $sha)"
