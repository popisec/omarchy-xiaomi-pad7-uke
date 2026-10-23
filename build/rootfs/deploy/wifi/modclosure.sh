#!/bin/bash
# modclosure.sh DEPFILE MOD [MOD...]
# Cierre transitivo de dependencias leyendo un modules.dep (formato depmod). Imprime, una por linea,
# las rutas relativas (a /usr/lib/modules/<krel>/) de los .ko necesarios, dependencias primero NO
# garantizado (da igual: depmod -a en la tablet reconstruye indices). Solo lectura. Sin kmod.
#   modclosure.sh .../modroot/lib/modules/7.2.9-.../modules.dep ath11k_ahb qcom_q6v5_pas qrtr_smd
# Salida de error: 'FALTA <mod>' por cada modulo pedido que no esta en el modules.dep (builtin o no
# construido) y codigo de salida 3 si falta alguno que NO sea builtin conocido (lo decide el llamador).
set -eu
dep=${1:?uso: modclosure.sh DEPFILE MOD...}
shift
[ -f "$dep" ] || { echo "no existe $dep" >&2; exit 2; }
awk -v want="$*" '
BEGIN { n = split(want, w, " "); for (i = 1; i <= n; i++) { x = w[i]; gsub(/-/, "_", x); need[x] = 1 } }
{
	split($0, a, ":"); p = a[1]; deps[p] = a[2]
	b = p; sub(/.*\//, "", b); sub(/\.ko(\.[a-z]+)?$/, "", b); gsub(/-/, "_", b)
	byname[b] = p
}
END {
	qn = 0; miss = 0
	for (m in need) { if (m in byname) q[++qn] = byname[m]; else { print "FALTA " m > "/dev/stderr"; miss++ } }
	for (i = 1; i <= qn; i++) {
		p = q[i]; if (p in seen) continue
		seen[p] = 1; out[++on] = p
		nd = split(deps[p], d, " ")
		for (j = 1; j <= nd; j++) if (!(d[j] in seen)) q[++qn] = d[j]
	}
	for (k = 1; k <= on; k++) print out[k]
	exit (miss ? 3 : 0)
}' "$dep"
