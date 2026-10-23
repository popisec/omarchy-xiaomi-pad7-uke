#!/usr/bin/env python3
"""Pruebas offline de uke_lapiz_ble.py (analisis de la salida real de bluetoothctl)."""
import json, os, signal, socket, stat, subprocess, sys, tempfile, textwrap, time, unittest

import uke_lapiz_ble as L

LIN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "android", "lapiz-20261019", "linux")


class ParseTests(unittest.TestCase):
    SAMPLE = ("\x1b[0;94m[Xiaomi Focus Pen]> \x1b[0m\n[CHG] Attribute /org/bluez/hci0/dev_70_61_EE_XX_XX_XX/service001c/char002d Value:\n"
              "[Xiaomi Focus Pen:/service001c/char002d]> \n    \n  5c 1b 00 00 9b 6f ef 43 cb 2d ff 54 54 a1        .\\...o.C.-.TT.  \n"
              "[CHG] Attribute /org/bluez/hci0/dev_70_61_EE_XX_XX_XX/service001c/char0029 Value:\n  6e                                              n\n"
              "[CHG] Attribute /org/bluez/hci0/dev_70_61_EE_XX_XX_XX/service001c/char0029 Value:\n  00                                              .\n"
              "[CHG] Attribute /org/bluez/hci0/dev_70_61_EE_XX_XX_XX/service0034/char0037 Value:\n  53 01 01                                        S..\n")

    def test_parse(self):
        items = L.parse_stream(self.SAMPLE)
        self.assertEqual([c for c, _ in items], ["service001c/char002d", "service001c/char0029", "service001c/char0029", "service0034/char0037"])
        self.assertEqual(items[0][1].hex(), "5c1b00009b6fef43cb2dff5454a1")

    def test_messages(self):
        st = {}
        m = []
        for c, d in L.parse_stream(self.SAMPLE):
            m += L.to_messages(c, d, st)
        self.assertEqual(m, [{"pressure": 0x1b5c}, {"btn": "small", "down": True}, {"btn": "small", "down": False},
                             {"attached": True}])

    def test_pressure_deduplicated(self):
        st = {}
        d = bytes.fromhex("0a000000" "9b6fef43" "0000" "ff5454" "a1")
        self.assertEqual(L.to_messages("service001c/char002d", d, st), [{"pressure": 10}])
        self.assertEqual(L.to_messages("service001c/char002d", d, st), [])

    def test_chunked_notifications_not_lost(self):
        full = self.SAMPLE
        # partir en trozos arbitrarios (incluso por la mitad de una linea hex): el resultado debe ser identico al analisis completo
        want = L.parse_stream(full)
        for step in (1, 2, 3, 7, 13, 50):
            buf, got = "", []
            for i in range(0, len(full), step):
                buf += full[i:i + step]
                items, buf = L.parse_chunk(buf)
                got += items
            items, buf = L.parse_chunk(buf + "\n")
            got += items
            self.assertEqual(got, want, "step=%d" % step)

    def test_hall_echo_ignored_after_write(self):
        st = {"hall_write_t": 10.0}
        d = bytes.fromhex("530100")
        self.assertEqual(L.to_messages("service0034/char0037", d, st, now=10.5), [])        # eco de nuestro 51 01
        self.assertEqual(L.to_messages("service0034/char0037", d, st, now=12.0), [{"attached": False}])

    def test_reports5_counted(self):
        st = {}
        d = bytes.fromhex("0a000000" "9b6fef43" "0000" "ff5454" "a1")
        L.to_messages("service001c/char002d", d, st)
        L.to_messages("service001c/char002d", d, st)
        self.assertEqual(st["reports5"], 2)

    def test_conn_cache_rate_limits(self):
        calls = []
        orig = L.btctl
        L.btctl = lambda *a, **k: calls.append(a) or "Connected: yes"
        try:
            c = L.ConnCache(period=60)
            for _ in range(100):
                self.assertTrue(c())
            self.assertEqual(len(calls), 1)
        finally:
            L.btctl = orig

    def test_conn_cache_follows_monitor_without_polling(self):
        calls = []
        orig = L.btctl
        L.btctl = lambda *a, **k: calls.append(a) or "Connected: yes"
        try:
            c = L.ConnCache(period=60)
            c.set(True)
            self.assertTrue(c())
            c.set(False)
            self.assertFalse(c())
            self.assertEqual(calls, [])                      # el monitor basta: ni una llamada a bluetoothctl
            self.assertTrue(c(force=True))                   # forzar si consulta
            self.assertEqual(len(calls), 1)
        finally:
            L.btctl = orig

    def test_parse_busctl_connected(self):
        tpl = ('{"member":"PropertiesChanged","path":"/org/bluez/hci0/dev_70_61_EE_XX_XX_XX","payload":{"data":["org.bluez.Device1",'
               '{"Connected":{"type":"b","data":%s}},[]]}}')
        self.assertIs(L.parse_busctl_connected(tpl % "true"), True)
        self.assertIs(L.parse_busctl_connected(tpl % "false"), False)
        self.assertIsNone(L.parse_busctl_connected(tpl.replace("Device1", "Battery1") % "true"))
        self.assertIsNone(L.parse_busctl_connected('{"member":"PropertiesChanged","path":"/org/bluez/hci0/dev_AA","payload":{"data":["org.bluez.Device1",{"Connected":{"data":true}},[]]}}'))
        self.assertIsNone(L.parse_busctl_connected("basura"))

    def test_busctl_monitor_real_sample(self):
        fx = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "busctl-monitor-sample.jsonl")
        with open(fx) as f:
            lines = f.read().splitlines()
        items = [L.parse_busctl_line(l) for l in lines]
        self.assertTrue(all(i is not None for i in items))
        chars = {c for c, _ in items}
        self.assertIn("service001c/char002d", chars)
        st, msgs = {}, []
        for c, d in items:
            msgs += L.to_messages(c, d, st, now=1000.0)
        self.assertTrue(any("pressure" in m for m in msgs))
        self.assertEqual(st["reports5"], sum(1 for c, _ in items if c.endswith("char002d")))

    def test_busctl_line_filters_noise(self):
        self.assertIsNone(L.parse_busctl_line('{"member":"PropertiesChanged","path":"/org/bluez/hci0/dev_AA_BB/service0001/char0002","payload":{"data":["x",{"Value":{"data":[1]}},[]]}}'))
        self.assertIsNone(L.parse_busctl_line("no es json dev_70_61_EE_XX_XX_XX/service PropertiesChanged"))
        self.assertIsNone(L.parse_busctl_line(""))
        rssi = ('{"member":"PropertiesChanged","path":"/org/bluez/hci0/dev_70_61_EE_XX_XX_XX/service001c/char0029",'
                '"payload":{"data":["org.bluez.GattCharacteristic1",{"Notifying":{"data":true}},[]]}}')
        self.assertIsNone(L.parse_busctl_line(rssi))                 # PropertiesChanged sin Value

    def test_unknown_ignored(self):
        self.assertEqual(L.to_messages("service001c/char0025", b"\0\0\0\0", {}), [])
        self.assertEqual(L.to_messages("service0034/char0037", bytes.fromhex("d100"), {}), [])


