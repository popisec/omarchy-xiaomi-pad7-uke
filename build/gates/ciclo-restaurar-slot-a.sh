#!/bin/sh
# ciclo-restaurar-slot-a.sh — restaura el slot A con los binarios stock + kernel UKE-POKE (F5/B1).
#
# POR QUÉ (forense en curso, ver F9 — candidata, NO causa raíz medida): cuatro arranques
# seguidos con imágenes de `boot` de nueva factura escritas en el SLOT A se quedaron mudos, y
# el slot A tiene `vendor_boot` e `init_boot` VACÍAS (todo ceros) desde que el proyecto hermano
# hizo `erase boot_a init_boot_a vendor_boot_a dtbo_a` + `erase super` el 24-sep (su ledger
# #384/#385) sin que ninguna entrada posterior (buscado hasta su #444) las restaure. Estado de
# ceros medido en la tablet por la sesión forense (96/8 MiB; NO verificado independiente en
# este repo) y `vendor_boot_b` = stock `3ee6d4ac…` (hermano #238/#273). El hermano tiene medido
# (su ledger #236 — OJO: no #336, que trata del LAST-POKE) que `vendor_boot` es LA BASE DEL
# DEVICE TREE: sin ella no hay DT, y sin DT el kernel no inicializa ni la consola (cero líneas,
# slot marcado no booteable, caída a fastboot). Esa es la forma de los 4 mudos en A. El wedge
# del s251 en el slot B (28-sep 11:52–12:03, retry 7→0) es OTRA cosa con causa medida propia
# (enlazar `apps-smmu`) y no entra en esta cuenta.
#
# RESTRICCIÓN (ledger del hermano #272, CORREGIDO por su #275 y precisado por su #278): el ABL
# rechazó el `vendor_boot` reempaquetado s140 (#272), pero el "no acepta repacks" lo corrigió el
# propio ledger como mito (#275: el s38 sin vbmeta ni footer ARRANCÓ en a y en b; regla real H3
# = la cadena DTB tiene que enlosar dtb_size por totalsize). Y aun con cadena perfecta, un árbol
# C sustituido sigue rechazado (#278: valida ALGO del contenido). Por eso NO se reconstruye ni
# se reempaqueta nada: se copia el stock tal cual, byte a byte. Cualquier transformación lo
# pondría en la zona rechazada.
#
# QUÉ HACE ESTE CICLO (dos variables a la vez: reparación + kernel nuevo, tres escrituras en el slot A):
#   1. vendor_boot_a <- stock (96 MiB, byte a byte, sin tocar)
#   2. init_boot_a   <- stock (8 MiB, byte a byte, sin tocar)
#   3. boot_a        <- boot-pokes.img (kernel instrumentado UKE-POKE, ver abajo)
# POR QUÉ boot-pokes.img EN boot_a EN ESTE CICLO: es el kernel instrumentado UKE-POKE que lleva
# el diferir del probe del SMMU de apps-smmu; este ciclo es el primero en el que ese código puede
# llegar a ejecutarse de verdad (antes el slot A estaba mudo por las particiones vacías).
# ADVERTENCIA DE MÉTODO (decisión del dueño): este ciclo cambia DOS variables a la vez
# (reparación del slot + kernel nuevo); si vuelve a quedarse mudo, NO se puede concluir
# cuál de las dos falló. Queda escrito aquí para que no se lea como control.
#
# NUNCA TOCA boot_b NI dtbo_b. Lo dice este comentario y lo comprueba la función flash_a():
# aborta si el destino no es exactamente una de las tres particiones _a de arriba. El par bueno
# (s244-bounce + s229) queda intacto como red de recuperación: si el slot A falla, basta
# `fastboot set_active b` + `fastboot reboot` para volver a Ubuntu/Arch.
#
# TODO LOCAL SALVO EL MODO REAL. Modo por defecto --dry-run: 100% local, no escribe NADA (ni en
# la tablet ni en el ledger), solo verifica fuentes+shas e informa qué haría. El modo real es
# --ejecutar y hace, EN ESTE ORDEN: lecturas getvar (batería, desbloqueo, los 4 slot-retry-count,
# unbootable, slot actual) -> verificación de los 3 shas (PARA si uno no coincide) -> pre-registro
# en build/gates/PRE-REGISTRO-F5-B1.md ANTES de la primera escritura (regla dura) -> los 3 flash
# -> relectura de getvar (coste real) -> set_active a -> reboot.
# Estilo y gates copiados de build/gates/paquete-firmware-gpu.sh (dry-run por defecto, contadores
# PASS/FAIL, rutas fuera de /tmp, sync donde aplique).
#
# PASO OPCIONAL F0 DESACTIVADO: la limpieza del BCB de `misc` se hace con el generador existente
# build/gates/bcb-clean-8192.py (ver build/gates/DECISION-misc-BCB.md). No va en este ciclo: este
# guion no escribe en misc y no ejecuta ese paso. Si el dueño lo ordena, va como ciclo aparte con
# su propia fila de ledger.
#
# Presupuesto por ciclo (docs/historia/AGENTS.md): batería >= 3700 mV para flashear; <= 2 escrituras por día
# (este ciclo trae 3: contar con el dueño); si slot-retry-count:b < 3, ese día solo lectura.
# Consola con UN SOLO LECTOR y vigía de fastboot pausado durante el flash.
# EXENCIÓN DE BATERÍA: el dueño autorizó este ciclo por debajo del gate (~3426 mV, cargador
# limitado a 100 mA). Se pasa EXPLÍCITAMENTE con --waiver-bateria (segundo argumento) o con
# CICLO_WAIVER_BATERIA=si en el entorno. Sin una de esas dos, aborta como siempre; con ella,
# no aborta pero anota el valor real y la exención en la salida y en el pre-registro.
# No hay valor por defecto que la active: WAIVER empieza vacío en cada invocación.
#
# Uso: sh build/gates/ciclo-restaurar-slot-a.sh [--dry-run|--ejecutar] [--waiver-bateria]

