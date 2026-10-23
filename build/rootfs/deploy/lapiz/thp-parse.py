"""Reconstruye frames de 8 KB desde thp.gz (8 kprobes uke_thp0..7 en nvt_ts_work_func+0x2f8). CORREGIDO 19-oct: las sondas del mismo frame
se disparan en orden 7,6,...,0 (mismo instante, <0.2 ms): un frame empieza en uke_thp7 y acaba en uke_thp0 (antes se abria en k==0 y se
mezclaban partes de interrupciones distintas)."""
import gzip, re, struct, sys
rx = re.compile(r'\]\s+[d.]+\s+([\d.]+): uke_thp(\d): \(.*?\) a=\{(.*?)\} b=\{(.*?)\}')
arr = lambda s: b''.join(struct.pack('<Q', int(x, 16)) for x in s.split(','))
src = sys.argv[1] if len(sys.argv) > 1 else 'thp.gz'
dst = sys.argv[2] if len(sys.argv) > 2 else 'frames8k.bin'
cur = None; n = bad = 0
with gzip.open(src, 'rt', errors='replace') as f, open(dst, 'wb') as out:
    for l in f:
        m = rx.search(l)
        if not m: continue
        t = float(m.group(1)); k = int(m.group(2)); d = arr(m.group(3)) + arr(m.group(4))
        if k == 7:
            cur = [t, {}]
        if cur is None or abs(t - cur[0]) > 0.005:
            cur = None; bad += 1; continue
        cur[1][k] = d
        if k == 0:
            if len(cur[1]) == 8 and all(len(cur[1][i]) == 1024 for i in range(8)):
                out.write(struct.pack('<d', cur[0]) + b''.join(cur[1][i] for i in range(8))); n += 1
            else: bad += 1
            cur = None
print('frames completos', n, 'descartados', bad)
