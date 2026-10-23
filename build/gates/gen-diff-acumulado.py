#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen-diff-acumulado.py — genera UN diff autocontenido que lleva el arbol del
proyecto desde el commit base del fork hasta el estado instrumentado actual.

POR QUÉ (1-oct-2026). Antes los parches versionados llegaban hasta K18, pero:
  - K19 (volcado SME/CB/tablas), K20 (uke_gmu_shared), K21 (CBpage) y K23/K23b
    (geometria + decode del dump) vivian SOLO dentro de build/kernel-pokes/k18-tree,
    que esta en .gitignore y no tiene .git;
  - y k13-tree (la base "pristine") tiene cambios en arm-smmu.{c,h}, qcom.c,
    msm_iommu.c y msm_kms.c que NO estan ni en el commit del fork ni en su
    working tree, asi que tampoco era reconstruible desde ahi.
Es decir: el kernel que hay en la tablet no se podia reconstruir desde el repo.
Este diff lo arregla: base = commit d1c7ef2e0 del fork, y el diff lleva TODO.

Uso:
  gen-diff-acumulado.py                 # escribe el diff + el manifiesto de shas
  gen-diff-acumulado.py --check         # solo comprueba que el diff aplica en seco

Comprobacion de aplicabilidad (la que de verdad importa):
  git -C ~/gpu-work/palawan-linux stash list   # el arbol del hermano esta sucio
  # en un arbol NUEVO de d1c7ef2e0:
  patch -p1 --dry-run < build/gates/patches/ACUMULADO-*.diff
"""
import hashlib
import os
import subprocess
import sys

def _repo_root():
    """Raiz del repo: se sube hasta el directorio con .git, para que el script
    funcione recien clonado y no dependa de donde este el arbol."""
    d = os.path.dirname(os.path.abspath(__file__))
    while d != "/" and not os.path.isdir(os.path.join(d, ".git")):
        d = os.path.dirname(d)
    return d


R = _repo_root()


HOME = os.path.expanduser("~")
FORK = HOME + "/gpu-work/palawan-linux"
TREE = R + "/build/kernel-pokes/k18-tree"
OUTDIR = R + "/build/gates/patches"
BASE_COMMIT = "d1c7ef2e0"
NAME = "ACUMULADO-palawan-%s-a-k24.diff" % BASE_COMMIT

# Solo fuentes: los .o/.ko/.cmd del arbol de build no interesan y hacen el diff
# inmanejable.
SRC_EXT = (".c", ".h", ".dts", ".dtsi", ".rs")
SRC_NAMES = ("Makefile", "Kconfig", "Kbuild")
SKIP_DIRS = {".git", "Documentation", "tools", "samples", "scripts/dtc"}


def is_src(p):
    return p.endswith(SRC_EXT) or os.path.basename(p) in SRC_NAMES


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def walk(root):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        rel = os.path.relpath(dirpath, root)
        if any(rel == d or rel.startswith(d + os.sep) for d in SKIP_DIRS):
            dirnames[:] = []
            continue
        dirnames[:] = [d for d in dirnames if d not in (".git",)]
        for fn in filenames:
            if is_src(fn):
                out.append(os.path.relpath(os.path.join(dirpath, fn), root))
    return sorted(out)


def main():
    if not os.path.isdir(FORK) or not os.path.isdir(TREE):
        sys.exit("ABORT: falta %s o %s" % (FORK, TREE))
    head = subprocess.run(["git", "-C", FORK, "rev-parse", "--short", "HEAD"],
                          capture_output=True, text=True).stdout.strip()
    dirty = subprocess.run(["git", "-C", FORK, "status", "--short"],
                           capture_output=True, text=True).stdout.strip()
    print("fork: %s  HEAD=%s  (%s)" % (FORK, head,
                                       "working tree SUCIO, el diff lo absorbe"
                                       if dirty else "working tree limpio"))
    if head != BASE_COMMIT:
        print("AVISO: el diff se genero contra %s y el fork esta ahora en %s."
              % (BASE_COMMIT, head))

    a = set(walk(FORK))
    b = set(walk(TREE))
    only_b = sorted(b - a)
    # Candidatos: comparar primero en disco (rapido, sin subprocess) y solo
    # preguntarle a git por ESOS. Un 'git show' por cada uno de los ~70k
    # ficheros tarda una eternidad.
    cand = sorted(f for f in (a & b)
                  if sha(os.path.join(FORK, f)) != sha(os.path.join(TREE, f)))
    # El lado "a" de cada fichero se toma del COMMIT (git show), no del working
    # tree: el repo del hermano esta sucio (5 ficheros sin commitear, dos de
    # ellos en el juego) y si el diff se generara contra el disco no aplicaria
    # sobre un checkout limpio, que es justamente lo que hay que poder hacer.
    def base_bytes(f):
        r = subprocess.run(["git", "-C", FORK, "show", "%s:%s" % (BASE_COMMIT, f)],
                           capture_output=True)
        return r.stdout if r.returncode == 0 else None

    changed = []
    for f in cand:
        bb = base_bytes(f)
        if bb is None or hashlib.sha256(bb).hexdigest() != sha(os.path.join(TREE, f)):
            changed.append(f)
    print("fuentes: fork=%d tree=%d | candidatos en disco=%d | distintos vs %s=%d"
          % (len(a), len(b), len(cand), BASE_COMMIT, len(changed)))
    for f in only_b:
        print("  SOLO EN EL ARBOL PROYECTO: %s" % f)

    targets = changed + only_b
    if not targets:
        print("nada que documentar")
        return

    if "--check" in sys.argv:
        print("modo --check: no se escribe nada")
        return

    os.makedirs(OUTDIR, exist_ok=True)
    out = os.path.join(OUTDIR, NAME)
    chunks = []
    tmp = "/tmp/opencode/uke-base-file"
    for f in targets:
        pb = os.path.join(TREE, f)
        if f in only_b:
            pa = "/dev/null"
        else:
            with open(tmp, "wb") as tf:
                tf.write(base_bytes(f))
            pa = tmp
        r = subprocess.run(["diff", "-u", "--label", "a/" + f, "--label", "b/" + f,
                            pa, pb], capture_output=True, text=True)
        body = r.stdout
        if not body:
            continue
        chunks.append(body)

    header = """# ACUMULADO — del commit base del fork al estado K24 del proyecto omarchy-uke
