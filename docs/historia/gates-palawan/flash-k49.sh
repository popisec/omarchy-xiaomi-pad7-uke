#!/bin/bash
# flash-k49.sh — ciclo #509: DOS escrituras (boot_a = K49, dtbo_a = s266), reboot y captura.
#
# QUÉ HACE:
#   - Gate de artefactos con shas PRE-REGISTRADOS (ledger #509-bis).
#   - Gate de tamaño contra partition-size del propio fastboot (lección #472).
#   - Gate de batería ≥3700 mV SALVO --exenta-bateria (exención del dueño,
#     ledger #508: "flashea da igual la bateria"; re-confirmada implícitamente
#     al mantener el ciclo #509 en marcha).
#   - UNA variable lógica: el par kernel+dtbo de paridad ESD del vendor.
#   - Tras el flash: lector2 armado ANTES del reboot (regla: nunca arrancar sin lector).
#
# USO:
#   docs/historia/gates-palawan/flash-k49.sh --dry-run            # solo gates, no escribe
#   docs/historia/gates-palawan/flash-k49.sh --exenta-bateria     # flashea y rebootea
set -u
R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
BOOT="${K49_BOOT:-$R/build/bootimg/boot-ukek49-esd.img}"
DTBO="$R/build/bootimg/s266-boot-dtbo-esd.img"
BOOT_SHA="${K49_BOOT_SHA:-d4b96f952957bda508bd23cd89e8e56510e3ad4fafc41da01092b8567a9bbc17}"
DTBO_SHA="15fdbbd3d265c393baac69c2e19884fe72417e6c304692db3fafacc8fdc7d695"
DRY=0; EXENTA=0
while [ $# -gt 0 ]; do
	case "$1" in
	--dry-run)         DRY=1; shift ;;
	--exenta-bateria)  EXENTA=1; shift ;;
	*) echo "arg desconocido: $1"; exit 2 ;;
	esac
done
say() { echo "[$(date +%H:%M:%S)] $*"; }
die() { say "ABORT: $*"; exit 1; }

say "=== GATES (sin escrituras todavia) ==="
for f in "$BOOT" "$DTBO"; do
	[ -f "$f" ] || die "no existe $f"
done
for f in "$BOOT:$BOOT_SHA:boot" "$DTBO:$DTBO_SHA:dtbo"; do
	img=${f%%:*}; resto=${f#*:}; want=${resto%%:*}; etiq=${resto##*:}
	got=$(sha256sum "$img" | cut -d' ' -f1)
	say "    $etiq sha = $got"
	[ "$got" = "$want" ] || die "SHA de $etiq NO es el pre-registrado (#509-bis)
		imagen: $got
		ledger: $want"
done
say "OK  shas pre-registrados"

timeout 30 fastboot devices | grep -q fastboot || die "la tablet NO esta en fastboot"
say "OK  tablet en fastboot"

# tamaño de particiones vs artefactos (lección #472: rechazo silencioso)
for par in boot_a dtbo_a; do
	case "$par" in
	boot_a) img=$BOOT ;;
	dtbo_a) img=$DTBO ;;
	esac
	sz=$(stat -c%s "$img")
	psz=$(timeout 30 fastboot getvar partition-size:$par 2>&1 \
	      | grep -m1 "partition-size:$par" | sed 's/.*: *//' | tr -d '\r[:space:]')
	case "$psz" in 0x*) psz=$((psz)) ;; esac
	[ -n "$psz" ] || die "no pude leer partition-size:$par"
	say "    $par: imagen $sz B / particion $psz B"
	# #472: boot_a exige tamaño EXACTO (el bootloader rechaza y calla si es mayor);
	# dtbo_a admite imágenes menores (s262 de 608801 B ya flasheó OK a 25165824 B).
	if [ "$par" = boot_a ]; then
		[ "$sz" = "$psz" ] || die "$par: la imagen ($sz B) != particion ($psz B)"
	else
		[ "$sz" -le "$psz" ] || die "$par: la imagen ($sz B) > particion ($psz B)"
	fi
done
say "OK  tamaños exactos"

bat=$(timeout 30 fastboot getvar battery-voltage 2>&1 | grep -m1 '^battery-voltage:' | sed 's/^[^:]*: *//' | tr -d '\r[:space:]')
case "$bat" in *[!0-9]*|'') die "battery-voltage ilegible: '$bat'" ;; esac
say "    bateria = $bat mV"
if [ "$EXENTA" = 1 ]; then
	say "    EXENTA (ledger #508: orden del dueño)"
else
	[ "$bat" -ge 3700 ] || die "bateria $bat < 3700 mV (usa --exenta-bateria si el dueño lo re-confirma)"
fi

say "    slots ANTES:"
timeout 30 fastboot getvar all 2>&1 | grep -E 'current-slot|slot-unbootable|slot-retry-count' | sed 's/^/      /'

if [ "$DRY" = 1 ]; then
	say "=== DRY-RUN: gates superados, NO se ha escrito nada ==="
	exit 0
fi

say "=== escrituras: boot_a + dtbo_a ==="
for par in boot_a dtbo_a; do
	case "$par" in
	boot_a) img=$BOOT ;;
	dtbo_a) img=$DTBO ;;
	esac
	out=$(timeout 300 fastboot flash "$par" "$img" 2>&1); rc=$?
	printf '%s\n' "$out" | tail -2 | sed 's/^/  /'
	[ "$rc" -eq 0 ] || die "fastboot flash $par fallo (rc=$rc); $par conserva el contenido anterior"
	case "$out" in *OKAY*) : ;; *) die "sin OKAY en $par; conserva el contenido anterior" ;; esac
	say "OK  $par escrito"
done

say "    slots DESPUES:"
timeout 30 fastboot getvar all 2>&1 | grep -E 'current-slot|slot-unbootable|slot-retry-count' | sed 's/^/      /'

say "=== ARMANDO lector2 antes del reboot ==="
bash "$R/build/gates/uke-consola-lector2.sh" --stop >/dev/null 2>&1
bash "$R/build/gates/uke-consola-lector2.sh" >/dev/null 2>&1
sleep 2
bash "$R/build/gates/uke-consola-lector2.sh" --status 2>&1 | head -1 | sed 's/^/  /'

say "=== reboot ==="
timeout 60 fastboot reboot 2>&1 | tail -1
say "DONE FLASH-K49-OK — tras arrancar: fsck-flujo (EXT4 sucio) + leer uke-cazador.log (P219)"
