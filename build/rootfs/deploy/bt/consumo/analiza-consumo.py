#!/usr/bin/env python3
"""analiza-consumo.py — analiza el registro de bt-consumo.sh (lineas FASE y SUSP).

Despierto: cada fase se compara con la MEDIA de las dos bases vecinas (antes y despues); la incertidumbre suma el error tipico de la fase, el de las bases y la
deriva entre ellas (|b1-b2|/2). Por fase se promedian las repeticiones. Criterio de la sesion de bateria: |delta| < 0,1 W o < 2 sigma = no significativo.
Suspension: W = (q0 - q1)[uAh]·1e-6 · V[V] / (dur[s]/3600), por suspension; mismo esquema (s_hook como base intercalada). Se descartan (se marcan) las filas con
USB conectado (usb_w > 0,3 W: el contador mezcla carga y consumo) o con un despertar distinto del habitual (pm_wakeup_irq: debe ser el de la alarma RTC).
Uso: analiza-consumo.py LOG [--umbral 0.1]
"""
import argparse, math, re, statistics as st, sys
from collections import Counter, defaultdict

def kv(line):
    return dict(x.split('=', 1) for x in line.split()[1:] if '=' in x)

def agg(vals):  # vals: lista de (delta, sigma) -> (media, sigma_total)
    d = [v[0] for v in vals]
    m = st.mean(d)
    s_in = math.sqrt(sum(v[1] ** 2 for v in vals)) / len(vals)
    s_out = (st.stdev(d) / math.sqrt(len(d))) if len(d) > 1 else 0.0
    return m, max(s_in, s_out)

def veredicto(m, s, umbral):
    return 'no significativo' if abs(m) < umbral or abs(m) < 2 * s else ('MAS consumo' if m > 0 else 'MENOS consumo')

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('log'); ap.add_argument('--umbral', type=float, default=0.1); a = ap.parse_args()
    F = []; S = []
    for l in open(a.log, encoding='utf-8', errors='replace'):
        if l.startswith('FASE'): F.append(kv(l))
        elif l.startswith('SUSP'): S.append(kv(l))
    rc = 0
    if F:
        deltas = defaultdict(list); bases = [float(f['sys_w']) for f in F if f['name'] == 'base' and f.get('sys_w') not in (None, 'None')]
        for i, f in enumerate(F):
            if f['name'] == 'base' or i == 0 or i == len(F) - 1: continue
            b1, b2 = F[i - 1], F[i + 1]
            if b1['name'] != 'base' or b2['name'] != 'base': continue
            w, e = float(f['sys_w']), float(f['sys_sem'] or 0); w1, e1, w2, e2 = float(b1['sys_w']), float(b1['sys_sem'] or 0), float(b2['sys_w']), float(b2['sys_sem'] or 0)
            sig = math.sqrt(e ** 2 + (e1 ** 2 + e2 ** 2) / 4 + ((w1 - w2) / 2) ** 2)
            deltas[f['name']].append((w - (w1 + w2) / 2, sig))
        print('DESPIERTO (potencia del sistema en W; delta frente a la media de las dos bases vecinas)')
        if bases: print(f"  base: {len(bases)} medidas, media {st.mean(bases):.3f} W, sigma {st.stdev(bases) if len(bases) > 1 else 0:.3f} W")
        print(f"  {'fase':10s} {'n':>2s} {'delta W':>9s} {'± sigma':>8s}  veredicto")
        for name, v in sorted(deltas.items()):
            m, s = agg(v); print(f"  {name:10s} {len(v):2d} {m:+9.3f} {s:8.3f}  {veredicto(m, s, a.umbral)}")
    if S:
        irq = Counter(s.get('wake_irq') for s in S).most_common(1)[0][0]
        rows = []
        for s in S:
            try:
                dq = float(s['q0_uah']) - float(s['q1_uah']); v = float(s['v_uv']) / 1e6; dur = float(s['dur_s']); usb = float(s.get('usb_w', 0))
            except (KeyError, ValueError): continue
            ok = usb <= 0.3 and s.get('wake_irq') == irq and dur > 0
            rows.append(dict(name=s['name'], rep=s.get('rep'), w=(dq * 1e-6 * v) / (dur / 3600) if dur > 0 else float('nan'), ok=ok, usb=usb, irq=s.get('wake_irq'), dur=dur))
        print(f"\nSUSPENSION (s2idle con alarma RTC; despertar habitual = IRQ {irq}); {sum(1 for r in rows if not r['ok'])} fila(s) descartada(s) por USB o despertar distinto")
        for r in rows:
            if not r['ok']: print(f"  DESCARTADA {r['name']} rep={r['rep']}: usb_w={r['usb']} wake_irq={r['irq']} dur={r['dur']}")
        good = [r for r in rows if r['ok']]
        print(f"  {'variante':10s} {'n':>2s} {'W medio':>9s} {'± sem':>7s}")
        for name in sorted({r['name'] for r in good}):
            w = [r['w'] for r in good if r['name'] == name]
            print(f"  {name:10s} {len(w):2d} {st.mean(w):9.4f} {(st.stdev(w) / math.sqrt(len(w)) if len(w) > 1 else 0):7.4f}")
        d2 = defaultdict(list)
        for i, r in enumerate(rows):
            if r['name'] == 's_hook' or i == 0 or i == len(rows) - 1 or not r['ok']: continue
            b1, b2 = rows[i - 1], rows[i + 1]
            if b1['name'] != 's_hook' or b2['name'] != 's_hook' or not (b1['ok'] and b2['ok']): continue
            d2[r['name']].append((r['w'] - (b1['w'] + b2['w']) / 2, abs(b1['w'] - b2['w']) / 2))
        for name, v in sorted(d2.items()):
            m, s = agg(v); print(f"  delta {name} - s_hook: {m:+.4f} W ± {s:.4f}  ({len(v)} par(es)): {veredicto(m, s, a.umbral / 10)}")
        print("  (el umbral de significacion en suspension es la decima parte del de despierto: ~0,01 W; el contador de carga manda)")
    if not F and not S: print('sin lineas FASE ni SUSP'); rc = 1
    return rc

if __name__ == '__main__': sys.exit(main())
