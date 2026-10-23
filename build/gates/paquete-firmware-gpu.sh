#!/bin/sh
# paquete-firmware-gpu.sh — paquete de firmware de la GPU al rootfs (F1a/F2).
#
# QUÉ: los 3 blobs vendor que YA FUNCIONAN (probe bueno del 24-sep del hermano:
#   GMU OPP table OK + G2-initOK; F1a propio del 27-sep: card0 + renderD128 con
#   s231) copiados a las 8 rutas que fija el driver + el DT:
#   - qcom/gen71100_gmu.bin + qcom/gen71100_sqe.fw
#     (a6xx_catalog.c, entrada 0x43030b00, vía adreno_request_fw()
#     en adreno_gpu.c:527-, que prueba primero "qcom/<nombre>");
#   - qcom/uke/gen71100_zap.mbn (xiaomi-uke.dts:555, firmware-name del
#     &gpu_zap_shader; petición directa con request_firmware_direct);
#   - qcom/palawan/gen71100_zap.mbn (lamma-qrd.dts, placa de referencia);
#   - qcom/gen71100_zap.mbn (fallback del zapfw del catálogo);
#   - gen71100_{gmu.bin,sqe.fw,zap.mbn} en la raíz de /lib/firmware
#     (ubicación "legacy" sin prefijo: SESION-24SEP-GPU.md del hermano midió
#     que sin estos el fw_load del GMU NO DA ERROR, se cuelga).
#   Mismo mapa que build/pkg/uke-gpu-firmware/PKGBUILD (paquete 1-1 ya
#   instalado en la tablet el 27-sep-2026, NOTAS-OMARCHY.md).
# FUENTE (versionada en este repo): build/pkg/uke-gpu-firmware/
#   (3 blobs + PKGBUILD en git; el .pkg.tar.zst es derivado y está ignorado).
#   Shas esperados: firmware-gpu.sha256 (mismo dir; los 3 publicados en el
#   SHA256SUMS del staging del hermano del 11-sep-2026 — ver su cabecera;
#   NINGUNO es generado nuevo, al contrario que el paquete del WLAN).
# DESTINO: staging/lib/firmware/ (fuente del mkfs.ext4 -d, INFORME-A2 §a.8).
#   El staging trae linux-firmware de stock SIN dir qcom/ (INFORME-A2 §b):
#   este paquete es AUTOCONTENIDO, no depende de ningún paquete de firmware.
#
# TODO LOCAL, 100% offline: NO copia nada a la tablet. Modo por defecto
#   --dry-run (verifica fuentes+shas e informa qué haría). El modo real
#   --instalar escribe SOLO en staging/ local (ni tablet, ni flash, ni dd).
# Lecciones aplicadas: mkdir -p ANTES de copiar (R-49: scp sin mkdir falla);
#   nada bajo /tmp (tmpfs: se pierde al reinicio); sync tras copiar (ronda 39 §4).
#
# Uso: sh build/gates/paquete-firmware-gpu.sh [--dry-run|--instalar]

set -eu
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GATES="$REPO/build/gates"
STAGE_SRC="$REPO/build/pkg/uke-gpu-firmware"
MANIFIESTO="$GATES/firmware-gpu.sha256"
DSTBASE="$REPO/build/rootfs/staging/lib/firmware"
# Segunda copia independiente (solo lectura, no fatal si falta): staging del
# hermano. Si está, sus shas tienen que coincidir con el manifiesto.
XTRA_SRC="$HOME/gpu-work/uke-staging/firmware"
MODE="${1:---dry-run}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FALLO: $1"; }
[ "$MODE" = "--dry-run" ] || [ "$MODE" = "--instalar" ] || { echo "uso: $0 [--dry-run|--instalar]"; exit 2; }

echo "== A8-gpu paquete-firmware-gpu ($MODE) =="
echo "-- gate 0: rutas fuera de /tmp y manifiesto presente --"
case "$STAGE_SRC $DSTBASE" in *tmp*) bad "ruta bajo /tmp"; exit 1;; *) ok "fuente y destino fuera de /tmp";; esac
[ -f "$MANIFIESTO" ] || { bad "falta $MANIFIESTO"; exit 1; }
ok "manifiesto $MANIFIESTO"
[ -d "$STAGE_SRC" ] || { bad "fuente ausente: $STAGE_SRC"; exit 1; }
ok "fuente accesible (versionada en git)"

echo "-- gate 1: los 3 blobs existen y su sha == manifiesto --"
N=0
while read -r sha rel; do
    case "$sha" in \#*|"") continue;; esac
    N=$((N+1)); f="$STAGE_SRC/$rel"
    [ -f "$f" ] || { bad "falta $rel"; continue; }
    got="$(sha256sum "$f" | cut -d' ' -f1)"
    size="$(stat -c%s "$f")"
    if [ "$got" = "$sha" ]; then ok "$rel  $size B  sha ✓"; else bad "$rel sha DISTINTO (esperado $sha, medido $got)"; fi
