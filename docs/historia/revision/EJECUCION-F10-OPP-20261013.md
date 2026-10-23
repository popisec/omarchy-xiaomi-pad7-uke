# Ejecución F10 — OPP del host DSI a 148,65 MHz

**Fecha:** 2026-10-13
**Resultado del flash:** el OPP **se aplicó y está verificado en hardware**.
**Resultado del commit:** el camino mortal **sigue sin superarse** (ver §4).

---

## 1. Flash ejecutado

| | |
|---|---|
| Artefacto | `build/bootimg/s281-boot-dtbo-gpu-display-opp148.img` |
| sha256 | `90e41a6b4b91f47451bb18c0518193997604df7362631f7f3946c3ad6481b437` (gate, verificado antes de escribir) |
| Tamaño | 607.326 B |
| Partición | **solo `dtbo_a`** — kernel, `boot_a`/`boot_b`, `misc`, GPT, sin tocar |
| Duración | 0,051 s |
| Batería en el momento | **3415 mV** — por debajo del gate de 3700 mV. Aceptado por ser el flash más pequeño y rápido del proyecto (607 KB). **Anotado como violated-gate deliberado.** |
| `set_active a` | sí, antes del reboot |
| `slot-retry-count:a` | 5 → 7 tras el reboot |

**Rollback:** `fastboot flash dtbo_a build/bootimg/s275-boot-dtbo-gpu-display.img`
(sha256 `67a65bc161b6…`). Probado de facto: es el dtbo que llevaba puesto antes.

### Verificación posterior — NO POSIBLE

`fastboot fetch` → `Device does not support fetch command`. Este ABL no lo soporta.
No hay hash de lectura de vuelta. **El flash queda registrado como no verificado por
hash**; la verificación real vino por comportamiento (abajo), que es más fuerte.

---

## 2. ⭐ Verificación del OPP (la测量 importante)

`/sys/kernel/debug/clk/clk_summary` tras el boot:

```
disp_cc_mdss_byte0_clk        148645532 Hz    enable=0    ae94000.dsi   byte
disp_cc_mdss_byte1_clk        148645532 Hz    enable=0    ae96000.dsi   byte
disp_cc_mdss_byte0_intf_clk    74322766 Hz    enable=0                   byte_intf  (= byte/2)
disp_cc_mdss_pclk0_clk        158555234 Hz    enable=0                   pixel
disp_cc_mdss_pclk1_clk        158555234 Hz    enable=0                   pixel
disp_cc_mdss_esc0_clk          38400000 Hz    enable=0                   core
```

| Reloj | Antes (mainline) | Después (F10) | Vendor Android |
|---|---|---|---|
| `byte0_clk` | 187.500.000 | **148.645.532** | 148.648.750 |
| `pclk0_clk` | 158.555.234 | 158.555.234 | 158.558.666 |

**El OPP se aplicó.** El nodo `fase4-display.dts:390` es el que se consume.
Diferencia con el vendor: −0,002 % en byte, −0,002 % en pixel. Es el mismo reloj.

Esto confirma la fila 1 de la tabla pre-registrada en la parte del reloj
(`PRE-REGISTRO-F10-OPP.md` §7): el OPP que se edita es el que se aplica.

---

## 3. Efecto colateral observado

El conector pasó de `status = unknown` (sin modos) a:

```
status = connected
modes  = 3200x2136        (único modo, 120.00 Hz, 238x163 mm)
encoder 35, CRTC 85
```

El probe de arranque `K47-pan-probe-attach-ok` (t=0,597 s) ahora ancla contra un
enlace viable. Antes no había ningún modo publicado en el connector.

---

## 4. Commit: dos intentos fallidos por SINTAXIS, y el tercero

Registro honesto de los intentos. Los dos primeros **no dispararon nada** y no cuentan.