HERE = os.path.dirname(os.path.abspath(__file__))
SAMPLE_FX = os.path.join(HERE, "fixtures", "busctl-monitor-sample.jsonl")
NOISE = ('{"type":"signal","path":"/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF","interface":"org.freedesktop.DBus.Properties","member":"PropertiesChanged",'
         '"payload":{"type":"sa{sv}as","data":["org.bluez.Device1",{"RSSI":{"type":"n","data":-60}},[]]}}')


def script(d, name, body):
    p = os.path.join(d, name)
    with open(p, "w") as f:
        f.write("#!/bin/sh\n" + textwrap.dedent(body))
    os.chmod(p, 0o755)
    return p


def rd(p):
    with open(p) as f:
        return f.read()


def old_json_parse(line):                     # el analizador de referencia (json.loads) anterior a la version barata
    m = json.loads(line)
    d = m["payload"]["data"]
    if m.get("member") != "PropertiesChanged" or len(d) < 2 or "Value" not in d[1]:
        return None
    return m["path"].split("dev_70_61_EE_XX_XX_XX/")[-1], bytes(d[1]["Value"]["data"])


class FastParseTests(unittest.TestCase):
    def test_bytes_parser_matches_json_reference(self):
        with open(SAMPLE_FX, "rb") as f:
            lines = f.read().splitlines()
        for ln in lines:
            self.assertEqual(L.parse_busctl_bytes(ln), old_json_parse(ln))
            self.assertEqual(L.parse_busctl_line(ln.decode()), old_json_parse(ln))
        # formas raras: Value vacio, formato con espacios (respaldo json), basura
        empty = ('{"member":"PropertiesChanged","path":"/org/bluez/hci0/dev_70_61_EE_XX_XX_XX/service001c/char0029","payload":{"type":"sa{sv}as",'
                 '"data":["x",{"Value":{"type":"ay","data":[]}},[]]}}')
        self.assertEqual(L.parse_busctl_line(empty), ("service001c/char0029", b""))
        spaced = ('{"member": "PropertiesChanged", "path": "/org/bluez/hci0/dev_70_61_EE_XX_XX_XX/service001c/char0029", "payload": {"data": '
                  '["x", {"Value": {"data": [110]}}, []]}}')
        self.assertEqual(L.parse_busctl_line(spaced), ("service001c/char0029", b"n"))
        self.assertIsNone(L.parse_busctl_line(b'dev_70_61_EE_XX_XX_XX/service "member":"PropertiesChanged" "Value" {{{'))
        self.assertIsNone(L.parse_busctl_bytes(b'{"member":"PropertiesChanged","path":"/x/dev_70_61_EE_XX_XX_XX/service1/char2","payload":{"data":["x",{"Value":{"type":"ay","data":[999999999999999999999999,x]}},[]]}}'))

    def test_parse_cost_50k_lines(self):
        with open(SAMPLE_FX, "rb") as f:
            base = f.read().splitlines()
        lines = [base[i % len(base)] if i % 4 else NOISE.encode() for i in range(50000)]
        t0 = time.perf_counter()
        n = 0
        for ln in lines:
            if b'"Connected"' in ln:
                L.parse_busctl_connected(ln)
            if L.parse_busctl_bytes(ln):
                n += 1
        us = (time.perf_counter() - t0) / len(lines) * 1e6
        print("\n[bench] %d lineas, %d con Value, %.2f us/linea" % (len(lines), n, us))
        self.assertEqual(n, sum(1 for i in range(50000) if i % 4 and old_json_parse(base[i % len(base)]) is not None))
        self.assertLess(us, 60)               # el json.loads anterior costaba ~19 us en este PC; holgura para la tablet cargada


