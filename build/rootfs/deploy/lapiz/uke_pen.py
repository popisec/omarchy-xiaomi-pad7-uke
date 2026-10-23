"""uke_pen.py — modo lapiz del NT36532 para uke-touchd, sin pausar el demonio (19/20-oct-2026). Desplegado UNA vez en la tablet (sesion del 19-oct,
resultados sin recuperar); revisado de forma independiente el 20-oct (analisis/REVISION-MODO-INTEGRADO.md) y corregido: todo el codigo del lapiz va
detras de PenRuntime, que atrapa cualquier excepcion y se desactiva solo (un fallo del lapiz NO puede tumbar el tactil).

Piezas, separadas para poder probarlas sin hardware:
  PenChip      escrituras al chip con ACK, tal como las hace el driver de Xiaomi (LAPIZ-20261018.md §21–§22):
                 despegado (enable):  [0xBF,0x04,0x00,0x01,0x00] (5x20 ms) ; 22 ms ; [0x7B,0x01] (10x10 ms)
                 pegado (disable):    [0xBF,0x04,0x00,0x00,0x00]            (NUNCA pen_switch 0 ni 0x7C: Android no lo hace)
  PenSession   maquina de estados pura: frames 0x509 (thp_pen.parse) + mensajes BLE -> eventos abstractos
  PenUInput    nodo uinput «uke Focus Pen» (ABS_X/Y/PRESSURE/TILT, BTN_TOOL_PEN/TOUCH/STYLUS*)
  PenRuntime   lo unico que ve uke-touchd: socket + chip + sesion + uinput, con aislamiento de errores, reintento de enable, liberacion de estado
Mensajes BLE (JSON por linea en el socket de datagramas /run/uke-lapiz.sock, escritos por el cliente BLE):
  {"connected": true|false}  {"attached": true|false}  {"pressure": 0..8191}  {"btn": "small|big_up|big_down", "down": true|false}
"""
import json, math, os, socket, struct, time

import thp_pen

_HDR_UNPACK = thp_pen._HDR.unpack_from

if os.environ.get("LAPIZ_STACKS"):          # depuracion de parones: vuelca la pila de todos los hilos cada 10 s al fichero indicado
    import faulthandler
    _stk = open(os.environ["LAPIZ_STACKS"] + "." + str(os.getpid()), "a")
    faulthandler.dump_traceback_later(10, repeat=True, file=_stk)

HOLD_S = 0.30          # Android mantiene el lapiz «en rango» 0.25–0.5 s tras el ultimo frame con lapiz
# En el nodo de TABLETA solo sale el boton pequeño (BTN_STYLUS = 0x14B) y solo con el lapiz en rango. Los botones grandes van SIEMPRE por el nodo de
# teclado (PgUp/PgDn): BTN_STYLUS2 (0x14C) lo traduce QtWayland a clic derecho y, sin movimiento previo (posicion (0,0)), quickshell hace SIGSEGV
# (Qt 6.11.2, QQuickDeliveryAgent::contextMenuTargets -> mapToScene con activeFocusItem nulo; analisis/CAUSA-QUICKSHELL-LAPIZ.md);
# BTN_STYLUS3 (0x149) no es un boton estandar de libinput.
BTN_CODES = {"small": 0x14B, "big_up": 0x14C, "big_down": 0x149}     # nombres validos de boton (los de tableta se limitan en TABLET_BUTTONS)
TABLET_BUTTONS = {"small"}
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
ABS_X, ABS_Y, ABS_PRESSURE, ABS_TILT_X, ABS_TILT_Y = 0, 1, 0x18, 0x1A, 0x1B
BTN_TOOL_PEN, BTN_TOUCH = 0x140, 0x14A
PRESSURE_MAX = 8191
PRESSURE_FLOOR = 100        # ~1,2 %: con el chip en contacto, libinput decide la punta por umbral de presion y el BLE llega con retardo
ACTIVITY_S = 1.5            # un lapiz con presion BLE o frames presentes hace menos de ACTIVITY_S NO esta pegado: el aviso de hall «pegado» se ignora
BTN_MAX_HOLD_S = 15.0       # seguridad (REVISION-FALLOS F1/F2): una tecla de boton sin «soltar» por BLE se suelta sola tras tanto tiempo
BLE_SILENCE_S = 15.0        # (F3) el cliente BLE reenvia el estado cada 2 s: 15 s sin NINGUN mensaje con connected=True = cliente muerto = desconectado
PRESSURE_STALE_S = 5.0      # (F4) presion BLE > 0 sin punta (contacto del chip) y sin informes nuevos en tanto tiempo: el «0» se perdio, se da por 0
JUMP_X, JUMP_Y = 4000, 6000 # salto maximo de posicion entre frames (~19 % del eje en 4 ms): mayor = ruido hasta que otro frame lo confirme


