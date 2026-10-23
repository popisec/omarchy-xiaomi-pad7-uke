#!/bin/bash
# wifi-test.sh — ciclo completo del WLAN (ath11k/WCN6750) EN LA TABLET, en un solo arranque.
#
# QUÉ HACE (en este orden, sin flashear nada):
#   1) CHECK de firmware: los 16 ficheros del WCN6750 con su sha256 (manifiesto embebido,
#      copia de build/gates/firmware-wlan.sha256).
#   2) CHECK de módulos: la cadena cerrada que necesita ath11k_ahb (cfg80211, mac80211, rfkill,
#      qcom_q6v5*, pwrseq-qcom-wcn, qrtr_smd, qcom_pd_mapper). Si falta algo, PARA (no se gasta
#      el ciclo: en el rootfs Arch V3/V4 solo hay 5 .ko; usar el payload de P3-wifi.md Rank 1).
#   3) BLACKLIST: escribe /etc/modprobe.d/blacklist-ath11k.conf (idempotente) para que un reset no
#      deje autocarga fantasma por modalias en el arranque siguiente (lección ledger #441 §1).
#   4) ARNÉS: kprobes en ath11k_pcic_write32/read32 (entrada+retorno) + trace_pipe + dmesg -w,
#      todo a /root/wifi-test/ (persiste al reset; sync cada 2 s).
#   5) TRIGGER: modprobe ath11k (debug_mask) + modprobe ath11k_ahb. UN solo ciclo.
#   6) CAPTURA 30 s (configurable) y, si la tablet vive, espera a 300 s para el criterio
#      "sobrevive" de F3.
#   7) INFORME: Δ(t0→muerte), Δ(firmware start→muerte), entradas/retornos de MMIO, veredicto.
#
# VEREDICTOS PRE-REGISTRADOS (no cambiarlos a posteriori):
#   SIN-RESET-300s  -> el bring-up sobrevive 300 s: WiFi en camino (seguir con nmcli/iperf3).
#   RESET/APSS-LIMPIO -> reset con TODAS las MMIO con retorno => lado firmware/TZ (Δ 7,2-7,45 s
#                        desde el inicio del probe es la banda de 4/4 medidas: 7.319/7.333/7.350/7.397).
#   RESET/BUS-WEDGE -> última entrada SIN retorno => wedge de bus: volver al acceso concreto.
#   DEFER           -> el probe no llegó a "powering up wpss" (pwrseq no listo): repetir en frío.
#   SIN-DATOS       -> el arnés no capturó nada: fallo del experimento, no veredicto.
#
# USO (en la tablet, como root):
#   ./wifi-test.sh                     # ciclo completo (30 s de captura + espera a 300 s si vive)
#   ./wifi-test.sh --solo-check        # solo firmware (no toca módulos)
#   ./wifi-test.sh --solo-modulos      # solo cadena de módulos
#   ./wifi-test.sh --captura 60        # 60 s de captura
#   ./wifi-test.sh --sin-probe         # arma capturas pero no dispara (mirar a mano)
#   ./wifi-test.sh --informe [dir]     # re-parsea la captura más reciente (tras un reset)
#
# Requisitos: bash, awk, sha256sum, modprobe, dmesg (util-linux), tracefs/kprobes en el kernel.
# NO requiere python. NO toca slot/particiones/fastboot.
set -u

BASE=${WIFI_TEST_BASE:-/root/wifi-test}
CAPT=30
MODE=ciclo
INFORME_DIR=""

