# AUDIO — cadena de Android antes del TDM_SINK (MFC → SAL → LOG → TDM_SINK, 32 bit, 4 canales {1,2,8,9}) preparada en el PC — 19-oct-2026

**No se tocó la tablet.** Motivo: el subgrafo del altavoz del ACDB de Android es `MFC (0x07001015) → SAL (0x07001010) → SPLITTER → LOG → TDM_SINK` con `HW_EP_MF_CFG` de **32 bit / 4 canales** y un mapa de canales `{1,2,8,9}`; nosotros solo `LOG → TDM_SINK` con el ancho del PCM (16 bit, 2 canales). El S24 reventó el `audio_process` del ADSP, lo que indica que el sumidero es sensible al formato de entrada.

## Qué hay (compilado y verificado en el PC; el build normal no cambia: `UKE-tplg.bin` sigue `c3ff8ed1…`)
| Pieza | Qué es |
|---|---|
| `topology/uke/module_sal.m4`, `topology/uke/subgraph-device-tdm-playback-chain.m4`, `UKE.m4` (`UKE_CHAIN`) | Subgrafo de dispositivo TDM con **MFC → SAL → LOG → TDM_SINK** (sin el SPLITTER, que en Android alimenta el camino de retorno V/I). `build.sh` genera `firmware/qcom/sm8650/UKE-tplg-chain.bin` (sha `f848f629…`, redecodifica con `alsatplg -d` y trae los widgets `device24.mfc1/sal1`) |
| `kernel/0008-q6apm-tdm-chain-format.patch` → `out/snd-q6apm-uke.ko` | Parámetros `uke_tdm_chain_bits` (32) y `uke_tdm_chain_chan` (4), **0644, defecto 0 = sin cambios**. Solo para los módulos MFC/SAL/TDM_SINK de un subgrafo de dispositivo de reproducción (dirección TX): fuerzan 32 bit y 4 canales con mapa `{1,2,8,9}`; el kernel ya sabía configurar MFC (`PARAM_ID_MFC_OUTPUT_MEDIA_FORMAT`) y SAL (`PARAM_ID_SAL_OUTPUT_CFG` = ancho de bit). El PCM sigue siendo 2 canales S16, como en Android (el MFC hace el ensanche 2→4 y el SAL pasa a 32 bit). El `slot_mask` del TDM sale 0xF con 4 canales (= ACDB) |
| `fs19xx/test-chain.sh ETAPA` | Etapas **a** (cadena con parámetros a 0, amps sin tocar), **b** (+32 bit), **c** (+4 canales), **d** (= c con amps habilitados, vol 0xF3 y tono −18 dBFS 2 s para escuchar). Cada una restaura parámetros y `uke_fs_play=N` y muestra si el ADSP cae |
| `V=chain fs19xx/deploy-s32.sh --go` | Copia solo `UKE-tplg-chain.bin` junto a la normal |

## Procedimiento propuesto (con autorización; vigía + doble captura; ACM un lector)
1. `e7/deploy.sh --go` (snd-q6apm con 0008) y `V=chain deploy-s32.sh --go` (solo ficheros), **reiniciar** (coordinado con la sesión BT: el `.ko` entra en el arranque), cargar e7i2c → e3 + driver → e8b **con la topología normal** y comprobar que todo está como hoy.
2. Sustituir `UKE-tplg.bin` por la de cadena (la original queda en `UKE-tplg.orig.bin`), `rmmod/insmod uke_audio_e8b`.
3. **Etapas a → b → c SIN amps** (`uke_fs_play=N`): solo verifican que el ADSP acepta el grafo; **parar al primer fallo** (ADSP caído ⇒ no usar stop/start con la pila cargada: reiniciar).
4. Etapa **d** (amps ON, tono −18 dBFS, 2 s): el dueño escucha a 20-30 cm.
**Reversa:** restaurar `UKE-tplg.bin` desde `UKE-tplg.orig.bin` y recargar e8b (o reiniciar); parámetros a 0 (por defecto en cada arranque).

