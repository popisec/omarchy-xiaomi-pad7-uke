#!/usr/bin/env python3
"""Escenarios extra de simulacion (demonio REAL + validador kernel-like) y fuzzing reproducible para palm_android (21-oct-2026).
Reusa sim_palma.run/kernel/downs. Un frame = 1/226 s. Uso: python3 sim_extra.py  (tabla de escenarios y latencias en ms simulados).
Los asserts estan en test_sim_extra.py. Los helpers de tiempo/latencia estan aqui: lat(out, marks, fase) = ms desde el primer frame de la
fase hasta el primer `down` (TRACKING_ID >= 0) emitido; None si no hay down."""
import os, random, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sim_palma as S
H, A, DT = S.H, S.H.A, S.DT

# --- cache del build (cada run() parcheaba el demonio de nuevo: ~0,3 s) -----------------------------------------------------
_build = S.build
_cache = {}


def _cached(extra_patches=(), base_patch=None):
    if "p" not in _cache:
        _cache["p"] = _build(extra_patches, base_patch)
    return _cache["p"]


S.H.build = _cached


def ms(x):
    return max(0, int(round(x / (DT * 1e3))))


def frame_ms(n):
    return n * DT * 1e3


# --- constructores de frames ------------------------------------------------------------------------------------------------
KINDS = {"f": 9, "m": 5, "s": 1}      # area del tracker (nodos >= thr_on en el 3x3): dedo completo, cruz, solo centro


def F(contacts=(), off=0):
    """contacts = [(fila, col[, tipo])] en nodos; tipo 'f' (area 9, por defecto), 'm' (5), 's' (1)."""
    base = bytearray(H.finger_frame([]))
    g = [10000 + off] * (A.ROWS * A.COLS)
    for c in contacts:
        r, cc, k = (c + ("f",))[:3]
        for dr in (-1, 0, 1):
            for dc in (-1, 0, 1):
                rr, c2 = r + dr, cc + dc
                if not (0 <= rr < A.ROWS and 0 <= c2 < A.COLS):
                    continue
                cross = (dr == 0) != (dc == 0)
                if (dr, dc) == (0, 0):
                    g[rr * A.COLS + c2] += 1300
                elif k == "f" or (k == "m" and cross):
                    g[rr * A.COLS + c2] += 450
    struct.pack_into("<%dH" % len(g), base, 0x40, *g)
    return bytes(base)


def NOISE(n=1):
    """frame 0x509 sin lapiz presente (amp 20 < umbral): el chip los intercala; no deben activar el rechazo"""
    import test_lapiz as TL
    one = bytes(TL.synth(amp=20)); one += bytes(max(0, 0x40 + 2 * A.ROWS * A.COLS - len(one)))
    return [one] * n


IDLE = S.IDLE


def PEN(n, contact=16):
    """n frames de lapiz iguales (objeto compartido: las rafagas de minutos no gastan memoria)"""
    return [H.pen_frame(contact)] * n


HOVER = lambda n: PEN(n, 0)                       # noqa: E731
HOLD = lambda n, c, off=0: [F(c, off) for _ in range(n)]   # noqa: E731


def MOVE(n, a, b):
    """n frames; cada contacto i va de a[i] a b[i] (fila,col) en pasos de nodo (entero) -> hay desplazamiento > 8 px en cuanto cambia el nodo"""
    out = []
    for i in range(n):
        t = i / max(1, n - 1)
        out.append(F([(round(p[0] + (q[0] - p[0]) * t), round(p[1] + (q[1] - p[1]) * t)) + tuple(p[2:]) for p, q in zip(a, b)]))
    return out


def MIX(n, k, contacts_at, contact=16):
    """n repeticiones de (k frames de lapiz + 1 frame de dedos con contacts_at(i))"""
    f = []
    for i in range(n):
        f += PEN(k, contact) + [F(contacts_at(i))]
    return f


def seq(parts):
    f, m = [], {}
    for key, fr in parts:
        m[key] = (len(f), len(f) + len(fr)); f += fr
    return f, m


