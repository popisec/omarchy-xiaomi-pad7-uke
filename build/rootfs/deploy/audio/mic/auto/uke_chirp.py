#!/usr/bin/env python3
"""uke_chirp.py - medidas acusticas automaticas con chirp logaritmico (solo libreria estandar; numpy OPCIONAL solo acelera).

Subcomandos:
  gen     SALIDA.wav [--bursts N] [--amp dBFS] [--ch both|L|R] [--out-json meta.json]
          secuencia de reproduccion: silencio inicial (cubre el chasquido de arranque) + N chirps con hueco de ruido.
  analyze GRABACION.wav --meta meta.json [--mic-dist-cm D]
          correlacion (filtro adaptado) -> inicio del chirp por canal, retardo inter-canal (muestras, mm), nivel, ruido, SNR,
          GCC-PHAT, respuesta en frecuencia y HD2/HD3 por Farina. Salida JSON en stdout.
  locate  --speakers "x,y;x,y;x,y;x,y" --dt "t0,t1,t2,t3" [--lvl "dB0,dB1,..."]   (cm, ms; dt = llegada ch1 - ch0)
          busca (xA,yA,xB,yB) que explica los retardos diferenciales (cm). Orientativo: ver el informe.
  selftest   simula dos micros con retardo/atenuacion/ruido/chasquido/no linealidad y comprueba que se recuperan.
El WAV de grabacion: S16/48 kHz/2 canales (formato unico de hw:UKE,2). Retardo > 0 = el canal 1 recibe DESPUES que el canal 0.
"""
import sys, os, math, json, wave, struct, array, random, argparse, cmath

FS = 48000
C_MM_S = 343000.0  # velocidad del sonido a ~20 C (mm/s)
F1, F2, TCH = 200.0, 12000.0, 1.0   # barrido
LEAD, GAP = 1.5, 1.5                # s de silencio inicial / hueco tras cada chirp
FADE = 0.01
try:
    import numpy as np
except Exception:
    np = None

# ---------------------------------------------------------------- senal
def chirp_val(t):
    """valor del chirp (sin ventana de fade) en t segundos desde su inicio; fase analitica => retardos fraccionarios exactos."""
    if t < 0 or t > TCH:
        return 0.0
    L = TCH / math.log(F2 / F1)
    ph = 2 * math.pi * F1 * L * (math.exp(t / L) - 1.0)
    w = 1.0
    if t < FADE: w = 0.5 - 0.5 * math.cos(math.pi * t / FADE)
    elif t > TCH - FADE: w = 0.5 - 0.5 * math.cos(math.pi * (TCH - t) / FADE)
    return w * math.sin(ph)

def ref_chirp():
    return [chirp_val(i / FS) for i in range(int(TCH * FS))]

def schedule(nb):
    P = TCH + GAP
    return [LEAD + k * P for k in range(nb)], P, LEAD + nb * P

def write_wav(path, chans, fs=FS):
    n = len(chans[0]); a = array.array('h')
    for i in range(n):
        for c in chans:
            a.append(max(-32768, min(32767, int(round(c[i] * 32767)))))
    if sys.byteorder == 'big': a.byteswap()
    with wave.open(path, 'wb') as w:
        w.setnchannels(len(chans)); w.setsampwidth(2); w.setframerate(fs); w.writeframes(a.tobytes())

def read_wav(path):
    with wave.open(path, 'rb') as w:
        nc, sw, fs, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes(); raw = w.readframes(n)
    assert sw == 2, "se espera S16"
    a = array.array('h'); a.frombytes(raw)
    if sys.byteorder == 'big': a.byteswap()
    return [[a[i * nc + c] / 32768.0 for i in range(n)] for c in range(nc)], fs

