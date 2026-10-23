#!/usr/bin/env python3
"""uke_lapiz_ble.py — cliente BLE del Focus Pen para uke-touchd (--pen). Desplegado una vez en la tablet (19-oct); corregido tras la revision independiente (20-oct); desde el 20-oct lee las notificaciones de `busctl monitor` (bluetoothctl las perdia). Robustez (20-oct tarde): sendto no bloqueante con cola acotada, bucle con select y timers independientes del flujo de busctl, watchdog del monitor, parseo barato por bytes.

Mantiene la conexion BLE del lapiz (02:00:5E:00:00:07), hace el handshake de Android (lapiz_ble.handshake), activa las notificaciones
con `bluetoothctl` (en la tablet no hay gi/bleak) y traduce los informes a mensajes JSON para /run/uke-lapiz.sock (uke_pen.py):
  informe 5 (service001c/char002d, 14 B)  -> {"pressure": u16 LE de los bytes 0-1}           (r=0,993 con ABS_PRESSURE, §21)
  teclado    (service001c/char0029, 1 B)   -> {"btn": small|big_up|big_down, "down": bool}    (0x6e / 0x4b / 0x4e; 0 = soltar)
  fe12       (service0034/char0037)        -> 53 01 xx = estado del hall del lapiz            (SIN CALIBRAR: ver HALL_ATTACHED)
Solo la funcion de analisis (parse_stream / to_messages) esta probada offline contra los registros reales de la tablet.
"""
import collections, fcntl, json, os, re, select, signal, socket, struct, subprocess, sys, termios, threading, time

import lapiz_ble

if os.environ.get("LAPIZ_STACKS"):          # depuracion de parones: vuelca la pila de todos los hilos cada 10 s al fichero indicado
    import faulthandler
    _stk = open(os.environ["LAPIZ_STACKS"] + "." + str(os.getpid()), "a")
    faulthandler.dump_traceback_later(10, repeat=True, file=_stk)

PEN = "02:00:5E:00:00:07"
SOCK = "/run/uke-lapiz.sock"
DEV = "/org/bluez/hci0/dev_" + PEN.replace(":", "_")
NOTIFY = ["service0034/char0037", "service001c/char0029", "service001c/char002d"]      # sin char0025 (raton aereo): no se usa y despierta la CPU
# El lapiz notifica `53 01 xx` al pegar/despegar. En Android el host escribia `51 01 hall` y el lapiz respondia el complemento
# (510100 -> 530101); en Linux con el dueno pegando/despegando salieron 8 avisos alternos 00/01. Que valor es «pegado» NO esta
# medido: hipotesis 1 = pegado. Calibrar con una prueba (pegar -> leer el valor) antes de fiarse.
HALL_ATTACHED = 1

ANSI = re.compile(r"\x1b\[[0-9;]*m")
HDR = re.compile(r"Attribute \S+/(service\w+/char\w+) Value:")
HEXLINE = re.compile(r"^\s\s((?:[0-9a-f]{2} )+)")


def parse_stream(text):
    """Texto de bluetoothctl -> lista de (char, bytes). Cada `Value:` va seguido (tras lineas de prompt) de una linea hex."""
    lines = ANSI.sub("", text).replace("\r", "").split("\n")
    out = []
    for i, l in enumerate(lines):
        m = HDR.search(l)
        if not m:
            continue
        for j in range(i + 1, min(i + 8, len(lines))):
            h = HEXLINE.match(lines[j])
            if h:
                out.append((m.group(1), bytes.fromhex(h.group(1).replace(" ", ""))))
                break
    return out


