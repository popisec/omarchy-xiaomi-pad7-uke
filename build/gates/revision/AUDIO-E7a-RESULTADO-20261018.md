# AUDIO — E7a ejecutado: el backend TDM del altavoz (TDM_SINK) arranca y el ADSP consume los datos a 48 kHz — 18-oct-2026 17:45

Autorizado por el dueño. Gate: 3819 mV, Charging, ADSP/WPSS running; vigía + `dmesg -w` + ACM. Logs `build/logs/audio/e7a-20261018-tablet.log`.

## Resultado (MEDIDO) — **PASA, sin oops ni faults**
1. **Recarga de la pila con los módulos nuevos** (`updates/snd-q6apm.ko` 0005+0006 y `updates/q6apm-lpass-dais.ko` 0006): `uke-audio-up.sh --down` **falló** («snd_q6apm in use»: el script no descargaba `q6apm_dai`/`q6apm_lpass_dais`, que ahora cuelgan de q6apm desde que bedais/dais viven en E2d); descarga manual `modprobe -r` y `uke-audio-up.sh --service` ⇒ VERDE (en caliente el primer comando se pierde: `estado = 0 (intento 1)` → `= 1 (intento 2)`, lo cubre el reintento); `snd_q6apm` ya expone `uke_tdm_*`; `dais` en iommu group 10. **Corregido en el repo** (`uke-audio-up.sh --down` descarga ahora las tarjetas/overlays opcionales, `q6apm_dai`, `q6apm_lpass_dais`…; tests 20/0; falta desplegarlo con `boot/deploy.sh --service`).
2. `insmod uke_audio_e7a.ko` → tarjeta `0 [UKE]: sm8650 - UKE` con la topología nueva (PCM MultiMedia1/2 playback, 3/4 capture) y el mezclador **`PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1/2/5`**.
3. `amixer … 'PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1' on` + `aplay -D hw:UKE,0 -f S16_LE -r 48000 -c 2 -t raw /dev/zero` (silencio): `state: RUNNING`, `hw_ptr` **118 559 a 2,5 s → 262 079 a 5,5 s = 47 840 tramas/s ≈ 48 kHz**; DAPM `Primary TDM0 Playback: On … stream active`. **El ADSP aceptó `MODULE_ID_TDM_SINK` + `PARAM_ID_TDM_INTF_CFG` (LPAIF_VA PRIMARY, 4 slots × 32 bit, slot_mask 0x3, sync interna, short-sync-bit, retraso 1 BCLK) + `HW_EP_MF_CFG`** y arrancó el grafo.
4. `aplay` del WAV de −40 dBFS (2 s): **rc 0, 2,70 s**, sin errores, sin faults, ADSP running, Charging.
5. **Sin pines** (e7a): los datos se consumen en el ADSP pero **no salen por ningún pin** y los amplificadores no reciben reloj: no hay sonido ni riesgo para los altavoces.
Estado final: la tarjeta de E7a queda cargada en RAM (se pierde al reiniciar). No se probó su descarga con `rmmod`.

## Qué prueba
La cadena completa **TDM** de AudioReach funciona en el firmware de Xiaomi con la configuración leída del ACDB: grafo TDM, DMA por SMMU y posición. Falta lo físico: **pines**, **driver de los 4 FS19xx**, mapa canal→slot→altavoz y protección.

## Siguiente (decisiones del dueño; cada paso con riesgo pide autorización)
1. **E3c** (una lectura de un pin LPI con votos PRM activos): primer acceso MMIO al LPASS TLMM; requisito de E7b.
2. **E7b** (tarjeta con `pinctrl-0 = uke_tdm1_active`): primeras escrituras MMIO y BCLK/WS/DATA reales hacia los 4 FS19xx **sin driver** (riesgo alto: cuelgue duro; efecto en amplificadores desconocido: usar silencio/−40 dBFS).
3. **Driver FS19xx** (I²C-4 0x34-0x37, `fs19xx.fsm`, reset/IRQ GPIO) y configurarlos como TDM esclavo 4×32 con 1 BCLK de retraso; habilitar `i2c@88c000`. Es el trabajo grande y el que realmente hace sonar el altavoz (+ mezcla estéreo→4 canales con MFC y topes de volumen).