# ---------------------------------------------------------------- FFT (numpy si hay; si no, radix-2 puro)
def _fft_py(x, inv=False):
    n = len(x); j = 0; x = list(x)
    for i in range(1, n):
        bit = n >> 1
        while j & bit: j ^= bit; bit >>= 1
        j ^= bit
        if i < j: x[i], x[j] = x[j], x[i]
    m = 2
    while m <= n:
        s = -1 if not inv else 1; wm = cmath.exp(s * 2j * math.pi / m); h = m // 2
        ws = [1]
        for _ in range(h - 1): ws.append(ws[-1] * wm)
        for k in range(0, n, m):
            for q in range(h):
                u = x[k + q]; v = x[k + q + h] * ws[q]; x[k + q] = u + v; x[k + q + h] = u - v
        m <<= 1
    return [v / n for v in x] if inv else x

def _nextpow2(n):
    p = 1
    while p < n: p <<= 1
    return p

def xcorr(sig, ref):
    """correlacion cruzada (lag i = muestra del inicio de ref dentro de sig) - filtro adaptado."""
    n = _nextpow2(len(sig) + len(ref))
    if np is not None:
        S = np.fft.rfft(np.asarray(sig), n); R = np.fft.rfft(np.asarray(ref), n)
        return np.fft.irfft(S * np.conj(R), n)[:len(sig)].tolist()
    S = _fft_py(list(sig) + [0] * (n - len(sig))); R = _fft_py(list(ref) + [0] * (n - len(ref)))
    out = _fft_py([s * r.conjugate() for s, r in zip(S, R)], True)
    return [v.real for v in out[:len(sig)]]

def gcc_phat(a, b, maxlag=200):
    """retardo de b respecto a a (muestras, subpixel) con GCC-PHAT."""
    n = _nextpow2(len(a) + len(b))
    if np is not None:
        A = np.fft.rfft(np.asarray(a), n); B = np.fft.rfft(np.asarray(b), n)
        X = B * np.conj(A); X /= np.abs(X) + 1e-12
        # banda util: 200 Hz..12 kHz (donde hay chirp)
        f = np.fft.rfftfreq(n, 1 / FS); X[(f < F1) | (f > F2)] = 0
        cc = np.fft.irfft(X, n)
        seg = np.concatenate((cc[-maxlag:], cc[:maxlag + 1])).tolist(); off = -maxlag
    else:
        A = _fft_py(list(a) + [0] * (n - len(a))); B = _fft_py(list(b) + [0] * (n - len(b)))
        X = []
        for k in range(n):
            f = k * FS / n if k <= n // 2 else (n - k) * FS / n
            v = B[k] * A[k].conjugate(); m = abs(v)
            X.append(0 if (m < 1e-12 or f < F1 or f > F2) else v / m)
        cc = [v.real for v in _fft_py(X, True)]
        seg = cc[-maxlag:] + cc[:maxlag + 1]; off = -maxlag
    i = max(range(len(seg)), key=lambda k: seg[k])
    return off + i + parab(seg, i)

def parab(y, i):
    if 0 < i < len(y) - 1:
        d = y[i - 1] - 2 * y[i] + y[i + 1]
        if d != 0: return 0.5 * (y[i - 1] - y[i + 1]) / d
    return 0.0

def db(x): return 20 * math.log10(max(x, 1e-12))
def rms(v): return math.sqrt(sum(s * s for s in v) / max(1, len(v)))

