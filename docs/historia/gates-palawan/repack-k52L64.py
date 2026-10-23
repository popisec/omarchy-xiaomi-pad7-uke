#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
repack-k52L64.py — boot-uke-k52L64.img (14-oct): L63 display-only (kernel nuevo k52L64-build).
L64: PPS post-0x29 como L63 pero config del L62 SIN carga =y (el wedge L63 exculpa
display: fue la carga; battmgr/glink/ucsi vuelven a =m). Build DONE 23:34:08;
panel .o 23:10:11 > fuente 23:09:53 (sin cambios, make lo conserva); Image 23:34:06.
Refs: `L63-PPS-ORDEN.md`, `CARGA-ANDROID-REF.md`. Cmdline 622 B = L63 byte a byte.
Append=-video=DSI-1:d,iomem=relaxed,arm_smmu.uke_disp_reclaim=1,regulator_ignore_unused
(igual que L56; primero se valida la cmdline 632 B == L56 byte a byte y LUEGO se corta).
NO invocar con --dsid. NO flashear hasta verificado L56 (cold boot; rollback = L56 3e68abe8).
Clon de repack-k52L56.py: IDENTICOS gates de kernel (UKE-L56=1, UKE-L45=1, FIX-A1b=6,
UKE-K68/D2 + UKE-K65/D3 verbatim) y ausencia de K64/C1/poll/G10/G8,
de D ajeno (k65-D1/k65-D2/K66/K67/K68-SIN-D1/L2-SIN-D2/L2-SIN-D3) y de
familia + los 11 testigos UKE-L6 del tramo ciego (x1 c/u) + los 7 testigos UKE-L7 del tramo K44→S3 (x1 c/u) + los 2 testigos UKE-L8 (write-done tras el write, nopoll-ok como EPILOGO post-poll) + los 4 testigos UKE-L10 del hunk vendor (L10-gbif/L10-recfg args + pr_err, x1 c/u) + los 2 testigos UKE-L11 del poll VENDOR (L11-pollok arg + pr_err, x1 c/u); cmdline = L56 menos mem + cpio = k52b2. SOLO-PC (repack; sin tablet).
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
KERNEL = R + "/build/kernel-pokes/k52L64-build/arch/arm64/boot/Image.gz"
K13_INITRAMFS = R + "/build/init/uke-k22-initramfs.cpio.gz"
K13_INITRAMFS_SHA = "08780e3565c2641660703f884bbac9c0f3aab0e1e8cadb78611a674e5238b706"
# fallback del cpio si /var/tmp lo borran otra vez (copias verificadas):
K13_INITRAMFS_FB = R + "/build/init/uke-k12-initramfs.cpio.gz"  # fallback: cpio K12 puro (sin fw)

DSID = False  # L46: display-ON por --cmdline-append; sin variante dsid
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
        # L46: aceptar tambien --flag=valor (el runbook lo escribe asi)
        for a in sys.argv:
            if a.startswith(flag + "="):
                return [t.encode() for t in a[len(flag) + 1:].split(",") if t]
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
else:
    OUT = R + "/build/bootimg/boot-uke-k52L64.img"
    LOG = R + "/build/bootimg/repack-k52L64-report.txt"