class PenChip:
    """spi: objeto con read(addr, n) -> bytes y write_regs(addr, payload) (como las clases Spi/Tp de uke-touchd/fwload)."""

    HOST_CMD_OFF = 0x50

    def __init__(self, spi, event_buf, sleep=time.sleep):
        self.spi, self.addr, self.sleep = spi, event_buf + self.HOST_CMD_OFF, sleep
        self.enabled = False

    def _idle(self):
        return self.spi.read(self.addr, 2)[0] == 0

    def _cmd(self, data, tries, wait):
        for _ in range(tries):
            self.spi.write_regs(self.addr, bytes(data))
            self.sleep(wait)
            if self._idle():
                return True
        return False

    def enable(self):
        """Tras cada recarga de firmware y cada vez que el lapiz se despega (si esta conectado por BLE)."""
        if not self._idle():
            return False
        self.sleep(0.035)                    # msleep(35) de nvt_set_extend_custom_cmd
        ok = self._cmd([0xBF, 0x04, 0x00, 0x01, 0x00], 5, 0.020)
        if ok:
            self.sleep(0.022)
            ok = self._cmd([0x7B, 0x01], 10, 0.010)
        self.enabled = ok
        return ok

    def extra(self, data, name=""):
        """Comandos extendidos que Android manda ademas (RE-CHIP-MODO-LAPIZ §1/§8 A2–A3): msleep(35) y [BF sub 00 val 00] con ACK 5x20 ms."""
        if not self._idle():
            return False
        self.sleep(0.035)
        return self._cmd(data, 5, 0.020)

    def op_mode2(self):
        return self.extra([0xBF, 0x01, 0x00, 0x02, 0x00])      # nvt_xm_htc_set_op_mode: sub 0x01, valor 2

    def idle_baseline(self):
        return self.extra([0xBF, 0x19, 0x00, 0x01, 0x00])      # nvt_xm_htc_set_idle_baseline_update: sub 0x19, valor 1

    def disable(self):
        ok = self._cmd([0xBF, 0x04, 0x00, 0x00, 0x00], 5, 0.020) if self._idle() else False
        self.enabled = False if ok else self.enabled
        return ok


