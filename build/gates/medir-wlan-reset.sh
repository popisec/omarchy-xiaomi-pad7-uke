#!/bin/bash
# medir-wlan-reset.sh — mide el reset silencioso del WLAN (F3) y discrimina
# BUS (wedge en MMIO) vs FIRMWARE (APSS limpio), con UN SOLO ciclo de modprobe.
#
# Corre en el PC, pilota la tablet por SSH. NO flashea, NO hace dd, NO toca slots.
# Gasta COMO MUCHO 1 reintento de slot (1 reset); si gasta mas, es alarma.
#
# GATES Y CRITERIOS (decididos ANTES de ejecutar, cabecera = pre-registro):
#   VEREDICTO-A "BUS WEDGE": la ultima entrada uke_w/uke_r del trace NO tiene su
#     retorno uke_w_ret/uke_r_ret antes del corte  => un acceso MMIO no completo.
#   VEREDICTO-B "APSS LIMPIO => FIRMWARE": todas las entradas tienen retorno
#     (como el Branch B de #436: 137/137, y r9c: 211/211) => el culpable esta del
#     lado dispositivo/firmware-TZ, no en el bus.
#   CORROBORACION-TEMPORIZADOR: Delta(t0=probe, ultima linea) en 7.2-7.45 s
#     (4/4 hasta r10e: 7.319/7.333/7.350/7.397) => 5a medida a favor del
#     watchdog de firmware-TZ; fuera de banda => anotar punto nuevo, hipotesis
#     del temporizador debilitada.
#   FALLO DEL EXPERIMENTO (no veredicto): sin reset y sin supervivencia a 300 s
#     (captura cortada a mano), o probes no registrables => repetir, no concluir.
#
# DOBLE CAPTURA OBLIGATORIA (LECCIONES ronda 38 s3 + #428->#429): la consola de
# 115200 pierde la cola al cortar el reset. Por eso las DOS capturas (dmesg -w y
# trace_pipe) van POR SSH A FICHERO EN EL PC, arrancadas ANTES de disparar nada.
# Si la tablet wedgea, los ficheros ya estan escritos en el PC.
#
# MATIZ HONESTO (posted writes): en ARM64 el iowrite32 es posted (no espera).
# Un wedge de bus se vera con mas probabilidad como una LECTURA sin retorno
# (ioread32 si espera) o como SError. Por eso se instrumentan write32 Y read32,
# con entrada+retorno, y el veredicto cuenta CUALQUIER acceso sin retorno.
#
# USO:
#   UKE_SSH=root@192.168.42.129 UKE_SLOT_RETRY_B=7 UKE_BAT_MV=4100 ./medir-wlan-reset.sh [salida/]
#   UKE_SLOT_RETRY_B = ultimo slot-retry-count:b leido por fastboot (OBLIGATORIO).
#   UKE_BAT_MV       = ultima battery-voltage por fastboot (OBLIGATORIO, >=3700).
set -u
OUT=${1:-out/medicion-wlan}
SSH=${UKE_SSH:-root@192.168.42.129}
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=2 -o ServerAliveCountMax=3"
RETRY_B=${UKE_SLOT_RETRY_B:-}
BAT_MV=${UKE_BAT_MV:-}

die() { echo "ABORT: $*" >&2; exit 1; }

# GATE 0: presupuesto de operacion (docs/historia/AGENTS.md). Sin estos dos datos no se corre.
[ -n "$RETRY_B" ] || die "falta UKE_SLOT_RETRY_B (leer fastboot getvar all ANTES)"
[ -n "$BAT_MV" ] || die "falta UKE_BAT_MV (leer fastboot getvar battery-voltage ANTES)"
[ "$RETRY_B" -ge 3 ] || die "slot-retry-count:b=$RETRY_B < 3: ese dia SOLO LECTURA"
[ "$BAT_MV" -ge 3700 ] || die "bateria $BAT_MV mV < 3700: no flashear/probar"
echo "presupuesto OK: retry_b=$RETRY_B bat=${BAT_MV}mV (registrar inicial/final en ledger)"

mkdir -p "$OUT"
TS=$(date +%Y%m%d-%H%M%S)
DML=$OUT/dmesg-$TS.log
TRP=$OUT/trace-$TS.log
QBT0=$OUT/qbootctl-antes-$TS.txt
QBT1=$OUT/qbootctl-despues-$TS.txt
ssh $SSH_OPTS "$SSH" true || die "sin SSH a $SSH (tablet ocupada o caida: mirar ESTADO-ACTUAL del hermano)"

# Estado slot ANTES (qbootctl dump, solo lectura) + boot_id.
ssh $SSH_OPTS "$SSH" '/usr/local/bin/qbootctl 2>/dev/null || qbootctl' >"$QBT0" 2>&1 || true
BOOT0=$(ssh $SSH_OPTS "$SSH" 'cat /proc/sys/kernel/random/boot_id') || die "no se lee boot_id"
echo "boot_id antes: $BOOT0"

# dmesg -n 7 ANTES de pedir evidencia (los UKE-* son KERN_INFO/nivel 6).
ssh $SSH_OPTS "$SSH" 'dmesg -n 7 && echo NIVEL-OK'

cleanup() {
    # Best-effort: si la tablet sigue viva, desarmar probes y tracing.
    ssh $SSH_OPTS -o ConnectTimeout=5 "$SSH" \
        'echo 0 > /sys/kernel/tracing/tracing_on 2>/dev/null; echo > /sys/kernel/tracing/kprobe_events 2>/dev/null; true' || true
}
trap cleanup EXIT

