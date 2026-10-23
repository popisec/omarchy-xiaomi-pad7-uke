# AUDIO — E8 diagnóstico 3: el nivel descartado; el reloj llega; ¿qué falla en datos/slot/config del amp? — 19-oct-2026

**No se tocó la tablet en esta etapa.** Estado medido: los 4 FS19xx están habilitados, ven el BCLK (D4-1) y el volumen/estado se comportan, pero **no suena nada ni a −18 dBFS con vol 0xF3 ni con 4 canales** (el dueño escuchó cada escalón).

## Lo que se sabe del ACDB (Android) frente a lo que enviamos (MEDIDO en el PC, `Forte_acdb_cal.acdb`)
| Parámetro del `TDM_SINK` | ACDB (Android) | Nosotros |
|---|---|---|
| `TDM_INTF_CFG` | LPAIF_VA, PRIMARY, interna, data_oe 1, slot_mask 0xF, 4 slots × 32 bit, short-sync-bit, sin invertir, retraso 1 | **igual**, salvo `slot_mask` = (1<<canales)−1 (0x3 con 2 canales, 0xF con 4) |
| `HW_EP_MF_CFG` | 48 kHz, **bit_width 32**, 4 canales, punto fijo | 48 kHz, **bit_width = el del PCM (16 con S16_LE)**, canales del PCM |
| `TDM_LANE_CFG` | «1 carril por defecto» (opcional con un solo carril) | no se envía (= el mismo valor por defecto) |
| `HW_INTF_CLK_CFG` | (clock_id/freq/attr por defecto en la ruta del speaker; no localizado un bloque propio) | no se envía |
| Cadena previa al sumidero | módulos `0x07001015` y `0x07001010` (no públicos; `0x07001015` probablemente MFC) y un bloque de 56 B con un mapa de canales `{L=1,R=2,8,9}` | solo `LOG → TDM_SINK` |
Conclusión: **los parámetros de la interfaz coinciden**; las diferencias están en (a) el **ancho de bit del dato** (Android 32, nosotros 16 con S16), (b) los **módulos de conversión/mapa de canales** previos al sumidero, (c) lo que no se ve desde Linux (cableado de línea de datos, configuración interna del amp).

## Experimentos preparados (PC), de menor a mayor coste
1. **Dato de 32 bit (como Android):** reproducir un WAV **S32_LE** (el DAI del códec ya acepta S32). Cambia `bit_width` a 32 en el sumidero. Coste: un WAV nuevo y `aplay`; sin cambios de módulos. *Es el candidato más barato.*
2. **Barrido de formato TDM** (`fs19xx/sweep-tdm.sh`): retraso {0,1,2} × sincronismo {short-bit, long, short-slot} × inversión {0,1} = 18 combinaciones, 2 s de tono a −18 dBFS cada una con los amps habilitados; imprime `[n] delay=d sync=s inv=i` antes de cada tono y los registros 00/0A/0C/19 del amp 0x34 a mitad (por si algún registro cambia con un formato correcto aunque no se oiga). El dueño cuenta los tonos y dice en cuál oye algo. **Requiere** el `snd-q6apm` con los parámetros `uke_tdm_*` en 0644 (el parche 0006 ya los pone así; `out/snd-q6apm-uke.ko` reconstruido; el módulo instalado hoy los tiene en 0444). Para cargarlo hay que reiniciar la tablet (el módulo `updates/` entra solo en el arranque) o recargar la pila completa.
3. **Cadena como Android**: añadir MFC (2→4 canales con mapa {1,2,8,9}) y el módulo `0x07001010` al subgrafo de la topología. Más trabajo y sin documentación pública del `0x07001010`.
4. **Comparar registros del amp con tono y con silencio** (barato, solo lectura): ¿cambia algún registro de «señal presente» al llevar datos? (`diag-noclk.sh` adaptado). Si no cambia ninguno, el amp **no está decodificando datos** (formato/slot/línea); si cambia, el amp recibe datos y el fallo es de salida (boost/OCP/mute interno).

## Propuesta de orden
**(1) S32_LE** → **(4) tono vs silencio** → **(2) barrido** (con reinicio y coordinación con la sesión BT) → (3).
Seguridad: mismo nivel que ya probado (tono −18 dBFS, vol 0xF3, ≤ 2 s por prueba, amps con los límites de siempre); el barrido repite la apertura de PCM 18 veces (≈ 1,3 min).

## Añadido: ficheros listos para los experimentos 1 y 4
`e4c/make-wav-level.sh NIVEL OUT.wav [16|32]` (ahora con S32_LE); WAV `uke-1k-m18-s32.wav` (1 kHz, −18 dBFS, S32_LE) generado en el PC y `fs19xx/diag-signal.sh` (A/B silencio vs tono; admite el WAV S32). Ambos se copian a la tablet con una petición propia.