class PenSession:
    """Maquina de estados pura. feed_frame(F, now) y feed_ble(msg, now) devuelven listas de eventos:
       ("tool", bool) ("pos", x, y) ("touch", bool) ("pressure", p) ("btn", nombre, bool) ("enable", bool).
       La PUNTA la decide el contacto del chip (F+0x44); la presion BLE solo se emite mientras hay contacto (con suelo PRESSURE_FLOOR) y
       vuelve a 0 en el mismo instante en que se levanta (revision de arquitectura: libinput usa umbral de presion)."""

    MIN_FRAMES = 2          # frames «presentes» seguidos para entrar en rango (~4 % de falsos positivos de presencia, §21 M6)

    def __init__(self):
        self.connected = False
        self.attached = True        # sin informacion se asume pegado (no activar)
        self.in_range = False
        self.touching = False
        self.pressure = 0           # ultima presion BLE
        self.out_pressure = 0       # presion emitida (0 sin contacto)
        self.last_pen = None
        self.want_enable = False
        self._run = 0
        self._pos = None
        self._pending_jump = None
        self.last_ble = None        # ultimo mensaje BLE recibido (liveness del cliente)
        self.pressure_t = None      # ultimo mensaje de presion
        self.last_activity = None   # ultimo instante con presion BLE > 0 o frame de lapiz presente
        self.stats = {"frames": 0, "present": 0, "noise": 0, "bad": 0, "jumps": 0, "hall_ignored": 0, "hall_healed": 0}

    def _want(self):
        return self.connected and not self.attached

    def _enable_events(self):
        w = self._want()
        if w != self.want_enable:
            self.want_enable = w
            return [("enable", w)]
        return []

    def _active(self, now):
        return self.last_activity is not None and now - self.last_activity < ACTIVITY_S

    def _heal_hall(self, now):
        """Actividad real (presion BLE o frames) con el estado «pegado»: el aviso de hall era espurio (p. ej. tras el boton pequeño)."""
        if self.attached:
            self.attached = False
            self.stats["hall_healed"] += 1
            return self._enable_events()
        return []

    def _target_pressure(self):
        return max(self.pressure, PRESSURE_FLOOR) if (self.touching and self.in_range) else 0

    def _pressure_events(self):
        p = self._target_pressure()
        if p != self.out_pressure:
            self.out_pressure = p
            return [("pressure", p)]
        return []

    def release(self):
        """Suelta todo (panel apagado, BLE caido...): presion 0, punta y herramienta fuera."""
        ev = []
        if self.out_pressure:
            self.out_pressure = 0
            ev.append(("pressure", 0))
        if self.touching:
            self.touching = False
            ev.append(("touch", False))
        if self.in_range:
            self.in_range = False
            ev.append(("tool", False))
        self._run = 0
        self._pos = None
        self._pending_jump = None
        return ev

    def feed_ble(self, msg, now):
        ev = []
        if not isinstance(msg, dict):
            return ev
        self.last_ble = now
        was_conn = self.connected
        if isinstance(msg.get("connected"), bool):
            self.connected = msg["connected"]
        if isinstance(msg.get("attached"), bool):
            if msg["attached"] and self._active(now):
                self.stats["hall_ignored"] += 1              # «pegado» con el lapiz en uso: espurio, se ignora
            else:
                self.attached = msg["attached"]
        p = msg.get("pressure")
        if isinstance(p, float) and not math.isfinite(p):
            p = None                                         # NaN/Infinity (json.loads los acepta): int() lanzaria y mataria el modo lapiz
        if isinstance(p, (int, float)) and not isinstance(p, bool):
            self.pressure = max(0, min(PRESSURE_MAX, int(p)))
            self.pressure_t = now
            if self.pressure > 0:
                self.last_activity = now
                ev += self._heal_hall(now)
            ev += self._pressure_events()
        b = msg.get("btn")
        if isinstance(b, str) and b in BTN_CODES:
            ev.append(("btn", b, bool(msg.get("down", True))))
        if was_conn and not self.connected:
            self.pressure = 0
            ev += self.release()
        return self._enable_events() + ev

    def feed_frame(self, F, now):
        r = thp_pen.parse(F)
        self.stats["frames"] += 1
        if r is None:
            self.stats["bad"] += 1
            return []
        if not r["present"]:
            self.stats["noise"] += 1
            self._run = 0
            return []
        self.stats["present"] += 1
        self.last_pen = now
        self.last_activity = now
        self._run += 1
        ev = self._heal_hall(now)
        if not self.in_range:
            if self._run < self.MIN_FRAMES:
                return ev                                   # el 1.er frame presente aun no abre el rango, pero SI corrige un «pegado» espurio
            self.in_range = True
            ev.append(("tool", True))
        x, y = r["x"], r["y"]
        if self._pos is not None and (abs(x - self._pos[0]) > JUMP_X or abs(y - self._pos[1]) > JUMP_Y):
            pj = self._pending_jump
            if pj is not None and abs(x - pj[0]) <= JUMP_X and abs(y - pj[1]) <= JUMP_Y:
                self._pending_jump = None                       # un 2.o frame confirma el salto: es real
            else:
                self._pending_jump = (x, y)
                self.stats["jumps"] += 1
                x, y = self._pos                                # se retiene la posicion anterior un frame
        else:
            self._pending_jump = None
        self._pos = (x, y)
        ev.append(("pos", x, y))
        contact = bool(r["contact"])
        if contact != self.touching:
            self.touching = contact
            ev += self._pressure_events()
            ev.append(("touch", contact))
        return ev

    def tick(self, now):
        """Llamar periodicamente: libera el lapiz tras HOLD_S sin frames."""
        if self.connected and self.last_ble is not None and now - self.last_ble > BLE_SILENCE_S:
            return self.feed_ble({"connected": False}, now)           # cliente BLE mudo/muerto (SIGKILL, crash): sin esto «connected» queda True para siempre
        if self.pressure > 0 and not self.touching and self.pressure_t is not None and now - self.pressure_t > PRESSURE_STALE_S:
            self.pressure = 0                                          # se perdio el informe «presion 0»: si no, 200 rearmes seguidos (400 escrituras SPI)
        if self.in_range and self.last_pen is not None and now - self.last_pen > HOLD_S:
            return self.release()
        return []


