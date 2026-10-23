#!/usr/bin/env bash
# FASE 2 del -Syu a Qt 6.12 en la tablet uke: Qt 6.12 (5 paquetes) + quickshell/omarchy 4.0.6 de Omarchy stable con -U EN LA MISMA ORDEN SSH.
# NO EJECUTADO. Requiere la fase 1 hecha y verificada, orden del dueño y un hueco sin otras sesiones.
# Uso: fase2.sh precheck | run | verify | rollback        (`run` y `rollback` exigen EJECUTAR=si)
# No reinicia la tablet. La barra se reinicia a mano (`omarchy-restart-shell`) cuando el dueño este delante.
set -euo pipefail
REPO="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
K=$REPO/build/rootfs/uke-arch-root
T() { ssh -i "$K" -o BatchMode=yes -o ConnectTimeout=10 root@uke "$@"; }
BK=/root/syu-qt612-20261022
CONF0=$BK/pacman-syu.conf
CONF2=$BK/pacman-fase2.conf     # = fase 0 (+ mesa ignorada si IGNORA_MESA=si, como en la fase 1)
MESA=""; [ "${IGNORA_MESA:-}" = si ] && MESA=" mesa"
QS=/root/qs-new
SHA_OMARCHY=27cd6d88fda0be6c269c14dd65dad6a014384fedc3ea4eb5c742b2b972b10494
SHA_SETTINGS=f653d97a7832eaa6b71dae1a6ce0480cb2631d6ca9a3350534a579cb08c6b309
SHA_QS=e1227d2930f84b78284cdffab8331e6a47632b2f65ee64945d785da1eb659fef
ST=$REPO/build/stage-escritorio   # paquetes Qt 6.11.2 y quickshell 0.3.2-3 del PC para el rollback

case "${1:-}" in
precheck)
  ping -c1 -W2 192.168.42.129 >/dev/null && echo "USB RNDIS accesible" || { echo "SIN USB: no seguir"; exit 1; }
  T "set -e; pacman -Q systemd | grep -q ' 262' && echo 'fase 1 aplicada (systemd 262)' || { echo 'FALTA la fase 1'; exit 1; }
     sed 's/^IgnorePkg = .*/&$MESA/' $CONF0 > $CONF2; grep '^IgnorePkg' $CONF2 | cut -c1-60,200-
     cd $QS && sha256sum -c <<<\"$SHA_OMARCHY  omarchy-4.0.6-1-aarch64.pkg.tar.zst
$SHA_SETTINGS  omarchy-settings-4.0.6-1-aarch64.pkg.tar.zst
$SHA_QS  quickshell-0.3.2.r7.g2b4501a-1-aarch64.pkg.tar.zst\"
     pacman --config $CONF2 -Su --print --print-format '%n %v' | tr '\n' ';'; echo
     ls $BK/qt6-base-*.files.tgz $BK/quickshell-*.files.tgz"
  ;;
run)
  [ "${EJECUTAR:-}" = si ] || { echo "Falta EJECUTAR=si (orden explicita del dueño)"; exit 1; }
  "$0" precheck
  # Una sola orden SSH: si falla el -Su no se hace el -U y al reves se avisa; no se reinicia nada.
  T "set -e
     OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman --config $CONF2 -Su --noconfirm 2>&1 | tail -40
     pacman -U --noconfirm $QS/quickshell-0.3.2.r7.g2b4501a-1-aarch64.pkg.tar.zst $QS/omarchy-4.0.6-1-aarch64.pkg.tar.zst $QS/omarchy-settings-4.0.6-1-aarch64.pkg.tar.zst 2>&1 | tail -40
     sync; pacman -Q qt6-base quickshell omarchy omarchy-settings | tr '\n' ';'; echo"
  ;;
verify)
  T 'set -x; quickshell --version; strings /usr/bin/quickshell | grep -c "Qt_6.12" || true; quickshell --private-check-compat 2>&1 | tail -3 || true
     pacman -Q qt6-base qt6-declarative quickshell omarchy | tr "\n" ";"; echo
     head -3 /usr/share/omarchy/shell/shell.qml; grep -c "OmarchyLoadPatch" /usr/share/omarchy/shell/shell.qml
     pgrep -a quickshell | head -1 | cut -c1-80; systemctl --failed --no-legend'
  echo "Siguiente (con el dueño delante): ssh ... 'omarchy-restart-shell' y comprobar barra, teclado en pantalla y lanzador; si falla -> rollback."
  ;;
rollback)   # vuelve a Qt 6.11.2 + quickshell 0.3.2-3 + omarchy 4.0.4 desde los paquetes del PC (NO toca systemd/mesa)
  [ "${EJECUTAR:-}" = si ] || { echo "Falta EJECUTAR=si"; exit 1; }
  T "mkdir -p /root/rollback2"
  scp -i "$K" -o BatchMode=yes "$ST"/qt6-base-6.11.2-3-aarch64.pkg.tar.xz "$ST"/qt6-declarative-6.11.2-2-aarch64.pkg.tar.xz "$ST"/qt6-svg-6.11.2-1-aarch64.pkg.tar.xz "$ST"/qt6-wayland-6.11.2-1-aarch64.pkg.tar.xz "$ST"/qt6-translations-6.11.2-1-any.pkg.tar.xz "$ST"/quickshell-0.3.2-3-aarch64.pkg.tar.zst "$ST"/omarchy-4.0.4-2-aarch64.pkg.tar.zst "$ST"/omarchy-settings-4.0.4-6-aarch64.pkg.tar.zst root@uke:/root/rollback2/
  T "cd /root/rollback2 && OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -U --noconfirm *.pkg.tar.* 2>&1 | tail -30; sync; omarchy-restart-shell || true"
  echo "Si ni asi: tar xzf $BK/qt6-*-6.11.*.files.tgz y quickshell-0.3.2-3.files.tgz con -C / (restaura ficheros) y revisar USB/ACM."
  ;;
*) echo "uso: $0 precheck|run|verify|rollback"; exit 1;;
esac
