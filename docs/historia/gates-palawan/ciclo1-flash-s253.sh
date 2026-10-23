#!/usr/bin/env bash
# ciclo1-flash-s253.sh — EJECUTA la fila #P1 del PRE-REGISTRO-PANTALLA.md (s253, A′ del
# apps-smmu). Lo corre SOLO el orquestador, con la tablet en Arch por USB y TODOS los gates
# en verde. Canal: scp + dd a dtbo_b + relectura sha + reinicio sysrq-b (el que sí funciona).
#
# Uso:  docs/historia/gates-palawan/ciclo1-flash-s253.sh [--waiver-bateria]
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
IMG="$ROOT/build/bootimg/s253-boot-dtbo-aprima.img"
SHA="53653d1a8202d54e344c380b57bf11cbfa1ff322ef179c2d97811c9d687a0928"
HOST=192.168.42.129
KEY="$ROOT/build/rootfs/uke-arch-root"
SSH_OPTS=(-i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o ConnectTimeout=8 -o LogLevel=ERROR)
WAFER_BAT=no; [ "${1:-}" = "--waiver-bateria" ] && WAFER_BAT=si

die() { echo "GATE FALLIDO: $*" >&2; exit 1; }

echo "== gates previos =="
[ "$(sha256sum "$IMG" | cut -d' ' -f1)" = "$SHA" ] || die "sha del artefacto no coincide"
SIZE=$(stat -c%s "$IMG"); echo "  artefacto: sha OK ($SIZE B)"
ping -c1 -W2 "$HOST" >/dev/null 2>&1 || die "tablet no responde a ping (¿USB?)"
echo "  ping OK"
BAT=$(ssh "${SSH_OPTS[@]}" "root@$HOST" cat /sys/class/power_supply/qcom-battmgr-bat/voltage_now)
[ -n "$BAT" ] || die "no pude leer voltage_now"
if [ "$BAT" -lt 3700000 ] && [ "$WAFER_BAT" = "no" ]; then
  die "batería ${BAT} µV < gate 3700000 µV (usa --waiver-bateria si el dueño lo autoriza)"
fi
echo "  batería: ${BAT} µV (waiver: $WAFER_BAT)"
pgrep -f uke-console-cap.sh >/dev/null || die "no hay captura de consola corriendo (un solo lector)"
echo "  captura de consola: OK"
pgrep -f rescate-fastboot-pantalla.sh >/dev/null || die "el vigía de rescate no está armado"
[ -f /tmp/rescate-pantalla.pause ] && die "el vigía está en PAUSA (rm /tmp/rescate-pantalla.pause)"
echo "  rescate armado, sin pausa: OK"
KVER=$(ssh "${SSH_OPTS[@]}" "root@$HOST" uname -r)
echo "$KVER" | grep -q palawan || die "la tablet no corre el kernel palawan ($KVER)"
echo "  kernel: $KVER"
echo "  slot-retry ANTES: $(timeout 15 /opt/android-sdk/platform-tools/fastboot getvar slot-retry-count:b 2>&1 | head -1 || echo 'n/d (no está en fastboot, normal)')"

echo "== subida y verificación =="
scp "${SSH_OPTS[@]}" "$IMG" "root@$HOST:/root/s253.img"
RSHA=$(ssh "${SSH_OPTS[@]}" "root@$HOST" sha256sum /root/s253.img | cut -d' ' -f1)
[ "$RSHA" = "$SHA" ] || die "sha en tablet no coincide tras scp"

echo "== flash dd a dtbo_b + relectura =="
ssh "${SSH_OPTS[@]}" "root@$HOST" "dd if=/root/s253.img of=/dev/disk/by-partlabel/dtbo_b bs=1M conv=fsync && sync"
VSHA=$(ssh "${SSH_OPTS[@]}" "root@$HOST" "head -c $SIZE /dev/disk/by-partlabel/dtbo_b | sha256sum" | cut -d' ' -f1)
[ "$VSHA" = "$SHA" ] || die "RELECTURA no coincide ($VSHA) — NO reiniciar; restaurar s238 a mano"
echo "  relectura sha OK: dtbo_b = s253"

echo "== reinicio (sysrq-b) =="
ssh "${SSH_OPTS[@]}" "root@$HOST" "sync; sync; echo b > /proc/sysrq-trigger" || true
echo "  reinicio disparado ($(date '+%H:%M:%S')). Vigilar consola (captura activa) y esperar re-enum USB."

echo "== post: esperar vuelta y recoger evidencia =="
for i in $(seq 1 36); do   # hasta ~6 min
  sleep 10
  ping -c1 -W2 "$HOST" >/dev/null 2>&1 && break
  [ "$i" = 36 ] && { echo "  AVISO: sin ping a los 6 min — mirar consola/rescate; NO reintentar flash"; exit 3; }
done
echo "  tablet de vuelta ($(date '+%H:%M:%S'))"
sleep 15
ssh "${SSH_OPTS[@]}" "root@$HOST" \
  "dmesg | grep -iE 'arm-smmu 15000000|apps-smmu|iommu group|no IOMMU|bailing|msm_dpu|mdss|panel' | tail -40" \
  || true
echo "== fin: clasificar veredicto según PRE-REGISTRO #P1 =="
