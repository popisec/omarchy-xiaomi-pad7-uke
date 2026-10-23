#!/usr/bin/env bash
# deploy-check.sh — pasa el 'check' de cada despliegue y clasifica el resultado.
#
# POR QUE ESTE SCRIPT Y NO UN BUCLE EN EL Makefile. No todos los despliegues
# tienen el mismo subcomando de verificacion: unos usan 'check', otros '--check',
# y otros no tienen ninguno (solo apply/revert). Ademas, algunos 'check' fallan
# por motivos que NO son un defecto del repo (la tablet no esta conectada, o
# falta material local que no se publica). Este script distingue esos casos y
# no los cuenta como fallos.
#
# USO:  bash tools/deploy-check.sh [--verbose]
# SALIDA: 0 si ningun despliegue tiene un fallo real; 1 si hay alguno.
set -uo pipefail

R="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1

ok=0; sin_check=0; falta_local=0; necesita_tablet=0; fallos=0
declare -A FALLO=()

for d in "$R"/build/rootfs/deploy/*/; do
	tema=$(basename "$d")
	s="$d/deploy.sh"
	[ -f "$s" ] || continue
	chmod +x "$s" 2>/dev/null || true

	# Que forma de verificacion ofrece? Dos estilos conviven:
	#   'check)'  -> subcomando:  deploy.sh check
	#   '--check' -> flag o rama: deploy.sh --check
	modo=""
	if grep -qE '^[[:space:]]*check\)' "$s"; then
		modo="check"
	elif grep -qE '^[[:space:]]*--check\)?' "$s" && grep -q -- '--check' "$s"; then
		modo="--check"
	fi
	if [ -z "$modo" ]; then
		uso=$(grep -m1 -oE 'uso:.*' "$s" | cut -c1-70)
		printf "  %-22s %-9s %s\n" "$tema" "sin check" "${uso:-no ofrece subcomando de verificacion}"
		sin_check=$((sin_check+1))
		continue
	fi

	salida=$(cd "$d" && timeout 120 bash "$s" "$modo" 2>&1)
	rc=$?
	if [ $rc -eq 0 ]; then
		printf "  %-22s %s\n" "$tema" "OK"
		ok=$((ok+1))
	elif grep -qiE "permission denied|no such host|could not resolve|timed out|connection refused" <<<"$salida"; then
		printf "  %-22s %s\n" "$tema" "necesita la tablet conectada"
		necesita_tablet=$((necesita_tablet+1))
	elif grep -qiE "falta (la clave|.*stage-escritorio|.*firmware|.*\.ko)|no existe|could not be read|FAILED open or read|no coincide con SHA256SUMS|corre? build\.sh|out/" <<<"$salida"; then
		# Los artefactos GENERADOS (out/, *.ko, firmware) no se publican: sin
		# ellos el check no puede pasar en un clon nuevo. Lo que SI se comprueba
		# aparte es que las FUENTES del manifiesto cuadren (tools/check-manifests.py).
		printf "  %-22s %s\n" "$tema" "necesita material local (no se publica)"
		falta_local=$((falta_local+1))
	else
		printf "  %-22s %s\n" "$tema" "FALLO"
		FALLO[$tema]="$salida"
		fallos=$((fallos+1))
	fi
	[ $VERBOSE -eq 1 ] && [ ${FALLO[$tema]:-} ] && echo "$salida" | sed 's/^/      /'
done

echo
echo "OK: $ok | sin subcomando de check: $sin_check | necesitan la tablet: $necesita_tablet | necesitan material local: $falta_local | FALLOS: $fallos"
if [ $fallos -gt 0 ]; then
	echo
	for t in "${!FALLO[@]}"; do
		echo "--- $t"
		echo "${FALLO[$t]}" | tail -3 | sed 's/^/    /'
	done
	exit 1
fi
exit 0
