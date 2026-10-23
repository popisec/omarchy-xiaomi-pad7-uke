#!/usr/bin/env python3
"""Vuelca nodos del DT de Android (arbol /proc/device-tree copiado a ficheros) resolviendo phandles.
Uso: dt-dump.py <raiz-dt> <ruta-relativa-nodo> [-r]   (solo lectura)"""
import os, sys, struct
root = os.path.abspath(sys.argv[1]); node = sys.argv[2]; rec = '-r' in sys.argv
def phmap():
    m = {}
    for d, _, fs in os.walk(root):
        for f in ('phandle', 'linux,phandle'):
            if f in fs:
                v = open(os.path.join(d, f), 'rb').read()
                if len(v) == 4: m[struct.unpack('>I', v)[0]] = os.path.relpath(d, root)
    return m
PH = phmap()
def fmt(name, b):
    if not b: return 'true'
    if all((32 <= c < 127) or c == 0 for c in b) and b[-1] == 0 and b[0] != 0:
        return '"' + '", "'.join(s.decode() for s in b[:-1].split(b'\0')) + '"'
    if len(b) % 4 == 0:
        w = struct.unpack('>%dI' % (len(b) // 4), b)
        out = []
        for x in w:
            out.append(('&' + PH[x].split('/')[-1] + '(' + hex(x) + ')') if (x in PH and x > 0xff) else hex(x))
        return '<' + ' '.join(out) + '>'
    return b.hex()
def dump(p, ind=0):
    full = os.path.join(root, p)
    print(' ' * ind + os.path.basename(p) + ' {')
    for f in sorted(os.listdir(full)):
        fp = os.path.join(full, f)
        if os.path.isfile(fp):
            print(' ' * (ind + 2) + f + ' = ' + fmt(f, open(fp, 'rb').read()) + ';')
    if rec:
        for f in sorted(os.listdir(full)):
            if os.path.isdir(os.path.join(full, f)): dump(os.path.join(p, f), ind + 2)
    print(' ' * ind + '};')
dump(node)
