#!/bin/sh
# uke-ufs-witness.sh — canal testigo en UFS (RONDA-A2 vía 1, 10-oct-2026)
#
# Problema: P1 (pstore/mtdoops) y P2 (ramoops-DRAM) no sobreviven al reset del
# SoC (sin partición oops bindeable; la DRAM no sobrevive al reboot). El UFS
# SÍ sobrevive: este script vuelca dmesg + ftrace (funciones a6xx*) a flash
# con sync periódico, para capturar el entorno de UNA muerte del release del
# CM3 con resolución de ~200 ms.
#
# Uso (en la tablet, como root):
#   /root/uke-ufs-witness.sh arm         # arranca testigo en background
#   /root/uke-ufs-witness.sh mark TEXTO  # marca con timestamp en dmesg.log
#   /root/uke-ufs-witness.sh stop        # para lectores y sync-loop
#
# NOTA: rootfs está rw (norecovery) — tras el protocolo de muertes, e2fsck en
# frío como manda la regla del proyecto (drift del no-journal).

DIR=/root/witness
T=/sys/kernel/tracing
PIDF=$DIR/pids

case "$1" in
  arm)
    mkdir -p "$DIR"
    # 0. rotar (NO truncar): el boot anterior es evidencia — se conserva 1 generación
    [ -f "$DIR/dmesg.log" ] && mv "$DIR/dmesg.log" "$DIR/dmesg.prev.log" 2>/dev/null
    [ -f "$DIR/trace.log" ] && mv "$DIR/trace.log" "$DIR/trace.prev.log" 2>/dev/null
    : > "$PIDF"   # PIDs frescos: los de boots anteriores están reciclados (CRITICA-A2 #1)
    # 0. cabecera con el contexto del boot (boot_index + pureason incluidos)
    {
      echo "=== UKE-UFS-WITNESS arm $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
      cat /proc/cmdline | tr ' ' '\n' | grep -E 'bootinfo|boot_index|uke_|panic|hung|watchdog' | tr '\n' ' '; echo
      echo "bateria: telemetria battmgr no disponible en este kernel (EAGAIN)"
    } > "$DIR/dmesg.log"
    : > "$DIR/trace.log"

    # 1. ftrace: tracer function filtrado a a6xx* (87 funciones en L11)
    echo 0 > "$T/tracing_on" 2>/dev/null
    echo nop > "$T/current_tracer" 2>/dev/null
    : > "$T/trace" 2>/dev/null
    echo 'a6xx*' > "$T/set_ftrace_filter" 2>/dev/null
    echo function > "$T/current_tracer" 2>/dev/null
    {
      echo "=== ftrace filter: $(wc -l < "$T/set_ftrace_filter" 2>/dev/null) funciones, tracer=$(cat "$T/current_tracer" 2>/dev/null) ==="
    } >> "$DIR/trace.log"
    echo 1 > "$T/tracing_on" 2>/dev/null

    # 2. lectores a fichero (snapshot completo de dmesg + follow)
    dmesg >> "$DIR/dmesg.log" 2>&1
    dmesg -w >> "$DIR/dmesg.log" 2>&1 &
    echo $! >> "$PIDF"
    cat "$T/trace_pipe" >> "$DIR/trace.log" 2>&1 &
    echo $! >> "$PIDF"

    # 3. sync periódico: el tail del testigo queda en UFS ≤0,2 s tras la muerte
    ( while :; do sync; sleep 0.2; done ) &
    echo $! >> "$PIDF"

    echo "UKE-WITNESS: armado en $DIR ($(wc -l < "$PIDF") procesos)"
    ;;

  mark)
    echo "UKE-WITNESS-MARK: $*" > /dev/kmsg
    ;;

  test)
    # autotest de AMBOS canales sin GPU: trace_marker (ftrace) + kmsg (dmesg)
    echo "UKE-WITNESS-PROBE $(date +%s)" > "$T/trace_marker" 2>/dev/null
    echo "UKE-WITNESS-PROBE kmsg" > /dev/kmsg
    sleep 1
    echo "trace_marker capturado: $(grep -c UKE-WITNESS-PROBE "$DIR/trace.log" 2>/dev/null)"
    echo "kmsg capturado:       $(grep -c UKE-WITNESS-PROBE "$DIR/dmesg.log" 2>/dev/null)"
    v=0; for pid in $(cat "$PIDF" 2>/dev/null); do [ -d "/proc/$pid" ] && v=$((v+1)); done; echo "lectores vivos:       $v/3"
    ;;

  stop)
    if [ -f "$PIDF" ]; then
      kill $(cat "$PIDF") 2>/dev/null
      rm -f "$PIDF"
    fi
    echo 0 > "$T/tracing_on" 2>/dev/null
    sync
    echo "UKE-WITNESS: parado"
    ;;

  *)
    echo "uso: $0 arm|mark TEXTO|stop" >&2
    exit 1
    ;;
esac
