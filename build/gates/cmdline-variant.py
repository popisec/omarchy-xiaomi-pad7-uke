#!/usr/bin/env python3
"""cmdline-variant.py — variante de un boot.img v4 YA GATEADO que solo cambia la cmdline (17-oct-2026).

Uso: cmdline-variant.py <base.img> <sha256-base> <salida.img> <token> [<token>...]
- Verifica el sha de la base (el boot que paso todos los gates del repack).
- Anade los tokens al final del campo cmdline de la cabecera v4 (offset 44, 1536 B), separados por espacio.
- Gates: magia ANDROID!, header v4, cada token nuevo no estaba y queda x1, cmdline final < 1536 B,
  y la imagen de salida difiere de la base SOLO dentro del campo cmdline (byte a byte fuera de el).
Sirve para bisect por module params sin recompilar ni re-gatear el kernel (los gates del repack exigen la
cmdline de L57 byte a byte, por eso la variante se hace despues y aparte).
"""
import hashlib, struct, sys

CMD_OFF, CMD_FIELD = 44, 1536


def die(m):
    print("FALLO:", m); sys.exit(1)


base, want, out, toks = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
if not toks:
    die("sin tokens")
b = open(base, "rb").read()
if hashlib.sha256(b).hexdigest() != want:
    die("sha de la base != %s" % want[:16])
if b[:8] != b"ANDROID!" or struct.unpack_from("<I", b, 40)[0] != 4:
    die("la base no es boot v4")
field = b[CMD_OFF:CMD_OFF + CMD_FIELD]
cmd = field.split(b"\x00")[0]
for t in toks:
    if t.encode() in cmd.split():
        die("token %r ya estaba" % t)
new = cmd + b" " + b" ".join(t.encode() for t in toks)
if len(new) >= CMD_FIELD:
    die("cmdline de %d B no cabe" % len(new))
for t in toks:
    if new.split().count(t.encode()) != 1:
        die("token %r no queda x1" % t)
o = bytearray(b)
o[CMD_OFF:CMD_OFF + CMD_FIELD] = new + b"\x00" * (CMD_FIELD - len(new))
diff = [i for i in range(len(b)) if b[i] != o[i]]
if any(not (CMD_OFF <= i < CMD_OFF + CMD_FIELD) for i in diff):
    die("hay bytes cambiados fuera del campo cmdline")
open(out, "wb").write(o)
print("OK  base %s.. -> %s" % (want[:16], out))
print("OK  cmdline %d -> %d B (+%s); %d bytes cambiados, todos en el campo cmdline" % (len(cmd), len(new), " ".join(toks), len(diff)))
print("OK  sha256 =", hashlib.sha256(o).hexdigest())
