"""thp_algo.py — de rejilla THP cruda (NT36532, 40x60 mutual) a toques, para la uke (18-oct-2026).

Sin dependencias. Lo usan uke-touchd.py (en la tablet) y thp_validate.py (en el PC, contra los frames y el getevent
capturados en Android: build/android/perif-20261017/touch-dedo/).

Formato del frame (medido en Android, touch-dedo/README.md): F = cabecera 64 B (id u16 @+4, magic 0x4BF @+8,
~id @+0xC, ~magic @+0x10) + mutual u16[40*60] @F+0x40, fila mayor (40 filas x 60 columnas).
Mapeo medido contra getevent: fila = X/21360*40, col = Y/32000*60 (X,Y en la escala de Android, super_resolution 10:
2136x3200 en pixeles del panel en orientacion natural vertical).
"""
import struct

ROWS, COLS = 40, 60
MAGIC = 0x4BF
X_MAX, Y_MAX = 21360, 32000          # escala de Android (x10 de 2136 x 3200)


def parse_frame(F):
    """Devuelve (id, lista de 2400 enteros) o None si la cabecera no es valida."""
    if len(F) < 0x40 + 2 * ROWS * COLS:
        return None
    fid, mag, nid, nmag = struct.unpack_from("<H2xH2xH2xH", F, 4)
    if mag != MAGIC or nmag != (~MAGIC & 0xFFFF) or nid != (~fid & 0xFFFF):
        return None
    return fid, list(struct.unpack_from("<%dH" % (ROWS * COLS), F, 0x40))


class Tracker:
    """Linea base por nodo + deteccion de picos + centroide + seguimiento de IDs."""

    def __init__(self, thr_on=420, thr_peak=600, alpha=1 / 64, max_touch=10, track_dist=2.5):
        self.base = None
        self.thr_on = thr_on          # nodo "tocado" (cuentas sobre la base)
        self.thr_peak = thr_peak      # pico minimo para declarar un dedo
        self.alpha = alpha            # adaptacion de la base en nodos sin toque
        self.max_touch = max_touch
        self.track_dist = track_dist  # distancia maxima (en nodos) para conservar el ID entre frames
        self.prev = []                # [(id, r, c)]
        self.next_id = 0

    def _peaks(self, d):
        pk = []
        for r in range(ROWS):
            row = r * COLS
            for c in range(COLS):
                v = d[row + c]
                if v < self.thr_peak:
                    continue
                ok = True
                for dr in (-1, 0, 1):
                    rr = r + dr
                    if not 0 <= rr < ROWS:
                        continue
                    for dc in (-1, 0, 1):
                        cc = c + dc
                        if (dr or dc) and 0 <= cc < COLS:
                            w = d[rr * COLS + cc]
                            # maximo local estricto, desempate por indice para mesetas
                            if w > v or (w == v and (rr * COLS + cc) < row + c):
                                ok = False
                                break
                    if not ok:
                        break
                if ok:
                    pk.append((v, r, c))
        pk.sort(reverse=True)
        return pk[: self.max_touch]

    def _centroid(self, d, r, c):
        sw = sr = sc = 0.0
        n = 0
        for rr in range(max(0, r - 1), min(ROWS, r + 2)):
            for cc in range(max(0, c - 1), min(COLS, c + 2)):
                w = d[rr * COLS + cc]
                if w > 0:
                    sw += w
                    sr += w * rr
                    sc += w * cc
                    if w >= self.thr_on:
                        n += 1
        return (sr / sw, sc / sw, n) if sw else (float(r), float(c), 1)

    def quick_idle(self, mutual, every=16):
        """Via rapida de reposo (uke-touchd): True si el frame no puede contener un dedo y no hay toques activos.

        Usa max() en C sobre la rejilla (array/lista) en vez de recorrer 2400 nodos en Python; la base se adapta solo
        1 de cada `every` frames de reposo. Con la base ~plana (9962..10071) basta comparar contra max(base) + umbral.
        """
        if self.base is None or self.prev:
            return False
        if max(mutual) >= self._base_max + self.thr_peak:
            return False
        self._idle_n = getattr(self, "_idle_n", 0) + 1
        if self._idle_n % every == 0:
            a = self.alpha * every
            b = self.base
            for i in range(ROWS * COLS):
                e = mutual[i] - b[i]
                if e < 0 or e < self.thr_on / 2:
                    b[i] += (a if e >= 0 else min(1.0, 4 * a)) * e
            self._base_max = max(b)
        return True

    def reset(self):
        """Olvidar base y toques (tras recargar el firmware del chip)."""
        self.base = None
        self.prev = []

    def feed(self, mutual):
        """Devuelve lista de toques [(id, x, y, area)] en escala Android (0..21360, 0..32000)."""
        if self.base is None:
            # base inicial PLANA = mediana del frame: con un dedo ya apoyado al arrancar (pasa en la captura de
            # Android: f0000 trae un dedo en r18 c28) copiar el frame meteria el dedo en la base. La base real
            # es casi plana (9962..10071 medido sobre 1284 frames) y el dedo da +1100..1280.
            med = sorted(mutual)[len(mutual) // 2]
            self.base = [float(med)] * (ROWS * COLS)
            self._base_max = float(med)
        d = [mutual[i] - self.base[i] for i in range(ROWS * COLS)]
        peaks = self._peaks(d)
        pts = []
        for v, r, c in peaks:
            rc, cc, n = self._centroid(d, r, c)
            pts.append((rc, cc, n))
        # base: adaptar solo donde no hay toque (y lejos de los picos)
        touched = set()
        for rc, cc, _ in pts:
            for rr in range(int(rc) - 2, int(rc) + 3):
                for c2 in range(int(cc) - 2, int(cc) + 3):
                    if 0 <= rr < ROWS and 0 <= c2 < COLS:
                        touched.add(rr * COLS + c2)
        a = self.alpha
        for i in range(ROWS * COLS):
            if i in touched:
                continue
            e = mutual[i] - self.base[i]
            # adaptar solo con desviaciones pequenas (deriva); por debajo de la base, rapido (dedo que se fue)
            if e < 0:
                self.base[i] += 4 * a * e
            elif e < self.thr_on / 2:
                self.base[i] += a * e
        # seguimiento: emparejar por distancia con los toques del frame anterior
        out, used = [], set()
        for rc, cc, n in pts:
            best, bd = None, self.track_dist
            for tid, pr, pc in self.prev:
                if tid in used:
                    continue
                dd = ((pr - rc) ** 2 + (pc - cc) ** 2) ** 0.5
                if dd < bd:
                    best, bd = tid, dd
            if best is None:
                best = self.next_id
                self.next_id = (self.next_id + 1) & 0xFFFF
            used.add(best)
            out.append((best, rc, cc, n))
        self.prev = [(t, r, c) for t, r, c, _ in out]
        self._base_max = max(self.base)
        return [(t, (r + 0.5) * X_MAX / ROWS, (c + 0.5) * Y_MAX / COLS, n) for t, r, c, n in out]
