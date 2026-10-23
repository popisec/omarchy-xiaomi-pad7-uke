#!/usr/bin/env bash
# deltas-omarchy-v4.sh — 18-oct-2026. Delta v4 sobre ouke3: SOLO codigo, config identica.
#   Parches de kernel de la serie de audio (build/rootfs/deploy/audio/kernel/): 0002 (SIDs 0x801001/0x1061 del LPASS) y 0004 (SIDs de los
#   compute-cb de FastRPC del ADSP) en drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c. Informes: AUDIO-E2b-INVESTIGACION/PREPA-20261018.md.
#   Idempotente: si ya estan aplicados no repite. Verifica que SOLO cambia ese fichero respecto al tarball firmado (reproducir-arbol.sh).
#   Config: config-senemos-ouke4 = config-senemos-ouke3 (el release cambia por LOCALVERSION, no por .config).
set -Eeuo pipefail
R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
# El arbol por defecto, pero se puede pointing con SENEMOS_TREE (lo usa
# build/gates/senemos/deltas-senemos.sh para aplicar los deltas sobre un arbol
# recien reproducido).
K=${SENEMOS_TREE:-$R/build/kernel-pokes/senemos-7.2.9/linux-7.2.9}
B=$R/build/kernel-pokes/senemos-build
PD=$R/build/rootfs/deploy/audio/kernel
F=drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c
LV=-senemos.1.4054.3-ouke4
say() { printf '[deltas-v4] %s\n' "$*"; }
# Modo "solo parches": cuando el llamante fija SENEMOS_TREE (arbol recien
# reproducido, sin directorio de build) no se toca la config: esta vive
# versionada en build/kernel-config/senemos-ouke5.config.
SOLO_PARCHES=0
[ -n "${SENEMOS_TREE:-}" ] && SOLO_PARCHES=1
[ "$SOLO_PARCHES" = 1 ] || [[ -f $B/config-senemos-ouke3 ]] || { say "falta config-senemos-ouke3"; exit 1; }
if grep -q 'sid == 0x401007' "$K/$F"; then
    say "0002+0004 ya aplicados en $F"
else
    grep -q 'sid == 0x801001' "$K/$F" && { say "0002 aplicado sin 0004: estado inesperado"; exit 1; }
    # La copia va FUERA del arbol: dentro, aparece como fichero de mas en
    # cualquier comparacion del arbol y el kernel lo podria llegar a compilar.
    cp -a "$K/$F" "$K/../$(basename "$F").pre-v4"
    (cd "$K" && patch -p1 --dry-run < "$PD/0002-uke-smmu-admit-lpass-audio-sids.patch" >/dev/null && patch -p1 < "$PD/0002-uke-smmu-admit-lpass-audio-sids.patch" >/dev/null \
        && patch -p1 --dry-run < "$PD/0004-uke-arm-smmu-qcom-fastrpc-adsp-sids.patch" >/dev/null && patch -p1 < "$PD/0004-uke-arm-smmu-qcom-fastrpc-adsp-sids.patch" >/dev/null)
    say "aplicados 0002 y 0004 (copia previa: $F.pre-v4)"
fi
grep -q 'sid == 0x401007' "$K/$F" && grep -q 'sid == 0x801001' "$K/$F" || { say "los parches no estan en el fichero"; exit 1; }
if [ "$SOLO_PARCHES" = 0 ]; then
	cp -f "$B/config-senemos-ouke3" "$B/config-senemos-ouke4"
	cp -f "$B/config-senemos-ouke4" "$B/.config"
	say "OK: config-senemos-ouke4 = ouke3; LOCALVERSION=$LV"
else
	say "OK: parches 0002+0004 aplicados; la config es build/kernel-config/senemos-ouke5.config"
fi