def lat(out, marks, key, nth=0):
    """ms simulados entre el inicio de la fase y su n-esimo down (None si no hay)"""
    d = S.downs(out, *marks[key])
    return None if len(d) <= nth else round((d[nth] - marks[key][0]) * DT * 1e3, 1)


def pos_at(out, idx):
    """(x, y) de la posicion de slot emitida en el SYN del frame de entrada idx (la primera si hay varias)"""
    for i, fr in out:
        if i == idx:
            xs = [v for t, c, v in fr if t == H.EV_ABS and c == 0x35]
            ys = [v for t, c, v in fr if t == H.EV_ABS and c == 0x36]
            if xs and ys:
                return xs[0], ys[0]
    return None


def first_down_pos(out, marks, key):
    d = S.downs(out, *marks[key])
    return pos_at(out, d[0]) if d else None


def ups(out, lo=0, hi=10 ** 9):
    return [i for i, fr in out if lo <= i < hi for t, c, v in fr if t == H.EV_ABS and c == H.TID and v == -1]


def n_down(out, marks, key):
    return len(S.downs(out, *marks[key]))


PALM = [(10, 10)]


def scenarios():
    X = {}
    # ---- 1. escritura larga con la palma apoyada que se mueve ---------------------------------------------------------------
    # A) como el chip real: rafaga continua, la palma se arrastra durante ella; tras la rafaga el primer frame de dedos la trae desplazada
    for drift in (0, 1, 2, 4, 8):
        X["arrastre_post_rafaga_d%d" % drift] = seq([("idle", IDLE(12)), ("palma0", HOLD(2, PALM)), ("pen", PEN(260)),
            ("palma", HOLD(60, [(10 + drift, 10 + drift)])), ("fin", IDLE(20))]) + ("palma",)
    # B) hipotesis desfavorable: el chip intercala un frame de dedos cada k de lapiz; la palma avanza 1 nodo cada `step` frames de dedos
    for k, step in ((2, 6), (4, 3), (8, 2)):
        X["arrastre_intercalado_k%d_s%d" % (k, step)] = seq([("idle", IDLE(12)), ("pen", MIX(200, k, lambda i, s=step: [(10 + i // s, 10 + i // s)])),
            ("palma", HOLD(40, [(10 + 200 // step, 10 + 200 // step)])), ("fin", IDLE(20))]) + ("pen",)
    # ---- 2. palma que se levanta y vuelve varias veces durante la escritura -------------------------------------------------
    for gap in (30, 60, 90, 200):
        parts = [("idle", IDLE(12)), ("palma0", HOLD(2, PALM))]
        for i in range(6):
            parts += [("pen%d" % i, PEN(60)), ("hueco%d" % i, IDLE(ms(gap))), ("palma%d" % i, HOLD(30, PALM))]
        parts += [("fin", IDLE(20))]
        X["palma_va_y_viene_gap%d" % gap] = seq(parts) + ("palma0",)

    # ---- 3. dedo legitimo con el lapiz en hover / recien levantado ----------------------------------------------------------
    # (el chip real no intercala dedos dentro de la rafaga: el dedo aparece tras el ultimo frame de lapiz, dentro o fuera del margen de 100 ms)
    FINGER_MOV = lambda: MOVE(40, [(20, 20)], [(30, 20)])                     # noqa: E731  (10 nodos = 530 px en 176 ms)
    for tag, contact in (("hover", 0), ("escritura", 16)):
        for gap in (0, 20, 50, 90, 120, 200, 500):
            X["dedo_quieto_%s_gap%d" % (tag, gap)] = seq([("idle", IDLE(12)), ("pen", PEN(60, contact)), ("hueco", IDLE(ms(gap))),
                                                        ("dedo", HOLD(40, [(20, 20)])), ("fin", IDLE(20))]) + ("dedo",)
            X["dedo_mueve_%s_gap%d" % (tag, gap)] = seq([("idle", IDLE(12)), ("pen", PEN(60, contact)), ("hueco", IDLE(ms(gap))),
                                                       ("dedo", FINGER_MOV()), ("fin", IDLE(20))]) + ("dedo",)
    for gap in (20, 60):
        X["scroll2_tras_lapiz_gap%d" % gap] = seq([("idle", IDLE(12)), ("pen", PEN(60)), ("hueco", IDLE(ms(gap))),
            ("dedo", MOVE(40, [(15, 20), (15, 30)], [(25, 20), (25, 30)])), ("fin", IDLE(20))]) + ("dedo",)
        X["pellizco_tras_lapiz_gap%d" % gap] = seq([("idle", IDLE(12)), ("pen", PEN(60)), ("hueco", IDLE(ms(gap))),
            ("dedo", [F(p) for p in H.pinch()]), ("fin", IDLE(20))]) + ("dedo",)
        X["gesto3_tras_lapiz_gap%d" % gap] = seq([("idle", IDLE(12)), ("pen", PEN(60)), ("hueco", IDLE(ms(gap))),
            ("dedo", MOVE(50, [(30, 15), (30, 30), (30, 45)], [(14, 15), (14, 30), (14, 45)])), ("fin", IDLE(20))]) + ("dedo",)
        # borde: 1 dedo nace en el borde (fila 0) y entra 220+ px
        X["borde_entra_tras_lapiz_gap%d" % gap] = seq([("idle", IDLE(12)), ("pen", PEN(60)), ("hueco", IDLE(ms(gap))),
            ("dedo", MOVE(30, [(0, 30)], [(8, 30)])), ("fin", IDLE(20))]) + ("dedo",)
    X["borde_entra_sin_lapiz"] = seq([("idle", IDLE(12)), ("dedo", MOVE(30, [(0, 30)], [(8, 30)])), ("fin", IDLE(20))]) + ("dedo",)
    # ---- 4. lapiz entrando y saliendo de rango en rapida sucesion -----------------------------------------------------------
    for gap in (2, 10, 40, 90):
        parts = [("idle", IDLE(12)), ("palma", HOLD(2, PALM))]
        parts += sum(([("p%d" % i, PEN(3 + i % 4)), ("h%d" % i, [F(PALM) for _ in range(max(1, ms(gap)))])] for i in range(40)), [])
        parts += [("fin", IDLE(20))]
        X["lapiz_parpadea_gap%d_con_palma" % gap] = seq(parts) + ("palma",)
    X["lapiz_parpadea_dedo_mueve"] = seq([("idle", IDLE(12))] + sum(([("p%d" % i, PEN(4)), ("h%d" % i, MOVE(6, [(10 + i // 2, 20)], [(11 + i // 2, 20)]))] for i in range(30)), []) + [("fin", IDLE(20))]) + ("p0",)
    # ---- 5. frames 0x509 de ruido aislados (lapiz NO presente): no activan el rechazo ---------------------------------------
    f = [x for i in range(40) for x in (HOLD(4, [(20, 20)]) + NOISE(1))]
    X["ruido_aislado_dedo_continuo"] = seq([("idle", IDLE(12)), ("dedo", f), ("fin", IDLE(20))]) + ("dedo",)
    X["ruido_aislado_toque_nuevo"] = seq([("idle", IDLE(12)), ("n", NOISE(1)), ("dedo", HOLD(30, [(20, 20)])), ("fin", IDLE(20))]) + ("dedo",)
    X["ruido_bajo_hover_palma"] = seq([("idle", IDLE(12)), ("pen", PEN(40)), ("palma", [x for i in range(30) for x in (HOLD(3, PALM) + NOISE(1))]), ("fin", IDLE(20))]) + ("palma",)
    # ---- 5b. ruido aislado con un dedo que ya paso (el tid cambia en cada tr.reset(): el estado debe sobrevivir) ----------------
    f = [x for i in range(25) for x in (MOVE(8, [(12 + i, 20)], [(13 + i, 20)]) + NOISE(1))]
    X["ruido_dedo_mueve_tras_lapiz"] = seq([("idle", IDLE(12)), ("pen", PEN(60)), ("hueco", IDLE(ms(20))), ("dedo", f), ("fin", IDLE(20))]) + ("dedo",)
    # palma baneada que sigue apoyada cuando el lapiz ya se fue (>100 ms) y llegan 0x509 de ruido (tr.reset() => tid nuevo): no debe soltar un toque
    f = [x for i in range(20) for x in (HOLD(9, PALM) + NOISE(1))]
    X["palma_baneada_con_ruido_tras_lapiz"] = seq([("idle", IDLE(12)), ("pen", PEN(60)), ("palma", HOLD(30, PALM)), ("resto", f), ("fin", IDLE(20))]) + ("resto",)
    # ---- 3b. dedo pequeno (area 5) quieto justo tras el lapiz: candidato a liberar el ban (M1) -------------------------------------
    for k in ("m", "f"):
        X["dedo_quieto_area_%s_gap20_largo" % k] = seq([("idle", IDLE(12)), ("pen", PEN(60)), ("hueco", IDLE(ms(20))),
            ("dedo", HOLD(226, [(20, 20, k)])), ("fin", IDLE(20))]) + ("dedo",)
    # ---- 6. 10 dedos --------------------------------------------------------------------------------------------------------
    TEN = [(3 + 4 * (i % 5), 6 + 24 * (i // 5)) for i in range(10)]
    X["diez_dedos_sin_lapiz"] = seq([("idle", IDLE(12)), ("dedo", HOLD(30, TEN)), ("fin", IDLE(20))]) + ("dedo",)
    X["diez_dedos_con_hover"] = seq([("idle", IDLE(12)), ("pen", PEN(40, 0)), ("hueco", IDLE(ms(20))), ("dedo", HOLD(40, TEN)), ("fin", IDLE(20))]) + ("dedo",)
    X["diez_dedos_moviendose_con_hover"] = seq([("idle", IDLE(12)), ("pen", PEN(40, 0)), ("hueco", IDLE(ms(20))),
        ("dedo", MOVE(40, TEN, [(r + 4, c) for r, c in TEN])), ("fin", IDLE(20))]) + ("dedo",)
    # ---- 7. dedos que entran y salen con tids reutilizados (el Tracker reasigna ids tras reset) ---------------------------------
    parts = [("idle", IDLE(12))]
    for i in range(20):
        parts += [("t%d" % i, HOLD(8, [(20, 20)] + ([(10, 40)] if i % 2 else []))), ("i%d" % i, IDLE(3)), ("pen%d" % i, PEN(2) if i % 5 == 4 else [])]
    X["tids_reutilizados"] = seq(parts + [("fin", IDLE(20))]) + ("t0",)
    # ---- 8. rafaga de lapiz muy larga (minutos simulados) ------------------------------------------------------------------------
    X["rafaga_larga_2min"] = seq([("idle", IDLE(12)), ("palma0", HOLD(2, PALM)), ("pen", PEN(226 * 120)), ("palma", HOLD(40, [(12, 12)])),
                                  ("fin", IDLE(40)), ("dedo", HOLD(30, [(20, 20)])), ("fin2", IDLE(20))]) + ("palma",)
    return X


# --- fuzzing reproducible --------------------------------------------------------------------------------------------------------
def _spaced(rng, k):
    """k posiciones (fila, col) separadas >= 5 nodos"""
    pts = []
    while len(pts) < k:
        c = (rng.randrange(0, A.ROWS), rng.randrange(0, A.COLS))
        if all(abs(c[0] - p[0]) >= 5 or abs(c[1] - p[1]) >= 5 for p in pts):
            pts.append(c)
    return pts


def random_timeline(seed, n_segments=60):
    """secuencia aleatoria (semilla fija = reproducible) de segmentos: reposo, lapiz (hover/punta), ruido 0x509, dedos quietos/en movimiento
    (1..10), mezcla lapiz+dedo, palma. Devuelve la lista de frames."""
    rng = random.Random(seed)
    f = IDLE(8)
    for _ in range(n_segments):
        kind = rng.choice(["idle", "pen", "pen", "noise", "hold", "hold", "move", "mix", "palm", "blink"])
        if kind == "idle":
            f += IDLE(rng.randrange(1, 70))
        elif kind == "pen":
            f += PEN(rng.randrange(1, 90), rng.choice([0, 16]))
        elif kind == "noise":
            f += NOISE(rng.randrange(1, 4))
        elif kind == "hold":
            f += HOLD(rng.randrange(1, 60), _spaced(rng, rng.choice([1, 1, 2, 3, 5, 10])))
        elif kind == "move":
            k = rng.choice([1, 2, 3, 10])
            a = _spaced(rng, k)
            b = [(min(A.ROWS - 1, max(0, r + rng.randrange(-12, 13))), min(A.COLS - 1, max(0, c + rng.randrange(-12, 13)))) for r, c in a]
            f += MOVE(rng.randrange(2, 50), a, b)
        elif kind == "mix":
            p = _spaced(rng, rng.choice([1, 2]))
            f += MIX(rng.randrange(1, 25), rng.randrange(1, 8), lambda i, p=p: p, rng.choice([0, 16]))
        elif kind == "palm":
            f += HOLD(rng.randrange(1, 40), [(rng.randrange(5, 30), rng.randrange(5, 50))])
        else:
            for _ in range(rng.randrange(2, 10)):
                f += PEN(rng.randrange(1, 5)) + IDLE(rng.randrange(1, 12))
    return f + IDLE(40)


def fuzz_demon(seed, **kw):
    """ejecuta el demonio real con la secuencia de la semilla. Devuelve (violaciones, max dedos, n eventos, n downs)"""
    out, _ = S.run(random_timeline(seed), **kw)
    mx, viol = S.kernel(out)
    return viol, mx, len(out), len(S.downs(out))


def fuzz_pure(seed, n=4000, **kw):
    """logica pura con tids reutilizados (pool de 12), saltos de reloj, pen_frame/tracker_reset aleatorios y lifts en cualquier frame.
    Comprueba invariantes en cada paso; devuelve (max len(rec), max len(ghosts), stats)."""
    import palm_android as P
    rng = random.Random(seed)
    p = P.AndroidPalm(**kw)
    t, mr, mg = 100.0, 0, 0
    live = {}
    for _ in range(n):
        t += rng.choice([DT] * 8 + [0.003, 0.006, 0.12, 2.0])
        r = rng.random()
        if r < 0.25:
            p.pen_frame(t); live = {}                       # el demonio hace tr.reset(): los tids se renuevan
        elif r < 0.30:
            p.tracker_reset(t); live = {}
        if rng.random() < 0.2 and live:
            live.pop(rng.choice(list(live)))
        if rng.random() < 0.3 and len(live) < 10:
            live[rng.randrange(12)] = (rng.randrange(0, 2136), rng.randrange(0, 3200))
        pts = []
        for tid, (x, y) in list(live.items()):
            if rng.random() < 0.3:
                x, y = max(0, min(2135, x + rng.randrange(-20, 21))), max(0, min(3199, y + rng.randrange(-20, 21)))
                live[tid] = (x, y)
            pts.append((tid, x, y, rng.randrange(1, 10)))
        out = p.filter(pts, t, rng.random() < 0.5)
        ids = {q[0] for q in pts}
        assert len(set(o[0] for o in out)) == len(out), "tid duplicado en la salida"
        assert len(p.rec) <= len(pts) and len(p.ghosts) <= p.max_ghosts, (len(p.rec), len(p.ghosts))
        mr, mg = max(mr, len(p.rec)), max(mg, len(p.ghosts))
    for _ in range(10):                                     # todo levantado y sin lapiz: ningun contacto atascado
        t += 0.2
        p.filter([], t, False)
    assert not p.rec
    return mr, mg, dict(p.stats)


def report():
    for name, v in scenarios().items():
        f, m = v[0], v[1]
        out, _ = S.run(f)
        mx, viol = S.kernel(out)
        print("%-34s viol %d  max %d  downs %s" % (name, len(viol), mx, [round(i * DT * 1e3) for i in S.downs(out)][:8]))


if __name__ == "__main__":
    report()