# ---------------------------------------------------------------- analisis
def analyze(rec, meta, mic_dist_cm=None):
    ref = ref_chirp(); E = sum(r * r for r in ref)
    starts = meta['starts_s']; P = meta['period_s']; res = {'channels': [], 'bursts': len(starts)}
    L = TCH / math.log(F2 / F1)
    chan = []
    for ci, x in enumerate(rec):
        cc = xcorr(x, ref)
        # ancla: maximo global tras 0,5 s (el chasquido de arranque se excluye)
        lo = int(0.5 * FS); i0 = max(range(lo, len(cc)), key=lambda i: abs(cc[i]))
        k0 = round((i0 / FS - starts[0]) / P) if False else 0
        # el maximo global puede ser cualquier burst: se localiza cual por el modulo del periodo
        kk = min(range(len(starts)), key=lambda k: abs(i0 / FS - (starts[k] + meta.get('anchor_offset_s', 0.0))))
        t_first = i0 / FS - kk * P
        bs = []
        for k in range(len(starts)):
            c0 = int((t_first + k * P) * FS); w = int(0.02 * FS)
            a, b = max(0, c0 - w), min(len(cc), c0 + w + 1)
            if b - a < 3: continue
            loc = max(range(a, b), key=lambda i: abs(cc[i]))
            sub = loc + parab([abs(v) for v in cc[a:b]], loc - a)
            ya = [abs(v) for v in cc[a:b]]; i_ = loc - a; fr_ = parab(ya, i_)
            pkv = ya[i_] - 0.25 * (ya[i_ - 1] - ya[i_ + 1]) * fr_ if 0 < i_ < len(ya) - 1 else ya[i_]
            amp = pkv / E                                # ganancia lineal estimada (pico interpolado)
            seg = x[int(sub): int(sub) + int(TCH * FS)]
            gap = x[int(sub) + int((TCH + 0.3) * FS): int(sub) + int((TCH + P - TCH - 0.2) * FS)]
            bs.append({'k': k, 't_s': sub / FS, 'sub_samp': sub, 'gain_db': db(amp), 'burst_rms_dbfs': db(rms(seg)),
                       'noise_rms_dbfs': db(rms(gap)) if len(gap) > 100 else None,
                       'peak_to_sidelobe_db': None})
        chan.append((x, bs, cc))
        res['channels'].append({'ch': ci, 'bursts': bs})
    # estadisticos por canal
    for ci, (x, bs, cc) in enumerate(chan):
        g = [b['gain_db'] for b in bs]; res['channels'][ci]['gain_db_mean'] = sum(g) / len(g)
        res['channels'][ci]['gain_db_std'] = math.sqrt(sum((v - sum(g) / len(g)) ** 2 for v in g) / len(g)) if len(g) > 1 else 0.0
        nz = [b['noise_rms_dbfs'] for b in bs if b['noise_rms_dbfs'] is not None]
        res['channels'][ci]['noise_dbfs'] = sum(nz) / len(nz) if nz else None
        res['channels'][ci]['snr_db'] = (sum(b['burst_rms_dbfs'] for b in bs) / len(bs) - res['channels'][ci]['noise_dbfs']) if nz else None
    if len(chan) >= 2:
        ds = [(b1['sub_samp'] - b0['sub_samp']) for b0, b1 in zip(chan[0][1], chan[1][1])]
        res['inter_channel'] = {'delay_samples_mf': ds, 'delay_samples_mean': sum(ds) / len(ds),
                                'ratio_db_ch0_minus_ch1': res['channels'][0]['gain_db_mean'] - res['channels'][1]['gain_db_mean']}
        res['inter_channel']['delay_mm'] = res['inter_channel']['delay_samples_mean'] / FS * C_MM_S
        # GCC-PHAT sobre el primer burst
        t0 = chan[0][1][0]['sub_samp']; a = int(t0) - 200; b = int(t0) + int(TCH * FS) + 400
        res['inter_channel']['delay_samples_gccphat'] = gcc_phat(chan[0][0][a:b], chan[1][0][a:b])
        if mic_dist_cm:
            res['inter_channel']['max_delay_samples_geom'] = mic_dist_cm * 10 / C_MM_S * FS
    # respuesta en frecuencia + HD por Farina (canal a canal, primer burst)
    for ci, (x, bs, cc) in enumerate(chan):
        res['channels'][ci].update(farina(x, bs[0]['sub_samp'], L))
    return res

