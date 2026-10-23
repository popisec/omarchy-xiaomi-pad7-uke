#!/bin/sh
# check-session-b.sh — gate PREVIO a la primera escritura de la sesión F5 (grupo B).
# Se ejecuta en el PC (no toca la tablet salvo lecturas fastboot/SSH).
# Imprime checklist OK/FALLO y sale != 0 si algo falla. Nada se flashea aquí.
# Reglas que implementa: docs/historia/AGENTS.md §§Reglas, Presupuesto y las 11 lecciones del hermano.
#
# Uso:  sh build/gates/check-session-b.sh
# Requiere en el entorno: fastboot en PATH; BOOT_ARCH=path a boot-arch-uke.img (para B4;
#   si aún no existe, el gate B4 queda en FALLO explícito, que es lo correcto).

FAIL=0
BOOT_ARCH="${BOOT_ARCH:-"$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"/build/bootimg/boot-arch-uke.img}"
SHA_BUENOS=""$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"/build/gates/SHA-BUENOS.txt"
LEDGER="$HOME/proyectos/ubuntu-permanente/docs/FLASH-LEDGER.md"
ESTADO_HERMANO="$HOME/proyectos/ubuntu-permanente/docs/ESTADO-ACTUAL.md"

ok()   { echo "OK    - $1"; }
fail() { echo "FALLO - $1"; FAIL=1; }
info() { echo "INFO  - $1"; }

echo "=== GATE F5-B (pre-escritura) — $(date -u '+%Y-%m-%d %H:%M UTC') ==="

# 1. Semáforo inter-proyecto (lo verifica el OPERADOR; aquí solo se muestra dónde mirar).
#    El ledger del hermano iba por #442 con ronda en vuelo: mientras haya sesión viva, STOP.
echo "--- [1] Semáforo inter-proyecto (manual, bloqueante) ---"
echo "      Mirar EXACTAMENTE esto antes de seguir:"
echo "      a) tail -30 $LEDGER  → ¿la última entrada es un PRE-REGISTRO sin su RESULTADO?"
echo "         (una fila 'PRE-REGISTRO ... nada flasheado' abierta = ronda en vuelo = STOP)"
echo "      b) $ESTADO_HERMANO sección 'AHORA' → ¿dice 'sesión viva / no tocar'?"
echo "      c) pgrep -af 'uke-console-cap|uke-fastboot-watch|uke-wifi-trace' → ¿hay capturas ajenas corriendo?"
if tail -5 "$LEDGER" 2>/dev/null | grep -qiE 'pre-registro|ronda.*(en vuelo|en curso)|sin flashear'; then
    fail "el ledger parece tener una ronda ABIERTA (cola con PRE-REGISTRO). Leer el ledger entero y STOP."
else
    info "cola del ledger sin pre-registro abierto OBVIO; el operador DEBE confirmarlo a mano."
fi

# 2. Batería >= 3700 mV. En fastboot NO carga: con display experimental, pared obligatoria.
echo "--- [2] Batería (fastboot getvar battery-voltage) ---"
if ! command -v fastboot >/dev/null 2>&1; then
    fail "no hay 'fastboot' en PATH; no se puede medir batería ni slots."
else
    MV=$(fastboot getvar battery-voltage 2>&1 | grep -oiE '[0-9]{3,5}[ ]?m?v' | grep -oE '[0-9]+' | head -1)
    if [ -z "$MV" ]; then
        fail "no se pudo leer battery-voltage (¿tablet en fastboot? ¿cable?). Ver salida de fastboot."
    elif [ "$MV" -ge 3700 ]; then
        ok "batería ${MV} mV ≥ 3700 mV (registrar valor inicial y final en el ledger)."
    else
        fail "batería ${MV} mV < 3700 mV: hoy SOLO LECTURA, no flashear."
    fi
fi

# 3. Cargador de pared: NO verificable por software → paso manual documentado.
echo "--- [3] Cargador de pared (MANUAL, no verificable por software) ---"
info "confirmar a mano: cargador de PARED enchufado (en fastboot la tablet NO carga por USB)."