## Riesgos
| # | Riesgo | Prob./impacto | Mitigación |
|---|---|---|---|
| 1 | El ADSP vuelve a caer (`audio_process` fatal) si el grafo MFC/SAL/32 bit es inconsistente con el flujo de formato de la etapa de stream (ya pasó con S24) | media / medio (reinicio; sin daño físico) | etapas a→b→c **sin amps**, una por vez; recovery desactivado: se reinicia, nunca stop/start con la pila cargada (Oops medido el 19-oct) |
| 2 | El SAL tiene un limitador (`audioreach_sal_limiter_enable`): puede cambiar el nivel | baja / bajo | tono −18 dBFS, vol 0xF3 |
| 3 | La topología de cadena no sondea la tarjeta | media / bajo | se restaura el fichero original y se recarga e8b |
| 4 | Mapa `{1,2,8,9}` y sin SPLITTER no equivalen exactamente a Android (el 0x4961 SPLITTER alimenta el retorno V/I) | media / bajo | es el primer intento; el SPLITTER se puede añadir después |
| 5 | Niveles en amps: con MFC ensanchando a 4 canales, los altavoces pasan a recibir señal en slots 0-3 | baja / bajo | tono −18 dBFS, 2 s, vol 0xF3 (ya probado en 2 slots) |

## Etapas a, b y c EJECUTADAS (MEDIDO, 10:19-10:20 del 19-oct) — el ADSP acepta la cadena de Android; sin amps
`e7/deploy.sh --go` (snd-q6apm con 0005-0008, sha `7ee7a7dd…`), `V=chain deploy-s32.sh --go`, reinicio coordinado con la sesión BT, carga e7i2c → e3 + driver LPI → e8b **con la topología normal** (todo como siempre, 0 oops), después `UKE-tplg.bin` ← cadena (`f848f629…`; original `c3ff8ed1…` en `UKE-tplg.orig.bin`) y e8b recargada (sondea sin avisos). `test-chain.sh` con **`uke_fs_play=N` (amps sin tocar)**:
- **a** (cadena MFC→SAL→LOG→TDM_SINK con parámetros a 0, 16 bit/2 canales): `aplay rc 0`, ADSP running.
- **b** (+`uke_tdm_chain_bits=32`): `aplay rc 0`, ADSP running.
- **c** (+`uke_tdm_chain_chan=4`, mapa {1,2,8,9}; slot_mask 0xF): `aplay rc 0`, ADSP running.
Vigía y capturas vivos, 0 oops/faults, parámetros restaurados a 0 tras cada etapa. **A diferencia del S24, esta cadena a 32 bit/4 canales NO tumba el ADSP**: el grafo con MFC+SAL sí es aceptado (el MFC/SAL absorben la conversión de formato).
Estado de la tablet ahora: topología de cadena instalada como `UKE-tplg.bin` (original guardada), e8b cargada, `uke_fs_play=N`.
**Siguiente: etapa d** (amps habilitados, vol 0xF3, tono −18 dBFS, 2 s; el dueño escucha a 20-30 cm).

## Etapa d EJECUTADA (MEDIDO, 10:21): cadena a 32 bit/4 canales con amps habilitados — **sigue sin oírse nada**
`test-chain.sh d`: cadena MFC→SAL→LOG→TDM_SINK con `uke_tdm_chain_bits=32` y `uke_tdm_chain_chan=4`, `uke_fs_play=Y`, vol 0xF3, tono 1 kHz −18 dBFS 2 s: `aplay rc 0`, `amps habilitados: rc 0`, ADSP running, 0 oops; **el dueño no oyó nada a 20-30 cm**. Restaurado todo: `UKE-tplg.bin` = original (`c3ff8ed1…`), e8b recargada, parámetros a 0, `uke_fs_play=N`.
**Conclusión:** la cadena de Android (MFC→SAL, 32 bit, 4 canales, mapa {1,2,8,9}) no cambia el resultado. Con los 4 amps habilitados, con reloj detectado, con formato/slots/carril/ancho de dato variados y con nivel hasta −18 dBFS a vol 0xF3, **no hay sonido**. Lo que queda no se puede deducir desde Linux sin una referencia:
1. **Comparar con Android funcionando** (volcar los registros de los amps con sonido real y la configuración del grafo en uso): requiere arrancar Android (ranura/flash a mano del dueño).
2. El camino de **retorno V/I** (`TDM-LPAIF_VA-TX-PRIMARY`, SPLITTER en la cadena): los amps con protección podrían quedar silenciados sin realimentación (INFERIDO, sin evidencia).
3. Condiciones de **hardware** no vistas desde Linux (alimentación del boost/VBAT de los amps, un GPIO de habilitación distinto del reset, p. ej. «speaker enable»): el DT de Android las define; hay estados `spkr_1_sd_n`/`wsa_spkr_en*` (gpio98 principal y gpio13 LPI) sin consumidor conocido en esta placa.
