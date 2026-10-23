#!/bin/bash
# flash-fix529.sh — ciclo #530: boot de validación fix529 (boot_a = boot-uke-fix529,
# dtbo_a = s268), con userdata OPCIONAL (FLASH_USERDATA=1) y set_active a.
#
# QUÉ HACE:
#   - Gate de artefactos: boot y sha vienen POR ENTORNO (FIX_BOOT/FIX_BOOT_SHA,
#     obligatorios — nada de defaults); dtbo s268 fijo dentro (sha pre-registrado).
#   - Gate de tamaño contra partition-size del propio fastboot (lección #472:
#     boot_a EXACTO; dtbo_a/userdata <= partición).
#   - Gate de batería >= 3700 mV (requisito impreso siempre; sin exención:
#     el dueño lanza cuando la batería esté — no hay --exenta en este ciclo).
#   - userdata SOLO si FLASH_USERDATA=1: escribe /var/tmp/rootfs-uke-k521.img
#     (rootfs v8: fw + módulos + servicio adsp) con sha check. Si no, NO SE TOCA.
#   - set_active a al final de las escrituras.
#   - Tras el flash: lector2 armado ANTES del reboot (nunca arrancar sin lector).
#
# USO:
#   FIX_BOOT=.../boot-uke-fix529.img FIX_BOOT_SHA=1f1f8703… ./flash-fix529.sh --dry-run
#   FIX_BOOT=.../boot-uke-fix529.img FIX_BOOT_SHA=1f1f8703… ./flash-fix529.sh                 # flashea boot+dtbo
#   FIX_BOOT=... FIX_BOOT_SHA=... FLASH_USERDATA=1 ./flash-fix529.sh                          # + userdata (rootfs v8)
#
# REQUISITO DE BATERÍA: >= 3700 mV (getvar battery-voltage). El script imprime
# el requisito en cada pasada y ABORTA si no se cumple.
#
# NUNCA lo ejecuta un agente: lo lanza el dueño con la tablet en fastboot.
set -u
R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
BOOT="${FIX_BOOT:-}"
BOOT_SHA="${FIX_BOOT_SHA:-}"
DTBO="$R/build/bootimg/s268-boot-dtbo-validation.img"
DTBO_SHA="f2dede80e7452fd084420f841aae5f419e45d8d33a3ce0037e95e36df674c44b"
ROOTFS="/var/tmp/rootfs-uke-k521.img"
ROOTFS_SHA="bd2b30294aee99897ca7e86cb4843317cdf545ee08f1694aac1bc3ccf101899c"
DRY=0; WANT_USERDATA="${FLASH_USERDATA:-0}"
case "$WANT_USERDATA" in 0|1) : ;; *) echo "ABORT: FLASH_USERDATA='$WANT_USERDATA' invalido (solo 0 o 1)"; exit 2 ;; esac
SERIAL="SERIE0001"
FB="fastboot -s $SERIAL"
while [ $# -gt 0 ]; do
	case "$1" in
	--dry-run) DRY=1; shift ;;
	*) echo "arg desconocido: $1"; exit 2 ;;
	esac
done
say() { echo "[$(date +%H:%M:%S)] $*"; }
die() { say "ABORT: $*"; exit 1; }

say "=== GATES (sin escrituras todavia) ==="
[ -n "$BOOT" ] || die "FIX_BOOT no definido (export FIX_BOOT=/ruta/boot-uke-fix529.img)"
[ -n "$BOOT_SHA" ] || die "FIX_BOOT_SHA no definido (export FIX_BOOT_SHA=<sha256 del boot>)"
[ "$BOOT_SHA" = "1f1f8703147d99467e4f7d1ee3e657af4512eb7f36c2e2d58bbbd3d8e89c33d6" ] \
	|| die "FIX_BOOT_SHA no es el boot fix529 del ledger #530 (¿me pasas otro boot?)
	esperado: 1f1f8703147d99467e4f7d1ee3e657af4512eb7f36c2e2d58bbbd3d8e89c33d6"
if [ "$WANT_USERDATA" = 1 ]; then
	for f in "$BOOT" "$DTBO" "$ROOTFS"; do [ -f "$f" ] || die "no existe $f"; done
else
	for f in "$BOOT" "$DTBO"; do [ -f "$f" ] || die "no existe $f"; done
	say "    userdata NO se flashea (FLASH_USERDATA!=1); /var/tmp/rootfs-uke-k521.img queda intacto"
