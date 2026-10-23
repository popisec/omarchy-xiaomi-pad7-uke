#!/usr/bin/env python3
"""analiza-medicion.py — analiza el registro de bt-medir.sh (lineas `CICLO ronda=R cfg=L:B:S rc=0 timeouts=T ok=1 rise_us=N dur_s=D`).

Por configuracion: ciclos, 1.er intento OK (timeouts==0 y ok), recuperados por reintento del driver (ok con timeouts>0), mudos (ok=0), intentos y exito por intento,
intervalo de Wilson 95 % del 1.er intento OK y p-valor exacto de Fisher (dos colas) frente al CONTROL (por defecto 50:50:0) sobre «1.er intento OK».
Si hay rise_us (SW_CTRL sondeado), muestra su distribucion y la separa por resultado del 1.er intento (para contrastar la hipotesis de carrera:
 si los fallos se concentran en subidas lentas, el comando sale antes de que el chip este listo).
Uso: analiza-medicion.py LOG [--control 50:50:0] [--min-ciclos 10]
"""
import argparse, math, re, statistics, sys
from collections import defaultdict

def wilson(k, n, z=1.96):
    if n == 0: return (0.0, 0.0)
    p = k / n; d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d; h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))

def fisher(a, b, c, d):  # tabla [[a,b],[c,d]] ; p dos colas exacta (suma de probabilidades <= la observada)
    n1, n2, k = a + b, c + d, a + c
    def pr(x): return math.comb(n1, x) * math.comb(n2, k - x) / math.comb(n1 + n2, k)
    lo, hi = max(0, k - n2), min(n1, k); p0 = pr(a)
    return min(1.0, sum(pr(x) for x in range(lo, hi + 1) if pr(x) <= p0 * (1 + 1e-9)))

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('log'); ap.add_argument('--control', default='50:50:0'); ap.add_argument('--min-ciclos', type=int, default=10)
    a = ap.parse_args()
    rows = []
    for l in open(a.log, encoding='utf-8', errors='replace'):
        if not l.startswith('CICLO'): continue
        d = dict(kv.split('=', 1) for kv in l.split()[1:] if '=' in kv)
        try: rows.append((d['cfg'], int(d['timeouts']), int(d['ok']), None if d.get('rise_us', '-') == '-' else int(d['rise_us'])))
        except (KeyError, ValueError): print('linea ignorada:', l.strip()[:100], file=sys.stderr)
    if not rows: print('sin lineas CICLO'); return 1
    by = defaultdict(list)
    for r in rows: by[r[0]].append(r)
    S = {}
    for cfg, R in by.items():
        n = len(R); f1 = sum(1 for _, t, ok, _ in R if ok and t == 0); rec = sum(1 for _, t, ok, _ in R if ok and t > 0); mute = sum(1 for _, t, ok, _ in R if not ok)
        fails = sum(t for _, t, _, _ in R); succ = sum(1 for _, _, ok, _ in R if ok)
        S[cfg] = dict(n=n, f1=f1, rec=rec, mute=mute, fails=fails, succ=succ)
    ctl = S.get(a.control)
    print(f"{'config L:B:S':14s} {'ciclos':>6s} {'1.er OK':>8s} {'%':>5s} {'IC95 Wilson':>14s} {'recup.':>6s} {'mudos':>5s} {'exito/intento':>13s} {'p(Fisher) vs ' + a.control:>20s}")
    for cfg in sorted(S, key=lambda c: (c != a.control, c)):
        s = S[cfg]; lo, hi = wilson(s['f1'], s['n']); att = s['fails'] + s['succ']
        p = '-' if (cfg == a.control or not ctl) else f"{fisher(s['f1'], s['n'] - s['f1'], ctl['f1'], ctl['n'] - ctl['f1']):.3f}"
        print(f"{cfg:14s} {s['n']:6d} {s['f1']:8d} {100 * s['f1'] / s['n']:4.0f}% {f'[{lo:.0%}-{hi:.0%}]':>14s} {s['rec']:6d} {s['mute']:5d} {100 * s['succ'] / att:12.0f}% {p:>20s}")
    rise = [(t, ok, r) for _, t, ok, r in rows if r is not None]
    if rise:
        ok1 = [r for t, ok, r in rise if ok and t == 0]; bad1 = [r for t, ok, r in rise if not (ok and t == 0)]
        def desc(x): return f"n={len(x)} min={min(x)} mediana={int(statistics.median(x))} max={max(x)} us" if x else 'n=0'
        print('\nSW_CTRL (us desde BT_EN alto hasta SW_CTRL=1; solo ciclos con sondeo):')
        print('  1.er intento OK :', desc(ok1)); print('  1.er intento MAL:', desc(bad1))
        if ok1 and bad1: print('  -> si MAL tiene subidas claramente mayores que OK, el fallo es una carrera con el arranque del chip; si se solapan, la causa es otra (p. ej. el estado de la UART del host).')
    ok_cfgs = [c for c, s in S.items() if c != a.control and s['n'] >= a.min_ciclos and ctl and ctl['n'] >= a.min_ciclos]
    print()
    if not ctl or ctl['n'] < a.min_ciclos: print(f"AVISO: el control {a.control} tiene menos de {a.min_ciclos} ciclos: conclusiones debiles.")
    for c in ok_cfgs:
        s = S[c]; p = fisher(s['f1'], s['n'] - s['f1'], ctl['f1'], ctl['n'] - ctl['f1'])
        better = s['f1'] / s['n'] > ctl['f1'] / ctl['n']
        print(f"  {c}: {'MEJORA' if better and p < 0.05 else ('mejora no significativa' if better else 'sin mejora')} (1.er OK {s['f1']}/{s['n']} vs control {ctl['f1']}/{ctl['n']}, p={p:.3f}; mudos {s['mute']} vs {ctl['mute']})")
    return 0

if __name__ == '__main__': sys.exit(main())
