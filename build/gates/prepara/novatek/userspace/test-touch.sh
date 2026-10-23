#!/bin/sh
# test-touch.sh — secuencia de verificación del táctil/lápiz tras la pantalla.
# Uso: sh test-touch.sh            (en la tablet; como root o con la regla
#                                   70-uke-input.rules / grupo input)
# No toca nada: solo lee y lista. Los pasos interactivos se imprimen al final.

echo "== 1. nodos /dev/input =="
ls -l /dev/input/event* 2>/dev/null

echo
echo "== 2. quién es quién (/proc/bus/input/devices, solo novatek) =="
grep -iA4 "novatek" /proc/bus/input/devices 2>/dev/null || echo "(sin novatek)"

echo
echo "== 3. properties por evento (bit 1 = INPUT_PROP_DIRECT) =="
for e in /dev/input/event*; do
    n=$(cat /sys/class/input/$(basename "$e")/device/name 2>/dev/null)
    p=$(cat /sys/class/input/$(basename "$e")/device/properties 2>/dev/null)
    echo "$e  name='$n'  properties=$p"
done

echo
echo "== 4. libinput list-devices (bloques novatek) =="
if command -v libinput >/dev/null 2>&1; then
    libinput list-devices 2>/dev/null | grep -iB2 -A12 novatek
else
    echo "(libinput no instalado: pacman -S libinput libinput-tools)"
fi

echo
echo "== 5. tablets que ve el compositor =="
if command -v hyprctl >/dev/null 2>&1; then
    hyprctl devices -j 2>/dev/null | python3 -c 'import json,sys;d=json.load(sys.stdin);print("tablets:",[t.get("name") for t in d.get("tablets",[])])' 2>/dev/null || hyprctl devices 2>/dev/null | sed -n '/Tablets/,/^$/p'
    echo "touchdevice:transform = $(hyprctl getoption input:touchdevice:transform 2>/dev/null | head -1)"
    echo "tablet:transform      = $(hyprctl getoption input:tablet:transform 2>/dev/null | head -1)"
else
    echo "(sin hyprctl: aún no hay sesión)"
fi

echo
echo "== siguientes pasos (interactivos) =="
cat <<'EOF'
  TÁCTIL   : evtest /dev/input/eventN            -> ABS_MT_* con 1..10 dedos
             libinput debug-events --device /dev/input/eventN
  LÁPIZ    : evtest /dev/input/eventP (NVTCapacitivePenM80p)
             libinput debug-events --device /dev/input/eventP  -> TABLET_TOOL
             wev  (dentro de la sesión Hyprland) -> zwp_tablet_tool_v2
  ESQUINAS : con la tablet apaisada, tocar las 4 esquinas y anotar (x,y) crudos;
             elegir transform (1/3) en hyprland-touch-pen.{conf,lua}
  APP      : GTK4 GestureStylus (Gdk.AxisUse.PRESSURE) / Krita / GIMP
EOF
