# AUDIO — E8 diagnóstico 2: ¿conmutan los pads TDM? ¿qué slot lee cada amp? Preparado en el PC — 18-oct-2026

**No se tocó la tablet.** Situación medida: los 4 FS19xx están vivos, con reloj aparente y habilitados (cambian de estado, ver `AUDIO-E8-DIAG-RESULTADO`), pero **no suena nada ni a 0xC0, 0xE0 ni 0xF3** con el tono de 1 kHz a −40 dBFS. El volumen deja de ser la explicación.

## Lo ya descartado o aclarado
- **`data_oe` (ACDB = 1):** en `pcm_tdm_api.h` `ctrl_data_out_enable` solo indica si el bloque «comparte la señal data-out con otros masters» (0/1); **no es una máscara de línea**. 1 es el valor correcto; no es hipótesis.
- Pines: el DT de Android define `lpi_tdm1_{sck,ws,sd0,sd1}` = **gpio6/7/8/9, `func2`** (idénticas a las nuestras: `i2s1_clk/ws/data/data`), y también `quat_tdm_*` en gpio0-5 (4 líneas de datos) y `lpi_tdm2..4`. **No se ha podido demostrar cuál de los juegos usa el backend `TDM-LPAIF_VA-RX-PRIMARY`** (el nodo `sound` de Android no referencia los pinctrl TDM). gpio6-9 sigue siendo la mejor apuesta (por nombre «TDM1» y por tener 2 líneas de datos), pero **es la hipótesis principal a verificar**.
- Slots: en el preset, `reg 0x1A` por amp vale `0x00/0x11/0x22/0x33` (0x35/0x37/0x34/0x36) y `info[16]` = 8/2/4/1; ambos parecen **selección de slot** (cada amp lee un slot distinto). Con el PCM de 2 canales (`slot_mask = 0x3`) solo recibirían datos los amps cuyo slot sea 0 ó 1; **no explica el silencio total**, pero sí que haría falta 4 canales para tocar los 4.

## Qué se ha preparado (todo en el PC)
| Pieza | Para qué |
|---|---|
| `e3c/uke_lpi_rd.ko` (nuevo sha `104c376d…`) con `uke_lpi_samples=N` | **Solo lectura**: N lecturas seguidas de `VALUE` (offset 0x04) de un pin LPI; cuenta unos y transiciones del bit IN. Un pad que conmuta a MHz (BCLK gpio6, WS gpio7, DATA gpio8/9 con el tono) da ≈50 % de unos y muchas transiciones; uno estático da 0 ó N unos y 0 transiciones |
| `e3c/sample-pins.sh` | En la tablet: PCM de 48 kHz sonando (con **`uke_fs_play=N`: los amps NO se tocan**), muestrea gpio6..9 ×5000 lecturas. Aborta si `uke_fs_play` no es `N` |
| `topology/UKE.m4` con `UKE_CH` (defecto 2: el `UKE-tplg.bin` normal **no cambia**, sha `c3ff8ed1…`) y `build.sh` | Genera `firmware/qcom/sm8650/UKE-tplg-4ch.bin` (MultiMedia1 con 4 canales) para el test de mapa canal→slot→altavoz |
| `e4c/make-wav4.sh` | WAV de 4 canales, 48 kHz, S16, tono 1 kHz a −40 dBFS **solo en un canal cada vez** (canal k en [2k, 2k+1.5) s; 8 s) |
| `fs19xx/deploy-4ch.sh` | Copia **solo ficheros**: `UKE-tplg-4ch.bin` (junto a la normal) y `/root/uke-4ch-seq-40dbfs.wav` |

## Procedimiento propuesto (cada paso con autorización; vigía + doble captura; ACM un lector)
- **D2-0** `e3c/deploy.sh --go` (nuevo `uke_lpi_rd.ko`) y `fs19xx/deploy-4ch.sh --go` (topología 4ch + WAV): solo ficheros.
- **D2-1 (solo lectura de pads)**: `bash -s < e3c/sample-pins.sh`. **Interpretación:** *BCLK/WS conmutan* ⇒ el LPAIF saca reloj por gpio6/7: el fallo está en el lado del amp (datos/slot/configuración); *estáticos* ⇒ el pinmux/LPAIF no está sacando la señal por esos pines (¿otro juego de pines? ¿falta una configuración del PRIMARY TDM en el ADSP?).
- **D2-2 (test 4 canales, solo si D2-1 muestra conmutación)**: copia de seguridad de `UKE-tplg.bin`, sustituirla por la de 4 canales, `rmmod uke_audio_e8b` + `insmod uke_audio_e8b` (≈15 s de timeouts del APM), `uke_fs_play=1`, vol 0xF3, `aplay -D hw:UKE,0 /root/uke-4ch-seq-40dbfs.wav` (8 s; **el dueño anota qué altavoz suena en cada segundo**), `uke_fs_play=N`; reversa: restaurar el fichero y recargar la tarjeta.
- **D2-3**: según el resultado, probar los otros juegos de pines (quat gpio0-5, tdm2-4) con un overlay de pines alternativo, o revisar la configuración del TDM en el ADSP (p. ej. `PARAM_ID_TDM_INTF_CFG` por lane, relojes PRM del TDM).

## Riesgos
D2-1: solo lecturas MMIO (ya medidas OK); 4 `insmod` rápidos, bajo. D2-2: el volumen sigue en 0xF3 pero el contenido está a −40 dBFS en un solo canal (seguro); el cambio de topología puede dejar la tarjeta sin sondear si el ADSP rechaza el grafo de 4 canales (se restaura el fichero original; sin riesgo físico). Sin sensor térmico en los amps: tests ≤ 8 s, el dueño atento al calor/ruido.

