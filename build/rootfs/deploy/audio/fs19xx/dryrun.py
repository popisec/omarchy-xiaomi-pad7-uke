#!/usr/bin/env python3
"""dryrun.py — réplica en Python de la validación y la secuencia de uke_fs19xx.c sobre el .fsm real (solo lectura, sin tablet).
Uso: dryrun.py fs19xx.fsm [--scene N] [--amp 0x34] [--all-writes]
Verifica: tamaño, CRC-16/MODBUS, trozo por dirección, descriptores admitidos (fs_desc_ok) y lista las transacciones I2C
que haría fs_reg_init + fs_start_up (48 kHz, BCLK 6,144 MHz, volumen/escena dados). NO escribe nada en ningún sitio."""
import struct, sys
u16 = lambda d, o: struct.unpack('<H', d[o:o+2])[0]
def crc16(b):
    c = 0
    for x in b:
        c ^= x
        for _ in range(8): c = (c >> 1) ^ 0xA001 if c & 1 else c >> 1
    return c
def desc_ok(d):
    if d >= 0x1000 and (d & 0xf00) == 0xf00: return False
    if d >= 0xf000 and (d & 0xf00) == 0: return True
    return (d >> 12) + 1 + ((d >> 8) & 0xf) <= 16
def parse(d, addr):
    assert u16(d, 0x16) == len(d), "tamaño"
    assert crc16(d[0x1a:]) == u16(d, 0x18), "crc"
    n = u16(d, 0x1a); s = None
    for k in range(n):
        off = u16(d, 0x1c + 4*k)
        if u16(d, off + 0x1e) == addr: s = off
    assert s is not None, "sin trozo"
    r = {}
    for k in range(u16(d, s + 0x1a)):
        typ = u16(d, s + 0x2a + 4*k); t = s + 0x28 + u16(d, s + 0x28 + 4*k); c = u16(d, t)
        if typ == 1: r['info'] = [u16(d, t+2+2*i) for i in range(c)]
        if typ == 2: r['common'] = [(u16(d, t+2+4*i), u16(d, t+4+4*i)) for i in range(c)]
        if typ == 3: r['scene'] = [(u16(d, t+2+6*i), u16(d, t+4+6*i), u16(d, t+6+6*i)) for i in range(c)]
    for dd, _ in r['common']: assert desc_ok(dd), hex(dd)
    for _, dd, _ in r['scene']: assert desc_ok(dd), hex(dd)
    return r
def tx(desc, val):
    if desc >= 0xf000 and (desc & 0xf00) == 0: return "W %02x <- %04x" % (desc & 0xff, val)
    w = (desc >> 12) + 1; sh = (desc >> 8) & 0xf; m = ((1 << w) - 1) << sh
    return "RMW %02x mask %04x <- %04x" % (desc & 0xff, m, (val << sh) & m)
def main():
    d = open(sys.argv[1], 'rb').read()
    scene = int(sys.argv[sys.argv.index('--scene')+1]) if '--scene' in sys.argv else 0
    only = int(sys.argv[sys.argv.index('--amp')+1], 0) if '--amp' in sys.argv else None
    for addr in (0x34, 0x35, 0x36, 0x37):
        if only and addr != only: continue
        r = parse(d, addr)
        regs = set(); lines = []
        for dd, v in r['common']: lines.append(tx(dd, v)); regs.add(dd & 0xff)
        mask = 1 << scene; sc = [(dd, v) for m, dd, v in r['scene'] if m & mask]
        for dd, v in sc: lines.append(tx(dd, v)); regs.add(dd & 0xff)
        print("amp 0x%02x: info[1]=%#x pos=%d | %d comunes + %d de escena %d -> registros tocados %s" %
              (addr, r['info'][1], r['info'][16], len(r['common']), len(sc), scene, ' '.join('%02x' % x for x in sorted(regs))))
        if '--all-writes' in sys.argv: print('\n'.join('   ' + l for l in lines))
    print("OK: todos los descriptores admitidos; tamaño/CRC/trozos validados")
main()
