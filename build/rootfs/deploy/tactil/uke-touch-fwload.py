#!/usr/bin/env python3
"""uke-touch-fwload.py — cargador de firmware en espacio de usuario del tactil NT36532 (TDDI, SPI, "Cascade Chip").

18-oct-2026. Python puro (ioctl de spidev, sin modulos externos). Requiere /dev/spidev0.0 (spidev ligado a spi0.0,
ver README.md de esta carpeta). Replica la secuencia que hace el driver del vendor (nt36532_touch.ko,
"nvt_version_2024.01.13-001") en nvt_update_firmware -> nvt_download_firmware_hw_crc, con el chip detectado como
"Cascade Chip", hw_crc = 2, auto_copy = 2. Informe con direcciones del .ko y fuentes: build/gates/revision/TACTIL-FWLOAD-20261018.md

MODOS (ninguno escribe sin --execute; --dry-run se puede combinar con --verify-only):
  --parse-only    solo analiza el .bin (cabecera, particiones, CRC) — sin SPI, sin dispositivo
  --dry-run       recorre TODA la secuencia imprimiendo cada transferencia SPI sin ejecutarla (simula las lecturas);
                  ademas reconstruye la SRAM virtual y comprueba que cada particion cae en su direccion
  --verify-only   SOLO LECTURAS (+ seleccion de pagina): chip_ver_trim, bit cascade, FWINFO/estado de reset en los
                  mapas cascade y single, registros BLD CRC. NO hace reset (un reset mataria un firmware vivo)
  --execute       escribe de verdad (reset del bootloader + descarga a SRAM + arranque + comprobacion)

Secuencia (vendor, ko 0x10e24-0x11088; todas las direcciones de registro del NT36532_cascade_memory_map):
  1. bootloader reset: write 0x69 -> 0x1fb43e (swrst_sif), espera
  2. set_bld_crc_bank ILM y DLM: DES<-SRAM_addr(24b), LENGTH<-size(24b), G_CHECKSUM<-crc(32b)
  3. tx auto copy (el bin trae cascade_2nd_header_info=1): write 0x56 -> 0x1fc925
  4. nvt_write_firmware: por cada particion con size!=0 escribe size+1 bytes a SRAM_addr (por bloques)
  5. espera auto copy: sondea 0x1fc925 hasta 0 (200 x 1 ms)
  6. fw_crc_enable: EVENT_BUF+0x60 <- 0 (x6), EVENT_BUF+0x50 <- 0xAE
  7. boot_ready: write 0x01 -> 0x1fb50d, espera
  8. check_fw_reset_state(0xA0): EVENT_BUF+0x60 en [0xA0,0xAF] (10 reintentos x 10 ms)
  9. get_fw_info: EVENT_BUF+0x78, 39 B; fw_ver + ~fw_ver == 0xFF
Reintentos del vendor: 3 intentos de descarga (si falla el estado de reset), 4 de FWINFO.

Protocolo SPI (RE del .ko; coincide con uke-touch-probe.py salvo el set_page, que aqui es EXACTO al vendor, 3 B):
  set_page(addr): escritura [0xFF][A22:15][A14:7]         (CTP_SPI_WRITE de 3 bytes; el probe mandaba un 0x00 de mas)
  write(addr, p): [ (addr&0x7F)|0x80 ][p...]              (tras set_page; CTP_SPI_WRITE: primer byte |0x80)
  read(addr, n):  full-duplex [addr&0x7F][0x00*(n+1)]     (datos desde rx[2])
"""
import argparse, ctypes, fcntl, hashlib, os, struct, sys, time

DEV = "/dev/spidev0.0"
SPEED_DEFAULT = 4_000_000      # el probe leyo bien a 4 MHz; el vendor usa 19,2 MHz (spi-max-frequency del DT)