def parse_chunk(buf):
    """Como parse_stream pero para un buffer que crece: solo usa lineas COMPLETAS y devuelve (items, resto). El resto conserva desde la
    ultima cabecera `Value:` cuya linea hex aun no ha llegado (o la linea a medias), de modo que no se pierden notificaciones partidas."""
    nl = buf.rfind("\n")
    if nl < 0:
        return [], buf
    done, tail = buf[:nl + 1], buf[nl + 1:]
    lines = ANSI.sub("", done).replace("\r", "").split("\n")
    items, last_consumed, pending_hdr = [], -1, None
    for i, l in enumerate(lines):
        m = HDR.search(l)
        if m:
            pending_hdr = (i, m.group(1))
            continue
        h = HEXLINE.match(l)
        if h and pending_hdr is not None and i - pending_hdr[0] <= 8:
            items.append((pending_hdr[1], bytes.fromhex(h.group(1).replace(" ", ""))))
            last_consumed = i
            pending_hdr = None
    keep_from = pending_hdr[0] if pending_hdr is not None else last_consumed + 1
    rest = "\n".join(lines[keep_from:]) if keep_from < len(lines) else ""
    return items, (rest + tail if rest or tail else "")


# MAC del lapiz BLE (Xiaomi Focus Pen). En el repo publico va ENMASCARADA: define
# LAPIZ_BLE_MAC=70:61:EE:xx:xx:xx en el entorno para usar la real de tu aparato.
LAPIZ_BLE_MAC = os.environ.get("LAPIZ_BLE_MAC", "70:61:EE:XX:XX:XX")
_DEVID = "dev_" + LAPIZ_BLE_MAC.replace(":", "_")
MONITOR_KEY = _DEVID + "/service"
_KEY_B = MONITOR_KEY.encode()
_DEVPFX = (_DEVID + "/").encode()
_VALUE_B = b'"Value":{"type":"ay","data":['
_VL = len(_VALUE_B)


def parse_busctl_bytes(line):
    """Version barata de parse_busctl_line para bytes (lo que lee el bucle): primero comprobaciones de subcadena en C (casi todas las lineas
    de org.bluez se descartan ahi), luego extraccion por find/split del formato fijo de `busctl --json=short`; json.loads solo como respaldo
    si la forma no es la esperada. Devuelve (char, bytes) o None."""
    if _KEY_B not in line or b"PropertiesChanged" not in line:
        return None
    v = line.find(_VALUE_B)
    if v >= 0:
        p0 = line.find(b'"path":"')
        p1 = line.find(b'"', p0 + 8) if p0 >= 0 else -1
        e = line.find(b"]", v + _VL)
        if p0 >= 0 and p1 > p0 and e > v:
            path = line[p0 + 8:p1]
            k = path.find(_DEVPFX)
            if k >= 0 and v > p1:
                try:
                    body = line[v + _VL:e]
                    return path[k + len(_DEVPFX):].decode("ascii"), (bytes(map(int, body.split(b","))) if body else b"")
                except (ValueError, UnicodeDecodeError):
                    pass
    elif b'"Value"' not in line:
        return None
    try:                                                    # respaldo: forma inesperada
        m = json.loads(line)
        d = m["payload"]["data"]
        if m.get("member") != "PropertiesChanged" or len(d) < 2 or "Value" not in d[1]:
            return None
        return m["path"].split(_DEVID + "/")[-1], bytes(d[1]["Value"]["data"])
    except (ValueError, KeyError, TypeError, IndexError, AttributeError, RecursionError, MemoryError):   # RecursionError: JSON anidado hostil (F5)
        return None


def parse_busctl_line(line):
    """Una linea de `busctl --json=short monitor org.bluez` (str o bytes) -> (char, bytes) si es un PropertiesChanged con `Value` de una
    caracteristica del lapiz, si no None. Es la via FIABLE: bluetoothctl pierde notificaciones (el btsnoop veia 30 pulsaciones, bluetoothctl 1)."""
    return parse_busctl_bytes(line.encode() if isinstance(line, str) else line)


HALL_IGNORE_S = 1.5       # el lapiz responde `53 01 xx` a nuestro `51 01 hh` del handshake: no es un evento de hall real (revision I5)


