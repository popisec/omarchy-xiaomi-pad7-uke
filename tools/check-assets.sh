#!/usr/bin/env bash
# check-assets.sh — audita los assets de los releases del repo.
#
# POR QUE. Los checks de la CI miran `git ls-files` y `git grep`: un asset
# COMPRIMIDO de un release es INVISIBLE para todos ellos. Se publico una
# imagen de rootfs de 4 GiB que llevaba dentro el firmware del fabricante, el
# hash de la contrasena de root y las claves SSH privadas del host, y ningun
# check de la CI lo vio. Este script cierra ese canal.
#
# QUE COMPRUEBA, por cada asset de cada release:
#   1. que el sha256 que anuncia el release sea el del fichero descargado
#   2. que NO contenga material prohibido:
#        - claves privadas (PEM/OpenSSH)
#        - hashes de contrasena ($6$...)
#        - authorized_keys
#        - firmware del fabricante (adsp*, cdsp*, wpss*, gen71100*)
#      Se busca DENTRO del asset: si es un tar, se extrae; si es un .zst o una
#      imagen, se busca en el flujo descomprimido (un hash de /etc/shadow SI
#      aparece como cadena en la imagen).
#   3. que el tar no lleve el nombre de usuario del autor en los metadatos
#      (uid/gid distintos de 0/0)
#
# USO:  bash tools/check-assets.sh [OWNER/NAME]
# ENTORNO: GITHUB_TOKEN (para la API y las descargas)
#         UKER_ASSET_MAX_MB  (por defecto 400: no se descargan assets mayores)
# SALIDA: 0 si todo cuadra, 1 si hay algo que revisar.
set -uo pipefail

REPO="${1:-${UKER_REPO:-popisec/omarchy-xiaomi-pad7-uke}}"
MAX_MB="${UKER_ASSET_MAX_MB:-400}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fallos=0

say() { printf '[assets] %s\n' "$*"; }
api() { curl -s -H "Authorization: Bearer ${GITHUB_TOKEN:-}" -H "Accept: application/vnd.github+json" "$@"; }

if [ -z "${GITHUB_TOKEN:-}" ]; then
	say "sin GITHUB_TOKEN: no se pueden auditar los assets; se omite"
	exit 0
fi

# --- patrones de material prohibido ---------------------------------------
PATRONES_PROHIBIDOS='-----BEGIN (OPENSSH|RSA|EC|DSA|PGP|PRIVATE) PRIVATE KEY-----|^root:\$6\$|authorized_keys|/adsp\.[a-z0-9]+|/cdsp\.[a-z0-9]+|/wpss\.b[0-9]+|gen71100_zap\.mbn'

# Los ficheros prohibidos por nombre (dentro de un tar).
NOMBRES_PROHIBIDOS='ssh_host_.*_key$|authorized_keys$|/shadow$'

releases=$(api "https://api.github.com/repos/$REPO/releases?per_page=100" \
	| python3 -c 'import sys,json;[print(r["tag_name"]) for r in json.load(sys.stdin)]' 2>/dev/null)
[ -z "$releases" ] && { say "no se han podido listar los releases"; exit 1; }

for tag in $releases; do
	say "=== $tag ==="
	assets=$(api "https://api.github.com/repos/$REPO/releases/tags/$tag" \
		| python3 -c '
import sys, json
for a in json.load(sys.stdin).get("assets", []):
    print("\t".join([a["name"], str(a["size"]), a.get("digest") or "", a["browser_download_url"]]))' 2>/dev/null)
	[ -z "$assets" ] && { say "  sin assets"; continue; }
	while IFS=$'\t' read -r nombre size digest url; do
		[ -z "${nombre:-}" ] && continue
		mb=$((size / 1024 / 1024))
		say "  $nombre (${mb} MiB)"
		if [ "$mb" -gt "$MAX_MB" ]; then
			echo "::error::el asset $nombre pesa $mb MiB (mas que el limite de $MAX_MB): no se audita"
			fallos=1
			continue
		fi
		if ! curl -sL --max-time 600 --max-filesize $((MAX_MB * 1024 * 1024 + 10)) "$url" -o "$TMP/$nombre"; then
			say "    no se pudo descargar"; fallos=1; continue
		fi

		# 1) el sha que anuncia el release
		got=$(sha256sum "$TMP/$nombre" | cut -d' ' -f1)
		decl="${digest#sha256:}"
		if [ -n "$decl" ]; then
			if [ "$decl" != "$got" ]; then
				echo "::error::el sha del asset $nombre no coincide con el que anuncia el release"
				fallos=1
			else
				say "    sha OK ($got)"
			fi
		else
			say "    (el release no anuncia sha; el digest calculado es $got)"
		fi

		# 2) material prohibido, DENTRO del asset
		case "$nombre" in
		*.tar.gz|*.tgz)
			# 3) metadatos del tar: propietario neutro
			props=$(tar tzvf "$TMP/$nombre" 2>/dev/null | awk '{print $2}' | sort -u | tr '\n' ' ')
			if echo "$props" | grep -qvE '^(0/0|root/root)( |$)'; then
				echo "::error::el tar lleva propietarios no neutros (puede filtrar el nombre del autor): $props"
				fallos=1
			else
				say "    metadatos del tar neutros"
			fi
			mkdir -p "$TMP/x" && tar xzf "$TMP/$nombre" -C "$TMP/x" 2>/dev/null
			hit=$(grep -rlE "$PATRONES_PROHIBIDOS" "$TMP/x" 2>/dev/null | head -5)
			[ -n "$hit" ] && { echo "::error::el asset contiene material prohibido:"; echo "$hit" | sed 's/^/    /'; fallos=1; }
			hit=$(find "$TMP/x" -type f 2>/dev/null | grep -E "$NOMBRES_PROHIBIDOS" | head -5)
			[ -n "$hit" ] && { echo "::error::el asset contiene ficheros prohibidos:"; echo "$hit" | sed 's/^/    /'; fallos=1; }
			rm -rf "$TMP/x"
			;;
		*.zst|*.zstd|*.xz|*.gz|*.img)
			# Un asset comprimido: se busca en el flujo DESCOMPRIMIDO. Un hash
			# de /etc/shadow o una clave PEM SI aparecen como cadenas.
			hit=$(zstd -dc "$TMP/$nombre" 2>/dev/null | grep -a -oE "$PATRONES_PROHIBIDOS" | sort -u | head -5)
			[ -z "$hit" ] && hit=$(xz -dc "$TMP/$nombre" 2>/dev/null | grep -a -oE "$PATRONES_PROHIBIDOS" | sort -u | head -5)
			[ -z "$hit" ] && hit=$(gzip -dc "$TMP/$nombre" 2>/dev/null | grep -a -oE "$PATRONES_PROHIBIDOS" | sort -u | head -5)
			if [ -n "$hit" ]; then
				echo "::error::el asset $nombre contiene material prohibido (dentro del comprimido):"
				echo "$hit" | sed 's/^/    /'
				fallos=1
			else
				say "    sin material prohibido en el contenido"
			fi
			;;
		esac
	done <<< "$assets"
done

if [ $fallos -eq 0 ]; then
	say "OK: los assets cuadran y no llevan material prohibido."
else
	say "HAY QUE REVISAR LOS ASSETS"
fi
exit $fallos
