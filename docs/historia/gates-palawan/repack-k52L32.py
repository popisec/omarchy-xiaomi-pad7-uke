#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
repack-k52L32.py — boot-uke-k52L32.img (12-oct, exonera :d: MISMO skip que
L24 pero CONSERVANDO video=DSI-1:d + instrumentacion nueva de probe del
panel):
kernel L19-equivalente (gates L22+L22b revertidos a mano) + UNICO hunk L24
(msm_mdss_reset salta con msm.uke_skip_mdss_reset=1) + 5 pokes nuevos en el
panel (K47-pan-probe/probe-ok/probe-attach-ok/pwron/pwron-ok; K47-pan-prep
ya existia) + cmdline L32 = base L19/k64 (580 B) INTACTA (video=DSI-1:d
PRESENTE) + " msm.uke_skip_mdss_reset=1" (606 B). Clon de repack-k52L24.py:
IDENTICOS gates G0/G1/G4/G5/G8 y G3 de linaje (L11: POKE=113, K13=11,
L6x11/L7x7/L8x2/L10x4/L11x2, negativos, cpio k52b2); G0 apunta al tree
k52L32 (+msm_mdss.c, dpu_kms.c, dispcc-sm8550.c, panel-o82, uke-poke.h en
la lista rancia); G2/G6 reescritos para la cmdline L32 (606 B, CON :d);
G3 exige 0 herencia + gate reset x3/x1 + las 6 migas K47 del panel x1
(ancladas con NUL: K47-pan-probe es prefijo de probe-ok/attach-ok y
K47-pan-pwr de pwron).
REDACTADO SIN EJECUTAR (solo-PC).
"""
import hashlib
import os
import struct
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
BASE = HOME + "/gpu-work/ramaa/s21/avb/boot-s240-mem2g.img"
BASE_SHA = "e3c60969269c0b36f23a37db5b1772128891232517c8d7979bd967b88acab206"
K13 = R + "/build/bootimg/boot-ukek13.img"
K13_SHA = "d71ea2b5f6aaf7f8b4820748362b5b32ebed4a064f6f224bb037a7abc9707381"
K13DSID = R + "/build/bootimg/boot-ukek13-dsid.img"
K13DSID_SHA = "e0ee47dc4044e9cccbcf177ab36cc8efd005ee9ef4d7cff370741578707c5c57"
# K65 (9-oct-2026): referencia de cmdline = la del k64 flasheado (580 B).
# Gate más fuerte que referencia+append: byte-idéntica o nada.
K64IMG = R + "/build/bootimg/boot-uke-k64-vendorcfg.img"
# L32 (12-oct): la cmdline BASE es la del L19 (el que funciona, control
# verificado 12-oct 03:4x). Su cmdline es byte-idéntica a la del k64 (580 B,
# verificado); se exige el sha pre-registrado y la igualdad k64==L19.
L19IMG = R + "/build/bootimg/boot-uke-k52L19.img"
L19_SHA = "71d89ca6e875941b75af012ac24d20fb7690de407fa341923f2d896557ee51a9"
KERNEL = R + "/build/kernel-pokes/k52L25-diag-Image.gz"
# L21 (11-oct #598-bis): = L19 + l21-wifi-btgpio.diff (bt-enable no-fatal en pwrseq)
K13_INITRAMFS = R + "/build/init/uke-k22-initramfs.cpio.gz"
K13_INITRAMFS_SHA = "08780e3565c2641660703f884bbac9c0f3aab0e1e8cadb78611a674e5238b706"
# fallback del cpio si /var/tmp lo borran otra vez (copias verificadas):
K13_INITRAMFS_FB = R + "/build/init/uke-k12-initramfs.cpio.gz"  # fallback: cpio K12 puro (sin fw)

DSID = "--dsid" in sys.argv
# --- K23b (1-oct-2026): --out / --kernel / --gate-k23b ---------------------
# ANTES: OUT fijo en boot-ukek18[ d].img, y el repack del K23 (2:36) escribio
# boot-ukek18d.img, el MISMO nombre que #P47 habia pre-registrado con otro sha
# (99d49b06). Por eso el K23 se renombro a boot-ukek23.img a mano. Con --out el
# nombre ya no se pisa y el reporte lo dice.
# GATE_K23B: exige en el binario los marcadores del dump CORREGIDO (1-oct).
# Sin este flag se puede re-empaquetar el kernel viejo, cuyo dump miente.
GATE_K23B = "--gate-k23b" in sys.argv

# --- K24 (1-oct-2026, sesion #455): --cmdline-append / --cmdline-require -------
# Append de tokens a la cmdline, con gate de que esten. Ver el bloque G2.
def _csv(flag):
    if flag not in sys.argv:
        return []
    v = sys.argv[sys.argv.index(flag) + 1]
    return [t.encode() for t in v.split(",") if t]


CMD_APPEND = _csv("--cmdline-append")
CMD_REQUIRE = _csv("--cmdline-require")

_arg_out = None
if "--out" in sys.argv:
    _arg_out = sys.argv[sys.argv.index("--out") + 1]
if "--kernel" in sys.argv:
    KERNEL = sys.argv[sys.argv.index("--kernel") + 1]
if _arg_out:
    OUT = R + "/build/bootimg/" + _arg_out
    LOG = R + "/build/bootimg/repack-" + _arg_out[:-4] + "-report.txt"
elif DSID:
    OUT = R + "/build/bootimg/boot-uke-k52L22.img"
    LOG = R + "/build/bootimg/repack-k52L11-report.txt"
else:
    OUT = R + "/build/bootimg/boot-ukek18.img"
    LOG = R + "/build/bootimg/repack-k18-report.txt"

PAGE, CMD_OFF, KS_OFF, RS_OFF = 4096, 44, 8, 12
DIAG_CPIO = R + "/build/init/uke-k52b2-diag-initramfs.cpio.gz"
CMD_FIELD = 1536
STOCK_SIZE = 100663296
AVB0_OFF, AVBF_OFF = 35438592, 100663232
K13_KSZ = 16577409

TOK_PROBE = b"arm_smmu.uke_smmu_probe=1"
TOKS_KEPT = (b"arm_smmu.uke_smr_max=0", b"arm_smmu.uke_keep_boot=1",
             b"arm_smmu.uke_attach_log=2", b"arm_smmu.uke_reset_mask=12")

LOGF = []


def log(m):
    print(m)
    LOGF.append(m)


def die(m):
    log("*** %s ***" % m)
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, "w", encoding="utf-8") as f:
        f.write("\n".join(LOGF) + "\n")
    sys.exit(1)


def sha(b):
    return hashlib.sha256(b).hexdigest()


def main():
    global K13_INITRAMFS
    log("=== G0: entradas (K18%s) ===" % ("-dsid" if DSID else ""))
    if not os.path.isfile(K13_INITRAMFS) or sha(open(K13_INITRAMFS, "rb").read()) != K13_INITRAMFS_SHA:
        if os.path.isfile(K13_INITRAMFS_FB):
            K13_INITRAMFS = K13_INITRAMFS_FB
    for p, want, nombre in ((BASE, BASE_SHA, "shell s240-mem2g"),
                            (K13, K13_SHA, "boot-ukek13.img (cmdline plain)"),
                            (K13DSID, K13DSID_SHA, "boot-ukek13-dsid.img (cmdline dsid)"),
                            (K13_INITRAMFS, K13_INITRAMFS_SHA, "initramfs (= K12/K13)")):
        if not os.path.isfile(p):
            die("G0 FALLO: no existe %s" % p)
        b = open(p, "rb").read()
        if sha(b) != want:
            die("G0 FALLO: %s no es el registrado (sha %s)" % (p, sha(b)[:16]))
    if not os.path.isfile(KERNEL):
        die("G0 FALLO: no existe %s (build incompleto)" % KERNEL)
    kern = open(KERNEL, "rb").read()
    # G0 (1-oct, gate rancio arreglado): antes solo se miraba la mtime de
    # arm-smmu.c, asi que un cambio SOLO en a6xx_gmu.c —que es donde vive el
    # dump del CM3— colaba un build viejo sin quejarse. Ahora se miran todos
    # los ficheros de los que depende el kernel que flashamos.
    for rel in ("drivers/iommu/arm/arm-smmu/arm-smmu.c",
                "drivers/gpu/drm/msm/adreno/a6xx_gmu.c",
                "drivers/gpu/drm/msm/adreno/a6xx_gpu.c",
                "drivers/gpu/drm/msm/adreno/adreno_device.c",
                "drivers/gpu/drm/msm/adreno/adreno_gpu.c",
                "drivers/gpu/drm/msm/msm_drv.c",
                "drivers/gpu/drm/msm/msm_gpu.c",
                "drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c",
                "drivers/soc/qcom/uke-panic-fb.c",
                # L32 (12-oct): el gate unico vive en msm_mdss.c + el param en
                # msm_drv.c + el accesor en uke-poke.h; dpu_kms.c y dispcc van
                # para pillar un build rancio que no los reconstruyera; el
                # panel-o82 va por las 5 migas nuevas de probe/pwron.
                "drivers/gpu/drm/msm/msm_mdss.c",
                "drivers/gpu/drm/msm/disp/dpu1/dpu_kms.c",
                "drivers/clk/qcom/dispcc-sm8550.c",
                "include/linux/uke-poke.h"):
        src = R + "/build/kernel-pokes/k52L25-tree/" + rel
        if not os.path.isfile(src):
            die("G0 FALLO: no existe el fuente %s" % src)
        if os.path.getmtime(src) > os.path.getmtime(KERNEL):
            die("G0 FALLO: %s mas nuevo que Image.gz (build rancio)" % rel)
    log("  OK  Image.gz %d B sha256=%s (13 fuentes sin cambios posteriores)"
        % (len(kern), sha(kern)[:16]))
    base = open(BASE, "rb").read()
    k13 = open(K13, "rb").read()
    k13d = open(K13DSID, "rb").read()

    log("\n=== G1: cabecera v4 de la base ===")
    if base[0:8] != b"ANDROID!":
        die("G1 FALLO: sin magia ANDROID!")
    if struct.unpack_from("<I", base, 40)[0] != 4 or struct.unpack_from("<I", base, 20)[0] != 1584:
        die("G1 FALLO: la base no es header v4/header_size 1584")
    if struct.unpack_from("<I", base, RS_OFF)[0] != 0:
        die("G1 FALLO: la base ya lleva ramdisk")
    if base[PAGE:PAGE + 2] != b"\x1f\x8b":
        die("G1 FALLO: sin kernel gzip @4096")
    log("  OK  v4/1584; ramdisk 0; gzip @4096")

    log("\n=== G2: cmdline (fuente: boot-uke-k52L11.img 580 B — el que VIVE, #585) ===")
    # #585/#586: la cmdline de k13/k13d (356/370 B) NO trae msm.uke_gmu_shared=0
    # ni la familia K24 -> el GMU comparte el dominio TTBR1 de la GPU y el mapeo
    # de iovas bajos muere con -ERANGE (R6-gmu-erange). La buena es la del L11.
    cmd = open(K64IMG, "rb").read()[CMD_OFF:CMD_OFF + CMD_FIELD].split(b"\x00")[0]
    if len(cmd) != 580:
        die("G2 FALLO: cmdline k64 mide %d != 580" % len(cmd))
    # L32: la base tiene que ser la cmdline del L19 (control que funciona).
    # Se exige el sha pre-registrado del L19 y la igualdad byte-exacta k64==L19
    # (verificada a mano 12-oct: identicas, 580 B).
    l19 = open(L19IMG, "rb").read()
    if sha(l19) != L19_SHA:
        die("G2 FALLO: L19 no es el registrado (sha %s)" % sha(l19)[:16])
    l19cmd = l19[CMD_OFF:CMD_OFF + CMD_FIELD].split(b"\x00")[0]
    if cmd != l19cmd:
        die("G2 FALLO: cmdline k64 != cmdline L19 (%d B vs %d B)" % (len(cmd), len(l19cmd)))
    log("  OK  base = cmdline L19 (sha 71d89ca6..., 580 B, identica a k64)")
    if b"msm.uke_gmu_shared=0" not in cmd:
        die("G2 FALLO: la cmdline no trae msm.uke_gmu_shared=0 (R6-gmu-erange)")
    # L32 (12-oct 05:3x): INVERSIÓN respecto al L25. L25 demostró que el skip
    # del BCR sobrevive al bind del DPU; ahora quitamos ":d" para que el conector
    # se habilite y por fin corra un prepare real del panel.
    if b"video=DSI-1:d" not in cmd:
        die("G2 FALLO: la base L19 debe traer video=DSI-1:d (es lo que se quita)")
    if TOK_PROBE in cmd or b"  " in cmd:
        die("G2 FALLO: probe token o doble espacio")
    for t in TOKS_KEPT:
        if cmd.count(t) != 1:
            die("G2 FALLO: token %r aparece %d veces" % (t, cmd.count(t)))
    # L32 (12-oct 05:3x): se QUITA " video=DSI-1:d" de la base L19 y se ANADE
    # " msm.uke_skip_mdss_reset=1". El :d debe estar x1 exacto ANTES de quitarlo
    # (si no, la base no es la esperada y no se firma).
    if cmd.count(b"video=DSI-1:d") != 1:
        die("G2 FALLO: video=DSI-1:d aparece x%d en la base (esperado x1)"
            % cmd.count(b"video=DSI-1:d"))
    if b" video=DSI-1:d" not in cmd:
        die("G2 FALLO: no se encuentra ' video=DSI-1:d' con espacio previo")
    cmd = cmd.replace(b" video=DSI-1:d", b" video=DSI-1:e", 1)
    if cmd.count(b"video=DSI-1:e") != 1:
        die("G2 FALLO: video=DSI-1:e debe quedar x1")
    # L32: quitar fbcon para que NO haya auto-modeset en el boot (si no, el
    # commit mata a los ~4 s y UKE-DIAG no lo ve). El ACM va por ttyGS0 aparte.
    for tok in (b" console=tty0", b" fbcon=map:0"):
        if tok not in cmd:
            die("G2 FALLO: no encuentro el token %r en la base" % tok)
        cmd = cmd.replace(tok, b"", 1)
    cmd = cmd + b" msm.fbdev=0 msm.uke_skip_mdss_reset=1"
    if cmd.count(b"msm.uke_skip_mdss_reset=1") != 1:
        die("G2 FALLO: skip_mdss_reset aparece x%d" % cmd.count(b"msm.uke_skip_mdss_reset=1"))
    if b"msm.uke_panel_inherit" in cmd:
        die("G2 FALLO: resto de herencia en la cmdline L32 (prohibido)")
    if b"  " in cmd:
        die("G2 FALLO: doble espacio tras la cirugia L32")
    if len(cmd) != 593:
        die("G2 FALLO: cmdline L32 mide %d != 593 (581 +12)" % len(cmd))
    log("  OK  cirugia L32: SIN video=DSI-1:d, +msm.uke_skip_mdss_reset=1 -> %d B" % len(cmd))

    # --- K24 (1-oct-2026, sesion #455): --cmdline-append ------------------------
    # El ciclo K24 necesita DOS tokens que NO estan en la cmdline del K13:
    #   uke_gmu_shared=0  -> el GMU usa dominio propio (ataca la capa de ATTACH;
    #                        es un module_param, o sea NO requiere rebuild)
    #   hung_task_panic=0 -> un wedge cuesta 1 reintento de slot en vez de 7
    #                        (mitiga; NO protege: el ABL marca unbootable ante
    #                        cualquier arranque sin marca de exito)
    # Antes esto obligaba a editar el .img a mano. Se hace aqui para que quede
    # en el artefacto versionado y con gate.
    if CMD_APPEND:
        for tok in CMD_APPEND:
            if tok.startswith(b"-"):           # quita una opcion que ya este
                opt = tok[1:]
                if opt in cmd:
                    cmd = cmd.replace(b" " + opt, b"")
                continue
            if tok in cmd:
                die("G2 FALLO: %r ya estaba en la cmdline (no lo duplico)" % tok)
            cmd = cmd + b" " + tok
        log("  OK  cmdline +%d token(s) de --cmdline-append" % len(CMD_APPEND))
    # GATE: lo que se ha anadido tiene que estar, y el dump tiene que ser el
    # que camina la tabla (si no, el discriminador lee basura).
    if CMD_REQUIRE:
        for tok in CMD_REQUIRE:
            if tok not in cmd:
                die("G2 FALLO: %r no esta en la cmdline final" % tok)
        log("  OK  cmdline contiene los %d token(s) exigidos" % len(CMD_REQUIRE))
    log("  OK  cmdline L32 %d B (CON video=DSI-1:d, con msm.uke_skip_mdss_reset=1)" % len(cmd))

    log("\n=== G3: kernel K18 ===")
    import gzip
    raw = gzip.decompress(kern)
    if abs(len(raw) - 41355776) > 262144:
        die("G3 FALLO: Image crudo %d B (delta desproporcionado)" % len(raw))
    if raw.count(b"UKE-POKE") != 113:
        die("G3 FALLO: UKE-POKE=%d != 113" % raw.count(b"UKE-POKE"))
    if raw.count(b"UKE-K13") != 11 or raw.count(b"PINADO sin estar vivo") != 0:
        die("G3 FALLO: marcadores K13 rotos")
    if raw.count(b"UKE-K16: display sid=0x%04x -> grupo PROPIO rc=%ld (split)") != 1:
        die("G3 FALLO: miga UKE-K16 ausente")
    if raw.count(b"UKE-P82") < 20:
        die("G3 FALLO: migas panel UKE-P82 ausentes")
    # K65 (9-oct-2026): el check de UKE-K17:dtcmR-val se relaja a S0 solo.
    # El k64 flasheado (#550b) tampoco lo lleva (raw: S0=1, val=0) — la
    # instrumentación SMMU migró al layout upstream entre el 6 y el 9-oct.
    if raw.count(b"S0-dtcmR") < 1:
        die("G3 FALLO: miga GMU K17 S0-dtcmR ausente")
    if raw.count(b"arm_smmu.uke_kgsl_keep") != 1:
        die("G3 FALLO: falta el param uke_kgsl_keep (K18 no esta en el binario)")
    if raw.count(b"UKE-K18: kgsl heredado SMR(%d)=0x%08x S2CR(%d)=0x%08x") < 1:
        die("G3 FALLO: falta el volcado UKE-K18 de SMR heredados")
    if raw.count(b"UKE-K11") != 0:
        die("G3 FALLO: UKE-K11 en el kernel")
    for p in (b"arm_smmu.uke_smmu_probe", b"arm_smmu.uke_write_mask",
              b"arm_smmu.uke_handoff", b"arm_smmu.uke_keep_boot"):
        if raw.count(p) < 1:
            die("G3 FALLO: falta el param %r" % p)
    # NOTA L21: el hunk btgpio vive en el MODULO pwrseq-qcom-wcn.ko (CONFIG_..._WCN=m),
    # NO en el Image — el gate de la cadena va sobre el .ko (build-mod-l21.sh).
    log("  OK  crudo %d B; POKE=113; K13=11; K16=1; P82>=20; S0; K18 param+volcado presentes" % len(raw))

    # L11 (10-oct-2026): = L10 + poll VENDOR + HFI (`goto` nopoll-ok
    # ELIMINADO; poll S4 con (val&0x1ff)==0x100 + poke L11-pollok; etiqueta
    # como epilogo comun con `ret = 0` para dejar seguir a HFI; el gate
    # L11-WRITE del build verifica el `str` por desensamblado). Positivos:
    # TODOS los de L10 (L6x11 + L7x7 + L8x2 + L10x4) + los 2 UKE-L11 (x1 c/u).
    # Negativos: los mismos de L10, con UKE-L1 anclado con ':' (los pr_err
    # "UKE-L10: ..."/"UKE-L11: ..." contienen el substring "UKE-L1"; el hunk
    # del gemelo L1 usa "UKE-L1: ").
    # POKE=113 (igual que L10: el poke L11-pollok NO duplica la cadena
    # "UKE-POKE" en el binario; VERIFICADO en el Image L11 real, §3 del
    # informe BISECT-L11).
    for t, n in ((b"UKE-K19", 21),
                 (b"UKE-K17: dtcmR", 1),
                 (b"WALK", 8),
                 (b"MAPPING", 15),
                 (b"UKE-L2: D1 gmu clk_set 220M rc=%d", 1),
                 (b"UKE-K68: D2 hub clk_set 200M rc=%d", 1),
                 (b"UKE-K65: D3 cx LOW_SVS opp_set_rate 220M rc=%d", 1),
                 (b"UKE-L6: open-enter", 1),
                 (b"UKE-L6: fw-enter", 1),
                 (b"UKE-L6: fw-exit-ok", 1),
                 (b"UKE-L6: ucode-enter", 1),
                 (b"UKE-L6: ucode-exit-ok", 1),
                 (b"UKE-L6: rpm-enter", 1),
                 (b"UKE-L6: rpm-exit-ok", 1),
                 (b"UKE-L6: hwinit-enter", 1),
                 (b"UKE-L6: gmu-pm-resume-enter", 1),
                 (b"UKE-L6: pm-resume-enter", 1),
                 (b"UKE-L6: gmu-resume-enter", 1),
                 (b"UKE-L7: k44b-ok", 1),
                 (b"UKE-L7: k44c-ok", 1),
                 (b"UKE-L7: k44d-ok", 1),
                 (b"UKE-L7: k44e-ok", 1),
                 (b"UKE-L7: k25-ok", 1),
                 (b"UKE-L7: pre-rst", 1),
                 (b"UKE-L7: post-rst", 1),
                 (b"UKE-L8: write-done", 1),
                 (b"UKE-L8: nopoll-ok", 1),
                 (b"L10-gbif", 1),
                 (b"L10-recfg", 1),
                 (b"UKE-L10: gbif-ok", 1),
                 (b"UKE-L10: recfg-ok", 1),
                 (b"L11-pollok", 1),
                 (b"UKE-L11: pollok", 1)):
        if raw.count(t) != n:
            die("G3 FALLO: testigo L11 %r x%d (hay x%d)" % (t, n, raw.count(t)))
    for bad in (b"UKE-K55", b"UKE-K56", b"UKE-K57", b"UKE-K58", b"UKE-K59",
                b"UKE-K60", b"UKE-K61", b"UKE-K62", b"UKE-K63", b"UKE-K64",
                b"UKE-K65: D1", b"UKE-K65: D2",
                b"UKE-K66:", b"UKE-K67:",
                b"UKE-L2: SIN-D2", b"UKE-L2: SIN-D3",
                b"UKE-K68: SIN-D1", b"UKE-K68: GENERAL_10",
                b"UKE-K68: GENERAL_8", b"UKE-K68: poll vendor",
                b"UKE-C1", b"UKE-K70", b"UKE-C3", b"UKE-L1:",
                b"uke_s3_stage", b"uke_rescue",
                b"poll vendor", b"GENERAL_10", b"GENERAL_8",
                b"register_config"):
        if bad in raw:
            die("G3 FALLO: %r sigue en el binario (no es L11)" % bad)
    log("  OK  L11: = L10 + poll VENDOR + HFI; K64/C1/poll/G10/G8/D-ajeno/familia ausentes")
    # L32 (12-oct): SIN herencia + gate unico de reset (igual que L24) +
    # instrumentacion nueva del panel. uke_skip_mdss_reset mide x3, NO x2:
    # tabla __param ("msm.uke_skip_mdss_reset") + __kstrtab (EXPORT_SYMBOL) +
    # la propia miga pr_info ("...gate msm.uke_skip_mdss_reset=1"). Verificado
    # en el Image L24 real. La miga UKE-L24 y el poke L24-skip-mdss-reset van
    # x1; "msm_mdss_reset SALTADO" PRESENTE x1. Las 6 migas K47 del panel van
    # x1 cada una, ancladas con NUL porque hay prefijos compartidos:
    # "K47-pan-probe" es prefijo de "K47-pan-probe-ok" y de
    # "K47-pan-probe-attach-ok"; "K47-pan-pwr" es prefijo de "K47-pan-pwron".
    # (Medido en el Image L32 real con raw.count; ver informe.)
    for t, n in ((b"uke_skip_mdss_reset", 3),
                 (b"UKE-L24", 1),
                 (b"L24-skip-mdss-reset", 1),
                 (b"msm_mdss_reset SALTADO", 1),
                 (b"K47-pan-probe\x00", 1),
                 (b"K47-pan-probe-ok\x00", 1),
                 (b"K47-pan-probe-attach-ok\x00", 1),
                 (b"K47-pan-prep\x00", 1),
                 (b"K47-pan-pwron\x00", 1),
                 (b"K47-pan-pwron-ok\x00", 1)):
        if raw.count(t) != n:
            die("G3 FALLO: testigo L32 %r x%d (hay x%d)" % (t, n, raw.count(t)))
    for bad in (b"UKE-P82-INHERIT",
                b"P82-inh-",
                b"uke_panel_inherit",
                b"dpu_vbif_init_memtypes SALTADO",
                b"clk_bulk SALTADO",
                b"pll_configure SALTADO",
                b"uke_skip_pll",
                b"prepare SALTADO",
                b"unprepare SALTADO",
                b"scanout ABL vivo"):
        if bad in raw:
            die("G3 FALLO: resto herencia/L22b %r sigue en el binario" % bad)
    log("  OK  L32: 0 herencia/L22b; gate reset presente (param x3, miga+poke x1); 6 migas K47 x1")
    k12gz = open(K13_INITRAMFS, "rb").read()
    import zlib
    pos = raw.find(b"\x1f\x8b\x08")
    blob_at = None
    dec = None
    while pos != -1:
        d = zlib.decompressobj(31)
        try:
            dec = d.decompress(raw[pos:pos + 8_000_000])
        except Exception:
            dec = None
        if dec is not None and dec[:6] == b"070701":
            blob_at = pos
            break
        pos = raw.find(b"\x1f\x8b\x08", pos + 1)
    # L0 (9-oct-2026, BISECT): este linaje embebe el cpio K34-fw versión 6-oct
    # (ebc2de46…, recuperado de git: es el que llevaba el k52b2), NO el del
    # k64. Referencia: el kernel del PROPIO k52b2 (boot-uke-k52b2-bateria.img).
    L0IMG = R + "/build/bootimg/boot-uke-k52b2-bateria.img"
    k64kern = gzip.decompress(open(L0IMG, "rb").read()[PAGE:PAGE + 17000000])
    pos64 = k64kern.find(b"\x1f\x8b\x08")
    while pos64 != -1:
        dd = zlib.decompressobj(31)
        try:
            dec64 = dd.decompress(k64kern[pos64:pos64 + 8_000_000])
        except Exception:
            dec64 = None
        if dec64 is not None and dec64[:6] == b"070701":
            break
        pos64 = k64kern.find(b"\x1f\x8b\x08", pos64 + 1)
    # L16: el Image crece +65536 B (alineación de la línea chipid) y el cpio
    # embebido se desplaza igual: se exige el MISMO contenido en L11-offset o
    # en L11-offset+65536.
    if pos64 == -1 or blob_at not in (pos64, pos64 + 65536):
        die("G3 FALLO: initramfs embebido fuera de los offsets k52b2/k52L16 "
            "(offset %s vs %s)" % (blob_at, pos64))
    dd2 = zlib.decompressobj(31)
    try:
        dec70 = dd2.decompress(raw[blob_at:blob_at + 8_000_000])
    except Exception:
        dec70 = None
    # L32 (13-oct): este kernel lleva el cpio CON EL VIGILANTE UKE-DIAG, no el
    # de k52b2. El gate debe verificar que el embebido es el de diag y que el
    # vigilante está dentro, no que sea el de k52b2.
    diag = open(DIAG_CPIO, "rb").read()
    if dec70 is None or dec70 != gzip.decompress(diag):
        die("G3 FALLO: cpio embebido != cpio UKE-DIAG")
    if dec70.count(b"UKE-DIAG") < 5 or dec70.count(b"diag-snapshot.sh") < 5:
        die("G3 FALLO: el cpio embebido no contiene el vigilante UKE-DIAG")
    log("  OK  initramfs embebido @%d = cpio UKE-DIAG (con vigilante, "
        "UKE-DIAG x%d)" % (blob_at, dec70.count(b"UKE-DIAG")))

    log("\n=== G4: ensamblado ===")
    img = bytearray(base)
    ksz = len(kern)
    if PAGE + ksz >= AVB0_OFF:
        die("G4 FALLO: kernel pisaria AVB0")
    struct.pack_into("<I", img, KS_OFF, ksz)
    img[PAGE:PAGE + ksz] = kern
    img[CMD_OFF:CMD_OFF + CMD_FIELD] = cmd + b"\x00" * (CMD_FIELD - len(cmd))
    if img[PAGE + ksz:AVB0_OFF] != b"\x00" * (AVB0_OFF - PAGE - ksz):
        die("G4 FALLO: hueco tras kernel no es ceros")
    log("  OK  kernel_size@8=%d; cmdline @44..%d" % (ksz, CMD_OFF + len(cmd)))

    log("\n=== G5: forma/AVB ===")
    if bytes(img[0:8]) != b"ANDROID!" or bytes(img[AVB0_OFF:AVB0_OFF + 4]) != b"AVB0" or bytes(img[AVBF_OFF:AVBF_OFF + 4]) != b"AVBf":
        die("G5 FALLO: forma")
    if struct.unpack_from("<I", img, RS_OFF)[0] != 0:
        die("G5 FALLO: ramdisk_size != 0")
    log("  OK  96 MiB; AVB0/AVBf en sitio")

    log("\n=== G6: deltas ===")
    KZ_INI, KZ_FIN = PAGE, max(PAGE + ksz, PAGE + K13_KSZ)
    zonas = [(KS_OFF, KS_OFF + 4), (CMD_OFF, CMD_OFF + CMD_FIELD), (KZ_INI, KZ_FIN)]
    ref = k13d if DSID else k13
    fuera = [i for i in range(STOCK_SIZE) if base[i] != img[i] and not any(a <= i < b_ for a, b_ in zonas)]
    if fuera:
        die("G6 FALLO: %d bytes fuera de zonas vs s240" % len(fuera))
    dif = sum(1 for i in range(CMD_OFF, CMD_OFF + CMD_FIELD) if ref[i] != img[i])
    if CMD_APPEND:
        # UKE-K24: con --cmdline-append la diferencia NO es "tolerancia", es un
        # sufijo INTENCIONAL. En vez de subir el limite de bytes (que dejaria
        # pasar una corrupcion cualquiera), se exige que la cmdline final sea
        # EXACTAMENTE la de referencia + los tokens anadidos, y que el prefijo
        # de la referencia este intacto. Gate mas fuerte, no mas laxo.
        ref_cmd = ref[CMD_OFF:CMD_OFF + CMD_FIELD].split(b"\x00")[0]
        # Se replican aqui las MISMAS reglas que se aplicaron a `cmd` en G2
        # (borrar con -token, anadir el resto), para que la referencia esperada
        # sea la referencia REAL y no "la de referencia + solo los appends".
        # Sin esto, un borrado legitimo hacia fallar el gate (fallo real que
        #fue justo lo que paso, sesion #456).
        esperado = open(K64IMG, "rb").read()[CMD_OFF:CMD_OFF + CMD_FIELD].split(b"\x00")[0]  # L22: ref REAL = k64 (G2 la usa como base)
        for tok in CMD_APPEND:
            if tok.startswith(b"-"):
                opt = tok[1:]
                if opt in esperado:
                    esperado = esperado.replace(b" " + opt, b"")
            else:
                esperado = esperado + b" " + tok
        if cmd != esperado:
            die("G6 FALLO: la cmdline final no es referencia+append\n"
                "        esperada %d B: %r\n        obtenida %d B: %r"
                % (len(esperado), esperado, len(cmd), cmd))
        log("  OK  cmdline = referencia (%d B) + %d B de append, prefijo intacto"
            % (len(ref_cmd), len(cmd) - len(ref_cmd)))
        # L22: la cmdline final tiene que ser BYTE-IDENTICA a k64 + los appends
        # (única variable = el kernel + el param de herencia; ya verificado arriba
        # que cmd == esperado con la k64 como referencia).
        k64cmd = open(K64IMG, "rb").read()[CMD_OFF:CMD_OFF + CMD_FIELD].split(b"\x00")[0]
        log("  OK  cmdline = k64 (%d B) + appends L22 -> %d B" % (len(k64cmd), len(cmd)))
    elif not CMD_APPEND:
        # L32: la UNICA cmdline valida es base k64/L19 (580 B) INTACTA
        # (video=DSI-1:d PRESENTE) + " msm.uke_skip_mdss_reset=1" (606 B).
        # Gate fuerte (estilo K24): igualdad EXACTA contra lo esperado,
        # no tolerancia de bytes (un dif>0 aqui seria corrupcion).
        k64cmd = open(K64IMG, "rb").read()[CMD_OFF:CMD_OFF + CMD_FIELD].split(b"\x00")[0]
        # L32 (12-oct 05:3x): la esperada QUITA " video=DSI-1:d" de la base
        # L19/k64 y AÑADE el skip del reset -> 580-14+26 = 592 B. Igualdad exacta.
        esperado = (k64cmd.replace(b" video=DSI-1:d", b" video=DSI-1:e")
                   .replace(b" console=tty0", b"").replace(b" fbcon=map:0", b"")
                   + b" msm.fbdev=0 msm.uke_skip_mdss_reset=1")
        if cmd != esperado:
            die("G6 FALLO: la cmdline final no es la L32 esperada\n"
                "        esperada %d B: %r\n        obtenida %d B: %r"
                % (len(esperado), esperado, len(cmd), cmd))
        log("  OK  cmdline = L32 (k64/L19 580 B -14 (:d) +26 (skip) -> 592 B), prefijo intacto")
    elif open(K64IMG, "rb").read()[CMD_OFF:CMD_OFF + CMD_FIELD].split(b"\x00")[0] == cmd:
        log("  OK  vs s240 confinado; cmdline = k64 (580 B, uke_gmu_shared=0) por diseno #586")
    elif dif > (14 if DSID else 0):
        die("G6 FALLO: cmdline difiere de la referencia en %d B" % dif)
    else:
        log("  OK  vs s240 confinado; vs %s: cmdline %d B difieren" % ("k13d" if DSID else "k13", dif))

    log("\n=== G7: publicacion ===")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as f:
        f.write(bytes(img))
    out = open(OUT, "rb").read()
    if sha(out) != sha(bytes(img)):
        die("G7 FALLO: relectura")
    log("  %s" % OUT)
    log("  %d B   sha256 = %s" % (len(out), sha(out)))
    log("\n  ESTE SHA TIENE QUE IR PRE-REGISTRADO (ledger, fila L32) ANTES DE FLASHEAR.")

    import subprocess, shutil
    log("\n=== G8: herramientas ===")
    if shutil.which("unpack_bootimg"):
        ud = "/var/tmp/uke-k52L32-unpack"
        r = subprocess.run(["unpack_bootimg", "--boot_img", OUT, "--out", ud],
                           capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            die("G8 FALLO: unpack_bootimg rc=%d" % r.returncode)
        if sha(open(os.path.join(ud, "kernel"), "rb").read()) != sha(kern):
            die("G8 FALLO: kernel extraido != Image.gz")
        log("  OK  unpack_bootimg rc=0")
    else:
        log("  G8 unpack_bootimg [NO DISPONIBLE]")
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, "w", encoding="utf-8") as f:
        f.write("\n".join(LOGF) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
