#!/bin/bash
# Compila quic/fastrpc (adsprpcd, libadsprpc, libadsp_default_listener) para aarch64 desde el PC, sin tocar la tablet.
# Reproduce lo hecho el 18-oct-2026 en E2b: clang (--target aarch64) + el sysroot aarch64 del rootfs (build/rootfs/staging) + gcc/libyaml/libbsd/libmd
# de ALARM (solo para crtbegin/libgcc y las libs; se descargan a un dir temporal y se comprueban por sha256).
# Salida: out/fastrpc-uke-<commit>.tar (usr/bin/adsprpcd, usr/lib/libadsp*.so*, usr/lib/systemd/system/adsprpcd_audiopd.service, usr/lib/sysusers.d/fastrpc.conf).
# NO instala nada en la tablet. Requiere en la tablet: libyaml (pacman -S libyaml; libbsd y libmd ya estan).
set -Eeuo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd); R=$(cd "$HERE/../../../.." && pwd)
SR=$R/build/rootfs/staging; REPO=https://github.com/quic/fastrpc; COMMIT=${COMMIT:-a56e9d4de3614a8d8f4b0e15ff561350c4b686e3}
M=http://fl.us.mirror.archlinuxarm.org/aarch64
W=${KEEP:-$(mktemp -d)}; [ -n "${KEEP:-}" ] || trap 'rm -rf "$W"' EXIT; mkdir -p "$W"
X=$W/extra
declare -A SHA=(
 [core/gcc-16.1.1%2Br12%2Bg301eb08fa2c5-1]=067a2aa64f5c7e626e3910fed6fd1f173a1fd9eb6bebaebdd7a7f5be58e170c4
 [extra/libbsd-0.12.2-2]=3d47f2e64ab9c2dfbdc5791ad7db237ed3c9708ad80718c26f4b850cf2b69238
 [extra/libmd-1.3.0-1]=e2f1090d6e3401da5655ac553398bd47338c4c6e39ac0ed684a9b4f33707354b
 [extra/libyaml-0.2.5-3]=f96d25c8898b27d3364034336630363bcf48eb968c90d5d5c240e4b237ae153b )
mkdir -p "$X" "$W/dl"
for f in "${!SHA[@]}"; do
  b=$(basename "$f"); curl -fsSL --max-time 300 -o "$W/dl/$b.pkg.tar.xz" "$M/$f-aarch64.pkg.tar.xz"
  [ "$(sha256sum "$W/dl/$b.pkg.tar.xz" | cut -d' ' -f1)" = "${SHA[$f]}" ] || { echo "sha distinto en $f"; exit 1; }
  tar -xf "$W/dl/$b.pkg.tar.xz" -C "$X" 2>/dev/null || true
done
G=$(echo "$X"/usr/lib/gcc/aarch64-unknown-linux-gnu/*)
echo "GROUP($X/usr/lib/libbsd.so.0.12.2 AS_NEEDED(-lmd))" > "$X/usr/lib/libbsd.so"   # el script de ld trae ruta absoluta
cat > "$W/cc.sh" <<EOS
#!/bin/bash
exec clang --target=aarch64-linux-gnu --sysroot=$SR --gcc-install-dir=$G -fuse-ld=lld -I$X/usr/include -L$X/usr/lib -Wno-unused-command-line-argument "\$@"
EOS
chmod +x "$W/cc.sh"
git clone -q "$REPO" "$W/src" && git -C "$W/src" checkout -q "$COMMIT"
(cd "$W/src" && bash autogen.sh >/dev/null 2>&1)
mkdir "$W/fb"; cd "$W/fb"
PKG_CONFIG_LIBDIR=$X/usr/lib/pkgconfig:$SR/usr/lib/pkgconfig CC=$W/cc.sh CFLAGS=-O2 \
  "$W/src/configure" --host=aarch64-linux-gnu --prefix=/usr --sysconfdir=/etc >"$W/configure.log" 2>&1
# libtool mete /usr/lib del PC en la busqueda: fijar la de aarch64
sed -i "s|^sys_lib_search_path_spec=.*|sys_lib_search_path_spec=\"$X/usr/lib $SR/usr/lib\"|; s|^sys_lib_dlsearch_path_spec=.*|sys_lib_dlsearch_path_spec=\"$X/usr/lib\"|" libtool
env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL MAKE=/usr/bin/make /usr/bin/make -j8 LIBS="-L$X/usr/lib -lyaml -lbsd -lmd" >"$W/make.log" 2>&1 || { tail -20 "$W/make.log"; exit 1; }
# sin `make install`: el relink de libtool llama al enlazador con el destino equivocado (x86-64) -> se toman los .libs ya enlazados
B=$W/fb/src; P=$W/pkg; mkdir -p "$P/usr/bin" "$P/usr/lib/systemd/system" "$P/usr/lib/sysusers.d"
install -m755 "$B/adsprpcd" "$P/usr/bin/adsprpcd"
cp -a "$B"/.libs/libadsp_default_listener.so* "$B"/.libs/libadsprpc.so* "$P/usr/lib/"
install -m644 "$W/src/files/fastrpc.conf" "$P/usr/lib/sysusers.d/fastrpc.conf"
sed 's|@sbindir@|/usr/bin|; s|/usr/sbin/adsprpcd|/usr/bin/adsprpcd|' "$W/fb/files/adsprpcd_audiopd.service" > "$P/usr/lib/systemd/system/adsprpcd_audiopd.service"
llvm-strip --strip-unneeded "$P/usr/bin/adsprpcd" "$P"/usr/lib/lib*.so.1.0.0
readelf -h "$P/usr/bin/adsprpcd" | grep -q AArch64 || { echo "no es aarch64"; exit 1; }
OUT=$HERE/out/fastrpc-uke-${COMMIT:0:8}.tar
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -C "$P" -cf "$OUT" .
sha256sum "$OUT"; tar -tvf "$OUT"