class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.d.name, "s.sock")
        self.rx = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        self.rx.bind(self.path)
        self.rx.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
        self.rx.setblocking(False)

    def tearDown(self):
        self.rx.close()
        self.d.cleanup()

    def drain(self):
        out = []
        while True:
            try:
                out.append(json.loads(self.rx.recv(4096)))
            except BlockingIOError:
                return out

    def test_full_receiver_never_blocks_and_keeps_buttons_and_last_state(self):
        pub = L.Publisher(self.path)
        self.addCleanup(pub.close)
        self.assertFalse(pub.s.getblocking())
        t0 = time.monotonic()
        pub.send({"btn": "small", "down": True})
        for i in range(1, 3000):                       # el receptor no lee: la cola del kernel se llena enseguida
            pub.send({"pressure": i})
            if i == 1500:
                pub.send({"btn": "small", "down": False})
        pub.send({"attached": True})
        pub.send({"attached": False})
        self.assertLess(time.monotonic() - t0, 2.0)    # un sendto bloqueante habria colgado aqui
        self.assertGreater(pub.dropped_full, 0)
        self.assertLess(len(pub.q), 10)                # solo 1 presion, 1 attached y los 2 botones pendientes como mucho
        got = []
        for _ in range(100):                           # el receptor vuelve a leer
            got += self.drain()
            pub.flush()
            if not pub.q:
                got += self.drain()
                break
        self.assertFalse(pub.q)
        btns = [m for m in got if "btn" in m]
        self.assertEqual(btns, [{"btn": "small", "down": True}, {"btn": "small", "down": False}])   # ningun boton perdido ni reordenado
        self.assertEqual([m["pressure"] for m in got if "pressure" in m][-1], 2999)                  # la ultima presion llega
        self.assertEqual([m["attached"] for m in got if "attached" in m][-1], False)

    def test_buttons_bounded_memory(self):
        pub = L.Publisher(self.path)
        self.addCleanup(pub.close)
        while True:                                    # llena el kernel
            try:
                pub.s.sendto(b"x" * 100, self.path)
            except BlockingIOError:
                break
        for i in range(L.MAXQ * 3):
            pub.send({"btn": "big_up", "down": bool(i % 2)})
        self.assertLessEqual(len(pub.q), L.MAXQ)

    def test_absent_receiver_counts_and_does_not_queue(self):
        pub = L.Publisher(os.path.join(self.d.name, "no-existe.sock"))
        self.addCleanup(pub.close)
        for _ in range(5):
            pub.send({"pressure": 1})
        self.assertEqual((pub.dropped_absent, len(pub.q)), (5, 0))
        dead = os.path.join(self.d.name, "muerto.sock")           # fichero de socket sin nadie escuchando -> ConnectionRefusedError
        s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        s.bind(dead)
        s.close()
        pub2 = L.Publisher(dead)
        self.addCleanup(pub2.close)
        pub2.send({"btn": "small", "down": True})
        self.assertEqual((pub2.dropped_absent, len(pub2.q)), (1, 0))


