#!/usr/bin/env bash
# backup-par-bueno.sh — F0 paso 5 como PROCEDIMIENTO, no como comando suelto.
#
# POR QUÉ EXISTE. El paso 5 de F0 ("backup del par bueno leído de la tablet") no
# existía como script: era un fragmento en el plan que había que reescribir a mano
# en cada sesión. Un comando escrito a mano en un chat se pierde, se ejecuta a
# medias y no deja gates. Este script es el procedimiento entero: identifica,
# lee, re-hashea en la tablet, baja, re-hashea en el PC y compara. O pasa todos
# los gates o aborta; no hay "backup más o menos bien".
#
# POR QUÉ SSH Y NO OTRA COSA. `fastboot fetch` NO está verificado en este ABL
# (REFUTADO B-01 del proyecto hermano: un fetch estéril se lee como "el kernel
# no arranca") y en la tablet NO hay adb (es Ubuntu/Arch, no Android). El único
# canal que funciona es SSH + dd + relectura (patrón del ledger #241).
#
# POR QUÉ POR ETIQUETA Y CON MAGIC (R-49). Las letras /dev/sdX cambian entre
# arranques; `dd if=<un directorio>` escribe basura (REFUTADO R-49). Aquí las
# particiones se resuelven por /dev/disk/by-partlabel/{boot_b,dtbo_b} Y se exige
# que el path sea un bloque ([ -b ]) y que traiga su magic antes de leer nada:
# boot = "ANDROID!" en los primeros 8 B; dtbo = 0xd7b7ab1e en los primeros 4 B.
# Sin magic no hay lectura: aborta.
#
# POR QUÉ SE HASHEA AL TAMAÑO EXACTO (patrón #241). Las particiones son más
# grandes que las imágenes (boot: 96 MiB de partición; dtbo: 24 MiB de partición
# para una imagen útil de ~607 KiB) y el resto es pad de ceros. Hashear la
# partición entera daría un sha distinto en cada aparato. Para boot_b el tamaño
# exacto es 100663296 B (la imagen buena YA mide 96 MiB). Para dtbo_b el tamaño
# útil NO se supone: se DESCUBRE leyendo el total_size de su propia cabecera
# (bytes 4:8, big-endian) y se verifica que coincide en ambos lados.
#
# SOLO LECTURA en la tablet. Lo único que se escribe allí son los dos ficheros
# de staging en /root (NO en /tmp: es tmpfs y no caben 120 MB; los staging van
# a /root por regla del proyecto). Ninguna partición se toca, ningún slot
# cambia, ningún reboot. Tras los dd hay `sync` antes de hashear.
#
# Uso:
#   ./backup-par-bueno.sh                  # backup real por SSH a build/backup-par-bueno/
#   ./backup-par-bueno.sh --self-test      # verifica TODA la lógica de PC sin tocar la tablet
#   ./backup-par-bueno.sh -h               # ayuda
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
KEY="$ROOT/build/rootfs/uke-arch-root"
HOST="192.168.42.129"
OUTDIR="$ROOT/build/backup-par-bueno"
CONNECT_TIMEOUT=45

# Shas conocidos, con FECHA (regla del proyecto: lo no re-medido en 14 días caduca).
# Medidos 28-sep-2026: el dtbo, re-medido hoy contra el fichero s238 en disco
# (`sha256sum build/bootimg/s238-boot-dtbo-dedup-gpio.img`) y contra ESTADO-VIVO:4.
# El valor es bdb361dff87de52dd7d4581c7f4007abdaf98ac145d47658ef2a29bc458f0022
# (64 hex, `dff` en las posiciones 7-9); coincide carácter a carácter con el del
# enunciado que pidió este script. No había errata que corregir: manda lo medido.
# Comparación solo INFORMATIVA (el slot cambia: s229 -> s238 ya pasó una vez):
# el GATE duro es tablet == PC, no "igual que hace días".
EXPECT_BOOT_SHA="ffff8c51265ff03c84cff15ffdb275f396a666a491eb5d67580be705321db99e"
EXPECT_DTBO_SHA="bdb361dff87de52dd7d4581c7f4007abdaf98ac145d47658ef2a29bc458f0022"
EXPECT_DTBO_UTIL="607534"
KNOWN_DATE="28-sep-2026"

BOOT_BYTES=100663296   # 96 MiB: la imagen buena YA mide lo que la partición
DTBO_PART_MB=24        # la partición dtbo mide 24 MiB (25165824 B)

die() { echo "ABORT: $*" >&2; exit 1; }
info() { echo "$*"; }

usage() {
    sed -n '2,/^set -u/p' "$0" | sed 's/^# \{0,1\}//'
    echo "USO: $0 [--self-test] [-h]"
}

