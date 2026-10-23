#!/bin/bash
# brillo-dual: verifica (y prueba) que uke-backlight escribe los DOS KTZ8866.
# Uso: deploy.sh check   -> SOLO LECTURA: regs 0x04/0x05/0x08 de i2c-2 y i2c-5 y compara.
#      deploy.sh apply   -> prueba activa (escribe sysfs brightness; pide autorizacion del dueno):
#                           guarda el brillo, fija 600 y 200, compara ambos chips, restaura.
#      deploy.sh revert  -> restaura el brillo guardado en /run/brillo-dual.saved
# Variable: UKE_SSH (por defecto, ssh a la tablet por RNDIS). Con TARGET=local corre en la propia tablet.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
KEY="$HERE/../../uke-arch-root"
run() { if [ "${TARGET:-ssh}" = local ]; then bash -s -- "$@"; else ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 root@192.168.42.129 bash -s -- "$@"; fi; }
REMOTE=$(cat <<'R'
BL=/sys/class/backlight/uke-backlight
regs() { python3 - <<'P'
import fcntl,os
o=[]
for bus in (2,5):
    fd=os.open("/dev/i2c-%d"%bus,os.O_RDWR); fcntl.ioctl(fd,0x0706,0x11)
    o.append(" ".join("%02x=%02x"%(r,(os.write(fd,bytes([r])),os.read(fd,1)[0])[1]) for r in (4,5,8)))
print(o[0]+" | "+o[1]); raise SystemExit(0 if o[0]==o[1] else 3)
P
}
case "$1" in
check) echo "brightness=$(cat $BL/brightness) actual=$(cat $BL/actual_brightness)"; regs && echo OK-IGUALES || echo DIFIEREN;;
apply) cat $BL/brightness > /run/brillo-dual.saved
  for v in 600 200; do echo $v > $BL/brightness; sleep 1; echo -n "set $v: "; regs && echo OK || echo DIFIEREN; done
  cat /run/brillo-dual.saved > $BL/brightness; echo "restaurado $(cat $BL/brightness)";;
revert) [ -f /run/brillo-dual.saved ] && cat /run/brillo-dual.saved > $BL/brightness; echo "brightness=$(cat $BL/brightness)";;
esac
R
)
case "${1:-check}" in check|apply|revert) printf '%s\n' "$REMOTE" | run "$1";; *) sed -n 2,8p "$0"; exit 1;; esac
