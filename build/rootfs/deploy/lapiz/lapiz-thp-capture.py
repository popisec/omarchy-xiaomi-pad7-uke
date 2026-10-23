#!/usr/bin/env python3
"""lapiz-thp-capture.py — captura SOLO LECTURA de frames THP crudos del NT36532 (uke) para localizar el bloque del lapiz.

19-oct-2026. Reutiliza Spi/IRQ de uke-touchd.py (importlib). Lee el bloque de eventos COMPLETO (0x1FFF B tras el offset
0x100, como el SPI del vendor) en cada IRQ y lo vuelca a un fichero con marca de tiempo y fase. NO escribe en el chip.
Requiere que uke-touchd este en SIGSTOP (lo hace el lanzador lapiz-thp-capture.sh): un solo lector de spidev.
Formato de salida: por frame  <f64 t><u16 fase><u32 len> + len bytes.
"""
import importlib.machinery, importlib.util, os, select, struct, sys, time

TD = "/usr/local/share/uke/tactil/uke-touchd.py"
OUT = sys.argv[1] if len(sys.argv) > 1 else "/root/lapiz-thp-frames.bin"
PHASES = [(8, "A reposo, sin lapiz"), (10, "B lapiz acercado (hover), sin tocar"), (12, "C punta apoyada y moviendose"), (10, "D botones: pequeno, grande arriba, grande abajo")]
LEN = 0x1FFF

loader = importlib.machinery.SourceFileLoader("td", TD)
spec = importlib.util.spec_from_loader("td", loader)
td = importlib.util.module_from_spec(spec)
loader.exec_module(td)


def main():
    spi = td.Spi()
    n = 2 + td.THP_OFF + LEN
    import ctypes
    spi.tx = ctypes.create_string_buffer(n)
    spi.rx = ctypes.create_string_buffer(n)
    # sin IRQ: uke-touchd (parado con SIGSTOP) conserva la linea; sondeo a ~125 Hz y descarte por id de frame
    last_id = None
    t0 = time.monotonic()
    end = t0 + sum(p[0] for p in PHASES)
    bounds, acc = [], 0
    for d, name in PHASES:
        acc += d
        bounds.append((acc, name))
    cur = -1
    cnt = 0
    with open(OUT, "wb") as f:
        while time.monotonic() < end:
            time.sleep(0.008)
            t = time.monotonic() - t0
            ph = next(i for i, (b, _) in enumerate(bounds) if t < b) if t < bounds[-1][0] else len(bounds) - 1
            if ph != cur:
                cur = ph
                print("FASE %d (%s) a t=%.1f s" % (ph, bounds[ph][1], t), flush=True)
            F = spi.read(td.EVENT_BUF, td.THP_OFF + LEN)[td.THP_OFF:]
            fid = struct.unpack_from("<H", F, 4)[0]
            if fid == last_id:
                continue
            last_id = fid
            f.write(struct.pack("<dHI", t, ph, len(F)) + F)
            cnt += 1
    print("frames guardados:", cnt, "->", OUT, flush=True)


main()
