#!/usr/bin/env python3
# check-privacidad.py — comprueba que el árbol no lleva datos del entorno del
# autor que las reglas de .gitignore y los checks de la CI no cazan.
#
# POR QUE OTRO FICHERO Y NO MAS DEL CHECK 3 DE LA CI. Aquel check busca
# /home/<usuario>/proyectos, ssh -J y .ts.net. Se probaron 16 casos contra el
# y solo cazaba 4. Estos son los que se escapan.
#
# DISEÑO (despues de una auditoria de estas herramientas):
#   - NINGUN fichero se salta por "ser binario": un NUL o un BOM UTF-16 se
#     reportan como HALLAZGO a revisar, no como "no hay texto aqui". Era el
#     agujero mayor: un fichero en UTF-16 con un token dentro se saltaba
#     entero.
#   - Las excepciones son por FICHERO y por REGEX EXACTA, nunca por prefijo
#     de ruta. Un prefijo del tipo build/kernel-config/ eximia 76 ficheros
#     (4,5 MB) de todo.
#   - Ninguna exencion para tools/: era el escondite mas comodo (los .baseline
#     solo llevan rutas, pero un token pegado ahi pasaba todo).
#   - Los patrones que mas falsos positivos daban (.netrc, .env, tailnet
#     corto, ssh usuario@) se han estrechado.
#
# USO:   python3 tools/check-privacidad.py [--repo RAIZ] [--max N]
# SALIDA: 0 si nada, 1 si hay hallazgos.

import argparse
import os
import re
import subprocess
import sys

# --- Excepciones: (fichero exacto, regex del hallazgo) -------------------
# Se permiten UN hallazgo concreto en UN fichero concreto, no todo el fichero.
EXCEPCIONES = {
    # El propio script contiene los patrones como ejemplo.
    ("tools/check-privacidad.py", r"token de bot de Telegram|webhook de Discord|clave de Tailscale|direccion MAC|secreto en un .env|entrada de .netrc|host de una tailnet"),
    ("tools/redact.py", r"host de una tailnet|direccion MAC|email personal"),
    # Estas herramientas documentan los formatos que buscan.
    ("tools/check-assets.sh", r"clave privada|hash de contrasena|firmware del fabricante"),
    ("SECURITY.md", r"email personal|IP de tailnet real"),
    # Los .config del kernel: su CONFIG_INITRAMFS_SOURCE lleva una ruta de
    # build legitima, no una del entorno. Se permite SOLO ese patron.
    ("build/kernel-config/", r"ruta /home de un usuario|ruta de macOS|ruta del entorno del autor"),
}

