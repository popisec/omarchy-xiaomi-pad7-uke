#!/bin/bash
# flash-userdata-l76r-gated.sh — vuelta de Android a Linux (17-oct-2026): userdata <- rootfs Arch 8 GiB
# (build/rootfs/rootfs-uke-l76-8g.img, stack de carga horneado) y despues boot_a <- L76R via
# flash-l76r-gated.sh (que repite sus gates, escribe boot_a, set_active a, reboot y mide 19 gates de
# paridad + 4 de CARGA). Pre-registro: ledger #654. Runbook: build/gates/revision/RUNBOOK-FLASH-L76R-20261017.md.
#
# ⚠️ ESCRIBIR userdata BORRA EL ANDROID ACTUAL (apps y datos de HyperOS en slot b). Para volver a Android
#    despues: fastboot erase userdata + erase metadata ANTES del primer arranque de Android (LV-R1).
# Escrituras: userdata (8 GiB, sparse por fastboot) + boot_a. NO toca dtbo_a (s288), slot b, vbmeta, super.
set -u
set -o pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")" || exit 1
ROOTFS=build/rootfs/rootfs-uke-l76-8g.img
ER=7e4309f008ad4bfcde6f9f3634f8207b5730e1b853e384a9c9dcd7b60a44a13c
[ "${CONFIRMO_BORRAR_ANDROID:-0}" = "1" ] || { echo "ABORTADO: exporta CONFIRMO_BORRAR_ANDROID=1 (userdata borra Android)"; exit 1; }
echo "== gate rootfs: sha =="
[ "$(stat -c%s "$ROOTFS")" = 8589934592 ] || { echo "ABORTADO: tamaño del rootfs inesperado"; exit 2; }
[ "$(sha256sum "$ROOTFS" | cut -d' ' -f1)" = "$ER" ] || { echo "ABORTADO: ROOTFS SHA MISMATCH"; exit 2; }
echo "== gates previos (sin escribir nada) =="
DEV=$(timeout 15 fastboot devices 2>/dev/null | head -1)
[ -n "$DEV" ] || { echo "ABORTADO: fastboot devices vacio (tablet en fastboot por USB al PC)"; exit 3; }
echo "device: $DEV"
for v in battery-voltage battery-soc-ok current-slot slot-retry-count:a slot-retry-count:b slot-unbootable:a slot-unbootable:b; do
  timeout 15 fastboot getvar "$v" 2>&1 | grep -E "^$v" | head -1
done
MV=$(timeout 15 fastboot getvar battery-voltage 2>&1 | grep -E '^battery-voltage' | grep -oE '[0-9]+' | head -1)
[ -n "${MV:-}" ] || { echo "ABORTADO: battery-voltage vacio (LV-R6: gate sin dato = no se flashea)"; exit 4; }
[ "$MV" -ge 3700 ] || { echo "ABORTADO: bateria $MV mV < 3700 (en fastboot NO carga)"; exit 4; }
LPID=/var/tmp/uke-consola-lector.pid
{ [ -f "$LPID" ] && kill -0 "$(cat "$LPID")" 2>/dev/null; } || { echo "ABORTADO: lector ACM no armado (bash build/gates/uke-consola-lector.sh)"; exit 6; }
echo "== ESCRITURA 1/2: userdata <- rootfs 8 GiB (unos minutos; fastboot lo trocea en sparse) =="
timeout 1800 fastboot flash userdata "$ROOTFS" 2>&1 | tail -4
URC=${PIPESTATUS[0]}
[ "$URC" -eq 0 ] || { echo "ABORTADO: fastboot flash userdata rc=$URC; NO se toca boot_a"; exit 7; }
echo "userdata OK"
echo "== ESCRITURA 2/2: boot_a <- L76R (flash-l76r-gated.sh, con sus propios gates) =="
exec bash docs/historia/gates-palawan/flash-l76r-gated.sh
