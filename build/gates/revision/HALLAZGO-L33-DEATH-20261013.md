# HALLAZGO L33 (13-oct ~18:10) — **EL COMMIT DEL MODESET, POR FIN, DESPLEGADO**

## Por qué este documento existe

Nueve ciclos (L25→L33) buscando la misma cosa: **dónde se muere exactamente el SoC cuando
se hace el commit de un modeset**. Era imposible por dos razones, ambas resueltas aquí:

1. La muerte ocurría a **3,96 s** y UKE-DIAG no escribía hasta los **5,97 s** ⇒ nunca la veía.
2. Con `video=DSI-1:d` (L25) el sistema vivía, pero `DRM_MODE_FORCE_OFF` hace que
   `drmModeSetCrtc` devuelva `-EINVAL` ⇒ **nadie podía lanzarla tampoco**.

L33 quita las dos trabas a la vez: `CONFIG_DRM_FBDEV_EMULATION=n` (nadie hace commit al
arrancar) y **ningún token `video=`** (nada fuerza el conector). SSH a los 20 s, y el
commit se dispara a los **207 s**, disparado por el greeter de `sddm`.

## La secuencia del commit, completa

Extraída de `out/acm-keep/acm-L33-8arranques.log` (consola serie `ttyGS0`, que sí sobrevivió).
Guardada en `out/diag-L33/VENTA-MUERTE-acm-207s.txt`.

```
[207.246] K47-pan-modes      ×3      ← o82_get_modes, tres modos
[207.911] K47-enc-mset               ← encoder atomic_enable
[207.912] K47-mgr-mset               ← manager atomic_enable
[207.912] K47-crtc-en                ← CRTC atomic_enable
[207.915] K47-phy-en         ×2      ← DSI PHY enable (2 links)
[207.915] K47-7nm-en         ×2      ← del PHY "7nm" (L17 del DPU de Qualcomm)
[207.918] K47-host-pwr               ← clocks de enlace DSI
[207.924] K47-pll-prep               ← programa del PLL
[207.945] K47-host-pwr               ← segunda vez
[207.967] K47-host-en                ← host enable          ◄── ÚLTIMO PASO CORRECTO
[207.967] dsi_err_worker: status=4   ×8 en ráfaga          ◄── ERROR DE FIFO, INMEDIATO
[207.968] K47-pan-prep               ← panel prepare
[207.969] K47-pan-pwron              ← panel power on
[207.979] K47-pwr-OK / pan-pwron-ok
[207.979] K47-pre-rst / K48-rst-A → A2 / R → R2          ◄── resets del panel (11 ms)
[207.993] K49-esd-irq ×2                                  ◄── ESD fired en gpio 86 y 87
[208.102] K47-pre-rstOK
[208.103] K47-pre-init
[208.103] UKE-K47c: cmd#0 off=0 dt=39 ◄── primer comando DCS al panel
[208.103] K47-host-xfer
[208.104] K47-host-xfer
[208.181] msm_dsi: dsi_cmds2buf_tx *ERROR* wait for video done timed out   ◄── MUERTE
```

**Y no hay una sola línea más.** El SoC muere en los milisegundos siguientes.

## Las dos respuestas concretas

### 1. `status=4` = `DSI_ERR_STATE_FIFO`

```c
/* drivers/gpu/drm/msm/dsi/dsi_host.c:89-95 */
#define DSI_ERR_STATE_ACK                        0x0000
#define DSI_ERR_STATE_TIMEOUT                    0x0001
#define DSI_ERR_STATE_DLN0_PHY                   0x0002
#define DSI_ERR_STATE_FIFO                       0x0004   ◄── status=4
#define DSI_ERR_STATE_MDP_FIFO_UNDERFLOW         0x0008
#define DSI_ERR_STATE_INTERLEAVE_OP_CONTENTION   0x0010
#define DSI_ERR_STATE_PLL_UNLOCKED               0x0020
```

El controlador DSI levanta un **error de FIFO en el mismo instante en que se habilita el
host** (`K47-host-en`, 207,967 s), ocho veces seguidas. No es timeout (0x1), no es
`DLN0_PHY` (0x2), no es **`PLL_UNLOCKED` (0x20)** ⇒ **el PLL enganchó bien**. Lo que falla
es la capa de enlace/buffer.

Y ojo: `DSI_ERR_STATE_FIFO` **no** dispara el `dsi_sw_reset()` que sí hace
`MDP_FIFO_UNDERFLOW` (`dsi_host.c:1574`). O sea que el error se anota y se sigue.

### 2. `wait for video done timed out` = el motor de vídeo nunca arrancó

