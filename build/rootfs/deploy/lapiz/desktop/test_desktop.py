#!/usr/bin/env python3
"""Pruebas offline de lapiz/desktop (cd build/rootfs/deploy/lapiz/desktop && PYTHONPATH=..:. python3 -m unittest test_desktop -v).
Sin hardware: parche de palma sobre copia temporal, uke-pen-sync con un hyprctl falso, validacion de quirks/udev/lua y de la tabla de botones."""
import json, os, re, shutil, struct, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
LAPIZ = os.path.dirname(HERE)
TACTIL = os.path.join(LAPIZ, "..", "tactil")
sys.path.insert(0, LAPIZ)


def patched_touchd():
    d = tempfile.mkdtemp()
    for f in os.listdir(TACTIL):
        if f.endswith(".py"):
            shutil.copy(os.path.join(TACTIL, f), d)
    dst = os.path.join(d, "uke-touchd-pen.py")
    os.rename(os.path.join(d, "uke-touchd.py"), dst)
    for p in ("uke-touchd-pen.patch", os.path.join("desktop", "uke-touchd-palm.patch")):
        r = subprocess.run(["patch", "-p0", dst, os.path.join(LAPIZ, p)], capture_output=True, text=True)
        assert r.returncode == 0, r.stdout + r.stderr
    return d, dst


class PalmPatch(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir, cls.path = patched_touchd()
        import importlib.util
        spec = importlib.util.spec_from_file_location("touchd_palm", cls.path)
        cls.m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.m)

    def test_compiles_and_original_untouched(self):
        subprocess.run([sys.executable, "-m", "py_compile", self.path], check=True)
        with open(os.path.join(TACTIL, "uke-touchd.py")) as f:
            self.assertNotIn("PalmGuard", f.read())

    def test_guard_blocks_in_range_and_hold(self):
        g = self.m.PalmGuard(hold=0.5)
        pts = [(7, 100, 100, 20)]
        self.assertEqual(g.filter(pts, 10.0, False), (pts, False))          # sin lapiz pasa
        g.pen_seen(10.0)
        out, cancel = g.filter(pts, 10.2, False)
        self.assertEqual((out, cancel), ([], True))                          # dentro del margen: bloqueado
        self.assertEqual(g.filter(pts, 10.4, True)[0], [])                   # en rango: bloqueado aunque pase el margen
        out, cancel = g.filter(pts, 10.6, False)                             # margen vencido, pero la palma sigue (mismo tid): ignorada
        self.assertEqual((out, cancel), ([], False))
        new = [(8, 300, 300, 20)]
        self.assertEqual(g.filter(pts + new, 10.7, False)[0], new)           # un dedo nuevo si pasa
        self.assertEqual(g.filter(new, 10.8, False)[0], new)                 # la palma se levanto: su tid sale del ban
        self.assertNotIn(7, g.ban)

    def test_area_threshold(self):
        g = self.m.PalmGuard(hold=0.5, area=40)
        self.assertEqual(g.filter([(1, 0, 0, 50), (2, 0, 0, 10)], 0.0, False)[0], [(2, 0, 0, 10)])

    def test_cancel_all_events(self):
        r, w = os.pipe()
        u = object.__new__(self.m.UInput)
        u.fd, u.slot_of, u.buf = w, {5: 0, 6: 1}, []
        for mode in ("palm", "lift"):                                        # ambos modos: levantado normal, SIN ABS_MT_TOOL_TYPE (rompia el pellizco)
            u.slot_of = {5: 0, 6: 1}
            u.cancel_all(mode)
            raw = os.read(r, 4096)
            evs = [struct.unpack_from("qqHHi", raw, i)[2:] for i in range(0, len(raw), 24)]
            self.assertNotIn(0x37, [c for t, c, v in evs])
            self.assertEqual(evs.count((3, 0x39, -1)), 2)                    # fin de tracking
            self.assertIn((1, 0x14a, 0), evs)
            self.assertEqual(evs[-1], (0, 0, 0))
            self.assertEqual(u.slot_of, {})

    def test_uinput_does_not_declare_mt_tool_type(self):
        """21:40 20-oct: declarar ABS_MT_TOOL_TYPE en el uinput del dedo rompia el pellizco de 2 dedos."""
        with open(self.path) as f:
            src = f.read()
        self.assertNotIn("ABS_MT_TOOL_TYPE", src.replace("NO se usa MT_TOOL_PALM: declarar ABS_MT_TOOL_TYPE", ""))


