#!/usr/bin/env python3
"""gen-manifest.py -- cierre de dependencias OFFLINE del escritorio Omarchy para la uke.

Solo PC, solo lectura sobre: el stage (build/stage-escritorio, .PKGINFO por bsdtar), la imagen del
rootfs (debugfs SIN -w: base de datos local de pacman + existencia de ficheros) y las DB de sync
del stage. Escribe unicamente en --out (por defecto ../manifest).

Que calcula (es lo que se hizo a mano el 17-oct para modetest, ahora reproducible):
  1. tier1  = cierre estricto de las raices (omarchy, hyprland, quickshell, sddm, mesa, fuentes...)
              resuelto contra (instalado segun la DB de la imagen) + (stage). Lo que ya satisface
              la base NO se reinstala: la base no se toca (salvo lo que un paquete fije por version).
  2. tier2  = paquetes del stage que no son dependencia pero son los que Omarchy lanza (foot, kitty,
              hyprlock, hypridle, waybar, grim, slurp...): paridad con el escritorio que funciono en L57.
  3. tier3  = subidas de version de paquetes de la base (systemd 262, openssh, openssl...): EXCLUIDAS
              (no hacen falta: la base ya satisface todas las dependencias; y subir systemd/openssh
              por SSH es el riesgo gratuito).
  4. integridad del estado final (deps rotas, conflictos, replaces), orden topologico (lotes del
     stage), conflictos de ficheros contra lo instalado y contra el disco de la imagen (el rootfs
     v8 lleva 171 paquetes volcados con bsdtar SIN registrar en pacman: sus ficheros existen sin dueno
     y pacman -U los rechazaria -> esos lotes llevan --overwrite).
  5. paquetes opcionales que NO estan en el stage (xdg-terminal-exec, udiskie, mesa-utils...) con URL y
     sha256 de la DB de sync (NO se descargan aqui).

Uso:  python3 -I gen-manifest.py [--stage DIR] [--image IMG] [--out DIR] [--batch-mib N] [--no-extras]
Salida: exit 0 si todo cuadra; != 0 si hay deps sin proveedor, rotas, conflictos o violaciones de orden.
"""
import argparse, collections, concurrent.futures as cf, functools, hashlib, json, os, re, subprocess, sys, tarfile
import tempfile

# Raiz del repo: se sube hasta el directorio que tiene .git, para que el
# script funcione recien clonado y no dependa de donde este el arbol.
def _repo_root():
    d = os.path.dirname(os.path.abspath(__file__))
    while d != "/" and not os.path.isdir(os.path.join(d, ".git")):
        d = os.path.dirname(d)
    return d

R = _repo_root()
HERE = os.path.dirname(os.path.abspath(__file__))
ROOTS = ["omarchy", "omarchy-settings", "omarchy-keyring", "hyprland", "quickshell", "sddm", "mesa", "uwsm",
         "xdg-desktop-portal-hyprland", "ttf-jetbrains-mono-nerd-basic", "noto-fonts", "noto-fonts-emoji",
         "ttf-nerd-fonts-symbols", "inter-font", "networkmanager", "pipewire", "wireplumber", "gnome-keyring"]
# No estan en el stage pero el escritorio los quiere o ayudan a diagnosticar la GPU (no se instalan aqui).
OPTIONAL = ["xdg-terminal-exec", "udiskie", "mesa-utils", "vulkan-freedreno", "vulkan-tools", "wtype", "pamixer",
            "power-profiles-daemon", "hyprsunset", "fcitx5", "wlr-randr", "wayland-utils"]
MIRRORS = {"core": "https://fl.us.mirror.archlinuxarm.org/aarch64/core", "extra": "https://fl.us.mirror.archlinuxarm.org/aarch64/extra",
           "alarm": "https://fl.us.mirror.archlinuxarm.org/aarch64/alarm", "omarchy": "https://pkgs.omarchy.org/edge/aarch64"}


@functools.lru_cache(maxsize=None)
def vercmp(a, b):
    return int(subprocess.run(["vercmp", a, b], capture_output=True, text=True, check=True).stdout.strip())


DEP_RE = re.compile(r"^([^<>=]+?)(?:(<=|>=|=|<|>)(.+))?$")


