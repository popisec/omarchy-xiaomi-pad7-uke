#!/usr/bin/env python3
"""bcb-clean-8192.py — genera el BCB limpio de 8192 B (F0 pasos 3 y 6).

LA TRAMPA (F0, 27-sep-2026). En ~/gpu-work/ hay un `bcb-clean.bin` de 2048 B de
ceros que NINGÚN script usa. La imagen de limpieza que el proyecto declara es de
8192 B de ceros (B §4.5: "misc.img son 8192 B de ceros"). Flashear el fichero de
2048 B escribiría solo los primeros 2 KiB y dejaría 6 KiB de BCB viejo intacto
(8192 - 2048 = 6144): exactamente el fallo que F0 viene a arreglar
(`command = "reboot-bootloader"` => el próximo reinicio puede caer a fastboot,
y en fastboot la tablet NO CARGA), pero con la falsa sensación de haberlo
arreglado. Por eso 2048 B es PEOR que no hacer nada: el "no hacer nada" al
menos no miente en el ledger.

QUÉ HACE ESTE SCRIPT Y QUÉ NO. Genera 8192 bytes de ceros, les pasa tres gates
(tamaño exacto, todo ceros, command[0:32] en ceros) más un cuarto gate que lee
el tamaño que EL PLAN declara para `misc` (no de memoria: del propio
F-plan-por-fases.md) y avisa si no es 8192. Imprime el sha para pre-registrarlo
en el ledger ANTES de escribir nada. NO flashea: el flash es el paso 6 de F0 y
va con su fila de ledger, su batería >= 3700 mV y su relectura de 4 KiB.

Uso:
    python3 build/gates/bcb-clean-8192.py [salida]
    # salida por defecto: build/gates/misc-zeros-8192.img
"""
import hashlib
import re
import sys
from pathlib import Path

EXPECTED = 8192  # B §4.5 + F0: la imagen de limpieza son 8192 B de ceros

# Patrones NORMATIVOS: frases del plan que declaran el tamaño CORRECTO de la
# imagen de limpieza (no las que describen el artefacto-trampa ni las que
# describen el residuo que quedaría). Cada match TIENE que dar 8192.
NORMATIVE = [
    re.compile(r"[Rr]egenerar\w* a (\d+)\s*B\b"),          # "Regenerar a 8192 B"
    re.compile(r"son \*{0,2}(\d+)\s*B\b"),                 # "misc son **8192 B**"
    re.compile(r"fichero de (\d+)\s*B\b"),                 # "el fichero de 8192 B"
    re.compile(r"[Ll]impia\w* [^.\n]*?(\d+)\s*B\b"),       # "Limpia misc a ceros (8192 B)"
    re.compile(r"ceros[^.\n]{0,80}?(\d+)\s*B\b"),          # "8192 B de ceros"
    re.compile(r"stat [^#\n]*#\s*→\s*(\d+)\b"),            # "stat ... # → 8192"
]
# Menciones de la TRAMPA (informativas: confirman que el plan la conoce).
TRAP = re.compile(r"bcb-clean\.bin|2048|6\s*KB?", re.IGNORECASE)


def plan_declared_sizes(plan_text):
    """Extrae la sección F0 del plan y devuelve (normativos, menciones_trampa).

    Falla CERRADO (excepción) si no encuentra la sección o si no encuentra
    ninguna declaración normativa: un gate que no encuentra su ancla no puede
    dar verde en silencio (lección H2 de la auditoría del 28-sep: un gate que
    no puede fallar no es un gate).
    """
    m = re.search(r"^### F0\b.*?(?=^### F1a?\b|\Z)", plan_text,
                  re.MULTILINE | re.DOTALL)
    if not m:
        raise SystemExit("GATE PLAN: no se encontró la sección F0 en el plan; "
                         "el supuesto queda sin ancla. ABORTO.")
    f0 = m.group(0)
    normative = []
    for line in f0.splitlines():
        if "bcb-clean.bin" in line:
            continue  # describe el artefacto-trampa, no el tamaño correcto
        for pat in NORMATIVE:
            normative += [int(x) for x in pat.findall(line)]
    trap_mentions = sum(1 for line in f0.splitlines() if TRAP.search(line)
                        and ("misc" in line.lower() or "bcb" in line.lower()))
    if not normative:
        raise SystemExit("GATE PLAN: F0 ya no declara ningún tamaño para la "
                         "imagen de misc; el supuesto queda sin ancla. ABORTO.")
    return normative, trap_mentions


def check_normative(normative):
    """Gate: todo tamaño normativo tiene que ser 8192.

    Si el plan declara otra cosa, el supuesto del que depende todo el gate es
    falso: AVISO explícito y ABORTO, no verde.
    """
    bad = [n for n in normative if n != EXPECTED]
    if bad:
        raise SystemExit(
            f"AVISO: el plan declara para misc un tamaño distinto de 8192: "
            f"{sorted(set(bad))}. El supuesto del gate es FALSO; no se genera "
            f"nada hasta que un humano resuelva la discrepancia. ABORTO.")


def main(argv):
    root = Path(__file__).resolve().parents[2]
    plan = root / "F-plan-por-fases.md"
    if not plan.is_file():
        raise SystemExit(f"GATE PLAN: no existe {plan}. ABORTO.")
    normative, trap_mentions = plan_declared_sizes(
        plan.read_text(encoding="utf-8"))
    print(f"plan: declaraciones normativas de tamaño en F0: {normative} "
          f"(líneas que mencionan la trampa: {trap_mentions})")
    check_normative(normative)

    out = Path(argv[1]) if len(argv) > 1 else root / "build/gates/misc-zeros-8192.img"
    data = b"\x00" * EXPECTED
    out.write_bytes(data)

    # GATES sobre el artefacto (todos con aserción: si fallan, excepción).
    raw = out.read_bytes()
    assert len(raw) == EXPECTED, \
        f"GATE TAMAÑO: {len(raw)} != {EXPECTED}"
    assert raw.strip(b"\x00") == b"", "GATE CEROS: hay bytes no nulos"
    assert raw[0:32] == b"\x00" * 32, \
        "GATE command[0:32]: el criterio de hecho de F0 no se cumple"
    sha = hashlib.sha256(raw).hexdigest()

    print(f"OK  tamaño exacto: {len(raw)} B (NO 2048: la trampa)")
    print(f"OK  todo ceros: {len(raw)} B verificados")
    print(f"OK  command[0:32] en ceros (criterio de hecho de F0 paso 6)")
    print(f"artefacto: {out}")
    print(f"sha256: {sha}")
    print(f"Pre-registra en el ledger ANTES de flashear: misc-zeros sha {sha}")
    print("NO flasheado. El flash es F0 paso 6, con relectura de 4 KiB.")


if __name__ == "__main__":
    main(sys.argv)