def to_messages(char, data, state, now=None):
    """(char, bytes) -> lista de mensajes dict. state: dict mutable con 'last_pressure' (se emite solo al cambiar)."""
    if char.endswith("service001c/char002d"):
        r = lapiz_ble.parse_pressure_report(data)
        if r is None:
            return []
        state["reports5"] = state.get("reports5", 0) + 1
        p = r["pressure"]
        if p == state.get("last_pressure"):
            return []
        state["last_pressure"] = p
        return [{"pressure": p}]
    if char.endswith("service001c/char0029"):
        k, name = lapiz_ble.parse_keyboard_report(data)
        if k == "down":
            out = [{"btn": state["btn"], "down": False}] if state.get("btn") and state["btn"] != name else []   # otro boton sin soltar: cerrarlo (F5)
            state["btn"] = name
            return out + [{"btn": name, "down": True}]
        if k == "up" and state.get("btn"):
            name, state["btn"] = state["btn"], None
            return [{"btn": name, "down": False}]
        return []
    if char.endswith("service0034/char0037") and len(data) == 3 and data[0] == 0x53 and data[1] == 0x01:
        now = time.monotonic() if now is None else now
        if now - state.get("hall_write_t", -1e9) < HALL_IGNORE_S:
            return []
        state["attached_value"] = data[2] == HALL_ATTACHED          # para reenviar el estado completo (touchd puede reiniciarse)
        return [{"attached": state["attached_value"]}]
    return []


def release_held(state):
    """Mensajes «soltar» para el boton que sigue pulsado (conexion perdida, monitor reiniciado, SIGTERM): si no, touchd deja la tecla pegada."""
    name, state["btn"] = state.get("btn"), None
    return [{"btn": name, "down": False}] if name else []


DEBUG = bool(os.environ.get("LAPIZ_DEBUG"))
STATE_KEYS = ("pressure", "connected", "attached")       # mensajes idempotentes: de cada clase solo importa el ultimo
MAXQ = 512                                                # tope de la cola si el receptor no lee (solo botones se acumulan mas alla de esto)


class Publisher:
    """Datagramas AF_UNIX hacia touchd SIN bloquear nunca. Si el receptor tiene la cola llena (BlockingIOError) los mensajes se guardan en una
    cola corta: de `pressure`/`connected`/`attached` solo se conserva el ultimo; los botones se conservan todos (hasta MAXQ). Receptor ausente
    (FileNotFoundError / ConnectionRefusedError) = se descarta y se cuenta. flush() reintenta en cada vuelta del bucle."""

    def __init__(self, path=SOCK):
        self.s, self.path = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM), path
        self.s.setblocking(False)
        self.q = collections.deque()                      # (clave|None, bytes)
        self.sent = self.dropped_full = self.dropped_absent = 0

    def close(self):
        self.s.close()

    def _key(self, msg):
        for k in STATE_KEYS:
            if k in msg:
                return k
        return None

    def send(self, msg):
        if DEBUG:
            print("%.3f %s" % (time.monotonic(), json.dumps(msg)), flush=True)
        data = json.dumps(msg).encode()
        key = self._key(msg)
        if self.q:
            self._enqueue(key, data)
            self.flush()
            return
        r = self._try(data)
        if r is False:
            self._enqueue(key, data)

    def _try(self, data):
        """True = enviado o descartado definitivamente; False = receptor lleno (reintentar)."""
        try:
            self.s.sendto(data, self.path)
            self.sent += 1
            return True
        except BlockingIOError:
            return False
        except (FileNotFoundError, ConnectionRefusedError):
            self.dropped_absent += 1                      # touchd aun no ha creado el socket
            return True
        except OSError:
            self.dropped_absent += 1
            return True

    def _enqueue(self, key, data):
        if key is not None:
            n = len(self.q)
            if any(k == key for k, _ in self.q):
                self.q = collections.deque((k, d) for k, d in self.q if k != key)
                self.dropped_full += n - len(self.q)
        self.q.append((key, data))
        while len(self.q) > MAXQ:                         # ultimo recurso: memoria acotada; prefiere perder estado a perder botones
            for i, (k, _) in enumerate(self.q):
                if k is not None:
                    del self.q[i]
                    break
            else:
                self.q.popleft()
            self.dropped_full += 1

    def flush(self):
        while self.q:
            if self._try(self.q[0][1]) is False:
                return
            self.q.popleft()


