#!/usr/bin/env bash
# auto-flash-s234.sh — espera a que la tablet entre en fastboot y entonces flashea s234 en dtbo_b.
#
# POR QUE ESTO EXISTE. La tablet arranca por boot.img de Android (ABL -> boot -> initramfs) y NO
# tiene EFI (medido: /sys/firmware/efi vacio), ni android_usb, ni sysfs que acepte un motivo de
# reinicio. O sea: no hay forma de pedir "reboot to bootloader" desde userspace. El power cycle
# (Power+Vol-) es fisico y no se puede automatizar. Lo unico automatizable es todo lo que viene
# DESPUES, y eso es justo donde estan los gates que importan.
#
# QUE HACE, EN ORDEN, Y ABORTA EN CADA GATE:
#   1. espera a que aparezca el dispositivo fastboot (con timeout, y reintenta si se va)
#   2. lee battery-voltage y los 4 slot-retry-count  -> sin voltage suficiente, NO flashea
#   3. verifica que el sha de la imagen es el pre-registrado  -> si no, NO flashea
#   4. fastboot flash dtbo_b  (imagen CRUDA; una sparse NO borra la particion)
#   5. fastboot reboot
# Deja log en /tmp/opencode/autoflash-s234.log y el sha leido en .sha para poder auditarlo.
set -u
LOG=/tmp/opencode/autoflash-s234.log
IMG="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"/build/bootimg/s234-boot-dtbo-l8b-path.img
ESPERADO=2a28e4b1651b10b6d750c1624f9db446c12663d62c0f025d1e7eda76b4e97115
DEADLINE=$(( $(date +%s) + 3600 ))   # 1 hora de margen

log() { printf '[%s] %s\n' "$(date +%T)" "$*" | tee -a "$LOG"; }

log "=== vigilante armado para $IMG"
log "    sha esperado: $ESPERADO"
log "   Deadline: $(date -d @"$DEADLINE" +%T 2>/dev/null || echo '3600 s')"

# ---------- gate 3 (offline): el sha de la imagen, antes de esperar nada ----------
SHA_LOCAL=$(sha256sum "$IMG" 2>/dev/null | cut -d' ' -f1)
if [ "$SHA_LOCAL" != "$ESPERADO" ]; then
  log "ABORTO: sha local $SHA_LOCAL != esperado. NO se toca la tablet."
  exit 1
fi
log "gate 3 OK: sha local coincide con el pre-registrado"

# ---------- 1. esperar fastboot ----------
VISTO=0
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  if fastboot devices 2>/dev/null | grep -q fastboot; then
    VISTO=$((VISTO+1))
    log "fastboot detectado (vez $VISTO), espero 6 s a que se estabilice"
    sleep 6
    fastboot devices 2>/dev/null | grep -q fastboot || { log "se fue otra vez, sigo esperando"; sleep 10; continue; }
    break
  fi
  sleep 5
done

if [ "$(date +%s)" -ge "$DEADLINE" ]; then
  log "TIMEOUT: no aparecio fastboot en el plazo. No se ha escrito nada."
  exit 2
fi

# ---------- 2. gates de voltaje y slots ----------
log "--- leyendo estado del bootloader ---"
ST=$(fastboot getvar all 2>&1)
MV=$(echo "$ST" | grep -i "battery-voltage" | head -1 | sed 's/.*: *//')
SLOT=$(echo "$ST" | grep -i "current-slot" | head -1 | sed 's/.*: *//')
log "battery-voltage: ${MV:-?} mV"
log "current-slot   : ${SLOT:-?}"
echo "$ST" | grep -iE "slot-retry-count|slot-unbootable" | while read -r l; do log "  $l"; done

# sin numero de voltaje NO se flashea: el budget de >=3700 mV es del proyecto
if ! printf '%s' "${MV:-x}" | grep -qE '^[0-9]+$'; then
  log "ABORTO: battery-voltage no es un numero ('${MV:-}'). NO se toca la tablet."
  exit 3
fi
if [ "$MV" -lt 3700 ]; then
  log "ABORTO: $MV mV < 3700 mV. NO se toca la tablet."
  exit 3
fi
log "gate 2 OK: $MV mV >= 3700"

# ---------- 3. sha de la imagen, de nuevo ----------
SHA=$(sha256sum "$IMG" | cut -d' ' -f1)
[ "$SHA" = "$ESPERADO" ] || { log "ABORTO: sha cambio a $SHA"; exit 1; }
log "gate 3 OK otra vez: sha verificado justo antes de escribir"

# ---------- 4. el flash ----------
log "--- fastboot flash dtbo_b (cruda, un solo destino) ---"
fastboot flash dtbo_b "$IMG" 2>&1 | tr '\r' '\n' | tail -4 | while read -r l; do log "  $l"; done
RC=${PIPESTATUS[0]}
if [ "${RC:-1}" != "0" ]; then
  log "ABORTO: fastboot devolvio rc=$RC. La particion puede estar a medias; NO reiniciar."
  exit 4
fi
log "flash OK (rc=0)"

# ---------- 5. verificacion post-escritura y reinicio ----------
log "--- estado de slots tras la escritura ---"
fastboot getvar all 2>&1 | grep -iE "slot-retry-count|slot-unbootable" | while read -r l; do log "  $l"; done
log "--- limpiar el estado unbootable ANTES de reiniciar (MEDIDO: sin esto el ABL cuenta"
log "    reintentos, marca el slot unbootable y luego ya no hay vuelta con 'fastboot reboot':"
log "    'slot-unbootable:b: yes' + continue -> 'Failed to load image from partition') ---"
fastboot set_active "$SLOT" 2>&1 | tail -1 | while read -r l; do log "  set_active $SLOT: $l"; done
fastboot getvar all 2>&1 | grep -iE "slot-unbootable|slot-retry-count" | while read -r l; do log "  $l"; done
log "--- reinicio ---"
fastboot reboot 2>&1 | tail -1 | while read -r l; do log "  $l"; done
log "=== hecho. rollout: ahora esperar consola + red y medir /dev/dri, /dev/fb0 ==="
