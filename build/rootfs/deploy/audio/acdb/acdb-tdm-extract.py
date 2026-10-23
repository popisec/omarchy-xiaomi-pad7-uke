#!/usr/bin/env python3
"""Extrae del ACDB `Forte` (solo lectura; el fichero NO esta en el repo) los parametros de los modulos TDM de AudioReach.

Uso: python3 -I acdb-tdm-extract.py /ruta/Forte_acdb_cal.acdb  [ruta/a/audioreach-graphservices/spf/api]
Formato (deducido, 18-oct-2026): 'ACDB' + u32 0 + u32 longitud, luego trozos [tag(4) size(u32) datos]; POOL = datos; bloques del POOL = [u32 0][u32 size][datos].
SGIT = tabla de subgrafos (id 0xb000xxxx, pares (module_id, instance_id)); CDDE = grupos [n, n pares (iid, param_id)].
Estructura param_id_tdm_intf_cfg_t y IDs: github.com/Audioreach/audioreach-graphservices spf/api/modules/pcm_tdm_api.h (BSD-3).
Busca en POOL las estructuras param_id_tdm_intf_cfg_t plausibles (lpaif_type, intf_idx, sync_src, data_oe, slot_mask, nslots, slot_width, sync_mode, invert, delay).
"""
import struct, sys
d = open(sys.argv[1], 'rb').read()
assert d[:4] == b'ACDB'
def chunk(tag):
    off = 12
    while off + 8 <= len(d):
        t, s = d[off:off+4], struct.unpack_from('<I', d, off+4)[0]
        if t == tag: return off + 8, s
        off += 8 + s
po, ps = chunk(b'POOL'); pool = d[po:po+ps]
def plaus(b):
    lp, idx, sync, oe, slot, ns, sw, sm, inv, dly, rsv = struct.unpack('<IIHHIHHHHHH', b)
    return (lp <= 4 and idx <= 4 and sync <= 1 and oe <= 1 and 0 < slot <= 0xffff and 1 <= ns <= 32 and sw in (16, 24, 32)
            and sm <= 2 and inv <= 1 and dly <= 2 and rsv == 0 and slot < (1 << ns))
LP = {0: 'LPAIF', 1: 'LPAIF_RXTX', 2: 'LPAIF_WSA', 3: 'LPAIF_VA', 4: 'LPAIF_AXI'}
for off in range(0, len(pool) - 28, 4):
    b = pool[off:off+28]
    if plaus(b) and struct.unpack_from('<II', pool, off - 8) == (0, 28):
        lp, idx, sync, oe, slot, ns, sw, sm, inv, dly, rsv = struct.unpack('<IIHHIHHHHHH', b)
        print('%-11s intf=%d sync_src=%d data_oe=%d slot_mask=0x%x nslots=%d slot_width=%d sync_mode=%d invert=%d data_delay=%d' %
              (LP[lp], idx, sync, oe, slot, ns, sw, sm, inv, dly))