```c
/* drivers/gpu/drm/msm/dsi/dsi_host.c:1196-1212 */
static void dsi_wait4video_done(struct msm_dsi_host *msm_host)
{
        dsi_intr_ctrl(msm_host, DSI_IRQ_MASK_VIDEO_DONE, 1);
        reinit_completion(&msm_host->video_comp);
        ret = wait_for_completion_timeout(&msm_host->video_comp,
                        msecs_to_jiffies(70));        /* 70 ms */
        if (ret == 0)
                DRM_DEV_ERROR(dev, "wait for video done timed out\n");
        ...
}
```

Se agotan los **70 ms** esperando el IRQ `VIDEO_DONE`. El motor de modo vídeo nunca
señaló haber enviado el blanking packet. En un panel que funciona, ese IRQ llega en
microsegundos tras `dsi_set_mode(VIDEO)`; 70 ms es una eternidad.

## Qué queda exonerado (importante)

Por primera vez se puede decir **qué NO es**, porque lo hemos visto pasar:

| Paso | Resultado |
|---|---|
| `o82_get_modes` | ✅ 3 modos, sin quejar |
| `enc_mset` / `mgr_mset` / `crtc-en` | ✅ |
| PHY enable (2 links) + `7nm-en` | ✅ |
| **PLL** | ✅ engancha (`status` no tiene `0x20`) |
| **Relojes de enlace** (`host-pwr`) | ✅ |
| `panel prepare` + `panel power on` | ✅ |
| **Resets del panel** (`rst-A`, `rst-A2`, `rst-R`, `rst-R2`) | ✅ los 4, en 11 ms |
| **ESD** | ⚠️ salta en gpio 86 y 87 |
| **Primer DCS (`cmd#0 dt=39`)** | ⚠️ se encola pero no se envía |
| **Motor de vídeo / enlace FIFO** | ❌ **AQUÍ** |

## Consecuencia para el bisect

El siguiente paso **ya no es a ciegas**. La variable está acotada a la capa de enlace del
controlador DSI, entre `K47-host-en` y el primer `cmds2buf_tx`. Candidatos, en orden:

1. **Configuración del enlace**: número de data lanes, `DSI_CTRL`, tamaño/burst del MDP,
   y el bloque `DSI_MDP_*`. El error es literalmente de FIFO ⇒ mirar el buffer antes que el PHY.
2. **Secuencia de exit de ULPS**: si el PHY sewakeó pero quedó en LP, el motor de vídeo no
   arranca. Comparar con `msm_drm.ko` de Android entre `dsi_host_enable` y el primer comando.
3. **`dsi_set_mode(VIDEO)`** y cuándo se llama respecto a `host-en`: en mainline se llama
   *dentro* de la cadena; el orden importa.
4. **El ESD** (gpio 86/87 salta durante los resets del panel): puede ser normal (el panel
   dispara ESD al resetear) o puede ser el síntoma de un reset mal temporizado.

**El paso 2 es el más promising**: ya tenemos el `msm_drm.ko` de Android con 21891 símbolos
(`~/proyectos/ubuntu-uke/stock/modules/msm_drm.ko`) y sabemos exactamente qué
llamada hacer para compararlo. Es la comparación que faltaba en el ciclo anterior, cuando
solo teníamos el arranque de 4 s y no la secuencia de power-on.

## Efecto secundario documentado: **el modeset fallido envenena el arranque**

Después de morir en el commit, la tablet **ya no arrancaba**: 3 resets seguidos, cada uno
muriendo en `K47-crtc-en` a los ~10,4 s (y uno con
`dsi_cmds2buf_tx *ERROR* wait for video done timed out` a los 10,39 s).
`slot-retry-count:a` subió a 3.

Es el mismo punto de fallo, pero en el `hw_init` del arranque en vez de en el commit.
**Interpretación**: el DPU/DSI quedó programado a medias y el estado persiste entre resets.
Se necesitó entrar en fastboot y reflashear L25-diag para desbloquearla.

**Consecuencia práctica**: cada intento de modeset que muera cuesta **un ciclo extra de
recuperación**, no solo un flash. Anotado para el presupuesto de slots.

## Los datos

- `out/diag-L33/BASE-pre-sddm.txt` — 4361 líneas de dmesg justo antes de disparar
- `out/diag-L33/dmesg.{1,2,3,4}.txt` — instantáneas del vigilante, última a **197,19 s**
- `out/diag-L33/VENTA-MUERTE-acm-207s.txt` — **la secuencia del commit** (156 líneas)
- `out/acm-keep/acm-L33-8arranques.log` — 59230 líneas de consola, los 8 arranques