# MICRÓFONO interno de la uke — investigación (20-oct-2026, solo lectura; nada activado)

Alcance: lectura de las capturas de Android del repo, del DT, de las fuentes del kernel `senemos-ouke6` (7.2.9), de los overlays/topología del audio y de la tablet por RNDIS (`192.168.42.129`; Tailscale daba timeout). En la tablet solo `lsmod`, `ls`, `cat`. No se cargó nada, no se grabó, no se tocó el ADSP.
Estado de la tablet al medir (23:45, uptime 0 min, ouke5): arrancando, `/proc/asound/cards` = «no soundcards», `uke-audio` active y `uke-audio-amps` activating. Módulos presentes (`ls`): `snd-soc-wcd939x{,-sdw}`, `snd-soc-lpass-{tx,va,rx}-macro`, `soundwire-qcom`, `soundwire-bus`, `snd-soc-wcd-{common,classh,mbhc}`, `snd-soc-dmic`; `UKE-tplg*.bin` en `/lib/firmware/qcom/sm8650/`. El árbol `/sys/bus/soundwire` no existe aún (WCD nunca se ha levantado).

## 1. Hardware del micrófono

**Conclusión principal: los micros son ANALÓGICOS (AMIC) en el WCD9395 y entran por SoundWire TX; NO hay DMIC.** (Corrige el supuesto «DMIC digital» de `AUDIO-SENEMOS-20261018.md` filas 15-16 y de `AUDIO-E0-20261018.md:121`.)

Evidencia:
| Dato | Fuente |
|---|---|
| El `odm-mixer_paths_overlay_static.xml` de Xiaomi **sustituye** todas las rutas de micro por rutas AMIC: `handset-mic` → `main-mic` (AMIC3), `handset-dmic-endfire` (grabación estéreo normal) = AMIC1 «sidebottom» + AMIC5 «sidetop», `top-mic` AMIC3, `back-mic` AMIC4, `headset-mic` AMIC2 | `build/android/cosecha-20261017/audio/odm-mixer_paths_overlay_static.xml:151-262` (p. ej. `:241-262`, `:224-240`) |
| Las rutas `dmic*` del `odm-mixer_paths_cliffs_mtp.xml:295-312, 621, 1035-1040` son de la plantilla genérica y las pisa el overlay estático (regla 4 de su cabecera, `:1-9`) | ídem |
| Los 4 nodos `cdc_dmic{01,23,45,67}_pinctrl` están **`status = "disabled"`** en el DT vivo | `build/android/dt-full-uke-android/base/soc/spf_core_platform/cdc_dmic*_pinctrl/status` |
| El driver de la tarjeta de Android da 3× `msm_cdc_pinctrl_get_gpiodata: platform device not found!` justo al registrar la tarjeta (los 3 `qcom,cdc-dmic01/23/45-gpios`, phandles 0x5e0-0x5e2, apuntan a esos nodos desactivados) | `build/android/cosecha-20261017/01-dmesg.txt:8394-8396`, `sistema-ref-20261019/dmesg.txt:1860` |
| gpio6-9 (DMIC01/23 función 1) son TDM1 de los altavoces (función 2) en Android | `vendor-harvest-20261017b/gpio.txt:7-10`; gpio12 = reset del WCD (`gpio.txt:13`), así que DMIC45 tampoco |
| Los nodos `dmic_swr@…` (SWR DMIC) no se instancian; solo se ligan los 2 slaves WCD939x | `build/android/dt-sound-nodes.txt:58-59` |

**Cuántos:** las rutas de Android nombran **AMIC1, AMIC3, AMIC4, AMIC5** (cuerpo) y **AMIC2** (jack/headset USB-C analógico). El nº físico exacto NO está medido (los nombres «sidebottom/sidetop/main/back» son del vendor; `audio_policy_configuration.xml:55-56,287-292` solo declara `Built-In Mic` y `Built-In Back Mic`). Grabación estéreo por defecto = 2 micros (AMIC1+AMIC5); mono = AMIC3. Prueba empírica en M2 (nivel por AMIC).

