#!/usr/bin/env bash
# Crea en la TABLET paquetes de vuelta atras (estilo bacman) de los paquetes instalados que la fase 1 va a actualizar.
# .PKGINFO generado desde `pacman -Qi`; ficheros tal como estan en disco. Salida: /root/syu-qt612-20261022/rollback/*.pkg.tar.zst
# Uso: mkrollback.sh   (desde el PC; escribe solo en /root de la tablet)
set -euo pipefail
K="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"/build/rootfs/uke-arch-root
ssh -i "$K" -o BatchMode=yes root@uke 'bash -s' <<'REMOTE'
set -euo pipefail
OUT=/root/syu-qt612-20261022/rollback; mkdir -p $OUT
for p in systemd systemd-libs systemd-sysvcompat systemd-resolvconf pacman openssh openssl util-linux util-linux-libs; do
  ver=$(pacman -Q $p | cut -d' ' -f2); arch=$(pacman -Qi $p | awk -F': *' '/^Architecture/{print $2}')
  W=$(mktemp -d); 
  { echo "pkgname = $p"; echo "pkgver = $ver"; echo "pkgdesc = rollback $p"; echo "arch = $arch"; echo "builddate = $(date +%s)"; echo "packager = rollback-uke"
    echo "size = $(pacman -Qi $p | awk -F': *' '/^Installed Size/{print int($2*1024)}')"
    pacman -Qi $p | awk -F': *' '/^Depends On/{n=split($2,a,"  "); for(i=1;i<=n;i++) if(a[i]!="None") print "depend = " a[i]}'
    pacman -Qi $p | awk -F': *' '/^Provides/{n=split($2,a,"  "); for(i=1;i<=n;i++) if(a[i]!="None") print "provides = " a[i]}'
    pacman -Qi $p | awk -F': *' '/^Conflicts With/{n=split($2,a,"  "); for(i=1;i<=n;i++) if(a[i]!="None") print "conflict = " a[i]}'
    pacman -Qi $p | awk -F': *' '/^Replaces/{n=split($2,a,"  "); for(i=1;i<=n;i++) if(a[i]!="None") print "replaces = " a[i]}'
  } > $W/.PKGINFO
  pacman -Qlq $p | grep -v '/$' | sed 's#^/##' > $W/files.lst
  tar --zstd -cf $OUT/$p-$ver-$arch.pkg.tar.zst -C / --no-recursion --ignore-failed-read -T $W/files.lst -C $W .PKGINFO 2>/dev/null || true
  rm -rf $W
  f=$OUT/$p-$ver-$arch.pkg.tar.zst
  [ -s "$f" ] && pacman -Qpi "$f" >/dev/null 2>&1 && echo "OK $(basename $f) $(du -h $f | cut -f1) ficheros=$(tar --zstd -tf $f | wc -l)" || echo "FALLO $f"
done
( cd $OUT && sha256sum *.pkg.tar.zst > SHA256SUMS ); ls $OUT | wc -l; du -sh $OUT
REMOTE