# ---------------------------------------------------------------- manifiesto de firmware (16)
# rutas relativas a /lib/firmware (= /usr/lib/firmware en Arch). sha256 completo.
FW_MANIFEST=$(cat <<'EOF'
c42e06f534c07ffdaec3b265ff1e38b312741e35eb5fb21b5ca77995fab8d688  ath11k/WCN6750/hw1.0/amss.bin
2a63af3fec4a2405df339bc9629d65edac8f486dbd16180816a4d6a712fc27ba  ath11k/WCN6750/hw1.0/board.bin
dfd788a4302391118b45d6d350aeb71a4f51633fa4d7a0c7cdc2d2d330d606dc  ath11k/WCN6750/hw1.0/regdb.bin
2f0b37ad814da7e612bdd420c411a323367936efea2eea32f19c9b796244b0d4  qca6750/wpss.b00
3dd190536edda87cda85b69fcc7d03174e948daa3618ca5b9a5e902f4dd2d7d4  qca6750/wpss.b01
bcaff73b3436be65aa26cf06b5e5f3e4eef3b8b5a625cc78e9169e7c9b3f5dc0  qca6750/wpss.b02
b7a3b1f97ef810824c8660222d4deb8689de77ea809c6c9ed8d779ec48dfea1d  qca6750/wpss.b03
41870cea04a11339ed8e99324e33ff2119c8de23cb77d0ad3fc7b52de059f8c9  qca6750/wpss.b04
aae176b232881e8b9258e1844a9b946a4e4690b9bb5463b281cd1ba2b3ee1f14  qca6750/wpss.b05
2b9d868e0d776659f3741d9cce75f7239f4693596181657e420c5693979473a3  qca6750/wpss.b06
d7846f851ef64896a307db5b0e08249cfd9319f0769ec91988156d92833de9fa  qca6750/wpss.b07
0de7c47d174666be7f6a820951225ce0d50c97007aa186191e9ef25356efcb34  qca6750/wpss.b08
57464f648ec1a089770e642b7c35717bf9b925e65996ba5d7671e9c77321de13  qca6750/wpss.b09
26d0fc62bd7983c7c95c03079e751e8a3188a5965b7e0c4a101ad26331819a0c  qca6750/wpss.b10
54c223d5bd1b2702572950536126184dafaad0c88da96e5a596f00d59a6f7679  qca6750/wpss.b12
e2d14e4fbcf2acbfd3ae25d2a7bc501e34264a66ad3651c408f494231c07eed8  qca6750/wpss.mdt
EOF
)

# cadena cerrada que hay que poder cargar (nombres de módulo; se comprueba con modinfo -n)
CHAIN="cfg80211 mac80211 rfkill ath11k ath11k_ahb qcom_q6v5 qcom_q6v5_pas qcom_pil_info qcom_common qcom_glink_smem qrtr-smd pwrseq-qcom-wcn qcom_pd_mapper"

say()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die()  { say "ABORT: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- argumentos
while [ $# -gt 0 ]; do
    case "$1" in
        --solo-check)   MODE=check ;;
        --solo-modulos) MODE=modulos ;;
        --sin-probe)    MODE=sinprobe ;;
        --informe)      MODE=informe; [ $# -ge 2 ] && [ "${2#--}" = "$2" ] && { INFORME_DIR=$2; shift; } ;;
        --captura)      [ $# -ge 2 ] || die "--captura N"; CAPT=$2; shift ;;
        -h|--help)      sed -n '2,40p' "$0"; exit 0 ;;
        *) die "argumento no reconocido: $1 (usa --help)" ;;
    esac
    shift
done

# el chequeo de root solo aplica a los modos que cargan módulos/escriben; --informe/--solo-check
# pueden correr como usuario normal.
case "$MODE" in
    ciclo|sinprobe) [ "$(id -u)" = 0 ] || die "hay que ser root para el ciclo (modprobe + blacklist)"; mkdir -p "$BASE" ;;
esac
TS=$(date +%Y%m%d-%H%M%S)

# ---------------------------------------------------------------- 1) firmware
check_firmware() {
    local fwroot=/lib/firmware n=0 ok=0 mal=0 falta=0
    [ -d /usr/lib/firmware ] && fwroot=/usr/lib/firmware
    say "== 1) firmware en $fwroot =="
    while read -r sha rel; do
        [ -n "${sha:-}" ] || continue
        n=$((n+1)); f="$fwroot/$rel"
        if [ ! -f "$f" ]; then
            echo "  FALTA   $rel"; falta=$((falta+1)); continue
        fi
        got=$(sha256sum "$f" | cut -d' ' -f1)
        if [ "$got" = "$sha" ]; then
            echo "  OK      $rel  ($(stat -c%s "$f") B)"; ok=$((ok+1))
        else
            echo "  SHA MAL $rel  esperado ${sha%????????????????????????????????}… medido ${got%????????????????????????????????}…"
            mal=$((mal+1))
        fi
    done <<< "$FW_MANIFEST"
    echo "  --> $ok ok, $falta faltan, $mal con sha distinto (de $n)"
    [ "$falta" -eq 0 ] && [ "$mal" -eq 0 ]
}