**Camino:** mic → WCD9395 (ADC1-4, MIC BIAS) → SoundWire TX (master `6d30000`, SPI 496/520, HW 0x2010000; slave `wcd939x-tx-slave` = SDW `e01170223`, DT `va_swr_master`) → TX/VA macro (DEC, `TX SMIC MUX`) → CODEC_DMA → ADSP. Backend de Android para handset/speaker mic: **`CODEC_DMA-LPAIF_RXTX-TX-3`** (`odm-resourcemanager_cliffs_mtp.xml:127-128, 307-308`), 2 canales/48 kHz/16 bit (`:129-133`). Backend de «VA mic» (escucha continua): `CODEC_DMA-LPAIF_VA-TX-0` (`:612-617`), ruta `va-mic-mono-lpi` = AMIC1 por VA (`odm-mixer_paths_overlay_static.xml:712-720`, solo secundario).

**Rutas de mezclador de Android (valores vendor):**
- `main-mic`/`handset-mic` (AMIC3): `TX DEC5 MUX=SWR_MIC`, `TX SMIC MUX5=SWR_MIC8`, `TX_AIF1_CAP Mixer DEC5=1`, `ADC3 MUX=CH3_AMIC3`, `ADC3 ChMap=SWRM_TX3_CH1`, `TX2 MODE=ADC_LP`, `ADC3_MIXER`/`AMIC3_MIXER=1`, `TX_DEC5 Volume=102` (`:224-235`).
- `handset-dmic-endfire` (AMIC1+AMIC5): DEC1/`SMIC MUX1=SWR_MIC4`/`ADC1 MUX=CH1_AMIC1`/`ADC1 ChMap=SWRM_TX2_CH1`/`TX0 MODE=ADC_LP`/`ADC1 Volume=8`; DEC3/`SMIC MUX3=SWR_MIC9`/`ADC4 MUX=CH4_AMIC5`/`ADC4 ChMap=SWRM_TX3_CH2`/`TX3 MODE=ADC_LP` (`:241-262`).
- Defaults de reposo: `ADCn MUX=CHn_AMIC_DISABLE`, `ADC1-4 Volume=6`, `TX_DEC0-4 Volume=84` (`:14-33`).

**Pines / bias / reguladores:**
- Pines LPI: SWR TX = **gpio0 (clk), gpio1, gpio2, gpio14 (datos), función 1** (`dt-full-uke-android/.../lpi_pinctrl@6E80000/tx_swr_*_active/mux`); ya están en `uke_tx_swr_active` del overlay e3 (`dts/uke-audio-e3-lpi.dtso:48-64`). Reset WCD = LPI gpio12 (ya en e3). **No hace falta ningún pin DMIC**, así que desaparece el conflicto con TDM1 (gpio6-9) y con `wcd_reset` (gpio12).
- MIC BIAS: el DAPM del vendor cuelga AMIC1→MIC BIAS1, AMIC2→2, AMIC3→3, AMIC4→3, AMIC5→4 (`qcom,audio-routing` del DT: `sound/qcom,audio-routing`), idéntico al `sm8650-qrd.dts:102-106`. Los 4 micbias = `0xabe` mV = 2750 mV (`wcd939x-codec/qcom,cdc-micbias*-mv`; ya en `uke-audio-e5-codec.dtso`).
- Reguladores: `cdc-vdd-{rx,tx,buck,px}` = `pmxr2230_l7` 1,8 V; `cdc-vdd-mic-bias` = `pmxr2230_bob` (3,296 V; `qcom,cdc-vdd-mic-bias-voltage 3,3 V`). Ya en el e5-codec. **Riesgo**: `l7` también alimenta el usbss del USB-C (`wcd939x_i2c@e`), el camino de RNDIS/SSH (AUDIO-SENEMOS fila 9).
- Macros vendor: tx `6ae0000` (`qcom,is-used-swr-gpio=0`, `tx-dmic-sample-rate=0x249f00`), va `6d44000` (`is-used-swr-gpio=1`, `va-swr-gpios`), rx `6ac0000`.
- No medido: la captura de Android del 19/20-oct fue de reproducción; no hay volcado de pinctrl/clk/regulator con un micro activo (hueco; sería un tercer viaje a Android, no necesario para M0-M2).

## 2. Qué hay en mainline

