#!/bin/bash
# test-ukeinit-v8a.sh — 23-oct-2026. Simulacion EN EL PC del bloque de montaje del /ukeinit de v8a (V8-FSCK + V8-MNT).
# Ejecuta el texto REAL del ukeinit (desde «S123: raiz candidata» hasta el switch_root) con el busybox ash DEL CPIO
# bajo qemu-aarch64 y el e2fsck aarch64 DEL CPIO (qemu-aarch64 -L <cpio extraido>) sobre imagenes ext reales:
#   - ext2-features igual que sda32 (sin has_journal), limpio / sucio+errores / corrupto
#   - con has_journal (ext3)
# El reloj se simula como en la tablet en el initramfs (rtc-pm8xxx: 1970-01-06, E2FSCK_TIME=514245).
# `mount` es un STUB (sin root no se puede montar): se prueban los 3 caminos (ro OK / ro falla->ro,noload / ambos fallan).
# El comportamiento del KERNEL (ext4 'ro' sin noload) NO se prueba aqui (ver informe).
# Uso: bash build/gates/test-ukeinit-v8a.sh   (sale 0 si todo PASA)
set -uo pipefail
R=/home/USUARIO/proyectos/omarchy-uke
CPIO=$R/build/kernel-pokes/optim-ouke6/v8a/uke-k34-fw-v8a-initramfs.cpio.gz
W=$(mktemp -d /tmp/v8a-test.XXXXXX)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/root" "$W/pop/sbin"
(cd "$W/root" && gzip -dc "$CPIO" | cpio -idm --quiet)
printf '#!/bin/sh\n' > "$W/pop/sbin/init"; chmod +x "$W/pop/sbin/init"
Q=$(command -v qemu-aarch64)
BB="$Q $W/root/bin/busybox"
# wrapper: el e2fsck aarch64 del cpio (con sus libs) sobre la imagen; reloj de 1970 como en el initramfs
cat > "$W/e2fsck" <<EOF
#!/bin/sh
exec env LD_LIBRARY_PATH=/lib E2FSCK_TIME=514245 $Q -L $W/root $W/root/bin/e2fsck "\$@"
EOF
chmod +x "$W/e2fsck"
# bloque real del ukeinit nuevo
awk '/^if \[ -n "\$UBUNTU" \] && \[ "\$max" -gt 20000000 \]/{f=1} f{print} f&&/^fi$/{exit}' "$W/root/ukeinit" > "$W/bloque.sh"
grep -q 'V8-FSCK' "$W/bloque.sh" && grep -q 'V8-MNT' "$W/bloque.sh" || { echo "no encuentro el bloque V8"; exit 1; }

mkimg() {  # $1 nombre, $2 tipo mke2fs
  mke2fs -q -F -t "$2" -d "$W/pop" "$W/$1.img" 64M
}
fallos=0
caso() {  # $1 descripcion, $2 imagen, $3 modo mount stub (ok|rofail|allfail), $4 con_e2fsck (1|0), $5 regex esperado (kmsg)
  local desc=$1 img=$2 modo=$3 con=$4 want=$5
  local E2F="$W/e2fsck"; [ "$con" = 1 ] || E2F="$W/no-existe-e2fsck"
  sed -e "s#/bin/e2fsck#$E2F#g" -e 's#exec busybox switch_root /mnt/ubuntu /sbin/init#echo "SWITCH_ROOT /mnt/ubuntu"; exit 0#' \
      -e 's#/dump-log.sh#true#' -e 's#busybox killall telnetd#true#' -e "s#/mnt/ubuntu#$W/mnt#g" -e "s#/tmp/fsck-v8.log#$W/fsck-v8.log#g" \
      "$W/bloque.sh" > "$W/caso.sh"
  cat > "$W/harness.sh" <<EOF
kmsg() { echo "KMSG \$*"; }
mount() {
  case "\$*" in
    *"-o ro,noload "*) [ "$modo" = allfail ] && return 32; echo "MOUNT \$*"; mkdir -p $W/mnt/sbin; cp $W/pop/sbin/init $W/mnt/sbin/; return 0 ;;
    *"-o ro "*)        [ "$modo" = ok ] || return 32; echo "MOUNT \$*"; mkdir -p $W/mnt/sbin; cp $W/pop/sbin/init $W/mnt/sbin/; return 0 ;;
    *remount*)         echo "MOUNT \$*"; return 0 ;;
  esac; return 1; }
