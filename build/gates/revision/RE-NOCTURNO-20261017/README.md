# RE-NOCTURNO-20261017 — índice

Sesión nocturna del 17-oct-2026 (dueño durmiendo): RE de **todo lo atacable fuera del panel**
(el panel/L75 es de la otra sesión). Método: 12 subagentes en 4 oleadas + verificación
independiente (W2) + reparación/re-dry-run (W3) + spot-check propio con REA.

> **Consolidado de toda la noche (con referencias):** [`docs/guias/RE-NOCTURNO-HALLAZGOS-20261017.md`](../../../../RE-NOCTURNO-HALLAZGOS-20261017.md) — en la raíz del repo.
Reglas respetadas: solo lectura (repo + `adb` root de la tablet en Android), cero builds,
cero flash, cero escrituras en la tablet, nada de ficheros existentes editado salvo las
erratas de estos mismos informes y el fix GAP-1 de `charge/uke-charge-run.sh`.

## Informes (orden de lectura sugerido)

| Fichero | Tema |
|---|---|
| `RE-TOUCH-NT36532.md` | vendor vs driver mainline (IRQ `0x2001` RISING+ONESHOT triple-verificado, SPI CS0 19,2M MODE_0, chip/fw ids, **superres ×10**) |
| `RE-STYLUS-FW-CSOT.md` | lápiz M80p/P81c (ejes, twist P81c, gestos) + parseo de fw CSOT (NVT, CRC) |
| `RE-TOUCH-MT-LAYOUT.md` | quién decodifica el dedo (nadie en kernel; HAL) + framing THP |
| `RE-TOUCH-THP-BODY.md` | cuerpo THP **5748 B**, `thp-decode.py`, corrección del tamaño |
| `RE-BT-WCN6750.md` | `btpower.ko` (9 supplies, GPIO 156), fw ELF32 `msbtfw12`, plan `hci_qca` |
| `RE-AUDIO-WCD939X-FS19XX.md` (+`ADD1`, `ADD2`) | fs19xx/wcd939x/machine; blob `.fsm`; spec de driver |
| `AUDIT-ADD2-20261017.md` | auditoría del ADD2 (recomputada) + `fs19xx-presets.h` |
| `RE-WIFI-BDF.md` | BDF o82gl (offset 1024+58180) / regdb + **payload v2** |
| `RE-FOLIO-SENSORES.md` | Nanosic 803 (i2c@a8c000/0x4c), hall por `smp2p-adsp`, sensores solo SSC |
| `ATAQUE-OMARCHY-OFFLINE.md` | migraciones (killer único = snapper `1781984677`), wrappers, gates |
| `FIXES-W3-20261017.md` | reparación de parches + **orden de aplicación** + dry-run 15/15 |
| `VERIFICACION-W2-20261017.md` | verificación mecánica de los 7 informes de la 1.ª oleada |

## Artefactos clave

- `artifacts/parches/` — set para el día del flash: `10` base (0001), `11` DT superres,
  `12` MT parser THP, `13` pen v2, `20` BT dtsi v2; `00-ESTADO.md` con orden, comando y riesgos.
- `build/pkg/uke-wifi-payload-v2.tar.gz` (sha `2b0dd75a…`) + `.sha256` — board/regdb correctos, sin `amss.bin`.
- `artifacts/audio/fs19xx-presets.h` (tablas C del blob; `gcc -fsyntax-only` OK) + `fsm-blob-parser.py`/`fsm-blob-emit-c.py`.
- `artifacts/touch/mt-layout/{thp-decode.py,frame-scan.py}`, `artifacts/bt/parse_msbtfw.py`.
- Decompilados Ghidra de los `.ko` vendor (derivados; **fuera de git**): `artifacts/**/decomp*`.
- Blobs grandes deliberadamente fuera de git (p.ej. `artifacts/wifi/amss-kiwi-tabletProbe.bin`, 7,2 MB);
  sus shas viven en los informes.

## Reproducir (2 minutos)

```bash
# 1) módulos vendor desde la tablet (solo lectura)
mkdir -p build/android/vendor-modules-20261017
for m in nt36532_touch xiaomi_touch btpower fs19xx_dlkm machine_dlkm wcd939x_dlkm \
         wcd939x_slave_dlkm wcd9xxx_dlkm wcd_core_dlkm xiaomi_keyboard_driver \
         xiaomi_hall wlan_firmware_service xiaomi_wifi_gpio; do
  adb -s 192.0.2.13:5555 exec-out "su -c 'cat /vendor/lib/modules/$m.ko'" \
    > build/android/vendor-modules-20261017/$m.ko
done
# 2) decompilar (Ghidra serializado; JAVA_HOME=java-27-openjdk)
flock /tmp/opencode/ghidra.lock ~/tools/ghidra_12.1.4_PUBLIC/support/analyzeHeadless \
  ~/ghidra-projects uke-night -import build/android/vendor-modules-20261017/nt36532_touch.ko \
  -processor AARCH64:LE:64:v8A -overwrite -scriptPath build/tools/ghidra \
  -postScript ExportAllDecompiled.java /tmp/opencode/decomp
```

`build/android/vendor-modules-20261017/00-listing.txt` guarda el censo de los 320 módulos vendor.
Spot-check externo de la noche (REA): `nvt_ts_work_func` (0x15e06c) — 25 callees, **cero** `input_event`.