_EV = struct.Struct("qqHHi")       # struct input_event de 64 bit, precompilado
_EV_PACK = _EV.pack


class PenUInput:
    def __init__(self, w, h, ioc):
        import fcntl
        self.fcntl, self.ioc = fcntl, ioc
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        U = ord("U")
        io = lambda nr, v: fcntl.ioctl(self.fd, ioc(1, U, nr, 4), v)  # noqa: E731
        io(100, EV_KEY); io(100, EV_ABS)
        for c in (BTN_TOOL_PEN, BTN_TOUCH, *BTN_CODES.values()):
            io(101, c)
        io(110, 1)  # INPUT_PROP_DIRECT
        # Sin ABS_TILT_X/Y: la inclinacion no esta decodificada (§27) y anunciar ejes que nunca se emiten confunde a libinput
        for code, lo, hi, res in ((ABS_X, 0, w - 1, 13), (ABS_Y, 0, h - 1, 13), (ABS_PRESSURE, 0, PRESSURE_MAX, 0)):
            io(103, code)
            fcntl.ioctl(self.fd, ioc(1, U, 4, 28), struct.pack("Hxxiiiiii", code, 0, lo, hi, 0, 0, res))
        setup = struct.pack("HHHH80sI", 0x18, 0x2717, 0x4D80, 1, b"uke Focus Pen", 0)
        fcntl.ioctl(self.fd, ioc(1, U, 3, len(setup)), setup)
        fcntl.ioctl(self.fd, ioc(0, U, 1, 0))
        self.buf = []

    def ev(self, t, c, v):
        self.buf.append(_EV_PACK(0, 0, t, c, v))

    def close(self):
        os.close(self.fd)

    def flush(self):
        self.ev(EV_SYN, 0, 0)
        os.write(self.fd, b"".join(self.buf))
        self.buf = []

    def apply(self, events, to_screen):
        for e in events:
            k = e[0]
            if k == "tool":
                self.ev(EV_KEY, BTN_TOOL_PEN, int(e[1]))
            elif k == "pos":
                sx, sy = to_screen(e[1], e[2])
                self.ev(EV_ABS, ABS_X, sx); self.ev(EV_ABS, ABS_Y, sy)
            elif k == "touch":
                self.ev(EV_KEY, BTN_TOUCH, int(e[1]))
            elif k == "pressure":
                self.ev(EV_ABS, ABS_PRESSURE, e[1])
            elif k == "btn":
                self.ev(EV_KEY, BTN_CODES[e[1]], int(e[2]))
        if self.buf:
            self.flush()


KEY_CODES = {"small": 189, "big_up": 104, "big_down": 109}     # KEY_F19, KEY_PAGEUP, KEY_PAGEDOWN (como el nodo de teclado del lapiz en Android)


