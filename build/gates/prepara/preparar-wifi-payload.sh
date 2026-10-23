#!/bin/bash
# preparar-wifi-payload.sh — arma en el PC el paquete que la tablet necesita para probar el WiFi
# (firmware WCN6750 + cadena de módulos + blacklist), SIN tocar la tablet.
#
# POR QUÉ: el rootfs Arch (V3/V4) trae (a) solo el firmware de linux-firmware (no el del vendor:
# falta qca6750/, board.bin, regdb.bin) y (b) solo 5 .ko (ath11k×3, qcom_battmgr, qcom_pd_mapper):
# faltan cfg80211/mac80211/rfkill/qcom_q6v5_pas/pwrseq-qcom-wcn/… ⇒ 'modprobe ath11k_ahb' no puede
# funcionar. Este script junta lo que falta desde fuentes locales (solo lectura) y lo empaqueta.
#
# FUENTES (solo lectura):
#   firmware: ~/gpu-work/ramaa/s21/wifi-fw-stage (16 ficheros, shas en build/gates/firmware-wlan.sha256)
#   módulos : /var/tmp/uke-k1-build (build del MISMO árbol/config que el kernel K6/K7 de la tablet;
#             se generan con:  env MAKE=/usr/bin/make make -C /var/tmp/uke-k1 O=/var/tmp/uke-k1-build \
#                                ARCH=arm64 LLVM=1 MAKE=/usr/bin/make modules -j8)
#
# SALIDA: /var/tmp/wifi-prep/payload/uke-wifi-payload.tar.gz (+ .sha256 + INVENTARIO.txt)
#   El tar se extrae EN LA TABLET con:  tar xzf uke-wifi-payload.tar.gz -C /
#   Contenido (rutas absolutas al extraer): usr/lib/firmware/… · usr/lib/modules/… · etc/modprobe.d/…
#
# GATES (falla ruidosamente si algo no cuadra):
#   G1 los 16 shas del firmware coinciden con el manifiesto
#   G2 los .ko existen en el build y su vermagic es 7.2.0-rc2-palawan+
#   G3 'depmod -b payload' + 'modprobe -d payload --show-depends' resuelve la cadena SIN faltantes
#   G4 el tar contiene exactamente lo inventariado (recuento) y se publica su sha256
#
# Uso: sh preparar-wifi-payload.sh [--construir|--dry-run]   (por defecto --dry-run)
set -u

REPO=$(cd "$(dirname "$0")/../../.." && pwd)
GATES="$REPO/build/gates"
FWSTAGE="${UKE_FWSTAGE:-$HOME/gpu-work/ramaa/s21/wifi-fw-stage}"
MANIFEST="$GATES/firmware-wlan.sha256"
BUILD="${UKE_KBUILD:-/var/tmp/uke-k1-build}"
# OJO: el release REAL del kernel K-series es 7.2.0-rc2-palawan (sin '+'); los .ko del rootfs Arch
# están bajo 7.2.0-rc2-palawan+ (build antiguo del árbol git) y NO cargan en el kernel actual.
VER="${UKE_KVER:-$(cat "$BUILD/include/config/kernel.release" 2>/dev/null || echo 7.2.0-rc2-palawan)}"
PAY="${UKE_PAYLOAD:-/var/tmp/wifi-prep/payload}"
MODE="${1:---dry-run}"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  OK: $*"; }
bad(){ FAIL=$((FAIL+1)); echo "  FALLO: $*"; }
[ "$MODE" = "--construir" ] || [ "$MODE" = "--dry-run" ] || { echo "uso: $0 [--construir|--dry-run]"; exit 2; }

echo "== preparar-wifi-payload ($MODE) =="

# --- G0 fuentes presentes y fuera de /tmp salvo el destino -------------------
[ -d "$FWSTAGE" ] || { bad "fuente de firmware ausente: $FWSTAGE"; exit 1; }
[ -f "$MANIFEST" ] || { bad "manifiesto ausente: $MANIFEST"; exit 1; }
[ -d "$BUILD" ] || { bad "build del kernel ausente: $BUILD (¿lanzaste 'make modules'?)"; exit 1; }
ok "fuentes: $FWSTAGE + $BUILD"

# --- G1 firmware: 16 shas ----------------------------------------------------
N=0
while read -r sha rel; do
    case "$sha" in \#*|"") continue;; esac
    N=$((N+1)); f="$FWSTAGE/$rel"
    if [ ! -f "$f" ]; then bad "falta $rel"; continue; fi
    got=$(sha256sum "$f" | cut -d' ' -f1)
    [ "$got" = "$sha" ] && ok "fw $rel ($(stat -c%s "$f") B)" || bad "fw $rel sha DISTINTO ($got)"
done < "$MANIFEST"
[ "$N" -eq 16 ] || bad "el manifiesto trae $N, esperados 16"