def farina(x, sub, L):
    """IR por deconvolucion: conv(grabacion, inverso). Lineal en 0; armonico k en -L*ln(k) s. Devuelve HD2/HD3 y respuesta en 1/3 oct."""
    ref = ref_chirp(); n = len(ref)
    inv = [ref[n - 1 - i] * math.exp(-(i / FS) / L) for i in range(n)]       # inverso: ref invertido x envolvente 1/f
    a = int(sub) - int(0.4 * FS); a = max(a, 0); seg = x[a: int(sub) + n + int(0.3 * FS)]
    N = _nextpow2(len(seg) + n)
    if np is not None:
        ir = np.fft.irfft(np.fft.rfft(np.asarray(seg), N) * np.fft.rfft(np.asarray(inv), N), N).tolist()
    else:
        S = _fft_py(list(seg) + [0] * (N - len(seg))); I = _fft_py(list(inv) + [0] * (N - n))
        ir = [v.real for v in _fft_py([s * i for s, i in zip(S, I)], True)]
    # el pico lineal esta en seg-indice (sub - a) + n - 1
    c = int(sub) - a + n - 1; c = c if c < len(ir) else len(ir) - 1
    pk = max(range(max(0, c - 40), min(len(ir), c + 40)), key=lambda i: abs(ir[i])); c = pk

    def win(centre, half):
        lo = max(0, int(centre - half)); hi = min(len(ir), int(centre + half))
        return math.sqrt(sum(v * v for v in ir[lo:hi])) if hi > lo else 0.0
    HW = 0.002 * FS                          # misma anchura (+-2 ms) para lineal y armonicos
    lin = win(c, HW)
    out = {}
    for k in (2, 3):
        d = L * math.log(k) * FS
        nxt = L * math.log(k + 1) * FS; half = min(HW, 0.4 * (nxt - d))
        h = win(c - d, half)
        out['hd%d_db' % k] = db(h / max(lin, 1e-12))
    # respuesta: |FFT| del IR lineal (ventana 10 ms) en bandas de 1/3 de octava
    m = int(0.010 * FS); lin_ir = [ir[c - 8 + i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / m)) for i in range(m)]
    NN = 1 << 13
    if np is not None:
        H = np.abs(np.fft.rfft(np.asarray(lin_ir), NN)).tolist()
    else:
        H = [abs(v) for v in _fft_py(lin_ir + [0] * (NN - m))[:NN // 2 + 1]]
    fr = {}
    f = 250.0
    while f * 2 ** (1 / 6) < min(F2, FS / 2):
        lo, hi = f / 2 ** (1 / 6), f * 2 ** (1 / 6)
        vs = [H[i] for i in range(len(H)) if lo <= i * FS / NN < hi]
        if vs: fr[int(round(f))] = db(math.sqrt(sum(v * v for v in vs) / len(vs)))
        f *= 2 ** (1 / 3)
    out['response_third_oct_db'] = {str(k): round(v, 1) for k, v in fr.items()}
    return out

# ---------------------------------------------------------------- locate
def locate(spk, dt_ms, speed=343.0):
    """spk: [(x,y)] cm; dt_ms: llegada ch1 - ch0 por altavoz. Busca A,B en [0,W]x[0,H] (caja que envuelve a los altavoces, ampliada)
    que minimicen sum((|B-S|-|A-S|)/c - dt)^2. Devuelve las mejores soluciones (hay ambiguedad espejo/hiperbola)."""
    xs = [s[0] for s in spk]; ys = [s[1] for s in spk]; x0, x1, y0, y1 = min(xs) - 2, max(xs) + 2, min(ys) - 2, max(ys) + 2
    rnd = random.Random(1)
    def cost(p):
        A = (p[0], p[1]); B = (p[2], p[3]); e = 0
        for s, d in zip(spk, dt_ms):
            m = (math.dist(B, s) - math.dist(A, s)) / (speed * 100) * 1000   # ms
            e += (m - d) ** 2
        return e
    sols = []
    for _ in range(300):
        p = [rnd.uniform(x0, x1), rnd.uniform(y0, y1), rnd.uniform(x0, x1), rnd.uniform(y0, y1)]; st = 4.0; c = cost(p)
        while st > 0.02:
            imp = False
            for i in range(4):
                for sgn in (1, -1):
                    q = list(p); q[i] += sgn * st
                    q[i] = min(max(q[i], x0 if i % 2 == 0 else y0), x1 if i % 2 == 0 else y1)
                    cq = cost(q)
                    if cq < c: p, c, imp = q, cq, True
            if not imp: st /= 2
        sols.append((c, p))
    sols.sort(key=lambda t: t[0])
    return [{'rms_err_ms': round(math.sqrt(c / len(dt_ms)), 4), 'A': [round(p[0], 1), round(p[1], 1)], 'B': [round(p[2], 1), round(p[3], 1)]} for c, p in sols[:5]]

# ---------------------------------------------------------------- simulacion / selftest
def simulate(meta, d0_s, d1_s, g0, g1, noise_dbfs=-50, click_dbfs=-20, hd2=0.0, seed=7, tail=0.5, scale_amp=1.0):
    """dos micros: chirp analitico retardado d_s (fraccionario exacto) x ganancia g; + ruido blanco + chasquido de arranque + 2.o armonico."""
    rnd = random.Random(seed); n = int((meta['total_s'] + tail) * FS); out = []
    na = 10 ** (noise_dbfs / 20) * math.sqrt(1)
    for d, g in ((d0_s, g0), (d1_s, g1)):
        x = [0.0] * n
        for t0 in meta['starts_s']:
            i0 = int((t0 + d) * FS) - 2; i1 = i0 + int(TCH * FS) + 6
            for i in range(max(0, i0), min(n, i1)):
                v = chirp_val(i / FS - t0 - d) * g * scale_amp
                x[i] += v + hd2 * v * v
        for i in range(int(0.15 * FS)):   # chasquido: pulso decayente con DC
            x[i] += 10 ** (click_dbfs / 20) * math.exp(-i / (0.02 * FS)) * math.sin(2 * math.pi * 900 * i / FS) + 0.002
        out.append([max(-1, min(1, v + rnd.gauss(0, na))) for v in x])
    return out

def mkmeta(nb, amp_db=-18.0, ch='both'):
    st, P, tot = schedule(nb)
    return {'starts_s': st, 'period_s': P, 'total_s': tot, 'bursts': nb, 'amp_dbfs': amp_db, 'ch': ch,
            'chirp': {'f1': F1, 'f2': F2, 'dur_s': TCH, 'fs': FS}, 'note': 'ch1 - ch0 > 0: ch1 recibe despues'}

def gen_sequence(path, nb, amp_db, ch):
    meta = mkmeta(nb, amp_db, ch); n = int(meta['total_s'] * FS); a = 10 ** (amp_db / 20)
    x = [0.0] * n
    for t0 in meta['starts_s']:
        i0 = int(round(t0 * FS))
        for i in range(int(TCH * FS)): x[i0 + i] = a * chirp_val(i / FS)
    z = [0.0] * n
    chans = {'both': (x, x), 'L': (x, z), 'R': (z, x)}[ch]
    write_wav(path, chans); return meta

def selftest():
    import tempfile
    ok = True
    def chk(name, got, want, tol):
        nonlocal ok; good = abs(got - want) <= tol; ok &= good
        print("  %-34s medido %9.3f  esperado %9.3f  tol %.2f  %s" % (name, got, want, tol, "OK" if good else "FALLA"))
    meta = mkmeta(3)
    # caso 1: mic1 20 cm mas lejos que mic0 + atenuacion 6,0 dB, ruido -50, chasquido -20 dBFS, HD2 1%
    d0 = 0.0043; extra = 4.37 / FS * 1.0 * 0   # (placeholder)
    dly_samples = 37.35                          # retardo diferencial fraccionario
    d1 = d0 + dly_samples / FS
    rec = simulate(meta, d0, d1, 0.30, 0.30 * 10 ** (-6.0 / 20), hd2=0.01)
    tmp = os.path.join(tempfile.gettempdir(), 'uke_selftest.wav'); write_wav(tmp, rec); rec2, _ = read_wav(tmp)
    r = analyze(rec2, meta)
    print("caso 1 (dos micros, retardo %.2f muestras, ratio 6 dB):" % dly_samples)
    chk("retardo ch1-ch0 (filtro adaptado)", r['inter_channel']['delay_samples_mean'], dly_samples, 0.15)
    chk("retardo ch1-ch0 (GCC-PHAT)", r['inter_channel']['delay_samples_gccphat'], dly_samples, 0.5)
    chk("ratio ch0-ch1 dB", r['inter_channel']['ratio_db_ch0_minus_ch1'], 6.0, 0.2)
    chk("ganancia ch0 dB (0,30 = -10,46)", r['channels'][0]['gain_db_mean'], db(0.30), 0.2)
    chk("HD2 ch0 dB (hd2=1%, A=.3: -56,5)", r['channels'][0]['hd2_db'], -56.5, 3.0)
    chk("ruido ch0 dBFS", r['channels'][0]['noise_dbfs'], -50.0, 1.5)
    # caso 2: el chasquido de arranque NO debe confundir el ancla (chasquido -6 dBFS, mas fuerte que el chirp)
    rec = simulate(meta, d0, d1, 0.05, 0.03, click_dbfs=-6)
    r = analyze(rec, meta)
    print("caso 2 (chasquido -6 dBFS > chirp -26 dBFS):")
    chk("retardo con chasquido fuerte", r['inter_channel']['delay_samples_mean'], dly_samples, 0.2)
    # caso 3: SNR bajo (ruido = nivel del chirp)
    rec = simulate(meta, d0, d1, 0.02, 0.02, noise_dbfs=-38)
    r = analyze(rec, meta)
    print("caso 3 (SNR por muestra ~ -4 dB, ganancia de proceso del chirp ~ 45 dB):")
    chk("retardo con ruido alto", r['inter_channel']['delay_samples_mean'], dly_samples, 0.5)
    # caso 4: locate
    spk = [(3, 27), (22, 27), (3, 3), (22, 3)]; A = (13, 1); B = (13, 26)   # A inferior, B superior
    dts = [(math.dist(B, s) - math.dist(A, s)) / 34300 * 1000 for s in spk]
    sol = locate(spk, dts)
    print("caso 4 (locate, 4 altavoces, retardos exactos):", sol[0])
    chk("error de ajuste ms", sol[0]['rms_err_ms'], 0.0, 0.01)
    print("RESULTADO:", "VERDE" if ok else "ROJO"); return 0 if ok else 1

def main():
    ap = argparse.ArgumentParser(); sp = ap.add_subparsers(dest='cmd', required=True)
    g = sp.add_parser('gen'); g.add_argument('out'); g.add_argument('--bursts', type=int, default=3); g.add_argument('--amp', type=float, default=-18.0)
    g.add_argument('--ch', default='both', choices=['both', 'L', 'R']); g.add_argument('--out-json')
    a = sp.add_parser('analyze'); a.add_argument('wav'); a.add_argument('--meta', required=True); a.add_argument('--mic-dist-cm', type=float)
    l = sp.add_parser('locate'); l.add_argument('--speakers', required=True); l.add_argument('--dt', required=True)
    sp.add_parser('selftest')
    o = ap.parse_args()
    if o.cmd == 'gen':
        m = gen_sequence(o.out, o.bursts, o.amp, o.ch); json.dump(m, open(o.out_json or o.out + '.json', 'w'), indent=1); print("escrito", o.out, "total %.1f s" % m['total_s'])
    elif o.cmd == 'analyze':
        rec, fs = read_wav(o.wav); assert fs == FS, "se espera 48 kHz"
        print(json.dumps(analyze(rec, json.load(open(o.meta)), o.mic_dist_cm), indent=1))
    elif o.cmd == 'locate':
        spk = [tuple(map(float, p.split(','))) for p in o.speakers.split(';')]; dt = list(map(float, o.dt.split(',')))
        print(json.dumps(locate(spk, dt), indent=1))
    else:
        sys.exit(selftest())

if __name__ == '__main__':
    main()