fi
for f in "$BOOT:$BOOT_SHA:boot" "$DTBO:$DTBO_SHA:dtbo-s268"; do
	img=${f%%:*}; resto=${f#*:}; want=${resto%%:*}; etiq=${resto##*:}
	got=$(sha256sum "$img" | cut -d' ' -f1)
	say "    $etiq sha = $got"
	[ "$got" = "$want" ] || die "SHA de $etiq NO es el pre-registrado (#530)
		imagen: $got
		ledger: $want"
done
if [ "$WANT_USERDATA" = 1 ]; then
	got=$(sha256sum "$ROOTFS" | cut -d' ' -f1)
	say "    userdata(rootfs v8) sha = $got"
	[ "$got" = "$ROOTFS_SHA" ] || die "SHA del rootfs v8 NO es el pre-registrado: $got vs $ROOTFS_SHA"
fi
say "OK  shas pre-registrados"

timeout 30 fastboot devices | grep -q "^$SERIAL[[:space:]].*fastboot" \
	|| die "la tablet $SERIAL NO esta en fastboot (¿otro aparato conectado? revise 'fastboot devices')"
say "OK  tablet en fastboot"

# tamaño de particiones vs artefactos (lección #472: rechazo silencioso)
sz_boot=$(stat -c%s "$BOOT"); sz_dtbo=$(stat -c%s "$DTBO")
psz_boot=$(timeout 30 $FB getvar partition-size:boot_a 2>&1 \
      | grep -m1 "partition-size:boot_a" | sed 's/.*: *//' | tr -d '\r[:space:]')
psz_dtbo=$(timeout 30 $FB getvar partition-size:dtbo_a 2>&1 \
      | grep -m1 "partition-size:dtbo_a" | sed 's/.*: *//' | tr -d '\r[:space:]')
case "$psz_boot" in 0x*) psz_boot=$((psz_boot)) ;; esac
case "$psz_dtbo" in 0x*) psz_dtbo=$((psz_dtbo)) ;; esac
[ -n "$psz_boot" ] && [ -n "$psz_dtbo" ] || die "no pude leer partition-size (boot_a/dtbo_a)"
say "    boot_a: imagen $sz_boot B / particion $psz_boot B"
say "    dtbo_a: imagen $sz_dtbo B / particion $psz_dtbo B"
[ "$sz_boot" = "$psz_boot" ] || die "boot_a: la imagen ($sz_boot B) != particion ($psz_boot B)"
[ "$sz_dtbo" -le "$psz_dtbo" ] || die "dtbo_a: la imagen ($sz_dtbo B) > particion ($psz_dtbo B)"
if [ "$WANT_USERDATA" = 1 ]; then
	sz_ud=$(stat -c%s "$ROOTFS")
	psz_ud=$(timeout 30 $FB getvar partition-size:userdata 2>&1 \
	      | grep -m1 "partition-size:userdata" | sed 's/.*: *//' | tr -d '\r[:space:]')
	case "$psz_ud" in 0x*) psz_ud=$((psz_ud)) ;; esac
	[ -n "$psz_ud" ] || die "no pude leer partition-size:userdata"
	say "    userdata: imagen $sz_ud B / particion $psz_ud B"
	[ "$sz_ud" -le "$psz_ud" ] || die "userdata: la imagen ($sz_ud B) > particion ($psz_ud B)"
fi
say "OK  tamaños"

# REQUISITO: bateria >= 3700 mV para flashear (se imprime SIEMPRE)
say "    REQUISITO: batería >= 3700 mV (fastboot getvar battery-voltage)"
bat=$(timeout 30 $FB getvar battery-voltage 2>&1 | grep -m1 '^battery-voltage:' | sed 's/^[^:]*: *//' | tr -d '\r[:space:]')
case "$bat" in *[!0-9]*|'') die "battery-voltage ilegible: '$bat'" ;; esac
say "    bateria = $bat mV"
[ "$bat" -ge 3700 ] || die "bateria $bat < 3700 mV: cargar la tablet y reintentar"

say "    slots ANTES:"
timeout 30 $FB getvar all 2>&1 | grep -E 'current-slot|slot-unbootable|slot-retry-count' | sed 's/^/      /'

if [ "$DRY" = 1 ]; then
	say "=== DRY-RUN: gates superados, NO se ha escrito nada ==="
	say "    (escrituras que haria: boot_a + dtbo_a$( [ "$WANT_USERDATA" = 1 ] && echo ' + userdata' ) + set_active a + reboot)"
	exit 0
fi

say "=== escrituras: boot_a + dtbo_a$( [ "$WANT_USERDATA" = 1 ] && echo ' + userdata' ) ==="
flash_one() { # $1 particion  $2 imagen
	out=$(timeout 300 $FB flash "$1" "$2" 2>&1); rc=$?
	printf '%s\n' "$out" | tail -2 | sed 's/^/  /'
	[ "$rc" -eq 0 ] || die "fastboot flash $1 fallo (rc=$rc); $1 conserva el contenido anterior"
	case "$out" in *OKAY*) : ;; *) die "sin OKAY en $1; conserva el contenido anterior" ;; esac
	say "OK  $1 escrito"
}
flash_one boot_a "$BOOT"
flash_one dtbo_a "$DTBO"
[ "$WANT_USERDATA" = 1 ] && { say "    userdata: ~30-40 s (4,3 GB) — el OKAY manda, no el reloj (#472)"; flash_one userdata "$ROOTFS"; }

say "=== set_active a ==="
out=$(timeout 60 $FB set_active a 2>&1); rc=$?
printf '%s\n' "$out" | tail -2 | sed 's/^/  /'
[ "$rc" -eq 0 ] || die "set_active a fallo (rc=$rc)"

say "    slots DESPUES:"
timeout 30 $FB getvar all 2>&1 | grep -E 'current-slot|slot-unbootable|slot-retry-count' | sed 's/^/      /'

say "=== ARMANDO lector2 antes del reboot ==="
bash "$R/build/gates/uke-consola-lector2.sh" --stop >/dev/null 2>&1
bash "$R/build/gates/uke-consola-lector2.sh" >/dev/null 2>&1
sleep 2
bash "$R/build/gates/uke-consola-lector2.sh" --status 2>&1 | head -1 | sed 's/^/  /'

say "=== reboot ==="
timeout 60 $FB reboot 2>&1 | tail -1
say "DONE FLASH-FIX529-OK — validación: pantalla (panel o82), táctil 2136x3200 evtest," \
   "ADSP/charger_pd, WiFi/BT (fw en rootfs v8), hub clk por ssh (debugfs clk_summary):" \
   "sin token cmdline CM3 (no existe mecanismo; el hub se lee por ssh)"
