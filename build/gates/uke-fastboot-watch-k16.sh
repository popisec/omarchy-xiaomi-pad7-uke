#!/bin/bash
# uke-fastboot-watch-k16.sh — vigía fastboot RETARGETEADO al par vigente del 30-sep
# (copia local de ~/proyectos/ubuntu-permanente/bin/uke-fastboot-watch.sh — ESE es
# solo lectura y apunta al par viejo s244-bounce+s229; NO tocar).
#
# Par bueno: boot K13-dsid (e0ee47dc…) + dtbo s260 (6fbb5173…), copias verificadas
# en build/backup-par-bueno/ (shas en build/gates/SHA-BUENOS.txt §PAR VIGENTE 30-sep).
#
# Protocolo de la sesión #P44 (PLAN-SIGUIENTE-v2 P2):
#   1. armarlo ANTES del flash CON PAUSA (touch /tmp/uke-fastboot-watch.pause):
#      durante el flash Y mientras se observa un desenlace de muerte, la caída a
#      fastboot es el RESULTADO esperado — sin pausa el vigía la sacaría y
#      destruiría la captura de consola.
#   2. tras leer el desenlace: rm -f de la pausa -> si la tablet sigue en fastboot,
#      resetea contadores (set_active a/b) y arranca; a la 3ª caída seguida
#      restaura el par K13-dsid + s260 (rollback automático).
# Uso: setsid nohup bash build/gates/uke-fastboot-watch-k16.sh >/dev/null 2>&1 &
set -u
R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
LOG=/var/tmp/uke-k16-watch.log
PAUSA=/tmp/uke-fastboot-watch.pause
FB=$(command -v fastboot || echo /opt/android-sdk/platform-tools/fastboot)
BOOT_OK="$R/build/backup-par-bueno/boot-ukek13-dsid.img"
DTBO_OK="$R/build/backup-par-bueno/s260-boot-dtbo-dpu-iommus.img"
SHA_BOOT_OK=e0ee47dc4044e9cccbcf177ab36cc8efd005ee9ef4d7cff370741578707c5c57
SHA_DTBO_OK=6fbb5173b8af5add34e90dcff9d3dce742f7fa9fe76182eda2db123b39685ad7
INTERVALO=${UKE_FB_INTERVALO:-15}
MAX_INTENTOS=${UKE_FB_MAX_INTENTOS:-3}

mkdir -p "$(dirname "$LOG")"
say() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >> "$LOG"; }

if [ "$(sha256sum "$BOOT_OK" 2>/dev/null | cut -d' ' -f1)" != "$SHA_BOOT_OK" ]; then
    say "AVISO: boot del par bueno no está o sha no cuadra: NO se restaurará ($BOOT_OK)"
    BOOT_OK=""
fi
if [ "$(sha256sum "$DTBO_OK" 2>/dev/null | cut -d' ' -f1)" != "$SHA_DTBO_OK" ]; then
    say "AVISO: dtbo del par bueno no está o sha no cuadra: NO se restaurará ($DTBO_OK)"
    DTBO_OK=""
fi

say "VIGÍA-K16 arrancado (sondeo ${INTERVALO}s, ${MAX_INTENTOS} intentos antes de restaurar)"
say "  par bueno: $(basename "${BOOT_OK:-NINGUNO}") + $(basename "${DTBO_OK:-NINGUNO}")"

estado() {
    local v
    for v in current-slot slot-retry-count:a slot-unbootable:a slot-retry-count:b slot-unbootable:b battery-voltage; do
        printf '    %-22s %s\n' "$v" "$(timeout 12 "$FB" getvar "$v" 2>&1 | head -1)"
    done
}

en_arch() { ping -c1 -W1 192.168.42.129 >/dev/null 2>&1; }

intentos=0
while :; do
    if en_arch; then
        [ "${intentos:-0}" -ne 0 ] && say "  la tablet arranco Arch: cuenta de caidas a 0 (era $intentos)"
        intentos=0
        sleep "$INTERVALO"
        continue
    fi
    if ! timeout 10 "$FB" devices 2>/dev/null | grep -q .; then
        sleep "$INTERVALO"
        continue
    fi

    say "FASTBOOT detectado"
    estado | while IFS= read -r l; do say "$l"; done

    if [ -e "$PAUSA" ]; then
        say "  PAUSA activa ($PAUSA): no toco nada. Recuerda que en fastboot NO carga."
        sleep "$INTERVALO"
        continue
    fi

    intentos=$((intentos + 1))
    say "  intento $intentos/$MAX_INTENTOS: reinicio contadores y arranco (en fastboot no carga)"

    if [ "$intentos" -ge "$MAX_INTENTOS" ] && [ -n "$BOOT_OK" ] && [ -n "$DTBO_OK" ]; then
        say "  $intentos caídas seguidas: el par flasheado está roto -> restauro par vigente K13-dsid + s260"
        timeout 200 "$FB" flash boot_b "$BOOT_OK" 2>&1 | tail -1 | while IFS= read -r l; do say "    $l"; done
        timeout 200 "$FB" flash dtbo_b "$DTBO_OK" 2>&1 | tail -1 | while IFS= read -r l; do say "    $l"; done
        intentos=0
    fi

    timeout 20 "$FB" set_active a 2>&1 | tail -1 >/dev/null
    timeout 20 "$FB" set_active b 2>&1 | tail -1 >/dev/null
    say "  contadores: $(timeout 12 "$FB" getvar slot-retry-count:b 2>&1 | head -1)"
    timeout 20 "$FB" reboot 2>&1 | tail -1 >/dev/null
    say "  reboot lanzado; si vuelve a fastboot en <90 s es que el par no arranca"
    sleep 90
done
