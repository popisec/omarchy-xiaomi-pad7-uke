#!/usr/bin/env python3
"""osk-latencia.py — latencia de aparicion/ocultacion del teclado en pantalla (ESCRITORIO-TACTIL 22-oct-2026).

Se ejecuta EN LA TABLET como omarchy (con el entorno de la sesion). Necesita una ventana con un campo de texto
enfocado (por defecto gnome-text-editor: su texto recibe el foco al abrir).
Ciclo: enfocar un escritorio vacio (el teclado se oculta) -> enfocar la ventana con texto -> esperar el evento
`openlayer>>omarchy-keyboard` del socket2 de Hyprland. t = desde justo antes de lanzar hyprctl hasta el evento,
menos el coste medido de un `hyprctl eval` vacio (lanzar el proceso).
Uso: osk-latencia.py [N=10] [clase=uke.oskprueba] [clase_sin_texto]   (sin la 3.a: un escritorio vacio)
"""
import json, os, socket, statistics, subprocess, sys, time

N = int(sys.argv[1]) if len(sys.argv) > 1 else 10
CLS = sys.argv[2] if len(sys.argv) > 2 else "uke.oskprueba"
AWAY = sys.argv[3] if len(sys.argv) > 3 else ""
RT = os.environ["XDG_RUNTIME_DIR"]
SIG = os.environ["HYPRLAND_INSTANCE_SIGNATURE"]


def hypr(lua):
    subprocess.run(["hyprctl", "eval", lua], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


def wait_event(sock, prefix, timeout):
    end = time.monotonic() + timeout
    buf = b""
    while time.monotonic() < end:
        sock.settimeout(max(0.01, end - time.monotonic()))
        try:
            data = sock.recv(65536)
        except socket.timeout:
            break
        if not data:
            break
        buf += data
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            if line.decode(errors="replace").startswith(prefix):
                return time.monotonic()
    return None


def main():
    clients = json.loads(subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True).stdout)
    target = next((c for c in clients if c.get("class") == CLS), None)
    if not target:
        sys.exit(f"no hay ventana de clase {CLS}")
    addr = target["address"]
    away = 'hl.dispatch(hl.dsp.focus({ workspace = "empty" }))'
    if AWAY:
        a = next((c for c in clients if c.get("class") == AWAY), None)
        if not a:
            sys.exit(f"no hay ventana de clase {AWAY}")
        away = f'hl.dispatch(hl.dsp.focus({{ window = "address:{a["address"]}" }}))'
    # coste de lanzar hyprctl (se resta)
    over = []
    for _ in range(5):
        t = time.monotonic(); hypr("return 1"); over.append(time.monotonic() - t)
    ov = statistics.median(over)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(f"{RT}/hypr/{SIG}/.socket2.sock")
    shows, hides = [], []
    for i in range(N):
        t0 = time.monotonic()
        hypr(away)
        t1 = wait_event(s, "closelayer>>omarchy-keyboard", 3)
        if t1:
            hides.append(t1 - t0 - ov)
        time.sleep(0.6)
        t0 = time.monotonic()
        hypr(f'hl.dispatch(hl.dsp.focus({{ window = "address:{addr}" }}))')
        t1 = wait_event(s, "openlayer>>omarchy-keyboard", 3)
        shows.append(None if t1 is None else t1 - t0 - ov)
        time.sleep(0.8)
    ok = [x for x in shows if x is not None]
    ms = lambda v: f"{v * 1000:.0f}"
    print(f"hyprctl (restado): {ms(ov)} ms")
    print(f"aparicion: {len(ok)}/{N}  mediana {ms(statistics.median(ok)) if ok else '-'} ms  "
          f"min {ms(min(ok)) if ok else '-'}  max {ms(max(ok)) if ok else '-'}  muestras {[ms(x) if x else 'NO' for x in shows]}")
    if hides:
        print(f"ocultacion: {len(hides)}/{N}  mediana {ms(statistics.median(hides))} ms (incluye el retardo de 250 ms a proposito)")


if __name__ == "__main__":
    main()