# ---------------------------------------------------------------- 2) módulos
check_modules() {
    local krel miss=0
    krel=$(uname -r)
    say "== 2) cadena de módulos para $krel =="
    if [ ! -d "/usr/lib/modules/$krel" ] && [ ! -d "/lib/modules/$krel" ]; then
        echo "  AVISO GORDO: no existe /usr/lib/modules/$krel (el rootfs trae 7.2.0-rc2-palawan+"
        echo "  del build viejo del árbol git; el kernel K-series es $krel SIN '+'). Ningún modprobe"
        echo "  funcionará hasta instalar el payload en /usr/lib/modules/$krel/."
    fi
    for m in $CHAIN; do
        p=$(modinfo -n "$m" 2>/dev/null) || p=""
        if [ -n "$p" ] && [ -f "$p" ]; then
            echo "  OK      $m  -> ${p#/usr/lib/modules/$krel/}"
        else
            echo "  FALTA   $m"; miss=$((miss+1))
        fi
    done
    echo "  --> faltan $miss módulos"
    if [ "$miss" -gt 0 ]; then
        echo "  PISTA: instalar el payload de P3-wifi.md Rank 1 (uke-wifi-payload.tar.gz) y 'depmod -a'."
    fi
    [ "$miss" -eq 0 ]
}

# ---------------------------------------------------------------- 3) blacklist
install_blacklist() {
    say "== 3) blacklist (idempotente) =="
    cat > /etc/modprobe.d/blacklist-ath11k.conf <<'EOF'
blacklist ath11k
blacklist ath11k_ahb
blacklist ath11k_pci
EOF
    sync
    echo "  escrito /etc/modprobe.d/blacklist-ath11k.conf (3 líneas)"
}

# ---------------------------------------------------------------- 4) arnés
TR=""
setup_trace() {
    TR=/sys/kernel/tracing
    [ -d "$TR" ] || TR=/sys/kernel/debug/tracing
    [ -d "$TR" ] || die "no hay tracefs (¿CONFIG_FTRACE?)"
    say "== 4) arnés de traza en $TR =="
    echo 0 > "$TR/tracing_on" 2>/dev/null || true
    echo > "$TR/trace" 2>/dev/null || true
    echo 32768 > "$TR/buffer_size_kb" 2>/dev/null || true
    # si una ronda previa dejó ath11k cargado sin bindear, descargarlo para aplicar debug_mask
    if lsmod | grep -q '^ath11k'; then
        say "  ath11k ya cargado: rmmod para recargar con debug_mask"
        rmmod ath11k_ahb 2>/dev/null || true
        if ! rmmod ath11k 2>/dev/null; then
            die "no se puede descargar ath11k (¿bindeado a 17110040.qcom,wcn6750?): reiniciar y repetir"
        fi
    fi
    # ath11k (core) primero: los kprobes necesitan sus símbolos. No bindea nada por sí solo.
    modprobe ath11k debug_mask=0x1FFFF || die "modprobe ath11k falló (¿faltan cfg80211/mac80211?)"
    echo "  ath11k cargado (debug_mask=$(cat /sys/module/ath11k/parameters/debug_mask 2>/dev/null))"
    # eventos ftrace del driver (si el kernel los trae)
    for e in ath11k_log_dbg ath11k_log_err ath11k_log_warn ath11k_log_info ath11k_wmi_cmd ath11k_wmi_event; do
        [ -e "$TR/events/ath11k/$e" ] && { echo 1 > "$TR/events/ath11k/$e/enable"; echo "  evento ON: ath11k/$e"; }
    done
    # kprobes de MMIO (entrada+retorno). Sintaxis validada en las rondas r9c/r10 del hermano.
    echo > "$TR/kprobe_events" 2>/dev/null || true
    if echo "p:uke_pcic_w ath11k_pcic_write32 offset=%x1 value=%x2" >> "$TR/kprobe_events" 2>/dev/null; then
        echo 1 > "$TR/events/kprobes/uke_pcic_w/enable"; echo "  kprobe ON: ath11k_pcic_write32 (offset,value)"
    else
        echo "  AVISO: no se pudo instalar el kprobe de write32 (¿símbolo ausente?)"
    fi
    if echo "p:uke_pcic_r ath11k_pcic_read32 offset=%x1" >> "$TR/kprobe_events" 2>/dev/null; then
        echo 1 > "$TR/events/kprobes/uke_pcic_r/enable"; echo "  kprobe ON: ath11k_pcic_read32 (offset)"
    else
        echo "  AVISO: no se pudo instalar el kprobe de read32"
    fi
    if echo "r:uke_pcic_w_ret ath11k_pcic_write32 offset=\$arg1 value=\$arg2 ret=\$retval" >> "$TR/kprobe_events" 2>/dev/null; then
        echo 1 > "$TR/events/kprobes/uke_pcic_w_ret/enable"; echo "  kretprobe ON: write32 (retorno)"
    elif echo "r:uke_pcic_w_ret ath11k_pcic_write32 ret=\$retval" >> "$TR/kprobe_events" 2>/dev/null; then
        echo 1 > "$TR/events/kprobes/uke_pcic_w_ret/enable"; echo "  kretprobe ON: write32 (retorno, sin args)"
    else
        echo "  AVISO: no se pudo instalar el kretprobe de write32 (no habrá prueba de retorno)"
    fi
    if echo "r:uke_pcic_r_ret ath11k_pcic_read32 offset=\$arg1 ret=\$retval" >> "$TR/kprobe_events" 2>/dev/null; then
        echo 1 > "$TR/events/kprobes/uke_pcic_r_ret/enable"; echo "  kretprobe ON: read32 (retorno)"
    elif echo "r:uke_pcic_r_ret ath11k_pcic_read32 ret=\$retval" >> "$TR/kprobe_events" 2>/dev/null; then
        echo 1 > "$TR/events/kprobes/uke_pcic_r_ret/enable"; echo "  kretprobe ON: read32 (retorno, sin args)"
    else
        echo "  AVISO: no se pudo instalar el kretprobe de read32"
    fi
}