# Generado por build/gates/gen-diff-acumulado.py el %s
#
# BASE:  commit %s de ~/gpu-work/palawan-linux (rama palawan/v7.2-rc2), taken con
#        'git show', NO desde el working tree de ese repo (que esta sucio con 5
#        ficheros sin commitear). Por tanto APLICA sobre un checkout limpio.
# APLICAR:
#        git -C ~/gpu-work/palawan-linux archive %s | tar -x -C /tmp/arbol
#        patch -p1 -d /tmp/arbol < este-fichero
#        make O=/tmp/build ARCH=arm64 LLVM=1 Image      (config: build/kernel-config/k23b.config)
# ALCANCE: todo el proyecto (K1..K24) en un solo diff. Los diffs por peldanio
#        k1..k18 de este directorio siguen siendo historial, pero NO hay que
#        aplicarlos: este los supersede.
# POR QUE: hasta 1-oct-2026 el kernel que estaba en la tablet (K23) no era
#        reconstruible desde el repo: K19/K20/K21/K23 vivian solo en
#        build/kernel-pokes/k18-tree (ignorado por git) y k13-tree tenia
#        cambios que no estaban ni en el commit del fork.
#
# FICHEROS (%d):
%s
""" % (
        subprocess.run(["date", "-Iseconds"], capture_output=True,
                       text=True).stdout.strip(),
        BASE_COMMIT, BASE_COMMIT, len(targets),
        "\n".join("#   %s" % f for f in targets))

    with open(out, "w", encoding="utf-8") as f:
        f.write(header)
        f.write("\n".join(chunks))
    print("escrito %s (%d B)" % (out, os.path.getsize(out)))

    # manifiesto de shas del estado destino: permite verificar el arbol sin el diff
    man = os.path.join(OUTDIR, "SHA-ARBOL-K24.txt")
    with open(man, "w", encoding="utf-8") as f:
        f.write("# sha256 de los ficheros que fija %s (destino = build/kernel-pokes/k18-tree)\n"
                "# Para reconstruir: checkout de %s + este diff, y comprobar con\n"
                "#   sha256sum -c SHA-ARBOL-K24.txt  (desde la raiz del arbol)\n" % (NAME, BASE_COMMIT))
        for t in targets:
            f.write("%s  %s\n" % (sha(os.path.join(TREE, t)), t))
    print("escrito %s (%d shas)" % (man, len(targets)))


if __name__ == "__main__":
    main()
