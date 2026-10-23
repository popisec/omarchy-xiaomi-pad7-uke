#!/usr/bin/env bash
# flash-k23b.sh — pone el K23b en la tablet y verifica. Todo con gates, sin suposiciones.
#
# QUÉ ES ESTO. El K23b = el K23 con el volcado del CM3 corregido (geometría del
# ID1, decode de S2CR/SMR correcto, ioremap ceñido al recurso del DT, 8
# descriptores de la tabla de cada CB y pr_flush tras S3-rst0). NO cambia el modo
# de la GPU ni su tabla: sigue siendo instrumentación. El fix de verdad (K24)
# espera a leer la tabla de CB1.
#
# POR QUÉ UN SCRIPT Y NO COMANDOS SUELTOS. El proyecto tiene ~450 filas de
# ledger y la mitad de los ciclos perdidos fueron gates saltados: la verificación
# por sha de la lectura vuelta es lo que distingue "escribí" de "está escrito",
# y el reintento sin leer mV drena la batería en fastboot.
#
# REGLAS QUE RESPETA (REGLAS.md):
#   - nada de escrituras sin sha pre-registrado (aquí está, en el propio script);
#   - batería ≥ 3700 mV leída ANTES (en fastboot no carga);
#   - slot-retry-count de los 4 contadores leídos antes y después;
#   - relectura por sha256 AL TAMAÑO EXACTO de la imagen (96 MiB), que anula el pad;
#   - slot B intacto = rollback; todo se hace en A;
#   - reinicio limpio CONFIRMADO, no "reboot enviado".
#
# USO (la tablet la pone el dueño en fastboot con las teclas):
#   docs/historia/gates-palawan/flash-k23b.sh            # ejecuta
#   docs/historia/gates-palawan/flash-k23b.sh --dry-run  # solo gates, no escribe
set -euo pipefail

R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
IMG=$R/build/bootimg/boot-ukek23b.img
IMG_SHA=c31f098fe834bf852ee891dc0875a38b693375627bcf6ff028058ec99cd7b6d5
SIZE=100663296
TMP=${TMPDIR:-/tmp}/uke-k23b-$(date +%s)
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