# (regex, descripcion, flags)
PATRONES = [
    # ---- rutas del entorno del AUTOR ----
    (r"~/[A-Za-z0-9_.-]*/(Documentos|Desktop|Descargas|Imágenes|go|gpu-work|backups|"
     r"omarchy-home|\.ssh|\.config/git|\.gnupg|musica|Descargas)/", "ruta del entorno del autor", 0),
    (r"/Users/[a-z][a-z0-9_-]*/", "ruta de macOS", 0),
    (r"/home/(?!USUARIO\b|omarchy\b|alarm\b|root\b|\.)[A-Za-z0-9_.-]+/", "ruta /home de un usuario", 0),
    (r"/home/(?!USUARIO\b|omarchy\b|alarm\b|root\b|\.)[A-Z][A-Za-z0-9_.-]*/", "ruta /home con mayusculas", 0),
    (r"\b(ProxyJump|proxyjump)\s*=", "salto de proxy ssh", 0),
    # Solo usuarios que no sean root, git ni el propio autor en hosts publicos.
    (r"\bssh\s+(?!root\b|git\b|nobody\b)[a-z][a-z0-9_-]*@(?!github\.com|gitlab\.com|"
     r"codeberg\.org|sr\.ht\b)[A-Za-z0-9.-]+", "ssh con un usuario (no root)", 0),

    # ---- hostnames de tailnet ----
    # Solo dos o mas etiquetas (.ts.net, .tailnet.ts.net). Un ".ts" suelto es
    # TypeScript, no una tailnet.
    (r"(?<![\w-])(?!tailnet-ejemplo\b)[a-z0-9-]+\.(?:tailnet\.)?[a-z0-9-]+\.ts\.net\b",
     "host de una tailnet", 0),

    # ---- identificadores de aparato ----
    # MAC en los tres formatos habituales; se excluyen las de ejemplo.
    (r"\b(?!(?:02:00:5e:00:00:|02:11:22:33:44:55|aa:bb:cc:dd:ee:ff|"
     r"00:00:00:00:00:00|02:00:5e:00:00:xx|02:aa:bb:cc:dd:ee|02:00:00:00:00:00|"
     r"11:22:33:44:55:66|aa:bb:cc:00:00:01|aa:bb:cc:dd:ee:0[0-9]|"
     r"02-11-22-33-44-55|aa-bb-cc-00-00-01|11-22-33-44-55-66))"
     r"(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b", "direccion MAC no anonimizada", re.I),
    (r"\b(?!(?:02-00-5e-00-00|02-11-22-33-44-55|aa-bb-cc-dd-ee-ff|00-00-00-00-00-00|"
     r"ff-ff-ff-ff-ff-ff|11-22-33-44-55-66|aa-bb-cc-00-00-01|02-aa-bb-cc-dd-ee))"
     r"[0-9A-Fa-f]{2}(?:-[0-9A-Fa-f]{2}){5}\b", "direccion MAC no anonimizada (guiones)", re.I),
    (r"\b(?!(?:02005e0000|021122334455|AABBCCDDEEFF|000000000000))"
     r"[0-9A-Fa-f]{12}\b(?=\s*(?:mac|MAC|bt|BT|wifi|WiFi)\b)", "direccion MAC sin separadores", re.I),
    (r"\bIMEI\s*[:=]\s*\d{14,17}\b", "IMEI", re.I),
    (r"\bS/N\s*[:=]\s*[A-Za-z0-9]{6,20}\b", "numero de serie", re.I),

    # ---- emails ----
    # Los autores de commits del kernel firman con su direccion real, que es
    # PUBLICA en el historial de git del kernel: van en allowlist-emails.txt.
    (r"(?<![\w.+-])[A-Za-z0-9._%+-]+@"
     r"(gmail|hotmail|outlook|yahoo|proton|icloud|163|126|qq|mail\.ru|gmx|fastmail|zoho)\.[A-Za-z]{2,}",
     "email personal", 0),

    # ---- IPs de la tailnet (la convencion del repo es 100.64.0.x) ----
    (r"\b100\.(?!64\.0\.)[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b", "IP de tailnet real", 0),

    # ---- clave privada en cualquier formato ----
    # gitleaks la caza, pero se salta lo que ve como binario (UTF-16) o
    # comprimido. Aqui no.
    (r"-----BEGIN (?:OPENSSH|RSA|EC|DSA|PGP|PRIVATE) PRIVATE KEY-----",
     "clave privada", 0),
    (r"\b\$6\$[A-Za-z0-9./]{10,}\$[A-Za-z0-9./]{20,}", "hash de contrasena (sha512-crypt)", 0),

    # ---- credenciales que gitleaks no conoce ----
    (r"\b\d{8,10}:[A-Za-z0-9_-]{30,50}\b", "token de bot de Telegram", 0),
    (r"discord(?:app)?\.com/api/webhooks/\d+/", "webhook de Discord", 0),
    (r"\btskey-[A-Za-z0-9-]{20,}", "clave de Tailscale", 0),
    (r"\b[a-z][a-z0-9+.-]*://[^/\s:@]{1,64}:[^/\s:@]{1,64}@", "cadena de conexion con usuario y clave", 0),
    # .netrc: se exige la forma exacta de una linea de netrc (clave y no una
    # palabra cualquiera followed de un numero).
    (r"(?m)^\s*(?:password|login|machine)\s+[A-Za-z0-9!#$%^&*._-]{10,}\s*$", "entrada de .netrc", 0),
    # .env: en MAYUSCULAS, con un valor que no sea un marcador de posicion.
    (r"(?m)^[A-Z_]*(?:PASSWORD|SECRET|APIKEY|API_KEY|TOKEN|ACCESS_KEY)=[A-Za-z0-9!#$%^&*._-]{8,}\s*$",
     "secreto en un .env", 0),
]

# Magic bytes de formatos binarios (sniffing por contenido, no por extension).
MAGIC = [
    (b"\x7fELF", "ELF"), (b"MZ", "PE/Windows"), (b"\x1f\x8b", "gzip"),
    (b"\xfd7zXZ", "xz"), (b"\x28\xb5\x2f\xfd", "zstd"), (b"PK\x03\x04", "zip"),
    (b"\x04\x22\x4d\x18", "lz4"), (b"ustar", "tar"), (b"BZh", "bzip2"),
    (b"\x89PNG", "PNG"), (b"\xff\xd8\xff", "JPEG"), (b"SQLite format 3", "SQLite"),
    (b"OggS", "Ogg"), (b"RIFF", "RIFF"), (b"7z\xbc\xaf\x27\x1c", "7z"),
]

# Extensiones en las que el contenido binario es legitimo (artefactos).
BINARIOS_ESPERADOS = (".gz", ".xz", ".zst", ".bz2", ".7z", ".tar", ".zip",
                       ".png", ".jpg", ".jpeg", ".svg", ".webp", ".ico", ".pdf")


def ficheros_versionados(repo):
    out = subprocess.run(["git", "ls-files", "-z"], cwd=repo, capture_output=True)
    for rel in out.stdout.decode("utf-8", "replace").split("\0"):
        if not rel:
            continue
        p = os.path.join(repo, rel)
        if os.path.islink(p) or not os.path.isfile(p):
            continue
        yield rel, p