## D5 EJECUTADO (MEDIDO, 00:13 y 09:29 del 19-oct): A/B tono vs silencio inconcluyente; el test S32 no era posible con la topología actual
- WAV S32 copiado a la tablet. `diag-signal.sh` con el WAV S16 (−18 dBFS, vol 0xF3, amps habilitados, solo lectura): **entre silencio y tono solo cambian ±1 unidad del registro `0x01`** en dos amps (0x34: 0x012c→0x012b; 0x37: 0x012e→0x012d), un registro que ya fluctuaba entre lecturas sin tono (0x0126-0x012c): **no hay evidencia de que los amps vean el dato** ni de lo contrario (no hay ningún registro «señal presente» evidente).
- El mismo script con el WAV **S32_LE falló**: `aplay: set_params: Sample format non available — Available formats: S16_LE`. La topología actual solo ofrece S16_LE (MultiMedia1 y el backend TDM); el segundo volcado quedó con los amps parados. Sin daño: 0 oops, `uke_fs_play` en `N`.
- (Entre medias la tablet dejó de contestar por SSH unos minutos y volvió sin reiniciar: uptime 12 h al volver.)
## Preparado para el test de dato de 32 bit
`UKE.m4` con `UKE_FMT` (defecto S16_LE; el `UKE-tplg.bin` normal sigue `c3ff8ed1…`) y `build.sh` genera `firmware/qcom/sm8650/UKE-tplg-s32.bin` (MultiMedia1 en S32_LE). `fs19xx/deploy-s32.sh` copia solo ese fichero. Procedimiento: copia (ya hecha la de seguridad `UKE-tplg.orig.bin`), sustituir `UKE-tplg.bin` por la S32, `rmmod/insmod uke_audio_e8b` (≈15 s de timeouts del APM), `uke_fs_play=1`, vol 0xF3, `aplay` del WAV S32 (−18 dBFS, 2 s; el dueño escucha a 20-30 cm), `uke_fs_play=N`, restaurar la topología original y recargar e8b.

## D6 EJECUTADO (MEDIDO, 09:54): el test S32 no es posible — el frontend `q6apm-dai` solo ofrece S16/S24
`deploy-s32.sh --go`, `UKE-tplg.bin` ← S32, `rmmod/insmod uke_audio_e8b`: la tarjeta sondea, pero `aplay -f S32_LE` da **`audio open error: Invalid argument`**: la intersección entre el PCM de la topología (S32_LE) y las capacidades del frontend (`q6apm-dai.c`: `S16_LE | S24_LE`) es vacía. Restaurada la topología original (`UKE-tplg.bin` = `c3ff8ed1…`, verificado), e8b recargada, el PCM vuelve a ofrecer solo S16_LE; `uke_fs_play=N`, 0 oops. **No se reprodujo ningún sonido** (no hubo ni amps habilitados).
## Preparado: variante S24_LE (dato de 24 bit en contenedor de 32; el HW_EP_MF_CFG enviará bit_width 24 en vez de 16)
`UKE-tplg-s24.bin` (sha `2e72b8ca…`; la normal sigue `c3ff8ed1…`), `uke-1k-m18-s24.raw` (1 kHz, −18 dBFS, S24_LE en contenedor de 32 bit, 2 s; se reproduce con `aplay -t raw -f S24_LE -r 48000 -c 2`) y `V=s24 fs19xx/deploy-s32.sh --go`. Mismo procedimiento que el del S32 (sustituir, recargar e8b, `uke_fs_play=1`, vol 0xF3, 2 s, escucha a 20-30 cm, restaurar).

## D7 EJECUTADO (09:56) — **CAÍDA DEL ADSP al arrancar el stream S24_LE** (no hubo sonido)
`V=s24 deploy-s32.sh --go`, raw S24 copiado, `UKE-tplg.bin` ← S24 (original verificada `c3ff8ed1…` antes), e8b recargada (la tarjeta sondea). Al abrir el PCM `aplay -t raw -f S24_LE … /dev/zero` (**con `uke_fs_play=N`: los amps no se tocaron**): el ADSP reportó
`PDM: service 'audio_process' crash: EX:audio_process:0x2:GC_4001:0x68eb:PC=0xb051f4d8:LR=0xb05219e4` → `qcom_q6v5_pas: fatal error received: err_qdi.c:1204:EX:audio_process…` → `remoteproc1: crash detected in adsp: type fatal error` (recovery deshabilitado ⇒ queda en `crashed`) → `bedais: Failed to start APM port 24` / `ASoC error (-110) at soc_dai_trigger() on PRIMARY_TDM_RX_0` → `glink-edge: intent request timed out` ×N. Consecuencias medidas: `remoteproc1 adsp = crashed`, `battmgr` ilegible (Connection timed out, depende del ADSP), vigía con ALARMA; WPSS sigue `running`. El cargador no depende del ADSP, pero la lectura de batería sí.
**Hipótesis:** el sumidero TDM del ADSP revienta con `bit_width = 24` (Q27) con esta configuración (formato de entrada/salida inconsistente entre el grafo del stream y el módulo, o falta de conversión de formato como la cadena MFC/0x07001010 de Android). Es un hallazgo útil: **el ancho de dato SÍ importa** para el `audio_process` del ADSP.
Acciones tomadas: solo restaurar el fichero `UKE-tplg.bin` original (sha `c3ff8ed1…`). **No se ha tocado el ADSP** (stop/start o reinicio pendientes de autorización del dueño).