def parse_dep(s):
    m = DEP_RE.match(s.strip())
    return m.group(1), m.group(2), m.group(3)


def cmp_ok(have, op, want):
    c = vercmp(have, want)
    return {"=": c == 0, ">=": c >= 0, "<=": c <= 0, ">": c > 0, "<": c < 0}[op]


class Pkg:
    def __init__(self, name, ver, depends, provides, conflicts, replaces, size, src, arch="", files=None):
        self.name, self.ver, self.depends, self.provides = name, ver, depends, provides
        self.conflicts, self.replaces, self.size, self.src, self.arch = conflicts, replaces, size, src, arch
        self.files = files or []

    def satisfies(self, dep):
        n, op, v = parse_dep(dep)
        if self.name == n:
            return op is None or cmp_ok(self.ver, op, v)
        for p in self.provides:
            pn, pop, pv = parse_dep(p)
            if pn == n:
                if op is None:
                    return True
                if pop == "=" and cmp_ok(pv, op, v):
                    return True
        return False


def read_pkginfo(path):
    txt = subprocess.run(["bsdtar", "-xOf", path, ".PKGINFO"], capture_output=True, text=True).stdout
    info = collections.defaultdict(list)
    for line in txt.splitlines():
        if line.startswith("#") or " = " not in line:
            continue
        k, v = line.split(" = ", 1)
        info[k].append(v)
    files = subprocess.run(["bsdtar", "-tf", path], capture_output=True, text=True).stdout.splitlines()
    files = [f for f in files if not f.startswith(".")]
    p = Pkg(info["pkgname"][0], info["pkgver"][0], info["depend"], info["provides"], info["conflict"], info["replaces"],
            int(info["size"][0]) if info["size"] else 0, os.path.basename(path), info["arch"][0] if info["arch"] else "", files)
    return p


def load_stage(stage):
    paths = sorted(os.path.join(stage, f) for f in os.listdir(stage) if ".pkg.tar." in f and not f.endswith(".sig"))
    with cf.ThreadPoolExecutor(12) as ex:
        pk = list(ex.map(read_pkginfo, paths))
    out = {}
    for p in pk:
        if p.name in out:
            sys.exit(f"stage: nombre duplicado {p.name}")
        out[p.name] = p
    return out


def debugfs(img, cmd):
    return subprocess.run(["debugfs", "-R", cmd, img], capture_output=True, text=True).stdout


def load_local(img):
    """DB local de pacman de la imagen, leida con debugfs (solo lectura)."""
    names = [l.strip() for l in debugfs(img, "ls -p /var/lib/pacman/local").splitlines()]
    dirs = []
    for l in names:
        f = l.split("/")
        if len(f) > 5 and f[5] not in (".", "..", "ALPM_DB_VERSION") and f[5]:
            dirs.append(f[5])
    out = {}
    for d in sorted(set(dirs)):
        desc = debugfs(img, f"cat /var/lib/pacman/local/{d}/desc")
        sec, cur = {}, None
        for line in desc.splitlines():
            if line.startswith("%") and line.endswith("%"):
                cur = line.strip("%")
                sec[cur] = []
            elif line and cur:
                sec[cur].append(line)
        if "NAME" not in sec:
            continue
        files, on = [], False
        for line in debugfs(img, f"cat /var/lib/pacman/local/{d}/files").splitlines():
            if line == "%FILES%":
                on = True
                continue
            if line.startswith("%"):
                on = False
                continue
            if on and line:
                files.append(line)
        out[sec["NAME"][0]] = Pkg(sec["NAME"][0], sec["VERSION"][0], sec.get("DEPENDS", []), sec.get("PROVIDES", []),
                                  sec.get("CONFLICTS", []), sec.get("REPLACES", []), int(sec.get("SIZE", ["0"])[0]), d,
                                  (sec.get("ARCH") or [""])[0], files)
    return out


