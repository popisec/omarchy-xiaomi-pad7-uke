#!/bin/sh
# uke-wedge-sampler.sh — sampler E3 del wedge del panel (informe 11-oct-2026).
#
# Muestrea a ~25 Hz, en /root/witness/wedge/ (UFS, con sync cada 0,5 s):
#   rails.log  — microvoltios+estado de los reguladores L8 / vsp / vsn del panel
#   tlmm.log   — gpio 2 (reset del panel), 74/75 (vsp/vsn por GPIO) y 168/169
#                (táctil/ESD del TDDI): valor/estado crudo del conector gpio
#   irq.now    — último snapshot de /proc/interrupts (renombrado atómico: en la
#                muerte queda el ÚLTIMO, nunca un fichero vacío a medio grep)
#   irq-full-N.txt — /proc/interrupts completo cada 40 ticks (1,6 s)
#
# Uso (en la tablet, como root):
#   uke-wedge-sampler.sh arm     # arranca los 3 loops en background
#   uke-wedge-sampler.sh stop    # para y cierra
#
# Diseñado para correr ANTES del enable deliberado del panel (modetest/status),
# junto a uke-ufs-witness.sh y acm-loop.sh. Si el SoC muere, lo último escrito
# y sincronizado (0,5 s de granularidad) queda en UFS.
#
# Nota: lee sysfs/debugfs solo; no toca hardware. Timestamps con date +%s%3N
# (coreutils); si la date no soporta %3N, arm lo avisa en rails.log y cae a s.

set -u
DIR=/root/witness/wedge
PIDF=/root/witness/wedge/sampler.pids
HZ=25

mkdir -p "$DIR"

resolve_regulators() {
    # Localiza una vez los dirs regulator cuyo name case-insensitive
    # matchee l8 / vsp / vsn (los rieles del panel o82).
    : > "$DIR/regmap.txt"
    for d in /sys/class/regulator/regulator.*; do
        [ -r "$d/name" ] || continue
        n=$(cat "$d/name" 2>/dev/null)
        case "$n" in
            *[Ll]8*|*[Vv]sp*|*[Vv]sn*) echo "$d $n" >> "$DIR/regmap.txt" ;;
        esac
    done
}

loop_rails() {
    while :; do
        ts=$(date +%s%3N 2>/dev/null || date +%s)
        line="$ts"
        while read -r d n; do
            mv=$(cat "$d/microvolts" 2>/dev/null)
            st=$(cat "$d/state" 2>/dev/null)
            line="$line $n=$mv:$st"
        done < "$DIR/regmap.txt"
        echo "$line" >> "$DIR/rails.log"
        # coreutils no trae usleep (solo busybox): dormir directo con sleep,
        # que en Arch (GNU coreutils) acepta decimales.
        sleep 0.04
    done
}

loop_tlmm() {
    while :; do
        ts=$(date +%s%3N 2>/dev/null || date +%s)
        line="$ts"
        if [ -e /sys/class/gpio/gpio2/value ]; then
            for g in 2 74 75 168 169; do
                v=$(cat "/sys/class/gpio/gpio$g/value" 2>/dev/null)
                line="$line g$g=$v"
            done
        else
            # Sin gpiofs (CONFIG_GPIO_SYSFS no esta en el kernel L19): UNA lectura
            # de debugfs y UN awk por tick (antes: 5x grep|sed = 16 forks/tick).
            # Formatos que cubre:
            #   mainline (gpiolib.c:5424): " gpio-2   (name|label) out hi IRQ"
            #   downstream qcom:           " gpio2   : out low  func0 8mA pull up"
            line="$line $(awk -v wl="2 74 75 168 169" '
                BEGIN { n = split(wl, w, " "); for (i = 1; i <= n; i++) want[w[i]] = i }
                {
                    g = ""
                    if (match($1, /^gpio-[0-9]+$/))      g = substr($1, 6) + 0
                    else if (match($1, /^gpio[0-9]+$/))  g = substr($1, 5) + 0
                    if (g in want) {
                        s = $0
                        if (sub(/^[^)]*\) /, "", s) == 0)
                            sub(/^ *gpio[-]?[0-9]+ *: */, "", s)
                        out[want[g]] = "g" g "=" substr(s, 1, 40)
                    }
                }
                END {
                    for (i = 1; i <= n; i++)
                        printf "%s%s", (i in out ? out[i] : "g" w[i] "=?"), (i < n ? " " : "")
                    printf "\n"
                }' /sys/kernel/debug/gpio 2>/dev/null)"
        fi
        echo "$line" >> "$DIR/tlmm.log"
        sleep 0.04
    done
}

