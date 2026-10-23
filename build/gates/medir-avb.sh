#!/usr/bin/env bash
# medir-avb.sh — Mide las estructuras AVB/vbmeta de las imagenes boot de uke.
# Solo lectura: no modifica ni la tablet ni los ficheros del repo.
# Uso: ./medir-avb.sh [FICHERO_SALIDA]
#   Sin argumentos: escribe build/gates/medir-avb-<fecha-UTC>.log y lo vuelca a stdout.
# Requiere: bash, python3, sha256sum, grep, cmp. Opcionales: avbtool, ssh (parte tablet).
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
LEE="$REPO/build/backup-par-bueno/boot_b-lee.img"   # la que ARRANCA (s244, slot b)
POKES="$REPO/build/bootimg/boot-pokes.img"          # la que NO arranco
OUT="${1:-$SCRIPT_DIR/medir-avb-$(date -u +%Y%m%d-%H%M%S).log}"

log() { echo "$*"; }
{
log "medir-avb.sh — $(date -u +%Y-%m-%dT%H:%M:%SZ) repo=$REPO"
log ""

for f in "$LEE" "$POKES"; do
  [ -f "$f" ] || { log "FALTA: $f"; exit 1; }
done

log "=== a) sha256 + tamano ==="
sha256sum "$LEE" "$POKES"
stat -c '%n %s B' "$LEE" "$POKES"
log ""

log "=== b) offsets AVB0 / AVBf ==="
for f in "$LEE" "$POKES"; do
  log "--- $f"
  grep -abo 'AVB0' "$f"
  grep -abo 'AVBf' "$f"
done
log ""

log "=== c+d+e) descriptor HASH de boot: declarado vs real ==="
LEE_F="$LEE" POKES_F="$POKES" python3 - <<'PYEOF'
import struct, hashlib, os
def boot_hash_desc(path):
    sz = os.path.getsize(path)
    with open(path, 'rb') as f:
        f.seek(sz - 64); fb = f.read(64)
    assert fb[0:4] == b'AVBf', "sin footer AVBf"
    orig_sz = struct.unpack('>Q', fb[12:20])[0]
    vbmeta_off = struct.unpack('>Q', fb[20:28])[0]
    vbmeta_sz = struct.unpack('>Q', fb[28:36])[0]
    with open(path, 'rb') as f:
        f.seek(vbmeta_off); hdr = f.read(256)
    assert hdr[0:4] == b'AVB0'
    auth_sz, aux_sz = struct.unpack('>QQ', hdr[12:28])
    release = hdr[128:176].split(b'\x00')[0]
    with open(path, 'rb') as f:
        f.seek(vbmeta_off + 256 + auth_sz)
        tag, nbf = struct.unpack('>QQ', f.read(16)); body = f.read(nbf)
    assert tag == 2, f"primer descriptor no es HASH (tag={tag})"
    img_sz = struct.unpack('>Q', body[0:8])[0]
    halg = body[8:40].split(b'\x00')[0]
    pnl, sl, dl = struct.unpack('>III', body[40:52])
    q = 116; part = body[q:q+pnl]; q += pnl
    salt = body[q:q+sl]; q += sl; dgst = body[q:q+dl]
    assert len(salt) == 32 and len(dgst) == 32, (len(salt), len(dgst))
    h = hashlib.sha256(); h.update(salt)
    with open(path, 'rb') as f:
        rem = img_sz
        while rem:
            ch = f.read(min(1 << 20, rem)); h.update(ch); rem -= len(ch)
    print(f"fichero: {path}")
    print(f"  footer: orig_sz={orig_sz} vbmeta_off={vbmeta_off} vbmeta_sz={vbmeta_sz} release={release}")
    print(f"  descriptor: part={part} halg={halg} img_sz={img_sz} (cubre bytes [0,{img_sz}))")
    print(f"  salt(32B): {salt.hex()}")
    print(f"  declarado : {dgst.hex()}")
    print(f"  real      : {h.hexdigest()}")
    print(f"  COINCIDE  : {h.hexdigest() == dgst.hex()}")
for p in (os.environ['LEE_F'], os.environ['POKES_F']):
    boot_hash_desc(p)
PYEOF
log ""

log "=== vbmeta empotrados + footer: identicos entre ambas? ==="
for spec in "35438592 2240" "35440832 2240" "35454976 1728"; do
  set -- $spec
  log "--- blob@$1 ($2 B) ---"
  dd if="$LEE" bs=1 skip="$1" count="$2" status=none | sha256sum | sed 's/  -/  lee/'
  dd if="$POKES" bs=1 skip="$1" count="$2" status=none | sha256sum | sed 's/  -/  pokes/'
done
log "--- footer (ultimos 64 B) ---"
tail -c 64 "$LEE" | sha256sum | sed 's/  -/  lee/'
tail -c 64 "$POKES" | sha256sum | sed 's/  -/  pokes/'
log ""

log "=== region de diferencias lee vs pokes ==="
cmp -l "$LEE" "$POKES" | awk '{print $1}' | python3 -c "
import sys
offs=[int(l) for l in sys.stdin]
print('bytes distintos:', len(offs), 'primero:', offs[0], 'ultimo:', offs[-1])
print('desde', offs[-1]+1, 'hasta EOF: identicos (ramdisk+vbmeta+footer)')
"
log ""

if command -v avbtool >/dev/null 2>&1; then
  log "=== avbtool verify_image (solo lectura, via symlink en tmpfs) ==="
  for pair in "$LEE:vlee" "$POKES:vpokes"; do
    src="${pair%%:*}"; tag="${pair##*:}"
    d="$(mktemp -d)"; ln -s "$src" "$d/boot.img"
    log "--- $tag ---"
    avbtool verify_image --image "$d/boot.img" 2>&1 | grep -E 'Successfully|does not match|Error' || true
    rm -rf "$d"
  done
else
  log "avbtool no instalado: se omite cross-check"
fi
log ""

log "=== PARTE TABLET (solo lectura; se omite si no hay SSH) ==="
KEY="$REPO/build/rootfs/uke-arch-root"; HOST="${UKE_SSH_HOST:-root@192.168.42.129}"
if [ -f "$KEY" ] && command -v ssh >/dev/null 2>&1; then
  if timeout 60 ssh -i "$KEY" "$HOST" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=20 -o BatchMode=yes 'echo OK' 2>/dev/null | grep -q OK; then
    timeout 240 ssh -i "$KEY" "$HOST" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=20 -o BatchMode=yes '
      echo "-- labels --"; ls -l /dev/disk/by-partlabel/ | grep -E "vbmeta_[ab]|boot_[ab]";
      for s in a b; do echo "-- vbmeta_$s --"; blockdev --getsize64 /dev/disk/by-partlabel/vbmeta_$s;
        dd if=/dev/disk/by-partlabel/vbmeta_$s bs=65536 status=none | sha256sum; done
      echo "-- qbootctl --"; qbootctl 2>&1 | head -5
      echo "-- bateria --"; for f in /sys/class/power_supply/*/capacity /sys/class/power_supply/*/voltage_now /sys/class/power_supply/*/status; do echo "$f: $(cat $f 2>/dev/null)"; done
      ' 2>&1
  else
    log "TABLET: sin SSH (omitido, no fatal)"
  fi
else
  log "TABLET: sin clave ssh o sin ssh (omitido, no fatal)"
fi
log ""
log "fin — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} | tee "$OUT"
echo "salida guardada en: $OUT"