set -eu
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GATES="$REPO/build/gates"
BACKUP="$REPO/build/backup-par-bueno"
PRE_REG="$GATES/PRE-REGISTRO-F5-B1.md"
MODE="${1:---dry-run}"
WAIVER=""
for _a in "$@"; do
    case "$_a" in
        --waiver-bateria) WAIVER=1;;
    esac
done
# Vía entorno solo con el valor exacto "si"; cualquier otra cosa (incluido no definirla) = sin exención.
if [ "${CICLO_WAIVER_BATERIA:-}" = "si" ]; then WAIVER=1; fi
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FALLO: $1"; }
[ "$MODE" = "--dry-run" ] || [ "$MODE" = "--ejecutar" ] || { echo "uso: $0 [--dry-run|--ejecutar] [--waiver-bateria]"; exit 2; }
for _a in "$@"; do
    case "$_a" in
        --dry-run|--ejecutar|--waiver-bateria) ;;
        *) echo "uso: $0 [--dry-run|--ejecutar] [--waiver-bateria] (argumento desconocido: $_a)"; exit 2;;
    esac
done

# --- Constantes del ciclo: las tres imágenes y sus shas. El sha manda, no el fichero. ---
VENDOR_BOOT_SRC="$BACKUP/vendor_boot-stock.img"
VENDOR_BOOT_SHA="3ee6d4ac5fefc6ea9dbe9e6ed48b298762ad273f4592e3acc56e4439f096a208"
VENDOR_BOOT_SIZE=100663296
INIT_BOOT_SRC="$BACKUP/init_boot-stock.img"
INIT_BOOT_SHA="5228e6e2e5e9d903c352104738377e957e7cbd1ae67d7a3ffa97cb09cbef4a8d"
INIT_BOOT_SIZE=8388608
# Kernel de este ciclo: boot-pokes.img (instrumentado UKE-POKE, diferir del probe del SMMU
# de apps-smmu). NO es el control s244-bounce: ver ADVERTENCIA DE MÉTODO en la cabecera.
BOOT_A_SRC="$REPO/build/bootimg/boot-pokes.img"
BOOT_A_SHA="11cf34823441bec66ac41a4af2d1a09fbbfdf6fd5ba67b97ff26cccdb32c61a7"
BOOT_A_SIZE=100663296
BAT_MIN_MV=3700