# Descubre el tamaño útil de una imagen dtbo desde su propia cabecera:
# magic 0xd7b7ab1e (bytes 0:4) + total_size big-endian (bytes 4:8).
# Imprime el tamaño o sale con error. Nunca supone nada.
discover_dtbo_size() {
    python3 - "$1" <<'PYEOF'
import struct, sys
p = sys.argv[1]
with open(p, "rb") as f:
    hdr = f.read(8)
if len(hdr) < 8:
    sys.exit("dtbo: fichero de menos de 8 B: " + p)
magic, total = struct.unpack(">II", hdr)
if magic != 0xD7B7AB1E:
    sys.exit("dtbo: magic != 0xd7b7ab1e en %s (gate R-49)" % p)
if total <= 0:
    sys.exit("dtbo: total_size <= 0 en %s" % p)
print(total)
PYEOF
}

sha_at_size() { # $1=fichero $2=bytes -> sha256 de head -c (patrón #241)
    head -c "$2" "$1" | sha256sum | cut -d' ' -f1
}

# --- self-test: toda la lógica de PC contra fixtures locales, sin tablet ------
self_test() {
    info "== self-test: lógica de PC sin tablet =="
    BOOT_FIX="$ROOT/build/backup-par-bueno/boot_b-lee.img"
    DTBO_FIX="$ROOT/build/bootimg/s238-boot-dtbo-dedup-gpio.img"
    [ -f "$BOOT_FIX" ] || die "falta fixture $BOOT_FIX"
    [ -f "$DTBO_FIX" ] || die "falta fixture $DTBO_FIX"

    # 1) descubrimiento del tamaño útil del dtbo desde su cabecera
    UTIL="$(discover_dtbo_size "$DTBO_FIX")" || die "discover_dtbo_size falló"
    [ "$UTIL" = "$EXPECT_DTBO_UTIL" ] \
        || die "tamaño descubierto $UTIL != $EXPECT_DTBO_UTIL declarado"
    info "OK  tamaño dtbo descubierto de cabecera: $UTIL B"

    # 2) hash al tamaño exacto, ambos lados simulados con el mismo camino de código
    SB="$(sha_at_size "$BOOT_FIX" "$BOOT_BYTES")"
    SD="$(sha_at_size "$DTBO_FIX" "$UTIL")"
    [ "$SB" = "$EXPECT_BOOT_SHA" ] || die "sha boot fixture != conocido ($SB)"
    [ "$SD" = "$EXPECT_DTBO_SHA" ] || die "sha dtbo fixture != conocido ($SD)"
    info "OK  sha al tamaño exacto coincide con los conocidos ($KNOWN_DATE)"

    # 3) tabla como la del backup real
    printf '%-10s | %-12s | %-64s | %-64s | %s\n' \
        "particion" "bytes" "sha_tablet(sim)" "sha_pc" "coincide"
    printf '%-10s | %-12s | %-64s | %-64s | %s\n' \
        "boot_b" "$BOOT_BYTES" "$SB" "$SB" "SÍ"
    printf '%-10s | %-12s | %-64s | %-64s | %s\n' \
        "dtbo_b" "$UTIL" "$SD" "$SD" "SÍ"

    # 4) prueba NEGATIVA: 1 byte corrupto en la "descarga" -> el gate tiene que abortar
    T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
    cp "$DTBO_FIX" "$T/dtbo_b-lee.img"
    printf 'X' | dd of="$T/dtbo_b-lee.img" bs=1 seek=100 count=1 conv=notrunc status=none
    SD_BAD="$(sha_at_size "$T/dtbo_b-lee.img" "$UTIL")"
    if [ "$SD_BAD" = "$SD" ]; then
        die "el gate NO detectó la corrupción (sha igual tras flip de 1 B)"
    fi
    info "OK  prueba negativa: 1 B corrupto cambia el sha y el gate abortaría"
    info "== self-test VERDE =="
}

# --- backup real ---------------------------------------------------------------
do_backup() {
    [ -f "$KEY" ] || die "falta la clave SSH $KEY"
    command -v ssh >/dev/null || die "sin ssh en el PC"
    command -v scp >/dev/null || die "sin scp en el PC"
    mkdir -p "$OUTDIR"

    SSHOPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
             -o ConnectTimeout="$CONNECT_TIMEOUT" -o LogLevel=ERROR
             -i "$KEY" "root@$HOST")

    info "== 0) pre-vuelo: la tablet responde por SSH =="
    ssh "${SSHOPTS[@]}" 'echo "ssh OK: $(uname -m) $(uname -r)"' \
        || die "la tablet no responde por SSH a $HOST (¿IP? ¿red del gadget?)"

    info "== 1) lectura en la tablet (etiqueta + magic + dd + hash al tamaño exacto) =="
    # El bloque remoto va por stdin con bash -s (patrón de uke-ssh.sh): llega
    # literal, sin escapes. Todo gate remoto aborta con exit != 0.
    REMOTE_OUT="$(ssh -T "${SSHOPTS[@]}" bash -s <<'REMOTE_EOF'
