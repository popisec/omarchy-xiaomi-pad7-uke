# PRE-REGISTRO L25-diag — 12-oct · **el que rompe la racha de ciclos no medidos**

## Qué es

Un build de **L25 (el boot bueno) + un vigilante de diagnóstico** en el initramfs. No cambia la
lógica del kernel ni la cmdline: **solo añade un proceso en background que escribe `dmesg` y estado
crítico en `/root/diag/` del rootfs persistente**, cada ~1 s, de forma rotativa y atómica.

Como el kernel muere **sin shutdown limpio**, no hay "momento de la muerte": lo que vale es el
**último snapshot escrito con éxito**. Y como el rootfs es ext4 persistente, **sobrevive al reset**.

## Artefactos

| Qué | sha256 |
|---|---|
| `build/bootimg/boot-uke-k52L25-diag.img` | **`e2c2ccc5452018221b177c24408d31c0257bb171e5613ca8a39bc9f38df008aa`** (100663296 B) |
| `build/init/uke-k52b2-diag-initramfs.cpio.gz` | `8f887ea2…f5abfd4` (1107682 B, **+3661 B** vs k52b2) |
| `build/init/diag-snapshot.sh` | el vigilante (POSIX sh) |
| `build/gates/mkcpio-k52b2-diag.py` / `repack-k52L25diag.py` | constructores, gates G0–G8 verdes |

**`dtbo_a` = s275-r2 sin tocar.** Cmdline **606 B, byte-idéntica a L25**.

## ⚠️ Hallazgo importante que cambió el plan

El boot vivo **no usa `ukeinit-arch`**: L25 lleva `rdinit=/ukeinit` (init de Ubuntu) y su initramfs va
**embebido en el `Image.gz`** (offset 35467896), no como `boot` con ramdisk. El cpio del boot bueno es
`uke-k34-fw-k52b2-initramfs.cpio.gz` (`ebc2de46…`), y el flujo a reusar es el del precedente **#602
(L19fsck)**. `ukeinit-arch` **no se ha tocado**.

## Qué escribe en `/root/diag/`

| Fichero | Contenido |
|---|---|
| `dmesg.0..4.txt` | **últimas 400 líneas** de `dmesg`, rotativo (N mod 5), escritura atómica (`tmp` + `mv`) |
| `estado.txt` | `uptime`, `/proc/cmdline` (incluye **`bootinfo.pureason`**), IRQ de display/mdss/dsi/esd, `card1-DSI-1` + `status`, `uname`, `df` |
| `ultimo.txt` | **marcador de vida**: versión, nº de ciclo, uptime, líneas del snapshot |

Y una línea `UKE-DIAG-SNAP <n>` al kmsg cada 10 ciclos (para verla en el ACM si llega).

## Gates ejecutados (todo en PC)

- `mkcpio-k52b2-diag.py`: **G0** pin + `bash -n`/`ash -n` con busybox real bajo qemu · **G1** ancla
  única del hook · **G2** smoke funcional bajo qemu (12 ciclos → 5×400 líneas exactas, estado con
  `pureason`/IRQ/drm, latido; caso ro → rc 0 sin escribir; dmesg vacío → rc 0) · **G3** roundtrip ·
  **G4** tamaño. **OK**
- `repack-k52L25diag.py`: **G0–G8 verdes** (cmdline L25 606 B byte-idéntica, AVB intacto, cpio
  embebido == fichero, `unpack_bootimg` OK).
- **Independent diff**: DIAG vs L25 difieren **0 bytes** fuera de zona kernel/size/cmdline;
  **0 strings ≥12 chars distintos** salvo el contador `#1→#2` ⇒ código idéntico.

## Cómo leer el próximo boot loop

1. Arrancar el par bueno, montar `/dev/sda32`.
2. `/root/diag/ultimo.txt` → ¿hasta qué ciclo/llegó el vigilante?
3. `dmesg.N.txt` (el más reciente) → **las últimas 400 líneas antes de la muerte**.
4. `estado.txt` → IRQ de display, `card1-DSI-1`, `pureason` del boot anterior.

**Interpretación de la ausencia**:
- `ultimo.txt` existe pero el `dmesg` acaba en el bind ⇒ **murió en el bind** (el caso de L26/L28/s280).
- `ultimo.txt` existe y el `dmesg` va más allá ⇒ **pasó el bind**; el killer es posterior (sospechoso L29).
- No existe `ultimo.txt` pero hay `UKE-DIAG: vigilante lanzado` en el ACM ⇒ murió **antes** del remount rw.
- No hay ni eso ⇒ murió en la ventana initramfs pura, antes del S123.

## Riesgos asumidos

- El kernel-diag **no es byte-idéntico** a L25 (+3,7 KiB initramfs, contador de build, build-id); el
  código sí. Riesgo residual de relink, mitigado por los gates de marcadores.
- Si el hook o el `setsid` fallaran, el boot sería **exactamente L25 sin diag**; el self-test
  `UKE-DIAG-TEST: FALLO` lo delata en el ACM.
- Límite de 1800 ciclos (~30 min): en un boot sano deja de escribir solo.

## Recuperación

```
fastboot flash boot_a build/bootimg/boot-uke-k52L25.img   # sha 04cd49803b9a…
fastboot flash dtbo_a build/bootimg/s275-boot-dtbo-gpu-display.img  # sha 67a65bc161b6…
fastboot set_active a ; fastboot reboot
```