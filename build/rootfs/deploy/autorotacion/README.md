# Autorrotación de la uke (T7) — material preparado, NADA desplegado

Fecha: 18-oct-2026. Informe con etapas R0–R8, riesgos y autorizaciones: [`build/gates/revision/AUTOROTACION-20261018.md`](../../../gates/revision/AUTOROTACION-20261018.md).

> Nada de esto se ha copiado a la tablet ni se ha ejecutado en ella. Solo se ha probado `uke-autorotate` en el PC con un
> `monitor-sensor` y un `uke-rotate` simulados. **No toca el ADSP ni fastrpc** (es solo cliente D-Bus de iio-sensor-proxy).

## Qué hay

| Ruta | Qué es | Etapa |
|---|---|---|
| `root/usr/local/bin/uke-autorotate` | Demonio: lee `monitor-sensor --accel`, espera 0,8 s sin cambios, llama a `uke-rotate <grados>`. `lock [grados]` / `unlock` / `toggle` / `status` | R6 |
| `root/etc/systemd/user/uke-autorotate.service` | Unidad de usuario; `ConditionPathExists=/dev/fastrpc-adsp` (sin PD de sensores no arranca) | R6 |
| `root/etc/uke/autorotate.conf.example` | Mapa orientación de iio-sensor-proxy → grados (`MAP_*`) y tiempo de asentamiento | R5/R6 |
| `deploy.sh check\|apply\|revert\|status` | Copia/quita lo anterior. **No habilita nada** | R6 |
| `propuesto/uke-sensors-extract.sh` | Extracción SOLO LECTURA de odm/vendor/persist de Android (EROFS por loop `ro`, persist por `debugfs rdump`) | R1 |
| `propuesto/uke-sensors-import` | Apunta `/odm/etc/sensors/config`, `/vendor/etc/sensors/sns_reg_config`, `/mnt/vendor/persist/sensors` a copias en `/var/lib/uke-sensors` | R2/R3 |
| `propuesto/adsprpcd_sensorspd.service` | Gemelo de `adsprpcd_audiopd.service`: `adsprpcd sensorspd` | R3 |
| `propuesto/71-uke-sensors.rules` | udev: tipos `ssc-accel ssc-proximity` + `ACCEL_MOUNT_MATRIX` (identidad provisional) en `/dev/fastrpc-adsp*` | R5 |
| `android-paths-opened-by-sensorspd.txt` | Rutas que el PD de sensores abrió en el arranque de Android (`logcat-30s.txt` del 17-oct) | R1 |

`propuesto/` NO tiene `deploy.sh` a propósito: son piezas de R1–R5, que exigen orden del dueño y coordinación con la sesión de audio.

## Uso previsto (tras R4 verde)

```bash
build/rootfs/deploy/autorotacion/deploy.sh check && build/rootfs/deploy/autorotacion/deploy.sh apply
# en la tablet, como omarchy:
systemctl --user enable --now uke-autorotate
uke-autorotate lock        # bloqueo de rotación (se queda en la orientación actual); lock 90 fija antes esa orientación
uke-autorotate unlock      # desbloquea y aplica ya la orientación que ve el sensor
```
Para atarlo a una tecla: `uke-autorotate toggle` (p. ej. en `bindings.lua`, junto a los binds de T2).

## Prueba en el PC (hecha 18-oct)

`monitor-sensor` falso emite `normal`, `left-up`→`right-up` (a 0,2 s), `bottom-up`: salen `rotate 0`, `270`, `180` (el vaivén `left-up` se
descarta por el asentamiento); con `lock` no sale ninguna llamada; `unlock` reaplica `bottom-up`.

## Pendiente de medir en la tablet (R5)

- El mapa `MAP_*` es el de iio-hyprland (`left-up`→90, `right-up`→270, `bottom-up`→180); depende de la matriz de montaje y de que el panel sea
  landscape nativo. Si sale al revés: intercambiar 90↔270 en `autorotate.conf` (o `uke-rotate touchmap`).
- `ACCEL_MOUNT_MATRIX` real: medir con `ssccli --sensor accelerometer` en 4 posturas (patrón del PR gts8pwifi).
- Nunca se ha visto `monitor-sensor` con el SSC de esta tablet: el formato de línea es el documentado de iio-sensor-proxy 3.x.
