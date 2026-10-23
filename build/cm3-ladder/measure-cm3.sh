#!/bin/bash
# Medicion del cuelgue CM3 con la escalera UKE-CM3. NO flashea, NO hace dd.
# Se corre en el PC contra la tablet por SSH. El trigger es en caliente
# (resume del GPU por runtime PM): gasta CERO reintentos de slot.
#
# Orden obligatorio (lecciones del proyecto hermano):
#   1. dmesg -n 7 en la tablet ANTES de nada (ronda 36: sin esto los
#      printk de nivel 6 no se ven y se concluye "sin evidencia" en falso)
#   2. DOBLE CAPTURA ABIERTA ANTES del trigger: consola ACM + dmesg -w a
#      fichero (ledger #428->#429: la serie a 115200 pierde la cola cuando
#      el reset la corta; el fichero por SSH sobrevive)
#   3. sync antes de cualquier reboot; y este script NO reinicia solo:
#      el watchdog del s229 NO esta arreglado (R-42): un cuelgue exige
#      reset fisico del dueno. El script espera y deja el reset a mano.
#   4. NUNCA volcar rangos MMIO/regmap en caliente (ronda 33: cuelga).
#      La unica lectura "en caliente" permitida es la que ya lleva el
#      parche dentro del camino (canario L14): instrumentar en arranque.
#
# Uso: TABLET=root@192.168.42.129 ./measure-cm3.sh [T1|T2]
#   T1 (defecto): resume por runtime PM (power/control=on en el device GPU)
#   T2: unbind/bind del driver msm (mas pesado; solo si T1 no provoco resume)
set -u
TABLET="${TABLET:-root@192.168.42.129}"
MODE="${1:-T1}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
OUTDIR="${OUTDIR:-/tmp/opencode/cm3-measure-$STAMP}"
CONSOLE_CAP="$HOME/proyectos/ubuntu-permanente/bin/uke-console-cap.sh"
DMESG_FILE="$OUTDIR/dmesg-w.log"
CONSOLE_FILE="$OUTDIR/console-acm.log"

say() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
die() { say "ABORTO: $*"; exit 1; }
ssh_t() { ssh -o BatchMode=yes -o ConnectTimeout=8 "$TABLET" "$@"; }

mkdir -p "$OUTDIR"
say "=== MEDICION CM3 $STAMP modo=$MODE tablet=$TABLET ==="

# --- Gate 0: ssh vivo ---
ssh_t true || die "sin ssh a $TABLET"
say "G0 ssh OK"

# --- Paso 1: dmesg -n 7 ANTES DE NADA ---
ssh_t 'dmesg -n 7' || die "dmesg -n 7 fallo"
say "P1 dmesg -n 7 puesto (los UKE-CM3: de nivel 6 ya son visibles)"

# --- Gate 1: firmware presente (separa el cuelgue "sin legacy" sin flash) ---
# R-57: paquete uke-gpu-firmware instalado y verificado (14 ficheros, 8 sha).
# Si falta el legacy, el fw_load se queda en el helper ~60 s por fichero:
# firma distinta (atasco ANTES de F1) del cuelgue CM3 (DESPUES de F4-verOK).
ssh_t 'ls -l /lib/firmware/gen71100_gmu.bin /lib/firmware/qcom/gen71100_gmu.bin 2>&1' \
  | tee "$OUTDIR/fw-gate.log"
ssh_t 'dmesg | grep -E "loaded .*gen71100|failed to load.*gen71100|fwloc|legacy location" | tail -n 5' \
  | tee -a "$OUTDIR/fw-gate.log"
say "G1 firmware listado (revisar $OUTDIR/fw-gate.log: si falta el legacy, parar aqui)"

# --- Gate 2: device GPU localizado + estado runtime ---
GPU_DEV="$(ssh_t 'for d in /sys/bus/platform/devices/*; do c="$d/of_node/compatible"; [ -f "$c" ] && tr "\0" " " < "$c" | grep -q "adreno" && basename "$d"; done' | head -n 1)"
[ -n "$GPU_DEV" ] || die "no se encontro el device GPU (compatible adreno) en /sys/bus/platform/devices"
say "G2 gpu=$GPU_DEV"
ssh_t "cat /sys/bus/platform/devices/$GPU_DEV/power/runtime_status 2>/dev/null || echo desconocido" \
  | tee "$OUTDIR/runtime-before.log"
ssh_t 'ls /dev/dri/ 2>&1' | tee "$OUTDIR/dri.log"

# --- Paso 2: abrir DOBLE CAPTURA ANTES del trigger ---
say "P2a abriendo dmesg -w por SSH -> $DMESG_FILE"
ssh_t 'dmesg -w' > "$DMESG_FILE" 2>"$OUTDIR/dmesg-w.err" &
DMESG_PID=$!
sleep 2
kill -0 "$DMESG_PID" 2>/dev/null || die "dmesg -w murio al arrancar ($(cat "$OUTDIR/dmesg-w.err"))"
# Gate 3: el tubo tiene que estar VIVO y NO VACIO antes del trigger.
# Se inyecta un marcador y se exige verlo en el fichero.
ssh_t 'echo UKE-CM3-MEASURE-START > /dev/kmsg'
sleep 2
grep -q "UKE-CM3-MEASURE-START" "$DMESG_FILE" \
  || die "el fichero dmesg no contiene el marcador: la captura NO esta viva"