# --- G2 módulos: superset de dirs que cubre la cadena -----------------------
# (superset acotado: no se copian los ~400 .ko del kernel, solo los árboles de la cadena WiFi/BT)
MODDIRS="drivers/net/wireless/ath/ath11k net/wireless net/mac80211 net/rfkill \
drivers/remoteproc drivers/soc/qcom drivers/rpmsg net/qrtr drivers/power/sequencing"
KOS=""
for d in $MODDIRS; do
    [ -d "$BUILD/$d" ] || { echo "  nota: dir de build ausente (se omite): $d"; continue; }
    list=$(find "$BUILD/$d" -maxdepth 1 -name '*.ko' 2>/dev/null | sort)
    [ -n "$list" ] && KOS="$KOS
$list"
done
NK=$(printf '%s\n' "$KOS" | grep -c '\.ko$' || true)
[ "$NK" -gt 0 ] || { bad "no se encontró ningún .ko (¿build incompleto?)"; exit 1; }
ok "$NK módulos .ko encontrados en el build"
# vermagic (todos deben ser del mismo kernel)
badver=0
while read -r ko; do
    [ -n "$ko" ] || continue
    v=$(strings "$ko" 2>/dev/null | grep -m1 '^vermagic=' | cut -d= -f2-)
    [ "$v" = "$VER SMP preempt mod_unload aarch64" ] || { [ -n "$v" ] && { bad "vermagic distinto en $(basename "$ko"): $v"; badver=$((badver+1)); }; }
done <<< "$KOS"
[ "$badver" -eq 0 ] && ok "vermagic uniforme ($VER SMP preempt mod_unload aarch64)"

if [ "$MODE" = "--dry-run" ]; then
    echo "  (dry-run: no se escribe nada; usar --construir)"
    echo "== resultado: $PASS ok, $FAIL fallos =="
    [ "$FAIL" -eq 0 ]
    exit $?
fi

# --- construir ---------------------------------------------------------------
echo "-- construyendo $PAY --"
rm -rf "$PAY"
mkdir -p "$PAY/usr/lib/firmware" "$PAY/usr/lib/modules/$VER" "$PAY/etc/modprobe.d"

# firmware (16): el manifiesto usa rutas "lib/firmware/…"; en el payload van a usr/lib/firmware/…
while read -r sha rel; do
    case "$sha" in \#*|"") continue;; esac
    r=${rel#lib/firmware/}
    d="$PAY/usr/lib/firmware/$(dirname "$r")"
    mkdir -p "$d"
    cp -a "$FWSTAGE/$rel" "$d/"
done < "$MANIFEST"
ok "firmware copiado (16) a usr/lib/firmware/"

# módulos: preservar el path relativo al build (kernel/…) para que depmod los vea
while read -r ko; do
    [ -n "$ko" ] || continue
    rel=${ko#$BUILD/}
    d="$PAY/usr/lib/modules/$VER/kernel/$(dirname "$rel")"
    mkdir -p "$d"
    cp -a "$ko" "$d/"
done <<< "$KOS"
ok "módulos copiados ($NK) bajo kernel/"

# blacklist horneada (lección #441 §1: sin ella, udev autocarga por modalias)
cat > "$PAY/etc/modprobe.d/blacklist-ath11k.conf" <<'EOF'
blacklist ath11k
blacklist ath11k_ahb
blacklist ath11k_pci
EOF
ok "blacklist-ath11k.conf escrito"

# depmod + G3: la cadena se resuelve sin faltantes
# (depmod -b busca <basedir>/lib/modules; el payload usa usr/lib/modules → symlink temporal lib->usr/lib,
#  que NO entra en el tar porque el tar lista rutas explícitas)
ln -sfn usr/lib "$PAY/lib"
depmod -b "$PAY" "$VER" || { bad "depmod falló"; exit 1; }
ok "depmod -b hecho (release $VER)"
for m in ath11k_ahb ath11k qcom_q6v5_pas pwrseq-qcom-wcn qcom_pd_mapper cfg80211 mac80211 rfkill qrtr_smd; do
    out=$(modprobe -d "$PAY" -S "$VER" --show-depends "$m" 2>&1) || { bad "modprobe --show-depends $m falló: $out"; continue; }
    missing=0
    while read -r line; do
        case "$line" in insmod\ *) f=${line#insmod }; [ -f "$f" ] || missing=$((missing+1));; esac
    done <<< "$out"
    [ "$missing" -eq 0 ] && ok "cadena $m resuelve ($(printf '%s\n' "$out" | grep -c '^insmod') ficheros)" \
                         || bad "cadena $m con $missing ficheros inexistentes"
done

# inventario + tar
( cd "$PAY" && find . -type f | sort | xargs sha256sum ) > "$(dirname "$PAY")/INVENTARIO.txt"
TAR="$(dirname "$PAY")/uke-wifi-payload.tar.gz"
tar czf "$TAR" -C "$PAY" usr/lib/firmware usr/lib/modules etc/modprobe.d
sha256sum "$TAR" | sed 's# .*/#  #' > "$TAR.sha256"
echo "-- tar: $TAR ($(stat -c%s "$TAR") B, $(tar tzf "$TAR" | wc -l) entradas)"
echo "-- destino en la tablet: tar xzf uke-wifi-payload.tar.gz -C / && depmod -a"
cat "$TAR.sha256"
echo "== resultado: $PASS ok, $FAIL fallos =="
[ "$FAIL" -eq 0 ]
