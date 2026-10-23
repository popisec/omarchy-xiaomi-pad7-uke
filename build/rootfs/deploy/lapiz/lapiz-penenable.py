#!/usr/bin/env python3
"""lapiz-penenable.py — arranque del modo lapiz del NT36532 siguiendo al vendor (19-oct-2026). Escribe en el chip tactil.

Secuencia del driver Xiaomi (nt36532_touch.ko, decompilacion en RE-NOCTURNO-20261017/artifacts/touch/stylus-fw/decomp-full/):
  update_pen_status(): stylus_enable = pen_conectado_BLE && !pen_cargando; si enable -> nvt_set_pen_switch(ts->pen_id)
  nvt_xm_htc_set_stylus_enable(en) = nvt_set_extend_custom_cmd(4, en):
      set_page(EVENT_BUF|0x50); hasta 5 veces: escribir [0x50|0x80, 0xBF, 0x04, 0x00, en_lo, en_hi]; esperar 20 ms; leer 0x50;
      exito si el byte en EVENT_BUF+0x50 vale 0
  nvt_set_pen_switch(id): set_page; hasta 10 veces: escribir [0x50|0x80, 0x7B, id]; esperar 10 ms; leer 0x50; exito si vale 0
Aqui: comprueba antes que el chip esta idle (EVENT_BUF+0x50 == 0) y que el firmware vive; aplica la secuencia con ACK; captura frames THP
(solo cuenta magic y guarda los 0x509); y SIEMPRE revierte (pen_switch 0, stylus_enable 0) en el finally, tambien ante SIGTERM/SIGHUP.
Uso: lapiz-penenable.py [segundos] [pen_id]   (por defecto 40 s, pen_id 1). uke-touchd debe estar en SIGSTOP (lo hace el .sh).
"""
import collections, ctypes, gzip, importlib.machinery, importlib.util, signal, struct, sys, time

td_path = "/usr/local/share/uke/tactil/uke-touchd.py"
loader = importlib.machinery.SourceFileLoader("td", td_path)
spec = importlib.util.spec_from_loader("td", loader)
td = importlib.util.module_from_spec(spec)
loader.exec_module(td)

SEC = int(sys.argv[1]) if len(sys.argv) > 1 else 40
PEN_ID = int(sys.argv[2]) if len(sys.argv) > 2 else 1
LEN = 0x1FFF
OUT = "/root/lapiz-penenable-frames.gz"
HOST_CMD = td.EVENT_BUF + 0x50


def log(*a):
    print("%.3f" % time.monotonic(), *a, flush=True)


def wr(spi, addr, data):
    ctypes.memset(spi.tx, 0, 4)
    spi.tx[0], spi.tx[1], spi.tx[2] = 0xFF, (addr >> 15) & 0xFF, (addr >> 7) & 0xFF
    spi._xfer(4)
    ctypes.memset(spi.tx, 0, len(data) + 2)
    spi.tx[0] = (addr & 0x7F) | 0x80
    for i, b in enumerate(data):
        spi.tx[1 + i] = b
    spi._xfer(1 + len(data))


def ack0(spi):
    return spi.read(HOST_CMD, 2)[0] == 0


VERBOSE = True


def host_cmd(spi, data, tries, wait_s, name):
    """Escribe data en EVENT_BUF+0x50 y espera ACK (byte 0x50 == 0), reintentando como el vendor. Devuelve True si hubo ACK."""
    for i in range(tries):
        wr(spi, HOST_CMD, bytes(data))
        time.sleep(wait_s)
        if ack0(spi):
            if VERBOSE:
                log(name, "ACK en el intento", i + 1)
            return True
    log(name, "SIN ACK tras", tries, "intentos")
    return False


def stylus_enable(spi, en):
    return host_cmd(spi, [0xBF, 0x04, 0x00, en & 0xFF, (en >> 8) & 0xFF], 5, 0.020, "stylus_enable(%d)" % en)


def pen_switch(spi, v):
    return host_cmd(spi, [0x7B, v], 10, 0.010, "pen_switch(%d)" % v)


def hop_ack(spi):
    """nvt_set_pen_hopping_ack del vendor: [0x50|0x80, 0x7C]; espera 20 ms; ACK si EVENT_BUF+0x50 == 0 (hasta 5 intentos)."""
    return host_cmd(spi, [0x7C], 5, 0.020, "hop_ack")


def _term(*_):
    raise SystemExit(1)       # SIGTERM/SIGHUP pasan por el finally


def main():
    for sg in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sg, _term)
    spi = td.Spi()
    n = 2 + td.THP_OFF + LEN
    spi.tx = ctypes.create_string_buffer(n)
    spi.rx = ctypes.create_string_buffer(n)
    if not td.fw_alive(spi):
        sys.exit("el firmware del chip no responde (fw_alive): no se escribe nada")
    if not ack0(spi):
        sys.exit("el registro de comando host (EVENT_BUF+0x50) no esta a 0: chip ocupado, no se escribe nada")
    mag = collections.Counter()
    last_id = None
    armed = False
    rearm = 0
    last_pen = None          # instante del ultimo frame 0x509
    last_rearm = 0.0
    bursts = []              # frames 0x509 por rafaga
    try:
        armed = True
        ok1 = stylus_enable(spi, 1)
        ok2 = pen_switch(spi, PEN_ID) if ok1 else False
        ok3 = hop_ack(spi) if ok2 else False
        log("estado: stylus_enable", ok1, "pen_switch", ok2, "hop_ack", ok3)
        global VERBOSE
        VERBOSE = False
        t0 = time.monotonic()
        with gzip.open(OUT, "wb", compresslevel=1) as f:
            while time.monotonic() - t0 < SEC:
                time.sleep(0.004)
                F = spi.read(td.EVENT_BUF, td.THP_OFF + LEN)[td.THP_OFF:]
                fid = struct.unpack_from("<H", F, 4)[0]
                if fid == last_id:
                    continue
                last_id = fid
                m = struct.unpack_from("<I", F, 8)[0]
                mag[m] += 1
                now = time.monotonic()
                if m != 0x4bf:
                    f.write(struct.pack("<dI", now - t0, len(F)) + F)
                if m == 0x509:
                    if last_pen is None or now - last_pen > 0.3:
                        bursts.append(0)
                    bursts[-1] += 1
                    last_pen = now
                # hipotesis (19-oct): el chip emite una rafaga fija de 128 frames de lapiz y se detiene si el host no rearma;
                # si pasan 0.3 s sin frames de lapiz se reenvia el ACK de salto de frecuencia (0x7C, con ACK), como maximo 4 veces por segundo
                if now - (last_pen if last_pen is not None else t0) > 0.3 and now - last_rearm > 0.25 and rearm < 400:
                    last_rearm = now
                    rearm += 1
                    hop_ack(spi)
    finally:
        if armed:
            pen_switch(spi, 0)
            stylus_enable(spi, 0)
            log("revertido")
    log("magic vistos:", {hex(k): v for k, v in mag.items()})
    log("rearmes (hop_ack):", rearm, "rafagas de lapiz (frames):", bursts)


main()
