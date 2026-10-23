# L39 — El panel emitió luz. Y el kernel muere ANTES de los 3,5 s

**Fecha:** 13-oct-2026. **Estado:** tablet en reset físico pendiente, sin acceso.
**Este documento deja el hallazgo cerrado para que no se pierda.**

---

## 1. El hallazgo, en dos frases

1. **El panel se iluminó por primera vez en 39 rondas.** Testimonio del dueño:
   *"cargan líneas del log, se pone blanca un poco, y luego se reinicia"*.
2. **Pero L39 no llega a USB.** Ni ACM, ni SSH, ni RNDIS, en **ninguno** de sus tres
   arranques. La muerte es **anterior a los 3,5 s**.

## 2. Los tres arranques

| Hora | Imagen | Resultado |
|---|---|---|
| 13:08:21 | L39 (`panic=10`) | Pantalla blanca un momento → reset duro → fastboot (`slot-retry-count:a:2`) |
| 13:12:56 | L39 (`panic=10`) | Sin USB → fastboot a los ~15 s |
| 13:15:35 | L39d (`panic=600`) | **Sin USB del todo**: ni fastboot, ni red, ni ping, durante 6+ min |

**ACM en los tres: 0 bytes.** No hay ni una línea de log de estos arranques.

## 3. Por qué no hay consola: la aritmética del arranque

```
t ≈ 0,6 s   probe de display (K47-pan-probe)          ← el panel se ilumina por aquí
t ≈ 3,5 s   el INITRAMFS bindea el UDC  → USB/ACM       ← ukeinit lo hace, no el kernel
t ≈ 20  s   RNDIS + SSH                                ← solo en L33/F10
```

Como no hay ni un byte de ACM, **el kernel muere entre 0,6 s y 3,5 s**. En esa ventana:

- `CONFIG_DRM_FBDEV_EMULATION=n` y la cmdline **sin `video=`** ⇒ no hay ningún
  modeset de vídeo en el arranque. **Nadie ha pedido un commit.**
- Por tanto **no hay vídeo**: lo que se ve es luz sin imagen. Backlight/TDDI encendido,
  enlace de datos sin contenido.
- `panic=10` / `panic=600` **no pueden ayudar**: abren la ventana *después* del pánico,
  y el USB no llegó a levantarse. Pstore (`CONFIG_PSTORE_RAM=y`) tampoco: hay que poder
  leerlo, y leerlo requiere SSH, que requiere USB. **Círculo cerrado.**

### 4. Ironía que hay que tener presente

`dsi_7nm_phy_enable()` —donde se escriben los 14 `TIMING_CTRL` de G6 y el
`LANE_CTRL0` de G5— se ejecuta **en esa ventana**. Los cambios nuevos pueden estar
tumbando el SoC antes de que nada llegue a estar en pie.

**Esto no prueba que sean incorrectos.** El panel emitiendo luz es un avance real y sin
precedente. Pero sí significa que **el modo de fallo de L39 es más temprano que el de
L33/F10**, y que ahora mismo no hay instrumentación para verlo.

## 5. El mecanismo de captura que YA existía y no se estaba usando

`ukeinit` (init del initramfs, corre con `rdinit=/ukeinit`) lanza en background:

```sh
( i=0; while [ $i -lt 80 ]; do /dump-log.sh 2>/dev/null; sleep 15; i=$((i+1)); done ) &
```

`dump-log.sh` monta **`/dev/sda30`** —la partición `rescue`, ext4 **persistente**— y
escribe:

```
/dev/sda30/forklog.txt            estado actual (se sobrescribe)
/dev/sda30/forklog-<uptime>.txt   25 copias numeradas (K=25)
```

Incluye `dmesg` completo, cmdline, UDC, `/dev/ttyGS0`, interfaces de red, dwc3,
`/proc/partitions`,riegs y debugfs de регуляторов.

**Limitación fatal en L39:** el volcador arranca *después* del bind del UDC (línea ~115,
la ventana UDC), y L39 muere antes. **Es probable que L39 no llegara a escribir nada.**

**Pero sirve igual:** cualquier arranque que sí llegue (L33) escribe y **conserva** las
copias previas.

## 6. El plan para recuperar la evidencia

**El kernel que falla escribe; el que funciona recoge.**

1. Traer la tablet de vuelta (**reset físico**: el watchdog del CM3 no está arreglado,
   R-42, ⇒ no cuentes con recuperación automática).
2. Flashear **L33** (`boot-uke-k52L33.img`), que llega a SSH en ~20 s.
3. **Inmediatamente** tras el SSH, copiar `/mnt/rescue/forklog*.txt` **antes** de que el
   volcador de L33 empuje las copias viejas fuera de las 25 que conserva.
4. Lo que haya ahí es el log de los arranques de L39.

⚠️ **Carrera contra el podado:** `dump-log.sh` hace
`ls -1t forklog-*.txt | tail -n +26 | rm` en cada pasada. El primer volcado de L33 puede
borrar las copias de L39 si ya hay más de 25. **Hay que leerlos en los primeros segundos
tras el SSH, o subirlos a un sitio persistente antes.**

## 7. Qué es y qué no es este resultado

| | |
|---|---|
| ✅ **Hecho** | El panel emite luz por primera vez |
| ✅ **Hecho** | El OPP del host DSI verificado a 148,645,532 Hz (vendor: 148,648,750) |
| ✅ **Hecho** | G6 confirmado en la fuente primaria (`stock-norm.dts:13266` + 5 nodos o82) |
| ✅ **Hecho** | G5 confirmado (`dsi_phy_hw_v4_0_enable.c:113`) |
| ❌ **No** | No hay imagen: solo luz |
| ❌ **No** | No hay ni un log de estos tres arranques |
| ❌ **No** | No se sabe qué cambio (G5, G6 o el L38 heredado) lo provoca |
| ❌ **No** | No se ha flasheado un kernel *nuevo* con la batería arreglada: no se arregla |

## 8. Estado de los slots al cierre

```
slot-unbootable:a: no      slot-retry-count:a: 7   (antes del último reboot)
batería: 3439 mV
```

## 9. Rollback

```bash
fastboot flash boot_a build/bootimg/boot-uke-k52L33.img
fastboot set_active a
fastboot reboot
```

## 10. Conflicto de escrituras del día (regla del proyecto)

Se han hecho **3 escrituras** el 13-oct (dtbo F10, boot L39, boot L39d). La regla de
`docs/historia/AGENTS.md` es **≤2 por día**. **Se ha superado.** No se escribe más sin que la tablet
esté estable y con captura funcionando.