say "G3 dmesg -w vivo y con contenido ANTES del trigger (marcador presente)"

say "P2b abriendo consola ACM -> $CONSOLE_FILE"
if [ -x "$CONSOLE_CAP" ]; then
  "$CONSOLE_CAP" > "$CONSOLE_FILE" 2>"$OUTDIR/console.err" &
  CONSOLE_PID=$!
  sleep 2
  if kill -0 "$CONSOLE_PID" 2>/dev/null; then
    say "consola ACM capturando (pid $CONSOLE_PID)"
  else
    say "AVISO: console-cap murio ($(cat "$OUTDIR/console.err" 2>/dev/null)); sigo SOLO con dmesg-w"
    CONSOLE_PID=""
  fi
else
  say "AVISO: no existe $CONSOLE_CAP; sigo SOLO con dmesg-w"
  CONSOLE_PID=""
fi

# --- Paso 3: TRIGGER (en caliente, sin flash) ---
say "P3 trigger $MODE (capturas ya abiertas)"
case "$MODE" in
  T1)
    ssh_t "echo on > /sys/bus/platform/devices/$GPU_DEV/power/control" \
      && say "control=on enviado" || say "AVISO: no se pudo escribir power/control"
    ;;
  T2)
    DRV="$(ssh_t "basename \$(readlink /sys/bus/platform/devices/$GPU_DEV/driver 2>/dev/null) 2>/dev/null || echo msm")"
    say "unbind/bind via $DRV (mas pesado que T1)"
    ssh_t "echo $GPU_DEV > /sys/bus/platform/drivers/$DRV/unbind" \
      || say "AVISO: unbind fallo"
    sleep 3
    ssh_t "echo $GPU_DEV > /sys/bus/platform/drivers/$DRV/bind" \
      || say "AVISO: bind fallo"
    ;;
  *) die "modo $MODE desconocido (T1|T2)" ;;
esac

# --- Paso 4: ventana de observacion (sin tocar nada) ---
say "P4 esperando 60 s (NO tocar la tablet; ni MMIO ni reboot)"
sleep 60
ssh_t 'dmesg | tail -n 5' > "$OUTDIR/dmesg-tail-post.log" 2>&1 \
  && say "la tablet responde a ssh tras la ventana" \
  || say "AVISO: sin ssh tras la ventana (posible cuelgue: pasar a P5)"
ssh_t "cat /sys/bus/platform/devices/$GPU_DEV/power/runtime_status 2>/dev/null" \
  > "$OUTDIR/runtime-after.log" 2>&1 || true
say "runtime antes: $(cat "$OUTDIR/runtime-before.log") despues: $(cat "$OUTDIR/runtime-after.log" 2>/dev/null)"

# --- Paso 5: cerrar capturas con sync, y decidir ---
say "P5 cerrando capturas"
kill "$DMESG_PID" 2>/dev/null; wait "$DMESG_PID" 2>/dev/null || true
[ -n "${CONSOLE_PID:-}" ] && { kill "$CONSOLE_PID" 2>/dev/null; wait "$CONSOLE_PID" 2>/dev/null || true; }
sync
say "ultimas UKE-CM3: en dmesg-w:"
grep "UKE-CM3:" "$DMESG_FILE" | tail -n 8 || say "(ninguna)"
if [ -f "$CONSOLE_FILE" ]; then
  say "ultimas UKE-CM3: en consola ACM:"
  grep "UKE-CM3:" "$CONSOLE_FILE" | tail -n 8 || say "(ninguna)"
fi

cat <<'EOF'
--- TABLA DE LECTURA (ultima linea UKE-CM3: manda) ---
PRE dtcm-magic (L10)        -> bloque GMU ilegible: power/reloj del CX (mirar
                               linea UKE-CM3DBG clks del mismo arranque)
PRE canary-init-result (L14)-> wedge al soltar el reset: el fetch del CM3 mato
                               el bus de forma sincrona (firma dependiente de fw)
PRE poll + cuelgue           -> canario OK pero el poll no avanza: CM3 a medio
                               arrancar; raro, anotar iteracion si se ve
POST poll + "timed out"      -> el BUS FUNCIONA y el CM3 no contesto:
                               firmware/chipid/power, NO stall (R-57: son dos
                               categorias distintas)
POST poll ret=0              -> el CM3 ARRANCO: el cuelgue esta despues (HFI L16
                               o fuera del GMU); no era el CM3
nada UKE-CM3: pero H1..H5 si -> el resume no llego al fw_start (antes del CM3)
nada de nada                 -> el trigger no provoco resume (runtime ya active):
                               repetir con T2, o el GPU no bindeo en este arranque
EOF
say "=== FIN (si hubo cuelgue: sync hecho; el reset fisico lo hace el dueno) ==="
