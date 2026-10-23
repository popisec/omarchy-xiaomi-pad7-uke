#!/usr/bin/env bash
# diag-f1a.sh — VEREDICTO DE F1a (render/GLES sin display) cuando haya tablet.
#
# QUE RECOGE (criterio de "hecho" del plan F, F1a):
#   ls -l /dev/dri/renderD128                    -> tiene que EXISTIR (sin card0: esperado)
#   eglinfo -B | grep -A2 "OpenGL ES profile"    -> vendor "freedreno"
#   eglinfo --display surfaceless -B             -> GLES 3.2 aunque sea surfaceless
#   dmesg | grep -c "no IOMMU"                   -> 1 es NORMAL (aborta KMS, no la GPU)
#   y sobre todo: el probe llega a "ready" y sobrevive 300 s, SIN cuelgue del CM3.
# OJO: el criterio es eglinfo, NO la existencia del nodo. Un renderD128 sin
# eglinfo -> freedreno es un F1a FALLIDO (leccion del hermano: master DRM a medias).
#
# REGLAS DEL PROYECTO (docs/historia/AGENTS.md), aplicadas aqui:
#   - `dmesg -n 7` ANTES de buscar nada (los UKE-CM3DBG son KERN_INFO nivel 6 y con el
#     nivel por defecto se concluye "no hay evidencia" en vez de "fallo").
#   - DOBLE CAPTURA obligatoria: consola ACM + `ssh ... 'dmesg -w' > fichero`. La consola
#     a 115200 PIERDE la cola cuando el reset la corta (falso "sin errores" #428->#429).
#   - `sync` antes de cualquier sysrq/reboot; /tmp es tmpfs (evidencia a /root + copia
#     local); NADA de flash/dd/fastboot en este script: es SOLO LECTURA + el trigger en
#     caliente ya documentado. Si el CM3 cuelga, la tablet puede reiniciarse sola.
#
# USO:  ./diag-f1a.sh [user@host] [dir-salida]
#       por defecto root@192.168.42.129 y ./out-f1a-<fecha>.
# REQUIERE: el dtbo s252 ya flasheado en dtbo_b (arranque sano esperado: SIN /dev/dri,
#   SIN msm_dpu, SIN ae01000) y, para el trigger, el clon s245 del hermano copiado a
#   /root/s245-cm3-clon.dtbo en la tablet. Este script NO inyecta el overlay: lo verifica
#   y recoge el veredicto. El trigger en caliente lo hace uke-cm3-test.sh del hermano.
#
# STRINGS DECISIVOS que busca (cada uno con su significado):
#   "UKE-CM3DBG: dtcm-magic"   firmware del GMU cargado en TCM (magic 0x40050001 esperado)
#   "UKE-POKE: S3-rst0"        se solto el reset del CM3 (el trigger llego)
#   "UKE-POKE: S4-poll"        el primer readl VOLVIO: el CM3 NO cuelga (=> H3, no H1)
#   "GMU firmware initialization timed out"  el fallo UPSTREAM (con mensaje, -ETIMEDOUT):
#                              categoria DISTINTA de nuestro hang mudo
#   "[drm] Initialized msm"    DRM registrado (G2-initOK del 24-sep)
#   "no IOMMU, bailing out"    1 es NORMAL con s252 (aborta KMS, no la GPU); 0 con el
#                              clon bindeado seria raro; >1 indica master reaparecido
set -u
H="${1:-root@192.168.42.129}"
OUT="${2:-./out-f1a-$(date +%Y%m%d-%H%M%S)}"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"

mkdir -p "$OUT"
FALLOS=0
nota() { echo "[f1a] $*"; echo "[f1a] $*" >> "$OUT/f1a-veredicto.log"; }
falla() { echo "[f1a-FALLO] $*"; echo "[f1a-FALLO] $*" >> "$OUT/f1a-veredicto.log"; FALLOS=$((FALLOS+1)); }
pasa() { echo "[f1a-OK] $*"; echo "[f1a-OK] $*" >> "$OUT/f1a-veredicto.log"; }

nota "destino=$H salida=$OUT inicio=$(date -u +%FT%TZ)"
nota "REQUISITO: captura de consola ACM armada ANTES de empezar (bin/uke-console-cap.sh"
nota "del hermano). Este script arranca ADEMAS la captura gemela por SSH (doble captura)."

# --- paso 0: captura gemela dmesg -w a fichero (fondo) ---
$SSH "$H" 'dmesg -w' > "$OUT/f1a-dmesg-ssh.log" 2>"$OUT/f1a-ssh-err.log" &
CAP_PID=$!
sleep 2
if ! kill -0 $CAP_PID 2>/dev/null; then
  falla "sin SSH a $H: no hay evidencia posible. ABORTO"
  exit 2
fi
nota "captura gemela dmesg -w en marcha (pid $CAP_PID)"

# --- paso 1: dmesg -n 7 ANTES de buscar nada ---
$SSH "$H" 'dmesg -n 7; cat /proc/sys/kernel/printk' > "$OUT/f1a-printk.log" 2>/dev/null \
  || falla "no se pudo poner dmesg -n 7"
nota "printk tras dmesg -n 7: $(cat "$OUT/f1a-printk.log" 2>/dev/null | tr '\n' ' ')"

# --- paso 2: estado de partida (arranque sano con s252?) ---
$SSH "$H" 'ls -l /dev/dri/ 2>&1; echo ---; ls /sys/bus/platform/devices/ | grep -E "ae01000|apps-smmu|kgsl" 2>&1; echo ---; cat /sys/module/msm/parameters/separate_gpu_kms 2>&1; echo ---; cat /sys/kernel/config/device-tree/overlays/cm3clon/status 2>&1; echo ---; ls -d /sys/bus/platform/drivers/adreno/*clon* 2>&1; echo ---; uptime' > "$OUT/f1a-estado.log" 2>/dev/null \
  || falla "no se pudo leer el estado"
