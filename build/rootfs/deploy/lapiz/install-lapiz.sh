#!/bin/sh
# install-lapiz.sh — instala el modo lapiz PERMANENTE en la tablet. NO EJECUTAR SIN AUTORIZACION DEL DUENO.
# Uso (en el PC):  build/rootfs/deploy/lapiz/install-lapiz.sh [--dry-run] [--uninstall]
# Hace: (1) pruebas offline, (2) construye uke-touchd-pen.py aplicando uke-touchd-pen.patch a tactil/uke-touchd.py, (3) copia modulos,
# la copia parcheada, las unidades y el drop-in a la tablet, con copia de seguridad en /root/lapiz-bak-<fecha>, (4) NO arranca nada:
# la activacion es `systemctl daemon-reload && systemctl restart uke-touch && systemctl enable --now uke-lapiz` (o reiniciar).
# Reversion: --uninstall (quita el drop-in y la unidad; el servicio original queda como estaba) o `touch /etc/uke/no-pen`.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
KEY=${UKE_KEY:-$HERE/../../uke-arch-root}
HOST=${UKE_HOST:-root@uke}      # por Tailscale (orden del dueno 20-oct); USB de respaldo: UKE_HOST=root@192.168.42.129
SSH="ssh -i $KEY -o BatchMode=yes $HOST"
SCP="scp -q -i $KEY -o BatchMode=yes"
DRY=0; UNINSTALL=0
for a in "$@"; do case "$a" in --dry-run) DRY=1;; --uninstall) UNINSTALL=1;; *) echo "opcion desconocida $a"; exit 2;; esac; done
run() { if [ $DRY = 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }
if [ $UNINSTALL = 1 ]; then
  run $SSH 'systemctl disable --now uke-lapiz 2>/dev/null; rm -f /etc/systemd/system/uke-lapiz.service /etc/systemd/system/uke-touch.service.d/pen.conf; rmdir /etc/systemd/system/uke-touch.service.d 2>/dev/null; systemctl daemon-reload; U1=$(id -u omarchy); sudo -u omarchy env XDG_RUNTIME_DIR=/run/user/$U1 systemctl --user disable --now uke-pen-sync.path uke-pen-sync.service 2>/dev/null; rm -f /home/omarchy/.config/systemd/user/uke-pen-sync.path /home/omarchy/.config/systemd/user/uke-pen-sync.service /usr/local/bin/uke-pen-sync; sudo -u omarchy env XDG_RUNTIME_DIR=/run/user/$U1 systemctl --user daemon-reload; echo "desinstalado (reiniciar uke-touch para volver al demonio original)"'
  exit 0
fi
echo "== pruebas offline"; (cd "$HERE" && PYTHONPATH=. python3 -W error -m unittest test_touchd_pen_smoke test_uke_lapiz_ble test_uke_pen test_lapiz) && (cd "$HERE/desktop" && PYTHONPATH=..:. python3 -W error -m unittest test_desktop)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cp "$HERE/../tactil/uke-touchd.py" "$TMP/uke-touchd-pen.py"
patch -p0 -s "$TMP/uke-touchd-pen.py" < "$HERE/uke-touchd-pen.patch"
patch -p0 -s "$TMP/uke-touchd-pen.py" < "$HERE/desktop/uke-touchd-palm.patch"      # rechazo de palma (20-oct)
python3 -m py_compile "$TMP/uke-touchd-pen.py"
echo "== sha256 de lo que se instala"; (cd "$HERE" && sha256sum thp_pen.py lapiz_ble.py uke_pen.py uke_lapiz_ble.py systemd/* desktop/uke-pen-sync desktop/systemd/*) ; sha256sum "$TMP/uke-touchd-pen.py"
D=/root/lapiz-bak-$(date +%Y%m%d-%H%M%S)
run $SSH "mkdir -p $D /usr/local/share/uke/lapiz /etc/systemd/system/uke-touch.service.d && cp -a /usr/local/share/uke/lapiz /usr/local/share/uke/tactil/uke-touchd-pen.py /etc/systemd/system/uke-lapiz.service /etc/systemd/system/uke-touch.service.d $D/ 2>/dev/null || true"
run $SCP "$HERE/thp_pen.py" "$HERE/lapiz_ble.py" "$HERE/uke_pen.py" "$HERE/uke_lapiz_ble.py" "$HERE/README.md" $HOST:/usr/local/share/uke/lapiz/
run $SCP "$TMP/uke-touchd-pen.py" $HOST:/usr/local/share/uke/tactil/uke-touchd-pen.py
run $SCP "$HERE/systemd/uke-lapiz.service" $HOST:/etc/systemd/system/uke-lapiz.service
run $SCP "$HERE/systemd/pen.conf" $HOST:/etc/systemd/system/uke-touch.service.d/pen.conf
# rotacion del lapiz (uke-pen-sync + unidades de USUARIO de omarchy)
run $SCP "$HERE/desktop/uke-pen-sync" $HOST:/usr/local/bin/uke-pen-sync
run $SSH 'chmod 755 /usr/local/bin/uke-pen-sync; U=/home/omarchy/.config/systemd/user; mkdir -p $U && chown omarchy:omarchy $U'
run $SCP "$HERE/desktop/systemd/uke-pen-sync.service" "$HERE/desktop/systemd/uke-pen-sync.path" $HOST:/home/omarchy/.config/systemd/user/
run $SSH 'chown omarchy:omarchy /home/omarchy/.config/systemd/user/uke-pen-sync.*; U1=$(id -u omarchy); sudo -u omarchy env XDG_RUNTIME_DIR=/run/user/$U1 systemctl --user daemon-reload; sudo -u omarchy env XDG_RUNTIME_DIR=/run/user/$U1 systemctl --user enable --now uke-pen-sync.path; sudo -u omarchy env XDG_RUNTIME_DIR=/run/user/$U1 systemctl --user enable uke-pen-sync.service'
run $SSH 'systemctl daemon-reload; systemctl cat uke-touch | tail -8'
echo "Instalado SIN activar. Para activar: systemctl restart uke-touch && systemctl enable --now uke-lapiz   (vuelta atras: install-lapiz.sh --uninstall, o touch /etc/uke/no-pen)"
