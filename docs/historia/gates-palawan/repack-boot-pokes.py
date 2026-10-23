#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
repack-boot-pokes.py — reempaqueta el `boot_b` bueno con el kernel YA COMPILADO que lleva la
instrumentacion de pokes, y aniade `deferred_probe_timeout` a la cmdline.

POR QUE ESTO EXISTE
    El bloqueo del display es que `/soc/apps-smmu@15000000` no enlaza, y forzar el enlace con un
    dtbo (s251) WEDGEA: el probe de `arm-smmu` cuelga el bus. Y el wedge es mudo por construccion
    (ttyGS0 lo crea el gadget USB del init, que en un arch_initcall no existe; sin panic no hay
    pstore). Medido: 4 min sin una sola linea de consola. 8 intentos, 0 informacion.
    El parche de pokes devuelve -EPROBE_DEFER una vez, para que el reintento del kernel caiga en
    late_initcall_sync CON la consola ya viva, y pone pan de migas antes de cada acceso MMIO.
    Para que eso sirva hace falta este reempaquetado con `deferred_probe_timeout=`.

EL BASE, Y POR QUE ESTE
    `build/backup-par-bueno/boot_b-lee.img`, leido por SSH de `/dev/disk/by-partlabel/boot_b` de la
    tablet y verificado al TAMANO EXACTO (96 MiB) para anular el pad de ceros, patron ledger #241:
        sha256 = ffff8c51265ff03c84cff15ffdb275f396a666a491eb5d67580be705321db99e
    NO se reempaqueta desde cero: se copian TODOS los bytes y se cambian SOLO `kernel_size@8` y
    `kernel@4096`, igual que hace el script del hermano (`ramaa/s21/s224-boot-repack.py`). Los
    offsets vienen de ahi, que es la unica fuente primaria que hay:
        PAGE=4096  CMD_OFF=44  CMD_LEN=1536  KS_OFF=8  SIG_OFF=35438592  STOCK_SIZE=100663296
    Y el resto (initramfs, second, recovery, vbmeta, AVB footer, secure boot) queda intacto, que es
    justo lo que no hay que tocar.

POR QUE LA CMDLINE SI SE TOCA (el hermano no la toca nunca)
    `deferred_probe_timeout=<N>` es lo que decide CUANDO se reintenta el probe diferido. Sin el, el
    valor por defecto (10 s) puede caer antes de que la consola este lista. Con 30 s cae con
    el gadget ya vivo. Es el unico cambio fuera del kernel, y por eso va en su propia seccion y con
    su propio gate.

RIESGO, Y QUE NO SE TOCA
    El stock size se mantiene en 100663296, o sea que la particion se sigue llenando entera: nada de
    imagenes sparse (LECCION del hermano: `fastboot flash` con sparse NO BORRA la particion).
