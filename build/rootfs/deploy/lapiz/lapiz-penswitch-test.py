#!/usr/bin/env python3
"""lapiz-penswitch-test.py — NO EJECUTAR SIN AUTORIZACION: la prueba del 19-oct dejo el tactil sin respuesta (causa sin determinar).
Pendiente segun la revision: ACK con reintentos x10 como el vendor, restaurar el valor previo (no 0), activar antes stylus_enable ([0x50,0xBF,..]).
Prueba REVERSIBLE del pen switch del NT36532 (19-oct-2026, autorizada por el dueno).

Escribe el comando host 0x7B (nvt_set_pen_switch, reg 0x7B50 = [0x50,0x7B,v]) con v=1 durante N s, captura frames THP (solo cuenta
magic y guarda frames 0x509) y vuelve a escribir v=0 SIEMPRE (finally). uke-touchd se pausa con SIGSTOP (lo hace el .sh) porque
solo puede haber un lector de spidev.  Uso: lapiz-penswitch-test.py [segundos]   (por defecto 40)
"""
import collections, ctypes, gzip, importlib.machinery, importlib.util, signal, struct, sys, time

td_path = "/usr/local/share/uke/tactil/uke-touchd.py"
loader = importlib.machinery.SourceFileLoader("td", td_path)
spec = importlib.util.spec_from_loader("td", loader)
td = importlib.util.module_from_spec(spec)
loader.exec_module(td)

SEC = int(sys.argv[1]) if len(sys.argv) > 1 else 40
LEN = 0x1FFF
OUT = "/root/lapiz-penswitch-frames.gz"
HOST_CMD = 0x50


def wr(spi, addr, data):
    ctypes.memset(spi.tx, 0, 4)
    spi.tx[0], spi.tx[1], spi.tx[2] = 0xFF, (addr >> 15) & 0xFF, (addr >> 7) & 0xFF
    spi._xfer(4)
    ctypes.memset(spi.tx, 0, len(data) + 2)
    spi.tx[0] = (addr & 0x7F) | 0x80
    for i, b in enumerate(data):
        spi.tx[1 + i] = b
    spi._xfer(1 + len(data))


def pen_switch(spi, v):
    wr(spi, td.EVENT_BUF + HOST_CMD, bytes([0x7B, v]))


def _term(*_):
    raise SystemExit(1)      # que SIGTERM/SIGHUP pasen por el finally y reviertan el pen switch


def main():
    for sg in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sg, _term)
    spi = td.Spi()
    n = 2 + td.THP_OFF + LEN
    spi.tx = ctypes.create_string_buffer(n)
    spi.rx = ctypes.create_string_buffer(n)
    mag = collections.Counter()
    last_id = None
    t0 = time.monotonic()
    try:
        print("pen_switch ON", flush=True)
        pen_switch(spi, 1)
        with gzip.open(OUT, "wb", compresslevel=1) as f:
            while time.monotonic() - t0 < SEC:
                time.sleep(0.008)
                F = spi.read(td.EVENT_BUF, td.THP_OFF + LEN)[td.THP_OFF:]
                fid = struct.unpack_from("<H", F, 4)[0]
                if fid == last_id:
                    continue
                last_id = fid
                m = struct.unpack_from("<I", F, 8)[0]
                mag[m] += 1
                if m != 0x4bf:      # guardar solo lo que no es el frame tactil normal
                    f.write(struct.pack("<dI", time.monotonic() - t0, len(F)) + F)
    finally:
        pen_switch(spi, 0)
        print("pen_switch OFF (revertido)", flush=True)
    print("magic vistos:", {hex(k): v for k, v in mag.items()}, flush=True)


main()
