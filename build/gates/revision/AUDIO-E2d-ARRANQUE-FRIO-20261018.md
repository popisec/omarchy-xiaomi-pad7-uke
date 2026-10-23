# AUDIO — primer arranque en frío con `uke-audio.service`: ROJO por el primer comando APM perdido; arreglo preparado — 18-oct-2026

## Qué pasó (MEDIDO, arranque tras el reset físico a 16:32)
- Reinicio: `sync` + `systemctl reboot` (16:32) dejó la tablet **sin volver** (USB responde a ping, sshd cerrado >8 min; apagado colgado, probable por el ASoC bloqueado tras el oops de E4c). El dueño hizo reset físico y la dejó en fastboot; `fastboot reboot` (lectura previa: 3847 mV, slot a, retry a=7 b=6) y arrancó bien.
- Estado tras el arranque: `uke-carga`, `uke-wifi`, `uke-bt` (**VERDE al primer intento**, sin reintentos), `uke-desktop`, `uke-touch`, `bluetooth` activos; ADSP/WPSS running, Charging, wlan0 UP (192.0.2.15). **Sin oops, faults, hung-task ni errores de SMMU.** `uke-audio.service`: **failed (ROJO)**.
- Causa del ROJO: el servicio cargó E2d + `apr` a 7,8 s de uptime (≈3,5 s después de que el ADSP subiera) y **el primer `APM_CMD_GET_SPF_STATE` se perdió**: `qcom-apm: uke: estado APM (async) = 0` tras `CMD timeout` (5 s). Es el mismo patrón que Android (el primer comando falla, ~50 ms después responde): en frío el SPF tarda en estar listo. En caliente (ADSP ya estable) siempre respondió a 1 ms. `q6apm_dai`/`bedais` sí cargaron con el padre correcto (arreglo del oops de E4c) y sin faults.

## Arreglo (preparado en el PC; NO instalado)
- `kernel/0005` + `snd-q6apm-uke.ko` (sha `5376897a…`): el comando de estado asíncrono **se reintenta** cada ~1 s (+5 s del timeout) hasta `uke_retries` (15) veces mientras el estado sea 0; cada intento deja `uke: estado APM (async) = N (intento K)`.
- `uke-audio-up.sh`: ya no da ROJO al primer `CMD timeout`; espera hasta `UKE_AUDIO_WAIT_APM` (75 s; el servicio tiene 150 s) el `estado = 1`; ROJO solo si vence el plazo con timeouts, AMARILLO si no vio ninguna línea. Pruebas con mocks: 20 ok / 0 fallos.
- Pendiente de decisión del dueño: instalar (`boot/deploy.sh --go --module --service`: solo ficheros) y comprobar con un **reinicio en frío** (el apagado ahora debería ser normal: el ASoC ya no está colgado), o primero probar en caliente `uke-audio-up.sh --down && uke-audio-up.sh` (no reproduce el timing frío).

## Respuesta a la sesión BT (ya enviada)
`uke-bt` VERDE al primer intento (colchón 7,84 s desde uke-wifi; chip OK a 25,4 s de uptime), `hci0` y `Powered: yes`; un único aviso de Quickshell por `org.bluez` a las 16:32:16 (el shell arrancó ~4 s antes que hci0).

---
# Segundo arranque en frío (16:47, `systemctl reboot` normal, con el arreglo instalado) — **TODO VERDE**
- Reinicio limpio: SSH de vuelta a los ~23 s (el apagado ya no se cuelga: el ASoC no estaba bloqueado).
- `uke-audio.service`: **active, Result=success** — `VERDE: APM estado 1 y q6prm_clocks cargado` a 1 s de ejecutar (`uke: estado APM (async) = 1 (intento 1)` a 7,77 s de uptime). Esta vez el primer comando sí respondió; los reintentos quedan como red de seguridad (el arranque anterior lo perdió: es una carrera de tiempo).
- `uke-carga`, `uke-wifi`, `uke-bt` (hci0, Powered: yes), `uke-desktop`, `uke-touch`, `bluetooth` activos; ADSP/WPSS running, Charging, wlan0 UP (192.0.2.15). Sin oops/faults de SMMU (el `grep` solo casó con la cmdline).
- Hasta aquí: **q6apm/q6prm/bedais/dais (con SMMU del LPASS) y los relojes PRM de E3 (bajo demanda) arrancan solos**; todavía sin tarjeta ni sonido.