start_captures() {
    local tag=$1
    DML="$BASE/dmesg-$tag.log"; TRP="$BASE/trace-$tag.log"
    # stdbuf -oL: sin buffer de stdio; si el SoC resetea, el fichero ya tiene la cola.
    if have stdbuf; then
        ( stdbuf -oL dmesg -w > "$DML" 2>&1 & echo $! > "$BASE/.pid-dmesg" )
        ( stdbuf -oL cat "$TR/trace_pipe" > "$TRP" 2>&1 & echo $! > "$BASE/.pid-trace" )
    else
        ( dmesg -w > "$DML" 2>&1 & echo $! > "$BASE/.pid-dmesg" )
        ( cat "$TR/trace_pipe" > "$TRP" 2>&1 & echo $! > "$BASE/.pid-trace" )
        echo "  AVISO: sin stdbuf (coreutils): la cola puede perderse si hay reset"
    fi
    # flush periódico a disco (el reset se lleva la caché de página)
    ( while :; do sleep 2; sync; done & echo $! > "$BASE/.pid-sync" )
    sleep 2
    echo "  capturas: $DML + $TRP"
    # marca de canal (verifica que trace_pipe está vivo)
    echo "UKE-WIFI-CANAL-OK" > "$TR/trace_marker" 2>/dev/null || true
    sleep 1
    if grep -aq 'UKE-WIFI-CANAL-OK' "$TRP" 2>/dev/null; then
        echo "  canal trace_pipe VIVO (marca recibida)"
    else
        echo "  AVISO: no llegó la marca a trace_pipe (¿trace_marker no soportado?)"
    fi
    echo 1 > "$TR/tracing_on"
}

stop_captures() {
    [ -n "${TR:-}" ] && { echo 0 > "$TR/tracing_on" 2>/dev/null || true; }
    for p in "$BASE/.pid-dmesg" "$BASE/.pid-trace" "$BASE/.pid-sync"; do
        [ -f "$p" ] && { kill "$(cat "$p")" 2>/dev/null || true; rm -f "$p"; }
    done
    sync
}

