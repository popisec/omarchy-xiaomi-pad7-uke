#!/bin/bash
# post-flash-medir.sh — mide el resultado de F3/L24 con los CRITERIOS PRE-REGISTRADOS.
# Uso: ./post-flash-medir.sh <ruta-a-imagen> <sha-esperado>
# NO hace flash. NO hace reboot. Solo LECTURA (local + SSH).

set -uo pipefail
IMG="${1:-}"; SHA_ESP="${2:-}"
PROJ="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
KEY="$PROJ/build/rootfs/uke-arch-root"
IP=192.168.42.129
OUT=/tmp/opencode/f3-medicion
mkdir -p "$OUT"

hdr(){ echo; echo "════════════════════════════════════════════════"; echo " $*"; echo "════════════════════════════════════════════════"; }

hdr "0. VERIFICACIÓN DEL ARTEFACTO (antes de tocar nada)"
if [ -f "$IMG" ]; then
  SHA_REAL=$(sha256sum "$IMG" | cut -d' ' -f1)
  SZ=$(stat -c %s "$IMG")
  echo "fichero : $IMG"
  echo "sha     : $SHA_REAL"
  echo "esperado: ${SHA_ESP:-<sin esperado>}"
  [ -n "$SHA_ESP" ] && { [ "$SHA_REAL" = "$SHA_ESP" ] && echo "✅ SHA OK" || echo "❌ SHA MISMATCH — NO FLASHEAR"; }
  echo "tamaño  : $SZ (partición boot_a = 100663296)"
  [ "$SZ" = "100663296" ] && echo "✅ tamaño exacto" || echo "❌ tamaño incorrecto"
else
  echo "❌ imagen no encontrada"; exit 1
fi

hdr "1. ESTADO FASTBOOT (lectura)"
fastboot devices 2>&1 | sed 's/^/  /'
fastboot getvar battery-voltage 2>&1 | grep -i volt | sed 's/^/  /'
fastboot getvar all 2>&1 | grep -iE 'slot-retry-count|slot-unbootable|current-slot' | sed 's/^/  /'

hdr "2. CMDLINE DE LA IMAGEN (verificación del pre-registro)"
python3 - "$IMG" <<'PY'
import sys
d=open(sys.argv[1],'rb').read(8192)
cmd=d[44:44+2048].split(b'\x00')[0].decode('utf-8','replace')
print("  longitud:", len(cmd), "bytes")
print("  cmdline :", cmd)
print()
print("  GATE CRÍTICOS (según PRE-REGISTRO-F3-L24.md):")
checks=[("video=DSI-1:d  DEBE ESTAR AUSENTE", 'video=' not in cmd),
        ("msm.uke_skip_mdss_reset=1  DEBE ESTAR", 'msm.uke_skip_mdss_reset=1' in cmd),
        ("msm.uke_panel_inherit  DEBE ESTAR AUSENTE", 'uke_panel_inherit' not in cmd)]
for txt,ok in checks: print(f"   {'✅' if ok else '❌'} {txt}")
PY

hdr "3. MEDICIÓN EN LA TABLETA (SSH, solo lectura)"
ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=10 root@$IP '
echo "--- 3.1 ¿CORRIÓ EL PREPARE? (criterio de validez del test) ---"
N=$(dmesg | grep -c "UKE-P82")
echo "marcas UKE-P82: $N"
if [ "$N" = "0" ]; then echo "   ❌ TEST INVÁLIDO: el prepare NO corrió (no cuenta como ciclo)"; else echo "   ✅ el prepare corrió"; fi
echo
echo "--- 3.2 ¿el log de fbcon sobrevive a 0,6s y 4,1s? (criterio de éxito) ---"
dmesg | grep -E "^\[ +0\.[5-9]|^\[ +[1-9]\." | tail -5 | sed "s/^/   /"
echo "   (mirar si hay líneas DESPUÉS de 0,6 s y después de 4,1 s)"
echo
echo "--- 3.3 gpio2 (reset del panel) ---"
grep -E "^gpio2[: ]" /sys/kernel/debug/gpio 2>/dev/null | sed "s/^/   /" || echo "   gpio2 no listado"
echo
echo "--- 3.4 rails del panel (use=1 = levantados) ---"
grep -iE "l8|vsp|vsn|l19" /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | awk "{print \"   \"\$1,\$4,\$5,\$6}" || echo "   no disponible"
echo
echo "--- 3.5 PLLs del DSI ---"
grep -E "dsi.*(vco|byte|pclk)" /sys/kernel/debug/clk/clk_summary 2>/dev/null | awk "{print \"   \"\$0}" | head -6
echo
echo "--- 3.6 pureason + pstore ---"
tr " " "\n" < /proc/cmdline | grep -E "pureason|pdreason" | sed "s/^/   /"
echo "   ficheros pstore:"; ls -la /sys/fs/pstore/ 2>/dev/null | tail -n +2 | sed "s/^/   /"
echo
echo "--- 3.7 estado ---"
uptime | sed "s/^/   /"
echo "   frame_done_cnt:"; grep -H . /sys/kernel/debug/drm/*/encoder*/status 2>/dev/null | head -2 | sed "s/^/   /"
' 2>&1 | tee "$OUT/medicion-ssh.txt"

hdr "4. RESUMEN"
echo "Guardado en: $OUT/medicion-ssh.txt"
echo
echo "INTERPRETAR según la tabla de PRE-REGISTRO-F3-L24.md:"
echo "  imagen + log vivo  → BCR = asesino nº1, primer display real"
echo "  log vivo, negro    → prepare sobrevivió al BCR; el asesino está en 0,3-0,6s"
echo "  wedge / panic      → fenómeno B (muerte del SoC en el prepare)"
echo "  0 marcas UKE-P82   → TEST INVÁLIDO, no cuenta como ciclo"