def load_sync(stage):
    repo = {}
    for r in ("omarchy", "alarm", "core", "extra"):
        path = os.path.join(stage, "db-sync", "sync", r + ".db")
        if not os.path.exists(path):
            continue
        t = tarfile.open(path)
        for m in t.getmembers():
            if not m.name.endswith("/desc"):
                continue
            sec, cur = {}, None
            for line in t.extractfile(m).read().decode(errors="replace").splitlines():
                if line.startswith("%") and line.endswith("%"):
                    cur = line.strip("%")
                    sec[cur] = []
                elif line and cur:
                    sec[cur].append(line)
            if "NAME" not in sec:
                continue
            p = Pkg(sec["NAME"][0], sec["VERSION"][0], sec.get("DEPENDS", []), sec.get("PROVIDES", []), sec.get("CONFLICTS", []),
                    sec.get("REPLACES", []), int(sec.get("ISIZE", ["0"])[0]), r, (sec.get("ARCH") or [""])[0])
            p.filename = sec.get("FILENAME", [""])[0]
            p.csize = int(sec.get("CSIZE", ["0"])[0])
            p.sha256 = (sec.get("SHA256SUM") or [""])[0]
            if p.name not in repo or r == "omarchy":
                repo[p.name] = p
    return repo


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", default=f"{R}/build/stage-escritorio")
    ap.add_argument("--image", default=f"{R}/build/rootfs/rootfs-uke-l76-8g.img")
    ap.add_argument("--out", default=os.path.join(HERE, "..", "manifest"))
    ap.add_argument("--batch-mib", type=int, default=250, help="tamano instalado objetivo por tanda (se corta en frontera de lote)")
    ap.add_argument("--no-extras", action="store_true", help="solo tier1 (cierre estricto)")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    problems = []
    log = []

    def say(s=""):
        print(s)
        log.append(s)

    STAGE = load_stage(a.stage)
    INST = load_local(a.image)
    say(f"stage: {len(STAGE)} paquetes | instalados en la DB de la imagen: {len(INST)}")
    bad_arch = [n for n, p in STAGE.items() if p.arch not in ("aarch64", "any")]
    if bad_arch:
        problems.append(f"arquitectura no aarch64/any: {bad_arch}")

    def providers(pool, dep):
        n = parse_dep(dep)[0]
        c = [p for p in pool.values() if p.satisfies(dep)]
        c.sort(key=lambda p: (p.name != n, p.name))
        return c

    # ---- 1. tier1: cierre estricto
    selected, missing = {}, []
    queue = [(None, r) for r in ROOTS]
    while queue:
        who, dep = queue.pop()
        if any(s.satisfies(dep) for s in selected.values()):
            continue
        if providers(INST, dep):
            continue
        sp = providers(STAGE, dep)
        if not sp:
            missing.append((who, dep))
            continue
        pk = sp[0]
        selected[pk.name] = pk
        queue += [(pk.name, d) for d in pk.depends]

    def final_state(sel):
        st = dict(INST)
        st.update(sel)
        return st

    def broken(state):
        pool = list(state.values())
        return [(p.name, d) for p in pool for d in p.depends if not any(q.satisfies(d) for q in pool)]

    # punto fijo: lo instalado que depende (versionado) de algo que sube debe subir tambien
    for _ in range(50):
        ch = False
        for who, d in broken(final_state(selected)):
            sp = providers(STAGE, d)
            if sp and sp[0].name not in selected:
                selected[sp[0].name] = sp[0]
                ch = True
        if not ch:
            break
    tier1 = set(selected)
    extras = [] if a.no_extras else sorted(n for n in STAGE if n not in tier1 and n not in INST)
    sel_names = sorted(tier1 | set(extras))
    sel = {n: STAGE[n] for n in sel_names}
    tier3 = sorted(n for n in STAGE if n not in sel and n in INST)
    tier3_diff = [n for n in tier3 if vercmp(STAGE[n].ver, INST[n].ver) != 0]

    st = final_state(sel)
    bk = broken(st)
    conf = []
    for p in st.values():
        for c in p.conflicts:
            for q in st.values():
                if q is not p and q.name != p.name and q.satisfies(c):
                    conf.append((p.name, c, q.name))
    if missing:
        problems.append(f"dependencias sin proveedor: {sorted(set(missing), key=str)}")
    if bk:
        problems.append(f"dependencias rotas en el estado final: {bk}")
    if conf:
        problems.append(f"conflictos declarados: {conf}")
    upg = [(n, INST[n].ver, sel[n].ver) for n in sel if n in INST and vercmp(sel[n].ver, INST[n].ver) != 0]
    downg = [u for u in upg if vercmp(u[2], u[1]) < 0]
    if downg:
        problems.append(f"DOWNGRADES: {downg}")
    say(f"tier1 (cierre estricto): {len(tier1)} | tier2 (extras de Omarchy): {len(extras)} | total a instalar: {len(sel)}")
    say(f"tier3 (subidas de la base, EXCLUIDAS): {len(tier3_diff)}  | mismas versiones: {len(tier3) - len(tier3_diff)}")
    say(f"actualizan algo instalado: {upg}")
    say(f"integridad: sin proveedor={len(missing)} rotas={len(bk)} conflictos={len(conf)} downgrades={len(downg)}")

    # ---- 2. orden topologico = lotes del stage
    lote_of, lote_file = {}, {}
    for i in range(100):
        pth = f"{a.stage}/lotes/lote-{i:02d}.txt"
        if not os.path.exists(pth):
            break
        for line in open(pth):
            if line.startswith("#") or not line.strip():
                continue
            f, size, name, ver = line.split()
            lote_of[name] = i
            lote_file[name] = f
    viol = [(n, d, q) for n in sel for d in sel[n].depends for q in sel
            if q != n and sel[q].satisfies(d) and lote_of[q] > lote_of[n]]
    if viol:
        problems.append(f"violaciones de orden de lotes: {viol[:5]}")
    say(f"orden: violaciones de lotes = {len(viol)}")

    # ---- 3. conflictos de ficheros: contra instalados y contra el disco de la imagen
    owner = {}
    for p in INST.values():
        for f in p.files:
            owner[f.rstrip("/")] = p.name
    mine = collections.defaultdict(list)
    for n in sel:
        for f in sel[n].files:
            if not f.endswith("/"):
                mine[f].append(n)
    dups = {f: v for f, v in mine.items() if len(v) > 1}
    clash = [(f, v[0], owner[f]) for f, v in mine.items() if f in owner and owner[f] != v[0] and owner[f] not in sel]
    if dups:
        problems.append(f"ficheros en >1 paquete seleccionado: {list(dups.items())[:5]}")
    if clash:
        problems.append(f"ficheros que pertenecen a paquetes instalados que no se reemplazan: {clash[:5]}")
    cand = [f for f in mine if f not in owner]
    with tempfile.NamedTemporaryFile("w", suffix=".cmds", delete=False) as fh:
        for f in cand:
            fh.write("stat /" + f + "\n")
        cmds = fh.name
    out = subprocess.run(["debugfs", "-f", cmds, a.image], capture_output=True, text=True).stdout.splitlines()
    os.unlink(cmds)
    present, cur = [], None
    for line in out:
        if line.startswith("debugfs: stat "):
            cur = line[len("debugfs: stat "):]
        elif line.startswith("Inode:") and cur:
            present.append(cur[1:])
            cur = None
    by_pkg = collections.Counter(mine[f][0] for f in present)
    total_files = {n: sum(1 for f in sel[n].files if not f.endswith("/")) for n in sel}
    say(f"ficheros ya en el disco SIN dueno en la DB: {len(present)} en {len(by_pkg)} paquetes (volcado bsdtar del rootfs v8) -> --overwrite en sus tandas")
    with open(os.path.join(a.out, "overlay-sin-dueno.tsv"), "w") as fh:
        fh.write("# paquete\tficheros_ya_en_disco\tficheros_del_paquete\tver_stage\n")
        for n, c in sorted(by_pkg.items(), key=lambda kv: -kv[1]):
            fh.write(f"{n}\t{c}\t{total_files[n]}\t{sel[n].ver}\n")
    overlay = set(by_pkg)

    # ---- 4. tandas: lotes consecutivos hasta ~batch-mib instalados
    per = collections.OrderedDict()
    for n in sel:
        per.setdefault(lote_of[n], []).append(n)
    sha = {}
    for line in open(os.path.join(a.stage, "manifest.sha256")):
        h, f = line.split(None, 1)
        sha[f.strip()] = h
    batches, cur, cur_i = [], [], 0
    for i in sorted(per):
        cur.append(i)
        cur_i += sum(sel[n].size for n in per[i])
        # omarchy (ultimo lote) y omarchy-settings quedan al final de su tanda: orden natural
        if cur_i >= a.batch_mib * 1048576:
            batches.append(cur)
            cur, cur_i = [], 0
    if cur:
        batches.append(cur)
    sha_bad = []
    rows = []
    for b, lotes in enumerate(batches, 1):
        for i in lotes:
            for n in sorted(per[i], key=lambda x: x):
                f = sel[n].src
                if f not in sha:
                    sha_bad.append(f"{f}: sin entrada en manifest.sha256")
                    continue
                path = os.path.join(a.stage, f)
                csize = os.path.getsize(path)
                rows.append((b, i, f, n, sel[n].ver, csize, sel[n].size, 1 if n in overlay else 0, sha[f]))
    if sha_bad:
        problems.append(f"sha256: {sha_bad[:5]}")
    with open(os.path.join(a.out, "instalar.tsv"), "w") as fh:
        fh.write("# tanda\tlote\tfichero\tpaquete\tpkgver\tbytes_comprimido\tbytes_instalado\toverlay_sin_dueno\tsha256\n")
        for r in rows:
            fh.write("\t".join(str(x) for x in r) + "\n")
    say("tandas:")
    for b, lotes in enumerate(batches, 1):
        rr = [r for r in rows if r[0] == b]
        say(f"  T{b}: lotes {lotes[0]:02d}-{lotes[-1]:02d} | {len(rr):3d} pkgs | {sum(r[5] for r in rr)/1048576:6.1f} MiB comprimido | "
            f"{sum(r[6] for r in rr)/1048576:7.1f} MiB instalado | overlay={sum(r[7] for r in rr)}")
    tot_i = sum(r[6] for r in rows)
    already = sum(sel[n].size for n in overlay if by_pkg[n] == total_files[n])
    say(f"TOTAL: {len(rows)} pkgs | {sum(r[5] for r in rows)/1048576:.0f} MiB comprimido | {tot_i/1048576:.0f} MiB instalado "
        f"(de ellos ~{already/1048576:.0f} MiB ya estan en disco sin registrar => netos ~{(tot_i-already)/1048576:.0f} MiB)")

    # ---- 5. lo que se excluye
    with open(os.path.join(a.out, "no-incluidos.tsv"), "w") as fh:
        fh.write("# paquete\tversion_stage\tversion_instalada_DB\tmotivo\n")
        for n in tier3:
            same = vercmp(STAGE[n].ver, INST[n].ver) == 0
            fh.write(f"{n}\t{STAGE[n].ver}\t{INST[n].ver}\t{'misma version: --needed lo saltaria' if same else 'subida de base no necesaria (la base ya satisface las deps)'}\n")
        for n in sorted(STAGE):
            if n not in sel and n not in INST:
                fh.write(f"{n}\t{STAGE[n].ver}\t-\tnuevo pero fuera de seleccion (--no-extras)\n")

    # ---- 6. opcionales fuera del stage
    REPO = load_sync(a.stage)
    final_names = dict(st)

    def have(dep):
        return any(q.satisfies(dep) for q in final_names.values())

    with open(os.path.join(a.out, "opcionales.tsv"), "w") as fh:
        fh.write("# paquete\tversion\trepo\tfichero\tbytes\tsha256\turl\tdeps_sin_cubrir\n")
        for n in OPTIONAL:
            p = REPO.get(n)
            if not p:
                fh.write(f"{n}\t-\t-\t-\t-\t-\t-\t(no esta en la DB de sync del stage)\n")
                continue
            unc = [d for d in p.depends if not have(d)]
            fh.write(f"{n}\t{p.ver}\t{p.src}\t{p.filename}\t{p.csize}\t{p.sha256}\t{MIRRORS[p.src]}/{p.filename}\t{' '.join(unc) or '-'}\n")

    # ---- 7. listas planas
    with open(os.path.join(a.out, "nombres.txt"), "w") as fh:
        fh.write("\n".join(r[3] for r in rows) + "\n")
    with open(os.path.join(a.out, "resumen.txt"), "w") as fh:
        fh.write("\n".join(log) + "\n")
        fh.write("\nPROBLEMAS:\n" + ("\n".join(problems) if problems else "ninguno") + "\n")
    if problems:
        print("\nPROBLEMAS:")
        for p in problems:
            print("  -", p)
        sys.exit(2)
    print("\nOK: cierre completo, 0 problemas")


if __name__ == "__main__":
    main()