set -u
P_BOOT=/dev/disk/by-partlabel/boot_b
P_DTBO=/dev/disk/by-partlabel/dtbo_b
# GATE R-49: etiqueta resuelta, es bloque, y trae su magic. Si no, ni se lee.
[ -b "$P_BOOT" ] || { echo "ABORT: $P_BOOT no es un bloque"; exit 10; }
[ -b "$P_DTBO" ] || { echo "ABORT: $P_DTBO no es un bloque"; exit 11; }
dd if="$P_BOOT" bs=8 count=1 2>/dev/null | grep -q 'ANDROID!' \
    || { echo "ABORT: boot_b sin magic ANDROID!"; exit 12; }
[ "$(dd if="$P_DTBO" bs=4 count=1 2>/dev/null | od -A n -t x1 | tr -d ' \n')" = "d7b7ab1e" ] \
    || { echo "ABORT: dtbo_b sin magic DTBO (0xd7b7ab1e)"; exit 13; }
# Lectura completa de cada partición (boot 96 MiB; dtbo 24 MiB enteros: el
# backup tiene que servir aunque la imagen útil crezca; F0 ponía count=16 para
# dtbo, que recorta la partición: aquí se lee entera a propósito).
dd if="$P_BOOT" of=/root/boot_b-lee.img bs=1M count=96 conv=fsync status=none \
    || { echo "ABORT: dd boot_b"; exit 14; }
dd if="$P_DTBO" of=/root/dtbo_b-lee.img bs=1M count=24 conv=fsync status=none \
    || { echo "ABORT: dd dtbo_b"; exit 15; }
sync
BOOT_BYTES=100663296
SHA_BOOT="$(head -c "$BOOT_BYTES" /root/boot_b-lee.img | sha256sum | cut -d' ' -f1)"
# Tamaño útil del dtbo: DESCUBIERTO de su cabecera, no supuesto.
if command -v python3 >/dev/null 2>&1; then
    DTBO_UTIL="$(python3 -c "import struct; print(struct.unpack('>I', open('/root/dtbo_b-lee.img','rb').read()[4:8])[0])")"
else
    HEX="$(dd if=/root/dtbo_b-lee.img bs=8 count=1 2>/dev/null | od -A n -t x1 | tr -d ' \n' | cut -c9-16)"
    DTBO_UTIL="$((16#$HEX))"