def parse_busctl_connected(line):
    """Linea de `busctl monitor org.bluez` (str o bytes) -> True/False si es un PropertiesChanged de Device1 con `Connected` del lapiz, si no
    None. Evita lanzar `bluetoothctl info` en el bucle (el 20-oct un paron de 20,6 s del cliente cuadraba con dos timeouts de 10 s)."""
    if isinstance(line, str):
        line = line.encode()
    if b'"Connected"' not in line or _DEVPFX.rstrip(b"/") not in line or b"PropertiesChanged" not in line:
        return None
    try:
        m = json.loads(line)
        if not m["path"].endswith(_DEVID):
            return None
        d = m["payload"]["data"]
        if d[0] != "org.bluez.Device1" or "Connected" not in d[1]:
            return None
        v = d[1]["Connected"]["data"]
        return bool(v) if isinstance(v, bool) else None
    except (ValueError, KeyError, TypeError, IndexError, RecursionError):
        return None


BTCTL = os.environ.get("LAPIZ_BTCTL", "bluetoothctl")      # sobreescribibles (pruebas con binarios falsos)
BUSCTL = os.environ.get("LAPIZ_BUSCTL", "busctl")


def btctl(*args, timeout=4):
    try:
        return subprocess.run([BTCTL, *args], capture_output=True, text=True, timeout=timeout).stdout
    except (subprocess.TimeoutExpired, OSError):
        return ""


def reap(p, grace=1.0):
    """Termina y recoge un hijo sin colgarse nunca (terminate -> kill -> wait con tope). Sin zombis."""
    if p is None:
        return
    try:
        if p.poll() is None:
            p.terminate()
            try:
                p.wait(grace)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait(grace)
    except (OSError, subprocess.TimeoutExpired):
        pass
    for f in (p.stdin, p.stdout):
        try:
            if f:
                f.close()
        except OSError:
            pass


class ConnCache:
    """Estado `Connected` del lapiz: lo actualiza el monitor D-Bus (set); `bluetoothctl info` solo como comprobacion de respaldo cada `period` s
    (o si se fuerza / aun no hay dato). __call__ es sincrono (arranque); tick() es el respaldo ASINCRONO del bucle (no bloquea los timers)."""

    def __init__(self, period=20.0, tmo=4.0):
        self.period, self.tmo, self.t, self.v = period, tmo, -1e9, None
        self.proc, self.proc_t = None, 0.0

    def set(self, v):
        self.v, self.t = bool(v), time.monotonic()

    def __call__(self, force=False):
        now = time.monotonic()
        if force or self.v is None or now - self.t >= self.period:
            self.t, self.v = now, "Connected: yes" in btctl("info", PEN)
        return self.v

    def tick(self, now=None):
        """Sin bloquear: lanza `bluetoothctl info` si toca, recoge su resultado cuando acaba, lo mata pasado el timeout."""
        now = time.monotonic() if now is None else now
        if self.proc is not None:
            if self.proc.poll() is not None:
                try:
                    out = self.proc.stdout.read().decode(errors="replace")
                except OSError:
                    out = ""
                reap(self.proc)
                self.proc = None
                if "Connected:" in out:
                    self.v, self.t = "Connected: yes" in out, now
            elif now - self.proc_t > self.tmo:
                reap(self.proc, 0.5)
                self.proc, self.t = None, now             # no reintentar de golpe
        elif now - self.t >= self.period:
            self.t = now
            try:
                self.proc, self.proc_t = subprocess.Popen([BTCTL, "info", PEN], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL), now
            except OSError:
                self.proc = None
        return self.v


