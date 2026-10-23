#!/usr/bin/env bash
# gpu-fw-fix.sh — cerrar el ENOENT de qcom/gen71100_sqe.fw (#P40 RESULTADO, 30-sep-2026).
#
# DIAGNOSTICO (k14-cycle.log, 2 ciclos identicos, t=4,203 s / 4,208 s):
#   msm_dpu ae01000.display-controller: Direct firmware load for qcom/gen71100_sqe.fw failed with error -2
#   [drm:adreno_request_fw] *ERROR* failed to load gen71100_sqe.fw
#   -> el arranque muere detras (fin de captura = nueva-version-kernel en la linea siguiente).
#
# POR QUE EL ROOTFS SOLO NO BASTA (hallazgo clave de U1, 30-sep noche):
#   La peticion ocurre en msm_open -> load_gpu -> adreno_load_gpu -> adreno_load_fw
#   (adreno_device.c:93), disparado por el cliente fbdev en el MISMO initcall del bind.
#   Con el arming K11 (ukeinit, "UKE-K11: armado rc=0 a 3s") toda esa cadena corre a ~4,2 s,
#   ANTES del switch_root del ukeinit (S123; UFS enumera a 4,18 s; mount+switch viene despues).
#   El loader de firmware del kernel lee SIEMPRE contra el root INICIAL de init_task
#   (kernel_read_file_from_path_initns, fs/kernel_read_file.c:147-172: get_fs_root(init_task.fs))
#   = el initramfs, no el rootfs real. En 27-sep (F1a, card0+renderD128 con s231) funciono porque
#   sin arming el open fue TARDIO, ya tras switch_root (el overmount cruza al rootfs).
#   => El firmware tiene que estar en el INITRAMFS (determinista para el bind de 4,2 s)
#      y en el rootfs (determinista para cargas post-switch: reprobes, runtime PM).
#
# MODOS:
#   --check      (default, PC, solo lectura) verifica blobs vs manifiesto y estado de rootfs/imagen.
#   --initramfs  (PC) construye /var/tmp/u1-gpu-fw/boot-ukek13-fw.img: copia boot-ukek13.img
#                byte a byte y SOLO cambia ramdisk_size@12 + anade un initrd externo (cpio newc,
#                gzip -9n) con las 8 rutas del paquete uke-gpu-firmware. El initrd externo NO lleva
#                /ukeinit: el built-in (armado K11) sigue mandando. Precedente: K10 ya uso initrd
#                externo con esta ABL y este header (INFORME-K10-BUILD.md G5, boot verificado).
#                NO FLASHEA: imprime el comando fastboot para el DUENO.
#   --ssh        (PC, con tablet viva en Arch por USB NCM) instala las 8 rutas en
#                /usr/lib/firmware del rootfs vivo y verifica sha256. Usa el canal de
#                uke-ssh.sh (key build/rootfs/uke-arch-root, root@192.168.42.129).
#                No reinicia, no toca servicios.
#
# NOMBRES EXACTOS que pide el driver (arbol /var/tmp/uke-k13-tree):
#   qcom/gen71100_sqe.fw       a6xx_catalog.c:1621 (fw[ADRENO_FW_SQE]) via adreno_request_fw
#                              (adreno_gpu.c:524-592: prueba "qcom/<n>" -> legacy "<n>" -> helper)
#   qcom/gen71100_gmu.bin      a6xx_catalog.c:1622 (fw[ADRENO_FW_GMU]) via adreno_request_fw
#   qcom/uke/gen71100_zap.mbn  xiaomi-uke.dts:555 (firmware-name del zap-shader), peticion DIRECTA
#                              request_firmware_direct en adreno_gpu.c:75-79, SIN fallback
#   Orden en el boot (todo dentro de adreno_load_gpu, adreno_device.c:69-):
#   1) SQE, 2) GMU (bucle adreno_load_fw, adreno_gpu.c:607-622), 3) hw_init:
#      GMU escribe bloques (a6xx_gmu.c:901-933) y zap (a6xx_gpu.c:1493 -> adreno_gpu.c:30-160).
#
# FORMATOS (sin conversion): SQE = microcode crudo (memcpy a sqe_bo, a6xx_gpu.c:1049-1054);
#   GMU = imagen con block_header {addr,size,type,value,data[]} (a6xx_gmu.c:855-860, parse :901);
#   ZAP = mbn/MDT firmado por SKU (qcom_mdt_load, adreno_gpu.c:130-141; + qcom_scm_pas_auth_and_reset).
#   Los 3 blobs vendor ya van en ese formato (probe 27-sep F1a y SHA256SUMS del hermano 11-sep).
#   PROHIBIDO usar el zap del QRD (sha a6a4265b..., ~/gpu-work/fw-qrd8635/): otra firma.
#
# FUENTES de blobs (primera que verifique sha gana):
#   1) build/pkg/uke-gpu-firmware/            (staged versionado)
#   2) $HOME/gpu-work/uke-staging/firmware/qcom[/uke]/
#   3) $HOME/proyectos/ubuntu-uke/stock/firmware/
#   Manifiesto: build/gates/firmware-gpu.sha256 (los 3 shas publicados).
#
# Este script NO escribe nada en $HOME fuera de si mismo; salidas a /var/tmp/u1-gpu-fw/.

