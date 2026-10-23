#!/bin/bash
# paso: ¿desde que distancia al borde arranca el deslizamiento nativo de Hyprland (1 dedo, workspace_swipe_touch)?
# Dos apps de prueba en escritorios distintos; trazos de 1 dedo hacia dentro empezando a X px fisicos del borde izquierdo.
HERE=$(cd "$(dirname "$0")" && pwd)
KEY=$(cd "$HERE/../../../.." && pwd)/build/rootfs/uke-arch-root
for f in mt-inject.py osk-entry.py; do ssh -i "$KEY" -o BatchMode=yes root@uke "cat > /tmp/$f" < "$HERE/$f"; done
{ cat <<'PRE'
export XDG_RUNTIME_DIR=/run/user/1001 HOME=/home/omarchy USER=omarchy WAYLAND_DISPLAY=wayland-1 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1001/hypr | head -1) LANG=C.UTF-8 OMARCHY_PATH=/usr/share/omarchy
export PATH=/usr/share/omarchy/bin:/usr/local/bin:/usr/bin
PRE
cat <<'REMOTE'
cd /tmp
actws() { hyprctl activeworkspace -j | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])'; }
python3 -I /tmp/osk-entry.py --sin-campo >/dev/null 2>&1 & A=$!; sleep 2
python3 -I /tmp/osk-entry.py >/dev/null 2>&1 & B=$!; sleep 2
omarchy-shell omarkyy.tablet hide >/dev/null 2>&1
for X in 3 8 15 25 40 70; do
  w0=$(actws)
  python3 -I /tmp/mt-inject.py --path-file /tmp/mt.path --wait 1.2 "path:$X,1300;$((X+400)),1300;$((X+1100)),1300" >/dev/null 2>&1; sleep 1
  w1=$(actws); echo "borde izq. a $X px fisicos: escritorio $w0 -> $w1 $([ "$w0" != "$w1" ] && echo CAMBIA || echo igual)"
  [ "$w0" != "$w1" ] && hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = $w0 }))" >/dev/null && sleep 0.8
done
kill $A $B
REMOTE
} | ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=10 root@uke 'setpriv --reuid=1001 --regid=1001 --init-groups bash -s'
