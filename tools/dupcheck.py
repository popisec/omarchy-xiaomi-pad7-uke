#!/usr/bin/env python3
# dupcheck.py — detecta ficheros duplicados en el arbol versionado.
#
# Por que: en el repo hubo 73 ficheros .config de kernel para 16 contenidos
# distintos (18 MB de texto repetido), y tres copias del protocolo del teclado
# en pantalla. Nadie lo vio porque el .gitignore no lo prohibe y git no lo
# avisa. Este script lo hace visible ANTES de que llegue al repo.
#
# Regla: dos ficheros versionados de mas de MIN_BYTES con el MISMO contenido
# son un duplicado. Se permiten:
#   - ficheros de menos de MIN_BYTES (codigo pequeno, cabeceras, LICENSE)
#   - ficheros con contenido identico pero en carpetas distintas que son
#     deliberadamente copias (se listan en PERMITIDOS)
#
# Uso:   python3 tools/dupcheck.py [--min-bytes N] [--max N]
# Salida: 0 si no hay duplicados nuevos, 1 si los hay.

import argparse
import hashlib
import os
import subprocess
import sys

MIN_BYTES_DEF = 4096

# Prefijos donde los duplicados son DELIBERADOS y no se deben tocar.
# build/linux-senemos-20261017/ tiene volcados "plano" (antes) y "reposo"
# (despues) de la misma medicion: que dos volcados sean identicos ES la
# evidencia de que algo no cambio. Borrar uno seria falsear la evidencia.
PERMITIDOS_PREFIJOS = (
    "build/linux-senemos-20261017/",
    "build/linux-l76r-20261017/",
)

# Duplicados que se conservan a proposito (con motivo).
PERMITIDOS = {
    # Los .config de kernel: los duplicados son symlinks al canonico, asi que
    # no tienen contenido propio (git los guarda como enlaces).
}


def ficheros_versionados(repo):
    out = subprocess.run(["git", "ls-files", "-z"], cwd=repo, capture_output=True)
    return [p for p in out.stdout.decode("utf-8", "replace").split("\0") if p]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--min-bytes", type=int, default=MIN_BYTES_DEF)
    ap.add_argument("--max", type=int, default=30, help="maximo de grupos a listar")
    args = ap.parse_args()
    repo = os.path.abspath(args.repo)

    grupos = {}
    for rel in ficheros_versionados(repo):
        if rel in PERMITIDOS:
            continue
        if any(rel.startswith(p) for p in PERMITIDOS_PREFIJOS):
            continue
        p = os.path.join(repo, rel)
        if os.path.islink(p) or not os.path.isfile(p):
            continue
        try:
            tam = os.path.getsize(p)
        except OSError:
            continue
        if tam < args.min_bytes:
            continue
        h = hashlib.sha256(open(p, "rb").read()).hexdigest()
        grupos.setdefault(h, []).append(rel)

    dups = {h: v for h, v in grupos.items() if len(v) > 1}
    total = sum(len(v) - 1 for v in dups.values())

    print(f"ficheros versionados >= {args.min_bytes} B: {sum(len(v) for v in grupos.values())}")
    if not dups:
        print("OK: ningun fichero duplicado.")
        return 0

    print(f"duplicados: {total} ficheros de mas en {len(dups)} grupos\n")
    for h, nombres in sorted(dups.items(), key=lambda kv: -len(kv[1]))[:args.max]:
        print(f"  sha256 {h[:12]}  ({len(nombres)} ficheros, {os.path.getsize(os.path.join(repo, nombres[0]))} B)")
        for n in nombres:
            print(f"      {n}")
    if len(dups) > args.max:
        print(f"  ... y {len(dups) - args.max} grupos mas")
    print("\nSugerencia: convierte los sobrantes en symlinks al canonico, o bórralos")
    print("y deja la referencia en el informe del ciclo.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
