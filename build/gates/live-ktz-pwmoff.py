#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# live-ktz-pwmoff.py — prueba EN VIVO del bit PWM_ENABLE (0x02[0]) del KTZ8866 en uke.
#
# Contexto (14-oct-2026, PIPELINE-PANEL-20261014/KTZ-PWM-ENABLE.md):
#  - Los volcados UKE-K53 (0x00-0x10) muestran 0x02=0x53 -> PWM_ENABLE=1 (modo "I2C x PWM")
#    con el pin PWM (pull-down 300k, nadie lo maneja en Linux) a duty=0.
#  - Datasheet KTZ8866 (Kinetic, rev 04b) tabla de enable: HWEN=1, BL_EN=1, duty=0,
#    brilla>=1, sinks ON, PWM_EN=1 -> "Standby" (boost OFF)  => registros "perfectos" y sin luz.
#  - Fix candidato: 0x02 bit0=0 (I2C Only Mode) -> "boost enabled + sinks enabled + I2C control only".
#
# Uso en la tablet (root):
#   python3 live-ktz-pwmoff.py                 # pasa a I2C-only y re-arma BL_EN
#   python3 live-ktz-pwmoff.py --set-brt 0x530 # además fija el código de brillo (11 bit)
#   python3 live-ktz-pwmoff.py --restore       # vuelve a PWM_EN=1 (restaura 0x02 bit0)
#
# Solo escribe 0x02 (bit0), 0x08 (re-armar) y opcionalmente 0x04/0x05. Nada más.
# Un reinicio restaura todo (el ABL re-inicializa el chip).

import fcntl
import glob
import os
import sys
import time

I2C_SLAVE_FORCE = 0x0706
ADDR = 0x11
BRT_LSB = 0x04
BRT_MSB = 0x05
BL_EN = 0x08
BL_CFG1 = 0x02


def open_bus(path):
    fd = os.open(path, os.O_RDWR)
    fcntl.ioctl(fd, I2C_SLAVE_FORCE, ADDR)
    return fd


def rd(fd, reg):
    os.write(fd, bytes([reg]))
    return os.read(fd, 1)[0]


def wr(fd, reg, val):
    os.write(fd, bytes([reg, val]))


def dump(fd, tag):
    vals = []
    for r in range(0x16):
        try:
            vals.append(rd(fd, r))
        except OSError:
            vals.append(None)
    txt = " ".join("--" if v is None else "%02x" % v for v in vals)
    print("%s 0x00-0x15: %s" % (tag, txt))
    return vals


def find_chips():
    chips = []
    for path in sorted(glob.glob("/dev/i2c-*"),
                       key=lambda p: int(p.rsplit("-", 1)[1])):
        fd = None
        try:
            fd = open_bus(path)
            did = rd(fd, 0x01)
            if (did & 0xF8) == 0x20:
                chips.append((path, fd))
                print("[+] KTZ8866 en %s (DEVICE_ID=0x%02x)" % (path, did))
            else:
                os.close(fd)
        except OSError:
            if fd is not None:
                try:
                    os.close(fd)
                except OSError:
                    pass
    return chips


def main():
    restore = "--restore" in sys.argv
    read_only = "--read-only" in sys.argv
    set_brt = None
    if "--set-brt" in sys.argv:
        set_brt = int(sys.argv[sys.argv.index("--set-brt") + 1], 0)

    chips = find_chips()
    if not chips:
        print("[-] No se encontró ningún KTZ8866 (DEVICE_ID 00100xxx) en /dev/i2c-*")
        return 1

    for path, fd in chips:
        dump(fd, "antes %s:" % path)
    if read_only:
        return 0

    for path, fd in chips:
        v = rd(fd, BL_CFG1)
        nv = (v | 1) if restore else (v & ~1)
        wr(fd, BL_CFG1, nv)
        modo = "PWM (bit0=1)" if restore else "I2C-only (bit0=0)"
        print("[*] %s: 0x02 0x%02x -> 0x%02x  [%s]" % (path, v, nv, modo))
        # re-armar el enable (transición off->on de BL_EN, sinks quedan)
        wr(fd, BL_EN, 0x3F)
        time.sleep(0.05)
        wr(fd, BL_EN, 0x7F)
        if set_brt is not None:
            wr(fd, BRT_LSB, set_brt & 0x7)
            wr(fd, BRT_MSB, (set_brt >> 3) & 0xFF)
            print("[*] %s: brillo codigo 0x%03x (0x04=%d 0x05=0x%02x)"
                  % (path, set_brt, set_brt & 0x7, (set_brt >> 3) & 0xFF))

    time.sleep(0.5)
    for path, fd in chips:
        dump(fd, "despues %s:" % path)

    print("** MIRA LA PANTALLA: ¿hay luz? (los chips encontrados: %d) **"
          % len(chips))
    return 0


if __name__ == "__main__":
    sys.exit(main())
