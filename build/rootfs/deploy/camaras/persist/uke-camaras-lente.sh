#!/usr/bin/env bash
# uke-camaras-lente.sh — mantiene ENCENDIDA la lente (VCM CN3927V, subdev dw9714) en un foco fijo: Megapixels 1.8.3 no maneja el foco y,
# sin nadie con el subdev abierto, el runtime PM apaga el VCM y la lente cae a reposo. PREPARADO 22-oct-2026, NO INSTALADO.
# Foco: /etc/uke/camaras.conf (FOCO=0..1023; ciclos 19-20: ~450-480 a ~0,5 m; valores bajos = lejos; 200 es una hipotesis para 1-2 m).
set -u
read -r L FOCO < /run/uke-camaras.lente || exit 0
exec 3<>"$L" || exit 1
v4l2-ctl -d "$L" -c focus_absolute="$FOCO" || exit 1
echo "uke-camaras-lente: $L en focus_absolute=$FOCO"
exec sleep infinity