# ---------------------------------------------------------------- 5) trigger + espera
do_probe() {
    local t0
    say "== 5) trigger: modprobe ath11k_ahb (UN ciclo) =="
    echo "UKE-WIFI-TEST-TRIGGER $(date -u +%FT%TZ)" > /dev/kmsg 2>/dev/null || true
    t0=$(cat /proc/uptime | cut -d' ' -f1)
    echo "  uptime t0=$t0"
    modprobe ath11k_ahb 2>&1 | sed 's/^/  modprobe: /'
    echo "  modprobe rc=$? (si la tablet resetea aquí, el SSH/consola se corta: seguir con --informe)"
}

# ---------------------------------------------------------------- 7) informe
# Extrae anclas del dmesg y cuenta entradas/retornos del trace. Imprime el veredicto.
informe() {
    local dml=$1 trp=$2 tag=$3
    say "== 7) informe ($tag) =="
    [ -f "$dml" ] || die "no existe $dml"
    awk -v tag="$tag" '
        function ts(l,   m,s) { if (match(l, /^\[[ ]*[0-9]+\.[0-9]+\]/)) { s=substr(l,RSTART+1,RLENGTH-2); gsub(/ /,"",s); return s+0 } return -1 }
        /UKE-WIFI-TEST-TRIGGER/ { if (ts($0)>0) t0m=ts($0) }
        /ath11k .*deferred probe timeout/ { p0=ts($0) }        # se queda la ULTIMA (el probe que murio)
        /ath11k .*wcn6750 hw1\.0/ { if (hw<=0) hw=ts($0) }
        /remoteproc.*powering up wpss/ { wp=ts($0) }
        /qmi firmware init done/ { fi=ts($0) }
        /qmi Coldboot calibration wait started/ { cal0=ts($0) }
        /qmi cold boot calibration done/ { cal1=ts($0) }
        /qmi firmware ready/ { fr=ts($0) }
        /qmi firmware start/ { fs=ts($0) }
        /ath11k / { last=ts($0); lastl=$0 }
        # avisos: solo del WLAN (el log entero trae errores ajenos de la plataforma)
        /ath11k|wcn6750|wpss/ && /watchdog received|fatal error received|qmi failed|failed to|error -/ { err[++ne]=$0 }
        END {
            t0 = (t0m>0 ? t0m : p0)
            printf "  t0(trigger)         : %.6f\n", (t0m>0?t0m:0)
            printf "  t0(probe, ultimo)   : %.6f\n", (p0>0?p0:0)
            printf "  powering up wpss    : %.6f\n", (wp>0?wp:0)
            printf "  qmi firmware init   : %.6f\n", (fi>0?fi:0)
            printf "  qmi firmware ready  : %.6f\n", (fr>0?fr:0)
            printf "  qmi firmware start  : %.6f\n", (fs>0?fs:0)
            printf "  cal wait started    : %.6f\n", (cal0>0?cal0:0)
            printf "  cal done            : %.6f\n", (cal1>0?cal1:0)
            printf "  ultima linea ath11k : %.6f\n", (last>0?last:0)
            if (last>0) printf "  ultima linea        : %s\n", lastl
            if (t0>0 && last>0) printf "  DELTA(t0->ultima)   : %.3f s   (banda reset: 7.2-7.45)\n", last-t0
            if (fs>0 && last>0) printf "  DELTA(fw_start->ultima): %.3f s (patron: 0.38)\n", last-fs
            if (wp>0 && last>0) printf "  DELTA(wpss->ultima) : %.3f s\n", last-wp
            if (cal0>0 && cal1>0) printf "  cal coldboot (wait->done): %.3f s (patron: 6.14)\n", cal1-cal0
            if (fr>0 && fi>0)  printf "  init_done->ready    : %.3f s\n", fr-fi
            for (i=1;i<=ne;i++) printf "  AVISO: %s\n", err[i]
            if (last<=0) printf "  SIN-DATOS: no se capturo ninguna linea ath11k\n"
        }' "$dml"
    if [ -f "$trp" ]; then
        ent=$(grep -ac 'uke_pcic_w:\|uke_pcic_r:' "$trp" 2>/dev/null || echo 0)
        ret=$(grep -ac 'uke_pcic_w_ret:\|uke_pcic_r_ret:' "$trp" 2>/dev/null || echo 0)
        echo "  MMIO: entradas=$ent retornos=$ret"
        echo "  ultimas 3 lineas del trace:"; tail -3 "$trp" | sed 's/^/    /'
        if [ "$ent" -eq 0 ]; then
            echo "  VEREDICTO: SIN-DATOS (el arnes no capturo; no concluir)"
        elif [ "$ent" -gt "$ret" ]; then
            echo "  VEREDICTO: RESET/BUS-WEDGE (ultima MMIO sin retorno)"
        else
            echo "  VEREDICTO: RESET/APSS-LIMPIO (todas las MMIO con retorno => firmware/TZ)"
        fi
    fi
    # supervivencia
    up=$(cut -d' ' -f1 /proc/uptime)
    echo "  uptime actual: ${up}s  (si < captura+trigger, la tablet reseteo)"
}