class FakeBinTests(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.TemporaryDirectory()
        self.orig = (L.BUSCTL, L.BTCTL)

    def tearDown(self):
        L.BUSCTL, L.BTCTL = self.orig
        self.d.cleanup()

    def test_mute_busctl_is_restarted_reaped_and_probed(self):
        pidf = os.path.join(self.d.name, "pids")
        mute = script(self.d.name, "mute.sh", 'echo $$ >> %s\necho \'{"type":"x"}\'\nexec sleep 60\n' % pidf)
        probe = script(self.d.name, "probe.sh", "echo probe >> %s.probe\n" % pidf)
        L.BUSCTL = probe
        mon = L.Monitor(silence=0.6, cmd=[mute])
        try:
            first = mon.p
            t0 = time.monotonic()
            while mon.restarts == 0 and time.monotonic() - t0 < 5:
                r, _, _ = __import__("select").select([mon.fileno()], [], [], 0.05)
                if r:
                    mon.read_lines(time.monotonic())
                mon.watchdog(time.monotonic(), True)
            self.assertEqual(mon.restarts, 1)
            self.assertGreaterEqual(mon.probes, 1)                       # sonda a N/2
            self.assertIsNotNone(first.poll())                           # el viejo esta muerto y recogido (sin zombi)
            with self.assertRaises(ChildProcessError):
                os.waitpid(first.pid, os.WNOHANG)
            self.assertTrue(os.path.exists(pidf + ".probe"))
        finally:
            mon.close()
        # inactivo (sin lapiz conectado) no reinicia
        mon = L.Monitor(silence=0.3, cmd=[mute])
        try:
            time.sleep(0.5)
            self.assertFalse(mon.watchdog(time.monotonic(), False))
            self.assertEqual(mon.restarts, 0)
        finally:
            mon.close()

    def test_dead_busctl_restarts(self):
        die = script(self.d.name, "die.sh", "exit 0\n")
        mon = L.Monitor(silence=0, cmd=[die])
        try:
            t0 = time.monotonic()
            while mon.restarts < 2 and time.monotonic() - t0 < 5:
                time.sleep(0.05)
                mon.read_lines(time.monotonic())
            self.assertGreaterEqual(mon.restarts, 2)
        finally:
            mon.close()

    def test_timers_run_while_busctl_is_mute(self):
        mute = script(self.d.name, "mute.sh", "exec sleep 60\n")
        sent = []

        class Pub:
            q = ()
            def send(self, m): sent.append(m)
            def flush(self): pass

        class Conn:
            v = True
            def set(self, v): self.v = v
            def tick(self, now=None): return self.v

        mon = L.Monitor(silence=0, cmd=[mute])
        try:
            s = L.Session(Pub(), {"attached_value": False}, Conn(), mon, [], announce_now=True)
            for k in range(1, 8):
                s.step(now=k * 1.0, max_wait=0.001)      # 7 s "simulados" sin una sola linea de busctl
            conns = [m for m in sent if m == {"connected": True}]
            self.assertEqual(len(conns), 3)               # t=3,5,7: cada 2 s (t_state arranca en 0)
            self.assertEqual(len([m for m in sent if "attached" in m]), 3)
        finally:
            mon.close()

    def test_session_end_to_end_with_fake_busctl_flood(self):
        with open(SAMPLE_FX) as f:
            lines = f.read()
        fx = os.path.join(self.d.name, "lines.jsonl")
        with open(fx, "w") as f:
            f.write(lines * 20)
        src = script(self.d.name, "flood.sh", "cat %s\nexec sleep 60\n" % fx)
        sent = []

        class Pub:
            q = ()
            def send(self, m): sent.append(m)
            def flush(self): pass

        class Conn:
            v = True
            def set(self, v): self.v = v
            def tick(self, now=None): return self.v

        mon = L.Monitor(silence=0, cmd=[src])
        try:
            s = L.Session(Pub(), {}, Conn(), mon, [])
            t0 = time.monotonic()
            while mon.lines < 39 * 20 and time.monotonic() - t0 < 5:
                s.step(max_wait=0.05)
            self.assertEqual(mon.lines, 39 * 20)
            self.assertTrue(any("pressure" in m for m in sent))
        finally:
            mon.close()

    def test_conn_cache_tick_is_async_and_kills_hung_info(self):
        hang = script(self.d.name, "bt.sh", "exec sleep 60\n")
        L.BTCTL = hang
        c = L.ConnCache(period=0, tmo=0.3)
        t0 = time.monotonic()
        c.tick()                                         # lanza el hijo y vuelve al instante
        self.assertLess(time.monotonic() - t0, 0.2)
        self.assertIsNotNone(c.proc)
        child = c.proc
        time.sleep(0.4)
        c.tick()
        self.assertIsNone(c.proc)
        self.assertIsNotNone(child.poll())               # matado y recogido
        ok = script(self.d.name, "bt2.sh", "echo 'Connected: yes'\n")
        L.BTCTL = ok
        c = L.ConnCache(period=0)
        c.tick()
        t0 = time.monotonic()
        while c.v is None and time.monotonic() - t0 < 3:
            time.sleep(0.02)
            c.tick()
        self.assertIs(c.v, True)

    def test_btctl_timeout_returns_empty(self):
        L.BTCTL = script(self.d.name, "bt.sh", "exec sleep 60\n")
        t0 = time.monotonic()
        self.assertEqual(L.btctl("info", "x", timeout=0.3), "")
        self.assertLess(time.monotonic() - t0, 2)

    def _flood_script(self, flag, n=20000):
        # escribe ~2 MB (muy por encima de los 64 KiB de la tuberia) y SOLO si no se bloquea crea el fichero testigo
        return script(self.d.name, "flood2.sh", 'i=0\nwhile [ $i -lt %d ]; do echo \'{"type":"signal","member":"x","payload":"%s"}\'; i=$((i+1)); done\n'
                      'echo ok > %s\nexec sleep 60\n' % (n, "y" * 60, flag))

    def test_stalled_consumer_never_blocks_busctl(self):
        """Regresion 22-oct 03:50: si el bucle deja de leer, busctl se bloquea escribiendo y el broker acumula su cola hasta expulsar a logind.
        Aqui NADIE llama a read_lines: el productor debe acabar igualmente y la cola quedar acotada (descartando lo viejo)."""
        flag = os.path.join(self.d.name, "flag")
        mon = L.Monitor(silence=0, cmd=[self._flood_script(flag)], qmax=100)
        try:
            t0 = time.monotonic()
            while not os.path.exists(flag) and time.monotonic() - t0 < 10:
                time.sleep(0.05)
            self.assertTrue(os.path.exists(flag), "busctl se bloqueo: nadie vaciaba la tuberia")
            self.assertLessEqual(len(mon.q), 100)
            self.assertGreater(mon.dropped, 19000)                       # lo viejo se tiro
            self.assertEqual(mon.restarts, 0)
            lines = mon.read_lines(time.monotonic())                      # y al volver a leer llegan las MAS NUEVAS
            self.assertEqual(len(lines), 100)
        finally:
            mon.close()

    def test_run_drains_busctl_while_pen_is_disconnected(self):
        """El camino exacto del fallo: run() esperando al lapiz (time.sleep / bluetoothctl connect) sin ninguna Session leyendo el monitor."""
        flag = os.path.join(self.d.name, "flag")
        bt = script(self.d.name, "bt.sh", 'case "$1" in info) echo "Connected: no";; *) :;; esac\n')
        env = dict(os.environ, LAPIZ_BTCTL=bt, LAPIZ_BUSCTL=self._flood_script(flag), PYTHONPATH=HERE)
        p = subprocess.Popen([sys.executable, "-c", "import sys, uke_lapiz_ble as L; sys.exit(L.run())"], env=env,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            t0 = time.monotonic()
            while not os.path.exists(flag) and time.monotonic() - t0 < 10:
                time.sleep(0.05)
            self.assertTrue(os.path.exists(flag), "run() dejo de vaciar busctl mientras el lapiz no estaba conectado")
        finally:
            p.send_signal(signal.SIGTERM)
            p.wait(timeout=5)

    def test_monitor_default_cmd_has_match_filter(self):
        argf = os.path.join(self.d.name, "args")
        L.BUSCTL = script(self.d.name, "rec.sh", 'echo "$@" > %s\nexec sleep 60\n' % argf)
        mon = L.Monitor(silence=0)
        try:
            t0 = time.monotonic()
            while not os.path.exists(argf) and time.monotonic() - t0 < 3:
                time.sleep(0.02)
            time.sleep(0.1)
            args = rd(argf)
            self.assertIn("--match", args)
            self.assertIn("member='PropertiesChanged'", args)
            self.assertIn("path_namespace='%s'" % L.DEV, args)
        finally:
            mon.close()

    def test_sigterm_clean_exit_no_orphans(self):
        pids = os.path.join(self.d.name, "pids")
        bt = script(self.d.name, "bt.sh", """
            case "$1" in
              info) echo 'Connected: yes'; echo 'ServicesResolved: yes';;
              show) echo 'Controller AA:BB:CC:DD:EE:FF (public)';;
              *) echo bt $$ >> %s; exec cat >/dev/null;;
            esac
            """ % pids)
        bus = script(self.d.name, "bus.sh", "echo bus $$ >> %s\nexec sleep 60\n" % pids)
        env = dict(os.environ, LAPIZ_BTCTL=bt, LAPIZ_BUSCTL=bus, PYTHONPATH=HERE)
        p = subprocess.Popen([sys.executable, "-c", "import sys, uke_lapiz_ble as L; sys.exit(L.run())"], env=env,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        t0 = time.monotonic()
        while time.monotonic() - t0 < 5 and not (os.path.exists(pids) and len(rd(pids).split("\n")) > 2):
            time.sleep(0.05)
        p.send_signal(signal.SIGTERM)
        self.assertEqual(p.wait(timeout=5), 0)
        time.sleep(0.3)
        for ln in rd(pids).splitlines():
            pid = int(ln.split()[1])
            with self.assertRaises(ProcessLookupError):
                os.kill(pid, 0)                              # ningun hijo huerfano


@unittest.skipUnless(os.path.exists(os.path.join(LIN, "lapiz-hid-penenable.raw")), "sin registros de la tablet")
class RealLogTests(unittest.TestCase):
    def test_real_run_pressure(self):
        with open(os.path.join(LIN, "lapiz-hid-penenable.raw"), errors="replace") as f:
            text = f.read()
        st, msgs = {}, []
        for c, d in L.parse_stream(text):
            msgs += L.to_messages(c, d, st)
        pr = [m["pressure"] for m in msgs if "pressure" in m]
        self.assertGreater(len(pr), 10)
        self.assertGreater(max(pr), 1000)                  # medido: hasta 1345 en esa prueba
        self.assertLessEqual(max(pr), 8191)


if __name__ == "__main__":
    unittest.main(verbosity=2)