class PenSync(unittest.TestCase):
    def run_sync(self, deg, touchmap=None, penmap=None):
        st = tempfile.mkdtemp()
        open(os.path.join(st, "deg"), "w").write("%s\n" % deg)
        if touchmap:
            open(os.path.join(st, "touchmap"), "w").write(touchmap)
        if penmap:
            open(os.path.join(st, "penmap"), "w").write(penmap)
        env = dict(os.environ, UKE_ROTATE_STATE=st, HYPRCTL="echo")
        return subprocess.run([os.path.join(HERE, "uke-pen-sync"), "--dry-run"], capture_output=True, text=True, env=env)

    def test_default_follows_touch_map(self):
        for deg, tf in ((0, 0), (90, 1), (180, 2), (270, 3)):
            r = self.run_sync(deg)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn('transform=%d' % tf, r.stdout)
            self.assertIn('output="DSI-1"', r.stdout)

    def test_maps(self):
        self.assertIn("transform=3", self.run_sync(90, touchmap="0 3 2 1").stdout)
        self.assertIn("transform=2", self.run_sync(90, touchmap="0 3 2 1", penmap="0 2 0 0").stdout)   # penmap manda sobre touchmap
        self.assertNotEqual(self.run_sync(90, penmap="0 9 2 3").returncode, 0)                          # mapa invalido
        self.assertIn("transform=0", self.run_sync("basura").stdout)                                    # estado corrupto -> 0

    def test_bash_syntax(self):
        subprocess.run(["bash", "-n", os.path.join(HERE, "uke-pen-sync")], check=True)


class Configs(unittest.TestCase):
    def test_lua(self):
        luac = shutil.which("luac")
        if not luac:
            self.skipTest("sin luac")
        subprocess.run([luac, "-p", os.path.join(HERE, "hyprland-pen.lua")], check=True)
        lua = shutil.which("lua")
        if lua:  # ejecutar con un hl falso: comprueba que la tabla de config y los hooks son los esperados
            stub = ("local calls={} hl={config=function(t) calls[#calls+1]=t end,on=function(e,f) calls[#calls+1]=e end,"
                    "exec_cmd=function() end} o={bind=function() end} dofile(os.getenv('F')) "
                    "assert(calls[1].input.tablet.output=='DSI-1') assert(calls[2]=='hyprland.start' and calls[3]=='config.reloaded') print('ok')")
            r = subprocess.run([lua, "-e", stub], capture_output=True, text=True, env=dict(os.environ, F=os.path.join(HERE, "hyprland-pen.lua")))
            self.assertEqual(r.stdout.strip(), "ok", r.stderr)

    def test_quirks(self):
        txt = open(os.path.join(HERE, "50-uke-pen.quirks")).read()
        keys = set(re.findall(r"^([A-Za-z]+)=", txt, re.M))
        known = {"MatchUdevType", "MatchVendor", "MatchProduct", "MatchName", "MatchBus", "AttrTabletSmoothing", "AttrPressureRange"}
        self.assertLessEqual(keys, known)
        if os.path.isdir("/usr/share/libinput"):        # verdad local: claves usadas por los .quirks de sistema de libinput instalado
            sysk = set()
            for f in os.listdir("/usr/share/libinput"):
                sysk |= set(re.findall(r"^([A-Za-z]+)=", open("/usr/share/libinput/" + f).read(), re.M))
            self.assertLessEqual(keys, sysk)
        self.assertEqual(len(re.findall(r"^\[.*\]$", txt, re.M)), 1)
        self.assertRegex(txt, r"MatchVendor=0x2717\n")                        # formato doc: 0x + 4 digitos hex en mayusculas
        self.assertRegex(txt, r"MatchProduct=0x4D80\n")
        self.assertIn("AttrTabletSmoothing=0", txt)

    def test_udev_rules(self):
        if not shutil.which("udevadm"):
            self.skipTest("sin udevadm")
        r = subprocess.run(["udevadm", "verify", os.path.join(HERE, "71-uke-pen.rules")], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_systemd_units(self):
        if not shutil.which("systemd-analyze"):
            self.skipTest("sin systemd-analyze")
        d = tempfile.mkdtemp()
        for f in ("uke-pen-sync.path", "uke-pen-sync.service"):
            shutil.copy(os.path.join(HERE, "systemd", f), d)
        r = subprocess.run(["systemd-analyze", "verify", "--user", os.path.join(d, "uke-pen-sync.path")], capture_output=True, text=True)
        self.assertNotIn("Unknown key", r.stderr + r.stdout)          # /usr/local/bin/uke-pen-sync no existe aqui: ese aviso es esperado

    def test_buttons_table_matches_daemon(self):
        import uke_pen as U
        t = json.load(open(os.path.join(HERE, "botones.json")))
        for name, row in t["botones"].items():
            self.assertEqual(row["evento_tableta"], U.BTN_CODES[name] if name in U.TABLET_BUTTONS else None)
            self.assertEqual(row["tecla_fuera_de_rango"], U.KEY_CODES[name])
        self.assertEqual(t["botones"]["small"]["evento_tableta"], 0x14B)
        self.assertEqual(t["punta"]["evento"], ["BTN_TOUCH", "ABS_PRESSURE"])
        self.assertEqual(t["goma"], None)


if __name__ == "__main__":
    unittest.main(verbosity=2)
