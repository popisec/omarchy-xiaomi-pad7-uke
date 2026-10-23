# PRE-REGISTRO F3/L33 — 13-oct · **el primer experimento que puede funcionar**

## Por qué L33 y no un cuarto intento de cmdline

L28, L30, L31 y L32 mueren **todas a ~4,0 s**, en el mismo punto, sin importar la cmdline.
Eso no era un problema de argumentos: era que **algo hace el commit de modeset sin que nadie lo pida**.

El mecanismo, leído en el código (no supuesto):

```
drivers/gpu/drm/drm_fb_helper.c
  drm_fb_helper_single_fb_probe()
      ...
      drm_client_modeset_commit(client);      ← EL COMMIT QUE MATA
```

Y su configuración:

```
drivers/gpu/drm/msm/Kconfig:72
config DRM_MSM_KMS_FBDEV
        def_bool DRM_FBDEV_EMULATION
```

`CONFIG_DRM_FBDEV_EMULATION=y` → compila `msm_fbdev.o` → la emulación genérica hace el
commit en el probe → muerte a los 4 s.

**L32 lo comprobó en negativo**: `msm.fbdev=0` (el `module_param` de `msm_fbdev.c`)
**no** desactiva ese commit, porque el commit está en la emulación *genérica*, no en
`msm_fbdev.c`. L32 murió a 4,092 s. Por eso L33 cambia el Kconfig, no la cmdline.

## Las tres variables de L33

| | valor | por qué |
|---|---|---|
| **kernel** | `CONFIG_DRM_FBDEV_EMULATION=n` (y `DRM_MSM_KMS_FBDEV` off por `def_bool`) | nadie hace commit en el boot |
| **cmdline** | **sin `video=` en absoluto** | sin `DRM_MODE_FORCE_*` ⇒ userspace *puede* modesetear después |
| **initramfs** | cpio `uke-k52b2-diag` | el vigilante UKE-DIAG, que escribe a partir de ~5,97 s |

Comparado con L25 (`video=DSI-1:d`), L33 quita el *force*. En L25 el conector estaba
forzado a OFF, así que `drmModeSetCrtc` desde SSH devolvía `-EINVAL` y **el camino del
commit nunca se había ejecutado**. L33 es el primer build donde ese camino es alcanzable.

## Artefacto

- **sha256**: `bc8b1ca6c405089aec4c18fda81d4799c8bfd67a71ef1545dd7184e7c329095f`
- **Kernel**: `build/kernel-pokes/k52L33-build/arch/arm64/boot/Image.gz`
- **Árbol**: `build/kernel-pokes/k52L33-tree` (clon de `k52L25-tree`, sin cambios de fuente)
- **Config base**: `build/kernel-pokes/k52L33-build/.config` ← clon de L25
- **Cmdline**: 567 B = L19 (580) − `console=tty0` (13) − `fbcon=map:0` (12) − ` video=DSI-1:d` (14)
  + ` msm.uke_skip_mdss_reset=1` (26)

## Gates

- **G3-L33 (nuevo)**: `msm.fbdev`, `Enable fbdev compat layer` y
  `msm_fbdev_driver_fbdev_probe` deben aparecer **0 veces** en el Image descomprimido.
  Si aparece alguno, el `CONFIG` no quedó off y el experimento nace muerto.
- G2: cmdline 567 B, sin `video=`, sin `fbcon`, sin `console=tty0`, con `console=ttyGS0`.
- G0–G8: los de siempre, más la verificación del cpio UKE-DIAG.

## Procedimiento tras el boot

1. SSH a `192.168.42.129` (`-i build/rootfs/uke-arch-root`). **sddm está enmascarado**
   desde el ciclo L31: no arrancará ni hará un commit solo.
2. Confirmar vivo: `uptime`, GPU, `/root/diag/` presente.
3. Confirmar que **no** hubo commit: el conector `DSI-1` debe estar *desconectado*
   (`status` = `unknown`/`disconnected`), porque nada ha hecho detect+modeset.
4. Disparar el modeset desde userspace. Primer intento de menor a mayor riesgo:
   - `echo detect > /sys/class/drm/card1-DSI-1/status`
   - `modetest -d msm -p` (el `-d msm` no enumeró en el test D-1; si falla, el plan B es
     un `drmModeSetCrtc` escrito a mano)
5. Si el SoC muere: reboot. Al volver, `/root/diag/` tendrá `dmesg.N.txt` con las 400
   líneas previas al death, `estado.txt` y `ultimo.txt`.

## Tabla de lectura pre-registrada

| Resultado | Lectura |
|---|---|
| **El commit sobrevive** | DSI + PHY + PLL + panel funcionan. El panel se puede encender. Siguiente: quitar el `:d` del boot y dejar que fbcon haga el commit sola |
| **Muerte, UKE-DIAG captura** | **Por fin la línea exacta.** Empieza el bisect del commit: CRTC → encoder → PHY/PLL → link clocks → `o82_prepare` |
| **Muerte sin captura** | Murió antes de 5,97 s ⇒ el commit no lo disparamos nosotros. Revisar qué otro cliente lo hizo |
| **No entra SSH** | El build noittings lo esperado. Recuperar con `boot-uke-k52L25-diag.img` (sha `e2c2ccc54520…`) + `set_active a` |

## Recuperación

```
fastboot flash boot_a build/bootimg/boot-uke-k52L25-diag.img   # sha e2c2ccc54520…
fastboot flash dtbo_a build/bootimg/s275-boot-dtbo-gpu-display.img  # sha 67a65bc161b6…
fastboot set_active a ; fastboot reboot
```