#!/usr/bin/env bash
# build-megapixels.sh — Megapixels 1.8.3 para la uke, compilado EN LA TABLET sin pacman (gtk4, libfeedback, zbar, libtiff, epoxy, meson, gcc ya
# estan; comprobado con pkg-config el 22-oct-2026). PREPARADO 22-oct-2026, NO EJECUTADO.
#   ./build-megapixels.sh --src       (solo PC) arma el tarball: tag 1.8.3 del repo oficial + 0001-mode-stride-16-qcom-camss.patch
#   ./build-megapixels.sh --build     sube el tarball y compila en /root/megapixels-1.8.3-uke (meson+ninja; no instala nada)
#   ./build-megapixels.sh --install   (necesita OK del duenio) meson install a /usr/local + xiaomi,uke.ini + schemas + postprocess de la uke
# Turno «camaras-2» en --build e --install. Host USB por defecto (UKE_HOST).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); R=$(cd "$HERE/../../../../.." && pwd)
HOST=${UKE_HOST:-root@192.168.42.129}; export UKE_HOST=$HOST
SSH=(ssh -o ConnectTimeout=8 -o ServerAliveInterval=10 -i "$R/build/rootfs/uke-arch-root" -o BatchMode=yes "$HOST")
TURNO="$R/build/rootfs/deploy/turno/uke-turno"
SRC=${MP_SRC:-$HOME/.cache/uke-megapixels/Megapixels}     # clon del repo oficial https://gitlab.com/megapixels-org/Megapixels
TAR=$HERE/megapixels-1.8.3-uke.tar.gz                      # no se versiona (.gitignore)
RD=/root/megapixels-1.8.3-uke
case "${1:-}" in
--src)
	[ -d "$SRC/.git" ] || git clone -q https://gitlab.com/megapixels-org/Megapixels.git "$SRC"
	[ "$(git -C "$SRC" rev-parse '1.8.3^{commit}')" = "$(cat "$HERE/MEGAPIXELS-VERSION")" ] || { echo "el tag 1.8.3 no es el commit de MEGAPIXELS-VERSION"; exit 2; }
	T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
	git -C "$SRC" archive --prefix=megapixels-1.8.3-uke/ 1.8.3 | tar xf - -C "$T"
	for p in "$HERE"/0*.patch; do patch -d "$T/megapixels-1.8.3-uke" -p1 < "$p"; done
	cp "$HERE/xiaomi,uke.ini" "$HERE/postprocess-uke.sh" "$HERE/uke-dng2jpg.c" "$HERE/uke-megapixels" "$T/megapixels-1.8.3-uke/"
	tar czf "$TAR" -C "$T" megapixels-1.8.3-uke; sha256sum "$TAR" | tee "$TAR.sha256"
	;;
--build)
	[ -s "$TAR" ] || { echo "falta $TAR (--src)"; exit 2; }
	"$TURNO" pedir --recurso sistema camaras-2 "compilar Megapixels 1.8.3 en /root (sin instalar)" ${TURNO_ESPERA:-5400} || { echo "sin turno: no se compila"; exit 3; }; trap '"$TURNO" soltar --recurso sistema camaras-2' EXIT
	"${SSH[@]}" "rm -rf $RD; mkdir -p /root" && "${SSH[@]}" "tar xzf - -C /root" < "$TAR"
	"${SSH[@]}" "cd $RD && meson setup build --prefix=/usr/local --buildtype=release -Dc_args=-Wno-error=incompatible-pointer-types >/root/mp-setup.log 2>&1 && nice -n 10 ninja -C build >/root/mp-build.log 2>&1; echo rc=\$?; tail -3 /root/mp-build.log;
		cc -O2 -Wall -o build/uke-dng2jpg uke-dng2jpg.c \$(pkg-config --cflags --libs libtiff-4) -lm && sync -f build/uke-dng2jpg && echo "uke-dng2jpg OK"; ls -l build/megapixels build/megapixels-list-devices build/uke-dng2jpg"
	;;
--install)
	"$TURNO" pedir --recurso sistema camaras-2 "instalar Megapixels 1.8.3 en /usr/local" ${TURNO_ESPERA:-5400} || { echo "sin turno: no se instala"; exit 3; }; trap '"$TURNO" soltar --recurso sistema camaras-2' EXIT
	"${SSH[@]}" "cd $RD && sync -f build/megapixels build/megapixels-list-devices build/uke-dng2jpg uke-megapixels postprocess-uke.sh && meson install -C build >/root/mp-install.log 2>&1; echo rc=\$?;
		install -Dm644 'xiaomi,uke.ini' '/usr/local/share/megapixels/config/xiaomi,uke.ini';
		install -Dm755 build/uke-dng2jpg /usr/local/bin/uke-dng2jpg; install -Dm755 uke-megapixels /usr/local/bin/uke-megapixels; sed -i 's|^Exec=megapixels|Exec=uke-megapixels|' /usr/local/share/applications/org.postmarketos.Megapixels.desktop; install -Dm755 postprocess-uke.sh /usr/local/share/megapixels/postprocess.sh;
		glib-compile-schemas /usr/local/share/glib-2.0/schemas; sync;
		cmp build/megapixels /usr/local/bin/megapixels && cmp build/uke-dng2jpg /usr/local/bin/uke-dng2jpg && echo 'binarios verificados (cmp)';
		ls /usr/local/share/megapixels/config/ | grep uke"
	;;
*) echo "uso: $0 --src | --build | --install"; exit 2 ;;
esac
