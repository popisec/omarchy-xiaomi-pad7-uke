# AUDIO — E2d ejecutado: **q6apm y q6prm sondean y el APM responde (estado = 1)** — 18-oct-2026 16:00

Autorizado por el dueño (E2d: `updates/snd-q6apm.ko` parcheado + overlay e2d + `modprobe apr`). Gate: 3867 mV, Charging; vigía + `ssh dmesg -w` + ACM; kernel v4 (ouke4). Logs `build/logs/audio/e2d-20261018-*.log`.

## Resultado
**PASA tras corregir un segundo problema.**
1. Solo con el parche del puerto (src_port=3, comando enviado dentro del `probe` de q6apm): **sigue el `CMD timeout`**, pero con un dato nuevo gracias a la traza: **la respuesta `0x02001007` SÍ llega, ~3 ms después de vencer los 5 s** (2 intentos). El ADSP contesta; el problema es de entrega/procesamiento en el lado Linux mientras `apm_probe` está esperando.
2. Con el primer comando lanzado desde un **kworker** (parámetro `uke_async`, igual que la sonda): `qcom-apm gprsvc:service:2:3: uke: estado APM (async) = 1` a **1 ms**; **q6prm sondea y `q6prm_clocks` registra los relojes** (`LPASS_HW_MACRO`, `LPASS_HW_DCODEC`, `LPASS_CLK_ID_*` en `clk_summary`). Sin errores, ADSP running, Charging, WiFi up.
- Causa del bloqueo: **sin identificar con precisión** (hipótesis: esperar de forma síncrona dentro del `probe`, ejecutado desde `modprobe`/udev mientras se carga el módulo, retiene algo que necesita la ruta de recepción del canal GLINK; el kworker no). Es el mismo bloqueo que producía el `CMD timeout` de E2/E2b/E2c incluso con puerto 1: **parte del fallo de los ciclos 1-3 era este, no solo el puerto**. Pendiente de verificar si con puerto 1 + async también respondería (no probado; la sonda mostró que con puerto 1 en E2 la respuesta tampoco constaba, sin traza).
- Entregado: `kernel/0005` (src_port = id de servicio + `uke_async` por defecto activo + `uke_trace`, `uke_delay_ms`, `uke_src_port`), `out/snd-q6apm-uke.ko` (sha `f415a1d7…`, modversions idénticos al del árbol), overlay `e2d`.

## Reversa y estado final
rmmod q6prm_clocks/q6prm/snd_q6apm/apr, `uke_audio_e2d` (overlay retirado), `updates/snd-q6apm.ko` movido a `/root/snd-q6apm-uke.ko.installed` + depmod (`modinfo -n snd-q6apm` vuelve a `kernel/`), snd* descargados. ADSP/WPSS running, Charging, wlan0 UP. `fastrpc.ko` sigue cargado (refcnt colgado, hasta reiniciar).

## Siguiente (decisiones del dueño; cada paso con riesgo pide autorización)
1. **Hacerlo persistente** (el camino que ya funciona): `updates/snd-q6apm.ko`, `uke_audio_e2d.ko` y `apr` al arranque (servicio `uke-audio.service` con la guarda de `uke-bootguard`, después de `uke-carga`), sin la blacklist de `apr` para ese caso. Hoy `apr` está en la blacklist de carga a propósito.
2. **E3** (relojes PRM + LPI pinctrl): ya hay `q6prm-lpass-clocks`; falta `pinctrl-sm8650-lpass-lpi` y votar relojes.
3. **E4**: DAIs/DMA con SMMU 0x801001/0x1061 (admitidos en v4). Riesgo: los grafos usan puertos dinámicos (`gpr_alloc_port`, ≥0x10000000); no sabemos si el firmware enruta sus respuestas — la prueba de E4 lo dirá.
4. Los altavoces (E7) siguen necesitando el driver FS19xx y el módulo TDM (trabajo grande); el micro, E5.
