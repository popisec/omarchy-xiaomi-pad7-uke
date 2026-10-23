#!/bin/bash
# flash-599.sh — #599: L21 + s278-nostrip + despliegue del módulo pwrseq + P4.
#
# FASE 1 (fastboot): espera a que la tablet aparezca, flashea boot_a=L21 +
#   dtbo_a=s278-nostrip, set_active a (lección #596) y reboot.
# FASE 2 (SSH): espera al SSH, despliega el .ko del pwrseq (hunk btgpio),
#   depmod, modprobe pwrseq → ath11k_ahb, y reporta el estado (card1, wifi,
#   watchdog-device).
#
# Uso: gates/flash-599.sh [fase1|fase2|all]   (default: all)
set -u
R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
B=$R/build/bootimg
BOOT=$B/boot-uke-k52L21.img
BOOT_SHA=7d178b019d25e5e071843ae9a50a2683209774eb577af91fb146d3270df7e131
DTBO=$B/s278-nostrip-boot-dtbo.img
DTBO_SHA=5fcfbc84aa0c5389e9e02780c55471322c6d789ab79e2b2f79a7211366aa5c22
KO=$R/build/kernel-pokes/k52L21-build/drivers/power/sequencing/pwrseq-qcom-wcn.ko
KO2=$R/build/kernel-pokes/k52L21-build/drivers/power/sequencing/pwrseq-pcie-m2.ko
SSH_CMD="$R/build/gates/uke-ssh.sh"
say() { echo "[$(date '+%H:%M:%S')] $*"; }

verify() { # verify <fichero> <sha>
    echo "$(sha256sum "$1" 2>/dev/null | cut -d' ' -f1)" == "$2" || { say "*** SHA MAL: $1"; exit 1; }
}

fase1() {
    verify "$BOOT" "$BOOT_SHA"; verify "$DTBO" "$DTBO_SHA"
    say "esperando fastboot (el drain o el usuario meten la tablet)..."
    for i in $(seq 1 1200); do
        fastboot devices 2>/dev/null | grep -q fastboot && break
        sleep 15
    done
    fastboot devices | grep -q fastboot || { say "sin fastboot tras 60 min"; exit 1; }
    say "flasheando boot_a=L21..."
    fastboot flash boot_a "$BOOT" | tail -2 || exit 1
    say "flasheando dtbo_a=s278-nostrip..."
    fastboot flash dtbo_a "$DTBO" | tail -2 || exit 1
    say "set_active a (contador a 7)..."
    fastboot set_active a | tail -1 || exit 1
    say "reboot..."
    fastboot reboot | tail -1
}

fase2() {
    say "esperando SSH..."
    for i in $(seq 1 30); do
        $SSH_CMD -i 2>/dev/null | grep -q "ssh: OK" && break
        sleep 15
    done
    $SSH_CMD -i | grep -q "ssh: OK" || { say "sin SSH"; exit 1; }
    say "desplegando módulos pwrseq L21..."
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i "$R/build/rootfs/uke-arch-root" "$KO" "$KO2" \
        root@192.168.42.129:/tmp/ 2>&1 | grep -v Warning
    $SSH_CMD 'D=/lib/modules/7.2.0-rc2-palawan/kernel/drivers/power/sequencing;
              mkdir -p $D; cp /tmp/pwrseq-qcom-wcn.ko /tmp/pwrseq-pcie-m2.ko $D/;
              depmod -a 7.2.0-rc2-palawan; echo deploy-OK' | tail -2
    say "estado display (card1 debe nacer con nostrip):"
    $SSH_CMD 'ls /dev/dri/; dmesg | grep -a "msm_dsi.*failed" | tail -2; echo ===watchdog===; ls /sys/class/watchdog/ 2>/dev/null; echo ===wifi===; modprobe pwrseq-qcom-wcn 2>&1; echo rc=$?; sleep 2; modprobe ath11k_ahb 2>&1; echo rc=$?; sleep 8; ip link | grep -c wlan; dmesg | grep -aE "UKE-WIFI|ath11k" | tail -6'
}

case "${1:-all}" in
    fase1) fase1 ;;
    fase2) fase2 ;;
    all)   fase1; fase2 ;;
    *) echo "uso: $0 [fase1|fase2|all]"; exit 2 ;;
esac
