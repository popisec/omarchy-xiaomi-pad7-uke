# PRE-REGISTRO F5/L35 — 13-oct · **L34 + `systemd.mask=sddm`** (para que L34 se pueda probar)

## Por qué este build

L34 **nunca llegó a probarse**: al reiniciar, `sddm` (que yo había `unmask`eado antes de
L33) arranca solo en cada boot, su greeter hace el commit de modeset, y el SoC muere a
los ~10 s **antes de que yo pueda hacer nada**. Los "3 resets" que dllamé arranque
envenenado eran mi propio cambio.

L35 = el **mismo kernel de L34** (con `TIMING_FLUSH←1`) + **un token de cmdline**:
`systemd.mask=sddm`. Así el greeter NO arranca solo, el sistema llega a SSH, y disparo
el commit a mi ritmo con el vigilante puesto. La variable del test sigue siendo **el
registro**, no la cmdline.

- **sha256**: `9f260d3d36fe1b0dfef896b2731788b06665cb88263eae1a09f05687c368f26e`
- Kernel: idéntico a L34 (`8a0ca07c…`), gate L34 del flush sigue verde
- Cmdline: 585 B = L34 (567) + ` systemd.mask=sddm` (18). `video=` sigue ausente.
