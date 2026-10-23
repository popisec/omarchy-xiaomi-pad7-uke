#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
patch-uke-smmu-pokes.py — instrumentacion para que el wedge de `apps-smmu` DEJE de ser mudo.

POR QUE
    El bloqueo del display es que `/soc/apps-smmu@15000000` no enlaza: su compatible es
    `qcom,qsmmu-v500`, que no esta ni en `arm_smmu_of_match` ni en la tabla de 21 filas de
    `qcom_smmu_bind`. Forzarlo con un dtbo (s251) WEDGEA: el probe de `arm-smmu` cuelga el bus.
    Y el wedge es mudo POR CONSTRUCCION, no por casualidad:
      - `ttyGS0` lo crea el propio gadget USB, que nace en el init
      - un `arch_initcall` (donde corre el probe de un SMMU built-in) cuelga ANTES de que exista
      - sin panic no hay pstore, y sin pstore no hay ramoops
    Medido en la tablet el 28-sep: 4 minutos sin gadget, sin red y con CERO lineas de consola; el
    ABL cae a fastboot con `slot-retry-count:b` a 0. El hermano midio exactamente lo mismo 6 veces
    (ledger #418/#431). O sea: 8 intentos y CERO informacion sobre DONDE se cuelga.
    Este parche no intenta arreglarlo todavia: intenta que la proxima vez HAYA DATO.

QUE HACE, tres cosas
    1. Quita `.suppress_bind_attrs = true` (arm-smmu.c:2362). Es lo que hace que
       `/sys/bus/platform/drivers/arm-smmu/bind` NO exista (verificado en la tablet: 264 drivers lo
       tienen, arm-smmu no). Sin ese atributo no hay forma de lanzar el probe a mano.
    2. Difiere el probe de ESTE SMMU una vez, devolviendo -EPROBE_DEFER. El mecanismo de deferred
       probe del kernel lo reintenta en `late_initcall_sync`, o sea con la consola ya viva. Asi:
        - si el probe pasa, el SMMU queda vivo sin haber arriesgado el arranque
        - si wedgea, wedgea TARDE y CON CONSOLA, y la ultima linea de dmesg dice donde
       Ningun otro SMMU se toca: el de la GPU (kgsl-smmu) sigue enlazando como siempre.
    3. Pan de migas (`pr_info`) antes de cada acceso MMIO del probe, para que la ultima linea
       impressa senale el acceso exacto y no solo la funcion.

COMO SE USA
    El retardo del reintento se controla con `deferred_probe_timeout=` en la cmdline, que va en la
    imagen de boot que se construya con este kernel. Con 30 s el reintento cae con la consola
    Durante el arranque normal el valor por defecto (10 s) tambien serviria, pero se pone
    explicito para que el experimento sea reproducible.

RIESGO
    Un parche de instrumentacion, no de funcionalidad: no cambia el resultado del probe, solo
    cuando se ejecuta y que se vea. El riesgo real es el MISMO que ya se acepto 8 veces: que el
    probe wedgee. La diferencia es que ahora wedgea con la consola encendida, que es el unico modo
    de avanzar.
"""
import os
import re
import sys
import subprocess

def _repo_root():
    """Raiz del repo: se sube hasta el directorio con .git, para que el script
    funcione recien clonado y no dependa de donde este el arbol."""
    d = os.path.dirname(os.path.abspath(__file__))
    while d != "/" and not os.path.isdir(os.path.join(d, ".git")):
        d = os.path.dirname(d)
    return d


R = _repo_root()


SRC = os.path.expanduser("~/gpu-work/palawan-linux/drivers/iommu/arm/arm-smmu")

# El nodo que interesa, por direccion de registro (estable y unico; el compatible lo cambia el dtbo)
APPS_BASE = 0x15000000
MARCA = "UKE-POKE"


def leer(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def escribir(path, txt):
    with open(path, "w", encoding="utf-8") as f:
        f.write(txt)


def ok(msg):
    print("  OK  %s" % msg)


def die(msg, extra=""):
    print("\n*** %s ***" % msg)
    if extra:
        print(extra)
    sys.exit(1)


def una_vez(txt, ancla, insercion, msg, marca=None):
    """Inserta 'insercion' justo despues de 'ancla', una sola vez, guardando POR PARCHE.

    BUG REAL QUE TENIA ESTA FUNCION, que es la peor clase posible: hacia

        return txt.replace(ancla, ancla), True

    o sea, sustituia el ancla POR SI MISMA. Nunca recibio el texto que tenia que insertar, asi que
    el diferir -EPROBE_DEFER no se inserto NUNCA, y aun asi la primera vez informo
    "2. probe de apps-smmu diferido" porque devolvia hecho=True. Un parche que INFORMA un cambio que
    no hace, y que devuelve "hecho": el gate decia OK sobre un kernel al que le faltaba justo lo que
    hacia falta para que el probe no corriera en arch_initcall. Por eso la verificacion final lee el
    FICHERO y no se fia del informe de cambios.

    EL GUARDA TAMBIEN ES POR PARCHE, NO GLOBAL: con una sola cadena ("UKE-POKE") para los cuatro
    parches, al reejecutar las migas de pan hacian creer que el diferir ya estaba puesto.
    """
    if marca and marca in txt:
        print("  ya parcheado (%s): no toco" % msg)
        return txt, False
    if txt.count(ancla) != 1:
        die("ancla no unica para %s (%d apariciones). NO APLICAR a mano; revisa el fichero."
            % (msg, txt.count(ancla)))
    if insercion in txt:
        die("la insercion de %s YA esta en el fichero pero la marca %r no aparece: estado "
            "imposible. NO APLICAR; mira el fichero a mano." % (msg, marca))
    return txt.replace(ancla, ancla + insercion), True


def main():
    arm = os.path.join(SRC, "arm-smmu.c")
    qcom = os.path.join(SRC, "arm-smmu-qcom.c")
    for p in (arm, qcom):
        if not os.path.isfile(p):
            die("no existe %s" % p)

    t_arm, t_qcom = leer(arm), leer(qcom)
    cambios = []

    # ---------- 1. quitar suppress_bind_attrs ----------
    viejo = "\t\t.pm\t\t\t= &arm_smmu_pm_ops,\n\t\t.suppress_bind_attrs    = true,\n"
    nuevo = ("\t\t.pm\t\t\t= &arm_smmu_pm_ops,\n"
             "\t\t/*\n"
             "\t\t * UKE (28-sep): se QUITA suppress_bind_attrs a proposito. Con el, este driver no\n"
             "\t\t * expone bind/unbind (medido: 264 drivers de plataforma los tienen, arm-smmu no),\n"
             "\t\t * y sin bind no hay forma de lanzar el probe de apps-smmu a mano, que es\n"
             "\t\t * justamente lo que hace falta para verlo fallar con la consola ya viva.\n"
             "\t\t */\n")
    # Idempotencia: se mira la MARCA, no la palabra "suppress_bind_attrs", porque el comentario que
    # inserta la menciona. Con la palabra, el parche no era idempotente y en la segunda pasada
    #abortaba. Un parche que no se puede volver a ejecutar sin limpiar el arbol es un parche que
    #algún dia te va a morder.
    if ".suppress_bind_attrs    = true" in t_arm:
        if t_arm.count(viejo) != 1:
            die("suppress_bind_attrs esta pero con otro formato; revisa arm-smmu.c a mano")
        t_arm = t_arm.replace(viejo, nuevo)
        cambios.append("1. quitado .suppress_bind_attrs (arm-smmu.c:2362)")
    else:
        cambios.append("1. .suppress_bind_attrs ya no estaba (hecho en una pasada anterior)")

    # ---------- 2. diferir el probe de apps-smmu una vez ----------
    # Se ancla en el inicio de arm_smmu_device_probe, que es .probe del platform_driver.
    ancla = "static int arm_smmu_device_probe(struct platform_device *pdev)\n{\n\tstruct resource *res;\n"
    # `dif` es SOLO el cuerpo a insertar: `una_vez` ya hace
    # `txt.replace(ancla, ancla + insercion)`. Si `dif` empezara por `ancla + ...`,
    # el ancla quedaria DUPLICADA ("function definition is not allowed here") y costo un ciclo.
    dif = (
        "\t/*\n"
        "\t * UKE (28-sep): el probe de apps-smmu wedgea el bus, y wedgea mudo porque ttyGS0 lo crea\n"
        "\t * el gadget USB del init, que todavia no existe en un arch_initcall. Sin panic no hay\n"
        "\t * pstore. Medido: 4 min sin una sola linea de consola, y luego el ABL cae a fastboot.\n"
        "\t *\n"
        "\t * Aqui NO se cambia lo que hace el probe: se cambia CUANDO. Se devuelve -EPROBE_DEFER\n"
        "\t * una sola vez, y el mecanismo de deferred probe del kernel lo reintenta en\n"
        "\t * late_initcall_sync, con la consola ya viva. Asi el wedge pasa a ser visible, y si el\n"
        "\t * probe funciona el SMMU queda vivo sin haber arriesgado el arranque.\n"
        "\t *\n"
        "\t * Solo para apps-smmu (base 0x%x). El de la GPU no se toca.\n"
        "\t */\n"
        "\t{\n"
        "\t\tstruct device *dev = &pdev->dev;\n"
        "\t\tstruct device_node *np = dev->of_node;\n"
        "\t\tint base = -1, size = -1;\n"
        "\n"
        "\t\tif (np && of_property_read_u32(np, \"reg\", &base) == 0 &&\n"
        "\t\t    of_property_read_u32_index(np, \"reg\", 1, &size) == 0 &&\n"
        "\t\t    (u32)base == 0x%x && (u32)size == 0x100000) {\n"
        "\t\t\tstatic bool ya_diferido;\n"
        "\n"
        "\t\t\tif (!ya_diferido) {\n"
        "\t\t\t\tya_diferido = true;\n"
        "\t\t\t\tpr_info(\"UKE-POKE: apps-smmu @%%p base=0x%%x: primer probe DIFFERido \"\n"
        "\t\t\t\t\t\"para que el reintento caiga con la consola viva\\n\",\n"
        "\t\t\t\t\tdev, (unsigned int)base);\n"
        "\t\t\t\treturn -EPROBE_DEFER;\n"
        "\t\t\t}\n"
        "\t\t\tpr_info(\"UKE-POKE: apps-smmu: REINTENTO del probe, consola ya viva. \"\n"
        "\t\t\t\t\"Lo que viene a continuación es el probe de verdad.\\n\");\n"
        "\t\t}\n"
        "\t}\n"
    ) % (APPS_BASE, APPS_BASE)
    t_arm, hecho = una_vez(t_arm, ancla, dif, "diferir el probe",
                          marca="UKE-POKE: apps-smmu @")
    if hecho:
        cambios.append("2. probe de apps-smmu diferido una vez (-EPROBE_DEFER)")

    # ---------- 3a. migas en arm_smmu_device_probe, POR NUMERO DE LINEA ----------
    # Se hace por indice y no por texto porque `arm_smmu_device_reset(smmu);` aparece DOS veces
    # (arm_smmu_device_probe y arm_smmu_device_remove) y un replace por subcadena meteria la miga en
    # los dos sitios, o en el equivocado. El gate de "ancla unica" existe justo para cazar esto, y
    # cazo un bug del propio parche: la primera version ancla ahi y es ambigua.
    if "UKE-POKE: apps-smmu: ->" not in t_arm:
        lineas = t_arm.split("\n")
        objetivos = []
        for i, x in enumerate(lineas):
            if x == "\terr = arm_smmu_device_cfg_probe(smmu);":
                objetivos.append((i, 'pr_info("UKE-POKE: apps-smmu: -> arm_smmu_device_cfg_probe '
                                      '(lectura IDR0/1/2 y PIDR; y qcom_smmu_cfg_probe ESCRIBE el '
                                      'S2CR del ultimo grupo y lo relee, que es el test del bypass '
                                      'quirk)\\n");'))
            elif x == "\tarm_smmu_device_reset(smmu);" and i > 0 \
                    and "rmr_install_bypass_smr" in lineas[i - 2]:
                objetivos.append((i, 'pr_info("UKE-POKE: apps-smmu: -> arm_smmu_device_reset '
                                      '(SMR/S2CR x%u, CBAR/SCTLR/FSR x%u, TLBIALLH, RMW de sCR0, y '
                                      'arm_mmu500_reset con CB_ACTLR si '
                                      'CONFIG_ARM_SMMU_MMU_500_CPRE_ERRATA)\\n", '
                                      'smmu->num_mapping_groups, smmu->num_context_banks);'))
        if len(objetivos) != 2:
            die("esperaba 2 anclas para las migas y encontré %d. Revisa arm-smmu.c a mano; el "
                "arbol puede haber cambiado." % len(objetivos))
        for i, migas in sorted(objetivos, reverse=True):
            lineas.insert(i, "\t" + migas)
            cambios.append("3. miga antes de " + lineas[i + 1].strip()[:52])
        t_arm = "\n".join(lineas)

    # ---------- 3b. migas en el reset de MMU-500 (arm-smmu-impl.c) ----------
    # ---------- 3b. migas en el reset de MMU-500 (arm-smmu-impl.c) ----------
    # El guarda es POR MIGA (la frase identificativa "-> arm_mmu500_reset"), no una comprobacion
    # global: la version anterior miraba solo si el ancla existia, que es SIEMPRE cierto, asi que
    # cada re-ejecucion anadia OTRA copia (el fuente llego a tener 8 lineas pr_info duplicadas).
    impl = os.path.join(os.path.dirname(arm), "arm-smmu-impl.c")
    t_impl = leer(impl)
    miga_impl = ("\tpr_info(\"UKE-POKE: apps-smmu: -> arm_mmu500_reset: lectura ID7 y RMW de sACR\"\n"
                 "\t\t\"(CACHE_LOCK, SMTNMB, S2CRB_TLBEN)\\n\");\n")
    a2 = "\treg = arm_smmu_gr0_read(smmu, ARM_SMMU_GR0_sACR);\n"
    if "-> arm_mmu500_reset" in t_impl:
        print("  ya parcheado (miga de arm_mmu500_reset): no toco")
    elif t_impl.count(a2) != 1:
        die("ancla no unica para la miga de arm_mmu500_reset (%d apariciones). NO APLICAR a mano; "
            "revisa el fichero." % t_impl.count(a2))
    else:
        t_impl = t_impl.replace(a2, miga_impl + a2)
        cambios.append("3. miga antes de arm_mmu500_reset (arm-smmu-impl.c)")

    # Se escribe SOLO si cambio algo: reescribir sin cambios bumpa el mtime y el gate de
    # frescura del reempaquetador (G0) abortaria tras una pasada no-op. (impl ya lo hacia asi.)
    if t_arm != leer(arm):
        escribir(arm, t_arm)
    if t_qcom != leer(qcom):
        escribir(qcom, t_qcom)
    if t_impl != leer(impl):
        escribir(impl, t_impl)

    # ---------- VERIFICACION FINAL: los cambios tienen que ESTAR, no solo quedarinformedos ----
    # Esto es lo que faltaba: el script informaba de lo que creia haber hecho y no comprobaba que
    # estuviera. Un informe de cambios no es una asercion.
    print("\n=== verificacion final (no confio en el informe de cambios) ===")
    faltan = []
    tf = leer(arm)
    ti = leer(impl)
    if ".suppress_bind_attrs    = true" in tf:
        faltan.append("1. .suppress_bind_attrs sigue puesto")
    else:
        ok("1. .suppress_bind_attrs quitado")
    if "UKE-POKE: apps-smmu @" in tf:
        ok("2. el diferir -EPROBE_DEFER esta en el fuente")
    else:
        faltan.append("2. el diferir NO esta: sin el el probe corre en arch_initcall y wedgea "
                      "mudo, y este kernel no serviria para NADA")
    # 2b. Asercion CAPAZ DE FALLAR ante el bug real (costo un ciclo de flash): el template leia
    # size con of_property_read_u32, que lee SIEMPRE el elemento 0, o sea size==base==0x15000000
    # y la condicion era SIEMPRE falsa. OJO: se mira el TEXTO DEL SCRIPT (el template `dif` que
    # es lo que se genera), NO el fuente del arbol: arm-smmu.c tiene un COMENTARIO que documenta
    # el bug viejo y contiene esa misma cadena, asi que mirar el fuente daria un falso positivo.
    if "of_property_read_u32_index(np, \"reg\", 1, &size)" not in dif:
        faltan.append("2b. el diferir usa read_u32 para size: la condicion es siempre falsa "
                      "(size==base); verificado contra reg=<0x15000000 0x100000>")
    else:
        ok("2b. el diferir lee size con read_u32_index(..., 1) (el template, no el comentario)")
    for frase, que in (("-> arm_smmu_device_cfg_probe", "miga de cfg_probe"),
                       ("-> arm_smmu_device_reset", "miga de device_reset")):
        if frase in tf:
            ok("3. %s presente" % que)
        else:
            faltan.append("3. falta la %s" % que)
    if "UKE-POKE" in ti:
        ok("3. miga dentro de arm_mmu500_reset presente")
    else:
        faltan.append("3. falta la miga de arm_mmu500_reset")
    if faltan:
        die("FALTAN %d de los cambios:\n        - %s" % (len(faltan), "\n        - ".join(faltan)))

    # ---------- GATE QUE FALTABA: QUE COMPILE ----------
    # Las comprobaciones de arriba son de texto. Un fichero con corchetes descuadrados las pasa
    # todas (las frases estan) y revienta al compilar con "function definition is not allowed
    # here". Pasó aqui: el ancla quedo duplicada y el kernel que se empaqueto no compilaba. Lo unico
    # que de verdad dice si el parche sirve es el compilador.
    print("\n=== gate final: que compile ===")
    O = os.path.join(R, "build/kernel-pokes")
    TREE = os.path.expanduser("~/gpu-work/palawan-linux")
    if not os.path.isdir(O):
        die("sin arbol de build en %s: sin compilacion no se sabe si el parche sirve. "
            "NO SEGUIR." % O)
    for obj, src in (("drivers/iommu/arm/arm-smmu/arm-smmu.o",
                      "drivers/iommu/arm/arm-smmu/arm-smmu.c"),
                     ("drivers/iommu/arm/arm-smmu/arm-smmu-impl.o",
                      "drivers/iommu/arm/arm-smmu/arm-smmu-impl.c")):
        r = subprocess.run("make -C %s LLVM=1 ARCH=arm64 O=%s -j8 %s 2>&1" % (TREE, O, obj),
                           shell=True, capture_output=True, text=True)
        if r.returncode != 0 or "error:" in r.stdout:
            log = r.stdout[-2500:]
            die("GATE DE COMPILACION FALLO (%s, rc=%d). El parche no sirve:\n%s"
                % (obj, r.returncode, log))
        ok("%s compila" % obj)
        o_path = os.path.join(O, obj)
        c_path = os.path.join(TREE, src)
        if not os.path.isfile(o_path) or os.path.getmtime(o_path) < os.path.getmtime(c_path):
            die("el .o de %s no es mas nuevo que su .c: el build no reconstruyo. NO SEGUIR." % obj)
        ok("%s mas nuevo que su .c (frescura)" % obj)

    # ---------- GATE DE SIMULACION: la condicion con los valores reales del DT ----------
    # No basta con creer que read_u32_index arregla la condicion: se simula en python con el
    # reg real de apps-smmu (<0x15000000 0x100000 0x151fe000 0x40>, medido descompilando
    # base-dtb.img de ramaa/s21/dtbo-gpu con dtc). Con read_u32_index la condicion da True;
    # con la version buggy (read_u32 para size) da False. Si la simulacion no discrimina asi,
    # los valores supuestos del DT estan mal y el gate no vale nada.
    print("\n=== gate de simulacion: la condicion con el reg real ===")
    reg_apps = [0x15000000, 0x100000, 0x151fe000, 0x40]
    base = reg_apps[0]          # of_property_read_u32 lee SIEMPRE el elemento 0
    size_buggy = reg_apps[0]    # BUG: of_property_read_u32(np, "reg", &size) tambien lee el 0
    size_ok = reg_apps[1]       # FIX: of_property_read_u32_index(np, "reg", 1, &size)
    cond_buggy = (base == 0x15000000 and size_buggy == 0x100000)
    cond_ok = (base == 0x15000000 and size_ok == 0x100000)
    if cond_buggy:
        die("simulacion incoherente: la version buggy daria True. Revisa los valores del DT.")
    if not cond_ok:
        die("simulacion: la version con read_u32_index daria False con reg=%s. Revisa los "
            "valores del DT." % ([hex(x) for x in reg_apps]))
    ok("buggy da False, con _index da True: la condicion del template discrimina de verdad")

    if not cambios:
        die("no se aplico ningun cambio: revisar el parche")
    print("cambios aplicados:")
    for c in cambios:
        print("  - %s" % c)
    print()
    print("SIGUIENTE: hay que reconstruir (el .config de w1-out/build esta desfasado respecto al")
    print("arbol: aparecieron TEST_CLOCKSOURCE_WATCHDOG y TEST_OBJPOOL) y REEMPAQUETAR el kernel")
    print("con deferred_probe_timeout=30 en la cmdline. El dtbo va aparte (s251).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