if [ "$MODE" = informe ]; then
    d=${INFORME_DIR:-$BASE}
    [ -d "$d" ] || die "no existe $d"
    dml=$(ls -1t "$d"/dmesg-*.log 2>/dev/null | head -1) || true
    trp=$(ls -1t "$d"/trace-*.log 2>/dev/null | head -1) || true
    [ -n "$dml" ] || die "no hay dmesg-*.log en $d"
    informe "$dml" "${trp:-/dev/null}" "$(basename "$dml" .log)"
    exit 0
fi

if [ "$MODE" = check ]; then check_firmware; exit $?; fi
if [ "$MODE" = modulos ]; then check_modules; exit $?; fi

# ---------------------------------------------------------------- ciclo
say "== wifi-test $TS (captura ${CAPT}s) =="
echo "  kernel: $(uname -r)   uptime: $(cut -d' ' -f1 /proc/uptime)s"
COMPAT=$(tr -d '\0' < /proc/device-tree/soc/qcom,wcn6750/compatible 2>/dev/null || echo "?")
echo "  nodo WLAN compatible: ${COMPAT:-?}  (debe contener qcom,wcn6750-wifi)"
[ "$COMPAT" = "${COMPAT#*qcom,wcn6750-wifi}" ] && echo "  AVISO: el DT vivo NO trae qcom,wcn6750-wifi: el dtbo no es de la cadena WiFi (P3-wifi.md §b.2)"
echo "  ath11k cargado antes: $(lsmod | grep -c '^ath11k' || true)"
echo "  bateria: $(for b in /sys/class/power_supply/*/voltage_now; do [ -r "$b" ] && echo "$(cat "$b") uV"; done | head -2 | tr '\n' ' ')"

check_firmware || { say "firmware incompleto: instalar el payload de P3-wifi.md Rank 1 y repetir"; exit 1; }
check_modules  || { say "cadena de modulos incompleta: instalar el payload y 'depmod -a'"; exit 1; }
install_blacklist

setup_trace
start_captures "$TS"
[ "$MODE" = sinprobe ] && { say "--sin-probe: no se dispara nada (mira $BASE)"; stop_captures; exit 0; }

do_probe
say "esperando ${CAPT}s de captura..."
sleep "$CAPT"

if kill -0 "$(cat "$BASE/.pid-dmesg" 2>/dev/null)" 2>/dev/null; then
    say "la tablet VIVE tras ${CAPT}s: esperando a 300 s (criterio F3)..."
    sleep 240
fi

stop_captures
informe "$DML" "$TRP" "$TS" | tee "$BASE/reporte-$TS.txt"

# estado final si vive
if [ -r /proc/uptime ]; then
    echo "== estado final ==" | tee -a "$BASE/reporte-$TS.txt"
    lsmod | grep -E 'ath11k|qcom_q6v5_pas|pwrseq' | tee -a "$BASE/reporte-$TS.txt"
    ip link 2>/dev/null | grep -E 'wlan|wlp' | tee -a "$BASE/reporte-$TS.txt" || echo "  (sin interfaz wlan*)"
    if have nmcli; then nmcli dev status 2>&1 | tee -a "$BASE/reporte-$TS.txt"; fi
    sha256sum "$DML" "$TRP" >> "$BASE/reporte-$TS.txt" 2>/dev/null
fi
say "hecho. evidencia: $BASE/reporte-$TS.txt + $(basename "$DML") + $(basename "$TRP")"
say "si hubo reset: tras el reinicio, './wifi-test.sh --informe' re-parsea esta misma captura."
