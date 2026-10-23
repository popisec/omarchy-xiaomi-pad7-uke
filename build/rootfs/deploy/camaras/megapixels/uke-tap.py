#!/usr/bin/env python3
"""uke-tap.py X Y [W H] — un clic sintetico (puntero absoluto por /dev/uinput, sin dependencias) en la posicion X,Y de una pantalla W x H
(por defecto 3200 x 2136, la de la uke). Para probar Megapixels sin estar delante (pulsar el disparador). 22-oct-2026, sesion de camaras.
Crea el dispositivo, espera a que el compositor lo vea, mueve, pulsa, suelta y lo destruye."""
import fcntl, os, struct, sys, time

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
SYN_REPORT, BTN_LEFT, ABS_X, ABS_Y = 0, 0x110, 0, 1
UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT = 0x40045564, 0x40045565, 0x40045567
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502

x, y = int(sys.argv[1]), int(sys.argv[2])
w = int(sys.argv[3]) if len(sys.argv) > 3 else 3200
h = int(sys.argv[4]) if len(sys.argv) > 4 else 2136
fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
for ev in (EV_KEY, EV_ABS):
    fcntl.ioctl(fd, UI_SET_EVBIT, ev)
fcntl.ioctl(fd, UI_SET_KEYBIT, BTN_LEFT)
for a in (ABS_X, ABS_Y):
    fcntl.ioctl(fd, UI_SET_ABSBIT, a)
absmax = [0] * 64; absmax[ABS_X] = w - 1; absmax[ABS_Y] = h - 1
dev = struct.pack("80sHHHHi", b"uke-tap", 0x06, 0x1234, 0x5678, 1, 0) + struct.pack("64i", *absmax) + struct.pack("64i", *([0] * 64)) * 3
os.write(fd, dev)
fcntl.ioctl(fd, UI_DEV_CREATE)
time.sleep(1.0)


def ev(t, c, v):
    s = time.time()
    os.write(fd, struct.pack("qqHHi", int(s), int((s % 1) * 1e6), t, c, v))


ev(EV_ABS, ABS_X, x); ev(EV_ABS, ABS_Y, y); ev(EV_SYN, SYN_REPORT, 0); time.sleep(0.15)
ev(EV_KEY, BTN_LEFT, 1); ev(EV_SYN, SYN_REPORT, 0); time.sleep(0.08)
ev(EV_KEY, BTN_LEFT, 0); ev(EV_SYN, SYN_REPORT, 0); time.sleep(0.3)
fcntl.ioctl(fd, UI_DEV_DESTROY)
os.close(fd)
print("clic en", x, y)