(Árbol local `build/kernel-pokes/senemos-ouke6/linux-7.2.9`, 7.2.9, medido 20-oct-2026; URL web de git.kernel.org dio 403 desde aquí, citado por ruta de fichero.)
- `sound/soc/codecs/wcd939x.c` + `wcd939x-sdw.c` (SDW id 0x0217/0x10e, `wcd939x-sdw.c:1414`): DAPM `AMIC1-5`, `ADC1-4 MUX` (`CH1_AMIC1…`), `MIC BIAS1-4`, `ADC1-4_OUTPUT` (`wcd939x.c:2574-2578, 2681-2720, 2795-2827`). Micbias por DT `qcom,micbiasN-microvolt` (`wcd-common.c:41`).
- `lpass-tx-macro.c`: `TX DEC0-7 MUX {MSM_DMIC,SWR_MIC,…}` (`:1265`), `TX SMIC MUX0-7 {ZERO,SWR_MIC0..11}` (`:1836-1838`, rutas a `TX SWR_INPUT0-11` `:1892-1920`). `lpass-va-macro.c` análogo (DMIC por VA, no necesario).
- `sound/soc/qcom/sc8280xp.c:178` `qcom,sm8650-sndcard`; `TX_CODEC_DMA_TX_0..3` tratados (`sc8280xp.c:85-88`, `common.c:218-221`); `q6dsp-lpass-ports.c:664` define el DAI `TX_CODEC_DMA_TX_3`.
- DT de referencia: `sm8650-qrd.dts:128-136` (enlace «WCD Capture»: `q6apmbedai TX_CODEC_DMA_TX_3` + `wcd939x 1` + `swr2 0` + `lpass_txmacro 0`), `:102-106` (rutas AMIC/MIC BIAS), `:1206-1210` (`qcom,tx-port-mapping = <2 2 3 4>`), `sm8650.dtsi:4764-4795` (`swr2`). `sm8650-hdk.dts:167-169,190-198` usa AMIC1/2/5. Es **idéntico a lo que ya tiene `uke-audio-e5-card.dtso`/`e5-codec.dtso`**.
- Topología AudioReach: `SM8550-HDK.m4` upstream trae captura MultiMedia3/4 + `TX_CODEC_DMA_TX_3` y `VA_CODEC_DMA_TX_0`; nuestra `UKE-tplg.bin` (de `UKE.m4:59-64, 99-111, 131-136`) **ya las contiene** (`topology/out/UKE.conf:942, 2455, 2523`; mixer `MultiMedia3 Mixer TX_CODEC_DMA_TX_3`).
- UCM (alsa-ucm-conf 1.2.16.1 instalado en la tablet, `/usr/share/alsa/ucm2/Qualcomm/sm8650/QRD/HiFi.conf`; también en GitHub, consultado 20-oct-2026): `SM8650-QRD` define Mic1 (AMIC1 «Bottom»), Headset (AMIC2) y Mic2 (AMIC4 «Back») con `CapturePCM hw:${CardId},2`; secuencias en `codecs/wcd939x/AnalogMic{1,3,4,5}EnableSeq.conf` y `codecs/qcom-lpass/tx-macro/SoundwireMic0EnableSeq.conf` (`TX DEC0 MUX=SWR_MIC`, `TX SMIC MUX0=SWR_MIC0`, `TX_AIF1_CAP Mixer DEC0=1`, `TX_DEC0 Volume=100`; `ADCn_MIXER`, `ADC1 MUX`, `ADC1 Volume 10`, `TX0 MODE ADC_ULP`). `conf.d/sm8650/SM8650-QRD.conf` enlaza por nombre de tarjeta; la nuestra se llama `UKE` ⇒ **hace falta UCM propio** (`conf.d/sm8650/UKE.conf` no existe).
- Diferencia de numeración a vigilar: Android usa `SWR_MIC4/5/8/9` y `ADCn ChMap SWRM_TXp_CHc`; QRD usa `SWR_MIC0`+`ADC1`. El vendor compone el índice como (puerto-1)·4+(canal-1) (TX2_CH1→4, TX2_CH2→5, TX3_CH1→8, TX3_CH2→9); en mainline el mapa lo da `qcom,tx-port-mapping`. **No resoluble en el PC**; en M2 se barren los `SWR_MIC0..11`.

## 3. Qué falta en NUESTRA cadena