umount() { echo "UMOUNT \$*"; }
sync() { :; }
UBUNTU="..$W/$img"; max=110000000
$(cat "$W/caso.sh")
echo "FIN-SIN-SWITCH (fallback fork)"
EOF
  rm -rf "$W/mnt"
  local out; out=$(PATH=/usr/bin:/bin $BB ash "$W/harness.sh" 2>&1)
  local okc=1 pat
  IFS=$'\x1f' read -r -a pats <<< "${want//|||/$'\x1f'}"
  for pat in "${pats[@]}"; do echo "$out" | grep -Eq -- "$pat" || { okc=0; echo "      (falta: $pat)"; }; done
  if [ $okc = 1 ]; then echo "PASA  $desc"; else echo "FALLA $desc"; fallos=$((fallos+1)); fi
  echo "$out" | sed 's/^/      /'
}

mkimg nj ext2                       # = features de sda32 (ext_attr resize_inode dir_index filetype sparse_super large_file)
mkimg jn ext3                       # con has_journal
cp "$W/nj.img" "$W/sucio.img"; debugfs -w -R "ssv state 2" "$W/sucio.img" >/dev/null 2>&1   # 'not clean with errors'
cp "$W/jn.img" "$W/jsucio.img"; debugfs -w -R "feature needs_recovery" "$W/jsucio.img" >/dev/null 2>&1   # journal pendiente
cp "$W/nj.img" "$W/roto.img"
# corrupcion que preen NO arregla: bitmap de bloques del grupo 0 apuntando fuera del fs -> rc 4 (o 8)
debugfs -w -R "set_bg 0 block_bitmap 999999999" "$W/roto.img" >/dev/null 2>&1
dumpe2fs -h "$W/nj.img" 2>/dev/null | grep -E 'features' | sed 's/^/  nj: /'
dumpe2fs -h "$W/jn.img" 2>/dev/null | grep -E 'features' | sed 's/^/  jn: /'

caso "sin journal, limpio, mount ro OK"            nj.img    ok       1 'V8-FSCK: rc=0 |||S123: mount ro OK|||SWITCH_ROOT'
caso "con journal (ext3), limpio, mount ro OK"     jn.img    ok       1 'V8-FSCK: rc=0 |||S123: mount ro OK|||SWITCH_ROOT'
caso "sin journal, sucio+errores -> preen corrige" sucio.img ok       1 'V8-FSCK: rc=[01] '
caso "con journal y needs_recovery -> e2fsck reproduce" jsucio.img ok 1 'V8-FSCK: rc=[01] |||S123: mount ro OK|||SWITCH_ROOT'
caso "corrupto -> rc>=4, AVISO y SIGUE montando"   roto.img  ok       1 'V8-FSCK: rc=([4-9]|[1-9][0-9]) |||V8-FSCK AVISO|||SWITCH_ROOT'
caso "ro falla -> respaldo ro,noload"              nj.img    rofail   1 'V8-MNT AVISO|||MOUNT -t ext4 -o ro,noload|||S123: mount ro,noload OK|||SWITCH_ROOT'
caso "ro y ro,noload fallan -> fallback fork"      nj.img    allfail  1 'S123: mount ro fallo — fallback fork|||FIN-SIN-SWITCH'
caso "cpio sin e2fsck -> monta sin fsck"           nj.img    ok       0 'V8-FSCK: cpio sin |||S123: mount ro OK|||SWITCH_ROOT'
# tras el caso «roto» el fs no debe haberse reiniciado nada: el bloque no contiene reboot
grep -v '^\s*#' "$W/bloque.sh" | grep -q reboot && { echo "FALLA: el bloque contiene reboot"; fallos=$((fallos+1)); }
echo "fallos=$fallos"
exit $fallos
