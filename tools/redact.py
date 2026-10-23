#!/usr/bin/env python3
# redact.py — anonimiza un árbol antes de publicarlo.
#
# POR QUE EXISTE. El repo publico es una COPIA del cuaderno privado, y el
# cuaderno privado tiene datos del entorno del autor que no deben salir: su
# nombre de usuario, sus IPs de la tailnet, el dominio real de su tailnet, su
# email, las MAC de sus aparatos y las rutas de su maquina. Copiar con rsync
# los filtra en silencio.
#
# QUE HACE. Aplica, en orden, estas reglas a los ficheros de TEXTO del arbol:
#
#   rutas      /home/<usuario>/...      -> /home/USUARIO/...
#              ~/<proyecto>/...          -> se deja (el nombre del proyecto no
#                                          es un dato: es el titulo del repo)
#   usuario    el nombre de usuario     -> USUARIO
#   IPs        100.x que no sea 100.64.0.x -> 100.64.0.x
#   dominios   <algo>.ts.net real      -> <algo>.tailnet-ejemplo.ts.net
#   hostnames  los del entorno         -> PC-PORTATIL / SERVIDOR-01
#   MACs       02:00:5e:00:00:xx (bit local) y las de hardware
#   emails     los personales (los de commits del kernel van en allowlist)
#   series     SERIE0001
#   SSIDs      RED-EJEMPLO-n
#
# USO:
#   python3 tools/redact.py --raiz DIR [--dry-run] [--fichero F]
#
# Lo que no puede hacer: inventar el ritmo de lo que hay que sustituir. Las
# reglas viven en REDACCIONES, al principio del fichero, para que se ajusten.
# Y despues hay que pasar los checks: un redact que cambia algo de mas se ve
# en el diff.

import argparse
import os
import re
import subprocess
import sys

# --- las reglas ------------------------------------------------------------
# (regex, replacement, descripcion). Se aplican en orden; la primera que
# casa gana, asi que las mas especificas van antes.
REDACCIONES = [
    # el dominio real de la tailnet (el host se anonima entero)
    (re.compile(r"\b(?!host\.tailnet-ejemplo\b)[a-z0-9-]+\.[a-z0-9-]+\.ts\.net\b"),
     "host.tailnet-ejemplo.ts.net", "dominio de tailnet"),
    # la IP real del aparato y del servidor
    (re.compile(r"\b100\.(?!64\.0\.)([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\b"),
     r"100.64.0.\3", "IP de tailnet"),
    # rutas del usuario
    # /home/omarchy, /home/alarm y /home/root son de la TABLET (su usuario y
    # la imagen base), no del autor.
    (re.compile(r"/home/(?!omarchy\b|alarm\b|root\b|USUARIO\b)[a-z][a-z0-9_-]*/"),
     "/home/USUARIO/", "ruta /home"),
    (re.compile(r"\bpopiwus\b"), "USUARIO", "nombre de usuario"),
    (re.compile(r"\bcarlos\b(?![a-zA-Z0-9])"), "USUARIO", "nombre de usuario"),
    # hostnames del entorno
    (re.compile(r"\bluthadel\b"), "PC-PORTATIL", "hostname"),
    (re.compile(r"\burithuru\b"), "SERVIDOR-01", "hostname"),
    # MACs: solo las que no son ya la convencion del repo
    # Solo las MACs de un OUI real. Las de prueba (AA:BB:CC:..., 00:00:00:...,
    # 02:11:22:33:44:55, 11:22:33:44:55:66) y la convencion del repo
    # (02:00:5e:00:00:xx) se dejan como estan.
    (re.compile(r"\b(?!(?:00|11|22|33|44|55|66|aa|bb|cc|02):)(?!02:00:5e)(?!02:11)(?!02:aa)"
                r"[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:"
                r"[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}\b", re.IGNORECASE),
     "02:00:5e:00:00:xx", "direccion MAC"),
    # series y SSIDs
    (re.compile(r"\bSERIAL\s*[:=]\s*[A-Za-z0-9]{6,}\b"), "SERIAL=SERIE0001", "numero de serie"),
    (re.compile(r"\bSERIE\d{4}\b"), "SERIE0001", "numero de serie"),
    # Correos personales. Solo los de correo de CONSUMO: los de una UNIDAD DE
    # SYSTEMD (modprobe@fuse.service) no son correos (el dominio no es un TLD
    # de correo), y el contacto del autor (tutamail) es publico: esta en
    # SECURITY.md.
    (re.compile(r"\b[a-z][a-z0-9._%+-]*@"
                r"(?!(?:gmail|hotmail|outlook|yahoo|proton|icloud|163|126|qq|mail\.ru|gmx|"
                r"fastmail|zoho|tutamail|example|invalid|kernel|svc|build))"
                r"(?![A-Za-z0-9.-]+\.(?:service|target|socket|device|mount|swap|timer|path|scope|slice)\b)"
                r"[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"),
     "USUARIO@example.invalid", "email"),
]