Lo que ya está listo (PC): overlays `e5-codec` (macros, swr1/swr2, WCD9395, micbias 2750, supplies) y `e5-card`; pines SWR/reset en e3; subgrafos y PCM de captura en la topología; módulos `.ko` del kernel; reloj/votos PRM de `e2d`/`e3`.
Lo que falta:
1. **Overlay de tarjeta combinada.** La tarjeta de altavoces (`e8b`, modelo `UKE`) solo tiene el enlace TDM; `e5-card` es otra tarjeta con el mismo nombre (solo una a la vez). Falta un `e9a-card-fs19xx-wcd-capture.dtso` = e8b + `wcd-capture-dai-link` (+ `audio-routing` AMIC/MIC BIAS/`TX SWR_INPUT*`). Sin enlace de reproducción WCD (no hace falta, menos riesgo).
2. **Cargar `e5-codec` en caliente** (un módulo cargador `uke_audio_e5.ko` como los e3/e8b; no existe). Es la etapa de más riesgo del plan original (`uke-audio-e5-codec.dtso:3-8`): sondeo de macros (MMIO LPASS) sin relojes ⇒ cuelgue; reset del WCD por LPI gpio12; comparte `l7` con el usbss. Desventaja: el probe del WCD9395 también registra RX/mbhc; sin `mode-switch` no toca el USB.
3. **Módulos** a cargar: `snd-soc-wcd-common/classh/mbhc`, `snd-soc-wcd939x{,-sdw}`, `snd-soc-lpass-{tx,va,rx}-macro` (+`lpass-macro-common`), `soundwire-bus/qcom`. Ya instalados (vistos con `ls`); falta verificar dependencias con `modprobe -n`.
4. **Mezclador**: ruta mínima (valores de la QRD; los del vendor como alternativa): `MultiMedia3 Mixer TX_CODEC_DMA_TX_3 on`, `TX DEC0 MUX SWR_MIC`, `TX SMIC MUX0 SWR_MICx`, `TX_AIF1_CAP Mixer DEC0 on`, `TX_DEC0 Volume ~100`, `ADC1_MIXER on`, `ADC1 MUX CH1_AMICn`, `ADC1 Switch on`, `ADC1 Volume 10`, `TX0 MODE ADC_ULP`. MICBIAS lo activa el DAPM al abrir el PCM.
5. **UCM** `conf.d/sm8650/UKE.conf` + `Qualcomm/uke/HiFi.conf` (copia de QRD con Speaker TDM/FS19xx, Mic AMIC3/AMIC1+5) y, para PipeWire, una entrada `uke-mic` (ALSA `hw:UKE,2`) o `api.alsa.path`. Hoy PipeWire usa un sumidero propio (`51-uke-speakers.conf`), así que lo más simple es un `51-uke-mic.conf` análogo.
6. **Incógnitas del ADSP de Xiaomi** (lo que puede romper): (a) la topología TX_CODEC_DMA nunca se ha probado en este ADSP (solo TDM); los parámetros del módulo CODEC_DMA_SOURCE (`LPAIF_INTF_TYPE_RXTX`, `CODEC_INTF_IDX_TX3`, IIDs 0x4009/0x6090) vienen del HDK, no del ACDB `Forte` (que es legible: sección `SGIT`; se podría extraer el subgrafo `DeviceTX_Handset…` como se hizo con el TDM en `AUDIO-ACDB-20261018.md`); (b) votos de reloj `LPASS_CLK_ID_TX_CORE_MCLK`/`RX_CORE_TX_MCLK` y `fsgen` del VA (el vendor tiene `qcom,va-clk-mux-select`); (c) `q6apm_lpass_dais` con IOMMU/SID del LPASS ya admitido (0002) pero cubierto solo para TDM; (d) SWRM HW 2.1.0 vs compat `v2.0.0`.

Reutilizable del camino de los altavoces: toda la pila ADSP/GPR/APM/PRM (`uke-audio.service`), parches q6apm 0005-0008, `e3` (LPI y SWR TX), `e2d`, módulo cargador genérico `uke-ovl.h`, esquema de vigía/doble captura, guardias `uke-bootguard`, servicio de cargas escalonadas (`uke-audio-amps.service`) y la configuración de PipeWire.

## 4. Plan por etapas

