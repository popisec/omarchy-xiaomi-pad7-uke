# PRE-REGISTRO F2/L31 — 13-oct · **el experimento que hace la muerte MEDIBLE**

## La idea

La muerte ocurre a **3,96 s**. UKE-DIAG escribe a partir de **5,97 s**. Nunca la verá.
**L31 mueve la muerte de los 4 s a los ~120 s**, dentro del alcance del vigilante.

Dos cambios de cmdline, **ninguno de kernel** (0 builds):

| | Antes | L31 | Por qué |
|---|---|---|---|
| fbcon | `console=tty0 fbcon=map:0` | **fuera** | sin fbcon no hay auto-modeset en el boot |
| conector | `video=DSI-1:d` (off) | **`video=DSI-1:e`** (habilitado) | el conector está disponible, pero nadie lo usa hasta que lo hagamos nosotros |

El kernel arranca, el DPU bindea, **nadie hace commit de modeset ⇒ vive**. SSH a los ~70 s.

## Artefacto

- **sha256**: `4faf162fc1b596bea2cf7a3fac0caabb2ea68afbeaaee0197b0937e4bb23a266`
- **Tamaño**: 100663296 B
- **Kernel**: el de L25-diag (`k52L25-diag-Image.gz`, sha `422b85db…`) — **contiene UKE-DIAG**
  (verificado en el binario: `UKE-DIAG` ×10, cpio `070701` válido)
- **Cmdline**: 581 B = L19 (580) − `console=tty0` (13) − `fbcon=map:0` (12) − ` video=DSI-1:d` (14)
  + ` video=DSI-1:e` (14) + ` msm.uke_skip_mdss_reset=1` (26)
- Gates G0–G8 verdes. `console=ttyGS0,115200` **conservado** (ACM intacto).

## Verificación hecha

```
video=DSI-1:e  ✓ presente      video=DSI-1:d ✗ ausente
console=tty0   ✗ ausente      fbcon          ✗ ausente
console=ttyGS0 ✓ presente      skip reset     ✓ presente
```

## Qué se desbloquea

Con `:d` **nunca** se ejecutó el camino del commit de modeset: `dsi_phy_enable`, PLL,
`set_link_frequencies`, `panel pre_enable → o82_prepare`. Es terreno virgen, y es donde está la muerte.

## Procedimiento tras el boot

1. SSH a `192.168.42.129` (`-i build/rootfs/uke-arch-root`). **NO arrancar sddm todavía**: si sddm
   hace un modeset, la muerte vuelve a ser a los ~4 s y no la vemos.
2. Confirmar que el sistema está vivo y el conector habilitado (`status`, `enabled`).
3. Disparar el modeset desde userspace. Candidatos, en orden de menor a mayor riesgo:
   - `echo detect > /sys/class/drm/card1-DSI-1/status`
   - `modetest -d msm -s <conn>@<crtc>:<w>x<h>` (ojo: `modetest` no enumeró en el test D-1)
   - `echo on > /sys/class/drm/card1-DSI-1/status`
4. Si el SoC muere: **reboot**. Al volver, UKE-DIAG habrá escrito en `/root/diag/`:
   `dmesg.N.txt` (400 líneas previas), `estado.txt`, `ultimo.txt` (hasta qué ciclo llegó).
5. **Ese `dmesg.N.txt` es la primera lectura real de dónde muere el commit.**

## Tabla de lectura pre-registrada

| Resultado | Lectura |
|---|---|
| **El commit sobrevive** | El DSI+PHY+PLL+panel funcionan ⇒ el panel se puede encender. Siguiente: quitar `:e` del boot y dejar que fbcon haga el commit |
| **Muerte, UKE-DIAG captura dmesg** | **Por fin sabemos la línea exacta.** Empieza el bisect del commit (1 flag por ciclo) |
| **Muerte sin captura** | Murió antes de 5,97 s ⇒ el trigger no fue el esperado; revisar si algo hizo commit antes |

## Riesgos

- Si sddm arranca solo y hace modeset, la muerte es a los ~4 s. **Dejar sddm parado.**
- Un cuelgue duro del bus ⇒ power cycle manual (imposible reboot por software: `/sbin/reboot` →
  `systemctl` y no hay logind).

## Recuperación

```
fastboot flash boot_a build/bootimg/boot-uke-k52L25-diag.img   # sha e2c2ccc54520…
fastboot flash dtbo_a build/bootimg/s275-boot-dtbo-gpu-display.img  # sha 67a65bc161b6…
fastboot set_active a ; fastboot reboot
```