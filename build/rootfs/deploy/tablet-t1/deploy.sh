#!/bin/bash
# T1 + T6a: tamaños táctiles, gesto de espacios, hypridle sin lock, % de batería.
# Uso: deploy.sh apply|revert   (por SSH a la tablet; no toca boot/dtbo ni reinicia Hyprland)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
KEY=$HERE/../../uke-arch-root
T="ssh -i $KEY -o BatchMode=yes root@192.168.42.129"
cmd=${1:-}
OM=/home/omarchy
RUN='ID=$(id -u omarchy); export XDG_RUNTIME_DIR=/run/user/$ID; SIG=$(ls $XDG_RUNTIME_DIR/hypr|head -1)
S="sudo -u omarchy env XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR HYPRLAND_INSTANCE_SIGNATURE=$SIG WAYLAND_DISPLAY=wayland-1 OMARCHY_PATH=/usr/share/omarchy PATH=/usr/local/bin:/usr/bin"'
case $cmd in
apply)
  D=$(date +%Y%m%d-%H%M)
  $T "tar czf /root/backup-t1-$D.tgz -C / --ignore-failed-read home/omarchy/.config/omarchy/shell.toml home/omarchy/.config/hypr/looknfeel.lua home/omarchy/.config/hypr/hypridle.conf home/omarchy/.config/systemd/user/uke-hypridle.service"
  scp -i $KEY -o BatchMode=yes $HERE/files/* root@192.168.42.129:/root/
  $T "$RUN
  install -o omarchy -g omarchy -m644 /root/shell.toml $OM/.config/omarchy/shell.toml
  install -o omarchy -g omarchy -m644 /root/looknfeel.lua $OM/.config/hypr/looknfeel.lua
  install -o omarchy -g omarchy -m644 /root/hypridle.conf $OM/.config/hypr/hypridle.conf
  \$S mkdir -p $OM/.config/systemd/user
  install -o omarchy -g omarchy -m644 /root/uke-hypridle.service $OM/.config/systemd/user/
  \$S systemctl --user daemon-reload
  \$S systemctl --user enable --now uke-hypridle.service
  sleep 2; \$S hyprctl configerrors; echo '(configerrors arriba, vacío = OK)'
  \$S omarchy restart shell"
  echo "Batería %: botón derecho en el icono de batería, o: qs ipc -n -p /usr/share/omarchy/shell call omarchy.power togglePercentage (alterna; comprobar showPercentage en shell.json)";;
revert)
  F=${2:?uso: deploy.sh revert /root/backup-t1-<fecha>.tgz}
  $T "$RUN
  \$S systemctl --user disable --now uke-hypridle.service || true
  rm -f $OM/.config/systemd/user/uke-hypridle.service $OM/.config/hypr/hypridle.conf
  tar xzf $F -C /
  chown omarchy:omarchy $OM/.config/omarchy/shell.toml $OM/.config/hypr/looknfeel.lua
  \$S systemctl --user daemon-reload; sleep 1; \$S hyprctl configerrors; \$S omarchy restart shell";;
*) echo "uso: $0 apply | revert <backup.tgz>"; exit 1;;
esac
