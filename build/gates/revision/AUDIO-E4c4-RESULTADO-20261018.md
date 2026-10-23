# AUDIO — E4c paso 4: **¡la primera DMA del LPASS funciona!** El puntero PCM avanza a 48 kHz — 18-oct-2026 16:53

Autorizado por el dueño (`amixer` + `aplay` a −40 dBFS). Base: arranque en frío, `uke-audio.service` VERDE (E2d con bedais/dais, SMMU del LPASS), tarjeta mínima `UKE` (E4c). Gate: 3820 mV, Charging, ADSP running; vigía + `dmesg -w` + ACM. Log `build/logs/audio/e4c4-20261018-tablet.log`.

## Resultado (MEDIDO) — **PASA**
1. `insmod uke_audio_e4c.ko` → `0 [UKE]: sm8650 - UKE`, sin oops. Mezclador: `amixer -c0 cset name='PRIMARY_MI2S_RX Audio Mixer MultiMedia1' on,on` (valores `on,off`).
2. `aplay -D hw:UKE,0 /root/uke-1k-40dbfs.wav` (2 s, 1 kHz, −40 dBFS): **rc 0, 2,69 s** de reloj (2 s de audio + apertura), sin `CMD timeout`, sin `DSP returned error`, sin faults de SMMU.
3. **Prueba de que se mueve DMA real** (`aplay -t raw /dev/zero`, silencio; estado leído en `/proc/asound/card0/pcm0p/sub0/status`): `state: RUNNING`, `hw_ptr` **93 599** a los 2 s → **237 119** a los 5 s ⇒ **47 840 tramas/s ≈ 48 kHz** (nominal), `delay 24960`, sin xruns. Es decir: el ADSP/LPAIF consume en tiempo real nuestro búfer por el cliente SMMU de `dais` y reporta la posición (el grafo `MultiMedia1 → PRIMARY_MI2S_RX Audio Mixer → Primary MI2S Playback → spdif-dit` está activo: DAPM `On`, `stream active`).
4. Ruta DAPM (debugfs): `MultiMedia1 Playback` ⟶ `stream0.wrsh_ep1`(gprsvc:service:2:3) ⟶ … ⟶ `device16.i2s_rx1` ⟶ `Primary MI2S Playback` ⟶ `spdif-dit Playback`.
5. ADSP `running`, `Charging`, WiFi up durante y después; sin oops/faults.

## Lo que esto prueba (y lo que no)
- **Prueba**: AudioReach de mainline funciona con el SPF de Xiaomi con tres arreglos nuestros: puerto de origen GPR = id de servicio (3/7) para los comandos de nivel de servicio, primer comando asíncrono con reintentos, y `dais` con el padre correcto; **el cliente SMMU (0x801001/0x1061) y el `dma_addr | (sid << 32)` son correctos**; los puertos GPR dinámicos de los grafos **sí** reciben respuestas (el grafo abre, arranca y reporta posición). Pipeline PCM → ADSP → LPAIF operativo.
- **No hay sonido todavía**: PRIMARY_MI2S_RX no tiene pines ni amplificador. Para los altavoces faltan: (a) **backend TDM** (`TDM-LPAIF_VA-RX-PRIMARY`, 4 canales, 48 kHz, 32 bit) en `audioreach.c`/`q6apm-lpass-dais` y su subgrafo en la topología con los parámetros del módulo (ACDB `Forte`), (b) **pinmux LPI gpio6-9 función 2** (E3: ya hay pinctrl con `uke_tdm1_active`), (c) el **driver FS19xx** de los 4 amplificadores (I2C-4 + `fs19xx.fsm`) y el reset/IRQ por GPIO, (d) topes de volumen seguros (sin el algoritmo de protección `FSADSP` del vendor hay riesgo de dañar altavoces).
- No se probó la reversa de la tarjeta con `rmmod` (se deja cargada hasta el próximo reinicio: solo RAM). Tampoco la captura.

## Siguiente (decisiones del dueño)
1. Seguir hacia los altavoces: E7 es trabajo grande (TDM en AudioReach + subgrafo + FS19xx). Antes, **ingeniería inversa del ACDB `Forte`** (partición `super`/`odm_b`, solo lectura) para los parámetros TDM y la cadena del amplificador.
2. Alternativa audible a corto plazo: **Bluetooth A2DP ya funciona** (línea BT).
3. Mientras: dejar `uke-audio.service` como está (E2d + bedais/dais al arrancar); las tarjetas/E3/E4c solo bajo orden.
