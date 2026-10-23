# PRE-REGISTRO F4/L34 — 13-oct · **ciclo 1a: `TIMING_FLUSH ← 1`**

## La variable

Una sola escritura nueva en `dsi_timing_setup()`, rama de vídeo
(`drivers/gpu/drm/msm/dsi/dsi_host.c`), después de los seis registros de timing:

```c
dsi_write(msm_host, REG_DSI_TIMING_FLUSH_L34, 0x1);   /* offset mainline 0x1e0 */
```

**Nada más cambia.** La cmdline de L34 es **byte-idéntica** a la de L33 (verificado:
`L33 cmdline == L34 cmdline → True`), así que el resultado es atribuible al registro.

## Por qué este offset (evidencia, no suposición)

Desensamblado del `msm_drm.ko` de Android con `llvm-objdump`, función
`dsi_ctrl_hw_cmn_set_video_timing` @ `0x12d75c`:

```
12d90c: f9400268   ldr  x8, [x19]
12d910: 52800020   mov  w0, #0x1
12d914: 91079101   add  x1, x8, #0x1e4
12d918: 94000000   bl   <dsi_writel>        → WRITE(base+0x1e4, 1)
```

Y en la misma función, justo antes:

```
12d8e8: 52977000   mov  w0, #0xbb80
12d8ec: 72a00080   movk w0, #0x4, lsl #16    → w0 = 0x0004bb80
12d8f0: 9102f101   add  x1, x8, #0xbc
12d8f4: 94000000   bl   <dsi_writel>        → WRITE(base+0xbc, 0x4bb80)  HS_TIMER_CTRL
12d8fc: 52802000   mov  w0, #0x100
12d900: 72a00020   movk w0, #0x1, lsl #16    → w0 = 0x00010000
12d904: 91029101   add  x1, x8, #0xa4
12d908: 94000000   bl   <dsi_writel>        → WRITE(base+0xa4, 0x10000)   ← ver nota
12d910: ...                                      WRITE(base+0x1e4, 1)      TIMING_FLUSH
```

Mainline escribe solo los seis timings (`0x20`–`0x34` en su numeración) y nada más.

**El desplazamiento**: el `.ko` de Android usa el mapa CAF, que es el de mainline **+4**
(mainline lo corrige en runtime, `dsi_host.c:2038`: `msm_host->ctrl_base += cfg->io_offset`).
CAF `0x1e4` → mainline **`0x1e0`**. Encaja en el hueco libre entre `RDBK_DATA_CTRL` (0x1d0)
y `VERSION` (0x1f0). Se comprobó que `REG_DSI_HS_TIMER_CTRL` = **0xb8** en mainline,
coherente con CAF 0xbc − 4: **el desplazamiento está confirmado por un registro que sí existe**.

## Nota: un registro que el informe no menciona

El subagentealarmó de `TIMING_FLUSH` y `DB_MODE`, pero en el mismo desensamblado aparece
**un tercer write que no estaba en el informe**: `base+0xa4 ← 0x00010000`
(mainline `0xa0`). Está entre el HS-timer y el flush. Queda **sin tocar** en este ciclo
(criterio de una variable) y anotado como candidato para 1d.

## Instrumentación añadida (solo lectura, no cambia comportamiento)

```c
pr_info("UKE-L34: timing pre-flush: FLUSH(1e0)=%x HS_TIMER(b8)=%x LINKCFG(a0)=%x\n", ...)
```

Imprime los **valores de reset** de los tres registros antes de escribir. Si el commit
vuelve a matar, sabremos qué tenía el hardware de origen. Es el único extra del ciclo.

## Artefacto

| | |
|---|---|
| **sha256** | `c14e8d9a843e2a6c02d98d7253447fd76e1ce17f6c2e022a19945a8cc90daadd` |
| Tamaño | 100663296 B |
| Kernel | `k52L33-build/arch/arm64/boot/Image.gz`, sha `8a0ca07c7d5f…` |
| Cmdline | 567 B, **idéntica a L33** |
| Patch | `build/gates/patches/l34-timing-flush.diff` (52 líneas) |

### Verificación en el binario antes de flashear

```
UKE-L34: timing flush comprometido   x1     ← el cambio está dentro
L34-timing-flush                     x1     ← la llamada uke_poke
UKE-L34: timing pre-flush            x1
msm.fbdev                            x0     ← emulación de fbdev sigue ausente
drm_fb_helper                         x0
UKE-POKE                           x113     ← migas intactas
K47-                                 x27
msm_mdss_reset SALTADO                x1
```

Gates G0–G8 verdes + gate L34 (la miga del flush debe salir x1).

## Procedimiento

1. **Poner la tablet en fastboot** (SSH no puede: `reboot bootloader` → `systemctl`, no hay logind).
2. Preflight: `battery-voltage` (**gate ≥3700 mV; está por debajo ⇒ cargador**), `slot-retry-count`.
3. `fastboot flash boot_a boot-uke-k52L34.img` + `set_active a`.
4. Armar lector ACM **antes** del reboot.
5. `fastboot reboot` → SSH a los ~20 s.
6. `setsid sh /root/diag-watch-ssh.sh &` (**el vigilante embebido no sirve**, ver NOTAS).
7. **NO arrancar sddm todavía.** Comprobar primero que el sistema vive y que la
   instrumentación aparece en `dmesg` (los valores de reset del flush/HS-timer/0xa0).
8. Cuando todo cuadre: `systemctl unmask sddm && systemctl start sddm` ⇒ el commit.

## Tabla de lectura

| Resultado | Lectura |
|---|---|
| **Sobrevive al commit y el panel se enciende** | H1 confirmada. Se finishes pantalla |
| **Sigue muriendo pero sin ráfaga `status=4`** | El flush era necesario pero insuficiente ⇒ pasa a 1b (`HS_TIMER`) |
| **Sigue muriendo con ráfaga `status=4` igual** | H1 refutada como causa ⇒ ciclo 2 (limpieza W1C) |
| **El panel se enciende pero parpadea/negro** | El timing sepriló tarde ⇒ mover el flush antes de los DCS (H2) |

## Recuperación

```
fastboot flash boot_a build/bootimg/boot-uke-k52L25-diag.img   # sha e2c2ccc54520…
fastboot set_active a ; fastboot reboot
```

⚠️ **Recordatorio del coste**: un commit que mata **envenena el arranque** (3 resets, cada
uno muriendo en `K47-crtc-en` a los ~10,4 s). Cada intento cuesta un ciclo extra de
recuperación, no solo un flash.