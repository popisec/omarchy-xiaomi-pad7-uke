#!/usr/bin/env python3
"""lapiz-handshake.py — arranque BLE del Xiaomi Focus Pen (M80P) desde Linux. Probado el 19-oct-2026: los 15 comandos reciben ACK.

Replica el handshake capturado de Android (btsnoop, LAPIZ-20261018.md §16 / PROTOCOLO-BLE-LAPIZ.md):
  servicio fe10aa6c-462a-964a-7f2ed5b3e512, fe11 = comandos (write-without-response), fe12 = notificaciones (CCCD).
  Secuencia: 52 00 | 00 00 | 01 00 | 02 00 | 03 00 | 04 00 | 30 1e <MAC BT host> ... | 31 08 00 03 <freq> 28 00 |
             32 03 00 28 00 | 04 00 | 30 ... 01 ... | 31 08 01 03 <freq> 28 00 | 32 03 01 28 00 | 33 04 <unix BE> | 51 01 <hall>.
Usa bluetoothctl (sin gi/bleak en la tablet): menu gatt + select-attribute + write. El lápiz debe estar conectado.
Uso:  lapiz-handshake.py [--hall 0|1] [--dry-run]   (dry-run solo imprime los comandos)
"""
import argparse, subprocess, sys, time, glob, re

PEN = "02:00:5E:00:00:07"
sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
import lapiz_ble  # noqa: E402  (la secuencia vive en lapiz_ble.handshake, cubierta por test_lapiz.py)


def hostmac():
    out = subprocess.run(["bluetoothctl", "show"], capture_output=True, text=True).stdout
    m = re.search(r"Controller ([0-9A-F:]{17})", out)
    return bytes.fromhex(m.group(1).replace(":", "")) if m else None


def cmds(hall, mac):
    if mac is None:
        sys.exit("no se pudo leer la MAC del controlador local (bluetoothctl show): no se envia nada")
    return lapiz_ble.handshake(mac, hall)


def char_path(uuid_suffix):
    # fe11 / fe12: caracteristicas del servicio fe10aa6c (resueltas por busctl)
    tree = subprocess.run(["busctl", "tree", "org.bluez", "--list"], capture_output=True, text=True).stdout.split()
    dev = "dev_" + PEN.replace(":", "_")
    for p in tree:
        if dev in p and "/char" in p and "/desc" not in p:
            u = subprocess.run(["busctl", "get-property", "org.bluez", p, "org.bluez.GattCharacteristic1", "UUID"], capture_output=True, text=True).stdout
            if "0000%s-aa6c" % uuid_suffix in u:
                return p
    return None


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--hall", type=int, default=0); ap.add_argument("--dry-run", action="store_true"); ap.add_argument("--mac", help="MAC del host para --dry-run (aa:bb:cc:dd:ee:ff)")
    a = ap.parse_args()
    seq = cmds(a.hall, bytes.fromhex(a.mac.replace(":", "")) if a.mac else hostmac())
    if a.dry_run:
        for c in seq: print(c.hex())
        return
    w, n = char_path("fe11"), char_path("fe12")
    if not (w and n): sys.exit("fe11/fe12 no encontradas: ¿lapiz conectado y servicios resueltos?")
    lines = ["menu gatt", "select-attribute " + n, "notify on"]
    for c in seq:
        lines += ["select-attribute " + w, "write \"" + " ".join("0x%02x" % b for b in c) + "\" 0 command", "!sleep 0.35"]
    lines += ["!sleep 1", "back", "quit"]
    # bluetoothctl no tiene "!sleep": se intercala con retardos desde Python
    p = subprocess.Popen(["bluetoothctl"], stdin=subprocess.PIPE, text=True)  # la salida (acks por fe12) va a stdout del script
    for l in lines:
        if l.startswith("!sleep"): time.sleep(float(l.split()[1])); continue
        p.stdin.write(l + "\n"); p.stdin.flush(); time.sleep(0.1)
    p.wait(timeout=30)


if __name__ == "__main__":
    main()
