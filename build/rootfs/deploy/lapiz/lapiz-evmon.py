#!/usr/bin/env python3
"""lapiz-evmon.py — registra los eventos del nodo uinput «uke Focus Pen» (solo lectura) con CLOCK_MONOTONIC. Uso: lapiz-evmon.py [segundos] [fichero]."""
import fcntl, os, re, select, struct, sys, time
SEC = int(sys.argv[1]) if len(sys.argv) > 1 else 300
OUT = sys.argv[2] if len(sys.argv) > 2 else "/root/lapiz-evmon.log"
dev = None
txt = open("/proc/bus/input/devices").read()
for blk in txt.split("\n\n"):
    if 'Name="uke Focus Pen"' in blk:
        m = re.search(r"event(\d+)", blk)
        dev = "/dev/input/event" + m.group(1) if m else None
if not dev:
    sys.exit("no existe el nodo 'uke Focus Pen'")
fd = os.open(dev, os.O_RDONLY | os.O_NONBLOCK)
fcntl.ioctl(fd, 0x400445a0, struct.pack("i", 1))     # EVIOCSCLOCKID = CLOCK_MONOTONIC: alinea con time.monotonic() del cliente BLE y del demonio
end = time.monotonic() + SEC
n = 0
with open(OUT, "w") as f:
    f.write("dispositivo %s\n" % dev)
    while time.monotonic() < end:
        if not select.select([fd], [], [], 1.0)[0]:
            continue
        try:
            data = os.read(fd, 24 * 64)
        except BlockingIOError:
            continue
        for i in range(0, len(data) - 23, 24):
            sec, usec, t, c, v = struct.unpack("qqHHi", data[i:i + 24])
            f.write("%.4f %d %d %d\n" % (sec + usec / 1e6, t, c, v)); n += 1
        f.flush()
print("eventos:", n)