# Un solo ciclo: descargar modulos (quedan sin bindear si pwrseq no esta listo).
ssh $SSH_OPTS "$SSH" 'rmmod ath11k_ahb 2>/dev/null; rmmod ath11k 2>/dev/null; lsmod | grep -c ath11k || echo 0'
# Cargar SOLO ath11k (libreria, sin efecto lateral) para que los simbolos existan...
ssh $SSH_OPTS "$SSH" 'modprobe ath11k && grep -c ath11k_pcic_write32 /proc/kallsyms'
# ...y registrar kprobe+kretprobe de write32 Y read32 (off=x1, val=x2 en ARM64).
ssh $SSH_OPTS "$SSH" 'cd /sys/kernel/tracing && echo > kprobe_events && \
  echo "p:uke_w ath11k_pcic_write32 off=+0(x1):u32 val=+0(x2):u32" >> kprobe_events && \
  echo "r:uke_w_ret ath11k_pcic_write32" >> kprobe_events && \
  echo "p:uke_r ath11k_pcic_read32 off=+0(x1):u32" >> kprobe_events && \
  echo "r:uke_r_ret ath11k_pcic_read32 ret=\\$retval:u32" >> kprobe_events && \
  echo 1 > tracing_on && cat kprobe_events' \
    || die "probes no registrables (PENDIENTE validar sintaxis de regs ARM64 en tablet): no concluir nada"

# DOBLE CAPTURA EN SEGUNDO PLANO, ANTES DE DISPARAR (ficheros ya en el PC).
# shellcheck disable=SC2086
ssh $SSH_OPTS "$SSH" 'dmesg -w' >"$DML" 2>&1 &
PID_DML=$!
ssh $SSH_OPTS "$SSH" 'cat /sys/kernel/tracing/trace_pipe' >"$TRP" 2>&1 &
PID_TRP=$!
sleep 3
kill -0 $PID_DML 2>/dev/null || die "captura dmesg muerta antes del trigger"
kill -0 $PID_TRP 2>/dev/null || die "captura trace muerta antes del trigger"
echo "capturas vivas (dmesg->$(basename "$DML"), trace->$(basename "$TRP"))"

# TRIGGER: un solo modprobe. Si hay reset, el SSH cae y las capturas quedan.
echo "trigger: modprobe ath11k_ahb (UN SOLO CICLO)"
ssh $SSH_OPTS "$SSH" 'modprobe ath11k_ahb; echo MODPROBE-RC=$?' || echo "ssh cayo (posible reset; las capturas mandan)"

# Esperar: o vuelve el prompt (sobrevive) o cae (reset). Max 60 s aqui; la
# supervivencia a 300 s se verifica despues con uptime si sigue viva.
sleep 45
if ssh $SSH_OPTS -o ConnectTimeout=8 "$SSH" true 2>/dev/null; then
    echo "tablet VIVA tras 45 s: verificar supervivencia a 300 s con uptime."
    ssh $SSH_OPTS "$SSH" 'uptime; lsmod | grep ath11k' || true
    sleep 260
    ssh $SSH_OPTS "$SSH" 'uptime' || echo "cayo entre 45 s y 300 s (anotar)"
else
    echo "tablet CAIDA (reset): esperar 90 s y reintentar una vez."
    sleep 90
    ssh $SSH_OPTS -o ConnectTimeout=15 "$SSH" 'uptime' || echo "sigue caida: NO insistir (techo 1 ciclo); pasar a fastboot/vigia"
fi

# Cerrar capturas (lo recibido YA esta en disco) y estado despues.
kill $PID_DML $PID_TRP 2>/dev/null || true
wait 2>/dev/null || true
sync
ssh $SSH_OPTS -o ConnectTimeout=10 "$SSH" '/usr/local/bin/qbootctl 2>/dev/null || qbootctl' >"$QBT1" 2>&1 || echo "sin qbootctl-despues (tablet caida)"
BOOT1=$(ssh $SSH_OPTS -o ConnectTimeout=10 "$SSH" 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null || echo CAIDA)
echo "boot_id despues: $BOOT1"
if [ "$BOOT1" != "$BOOT0" ]; then
    echo "RESET CONFIRMADO (boot_id cambio): 1 reintento de slot gastado. Verificar con: fastboot getvar all (slot-retry-count:b esperado: $((RETRY_B - 1)))"
else
    echo "sin reset en la ventana (boot_id igual): 0 reintentos gastados."
fi

# Veredicto local (conteo entradas vs retornos; ultima linea manda).
python3 - "$TRP" <<'EOF'
import re, sys
trp = sys.argv[1]
ent = ret = 0
last_ent = last_ret = None
for line in open(trp, errors='replace'):
    if 'uke_w:' in line or 'uke_r:' in line:
        ent += 1; last_ent = line.strip()[-160:]
    if 'uke_w_ret:' in line or 'uke_r_ret:' in line:
        ret += 1; last_ret = line.strip()[-160:]
print(f"entradas={ent} retornos={ret}")
if ent == 0:
    print("VEREDICTO: FALLO DEL EXPERIMENTO (arnes no capturo; no concluir)")
elif ent > ret:
    print("VEREDICTO-A: BUS WEDGE (ultimo acceso SIN retorno)")
    print("ultima entrada:", last_ent)
else:
    print("VEREDICTO-B: APSS LIMPIO => FIRMWARE (todas con retorno)")
    print("ultimo retorno:", last_ret)
EOF
echo "dmesg-> $DML | trace-> $TRP | computar Delta a mano contra t0 (deferred probe timeout) y banda 7.2-7.45 s"
