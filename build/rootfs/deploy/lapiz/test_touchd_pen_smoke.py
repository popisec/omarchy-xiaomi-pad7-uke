#!/usr/bin/env python3
"""Humo del parche: aplica uke-touchd-pen.patch a una copia de tactil/uke-touchd.py y comprueba que compila y que main() contiene
las defensas (PenRuntime, SIGTERM, unregister del fd, liberacion del dedo). No ejecuta hardware."""
import os, subprocess, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TD = os.path.join(HERE, "..", "tactil", "uke-touchd.py")


class PatchTests(unittest.TestCase):
    def test_patch_applies_and_compiles(self):
        d = tempfile.mkdtemp()
        dst = os.path.join(d, "uke-touchd.py")
        with open(TD) as f, open(dst, "w") as o:
            o.write(f.read())
        self.addCleanup(lambda: None)
        r = subprocess.run(["patch", "-p0", dst, os.path.join(HERE, "uke-touchd-pen.patch")], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        subprocess.run(["python3", "-m", "py_compile", dst], check=True)
        with open(dst) as f:
            src = f.read()
        for needle in ("PenRuntime", "signal.SIGTERM", "poller.unregister(pen_fd)", "rt.set_ready", "rt.resync", "rt.handles(F)",
                       "ui.frame([]); was_down = False", "def write_regs", "stop_req.append(1)"):
            self.assertIn(needle, src)
        # el original no cambia sin --pen: el parche solo anade, no elimina lineas del camino tactil
        with open(os.path.join(HERE, "uke-touchd-pen.patch")) as f:
            removed = [l for l in f.read().splitlines() if l.startswith("-") and not l.startswith("---")]
        self.assertLessEqual(len(removed), 6, removed)


    def test_idle_sleep_cannot_run_away_during_full_rate_burst(self):
        """20-oct: con frames a ~226 Hz (lapiz) next_idle se adelantaba al reloj 1/60 s por vuelta y al acabar la rafaga se dormian decenas
        de segundos (tactil y lapiz muertos). Se ejecuta el bloque real del bucle de reposo con un reloj simulado."""
        d = tempfile.mkdtemp()
        dst = os.path.join(d, "uke-touchd.py")
        with open(TD) as f, open(dst, "w") as o:
            o.write(f.read())
        subprocess.run(["patch", "-p0", dst, os.path.join(HERE, "uke-touchd-pen.patch")], check=True, capture_output=True)
        with open(dst) as fh:
            lines = fh.read().splitlines()
        i = next(k for k, l in enumerate(lines) if l.strip() == "t = time.monotonic()" and lines[k + 1].strip().startswith("if t - last_touch > hold"))
        j = next(k for k in range(i, len(lines)) if "time.monotonic()" in lines[k] and "next_idle = max(" in lines[k])
        end = j + 1
        while lines[end].strip().startswith(("else:", "next_idle = t")):
            end += 1
        block = "\n".join(l[12:] for l in lines[i:end])            # sangria del bucle: 12 espacios
        clock = [0.0]
        slept = []

        class T:
            monotonic = staticmethod(lambda: clock[0])

            @staticmethod
            def sleep(x):
                slept.append(x)
                clock[0] += x
        ns = dict(time=T, next_idle=0.0, last_touch=0.0, hold=0.5, idle_period=3 / 180.0)
        code = compile(block, "bloque", "exec")
        for _ in range(8000):                                      # 30 s de rafaga a ~226 Hz: last_touch = now en cada vuelta
            clock[0] += 1 / 226.0
            ns["last_touch"] = clock[0]
            exec(code, ns)
        for _ in range(400):                                       # reposo: nunca duerme mas de un periodo
            clock[0] += 1 / 226.0                                  # el poll() tarda lo que tarda el siguiente frame
            exec(code, ns)
        self.assertLessEqual(max(slept or [0]), ns["idle_period"] + 1e-9, max(slept or [0]))
        self.assertLessEqual(clock[0] - 8000 / 226.0, 400 * ns["idle_period"] + 1.0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