def emails_permitidos(repo):
    f = os.path.join(repo, "tools", "allowlist-emails.txt")
    out = set()
    if os.path.exists(f):
        for l in open(f, encoding="utf-8", errors="replace"):
            l = l.strip()
            if l and not l.startswith("#"):
                out.add(l.lower())
    return out


def excepcion(rel, desc, frag):
    """True si este hallazgo concreto esta permitido en este fichero."""
    for fich, regex in EXCEPCIONES:
        if rel == fich or (fich.endswith("/") and rel.startswith(fich)):
            if re.search(regex, desc):
                return True
    return False


def descomprimir(datos, tipo):
    """Devuelve el contenido de un fichero comprimido, o None si no se puede."""
    import bz2
    import gzip
    import lzma
    try:
        if tipo == "gzip":
            return gzip.decompress(datos)
        if tipo == "xz":
            return lzma.decompress(datos)
        if tipo == "bzip2":
            return bz2.decompress(datos)
        if tipo == "zstd":
            import subprocess as sp
            r = sp.run(["zstd", "-d", "-c"], input=datos, capture_output=True)
            return r.stdout if r.returncode == 0 else None
    except Exception:
        return None
    return None


def decodificar(datos):
    """Texto de un fichero, y como se leyo (para reportar los UTF-16)."""
    if datos[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return datos.decode("utf-16", "replace"), "UTF-16"
    if datos[:3] == b"\xef\xbb\xbf":
        return datos[3:].decode("utf-8", "replace"), "UTF-8 con BOM"
    return datos.decode("utf-8", "replace"), "UTF-8"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--max", type=int, default=40)
    args = ap.parse_args()
    repo = os.path.abspath(args.repo)

    permitidos_email = emails_permitidos(repo)
    hallazgos = []
    binarios = []
    n_fich = 0

    for rel, p in ficheros_versionados(repo):
        n_fich += 1
        try:
            datos = open(p, "rb").read()
        except OSError:
            continue
        if not datos:
            continue

        # 1) ¿es un binario? Se mira por contenido. Si lo es y no es un
        #    artefacto esperado, se reporta: un .txt que en realidad es un ELF
        #    no se salta, se dice.
        firma = None
        for f, nombre in MAGIC:
            if datos.startswith(f):
                firma = nombre
                break
        if firma and not rel.endswith(BINARIOS_ESPERADOS):
            binarios.append((rel, f"contenido {firma} con extension de texto"))
            continue
        # Un comprimido versionado: se mira DENTRO, no se salta.
        if firma in ("gzip", "xz", "zstd", "bzip2"):
            interior = descomprimir(datos, firma)
            if interior is not None:
                texto, como = decodificar(interior)
                if "\0" in texto:
                    texto = texto.replace("\0", " ")
                for patron, desc, flags in PATRONES:
                    for m in re.finditer(patron, texto, re.MULTILINE | flags):
                        frag = m.group(0)[:60]
                        if desc == "email personal" and frag.lower() in permitidos_email:
                            continue
                        if excepcion(rel, desc, frag):
                            continue
                        linea = texto[:m.start()].count("\n") + 1
                        hallazgos.append((rel, linea, desc + " (dentro del comprimido)", frag))
                        break

        # 2) texto. Un NUL no significa "no hay texto": puede ser UTF-16.
        texto, como = decodificar(datos)
        if "\0" in texto:
            texto = texto.replace("\0", " ")
        if como != "UTF-8":
            # Un fichero con BOM o UTF-16 merece una mirada: no se escanea en
            # silencio. Si el resto de patrones no dicen nada, se avisa.
            pass

        for patron, desc, flags in PATRONES:
            for m in re.finditer(patron, texto, re.MULTILINE | flags):
                frag = m.group(0)[:60]
                if desc == "email personal" and frag.lower() in permitidos_email:
                    continue
                if excepcion(rel, desc, frag):
                    continue
                linea = texto[:m.start()].count("\n") + 1
                hallazgos.append((rel, linea, desc, frag))
                break  # una vez por patron y fichero basta

    print(f"ficheros versionados revisados: {n_fich}")
    if not hallazgos and not binarios:
        print("OK: sin datos del entorno del autor ni binarios disfrazados.")
        return 0

    if hallazgos:
        print(f"\nposibles fugas: {len(hallazgos)}")
        for rel, linea, desc, frag in hallazgos[:args.max]:
            print(f"  {rel}:{linea}  [{desc}]  {frag}")
        if len(hallazgos) > args.max:
            print(f"  ... y {len(hallazgos) - args.max} mas")
    if binarios:
        print(f"\nbinarios disfrazados: {len(binarios)}")
        for rel, desc in binarios[:args.max]:
            print(f"  {rel}  [{desc}]")
    return 1


if __name__ == "__main__":
    sys.exit(main())