done < "$MANIFIESTO"
[ "$N" -eq 3 ] && ok "recuento de manifiesto: 3 blobs" || bad "manifiesto trae $N, esperados 3"

echo "-- gate 1b: cruce con la segunda copia del hermano (si está) --"
if [ -d "$XTRA_SRC" ]; then
    for rel in qcom/gen71100_sqe.fw qcom/gen71100_gmu.bin qcom/uke/gen71100_zap.mbn qcom/palawan/gen71100_zap.mbn; do
        base="$(basename "$rel")"
        srcbase="$STAGE_SRC/$base"
        [ -f "$XTRA_SRC/$rel" ] || { bad "segunda copia sin $rel"; continue; }
        cmp -s "$srcbase" "$XTRA_SRC/$rel" \
            && ok "coincide con hermano: $rel" \
            || bad "DIFIEREN fuente y hermano en $rel (¿blob cambiado?)"
    done
else
    echo "  (aviso: sin segunda copia en $XTRA_SRC; se sigue con la fuente versionada)"
fi

echo "-- gate 2: sin colisiones con el linux-firmware de stock del staging --"
[ -e "$DSTBASE/qcom" ] && bad "staging ya trae qcom/ (inesperado: INFORME-A2 §b dice que no)" \
                       || ok "staging sin qcom/ (se creará)"
for b in gen71100_gmu.bin gen71100_sqe.fw gen71100_zap.mbn; do
    [ -e "$DSTBASE/$b" ] && bad "colisión legacy: staging ya trae $b" \
                         || ok "sin colisión legacy: $b es NUEVO en staging"
done

if [ "$MODE" = "--instalar" ]; then
    echo "-- modo real: mkdir -p (R-49) + copia + cmp + sync --"
    while read -r sha rel; do
        case "$sha" in \#*|"") continue;; esac
        base="$(basename "$rel")"
        case "$base" in
            gen71100_gmu.bin) dests="qcom/gen71100_gmu.bin gen71100_gmu.bin"; srcsha="$sha";;
            gen71100_sqe.fw)  dests="qcom/gen71100_sqe.fw gen71100_sqe.fw";   srcsha="$sha";;
            gen71100_zap.mbn) dests="qcom/uke/gen71100_zap.mbn qcom/palawan/gen71100_zap.mbn qcom/gen71100_zap.mbn gen71100_zap.mbn"; srcsha="$sha";;
        esac
        for d_rel in $dests; do
            d="$DSTBASE/$(dirname "$d_rel")"
            mkdir -p "$d"
            cp -a "$STAGE_SRC/$base" "$d/$(basename "$d_rel").tmp-$$"
            mv "$d/$(basename "$d_rel").tmp-$$" "$d/$(basename "$d_rel")"
            cmp -s "$STAGE_SRC/$base" "$d/$(basename "$d_rel")" \
                && ok "copiado $d_rel" || { bad "cmp tras copia: $d_rel"; exit 1; }
            got="$(sha256sum "$d/$(basename "$d_rel")" | cut -d' ' -f1)"
            [ "$got" = "$srcsha" ] || { bad "sha tras copia: $d_rel"; exit 1; }
        done
    done < "$MANIFIESTO"
    sync && ok "sync ejecutado"
fi

echo "-- gate 3: recuento final en staging --"
c_qcom="$(find "$DSTBASE/qcom" -type f 2>/dev/null | wc -l)"
c_leg="$(find "$DSTBASE" -maxdepth 1 -name 'gen71100_*' 2>/dev/null | wc -l)"
echo "  staging/lib/firmware/qcom/               = $c_qcom ficheros (esperado tras --instalar: 5)"
echo "  staging/lib/firmware/gen71100_* (legacy)  = $c_leg ficheros (esperado tras --instalar: 3)"
echo "  staging/lib/firmware/qca6750/             = $(find "$DSTBASE/qca6750" -type f 2>/dev/null | wc -l) ficheros (paquete WLAN, no se toca aquí)"
echo "  staging/lib/firmware/ath11k/WCN6750/      = $(find "$DSTBASE/ath11k/WCN6750" -type f 2>/dev/null | wc -l) ficheros (paquete WLAN, no se toca aquí)"
if [ "$MODE" = "--instalar" ]; then
    [ "$c_qcom" -eq 5 ] && ok "qcom/ completo (5)" || bad "qcom/ trae $c_qcom, esperados 5"
    [ "$c_leg" -eq 3 ] && ok "legacy completo (3)" || bad "legacy trae $c_leg, esperados 3"
else
    echo "  (dry-run: no se escribe nada; el modo real es --instalar, NO invocado aquí)"
fi

echo "== resultado: $PASS ok, $FAIL fallos =="
[ "$FAIL" -eq 0 ]