echo "== ciclo-restaurar-slot-a ($MODE) =="

echo "-- gate 0: rutas fuera de /tmp y ficheros presentes --"
case "$VENDOR_BOOT_SRC $INIT_BOOT_SRC $BOOT_A_SRC $PRE_REG" in *tmp*) bad "ruta bajo /tmp"; exit 1;; *) ok "rutas fuera de /tmp";; esac
[ -f "$VENDOR_BOOT_SRC" ] || { bad "falta $VENDOR_BOOT_SRC"; exit 1; }
[ -f "$INIT_BOOT_SRC" ]   || { bad "falta $INIT_BOOT_SRC"; exit 1; }
[ -f "$BOOT_A_SRC" ]      || { bad "falta $BOOT_A_SRC"; exit 1; }
ok "las 3 imágenes presentes (fuera de git: .gitignore las ignora, el sha manda)"
[ -f "$PRE_REG" ] || { bad "falta $PRE_REG (pre-registro)"; exit 1; }
ok "fichero de pre-registro presente"

echo "-- gate 1: tamaño exacto + sha256 de los TRES artefactos (PARA si uno no coincide) --"
check_img() {
    _f="$1"; _sha="$2"; _size="$3"; _nombre="$4"
    _got_size="$(stat -c%s "$_f")"
    if [ "$_got_size" = "$_size" ]; then ok "$_nombre tamaño $_got_size B"; else bad "$_nombre tamaño DISTINTO (esperado $_size, medido $_got_size)"; return 1; fi
    _got="$(sha256sum "$_f" | cut -d' ' -f1)"
    if [ "$_got" = "$_sha" ]; then ok "$_nombre sha ✓"; else bad "$_nombre sha DISTINTO (esperado $_sha, medido $_got)"; return 1; fi
}
check_img "$VENDOR_BOOT_SRC" "$VENDOR_BOOT_SHA" "$VENDOR_BOOT_SIZE" "vendor_boot stock" || exit 1
check_img "$INIT_BOOT_SRC" "$INIT_BOOT_SHA" "$INIT_BOOT_SIZE" "init_boot stock" || exit 1
check_img "$BOOT_A_SRC" "$BOOT_A_SHA" "$BOOT_A_SIZE" "boot_a = boot-pokes.img (UKE-POKE)" || exit 1

echo "-- gate 2: el guion NUNCA toca boot_b ni dtbo_b (comprobación estática) --"
# Solo hay 3 destinos permitidos; cualquier otra línea de escritura aborta el ciclo aquí.
if grep -nE 'fastboot[[:space:]]+flash[[:space:]]+(boot_b|dtbo_b|dtbo_a|boot_b|vendor_boot_b|init_boot_b|userdata|misc|super|vbmeta)' "$0" >/dev/null; then
    bad "el guion menciona un destino prohibido (ver líneas de arriba)"
    exit 1
else
    ok "ninguna escritura a boot_b, dtbo_b ni a ninguna otra partición"
fi

# Guarda de runtime: solo deja escribir en las tres particiones _a de este ciclo.
flash_a() {
    case "$1" in
        vendor_boot_a|init_boot_a|boot_a) ;;
        *) echo "  FALLO: destino prohibido: $1 (solo *_a de este ciclo)"; exit 1;;
    esac
    fastboot flash "$1" "$2"
}

leer_getvar() {
    echo "  -- getvar ($1) --"
    echo "  battery-voltage:    $(fastboot getvar battery-voltage 2>&1 | tr -d '\r' | head -1)"
    echo "  unlocked:           $(fastboot getvar unlocked 2>&1 | tr -d '\r' | head -1)"
    echo "  current-slot:       $(fastboot getvar current-slot 2>&1 | tr -d '\r' | head -1)"
    echo "  slot-retry-count:a: $(fastboot getvar slot-retry-count:a 2>&1 | tr -d '\r' | head -1)"
    echo "  slot-retry-count:b: $(fastboot getvar slot-retry-count:b 2>&1 | tr -d '\r' | head -1)"
    echo "  slot-unbootable:a:  $(fastboot getvar slot-unbootable:a 2>&1 | tr -d '\r' | head -1)"
    echo "  slot-unbootable:b:  $(fastboot getvar slot-unbootable:b 2>&1 | tr -d '\r' | head -1)"
}