# ---------------------------------------------------------------------------------------------------------------
# Mapa de memoria NT36532_cascade_memory_map (.rodata+0x9ecc del .ko) — campo = indice*4 de la tabla de 51 u32.
# (el chip de la uke se detecta como "Cascade Chip": bit0 de 0x1fb12c == 0; ver nvt_ts_check_chip_ver_trim_loop)
# ---------------------------------------------------------------------------------------------------------------
CASCADE = dict(
    EVENT_BUF=0x11c400,        # [0]
    BOOT_RDY=0x1fb50d,         # [33]  +0x84
    TX_AUTO_COPY_EN=0x1fc925,  # [35]  +0x8c
    ILM_LENGTH=0x1fb518,       # [38]  +0x98
    DLM_LENGTH=0x1fb530,       # [39]  +0x9c
    ILM_DES=0x1fb528,          # [41]  +0xa4
    DLM_DES=0x1fb52c,          # [42]  +0xa8
    G_ILM_CHECKSUM=0x1fb500,   # [43]  +0xac
    G_DLM_CHECKSUM=0x1fb504,   # [44]  +0xb0
    R_ILM_CHECKSUM=0x1fb520,   # [45]  +0xb4
    R_DLM_CHECKSUM=0x1fb524,   # [46]  +0xb8
    BLD_CRC_STATUS=0x1fb533,   # [48]  +0xc0  (nvt_read_bld_hw_crc: bit2 crc_done, bit0 ilm_crc_flag, bit1 dlm_crc_flag)
)
# mapa single (NT36532_single_memory_map, .rodata+0x9e00): solo EVENT_BUF difiere de lo que usamos.
SINGLE_EVENT_BUF = 0x125800    # el que usaba uke-touch-probe.py: NO es el mapa de este chip (cascade)
CHIP_VER_TRIM = 0x1fb104       # hw_reg_addr_info[0] (+ SWRST_SIF y CRC_ERR_FLAG, mismos que en el log de Android)
SWRST_SIF = 0x1fb43e           # hw_reg_addr_info[1]
CRC_ERR_FLAG = 0x1fb535        # hw_reg_addr_info[2]
CASCADE_DETECT = 0x1fb12c      # single_map[27]/[28] = {addr, mask 0x01}: bit0=1 -> Single Chip, bit0=0 -> Cascade Chip
ENG_RST_ADDR = 0x7fff80        # global ENG_RST_ADDR (.data+0); solo en el camino sin hw_crc; NO se usa aqui
EVT_HOST_CMD = 0x50            # EVENT_MAP_HOST_CMD (offset dentro de EVENT_BUF)
EVT_RESET_COMPLETE = 0x60      # EVENT_MAP_RESET_COMPLETE
EVT_FWINFO = 0x78              # EVENT_MAP_FWINFO
CMD_BOOTLOADER_RESET = 0x69
AUTO_COPY_MODE2_VALUE = 0x56   # nvt_tx_auto_copy_mode, ts->auto_copy == 2 (NT36532_hw_info.auto_copy = 2)
CMD_FW_CRC_ENABLE = 0xAE
RESET_STATE_INIT = 0xA0        # el vendor llama nvt_check_fw_reset_state(0xA0)
RESET_STATE_MAX = 0xAF
FW_RST_RETRY = 10              # 10 si reset_state == 0xA0 (50 en otro caso)
# tiempos: vendor __const_udelay(5000) tras el reset y tras boot_ready; usleep_range(10000) en cada reintento de estado
DEFAULT_RESET_WAIT_MS = 35     # el driver GPL RFC (Chan, 2024) espera 35 ms; el vendor 5 ms: aqui >= vendor
DEFAULT_BOOT_WAIT_MS = 10      # GPL RFC "old logic 5ms, retention to 10ms"; vendor 5 ms
# valores esperados tras la descarga (log de Android 17-oct 17.77 s, nvt_get_fw_info: fw_ver=0x11, fw_type=0x01, PID=0x5993,
# abs_x_max=32000, abs_y_max=21360, y el FW_VER del propio bin = 0x11). OJO: 0x0E / 2136x3200 NO son del firmware:
# 0x0E es el 1er byte de chip_ver_trim y 2136x3200 son los defaults/DT de cuando FWINFO esta roto.
EXPECT = dict(fw_ver=0x11, fw_type=0x01, pid=0x5993, x_max=32000, y_max=21360)
CHIP_ID_TAIL = bytes([0x32, 0x65, 0x03])  # trim_id_table[0] (NT36532): id ff ff ff 32 65 03, mascara 00 00 00 01 01 01


# ---------------------------------------------------------------------------------------------------------------
# Analisis del .bin (nvt_get_fw_need_write_size + nvt_bin_header_parser del vendor, inlinados en nvt_update_firmware)
# ---------------------------------------------------------------------------------------------------------------
class Part:
    def __init__(self, name, bin_addr, sram_addr, size, crc):
        self.name, self.bin_addr, self.sram_addr, self.size, self.crc = name, bin_addr, sram_addr, size, crc

    def __repr__(self):
        return "%-10s BIN 0x%06x -> SRAM 0x%06x size 0x%06x (+1 = %d B) crc 0x%08x" % (
            self.name, self.bin_addr, self.sram_addr, self.size, self.size + 1 if self.size else 0, self.crc)


def u32(d, o):
    return struct.unpack_from("<I", d, o)[0]


_T = []
for _i in range(256):
    _c = _i << 24
    for _ in range(8):
        _c = ((_c << 1) ^ 0x04C11DB7) & 0xFFFFFFFF if _c & 0x80000000 else (_c << 1) & 0xFFFFFFFF
    _T.append(_c)