MON_SILENCE_S = float(os.environ.get("LAPIZ_MON_SILENCE", "30"))   # sin ni un byte de busctl con el lapiz conectado: sonda a N/2, reinicio a N
MON_QMAX = int(os.environ.get("LAPIZ_MON_QMAX", "4000"))           # lineas pendientes de procesar; si el consumidor se retrasa se descartan las MAS VIEJAS
MON_BACKLOG_BYTES = 32768                                          # bytes parados en la tuberia de busctl (el tope del kernel son 64 KiB)...
MON_BACKLOG_S = float(os.environ.get("LAPIZ_MON_BACKLOG_S", "2"))  # ...durante tanto tiempo = no damos abasto: se mata y se relanza busctl
# Solo lo que usa el cliente: PropertiesChanged del dispositivo del lapiz y de sus caracteristicas (Value) y de Device1 (Connected), que
# cuelgan todos de ese path. Sin filtro el monitor veia TODO el trafico de org.bluez (el 22-oct el broker llego a 1,1 GB de RSS).
MON_MATCH = "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path_namespace='%s'" % DEV


def _kill(p, grace=1.0):
    """terminate -> kill -> wait con tope; NO cierra stdout (lo cierra el hilo lector, unico que lo lee)."""
    try:
        if p.poll() is None:
            p.terminate()
            try:
                p.wait(grace)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait(grace)
    except (OSError, subprocess.TimeoutExpired):
        pass