if [ "$MODE" = "--dry-run" ]; then
    echo "-- plan (dry-run: no se escribe NADA, ni en la tablet ni en el ledger) --"
    echo "  1. fastboot devices (tablet en fastboot, cargador de pared, consola con un solo lector,"
    echo "     vigía pausado: touch /tmp/uke-fastboot-watch.pause)"
    echo "  2. getvar ANTES: battery-voltage (>= $BAT_MIN_MV mV, salvo --waiver-bateria explícito),"
    echo "     unlocked (tiene que ser yes: con unlocked: yes el ABL NO impone verificación AVB,"
    echo "     o sea que los shas de las 3 imágenes bastan y no hace falta firma), current-slot,"
    echo "     slot-retry-count:a/b, slot-unbootable:a/b"
    echo "  3. re-verificar los 3 shas (gate 1 de arriba; PARA si uno no coincide)"
    echo "  4. PRE-REGISTRO en $PRE_REG ANTES de la primera escritura (regla dura)"
    echo "  5. fastboot flash vendor_boot_a $VENDOR_BOOT_SRC  (stock, $VENDOR_BOOT_SIZE B)"
    echo "  6. fastboot flash init_boot_a $INIT_BOOT_SRC  (stock, $INIT_BOOT_SIZE B)"
    echo "  7. fastboot flash boot_a $BOOT_A_SRC  (boot-pokes.img, UKE-POKE SMMU-defer)"
    echo "     waiver batería: $([ -n "$WAIVER" ] && echo "ACTIVO (exención explícita del dueño)" || echo "no (gate $BAT_MIN_MV mV en vigor)")"
    echo "     unlocked: con 'unlocked: yes' el ABL no verifica AVB; shas de la tabla bastan, sin firma"
    echo "  8. getvar DESPUÉS (los 4 retry-count: coste real del ciclo)"
    echo "  9. fastboot set_active a  (OBLIGATORIO antes de reboot; sin esto el ABL marca unbootable)"
    echo "  10. fastboot reboot  (+ rm -f del pause del vigía)"
    echo "  NO se toca en ningún paso: boot_b, dtbo_b, vendor_boot_b, init_boot_b, userdata,"
    echo "  vbmeta, misc. Rollback: fastboot set_active b + reboot (par bueno intacto)."
    echo "  Criterio de ÉXITO: el slot A arranca con consola viva (vendor_boot ya trae el DT) y el"
    echo "  código UKE-POKE del diferir del probe del SMMU puede ejecutarse por primera vez."
    echo "  Criterio de FRACASO: mudo otra vez => NO se puede distinguir si falló la reparación o el"
    echo "  kernel nuevo (dos variables en un ciclo, decisión del dueño); volver a b y"
    echo "  anotar REFUTADO al tercer ciclo sin movimiento en dmesg (doble captura: ACM + dmesg -w)."
    echo "  (dry-run: modo real = --ejecutar, NO invocado aquí)"
    echo "== resultado: $PASS ok, $FAIL fallos =="
    [ "$FAIL" -eq 0 ]
    exit 0
fi

echo "-- modo real: lecturas getvar ANTES --"
fastboot devices
leer_getvar "ANTES"
MV="$(fastboot getvar battery-voltage 2>&1 | tr -d '\r' | grep -oE '[0-9]+' | head -1)"
UNLOCK="$(fastboot getvar unlocked 2>&1 | tr -d '\r' | head -1)"
case "$UNLOCK" in *yes*) ok "unlocked: yes";; *) bad "unlocked no es yes ($UNLOCK)"; exit 1;; esac
if [ "${MV:-0}" -ge "$BAT_MIN_MV" ]; then ok "batería $MV mV >= $BAT_MIN_MV"; elif [ -n "$WAIVER" ]; then ok "batería $MV mV < $BAT_MIN_MV: EXENCIÓN EXPLÍCITA --waiver-bateria (autorizada por el dueño, cargador a 100 mA); se sigue y queda anotado"; else bad "batería $MV mV < $BAT_MIN_MV: NO se escribe (pasar --waiver-bateria explícito si el dueño lo autoriza)"; exit 1; fi
RA="$(fastboot getvar slot-retry-count:a 2>&1 | tr -d '\r' | grep -oE '[0-9]+' | head -1)"
RB="$(fastboot getvar slot-retry-count:b 2>&1 | tr -d '\r' | grep -oE '[0-9]+' | head -1)"
echo "  slot-retry-count:a=$RA b=$RB (presupuesto: <= 2 escrituras/día; si b < 3, solo lectura)"
FECHA="$(date +%Y-%m-%d\ %H:%M)"

