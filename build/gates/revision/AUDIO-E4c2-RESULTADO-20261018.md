# AUDIO — E4c pasos 1-3 repetidos: **la tarjeta `UKE` se registra con la topología y sus PCM** — 18-oct-2026 16:50

Autorizado por el dueño (sin `aplay`). Base: arranque en frío con `uke-audio.service` VERDE; `bedais` y `dais` creados por el `of_platform_populate` de q6apm (padre `gprsvc:service:2:3`, `dais` en iommu group 10). Gate: 3838 mV, Charging, ADSP running; vigía + ACM. Logs `build/logs/audio/e4c2-20261018-tablet.log`.

## Resultado (MEDIDO) — **PASA, sin oops**
`insmod uke_audio_e4c.ko` (solo el overlay de la tarjeta; sin e4a/e4b):
- `snd-sc8280xp sound: …` la tarjeta hace probe, **carga `qcom/sm8650/UKE-tplg.bin`** y registra: `/proc/asound/cards` → `0 [UKE]: sm8650 - UKE`.
- PCMs creados desde la topología: `00-00 MultiMedia1 Playback`, `00-01 MultiMedia2 Playback`, `00-02 MultiMedia3 Capture`, `00-03 MultiMedia4 Capture` (`aplay -l` lo confirma). Mezclador `PRIMARY_MI2S_RX Audio Mixer MultiMedia1/2/5` presente (el backend MI2S con códec `spdif-dit`).
- Avisos benignos: `ALSA: Control name 'stream0.vol_ctrl0 MultiMedia1 Playback Volume' truncated…` (nombres >44 caracteres de la topología) y `MultiMedia1 Playback: ASoC: no backend DAIs enabled … possibly missing ALSA mixer-based routing` ⇒ **hay que activar el mezclador antes de reproducir**: `amixer -c0 cset name='PRIMARY_MI2S_RX Audio Mixer MultiMedia1' on`.
- **0** oops/faults de SMMU; ADSP/WPSS running, Charging, WiFi up. Ningún comando de grafo ni DMA llegó al ADSP todavía.
- El arreglo del padre (bedais/dais dentro de E2d) elimina el oops del primer intento: `q6apm_is_graph_in_push_pull_mode_from_id` encuentra su `apm`.
- **Estado**: tras medirlo, la sesion BT reinicio la tablet (la tarjeta, solo RAM, desaparecio; los logs de la tablet se perdieron: `e4c2-…-tablet.log` es una transcripcion de la salida medida).

## Siguiente: paso 4 (primera DMA real) — riesgo ALTO, solo con autorización expresa
1. `amixer -c0 cset name='PRIMARY_MI2S_RX Audio Mixer MultiMedia1' on` (solo software).
2. `aplay -D hw:UKE,0 /root/uke-1k-40dbfs.wav` (2 s, −40 dBFS): `APM_CMD_GRAPH_OPEN`, `SHARED_MEM_MAP_REGIONS` con `dma_addr | (0x1001 << 32)` (cliente SMMU de `dais`), `GRAPH_START`, y el LPAIF leyendo los búferes; las respuestas llegan a **puertos GPR dinámicos** (≥0x10000000), que el firmware quizá no enrute (el puerto 1 no se enrutaba).
   Resultados posibles: éxito (aplay sale sin error y sin faults) · `CMD timeout` en GRAPH_OPEN (inocuo; contingencia: recompilar `apr.ko` con otro rango de puertos dinámicos) · `Unhandled context fault`/ADSP `crashed` (stop/start del ADSP; si no vuelve, reset físico).
3. Reversa: parar `aplay`; `rmmod uke_audio_e4c` (la tarjeta, sana, se desregistra); si hubo oops o ASoC colgado NO usar rmmod (reiniciar).
Sin los altavoces reales (TDM + FS19xx, E7) esto no suena: solo valida la DMA/grafo.