loop_irq() {
    n=0
    while :; do
        # escribir a .tmp y renombrar (mismo dir = rename atomico): si el SoC
        # muere entre truncar y escribir, irq.now conserva el snapshot anterior
        # en vez de quedar vacio.
        grep -E 'gp|pm8|pmx|spmi' /proc/interrupts > "$DIR/irq.now.tmp" 2>/dev/null
        mv "$DIR/irq.now.tmp" "$DIR/irq.now"
        n=$((n + 1))
        echo $n > "$DIR/irq.count"
        if [ $((n % 40)) -eq 0 ]; then
            cp /proc/interrupts "$DIR/irq-full-$n.txt" 2>/dev/null
        fi
        sleep 0.04
    done
}

syncer() {
    while :; do
        sync -f "$DIR" 2>/dev/null || sync 2>/dev/null
        sleep 0.5
    done
}

case "${1:-}" in
arm)
    # comprobar pid a pid: cat de varias lineas dentro de kill -0 no funciona,
    # y rearmar sobre un PIDF rancio haria que `stop`/xargs kill matara un pid
    # RECICLADO (mismo bug que CRITICA-A2 #1 corrigio en uke-ufs-witness.sh).
    if [ -f "$PIDF" ]; then
        for p in $(cat "$PIDF"); do
            if kill -0 "$p" 2>/dev/null; then
                echo "ya armado (pid $p)"; exit 1
            fi
        done
        : > "$PIDF"
    fi
    resolve_regulators
    nr=$(wc -l < "$DIR/regmap.txt")
    [ "$nr" -lt 3 ] && echo "AVISO: regmap=$nr rieles (<3): L8/vsp/vsn no matchearon por nombre" >&2
    if [ ! -e /sys/class/gpio/gpio2/value ] && [ ! -r /sys/kernel/debug/gpio ]; then
        echo "AVISO: sin gpiofs NI debugfs montado — tlmm.log saldra con gN=?" >&2
    fi
    echo "# $(date) HZ=$HZ regmap:" > "$DIR/rails.log"
    case "$(date +%s%3N 2>/dev/null)" in
        *N*) echo "# AVISO: date sin %3N (busybox? se esperaba coreutils) — timestamps en s" >> "$DIR/rails.log" ;;
    esac
    cat "$DIR/regmap.txt" >> "$DIR/rails.log"
    echo "# $(date) pines 2/74/75/168/169 (estado crudo del conector)" > "$DIR/tlmm.log"
    echo 0 > "$DIR/irq.count"
    : > "$DIR/irq.now"
    loop_rails & echo $! >> "$PIDF"
    loop_tlmm & echo $! >> "$PIDF"
    loop_irq  & echo $! >> "$PIDF"
    syncer    & echo $! >> "$PIDF"
    echo "armado: $(wc -l < "$PIDF") loops; regmap:"
    cat "$DIR/regmap.txt"
    ;;
stop)
    [ -f "$PIDF" ] || { echo "no armado"; exit 0; }
    xargs -r kill < "$PIDF" 2>/dev/null
    rm -f "$PIDF"
    sync -f "$DIR" 2>/dev/null || sync
    echo "parado; ficheros en $DIR:"
    ls -la "$DIR"
    ;;
*)
    echo "uso: $0 arm|stop" >&2
    exit 2
    ;;
esac