| Etapa | Qué | Hecho cuando | Riesgo | Autorización |
|---|---|---|---|---|
| **M0** (solo PC) | Escribir `e9a` (e8b + WCD Capture + routing), cargador `uke_audio_e5.ko` (aplica `e5-codec` y luego `e9a`), UCM `UKE`, script de mezclador; `build.sh` verde (`dtc`, `fdtoverlay`, `check-overlays.py`, `modprobe -n`). Opcional: extraer del ACDB `Forte` el subgrafo `DeviceTX_Handset` y comparar con los params del HDK | build verde, tabla de sha en MANIFEST | nulo | ninguna |
| **M1** (en la tablet, riesgo medio-alto) | Con la tarjeta de altavoces YA arriba: cargar `e5-codec` y verificar solo que **WCD9395 enumera por SoundWire**: `/sys/bus/soundwire/devices` con `sdw:…0217:010e…` ×2 (unique-id 3 y 4), dmesg sin SMMU/oops, ADSP `running`, SSH por RNDIS intacto | `ls /sys/bus/soundwire/devices` con RX y TX; `dmesg` limpio 5 min; sin card nueva | cuelgue por MMIO/relojes (regla 3/AGENTS), usbss/`l7`, reset LPI12; sin recuperación automática | **orden expresa del dueño**; vigía + doble captura + ACM un lector, `dmesg -n 7`, `sync`, cargador de pared, ≥3700 mV |
| **M2** | Cambiar a la tarjeta `e9a` (descargar la de altavoces: solo una `UKE`) y listar `arecord -l`/`amixer controls` con los mandos `TX SMIC MUX`, `ADCn`, `MIC BIAS` y el PCM de captura; **sin grabar** | `arecord -l` muestra `MultiMedia3 Capture`; `amixer` (solo lectura) lista los controles | medio: el grafo de captura se crea al abrir el PCM, no al cargar | dueño (mismo paquete que M1) |
| **M3 — primer hito realista** | Captura cruda 48 kHz S16 2-4 s con `arecord -D hw:UKE,2` (mezclador de §3.4; barrer `SWR_MIC0..11`/`ADC1..4`/`AMIC1,3,4,5`, que el dueño golpee/hable) y `sox stat`/RMS: **no es silencio** (RMS > −70 dBFS y cambia al hablar) | WAV con señal; qué AMIC/ruta da señal; anotar contraste con la tabla de Android | medio: primera vez que el ADSP abre CODEC_DMA TX3; si el SPF rechaza el grafo, puede tirar el ADSP (como S24) | dueño; ledger; vigía; arrancar con volumen de altavoces apagado/amps parados |
| **M4** | Mapa de micros (cuántos hay, posición), ganancia (`TX_DEC Volume`, `ADCn Volume`), ruido, estéreo AMIC1+5; elegir ruta por defecto | tabla de nivel por mic, WAV de 3 s con voz limpia | bajo | dueño |
| **M5** | UCM `UKE` + `51-uke-mic.conf` de PipeWire (`pw-record`), servicio persistente (`uke-audio-mic.service` tras `uke-audio-amps`) con `nofail`; micro y altavoz a la vez (dúplex, eco) | `wpctl status` muestra fuente; `pw-record` OK tras arranque en frío | medio (carrera de arranque, ya vista con el audio) | dueño |
| **M6** | Aguante: 15 min de captura continua, suspensión/reanudación, convivencia con BT y lápiz; documentar en `NOTAS` y `ESTADO-VIVO` | sin xruns/oops, resume OK | bajo-medio | dueño |

Mitigaciones generales: respetar las reglas del proyecto (doble captura, `dmesg -n 7`, `sync` antes de reiniciar, ≤2 escrituras/día; ninguna etapa M1-M3 flashea nada). Si el WCD arruina SSH por RNDIS, el USB queda sin USB2 hasta reiniciar.

## 5. Confianza y huecos
- ALTA (medido/leído): micros analógicos por WCD9395 TX (rutas Xiaomi, DMIC pinctrl desactivados, error de plataforma 0x3 en Android), backend `RXTX-TX-3`, pines SWR, MIC BIAS/reguladores, mainline y topología ya cubren el enlace.
- MEDIA (inferido): que el SPF de Xiaomi acepte el grafo CODEC_DMA del HDK; correspondencia `SWR_MIC` vendor↔mainline.
- SIN MEDIR: nº físico de micros; estado eléctrico del WCD/pines con un micro activo en Android (no hay captura de grabación en el repo).
- Medidas web con fecha 20-oct-2026: alsa-ucm-conf `ucm2/Qualcomm/sm8650/QRD/HiFi.conf` (GitHub); git.kernel.org devolvió 403, por eso las citas del kernel son al árbol local 7.2.9.
