#!/bin/bash
# leer-journal-wifi.sh check|run [arranque=-1] — SE EJECUTA EN EL PC. SOLO LECTURA (pendiente B7: WiFi/NM caido 21-oct 23:52, «NetworkManager is not running»).
# Vuelca a build/logs/wifi-caido-<fecha>.txt: lista de arranques, y del arranque pedido: NetworkManager, wpa_supplicant, tailscaled, ath11k/cfg80211,
# uke-wifi*, rfkill, OOM/segfault/coredump y las ultimas lineas antes del corte. Revert: nada (no escribe en la tablet).
set -u; . "$(dirname "$0")/lib.sh"
case "${1:-}" in
check) bash -n "$0" && echo "CHECK OK";;
run) B=${2:--1}; S true 2>/dev/null || die "tablet inalcanzable por $HOST (con el WiFi caido usa el USB: UKE_HOST=root@192.168.42.129)"; T=${T:-120}; OUT=$R/build/logs/wifi-caido-$(date +%Y%m%d-%H%M%S).txt; mkdir -p "$R/build/logs"
  { echo "== arranques =="; S 'journalctl --list-boots --no-pager 2>&1 | tail -8'
    echo "== arranque $B: resumen por unidad (NM/wpa/tailscale/uke-wifi) =="
    S "journalctl -b $B --no-pager -u NetworkManager -u wpa_supplicant -u tailscaled -u uke-wifi -u uke-wifi-nm -u uke-wifi-omarchy 2>&1 | grep -iE 'fail|error|stop|exit|killed|signal|timeout|not running|deactivat|disconnect|start' | tail -60"
    echo "== kernel: ath11k/cfg80211/rfkill/OOM/segfault =="
    S "journalctl -b $B --no-pager -k 2>&1 | grep -iE 'ath11k|cfg80211|rfkill|oom|out of memory|segfault|hung task|wlan0' | tail -40"
    echo "== coredumps recientes =="; S 'coredumpctl list --no-pager 2>&1 | tail -8'
    echo "== ultimas 40 lineas del arranque $B =="; S "journalctl -b $B --no-pager -n 40 2>&1 | cut -c1-200"
    echo "== estado actual =="; S 'systemctl is-active NetworkManager wpa_supplicant tailscaled uke-wifi 2>&1; iw dev wlan0 link 2>&1 | head -2'
  } | tee "$OUT"; echo "guardado: $OUT";;
*) echo "uso: $0 check|run [arranque, p.ej. -1]"; exit 2;;
esac
