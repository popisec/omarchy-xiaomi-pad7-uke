#!/bin/sh
# postprocess.sh de Megapixels 1.8.3 para la uke (22-oct-2026): en la tablet no hay dcraw/libraw, asi que el DNG se revela con
# uke-dng2jpg (balance gris, demosaico bilineal, sRGB) y ImageMagick lo pasa a JPEG. Argumentos de Megapixels: dir-rafaga nombre guardar-dng.
set -e
[ "$#" -eq 3 ] || { echo "Usage: $0 [burst-dir] [target-name] [save-dng]"; exit 2; }
BURST_DIR="$1"; TARGET_NAME="$2"; SAVE_DNG="$3"
MAIN_PICTURE="$BURST_DIR"/1
[ "$SAVE_DNG" = "1" ] && cp "$BURST_DIR"/1.dng "$TARGET_NAME.dng"
# rafaga (Megapixels guarda 0.dng, 1.dng, 2.dng...): uke-dng2jpg promedia las que tengan el mismo tamano (menos ruido)
if command -v uke-dng2jpg >/dev/null && ORIENT=$(set -- "$MAIN_PICTURE.dng"; for f in "$BURST_DIR"/*.dng; do [ "$f" = "$MAIN_PICTURE.dng" ] || set -- "$@" "$f"; done; uke-dng2jpg "$@" "$BURST_DIR/1.ppm"); then
	case "$ORIENT" in 2) ROT="-flop";; 3) ROT="-rotate 180";; 4) ROT="-flip";; 5) ROT="-transpose";; 6) ROT="-rotate 90";; 7) ROT="-transverse";; 8) ROT="-rotate 270";; *) ROT="";; esac	# EXIF de Megapixels (con espejo en la frontal)
	IM=magick; command -v magick >/dev/null || IM=convert
	$IM "$BURST_DIR/1.ppm" $ROT -sharpen 0x1.0 -quality 92 "$TARGET_NAME.jpg"
	echo "$TARGET_NAME.jpg"
else
	cp "$BURST_DIR"/1.dng "$TARGET_NAME.dng"
	echo "$TARGET_NAME.dng"
fi
rm -rf "$BURST_DIR"
