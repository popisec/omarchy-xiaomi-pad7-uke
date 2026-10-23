#!/usr/bin/env bash
# rescate-fastboot-pantalla.sh — vigía del PLAN-PANTALLA (F2). Arrancarlo ANTES de cualquier
# flash de dtbo. Si la tablet cae a fastboot (wedge del dtbo de prueba o contador de slot
# agotado — en fastboot NO carga), restaura dtbo_b = s238 (par bueno verificado), hace el
# baile set_active a+b (resetea el contador a 7) y reinicia. Tope: 4 acciones por episodio,
# luego se autopausa (fichero .pause) para no quemar escrituras en bucle.
#
#   pausar:  touch /tmp/rescate-pantalla.pause     reanudar: rm -f /tmp/rescate-pantalla.pause
#   log:     ~/proyectos/out/rescate-pantalla.log
#   arrancar: nohup build/gates/rescate-fastboot-pantalla.sh >/dev/null 2>&1 &  (setsid)
set -u
FB=/opt/android-sdk/platform-tools/fastboot
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
DTBO_BUENO="$ROOT/build/bootimg/s238-boot-dtbo-dedup-gpio.img"
SHA_BUENO="bdb361dff87de52dd7d4581c7f4007abdaf98ac145d47658ef2a29bc458f0022"  # verificado vs partición 28-sep (ESTADO-VIVO)
LOG="$HOME/proyectos/out/rescate-pantalla.log"
PAUSE=/tmp/rescate-pantalla.pause
ACCIONES=0

say() { echo "[$(date '+%d-%b %H:%M:%S')] $*" >> "$LOG"; }

# gate de artefacto: si el backup no es el esperado, no rescatar con algo desconocido
actual=$(sha256sum "$DTBO_BUENO" 2>/dev/null | cut -d' ' -f1)
if [ "$actual" != "$SHA_BUENO" ]; then
  say "ABORT: sha del dtbo bueno no coincide ($actual) — no arranco el vigía"
  exit 1
fi
say "vigía armado (dtbo bueno $SHA_BUENO de ${#SHA_BUENO} chars verificado)"

while true; do
  sleep 10
  [ -f "$PAUSE" ] && continue
  # ¿tablet en fastboot?
  if timeout 8 "$FB" devices 2>/dev/null | grep -q fastboot; then
    if [ "$ACCIONES" -ge 4 ]; then
      [ -f "$PAUSE" ] || { touch "$PAUSE"; say "TOPE 4 acciones: autopausado ($PAUSE)"; }
      continue
    fi
    ACCIONES=$((ACCIONES + 1))
    say "fastboot detectado — acción $ACCIONES/4: restaurar dtbo_b s238 + set_active + reboot"
    sleep 5   # que el fastboot del ABL asiente
    timeout 60 "$FB" flash dtbo_b "$DTBO_BUENO" >> "$LOG" 2>&1
    timeout 20 "$FB" set_active a >> "$LOG" 2>&1
    timeout 20 "$FB" set_active b >> "$LOG" 2>&1
    timeout 20 "$FB" reboot >> "$LOG" 2>&1 || true
    sleep 240  # no re-disparar mientras arranca (~40 s) ni en el rebote del contador
    # si volvió a Arch, resetear el contador de acciones del episodio
    if ping -c1 -W2 192.168.42.129 >/dev/null 2>&1; then
      ACCIONES=0
      say "tablet de vuelta en Arch — contador de acciones a 0"
    fi
  fi
done