class PenKeys:
    """Teclado uinput «uke Focus Pen Buttons»: los botones con el lapiz FUERA de rango (modo presentador / avance de diapositivas)."""

    def __init__(self, ioc):
        import fcntl
        self.fcntl, self.ioc = fcntl, ioc
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        U = ord("U")
        io = lambda nr, v: fcntl.ioctl(self.fd, ioc(1, U, nr, 4), v)  # noqa: E731
        io(100, EV_KEY)
        for c in KEY_CODES.values():
            io(101, c)
        setup = struct.pack("HHHH80sI", 0x18, 0x2717, 0x4D81, 1, b"uke Focus Pen Buttons", 0)
        fcntl.ioctl(self.fd, ioc(1, U, 3, len(setup)), setup)
        fcntl.ioctl(self.fd, ioc(0, U, 1, 0))

    def key(self, name, down):
        os.write(self.fd, _EV_PACK(0, 0, EV_KEY, KEY_CODES[name], int(down)) + _EV_PACK(0, 0, EV_SYN, 0, 0))

    def close(self):
        os.close(self.fd)


def open_ble_socket(path="/run/uke-lapiz.sock"):
    if os.path.exists(path):
        os.unlink(path)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    s.bind(path)
    os.chmod(path, 0o660)
    s.setblocking(False)
    return s


def read_ble(sock):
    """Vacia el socket y devuelve la lista de mensajes JSON validos (los demas se ignoran)."""
    out = []
    while True:
        try:
            data = sock.recv(1024)
        except BlockingIOError:
            return out
        try:
            m = json.loads(data.decode())
            if isinstance(m, dict):
                out.append(m)
        except (ValueError, UnicodeDecodeError):
            pass


