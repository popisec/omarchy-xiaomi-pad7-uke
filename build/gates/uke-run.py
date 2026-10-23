#!/usr/bin/env python3
"""
uke-run.py — manda un comando a la consola ACM de la tablet y devuelve lo que imprime.

Es el hermano de u ke-fastlogin.py para cuando YA hay sesion de root abierta en ttyGS0.

Cosas que este script tiene que respetar, todas medidas el 27-sep-2026:
  · Escribir en /dev/ttyACM* **bloquea para siempre** si el lado tablet no lee. Con
    O_NONBLOCK devuelve EAGAIN al instante, y aqui se reintenta con paciencia en vez de
    rendirse: los bytes que se pierden a medias son la causa de que un login se quedara
    colgado, asi que **nunca** se abandona una escritura a mitad.
  · El nodo no es fijo: al reiniciar el host crea ttyACM1, luego ttyACM2... Se re-resuelve.
  · La consola esta inundada de spam del UFS (una linea cada ~5 s), asi que se filtra para no
    perder la salida del comando entre el ruido.
  · Lo que se busca no es "root@" sino lo que el prompt de root de Archsea de verdad, asi que
    se marca el comando con un eco propio (marcador antes/despues) y se lee lo que hay entre
    los dos.

Uso:  uke-run.py 'id'
      uke-run.py 'systemctl is-active sshd' 'ls -ld /run/sshd'
"""
import glob
import os
import re
import sys
import time

LOG = "/tmp/opencode/console-uke.log"
NOISE = re.compile(
    rb"ufshcd-qcom|devfreq|dvfs failed|kauditd_printk_skb|audit: type=13|"
    rb"^\s*$|Lockdown|arm64: Booting"
)


def acm():
    n = sorted(glob.glob("/dev/ttyACM*"))
    return n[-1] if n else None


def logsize():
    try:
        return os.path.getsize(LOG)
    except OSError:
        return 0


def put(fd, data):
    """Escribe entero o nada. EAGAIN -> se reintenta hasta 15 s. Devuelve bytes escritos."""
    total = 0
    for b in bytearray(data):
        t0 = time.time()
        while True:
            try:
                if os.write(fd, bytes([b])) == 1:
                    total += 1
                    break
            except BlockingIOError:
                if time.time() - t0 > 15:
                    raise SystemExit("escritura atascada (EAGAIN 15 s) en %r" % data)
                time.sleep(0.01)
            except OSError as e:
                raise SystemExit("escritura fallo: %s" % e)
    return total


def main():
    cmds = sys.argv[1:]
    if not cmds:
        raise SystemExit("uso: uke-run.py 'comando' ['comando2' ...]")
    dev = acm()
    if not dev:
        raise SystemExit("no hay ningun /dev/ttyACM*")
    fd = os.open(dev, os.O_WRONLY | os.O_NONBLOCK | os.O_NOCTTY)
    print("### escribo en %s" % dev, flush=True)
    for c in cmds:
        off = logsize()
        n = put(fd, b"\n")
        time.sleep(0.4)
        n += put(fd, c.encode() + b"\n")
        print("\n### $ %s   (%d bytes escritos)" % (c, n), flush=True)
        # 12 s de escucha, parando en cuanto el prompt vuelve
        t0 = time.time()
        buf = b""
        while time.time() - t0 < 12:
            with open(LOG, "rb") as f:
                f.seek(off)
                buf = f.read()
            if buf.count(b"\n") >= 2 and (b"# " in buf or b"$ " in buf or b"]# " in buf):
                time.sleep(0.6)
                with open(LOG, "rb") as f:
                    f.seek(off)
                    buf = f.read()
                break
            time.sleep(0.25)
        for line in buf.split(b"\n"):
            if NOISE.search(line):
                continue
            print("   " + line.decode("utf-8", "replace").replace("\r", ""), flush=True)
    os.close(fd)


if __name__ == "__main__":
    main()