class Monitor:
    """`busctl --json=short monitor --match ...` con un HILO LECTOR DEDICADO que vacia la tuberia SIEMPRE (22-oct: el bucle principal dejaba de
    leer -dormia en time.sleep/bluetoothctl mientras el lapiz no estaba conectado-, busctl se bloqueaba en write, dejaba de vaciar su cola
    del broker y la cuota de root de dbus-broker se desbordo: logind, NetworkManager y libseat expulsados, tablet congelada).
    El hilo reparte las lineas en una cola ACOTADA (si el consumidor se retrasa se tiran las mas viejas; busctl nunca espera) y avisa por una
    tuberia de despertar (fileno()) para el select del llamador. El propio hilo hace de vigia: si el hijo muere, o hay backlog sostenido en su
    tuberia, lo mata y lo relanza (con espera creciente). El vigia de silencio (watchdog) lo llama el bucle, solo con el lapiz activo."""

    def __init__(self, silence=None, cmd=None, qmax=None, backlog_s=None):
        self.silence = MON_SILENCE_S if silence is None else silence
        self.cmd = cmd or [BUSCTL, "--json=short", "monitor", "--match", MON_MATCH]
        self.backlog_s = MON_BACKLOG_S if backlog_s is None else backlog_s
        self.q = collections.deque(maxlen=MON_QMAX if qmax is None else qmax)
        self.last_rx = time.monotonic()
        self.restarts = self.probes = self.lines = self.dropped = self.backlog_kills = 0
        self.probe_p, self.probe_t, self.probed = None, 0.0, False
        self.closed = False
        self.wr, self.ww = os.pipe()
        os.set_blocking(self.wr, False)
        os.set_blocking(self.ww, False)
        self.p = None
        self._spawn()
        self.th = threading.Thread(target=self._run, name="busctl-reader", daemon=True)
        self.th.start()

    # --- hilo lector -------------------------------------------------------------------------------------------------------------
    def _spawn(self):
        p = subprocess.Popen(self.cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
        os.set_blocking(p.stdout.fileno(), False)
        p.uke_killed = False
        self.p = p
        self.last_rx = time.monotonic()
        self.probed = False

    def _wake(self):
        try:
            os.write(self.ww, b"x")
        except OSError:                                    # BlockingIOError: ya hay un aviso pendiente
            pass

    def _pump(self, p):
        """Vacia stdout de `p` hasta EOF / muerte / kill / cierre. Nunca bloquea: select con tope + os.read no bloqueante."""
        fd, buf, backlog_t0 = p.stdout.fileno(), bytearray(), None
        while not self.closed and not p.uke_killed:
            try:
                r, _, _ = select.select([fd], [], [], 0.25)
            except (OSError, ValueError):
                return
            if not r:
                if p.poll() is not None:
                    return
                continue
            try:
                chunk = os.read(fd, 262144)
            except (BlockingIOError, InterruptedError):
                continue
            except OSError:
                return
            if not chunk:                                  # EOF: el hijo cerro stdout
                return
            self.last_rx = time.monotonic()
            buf += chunk
            lines = buf.split(b"\n")
            rest = lines.pop()
            buf = bytearray(rest[-20000:] if len(rest) > 20000 else rest)
            if lines:
                over = len(self.q) + len(lines) - self.q.maxlen
                if over > 0:
                    self.dropped += over                   # consumidor atrasado: se pierden las lineas viejas, nunca se frena a busctl
                self.q.extend(lines)                       # deque(maxlen) tira por la izquierda
                self._wake()
            try:                                           # vigia de backlog: bytes que siguen esperando en la tuberia tras vaciarla
                pend = struct.unpack("i", fcntl.ioctl(fd, termios.FIONREAD, b"\0\0\0\0"))[0]
            except OSError:
                pend = 0
            if pend < MON_BACKLOG_BYTES:
                backlog_t0 = None
            elif backlog_t0 is None:
                backlog_t0 = time.monotonic()
            elif time.monotonic() - backlog_t0 >= self.backlog_s:
                self.backlog_kills += 1
                return

    def _run(self):
        backoff = 0.1
        while not self.closed:
            p = self.p
            t0 = time.monotonic()
            try:
                self._pump(p)
            except Exception:                              # noqa: BLE001  el lector NO puede morir: sin el la tuberia dejaria de vaciarse
                pass
            if self.closed:
                break
            _kill(p)
            try:
                p.stdout.close()
            except OSError:
                pass
            if not p.uke_killed:
                self.restarts += 1                         # muerte/EOF/backlog (los reinicios pedidos ya los cuenta restart())
            backoff = 0.1 if time.monotonic() - t0 > 5 else min(backoff * 2, 5.0)
            end = time.monotonic() + backoff
            while not self.closed and time.monotonic() < end:
                time.sleep(0.05)
            while not self.closed:
                try:
                    self._spawn()
                    break
                except OSError:
                    time.sleep(1.0)

    # --- API para el bucle -------------------------------------------------------------------------------------------------------
    def fileno(self):
        return self.wr

    def discard(self):
        """Tira lo acumulado (p. ej. lo que llego mientras no habia sesion)."""
        self.q.clear()
        try:
            while os.read(self.wr, 4096):
                pass
        except OSError:
            pass

    def restart(self, now=None):
        """Mata el hijo actual (el hilo lector lanza el siguiente) y lo cuenta."""
        p = self.p
        p.uke_killed = True
        self.restarts += 1
        _kill(p)
        self.last_rx = time.monotonic() if now is None else now
        self.probed = False

    def read_lines(self, now):
        """Lineas completas (bytes) acumuladas desde la ultima llamada. No bloquea."""
        try:
            while os.read(self.wr, 4096):
                pass
        except OSError:
            pass
        out = []
        try:
            while True:
                out.append(self.q.popleft())
        except IndexError:
            pass
        self.lines += len(out)
        return out

    def watchdog(self, now, active):
        """active = lapiz conectado y handshake hecho. Devuelve True si reinicio."""
        if not self.th.is_alive() and not self.closed:     # el lector no debe morir; si lo hace, se rearma
            self.th = threading.Thread(target=self._run, name="busctl-reader", daemon=True)
            self.th.start()
        if self.probe_p is not None and (self.probe_p.poll() is not None or now - self.probe_t > 3.0):
            reap(self.probe_p, 0.3)
            self.probe_p = None
        if not active or self.silence <= 0:
            self.last_rx = now                             # la cuenta de silencio empieza cuando pasa a activo
            return False
        quiet = now - self.last_rx
        if quiet >= self.silence:
            self.restart(now)
            return True
        if quiet >= self.silence / 2 and not self.probed and self.probe_p is None:
            self.probed, self.probes, self.probe_t = True, self.probes + 1, now
            try:
                self.probe_p = subprocess.Popen([BUSCTL, "--timeout=2", "get-property", "org.bluez", DEV, "org.bluez.Device1", "Connected"],
                                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except OSError:
                self.probe_p = None
        return False

    def close(self):
        self.closed = True
        _kill(self.p)
        self.th.join(2.0)
        for f in (self.wr, self.ww):
            try:
                os.close(f)
            except OSError:
                pass
        reap(self.probe_p, 0.3)
        try:
            self.p.stdout.close()
        except OSError:
            pass


class Session:
    """Una conexion del lapiz ya conectada: reparte la escritura a bluetoothctl (no bloqueante), los timers y la lectura del monitor en un
    unico select, de modo que el reenvio de estado (2 s) corre aunque busctl se calle."""
    FEED_GAP = 0.35
    STATE_PERIOD = 2.0

    def __init__(self, pub, state, connected, mon, feed, wproc=None, announce_now=False):
        self.pub, self.state, self.connected, self.mon = pub, state, connected, mon
        self.feed, self.idx, self.wproc, self.wbuf = feed, 0, wproc, bytearray()
        now = time.monotonic()
        self.t_send, self.t_state, self.announced, self.t_dbg = now, 0.0, bool(announce_now), now
        self.stats_prev, self.n_lines_prev = (0, 0), 0
        self.mon_restarts = mon.restarts
        if wproc is not None:
            os.set_blocking(wproc.stdin.fileno(), False)

    def alive(self):
        return (self.wproc is None or self.wproc.poll() is None) and bool(self.connected.v)

    def _feed(self, now):
        if self.idx < len(self.feed) and now - self.t_send > self.FEED_GAP and not self.wbuf:
            cmd, is_hall = self.feed[self.idx]
            self.wbuf += (cmd + "\n").encode()
            self.idx += 1
            self.t_send = now
            if is_hall:
                self.state["hall_write_t"] = now
            if self.idx == len(self.feed):
                self.announced = True                      # handshake completo: ahora si, el lapiz esta listo (revision I8)
                if os.environ.get("LAPIZ_ASSUME_DETACHED") and "attached_value" not in self.state:
                    self.state["attached_value"] = False
                    self.pub.send({"attached": False})

    def _write(self):
        if self.wbuf and self.wproc is not None:
            try:
                n = os.write(self.wproc.stdin.fileno(), self.wbuf)
                del self.wbuf[:n]
            except (BlockingIOError, InterruptedError):
                pass
            except OSError:
                self.wbuf.clear()

    def step(self, now=None, max_wait=0.25):
        """Una vuelta: timers, escritura, select (con tope), lectura y proceso del monitor, watchdog."""
        real = now is None
        now = time.monotonic() if real else now
        self._feed(now)
        if self.announced and now - self.t_state >= self.STATE_PERIOD:     # reenviar el estado: touchd puede haberse reiniciado
            self.t_state = now
            self.pub.send({"connected": True})
            if "attached_value" in self.state:
                self.pub.send({"attached": self.state["attached_value"]})
        self.connected.tick(now)
        self.pub.flush()
        wait = max_wait
        if self.pub.q:
            wait = min(wait, 0.02)
        if self.idx < len(self.feed):
            wait = min(wait, max(0.0, self.FEED_GAP - (now - self.t_send)) + 0.005)
        wl = [self.wproc.stdin.fileno()] if self.wbuf and self.wproc is not None else []
        try:
            r, w, _ = select.select([self.mon.fileno()], wl, [], wait)
        except (OSError, ValueError):
            r, w = [], []
        if w:
            self._write()
        now2 = time.monotonic() if real else now
        if r:
            for ln in self.mon.read_lines(now2):
                self.handle_line(ln, now2)
        self.mon.watchdog(now2, self.announced and bool(self.connected.v))
        if self.mon.restarts != self.mon_restarts:                         # el monitor se reinicio: puede haberse perdido el «soltar» de un boton
            self.mon_restarts = self.mon.restarts
            for m in release_held(self.state):
                self.pub.send(m)
        if DEBUG and now - self.t_dbg > 10:
            self.debug(now)

    def handle_line(self, ln, now):
        try:
            if b'"Connected"' in ln:
                cv = parse_busctl_connected(ln)
                if cv is not None:
                    self.connected.set(cv)
            it = parse_busctl_bytes(ln)
            if it:
                for msg in to_messages(it[0], it[1], self.state, now):
                    self.pub.send(msg)
        except Exception as e:                                             # noqa: BLE001  una linea rara NUNCA debe tumbar al cliente (se perderia el estado)
            self.state["bad_lines"] = self.state.get("bad_lines", 0) + 1
            if DEBUG:
                print("linea ignorada (%r)" % (e,), flush=True)

    def debug(self, now):
        dt = now - self.t_dbg
        self.t_dbg = now
        mon, pub = self.mon, self.pub
        print("%.3f informes5=%d lineas/s=%.1f descartes_cola=%d descartes_ausente=%d enviados=%d en_cola=%d reinicios_monitor=%d sondas=%d" % (
            now, self.state.get("reports5", 0), (mon.lines - self.n_lines_prev) / dt if dt > 0 else 0.0, pub.dropped_full, pub.dropped_absent,
            pub.sent, len(pub.q), mon.restarts, mon.probes), flush=True)
        self.n_lines_prev = mon.lines


def _sigterm(signum, frame):
    raise SystemExit(0)


def run():
    signal.signal(signal.SIGTERM, _sigterm)
    pub, state = Publisher(), {}
    connected = ConnCache()
    mon = Monitor()
    try:
        while True:
            while not connected(force=True):
                pub.send({"connected": False})
                try:
                    subprocess.run(["timeout", "6", BTCTL, "connect", PEN], capture_output=True, timeout=10)
                except subprocess.TimeoutExpired:
                    pass
                time.sleep(2)
            m = re.search(r"Controller ([0-9A-F:]{17})", btctl("show"))
            mac = bytes.fromhex(m.group(1).replace(":", "")) if m else None
            if mac is None:
                time.sleep(5)
                continue
            for _ in range(10):
                if "ServicesResolved: yes" in btctl("info", PEN):
                    break
                time.sleep(1)
            w = f"{DEV}/service0034/char0035"
            cmds = lapiz_ble.handshake(mac, 1)        # 1 = despegado; hall real: ver HALL_ATTACHED (sin calibrar)
            # bluetoothctl solo ESCRIBE (notify on + handshake); sus notificaciones no se leen de aqui sino de busctl monitor
            p = subprocess.Popen([BTCTL], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            feed = [("menu gatt", False)] + [(f"select-attribute {DEV}/{c}\nnotify on", False) for c in NOTIFY]
            for c in cmds:
                feed.append((f"select-attribute {w}\nwrite \"{' '.join('0x%02x' % b for b in c)}\" 0 command", c[:1] == b"\x51"))
            state.pop("last_pressure", None)
            sess = Session(pub, state, connected, mon, feed, wproc=p)
            try:
                while sess.alive():
                    sess.step()
            finally:
                reap(p)
            for m in release_held(state) + [{"connected": False}]:
                pub.send(m)
    finally:
        try:                                                               # SIGTERM/excepcion: touchd no debe quedarse con botones pegados ni «conectado» eterno (F1/F3)
            for m in release_held(state) + [{"connected": False}]:
                pub.send(m)
            pub.flush()
        except Exception:                                                  # noqa: BLE001
            pass
        mon.close()
        reap(connected.proc, 0.3)
        pub.close()


if __name__ == "__main__":
    sys.exit(run())