fi
[ "$DTBO_UTIL" -gt 0 ] 2>/dev/null || { echo "ABORT: total_size dtbo inválido: $DTBO_UTIL"; exit 16; }
[ "$DTBO_UTIL" -le 25165824 ] || { echo "ABORT: total_size dtbo mayor que la partición: $DTBO_UTIL"; exit 17; }
SHA_DTBO="$(head -c "$DTBO_UTIL" /root/dtbo_b-lee.img | sha256sum | cut -d' ' -f1)"
echo "BOOT_BYTES=$BOOT_BYTES"
echo "SHA_TABLET_BOOT=$SHA_BOOT"
echo "DTBO_UTIL_BYTES=$DTBO_UTIL"
echo "SHA_TABLET_DTBO=$SHA_DTBO"
REMOTE_EOF
)" || die "falló la fase remota. Salida: $REMOTE_OUT"

    BOOT_BYTES_TB="$(echo "$REMOTE_OUT" | sed -n 's/^BOOT_BYTES=//p')"
    SHA_TB_BOOT="$(echo "$REMOTE_OUT" | sed -n 's/^SHA_TABLET_BOOT=//p')"
    DTBO_UTIL_TB="$(echo "$REMOTE_OUT" | sed -n 's/^DTBO_UTIL_BYTES=//p')"
    SHA_TB_DTBO="$(echo "$REMOTE_OUT" | sed -n 's/^SHA_TABLET_DTBO=//p')"
    [ -n "$SHA_TB_BOOT" ] && [ -n "$SHA_TB_DTBO" ] && [ -n "$DTBO_UTIL_TB" ] \
        || die "la tablet no devolvió los 4 campos. Salida: $REMOTE_OUT"
    info "tablet: boot $BOOT_BYTES_TB B sha ${SHA_TB_BOOT:0:12}… dtbo útil $DTBO_UTIL_TB B sha ${SHA_TB_DTBO:0:12}…"

    info "== 2) bajada al PC (sin pisar: lo previo se aparta con fecha) =="
    NOW="$(date -u +%Y%m%dT%H%M%SZ)"
    for f in boot_b-lee.img dtbo_b-lee.img; do
        if [ -f "$OUTDIR/$f" ]; then
            mv "$OUTDIR/$f" "$OUTDIR/$f.prev-$NOW" \
                || die "no pude apartar $OUTDIR/$f"
            info "aparto previo: $f -> $f.prev-$NOW"
        fi
    done
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout="$CONNECT_TIMEOUT" -o LogLevel=ERROR -i "$KEY" \
        "root@$HOST:/root/boot_b-lee.img" "root@$HOST:/root/dtbo_b-lee.img" \
        "$OUTDIR/" || die "scp falló a medias: revisa $OUTDIR antes de repetir"

    info "== 3) re-hash en el PC + gates =="
    BOOT_PC="$OUTDIR/boot_b-lee.img"
    DTBO_PC="$OUTDIR/dtbo_b-lee.img"
    BYTES_BOOT_PC="$(stat -c '%s' "$BOOT_PC")"
    BYTES_DTBO_PC="$(stat -c '%s' "$DTBO_PC")"
    [ "$BYTES_BOOT_PC" = "100663296" ] \
        || die "boot bajado mide $BYTES_BOOT_PC B, no 100663296"
    [ "$BYTES_DTBO_PC" = "25165824" ] \
        || die "dtbo bajado mide $BYTES_DTBO_PC B, no 25165824 (partición incompleta)"
    # El tamaño útil se REDESCUBRE aquí del fichero bajado: si la bajada se
    # corrompió justo en la cabecera, este número ya no coincide con el de la
    # tablet y el gate lo caza.
    DTBO_UTIL_PC="$(discover_dtbo_size "$DTBO_PC")" \
        || die "el dtbo bajado no trae magic DTBO (bajada corrupta)"
    [ "$DTBO_UTIL_PC" = "$DTBO_UTIL_TB" ] \
        || die "tamaño útil dtbo: tablet=$DTBO_UTIL_TB PC=$DTBO_UTIL_PC (bajada corrupta)"
    SHA_PC_BOOT="$(sha_at_size "$BOOT_PC" "$BOOT_BYTES")"
    SHA_PC_DTBO="$(sha_at_size "$DTBO_PC" "$DTBO_UTIL_PC")"

    printf '%-10s | %-12s | %-64s | %-64s | %s\n' \
        "particion" "bytes" "sha_tablet" "sha_pc" "coincide"
    if [ "$SHA_TB_BOOT" = "$SHA_PC_BOOT" ]; then C1="SÍ"; else C1="NO"; fi
    if [ "$SHA_TB_DTBO" = "$SHA_PC_DTBO" ]; then C2="SÍ"; else C2="NO"; fi
    printf '%-10s | %-12s | %-64s | %-64s | %s\n' \
        "boot_b" "$BOOT_BYTES" "$SHA_TB_BOOT" "$SHA_PC_BOOT" "$C1"
    printf '%-10s | %-12s | %-64s | %-64s | %s\n' \
        "dtbo_b" "$DTBO_UTIL_PC" "$SHA_TB_DTBO" "$SHA_PC_DTBO" "$C2"

    # GATE DURO: si un solo sha difiere, el backup NO vale. Abortar, no adornar.
    [ "$C1" = "SÍ" ] || die "boot_b: tablet != PC. El backup NO está bien."
    [ "$C2" = "SÍ" ] || die "dtbo_b: tablet != PC. El backup NO está bien."

    # Comparación informativa con los shas registrados (el slot evoluciona;
    # diferir aquí es "el contenido cambió", no "el backup está mal").
    [ "$SHA_PC_BOOT" = "$EXPECT_BOOT_SHA" ] \
        || info "AVISO (no fatal): boot_b difiere del registrado el $KNOWN_DATE."
    [ "$SHA_PC_DTBO" = "$EXPECT_DTBO_SHA" ] \
        || info "AVISO (no fatal): dtbo_b difiere del registrado el $KNOWN_DATE."
    info "== BACKUP OK: $BOOT_PC + $DTBO_PC =="
    info "Pre-registra en el ledger: boot=$SHA_PC_BOOT dtbo=$SHA_PC_DTBO (útil $DTBO_UTIL_PC B)"
}

case "${1:-}" in
    --self-test) self_test ;;
    -h|--help) usage; exit 0 ;;
    "") do_backup ;;
    *) die "argumento desconocido: $1 (ver -h)" ;;
esac