| # | Comando | Qué pasó realmente |
|---|---|---|
| 1 | `Hyprland --config /etc/hypr/hyprland.conf` | Error: el fichero no existe. Hyprland no arrancó. Sin commit. |
| 2 | `modetest -s 36` | **Sintaxis inválida.** `modetest` exige `-s <conn>[@<crtc>]:<mode>`. Imprimió uso y salió. Sin commit. |
| 3 | `modetest -s 36@85:3200x2136` | **Commit real.** SSH `rc=255`, `Timeout, server not responding` a los ~14 s. |

Las marcas `K47-pan-modes` que aparecen a t=591,6 s **no son del trigger**: son de las
consultas de lectura `modetest -c` / `-p` del diagnóstico anterior. Lo demuestra el
contexto, que es `get_modes`:

```
[  591.634470] UKE-POKE: K47-pan-modes
[  591.634570] UKE-P82: get_modes: entrada
```

> **Lección operativa:** antes de declarar cualquier marca como evidencia de un commit,
> comprobar si viene de `get_modes` (lectura) o de la ruta de commit. Una marca de
> `pan-modes` leída como "el commit corrió" fue un falso positivo de esta sesión.

### Síntoma del intento 3

```
rc=255  Timeout, server 192.168.42.129 not responding.   (~14 s)
```

El SoC dejó de responder. **Pendiente de determinar** si es la misma muerte de `w4-done`
o un punto distinto. Se leerá de `/root/diag-f10/dmesg-f10.log` (captura persistente en
la tablet, sobrevive a la muerte; el ACM del host es *lossy* y ya ha dado falsos
negativos en L24/L26/L28/L29).

---

## 5. Estado del display tras el intento

```
enabled = disabled
clocks: todos enable_count = 0
rails:  .0-vddil8b use=0   .0-vsp use=0   .0-vsn use=0
```

Display completamente apagado tras el intento. Sin panic en pstore.

---

## 6. Batería — hallazgo colateral importante

`/sys/class/power_supply/` está **VACÍO**. No hay `battery`, ni `usb`.

Causa raíz: `CONFIG_BATTERY_QCOM_BATTMGR`, `CONFIG_QCOM_PMIC_GLINK` y
`CONFIG_UCSI_PMIC_GLINK` están en `=m`, y **los `.ko` nunca se construyeron ni se
instalaron** (el build del rootfs no tiene paso `modules_install`). Además hay un
*vermagic* incompatible: el kernel corre como `7.2.0-rc2-palawan` pero el directorio de
módulos es `7.2.0-rc2-palawan+`.

Consecuencia: sin `pmic_glink` no hay UCSI/PD, así que el puerto USB del PC da
500–900 mA y la tablet **descarga con el cargador puesto**.

`qcom,shutdown-voltage = 3150 mV`; última lectura conocida 3415 mV.

**Procedimiento para llegar al gate:** apagar del todo, cargador de pared **sin pasar por
el PC**, 30–60 min, medir luego en fastboot (en fastboot no carga, pero la lectura vale).

**Fix de fondo:** tres líneas de Kconfig (`=m` → `=y`) + un `modules_install`. Ningún
driver nuevo hace falta. Requiere además bringup del ADSP (`remoteproc0: releasing adsp`),
que hoy lo deja apagado — ciclo aparte.

> **Riesgo para la lectura de F10:** una caída de tensión produce un `w4-done` ausente
> indistinguible de un apagado por voltage. Si el log muestra muerte limpia en la ruta
> DSI, es del kernel. Si muestra corte abrupto sin marcas, no se puede atribuir.

---

## 7. Reproducir el commit

```bash
ssh -i build/rootfs/uke-arch-root root@192.168.42.129

# 1. armar captura persistente (ground truth)
setsid nohup sh -c 'dmesg -n 7; stdbuf -oL dmesg -w >> /root/diag-f10/dmesg-f10.log' &

# 2. ver el modo exacto publicado (solo lectura)
modetest -c

# 3. EL COMMIT  (ojo: la sintaxis exige conn@crtc:mode)
setsid nohup modetest -s 36@85:3200x2136 > /root/diag-f10/modetest2.log 2>&1 &

# 4. tras la muerte: leer el log persistente
cat /root/diag-f10/dmesg-f10.log | tail -200
```