# 4. Los 4 slot-retry-count leídos y registrados.
echo "--- [4] Slots (fastboot getvar all) ---"
if command -v fastboot >/dev/null 2>&1; then
    SLOTS=$(fastboot getvar all 2>&1 | grep -i 'slot-retry-count' || true)
    echo "$SLOTS" | sed 's/^/      /'
    N=$(echo "$SLOTS" | grep -c 'slot-retry-count' || true)
    BCOUNT=$(echo "$SLOTS" | grep -i 'slot-retry-count:b' | grep -oE '[0-9]+' | tail -1)
    if [ "$N" -lt 4 ]; then
        fail "se esperaban 4 slot-retry-count, se leyeron $N."
    else
        ok "4 slot-retry-count leídos (pegarlos en la fila del ledger)."
    fi
    if [ -n "$BCOUNT" ] && [ "$BCOUNT" -lt 3 ]; then
        fail "slot-retry-count:b=$BCOUNT < 3: hoy SOLO LECTURA."
    fi
else
    fail "sin fastboot no hay lectura de slots."
fi

# 5. Partición destino POR CONTENIDO, no por letra (regla 10; R-49: dd if=<directorio> = basura).
#    Esto se verifica EN LA TABLET por SSH cuando toque B3; aquí se deja el gate exacto.
echo "--- [5] Destino userdata por contenido (gate para B3, vía SSH en su momento) ---"
cat <<'GATE'
      En la tablet, ANTES del dd, ejecutar y exigir rc=0 en las tres:
        P=/dev/disk/by-partlabel/userdata
        [ -b "$P" ] || { echo "ABORT: no existe $P"; exit 1; }
        [ -f "$P" ] && { echo "ABORT: es un fichero, no un block device (R-49)"; exit 1; }
        head -c4 "$P" | od -An -tx1 | tr -d ' \n' | grep -qi '^ef53' \
          || head -c2 "$P" | od -An -tx1 | tr -d ' \n' | grep -qi '^ef53' \
          || { echo "ABORT: magia no-ext4"; exit 1; }
      (magia ext4 = 53 ef en offset 1080; el dd se hace contra $P, NUNCA /dev/sdX por letra)
GATE
ok "gate documentado (se ejecuta en B3, no ahora)."

# 6. El boot_b a escribir, MEDIDO y pre-registrado (sha en SHA-BUENOS + fila del ledger).
echo "--- [6] boot-arch-uke.img medido y pre-registrado (para B4) ---"
if [ -f "$BOOT_ARCH" ]; then
    sha256sum "$BOOT_ARCH"
    ok "existe $BOOT_ARCH (su sha debe estar pegado en pre-registro-ledger.md ANTES de flashear)."
else
    fail "NO existe $BOOT_ARCH (build/bootimg/ vacío): B2 y B4 bloqueados hasta que el agente de repack lo entregue."
fi
if [ -f "$SHA_BUENOS" ]; then ok "SHA-BUENOS.txt presente."; else fail "falta SHA-BUENOS.txt."; fi

# 7. Consola ACM armada, UN solo lector (dos lectores = write() bloqueados = cuelgue no registrado).
echo "--- [7] Consola ACM (un solo lector) ---"
CAP=$(pgrep -af 'uke-console-cap' || true)
N=$(echo "$CAP" | grep -c 'uke-console-cap' || true)
if [ -z "$CAP" ]; then
    fail "no hay captura ACM corriendo: armar bin/uke-console-cap.sh ANTES del flash."
elif [ "$N" -gt 1 ]; then
    fail "hay $N lectores de ACM (solo puede haber 1): matar los sobrantes."
else
    ok "un único lector ACM: $CAP"
fi
info "NO abrir minicom/cat/ttyACM0 en paralelo durante el ciclo (ni leer /dev/ttyACM0 directo)."

# 8. Vigía fastboot corriendo, apuntando al par bueno, y PAUSADO durante el flash.
echo "--- [8] Vigía fastboot (par bueno s244-bounce + s229) ---"
W=$(pgrep -af 'uke-fastboot-watch' || true)
if [ -z "$W" ]; then
    fail "uke-fastboot-watch.sh NO corre: arrancarlo apuntando al par bueno ANTES de flashear."
else
    ok "vigía corriendo: $W"
fi
if [ -f /tmp/uke-fastboot-watch.pause ]; then
    ok "/tmp/uke-fastboot-watch.pause presente (vigía pausado para el flash)."
else
    info "tocar /tmp/uke-fastboot-watch.pause JUSTO antes de flashear y borrarlo al terminar."
fi

echo "=== VEREDICTO: $([ "$FAIL" = 0 ] && echo 'TODO OK — se puede pre-registrar y flashear' || echo 'HAY FALLOS — no escribir nada') ==="
exit "$FAIL"