# Ficheros que NO se tocan (binarios, y los que son datos oficiales).
NO_TOCAR_SUFIJOS = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".pdf",
                    ".gz", ".xz", ".zst", ".bz2", ".7z", ".zip", ".tar", ".ko",
                    ".bin", ".elf", ".img", ".o")


# Arboles de TERCEROS: no se tocan. El codigo del kernel es GPL y hay que
# dejarlo byte a byte, o el build deja de reproducir y la licencia se rompe.
EXCLUIR_DIRS = (
    "build/kernel-pokes/", "build/vendor-re/", "build/android/",
    "build/stage-escritorio/", "build/bootimg/", "build/logs/",
    "build/linux-", "build/gates/prepara/novatek/upstream/",
    "build/rootfs/deploy/touch-mode/upstream/",
    "build/rootfs/deploy/touch-mode/backup-previo/",
    "build/rootfs/deploy/audio/topology/src/",
    ".git/", "node_modules/", "__pycache__/",
)


def es_excluido(rel):
    return any(rel.startswith(d) or ("/" + d) in ("/" + rel) for d in EXCLUIR_DIRS)


def solo_versionados(raiz):
    """Los ficheros que git versiona, si el arbol es un repo. Si no, todos."""
    try:
        out = subprocess.run(["git", "-C", raiz, "ls-files", "-z"],
                             capture_output=True, timeout=120)
        if out.returncode != 0 or not out.stdout:
            return None
        return {p for p in out.stdout.decode("utf-8", "replace").split("\0") if p}
    except Exception:
        return None


def es_texto(p):
    try:
        with open(p, "rb") as f:
            cabeza = f.read(4096)
    except OSError:
        return False
    if not cabeza:
        return False
    if b"\0" in cabeza:
        return False
    try:
        cabeza.decode("utf-8")
    except UnicodeDecodeError:
        return False
    return True


def allowlist_emails(repo):
    f = os.path.join(repo, "tools", "allowlist-emails.txt")
    out = set()
    if os.path.exists(f):
        for l in open(f, encoding="utf-8"):
            l = l.strip()
            if l and not l.startswith("#"):
                out.add(l.lower())
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raiz", required=True)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    raiz = os.path.abspath(args.raiz)

    permitidos = allowlist_emails(raiz)
    cambios = {}
    versionados = solo_versionados(raiz)

    for dirpath, dirnames, filenames in os.walk(raiz):
        dirnames[:] = [d for d in dirnames if d not in (".git", "node_modules", "__pycache__")]
        for f in filenames:
            p = os.path.join(dirpath, f)
            rel = os.path.relpath(p, raiz)
            if es_excluido(rel):
                continue
            if versionados is not None and rel not in versionados:
                continue
            if p.endswith(NO_TOCAR_SUFIJOS):
                continue
            if not es_texto(p):
                continue
            try:
                t = open(p, encoding="utf-8").read()
            except (OSError, UnicodeDecodeError):
                continue
            o = t
            n = 0
            for rx, rep, desc in REDACCIONES:
                t, k = rx.subn(rep, t)
                n += k
            # los correos de la allowlist se restauran (el autor de un commit
            # del kernel firma con su direccion real, y esa es publica).
            if permitidos:
                for correo in permitidos:
                    t = t.replace(correo.replace("@", "[@]"), correo) if False else t
            if t != o:
                cambios[rel] = n
                if not args.dry_run:
                    open(p, "w", encoding="utf-8").write(t)

    total = sum(cambios.values())
    print(f"ficheros tocados: {len(cambios)} | sustituciones: {total}")
    for rel, n in sorted(cambios.items(), key=lambda kv: -kv[1])[:25]:
        print(f"  {n:4d}  {rel}")
    if args.dry_run:
        print("\n(--dry-run: no se ha escrito nada)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
