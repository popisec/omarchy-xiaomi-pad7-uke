#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
repack-senemos.py — boot-uke-senemos-7.2.9.img (17-oct-2026): kernel del repo externo
MCC45TR/senemos-uke-kernel-mainline (HEAD 43e4036 "native54" = build 7.2.9-1.4054.3, perfil
nativo O82-42 de siete modos, 120 Hz preferido) reconstruido A MANO desde Linux 7.2.9 firmado
(build/kernel-pokes/senemos-7.2.9/reproducir-arbol.sh) + deltas propios
(build/kernel-pokes/senemos-7.2.9/deltas-omarchy.sh: panic diferido en uke-abl.c en vez de
cuelgue mudo; CMDLINE_FORCE fuera; initramfs k34-fw embebido; UFS/USB-gadget/MSM/O82/KTZ =y).
Informe: build/gates/revision/SENEMOS-PRUEBA-PREP-20261017.md.

Clon de repack-k52L76r.py: MISMA base v4 (shell s240-mem2g), MISMO initramfs k34-fw embebido en
el Image (CONFIG_INITRAMFS_SOURCE, ramdisk_size 0), kernel Image.gz @4096, cmdline en el campo
de cabecera (offset 44, 1536 B), AVB0/AVBf en sitio. Gates adaptados: no hay marcadores UKE-L7x;
en su lugar se exige en el binario la entrada nativa de senemos (overlays UFS/USB/display
embebidos byte a byte, selector O82-42, panic propio) y la ausencia de la cmdline forzada de Fedora.

V2 (17-oct-2026 noche): `--v2` empaqueta el build ouke2 (overlay USB sin usb-psy-name; ver
build/gates/revision/SENEMOS-V2-USB-20261017.md) -> build/bootimg/boot-uke-senemos-7.2.9-v2.img.
V3: `--v3` = ouke3 (ouke2 + CONFIG_SM_GPUCC_CLIFFS=y; GPU-SENEMOS-20261017.md) -> boot-uke-senemos-7.2.9-v3.img.
Sin `--v2` el script es el de la v1 (ouke1); tras el rebuild ouke2 ya no la reproduce (G0/G3 abortan por build rancio/banner:
la v1 se conserva ya construida en build/bootimg/boot-uke-senemos-7.2.9.img + senemos-build/ouke1-artefactos/).