PAGE, CMD_OFF, KS_OFF, RS_OFF = 4096, 44, 8, 12
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
    log("=== G0: entradas (L64) ===")
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
                "drivers/soc/qcom/qcom-geni-se.c",
                "drivers/video/backlight/ktz8866.c",
                "drivers/gpu/drm/msm/adreno/a6xx_gmu.c",
                "drivers/gpu/drm/msm/adreno/a6xx_gpu.c",
                "drivers/gpu/drm/msm/adreno/adreno_device.c",
                "drivers/gpu/drm/msm/adreno/adreno_gpu.c",
                "drivers/gpu/drm/msm/msm_drv.c",
                "drivers/gpu/drm/msm/msm_gpu.c",
                "drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c",
                "drivers/soc/qcom/uke-panic-fb.c"):
        src = R + "/build/kernel-pokes/k52-L16-tree/" + rel
        if not os.path.isfile(src):
            die("G0 FALLO: no existe el fuente %s" % src)
        if os.path.getmtime(src) > os.path.getmtime(KERNEL):
            die("G0 FALLO: %s mas nuevo que Image.gz (build rancio)" % rel)
    log("  OK  Image.gz %d B sha256=%s (11 fuentes sin cambios posteriores)"
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
    if b"msm.uke_gmu_shared=0" not in cmd:
        die("G2 FALLO: la cmdline no trae msm.uke_gmu_shared=0 (R6-gmu-erange)")
    if b"video=DSI-1:d" not in cmd:
        die("G2 FALLO: sin video=DSI-1:d")
    if TOK_PROBE in cmd or b"  " in cmd:
        die("G2 FALLO: probe token o doble espacio")
    for t in TOKS_KEPT:
        if cmd.count(t) != 1:
            die("G2 FALLO: token %r aparece %d veces" % (t, cmd.count(t)))
    # L46: el SOURCE (k64) trae video=DSI-1:d; la variante display-ON lo QUITA con
    # --cmdline-append=-video=DSI-1:d; el gate de la cmdline final va mas abajo.

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
    if b"video=" in cmd:
        die("G2 FALLO: display-ON pero la cmdline final trae video=")
    if len(cmd) != 632:
        die("G2 FALLO: cmdline display-ON+iomem+reclaim+regulator mide %d != 632" % len(cmd))
    if b"iomem=relaxed" not in cmd:
        die("G2 FALLO: sin iomem=relaxed")
    # L52 (FIX-A1b quirurgico): reclaim SI, wmask global NO (default 0).
    # El param uke_write_mask SIGUE existiendo como modulo: el gate de ausencia
    # es sobre la CMDLINE, nunca sobre el binario.
    if b"arm_smmu.uke_disp_reclaim=1" not in cmd:
        die("G2 FALLO: sin token reclaim arm_smmu.uke_disp_reclaim=1")
    if b"regulator_ignore_unused" not in cmd:
        die("G2 FALLO: sin token regulator_ignore_unused (hipotesis AVDD L54/L55/L56)")
    if b"ignore_loglevel" in cmd:
        die("G2 FALLO: ignore_loglevel sigue en cmdline (L54/L55/L56 lo quitan)")
    if b"uke_write_mask" in cmd:
        die("G2 FALLO: uke_write_mask en cmdline (L56 sigue sin wmask global)")
    log("  OK  cmdline %d B (display-ON + iomem=relaxed + reclaim + regulator, sin loglevel/wmask; L56)" % len(cmd))

    # --- L58: mismo corte mem=2048M que L57 (mecanismo verificado, intacto) -----
    # La cmdline 632 B validada arriba TIENE que ser la L56 byte a byte: se
    # comprueba contra el artefacto L56 real (sha pre-registrado 3e68abe8) y
    # LUEGO se corta EXACTAMENTE el prefijo b"mem=2048M " (10 B). Los dos
    # memmap= quedan intactos (gate de conteo antes y despues del corte).
    MEMCUT = b"mem=2048M "
    L56IMG = R + "/build/bootimg/boot-uke-k52L56.img"
    L56_SHA = "3e68abe88223ed11974024ce4278e5c127c49ef5d1127365893d7075b482728f"
    if not os.path.isfile(L56IMG) or sha(open(L56IMG, "rb").read()) != L56_SHA:
        die("G2-L58 FALLO: artefacto L56 ausente o con sha distinto de 3e68abe8 (rollback invalido)")
    l56cmd = open(L56IMG, "rb").read()[CMD_OFF:CMD_OFF + CMD_FIELD].split(b"\x00")[0]
    if len(l56cmd) != 632:
        die("G2-L58 FALLO: cmdline del artefacto L56 mide %d != 632" % len(l56cmd))
    if cmd != l56cmd:
        die("G2-L58 FALLO: la cmdline 632 B NO es la L56 byte a byte (el corte seria sobre otra base)")
    log("  OK  cmdline 632 B pre-corte == artefacto L56 (3e68abe8) byte a byte")
    if not cmd.startswith(MEMCUT):
        die("G2-L58 FALLO: la cmdline no empieza por 'mem=2048M ' (%r...)" % cmd[:40])
    if cmd.count(b"mem=2048M") != 1:
        die("G2-L58 FALLO: mem=2048M aparece x%d != 1" % cmd.count(b"mem=2048M"))
    if cmd.count(b"memmap=") != 2:
        die("G2-L58 FALLO: memmap= aparece x%d != 2 (se tocaria un carveout)" % cmd.count(b"memmap="))
    cmd = cmd[len(MEMCUT):]
    if b"mem=2048M" in cmd or b"  " in cmd:
        die("G2-L58 FALLO: residuo de mem o doble espacio tras el corte")
    if cmd.count(b"memmap=") != 2:
        die("G2-L58 FALLO: un memmap= se perdio en el corte")
    for t in (b"regulator_ignore_unused", b"uke_disp_reclaim",
              b"arm_smmu.uke_disp_reclaim=1", b"iomem=relaxed",
              b"memmap=0x1A12800$0xE3940000", b"memmap=0x2B00000$0xE3940000"):
        if cmd.count(t) != 1:
            die("G2-L58 FALLO: token %r x%d != 1 tras el corte" % (t, cmd.count(t)))
    if b"video=" in cmd or b"ignore_loglevel" in cmd or b"uke_write_mask" in cmd:
        die("G2-L58 FALLO: video/loglevel/wmask tras el corte (herencia L56 rota)")
    if len(cmd) != 622:
        die("G2-L58 FALLO: cmdline post-corte mide %d != 622" % len(cmd))
    log("  OK  L58: cmdline 622 B = L56 menos el prefijo 'mem=2048M ' (mecanismo L57 exacto; resto intacto y en orden)")
    # L58: la cmdline final TIENE que ser la L57 byte a byte (mismo corte, mismos
    # tokens: el kernel cambia, la cmdline no). Barrido total de mem= ya exigido arriba.
    L57IMG = R + "/build/bootimg/boot-uke-k52L57.img"
    L57_SHA = "ebe9409340db2ad5499ced7ac2f3db088e1558a0c74f46fd1b5f559d068c2b82"
    if not os.path.isfile(L57IMG) or sha(open(L57IMG, "rb").read()) != L57_SHA:
        die("G2-L58 FALLO: artefacto L57 ausente o con sha distinto de ebe94093 (referencia invalida)")
    l57cmd = open(L57IMG, "rb").read()[CMD_OFF:CMD_OFF + CMD_FIELD].split(b"\x00")[0]
    if cmd != l57cmd:
        die("G2-L58 FALLO: cmdline != L57 byte a byte\n"
            "        esperada (%d B): %r\n        obtenida (%d B): %r"
            % (len(l57cmd), l57cmd, len(cmd), cmd))
    log("  OK  cmdline 622 B == artefacto L57 (ebe94093) byte a byte")
    # L59: la cmdline TIENE que ser la L58 byte a byte (el kernel cambia, la
    # cmdline no). Transitivo con lo anterior (L58 == L57), pero explicito.
    L58IMG = R + "/build/bootimg/boot-uke-k52L58.img"
    L58_SHA = "763d7869795e4699a6950e0ff91426d028732f14adc583d6f935653e82098550"
    if not os.path.isfile(L58IMG) or sha(open(L58IMG, "rb").read()) != L58_SHA:
        die("G2-L59 FALLO: artefacto L58 ausente o con sha distinto de 763d7869 (referencia invalida)")
    l58cmd = open(L58IMG, "rb").read()[CMD_OFF:CMD_OFF + CMD_FIELD].split(b"\x00")[0]
    if cmd != l58cmd:
        die("G2-L59 FALLO: cmdline != L58 byte a byte (%d B vs %d B)" % (len(l58cmd), len(cmd)))
    log("  OK  cmdline 622 B == artefacto L58 (763d7869) byte a byte")
    # L62: la cmdline TIENE que ser la L59 byte a byte (el kernel cambia, la
    # cmdline no). Transitivo con lo anterior, pero explicito.
    L59IMG = R + "/build/bootimg/boot-uke-k52L59.img"
    L59_SHA = "e3511595de6cb2ae142735402e5b5db0c0dfcdbbe5412f78307aa8686829534e"
    if not os.path.isfile(L59IMG) or sha(open(L59IMG, "rb").read()) != L59_SHA:
        die("G2-L62 FALLO: artefacto L59 ausente o con sha distinto de e3511595 (referencia invalida)")
    l59cmd = open(L59IMG, "rb").read()[CMD_OFF:CMD_OFF + CMD_FIELD].split(b"\x00")[0]
    if cmd != l59cmd:
        die("G2-L62 FALLO: cmdline != L59 byte a byte (%d B vs %d B)" % (len(l59cmd), len(cmd)))
    log("  OK  cmdline 622 B == artefacto L59 (e3511595) byte a byte")
    # L63: la cmdline TIENE que ser la L62 byte a byte (el kernel cambia, la
    # cmdline no). Transitivo con lo anterior, pero explicito.
    L62IMG = R + "/build/bootimg/boot-uke-k52L62.img"
    L62_SHA = "d52f59677af04a9d5ab9efcffd0b5d7224b2dcc3fedea1cca621cd519f90f260"
    if not os.path.isfile(L62IMG) or sha(open(L62IMG, "rb").read()) != L62_SHA:
        die("G2-L63 FALLO: artefacto L62 ausente o con sha distinto de d52f5967 (referencia invalida)")
    l62cmd = open(L62IMG, "rb").read()[CMD_OFF:CMD_OFF + CMD_FIELD].split(b"\x00")[0]
    if cmd != l62cmd:
        die("G2-L63 FALLO: cmdline != L62 byte a byte (%d B vs %d B)" % (len(l62cmd), len(cmd)))
    log("  OK  cmdline 622 B == artefacto L62 (d52f5967) byte a byte")
    # L64: la cmdline TIENE que ser la L63 byte a byte (el kernel cambia, la
    # cmdline no). Transitivo con lo anterior, pero explicito.
    L63IMG = R + "/build/bootimg/boot-uke-k52L63.img"
    L63_SHA = "1d7b440f901d98a6f659c2cdde81b7370364f357804b88f34181068a244ee109"
    if not os.path.isfile(L63IMG) or sha(open(L63IMG, "rb").read()) != L63_SHA:
        die("G2-L64 FALLO: artefacto L63 ausente o con sha distinto de 1d7b440f (referencia invalida)")
    l63cmd = open(L63IMG, "rb").read()[CMD_OFF:CMD_OFF + CMD_FIELD].split(b"\x00")[0]
    if cmd != l63cmd:
        die("G2-L64 FALLO: cmdline != L63 byte a byte (%d B vs %d B)" % (len(l63cmd), len(cmd)))
    log("  OK  cmdline 622 B == artefacto L63 (1d7b440f) byte a byte")

    log("\n=== G3: kernel L64 ===")
    import gzip
    raw = gzip.decompress(kern)
    # L49: netconsole (+~290 KB de .text/rodata) amplia la tolerancia a 512 KB
    if abs(len(raw) - 41355776) > 524288:
        die("G3 FALLO: Image crudo %d B (delta desproporcionado)" % len(raw))
    # L46: F-INT-5 REFUTADA (medido en el binario): los call-sites nuevos de
    # uke_poke() NO anaden la cadena "UKE-POKE" (vive en el helper por TU);
    # el conteo sigue 113.
    # L48: el heartbeat (pr_err "UKE-POKE: K48-alive-%d") y el opp-rate anaden 2
    # literales "UKE-POKE" -> 113 + 2 = 115 (medido en el binario).
    # L52 (FIX-A1b, reemplazo limpio de A1): 6 pr_info("UKE-POKE: FIX-A1b: ...")
    # sobre base L50 sin A1 -> 115 + 6 = 121 (= 117-2+6; fuente: 6x
    # 'UKE-POKE: FIX-A1b' en arm-smmu.c, 0x 'FIX-A1:' viejo).
    if raw.count(b"UKE-POKE") != 121:
        die("G3 FALLO: UKE-POKE=%d != 121" % raw.count(b"UKE-POKE"))
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
    log("  OK  crudo %d B; POKE=115; K13=11; K16=1; P82>=20; S0; K18 param+volcado presentes" % len(raw))

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
    for t, n in ((b"UKE-L43-ICC", 1), (b"X9I2C-icc-get-ok", 1)):
        if raw.count(t) != n:
            die("G3 FALLO: marcador L43 %r x%d (hay x%d)" % (t, n, raw.count(t)))
    log("  OK  L43: marcadores UKE-L43-ICC x1 + X9I2C-icc-get-ok x1")
    # L44: el driver KTZ8866 va built-in (=y); sus strings vendor-exactos
    # tienen que estar en el binario (los 3 llevan prefijo "ktz8866", unicos
    # en el arbol; verificado por grep -rlF contra k52-L16-tree/drivers/).
    # Sin marcador UKE-L44-*: no hizo falta anadirlo.
    for t, n in ((b"ktz8866 backlight 0x%02x ,exponential brightness %d", 1),
                  (b"probe sucess end", 1),
                  (b"ktz8866 backlight out of 4095 too large!!!", 1)):
        if raw.count(t) != n:
            die("G3 FALLO: string KTZ L44 %r x%d (hay x%d)" % (t, n, raw.count(t)))
    log("  OK  L44: strings KTZ x1 c/u (exponential/probe-sucess/out-of-4095)")
    for t, n in ((b"UKE-L45", 1), (b"reintento de probe", 1)):
        if raw.count(t) != n:
            die("G3 FALLO: marcador L45 %r x%d (hay x%d)" % (t, n, raw.count(t)))
    log("  OK  L45: marcadores UKE-L45 x1 + reintento-de-probe x1")
    for t, n in ((b"L27-vci-ok", 1), (b"L27-vci-absent", 1), (b"UKE-P82: power_on: vci", 1)):
        if raw.count(t) != n:
            die("G3 FALLO: marcador vci L46 %r x%d (hay x%d)" % (t, n, raw.count(t)))
    # S4-DIAG: en FUENTE sale 9x (con comentarios); el gate cuenta en el
    # BINARIO como hizo L49 (medido Image.gz L49: 4). No "corregir" a 9.
    if raw.count(b"S4-DIAG") != 4:
        die("G3 FALLO: S4-DIAG x%d != 4" % raw.count(b"S4-DIAG"))
    log("  OK  L46: vci x3 (ok/absent/power_on) + S4-DIAG x4")
    # L47: las 9 migas nuevas del enable-path, x1 c/u (el agregado K47- depende
    # del compilador y ya hay tags historicos; gate por-tag, preciso)
    # (K47-crtc-en y K47-phy-en YA existian en L46: no se gatean como nuevas)
    for t in (b"K47-atom-tail", b"K47-dpu-hw-in", b"K47-kms-en-commit", b"K47-dpu-res",
              b"K47-enc-en", b"K47-brg-pre-en", b"K47-mgr-phy-en"):
        if raw.count(t) != 1:
            die("G3 FALLO: miga L47 %r x%d" % (t, raw.count(t)))
    log("  OK  L47: 7 migas nuevas x1 c/u (crtc-en/phy-en ya existian)")
    # L48: 13 tags literales nuevos x1 + el formato del heartbeat
    for t in (b"K48-opp-rate", b"K48-mdss-en-in", b"K48-mdss-en-ok", b"K48-res-clk-in",
              b"K48-res-clk-ok", b"K48-hw-resume-ok", b"K48-hw-mmu-ok", b"K48-res-vbif-ok",
              b"K48-res-enc-ok", b"K48-hw-vbif-ok", b"K48-post-init", b"K48-dpu-susp", b"K48-mdss-susp"):
        if raw.count(t) < 1:
            die("G3 FALLO: miga L48 %r ausente" % t)
    if raw.count(b"K48-alive") != 1:
        die("G3 FALLO: K48-alive x%d != 1" % raw.count(b"K48-alive"))
    log("  OK  L48: 13 tags K48 + heartbeat (K48-alive x1)")
    # L49: los pokes de captura del prep (l49-capture.diff) + el netconsole
    for t in (b"L49-host-vreg-ok", b"L49-host-clk-ok", b"L49-host-ctrl-ok", b"L49-phy-ok", b"L49-pwron-ok"):
        if raw.count(t) != 1:
            die("G3 FALLO: poke L49 %r x%d" % (t, raw.count(t)))
    if raw.count(b"netconsole") < 1:
        die("G3 FALLO: sin netconsole en el binario")
    log("  OK  L49: 5 pokes de captura + netconsole")
    # L50 (14-oct, l50-instrument.diff): 12 tags uke_poke("K50-*") -> 18
    # ocurrencias de b"K50-" en el binario (6 tags x2 poke+pr_err con valores +
    # 6 tags x1 solo-poke) + los 6 formatos con valores x1 c/u. Cero literales
    # "UKE-POKE" anadidos (medido grep -c = 0) -> UKE-POKE se mantiene en 115.
    # (Medido en el diff: K50- x18, pr_err("K50- x6, uke_poke("K50- x12.)
    if raw.count(b"K50-") != 18:
        die("G3 FALLO: K50- x%d != 18" % raw.count(b"K50-"))
    for t in (b"K50-dma-base=", b"K50-commit: id=", b"K50-mgr-enter: id=",
              b"K50-clk-en: id=", b"K50-ctrl-ok: id=", b"K50-trig-done: id="):
        if raw.count(t) != 1:
            die("G3 FALLO: formato L50 %r x%d != 1" % (t, raw.count(t)))
    log("  OK  L50: K50- x18 + 6 formatos con valores x1 c/u")
    # L52 (FIX-A1b): "FIX-A1b" en 6 literales (6 pr_info; los otros 5 de la
    # fuente son comentarios y no compilan). "FIX-A1:" con dos puntos = el A1
    # viejo: debe ser 0 ("FIX-A1b:" no contiene ese substring: tras el 1 va 'b').
    # Medido en fuente: FIX-A1b x11 (6 codigo + 5 comentarios), FIX-A1: x0.
    if raw.count(b"FIX-A1b") != 6:
        die("G3 FALLO: FIX-A1b x%d != 6" % raw.count(b"FIX-A1b"))
    if raw.count(b"FIX-A1:") != 0:
        die("G3 FALLO: residuo FIX-A1: viejo x%d (A1 no reemplazado)" % raw.count(b"FIX-A1:"))
    # uke_disp_reclaim: 1x como nombre de param (patron uke_kgsl_keep).
    if raw.count(b"uke_disp_reclaim") != 1:
        die("G3 FALLO: uke_disp_reclaim x%d != 1" % raw.count(b"uke_disp_reclaim"))
    log("  OK  L52: FIX-A1b x6 + viejo FIX-A1: x0 + uke_disp_reclaim x1 (UKE-POKE=121)")
    # L53 (instrumento KTZ, l53-ktz-dump.diff, solo ktz8866.c): "UKE-K53" sale
    # 2x en fuente (1 comentario + 1 pr_err) -> binario x1. Los 5 tags van x1
    # en fuente como args de uke_ktz_dump; pero en BINARIO solo se gatean los 3
    # unicos tree-wide ("update-in" colisiona con "dlg,update-interval" de
    # da9150-fg.c; "post-init" con "K48-post-init" y "post-init-providers").
    # Medido: update-out / probe-entry (estado ABL) / post-first-update x1 c/u
    # en todo el arbol; update-in y post-init x1 en ktz8866.c (solo fuente).
    if raw.count(b"UKE-K53") != 1:
        die("G3 FALLO: UKE-K53 x%d != 1" % raw.count(b"UKE-K53"))
    for t in (b"update-out", b"probe-entry (estado ABL)", b"post-first-update"):
        if raw.count(t) != 1:
            die("G3 FALLO: tag KTZ L53 %r x%d != 1" % (t, raw.count(t)))
    log("  OK  L53: UKE-K53 x1 + 3 tags KTZ unicos x1 (update-in/post-init solo-fuente x1)")
    # L58 (zram=y/zsmalloc=y/LZ4, kernel nuevo): deltas medidos L56->L58 en
    # binario (raw; strings -n 8 coincide salvo zram: 19/17 porque 2 literales
    # son el nombre corto "zram" <8 chars y strings los filtra):
    # zram 0->19, comp_algorithm 0->2, zsmalloc 0->6, disksize 1->3 (+2 del
    # driver; el 1 preexistente es de otro driver), "zram: " (pr_fmt) 0->10.
    # lz4_compress/zram0/max_comp_streams/ZRAM siguen a 0 (nombres que este
    # arbol no usa): NO se gatean. Baseline L56 medido antes del repack.
    for t, n in ((b"comp_algorithm", 2), (b"zsmalloc", 6), (b"zram", 19),
                 (b"disksize", 3)):
        if raw.count(t) != n:
            die("G3 FALLO: zram L58 %r x%d != %d" % (t, raw.count(t), n))
    log("  OK  L58: zram (comp_algorithm x2 + zsmalloc x6 + zram x19 + disksize x3)")
    # L59 (PPS DSC, solo panel o82): 3 tags uke_poke("L37-pps-*") pack/send/done
    # (:412/:414/:433, sin UKE-POKE por F-INT-5 -> UKE-POKE sigue 121) + 2
    # pr_info "UKE-L37: ..." (:428 ok, :435 fallo con accum_err del fix).
    # Medido en binario (raw == strings): L37-pps=3, UKE-L37=2.
    if raw.count(b"L37-pps") != 3:
        die("G3 FALLO: L37-pps x%d != 3" % raw.count(b"L37-pps"))
    if raw.count(b"UKE-L37") != 2:
        die("G3 FALLO: UKE-L37 x%d != 2" % raw.count(b"UKE-L37"))
    log("  OK  L59: PPS (L37-pps x3 + UKE-L37 x2)")
    # L62 (PPS dims por link, panel o82 :431): pr_info "UKE-L62: PPS dims=%ux%u
    # por link (host=%ux%u)". Fuente x1 (sin comentario) -> binario x1 (medido:
    # raw == strings == 1; baseline L59 = 0).
    if raw.count(b"UKE-L62") != 1:
        die("G3 FALLO: UKE-L62 x%d != 1" % raw.count(b"UKE-L62"))
    log("  OK  L62: UKE-L62 x1 (PPS 1600x2136 por link)")
    # L63 (PPS post-0x29 via o82_enable, panel :627): pr_info "UKE-L63: PPS
    # post-0x29 enviada (dims=%ux%u por link, err=%d)". Fuente x1 (sin
    # comentario) -> binario x1 (medido raw == strings == 1; baseline L62 = 0).
    if raw.count(b"UKE-L63") != 1:
        die("G3 FALLO: UKE-L63 x%d != 1" % raw.count(b"UKE-L63"))
    log("  OK  L63: UKE-L63 x1 (PPS post-0x29)")
    # L64 display-only: hereda UKE-L63 x1 (mismo panel) pero SIN los drivers de
    # carga (vuelven a =m). El bloque L63 de carga-presente NO aplica aqui.
    # L64 display-only (config L62: glink/ucsi/battmgr =m): carga AUSENTE como
    # en L62 (medido raw == strings). `pmic_glink` (guion bajo) queda x1 del
    # altmode preexistente — no se gatea, solo se documenta.
    for t in (b"pmic-glink", b"qcom,pmic-glink", b"ucsi_glink", b"qcom_battmgr", b"battmgr"):
        if raw.count(t) != 0:
            die("G3 FALLO: carga L64 %r x%d (display-only: debe ser 0)" % (t, raw.count(t)))
    log("  OK  L64: sin carga (pmic-glink/qcom,pmic-glink/ucsi_glink/battmgr x0)")
    # L56 (KTZ PWM_EN=0 I2C-only + re-armo en probe, solo ktz8866.c): "UKE-L56"
    # sale 1x en fuente (dev_info :596, sin comentario) -> binario x1 (medido: 1).
    if raw.count(b"UKE-L56") != 1:
        die("G3 FALLO: UKE-L56 x%d != 1" % raw.count(b"UKE-L56"))
    log("  OK  L56: UKE-L56 x1 (PWM_EN=0 + re-armo)")
    # L56 vuelve al externo (panel reclama KTZ): UKE-L45 x1 + reintento x1
    # (medido en binario: 1/1; el L55 los tenia a 0). Sin marcadores internos:
    # "failed to create backlight" x0 (el x1 fusionado del L55 era del o82
    # interno; el jdi nunca estuvo compilado) y K47-pan-bl x0 (medido: 0/0).
    if raw.count(b"failed to create backlight") != 0:
        die("G3 FALLO: failed-to-create-backlight x%d (L56 es externo)" % raw.count(b"failed to create backlight"))
    if raw.count(b"K47-pan-bl") != 0:
        die("G3 FALLO: K47-pan-bl x%d (L56 es externo)" % raw.count(b"K47-pan-bl"))
    log("  OK  L56: panel externo (sin failed-to-create ni K47-pan-bl)")
    # L47: FBDEV_EMULATION=n medido en el binario (L46: drmfb=1, drm_client_setup=3)
    if raw.count(b"drmfb") != 0 or raw.count(b"drm_client_setup") != 0:
        die("G3 FALLO: FBDEV=n no efectivo (drmfb=%d drm_client_setup=%d)"
            % (raw.count(b"drmfb"), raw.count(b"drm_client_setup")))
    log("  OK  L47: FBDEV=n efectivo (drmfb=0, drm_client_setup=0)")
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
    # L44: el KTZ built-in crece .text; la ventana +-128K lo absorbe.
    # L43: el parche ICC crece .text y el offset puede moverse unos KB más; se
    # admite una ventana +-128K y se exige el CONTENIDO byte-idéntico (check
    # fuerte de abajo). El offset exacto no es un invariante.
    # L58: ventana +-192K (era +-128K): zram+zsmalloc+LZ4 crecen .text +69632 B
    # y el cpio embebido se desplaza +131912 (exceso de 840 B sobre 128K; contenido
    # verificado byte-identico a mano: 2099712 B). El check fuerte de CONTENIDO
    # sigue intacto; el offset exacto no es un invariante.
    if pos64 == -1 or blob_at is None or abs(blob_at - pos64) > 196608:
        die("G3 FALLO: initramfs embebido fuera de la ventana k52b2 +-192K "
            "(offset %s vs %s)" % (blob_at, pos64))
    dd2 = zlib.decompressobj(31)
    try:
        dec70 = dd2.decompress(raw[blob_at:blob_at + 8_000_000])
    except Exception:
        dec70 = None
    if dec70 is None or dec70 != dec64:
        die("G3 FALLO: cpio embebido != cpio del k52b2")
    log("  OK  initramfs embebido @%d byte-idéntico al del k52b2" % blob_at)

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
        ref_cmd = open(K64IMG, "rb").read()[CMD_OFF:CMD_OFF + CMD_FIELD].split(b"\x00")[0]
        # Se replican aqui las MISMAS reglas que se aplicaron a `cmd` en G2
        # (borrar con -token, anadir el resto), para que la referencia esperada
        # sea la referencia REAL y no "la de referencia + solo los appends".
        # Sin esto, un borrado legitimo hacia fallar el gate (fallo real que
        #fue justo lo que paso, sesion #456).
        esperado = ref_cmd
        for tok in CMD_APPEND:
            if tok.startswith(b"-"):
                opt = tok[1:]
                if opt in esperado:
                    esperado = esperado.replace(b" " + opt, b"")
            else:
                esperado = esperado + b" " + tok
        if not esperado.startswith(MEMCUT):
            die("G6 FALLO: la referencia+append no empieza por 'mem=2048M ' (k64 cambio?)")
        esperado = esperado[len(MEMCUT):]  # L57: el corte aplica tambien a la referencia
        if cmd != esperado:
            die("G6 FALLO: la cmdline final no es referencia+append\n"
                "        esperada %d B: %r\n        obtenida %d B: %r"
                % (len(esperado), esperado, len(cmd), cmd))
        log("  OK  cmdline L57 = referencia (%d B) + append - prefijo mem (neto %+d B)"
            % (len(ref_cmd), len(cmd) - len(ref_cmd)))
        # L56: la cmdline final = igual que L54 (k64-sin-video + iomem + reclaim + regulator).
        # (SIN wmask, SIN loglevel). Se exige byte-identica a esa referencia (632 B).
        # L57: la MISMA referencia MENOS el prefijo 'mem=2048M ' (622 B).
        k64cmd = open(K64IMG, "rb").read()[CMD_OFF:CMD_OFF + CMD_FIELD].split(b"\x00")[0]
        k64on = (k64cmd.replace(b" video=DSI-1:d", b"") + b" iomem=relaxed"
                 + b" arm_smmu.uke_disp_reclaim=1" + b" regulator_ignore_unused")
        if len(k64on) != 632:
            die("G6 FALLO: referencia L56 mide %d != 632 (k64 cambio?)" % len(k64on))
        if not k64on.startswith(MEMCUT):
            die("G6 FALLO: la referencia k64 no empieza por 'mem=2048M ' (k64 cambio?)")
        k64on57 = k64on[len(MEMCUT):]
        if cmd != k64on57:
            die("G6 FALLO: cmdline != k64-sin-video+reclaim+regulator SIN mem (%d B vs %d B)\n"
                "        esperada: %r\n        obtenida: %r"
                % (len(k64on57), len(cmd), k64on57, cmd))
        log("  OK  cmdline byte-idéntica a k64 sin ' video=DSI-1:d' NI 'mem=2048M ' + reclaim + regulator (%d B)" % len(cmd))
        if cmd != l56cmd[len(MEMCUT):]:
            die("G6 FALLO: cmdline != artefacto L56 menos el prefijo mem")
        log("  OK  cmdline == artefacto L56 (3e68abe8) menos 'mem=2048M ' (%d B)" % len(cmd))
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
    log("\n  ESTE SHA TIENE QUE IR PRE-REGISTRADO (ledger, fila L64) ANTES DE FLASHEAR.")
    log("  NO FLASHAR hasta verificado L56 en la tablet; rollback = L56 3e68abe8.")

    import subprocess, shutil
    log("\n=== G8: herramientas + ausencia de mem ===")
    # Gate (a) L57: mem=2048M AUSENTE de la imagen resultante.
    # Metodo: el kernel (gz y crudo) NO contiene el token (medido: x0/x0), asi
    # que un barrido de los 96 MiB == barrido de cmdline+bootconfig. Ademas se
    # lee el campo cmdline de cabecera (offset 44, 1536 B) y se exige que no lo
    # traiga; y se cruza con unpack_bootimg (kernel extraido == Image.gz).
    if bytes(img[CMD_OFF:CMD_OFF + CMD_FIELD]).count(b"mem=2048M") != 0:
        die("G8 FALLO: mem=2048M sigue en el campo cmdline de cabecera")
    if bytes(img).count(b"mem=2048M") != 0:
        die("G8 FALLO: mem=2048M aparece en la imagen (%dx)"
            % bytes(img).count(b"mem=2048M"))
    log("  OK  mem=2048M x0 en campo cmdline (44+1536) y x0 en los 96 MiB")
    if shutil.which("unpack_bootimg"):
        ud = "/var/tmp/uke-k52L64-unpack"
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
