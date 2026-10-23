#!/usr/bin/python3 -I
"""osk-click.py — inyecta pulsaciones de puntero absoluto (uinput) para probar el teclado en pantalla con 'dedo' simulado.
Uso: osk-click.py FX,FY [FX,FY ...] [--hold SEG] [--drag FX2,FY2]   (coordenadas como fraccion 0..1 de la pantalla)
  osk-click.py 0.5,0.9            toque corto
  osk-click.py 0.5,0.9 --hold 0.8   pulsacion larga
  osk-click.py 0.5,0.9 --hold 0.8 --drag 0.55,0.8   pulsacion larga y deslizar antes de soltar
Necesita /dev/uinput (usuario omarchy, grupo input)."""
import fcntl, os, struct, sys, time
UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT = 0x40045564, 0x40045565, 0x40045567
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
ABS_X, ABS_Y, BTN_LEFT = 0, 1, 0x110
MAXV = 32767
fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
for ev in (EV_KEY, EV_ABS): fcntl.ioctl(fd, UI_SET_EVBIT, ev)
fcntl.ioctl(fd, UI_SET_KEYBIT, BTN_LEFT)
for a in (ABS_X, ABS_Y): fcntl.ioctl(fd, UI_SET_ABSBIT, a)
absmax = [0] * 64; absmin = [0] * 64; absmax[ABS_X] = absmax[ABS_Y] = MAXV
dev = struct.pack("80sHHHHi", b"osk-click-test", 3, 0x1234, 0x5678, 1, 0) + struct.pack("64i", *absmax) + struct.pack("64i", *absmin) + struct.pack("64i", *([0] * 64)) + struct.pack("64i", *([0] * 64))
os.write(fd, dev)
fcntl.ioctl(fd, UI_DEV_CREATE)
time.sleep(1.2)
def ev(t, c, v): os.write(fd, struct.pack("llHHi", 0, 0, t, c, v))
def move(fx, fy):
    ev(EV_ABS, ABS_X, int(fx * MAXV)); ev(EV_ABS, ABS_Y, int(fy * MAXV)); ev(EV_SYN, 0, 0)
args = sys.argv[1:]
hold = 0.06; drag = None; pts = []
i = 0
while i < len(args):
    if args[i] == "--hold": hold = float(args[i + 1]); i += 2
    elif args[i] == "--drag": drag = tuple(float(v) for v in args[i + 1].split(",")); i += 2
    else: pts.append(tuple(float(v) for v in args[i].split(","))); i += 1
for fx, fy in pts:
    move(fx, fy); time.sleep(0.15)
    ev(EV_KEY, BTN_LEFT, 1); ev(EV_SYN, 0, 0)
    time.sleep(hold)
    if drag:
        for k in range(1, 6):
            move(fx + (drag[0] - fx) * k / 5, fy + (drag[1] - fy) * k / 5); time.sleep(0.05)
        time.sleep(0.3)
    ev(EV_KEY, BTN_LEFT, 0); ev(EV_SYN, 0, 0)
    time.sleep(0.25)
fcntl.ioctl(fd, UI_DEV_DESTROY)
