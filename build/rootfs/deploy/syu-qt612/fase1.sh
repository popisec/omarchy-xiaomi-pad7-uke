#!/usr/bin/env bash
# FASE 1 del -Syu a Qt 6.12 en la tablet uke: TODO EL SISTEMA MENOS Qt (136 paquetes simulados el 22-oct-2026 con las DB de la tablet).
# NO EJECUTADO. Requiere: fase 0 hecha, orden del dueño (presente), «libre» de la sesión gestora y un hueco SIN otras sesiones.
# Uso: fase1.sh precheck | sim | run | verify | rollback-info      (desde el PC)
# `run` exige EJECUTAR=si en el entorno. No reinicia la tablet ni la sesión gráfica.
set -euo pipefail
REPO="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
K=$REPO/build/rootfs/uke-arch-root
T() { ssh -i "$K" -o BatchMode=yes -o ConnectTimeout=10 root@uke "$@"; }
BK=/root/syu-qt612-20261022
CONF0=$BK/pacman-syu.conf
CONF1=$BK/pacman-fase1.conf     # fase 0 + Qt congelado (mismos IgnorePkg + qt6-base/declarative/svg/wayland/translations)
QT="qt6-base qt6-declarative qt6-svg qt6-wayland qt6-translations"
# IGNORA_MESA=si congela mesa 26.2.4 (stack GPU freedreno/Adreno 732 del proyecto); simulado sin errores de dependencias (135 paquetes)
[ "${IGNORA_MESA:-}" = si ] && QT="$QT mesa"

case "${1:-}" in
precheck)   # solo lectura
  ping -c1 -W2 192.168.42.129 >/dev/null && echo "USB RNDIS accesible (respaldo)" || { echo "SIN USB RNDIS: no seguir"; exit 1; }
  T 'set -e; uptime; echo "bateria $(cat /sys/class/power_supply/*/capacity | head -1) %"; systemctl --failed --no-legend | tee /root/syu-qt612-20261022/failed-antes.txt; pgrep -a pacman && exit 1 || echo "sin pacman en marcha"
     test -f /root/syu-qt612-20261022/etc.tgz && echo "backup fase 0 presente"; ls /root/qs-new
     sha256sum /usr/bin/quickshell; pacman -Q systemd qt6-base quickshell omarchy mesa pacman | tr "\n" ";"; echo
     df -h / | tail -1; free -m | sed -n 2p'
  ;;
sim)        # muestra la transaccion exacta, sin instalar (usa la cache de la fase 0)
  T "set -e; grep -v '^IgnorePkg' $CONF0 | sed '/^\\[options\\]/a IgnorePkg = '\"\$(grep '^IgnorePkg' $CONF0 | sed 's/^IgnorePkg = //') $QT\" > $CONF1
     grep '^IgnorePkg' $CONF1
     pacman --config $CONF1 -Su --print --print-format '%n %v' | tee $BK/fase1-simulacion.txt | wc -l
     pacman --config $CONF1 -Su --print --print-format '%n %v' | grep -E '^(systemd|util-linux|openssh|openssl|pacman|mesa|python|polkit|mkinitcpio|qt6|quickshell|omarchy|hyprland)' | tr '\n' ';'; echo"
  ;;
conflictos) # solo lectura: ficheros del disco SIN dueño que chocan con los paquetes de la transaccion (guarda la lista en la tablet)
  T 'bash -s' <<'REMOTE'
set -u
B=/root/syu-qt612-20261022
cat /var/lib/pacman/local/*/files | grep -v '^%' | grep -v '^$' | sort -u > /tmp/owned.txt
pacman --config $B/pacman-fase1.conf -Su --print --print-format '%n-%v' > /tmp/tx.txt
: > /tmp/conf.txt
for pv in $(cat /tmp/tx.txt); do
  f=$(ls /var/cache/pacman/pkg/${pv}-*.pkg.tar.* 2>/dev/null | grep -v '\.sig$' | head -1)
  [ -z "$f" ] && { echo "NO EN CACHE: $pv"; continue; }
  tar -tf "$f" 2>/dev/null | grep -v '/$' | grep -v '^\.' | while read -r path; do
    if { [ -e "/$path" ] || [ -L "/$path" ]; } && ! grep -qxF "$path" /tmp/owned.txt; then echo "${pv%-*-*} $path" >> /tmp/conf.txt; fi
  done
done
cp /tmp/conf.txt $B/fase1-conflictos.txt; echo "conflictos: $(wc -l < /tmp/conf.txt) ficheros en $(cut -d' ' -f1 /tmp/conf.txt | sort -u | wc -l) paquetes"
REMOTE
  ;;
run)        # SOLO con EJECUTAR=si; el dueño debe estar presente. No reinicia.
  [ "${EJECUTAR:-}" = si ] || { echo "Falta EJECUTAR=si (orden explicita del dueño)"; exit 1; }
  "$0" precheck
  T "set -e; test -f $CONF1 || { echo 'falta $CONF1: ejecuta sim antes'; exit 1; }
     test -s $BK/fase1-conflictos.txt || { echo 'falta fase1-conflictos.txt: ejecuta conflictos antes'; exit 1; }
     OVW=\$(sed 's#^[^ ]* #/#' $BK/fase1-conflictos.txt | paste -sd,)   # SOLO los ficheros sin dueño que chocan (261 el 22-oct)
     OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman --config $CONF1 -Su --noconfirm --overwrite \"\$OVW\" 2>&1 | tail -60
     echo '--- pacnew/pacsave nuevos:'; find /etc -name '*.pacnew' -newer $CONF1 -o -name '*.pacsave' -newer $CONF1; sync"
  ;;
verify)     # tras `run`, antes de nada mas; sin reinicio
  T 'set -x; systemctl --failed --no-legend | diff - /root/syu-qt612-20261022/failed-antes.txt && echo "mismas unidades fallidas que antes"
     pacman -Q systemd systemd-libs util-linux openssh mesa qt6-base quickshell omarchy | tr "\n" ";"; echo
     systemctl is-system-running; systemctl is-active sshd NetworkManager wpa_supplicant bluetooth uke-bt uke-audio 2>&1 | tr "\n" " "; echo
     pgrep -a quickshell | head -1 | cut -c1-80; pgrep -a Hyprland | head -1; pgrep -a pipewire | head -1
     ip -br a | grep -E "usb0|wlan0"; dmesg --level=err,warn | tail -8
     pacman -Qkk 2>&1 | grep -v " 0 altered" | head -10'
  ;;
rollback-info)
  cat <<'R'
Vuelta atras fase 1 (parcial, solo si algo falla): en la cache de la tablet NO estan las versiones previas.
  - mesa 26.2.4-1, openssh 10.6p1-1, openssl 3.6.5-1, pacman 7.1.0.r9-2, util-linux(-libs) 2.42.4-1, systemd(-libs) 262-1:
    estan en $REPO/build/stage-escritorio/ (PC) -> scp a /root/rollback/ y `pacman -U` (los de 262-1 no son 261.2).
  - systemd 261.2-1: NO hay copia; el unico camino hacia atras es otro -U de un paquete 261.x bajado del archivo de ALARM.
  - Lista de lo instalado antes: /root/syu-qt612-20261022/pacman-Q.txt; ficheros de config: etc.tgz.
  - Si el sistema no arranca: USB/ACM como respaldo; la fase 1 NO toca kernel ni firmware.
R
  ;;
*) echo "uso: $0 precheck|sim|conflictos|run|verify|rollback-info"; exit 1;;
esac
