#!/usr/bin/env python3
"""palm_android.py - rechazo de palma estilo Android para uke-touchd (21-oct-2026). Logica PURA (sin E/S, reloj inyectado), NO desplegada.

Modelo de Android (build/android/lapiz-20261019/binarios/stylus_palm_reject_config.json): weakModeDelayTime 40 ms,
strongModeDelayTime 64 ms, move threshold 8 (HIPOTESIS: pixeles del panel; en pantalla Linux 3200x2136 coincide 1:1 con los px
nativos 2136x3200 porque la escala de Android es 10 u por px; jitter medido de un dedo quieto con thp_algo: <= 2 px, 18-oct).

Reglas (cada dedo es un contacto con registro propio; los pts llegan en px de pantalla: (tid, x, y, area)):
  activo = el lapiz dio un frame 0x509 «presente» hace <= margin, o la punta toca (BLE/chip)  [= ABS_DISTANCE de Android]
  A. contacto NUEVO sin lapiz activo         -> pasa YA (sin retardo).
  B. contacto NUEVO con lapiz activo         -> PENDIENTE: no se emite. A los 40 ms (lapiz solo en hover) / 64 ms (punta tocando):
        se movio > thr  -> dedo (pasa, desde la posicion actual);  no se movio y el lapiz sigue activo -> PALMA (ban);
        el lapiz ya no esta activo -> dedo.  Si se levanta antes del plazo: con hover y quieto se re-emite como TOQUE de 1 frame
        (tap_replay); con la punta tocando se descarta.
  C. dedo que entro <= pre_ms ANTES del primer frame del lapiz y no se movio > thr -> PALMA (el demonio ya lo solto con la rafaga).
  D. continuidad: tr.reset() en cada frame de lapiz reinicia el Tracker (ids nuevos, ban por tid inutil). Al llegar un frame de
     lapiz el estado de cada contacto pasa a «fantasma» (posicion+estado) y un contacto nuevo a <= ghost_px de un fantasma vivo
     (<= margin tras el ultimo frame de lapiz) HEREDA su estado. Sin fantasma: el PRIMER frame de dedos tras una rafaga >= min_burst
     que trae un contacto = palma que ya estaba apoyada -> ban.
  E. NO hay bloqueo por tiempo: un contacto con ban vive baneado mientras el mismo contacto siga vivo; un contacto nuevo tras
     margin sin lapiz pasa sin retardo. Pellizco de 2 dedos sin lapiz: regla A, identico a sin modulo.
NO declara ABS_MT_TOOL_TYPE ni emite MT_TOOL_*: solo decide que pts se emiten; el demonio hace el resto (SLOT explicito, -1 por slot)."""
import math

PASS, PEND, BAN = "pass", "pend", "ban"


class _Rec:
    __slots__ = ("state", "t0", "x0", "y0", "x", "y", "area", "moved", "strong", "amax", "tban", "replay")

    def __init__(self, t0, x, y, area, state):
        self.state, self.t0, self.x0, self.y0, self.x, self.y, self.area = state, t0, x, y, x, y, area
        self.moved, self.strong = 0.0, False
        self.amax, self.tban, self.replay = area, None, False