cat "$OUT/f1a-estado.log"
if grep -q "ae01000" "$OUT/f1a-estado.log"; then
  falla "ae01000 presente: el master DRM NO esta deshabilitado (s252 no activo?)"
else
  pasa "ae01000 ausente: master DRM deshabilitado (s252 activo)"
fi

# --- paso 3: /dev/dri ---
if $SSH "$H" 'test -c /dev/dri/renderD128' 2>/dev/null; then
  pasa "/dev/dri/renderD128 existe"
else
  falla "/dev/dri/renderD128 NO existe (F1a no arrancado: falta el trigger en caliente?)"
fi
if $SSH "$H" 'test -e /dev/dri/card0' 2>/dev/null; then
  nota "card0 existe: hay KMS (inesperado con s252; anotarlo, no es fallo F1a)"
else
  nota "sin card0: lo esperado con s252 (render-only)"
fi

# --- paso 4: eglinfo (EL criterio) ---
for modo in "-B" "--display surfaceless -B"; do
  tag=$(echo "$modo" | tr ' ' '_')
  $SSH "$H" "timeout 30 eglinfo $modo 2>&1" > "$OUT/f1a-eglinfo$tag.log" 2>/dev/null
  if grep -q -i "freedreno" "$OUT/f1a-eglinfo$tag.log"; then
    pasa "eglinfo $modo -> freedreno"
  else
    falla "eglinfo $modo NO reporta freedreno (ver $OUT/f1a-eglinfo$tag.log)"
  fi
done
grep -h -A2 "OpenGL ES profile" "$OUT"/f1a-eglinfo*.log | head -8

# --- paso 5: prueba de render (la primera que exista; si no hay ninguna, se dice) ---
$SSH "$H" 'for b in glmark2-es2 es2_info es2gears_x11 kmscube glxgears; do command -v $b 2>/dev/null && echo FOUND:$b; done; echo FIN' > "$OUT/f1a-render-bins.log" 2>/dev/null
RENDER_BIN=$($SSH "$H" 'command -v glmark2-es2 || command -v kmscube || command -v es2_info || true' 2>/dev/null)
if [ -n "$RENDER_BIN" ]; then
  nota "prueba de render con $RENDER_BIN (timeout 90)"
  $SSH "$H" "timeout 90 $RENDER_BIN 2>&1 | head -40" > "$OUT/f1a-render.log" 2>/dev/null
  RRC=$?
  nota "render rc=$RRC (0 = dibujo OK). Primeras lineas:"
  head -12 "$OUT/f1a-render.log"
  [ "$RRC" -eq 0 ] && pasa "render de prueba rc=0" || falla "render de prueba rc=$RRC"
else
  falla "sin binario de render en la tablet (ni glmark2-es2 ni kmscube ni es2_info): F1a sin cierre"
fi

# --- paso 6: CM3 (los strings decisivos, sobre el delta capturado por SSH) ---
sleep 2
$SSH "$H" 'dmesg' > "$OUT/f1a-dmesg-final.log" 2>/dev/null
{
  echo "--- UKE-CM3DBG / UKE-POKE S* ---"
  grep -a -E "UKE-CM3DBG|UKE-POKE: (S[0-9]|G[0-9]|H[0-9]|F[0-9]|P[0-9])" "$OUT/f1a-dmesg-final.log" | tail -30
  echo "--- DRM / GMU / IOMMU ---"
  grep -a -c "no IOMMU, bailing out" "$OUT/f1a-dmesg-final.log"
  grep -a -E "Initialized msm|GMU firmware initialization timed out|Loaded GMU firmware|dpu_kms_destroy|Internal error|adreno.*bind|3d61000" "$OUT/f1a-dmesg-final.log" | tail -15
} > "$OUT/f1a-cm3.log" 2>/dev/null
cat "$OUT/f1a-cm3.log"
if grep -q "UKE-POKE: S3-rst0" "$OUT/f1a-dmesg-final.log" 2>/dev/null; then
  pasa "S3-rst0 visto: el trigger solto el reset del CM3"
  if grep -q "UKE-POKE: S4-poll" "$OUT/f1a-dmesg-final.log" 2>/dev/null; then
    pasa "S4-poll visto: el primer readl VOLVIO (H1 refutada en este arranque; via H3)"
  else
    falla "S3-rst0 SIN S4-poll: CM3 cuelga en el primer readl (H1 confirmada; sin GLES)"
  fi
else
  falla "sin S3-rst0: el trigger NO llego al CM3 (mirar bind/deferred, no concluir del CM3)"
fi
if grep -q "GMU firmware initialization timed out" "$OUT/f1a-dmesg-final.log" 2>/dev/null; then
  nota "timeout UPSTREAM con mensaje: categoria distinta del hang mudo (anotarlo aparte)"
fi

# --- paso 7: cierre ---
kill $CAP_PID 2>/dev/null
$SSH "$H" 'sync' 2>/dev/null
nota "captura gemela detenida; sync remoto hecho. Uptime final:"
$SSH "$H" 'uptime' 2>/dev/null | tee -a "$OUT/f1a-veredicto.log"
nota "FALLOS=$FALLOS (0 = F1a VERDE salvo la supervivencia de 300 s, que se re-mide aparte)"
nota "Evidencia en $OUT: f1a-dmesg-ssh.log (gemela) + f1a-dmesg-final.log + eglinfo + render + cm3."
exit $FALLOS