## D7b — recuperación del ADSP (09:58): vuelve, pero con un **Oops** en el reinicio
`echo stop` → `offline`, `echo start` → `running` en pocos segundos; `battmgr` vuelve a leerse (`Charging`), `uke-audio`/`uke-wifi` `active` (estado del servicio, sin re-ejecutar), `wlan0` sigue DOWN (ya lo estaba desde ayer, ajeno).
**Pero** durante el arranque del ADSP: `Unable to handle kernel NULL pointer dereference at virtual address 0` en `gpr_send_pkt+0x34 [apr]` ← `audioreach_send_cmd_sync [snd_q6apm]` ← `q6apm_is_adsp_ready` desde `pdr_indack_wq` (kworker `pdr_indack_work`): el PDR notificó `audio_pd` UP y `q6apm` intentó enviar un comando por un canal GPR que el reinicio había dejado a NULL (`gdev->ch`). **Kernel tainted (Oops [#1])**; el sistema sigue vivo (SSH, carga), pero la cola `pdr_indack_wq` y el estado de `q6apm`/`apr` no son de fiar y, según la regla del proyecto, **no se usa `rmmod` de los módulos de audio tras un oops: reiniciar**.
Hallazgo para el diseño: `q6apm_is_adsp_ready()` no tolera un reinicio del ADSP con la pila cargada (fallo conocido de mainline con `qcom,gpr` + PDR; en las demás etapas el stop/start se hizo con la pila descargada).

## D8 — reinicio tras el Oops (10:00): tablet limpia
`sync` + `systemctl reboot` (avisada la sesión BT). Tras volver (≈2 min): `uke-audio`, `uke-bt`, `uke-wifi`, `uke-carga` `active` (uke-audio y uke-bt «ok» en bootguard), ADSP `running`, battmgr `Charging`, **0 oops en el arranque**, `UKE-tplg.bin` = original (`c3ff8ed1…`), **sin módulos de prueba cargados** (solo `uke_audio_e2d`, `uke_bt_b`, `uke_tapa`). `wlan0` sigue DOWN (ajeno a audio, desde ayer).
## Estado y siguiente
- Lo medido hasta hoy: los 4 FS19xx contestan por I²C y se habilitan; ven el BCLK (A/B de registros); el nivel (hasta −18 dBFS a vol 0xF3) y 4 canales a −40 dBFS no dan sonido; el A/B tono-vs-silencio es inconcluyente; **S24 hace caer el `audio_process` del ADSP** (S32 ni se abre).
- Pendiente (con autorización): (a) desplegar el `snd-q6apm` con `uke_tdm_*` en 0644 y hacer el **barrido de formato TDM** (`fs19xx/sweep-tdm.sh`, 18 combinaciones); (b) investigar por qué S24 revienta el ADSP (formato de entrada del `TDM_SINK`); (c) la cadena previa de Android (MFC + `0x07001010`).

## D9 EJECUTADO (10:20): barrido de formato TDM (18 combinaciones) — **ningún tono**
`e7/deploy.sh --go` (snd-q6apm con `uke_tdm_*` 0644), reinicio coordinado con la sesión BT, carga e7i2c → e3 + driver LPI → e8b (uke-bt falló en ese arranque: asunto de la sesión BT), `sweep-tdm.sh`: delay {1,0,2} × sync {0,1,2} × inv {0,1}, tono −18 dBFS, vol 0xF3, 2 s cada una. Los registros 00/0A/0C del amp 0x34 salieron **idénticos en las 18** (`0040/0050/0069`) y **el dueño no oyó ningún tono**. Sin errores, 0 oops, ADSP running, parámetros restaurados (`delay=1 sync=0 inv=0`, `uke_fs_play=N`). Log: `build/logs/audio/e9-sweep-20261019.txt` (ignorado).
Lectura: el formato TDM no es la causa (o no se aplica por stream): ni cambiando el modo cambia el estado del amp.
## Siguiente hipótesis (preparada en el PC): la línea de datos
`kernel/0007-q6apm-tdm-lane-cfg.patch` (parámetro `uke_tdm_lane`, 0644, defecto 0 = no cambia nada): envía además `PARAM_ID_TDM_LANE_CFG` (0x0800106A) con `lane_mask` 1/2/3. Hoy el sumidero TDM usa la línea por defecto (lane 1 = SD0 = gpio8); si los amplificadores cuelgan de **SD1 (gpio9)** o de ambas, no reciben datos. `fs19xx/sweep-lane.sh` prueba lane 1, 2 y 3 (tono −18 dBFS, 2 s cada una). `out/snd-q6apm-uke.ko` reconstruido con 0005+0006+0007 (sha en `out/`). Requiere desplegar (`e7/deploy.sh --go`) y reiniciar.