set -eu

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
STAGED="$REPO/build/pkg/uke-gpu-firmware"
MANIFIESTO="$REPO/build/gates/firmware-gpu.sha256"
SSH_KEY="$REPO/build/rootfs/uke-arch-root"
SSH_HOST="192.168.42.129"
OUTDIR="/var/tmp/u1-gpu-fw"
BASE_DEF="$REPO/build/bootimg/boot-ukek13.img"
BASE_SHA="d71ea2b5f6aaf7f8b4820748362b5b32ebed4a064f6f224bb037a7abc9707381"
IMG_SIZE=100663296
AVB0_OFF=35438592
QRD_ZAP_SHA="a6a4265b0ce1fa0400e512d9fea9be976cda2f714ba4e02277a1ccb70d79a208"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  OK: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FALLO: %s\n' "$1"; }
die() { printf 'ABORT: %s\n' "$1" >&2; exit 1; }

# nombre logico -> sha (del manifiesto, copiado aqui como gate duro)
SQE_SHA="b6df660d109504dbea5a266910b037a33d893a11c6de52f524a5fd112008c401"
GMU_SHA="435c7bac9a328b8a100df930b84b65b4d579e42be44785d0e60e3729291bb864"
ZAP_SHA="0c86e4ae6ed618101949965df451510a3216e0f0de1aef4920bd1888a15ea8e6"

# resolver blob: $1=gen71100_sqe.fw|gen71100_gmu.bin|gen71100_zap.mbn -> eco de la ruta elegida
resolver_blob() {
    local b="$1" sha case
    case "$b" in
        gen71100_sqe.fw)  sha="$SQE_SHA";;
        gen71100_gmu.bin) sha="$GMU_SHA";;
        gen71100_zap.mbn) sha="$ZAP_SHA";;
        *) return 1;;
    esac
    for cand in \
        "$STAGED/$b" \
        "$HOME/gpu-work/uke-staging/firmware/qcom/$b" \
        "$HOME/gpu-work/uke-staging/firmware/qcom/uke/$b" \
        "$HOME/proyectos/ubuntu-uke/stock/firmware/$b"; do
        if [ -f "$cand" ]; then
            local got; got="$(sha256sum "$cand" | cut -d' ' -f1)"
            if [ "$got" = "$sha" ]; then printf '%s\n' "$cand"; return 0; fi
        fi
    done
    return 1
}

# las 8 rutas de instalacion (mapa del PKGBUILD:41-49)
rutas_8() {
    printf '%s\n' \
        "usr/lib/firmware/qcom/gen71100_sqe.fw gen71100_sqe.fw $SQE_SHA" \
        "usr/lib/firmware/qcom/gen71100_gmu.bin gen71100_gmu.bin $GMU_SHA" \
        "usr/lib/firmware/qcom/uke/gen71100_zap.mbn gen71100_zap.mbn $ZAP_SHA" \
        "usr/lib/firmware/qcom/palawan/gen71100_zap.mbn gen71100_zap.mbn $ZAP_SHA" \
        "usr/lib/firmware/qcom/gen71100_zap.mbn gen71100_zap.mbn $ZAP_SHA" \
        "usr/lib/firmware/gen71100_gmu.bin gen71100_gmu.bin $GMU_SHA" \
        "usr/lib/firmware/gen71100_sqe.fw gen71100_sqe.fw $SQE_SHA" \
        "usr/lib/firmware/gen71100_zap.mbn gen71100_zap.mbn $ZAP_SHA"
}