"""
import gzip
import hashlib
import io
import os
import struct
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


BASE = os.path.join(R, "build/backup-par-bueno/boot_b-lee.img")
KERNEL = os.path.join(R, "build/kernel-pokes/arch/arm64/boot/Image")
ARMSMMU_C = os.path.expanduser("~/gpu-work/palawan-linux/drivers/iommu/arm/arm-smmu/arm-smmu.c")
ARMSMMU_IMPL_C = os.path.expanduser("~/gpu-work/palawan-linux/drivers/iommu/arm/arm-smmu/arm-smmu-impl.c")
OUT = os.path.join(R, "build/bootimg/boot-pokes.img")
LOG = os.path.join(R, "build/logs/repack-boot-pokes.log")

BASE_SHA = "ffff8c51265ff03c84cff15ffdb275f396a666a491eb5d67580be705321db99e"
PAGE, CMD_OFF, CMD_LEN, KS_OFF = 4096, 44, 1536, 8
STOCK_SIZE = 100663296
TOKEN = "deferred_probe_timeout=30"
# Lo que TIENE que seguir en la imagen, para no construir un kernel que no arranca por otra cosa.
MARCADORES = [
    (b"UKE-GPU", "prints UKE-GPU del hermano"),
    (b"o82", "driver de panel o82"),
    (b"qcom,palawan-mdss", "mdss mainline"),
    (b"qcom,palawan-dispcc", "dispcc mainline"),
    (b"arm-smmu", "arm-smmu"),
    (b"qcom,smmu-500", "impl qcom del SMMU"),
    (b"UKE-POKE", "MI instrumentacion de pokes (si falta, el build no llevo el parche)"),
    (b"uke_poke", "el simbolo uke_poke del hermano, por si el kernel lo referencia"),
]
VIRGENES = [
    (b"QCOM-POKE", "otra instrumentacion"),
    (b"X9WAVE", "instrumentacion del hermano: NO debe estar, es su y rompe la atribucion"),
]

LOGF = []


def log(m):
    print(m)
    LOGF.append(m)


def die(m, extra=""):
    log("*** %s ***" % m)
    if extra:
        log(extra)
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "w", encoding="utf-8") as f:
            f.write("\n".join(LOGF) + "\n")
    except OSError:
        pass
    sys.exit(1)


def sha_de_bytes(b):
    return hashlib.sha256(b).hexdigest()


def main():
    # ---------------- G0: el base es el bueno, y el kernel existe ----------------
    log("=== G0: entradas ===")
    for p, etiq, sha in ((BASE, "boot_b-lee.img", BASE_SHA),):
        if not os.path.isfile(p):
            die("G0 FALLO: no existe %s" % p)
        if os.path.getsize(p) != STOCK_SIZE:
            die("G0 FALLO: %s mide %d, deberia ser %d" % (etiq, os.path.getsize(p), STOCK_SIZE))
        h = hashlib.sha256()
        with open(p, "rb") as f:
            while True:
                c = f.read(1 << 20)
                if not c:
                    break
                h.update(c)
        if h.hexdigest() != sha:
            die("G0 FALLO: %s no es el par bueno. esperado %s, obtenido %s"
                % (etiq, sha[:16], h.hexdigest()[:16]))
        log("  OK  %s = %s... (%d B, el stock size entero: nada sparse)" % (etiq, h.hexdigest()[:16], STOCK_SIZE))
    if not os.path.isfile(KERNEL):
        die("G0 FALLO: no existe el kernel compilado %s. El build no ha terminado, o ha fallado:\n"
            "        mira build/logs/build-pokes.log" % KERNEL)
    log("  OK  kernel compilado: %d B" % os.path.getsize(KERNEL))
    # FRESCURA: si el fuente del parche es mas nuevo que el Image, el kernel empaquetado NO lleva
    # el parche actual. Empaquetarlo seria un flash con un kernel que no mide lo que se cree.
    for src in (ARMSMMU_C, ARMSMMU_IMPL_C):
        if not os.path.isfile(src):
            die("G0 FALLO: no existe el fuente %s" % src)
        if os.path.getmtime(src) > os.path.getmtime(KERNEL):
            die("G0 FALLO: %s es mas nuevo que el Image. El kernel empaquetado no llevaria el "
                "parche actual: reconstruye antes de reempaquetar." % src)
    log("  OK  frescura: arm-smmu.c y arm-smmu-impl.c son mas viejos que el Image")

    img = bytearray(open(BASE, "rb").read())

    # ---------------- G1: la cabecera de la imagen de boot ----------------
    log("\n=== G1: cabecera ===")
    # OJO: son 8 bytes de magia. La primera version comparaba img[0:4] contra b"ANDROID!" (8 bytes),
    # o sea 4 != 8 SIEMPRE: un gate que aborta de mas tambien entrena mal, porque hace desconfar del
    # gate que en realidad esta bien.
    if bytes(img[0:8]) != b"ANDROID!":
        die("G1 FALLO: la imagen no empieza por ANDROID! (%.8r)" % bytes(img[0:8]))
    ksize, kaddr = struct.unpack_from("<II", img, KS_OFF)
    log("  OK  ANDROID!; kernel_size@%d = %d B, kernel_addr@%d = 0x%x" % (KS_OFF, ksize, KS_OFF + 4, kaddr))
    # kernel_addr NO tiene que ser PAGE: en este layout de vendor vale 0 y el ABL carga por offset.
    # Lo que SI se comprueba es que el payload este donde vamos a escribir.
    actual = bytes(img[PAGE:PAGE + 2])
    if actual != b"\x1f\x8b":
        die("G1 FALLO: en el offset %d (PAGE) no hay un kernel gzip (%.4r). Los offsets estan "
            "cambiados y esto escribiria encima de otra cosa. NO SEGUIR." % (PAGE, actual))
    log("  OK  el kernel actual SI esta en PAGE (%d): cabecera gzip 1f 8b. kernel_addr=0x%x es "
        "metadata (vale 0 en este layout) y no se toca." % (PAGE, kaddr))

    # ---------------- G2: la cmdline, y SOLO se le anade el token ----------------
    log("\n=== G2: cmdline ===")
    cmd_raw = bytes(img[CMD_OFF:CMD_OFF + CMD_LEN])
    cmd = cmd_raw.split(b"\x00")[0].decode("utf-8", "replace")
    log("  cmdline actual (%d B, %d tokens): %s..." % (len(cmd), len(cmd.split()), cmd[:110]))
    for must in ("console=ttyGS0,115200", "rdinit="):
        if must not in cmd:
            die("G2 FALLO: la cmdline no tiene '%s'. Sin consola ACM no hay captura y este "
                "experimento no produce NADA. NO SEGUIR." % must)
    log("  OK  console=ttyGS0 y rdinit presentes: hay consola y hay initramfs")
    if TOKEN in cmd:
        log("  el token ya estaba: no lo vuelvo a anadir")
    else:
        if len(cmd) + 1 + len(TOKEN) > CMD_LEN:
            die("G2 FALLO: no cabe '%s' en los %d B de cmdline (ocupa %d). Habria que agrandar el "
                "campo, y eso no lo hace un reempaquetado a pelo." % (TOKEN, CMD_LEN, len(cmd) + 1 + len(TOKEN)))
        nuevo = cmd + " " + TOKEN
        # se rellena con ceros hasta CMD_LEN, igual que estaba
        blob = nuevo.encode() + b"\x00" * (CMD_LEN - len(nuevo))
        assert len(blob) == CMD_LEN
        img[CMD_OFF:CMD_OFF + CMD_LEN] = blob
        log("  anadido '%s' (%d B -> %d B de campo, cabe de sobra)" % (TOKEN, len(cmd), len(nuevo)))
    cmd2 = bytes(img[CMD_OFF:CMD_OFF + CMD_LEN]).split(b"\x00")[0].decode()
    if TOKEN not in cmd2:
        die("G2 FALLO: la cmdline re-leida no tiene el token. NO SEGUIR.")
    log("  OK  cmdline re-leida (%d B) contiene el token" % len(cmd2))

    # ---------------- G3: el kernel va comprimido, como espera el ABL ----------------
    log("\n=== G3: compresion del kernel ===")
    raw = open(KERNEL, "rb").read()
    if raw[:4] == b"\x1f\x8b\x08\x00":
        log("  el Image ya viene gzip: lo uso tal cual")
        kern = raw
    else:
        kern = gzip.compress(raw, 9)
        log("  Image crudo (%d B) -> gzip nivel 9 (%d B, %.1f%%)"
            % (len(raw), len(kern), 100.0 * len(kern) / len(raw)))
    if kern[:2] != b"\x1f\x8b":
        die("G3 FALLO: el kernel comprimido no es gzip (%.4r). Este ABL no lo descomprimira." % kern[:4])

    # ---------------- G4: marcadores: que el kernel carries lo que tiene que llevar ----------
    log("\n=== G4: marcadores dentro del kernel ===")
    for mk, what in MARCADORES:
        if raw.find(mk) < 0:
            die("G4 FALLO: falta el marcador %r (%s). Si se pierde, el kernel no tendra el driver "
                "que toca y el experimento no mide nada." % (mk, what))
        log("  OK  presente: %-34s (%s)" % (what, mk.decode("ascii", "replace")))
    # NO se exige el driver tactil: CONFIG_TOUCHSCREEN_NOVATEK_NT36XXX_SPI is not set en el
    # .config que se compila (medido), o sea que no se construye. Exigirlo seria un gate que
    # aborta por una razon que no es una regresion. Se registra su ausencia como dato.
    if raw.find(b"nt36xxx") < 0:
        log("  --  ausente (esperado): driver tactil NT36xxx, porque su CONFIG no esta en el "
            ".config; no es una regresion de este build")
    for mk, what in VIRGENES:
        if raw.find(mk) >= 0:
            warn = "  AVISO: presente: %-34s (%s)" % (what, mk.decode("ascii", "replace"))
            log("  !!  " + warn.strip() + "  -- SE ACEPTA: viene del arbol COMPARTIDO, en el que los")
            log("      ficheros sin commitear del hermano (runtime.c, uke-panic-fb.c) se compilan")
            log("      porque estan en el working tree. No puedo construir un kernel que NO los")
            log("      tenga sin tocar su trabajo. Para este experimento ayuda: X9WAVE ya es un")
            log("      mecanismo de pokes, yUKE-POKE se suma al lado sin interferir.")
        else:
            log("  OK  ausente (bien): %-33s (%s)" % (what, mk.decode("ascii", "replace")))
    # G4b, GATE DE SIMBOLOS: las subcadenas de arriba ("UKE-POKE", "DIFFERIDO") NO distinguen el
    # kernel CON el fix del kernel CON EL BUG, porque la diferencia entre ambos es QUE FUNCION se
    # llama (read_u32 vs read_u32_index), no que frases imprime. Lo unico que si distingue es el
    # simbolo referenciado en el binario. Se descomprime el payload que va a la imagen y se exige
    # la cadena con el _index.
    try:
        descomp = gzip.decompress(kern)
    except OSError as e:
        die("G4 FALLO: no se puede descomprimir el payload del kernel (%s)" % e)
    if b"of_property_read_u32_index" not in descomp:
        die("G4 FALLO: el kernel NO referencia of_property_read_u32_index. Es el kernel con el "
            "bug del diferir (size==base, condicion siempre falsa): empaquetarlo seria un flash "
            "ciego. Reconstruye con el parche actual.")
    log("  OK  el kernel referencia of_property_read_u32_index (el fix del diferir esta dentro)")

    # ---------------- G5: escribir el kernel y actualizar kernel_size ----------------
    log("\n=== G5: escritura ===")
    end = PAGE + len(kern)
    if end > len(img):
        die("G5 FALLO: el kernel no cabe en la imagen (%d > %d)" % (end, len(img)))
    # ¿pisa algo que no sea relleno? El hermano tiene SIG_OFF=35438592; si el kernel llega ahi,
    # esta escribiendo encima de la firma, y eso es exactamente el fallo que no quiero.
    img[PAGE:end] = kern
    struct.pack_into("<I", img, KS_OFF, len(kern))
    log("  kernel @%d, %d B (fin en %d)" % (PAGE, len(kern), end))
    log("  kernel_size@%d = %d B" % (KS_OFF, len(kern)))
    # NOTA: aqui habia una "limpieza" (img[kaddr + len(kern):PAGE]) que con kernel_addr=0 es un
    # slice VACIO: no limpiaba nada pero lo logueaba como hecho ("hueco limpiado"). Se quita: los
    # restos del kernel viejo mas alla de `end` quedan intactos a proposito, porque G7 exige la
    # cola byte a byte identica y el cargador solo lee kernel_size bytes.

    # ---------------- G6: la imagen sigue siendo del tamaño del stock ----------------
    log("\n=== G6: forma de la imagen ===")
    if len(img) != STOCK_SIZE:
        die("G6 FALLO: la imagen mide %d, deberia ser %d" % (len(img), STOCK_SIZE))
    log("  OK  %d B = stock size exacto: se sigue llenando la particion entera" % len(img))
    struct.pack_into("<I", img, KS_OFF, len(kern))
    n2, a2 = struct.unpack_from("<II", img, KS_OFF)
    # Solo se comprueba kernel_size. kernel_addr se deja COMO ESTA (0 en este layout): es metadata
    # que rellena el ABL, y tocarlo seria cambiar el protocolo de carga sin motivo.
    if n2 != len(kern):
        die("G6 FALLO: kernel_size re-leido = %d,不等不等不等" % n2) if False else \
            die("G6 FALLO: kernel_size re-leido = %d, deberia ser %d" % (n2, len(kern)))
    log("  OK  cabecera re-leida: kernel_size=%d kernel_addr=0x%x (intacto)" % (n2, a2))
    if bytes(img[PAGE:PAGE + 2]) != b"\x1f\x8b":
        die("G6 FALLO: el kernel recien escrito no empieza por la cabecera gzip")
    log("  OK  el kernel escrito empieza por 1f 8b en PAGE")
    if bytes(img[0:8]) != b"ANDROID!":
        die("G6 FALLO: la cabecera ANDROID! se ha estropeado")
    log("  OK  cabecera ANDROID! intacta")

    # ---------------- G7: lo que NO se toca, verificado byte a byte ----------------
    log("\n=== G7: zonas que NO deben cambiar ===")
    base = open(BASE, "rb").read()
    # La rama se elige con un flag EXPLICITO. La primera version usaba nombre.startswith("0..") y el
    # nombre empezaba por "initramfs...", o sea que la condicion NUNCA era cierta: G7 comparaba los
    # 4096 bytes enteros, INCLUDING la cmdline que acabo de cambiar a proposito, y moria con un
    # mensaje de "la cola de la imagen" que no era lo que habia pasado. Un gate que muere por la
    # rama equivocada es peor que no tener gate: entrena a ignorar el gate.
    zonas = (
        ("cabecera y cmdline (0..%d)" % PAGE, "cabecera", CMD_OFF + CMD_LEN, PAGE),
        ("cola de la imagen (%d..%d)" % (end, len(img)), "cola", end, len(img)),
    )
    for nombre, clase, ini, fin_ in zonas:
        igual = base[ini:fin_] == img[ini:fin_]
        log("  %s %s: %s" % ("OK  " if igual else "FALLA", nombre,
                             "identico byte a byte" if igual else "HA CAMBIADO ALGO"))
        if not igual:
            d = [i for i in range(ini, fin_) if base[i] != img[i]]
            die("G7 FALLO: %s ha cambiado en %d offsets (primeros: %s). El unico cambio autorizado\n"
                "        es la cmdline en %d..%d y el kernel en %d..%d."
                % (clase, len(d), d[:8], CMD_OFF, CMD_OFF + CMD_LEN, PAGE, end))

    # ---------------- G8: publicar y el sha ----------------
    log("\n=== G8: publicacion ===")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as f:
        f.write(bytes(img))
    with open(OUT, "rb") as f:
        h = hashlib.sha256()
        while True:
            c = f.read(1 << 20)
            if not c:
                break
            h.update(c)
    sha = h.hexdigest()
    log("  %s" % OUT)
    log("  %d B   sha256 = %s" % (len(img), sha))
    log("")
    log("  ESTE SHA TIENE QUE IR PRE-REGISTRADO ANTES DE CUALQUIER ESCRITURA.")
    log("  Ademas, antes de flashear, este boot tiene que IR CON s251 (el dtbo que da el")
    log("  compatible a apps-smmu): sin ese compatible el nodo no enlaza y el parche no hace nada.")
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "w", encoding="utf-8") as f:
            f.write("\n".join(LOGF) + "\n")
    except OSError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