REQUISITO DE ARRANQUE (fuera de esta imagen): dtbo del slot = dtbo STOCK (dtbo_b.img del backup
android-20261017, sha particion 27e61d21…). Con s288 el transform de uke-abl.c RECHAZA el grafo
(kgsl reg 0x3d9e000/0x2000 != 0x1000) -> panic diferido -> reinicio (antes: cuelgue mudo).
"""
import gzip
import hashlib
import os
import shutil
import struct
import subprocess
import sys
import zlib

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
SB4 = R + "/build/kernel-pokes/senemos-build"   # ouke1..4 (intacto)
SB = R + "/build/kernel-pokes/optim-ouke6/build7"  # "v7" = v6 + ouke7.config (build-v7.sh; mismo release ouke5)
SRC = R + "/build/kernel-pokes/optim-ouke6/linux-7.2.9"   # copia de ouke6 con 0045 + 0046 (+ config v7)
KERNEL = SB + "/arch/arm64/boot/Image.gz"
KCONFIG = SB + "/.config"
KCONFIG_REF = SB + "/config-senemos-ouke1"
INITRD = R + "/build/init/uke-k34-fw-k52b2-initramfs.cpio.gz"
INITRD_SHA = "ebc2de46ea89a4512be06b87e92d5dbb2f8aca8fe9a07304b697566551bf48bc"
GEN = SRC + "/native-generated"
KREL = "7.2.9-senemos.1.4054.3-ouke1"
OUT = R + "/build/bootimg/boot-uke-senemos-7.2.9.img"
LOG = R + "/build/bootimg/repack-senemos-7.2.9-report.txt"
V4 = "--v4" in sys.argv
V3 = "--v3" in sys.argv or V4
V2 = "--v2" in sys.argv or V3
if V2:
    KCONFIG_REF = SB + "/config-senemos-ouke2"
    GEN = SRC + "/native-generated-v2"
    KREL = "7.2.9-senemos.1.4054.3-ouke2"
    OUT = R + "/build/bootimg/boot-uke-senemos-7.2.9-v2.img"
    LOG = R + "/build/bootimg/repack-senemos-7.2.9-v2-report.txt"
if V3:
    # V3 (17-oct-2026 noche): ouke2 + CONFIG_SM_GPUCC_CLIFFS=y (GPU-SENEMOS-20261017.md). Mismos overlays que v2.
    KCONFIG_REF = SB + "/config-senemos-ouke3"
    KREL = "7.2.9-senemos.1.4054.3-ouke3"
    OUT = R + "/build/bootimg/boot-uke-senemos-7.2.9-v3.img"
    LOG = R + "/build/bootimg/repack-senemos-7.2.9-v3-report.txt"
if V4:
    # V4 (18-oct-2026): ouke3 + parches de kernel 0002+0004 (arm-smmu-qcom.c: SIDs de audio y FastRPC en la lista blanca; E2b). Misma config.
    KCONFIG_REF = SB + "/config-senemos-ouke4"
    KREL = "7.2.9-senemos.1.4054.3-ouke4"
    OUT = R + "/build/bootimg/boot-uke-senemos-7.2.9-v4.img"
    LOG = R + "/build/bootimg/repack-senemos-7.2.9-v4-report.txt"
# V6 (20-oct-2026, sesion de camara C5b): ouke5 + 0046 (SMMU camara), MISMA release ouke5. Derivado de repack-senemos-v5.py.
# V5 (19-oct-2026, sesion de camara C3): ouke4 + 0045 (allowlist rpmh: ldob20/ldoe6/ldoc3). Script derivado de repack-senemos.py --v4: siempre v5.
V4 = V3 = V2 = True
KCONFIG_REF = R + "/build/kernel-pokes/senemos-ouke5/build/config-senemos-ouke5"  # config BASE (v5/v6); v7 = base + ouke7.config
GEN = SRC + "/native-generated-v2"
KREL = "7.2.9-senemos.1.4054.3-ouke5"
OUT = R + "/build/bootimg/boot-uke-senemos-7.2.9-v7.img"
LOG = R + "/build/bootimg/repack-senemos-7.2.9-v7-report.txt"
TOOLCHAIN_SYMS = ("CONFIG_CC_VERSION_TEXT=", "CONFIG_CLANG_VERSION=", "CONFIG_AS_VERSION=", "CONFIG_LLD_VERSION=",
                  "CONFIG_RUSTC_VERSION=", "CONFIG_RUSTC_LLVM_VERSION=")
GEN_V1 = SRC + "/native-generated/ouke1"
if "--kernel" in sys.argv:
    KERNEL = sys.argv[sys.argv.index("--kernel") + 1]
if "--out" in sys.argv:
    o = sys.argv[sys.argv.index("--out") + 1]
    OUT = R + "/build/bootimg/" + o
    LOG = R + "/build/bootimg/repack-" + o[:-4] + "-report.txt"

PAGE, CMD_OFF, KS_OFF, RS_OFF = 4096, 44, 8, 12
CMD_FIELD = 1536
STOCK_SIZE = 100663296
AVB0_OFF, AVBF_OFF = 35438592, 100663232

# --- cmdline del boot.img (la de L76R adaptada; ver §cmdline del informe) ---------------
# Se QUITAN: memmap= (x86, sin efecto en arm64), arm_smmu.uke_* / msm.uke_* (params palawan
# inexistentes aqui), arm-smmu.disable_bypass=0 (senemos corre con bypass deshabilitado),
# fw_devlink=permissive (senemos corre con fw_devlink=on por defecto).
# Se ANADEN (de su CONFIG_CMDLINE forzada): msm.separate_gpu_kms=1, consoleblank=0,
# fbcon=font:TER16x32, regulator_ignore_unused, systemd.unit=multi-user.target (sin sddm: el
# GPU queda sin gpucc =m, y modetest necesita el maestro DRM libre); y fw_devlink.strict=0 para
# anular el fw_devlink.strict=1 que trae el /chosen/bootargs del DT vendor (con CMDLINE_FORCE
# senemos nunca lo veia).
CMDLINE = (b"rdinit=/ukeinit panic=10 console=tty0 fbcon=map:0 fbcon=font:TER16x32 consoleblank=0 "
           b"console=ttyGS0,115200 hung_task_timeout_secs=20 hung_task_panic=0 watchdog_thresh=10 "
           b"clk_ignore_unused pd_ignore_unused regulator_ignore_unused fw_devlink.strict=0 "
           b"msm.separate_gpu_kms=1 systemd.unit=multi-user.target printk.always_kmsg_dump=0 "
           b"plymouth.enable=0 iomem=relaxed cpuidle.governor=teo audit=0")
REQUIRED = (b"cpuidle.governor=teo", b"audit=0", b"rdinit=/ukeinit", b"panic=10", b"console=ttyGS0,115200", b"console=tty0",
            b"clk_ignore_unused", b"pd_ignore_unused", b"regulator_ignore_unused",
            b"msm.separate_gpu_kms=1", b"fw_devlink.strict=0", b"systemd.unit=multi-user.target")
# prefijos de TOKEN prohibidos (se comparan por token: "iomem=" no es "mem=")
FORBIDDEN = (b"root=", b"init=", b"mem=", b"memmap=", b"arm_smmu.", b"arm-smmu.", b"msm.uke_",
             b"video=", b"fw_devlink=", b"ignore_loglevel", b"rdinit=/usr/lib/systemd")
# Prefijo que el ABL antepone (medido): /chosen/bootargs del DT vendor + cmdline de vendor_boot.
# Nuestros tokens tienen que caer antes del byte 2048 (COMMAND_LINE_SIZE arm64): lo que pase de
# ahi lo trunca el kernel (hoy ya se corta la cola del ABL, inocuo).
DT_STOCK_BOOTARGS_LEN = 684 + 1   # fdtget merged-2-dtbo_b-0.dtb /chosen bootargs (+espacio)
VENDOR_CMDLINE_LEN = 154 + 1      # unpack_bootimg vendor_boot_a: "video=vfb:... bootconfig" (154 B)

LOGF = []


def log(m):
    print(m)
    LOGF.append(m)


def flush():
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, "w", encoding="utf-8") as f:
        f.write("\n".join(LOGF) + "\n")


def die(m):
    log("*** %s ***" % m)
    flush()
    sys.exit(1)


def sha(b):
    return hashlib.sha256(b).hexdigest()


def find_gz_cpio(raw):
    pos = raw.find(b"\x1f\x8b\x08")
    while pos != -1:
        d = zlib.decompressobj(31)
        try:
            dec = d.decompress(raw[pos:pos + 16_000_000])
        except Exception:
            dec = None
        if dec is not None and dec[:6] == b"070701":
            return pos, dec
        pos = raw.find(b"\x1f\x8b\x08", pos + 1)
    return None, None


def main():
    log("=== G0: entradas (senemos 7.2.9 .4054 + deltas omarchy) ===")
    for p, want, nombre in ((BASE, BASE_SHA, "shell s240-mem2g (v4)"), (INITRD, INITRD_SHA, "initramfs k34-fw")):
        if not os.path.isfile(p) or sha(open(p, "rb").read()) != want:
            die("G0 FALLO: %s ausente o con sha distinto (%s)" % (nombre, p))
    if not os.path.isfile(KERNEL):
        die("G0 FALLO: no existe %s (build incompleto)" % KERNEL)
    ALLOWED = ("CONFIG_NF_", "CONFIG_NFT_", "CONFIG_NETFILTER", "CONFIG_IP_NF_", "CONFIG_IP6_NF_", "CONFIG_IP_MULTIPLE", "CONFIG_IPV6_MULTIPLE",
               "CONFIG_IP_ADVANCED_ROUTER", "CONFIG_FIB_RULES", "CONFIG_ZRAM", "CONFIG_ZSMALLOC", "CONFIG_CRYPTO_ZSTD", "CONFIG_CRYPTO_LZ4",
               "CONFIG_CPU_IDLE_GOV_TEO", "CONFIG_ZSTD_", "CONFIG_DST_CACHE", "CONFIG_NET_", "CONFIG_LIBCRC", "CONFIG_IP_SET", "CONFIG_BRIDGE_NF",
               "CONFIG_CRYPTO_", "CONFIG_CRC", "CONFIG_REED", "CONFIG_XZ_", "CONFIG_DECOMPRESS")
    def _cfg(path):
        d = {}
        for l in open(path).read().splitlines():
            if l.startswith("CONFIG_") and "=" in l:
                k, v = l.split("=", 1); d[k] = v
            elif l.startswith("# CONFIG_") and l.endswith(" is not set"):
                d[l[2:-11]] = "n"
        return d
    cb, cn = _cfg(KCONFIG_REF), _cfg(KCONFIG)
    dif = sorted(k for k in set(cb) | set(cn) if cb.get(k, "n") != cn.get(k, "n") and not k.startswith(TOOLCHAIN_SYMS))
    mal = [k for k in dif if not k.startswith(ALLOWED)]
    if mal:
        die("G0 FALLO: la config v7 cambia simbolos fuera de la lista permitida: %s" % ", ".join(mal[:20]))
    for k in dif:
        if cb.get(k, "n") == "y" and cn.get(k, "n") != "y":
            die("G0 FALLO: %s pasa de =y a %s (un built-in no debe degradarse)" % (k, cn.get(k, "n")))
    if cn.get("CONFIG_PSI", "n") != "n" or cn.get("CONFIG_MODVERSIONS", "n") != "n":
        die("G0 FALLO: PSI o MODVERSIONS activos (v7 no debe tocarlos)")
    log("  OK  config v7 = base ouke5 + %d simbolos (todos en la lista permitida; ningun =y degradado; sin PSI)" % len(dif))
    kern = open(KERNEL, "rb").read()
    km = os.path.getmtime(KERNEL)
    for rel in ("arch/arm64/kernel/uke-abl.c", "arch/arm64/kernel/uke-abl-native.h",
                "arch/arm64/kernel/uke-native-display.h", "arch/arm64/kernel/uke-abl-overlays.h",
                "drivers/gpu/drm/panel/panel-xiaomi-o82.c", "drivers/gpu/drm/msm/dsi/dsi_host.c",
                "drivers/gpu/drm/msm/disp/dpu1/dpu_encoder_phys_vid.c", "drivers/clk/qcom/dispcc-sm8550.c"):
        if os.path.getmtime(SRC + "/" + rel) > km:
            die("G0 FALLO: %s mas nuevo que Image.gz (build rancio)" % rel)
    if V2:
        for rel in ("usb.dtbo", "ufs.dtbo", "display.dtbo"):
            if os.path.getmtime(GEN + "/" + rel) > km:
                die("G0 FALLO: %s (v2) mas nuevo que Image.gz (build rancio)" % rel)
        if V4:
            a = [l for l in open(SB4 + "/config-senemos-ouke3").read().splitlines() if not l.startswith(TOOLCHAIN_SYMS)]
            b = [l for l in open(KCONFIG_REF).read().splitlines() if not l.startswith(TOOLCHAIN_SYMS)]
            if a != b:
                die("G0 FALLO: config-senemos-ouke4 difiere de ouke3 (v4 no debe tocar la config)")
            for rel, needle in (("drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c", "sid == 0x401007"),
                                ("drivers/regulator/qcom-rpmh-regulator-uke.c", 'strcmp(aggr_vreg->resource_name, "ldoc3"))'),
                                ("drivers/iommu/arm/arm-smmu/arm-smmu-qcom.c", "sid == UKE_CAMERA_IFE_SID")):
                if needle not in open(SRC + "/" + rel).read() or os.path.getmtime(SRC + "/" + rel) > km:
                    die("G0 FALLO: %s sin los parches 0002+0004 aplicados o mas nuevo que Image.gz" % rel)
            log("  OK  v4: config = ouke3 (identica salvo version del toolchain); arm-smmu-qcom.c con 0002+0004 y no mas nuevo que Image.gz")
        elif V3:
            a = [l for l in open(SB + "/config-senemos-ouke2").read().splitlines() if not l.startswith(TOOLCHAIN_SYMS)]
            b = [l for l in open(KCONFIG_REF).read().splitlines() if not l.startswith(TOOLCHAIN_SYMS)]
            if [l for l in a if l not in b] != ["CONFIG_SM_GPUCC_CLIFFS=m"] or [l for l in b if l not in a] != ["CONFIG_SM_GPUCC_CLIFFS=y"]:
                die("G0 FALLO: config-senemos-ouke3 difiere de ouke2 en algo mas que SM_GPUCC_CLIFFS (sin contar la version del toolchain)")
            log("  OK  v3: config = ouke2 + CONFIG_SM_GPUCC_CLIFFS=y (unica diferencia funcional; toolchain clang 23.1.1 -> 23.1.3)")
        elif open(KCONFIG_REF, "rb").read() != open(SB + "/config-senemos-ouke1", "rb").read():
            die("G0 FALLO: config-senemos-ouke2 != config-senemos-ouke1 (v2 no debe tocar la config)")
    cfg = open(KCONFIG).read()
    for need in ("CONFIG_INITRAMFS_SOURCE=\"%s\"" % INITRD, "# CONFIG_CMDLINE_FORCE is not set",
                 "CONFIG_CMDLINE_FROM_BOOTLOADER=y", "CONFIG_QCOM_UKE_ABL_DT=y", "CONFIG_DRM_MSM=y",
                 "CONFIG_DRM_PANEL_XIAOMI_O82=y", "CONFIG_BACKLIGHT_KTZ8866=y", "CONFIG_SM_DISPCC_8550=y",
                 "CONFIG_SCSI_UFS_QCOM=y", "CONFIG_PHY_QCOM_QMP_UFS=y", "CONFIG_USB_DWC3=y",
                 "CONFIG_USB_DWC3_QCOM=y", "CONFIG_USB_CONFIGFS_ACM=y", "CONFIG_USB_CONFIGFS_NCM=y",
                 "CONFIG_USB_F_ACM=y", "CONFIG_USB_F_NCM=y", "CONFIG_EXT4_FS=y", "CONFIG_I2C_QCOM_GENI=y") + \
                (("CONFIG_SM_GPUCC_CLIFFS=y",) if V3 else ()):
        if need not in cfg.splitlines():
            die("G0 FALLO: config sin '%s'" % need)
    log("  OK  Image.gz %d B sha256=%s; config = %s (deltas verificados)" % (len(kern), sha(kern), os.path.basename(KCONFIG_REF)))
    base = open(BASE, "rb").read()

    log("\n=== G1: cabecera v4 de la base ===")
    if base[0:8] != b"ANDROID!" or struct.unpack_from("<I", base, 40)[0] != 4 or \
            struct.unpack_from("<I", base, 20)[0] != 1584:
        die("G1 FALLO: la base no es ANDROID! v4/1584")
    if struct.unpack_from("<I", base, RS_OFF)[0] != 0:
        die("G1 FALLO: la base ya lleva ramdisk")
    if base[PAGE:PAGE + 2] != b"\x1f\x8b":
        die("G1 FALLO: sin kernel gzip @4096")
    base_ksz = struct.unpack_from("<I", base, KS_OFF)[0]
    log("  OK  v4/1584; ramdisk 0; gzip @4096 (kernel base %d B)" % base_ksz)

    log("\n=== G2: cmdline (nueva, senemos; no hereda la cadena L57..L77) ===")
    cmd = CMDLINE
    if b"  " in cmd or cmd != cmd.strip():
        die("G2 FALLO: doble espacio o espacios en los extremos")
    for t in REQUIRED:
        if cmd.split().count(t) != 1:
            die("G2 FALLO: token %r aparece %d veces (debe ser 1)" % (t, cmd.split().count(t)))
    for tok in cmd.split():
        for t in FORBIDDEN:
            if tok.startswith(t):
                die("G2 FALLO: token prohibido %r (prefijo %r) en la cmdline" % (tok, t))
    if len(cmd) >= CMD_FIELD:
        die("G2 FALLO: cmdline %d B no cabe en el campo de 1536" % len(cmd))
    fin = DT_STOCK_BOOTARGS_LEN + VENDOR_CMDLINE_LEN + len(cmd)
    if fin >= 2048 - 64:
        die("G2 FALLO: nuestros tokens acabarian en el byte %d de /proc/cmdline (limite 2048)" % fin)
    log("  OK  cmdline %d B; con el prefijo ABL medido (DT stock %d + vendor_boot %d) acaba en ~%d < 2048"
        % (len(cmd), DT_STOCK_BOOTARGS_LEN, VENDOR_CMDLINE_LEN, fin))
    log("      %s" % cmd.decode())

    log("\n=== G3: contenido del kernel ===")
    try:
        raw = gzip.decompress(kern)
    except Exception as e:
        die("G3 FALLO: Image.gz no descomprime (%s)" % e)
    if raw[0x38:0x3C] != b"ARM\x64":
        die("G3 FALLO: sin magia ARM64 en el Image")
    img_size = struct.unpack_from("<Q", raw, 16)[0]
    log("  OK  Image crudo %d B (image_size cabecera %d B; L76R: 41724416 B)" % (len(raw), img_size))
    if len(raw) > 64 * 1024 * 1024 or img_size > 64 * 1024 * 1024:
        die("G3 FALLO: Image > 64 MiB (techo de carga del ABL sin fuente primaria: no arriesgar)")
    if ("Linux version %s " % KREL).encode() not in raw:
        die("G3 FALLO: banner 'Linux version %s' ausente" % KREL)
    bi = raw.find(("Linux version %s " % KREL).encode())
    if b"#7 " not in raw[bi:bi + 400]:
        die("G3 FALLO: el banner no lleva el numero de build #7 (¿build v6 o rancio?)")
    pos, dec = find_gz_cpio(raw)
    want = gzip.decompress(open(INITRD, "rb").read())
    if pos is None or dec != want:
        die("G3 FALLO: initramfs embebido != k34-fw (%s)" % ("no encontrado" if pos is None else "difiere"))
    if b"ukeinit" not in dec:
        die("G3 FALLO: el cpio embebido no trae /ukeinit")
    log("  OK  initramfs embebido @%d == uke-k34-fw-k52b2 (%d B cpio, trae /ukeinit)" % (pos, len(dec)))
    for nombre in ("ufs.dtbo", "usb.dtbo", "display.dtbo"):
        blob = open(GEN + "/" + nombre, "rb").read()
        if raw.count(blob) != 1:
            die("G3 FALLO: overlay %s no esta embebido exactamente 1 vez en el Image (x%d)" % (nombre, raw.count(blob)))
    log("  OK  overlays UFS/USB/display (O82-42 7 modos) embebidos byte a byte (x1 cada uno)")
    if V2:
        ub = open(GEN + "/usb.dtbo", "rb").read()
        u1 = open(GEN_V1 + "/usb.dtbo", "rb").read()
        if b"usb-psy-name" in ub or b"qcom-battmgr-usb" in ub:
            die("G3 FALLO: el overlay USB v2 aun lleva usb-psy-name / qcom-battmgr-usb")
        if b"peripheral" not in ub or b"qcom,sm7675-dwc3" not in ub or b"high-speed" not in ub:
            die("G3 FALLO: el overlay USB v2 perdio dr_mode peripheral / compatible / high-speed")
        if raw.count(u1) != 0:
            die("G3 FALLO: el overlay USB de ouke1 (con usb-psy-name) sigue embebido en el Image")
        if b"qcom-battmgr-usb" in raw:
            die("G3 FALLO: la cadena qcom-battmgr-usb sigue en el Image")
        # el unico cambio frente a ouke1 es el array usb: ufs y display identicos byte a byte
        for nombre in ("ufs.dtbo", "display.dtbo"):
            if open(GEN + "/" + nombre, "rb").read() != open(GEN_V1 + "/" + nombre, "rb").read():
                die("G3 FALLO: %s (v2) difiere del de ouke1 (el display debe quedar intacto)" % nombre)
        log("  OK  v2: usb.dtbo SIN usb-psy-name (dr_mode peripheral, high-speed, sm7675-dwc3 intactos); el de ouke1 ya no esta"
            " embebido; ufs/display identicos a ouke1 (display intacto)")
    marks = (b"msm_drm.dsi_display0=qcom,mdss_dsi_o82_42_02_0b_dualdsi_dsc_vid:",
             b"isolated native display graph prepared",
             b"UKE-SENEMOS: Uke ABL DT adaptation",
             b"Qualcomm Technologies, Inc. Uke based on SM8635",
             b"rdinit=/ukeinit panic=10 clk_ignore_unused pd_ignore_unused regulator_ignore_unused")
    for m in marks:
        if m not in raw:
            die("G3 FALLO: marcador %r ausente del Image" % m)
    if b"refusing incomplete board graph" not in raw:
        die("G3 FALLO: mensaje de rechazo de uke-abl.c ausente")
    for bad in (b"root=PARTLABEL=linux", b"rdinit=/usr/lib/systemd/systemd"):
        if bad in raw:
            die("G3 FALLO: la cmdline forzada de Fedora sigue en el Image (%r)" % bad)
    log("  OK  selector O82-42, entrada nativa, panic propio, modelo Uke y CONFIG_CMDLINE nuestra presentes;"
        " sin root=PARTLABEL=linux")

    log("\n=== G4: ensamblado ===")
    img = bytearray(base)
    ksz = len(kern)
    if PAGE + ksz >= AVB0_OFF:
        die("G4 FALLO: kernel (%d B) pisaria AVB0 @%d" % (ksz, AVB0_OFF))
    struct.pack_into("<I", img, KS_OFF, ksz)
    img[PAGE:PAGE + max(ksz, base_ksz)] = kern + b"\x00" * max(0, base_ksz - ksz)
    img[CMD_OFF:CMD_OFF + CMD_FIELD] = cmd + b"\x00" * (CMD_FIELD - len(cmd))
    if img[PAGE + ksz:AVB0_OFF] != b"\x00" * (AVB0_OFF - PAGE - ksz):
        die("G4 FALLO: hueco tras kernel no es ceros")
    log("  OK  kernel_size@8=%d; cmdline @44..%d; margen hasta AVB0 %d B" % (ksz, CMD_OFF + len(cmd), AVB0_OFF - PAGE - ksz))

    log("\n=== G5: forma/AVB ===")
    if bytes(img[0:8]) != b"ANDROID!" or bytes(img[AVB0_OFF:AVB0_OFF + 4]) != b"AVB0" or \
            bytes(img[AVBF_OFF:AVBF_OFF + 4]) != b"AVBf" or len(img) != STOCK_SIZE:
        die("G5 FALLO: forma")
    if struct.unpack_from("<I", img, RS_OFF)[0] != 0:
        die("G5 FALLO: ramdisk_size != 0")
    log("  OK  96 MiB; AVB0/AVBf en sitio; ramdisk 0")

    log("\n=== G6: deltas confinados vs s240 ===")
    zonas = [(KS_OFF, KS_OFF + 4), (CMD_OFF, CMD_OFF + CMD_FIELD), (PAGE, PAGE + max(ksz, base_ksz))]
    a = memoryview(base)
    b = memoryview(img)
    fuera = 0
    prev = 0
    for z0, z1 in sorted(zonas) + [(STOCK_SIZE, STOCK_SIZE)]:
        if a[prev:z0] != b[prev:z0]:
            fuera += sum(1 for i in range(prev, z0) if base[i] != img[i])
        prev = max(prev, z1)
    if fuera:
        die("G6 FALLO: %d bytes cambiados fuera de kernel_size/cmdline/kernel" % fuera)
    log("  OK  solo cambian kernel_size, campo cmdline y zona del kernel")

    log("\n=== G7: publicacion ===")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as f:
        f.write(bytes(img))
    out = open(OUT, "rb").read()
    if sha(out) != sha(bytes(img)):
        die("G7 FALLO: relectura")
    with open(OUT + ".sha256", "w") as f:
        f.write("%s  %s\n" % (sha(out), os.path.basename(OUT)))
    log("  %s" % OUT)
    log("  %d B   sha256 = %s" % (len(out), sha(out)))
    log("  ESTE SHA TIENE QUE IR PRE-REGISTRADO (ledger hermano) ANTES DE FLASHEAR, junto al dtbo STOCK.")

    log("\n=== G8: unpack_bootimg ===")
    if shutil.which("unpack_bootimg"):
        ud = "/var/tmp/uke-senemos-unpack"
        shutil.rmtree(ud, ignore_errors=True)
        r = subprocess.run(["unpack_bootimg", "--boot_img", OUT, "--out", ud], capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            die("G8 FALLO: unpack_bootimg rc=%d" % r.returncode)
        if sha(open(os.path.join(ud, "kernel"), "rb").read()) != sha(kern):
            die("G8 FALLO: kernel extraido != Image.gz")
        if ("command line args: %s" % cmd.decode()) not in r.stdout:
            die("G8 FALLO: unpack_bootimg no muestra la cmdline esperada")
        log("  OK  unpack_bootimg rc=0; kernel extraido == Image.gz; cmdline == la de G2")
    else:
        log("  G8 unpack_bootimg [NO DISPONIBLE]")
    flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