gate_blobs() {
    printf -- '---- gate blobs (sha vs manifiesto %s) ----\n' "$MANIFIESTO"
    [ -f "$MANIFIESTO" ] || { bad "manifiesto ausente"; return 1; }
    local b src got
    for b in gen71100_sqe.fw gen71100_gmu.bin gen71100_zap.mbn; do
        if src="$(resolver_blob "$b")"; then
            ok "$b <= $src"
        else
            bad "$b: ninguna fuente con sha correcto (staged/staging/stock)"
        fi
    done
    # rechazo explicito del zap QRD (firma de otra SKU)
    local q="$HOME/gpu-work/fw-qrd8635/gen71100_zap.mbn"
    if [ -f "$q" ]; then
        got="$(sha256sum "$q" | cut -d' ' -f1)"
        [ "$got" = "$QRD_ZAP_SHA" ] && printf '  (aviso: zap QRD presente en gpu-work; EXCLUIDO a proposito)\n' || bad "zap QRD cambio de sha: $got"
    fi
    [ "$FAIL" -eq 0 ]
}

modo_check() {
    printf -- '-- U1 gpu-fw-fix --check (solo lectura) --\n'
    gate_blobs || true
    printf -- '---- estado rootfs vivo (imagen) y staged ----\n'
    local img="$REPO/build/rootfs/arch-rootfs.img"
    if [ -f "$img" ] && command -v debugfs >/dev/null 2>&1; then
    if debugfs -R 'stat /usr/lib/firmware/qcom/gen71100_sqe.fw' "$img" 2>&1 | grep -q 'File not found'; then
        printf '  (dato: arch-rootfs.img NO trae el fw: correcto y documentado; la tablet viva\n'
        printf '   se instalo aparte el 27-sep. Para el boot K15 no basta solo esto: ver cabecera)\n'
    else
        ok "imagen rootfs TRAE qcom/gen71100_sqe.fw (inesperado segun G1 par.2.3)"
    fi
    fi
    for f in "$STAGED/gen71100_sqe.fw" "$STAGED/gen71100_gmu.bin" "$STAGED/gen71100_zap.mbn"; do
        [ -f "$f" ] && ok "staged presente: $f ($(stat -c%s "$f") B)" || bad "staged ausente: $f"
    done
    printf -- '-- resultado --check: %d ok, %d fallos --\n' "$PASS" "$FAIL"
}

modo_ssh() {
    printf -- '-- U1 gpu-fw-fix --ssh (instala en rootfs vivo; NO reinicia) --\n'
    gate_blobs || die "blobs no verificados; no se toca la tablet"
    local SSHTC=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o LogLevel=ERROR -i "$SSH_KEY" "root@$SSH_HOST")
    printf '  ping+ssh gate a %s...\n' "$SSH_HOST"
    ping -c1 -W2 "$SSH_HOST" >/dev/null 2>&1 || die "sin ping a $SSH_HOST (tablet viva? canal USB NCM?)"
    local rel; rel="$(ssh "${SSHTC[@]}" 'uname -r')" || die "ssh no responde"
    case "$rel" in *palawan*) ok "kernel remoto: $rel";; *) die "kernel remoto $rel no es palawan/uke";; esac
    # subir solo los 3 blobs a /tmp de la tablet
    local tmpd="/tmp/gpufw.$$"
    ssh "${SSHTC[@]}" "mkdir -p $tmpd" || die "no se creo $tmpd en la tablet"
    local b src
    for b in gen71100_sqe.fw gen71100_gmu.bin gen71100_zap.mbn; do
        src="$(resolver_blob "$b")"
        ssh "${SSHTC[@]}" "cat > $tmpd/$b" < "$src" || die "fallo el push de $b"
    done
    # instalar 8 rutas + verificar sha + sync, todo del lado tablet
    # (la tabla viaja DENTRO del script remoto: el stdin de bash -s es el propio script)
    local script="set -eu; umask 022
