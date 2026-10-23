#!/bin/bash
# medir-drenaje-uso.sh check|start [etiqueta]|stop|report [CSV...] — SE EJECUTA EN EL PC. Drenaje con USO REAL y larga duracion (pendiente B2).
# No genera carga: el dueño usa la tablet; esto solo MARCA el inicio/fin en /var/lib/uke-bateria/marcas-uso.csv y luego calcula, con el log de 60 s
# de uke-bateria-log (/var/log/uke-bateria/*.csv), %/h, W medios y autonomia SOLO con filas estado=Discharging dentro de las marcas.
# start: gates (turno, Discharging >=30 %) · stop: marca el fin · report: copia los CSV (solo lectura) y calcula · revert: borra el fichero de marcas.
# Referencia: 21-oct 65 min Equilibrado 3,88 %/h (~24,5 h; 1,50 W por gauge).
set -u; . "$(dirname "$0")/lib.sh"
M=${UKE_MARCAS:-/var/lib/uke-bateria/marcas-uso.csv}
calc() { python3 - "$@" <<'PY'
import csv, sys, glob
# argumentos: marcas.csv (etiqueta,inicio,fin) y los CSV del log
marcas = [l.strip().split(",") for l in open(sys.argv[1]) if l.strip() and not l.startswith("etiqueta")]
filas = []
for f in sys.argv[2:]:
    filas += list(csv.DictReader(open(f)))
if not marcas: sys.exit("sin marcas")
for et, a, b in marcas:
    a = int(a); b = int(b) if b else None
    r = [x for x in filas if x.get("estado") == "Discharging" and not x.get("event") and int(x["ts"]) >= a and (b is None or int(x["ts"]) <= b)]
    runs, cur = [], []
    for x in r:                      # tramos continuos: un hueco > 180 s (suspension, cargador) corta el tramo
        if cur and int(x["ts"]) - int(cur[-1]["ts"]) > 180: runs.append(cur); cur = []
        cur.append(x)
    if cur: runs.append(cur)
    runs = [q for q in runs if len(q) >= 3]
    if not runs: print(f"{et}: sin tramos Discharging continuos de >=3 filas en la ventana"); continue
    for k, q in enumerate(runs, 1):
        t = int(q[-1]["ts"]) - int(q[0]["ts"]); p0 = float(q[0]["pct_exact"]); p1 = float(q[-1]["pct_exact"])
        w = [float(x["w"]) for x in q if x["w"]]; hrs = t / 3600
        ph = (p0 - p1) / hrs if hrs else 0
        print(f"{et} tramo {k}: {hrs:.2f} h, {p0:.2f}->{p1:.2f} % = {ph:.2f} %/h (~{100/ph:.1f} h de 100 %), W medio {sum(w)/len(w):.2f} (por corriente), perfil {q[-1]['perfil']}, hz {q[-1]['hz']}, brillo {q[-1]['brillo_pct']} %" if ph > 0 else f"{et} tramo {k}: sin descarga neta")
PY
}
case "${1:-}" in
check) bash -n "$0" && echo "CHECK OK";;
start) gate_turno; gate_bateria 30 Discharging; S "mkdir -p $(dirname $M); [ -s $M ] || echo etiqueta,inicio,fin > $M; echo \"${2:-uso},\$(date +%s),\" >> $M; tail -1 $M"; echo "marcado el inicio. Usa la tablet con normalidad; al terminar: $0 stop";;
stop) S "python3 - $M <<'P'
import sys,time
f=sys.argv[1]; L=open(f).read().splitlines()
assert L[-1].endswith(','), 'sin marca abierta'
L[-1]+=str(int(time.time())); open(f,'w').write('\n'.join(L)+'\n'); print(L[-1])
P";;
report) D=$(mktemp -d); S "cat $M" > $D/marcas.csv || die "sin marcas"; if [ $# -ge 2 ]; then shift; cp "$@" $D/ 2>/dev/null; else for f in $(S 'ls /var/log/uke-bateria/*.csv' 2>/dev/null); do S "cat $f" > $D/$(basename $f); done; fi
  calc $D/marcas.csv $(ls $D/*.csv | grep -v marcas.csv); rm -rf "$D";;
revert) S "rm -f $M; echo revertido-marcas-el-log-de-60s-no-se-toca";;
*) echo "uso: $0 check|start [etiqueta]|stop|report [CSV...]|revert"; exit 2;;
esac