echo "-- pre-registro ANTES de la primera escritura (regla dura) --"
cat >> "$PRE_REG" <<EOF

---

## F5-B1-RESTAURAR-SLOT-A — pre-registro ($FECHA, escrito ANTES de escribir)

**Por qué.** El slot A tiene `vendor_boot` e `init_boot` VACÍAS (ceros, medido por la sesión
forense, NO verificado independiente aquí) desde el erase del 24-sep del hermano (su ledger
#384/#385, sin restauración posterior hasta su #444); sin `vendor_boot` no hay device tree
(su ledger #236, no #336) y el kernel no inicializa ni la consola: así fueron los 4 mudos en
A (el wedge del s251 en B es otra causa, medida aparte). El ABL rechazó el repack s140 (su
ledger #272, matizado por su #275/#278): solo vale el stock byte a byte.

**Qué se escribe (slot A SOLO; boot_b y dtbo_b NO se tocan).**

| campo | valor |
|---|---|
| fila | ledger hermano **pendiente de asignar** (este proyecto no escribe en el suyo) |
| fecha | $FECHA |
| vendor_boot_a | stock, $VENDOR_BOOT_SIZE B, sha \`$VENDOR_BOOT_SHA\` |
| init_boot_a | stock, $INIT_BOOT_SIZE B, sha \`$INIT_BOOT_SHA\` |
| boot_a | **boot-pokes.img (UKE-POKE: diferir del probe del SMMU de apps-smmu)**, $BOOT_A_SIZE B, sha \`$BOOT_A_SHA\` |
| por qué pokes | primer ciclo en el que ese código puede ejecutarse de verdad; DOS variables a la vez (reparación + kernel): si queda mudo, NO se puede concluir cuál falló (decisión del dueño) |
| NO se toca | \`boot_b\`, \`dtbo_b\`, \`vendor_boot_b\`, \`init_boot_b\`, \`userdata\`, \`vbmeta\`, \`misc\` |
| orden | getvar ANTES -> 3 shas -> ESTE pre-registro -> 3 flash -> getvar DESPUÉS -> \`set_active a\` -> reboot |
| gates de entrada | battery-voltage $MV mV (>= $BAT_MIN_MV$(if [ -n "$WAIVER" ]; then echo ", EXENCIÓN EXPLÍCITA --waiver-bateria autorizada por el dueño"; fi)) · unlocked yes (ABL no verifica AVB: shas bastan, sin firma) · retry a=$RA b=$RB · shas == tabla |
| rollback | \`fastboot set_active b\` + reboot (par bueno intacto) |
| éxito | el slot A arranca con consola viva |
| fracaso | mudo otra vez => volver a b SIN concluir (reparación o kernel); al 3.er ciclo sin movimiento en dmesg, hipótesis REFUTADA |

EOF
ok "pre-registro añadido a $PRE_REG"

echo "-- modo real: los 3 flash (slot A SOLO) --"
flash_a vendor_boot_a "$VENDOR_BOOT_SRC" && ok "flash vendor_boot_a"
flash_a init_boot_a "$INIT_BOOT_SRC" && ok "flash init_boot_a"
flash_a boot_a "$BOOT_A_SRC" && ok "flash boot_a (boot-pokes.img, UKE-POKE)"

echo "-- modo real: lecturas getvar DESPUÉS (coste real) --"
leer_getvar "DESPUÉS"

echo "-- modo real: activar A y reiniciar --"
fastboot set_active a && ok "set_active a"
fastboot reboot && ok "reboot (quitar el pause del vigía: rm -f /tmp/uke-fastboot-watch.pause)"

echo "== resultado: $PASS ok, $FAIL fallos =="
[ "$FAIL" -eq 0 ]
