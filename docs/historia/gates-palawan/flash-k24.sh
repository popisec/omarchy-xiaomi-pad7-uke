#!/bin/bash
# flash-k24.sh — ciclo K24: 1 escritura (solo boot_a), luego reboot y captura.
#
# QUÉ HACE Y QUÉ NO (decidido tras 3 rondas de auditoría, ledger #454/#455):
#   - UNA sola escritura: `boot_a`. El dtbo se QUEDA en s260 (no se toca). El
#     par bueno vive en slot b como referencia, PERO OJO: b está `unbootable`
#     desde #452 (solo se rehabilitó a) ⇒ si este ciclo quema `a`, quedan CERO
#     slots arrancables y la vuelta es power-cycle + fastboot + reflash desde
#     build/backup-par-bueno/. No hay rollback arrancable.
#   - El artefacto es un REPACK del kernel recién construido con dos tokens de
#     cmdline: `uke_gmu_shared=0` (que decide el experimento) y
#     `hung_task_panic=0` (que hace que un wedge cueste 1 reintento, no 7).
#   - NO hace `set_active` salvo que se le pase --set-active: en este bootloader
#     `set_active` INCREMENTA el retry del slot (medido), y no hace falta para
#     flashear un slot inactivo.
#
# USO:
#   docs/historia/gates-palawan/flash-k24.sh --dry-run     # solo gates, no escribe
#   docs/historia/gates-palawan/flash-k24.sh                # flashea boot_a y rebootea
set -u
R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
IMG=${K24_IMG:-$R/build/bootimg/boot-ukek24.img}
DRY=0
SETA=0
while [ $# -gt 0 ]; do
	case "$1" in
	--dry-run)    DRY=1; shift ;;
	--set-active) SETA=1; shift ;;
	--expect-sha) [ $# -ge 2 ] || { echo "--expect-sha sin valor"; exit 2; }
	              EXPECT_SHA="$2"; shift 2 ;;
	*) echo "arg desconocido: $1"; exit 2 ;;
	esac
done
say() { echo "[$(date +%H:%M:%S)] $*"; }
die() { say "ABORT: $*"; exit 1; }

# ---------------- GATES ANTES DE ESCRIBIR NADA ----------------
say "=== GATES (sin escrituras todavia) ==="
[ -f "$IMG" ] || die "no existe el artefacto $IMG (falta el build o el repack)"
SZ=$(stat -c%s "$IMG")
say "OK  artefacto presente: $SZ B"
sha=$(sha256sum "$IMG" | cut -d' ' -f1)
say "    sha256 = $sha"
# C2 (2-oct, sesion #480): el gate anterior comparaba el sha consigo mismo
# (calculado dos veces), o sea NO ERA UN GATE: no podia fallar nunca. El sha
# pre-registrado se pasa con --expect-sha y se compara de verdad.
EXPECT=${EXPECT_SHA:-}
[ -n "$EXPECT" ] || die "falta --expect-sha: sin el sha PRE-REGISTRADO en el ledger no hay
	forma de saber que estoy flasheando lo que cree el registro. (C2)"
[ "$sha" = "$EXPECT" ] || die "SHA QUE NO ES EL PRE-REGISTRADO
	    imagen: $sha
	    ledger: $EXPECT"

# UKE-K34 (2-oct, ledger #472): GATE DE TAMAÑO. Una imagen 28 B mas larga que la
# particion hace que el bootloader responda `Error flashing partition : 0000000B`
# y deja `boot_a` CON EL CONTENIDO ANTERIOR: parece un flash OK y en realidad no
# se escribio nada. Pasa cuando se parchea la cmdline a mano sobre una imagen ya
# empaquetada. Se compara contra `partition-size:boot_a` del propio fastboot.
PSZ=$(timeout 30 fastboot getvar partition-size:boot_a 2>&1 \
      | grep -m1 'partition-size:boot_a' | sed 's/.*: *//' | tr -d '\r[:space:]')
case "$PSZ" in
	0x*) PSZ=$((PSZ)) ;;
	'')  die "no pude leer partition-size:boot_a (sin gate de tamano)" ;;
	*[!0-9]*) die "partition-size ilegible: '$PSZ'" ;;
esac
say "    particion boot_a = $PSZ B"
[ "$SZ" = "$PSZ" ] || die "LA IMAGEN MIDE $SZ B Y LA PARTICION $PSZ B: el bootloader
	rechazaria el flash y boot_a se quedaria con el contenido anterior. Recorta a
	$PSZ B (solo pad) antes de nada."

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
say "=== la escritura: flash boot_a ==="
# C2 (2-oct, sesion #480): con `| tail -2 || die` el codigo de salida que se
# comprueba es el de `tail`, que SIEMPRE vale 0: un `FAILED` del bootloader pasaba
# y el script seguia diciendo "OK boot_a escrito". Eso es exactamente como una
# imagen 28 B mayor llego a "escrita" sin haberse escrito (#472). Ahora se mira
# la salida de verdad.
FBOUT=$(timeout 300 fastboot flash boot_a "$IMG" 2>&1); FBRC=$?
printf '%s\n' "$FBOUT" | tail -2 | sed 's/^/  /'
[ "$FBRC" -eq 0 ] || die "fastboot flash fallo (rc=$FBRC); boot_a conserva el contenido anterior:
$(printf '%s' "$FBOUT" | tail -3)"
case "$FBOUT" in
	*OKAY*) : ;;
	*) die "fastboot no devolvio OKAY; boot_a conserva el contenido anterior:
$(printf '%s' "$FBOUT" | tail -3)" ;;
esac
say "OK  boot_a escrito (fastboot confirmo OKAY)"

if [ "$SETA" = 1 ]; then
	say "=== set_active a (ojo: INCREMENTA el retry en este bootloader) ==="
	timeout 60 fastboot set_active a 2>&1 | tail -1
fi

say "    slots DESPUES del flash:"
timeout 30 fastboot getvar all 2>&1 | grep -E 'current-slot|slot-unbootable|slot-retry-count' | sed 's/^/      /'

say "=== ARMANDO lector ACM antes de rebootear (regla: nunca arrancar sin lector) ==="
# C2 (2-oct, sesion #480): el v1 (`timeout 5 cat`) abre huecos cada 5 s y el kernel
# se bloquea escribiendo sin lector (docs/historia/AGENTS.md). Se usa el LECTOR2 (fd abierto de
# forma permanente) y se para el v1 si alguien lo dejo vivo: nunca puede haber dos.
bash "$R/build/gates/uke-consola-lector.sh" --stop >/dev/null 2>&1
bash "$R/build/gates/uke-consola-lector2.sh" >/dev/null 2>&1
sleep 2
bash "$R/build/gates/uke-consola-lector2.sh" --status 2>&1 | head -1 | sed 's/^/  /'

say "=== reboot ==="
timeout 60 fastboot reboot 2>&1 | tail -1
say "DONE FLASH-K24-OK (sha $sha)"