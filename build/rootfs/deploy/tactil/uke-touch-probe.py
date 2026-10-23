#!/usr/bin/env python3
"""uke-touch-probe.py — sonda de SOLO LECTURA del tactil NT36532 (TDDI, SPI) de la Xiaomi Pad 7 'uke'.

18-oct-2026. Python puro (ioctl de spidev, sin modulos externos). Requiere /dev/spidev0.0, que se obtiene con
`modprobe spidev` + driver_override=spidev + bind de spi0.0 (ver README.md de esta carpeta; eso escribe en sysfs y
necesita la orden del dueno).

Que hace (NADA de reset, bootloader ni descarga de firmware):
  1. lee el bloque FWINFO del firmware: EVENT_BUF 0x125800 + 0x78 (como nvt_get_fw_info del driver del vendor).
     En Android (17-oct, coldboot): fw_ver 0x0E, x 2136 / y 3200, rx 40 / tx 60. Si fw_ver y ~fw_ver casan, el
     firmware del chip esta VIVO (lo cargo el ABL o persiste); si no, el chip esta sin firmware/en bootloader.
  2. opcional (--frames N): lee N veces el bloque de evento (0x125800, 0x101 + 0x1438 B, el memcpy de
     nvt_ts_work_func+0x2f8 en Android) y valida la cabecera THP medida en Android: F=buf+0x101 del vendor (= dato+0x100),
     id u16 @F+4, magic 0x4BF @F+8, ~id @F+0xC, ~magic @F+0x10; mutual u16[40x60] @F+0x40.

Protocolo SPI (RE del nt36532_touch.ko, build/.../TOUCH-REWRITE.md de ubuntu-permanente, ronda 29):
  set_page(addr): escritura [0xFF][A22:15][A14:7][0x00]   (0xFF = registro de pagina | bit de escritura 0x80)
  read(addr, n):  full-duplex [addr & 0x7F][0x00 * (n+1)] -> los datos empiezan en rx[2]
"""
import argparse, ctypes, fcntl, os, struct, sys, time

DEV = "/dev/spidev0.0"
SPEED = 19_200_000          # spi-max-frequency del DT (0x0124f800)
EVENT_BUF = 0x125800                # OJO: mapa SINGLE; este chip es CASCADE (0x11c400): usar uke-touch-fwload.py --verify-only
FWINFO_OFF = 0x78
# en el driver del vendor buf[0] es el byte de comando: su buf+0x101 es nuestro dato+0x100
THP_OFF, THP_LEN = 0x100, 0x1438
MAGIC = 0x4BF
ROWS, COLS = 40, 60


def _ioc(direction, typ, nr, size):
    return (direction << 30) | (size << 16) | (ord(typ) << 8) | nr


SPI_IOC_WR_MODE = _ioc(1, 'k', 1, 1)
SPI_IOC_WR_BITS = _ioc(1, 'k', 3, 1)
SPI_IOC_WR_SPEED = _ioc(1, 'k', 4, 4)


def spi_message(n):
    return _ioc(1, 'k', 0, 32 * n)


class Spi:
    def __init__(self, path, speed):
        self.fd = os.open(path, os.O_RDWR)
        self.speed = speed
        fcntl.ioctl(self.fd, SPI_IOC_WR_MODE, struct.pack("B", 0))
        fcntl.ioctl(self.fd, SPI_IOC_WR_BITS, struct.pack("B", 8))
        fcntl.ioctl(self.fd, SPI_IOC_WR_SPEED, struct.pack("I", speed))

    def xfer(self, tx):
        n = len(tx)
        txb = ctypes.create_string_buffer(bytes(tx), n)
        rxb = ctypes.create_string_buffer(n)
        # struct spi_ioc_transfer: tx_buf u64, rx_buf u64, len u32, speed_hz u32, delay_usecs u16,
        # bits_per_word u8, cs_change u8, tx_nbits u8, rx_nbits u8, word_delay_usecs u8, pad u8 (32 B)
        tr = struct.pack("QQIIHBBBBBB", ctypes.addressof(txb), ctypes.addressof(rxb), n, self.speed, 0, 8, 0, 0, 0, 0, 0)
        fcntl.ioctl(self.fd, spi_message(1), bytearray(tr))
        return rxb.raw

    def set_page(self, addr):
        self.xfer([0xFF, (addr >> 15) & 0xFF, (addr >> 7) & 0xFF, 0x00])

    def read(self, addr, n):
        self.set_page(addr)
        rx = self.xfer([addr & 0x7F] + [0] * (n + 1))
        return rx[2:2 + n]


def gpio54():
    """Estado del GPIO de interrupcion (tlmm 54) leido de debugfs, sin pedir la linea."""
    try:
        for line in open("/sys/kernel/debug/gpio"):
            if "gpio54 " in line or "gpio54:" in line or line.strip().startswith("gpio54"):
                return line.strip()
    except OSError as e:
        return "debugfs gpio no legible: %s" % e
    return "gpio54 no listado en debugfs"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--frames", type=int, default=0, help="leer N bloques de evento (THP) y validar cabecera")
    ap.add_argument("--speed", type=int, default=SPEED)
    ap.add_argument("--dump", help="guardar los bloques de evento leidos en este fichero")
    a = ap.parse_args()
    if not os.path.exists(DEV):
        sys.exit("no existe %s (falta spidev ligado a spi0.0)" % DEV)
    s = Spi(DEV, a.speed)
    print("GPIO irq:", gpio54())
    fi = s.read(EVENT_BUF | FWINFO_OFF, 39)
    print("FWINFO @0x%06x: %s" % (EVENT_BUF | FWINFO_OFF, fi.hex(" ")))
    fw, nfw = fi[0], fi[1]
    xnum, ynum = fi[2], fi[3]
    xmax, ymax = (fi[4] << 8) | fi[5], (fi[6] << 8) | fi[7]
    vivo = fw == (~nfw & 0xFF) and fw not in (0x00, 0xFF)
    print("fw_ver=0x%02x ~fw_ver=0x%02x -> %s; x_num=%d y_num=%d abs_x_max=%d abs_y_max=%d"
          % (fw, nfw, "FIRMWARE VIVO" if vivo else "sin firmware valido (bootloader/RAM vacia?)", xnum, ynum, xmax, ymax))
    print("  (Android: fw_ver 0x0E, 2136x3200, rx 40 / tx 60)")
    out = open(a.dump, "wb") if a.dump else None
    ok = 0
    for i in range(a.frames):
        buf = s.read(EVENT_BUF, THP_OFF + THP_LEN)
        if out:
            out.write(buf)
        F = buf[THP_OFF:]
        fid, mag, nid, nmag = struct.unpack_from("<H2xH2xH2xH", F, 4)
        good = mag == MAGIC and nmag == (~MAGIC & 0xFFFF) and nid == (~fid & 0xFFFF)
        mutual = struct.unpack_from("<%dH" % (ROWS * COLS), F, 0x40)
        base = sorted(mutual)[len(mutual) // 2]
        peak = max(range(len(mutual)), key=lambda k: mutual[k])
        print("frame %d: id=%d magic=0x%03x %s  mediana=%d pico=%d en r%d c%d (+%d)  gpio=%s"
              % (i, fid, mag, "OK" if good else "cabecera NO valida", base, mutual[peak], peak // COLS, peak % COLS,
                 mutual[peak] - base, gpio54().split()[-1] if gpio54() else "?"))
        ok += good
        time.sleep(0.05)
    if a.frames:
        print("frames con cabecera THP valida: %d/%d" % (ok, a.frames))


if __name__ == "__main__":
    main()
