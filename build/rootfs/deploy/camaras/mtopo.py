#!/usr/bin/env python3
"""mtopo.py [/dev/mediaN] -- lista entidades y enlaces con MEDIA_IOC_G_TOPOLOGY (incluye los enlaces AUXILIARES sensor->lente, que
media-ctl -p no muestra porque no tienen pads). Solo lectura; sin dependencias. 22-oct-2026, ciclo 22."""
import fcntl, struct, sys, ctypes
dev = sys.argv[1] if len(sys.argv) > 1 else "/dev/media0"
IOC = 0xC0487C04          # _IOWR('|', 0x04, struct media_v2_topology) (72 B)
fd = open(dev, "rb", buffering=0)
def topo(ne=0, nl=0, pe=0, pl=0):
    b = bytearray(struct.pack("=QIIQIIQIIQIIQ", 0, ne, 0, pe, 0, 0, 0, 0, 0, 0, nl, 0, pl))
    fcntl.ioctl(fd, IOC, b)
    return struct.unpack("=QIIQIIQIIQIIQ", b)
v = topo(); ne, nl = v[1], v[10]
eb = ctypes.create_string_buffer(ne * 96); lb = ctypes.create_string_buffer(nl * 40)
topo(ne, nl, ctypes.addressof(eb), ctypes.addressof(lb))
ents = {}
for i in range(ne):
    eid, name, func, fl = struct.unpack_from("=I64sII", eb, i * 96)
    ents[eid] = (name.split(b"\0")[0].decode(), func)
kinds = {0: "datos", 1: "interfaz", 2: "AUXILIAR"}
aux = 0
for i in range(nl):
    lid, src, snk, fl = struct.unpack_from("=IIII", lb, i * 40)
    k = (fl >> 28) & 0xf
    if k == 2:
        aux += 1
        print("AUXILIAR: %s -> %s" % (ents.get(src, ("?",))[0], ents.get(snk, ("?",))[0]))
lens = [n for n, f in ents.values() if f == 0x00020003]
print("entidades=%d enlaces=%d auxiliares=%d lentes=%s" % (ne, nl, aux, lens))