## D2-0 y D2-1 EJECUTADOS (MEDIDO, 23:35) — los pads gpio6-9 NO conmutan con el PCM en marcha
- D2-0: `e3c/deploy.sh --go` (`uke_lpi_rd.ko` sha `104c376d…`) y `fs19xx/deploy-4ch.sh --go` (`UKE-tplg-4ch.bin` `45c3713a…` junto a la normal `c3ff8ed1…` intacta; WAV `6a86954d…`): solo ficheros.
- D2-1 (`uke_fs_play=N`, amps sin tocar, vigía y capturas vivos, 0 oops): con **`state: RUNNING` comprobado antes y después de cada muestreo** (PCM de `/dev/zero`, 48 kHz): `VALUE(gpio6) / gpio7 / gpio8 / gpio9: n=5000 unos=0 transiciones=0` (gpio6 y gpio7 repetidos: igual). `CFG(gpio6..8)=0x6c8`, `CFG(gpio9)=0x6c9` (siguen en función 2). Un primer muestreo con WAV en bucle (estado `DRAINING` en el momento) dio lo mismo.
- **Lectura:** ni el BCLK (gpio6) ni el WS (gpio7) conmutan en los pines mientras el ADSP reporta el backend TDM en marcha (el `hw_ptr` avanza). **No sale reloj por gpio6-9.** Esto explica el silencio (los amps no reciben señal) y descarta, por ahora, slots/volumen como causa principal. Caveat: la validez de leer `VALUE.IN` con la función alternativa activa no está comprobada con un pad que se sepa que conmuta.

## Nueva hipótesis principal (INFERIDO, comprobable sin riesgo físico): falta el voto de HW del LPASS durante el streaming
En Android el nodo `sound` lleva `clocks = <… 0>, clock-names = "lpass_audio_hw_vote"` y `qcom,mi2s-tdm-is-hw-vote-needed = <1 …>` (los TDM necesitan el voto HW). En nuestra pila los votos `LPASS_HW_MACRO/DCODEC` los toma el driver LPI **solo mientras accede a un pin** y los suelta a los 100 ms (autosuspend): **durante el stream están a 0**. Sin ese voto el reloj/pad del LPAIF puede no sacar BCLK aunque el DMA avance. (Mis lecturas de D2-1 SÍ tuvieron los votos activos mientras duraba cada `insmod`, pero el voto lo suelta el driver al terminar cada lectura y el LPAIF arranca sin él; el ADSP puede no habilitar la salida si el voto falta al abrir el grafo.)
- **Prueba D3-1 (barata y reversible):** `echo on > /sys/devices/platform/soc/6e80000.pinctrl/power/control` (fuerza ambos votos PRM, como en E3b), luego **reabrir** el stream (el grafo se abre al `aplay`), muestrear gpio6-9 y, si conmutan, repetir el WAV (amps con `uke_fs_play=1`, vol 0xF3). Reversa: `echo auto`.
- Si no conmutaran ni así: D3-2 = probar otros juegos de pines (quat gpio0-5, tdm2-4) y/o revisar la configuración del TDM en el ADSP (relojes IBIT por PRM, `PARAM_ID_TDM_INTF_CFG`).

## D3-1 EJECUTADO (MEDIDO, 23:38) — hipótesis del voto HW REFUTADA
`echo on > …/6e80000.pinctrl/power/control` (runtime `active`, `LPASS_HW_MACRO` y `LPASS_HW_DCODEC` con enable_count 1 durante todo el stream) + PCM de `/dev/zero` en `RUNNING`: `VALUE(gpio6/7/8/9): n=5000 unos=0 transiciones=0`. Los pads siguen sin conmutar con los votos mantenidos. `echo auto` aplicado (runtime `suspended`, votos a 0), `uke_fs_play=N` todo el rato, 0 oops/faults. No se pasó al WAV (condición «si conmutan» no cumplida).

## Qué queda por descartar (ordenado por coste/riesgo)
1. **Validar el método de medida** (barato, escribe solo en un pin sin uso): con un pin LPI libre (p. ej. gpio13) en función GPIO como salida, alternar `VALUE.OUT` y comprobar que `VALUE.IN` lo sigue con `uke_lpi_rd`. Si `IN` no siguiera, todas las lecturas anteriores serían engañosas (en función alternativa el pad podría no reflejarse en `IN`).
2. **Reloj de bit del TDM por PRM**: `q6prm_set_lpass_clock()` existe pero la tabla de `q6prm-clocks` solo trae MI2S; los IDs de TDM (`LPASS_CLK_ID_PRI_TDM_IBIT` = 35 en los bindings del puerto; el ID PRM exacto NO verificado) no se piden nunca. En Android `mi2s-tdm-is-hw-vote-needed = 1` y `tdm-clk-attribute = 4`. Un módulo mínimo podría pedir ese reloj (6,144 MHz) antes del stream; un ID erróneo solo devolvería error de PRM.
3. **Otros juegos de pines**: `quat_tdm` = gpio0-5 (func2/3, 4 líneas de datos), `lpi_tdm2..4`; un overlay de pines alternativo (escrituras en pines hoy sin uso) y muestreo.
4. **Lado ADSP**: revisar si falta algún parámetro del TDM (`PARAM_ID_TDM_LANE`/lane, power mode, clocks del subgrafo en el ACDB distintos de los que enviamos).
Mi recomendación: 1 → 2 → 3.
