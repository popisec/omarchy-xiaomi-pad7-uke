# AUDIO — E8 diagnóstico (D-0/D-1) ejecutado: los amps están vivos y con reloj; el silencio apunta al volumen — 18-oct-2026 21:30

Autorizado por el dueño. Vigía + `dmesg -w` + ACM; tras el reinicio en frío de la sesión BT (21:24) se rearmaron y se rehízo la carga en orden: `uke_fs19xx.ko` nuevo (debugfs, sha `48e399ff…`) copiado a `extra/`, `insmod e7i2c` → i2c-4 + 4 amps (`DEVID 0x2900`), `insmod e3` + `modprobe pinctrl-sm8650-lpass-lpi`, `insmod e8b`. Volcado completo (solo lectura) en `build/logs/audio/e8-diag-20261018.txt` (sin commit: ignorado). 0 oops/faults, ADSP running, Charging, `uke_fs_play` devuelto a `N`.

## Qué dicen los registros (MEDIDO; la interpretación de bits es INFERIDA)
| Reg | Reposo | Reproduciendo (play=1, vol 0x20) | Lectura |
|---|---|---|---|
| 0x16 | `ffc0` | `20c0` | volumen = byte alto: **reposo/reset = 0xFF (máximo, como el «Volume 255» de Android)**; con nuestro 0x20 el amp está ~223 pasos por debajo |
| 0x10 / 0x11 | `0001` / `0000` | `0000` / `00ef` | fuera de standby y habilitado (secuencia aplicada) |
| 0x17 | `900b` | `980b` | código de frecuencia 9 = 48 kHz + bit de actualización |
| 0x00 | `0000` | `0240` | un registro de estado cambia (bits 0x200/0x040), **igual en los 4 amps** |
| 0x0C, 0x0A, 0x05, 0x01/0x02 | `00fe`, `0000`, `0000`, `0130/0119` | `0069`, `0043/44`, `0021`, `0128/0117…` | también cambian con el reloj presente (INFERIDO: bloqueo del PLL/detección de I²S) |
| 0x0E | `0003` | `0001` | cambio de estado de reset/arranque |
| 0x30 | `0210` | `0210` | (parada la deja en `0310`) |
Los 4 amps son idénticos salvo las constantes de calibración (0x1A/0x1C), como en el preset. No hay evidencia de fallo (no sé qué bits son de OCP/OTP; el estado cambia por igual en los cuatro).

## Conclusión provisional
Los FS19xx **reciben reloj, se habilitan y cambian de estado**: la ruta Linux→ADSP→TDM→amp funciona hasta donde puede verse sin instrumento. Lo más probable es que **no se oiga por el volumen**: Android reproduce a 235-243 y el máximo es 255; con el tono a −40 dBFS (≈ 1 % de amplitud) y el registro en 0x20/0x40 la salida queda ~100 dB por debajo. **Seguridad:** el contenido de prueba es −40 dBFS, así que incluso con el volumen al máximo del amp la salida es ≈ −40 dBFS (un tono muy bajo); lo peligroso sería contenido a fondo, que no se usa.

## Cambio ya hecho en el PC (sin desplegar)
`uke_fs_volmax` pasa a modificable en caliente (0644, recortado a 255): el tope sigue en 0x80 por defecto y subirlo exige un `echo` explícito de root. Evita recargar la tarjeta (≈15 s de timeouts del APM) en cada escalón. Nuevo `.ko` compilado (sha en `out/`), pendiente de copiar/recargar (requiere D-0 otra vez).

## Siguiente (decisión del dueño)
Escalera con el WAV de −40 dBFS, ≤ 3 s por escalón, tope a subir con `echo`: **0xC0 → 0xE0 → 0xF3** (0xF3 = 243, el nivel de música de Android). El dueño escucha y para ante cualquier distorsión, calor o ruido anormal. Si siguiera mudo a 0xF3 pasaríamos a las hipótesis de slots/línea de datos (informe `AUDIO-E8-DIAG-PREPA`).
