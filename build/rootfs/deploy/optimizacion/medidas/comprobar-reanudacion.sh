#!/bin/bash
# comprobar-reanudacion.sh — SE EJECUTA EN EL PC, SOLO LECTURA. Tras una suspension (s2idle, tapa o boton), comprueba que vuelve todo. 22-oct-2026.
# WiFi (NM conectado + IP), Tailscale (Running), tactil (uke-touch activo y uke-touchd no parado), lapiz (uke-lapiz), audio (PipeWire con sinks),
# Bluetooth (adaptador encendido), power_save del WiFi = el del perfil (gancho NM 90-uke-wifi-ps), refresco segun cargador, y la ultima suspension
# del journal (entrada/salida, IRQ que la desperto). Uso: comprobar-reanudacion.sh [espera_s=0]   (sale 1 si algo FALLA)
set -u; . "$(dirname "$0")/lib.sh"
sleep "${1:-0}"
S 'H="setpriv --reuid=1001 --regid=1001 --init-groups env XDG_RUNTIME_DIR=/run/user/1001"; f=0
ok() { if eval "$2" >/dev/null 2>&1; then echo "PASA  $1"; else echo "FALLA $1"; f=1; fi; }
r=$(cat /run/uke-last-resume 2>/dev/null); echo "ultima reanudacion: $(date -d @${r:-0} +%T 2>/dev/null) (hace $(( $(date +%s) - ${r:-0} )) s); wakeup_irq=$(cat /sys/power/pm_wakeup_irq 2>/dev/null) ($(grep -E "^ *$(cat /sys/power/pm_wakeup_irq 2>/dev/null):" /proc/interrupts | awk "{print \$NF}"))"
ok "wifi conectada (NM 100)" "[ \"\$(nmcli -t -g GENERAL.STATE device show wlan0 | cut -d\" \" -f1)\" = 100 ]"
ok "wifi con IPv4" "ip -4 addr show wlan0 | grep -q inet"
ok "tailscale Running" "tailscale status --json | grep -q \"\\\"BackendState\\\": \\\"Running\\\"\""
ok "uke-touch activo" "systemctl is-active --quiet uke-touch"
ok "uke-touchd no parado" "ps -o stat= -p \$(pgrep -f \"[u]ke-touchd\" | head -1) | grep -qv T"
ok "uke-lapiz activo" "systemctl is-active --quiet uke-lapiz"
ok "pipewire con sinks" "\$H wpctl status | sed -n \"/Sinks:/,/Sources:/p\" | grep -qE \"[0-9]+\\.\""
ok "bluetooth encendido" "bluetoothctl show | grep -q \"Powered: yes\""
. /etc/uke/perfiles.conf; case "$(cat /var/lib/uke-bateria/perfil)" in power-saver) ps=$P_ahorro_WIFI_PS;; performance) ps=$P_rendimiento_WIFI_PS;; *) ps=$P_equilibrado_WIFI_PS;; esac
ok "wifi power_save = $ps (perfil $(cat /var/lib/uke-bateria/perfil))" "iw dev wlan0 get power_save | grep -q \"Power save: $ps\""
[ "$(cat /sys/class/power_supply/qcom-battmgr-usb/online)" = 1 ] && hz=120 || hz=60
ok "refresco $hz Hz" "[ \"\$(\$H HYPRLAND_INSTANCE_SIGNATURE=\$(ls /run/user/1001/hypr | head -1) hyprctl monitors -j | jq -r \".[0].refreshRate|floor\")\" = $hz ]"
echo "--- ultima suspension (journal):"; journalctl -b --no-pager -o short --since -3h | grep -E "PM: suspend (entry|exit)|Lid (closed|opened)|Power key pressed|uke-wifi-resume|wakeup from IRQ" | tail -6
tail -2 /var/log/uke-bt.log 2>/dev/null
exit $f'
