# AUDIO — E4c preparado en el PC: tarjeta mínima y primera DMA del LPASS (sin tocar la tablet) — 18-oct-2026

Orden del dueño: preparar E4c (tarjeta mínima con MultiMedia1 hacia PRIMARY_MI2S_RX y códec ficticio, topología UKE-tplg.bin, procedimiento), con informe de riesgos y reversa. **No se tocó la tablet.**

## Diseño (lectura de `qcom_snd_parse_of`, `sc8280xp.c`, `topology.c`; VERIFICADO-PC lo compilable)
- **Frontends**: no se declaran en el DT; los crea la topología (`UKE-tplg.bin` lleva `SectionPCM "MultiMedia1 Playback"`…). **Backend**: un solo dai-link `PRIMARY_MI2S_RX` (cpu = `bedais`, platform = `q6apm` service@3) con un **códec ficticio `linux,spdif-dit`** (`snd-soc-spdif-tx`, presente en ouke4): sin `codec` el parser de Qualcomm lo trataría como frontend (`common.c:147`).
- Overlay `dts/uke-audio-e4c-card.dtso` → `out/uke-audio-e4c-card.dtbo` (sha `0c6b247d…`), cargador `out/uke_audio_e4c.ko` (sha `8f7f169e…`, vermagic ouke4). `build.sh`: `dtc -@` sin avisos; `fdtoverlay e2d+e4a+e4b+e4c` aplica; `/sound model = UKE`, `/spdif-dit`, un único dai-link. Es **alternativa** a `e5-card` (mismo modelo `UKE`: no cargar las dos).
- Topología: `firmware/qcom/sm8650/UKE-tplg.bin` (28 828 B, ya generada en E0; fuentes BSD, no es firmware de Qualcomm) con `MultiMedia1 Playback` → `PRIMARY_MI2S_RX Audio Mixer` → `Primary MI2S Playback` → `device16.i2s_rx1`. Nombre pedido por el kernel: `qcom/sm8650/UKE-tplg.bin` (driver `sm8650` + `model = "UKE"`).
- **Por qué PRIMARY_MI2S_RX**: el DT vendor no tiene pinctrl de MI2S primario (solo `quin_mi2s_pinctrl` = TDM1 de los amplificadores y `fm_i2s1`): esa interfaz LPAIF no tiene pines ⇒ el ADSP consume los datos por DMA pero no salen por ningún pin (INFERIDO).
- `e4c/make-wav.sh` genera el WAV de prueba (2 s, 48 kHz estéreo S16, seno 1 kHz a **−40 dBFS**); `e4c/deploy.sh` instala **solo ficheros** (topología, `.ko`, WAV; `--check`, `--revert`; sin `--go` solo verifica en el PC y no abre conexión).

## Procedimiento propuesto (NADA ejecutado; cada paso con riesgo pide autorización)
Gate: ≥3700 mV, Charging, ADSP/WPSS running, vigía + `dmesg -w` a fichero + ACM, tablet en ouke4 con E2d cargado.
1. **Ficheros** (sin riesgo para el ADSP): `e4c/deploy.sh --go`; `pacman -S alsa-utils` en la tablet (hoy **no hay `aplay`**; escribe en el rootfs).
2. `insmod uke_audio_e4a.ko`, `insmod uke_audio_e4b.ko` (como E4a/E4b: medido OK).
3. `insmod uke_audio_e4c.ko` → crea `spdif-dit` y `sound`; se autocargan `snd_soc_sc8280xp`/`snd_soc_spdif_tx`; el kernel pide la topología y registra la tarjeta. Riesgo **medio**: parser de topología (nada medido), componentes ASoC; **todavía sin comandos de grafo al ADSP**. Éxito: `/proc/asound/cards` con `UKE` y `aplay -l` con un PCM MultiMedia1; sin errores de topología.
4. **Primera DMA**: `aplay -D hw:UKE,<n> /root/uke-1k-40dbfs.wav` (2 s). Riesgo **alto**: `APM_CMD_GRAPH_OPEN`, `SHARED_MEM_MAP_REGIONS` con `dma_addr | (0x1001 << 32)` (dirección por el cliente SMMU de E4b), `GRAPH_START`, y el LPAIF leyendo nuestros búferes. Posibles resultados:
   - **Éxito**: `aplay` termina sin error; sin `arm-smmu … fault`; ADSP running.
   - **`CMD timeout` en GRAPH_OPEN** (probable si el firmware no enruta las respuestas a los **puertos GPR dinámicos** ≥0x10000000 de `gpr_alloc_port`, como pasó con el puerto 1): inocuo, `aplay` falla a los 5 s. Contingencia ya prevista: recompilar `apr.ko` con el rango dinámico en puertos que el firmware acepte (parámetro de módulo), igual que se hizo con q6apm.
   - **`Unhandled context fault`/ADSP `crashed`**: la DMA falló (SID/IOVA): stop/start del ADSP (E2', ~2 s); si no vuelve, reset físico (`recovery=disabled`).
5. **Reversa** (orden): parar `aplay`; `rmmod uke_audio_e4c` (la tarjeta se desregistra), `rmmod snd_soc_sc8280xp snd_soc_spdif_tx` si siguen; `rmmod uke_audio_e4b q6apm_dai`, `uke_audio_e4a q6apm_lpass_dais`; si el ADSP se degradó: stop/start. Ficheros: `e4c/deploy.sh --revert`.

## Qué NO se comprobó en el PC
Que el parser de topología del kernel (`topology.c`) acepte `UKE-tplg.bin` y que el ADSP acepte el grafo; que `spdif-dit` enlace el backend (INFERIDO por `snd_soc_dapm_link_dai_widgets`); y todo lo que dependa del firmware (puertos dinámicos, DMA por SID).
## Recomendación
Hacer 1-3 (riesgo medio) y revisar el dmesg antes de **4**; el paso 4 solo con autorización expresa. Sin TDM ni FS19xx (E7) no hay sonido audible aunque E4c funcione: E4c solo valida la tubería DMA.