def nvt_crc(data):
    """CRC de las particiones del bin (verificada contra el .bin real: ILM, DLM y las dos cabeceras):
    CRC-32 poly 0x04C11DB7 MSB-first, init 0xFFFFFFFF, sin xorout, sobre los datos con cada palabra de 32 bits
    invertida (LE -> BE). Cubre size+1 bytes (ILM/DLM); en las cabeceras, los 252 primeros (el crc va en los 4 ultimos)."""
    if len(data) % 4:
        raise ValueError("longitud no multiplo de 4")
    sw = struct.pack(">%dI" % (len(data) // 4), *struct.unpack("<%dI" % (len(data) // 4), data))
    c = 0xFFFFFFFF
    for b in sw:
        c = ((c << 8) & 0xFFFFFFFF) ^ _T[((c >> 24) ^ b) & 0xFF]
    return c


class FwBin:
    def __init__(self, data):
        self.data = data
        self.problems = []
        self.parse()

    def parse(self):
        d = self.data
        n = len(d)
        # nvt_get_fw_need_write_size (ko 0xfe68-0x10038): desde el final, el primer sector de 4 KiB que acaba en "NVT" o "MOD"
        self.need = None
        for i in range(n // 4096, 0, -1):
            tag = d[i * 4096 - 3:i * 4096]
            if tag in (b"NVT", b"MOD"):
                self.need, self.endflag = i * 4096, tag.decode()
                break
        if self.need is None:
            raise ValueError('flag final "NVT"/"MOD" no encontrado')
        # FW_VER + FW_VER_BAR == 0xFF (ko 0x100b4-0x100dc): bytes need-0x1000 y need-0xfff
        self.fw_ver, self.fw_ver_bar = d[self.need - 0x1000], d[self.need - 0xFFF]
        if (self.fw_ver + self.fw_ver_bar) != 0xFF:
            raise ValueError("FW_VER(0x%02x) + FW_VER_BAR(0x%02x) != 0xFF" % (self.fw_ver, self.fw_ver_bar))
        # nvt_bin_header_parser (ko 0x100e0-0x10970)
        self.end = u32(d, 0)
        self.cascade = (d[0x20] & 0x02) >> 1                       # cascade_2nd_header_info
        info = 0
        pos = 0x30
        lim = self.end // 2 if self.cascade else self.end
        while pos < lim:
            info += 1
            pos += 0x10
        if self.cascade:
            info += 1                                               # "next header section"
        self.info_sec_num = info
        self.ovly_info = (d[0x28] & 0x10) >> 4
        self.ovly_sec_num = (d[0x28] & 0x0F) if self.ovly_info else 0
        self.ilm_dlm_num = 2
        self.partition = self.ilm_dlm_num + self.ovly_sec_num + self.info_sec_num
        parts = []
        header_seen = False
        pos = 0x30
        for lst in range(self.partition):
            if lst < 2:                                             # ILM / DLM: {BIN, SRAM, size} x12 B, crc @0x18+4*lst
                p = Part("ILM" if lst == 0 else "DLM", u32(d, lst * 12), u32(d, lst * 12 + 4), u32(d, lst * 12 + 8),
                         u32(d, 0x18 + 4 * lst))
            elif lst < self.info_sec_num + 2:                      # Info: {SRAM, size, BIN, crc} x16 B desde 0x30
                if not header_seen:
                    pos = lst * 16 + 0x10
                elif self.cascade:
                    pos = self.end - 16                             # ko 0x1051c-0x1052c
                sram, size, bina, crc = struct.unpack_from("<4I", d, pos)
                if bina < self.end and size != 0:                  # ko 0x10610-0x1063c: nombre "Header", header_seen = 1
                    name, header_seen = "Header", True
                else:
                    name = "Info-%d" % (lst - 2)
                p = Part(name, bina, sram, size, crc)
            else:                                                   # Overlay (no hay en este bin; formula del ko, SIN VERIFICAR)
                pos = self.parts_bin1 + 0x10 * (lst - 2 - self.info_sec_num) if hasattr(self, "parts_bin1") else 0
                sram, size, bina, crc = struct.unpack_from("<4I", d, pos)
                p = Part("Overlay-%d" % (lst - 2 - self.info_sec_num), bina, sram, size, crc)
            if lst == 1:
                self.parts_bin1 = p.bin_addr
            if p.bin_addr + p.size > n:
                raise ValueError("%s: acceso 0x%08x..0x%08x mayor que el bin (%d)" % (p.name, p.bin_addr, p.bin_addr + p.size, n))
            parts.append(p)
        self.parts = parts
        if self.ovly_sec_num:
            self.problems.append("overlays (%d): formula del ko NO verificada con datos reales" % self.ovly_sec_num)

    def check_crc(self):
        """Comprueba el crc dorado de cada particion contra el recalculado (verificado para ILM, DLM y cabeceras)."""
        res = []
        for p in self.parts:
            if p.size == 0:
                continue
            ln = p.size + 1
            if p.name == "Header":
                ln -= 4                                              # el crc esta en los 4 ultimos bytes de la cabecera
            c = nvt_crc(self.data[p.bin_addr:p.bin_addr + ln])
            res.append((p, c, c == p.crc))
        return res

    def partitions_to_write(self):
        return [p for p in self.parts if p.size]                     # nvt_write_firmware: "if (!size) continue"

    def blob(self, p):
        return self.data[p.bin_addr:p.bin_addr + p.size + 1]        # size + 1 bytes (ko 0x11638 add w25, w10, #1)


# ---------------------------------------------------------------------------------------------------------------
# Transportes
# ---------------------------------------------------------------------------------------------------------------
def _ioc(direction, typ, nr, size):
    return (direction << 30) | (size << 16) | (ord(typ) << 8) | nr


SPI_IOC_WR_MODE = _ioc(1, 'k', 1, 1)
SPI_IOC_WR_BITS = _ioc(1, 'k', 3, 1)
SPI_IOC_WR_SPEED = _ioc(1, 'k', 4, 4)


def spi_message(n):
    return _ioc(1, 'k', 0, 32 * n)


class SpiDev:
    """Transporte real: un ioctl SPI_IOC_MESSAGE de una sola transferencia por operacion (CS bajo solo en ella)."""
    sim = False

    def __init__(self, path, speed):
        self.fd = os.open(path, os.O_RDWR)
        self.speed = speed
        fcntl.ioctl(self.fd, SPI_IOC_WR_MODE, struct.pack("B", 0))
        fcntl.ioctl(self.fd, SPI_IOC_WR_BITS, struct.pack("B", 8))
        fcntl.ioctl(self.fd, SPI_IOC_WR_SPEED, struct.pack("I", speed))
        self.n = 0

    def _msg(self, tx, rx_len):
        n = len(tx)
        txb = ctypes.create_string_buffer(bytes(tx), n)
        rxb = ctypes.create_string_buffer(rx_len) if rx_len else None
        # struct spi_ioc_transfer: tx_buf u64, rx_buf u64, len u32, speed_hz u32, delay_usecs u16, bits_per_word u8,
        # cs_change u8, tx_nbits u8, rx_nbits u8, word_delay_usecs u8, pad u8 (32 B)
        tr = struct.pack("QQIIHBBBBBB", ctypes.addressof(txb), ctypes.addressof(rxb) if rxb else 0, n, self.speed,
                         0, 8, 0, 0, 0, 0, 0)
        last = None
        for _ in range(5):                                           # el vendor reintenta 5 veces el spi_sync
            try:
                fcntl.ioctl(self.fd, spi_message(1), bytearray(tr))
                self.n += 1
                return rxb.raw if rxb else None
            except OSError as e:
                last = e
                time.sleep(0.001)
        raise last

    def write(self, tx):
        self._msg(tx, 0)

    def xfer(self, tx):
        return self._msg(tx, len(tx))


class DryRun:
    """Transporte simulado: imprime cada transferencia y mantiene una SRAM virtual de 8 MiB (espacio de 23 bits).
    Las lecturas devuelven la memoria virtual, salvo las direcciones 'simuladas' (marcadas [SIM]) que representan
    al chip real (chip_ver_trim, bit cascade, estado de arranque, FWINFO)."""
    sim = True

    def __init__(self, verbose=False):
        self.mem = bytearray(0x800000)
        self.page = 0
        self.n = 0
        self.nbytes = 0
        self.verbose = verbose
        self.label = ""
        self.over = {}
        self.written = []   # (addr, len)
        self._seed()

    def _seed(self):
        m = self.mem
        m[CHIP_VER_TRIM:CHIP_VER_TRIM + 8] = bytes([0x0E, 0x00, 0x04, 0x32, 0x65, 0x03, 0x10, 0x00])
        m[CASCADE_DETECT] = 0x00
        m[CASCADE['TX_AUTO_COPY_EN']] = 0x00
        # el chip real pone TX_AUTO_COPY_EN a 0 cuando termina la copia al 2o chip; el simulador lo da por terminado
        self.over[CASCADE['TX_AUTO_COPY_EN']] = b"\x00"
        # tras el arranque el FW real deja estos valores; el simulador los muestra siempre (dry-run no puede saber mas)
        self.over[CASCADE['EVENT_BUF'] + EVT_RESET_COMPLETE] = bytes([0xA0, 0, 0, 0, 0, 0])
        fi = bytearray(39)
        fi[0], fi[1] = EXPECT['fw_ver'], (~EXPECT['fw_ver']) & 0xFF
        fi[2], fi[3] = 40, 60
        fi[4:6] = struct.pack(">H", EXPECT['x_max'])
        fi[6:8] = struct.pack(">H", EXPECT['y_max'])
        fi[13] = EXPECT['fw_type']
        fi[34:36] = struct.pack("<H", EXPECT['pid'])
        self.over[CASCADE['EVENT_BUF'] + EVT_FWINFO] = bytes(fi)

    def _show(self, kind, tx, extra=""):
        self.n += 1
        self.nbytes += len(tx)
        if len(tx) <= 24 or self.verbose:
            body = tx.hex(" ")
        else:
            body = "%s ... [%d B, sha256 %s]" % (tx[:12].hex(" "), len(tx), hashlib.sha256(tx).hexdigest()[:12])
        print("  SPI#%04d %s %6dB  %s%s" % (self.n, kind, len(tx), body, extra))

    def _decode_write(self, tx):
        reg = tx[0] & 0x7F
        if tx[0] == 0xFF and len(tx) == 3:
            self.page = (tx[1] << 15) | (tx[2] << 7)
            return "   # set_page 0x%06x" % self.page
        addr = self.page | reg
        self.mem[addr:addr + len(tx) - 1] = tx[1:]
        self.written.append((addr, len(tx) - 1))
        if len(tx) - 1 <= 8:
            return "   # write 0x%06x <- %s" % (addr, tx[1:].hex(" "))
        return "   # write 0x%06x .. 0x%06x" % (addr, addr + len(tx) - 2)

    def write(self, tx):
        tx = bytes(tx)
        assert tx[0] & 0x80, "una escritura debe llevar el bit 0x80 en el comando"
        self._show("W ", tx, self._decode_write(tx))

    def xfer(self, tx):
        tx = bytes(tx)
        assert not tx[0] & 0x80, "una lectura no debe llevar el bit 0x80"
        addr = self.page | (tx[0] & 0x7F)
        n = len(tx) - 2
        data = None
        for a, v in self.over.items():
            if a <= addr < a + len(v):
                data = (v + bytes(n))[addr - a:addr - a + n]
                tag = " [SIM]"
                break
        if data is None:
            data = bytes(self.mem[addr:addr + n])
            tag = " [SIM]" if addr in (CHIP_VER_TRIM, CASCADE_DETECT, CASCADE['TX_AUTO_COPY_EN']) else ""
        self._show("R ", tx[:1], "   # read 0x%06x x%d -> %s%s" % (addr, n, data[:16].hex(" ") + (" ..." if n > 16 else ""), tag))
        return b"\x00\x00" + data


# ---------------------------------------------------------------------------------------------------------------
# Capa del chip
# ---------------------------------------------------------------------------------------------------------------
class Chip:
    def __init__(self, tr, args):
        self.t = tr
        self.a = args

    def sleep(self, secs):
        if not self.t.sim:
            time.sleep(secs)

    # --- primitivas del vendor
    def set_page(self, addr):                                       # nvt_set_page, ko 0x9a0 (CTP_SPI_WRITE de 3 bytes)
        self.t.write(bytes([0xFF, (addr >> 15) & 0xFF, (addr >> 7) & 0xFF]))

    def write_regs(self, addr, payload):                            # set_page + CTP_SPI_WRITE([addr&0x7F, payload...])
        self.set_page(addr)
        self.t.write(bytes([(addr & 0x7F) | 0x80]) + bytes(payload))

    def write_addr(self, addr, val):                                # nvt_write_addr, ko 0xa18
        self.write_regs(addr, [val])

    def read(self, addr, n, page=True):                             # set_page + CTP_SPI_READ(len = n+1)
        if page:
            self.set_page(addr)
        rx = self.t.xfer(bytes([addr & 0x7F]) + bytes(n + 1))
        return rx[2:2 + n]

    # --- pasos
    def bootloader_reset(self):                                     # nvt_bootloader_reset, ko 0x320c
        self.write_addr(SWRST_SIF, CMD_BOOTLOADER_RESET)
        self.sleep(self.a.reset_wait_ms / 1000.0)
        # SPI_RD_FAST_ADDR == 0 en este DT ("not support novatek,spi-rd-fast-addr"): nada mas

    def set_bld_crc_bank(self, des, sram, length_reg, size, g_reg, crc):   # nvt_set_bld_crc_bank, ko 0x11c18
        self.set_page(des)                                          # una sola set_page: las 3 regs caen en la misma ventana de 128 B
        self.t.write(bytes([(des & 0x7F) | 0x80]) + struct.pack("<I", sram)[:3])
        self.t.write(bytes([(length_reg & 0x7F) | 0x80]) + struct.pack("<I", size)[:3])   # hw_crc==2 -> len 4 (cmd+3)
        self.t.write(bytes([(g_reg & 0x7F) | 0x80]) + struct.pack("<I", crc))

    def tx_auto_copy_mode(self):                                    # nvt_tx_auto_copy_mode, ko 0x2b48 (auto_copy == 2)
        self.write_addr(CASCADE['TX_AUTO_COPY_EN'], AUTO_COPY_MODE2_VALUE)

    def write_sram(self, sram, blob, chunk):                        # nvt_write_firmware, ko 0x11598 (bloque 0xFC00 -> aqui <= chunk)
        off = 0
        while off < len(blob):
            part = blob[off:off + chunk]
            self.write_regs(sram + off, part)
            off += len(part)

    def wait_auto_copy(self):                                       # nvt_check_tx_auto_copy, ko 0x2e58: 200 x 1 ms hasta 0
        for i in range(200):
            v = self.read(CASCADE['TX_AUTO_COPY_EN'], 1)[0]
            if v == 0:
                return True
            self.sleep(0.001)
        print("  auto copy no termino: TX_AUTO_COPY_EN=0x%02x tras 200 intentos" % v)
        return False

    def fw_crc_enable(self):                                        # nvt_fw_crc_enable, ko 0x2a04
        eb = CASCADE['EVENT_BUF']
        self.set_page(eb)
        self.t.write(bytes([EVT_RESET_COMPLETE | 0x80]) + bytes(6))            # CTP_SPI_WRITE de 7 B: 0x60 <- 0 (x6)
        self.t.write(bytes([EVT_HOST_CMD | 0x80, CMD_FW_CRC_ENABLE, 0x00]))     # CTP_SPI_WRITE de 3 B: 0x50 <- 0xAE, 0x00

    def boot_ready(self):                                           # nvt_boot_ready, ko 0x2ad0 (hw_crc != 0: solo el 1)
        self.write_addr(CASCADE['BOOT_RDY'], 0x01)
        self.sleep(self.a.boot_wait_ms / 1000.0)

    def check_fw_reset_state(self, state=RESET_STATE_INIT):        # nvt_check_fw_reset_state, ko 0x3618
        eb = CASCADE['EVENT_BUF']
        retry = FW_RST_RETRY if state == RESET_STATE_INIT else 50
        self.set_page(eb)
        last = b""
        for i in range(retry + 1):
            last = self.read(eb + EVT_RESET_COMPLETE, 5, page=False)
            if last[0] <= RESET_STATE_MAX and last[0] >= state:
                return True, last
            if i < retry:
                self.sleep(0.010)
        return False, last

    def get_fw_info(self, eb=None):                                 # nvt_get_fw_info, ko 0x37f4 (4 intentos)
        eb = CASCADE['EVENT_BUF'] if eb is None else eb
        for i in range(4):
            fi = self.read(eb + EVT_FWINFO, 38)
            if (fi[0] + fi[1]) & 0xFF == 0xFF:
                return self.decode_fwinfo(fi)
            self.sleep(0.010)
        return None

    @staticmethod
    def decode_fwinfo(fi):
        return dict(fw_ver=fi[0], x_num=fi[2], y_num=fi[3], x_max=(fi[4] << 8) | fi[5], y_max=(fi[6] << 8) | fi[7],
                    max_button=fi[10], fw_type=fi[13], pid=fi[34] | (fi[35] << 8), raw=bytes(fi))

    def read_bld_hw_crc(self):                                      # nvt_read_bld_hw_crc, ko 0x118fc: SOLO diagnostico (lecturas)
        st = self.read(CASCADE['BLD_CRC_STATUS'], 1)[0]
        print("  BLD CRC: crc_done=%d ilm_crc_flag=%d dlm_crc_flag=%d (0x%02x)" % ((st >> 2) & 1, st & 1, (st >> 1) & 1, st))
        out = {}
        for k in ("G_ILM_CHECKSUM", "R_ILM_CHECKSUM", "G_DLM_CHECKSUM", "R_DLM_CHECKSUM"):
            out[k] = struct.unpack("<I", self.read(CASCADE[k], 4))[0]
        print("  ILM golden(chip)=0x%08x resultado=0x%08x | DLM golden(chip)=0x%08x resultado=0x%08x" % (
            out["G_ILM_CHECKSUM"], out["R_ILM_CHECKSUM"], out["G_DLM_CHECKSUM"], out["R_DLM_CHECKSUM"]))
        return out


def show_fwinfo(fi, tag=""):
    ok = fi is not None
    if not ok:
        print("  FWINFO%s: invalido (fw_ver + ~fw_ver != 0xFF)" % tag)
        return
    exp = " (esperado Android: 0x%02X, PID 0x%04X, %dx%d)" % (EXPECT['fw_ver'], EXPECT['pid'], EXPECT['x_max'], EXPECT['y_max'])
    print("  FWINFO%s: fw_ver=0x%02x fw_type=0x%02x PID=0x%04x x_num=%d y_num=%d abs_x_max=%d abs_y_max=%d max_button=%d%s"
          % (tag, fi['fw_ver'], fi['fw_type'], fi['pid'], fi['x_num'], fi['y_num'], fi['x_max'], fi['y_max'], fi['max_button'], exp))


def step(msg):
    print("\n== %s" % msg)


# ---------------------------------------------------------------------------------------------------------------
def identify(ch):
    """Solo lecturas: chip_ver_trim + bit cascade. Devuelve (ok_id, cascade_bool)."""
    step("identificacion (solo lectura)")
    v = ch.read(CHIP_VER_TRIM, 6)
    print("  chip_ver_trim @0x%06x = %s   (Android: 0e 00 04 32 65 03)" % (CHIP_VER_TRIM, v.hex(" ")))
    ok_id = bytes(v[3:6]) == CHIP_ID_TAIL
    c = ch.read(CASCADE_DETECT, 1)[0]
    cascade = (c & 0x01) == 0
    print("  bit0 de 0x%06x = %d -> %s" % (CASCADE_DETECT, c & 1, "Cascade Chip" if cascade else "Single Chip"))
    return ok_id, cascade


def verify_only(ch):
    ok_id, cascade = identify(ch)
    step("estado del firmware (solo lectura): mapa CASCADE (EVENT_BUF=0x%06x) y mapa SINGLE (0x%06x, el del probe antiguo)"
         % (CASCADE['EVENT_BUF'], SINGLE_EVENT_BUF))
    res = {}
    for name, eb in (("cascade", CASCADE['EVENT_BUF']), ("single", SINGLE_EVENT_BUF)):
        st = ch.read(eb + EVT_RESET_COMPLETE, 5)
        alive_state = RESET_STATE_INIT <= st[0] <= RESET_STATE_MAX
        print("  [%s] EVENT_BUF+0x60 (reset state) = %s -> %s" % (name, st.hex(" "), "FW arrancado (>=0xA0)" if alive_state else "sin estado de FW"))
        fi = ch.read(eb + EVT_FWINFO, 38)
        valid = (fi[0] + fi[1]) & 0xFF == 0xFF and fi[0] not in (0x00, 0xFF)
        print("  [%s] FWINFO @0x%06x = %s" % (name, eb + EVT_FWINFO, fi[:16].hex(" ") + " ..."))
        show_fwinfo(ch.decode_fwinfo(fi) if valid else None, " [%s]" % name)
        res[name] = valid
    step("registros del bootloader/CRC (solo lectura)")
    print("  TX_AUTO_COPY_EN 0x%06x = 0x%02x ; BOOT_RDY 0x%06x = 0x%02x ; CRC_ERR_FLAG 0x%06x = 0x%02x" % (
        CASCADE['TX_AUTO_COPY_EN'], ch.read(CASCADE['TX_AUTO_COPY_EN'], 1)[0], CASCADE['BOOT_RDY'],
        ch.read(CASCADE['BOOT_RDY'], 1)[0], CRC_ERR_FLAG, ch.read(CRC_ERR_FLAG, 1)[0]))
    ch.read_bld_hw_crc()
    print("\nResumen: id %s, %s, FW vivo en mapa cascade: %s, en mapa single: %s"
          % ("OK" if ok_id else "NO COINCIDE", "cascade" if cascade else "single", res['cascade'], res['single']))
    return 0 if ok_id else 2


def download(ch, fw, args):
    eb = CASCADE['EVENT_BUF']
    parts = fw.partitions_to_write()
    ilm, dlm = fw.parts[0], fw.parts[1]
    tries = 3                                                       # ko: 3 intentos (cmp w23,#2)
    for attempt in range(tries):
        step("descarga, intento %d/%d" % (attempt + 1, tries))
        step("1. bootloader reset (0x%02x -> 0x%06x)" % (CMD_BOOTLOADER_RESET, SWRST_SIF))
        ch.bootloader_reset()
        step("2. set_bld_crc_bank ILM / DLM")
        ch.set_bld_crc_bank(CASCADE['ILM_DES'], ilm.sram_addr, CASCADE['ILM_LENGTH'], ilm.size, CASCADE['G_ILM_CHECKSUM'], ilm.crc)
        ch.set_bld_crc_bank(CASCADE['DLM_DES'], dlm.sram_addr, CASCADE['DLM_LENGTH'], dlm.size, CASCADE['G_DLM_CHECKSUM'], dlm.crc)
        if fw.cascade:
            step("3. tx auto copy (0x%02x -> 0x%06x)" % (AUTO_COPY_MODE2_VALUE, CASCADE['TX_AUTO_COPY_EN']))
            ch.tx_auto_copy_mode()
        step("4. escritura a SRAM (%d particiones, bloques de %d B)" % (len(parts), args.chunk))
        for p in parts:
            blob = fw.blob(p)
            print("  %s -> SRAM 0x%06x (%d B)" % (p.name, p.sram_addr, len(blob)))
            ch.write_sram(p.sram_addr, blob, args.chunk)
        if fw.cascade:
            step("5. espera auto copy")
            if not ch.wait_auto_copy():
                print("  FALLO: auto copy; reintento")
                continue
        step("6. fw_crc_enable")
        ch.fw_crc_enable()
        step("7. boot_ready")
        ch.boot_ready()
        step("8. check_fw_reset_state(0x%02x)" % RESET_STATE_INIT)
        ok, last = ch.check_fw_reset_state()
        print("  estado de reset = %s -> %s" % (last.hex(" "), "OK" if ok else "FALLO"))
        if ok:
            return True
        print("  diagnostico CRC del bootloader:")
        ch.read_bld_hw_crc()
    return False


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--fw", help="ruta del novatek_nt36532_o82_fw_csot.bin (NO se copia al repo)")
    ap.add_argument("--dev", default=DEV)
    ap.add_argument("--speed", type=int, default=SPEED_DEFAULT)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--parse-only", action="store_true", help="solo analizar el .bin (sin SPI)")
    g.add_argument("--verify-only", action="store_true", help="solo lecturas (no resetea el chip); combinable con --dry-run")
    g.add_argument("--execute", action="store_true", help="ESCRIBE de verdad (orden del dueno)")
    ap.add_argument("--dry-run", action="store_true",
                    help="imprimir las transferencias SPI sin ejecutarlas (solo, simula la descarga completa; con --verify-only simula las lecturas)")
    ap.add_argument("--chunk", type=int, default=16256, help="bytes de payload por transferencia SPI (<= bufsiz-1 = 16383; vendor 64512)")
    ap.add_argument("--reset-wait-ms", type=int, default=DEFAULT_RESET_WAIT_MS)
    ap.add_argument("--boot-wait-ms", type=int, default=DEFAULT_BOOT_WAIT_MS)
    ap.add_argument("--force", action="store_true", help="recargar aunque el FW ya este vivo")
    ap.add_argument("--verbose", action="store_true", help="dry-run: volcar los payloads completos")
    a = ap.parse_args()
    if not (a.parse_only or a.dry_run or a.verify_only or a.execute):
        ap.error("elige un modo: --parse-only | --dry-run | --verify-only | --execute (sin --execute no se escribe nada)")
    if a.dry_run and a.execute:
        ap.error("--dry-run y --execute son incompatibles")
    if a.chunk < 4 or a.chunk > 16383:
        ap.error("--chunk debe estar entre 4 y 16383 (spidev bufsiz por defecto 16384, incluye el byte de comando)")
    a.chunk -= a.chunk % 4

    fw = None
    if a.fw or not a.verify_only:
        if not a.fw:
            ap.error("falta --fw")
        data = open(a.fw, "rb").read()
        print("bin: %s  %d B  sha256 %s" % (a.fw, len(data), hashlib.sha256(data).hexdigest()))
        fw = FwBin(data)
        print("  fw_need_write_size = 0x%x (%d), flag final \"%s\"; FW_VER=0x%02x FW_VER_BAR=0x%02x" % (
            fw.need, fw.need, fw.endflag, fw.fw_ver, fw.fw_ver_bar))
        print("  cabecera: end=0x%x cascade_2nd_header_info=%d ovly_info=%d ilm_dlm_num=%d ovly_sec_num=%d info_sec_num=%d partition=%d"
              % (fw.end, fw.cascade, fw.ovly_info, fw.ilm_dlm_num, fw.ovly_sec_num, fw.info_sec_num, fw.partition))
        for i, p in enumerate(fw.parts):
            print("  [%2d] %r%s" % (i, p, "" if p.size else "   (vacia, no se escribe)"))
        bad = 0
        for p, c, ok in fw.check_crc():
            print("  crc %-7s dorado 0x%08x recalculado 0x%08x %s" % (p.name, p.crc, c, "OK" if ok else "NO COINCIDE"))
            bad += (not ok)
        for pr in fw.problems:
            print("  AVISO:", pr)
        if bad:
            print("el bin NO pasa la comprobacion de CRC: no se continua")
            return 2
        if fw.cascade != 1:
            print("el bin no es cascade (cascade_2nd_header_info=0): camino no verificado, no se continua")
            return 2
        if a.parse_only:
            return 0

    if a.dry_run:
        tr = DryRun(a.verbose)
    else:
        if not os.path.exists(a.dev):
            sys.exit("no existe %s (falta spidev ligado a spi0.0)" % a.dev)
        try:                                                         # limite real de spidev (module param bufsiz, incluye el byte de comando)
            bufsiz = int(open("/sys/module/spidev/parameters/bufsiz").read())
        except (OSError, ValueError):
            bufsiz = 4096                                            # valor por defecto del modulo si no se puede leer
        if a.chunk + 1 > bufsiz:
            a.chunk = (bufsiz - 1) // 4 * 4
            print("aviso: spidev bufsiz=%d -> --chunk reducido a %d" % (bufsiz, a.chunk))
        tr = SpiDev(a.dev, a.speed)
    ch = Chip(tr, a)

    if a.verify_only:
        return verify_only(ch)

    ok_id, cascade = identify(ch)
    if not ok_id or not cascade:
        print("el chip no se identifica como NT36532 Cascade: ABORTO (no se ha escrito nada)")
        return 2
    step("estado previo (solo lectura)")
    st = ch.read(CASCADE['EVENT_BUF'] + EVT_RESET_COMPLETE, 5)
    fi0 = ch.get_fw_info() if RESET_STATE_INIT <= st[0] <= RESET_STATE_MAX else None
    print("  reset state = %s" % st.hex(" "))
    show_fwinfo(fi0, " previo")
    if fi0 and not a.force and not a.dry_run:
        print("el firmware ya esta vivo (fw_ver=0x%02x): no se recarga (usa --force). Nada que hacer." % fi0['fw_ver'])
        return 0

    t0 = time.time()
    ok = download(ch, fw, a)
    dt = time.time() - t0
    if not ok:
        print("\nDESCARGA FALLIDA tras 3 intentos (%.2f s). El chip puede quedar en bootloader; reintentar o recuperar con el display (suspend/resume)." % dt)
        return 3
    step("9. get_fw_info")
    fi = ch.get_fw_info()
    show_fwinfo(fi)
    print("\nDescarga %s en %.2f s, %d transferencias SPI" % ("simulada" if a.dry_run else "completada", dt, tr.n))
    if a.dry_run:
        step("comprobacion de la SRAM virtual contra el bin")
        okall = True
        total = 0
        for p in fw.partitions_to_write():
            blob = fw.blob(p)
            same = bytes(tr.mem[p.sram_addr:p.sram_addr + len(blob)]) == blob
            okall &= same
            total += len(blob)
            print("  %-8s SRAM 0x%06x..0x%06x (%d B): %s" % (p.name, p.sram_addr, p.sram_addr + len(blob) - 1, len(blob), "IDENTICA al bin" if same else "DIFIERE"))
        for nm, reg, exp in (("ILM_DES", CASCADE['ILM_DES'], fw.parts[0].sram_addr), ("ILM_LENGTH", CASCADE['ILM_LENGTH'], fw.parts[0].size),
                             ("DLM_DES", CASCADE['DLM_DES'], fw.parts[1].sram_addr), ("DLM_LENGTH", CASCADE['DLM_LENGTH'], fw.parts[1].size)):
            v = int.from_bytes(tr.mem[reg:reg + 3], "little")
            okall &= (v == exp)
            print("  %-10s 0x%06x = 0x%06x (esperado 0x%06x) %s" % (nm, reg, v, exp, "OK" if v == exp else "MAL"))
        for nm, reg, exp in (("G_ILM_CHECKSUM", CASCADE['G_ILM_CHECKSUM'], fw.parts[0].crc), ("G_DLM_CHECKSUM", CASCADE['G_DLM_CHECKSUM'], fw.parts[1].crc)):
            v = int.from_bytes(tr.mem[reg:reg + 4], "little")
            okall &= (v == exp)
            print("  %-14s 0x%06x = 0x%08x (esperado 0x%08x) %s" % (nm, reg, v, exp, "OK" if v == exp else "MAL"))
        print("  total %d B a SRAM; %d transferencias; mayor payload %d B" % (total, tr.n, max(l for _, l in tr.written)))
        print("  max bytes por transferencia SPI: %d (limite spidev 16384)" % (max(l for _, l in tr.written) + 1))
        print("RESULTADO DRY-RUN: %s" % ("OK" if okall else "FALLO"))
        return 0 if okall else 4
    if not fi or fi['fw_ver'] != EXPECT['fw_ver']:
        print("FWINFO no coincide con lo esperado (fw_ver 0x%02x)" % EXPECT['fw_ver'])
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
