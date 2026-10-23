#!/bin/bash
# bt-medir.sh — EN LA TABLET (como root): mide la tasa de fallo del PRIMER comando del WCN6750 (0xfc00) con distintos tiempos del hci_uart parcheado
# (hciqca/hci_qca-uke-tiempos.patch) y, opcionalmente, con carga de WiFi o de CPU de fondo. Un «ciclo» = uke-bt-up.sh --down + pausa + encendido de UN solo ciclo
# (UKE_BT_CYCLES=1: 4 intentos del driver como mucho). Las configuraciones se intercalan en ORDEN ALEATORIO por ronda (evita que la deriva térmica o de arranque
# se confunda con el efecto). Deja el BT encendido con los valores por defecto al terminar (o al abortar).
#
#   bt-medir.sh [-n RONDAS] [-c "L:B:S L:B:S ..."] [-w] [-l] [-o LOG] [--dry-run]
#     -n   rondas (cada ronda hace un ciclo por configuracion; por defecto 20)
#     -c   configuraciones L:B:S = uke_bt_low_ms:uke_bt_boot_ms:uke_bt_swctrl_ms (por defecto "50:50:0 50:150:0 50:300:0 50:50:300")
#          50:50:0 = valores de serie (CONTROL); S>0 sondea SW_CTRL hasta S ms y REGISTRA a los cuantos us subio (mide el arranque del chip)
#     -w   trafico y escaneos WiFi de fondo (simula la actividad del arranque); -l  carga de CPU de fondo
#     -o   fichero de registro (por defecto /root/bt-medir-<fecha>.log)
#     --dry-run   solo imprime el plan y las ordenes; no toca nada
# Requiere: el hci_uart PARCHEADO instalado en extra/ (si no, `modprobe hci_uart uke_bt_*=` falla y se aborta con un mensaje claro).
# Formato de salida (una linea por ciclo):  CICLO ronda=R cfg=L:B:S rc=0 timeouts=T ok=1 rise_us=N dur_s=D   (rise_us = '-' si no se sondeo / no subio)
# Analisis en el PC:  python3 hciqca/analiza-medicion.py LOG [--control 50:50:0]
set -u
UP=${BT_UP:-/usr/local/sbin/uke-bt-up.sh}
N=20; CONFIGS="50:50:0 50:150:0 50:300:0 50:50:300"; WIFI=0; CPU=0; DRY=0; LOG=/root/bt-medir-$(date +%Y%m%d-%H%M%S).log
while [ $# -gt 0 ]; do case "$1" in
	-n) N=${2:?-n N}; shift ;; -c) CONFIGS=${2:?-c "L:B:S ..."}; shift ;; -w) WIFI=1 ;; -l) CPU=1 ;; -o) LOG=${2:?-o fichero}; shift ;; --dry-run) DRY=1 ;;
	-h|--help) awk 'NR>1 && /^set -u/{exit} NR>1' "$0"; exit 0 ;; *) echo "uso: $0 [-n N] [-c cfgs] [-w] [-l] [-o log] [--dry-run]" >&2; exit 1 ;; esac; shift; done
case "$N" in ''|*[!0-9]*|0) echo "-n debe ser un entero > 0" >&2; exit 1 ;; esac
for c in $CONFIGS; do case "$c" in [0-9]*:[0-9]*:[0-9]*) ;; *) echo "configuracion invalida '$c' (L:B:S)" >&2; exit 1 ;; esac; done
opts() { local L B S; IFS=: read -r L B S <<<"$1"; echo "uke_bt_low_ms=$L uke_bt_boot_ms=$B uke_bt_swctrl_ms=$S"; }
log() { echo "$*" | tee -a "$LOG"; }
if [ "$DRY" = 1 ]; then
	echo "PLAN: $N rondas x $(echo $CONFIGS | wc -w) configuraciones (orden aleatorio por ronda) = $((N * $(echo $CONFIGS | wc -w))) ciclos; WiFi de fondo=$WIFI CPU de fondo=$CPU; log=$LOG"
	for c in $CONFIGS; do echo "  cfg $c -> UKE_BT_CYCLES=1 UKE_BT_HCI_OPTS=\"$(opts $c)\" $UP --service   (precedido de: $UP --down; sleep 2)"; done
	echo "  al final: $UP --down; UKE_BT_CYCLES=3 $UP --service   (valores por defecto)"; exit 0