while read -r dest base sha; do
  mkdir -p \"\$(dirname \"/\$dest\")\"
  cp \"/\$tmpd/\$base\" \"/\$dest.tmp-in\"
  mv \"/\$dest.tmp-in\" \"/\$dest\"
  got=\$(sha256sum \"/\$dest\" | cut -d' ' -f1)
  [ \"\$got\" = \"\$sha\" ] || { echo \"SHA-MAL \$dest \$got\"; exit 1; }
  echo \"OK \$dest\"
done <<'TABLA'
$(rutas_8)
TABLA
sync
rm -rf '$tmpd'"
    ssh "${SSHTC[@]}" "bash -s" <<<"$script" | sed 's/^/  [tablet] /'
    printf -- '-- resultado --ssh: %d ok, %d fallos --\n' "$PASS" "$FAIL"
    [ "$FAIL" -eq 0 ]
}

modo_initramfs() {
    local base="${1:-$BASE_DEF}"
    printf -- '-- U1 gpu-fw-fix --initramfs (PC; salida en %s; NO flashea) --\n' "$OUTDIR"
    gate_blobs || die "blobs no verificados"
    printf -- '---- gate base ----\n'
    [ -f "$base" ] || die "base ausente: $base"
    local sha; sha="$(sha256sum "$base" | cut -d' ' -f1)"
    if [ "$sha" != "$BASE_SHA" ]; then
        die "sha de base DISTINTO al del boot_b #P40 (esperado $BASE_SHA, medido $sha). Si es intencionado, revisar layout antes"
    fi
    ok "base == boot-ukek13.img de #P40 ($sha)"
    mkdir -p "$OUTDIR"
    printf -- '---- construir initrd externo (8 rutas) ----\n'
    local initrd_gz="$OUTDIR/uke-gpufw-initrd.cpio.gz"
    python3 - "$STAGED" "$initrd_gz" <<'PYEOF'
import gzip, io, os, sys
staged, out = sys.argv[1], sys.argv[2]
SQE="b6df660d109504dbea5a266910b037a33d893a11c6de52f524a5fd112008c401"
GMU="435c7bac9a328b8a100df930b84b65b4d579e42be44785d0e60e3729291bb864"
ZAP="0c86e4ae6ed618101949965df451510a3216e0f0de1aef4920bd1888a15ea8e6"
# (ruta dentro del initramfs, fichero fuente, sha)
rutas = [
    ("lib", None, None),
    ("lib/firmware", None, None),
    ("lib/firmware/qcom", None, None),
    ("lib/firmware/qcom/uke", None, None),
    ("lib/firmware/qcom/gen71100_sqe.fw", "gen71100_sqe.fw", SQE),
    ("lib/firmware/qcom/gen71100_gmu.bin", "gen71100_gmu.bin", GMU),
    ("lib/firmware/qcom/uke/gen71100_zap.mbn", "gen71100_zap.mbn", ZAP),
    ("lib/firmware/qcom/palawan/gen71100_zap.mbn", "gen71100_zap.mbn", ZAP),
    ("lib/firmware/qcom/gen71100_zap.mbn", "gen71100_zap.mbn", ZAP),
    ("lib/firmware/gen71100_gmu.bin", "gen71100_gmu.bin", GMU),
    ("lib/firmware/gen71100_sqe.fw", "gen71100_sqe.fw", SQE),
    ("lib/firmware/gen71100_zap.mbn", "gen71100_zap.mbn", ZAP),
]
def newc(name, data, mode):
    nb = name.encode()
    h = b"070701" + "".join(f"{v:08X}" for v in (
        0, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(nb)+1, 0)).encode("ascii")
    out = h + nb + b"\0"
    out += b"\0" * ((4 - len(out) % 4) % 4)
    out += data + b"\0" * ((4 - len(data) % 4) % 4)
    return out
buf = io.BytesIO()
for ruta, src, sha in rutas:
    if src is None:
        buf.write(newc(ruta, b"", 0o40755))
    else:
        data = open(os.path.join(staged, src), "rb").read()
        import hashlib
        got = hashlib.sha256(data).hexdigest()
        if got != sha:
            sys.exit(f"sha MAL en {src}: {got}")
        buf.write(newc(ruta, data, 0o100644))
buf.write(newc("TRAILER!!!", b"", 0))
buf.write(b"\0" * ((512 - buf.tell() % 512) % 512))
gz = gzip.compress(buf.getvalue(), 9, mtime=0)
open(out, "wb").write(gz)
print(f"initrd: {len(gz)} B ({len(rutas)-1} ficheros+dirs), sha256={hashlib.sha256(gz).hexdigest()}")
PYEOF
    [ -s "$initrd_gz" ] || die "initrd no generado"
    ok "initrd externo generado: $initrd_gz ($(stat -c%s "$initrd_gz") B)"
    printf -- '---- reempaquetar boot (solo @12 + region ramdisk) ----\n'
    local out_img="$OUTDIR/boot-ukek13-fw.img"
    python3 - "$base" "$initrd_gz" "$out_img" "$IMG_SIZE" "$AVB0_OFF" <<'PYEOF'
import struct, sys, os
base, initrd, out, total, avb0 = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
img = bytearray(open(base, "rb").read())
rd = open(initrd, "rb").read()
if len(img) != total: sys.exit(f"tamano base {len(img)} != {total}")
ks, rs = struct.unpack_from("<II", img, 8)
if rs != 0: sys.exit(f"base ya trae initrd externo (ramdisk_size@12={rs}): layout distinto al validado")
rdoff = (4096 + ks + 4095) // 4096 * 4096
if rdoff + len(rd) > avb0: sys.exit(f"initrd invade zona AVB: fin {rdoff+len(rd)} > AVB0 {avb0}")
struct.pack_into("<I", img, 12, len(rd))
img[rdoff:rdoff+len(rd)] = rd
open(out, "wb").write(img)
# gates de salida
img2 = open(out, "rb").read()
ks2, rs2 = struct.unpack_from("<II", img2, 8)
assert ks2 == ks and rs2 == len(rd)
base_b = open(base, "rb").read()
delta = [i for i in range(total) if img2[i] != base_b[i]]
lo, hi = (min(delta), max(delta)) if delta else (0, 0)
print(f"salida: {out} ({len(img2)} B) kernel_size={ks} ramdisk_off={rdoff} ramdisk_size={rs2}")
print(f"delta vs base confinado a: bytes {lo}..{hi} (cabecera@12 + region ramdisk)")
ok_delta = all((12 <= i < 16) or (rdoff <= i < rdoff + len(rd)) for i in delta)
if not ok_delta: sys.exit("delta FUERA de las regiones permitidas")
print("GATES-OK")
PYEOF
    [ -s "$out_img" ] || die "imagen de salida no generada"
    ok "imagen lista: $out_img ($(stat -c%s "$out_img") B)"
    printf -- '---- verificacion independiente del ramdisk en la imagen ----\n'
    if python3 - "$out_img" <<'PYEOF'
import struct, sys, gzip, io, hashlib
SQE="b6df660d109504dbea5a266910b037a33d893a11c6de52f524a5fd112008c401"
GMU="435c7bac9a328b8a100df930b84b65b4d579e42be44785d0e60e3729291bb864"
ZAP="0c86e4ae6ed618101949965df451510a3216e0f0de1aef4920bd1888a15ea8e6"
espera = {
 "lib/firmware/qcom/gen71100_sqe.fw": SQE,
 "lib/firmware/qcom/gen71100_gmu.bin": GMU,
 "lib/firmware/qcom/uke/gen71100_zap.mbn": ZAP,
 "lib/firmware/qcom/palawan/gen71100_zap.mbn": ZAP,
 "lib/firmware/qcom/gen71100_zap.mbn": ZAP,
 "lib/firmware/gen71100_gmu.bin": GMU,
 "lib/firmware/gen71100_sqe.fw": SQE,
 "lib/firmware/gen71100_zap.mbn": ZAP,
}
img = open(sys.argv[1], "rb").read()
ks, rs = struct.unpack_from("<II", img, 8)
rdoff = (4096 + ks + 4095) // 4096 * 4096
cpio = gzip.decompress(img[rdoff:rdoff+rs])
vistos, i = {}, 0
while i + 110 <= len(cpio):
    if cpio[i:i+6] != b"070701": break
    f = [int(cpio[i+6+j*8:i+14+j*8], 16) for j in range(13)]
    namesize, filesize, mode = f[11], f[6], f[1]
    name = cpio[i+110:i+110+namesize-1].decode()
    doff = i + 110 + namesize
    doff += (4 - doff % 4) % 4
    if name == "TRAILER!!!": break
    if mode & 0o170000 == 0o100000:
        vistos[name] = hashlib.sha256(cpio[doff:doff+filesize]).hexdigest()
    i = doff + filesize + ((4 - filesize % 4) % 4)
mal = 0
for ruta, sha in espera.items():
    if vistos.get(ruta) == sha:
        print(f"  OK en initrd: /{ruta}")
    else:
        print(f"  FALLO en initrd: /{ruta} (visto: {vistos.get(ruta,'AUSENTE')})")
        mal += 1
sys.exit(1 if mal else 0)
PYEOF
    then
        :
    else
        die "verificacion del ramdisk fallo"
    fi
    printf -- '-- resultado --initramfs: %d ok, %d fallos --\n' "$PASS" "$FAIL"
    printf 'SIGUIENTE PASO (lo ejecuta el DUENO con tablet en fastboot y gate de bateria):\n'
    printf '  fastboot flash boot_b %s\n' "$out_img"
    printf '  (rollback: fastboot flash boot_b build/backup-par-bueno/boot_b-lee.img)\n'
}

[ -f "$MANIFIESTO" ] || die "manifiesto ausente: $MANIFIESTO"
case "${1:---check}" in
    --check)     modo_check;;
    --ssh)       modo_ssh;;
    --initramfs) modo_initramfs "${2:-}";;
    *) printf 'uso: %s [--check|--ssh|--initramfs [boot.img]]\n' "$0"; exit 2;;
esac
