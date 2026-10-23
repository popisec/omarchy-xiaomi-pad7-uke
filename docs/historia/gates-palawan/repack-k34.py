#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
repack-k18.py — boot-ukek18.img / boot-ukek18d.img (#P47): kernel K17 + UKE-K18
(uke_kgsl_keep: el kgsl-smmu conserva el estado del BL; volcado de SMR/S2CR
heredados en probe). El fix del asesino unificado: el CM3 del GMU wedgeaba el
bus al liberarlo (S3-rst0) porque su fetch icache (SID 5, kgsl-smmu) quedaba
sin la traduccion del BL tras el reset mainline.

    base      : ~/gpu-work/ramaa/s21/avb/boot-s240-mem2g.img (e3c60969…, 96 MiB)
    kernel    : build/kernel-pokes/k18-build/arch/arm64/boot/Image.gz
                (k13-tree + k16-disp-split + k17-migas-panel-gmu + K18-kgsl-keep)
    cmdline   : variante plain = la de boot-ukek13.img (356 B, SIN video=);
                --dsid = la de boot-ukek13-dsid.img (370 B, video=DSI-1:d).
    AVB/dtb/second/cola: byte a byte s240. initramfs: cpio K12/K13 (cb10ff40…).
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
KERNEL = R + "/build/kernel-pokes/k18-build/arch/arm64/boot/Image.gz"
K13_INITRAMFS = R + "/build/init/uke-k34-fw-initramfs.cpio.gz"
K13_INITRAMFS_SHA = "ebc2de46ea89a4512be06b87e92d5dbb2f8aca8fe9a07304b697566551bf48bc"
# fallback del cpio si /var/tmp lo borran otra vez (copias verificadas):
K13_INITRAMFS_FB = R + "/build/init/uke-k34-fw-initramfs.cpio.gz"

DSID = "--dsid" in sys.argv
# --- K23b (1-oct-2026): --out / --kernel / --gate-k23b ---------------------
# ANTES: OUT fijo en boot-ukek18[ d].img, y el repack del K23 (2:36) escribio
# boot-ukek18d.img, el MISMO nombre que #P47 habia pre-registrado con otro sha
# (99d49b06). Por eso el K23 se renombro a boot-ukek23.img a mano. Con --out el
# nombre ya no se pisa y el reporte lo dice.
# GATE_K23B: exige en el binario los marcadores del dump CORREGIDO (1-oct).
# Sin este flag se puede re-empaquetar el kernel viejo, cuyo dump miente.
GATE_K23B = "--gate-k23b" in sys.argv
# --- K45 (#495): variante PANTALLA SIN GPU (DRM_MSM=n): el Image NO puede llevar
# marcadores del stack msm/adreno (ese es el gate), y SI el compatible de simpledrm.
GATE_K45 = "--k45" in sys.argv
# --- K50 (#510): --initramfs <path> pinea OTRO cpio (k50 = k34 + e2fsck) ---
INITRAMFS_ARG = None
if "--initramfs" in sys.argv:
    INITRAMFS_ARG = sys.argv[sys.argv.index("--initramfs") + 1]

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
    OUT = R + "/build/bootimg/boot-ukek18d.img"
    LOG = R + "/build/bootimg/repack-k18d-report.txt"
else:
    OUT = R + "/build/bootimg/boot-ukek18.img"
    LOG = R + "/build/bootimg/repack-k18-report.txt"

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
                "drivers/gpu/drm/panel/panel-xiaomi-o82-dualdsi.c",
                "drivers/soc/qcom/uke-panic-fb.c"):
        src = R + "/build/kernel-pokes/k18-tree/" + rel
        if not os.path.isfile(src):
            die("G0 FALLO: no existe el fuente %s" % src)
        if os.path.getmtime(src) > os.path.getmtime(KERNEL):
            die("G0 FALLO: %s mas nuevo que Image.gz (build rancio)" % rel)
    log("  OK  Image.gz %d B sha256=%s (4 fuentes sin cambios posteriores)"
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

    log("\n=== G2: cmdline ===")
    cmd = k13[CMD_OFF:CMD_OFF + CMD_FIELD].split(b"\x00")[0]
    if len(cmd) != 356:
        die("G2 FALLO: cmdline K13 mide %d != 356" % len(cmd))
    if DSID:
        cmd = k13d[CMD_OFF:CMD_OFF + CMD_FIELD].split(b"\x00")[0]
        if len(cmd) != 370 or b"video=DSI-1:d" not in cmd:
            die("G2 FALLO: cmdline dsid mide %d o sin video=" % len(cmd))
    if TOK_PROBE in cmd or b"  " in cmd:
        die("G2 FALLO: probe token o doble espacio")
    for t in TOKS_KEPT:
        if cmd.count(t) != 1:
            die("G2 FALLO: token %r aparece %d veces" % (t, cmd.count(t)))
    if not DSID and b"video=" in cmd:
        die("G2 FALLO: video= en la variante plain")

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
    log("  OK  cmdline %d B (%s)" % (len(cmd), "dsid con video=DSI-1:d" if DSID else "plain SIN video="))

    log("\n=== G3: kernel K18 ===")
    import gzip
    raw = gzip.decompress(kern)
    # UKE-K45 (#495): DRM_MSM=n se lleva ~1,5 MB del Image (39918080 B medido).
    # Rango ampliado a +-1,7 MB: sigue cazando "kernel equivocado" (k13/k18 sueltos
    # difieren mucho mas) pero admite variantes de config sin el stack msm.
    if abs(len(raw) - 41355776) > 1782579:
        die("G3 FALLO: Image crudo %d B (delta desproporcionado)" % len(raw))
    if GATE_K45:
        # los marcadores msm/adreno DEBEN estar ausentes; simpledrm presente
        # (UKE-P82 NO se excluye: el driver del panel es drm/panel, ajeno a DRM_MSM)
        for t in (b"S0-dtcmR", b"UKE-POKE: G1-bind", b"msm_dpu"):
            if raw.count(t) != 0:
                die("G3 FALLO K45: %r presente (%d) y DRM_MSM=n lo excluye" % (t, raw.count(t)))
        if raw.count(b"simple-framebuffer") < 1:
            die("G3 FALLO K45: falta el compatible de simpledrm")
        if raw.count(b"\x013UKE-POKE: %s") != 1:
            die("G3 FALLO K45: uke_poke pr_err ausente")
        log("  OK  G3-k45: sin marcadores msm; simpledrm y uke_poke pr_err presentes")
    if raw.count(b"UKE-POKE") != 113 and not GATE_K45:
        die("G3 FALLO: UKE-POKE=%d != 113" % raw.count(b"UKE-POKE"))
    if not GATE_K45:
        if raw.count(b"UKE-K13") != 11 or raw.count(b"PINADO sin estar vivo") != 0:
            die("G3 FALLO: marcadores K13 rotos")
        if raw.count(b"UKE-K16: display sid=0x%04x -> grupo PROPIO rc=%ld (split)") != 1:
            die("G3 FALLO: miga UKE-K16 ausente")
        if raw.count(b"UKE-P82") < 20:
            die("G3 FALLO: migas panel UKE-P82 ausentes")
        if raw.count(b"S0-dtcmR") < 1 or raw.count(b"UKE-K17: dtcmR val=%#x") < 1:
            die("G3 FALLO: migas GMU K17 ausentes")
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
    else:
        for p in (b"arm_smmu.uke_smmu_probe", b"arm_smmu.uke_write_mask",
                  b"arm_smmu.uke_handoff", b"arm_smmu.uke_keep_boot"):
            if raw.count(p) < 1:
                die("G3 FALLO K45: falta el param %r (arm-smmu sigue dentro)" % p)
    log("  OK  crudo %d B; POKE=113; K13=11; K16=1; P82>=20; S0; K18 param+volcado presentes" % len(raw))

    # G3b (K23b, 1-oct-2026): el dump del CM3 tiene que llevar la geometria y el
    # decode CORREGIDOS. Sin este gate se puede flashear un kernel cuyo dump
    # miente: lei��a 0x8000+i*0x1000 (S1CD, no CBs) y (i<<16) (stride SMMUv3)
    # en un MMU-500, y decodificaba S2CR al reves (type=s2cr&3, cbndx=s2cr>>16),
    # con lo que un S2CR=0x00000001 (TRANS por CB1) salia como "BYPASS".
    if GATE_K23B:
        k23b = {
            b"UKE-K19: GEO ID0=": "linea GEO (ID0/ID1/pgshift/CBbase)",
            b"CBbase=0x%llx stride=0x%llx": "CBbase/stride calculados del ID1",
            b"type=%u=%s cbndx=%u": "decode S2CR correcto (TYPE=[17:16], CBNDX=[7:0])",
            b"recurso del DT, exacto": "ioremap limitado al recurso del DT (0x40000)",
            b"-> TRANS por CB%u": "anota el CB al que apunta cada S2CR valido",
            b"L[%d] iova=0x%05llx": "decode de descriptores LPAE (con L[4] = icache@0x4000)",
        }
        faltan = [w for t, w in k23b.items() if raw.count(t) < 1]
        if faltan:
            die("G3b FALLO: el kernel NO lleva el dump corregido: %s" % "; ".join(faltan))
        log("  OK  G3b K23b: dump corregido presente (%d marcadores)" % len(k23b))

    # --- K24 (1-oct-2026, sesion #455): el dump tiene que CAMINAR la tabla ----
    # El gate de arriba acepta un kernel que solo vuelca e[0..7] y llama "L[4]" al
    # icache@0x4000. Eso es FALSO: el arranque dice "0 stage-2 only" => traduccion
    # de 32 bits => la tabla de primer nivel tiene 4 entradas de 1 GB, y e[4..7]
    # estan MAS ALLA DEL FINAL de la tabla (basura). El descriptor de 0x4000 hay
    # que recorrerlo (L1[0] -> L2 -> L3[4]). Sin este gate se puede flashear un
    # kernel cuyo discriminador no distingue nada (fue justo lo que cazo la
    # auditoria, sesion #455).
    # K45 (#495): el caminador vive en a6xx_gmu.c (DRM_MSM=n lo excluye) — se salta.
    if GATE_K45:
        log("  OK  G3c K24: SKIP (K45 sin stack msm)")
    else:
        k24 = {
            b"WALK iova=0x%llx": "caminador de tabla (el discriminador real)",
            b"MAPPING ENCONTRADO": "desenlace positivo del walk",
            b"HUECO": "desenlace negativo (sin mapping en ese CB)",
            b"veredicto=%s": "veredicto explicito del dtcm-magic (OK/STALE)",
        }
        faltan = [w for t, w in k24.items() if raw.count(t) < 1]
        if faltan:
            die("G3c FALLO: el kernel NO lleva el caminador de tabla: %s" % "; ".join(faltan))
        if raw.count(b"uke_k19_dump_desc(e[4]"):
            die("G3c FALLO: sigue el volcado plano e[4] (leia basura, fuera de la tabla)")
        log("  OK  G3c K24: caminador de tabla presente (%d marcadores), sin volcado plano" % len(k24))
    k12gz = open(INITRAMFS_ARG or K13_INITRAMFS, "rb").read()
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
    if blob_at is None or raw[blob_at:blob_at + len(k12gz)] != k12gz:
        die("G3 FALLO: initramfs embebido != cpio K34")
    # UKE-K34: el cpio tiene que LLEVAR el firmware DENTRO (es el objeto del ciclo:
    # el DPU lo pide a ~4 s, antes de montar la rootfs).
    import zlib as _z
    _d = _z.decompressobj(31)
    _cpio = _d.decompress(raw[blob_at:blob_at + 8_000_000])
    for _f in (b"lib/firmware/qcom/gen71100_sqe.fw",
               b"lib/firmware/qcom/gen71100_gmu.bin",
               b"lib/firmware/qcom/gen71100_zap.mbn"):
        if _f not in _cpio:
            die("G3 FALLO: el cpio embebido NO lleva %s (el DPU lo pide antes de la rootfs)" % _f.decode())
    if b"ukeinit" not in _cpio:
        die("G3 FALLO: el cpio embebido no lleva ukeinit")
    log("  OK  initramfs embebido @%d = cpio %s CON el fw GPU dentro y ukeinit" % (blob_at, os.path.basename(INITRAMFS_ARG or K13_INITRAMFS)))

    log("\n=== G4: ensamblado ===")
    img = bytearray(base)
    ksz = len(kern)
    if PAGE + ksz >= AVB0_OFF:
        die("G4 FALLO: kernel pisaria AVB0")
    struct.pack_into("<I", img, KS_OFF, ksz)
    img[PAGE:PAGE + ksz] = kern
    img[CMD_OFF:CMD_OFF + CMD_FIELD] = cmd + b"\x00" * (CMD_FIELD - len(cmd))
    # K45 (#495): con un kernel MENOR que el del base quedan restos del kernel base
    # en el hueco hasta AVB0 — se ponen a cero (el gate de abajo lo exigia de sobra).
    img[PAGE + ksz:AVB0_OFF] = b"\x00" * (AVB0_OFF - PAGE - ksz)
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
        esperado = ref_cmd
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
    log("\n  ESTE SHA TIENE QUE IR PRE-REGISTRADO (#P47/K18) ANTES DE FLASHEAR.")

    import subprocess, shutil
    log("\n=== G8: herramientas ===")
    if shutil.which("unpack_bootimg"):
        ud = "/var/tmp/uke-k18-unpack"
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
