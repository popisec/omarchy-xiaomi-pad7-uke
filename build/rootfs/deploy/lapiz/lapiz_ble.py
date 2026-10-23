"""lapiz_ble.py — protocolo BLE del Xiaomi Focus Pen (M80P): handshake, informe de presion y botones.

19-oct-2026. Fuente: btsnoop de Android y de Linux (LAPIZ-20261018.md §16, §20; PROTOCOLO-BLE-LAPIZ.md). Sin dependencias.
GATT: servicio fe10aa6c-462a-964a-7f2ed5b3e512: fe11 (comandos, write-without-response), fe12 (notificaciones, CCCD).
HID-over-GATT: informe 1 (raton aereo), 2 (teclado = botones), 5 (vendor 14 B: presion).
"""
import time

FREQ_M80P = bytes.fromhex("9b6fef43")   # codigo de frecuencia TX fijado por Android en el handshake (indice 0 de su tabla M80P)
P30_TAIL = bytes.fromhex("a01e3e171a04")
# usages del informe de teclado -> boton
BUTTONS = {0x6E: "small", 0x4B: "big_up", 0x4E: "big_down"}


def handshake(mac, hall, now=None, freq=FREQ_M80P):
    """Lista de 15 comandos (bytes) a escribir en fe11, en orden. mac: 6 bytes de la MAC BT del host; hall: 0 pegado, 1 despegado."""
    if len(mac) != 6:
        raise ValueError("mac debe tener 6 bytes")
    now = int(time.time() if now is None else now)

    def p30(idx):
        tail = bytes([0x1A, 0x03 if idx == 0 else 0x01, 0, 0]) + bytes.fromhex("0d680000052800000d68f401")
        return b"\x30\x1e" + mac + b"\x03" + bytes([idx]) + P30_TAIL + tail

    seq = [bytes.fromhex(x) for x in ("5200", "0000", "0100", "0200", "0300", "0400")]
    seq += [p30(0), b"\x31\x08\x00\x03" + freq + b"\x28\x00", b"\x32\x03\x00\x28\x00", b"\x04\x00"]
    seq += [p30(1), b"\x31\x08\x01\x03" + freq + b"\x28\x00", b"\x32\x03\x01\x28\x00"]
    seq += [b"\x33\x04" + now.to_bytes(4, "big"), b"\x51\x01" + bytes([hall])]
    return seq


def expected_acks():
    """Respuesta esperada por fe12 para cada comando (el lapiz responde opcode|0x80 salvo los indicados), segun la captura."""
    return ["d20101", "8001ff", "81024702", "82020000", "8303010100", "840100", "b000", "b100", "b200", "840101", "b000", "b100", "b200", "b300", "d100"]


def parse_pressure_report(b):
    """Informe 5 (14 B): devuelve dict(pressure 0..8191, freq=bytes 4..7 hex, counter u16, raw). None si longitud != 14."""
    if len(b) != 14:
        return None
    return {"pressure": int.from_bytes(b[0:2], "little"), "freq": b[4:8].hex(), "counter": int.from_bytes(b[8:10], "little"),
            "status": b[10:13].hex()}


def parse_keyboard_report(b):
    """Informe de teclado (1 B de usage; 0 = soltar). Devuelve ('down', nombre) / ('up', None) / ('unknown', usage)."""
    if len(b) != 1:
        return ("unknown", b.hex())
    u = b[0]
    if u == 0:
        return ("up", None)
    return ("down", BUTTONS[u]) if u in BUTTONS else ("unknown", u)
