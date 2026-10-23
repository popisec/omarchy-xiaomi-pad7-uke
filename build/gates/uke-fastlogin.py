#!/usr/bin/env python3
"""
uke-fastlogin.py — entra por la consola ACM de la tablet en la ventana que da el getty.

POR QUÉ ESTE SCRIPT (los dos anteriores norottling)
----------------------------------------------------
1. Escribir en /dev/ttyACM0 **bloquea para siempre** si el lado tablet no lee: el buffer de
   entrada se llena, el dispositivo NACKEA y el `write()` del host no termina (medido: rc=124
   con `timeout 6`). Con O_NONBLOCK en su lugar devuelve EAGAIN al instante y el script nunca
   se cuelga (medido: errno 11 en 0.00 s).
2. El getty **agota su LoginTimeout y se retira** (medido: "login: timed out after 60 seconds",
   dos veces). Cuando se va, nadie lee ttyGS0, se acaba de llenar el buffer y las escrituras
   dan EAGAIN para siempre: es un deadlock. La única salida es reiniciar la tablet y meter el
   login DENTRO de la ventana de 60 s. Este script se queda escuchando el log y ataca en
   cuanto aparece el prompt.
3. systemd/getty emiten ESC[6n (cursor position request) y ESPERAN la respuesta. Contesta
   como un terminal real (ESC[<fila>;<col>R) en cuanto la ve, con un bucle de 50 ms, porque
   la ventana del prompt es corta.
4. La contraseña de root no va en el repo (rotada 22-oct-2026): se lee de $uke_root_pass o de ~/.config/omarchy-uke/root-tablet.pass.

Uso:  uke-fastlogin.py            # se queda en la consola hastaConseguir shell
      uke-fastlogin.py --once     # un solo intento y sale
"""
import glob
import os
import re
import sys
import time

# ⚠️ NO SE PUEDE FIJAR /dev/ttyACM0. Medido el 27-sep-2026: al reiniciar, el host crea el
# nodo con el índice SIGUIENTE (ttyACM1, ttyACM2...). El índice es del host, no del gadget.
# Un login atado a ttyACM0 pierde los 60 s del getty entera. Se re-resuelve en cada ciclo.
LOG = "/tmp/opencode/console-uke.log"
USER = "root"
PASS = os.environ.get("UKE_ROOT_PASS") or open(os.path.expanduser("~/.config/omarchy-uke/root-tablet.pass")).read().strip()
LOGIN_RE = re.compile(rb"login:")
PASSWD_RE = re.compile(rb"[Pp]assword")
SHELL_RE = re.compile(rb"\[root@|~ #|/# ")
DSR = b"\x1b[6n"
DSR_ANSWER = b"\x1b[20;1R"
ONCE = "--once" in sys.argv


def acm():
    """El nodo ttyACM* mas alto que exista ahora mismo."""
    nodes = sorted(glob.glob("/dev/ttyACM*"))
    return nodes[-1] if nodes else None


def open_dev():
    dev = acm()
    if not dev:
        return None, None
    try:
        return dev, os.open(dev, os.O_WRONLY | os.O_NONBLOCK | os.O_NOCTTY)
    except OSError:
        return dev, None


def put(fd, data):
    """Escribe sin bloquear nunca. Devuelve True si TODO salió.

    Paciencia: 5 s por byte. Un byte perdido deja la linea a medias, que es exactamente lo
    que hacia fallar el login, asi que aqui no se abandona a la primera de cambio.
    """
    ok = True
    for b in bytearray(data):
        t0 = time.time()
        while True:
            try:
                if os.write(fd, bytes([b])) == 1:
                    break
            except BlockingIOError:
                if time.time() - t0 > 5:
                    ok = False
                    break
                time.sleep(0.005)
            except OSError:
                ok = False
                break
    return ok


def tail_since(off):
    try:
        with open(LOG, "rb") as f:
            f.seek(off)
            return f.read()
    except OSError:
        return b""


def logsize():
    try:
        return os.path.getsize(LOG)
    except OSError:
        return 0


def main():
    dev, fd = open_dev()
    print("### esperando un nodo ttyACM* (nivel actual: %s)" % (dev,), flush=True)
    off = logsize()
    deadline = time.time() + 900
    phase = 0          # 0 esperando prompt, 1 esperando password, 2 esperando shell
    t_prompt = t_user = None
    attempt = 0
    reintentos = 0
    while time.time() < deadline:
        if fd is None:
            # el nodo aparece y desaparece en cada reinicio: re-resolver en cada vuelta
            dev, fd = open_dev()
            if fd is not None:
                print("### enganchado a %s" % dev, flush=True)
            time.sleep(0.2)
            continue
        buf = tail_since(off)
        if buf:
            off += len(buf)
            # 1) DSR primero: si aparece, se contesta ya
            if DSR in buf:
                put(fd, DSR_ANSWER)
                print("   DSR contestado", flush=True)
            if phase == 0 and LOGIN_RE.search(buf):
                attempt += 1
                if attempt > 1 and ONCE:
                    break
                print("   prompt de login visto -> mando '%s'" % USER, flush=True)
                # un solo \r: ver el aviso del reintento
                put(fd, USER.encode() + b"\r")
                t_user = time.time()
                reintentos = 0
                phase = 1
            elif phase == 1 and PASSWD_RE.search(buf):
                print("   prompt de password -> mando la clave", flush=True)
                time.sleep(0.25)
                put(fd, PASS.encode() + b"\r")
                phase = 2
            elif phase == 2 and (SHELL_RE.search(buf) or b"Login incorrect" in buf):
                if SHELL_RE.search(buf):
                    print("\n>>> SHELL CONSEGUIDA", flush=True)
                    return 0
                print("   login incorrecto", flush=True)
                phase = 0
        # vigilas de seguridad
        if phase == 1 and t_user and time.time() - t_user > 6:
            # La escritura del usuario se puede perder: el buffer del gadget da EAGAIN y un
            # byte a medias deja la linea a medias. Se REENVIA el usuario (hasta 4 veces) en vez
            # de volver a esperar un prompt que ya no va a aparecer. Medido: el primer
            # reintento se quedaba colgado en fase 1 sin reenviar nada.
            reintentos += 1
            if reintentos > 4:
                print("   el usuario no se entrega; abandono este arranque", flush=True)
                phase = 0
                reintentos = 0
            else:
                print("   no llego 'Password'; reenvio '%s' (intento %d)" % (USER, reintentos), flush=True)
                # ⚠️ UN SOLO \r, NUNCA \r\n. Con ICRNL activo, "\r\n" son DOS finales de
                # linea: el getty lee el usuario, y el segundo lo consume como una CONTRASENA
                # VACIA -> "Login incorrect". Medido: asi se producia el rechazo.
                put(fd, USER.encode() + b"\r")
                t_user = time.time()
        if phase == 0 and t_prompt and time.time() - t_prompt > 12:
            put(fd, b"\r")
            t_prompt = time.time()
        time.sleep(0.05)
    print(">>> se acabo el tiempo sin shell", flush=True)
    return 1


if __name__ == "__main__":
    sys.exit(main())