class PenRuntime:
    """Fachada para uke-touchd: NINGUNA excepcion sale de aqui. Al primer fallo se desactiva el lapiz (se intenta BF 04 00 00 00) y el
    demonio sigue con el tactil. Metodos: fileno, on_socket, handles, on_frame, tick, set_ready, resync, shutdown, stats_line."""

    RETRY_S = 1.0
    MAX_TRIES = 20
    REARM_S = 1.0           # presion BLE (la punta toca) sin frames del chip: volver a mandar stylus_enable+pen_switch como mucho cada REARM_S
    REARM_AFTER = 0.3       # sin frames de lapiz durante tanto tiempo
    MAX_REARMS = 200
    OPMODE = os.environ.get("LAPIZ_OPMODE", "0") == "1"   # opcional: tras activar, op_mode=2 + idle_baseline (como Android). NO hace falta: el 20-oct hubo frames de lapiz sin ello

    def __init__(self, spi, event_buf, w, h, ioc, to_screen, log=print, ui_factory=None, sock_factory=None, sleep=time.sleep,
                 keys_factory=None):
        self._log = log
        self.log = lambda *m: self._log("[%.3f]" % time.monotonic(), *m)      # marca monotonica comun con el cliente BLE y evmon
        self.to_screen = to_screen
        self.keys = None
        self.btn_t = {}              # boton de teclado -> instante de la pulsacion (seguridad BTN_MAX_HOLD_S)
        self.btn_early = set()       # botones de tableta ya soltados al salir de rango: su «soltar» posterior por BLE se descarta
        self.btn_route = {}          # boton -> «stylus» (BTN_STYLUS*, lapiz en rango) o «key» (teclado, fuera de rango); el soltar sigue a la pulsacion
        self.dead = False
        self.ready = True
        self.chip = self.sess = self.ui = self.sock = None
        self.tries, self.last_try, self.last_stats = 0, 0.0, time.monotonic()
        self.last_rearm, self.rearms = -1e9, 0
        try:
            self.chip = PenChip(spi, event_buf, sleep=sleep)
            self.sess = PenSession()
            self.ui = (ui_factory or (lambda: PenUInput(w, h, ioc)))()
            self.sock = (sock_factory or open_ble_socket)()
            self.keys = (keys_factory or (lambda: PenKeys(ioc)))()
        except Exception as e:           # noqa: BLE001
            self._kill("init", e)

    # ---- aislamiento
    def _kill(self, where, e):
        if self.dead:
            return
        self.dead = True
        self.log("lapiz: ERROR en %s (%r): modo lapiz DESACTIVADO, el tactil sigue" % (where, e))
        try:
            if self.chip is not None and self.chip.enabled:
                self.chip.disable()
        except Exception:                # noqa: BLE001
            pass
        for o in (self.ui, self.sock, self.keys):
            try:
                if o is not None:
                    (o.close if hasattr(o, "close") else (lambda: os.close(o.fd)))()
            except Exception:            # noqa: BLE001
                pass

    def fileno(self):
        return -1 if self.dead or self.sock is None else self.sock.fileno()

    # ---- acciones
    def _enable(self, now):
        self.last_try = now
        self.tries += 1
        ok = self.chip.enable()
        self.log("lapiz: activar modo lapiz del chip -> %s (intento %d)" % ("ok" if ok else "SIN ACK", self.tries))
        if ok and self.OPMODE:
            self.log("lapiz: op_mode=2 -> %s, idle_baseline -> %s" % (
                "ok" if self.chip.op_mode2() else "SIN ACK", "ok" if self.chip.idle_baseline() else "SIN ACK"))
        return ok

    def _apply(self, evs, now):
        rest = []
        if any(e[0] == "tool" and not e[1] for e in evs):
            for name in [n for n, r in self.btn_route.items() if r == "stylus"]:   # soltar los botones de tableta ANTES de salir de rango
                self.btn_route.pop(name, None)
                self.btn_early.add(name)
                rest.append(("btn", name, False))
        for e in evs:
            if e[0] == "enable":
                if e[1]:
                    self.tries = 0
                    if self.ready:
                        self._enable(now)
                else:
                    ok = self.chip.disable()
                    self.log("lapiz: desactivar modo lapiz del chip -> %s" % ("ok" if ok else "SIN ACK"))
            elif e[0] == "btn":
                name, down = e[1], e[2]
                if not down and name in self.btn_early:
                    self.btn_early.discard(name)               # ya se soltó al salir de rango
                    continue
                if down:
                    self.btn_early.discard(name)
                    self.btn_route[name] = "stylus" if (self.sess.in_range and name in TABLET_BUTTONS) else "key"
                    self.btn_t[name] = now
                route = self.btn_route.get(name, "key") if down else self.btn_route.pop(name, "key")
                if not down:
                    self.btn_t.pop(name, None)
                if route == "key":
                    self.keys.key(name, down)
                else:
                    rest.append(e)
            else:
                rest.append(e)
        if rest:
            self.ui.apply(rest, self.to_screen)

    def _release_keys(self, why, now=None):
        """Suelta las teclas de boton que siguen pulsadas (el «soltar» no va a llegar: BLE caido, cliente muerto, timeout)."""
        for name in [n for n, r in self.btn_route.items() if r == "key" and (now is None or now - self.btn_t.get(n, now) > self.BTN_MAX_HOLD_S)]:
            self.btn_route.pop(name, None)
            self.btn_t.pop(name, None)
            self.keys.key(name, False)
            self.log("lapiz: tecla %s soltada (%s)" % (name, why))

    BTN_MAX_HOLD_S = BTN_MAX_HOLD_S

    def on_socket(self, now):
        if self.dead:
            return
        try:
            for m in read_ble(self.sock):
                was = self.sess.connected
                self._apply(self.sess.feed_ble(m, now), now)
                if was and not self.sess.connected:
                    self._release_keys("BLE desconectado")
        except Exception as e:           # noqa: BLE001
            self._kill("socket", e)

    def handles(self, F):
        """True si F es un frame de lapiz valido (magic 0x509 y complementos) y el lapiz esta activo en el demonio."""
        if self.dead:
            return False
        try:
            if len(F) < 0x14:
                return False
            fid, magic, nid, nmag = _HDR_UNPACK(F, 4)
            return magic == thp_pen.MAGIC_PEN and nmag == (~magic & 0xFFFF) and nid == (~fid & 0xFFFF)
        except Exception:                # noqa: BLE001
            return False

    def on_frame(self, F, now):
        if self.dead:
            return
        try:
            self._apply(self.sess.feed_frame(F, now), now)
        except Exception as e:           # noqa: BLE001
            self._kill("frame", e)

    def tick(self, now):
        if self.dead:
            return
        try:
            was = self.sess.connected
            self._apply(self.sess.tick(now), now)
            if was and not self.sess.connected:
                self._release_keys("cliente BLE mudo %.0f s" % BLE_SILENCE_S)
            self._release_keys("sin «soltar» en %.0f s" % BTN_MAX_HOLD_S, now)
            if (self.ready and self.sess.want_enable and not self.chip.enabled and now - self.last_try > self.RETRY_S
                    and self.tries < self.MAX_TRIES):
                self._enable(now)                                  # reintento real (revision I3)
            # El chip puede dejar el modo lapiz por su cuenta (20-oct: 23 s de frames y luego nada con el lapiz vivo y presionando por BLE):
            # si el lapiz presiona (BLE) y el chip no manda frames, se re-arma
            if (self.ready and self.chip.enabled and self.sess.pressure > 0 and self.sess.want_enable
                    and now - (self.sess.last_pen if self.sess.last_pen is not None else -1e9) > self.REARM_AFTER
                    and now - self.last_rearm > self.REARM_S and self.rearms < self.MAX_REARMS):
                self.last_rearm = now
                self.rearms += 1
                ok = self.chip.enable()
                self.log("lapiz: rearme %d (presion BLE %d sin frames del chip) -> %s" % (self.rearms, self.sess.pressure, "ok" if ok else "SIN ACK"))
            if now - self.last_stats > 30:
                self.last_stats = now
                self.log("lapiz: " + self.stats_line())
        except Exception as e:           # noqa: BLE001
            self._kill("tick", e)

    SILENCE_S = 2.0         # el chip no da NI UN frame (IRQ) en este tiempo con el modo lapiz activo: se le quita el modo lapiz
    SILENCE_HOLDOFF_S = 10.0

    def silence(self, now, last_irq):
        """20-oct 15:14: tras el boton pequeño el chip dejo de dar frames 55 s con el modo lapiz activo (tactil muerto) y el bucle del
        demonio, sin IRQ, ni siquiera llamaba a tick(). Se devuelve el chip al modo normal y se reintenta tras SILENCE_HOLDOFF_S."""
        if self.dead or not (self.ready and self.chip.enabled) or now - last_irq < self.SILENCE_S:
            return
        try:
            ok = self.chip.disable()
            self.log("lapiz: chip mudo %.1f s con modo lapiz -> desactivar %s; reintento en %.0f s" % (now - last_irq, "ok" if ok else "SIN ACK", self.SILENCE_HOLDOFF_S))
            self._apply(self.sess.release(), now)
            self.chip.enabled = False
            self.tries, self.last_try = 0, now + self.SILENCE_HOLDOFF_S - self.RETRY_S
            self.silences = getattr(self, "silences", 0) + 1
        except Exception as e:           # noqa: BLE001
            self._kill("silence", e)

    def set_ready(self, ready, now=0.0):
        """Llamar cuando cambie «panel listo y firmware cargado»: al perderlo se suelta el lapiz y se da el modo por perdido."""
        if self.dead or ready == self.ready:
            return
        self.ready = ready
        try:
            if not ready:
                self.chip.enabled = False
                self._apply(self.sess.release(), now)
        except Exception as e:           # noqa: BLE001
            self._kill("ready", e)

    def resync(self, now=0.0):
        """Tras recargar el firmware el chip pierde el modo lapiz: se reintenta (tick) si la sesion lo quiere."""
        if self.dead:
            return
        self.chip.enabled = False
        self.tries, self.last_try = 0, 0.0

    def shutdown(self):
        """SIGTERM/salida: BF 04 00 00 00 si estaba activo (nunca 7B 00 ni 7C, como Android) y soltar el lapiz."""
        if self.dead:
            return
        try:
            self._apply(self.sess.release(), 0.0)
            if self.chip.enabled:
                self.chip.disable()
        except Exception as e:           # noqa: BLE001
            self._kill("shutdown", e)

    def stats_line(self):
        st = self.sess.stats if self.sess else {}
        return "hall_ignorados=%d hall_corregidos=%d rearmes=%d frames0x509=%d presentes=%d ruido=%d malos=%d en_rango=%s tocando=%s presion_ble=%d modo_chip=%s" % (
            st.get("hall_ignored", 0), st.get("hall_healed", 0), self.rearms, st.get("frames", 0), st.get("present", 0), st.get("noise", 0), st.get("bad", 0),
            self.sess.in_range, self.sess.touching, self.sess.pressure, self.chip.enabled)
