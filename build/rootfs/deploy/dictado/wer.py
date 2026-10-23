#!/usr/bin/env python3
"""WER de un motor de dictado contra ref.tsv (nombre<TAB>duracion<TAB>texto).
Uso: wer.py ref.tsv hip.tsv   (hip.tsv: nombre<TAB>segundos_de_proceso<TAB>texto)
Normaliza: minusculas, sin puntuacion, sin tildes (la referencia MLS usa ortografia antigua: «á los», «fué»)."""
import re, sys, unicodedata


def norm(t):
    t = unicodedata.normalize("NFD", t.lower())
    t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9ñ ]+", " ", t).split()


def dist(a, b):
    d = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        prev, d[0] = d[0], i
        for j, y in enumerate(b, 1):
            prev, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, prev + (x != y))
    return d[len(b)]


ref = {l.split("\t")[0]: l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()}
err = words = 0
audio = proc = 0.0
for l in open(sys.argv[2]):
    if not l.strip():
        continue
    n, secs, txt = (l.rstrip("\n").split("\t") + [""])[:3]
    r = norm(ref[n][2])
    e = dist(r, norm(txt))
    err += e; words += len(r); audio += float(ref[n][1]); proc += float(secs)
    print(f"{n}  wer={e / len(r):.3f}  rtf={float(secs) / float(ref[n][1]):.3f}  {txt.strip()[:90]}")
print(f"TOTAL wer={err / words:.3f}  rtf={proc / audio:.3f}  audio={audio:.1f}s  proceso={proc:.1f}s")