fi
[ "$(id -u)" = 0 ] || { echo "hace falta root" >&2; exit 1; }
modinfo -F parm hci_uart 2>/dev/null | grep -q uke_bt_boot_ms || { echo "el hci_uart instalado NO es el parcheado (falta el parametro uke_bt_boot_ms): instala hciqca/out-hciqca/hci_uart.ko en /usr/lib/modules/\$(uname -r)/extra/ y depmod -a" >&2; exit 2; }
BG=""
cleanup() { for p in $BG; do kill "$p" 2>/dev/null; done; wait 2>/dev/null; log "# restaurando: encendido con los valores por defecto"; "$UP" --down >/dev/null 2>&1; sleep 2; UKE_BT_CYCLES=3 "$UP" --service 2>&1 | tail -2 | sed 's/^/# /' | tee -a "$LOG"; }
trap cleanup EXIT
trap 'echo "abortado"; exit 130' INT TERM
dmesg -n 7; sync
log "# bt-medir $(date -Is) kernel=$(uname -r) rondas=$N configs='$CONFIGS' wifi=$WIFI cpu=$CPU"
if [ "$WIFI" = 1 ]; then
	GW=$(ip route | awk '/default/{print $3; exit}')
	[ -n "$GW" ] && { ping -i 0.02 -q "$GW" >/dev/null 2>&1 & BG="$BG $!"; }
	( while :; do wpa_cli -i wlan0 scan >/dev/null 2>&1; sleep 1; done ) & BG="$BG $!"
	log "# carga WiFi de fondo: ping -i 0.02 $GW + escaneos"
fi
if [ "$CPU" = 1 ]; then for i in $(seq "$(nproc)"); do ( while :; do :; done ) & BG="$BG $!"; done; log "# carga de CPU de fondo: $(nproc) bucles"; fi
FAULT_RE='smmu.*fault|Unhandled fault|Oops|BUG:|hung task|rcu.*stall|iommu.*fault'
for r in $(seq 1 "$N"); do
	for c in $(echo $CONFIGS | tr ' ' '\n' | shuf); do
		"$UP" --down >/dev/null 2>&1; sleep 2
		mark=$(dmesg | wc -l); t0=$(date +%s.%N)
		out=$(UKE_BT_CYCLES=1 UKE_BT_HCI_OPTS="$(opts "$c")" timeout 150 "$UP" --service 2>&1); rc=$?
		t1=$(date +%s.%N); new=$(dmesg | tail -n +$((mark + 1)))
		to=$(grep -c '0xfc00 tx timeout' <<<"$new"); ok=$(grep -c 'QCA setup on UART is completed' <<<"$new"); [ "$ok" -gt 0 ] && ok=1
		rise=$(grep -m1 -o 'SW_CTRL=[01] a los [0-9]* us' <<<"$new" | sed 's/.* a los //; s/ us//'); [ -n "$rise" ] || rise=-
		if grep -q 'modprobe hci_uart fallo' <<<"$out"; then log "# FALLO: modprobe hci_uart con opciones rechazadas: $(grep -m1 'hci_uart fallo' <<<"$out" | cut -c1-160)"; exit 2; fi
		log "CICLO ronda=$r cfg=$c rc=$rc timeouts=$to ok=$ok rise_us=$rise dur_s=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.1f", b - a}')"
		if grep -qiE "$FAULT_RE" <<<"$new"; then log "# FAULT en el kernel durante el ciclo: parado"; grep -iE "$FAULT_RE" <<<"$new" | head -3 | sed 's/^/# /' | tee -a "$LOG"; exit 3; fi
	done
done
log "# FIN $(date -Is)"
echo "--- resumen rapido (analisis completo en el PC: python3 hciqca/analiza-medicion.py $LOG)"
awk '/^CICLO/{c=$3; n[c]++; split($5,a,"="); split($6,b,"="); if (a[2]==0 && b[2]==1) f[c]++; if (b[2]==0) m[c]++} END{for (c in n) printf "  %-12s ciclos=%d  1.er intento OK=%d (%.0f%%)  mudos=%d\n", c, n[c], f[c], 100*f[c]/n[c], m[c]}' "$LOG" | sort