say()  { printf '\n== %s\n' "$*"; }
ok()   { printf '   OK  %s\n' "$*"; }
die()  { printf '\n*** ABORT: %s ***\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- gates previos
say "G0 — artefacto"
[ -f "$IMG" ] || die "no existe $IMG"
s=$(sha256sum "$IMG" | cut -d' ' -f1)
[ "$s" = "$IMG_SHA" ] || die "sha del .img = $s, el pre-registrado es $IMG_SHA"
sz=$(stat -c%s "$IMG")
[ "$sz" = "$SIZE" ] || die "el .img mide $sz, no $SIZE"
ok "sha $s"
ok "tamaño $sz B (96 MiB exactos)"

say "G1 — la tablet está en fastboot y con batería"
fastboot devices | grep -q . || die "no hay ningun dispositivo en fastboot (¿teclas power+vol-) o el cable USB no enumera; el cable de datos, no de carga)"
fastboot devices | sed 's/^/   /'
batt=$(fastboot getvar battery-voltage 2>&1 | tr -d '\r' | grep -oE '[0-9]{3,5}' | head -1)
[ -n "$batt" ] || die "fastboot no devuelve battery-voltage (o no es numerico): SIN mV no se toca nada (regla 1.2). Texto crudo:
$(fastboot getvar battery-voltage 2>&1 | sed 's/^/     /')"
printf '   bateria: %s mV\n' "$batt"
[ "$batt" -ge 3700 ] || die "bateria $batt mV < 3700: en fastboot no carga. Cargador de pared + set_active b + arrancar el par estable y esperar (ver docs/historia/PLAN-SIGUIENTE-v4.md §5)"

say "G2 — estado de slots ANTES"
fastboot getvar all > "$TMP-getvar-antes.txt" 2>&1 || true
grep -E 'slot-count|current-slot|slot-retry-count|snapshot-update-status' "$TMP-getvar-antes.txt" | sed 's/^/   /' || true
if [ "$DRY" = 1 ]; then say "dry-run: no se escribe nada"; exit 0; fi

say "G3 — escritura de boot_a"
fastboot flash boot_a "$IMG" || die "fastboot flash fallo (ver getvar)"

say "G4 — relectura y verificacion por sha (al tamano exacto, anula el pad)"
fastboot fetch boot_a "$TMP-readback.img" >/dev/null 2>&1 \
  || die "este fastboot no pudo hacer 'fetch' de boot_a: NO se puede verificar la escritura, no sigas"
rsz=$(stat -c%s "$TMP-readback.img")
[ "$rsz" = "$SIZE" ] || die "la relectura mide $rsz, no $SIZE"
rs=$(dd if="$TMP-readback.img" bs=1M count=96 status=none | sha256sum | cut -d' ' -f1)
echo "   sha leido de la tablet: $rs"
echo "   sha pre-registrado    : $IMG_SHA"
if [ "$rs" = "$IMG_SHA" ]; then
  ok "COINCIDE"
else
  echo "   *** MISMATCH ***" >&2
  echo "   Reintento 1: re-dd y relectura" >&2
  fastboot flash boot_a "$IMG" || die "segundo flash fallo"
  fastboot fetch boot_a "$TMP-readback2.img" >/dev/null 2>&1 || true
  rs2=$(dd if="$TMP-readback2.img" bs=1M count=96 status=none 2>/dev/null | sha256sum | cut -d' ' -f1)
  [ "$rs2" = "$IMG_SHA" ] || die "2o mismatch ($rs2): el canal de escritura falla. NO reinicies: deja la tablet en fastboot y avisa. El slot b sigue intacto y es el rollback (set_active b)."
  ok "COINCIDE tras el reintento"
fi

say "G5 — activar el slot a y reinicio limpio"
fastboot set_active a || die "set_active a fallo"
ok "slot a activo"
# En fastboot no hay 'systemctl reboot': el reinicio sale de aqui. Aun asi, el
# fallo #P49 (un reboot que se anuncia y no ocurre) se evita CONFIRMANDO que la
# maquina cae y vuelve, no confiando en el comando.
fastboot reboot || die "fastboot reboot fallo: la tablet sigue en fastboot, no la desconectes"
echo "   reboot LANZADO. Falta lo importante: confirmar que la maquina CAE y VUELVE."
echo "   Vigia recomendado (con pausa mientrasobservation):"
echo "     touch /tmp/uke-fastboot-watch.pause"
echo "     setsid nohup bash build/gates/uke-fastboot-watch-k16.sh >/dev/null 2>&1 &"
echo "   Y el poll de SSH en paralelo (el zombi llega a ~280-400 s):"
echo "     until build/gates/uke-ssh.sh 'echo ok'; do sleep 3; done"

say "que mirar en el arranque (arbol de 6 ramas, docs/historia/RUNBOOK-SIGUIENTE.md Paso 3)"
cat <<'EOF'
   build/gates/uke-ssh.sh 'dmesg -n 7; dmesg > /dev/shm/dm.txt; cat /dev/shm/dm.txt' \
     | tee build/logs/k23b-arranque-full.log
   grep -aE "GEO ID0=|SME\(|CBpage|S3-rst0|S4-poll|H8-cm3|H9-hfiq|H10-hfi|K21 completo" \
     build/logs/k23b-arranque-full.log

   Lo que DECIDE (y es lo nuevo):
   - la linea GEO debe decir pgshift=12 NUMPAGENDXB=4 numpage=32 numcb=22
     CBbase=0x20000 CBfin=0x36000.  Si el ID1 real NO coincide, mi inferencia
     estaba mal: el propio volcado lo dice (y eso tambien es un resultado).
   - SME(1) debe salir como type=0=TRANS cbndx=1  (NO "type=1").
   - CBpage(1) off=0x21000 es LA linea: SCTLR, TTBR0 y el descriptor L[4]
     (el que cubre el icache@0x4000). De ahi sale el fix K24.
   - el desenlace de la escalera sigue siendo B (S4-pollFAIL) salvo sorpresa:
     este kernel no arregla el CM3.
EOF

say "SI ALGO SALE MAL"
cat <<'EOF'
   - la tablet cae a fastboot (slot a agotado): fastboot set_active b && fastboot reboot
     -> vuelve el par estable K13-dsid+s260, que NO se toca.
   - no arranca y no hay consola: casi siempre es el zombi (fs sin journal). No
     rebotar a lo loco: guardar la evidencia, y luego e2fsck (RUNBOOK Paso 4).
   - rollback completo: fastboot set_active b; solo si B se hubiera pisado
     (no deberia) fastboot flash boot_b build/backup-par-bueno/boot-ukek13-dsid.img
EOF
rm -f "$TMP-readback".img
printf '\nFLASH-K23B-OK  (boot_a = K23b %s)\n' "$IMG_SHA"