class AndroidPalm:
    def __init__(self, weak_ms=40, strong_ms=64, move_px=8, pre_ms=64, margin_ms=100, ghost_px=120, carry_ms=30,
                 min_burst_ms=100, tap_replay=True, burst_gap_ms=50, replay_start=True, release_ms=0, release_area=6, max_ghosts=16):
        self.weak, self.strong, self.move = weak_ms / 1e3, strong_ms / 1e3, move_px
        self.pre, self.margin, self.ghost_px = pre_ms / 1e3, margin_ms / 1e3, ghost_px
        self.carry, self.min_burst, self.tap_replay, self.burst_gap = carry_ms / 1e3, min_burst_ms / 1e3, tap_replay, burst_gap_ms / 1e3
        self.replay_start = replay_start      # al pasar a dedo tras moverse, el 1.er frame sale en la posicion DONDE EMPEZO (bordes de uke-gestures)
        self.release_ms, self.release_area = release_ms / 1e3, release_area   # M1 (0 = apagado): ver abajo
        self.max_ghosts = max_ghosts
        self.rec = {}                 # tid -> _Rec (solo contactos vivos en el Tracker actual)
        self.ghosts = []              # [[x, y, _Rec, t_visto]]
        self.last_pen = None
        self.burst_start = None
        self._calls_since_pen = 1
        self.stats = {"palm": 0, "pre": 0, "carry": 0, "inherit": 0, "tap": 0, "dropped_tap": 0, "pass_moved": 0, "delayed": 0, "released": 0, "resets": 0}

    # --- estado del lapiz -------------------------------------------------------------------------------------------------
    def pen_active(self, now, touching=False):
        return touching or (self.last_pen is not None and now - self.last_pen <= self.margin)

    def pen_frame(self, now):
        """Llamar con CADA frame 0x509 con lapiz presente (en el demonio justo tras rt.on_frame, antes de tr.reset ya hecho)."""
        if self.last_pen is None or now - self.last_pen > self.burst_gap:
            self.burst_start = now
            for r in self.rec.values():                            # C: dedo recien llegado y quieto justo antes del lapiz
                if r.state == PASS and now - r.t0 <= self.pre and r.moved <= self.move:
                    r.state = BAN
                    self.stats["pre"] += 1
        self.last_pen = now
        for r in self.rec.values():                                # D: los ids del Tracker mueren con tr.reset()
            self._add_ghost(r, now)
        self.rec.clear()
        for g in self.ghosts:
            g[3] = now
        self._calls_since_pen = 0

    def _add_ghost(self, r, now):
        self.ghosts.append([r.x, r.y, r, now])
        if len(self.ghosts) > self.max_ghosts:                     # memoria acotada en rafagas largas con muchos contactos que van y vienen
            del self.ghosts[0]

    def tracker_reset(self, now):
        """Llamar con un frame 0x509 SIN lapiz presente (ruido aislado: el demonio hace tr.reset() igualmente). NO activa el lapiz ni toca
        last_pen/burst; solo conserva el estado de los contactos como fantasmas para que el dedo (o la palma baneada) no pierda su estado
        al cambiar de tid."""
        self.stats["resets"] += 1
        for r in self.rec.values():
            self._add_ghost(r, now)
        self.rec.clear()
    def reset(self):
        self.rec.clear(); self.ghosts.clear()

    # --- filtro por frame de dedos ----------------------------------------------------------------------------------------
    def _take_ghost(self, x, y, now):
        best, bd = None, self.ghost_px
        for g in self.ghosts:
            d = math.hypot(g[0] - x, g[1] - y)
            if d <= bd and now - g[3] <= self.margin:
                best, bd = g, d
        if best is not None:
            self.ghosts.remove(best)
            return best[2]
        return None

    def filter(self, pts, now, touching=False):
        """pts = [(tid, x, y, area)] (puede ser []). Devuelve los pts a emitir (los pendientes y baneados NO salen)."""
        touching = touching and self.last_pen is not None and now - self.last_pen <= self.margin   # sess.touching envejece tras la rafaga
        active = self.pen_active(now, touching)
        self.ghosts = [g for g in self.ghosts if now - g[3] <= self.margin]
        first_after_burst = (self._calls_since_pen == 0 and self.last_pen is not None and now - self.last_pen <= self.carry
                             and self.burst_start is not None and self.last_pen - self.burst_start >= self.min_burst)
        self._calls_since_pen += 1
        alive = {p[0] for p in pts}
        once = []
        for tid in [t for t in self.rec if t not in alive]:          # contacto levantado
            r = self.rec.pop(tid)
            if r.state == PEND:
                if self.tap_replay and not (touching or r.strong) and r.moved <= self.move:
                    once.append((tid, r.x, r.y, r.area)); self.stats["tap"] += 1
                else:
                    self.stats["dropped_tap"] += 1
            elif r.state == BAN:
                self._add_ghost(r, now)                              # el Tracker puede perder y recuperar la palma un frame
        out = []
        for tid, x, y, area in pts:
            r = self.rec.get(tid)
            if r is None:
                g = self._take_ghost(x, y, now)
                if g is not None:
                    r = g; r.x, r.y = x, y; self.stats["inherit"] += 1
                elif not active and not first_after_burst:
                    r = _Rec(now, x, y, area, PASS)                     # A
                elif first_after_burst:
                    r = _Rec(now, x, y, area, BAN); self.stats["carry"] += 1
                else:
                    r = _Rec(now, x, y, area, PEND)                     # B
                self.rec[tid] = r
            r.x, r.y, r.area = x, y, area
            r.moved = max(r.moved, math.hypot(x - r.x0, y - r.y0))
            if area > r.amax:
                r.amax = area
            if r.state == PEND:
                r.strong = r.strong or touching
                if now - r.t0 >= (self.strong if r.strong else self.weak):
                    if r.moved > self.move or not active:
                        r.state = PASS; self.stats["pass_moved" if r.moved > self.move else "delayed"] += 1
                        r.replay = self.replay_start and r.moved > self.move
                    else:
                        r.state = BAN; r.tban = now; self.stats["palm"] += 1
            elif r.state == BAN and self.release_ms and not active and r.amax <= self.release_area:
                # M1: contacto quieto baneado, lapiz ya inactivo y NUNCA con forma de palma (area <= release_area): tras release_ms pasa
                if r.tban is None:
                    r.tban = now
                if now - max(r.tban, self.last_pen if self.last_pen is not None else 0) >= self.release_ms:
                    r.state = PASS; self.stats["released"] += 1
            if r.state == PASS:
                if r.replay:
                    out.append((tid, r.x0, r.y0, area)); r.replay = False
                else:
                    out.append((tid, x, y, area))
        return out + once
